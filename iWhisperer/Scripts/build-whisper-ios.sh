#!/bin/bash
set -euo pipefail

# Build whisper.cpp static libraries for iOS arm64
# Requires: CMake, Xcode command line tools

WHISPER_SRC="$(cd "$(dirname "$0")/../../Whisperer/Vendor/whisper.cpp" && pwd)"
OUTPUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/Vendor/whisper-built"
BUILD_DIR="/tmp/whisper-ios-build"

echo "Source:  $WHISPER_SRC"
echo "Output:  $OUTPUT_DIR"
echo "Build:   $BUILD_DIR"

rm -rf "$BUILD_DIR" "$OUTPUT_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR/lib" "$OUTPUT_DIR/include"

cd "$BUILD_DIR"

cmake "$WHISPER_SRC" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
  -DCMAKE_INSTALL_PREFIX="$OUTPUT_DIR" \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DGGML_NATIVE=OFF \
  -DGGML_OPENMP=OFF \
  -DGGML_BLAS=OFF \
  -DWHISPER_COREML=OFF \
  -DBUILD_SHARED_LIBS=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_EXAMPLES=OFF

cmake --build . --config Release -j$(sysctl -n hw.ncpu)

# Copy libraries
find . -name "*.a" -exec cp {} "$OUTPUT_DIR/lib/" \;

# Copy headers
cp "$WHISPER_SRC/include/whisper.h" "$OUTPUT_DIR/include/"
for header in ggml.h ggml-alloc.h ggml-backend.h ggml-metal.h ggml-cpu.h ggml-cpp.h ggml-opt.h gguf.h; do
  cp "$WHISPER_SRC/ggml/include/$header" "$OUTPUT_DIR/include/"
done

echo ""
echo "whisper.cpp built for iOS arm64 at $OUTPUT_DIR"
echo ""
echo "Libraries:"
ls -la "$OUTPUT_DIR/lib/"
echo ""
echo "Headers:"
ls -la "$OUTPUT_DIR/include/"
