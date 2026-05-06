#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ARTIFACT_ROOT="${1:-${TMPDIR:-/tmp}/kuyu-learning-readiness-$(date +%Y%m%d-%H%M%S)}"
DERIVED_DATA="${KUYU_XCODE_DERIVED_DATA:-$ARTIFACT_ROOT/DerivedData}"
DESTINATION="${KUYU_XCODE_DESTINATION:-platform=macOS}"
CONFIGURATION="${KUYU_XCODE_CONFIGURATION:-Debug}"
TIMEOUT_SECONDS="${KUYU_LEARNING_PREFLIGHT_TIMEOUT_SECONDS:-900}"
RUN_TESTS="${KUYU_LEARNING_PREFLIGHT_RUN_TESTS:-0}"
TEST_TIMEOUT_SECONDS="${KUYU_XCODE_TEST_TIMEOUT_SECONDS:-60}"
MIN_FREE_GB="${KUYU_LEARNING_MIN_FREE_GB:-20}"

TASK="${KUYU_LEARNING_TASK:-lift}"
SUITES="${KUYU_LEARNING_SUITES:-6}"
EPISODES="${KUYU_LEARNING_PREFLIGHT_EPISODES:-1}"
WORKERS="${KUYU_LEARNING_WORKERS:-1}"
MODEL_DESCRIPTOR="${KUYU_LEARNING_MODEL:-}"
SOURCE_CHECKPOINT="${KUYU_LEARNING_SOURCE_CHECKPOINT:-}"
BOOTSTRAP_SUITE="${KUYU_LEARNING_BOOTSTRAP_SUITE:-$(python3 - "$SUITES" <<'PY'
import sys

suites = [item.strip() for item in sys.argv[1].split(",") if item.strip()]
print(suites[0] if suites else "6")
PY
)}"
BOOTSTRAP_EPISODES="${KUYU_LEARNING_BOOTSTRAP_EPISODES:-$EPISODES}"
BOOTSTRAP_SEQUENCE="${KUYU_LEARNING_BOOTSTRAP_SEQUENCE:-16}"
BOOTSTRAP_EPOCHS="${KUYU_LEARNING_BOOTSTRAP_EPOCHS:-1}"
BOOTSTRAP_MAX_BATCHES="${KUYU_LEARNING_BOOTSTRAP_MAX_BATCHES:-1}"
BOOTSTRAP_LR="${KUYU_LEARNING_BOOTSTRAP_LR:-0.001}"

mkdir -p "$ARTIFACT_ROOT"

run_with_timeout() {
  python3 - "$TIMEOUT_SECONDS" "$@" <<'PY'
import subprocess
import sys

timeout = int(sys.argv[1])
command = sys.argv[2:]
sys.exit(subprocess.run(command, timeout=timeout).returncode)
PY
}

run_allowing_harness_reject() {
  set +e
  run_with_timeout "$@"
  local status=$?
  set -e
  return "$status"
}

run_kuyu_plain() {
  run_with_timeout "$KUYU_BIN" "$@"
}

run_kuyu_with_model() {
  if [[ -n "$MODEL_DESCRIPTOR" ]]; then
    run_with_timeout "$KUYU_BIN" "$@" --model "$MODEL_DESCRIPTOR"
  else
    run_with_timeout "$KUYU_BIN" "$@"
  fi
}

run_kuyu_allowing_harness_reject_with_model() {
  if [[ -n "$MODEL_DESCRIPTOR" ]]; then
    run_allowing_harness_reject "$KUYU_BIN" "$@" --model "$MODEL_DESCRIPTOR"
  else
    run_allowing_harness_reject "$KUYU_BIN" "$@"
  fi
}

available_kb="$(df -Pk "$ARTIFACT_ROOT" | awk 'NR == 2 { print $4 }')"
required_kb="$(python3 - "$MIN_FREE_GB" <<'PY'
import math
import sys

gb = float(sys.argv[1])
print(math.ceil(gb * 1024 * 1024))
PY
)"
if (( available_kb < required_kb )); then
  echo "[learning-readiness] insufficient free disk: availableKB=$available_kb requiredKB=$required_kb" >&2
  exit 1
fi

if [[ -n "$MODEL_DESCRIPTOR" && ! -f "$MODEL_DESCRIPTOR" ]]; then
  echo "[learning-readiness] missing model descriptor: $MODEL_DESCRIPTOR" >&2
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
  echo "[learning-readiness] missing executable: $KUYU_BIN" >&2
  exit 1
fi

run_kuyu_with_model check-kuyu-regression \
  --controller teacherBaseline \
  --tasks "$TASK" \
  --suites "$SUITES" \
  --episodes "$EPISODES" \
  --artifact-root "$ARTIFACT_ROOT/teacher-regression"

if [[ -n "$SOURCE_CHECKPOINT" ]]; then
  CURRENT_CHECKPOINT="$SOURCE_CHECKPOINT"
  if [[ ! -f "$CURRENT_CHECKPOINT/model.json" || ! -f "$CURRENT_CHECKPOINT/core.safetensors" || ! -f "$CURRENT_CHECKPOINT/reflex.safetensors" ]]; then
    echo "[learning-readiness] incomplete source checkpoint: $CURRENT_CHECKPOINT" >&2
    exit 1
  fi
  run_kuyu_allowing_harness_reject_with_model check-kuyu-regression \
    --controller manasMLX \
    --snapshot "$CURRENT_CHECKPOINT" \
    --tasks "$TASK" \
    --suites "$SUITES" \
    --episodes "$EPISODES" \
    --artifact-root "$ARTIFACT_ROOT/source-regression" || true
else
  run_kuyu_with_model rollout \
    --controller teacherBaseline \
    --task "$TASK" \
    --suite "$BOOTSTRAP_SUITE" \
    --episodes "$BOOTSTRAP_EPISODES" \
    --workers "$WORKERS" \
    --export-dataset "$ARTIFACT_ROOT/bootstrap-dataset"

  run_kuyu_plain train-manas-core \
    --dataset "$ARTIFACT_ROOT/bootstrap-dataset" \
    --output "$ARTIFACT_ROOT/bootstrap-checkpoint" \
    --sequence "$BOOTSTRAP_SEQUENCE" \
    --epochs "$BOOTSTRAP_EPOCHS" \
    --max-batches "$BOOTSTRAP_MAX_BATCHES" \
    --lr "$BOOTSTRAP_LR" \
    --no-aux
  CURRENT_CHECKPOINT="$ARTIFACT_ROOT/bootstrap-checkpoint"
fi

if [[ ! -f "$CURRENT_CHECKPOINT/model.json" || ! -f "$CURRENT_CHECKPOINT/core.safetensors" || ! -f "$CURRENT_CHECKPOINT/reflex.safetensors" ]]; then
  echo "[learning-readiness] incomplete ready checkpoint: $CURRENT_CHECKPOINT" >&2
  exit 1
fi

python3 - "$ARTIFACT_ROOT" "$CURRENT_CHECKPOINT" "$KUYU_BIN" "$TASK" "$SUITES" "$EPISODES" "$WORKERS" "$available_kb" "$required_kb" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
checkpoint = pathlib.Path(sys.argv[2])
binary = pathlib.Path(sys.argv[3])
task = sys.argv[4]
suites = sys.argv[5]
episodes = int(sys.argv[6])
workers = int(sys.argv[7])
available_kb = int(sys.argv[8])
required_kb = int(sys.argv[9])

def load_json(path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)

teacher = load_json(root / "teacher-regression" / "kuyu-regression-summary.json")
if not teacher.get("environmentReady") or not teacher.get("allPassed"):
    raise SystemExit("teacher regression did not pass readiness")

source_regression_path = root / "source-regression" / "kuyu-regression-summary.json"
source_regression = load_json(source_regression_path) if source_regression_path.exists() else None
if source_regression is not None and not source_regression.get("environmentReady"):
    raise SystemExit("source checkpoint regression environment was not ready")

for filename in ["model.json", "core.safetensors", "reflex.safetensors"]:
    if not (checkpoint / filename).exists():
        raise SystemExit(f"ready checkpoint missing file: {filename}")

summary = {
    "ready": True,
    "artifactRoot": str(root),
    "kuyuBinary": str(binary),
    "task": task,
    "suites": suites,
    "episodes": episodes,
    "workers": workers,
    "availableDiskKB": available_kb,
    "requiredDiskKB": required_kb,
    "teacherRegressionAccepted": bool(teacher.get("allPassed")),
    "sourceRegressionAccepted": (
        source_regression.get("allPassed")
        if source_regression is not None
        else None
    ),
    "readyCheckpoint": str(checkpoint),
}
summary_path = root / "learning-readiness-summary.json"
summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"[learning-readiness] summary={summary_path}")
print(f"[learning-readiness] ready=true checkpoint={checkpoint}")
PY
