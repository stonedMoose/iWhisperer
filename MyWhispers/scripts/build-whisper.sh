#!/bin/bash
# Build whisper.cpp into a static library with Metal support
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WHISPER_DIR="$PROJECT_DIR/Vendor/whisper.cpp"
BUILD_DIR="$PROJECT_DIR/.build/whisper-cpp"
INSTALL_DIR="$PROJECT_DIR/Vendor/whisper-built"

# Check if already built (skip rebuild for speed)
if [ -f "$INSTALL_DIR/lib/libwhisper.a" ] && [ -f "$INSTALL_DIR/lib/libggml.a" ]; then
    echo "whisper.cpp already built. Run with --clean to rebuild."
    if [ "${1:-}" != "--clean" ]; then
        exit 0
    fi
fi

if [ "${1:-}" = "--clean" ]; then
    rm -rf "$BUILD_DIR" "$INSTALL_DIR"
fi

echo "Building whisper.cpp with Metal support..."
mkdir -p "$BUILD_DIR"

cmake -B "$BUILD_DIR" -S "$WHISPER_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DGGML_ACCELERATE=ON \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_SERVER=OFF \
    -DBUILD_SHARED_LIBS=OFF

cmake --build "$BUILD_DIR" --config Release -j$(sysctl -n hw.logicalcpu)
cmake --install "$BUILD_DIR" --config Release

echo ""
echo "whisper.cpp built successfully:"
echo "  Headers: $INSTALL_DIR/include/"
echo "  Libraries: $INSTALL_DIR/lib/"
ls -la "$INSTALL_DIR/lib/"*.a
