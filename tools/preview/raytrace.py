"""Small numpy ray tracer for the preview tool: renders Roblox parts (Block, Ball, Cylinder, Wedge, CornerWedge) seen
from a perspective camera. Used for ViewportFrame contents (ingredient icons, the Recipe Desk cake) and for the
classic 3D world under the GUI when the pixel image does not cover the screen.

Shapes follow the same rules as raycast.luau (Ball diameter = smallest side, Cylinder along local X with diameter =
smaller of Y/Z, Wedge with the high edge at the back, CornerWedge apex above the (+X, -Z) corner; rays starting inside
a part do not hit it)."""
import math

import numpy as np


def cf_parts(cf):
    """CFrame components (x, y, z, r00..r22 row-major) -> (pos (3,), R (3,3)) with R columns = local axes."""
    pos = np.array(cf[0:3], dtype=np.float64)
    R = np.array(cf[3:12], dtype=np.float64).reshape(3, 3)
    return pos, R


def camera_rays(cam, w, h):
    """Origins (3,) and unit directions (h, w, 3) of a Roblox perspective camera (vertical FieldOfView)."""
    pos, R = cf_parts(cam["cf"])
    fov = math.radians(cam.get("fov") or 70)
    th = math.tan(fov / 2)
    aspect = w / max(1, h)
    xs = ((np.arange(w) + 0.5) / w) * 2 - 1
    ys = 1 - ((np.arange(h) + 0.5) / h) * 2
    gx, gy = np.meshgrid(xs * th * aspect, ys * th)
    d_local = np.stack([gx, gy, -np.ones_like(gx)], axis=-1)
    d_local /= np.linalg.norm(d_local, axis=-1, keepdims=True)
    dirs = d_local @ R.T  # world = R @ local
    return pos, dirs


def project_rect(cam, w, h, corners):
    """Screen rect (x0, y0, x1, y1) covering world points, or None when off screen; full screen if any is behind."""
    pos, R = cf_parts(cam["cf"])
    fov = math.radians(cam.get("fov") or 70)
    th = math.tan(fov / 2)
    aspect = w / max(1, h)
    local = (corners - pos) @ R  # R^T (p - pos)
    depth = -local[:, 2]
    if np.any(depth <= 0.05):
        return (0, 0, w - 1, h - 1)
    nx = local[:, 0] / (depth * th * aspect)
    ny = local[:, 1] / (depth * th)
    sx = (nx + 1) / 2 * w
    sy = (1 - ny) / 2 * h
    x0, x1 = int(math.floor(sx.min())) - 1, int(math.ceil(sx.max())) + 1
    y0, y1 = int(math.floor(sy.min())) - 1, int(math.ceil(sy.max())) + 1
    if x1 < 0 or y1 < 0 or x0 >= w or y0 >= h:
        return None
    return (max(0, x0), max(0, y0), min(w - 1, x1), min(h - 1, y1))


def wedge_planes(hx, hy, hz, corner):
    if corner:
        return [(1, 0, 0, hx), (0, 0, -1, hz), (0, -1, 0, hy), (-hy, hx, 0, 0), (0, hz, hy, 0)]
    return [(1, 0, 0, hx), (-1, 0, 0, hx), (0, -1, 0, hy), (0, 0, 1, hz), (0, hz, -hy, 0)]


def intersect(shape, o, d, pos, R, size):
    """o: (3,) or (n, 3) ray origins, d: (n, 3). Returns t (n,) with inf for misses and world normals (n, 3)."""
    n = d.shape[0]
    o = np.broadcast_to(np.asarray(o, dtype=np.float64), d.shape)
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    if shape == "ball":
        rad = min(hx, hy, hz)
        oc = o - pos
        a = np.einsum("ij,ij->i", d, d)
        b = 2 * np.einsum("ij,ij->i", d, oc)
        c = np.einsum("ij,ij->i", oc, oc) - rad * rad
        disc = b * b - 4 * a * c
        ok = (disc >= 0) & (c > 0)
        t = np.where(ok, (-b - np.sqrt(np.where(ok, disc, 0))) / (2 * a), np.inf)
        t = np.where(t >= 0, t, np.inf)
        hit = o + d * np.where(np.isfinite(t), t, 0)[:, None]
        nrm = (hit - pos) / rad
        return t, nrm
    lo = (o - pos) @ R  # (n, 3) local origins
    ld = d @ R  # (n, 3) local directions
    eps = 1e-12
    if shape == "block":
        te = np.full(n, -np.inf)
        tx = np.full(n, np.inf)
        axis = np.zeros(n, dtype=np.int64)
        sign = np.zeros(n)
        for a, h in ((0, hx), (1, hy), (2, hz)):
            da = ld[:, a]
            oa = lo[:, a]
            par = np.abs(da) < eps
            safe = np.where(par, 1.0, da)
            s1 = (-h - oa) / safe
            s2 = (h - oa) / safe
            smin = np.minimum(s1, s2)
            smax = np.maximum(s1, s2)
            outside = par & ((oa < -h) | (oa > h))
            smin = np.where(par, np.where(outside, np.inf, -np.inf), smin)
            smax = np.where(par, np.where(outside, -np.inf, np.inf), smax)
            upd = smin > te
            te = np.where(upd, smin, te)
            axis = np.where(upd, a, axis)
            sign = np.where(upd, np.where(da > 0, -1.0, 1.0), sign)
            tx = np.minimum(tx, smax)
        ok = (te <= tx) & (te >= 0) & np.isfinite(te)
        t = np.where(ok, te, np.inf)
        ln = np.zeros((n, 3))
        ln[np.arange(n), axis] = sign
        return t, ln @ R.T
    if shape == "cylinder":
        rad = min(hy, hz)
        qa = ld[:, 1] ** 2 + ld[:, 2] ** 2
        qb = 2 * (lo[:, 1] * ld[:, 1] + lo[:, 2] * ld[:, 2])
        qc = lo[:, 1] ** 2 + lo[:, 2] ** 2 - rad * rad
        par = qa < 1e-18
        disc = qb * qb - 4 * qa * qc
        sq = np.sqrt(np.where(disc >= 0, disc, 0))
        safe_a = np.where(par, 1.0, qa)
        te = np.where(par, np.where(qc <= 0, -np.inf, np.inf), (-qb - sq) / (2 * safe_a))
        tx = np.where(par, np.where(qc <= 0, np.inf, -np.inf), (-qb + sq) / (2 * safe_a))
        miss = (~par) & (disc < 0)
        da = ld[:, 0]
        ox = lo[:, 0]
        parx = np.abs(da) < eps
        safe = np.where(parx, 1.0, da)
        s1 = (-hx - ox) / safe
        s2 = (hx - ox) / safe
        smin = np.where(parx, np.where((ox < -hx) | (ox > hx), np.inf, -np.inf), np.minimum(s1, s2))
        smax = np.where(parx, np.inf, np.maximum(s1, s2))
        cap = smin > te
        te2 = np.maximum(te, smin)
        tx2 = np.minimum(tx, smax)
        ok = (~miss) & (te2 <= tx2) & (te2 >= 0) & np.isfinite(te2)
        t = np.where(ok, te2, np.inf)
        tt = np.where(np.isfinite(t), t, 0)
        ly = lo[:, 1] + ld[:, 1] * tt
        lz = lo[:, 2] + ld[:, 2] * tt
        ln = np.stack([np.where(cap, np.where(da > 0, -1.0, 1.0), 0.0), np.where(cap, 0, ly / rad), np.where(cap, 0, lz / rad)], axis=-1)
        return t, ln @ R.T
    # wedge / cornerwedge: convex clip
    planes = wedge_planes(hx, hy, hz, shape == "cornerwedge")
    te = np.full(n, -np.inf)
    tx = np.full(n, np.inf)
    enter = np.full(n, -1, dtype=np.int64)
    miss = np.zeros(n, dtype=bool)
    for q, (px, py, pz, pd) in enumerate(planes):
        pv = np.array([px, py, pz], dtype=np.float64)
        denom = ld @ pv
        num = pd - lo @ pv
        par = np.abs(denom) < eps
        miss |= par & (num < 0)
        safe = np.where(par, 1.0, denom)
        t = num / safe
        ent = (~par) & (denom < 0) & (t > te)
        te = np.where(ent, t, te)
        enter = np.where(ent, q, enter)
        ext = (~par) & (denom > 0)
        tx = np.where(ext, np.minimum(tx, t), tx)
    ok = (~miss) & (enter >= 0) & (te <= tx) & (te >= 0)
    t = np.where(ok, te, np.inf)
    pn = np.array([p[0:3] for p in planes], dtype=np.float64)
    pn /= np.linalg.norm(pn, axis=1, keepdims=True)
    ln = pn[np.clip(enter, 0, len(planes) - 1)]
    return t, ln @ R.T


def part_corners(pos, R, size):
    h = np.array(size, dtype=np.float64) / 2
    out = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                out.append(pos + R @ (h * np.array([sx, sy, sz])))
    return np.array(out)


def render(cam, parts, w, h, light=None, background=None, supersample=1):
    """Renders parts to an RGBA uint8 array (h, w, 4). light: dict(ambient=(r,g,b), color=(r,g,b), dir=(x,y,z)).
    background: (r, g, b, a) floats 0..1 or None for transparent."""
    W, Hh = w * supersample, h * supersample
    if W < 1 or Hh < 1:
        return np.zeros((max(1, h), max(1, w), 4), dtype=np.uint8)
    origin, dirs = camera_rays(cam, W, Hh)
    depth = np.full((Hh, W), np.inf)
    nrm = np.zeros((Hh, W, 3))
    col = np.zeros((Hh, W, 3))
    for p in parts:
        if p.get("tr", 0) >= 0.95:
            continue
        pos, R = cf_parts(p["cf"])
        size = p["size"]
        rect = project_rect(cam, W, Hh, part_corners(pos, R, size))
        if rect is None:
            continue
        x0, y0, x1, y1 = rect
        sub = dirs[y0 : y1 + 1, x0 : x1 + 1].reshape(-1, 3)
        t, n = intersect(p["shape"], origin, sub, pos, R, size)
        t = t.reshape(y1 - y0 + 1, x1 - x0 + 1)
        cur = depth[y0 : y1 + 1, x0 : x1 + 1]
        closer = t < cur
        if not closer.any():
            continue
        cur[closer] = t[closer]
        n = n.reshape(y1 - y0 + 1, x1 - x0 + 1, 3)
        nrm[y0 : y1 + 1, x0 : x1 + 1][closer] = n[closer]
        c = np.array(p["color"], dtype=np.float64)
        if p.get("mat") == "Neon":
            c = np.clip(c * 1.35 + 0.1, 0, 1)
        col[y0 : y1 + 1, x0 : x1 + 1][closer] = c
    light = light or {}
    amb = np.array(light.get("ambient", (0.78, 0.78, 0.78)))
    lc = np.array(light.get("color", (0.55, 0.55, 0.55)))
    ld = np.array(light.get("dir", (-1, -1, -1)), dtype=np.float64)
    ld = ld / (np.linalg.norm(ld) or 1)
    lam = np.clip(nrm @ (-ld), 0, 1)
    shaded = np.clip(col * (amb + lc * lam[..., None]), 0, 1)
    hit = np.isfinite(depth)
    out = np.zeros((Hh, W, 4))
    if background is not None:
        out[..., 0:3] = background[0:3]
        out[..., 3] = background[3]
    if callable(light.get("sky")):
        sky = light["sky"](dirs)
        out[..., 0:3] = sky
        out[..., 3] = 1
    out[hit, 0:3] = shaded[hit]
    out[hit, 3] = 1
    img = (out * 255 + 0.5).astype(np.uint8)
    if supersample > 1:
        img = img.reshape(h, supersample, w, supersample, 4).mean(axis=(1, 3)).astype(np.uint8)
    return img


# ---------------------------------------------------------------- orthographic true-isometric view (REWORK2 1.1-1.2)
ISO_YAW, ISO_PITCH = math.radians(45), math.atan(1 / math.sqrt(2))
INK = (0x2B / 255, 0x1E / 255, 0x2E / 255)


def iso_basis():
    back = np.array([math.sin(ISO_YAW) * math.cos(ISO_PITCH), math.sin(ISO_PITCH), math.cos(ISO_YAW) * math.cos(ISO_PITCH)])
    L = -back
    up = np.array([0.0, 1.0, 0.0])
    Rv = np.cross(L, up)
    Rv /= np.linalg.norm(Rv)
    Uv = np.cross(Rv, L)
    return Rv, Uv, L


def iso_view(bmin, bmax, fx, fy, margin=0.02, view_min_h=22.0, lower_by=2.0, insets=None, safe_margin=0.03):
    """REWORK2 1.2 framing of the box bmin..bmax (world) on an fx x fy screen -> (C, viewH, R, U, L).
    With insets (top, bottom, left, right; full-screen px): the current contain fit, the box whole inside the safe rect
    with safe_margin of it free on each side and centred there (Raster.fit). Without: the older width-fill framing."""
    Rv, Uv, L = iso_basis()
    corners = np.array([[x, y, z] for x in (bmin[0], bmax[0]) for y in (bmin[1], bmax[1]) for z in (bmin[2], bmax[2])], dtype=np.float64)
    u, v = corners @ Rv, corners @ Uv
    B = (np.array(bmin) + np.array(bmax)) / 2
    if insets is not None:
        t, b, l, r = [max(0.0, float(x)) for x in insets]
        def squeeze(a, c, full):
            room = full * 0.65
            if a + c > room:
                k = room / (a + c)
                return a * k, c * k
            return a, c
        t, b = squeeze(t, b, fy)
        l, r = squeeze(l, r, fx)
        sw, sh = fx - l - r, fy - t - b
        s = min(sw * (1 - 2 * safe_margin) / (u.max() - u.min()), sh * (1 - 2 * safe_margin) / (v.max() - v.min()))
        uc = (u.max() + u.min()) / 2 - (l + sw / 2 - fx / 2) / s
        vc = (v.max() + v.min()) / 2 + (t + sh / 2 - fy / 2) / s
        C = Rv * uc + Uv * vc + L * float(B @ L)
        return C, fy / s, Rv, Uv, L
    view_w = (u.max() - u.min()) * (1 + 2 * margin)
    view_h = min(max(view_w * fy / fx, view_min_h), (v.max() - v.min()) * (1 + 2 * margin))
    C = Rv * (u.max() + u.min()) / 2 + Uv * ((v.max() + v.min()) / 2 - lower_by) + L * float(B @ L)
    return C, view_h, Rv, Uv, L


def render_iso(parts, bmin, bmax, fx, fy, layer_h, ray_back=150.0, max_dist=400.0, sun=(-0.45, 0.8, 0.35), k=None, insets=None):
    """Orthographic render at the pixel-layer size with a 3-band toon ramp and ink outlines. With k (the game's
    PixelRenderer.pixelScale) and insets (CameraController.safeInsets): the current art grid (top-left, no offset) and
    framing. Without: the older K = round(fy / layer_h), centred overflow and width-fill framing.
    Returns an RGBA uint8 array (H, W, 4) and K."""
    K = int(k) if k else max(1, int(math.floor(fy / layer_h + 0.5)))
    W, H = int(math.ceil(fx / K)), int(math.ceil(fy / K))
    C, view_h, Rv, Uv, L = iso_view(bmin, bmax, fx, fy, insets=insets)
    s = fy / view_h
    offx, offy = (0.0, 0.0) if k else ((W * K - fx) / 2, (H * K - fy) / 2)
    xs = (np.arange(W) + 0.5) * K - offx
    ys = (np.arange(H) + 0.5) * K - offy
    gx, gy = np.meshgrid(xs, ys)
    origins = C + Rv * ((gx - fx / 2) / s)[..., None] - Uv * ((gy - fy / 2) / s)[..., None] - L * ray_back
    dirs = np.broadcast_to(L, origins.shape)  # unit: t is in studs
    depth = np.full((H, W), np.inf)
    ids = np.zeros((H, W), dtype=np.int64)
    nrm = np.zeros((H, W, 3))
    col = np.zeros((H, W, 3))
    for idx, p in enumerate(parts, start=1):
        if p.get("tr", 0) >= 0.95:
            continue
        pos, R = cf_parts(p["cf"])
        size = p["size"]
        corners = part_corners(pos, R, size)
        cx = (corners - C) @ Rv * s + fx / 2 + offx
        cy = fy / 2 - (corners - C) @ Uv * s + offy
        x0, x1 = int(math.floor(cx.min() / K)) - 1, int(math.ceil(cx.max() / K)) + 1
        y0, y1 = int(math.floor(cy.min() / K)) - 1, int(math.ceil(cy.max() / K)) + 1
        if x1 < 0 or y1 < 0 or x0 >= W or y0 >= H:
            continue
        x0, y0, x1, y1 = max(0, x0), max(0, y0), min(W - 1, x1), min(H - 1, y1)
        o = origins[y0 : y1 + 1, x0 : x1 + 1].reshape(-1, 3)
        d = dirs[y0 : y1 + 1, x0 : x1 + 1].reshape(-1, 3)
        t, n = intersect(p["shape"], o, d, pos, R, size)
        t = np.where(t <= max_dist, t, np.inf).reshape(y1 - y0 + 1, x1 - x0 + 1)
        cur = depth[y0 : y1 + 1, x0 : x1 + 1]
        closer = t < cur
        if not closer.any():
            continue
        cur[closer] = t[closer]
        ids[y0 : y1 + 1, x0 : x1 + 1][closer] = idx
        nrm[y0 : y1 + 1, x0 : x1 + 1][closer] = n.reshape(y1 - y0 + 1, x1 - x0 + 1, 3)[closer]
        c = np.array(p["color"], dtype=np.float64)
        col[y0 : y1 + 1, x0 : x1 + 1][closer] = c
    sunv = np.array(sun, dtype=np.float64)
    sunv /= np.linalg.norm(sunv)
    lam = np.clip(nrm @ sunv, 0, 1)
    band = np.where(lam < 0.25, 0.72, np.where(lam < 0.65, 0.88, 1.0))
    img = np.clip(col * band[..., None], 0, 1)
    hit = np.isfinite(depth)
    sky_top, sky_bot = np.array([0.62, 0.85, 0.95]), np.array([0.86, 0.94, 0.97])
    tt = (np.arange(H) / max(1, H - 1))[:, None, None]
    sky = sky_top * (1 - tt) + sky_bot * tt
    img = np.where(hit[..., None], img, np.broadcast_to(sky, img.shape))
    # 1 px ink outlines where a nearer surface of another part starts (silhouettes and creases)
    dd = np.where(hit, depth, 1e9)
    edge = np.zeros((H, W), dtype=bool)
    for dy, dx in ((0, 1), (1, 0), (0, -1), (-1, 0)):
        nb_id = np.roll(np.roll(ids, dy, axis=0), dx, axis=1)
        nb_d = np.roll(np.roll(dd, dy, axis=0), dx, axis=1)
        edge |= (ids != nb_id) & (dd < nb_d - 0.6) & hit
    img[edge] = INK
    out = np.concatenate([img, np.ones((H, W, 1))], axis=-1)
    return (out * 255 + 0.5).astype(np.uint8), K
