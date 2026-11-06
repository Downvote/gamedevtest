# Stitch the tiles of a panorama scenario (pdecopan) into one PNG: each tile is one capture at pan (px, py) art px
# with K screen px per art px, logged as "tile <name> <px> <py> <K>". Usage: stitch.py <outdir>/_logs <outdir> <out.png>
import re, sys, glob
from PIL import Image
logdir, imgdir, out = sys.argv[1], sys.argv[2], sys.argv[3]
tiles = []
for f in glob.glob(logdir + "/*.txt"):
    for line in open(f, errors="replace"):
        m = re.search(r"tile (pdecopan_\d+) (-?\d+) (-?\d+) (\d+)", line)
        if m:
            tiles.append((m.group(1), int(m.group(2)), int(m.group(3)), int(m.group(4))))
seen = {}
for t in tiles:
    seen[t[0]] = t
tiles = sorted(seen.values())
K = tiles[0][3]
x0 = min(t[1] for t in tiles); y0 = min(t[2] for t in tiles)
imgs = {t[0]: Image.open(glob.glob(f"{imgdir}/{t[0]}_*desktop.png")[0]).convert("RGB") for t in tiles}
w, h = next(iter(imgs.values())).size
W = max((t[1] - x0) * K for t in tiles) + w
H = max((t[2] - y0) * K for t in tiles) + h
canvas = Image.new("RGB", (W, H), (0, 0, 0))
for name, px, py, k in reversed(tiles):
    canvas.paste(imgs[name], ((px - x0) * K, (py - y0) * K))
canvas.save(out)
print("stitched", len(tiles), "tiles", canvas.size)
