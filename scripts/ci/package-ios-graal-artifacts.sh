#!/usr/bin/env bash
set -euo pipefail
TARGET="${1:?target required}"
MIN_IOS_VERSION="${MIN_IOS_VERSION:-15.0}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST="$ROOT/dist/$TARGET"
ZIP="$ROOT/dist/ios-graal-jdk-21-$TARGET.zip"
if [ ! -d "$DIST" ]; then
  echo "Missing dist target: $DIST" >&2
  exit 1
fi
cat > "$DIST/MANIFEST.txt" <<EOF_MANIFEST
name=ios-graal-jdk-21
target=$TARGET
min_ios_version=$MIN_IOS_VERSION
built_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
repository=${GITHUB_REPOSITORY:-local}
commit=${GITHUB_SHA:-unknown}
EOF_MANIFEST
(cd "$DIST" && shasum -a 256 $(find . -type f | sed 's#^./##' | sort) > SHA256SUMS.txt)
rm -f "$ZIP"
(cd "$ROOT/dist" && zip -r "$(basename "$ZIP")" "$TARGET")
echo "Wrote $ZIP"
ls -lh "$ZIP"
