#!/bin/sh
# Verify the actual catalogue with pkg's signature implementation.
set -eu
TOP=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
OUT=$(cd "${1:?usage: check-repository.sh <repository> <amd64|arm64>}" && pwd)
case "${2:?set architecture}" in
    arm64) ABI=FreeBSD:15:aarch64 ;;
    amd64) ABI=FreeBSD:15:amd64 ;;
    *) exit 1 ;;
esac
OSVERSION=$(uname -K)
export ABI OSVERSION IGNORE_OSVERSION=yes
check=$(mktemp -d)
trap 'rm -rf "$check"' EXIT INT TERM
mkdir -p "$check/root" "$check/repos"
cat > "$check/repos/StepBSD.conf" <<CONF
StepBSD: { url: "file://$OUT", signature_type: pubkey, pubkey: "$TOP/keys/StepBSD.pub" }
CONF
pkg -r "$check/root" -R "$check/repos" update -f
pkg -r "$check/root" -R "$check/repos" rquery -r StepBSD '%n %v'
# A repository signed by another key must be rejected, even if its name is StepBSD.
openssl genrsa -out "$check/wrong.pem" 2048 >/dev/null 2>&1
openssl rsa -in "$check/wrong.pem" -pubout -out "$check/wrong.pub" >/dev/null 2>&1
mkdir -p "$check/untrusted-root"
sed "s|$TOP/keys/StepBSD.pub|$check/wrong.pub|" "$check/repos/StepBSD.conf" > "$check/repos/WrongKey.conf"
rm "$check/repos/StepBSD.conf"
pkg -r "$check/untrusted-root" -R "$check/repos" update -f > "$check/wrong-key.log" 2>&1 || true
# pkg 2.8 can return success after its failed legacy-catalogue fallback. Check
# the usable catalogue, rather than treating that exit status as verification.
if pkg -r "$check/untrusted-root" -R "$check/repos" rquery -r StepBSD '%n' > "$check/untrusted-packages" 2>/dev/null &&
    [ -s "$check/untrusted-packages" ]; then
    echo 'repository was accepted with the wrong verification key' >&2; exit 1
fi
grep -q 'Invalid signature' "$check/wrong-key.log"
echo 'PASS: signed catalogue accepted; mismatched key rejected'
