#!/usr/bin/env python3
"""An animated GIF of consecutive preview frames (the loading card's scene: scenario "ploadinggif").

Usage: make_gif.py <outdir> <prefix> <device> [fps] [scale]
Reads <outdir>/<prefix>_<NNN>_<device>.png in order and writes <outdir>/<prefix>_<device>.gif (fps default 12, scale
default 1: the device's own size; 0.5 halves it, nearest-neighbour)."""
import glob
import os
import sys

from PIL import Image


def main():
    out, prefix, device = sys.argv[1], sys.argv[2], sys.argv[3]
    fps = float(sys.argv[4]) if len(sys.argv) > 4 else 12
    scale = float(sys.argv[5]) if len(sys.argv) > 5 else 1
    names = sorted(glob.glob(os.path.join(out, "%s_[0-9][0-9][0-9]_%s.png" % (prefix, device))))
    if not names:
        raise SystemExit("no frames %s_NNN_%s.png in %s" % (prefix, device, out))
    frames = []
    for n in names:
        im = Image.open(n).convert("RGB")
        if scale != 1:
            im = im.resize((int(im.width * scale), int(im.height * scale)), Image.NEAREST)
        frames.append(im.quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE))
    path = os.path.join(out, "%s_%s.gif" % (prefix, device))
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=int(round(1000 / fps)), loop=0, optimize=False, disposal=1)
    print("%s: %d frames, %d x %d, %.1f s" % (path, len(frames), frames[0].width, frames[0].height, len(frames) / fps))


if __name__ == "__main__":
    main()
