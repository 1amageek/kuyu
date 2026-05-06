#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ARTIFACT_ROOT="${1:-}"
ALLOW_FAILED="${KUYU_VALIDATE_ALLOW_FAILED:-0}"

if [[ -z "$ARTIFACT_ROOT" ]]; then
  echo "usage: $0 <artifact-root>" >&2
  exit 2
fi

python3 - "$ARTIFACT_ROOT" "$ALLOW_FAILED" <<'PY'
import json
import math
import pathlib
import sys
from datetime import datetime, timezone

root = pathlib.Path(sys.argv[1])
allow_failed = sys.argv[2] == "1"
issues = []

def issue(code, detail):
    issues.append({"code": code, "detail": detail})

def load_json(relative_path):
    path = root / relative_path
    if not path.is_file():
        issue("missing-json", relative_path)
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        issue("invalid-json", f"{relative_path}: {error}")
        return None

def load_json_lines(relative_path):
    path = root / relative_path
    if not path.is_file():
        issue("missing-jsonl", relative_path)
        return []
    records = []
    for index, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError as error:
            issue("invalid-jsonl", f"{relative_path}:{index}: {error}")
    return records

def checkpoint_complete(path):
    checkpoint = pathlib.Path(path)
    return all((checkpoint / name).is_file() for name in [
        "model.json",
        "core.safetensors",
        "reflex.safetensors",
    ])

def finite_number(value):
    return isinstance(value, (int, float)) and math.isfinite(value)

if not root.is_dir():
    issue("missing-artifact-root", str(root))

plan = load_json("learning-campaign-plan.json")
environment = load_json("learning-campaign-environment.json")
status = load_json("campaign-status.json")
summary = load_json("learning-campaign-summary.json")
progress = load_json_lines("progress.jsonl")
resource_sample_required = True
if plan:
    resource_sample_seconds = plan.get("resourceSampleSeconds", 30)
    if finite_number(resource_sample_seconds) and resource_sample_seconds <= 0:
        resource_sample_required = False
resource_sample_path = root / "resource-samples.jsonl"
resource_samples = (
    load_json_lines("resource-samples.jsonl")
    if resource_sample_required or resource_sample_path.exists()
    else []
)

if status:
    if status.get("status") != "succeeded" and not allow_failed:
        issue("campaign-not-succeeded", str(status.get("status")))
    if not isinstance(status.get("exitCode"), int):
        issue("invalid-exit-code", str(status.get("exitCode")))

if progress:
    if progress[-1].get("event") != "campaign-finished":
        issue("missing-finished-progress-event", "progress.jsonl")
else:
    issue("empty-progress", "progress.jsonl")

if resource_samples:
    for index, sample in enumerate(resource_samples, start=1):
        free_bytes = sample.get("artifactRootFreeBytes")
        if not finite_number(free_bytes) or free_bytes < 0:
            issue("invalid-resource-free-bytes", f"resource-samples.jsonl:{index}")
elif resource_sample_required:
    issue("empty-resource-samples", "resource-samples.jsonl")

if environment:
    repositories = environment.get("repositories")
    if not isinstance(repositories, list) or not repositories:
        issue("missing-repository-state", "learning-campaign-environment.json")

if plan and summary:
    plan_seeds = [str(seed) for seed in plan.get("seeds", [])]
    summary_runs = summary.get("runs", [])
    summary_seeds = [str(run.get("seed")) for run in summary_runs]
    if plan_seeds != summary_seeds:
        issue("seed-summary-mismatch", f"plan={plan_seeds} summary={summary_seeds}")
    try:
        expected_fitness_count = int(plan.get("population", 0)) * int(plan.get("generations", 0))
    except (TypeError, ValueError):
        issue("invalid-plan-fitness-shape", "population/generations")
        expected_fitness_count = 0
    for run in summary_runs:
        seed = str(run.get("seed"))
        evolution_root = root / "seeds" / f"seed-{seed}" / "evolution"
        for name in [
            "accepted-checkpoint.json",
            "evolution-manifest.json",
            "evaluation-trace.jsonl",
            "fitness.jsonl",
            "candidates.jsonl",
        ]:
            if not (evolution_root / name).is_file():
                issue("missing-seed-evolution-artifact", f"seed={seed} file={name}")
        fitness_count = run.get("fitnessCount")
        if expected_fitness_count > 0 and fitness_count != expected_fitness_count:
            issue(
                "fitness-count-mismatch",
                f"seed={seed} expected={expected_fitness_count} actual={fitness_count}",
            )
        if run.get("accepted") and not run.get("acceptedCheckpointURL"):
            issue("accepted-missing-checkpoint-url", f"seed={seed}")
    final_checkpoint = summary.get("finalCheckpoint")
    if not final_checkpoint or not checkpoint_complete(final_checkpoint):
        issue("incomplete-final-checkpoint", str(final_checkpoint))

validation = {
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "artifactRoot": str(root),
    "valid": not issues,
    "issueCount": len(issues),
    "issues": issues,
}
(root / "learning-campaign-validation.json").write_text(
    json.dumps(validation, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)

if issues:
    print(f"[learning-campaign-validation] invalid issueCount={len(issues)}")
    for item in issues:
        print(f"[learning-campaign-validation] {item['code']}: {item['detail']}")
    raise SystemExit(1)

print(f"[learning-campaign-validation] valid artifactRoot={root}")
PY
