#!/usr/bin/env python3
# The thumbnails after the genre's own (the request of 2026-11-21: "do more thumbnail research, and replicate popular
# game thumbnails with the same genre type"). What the research found (GAME_DESIGN 11.1): the most played and most
# liked pet, hatching, tycoon and island games on Roblox reuse a few frames, and these take five of them with this
# game's own driftlings, eggs and islands, drawn as pixel illustrations under the standing rules (one art grid a
# picture, 1 px outlines a darker step of what they ring, anti-aliasing where they step, nothing scaled):
#   * thumb_rarity: the rarity ladder (three panels split by slanted bars, the same kind of creature grander in each,
#     its rarity's name over it and a bigger number under it);
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


# ---------------------------------------------------------------- the rarity ladder
def thumb_rarity(pics):
    """Three panels split by slanted white bars, a common, a rare and an eternal driftling each on a little floating
    island, each panel's sky grander than the last, the rarity's name over it in its colour and how much faster it
    works under it (Tuning.RarityWork), with a coin."""
    W, H = G.TW, G.TH
    cv = G.Art(W, H)
    B1, B2, BW, STEP = 180, 340, 6, 8

    def panel(x, y):
        if x < B1 - y // STEP:
            return 0
        if x < B2 - y // STEP:
            return 1
        return 2

    skies = (((122, 180, 238), (198, 230, 252)), ((40, 150, 196), (150, 228, 226)), ((84, 50, 146), (240, 136, 204)))
    for i, (top, bottom) in enumerate(skies):
        bands(cv, top, bottom, 0, H, 9, clip=lambda x, y, i=i: panel(x, y) == i)
    rarities = ((1, "COMMON", PAL["text_dim"], "lad_1", 96, None), (3, "RARE", light(PAL["button"], 0.15), "lad_2", 106, None), (9, "ETERNAL", PAL["eternal"], "lad_3", 118, rainbow))
    # the panels' middles at the creature's height and at the words'
    mids = ((B1 - 17) // 2, (B1 + B2) // 2 - 17, (B2 - 17 + W) // 2)
    tops = ((B1 - 2) // 2, (B1 + B2) // 2, (B2 + W) // 2 + 2)
    # rays in the rare panel and the eternal one, sparkles round the eternal
    rays(cv, mids[1], 120, 12, 0.14, 0.08, 70, WHITE, lambda x, y: panel(x, y) == 1)
    rays(cv, mids[2], 118, 16, 0.2, 0.12, 80, (255, 236, 252), lambda x, y: panel(x, y) == 2, turn=0.3)
    for i, (r, name, col, key, iw, hue) in enumerate(rarities):
        cx = mids[i]
        ty = 132 - i * 4
        isl, (fx, fy) = big_islet(cx, ty, iw, seed=3 + i)
        isl.stamp(cv)
        mask = set()
        place_feet(cv, pics[key], fx, fy + 2, mask)
        if i == 2:
            rings(cv, mask, ((2, 0.3), (5, 0.16), (9, 0.07)), (255, 244, 255), clip=lambda x, y: panel(x, y) == 2)
            IL.rim_light(cv, lambda x, y: (x, y) in mask, 0.2)
        # the name over it
        room = (B1 - 24) if i == 0 else ((B2 - B1 - 20) if i == 1 else (W - B2 - 12))
        size = fit_size(name, 30, room)
        G.title(cv, name, size, col, cx=tops[i], top=10, depth=3, glint=i > 0, chars=rainbow_chars(name) if hue else None)
        # how much faster it works, under it, with a coin
        num = "x" + RARITY_WORK[r]
        nsize = (26, 30, 36)[i]
        from PIL import ImageFont

        ft = ImageFont.truetype(G.TITLE_FONT, nsize)
        l, _, rr, _ = ft.getbbox(num)
        nw = rr - l
        cr = (8, 9, 11)[i]
        x0 = cx - (nw + 2 * cr + 5) // 2
        ny = (190, 186, 182)[i]
        G.title(cv, num, nsize, WHITE if i == 0 else col, x0=x0, top=ny, depth=3, glint=i > 0, chars=rainbow_chars(num) if hue else None)
        coin(cv, x0 + nw + cr + 6, ny + nsize // 2 + 2, cr)
    sparkles(cv, ((mids[2] - 58, 70, 4), (mids[2] + 54, 96, 3), (mids[2] + 40, 54, 2), (mids[2] - 44, 128, 2), (mids[1] + 52, 80, 2)), (255, 250, 230))
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
