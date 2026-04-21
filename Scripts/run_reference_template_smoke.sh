#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_BIN="$(mktemp "$ROOT/tmp/reference-template-smoke.XXXXXX")"
trap 'rm -f "$TMP_BIN"' EXIT

swiftc \
  "$ROOT/EduNode/Features/Agents/EduLessonTemplateParser.swift" \
  "$ROOT/EduNode/Features/Agents/EduLessonReferenceDocument.swift" \
  "$ROOT/Scripts/reference_template_smoke.swift" \
  -o "$TMP_BIN"

"$TMP_BIN" "$@"
