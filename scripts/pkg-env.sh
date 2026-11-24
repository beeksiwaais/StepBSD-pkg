# shellcheck shell=sh
# Target package metadata, independent of the FreeBSD build host and C triple.
# Sourced by source builds and StepBSD's pinned integration checkout.
stepbsd_pkg_target() {
    case "$1" in
        amd64|x86_64) STEPBSD_ABI_ARCH=amd64 ;;
        arm64|aarch64) STEPBSD_ABI_ARCH=aarch64 ;;
        *) echo "Unsupported package architecture: $1" >&2; return 1 ;;
    esac
    ABI="NextBSD:27:$STEPBSD_ABI_ARCH"
    OSVERSION=2700000
    export ABI OSVERSION ASSUME_ALWAYS_YES=yes
}

# A build-host-only bootstrap for assembling the sysroot needed to compile our
# own pkg. Never install this NextBSD binary as StepBSD's package manager.
stepbsd_pkg_bootstrap() {
    stepbsd_tool_dir=$1/pkg-tool
    mkdir -p "$stepbsd_tool_dir"
    case "$(uname -m)" in
        amd64|x86_64) stepbsd_host_arch=amd64 ;;
        arm64|aarch64) stepbsd_host_arch=arm64 ;;
        *) echo 'Unsupported pkg bootstrap host' >&2; return 1 ;;
    esac
    stepbsd_tool_archive=$stepbsd_tool_dir/nextbsd-contrib-pkg-$stepbsd_host_arch.tar.gz
    if [ ! -s "$stepbsd_tool_archive" ]; then
        fetch -o "$stepbsd_tool_archive.part" "https://github.com/nextbsd/nextbsd-contrib/releases/download/continuous/nextbsd-contrib-pkg-$stepbsd_host_arch.tar.gz" || return
        mv "$stepbsd_tool_archive.part" "$stepbsd_tool_archive"
    fi
    tar -xOf "$stepbsd_tool_archive" ./usr/sbin/pkg-static > "$stepbsd_tool_dir/pkg-static" || return
    chmod 0500 "$stepbsd_tool_dir/pkg-static"
    STEPBSD_PKG_TOOL=$stepbsd_tool_dir/pkg-static
    STEPBSD_PKG_CONFIG=$stepbsd_tool_dir/pkg.conf
    : > "$STEPBSD_PKG_CONFIG"
    stepbsd_pkg_check_abi
}

# Local build artifacts are trusted inputs. Publication/bootstrap callers must
# verify the archive's detached signature before executing its static binary.
stepbsd_pkg_from_repository() {
    stepbsd_tool_repo=$1
    stepbsd_tool_dir=$2/pkg-tool-stepbsd
    stepbsd_archive_abi=${3:-$ABI}
    set -- "$stepbsd_tool_repo"/pkg-[0-9]*.pkg
    if [ "$#" -ne 1 ] || [ ! -s "$1" ]; then
        echo 'Need exactly one freshly built StepBSD pkg archive; use a fresh output directory for the ABI migration' >&2
        return 1
    fi
    mkdir -p "$stepbsd_tool_dir"
    tar -xOf "$1" /usr/sbin/pkg-static > "$stepbsd_tool_dir/pkg-static" || return
    chmod 0500 "$stepbsd_tool_dir/pkg-static"
    STEPBSD_PKG_TOOL=$stepbsd_tool_dir/pkg-static
    STEPBSD_PKG_CONFIG=$stepbsd_tool_dir/pkg.conf
    : > "$STEPBSD_PKG_CONFIG"
    stepbsd_pkg_check_abi || return
    [ "$(stepbsd_pkg query -F "$1" %n)" = pkg ] || return 1
    [ "$(stepbsd_pkg query -F "$1" %q)" = "$stepbsd_archive_abi" ] || {
        echo "StepBSD pkg archive does not target $stepbsd_archive_abi; rebuild the source packages" >&2
        return 1
    }
}

# A release VM can sign/query either target architecture with its native pkg.
# Cross-architecture callers supply the native build's artifact directory.
stepbsd_pkg_metadata_tool() {
    case "$(uname -m)" in
        amd64|x86_64) stepbsd_metadata_arch=amd64 ;;
        arm64|aarch64) stepbsd_metadata_arch=aarch64 ;;
        *) echo 'Unsupported package metadata host' >&2; return 1 ;;
    esac
    if [ "$ABI" != "NextBSD:27:$stepbsd_metadata_arch" ] && [ -z "${STEPBSD_PKG_HOST_REPO:-}" ]; then
        echo 'Cross-architecture package operations require STEPBSD_PKG_HOST_REPO with the native host pkg archive' >&2
        return 1
    fi
    stepbsd_pkg_from_repository "${STEPBSD_PKG_HOST_REPO:-$1}" "$2" "NextBSD:27:$stepbsd_metadata_arch"
}

stepbsd_pkg_check_abi() {
    stepbsd_tool_abi=$(stepbsd_pkg config ABI) || return
    [ "$stepbsd_tool_abi" = "$ABI" ] || {
        echo "Package tool cannot handle target ABI $ABI (got $stepbsd_tool_abi)" >&2
        return 1
    }
}

stepbsd_pkg() {
    "$STEPBSD_PKG_TOOL" -C "$STEPBSD_PKG_CONFIG" "$@"
}
