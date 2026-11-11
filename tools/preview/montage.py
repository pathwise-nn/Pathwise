#!/usr/bin/env python3
"""Every scene in one picture: preview/<scene>.png side by side, named.

    python3 tools/preview/montage.py [scene ...]   -> preview/all.png
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.getcwd()
OUT = os.path.join(ROOT, "preview")
names = sys.argv[1:] or sorted(f[:-4] for f in os.listdir(OUT) if f.endswith(".png") and "@" not in f and not f.startswith(("themes", "all")))
TW, TH, PAD, CAP, COLS = 800, 450, 24, 46, 3
font = ImageFont.truetype(os.path.join(ROOT, "Pathwise", "Media", "Fonts", "Inter-SemiBold.ttf"), 26)
rows = (len(names) + COLS - 1) // COLS
sheet = Image.new("RGB", (PAD + COLS * (TW + PAD), PAD + rows * (TH + CAP + PAD)), (12, 16, 22))
d = ImageDraw.Draw(sheet)
for i, n in enumerate(names):
    x, y = PAD + (i % COLS) * (TW + PAD), PAD + (i // COLS) * (TH + CAP + PAD)
    d.text((x, y + 8), n, font=font, fill=(240, 245, 250))
    sheet.paste(Image.open(os.path.join(OUT, n + ".png")).convert("RGB").resize((TW, TH), Image.LANCZOS), (x, y + CAP))
sheet.save(os.path.join(OUT, "all.png"))
print("wrote preview/all.png", sheet.size)
