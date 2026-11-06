#!/usr/bin/env python3
# scripts/gen_pixelfont.py: regenerates src/shared/Render/PixelFontData.luau from the "Minecraft" TTF (Craftron Gaming).
#
#   python3 scripts/gen_pixelfont.py [font.ttf] [--out src/shared/Render/PixelFontData.luau] [--draft CHARS]
#                                    [--png out.png "sample text"] [--png-big out.png "SAMPLE"]
#
# The TTF itself is NOT in the repo (see README, "Fonts and licences"): keep it outside the tree and pass its path
# (only --draft reads it; the faces below are this script's own tables).
#
# What the TTF is: unitsPerEm 1024, ascent 768, descent 256, every outline axis-aligned with all points on a 64-unit
# grid (16 cells per em). Strokes are 2 cells (128 units) thick, letters are 1 cell apart, and many features sit on
# odd cells (H's bar at cells 5-7 of 12, A 9 cells wide, lowercase 7-10 cells tall): a hand-drawn trace of an 8 px
# pixel font at about 1.7 cells per pixel, not an exact 2x bitmap. So:
#   * BIG  = the SMALL face below doubled, then smoothed on the 1 px grid (build_big): every font pixel becomes 2 x 2
#            art px (14 px caps, 2 px strokes, 2 px letter spacing) and every diagonal step and rounded corner gets a
#            1 px stair (an empty pixel between two inked neighbours that touch only at a corner takes the corner's
#            quarter), so no step is a 2 px block next to the 1 px outline: big titles drawn 1:1 (the Materializer's
#            cutscene, a celebration's number, the contest's words). The TTF's own 16-cell glyphs were used before:
#            a trace at about 1.7 cells per pixel, their features 1, 2 or 3 px apart, they read as mixed pixel sizes.
#   * SMALL = the UI face: the same letterforms redrawn at one pixel per stroke on the game's 8 px em (7 px caps,
#            5 px x-height, 1 px descender; Press Start 2P's vertical metrics, so every 10 px line layout stays),
#            proportional (each glyph's width from its TTF width, 1 px letter spacing). The table below was drafted
#            from the TTF by collapsing runs of identical cell rows / columns (--draft prints that draft) and then
#            evened out by hand (same bar heights across E F H A P R, same bowls, same accents); the TTF has no
#            glyphs for the accented letters, the middle dot, star, degree and arrows the game needs, so those are
#            drawn here in the same style. Unknown characters draw the box BOX.
import argparse, json, os, sys

# ---------------------------------------------------------------- SMALL face (hand-curated 1x glyphs)
# Rows top to bottom; row 0 = cap top, rows 0-6 sit on the baseline (row 6 is the bottom row of the letters), row 7 is
# the descender. A "top" other than 0 is given as (top, rows): accents above the caps start at row -1 or -2.
# Advance = width + 1 (1 px letter spacing) unless ADV says otherwise.
SMALL = {
    # capitals (7 rows)
    "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
    "C": [".####.", "#....#", "#.....", "#.....", "#.....", "#....#", ".####."],
    "D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
    "E": ["#####", "#....", "#....", "###..", "#....", "#....", "#####"],
    "F": ["#####", "#....", "#....", "###..", "#....", "#....", "#...."],
    "G": [".#####", "#.....", "#.....", "#...##", "#....#", "#....#", ".####."],
    "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "I": ["###", ".#.", ".#.", ".#.", ".#.", ".#.", "###"],
    "J": ["...#", "...#", "...#", "...#", "...#", "#..#", ".##."],
    "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
    "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
    "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#", "#...#", "#...#"],
    "N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
    "O": [".####.", "#....#", "#....#", "#....#", "#....#", "#....#", ".####."],
    "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
    "Q": [".####.", "#....#", "#....#", "#....#", "#....#", "#...#.", ".###.#"],
    "R": ["#####.", "#....#", "#....#", "#####.", "#..#..", "#...#.", "#....#"],
    "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
    "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
    "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    "V": ["#...#", "#...#", "#...#", "#...#", ".#.#.", ".#.#.", "..#.."],
    "W": ["#...#", "#...#", "#...#", "#...#", "#.#.#", "##.##", "#...#"],
    "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
    "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
    "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
    # digits: all 4 px wide (tabular: counters, timers and the HUD plates sized to them keep their width as the
    # numbers change; the TTF's digits are 6-10 cells wide)
    "0": [".##.", "#..#", "#..#", "#..#", "#..#", "#..#", ".##."],
    "1": [".#..", "##..", ".#..", ".#..", ".#..", ".#..", "###."],
    "2": [".##.", "#..#", "...#", "..#.", ".#..", "#...", "####"],
    "3": [".##.", "#..#", "...#", "..#.", "...#", "#..#", ".##."],
    "4": ["..#.", ".##.", "#.#.", "#.#.", "####", "..#.", "..#."],
    "5": ["####", "#...", "###.", "...#", "...#", "#..#", ".##."],
    "6": ["..##", ".#..", "#...", "###.", "#..#", "#..#", ".##."],
    "7": ["####", "#..#", "...#", "..#.", ".#..", ".#..", ".#.."],
    "8": [".##.", "#..#", "#..#", ".##.", "#..#", "#..#", ".##."],
    "9": [".##.", "#..#", "#..#", ".###", "...#", "...#", ".##."],
    # lowercase (x-height rows 2-6, ascenders from row 0, descenders on row 7)
    "a": [".....", ".....", "####.", "....#", ".####", "#...#", ".####"],
    "b": ["#....", "#....", "#.##.", "##..#", "#...#", "#...#", "####."],
    "c": [".....", ".....", ".###.", "#...#", "#....", "#...#", ".###."],
    "d": ["...#", "...#", ".###", "#..#", "#..#", "#..#", ".###"],
    "e": ["....", "....", ".##.", "#..#", "####", "#...", ".###"],
    "f": [".###", ".#..", "####", ".#..", ".#..", ".#..", ".#.."],
    "g": ["....", "....", ".###", "#..#", "#..#", ".###", "...#", "###."],
    "h": ["#...", "#...", "#.#.", "##.#", "#..#", "#..#", "#..#"],
    "i": ["#", ".", "#", "#", "#", "#", "#"],
    "j": ["...#", "....", "...#", "...#", "...#", "...#", "#..#", ".##."],
    "k": ["#...", "#...", "#..#", "#.#.", "##..", "#.#.", "#..#"],
    "l": ["#", "#", "#", "#", "#", "#", "#"],
    "m": [".......", ".......", "###.##.", "#..#..#", "#..#..#", "#..#..#", "#..#..#"],
    "n": [".....", ".....", "####.", "#...#", "#...#", "#...#", "#...#"],
    "o": ["....", "....", ".##.", "#..#", "#..#", "#..#", ".##."],
    "p": [".....", ".....", "#.##.", "##..#", "#...#", "#...#", "####.", "#...."],
    "q": ["....", "....", ".###", "#..#", "#..#", "#..#", ".###", "...#"],
    "r": ["....", "....", "#.##", "##..", "#...", "#...", "#..."],
    "s": ["....", "....", ".###", "#...", ".##.", "...#", "###."],
    "t": ["...", ".#.", "###", ".#.", ".#.", ".#.", "..#"],
    "u": ["....", "....", "#..#", "#..#", "#..#", "#..#", ".###"],
    "v": [".....", ".....", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
    "w": [".....", ".....", "#...#", "#...#", "#.#.#", "#.#.#", ".####"],
    "x": [".....", ".....", "#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
    "y": ["....", "....", "#..#", "#..#", "#..#", ".###", "...#", "###."],
    "z": ["....", "....", "####", "..#.", ".#..", "#...", "####"],
    # punctuation and symbols
    "!": ["#", "#", "#", "#", "#", ".", "#"],
    '"': ["#.#", "#.#", "...", "...", "...", "...", "..."],
    "#": [".#.#.", ".#.#.", "#####", ".#.#.", "#####", ".#.#.", ".#.#."],
    "$": ["..#..", ".####", "#.#..", ".###.", "..#.#", "####.", "..#.."],
    "%": ["##..#", "##..#", "...#.", "..#..", ".#...", "#..##", "#..##"],
    "&": [".##..", "#..#.", "#.#..", ".#...", "#.#.#", "#..#.", ".##.#"],
    "'": ["#", "#", ".", ".", ".", ".", "."],
    "(": [".##", "#..", "#..", "#..", "#..", "#..", ".##"],
    ")": ["##.", "..#", "..#", "..#", "..#", "..#", "##."],
    "*": ["#.#", ".#.", "#.#", "...", "...", "...", "..."],
    "+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
    ",": [".", ".", ".", ".", ".", ".", "#", "#"],
    "-": ["...", "...", "...", "###", "...", "...", "..."],
    ".": [".", ".", ".", ".", ".", ".", "#"],
    "/": ["...#", "..#.", "..#.", ".#..", ".#..", "#...", "#..."],
    ":": [".", ".", "#", ".", ".", ".", "#"],
    ";": [".", ".", "#", ".", ".", ".", "#", "#"],
    "<": ["...", "..#", ".#.", "#..", ".#.", "..#", "..."],
    "=": ["....", "....", "####", "....", "####", "....", "...."],
    ">": ["...", "#..", ".#.", "..#", ".#.", "#..", "..."],
    "?": [".##.", "#..#", "...#", "..#.", ".#..", "....", ".#.."],
    "@": [".###.", "#...#", "#.###", "#.#.#", "#.###", "#....", ".###."],
    "[": ["##", "#.", "#.", "#.", "#.", "#.", "##"],
    "\\": ["#...", ".#..", ".#..", "..#.", "..#.", "...#", "...#"],
    "]": ["##", ".#", ".#", ".#", ".#", ".#", "##"],
    "^": [".#.", "#.#", "...", "...", "...", "...", "..."],
    "_": [".....", ".....", ".....", ".....", ".....", ".....", ".....", "#####"],
    "`": ["#.", ".#", "..", "..", "..", "..", ".."],
    "{": ["..#", ".#.", ".#.", "#..", ".#.", ".#.", "..#"],
    "|": ["#", "#", "#", "#", "#", "#", "#", "#"],
    "}": ["#..", ".#.", ".#.", "..#", ".#.", ".#.", "#.."],
    "~": [".....", ".....", ".....", ".##.#", "#..#.", ".....", "....."],
    # drawn for the game (not in the TTF)
    "\u00b7": [".", ".", ".", "#", ".", ".", "."],  # middle dot
    "\u2022": ["..", "..", "..", "##", "##", "..", ".."],  # bullet
    "\u2026": [".....", ".....", ".....", ".....", ".....", ".....", "#.#.#"],  # ellipsis
    "\u00b0": [".#.", "#.#", ".#.", "...", "...", "...", "..."],  # degree
    "\u2605": ["...#...", "...#...", "..###..", "#######", ".#####.", "..#.#..", ".#...#."],  # star
    "\u00d7": [".....", ".....", "#...#", ".#.#.", "..#..", ".#.#.", "#...#"],  # multiplication sign
    "\u2192": [".....", "..#..", "...#.", "#####", "...#.", "..#..", "....."],  # right arrow
    "\u2190": [".....", "..#..", ".#...", "#####", ".#...", "..#..", "....."],  # left arrow
    "\u2191": ["..#..", ".###.", "#.#.#", "..#..", "..#..", "..#..", "....."],  # up arrow
    "\u2193": [".....", "..#..", "..#..", "..#..", "#.#.#", ".###.", "..#.."],  # down arrow
    "\u2013": ["....", "....", "....", "####", "....", "....", "...."],  # en dash
    "\u2014": [".......", ".......", ".......", "#######", ".......", ".......", "......."],  # em dash
    # the other languages' punctuation and ligatures (docs/LOCALIZATION.md 3)
    "\u00bf": ["..#.", "....", "..#.", ".#..", "#...", "#..#", ".##."],  # inverted question mark
    "\u00a1": ["#", ".", "#", "#", "#", "#", "#"],  # inverted exclamation mark
    "\u00ab": ["....", "....", "....", ".#.#", "#.#.", ".#.#", "...."],  # left guillemet
    "\u00bb": ["....", "....", "....", "#.#.", ".#.#", "#.#.", "...."],  # right guillemet
    "\u0153": [".......", ".......", ".##.##.", "#..#..#", "#..####", "#..#...", ".##.###"],  # oe
    "\u0152": [".#######", "#...#...", "#...#...", "#...###.", "#...#...", "#...#...", ".#######"],  # OE
    "\u00ba": [".#.", "#.#", ".#.", "...", "###", "...", "..."],  # masculine ordinal
    "\u00aa": [".#.", "#.#", ".##", "...", "###", "...", "..."],  # feminine ordinal
    # Cyrillic (Russian), in the same hand: 7 px capitals, 5 px x-height, the descenders of Д Ц Щ on row 7 (the
    # letters shaped like Latin ones are ALIASES below)
    "\u0411": ["#####", "#....", "#....", "####.", "#...#", "#...#", "####."],  # Б
    "\u0413": ["####", "#...", "#...", "#...", "#...", "#...", "#..."],  # Г
    "\u0414": ["..###.", ".#..#.", ".#..#.", ".#..#.", ".#..#.", ".#..#.", "######", "#....#"],  # Д
    "\u0416": ["#..#..#", "#..#..#", ".#.#.#.", "..###..", ".#.#.#.", "#..#..#", "#..#..#"],  # Ж
    "\u0417": [".###.", "#...#", "....#", "..##.", "....#", "#...#", ".###."],  # З
    "\u0418": ["#...#", "#...#", "#..##", "#.#.#", "##..#", "#...#", "#...#"],  # И
    "\u041b": ["..###", ".#..#", ".#..#", ".#..#", ".#..#", ".#..#", "#...#"],  # Л
    "\u041f": ["#####", "#...#", "#...#", "#...#", "#...#", "#...#", "#...#"],  # П
    "\u0423": ["#...#", "#...#", "#...#", ".####", "....#", "#...#", ".###."],  # У
    "\u0424": ["..#..", ".###.", "#.#.#", "#.#.#", ".###.", "..#..", "..#.."],  # Ф
    "\u0426": ["#...#.", "#...#.", "#...#.", "#...#.", "#...#.", "#...#.", "######", ".....#"],  # Ц
    "\u0427": ["#...#", "#...#", "#...#", ".####", "....#", "....#", "....#"],  # Ч
    "\u0428": ["#..#..#", "#..#..#", "#..#..#", "#..#..#", "#..#..#", "#..#..#", "#######"],  # Ш
    "\u0429": ["#..#..#.", "#..#..#.", "#..#..#.", "#..#..#.", "#..#..#.", "#..#..#.", "########", ".......#"],  # Щ
    "\u042a": ["##....", ".#....", ".#....", ".####.", ".#...#", ".#...#", ".####."],  # Ъ
    "\u042b": ["#.....#", "#.....#", "#.....#", "####..#", "#...#.#", "#...#.#", "####..#"],  # Ы
    "\u042c": ["#....", "#....", "#....", "####.", "#...#", "#...#", "####."],  # Ь
    "\u042d": [".###.", "#...#", "....#", "..###", "....#", "#...#", ".###."],  # Э
    "\u042e": ["#..###.", "#.#...#", "#.#...#", "###...#", "#.#...#", "#.#...#", "#..###."],  # Ю
    "\u042f": [".####", "#...#", "#...#", ".####", "..#.#", ".#..#", "#...#"],  # Я
    "\u0431": [".####", "#....", "####.", "#...#", "#...#", "#...#", ".###."],  # б
    "\u0432": ["....", "....", "###.", "#..#", "###.", "#..#", "###."],  # в
    "\u0433": ["....", "....", "####", "#...", "#...", "#...", "#..."],  # г
    "\u0434": ["......", "......", "..###.", ".#..#.", ".#..#.", ".#..#.", "######", "#....#"],  # д
    "\u0436": [".......", ".......", "#..#..#", ".#.#.#.", "..###..", ".#.#.#.", "#..#..#"],  # ж
    "\u0437": ["....", "....", "###.", "...#", ".##.", "...#", "###."],  # з
    "\u0438": [".....", ".....", "#...#", "#..##", "#.#.#", "##..#", "#...#"],  # и
    "\u043a": ["....", "....", "#..#", "#.#.", "##..", "#.#.", "#..#"],  # к
    "\u043b": [".....", ".....", "..###", ".#..#", ".#..#", ".#..#", "#...#"],  # л
    "\u043c": [".....", ".....", "#...#", "##.##", "#.#.#", "#...#", "#...#"],  # м
    "\u043d": ["....", "....", "#..#", "#..#", "####", "#..#", "#..#"],  # н
    "\u043f": ["....", "....", "####", "#..#", "#..#", "#..#", "#..#"],  # п
    "\u0442": [".....", ".....", "#####", "..#..", "..#..", "..#..", "..#.."],  # т
    "\u0444": ["..#..", "..#..", ".###.", "#.#.#", "#.#.#", "#.#.#", ".###.", "..#.."],  # ф
    "\u0446": [".....", ".....", "#..#.", "#..#.", "#..#.", "#..#.", "#####", "....#"],  # ц
    "\u0447": ["....", "....", "#..#", "#..#", ".###", "...#", "...#"],  # ч
    "\u0448": [".....", ".....", "#.#.#", "#.#.#", "#.#.#", "#.#.#", "#####"],  # ш
    "\u0449": ["......", "......", "#.#.#.", "#.#.#.", "#.#.#.", "#.#.#.", "######", ".....#"],  # щ
    "\u044a": [".....", ".....", "##...", ".#...", ".###.", ".#..#", ".###."],  # ъ
    "\u044b": ["......", "......", "#....#", "#....#", "###..#", "#..#.#", "###..#"],  # ы
    "\u044c": ["....", "....", "#...", "#...", "###.", "#..#", "###."],  # ь
    "\u044d": ["....", "....", "###.", "...#", ".###", "...#", "###."],  # э
    "\u044e": ["......", "......", "#..##.", "#.#..#", "###..#", "#.#..#", "#..##."],  # ю
    "\u044f": ["....", "....", ".###", "#..#", ".###", ".#.#", "#..#"],  # я
}

# Accented letters: base glyph + a mark (rows above row 0 for lowercase marks, above the caps for capitals).
# Marks are centred on the base glyph (or on its middle column pair) and kept one empty row clear of the letter.
MARKS = {  # (for an odd-width letter, for an even-width letter)
    "acute": (["..#", ".#."], ["..#.", ".#.."]),
    "grave": (["#..", ".#."], [".#..", "..#."]),
    "circ": ([".#.", "#.#"], [".##.", "#..#"]),
    "diaer": (["#.#"], ["#..#"]),
    "tilde": ([".#.#", "#.#."], [".#.#", "#.#."]),
    "breve": (["#.#", ".#."], ["#..#", ".##."]),
}
ACCENTS = {
    # lowercase: the x-height top is row 2, so a mark ends on row 0 and row 1 stays clear
    "\u00e0": ("a", "grave"), "\u00e1": ("a", "acute"), "\u00e2": ("a", "circ"), "\u00e4": ("a", "diaer"),
    "\u00e8": ("e", "grave"), "\u00e9": ("e", "acute"), "\u00ea": ("e", "circ"), "\u00eb": ("e", "diaer"),
    "\u00ec": ("i", "grave"), "\u00ed": ("i", "acute"), "\u00ee": ("i", "circ"), "\u00ef": ("i", "diaer"),
    "\u00f2": ("o", "grave"), "\u00f3": ("o", "acute"), "\u00f4": ("o", "circ"), "\u00f6": ("o", "diaer"),
    "\u00f9": ("u", "grave"), "\u00fa": ("u", "acute"), "\u00fb": ("u", "circ"), "\u00fc": ("u", "diaer"),
    "\u00f1": ("n", "tilde"),
    # capitals: the mark ends on row -2 (row -1 clear) above the full 7-row letter; it reaches into the line gap
    "\u00c0": ("A", "grave"), "\u00c1": ("A", "acute"), "\u00c2": ("A", "circ"), "\u00c4": ("A", "diaer"),
    "\u00c8": ("E", "grave"), "\u00c9": ("E", "acute"), "\u00ca": ("E", "circ"), "\u00cb": ("E", "diaer"),
    "\u00d6": ("O", "diaer"), "\u00dc": ("U", "diaer"), "\u00d1": ("N", "tilde"),
    # Portuguese, French and Italian (docs/LOCALIZATION.md 3)
    "\u00e3": ("a", "tilde"), "\u00f5": ("o", "tilde"), "\u00ff": ("y", "diaer"),
    "\u00c3": ("A", "tilde"), "\u00d5": ("O", "tilde"),
    "\u00cc": ("I", "grave"), "\u00cd": ("I", "acute"), "\u00ce": ("I", "circ"), "\u00cf": ("I", "diaer"),
    "\u00d2": ("O", "grave"), "\u00d3": ("O", "acute"), "\u00d4": ("O", "circ"),
    "\u00d9": ("U", "grave"), "\u00da": ("U", "acute"), "\u00db": ("U", "circ"), "\u0178": ("Y", "diaer"),
    # Russian: Й й (И with a breve), Ё ё
    "\u0419": ("\u0418", "breve"), "\u0439": ("\u0438", "breve"),
    "\u0401": ("E", "diaer"), "\u0451": ("e", "diaer"),
}
CEDILLA = {"\u00e7": "c", "\u00c7": "C"}
ALIASES = {  # characters drawn with another glyph: curly quotes, no-break space, minus sign
    "\u2019": "'", "\u2018": "'", "\u201c": '"', "\u201d": '"', "\u00a0": " ", "\u2212": "-",
    "\u202f": " ", "\u201e": '"',  # narrow no-break space (French), low double quote
    # Cyrillic letters shaped like Latin ones
    "\u0410": "A", "\u0412": "B", "\u0415": "E", "\u041a": "K", "\u041c": "M", "\u041d": "H", "\u041e": "O",
    "\u0420": "P", "\u0421": "C", "\u0422": "T", "\u0425": "X",
    "\u0430": "a", "\u0435": "e", "\u043e": "o", "\u0440": "p", "\u0441": "c", "\u0443": "y", "\u0445": "x",
}
BOX = ["####", "#..#", "#..#", "#..#", "#..#", "#..#", "####"]
SPACE_ADV = 3  # a word gap is the last letter's 1 px spacing plus this
ADV = {}  # advances other than width + 1


def build_small():
    glyphs = {}
    for ch, rows in SMALL.items():
        glyphs[ch] = (0, rows)
    for ch, (base, mark) in ACCENTS.items():
        b = SMALL[base]
        if base == "i":  # the mark takes the dot's place; the glyph widens to the mark
            m = MARKS[mark][0]
            mw = len(m[0])
            stem = ["." * ((mw - 1) // 2) + "#" + "." * (mw // 2)] * 5
            glyphs[ch] = (1 - len(m), m + ["." * mw] + stem)
            continue
        w = len(b[0])
        m = MARKS[mark][w % 2 == 0 and 1 or 0]
        mw = len(m[0])
        x0 = max(0, (w - mw) // 2)
        mrows = ["." * x0 + r + "." * (w - x0 - mw) for r in m]
        if base.isupper():
            glyphs[ch] = (-1 - len(mrows), mrows + ["." * w] + b)
        else:
            glyphs[ch] = (1 - len(mrows), mrows + ["." * w] + b[2:])
    for ch, base in CEDILLA.items():
        b = SMALL[base]
        w = len(b[0])
        glyphs[ch] = (0, b + ["." * (w // 2) + "#" + "." * (w - w // 2 - 1)])
    return glyphs



def build_big(small):
    """The BIG face: each SMALL glyph doubled, with a 1 px stair wherever two inked pixels touch only at a corner."""

    def double(rows):
        h, w = len(rows), len(rows[0])

        def at(x, y):
            return 0 <= y < h and 0 <= x < w and rows[y][x] == "#"

        out = [["."] * (2 * w) for _ in range(2 * h)]
        for y in range(h):
            for x in range(w):
                if at(x, y):
                    q = [True] * 4
                else:
                    up, dn, lf, rt = at(x, y - 1), at(x, y + 1), at(x - 1, y), at(x + 1, y)
                    # (top-left, top-right, bottom-left, bottom-right): filled when its two sides are inked and the
                    # pixel between them diagonally is not (a diagonal, not an inside corner)
                    q = [
                        up and lf and not at(x - 1, y - 1),
                        up and rt and not at(x + 1, y - 1),
                        dn and lf and not at(x - 1, y + 1),
                        dn and rt and not at(x + 1, y + 1),
                    ]
                for i, (dx, dy) in enumerate(((0, 0), (1, 0), (0, 1), (1, 1))):
                    if q[i]:
                        out[2 * y + dy][2 * x + dx] = "#"
        return ["".join(r) for r in out]

    big = {}
    for ch, (top, rows) in small.items():
        big[ch] = (2 * top, double(rows))
    big[" "] = (0, ["." * (2 * SPACE_ADV - 2)])
    return big

# ---------------------------------------------------------------- TTF -> 64-unit cell bitmaps
CELL = 64


def ttf_cells(path):
    from fontTools.ttLib import TTFont

    f = TTFont(path)
    assert f["head"].unitsPerEm == 1024, "expected unitsPerEm 1024"
    asc, desc = f["hhea"].ascent, f["hhea"].descent
    assert asc == 768 and desc == -256, "expected ascent 768 / descent -256"
    glyf, hmtx, cmap = f["glyf"], f["hmtx"], f.getBestCmap()
    top, bot = asc // CELL, desc // CELL  # 12, -4
    out = {}
    for cp, name in sorted(cmap.items()):
        g = glyf[name]
        adv = hmtx[name][0]
        assert adv % CELL == 0, "advance off the grid: %r" % chr(cp)
        contours = []
        if g.numberOfContours > 0:
            coords, ends, flags = g.getCoordinates(glyf)
            assert all(fl & 1 for fl in flags), "curve in %r" % chr(cp)
            s = 0
            for e in ends:
                pts = [(int(x), int(y)) for x, y in coords[s : e + 1]]
                s = e + 1
                for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]):
                    assert x0 == x1 or y0 == y1, "diagonal edge in %r" % chr(cp)
                    assert x0 % CELL == 0 and y0 % CELL == 0, "point off the 64 grid in %r" % chr(cp)
                contours.append(pts)

        def inside(x, y):
            wn = 0
            for c in contours:
                for (x0, y0), (x1, y1) in zip(c, c[1:] + c[:1]):
                    if (y0 <= y < y1) or (y1 <= y < y0):
                        xi = x0 + (y - y0) * (x1 - x0) / (y1 - y0)
                        if xi > x:
                            wn += 1 if y1 > y0 else -1
            return wn != 0

        w = adv // CELL
        rows = []
        for cy in range(top - 1, bot - 1, -1):
            rows.append("".join("#" if inside(cx * CELL + CELL / 2, cy * CELL + CELL / 2) else "." for cx in range(w)))
        out[chr(cp)] = rows
    return out


def draft(cells, ch):
    """The run-collapse draft of a TTF glyph at 1x (see the header); a starting point for SMALL entries."""
    rows = cells[ch]
    W = len(rows[0]) - 1
    if W <= 0:
        return []
    cols = ["".join(r[x] for r in rows) for x in range(W)]
    xb = [0] + [x for x in range(1, W) if cols[x] != cols[x - 1]] + [W]
    yb = [0] + [i for i in range(1, len(rows)) if rows[i] != rows[i - 1]] + [len(rows)]

    def up(y):
        return int(y * 5 / 9 + 0.5) if y <= 9 else 5 + int((y - 9) * 2 / 3 + 0.5)

    def row(i):
        return 7 - up(12 - i) if i <= 12 else 8

    X = lambda x: (x + 1) // 2
    grid = [["."] * X(W) for _ in range(8)]
    for a, b in zip(yb, yb[1:]):
        for xa, xz in zip(xb, xb[1:]):
            if rows[a][xa] == "#":
                for r in range(row(a), row(b)):
                    for c in range(X(xa), X(xz)):
                        grid[r][c] = "#"
    return ["".join(r) for r in grid]


# ---------------------------------------------------------------- Luau output
def bits(row):
    v = 0
    for i, c in enumerate(row):
        if c == "#":
            v |= 1 << i
    return v


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def emit(path, small, big):
    L = []
    L.append("--!strict")
    L.append("-- GENERATED by scripts/gen_pixelfont.py from the \"Minecraft\" TTF by Craftron Gaming (the TTF is not in the repo;")
    L.append("-- see README \"Fonts and licences\"). Do not edit by hand: change the script's tables and run it again.")
    L.append("-- Glyph rows are bit masks (bit 0 = the leftmost pixel). Keys are characters (UTF-8).")
    L.append("--   SMALL: the UI face, 8 px em (rows 0-6 above the baseline, row 7 the descender), 1 font px = 1 art px;")
    L.append("--          { w, top, rows... }: width in px, first row (negative for accents above the cap line), masks.")
    L.append("--   BIG:   SMALL doubled with 1 px stairs on its diagonals (scripts/gen_pixelfont.py build_big), 16 px em (rows")
    L.append("--          0-13 above the baseline, 14-15 the descender), { w, top, rows... } like SMALL (advance = w + 2).")
    L.append("-- stylua: ignore start")
    L.append("return {")
    L.append("\tsmallSpace = %d," % SPACE_ADV)
    L.append("\tsmallBox = { %d, 0, %s },"
             % (len(BOX[0]), ", ".join(str(bits(r)) for r in BOX)))
    L.append("\tsmall = {")
    for ch in sorted(small, key=lambda c: ord(c)):
        top, rows = small[ch]
        w = max(len(r) for r in rows)
        assert all(len(r) == w for r in rows), "ragged rows in %r" % ch
        L.append("\t\t[%s] = { %d, %d, %s }," % (lua_str(ch), w, top, ", ".join(str(bits(r)) for r in rows)))
    L.append("\t},")
    L.append("\tsmallAlias = {")
    for a, b in sorted(ALIASES.items()):
        L.append("\t\t[%s] = %s," % (lua_str(a), lua_str(b)))
    L.append("\t},")
    L.append("\tbigBox = { %d, 0, %s }," % (2 * len(BOX[0]), ", ".join(str(bits(r)) for r in build_big({"?": (0, BOX)})["?"][1])))
    L.append("\tbig = {")
    for ch in sorted(big, key=lambda c: ord(c)):
        top, rows = big[ch]
        L.append("\t\t[%s] = { %d, %d, %s }," % (lua_str(ch), len(rows[0]), top, ", ".join(str(bits(r)) for r in rows)))
    L.append("\t},")
    L.append("}")
    L.append("-- stylua: ignore end")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(L) + "\n")


def render_png(path, small, text, scale=4):
    from PIL import Image

    lines = text.split("\\n")
    def adv(ch):
        if ch == " ":
            return SPACE_ADV
        g = small.get(ch) or small.get(ALIASES.get(ch, "")) or (0, BOX)
        return len(g[1][0]) + 1
    W = max(sum(adv(c) for c in ln) for ln in lines) + 4
    H = len(lines) * 10 + 4
    img = Image.new("RGB", (W, H), (43, 30, 46))
    px = img.load()
    for li, ln in enumerate(lines):
        x = 2
        for ch in ln:
            if ch != " ":
                top, rows = small.get(ch) or small.get(ALIASES.get(ch, "")) or (0, BOX)
                for ry, r in enumerate(rows):
                    for rx, c in enumerate(r):
                        if c == "#":
                            yy = 3 + li * 10 + top + ry
                            if 0 <= yy < H:
                                px[x + rx + 1, yy + 1] = (20, 12, 22)
                                px[x + rx, yy] = (255, 244, 224)
            x += adv(ch)
    img.resize((W * scale, H * scale), Image.NEAREST).save(path)


def render_png_big(path, big, text, scale=4):
    """TEXT in the BIG face as the game's titles draw it: the face, a 1 px outline and 2 px of depth."""
    from PIL import Image

    pen, ink = 0, set()
    for ch in text:
        top, rows = big.get(ch) or big.get(ALIASES.get(ch, "")) or big["?"]
        for ry, r in enumerate(rows):
            for rx, c in enumerate(r):
                if c == "#":
                    ink.add((pen + rx + 2, top + ry + 4))
        pen += len(rows[0]) + 2
    W, H = pen + 4, 24
    img = Image.new("RGB", (W, H), (43, 30, 46))
    px = img.load()
    for x, y in ink:
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, 1), (1, 1), (-1, 2), (1, 2), (0, 2), (0, 3)):
            if 0 <= x + dx < W and 0 <= y + dy < H:
                px[x + dx, y + dy] = (110, 60, 20)
    for x, y in ink:
        if 0 <= x < W and 0 <= y < H:
            px[x, y] = (255, 200, 60)
    img.resize((W * scale, H * scale), Image.NEAREST).save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ttf", nargs="?", default=None, help="the Minecraft TTF (only --draft needs it)")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "src", "shared", "Render", "PixelFontData.luau"))
    ap.add_argument("--draft", default=None, help="print the run-collapse draft of these characters and exit")
    ap.add_argument("--png", nargs=2, metavar=("OUT", "TEXT"), help="draw TEXT in the SMALL face to OUT and exit")
    ap.add_argument("--png-big", nargs=2, metavar=("OUT", "TEXT"), help="draw TEXT in the BIG face to OUT and exit")
    a = ap.parse_args()
    if a.draft:
        assert a.ttf, "--draft reads the TTF: pass its path"
        cells = ttf_cells(a.ttf)
        for ch in a.draft:
            print(repr(ch))
            print("\n".join(draft(cells, ch)))
        return
    small = build_small()
    if a.png:
        render_png(a.png[0], small, a.png[1])
        return
    big = build_big(small)
    if a.png_big:
        render_png_big(a.png_big[0], big, a.png_big[1])
        return
    missing = [chr(c) for c in range(33, 127) if chr(c) not in small]
    assert not missing, "SMALL lacks %r" % missing
    out = os.path.normpath(a.out)
    emit(out, small, big)
    print("wrote %s: %d small glyphs, %d big glyphs" % (out, len(small), len(big)))


if __name__ == "__main__":
    main()
