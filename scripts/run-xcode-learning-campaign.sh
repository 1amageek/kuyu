#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ARTIFACT_ROOT="${1:-${TMPDIR:-/tmp}/kuyu-learning-campaign-$(date +%Y%m%d-%H%M%S)}"
DERIVED_DATA="${KUYU_XCODE_DERIVED_DATA:-$ARTIFACT_ROOT/DerivedData}"
DESTINATION="${KUYU_XCODE_DESTINATION:-platform=macOS}"
CONFIGURATION="${KUYU_XCODE_CONFIGURATION:-Debug}"
TIMEOUT_SECONDS="${KUYU_LEARNING_TIMEOUT_SECONDS:-1200}"
RUN_TESTS="${KUYU_LEARNING_RUN_TESTS:-0}"
TEST_TIMEOUT_SECONDS="${KUYU_XCODE_TEST_TIMEOUT_SECONDS:-60}"
MIN_FREE_GB="${KUYU_LEARNING_MIN_FREE_GB:-20}"
LOCK_PATH="${KUYU_LEARNING_LOCK_PATH:-${TMPDIR:-/tmp}/kuyu-learning-campaign.lock}"
RESUME="${KUYU_LEARNING_RESUME:-0}"
RESOURCE_SAMPLE_SECONDS="${KUYU_LEARNING_RESOURCE_SAMPLE_SECONDS:-30}"

TASK="${KUYU_LEARNING_TASK:-lift}"
SUITES="${KUYU_LEARNING_SUITES:-6}"
EPISODES="${KUYU_LEARNING_EPISODES:-1}"
WORKERS="${KUYU_LEARNING_WORKERS:-1}"
POPULATION="${KUYU_LEARNING_POPULATION:-4}"
GENERATIONS="${KUYU_LEARNING_GENERATIONS:-5}"
ELITE_COUNT="${KUYU_LEARNING_ELITE_COUNT:-1}"
CANDIDATE_EVALUATION_CONCURRENCY="${KUYU_LEARNING_CANDIDATE_EVALUATION_CONCURRENCY:-1}"
VARIATION="${KUYU_LEARNING_VARIATION:-gaussian}"
SEARCH_STRATEGY="${KUYU_LEARNING_SEARCH_STRATEGY:-qualityDiversity}"
MUTATION_RATE="${KUYU_LEARNING_MUTATION_RATE:-0.08}"
MUTATION_NOISE_SCALE="${KUYU_LEARNING_MUTATION_NOISE_SCALE:-0.01}"
SEEDS_CSV="${KUYU_LEARNING_SEEDS:-}"
SEED_COUNT="${KUYU_LEARNING_SEED_COUNT:-3}"
MODEL_DESCRIPTOR="${KUYU_LEARNING_MODEL:-}"
SOURCE_CHECKPOINT="${KUYU_LEARNING_SOURCE_CHECKPOINT:-}"
MIN_REWARD_AVERAGE="${KUYU_LEARNING_MIN_REWARD_AVERAGE:-}"
MIN_INCUMBENT_IMPROVEMENT="${KUYU_LEARNING_MIN_INCUMBENT_IMPROVEMENT:-0}"
MIN_NOVELTY_SCORE="${KUYU_LEARNING_MIN_NOVELTY_SCORE:-}"
TIER="${KUYU_LEARNING_TIER:-tier1}"
CUT_PERIOD="${KUYU_LEARNING_CUT_PERIOD:-2}"
KP="${KUYU_LEARNING_KP:-0.35}"
KD="${KUYU_LEARNING_KD:-0.08}"
YAW_DAMPING="${KUYU_LEARNING_YAW_DAMPING:-0.04}"
HOVER_SCALE="${KUYU_LEARNING_HOVER_SCALE:-1.0}"
NO_QUALITY_GATE="${KUYU_LEARNING_NO_QUALITY_GATE:-0}"

run_with_timeout() {
  python3 - "$TIMEOUT_SECONDS" "$@" <<'PY'
import subprocess
import sys

timeout = int(sys.argv[1])
command = sys.argv[2:]
sys.exit(subprocess.run(command, timeout=timeout).returncode)
PY
}

validate_flag() {
  local name="$1"
  local value="$2"
  if [[ "$value" != "0" && "$value" != "1" ]]; then
    echo "[learning-campaign] $name must be 0 or 1: $value" >&2
    exit 1
  fi
}

validate_flag "KUYU_LEARNING_RUN_TESTS" "$RUN_TESTS"
validate_flag "KUYU_LEARNING_RESUME" "$RESUME"
validate_flag "KUYU_LEARNING_NO_QUALITY_GATE" "$NO_QUALITY_GATE"

if [[ "$NO_QUALITY_GATE" == "1" ]]; then
  echo "[learning-campaign] KUYU_LEARNING_NO_QUALITY_GATE is not allowed for learning campaigns" >&2
  exit 1
fi

if [[ -n "$SEEDS_CSV" && -n "${KUYU_LEARNING_SEED_COUNT:-}" ]]; then
  echo "[learning-campaign] KUYU_LEARNING_SEEDS and KUYU_LEARNING_SEED_COUNT cannot both be set" >&2
  exit 1
fi

if [[ "$RESUME" == "1" ]]; then
  echo "[learning-campaign] resume is owned by Swift artifacts and is not enabled in this launcher yet" >&2
  exit 1
fi

if [[ -z "$SOURCE_CHECKPOINT" ]]; then
  echo "[learning-campaign] KUYU_LEARNING_SOURCE_CHECKPOINT is required for task-specific campaigns" >&2
  exit 1
fi

if [[ -e "$ARTIFACT_ROOT" ]]; then
  if [[ ! -d "$ARTIFACT_ROOT" ]]; then
    echo "[learning-campaign] artifact root is not a directory: $ARTIFACT_ROOT" >&2
    exit 1
  fi
  if [[ -n "$(find "$ARTIFACT_ROOT" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "[learning-campaign] refusing to reuse non-empty artifact root: $ARTIFACT_ROOT" >&2
    exit 1
  fi
fi
mkdir -p "$ARTIFACT_ROOT"

mkdir -p "$(dirname "$LOCK_PATH")"
if ! mkdir "$LOCK_PATH" 2>/dev/null; then
  lock_pid="$(cat "$LOCK_PATH/pid" 2>/dev/null || true)"
  lock_artifact_root="$(cat "$LOCK_PATH/artifact-root" 2>/dev/null || true)"
  if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
    echo "[learning-campaign] another campaign is running: pid=$lock_pid artifactRoot=$lock_artifact_root lock=$LOCK_PATH" >&2
    exit 1
  fi
  echo "[learning-campaign] removing stale campaign lock: $LOCK_PATH" >&2
  rm -rf "$LOCK_PATH"
  mkdir "$LOCK_PATH"
fi
printf "%s\n" "$$" > "$LOCK_PATH/pid"
printf "%s\n" "$ARTIFACT_ROOT" > "$LOCK_PATH/artifact-root"
trap 'rm -rf "$LOCK_PATH"' EXIT

available_kb="$(df -Pk "$ARTIFACT_ROOT" | awk 'NR == 2 { print $4 }')"
required_kb="$(python3 - "$MIN_FREE_GB" <<'PY'
import math
import sys

gb = float(sys.argv[1])
print(math.ceil(gb * 1024 * 1024))
PY
)"
if (( available_kb < required_kb )); then
  echo "[learning-campaign] insufficient free disk: availableKB=$available_kb requiredKB=$required_kb" >&2
  exit 1
fi

if [[ ! -f "$SOURCE_CHECKPOINT/model.json" || ! -f "$SOURCE_CHECKPOINT/core.safetensors" || ! -f "$SOURCE_CHECKPOINT/reflex.safetensors" ]]; then
  echo "[learning-campaign] incomplete source checkpoint: $SOURCE_CHECKPOINT" >&2
  exit 1
fi

if [[ -n "$MODEL_DESCRIPTOR" && ! -f "$MODEL_DESCRIPTOR" ]]; then
  echo "[learning-campaign] missing model descriptor: $MODEL_DESCRIPTOR" >&2
  exit 1
fi

if [[ "$RUN_TESTS" == "1" ]]; then
  run_with_timeout xcodebuild test \
    -scheme kuyu \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -maximum-test-execution-time-allowance "$TEST_TIMEOUT_SECONDS"
else
  run_with_timeout xcodebuild build \
    -scheme kuyu \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA"
fi

KUYU_BIN="$DERIVED_DATA/Build/Products/$CONFIGURATION/kuyu"
if [[ ! -x "$KUYU_BIN" ]]; then
  echo "[learning-campaign] missing executable: $KUYU_BIN" >&2
  exit 1
fi

ARGS=(
  run-learning-campaign
  --task "$TASK"
  --source-checkpoint "$SOURCE_CHECKPOINT"
  --artifact-root "$ARTIFACT_ROOT"
  --population "$POPULATION"
  --generations "$GENERATIONS"
  --elite-count "$ELITE_COUNT"
  --workers "$WORKERS"
  --candidate-evaluation-concurrency "$CANDIDATE_EVALUATION_CONCURRENCY"
  --suites "$SUITES"
  --episodes "$EPISODES"
  --tier "$TIER"
  --cut-period "$CUT_PERIOD"
  --variation "$VARIATION"
  --search-strategy "$SEARCH_STRATEGY"
  --mutation-rate "$MUTATION_RATE"
  --mutation-noise-scale "$MUTATION_NOISE_SCALE"
  --min-incumbent-improvement "$MIN_INCUMBENT_IMPROVEMENT"
  --resource-sample-seconds "$RESOURCE_SAMPLE_SECONDS"
  --kp "$KP"
  --kd "$KD"
  --yaw-damping "$YAW_DAMPING"
  --hover-scale "$HOVER_SCALE"
)

if [[ -n "$SEEDS_CSV" ]]; then
  ARGS+=(--seeds "$SEEDS_CSV")
else
  ARGS+=(--seed-count "$SEED_COUNT")
fi

if [[ -n "$MODEL_DESCRIPTOR" ]]; then
  ARGS+=(--model "$MODEL_DESCRIPTOR")
fi
if [[ -n "$MIN_REWARD_AVERAGE" ]]; then
  ARGS+=(--min-reward-average "$MIN_REWARD_AVERAGE")
fi
if [[ -n "$MIN_NOVELTY_SCORE" ]]; then
  ARGS+=(--min-novelty-score "$MIN_NOVELTY_SCORE")
fi
if [[ "$NO_QUALITY_GATE" == "1" ]]; then
  ARGS+=(--no-quality-gate)
fi

echo "[learning-campaign] build=$KUYU_BIN"
echo "[learning-campaign] artifactRoot=$ARTIFACT_ROOT"
echo "[learning-campaign] sourceCheckpoint=$SOURCE_CHECKPOINT"
run_with_timeout "$KUYU_BIN" "${ARGS[@]}"
run_with_timeout "$KUYU_BIN" validate-learning-campaign --artifact-root "$ARTIFACT_ROOT"
