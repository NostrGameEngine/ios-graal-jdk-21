#!/usr/bin/env bash
set -euo pipefail
TARGET="${1:?target required}"
SDK="${2:?sdk required}"
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
rm -rf "$WORK"
git clone --depth 1 https://github.com/NostrGameEngine/cap-cache-generator.git "$WORK"
export GRAALVM_HOME
export SDKROOT="$(xcrun --sdk "$SDK" --show-sdk-path)"
export CC="$(xcrun --sdk "$SDK" --find clang)"
export CXX="$(xcrun --sdk "$SDK" --find clang++)"
if [ "$SDK" = "iphonesimulator" ]; then
  export CFLAGS="${CFLAGS:-} -target arm64-apple-ios15.0-simulator -isysroot $SDKROOT"
  export CPPFLAGS="${CPPFLAGS:-} -target arm64-apple-ios15.0-simulator -isysroot $SDKROOT"
  export LDFLAGS="${LDFLAGS:-} -target arm64-apple-ios15.0-simulator -isysroot $SDKROOT"
else
  export CFLAGS="${CFLAGS:-} -target arm64-apple-ios15.0 -isysroot $SDKROOT"
  export CPPFLAGS="${CPPFLAGS:-} -target arm64-apple-ios15.0 -isysroot $SDKROOT"
  export LDFLAGS="${LDFLAGS:-} -target arm64-apple-ios15.0 -isysroot $SDKROOT"
fi
cd "$WORK"
./gradlew --no-daemon generateCapCache
FOUND="$(find build -path '*libs*' -name '*.cap' -type f | wc -l | tr -d ' ')"
if [ "$FOUND" = "0" ]; then
  echo "No CAP files generated" >&2
  find build -type f | sort >&2 || true
  exit 1
fi
find build -path '*libs*' -name '*.cap' -type f -exec cp {} "$CAP_DIR/" \;
echo "Wrote CAP files to $CAP_DIR"
ls -lh "$CAP_DIR"
