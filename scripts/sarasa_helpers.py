def zh_family(name):
    res = name.replace(looseName, "更纱终端书呆黑体-简")
    res = res.replace(compactName, "更纱终端书呆黑体-简")
    return res

def en_subfamily(compact):
    return compact.replace("Italic", " Italic").strip()

def zh_subfamily(compact):
    sub_family_dict = {
        "ExtraLight": "特细体",
        "ExtraLightItalic":"特细斜体",
        "Light":"细体",
        "LightItalic":"细斜体",
        "Regular":"常规体",
        "Italic":"斜体",
        "SemiBold":"中粗体",
        "SemiBoldItalic":"中粗斜体",
        "Bold":"粗体",
        "BoldItalic":"粗斜体"
    }
    return sub_family_dict[compact]

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

