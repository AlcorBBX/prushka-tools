#!/bin/bash
# Wrap the SwiftPM binary into "Prushka L.app". No sandbox entitlement.
# Updates the .app in place so a running instance can rebuild itself safely
# (the live process keeps its mapped inode; a new launch loads the new binary).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

CONFIG="debug"
if [[ "${1:-}" == "--release" ]]; then
  CONFIG="release"
fi

swift build -c "${CONFIG}"

BIN="${ROOT}/.build/${CONFIG}/PrushkaDev"
APP="${ROOT}/dist/Prushka L.app"
ICON="${ROOT}/Resources/AppIcon.icns"

# Drop the old product name if present; do not wipe Prushka L.app while updating.
rm -rf "${ROOT}/dist/PrushkaDev.app"

mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

# Copy via a temp name then replace, so a partial copy cannot leave a truncated binary.
TMP_BIN="${APP}/Contents/MacOS/PrushkaDev.new"
cp "${BIN}" "${TMP_BIN}"
chmod +x "${TMP_BIN}"
mv -f "${TMP_BIN}" "${APP}/Contents/MacOS/PrushkaDev"

cp "${ROOT}/Info.plist" "${APP}/Contents/Info.plist"
if [[ -f "${ICON}" ]]; then
  cp "${ICON}" "${APP}/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc signature, no entitlements — App Sandbox stays off.
codesign --force --sign - "${APP}"

echo "Built ${APP}"
