#!/bin/bash
set -euo pipefail

APP_NAME="Claude Usage Counter"
BINARY_NAME="ClaudeUsageCounter"
BUNDLE_ID="com.lazymodthai.claude-usage-counter"
VERSION="1.0.0"
BUILD_DIR="build"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"

echo "🔨 Building ${APP_NAME}..."

# Build release binary
swift build -c release --arch arm64 --arch x86_64 2>&1

echo "📦 Creating .app bundle..."

# Clean and create bundle structure
rm -rf "${APP_PATH}"
mkdir -p "${APP_PATH}/Contents/MacOS"
mkdir -p "${APP_PATH}/Contents/Resources"

# Copy universal binary
cp ".build/apple/Products/Release/${BINARY_NAME}" "${APP_PATH}/Contents/MacOS/${APP_NAME}" 2>/dev/null || \
cp ".build/release/${BINARY_NAME}" "${APP_PATH}/Contents/MacOS/${APP_NAME}"

chmod +x "${APP_PATH}/Contents/MacOS/${APP_NAME}"

# Write Info.plist
cat > "${APP_PATH}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 lazymodthai. MIT License.</string>
</dict>
</plist>
PLIST

# Write PkgInfo
printf "APPL????" > "${APP_PATH}/Contents/PkgInfo"

echo ""
echo "✅ Built: ${APP_PATH}"
echo ""
echo "To install: cp -r \"${APP_PATH}\" /Applications/"
echo "To run now: open \"${APP_PATH}\""
