#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Wordie"

cd "$PROJECT_DIR"

# Quit any running instances
osascript -e "tell application \"${APP_NAME}\" to quit" 2>/dev/null || true
sleep 0.5
# Force kill if it didn't quit gracefully
pkill -x "${APP_NAME}" 2>/dev/null || true
sleep 0.5

# Build and bundle
./scripts/bundle.sh

# Remove old version and install
rm -rf "/Applications/${APP_NAME}.app"
cp -r "build/${APP_NAME}.app" /Applications/

# Clear icon cache so the icon shows up correctly
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user 2>/dev/null || true

echo ""
echo "✅ Installed to /Applications/${APP_NAME}.app"
echo ""
echo "Launching..."
open "/Applications/${APP_NAME}.app"
