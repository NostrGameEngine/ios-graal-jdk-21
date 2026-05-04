#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OPENJDK="$ROOT/labs-openjdk/labs-openjdk-21"
PATCH="$ROOT/labs-openjdk/ios-jdk.patch"
if ! git -C "$OPENJDK" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Initializing submodule: $OPENJDK"
  git -C "$ROOT" submodule sync --recursive
  git -C "$ROOT" submodule update --init --recursive labs-openjdk/labs-openjdk-21
fi
if ! git -C "$OPENJDK" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Missing submodule after initialization attempt: $OPENJDK" >&2
  exit 1
fi
cd "$OPENJDK"
if git apply --reverse --check "$PATCH" >/dev/null 2>&1; then
  echo "OpenJDK iOS patch already applied"
else
  echo "Applying OpenJDK iOS patch"
  git apply "$PATCH"
fi
