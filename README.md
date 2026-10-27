# StepBSD-pkg

StepBSD's source package recipes, patches, build tests and repository signing.
This is a separate repository from [StepBSD](https://github.com/beeksiwaais/StepBSD),
which assembles and tests the installable operating-system images.

| Package | Sources | Responsibility |
|---|---|---|
| `StepBSD-xorg` | X.Org Server 21.1.25, X.Org tools and drivers, libepoxy, libxcvt, libpciaccess | Server, Xvfb, modesetting, libinput, BSD keyboard/mouse, scfb; VESA on amd64 |
| `pkg` | FreeBSD pkg 2.8.4 with NextBSD compatibility patches and StepBSD distribution policy | Normal installation and updates from StepBSD and NextBSD repositories |

No XLibre package, source archive, driver module or server is used. NextBSD
still supplies the base system, Mesa, X client libraries and shared display
support libraries. FreeBSD packages on the **build host** provide build tools;
they are never installed into the target root or used as target link inputs.

## Layout

```text
packages/<recipe>/sources.lock       upstream URLs, versions and SHA-256 hashes
packages/<recipe>/version            package version, including our revision
packages/<recipe>/requirements.txt   target NextBSD package dependencies
packages/<recipe>/patches/<source>/  ordered series, each patch with an Origin
packages/<recipe>/build.sh           upstream build commands
scripts/                            build, validation, signing and bootstrap
keys/StepBSD.pub                     public repository/bootstrap verification key
```

X.Org sources come from X.Org, GNOME and scfb's upstream project. The
FreeBSD-specific patches are carried with their immutable upstream references.
Our DRI path patch keeps build-sysroot paths out of the installed server.
All server modules are compiled against our X.Org SDK. Runtime fonts for
GNUstep come from NextBSD's font stack; the X server also has its built-in
core fonts. Optional desktop clients such as xterm and twm are not included:
StepBSD supplies Gershwin's applications and window manager.

## Build and test

Use a FreeBSD 15.1 VM of the target architecture, as root:

```sh
pkg install -y git python3 meson ninja pkgconf autoconf automake libtool xorg-macros gmake
sh scripts/build.sh out
sh scripts/install-test.sh out
```

The default builds both recipes. To build only one, append `pkg` or `xorg`.
Downloads are checksum checked on every use, including cache hits. Target
packages install into an isolated sysroot; the compiler uses that sysroot
and pkgconf searches only its `.pc` directories. Verification rejects file
ownership collisions, unresolved shared libraries and build-host RPATHs.
The install test uses the new pkg-static to install X.Org from a repository,
starts an authenticated Xvfb session, queries display/input, compiles an XKB
keymap, and verifies that foreign packages cannot install into `/System`.
It does not establish physical GPU support; StepBSD's ISO boot tests cover
the full desktop on the tested VM hardware.

For patch iteration after a failed build, reuse **only this disposable build
root**, for example:

```sh
REUSE_ROOT=1 START_AT=xf86-input-keyboard sh scripts/build.sh out xorg
```

Do a clean build before release. Bump the `_revision` in `version` whenever a
recipe or patch changes. Installed packages record the source pins, recipe
commit and versions of the base packages used to build them. Base dependencies
currently follow NextBSD's rolling repository; these builds are traceable,
but not yet independent snapshots of the complete NextBSD toolchain and base.

## Signing and publication

Local builds produce an unsigned temporary repository. Publication always
requires the private RSA key matching `keys/StepBSD.pub`:

```sh
REPO_SIGNING_KEY=/secure/path/StepBSD-repo.pem sh scripts/sign-repository.sh out
sh scripts/check-repository.sh out arm64
TEST_SIGNED_REPO=1 sh scripts/install-test.sh out
```

Repository catalogues are signed with pkg's signing mechanism. Bootstrap
package archives also have detached SHA-256 signatures (`.pkg.sig`). Keep
the private key outside both repositories and back it up securely. CI gets
it from the `STEPBSD_REPO_SIGNING_KEY` secret; the public key is committed.
The publish job fails before uploading if the key is absent or does not match.

The workflow builds and install-tests amd64 and arm64 before publishing
`packages-amd64` and `packages-arm64`. StepBSD consumes a pinned recipe commit,
builds these packages, adds `StepBSD-desktop`, signs the combined catalogue,
and publishes its own complete repository for installed systems.

## Package-manager policy

StepBSD's pkg trusts the configured `StepBSD` and `NextBSD` repositories for
base-system paths. Local package files identify themselves with
`org.stepbsd.origin=StepBSD` or `org.nextbsd.origin=NextBSD`; this marker is
not a cryptographic signature. Downloaded packages are authenticated through
signed repository metadata. Other packages retain NextBSD's `/usr/local`
and `/var` restriction. Only StepBSD may supply pkg's repository updates;
local pkg replacements must carry StepBSD's origin marker.

For an older image, obtain `pkg-<version>.pkg` and its `.sig` from a signed
release, then run `sh scripts/bootstrap-pkg.sh /path/to/pkg-<version>.pkg`.
The helper verifies the detached signature before extracting or running the
static package manager. Fresh StepBSD images bootstrap it during assembly.
