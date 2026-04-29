#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ARTIFACT_ROOT="${1:-${TMPDIR:-/tmp}/kuyu-training-harness-$(date +%Y%m%d-%H%M%S)}"
TIMEOUT_SECONDS="${KUYU_HARNESS_TIMEOUT_SECONDS:-360}"

python3 - "$TIMEOUT_SECONDS" swift run kuyu check-training-harness --artifact-root "$ARTIFACT_ROOT" <<'PY'
import subprocess
import sys

timeout = int(sys.argv[1])
command = sys.argv[2:]
sys.exit(subprocess.run(command, timeout=timeout).returncode)
PY

python3 - "$ARTIFACT_ROOT/training-harness-summary.json" <<'PY'
import json
import sys

summary_path = sys.argv[1]
with open(summary_path, "r", encoding="utf-8") as handle:
    summary = json.load(handle)

if not summary.get("environmentReady"):
    raise SystemExit("environmentReady=false")
if not summary.get("allPassed"):
    raise SystemExit("allPassed=false")
if not summary.get("probes"):
    raise SystemExit("probes is empty")

for probe in summary["probes"]:
    if probe.get("harnessSatisfied"):
        print(
            "[harness-script] harness-satisfied "
            f"task={probe.get('task')} attempt={probe.get('attempt')} "
            f"taskSolved={probe.get('taskSolved')} artifact={probe.get('artifactPath')}"
        )
        break
else:
    raise SystemExit("no harness-satisfied probe found")

print(f"[harness-script] summary={summary_path}")
PY
