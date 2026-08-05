#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib
import re
import sys


def _read_text(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def _write_text(path: pathlib.Path, data: str) -> None:
    path.write_text(data, encoding="utf-8", newline="\n")


def _parse_material_ranges(path: pathlib.Path) -> list[tuple[int, int]]:
    ranges: list[tuple[int, int]] = []
    for raw in _read_text(path).splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        start_s, end_s = line.split("-", 1)
        start = int(start_s, 16)
        end = int(end_s, 16)
        if start > end:
            raise ValueError(f"Invalid Material range: {line}")
        ranges.append((start, end))
    return ranges


def _render_material_block(ranges: list[tuple[int, int]]) -> str:
    lines = ["            # FOR SARASA"]
    for start, end in ranges:
        lines.append(
            "            {'Enabled': self.args.material,             'Name': \"Material\",                "
            f"'Filename': \"materialdesign/MaterialDesignIconsDesktop.ttf\",  'Exact': True,  "
            f"'SymStart': 0x{start:05X},'SymEnd': 0x{end:05X},'SrcStart': None,   "
            "'ScaleRules': MDI_SCALE_LIST,   'Attributes': SYM_ATTR_DEFAULT},"
        )
    return "\n".join(lines)


def _apply_simple_replacements(upstream_text: str, material_block: str) -> str:
    """
    Apply the bulk of our changes by extracting the added lines from the patch
    and inserting them around stable anchors. This avoids depending on exact
    upstream line numbers.
    """
    out = upstream_text

    # 1) Add SARASA globals after projectNameSingular definition.
    sarasa_globals = (
        "\n"
        "# FOR SARASA\n"
        "projectName = \"Nerds\"\n"
        "projectNameAbbreviation = \"\"\n"
        "projectNameSingular = projectName[:-1]\n"
        "subFamily = \"\"\n"
        "looseName = \"Sarasa Term SC Nerd\"\n"
        "compactName = \"SarasaTermSCNerd\"\n"
    )
    anchor = 'projectNameSingular = projectName[:-1]\n'
    if sarasa_globals not in out:
        if anchor not in out:
            raise ValueError("Anchor for SARASA globals not found")
        out = out.replace(anchor, anchor + sarasa_globals, 1)

    # 2) Force monospaced checks for Sarasa.
    out = re.sub(
        r"return 1 if panose_mono else 0\n",
        "\n    # FOR SARASA\n    return 1\n    # return 1 if panose_mono else 0\n",
        out,
        count=1,
    )
    out = out.replace(
        "# Some fonts lie (or have not any Panose flag set), spot check monospaced:\n",
        "# Some fonts lie (or have not any Panose flag set), spot check monospaced:\n\n"
        "    # FOR SARASA\n"
        "    return (True, None)\n\n",
        1,
    )

    # 3) Output filename normalization (SarasaTermSCNerd-Subfamily.ttf).
    out = out.replace(
        "sanitize_filename(fontname) + self.args.extension))\n",
        "sanitize_filename(fontname) + self.args.extension))\n\n"
        "            # FOR SARASA\n"
        "            outfile = os.path.normpath(os.path.join(\n"
        "                sanitize_filename(self.args.outputdir, True),\n"
        "                f'{compactName}-{self.get_subfamily()}.ttf'\n"
        "            ))\n",
        1,
    )

    # 4) Post-processing: build hdmx and fix post table.
    out = out.replace(
        "print(message)\n",
        "print(message)\n\n"
        "        # FOR SARASA: build hdmx table\n"
        "        print(\"Building hdmx table and fix post table\")\n"
        "        post_fix(self.args.font, outfile)\n\n",
        1,
    )

    # 5) Clean suffix naming to keep family names stable.
    suffix_marker = "\n        # add mono signifier to beginning of name suffix\n"
    if suffix_marker not in out:
        raise ValueError("Could not find suffix naming marker")
    out = out.replace(
        suffix_marker,
        "\n        # FOR SARASA: clean file name\n"
        "        additionalFontNameSuffix = \"\" + projectNameSingular\n"
        "        verboseAdditionalFontNameSuffix = \"\" + projectNameSingular\n"
        + suffix_marker,
        1,
    )
    out = out.replace(
        "variant_full = \"\"\n",
        "variant_full = \"\"\n\n"
        "        # FOR SARASA: clean file name\n"
        "        variant_abbrev = \"\"\n"
        "        variant_full = \"\"\n",
        1,
    )
    out = out.replace(
        "additionalFontNameSuffix = \" \" + projectNameSingular + variant_full + additionalFontNameSuffix\n",
        "additionalFontNameSuffix = \" \" + projectNameSingular + variant_full + additionalFontNameSuffix\n\n"
        "        # FOR SARASA: clean file name\n"
        "        additionalFontNameSuffix = \"\" + projectNameSingular\n"
        "        verboseAdditionalFontNameSuffix = \"\" + projectNameSingular\n",
        1,
    )

    # 6) Family fallback style derived from filename subfamily.
    out = out.replace(
        "familyname = fontname\n",
        "familyname = fontname\n\n"
        "        # FOR SARASA\n"
        "        familyname = looseName\n"
        "        fallbackStyle = self.get_subfamily()\n",
        1,
    )

    # 7) Comment string customizations.
    out = out.replace(
        "projectInfo = (\n"
        "            \"Patched with '\" + projectName + \" Patcher' (https://github.com/ryanoasis/nerd-fonts)\\n\\n\"\n",
        "projectInfo = (\n"
        "            # \"Patched with '\" + projectName + \" Patcher' (https://github.com/ryanoasis/nerd-fonts)\\n\\n\"\n"
        "            \"Patched with 'Sarasa Term SC Nerd Patcher' (https://github.com/laishulu/Sarasa-Term-SC-Nerd)\\n\\n\"\n",
        1,
    )
    out = out.replace(
        "\"* Development Website: https://github.com/ryanoasis/nerd-fonts\\n\"\n"
        "            \"* Changelog: https://github.com/ryanoasis/nerd-fonts/blob/-/changelog.md\"",
        "# \"* Development Website: https://github.com/ryanoasis/nerd-fonts\\n\"\n"
        "            # \"* Changelog: https://github.com/ryanoasis/nerd-fonts/blob/-/changelog.md\"",
        1,
    )

    # 8) Override SFNT naming + unique id to follow Sarasa naming conventions.
    if "compat = compatibility_name(preferredFamily, preferredStyle)" not in out:
        marker = "n.rename_font(font)\n\n"
        insert = (
            "\n"
            "        # FOR SARASA\n"
            "        preferredFamily = looseName\n"
            "        subFamily = self.get_subfamily()\n"
            "        preferredStyle = style_name(subFamily)\n"
            "        compat = compatibility_name(preferredFamily, preferredStyle)\n"
            "        compatFamily = compat['family']\n"
            "        compatStyle = compat['style']\n"
            "        fullName = full_name(compatFamily, compatStyle)\n"
            "        uniqueID = f\"{preferredFamily} {preferredStyle}\"\n"
            "\n"
            "        font.familyname = compatFamily\n"
            "        font.fullname = fullName\n"
            "        font.fontname = postscript_name(preferredFamily, preferredStyle)\n"
            "\n"
            "        font.appendSFNTName(str(\"English (US)\"), str(\"UniqueID\"), uniqueID)\n"
            "        font.appendSFNTName(str(\"Chinese (PRC)\"), str(\"UniqueID\"), uniqueID)\n"
            "        font.appendSFNTName(str('English (US)'), str('Fullname'), fullName)\n"
            "        font.appendSFNTName(str(\"Chinese (PRC)\"), str(\"Fullname\"), fullName)\n"
            "\n"
            "        font.appendSFNTName(str('English (US)'), str('Family'), compatFamily)\n"
            "        font.appendSFNTName(str('Chinese (PRC)'), str('Family'), compatFamily)\n"
            "        font.appendSFNTName(str('English (US)'), str('SubFamily'), compatStyle)\n"
            "        font.appendSFNTName(str('Chinese (PRC)'), str('SubFamily'), compatStyle)\n"
            "\n"
            "        font.appendSFNTName(str('English (US)'), str('Preferred Family'), preferredFamily)\n"
            "        font.appendSFNTName(str('Chinese (PRC)'), str('Preferred Family'), preferredFamily)\n"
            "        font.appendSFNTName(str('English (US)'), str('Preferred Styles'), preferredStyle)\n"
            "        font.appendSFNTName(str('Chinese (PRC)'), str('Preferred Styles'), preferredStyle)\n"
            "\n"
        )
        if marker not in out:
            raise ValueError("Could not find rename_font marker for SFNT override insertion")
        out = out.replace(marker, marker + insert, 1)

    # 9) Force width == 1 cell.
    out = out.replace(
        "if self.args.single or ('pa' not in stretch and '2' not in stretch) or '1' in stretch:\n"
        "            return 1\n"
        "        return 2\n",
        "\n        # FOR SARASA\n        return 1\n\n"
        "        # if self.args.single or ('pa' not in stretch and '2' not in stretch) or '1' in stretch:\n"
        "        #     return 1\n"
        "        # return 2\n",
        1,
    )

    # 10) Add get_subfamily() helper.
    if "def get_subfamily(self):" not in out:
        marker = "        return None\n\n"
        insert = (
            "    # FOR SARASA: extract subFamily from font name\n"
            "    def get_subfamily(self):\n"
            "        file_name = self.args.font.split('.')[-2]\n"
            "        return file_name.split('-')[-1]\n\n"
        )
        if marker not in out:
            raise ValueError("Could not find insertion marker for get_subfamily")
        out = out.replace(marker, marker + insert, 1)

    # 11) Inject naming helpers + post_fix/hmdx at end of file, before __main__.
    if "def post_fix(" not in out:
        main_marker = "if __name__ == \"__main__\":\n"
        if main_marker not in out:
            raise ValueError("Could not locate __main__ marker for helper insertion")
        helper_block = _read_text(pathlib.Path(__file__).with_name("sarasa_helpers.py"))
        out = out.replace(main_marker, helper_block + "\n\n" + main_marker, 1)

    # 12) Material icon range narrowing (replace single upstream material entry).
    out = re.sub(
        r"^\s*\{\s*'Enabled': self\.args\.material,.*'Filename': \"materialdesign/MaterialDesignIconsDesktop\.ttf\".*\}\s*,\s*$",
        lambda m: material_block,
        out,
        flags=re.MULTILINE,
        count=1,
    )

    return out


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--upstream", required=True, type=pathlib.Path)
    p.add_argument("--patch", required=True, type=pathlib.Path)
    p.add_argument("--active-material", required=True, type=pathlib.Path)
    p.add_argument("--out", required=True, type=pathlib.Path)
    args = p.parse_args()

    upstream_text = _read_text(args.upstream)
    _ = _read_text(args.patch)
    material_ranges = _parse_material_ranges(args.active_material)
    material_block = _render_material_block(material_ranges)
    out_text = _apply_simple_replacements(upstream_text, material_block)
    compile(out_text, str(args.out), "exec")

    _write_text(args.out, out_text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
