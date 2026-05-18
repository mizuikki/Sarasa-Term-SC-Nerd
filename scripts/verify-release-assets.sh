#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Verify that a GitHub Release's font artifacts were built from the expected upstream sources.

This script downloads the release assets, extracts a small sample, then:
  - reads version strings embedded in the font 'name' table (Sarasa / Nerds / ttfautohint)
  - compares TrueType hinting-related tables between hinted and unhinted builds

Usage:
  scripts/verify-release-assets.sh --tag v2.4.0 [--repo owner/name] [--workdir tmp/verify-v2.4.0] [--keep]

Examples:
  scripts/verify-release-assets.sh --tag v2.4.0
  scripts/verify-release-assets.sh --tag v2.4.0 --repo mizuikk/Sarasa-Term-SC-Nerd

Notes:
  - Requires: gh, tar, python3, and Python module 'fontTools' (fonttools / ttx).
  - By default, extracts only *.ttf.tar.gz assets (fast). Use --keep to retain extracted files.
EOF
}

die() {
  echo "[verify] ERROR: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

TAG=""
REPO=""
WORKDIR=""
KEEP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      TAG="${2:-}"
      shift 2
      ;;
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --workdir)
      WORKDIR="${2:-}"
      shift 2
      ;;
    --keep)
      KEEP=1
      shift 1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1 (use --help)"
      ;;
  esac
done

[[ -n "${TAG}" ]] || die "--tag is required (e.g. --tag v2.4.0)"

need_cmd gh
need_cmd tar
need_cmd python3

# Ensure fontTools import works (more robust than checking for `ttx` binary only).
python3 - <<'PY' >/dev/null
import fontTools  # noqa: F401
PY

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "${REPO}" ]]; then
  # Prefer git remote `origin`, because `gh repo view` can point at upstream/fork unintentionally.
  origin_url="$(git remote get-url origin 2>/dev/null || true)"
  if [[ "${origin_url}" =~ github\.com[:/]+([^/]+/[^/.]+)(\.git)?$ ]]; then
    REPO="${BASH_REMATCH[1]}"
  elif REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"; then
    :
  else
    die "cannot infer --repo; pass --repo owner/name"
  fi
fi

tag_slug="${TAG//\//_}"
WORKDIR="${WORKDIR:-${ROOT_DIR}/tmp/verify-${tag_slug}}"

ASSET_HINTED_TTF_TGZ="SarasaTermSCNerd.ttf.tar.gz"
ASSET_UNHINTED_TTF_TGZ="SarasaTermSCNerd-Unhinted.ttf.tar.gz"

mkdir -p "${WORKDIR}"
echo "[verify] repo: ${REPO}"
echo "[verify] tag:  ${TAG}"
echo "[verify] dir:  ${WORKDIR}"

echo "[verify] download assets..."
gh release download "${TAG}" -R "${REPO}" \
  -p "${ASSET_HINTED_TTF_TGZ}" \
  -p "${ASSET_UNHINTED_TTF_TGZ}" \
  -D "${WORKDIR}"

hinted_dir="${WORKDIR}/hinted"
unhinted_dir="${WORKDIR}/unhinted"
rm -rf "${hinted_dir}" "${unhinted_dir}"
mkdir -p "${hinted_dir}" "${unhinted_dir}"

echo "[verify] extract assets..."
tar -xzf "${WORKDIR}/${ASSET_HINTED_TTF_TGZ}" -C "${hinted_dir}"
tar -xzf "${WORKDIR}/${ASSET_UNHINTED_TTF_TGZ}" -C "${unhinted_dir}"

pick_sample() {
  local base_dir="$1"
  local preferred="$2"
  if [[ -f "${base_dir}/${preferred}" ]]; then
    echo "${base_dir}/${preferred}"
    return 0
  fi
  # fallback: first .ttf in directory
  local first
  first="$(ls -1 "${base_dir}"/*.ttf 2>/dev/null | head -n 1 || true)"
  [[ -n "${first}" ]] || die "no .ttf found in ${base_dir}"
  echo "${first}"
}

hinted_sample="$(pick_sample "${hinted_dir}" "SarasaTermSCNerd-Regular.ttf")"
unhinted_sample="$(pick_sample "${unhinted_dir}" "SarasaTermSCNerd-Regular.ttf")"

echo "[verify] sample hinted:   ${hinted_sample}"
echo "[verify] sample unhinted: ${unhinted_sample}"

echo
echo "[verify] embedded upstream strings (name table):"
python3 - <<PY
from fontTools.ttLib import TTFont
import re

def interesting_lines(path: str):
    f = TTFont(path)
    seen = set()
    for rec in f["name"].names:
        try:
            s = rec.toUnicode()
        except Exception:
            continue
        if s:
            seen.add(s)
    pat = re.compile(r"sarasa\\s*v|nerds\\s*\\d|patched with|ttfautohint|version\\s+\\d", re.I)
    lines = [s for s in sorted(seen) if pat.search(s)]
    return lines

for label, path in [
    ("hinted", "${hinted_sample}"),
    ("unhinted", "${unhinted_sample}"),
]:
    print(f"[{label}]")
    for line in interesting_lines(path):
        print(" ", line)
    print()
PY

TTX_BIN="ttx"
if ! command -v "${TTX_BIN}" >/dev/null 2>&1; then
  TTX_BIN="python3 -m fontTools.ttx"
fi

echo "[verify] hinting tables (ttx -l):"
echo "[hinted]"
${TTX_BIN} -l "${hinted_sample}" | grep -nE 'cvt |fpgm|prep|gasp' || true
echo "[unhinted]"
${TTX_BIN} -l "${unhinted_sample}" | grep -nE 'cvt |fpgm|prep|gasp' || true

echo
echo "[verify] upstream latest release tags (for comparison):"
echo -n "Sarasa-Gothic latest: "
gh release view -R be5invis/Sarasa-Gothic --json tagName,publishedAt -q '.tagName+" "+.publishedAt' || echo "(failed to query)"
echo -n "nerd-fonts latest:   "
gh release view -R ryanoasis/nerd-fonts --json tagName,publishedAt -q '.tagName+" "+.publishedAt' || echo "(failed to query)"

if [[ "${KEEP}" -eq 0 ]]; then
  rm -rf "${hinted_dir}" "${unhinted_dir}"
  echo
  echo "[verify] cleaned extracted files (use --keep to retain): ${hinted_dir} ${unhinted_dir}"
fi

echo
echo "[verify] done"
