#!/usr/bin/env python3
# The thumbnails after the genre's own (the request of 2026-11-21: "do more thumbnail research, and replicate popular
# game thumbnails with the same genre type"). What the research found (GAME_DESIGN 11.1): the most played and most
# liked pet, hatching, tycoon and island games on Roblox reuse a few frames, and these take five of them with this
# game's own driftlings, eggs and islands, drawn as pixel illustrations under the standing rules (one art grid a
# picture, 1 px outlines a darker step of what they ring, anti-aliasing where they step, nothing scaled):
#   * thumb_rarity: the rarity ladder (three panels split by slanted bars, the same kind of creature grander in each,
#     on one of the game's own floating islets, its rarity's name over it and a bigger number under it);
#   * thumb_hero: one big face filling the frame, rays behind it, two more at the frame's edges looking in;
#   * thumb_hatch: an egg, a big curved arrow, what hatched from it, a short line of words;
#   * thumb_lucky: a field full of one common kind with one eternal among them, glowing, its rarity in rainbow letters;
#   * thumb_rich: the full island with coins flying off it and what it makes a minute in rainbow letters.
# Every number on them is the game's own: Tuning.RarityWork for the ladder's, the tier 20 town's coins a minute
# (logged by tools/preview/game_thumbs.luau) for the big one. game_thumbs.py calls these with its canvas, its words
# and its scenes (setup hands this module that one).
import colorsys
import math

from product_icons import PAL, WHITE, mix, dark, light, ink_of, lum  # noqa: F401
import illustrate as IL

G = None  # tools/preview/game_thumbs.py, for Art, title, stand, arrow, sparkle_big and the scenes' helpers


def setup(g):
    global G
    G = g


# a rainbow in flat runs of columns (the genre's rainbow words; each colour a clean band, never blended)
RAINBOW = ((255, 92, 104), (255, 160, 64), (255, 214, 64), (120, 214, 96), (72, 194, 255), (150, 124, 255), (240, 120, 220))


def rainbow(t):
    return RAINBOW[min(len(RAINBOW) - 1, int(t * len(RAINBOW)))]


# the rainbow a letter at a time: each letter or digit one whole colour, the next one the next colour, spread over the
# whole rainbow (the request of 2026-11-21: "make it such that each number is fully colored with colors of the rainbow
# differently to form a rainbow"); a comma or a point takes the colour of the letter before it
RAINBOW8 = ((255, 92, 104), (255, 160, 64), (255, 214, 64), (120, 214, 96), (64, 210, 196), (72, 168, 255), (150, 124, 255), (240, 120, 220))


def rainbow_chars(s):
    marks = [c for c in s if c.isalnum()]
    n = len(marks)
    out, k, last = [], 0, RAINBOW8[0]
    for c in s:
        if c.isalnum():
            last = RAINBOW8[0] if n <= 1 else RAINBOW8[round(k * (len(RAINBOW8) - 1) / (n - 1))]
            k += 1
        out.append(last)
    return out


# Tuning.RarityWork: how much faster a driftling works by its rarity (common 1, rare 2.5, eternal 40)
RARITY_WORK = {1: "1", 3: "2.5", 9: "40"}


# ---------------------------------------------------------------- small helpers
# Hue-shifted shading (the request of 2026-11-21: "use hueshifting such that darker and lighter shades are hueshifted
# to be colorful"): a darker shade turns its hue toward blue violet and grows more saturated as it darkens; a lighter
# one turns toward warm yellow and pales as it lightens. Drop-in for product_icons' dark(c, k) and light(c, k): the
# same k, the same lightness, a more colourful step.
HS_COOL, HS_WARM = 0.72, 0.14


def _hue_toward(h, target, amt):
    d = ((target - h + 0.5) % 1.0) - 0.5
    return (h + d * amt) % 1.0


def hs_dark(c, k):
    r, g, b = (v / 255 for v in c)
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    t = max(0.0, 1.0 - k)
    h = HS_COOL if s < 0.06 else _hue_toward(h, HS_COOL, min(1.0, t * 0.85))
    s = min(1.0, s + t * 0.45 + (0.12 if s < 0.06 else 0.0) * t * 2)
    v = v * k
    return tuple(int(round(x * 255)) for x in colorsys.hsv_to_rgb(h, s, v))


def hs_light(c, k):
    r, g, b = (v / 255 for v in c)
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    h = HS_WARM if s < 0.06 else _hue_toward(h, HS_WARM, min(1.0, k * 0.55))
    s = max(0.0, s * (1 - k * 0.6)) + (0.08 * k if s < 0.06 else 0.0)
    v = v + (1 - v) * k
    return tuple(int(round(x * 255)) for x in colorsys.hsv_to_rgb(h, min(1.0, s), min(1.0, v)))


HUE_SHADE = (hs_dark, hs_light)

# a 4 x 4 ordered dither (Bayer): where a gradient or a band of light passes from one flat step to the next, each pixel
# takes one step or the other by this threshold, so the change is a pattern of whole pixels, never a blend (the user's
# "use dithering if you want to make gradients and light bands", 2026-11-21)
BAYER4 = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))


def dither_step(t, x, y, zone=0.5):
    """The whole step for a level `t` (0 .. n-1, any real) at (x, y): floor(t), or the next one where the dither says
    so. Only the middle `zone` of each step's span is dithered (the rest stays flat)."""
    k = math.floor(t)
    f = t - k
    f = min(1.0, max(0.0, (f - 0.5) / max(0.01, zone) + 0.5))
    return k + (1 if f > (BAYER4[y % 4][x % 4] + 0.5) / 16 else 0)


def bands(cv, top, bottom, y0, y1, n, clip=None):
    """Clean flat bands from `top` at y0 to `bottom` at y1 (and on down), one seam row of alternating pixels where two
    meet; only where `clip(x, y)` holds."""
    cols = [tuple(int(round(top[i] + (bottom[i] - top[i]) * k / (n - 1))) for i in range(3)) for k in range(n)]
    step = (y1 - y0) / (n - 1)
    edges = [int(round(y0 + step * (k + 0.5))) for k in range(n - 1)]
    for y in range(cv.h):
        k = sum(1 for e in edges if y >= e)
        for x in range(cv.w):
            if clip is not None and not clip(x, y):
                continue
            c = cols[k]
            if k + 1 < n and y == edges[k] - 1 and (x + y) % 2 == 0:
                c = cols[k + 1]
            cv.px[y][x] = c
    return cols


def pic_box(pic):
    ys = [y for y, row in enumerate(pic) if any(c is not None for c in row)]
    xs = [x for row in pic for x, c in enumerate(row) if c is not None]
    return min(xs), min(ys), max(xs), max(ys)


def put_pic(cv, pic, ox, oy, mask=None):
    """The picture with its top left at (ox, oy); `mask` collects the canvas pixels it covers."""
    for y, row in enumerate(pic):
        for x, c in enumerate(row):
            if c is not None:
                cv.put(ox + x, oy + y, c)
                if mask is not None and 0 <= ox + x < cv.w and 0 <= oy + y < cv.h:
                    mask.add((ox + x, oy + y))


def place_feet(cv, pic, fx, fy, mask=None, shadow=True):
    """The picture with its feet at (fx, fy) (game_thumbs.stand's way: a two-step shadow under them first)."""
    last, mid, span = G.bottom_of(pic)
    if shadow:
        rx, ry = max(6, span * 0.55), max(2.5, span * 0.11)
        for y in range(int(fy - ry) - 1, int(fy + ry) + 2):
            for x in range(int(fx - rx) - 1, int(fx + rx) + 2):
                d = ((x + 0.5 - fx) / rx) ** 2 + ((y + 0.5 - fy) / ry) ** 2
                if d <= 1:
                    cv.shade(x, y, 0.62 if d <= 0.45 else 0.8)
    ox, oy = fx - mid, fy - last
    put_pic(cv, pic, ox, oy, mask)
    return ox, oy


def rings(cv, mask, steps, tint, clip=None):
    """A glow in rings of flat colour round `mask` (a set of pixels): within steps[i][0] px it mixes steps[i][1]
    toward `tint`, never on the mask itself."""
    limit = max(r for r, _ in steps)
    dist = IL.distance_to(lambda x, y: (x, y) in mask, cv.w, cv.h, limit)
    for y in range(cv.h):
        for x in range(cv.w):
            d = dist[y][x]
            if d is None or d == 0 or (clip is not None and not clip(x, y)):
                continue
            for (r, k) in steps:
                if d <= r:
                    cv.put(x, y, mix(cv.get(x, y), tint, k))
                    break


def dither_glow(cv, mask, reach, ks, tint, zone=0.7):
    """A glow round `mask` out to `reach` px: its strength falls off in the steps `ks` (0 first, the strongest last,
    the share mixed toward `tint`) and passes from one step to the next in the ordered dither, never on the mask."""
    dist = IL.distance_to(lambda x, y: (x, y) in mask, cv.w, cv.h, reach)
    n = len(ks) - 1
    for y in range(cv.h):
        for x in range(cv.w):
            d = dist[y][x]
            if d is None or d == 0:
                continue
            lv = min(n, dither_step(min(float(n), max(0.0, (reach - d) / (reach / n))), x, y, zone))
            if lv > 0:
                cv.px[y][x] = mix(cv.px[y][x], tint, ks[lv])


def rays(cv, cx, cy, n, k_near, k_far, near, tint, clip, turn=0.1):
    """Rays fanning out from (cx, cy): every other wedge of `n` a flat step toward `tint`, stronger within `near` px."""
    step = 2 * math.pi / n
    for y in range(cv.h):
        for x in range(cv.w):
            if not clip(x, y):
                continue
            a = math.atan2(y + 0.5 - cy, x + 0.5 - cx) + math.pi + turn
            if int(a / step) % 2 == 0:
                d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
                cv.put(x, y, mix(cv.get(x, y), tint, k_near if d <= near else k_far))


def slant_bar(cv, xb, w, step, color=WHITE):
    """A slanted bar like the before-and-after's: `color`, its edges a darker step of it, a pixel left every `step`
    rows, a pixel or two of anti-aliasing graded along each step outside the edge."""
    edge = ink_of(color)
    for y in range(cv.h):
        d = xb - y // step
        cv.put(d - 1, y, edge)
        for x in range(d, d + w):
            cv.put(x, y, color)
        cv.put(d + w, y, edge)
    for y in range(cv.h):
        d, r = xb - y // step, y % step
        tl = {step - 2: 0.3, step - 1: 0.5}.get(r)
        tr = {0: 0.5, 1: 0.3}.get(r)
        if tl and cv.get(d - 2, y) is not None:
            cv.put(d - 2, y, mix(cv.get(d - 2, y), edge, tl))
        if tr and y >= step and cv.get(d + w + 1, y) is not None:
            cv.put(d + w + 1, y, mix(cv.get(d + w + 1, y), edge, tr))


def coin(cv, cx, cy, r, tilt=1.0, shade=None):
    """A gold coin as the game draws its coin icon, `r` px across the middle, `tilt` squashing it to an ellipse: the
    face lit from the top left in three steps, a raised rim, a lit crescent, a 1 px outline a darker step of the gold,
    anti-aliased where its stair steps."""
    gold = PAL["gold"]
    dark, light = shade or (globals()["dark"], globals()["light"])
    rx, ry = r, max(2.0, r * tilt)
    L = IL.Layer()
    # a tilted coin shows its edge under its face: a band of darker gold, lit at its left end
    thick = int(round(max(0.0, (1 - tilt) * r * 0.32)))
    for k in range(thick, 0, -1):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            u = (x + 0.5 - cx) / rx
            if abs(u) > 1:
                continue
            yb = cy + k + ry * math.sqrt(max(0.0, 1 - u * u))
            for y in range(int(cy + k - 1), int(yb) + 1):
                v = (y + 0.5 - cy - k) / ry
                if u * u + v * v <= 1:
                    L.put(x, y, dark(gold, 0.78) if u > -0.4 else dark(gold, 0.9))
    for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            u, v = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
            d = u * u + v * v
            if d > 1:
                continue
            lit = -(u + v) * 0.7
            if d > 0.62:
                c = light(gold, 0.35) if lit > 0.25 else (dark(gold, 0.8) if lit < -0.3 else gold)
            elif d > 0.5:
                c = dark(gold, 0.86)
            else:
                c = light(gold, 0.2) if lit > 0.2 else (dark(gold, 0.9) if lit < -0.25 else gold)
                # a crescent of light on the inner face
                if 0.18 < d < 0.36 and u < -0.1 and v < -0.1:
                    c = light(gold, 0.6)
            L.put(x, y, c)
    L.outline(eight=False)

    def cover(x, y):
        hit = 0
        for j in range(4):
            for i in range(4):
                for k in (0, thick):
                    u = (x + (i + 0.5) / 4 - cx) / (rx + 1)
                    v = (y + (j + 0.5) / 4 - cy - k) / (ry + 1)
                    if u * u + v * v <= 1:
                        hit += 1
                        break
        return hit / 16

    L.stamp(cv, cover=cover)
    cv.put(int(cx - rx * 0.35), int(cy - ry * 0.45), WHITE)


def big_islet(cx, ty, w, grass=None, rock=None, seed=1):
    """A floating island for a creature to stand on, as a Layer (its outline and anti-aliasing included), lit from the
    top left like the game's islands: an oval lawn with a lit rim at the back and a darker lip at the front, a band of
    earth under it, then the rock in three tiers stepping in (each lit on its left, in shade on its right, a seam a
    step darker between them) down to a point, cracks on it. Returns the layer and the lawn's
    middle (where feet go). (A vine down the earth read as a broken line at this size: none.)"""
    grass = grass or PAL["grass"]
    rock = rock or PAL["rock"]
    rnd = IL._rand(seed)
    L = IL.Layer()
    rx, ry = w / 2, max(4.0, w / 6.0)
    cy = ty + ry
    lip = max(3, int(w / 22))
    earth_h = max(3, int(w / 18))
    g_hi, g_mid, g_lo, g_lip = light(grass, 0.28), grass, dark(grass, 0.86), dark(grass, 0.72)
    earth, earth_lo = (150, 104, 74), (122, 82, 60)
    r_hi, r_mid, r_lo, r_dk = light(rock, 0.2), rock, dark(rock, 0.84), dark(rock, 0.72)

    def lawn_in(x, y, yy=0.0):
        return ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy - yy) / ry) ** 2 <= 1

    # the rock: tiers stepping in, each `th` rows, the last a point
    tiers = [(rx * 0.92, w * 0.16), (rx * 0.66, w * 0.15), (rx * 0.38, w * 0.15)]
    y = int(cy + lip + earth_h)
    rock_px = {}
    for k, (half, th) in enumerate(tiers):
        for j in range(int(th)):
            hw = half - (half - (tiers[k + 1][0] if k + 1 < len(tiers) else 1.5)) * (j / th) * 0.55
            if k == len(tiers) - 1:
                hw = half * (1 - j / th) + 0.6
            for x in range(int(round(cx - hw)), int(round(cx + hw)) + 1):
                t = (x + 0.5 - cx) / max(1.0, hw)
                c = r_hi if t < -0.45 else (r_mid if t < 0.25 else (r_lo if t < 0.7 else r_dk))
                if j == 0 and k > 0:
                    c = dark(c, 0.86)
                rock_px[(x, y)] = c
            y += 1
    for q, c in rock_px.items():
        L.put(q[0], q[1], c)
    # cracks: short dark strokes on the rock
    for _ in range(4):
        x0 = int(cx + (rnd() - 0.5) * rx * 1.1)
        y0 = int(cy + lip + earth_h + 3 + rnd() * w * 0.25)
        for d in range(int(2 + rnd() * 4)):
            q = (x0 + (d // 2) * (1 if rnd() < 0.5 else -1), y0 + d)
            if q in rock_px:
                L.put(q[0], q[1], dark(rock_px[q], 0.78))
    # the earth band and the lawn's front lip, then the lawn
    for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
        for yy in range(int(cy), int(cy + ry + lip + earth_h) + 2):
            if not lawn_in(x, yy - lip - earth_h) and not lawn_in(x, yy):
                pass
            below = any(lawn_in(x, yy - d) for d in range(0, lip + earth_h + 1))
            if below and not lawn_in(x, yy):
                depth = min(d for d in range(0, lip + earth_h + 1) if lawn_in(x, yy - d))
                L.put(x, yy, g_lip if depth <= lip else (earth if (x + yy) % 5 else earth_lo))
    for yy in range(int(ty) - 1, int(cy + ry) + 2):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            if lawn_in(x, yy):
                u, v = (x + 0.5 - cx) / rx, (yy + 0.5 - cy) / ry
                c = g_mid
                if not lawn_in(x, yy - 1) or not lawn_in(x, yy - 2):
                    c = g_hi
                elif v > 0.55:
                    c = g_lo
                elif u < -0.55 and v < 0.2:
                    c = light(g_mid, 0.12)
                L.put(x, yy, c)
    # tufts of lighter grass on the lawn
    for _ in range(int(w / 12)):
        x = int(cx + (rnd() - 0.5) * rx * 1.4)
        yy = int(cy + (rnd() - 0.5) * ry * 1.0)
        if lawn_in(x, yy) and lawn_in(x, yy - 1):
            L.put(x, yy, g_hi)
            L.put(x, yy - 1, light(g_hi, 0.2))
    L.outline(eight=False)
    return L, (int(cx), int(cy))


def fit_size(s, want, room):
    """The biggest title size up to `want` whose words fit `room` art px across."""
    from PIL import ImageFont

    size = want
    while size > 10:
        ft = ImageFont.truetype(G.TITLE_FONT, size)
        l, _, r, _ = ft.getbbox(s)
        if r - l + 6 <= room:
            return size
        size -= 1
    return size


def sparkles(cv, pts, c, free=None):
    for (x, y, arm) in pts:
        if 0 < x < cv.w and 0 < y < cv.h and (free is None or free(x, y)):
            G.sparkle_big(cv, x, y, arm, c)


# ---------------------------------------------------------------- shading passes over the game's own pictures
# (the rarity ladder's: the request of 2026-11-21, "detail the creatures much more, along with what you did with the
# previous thumbnail")
def _hsv(c):
    return colorsys.rgb_to_hsv(c[0] / 255, c[1] / 255, c[2] / 255)


def _rgb(h, s, v):
    return tuple(int(round(x * 255)) for x in colorsys.hsv_to_rgb(h % 1.0, min(1.0, max(0.0, s)), min(1.0, max(0.0, v))))


def materials(count):
    """A picture's colours grouped by material. The renderer draws a material's bands (lit, mid, shadow and the darker
    crevices) as one hue and saturation at several values, so colours sharing those are one material; the greys are
    one. `count` maps a colour to its pixels. Returns {colour: (material, its brightest value, the colour's rank among
    the material's values, 0 the brightest)}."""
    groups = []
    for c in sorted(count, key=lambda q: -count[q]):
        h, s, _ = _hsv(c)
        grey = s < 0.08
        for g in groups:
            if (g["grey"] and grey) or (not g["grey"] and not grey and abs(((h - g["h"] + 0.5) % 1.0) - 0.5) < 0.03 and abs(s - g["s"]) < 0.07):
                g["cs"].append(c)
                break
        else:
            groups.append({"h": h, "s": s, "grey": grey, "cs": [c]})
    out = {}
    for i, g in enumerate(groups):
        vs = sorted({round(_hsv(c)[2], 3) for c in g["cs"]}, reverse=True)
        for c in g["cs"]:
            out[c] = (i, vs[0], vs.index(round(_hsv(c)[2], 3)))
    return out


def hue_shade(c, vmax, strength=1.0, lift=0.2):
    """One band of a material shaded again with hue shifting: the lit band a touch warmer, each darker one turned
    toward blue violet (further the darker it is, about 25 degrees at most) and more saturated, a grey taking a violet
    tint, the shadows lifted a little toward the lit value so the colour carries them more than the darkness."""
    h, s, v = _hsv(c)
    k = v / max(0.01, vmax)
    if k > 0.93:
        if s < 0.08:
            return _rgb(HS_WARM, s + 0.05 * strength, v)
        d = ((HS_WARM - h + 0.5) % 1.0) - 0.5
        return _rgb(h + max(-0.015, min(0.015, d * 0.2)) * strength, s * (1 - 0.04 * strength), v)
    t = (1 - k) * strength
    if s < 0.08:
        h2, s2 = HS_COOL, s + 0.06 + t * 0.3
    else:
        d = ((HS_COOL - h + 0.5) % 1.0) - 0.5
        cap = 0.12 * t
        h2, s2 = h + max(-cap, min(cap, d * 0.9 * t)), s + t * 0.22
    return _rgb(h2, s2, v + (vmax - v) * lift * strength)


class Painted:
    """A picture painted over (`paint`): its pixels by place, the outline ring round them, and the whole shape."""

    def __init__(self, layer, body):
        self.layer, self.body = layer, body

    def moved(self, ox, oy):
        L = IL.Layer()
        L.px = {(x + ox, y + oy): c for (x, y), c in self.layer.px.items()}
        L.edge = {(x + ox, y + oy) for (x, y) in self.layer.edge}
        return Painted(L, {(x + ox, y + oy) for (x, y) in self.body})

    def mask(self):
        return set(self.layer.px)


def paint(pix, strength=1.0, dither=True, rim=0.32, bounce=None):
    """The game's own picture of something (`pix`: {(x, y): colour}, its 1 px ink ring included) painted over as an
    illustration under the standing rules: the ring taken off, every band of every material hue shifted
    (`hue_shade`), the step from one band to the next dithered where both are two pixels deep (the lighter reaching a
    pixel into the darker in a checker, the darker a quarter into the lighter: thin marks keep their shape), a rim of
    light just inside the edges that face the light (the top left) and a dithered row inside it, `bounce` (a colour)
    mixed into the bottom edge as light thrown up from what it stands on, then a new 1 px outline, each pixel a darker
    step of the colour it rings."""
    body = {q: c for q, c in pix.items() if all((q[0] + dx, q[1] + dy) in pix for dx, dy in IL.N4)}
    count = {}
    for c in body.values():
        count[c] = count.get(c, 0) + 1
    mat = materials(count)
    new = {q: hue_shade(c, mat[c][1], strength) for q, c in body.items()}
    out = dict(new)
    if dither:
        for (x, y), c in body.items():
            m, _, r = mat[c]
            for dx, dy in IL.N4:
                q = (x + dx, y + dy)
                c2 = body.get(q)
                if c2 is None or mat[c2][0] != m or mat[c2][2] != r + 1:
                    continue
                far = body.get((x + 2 * dx, y + 2 * dy))
                back = body.get((x - dx, y - dy))
                if far is not None and mat[far][0] == m and mat[far][2] == r + 1 and (q[0] + q[1]) % 2 == 0:
                    out[q] = new[(x, y)]
                if back is not None and mat[back][0] == m and mat[back][2] == r and BAYER4[y % 4][x % 4] < 4:
                    out[(x, y)] = new[q]

    def inside(x, y):
        return (x, y) in body

    for (x, y) in body:
        c = out[(x, y)]
        if not inside(x, y - 1) or not inside(x - 1, y):
            c = hs_light(c, rim)
        elif (not inside(x, y - 2) or not inside(x - 2, y)) and (x + y) % 2 == 0:
            c = hs_light(c, rim * 0.45)
        if bounce is not None and not inside(x, y + 1) and inside(x, y - 1):
            c = mix(c, bounce, 0.3)
        out[(x, y)] = c
    L = IL.Layer()
    for q, c in out.items():
        L.put(q[0], q[1], c)
    L.outline(eight=False)
    return Painted(L, set(body))


# ---------------------------------------------------------------- the driftlings as pixel illustrations
# (the request of 2026-11-21: "detail the creatures like you would a pixel art illustration instead of a 3d model,
# making them more accurate and detailed and polished and recognizable")
def parse_gbuf(path):
    """The ladder driftlings' picture data from the cast's log (gthumbs=cast: `@@GTHG` and `@@GTHS` lines): for each,
    its size, art px a stud, and per pixel its colour before shading, whether it glows, which way it faces in the view
    (right, up, toward the viewer), its depth in studs (None where nothing is) and its solid, with each solid's kind
    (e eye, g glow, b blended body)."""
    out = {}
    with open(path) as f:
        for line in f:
            if line.startswith("@@GTHG "):
                _, name, w, h, hx = line.split(" ", 4)
                W, H = int(w), int(h)
                hx = hx.strip()
                alb = [[None] * W for _ in range(H)]
                glow = [[False] * W for _ in range(H)]
                nrm = [[None] * W for _ in range(H)]
                dep = [[None] * W for _ in range(H)]
                ids = [[0] * W for _ in range(H)]
                for i in range(W * H):
                    q = hx[i * 26:(i + 1) * 26]
                    sid = int(q[22:26], 16)
                    if sid == 0:
                        continue
                    dq = int(q[14:22], 16)
                    y, x = divmod(i, W)
                    a = int(q[0:8], 16)
                    alb[y][x] = ((a >> 16) & 255, (a >> 8) & 255, a & 255)
                    glow[y][x] = bool(a & 0x1000000)
                    nrm[y][x] = tuple(int(q[8 + 2 * k:10 + 2 * k], 16) / 127.0 - 1 for k in range(3))
                    dep[y][x] = dq / 256.0
                    ids[y][x] = sid
                out.setdefault(name, {}).update(W=W, H=H, alb=alb, glow=glow, n=nrm, d=dep, id=ids)
            elif line.startswith("@@GTHS "):
                parts = line.split()
                kinds = {}
                for t in parts[3:]:
                    i, k = t.split(":")
                    kinds[int(i)] = k
                out.setdefault(parts[1], {}).update(scale=float(parts[2]), kinds=kinds)
    return out


def _norm(v):
    m = math.sqrt(sum(c * c for c in v)) or 1.0
    return tuple(c / m for c in v)


def paint_driftling(g, rim_tint=(214, 236, 255), bounce=(170, 226, 160)):
    """A driftling drawn again as a pixel illustration from what the game's picture engine knows of each pixel (its
    colour before shading, which way it faces, its depth, its part), the way a pixel artist would shade it rather than
    as a lit 3D model:
      * one light from the top left, in front: each material in a ramp of five hue-shifted steps (deep shade, shade,
        base, light, highlight; the shades toward violet and more saturated, the lights warmer), each part shaded as
        the round form it is, from its own facing;
      * the steps in clean clusters: a pixel alone in its step among neighbours that agree takes theirs, and the
        steps' borders smoothed, never across a material's edge; between base and its neighbours a pixel wide seam in
        the ordered dither where the form turns slowly;
      * shade where a part tucks under another (the depth round a pixel stepping toward the viewer: under the chin,
        between the legs, where the head meets the body) and where one part stands between another and the light
        (traced across the picture's depths), light thrown up from the lawn on what faces down, a rim of
        cool back light on the edges turned away, a glint where the light meets the form square on;
      * the eyes, the blush and what glows kept as painted;
      * a line where one part passes in front of another (the depth stepping more than a tenth of a stud), a darker
        step of the part behind, softer than the outline, so legs, arms, ears, mane and tail read on their own;
      * a 1 px outline round it all, each pixel a darker step of the colour it rings."""
    W, H = g["W"], g["H"]
    alb, glow, nrm, dep, ids = g["alb"], g["glow"], g["n"], g["d"], g["id"]
    kinds = g.get("kinds", {})
    scale = g.get("scale", 80.0)
    L = _norm((-0.5, 0.6, 0.64))
    Hh = _norm((L[0], L[1], L[2] + 1.0))
    Rb = _norm((0.75, -0.1, -0.65))
    inside = [[alb[y][x] is not None for x in range(W)] for y in range(H)]

    def at(x, y):
        return 0 <= x < W and 0 <= y < H and inside[y][x]

    painted = {}
    for y in range(H):
        for x in range(W):
            if not inside[y][x]:
                continue
            k = kinds.get(ids[y][x], "")
            if glow[y][x] or "e" in k:
                painted[(x, y)] = True
    # ambient occlusion: how much of the ring 3 and 6 px round a pixel stands nearer the viewer than it by a stretch
    near_k = 0.08 * 80.0 / scale  # (studs nearer that count: about a tenth of a stud)
    dirs = [(math.cos(a), math.sin(a)) for a in (i * math.pi / 4 for i in range(8))]
    ao = [[0.0] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            if not inside[y][x]:
                continue
            d0 = dep[y][x]
            occ = 0
            for r in (3, 6):
                for (cx, cy) in dirs:
                    qx, qy = int(round(x + cx * r)), int(round(y + cy * r))
                    if at(qx, qy) and dep[qy][qx] < d0 - near_k * (r / 3):
                        occ += 1
            ao[y][x] = occ / 16.0
    # cast shadows: from each pixel toward the light across the picture, a part standing nearer the viewer than the
    # light's ray (with a little give) shades it, so the head shades the chest and the mane the back
    hl = math.hypot(L[0], L[1])
    sx, sy = L[0] / hl, -L[1] / hl
    rise = (L[2] / hl) / scale
    bias = 0.06 * 80.0 / scale
    shadow = [[False] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            if not inside[y][x] or painted.get((x, y)):
                continue
            d0 = dep[y][x]
            for t in range(3, 48):
                qx, qy = int(round(x + sx * t)), int(round(y + sy * t))
                if not (0 <= qx < W and 0 <= qy < H):
                    break
                if inside[qy][qx] and dep[qy][qx] < d0 - t * rise - bias:
                    shadow[y][x] = True
                    break
    # each pixel's light: wrapped lambert, less where it is tucked in or in a cast shadow; its step, 0 deep ..
    # 4 highlight
    lv = [[None] * W for _ in range(H)]
    tval = [[0.0] * W for _ in range(H)]
    EDGES = (0.1, 0.3, 0.6, 0.86)
    for y in range(H):
        for x in range(W):
            if not inside[y][x]:
                continue
            n = nrm[y][x]
            d = n[0] * L[0] + n[1] * L[1] + n[2] * L[2]
            v = (d + 0.35) / 1.35
            v -= ao[y][x] * 0.55
            if shadow[y][x]:
                v = min(v, 0.26)
            spec = max(0.0, n[0] * Hh[0] + n[1] * Hh[1] + n[2] * Hh[2]) ** 28
            if spec > 0.6:
                v = max(v, 0.9)
            # (a continuous step for the dither: k + how far toward the next)
            k = sum(1 for e in EDGES if v >= e)
            lo = EDGES[k - 1] if k > 0 else EDGES[0] - 0.2
            hi = EDGES[k] if k < 4 else EDGES[3] + 0.2
            tval[y][x] = k + min(0.999, max(0.0, (v - lo) / (hi - lo))) - 0.5
            lv[y][x] = k
    # clean clusters: one pass of the commonest step round each pixel (same material only), then lone pixels go
    def same_mat(x, y, qx, qy):
        return at(qx, qy) and alb[qy][qx] == alb[y][x] and not painted.get((qx, qy))

    for _ in range(2):
        new = [row[:] for row in lv]
        for y in range(H):
            for x in range(W):
                if lv[y][x] is None or painted.get((x, y)):
                    continue
                cnt = {}
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        if same_mat(x, y, x + dx, y + dy):
                            k = lv[y + dy][x + dx]
                            cnt[k] = cnt.get(k, 0) + (2 if dx == 0 and dy == 0 else 1)
                best = max(cnt, key=lambda k: (cnt[k], k == lv[y][x]))
                if cnt[best] >= 6:
                    new[y][x] = best
        lv = new
    for y in range(H):
        for x in range(W):
            if lv[y][x] is None or painted.get((x, y)):
                continue
            nb = [lv[y + dy][x + dx] for dx, dy in IL.N4 if same_mat(x, y, x + dx, y + dy)]
            if len(nb) >= 3 and all(k == nb[0] for k in nb) and nb[0] != lv[y][x]:
                lv[y][x] = nb[0]
    # the dithered seam: where the continuous step sits right at a border, a checker of the two steps
    for y in range(H):
        for x in range(W):
            if lv[y][x] is None or painted.get((x, y)):
                continue
            t = tval[y][x]
            f = t - math.floor(t)
            if abs(f - 0.5) < 0.08 and lv[y][x] in (1, 2, 3) and (x + y) % 2 == 0:
                up = round(t) if round(t) != lv[y][x] else None
                if up is not None and 0 <= up <= 4:
                    lv[y][x] = up

    ramps = {}

    def ramp(c):
        r = ramps.get(c)
        if r is None:
            r = (hs_dark(c, 0.7), hs_dark(c, 0.85), c, hs_light(c, 0.2), hs_light(c, 0.5))
            ramps[c] = r
        return r

    col = {}
    for y in range(H):
        for x in range(W):
            if not inside[y][x]:
                continue
            c = alb[y][x]
            if painted.get((x, y)):
                col[(x, y)] = c
                continue
            r = ramp(c)
            c2 = r[lv[y][x]]
            n = nrm[y][x]
            # light thrown up from the lawn on what faces down, the cool back light on the edges turned away
            if n[1] < -0.35 and lv[y][x] <= 2:
                c2 = mix(c2, bounce, 0.16)
            edge = any(not at(x + dx * k, y + dy * k) for dx, dy in IL.N4 for k in (1, 2))
            if edge and (n[0] * Rb[0] + n[1] * Rb[1] + n[2] * Rb[2]) > 0.45 and lv[y][x] <= 1:
                c2 = mix(r[2], rim_tint, 0.25)
            col[(x, y)] = c2
    # the lines where one part passes in front of another: on the pixel behind, a softer darker step of it
    jump = 0.1 * 80.0 / scale * 1.4
    lines = {}
    for y in range(H):
        for x in range(W):
            if not inside[y][x] or painted.get((x, y)):
                continue
            d0 = dep[y][x]
            for dx, dy in IL.N4:
                qx, qy = x + dx, y + dy
                if at(qx, qy) and dep[qy][qx] < d0 - jump and (ids[qy][qx] != ids[y][x] or dep[qy][qx] < d0 - 2 * jump):
                    lines[(x, y)] = mix(ink_of(col[(x, y)]), col[(x, y)], 0.3)
                    break
    col.update(lines)
    Ly = IL.Layer()
    for q, c in col.items():
        Ly.put(q[0], q[1], c)
    body = set(col)
    Ly.outline(eight=False)
    # (the outline on the lit side, above and left of the shape, a lighter darker step: the pixel artist's selective
    # outline, so the light seems to wrap round the edge)
    for (x, y) in Ly.edge:
        inner = [col[q] for q in ((x + 1, y), (x, y + 1)) if q in col]
        if inner and (x - 1, y) not in col and (x, y - 1) not in col:
            Ly.px[(x, y)] = mix(Ly.px[(x, y)], inner[0], 0.35)
    return Painted(Ly, body)


def pic_pixels(pic):
    return {(x, y): c for y, row in enumerate(pic) for x, c in enumerate(row) if c is not None}


def feet_shadow(cv, fx, fy, rx, ry):
    """A shadow under feet on the lawn: two hue-shifted steps darker, passing from one to the next and out to the lawn
    in the ordered dither."""
    for y in range(int(fy - ry * 1.1) - 1, int(fy + ry * 1.1) + 2):
        for x in range(int(fx - rx * 1.1) - 1, int(fx + rx * 1.1) + 2):
            d = ((x + 0.5 - fx) / rx) ** 2 + ((y + 0.5 - fy) / ry) ** 2
            if d > 1.2 or cv.get(x, y) is None:
                continue
            lv = min(2, dither_step(min(2.0, max(0.0, (1.2 - d) / 0.55 * 2)), x, y, 0.7))
            if lv > 0:
                cv.px[y][x] = hs_dark(cv.px[y][x], (1.0, 0.86, 0.72)[lv])


def dither_bands(cv, top, bottom, y0, y1, n, clip=None, zone=0.6):
    """Flat bands from `top` at y0 to `bottom` at y1, each passing into the next in the ordered dither (the request of
    2026-11-21: "use dithering if you want to make gradients and light bands"); only where `clip(x, y)` holds."""
    cols = [tuple(int(round(top[i] + (bottom[i] - top[i]) * k / (n - 1))) for i in range(3)) for k in range(n)]
    for y in range(cv.h):
        t = min(n - 1.0, max(0.0, (y - y0) / max(1, y1 - y0) * (n - 1)))
        for x in range(cv.w):
            if clip is None or clip(x, y):
                cv.px[y][x] = cols[min(n - 1, dither_step(t, x, y, zone))]
    return cols


def dither_rays(cv, cx, cy, n, ks, reach, tint, clip, turn=0.1):
    """Rays fanning out from (cx, cy): every other wedge of `n` mixed toward `tint` by ks[level], the level falling off
    out to `reach` px and passing from one to the next in the ordered dither; a wedge's side a checker a pixel wide,
    so its straight edge never stairs."""
    step = 2 * math.pi / n
    top = len(ks) - 1
    for y in range(max(0, int(cy - reach)), min(cv.h, int(cy + reach) + 1)):
        for x in range(max(0, int(cx - reach)), min(cv.w, int(cx + reach) + 1)):
            if not clip(x, y):
                continue
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            d = math.hypot(dx, dy)
            if d > reach:
                continue
            a = (math.atan2(dy, dx) + math.pi + turn) / step
            i = math.floor(a)
            if i % 2:
                continue
            f = a - i
            if min(f, 1 - f) * step * d < 1.0 and (x + y) % 2:
                continue
            lv = min(top, dither_step(top * (1 - d / reach), x, y, 0.7))
            if lv > 0:
                cv.px[y][x] = mix(cv.px[y][x], tint, ks[lv])


def shadowed(cv, draw, reach=6, tone=None):
    """`draw()` (words drawn onto `cv`) with a soft shadow round what it drew: within 3 px a darker hue-shifted step of
    the picture under it, out to `reach` px a lighter one in a checker, then the words back over it. With `tone` (a
    colour, for a light sky) the shadow is that colour mixed in instead, two pixels solid and two in a checker, so it
    reads as the sky's own shade and not a grey box. Returns what `draw` returned."""
    before = [row[:] for row in cv.px]
    out = draw()
    W, H = cv.w, cv.h
    text = {(x, y) for y in range(H) for x in range(W) if cv.px[y][x] != before[y][x]}
    words = {q: cv.px[q[1]][q[0]] for q in text}
    for y in range(H):
        cv.px[y] = before[y][:]
    if tone is not None:
        reach = 4
    dist = IL.distance_to(lambda x, y: (x, y) in text, W, H, reach)
    for y in range(H):
        for x in range(W):
            d = dist[y][x]
            if d is None or d == 0 or d > reach:
                continue
            if tone is not None:
                if d <= 2:
                    cv.px[y][x] = mix(cv.px[y][x], tone, 0.42)
                elif (x + y) % 2 == 0:
                    cv.px[y][x] = mix(cv.px[y][x], tone, 0.24)
            elif d <= 3:
                cv.px[y][x] = hs_dark(cv.px[y][x], 0.62)
            elif (x + y) % 2 == 0 or d == 4:
                cv.px[y][x] = hs_dark(cv.px[y][x], 0.78)
    for (x, y), c in words.items():
        cv.px[y][x] = c
    return out


# ---------------------------------------------------------------- the rarity ladder
def islets(frame):
    """The pedestals (gthumbs=pedestal: three of the game's own floating islets in a row, left to right, on the
    stage's plain backdrop): each one's pixels and its lawn's middle (where the green of its top is, above its rock).
    The backdrop is a few flat colours a row (dithered where two bands meet) that the islets never reach the sides
    of, so a pixel is backdrop when its row's margins hold its colour."""
    W, H = frame.w, frame.h
    sky = G.Art(W, H)
    for y in range(H):
        cols = {frame.px[y][x] for x in list(range(0, 24)) + list(range(W - 24, W))}
        for x in range(W):
            c = frame.px[y][x]
            sky.px[y][x] = c if c in cols else (-1, -1, -1)
    m = IL.island_mask(frame, sky, min_part=400)
    seen = set()
    parts = []
    for y in range(H):
        for x in range(W):
            if not m[y][x] or (x, y) in seen:
                continue
            stack, part = [(x, y)], []
            seen.add((x, y))
            while stack:
                q = stack.pop()
                part.append(q)
                for dx, dy in IL.N8:
                    n = (q[0] + dx, q[1] + dy)
                    if 0 <= n[0] < W and 0 <= n[1] < H and m[n[1]][n[0]] and n not in seen:
                        seen.add(n)
                        stack.append(n)
            if len(part) > 2000:
                parts.append(part)
    out = []
    for part in sorted(parts, key=lambda pt: min(q[0] for q in pt)):
        y0 = min(q[1] for q in part)
        y1 = max(q[1] for q in part)
        lawn = [q for q in part if q[1] < y0 + (y1 - y0) * 0.4 and frame.px[q[1]][q[0]][1] > frame.px[q[1]][q[0]][0] + 25 and frame.px[q[1]][q[0]][1] > frame.px[q[1]][q[0]][2] + 10]
        lx = sum(q[0] for q in lawn) // len(lawn)
        ly = sum(q[1] for q in lawn) // len(lawn)
        out.append(({q: frame.px[q[1]][q[0]] for q in part}, (lx, ly)))
    return out


def thumb_rarity(pics, sc, gbuf=None):
    """Three panels split by slanted white bars, a common, a rare and an eternal driftling each standing on one of the
    game's own floating islets (gthumbs=pedestal: the unclaimed plot's islet, each a step bigger; the request of
    2026-11-21: "make the islands the creatures are sitting on more like the ingame islands"), each panel's sky
    grander than the last, the rarity's name over it and how much faster it works under it (Tuning.RarityWork) with a
    coin. Drawn on the 960 x 540 grid as a pixel illustration like the big number ("detail the creatures much more,
    along with what you did with the previous thumbnail"): the driftlings drawn at twice the pixels and shaded again
    by hand's rules from the picture engine's own data (`paint_driftling`, from `gbuf`: "detail the creatures like you
    would a pixel art illustration instead of a 3d model"; without it, `paint` over the cast's picture), the islets
    hue shifted and outlined again, every sky, ray and glow passing from step to step in the
    ordered dither, the words in hue-shifted bands dithered down their faces with a soft shadow round them, the
    eternal's in a rainbow a letter each, and the big coin by each number."""
    from PIL import ImageFont

    W, H = 960, 540
    cv = G.Art(W, H)
    B1, B2, BW, STEP = 360, 680, 10, 8

    def panel(x, y):
        if x < B1 - y // STEP:
            return 0
        if x < B2 - y // STEP:
            return 1
        return 2

    def mid(i, y):
        """The panel's middle at row y."""
        d = y // STEP
        return ((B1 - d) // 2, (B1 - d + BW + B2 - d) // 2, (B2 - d + BW + W) // 2)[i]

    # ---- the skies: clean bands in the ordered dither, the rarer the deeper
    skies = (((104, 160, 234), (204, 234, 252)), ((26, 120, 186), (156, 232, 226)), ((60, 30, 128), (246, 146, 206)))
    for i, (top, bottom) in enumerate(skies):
        dither_bands(cv, top, bottom, 0, H - 40, 10, clip=lambda x, y, i=i: panel(x, y) == i)
    rnd = IL._rand(23)
    # stars in the eternal's sky: single pixels and a few crosses, fewer further down
    for _ in range(260):
        x, y = int(rnd() * W), int(rnd() * H * 0.55)
        if panel(x, y) != 2 or rnd() < y / (H * 0.55):
            continue
        cv.put(x, y, mix(cv.get(x, y), (255, 240, 250), 0.45 + 0.5 * rnd()))
    for _ in range(14):
        x, y = int(rnd() * W), int(rnd() * H * 0.4)
        if panel(x - 2, y) == 2 and panel(x + 2, y) == 2:
            cv.put(x, y, (255, 246, 252))
            for dx, dy in IL.N4:
                cv.put(x + dx, y + dy, mix(cv.get(x + dx, y + dy), (255, 236, 250), 0.5))
    # far islets, flat and a step darker than the sky behind them
    for (fx, fy, fw, i) in ((56, 232, 30, 0), (290, 168, 20, 0), (402, 250, 26, 1), (622, 196, 18, 1), (728, 300, 22, 2), (928, 214, 20, 2)):
        if panel(fx, fy) == i:
            IL.far_islet(cv, fx, fy, fw, mix(cv.get(fx, fy), skies[i][0], 0.5))
    # rays behind the rare one and the eternal
    LY = (366, 358, 350)
    dither_rays(cv, mid(1, 250), 250, 14, (0.0, 0.05, 0.1, 0.16), 300, WHITE, lambda x, y: panel(x, y) == 1)
    dither_rays(cv, mid(2, 236), 236, 18, (0.0, 0.06, 0.12, 0.2, 0.28), 330, (255, 236, 252), lambda x, y: panel(x, y) == 2, turn=0.3)
    # the sea of clouds under them, in each sky's own colour, flat with a lit rim on each puff (the game's way)
    for i, (top, bottom) in enumerate(skies):
        back = mix(bottom, WHITE, 0.35)
        front = mix(bottom, WHITE, 0.62)
        IL.cloud_sea(cv, ((452, 22, back, mix(back, WHITE, 0.5)), (488, 26, front, mix(front, WHITE, 0.6))), seed=11 + i, clip=lambda x, y, i=i: panel(x, y) == i)
    # ---- the islets and the driftlings on them
    pedestals = islets(sc["pedestal"])
    rarities = (
        (1, "COMMON", PAL["text_dim"], "lad_1", None, None),
        (3, "RARE", light(PAL["button"], 0.15), "lad_2", (WHITE, 26, (0.0, 0.07, 0.14, 0.22)), None),
        (9, "ETERNAL", PAL["eternal"], "lad_3", ((255, 236, 252), 44, (0.0, 0.06, 0.12, 0.2, 0.3, 0.42)), True),
    )
    eternal = None
    for i, (r, name, col, key, glow_at, rainbow_words) in enumerate(rarities):
        pix, (lx, ly) = pedestals[i]
        cx, cy = mid(i, LY[i]), LY[i]
        isl = paint(pix, strength=0.7, dither=False, rim=0.2).moved(cx - lx, cy - ly)
        pic = pics[key]
        last, foot_mid, span = G.bottom_of(pic)
        if gbuf and key in gbuf:
            drift = paint_driftling(gbuf[key]).moved(cx - foot_mid, cy + 2 - last)
        else:
            drift = paint(pic_pixels(pic), bounce=(150, 226, 150)).moved(cx - foot_mid, cy + 2 - last)
        if glow_at is not None:
            tint, reach, ks = glow_at
            dither_glow(cv, drift.mask(), reach, ks, tint)
        isl.layer.stamp(cv)
        feet_shadow(cv, cx, cy + 2, max(14, span * 0.5), max(5, span * 0.12))
        drift.layer.stamp(cv)
        if i == 2:
            eternal = (cx, cy, drift)
    # ---- the eternal's sparkle: motes rising round it, twinkles
    ex, ey, drift = eternal
    m = drift.mask()
    ys = [q[1] for q in m]
    for _ in range(40):
        fx = int(ex + (rnd() - 0.5) * 230)
        fy = int(min(ys) + rnd() * (ey - min(ys)))
        if (fx, fy) not in m and panel(fx, fy) == 2:
            c = ((255, 240, 170), (255, 200, 236), (214, 255, 236))[int(rnd() * 3)]
            cv.put(fx, fy, c)
            cv.put(fx, fy + 1, mix(cv.get(fx, fy + 1), c, 0.5))
    sparkles(cv, ((ex - 118, 150, 7), (ex + 108, 196, 6), (ex + 84, 112, 4), (ex - 92, 262, 4), (ex + 126, 290, 3), (mid(1, 160) + 112, 170, 4), (mid(1, 240) - 120, 236, 3)),
             (255, 250, 230), free=lambda x, y: (x, y) not in m)
    # ---- the words: the rarity's name over each, how much faster it works under it with a coin
    for i, (r, name, col, key, glow_at, rainbow_words) in enumerate(rarities):
        room = (B1 - 40) if i == 0 else ((B2 - B1 - 40) if i == 1 else (W - B2 - 28))
        size = fit_size(name, 62, room)
        tone = hs_dark(skies[i][0], 0.7)
        shadowed(cv, lambda: G.title(cv, name, size, col, cx=mid(i, 50), top=22, depth=5, glint=i > 0, chars=rainbow_chars(name) if rainbow_words else None, dither=True, shade=HUE_SHADE), tone=tone)
        num = "x" + RARITY_WORK[r]
        nsize = (54, 62, 74)[i]
        l, _, rr, _ = ImageFont.truetype(G.TITLE_FONT, nsize).getbbox(num)
        nw = rr - l
        cr = (19, 22, 26)[i]
        ny = 522 - int(nsize * 0.74) - 5
        x0 = mid(i, ny + 30) - (nw + 2 * cr + 16) // 2
        box = shadowed(cv, lambda: G.title(cv, num, nsize, WHITE if i == 0 else col, x0=x0, top=ny, depth=5, glint=i > 0, chars=rainbow_chars(num) if rainbow_words else None, dither=True, shade=HUE_SHADE), tone=tone)
        big_coin(cv, box[2] + 16 + cr, (box[1] + box[3] - 7) // 2, cr)
    slant_bar(cv, B1, BW, STEP)
    slant_bar(cv, B2, BW, STEP)
    return cv


# ---------------------------------------------------------------- the close-up
def thumb_hero(pics):
    """One driftling's face filling the frame (the genre's big cute pet in the middle), rays fanning out behind its
    head, a glow round it, two more driftlings at the frame's edges looking in, clouds under them."""
    W, H = G.TW, G.TH
    cv = G.Art(W, H)
    bands(cv, (70, 158, 236), (176, 226, 252), 0, H, 10)
    hero = pics["hero_big"]
    x0, y0, x1, y1 = pic_box(hero)
    hw = x1 - x0 + 1
    # the head about a third down, the body running off the frame's foot
    hx, hy = W // 2 - (x0 + hw // 2), 22 - y0
    rays(cv, W // 2, hy + y0 + 70, 18, 0.16, 0.09, 150, WHITE, lambda x, y: True, turn=0.05)
    low = (176, 226, 252)
    back, mid, front = G.cloud_tones(low)
    IL.cloud_sea(cv, [(206, 18, back[0], back[1]), (226, 16, mid[0], mid[1])], seed=21)
    # the two at the edges, looking in, cut by the frame
    lf, rt = pics["hero_lf"], pics["hero_rt"]
    lx0, ly0, lx1, ly1 = pic_box(lf)
    rx0, ry0, rx1, ry1 = pic_box(rt)
    put_pic(cv, lf, -lx0 - 22, H - ly1 + 16 - 1)
    put_pic(cv, rt, W - rx1 + 20 - 1, H - ry1 + 12 - 1)
    IL.cloud_sea(cv, [(248, 14, front[0], front[1])], seed=22)
    mask = set()
    put_pic(cv, hero, hx, hy, mask)
    rings(cv, mask, ((3, 0.3), (7, 0.15), (12, 0.06)), (255, 252, 236))
    IL.rim_light(cv, lambda x, y: (x, y) in mask, 0.18)
    sparkles(cv, ((96, 40, 5), (388, 30, 4), (60, 160, 3), (424, 176, 3), (150, 18, 2), (330, 92, 2)), (255, 250, 230), free=lambda x, y: (x, y) not in mask)
    return cv


# ---------------------------------------------------------------- the egg and what hatched
def thumb_hatch(pics):
    """The rarest egg on its little island, a big curved arrow, the eternal that hatched from it with rays behind it,
    and one short line of words at the top."""
    W, H = G.TW, G.TH
    cv = G.Art(W, H)
    bands(cv, (64, 150, 232), (196, 232, 255), 0, H, 10)
    low = (196, 232, 255)
    px, py = 356, 140
    rays(cv, px, py, 16, 0.18, 0.1, 110, (255, 246, 214), lambda x, y: x > 236)
    back, mid, front = G.cloud_tones(low)
    IL.cloud_sea(cv, [(214, 16, back[0], back[1]), (234, 14, mid[0], mid[1])], seed=31)
    # the egg on a little island, glowing
    isl, (fx, fy) = big_islet(108, 168, 150, seed=6)
    isl.stamp(cv)
    egg = set()
    place_feet(cv, pics["hatch_egg"], fx, fy + 4, egg)
    rings(cv, egg, ((3, 0.28), (7, 0.14), (12, 0.06)), (255, 240, 255))
    # what hatched, floating, glowing
    pal = pics["hatch_pal"]
    x0, y0, x1, y1 = pic_box(pal)
    out = set()
    put_pic(cv, pal, px - (x0 + x1) // 2, py - (y0 + y1) // 2, out)
    rings(cv, out, ((3, 0.32), (7, 0.16), (12, 0.07)), (255, 248, 222))
    IL.rim_light(cv, lambda x, y: (x, y) in out, 0.2)
    IL.cloud_sea(cv, [(254, 12, front[0], front[1])], seed=32)
    G.arrow(cv, ((150, 112), (224, 48), (282, 104)), (64, 168, 255), r=4.6, head=20, half=10)
    sparkles(cv, ((300, 196, 4), (438, 72, 4), (420, 196, 3), (56, 130, 3), (176, 170, 2), (466, 132, 2)), (255, 250, 230), free=lambda x, y: (x, y) not in out and (x, y) not in egg)
    size = fit_size("HATCH RARE PETS", 34, W - 24)
    G.title(cv, "HATCH RARE PETS", size, PAL["accent"], cx=W // 2, top=8, depth=3)
    return cv


# ---------------------------------------------------------------- one rare among many
def star_mask(frame, near):
    """The eternal's pixels in the frame drawn with it alone on the meadow: everything round (cx, cy) that is not the
    meadow's green or its shadow's."""
    cx, cy, rx, ry = near
    out = set()
    for y in range(max(0, cy - ry), min(frame.h, cy + ry)):
        for x in range(max(0, cx - rx), min(frame.w, cx + rx)):
            c = frame.px[y][x]
            if c is None:
                continue
            green = c[1] > c[0] + 18 and c[1] > c[2] + 18
            if not green:
                out.add((x, y))
    # (the few strays a speck of the meadow leaves: keep the biggest connected part)
    seen, best = set(), set()
    for p in out:
        if p in seen:
            continue
        part, stack = set(), [p]
        seen.add(p)
        while stack:
            q = stack.pop()
            part.add(q)
            for dx, dy in IL.N8:
                n = (q[0] + dx, q[1] + dy)
                if n in out and n not in seen:
                    seen.add(n)
                    stack.append(n)
        if len(part) > len(best):
            best = part
    return best


def thumb_lucky(sc):
    """The meadow full of one common kind (gthumbs=field) with the eternal in the middle: rays fanning out from it
    over the crowd, a glow round it, sparkles, and its rarity's name in rainbow letters at the top."""
    cv = sc["field"]
    W, H = cv.w, cv.h
    mask = star_mask(sc["field_star"], (W // 2, H // 2, 110, 140))
    xs = [p[0] for p in mask]
    ys = [p[1] for p in mask]
    cx, cy = (min(xs) + max(xs)) // 2, (min(ys) + max(ys)) // 2
    # the crowd a step dimmer away from it (two flat rings), then rays fanning out from it
    for y in range(H):
        for x in range(W):
            d = math.hypot((x + 0.5 - cx) / 1.6, y + 0.5 - cy)
            if d > 250:
                cv.shade(x, y, 0.86)
            elif d > 180:
                cv.shade(x, y, 0.93)
    rays(cv, cx, cy, 20, 0.2, 0.08, 240, (255, 246, 200), lambda x, y: (x, y) not in mask, turn=0.2)
    rings(cv, mask, ((3, 0.42), (8, 0.26), (14, 0.14), (22, 0.07)), (255, 248, 214))
    IL.rim_light(cv, lambda x, y: (x, y) in mask, 0.22)
    sparkles(cv, ((cx - 70, cy - 60, 8), (cx + 76, cy - 30, 6), (cx + 52, cy + 64, 4), (cx - 84, cy + 40, 5), (cx - 30, cy - 100, 4), (cx + 30, cy - 96, 3)), (255, 250, 226), free=lambda x, y: (x, y) not in mask)
    G.title(cv, "ETERNAL", 112, PAL["eternal"], cx=W // 2, top=16, depth=7, chars=rainbow_chars("ETERNAL"))
    return cv


# ---------------------------------------------------------------- the big number
def big_coin(cv, cx, cy, r):
    """The big coin by the number, drawn as a pixel illustration: the coin (`coin`), then a ridged rim (every few
    pixels round its edge a step darker), a raised star in the middle a step lighter with its own darker edge on its
    lower right, a diagonal glint across its face, and a warm glow round it, dithered from step to step (the request
    of 2026-11-21: "dither the glow here as well")."""
    gold = PAL["gold"]
    disc = {(x, y) for y in range(int(cy - r) - 1, int(cy + r) + 2) for x in range(int(cx - r) - 1, int(cx + r) + 2)
            if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r}
    dark, light = HUE_SHADE
    dither_glow(cv, disc, 14, (0.0, 0.07, 0.14, 0.24), (255, 226, 140))
    coin(cv, cx, cy, r, shade=HUE_SHADE)
    # the ridges round the rim
    for (x, y) in disc:
        d = math.hypot(x + 0.5 - cx, y + 0.5 - cy) / r
        if 0.84 < d <= 0.97:
            a = math.atan2(y + 0.5 - cy, x + 0.5 - cx)
            if int((a + math.pi) / (2 * math.pi) * 44) % 2 == 0:
                cv.put(x, y, dark(cv.get(x, y), 0.88))
    # a raised star in the middle
    R1, R2 = r * 0.42, r * 0.18

    def in_star(px, py):
        a = math.atan2(py - cy, px - cx) + math.pi / 2
        k = (a % (2 * math.pi / 5)) / (2 * math.pi / 5)
        rr = R2 + (R1 - R2) * abs(1 - 2 * k) ** 1.6
        return math.hypot(px - cx, py - cy) <= rr

    star = {(x, y) for (x, y) in disc if in_star(x + 0.5, y + 0.5)}
    for (x, y) in star:
        c = light(gold, 0.42)
        if (x + 1, y) not in star or (x, y + 1) not in star:
            c = dark(gold, 0.74)
        elif (x - 1, y) not in star or (x, y - 1) not in star:
            c = light(gold, 0.7)
        cv.put(x, y, c)
    # a glint across the face, top left to the middle
    for k in range(int(r * 0.5)):
        x, y = int(cx - r * 0.62 + k * 0.7), int(cy - r * 0.2 - k * 0.7)
        if (x, y) in disc and (x, y) not in star:
            cv.put(x, y, light(gold, 0.75))


def thumb_rich(sc, rate):
    """The tier 20 town (gthumbs=day100:20:tree) centred on the Tree of Life at night (the request of 2026-11-21:
    "center it in the middle, with the tree being the centerpiece, and use a night skybox"), drawn as a pixel
    illustration (then "remove the coins falling down, center the giant coin to the text. then, treat it as a pixel art
    illustration and detail and give it even more flair to be as appealing as possible", and "use the clouds as
    before. also, use dithering if you want to make gradients and light bands"): the night sky painted again in the
    game's own colours, a big moon with craters and rings of light in the open sky at the right, stars of a few sizes,
    the milky way, a shooting star and far islets, the game's own sea of clouds under them; the island cut from its sky
    with a whole outline and a rim of moonlight on its top right edge (the moon's side), dimmer and bluer in steps
    away from the tree; the tree lit as the island's light (a warm glow, a rim of light, motes rising off it,
    fireflies); every gradient and band of light passing from one step to the next in a 4 x 4 ordered dither; and what
    the island makes a minute (`rate`, the game's own count) centred over it in rainbow letters, a soft shadow round
    them, the big coin centred on them."""
    frame, sky, treef = sc["rich"], sc["rich_sky"], sc["rich_tree"]
    m = IL.island_mask(frame, sky)
    tm = IL.island_mask(treef, sky, near=24)
    IL.outline_edges(frame, m)
    W, H = frame.w, frame.h
    cv = G.Art(W, H)
    rnd = IL._rand(61)
    # ---- the night sky, painted again in clean bands of the game's own colours
    cols = range(0, W, 5)
    top = IL.row_colour(sky, 1, cols)
    low = IL.row_colour(sky, int(H * 0.66), cols)
    NB, Y1 = 9, int(H * 0.74)
    steps = [tuple(int(round(top[i] + (low[i] - top[i]) * k / (NB - 1))) for i in range(3)) for k in range(NB)]
    for y in range(H):
        for x in range(W):
            t = min(NB - 1.0, max(0.0, y / Y1 * (NB - 1)))
            cv.px[y][x] = steps[min(NB - 1, dither_step(t, x, y, 0.6))]

    # the milky way: a soft band from the lower left up to the top right, two steps lighter at its heart, dithered
    # where it fades, dense with stars
    def band(x, y):
        return abs((y - (300 - x * 0.42)) / 46.0) + 0.35 * math.sin(x * 0.031) * math.cos(y * 0.05)

    glow_mw = (0.0, 0.07, 0.15)
    for y in range(H):
        for x in range(W):
            lv = min(2, dither_step(min(2.0, max(0.0, (1.25 - band(x, y)) / 0.38)), x, y, 0.8))
            if lv > 0:
                cv.px[y][x] = mix(cv.px[y][x], (150, 150, 220), glow_mw[lv])
    # stars: many single pixels (denser in the milky way), some crosses, a few big twinkles
    for _ in range(900):
        x, y = int(rnd() * W), int(rnd() * H * 0.78)
        if band(x, y) > 1.0 and rnd() < 0.55:
            continue
        c = ((236, 240, 255), (255, 244, 214), (200, 214, 255))[int(rnd() * 3)]
        cv.put(x, y, mix(cv.get(x, y), c, 0.55 + 0.45 * rnd()))
    for _ in range(46):
        x, y = int(rnd() * W), int(rnd() * H * 0.7)
        c = ((236, 240, 255), (255, 240, 200))[int(rnd() * 2)]
        cv.put(x, y, c)
        for dx, dy in IL.N4:
            cv.put(x + dx, y + dy, mix(cv.get(x + dx, y + dy), c, 0.45))
    # the moon in the open sky at the right: a disc lit from its top right, craters a step darker with a lit lip, two
    # rings of light round it
    MX, MY, MR = 904, 204, 21
    for y in range(MY - MR - 16, MY + MR + 17):
        for x in range(MX - MR - 16, MX + MR + 17):
            d = math.hypot(x + 0.5 - MX, y + 0.5 - MY)
            base = cv.get(x, y)
            if base is None:
                continue
            if d <= MR:
                lit = (-(x + 0.5 - MX) + (y + 0.5 - MY)) / MR
                c = (255, 248, 222) if lit < 0.35 else ((236, 228, 200) if lit < 0.95 else hs_dark((236, 228, 200), 0.88))
                cv.put(x, y, c)
            else:
                lv = min(2, dither_step(min(2.0, max(0.0, (MR + 15 - d) / 6.0)), x, y, 0.9))
                if lv > 0:
                    cv.put(x, y, mix(base, (255, 248, 222), (0.0, 0.12, 0.3)[lv]))
    for (ox, oy, cr) in ((-8, -6, 5), (7, 4, 6), (-3, 11, 3), (10, -10, 3), (-12, 6, 2)):
        for y in range(MY + oy - cr - 1, MY + oy + cr + 2):
            for x in range(MX + ox - cr - 1, MX + ox + cr + 2):
                d = math.hypot(x + 0.5 - MX - ox, y + 0.5 - MY - oy)
                if d <= cr and math.hypot(x + 0.5 - MX, y + 0.5 - MY) <= MR - 1:
                    up = (y + 0.5 - MY - oy) < -cr * 0.4 and (x + 0.5 - MX - ox) > 0
                    cv.put(x, y, hs_dark((236, 228, 200), 0.86) if not up else hs_dark((236, 228, 200), 0.76))
                elif cr < d <= cr + 1 and (y + 0.5 - MY - oy) > 0 and math.hypot(x + 0.5 - MX, y + 0.5 - MY) <= MR - 1:
                    cv.put(x, y, (255, 250, 232))
    # a shooting star across the top left corner: a bright head, its trail fading in three flat steps
    sx, sy = 16, 210
    for k in range(56):
        x, y = sx + k, int(sy - k * 0.42)
        t = k / 70
        c = WHITE if k < 3 else mix(cv.get(x, y), (230, 236, 255), 0.75 if t < 0.25 else (0.45 if t < 0.55 else 0.2))
        cv.put(x, y, c)
        if k < 22:
            cv.put(x, y + 1, mix(cv.get(x, y + 1), (230, 236, 255), 0.3))
    # far islets, flat and a step darker than the sky behind
    for (fx, fy, fw) in ((150, 252, 20), (812, 250, 16), (28, 318, 14), (936, 330, 12)):
        IL.far_islet(cv, fx, fy, fw, mix(cv.get(fx, fy), (20, 22, 60), 0.35))
    # the sea of clouds as the game paints it (UI/SkyBackdrop's own, copied from its capture: each column from where
    # its first cloud pixel is, the purple of the clouds against the navy of the sky)
    for x in range(W):
        y0 = None
        for y in range(int(H * 0.55), H):
            c = sky.px[y][x]
            if c is not None and c[0] > 70 and c[0] > c[1] + 10:
                y0 = y
                break
        if y0 is not None:
            for y in range(y0, H):
                cv.px[y][x] = sky.px[y][x]
    # ---- the island, cut out and outlined, with a rim of moonlight on its top right edge (the moon's side): each
    # island pixel just inside the outline where the outline faces up or right, a step lighter and cooler
    IL.lay_island(cv, frame, m)

    def isl(x, y):
        return 0 <= x < W and 0 <= y < H and m[y][x]

    lit = []
    for y in range(H):
        for x in range(W):
            if not isl(x, y) or not all(isl(x + dx, y + dy) for dx, dy in IL.N4):
                continue
            if any((not isl(x + dx, y + dy - 1)) or (not isl(x + dx + 1, y + dy)) for dx, dy in ((0, 0), (0, -1), (1, 0))) and (not isl(x, y - 2) or not isl(x + 2, y)):
                lit.append((x, y))
    for (x, y) in lit:
        cv.px[y][x] = mix(light(cv.px[y][x], 0.28), (214, 224, 255), 0.18)
    tree = {(x, y) for y in range(H) for x in range(W) if tm[y][x]}
    xs = [p[0] for p in tree]
    ys = [p[1] for p in tree]
    tx, ty = (min(xs) + max(xs)) // 2, (min(ys) + max(ys)) // 2
    crown = min(ys)
    # the night on the island: flat steps dimmer and bluer in rings away from the tree
    night = (40, 46, 96)
    for y in range(H):
        for x in range(W):
            if not m[y][x] or (x, y) in tree:
                continue
            d = math.hypot((x + 0.5 - tx) / 1.7, y + 0.5 - ty)
            c = cv.px[y][x]
            lv = min(3, dither_step(min(3.0, max(0.0, (d - 100) / 62.0)), x, y, 0.45))
            if lv == 3:
                cv.px[y][x] = mix(hs_dark(c, 0.74), night, 0.24)
            elif lv == 2:
                cv.px[y][x] = mix(hs_dark(c, 0.82), night, 0.14)
            elif lv == 1:
                cv.px[y][x] = mix(hs_dark(c, 0.91), night, 0.05)
    # the tree lit: a warm glow, a rim of light
    dither_glow(cv, tree, 34, (0.0, 0.06, 0.13, 0.22, 0.34), (255, 236, 176))
    for y in range(H):
        for x in range(W):
            if (x, y) in tree and ((x - 1, y) not in tree or (x, y - 1) not in tree) and (x + 1, y) in tree and (x, y + 1) in tree:
                cv.px[y][x] = hs_light(cv.px[y][x], 0.22)
    # motes rising off the crown (two pixels each, a dimmer one under), fireflies round it
    for _ in range(34):
        fx = int(tx + (rnd() - 0.5) * 170)
        fy = int(crown - 6 - rnd() * 70)
        c = ((255, 240, 170), (255, 196, 226), (210, 255, 220))[int(rnd() * 3)]
        if (fx, fy) not in tree:
            cv.put(fx, fy, c)
            cv.put(fx, fy + 1, mix(cv.get(fx, fy + 1), c, 0.5))
    for _ in range(30):
        fx = int(tx + (rnd() - 0.5) * 320)
        fy = int(ty + (rnd() - 0.5) * 180)
        if 0 < fx < W - 1 and 0 < fy < H - 1 and (fx, fy) not in tree:
            cv.put(fx, fy, (255, 246, 190))
            cv.put(fx + 1, fy, mix(cv.get(fx + 1, fy), (255, 230, 150), 0.5))
    sparkles(cv, ((tx - 74, crown + 8, 5), (tx + 80, crown + 30, 4), (tx - 40, crown - 30, 3), (tx + 46, crown - 46, 4)), (255, 246, 214), free=lambda x, y: (x, y) not in tree)
    # ---- the number, centred, a soft shadow round it, the big coin centred on it
    from PIL import ImageFont

    num = "{:,}".format(int(rate))
    NS, MS, CR, TOP = 100, 54, 38, 20
    l, _, r, _ = ImageFont.truetype(G.TITLE_FONT, NS).getbbox(num)
    lm, _, rm, _ = ImageFont.truetype(G.TITLE_FONT, MS).getbbox("/min")
    total = 2 * CR + 16 + (r - l) + 10 + (rm - lm)
    x0 = (W - total) // 2
    before = [row[:] for row in cv.px]
    box = G.title(cv, num, NS, PAL["gold"], x0=x0 + 2 * CR + 16, top=TOP, depth=7, chars=rainbow_chars(num), dither=True, shade=HUE_SHADE)
    mbox = G.title(cv, "/min", MS, WHITE, x0=box[2] + 10, top=TOP + NS - MS - 4, depth=4, glint=False, dither=True, shade=HUE_SHADE)
    text = {(x, y) for y in range(H) for x in range(W) if cv.px[y][x] != before[y][x]}
    # (the shadow goes under the words: darken round them on the picture as it was, then put the words back)
    words = {q: cv.px[q[1]][q[0]] for q in text}
    for y in range(H):
        cv.px[y] = before[y][:]
    dist = IL.distance_to(lambda x, y: (x, y) in text, W, H, 6)
    for y in range(H):
        for x in range(W):
            d = dist[y][x]
            if d is not None and 0 < d <= 6:
                if d <= 3:
                    cv.px[y][x] = hs_dark(cv.px[y][x], 0.62)
                elif (x + y) % 2 == 0 or d == 4:
                    cv.px[y][x] = hs_dark(cv.px[y][x], 0.78)
    for (x, y), c in words.items():
        cv.px[y][x] = c
    # the coin centred on the number's face (its middle row between the words' top and the foot of their face)
    face_mid = (box[1] + box[3] - 7) // 2
    big_coin(cv, x0 + CR, face_mid, CR)
    sparkles(cv, ((x0 - 14, TOP + 8, 6), (mbox[2] + 14, TOP + 30, 5), (box[0] + 260, TOP - 2, 4), (box[2] - 120, box[3] + 12, 4), (x0 + 2 * CR + 6, box[3] + 4, 3)), (255, 250, 226))
    return cv
