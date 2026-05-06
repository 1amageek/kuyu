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
STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
RUN_TOKEN="$(date -u +"%Y%m%d-%H%M%S")"
RESOURCE_MONITOR_PID=""

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

if [[ "$RESUME" != "0" && "$RESUME" != "1" ]]; then
  echo "[learning-campaign] KUYU_LEARNING_RESUME must be 0 or 1: $RESUME" >&2
  exit 1
fi

if [[ -e "$ARTIFACT_ROOT" ]]; then
  if [[ ! -d "$ARTIFACT_ROOT" ]]; then
    echo "[learning-campaign] artifact root is not a directory: $ARTIFACT_ROOT" >&2
    exit 1
  fi
  if [[ "$RESUME" != "1" && -n "$(find "$ARTIFACT_ROOT" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "[learning-campaign] refusing to reuse non-empty artifact root: $ARTIFACT_ROOT" >&2
    exit 1
  fi
  if [[ "$RESUME" == "1" && ! -f "$ARTIFACT_ROOT/learning-campaign-plan.json" ]]; then
    echo "[learning-campaign] cannot resume without learning-campaign-plan.json: $ARTIFACT_ROOT" >&2
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

write_progress() {
  python3 - "$ARTIFACT_ROOT/progress.jsonl" "$1" "$2" <<'PY'
import json
import pathlib
import sys
from datetime import datetime, timezone

path = pathlib.Path(sys.argv[1])
event = sys.argv[2]
detail = sys.argv[3]
record = {
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "event": event,
}
if detail:
    record["detail"] = detail
with path.open("a", encoding="utf-8") as handle:
    handle.write(json.dumps(record, sort_keys=True) + "\n")
PY
}

write_campaign_status() {
  python3 - "$ARTIFACT_ROOT" "$1" "$STARTED_AT" <<'PY'
import json
import pathlib
import sys
from datetime import datetime, timezone

root = pathlib.Path(sys.argv[1])
status = int(sys.argv[2])
started_at = sys.argv[3]
finished_at = datetime.now(timezone.utc).isoformat()
summary = {
    "status": "succeeded" if status == 0 else "failed",
    "exitCode": status,
    "startedAt": started_at,
    "finishedAt": finished_at,
}
(root / "campaign-status.json").write_text(
    json.dumps(summary, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
with (root / "progress.jsonl").open("a", encoding="utf-8") as handle:
    handle.write(json.dumps({
        "timestamp": finished_at,
        "event": "campaign-finished",
        "exitCode": status,
        "status": summary["status"],
    }, sort_keys=True) + "\n")
PY
}

finalize_campaign() {
  local status=$?
  if [[ -n "$RESOURCE_MONITOR_PID" ]]; then
    kill "$RESOURCE_MONITOR_PID" 2>/dev/null || true
    wait "$RESOURCE_MONITOR_PID" 2>/dev/null || true
  fi
  write_campaign_status "$status"
  local kuyu_bin="${KUYU_BIN:-}"
  if [[ -n "$kuyu_bin" && -x "$kuyu_bin" && -f "$ARTIFACT_ROOT/learning-campaign-summary.json" ]]; then
    set +e
    "$kuyu_bin" validate-learning-campaign --artifact-root "$ARTIFACT_ROOT"
    local validation_status=$?
    set -e
    if [[ "$validation_status" -eq 0 ]]; then
      write_progress "validation-written" "$ARTIFACT_ROOT/learning-campaign-validation.json"
    else
      write_progress "validation-failed" "$ARTIFACT_ROOT/learning-campaign-validation.json"
      if [[ "$status" -eq 0 ]]; then
        status="$validation_status"
        write_campaign_status "$status"
        set +e
        "$kuyu_bin" validate-learning-campaign --artifact-root "$ARTIFACT_ROOT"
        set -e
      fi
    fi
  fi
  rm -rf "$LOCK_PATH"
  exit "$status"
}
trap finalize_campaign EXIT

write_progress "campaign-started" "$ARTIFACT_ROOT"

start_resource_monitor() {
  python3 - "$ARTIFACT_ROOT/resource-samples.jsonl" "$ARTIFACT_ROOT" "$RESOURCE_SAMPLE_SECONDS" "$$" <<'PY' &
import json
import math
import os
import pathlib
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone

path = pathlib.Path(sys.argv[1])
artifact_root = pathlib.Path(sys.argv[2])
interval = float(sys.argv[3])
parent_pid = int(sys.argv[4])

if not math.isfinite(interval) or interval <= 0:
    raise SystemExit(0)

def parent_alive():
    try:
        os.kill(parent_pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True

def rss_kib(pid):
    completed = subprocess.run(
        ["ps", "-o", "rss=", "-p", str(pid)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    value = completed.stdout.strip()
    return int(value) if value.isdigit() else None

def vm_pages():
    completed = subprocess.run(
        ["vm_stat"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    pages = {}
    for line in completed.stdout.splitlines():
        if ":" not in line:
            continue
        key, raw = line.split(":", 1)
        value = raw.strip().rstrip(".").replace(".", "")
        if value.isdigit():
            pages[key.strip()] = int(value)
    return pages

while parent_alive():
    usage = shutil.disk_usage(artifact_root)
    load_average = os.getloadavg()
    record = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "artifactRootFreeBytes": usage.free,
        "artifactRootUsedBytes": usage.used,
        "loadAverage1m": load_average[0],
        "loadAverage5m": load_average[1],
        "loadAverage15m": load_average[2],
        "parentPID": parent_pid,
        "parentRSSKiB": rss_kib(parent_pid),
        "vmPages": vm_pages(),
    }
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, sort_keys=True) + "\n")
    time.sleep(interval)
PY
  RESOURCE_MONITOR_PID="$!"
}

python3 - "$ARTIFACT_ROOT" "$MIN_FREE_GB" "$TASK" "$SUITES" "$EPISODES" "$WORKERS" "$POPULATION" "$GENERATIONS" "$ELITE_COUNT" "$CANDIDATE_EVALUATION_CONCURRENCY" "$SEEDS_CSV" "$SOURCE_CHECKPOINT" "$MODEL_DESCRIPTOR" "$VARIATION" "$SEARCH_STRATEGY" "$MUTATION_RATE" "$MUTATION_NOISE_SCALE" "$BOOTSTRAP_SUITE" "$BOOTSTRAP_EPISODES" "$BOOTSTRAP_SEQUENCE" "$BOOTSTRAP_EPOCHS" "$BOOTSTRAP_MAX_BATCHES" "$BOOTSTRAP_LR" "$RESUME" "$RESOURCE_SAMPLE_SECONDS" <<'PY'
import json
import math
import pathlib
import shutil
import sys

(
    root_raw,
    min_free_gb_raw,
    task,
    suites_raw,
    episodes_raw,
    workers_raw,
    population_raw,
    generations_raw,
    elite_count_raw,
    candidate_concurrency_raw,
    seeds_raw,
    source_checkpoint_raw,
    model_descriptor_raw,
    variation,
    search_strategy,
    mutation_rate_raw,
    mutation_noise_scale_raw,
    bootstrap_suite,
    bootstrap_episodes_raw,
    bootstrap_sequence_raw,
    bootstrap_epochs_raw,
    bootstrap_max_batches_raw,
    bootstrap_lr_raw,
    resume_raw,
    resource_sample_seconds_raw,
) = sys.argv[1:]

root = pathlib.Path(root_raw)

def parse_positive_int(name, raw):
    try:
        value = int(raw)
    except ValueError as error:
        raise SystemExit(f"{name} must be an integer: {raw}") from error
    if value <= 0:
        raise SystemExit(f"{name} must be positive: {value}")
    return value

def parse_nonnegative_float(name, raw):
    try:
        value = float(raw)
    except ValueError as error:
        raise SystemExit(f"{name} must be numeric: {raw}") from error
    if not math.isfinite(value) or value < 0:
        raise SystemExit(f"{name} must be finite and non-negative: {raw}")
    return value

def parse_positive_float(name, raw):
    value = parse_nonnegative_float(name, raw)
    if value <= 0:
        raise SystemExit(f"{name} must be positive: {raw}")
    return value

episodes = parse_positive_int("KUYU_LEARNING_EPISODES", episodes_raw)
workers = parse_positive_int("KUYU_LEARNING_WORKERS", workers_raw)
population = parse_positive_int("KUYU_LEARNING_POPULATION", population_raw)
generations = parse_positive_int("KUYU_LEARNING_GENERATIONS", generations_raw)
elite_count = parse_positive_int("KUYU_LEARNING_ELITE_COUNT", elite_count_raw)
candidate_concurrency = parse_positive_int(
    "KUYU_LEARNING_CANDIDATE_EVALUATION_CONCURRENCY",
    candidate_concurrency_raw,
)
bootstrap_episodes = parse_positive_int("KUYU_LEARNING_BOOTSTRAP_EPISODES", bootstrap_episodes_raw)
bootstrap_sequence = parse_positive_int("KUYU_LEARNING_BOOTSTRAP_SEQUENCE", bootstrap_sequence_raw)
bootstrap_epochs = parse_positive_int("KUYU_LEARNING_BOOTSTRAP_EPOCHS", bootstrap_epochs_raw)
bootstrap_max_batches = parse_positive_int("KUYU_LEARNING_BOOTSTRAP_MAX_BATCHES", bootstrap_max_batches_raw)
mutation_rate = parse_nonnegative_float("KUYU_LEARNING_MUTATION_RATE", mutation_rate_raw)
mutation_noise_scale = parse_nonnegative_float("KUYU_LEARNING_MUTATION_NOISE_SCALE", mutation_noise_scale_raw)
bootstrap_lr = parse_positive_float("KUYU_LEARNING_BOOTSTRAP_LR", bootstrap_lr_raw)
min_free_gb = parse_nonnegative_float("KUYU_LEARNING_MIN_FREE_GB", min_free_gb_raw)
resource_sample_seconds = parse_nonnegative_float(
    "KUYU_LEARNING_RESOURCE_SAMPLE_SECONDS",
    resource_sample_seconds_raw,
)
resume_enabled = resume_raw == "1"

if elite_count > population:
    raise SystemExit("KUYU_LEARNING_ELITE_COUNT must be <= KUYU_LEARNING_POPULATION")
if candidate_concurrency > population:
    raise SystemExit("KUYU_LEARNING_CANDIDATE_EVALUATION_CONCURRENCY must be <= KUYU_LEARNING_POPULATION")

seeds = [item.strip() for item in seeds_raw.split(",") if item.strip()]
if not seeds:
    raise SystemExit("KUYU_LEARNING_SEEDS must contain at least one seed")
for seed in seeds:
    int(seed)

suites = [item.strip() for item in suites_raw.split(",") if item.strip()]
if not suites:
    raise SystemExit("KUYU_LEARNING_SUITES must contain at least one suite")
for suite in suites:
    int(suite)

if model_descriptor_raw and not pathlib.Path(model_descriptor_raw).is_file():
    raise SystemExit(f"missing model descriptor: {model_descriptor_raw}")

if source_checkpoint_raw:
    source_checkpoint = pathlib.Path(source_checkpoint_raw)
    missing = [
        name
        for name in ["model.json", "core.safetensors", "reflex.safetensors"]
        if not (source_checkpoint / name).is_file()
    ]
    if missing:
        raise SystemExit(
            f"incomplete source checkpoint: {source_checkpoint} missing {', '.join(missing)}"
        )

usage = shutil.disk_usage(root)
required_bytes = math.ceil(min_free_gb * 1024 * 1024 * 1024)
if usage.free < required_bytes:
    raise SystemExit(
        f"insufficient free disk: availableBytes={usage.free} requiredBytes={required_bytes}"
    )

planned_candidate_evaluations = len(seeds) * population * generations
planned_incumbent_regressions = len(seeds)
planned_teacher_regressions = 1
planned_regression_rollouts = (
    planned_teacher_regressions
    + planned_incumbent_regressions
    + planned_candidate_evaluations
)
planned_regression_episodes = planned_regression_rollouts * len(suites) * episodes

plan = {
    "artifactRoot": str(root),
    "task": task,
    "suites": suites,
    "episodes": episodes,
    "workers": workers,
    "population": population,
    "generations": generations,
    "eliteCount": elite_count,
    "candidateEvaluationConcurrency": candidate_concurrency,
    "seeds": seeds,
    "sourceCheckpoint": source_checkpoint_raw or None,
    "modelDescriptor": model_descriptor_raw or None,
    "variation": variation,
    "searchStrategy": search_strategy,
    "mutationRate": mutation_rate,
    "mutationNoiseScale": mutation_noise_scale,
    "bootstrapSuite": bootstrap_suite,
    "bootstrapEpisodes": bootstrap_episodes,
    "bootstrapSequence": bootstrap_sequence,
    "bootstrapEpochs": bootstrap_epochs,
    "bootstrapMaxBatches": bootstrap_max_batches,
    "bootstrapLearningRate": bootstrap_lr,
    "resumeEnabled": resume_enabled,
    "resourceSampleSeconds": resource_sample_seconds,
    "availableDiskBytes": usage.free,
    "requiredDiskBytes": required_bytes,
    "plannedCandidateEvaluations": planned_candidate_evaluations,
    "plannedRegressionRollouts": planned_regression_rollouts,
    "plannedRegressionEpisodes": planned_regression_episodes,
}
plan_path = root / "learning-campaign-plan.json"
if resume_enabled:
    previous = json.loads(plan_path.read_text(encoding="utf-8"))
    ignored_keys = {
        "availableDiskBytes",
        "requiredDiskBytes",
        "resumeEnabled",
        "resourceSampleSeconds",
    }
    mismatches = []
    for key, value in plan.items():
        if key in ignored_keys:
            continue
        if previous.get(key) != value:
            mismatches.append(key)
    if mismatches:
        raise SystemExit(
            "resume plan mismatch: " + ", ".join(sorted(mismatches))
        )
plan_path.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"[learning-campaign] plan={plan_path}")
print(
    "[learning-campaign] planned "
    f"candidateEvaluations={planned_candidate_evaluations} "
    f"regressionEpisodes={planned_regression_episodes}"
)
PY

write_progress "plan-written" "$ARTIFACT_ROOT/learning-campaign-plan.json"
start_resource_monitor

python3 - "$ARTIFACT_ROOT" "$ROOT_DIR" "$DERIVED_DATA" "$DESTINATION" "$CONFIGURATION" "$LOCK_PATH" <<'PY'
import json
import pathlib
import platform
import subprocess
import sys
from datetime import datetime, timezone

root = pathlib.Path(sys.argv[1])
repo_root = pathlib.Path(sys.argv[2])
derived_data = sys.argv[3]
destination = sys.argv[4]
configuration = sys.argv[5]
lock_path = sys.argv[6]

def run(command):
    completed = subprocess.run(
        command,
        cwd=repo_root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    return completed.stdout.strip()

def repo_state(path):
    path = pathlib.Path(path)
    return {
        "path": str(path),
        "head": run(["git", "-C", str(path), "rev-parse", "HEAD"]),
        "branch": run(["git", "-C", str(path), "branch", "--show-current"]),
        "dirty": bool(run(["git", "-C", str(path), "status", "--short"])),
    }

environment = {
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "host": platform.node(),
    "platform": platform.platform(),
    "machine": platform.machine(),
    "xcodebuildVersion": run(["xcodebuild", "-version"]),
    "swiftVersion": run(["swift", "--version"]),
    "derivedData": derived_data,
    "destination": destination,
    "configuration": configuration,
    "lockPath": lock_path,
    "repositories": [
        repo_state(repo_root),
        repo_state(repo_root.parent / "kuyu-core"),
        repo_state(repo_root.parent / "kuyu-training"),
        repo_state(repo_root.parent / "kuyu-world-model"),
        repo_state(repo_root.parent / "kuyu-scenarios"),
        repo_state(repo_root.parent / "kuyu-physics"),
        repo_state(repo_root.parent / "manas"),
    ],
}
(root / "learning-campaign-environment.json").write_text(
    json.dumps(environment, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY

write_progress "environment-written" "$ARTIFACT_ROOT/learning-campaign-environment.json"

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
  write_progress "xcode-test-started" "$DERIVED_DATA"
  run_with_timeout xcodebuild test \
    -scheme kuyu \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" \
    -maximum-test-execution-time-allowance "$TEST_TIMEOUT_SECONDS"
  write_progress "xcode-test-finished" "$DERIVED_DATA"
else
  write_progress "xcode-build-started" "$DERIVED_DATA"
  run_with_timeout xcodebuild build \
    -scheme kuyu \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA"
  write_progress "xcode-build-finished" "$DERIVED_DATA"
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

checkpoint_complete() {
  local checkpoint="$1"
  [[ -f "$checkpoint/model.json" && -f "$checkpoint/core.safetensors" && -f "$checkpoint/reflex.safetensors" ]]
}

evolution_artifacts_complete() {
  local evolution_root="$1"
  [[ -f "$evolution_root/accepted-checkpoint.json" &&
     -f "$evolution_root/evolution-manifest.json" &&
     -f "$evolution_root/evaluation-trace.jsonl" &&
     -f "$evolution_root/fitness.jsonl" &&
     -f "$evolution_root/candidates.jsonl" ]]
}

resolve_accepted_checkpoint() {
  local decision_path="$1"
  local save_path="$2"
  python3 - "$decision_path" "$save_path" <<'PY'
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
missing = [
    name
    for name in ["model.json", "core.safetensors", "reflex.safetensors"]
    if not (source / name).is_file()
]
if missing:
    raise SystemExit(
        f"accepted checkpoint is incomplete: {source} missing {', '.join(missing)}"
    )
if save_path.exists():
    shutil.rmtree(save_path)
shutil.copytree(source, save_path)
print(save_path)
PY
}

quarantine_artifact_path() {
  local path="$1"
  local label="$2"
  if [[ ! -e "$path" ]]; then
    return 0
  fi
  local quarantine_root="$ARTIFACT_ROOT/quarantine/$label-$RUN_TOKEN"
  mkdir -p "$(dirname "$quarantine_root")"
  mv "$path" "$quarantine_root"
  echo "[learning-campaign] quarantined incomplete artifact: $quarantine_root"
  write_progress "artifact-quarantined" "$quarantine_root"
}

if [[ "$RESUME" == "1" && -f "$ARTIFACT_ROOT/teacher-regression/kuyu-regression-summary.json" ]]; then
  write_progress "teacher-regression-resumed" "$ARTIFACT_ROOT/teacher-regression"
else
  if [[ "$RESUME" == "1" ]]; then
    quarantine_artifact_path "$ARTIFACT_ROOT/teacher-regression" "teacher-regression"
  fi
  run_kuyu_with_model check-kuyu-regression \
    --controller teacherBaseline \
    --tasks "$TASK" \
    --suites "$SUITES" \
    --episodes "$EPISODES" \
    --artifact-root "$ARTIFACT_ROOT/teacher-regression"
  write_progress "teacher-regression-finished" "$ARTIFACT_ROOT/teacher-regression"
fi

if [[ -n "$SOURCE_CHECKPOINT" ]]; then
  CURRENT_CHECKPOINT="$SOURCE_CHECKPOINT"
  write_progress "source-checkpoint-selected" "$CURRENT_CHECKPOINT"
else
  if [[ "$RESUME" == "1" && -d "$ARTIFACT_ROOT/bootstrap-checkpoint" ]]; then
    if ! checkpoint_complete "$ARTIFACT_ROOT/bootstrap-checkpoint"; then
      quarantine_artifact_path "$ARTIFACT_ROOT/bootstrap-checkpoint" "bootstrap-checkpoint"
      quarantine_artifact_path "$ARTIFACT_ROOT/bootstrap-dataset" "bootstrap-dataset"
    else
      CURRENT_CHECKPOINT="$ARTIFACT_ROOT/bootstrap-checkpoint"
      write_progress "bootstrap-checkpoint-resumed" "$CURRENT_CHECKPOINT"
    fi
  fi

  if [[ -z "${CURRENT_CHECKPOINT:-}" ]]; then
    if [[ "$RESUME" == "1" ]]; then
      quarantine_artifact_path "$ARTIFACT_ROOT/bootstrap-dataset" "bootstrap-dataset"
    fi
    run_kuyu_with_model rollout \
      --controller teacherBaseline \
      --task "$TASK" \
      --suite "$BOOTSTRAP_SUITE" \
      --episodes "$BOOTSTRAP_EPISODES" \
      --workers "$WORKERS" \
      --export-dataset "$ARTIFACT_ROOT/bootstrap-dataset"
    write_progress "bootstrap-dataset-written" "$ARTIFACT_ROOT/bootstrap-dataset"

    run_kuyu_plain train-manas-core \
      --dataset "$ARTIFACT_ROOT/bootstrap-dataset" \
      --output "$ARTIFACT_ROOT/bootstrap-checkpoint" \
      --sequence "$BOOTSTRAP_SEQUENCE" \
      --epochs "$BOOTSTRAP_EPOCHS" \
      --max-batches "$BOOTSTRAP_MAX_BATCHES" \
      --lr "$BOOTSTRAP_LR" \
      --no-aux
    CURRENT_CHECKPOINT="$ARTIFACT_ROOT/bootstrap-checkpoint"
    write_progress "bootstrap-checkpoint-written" "$CURRENT_CHECKPOINT"
  fi
fi

if ! checkpoint_complete "$CURRENT_CHECKPOINT"; then
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

  if [[ "$RESUME" == "1" && -d "$RUN_ROOT" ]]; then
    if evolution_artifacts_complete "$RUN_ROOT/evolution"; then
      NEXT_CHECKPOINT="$(resolve_accepted_checkpoint "$RUN_ROOT/evolution/accepted-checkpoint.json" "$ARTIFACT_ROOT/accepted-checkpoints/seed-$seed")"
      if [[ -n "$NEXT_CHECKPOINT" ]]; then
        CURRENT_CHECKPOINT="$NEXT_CHECKPOINT"
      fi
      echo "[learning-campaign] seed=$seed already complete; resumed parent=$CURRENT_CHECKPOINT"
      write_progress "seed-resumed" "$seed"
      continue
    fi
    QUARANTINE_ROOT="$ARTIFACT_ROOT/quarantine/seed-$seed-$RUN_TOKEN"
    mkdir -p "$(dirname "$QUARANTINE_ROOT")"
    mv "$RUN_ROOT" "$QUARANTINE_ROOT"
    echo "[learning-campaign] quarantined incomplete seed artifact: $QUARANTINE_ROOT"
    write_progress "seed-quarantined" "$QUARANTINE_ROOT"
  fi

  mkdir -p "$RUN_ROOT"
  echo "[learning-campaign] seed=$seed parent=$CURRENT_CHECKPOINT"
  write_progress "seed-started" "$seed"

  run_kuyu_allowing_harness_reject_with_model check-kuyu-regression \
    --controller manasMLX \
    --snapshot "$CURRENT_CHECKPOINT" \
    --tasks "$TASK" \
    --suites "$SUITES" \
    --episodes "$EPISODES" \
    --artifact-root "$RUN_ROOT/incumbent-regression" || true
  write_progress "incumbent-regression-finished" "$RUN_ROOT/incumbent-regression"

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
  write_progress "evolution-finished" "$RUN_ROOT/evolution"

  NEXT_CHECKPOINT="$(resolve_accepted_checkpoint "$RUN_ROOT/evolution/accepted-checkpoint.json" "$ARTIFACT_ROOT/accepted-checkpoints/seed-$seed")"
  if [[ -n "$NEXT_CHECKPOINT" ]]; then
    CURRENT_CHECKPOINT="$NEXT_CHECKPOINT"
    echo "[learning-campaign] seed=$seed acceptedCheckpoint=$CURRENT_CHECKPOINT"
    write_progress "seed-accepted" "$seed"
  else
    echo "[learning-campaign] seed=$seed no accepted checkpoint; keeping parent"
    write_progress "seed-rejected" "$seed"
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
write_progress "summary-written" "$ARTIFACT_ROOT/learning-campaign-summary.json"
