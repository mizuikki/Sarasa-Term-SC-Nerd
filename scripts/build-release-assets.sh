#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-${ROOT_DIR}}"

SARASA_DIR_HINTED="${SARASA_DIR_HINTED:-${ROOT_DIR}/tmp/sarasa}"
SARASA_DIR_UNHINTED="${SARASA_DIR_UNHINTED:-${ROOT_DIR}/tmp/sarasa-unhinted}"
FONT_PATCHER_DIR="${FONT_PATCHER_DIR:-${ROOT_DIR}/tmp/FontPatcher}"

run_one() {
  local sarasa_dir="$1"
  local out_prefix="$2"

  rm -rf "${WORK_DIR}/sarasa" "${WORK_DIR}/sarasa-nerd" || true
  rm -rf "${WORK_DIR}/src" "${WORK_DIR}/bin" "${WORK_DIR}/glyphnames.json" "${WORK_DIR}/readme.md" || true
  mkdir -p "${WORK_DIR}/sarasa"
  cp -f "${sarasa_dir}"/*.ttf "${WORK_DIR}/sarasa/"

  if [[ ! -d "${FONT_PATCHER_DIR}/src" ]]; then
    echo "[build] ERROR: missing FontPatcher resources in ${FONT_PATCHER_DIR}"
    echo "[build]        run scripts/refresh-upstream.sh first"
    exit 1
  fi

  # Bring Nerd Fonts resources next to font-patcher, then overwrite the patcher script.
  cp -R "${FONT_PATCHER_DIR}/src" "${WORK_DIR}/"
  cp -R "${FONT_PATCHER_DIR}/bin" "${WORK_DIR}/"
  cp -f "${FONT_PATCHER_DIR}/glyphnames.json" "${WORK_DIR}/glyphnames.json"

  cp -f "${ROOT_DIR}/scripts/font-patcher" "${WORK_DIR}/font-patcher"
  chmod +x "${WORK_DIR}/font-patcher"
  sed -i.bak '1{s|^#!/usr/bin/env python$|#!/usr/bin/env python3|;}' "${WORK_DIR}/font-patcher" || true
  rm -f "${WORK_DIR}/font-patcher.bak" || true
  cp -f "${ROOT_DIR}/scripts/otf2otc.py" "${WORK_DIR}/otf2otc.py"

  # Ensure build uses local font-patcher copy from WORK_DIR
  (cd "${WORK_DIR}" && SARASA_DIR="sarasa" bash -xeu scripts/build)

  if [[ -n "${out_prefix}" ]]; then
    (
      cd "${WORK_DIR}/sarasa-nerd"
      mv SarasaTermSCNerd.ttf.tar.gz "${out_prefix}.ttf.tar.gz"
      mv SarasaTermSCNerd.ttc.tar.gz "${out_prefix}.ttc.tar.gz"
      mv SarasaTermSCNerd.ttf.7z "${out_prefix}.ttf.7z"
      mv SarasaTermSCNerd.ttc.7z "${out_prefix}.ttc.7z"
    )
  fi

  mkdir -p "${WORK_DIR}/dist"
  cp -f "${WORK_DIR}/sarasa-nerd/"SarasaTermSCNerd*.tar.gz "${WORK_DIR}/dist/"
  cp -f "${WORK_DIR}/sarasa-nerd/"SarasaTermSCNerd*.7z "${WORK_DIR}/dist/"
}

echo "[build] hinted from: ${SARASA_DIR_HINTED}"
run_one "${SARASA_DIR_HINTED}" ""

echo "[build] unhinted from: ${SARASA_DIR_UNHINTED}"
run_one "${SARASA_DIR_UNHINTED}" "SarasaTermSCNerd-Unhinted"

echo "[build] dist files:"
ls -la "${WORK_DIR}/dist"
