# shellcheck shell=sh
# Sourced by scripts/build.sh after the target sysroot and toolchain are ready.
started=0
[ -n "${START_AT:-}" ] || started=1
for COMPONENT in libepoxy libxcvt libpciaccess xkbcomp xorg-server \
    xf86-input-libinput xf86-input-keyboard xf86-input-mouse xf86-video-scfb xf86-video-vesa \
    xauth xinit xset setxkbmap xinput xrandr xdpyinfo xwininfo; do
    [ "$COMPONENT:$ARCH" != xf86-video-vesa:arm64 ] || continue
    [ "$COMPONENT" != "${START_AT:-}" ] || started=1
    [ "$started" = 1 ] || continue
    source_component "$COMPONENT"
    case "$COMPONENT" in
        libepoxy) meson_build -Dglx=yes -Degl=yes -Dx11=true -Dtests=false -Ddocs=false ;;
        libxcvt) meson_build ;;
        libpciaccess) meson_build -Dpci-ids=hwdata -Dzlib=disabled -Dinstall-scanpci=false ;;
        xkbcomp|setxkbmap) meson_build -Dxkb-config-root=/usr/share/X11/xkb ;;
        xorg-server)
            meson_build -Dxorg=true -Dxvfb=true -Dxnest=false -Dxephyr=false \
                -Dxwin=false -Dxquartz=false -Dglamor=true -Ddrm=true -Dglx=true \
                -Ddri1=false -Ddri2=true -Ddri3=true -Dpciaccess=true \
                -Dudev=true -Dudev_kms=true -Dhal=false -Dsystemd_logind=false \
                -Dsuid_wrapper=false -Dxselinux=false -Dlibunwind=false \
                -Ddocs=false -Ddevel-docs=false -Ddocs-pdf=false \
                -Dxf86-input-inputtest=false -Dsha1=libmd -Dsecure-rpc=false \
                -Dxcsecurity=true -Dfallback_input_driver=libinput \
                -Dlog_dir=/var/log -Ddefault_font_path=built-ins \
                -Dxkb_dir=/usr/share/X11/xkb -Dxkb_bin_dir=/usr/X11/bin \
                -Dxkb_output_dir=/var/db/xkb -Dbuilder_string=StepBSD \
                -Ddri_driver_path=/usr/X11/lib/dri
            # LoginWindow runs as root; preserve the existing startx behavior too.
            chown 0:0 "$COMP_STAGE/usr/X11/bin/Xorg"
            chmod 4555 "$COMP_STAGE/usr/X11/bin/Xorg"
            ;;
        xf86-input-libinput|xf86-input-keyboard|xf86-input-mouse|xf86-video-scfb|xf86-video-vesa)
            export ACLOCAL_PATH="$SYSROOT/usr/X11/share/aclocal:/usr/local/share/aclocal"
            driver_libs=
            [ "$COMPONENT" != xf86-input-mouse ] || driver_libs=-lusbhid
            LIBS="$driver_libs" CPPFLAGS="$CPPFLAGS $(pkgconf --cflags linux-input-shim)" \
            autotools_build --with-xorg-module-dir=/usr/X11/lib/xorg/modules \
                --with-sdkdir=/usr/X11/include/xorg \
                --with-xorg-conf-dir=/usr/X11/share/X11/xorg.conf.d
            ;;
        xinit) autotools_build --without-launchd --with-xinitdir=/usr/X11/etc/X11/xinit \
                --with-xauth=/usr/X11/bin/xauth ;;
        xset) meson_build -Dfontcache=disabled -Dxf86misc=disabled ;;
        xrandr) meson_build ;;
        *) autotools_build ;;
    esac
    stage_component
done
[ "$started" = 1 ] || die "unknown START_AT: $START_AT"
ln -sf Xorg "$STAGE/usr/X11/bin/X"
mkdir -p "$STAGE/var/db/xkb"
