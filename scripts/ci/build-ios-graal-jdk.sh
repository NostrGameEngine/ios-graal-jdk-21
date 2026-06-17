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

version_less_than() {
  awk -v left="$1" -v right="$2" '
    BEGIN {
      split(left, l, ".")
      split(right, r, ".")
      max = (length(l) > length(r)) ? length(l) : length(r)
      for (i = 1; i <= max; i++) {
        lv = (i in l) ? l[i] + 0 : 0
        rv = (i in r) ? r[i] + 0 : 0
        if (lv < rv) exit 0
        if (lv > rv) exit 1
      }
      exit 1
    }
  '
}

clang_supports_flag() {
  local clang_path="$1"
  local flag="$2"
  local sdk_path="$3"
  local apple_target="$4"
  "$clang_path" \
    -target "$apple_target" \
    -isysroot "$sdk_path" \
    -x objective-c++ \
    -fsyntax-only \
    "$flag" \
    - >/dev/null 2>&1 </dev/null
}

append_build_setting() {
  local name="$1"
  local value="$2"
  local existing="${!name:-}"
  if [ -n "$existing" ]; then
    printf '%s=%s %s\n' "$name" "$existing" "$value"
  else
    printf '%s=%s\n' "$name" "$value"
  fi
}

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
CLANGXX="$(xcrun --sdk "$SDK" --find clang++)"
if [ "$SDK" = "iphonesimulator" ]; then
  APPLE_TARGET="arm64-apple-ios${MIN_IOS_VERSION}-simulator"
else
  APPLE_TARGET="arm64-apple-ios${MIN_IOS_VERSION}"
fi
EXTRA_XCODE_ARGS=()
if version_less_than "$MIN_IOS_VERSION" "15.0" && \
  clang_supports_flag "$CLANGXX" "-fno-objc-msgsend-selector-stubs" "$SDKROOT" "$APPLE_TARGET"; then
  EXTRA_XCODE_ARGS+=(
    "$(append_build_setting OTHER_CFLAGS "-fno-objc-msgsend-selector-stubs")"
    "$(append_build_setting OTHER_CPLUSPLUSFLAGS "-fno-objc-msgsend-selector-stubs")"
  )
fi
if [ "${#EXTRA_XCODE_ARGS[@]}" -gt 0 ]; then
  echo "Extra Xcode compiler flags: ${EXTRA_XCODE_ARGS[*]}"
fi
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
if [ "${#EXTRA_XCODE_ARGS[@]}" -gt 0 ]; then
  COMMON_XCODE_ARGS+=("${EXTRA_XCODE_ARGS[@]}")
fi
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
