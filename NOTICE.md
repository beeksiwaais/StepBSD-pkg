# Source and patch licences

StepBSD's packaging scripts use BSD-2-Clause; see LICENSE. Downloaded source
is never committed. Each package retains its upstream copyright notices and
licence files in the source archives pinned in `sources.lock`.

| Component | Licence |
|---|---|
| FreeBSD pkg | BSD-2-Clause; bundled third-party libraries retain their upstream licences |
| X.Org Server, X.Org tools and drivers, libxcvt, libpciaccess | MIT/X11 and compatible notices; see each archive's COPYING |
| libepoxy | MIT; see COPYING and bundled registry notices |
| xf86-video-scfb | BSD-2-Clause; see COPYING |

The four initial pkg patches come from NextBSD's nextbsd-contrib repository
at commit `9cf90068fd4aaa6bd9a1a9bc0277edff43ac78f5`, BSD-2-Clause, copyright
Joseph Maloney. The X.Org xinit executable-path patches are also NextBSD's.
FreeBSD platform/driver patches retain immutable URLs in their Origin headers.
The keyboard close-device patch is rebased to the upstream release context;
its behavior is unchanged. StepBSD's package-manager policy and DRI path
patches are marked separately as Origin: StepBSD.

Full pinned source archives can be fetched with scripts/sources.py and are
available from the upstream URLs recorded inside each installed package.
