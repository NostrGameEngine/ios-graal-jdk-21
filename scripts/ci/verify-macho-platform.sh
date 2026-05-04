#!/usr/bin/env bash
set -euo pipefail
FILE="${1:?archive path required}"
EXPECTED="${2:?expected platform required: iphoneos or iphonesimulator}"
if [ ! -f "$FILE" ]; then
  echo "Missing file: $FILE" >&2
  exit 1
fi
if [[ "$FILE" != /* ]]; then
  FILE="$PWD/$FILE"
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
pushd "$TMP" >/dev/null
ar -x "$FILE" || { echo "ar failed for $FILE" >&2; exit 1; }
OBJ="$(find . -type f | head -n 1 || true)"
if [ -z "$OBJ" ]; then
  echo "Archive has no object files: $FILE" >&2
  exit 1
fi
INFO="$(xcrun vtool -show-build "$OBJ" 2>/dev/null || xcrun llvm-objdump --macho --private-headers "$OBJ" 2>/dev/null || true)"
popd >/dev/null
echo "$INFO"
case "$EXPECTED" in
  iphoneos)
    if echo "$INFO" | grep -Eiq 'platform[[:space:]]+IOS|LC_VERSION_MIN_IPHONEOS|IPHONEOS'; then
      echo "OK: $FILE is iPhoneOS/device"
      exit 0
    fi
    ;;
  iphonesimulator)
    if echo "$INFO" | grep -Eiq 'platform[[:space:]]+IOSSIMULATOR|IOSSIMULATOR|SIMULATOR'; then
      echo "OK: $FILE is iOS Simulator"
      exit 0
    fi
    ;;
  *)
    echo "Unknown expected platform: $EXPECTED" >&2
    exit 2
    ;;
esac
echo "Platform check failed for $FILE" >&2
echo "Expected: $EXPECTED" >&2
echo "arm64 alone is not enough: iPhoneOS arm64 and iOS Simulator arm64 are different Mach-O platforms." >&2
exit 1
