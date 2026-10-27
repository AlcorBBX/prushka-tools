#!/bin/bash
# Wrap the SwiftPM binary into "Prushka L.app". No sandbox entitlement.
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

rm -rf "${APP}"
# Remove previous name if present.
rm -rf "${ROOT}/dist/PrushkaDev.app"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN}" "${APP}/Contents/MacOS/PrushkaDev"
cp "${ROOT}/Info.plist" "${APP}/Contents/Info.plist"
if [[ -f "${ICON}" ]]; then
  cp "${ICON}" "${APP}/Contents/Resources/AppIcon.icns"
fi
chmod +x "${APP}/Contents/MacOS/PrushkaDev"

# Ad-hoc signature, no entitlements — App Sandbox stays off.
codesign --force --sign - "${APP}"

echo "Built ${APP}"
