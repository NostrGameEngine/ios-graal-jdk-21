#!/usr/bin/env bash
set -euo pipefail
MX_DIR="${MX_DIR:-$HOME/.mx}"
if [ ! -d "$MX_DIR/.git" ]; then
  git clone --depth 1 https://github.com/graalvm/mx.git "$MX_DIR"
fi
echo "$MX_DIR" >> "$GITHUB_PATH"
export PATH="$MX_DIR:$PATH"
mx --version
