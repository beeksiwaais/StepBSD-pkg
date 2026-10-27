# shellcheck shell=sh
# Shared by the package recipes; sourced by build.sh.
die() { echo "StepBSD-pkg: $*" >&2; exit 1; }

source_component() {
    COMPONENT=$1
    SRC=$WORK/src/$RECIPE/$COMPONENT
    OBJ=$WORK/obj/$RECIPE/$COMPONENT
    COMP_STAGE=$WORK/stage/$RECIPE/$COMPONENT
    rm -rf "$SRC" "$OBJ" "$COMP_STAGE"
    mkdir -p "$OBJ" "$COMP_STAGE"
    python3 "$TOP/scripts/sources.py" "$RECIPE" "$COMPONENT" --cache "$WORK/dl" --dest "$SRC"
    python3 "$TOP/scripts/licenses.py" "$SRC" "$STAGE/usr/share/licenses/$RECIPE/$COMPONENT"
    patches=$TOP/packages/$RECIPE/patches/$COMPONENT
    if [ -f "$patches/series" ]; then
        while IFS= read -r p; do
            case "$p" in ''|'#'*) continue ;; esac
            case "$p" in */*|*..*) die "invalid patch name: $p" ;; esac
            grep -q '^Origin: ' "$patches/$p" || die "patch $p has no Origin"
            patch -d "$SRC" -p1 --batch --forward --fuzz=0 < "$patches/$p"
        done < "$patches/series"
    fi
    echo "==> $RECIPE/$COMPONENT"
}

meson_build() {
    meson setup "$OBJ" "$SRC" --cross-file "$WORK/cross.ini" \
        --prefix=/usr/X11 --libdir=lib --buildtype=release --wrap-mode=nodownload \
        -Ddefault_library=shared "$@"
    ninja -C "$OBJ" -j "$JOBS"
    DESTDIR="$COMP_STAGE" meson install -C "$OBJ" --no-rebuild
}

autotools_build() {
    if [ ! -x "$SRC/configure" ]; then
        (cd "$SRC" && ACLOCAL_PATH="$SYSROOT/usr/X11/share/aclocal:/usr/local/share/aclocal" autoreconf -fi)
    fi
    (cd "$OBJ" && "$SRC/configure" --prefix=/usr/X11 --libdir=/usr/X11/lib \
        --build="$BUILD_TRIPLE" --host="$TARGET_TRIPLE" \
        --disable-static --enable-shared "$@" &&
        gmake -j "$JOBS" && gmake install DESTDIR="$COMP_STAGE")
}

stage_component() {
    # Every component may add its own files, but must never overwrite a base
    # package's file. Xorg's loadable modules are always rebuilt against our SDK.
    (cd "$COMP_STAGE" && find . \( -name '*.la' -o -name '*.a' \) -delete)
    for pcdir in share/pkgconfig libdata/pkgconfig; do
        if [ -d "$COMP_STAGE/usr/X11/$pcdir" ]; then
            mkdir -p "$COMP_STAGE/usr/X11/lib/pkgconfig"
            mv "$COMP_STAGE/usr/X11/$pcdir/"*.pc "$COMP_STAGE/usr/X11/lib/pkgconfig/"
            rmdir "$COMP_STAGE/usr/X11/$pcdir"
        fi
    done
    (cd "$COMP_STAGE" && find . \( -type f -o -type l \)) > "$WORK/component-files"
    while IFS= read -r f; do
        case "$f" in ./usr/X11/*) ;; *) die "unexpected X.Org install path: $f" ;; esac
        if [ -e "$SYSROOT/$f" ] || [ -L "$SYSROOT/$f" ]; then
            # A resumed build can replace a file from its own prior stage.
            if [ "${REUSE_ROOT:-0}" != 1 ] || { [ ! -e "$STAGE/$f" ] && [ ! -L "$STAGE/$f" ]; }; then
                die "$COMPONENT would overwrite $f"
            fi
        fi
    done < "$WORK/component-files"
    (cd "$COMP_STAGE" && tar -cf - .) | tar -xf - -C "$SYSROOT"
    (cd "$COMP_STAGE" && tar -cf - .) | tar -xf - -C "$STAGE"
}
