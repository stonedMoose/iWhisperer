#!/bin/bash
# Build and bundle MyWhispers as a proper .app
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="MyWhispers"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
ENTITLEMENTS="$PROJECT_DIR/$APP_NAME.entitlements"
SIGNING_IDENTITY="Apple Development: Julien Lhermite (7BZ7SQPUW6)"

echo "Building whisper.cpp..."
"$SCRIPT_DIR/build-whisper.sh"

echo "Building release..."
cd "$PROJECT_DIR"
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist
cp "$PROJECT_DIR/Sources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Add bundle identifier and executable name to Info.plist
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.mywhispers.app" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 0.1.0" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true

# Generate app icon
echo "Generating app icon..."
ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET_DIR"
ICON_SRC="$PROJECT_DIR/Resources/Assets.xcassets/AppIcon.appiconset"
cp "$ICON_SRC/icon_16.png"   "$ICONSET_DIR/icon_16x16.png"
cp "$ICON_SRC/icon_32.png"   "$ICONSET_DIR/icon_16x16@2x.png"
cp "$ICON_SRC/icon_32.png"   "$ICONSET_DIR/icon_32x32.png"
cp "$ICON_SRC/icon_64.png"   "$ICONSET_DIR/icon_32x32@2x.png"
cp "$ICON_SRC/icon_128.png"  "$ICONSET_DIR/icon_128x128.png"
cp "$ICON_SRC/icon_256.png"  "$ICONSET_DIR/icon_128x128@2x.png"
cp "$ICON_SRC/icon_256.png"  "$ICONSET_DIR/icon_256x256.png"
cp "$ICON_SRC/icon_512.png"  "$ICONSET_DIR/icon_256x256@2x.png"
cp "$ICON_SRC/icon_512.png"  "$ICONSET_DIR/icon_512x512.png"
cp "$ICON_SRC/icon_1024.png" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET_DIR")"

# Update Info.plist to reference the icns file
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP_BUNDLE/Contents/Info.plist"

# Sign the app bundle with entitlements
echo "Signing app bundle..."
codesign --force --sign "$SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --deep \
    "$APP_BUNDLE"

echo "Verifying signature..."
codesign --verify --verbose "$APP_BUNDLE"

echo ""
echo "App bundle created and signed at: $APP_BUNDLE"
echo ""
echo "To run: open $APP_BUNDLE"
echo "Or:     $APP_BUNDLE/Contents/MacOS/$APP_NAME"
