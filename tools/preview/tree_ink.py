#!/usr/bin/env python3
"""The Tree of Life's edges pixel by pixel, from a treeink preview log (TREEBOX, TREEPX, TREENAMES lines).

Usage: python3 tree_ink.py <log> <outdir> [label]

Writes <outdir>/<label>_colour.png (the picture round the tree, 8x) and <label>_parts.png (each pixel of the tree
coloured by its part's name, the rest grey), and prints what the request of 2026-11-20 is about ("the tree has alot
of jaggied outlines, and stray pixels around the outline, especially near the fruits"):

  specks    pixels of the tree that differ from all eight neighbours and sit on its silhouette or next to an ink edge
            (a lone pixel of another colour stuck on the outline)
  breaks    silhouette pixels of the tree (a 4-neighbour is not the tree and lies well behind it) that are not ink
  corners   ink pixels with an ink pixel to one side and one above or below whose diagonal is ink too (a doubled
            pixel at a turn: an L where a clean line steps once)
  floaters  bits of the tree standing apart from the rest of it (a mote, a blossom off the crown's edge)
  edges     pixels of a glowing mark (a rune, a glyph) or a mote within 2 px of an outline (another part's ink, or a
            pixel well behind them)
  slivers   a small part (a blossom, a flower, a fruit, a mark) of which one to three pixels show
and the same counted by part name, so a cause shows by name.
"""
import sys
from PIL import Image

INK = (0x2B, 0x1E, 0x2E)


def load(path):
    box = None
    rows = {}
    names = []
    for line in open(path, errors="replace"):
        if line.startswith("TREEBOX "):
            box = [int(v) for v in line.split()[1:5]]
        elif line.startswith("TREEPX "):
            _, y, data = line.rstrip("\n").split(" ", 2)
            px = []
            for i in range(0, len(data), 17):
                cell = data[i:i + 17]
                px.append((int(cell[0:6], 16), int(cell[6:8], 16), int(cell[8:12], 16) / 8.0, int(cell[12:16], 16), cell[16] == "1"))
            rows[int(y)] = px
        elif line.startswith("TREENAMES "):
            names = line.rstrip("\n").split(" ", 1)[1].split(",") if " " in line.strip() else []
    return box, rows, names


def rgb(c):
    return ((c >> 0) & 255, (c >> 8) & 255, (c >> 16) & 255)


def is_ink(c, colours):
    """An outline pixel: 0.45 of a neighbour's colour plus 0.3 of the ink (Shading.inkOf), or the flat ink."""
    r, g, b = rgb(c)
    if (r, g, b) == INK:
        return True
    for o in colours:
        orr, og, ob = rgb(o)
        q = (int(orr * 0.45 + INK[0] * 0.3 + 0.5), int(og * 0.45 + INK[1] * 0.3 + 0.5), int(ob * 0.45 + INK[2] * 0.3 + 0.5))
        if q == (r, g, b):
            return True
    return False


def main():
    log, out = sys.argv[1], sys.argv[2]
    label = sys.argv[3] if len(sys.argv) > 3 else "tree"
    box, rows, names = load(log)
    if box is None:
        print("no TREEBOX in", log)
        sys.exit(1)
    x0, y0, x1, y1 = box
    W, H = x1 - x0 + 1, y1 - y0 + 1
    grid = [rows[y0 + j] for j in range(H)]
    colour = lambda x, y: grid[y][x][0]
    name = lambda x, y: grid[y][x][1]
    depth = lambda x, y: grid[y][x][2]
    pid = lambda x, y: grid[y][x][3]
    # every colour in the box (an ink pixel is a darker step of one of them)
    allc = set(colour(x, y) for y in range(H) for x in range(W))
    inkc = {}
    for c in allc:
        inkc[c] = None

    # which colours are ink: an ink colour is inkOf(some colour in the picture) or flat ink
    base = list(allc)
    pack = {}
    for c in base:
        r, g, b = rgb(c)
        q = (int(r * 0.45 + INK[0] * 0.3 + 0.5), int(g * 0.45 + INK[1] * 0.3 + 0.5), int(b * 0.45 + INK[2] * 0.3 + 0.5))
        pack[q[0] + q[1] * 256 + q[2] * 65536] = True
    pack[INK[0] + INK[1] * 256 + INK[2] * 65536] = True
    ink = lambda x, y: grid[y][x][4]

    def tree(x, y):
        return 0 <= x < W and 0 <= y < H and name(x, y) > 0

    def nb4(x, y):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if 0 <= x + dx < W and 0 <= y + dy < H:
                yield x + dx, y + dy

    def nb8(x, y):
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if (dx or dy) and 0 <= x + dx < W and 0 <= y + dy < H:
                    yield x + dx, y + dy

    by = {}

    def count(kind, x, y):
        nm = names[name(x, y) - 1] if name(x, y) > 0 else "-"
        by.setdefault(kind, {})
        by[kind][nm] = by[kind].get(nm, 0) + 1

    specks = breaks = corners = 0
    marks = []
    for y in range(H):
        for x in range(W):
            if not tree(x, y):
                continue
            c = colour(x, y)
            silhouette = any(not tree(a, b) and depth(a, b) > depth(x, y) + 0.75 for a, b in nb4(x, y))
            nearInk = any(ink(a, b) for a, b in nb4(x, y))
            if all(colour(a, b) != c for a, b in nb8(x, y)) and (silhouette or nearInk) and not ink(x, y):
                specks += 1
                count("specks", x, y)
                marks.append((x, y, (255, 0, 255)))
            if silhouette and not ink(x, y):
                breaks += 1
                count("breaks", x, y)
                marks.append((x, y, (0, 255, 255)))
            if ink(x, y):
                h = (x + 1 < W and ink(x + 1, y)) or (x > 0 and ink(x - 1, y))
                v = (y + 1 < H and ink(x, y + 1)) or (y > 0 and ink(x, y - 1))
                if h and v:
                    # an L: one ink beside it and one above or below; the corner doubles the step when the two arms'
                    # ends touch diagonally and nothing else hangs on it
                    arms = [(a, b) for a, b in nb4(x, y) if ink(a, b)]
                    if len(arms) == 2:
                        (ax, ay), (bx, by_) = arms
                        if ax != bx and ay != by_:
                            corners += 1
                            count("corners", x, y)
    # floaters: bits of the tree standing apart from the rest of it in the picture (8-connected groups of its pixels
    # smaller than FLOAT_MAX): a mote, a blossom off the crown's edge
    FLOAT_MAX = 40
    seen = [[False] * W for _ in range(H)]
    floaters = 0
    for y in range(H):
        for x in range(W):
            if seen[y][x] or not tree(x, y):
                continue
            stack, comp = [(x, y)], []
            seen[y][x] = True
            while stack:
                a, b = stack.pop()
                comp.append((a, b))
                for c, d in nb8(a, b):
                    if not seen[d][c] and tree(c, d):
                        seen[d][c] = True
                        stack.append((c, d))
            if len(comp) < FLOAT_MAX:
                floaters += 1
                a, b = comp[0]
                count("floaters", a, b)
                for a, b in comp:
                    marks.append((a, b, (255, 255, 0)))
    # marks at the edge: pixels of the glowing marks (runes on the bark, glyphs on the stones) or of a mote within 2 px
    # of an outline (another part's ink, or a pixel well behind them): a mark on or at the edge of what it is on
    edges = 0
    for y in range(H):
        for x in range(W):
            nm = names[name(x, y) - 1] if name(x, y) > 0 else "-"
            if nm in ("Rune", "Glyph", "Mote") and any(
                depth(a, b) > depth(x, y) + 0.75 or (ink(a, b) and name(a, b) != name(x, y))
                for b in range(max(0, y - 2), min(H, y + 3))
                for a in range(max(0, x - 2), min(W, x + 3))
            ):
                edges += 1
                count("edges", x, y)
                marks.append((x, y, (255, 128, 0)))
    # slivers: a small part (a blossom, a flower, a fruit, a mark) showing only one to three pixels round whatever
    # hides the rest of it: a speck of colour with no shape
    SMALL = ("Blossom", "VineFlower", "VineTip", "Fruit", "Sparkle", "Rune", "Glyph", "Mote", "Lichen", "Flower", "Fallen")
    slivers = 0
    seen2 = [[False] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            if seen2[y][x] or pid(x, y) == 0:
                continue
            nm = names[name(x, y) - 1] if name(x, y) > 0 else "-"
            if nm not in SMALL:
                continue
            want = pid(x, y)
            stack, comp = [(x, y)], []
            seen2[y][x] = True
            while stack:
                a, b = stack.pop()
                comp.append((a, b))
                for c, d in nb8(a, b):
                    if not seen2[d][c] and pid(c, d) == want:
                        seen2[d][c] = True
                        stack.append((c, d))
            if len(comp) < 4:
                slivers += 1
                count("slivers", x, y)
                for a, b in comp:
                    marks.append((a, b, (0, 128, 255)))
    print("TREEINK %s: box %dx%d, specks %d, breaks %d, corners %d, floaters %d, edges %d, slivers %d" % (label, W, H, specks, breaks, corners, floaters, edges, slivers))
    for kind in ("specks", "breaks", "corners", "floaters", "edges", "slivers"):
        top = sorted(by.get(kind, {}).items(), key=lambda kv: -kv[1])[:12]
        print("  %s by part: %s" % (kind, ", ".join("%s %d" % kv for kv in top)))

    S = 8
    im = Image.new("RGB", (W * S, H * S))
    pim = Image.new("RGB", (W * S, H * S))
    import colorsys
    pal = {}
    for i, nm in enumerate(names):
        h = (i * 0.618) % 1.0
        r, g, b = colorsys.hsv_to_rgb(h, 0.65, 0.95)
        pal[i + 1] = (int(r * 255), int(g * 255), int(b * 255))
    for y in range(H):
        for x in range(W):
            c = rgb(colour(x, y))
            for j in range(S):
                for i in range(S):
                    im.putpixel((x * S + i, y * S + j), c)
            pc = pal.get(name(x, y), (90, 90, 90))
            if ink(x, y):
                pc = tuple(v // 3 for v in pc)
            for j in range(S):
                for i in range(S):
                    pim.putpixel((x * S + i, y * S + j), pc)
    im.save("%s/%s_colour.png" % (out, label))
    mk = im.copy()
    for x, y, col in marks:
        for i in range(S):
            mk.putpixel((x * S + i, y * S), col)
            mk.putpixel((x * S + i, y * S + S - 1), col)
            mk.putpixel((x * S, y * S + i), col)
            mk.putpixel((x * S + S - 1, y * S + i), col)
    mk.save("%s/%s_marks.png" % (out, label))
    pim.save("%s/%s_parts.png" % (out, label))
    legend = ", ".join("%d %s" % (i + 1, nm) for i, nm in enumerate(names))
    print("  parts: " + legend)


if __name__ == "__main__":
    main()
