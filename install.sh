#!/bin/bash
set -euo pipefail

APP_NAME="Claude Usage Counter"
APP_PATH="build/${APP_NAME}.app"
INSTALL_PATH="/Applications/${APP_NAME}.app"

if [ ! -d "${APP_PATH}" ]; then
    echo "❌ App not found. Run ./build.sh first."
    exit 1
fi

# Kill running instance if any
pkill -f "${APP_NAME}" 2>/dev/null || true
sleep 0.5

echo "📲 Installing to /Applications..."
rm -rf "${INSTALL_PATH}"
cp -r "${APP_PATH}" "${INSTALL_PATH}"

echo "🚀 Launching..."
open "${INSTALL_PATH}"
echo "✅ Done! Look for ⚡ in your menu bar."
