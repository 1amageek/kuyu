#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ARTIFACT_ROOT="${1:-}"
ALLOW_FAILED="${KUYU_VALIDATE_ALLOW_FAILED:-0}"
KUYU_BIN="${KUYU_BIN:-}"

if [[ -z "$ARTIFACT_ROOT" ]]; then
  echo "usage: $0 <artifact-root>" >&2
  exit 2
fi

ARGS=(validate-learning-campaign --artifact-root "$ARTIFACT_ROOT")
if [[ "$ALLOW_FAILED" == "1" ]]; then
  ARGS+=(--allow-failed)
fi

if [[ -n "$KUYU_BIN" ]]; then
  exec "$KUYU_BIN" "${ARGS[@]}"
fi

exec swift run kuyu "${ARGS[@]}"
