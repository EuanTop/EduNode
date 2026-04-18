#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/EduNode/.env"
DERIVED_DATA_PATH="$ROOT/tmp/DerivedData"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

cd "$ROOT"
mkdir -p "$ROOT/tmp"
rm -rf "$DERIVED_DATA_PATH"
xcodebuild \
  -project 'EduNode.xcodeproj' \
  -scheme 'EduNode' \
  -destination 'platform=macOS,variant=Mac Catalyst,name=My Mac' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  test \
  -skip-testing:EduNodeUITests \
  -only-testing:EduNodeTests
