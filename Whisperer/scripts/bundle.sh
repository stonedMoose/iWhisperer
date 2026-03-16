#!/bin/bash
# Build and bundle MacWhisperer as a proper .app
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="MacWhisperer"
BUILD_DIR="$PROJECT_DIR/.build/release"
# Resolve symlink so find works without -L
RESOLVED_BUILD_DIR="$(cd "$PROJECT_DIR/.build/release" && pwd -P)"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
DMG_OUTPUT="$PROJECT_DIR/$APP_NAME.dmg"
ENTITLEMENTS="$PROJECT_DIR/MacWhisperer.entitlements"
SIGNING_IDENTITY="Apple Development: Julien Lhermite (7BZ7SQPUW6)"

echo "Building whisper.cpp..."
"$SCRIPT_DIR/build-whisper.sh"

echo "Building release..."
cd "$PROJECT_DIR"
swift build -c release

# Patch SPM's generated resource_bundle_accessor to also look in
# Bundle.main.resourceURL (Contents/Resources/) which is where we place
# resource bundles in the .app. Without this, Bundle.module uses
# Bundle.main.bundleURL (the .app root) which fails codesign rules.
echo "Patching SPM resource bundle accessors..."
for accessor in "$RESOLVED_BUILD_DIR"/*.build/DerivedSources/resource_bundle_accessor.swift; do
    [ -f "$accessor" ] || continue
    if ! grep -q 'resourceURL' "$accessor"; then
        # Use a temp file to avoid macOS sed -i quirks
        tmp="$accessor.tmp"
        sed 's/Bundle\.main\.bundleURL\.appendingPathComponent/(Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent/' "$accessor" > "$tmp"
        mv "$tmp" "$accessor"
        echo "  Patched: $(basename "$(dirname "$(dirname "$accessor")")")"
    fi
done

# Rebuild after patching (only recompiles changed files)
echo "Rebuilding with patched accessors..."
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$RESOLVED_BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy SPM resource bundles into Contents/Resources/ (standard .app layout).
echo "Copying SPM resource bundles..."
find "$RESOLVED_BUILD_DIR" -name '*.bundle' -maxdepth 1 -exec cp -R {} "$APP_BUNDLE/Contents/Resources/" \;

# Copy Info.plist
cp "$PROJECT_DIR/Sources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Add bundle identifier and executable name to Info.plist
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string fr.moose.Whisperer" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
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

# Sign nested resource bundles, then the app itself
echo "Signing app bundle..."
find "$APP_BUNDLE/Contents/Resources" -name '*.bundle' -exec \
    codesign --force --sign "$SIGNING_IDENTITY" {} \;
codesign --force --sign "$SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    "$APP_BUNDLE"

echo "Verifying signature..."
codesign --verify --verbose "$APP_BUNDLE"

echo ""
echo "App bundle created and signed at: $APP_BUNDLE"

# Create DMG with Applications symlink (drag-to-install layout)
echo "Creating DMG..."
rm -f "$DMG_OUTPUT"

DMG_STAGING="$PROJECT_DIR/.build/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_OUTPUT"

rm -rf "$DMG_STAGING"

echo ""
echo "DMG created at: $DMG_OUTPUT"
echo ""
echo "To run: open $APP_BUNDLE"
echo "Or:     $APP_BUNDLE/Contents/MacOS/$APP_NAME"
