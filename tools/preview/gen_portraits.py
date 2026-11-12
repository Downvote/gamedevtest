#!/usr/bin/env python3
# tools/preview/gen_portraits.py: the driftlings' portraits from the preview scenario "pportraits" (tools/preview/
# portraits.luau: each model drawn by Pixel/Snapshot at a three-quarter angle), tidied to the pixel art rules
# (GAME_DESIGN 2: "for pixel art, always dont use mixels. use pixel art techniques such as anti-aliasing, avoiding
# jaggies, and avoiding mixels, and use a 1 pixel outline. respect the pixel art grid"), written to
# scripts/portraits.txt for scripts/gen_art.py (the "icon_<species>" sprites).
#
#   python3 tools/preview/gen_portraits.py <scenario log> [--out scripts/portraits.txt] [--sheet sheet.png] [--raw]
#
# What the tidying does to a picture (one picture pixel = one art pixel already: nothing is scaled, so no mixels):
#   * every pixel fully there or not at all (the outline and the model's edge never half see-through);
#   * the outline made again, 1 px of ink round the silhouette on its 4 sides only, so a convex corner comes out cut
#     and a turn never has a doubled pixel (the picture's own outline is taken off first);
#   * jaggies: a lone pixel sticking out of the silhouette (one neighbour) goes, a one-pixel notch is filled;
#   * the toon bands' dither at band edges (a checkerboard of two tones) settled to the nearer tone where a pixel stands
#     alone against four neighbours of one other tone: no grain at this size (the eyes' glints and the glow stay);
#   * the creases inside (the renderer's ink where one part meets another) thinned to 1 px where they come out 2, then
#     drawn a step darker than the colour beside them instead of in ink (selective outlining: at 24 px a web of black
#     lines hides the creature); a body too dark to read against the outline lifted (the eyes stay dark); tones
#     closer than a step made one (the request: "most of those sprites look unreadable. try to tweak them so they look
#     more readable");
#   * the curves softened inside the outline: a pixel that meets the outline only at a corner goes a step toward the
#     ink (anti-aliasing on the inside, never outside the outline).
import argparse, os, sys

INK = (0x2B, 0x1E, 0x2E)  # the renderer's outline and creases, drawn flat (Data/Palette "ink")
BLACK = (0x3B, 0x34, 0x42)  # the models' eyes and mouths (Data/Palette "black"), shaded by the toon bands


def parse(path):
    out = {}
    with open(path) as f:
        for line in f:
            if not line.startswith("@@PORT "):
                continue
            _, name, w, h, hexs = line.split()[:5]
            w, h = int(w), int(h)
            px = []
            for y in range(h):
                row = []
                for x in range(w):
                    i = (y * w + x) * 8
                    v = int(hexs[i:i + 8], 16)  # little-endian ABGR as u32
                    r, g, b, a = v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255
                    row.append((r, g, b) if a >= 128 else None)
                px.append(row)
            out[name] = px
    return out


def dist(a, b):
    return sum((a[k] - b[k]) ** 2 for k in range(3))


def lum(c):
    return 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]


def is_ink(c):  # exactly the renderer's ink (an eye's darkest band is a few steps from it)
    return c is not None and dist(c, INK) < 3 * 3


def is_eye(c):  # an eye's or a mouth's dark, any of its bands (never lifted, never merged away)
    return c is not None and not is_ink(c) and lum(c) < 64 and max(c) - min(c) < 30


def shade(c, k):  # a step darker, a little cooler (the ramps' own way: GAME_DESIGN 2)
    return (int(c[0] * k), int(c[1] * k), min(255, int(c[2] * k + 8)))


def tidy(px):
    h, w = len(px), len(px[0])
    get = lambda x, y: px[y][x] if 0 <= x < w and 0 <= y < h else None
    # 1. the picture's own outline off: ink touching the outside (8 ways)
    body = [[px[y][x] for x in range(w)] for y in range(h)]
    for y in range(h):
        for x in range(w):
            c = px[y][x]
            if c is not None and is_ink(c):
                if any(get(x + dx, y + dy) is None for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy):
                    body[y][x] = None
    gb = lambda x, y: body[y][x] if 0 <= x < w and 0 <= y < h else None
    # 2. jaggies: lone spikes off, one-pixel notches filled (twice: a spike's stem can be a spike in turn)
    for _ in range(2):
        nb = [[body[y][x] for x in range(w)] for y in range(h)]
        for y in range(h):
            for x in range(w):
                n4 = [gb(x + 1, y), gb(x - 1, y), gb(x, y + 1), gb(x, y - 1)]
                full = [c for c in n4 if c is not None]
                if body[y][x] is not None and len(full) <= 1:
                    nb[y][x] = None
                elif body[y][x] is None and len(full) >= 3:
                    # (the commonest neighbour's colour)
                    nb[y][x] = max(full, key=lambda c: (sum(1 for d in full if d == c), lum(c)))
        body = nb
    # 3. the bands' dither settled: a lone pixel against four of one other tone (not ink, not a bright glint or glow)
    nb = [[body[y][x] for x in range(w)] for y in range(h)]
    for y in range(h):
        for x in range(w):
            c = body[y][x]
            if c is None or is_ink(c):
                continue
            n4 = [gb(x + 1, y), gb(x - 1, y), gb(x, y + 1), gb(x, y - 1)]
            if any(d is None for d in n4):
                continue
            if all(d == n4[0] for d in n4) and n4[0] != c and not is_ink(n4[0]) and dist(c, n4[0]) < 70 * 70 and abs(lum(c) - lum(n4[0])) < 60:
                nb[y][x] = n4[0]
    body = nb
    # 3b. the creases inside (the renderer's ink where one part meets another) 1 px wide: of a line two pixels thick
    # between two runs of colour, the second pixel takes the colour beyond it
    for _ in range(2):
        nb = [[body[y][x] for x in range(w)] for y in range(h)]
        for y in range(h):
            for x in range(w):
                c = body[y][x]
                if c is None or not is_ink(c):
                    continue
                for dx, dy in ((0, 1), (1, 0)):
                    a, b1, b2 = gb(x - dx, y - dy), gb(x + dx, y + dy), gb(x + 2 * dx, y + 2 * dy)
                    if a is not None and not is_ink(a) and b1 is not None and is_ink(b1) and nb[y + dy][x + dx] == b1 and b2 is not None and not is_ink(b2):
                        nb[y + dy][x + dx] = b2
        body = nb
    # 3c. readability at 24 px: the creases inside become a step darker than the colour beside them (selective
    # outlining: the parts stay apart without a web of black lines), a body too dark to read against the outline is
    # lifted, and tones closer than a step are one tone
    nb = [[body[y][x] for x in range(w)] for y in range(h)]
    for y in range(h):
        for x in range(w):
            c = body[y][x]
            if c is None or not is_ink(c):
                continue
            n8 = [gb(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1))]
            near = [d for d in n8 if d is not None and not is_ink(d) and not is_eye(d)]
            if near:
                base = max(near, key=lambda d: (sum(1 for e in near if e == d), -lum(d)))
                nb[y][x] = shade(base, 0.62)
    body = nb
    for y in range(h):
        for x in range(w):
            c = body[y][x]
            if c is None or is_eye(c) or is_ink(c):
                continue
            L = lum(c)
            if L < 78:
                k = min(2.2, 78 / max(1.0, L))
                body[y][x] = tuple(min(255, int(c[i] * k + 6)) for i in range(3))
    # (a little more colour: on the panels' brown plates a muted body goes grey)
    for y in range(h):
        for x in range(w):
            c = body[y][x]
            if c is None or is_eye(c) or is_ink(c):
                continue
            m = sum(c) / 3
            body[y][x] = tuple(max(0, min(255, int(m + (c[i] - m) * 1.18))) for i in range(3))
    counts = {}
    for r in body:
        for c in r:
            if c is not None:
                counts[c] = counts.get(c, 0) + 1
    order = sorted(counts, key=lambda c: -counts[c])
    keep = []
    remap = {}
    for c in order:
        to = next((k for k in keep if dist(k, c) < 14 * 14 and not is_eye(c) and not is_eye(k)), None)
        if to is None:
            keep.append(c)
            remap[c] = c
        else:
            remap[c] = to
    body = [[None if c is None else remap[c] for c in r] for r in body]
    gb = lambda x, y: body[y][x] if 0 <= x < w and 0 <= y < h else None
    # 4. the outline again: 1 px of ink on the 4 sides of the silhouette (convex corners cut)
    out = [[body[y][x] for x in range(w)] for y in range(h)]
    for y in range(h):
        for x in range(w):
            if body[y][x] is None and any(gb(x + dx, y + dy) is not None for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                out[y][x] = INK
    go = lambda x, y: out[y][x] if 0 <= x < w and 0 <= y < h else None
    # 5. softened curves inside it: a pixel that meets the outline only at a corner a step toward the ink
    final = [[out[y][x] for x in range(w)] for y in range(h)]
    for y in range(h):
        for x in range(w):
            c = body[y][x]
            if c is None or is_ink(c):
                continue
            side = any(go(x + dx, y + dy) == INK and body[y + dy][x + dx] is None for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if 0 <= x + dx < w and 0 <= y + dy < h)
            corner = sum(1 for dx, dy in ((1, 1), (1, -1), (-1, 1), (-1, -1)) if 0 <= x + dx < w and 0 <= y + dy < h and out[y + dy][x + dx] == INK and body[y + dy][x + dx] is None)
            if not side and corner >= 1:
                final[y][x] = tuple(int(c[k] * 0.78 + INK[k] * 0.22) for k in range(3))
    return final


def sheet(pics, path, zoom=8, cols=8, raw=None):
    from PIL import Image, ImageDraw
    names = list(pics)
    W = max(len(p[0]) for p in pics.values())
    H = max(len(p) for p in pics.values())
    cw = (W + 4) * zoom * (2 if raw else 1)
    ch = (H + 6) * zoom
    rows = (len(names) + cols - 1) // cols
    bg = (0x54, 0x3A, 0x2C)
    img = Image.new("RGB", (cols * cw, rows * ch), bg)
    d = ImageDraw.Draw(img)
    for i, n in enumerate(names):
        ox, oy = (i % cols) * cw, (i // cols) * ch
        for k, src in enumerate([raw[n]] if raw else []):
            for y, r in enumerate(src):
                for x, c in enumerate(r):
                    if c is not None:
                        d.rectangle([ox + x * zoom, oy + y * zoom, ox + (x + 1) * zoom - 1, oy + (y + 1) * zoom - 1], fill=c)
        bx = ox + ((W + 2) * zoom if raw else 0)
        for y, r in enumerate(pics[n]):
            for x, c in enumerate(r):
                if c is not None:
                    d.rectangle([bx + x * zoom, oy + y * zoom, bx + (x + 1) * zoom - 1, oy + (y + 1) * zoom - 1], fill=c)
        d.text((ox + 2, oy + H * zoom + 4), n[:24], fill=(230, 220, 200))
    img.save(path)


def main():
    ap = argparse.ArgumentParser()
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("log")
    ap.add_argument("--out", default=os.path.join(root, "scripts", "portraits.txt"))
    ap.add_argument("--sheet", default=None)
    ap.add_argument("--raw", action="store_true", help="the sheet shows each raw picture beside its tidied one")
    ap.add_argument("--no-out", action="store_true")
    a = ap.parse_args()
    raw = parse(a.log)
    if not raw:
        sys.exit("no @@PORT lines in " + a.log)
    pics = {n: tidy(p) for n, p in raw.items()}
    if a.sheet:
        sheet(pics, a.sheet, raw=raw if a.raw else None)
    if not a.no_out:
        L = ["# GENERATED by tools/preview/gen_portraits.py from the preview scenario \"pportraits\" (sh tools/preview/portraits.sh):",
             "# the driftlings' portraits drawn from their models, tidied to the pixel art rules. scripts/gen_art.py reads it.",
             "# A portrait: \"portrait <species> <w> <h>\", then h rows of w pixels, each \"......\" (clear) or RRGGBB."]
        for n in sorted(pics):
            p = pics[n]
            L.append("portrait %s %d %d" % (n, len(p[0]), len(p)))
            for r in p:
                L.append(" ".join("......" if c is None else "%02X%02X%02X" % c for c in r))
        with open(a.out, "w") as f:
            f.write("\n".join(L) + "\n")
    print("%d portraits%s" % (len(pics), "" if a.no_out else " -> " + a.out))


if __name__ == "__main__":
    main()
