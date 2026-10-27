#!/bin/sh
# Install the signed distro pkg using its static binary. This is needed once
# on older images whose NextBSD pkg rejects a foreign distribution's pkg.
set -eu
TOP=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
archive=$(cd "$(dirname "${1:?usage: bootstrap-pkg.sh <pkg-version.pkg>}")" && pwd)/$(basename "$1")
ROOT=${STEPBSD_ROOT:-/}
[ "$(id -u)" = 0 ] || { echo 'Run as root.' >&2; exit 1; }
openssl dgst -sha256 -verify "$TOP/keys/StepBSD.pub" -signature "$archive.sig" "$archive"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT INT TERM
tar -xOf "$archive" /usr/sbin/pkg-static > "$temporary/pkg-static"
chmod 0500 "$temporary/pkg-static"
[ "$("$temporary/pkg-static" query -F "$archive" %n)" = pkg ]
"$temporary/pkg-static" -r "$ROOT" add -f "$archive"
