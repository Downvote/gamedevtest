#!/usr/bin/env python3
# The game passes' and developer products' icons, part 2 (part 1: tools/preview/product_icons.luau draws the subjects
# from the game's own models; sh tools/preview/product_icons.sh runs both). Each icon is pixel art on a 64 x 64 grid,
# scaled 8x (nearest) to the 512 x 512 PNG the Creator Dashboard takes, one pixel size throughout (the pixel art
# rule: no mixels, a 1 px outline, clean steps, ramps lit from the top left). Every outline is a darker step of the
# colour inside it, never flat ink (selective outlining, the request of 2026-11-20: "For outlines everywhere, no longer
# use pure black, but a darker version of suitable neighbouring pixels instead"): the shapes draw their outlines in ink
# as before (Canvas.edge, Canvas.outline) and Canvas.finish gives each the step of the colour it rings, the one
# Render/Shading's inkOf takes in the world; the words' outline and depth a stronger step of their face, as the game's
# words (Pixel/PixelText). Lines drawn on a thing (the clock's hands) stay ink:
#   * a game pass is a round badge (Roblox shows passes cut to a circle): a bevelled rim in the pass's colour round a
#     sunburst, the dark backdrop beyond it only in the corners the circle cuts away;
#   * a developer product is a rounded square badge, its corners left clear;
#   * on it the subject (the game's model, tidied: tools/preview/gen_portraits.tidy) and the overlays drawn here: the
#     words in the game's big pixel face (scripts/gen_pixelfont.py's BIG: "x2", "VIP", "24H", "FREE"), a clock, a
#     lightning bolt, two chasing arrows, a moon with its Z's, a golden ticket.
# The sunburst's ray edges are only at 0, 26.6, 45, 63.4 and 90 degrees (and their turns): slopes of 1:2, 1:1 and 2:1,
# which step evenly on the pixel grid.
#
# Usage: python3 tools/preview/product_icons.py <picons log> <out dir> [--sheet sheet.png]
import argparse, math, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, "scripts"))
from gen_portraits import parse, tidy  # noqa: E402
import gen_pixelfont  # noqa: E402

N = 64  # the art grid
SCALE = 8  # 512 / 64

# ---------------------------------------------------------------- colours (Data/Palette)
def palette():
    src = open(os.path.join(REPO, "src/shared/Data/Palette.luau")).read()
    out = {}
    for k, v in re.findall(r"^\s*([a-z_0-9]+)\s*=\s*0x([0-9A-Fa-f]{6})", src, re.M):
        out.setdefault(k, (int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16)))
    return out


PAL = palette()
INK = (0x2B, 0x1E, 0x2E)
WHITE = (255, 255, 255)
INK_KEEP, INK_ADD = 0.45, 0.3  # an outline: this much of the colour inside it, plus this much of the ink
TEXT_KEEP, TEXT_ADD = 0.3, 0.3  # the words' outline and depth (the game's words: Pixel/PixelText)


def ink_of(c, keep=INK_KEEP, add=INK_ADD):
    return tuple(min(255, int(c[i] * keep + INK[i] * add + 0.5)) for i in range(3))


def lum(c):
    return 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]


def pick_beside(cols):  # the commonest of the colours beside a pixel, the darker on a tie
    return max(cols, key=lambda c: (sum(1 for d in cols if d == c), -lum(c)))


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def dark(c, k):  # a step darker and a touch cooler (the ramps' own way)
    return (int(c[0] * k), int(c[1] * k), min(255, int(c[2] * k + 10 * (1 - k))))


def light(c, k):  # a step lighter and a touch warmer
    return mix(c, (255, 250, 236), k)


def ramp(base):
    """A theme's tones, darkest to lightest."""
    return {
        "back": dark(base, 0.30),  # the corners a round badge leaves
        "rim_d": dark(base, 0.55),
        "rim": dark(base, 0.78),
        "rim_l": light(base, 0.35),
        "ray_d": dark(base, 0.88),
        "ray": base,
        "glow": light(base, 0.28),
        "glow2": light(base, 0.5),
    }


# ---------------------------------------------------------------- the canvas
class Canvas:
    def __init__(self):
        self.px = [[None] * N for _ in range(N)]
        self.edges = {}  # (x, y) -> the points it rings (None: whatever is beside it): outlines drawn in ink for now

    def edge(self, x, y, inside=None):
        """An outline pixel: ink until `finish` makes it a darker step of the colour of `inside` (its neighbours)."""
        if 0 <= x < N and 0 <= y < N:
            self.px[y][x] = INK
            self.edges[(x, y)] = inside

    def finish(self):
        """Every outline pixel still showing (not drawn over since) a darker step of the colour it rings: the commonest of
        the colours at its `inside` points (else of its 4-neighbours, else its 8), the darker on a tie, never ink."""
        out = {}
        for (x, y), inside in self.edges.items():
            if self.px[y][x] != INK:
                continue
            cols = [self.get(*q) for q in (inside or [])]
            cols = [c for c in cols if c is not None and c != INK]
            for steps in (((1, 0), (-1, 0), (0, 1), (0, -1)), ((1, 1), (1, -1), (-1, 1), (-1, -1))):
                if not cols:
                    cols = [c for c in (self.get(x + dx, y + dy) for dx, dy in steps) if c is not None and c != INK]
            if cols:
                out[(x, y)] = ink_of(pick_beside(cols))
        for (x, y), c in out.items():
            self.px[y][x] = c

    def put(self, x, y, c):
        if 0 <= x < N and 0 <= y < N and c is not None:
            self.px[y][x] = c

    def get(self, x, y):
        return self.px[y][x] if 0 <= x < N and 0 <= y < N else None

    def sprite(self, rows, keys, ox, oy):
        # (a key drawn in ink is the sprite's outline: it rings the sprite's other pixels beside it)
        def at(x, y):
            return rows[y][x] if 0 <= y < len(rows) and 0 <= x < len(rows[y]) else "."

        for y, r in enumerate(rows):
            for x, ch in enumerate(r):
                if ch in keys:
                    if keys[ch] == INK:
                        inside = [(ox + x + dx, oy + y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                                  if at(x + dx, y + dy) in keys and keys[at(x + dx, y + dy)] != INK]
                        self.edge(ox + x, oy + y, inside)
                    else:
                        self.put(ox + x, oy + y, keys[ch])

    def picture(self, px, ox, oy):
        for y, row in enumerate(px):
            for x, c in enumerate(row):
                if c is not None:
                    self.put(ox + x, oy + y, c)

    def outline(self, mask, c=INK, diag=True):
        """A 1 px ring of `c` round the set of points `mask` (on pixels not in it); in ink, an outline `finish` makes a
        darker step of the colours inside it."""
        ring = {}
        steps = [(1, 0), (-1, 0), (0, 1), (0, -1)] + ([(1, 1), (1, -1), (-1, 1), (-1, -1)] if diag else [])
        for x, y in mask:
            for dx, dy in steps:
                q = (x + dx, y + dy)
                if q not in mask:
                    ring.setdefault(q, []).append((x, y))
        for (x, y), inside in ring.items():
            if c == INK:
                self.edge(x, y, inside)
            else:
                self.put(x, y, c)


# ---------------------------------------------------------------- badges
def depth_round(x, y):
    """How far pixel (x, y)'s centre is inside the round badge (negative: outside)."""
    return 31.6 - math.hypot(x + 0.5 - 32, y + 0.5 - 32)


def depth_square(x, y, r=11.0):
    """How far inside the rounded square (corner radius r)."""
    half = 32.0
    qx = max(abs(x + 0.5 - 32) - (half - r), 0.0)
    qy = max(abs(y + 0.5 - 32) - (half - r), 0.0)
    inner = min(max(abs(x + 0.5 - 32) - (half - r), abs(y + 0.5 - 32) - (half - r)), 0.0)
    return -(math.hypot(qx, qy) + inner - r)


# the ray boundaries: slopes 0, 1:2, 1:1, 2:1, vertical, in every quadrant
_B = [0.0, math.degrees(math.atan(0.5)), 45.0, math.degrees(math.atan(2.0))]
BOUNDS = sorted({(b + q) % 360 for q in (0, 90, 180, 270) for b in _B})


def ray_of(x, y, cx, cy):
    a = math.degrees(math.atan2(y + 0.5 - cy, x + 0.5 - cx)) % 360
    i = 0
    while i + 1 < len(BOUNDS) and a >= BOUNDS[i + 1]:
        i += 1
    return i % 2


def badge(cv, shape, t, rim):
    """The badge: backdrop, ink edge, the bevelled rim, an inner ink line and the sunburst with its glow."""
    dep = depth_round if shape == "round" else depth_square
    cx, cy = 32, 30  # the sunburst's middle, a little high (the subject sits on it)
    for y in range(N):
        for x in range(N):
            d = dep(x, y)
            if d < 0:
                if shape == "round":
                    cv.put(x, y, t["back"])
                continue
            if d < 1.0:
                # (the badge's outline: a darker step of the rim inside it)
                cv.edge(x, y, [(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if dep(x + dx, y + dy) >= 1.0])
            elif d < 4.0:
                # the rim, lit from the top left: the lit side's light tone, the shaded side's dark, a band of the
                # mid tone between (by where the pixel lies round the badge)
                nx, ny = (x + 0.5 - 32), (y + 0.5 - 32)
                ln = math.hypot(nx, ny) or 1
                facing = (-nx - ny) / (ln * math.sqrt(2))  # 1 at the top left, -1 at the bottom right
                if d < 1.9 and facing > 0.25:
                    c = rim["rim_l"]
                elif facing < -0.35 or d > 3.1:
                    c = rim["rim_d"]
                else:
                    c = rim["rim"]
                cv.put(x, y, c)
            elif d < 5.0:
                cv.edge(x, y)
            else:
                r = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
                c = t["ray"] if ray_of(x, y, cx, cy) == 0 else t["ray_d"]
                # the glow: two rings of light round the middle, their edges in a checker of the two tones
                if r < 11.5 or (r < 13.0 and (x + y) % 2 == 0):
                    c = t["glow2"]
                elif r < 18.5 or (r < 20.0 and (x + y) % 2 == 0):
                    c = t["glow"]
                cv.put(x, y, c)


def sparkle(cv, x, y, big=False, c=WHITE):
    """A four-pointed twinkle (3 or 5 px across), its points the colour, its heart white."""
    pts = [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)]
    if big:
        pts += [(2, 0), (-2, 0), (0, 2), (0, -2)]
    for dx, dy in pts:
        cv.put(x + dx, y + dy, c)
    cv.put(x, y, WHITE)


# ---------------------------------------------------------------- words in the big face
_SMALL = gen_pixelfont.build_small()
BIG = gen_pixelfont.build_big(_SMALL)


def text_mask(s):
    pen, pts, top_min, bot_max = 0, set(), 99, -99
    for ch in s:
        top, rows = BIG.get(ch) or BIG["?"]
        for ry, r in enumerate(rows):
            for rx, c in enumerate(r):
                if c == "#":
                    pts.add((pen + rx, top + ry))
                    top_min, bot_max = min(top_min, top + ry), max(bot_max, top + ry)
        pen += len(rows[0]) + 2
    w = pen - 2
    return {(x, y - top_min) for x, y in pts}, w, bot_max - top_min + 1


def words(cv, s, cx, by, fill, shade_c):
    """`s` centred on x `cx`, its baseline (last row) at y `by`: the face in `fill`, its lower rows in `shade_c`, a 1 px
    outline and 2 px of depth below in a darker step of the face (the game's titles)."""
    mask, w, h = text_mask(s)
    ox, oy = cx - w // 2, by - h + 1
    pts = {(x + ox, y + oy) for x, y in mask}
    deep = set(pts)
    for x, y in pts:
        deep |= {(x, y + 1), (x, y + 2)}
    edge_c = ink_of(fill, TEXT_KEEP, TEXT_ADD)
    cv.outline(deep, edge_c)
    for x, y in deep:
        cv.put(x, y, edge_c)
    for x, y in pts:
        cv.put(x, y, shade_c if y - oy >= h - 4 else fill)
        if y - oy <= 1 and (x, y - 1) not in pts:
            cv.put(x, y, light(fill, 0.6))


# ---------------------------------------------------------------- small symbols (hand drawn)
# keys: k ink, w white, plus each symbol's own
BOLT = [  # its edges at 1:1 and 1:2, lit down its left edge, its tail in the shade
    "......kkkkkkk",
    ".....kwyyyyyk",
    ".....kwyyyyk.",
    "....kwyyyyk..",
    "....kwyyyk...",
    "...kwyyyyk...",
    "...kwyyyykkkk",
    "..kwyyyyyyyyk",
    "..kkkkkkyyyk.",
    "......kyyyk..",
    ".....kyyok...",
    ".....kyok....",
    "....kyok.....",
    "....kok......",
    "...kok.......",
    "...kk........",
]
STAR9 = [
    "....k....",
    "...kyk...",
    "kkkkyykkk",
    "kwyyyyyyk",
    ".kyyyyok.",
    "..kyyyok.",
    ".kyookyok",
    ".kok.kook",
    ".kk...kkk",
]
ZZ = [  # a Z, 5 px, with its ink
    "kkkkkkk",
    "kwwwwwk",
    "kkkkwwk",
    "..kwwk.",
    ".kwwkkk",
    "kwwwwwk",
    "kkkkkkk",
]
ZS = [
    "kkkkk",
    "kwwwk",
    "kkwwk",
    "kwwkk",
    "kwwwk",
    "kkkkk",
]


def disc_pts(cx, cy, r):
    return {(x, y) for x in range(int(cx - r - 1), int(cx + r + 2)) for y in range(int(cy - r - 1), int(cy + r + 2))
            if math.hypot(x + 0.5 - cx, y + 0.5 - cy) <= r}


def clock(cv, cx, cy):
    """A round clock face with two hands at ten past two and speed lines behind it (the faster tree)."""
    face = disc_pts(cx, cy, 7.4)
    rim = face - disc_pts(cx, cy, 5.9)
    cv.outline(face, INK)
    for p in face:
        cv.put(*p, (255, 252, 240))
    for p in rim:
        x, y = p
        lit = (x + 0.5 - cx) + (y + 0.5 - cy) < 0
        cv.put(x, y, PAL["gold"] if lit else dark(PAL["gold"], 0.72))
    ix, iy = int(cx), int(cy)
    for d in range(0, 5):  # the long hand, up
        cv.put(ix, iy - d, INK)
    for d in range(0, 4):  # the short hand, right
        cv.put(ix + d, iy, INK)
    cv.put(ix, iy, PAL["berry_red"])
    for k in (-3, 0, 3):  # ticks
        pass
    for x, y in ((ix - 4, iy), (ix, iy + 4)):
        cv.put(x, y, dark(PAL["gold"], 0.72))
    # speed lines to the left
    for row, ln in ((iy - 3, 4), (iy, 6), (iy + 3, 4)):
        for x in range(int(cx - 8.5) - ln, int(cx - 8.5)):
            cv.put(x, row, WHITE)
        # (their outline a darker step of the white)
        line_ink = ink_of(WHITE)
        cv.put(int(cx - 8.5) - ln - 1, row, line_ink)
        for x in range(int(cx - 8.5) - ln - 1, int(cx - 8.5)):
            if cv.get(x, row - 1) not in (WHITE,):
                cv.put(x, row - 1, line_ink) if (x, row - 1) not in face else None
            if cv.get(x, row + 1) not in (WHITE,):
                cv.put(x, row + 1, line_ink) if (x, row + 1) not in face else None


def chip(cv, cx, cy, r, fill, rim=None):
    """A round chip for a symbol: an outline a darker step of it, a rim a tone darker on its lower right."""
    disc = disc_pts(cx, cy, r)
    cv.outline(disc, INK)
    for x, y in disc:
        edge = math.hypot(x + 0.5 - cx, y + 0.5 - cy) > r - 1.4
        lower = (x + 0.5 - cx) + (y + 0.5 - cy) > 0
        cv.put(x, y, (rim or dark(fill, 0.8)) if edge and lower else fill)
    return disc


def arrows(cv, cx, cy, col):
    """Two arrows chasing each other round a circle (a fresh lot) on a cream chip: each a 2 px arc with a gap before the
    next one's head, the heads' sides at 1:1, the right one pointing down and the left one up (clockwise)."""
    chip(cv, cx, cy, 12.4, (255, 252, 240), (232, 222, 200))
    dk = dark(col, 0.58)
    shape = set()
    for x, y in disc_pts(cx, cy, 8.0) - disc_pts(cx, cy, 5.2):
        a = math.degrees(math.atan2(y + 0.5 - cy, x + 0.5 - cx)) % 360
        if 232 <= a < 345 or 52 <= a < 165:
            shape.add((x, y))
    ix, iy = int(cx), int(cy)
    for k, w in enumerate((4, 3, 2, 1, 0)):  # rows 9, 7, 5, 3, 1 wide
        for dx in range(-w, w + 1):
            shape.add((ix + 6 + dx, iy - 1 + k))  # the right head, pointing down
            shape.add((ix - 7 + dx, iy - k))  # the left head, pointing up
    cv.outline(shape, dk)
    for x, y in shape:
        cv.put(x, y, col)


def moon(cv, cx, cy):
    """A crescent moon lit from the left, and two Z's floating up from the sleeper."""
    a = disc_pts(cx, cy, 6.6)
    b = disc_pts(cx + 3.6, cy - 2.4, 5.6)
    cres = a - b
    cv.outline(cres, INK)
    for x, y in cres:
        lit = (x + 0.5 - cx) + (y + 0.5 - cy) < -2
        cv.put(x, y, (255, 246, 200) if lit else PAL["yellow"])


def shell(cv, cx, by, R=21):
    """A big scallop (the shells counter's own, drawn large): ribs fanning up from the hinge at (cx, by), alternate ribs a
    tone darker, the whole lit from the top left, two ears at the hinge."""
    base = PAL["coral"]
    tones = [dark(base, 0.62), dark(base, 0.8), base, light(base, 0.3), light(base, 0.55)]
    hx, hy = cx, by - 2.0
    pts = {}
    for y in range(by - R - 2, by + 1):
        for x in range(cx - R - 2, cx + R + 3):
            dx, dy = x + 0.5 - hx, hy - (y + 0.5)
            r = math.hypot(dx, dy)
            a = math.degrees(math.atan2(dy, dx))
            if r <= R and 28 <= a <= 152:
                pts[(x, y)] = (r, a)
    # the ears: a little block each side of the hinge
    for x in range(cx - 7, cx + 7):
        for y in range(by - 4, by):
            if (x, y) not in pts and abs(x + 0.5 - cx) > 1.5:
                pts[(x, y)] = (0.0, 90.0 if x < cx else 90.0)
    cv.outline(set(pts), INK)
    bounds = [52.0, 63.4, 76.0, 90.0, 104.0, 116.6, 128.0]
    for (x, y), (r, a) in pts.items():
        rib = sum(1 for b in bounds if a > b)
        lit = (cx - x) * 0.6 + (by - y) * 0.5 - 6  # toward the top left
        k = 2 + (1 if lit > 4 else 0) + (1 if lit > 11 else 0) - (1 if lit < -4 else 0)
        if rib % 2 == 1:
            k -= 1
        if r > R - 1.2:  # the lip: a step lighter along the top edge
            k += 1
        cv.put(x, y, tones[max(0, min(4, k))])
    # the hinge's shadow between the ears
    for x in range(cx - 1, cx + 1):
        cv.put(x, by - 1, tones[0])


def ticket(cv, cx, cy):
    """A golden ticket, its ends notched, a star on it, tilted a step (its edges at 1:2)."""
    w, h = 36, 22
    pts = set()
    for y in range(h):
        for x in range(w):
            # the notches: a half disc cut from each end's middle
            if math.hypot(x + 0.5, y + 0.5 - h / 2) < 4.2 or math.hypot(x + 0.5 - w, y + 0.5 - h / 2) < 4.2:
                continue
            # the corners rounded off by a pixel
            if (x, y) in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
                continue
            pts.add((x, y))
    # a shear of one pixel up per two across: the ticket tilted with clean 1:2 steps
    sheared = {(x + cx - w // 2, y + cy - h // 2 - x // 6) for x, y in pts}
    cv.outline(sheared, INK)
    gold, gold_d, gold_l = PAL["gold"], dark(PAL["gold"], 0.72), light(PAL["gold"], 0.55)
    for x0, y0 in pts:
        x, y = x0 + cx - w // 2, y0 + cy - h // 2 - x0 // 6
        c = gold
        if y0 < 2:
            c = gold_l
        elif y0 >= h - 2:
            c = gold_d
        # the perforation: a dotted line a third along
        if x0 == 10 and y0 % 3 == 1:
            c = gold_d
        # a border line inside the edge
        if 2 <= y0 < h - 2 and (y0 == 2 or y0 == h - 3) and 4 < x0 < w - 5:
            c = gold_d
        cv.put(x, y, c)
    cv.sprite(STAR9, {"k": INK, "y": PAL["berry_red"], "w": light(PAL["berry_red"], 0.6), "o": dark(PAL["berry_red"], 0.7)}, cx + 1, cy - 7)


# ---------------------------------------------------------------- the icons
# id -> shape (round: a game pass; square: a developer product), theme colour (rim and sunburst), subject (a picons
# picture), its offset, words, symbols
ICONS = [
    ("VIP", "round", "gold", "crown", (0, -5), ("VIP", WHITE), None),
    ("DoubleIncome", "round", "teal", None, (0, 0), ("x2", PAL["yellow"]), "shell"),
    ("QuickTree", "round", "leaf", "tree", (-2, -3), None, "clock"),
    ("FreeDecor", "round", "pink", "fountain", (0, -4), ("FREE", WHITE), None),
    ("PremiumTrack", "round", "purple", None, (0, 0), None, "ticket"),
    ("OfflinePass", "round", "sky_night", "sleeper", (2, -3), ("24H", PAL["yellow"]), "moon"),
    ("EggUncommon", "square", "r_uncommon", "egg2", (0, -1), None, None),
    ("EggRare", "square", "r_rare", "egg3", (0, -1), None, None),
    ("EggEpic", "square", "r_epic", "egg4", (0, -1), None, None),
    ("EggLegendary", "square", "r_legend", "egg5", (0, -1), None, None),
    ("EggMythic", "square", "r_mythic", "egg6", (0, -1), None, None),
    ("EggCelestial", "square", "sky_night", "egg7", (0, -1), None, None),
    ("RefreshShop", "square", "orange", "stall", (-2, -2), None, "arrows"),
    ("StarterPack", "square", "sky_day", "starter", (0, -1), None, None),
    ("HatcheryNow", "square", "yellow", "hatchery", (-2, -1), None, "bolt"),
    ("RefreshEggs", "square", "leaf", "eggs3", (-1, -2), None, "arrows"),
]


def build_icon(spec, pics):
    key, shape, theme, subject, off, word, sym = spec
    base = PAL.get(theme) or PAL["gold"]
    t = ramp(base)
    cv = Canvas()
    badge(cv, shape, t, t)
    # twinkles in the sky round the subject
    for (x, y, big) in ((12, 15, True), (51, 13, False), (49, 47, False), (14, 44, False)):
        sparkle(cv, x, y, big, light(base, 0.75))
    if subject:
        px = pics[subject]
        h, w = len(px), len(px[0])
        cv.picture(px, (N - w) // 2 + off[0], (N - h) // 2 + off[1])
    if sym == "shell":
        shell(cv, 32, 44)
    elif sym == "ticket":
        ticket(cv, 32, 33)
    elif sym == "clock":
        clock(cv, 45, 45)
    elif sym == "arrows":
        arrows(cv, 45, 45, dark(PAL["leaf"], 0.85) if key == "RefreshEggs" else dark(PAL["orange"], 0.92))
    elif sym == "bolt":
        chip(cv, 46, 45, 12.0, PAL["sky_night"], dark(PAL["sky_night"], 0.7))
        cv.sprite(BOLT, {"k": INK, "y": PAL["yellow"], "w": light(PAL["yellow"], 0.7), "o": dark(PAL["yellow"], 0.75)}, 40, 37)
    elif sym == "moon":
        moon(cv, 17, 17)
        cv.sprite(ZS, {"k": INK, "w": WHITE}, 42, 9)
        cv.sprite(ZZ, {"k": INK, "w": WHITE}, 47, 15)
    if word:
        s, fill = word
        words(cv, s, 32, 53, fill, dark(fill, 0.8))
    cv.finish()
    return cv


def save(cv, path, scale=SCALE):
    from PIL import Image

    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    for y in range(N):
        for x in range(N):
            c = cv.px[y][x]
            if c is not None:
                img.putpixel((x, y), c + (255,))
    img.resize((N * scale, N * scale), Image.NEAREST).save(path)
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("out")
    ap.add_argument("--sheet")
    a = ap.parse_args()
    raw = parse(a.log, "@@ICON ")
    if not raw:
        sys.exit("no @@ICON lines in " + a.log)
    pics = {k: tidy(v, thin=True) for k, v in raw.items()}
    os.makedirs(a.out, exist_ok=True)
    smalls = []
    for spec in ICONS:
        if spec[3] and spec[3] not in pics:
            sys.exit("no picture for " + spec[3])
        cv = build_icon(spec, pics)
        smalls.append((spec[0], save(cv, os.path.join(a.out, spec[0] + ".png"))))
    print("%d icons (512 x 512) -> %s" % (len(smalls), a.out))
    if a.sheet:
        from PIL import Image

        S, cols = 4, 4
        rows = (len(smalls) + cols - 1) // cols
        sheet = Image.new("RGBA", (cols * (N * S + 16) + 16, rows * (N * S + 16) + 16), (40, 34, 48, 255))
        for i, (_, img) in enumerate(smalls):
            big = img.resize((N * S, N * S), Image.NEAREST)
            sheet.alpha_composite(big, (16 + (i % cols) * (N * S + 16), 16 + (i // cols) * (N * S + 16)))
        sheet.save(a.sheet)
        print("sheet:", a.sheet)


if __name__ == "__main__":
    main()
