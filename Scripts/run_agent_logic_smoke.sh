#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_BIN="$(mktemp /tmp/edunode-agent-smoke.XXXXXX)"
trap 'rm -f "$TMP_BIN"' EXIT

xcrun swiftc \
  "$ROOT_DIR/EduNode/Features/Agents/EduAgentLogicCore.swift" \
  "$ROOT_DIR/EduNode/Features/Agents/EduLessonTemplateParser.swift" \
  "$ROOT_DIR/Scripts/agent_logic_smoke.swift" \
  -o "$TMP_BIN"

"$TMP_BIN"
