#!/usr/bin/env python3
# scripts/gen_art.py: regenerates src/client/UI/ArtData.luau, every interface sprite (the driftlings' portraits, the
# island's small icons, the arrows, a note, a heart, sparks), from the masks below. (The world, the driftlings and the
# expeditions are 3D: Models/*, drawn by the pixel filter with the same outline and palette.)
#
#   python3 scripts/gen_art.py [--out src/client/UI/ArtData.luau] [--png sheet.png] [--zoom 6]
#
# The pixel art rules (GAME_DESIGN 2; the request: "for pixel art, always dont use mixels. use pixel art techniques
# such as anti-aliasing, avoiding jaggies, and avoiding mixels, and use a 1 pixel outline. respect the pixel art
# grid"): every sprite is drawn at its own size, one sprite pixel = one art pixel, never scaled (a smaller or bigger
# thing is its own mask: "icon_x" and its small "mini_x"). A mask gives the silhouette and its colour regions; this
# script then
#   * shades each region with its four-tone ramp, the light from the top left: the edge facing the light one tone up,
#     the edges away from it one and two tones down (a 1 px feature stays mid-tone), and a region's pixels that touch
#     the outline only at a corner one tone down (inner anti-aliasing on curves);
#   * draws a 1 px ink outline round the silhouette (the 4-neighbours: convex corners come out cut, so no double
#     pixels at the turns) - a mask leaves a 1 px margin for it;
#   * anti-aliases the outline's steps: an empty pixel touching the outline on one side and one end gets 35% ink.
# Mask characters: "." empty; an UPPERCASE letter a shaded region (REGIONS: R red, O orange, Y yellow, G green, C cyan,
# B blue, P purple, K pink, N brown, S steel grey, F skin, W white, D dark); a lowercase letter or digit a flat colour
# (FLAT, or the sprite's own "flat" map); "#" an ink line inside the sprite.
import argparse, os, sys

PAL = {
    "ink": 0x2B1E2E,
    "red0": 0x6E1F33, "red1": 0xB0304A, "red2": 0xE8465B, "red3": 0xFF8A8F,
    "org0": 0x8A3E1C, "org1": 0xD06A2E, "org2": 0xFFA553, "org3": 0xFFD39A,
    "yel0": 0x8F6410, "yel1": 0xD9A21E, "yel2": 0xFFCB30, "yel3": 0xFFF0A0,
    "grn0": 0x24563A, "grn1": 0x3F8F4F, "grn2": 0x6CC06A, "grn3": 0xB4EA9E,
    "cyn0": 0x1A5A73, "cyn1": 0x2F92B5, "cyn2": 0x6FD3F2, "cyn3": 0xC9F2FF,
    "blu0": 0x24346E, "blu1": 0x3E5CB8, "blu2": 0x70A9EA, "blu3": 0xC0DCFF,
    "pur0": 0x3E2A66, "pur1": 0x6A4BA8, "pur2": 0xA77DD7, "pur3": 0xDCC6F7,
    "pnk0": 0x8C3A63, "pnk1": 0xC9608F, "pnk2": 0xFFA7CA, "pnk3": 0xFFDCEB,
    "brn0": 0x4A2E1E, "brn1": 0x8B5B3D, "brn2": 0xC88D5C, "brn3": 0xEDC293,
    "gry0": 0x3E4554, "gry1": 0x6E7888, "gry2": 0xAEB8C5, "gry3": 0xE4E9EF,
    "skn0": 0x8A5A3C, "skn1": 0xCB9063, "skn2": 0xF1C39B, "skn3": 0xFFE4CC,
    "wht": 0xFFFFFF, "crm": 0xFFF3D9, "blk": 0x3B3442, "plt": 0x463B5C,
}
RAMPS = {
    "R": ["red0", "red1", "red2", "red3"], "O": ["org0", "org1", "org2", "org3"], "Y": ["yel0", "yel1", "yel2", "yel3"],
    "G": ["grn0", "grn1", "grn2", "grn3"], "C": ["cyn0", "cyn1", "cyn2", "cyn3"], "B": ["blu0", "blu1", "blu2", "blu3"],
    "P": ["pur0", "pur1", "pur2", "pur3"], "K": ["pnk0", "pnk1", "pnk2", "pnk3"], "N": ["brn0", "brn1", "brn2", "brn3"],
    "S": ["gry0", "gry1", "gry2", "gry3"], "F": ["skn0", "skn1", "skn2", "skn3"], "W": ["gry1", "gry2", "gry3", "wht"],
    "D": ["ink", "blk", "plt", "gry0"],
}
FLAT = {
    "k": "ink", "w": "wht", "r": "red2", "o": "org2", "y": "yel2", "g": "grn2", "c": "cyn2", "b": "blu2", "p": "pnk2",
    "n": "brn1", "s": "gry2", "e": "yel3", "q": "red3", "u": "pur2", "x": "blk", "z": "cyn3", "h": "gry3", "m": "crm",
}
AA_ALPHA = 0.35

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


# ---------------------------------------------------------------- the driftlings' portraits, 16 x 16
# One mask a body shape (Data/Creatures shape): "A" the body, "Z" the accent, "k" an eye, "w" a highlight. Each
# species is its shape in its own two ramps (CREATURE_RAMPS), so "icon_<species>" in the Index, the Driftlings panel
# and the battle's bars.
SHAPES = {
    "blob": [
        "................",
        "................",
        "................",
        ".....AAAAAA.....",
        "....AAAAAAAA....",
        "...AAwAAAAAAA...",
        "...AAAAAAAAAA...",
        "..AAAAkAAkAAAA..",
        "..AAAAkAAkAAAA..",
        "..AAAAAAAAAAAA..",
        "..AAAAAZZAAAAA..",
        "..AAAAAAAAAAAA..",
        "...AAAAAAAAAA...",
        "....ZZZZZZZZ....",
        "................",
        "................",
    ],
    "crab": [
        "................",
        ".ZZZ........ZZZ.",
        ".Z.ZZ......ZZ.Z.",
        ".ZZZZ......ZZZZ.",
        "..ZZ..k..k..ZZ..",
        "...Z..A..A..Z...",
        "...ZAAAAAAAAZ...",
        "...AAAAAAAAAA...",
        "..AAwAAAAAAAAA..",
        "..AAAAAAAAAAAA..",
        "..AAAAZZZZAAAA..",
        "...AAAAAAAAAA...",
        "..Z.Z.Z..Z.Z.Z..",
        "..Z.Z.Z..Z.Z.Z..",
        "................",
        "................",
    ],
    "bird": [
        "................",
        "................",
        "..........AAA...",
        ".........AAAAA..",
        ".........AkAAZZ.",
        ".........AAAAZ..",
        "..Z.....AAAAA...",
        "..ZZ..AAAAAAA...",
        "...ZZAAAZZZAA...",
        "...ZAAAAAZZZA...",
        "..ZZ.AAAAAAAA...",
        "..Z...AAAAAA....",
        ".........ZZ.....",
        "................",
        "................",
        "................",
    ],
    "bun": [
        "................",
        "....AA....AA....",
        "...AZZA..AZZA...",
        "...AZZA..AZZA...",
        "...AZZA..AZZA...",
        "...AAAAAAAAAA...",
        "..AAAAAAAAAAAA..",
        "..AwAAAAAAAAAA..",
        "..AAAkAAAAkAAA..",
        "..AAAAAAAAAAAA..",
        "..AAAAAZZAAAAA..",
        "...AAAAAAAAAA...",
        "....AAAAAAAA....",
        "....ZZ....ZZ....",
        "................",
        "................",
    ],
    "lizard": [
        "................",
        "................",
        "................",
        "........ZZZ.....",
        ".......ZAAAA....",
        "......ZAAAkAA...",
        "......AAAAAAAAA.",
        ".....AAAAAAAA...",
        "..AAAAAAwAAA....",
        ".AAAAAAAAAAA....",
        ".AA.AZAAAZAA....",
        ".AA..AA...AA....",
        "..AA............",
        "...AAA..........",
        "................",
        "................",
    ],
    "owl": [
        "................",
        "...Z........Z...",
        "...ZZ......ZZ...",
        "...AAAAAAAAAA...",
        "..AAAAAAAAAAAA..",
        "..AwwwAAAAwwwA..",
        "..AwkwAAAAwkwA..",
        "..AwwwAZZAwwwA..",
        "..AAAAAAZAAAAA..",
        "..AAZAAAAAAZAA..",
        "..AZAZAAAAZAZA..",
        "...AAAAAAAAAA...",
        "....AAAAAAAA....",
        "....ZZ....ZZ....",
        "................",
        "................",
    ],
    "pup": [
        "................",
        "................",
        "..ZZ........ZZ..",
        "..ZAA......AAZ..",
        "..ZAAA....AAAZ..",
        "...AAAAAAAAAA...",
        "..AAAAAAAAAAAA..",
        "..AwAkAAAAkAAA..",
        "..AAAkAAAAkAAA..",
        "..AAAAAAAAAAAA..",
        "...AAZZkkZZAA...",
        "....AZZZZZZA....",
        ".....AAAAAA.....",
        "................",
        "................",
        "................",
    ],
    "mole": [
        "................",
        "................",
        "................",
        ".....AAAAAA.....",
        "....AAAAAAAA....",
        "...AwAAAAAAAA...",
        "...AAkAAAAkAA...",
        "..AAAAAZZAAAAA..",
        "..AAAAAZZAAAAA..",
        ".ZZAAAAAAAAAAZZ.",
        ".ZZZAAAAAAAAZZZ.",
        "..Z.AAAAAAAA.Z..",
        "....AAAAAAAA....",
        ".....ZZ..ZZ.....",
        "................",
        "................",
    ],
    "bat": [
        "................",
        "................",
        "................",
        "......A..A......",
        "......AAAA......",
        ".Z...AkAAkA...Z.",
        ".ZZ..AAAAAA..ZZ.",
        ".ZZZAAAZZAAAZZZ.",
        ".ZZZZAAAAAAZZZZ.",
        ".ZZZZZAAAAZZZZZ.",
        ".Z.ZZ.AAAA.ZZ.Z.",
        "......A..A......",
        "................",
        "................",
        "................",
        "................",
    ],
    "yeti": [
        "................",
        "................",
        ".....AAAAAA.....",
        "....AAAAAAAA....",
        "...AAZZZZZZAA...",
        "...AAZkZZkZAA...",
        "..AAAZZZZZZAAA..",
        ".AAAAAZZZZAAAAA.",
        ".AA.AAAAAAAA.AA.",
        ".AA.AAAAAAAA.AA.",
        "....AAAAAAAA....",
        "....AAA..AAA....",
        "....AAA..AAA....",
        "................",
        "................",
        "................",
    ],
    "seal": [
        "................",
        "................",
        "................",
        ".........AAAA...",
        "........AAAAAA..",
        "........AAkAAAZ.",
        "........AAAAAA..",
        "......AAAAAAA...",
        "....AAAAwwAA....",
        "...AAAAAAAAA....",
        "..ZAAAAAAAAAZ...",
        ".ZZ.AAAAAAAA.ZZ.",
        "................",
        "................",
        "................",
        "................",
    ],
    "sprite": [
        "................",
        ".......A........",
        ".......A........",
        "......AAA.......",
        ".A...AAAAA...A..",
        "..AAAAAAAAAAA...",
        "...AAkAAAkAA....",
        "....AAAAAAA.....",
        "...AAAZZZAAA....",
        "..AAAAAAAAAAA...",
        ".A...AAAAA...A..",
        "......AAA.......",
        ".......A........",
        "................",
        "................",
        "................",
    ],
    "jelly": [
        "................",
        "................",
        ".....AAAAAA.....",
        "....AAwwAAAA....",
        "...AAwAAAAAAA...",
        "...AAAAAAAAAA...",
        "..AAAkAAAAkAAA..",
        "..AAAAAZZAAAAA..",
        "..ZZZZZZZZZZZZ..",
        "...Z..Z..Z..Z...",
        "...Z..Z..Z..Z...",
        "..Z..Z..Z..Z....",
        "..Z..Z..Z..Z....",
        "................",
        "................",
        "................",
    ],
    "wyrm": [
        "................",
        "..........AAA...",
        ".........AAAAA..",
        "........ZAkAAAZ.",
        "........ZAAAAZ..",
        ".........AAAA...",
        "....AAA..AAZ....",
        "...AAAAAAAAZ....",
        "..AAZ.AAAAZ.....",
        "..AZ...AAZ......",
        "..AAZ...........",
        "...AAAA.........",
        "....ZZ..........",
        "................",
        "................",
        "................",
    ],
}
# species -> (shape, body ramp, accent ramp): Data/Creatures' shapes, ramps near their 3D colours
CREATURE_ICONS = {
    "pebblit": ("blob", "S", "D"), "clawdle": ("crab", "R", "O"), "gullfin": ("bird", "W", "B"),
    "mossbun": ("bun", "G", "K"), "frondle": ("lizard", "G", "Y"), "twiggle": ("owl", "N", "O"),
    "emberpup": ("pup", "O", "Y"), "magmole": ("mole", "D", "O"), "scorchwing": ("bat", "P", "O"),
    "snowpuff": ("yeti", "W", "C"), "floe": ("seal", "C", "W"), "frostling": ("sprite", "C", "Y"),
    "lumajelly": ("jelly", "K", "P"), "novafox": ("pup", "Y", "P"), "tidewyrm": ("wyrm", "B", "C"),
}
for sp, (shape, body, accent) in CREATURE_ICONS.items():
    rows = [r.replace("A", body).replace("Z", accent) for r in SHAPES[shape]]
    S("icon_" + sp, rows)

# ---------------------------------------------------------------- the small icons, 11 x 11 (chips, lists, the path)
SMALL = {
    # what the island has
    "shell": [".........", "...YYY...", "..YoYoY..", ".YoYoYoY.", ".YoYoYoY.", ".YYoYoYY.", "..YYYYY..", "...YYY...", "........."],
    "food": ["....g....", "...Ng....", "..RRNRR..", ".RRRRRRR.", ".RwRRRRR.", ".RRRRRRR.", ".RRRRRRR.", "..RRRRR..", "...R.R..."],
    "wood": [".........", ".........", "..NNNNYY.", ".NNNNYoYY", ".NnNNYooY", ".NNNNYoYY", "..NNNNYY.", ".........", "........."],
    "sun": ["....Y....", ".Y..Y..Y.", "..YYYYY..", "..YYwYY..", "YYYYYYYYY", "..YYYYY..", "..YYYYY..", ".Y..Y..Y.", "....Y...."],
    "moon": [".........", "...BBB...", "..BB.....", ".BBB.....", ".BBB.....", ".BBB.....", "..BB.....", "...BBB...", "........."],
    "charm": [".........", ".KK...KK.", "KKKK.KKKK", "KwKKKKKKK", "KKKKKKKKK", ".KKKKKKK.", "..KKKKK..", "...KKK...", "....K...."],
    "folk": ["...NNN...", "..NNNNN..", "..NFFFN..", "..FkFkF..", "..FFFFF..", "...FFF...", ".BBBBBBB.", ".BBBBBBB.", "........."],
    "pal": [".........", "..C...C..", ".CCC.CCC.", ".CCCCCCC.", ".CkCCCkC.", ".CCCCCCC.", ".CCCpCCC.", "..CCCCC..", "........."],
    "visitor": ["...YYY...", "..YYYYY..", "..FFFFF..", "..FkFkF..", "..FFFFF..", "...FFF...", ".OOOOOOO.", ".OOOOOOO.", "........."],
    # what can be built (the build tray's tabs)
    "home": ["....R....", "...RRR...", "..RRRRR..", ".RRRRRRR.", "..NNNNN..", "..NNkNN..", "..NNkNN..", ".........", "........."],
    "nest": [".........", "...WWW...", "..WWWWW..", ".NNWWWNN.", "NNnNNNnNN", ".NNNNNNN.", "..NNNNN..", ".........", "........."],
    "train": [".........", ".SS...SS.", ".SS...SS.", ".SSDDDSS.", ".SS...SS.", ".SS...SS.", ".........", ".........", "........."],
    "decor": ["....G....", "...GGG...", "..GGKGG..", "...GGG...", "....N....", "..GGNGG..", "...GNG...", "....N....", "........."],
    # the expedition's path
    "start": ["..R......", "..RRR....", "..RRRRR..", "..RRR....", "..N......", "..N......", "..N......", ".NNN.....", "........."],
    "loot": ["....N....", "...NNN...", "....N....", "..OOOOO..", ".OOOOOOO.", ".OwOOOOO.", ".OOOOOOO.", "..OOOOO..", "........."],
    "chest": [".........", "..NNNNN..", ".NNNNNNN.", ".YYYYYYY.", ".NNNyNNN.", ".NNNNNNN.", ".NNNNNNN.", ".........", "........."],
    "wild": ["..O...O..", ".OOO.OOO.", "..O...O..", "O..OOO..O", "..OOOOO..", ".OOOOOOO.", ".OOOOOOO.", "..OO.OO..", "........."],
    "rest": ["....O....", "...OYO...", "...OYO...", "..OYYYO..", "..OYwYO..", ".NN...NN.", "..NNNNN..", ".NN...NN.", "........."],
    "boss": [".........", ".Y..Y..Y.", ".YY.Y.YY.", ".YYYYYYY.", ".YRYYYBY.", ".YYYYYYY.", ".........", ".........", "........."],
    "star": ["....Y....", "....Y....", "...YYY...", "YYYYYYYYY", ".YYYYYYY.", "..YYYYY..", "..YY.YY..", ".Y.....Y.", "........."],
    "boat": [".........", "....W....", "....WW...", "....WWW..", "....N....", ".NNNNNNN.", "..NNNNN..", "BBBBBBBBB", "........."],
}
for k, rows in SMALL.items():
    S("mini_" + k, rows, pad=True)

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
def tone_of(grid, x, y, letter, w, h):
    def out(dx, dy):
        nx, ny = x + dx, y + dy
        return not (0 <= nx < w and 0 <= ny < h) or grid[ny][nx] != letter
    tl = out(-1, 0) or out(0, -1)
    br = out(1, 0) or out(0, 1)
    if tl and br:
        return 2
    if tl:
        return 3
    if br:
        return 0 if (out(1, 0) and out(0, 1)) else 1
    # a second shadow band two pixels in from the bottom right on big regions
    if out(2, 0) or out(0, 2):
        return 1 if (out(2, 0) and out(0, 2)) or out(1, 1) else 2
    return 2


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
                t = tone_of(grid, x, y, c, w, h) if spec["shade"] else 2
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
                    diag = sum(1 for dx, dy in ((1, 1), (-1, 1), (1, -1), (-1, -1)) if outl[y + dy][x + dx])
                    if not orth and diag >= 1:
                        ramp = RAMPS[c]
                        cur = ramp.index(next(k for k in ramp if PAL[k] == px[y][x][0])) if any(PAL[k] == px[y][x][0] for k in ramp) else 2
                        px[y][x] = (PAL[ramp[max(0, cur - 1)]], 1.0)
        for y in range(h):
            for x in range(w):
                if outl[y][x]:
                    px[y][x] = (PAL["ink"], 1.0)
        # outer anti-aliasing: an empty pixel with outline on one side and one end (a step) gets a faint ink
        for y in range(h):
            for x in range(w):
                if px[y][x] is not None:
                    continue
                hor = any(0 <= x + dx < w and outl[y][x + dx] for dx in (-1, 1))
                ver = any(0 <= y + dy < h and outl[y + dy][x] for dy in (-1, 1))
                if hor and ver:
                    px[y][x] = (PAL["ink"], AA_ALPHA)
    return px


def pad_to(px, W, H):  # a sprite on a bigger canvas, bottom centre (an animation's frames share one size)
    h, w = len(px), len(px[0])
    ox, oy = (W - w) // 2, H - h
    return [[px[y - oy][x - ox] if 0 <= x - ox < w and 0 <= y - oy < h else None for x in range(W)] for y in range(H)]


def all_sprites():
    out = {}
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
        if not (name.startswith("icon_") or name.startswith("mini_")):
            flash = [[None if p is None else ((PAL["wht"], 1.0) if p[1] == 1.0 and p[0] != PAL["ink"] else p) for p in r] for r in out[name]]
            out[name + "_flash"] = flash
        if name.startswith("icon_") or name.startswith("mini_"):
            sil = [[None if p is None else ((PAL["ink"], 0.55) if p[1] == 1.0 and p[0] != PAL["ink"] else p) for p in r] for r in out[name]]
            out[name + "_sil"] = sil
    return out


CHARS = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!$%&*+-/:;<=>?@^_~"


def emit(sprites, path):
    L = ["--!strict",
         "-- GENERATED by scripts/gen_art.py: do not edit (change the masks there and run it). Every interface sprite at its",
         "-- own size, one character a pixel: \".\" clear, else an index into `pal` (0xRRGGBB) with its `alpha` (0..1).",
         "-- docs/ARCHITECTURE.md 10.9; the pixel art rules: GAME_DESIGN 2.",
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
    ap.add_argument("--png", default=None)
    ap.add_argument("--zoom", type=int, default=6)
    a = ap.parse_args()
    sprites = all_sprites()
    emit(sprites, a.out)
    if a.png:
        png(sprites, a.png, a.zoom)
    print("%d sprites -> %s" % (len(sprites), a.out))


if __name__ == "__main__":
    main()
