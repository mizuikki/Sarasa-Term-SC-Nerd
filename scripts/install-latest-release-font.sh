#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Download the latest (or a specified) GitHub Release font asset and install/overwrite it on this machine.

Defaults:
  - repo: inferred from git remote 'origin' (fallback: mizuikki/Sarasa-Term-SC-Nerd)
  - tag:  latest release
  - format: ttc
  - hinting: hinted
  - scope: user (~/.local/share/fonts)

Usage:
  scripts/install-latest-release-font.sh [options]

Options:
  --repo owner/name        GitHub repo (default: infer from origin)
  --tag TAG                Release tag to install (default: latest)
  --format ttc|ttf         Install TTC collection or individual TTFs (default: ttc)
  --hinting hinted|unhinted  Choose hinted or unhinted build (default: hinted)
  --scope user|system      Install for current user or system-wide (default: user)
  --dest-dir DIR           Override destination directory (advanced)
  --dry-run                Print what would be done, do not modify system
  --keep                   Keep the temporary download/extract directory
  -h, --help               Show help

Examples:
  scripts/install-latest-release-font.sh
  scripts/install-latest-release-font.sh --scope system
  scripts/install-latest-release-font.sh --format ttf --hinting unhinted
  scripts/install-latest-release-font.sh --tag v1.0.37-nf3.4.0 --scope system
EOF
}

die() {
  echo "[install] ERROR: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

REPO=""
TAG=""
FORMAT="ttc"
HINTING="hinted"
SCOPE="user"
DEST_DIR=""
DRY_RUN=0
KEEP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --tag)
      TAG="${2:-}"
      shift 2
      ;;
    --format)
      FORMAT="${2:-}"
      shift 2
      ;;
    --hinting)
      HINTING="${2:-}"
      shift 2
      ;;
    --scope)
      SCOPE="${2:-}"
      shift 2
      ;;
    --dest-dir)
      DEST_DIR="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift 1
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

case "${FORMAT}" in
  ttc|ttf) ;;
  *) die "--format must be 'ttc' or 'ttf' (got: ${FORMAT})" ;;
esac

case "${HINTING}" in
  hinted|unhinted) ;;
  *) die "--hinting must be 'hinted' or 'unhinted' (got: ${HINTING})" ;;
esac

case "${SCOPE}" in
  user|system) ;;
  *) die "--scope must be 'user' or 'system' (got: ${SCOPE})" ;;
esac

need_cmd gh
need_cmd tar
need_cmd fc-cache
need_cmd fc-list
need_cmd sha256sum
need_cmd mktemp
need_cmd grep
need_cmd cut

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "${REPO}" ]]; then
  origin_url="$(git -C "${ROOT_DIR}" remote get-url origin 2>/dev/null || true)"
  if [[ "${origin_url}" =~ github\.com[:/]+([^/]+/[^/.]+)(\.git)?$ ]]; then
    REPO="${BASH_REMATCH[1]}"
  else
    REPO="mizuikki/Sarasa-Term-SC-Nerd"
  fi
fi

if [[ -z "${TAG}" ]]; then
  TAG="$(gh release view -R "${REPO}" --json tagName -q .tagName)"
fi

asset_base="SarasaTermSCNerd"
if [[ "${HINTING}" == "unhinted" ]]; then
  asset_base="SarasaTermSCNerd-Unhinted"
fi

asset="${asset_base}.${FORMAT}.tar.gz"

default_dest_user="${XDG_DATA_HOME:-${HOME}/.local/share}/fonts/sarasa-term-sc-nerd"
default_dest_system="/usr/local/share/fonts/sarasa-term-sc-nerd"

if [[ -z "${DEST_DIR}" ]]; then
  if [[ "${SCOPE}" == "system" ]]; then
    DEST_DIR="${default_dest_system}"
  else
    DEST_DIR="${default_dest_user}"
  fi
fi

tmpdir="$(mktemp -d -t sarasa-term-sc-nerd-install-XXXXXX)"
cleanup() {
  if [[ "${KEEP}" -eq 1 ]]; then
    echo "[install] kept workdir: ${tmpdir}"
  else
    rm -rf "${tmpdir}"
  fi
}
trap cleanup EXIT

echo "[install] repo:    ${REPO}"
echo "[install] tag:     ${TAG}"
echo "[install] asset:   ${asset}"
echo "[install] scope:   ${SCOPE}"
echo "[install] dest:    ${DEST_DIR}"

echo "[install] currently installed SarasaTermSCNerd locations (if any):"
fc-list : file family style | grep -i 'SarasaTermSCNerd' || true

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "[install] dry-run: skipping download/install"
  exit 0
fi

echo "[install] download..."
gh release download -R "${REPO}" "${TAG}" -p "${asset}" -D "${tmpdir}"

echo "[install] extract..."
tar -xzf "${tmpdir}/${asset}" -C "${tmpdir}"

sudo_cmd=""
if [[ "${SCOPE}" == "system" ]]; then
  sudo_cmd="sudo"
fi

echo "[install] install/overwrite..."
${sudo_cmd} mkdir -p "${DEST_DIR}"

if [[ "${FORMAT}" == "ttc" ]]; then
  ttc_path="${tmpdir}/${asset_base}.ttc"
  [[ -f "${ttc_path}" ]] || die "expected ${ttc_path} after extraction"

  dst="${DEST_DIR}/${asset_base}.ttc"
  if [[ -f "${dst}" ]]; then
    old_sha="$(${sudo_cmd} sha256sum "${dst}" | cut -d' ' -f1)"
    new_sha="$(sha256sum "${ttc_path}" | cut -d' ' -f1)"
    if [[ "${old_sha}" == "${new_sha}" ]]; then
      echo "[install] unchanged: ${dst} (sha256 match), skipping overwrite"
    else
      ${sudo_cmd} install -m 0644 "${ttc_path}" "${dst}"
      echo "[install] updated: ${dst}"
    fi
  else
    ${sudo_cmd} install -m 0644 "${ttc_path}" "${dst}"
    echo "[install] installed: ${dst}"
  fi
else
  shopt -s nullglob
  ttf_files=("${tmpdir}/${asset_base}-"*.ttf)
  shopt -u nullglob
  [[ "${#ttf_files[@]}" -gt 0 ]] || die "no ${asset_base}-*.ttf found after extraction"

  # Replace only SarasaTermSCNerd*.ttf in DEST_DIR to avoid trampling unrelated fonts.
  ${sudo_cmd} rm -f "${DEST_DIR}/${asset_base}-"*.ttf 2>/dev/null || true
  for f in "${ttf_files[@]}"; do
    ${sudo_cmd} install -m 0644 "${f}" "${DEST_DIR}/$(basename "${f}")"
  done
  echo "[install] installed ${#ttf_files[@]} .ttf files into ${DEST_DIR}"
fi

echo "[install] refresh fontconfig cache..."
if [[ "${SCOPE}" == "system" ]]; then
  ${sudo_cmd} fc-cache -f "${DEST_DIR}"
else
  fc-cache -f "${DEST_DIR}"
fi

echo "[install] done"
