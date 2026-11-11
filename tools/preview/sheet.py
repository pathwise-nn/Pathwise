#!/usr/bin/env python3
"""One picture of every theme: preview/hub@<theme>.png side by side, named.

    python3 tools/preview/preview.py themes && node tools/preview/shot.js
    python3 tools/preview/sheet.py [scene]   -> preview/themes.png (the hub),
                                                preview/themes-<scene>.png
"""
import sys
import os
import re

from PIL import Image, ImageDraw, ImageFont

ROOT = os.getcwd()
OUT = os.path.join(ROOT, "preview")
src = open(os.path.join(ROOT, "Pathwise", "Theme", "Signature.lua")).read()
themes = re.findall(r'\{ key = "(\w+)", name = "([^"]+)", mode = "(\w+)"', src)
TW, TH, PAD, CAP, COLS = 960, 540, 28, 54, 3
font = ImageFont.truetype(os.path.join(ROOT, "Pathwise", "Media", "Fonts", "Inter-SemiBold.ttf"), 30)
small = ImageFont.truetype(os.path.join(ROOT, "Pathwise", "Media", "Fonts", "Inter-Regular.ttf"), 24)
scene = sys.argv[1] if len(sys.argv) > 1 else "hub"
rows = (len(themes) + COLS - 1) // COLS
sheet = Image.new("RGB", (PAD + COLS * (TW + PAD), PAD + rows * (TH + CAP + PAD)), (12, 16, 22))
d = ImageDraw.Draw(sheet)
for i, (key, name, mode) in enumerate(themes):
    path = os.path.join(OUT, f"{scene}@{key}.png")
    if not os.path.exists(path):
        continue
    x = PAD + (i % COLS) * (TW + PAD)
    y = PAD + (i // COLS) * (TH + CAP + PAD)
    d.text((x, y + 8), name, font=font, fill=(240, 245, 250))
    d.text((x + font.getlength(name) + 14, y + 13), mode.capitalize(), font=small, fill=(154, 175, 192))
    im = Image.open(path).convert("RGB").resize((TW, TH), Image.LANCZOS)
    sheet.paste(im, (x, y + CAP))
name = "themes.png" if scene == "hub" else f"themes-{scene}.png"
sheet.save(os.path.join(OUT, name))
print("wrote preview/" + name, sheet.size)
