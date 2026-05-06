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

TASK="${KUYU_LEARNING_TASK:-lift}"
SUITES="${KUYU_LEARNING_SUITES:-6}"
EPISODES="${KUYU_LEARNING_EPISODES:-1}"
WORKERS="${KUYU_LEARNING_WORKERS:-1}"
POPULATION="${KUYU_LEARNING_POPULATION:-4}"
GENERATIONS="${KUYU_LEARNING_GENERATIONS:-5}"
ELITE_COUNT="${KUYU_LEARNING_ELITE_COUNT:-1}"
CANDIDATE_EVALUATION_CONCURRENCY="${KUYU_LEARNING_CANDIDATE_EVALUATION_CONCURRENCY:-2}"
VARIATION="${KUYU_LEARNING_VARIATION:-gaussian}"
SEARCH_STRATEGY="${KUYU_LEARNING_SEARCH_STRATEGY:-qualityDiversity}"
MUTATION_RATE="${KUYU_LEARNING_MUTATION_RATE:-0.08}"
MUTATION_NOISE_SCALE="${KUYU_LEARNING_MUTATION_NOISE_SCALE:-0.01}"
SEEDS_CSV="${KUYU_LEARNING_SEEDS:-1,2,3}"
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

run_kuyu_with_model check-kuyu-regression \
  --controller teacherBaseline \
  --tasks "$TASK" \
  --suites "$SUITES" \
  --episodes "$EPISODES" \
  --artifact-root "$ARTIFACT_ROOT/teacher-regression"

if [[ -n "$SOURCE_CHECKPOINT" ]]; then
  CURRENT_CHECKPOINT="$SOURCE_CHECKPOINT"
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
  echo "[learning-campaign] incomplete source checkpoint: $CURRENT_CHECKPOINT" >&2
  exit 1
fi

IFS=',' read -r -a SEEDS <<< "$SEEDS_CSV"
mkdir -p "$ARTIFACT_ROOT/accepted-checkpoints"

for raw_seed in "${SEEDS[@]}"; do
  seed="$(echo "$raw_seed" | tr -d '[:space:]')"
  if [[ -z "$seed" ]]; then
    continue
  fi
  RUN_ROOT="$ARTIFACT_ROOT/seeds/seed-$seed"
  mkdir -p "$RUN_ROOT"
  echo "[learning-campaign] seed=$seed parent=$CURRENT_CHECKPOINT"

  run_kuyu_allowing_harness_reject_with_model check-kuyu-regression \
    --controller manasMLX \
    --snapshot "$CURRENT_CHECKPOINT" \
    --tasks "$TASK" \
    --suites "$SUITES" \
    --episodes "$EPISODES" \
    --artifact-root "$RUN_ROOT/incumbent-regression" || true

  run_kuyu_allowing_harness_reject_with_model evolve-manas \
    --snapshot "$CURRENT_CHECKPOINT" \
    --task "$TASK" \
    --population "$POPULATION" \
    --generations "$GENERATIONS" \
    --elite-count "$ELITE_COUNT" \
    --workers "$WORKERS" \
    --candidate-evaluation-concurrency "$CANDIDATE_EVALUATION_CONCURRENCY" \
    --suites "$SUITES" \
    --episodes "$EPISODES" \
    --variation "$VARIATION" \
    --evaluation regression \
    --search-strategy "$SEARCH_STRATEGY" \
    --mutation-rate "$MUTATION_RATE" \
    --mutation-noise-scale "$MUTATION_NOISE_SCALE" \
    --common-random-seed "$seed" \
    --artifact-root "$RUN_ROOT/evolution" || true

  NEXT_CHECKPOINT="$(
    python3 - "$RUN_ROOT/evolution/accepted-checkpoint.json" "$ARTIFACT_ROOT/accepted-checkpoints/seed-$seed" <<'PY'
import json
import pathlib
import shutil
import sys

decision_path = pathlib.Path(sys.argv[1])
save_path = pathlib.Path(sys.argv[2])
decision = json.loads(decision_path.read_text(encoding="utf-8"))
checkpoint = decision.get("checkpointURL")
if not decision.get("accepted") or not checkpoint:
    print("")
    raise SystemExit(0)
source = pathlib.Path(checkpoint)
if save_path.exists():
    shutil.rmtree(save_path)
shutil.copytree(source, save_path)
print(save_path)
PY
  )"
  if [[ -n "$NEXT_CHECKPOINT" ]]; then
    CURRENT_CHECKPOINT="$NEXT_CHECKPOINT"
    echo "[learning-campaign] seed=$seed acceptedCheckpoint=$CURRENT_CHECKPOINT"
  else
    echo "[learning-campaign] seed=$seed no accepted checkpoint; keeping parent"
  fi
done

python3 - "$ARTIFACT_ROOT" "$CURRENT_CHECKPOINT" "$SEEDS_CSV" <<'PY'
import json
import math
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
final_checkpoint = sys.argv[2]
seeds = [
    item.strip()
    for item in sys.argv[3].split(",")
    if item.strip()
]

def load_json(path):
    return json.loads(path.read_text(encoding="utf-8"))

def load_json_lines(path):
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]

def finite_number(value):
    return isinstance(value, (int, float)) and math.isfinite(value)

def best_fitness_record(records):
    finite_records = [
        record
        for record in records
        if finite_number(record.get("scalarFitness"))
    ]
    if not finite_records:
        return None
    return max(
        finite_records,
        key=lambda record: (
            float(record.get("scalarFitness")),
            int(record.get("generationIndex", -1)),
            str(record.get("candidateID", "")),
        )
    )

def metric(record, key):
    if record is None:
        return None
    value = record.get(key)
    if finite_number(value):
        return value
    return None

runs = []
accepted_count = 0
for seed in seeds:
    run_root = root / "seeds" / f"seed-{seed}"
    evolution_root = run_root / "evolution"
    decision_path = evolution_root / "accepted-checkpoint.json"
    manifest_path = evolution_root / "evolution-manifest.json"
    trace_path = evolution_root / "evaluation-trace.jsonl"
    fitness_path = evolution_root / "fitness.jsonl"
    candidates_path = evolution_root / "candidates.jsonl"
    missing_paths = [
        path.name
        for path in [decision_path, manifest_path, trace_path, fitness_path, candidates_path]
        if not path.exists()
    ]
    if missing_paths:
        raise SystemExit(
            f"missing evolution artifact for seed={seed}: {', '.join(missing_paths)}"
        )
    decision = load_json(decision_path)
    manifest = load_json(manifest_path)
    traces = load_json_lines(trace_path)
    fitness_records = load_json_lines(fitness_path)
    candidate_records = load_json_lines(candidates_path)
    incumbent_candidate_id = next(
        (
            candidate.get("candidateID")
            for candidate in candidate_records
            if candidate.get("isIncumbent") is True
        ),
        None
    )
    incumbent_record = next(
        (
            record
            for record in fitness_records
            if record.get("candidateID") == incumbent_candidate_id
        ),
        None
    )
    best_record = best_fitness_record(fitness_records)
    incumbent_fitness = metric(incumbent_record, "scalarFitness")
    best_fitness = metric(best_record, "scalarFitness")
    best_vs_incumbent_delta = (
        best_fitness - incumbent_fitness
        if best_fitness is not None and incumbent_fitness is not None
        else None
    )
    accepted = bool(decision.get("accepted"))
    if accepted:
        accepted_count += 1
    runs.append({
        "seed": seed,
        "terminalState": manifest.get("terminalState"),
        "accepted": accepted,
        "acceptedCandidateID": decision.get("candidateID"),
        "acceptedCheckpointURL": decision.get("checkpointURL"),
        "incumbentCandidateID": incumbent_candidate_id,
        "incumbentFitness": incumbent_fitness,
        "bestCandidateID": best_record.get("candidateID") if best_record else None,
        "bestFitness": best_fitness,
        "bestVsIncumbentDelta": best_vs_incumbent_delta,
        "bestTaskPassRate": metric(best_record, "taskPassRate"),
        "bestHoldTimeRatio": metric(best_record, "holdTimeRatio"),
        "bestSafetyViolationRate": metric(best_record, "safetyViolationRate"),
        "bestRewardAverage": metric(best_record, "rewardAverage"),
        "fitnessCount": len(fitness_records),
        "reasonCount": len(decision.get("reasons", [])),
        "evaluationTraceCount": len(traces),
        "overlappedEvaluation": any(
            trace.get("activeEvaluationCountAtStart", 0) > 1
            for trace in traces
        ),
    })

summary = {
    "artifactRoot": str(root),
    "seedCount": len(seeds),
    "acceptedCount": accepted_count,
    "finalCheckpoint": final_checkpoint,
    "runs": runs,
}
summary_path = root / "learning-campaign-summary.json"
summary_path.write_text(
    json.dumps(summary, indent=2, sort_keys=True),
    encoding="utf-8"
)
print(f"[learning-campaign] summary={summary_path}")
print(f"[learning-campaign] acceptedCount={accepted_count} finalCheckpoint={final_checkpoint}")
PY
