#!/usr/bin/env bash
# Stage the fixed x86_64 Node runtime and reproducibly build cli dependencies
# for macOS 10.15. node-pty is always compiled locally so its minos is explicit.
set -euo pipefail

DEST="${1:?usage: fetch-runtime.sh <dest-dir>}"
MACOS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="$(cd "$MACOS_DIR/.." && pwd)"
NODE_VERSION="${NODE_VERSION:-v20.18.0}"
export MACOSX_DEPLOYMENT_TARGET="10.15"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ "$(uname -m)" != "x86_64" ]; then
  echo "runtime build must run on an Intel (x86_64) macOS host" >&2
  exit 1
fi

TARBALL="node-$NODE_VERSION-darwin-x64.tar.gz"
BASE_URL="https://nodejs.org/dist/$NODE_VERSION"
echo "  ↓ $BASE_URL/$TARBALL" >&2
curl -fsSL "$BASE_URL/$TARBALL" -o "$WORK/$TARBALL"
curl -fsSL "$BASE_URL/SHASUMS256.txt" -o "$WORK/SHASUMS256.txt"
( cd "$WORK" && grep "  $TARBALL\$" SHASUMS256.txt | shasum -a 256 -c - )
tar -xzf "$WORK/$TARBALL" -C "$WORK"

mkdir -p "$DEST/bin" "$DEST/cli"
cp "$WORK/node-$NODE_VERSION-darwin-x64/bin/node" "$DEST/bin/node"
chmod +x "$DEST/bin/node"

# npm pack remains the source-of-truth for which cli files ship. The lockfile is
# copied separately because npm intentionally excludes package-lock.json from a
# package tarball; npm ci then fixes the exact dependency graph.
CLI_TARBALL="$(cd "$REPO_DIR/cli" && npm pack --silent --pack-destination "$WORK")"
tar -xzf "$WORK/$CLI_TARBALL" -C "$WORK"
cp -R "$WORK/package/." "$DEST/cli/"
cp "$REPO_DIR/cli/package-lock.json" "$DEST/cli/package-lock.json"

echo "  building cli production deps for x86_64 / macOS 10.15" >&2
(
  cd "$DEST/cli"
  PATH="$DEST/bin:$PATH" \
  npm_config_arch=x64 \
  npm_config_target_arch=x64 \
  npm_config_build_from_source=true \
  npm_config_registry=https://registry.npmjs.org \
  npm ci --omit=dev --no-audit --no-fund
)

(
  cd "$DEST/cli"
  PATH="$DEST/bin:$PATH" node -e 'require("node-pty")'
  PATH="$DEST/bin:$PATH" node scripts/fix-pty-perms.js || true
)

PTY_COUNT="$(find "$DEST/cli/node_modules/node-pty" -type f -name 'pty.node' | wc -l | tr -d ' ')"
[ "$PTY_COUNT" -ge 1 ] || { echo "node-pty build produced no pty.node" >&2; exit 1; }
echo "✓ runtime staged at $DEST"
