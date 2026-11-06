#!/usr/bin/env python3
"""Label a contact sheet's cells with their ids (the pfoods scenario logs "@@CELL frame id x y size K").

Usage: python3 tools/preview/label_cells.py <outdir> [device]
Reads <outdir>/_logs/*.txt (render.sh with PREVIEW_KEEP=1) and writes <frame>_<device>_labelled.png next to each
captured <frame>_<device>.png: the id under each picture, small, in dark ink.
"""
import glob
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

out = sys.argv[1]
device = sys.argv[2] if len(sys.argv) > 2 else "desktop"
cells = {}
for path in glob.glob(os.path.join(out, "_logs", "*.txt")):
    if device not in os.path.basename(path):
        continue
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.search(r"@@CELL (\S+) (\S+) (\d+) (\d+) (\d+) (\d+)", line)
        if m:
            frame, cid, x, y, size, k = m.group(1), m.group(2), int(m.group(3)), int(m.group(4)), int(m.group(5)), int(m.group(6))
            cells.setdefault(frame, {})[cid] = (x, y, size, k)
try:
    font = ImageFont.truetype("DejaVuSans.ttf", 11)
except OSError:
    font = ImageFont.load_default()
for frame, items in cells.items():
    src = os.path.join(out, "%s_%s.png" % (frame, device))
    if not os.path.exists(src):
        continue
    im = Image.open(src).convert("RGB")
    d = ImageDraw.Draw(im)
    for cid, (x, y, size, k) in items.items():
        tx, ty = x * k, (y + size) * k + 1
        d.text((tx, ty), cid[:17], fill=(43, 30, 46), font=font)
    dst = os.path.join(out, "%s_%s_labelled.png" % (frame, device))
    im.save(dst)
    print(dst)
