# Sarasa Term SC Nerd

Sarasa Term SC Nerd is a patched build of [Sarasa Term SC](https://github.com/be5invis/Sarasa-Gothic) with selected [Nerd Fonts](https://github.com/ryanoasis/nerd-fonts) glyphs added for terminal and editor use.

It is designed for setups that need all of the following at once:
- reliable 2:1 CJK and Latin alignment
- monospaced behavior in terminals and code editors
- Nerd Fonts symbols for prompts, statuslines, and developer tooling

## Highlights

- Built on `Sarasa Term SC`, a widely used CJK programming font with strong mixed-language alignment.
- Adds Nerd Fonts glyphs while preserving terminal-friendly spacing.
- Includes both hinted and unhinted release artifacts.
- Keeps the original `Sarasa Term SC` installable alongside the patched family.
- Applies extra metadata and table fixes for better behavior on Windows and other font consumers.
- Limits Material Design icon coverage to stay within the OpenType glyph budget.

## Installation

### Download a release

Download the latest assets from [Releases](https://github.com/mizuikki/Sarasa-Term-SC-Nerd/releases).

- `*.ttf`: one file per style
- `*.ttc`: a collection containing all styles
- `*Unhinted*`: unhinted builds for systems where hinted fonts render slowly

### Homebrew

```sh
brew tap laishulu/homebrew
brew install font-sarasa-nerd
```

## Usage

Set your terminal, editor, or theme to use `Sarasa Term SC Nerd`.

Common use cases:
- shell prompts such as `Starship`
- statusline-heavy terminal workflows
- editors that rely on Nerd Fonts icons
- mixed Chinese and English text in monospaced layouts

## Screenshots

Text rendering (`Regular`):

![Text rendering](screenshots/character.png)

Nerd Fonts icons in a prompt:

![Icon rendering](screenshots/nerd.jpg)

Table alignment in terminal `emacs` / `org-mode`:

![Alignment example](screenshots/align.png)

## Upstream Versions

- Sarasa Term SC: `1.0.37`
- Nerd Fonts: `3.4.0`
- Font Patcher: `4.20.3`

Version pins used by the current tooling also live in [scripts/upstream-versions.env](/home/mnm/code/github/Sarasa-Term-SC-Nerd/scripts/upstream-versions.env:1).

## Build From Source

### Requirements

- `gh`
- `python3`
- `fontforge`
- `python3-fontforge`
- `fonttools` / `ttx`
- `p7zip`
- `unzip`
- `tar`
- `jq`

On Ubuntu or Debian:

```sh
sudo apt update
sudo apt install -y fontforge python3-fontforge python3-fonttools p7zip jq unzip
```

### Build release assets

```sh
scripts/refresh-upstream.sh
scripts/build-release-assets.sh
ls -la dist/
```

This downloads pinned upstream assets, regenerates `scripts/font-patcher`, builds hinted and unhinted outputs, and writes release archives to `dist/`.

On macOS, use the Python interpreter bundled with FontForge:

```sh
brew install fontforge
pipenv --site-packages --python=/Applications/FontForge.app/Contents/Frameworks/Python.framework/Versions/Current/bin/python3
```

## Repository Layout

- `scripts/`: build, refresh, verification, and release tooling
- `dist/`: generated release archives
- `screenshots/`: README assets
- `font-patcher.patch`: local patch applied on top of upstream Nerd Fonts `font-patcher`

More script-level details are documented in [scripts/README.md](/home/mnm/code/github/Sarasa-Term-SC-Nerd/scripts/README.md:1).

## Notes

- Material Design icons are intentionally subsetted. The practical glyph cap used here is `65534`, not `65535`, because `65535` is commonly treated as a sentinel value by font tooling.
- Italic styles can contain more glyphs than regular styles, so glyph-budget fitting is based on the italic worst case.
- If font rendering is slow on your system, prefer the unhinted release artifacts.

## License

See [LICENSE](/home/mnm/code/github/Sarasa-Term-SC-Nerd/LICENSE:1).
