#!/usr/bin/env python3
# tools/preview/gen_thumbs.py: the build catalog's pictures from the preview scenario "pthumbs" (tools/preview/
# thumbs.luau: each piece drawn by Pixel/Snapshot from the world's camera), tidied to the pixel art rules the way the
# driftlings' portraits are (gen_portraits.tidy; GAME_DESIGN 2: "for pixel art, always dont use mixels. use pixel art
# techniques such as anti-aliasing, avoiding jaggies, and avoiding mixels, and use a 1 pixel outline. respect the pixel
# art grid"), centred, and written to scripts/thumbs.txt for scripts/gen_art.py (the "thumb_<id>" sprites in
# src/client/UI/ThumbData.luau).
#
#   python3 tools/preview/gen_thumbs.py <scenario log> [<log> ...] [--out scripts/thumbs.txt] [--sheet sheet.png]
#                                       [--raw-sheet raw.png] [--zoom 6] [--no-out]
#
# The tidying is the portraits' (no half see-through pixels, the outline made again 1 px on the four sides with cut
# corners, the bands' dither settled, creases 1 px and a shade of the colour beside them, dark parts lifted, near tones
# merged, curves softened inside the outline) with `thin` on: a pole, a spire or a rope keeps its tip and a gap between
# pickets stays open, since a building's thin parts are there on purpose. Each piece comes drawn on a few canvases a
# pixel apart, each at its own scale (thumbs.luau): the biggest drawing that fits the square is kept, cut out round its
# middle, so the silhouette is as big as fits (the renderer fits the parts' boxes, and a roof's wedges or a diamond's
# tips come out a pixel short of them). After the tidying the picture is moved by whole pixels so its silhouette sits
# in the middle of the square. Nothing is ever scaled.
import argparse, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_portraits import parse, tidy  # noqa: E402

PLATE = (0x54, 0x3A, 0x2C)  # the panels' brown plate, as the portraits' sheet
CHARS = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!$%&*+-/:;<=>?@^_~"  # (scripts/gen_art.py's)


def bbox(px):
    ys = [y for y, r in enumerate(px) if any(c is not None for c in r)]
    xs = [x for x in range(len(px[0])) if any(r[x] is not None for r in px)]
    if not xs:
        return None
    return min(xs), min(ys), max(xs), max(ys)


def centre(px):
    """The picture moved by whole pixels so its silhouette is centred (an odd pixel left over goes right and down)."""
    b = bbox(px)
    if b is None:
        return px
    h, w = len(px), len(px[0])
    x0, y0, x1, y1 = b
    dx = (w - (x1 - x0 + 1)) // 2 - x0
    dy = (h - (y1 - y0 + 1) + 1) // 2 - y0
    if dx == 0 and dy == 0:
        return px
    return [[px[y - dy][x - dx] if 0 <= x - dx < w and 0 <= y - dy < h else None for x in range(w)] for y in range(h)]


def pick(cands, size):
    """Of a piece's drawings on canvases of a few sizes (each at its own scale), the biggest whose drawing (the outline
    with it) fits size x size, cut out of its canvas round the drawing's middle. (canvas size, picture)"""
    for n in sorted(cands, reverse=True):
        px = cands[n]
        b = bbox(px)
        if b is None:
            continue
        x0, y0, x1, y1 = b
        if x1 - x0 + 1 > size or y1 - y0 + 1 > size:
            continue
        h, w = len(px), len(px[0])
        ox = min(max(0, x0 - (size - (x1 - x0 + 1)) // 2), w - size)
        oy = min(max(0, y0 - (size - (y1 - y0 + 1)) // 2), h - size)
        return n, [[px[oy + y][ox + x] for x in range(size)] for y in range(size)]
    sys.exit("no drawing fits %d x %d (canvases %s)" % (size, size, sorted(cands)))


def draw(d, px, ox, oy, zoom):
    for y, r in enumerate(px):
        for x, c in enumerate(r):
            if c is not None:
                d.rectangle([ox + x * zoom, oy + y * zoom, ox + (x + 1) * zoom - 1, oy + (y + 1) * zoom - 1], fill=c)


def sheet(pics, path, zoom=6, cols=12, raw=None):
    """Every picture at `zoom`, labelled, on the panels' plate colour (with `raw`: the raw picture to the left of each)."""
    from PIL import Image, ImageDraw
    names = list(pics)
    W = max(len(p[0]) for p in pics.values())
    H = max(len(p) for p in pics.values())
    gap = 3 * zoom
    cw = (W * (2 if raw else 1)) * zoom + gap * (2 if raw else 1)
    ch = H * zoom + 14 + gap
    rows = (len(names) + cols - 1) // cols
    img = Image.new("RGB", (cols * cw + gap, rows * ch + gap), PLATE)
    d = ImageDraw.Draw(img)
    for i, n in enumerate(names):
        ox, oy = gap + (i % cols) * cw, gap + (i // cols) * ch
        if raw:
            draw(d, raw[n], ox, oy, zoom)
            ox2 = ox + W * zoom + gap
        else:
            ox2 = ox
        # (the square's corners, faint: where the picture's edge is)
        for cx, cy in ((ox2 - 1, oy - 1), (ox2 + W * zoom, oy - 1), (ox2 - 1, oy + H * zoom), (ox2 + W * zoom, oy + H * zoom)):
            d.point((cx, cy), fill=(0x8A, 0x6A, 0x52))
        draw(d, pics[n], ox2, oy, zoom)
        d.text((ox, oy + H * zoom + 2), n[:26], fill=(230, 220, 200))
    img.save(path)


def main():
    ap = argparse.ArgumentParser()
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("logs", nargs="+")
    ap.add_argument("--out", default=os.path.join(root, "scripts", "thumbs.txt"))
    ap.add_argument("--sheet", default=None, help="every picture, tidied")
    ap.add_argument("--raw-sheet", default=None, help="every picture raw and tidied, side by side")
    ap.add_argument("--zoom", type=int, default=6)
    ap.add_argument("--size", type=int, default=24, help="the pictures' side")
    ap.add_argument("--no-out", action="store_true")
    a = ap.parse_args()
    drawn = {}
    for log in a.logs:
        drawn.update(parse(log, "@@THUMB "))
    if not drawn:
        sys.exit("no @@THUMB lines in " + " ".join(a.logs))
    cands = {}  # id -> { canvas size: picture }
    for key, px in drawn.items():
        pid, _, n = key.partition("@")
        cands.setdefault(pid, {})[int(n) if n else len(px)] = px
    raw, sizes = {}, {}
    for pid, c in cands.items():
        sizes[pid], raw[pid] = pick(c, a.size)
    # (in the catalog's order: the scenario's runs each drew a share of it)
    order = []
    try:
        import re
        with open(os.path.join(root, "src", "shared", "Data", "Buildings.luau")) as f:
            order = re.findall(r'\bB\(\{ id = "([a-z0-9_]+)"', f.read())
    except OSError:
        pass
    rank = {n: i for i, n in enumerate(order)}
    missing = [n for n in order if n != "tree" and n not in raw]
    if missing and not a.no_out:
        sys.exit("no picture of %d pieces (%s): scripts/thumbs.txt left as it was" % (len(missing), " ".join(missing[:20])))
    names = sorted(raw, key=lambda n: (rank.get(n, len(rank)), n))
    raw = {n: raw[n] for n in names}
    pics = {n: centre(tidy(p, thin=True)) for n, p in raw.items()}
    if a.sheet:
        sheet(pics, a.sheet, a.zoom)
    if a.raw_sheet:
        sheet(pics, a.raw_sheet, a.zoom, cols=8, raw=raw)
    if not a.no_out:
        L = ["# GENERATED by tools/preview/gen_thumbs.py from the preview scenario \"pthumbs\" (sh tools/preview/thumbs.sh):",
             "# the build catalog's pictures drawn from the pieces' models, tidied to the pixel art rules. scripts/gen_art.py",
             "# reads it. A picture: \"thumb <id> <w> <h>\", \"pal\" and its colours (RRGGBB), then h rows of w characters,",
             "# \".\" clear, else the colour's place in `pal` (" + CHARS[:10] + "...)."]
        for n in sorted(pics):
            p = pics[n]
            pal = []
            for r in p:
                for c in r:
                    if c is not None and c not in pal:
                        pal.append(c)
            if len(pal) > len(CHARS):
                sys.exit("%s: too many colours (%d)" % (n, len(pal)))
            L.append("thumb %s %d %d" % (n, len(p[0]), len(p)))
            L.append("pal " + " ".join("%02X%02X%02X" % c for c in pal))
            for r in p:
                L.append("".join("." if c is None else CHARS[pal.index(c)] for c in r))
        with open(a.out, "w") as f:
            f.write("\n".join(L) + "\n")
    grown = sum(1 for n in sizes.values() if n > a.size)
    print("%d pictures (%d drawn on a bigger canvas to fill the square)%s" % (len(pics), grown, "" if a.no_out else " -> " + a.out))


if __name__ == "__main__":
    main()
