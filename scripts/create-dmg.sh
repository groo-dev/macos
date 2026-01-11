#!/bin/bash
set -e

# Configuration
APP_NAME="Groo"
VERSION="${1:-1.0.0}"
APP_PATH="${2:-/Users/groo/work/dev.groo.mac/Groo.app}"
OUTPUT_DIR="${3:-/Users/groo/work/dev.groo.mac}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Output
DMG_PATH="$OUTPUT_DIR/${APP_NAME}-${VERSION}.dmg"

# Assets
BACKGROUND="$PROJECT_DIR/dmg-background.png"
VOLUME_ICON="$PROJECT_DIR/Groo/Assets.xcassets/AppIcon.appiconset/icon_512x512.png"

echo "Creating DMG for $APP_NAME v$VERSION..."

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo "Error: App not found at $APP_PATH"
    echo "Usage: $0 [version] [app_path] [output_dir]"
    exit 1
fi

# Check if create-dmg is installed
if ! command -v create-dmg &> /dev/null; then
    echo "Error: create-dmg not found. Install with: brew install create-dmg"
    exit 1
fi

# Unmount existing volume if mounted
hdiutil detach "/Volumes/$APP_NAME" 2>/dev/null || true

# Remove existing DMG
rm -f "$DMG_PATH"

# Create DMG
create-dmg \
  --volname "$APP_NAME" \
  --volicon "$VOLUME_ICON" \
  --background "$BACKGROUND" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "${APP_NAME}.app" 150 200 \
  --hide-extension "${APP_NAME}.app" \
  --app-drop-link 450 200 \
  "$DMG_PATH" \
  "$APP_PATH"

echo ""
echo "DMG created: $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"
