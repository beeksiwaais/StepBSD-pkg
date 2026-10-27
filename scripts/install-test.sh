#!/bin/sh
# Exercise the package manager actually shipped, not just the host's pkg.
set -eu
TOP=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
OUT=$(cd "${1:?usage: install-test.sh <repository>}" && pwd)
WORK=${TEST_WORKDIR:-$TOP/.work/install-test}
mkdir -p "$WORK"
WORK=$(cd "$WORK" && pwd)
R=$WORK/root
REPOS=$WORK/repos
SERVER=
cleanup() {
    [ -z "$SERVER" ] || { kill "$SERVER" 2>/dev/null || true; wait "$SERVER" 2>/dev/null || true; }
    umount "$R/dev" 2>/dev/null || true
}
trap cleanup EXIT INT TERM
cleanup
rm -rf "$R" "$REPOS"
mkdir -p "$R/private/etc" "$R/private/var" "$R/private/tmp" "$R/dev" "$REPOS"
for d in etc var tmp; do ln -s "private/$d" "$R/$d"; done
chmod 1777 "$R/private/tmp"
arch=$(uname -m)
case "$arch" in arm64) abiarch=aarch64 ;; *) abiarch=$arch ;; esac
OSVERSION=$(uname -K)
export ABI="FreeBSD:15:$abiarch" OSVERSION IGNORE_OSVERSION=yes ASSUME_ALWAYS_YES=yes
cat > "$REPOS/NextBSD.conf" <<CONF
NextBSD: { url: "https://github.com/nextbsd/nextbsd-pkg/releases/download/continuous-$arch", signature_type: none }
CONF
signature='signature_type: none'
if [ "${TEST_SIGNED_REPO:-0}" = 1 ]; then
    signature="signature_type: pubkey, pubkey: \"$TOP/keys/StepBSD.pub\""
fi
cat > "$REPOS/StepBSD.conf" <<CONF
StepBSD: { url: "file://$OUT", $signature, priority: 100 }
CONF
pkg -r "$R" -R "$REPOS" update -f
pkg -r "$R" -R "$REPOS" install -y pkg
P=$R/usr/sbin/pkg-static
"$P" -r "$R" -R "$REPOS" install -y StepBSD-xorg
"$P" -r "$R" check -d -s -a
"$P" -r "$R" info -e StepBSD-xorg
if "$P" -r "$R" info -e NextBSD-xlibre; then echo 'XLibre was installed' >&2; exit 1; fi
[ "$("$P" -r "$R" query %R pkg)" = StepBSD ]
expected_commit=$(git -c safe.directory="$TOP" -C "$TOP" rev-parse HEAD)
for recipe in pkg xorg; do
    [ "$(cat "$R/usr/share/stepbsd/packages/$recipe/recipe-commit")" = "$expected_commit" ]
done
mount -t devfs devfs "$R/dev"
chroot "$R" /usr/bin/env LD_LIBRARY_PATH=/usr/X11/lib:/usr/lib/system /usr/X11/bin/Xorg -version > "$WORK/Xorg-version.log" 2>&1
grep -Eq 'X.Org X Server (1\.)?21\.1\.25' "$WORK/Xorg-version.log"
cookie=$(openssl rand -hex 16)
chroot "$R" /usr/bin/env HOME=/tmp LD_LIBRARY_PATH=/usr/X11/lib:/usr/lib/system /usr/X11/bin/xauth -f /tmp/test.auth add :93 . "$cookie"
chroot "$R" /usr/bin/env LD_LIBRARY_PATH=/usr/X11/lib:/usr/lib/system \
    /usr/X11/bin/Xvfb :93 -screen 0 800x600x24 -nolisten tcp -auth /tmp/test.auth > "$WORK/Xvfb.log" 2>&1 &
SERVER=$!
ready=0
attempt=0
while [ "$attempt" -lt 50 ]; do
    attempt=$((attempt + 1))
    if chroot "$R" /usr/bin/env DISPLAY=:93 XAUTHORITY=/tmp/test.auth LD_LIBRARY_PATH=/usr/X11/lib:/usr/lib/system \
        /usr/X11/bin/xdpyinfo > "$WORK/xdpyinfo.log" 2>&1; then ready=1; break; fi
    kill -0 "$SERVER" || { cat "$WORK/Xvfb.log"; exit 1; }
    sleep .2
done
[ "$ready" = 1 ] || { cat "$WORK/Xvfb.log"; exit 1; }
grep -q '800x600 pixels' "$WORK/xdpyinfo.log"
chroot "$R" /usr/bin/env DISPLAY=:93 XAUTHORITY=/tmp/test.auth LD_LIBRARY_PATH=/usr/X11/lib:/usr/lib/system /usr/X11/bin/setxkbmap fr
chroot "$R" /usr/bin/env DISPLAY=:93 XAUTHORITY=/tmp/test.auth LD_LIBRARY_PATH=/usr/X11/lib:/usr/lib/system /usr/X11/bin/xinput list > "$WORK/xinput.log"
# An untrusted local package may not replace a file in the system domain.
mkdir -p "$WORK/fixture/System" "$WORK/fixture-repo"
echo forbidden > "$WORK/fixture/System/stepbsd-policy-probe"
cat > "$WORK/fixture-manifest" <<MANIFEST
name: StepBSD-policy-probe
origin: test/policy-probe
version: "1"
comment: "negative policy test"
desc: "negative policy test"
maintainer: "rtp@beeksiwaais.fr"
www: "https://github.com/beeksiwaais/StepBSD-pkg"
prefix: /
MANIFEST
echo /System/stepbsd-policy-probe > "$WORK/fixture-plist"
pkg create -M "$WORK/fixture-manifest" -p "$WORK/fixture-plist" -r "$WORK/fixture" -o "$WORK/fixture-repo"
if "$P" -r "$R" -R "$REPOS" add "$WORK/fixture-repo/StepBSD-policy-probe-1.pkg" > "$WORK/policy.log" 2>&1; then
    echo 'foreign package was allowed into /System' >&2; exit 1
fi
grep -q 'may only install under' "$WORK/policy.log"
[ ! -e "$R/System/stepbsd-policy-probe" ]
# Even a NextBSD-marked local archive may not replace StepBSD's pkg.
sed -e 's/name: StepBSD-policy-probe/name: pkg/' -e 's|origin: test/policy-probe|origin: nextbsd/pkg|' \
    -e 's/version: "1"/version: "99"/' "$WORK/fixture-manifest" > "$WORK/pkg-fixture-manifest"
echo 'annotations: { "org.nextbsd.origin": "NextBSD" }' >> "$WORK/pkg-fixture-manifest"
pkg create -M "$WORK/pkg-fixture-manifest" -p "$WORK/fixture-plist" -r "$WORK/fixture" -o "$WORK/fixture-repo"
if "$P" -r "$R" -R "$REPOS" add -f "$WORK/fixture-repo/pkg-99.pkg" > "$WORK/pkg-local-policy.log" 2>&1; then
    echo 'NextBSD package file replaced StepBSD pkg' >&2; exit 1
fi
grep -q 'pkg comes only from StepBSD' "$WORK/pkg-local-policy.log"
# Publish the same higher-version candidate under NextBSD's repository name;
# ordinary repository jobs must filter it out before planning an upgrade.
pkg repo "$WORK/fixture-repo"
mkdir -p "$WORK/fixture-repos"
cat > "$WORK/fixture-repos/NextBSD.conf" <<CONF
NextBSD: { url: "file://$WORK/fixture-repo", signature_type: none }
CONF
"$P" -r "$R" -R "$WORK/fixture-repos" update -f
"$P" -r "$R" -R "$WORK/fixture-repos" rquery -r NextBSD '%n %v' pkg | grep -q 'pkg 99'
"$P" -d -r "$R" -R "$WORK/fixture-repos" install -n -r NextBSD pkg > "$WORK/pkg-remote-policy.log" 2>&1 || true
grep -q 'StepBSD: ignoring pkg-99 from repository NextBSD' "$WORK/pkg-remote-policy.log"
if grep -Eq '^[[:space:]]+pkg:.*99' "$WORK/pkg-remote-policy.log"; then
    echo 'NextBSD repository can replace StepBSD pkg' >&2; exit 1
fi
[ "$("$P" -r "$R" query %v pkg)" = "$(cat "$TOP/packages/pkg/version")" ]
echo 'PASS: own pkg installs StepBSD X.Org and NextBSD libraries; Xvfb, XKB, input queries and distribution upgrade policy work'
