#!/usr/bin/env python3
# scripts/gen_art.py: regenerates src/client/UI/ArtData.luau, every interface sprite (the island's small icons, the
# arrows, a note, a heart, sparks) from the masks below, and the driftlings' portraits from scripts/portraits.txt (drawn
# from their 3D models: tools/preview/portraits.sh); and src/client/UI/ThumbData.luau, the build catalog's pictures
# from scripts/thumbs.txt (drawn from the pieces' models: tools/preview/thumbs.sh), in a module of their own so ArtData
# stays small; and src/client/UI/CosmeticThumbData.luau, the cosmetics' pictures from scripts/cosmetic_thumbs.txt
# (tools/preview/cosmetic_thumbs.sh). (The world and the driftlings are 3D: Models/*, drawn by the pixel filter with the
# same outline and palette.)
#
#   python3 scripts/gen_art.py [--out src/client/UI/ArtData.luau] [--thumbs-out src/client/UI/ThumbData.luau]
#                              [--looks-out src/client/UI/CosmeticThumbData.luau] [--png sheet.png] [--zoom 6]
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
import argparse, math, os, sys

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
    "grn0": 0x1E5652, "grn1": 0x368E5E, "grn2": 0x66C26E, "grn3": 0xA6E28C,
    "cyn0": 0x235A86, "cyn1": 0x34A0BC, "cyn2": 0x66D6DE, "cyn3": 0xB2F4EC,
    "blu0": 0x2E2F7C, "blu1": 0x4561BA, "blu2": 0x6F98E8, "blu3": 0xA9CFFA,
    "pur0": 0x3A2672, "pur1": 0x6A47AC, "pur2": 0x9B74D8, "pur3": 0xCAA6F0,
    "pnk0": 0x76306B, "pnk1": 0xC2548F, "pnk2": 0xF286B5, "pnk3": 0xFFBACB,
    "brn0": 0x4B2A33, "brn1": 0x8A543C, "brn2": 0xC3895C, "brn3": 0xEABC85,
    "gry0": 0x46425A, "gry1": 0x76728C, "gry2": 0xA6A3B5, "gry3": 0xD4D2D8,
    "skn0": 0x8F4C55, "skn1": 0xD18A6D, "skn2": 0xF4C49E, "skn3": 0xFFE3C2,
    "wht0": 0x8D93BF, "wht1": 0xBAC4E2, "wht2": 0xEDF1F7,
    "drk0": 0x2E2433, "drk1": 0x4B3D4E, "drk2": 0x685767, "drk3": 0x8C7886,
    "bas0": 0x3A2D35, "bas1": 0x5A4549, "bas2": 0x7A5E5C, "bas3": 0x9E7D72,
    "crm0": 0xA86D60, "crm1": 0xDEAC88, "crm2": 0xFBE0BF, "crm3": 0xFFF5E4,  # cream: bellies, muzzles, jaws
    "tel0": 0x1A4C58, "tel1": 0x28827E, "tel2": 0x3CB4A8, "tel3": 0x84E0C8,  # teal: the island birds' backs
    "cor0": 0x7C2B40, "cor1": 0xC9504F, "cor2": 0xFF8A72, "cor3": 0xFFC09A,  # coral: a wren's breast
    "ros0": 0x6E2448, "ros1": 0xB4466E, "ros2": 0xE77D9C, "ros3": 0xFFAFC2,  # rose: a mythic egg
    "ind0": 0x10102E, "ind1": 0x1E2050, "ind2": 0x2E3272, "ind3": 0x46509A,  # night blue: a celestial egg
    # the tone markers of a tinted sprite (Render/Fx.TONES, the same four values): drawn in the world they take the
    # tones of a colour given at draw time (a tuft the lawn's under it, a leaf its tree's, a butterfly its own), here a
    # plain green so the contact sheet shows them
    "tn0": 0x2E5937, "tn1": 0x4A8A4C, "tn2": 0x76B862, "tn3": 0xB7E08B,
    "wht": 0xFFFFFF, "crm": 0xFFF2DC, "blk": 0x3B3442, "plt": 0x463B5C,
}
RAMPS = {
    "R": ["red0", "red1", "red2", "red3"], "O": ["org0", "org1", "org2", "org3"], "Y": ["yel0", "yel1", "yel2", "yel3"],
    "G": ["grn0", "grn1", "grn2", "grn3"], "C": ["cyn0", "cyn1", "cyn2", "cyn3"], "B": ["blu0", "blu1", "blu2", "blu3"],
    "P": ["pur0", "pur1", "pur2", "pur3"], "K": ["pnk0", "pnk1", "pnk2", "pnk3"], "N": ["brn0", "brn1", "brn2", "brn3"],
    "S": ["gry0", "gry1", "gry2", "gry3"], "F": ["skn0", "skn1", "skn2", "skn3"], "W": ["wht0", "wht1", "wht2", "wht"],
    "D": ["drk0", "drk1", "drk2", "drk3"], "M": ["bas0", "bas1", "bas2", "bas3"], "E": ["crm0", "crm1", "crm2", "crm3"],
    "T": ["tel0", "tel1", "tel2", "tel3"], "Q": ["cor0", "cor1", "cor2", "cor3"],
    "H": ["ros0", "ros1", "ros2", "ros3"], "I": ["ind0", "ind1", "ind2", "ind3"],
}
FLAT = {
    "k": "ink", "w": "wht", "r": "red2", "o": "org2", "y": "yel2", "g": "grn2", "c": "cyn2", "b": "blu2", "p": "pnk2",
    "n": "brn1", "s": "gry2", "e": "yel3", "q": "red3", "u": "pur2", "x": "blk", "z": "cyn3", "h": "gry3", "m": "crm",
    "t": "org1", "d": "brn0", "l": "grn1",
}

SPRITES = {}  # name -> dict(rows, flat, shade, outline, recolor)


def S(name, rows, flat=None, shade=True, outline=True, variants=None, pad=False, sphere=None):
    def touches(rs):
        return any(c != "." for c in rs[0] + rs[-1]) or any(r[0] != "." or r[-1] != "." for r in rs)
    if pad or (outline and touches(rows)):  # a 1 px margin all round for the outline
        rows = ["." * (len(rows[0]) + 2)] + ["." + r + "." for r in rows] + ["." * (len(rows[0]) + 2)]
    w = len(rows[0])
    for r in rows:
        if len(r) != w:
            sys.exit("%s: rows of different widths (%d vs %d): %r" % (name, len(r), w, r))
    SPRITES[name] = dict(rows=rows, flat=flat or {}, shade=shade, outline=outline, variants=variants or {}, sphere=sphere)


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
# The cosmetics' pictures, 24 x 24 (GAME_DESIGN 14.1): every piece in Data/Cosmetics drawn from its parts the same way
# (the preview scenario "cthumbs"), from scripts/cosmetic_thumbs.txt (sh tools/preview/cosmetic_thumbs.sh makes it), to
# UI/CosmeticThumbData as "look_<id>" (UI/CosmeticIcons draws them).
LOOKS = {}  # "look_<id>" -> rows


def load_thumbs(path, store=THUMBS, prefix="thumb_", what="build catalog pictures", maker="thumbs.sh", module="ThumbData"):
    if not os.path.exists(path):
        print("no %s at %s (sh tools/preview/%s makes them): %s is empty" % (what, path, maker, module))
        return
    cur, pal = None, []
    with open(path) as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            if line.startswith("thumb "):
                _, pid, w, h = line.split()
                cur = store.setdefault(prefix + pid, [])
                continue
            if line.startswith("pal "):
                pal = [int(t, 16) for t in line.split()[1:]]
                continue
            cur.append([None if ch == "." else (pal[CHARS.index(ch)], 1.0) for ch in line])


load_thumbs(os.path.join(os.path.dirname(os.path.abspath(__file__)), "thumbs.txt"))
load_thumbs(os.path.join(os.path.dirname(os.path.abspath(__file__)), "cosmetic_thumbs.txt"), LOOKS, "look_", "cosmetic pictures", "cosmetic_thumbs.sh", "CosmeticThumbData")

# ---------------------------------------------------------------- the small icons, 11 x 11 (chips, lists, the path)

# Hand-toned icons, the way Random Bakery draws its own (its UI/PixelArt: every pixel's tone placed by hand from a few
# shared ramps, light from the top left on the real form, white glints, the lines inside a sprite a material's dark tone,
# never ink; one closed 1 px ink ring round the outside). The request of 2026-11-14: "The driftling, hatchery, season
# icons, starter pack and tree icons look flat and undetailed. Redo them. Reference the bakery game for icons", then "Do
# the same with all the other icons" and "Remember to use anti aliasing within the outline, avoid banding and use
# hueshifting": the ramps are hue shifted (cooler shadows, warmer lights), tones sit in clusters that follow the form
# (no rings of tone tracing the outline), and build() softens each step of a curve from the inside. Characters: "1" "2"
# "3" "4" the first ramp's dark, shadow, base and light; "5" "6" "7" "8" the second's; "a" "b" "c" "d" the third's; "w"
# a white glint; "x" a near-black (eyes, buttons); other letters the sprite's own `flat` keys.
def HAND(name, rows, ramps, flat=None):
    m = {"w": "wht", "x": "drk0"}
    for i, r in enumerate(ramps):
        for t, ch in enumerate(("1234", "5678", "abcd")[i]):
            m[ch] = RAMPS[r][t]
    m.update(flat or {})
    S(name, rows, flat=m, shade=False, pad=True)
    # each ramp character's ramp and tone, for the anti-aliasing pass inside the outline (build)
    SPRITES[name]["hand"] = {ch: (r, t) for i, r in enumerate(ramps) for t, ch in enumerate(("1234", "5678", "abcd")[i])
                             if ch not in (flat or {})}


# a driftling: a round little sea sprite, ears up, cheeks pink, lit from the top left
HAND("mini_pal", [
    ".3.....2.",
    ".4333332.",
    "4w4333332",
    "43x333x32",
    "4p33133p2",
    "333333322",
    "333333221",
    ".3332221.",
    "..22111..",
], ["C"], {"p": "pnk2"})
# the Hatchery: a cream egg with pink spots, round and lit
HAND("mini_egg", [
    "...443...",
    "..4w433..",
    ".444p333.",
    ".4443332.",
    "44p333332",
    "433333p22",
    "333332222",
    ".3322221.",
    "..22111..",
], ["E"], {"p": "pnk2"})
# spring: a pink blossom with a gold heart on a green stem and leaf
HAND("mini_season_spring", [
    "..44433..",
    ".4w43332.",
    ".43dd332.",
    ".43cd322.",
    "..33222..",
    "....6....",
    ".786.....",
    "..776....",
    "....5....",
], ["K", "G", "Y"])
# summer: the sun, a round gold ball with orange rays
HAND("mini_season_summer", [
    "....7....",
    ".6..7..6.",
    "...443...",
    "..4w433..",
    "774433265",
    "..43322..",
    "...322...",
    ".6..6..5.",
    "....6....",
], ["Y", "O"])
# autumn: a maple leaf turning orange, a darker vein down it, a brown stem
HAND("mini_season_autumn", [
    "....4....",
    ".4.443.3.",
    ".44423332",
    "444423332",
    ".4442332.",
    "..43222..",
    ".3.326.2.",
    "....6....",
    "....5....",
], ["O", "N"])
# winter: a snowman, two round snowballs, coal eyes and buttons, a carrot nose, a red scarf
HAND("mini_season_winter", [
    "...443...",
    "..4x4x3..",
    "..44o32..",
    "..87765..",
    ".4w43332.",
    "4443x3322",
    "44433x322",
    ".3332221.",
    "..22111..",
], ["W", "R"], {"o": "org2"})
# the starter pack: a red gift box, its lid a little wider, a gold ribbon and bow
HAND("mini_gift", [
    "..87.76..",
    "...876...",
    "444484333",
    "333376222",
    ".4447332.",
    ".4436322.",
    ".3336222.",
    ".3326221.",
    ".2225111.",
], ["R", "Y"])
# the Tree of Life: a round green crown with gold fruit, a brown trunk on spreading roots
HAND("mini_tree", [
    "..44433..",
    ".4w44333.",
    "4444d3332",
    "443333d22",
    ".3332222.",
    "...676...",
    "...675...",
    "..67755..",
    ".66...55.",
], ["G", "N", "Y"])

# The rest of the small icons, hand-toned the same way (the request of 2026-11-14: "Do the same with all the other
# icons"), each 9 x 9 inside its ink ring like the masks they replace, so every layout keeps its sizes.
ICONS = {
    # the shells: a scallop, its ribs fanning down to the hinge
    # food: a red apple, a brown stem and a green leaf
    "food": (["....c.87.", ".444c433.", "44w443332", "444433332", "444333322", "433333222", ".3332222.", ".3322221.", "..22.11.."], ["R", "G", "N"], None),
    # wood: a log lying down, its cut end showing the rings
    "wood": ([".........", ".4444487.", "433338776", "333328656", "323238766", "222227765", ".1111766.", ".........", "........."], ["N", "E"], None),
    # the sun: a gold ball with orange rays
    "sun": (["....7....", ".6..7..6.", "...443...", "..4w433..", "774433265", "..43322..", "...322...", ".6..6..5.", "....6...."], ["Y", "O"], None),
    # the moon: a pale crescent and a little star
    "moon": (["..44433..", ".4443....", "4443..w..", "4432.....", "4432.....", "4332.....", "33322....", ".332221..", "..22211.."], ["E"], None),
    # charm: a pink heart, its glint top left
    "charm": ([".44...33.", "4w44.4332", "444443332", "444433322", ".4333322.", "..33222..", "...322...", "....2....", "........."], ["K"], None),
    # a villager: a head and shoulders, brown hair, a blue shirt
    "folk": (["..cddcb..", ".cdddccb.", ".c4443cb.", ".44x3x32.", ".4443332.", "..43322..", ".8877765.", "887777665", "877776655"], ["F", "B", "N"], None),
    # Looks: a founder, orange hair, a green shirt
    "visitor": (["..cddcb..", ".cdddccb.", ".c4443cb.", ".44x3x32.", ".4443332.", "..43322..", ".8877765.", "887777665", "877776655"], ["F", "G", "O"], None),
    # home: a cream house, a red roof, a brown door
    "home": (["....8....", "...887...", "..88776..", ".8877665.", "887776655", ".4433332.", ".44cc332.", ".43cb322.", ".33cb221."], ["E", "R", "N"], None),
    # the huts: a twig nest with a cream egg in it
    "nest": ([".........", "...887...", "..8w876..", "..87766..", "443766432", "434343432", ".3232322.", "..22221..", "........."], ["N", "E"], None),
    # training: a steel dumbbell
    "train": ([".........", ".........", ".43...32.", "443...332", "443443322", "332...221", ".32...21.", ".........", "........."], ["S"], None),
    # a boost: a green arrow pointing up
    "boost": (["....4....", "...443...", "..44433..", ".4443332.", "444433322", "...433...", "...432...", "...332...", "...221..."], ["G"], None),
    # paths: stepping stones
    "path": (["443......", "4332.....", ".221.443.", "....43322", "443..2211", "4332.....", ".221.443.", "....43322", ".....2211"], ["S"], None),
    # decor: a pink flower in a clay pot, two leaves
    "decor": (["...443...", "..4yy32..", "...332...", ".876.67..", "..7666...", "..dcccb..", "...dcb...", "...cbb...", "...bba..."], ["K", "G", "O"], {"y": "yel3"}),
    # work: a spade, a steel blade on a wooden handle
    "work": ([".......c.", "......cb.", ".....cb..", "....cb...", "..43b....", ".4432....", "44332....", "4322.....", ".21......"], ["S", "G", "N"], None),
    # fences: two posts and two rails
    "fence": ([".4.....3.", "443...332", "443444322", "432333322", "432...322", "432...322", "432333322", "332222221", "221...211"], ["N"], None),
    # water: a blue drop with a white glint
    "water": (["....4....", "...443...", "..4w433..", ".44w4332.", ".4443332.", "443333322", "433333222", ".3332221.", "..32211.."], ["B"], None),
    # nature: a pine on a brown trunk
    "nature": (["....4....", "...443...", "..44332..", "...433...", "..44332..", ".4433322.", "443332221", "....b....", "...cba..."], ["G", "G", "N"], None),
    # fun: a red balloon on a string
    "fun": (["...443...", "..4w433..", ".4443332.", ".4433322.", "..33322..", "...322...", "....2....", "....s....", ".....s..."], ["R"], {"s": "gry2"}),
    # a start: a red flag on a pole
    "start": ([".c443....", ".c44433..", ".c443322.", ".c4322...", ".c2......", ".c.......", ".c.......", ".c.......", "acb......"], ["R", "G", "N"], None),
    # loot: a tied brown sack
    "loot": (["...4.3...", "....3....", "...434...", "..44332..", ".4w43332.", "444433322", "443333222", ".3332221.", "..22111.."], ["N"], None),
    # a chest: wood with a gold band and lock
    "chest": ([".........", ".4444433.", "444434332", "888878776", "443383322", "433373322", "433333222", "332222221", "........."], ["N", "Y"], None),
    # the wild: an orange paw print
    "wild": (["..44.33..", "..43.32..", "44.....33", "43.....32", "...443...", "..44332..", ".4433322.", ".4332222.", "..22.21.."], ["O"], None),
    # rest: a campfire, orange and gold flames on crossed logs
    "rest": (["....7....", "...787...", "..78d76..", "..7dcd6..", "...ddc...", "44.....32", ".443.332.", "..44332..", ".43...32."], ["N", "O", "Y"], None),
    # a boss: a silver crown with a red stone
    "boss": ([".........", "4...4...3", "44.4w4.33", "444443332", "4443r3322", "444333322", "333332222", ".........", "........."], ["S"], {"r": "red2"}),
    # a star, gold, a glint at its heart
    "star": (["....4....", "...443...", "444w43332", ".4444332.", "..44332..", "..43322..", ".432.322.", ".32...21.", "........."], ["Y"], None),
    # a boat: a brown hull, a white sail on its mast
    "boat": (["....8....", "....88...", "....877..", "....8776.", "....c....", "c4444433.", ".4333322.", "..22221..", "........."], ["N", "W", "N"], None),
    # search: a lens, a steel rim round blue glass, a wooden handle
    "search": (["..4443...", ".4w8763..", "48877662.", "48776652.", "37766552.", ".3655522.", "..3222cb.", ".....cba.", "......ba."], ["S", "C", "N"], None),
    # music: two beamed notes
    "note": (["...44443.", "...43332.", "...4...3.", "...4...3.", "...4...3.", ".443.443.", "4433.4332", "3322.3221", ".21...11."], ["P"], None),
    # a breeze: white streaks of wind
    "breeze": ([".........", "444443...", ".....32..", "44444332.", ".........", ".4443....", "....32...", ".........", "........."], ["W"], None),
    # rain: a cloud and its drops
    "rain": (["...443...", ".44w4433.", "444443332", "433333322", ".2222221.", ".8..8..8.", ".6..6..6.", "8..8..8..", "6..6..6.."], ["W", "B"], None),
    # a storm: a grey cloud and a gold bolt
    "storm": (["...443...", ".4444433.", "444443332", "333333322", ".2228221.", "....88...", "...87....", "....7....", "...7....."], ["S", "Y"], None),
    # fog: banks of grey mist
    "fog": (["..44433..", ".4444333.", ".........", "444443322", ".........", ".4444332.", ".........", "..44332..", "........."], ["S"], None),
    # snow: a white snowflake
    "snow": (["....4....", ".4..4..3.", "..4.4.3..", "...434...", "444w44332", "...323...", "..3.3.2..", ".3..3..2.", "....2...."], ["W"], None),
    # blossom: a pink five-petal flower, a gold heart
    "petal": (["...443...", ".4.443.2.", "444yy3322", "44yyy3322", ".43y332..", ".43.322..", "..3..2...", ".........", "........."], ["K"], {"y": "yel3"}),
    # haze: the sun over shimmering heat
    "heat": (["...878...", "...876...", "...846...", "...836...", "...836...", "..34332..", ".34w3322.", ".3333221.", "..32211.."], ["R", "W"], None),
    # leaves: a falling leaf, its vein down the middle, a brown stem
    "leaf": ([".....443.", "....44432", "...444232", "..4443322", ".4442332.", ".442332..", ".42322...", ".c222....", "c........"], ["O", "N", "N"], None),
    # the inventory: an open cardboard box
    "inv": (["4.......3", "44.....33", "443444332", "433333322", "433343322", "433333322", "433333222", "332222221", "........."], ["N"], None),
    # Quick remove: an orange arrow going down into the box
    "takeup": (["....8....", "...887...", "..88776..", "...876...", "4..876..3", "44.876.32", "443444322", "433333222", "332222211"], ["N", "O"], None),
    # the store: a stall, a red and cream awning, gold goods on a wooden counter
    "store": (["e4e4e4e43", "e3e3e3e32", ".2.2.2.2.", ".c.....b.", ".c.87..b.", ".c.76..b.", "dccccbbba", "cbbbbbbaa", "........."], ["R", "Y", "N"], {"e": "crm3"}),
    # VIP: a gold crown with a pink stone
    "crown": ([".........", "4...4...3", "44.4w4.33", "444443332", "4443p3322", "444333322", "333332222", ".........", "........."], ["Y"], {"p": "pnk2"}),
    # the pass track: a teal ticket, a notch each side, a perforated line
    "ticket": ([".........", ".........", "444444443", "444244433", ".3323332.", "333233322", "222122221", ".........", "........."], ["C"], None),
    # a new set: two turning arrows, green over blue
    "refresh": (["..44433..", ".43...32.", "43...4321", "4.....32.", ".........", ".76.....8", "8765...78", ".76...76.", "..77766.."], ["G", "B"], None),
    # Settings: a steel gear with a hole through it
    "gear": (["...443...", ".4.443.3.", "..44433..", "443...332", "443...322", "433...322", "..33222..", ".3.322.2.", "...221..."], ["S"], None),
}
for _k, (_rows, _ramps, _flat) in ICONS.items():
    for _r in _rows:
        assert len(_r) == 9, (_k, _r)
    assert len(_rows) == 9, _k
    HAND("mini_" + _k, _rows, _ramps, _flat)

# the shell (the shells counter and every price): the scallop it had before the hand-toned redraw, its ribs meeting at
# its hinge, shaded the region way (the request of 2026-11-14: "use the same shell sprite used before")
S("mini_shell", [".........", ".FFFFFFF.", "FFFFFFFFF", "FFjFjFjFF", "FFjFjFjFF", ".FFjjjFF.", "..FFjFF..", "...FFF...", "........."], flat={"j": "org1"}, pad=True)

# A mutation's tier, in stars after its name (the request of 2026-11-14: "the * in mutations should be replaced with
# small star sprites to show the rarity of mutations"): one 7 x 7 star a tier, in the tier's colour (UI's
# Traits.TIER_COLOR: white, green, teal, gold), drawn at its own size for a 10 px line of text.
STAR_T = ["..4..", ".443.", "44432", ".432.", ".3.2."]
for _t, _ramp in enumerate(("W", "G", "C", "Y"), start=1):
    HAND("star_t%d" % _t, STAR_T, [_ramp])

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
# purple with pink spots, a legendary one gold with a band of light, a mythic one rose with a white crescent moon and
# a white band, a celestial one night blue with a little constellation of white and cyan stars.
# (an egg, not an oval: the top narrower, the widest a little low, the base fuller: "The eggs also look too much
# like perfect ovals, they should be more like eggs, with a bigger base", 2026-11-14)
EGG = [
    "....AAAA....",
    "...AAAAAA...",
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
    "...AAAAAA...",
]
EGG_BAND = [
    "....AAAA....",
    "...AAAAAA...",
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
    "...AAAAAA...",
]
EGG_MOON = [
    "....AAAA....",
    "...AAAAAA...",
    "...AAAAAA...",
    "..AAAAAAAA..",
    "..AAAxxAAA..",
    ".AAAxAAAAAA.",
    ".AAAxAAAAAA.",
    "AAAAxxAAAAAA",
    "AAAAAAAAAAAA",
    "xAxAxAxAxAxA",
    "AxAxAxAxAxAx",
    "AAAAAAAAAAAA",
    ".AAAAAAAAAA.",
    ".AAAAAAAAAA.",
    "...AAAAAA...",
]
EGG_STARS = [
    "....AAAA....",
    "...AAAAAA...",
    "...AAAAyA...",
    "..AAAAAAAA..",
    "..AxAAAAAA..",
    ".AAAAAAAzAA.",
    ".AAAAAAAAAA.",
    "AAAAzAAAAAAA",
    "AAAAAAAAAxAA",
    "AAAAAAAAAAAA",
    "AAxAAAzAAAAA",
    "AAAAAAAAAAAA",
    ".AAAAAAAAxA.",
    ".AAAzAAAAAA.",
    "...AAAAAA...",
]
for _r, (_mask, _body, _spot) in enumerate([(EGG, "E", "n"), (EGG_BAND, "G", "w"), (EGG, "B", "w"), (EGG, "P", "p"), (EGG_BAND, "Y", "w"), (EGG_MOON, "H", "w"), (EGG_STARS, "I", "w")], start=1):
    S("egg_%d" % _r, [row.replace("A", _body).replace("x", _spot) for row in _mask], sphere={"body": _body, "light": "wyz", "dark": "np"})
# Build mode's puff of dust (Controllers/Puffs): a little cloud that swells, then thins out and breaks up.
S("poof_1", [".......", ".......", "..ww...", ".wwws..", ".wsss..", "..ss...", "......."], outline=False, shade=False)
S("poof_2", [".......", "..ww...", ".wwwws.", "wwwssss", ".wssss.", "..sss..", "......."], outline=False, shade=False)
S("poof_3", [".......", ".w...w.", "w.....s", ".......", "s.....s", ".s...s.", "......."], outline=False, shade=False)
# A rare egg's twinkle (EggView's sparks): a small white star that opens and closes, cyan at its tips.
S("twinkle_1", [".......", ".......", "...c...", "..cwc..", "...c...", ".......", "......."], outline=False, shade=False)
S("twinkle_2", [".......", "...c...", "...w...", ".cwwwc.", "...w...", "...c...", "......."], outline=False, shade=False)
# A mythic egg's twinkle: the same star in pink, opening to a cross with its corners lit.
S("twinkle_p1", [".......", ".......", "...p...", "..pwp..", "...p...", ".......", "......."], outline=False, shade=False)
S("twinkle_p2", [".......", "...p...", "...w...", ".pwwwp.", "...w...", "...p...", "......."], outline=False, shade=False)
S("twinkle_p3", ["...p...", ".q.p.q.", "..qwq..", "ppwwwpp", "..qwq..", ".q.p.q.", "...p..."], outline=False, shade=False, flat={"q": "pnk3"})
# A celestial egg's glint: a long thin cross of light that grows, then its diagonals in pink, cyan at the tips.
S("glint_1", [".........", ".........", ".........", "....z....", "...zwz...", "....z....", ".........", ".........", "........."], outline=False, shade=False)
S("glint_2", [".........", "....z....", "....z....", "....w....", ".zzwwwzz.", "....w....", "....z....", "....z....", "........."], outline=False, shade=False)
S("glint_3", ["....c....", ".q..z..q.", "..q.w.q..", "....w....", "czwwwwwzc", "....w....", "..q.w.q..", ".q..z..q.", "....c...."], outline=False, shade=False, flat={"q": "pnk3"})
S("heart", [".........", ".KK...KK.", "KKKK.KKKK", "KwKKKKKKK", "KKKKKKKKK", ".KKKKKKK.", "..KKKKK..", "...KKK...", "....K....", "........."])

# ---------------------------------------------------------------- the islands' small lives (Controllers/AmbientView)
# Drawn into the pixel layer by Render/Fx, in the world: one sprite pixel is one art pixel, so each has its own small
# version for a screen that shows the island small (a phone: "s" after the name). Hand-shaded with digit tones (0 deep,
# 1 shadow, 2 base, 3 light, from the top left); the creatures get the 1 px ink outline, the grass, flowers, leaves and
# glints are ground and light, drawn without one (like the sparks). No "_flash" for these. A tinted sprite draws its
# "0".."3" in the tones of a colour given at draw time (Render/Fx.TONES): a tuft in the lawn's own green, a leaf in its
# tree's, a flower or a butterfly in its own colour.
PIP = {"0": "tel0", "1": "tel1", "2": "tel2", "3": "tel3", "5": "crm1", "6": "crm2", "7": "crm3", "o": "org2"}
WREN = {"0": "brn0", "1": "brn1", "2": "brn2", "3": "brn3", "5": "cor1", "6": "cor2", "7": "cor3", "x": "blk"}
GULL = {"1": "wht0", "2": "wht1", "3": "wht2", "4": "wht", "s": "gry2", "d": "gry1", "t": "drk0", "y": "yel2"}
TINT = {"0": "tn0", "1": "tn1", "2": "tn2", "3": "tn3"}
FISH = {"1": "blu0", "2": "blu1", "3": "gry3", "4": "wht", "w": "wht2"}  # a silver fish, its back blue
FX = {
    # a teal pip with a crest, a cream breast and an orange beak: sitting, pecking, wings up, wings down (facing right)
    "pip": (PIP, [
        ["....3...", "...3322.", "..322k2o", "22222776", ".1222665", "..11555."],
        ["........", "21......", ".2333...", "..12222.", "..12k22o", "...5662.", "....55.."],
        [".33.....", ".233....", "..2333..", "22222k2o", ".1222776", "..11555."],
        ["....332.", "22223k2o", ".2322776", "..12065.", "..01...."],
    ]),
    "pips": (PIP, [
        ["..3.", ".22o", "2276", ".15."],
        ["....", "2...", ".22.", ".12o", "..5."],
        ["3...", ".33.", "222o", ".15."],
        ["....", "..2.", "222o", "215."],
    ]),
    # a sandy wren with a coral breast and a cocked tail: sitting, pecking, wings up, wings down
    "wren": (WREN, [
        ["2.......", "21..332.", ".2232kx.", "..222776", "..122665", "...1555."],
        ["........", "2.......", "21......", ".22333..", "..1222k2", "...2266x", "....555."],
        [".33.....", "2.333...", "21.2332.", ".2222kx.", "..122776", "...1155."],
        ["2...332.", "21222kx.", ".122277.", "..10266.", "..01...."],
    ]),
    "wrens": (WREN, [
        ["2...", "2.2x", ".276", "..15"],
        ["....", "2...", "222.", ".12x", "..5."],
        ["3...", "2.3.", ".22x", "..15"],
        ["....", "2.2.", "222x", "21.5"],
    ]),
    # a gull for the beach: standing, looking down, wings up, wings down
    "gull": (GULL, [
        ["......334..", ".....3342ky", "dsss33332..", ".tdsss3332.", "..tdss3321.", "...11111..."],
        ["...........", "......334..", "dsss33342k.", ".tdsss333y.", "..tdss332y.", "...11111..."],
        ["ss........ss", ".sss....sss.", "...dss3ss...", "....t3343kyy", ".....1111..."],
        ["............", "....334.....", "dss33343kyy.", ".ssd2233....", "..sss11.....", "...ss......."],
    ]),
    "gulls": (GULL, [
        ["...34.", "...3ky", "ds332.", ".t221."],
        ["......", "ds33..", ".t2334", "..12ky"],
        ["s...s.", ".s3s..", "..t3ky", "...11."],
        ["......", "..334.", "ds33ky", ".s11.."],
    ]),
    # a fish leaping out of the sea: nose up, level, nose down (facing right)
    "fish": (FISH, [
        ["....3.", "...34.", "..3k4.", "2.32..", ".22...", "2....."],
        ["2..34.", ".233k4", "2.22w."],
        ["2.....", ".22...", "2.33..", "..3k4.", "...34.", "....w."],
    ]),
    "fishs": (FISH, [
        ["..3", ".34", "2.."],
        ["2.34", ".23k"],
        ["2..", ".33", "..4"],
    ]),
}
for _name, (_flat, _frames) in FX.items():
    for _k, _rows in enumerate(_frames, start=1):
        S("fx_%s_%d" % (_name, _k), _rows, flat=_flat, shade=False, pad=True)
# grass tufts (upright, leaning right, leaning left as a gust goes by) and flowers (upright, leaning), tinted: a tuft
# by the lawn under it, a flower's petals by their colour (its stem stays green)
GROUND = {
    "tuft": [["..3..", "3.3.3", ".232.", ".1.1."], ["...3.", ".3.33", ".232.", ".1.1."], [".3...", "33.3.", ".232.", ".1.1."]],
    "tufts": [["3.3", ".1."], [".3.3", ".1.."], ["3.3.", "..1."]],
    "flower": [[".3.", "3y2", ".1.", ".g.", ".l."], ["..3.", ".3y2", "..1.", ".g..", ".l.."]],
    "flowers": [["3", "g"], [".3", "g."]],
}
for _name, _frames in GROUND.items():
    for _k, _rows in enumerate(_frames, start=1):
        S("fx_%s_%d" % (_name, _k), _rows, flat=dict(TINT, y="yel2", g="grn1", l="grn0"), shade=False, outline=False)
# a butterfly (wings open, wings folded; tinted by its colour, its body ink)
for _k, _rows in enumerate([["33.33", "32k23", ".1k1."], [".33..", ".32k.", "...k."]], start=1):
    S("fx_bfly_%d" % _k, _rows, flat=TINT, shade=False, outline=False)
# a leaf and a petal tumbling down (tinted by their tree), a glint on the sea, a ring spreading where a fish splashed
for _k, _rows in enumerate([[".3", "21"], ["32", ".1"], ["3", "2", "1"], ["321"]], start=1):
    S("fx_leaf_%d" % _k, _rows, flat=TINT, shade=False, outline=False)
for _k, _rows in enumerate([["32"], ["3", "2"], ["23"]], start=1):
    S("fx_petal_%d" % _k, _rows, flat=TINT, shade=False, outline=False)
# a snowflake drifting down (the weather, GAME_DESIGN 13): a small one, a round one, a star with soft arms (no outline:
# white on the light; the arms a step greyer, the flake's anti-aliasing)
for _k, _rows in enumerate([["w"], ["wh", "hz"], [".h.", "hwh", ".h."]], start=1):
    S("fx_flake_%d" % _k, _rows, flat={"w": "wht", "h": "wht2", "z": "wht1"}, shade=False, outline=False)
for _k, _rows in enumerate([["w"], [".z.", "zwz", ".z."], ["..z..", "zwwwz", "..z.."]], start=1):
    S("fx_glint_%d" % _k, _rows, shade=False, outline=False)
for _k, _rows in enumerate([[".hh.", "h..h", ".hh."], ["..hhh..", "hh...hh", "..hhh.."]], start=1):
    S("fx_ripple_%d" % _k, _rows, flat={"h": "wht2"}, shade=False, outline=False)

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
# A round thing's tones (the eggs: the request of 2026-11-14, "The egg sprites seem flat and have no depth. Reshade
# them"): the silhouette taken as the front of an egg (its ellipse, its middle a little low: an egg is fuller at the
# bottom), each pixel's slope lit from the top left and a little in front. A highlight (3) in a soft patch up at the
# top left, the base (2) over the middle, a shadow (1) crescent round the lower right and a deep (0) rim where the
# shell turns away, the bands smooth (no dither, no stray pixels: a lone pixel takes its neighbours' band).
def sphere_tones(grid, w, h):
    pts = [(x, y) for y in range(h) for x in range(w) if grid[y][x] != "."]
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    cx = (min(xs) + max(xs)) / 2
    cy = (min(ys) + max(ys)) / 2 + 0.7
    rx = (max(xs) - min(xs)) / 2 + 0.6
    ry = (max(ys) - min(ys)) / 2 + 0.6
    lx, ly, lz = -0.45, -0.55, 0.70
    ln = math.sqrt(lx * lx + ly * ly + lz * lz)
    lx, ly, lz = lx / ln, ly / ln, lz / ln
    tone = [[2] * w for _ in range(h)]
    for x, y in pts:
        nx = (x - cx) / rx
        ny = (y - cy) / (ry + (0.9 if y < cy else 0.0))  # the narrow top curves away faster
        r2 = min(nx * nx + ny * ny, 0.98)
        nz = math.sqrt(1 - r2)
        d = nx * lx + ny * ly + nz * lz
        tone[y][x] = 3 if d > 0.84 else 2 if d > 0.42 else 1 if d > 0.14 else 0
    # a lone pixel of a band takes its neighbours' (no specks in the gradient)
    for x, y in pts:
        t = tone[y][x]
        nb = [tone[y + dy][x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if 0 <= x + dx < w and 0 <= y + dy < h and grid[y + dy][x + dx] != "."]
        if nb and all(n != t for n in nb):
            tone[y][x] = max(set(nb), key=nb.count)
    return tone


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
    sph = spec.get("sphere")
    tones = sphere_tones(grid, w, h) if sph else cel_tones(grid, w, h)
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
                # (on a round thing a light mark turns with the shell: in its shadow the body's light tone, at its
                # rim the body's base, so the marks curve round it too)
                if sph and c in sph.get("light", "") and tones[y][x] <= 1:
                    key = RAMPS[sph["body"]][3 if tones[y][x] == 1 else 2]
                elif sph and c in sph.get("dark", "") and tones[y][x] == 0:
                    key = RAMPS[sph["body"]][0]
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
        hand = spec.get("hand")
        if hand:
            # (a hand-toned icon: the same rule on its ramp characters; glints, eyes and flat marks stay as drawn)
            for y in range(1, h - 1):
                for x in range(1, w - 1):
                    rt = hand.get(grid[y][x])
                    if rt is None:
                        continue
                    if any(outl[y + dy][x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                        continue
                    diag = [(dx, dy) for dx, dy in ((1, 1), (-1, 1), (1, -1), (-1, -1)) if outl[y + dy][x + dx]]
                    if not diag:
                        continue
                    r, t = rt
                    if t == 3:
                        t = 2
                    elif t == 2 and any(d != (-1, -1) for d in diag):
                        t = 1
                    elif t == 1 and (1, 1) in diag:
                        t = 0
                    px[y][x] = (PAL[RAMPS[r][t]], 1.0)
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
        if name.endswith("_alt") or name.startswith("fx_"):
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
LOOK_HEAD = ["-- GENERATED by scripts/gen_art.py from scripts/cosmetic_thumbs.txt: do not edit (sh tools/preview/cosmetic_thumbs.sh",
             "-- draws them again from the pieces' models). The cosmetics' pictures, \"look_<id>\", 24 x 24, in UI/ArtData's format:",
             "-- one character a pixel, \".\" clear, else an index into `pal` (0xRRGGBB) with its `alpha` (0..1). Drawn with",
             "-- UI/PixelSprites (UI/CosmeticIcons). docs/ARCHITECTURE.md 10.10; the pixel art rules: GAME_DESIGN 2."]


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
    ap.add_argument("--looks-out", default=os.path.join(root, "src", "client", "UI", "CosmeticThumbData.luau"))
    ap.add_argument("--png", default=None)
    ap.add_argument("--zoom", type=int, default=6)
    a = ap.parse_args()
    sprites = all_sprites()
    emit(sprites, a.out)
    emit(THUMBS, a.thumbs_out, THUMB_HEAD)
    emit(LOOKS, a.looks_out, LOOK_HEAD)
    if a.png:
        png(sprites, a.png, a.zoom)
    print("%d sprites -> %s" % (len(sprites), a.out))
    print("%d pictures -> %s" % (len(THUMBS), a.thumbs_out))
    print("%d cosmetic pictures -> %s" % (len(LOOKS), a.looks_out))


if __name__ == "__main__":
    main()
