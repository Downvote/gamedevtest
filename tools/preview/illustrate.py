#!/usr/bin/env python3
# Pixel illustration helpers for the game's thumbnails and icon (tools/preview/game_thumbs.py). The request of
# 2026-11-21 on the before-and-after thumbnail: "polish and detail it as if it is a pixel art illustration, with the
# pixel art rules i gave you" (the standing rule: "for pixel art, always dont use mixels. use pixel art techniques
# such as anti-aliasing, avoiding jaggies, and avoiding mixels, and use a 1 pixel outline. respect the pixel art
# grid"), and the icon's: "make an icon, with the island being the centerpiece".
#
# The islands stay the game's own pictures. What these add around them, every pixel on the art grid:
#   * island_mask: which pixels of a frame are the island, from the same frame captured with the world's layer hidden
#     (the sky alone); specks smaller than a few pixels (a drifting leaf, a far bird) are left out.
#   * outline_edges: a 1 px outline round the island against the sky, a darker step of the colour beside it, only
#     where the game has not drawn one already (never two pixels thick).
#   * a painted sky: clean bands with no dither across them (one seam row of alternating pixels where two meet), the
#     sun with two rings of light round it, far islets as flat silhouettes and a sea of clouds in flat colours with a
#     lit rim on each puff, no outlines (the game's sky keeps its own colours: UI/SkyBackdrop).
#   * Layer: a shape drawn on its own, then given its 1 px outline (each pixel a darker step of the colour it rings)
#     and anti-aliasing where the outline's stairs step (a pixel between the outline and what lies behind, only where
#     the ideal edge cuts through it), then stamped down.
#   * mini_islet: a small floating rock with a lawn on top, lit from the top left, for depth round the islands.
#   * bird: a gull far off, two strokes, no outline.
import math

from product_icons import WHITE, mix, dark, light, ink_of, lum, pick_beside

N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
N8 = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1))


# ---------------------------------------------------------------- the island, from the two captures
def island_mask(frame, sky, min_part=40, max_hole=6, near=None):
    """True where the frame differs from the sky-only frame: the island. Parts of fewer than `min_part` pixels (8-way
    connected: leaves on the wind, a far bird) are dropped, and holes of at most `max_hole` pixels inside it (an
    island pixel that happens to match the sky behind) filled; bigger enclosed patches are sky seen through it. With
    `near`, only the biggest part and the parts within `near` px of its box stay (gulls flying past go)."""
    W, H = frame.w, frame.h
    m = [[frame.px[y][x] != sky.px[y][x] for x in range(W)] for y in range(H)]

    def parts(want):
        seen = [[False] * W for _ in range(H)]
        for y in range(H):
            for x in range(W):
                if m[y][x] != want or seen[y][x]:
                    continue
                stack, part, edge = [(x, y)], [], False
                seen[y][x] = True
                while stack:
                    cx, cy = stack.pop()
                    part.append((cx, cy))
                    if cx in (0, W - 1) or cy in (0, H - 1):
                        edge = True
                    for dx, dy in (N8 if want else N4):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < W and 0 <= ny < H and m[ny][nx] == want and not seen[ny][nx]:
                            seen[ny][nx] = True
                            stack.append((nx, ny))
                yield part, edge

    kept = []
    for part, _ in list(parts(True)):
        if len(part) < min_part:
            for (x, y) in part:
                m[y][x] = False
        else:
            kept.append(part)
    if near is not None and kept:
        def box(part):
            xs = [q[0] for q in part]
            ys = [q[1] for q in part]
            return min(xs), min(ys), max(xs), max(ys)

        big = box(max(kept, key=len))
        for part in kept:
            b = box(part)
            if b[0] > big[2] + near or b[2] < big[0] - near or b[1] > big[3] + near or b[3] < big[1] - near:
                for (x, y) in part:
                    m[y][x] = False
    for part, edge in list(parts(False)):
        if not edge and len(part) <= max_hole:
            for (x, y) in part:
                m[y][x] = True
    return m


def mask_box(m):
    ys = [y for y, row in enumerate(m) if any(row)]
    xs = [x for x in range(len(m[0])) if any(m[y][x] for y in range(len(m)))]
    return (min(xs), min(ys), max(xs) + 1, max(ys) + 1) if xs and ys else None


def outline_edges(art, m, keep=0.8):
    """A 1 px outline round the island against the sky: each edge pixel the game left lighter than `keep` of the pixel
    inside it becomes a darker step of that inner pixel (Render/Shading.inkOf's mix). Where the game's own outline is
    there already, it stays as it is. Returns how many pixels changed."""
    W, H = art.w, art.h
    src = [row[:] for row in art.px]
    n = 0
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            if not m[y][x]:
                continue
            for dx, dy in N4:
                if m[y + dy][x + dx]:
                    continue
                ix, iy = x - dx, y - dy
                if m[iy][ix]:
                    b, i = src[y][x], src[iy][ix]
                    if b is not None and i is not None and lum(b) >= keep * lum(i):
                        art.px[y][x] = ink_of(i)
                        n += 1
                break
    return n


def lay_island(cv, frame, m, ox=0, oy=0, clip=None):
    """The island's pixels from `frame` onto `cv`, moved by (ox, oy); `clip(x, y)` may refuse a pixel."""
    for y, row in enumerate(m):
        for x, on in enumerate(row):
            if on and (clip is None or clip(x + ox, y + oy)):
                cv.put(x + ox, y + oy, frame.px[y][x])


# ---------------------------------------------------------------- the sky
def row_colour(ref, y, xs):
    cs = [ref.px[y][x] for x in xs if ref.px[y][x] is not None]
    return tuple(sum(c[i] for c in cs) / len(cs) for i in range(3))


def paint_sky(cv, top, bottom, y0, y1, bands=9, seam=True):
    """Bands from `top` (at y0) to `bottom` (at y1) and on down to the canvas's foot, each a clean flat colour; one
    seam row of alternating pixels where two bands meet."""
    cols = [tuple(int(round(top[i] + (bottom[i] - top[i]) * k / (bands - 1))) for i in range(3)) for k in range(bands)]
    step = (y1 - y0) / (bands - 1)
    edges = [int(round(y0 + step * (k + 0.5))) for k in range(bands - 1)]
    for y in range(cv.h):
        k = sum(1 for e in edges if y >= e)
        for x in range(cv.w):
            c = cols[k]
            if seam and k + 1 < bands and y == edges[k] - 1 and (x + y) % 2 == 0:
                c = cols[k + 1]
            cv.px[y][x] = c
    return cols


def sky_at(cv, x, y):
    return cv.get(x, y) or (150, 200, 240)


def sun(cv, cx, cy, r, core=(255, 248, 222)):
    """The sun: a disc a touch lighter at its top left, two rings of light round it in the sky's own colours, no
    outline."""
    for y in range(cy - r - 12, cy + r + 13):
        for x in range(cx - r - 12, cx + r + 13):
            d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
            base = sky_at(cv, x, y)
            if d <= r:
                c = core
                if math.hypot(x + 0.5 - (cx - r * 0.3), y + 0.5 - (cy - r * 0.3)) <= r * 0.45:
                    c = light(core, 0.6)
                cv.put(x, y, c)
            elif d <= r + 4:
                cv.put(x, y, mix(base, core, 0.42))
            elif d <= r + 10:
                cv.put(x, y, mix(base, core, 0.16))


def cloud_sea(cv, layers, seed=7, clip=None):
    """A sea of clouds, back to front: each layer (top y, puff radius, colour, rim colour) a row of round puffs and
    everything under them, in flat colour; a 1 px lit rim on each puff's upper left. No outline."""
    rnd = _rand(seed)
    for (ytop, r, col, rim) in layers:
        puffs = []
        x = -r - int(rnd() * r)
        while x < cv.w + r:
            rr = r * (0.75 + 0.5 * rnd())
            puffs.append((x, ytop + rr, rr))
            x += int(rr * (1.1 + 0.5 * rnd()))
        floor = ytop + r * 1.2

        def inside(px, py):
            if py + 0.5 >= floor:
                return True
            return any((px + 0.5 - bx) ** 2 + (py + 0.5 - by) ** 2 <= br * br for (bx, by, br) in puffs)

        y_from = int(min(p[1] - p[2] for p in puffs)) - 1
        for y in range(max(0, y_from), cv.h):
            for x in range(cv.w):
                if clip is not None and not clip(x, y):
                    continue
                if inside(x, y):
                    c = col
                    if not inside(x - 1, y - 1) or not inside(x, y - 1):
                        c = rim
                    cv.put(x, y, c)


def far_islet(cv, cx, ty, w, col):
    """An islet far off: a flat silhouette in one colour (a lawn on top, the rock under it narrowing to a point, a
    tree or two on it), no outline, as the game's sky draws them."""
    pts = set()
    half = w / 2
    for y in range(ty, ty + 3):
        for x in range(int(cx - half), int(cx + half) + 1):
            pts.add((x, y))
    y, hw = ty + 3, half - 1
    while hw > 0.6:
        for x in range(int(round(cx - hw)), int(round(cx + hw)) + 1):
            pts.add((x, y))
        y += 1
        hw -= 0.9 if (y % 3) else 1.6
    for tx, th in ((cx - half * 0.4, 5), (cx + half * 0.15, 4)):
        for yy in range(ty - th, ty):
            rr = 2.2 if yy < ty - 1 else 0.6
            for x in range(int(tx - rr), int(tx + rr) + 1):
                if (x + 0.5 - tx) ** 2 + ((yy + 0.5 - (ty - th + 2)) * 1.1) ** 2 <= 2.6 * 2.6 or (yy >= ty - 2 and abs(x - tx) < 1):
                    pts.add((x, yy))
    for (x, y) in pts:
        cv.put(x, y, col)


def bird(cv, x, y, col, flap=0):
    """A gull far off: two wing strokes meeting at the body."""
    rows = (((-3, 0), (-2, -1), (-1, -1), (0, 0), (1, -1), (2, -1), (3, 0)), ((-3, -1), (-2, -1), (-1, 0), (0, 0), (1, 0), (2, -1), (3, -1)))[flap % 2]
    for dx, dy in rows:
        cv.put(x + dx, y + dy, col)


# ---------------------------------------------------------------- shapes with their own outline and anti-aliasing
class Layer:
    """A shape drawn on its own: pixels (with colours), then `outline` rings it and `aa` softens the outline's stairs
    against whatever lies behind once it is stamped."""

    def __init__(self):
        self.px = {}
        self.edge = set()

    def put(self, x, y, c):
        self.px[(x, y)] = c

    def outline(self, eight=False, keep=None, add=None):
        ring = {}
        for (x, y), c in self.px.items():
            for dx, dy in (N8 if eight else N4):
                q = (x + dx, y + dy)
                if q not in self.px:
                    ring.setdefault(q, []).append(c)
        for q, cols in ring.items():
            c = pick_beside(cols)
            self.px[q] = ink_of(c) if keep is None else ink_of(c, keep, add)
            self.edge.add(q)

    def stamp(self, cv, aa=True, cover=None, strength=0.5):
        """Down onto the canvas. With `aa`, each canvas pixel outside the shape that sits in an inside corner of the
        outline's stair (two outline pixels beside it at a right angle) takes a mix of the outline and itself; with
        `cover(x, y)` (how much of the pixel the ideal shape with its outline covers, 0 to 1) only where that is a
        fair part of it, so lines at whole slopes stay clean."""
        extra = {}
        if aa:
            for (x, y) in self.edge:
                for dx, dy in N4:
                    q = (q0, q1) = (x + dx, y + dy)
                    if q in self.px or q in extra:
                        continue
                    hv = [(q0 + 1, q1) in self.edge, (q0 - 1, q1) in self.edge]
                    vv = [(q0, q1 + 1) in self.edge, (q0, q1 - 1) in self.edge]
                    if sum(hv) != 1 or sum(vv) != 1:
                        continue
                    if cover is not None:
                        f = cover(q0, q1)
                        if f < 0.22:
                            continue
                        t = min(0.65, max(0.3, f))
                    else:
                        t = strength
                    back = cv.get(q0, q1)
                    if back is None:
                        continue
                    near = [self.px[n] for n in ((q0 + 1, q1), (q0 - 1, q1), (q0, q1 + 1), (q0, q1 - 1)) if n in self.edge]
                    extra[q] = mix(back, pick_beside(near), t)
        for (x, y), c in self.px.items():
            cv.put(x, y, c)
        for (x, y), c in extra.items():
            cv.put(x, y, c)
        return len(extra)


def mini_islet(cx, ty, w, grass, rock, seed=1, far=0.0, sky=None):
    """A small floating rock with a lawn on top as a Layer (outline and anti-aliasing included), lit from the top left:
    an oval lawn (a lit rim at the back, a darker lip at the front), an earth lip, then the rock narrowing in steps to
    a point, its left side lit and its right in shade, a crack or two. `far` mixes it toward the sky behind (0 near,
    1 gone) for the ones further off."""
    rnd = _rand(seed)
    L = Layer()
    rx, ry = w / 2, max(2.5, w / 6.5)
    cy = ty + ry
    g_hi, g_mid, g_lo = light(grass, 0.25), grass, dark(grass, 0.82)
    earth = dark(mix(rock, (150, 104, 70), 0.6), 0.85)
    r_hi, r_mid, r_lo, r_dk = light(rock, 0.18), rock, dark(rock, 0.84), dark(rock, 0.7)

    def lawn_in(x, y):
        return ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1

    top = {}
    for y in range(int(ty) - 1, int(cy + ry) + 2):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            if lawn_in(x, y):
                d = ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2
                c = g_mid
                if not lawn_in(x, y - 1) or (d > 0.7 and y < cy and x < cx):
                    c = g_hi
                elif y > cy and d > 0.55:
                    c = g_lo
                top[(x, y)] = c
    # the lip: two rows under the lawn's front
    lip = {}
    for (x, y) in top:
        for d in (1, 2):
            q = (x, y + d)
            if q not in top:
                lip[q] = g_lo if d == 1 and rnd() < 0.35 else earth
    # the rock: rows under the lip, narrowing to a point
    body = {}
    y = int(cy + ry) + 2
    hw = rx - 1
    lean = (rnd() - 0.5) * 2
    while hw >= 0.5:
        x0, x1 = int(round(cx - hw + lean * 0.3)), int(round(cx + hw + lean * 0.3))
        for x in range(x0, x1 + 1):
            if (x, y) in top or (x, y) in lip:
                continue
            t = (x - x0) / max(1, x1 - x0)
            body[(x, y)] = r_hi if t < 0.18 else (r_mid if t < 0.55 else (r_lo if t < 0.85 else r_dk))
        y += 1
        hw -= 0.55 + rnd() * 0.9
        lean += (rnd() - 0.5) * 0.8
    # a crack or two down the rock, a step darker
    for _ in range(max(1, int(w // 14))):
        x = int(cx + (rnd() - 0.5) * rx)
        yy = int(cy + ry) + 3
        for _ in range(int(2 + rnd() * 4)):
            if (x, yy) in body:
                body[(x, yy)] = dark(body[(x, yy)], 0.8)
            yy += 1
            x += 1 if rnd() < 0.3 else 0
    # a tuft or a little bush on the lawn
    if w >= 16:
        bx, by = int(cx - rx * 0.3), int(cy - 1)
        for (dx, dy, c) in ((0, -2, g_hi), (1, -2, g_mid), (-1, -1, g_hi), (0, -1, g_mid), (1, -1, g_mid), (2, -1, g_lo), (0, 0, g_lo), (1, 0, g_lo)):
            top[(bx + dx, by + dy)] = dark(c, 0.92)
    for d in (body, lip, top):
        for q, c in d.items():
            L.put(q[0], q[1], c)
    if far > 0 and sky is not None:
        for q in list(L.px):
            L.px[q] = mix(L.px[q], sky, far)
    L.outline()
    if far > 0 and sky is not None:
        for q in L.edge:
            L.px[q] = mix(L.px[q], sky, far * 0.6)
    return L


def _rand(seed):
    s = [seed * 2654435761 % 2147483648 or 1]

    def r():
        s[0] = (s[0] * 1103515245 + 12345) % 2147483648
        return s[0] / 2147483648

    return r


def common_colour(frame, m, test):
    """The commonest colour among the island's pixels that pass `test` (the lawn's green, the rock's tan)."""
    count = {}
    for y, row in enumerate(m):
        for x, on in enumerate(row):
            if on:
                c = frame.px[y][x]
                if c is not None and test(c):
                    count[c] = count.get(c, 0) + 1
    return max(count, key=count.get) if count else None
