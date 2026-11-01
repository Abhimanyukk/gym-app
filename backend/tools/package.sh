#!/bin/sh
# Package only the Pi executable and operator files, never source/secrets/data.
set -eu
[ "$#" -eq 2 ] || { echo "Usage: $0 <ARM64-replab-server> <new.tar.gz>" >&2; exit 2; }
binary=$1
output=$2
[ -f "$binary" ] && [ "$(basename "$binary")" = replab-server ] || { echo "Expected the compiled replab-server binary." >&2; exit 2; }
file "$binary" | grep -qi aarch64 || { echo "This is not a Linux ARM64 binary." >&2; exit 2; }
[ ! -e "$output" ] && [ ! -e "$output.sha256" ] || { echo "Package/checksum already exists; refusing to overwrite." >&2; exit 1; }
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
mkdir -p "$(dirname "$output")"
set -C
tar -czf - -C "$(dirname "$binary")" replab-server -C "$root" deploy tools README.md > "$output"
sha256sum "$output" > "$output.sha256"
echo "Created executable-only Pi deployment package: $output"
