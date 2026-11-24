#!/bin/sh
# Verify the actual catalogue with pkg's signature implementation.
set -eu
TOP=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
OUT=$(cd "${1:?usage: check-repository.sh <repository> <amd64|arm64>}" && pwd)
. "$TOP/scripts/pkg-env.sh"
stepbsd_pkg_target "${2:?set architecture}"
check=$(mktemp -d)
trap 'rm -rf "$check"' EXIT INT TERM
set -- "$OUT"/pkg-[0-9]*.pkg
[ "$#" -eq 1 ] && [ -f "$1" ]
openssl dgst -sha256 -verify "$TOP/keys/StepBSD.pub" -signature "$1.sig" "$1"
stepbsd_pkg_metadata_tool "$OUT" "$check"
mkdir -p "$check/root" "$check/repos"
cat > "$check/repos/StepBSD.conf" <<CONF
StepBSD: { url: "file://$OUT", signature_type: pubkey, pubkey: "$TOP/keys/StepBSD.pub" }
CONF
stepbsd_pkg -r "$check/root" -R "$check/repos" update -f
stepbsd_pkg -r "$check/root" -R "$check/repos" rquery -r StepBSD '%n %v'
# A repository signed by another key must be rejected, even if its name is StepBSD.
openssl genrsa -out "$check/wrong.pem" 2048 >/dev/null 2>&1
openssl rsa -in "$check/wrong.pem" -pubout -out "$check/wrong.pub" >/dev/null 2>&1
mkdir -p "$check/untrusted-root"
sed "s|$TOP/keys/StepBSD.pub|$check/wrong.pub|" "$check/repos/StepBSD.conf" > "$check/repos/WrongKey.conf"
rm "$check/repos/StepBSD.conf"
stepbsd_pkg -r "$check/untrusted-root" -R "$check/repos" update -f > "$check/wrong-key.log" 2>&1 || true
# pkg 2.8 can return success after its failed legacy-catalogue fallback. Check
# the usable catalogue, rather than treating that exit status as verification.
if stepbsd_pkg -r "$check/untrusted-root" -R "$check/repos" rquery -r StepBSD '%n' > "$check/untrusted-packages" 2>/dev/null &&
    [ -s "$check/untrusted-packages" ]; then
    echo 'repository was accepted with the wrong verification key' >&2; exit 1
fi
grep -q 'Invalid signature' "$check/wrong-key.log"
echo 'PASS: signed catalogue accepted; mismatched key rejected'
