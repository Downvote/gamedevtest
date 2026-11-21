#!/usr/bin/env python3
# The game's thumbnails and icon, part 2 (part 1: tools/preview/game_thumbs.luau draws the scenes and the driftlings;
# sh tools/preview/game_thumbs.sh runs both). The request of 2026-11-20: "could you make thumbnails that are engaging
# and show the gameplay well, along with an icon? use creature models, dont need to show the player".
#
# Every picture is pixel art on one grid, scaled up whole (nearest) to the size Roblox takes (the pixel art rule: one
# pixel size, a 1 px outline, clean steps, no mixels; every outline a darker step of the colour beside it, never
# flat ink, since the request of 2026-11-20: "For outlines everywhere, no longer use pure black, but a darker version
# of suitable neighbouring pixels instead"), drawn as a pixel illustration round the game's own pictures (frames of
# the game read back onto the art grid pixel for pixel, driftlings and eggs drawn alone through Pixel/Snapshot):
#   * the before and after (thumb_0_days, the lead; the request of 2026-11-21: "research other island building games,
#     and make a thumbnail referencing their framing as close as possible"): 960 x 540 art px, 2x (illustrate.py: the
#     islands cut from their sky-only captures and outlined, a sky painted in clean bands, the sun, far islets, small
#     floating rocks, gulls, a sea of clouds; the bar, the arrow and the words anti-aliased where their outlines step);
#   * the genre's other frames (tools/preview/genre_thumbs.py; the request of 2026-11-21: "do more thumbnail research,
#     and replicate popular game thumbnails with the same genre type"): the rarity ladder, the close-up and the egg
#     and what hatched on the 480 x 270 grid (4x: a creature close up reads as pixel art there), the field with one
#     eternal and the big number on the 960 x 540 one;
#   * the icon is 256 x 256 art px, 2x: 512 x 512 (the Tree of Life big on its island).
# The words are drawn on the grid one art pixel at a time (title: a heavy face traced at its size, never scaled up).
#
# Usage: python3 tools/preview/game_thumbs.py <scenes dir> <cast log> <out dir> --rate <coins a minute> [--sheet sheet.png]
#   scenes dir: the PNGs of the gthumbs runs (gth_<name>_desktop.png: day1, day100, icon, icontree, field, rich and
#               their _sky / _star captures)
#   cast log:   the "gthumbs=cast" run's log (its @@GTH lines)
#   --rate:     the tier 20 town's coins a minute (the "gthumbs=day100:20" run logs it)
import argparse, math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, "scripts"))
from gen_portraits import parse  # noqa: E402
from product_icons import PAL, WHITE, mix, dark, light, ink_of, lum, pick_beside, TEXT_KEEP, TEXT_ADD  # noqa: E402
import illustrate as IL  # noqa: E402

K = 4
TW, TH = 480, 270  # a thumbnail's art grid
IW = 256  # the icon's (2x: 512 x 512)


# ---------------------------------------------------------------- the canvas
class Art:
    def __init__(self, w, h, fill=None):
        self.w, self.h = w, h
        self.px = [[fill] * w for _ in range(h)]

    def put(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h and c is not None:
            self.px[y][x] = c

    def get(self, x, y):
        return self.px[y][x] if 0 <= x < self.w and 0 <= y < self.h else None

    def picture(self, pic, ox, oy):
        for y, row in enumerate(pic):
            for x, c in enumerate(row):
                if c is not None:
                    self.put(ox + x, oy + y, c)

    def shade(self, x, y, k):
        c = self.get(x, y)
        if c is not None:
            self.px[y][x] = dark(c, k)

    def band(self, y0, y1, k):
        for y in range(max(0, y0), min(self.h, y1)):
            for x in range(self.w):
                self.shade(x, y, k)

    def image(self, scale):
        from PIL import Image

        img = Image.new("RGB", (self.w, self.h))
        img.putdata([c or (0, 0, 0) for row in self.px for c in row])
        return img.resize((self.w * scale, self.h * scale), Image.NEAREST)


def load_scene(path, k=K):
    """A frame the preview drew at k screen px an art px, read back onto the art grid pixel for pixel (its phase found
    by where the k x k blocks are whole). A frame drawn at another pixel size is refused: reading it at the wrong one
    resamples it unevenly, the mixels the thumbnails had while the game drew at 3 and this read at 4."""
    from PIL import Image

    img = Image.open(path).convert("RGB")
    W, H = img.size
    data = img.load()
    best, phase, total = -1, (0, 0), 0
    for oy in range(k):
        for ox in range(k):
            good, total = 0, 0
            for by in range(40, H - k, 37):
                for bx in range(40, W - k, 53):
                    x0, y0 = bx - (bx - ox) % k, by - (by - oy) % k
                    c = data[x0, y0]
                    total += 1
                    if all(data[x0 + i, y0 + j] == c for i in range(k) for j in range(k)):
                        good += 1
            if good > best:
                best, phase = good, (ox, oy)
    if best < 0.97 * total:
        sys.exit("%s: not drawn at %d screen px an art px (%d of %d blocks whole)" % (path, k, best, total))
    ox, oy = phase
    art = Art(W // k, H // k)
    for y in range(art.h):
        for x in range(art.w):
            sx, sy = min(W - 1, ox + x * k), min(H - 1, oy + y * k)
            art.px[y][x] = data[sx, sy]
    return art


# ---------------------------------------------------------------- small things drawn here
def bottom_of(pic):
    """The picture's lowest drawn row and the middle of what is drawn in its lowest fifth (where its feet are)."""
    h = len(pic)
    rows = [y for y in range(h) if any(c is not None for c in pic[y])]
    last = rows[-1]
    xs = [x for y in range(max(0, last - h // 5), last + 1) for x, c in enumerate(pic[y]) if c is not None]
    return last, (min(xs) + max(xs)) // 2, max(xs) - min(xs)


# ---------------------------------------------------------------- the before-and-after thumbnail
# The request (2026-11-21): "research other island building games, and make a thumbnail referencing their framing as
# close as possible". The genre's most liked island builders on Roblox (Build An Island!, Skybase Tycoon) lead with
# the same frame: a slanted white bar splits it, a first island alone in open sky on the left under a smaller "DAY 1",
# the full island on the right, bigger, bleeding off the frame under a big yellow "DAY 100", and a red arrow curving
# from the one to the other. Here both halves are frames of the game (gthumbs=day1, gthumbs=day100) under the same
# sky, so it runs on across the bar.
DW, DH = 960, 540  # its art grid: twice the pixels of the others (2 screen px an art px), the islands' and the words'
DIV_X, DIV_STEP, DIV_W = 396, 8, 14  # the bar's left edge at the top, a pixel left every DIV_STEP rows, its width
TITLE_FONT = os.path.join(HERE, "fonts", "body-heavy.woff")  # Montserrat ExtraBold (fonts/LICENSE-Montserrat)
_BAYER4 = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))  # (title's dithered bands)


def div_x(y):
    return DIV_X - y // DIV_STEP


def title(cv, s, size, fill, cx=None, x0=None, top=0, depth=5, glint=True, hue=None, chars=None, dither=False, shade=None):
    """Words drawn on the art grid itself, one art pixel at a time (the request of 2026-11-21: "make the text respect
    the pixel grid instead of using mixels", then "polish and detail it as if it is a pixel art illustration"): the
    font traced at `size` art px into a clean mask (half covered or more), an anti-aliasing pixel in each inside corner
    of a stair (between the face and its outline, where the font covers it a little), the face in a ramp of four bands
    lit from the top with a lit row on every top edge and a bevel (its left edges a step lighter, its right and bottom
    edges a step darker), a glint at each letter's top left, `depth` px of depth under it a darker step, a 1 px outline
    round all of it, a darker step of the face (the game's words), and anti-aliasing outside the outline where its
    stairs step (only where the font's ideal edge cuts through the pixel). `hue(t)` (t from 0 at the words' left to 1
    at their right) gives each column its own face colour in place of `fill`; `chars` (a colour for each character of
    `s`, None for `fill`) colours each letter whole, the genre's rainbow words (the request of 2026-11-21: "make it
    such that each number is fully colored with colors of the rainbow differently to form a rainbow"). `dither`: the
    face's bands pass into each other through a 4 x 4 ordered dither a few rows deep instead of a hard step ("do
    dithering across the number gradient as well"); `shade` = (darker, lighter) replaces `dark` and `light` for every
    shade drawn (genre_thumbs' hue-shifted pair: "use hueshifting such that darker and lighter shades are hueshifted to
    be colorful"). Returns the box drawn."""
    from PIL import Image, ImageDraw, ImageFont

    ft = ImageFont.truetype(TITLE_FONT, size)
    l, t, r, b = ft.getbbox(s)
    w, h = r - l + 4, b - t + 4
    img = Image.new("L", (w, h), 0)
    ImageDraw.Draw(img).text((2 - l, 2 - t), s, font=ft, fill=255)
    cov = img.load()
    # the same words four times bigger with a stroke one art px wide: how much of each pixel the face and its outline
    # cover, for the anti-aliasing outside the outline
    S = 4
    ft4 = ImageFont.truetype(TITLE_FONT, size * S)
    l4, t4, _, _ = ft4.getbbox(s)
    big = Image.new("L", (w * S, h * S), 0)
    ImageDraw.Draw(big).text((2 * S - l4, 2 * S - t4), s, font=ft4, fill=255, stroke_width=S, stroke_fill=255)
    stroked = big.resize((w, h), Image.BOX).load()
    face = {(x, y) for y in range(h) for x in range(w) if cov[x, y] >= 128}
    aa = set()
    for y in range(h):
        for x in range(w):
            if (x, y) in face or cov[x, y] < 24:
                continue
            up, dn, lf, rt = (x, y - 1) in face, (x, y + 1) in face, (x - 1, y) in face, (x + 1, y) in face
            if (up or dn) and (lf or rt):
                aa.add((x, y))
    ys = [y for _, y in face]
    y0f, y1f = min(ys), max(ys)
    xs = [x for x, _ in face]
    bw = max(xs) - min(xs) + 1
    ox = (x0 if x0 is not None else cx - bw // 2) - min(xs)
    oy = top - y0f
    body = face | aa
    deep = set()
    for (x, y) in body:
        for d in range(1, depth + 1):
            if (x, y + d) not in body:
                deep.add((x, y + d))
    hh = y1f - y0f + 1
    xmin = min(xs)

    # (each character's columns from where the pen puts it: its left edge to the next one's)
    starts = [2 - l + ft.getlength(s[:i]) for i in range(len(s))] if chars else []

    def fill_at(x):
        if chars:
            k = 0
            for i, x0c in enumerate(starts):
                if x + 0.5 >= x0c - 0.5:
                    k = i
            return chars[k] or fill
        return fill if hue is None else hue(min(1.0, max(0.0, (x - xmin) / max(1, bw - 1))))

    dk, lt = shade or (dark, light)
    EDGES = (0.17, 0.4, 0.66)
    ZONE = 0.07  # (each band edge dithered this share of the face's height either side)

    def band_of(x, y):
        ry = (y - y0f) / hh
        k = sum(1 for e in EDGES if ry >= e)
        if dither:
            for i, e in enumerate(EDGES):
                if abs(ry - e) < ZONE:
                    f = (ry - e + ZONE) / (2 * ZONE)
                    k = i + (1 if f > (_BAYER4[y % 4][x % 4] + 0.5) / 16 else 0)
        return k

    def face_c(x, y):
        f = fill_at(x)
        bands = (lt(f, 0.6), lt(f, 0.3), f, dk(f, 0.84))
        c = bands[band_of(x, y)]
        if (x, y - 1) not in face:
            return lt(f, 0.8)
        if (x - 1, y) not in face:
            return lt(c, 0.3)
        if (x + 1, y) not in face or (x, y + 1) not in face:
            return dk(c, 0.88)
        return c

    L = IL.Layer()
    for (x, y) in deep:
        L.put(x + ox, y + oy, dk(fill_at(x), 0.62))
    for (x, y) in face:
        L.put(x + ox, y + oy, face_c(x, y))
    # (the inside corners' pixels sit between the face and its outline, so they go in before the outline rings it)
    for (x, y) in aa:
        near = [face_c(qx, qy) for (qx, qy) in ((x, y - 1), (x, y + 1), (x - 1, y), (x + 1, y)) if (qx, qy) in face]
        L.put(x + ox, y + oy, mix(near[0], ink_of(fill_at(x), TEXT_KEEP, TEXT_ADD), 0.5))
    L.outline(eight=True, keep=TEXT_KEEP, add=TEXT_ADD)
    # a glint at each letter's top left: a short diagonal of white with a lit pixel either side, inside the face
    if glint:
        seen = set()
        for p0 in sorted(face, key=lambda q: (q[0] + q[1], q[1])):
            if p0 in seen:
                continue
            part, stack = [], [p0]
            seen.add(p0)
            while stack:
                q = stack.pop()
                part.append(q)
                for dx, dy in IL.N4:
                    n = (q[0] + dx, q[1] + dy)
                    if n in face and n not in seen:
                        seen.add(n)
                        stack.append(n)
            if len(part) < 40:
                continue
            gx, gy = min(part, key=lambda q: (q[0] + q[1], q[1]))
            arm = max(2, size // 28)
            for k in range(arm + 1):
                for (dx, dy, c) in ((0, 0, WHITE), (1, 0, lt(fill_at(gx), 0.85)), (0, 1, lt(fill_at(gx), 0.85))):
                    q = (gx + 3 + k + dx, gy + 3 + k + dy)
                    if q in face and (q[0], q[1] - 1) in face and (q[0] - 1, q[1]) in face:
                        L.put(q[0] + ox, q[1] + oy, c)

    def cover(x, y):
        best = 0
        for d in range(0, depth + 1):
            mx, my = x - ox, y - oy - d
            if 0 <= mx < w and 0 <= my < h:
                best = max(best, stroked[mx, my])
        return best / 255

    L.stamp(cv, cover=cover)
    return (min(xs) + ox - 1, oy - 1, max(xs) + ox + 1, y1f + oy + depth + 1)


def sparkle_big(cv, x, y, arm, c):
    """A four-pointed twinkle `arm` px long each way, its arms tapering in two widths, a 1 px outline a darker step of
    its colour."""
    pts = {(x, y)}
    for d in range(1, arm + 1):
        pts |= {(x + d, y), (x - d, y), (x, y + d), (x, y - d)}
    for d in range(1, max(1, arm // 3) + 1):
        pts |= {(x + d, y + 1), (x + d, y - 1), (x - d, y + 1), (x - d, y - 1), (x + 1, y + d), (x - 1, y + d), (x + 1, y - d), (x - 1, y - d)}
    for px, py in pts:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if (px + dx, py + dy) not in pts:
                cv.put(px + dx, py + dy, ink_of(c))
    for px, py in pts:
        cv.put(px, py, c)
    cv.put(x, y, WHITE)


def arrow(cv, pts, color, r=6.6, head=34, half=15):
    """A thick curved arrow through the quadratic curve `pts` (three points), its head at the end: the colour in a
    ramp (the upper side lit, the lower in the shade, a lit row along its top), a 1 px outline a darker step of it,
    anti-aliased where the outline's stairs step (illustrate.Layer: a pixel between the outline and the sky behind,
    only where the ideal edge cuts through it), and a shadow a step darker than what lies under it."""
    (x0, y0), (x1, y1), (x2, y2) = pts
    line = []
    for i in range(241):
        t = i / 240
        a, b, c = (1 - t) ** 2, 2 * t * (1 - t), t * t
        line.append((a * x0 + b * x1 + c * x2, a * y0 + b * y1 + c * y2))
    tx, ty = x2 - x1, y2 - y1
    n = math.hypot(tx, ty)
    tx, ty = tx / n, ty / n
    nx, ny = -ty, tx
    tip = (x2 + tx * head, y2 + ty * head)
    c1 = (x2 + nx * half, y2 + ny * half)
    c2 = (x2 - nx * half, y2 - ny * half)
    body = line[:-8]

    def tri_dist(px, py):
        """0 inside the head, else the distance to its nearest side."""
        def side(ax, ay, bx, by):
            return (bx - ax) * (py - ay) - (by - ay) * (px - ax)

        d1, d2, d3 = side(*tip, *c1), side(*c1, *c2), side(*c2, *tip)
        if not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0)):
            return 0.0
        best = 1e9
        for (a, b) in ((tip, c1), (c1, c2), (c2, tip)):
            ex, ey = b[0] - a[0], b[1] - a[1]
            t = max(0.0, min(1.0, ((px - a[0]) * ex + (py - a[1]) * ey) / (ex * ex + ey * ey)))
            best = min(best, math.hypot(px - a[0] - ex * t, py - a[1] - ey * t))
        return best

    def near_line(px, py):
        best, off = 1e9, 0.0
        for (lx, ly) in body:
            d = (px - lx) ** 2 + (py - ly) ** 2
            if d < best:
                best, off = d, py - ly
        return math.sqrt(best), off

    xs = [p[0] for p in line] + [tip[0], c1[0], c2[0]]
    ys = [p[1] for p in line] + [tip[1], c1[1], c2[1]]
    X0, X1, Y0, Y1 = int(min(xs)) - 8, int(max(xs)) + 9, int(min(ys)) - 8, int(max(ys)) + 9
    shape = {}
    for y in range(Y0, Y1):
        for x in range(X0, X1):
            d, off = near_line(x + 0.5, y + 0.5)
            if d <= r:
                shape[(x, y)] = off
            elif tri_dist(x + 0.5, y + 0.5) == 0.0:
                shape[(x, y)] = (y + 0.5 - (y2 + ty * head * 0.3)) * 0.5

    def cover(x, y):
        """How much of the pixel the ideal arrow with its outline covers (4 x 4 samples)."""
        hit = 0
        for j in range(4):
            for i in range(4):
                px, py = x + (i + 0.5) / 4, y + (j + 0.5) / 4
                if near_line(px, py)[0] <= r + 1 or tri_dist(px, py) <= 1:
                    hit += 1
        return hit / 16

    hi, lo = light(color, 0.38), dark(color, 0.74)
    L = IL.Layer()
    for (x, y), off in shape.items():
        c = hi if off < -2.4 else (lo if off > 2.4 else color)
        if (x, y - 1) not in shape:
            c = light(color, 0.6)
        L.put(x, y, c)
    L.outline(eight=True)
    # the shadow: the whole arrow 3 px down, a step darker than what is under it
    for (x, y) in list(L.px):
        q = (x, y + 3)
        if q not in L.px:
            under = cv.get(*q)
            if under is not None:
                cv.put(q[0], q[1], dark(under, 0.86))
    L.stamp(cv, cover=cover)


def find_sun(ref, default=(296, 168, 15)):
    """Where the game's sky put the sun (its disc: the brightest pixels above the clouds) and how big it is."""
    pts = [(x, y) for y in range(int(ref.h * 0.6)) for x in range(ref.w) if ref.px[y][x] is not None and lum(ref.px[y][x]) > 245]
    if len(pts) < 20:
        return default
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    return int(round(cx)), int(round(cy)), max(6, int(round(math.sqrt(len(pts) / math.pi))))


class Busy:
    """The places already taken (islands, words, the bar, the arrow), for putting small things in the sky clear of them."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.cells = [[False] * w for _ in range(h)]

    def mark_mask(self, m, clip=None):
        for y, row in enumerate(m):
            for x, on in enumerate(row):
                if on and (clip is None or clip(x, y)):
                    self.cells[y][x] = True

    def mark_box(self, x0, y0, x1, y1):
        for y in range(max(0, y0), min(self.h, y1)):
            for x in range(max(0, x0), min(self.w, x1)):
                self.cells[y][x] = True

    def free(self, x0, y0, x1, y1, pad=6):
        if x0 - pad < 0 or y0 - pad < 0 or x1 + pad > self.w or y1 + pad > self.h:
            return False
        return not any(self.cells[y][x] for y in range(y0 - pad, y1 + pad) for x in range(x0 - pad, x1 + pad))


def sky_scene(cv, ref, horizon, bands, sun_at=None):
    """The painted sky for a frame of the game (illustrate.paint_sky): the game's own top and low colours, read off
    its sky-only capture, in clean bands; the sun where `sun_at` says (or where the game had it)."""
    cols = range(0, ref.w, 5)
    top = IL.row_colour(ref, 1, cols)
    low = IL.row_colour(ref, int(ref.h * 0.62), cols)
    IL.paint_sky(cv, top, low, 0, horizon, bands=bands)
    sx, sy, sr = sun_at or find_sun(ref)
    IL.sun(cv, sx, sy, sr)
    return low


def cloud_tones(low):
    return (mix(low, WHITE, 0.38), mix(low, WHITE, 0.52)), (mix(low, WHITE, 0.66), mix(low, WHITE, 0.8)), ((246, 250, 255), WHITE)


def island_tones(frame, m):
    grass = IL.common_colour(frame, m, lambda c: c[1] > c[0] + 30 and c[1] > c[2] + 30) or (120, 200, 96)
    rock = IL.common_colour(frame, m, lambda c: abs(c[0] - c[1]) < 26 and c[0] > c[2] + 4 and 110 < lum(c) < 200) or (176, 160, 146)
    return grass, rock


def thumb_days(sc):
    """The before and after (GAME_DESIGN 11.1), drawn as a pixel illustration (the request of 2026-11-21: "polish and
    detail it as if it is a pixel art illustration, with the pixel art rules i gave you"): both islands the game's own
    pictures, cut from the sky by their sky-only captures and given a whole 1 px outline; the sky painted in clean
    bands round them (no dither across it), the sun and its rings, far islets, small floating rocks near each island,
    a few gulls and a sea of clouds the first island sinks into; the bar, the arrow and the words anti-aliased where
    their outlines step."""
    small, full = sc["day1"], sc["day100"]
    ms = IL.island_mask(small, sc["day1_sky"])
    mf = IL.island_mask(full, sc["day100_sky"])
    IL.outline_edges(small, ms)
    IL.outline_edges(full, mf)
    cv = Art(DW, DH)
    low = sky_scene(cv, sc["day1_sky"], int(DH * 0.72), 10)
    left = lambda x, y: x < div_x(y)
    right = lambda x, y: x >= div_x(y) + DIV_W
    busy = Busy(DW, DH)
    busy.mark_mask(ms, left)
    busy.mark_mask(mf, right)
    for y in range(DH):
        busy.mark_box(div_x(y) - 3, y, div_x(y) + DIV_W + 3, y + 1)
    busy.mark_box(20, 16, 236, 92)  # DAY 1
    busy.mark_box(440, 10, 960, 150)  # DAY 100
    busy.mark_box(220, 456, 470, 540)  # the arrow
    sx, sy, sr = find_sun(sc["day1_sky"])
    busy.mark_box(sx - sr - 10, sy - sr - 10, sx + sr + 10, sy + sr + 10)
    # far islets: flat, a step darker than the sky behind them
    far_c = lambda x, y: mix(cv.get(x, y) or low, (88, 128, 186), 0.22)
    for (fx, fy, fw) in ((70, 132, 22), (170, 150, 14), (612, 196, 18), (904, 214, 24), (520, 178, 12)):
        if busy.free(int(fx - fw / 2), fy - 6, int(fx + fw / 2), fy + 12, pad=4):
            IL.far_islet(cv, fx, fy, fw, far_c(fx, fy))
    back, mid, front = cloud_tones(low)
    IL.cloud_sea(cv, [(int(DH * 0.78), 22, back[0], back[1]), (int(DH * 0.85), 20, mid[0], mid[1])], seed=11)
    # small floating rocks near each island, nearer ones in full colour, further ones mixed toward the sky
    grass, rock = island_tones(small, ms)
    for (cx_, ty, w, far, seed) in ((58, 404, 26, 0.0, 3), (300, 112, 16, 0.35, 5), (470, 206, 30, 0.0, 8), (560, 236, 14, 0.4, 9), (36, 196, 12, 0.45, 4)):
        if busy.free(int(cx_ - w / 2) - 1, ty - 4, int(cx_ + w / 2) + 1, ty + w + 4, pad=5):
            isl = IL.mini_islet(cx_, ty, w, grass, rock, seed=seed, far=far, sky=cv.get(int(cx_), ty) or low)
            isl.stamp(cv)
            busy.mark_box(int(cx_ - w / 2) - 2, ty - 4, int(cx_ + w / 2) + 2, ty + w + 4)
    IL.lay_island(cv, small, ms, clip=left)
    IL.lay_island(cv, full, mf, clip=right)
    # the first island's point sinks into the front clouds (on its side of the bar only)
    IL.cloud_sea(cv, [(int(DH * 0.885), 18, front[0], front[1])], seed=12, clip=left)
    # gulls, a step darker than the sky
    gull = mix(low, (60, 92, 140), 0.55)
    for (bx, by, fl) in ((246, 104, 0), (259, 111, 1), (232, 116, 1), (668, 168, 0), (683, 160, 1)):
        if busy.free(bx - 4, by - 2, bx + 4, by + 2, pad=2):
            IL.bird(cv, bx, by, gull, fl)
    # the bar, white, its edges a darker step of it, a clean stair of DIV_STEP rows; at each step two or three pixels
    # of anti-aliasing graded along the step, outside the edge, where the ideal straight edge cuts through
    edge = ink_of(WHITE)
    for y in range(DH):
        d = div_x(y)
        cv.put(d - 1, y, edge)
        for x in range(d, d + DIV_W):
            cv.put(x, y, WHITE)
        cv.put(d + DIV_W, y, edge)
    for y in range(DH):
        d, r = div_x(y), y % DIV_STEP
        tl = {DIV_STEP - 3: 0.25, DIV_STEP - 2: 0.4, DIV_STEP - 1: 0.55}.get(r)
        tr = {0: 0.55, 1: 0.4, 2: 0.25}.get(r)
        if tl and cv.get(d - 2, y) is not None:
            cv.put(d - 2, y, mix(cv.get(d - 2, y), edge, tl))
        if tr and y >= DIV_STEP and cv.get(d + DIV_W + 1, y) is not None:
            cv.put(d + DIV_W + 1, y, mix(cv.get(d + DIV_W + 1, y), edge, tr))
    # the arrow from the first island round to the full one
    arrow(cv, ((232, 476), (318, 536), (404, 516)), PAL["berry_red"])
    # the words, on this grid: DAY 1 smaller over the first island, DAY 100 big and gold over the full one
    title(cv, "DAY 1", 66, WHITE, x0=30, top=26, depth=4, glint=False)
    right_mid = (div_x(0) + DIV_W + 1 + DW) // 2
    box = title(cv, "DAY 100", 112, PAL["accent"], cx=right_mid + 4, top=22, depth=6)
    for (x, y, arm) in ((box[0] - 14, 30, 7), (box[2] + 8, 104, 4), (box[2] + 4, 18, 5)):
        if 0 < x < DW:
            sparkle_big(cv, x, y, arm, light(PAL["accent"], 0.5))
    return cv


def icon(sc):
    """The game icon (the requests of 2026-11-21, last "Crop the icon as a square such that the island cuts off
    perfectly at the border. Then, detail and polish it as pixel art illustration, with extra flair to make it more
    like an icon"): the Tree of Life and its eggs drawn big (gthumbs=icon's second capture, View notch 7) on the island
    (its first capture, 6 art px a stud, the tree left out), both from one camera point so the tree stands on its own
    spot; on a 256 x 256 grid, 2x: 512 x 512, the island's sides at the frame's borders and the bottom border across
    its rock. Drawn as a pixel illustration: each cut from its sky-only capture and given a whole 1 px outline, a rim
    of light inside the outline where the tree and the island face the sun, the big tree's shade on the lawn; the sky
    painted in clean bands with the sun at the top left, rays fanning out behind the crown, a glow round it in rings
    of flat colour, a few blossom petals on the wind, twinkles and gulls."""
    fa, sa = sc["icon"], sc["icon_sky"]
    fb, sb = sc["icontree"], sc["icontree_sky"]
    ma = IL.island_mask(fa, sa, near=24)
    mb = IL.island_mask(fb, sb, min_part=12, near=24)
    IL.outline_edges(fa, ma)
    IL.outline_edges(fb, mb)
    W, H = fa.w, fa.h
    ba, bb = IL.mask_box(ma), IL.mask_box(mb)
    S = IW
    X0 = (ba[0] + ba[2]) // 2 - S // 2  # the island's middle in the frame's: its sides at the borders
    Y0 = bb[1] - 6  # the crown 6 px under the top border

    def at(m, x, y):
        X, Y = X0 + x, Y0 + y
        return 0 <= X < W and 0 <= Y < H and m[Y][X]

    cv = Art(S, S)
    cols = range(0, sa.w, 5)
    top = IL.row_colour(sa, max(0, Y0 - 40), cols)
    bottom = IL.row_colour(sa, min(sa.h - 1, Y0 + S), cols)
    IL.paint_sky(cv, top, bottom, 0, S, bands=8)
    low = bottom
    tree_c = (bb[0] + bb[2]) // 2 - X0, bb[1] - Y0 + int((bb[3] - bb[1]) * 0.3)
    subject = lambda x, y: at(ma, x, y) or at(mb, x, y)
    sun_at = (26, 26, 12)
    sky = lambda x, y: 0 <= x < S and 0 <= y < S and not subject(x, y) and math.hypot(x + 0.5 - sun_at[0], y + 0.5 - sun_at[1]) > sun_at[2] + 10
    IL.sunburst(cv, tree_c[0], tree_c[1], sky)
    IL.sun(cv, *sun_at)
    tree_d = IL.distance_to(lambda x, y: at(mb, x, y), S, S, 12)
    IL.glow(cv, tree_d, sky)
    # small floating rocks in the sky beside the crown, clear of everything
    busy = Busy(S, S)
    for y in range(S):
        for x in range(S):
            if subject(x, y) or (tree_d[y][x] is not None and tree_d[y][x] <= 6):
                busy.cells[y][x] = True
    sx, sy, sr = sun_at
    busy.mark_box(sx - sr - 10, sy - sr - 10, sx + sr + 10, sy + sr + 10)
    busy.mark_box(200, 18, 236, 44)  # the gulls
    grass, rock = island_tones(fa, ma)
    for (cx_, ty, w, far, seed) in ((20, 112, 14, 0.25, 3), (236, 96, 14, 0.25, 8), (16, 60, 10, 0.45, 5), (240, 150, 10, 0.4, 9)):
        if busy.free(int(cx_ - w / 2) - 1, ty - 4, int(cx_ + w / 2) + 1, ty + w + 2, pad=2):
            IL.mini_islet(cx_, ty, w, grass, rock, seed=seed, far=far, sky=cv.get(int(cx_), ty) or low).stamp(cv)
            busy.mark_box(int(cx_ - w / 2) - 2, ty - 4, int(cx_ + w / 2) + 2, ty + w + 3)
    # the island, the big tree's shade on it (an oval round its foot, toward the lower right, away from the sun), the
    # tree and its eggs, then the rim of light on both
    fcx, fcy = W // 2 - X0, H // 2 - Y0
    for y in range(S):
        for x in range(S):
            if at(ma, x, y):
                c = fa.px[Y0 + y][X0 + x]
                if ((x + 0.5 - (fcx + 10)) / 62.0) ** 2 + ((y + 0.5 - (fcy + 8)) / 26.0) ** 2 <= 1:
                    c = dark(c, 0.84)
                cv.put(x, y, c)
    for y in range(S):
        for x in range(S):
            if at(mb, x, y):
                cv.put(x, y, fb.px[Y0 + y][X0 + x])
    IL.rim_light(cv, lambda x, y: at(mb, x, y), 0.24)
    IL.rim_light(cv, lambda x, y: at(ma, x, y) and not at(mb, x, y), 0.18)
    # petals on the wind round the crown, twinkles, gulls
    for (x, y, t) in ((30, 150, 0), (44, 96, 1), (226, 70, 2), (212, 132, 3), (234, 180, 1), (58, 40, 2), (198, 30, 0)):
        if 0 <= x < S - 3 and 0 <= y < S - 3 and all(sky(x + dx, y + dy) for dx in range(4) for dy in range(3)):
            IL.petal(cv, x, y, t)
    gull = mix(low, (60, 92, 140), 0.55)
    IL.bird(cv, 212, 26, gull, 0)
    IL.bird(cv, 224, 32, gull, 1)
    crown = bb[1] - Y0
    for (dx, dy, arm) in ((-74, 18, 4), (70, 8, 4), (84, 40, 2), (-60, -2, 2), (-90, 70, 3), (92, 84, 2)):
        x, y = S // 2 + dx, crown + dy
        if 0 <= x < S and 0 <= y < S and sky(x, y):
            sparkle_big(cv, x, y, arm, light(PAL["accent"], 0.5))
    return cv


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scenes")
    ap.add_argument("castlog")
    ap.add_argument("out")
    ap.add_argument("--sheet")
    ap.add_argument("--rate", type=float, default=0, help="the tier 20 town's coins a minute (gthumbs=day100:20 logs it)")
    a = ap.parse_args()
    pics = parse(a.castlog, "@@GTH ")
    if not pics:
        sys.exit("no @@GTH lines in " + a.castlog)
    if a.rate <= 0:
        sys.exit("no --rate: the big number thumbnail shows the tier 20 town's coins a minute")
    import genre_thumbs

    genre_thumbs.setup(sys.modules[__name__])

    def scene(name):
        p = os.path.join(a.scenes, "gth_%s_desktop.png" % name)
        if not os.path.exists(p):
            sys.exit("no scene " + p)
        return load_scene(p, 2 if name.split("_")[0] in ("day1", "day100", "icon", "icontree", "field", "rich", "pedestal") else K)

    sc = {n: scene(n) for n in ("day1", "day100", "day1_sky", "day100_sky", "icon", "icon_sky", "icontree", "icontree_sky", "field", "field_star", "rich", "rich_sky", "rich_tree", "pedestal")}
    os.makedirs(a.out, exist_ok=True)
    # the before and after first, then the genre's other frames (tools/preview/genre_thumbs.py)
    made = [
        ("thumb_0_days", thumb_days(sc)),
        ("thumb_1_rarity", genre_thumbs.thumb_rarity(pics, sc, genre_thumbs.parse_gbuf(a.castlog))),
        ("thumb_2_hero", genre_thumbs.thumb_hero(pics)),
        ("thumb_3_hatch", genre_thumbs.thumb_hatch(pics)),
        ("thumb_4_lucky", genre_thumbs.thumb_lucky(sc)),
        ("thumb_5_rich", genre_thumbs.thumb_rich(sc, a.rate)),
    ]
    imgs = []
    for name, cv in made:
        img = cv.image(1920 // cv.w)
        img.save(os.path.join(a.out, name + ".png"))
        imgs.append(img)
    ic = icon(sc)
    ic.image(512 // ic.w).save(os.path.join(a.out, "icon.png"))
    print("%d thumbnails (1920 x 1080) and the icon (512 x 512) -> %s" % (len(made), a.out))
    if a.sheet:
        from PIL import Image

        sw, sh = 960, 540
        sheet = Image.new("RGB", (2 * sw + 48, 4 * sh + 80), (40, 34, 48))  # six thumbnails and the icon
        for i, img in enumerate(imgs):
            sheet.paste(img.resize((sw, sh), Image.NEAREST), (16 + (i % 2) * (sw + 16), 16 + (i // 2) * (sh + 16)))
        sheet.paste(ic.image(2), (16 + (sw - 512) // 2, 16 + 3 * (sh + 16) + (sh - 512) // 2))
        sheet.save(a.sheet)
        print("sheet:", a.sheet)


if __name__ == "__main__":
    main()
