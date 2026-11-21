#!/usr/bin/env python3
# The game's thumbnails and icon, part 2 (part 1: tools/preview/game_thumbs.luau draws the scenes and the driftlings;
# sh tools/preview/game_thumbs.sh runs both). The request of 2026-11-20: "could you make thumbnails that are engaging
# and show the gameplay well, along with an icon? use creature models, dont need to show the player".
#
# Every picture is pixel art on one grid, scaled up whole (nearest) to the size Roblox takes (the pixel art rule: one
# pixel size, a 1 px outline, clean steps, no mixels; every outline a darker step of the colour beside it, never
# flat ink, since the request of 2026-11-20: "For outlines everywhere, no longer use pure black, but a darker version
# of suitable neighbouring pixels instead"):
#   * a thumbnail is 480 x 270 art px, 4x: 1920 x 1080. Its scene is a frame of the game as it draws itself (the
#     pixel filter at 4 screen px an art px, read back onto the art grid), the HUD off and the founder out of it; over
#     it the driftlings drawn alone through the game's picture path (Pixel/Snapshot) at their own bigger sizes (a
#     bigger thing is its own picture, never one scaled), a shadow under each, and the words in the game's pixel faces:
#     the title in HUGE (the BIG face doubled the way BIG doubles SMALL: every diagonal step kept to a 1 px stair) and
#     the captions in BIG (scripts/gen_pixelfont.py), each in a ramp with a 1 px outline and depth under it in a
#     darker step of its face.
#   * the icon is 128 x 128 art px, 4x: 512 x 512: a driftling cheering on a little floating island in the sky, the
#     rarest egg beside it.
#
# Usage: python3 tools/preview/game_thumbs.py <scenes dir> <cast log> <out dir> [--sheet sheet.png]
#   scenes dir: the PNGs of the "gthumbs" and "gthumbs=hatch" runs (gth_<name>_desktop.png)
#   cast log:   the "gthumbs=cast" run's log (its @@GTH lines)
import argparse, math, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, "scripts"))
from gen_portraits import parse  # noqa: E402
from product_icons import PAL, WHITE, mix, dark, light, ink_of, pick_beside, TEXT_KEEP, TEXT_ADD  # noqa: E402
import gen_pixelfont  # noqa: E402

K = 4
TW, TH = 480, 270  # a thumbnail's art grid
IW = 128  # the icon's


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


# ---------------------------------------------------------------- words
_SMALL = gen_pixelfont.build_small()
BIG = gen_pixelfont.build_big(_SMALL)


def _double(rows):
    """gen_pixelfont.build_big's doubling: each pixel 2 x 2, a 1 px stair where two inked pixels touch at a corner."""
    h, w = len(rows), len(rows[0])

    def at(x, y):
        return 0 <= y < h and 0 <= x < w and rows[y][x] == "#"

    out = [["."] * (2 * w) for _ in range(2 * h)]
    for y in range(h):
        for x in range(w):
            if at(x, y):
                q = [True] * 4
            else:
                up, dn, lf, rt = at(x, y - 1), at(x, y + 1), at(x - 1, y), at(x + 1, y)
                q = [
                    up and lf and not at(x - 1, y - 1),
                    up and rt and not at(x + 1, y - 1),
                    dn and lf and not at(x - 1, y + 1),
                    dn and rt and not at(x + 1, y + 1),
                ]
            for i, (dx, dy) in enumerate(((0, 0), (1, 0), (0, 1), (1, 1))):
                if q[i]:
                    out[2 * y + dy][2 * x + dx] = "#"
    return ["".join(r) for r in out]


HUGE = {ch: (2 * top, _double(rows)) for ch, (top, rows) in BIG.items()}
# (GIANT: HUGE doubled the same way, for the before-and-after thumbnail's DAY 100)
GIANT = {ch: (2 * top, _double(rows)) for ch, (top, rows) in HUGE.items()}
FACES = {"big": (BIG, 2), "huge": (HUGE, 4), "giant": (GIANT, 4)}  # a face and its letter spacing


def text_mask(s, face="big"):
    glyphs, gap = FACES[face]
    pen, pts, top_min, bot_max = 0, set(), 99, -99
    for ch in s:
        top, rows = glyphs.get(ch) or glyphs["?"]
        for ry, r in enumerate(rows):
            for rx, c in enumerate(r):
                if c == "#":
                    pts.add((pen + rx, top + ry))
                    top_min, bot_max = min(top_min, top + ry), max(bot_max, top + ry)
        pen += len(rows[0]) + gap
    return {(x, y - top_min) for x, y in pts}, pen - gap, bot_max - top_min + 1


def words(cv, s, cx, by, fill, face="big", depth=2, x0=None):
    """`s` centred on x `cx` (or from `x0`), its last row at y `by`: the face in a ramp of `fill` (its top rows lit,
    its lower rows in the shade, a lit pixel on every top edge), a 1 px outline and `depth` px of depth under it, both
    a darker step of the face (selective outlining: the game's words, Pixel/PixelText). Returns the words' box."""
    mask, w, h = text_mask(s, face)
    ox = x0 if x0 is not None else cx - w // 2
    oy = by - h + 1
    pts = {(x + ox, y + oy) for x, y in mask}
    deep = set(pts)
    for x, y in pts:
        for d in range(1, depth + 1):
            deep.add((x, y + d))
    ring = set()
    for x, y in deep:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                q = (x + dx, y + dy)
                if q not in deep:
                    ring.add(q)
    edge_c = ink_of(fill, TEXT_KEEP, TEXT_ADD)
    for x, y in ring | deep:
        cv.put(x, y, edge_c)
    hi, lo = light(fill, 0.45), dark(fill, 0.78)
    top_rows = max(1, h // 4)
    low_rows = max(2, (h * 2) // 5)
    for x, y in pts:
        ry = y - oy
        c = hi if ry < top_rows else (lo if ry >= h - low_rows else fill)
        if (x, y - 1) not in pts:
            c = light(fill, 0.75)
        cv.put(x, y, c)
    return (ox - 1, oy - 1, ox + w, by + depth + 1)


# ---------------------------------------------------------------- small things drawn here
def sparkle(cv, x, y, big=False, c=WHITE):
    """A four-pointed twinkle with its outline (a darker step of its colour)."""
    arm = 3 if big else 2
    pts = {(x, y)}
    for d in range(1, arm + 1):
        pts |= {(x + d, y), (x - d, y), (x, y + d), (x, y - d)}
    for px, py in pts:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if (px + dx, py + dy) not in pts:
                cv.put(px + dx, py + dy, ink_of(c))
    for px, py in pts:
        cv.put(px, py, c)
    cv.put(x, y, WHITE)


def bottom_of(pic):
    """The picture's lowest drawn row and the middle of what is drawn in its lowest fifth (where its feet are)."""
    h = len(pic)
    rows = [y for y in range(h) if any(c is not None for c in pic[y])]
    last = rows[-1]
    xs = [x for y in range(max(0, last - h // 5), last + 1) for x, c in enumerate(pic[y]) if c is not None]
    return last, (min(xs) + max(xs)) // 2, max(xs) - min(xs)


def stand(cv, pic, fx, fy):
    """`pic` with its feet at (fx, fy) and a shadow under them on what is there (two flat steps, the world's own way of
    shading: an ellipse a step darker, its middle a step darker again)."""
    last, mid, span = bottom_of(pic)
    rx, ry = max(6, span * 0.55), max(2.5, span * 0.11)
    for y in range(int(fy - ry) - 1, int(fy + ry) + 2):
        for x in range(int(fx - rx) - 1, int(fx + rx) + 2):
            d = ((x + 0.5 - fx) / rx) ** 2 + ((y + 0.5 - fy) / ry) ** 2
            if d <= 1:
                cv.shade(x, y, 0.62 if d <= 0.45 else 0.8)
    cv.picture(pic, fx - mid, fy - last)


# ---------------------------------------------------------------- the thumbnails
def caption_band(cv, y0, y1):
    """A darker band for words over a busy scene: two flat steps, the edge a step lighter than the middle."""
    cv.band(y0, y1, 0.62)
    cv.band(y1, y1 + 3, 0.8)


def thumb_title(sc, pics):
    cv = sc["tree"]
    caption_band(cv, 0, 52)
    mask, w, h = text_mask("Pixel Island", "huge")
    gold, teal = PAL["accent"], PAL.get("shallow", (110, 220, 210))
    x0 = TW // 2 - w // 2
    mw = text_mask("Pixel ", "huge")[1] + 4
    words(cv, "Pixel", 0, 42, gold, "huge", 3, x0=x0)
    words(cv, "Island", 0, 42, light(teal, 0.15), "huge", 3, x0=x0 + mw)
    for (x, y, big) in ((x0 - 14, 16, True), (x0 + w + 12, 30, False), (x0 + w + 20, 12, True), (x0 - 22, 36, False)):
        sparkle(cv, x, y, big, light(gold, 0.5))
    stand(cv, pics["hero_l"], 82, 260)
    stand(cv, pics["hero_s"], 178, 266)
    stand(cv, pics["hero_r"], TW - 78, 262)
    return cv


def thumb_caption(cv, text, top=True):
    if top:
        caption_band(cv, 0, 30)
        words(cv, text, TW // 2, 21, PAL["accent"], "big", 2)
    else:
        cv.band(TH - 30, TH, 0.62)
        cv.band(TH - 33, TH - 30, 0.8)
        words(cv, text, TW // 2, TH - 10, PAL["accent"], "big", 2)


def thumb_hatch(sc, pics):
    cv = sc["hatch_blaze"]
    thumb_caption(cv, "Hatch rare driftlings", top=False)
    return cv


def thumb_eggs(sc, pics):
    cv = sc["tree_near"]
    thumb_caption(cv, "The Tree of Life lays new eggs", top=False)
    return cv


def thumb_build(sc, pics):
    cv = sc["town"]
    thumb_caption(cv, "Build your island town", top=True)
    stand(cv, pics["build_1"], 74, 262)
    stand(cv, pics["build_2"], 156, 266)
    return cv


def thumb_sky(sc, pics):
    cv = sc["sky"]
    thumb_caption(cv, "Grow your island in the sky", top=True)
    return cv


def thumb_collect(sc, pics, kinds):
    cv = sc["lawn"]
    thumb_caption(cv, "%d driftlings to find" % kinds, top=True)
    return cv


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


def div_x(y):
    return DIV_X - y // DIV_STEP


def title(cv, s, size, fill, cx=None, x0=None, top=0, depth=5):
    """Words drawn on the art grid itself, one art pixel at a time (the request of 2026-11-21: "make the text respect
    the pixel grid instead of using mixels"): the font traced at `size` art px into a clean mask (half covered or
    more), an anti-aliasing pixel in each inside corner of a stair (between the face and its outline, where the font
    covers it a little), the face in a ramp lit from the top (a lit row on every top edge), `depth` px of depth under
    it a darker step, and a 1 px outline round all of it, a darker step of the face (selective outlining, the game's
    words). Returns the box drawn."""
    from PIL import Image, ImageDraw, ImageFont

    ft = ImageFont.truetype(TITLE_FONT, size)
    l, t, r, b = ft.getbbox(s)
    w, h = r - l + 4, b - t + 4
    img = Image.new("L", (w, h), 0)
    ImageDraw.Draw(img).text((2 - l, 2 - t), s, font=ft, fill=255)
    cov = img.load()
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
    edge_c = ink_of(fill, TEXT_KEEP, TEXT_ADD)
    deep_c = dark(fill, 0.62)
    hi, lo, top_c = light(fill, 0.42), dark(fill, 0.8), light(fill, 0.72)
    hh = y1f - y0f + 1
    allp = body | deep
    for (x, y) in allp:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                q = (x + dx, y + dy)
                if q not in allp:
                    cv.put(q[0] + ox, q[1] + oy, edge_c)
    for (x, y) in deep:
        cv.put(x + ox, y + oy, deep_c)

    def face_c(x, y):
        ry = (y - y0f) / hh
        c = hi if ry < 0.3 else (lo if ry > 0.62 else fill)
        if (x, y - 1) not in face:
            c = top_c
        return c

    for (x, y) in face:
        cv.put(x + ox, y + oy, face_c(x, y))
    for (x, y) in aa:
        near = [face_c(qx, qy) for (qx, qy) in ((x, y - 1), (x, y + 1), (x - 1, y), (x + 1, y)) if (qx, qy) in face]
        cv.put(x + ox, y + oy, mix(near[0], edge_c, 0.5))
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
    ramp (the upper side lit, the lower in the shade), a 1 px outline a darker step of it (selective outlining)."""
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

    def in_tri(px, py):
        def side(ax, ay, bx, by):
            return (bx - ax) * (py - ay) - (by - ay) * (px - ax)

        d1, d2, d3 = side(*tip, *c1), side(*c1, *c2), side(*c2, *tip)
        return not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))

    shape = {}
    xs = [p[0] for p in line] + [tip[0], c1[0], c2[0]]
    ys = [p[1] for p in line] + [tip[1], c1[1], c2[1]]
    for y in range(int(min(ys)) - 8, int(max(ys)) + 9):
        for x in range(int(min(xs)) - 8, int(max(xs)) + 9):
            cx, cy = x + 0.5, y + 0.5
            best, off = 1e9, 0.0
            for (lx, ly) in line[:-8]:
                d = (cx - lx) ** 2 + (cy - ly) ** 2
                if d < best:
                    best, off = d, cy - ly
            if best <= r * r:
                shape[(x, y)] = off
            elif in_tri(cx, cy):
                shape[(x, y)] = (cy - (y2 + ty * head * 0.3)) * 0.5
    hi, lo = light(color, 0.38), dark(color, 0.74)
    for (x, y) in shape:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if (x + dx, y + dy) not in shape:
                    cv.put(x + dx, y + dy, ink_of(color))
    for (x, y), off in shape.items():
        c = hi if off < -2.4 else (lo if off > 2.4 else color)
        if (x, y - 1) not in shape:
            c = light(color, 0.6)
        cv.put(x, y, c)


def thumb_days(sc):
    small, full = sc["day1"], sc["day100"]
    cv = Art(DW, DH)
    for y in range(DH):
        d = div_x(y)
        for x in range(DW):
            cv.px[y][x] = small.px[y][x] if x < d else full.px[y][x]
    # the bar, white, its edges a darker step of it, a clean stair of DIV_STEP rows
    edge = ink_of(WHITE)
    for y in range(DH):
        d = div_x(y)
        cv.put(d - 1, y, edge)
        for x in range(d, d + DIV_W):
            cv.put(x, y, WHITE)
        cv.put(d + DIV_W, y, edge)
    # the arrow from the first island round to the full one
    arrow(cv, ((232, 476), (318, 536), (404, 516)), PAL["berry_red"])
    # the words, on this grid: DAY 1 smaller over the first island, DAY 100 big and gold over the full one
    title(cv, "DAY 1", 66, WHITE, x0=30, top=26, depth=4)
    right = (div_x(0) + DIV_W + 1 + DW) // 2
    box = title(cv, "DAY 100", 112, PAL["accent"], cx=right + 4, top=22, depth=6)
    for (x, y, arm) in ((box[0] - 14, 30, 7), (box[2] + 8, 104, 4), (box[2] + 4, 18, 5)):
        if 0 < x < DW:
            sparkle_big(cv, x, y, arm, light(PAL["accent"], 0.5))
    return cv


# ---------------------------------------------------------------- the icon
def icon(pics):
    cv = Art(IW, IW)
    sky = PAL.get("sky_day", (154, 218, 249))
    # (deeper and bluer toward the top, paler at the horizon: flat bands, each a clean step)
    bands = [(0, (92, 168, 236)), (22, (112, 186, 242)), (42, (132, 202, 246)), (60, sky), (74, light(sky, 0.3))]
    for y in range(IW):
        c = bands[0][1]
        for y0, bc in bands:
            if y >= y0:
                c = bc
        for x in range(IW):
            cv.put(x, y, c)
    # clouds: puffs of circles, flat, a shade on their undersides
    def cloud(cx, cy, r):
        pts = set()
        for (dx, dy, rr) in ((0, 0, r), (-r, 2, r * 0.75), (r, 2, r * 0.8), (int(r * 1.8), 4, r * 0.55)):
            for y in range(int(cy + dy - rr) - 1, int(cy + dy + rr) + 2):
                for x in range(int(cx + dx - rr) - 1, int(cx + dx + rr) + 2):
                    if (x + 0.5 - cx - dx) ** 2 + (y + 0.5 - cy - dy) ** 2 <= rr * rr and y <= cy + 4:
                        pts.add((x, y))
        for x, y in pts:
            cv.put(x, y, WHITE if (x, y + 2) in pts else light(sky, 0.7))

    cloud(22, 22, 7)
    cloud(96, 14, 6)
    cloud(14, 118, 5)
    cloud(104, 122, 4)
    # the floating island: a lawn (an ellipse, its rim a step lighter, a darker patch in the middle), the earth lip
    # under its front edge, the rock under that stepping in every 4 px to a point (lit on the left), a 1 px ink outline
    # round it all
    grass = PAL.get("grass", (110, 200, 90))
    earth = PAL.get("chocolate", (142, 92, 62))
    rock, rock_dark = PAL.get("rock", (158, 150, 146)), PAL.get("rock_dark", (110, 102, 100))
    cx, cy, rx, ry, lip = 64, 92, 58, 13, 6

    def lawn_d(x, y):
        return ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2

    land = set()
    for y in range(cy - ry - 1, IW):
        for x in range(IW):
            d = lawn_d(x, y)
            if d <= 1:
                cv.put(x, y, light(grass, 0.25) if d > 0.86 and y < cy else (grass if d > 0.3 else dark(grass, 0.92)))
            elif y > cy and any(lawn_d(x, y - t) <= 1 for t in range(1, lip + 1)):
                cv.put(x, y, earth if lawn_d(x, y - lip + 1) <= 1 else dark(earth, 0.8))
            else:
                k = (y - (cy + 4)) // 4
                w = (rx - 5) - k * 8
                if y < cy + 4 or w <= 0 or abs(x + 0.5 - cx) > w:
                    continue
                cv.put(x, y, rock if x + 0.5 < cx else rock_dark)
            land.add((x, y))
    # the outline: each pixel a darker step of the land beside it (the commonest there, the darker on a tie)
    beside = {}
    for (x, y) in list(land):
        for (nx, ny) in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if (nx, ny) not in land and 0 <= nx < IW and 0 <= ny < IW:
                beside.setdefault((nx, ny), []).append(cv.get(x, y))
    for (nx, ny), cols in beside.items():
        cv.put(nx, ny, ink_of(pick_beside([c for c in cols if c is not None])))
    stand(cv, pics["icon_egg"], 100, 90)
    for (x, y, big) in ((90, 60, True), (118, 72, False), (114, 52, False)):
        sparkle(cv, x, y, big, light(PAL["accent"], 0.5))
    stand(cv, pics["icon_main"], 52, 100)
    return cv


# ---------------------------------------------------------------- main
def pic_of(raw):
    return raw


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scenes")
    ap.add_argument("castlog")
    ap.add_argument("out")
    ap.add_argument("--sheet")
    a = ap.parse_args()
    pics = parse(a.castlog, "@@GTH ")
    if not pics:
        sys.exit("no @@GTH lines in " + a.castlog)
    kinds = 0
    for line in open(a.castlog):
        m = re.search(r"gthumbs: (\d+) kinds of driftling", line)
        if m:
            kinds = int(m.group(1))

    def scene(name):
        p = os.path.join(a.scenes, "gth_%s_desktop.png" % name)
        if not os.path.exists(p):
            sys.exit("no scene " + p)
        return load_scene(p, 2 if name in ("day1", "day100") else K)

    sc = {n: scene(n) for n in ("tree", "tree_near", "town", "lawn", "hatch_blaze", "sky", "day1", "day100")}
    os.makedirs(a.out, exist_ok=True)
    made = [
        ("thumb_0_days", thumb_days(sc)),
        ("thumb_1_title", thumb_title(sc, pics)),
        ("thumb_2_hatch", thumb_hatch(sc, pics)),
        ("thumb_3_collect", thumb_collect(sc, pics, kinds)),
        ("thumb_4_build", thumb_build(sc, pics)),
        ("thumb_5_eggs", thumb_eggs(sc, pics)),
        ("thumb_6_sky", thumb_sky(sc, pics)),
    ]
    imgs = []
    for name, cv in made:
        img = cv.image(1920 // cv.w)
        img.save(os.path.join(a.out, name + ".png"))
        imgs.append(img)
    ic = icon(pics)
    ic.image(4).save(os.path.join(a.out, "icon.png"))
    print("%d thumbnails (1920 x 1080) and the icon (512 x 512) -> %s" % (len(made), a.out))
    if a.sheet:
        from PIL import Image

        sw, sh = 960, 540
        sheet = Image.new("RGB", (2 * sw + 48, 4 * sh + 80), (40, 34, 48))
        for i, img in enumerate(imgs):
            sheet.paste(img.resize((sw, sh), Image.NEAREST), (16 + (i % 2) * (sw + 16), 16 + (i // 2) * (sh + 16)))
        sheet.paste(ic.image(4), (16 + sw + 16 + (sw - 512) // 2, 16 + 3 * (sh + 16) + (sh - 512) // 2))
        sheet.save(a.sheet)
        print("sheet:", a.sheet)


if __name__ == "__main__":
    main()
