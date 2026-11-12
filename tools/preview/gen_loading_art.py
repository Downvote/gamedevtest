#!/usr/bin/env python3
"""Packs the loading card's scene art into src/first/LoadingArt.luau (ARCHITECTURE 10.1).

Usage: gen_loading_art.py <ploadingart log> [<out.luau>] [--sheet <png>] [--atlas <png>]

The log is the preview scenario "ploadingart"'s (tools/preview/loading_art.luau: `@@LART` frames, `@@LSEQ`
sequences, `@@LPT` points); tools/preview/loading_art.sh runs both. Every sequence is cropped to the pixels its frames
use (its anchor and points moved with it), its frames packed into one atlas, and written as one palette (every
colour the frames use, 0xRRGGBB, most used first), per sequence the colours it uses (pal: indices into that palette)
and per frame a line of run-length codes:

  the alphabet is the 91 printable characters from '#' to '~' without the backslash; with the sequence's NS = 2 +
  #pal, a code below NS is a symbol, the codes from NS up are the digits of its run's length (bijective base 91 - NS,
  least significant first: no digit is a run of 1). Symbol 0 = the pixel of the sequence's previous frame at the same
  place (frames 2.., and the first frame of a sequence with a `base`: that sequence's first frame, framed alike), 1 =
  clear, 2 + i = the sequence's colour i + 1 (palette[pal[i + 1]]). A frame's pixels run row by row over its rect.

--sheet writes a contact sheet of every sequence (4x, on the card's wall pink), --atlas the atlas itself.
"""
import os
import sys

ALPHABET = "".join(chr(c) for c in range(35, 127) if c != 92)
assert len(ALPHABET) == 91
WALL = (59, 47, 92)  # the card's dusk sky, behind the contact sheet
FLAT = {"gull", "star", "crest", "ember", "glint"}  # hand-made 2D sequences (exact, never cut off)


def parse(path):
    seqs, order = {}, []
    for line in open(path, encoding="utf-8", errors="replace"):
        if line.startswith("@@LSEQ "):
            parts = line.split()
            _, name, n, dur, ax, ay = parts[:6]
            s = seqs.setdefault(name, {"frames": {}, "pts": {}})
            s.update(n=int(n), dur=float(dur), ax=int(ax), ay=int(ay), base=parts[6] if len(parts) > 6 else None)
            order.append(name)
        elif line.startswith("@@LPT "):
            _, name, key, x, y = line.split()
            seqs.setdefault(name, {"frames": {}, "pts": {}})["pts"][key] = (int(x), int(y))
        elif line.startswith("@@LART "):
            _, name, i, w, h, hexs = line.split()
            w, h = int(w), int(h)
            px = []
            for k in range(w * h):
                v = int(hexs[k * 8:k * 8 + 8], 16)
                r, g, b, a = v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255
                px.append((r, g, b) if a >= 128 else None)
            s = seqs.setdefault(name, {"frames": {}, "pts": {}})
            s["frames"][int(i)] = px
            s["w"], s["h"] = w, h
    return [(name, seqs[name]) for name in order]


def bounds(s):
    w = s["w"]
    xs, ys = [], []
    for i in range(1, s["n"] + 1):
        for k, c in enumerate(s["frames"][i]):
            if c is not None:
                xs.append(k % w)
                ys.append(k // w)
    if not xs:
        raise SystemExit("sequence with no pixels")
    return min(xs), max(xs) + 1, min(ys), max(ys) + 1


def crop(s, box=None):
    # (box: the rect to keep, when sequences framed alike share one: a sequence and those based on it)
    w, h = s["w"], s["h"]
    frames = [s["frames"][i] for i in range(1, s["n"] + 1)]
    x0, x1, y0, y1 = box or bounds(s)
    if s["name"] not in FLAT and (x0 == 0 or y0 == 0 or x1 == w or y1 == h):
        print("warning: a frame of %s reaches the edge of its %dx%d box (cut off?)" % (s.get("name", "?"), w, h))
    cw, ch = x1 - x0, y1 - y0
    out = []
    for px in frames:
        out.append([px[(y0 + y) * w + x0 + x] for y in range(ch) for x in range(cw)])
    s["frames"] = out
    s["w"], s["h"] = cw, ch
    s["ax"] -= x0
    s["ay"] -= y0
    # (points are from the anchor: they stay as they are)


def pack(seqs, width):
    # shelves, tallest sequences first; every frame of a sequence on the same shelf when it fits
    items = []
    for name, s in seqs:
        for i in range(len(s["frames"])):
            items.append((s["h"], s["w"], name, i))
    items.sort(key=lambda t: (-t[0], t[2], t[3]))
    pos = {}
    x = y = shelf_h = 0
    for h, w, name, i in items:
        if x + w > width:
            x, y, shelf_h = 0, y + shelf_h + 1, 0
        pos[(name, i)] = (x, y)
        x += w + 1
        shelf_h = max(shelf_h, h)
    return pos, y + shelf_h


def encode(seq, color_index, ns, first=None):
    # color_index: colour -> the sequence's own index (0-based); first: the frame its first frame is a change on
    base = 91 - ns
    lines = []
    prev = first
    for px in seq["frames"]:
        syms = []
        for k, c in enumerate(px):
            if prev is not None and c == prev[k]:
                syms.append(0)
            elif c is None:
                syms.append(1)
            else:
                syms.append(2 + color_index[c])
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
        lines.append("".join(out))
        prev = px
    return lines


def decode_check(lines, w, h, palette, ns, first=None):
    base = 91 - ns
    val = {c: i for i, c in enumerate(ALPHABET)}
    prev = first
    frames = []
    for line in lines:
        px = []
        i = 0
        while i < len(line):
            v = val[line[i]]
            i += 1
            run, mul = 1, 1
            while i < len(line) and val[line[i]] >= ns:
                run += (val[line[i]] - ns + 1) * mul
                mul *= base
                i += 1
            for _ in range(run):
                k = len(px)
                px.append(prev[k] if v == 0 else (None if v == 1 else palette[v - 2]))
        assert len(px) == w * h, (len(px), w * h)
        frames.append(px)
        prev = px
    return frames


def main():
    args = sys.argv[1:]
    sheet = atlas_png = None
    if "--sheet" in args:
        k = args.index("--sheet")
        sheet = args[k + 1]
        del args[k:k + 2]
    if "--atlas" in args:
        k = args.index("--atlas")
        atlas_png = args[k + 1]
        del args[k:k + 2]
    log = args[0]
    out = args[1] if len(args) > 1 else None
    seqs = parse(log)
    if not seqs:
        raise SystemExit("no @@LSEQ lines in " + log)
    by_name = dict(seqs)
    groups = {}  # a base sequence -> those based on it (they share its crop)
    for name, s in seqs:
        s["name"] = name
        if s.get("base"):
            if s["base"] not in by_name:
                raise SystemExit("%s: no base sequence %s" % (name, s["base"]))
            groups.setdefault(s["base"], []).append(name)
    boxes = {}
    for root, deps in groups.items():
        members = [by_name[root]] + [by_name[m] for m in deps]
        if len({(m["w"], m["h"], m["ax"], m["ay"]) for m in members}) != 1:
            raise SystemExit("%s: its sequences are not framed alike" % root)
        bs = [bounds(m) for m in members]
        boxes[root] = (min(b[0] for b in bs), max(b[1] for b in bs), min(b[2] for b in bs), max(b[3] for b in bs))
    for name, s in seqs:
        crop(s, boxes.get(s.get("base") or name))
    counts = {}
    for _, s in seqs:
        for px in s["frames"]:
            for c in px:
                if c is not None:
                    counts[c] = counts.get(c, 0) + 1
    palette = sorted(counts, key=lambda c: -counts[c])
    global_index = {c: i for i, c in enumerate(palette)}
    width = 256
    pos, height = pack(seqs, width)
    if height > 256:
        width = 512
        pos, height = pack(seqs, width)
    if height > 1024:
        raise SystemExit("the atlas is %dx%d: over the EditableImage limit" % (width, height))
    total = 0
    body = []
    for name, s in seqs:
        # the sequence's own colours (in the palette's order: the most used first), as indices into the palette
        used = sorted({c for px in s["frames"] for c in px if c is not None}, key=lambda c: global_index[c])
        if len(used) > 78:
            raise SystemExit("%s: too many colours for one-character codes: %d" % (name, len(used)))
        ns = 2 + len(used)
        first = by_name[s["base"]]["frames"][0] if s.get("base") else None
        lines = encode(s, {c: i for i, c in enumerate(used)}, ns, first)
        assert decode_check(lines, s["w"], s["h"], used, ns, first) == s["frames"], name
        total += sum(len(l) for l in lines)
        fr = ", ".join("{ %d, %d }" % pos[(name, i)] for i in range(len(s["frames"])))
        pts = "".join(", %s = { %d, %d }" % (k, v[0], v[1]) for k, v in sorted(s["pts"].items()))
        own = ", ".join(str(global_index[c] + 1) for c in used)
        based = ', base = "%s"' % s["base"] if s.get("base") else ""
        body.append("\t\t%s = { w = %d, h = %d, ax = %d, ay = %d, dur = %s, at = { %s }%s%s, pal = { %s },\n\t\t\tpx = {\n%s\n\t\t\t} },"
                    % (name, s["w"], s["h"], s["ax"], s["ay"], ("%.4f" % s["dur"]).rstrip("0").rstrip("."), fr, pts, based, own,
                       "\n".join('\t\t\t\t"%s",' % l for l in lines)))
    pal = ", ".join("0x%02X%02X%02X" % c for c in palette)
    text = """--!strict
-- GENERATED by tools/preview/gen_loading_art.py from the preview scenario "ploadingart" (tools/preview/loading_art.luau:
-- the island's driftlings, palms, huts, campfire, Tree of Life and boat built by MicroModels
-- and DecorModels and drawn through Pixel/Snapshot, and the hand-made gull, star, wave crest, ember and glint). Do not
-- edit by hand: run `sh tools/preview/loading_art.sh` (tools/README.md).
-- The loading card's scene (LoadingCard, ARCHITECTURE 8.0): one atlas of W x H art px; per sequence its frames' size
-- (w, h), anchor (ax, ay: the feet, a palm's foot, the boat's waterline, art px from the frame's top-left), seconds a
-- frame (dur), each frame's place in the atlas (at), points from the anchor (head: a word or a heart rises there;
-- flame: the embers), the sequence its first frame is a change on (base), its colours (pal: indices into the palette)
-- and its pixels (px: one string a frame, run-length codes over its colours, see gen_loading_art.py; 0 = as the frame
-- before, 1 = clear).
-- stylua: ignore start
return {
	W = %d,
	H = %d,
	palette = { %s },
	seqs = {
%s
	},
}
-- stylua: ignore end
""" % (width, height, pal, "\n".join(body))
    if out:
        open(out, "w", encoding="utf-8").write(text)
    frames = sum(len(s["frames"]) for _, s in seqs)
    print("loading art: %d sequences, %d frames, %d colours, atlas %dx%d, %d code chars, module %d bytes" % (
        len(seqs), frames, len(palette), width, height, total, len(text.encode("utf-8"))))
    if sheet or atlas_png:
        from PIL import Image, ImageDraw
        if atlas_png:
            im = Image.new("RGBA", (width, height), (0, 0, 0, 0))
            for name, s in seqs:
                for i, px in enumerate(s["frames"]):
                    x0, y0 = pos[(name, i)]
                    for k, c in enumerate(px):
                        if c is not None:
                            im.putpixel((x0 + k % s["w"], y0 + k // s["w"]), c + (255,))
            im.resize((width * 3, height * 3), Image.NEAREST).save(atlas_png)
        if sheet:
            Z = 4
            rows = []
            for name, s in seqs:
                rows.append((name, s))
            W = max(12 + len(s["frames"]) * (s["w"] + 2) for _, s in seqs) * Z
            H = sum((s["h"] + 12) for _, s in seqs) * Z
            im = Image.new("RGB", (max(W, 200), H), WALL)
            d = ImageDraw.Draw(im)
            y = 0
            for name, s in rows:
                d.text((4, y * Z + 2), "%s  %dx%d  %d frames  %.3f s" % (name, s["w"], s["h"], len(s["frames"]), s["dur"]), fill=(43, 30, 46))
                y += 10
                for i, px in enumerate(s["frames"]):
                    x0 = 4 + i * (s["w"] + 2)
                    for k, c in enumerate(px):
                        if c is not None:
                            xx, yy = (x0 + k % s["w"]) * Z, (y + k // s["w"]) * Z
                            d.rectangle((xx, yy, xx + Z - 1, yy + Z - 1), fill=c)
                    ax, ay = (x0 + s["ax"]) * Z, (y + s["ay"]) * Z
                    d.rectangle((ax, ay, ax + Z - 1, ay + Z - 1), outline=(0, 160, 255))
                    for _, v in s["pts"].items():
                        px_, py_ = (x0 + s["ax"] + v[0]) * Z, (y + s["ay"] + v[1]) * Z
                        d.rectangle((px_, py_, px_ + Z - 1, py_ + Z - 1), outline=(0, 200, 0))
                y += s["h"] + 2
            im.save(sheet)


if __name__ == "__main__":
    main()
