#!/usr/bin/env python3
# The game's thumbnails and icon, part 2 (part 1: tools/preview/game_thumbs.luau draws the scenes and the driftlings;
# sh tools/preview/game_thumbs.sh runs both). The request of 2026-11-20: "could you make thumbnails that are engaging
# and show the gameplay well, along with an icon? use creature models, dont need to show the player".
#
# Every picture is pixel art on one grid, scaled up whole (nearest) to the size Roblox takes (the pixel art rule: one
# pixel size, a 1 px ink outline, clean steps, no mixels):
#   * a thumbnail is 480 x 270 art px, 4x: 1920 x 1080. Its scene is a frame of the game as it draws itself (the
#     pixel filter at 4 screen px an art px, read back onto the art grid), the HUD off and the founder out of it; over
#     it the driftlings drawn alone through the game's picture path (Pixel/Snapshot) at their own bigger sizes (a
#     bigger thing is its own picture, never one scaled), a shadow under each, and the words in the game's pixel faces:
#     the title in HUGE (the BIG face doubled the way BIG doubles SMALL: every diagonal step kept to a 1 px stair) and
#     the captions in BIG (scripts/gen_pixelfont.py), each in a ramp with the 1 px ink outline and ink depth under it.
#   * the icon is 128 x 128 art px, 4x: 512 x 512: a driftling cheering on a hill by the sea, the rarest egg beside it.
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
from product_icons import PAL, INK, WHITE, mix, dark, light  # noqa: E402
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


def load_scene(path):
    """A frame the preview drew at K screen px an art px, read back onto the art grid (its phase found by where the
    K x K blocks are whole)."""
    from PIL import Image

    img = Image.open(path).convert("RGB")
    W, H = img.size
    data = img.load()
    best, phase = -1, (0, 0)
    for oy in range(K):
        for ox in range(K):
            good = 0
            for by in range(40, H - K, 37):
                for bx in range(40, W - K, 53):
                    x0, y0 = bx - (bx - ox) % K, by - (by - oy) % K
                    c = data[x0, y0]
                    if all(data[x0 + i, y0 + j] == c for i in range(K) for j in range(K)):
                        good += 1
            if good > best:
                best, phase = good, (ox, oy)
    ox, oy = phase
    art = Art(TW, TH)
    for y in range(TH):
        for x in range(TW):
            sx, sy = min(W - 1, ox + x * K + 1), min(H - 1, oy + y * K + 1)
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
FACES = {"big": (BIG, 2), "huge": (HUGE, 4)}  # a face and its letter spacing


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
    its lower rows in the shade, a lit pixel on every top edge), a 1 px ink outline and `depth` px of ink under it.
    Returns the words' box."""
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
    for x, y in ring | deep:
        cv.put(x, y, INK)
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
    """A four-pointed twinkle with its ink."""
    arm = 3 if big else 2
    pts = {(x, y)}
    for d in range(1, arm + 1):
        pts |= {(x + d, y), (x - d, y), (x, y + d), (x, y - d)}
    for px, py in pts:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if (px + dx, py + dy) not in pts:
                cv.put(px + dx, py + dy, INK)
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
    mask, w, h = text_mask("Driftling Isle", "huge")
    gold, teal = PAL["accent"], PAL.get("shallow", (110, 220, 210))
    x0 = TW // 2 - w // 2
    mw = text_mask("Driftling ", "huge")[1] + 4
    words(cv, "Driftling", 0, 42, gold, "huge", 3, x0=x0)
    words(cv, "Isle", 0, 42, light(teal, 0.15), "huge", 3, x0=x0 + mw)
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


def thumb_collect(sc, pics, kinds):
    cv = sc["lawn"]
    thumb_caption(cv, "%d driftlings to find" % kinds, top=True)
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
    # the sea along the horizon, its far edge lighter
    sea = PAL.get("sea", (60, 170, 210))
    for y in range(84, 96):
        for x in range(IW):
            cv.put(x, y, light(sea, 0.3) if y == 84 else (sea if y < 90 else dark(sea, 0.88)))
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
    cloud(70, 44, 4)
    # the hill: an ellipse of grass, its rim a step lighter, a band of sand where it meets the sea
    grass = PAL.get("grass", (110, 200, 90))
    sand = PAL.get("sand", (240, 210, 170))
    cx, cy, rx, ry = 64, 132, 92, 44
    for y in range(80, IW):
        for x in range(IW):
            d = ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2
            d2 = ((x + 0.5 - cx) / (rx + 4)) ** 2 + ((y + 0.5 - cy) / (ry + 3)) ** 2
            if d <= 1:
                cv.put(x, y, light(grass, 0.25) if d > 0.9 else (grass if d > 0.35 else dark(grass, 0.92)))
            elif d2 <= 1:
                cv.put(x, y, sand)
    # an ink line where the hill meets the sky and the sea
    edge = []
    for y in range(80, IW):
        for x in range(IW):
            c = cv.get(x, y)
            up = cv.get(x, y - 1)
            if c in (sand,) and up is not None and up not in (sand,) and not _is_land(up, grass, sand):
                edge.append((x, y - 1))
    for x, y in edge:
        cv.put(x, y, dark(sea, 0.6))
    stand(cv, pics["icon_egg"], 102, 112)
    for (x, y, big) in ((90, 60, True), (118, 72, False), (114, 52, False)):
        sparkle(cv, x, y, big, light(PAL["accent"], 0.5))
    stand(cv, pics["icon_main"], 52, 122)
    return cv


def _is_land(c, grass, sand):
    return c == sand or c == grass or c == light(grass, 0.25) or c == dark(grass, 0.92)


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
        return load_scene(p)

    sc = {n: scene(n) for n in ("tree", "tree_near", "town", "lawn", "hatch_blaze")}
    os.makedirs(a.out, exist_ok=True)
    made = [
        ("thumb_1_title", thumb_title(sc, pics)),
        ("thumb_2_hatch", thumb_hatch(sc, pics)),
        ("thumb_3_collect", thumb_collect(sc, pics, kinds)),
        ("thumb_4_build", thumb_build(sc, pics)),
        ("thumb_5_eggs", thumb_eggs(sc, pics)),
    ]
    imgs = []
    for name, cv in made:
        img = cv.image(K)
        img.save(os.path.join(a.out, name + ".png"))
        imgs.append(img)
    ic = icon(pics)
    ic.image(4).save(os.path.join(a.out, "icon.png"))
    print("%d thumbnails (1920 x 1080) and the icon (512 x 512) -> %s" % (len(made), a.out))
    if a.sheet:
        from PIL import Image

        sw, sh = 960, 540
        sheet = Image.new("RGB", (2 * sw + 48, 3 * sh + 64), (40, 34, 48))
        for i, img in enumerate(imgs):
            sheet.paste(img.resize((sw, sh), Image.NEAREST), (16 + (i % 2) * (sw + 16), 16 + (i // 2) * (sh + 16)))
        sheet.paste(ic.image(4), (16 + sw + 16 + (sw - 512) // 2, 16 + 2 * (sh + 16) + (sh - 512) // 2))
        sheet.save(a.sheet)
        print("sheet:", a.sheet)


if __name__ == "__main__":
    main()
