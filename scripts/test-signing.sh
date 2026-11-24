#!/bin/sh
# Ephemeral trust keys and a deliberately non-executable foreign pkg payload
# exercise real signature verification and cross-ABI metadata operations.
set -eu
TOP=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
OUT=$(cd "${1:?usage: test-signing.sh <repository>}" && pwd)
. "$TOP/scripts/pkg-env.sh"
stepbsd_pkg_target "$(uname -m)"
native_abi=$ABI
case "$STEPBSD_ABI_ARCH" in amd64) foreign_arch=arm64 ;; *) foreign_arch=amd64 ;; esac
check=$(mktemp -d)
trap 'rm -rf "$check"' EXIT INT TERM
mkdir -p "$check/tool/scripts" "$check/tool/keys" "$check/native" "$check/foreign" "$check/stage/usr/sbin"
cp "$TOP/scripts/pkg-env.sh" "$TOP/scripts/sign-repository.sh" "$TOP/scripts/check-repository.sh" "$check/tool/scripts/"
cp "$OUT/"* "$check/native/"
openssl genrsa -out "$check/key.pem" 2048 >/dev/null 2>&1
chmod 600 "$check/key.pem"
openssl rsa -in "$check/key.pem" -pubout -out "$check/tool/keys/StepBSD.pub" >/dev/null 2>&1
stepbsd_pkg_from_repository "$OUT" "$check"
REPO_SIGNING_KEY="$check/key.pem" sh "$check/tool/scripts/sign-repository.sh" "$check/native" "$(uname -m)"
sh "$check/tool/scripts/check-repository.sh" "$check/native" "$(uname -m)"

printf '#!/bin/sh\nexit 98\n' > "$check/stage/usr/sbin/pkg-static"
chmod 0755 "$check/stage/usr/sbin/pkg-static"
printf '/usr/sbin/pkg-static\n' > "$check/plist"
stepbsd_pkg_target "$foreign_arch"
cat > "$check/manifest" <<MANIFEST
name: pkg
origin: stepbsd/cross-metadata-test
version: "1"
comment: "foreign metadata fixture, not a runnable package manager"
desc: "Tests metadata and signing without running the foreign payload."
maintainer: "rtp@beeksiwaais.fr"
www: "https://github.com/beeksiwaais/StepBSD-pkg"
prefix: /
abi: "$ABI"
annotations: { "org.stepbsd.origin": "StepBSD" }
MANIFEST
stepbsd_pkg create -M "$check/manifest" -p "$check/plist" -r "$check/stage" -o "$check/foreign"
STEPBSD_PKG_HOST_REPO="$OUT" REPO_SIGNING_KEY="$check/key.pem" \
    sh "$check/tool/scripts/sign-repository.sh" "$check/foreign" "$foreign_arch"
STEPBSD_PKG_HOST_REPO="$OUT" sh "$check/tool/scripts/check-repository.sh" "$check/foreign" "$foreign_arch"
printf 'PASS: signed native %s and foreign %s metadata; wrong keys rejected and foreign pkg payload never executed\n' "$native_abi" "$ABI"
