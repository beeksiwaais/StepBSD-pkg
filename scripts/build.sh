#!/bin/sh
# Build source recipes on FreeBSD 15 with a pkg-assembled NextBSD sysroot.
# Build-host tools may come from FreeBSD; target files and link inputs may not.
set -eu
TOP=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
WORK=${WORKDIR:-$TOP/.work}
mkdir -p "$WORK" "${1:-$TOP/out}"
WORK=$(cd "$WORK" && pwd)
OUT=$(cd "${1:-$TOP/out}" && pwd)
[ "$#" -eq 0 ] || shift
[ "$(uname -s)" = FreeBSD ] || { echo 'Build on FreeBSD 15 (or in its VM).' >&2; exit 1; }
[ "$(id -u)" = 0 ] || { echo 'Run as root to assemble the target sysroot.' >&2; exit 1; }
# shellcheck source=common.sh
. "$TOP/scripts/common.sh"
ARCH=$(uname -m)
case "$ARCH" in
    arm64) ABIARCH=aarch64; CPU=aarch64; TARGET_TRIPLE=aarch64-unknown-freebsd ;;
    amd64) ABIARCH=amd64; CPU=x86_64; TARGET_TRIPLE=x86_64-unknown-freebsd ;;
    *) die "unsupported architecture $ARCH" ;;
esac
BUILD_TRIPLE=$(cc -dumpmachine)
export BUILD_TRIPLE
JOBS=${JOBS:-$(sysctl -n hw.ncpu)}
OSVERSION=$(uname -K)
export ABI="FreeBSD:15:$ABIARCH" OSVERSION IGNORE_OSVERSION=yes ASSUME_ALWAYS_YES=yes
NEXTBSD_REPO=${NEXTBSD_REPO:-https://github.com/nextbsd/nextbsd-pkg/releases/download/continuous-$ARCH}
mkdir -p "$WORK/repos" "$WORK/pkg-cache"
cat > "$WORK/repos/NextBSD.conf" <<CONF
NextBSD: { url: "$NEXTBSD_REPO", enabled: yes, signature_type: none }
CONF

[ "$#" -gt 0 ] || set -- pkg xorg
for RECIPE do
    case "$RECIPE" in pkg|xorg) ;; *) die "unknown recipe: $RECIPE" ;; esac
    SYSROOT=$WORK/root/$RECIPE
    STAGE=$WORK/package/$RECIPE
    reqs=$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$TOP/packages/$RECIPE/requirements.txt")
    if [ "${REUSE_ROOT:-0}" != 1 ]; then
    rm -rf "$SYSROOT" "$STAGE"
    mkdir -p "$SYSROOT/private/etc" "$SYSROOT/private/var" "$SYSROOT/private/tmp" "$STAGE"
    for d in etc var tmp; do ln -s "private/$d" "$SYSROOT/$d"; done
    pkg -r "$SYSROOT" -o REPOS_DIR="$WORK/repos" -o PKG_CACHEDIR="$WORK/pkg-cache" update -f
    # shellcheck disable=SC2086
    pkg -r "$SYSROOT" -o REPOS_DIR="$WORK/repos" -o PKG_CACHEDIR="$WORK/pkg-cache" install -y $reqs
    if pkg -r "$SYSROOT" info -e NextBSD-xlibre; then die 'XLibre entered the build root'; fi
    else
        [ -d "$STAGE" ] && [ -d "$SYSROOT/usr" ] || die "no build to resume for $RECIPE"
    fi
    # LLVM/FreeBSD build-host tools; the compiler and pkgconf can see only target headers/libs.
    export CC="/usr/bin/clang --target=$TARGET_TRIPLE --sysroot=$SYSROOT -fuse-ld=lld"
    export CXX="/usr/bin/clang++ --target=$TARGET_TRIPLE --sysroot=$SYSROOT -fuse-ld=lld"
    export AR=/usr/bin/llvm-ar RANLIB=/usr/bin/llvm-ranlib STRIP=/usr/bin/llvm-strip
    export PKG_CONFIG=pkgconf PKG_CONFIG_PATH=
    export PKG_CONFIG_LIBDIR="$SYSROOT/usr/X11/lib/pkgconfig:$SYSROOT/usr/libdata/pkgconfig"
    export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
    export CPPFLAGS="-I$SYSROOT/usr/X11/include"
    export CFLAGS="-O2 -pipe -ffile-prefix-map=$WORK=/build -Wno-error=deprecated-declarations"
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS="-L$SYSROOT/usr/X11/lib -Wl,-rpath,/usr/X11/lib"
    cat > "$WORK/cross.ini" <<CROSS
[binaries]
c = ['/usr/bin/clang', '--target=$TARGET_TRIPLE', '--sysroot=$SYSROOT']
cpp = ['/usr/bin/clang++', '--target=$TARGET_TRIPLE', '--sysroot=$SYSROOT']
c_ld = 'lld'
cpp_ld = 'lld'
ar = '/usr/bin/llvm-ar'
strip = '/usr/bin/llvm-strip'
pkg-config = 'pkgconf'
[properties]
needs_exe_wrapper = true
sys_root = '$SYSROOT'
pkg_config_libdir = ['$SYSROOT/usr/X11/lib/pkgconfig', '$SYSROOT/usr/libdata/pkgconfig']
[built-in options]
c_args = ['-O2', '-ffile-prefix-map=$WORK=/build']
c_link_args = ['-L$SYSROOT/usr/X11/lib', '-Wl,-rpath,/usr/X11/lib']
[host_machine]
system = 'freebsd'
cpu_family = '$CPU'
cpu = '$CPU'
endian = 'little'
CROSS
    # Recipe names are checked against the allowlist above.
    # shellcheck source=/dev/null
    . "$TOP/packages/$RECIPE/build.sh"
    python3 "$TOP/scripts/verify-stage.py" "$STAGE" "$SYSROOT" "$RECIPE"
    version=$(cat "$TOP/packages/$RECIPE/version")
    name=StepBSD-xorg
    [ "$RECIPE" != pkg ] || name=pkg
    deps=$(for d in $reqs; do pkg -r "$SYSROOT" query '"%n": { origin: "%o", version: "%v" },' "$d"; done)
    mkdir -p "$STAGE/usr/share/stepbsd/packages/$RECIPE"
    install -m 0444 "$TOP/LICENSE" "$STAGE/usr/share/licenses/$RECIPE/StepBSD-pkg-LICENSE"
    install -m 0444 "$TOP/NOTICE.md" "$STAGE/usr/share/licenses/$RECIPE/StepBSD-pkg-NOTICE.md"
    cp "$TOP/packages/$RECIPE/sources.lock" "$STAGE/usr/share/stepbsd/packages/$RECIPE/"
    pkg -r "$SYSROOT" query '%n %v' > "$STAGE/usr/share/stepbsd/packages/$RECIPE/build-dependencies.txt"
    # VM sync can preserve the checkout's host UID. Trust only this explicit
    # checkout for this command; do not change Git's global safety settings.
    recipe_commit=$(git -c safe.directory="$TOP" -C "$TOP" rev-parse HEAD) ||
        die "build from a StepBSD-pkg Git checkout so package provenance is recorded"
    printf '%s\n' "$recipe_commit" > "$STAGE/usr/share/stepbsd/packages/$RECIPE/recipe-commit"
    cat > "$WORK/manifest" <<MANIFEST
name: "$name"
origin: "stepbsd/$RECIPE"
version: "$version"
comment: "StepBSD source-built $RECIPE"
desc: "Built from checksum-pinned upstream sources with StepBSD's ordered patch series."
maintainer: "rtp@beeksiwaais.fr"
www: "https://github.com/beeksiwaais/StepBSD-pkg"
abi: "$ABI"
arch: "freebsd:15:$ABIARCH"
prefix: /
annotations: { "org.stepbsd.origin": "StepBSD" }
deps: {
$deps
}
MANIFEST
    (cd "$STAGE" && find . \( -type f -o -type l \) | sed 's|^\.||' | sort) > "$WORK/plist"
    [ "$RECIPE" != xorg ] || echo '@dir /var/db/xkb' >> "$WORK/plist"
    rm -f "$OUT/$name-$version.pkg" "$OUT/$name-$version.pkg.sig"
    pkg create -M "$WORK/manifest" -p "$WORK/plist" -r "$STAGE" -o "$OUT"
done
# A key is mandatory for publication, optional for an isolated local build.
if [ -n "${REPO_SIGNING_KEY:-}" ]; then
    sh "$TOP/scripts/sign-repository.sh" "$OUT"
else
    pkg repo "$OUT"
fi
