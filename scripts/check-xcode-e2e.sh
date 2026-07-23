#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ARTIFACT_ROOT="${1:-${TMPDIR:-/tmp}/kuyu-xcode-e2e-$(date +%Y%m%d-%H%M%S)}"
DERIVED_DATA="${KUYU_XCODE_DERIVED_DATA:-$ARTIFACT_ROOT/DerivedData}"
DESTINATION="${KUYU_XCODE_DESTINATION:-platform=macOS}"
CONFIGURATION="${KUYU_XCODE_CONFIGURATION:-Debug}"
TIMEOUT_SECONDS="${KUYU_XCODE_E2E_TIMEOUT_SECONDS:-900}"
TIMEOUT_GRACE_SECONDS="${KUYU_XCODE_E2E_TIMEOUT_GRACE_SECONDS:-5}"
TEST_TIMEOUT_SECONDS="${KUYU_XCODE_TEST_TIMEOUT_SECONDS:-60}"
RUN_TESTS="${KUYU_XCODE_RUN_TESTS:-1}"
TIMEOUT_HELPER="$ROOT_DIR/../scripts/run-with-process-group-timeout.py"

mkdir -p "$ARTIFACT_ROOT"

run_with_timeout() {
  python3 "$TIMEOUT_HELPER" \
    --timeout "$TIMEOUT_SECONDS" \
    --grace-period "$TIMEOUT_GRACE_SECONDS" \
    -- "$@"
}

run_allowing_harness_reject() {
  set +e
  run_with_timeout "$@"
  local status=$?
  set -e
  if [[ $status -eq 124 || $status -ge 128 ]]; then
    return "$status"
  fi
  return 0
}

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
  echo "[xcode-e2e] missing executable: $KUYU_BIN" >&2
  exit 1
fi

run_with_timeout "$KUYU_BIN" check-kuyu-regression \
  --controller teacherBaseline \
  --tasks lift \
  --suites 6 \
  --episodes 1 \
  --artifact-root "$ARTIFACT_ROOT/teacher-regression"

run_with_timeout "$KUYU_BIN" rollout \
  --controller teacherBaseline \
  --task lift \
  --suite 6 \
  --episodes 1 \
  --workers 1 \
  --export-dataset "$ARTIFACT_ROOT/bootstrap-dataset"

run_with_timeout "$KUYU_BIN" train-manas-core \
  --dataset "$ARTIFACT_ROOT/bootstrap-dataset" \
  --output "$ARTIFACT_ROOT/incumbent-checkpoint" \
  --sequence 16 \
  --epochs 1 \
  --max-batches 1 \
  --no-aux

INCUMBENT_CHECKPOINT="$ARTIFACT_ROOT/incumbent-checkpoint"
if [[ ! -f "$INCUMBENT_CHECKPOINT/model.json" || ! -f "$INCUMBENT_CHECKPOINT/core.safetensors" || ! -f "$INCUMBENT_CHECKPOINT/reflex.safetensors" ]]; then
  echo "[xcode-e2e] incomplete incumbent checkpoint: $INCUMBENT_CHECKPOINT" >&2
  exit 1
fi

run_allowing_harness_reject "$KUYU_BIN" check-kuyu-regression \
  --controller manasMLX \
  --snapshot "$INCUMBENT_CHECKPOINT" \
  --tasks lift \
  --suites 6 \
  --episodes 1 \
  --artifact-root "$ARTIFACT_ROOT/incumbent-regression"

run_allowing_harness_reject "$KUYU_BIN" evolve-manas \
  --snapshot "$INCUMBENT_CHECKPOINT" \
  --task lift \
  --population 2 \
  --generations 1 \
  --elite-count 1 \
  --workers 1 \
  --candidate-evaluation-concurrency 2 \
  --suites 6 \
  --episodes 1 \
  --variation copy \
  --evaluation regression \
  --search-strategy qualityDiversity \
  --artifact-root "$ARTIFACT_ROOT/evolution"

python3 - "$ARTIFACT_ROOT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])

def load_json(relative):
    path = root / relative
    if not path.exists():
        raise SystemExit(f"missing artifact: {path}")
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)

teacher = load_json("teacher-regression/kuyu-regression-summary.json")
if not teacher.get("environmentReady") or not teacher.get("allPassed"):
    raise SystemExit("teacher regression did not pass")

checkpoint = root / "incumbent-checkpoint"
for filename in ["model.json", "core.safetensors", "reflex.safetensors"]:
    if not (checkpoint / filename).exists():
        raise SystemExit(f"missing incumbent checkpoint file: {filename}")

incumbent = load_json("incumbent-regression/kuyu-regression-summary.json")
if not incumbent.get("environmentReady"):
    raise SystemExit("incumbent regression environment was not ready")
if "gateReport" not in incumbent:
    raise SystemExit("incumbent regression gateReport missing")

decision = load_json("evolution/accepted-checkpoint.json")
if decision.get("accepted"):
    checkpoint = decision.get("checkpointURL")
    if not checkpoint:
        raise SystemExit("accepted evolution decision has no checkpointURL")
else:
    if not decision.get("reasons"):
        raise SystemExit("rejected evolution decision has no reasons")

trace_path = root / "evolution/evaluation-trace.jsonl"
if not trace_path.exists():
    raise SystemExit(f"missing artifact: {trace_path}")
traces = [
    json.loads(line)
    for line in trace_path.read_text(encoding="utf-8").splitlines()
    if line.strip()
]
if len(traces) != 2:
    raise SystemExit(f"expected 2 evaluation traces, got {len(traces)}")
if not any(trace.get("activeEvaluationCountAtStart", 0) > 1 for trace in traces):
    raise SystemExit("candidate evaluation did not overlap")

print(f"[xcode-e2e] artifactRoot={root}")
print(
    "[xcode-e2e] teacher=pass "
    f"incumbentGateAccepted={incumbent['gateReport'].get('accepted')} "
    f"evolutionAccepted={decision.get('accepted')}"
)
PY
