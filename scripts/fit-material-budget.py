#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import pathlib
import shutil
import subprocess
import sys
import tempfile
from typing import Iterable

from fontTools.ttLib import TTFont


ROOT_DIR = pathlib.Path(__file__).resolve().parent.parent
SCRIPTS_DIR = ROOT_DIR / "scripts"
CANDIDATES_PATH = SCRIPTS_DIR / "material-icons-candidates.txt"
ACTIVE_PATH = SCRIPTS_DIR / "material-icons-active.txt"
PATCH_PATH = ROOT_DIR / "font-patcher.patch"
UPSTREAM_PATCHER = ROOT_DIR / "tmp" / "FontPatcher" / "font-patcher"
TMP_HINTED = ROOT_DIR / "tmp" / "sarasa" / "SarasaTermSC-BoldItalic.ttf"
TMP_UNHINTED = ROOT_DIR / "tmp" / "sarasa-unhinted" / "SarasaTermSC-BoldItalic.ttf"


def run_quiet(cmd: list[str], *, cwd: pathlib.Path) -> None:
    result = subprocess.run(
        cmd,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if result.returncode != 0:
        if result.stdout:
            sys.stderr.write(result.stdout)
        raise subprocess.CalledProcessError(result.returncode, cmd, output=result.stdout)


def parse_ranges(path: pathlib.Path, *, allow_empty: bool = False) -> list[tuple[int, int]]:
    ranges: list[tuple[int, int]] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        start_s, end_s = line.split("-", 1)
        start = int(start_s, 16)
        end = int(end_s, 16)
        if start > end:
            raise ValueError(f"invalid range {line} in {path}")
        ranges.append((start, end))
    if not ranges and not allow_empty:
        raise ValueError(f"no ranges found in {path}")
    return ranges


def merge_ranges(ranges: Iterable[tuple[int, int]]) -> list[tuple[int, int]]:
    merged: list[tuple[int, int]] = []
    for start, end in ranges:
        if not merged or start > merged[-1][1] + 1:
            merged.append((start, end))
            continue
        merged[-1] = (merged[-1][0], max(merged[-1][1], end))
    return merged


def format_range(start: int, end: int) -> str:
    return f"0x{start:05X}-0x{end:05X}"


def write_manifest(
    active_ranges: list[tuple[int, int]],
    *,
    destination: pathlib.Path,
    sarasa_tag: str,
    nerd_tag: str,
    budget: int,
    max_glyphs: int | None,
    write: bool,
) -> str:
    lines = [
        "# Active Material Design Icons ranges used to generate scripts/font-patcher.",
        "# Generated data may be rewritten by scripts/fit-material-budget.py.",
        f"# sarasa_tag={sarasa_tag}",
        f"# nerd_tag={nerd_tag}",
        f"# budget={budget}",
        "# probe_font=SarasaTermSC-BoldItalic.ttf",
    ]
    if max_glyphs is not None:
        lines.append(f"# probe_max_glyphs={max_glyphs}")
    lines.append(f"# generated_at={dt.datetime.now(dt.timezone.utc).isoformat()}")
    lines.extend(format_range(start, end) for start, end in active_ranges)
    content = "\n".join(lines) + "\n"
    if write:
        destination.write_text(content, encoding="utf-8")
    return content


def read_upstream_versions() -> tuple[str, str]:
    values: dict[str, str] = {}
    env_path = SCRIPTS_DIR / "upstream-versions.env"
    for raw in env_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = value
    return values.get("SARASA_TAG", ""), values.get("NERD_TAG", "")


def ensure_probe_inputs() -> None:
    missing = [str(path) for path in (UPSTREAM_PATCHER, TMP_HINTED, TMP_UNHINTED) if not path.exists()]
    if missing:
        raise FileNotFoundError(
            "missing probe inputs; run scripts/refresh-upstream.sh --fetch-only first:\n" + "\n".join(missing)
        )


def generate_patcher(workdir: pathlib.Path, active_manifest: pathlib.Path) -> pathlib.Path:
    output = workdir / "font-patcher"
    run_quiet(
        [
            sys.executable,
            str(SCRIPTS_DIR / "apply-font-patcher-patch.py"),
            "--upstream",
            str(UPSTREAM_PATCHER),
            "--patch",
            str(PATCH_PATH),
            "--active-material",
            str(active_manifest),
            "--out",
            str(output),
        ],
        cwd=ROOT_DIR,
    )
    output.chmod(0o755)
    return output


def probe_glyphs(patcher: pathlib.Path, source_font: pathlib.Path, workdir: pathlib.Path, label: str) -> int:
    run_dir = workdir / f"{label}-{source_font.stem}"
    out_dir = run_dir / "out"
    shutil.copytree(ROOT_DIR / "tmp" / "FontPatcher" / "src", run_dir / "src")
    shutil.copytree(ROOT_DIR / "tmp" / "FontPatcher" / "bin", run_dir / "bin")
    shutil.copy2(ROOT_DIR / "tmp" / "FontPatcher" / "glyphnames.json", run_dir / "glyphnames.json")
    shutil.copy2(patcher, run_dir / "font-patcher")
    shutil.copy2(source_font, run_dir / source_font.name)
    (run_dir / "font-patcher").chmod(0o755)
    out_dir.mkdir(parents=True, exist_ok=True)
    run_quiet(
        [
            str(run_dir / "font-patcher"),
            "--quiet",
            "--adjust-line-height",
            "--complete",
            "--careful",
            "--outputdir",
            str(out_dir),
            str(run_dir / source_font.name),
        ],
        cwd=run_dir,
    )
    outputs = sorted(out_dir.glob("SarasaTermSCNerd-*.ttf"))
    if len(outputs) != 1:
        raise RuntimeError(f"expected exactly one generated font for {source_font.name}, got {len(outputs)}")
    with TTFont(outputs[0]) as font:
        return int(font["maxp"].numGlyphs)


def fit_ranges(candidates: list[tuple[int, int]], budget: int) -> tuple[list[tuple[int, int]], int]:
    def probe(prefix_len: int) -> int:
        merged = merge_ranges(candidates[:prefix_len])
        sarasa_tag, nerd_tag = read_upstream_versions()
        with tempfile.TemporaryDirectory(prefix="sarasa-fit-") as td:
            workdir = pathlib.Path(td)
            manifest = workdir / "material-icons-active.txt"
            write_manifest(
                merged,
                destination=manifest,
                sarasa_tag=sarasa_tag,
                nerd_tag=nerd_tag,
                budget=budget,
                max_glyphs=None,
                write=True,
            )
            patcher = generate_patcher(workdir, manifest)
            try:
                hinted = probe_glyphs(patcher, TMP_HINTED, workdir, "hinted")
                unhinted = probe_glyphs(patcher, TMP_UNHINTED, workdir, "unhinted")
            except subprocess.CalledProcessError:
                # FontForge fails before writing output once the glyph count crosses
                # the SFNT limit, which should be treated as "over budget" during
                # binary search instead of aborting the whole fitting run.
                return budget + 1
        return max(hinted, unhinted)

    low = 0
    high = len(candidates)
    best_len = -1
    best_glyphs = -1
    while low <= high:
        mid = (low + high) // 2
        glyphs = probe(mid)
        if glyphs <= budget:
            best_len = mid
            best_glyphs = glyphs
            low = mid + 1
        else:
            high = mid - 1
    if best_len < 0:
        raise RuntimeError("glyph budget exceeded even with no active Material icons; issue is not fixable by trimming MDI")
    return merge_ranges(candidates[:best_len]), best_glyphs


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--budget", type=int, default=65534)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()

    ensure_probe_inputs()
    candidates = parse_ranges(CANDIDATES_PATH)
    current_active = parse_ranges(ACTIVE_PATH, allow_empty=True)
    sarasa_tag, nerd_tag = read_upstream_versions()

    fitted, glyphs = fit_ranges(candidates, args.budget)
    content = write_manifest(
        fitted,
        destination=ACTIVE_PATH,
        sarasa_tag=sarasa_tag,
        nerd_tag=nerd_tag,
        budget=args.budget,
        max_glyphs=glyphs,
        write=args.write and not args.dry_run,
    )

    print(f"[fit] candidates={len(candidates)} active_before={len(current_active)} active_after={len(fitted)}")
    print(f"[fit] probe_max_glyphs={glyphs} budget={args.budget}")
    removed = current_active != fitted
    if removed:
        print("[fit] active ranges changed")
    else:
        print("[fit] active ranges unchanged")
    if args.dry_run or not args.write:
        print(content, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
