#!/usr/bin/env python3
# scripts/gen_art.py: regenerates src/client/UI/ArtData.luau, every interface sprite (the island's small icons, the
# arrows, a note, a heart, sparks) from the masks below, and the driftlings' portraits from scripts/portraits.txt (drawn
# from their 3D models: tools/preview/portraits.sh); and src/client/UI/ThumbData.luau, the build catalog's pictures
# from scripts/thumbs.txt (drawn from the pieces' models: tools/preview/thumbs.sh), in a module of their own so ArtData
# stays small. (The world and the driftlings are 3D: Models/*, drawn by the pixel filter with the same outline and
# palette.)
#
#   python3 scripts/gen_art.py [--out src/client/UI/ArtData.luau] [--thumbs-out src/client/UI/ThumbData.luau]
#                              [--png sheet.png] [--zoom 6]
#
# The pixel art rules (GAME_DESIGN 2; the request: "for pixel art, always dont use mixels. use pixel art techniques
# such as anti-aliasing, avoiding jaggies, and avoiding mixels, and use a 1 pixel outline. respect the pixel art
# grid"): every sprite is drawn at its own size, one sprite pixel = one art pixel, never scaled (a smaller or bigger
# thing is its own mask: "icon_x" and its small "mini_x"). A mask gives the silhouette and its colour regions; each
# silhouette is drawn to read on its own (the user: "make sure each sillouhette is distinct enough to tell what the
# sprites are"). This script then
#   * shades the whole silhouette in cel steps, lit from the top left (`cel_tones`): the base tone does most of the
#     work, a 1 px shadow runs along the bottom and right edges (a portrait's belly two), a short light along the
#     upper half of the top-left edges of masses at least 3 px thick; no grain, no speckles, no white glints (the
#     user: the sprites looked "too busy" and "metallic"); the ramps' steps are close and hue-shifted (shadows a
#     little cooler, lights a little warmer);
#   * draws a 1 px ink outline round the silhouette (the 4-neighbours: convex corners come out cut, so no double
#     pixels at the turns) - a mask leaves a 1 px margin for it;
#   * softens the curves inside the outline: a pixel that meets the outline only at a corner goes a step toward the
#     shadow (never a dark speck on the lit side); nothing outside the outline.
# Mask characters: "." empty; an UPPERCASE letter a shaded region (REGIONS: R red, O orange, Y yellow, G green, C cyan,
# B blue, P purple, K pink, N brown, S stone grey, F skin and peach, W white, D dark, M warm basalt, E cream); a lowercase letter or digit a flat colour
# (FLAT, or the sprite's own "flat" map); "#" an ink line inside the sprite.
import argparse, os, sys

# a pixel's character in ArtData and ThumbData (and in scripts/thumbs.txt): its colour's place in the sprite's palette
CHARS = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!$%&*+-/:;<=>?@^_~"

PAL = {
    "ink": 0x2B1E2E,
    # four tones a colour, the base (2) doing most of the work: a shadow (1) a step darker and a little cooler, a light
    # (3) a step lighter and a little warmer, a deep (0) only where a shadow meets the outline on a curve. Close steps
    # and saturated shadows: matte and soft, never a chrome sweep from near black to near white.
    "red0": 0x6B1F48, "red1": 0xB83450, "red2": 0xE8535C, "red3": 0xFF8C72,
    "org0": 0x8A3A2E, "org1": 0xD2652E, "org2": 0xF7963F, "org3": 0xFFC86E,
    "yel0": 0x8F5E24, "yel1": 0xD99A2B, "yel2": 0xFFC93C, "yel3": 0xFFE98A,
    "grn0": 0x1F5650, "grn1": 0x3A8C55, "grn2": 0x6CBF5E, "grn3": 0xAEE07A,
    "cyn0": 0x26558F, "cyn1": 0x3B97C7, "cyn2": 0x6FCFEA, "cyn3": 0xB4F1F0,
    "blu0": 0x2E2F7C, "blu1": 0x4561BA, "blu2": 0x6F98E8, "blu3": 0xA9CFFA,
    "pur0": 0x3A2672, "pur1": 0x6A47AC, "pur2": 0x9B74D8, "pur3": 0xCAA6F0,
    "pnk0": 0x76306B, "pnk1": 0xC2548F, "pnk2": 0xF286B5, "pnk3": 0xFFBACB,
    "brn0": 0x4B2A33, "brn1": 0x8A553A, "brn2": 0xC28A57, "brn3": 0xE9BC7F,
    "gry0": 0x45425A, "gry1": 0x75738C, "gry2": 0xA5A4B5, "gry3": 0xD3D2D8,
    "skn0": 0x8F4C55, "skn1": 0xD18A6D, "skn2": 0xF4C49E, "skn3": 0xFFE3C2,
    "wht0": 0x8D93BF, "wht1": 0xBAC4E2, "wht2": 0xEDF1F7,
    "drk0": 0x2E2433, "drk1": 0x4B3D4E, "drk2": 0x685767, "drk3": 0x8C7886,
    "bas0": 0x3A2D35, "bas1": 0x5A4549, "bas2": 0x7A5E5C, "bas3": 0x9E7D72,
    "crm0": 0xA86E5E, "crm1": 0xDDAE86, "crm2": 0xFBE2BC, "crm3": 0xFFF6E2,  # cream: bellies, muzzles, jaws
    "wht": 0xFFFFFF, "crm": 0xFFF3D9, "blk": 0x3B3442, "plt": 0x463B5C,
}
RAMPS = {
    "R": ["red0", "red1", "red2", "red3"], "O": ["org0", "org1", "org2", "org3"], "Y": ["yel0", "yel1", "yel2", "yel3"],
    "G": ["grn0", "grn1", "grn2", "grn3"], "C": ["cyn0", "cyn1", "cyn2", "cyn3"], "B": ["blu0", "blu1", "blu2", "blu3"],
    "P": ["pur0", "pur1", "pur2", "pur3"], "K": ["pnk0", "pnk1", "pnk2", "pnk3"], "N": ["brn0", "brn1", "brn2", "brn3"],
    "S": ["gry0", "gry1", "gry2", "gry3"], "F": ["skn0", "skn1", "skn2", "skn3"], "W": ["wht0", "wht1", "wht2", "wht"],
    "D": ["drk0", "drk1", "drk2", "drk3"], "M": ["bas0", "bas1", "bas2", "bas3"], "E": ["crm0", "crm1", "crm2", "crm3"],
}
FLAT = {
    "k": "ink", "w": "wht", "r": "red2", "o": "org2", "y": "yel2", "g": "grn2", "c": "cyn2", "b": "blu2", "p": "pnk2",
    "n": "brn1", "s": "gry2", "e": "yel3", "q": "red3", "u": "pur2", "x": "blk", "z": "cyn3", "h": "gry3", "m": "crm",
    "t": "org1", "d": "brn0", "l": "grn1",
}

SPRITES = {}  # name -> dict(rows, flat, shade, outline, recolor)


def S(name, rows, flat=None, shade=True, outline=True, variants=None, pad=False):
    def touches(rs):
        return any(c != "." for c in rs[0] + rs[-1]) or any(r[0] != "." or r[-1] != "." for r in rs)
    if pad or (outline and touches(rows)):  # a 1 px margin all round for the outline
        rows = ["." * (len(rows[0]) + 2)] + ["." + r + "." for r in rows] + ["." * (len(rows[0]) + 2)]
    w = len(rows[0])
    for r in rows:
        if len(r) != w:
            sys.exit("%s: rows of different widths (%d vs %d): %r" % (name, len(r), w, r))
    SPRITES[name] = dict(rows=rows, flat=flat or {}, shade=shade, outline=outline, variants=variants or {})


def rot90(rows):  # a quarter turn clockwise
    h, w = len(rows), len(rows[0])
    return ["".join(rows[h - 1 - y][x] for y in range(h)) for x in range(w)]


def flipx(rows):
    return [r[::-1] for r in rows]


# ---------------------------------------------------------------- the driftlings' portraits, 32 x 32
# The request (2026-11-12): "instead of character sprites for the creatures, can you take their pixellated models in a
# 3/4 angle, and polish them to follow pixel art rules if required?" So a portrait is the driftling's own 3D model
# drawn by the game's picture path (the preview scenario "pportraits": Pixel/Snapshot, the world's palette, toon bands,
# shadows and outline), three quarters turned left, its head and eyes bigger so it reads small ("most of those sprites
# look unreadable. try to tweak them so they look more readable"), fitted to 32 x 32, then tidied to the pixel art rules
# (tools/preview/gen_portraits.py: no half see-through pixels, a 1 px outline with cut corners made again, lone spikes
# and notches gone, the bands' dither settled, creases 1 px, curves softened inside the outline). They come from
# scripts/portraits.txt (sh tools/preview/portraits.sh makes it); the hand-drawn 16 x 16 masks they replace are in
# this file's history, up to commit a4a7760.
PORTRAITS = {}  # "icon_<species>" -> rows of (0xRRGGBB, 1.0) or None


def load_portraits(path):
    if not os.path.exists(path):
        sys.exit("no portraits at %s: run sh tools/preview/portraits.sh" % path)
    cur = None
    with open(path) as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            if line.startswith("portrait "):
                _, sp, w, h = line.split()
                cur = PORTRAITS.setdefault("icon_" + sp, [])
                continue
            cur.append([None if t == "......" else (int(t, 16), 1.0) for t in line.split()])


load_portraits(os.path.join(os.path.dirname(os.path.abspath(__file__)), "portraits.txt"))

# ---------------------------------------------------------------- the build catalog's pictures, 24 x 24
# Every piece in Data/Buildings but the Tree of Life, drawn from its model by the game's picture path from the world's
# camera (the preview scenario "pthumbs": Pixel/Snapshot, the palette, toon bands, shadows and outline; a path or water
# tile as a 2 x 2 block, a fence as a corner, a bridge over a stream, a floating piece on a pond), fitted to 24 x 24 and
# tidied like the portraits (tools/preview/gen_thumbs.py). They come from scripts/thumbs.txt (sh tools/preview/
# thumbs.sh makes it) and go to UI/ThumbData as "thumb_<id>", where PixelSprites finds them by the prefix. No "_sil"
# or "_flash" for them: a card greys a locked piece itself.
THUMBS = {}  # "thumb_<id>" -> rows of (0xRRGGBB, 1.0) or None


def load_thumbs(path):
    if not os.path.exists(path):
        print("no build catalog pictures at %s (sh tools/preview/thumbs.sh makes them): ThumbData is empty" % path)
        return
    cur, pal = None, []
    with open(path) as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            if line.startswith("thumb "):
                _, pid, w, h = line.split()
                cur = THUMBS.setdefault("thumb_" + pid, [])
                continue
            if line.startswith("pal "):
                pal = [int(t, 16) for t in line.split()[1:]]
                continue
            cur.append([None if ch == "." else (pal[CHARS.index(ch)], 1.0) for ch in line])


load_thumbs(os.path.join(os.path.dirname(os.path.abspath(__file__)), "thumbs.txt"))

# ---------------------------------------------------------------- the small icons, 11 x 11 (chips, lists, the path)
SMALL = {
    # what the island has
    "shell": [".........", ".FFFFFFF.", "FFFFFFFFF", "FFjFjFjFF", "FFjFjFjFF", ".FFjjjFF.", "..FFjFF..", "...FFF...", "........."],
    "food": ["....n....", "....nll..", ".RRRnRRR.", "RRRRRRRRR", "RRRRRRRRR", "RRRRRRRRR", ".RRRRRRR.", ".RRRRRRR.", "..RR.RR.."],
    "wood": [".........", "..NNNNyy.", ".NNNNyyyy", ".NNNNytyy", ".NNNNyyyy", "..NNNNyy.", ".........", ".........", "........."],
    "sun": ["....Y....", ".Y..Y..Y.", "..YYYYY..", "..YYYYY..", "YYYYYYYYY", "..YYYYY..", "..YYYYY..", ".Y..Y..Y.", "....Y...."],
    "moon": ["...BBB...", "..BBB....", ".BBB.....", ".BBB.....", ".BBB.....", ".BBB.....", "..BBB....", "...BBB...", "........."],
    "charm": [".........", ".KK...KK.", "KKKK.KKKK", "KKKKKKKKK", "KKKKKKKKK", ".KKKKKKK.", "..KKKKK..", "...KKK...", "....K...."],
    "folk": ["...NNN...", "..NNNNN..", "..NFFFN..", "..FkFkF..", "..FFFFF..", "...FFF...", ".BBBBBBB.", ".BBBBBBB.", "........."],
    "pal": [".........", "..C...C..", ".CCC.CCC.", ".CCCCCCC.", ".CkCCCkC.", ".CCCCCCC.", ".CCCpCCC.", "..CCCCC..", "........."],
    "visitor": ["...YYY...", ".YYYYYYY.", "..FFFFF..", "..FkFkF..", "..FFFFF..", "...FFF...", ".OOOOOOO.", ".OOOOOOO.", "........."],
    # what can be built (the build tray's tabs)
    "home": ["....R....", "...RRR...", "..RRRRR..", ".RRRRRRR.", "RRRRRRRRR", ".mmmmmmm.", ".mnnmmcm.", ".mnnmmmm.", ".mnnmmmm."],
    "nest": [".........", "...WWW...", "..WWWWW..", "..WWWWW..", "NNNWWWNNN", "NNNNNNNNN", ".NdNNNdN.", "..NNNNN..", "........."],
    # the Tree of Life: a round crown with glowing fruit on a short trunk, roots spreading
    "tree": ["..GGGGG..", ".GGGGGGG.", "GGGyGGGGG", "GGGGGGyGG", ".GGGGGGG.", "...NNN...", "...NNN...", "..NNNNN..", ".NN...NN."],
    "train": [".........", ".S.....S.", "SSS...SSS", "SSSxxxSSS", "SSS...SSS", ".S.....S.", ".........", ".........", "........."],
    "boost": ["....G....", "...GGG...", "..GGGGG..", ".GGGGGGG.", "...GGG...", "...GGG...", "...GGG...", "...GGG...", "........."],
    "path": [".........", "SSS......", "SSS.SSS..", "....SSS..", ".SSS.....", ".SSS.SSS.", ".....SSS.", "..SSS....", "..SSS...."],
    "decor": ["..KK.KK..", ".KKKKKKK.", "..KKyKK..", ".KKKKKKK.", "..KK.KK..", "....G....", ".GG.G....", "..GGG.GG.", "....GGG.."],
    # the build catalog's tabs (GAME_DESIGN 4): work (a hammer), fences, water, nature (a pine), fun (a balloon)
    "work": [".........", ".SSSS....", "SSSSSS...", ".SSSSN...", ".....N...", "......N..", ".......N.", "........N", "........."],
    "fence": [".........", "N...N...N", "NNNNNNNNN", "N...N...N", "N...N...N", "NNNNNNNNN", "N...N...N", "N...N...N", "........."],
    "water": [".........", ".........", ".BB...BB.", "BBBB.BBBB", "BBBBBBBBB", ".........", ".BB...BB.", "BBBB.BBBB", "BBBBBBBBB"],
    "nature": ["....G....", "...GGG...", "..GGGGG..", "...GGG...", "..GGGGG..", ".GGGGGGG.", "....N....", "....N....", "........."],
    "fun": ["..RRR....", ".RRRRR...", ".RRRRR...", ".RRRRR...", "..RRR....", "...R.....", "...N.....", "....N....", "...N....."],
    # marks for a route (drawn since the expeditions; kept for the icon set)
    "start": ["..R......", "..RRR....", "..RRRRR..", "..RRR....", "..N......", "..N......", "..N......", ".NNN.....", "........."],
    "loot": ["..N...N..", "...NNN...", "...ooo...", "..NNNNN..", ".NNNNNNN.", ".NNNNNNN.", ".NNNNNNN.", "..NNNNN..", "........."],
    "chest": [".........", ".NNNNNNN.", "NNNNNNNNN", "YYYYYYYYY", "NNNNyNNNN", "NNNNNNNNN", "NNNNNNNNN", ".........", "........."],
    "wild": ["..OO.OO..", "..OO.OO..", "OO.....OO", "OO.OOO.OO", "..OOOOO..", ".OOOOOOO.", ".OOOOOOO.", "..OO.OO..", "........."],
    "rest": ["....O....", "...OO....", "...OYO...", "..OYYYO..", "..OYYYO..", ".N.OOO.N.", "..NNNNN..", ".N.....N.", "........."],
    "boss": [".........", ".Y..Y..Y.", ".YY.Y.YY.", ".YYYYYYY.", ".YrYYYbY.", ".YYYYYYY.", ".........", ".........", "........."],
    "star": ["....Y....", "....Y....", "...YYY...", "YYYYYYYYY", ".YYYYYYY.", "..YYYYY..", "..YY.YY..", ".Y.....Y.", "........."],
    "boat": [".........", "....W....", "....WW...", "....WWW..", "....N....", ".NNNNNNN.", "..NNNNN..", "BBBBBBBBB", "........."],
    # the build tray's search button: a round glass lens in a grey rim, a wooden handle down to the right
    "search": ["..SSS....", ".SCCCS...", "SCCCCCS..", "SCCCCCS..", "SCCCCCS..", ".SCCCSN..", "..SSSNN..", "......NN.", ".......NN"],
    # the music switch: two beamed notes
    "note": ["...WWWWWW", "...WWWWWW", "...W....W", "...W....W", "...W....W", ".WWW..WWW", "WWWW.WWWW", "WWW..WWW.", "........."],
}
SMALL_FLAT = {"shell": {"j": "org1"}}  # a scallop's ribs, meeting at its hinge
for k, rows in SMALL.items():
    S("mini_" + k, rows, flat=SMALL_FLAT.get(k), pad=True)

# ---------------------------------------------------------------- the microgames' overlay: a note, the fuse's spark and bomb, a heart
# (the microgames themselves are 3D now: Models/MicroModels on a stage the pixel filter draws)
S("note", [
    "..........",
    "......KK..",
    "......KKK.",
    "......K.K.",
    "......K...",
    "..KKKKK...",
    ".KKwKKK...",
    ".KKKKKK...",
    "..KKKK....",
    "..........",
])
S("spark_1", [".......", "...y...", "..yey..", ".yeweY.", "..yey..", "...y...", "......."], outline=False, shade=False, flat={"Y": "yel2"})
S("spark_2", [".......", ".y...y.", "..yey..", "..ewe..", "..yey..", ".y...y.", "......."], outline=False, shade=False)
S("spark_3", [".......", "...o...", "...y...", ".oyeyo.", "...y...", "...o...", "......."], outline=False, shade=False)
S("bombfuse", [
    "..........",
    "......N...",
    ".....N....",
    "...DDDD...",
    "..DwDDDD..",
    "..DDDDDD..",
    "..DDDDDD..",
    "...DDDD...",
    "..........",
])
# The tree's eggs (GAME_DESIGN 6), one a rarity, matching their 3D models (Controllers/EggView.LOOK: "color each egg
# differently with different effects to allow players to distinguish easily between egg rarities"): a common egg cream
# with brown freckles, an uncommon one green with a white zigzag band, a rare one sky blue with white stars, an epic one
# purple with pink spots, a legendary one gold with a band of light.
EGG = [
    "....AAAA....",
    "...AAAAAA...",
    "..AAAAxAAA..",
    "..AAAAAAAA..",
    ".AAxxAAAAAA.",
    ".AAAxAAAAAA.",
    "AAAAAAAAxxAA",
    "AAAAAAAAAxAA",
    "AAAAAAAAAAAA",
    "AAxAAAAAAAAA",
    "AAxxAAAxAAAA",
    ".AAAAAAxxAA.",
    ".AAAAAAAAAA.",
    "..AAAAAAAA..",
    "....AAAA....",
]
EGG_BAND = [
    "....AAAA....",
    "...AAAAAA...",
    "..AAAAAAAA..",
    "..AAAAAAAA..",
    ".AAAAAAAAAA.",
    ".AAAAAAAAAA.",
    "AxAAAxAAAxAA",
    "xAxAxAxAxAxA",
    "AAAxAAAxAAAx",
    "AAAAAAAAAAAA",
    "AAAAAAAAAAAA",
    ".AAAAAAAAAA.",
    ".AAAAAAAAAA.",
    "..AAAAAAAA..",
    "....AAAA....",
]
for _r, (_mask, _body, _spot) in enumerate([(EGG, "E", "n"), (EGG_BAND, "G", "w"), (EGG, "B", "w"), (EGG, "P", "p"), (EGG_BAND, "Y", "w")], start=1):
    S("egg_%d" % _r, [row.replace("A", _body).replace("x", _spot) for row in _mask])
# Build mode's puff of dust (Controllers/Puffs): a little cloud that swells, then thins out and breaks up.
S("poof_1", [".......", ".......", "..ww...", ".wwws..", ".wsss..", "..ss...", "......."], outline=False, shade=False)
S("poof_2", [".......", "..ww...", ".wwwws.", "wwwssss", ".wssss.", "..sss..", "......."], outline=False, shade=False)
S("poof_3", [".......", ".w...w.", "w.....s", ".......", "s.....s", ".s...s.", "......."], outline=False, shade=False)
# A rare egg's twinkle (EggView's sparks): a small white star that opens and closes, cyan at its tips.
S("twinkle_1", [".......", ".......", "...c...", "..cwc..", "...c...", ".......", "......."], outline=False, shade=False)
S("twinkle_2", [".......", "...c...", "...w...", ".cwwwc.", "...w...", "...c...", "......."], outline=False, shade=False)
S("heart", [".........", ".KK...KK.", "KKKK.KKKK", "KwKKKKKKK", "KKKKKKKKK", ".KKKKKKK.", "..KKKKK..", "...KKK...", "....K....", "........."])

ARROW = [
    ".............",
    "......W......",
    ".....WWW.....",
    "....WWWWW....",
    "...WWWWWWW...",
    "..WWWWWWWWW..",
    ".WWWWWWWWWWW.",
    "....WWWWW....",
    "....WWWWW....",
    "....WWWWW....",
    "....WWWWW....",
    "....WWWWW....",
    ".............",
]
ARROW_T = [".......", "...W...", "..WWW..", ".WWWWW.", "..WWW..", "..WWW..", "......."]
for nm, rows in (("arrow", ARROW), ("arrow_t", ARROW_T)):
    r = rows
    for d in ("up", "right", "down", "left"):
        S(nm.replace("arrow", "arrow_" + d), r)
        r = rot90(r)


# ---------------------------------------------------------------- the passes
def cel_tones(grid, w, h):
    """The tone of every shaded pixel, for the whole silhouette at once (never region by region: no pillow shading):
    the base (2) everywhere but a 1 px shadow (1) along the bottom and right edges (on a portrait also a second row
    under the belly) and a short light (3) along the upper half of the top-left edges of masses at least 3 px thick.
    No grain or speckle: a material reads from its colour and silhouette, the sprites stay calm."""
    def solid(x, y):
        return 0 <= x < w and 0 <= y < h and grid[y][x] != "."
    big = w >= 13 and h >= 13
    tone = [[2] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            if not solid(x, y):
                continue
            shadow = not solid(x + 1, y) or not solid(x, y + 1) or not solid(x + 1, y + 1)
            if big and not shadow and not solid(x, y + 2) and not solid(x + 1, y + 2):
                shadow = True
            if shadow:
                tone[y][x] = 1
                continue
            # the light: a top or left edge, facing the top left, on a mass thick enough to hold it
            top, left = not solid(x, y - 1), not solid(x - 1, y)
            if not (top or left) or solid(x - 1, y - 1) or not (solid(x + 1, y + 1) and solid(x + 2, y + 2)):
                continue
            if top:  # the left half of this row's run
                a = x
                while solid(a - 1, y):
                    a -= 1
                b = x
                while solid(b + 1, y):
                    b += 1
                if x > a + (b - a) * 0.5:
                    continue
            if left and not top:  # the upper half of this column's run
                c = y
                while solid(x, c - 1):
                    c -= 1
                d = y
                while solid(x, d + 1):
                    d += 1
                if y > c + (d - c) * 0.5:
                    continue
            tone[y][x] = 3
    return tone


def build(name, spec, recolor=None):
    rows = spec["rows"]
    h, w = len(rows), len(rows[0])
    grid = [list(r) for r in rows]
    if recolor:
        grid = [[recolor.get(c, c) if c.isupper() else c for c in r] for r in grid]
    flat = dict(FLAT)
    flat.update(spec["flat"])
    if recolor:
        for k, v in recolor.items():
            if not k.isupper():
                flat[k] = v
    px = [[None] * w for _ in range(h)]  # (hex, alpha)
    solid = [[grid[y][x] != "." for x in range(w)] for y in range(h)]
    tones = cel_tones(grid, w, h)
    for y in range(h):
        for x in range(w):
            c = grid[y][x]
            if c == ".":
                continue
            if c == "#":
                px[y][x] = (PAL["ink"], 1.0)
            elif c.isupper():
                ramp = RAMPS.get(c)
                if ramp is None:
                    sys.exit("%s: no ramp for %r" % (name, c))
                t = tones[y][x] if spec["shade"] else 2
                px[y][x] = (PAL[ramp[t]], 1.0)
            else:
                key = flat.get(c)
                if key is None:
                    sys.exit("%s: no colour for %r" % (name, c))
                px[y][x] = (PAL[key], 1.0)
    if spec["outline"]:
        outl = [[False] * w for _ in range(h)]
        for y in range(h):
            for x in range(w):
                if solid[y][x]:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and solid[ny][nx]:
                        outl[y][x] = True
        for y in range(h):
            for x in range(w):
                if solid[y][x] and (x in (0, w - 1) or y in (0, h - 1)):
                    sys.exit("%s: a solid pixel on the border at %d,%d: leave a 1 px margin for the outline" % (name, x, y))
        # inner anti-aliasing: a shaded region pixel that meets the outline only at a corner goes a tone down
        if spec["shade"]:
            for y in range(1, h - 1):
                for x in range(1, w - 1):
                    c = grid[y][x]
                    if not c.isupper():
                        continue
                    orth = any(outl[y + dy][x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                    if orth:
                        continue
                    diag = [(dx, dy) for dx, dy in ((1, 1), (-1, 1), (1, -1), (-1, -1)) if outl[y + dy][x + dx]]
                    if not diag:
                        continue
                    # a step softer toward the outline, never a dark speck on the lit side: a light pixel down to
                    # the base, a base pixel to the shadow where the curve turns away from the light, a shadow
                    # pixel deep only at the bottom right
                    t = tones[y][x]
                    if t == 3:
                        t = 2
                    elif t == 2 and any(d != (-1, -1) for d in diag):
                        t = 1
                    elif t == 1 and (1, 1) in diag:
                        t = 0
                    px[y][x] = (PAL[RAMPS[c][t]], 1.0)
        for y in range(h):
            for x in range(w):
                if outl[y][x]:
                    px[y][x] = (PAL["ink"], 1.0)
        # (no anti-aliasing outside the outline: the silhouette stays crisp)
    return px


def pad_to(px, W, H):  # a sprite on a bigger canvas, bottom centre (an animation's frames share one size)
    h, w = len(px), len(px[0])
    ox, oy = (W - w) // 2, H - h
    return [[px[y - oy][x - ox] if 0 <= x - ox < w and 0 <= y - oy < h else None for x in range(W)] for y in range(H)]


def all_sprites():
    out = {}
    for name, rows in PORTRAITS.items():
        out[name] = rows
    for name, spec in SPRITES.items():
        out[name] = build(name, spec)
        for vname, rec in spec["variants"].items():
            out[name + "_" + vname] = build(name, spec, rec)
    # an animation's frames (name_1, name_2, ...) on one canvas
    groups = {}
    for name in out:
        base, _, k = name.rpartition("_")
        if k.isdigit() and base:
            groups.setdefault(base, []).append(name)
    for base, names in groups.items():
        W = max(len(out[n][0]) for n in names)
        H = max(len(out[n]) for n in names)
        for n in names:
            out[n] = pad_to(out[n], W, H)
    for name in list(out):
        if name.endswith("_alt"):
            continue
        # a white flash (the fuse's bomb blinking) for the overlay's sprites, a dark silhouette (not found yet) for the
        # icons: the same outline
        if not (name.startswith(("icon_", "mini_"))):
            flash = [[None if p is None else ((PAL["wht"], 1.0) if p[1] == 1.0 and p[0] != PAL["ink"] else p) for p in r] for r in out[name]]
            out[name + "_flash"] = flash
        if name.startswith(("icon_", "mini_")):
            sil = [[None if p is None else ((PAL["ink"], 0.55) if p[1] == 1.0 and p[0] != PAL["ink"] else p) for p in r] for r in out[name]]
            out[name + "_sil"] = sil
    return out



ART_HEAD = ["-- GENERATED by scripts/gen_art.py: do not edit (change the masks there and run it). Every interface sprite at its",
            "-- own size, one character a pixel: \".\" clear, else an index into `pal` (0xRRGGBB) with its `alpha` (0..1).",
            "-- docs/ARCHITECTURE.md 10.10; the pixel art rules: GAME_DESIGN 2."]
THUMB_HEAD = ["-- GENERATED by scripts/gen_art.py from scripts/thumbs.txt: do not edit (sh tools/preview/thumbs.sh draws them again",
              "-- from the models). The build catalog's pictures, \"thumb_<id>\", 24 x 24, in UI/ArtData's format: one character a",
              "-- pixel, \".\" clear, else an index into `pal` (0xRRGGBB) with its `alpha` (0..1). Drawn with UI/PixelSprites.",
              "-- docs/ARCHITECTURE.md 10.10; the pixel art rules: GAME_DESIGN 2."]


def emit(sprites, path, head=ART_HEAD):
    L = ["--!strict"] + head + [
         "export type SpriteData = { w: number, h: number, px: string, pal: { number }, alpha: { number } }",
         "",
         "local DATA: { [string]: SpriteData } = {"]
    for name in sorted(sprites):
        px = sprites[name]
        h, w = len(px), len(px[0])
        pal, idx = [], {}
        rows = []
        for r in px:
            s = []
            for p in r:
                if p is None:
                    s.append(".")
                    continue
                if p not in idx:
                    idx[p] = len(pal)
                    pal.append(p)
                if idx[p] >= len(CHARS):
                    sys.exit("%s: too many colours" % name)
                s.append(CHARS[idx[p]])
            rows.append("".join(s))
        L.append("\t[%r] = {" % name)
        L.append("\t\tw = %d, h = %d," % (w, h))
        L.append("\t\tpx = \"%s\"," % "".join(rows))
        L.append("\t\tpal = { %s }," % ", ".join("0x%06X" % p[0] for p in pal))
        L.append("\t\talpha = { %s }," % ", ".join(("%g" % p[1]) for p in pal))
        L.append("\t},")
    L.append("}")
    L.append("")
    L.append("return table.freeze(DATA)")
    L.append("")
    with open(path, "w") as f:
        f.write("\n".join(L).replace("['", "[\"").replace("']", "\"]"))


def png(sprites, path, zoom):
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        sys.exit("--png needs Pillow")
    names = sorted(n for n in sprites if not n.endswith("_flash") and not n.endswith("_sil"))
    cell = 34
    cols = 12
    rows = (len(names) + cols - 1) // cols
    bg = (0x2F, 0x27, 0x40)
    img = Image.new("RGB", (cols * cell * zoom, rows * (cell + 6) * zoom), bg)
    d = ImageDraw.Draw(img)
    for i, n in enumerate(names):
        px = sprites[n]
        ox, oy = (i % cols) * cell * zoom, (i // cols) * (cell + 6) * zoom
        for y, r in enumerate(px):
            for x, p in enumerate(r):
                if p is None:
                    continue
                c, a = p
                rgb = ((c >> 16) & 255, (c >> 8) & 255, c & 255)
                mix = tuple(int(bg[k] * (1 - a) + rgb[k] * a) for k in range(3))
                d.rectangle([ox + x * zoom, oy + y * zoom, ox + (x + 1) * zoom - 1, oy + (y + 1) * zoom - 1], fill=mix)
        d.text((ox, oy + (cell + 1) * zoom), n[:18], fill=(200, 190, 220))
    img.save(path)


def main():
    ap = argparse.ArgumentParser()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap.add_argument("--out", default=os.path.join(root, "src", "client", "UI", "ArtData.luau"))
    ap.add_argument("--thumbs-out", default=os.path.join(root, "src", "client", "UI", "ThumbData.luau"))
    ap.add_argument("--png", default=None)
    ap.add_argument("--zoom", type=int, default=6)
    a = ap.parse_args()
    sprites = all_sprites()
    emit(sprites, a.out)
    emit(THUMBS, a.thumbs_out, THUMB_HEAD)
    if a.png:
        png(sprites, a.png, a.zoom)
    print("%d sprites -> %s" % (len(sprites), a.out))
    print("%d pictures -> %s" % (len(THUMBS), a.thumbs_out))


if __name__ == "__main__":
    main()
