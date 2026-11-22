#!/usr/bin/env bash
# Verify architecture and Mach-O minimum OS for the three release-critical
# binaries: Swift app, Node, and every node-pty addon. Also checks spawn-helper
# when a node-pty layout contains one.
set -euo pipefail

APP="${1:?usage: check-minos.sh <Switchboard.app>}"
MAX_MINOS="10.15"

version_le() {
  awk -v actual="$1" -v maximum="$2" 'BEGIN {
    split(actual, a, "."); split(maximum, b, ".");
    for (i = 1; i <= 3; i++) {
      av = (a[i] == "" ? 0 : a[i]) + 0;
      bv = (b[i] == "" ? 0 : b[i]) + 0;
      if (av < bv) exit 0;
      if (av > bv) exit 1;
    }
    exit 0;
  }'
}

check_binary() {
  label="$1"
  binary="$2"
  [ -f "$binary" ] || { echo "missing $label: $binary" >&2; return 1; }
  file -b "$binary" | grep -q 'Mach-O' || { echo "not Mach-O: $binary" >&2; return 1; }
  arches="$(lipo -archs "$binary")"
  [ "$arches" = "x86_64" ] || { echo "$label has unexpected arches: $arches" >&2; return 1; }
  minos="$(otool -l "$binary" | awk '
    $1 == "cmd" && $2 == "LC_BUILD_VERSION" { build = 1; legacy = 0; next }
    $1 == "cmd" && $2 == "LC_VERSION_MIN_MACOSX" { legacy = 1; build = 0; next }
    build && $1 == "minos" { print $2; exit }
    legacy && $1 == "version" { print $2; exit }
  ')"
  [ -n "$minos" ] || { echo "$label has no macOS minimum load command" >&2; return 1; }
  version_le "$minos" "$MAX_MINOS" || {
    echo "$label minos $minos exceeds $MAX_MINOS" >&2
    return 1
  }
  echo "MINOS $label=$minos arch=$arches path=${binary#"$APP/"}"
}

check_binary app "$APP/Contents/MacOS/Switchboard"
check_binary node "$APP/Contents/Resources/runtime/bin/node"

pty_count=0
while IFS= read -r -d '' pty; do
  pty_count=$((pty_count + 1))
  check_binary "pty.node[$pty_count]" "$pty"
done < <(find "$APP/Contents/Resources/runtime/cli/node_modules/node-pty" -type f -name pty.node -print0)
[ "$pty_count" -ge 1 ] || { echo "no pty.node found" >&2; exit 1; }

helper_count=0
while IFS= read -r -d '' helper; do
  file -b "$helper" | grep -q 'Mach-O' || continue
  helper_count=$((helper_count + 1))
  check_binary "spawn-helper[$helper_count]" "$helper"
done < <(find "$APP/Contents/Resources/runtime/cli/node_modules/node-pty" -type f -name spawn-helper -print0)

echo "MINOS verified: app=1 node=1 pty=$pty_count spawn-helper=$helper_count max=$MAX_MINOS"
