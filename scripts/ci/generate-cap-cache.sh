#!/usr/bin/env bash
set -euo pipefail
TARGET="${1:?target required}"
SDK="${2:?sdk required}"
MIN_IOS_VERSION="${MIN_IOS_VERSION:-15.0}"
ENABLE_MONITORING="${ENABLE_MONITORING:-false}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST="$ROOT/dist/$TARGET"
WORK="$ROOT/build/cap-cache-generator-$TARGET"
CAP_DIR="$DIST/cap"
OPENJDK="$ROOT/labs-openjdk/labs-openjdk-21"
mkdir -p "$CAP_DIR" "$(dirname "$WORK")"
GRAALVM_HOME="${GRAALVM_HOME:-}"
if [ -z "$GRAALVM_HOME" ]; then
  GRAALVM_HOME="$(find "$OPENJDK/build" -path '*/images/graal-builder-image' -type d | head -n 1 || true)"
fi
if [ -z "$GRAALVM_HOME" ] || [ ! -x "$GRAALVM_HOME/bin/native-image" ]; then
  echo "Cannot find native-image. Set GRAALVM_HOME or build graal-builder-image first." >&2
  exit 1
fi
echo "CAP cache native-image: $GRAALVM_HOME/bin/native-image"
"$GRAALVM_HOME/bin/native-image" --version
rm -rf "$WORK"
git clone --depth 1 https://github.com/NostrGameEngine/cap-cache-generator.git "$WORK"
export GRAALVM_HOME
export SDKROOT="$(xcrun --sdk "$SDK" --show-sdk-path)"
export CC="$(xcrun --sdk "$SDK" --find clang)"
export CXX="$(xcrun --sdk "$SDK" --find clang++)"
if [ "$SDK" = "iphonesimulator" ]; then
  APPLE_TARGET="arm64-apple-ios${MIN_IOS_VERSION}-simulator"
else
  APPLE_TARGET="arm64-apple-ios${MIN_IOS_VERSION}"
fi
export CFLAGS="${CFLAGS:-} -target $APPLE_TARGET -isysroot $SDKROOT"
export CPPFLAGS="${CPPFLAGS:-} -target $APPLE_TARGET -isysroot $SDKROOT"
export LDFLAGS="${LDFLAGS:-} -target $APPLE_TARGET -isysroot $SDKROOT"
echo "CAP cache target: $TARGET"
echo "SDKROOT=$SDKROOT"
echo "CC=$CC"
echo "CXX=$CXX"
echo "CFLAGS=$CFLAGS"
echo "CPPFLAGS=$CPPFLAGS"
echo "LDFLAGS=$LDFLAGS"
echo "ENABLE_MONITORING=$ENABLE_MONITORING"
cd "$WORK"
./gradlew --no-daemon build
LIBS_DIR="$WORK/build/libs"
IOS_LIB_DIR="$LIBS_DIR/ios"
DUMMY_JAR="$(find "$LIBS_DIR" -maxdepth 1 -name '*.jar' -type f | head -n 1 || true)"
if [ -z "$DUMMY_JAR" ]; then
  echo "Could not find cap-cache-generator jar under $LIBS_DIR" >&2
  exit 1
fi
rm -rf "$IOS_LIB_DIR"
mkdir -p "$IOS_LIB_DIR"
NATIVE_IMAGE_ARGS=(
  "$GRAALVM_HOME/bin/native-image"
  -cp "$DUMMY_JAR"
  --no-server
  -H:+UnlockExperimentalVMOptions
  -R:-UsePerfData
  -H:+ExitAfterRelocatableImageWrite
  -H:+SharedLibrary
  "-H:TempDirectory=$LIBS_DIR/ios-graal-cap-cache"
  -H:Name=usercode
  -H:+AddAllCharsets
  -H:-DeadlockWatchdogExitOnTimeout
  -H:DeadlockWatchdogInterval=0
  -H:+RemoveSaturatedTypeFlows
  -H:-SpawnIsolates
  -H:PageSize=16384
  -H:EnableURLProtocols=http,https,jar
  -H:+PrintAnalysisCallTree
  -H:Log=registerResource:
  -Djdk.internal.lambda.eagerlyInitialize=false
  -H:+ReportExceptionStackTraces
  -Dsvm.targetName=iOS
  -Dsvm.targetArch=arm64
  -H:CompilerBackend=lir
  '-Dsvm.platform=org.graalvm.nativeimage.Platform$IOS_AARCH64'
  --no-fallback
)
if [ "$ENABLE_MONITORING" = "true" ]; then
  NATIVE_IMAGE_ARGS+=(--enable-monitoring=heapdump,jfr)
fi
NATIVE_IMAGE_ARGS+=(
  -H:+NewCAPCache
  -H:+ExitAfterCAPCache
  "-H:CAPCacheDir=$IOS_LIB_DIR"
)
printf '%q ' "${NATIVE_IMAGE_ARGS[@]}"
printf '\n'
"${NATIVE_IMAGE_ARGS[@]}"
FOUND="$(find build -path '*libs*' -name '*.cap' -type f | wc -l | tr -d ' ')"
if [ "$FOUND" = "0" ]; then
  echo "No CAP files generated" >&2
  find build -type f | sort >&2 || true
  exit 1
fi
find build -path '*libs*' -name '*.cap' -type f -exec cp {} "$CAP_DIR/" \;
echo "Wrote CAP files to $CAP_DIR"
ls -lh "$CAP_DIR"
