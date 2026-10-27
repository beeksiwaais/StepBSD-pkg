# shellcheck shell=sh
source_component pkg
(cd "$OBJ" &&
    CPPFLAGS='' LDFLAGS="-L$SYSROOT/usr/lib" "$SRC/configure" --prefix=/usr/local \
        --sbindir=/usr/sbin --libdir=/usr/lib --includedir=/usr/include \
        --mandir=/usr/share/man --pkgconfigdir=/usr/libdata/pkgconfig &&
    gmake -j "$JOBS" &&
    gmake -C src install DESTDIR="$STAGE" &&
    gmake -C libpkg install DESTDIR="$STAGE" &&
    gmake -C docs install DESTDIR="$STAGE")
rm -f "$STAGE/usr/lib/libpkg.a"
sed -i '' 's|^prefix=.*|prefix=/usr|' "$STAGE/usr/libdata/pkgconfig/pkg.pc"
install -d "$STAGE/usr/share/examples/pkg"
install -m 0444 "$SRC/src/pkg.conf.sample" "$STAGE/usr/share/examples/pkg/pkg.conf.sample"
