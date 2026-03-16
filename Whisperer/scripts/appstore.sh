#!/bin/bash
# Build, sign, and package MacWhisperer for App Store submission.
#
# Prerequisites:
#   - "3rd Party Mac Developer Application" certificate in Keychain
#   - "3rd Party Mac Developer Installer" certificate in Keychain
#   - Provisioning profile for App Store distribution
#   - App created in App Store Connect
#
# Usage:
#   bash scripts/appstore.sh                # build + sign + .pkg
#   bash scripts/appstore.sh --upload       # also upload to App Store Connect
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="MacWhisperer"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
PKG_OUTPUT="$PROJECT_DIR/$APP_NAME.pkg"
ENTITLEMENTS="$PROJECT_DIR/MacWhisperer.appstore.entitlements"

# Signing identities
# "Apple Distribution" replaces the old "3rd Party Mac Developer Application" since Xcode 11
APP_SIGNING_IDENTITY="Apple Distribution: Julien Lhermite (3AKV63VNZX)"
# "Mac Installer Distribution" is needed for .pkg — create at developer.apple.com/account/resources/certificates
INSTALLER_SIGNING_IDENTITY="3rd Party Mac Developer Installer: Julien Lhermite (3AKV63VNZX)"

# Provisioning profile
PROVISIONING_PROFILE="${PROVISIONING_PROFILE_PATH:-$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/Mac_Distribution.provisionprofile}"

UPLOAD=false
if [[ "${1:-}" == "--upload" ]]; then
    UPLOAD=true
fi

# ── Step 1: Build ────────────────────────────────────────────────────────
echo "═══ Step 1: Building whisper.cpp + MacWhisperer (release) ═══"
"$SCRIPT_DIR/build-whisper.sh"
cd "$PROJECT_DIR"
swift build -c release

# ── Step 2: Create .app bundle ───────────────────────────────────────────
echo ""
echo "═══ Step 2: Creating .app bundle ═══"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy SPM resource bundles (e.g. KeyboardShortcuts localization)
echo "Copying SPM resource bundles..."
find "$BUILD_DIR" -name '*.bundle' -maxdepth 1 -exec cp -R {} "$APP_BUNDLE/Contents/Resources/" \;

cp "$PROJECT_DIR/Sources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Enrich Info.plist with required App Store fields
PLIST="$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string fr.moose.Whisperer" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string 0.1.0" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${BUILD_NUMBER:-2}" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 14.0" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :LSApplicationCategoryType string public.app-category.productivity" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleSupportedPlatforms array" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleSupportedPlatforms:0 string MacOSX" "$PLIST" 2>/dev/null || true

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
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$PLIST" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$PLIST"

# Embed provisioning profile if provided (strip quarantine attribute)
if [[ -n "$PROVISIONING_PROFILE" && -f "$PROVISIONING_PROFILE" ]]; then
    echo "Embedding provisioning profile..."
    cp "$PROVISIONING_PROFILE" "$APP_BUNDLE/Contents/embedded.provisionprofile"
    xattr -cr "$APP_BUNDLE/Contents/embedded.provisionprofile"
fi

# Compile asset catalog to .car (required by App Store)
echo "Compiling asset catalog..."
xcrun actool "$PROJECT_DIR/Resources/Assets.xcassets" \
    --compile "$APP_BUNDLE/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist /dev/null 2>/dev/null || echo "Warning: actool failed, continuing..."

# Remove .DS_Store, resource forks, and quarantine attributes
find "$APP_BUNDLE" -name '.DS_Store' -delete 2>/dev/null || true
find "$APP_BUNDLE" -name '._*' -delete 2>/dev/null || true
xattr -cr "$APP_BUNDLE"

# ── Step 3: Sign for App Store ───────────────────────────────────────────
echo ""
echo "═══ Step 3: Signing .app for App Store ═══"
codesign --force --sign "$APP_SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --options runtime \
    --deep \
    "$APP_BUNDLE"

echo "Verifying signature..."
codesign --verify --verbose=2 "$APP_BUNDLE"

# ── Step 4: Build .pkg installer ─────────────────────────────────────────
echo ""
echo "═══ Step 4: Building .pkg installer ═══"
rm -f "$PKG_OUTPUT"

# Copy .app via ditto to a temp dir to strip extended attributes / resource forks
CLEAN_DIR=$(mktemp -d)
ditto --noextattr --norsrc "$APP_BUNDLE" "$CLEAN_DIR/$APP_NAME.app"

productbuild \
    --component "$CLEAN_DIR/$APP_NAME.app" /Applications \
    --sign "$INSTALLER_SIGNING_IDENTITY" \
    "$PKG_OUTPUT"

rm -rf "$CLEAN_DIR"

echo "Verifying .pkg..."
pkgutil --check-signature "$PKG_OUTPUT"

echo ""
echo "═══ Package ready: $PKG_OUTPUT ═══"

# ── Step 5 (optional): Upload to App Store Connect ───────────────────────
if $UPLOAD; then
    echo ""
    echo "═══ Step 5: Uploading to App Store Connect ═══"

    API_KEY_DIR="$PROJECT_DIR/fastlane"
    if [[ -f "$API_KEY_DIR/api_key.json" ]]; then
        # Extract API key info from Fastlane's api_key.json
        ISSUER_ID=$(python3 -c "import json; print(json.load(open('$API_KEY_DIR/api_key.json'))['issuer_id'])")
        KEY_ID=$(python3 -c "import json; print(json.load(open('$API_KEY_DIR/api_key.json'))['key_id'])")
        KEY_FILE=$(python3 -c "import json; print(json.load(open('$API_KEY_DIR/api_key.json'))['key_filepath'])")

        xcrun altool --upload-package "$PKG_OUTPUT" \
            --type macos \
            --bundle-id "fr.moose.Whisperer" \
            --bundle-version "${BUILD_NUMBER:-2}" \
            --bundle-short-version-string "0.1.0" \
            --apiKey "$KEY_ID" \
            --apiIssuer "$ISSUER_ID" \
            --apple-id "6760629108"

        echo "Upload complete!"
    else
        echo "ERROR: No API key found at $API_KEY_DIR/api_key.json"
        echo "Create one at https://appstoreconnect.apple.com/access/integrations/api"
        echo ""
        echo "Or upload manually:"
        echo "  xcrun altool --upload-package $PKG_OUTPUT --type macos \\"
        echo "    --bundle-id fr.moose.Whisperer \\"
        echo "    --apiKey YOUR_KEY_ID --apiIssuer YOUR_ISSUER_ID"
        exit 1
    fi
else
    echo ""
    echo "To upload to App Store Connect, run:"
    echo "  bash scripts/appstore.sh --upload"
    echo ""
    echo "Or manually:"
    echo "  xcrun altool --upload-package $PKG_OUTPUT --type macos \\"
    echo "    --bundle-id fr.moose.Whisperer \\"
    echo "    --apiKey YOUR_KEY_ID --apiIssuer YOUR_ISSUER_ID"
fi
