#!/usr/bin/env python3
"""Preserve upstream licence notices alongside source-built binary packages."""
import pathlib
import shutil
import sys

source, destination = map(pathlib.Path, sys.argv[1:])
found = 0
for path in source.rglob("*"):
    name = path.name.upper()
    if path.is_file() and any(name.startswith(prefix) for prefix in ("COPYING", "COPYRIGHT", "LICENSE", "LICENCE")):
        target = destination / path.relative_to(source)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        found += 1
if not found:
    raise SystemExit(f"no upstream licence notices found in {source}")
