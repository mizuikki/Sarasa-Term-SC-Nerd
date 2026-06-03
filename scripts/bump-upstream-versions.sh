#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Bump pinned upstream versions (Sarasa-Gothic + nerd-fonts) and refresh generated font-patcher.

This is intended to be run by CI on a schedule. It updates:
  - scripts/upstream-versions.env (SARASA_TAG/ASSETs, NERD_TAG, FONT_PATCHER_VERSION)
  - scripts/font-patcher (generated from nerd-fonts FontPatcher.zip + local patch)

Usage:
  scripts/bump-upstream-versions.sh [--dry-run] [--write-github-output]

Options:
  --dry-run             Print the planned changes; do not write files.
  --write-github-output Write outputs to $GITHUB_OUTPUT (changed=..., old/new tags).

Outputs (when --write-github-output):
  changed=true|false
  sarasa_old / sarasa_new
  nerd_old / nerd_new
EOF
}

die() {
  echo "[bump] ERROR: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

DRY_RUN=0
WRITE_GITHUB_OUTPUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift 1
      ;;
    --write-github-output)
      WRITE_GITHUB_OUTPUT=1
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

need_cmd gh
need_cmd python3
need_cmd grep
need_cmd sed
need_cmd awk
need_cmd head
need_cmd cut
need_cmd tr

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERS_FILE="${ROOT_DIR}/scripts/upstream-versions.env"

[[ -f "${VERS_FILE}" ]] || die "missing ${VERS_FILE}"

# shellcheck disable=SC1090
source "${VERS_FILE}"

SARASA_OLD="${SARASA_TAG:-}"
NERD_OLD="${NERD_TAG:-}"

[[ -n "${SARASA_OLD}" ]] || die "SARASA_TAG missing in scripts/upstream-versions.env"
[[ -n "${NERD_OLD}" ]] || die "NERD_TAG missing in scripts/upstream-versions.env"

SARASA_NEW="$(gh release view -R be5invis/Sarasa-Gothic --json tagName -q .tagName)"
NERD_NEW="$(gh release view -R ryanoasis/nerd-fonts --json tagName -q .tagName)"

[[ -n "${SARASA_NEW}" ]] || die "failed to query Sarasa-Gothic latest tag"
[[ -n "${NERD_NEW}" ]] || die "failed to query nerd-fonts latest tag"

changed=0
if [[ "${SARASA_NEW}" != "${SARASA_OLD}" || "${NERD_NEW}" != "${NERD_OLD}" ]]; then
  changed=1
fi

write_outputs() {
  local out="${GITHUB_OUTPUT:-}"
  [[ "${WRITE_GITHUB_OUTPUT}" -eq 1 ]] || return 0
  [[ -n "${out}" ]] || die "--write-github-output set but GITHUB_OUTPUT is empty"
  {
    echo "changed=$([[ "${changed}" -eq 1 ]] && echo true || echo false)"
    echo "sarasa_old=${SARASA_OLD}"
    echo "sarasa_new=${SARASA_NEW}"
    echo "nerd_old=${NERD_OLD}"
    echo "nerd_new=${NERD_NEW}"
  } >> "${out}"
}

if [[ "${changed}" -eq 0 ]]; then
  echo "[bump] no upstream updates detected"
  echo "[bump] Sarasa: ${SARASA_OLD}"
  echo "[bump] Nerd Fonts: ${NERD_OLD}"
  write_outputs
  exit 0
fi

echo "[bump] upstream updates detected:"
echo "[bump] Sarasa: ${SARASA_OLD} -> ${SARASA_NEW}"
echo "[bump] Nerd Fonts: ${NERD_OLD} -> ${NERD_NEW}"

# Query Sarasa asset names from the specific release tag, rather than guessing file names.
sarasa_assets="$(gh release view -R be5invis/Sarasa-Gothic "${SARASA_NEW}" --json assets -q '.assets[].name')"

hinted_asset="$(printf '%s\n' "${sarasa_assets}" | grep -E '^SarasaTermSC-TTF-[0-9]+\.[0-9]+\.[0-9]+\.7z$' | head -n 1 || true)"
unhinted_asset="$(printf '%s\n' "${sarasa_assets}" | grep -E '^SarasaTermSC-TTF-Unhinted-[0-9]+\.[0-9]+\.[0-9]+\.7z$' | head -n 1 || true)"

[[ -n "${hinted_asset}" ]] || die "could not find Sarasa hinted asset name in ${SARASA_NEW}"
[[ -n "${unhinted_asset}" ]] || die "could not find Sarasa unhinted asset name in ${SARASA_NEW}"

echo "[bump] Sarasa assets:"
echo "[bump]   hinted:   ${hinted_asset}"
echo "[bump]   unhinted: ${unhinted_asset}"

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "[bump] dry-run: not writing ${VERS_FILE} or refreshing scripts/font-patcher"
  write_outputs
  exit 0
fi

cat > "${VERS_FILE}" <<EOF
SARASA_TAG=${SARASA_NEW}
SARASA_ASSET_HINTED=${hinted_asset}
SARASA_ASSET_UNHINTED=${unhinted_asset}
NERD_TAG=${NERD_NEW}
FONT_PATCHER_VERSION=${FONT_PATCHER_VERSION:-}
EOF

echo "[bump] refresh upstream assets..."
scripts/refresh-upstream.sh --fetch-only

echo "[bump] fit Material icon budget..."
scripts/fit-material-budget.py --write

echo "[bump] regenerate scripts/font-patcher..."
scripts/refresh-upstream.sh --generate-only

font_patcher_version="$(grep -E '^script_version = ' "${ROOT_DIR}/scripts/font-patcher" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)"
[[ -n "${font_patcher_version}" ]] || die "failed to parse script_version from scripts/font-patcher"

# Rewrite versions file with updated FONT_PATCHER_VERSION, preserving key order.
cat > "${VERS_FILE}" <<EOF
SARASA_TAG=${SARASA_NEW}
SARASA_ASSET_HINTED=${hinted_asset}
SARASA_ASSET_UNHINTED=${unhinted_asset}
NERD_TAG=${NERD_NEW}
FONT_PATCHER_VERSION=${font_patcher_version}
EOF

echo "[bump] updated ${VERS_FILE}:"
cat "${VERS_FILE}"

write_outputs
