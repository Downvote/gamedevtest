#!/usr/bin/env python3
"""Polishes the loading card's picture and packs it into src/first/LoadingArt.luau (ARCHITECTURE 8.0).

Usage: gen_loading_art.py <lart_big.png> <lart_small.png> [<out.luau>] [--sheet <png>]

The PNGs are the preview scenario "ploadingart"'s (tools/preview/loading_art.luau): the island drawn by the game's own
picture path at the screen's size, K screen px to an art px, on a flat key colour (255, 0, 255). The request of
2026-11-20: "make the island loading screen like this view, but render it as a still image, then polish it like a pixel
art illustration". Each picture is read back to its art px, the key taken out, and then polished:

  1. only the island: the biggest piece of it and the pieces within 2 px of it (a bird or a mote in the sky goes);
  2. near-twin colours merged (the toon bands' and the dither's near steps, so the picture keeps a clean palette of a
     few dozen colours), then at most MAX_COLOURS, the two closest merged at a time, the rarer into the commoner;
  3. specks cleaned: a pixel all of whose four neighbours are one colour close to its own takes that colour (noise
     left by the dither), and a lone outline pixel inside a colour (one of its darker steps, ringed by that colour on
     all eight sides) too;
  4. the silhouette cleaned: a single pixel poking out of it (three clear neighbours) goes, a single pixel notch in it
     (three filled neighbours) is filled;
  5. a 1 px outline all round, never flat ink: every edge pixel that is not already a darker step of the pixel inside
     it takes one (0.45 of that colour plus 0.3 of the ink 0x2B1E2E, the rule of 2026-11-20);
  6. a rim of light along the edges facing the light (the top and the left: the game's sun is up on the left): the
     pixel inside the outline there a step lighter, toward a warm white;
  7. depth: below the grass the underside sinks into the night, each row mixed a little more toward the sky's deep
     blue down to DEPTH_K at its tip (the illustration's depth; the top keeps its daylight colours);
  8. the outline's stair steps anti-aliased against the sky: where a step of two or more pixels turns, the clear
     corner pixel takes the outline's colour at half opacity (the card lays the picture over its painted sky, so that
     pixel comes out halfway between the outline and the sky behind it).

Then each picture is written as a palette (0xRRGGBB, most used first), the alpha of each entry (255, or 128 for the
anti-aliasing) and one line of run-length codes: the alphabet is the 91 printable characters from '#' to '~' without
the backslash; with NS = 1 + #palette, a code below NS is a symbol (0 clear, 1 + i the palette's colour i + 1) and the
codes from NS up are the digits of its run's length (bijective base 91 - NS, least significant first: no digit is a run
of 1). Rows run left to right, top to bottom.

--sheet writes the raw and the polished pictures side by side at 3x on the card's night sky, to look at.
"""
import sys
from collections import Counter, deque

from PIL import Image

ALPHABET = "".join(chr(c) for c in range(35, 127) if c != 92)
assert len(ALPHABET) == 91
KEY = (255, 0, 255)
INK = (0x2B, 0x1E, 0x2E)
LIGHT = (0xFF, 0xF4, 0xDC)
MAX_COLOURS = 86
DEEP = (0x1A, 0x1C, 0x3C)  # the night's deep blue the underside sinks into
DEPTH_K = 0.42
SKY = (0x1E, 0x23, 0x48)  # the contact sheet's backdrop (the card's night sky round the island)


def ink_of(c):
    return tuple(int(round(c[i] * 0.45 + INK[i] * 0.3)) for i in range(3))


def lum(c):
    return 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]


def dist2(a, b):
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2


def mix(a, b, k):
    return tuple(int(round(a[i] + (b[i] - a[i]) * k)) for i in range(3))


def read_art(path):
    """The PNG back to art px: the K (2..4) and the offset that make the most K x K blocks one colour."""
    im = Image.open(path).convert("RGB")
    W, H = im.size
    px = im.load()
    # (a block of a smaller K inside a bigger one is one colour too: the biggest K whose blocks are nearly all one
    # colour at its best offset; only blocks with something drawn in them count)
    best = None
    for K in (4, 3, 2):
        top = None
        for oy in range(K):
            for ox in range(K):
                same = tried = 0
                for y in range(oy, H - K, K * 3):
                    for x in range(ox, W - K, K * 3):
                        c = px[x, y]
                        cells = [px[x + i, y + j] for i in range(K) for j in range(K)]
                        if all(q == KEY for q in cells):
                            continue
                        tried += 1
                        if all(q == c for q in cells):
                            same += 1
                share = same / max(1, tried)
                if top is None or share > top[0]:
                    top = (share, ox, oy)
        if top[0] > 0.97:
            best = (K, top[1], top[2])
            break
    if best is None:
        raise SystemExit("%s: no pixel size fits" % path)
    K, ox, oy = best
    w, h = (W - ox) // K, (H - oy) // K
    art = [[None] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            c = px[ox + x * K + K // 2, oy + y * K + K // 2]
            art[y][x] = None if c == KEY else c
    return art, w, h, K


def keep_island(art, w, h):
    seen = [[False] * w for _ in range(h)]
    comps = []
    for y in range(h):
        for x in range(w):
            if art[y][x] is not None and not seen[y][x]:
                q = deque([(x, y)])
                seen[y][x] = True
                pts = []
                while q:
                    cx, cy = q.popleft()
                    pts.append((cx, cy))
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            nx, ny = cx + dx, cy + dy
                            if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] and art[ny][nx] is not None:
                                seen[ny][nx] = True
                                q.append((nx, ny))
                comps.append(pts)
    comps.sort(key=len, reverse=True)
    main = comps[0]
    x0, x1 = min(p[0] for p in main), max(p[0] for p in main)
    y0, y1 = min(p[1] for p in main), max(p[1] for p in main)
    # (a piece apart from it stays only when it is within 2 px of it: a bit of the island the outline split off;
    # a bird or a mote in the sky goes)
    near = set()
    for (mx, my) in main:
        for dx in range(-2, 3):
            for dy in range(-2, 3):
                near.add((mx + dx, my + dy))
    dropped = 0
    for c in comps[1:]:
        if not any(p in near for p in c):
            dropped += len(c)
            for p in c:
                art[p[1]][p[0]] = None
    # crop with a margin of 2 (the outline's anti-aliasing may reach one past it)
    m = 2
    out = [[None] * (x1 - x0 + 1 + 2 * m) for _ in range(y1 - y0 + 1 + 2 * m)]
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            out[y - y0 + m][x - x0 + m] = art[y][x]
    return out, x1 - x0 + 1 + 2 * m, y1 - y0 + 1 + 2 * m, dropped


def merge_colours(art, w, h, near, cap):
    counts = Counter(c for row in art for c in row if c is not None)
    remap = {c: c for c in counts}
    cols = sorted(counts, key=lambda c: -counts[c])
    # near twins into the commoner
    kept = []
    for c in cols:
        for k in kept:
            if dist2(c, k) <= near * near:
                remap[c] = k
                counts[k] += counts[c]
                break
        else:
            kept.append(c)
    while len(kept) > cap:
        best = None
        for i in range(len(kept)):
            for j in range(i + 1, len(kept)):
                d = dist2(kept[i], kept[j])
                if best is None or d < best[0]:
                    best = (d, i, j)
        _, i, j = best
        a, b = kept[i], kept[j]
        keep, drop = (a, b) if counts[a] >= counts[b] else (b, a)
        counts[keep] += counts[drop]
        kept.remove(drop)
        for c, to in remap.items():
            if to == drop:
                remap[c] = keep
    for y in range(h):
        for x in range(w):
            c = art[y][x]
            if c is not None:
                art[y][x] = remap[c]
    return len(counts), len(kept)


def n4(art, w, h, x, y):
    out = []
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nx, ny = x + dx, y + dy
        out.append(art[ny][nx] if 0 <= nx < w and 0 <= ny < h else None)
    return out


def n8(art, w, h, x, y):
    out = []
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dx or dy:
                nx, ny = x + dx, y + dy
                out.append(art[ny][nx] if 0 <= nx < w and 0 <= ny < h else None)
    return out


def despeckle(art, w, h):
    fixed = 0
    src = [row[:] for row in art]
    for y in range(h):
        for x in range(w):
            c = src[y][x]
            if c is None:
                continue
            ns = n4(src, w, h, x, y)
            if ns[0] is not None and all(n == ns[0] for n in ns) and ns[0] != c:
                o = ns[0]
                if dist2(c, o) <= 38 * 38:
                    art[y][x] = o
                    fixed += 1
                    continue
                # a lone outline pixel ringed by the colour it is a darker step of
                if all(n == o for n in n8(src, w, h, x, y)) and dist2(c, ink_of(o)) <= 10 * 10:
                    art[y][x] = o
                    fixed += 1
    return fixed


def silhouette(art, w, h):
    nubs = notches = 0
    src = [row[:] for row in art]
    for y in range(h):
        for x in range(w):
            ns = n4(src, w, h, x, y)
            filled = [n for n in ns if n is not None]
            if src[y][x] is not None and len(filled) <= 1:
                art[y][x] = None
                nubs += 1
            elif src[y][x] is None and len(filled) >= 3:
                art[y][x] = Counter(filled).most_common(1)[0][0]
                notches += 1
    return nubs, notches


def inner_of(art, w, h, x, y):
    """The colour inside an edge pixel: the commonest of its filled neighbours that is lighter than it, else its own."""
    c = art[y][x]
    cand = [n for n in n8(art, w, h, x, y) if n is not None and lum(n) > lum(c) + 4]
    if cand:
        return Counter(cand).most_common(1)[0][0]
    return c


def is_edge(art, w, h, x, y):
    return art[y][x] is not None and any(n is None for n in n4(art, w, h, x, y))


def outline(art, w, h):
    inked = 0
    src = [row[:] for row in art]
    for y in range(h):
        for x in range(w):
            if not is_edge(src, w, h, x, y):
                continue
            c = src[y][x]
            inside = inner_of(src, w, h, x, y)
            if inside == c:
                # not darker than what is inside it: an edge pixel of a fill, ink it
                art[y][x] = ink_of(c)
                inked += 1
            elif lum(c) > lum(ink_of(inside)) + 12:
                art[y][x] = ink_of(inside)
                inked += 1
    return inked


def rim_light(art, w, h, edge):
    lit = 0
    src = [row[:] for row in art]
    for y in range(h):
        for x in range(w):
            if not edge[y][x]:
                continue
            for dx, dy in ((0, 1), (1, 0)):
                # the clear side is up (dx, dy = 0, 1: the inner pixel is below) or left (1, 0: the inner pixel is right)
                ox, oy = x - dx, y - dy
                if 0 <= ox < w and 0 <= oy < h and src[oy][ox] is not None:
                    continue
                ix, iy = x + dx, y + dy
                if not (0 <= ix < w and 0 <= iy < h):
                    continue
                c = src[iy][ix]
                if c is None or edge[iy][ix]:
                    continue
                if lum(c) < 70:
                    continue  # (a dark line drawn on a thing keeps its colour)
                art[iy][ix] = mix(c, LIGHT, 0.22)
                lit += 1
    return lit


def stair_aa(art, w, h, alpha):
    """Half-opaque outline at the clear corner of each stair step of two or more pixels."""
    done = 0
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if art[y][x] is not None:
                continue
            for sx, sy in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
                a = art[y][x + sx]  # beside it
                b = art[y + sy][x]  # above or below it
                if a is None or b is None:
                    continue
                if art[y][x - sx] is not None or art[y - sy][x] is not None:
                    continue
                # the step runs on along one side for two or more
                run_a = art[y + sy][x + sx] is not None and art[y - sy][x + sx] is None
                long_a = 0 <= x + 2 * sx < w and art[y][x + 2 * sx] is not None and art[y - sy][x + 2 * sx] is None
                long_b = 0 <= y + 2 * sy < h and art[y + 2 * sy][x] is not None and art[y + 2 * sy][x - sx] is None
                if not (long_a or long_b):
                    continue
                c = a if lum(a) <= lum(b) else b
                art[y][x] = c
                alpha[y][x] = 128
                done += 1
                break
    return done


def depth_shade(art, w, h):
    """The underside sinks into the night: below the grass, each row mixed a little more toward the sky's deep blue,
    down to DEPTH_K at the tip (the illustration's depth; the top keeps its daylight colours)."""
    # (the grass line: the lowest row that still has a fair share of green)
    green_rows = [y for y in range(h) if sum(1 for c in art[y] if c is not None and c[1] > c[0] + 20 and c[1] > c[2] + 20) > w * 0.08]
    y0 = max(green_rows) if green_rows else h // 2
    n = 0
    for y in range(y0 - 6, h):
        k = DEPTH_K * max(0.0, (y - (y0 - 6)) / max(1, h - (y0 - 6))) ** 1.15
        for x in range(w):
            c = art[y][x]
            if c is not None:
                art[y][x] = mix(c, DEEP, k)
                n += 1
    return y0, n


def polish(art, w, h, label):
    raw = [row[:] for row in art]
    total, kept = merge_colours(art, w, h, near=9, cap=200)
    specks = despeckle(art, w, h)
    nubs, notches = silhouette(art, w, h)
    inked = outline(art, w, h)
    edge = [[is_edge(art, w, h, x, y) for x in range(w)] for y in range(h)]
    lit = rim_light(art, w, h, edge)
    grass, shaded = depth_shade(art, w, h)
    alpha = [[255 if art[y][x] is not None else 0 for x in range(w)] for y in range(h)]
    aa = stair_aa(art, w, h, alpha)
    # (at most MAX_COLOURS entries with the anti-aliasing's half-opaque ones)
    cap = MAX_COLOURS
    while True:
        total2, kept2 = merge_colours(art, w, h, near=0, cap=cap)
        pairs = {(art[y][x], alpha[y][x]) for y in range(h) for x in range(w) if art[y][x] is not None}
        if len(pairs) <= MAX_COLOURS:
            break
        cap -= len(pairs) - MAX_COLOURS
    print("%s: %dx%d, %d colours -> %d -> %d; %d specks, %d nubs, %d notches, %d outline px, %d rim px, %d anti-aliased, "
          "%d px shaded below row %d" % (label, w, h, total, kept, kept2, specks, nubs, notches, inked, lit, aa, shaded, grass))
    return raw, art, alpha


def encode(art, alpha, w, h):
    counts = Counter((art[y][x], alpha[y][x]) for y in range(h) for x in range(w) if art[y][x] is not None)
    pal = [k for k, _ in counts.most_common()]
    index = {k: i for i, k in enumerate(pal)}
    ns = 1 + len(pal)
    assert ns <= 89, "too many colours: %d" % len(pal)
    base = 91 - ns
    syms = []
    for y in range(h):
        for x in range(w):
            c = art[y][x]
            syms.append(0 if c is None else 1 + index[(c, alpha[y][x])])
    out = []
    k = 0
    while k < len(syms):
        v = syms[k]
        run = 1
        while k + run < len(syms) and syms[k + run] == v:
            run += 1
        k += run
        out.append(ALPHABET[v])
        n = run - 1
        while n > 0:
            d = (n - 1) % base + 1
            out.append(ALPHABET[ns + d - 1])
            n = (n - d) // base
    line = "".join(out)
    # decode it back
    val = {c: i for i, c in enumerate(ALPHABET)}
    got = []
    i = 0
    while i < len(line):
        v = val[line[i]]
        i += 1
        run, mul = 1, 1
        while i < len(line) and val[line[i]] >= ns:
            run += (val[line[i]] - ns + 1) * mul
            mul *= base
            i += 1
        got.extend([v] * run)
    assert got == syms
    return pal, line


def lua_entry(name, w, h, pal, line):
    cols = ", ".join("0x%02X%02X%02X" % c for c, _ in pal)
    alphas = ", ".join(str(a) for _, a in pal)
    return "\t%s = {\n\t\tw = %d,\n\t\th = %d,\n\t\tpal = { %s },\n\t\talpha = { %s },\n\t\tpx = \"%s\",\n\t},\n" % (
        name, w, h, cols, alphas, line)


def sheet(path, pairs):
    S = 3
    gap = 8
    width = sum(2 * w * S + 3 * gap for _, _, _, w, h in pairs) + gap
    height = max(h for *_, h in pairs) * S + 2 * gap
    im = Image.new("RGB", (width, height), SKY)
    px = im.load()
    x0 = gap
    for raw, art, alpha, w, h in pairs:
        for k, (src, al) in enumerate(((raw, None), (art, alpha))):
            for y in range(h):
                for x in range(w):
                    c = src[y][x]
                    if c is None:
                        continue
                    if al is not None and al[y][x] < 255:
                        c = mix(SKY, c, al[y][x] / 255)
                    for i in range(S):
                        for j in range(S):
                            px[x0 + x * S + i, gap + y * S + j] = c
            x0 += w * S + gap
        x0 += gap
    im.save(path)


def main():
    args = sys.argv[1:]
    sheet_path = None
    if "--sheet" in args:
        k = args.index("--sheet")
        sheet_path = args[k + 1]
        del args[k:k + 2]
    if len(args) < 2:
        raise SystemExit(__doc__)
    out = args[2] if len(args) > 2 else None
    entries = []
    pairs = []
    for name, path in (("big", args[0]), ("small", args[1])):
        art, w, h, K = read_art(path)
        art, w, h, dropped = keep_island(art, w, h)
        raw, art, alpha = polish(art, w, h, "%s (K %d, %d px dropped)" % (name, K, dropped))
        pal, line = encode(art, alpha, w, h)
        entries.append(lua_entry(name, w, h, pal, line))
        pairs.append((raw, art, alpha, w, h))
        print("%s: %d colours, %d characters" % (name, len(pal), len(line)))
    if sheet_path:
        sheet(sheet_path, pairs)
    if out:
        with open(out, "w", encoding="utf-8") as f:
            f.write("--!strict\n-- GENERATED by tools/preview/gen_loading_art.py (sh tools/preview/loading_art.sh): the loading card's\n")
            f.write("-- picture, the island drawn by the game's own picture path and polished (docs/ARCHITECTURE.md 8.0). Do not edit.\n")
            f.write("-- Each picture: w x h art px; pal (0xRRGGBB) and alpha (255, or 128: anti-aliased against the sky) per colour; px\n")
            f.write("-- one line of run-length codes (see gen_loading_art.py).\n")
            f.write("return {\n")
            for e in entries:
                f.write(e)
            f.write("}\n")


if __name__ == "__main__":
    main()
