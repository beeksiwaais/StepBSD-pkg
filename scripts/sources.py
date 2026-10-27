#!/usr/bin/env python3
"""Fetch only checksum-pinned upstream sources; never use distribution binaries."""
import argparse
import hashlib
import pathlib
import re
import tarfile
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent


def pins(recipe):
    result = {}
    for line in (recipe / "sources.lock").read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        name, version, digest, url = line.split()
        if name in result or not re.fullmatch(r"[a-z0-9][a-z0-9-]*", name):
            raise ValueError(f"invalid or duplicate component: {name}")
        if not re.fullmatch(r"[a-f0-9]{64}", digest):
            raise ValueError(f"invalid SHA-256 for {name}")
        if not url.startswith("https://") or "x11libre" in url.lower():
            raise ValueError(f"invalid upstream URL for {name}")
        result[name] = (version, digest, url)
    return result


def fetch(recipe, name, cache, dest):
    version, digest, url = pins(recipe)[name]
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / f"{name}-{digest[:16]}-{pathlib.PurePosixPath(urllib.parse.urlparse(url).path).name}"
    if not archive.exists():
        temporary = archive.with_suffix(archive.suffix + ".part")
        try:
            with urllib.request.urlopen(url, timeout=120) as source, temporary.open("wb") as output:
                while block := source.read(1024 * 1024):
                    output.write(block)
            temporary.replace(archive)
        finally:
            temporary.unlink(missing_ok=True)
    with archive.open("rb") as source:
        actual = hashlib.file_digest(source, "sha256").hexdigest()
    if actual != digest:
        raise ValueError(f"SHA-256 mismatch for {name}: expected {digest}, got {actual}; remove {archive} before retrying")
    dest.mkdir(parents=True, exist_ok=False)
    with tarfile.open(archive) as source:
        members = source.getmembers()
        roots = {m.name.split("/", 1)[0] for m in members}
        if len(roots) != 1:
            raise ValueError(f"{name}: expected one archive root")
        for member in members:
            _, _, member.name = member.name.partition("/")
            if member.name:
                source.extract(member, dest, filter="data")
    print(f"verified {name} {version} {digest}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("recipe", choices=["xorg", "pkg"])
    parser.add_argument("component", nargs="?")
    parser.add_argument("--cache", type=pathlib.Path)
    parser.add_argument("--dest", type=pathlib.Path)
    args = parser.parse_args()
    recipe = ROOT / "packages" / args.recipe
    if args.component:
        if args.cache is None or args.dest is None:
            parser.error("fetch requires --cache and --dest")
        fetch(recipe, args.component, args.cache, args.dest)
    else:
        for name, (version, digest, url) in pins(recipe).items():
            print(name, version, digest, url)


if __name__ == "__main__":
    main()
