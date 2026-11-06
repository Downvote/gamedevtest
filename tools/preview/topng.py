#!/usr/bin/env python3
"""Turns preview.luau dumps into PNGs at the device resolution.

Usage: topng.py <dump.txt> <outdir> [--ui] [--boxes] [--no-core] [--iso]
  For every @@FRAME in the dump writes <outdir>/<label>.png: the 3D world (only where nothing covers it), the
  EditableImage pixel layer upscaled nearest-neighbour exactly like an ImageLabel with ResampleMode Pixelated, and the
  GUI drawn from the dumped PlayerGui tree (layout per guilayout.py) in DisplayOrder / ZIndex order.
  --ui     also writes <label>_ui.png (the GUI alone on a transparent background)
  --boxes  also writes <label>_boxes.png (every visible GuiObject rect outlined, with names; layout debugging)
  --no-core  skip the approximate Roblox core UI (top bar buttons, touch jump button).
  --iso    also writes <label>_iso.png: the world from the REWORK2 true-isometric orthographic camera (framing of 1.2,
           layer height of the tier, toon bands and ink outlines). An approximation drawn by this tool, not the
           game's renderer: it shows the floor plan and framing while the game's camera or renderer is not ready."""
import html
import json
import math
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import guilayout  # noqa: E402
import raytrace  # noqa: E402

FONT_DIR = os.path.join(HERE, "fonts")
FONT_FILES = {
    "arcade": os.path.join(FONT_DIR, "arcade.woff"),
    "body500": os.path.join(FONT_DIR, "body.woff"),
    "body700": os.path.join(FONT_DIR, "body-bold.woff"),
    "body800": os.path.join(FONT_DIR, "body-heavy.woff"),
    "mono": "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
    "fallback": "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
}
for key, path in list(FONT_FILES.items()):
    if not os.path.exists(path):
        FONT_FILES[key] = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

ENUM_FONT = {
    "Arcade": "arcade",
    "GothamBlack": "body800", "FredokaOne": "body800", "LuckiestGuy": "body800", "Bangers": "body800",
    "GothamBold": "body700", "SourceSansBold": "body700", "ArialBold": "body700", "RobotoBold": "body700",
    "GothamSemibold": "body700", "GothamMedium": "body700", "SourceSansSemibold": "body700",
    "Code": "mono", "RobotoMono": "mono", "Ubuntu": "body500",
}

_font_cache = {}


def font(key, size):
    size = max(1, int(round(size)))
    k = (key, size)
    f = _font_cache.get(k)
    if f is None:
        f = ImageFont.truetype(FONT_FILES[key], size)
        _font_cache[k] = f
    return f


def font_key_of(node, bold=False):
    ff = node.raw.get("FontFace")
    key = None
    if isinstance(ff, dict):
        fam = ff.get("family", "")
        weight = ff.get("weight", "Regular")
        if "PressStart" in fam or "Arcade" in fam:
            key = "arcade"
        elif any(x in fam for x in ("Mono", "Code", "Inconsolata")):
            key = "mono"
        elif weight in ("Heavy", "ExtraBold", "Black"):
            key = "body800"
        elif weight in ("Bold", "SemiBold"):
            key = "body700"
        else:
            key = "body500"
    else:
        name = node.get("Font") or "Legacy"
        key = ENUM_FONT.get(name, "body700" if "Bold" in str(name) else "body500")
    if bold and key == "body500":
        key = "body700"
    elif bold and key == "body700":
        key = "body800"
    return key


# ---------------------------------------------------------------- font metrics (shared with guiengine.luau)
METRICS = {}
if os.path.exists(os.path.join(HERE, "fontmetrics.json")):
    with open(os.path.join(HERE, "fontmetrics.json")) as _fh:
        METRICS = json.load(_fh)
for _k in METRICS:
    METRICS[_k]["adv"] = {int(c): v for c, v in METRICS[_k]["adv"].items()}


SCRIPT_FONTS = {
    "thai": "/usr/share/fonts/opentype/tlwg/Loma-Bold.otf",
    "cjk": "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
    "arabic": "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
}
_script_cache = {}


def script_font(text, size):
    """A shaped font for a run in a script the game draws natively (Thai, Arabic, CJK), else None."""
    kind = None
    for ch in text:
        cp = ord(ch)
        if 0x0E00 <= cp <= 0x0E7F:
            kind = "thai"
        elif 0x0600 <= cp <= 0x06FF or 0x0590 <= cp <= 0x05FF:
            kind = "arabic"
        elif 0x2E80 <= cp <= 0x9FFF or 0xAC00 <= cp <= 0xD7AF or 0xFF00 <= cp <= 0xFFEF:
            kind = "cjk"
        if kind:
            break
    if kind is None:
        return None
    size = max(1, int(round(size)))
    k = (kind, size)
    f = _script_cache.get(k)
    if f is None:
        try:
            f = ImageFont.truetype(SCRIPT_FONTS[kind], size, layout_engine=ImageFont.Layout.RAQM)
        except Exception:
            f = ImageFont.truetype(SCRIPT_FONTS[kind], size)
        _script_cache[k] = f
    return f


def glyph_key(key, ch):
    return key if ord(ch) in METRICS[key]["adv"] else "fallback"


def advance(key, ch, size):
    cp = ord(ch)
    a = METRICS[key]["adv"].get(cp)
    if a is None:
        a = METRICS["fallback"]["adv"].get(cp, 600)
    return a * size / 1000


# ---------------------------------------------------------------- drawing helpers
def rgba(c, transparency=0.0):
    return (int(round(c[0] * 255)), int(round(c[1] * 255)), int(round(c[2] * 255)), int(round(max(0.0, min(1.0, 1 - transparency)) * 255)))


def intersect_rect(a, b):
    if a is None:
        return b
    if b is None:
        return a
    return (max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3]))


class Canvas:
    def __init__(self, w, h):
        self.img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.W, self.H = w, h

    def paste(self, tile, x, y, clip):
        """alpha-composite tile at (x, y) (ints), clipped to clip=(x0,y0,x1,y1) floats or None."""
        tw, th = tile.size
        x0, y0, x1, y1 = x, y, x + tw, y + th
        cx0, cy0, cx1, cy1 = 0, 0, self.W, self.H
        if clip is not None:
            cx0, cy0 = max(cx0, int(math.floor(clip[0] + 0.5))), max(cy0, int(math.floor(clip[1] + 0.5)))
            cx1, cy1 = min(cx1, int(math.floor(clip[2] + 0.5))), min(cy1, int(math.floor(clip[3] + 0.5)))
        ix0, iy0, ix1, iy1 = max(x0, cx0), max(y0, cy0), min(x1, cx1), min(y1, cy1)
        if ix0 >= ix1 or iy0 >= iy1:
            return
        part = tile.crop((ix0 - x, iy0 - y, ix1 - x, iy1 - y))
        self.img.alpha_composite(part, (ix0, iy0))


def rect_ints(n):
    x0, y0 = int(math.floor(n.x + 0.5)), int(math.floor(n.y + 0.5))
    x1, y1 = int(math.floor(n.x + n.w + 0.5)), int(math.floor(n.y + n.h + 0.5))
    return x0, y0, max(0, x1 - x0), max(0, y1 - y0)


def corner_radius(n, w, h):
    c = n.comp("UICorner")
    if not c:
        return 0
    r = c.get("CornerRadius")
    return max(0.0, min(min(w, h) / 2, r[0] * min(w, h) + r[1] * n.k))


def seq_eval(keys, t, n):
    t = max(0.0, min(1.0, t))
    for i in range(len(keys) - 1):
        a, b = keys[i], keys[i + 1]
        if a[0] <= t <= b[0]:
            f = 0 if b[0] == a[0] else (t - a[0]) / (b[0] - a[0])
            return [a[1 + j] + (b[1 + j] - a[1 + j]) * f for j in range(n)]
    return list(keys[-1][1 : 1 + n])


def gradient_rgba(n, w, h, base_rgb, base_alpha):
    g = n.comp("UIGradient")
    if not g or g.get("Enabled") is False or w <= 0 or h <= 0:
        return None
    cs = (g.get("Color") or {}).get("cs") or [[0, 1, 1, 1], [1, 1, 1, 1]]
    ns = (g.get("Transparency") or {}).get("ns") or [[0, 0, 0], [1, 0, 0]]
    rot = math.radians(float(g.get("Rotation") or 0))
    off = g.get("Offset") or [0, 0]
    ys, xs = np.mgrid[0:h, 0:w]
    u = (xs + 0.5) / w - 0.5 - off[0]
    v = (ys + 0.5) / h - 0.5 - off[1]
    t = u * math.cos(rot) + v * math.sin(rot)
    ext = abs(0.5 * math.cos(rot)) + abs(0.5 * math.sin(rot))
    t = (t / (2 * ext if ext > 0 else 1)) + 0.5
    lut_n = 256
    lut_t = np.linspace(0, 1, lut_n)
    col_lut = np.array([seq_eval(cs, x, 3) for x in lut_t])
    tr_lut = np.array([seq_eval(ns, x, 1)[0] for x in lut_t])
    idx = np.clip((t * (lut_n - 1)).astype(int), 0, lut_n - 1)
    rgb = col_lut[idx] * np.array(base_rgb)
    a = (1 - tr_lut[idx]) * base_alpha
    arr = np.concatenate([rgb, a[..., None]], axis=-1)
    return Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


def shape_mask(w, h, r):
    if w < 1 or h < 1:
        return Image.new("L", (max(1, w), max(1, h)), 0)
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    if r > 0.5:
        d.rounded_rectangle((0, 0, w - 1, h - 1), radius=int(round(r)), fill=255)
    else:
        d.rectangle((0, 0, w - 1, h - 1), fill=255)
    return m


# ---------------------------------------------------------------- renderer
class Frame:
    def __init__(self, label, meta, images, gui, world):
        self.label = label
        self.meta = meta
        self.images = images
        self.gui = gui
        self.world = world


class Renderer:
    def __init__(self, frame, opts):
        self.f = frame
        self.opts = opts
        self.W, self.H = frame.meta["w"], frame.meta["h"]
        self.boxes = []
        self.stats = {"nodes": 0, "texts": 0, "viewports": 0, "images": 0}

    # -- per node
    def draw_background(self, cv, n, x, y, w, h):
        bt = float(n.get("BackgroundTransparency") or 0)
        if bt >= 0.999 or w <= 0 or h <= 0:
            return
        c = n.get("BackgroundColor3")
        r = corner_radius(n, w, h)
        grad = gradient_rgba(n, w, h, c, 1 - bt)
        mask = shape_mask(w, h, r)
        if grad is not None:
            tile = grad
            a = np.array(tile.split()[3], dtype=np.float32) * (np.array(mask, dtype=np.float32) / 255)
            tile.putalpha(Image.fromarray(a.astype(np.uint8), "L"))
        else:
            tile = Image.new("RGBA", (w, h), rgba(c, bt))
            a = np.array(mask, dtype=np.float32) * (1 - bt)
            tile.putalpha(Image.fromarray(a.astype(np.uint8), "L"))
        cv.paste(tile, x, y, n.clip)
        bs = int(n.get("BorderSizePixel") or 0)
        if bs > 0 and r == 0:
            mode = n.get("BorderMode") or "Outline"
            off = bs if mode == "Outline" else (bs // 2 if mode == "Middle" else 0)
            bw, bh = w + 2 * off, h + 2 * off
            if bw > 0 and bh > 0:
                tile = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
                d = ImageDraw.Draw(tile)
                d.rectangle((0, 0, bw - 1, bh - 1), outline=rgba(n.get("BorderColor3"), bt), width=bs)
                cv.paste(tile, x - off, y - off, n.clip)

    def draw_stroke(self, cv, n, x, y, w, h):
        for c in n.kids:
            if c.cls != "UIStroke" or c.get("Enabled") is False:
                continue
            mode = c.get("ApplyStrokeMode")
            if mode == "Contextual" and n.cls in guilayout.TEXT_CLASSES:
                continue  # text outline, drawn with the text
            t = float(c.get("Thickness") or 1) * n.k
            if t <= 0.01:
                continue
            ti = max(1, int(round(t)))
            r = corner_radius(n, w, h)
            if r > 0:
                ro = r + ti
            else:
                ro = ti if c.get("LineJoinMode") == "Round" else 0
            ow, oh = w + 2 * ti, h + 2 * ti
            outer = shape_mask(ow, oh, ro)
            inner = Image.new("L", (ow, oh), 0)
            if w >= 1 and h >= 1:
                inner.paste(shape_mask(w, h, r), (ti, ti))
            m = np.array(outer, dtype=np.int16) - np.array(inner, dtype=np.int16)
            m = np.clip(m, 0, 255).astype(np.float32) * (1 - float(c.get("Transparency") or 0))
            tile = Image.new("RGBA", (ow, oh), rgba(c.get("Color")))
            tile.putalpha(Image.fromarray(m.astype(np.uint8), "L"))
            cv.paste(tile, x - ti, y - ti, n.clip)

    def draw_image(self, cv, n, x, y, w, h):
        if w <= 0 or h <= 0:
            return
        it = float(n.get("ImageTransparency") or 0)
        if it >= 0.999:
            return
        content = n.raw.get("ImageContent")
        src = None
        if isinstance(content, dict) and content.get("src") == "Object":
            src = self.f.images.get(content.get("inst"))
        if src is None:
            uri = n.get("Image") or (content.get("uri") if isinstance(content, dict) else "")
            if uri:
                tile = Image.new("RGBA", (w, h), (200, 200, 210, int(160 * (1 - it))))
                d = ImageDraw.Draw(tile)
                for i in range(-h, w, 8):
                    d.line((i, 0, i + h, h), fill=(150, 150, 165, int(160 * (1 - it))), width=1)
                cv.paste(tile, x, y, n.clip)
            return
        self.stats["images"] += 1
        resample = Image.NEAREST if n.get("ResampleMode") == "Pixelated" else Image.BILINEAR
        # ImageRectOffset / ImageRectSize: only that part of the image is shown (an atlas page, a sprite sheet)
        ro, rs = n.raw.get("ImageRectOffset"), n.raw.get("ImageRectSize")
        if isinstance(rs, list) and len(rs) == 2 and rs[0] > 0 and rs[1] > 0:
            ox, oy = (int(round(ro[0])), int(round(ro[1]))) if isinstance(ro, list) and len(ro) == 2 else (0, 0)
            src = src.crop((ox, oy, ox + int(round(rs[0])), oy + int(round(rs[1]))))
        tile = src.resize((w, h), resample)
        col = n.get("ImageColor3") or [1, 1, 1]
        if it > 0 or any(abs(v - 1) > 1e-3 for v in col):
            arr = np.array(tile, dtype=np.float32)
            arr[..., 0:3] *= np.array(col, dtype=np.float32)
            arr[..., 3] *= 1 - it
            tile = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
        r = corner_radius(n, w, h)
        if r > 0:
            a = np.array(tile.split()[3], dtype=np.float32) * (np.array(shape_mask(w, h, r), dtype=np.float32) / 255)
            tile.putalpha(Image.fromarray(a.astype(np.uint8), "L"))
        cv.paste(tile, x, y, n.clip)

    def draw_viewport(self, cv, n, x, y, w, h):
        vp = n.vp
        if not vp or not vp.get("camera") or w <= 1 or h <= 1:
            return
        it = float(n.get("ImageTransparency") or 0)
        if it >= 0.999:
            return
        self.stats["viewports"] += 1
        ss = 2 if w * h <= 300 * 300 else 1
        light = {
            "ambient": n.get("Ambient"),
            "color": n.get("LightColor"),
            "dir": n.get("LightDirection"),
        }
        arr = raytrace.render(vp["camera"], vp.get("parts", []), w, h, light=light, background=None, supersample=ss)
        tile = Image.fromarray(arr, "RGBA")
        col = n.get("ImageColor3") or [1, 1, 1]
        if it > 0 or any(abs(v - 1) > 1e-3 for v in col):
            a = np.array(tile, dtype=np.float32)
            a[..., 0:3] *= np.array(col, dtype=np.float32)
            a[..., 3] *= 1 - it
            tile = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
        cv.paste(tile, x, y, n.clip)

    def draw_text(self, cv, n, x, y, w, h):
        tx = n.extra.get("tx")
        if not tx or not tx.get("lines"):
            return
        tt = float(n.get("TextTransparency") or 0)
        if tt >= 0.999:
            return
        self.stats["texts"] += 1
        k = n.k
        pad4 = tx.get("pad") or [0, 0, 0, 0]
        x, y = x + pad4[0], y + pad4[1]
        w, h = max(0, w - pad4[0] - pad4[2]), max(0, h - pad4[1] - pad4[3])
        size = float(tx["size"])
        lines = tx["lines"]
        widths = [float(ln["w"]) for ln in lines]
        heights = [float(ln["h"]) for ln in lines]
        # truncation (one line, no wrap): AtEnd / SplitWord cut with "..."
        wrap = n.get("TextWrapped") or n.get("TextScaled")
        if not wrap and n.get("TextTruncate") in ("AtEnd", "SplitWord") and len(lines) == 1 and widths[0] > w + 0.5:
            segs = lines[0]["s"]
            key0, size0 = (segs[0][1], float(segs[0][2])) if segs else ("body500", size)
            ell = sum(advance(key0, c, size0) for c in "...")
            out, used = [], 0.0
            for seg in segs:
                text, key, fs = seg[0], seg[1], float(seg[2])
                sw = sum(advance(key, c, fs) for c in text)
                if used + sw + ell <= w:
                    out.append(seg)
                    used += sw
                    continue
                cut = text
                while cut and used + sum(advance(key, c, fs) for c in cut) + ell > w:
                    cut = cut[:-1]
                if cut:
                    out.append([cut, key, fs, 0, seg[4], seg[5], seg[6]])
                    used += sum(advance(key, c, fs) for c in cut)
                break
            last = segs[-1] if segs else ["", key0, size0, 0, None, None, None]
            out.append(["...", key0, size0, ell, last[4], last[5], last[6]])
            lines = [{"w": used + ell, "h": heights[0], "s": out}]
            widths = [used + ell]
        total_h = sum(heights)
        ya = n.get("TextYAlignment")
        y0 = y + (0 if ya == "Top" else (h - total_h if ya == "Bottom" else (h - total_h) / 2))
        xa = n.get("TextXAlignment")
        color = n.get("PlaceholderColor3") if tx.get("ph") else n.get("TextColor3")
        strokes = []
        tst = n.get("TextStrokeTransparency")
        if tst is not None and float(tst) < 0.999:
            strokes.append((n.get("TextStrokeColor3"), max(1, round(k)), float(tst)))
        for c in n.kids:
            if c.cls == "UIStroke" and c.get("Enabled") is not False and c.get("ApplyStrokeMode") == "Contextual":
                strokes.append((c.get("Color"), max(1, int(round(float(c.get("Thickness") or 1) * k))), float(c.get("Transparency") or 0)))
        pad = int(max([s_[1] for s_ in strokes] or [0]) + size * 0.6 + 4)
        placed = []
        ly = y0
        for ln, lw, lh in zip(lines, widths, heights):
            lx = x if xa == "Left" else (x + w - lw if xa == "Right" else x + (w - lw) / 2)
            placed.append((ln["s"], lx, lw, ly, lh))
            ly += lh
        tx0 = min([x] + [p_[1] for p_ in placed]) - pad
        tx1 = max([x + w] + [p_[1] + p_[2] for p_ in placed]) + pad
        ty0 = min(y, y0) - pad
        ty1 = max(y + h, y0 + total_h) + pad
        bx, by = int(math.floor(tx0)), int(math.floor(ty0))
        tile = Image.new("RGBA", (max(1, int(math.ceil(tx1)) - bx), max(1, int(math.ceil(ty1)) - by)), (0, 0, 0, 0))
        d = ImageDraw.Draw(tile)
        for segs, lx, lw, ly, lh in placed:
            cx = lx
            for seg in segs:
                text, key, fs = seg[0], seg[1], float(seg[2])
                col = seg[4] or color
                tr = seg[5] if seg[5] is not None else tt
                stl = list(strokes)
                if seg[6]:
                    sk = seg[6]
                    stl.append((sk[0:3], max(1, int(round(sk[3] * k))), sk[4]))
                sf = script_font(text, fs)
                if sf is not None:
                    # Thai, Arabic, Chinese ... (docs/LOCALIZATION.md 3): the whole run at once, shaped (RAQM)
                    asc, desc = sf.getmetrics()
                    base = ly + (lh - (asc + desc)) / 2 + asc
                    px, py = cx - bx, base - by
                    for sc, sw_, str_ in stl:
                        d.text((px, py), text, font=sf, fill=rgba(sc, str_), anchor="ls", stroke_width=sw_, stroke_fill=rgba(sc, str_))
                    d.text((px, py), text, font=sf, fill=rgba(col, tr), anchor="ls")
                    cx += sf.getlength(text)
                    continue
                for ch in text:
                    gk = glyph_key(key, ch)
                    adv = advance(key, ch, fs)
                    if not ch.isspace():
                        f = font(gk, fs)
                        asc, desc = f.getmetrics()
                        base = ly + (lh - (asc + desc)) / 2 + asc
                        px, py = cx - bx, base - by
                        for sc, sw_, str_ in stl:
                            d.text((px, py), ch, font=f, fill=rgba(sc, str_), anchor="ls", stroke_width=sw_, stroke_fill=rgba(sc, str_))
                        d.text((px, py), ch, font=f, fill=rgba(col, tr), anchor="ls")
                    cx += adv
        clip = n.clip
        if n.get("ClipsDescendants"):
            clip = intersect_rect(clip, (n.x, n.y, n.x + n.w, n.y + n.h))
        cv.paste(tile, bx, by, clip)

    def draw_scrollbar(self, cv, n, x, y, w, h):
        if n.cls != "ScrollingFrame" or not n.canvas:
            return
        th = int(round(float(n.get("ScrollBarThickness") or 0)))
        if th <= 0:
            return
        cw, ch = n.canvas
        if ch > h + 1 and n.get("ScrollingDirection") in ("XY", "Y"):
            frac = h / ch
            pos = (n.get("CanvasPosition") or [0, 0])[1] / max(1, ch - h)
            bh = max(th, int(h * frac))
            byy = y + int((h - bh) * min(1, max(0, pos)))
            tile = Image.new("RGBA", (th, bh), rgba(n.get("ScrollBarImageColor3"), max(float(n.get("ScrollBarImageTransparency") or 0), 0.35)))
            cv.paste(tile, x + w - th, byy, n.clip)

    def draw_node(self, cv, n, mode_global=False):
        if not n.visible() or not n.measured:
            return
        self.stats["nodes"] += 1
        x, y, w, h = rect_ints(n)
        rot = float(n.get("Rotation") or 0) % 360
        is_group = n.cls == "CanvasGroup"
        if (abs(rot) > 0.5 and abs(rot - 360) > 0.5) or is_group:
            layer = Canvas(cv.W, cv.H)
            self.draw_self(layer, n, x, y, w, h)
            self.draw_children(layer, n)
            img = layer.img
            if is_group:
                gt = float(n.get("GroupTransparency") or 0)
                gc = n.get("GroupColor3") or [1, 1, 1]
                arr = np.array(img, dtype=np.float32)
                arr[..., 0:3] *= np.array(gc, dtype=np.float32)
                arr[..., 3] *= 1 - gt
                mask = np.zeros(arr.shape[0:2], dtype=bool)
                mask[max(0, y) : max(0, y + h), max(0, x) : max(0, x + w)] = True
                arr[~mask, 3] = 0
                img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
            if abs(rot) > 0.5 and abs(rot - 360) > 0.5:
                img = img.rotate(-rot, resample=Image.BICUBIC, center=(n.x + n.w / 2, n.y + n.h / 2))
            cv.paste(img, 0, 0, n.clip)
            return
        self.draw_self(cv, n, x, y, w, h)
        if not mode_global:
            self.draw_children(cv, n)

    def draw_self(self, cv, n, x, y, w, h):
        if self.opts.get("boxes") is not None:
            self.boxes.append((n.x, n.y, n.w, n.h, n.name, n.cls))
        self.draw_background(cv, n, x, y, w, h)
        if n.cls in guilayout.IMAGE_CLASSES:
            self.draw_image(cv, n, x, y, w, h)
        elif n.cls == "ViewportFrame":
            self.draw_viewport(cv, n, x, y, w, h)
        if n.cls in guilayout.TEXT_CLASSES:
            self.draw_text(cv, n, x, y, w, h)
        self.draw_stroke(cv, n, x, y, w, h)
        self.draw_scrollbar(cv, n, x, y, w, h)

    def draw_children(self, cv, n):
        kids = [c for c in n.guikids if c.visible()]
        kids.sort(key=lambda c: (c.get("ZIndex") or 1))  # stable: equal ZIndex keeps child order
        for c in kids:
            self.draw_node(cv, c)

    def draw_screen(self, cv, sg):
        if sg.get("Enabled") is False:
            return
        if sg.get("ZIndexBehavior") == "Global":
            order = []

            def walk(node):
                for c in node.guikids:
                    if c.visible():
                        order.append(c)
                        walk(c)

            walk(sg)
            order.sort(key=lambda c: (c.get("ZIndex") or 1))
            for c in order:
                self.draw_node(cv, c, mode_global=True)
        else:
            self.draw_children(cv, sg)

    # -- whole frame
    def pixel_covers(self, screens):
        for sg in screens:
            if sg.get("Enabled") is False:
                continue
            stack = list(sg.guikids)
            while stack:
                n = stack.pop()
                if not n.visible():
                    continue
                stack.extend(n.guikids)
                c = n.raw.get("ImageContent")
                if n.cls in guilayout.IMAGE_CLASSES and isinstance(c, dict) and c.get("inst") in self.f.images:
                    if float(n.get("ImageTransparency") or 0) < 0.01 and n.x <= 0.5 and n.y <= 0.5 and n.x + n.w >= self.W - 0.5 and n.y + n.h >= self.H - 0.5:
                        return True
        return False

    def world_image(self):
        world = self.f.world
        if not world or not world.get("camera"):
            return Image.new("RGBA", (self.W, self.H), (159, 216, 242, 255))
        div = 3 if self.W * self.H > 1000 * 600 else 2
        w, h = max(1, self.W // div), max(1, self.H // div)

        def sky(dirs):
            t = np.clip(dirs[..., 1] * 0.5 + 0.5, 0, 1)[..., None]
            return np.array([0.86, 0.93, 0.97]) * (1 - t) + np.array([0.55, 0.78, 0.93]) * t

        sun = np.array([-0.45, 0.8, 0.35])
        light = {"ambient": (0.62, 0.6, 0.62), "color": (0.5, 0.48, 0.45), "dir": tuple(-sun), "sky": sky}
        arr = raytrace.render(world["camera"], world.get("parts", []), w, h, light=light, background=(0.62, 0.84, 0.95, 1))
        return Image.fromarray(arr, "RGBA").resize((self.W, self.H), Image.BILINEAR)

    def core_ui(self, cv):
        meta = self.f.meta
        inset = meta.get("inset", 0)
        d = ImageDraw.Draw(cv.img)
        if inset > 0:
            for i, x0 in enumerate((12,)):
                tile = Image.new("RGBA", (44, 44), (0, 0, 0, 0))
                td = ImageDraw.Draw(tile)
                td.rounded_rectangle((0, 0, 43, 43), radius=22, fill=(18, 18, 21, 150))
                td.rounded_rectangle((13, 13, 30, 30), radius=3, outline=(255, 255, 255, 230), width=3)
                cv.paste(tile, x0, max(0, (inset - 44) // 2), None)
        if meta.get("touch") and meta.get("touchControls", True):
            small = min(self.W, self.H) <= 500
            size = 70 if small else 120
            jx, jy = (self.W - 95, self.H - 90) if small else (self.W - 170, self.H - 210)
            tile = Image.new("RGBA", (size, size), (0, 0, 0, 0))
            td = ImageDraw.Draw(tile)
            td.ellipse((0, 0, size - 1, size - 1), fill=(255, 255, 255, 45), outline=(255, 255, 255, 140), width=3)
            s = size / 70
            td.polygon([(35 * s, 20 * s), (50 * s, 40 * s), (20 * s, 40 * s)], outline=(255, 255, 255, 170), width=3)
            cv.paste(tile, jx, jy, None)

    def render(self):
        screens = [guilayout.Node(g, None, i) for i, g in enumerate(self.f.gui or [])]
        order = sorted(range(len(screens)), key=lambda i: (screens[i].get("DisplayOrder") or 0, i))
        ui = Canvas(self.W, self.H)
        for i in order:
            self.draw_screen(ui, screens[i])
        if self.opts.get("core", True):
            self.core_ui(ui)
        covered = self.pixel_covers(screens)
        base = Image.new("RGBA", (self.W, self.H), (0, 0, 0, 255)) if covered else self.world_image()
        out = base.copy()
        out.alpha_composite(ui.img)
        return out.convert("RGB"), ui.img, covered

    def boxes_image(self, under):
        img = under.convert("RGBA").copy()
        d = ImageDraw.Draw(img)
        f = font("body500", 11)
        for x, y, w, h, name, cls in self.boxes:
            if w < 1 or h < 1:
                continue
            color = (255, 0, 120, 200) if cls in guilayout.TEXT_CLASSES else (0, 140, 255, 180)
            d.rectangle((x, y, x + max(0, w) - 1, y + max(0, h) - 1), outline=color, width=1)
            if w > 40 and h > 12:
                d.text((x + 2, y + 1), name[:24], font=f, fill=color)
        return img.convert("RGB")


# ---------------------------------------------------------------- parsing
def parse_dump(path):
    frames = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().split("\n")
    i = 0
    cur = None
    while i < len(lines):
        ln = lines[i]
        if ln.startswith("@@FRAME "):
            cur = {"label": ln[8:].strip(), "images": {}, "gui": None, "world": None, "meta": None}
        elif cur is not None and ln.startswith("@@META "):
            cur["meta"] = json.loads(ln[7:])
        elif cur is not None and ln.startswith("@@IMAGE "):
            _, iid, w, h, _writes = ln.split()
            w, h = int(w), int(h)
            data = bytes.fromhex("".join(lines[i + 1 : i + 1 + h]))
            cur["images"][int(iid)] = Image.frombytes("RGBA", (w, h), data)
            i += h
        elif cur is not None and ln.startswith("@@GUI "):
            cur["gui"] = json.loads(ln[6:])
        elif cur is not None and ln.startswith("@@WORLD "):
            cur["world"] = json.loads(ln[8:])
        elif cur is not None and ln.startswith("@@ENDFRAME"):
            frames.append(Frame(cur["label"], cur["meta"], cur["images"], cur["gui"], cur["world"]))
            cur = None
        i += 1
    return frames


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    dump, outdir = argv[1], argv[2]
    flags = set(argv[3:])
    os.makedirs(outdir, exist_ok=True)
    frames = parse_dump(dump)
    if not frames:
        print("no frames in " + dump)
        return 1
    for fr in frames:
        opts = {"core": "--no-core" not in flags, "boxes": [] if "--boxes" in flags else None}
        r = Renderer(fr, opts)
        img, ui, covered = r.render()
        path = os.path.join(outdir, fr.label + ".png")
        img.save(path)
        extra = []
        if "--ui" in flags:
            p2 = os.path.join(outdir, fr.label + "_ui.png")
            ui.save(p2)
            extra.append(os.path.basename(p2))
        if "--iso" in flags and fr.meta.get("iso") and fr.world:
            iso = fr.meta["iso"]
            tier = fr.meta.get("tier", "auto")
            layer_h = {"low": 180, "medium": 270, "high": 360}.get(tier, 180 if fr.meta.get("touch") else 270)
            arr, K = raytrace.render_iso(fr.world.get("parts", []), iso["min"], iso["max"], fr.meta["w"], fr.meta["h"], layer_h, k=iso.get("k"), insets=iso.get("insets"))
            iso_img = Image.fromarray(arr, "RGBA")
            full = iso_img.resize((iso_img.size[0] * K, iso_img.size[1] * K), Image.NEAREST)
            # the current art grid starts at the top-left corner; older trees centred the overflow
            ox, oy = (0, 0) if iso.get("k") else ((full.size[0] - fr.meta["w"]) // 2, (full.size[1] - fr.meta["h"]) // 2)
            full = full.crop((ox, oy, ox + fr.meta["w"], oy + fr.meta["h"]))
            p4 = os.path.join(outdir, fr.label + "_iso.png")
            full.convert("RGB").save(p4)
            extra.append(os.path.basename(p4))
        if "--boxes" in flags:
            p3 = os.path.join(outdir, fr.label + "_boxes.png")
            r.boxes_image(img).save(p3)
            extra.append(os.path.basename(p3))
        layer = ", ".join(f"{im.size[0]}x{im.size[1]}" for im in fr.images.values()) or "none"
        print(f"{path}  ({fr.meta['w']}x{fr.meta['h']}, pixel layer {layer}{', covers the screen' if covered else ', world drawn underneath'}; "
              f"{r.stats['nodes']} gui objects, {r.stats['texts']} texts, {r.stats['viewports']} viewports)" + (" + " + ", ".join(extra) if extra else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
