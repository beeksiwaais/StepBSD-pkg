#!/bin/sh
set -eu
TOP=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
OUT=${1:?usage: sign-repository.sh <repository>}
: "${REPO_SIGNING_KEY:?set REPO_SIGNING_KEY to the private RSA key file}"
pkg repo "$OUT" "$REPO_SIGNING_KEY"
for package in "$OUT"/StepBSD-*.pkg "$OUT"/pkg-[0-9]*.pkg; do
    [ -f "$package" ] || continue
    openssl dgst -sha256 -sign "$REPO_SIGNING_KEY" -out "$package.sig" "$package"
    openssl dgst -sha256 -verify "$TOP/keys/StepBSD.pub" -signature "$package.sig" "$package"
done
