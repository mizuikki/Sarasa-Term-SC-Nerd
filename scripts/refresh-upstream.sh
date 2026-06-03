#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="${ROOT_DIR}/tmp"
FETCH_ONLY=0
GENERATE_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fetch-only)
      FETCH_ONLY=1
      shift 1
      ;;
    --generate-only)
      GENERATE_ONLY=1
      shift 1
      ;;
    -h|--help)
      cat <<'EOF'
Usage: scripts/refresh-upstream.sh [--fetch-only | --generate-only]

Default behavior downloads upstream assets into tmp/ and regenerates scripts/font-patcher.
EOF
      exit 0
      ;;
    *)
      echo "[refresh] ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "${FETCH_ONLY}" -eq 1 && "${GENERATE_ONLY}" -eq 1 ]]; then
  echo "[refresh] ERROR: --fetch-only and --generate-only are mutually exclusive" >&2
  exit 1
fi

if [[ -f "${ROOT_DIR}/scripts/upstream-versions.env" ]]; then
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/scripts/upstream-versions.env"
fi

SARASA_TAG="${SARASA_TAG:-v1.0.37}"
NERD_TAG="${NERD_TAG:-v3.4.0}"

SARASA_ASSET_HINTED="${SARASA_ASSET_HINTED:-SarasaTermSC-TTF-1.0.37.7z}"
SARASA_ASSET_UNHINTED="${SARASA_ASSET_UNHINTED:-SarasaTermSC-TTF-Unhinted-1.0.37.7z}"

mkdir -p "${TMP_DIR}"

echo "[refresh] tmp: ${TMP_DIR}"
echo "[refresh] Sarasa: ${SARASA_TAG} (${SARASA_ASSET_HINTED}, ${SARASA_ASSET_UNHINTED})"
echo "[refresh] Nerd Fonts: ${NERD_TAG} (FontPatcher.zip)"

command -v gh >/dev/null || { echo "[refresh] ERROR: gh not found"; exit 1; }
command -v unzip >/dev/null || { echo "[refresh] ERROR: unzip not found"; exit 1; }
command -v 7zr >/dev/null || { echo "[refresh] ERROR: 7zr not found (p7zip)"; exit 1; }
command -v python3 >/dev/null || { echo "[refresh] ERROR: python3 not found"; exit 1; }

if [[ "${GENERATE_ONLY}" -eq 0 ]]; then
  rm -rf "${TMP_DIR}/sarasa" "${TMP_DIR}/sarasa-unhinted" "${TMP_DIR}/nerd-fonts"
  mkdir -p "${TMP_DIR}/sarasa" "${TMP_DIR}/sarasa-unhinted" "${TMP_DIR}/nerd-fonts"

  echo "[refresh] Download Sarasa hinted..."
  gh release download -R be5invis/Sarasa-Gothic "${SARASA_TAG}" -p "${SARASA_ASSET_HINTED}" -D "${TMP_DIR}/sarasa"
  (
    cd "${TMP_DIR}/sarasa"
    7zr x "${SARASA_ASSET_HINTED}" >/dev/null
  )

  echo "[refresh] Download Sarasa unhinted..."
  gh release download -R be5invis/Sarasa-Gothic "${SARASA_TAG}" -p "${SARASA_ASSET_UNHINTED}" -D "${TMP_DIR}/sarasa-unhinted"
  (
    cd "${TMP_DIR}/sarasa-unhinted"
    7zr x "${SARASA_ASSET_UNHINTED}" >/dev/null
  )

  echo "[refresh] Download Nerd Fonts FontPatcher..."
  gh release download -R ryanoasis/nerd-fonts "${NERD_TAG}" -p "FontPatcher.zip" -D "${TMP_DIR}/nerd-fonts"

  rm -rf "${TMP_DIR}/FontPatcher"
  mkdir -p "${TMP_DIR}/FontPatcher"
  unzip -q "${TMP_DIR}/nerd-fonts/FontPatcher.zip" -d "${TMP_DIR}/FontPatcher"
fi

if [[ ! -f "${TMP_DIR}/FontPatcher/font-patcher" ]]; then
  echo "[refresh] ERROR: font-patcher not found in FontPatcher.zip"
  exit 1
fi

echo "[refresh] Apply local patch to upstream font-patcher..."
cp "${TMP_DIR}/FontPatcher/font-patcher" "${TMP_DIR}/FontPatcher/font-patcher.patched"
python3 "${ROOT_DIR}/scripts/apply-font-patcher-patch.py" \
  --upstream "${TMP_DIR}/FontPatcher/font-patcher" \
  --patch "${ROOT_DIR}/font-patcher.patch" \
  --active-material "${ROOT_DIR}/scripts/material-icons-active.txt" \
  --out "${ROOT_DIR}/scripts/font-patcher"

sed -i.bak '1{s|^#!/usr/bin/env python$|#!/usr/bin/env python3|;}' "${ROOT_DIR}/scripts/font-patcher" || true
rm -f "${ROOT_DIR}/scripts/font-patcher.bak" || true
chmod +x "${ROOT_DIR}/scripts/font-patcher"
echo "[refresh] Done. Updated scripts/font-patcher"

echo "[refresh] NOTE: local builds require FontForge python bindings."
echo "[refresh]       On Ubuntu/Debian: sudo apt install -y fontforge python3-fontforge python3-fonttools p7zip jq unzip"
