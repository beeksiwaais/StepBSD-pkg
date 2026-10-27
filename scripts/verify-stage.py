#!/usr/bin/env python3
"""Check package ownership, runtime library closure, and installed search paths."""
import pathlib
import re
import subprocess
import sys

stage, sysroot, recipe = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
owned = set(subprocess.check_output(["pkg", "-r", str(sysroot), "query", "%Fp"], text=True).splitlines())
providers = {p.name for p in sysroot.rglob("*.so*") if p.is_file()}
providers.update(p.name for p in stage.rglob("*.so*") if p.is_file())
errors = []
count = 0
for path in stage.rglob("*"):
    if not (path.is_file() or path.is_symlink()):
        continue
    installed = "/" + str(path.relative_to(stage))
    if installed in owned and not (recipe == "pkg" and installed == "/usr/sbin/pkg"):
        errors.append(f"would overwrite a base-owned file: {installed}")
    if path.is_symlink():
        continue
    with path.open("rb") as source:
        if source.read(4) != b"\x7fELF":
            continue
    count += 1
    dynamic = subprocess.check_output(["readelf", "-d", str(path)], text=True)
    for needed in re.findall(r"\(NEEDED\).*?\[(.*?)\]", dynamic):
        if needed not in providers:
            errors.append(f"{installed}: unresolved library {needed}")
    for paths in re.findall(r"\((?:RUNPATH|RPATH)\).*?\[(.*?)\]", dynamic):
        for entry in paths.split(":"):
            if entry and entry not in {"/usr/X11/lib", "/usr/lib", "/usr/lib/system", "/lib", "$ORIGIN"}:
                errors.append(f"{installed}: unexpected runtime search path {entry}")
if recipe == "xorg":
    config = sysroot.parent.parent / "obj/xorg/xorg-server/include/dix-config.h"
    if '#define DRI_DRIVER_PATH "/usr/X11/lib/dri"' not in config.read_text():
        errors.append("X.Org embedded the wrong installed DRI driver path")
if errors:
    raise SystemExit("\n".join(errors))
print(f"verified {recipe}: {count} ELF objects, library closure, paths, and ownership")
