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
VERIFY_PARENT_TASK="${KUYU_LEARNING_VERIFY_PARENT_TASK:-1}"

TASK="${KUYU_LEARNING_TASK:-lift}"
case "$TASK" in
  lift|singleLift)
    DEFAULT_REQUIRE_SOURCE_POLICY_PASS=1
    ;;
  *)
    DEFAULT_REQUIRE_SOURCE_POLICY_PASS=0
    ;;
esac
REQUIRE_SOURCE_POLICY_PASS="${KUYU_LEARNING_REQUIRE_SOURCE_POLICY_PASS:-$DEFAULT_REQUIRE_SOURCE_POLICY_PASS}"
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
BOOTSTRAP_SEQUENCE="${KUYU_LEARNING_BOOTSTRAP_SEQUENCE:-16}"
case "$TASK" in
  lift)
    DEFAULT_BOOTSTRAP_EPISODES=13
    DEFAULT_BOOTSTRAP_EPOCHS=3
    DEFAULT_BOOTSTRAP_MAX_BATCHES=32
    ;;
  singleLift)
    DEFAULT_BOOTSTRAP_EPISODES=13
    DEFAULT_BOOTSTRAP_EPOCHS=3
    DEFAULT_BOOTSTRAP_MAX_BATCHES=32
    ;;
  *)
    DEFAULT_BOOTSTRAP_EPISODES="$EPISODES"
    DEFAULT_BOOTSTRAP_EPOCHS=1
    DEFAULT_BOOTSTRAP_MAX_BATCHES=1
    ;;
esac
BOOTSTRAP_EPISODES="${KUYU_LEARNING_BOOTSTRAP_EPISODES:-$DEFAULT_BOOTSTRAP_EPISODES}"
BOOTSTRAP_EPOCHS="${KUYU_LEARNING_BOOTSTRAP_EPOCHS:-$DEFAULT_BOOTSTRAP_EPOCHS}"
BOOTSTRAP_MAX_BATCHES="${KUYU_LEARNING_BOOTSTRAP_MAX_BATCHES:-$DEFAULT_BOOTSTRAP_MAX_BATCHES}"
BOOTSTRAP_LR="${KUYU_LEARNING_BOOTSTRAP_LR:-0.0001}"
BOOTSTRAP_REPAIR_ATTEMPTS="${KUYU_LEARNING_BOOTSTRAP_REPAIR_ATTEMPTS:-$([[ "$TASK" == "singleLift" ]] && printf "2" || printf "0")}"
BOOTSTRAP_MLX_SEED="${KUYU_LEARNING_BOOTSTRAP_MLX_SEED:-$([[ "$TASK" == "singleLift" ]] && printf "11" || printf "")}"
BOOTSTRAP_BIAS_DELTAS="${KUYU_LEARNING_BOOTSTRAP_BIAS_DELTAS:-$([[ "$TASK" == "singleLift" ]] && printf -- "-0.016,-0.0152,-0.0148,-0.01465,-0.0146,-0.01455,-0.0145,-0.0144,-0.0143,-0.0142,-0.0140,-0.0138,-0.0132,-0.0125,-0.0115,-0.0105,-0.0095,-0.0085,-0.0075,-0.0065" || printf "")}"

if [[ "$VERIFY_PARENT_TASK" != "0" && "$VERIFY_PARENT_TASK" != "1" ]]; then
  echo "[learning-readiness] KUYU_LEARNING_VERIFY_PARENT_TASK must be 0 or 1: $VERIFY_PARENT_TASK" >&2
  exit 1
fi
if [[ "$REQUIRE_SOURCE_POLICY_PASS" != "0" && "$REQUIRE_SOURCE_POLICY_PASS" != "1" ]]; then
  echo "[learning-readiness] KUYU_LEARNING_REQUIRE_SOURCE_POLICY_PASS must be 0 or 1: $REQUIRE_SOURCE_POLICY_PASS" >&2
  exit 1
fi

mkdir -p "$ARTIFACT_ROOT"

write_readiness_summary() {
  local ready="$1"
  local reason="${2:-}"
  local checkpoint="${CURRENT_CHECKPOINT:-}"
  local binary="${KUYU_BIN:-}"
  python3 - "$ARTIFACT_ROOT" "$checkpoint" "$binary" "$TASK" "$SUITES" "$EPISODES" "$WORKERS" "$available_kb" "$required_kb" "$REQUIRE_SOURCE_POLICY_PASS" "$ready" "$reason" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
checkpoint = pathlib.Path(sys.argv[2]) if sys.argv[2] else None
binary = pathlib.Path(sys.argv[3]) if sys.argv[3] else None
task = sys.argv[4]
suites = sys.argv[5]
episodes = int(sys.argv[6])
workers = int(sys.argv[7])
available_kb = int(sys.argv[8])
required_kb = int(sys.argv[9])
strict_source_required = sys.argv[10] == "1"
ready = sys.argv[11] == "true"
reason = sys.argv[12]

def load_json(path):
    if not path.exists():
        return None
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)

teacher = load_json(root / "teacher-regression" / "kuyu-regression-summary.json")
source_regression = load_json(root / "source-regression" / "kuyu-regression-summary.json")
ready_regression = load_json(root / "ready-regression" / "kuyu-regression-summary.json")
checkpoint_evaluation = load_json(root / "checkpoint-evaluation" / "checkpoint-evaluation.json")
bias_selection = load_json(root / "bootstrap-bias-calibration" / "bias-calibration-selection.json")

failure_reasons = []
if reason:
    failure_reasons.append(reason)
if teacher is None:
    failure_reasons.append("teacher-regression-missing")
elif not teacher.get("environmentReady"):
    failure_reasons.append("teacher-regression-environment-failed")
elif not teacher.get("allPassed"):
    failure_reasons.append("teacher-regression-failed")
if source_regression is not None and not source_regression.get("allPassed"):
    failure_reasons.append("source checkpoint regression did not pass readiness")
if ready_regression is not None:
    if not ready_regression.get("environmentReady"):
        failure_reasons.append("ready-regression-environment-failed")
    if not ready_regression.get("allPassed"):
        failure_reasons.append("ready checkpoint regression did not pass readiness")
        failure_reasons.extend(ready_regression.get("gateReport", {}).get("reasons", []))
elif task in {"lift", "singleLift"} and not ready:
    failure_reasons.append("ready-regression-missing")
if checkpoint_evaluation is not None:
    if not checkpoint_evaluation.get("policy" + "Passed", False):
        failure_reasons.append("checkpoint-evaluation-failed")
    for quality in checkpoint_evaluation.get("qualitySummary", []):
        if not quality.get("passed", False):
            failure_reasons.append("checkpoint-evaluation-task-quality-failed")
            for quality_reason in quality.get("failureReasons", []):
                failure_reasons.append(f"checkpoint-evaluation:{quality_reason}")
if bias_selection is not None and not bias_selection.get("selectedAccepted", False) and not ready:
    failure_reasons.append("bootstrap-bias-calibration-did-not-select-accepted-checkpoint")

ready = ready and not failure_reasons

summary = {
    "ready": ready,
    "artifactRoot": str(root),
    "kuyuBinary": str(binary) if binary is not None else None,
    "task": task,
    "suites": suites,
    "episodes": episodes,
    "workers": workers,
    "availableDiskKB": available_kb,
    "requiredDiskKB": required_kb,
    "teacherRegressionAccepted": (
        bool(teacher.get("allPassed")) if teacher is not None else None
    ),
    "sourceRegressionAccepted": (
        bool(source_regression.get("allPassed")) if source_regression is not None else None
    ),
    "readyRegressionAccepted": (
        bool(ready_regression.get("allPassed")) if ready_regression is not None else None
    ),
    "bootstrapRepairAttempts": int(__import__("os").environ.get("KUYU_LEARNING_BOOTSTRAP_REPAIR_ATTEMPTS", "2" if task == "singleLift" else "0")),
    "bootstrapBiasSelectionAccepted": (
        bool(bias_selection.get("selectedAccepted")) if bias_selection is not None else None
    ),
    "bootstrapBiasSelectedDelta": (
        bias_selection.get("selectedRawBiasDelta") if bias_selection is not None else None
    ),
    "strictSourcePolicyRequired": strict_source_required,
    "readyCheckpoint": str(checkpoint) if checkpoint is not None else None,
    "failureReasons": sorted(set(failure_reasons)),
}
summary_path = root / "learning-readiness-summary.json"
summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"[learning-readiness] summary={summary_path}")
if ready:
    print(f"[learning-readiness] ready=true checkpoint={checkpoint}")
else:
    print(f"[learning-readiness] ready=false reasons={'|'.join(summary['failureReasons'])}")
    raise SystemExit(1)
PY
}

finalize_readiness() {
  local status_code=$?
  if (( status_code != 0 )); then
    if [[ ! -f "$ARTIFACT_ROOT/learning-readiness-summary.json" ]]; then
      write_readiness_summary false "readiness-command-failed" || true
    fi
  fi
}
trap finalize_readiness EXIT

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

verify_parent_checkpoint_task() {
  local checkpoint="$1"
  if [[ "$VERIFY_PARENT_TASK" != "1" ]]; then
    return 0
  fi
  case "$TASK" in
    lift|singleLift)
      ;;
    *)
      return 0
      ;;
  esac
  local eval_root="$ARTIFACT_ROOT/checkpoint-evaluation"
  rm -rf "$eval_root"
  checkpoint_evaluation_args=(
    evaluate-manas-checkpoint
    --task "$TASK" \
    --checkpoint "$checkpoint" \
    --artifact-root "$eval_root"
  )
  if [[ "$REQUIRE_SOURCE_POLICY_PASS" == "1" ]]; then
    checkpoint_evaluation_args+=(--require-policy-pass)
  fi
  run_kuyu_with_model "${checkpoint_evaluation_args[@]}"
}

strict_checkpoint_passes() {
  local checkpoint="$1"
  local eval_root="$2"
  rm -rf "$eval_root"
  set +e
  run_kuyu_with_model evaluate-manas-checkpoint \
    --task "$TASK" \
    --checkpoint "$checkpoint" \
    --artifact-root "$eval_root" \
    --require-policy-pass
  local status=$?
  set -e
  return "$status"
}

verify_ready_checkpoint_regression() {
  local checkpoint="$1"
  case "$TASK" in
    lift|singleLift)
      ;;
    *)
      return 0
      ;;
  esac
  local regression_root="$ARTIFACT_ROOT/ready-regression"
  rm -rf "$regression_root"
  run_kuyu_with_model check-kuyu-regression \
    --controller manasMLX \
    --snapshot "$checkpoint" \
    --tasks "$TASK" \
    --suites "$SUITES" \
    --episodes "$EPISODES" \
    --workers "$WORKERS" \
    --artifact-root "$regression_root"
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
  bootstrap_rollout_args=(
    rollout
    --controller teacherBaseline
    --task "$TASK"
    --episodes "$BOOTSTRAP_EPISODES"
    --workers "$WORKERS"
    --export-dataset "$ARTIFACT_ROOT/bootstrap-dataset"
  )
  if [[ "$TASK" == "singleLift" ]]; then
    bootstrap_rollout_args+=(--training-suite)
  elif [[ "$TASK" != "lift" ]]; then
    bootstrap_rollout_args+=(--suite "$BOOTSTRAP_SUITE")
  fi
  run_kuyu_with_model "${bootstrap_rollout_args[@]}"

  bootstrap_train_args=(
    train-manas-core
    --dataset "$ARTIFACT_ROOT/bootstrap-dataset" \
    --output "$ARTIFACT_ROOT/bootstrap-checkpoint" \
    --sequence "$BOOTSTRAP_SEQUENCE" \
    --epochs "$BOOTSTRAP_EPOCHS" \
    --max-batches "$BOOTSTRAP_MAX_BATCHES" \
    --lr "$BOOTSTRAP_LR" \
    --no-aux
  )
  if [[ -n "$BOOTSTRAP_MLX_SEED" ]]; then
    bootstrap_train_args+=(--mlx-seed "$BOOTSTRAP_MLX_SEED")
  fi
  run_kuyu_plain "${bootstrap_train_args[@]}"
  CURRENT_CHECKPOINT="$ARTIFACT_ROOT/bootstrap-checkpoint"

  if [[ -n "$BOOTSTRAP_BIAS_DELTAS" ]]; then
    run_kuyu_with_model select-manas-bias-calibration \
      --source-checkpoint "$CURRENT_CHECKPOINT" \
      --artifact-root "$ARTIFACT_ROOT/bootstrap-bias-calibration" \
      --task "$TASK" \
      --suites "$SUITES" \
      --episodes "$EPISODES" \
      --workers "$WORKERS" \
      "--deltas=$BOOTSTRAP_BIAS_DELTAS"
    SELECTED_BIAS_CHECKPOINT="$(python3 - "$ARTIFACT_ROOT/bootstrap-bias-calibration/bias-calibration-selection.json" <<'PY'
import json
import pathlib
import sys

selection_path = pathlib.Path(sys.argv[1])
with selection_path.open("r", encoding="utf-8") as handle:
    selection = json.load(handle)
if not selection.get("selectedAccepted"):
    raise SystemExit(0)
checkpoint = selection.get("selectedCheckpointPath")
if not checkpoint:
    raise SystemExit("bias calibration selected no checkpoint")
print(checkpoint)
PY
)"
    if [[ -n "$SELECTED_BIAS_CHECKPOINT" ]]; then
      CURRENT_CHECKPOINT="$SELECTED_BIAS_CHECKPOINT"
    fi
  fi

  BOOTSTRAP_STRICT_READY=0
  if [[ "$TASK" == "singleLift" ]]; then
    if strict_checkpoint_passes "$CURRENT_CHECKPOINT" "$ARTIFACT_ROOT/bootstrap-checkpoint-evaluation"; then
      BOOTSTRAP_STRICT_READY=1
    fi
  fi

  if [[ "$TASK" == "singleLift" && "$BOOTSTRAP_REPAIR_ATTEMPTS" -gt 0 && "$BOOTSTRAP_STRICT_READY" != "1" ]]; then
    run_kuyu_with_model check-training-harness \
      --source-checkpoint "$CURRENT_CHECKPOINT" \
      --artifact-root "$ARTIFACT_ROOT/bootstrap-repair" \
      --attempts "$BOOTSTRAP_REPAIR_ATTEMPTS" \
      --sequence "$BOOTSTRAP_SEQUENCE" \
      --epochs "$BOOTSTRAP_EPOCHS" \
      --max-batches "$BOOTSTRAP_MAX_BATCHES" \
      --lr "$BOOTSTRAP_LR" \
      --recovery-repeat 1
    CURRENT_CHECKPOINT="$(python3 - "$ARTIFACT_ROOT/bootstrap-repair/training-harness-summary.json" <<'PY'
import json
import pathlib
import sys

summary_path = pathlib.Path(sys.argv[1])
with summary_path.open("r", encoding="utf-8") as handle:
    summary = json.load(handle)
if not summary.get("allPassed"):
    raise SystemExit("bootstrap repair did not satisfy readiness")
selected = summary.get("selectedCandidate") or {}
checkpoint = selected.get("checkpoint")
if not checkpoint:
    raise SystemExit("bootstrap repair did not publish a selected checkpoint")
print(checkpoint)
PY
)"
  fi
fi

if [[ ! -f "$CURRENT_CHECKPOINT/model.json" || ! -f "$CURRENT_CHECKPOINT/core.safetensors" || ! -f "$CURRENT_CHECKPOINT/reflex.safetensors" ]]; then
  echo "[learning-readiness] ready checkpoint missing file: $CURRENT_CHECKPOINT" >&2
  exit 1
fi
verify_parent_checkpoint_task "$CURRENT_CHECKPOINT"
verify_ready_checkpoint_regression "$CURRENT_CHECKPOINT"

write_readiness_summary true ""
