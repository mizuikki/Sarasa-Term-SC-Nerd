def style_name(compact):
    return compact.replace("Italic", " Italic").strip()

def compatibility_name(family, style):
    if style in {"Regular", "Bold", "Italic", "Bold Italic"}:
        return {"family": family, "style": style}

    compat_style = style
    if compat_style.startswith("Extra"):
        compat_style = compat_style.replace("Extra", "X", 1)

    if "Italic" in compat_style:
        return {
            "family": f"{family} {compat_style.replace('Italic', '').strip()}",
            "style": "Italic",
        }

    return {"family": f"{family} {compat_style}", "style": "Regular"}

def full_name(family, style):
    if style == "Regular":
        return family
    return f"{family} {style}"

def postscript_name(family, style):
    return f"{family} {style}".replace(" ", "-")

# FOR SARASA: build hdmx table
import math
from fontTools.ttLib import TTFont, newTable

def post_fix(src_file, dst_file):
    dst_font = TTFont(dst_file, recalcBBoxes=False)
    build_hdmx(dst_font)
    fix_isFixedPitch(dst_font)

    src_font = TTFont(src_file)
    dst_font["OS/2"].xAvgCharWidth = src_font["OS/2"].xAvgCharWidth
    src_font.close()

    dst_font.save(dst_file)
    dst_font.close()

def build_hdmx(font):
    headFlagInstructionsMayAlterAdvanceWidth = 0x0010
    sarasaHintPpemMin = 11
    sarasaHintPpemMax = 48

    originalFontHead = font["head"]
    originalFontHmtx = font["hmtx"]

    originalFontHead.flags |= headFlagInstructionsMayAlterAdvanceWidth

    hdmxTable = newTable("hdmx")
    hdmxTable.hdmx = {}

    # build hdmx table for odd and hinted ppems only.
    for ppem in range(
        math.floor(sarasaHintPpemMin / 2) * 2 + 1, sarasaHintPpemMax + 1, 2
    ):
        halfUpm = originalFontHead.unitsPerEm / 2
        halfPpem = math.ceil(ppem / 2)
        hdmxTable.hdmx[ppem] = {
            name: math.ceil(width / halfUpm) * halfPpem
            for name, (width, _) in originalFontHmtx.metrics.items()
        }

    font["hdmx"] = hdmxTable

def fix_isFixedPitch(font):
    post = font["post"].__dict__
    post["isFixedPitch"] = 1
