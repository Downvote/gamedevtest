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
villagers take jobs. You sail out with a party of villagers to the islands of your own sea chart (the further from
home, the higher their level; a bigger boat sails further), befriend the wild **driftlings** there with treats in
turn-based battles, and bring them home to help at the buildings of their knack. Beating an island's guardian charts
it. The islands of everyone on the server sit side by side along one boardwalk on a
shared sea. The look, the build system and the file formats come from our own Random Bakery (`Downvote/test`): the
2:1 pixel-art isometric diorama seen through the pixel filter, the pixel font, Rojo with strict Luau, a server that
decides everything, pure Data/Logic modules with specs, and the fake-engine simulator and preview tools.

## 1. The loop in one paragraph

Build a Veggie Patch so the island has food, a Tent so a castaway can move in at dawn, a Lumber Camp for wood and a
Snack Stall to sell food to the visitors for shells. Every day (Tuning.DaySeconds while you play) the island makes and
eats; a visitor moves into a free bed when the charm is high enough and takes a free job. Build a Driftling Nest,
then Explore: the sea chart shows the islands round yours; tap one in your boat's range, pick a party (you, the
captain, and up to three villagers or driftlings), pay the supplies in food and set sail: your founder boards the boat
at the pier and it sails off to that island. Walk its path of stops (loot, chests, a rest, battles with wild driftlings, the guardian at the
end); in battle choose Fight, Guard, Treat (food: a hurt wild one may join you) or Flee. Sail home with the loot (the
boat brings the party back to the pier). Spend shells and wood on more buildings, a bigger boat (further islands), upgrades (a making building's Lv 2 and 3) and decor (charm), and expand the
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
  chopping, selling): shorts over bare shins, shoes on light soles, a shirt with a collar, buttons and a belt with a
  buckle, sleeves over bare forearms and fists, ears, brows, a mouth and a glint in each eye; knees and elbows bend,
  and the face changes (fierce, shouting, hurt, happy, out cold). **Driftlings** are small 3D creatures of our own
  design hopping about and helping, each with its own details (moss and stubby arms on the pebble, bubbles on the
  crab, whiskers and a sprout on the bun, wing bones on the bat...) and limbs that move (§7).
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
- **Anti-aliasing, no jaggies.** A pixel that meets the outline only at a corner goes a step toward the shadow
  (never a dark speck on the lit side); skies blend between bands with a 1 px dither row; lines are drawn at clean slopes (a slash is a 1:1 diagonal).
- **Shading:** matte cel steps over the whole silhouette, lit from the top left (never a band hugging each colour
  region's edges: no pillow shading): the base tone does most of the work, a 1 px shadow runs along the bottom and
  right edges (two under a portrait's belly) and a short light along the upper half of the top-left edges. The ramps'
  steps are close, no white glints and no near-black to near-white sweeps: nothing looks like polished metal.
- **Hue shifting:** a ramp's darker tones lean cool (towards blue and purple), its lighter ones warm (towards yellow),
  never only darker or lighter of the same hue.
- **Calm and readable:** no grain or speckle noise; a material reads from its colour and silhouette. Every sprite is
  first a silhouette that tells what it is on its own: each driftling its own outline (the crab's raised pincers,
  the bun's long ears, the pup's floppy ears and flame, the fox's tall ears and pointed chin, the mole's claws, the
  owl's tufts and round eyes, the jelly's tentacles...), each icon a plain object (an apple, a log, a scallop shell,
  a house, an egg in a nest, a dumbbell, a flower, a sack, a paw print, a campfire, a hat on the visitor).

  > The request (2026-11-10): "the sprites still look too busy and hard to read. make sure each sillouhette is
  > distinct enough to tell what the sprites are. the sprites also all look metallic"
- **The outline is not anti-aliased on its outside:** the ink edge stands against the background as it is; the
  softening is inside (the anti-aliasing above).

> The request (2026-11-10): "alot of the sprites seem to be pillow shaded without regard to texture. can you do some
> respriting? also, no need to anti alias the outside of the outline. also, make sure to use hueshifting when deciding
> to use darker or lighter shades of colors"

- **One source:** `scripts/gen_art.py` holds every sprite as a text mask and makes `UI/ArtData` (and a contact sheet
  with `--png`); the client draws each sprite once into an EditableImage shown pixelated (or from 1 px rects).

## 3. The island's day (`Logic/Island`)

- A day is `DaySeconds` (40 s) while you are on the server; the HUD shows the day and its clock (a sun, a moon for
  the evening). Each building that makes something makes its rate a day: full with a villager working there, half
  with nobody (`IdleOutput`), more with a driftling of its knack helping (`PalBoost`), more again at Lv 2 and 3
  (`UpgradeMult`). Villagers eat `EatFolk` food a day, driftlings `EatPal`.
- **Shops** sell food to the visitors: their rate times visitors / `ShopVisitors` (at most double), eating food the
  same way. **Visitors** a day: 1 + charm / `VisitorCharm`, at most `VisitorsMax`.
- **Charm:** every piece's charm, one for each driftling, `ChartCharm` (3) for each island charted, up to
  `ChartCharmMax` (15).
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

Fifteen driftlings of our own, three living on each kind of island: Pebblit, Clawdle, Gullfin (beaches); Mossbun,
Frondle, Twiggle (meadows); Emberpup, Magmole, Scorchwing (volcanoes); Snowpuff, Floe, Frostling (snowfields);
Lumajelly, Novafox, Tidewyrm (reefs). Each has battle stats, a skill (Big Bonk, Double Dash, Splash Wave, Soothe, Shell
Guard), a **knack** (farms, fishing piers, lumber camps or shops: where it helps), a trust (how readily a treat
befriends it), a 3D model and a portrait. A befriended driftling needs a free nest slot (`PalsMax` at most) and starts
helping where its knack is needed. The Driftlings panel shows each (portrait, level, skill, where it helps, stats)
with **Help** (a picker of the buildings of its knack, or Rest) and **Release** (two taps). The **Index** lists all
fifteen: dark until met, named once met, its blurb and a heart once befriended.

## 7. Expeditions and battles (`Data/Islets`, `Logic/Expedition`, `Logic/Battle`, the sailing cutscene, the islet's screen)

> The request (2026-11-10): "can the green lines of the sea be more of a light blue instead? also, make exploration
> procedurally generated instead. make a cutscene where the player gets into the boat, then sails to a random island
> with random monsters. the level and monsters of the islands you discover is determined by your (captain) level,
> and you can choose to scale it down to whatever is under your level through a slider"

> The requests (2026-11-10): "make exploration more like a map: there are different islands, and opening the map
> shows available islands in a radius around your main island. clicking on an island lets you travel to there. as you
> can also upgrade your boat with shells and lumber, which lets you travel in a bigger radius. the bigger the radius,
> the more higher level the islands become."; "make the map actual islands like these. players can then click on any
> island to travel to them" (with a picture of a world map of big irregular islands of their own biomes: a style to
> follow, not a map to copy; the islands are drawn by our own shapes). The slider of the request above is gone: the
> level is now where an island lies.

- **The sea chart** (`Logic/Chart`, the Explore panel): every player has a sea of their own (a seed in the save) of
  `ChartIslands` (40) islands round their home island, the same every time. The first `ChartNear` lie within the first
  boat's range; the rest spread out to `ChartMaxDist` leagues, never closer than `ChartSpacing` to each other. **An
  island's level is its distance:** 1 near home, `ChartLvlPerLeague` (2) more each league further out (level 30 at
  the chart's edge). The panel draws the chart as a map: real islands of their own shapes (a wobbly coast, a smaller
  islet or two beside the bigger ones) in the colours of their kind (a beach's sand and palms, a meadow's grass,
  woods and ponds, a volcano's rock, crater and lava, a snowfield's ice and frozen lake, a reef's coral ring round its
  lagoon), each lit from the top left with its beach, surf and shallows, on a sea of swells; your home island in the
  middle with its plaza; a flag on every island charted. Islands out of the boat's range lie under a fog, the dotted
  ring of the range round them and a fainter ring of the next boat's; each island in range shows its level (green
  up to the captain's level, yellow up to three over it, red above that). **Tap an island** to pick it (outlined in white): the
  side shows its name, kind, level, its driftlings, its reward and whether it is charted; tap Set sail to go. An
  island out of range says "Too far for your boat: upgrade it to sail further."
- **The boat** (levels 1 to 6, `BoatRadius`, `BoatCost`): Upgrade, under the chart, pays shells and wood (500 and 60,
  then 1,800 and 200, 7,000 and 800, 18,000 and 1,800, 40,000 and 4,000) for the next level and a wider range; the
  boat at the pier, the one that sails you out and the one at the islands' shores is the new one (§8).
- **What an island holds** (`Logic/Expedition.chart`, from its level and its own seed):
  - **its kind**, one of those open at the level, picked by its seed: **beaches** from the start, **meadows** from 5,
    **volcanoes** from 10, **snowfields** from 16, **reefs** from 23;
  - **its name**, two words of its kind ("Gull Key", "Willow Thicket", "Scorch Peak", "Frost Drift", "Brine
    Hollow");
  - **its driftlings**: two of its kind's own and one more that strayed in from any kind open at the level, at about
    its level (a level under it at the landing, one more every four stops); its **guardian** is one of its own,
    titled ("Grumpy Clawdle", "Elder Floe"), two levels up with a friend from level 4;
  - **its path**: the landing, six to nine stops (battles, loot, chests, one rest late on; at least three battles),
    the guardian; one more stop from level 10;
  - **what it holds**, growing with the level: a loot stop's food and wood, a chest's shells, the guardian's reward
    (`Isle*`).
  Beating the guardian the first time pays its whole reward and **charts** the island (a flag on the map; the panel
  counts the islands charted; each is charm up to `ChartCharmMax`). An island sailed to again is the same island
  (its kind, driftlings and path), and its guardian pays half.
- **The cutscene** (`UI/Voyage`, skippable with Skip, Space or Return): letterbox bars slide in and the HUD steps
  aside; your founder walks from where they stand down the path, across the boardwalk and along the pier (or starts
  on the jetty when far away) and hops into the expedition boat, where the rest of the party waits on deck and
  cheers; the boat casts off and sails out to sea, the view following it; ink blinds close on the island's name and
  kind. The islet's screen opens behind them and the boat glides in to the island's shore; the party hops off and
  runs to its places. The boat stays away from the pier while the expedition does.
- **Home again** (`UI/Voyage.home`):

  > The request (2026-11-10): "make a transition instead of an instant cut back to the island after an exploration."

  Sail home (or a won or lost expedition's end) closes the ink blinds over the islet on "<name>'s Isle" (or "Home
  again!"); behind them the island comes back, the blinds open on the boat sailing in from the sea with the party on
  deck, the view following it to the pier; your founder hops onto the middle of the pier (well clear of its rails,
  free to walk off: the bug of the request below, a founder put against the pier's wall and stuck there, is fixed),
  the party cheers, the HUD comes back and the loot is shown. Back to island (the expedition waits) closes and opens the blinds the same way, without the
  boat.
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
- **The islet's screen** (3D, full screen): the island's own stage, its kind's set laid out by its seed (an island
  of its own, its shore stepping down into the moving sea: a beach with palms leaning out, a treasure chest, tide
  pools, maybe a rowboat, starfish and shells; a mossy meadow with trees, ferns, mushrooms, a winding stepping-stone
  path and maybe a fallen log; dark volcanic sand by a volcano with lava running down it, a rocky mound, obsidian and
  vents; a snowfield by a snowy peak with pines, ice crystals, maybe a frozen pond; the sea floor's corals, kelp,
  anemones, clams and maybe a sunken anchor), drawn by the pixel filter, with the party on the left (your founder,
  villagers as their chibis, driftlings as their models) and the wild ones dropping in on the right. Along the top:
  the island's name and level, the loot so far, the path of stops (the ones ahead hidden but
  the guardian's crown) and Back to island (the expedition waits; the HUD's card brings you back). Along the bottom:
  the party's cards with their health bars and levels, and the buttons (Sail home between stops; Fight, Guard,
  Treat and Flee in battle; Space or 1-4 on a keyboard). A win shows its xp, shells and level-ups, a new friend its
  portrait with confetti, a guardian's fall the island charted.

> The request (2026-11-10): "after returning home, the player gets stuck at the bay. also, make animations much more
> expressive and detailed, such as attack animations. make character and creature models much more detailed as
> wellmake it such that there is no need to click on "go on", it automatically goes on. also, make an actual day
> night cycle, causing things to go dark and then bright as time goes on"

- **It goes on by itself:** between stops there is no Go on to tap: a bar fills (`AUTO_GO`, 1.8 s) and the party
  walks on to the next stop (Space, or a tap on the bar, goes at once); a won battle's card goes by itself after
  `AUTO_CARD` (3 s, its bar running down). The guardian's fall and a defeat still wait for Sail home; battles still
  wait for your move.
- **Battles move:** a round plays back blow by blow. An attacker winds up (crouching back, squashed, the founder and
  villagers drawing a fist back with a fierce face), dashes right up to its target (stretched, kicking up dust),
  strikes (a lunge and a swing with a shout, a bite or a ram leaning in), and hops back home. The blow freezes the
  action for a few frames, shakes the picture, flashes the one hit and bursts into sparks; the one hit is knocked
  back leaning away (a flinch, a cry, eyes shut), or, when it is down, sent flying with a spin to lie flat (dust and
  stars). Skills have their own moves: a bash leaps high and slams down (a bigger shake, dust and debris), quick
  strikes three times in a blur of afterimages, a zap charges up in sparks where it stands and throws a bolt, a heal
  spins up with green bits and the healed one bounces, Shell Guard has everyone hunker down behind a glint, Rally
  sets them jumping. Guard crouches the party behind crossed arms; a treat is thrown in an arc and the wild one hops
  for joy with hearts, or shakes its head; fleeing turns everyone round to sprint off, or trip over their feet; a win
  has the party jumping and spinning in turn. Every driftling's limbs move with it: wings flap, claws and pincers
  snap open on the strike, tails wag, ears twitch (and droop when hurt), eyes blink and shut when hurt, mouths open to
  bite, cry or cheer.

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
- **Day and night** (the request in §7: "make an actual day night cycle, causing things to go dark and then bright
  as time goes on"): the island's day clock grades the whole picture (`Controllers/DayLight`): a rosy dawn as the day
  begins, plain daylight, a golden dusk (from 0.6 of the day), a violet twilight and a deep blue night (from 0.81)
  that brightens into the next dawn. At night the lamps, torches, the campfire, lanterns and lit windows keep their
  colour and pool warm light round them in three stepped rings on the pixel grid. The change steps (a few steps
  between keys, never a smear). An islet's screen keeps its daylight; with the pixel filter off Roblox's own clock
  follows the day instead.
- **Detail everywhere:** palms that lean, rocks, shells, starfish, driftwood, seaweed and flowering tufts strewn by
  each island's own seed; the boardwalk's planks on beams and posts with rope rails and lanterns; a pier with your
  moored boat. Every building has its doors, windows, ridged roofs with eaves, crates, barrels, sacks and pots, its own
  touches (the patch's scarecrow, the pier's fishing hut and pond, the hut on stilts, the stall's awning, the
  lighthouse's lamp) and, at Lv 3, a lamp and a pennant. Driftlings have shiny eyes, cheeks and a mouth.
- **Boats** (`Models/BoatSpec`: one plan for the boat at the pier, the one that sails you out and home, the one at
  an island's shore and the sailboats crossing the sea), bigger and finer with each boat level: a planked hull with
  seams, a painted band (gold trim from level 4), a rim, a bow, a stern with its rudder and tiller and a planked deck;
  a rowboat's oars at level 1; a cabin with a door, windows and a life ring from 2; a bowsprit and jib from 3; a
  foremast, a crow's nest and a figurehead from 4; a chimney and a stern lantern from 5; a mizzen and blue sails at
  6; striped sails, a flag and pennants, a lantern, fenders, a crate and barrels.

  > The request (2026-11-10): "polish everything even further, such as more detailed boat models, flags rippling in
  > the wind, and swaying leaves."

- **The wind:** leaves sway and flags ripple (the pixel filter, a few times a second like the water: palms, trees,
  bushes and tufts lean a pixel one way, rest and lean back, the sway drifting across the island; flags and pennants
  ripple along their length, a lifted fold a shade darker). The boats' flags flutter as they sail.
- **The camera** follows your founder and always keeps them in the middle of the view between the HUD's strips, at one
  zoom on every tier; Build mode frees it to pan.
- Up to `MaxPlots` (6) islands sit in a row along the boardwalk; an unclaimed lot is open water with a sandbar and a
  sign. Sailboats cross the sea, gulls fly over and cloud shadows drift across. You can walk onto anyone's island
  (the shore's edge holds you back from the sea); Home sends you back to your own. A tap on a sign shows that island's
  day, villagers, driftlings, charm and islands charted.

## 9. Your founder, settings and the tips

The Looks panel sets the founder's skin, hair, style and shirt (every client sees it). Settings: the pixel filter's
quality. **The tips** (the banner over the menu bar), each saying where the stores come from:

> The request (2026-11-10): "the tutorial should also state how to get food, wood and shells. start with enough shells
> to buy all the facilities required."

1 "Food: tap Build, place a Veggie Patch. It grows food; everyone eats it."; 2 "Wood: place a Lumber Camp. It chops
wood for bigger buildings."; 3 "Shells: place a Snack Stall. It sells food to visitors for shells."; 4 "Now a Tent: a
castaway may move in at dawn and work for you."; 5 "Build a Driftling Nest, then tap Explore and set sail to a new
island!"; 6 "Islands give food, wood and shells. Treat a hurt driftling to befriend it." (OK ends them). A new island
starts with `StartShells` (300) shells: the patch, the camp, the stall, the tent and the nest of the tips cost 280.

## 10. Saves and the economy, checked

The save is version 6 (`Logic/Schema`): a version 5 save keeps everything, its tips moved to the new steps, and gets
its sea seed, a level 1 boat and an empty chart; an older save (the game studio's) keeps the founder's look, the
settings and its start date and begins a fresh island with the tips. `tests/Career.luau` plays a sensible player through the same
rules (`Logic/*`) for three seeds and three hours; `tests/specs/Economy.spec.luau` holds the economy to these bounds:

- a villager within 3 minutes, a driftling friend within 15;
- a guardian beaten within 15 minutes; one of a level-5 island (meadows) within 45, level 10 (volcanoes) within 90,
  level 16 (snowfields) within 150; level 23 (reefs) a long-term goal (past two hours). The career's player sails to
  the strongest uncharted island in its boat's range that its party looks strong enough for (asking for more after
  each defeat; a charted one when none is left), and buys the next boat when it can pay and nothing new it can take
  is left in range but the next range holds some;
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
- **The sea lives:** the water rolls and the foam laps the shore (§8; the crests a light blue, as asked in §7), leaves
  sway and flags ripple in the wind, sailboats (the boats of §8, their flags fluttering) rock on the swell as they
  cross both ways, gulls cross now and then, clouds' shadows slide over the islands; each island's campfire flickers and smokes.
- **Coming home:** blinds close over the islet and open on the boat sailing home to the pier, the founder hopping
  off and the party cheering (§7).
- **Battles** play blow by blow (§7): wind-ups, dashes, strikes with hit-stop and shake, knock-backs, knock-outs,
  each skill its own move, the driftlings' limbs alive; the islands' driftlings blink, wag and step too.
- **Night falls** and the lamps light up (§8).
- **The islet's screen:** ink blinds open from the middle on the island's name; after the cutscene the boat brings
  the party ashore (back from the island they drop in from above in puffs of dust), the wild ones drop in; each stage has its ambient life (gulls and a glinting chest on the beach, butterflies
  in the meadow, volcano smoke, falling snow, bubbles and a crab on the sea floor); hits lunge, flash and spark,
  numbers float up, skills shout their names, heals and shells twinkle, a treat bursts into hearts, a friend leaves in
  confetti, a win cheers and throws confetti.
- **Sounds** (`Controllers/Audio`): every event plays a Creator Store library sound (the ones Random Bakery uses), its
  pitch varied a little, repeats inside a short cooldown dropped.

## 12. Out of scope for this version

Trading between players, visiting with gifts, offline progress, purchases (no game passes or products:
`Config/Monetization.luau` holds only the sound ids), music, other languages (English only; every string goes through
`Locale/Lang.t`).
