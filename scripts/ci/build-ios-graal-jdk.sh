#!/usr/bin/env bash
set -euo pipefail
TARGET="${1:?target required: iphoneos-arm64 or iphonesimulator-arm64}"
SDK="${2:?sdk required: iphoneos or iphonesimulator}"
ARCH="${ARCH:-arm64}"
CONFIG="${CONFIG:-Release-ios}"
MIN_IOS_VERSION="${MIN_IOS_VERSION:-15.0}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OPENJDK="$ROOT/labs-openjdk/labs-openjdk-21"
DIST="$ROOT/dist/$TARGET"
BUILD_ROOT="$ROOT/build/$TARGET"
BOOT_JDK_DIR="$ROOT/build/boot-jdk"
mkdir -p "$DIST" "$BUILD_ROOT" "$BOOT_JDK_DIR"
export PATH="$HOME/.mx:$PATH"
if [ ! -x "$BOOT_JDK_DIR/jdk21/bin/java" ]; then
  mx -y --no-warning fetch-jdk \
    --java-distribution labsjdk-ce-21 \
    --to "$BOOT_JDK_DIR" \
    --alias jdk21
fi
export JAVA_HOME="$BOOT_JDK_DIR/jdk21"
export SDKROOT="$(xcrun --sdk "$SDK" --show-sdk-path)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
echo "JAVA_HOME=$JAVA_HOME"
echo "SDKROOT=$SDKROOT"
echo "TARGET=$TARGET SDK=$SDK ARCH=$ARCH CONFIG=$CONFIG MIN_IOS_VERSION=$MIN_IOS_VERSION"
cd "$OPENJDK"
if [ ! -f "build/labsjdk/spec.gmk" ]; then
  bash configure \
    --with-conf-name=labsjdk \
    --with-version-opt=jvmci-23.1.3-b33 \
    --with-version-pre= \
    --with-vendor-name="GraalVM Community" \
    --with-vendor-url=https://www.graalvm.org/ \
    --with-vendor-bug-url=https://github.com/oracle/graal/issues \
    --with-vendor-vm-bug-url=https://github.com/oracle/graal/issues
fi
make CONF_NAME=labsjdk graal-builder-image
cd "$ROOT"
COMMON_XCODE_ARGS=(
  ARCHS="$ARCH"
  ONLY_ACTIVE_ARCH=NO
  SDKROOT="$SDK"
  IPHONEOS_DEPLOYMENT_TARGET="$MIN_IOS_VERSION"
  SUPPORTED_PLATFORMS="$SDK"
  CONFIGURATION_BUILD_DIR="$BUILD_ROOT/xcode-products"
  SYMROOT="$BUILD_ROOT/symroot"
  OBJROOT="$BUILD_ROOT/objroot"
  DSTROOT="$BUILD_ROOT/dstroot"
)
xcodebuild \
  -project labs-openjdk/svm.openjdk.xcodeproj \
  -target libjava \
  -configuration "$CONFIG" \
  -sdk "$SDK" \
  "${COMMON_XCODE_ARGS[@]}" \
  build
xcodebuild \
  -project svm/svm.graal.xcodeproj \
  -target libjvm \
  -configuration "$CONFIG" \
  -sdk "$SDK" \
  "${COMMON_XCODE_ARGS[@]}" \
  build
LIBJAVA="$(find "$BUILD_ROOT" -name 'libjava.a' -type f | head -n 1 || true)"
LIBJVM="$(find "$BUILD_ROOT" -name 'libjvm.a' -type f | head -n 1 || true)"
if [ -z "$LIBJAVA" ] || [ -z "$LIBJVM" ]; then
  echo "Failed to locate libjava.a/libjvm.a under $BUILD_ROOT" >&2
  find "$BUILD_ROOT" -type f | sort >&2 || true
  exit 1
fi
cp "$LIBJAVA" "$DIST/libjava-release.a"
cp "$LIBJVM" "$DIST/libjvm-release.a"
echo "Wrote:"
ls -lh "$DIST"/*.a
