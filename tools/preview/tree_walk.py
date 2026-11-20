#!/usr/bin/env python3
"""The treewalk preview's crops (tools/preview/preview.luau, scenario treewalk).

Usage: python3 tools/preview/tree_walk.py <outdir of render.sh treewalk ...> [scale]

Reads the dump in <outdir>/_logs (PREVIEW_KEEP=1) and writes, next to the frames:
  treewalk_worst_marked.png  the worst check's frame over the tree's box, the pixels off a fresh cast marked
                             (magenta: ink alone, red: sky over a part, blue: a part over sky, orange: the rest;
                             ties are left unmarked), scaled up with nearest;
  treewalk_end_vs_fresh.png  the last frame and the same view baked afresh, side by side over the tree's box, and
                             the screen pixels that differ in white.
"""
import glob
import os
import re
import sys

from PIL import Image, ImageChops

COLOURS = {"1": (255, 40, 40), "2": (40, 90, 255), "3": (255, 150, 0), "4": (255, 0, 255)}


def main():
    out = sys.argv[1]
    scale = int(sys.argv[2]) if len(sys.argv) > 2 else 3
    dumps = glob.glob(os.path.join(out, "_logs", "dump_*.txt"))
    if not dumps:
        sys.exit("no dump in %s/_logs (render with PREVIEW_KEEP=1)" % out)
    lines = open(dumps[0], encoding="utf-8", errors="replace").read().splitlines()
    k = 3
    for line in lines:
        m = re.search(r"layer (\d+)x(\d+) K (\d+)", line)
        if m:
            k = int(m.group(3))
    # the last TWBOX block is the worst check's
    box, rows = None, {}
    for line in lines:
        if line.startswith("TWBOX"):
            box = [int(v) for v in line.split()[1:5]]
            rows = {}
        elif line.startswith("TWMASK") and box is not None:
            _, y, row = line.split(" ", 2)
            rows[int(y)] = row
    frames = {os.path.basename(f): f for f in glob.glob(os.path.join(out, "treewalk_*.png"))}
    worst = next((f for n, f in frames.items() if n.startswith("treewalk_worst_")), None)
    if box and worst:
        x0, y0, x1, y1 = box
        im = Image.open(worst).convert("RGB")
        crop = im.crop((x0 * k, y0 * k, (x1 + 1) * k, (y1 + 1) * k))
        px = crop.load()
        n = 0
        for y, row in rows.items():
            for i, c in enumerate(row):
                col = COLOURS.get(c)
                if col is None:
                    continue
                n += 1
                bx, by = i * k, (y - y0) * k
                for dy in range(k):
                    for dx in range(k):
                        if (dx in (0, k - 1)) or (dy in (0, k - 1)):
                            px[bx + dx, by + dy] = col
        crop = crop.resize((crop.width * scale // k, crop.height * scale // k), Image.NEAREST)
        dest = os.path.join(out, "treewalk_worst_marked.png")
        crop.save(dest)
        print("%s: %d pixels off marked over the tree's box %s" % (dest, n, box))
    end = next((f for n, f in frames.items() if n.startswith("treewalk_end_")), None)
    fresh = next((f for n, f in frames.items() if n.startswith("treewalk_fresh_")), None)
    if end and fresh:
        a, b = Image.open(end).convert("RGB"), Image.open(fresh).convert("RGB")
        d = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v else 0)
        bb = d.getbbox()
        w, h = a.size
        region = (w // 4, 0, w * 3 // 4, h * 2 // 3)
        tiles = [x.crop(region) for x in (a, b, d.convert("RGB"))]
        tw, th = tiles[0].size
        sheet = Image.new("RGB", (tw * 3, th))
        for i, t in enumerate(tiles):
            sheet.paste(t, (tw * i, 0))
        dest = os.path.join(out, "treewalk_end_vs_fresh.png")
        sheet.save(dest)
        print("%s: the frames differ in %d screen px (box %s)" % (dest, sum(d.histogram()[1:]), bb))


if __name__ == "__main__":
    main()
