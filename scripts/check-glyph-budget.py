#!/usr/bin/env python3
from __future__ import annotations

import argparse
import glob
import pathlib
import sys
import tarfile
import tempfile

from fontTools.ttLib import TTFont


def count_glyphs(path: pathlib.Path) -> int:
    with TTFont(path) as font:
        return int(font["maxp"].numGlyphs)


def check_files(files: list[pathlib.Path], budget: int) -> int:
    bad: list[tuple[pathlib.Path, int]] = []
    for path in files:
        glyphs = count_glyphs(path)
        print(f"{path}: {glyphs}")
        if glyphs > budget:
            bad.append((path, glyphs))

    if bad:
        for path, glyphs in bad:
            print(
                f"::error file={path}::exceeds glyph budget {budget} ({glyphs})",
                file=sys.stderr,
            )
        return 1
    return 0


def check_glob(pattern: str, budget: int) -> int:
    files = [pathlib.Path(p) for p in sorted(glob.glob(pattern))]
    if not files:
        print(f"[glyph-budget] ERROR: no fonts matched {pattern}", file=sys.stderr)
        return 1
    return check_files(files, budget)


def check_ttf_archives(archives: list[pathlib.Path], budget: int) -> int:
    if not archives:
        print("[glyph-budget] ERROR: no archives provided", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory(prefix="glyph-budget-") as td:
        extract_root = pathlib.Path(td)
        files: list[pathlib.Path] = []
        for archive in archives:
            if not archive.exists():
                print(f"[glyph-budget] ERROR: missing archive {archive}", file=sys.stderr)
                return 1
            target_dir = extract_root / archive.stem.replace(".", "_")
            target_dir.mkdir(parents=True, exist_ok=True)
            with tarfile.open(archive, "r:gz") as tf:
                tf.extractall(target_dir, filter="data")
            files.extend(sorted(target_dir.glob("SarasaTermSCNerd-*.ttf")))

        if not files:
            print("[glyph-budget] ERROR: no TTF files found in archives", file=sys.stderr)
            return 1
        return check_files(files, budget)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--glob", dest="pattern")
    parser.add_argument("--budget", type=int, default=65534)
    parser.add_argument("--ttf-archive", action="append", default=[])
    args = parser.parse_args()

    if args.ttf_archive:
        archives = [pathlib.Path(p) for p in args.ttf_archive]
        return check_ttf_archives(archives, args.budget)

    pattern = args.pattern or "sarasa-nerd/SarasaTermSCNerd-*.ttf"
    return check_glob(pattern, args.budget)


if __name__ == "__main__":
    raise SystemExit(main())
