# Driftling Isle: Game Design

> The request (2026-11-10): "scrap this idea. could you make replicate beasty bay from kariosoft instead? still use the
> test repo as a reference"

We do not copy another studio's game (its name, creatures, islands, story or art). Asked which way to go, the answers
were: **an original game in the same genre** ("Yes, original game"); its loop **"Island building + farming, Creature
taming, Expeditions + battles, Villagers moving in"**; its world **"Shared sea of islands"**. Earlier requests still
hold where they apply: the first ("reference game dev story from kariosoft and make a simplified version of it in
gamedevtest. dont touch the "test" repo at all, only use it for reference"), the pixel art rules (§2) and the polish
requests (§11). The game studio of the earlier versions is gone (§10: an old save starts a fresh island).

Driftling Isle is a small island-village management game for Roblox. You wash up on a little island with a campfire
on its sand. You build food, wood and shops round it, visitors come for its charm and move into the homes you build, and your
villagers take jobs. You sail out to the islets nearby with a party of villagers, befriend the wild **driftlings**
there with treats in turn-based battles, and bring them home to help at the buildings of their knack. Beating each
islet's guardian opens the next. The islands of everyone on the server sit side by side along one boardwalk on a
shared sea. The look, the build system and the file formats come from our own Random Bakery (`Downvote/test`): the
2:1 pixel-art isometric diorama seen through the pixel filter, the pixel font, Rojo with strict Luau, a server that
decides everything, pure Data/Logic modules with specs, and the fake-engine simulator and preview tools.

## 1. The loop in one paragraph

Build a Veggie Patch so the island has food, a Tent so a castaway can move in at dawn, a Lumber Camp for wood and a
Snack Stall to sell food to the visitors for shells. Every day (Tuning.DaySeconds while you play) the island makes and
eats; a visitor moves into a free bed when the charm is high enough and takes a free job. Build a Driftling Nest,
then Explore: pick a party (you, the captain, and up to three villagers or driftlings), pay the supplies in food and
sail to an islet. Walk its path of stops (loot, chests, a rest, battles with wild driftlings, the guardian at the
end); in battle choose Fight, Guard, Treat (food: a hurt wild one may join you) or Flee. Sail home with the loot.
Spend shells and wood on more buildings, upgrades (a making building's Lv 2 and 3) and decor (charm), and expand the
island twice for bigger buildings. Nothing happens while you are away (no offline progress).

## 2. Look and feel

- **World:** one island per player along a shared boardwalk on the open sea, each of its own shape with a campfire at
  its heart, its grass, a sand beach and a shore stepping down into a moving sea (§8), seen from the Random Bakery
  camera: orthographic, yaw 45°, pitch 30°, the 2:1 pixel-art "isometric" grid, always centred on your founder. Everything is built from parts in code (no
  meshes, decals or uploaded images).
- **Pixel filter:** the same pipeline as Random Bakery's: a raycast G-buffer baked progressively, three toon bands
  from one sun, sun shadows, a palette LUT, a 1 px ink outline, and the characters drawn analytically every tick on
  top with the same projection. One pixel size K for the world, the UI and the text. Shadows keep the grid: the sun's
  ray is cast once for each 2x2 pixels, and every pixel on a shadow's edge then casts its own, so a shadow's edge
  steps one pixel at a time (the bug report, 2026-11-10: "some shadows appear to be blocky and have mixels, not
  respecting the pixel grid").
- **Villagers** are little chibis (their own looks) walking the island and working at their buildings (hoeing,
  chopping, selling); **driftlings** are small 3D creatures of our own design hopping about and helping.
- **Interface:** pixel-art plates with stepped corners, the pixel font, no borders; every driftling has a 16x16
  portrait and the island's things 11x11 icons, drawn by the rules below.
- **The founder:** you walk your island and the boardwalk as a chibi founder (§9).

**The pixel art rules** (they hold for every sprite, icon, scene and effect, now and from now on):

> The request (2026-11-09): "for pixel art, always dont use mixels. use pixel art techniques such as anti-aliasing,
> avoiding jaggies, and avoiding mixels, and use a 1 pixel outline. respect the pixel art grid. polish the minigames
> much much more"

- **No mixels.** One art pixel is one UI px is one K-sized block on the screen: nothing is ever drawn scaled up
  (no 2x or 3x sprites). A bigger or smaller thing is its own sprite drawn at its own size: a driftling's portrait is
  16x16, a small icon 11x11. The islets' stages are 3D (§7) and drawn by the pixel filter like the islands, so they keep
  the same grid, palette and outline.
- **The grid.** Sprites, scenes and effects sit at whole UI px: moves and tweens snap to whole pixels, particles are
  1 px bits, confetti 1 px pieces and 1x2 sticks (never a 2x2 block).
- **A 1 px ink outline** round every sprite's silhouette (the 4-neighbours, so a convex corner is cut, never doubled),
  and inner ink lines where shapes meet.
- **Anti-aliasing, no jaggies.** Where the outline steps, the empty corner pixel gets a faint ink (35%); a colour
  region's pixel that meets the outline only at a corner goes a tone darker; skies blend between bands with a 1 px
  dither row; lines are drawn at clean slopes (a slash is a 1:1 diagonal).
- **Shading:** every colour region is a 4-tone ramp lit from the top left (light top-left edge, shadow bottom right,
  a second shadow band on big shapes), from one shared palette.
- **One source:** `scripts/gen_art.py` holds every sprite as a text mask and makes `UI/ArtData` (and a contact sheet
  with `--png`); the client draws each sprite once into an EditableImage shown pixelated (or from 1 px rects).

## 3. The island's day (`Logic/Island`)

- A day is `DaySeconds` (40 s) while you are on the server; the HUD shows the day and its clock (a sun, a moon for
  the evening). Each building that makes something makes its rate a day: full with a villager working there, half
  with nobody (`IdleOutput`), more with a driftling of its knack helping (`PalBoost`), more again at Lv 2 and 3
  (`UpgradeMult`). Villagers eat `EatFolk` food a day, driftlings `EatPal`.
- **Shops** sell food to the visitors: their rate times visitors / `ShopVisitors` (at most double), eating food the
  same way. **Visitors** a day: 1 + charm / `VisitorCharm`, at most `VisitorsMax`.
- **Charm:** every piece's charm, one for each driftling, three for each islet opened.
- **Hunger:** when the food runs out everything makes half and the shops shut until there is food again; the food
  chip blinks red.
- The stores reach the client every second; a new day brings a banner (who moved in, who trained).

## 4. Building (`Data/Buildings`, `Logic/Plot`, Build mode)

27 pieces in seven kinds: **food** (Veggie Patch, Fishing Pier, Fruit Orchard, Greenhouse), **wood** (Lumber Camp,
Sawmill), **shops** (Snack Stall, Beach Cafe, Seaside Inn), **homes** (Tent, Grass Hut, Cottage: beds), **nests**
(Driftling Nest, Cozy Burrow: room for driftlings), the **Training Yard** (resting villagers and driftlings gain xp
each dawn) and **decor** (flowers to a lighthouse and a guardian statue: charm). Each is paid in shells and wood when
placed, on whole studs of the island's grass (a stud or more in from the sand), turned a quarter at a time, off the
campfire's plaza and the path to the jetty, and off every other piece, up to the island's piece limit (`PlotPieces`). The bigger buildings wait for a
bigger island (tier 2 or 3).

- **Build mode** (the HUD's Build): the view frees to pan over the island; a tray of tabs (Food, Wood, Shops, Homes,
  Nests, Decor) lists every piece with its price (red when you are short, locked ones greyed with the tier they
  need). A picked piece is a ghost on a cyan footprint where it fits, red where not; Place (or a second click on the
  same spot) builds it. Tapping a standing piece picks it up to move, **Upgrade** it (a building that makes
  something: Lv 2 and 3 for `UpgradeCost` times its price, making `UpgradeMult` times as much) or **Clear it away**
  (half its price back; not a home or nest whose beds are needed).
- **Expand** (in the tray's header): the island grows twice (`TierCost`): Castaway Cay, Palm Isle, Grand Isle, its coast
  reaching further out round the same campfire. A piece that no longer fits moves to the nearest free spot (none is
  lost; one with no spot left would be cleared with its whole price back).

## 5. Villagers (`Logic/Island`, the Villagers panel)

A visitor moves in at dawn when there is a free bed (`FolkMax` at most) and the charm is at least `MoveInCharm` times
the villagers already living there. A newcomer takes a free job straight away (food first, then wood, then shops).
The Villagers panel lists each one (portrait, level, job, battle stats) with **Job** (a picker of the buildings that
take workers: Go, Swap with whoever is there, or Rest) and **Dismiss** (two taps: they sail off, freeing the bed).
Each villager has their own fighting stats (from their seed) and a skill (Big Bonk, Soothe or Shell Guard), and grows
with levels (xp from battles and the yard).

## 6. Driftlings (`Data/Creatures`, the Driftlings panel, the Index)

Fifteen driftlings of our own, three on each islet: Pebblit, Clawdle, Gullfin (Pebble Beach); Mossbun, Frondle,
Twiggle (Mossgrove); Emberpup, Magmole, Scorchwing (Cinder Rock); Snowpuff, Floe, Frostling (Frostcap); Lumajelly,
Novafox, Tidewyrm (Coral Deep). Each has battle stats, a skill (Big Bonk, Double Dash, Splash Wave, Soothe, Shell
Guard), a **knack** (farms, fishing piers, lumber camps or shops: where it helps), a trust (how readily a treat
befriends it), a 3D model and a portrait. A befriended driftling needs a free nest slot (`PalsMax` at most) and starts
helping where its knack is needed. The Driftlings panel shows each (portrait, level, skill, where it helps, stats)
with **Help** (a picker of the buildings of its knack, or Rest) and **Release** (two taps). The **Index** lists all
fifteen: dark until met, named once met, its blurb and a heart once befriended.

## 7. Expeditions and battles (`Data/Islets`, `Logic/Expedition`, `Logic/Battle`, the islet's screen)

- **Five islets** open one after another: Pebble Beach (Lv 1+), Mossgrove (5+), Cinder Rock (10+), Frostcap (16+),
  Coral Deep (23+). Each has a path of 8 to 11 stops: the landing, loot (food and wood), chests (shells), wild
  battles, a rest (the party heals half), and the guardian (a bigger driftling with a friend). Beating the guardian
  pays its reward (half on later trips) and opens the next islet.
- **The party:** the captain (you) and up to `PartyMax` villagers or driftlings, picked in the Explore panel (the
  strongest listed first). Supplies: `Supplies` food each. While away they neither work nor eat; they can't be
  dismissed or released. One expedition at a time; leaving the game brings it home with its loot.
- **Battles**, round by round: you pick what the party does; then everyone acts in speed order. A fighter attacks
  (the party the weakest foe, a wild one a random member) or, every `SkillEvery` actions, uses its skill. **Guard**
  takes half the damage and mends a little; **Treat** (`TreatFood` food, a free nest) offers a treat to a wild one
  (tap its card; the most hurt by default): it may join you (its trust, more the more hurt, less the higher its
  level); **Flee** may get away. A guardian can't be befriended or fled from. A win gives xp to the party (levels) and
  shells; the knocked-out get up with a quarter of their health. If the party falls, the expedition is over and half
  the loot comes home.
- **The islet's screen** (3D, full screen): the islet's own stage (an islet of its own, its shore stepping down
  into the moving sea: a beach with leaning palms, a treasure chest, tide pools and a rowboat; a mossy meadow with
  ferns, mushrooms and a fallen log; Cinder Rock's dark sand by a volcano with lava running down it; a snowfield by a
  snowy peak with pines, ice crystals and a frozen pond; the sea floor's corals, kelp, anemones, clams and a sunken
  anchor), drawn by the pixel filter, with
  the party on the left (your founder, villagers as their chibis, driftlings as their models) and the wild ones
  dropping in on the right. Along the top: the islet, the loot so far, the path of stops (the ones ahead hidden but
  the guardian's crown) and Back to island (the expedition waits; the HUD's card brings you back). Along the bottom:
  the party's cards with their health bars and levels, and the buttons (Go on and Sail home between stops; Fight,
  Guard, Treat and Flee in battle; Space or 1-4 on a keyboard). A round plays back: lunges, flashes, damage numbers,
  skills' names, heals, shells, a treat's hearts, knock-outs; a win shows its xp, shells and level-ups, a new friend
  its portrait with confetti, a guardian's fall the next islet.

## 8. The islands and the sea (`Data/Street`, `Models/StreetModels`, `Models/DecorModels`)

> The request (2026-11-10): "make islands more irregular like actual islands, add shorelines, animated water,much
> much more detail and polish to all models and islands, no need for the house. in the main island, make the camera
> always center to the player."

- **Islands like islands:** each island's coast is a wobbly oval of whole-stud cells (an oval a tier, four sine
  wobbles of their own phases), with its bays and points. From the coast inward is the grass; outward a sand beach,
  wet sand, the foam line and the shallows, each a little lower than the one inside it, so the shore steps down into
  the sea. Buildings stand on the grass a stud or more in from the sand.
- **No house:** the island's heart is a plaza round a campfire (fire stones, logs, a flame with smoke, seats, a flag
  and torches); a path of stepping stones runs from it down to a wooden jetty that meets the boardwalk, your sign and
  mailbox either side of its foot. Villagers stroll the grass round it when they rest.
- **The water moves:** the sea, the shallows and the foam are redrawn a few times a second by the pixel filter: swells
  roll across in bands with crests catching the light and dark troughs, and the foam laps at the sand. The fishing
  pier's pond, the fountain and the islets' seas and pools move the same way.
- **Detail everywhere:** palms that lean, rocks, shells, starfish, driftwood, seaweed and flowering tufts strewn by
  each island's own seed; the boardwalk's planks on beams and posts with rope rails and lanterns; a pier with a moored
  boat. Every building has its doors, windows, ridged roofs with eaves, crates, barrels, sacks and pots, its own
  touches (the patch's scarecrow, the pier's fishing hut and pond, the hut on stilts, the stall's awning, the
  lighthouse's lamp) and, at Lv 3, a lamp and a pennant. Driftlings have shiny eyes, cheeks and a mouth.
- **The camera** follows your founder and always keeps them in the middle of the view between the HUD's strips, at one
  zoom on every tier; Build mode frees it to pan.
- Up to `MaxPlots` (6) islands sit in a row along the boardwalk; an unclaimed lot is open water with a sandbar and a
  sign. Sailboats cross the sea, gulls fly over and cloud shadows drift across. You can walk onto anyone's island
  (the shore's edge holds you back from the sea); Home sends you back to your own. A tap on a sign shows that island's
  day, villagers, driftlings, charm and islets.

## 9. Your founder, settings and the tips

The Looks panel sets the founder's skin, hair, style and shirt (every client sees it). Settings: the pixel filter's
quality. **The tips** (the banner over the menu bar): 1 build food, 2 build a home, 3 build a nest and sail to
Pebble Beach, 4 treat a hurt wild one (OK ends them).

## 10. Saves and the economy, checked

The save is version 5 (`Logic/Schema`): an older save (the game studio's) keeps the founder's look, the settings and
its start date and begins a fresh island with the tips. `tests/Career.luau` plays a sensible player through the same
rules (`Logic/*`) for three seeds and three hours; `tests/specs/Economy.spec.luau` holds the economy to these bounds:

- a villager within 3 minutes, a driftling friend within 15;
- the guardians of the first islet within 15 minutes, the second 45, the third 90, the fourth 150; the last islet is
  a long-term goal (past two hours);
- the island's second tier within 45 minutes, the third within 90; at an hour, at least 8 villagers and 8 driftlings;
- nobody starves for long, and the stores stay finite.

## 11. Polish and animation

> The requests (2026-11-06, 2026-11-09): "make the it more polished and animated as well"; "Polish everything to the
> max. Add animations and details to everything, including the minigames"

- **Buttons** lighten under the mouse, sink a pixel while pressed, click when used and buzz when disabled; panels and
  cards fade and rise in; notices slide down.
- **The HUD:** the stores count up and their chip flashes when they change, shells coming in rise from their chip
  ("+12"); the day chip's clock bar creeps along and its sun sets into a moon; the food chip blinks red while hungry;
  the expedition card's Continue pulses and gleams; a new tip bounces in; a new day's banner drops in (with a fanfare
  and bits when someone moved in).
- **The island lives:** villagers walk to their work and back and do it (hoe, chop, sell), wander when resting;
  driftlings hop beside their buildings or round the nests; a newcomer is welcomed with a word and confetti.
- **The sea lives:** the water rolls and the foam laps the shore (§8), sailboats rock on the swell as they cross both
  ways, gulls cross now and then, clouds' shadows slide over the islands; each island's campfire flickers and smokes.
- **The islet's screen:** ink blinds open from the middle on the islet's name; the party and the wild ones drop in
  from above in puffs of dust; each stage has its ambient life (gulls and a glinting chest on the beach, butterflies
  in the meadow, volcano smoke, falling snow, bubbles and a crab on the sea floor); hits lunge, flash and spark,
  numbers float up, skills shout their names, heals and shells twinkle, a treat bursts into hearts, a friend leaves in
  confetti, a win cheers and throws confetti.
- **Sounds** (`Controllers/Audio`): every event plays a Creator Store library sound (the ones Random Bakery uses), its
  pitch varied a little, repeats inside a short cooldown dropped.

## 12. Out of scope for this version

Trading between players, visiting with gifts, offline progress, purchases (no game passes or products:
`Config/Monetization.luau` holds only the sound ids), music, other languages (English only; every string goes through
`Locale/Lang.t`).
