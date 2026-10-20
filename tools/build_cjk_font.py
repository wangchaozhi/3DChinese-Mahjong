"""生成 Web 版用的中文子集字体 fonts/cjk_subset.ttf。

浏览器里读不到系统字体，main.gd 在 Web 平台改用这份内置字体。
只收录 scripts/*.gd 字符串字面量里出现的字符，新增界面文案后需要重新运行：

    pip install fonttools
    python tools/build_cjk_font.py <NotoSansSC 可变字体或静态字体.ttf>

源字体：Noto Sans SC（SIL Open Font License 1.1，见 fonts/OFL.txt）。
"""
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "fonts" / "cjk_subset.ttf"
WEIGHT = 500


def string_literals(code: str):
    """逐字符扫描 GDScript，产出双引号字符串内容，跳过注释。"""
    i, n = 0, len(code)
    while i < n:
        c = code[i]
        if c == "#":
            while i < n and code[i] != "\n":
                i += 1
        elif c == '"':
            i += 1
            start = i
            while i < n and code[i] != '"':
                i += 2 if code[i] == "\\" else 1
            yield code[start:i]
            i += 1
        else:
            i += 1


def collect_text() -> str:
    chars = {chr(c) for c in range(0x20, 0x7F)}
    for path in sorted((ROOT / "scripts").glob("*.gd")):
        for literal in string_literals(path.read_text(encoding="utf-8")):
            chars.update(literal)
    return "".join(sorted(chars))


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    font = TTFont(sys.argv[1])
    if "fvar" in font:
        font = instancer.instantiateVariableFont(font, {"wght": WEIGHT})
    text = collect_text()
    options = subset.Options()
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.notdef_outline = True
    subsetter = subset.Subsetter(options)
    subsetter.populate(text=text)
    subsetter.subset(font)
    OUT.parent.mkdir(exist_ok=True)
    font.save(OUT)
    print(f"{len(text)} 个字符 -> {OUT.relative_to(ROOT)} ({OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
