#!/usr/bin/env bash
# Downloads the OBI release tarball and puts the binary in bin/.
# Usage: install-obi.sh <url> <tarball-name> <bin-dir>
set -euo pipefail

URL="$1"
TARBALL="$2"
BIN_DIR="$3"

if [ -x "$BIN_DIR/obi" ]; then
  echo "$BIN_DIR/obi already present — delete it to force a re-download"
  exit 0
fi

mkdir -p "$BIN_DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "downloading $URL"
echo "(~50 MB — the binary bundles its eBPF programs)"
curl -fL --retry 3 --connect-timeout 20 -o "$tmp/$TARBALL" "$URL"

tar -xzf "$tmp/$TARBALL" -C "$tmp"

# The tarball holds the binary at its root, next to LICENSE/NOTICE/NOTICES.
src="$(find "$tmp" -maxdepth 2 -type f -name obi -perm -u+x | head -1)"
[ -n "$src" ] || { echo "no obi binary inside $TARBALL" >&2; exit 1; }

install -m 0755 "$src" "$BIN_DIR/obi"
echo "installed $BIN_DIR/obi"
