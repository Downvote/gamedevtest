#!/usr/bin/env python3
# scripts/gen_art.py: regenerates src/client/UI/ArtData.luau, every interface sprite (the ideas' icons, the
# microgames' things), from the masks below.
#
#   python3 scripts/gen_art.py [--out src/client/UI/ArtData.luau] [--png sheet.png] [--zoom 6]
#
# The pixel art rules (GAME_DESIGN 2; the request: "for pixel art, always dont use mixels. use pixel art techniques
# such as anti-aliasing, avoiding jaggies, and avoiding mixels, and use a 1 pixel outline. respect the pixel art
# grid"): every sprite is drawn at its own size, one sprite pixel = one art pixel, never scaled (a smaller or bigger
# thing is its own mask: "coin" and "coin_t" for Tiny). A mask gives the silhouette and its colour regions; this
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


# ---------------------------------------------------------------- the ideas' icons, 16 x 16
S("icon_action", [
    "................",
    "..........YYY...",
    ".........YYYY...",
    "........YYYY....",
    ".......YYYY.....",
    "......YYYY......",
    ".....YYYYYYYYY..",
    "....YYYYYYYYYY..",
    "...YYYYYYYYYY...",
    "........YYYY....",
    ".......YYYY.....",
    "......YYYY......",
    ".....YYY........",
    "....YYY.........",
    "....YY..........",
    "................",
])
S("icon_puzzle", [
    "................",
    "......BBB.......",
    ".....BBBBB......",
    ".....BBBBB......",
    "..BBBBBBBBBBB...",
    "..BBBBBBBBBBB...",
    "...BBBBBBBBBBB..",
    ".....BBBBBBBBBB.",
    ".....BBBBBBBBBB.",
    "...BBBBBBBBBBB..",
    "..BBBBBBBBBBB...",
    "..BBBBBBBBBBB...",
    "..BBBBBBBBBBB...",
    "..BBBBBBBBBBB...",
    "................",
    "................",
])
S("icon_animals", [
    "................",
    ".OO.........OO..",
    ".OpO.......OpO..",
    ".OppO.....OppO..",
    ".OOOOOOOOOOOOO..",
    ".OOOOOOOOOOOOO..",
    ".OOwkOOOOOwkOO..",
    ".OOkkOOOOOkkOO..",
    ".OOOOOOpOOOOOO..",
    ".OmmmmkOkmmmmO..",
    "..OmmmmmmmmmO...",
    "...OOOOOOOOO....",
    ".....OOOOO......",
    "................",
    "................",
    "................",
], flat={"m": "org3"})
S("icon_space", [
    "................",
    ".......RR.......",
    "......RRRR......",
    "......WWWW......",
    ".....WWWWWW.....",
    ".....WWzcWW.....",
    ".....WWccWW.....",
    ".....WWWWWW.....",
    ".....WWWWWW.....",
    "....RWWWWWWR....",
    "...RRWWWWWWRR...",
    "...RR.WWWW.RR...",
    "......oyyo......",
    ".......oo.......",
    "................",
    "................",
])
S("icon_cooking", [
    "................",
    "................",
    "....DDDDDD......",
    "...DDWWWWDD.....",
    "..DDWWWWWWDD....",
    "..DWWWYYWWWD....",
    "..DWWYYYYWWD....",
    "..DWWYYYYWWDNNN.",
    "..DWWWYYWWWDNNN.",
    "..DDWWWWWWDD....",
    "...DDWWWWDD.....",
    "....DDDDDD......",
    "................",
    "................",
    "................",
    "................",
])
S("icon_school", [
    "................",
    "........gg......",
    ".......gg.......",
    "....RRR.gRRR....",
    "...RRRRRRRRRR...",
    "..RRwRRRRRRRRR..",
    "..RRwRRRRRRRRR..",
    "..RRRRRRRRRRRR..",
    "..RRRRRRRRRRRR..",
    "..RRRRRRRRRRRR..",
    "...RRRRRRRRRR...",
    "...RRRRRRRRRR...",
    "....RRRR.RRR....",
    "................",
    "................",
    "................",
], flat={"g": "grn1"})
S("icon_adventure", [
    "................",
    ".....YYYYYY.....",
    "...YYYYYYYYYY...",
    "..YYmmmmmmmmYY..",
    "..YmmmmmmmmrmY..",
    ".YYmmmmmmmrrmYY.",
    ".YmmmmmmmrrrmmY.",
    ".YmmmmmmkkmmmmY.",
    ".YmmmmmmkkmmmmY.",
    ".YmmmmsssmmmmmY.",
    ".YYmmmsssmmmmYY.",
    "..YmmsssmmmmmY..",
    "..YYmmmmmmmmYY..",
    "...YYYYYYYYYY...",
    ".....YYYYYY.....",
    "................",
])
S("icon_racing", [
    "................",
    "................",
    "................",
    "......RRRRR.....",
    ".....RzzRzzR....",
    "...RRRzzRzzRRR..",
    ".RRRRRRRRRRRRRR.",
    ".RRwwRRRRRRRRRR.",
    ".RRRRRRRRRRRRRR.",
    ".RRDDDRRRRRDDDR.",
    "...DSD.....DSD..",
    "....D.......D...",
    "................",
    "................",
    "................",
    "................",
])
S("icon_sports", [
    "................",
    ".....WWWWWW.....",
    "...WWWkkkkWWW...",
    "..WWWWkkkkWWWW..",
    "..WkWWWkkWWWkW..",
    ".WkkWWWWWWWWkkW.",
    ".WkkkWWWWWWkkkW.",
    ".WkkWWWkkWWWkkW.",
    ".WWWWWkkkkWWWWW.",
    ".WWWWWkkkkWWWWW.",
    ".WkWWWWkkWWWWkW.",
    "..WkkWWWWWWkkW..",
    "..WWkkWWWWkkWW..",
    "...WWWWWWWWWW...",
    ".....WWWWWW.....",
    "................",
])
S("icon_pirates", [
    "................",
    "....RRRRRRR.....",
    "...RRRRRRRRRR...",
    "...RRwRRRwRRR...",
    "...WWWWWWWWWW...",
    "..WWWWWWWWWWWW..",
    "..WWkkkWWkkkWW..",
    "..WWkkkWWkkkWW..",
    "..WWWWWkkWWWWW..",
    "...WWWWkkWWWW...",
    "....WWWWWWWW....",
    "....WkWkWkWW....",
    ".....WWWWWW.....",
    "................",
    "................",
    "................",
])
S("icon_farming", [
    "................",
    "........G..G....",
    ".......GGGGG....",
    "........GGG.....",
    "........OO......",
    ".......OOOO.....",
    ".......OOOO.....",
    "......OOOOO.....",
    "......OOOO......",
    ".....OOOOO......",
    ".....OOOO.......",
    "....OOOO........",
    "....OOO.........",
    "....OO..........",
    "................",
    "................",
])
S("icon_ocean", [
    "................",
    "................",
    "................",
    ".....BBBBB......",
    "...BBBBBBBBB..B.",
    "..BBBBBBBBBBBBB.",
    ".BBwkBBBBBBBBBB.",
    ".BBkkBBBBBBBBBB.",
    ".BBBBBBBBBBBBBB.",
    "..BBBBBBBBBBBBB.",
    "...BBBBBBBBB..B.",
    ".....BBBBB......",
    "................",
    "................",
    "................",
    "................",
])
S("icon_rpg", [
    "................",
    "............SS..",
    "...........SSS..",
    "..........SSS...",
    ".........SSS....",
    "........SSS.....",
    ".......SSS......",
    "......SSS.......",
    "..Y..SSS........",
    "..YYSSS.........",
    "...YYY..........",
    "...NYYY.........",
    "..NNN.YY........",
    ".NNN............",
    ".NN.............",
    "................",
])
S("icon_fantasy", [
    "................",
    "........PP......",
    ".......PPP......",
    "......PPPP......",
    "......PPyPP.....",
    ".....PPyyyPP....",
    ".....PPPyPPP....",
    "....PPPPPPPPP...",
    "....PPPPPPPPP...",
    "...PPPPPPPPPPP..",
    "..YYYYYYYYYYYYY.",
    "..YYYYYYYYYYYYY.",
    "................",
    "................",
    "................",
    "................",
])
S("icon_rhythm", [
    "................",
    "..N........N....",
    "...N......N.....",
    "....N....N......",
    "...WWWWWWWWWW...",
    "..WWWWWWWWWWWW..",
    "..RRRRRRRRRRRR..",
    "..RyRRyRRyRRyR..",
    "..RRyRRyRRyRRR..",
    "..RRRRRRRRRRRR..",
    "..RRRRRRRRRRRR..",
    "...RRRRRRRRRR...",
    "................",
    "................",
    "................",
    "................",
])
S("icon_robots", [
    "................",
    ".......R........",
    ".......S........",
    "...SSSSSSSSS....",
    "..SSSSSSSSSSS...",
    "..SScczSSczSS...",
    "..SSccSSSccSS...",
    "..SSSSSSSSSSS...",
    ".SSSkkkkkkkSSS..",
    ".SSSkykykykSSS..",
    "..SSSSSSSSSSS...",
    "...SSSSSSSSS....",
    "................",
    "................",
    "................",
    "................",
])
S("icon_ninjas", [
    "................",
    ".......S........",
    "......SSS.......",
    "......SSS.......",
    ".......SS.......",
    "..SSS..SSS..S...",
    "...SSSSkSSSSS...",
    "....SSkkkSSS....",
    "...SSSSkSSSSS...",
    "..S..SSS..SSS...",
    ".......SS.......",
    "......SSS.......",
    "......SSS.......",
    ".......S........",
    "................",
    "................",
])
S("icon_zombies", [
    "................",
    "....GGGGGGG.....",
    "...GGGGGGGGG....",
    "..GGGGGGGGGGG...",
    "..GGqkGGGGkqG...",
    "..GGkkGGGGkkG...",
    "..GGGGGGGGGGG...",
    "..GGGGGkGGGGG...",
    "..GGGGGGGGGGG...",
    "...GwkwkwkwG....",
    "...GGGGGGGGG....",
    "....GGGGGGG.....",
    "................",
    "................",
    "................",
    "................",
])
S("icon_strategy", [
    "................",
    "..S.S..S..S.S...",
    "..SSSSSSSSSSS...",
    "..SSSSSSSSSSS...",
    "...SSSSSSSSS....",
    "...SSSSSSSSS....",
    "...SSSkkSSSS....",
    "...SSkkkkSSS....",
    "...SSkkkkSSS....",
    "...SSSSSSSSS....",
    "..SSSSSSSSSSS...",
    "..SSSSSSSSSSS...",
    "..SSSSSSSSSSS...",
    "................",
    "................",
    "................",
])
S("icon_horror", [
    "................",
    ".....WWWWW......",
    "....WWWWWWW.....",
    "...WWWWWWWWW....",
    "...WWkkWkkWW....",
    "...WWkkWkkWW....",
    "...WWWWWWWWW....",
    "...WWWkkkWWW....",
    "...WWWkkkWWW....",
    "...WWWWWWWWW....",
    "...WWWWWWWWW....",
    "...WW.WWW.WW....",
    "...W...W...W....",
    "................",
    "................",
    "................",
])
S("icon_dinosaurs", [
    "................",
    "....GGGGGG......",
    "...GGGGGGGGG....",
    "...GGwkGGGGGG...",
    "...GGkkGGGGGGG..",
    "...GGGGGGGGGGG..",
    "...GGGGGGGGGGG..",
    "...GGGGGGkkkkk..",
    "...GGGGGGG......",
    "...GGGGGGGGG....",
    "..GGGGGGGG......",
    "..GGGGGGG.......",
    "..GGGGGGG.......",
    "..GG..GG........",
    "................",
    "................",
])
S("icon_detectives", [
    "................",
    "....SSSSS.......",
    "...SCCCCCS......",
    "..SCzzCCCCS.....",
    "..SCzCCCCCS.....",
    "..SCCCCCCCS.....",
    "..SCCCCCCCS.....",
    "..SCCCCCCCS.....",
    "...SCCCCCS......",
    "....SSSSSN......",
    ".........NN.....",
    "..........NN....",
    "...........NN...",
    "............N...",
    "................",
    "................",
])
S("icon_simulation", [
    "................",
    "..........BBB...",
    "..........BBB...",
    ".....BBB..BBB...",
    ".....BBB..BBB...",
    ".....BeB..BeB...",
    "..BBBBBB..BBB...",
    "..BeBBeB.BBeBB..",
    "..BBBBBB.BBBBB..",
    "..BeBBeB.BeBeB..",
    "..BBBBBBBBBBBB..",
    "..BBBBBBBBBBBB..",
    "..GGGGGGGGGGGG..",
    "................",
    "................",
    "................",
])
S("icon_music", [
    "................",
    ".......KKKKKKK..",
    ".......KKKKKKK..",
    ".......K.....K..",
    ".......K.....K..",
    ".......K.....K..",
    ".......K.....K..",
    ".......K.....K..",
    "....KKKK..KKKK..",
    "...KKKKK.KKKKK..",
    "...KKKKK.KKKKK..",
    "....KKK...KKK...",
    "................",
    "................",
    "................",
    "................",
])

# ---------------------------------------------------------------- the small icons, 11 x 11 (the HUD's lists, Tiny)
SMALL = {
    "action": ["......Y..", ".....YY..", "....YY...", "...YYYYY.", "....YY...", "...YY....", "..YY.....", "..Y......", "........."],
    "puzzle": [".........", "...BB....", ".BBBBBB..", ".BBBBBBB.", ".BBBBBBB.", ".BBBBBB..", ".BBBBBB..", ".........", "........."],
    "animals": [".O.....O.", ".OO...OO.", ".OOOOOOO.", ".OkOOOkO.", ".OOOpOOO.", "..OOOOO..", "...OOO...", ".........", "........."],
    "space": ["....R....", "...RRR...", "...WcW...", "...WWW...", "..RWWWR..", "..R.o.R..", ".........", ".........", "........."],
    "cooking": [".........", "..YYYY...", ".YYYYYY..", ".DDDDDDNN", "..DDDD...", ".........", ".........", ".........", "........."],
    "school": ["....g....", "..RRgRR..", ".RRRRRRR.", ".RwRRRRR.", ".RRRRRRR.", "..RRRRR..", "...R.R...", ".........", "........."],
    "adventure": ["..YYYYY..", ".YmmmmrY.", ".YmmmrmY.", ".YmmkmmY.", ".YmsmmmY.", ".YsmmmmY.", "..YYYYY..", ".........", "........."],
    "racing": [".........", "...RRR...", "..RzRzR..", ".RRRRRRR.", ".RDRRRDR.", "..D...D..", ".........", ".........", "........."],
    "sports": ["..WWWWW..", ".WWkkkWW.", ".WkWWWkW.", ".WWWkWWW.", ".WkWWWkW.", ".WWkkkWW.", "..WWWWW..", ".........", "........."],
    "pirates": ["..RRRRR..", ".RRRRRRR.", ".WWWWWWW.", ".WkkWkkW.", ".WWWkWWW.", "..WkWkW..", "...WWW...", ".........", "........."],
    "farming": ["....G.G..", ".....G...", "....OO...", "....OO...", "...OO....", "...OO....", "..OO.....", ".........", "........."],
    "ocean": [".........", "..BBBB...", ".BBBBBB.B", ".BkBBBBBB", ".BBBBBB.B", "..BBBB...", ".........", ".........", "........."],
    "rpg": [".......S.", "......SS.", ".....SS..", "....SS...", ".Y.SS....", "..YY.....", ".NYY.....", "NN.......", "........."],
    "fantasy": ["....P....", "...PPP...", "...PyP...", "..PPPPP..", ".PPPPPPP.", "YYYYYYYYY", ".........", ".........", "........."],
    "rhythm": [".N.....N.", "..N...N..", ".WWWWWWW.", ".RRRRRRR.", ".RyRyRyR.", ".RRRRRRR.", ".........", ".........", "........."],
    "robots": ["....R....", ".SSSSSSS.", ".ScSSScS.", ".SSSSSSS.", ".SkkkkkS.", ".SSSSSSS.", ".........", ".........", "........."],
    "ninjas": ["....S....", "....SS...", ".SS.S.SS.", "..SSkSS..", ".SS.S.SS.", "...SS....", "....S....", ".........", "........."],
    "zombies": ["..GGGGG..", ".GGGGGGG.", ".GqGGGqG.", ".GGGGGGG.", ".GkGkGkG.", "..GGGGG..", ".........", ".........", "........."],
    "strategy": [".S.S.S.S.", ".SSSSSSS.", "..SSSSS..", "..SSkSS..", "..SSkSS..", ".SSSSSSS.", ".........", ".........", "........."],
    "horror": ["...WWW...", "..WWWWW..", "..WkWkW..", "..WWWWW..", "..WWkWW..", "..WWWWW..", "..W.W.W..", ".........", "........."],
    "dinosaurs": ["..GGGG...", "..GkGGGG.", "..GGGGGG.", "..GGGkkk.", ".GGGG....", ".GGGG....", ".G..G....", ".........", "........."],
    "detectives": ["..SSS....", ".SCCCS...", ".SCzCS...", ".SCCCS...", "..SSSN...", ".....NN..", "......N..", ".........", "........."],
    "simulation": [".......B.", "...B..BB.", "...BB.BB.", ".BBBB.BB.", ".BeBBBeB.", ".BBBBBBB.", ".GGGGGGG.", ".........", "........."],
    "music": ["....KKKK.", "....K..K.", "....K..K.", "..KKK.KK.", ".KKKK.KK.", "..KK..K..", ".........", ".........", "........."],
}
for k, rows in SMALL.items():
    S("mini_" + k, rows, pad=True)

# Spot it's odd one out: the same icon in other colours (icon_<id>_alt, mini_<id>_alt)
ALT = {
    "detectives": {"C": "K", "z": "pnk3"},
    "pirates": {"R": "B", "w": "cyn3"},
    "horror": {"W": "G"},
    "robots": {"S": "Y", "c": "red2", "z": "red3"},
}
for k, rec in ALT.items():
    for pre in ("icon_", "mini_"):
        SPRITES[pre + k]["variants"]["alt"] = rec

# ---------------------------------------------------------------- the microgames' things (normal, then _t: Tiny)
S("hero_1", [
    "............",
    "....NNNN....",
    "...NNNNNN...",
    "...NFFFFN...",
    "...FFkFkF...",
    "...FFFFFF...",
    "....FFFF....",
    "...BBBBBB...",
    "..FBBBBBBF..",
    "..F.BBBB.F..",
    "....DDDD....",
    "....DD.DD...",
    "...DD...DD..",
    "...N.....N..",
    "............",
    "............",
])
S("hero_2", [
    "............",
    "....NNNN....",
    "...NNNNNN...",
    "...NFFFFN...",
    "...FFkFkF...",
    "...FFFFFF...",
    "....FFFF....",
    "...BBBBBB...",
    "..FBBBBBBF..",
    "..F.BBBB.F..",
    "....DDDD....",
    ".....DDD....",
    ".....DD.....",
    ".....NN.....",
    "............",
    "............",
])
S("hero_t", [".........", "...NNN...", "...FkF...", "...FFF...", "..BBBBB..", "...BBB...", "...D.D...", "..N...N..", "........."])
S("block", [
    "..............",
    ".RRRRRRRRRRRR.",
    ".RRRRRRRRRRRR.",
    ".RRwwRRRRRRRR.",
    ".RRwRRRRRRRRR.",
    ".RRRRRRRRRRRR.",
    ".RRRRRRRRRRRR.",
    ".RRRRRRRRRRRR.",
    ".RRRRRRRRRRRR.",
    ".RRRRRRRRRRRR.",
    ".RRRRRRRRRRRR.",
    ".RRRRRRRRRRRR.",
    ".RRRRRRRRRRRR.",
    "..............",
])
S("block_t", ["........", ".RRRRRR.", ".RwRRRR.", ".RRRRRR.", ".RRRRRR.", ".RRRRRR.", ".RRRRRR.", "........"])
S("cone", [
    "............",
    ".....OO.....",
    ".....OO.....",
    "....OOOO....",
    "....WWWW....",
    "...OOOOOO...",
    "...OOOOOO...",
    "..WWWWWWWW..",
    "..OOOOOOOO..",
    ".OOOOOOOOOO.",
    ".SSSSSSSSSS.",
    "............",
])
S("cone_t", ["........", "...OO...", "...WW...", "..OOOO..", "..WWWW..", ".SSSSSS.", "........"])
S("car", [
    "............",
    "...RRRRRR...",
    "..RRRRRRRR..",
    ".DRzzzzzzRD.",
    ".DRzzzzzzRD.",
    "..RRRRRRRR..",
    "..RRRwwRRR..",
    "..RRRRRRRR..",
    ".DRRRRRRRRD.",
    ".DRzzzzzzRD.",
    "..RRRRRRRR..",
    "..RRRRRRRR..",
    "...RyRRyR...",
    "............",
])
S("car_t", ["........", "..RRRR..", ".DRzzRD.", "..RRRR..", ".DRRRRD.", "..RyyR..", "........"])
S("coin_1", [
    "............",
    "....YYYY....",
    "...YYYYYY...",
    "..YYYeeYYY..",
    "..YYeYYYYY..",
    "..YYeYYYYY..",
    "..YYYYYYYY..",
    "..YYYYYYYY..",
    "...YYYYYY...",
    "....YYYY....",
    "............",
])
S("coin_2", [
    "............",
    ".....YY.....",
    "....YYYY....",
    "....YeYY....",
    "....YeYY....",
    "....YYYY....",
    "....YYYY....",
    "....YYYY....",
    "....YYYY....",
    ".....YY.....",
    "............",
])
S("coin_3", [
    "............",
    ".....YY.....",
    ".....YY.....",
    ".....YY.....",
    ".....YY.....",
    ".....YY.....",
    ".....YY.....",
    ".....YY.....",
    ".....YY.....",
    ".....YY.....",
    "............",
])
S("coin_t", ["........", "..YYYY..", ".YYeYYY.", ".YeYYYY.", ".YYYYYY.", "..YYYY..", "........"])
S("bomb_1", [
    "..............",
    "........y.....",
    ".......yoy....",
    "........N.....",
    ".......N......",
    "....DDDDD.....",
    "...DDDDDDD....",
    "..DDwDDDDDD...",
    "..DwDDDDDDD...",
    "..DDDDDDDDD...",
    "..DDDDDDDDD...",
    "..DDDDDDDDD...",
    "...DDDDDDD....",
    "....DDDDD.....",
    "..............",
])
S("bomb_2", [
    "..............",
    "..............",
    "........e.....",
    "........N.....",
    ".......N......",
    "....DDDDD.....",
    "...DDDDDDD....",
    "..DDwDDDDDD...",
    "..DwDDDDDDD...",
    "..DDDDDDDDD...",
    "..DDDDDDDDD...",
    "..DDDDDDDDD...",
    "...DDDDDDD....",
    "....DDDDD.....",
    "..............",
])
S("bomb_t", ["......y.", ".....N..", "..DDDD..", ".DwDDDD.", ".DDDDDD.", ".DDDDDD.", "..DDDD..", "........"], pad=True)
S("fish_1", [
    "................",
    "................",
    "....OOOOO.......",
    "...OOOOOOOO..OO.",
    "..OOwkOOOOOOOOO.",
    "..OOkkOOOOOOOO..",
    "..OOOOOOOOOOOOO.",
    "...OOOOOOOO..OO.",
    "....OOOOO.......",
    "................",
])
S("fish_2", [
    "................",
    "................",
    "....OOOOO....O..",
    "...OOOOOOOO.OO..",
    "..OOwkOOOOOOOO..",
    "..OOkkOOOOOOOO..",
    "..OOOOOOOOOOOO..",
    "...OOOOOOOO.OO..",
    "....OOOOO....O..",
    "................",
])
S("fish_t", ["........", "..OOO..O", ".OkOOOOO", ".OOOOOOO", "..OOO..O", "........"])
S("jelly_1", [
    "............",
    "....KKKK....",
    "...KKKKKK...",
    "..KKwKKKKK..",
    "..KwKKKKKK..",
    "..KKKKKKKK..",
    "..KKKKKKKK..",
    "..K.K..K.K..",
    "..K.K..K.K..",
    "...K..K..K..",
    "............",
])
S("jelly_2", [
    "............",
    "............",
    "....KKKK....",
    "...KKKKKK...",
    "..KKwKKKKK..",
    "..KwKKKKKK..",
    "..KKKKKKKK..",
    "..K.K..K.K..",
    "...K..K..K..",
    "..K.K..K.K..",
    "............",
])
S("jelly_t", ["........", "..KKKK..", ".KwKKKK.", ".KKKKKK.", ".K.K.K..", "..K.K.K.", "........"])
S("basket", [
    "................",
    ".N............N.",
    ".NN..........NN.",
    ".NNNNNNNNNNNNNN.",
    ".NnNnNnNnNnNnNN.",
    ".NNNNNNNNNNNNNN.",
    "..NnNnNnNnNnNN..",
    "..NNNNNNNNNNNN..",
    "...NNNNNNNNNN...",
    "................",
])
S("basket_t", [".........", ".N.....N.", ".NNNNNNN.", ".NnNnNnN.", "..NNNNN..", "........."])
S("alien_1", [
    "..............",
    "...G......G...",
    "....G....G....",
    "...GGGGGGGG...",
    "..GGGGGGGGGG..",
    "..GGwkGGwkGG..",
    "..GGkkGGkkGG..",
    "..GGGGGGGGGG..",
    "...GGkkkkGG...",
    "...GGGGGGGG...",
    "..GG..GG..GG..",
    "..............",
])
S("alien_2", [
    "..............",
    "..G........G..",
    "...G......G...",
    "...GGGGGGGG...",
    "..GGGGGGGGGG..",
    "..GGwkGGwkGG..",
    "..GGkkGGkkGG..",
    "..GGGGGGGGGG..",
    "...GGGkkGGG...",
    "...GGGGGGGG...",
    "...GG.GG.GG...",
    "..............",
])
S("alien_t", ["........", ".G....G.", "..GGGG..", ".GkGGkG.", ".GGGGGG.", "..GkkG..", ".G.GG.G.", "........"])
S("sprout", [
    "............",
    "............",
    "....N..N....",
    ".....NN.....",
    "......N.....",
    "......N.....",
    "...OOOOOO...",
    "..OOOOOOOO..",
    "..OOOOOOOO..",
    "...OOOOOO...",
    "...OOOOOO...",
    "............",
])
S("flower", [
    "............",
    "....Y..Y....",
    "...YYrrYY...",
    "...YrrrrY...",
    "....YrrY....",
    "......G.....",
    "...OOGOOO...",
    "..OOOOOOOO..",
    "..OOOOOOOO..",
    "...OOOOOO...",
    "...OOOOOO...",
    "............",
])
S("sprout_t", ["........", "...N.N..", "....N...", "..OOOO..", ".OOOOOO.", "..OOOO..", "........"])
S("flower_t", ["........", "...YrY..", "....G...", "..OOOO..", ".OOOOOO.", "..OOOO..", "........"])
S("kid", [
    "............",
    "....NNNN....",
    "...NNNNNN...",
    "...NFFFFN...",
    "...FwkwkF...",
    "...FFFFFF...",
    "....FFFF....",
    "...KKKKKK...",
    "..FKKKKKKF..",
    "....KKKK....",
    "....BBBB....",
    "....B..B....",
    "...NN..NN...",
    "............",
])
S("kid_t", [".........", "...NNN...", "...FkF...", "..KKKKK..", "...KKK...", "...B.B...", "..N...N..", "........."])
S("fruit", [
    "..............",
    "......N.......",
    "......NG......",
    "....GGGGGG....",
    "...GGgGGgGG...",
    "..GGgGGgGGgG..",
    "..GwgGGgGGgG..",
    "..GGgGGgGGgG..",
    "..GGgGGgGGgG..",
    "..GGgGGgGGgG..",
    "...GGgGGgGG...",
    "....GGGGGG....",
    "..............",
], flat={"g": "grn1"})
S("fruit_cut", [
    "..............",
    "..............",
    "..............",
    "..GGGGGGGGGG..",
    "..RRRRRRRRRR..",
    "..RkRRkRRkRR..",
    "...RRRkRRRR...",
    "....RRRRRR....",
    "..............",
], flat={})
S("fruit_t", ["........", "....N...", "..GGGG..", ".GgGgGG.", ".GgGgGG.", "..GGGG..", "........"], flat={"g": "grn1"})
S("rock", [
    "..............",
    "..............",
    ".....SSSS.....",
    "...SSSSSSSS...",
    "..SSwSSSSSSS..",
    "..SSSSSSSSSS..",
    ".SSSSSSSSSSSS.",
    ".SSSSSSSSSSSS.",
    "..............",
])
S("rock_t", ["........", "...SSS..", "..SwSSS.", ".SSSSSS.", "........"])
S("cactus", [
    "............",
    ".....GG.....",
    "....GGGG....",
    ".G..GGGG....",
    ".GG.GGGG..G.",
    ".GG.GGGG.GG.",
    ".GGGGGGG.GG.",
    "..GGGGGGGGG.",
    "....GGGGGG..",
    "....GGGG....",
    "....GGGG....",
    "....GGGG....",
    "..NNNNNNNN..",
    "............",
])
S("cactus_t", ["........", "...GG...", ".G.GG.G.", ".GGGGGG.", "...GG...", "..NNNN..", "........"])
S("dino_1", [
    "................",
    "..........GGGG..",
    ".........GGwkGG.",
    ".........GGGGGG.",
    ".........GGGkkk.",
    "..G.....GGGG....",
    "..GG...GGGGGG...",
    "..GGGGGGGGGG....",
    "...GGGGGGGGG....",
    "....GGGGGGG.....",
    ".....GG..GG.....",
    ".....G...GG.....",
    "................",
])
S("dino_2", [
    "................",
    "..........GGGG..",
    ".........GGwkGG.",
    ".........GGGGGG.",
    ".........GGGkkk.",
    "..G.....GGGG....",
    "..GG...GGGGGG...",
    "..GGGGGGGGGG....",
    "...GGGGGGGGG....",
    "....GGGGGGG.....",
    "......GGG.G.....",
    "......GG..G.....",
    "................",
])
S("dino_t", ["........", ".....GGG", ".....GkG", ".G..GGG.", ".GGGGGG.", "..GGGG..", "..G..G..", "........"])
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
S("note_t", ["......", "...KK.", "...K..", ".KKK..", ".KKK..", "......"])
S("cat_1", [
    "..............................",
    "..OO......................OO..",
    "..OOO....................OOO..",
    "..OpOO..................OOpO..",
    "..OppOO................OOppO..",
    "..OpppOO..............OOpppO..",
    "..OOOOOOOOOOOOOOOOOOOOOOOOOO..",
    "..OOOOOOOOOOOOOOOOOOOOOOOOOO..",
    ".OOOOOOOOOOOOOOOOOOOOOOOOOOOO.",
    ".OOOOOOOOOOOOOOOOOOOOOOOOOOOO.",
    ".OOOOOkkkOOOOOOOOOOOOkkkOOOOO.",
    ".OOOOkwkkkOOOOOOOOOOkwkkkOOOO.",
    ".OOOOkkkkkOOOOOOOOOOkkkkkOOOO.",
    ".OOOOkkkkkOOOOOOOOOOkkkkkOOOO.",
    ".OOOOOkkkOOOOOOOOOOOOkkkOOOOO.",
    ".OOOOOOOOOOOOOOOOOOOOOOOOOOOO.",
    ".OOOmmmmmmmmmmppmmmmmmmmmmOOO.",
    ".OOmmmmmmmmmmmppmmmmmmmmmmmOO.",
    ".OOmmmmmmmmmmkmmkmmmmmmmmmmOO.",
    ".OOmmmmmmmmmkmmmmkmmmmmmmmmOO.",
    "..OmmmmmmmmmmmmmmmmmmmmmmmmO..",
    "..OOmmmmmmmmmmmmmmmmmmmmmmOO..",
    "...OOmmmmmmmmmmmmmmmmmmmmOO...",
    "....OOOOOOOOOOOOOOOOOOOOOO....",
    "......OOOOOOOOOOOOOOOOOO......",
    "..............................",
], flat={"m": "org3"})
S("cat_2", [
    "..............................",
    "..OO......................OO..",
    "..OOO....................OOO..",
    "..OpOO..................OOpO..",
    "..OppOO................OOppO..",
    "..OpppOO..............OOpppO..",
    "..OOOOOOOOOOOOOOOOOOOOOOOOOO..",
    "..OOOOOOOOOOOOOOOOOOOOOOOOOO..",
    ".OOOOOOOOOOOOOOOOOOOOOOOOOOOO.",
    ".OOOOOOOOOOOOOOOOOOOOOOOOOOOO.",
    ".OOOOOOOOOOOOOOOOOOOOOOOOOOOO.",
    ".OOOOkOOOkOOOOOOOOOOkOOOkOOOO.",
    ".OOOOOkOkOOOOOOOOOOOOkOkOOOOO.",
    ".OOOOOOkOOOOOOOOOOOOOOkOOOOOO.",
    ".OOqqOOOOOOOOOOOOOOOOOOOOqqOO.",
    ".OOqqOOOOOOOOOOOOOOOOOOOOqqOO.",
    ".OOOmmmmmmmmmmppmmmmmmmmmmOOO.",
    ".OOmmmmmmmmmmmppmmmmmmmmmmmOO.",
    ".OOmmmmmmmmmkmmmmkmmmmmmmmmOO.",
    ".OOmmmmmmmmmmkkkkmmmmmmmmmmOO.",
    "..OmmmmmmmmmmmmmmmmmmmmmmmmO..",
    "..OOmmmmmmmmmmmmmmmmmmmmmmOO..",
    "...OOmmmmmmmmmmmmmmmmmmmmOO...",
    "....OOOOOOOOOOOOOOOOOOOOOO....",
    "......OOOOOOOOOOOOOOOOOO......",
    "..............................",
], flat={"m": "org3", "q": "pnk2"})
S("ghost", [
    "........................",
    ".........WWWWWW.........",
    ".......WWWWWWWWWW.......",
    "......WWWWWWWWWWWW......",
    ".....WWWWWWWWWWWWWW.....",
    "....WWWWWWWWWWWWWWWW....",
    "....WWWWkkWWWWkkWWWW....",
    "...WWWWkkkkWWkkkkWWWW...",
    "...WWWWkkkkWWkkkkWWWW...",
    "...WWWWWkkWWWWkkWWWWW...",
    "...WWWWWWWWWWWWWWWWWW...",
    "...WWWWWWWWkkWWWWWWWW...",
    "...WWWWWWWkkkkWWWWWWW...",
    "...WWWWWWWkkkkWWWWWWW...",
    "...WWWWWWWWkkWWWWWWWW...",
    "...WWWWWWWWWWWWWWWWWW...",
    "...WWWWWWWWWWWWWWWWWW...",
    "...WWWWWWWWWWWWWWWWWW...",
    "...WWWW.WWWWWWWW.WWWW...",
    "...WWW...WWWWWW...WWW...",
    "...WW.....WWWW.....WW...",
    "........................",
], variants={"glare": {"W": "P", "k": "red2"}})
S("door", [
    "................",
    ".NNNNNNNNNNNNNN.",
    ".NNNNNNNNNNNNNN.",
    ".NNnnnnnnnnnnNN.",
    ".NNnNNNNNNNNnNN.",
    ".NNnNNNNNNNNnNN.",
    ".NNnNNNNNNNNnNN.",
    ".NNnnnnnnnnnnNN.",
    ".NNNNNNNNNNNNNN.",
    ".NNNNNNNNNNyNNN.",
    ".NNNNNNNNNNNNNN.",
    ".NNnnnnnnnnnnNN.",
    ".NNnNNNNNNNNnNN.",
    ".NNnNNNNNNNNnNN.",
    ".NNnNNNNNNNNnNN.",
    ".NNnnnnnnnnnnNN.",
    ".NNNNNNNNNNNNNN.",
    ".NNNNNNNNNNNNNN.",
    "................",
], flat={"n": "brn1"})
S("soldier", ["..........", "...SSSS...", "..SSSSSS..", "...FkkF...", "...FFFF...", "..RRRRRR..", ".FRRRRRRF.", "...RRRR...", "...DD.D...", "..DD..DD..", ".........."])
S("soldier_t", ["......", "..SS..", "..FF..", ".RRRR.", "..RR..", ".D..D.", "......"])
S("slime_1", [
    "................",
    "................",
    "......GGGG......",
    "....GGGGGGGG....",
    "...GGwGGGGGGG...",
    "..GGwGGGGGGGGG..",
    "..GGGGkGGkGGGG..",
    ".GGGGGkGGkGGGGG.",
    ".GGGGGGGGGGGGGG.",
    ".GGGGGGkkGGGGGG.",
    "..GGGGGGGGGGGG..",
    "................",
])
S("slime_2", [
    "................",
    "................",
    "................",
    ".....GGGGGG.....",
    "...GGwGGGGGGG...",
    "..GGwGGGGGGGGG..",
    ".GGGGGkGGkGGGGG.",
    ".GGGGGkGGkGGGGG.",
    ".GGGGGGGGGGGGGG.",
    ".GGGGGGkkGGGGGG.",
    "GGGGGGGGGGGGGGGG",
    "................",
])
S("pancake", [
    "..................",
    "....YYYYYYYYYY....",
    "..YYYYnYYYYYnYYY..",
    ".YYYYYYYYnYYYYYYY.",
    "..YYYYYYYYYYYYYY..",
    "..................",
], flat={"n": "yel1"})
S("pan", [
    "........................",
    ".DDDDDDDDDDDDDDDDDD.....",
    ".DDDDDDDDDDDDDDDDDDNNNN.",
    "..DDDDDDDDDDDDDDDD..NNN.",
    "...DDDDDDDDDDDDDD.......",
    "........................",
])
S("ball", [
    "..........",
    "...WWWW...",
    "..WkkWWW..",
    ".WkkWWkWW.",
    ".WWWWkkWW.",
    ".WkWWkkWW.",
    ".WWkWWWkW.",
    "..WWWkkW..",
    "...WWWW...",
    "..........",
])
S("goal", [
    "............................................",
    ".WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW.",
    ".WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW.",
    ".WW..s...s...s...s...s...s...s...s...s...WW.",
    ".WW..s...s...s...s...s...s...s...s...s...WW.",
    ".WW..s...s...s...s...s...s...s...s...s...WW.",
    ".WWssssssssssssssssssssssssssssssssssssssWW.",
    ".WW..s...s...s...s...s...s...s...s...s...WW.",
    ".WW..s...s...s...s...s...s...s...s...s...WW.",
    ".WW..s...s...s...s...s...s...s...s...s...WW.",
    ".WWssssssssssssssssssssssssssssssssssssssWW.",
    ".WW..s...s...s...s...s...s...s...s...s...WW.",
    ".WW..s...s...s...s...s...s...s...s...s...WW.",
    ".WW..s...s...s...s...s...s...s...s...s...WW.",
    ".WWssssssssssssssssssssssssssssssssssssssWW.",
    ".WW..s...s...s...s...s...s...s...s...s...WW.",
    ".WW..s...s...s...s...s...s...s...s...s...WW.",
    ".WW..s...s...s...s...s...s...s...s...s...WW.",
    ".WWssssssssssssssssssssssssssssssssssssssWW.",
    "............................................",
], shade=False)
S("hole", [
    "............................",
    "......NNNNNNNNNNNNNNNN......",
    "...NNNNkkkkkkkkkkkkkkNNNN...",
    "..NNNkkkkkkkkkkkkkkkkkkNNN..",
    "..NNNkkkkkkkkkkkkkkkkkkNNN..",
    "...NNNNkkkkkkkkkkkkkkNNNN...",
    "......NNNNNNNNNNNNNNNN......",
    "............................",
], variants={"crater": {"N": "P"}, "grave": {"N": "S"}})
S("hole_t", ["................", "...NNNNNNNNNN...", "..NNkkkkkkkkNN..", "...NNNNNNNNNN...", "................"],
  variants={"crater": {"N": "P"}, "grave": {"N": "S"}})
S("spark_1", [".......", "...y...", "..yey..", ".yeweY.", "..yey..", "...y...", "......."], outline=False, shade=False, flat={"Y": "yel2"})
S("spark_2", [".......", ".y...y.", "..yey..", "..ewe..", "..yey..", ".y...y.", "......."], outline=False, shade=False)
S("spark_3", [".......", "...o...", "...y...", ".oyeyo.", "...y...", "...o...", "......."], outline=False, shade=False)
S("star", [".....", "..y..", ".yey.", "..y..", "....."], outline=False, shade=False)
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
        # every sprite's white flash (a hit) and dark silhouette (not found yet): the same outline
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
