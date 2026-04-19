#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/EduNode/.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

cd "$ROOT"
TMP_BIN="$(mktemp /tmp/edunode-llm-materialization-smoke.XXXXXX)"
trap 'rm -f "$TMP_BIN"' EXIT

xcrun swiftc \
  -parse-as-library \
  Scripts/llm_materialization_smoke.swift \
  -o "$TMP_BIN"

"$TMP_BIN"
