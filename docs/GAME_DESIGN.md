# Driftling Isle: Game Design

> The request (2026-11-12): "scrap the entire cave, fighting, level, skill and expedition system. instead, players
> start with a tree of life: it creates a creature every few seconds to be put into a pen. the pen will automatically
> send the best creatures into huts if there is space, and the player can also select which creatures are sent to
> which hut. players can upgrade the incubator's luck and speed. creatures work faster based on their rarity and can
> also have mutations like before"

Asked what the huts are, the answer was **"Nests become huts"**: the Nests tab's buildings are the huts, a driftling
in a hut helps at a farm, pier, lumber camp or shop of its knack (faster the rarer it is), one left in the pen does
nothing, and the villagers stay and keep their jobs. Asked about breeding: **"Keep it"**: the Hatchery stays, without
levels, and a hatchling goes into the pen like the tree's. The "incubator" of the request is the Tree of Life itself:
its upgrades are Speed and Luck (§6).

> The request (2026-11-10): "scrap this idea. could you make replicate beasty bay from kariosoft instead? still use the
> test repo as a reference"

We do not copy another studio's game (its name, creatures, islands, story or art). Asked which way to go, the answers
were: **an original game in the same genre** ("Yes, original game"); its loop **"Island building + farming, Creature
taming, Expeditions + battles, Villagers moving in"** (the expeditions and battles went on 2026-11-12, above); its
world **"Shared sea of islands"**. Earlier requests still hold where they apply: the first ("reference game dev story
from kariosoft and make a simplified version of it in gamedevtest. dont touch the "test" repo at all, only use it for
reference"), the pixel art rules (§2) and the polish requests (§11). The game studio of the earlier versions is gone
(§10: an old save starts a fresh island).

Driftling Isle is a small island-village management game for Roblox. You wash up on a little island with a campfire
on its sand and an old tree behind it: the **Tree of Life**, which grows a **driftling** every few seconds into the
pen at its foot. You build food, wood and shops round the campfire, visitors come for the island's charm and move into
the homes you build, and your villagers take jobs. Build huts and the pen sends its best driftlings to live in them;
each helps at a building of its knack, more the rarer it is. Spend shells on the tree's Speed and Luck, sell the
driftlings you don't need, and grow the island for bigger buildings. The islands of everyone on the server sit side
by side along one boardwalk on a shared sea. The look, the build system and the file formats come from our own Random
Bakery (`Downvote/test`): the 2:1 pixel-art isometric diorama seen through the pixel filter, the pixel font, Rojo with
strict Luau, a server that decides everything, pure Data/Logic modules with specs, and the fake-engine simulator and
preview tools.

## 1. The loop in one paragraph

Build a Veggie Patch so the island has food, a Lumber Camp for wood, a Snack Stall to sell food to the visitors for
shells and a Tent so a castaway can move in. Every turn (Tuning.TurnSeconds while you play) the island makes and eats;
a visitor moves into a free bed when the charm is high enough and takes a free job. All the while the Tree of Life
grows a driftling every 12 seconds into its pen (faster with Speed; rarer ones more often with Luck), each born with
its own mutations. Build a Driftling Hut and the pen sends its best driftlings there: each takes a place at a farm,
pier, lumber camp or shop of its knack and adds to what it makes, a legendary seven times what a common one adds. The
pen holds only so many (6 on a first tier island) and the tree waits while it is full, so sell the commons for a few
shells, or move a better one into a hut yourself. Spend shells and wood on more buildings, huts and decor (charm) and
on the tree, and expand the island for bigger buildings. Nothing happens while you are away (no offline progress).

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
- **Interface:** pixel-art plates with stepped corners and a 1 px ink outline following them, the pixel font; the
  panels, cards, notices, the tip and the build tray cast a 2 px drop shadow; buttons are bevelled (a lit top row, a
  shaded lip) and sink a pixel when pressed; each panel has a title band with its icon, and each menu button its
  icon. Every driftling has a 16x16 portrait and the island's things 11x11 icons, drawn by the rules below.

  > The request (2026-11-11): "also, the sprites you made for the creatures dont follow a specific style and look
  > strange at times. reference pokemon sprites, with their angles and detailing" (with a sheet of another studio's
  > monster sprites: their angle and finish are the reference, never their creatures)

  The portraits were a mix of front-on heads, side views and top-down bodies. Now every one follows one template:
  the whole creature in a three-quarter view turned to the left, a big head (about half its height) over a small
  body, its feet on the bottom rows; two eyes, the far one narrower and the near one 2 px wide with a white
  highlight; a shaded cream ramp for muzzles, bellies and jaws, pink blush, the species' body colour with its
  markings in the accent. The same 1 px ink outline and lit-from-the-top-left shading as every sprite.

  > The request (2026-11-10): "also, polish the UI much more"

  > The request (2026-11-10): "make alot more polish to the UI and more in theme with the island theme"

  The island's looks: the plates are dark driftwood (`Palette.ui`: warm browns, sand-coloured quiet text, buttons
  painted lagoon blue, palm green, mango and coral; disabled ones driftwood grey), and everything that stands on its
  own sits in a frame of planks: lit along its top and left, shaded along its bottom and right, seams between the
  planks and a nail head in each corner. A panel has a thick frame and its title on a carved plank across the top (a
  coral Close), over the island seen through a sea-dark veil; the island card and the tree's card the same, their
  names on planks; the chips, the notices and the tip (a parchment note) thin frames; the chips and the rows in the
  panels are carved boards (a lit top row, a shaded bottom one); the menu bar stands on a wooden dock; the build tray is
  a workbench with its tabs on a plank. The loading card is the island at dusk (§11).
- **The founder:** you walk your island and the boardwalk as a chibi founder (§9).

**The pixel art rules** (they hold for every sprite, icon, scene and effect, now and from now on):

> The request (2026-11-09): "for pixel art, always dont use mixels. use pixel art techniques such as anti-aliasing,
> avoiding jaggies, and avoiding mixels, and use a 1 pixel outline. respect the pixel art grid. polish the minigames
> much much more"

- **No mixels.** One art pixel is one UI px is one K-sized block on the screen: nothing is ever drawn scaled up
  (no 2x or 3x sprites). A bigger or smaller thing is its own sprite drawn at its own size: a driftling's portrait is
  16x16, a small icon 11x11. The world and the driftlings are 3D and drawn by the pixel filter, so they keep the same
  grid, palette and outline.
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

## 3. The island's turns and the sea's days (`Logic/Island`, `WorldClock`)

> The requests (2026-11-10): "days go by too fast, it should take a few hours at least for a day to pass. also,
> lighting seems to not follow along with the camera as the camera moves"

- **A turn** is `TurnSeconds` (40 s) while you are on the server: the island's pace. Each building that makes
  something makes its rate a turn (the island card shows it a minute: "+57/min"): full with a villager working there,
  half with nobody (`IdleOutput`), more with a driftling of its knack helping (`PalBoost`), more again at Lv 2 and 3
  (`UpgradeMult`: only a building upgraded in an older save is above Lv 1, since upgrades were taken out, §4).
  Villagers eat `EatFolk` food a turn, driftlings in huts `EatPal` (less or more with their eating share; the pen's eat
  nothing). At each turn's end a visitor may move in.
- **A day** is `DaySeconds` (4 hours) of the sea's clock (`WorldClock`: one time of day for every island on the
  server, carried on across visits: it follows the real clock): the HUD shows the day count and its clock (a sun, a
  moon for the evening); day and night follow it (§8); each day's end while you play counts a day (a banner).
- **Shops** sell food to the visitors: their rate times visitors / `ShopVisitors` (at most double), eating food the
  same way. **Visitors** a turn: 1 + charm / `VisitorCharm`, at most `VisitorsMax`.
- **Charm:** every piece's charm, and one for each driftling living in a hut plus its charm share (Cute and its
  family; `Island.charm`).
- **Hunger:** when the food runs out everything makes half and the shops shut until there is food again; the food
  chip blinks red.
- The stores reach the client every second; a newcomer brings a banner (who moved in), a
  new day its own banner ("Day 12").

## 4. Building (`Data/Buildings`, `Logic/Plot`, Build mode)

73 pieces in ten kinds (the Tree of Life one of them), opening as the island grows (tier 1 .. 6, the build tray's "Island Lv"):

| Kind | Pieces (the tier they open at) |
|---|---|
| **food** | Veggie Patch, Fishing Pier (1), Fruit Orchard (2), Greenhouse (3), Rice Terrace (4), Kelp Farm (5), Sky Garden (6) |
| **wood** | Lumber Camp (1), Sawmill (2), Timber Works (3), Bamboo Grove (4), Grand Mill (5) |
| **shops** | Snack Stall (1), Beach Cafe (2), Seaside Inn (3), Bakery (4), Grand Bazaar (5), Grand Hotel (6) |
| **homes** (beds, comfort) | Tent 1, Grass Shack 2 +3% (1), Cottage 4 +6% (2), Longhouse 5 +8% (3), Townhouse 6 +12% (4), Villa 6 +18% (5), Manor 10 +25% (6) |
| **huts** (room, comfort: §6) | Driftling Hut 2, Cozy Burrow 4 +5% (2), Driftling Den 5 +8% (3), Treetop Roost 6 +12% (4), Spring Grotto 8 +18% (5), Driftling Palace 12 +25% (6) |
| **boosts** | Tool Shed (wood +10%), Windmill (farms +10%), Smokehouse (fishing +10%) (2), Market Hall (shops +12%) (3), Water Tower (all +6%) (4), Town Hall (all +10%) (5), Sun Beacon (all +15%) (6) |
| **paths** (2 x 2 tiles) | Dirt Path (1), Stone Path (2), Brick Road (4), Marble Walk (5) |
| the **Hatchery** (3, §6.1); the **Tree of Life** (every island's own, never in the tray: §6) | |
| **decor** (charm) | Flower Bed, Round Bush, Picket Fence, Tiki Torch, Sandcastle, Rock Garden, Shell Pile, Palm Tree, Bench, Hammock (1); Hedge, Lamp Post, Picnic Table, Flower Arch, Totem Pole, Fountain (2); Gazebo, Lighthouse, Guardian Statue (3); Street Lamp, Topiary, Bandstand, Clock Tower (4); Canal Bridge, Grand Arch, Observatory (5); Crystal Fountain, Sun Spire, Founder Monument (6) |

Each is paid in shells and wood when placed, on whole studs of the island's grass (a stud or more in from the sand),
turned a quarter at a time, off the campfire's plaza and the path to the jetty, and off every other piece, up to the
island's piece limit (`PlotPieces`: 24, 40, 60, 85, 115, 150; path tiles apart, `PathPieces`: 60 .. 500).

> The request (2026-11-11): "paths should be able to be drawn or made in a box like the original interface in the
> bakery game. also, fights should be shown in the same view as pokemon or beasty bay, in an angle like the image
> shown, and the party will also walk forward in the view like the image shown. polish the battle experience and
> interface much much more"

Paths are drawn, the way the bakery's floors were. Picking a path on the Paths tab opens the draw bar instead of the
usual placing: **Line** (drag and the tiles follow the finger, filling the gaps between cells), **Box** (drag a box
and every free cell inside it is filled), **Erase** (drag over tiles to lift them, with the usual refund) and **Look
around** (drag the view without drawing), and Cancel and Done. While dragging, each 2 x 2 cell shows as a glowing
plate: blue where a tile goes down, orange where one comes up, red where it can't (off the grass, on a piece, past
the limit); the bar says how many and what they cost. Letting go lays them in one go (`plot.paint`, up to
`PAINT_MAX` (40) cells a request: a long stroke goes in a few) or lifts them (`plot.unpaint`). Cells that can't take a
tile are skipped, never refused as a whole; running out of shells or wood stops where it runs out.

### 4.1 The town and the city

> The request (2026-11-10): "make much much more progression, allowing the player to build much more decorations,
> generators/work areas, better houses for villagers and creatures which improve their stats and work productivity,
> paths and other details, that unlock more as the island is expanded. increase the progression to the point where a
> big island that is well decorated should look like a well developed city. give players the ability to
> replace/upgrade buildings as well, including homes of creatures and villagers"

- **Six tiers** (`TierCost`): Castaway Cay, Palm Isle, Grand Isle, then **Harbor Town** (60,000 shells and 5,500
  wood), **Coral City** (180,000 / 15,000) and **Sunspire Capital** (480,000 / 40,000). The island grows north each
  time (the boardwalk stays where it is), to twice tier 3's grass at the capital, and only ever gains land (each
  tier's shape joined to the smaller ones': nothing built near an old shore has to move); more villagers (`FolkMax` 40) live there, and
  more driftlings in bigger huts.
- **Comfort** (homes and huts): the best homes are filled first, each villager in the order they came (the pen sends
  its best driftlings to the comfiest huts first). A resident's comfort (its home's, plus 4% / 8% at a level 2 / 3 home kept from an older
  save) makes them work
  that much more (`Island.rates`: a worker's output times 1 + its comfort; a helper's boost grows by it too). The Villagers panel shows each one's home and comfort ("Home:
  Villa, comfort +18%"), the Driftlings panel its hut.
- **Boost buildings**: every building of a knack makes more (`Island.boosts`); each kind of boost building counts
  once however many stand, the "all" ones count at every knack, and the boosts at one knack stop at `BoostMax` (60%).
- **Paths** in four materials, laid tile after tile (the piece stays picked), apart from the piece limit: roads
  through a town (a Brick Road brings a little charm, a Marble Walk more).
- **No upgrades** (taken out 2026-11-11: "remove the ability to upgrade buildings"). A better building is a
  **Replace** away, and a level from an older save is kept and still counts.
- **Replace**: a standing piece picked up shows **Replace**: the tray lists the others of its kind open at the tier
  (beds or room for homes and huts), each for its price less half the old one's (`Plot.replaceCost`); a tap swaps it
  where it stands (the new footprint must fit there; a home or hut must still house everyone): its workers stay, its
  level starts again. A tent becomes a cottage, a patch an orchard, a hut a palace.
- A big island well built reads as a city: roads in a grid with street lamps, townhouses and villas, a town hall and a
  clock tower, markets and a grand hotel, parks with hedges, topiaries and fountains (the `city` preview).

- **Build mode** (the HUD's Build): the view frees to pan over the island; a tray of tabs (Food, Wood, Shops, Homes,
  Huts, Boosts, Paths, Decor: icons alone on a phone) lists every piece with its price (red when you are short, locked ones greyed with the tier they
  need). A picked piece is a ghost on a cyan footprint where it fits, red where not; Place (or a second click on the
  same spot) builds it. Tapping a standing piece picks it up to move, **Replace** it (§4.1) or **Clear it away** (half its price back; not a home whose beds are
  needed, not a Hatchery warming an egg, never the Tree of Life; a hut's driftlings go back to the pen). The header counts the pieces (the path tiles on the Paths tab).
- **The tips in Build mode:** the tip's banner stays up, over the tray; opening Build mode (or a tip moving on while it
  is open) turns the tray to the tab of the building the tip asks for, and that building's card (and its tab, while
  another tab is shown) pulses until it stands on the island; placing it goes straight on to the next tip's tab.

  > The request (2026-11-10): "make the tutorial show while in the build menu as well, and auto switches the player to
  > the tab where the required buildings are in"
- **Expand** (in the tray's header): the island grows five times (`TierCost`, §4.1), its coast reaching further out
  round the same campfire. A piece that no longer fits moves to the nearest free spot (none is
  lost; one with no spot left would be cleared with its whole price back).

  > The request (2026-11-11): "also, expanding the island causes the game to lag abit before the actual expansion"

  The pause came from three places. The server built the whole bigger island (about 1,200 parts at the top sizes)
  in the frame of the tap. The pixel filter then waited half a second and re-baked the picture, and the screen
  stood still the whole time it baked. And the fanfare played at the tap, before anything had changed. Now the
  server builds each island's next size in the background, a few dozen parts a frame, and Expand only swaps it in.
  The filter re-bakes sooner, with more time a frame, behind the old picture, and the island keeps moving
  meanwhile (villagers, the founder, water and wind). The fanfare and "Your island grew." wait until the bigger
  island is on screen. Every size's coast cells are worked out when the server starts, and the next size's on
  the client a few seconds after each change, so the tap never waits for them either.

## 5. Villagers (`Logic/Island`, the Villagers panel)

A visitor moves in at a turn's end when there is a free bed (`FolkMax` at most) and the charm is at least `MoveInCharm` times
the villagers already living there. A newcomer takes a free job straight away (food first, then wood, then shops).
The Villagers panel lists each one (portrait, job) with **Job** (a picker of the buildings that take workers: Go,
Swap with whoever is there, or Rest) and **Dismiss** (two taps: they sail off, freeing the bed). Villagers no longer
fight or level up (2026-11-12): they work.

## 6. Driftlings and the Tree of Life (`Logic/Tree`, `Data/Creatures`, `Data/Traits`, the Tree panel, the Driftlings panel, the Index)

The request at the top of this file replaced the wild places, the battles, the levels and the skills with the tree.

**The Tree of Life** (`Logic/Tree`; its own piece in `Data/Buildings`: 6 x 4 studs, charm 4, never in the build
tray). A new island has it behind the campfire (`Tree.SPOT`, the nearest free spot); Build mode can move it but not
store it or clear it away (`fixed`). A broad old tree: roots over a patch of lawn, a thick trunk with bark ridges and a
glowing hollow, three branches, a two-layer crown with blossoms and five gold fruit, mushrooms and flowers at its foot,
and beside it a fenced pen with a gate, hay, a trough and a water bowl (`DecorModels.PEN`).

- **It grows** a driftling every `TreeSecs[Speed]` seconds (12 at Speed 1 down to 4 at Speed 10), faster with the
  huts' Leafy driftlings (`HutTree`: 50% at most), while you are on the server. The newcomer pops out of the hollow
  with a cheer and walks into the pen. A card under the HUD's chips shows the tree's bar filling and "Pen 3/6" (or
  "Pen full", the card pulsing); a tap opens the Tree panel, as does a tap on the tree itself.
- **What grows** (`Tree.roll`): a rarity first, each rarity step's weight (`Traits.RARITY`: 100, 45, 16, 5, 1.2)
  times the tree's luck to the power of the steps; luck is 1 at Luck 1, +0.12 a level (`TreeLuck`) and + the huts'
  Lucky driftlings (`HutLuck`: 0.5 at most). Then one of that rarity's kinds among those open at the island's tier
  (`Data/Islets` tier: beaches and meadows from the start, snowfields and mangroves at 2, volcanoes and grottoes at 3,
  reefs at 4, bluffs at 5, ruins at 6); a rarity none of them has falls to the next commoner one. It is born with
  mutations (below), rolled as one rarity rarer every `TreeMutLuck` (3) Luck levels past the first. A rare or better
  one gets a notice in its rarity's colour ("A rare Floe grew on the tree."), an epic or a legend a burst of sparkles.
- **The pen** holds `PenRoom` driftlings by the island's tier (6, 8, 10, 12, 14, 16). While it is full the tree
  waits with its bar full. Driftlings in the pen eat nothing and do nothing.
- **The huts** (the Huts tab in Build mode; the old nests: Driftling Hut 2 places, Cozy Burrow 4, Driftling Den 5,
  Treetop Roost 6, Spring Grotto 8, Driftling Palace 12; the home once called Grass Hut is now the Grass Shack so the
  names don't clash). Whenever a hut has room the pen sends its best driftling there (`Tree.settle`: the one worth most
  at work, its rarity's `RarityWork` times 1 plus its share at its knack), the comfiest hut first. It takes a free
  place at a building of its knack (`HelpMax`: 2 helpers a building) and helps there; with none free it rests in its
  hut. A driftling in a hut eats `EatPal` food a turn and adds its charm.
- **Your pick:** the Driftlings panel lists every driftling with **Move** (a picker: each hut with its room, and the
  pen; a full hut offers to swap with one of its driftlings), **Help** (which building of its knack, or rest) and
  **Sell**. One you put in the pen stays there (`held`) until you move it. The Tree panel lists the pen with **To a
  hut** and **Sell** for each, and **Sell commons**.
- **Selling** (`Tree.sell`, `Tree.sellPen`) pays `SellPrice` shells by rarity (2, 7, 25, 85, 320), times 1 + 0.25 a
  mutation tier (`SellTier`), times 1 + its sell share (Shiny and its family). It is a help, not the island's living:
  the career (§10) earns well under two thirds of its shells this way.
- **The upgrades** (the Tree panel: two rows with the level, what the next one does and its price; the odds of each
  rarity at the tree's luck below them): **Speed** and **Luck**, ten levels each, paid in shells and wood (Speed 2
  costs 120 shells and 10 wood, Speed 10 150,000 and 12,000; Luck 2 160 and 15, Luck 10 170,000 and 14,000).

**How much a driftling helps:** a helper adds `PalBoost` (0.5) times `RarityWork` by rarity (1, 1.6, 2.5, 4, 7: the
request's "creatures work faster based on their rarity") times 1 plus its work share at that building (its passive and
mutations, `Island.palWork`) and its hut's comfort, so a legendary woodsy driftling at a lumber camp is worth
many commons there.

> The requests (2026-11-10): "make each creature have a different passive ability. some can have different mutations
> which allow them to do different things better, such as better health, attack speed, etc. mutations also have
> tiers, so a rarer mutation gives better benefits. mimic the system in palworld. some creatures also have passives
> that make them better workers in logging, shells, etc. and mutations also helping in that."; "make much more
> creatures, some rarer than others, and more islands as well". The system is the genre's (a passive of each kind,
> rolled traits in tiers, workers better at some jobs); every name, number and creature is our own. With the fights
> gone (2026-11-12) the fighting effects became island ones (below).

> The requests (2026-11-11): "alot of the creatures are just simple shapes meshed together. can they be more
> detailed and look more like the animals /creatures that they are referencing?" (with a picture of a green turtle
> that read as a blob); "you should also add more expressive idle and other animations to the creatures, the whole
> mesh seems to move as one throughout all their animations. you can make different moving parts for creatures to
> allow for more expressiveness"

**Their bodies** (`Models/DriftModels`): each of the twenty body plans is built to read as its animal. The turtle has
a domed shell with a ring of plates and a rim, a head on a neck with a beak, and flippered legs. The fox pup has a
snout and nose, tall ears with dark tips, a fluffy chest and a bushy tail with a white tip. The crab has eyes on
stalks, big claws with a hinged pincer and three legs a side. The gull has a beak in two halves, wings with a white
bar and webbed feet. The rest follow the same way: the rabbit's long ears and big feet, the gecko's crest and banded
tail, the owl's facial discs and ear tufts, the mole's star nose and digging claws, the bat's two-part wings with
finger bones, the yeti's face and horns, the seal's flippers and flukes, the snail's spiral shell and eye stalks, the
frog's bulging eyes and wide jaw, the moth's feathery antennae and spotted wings, the golem's gem core and slit eyes,
the drake's horns, two-part wings and spaded tail, and the sea serpent's coils and toothed jaw.

**Their moving parts:** every driftling stands on a small skeleton (body, head, jaw, ears, arms, legs, wings, fins,
tail segments, eye stalks, pincers, tendrils, antennae), and each joint moves on its own. Idle, a driftling breathes,
looks about now and then, yawns, twitches its ears, sways its tail and blinks. Walking, its legs step in pairs (a
rabbit or frog hops on both hind legs, a crab scuttles, a seal or snail sways, a bat or moth flaps). Cheering, it
looks up with its arms up and wags fast. At work it has its own moves (§11).

Fifty-five driftlings of our own, five to seven to each of the nine kinds of island (`Data/Islets`: the tree grows a
kind's driftlings once the island reaches that kind's tier, above):

| Kind | Its driftlings (common .. legendary) |
|---|---|
| Beaches | Pebblit, Clawdle, Gullfin, Conchy, Shellback, Sunsprite |
| Meadows | Mossbun, Frondle, Twiggle, Hopsprout, Bloomoth, Elderbark |
| Mangroves | Murkle, Reedle, Bogsnail, Mudmole, Wispwing, Mirewyrm |
| Volcanoes | Emberpup, Magmole, Scorchwing, Cindertoad, Basaltor, Pyredrake, Pyrelord |
| Grottoes | Gemsnail, Glowbat, Quartzle, Crystowl, Prismoth |
| Snowfields | Snowpuff, Floe, Frostling, Icetoad, Glacior, Frostdrake, Frostcrown |
| Bluffs | Cloudbun, Breezle, Skyfox, Stormowl, Thunderdrake, Aurorawing |
| Reefs | Coralcrab, Lumajelly, Pearlback, Novafox, Tidewyrm, Abyssmaw |
| Ruins | Relicrab, Rubblet, Glyphowl, Sentinel, Runemoth, Solwyrm |

Each has a **knack** (farms, fishing piers, lumber camps or shops: where it helps), a 3D model built from parts
(twenty body plans: blob, crab, bird, bun, lizard, owl, pup, mole, jelly, fox, wyrm, seal, bat, sprite, yeti, snail,
turtle, frog, moth, golem and drake) and a 16x16 portrait. Its old fighting numbers stay only to rank the kinds for
the Hatchery (`Creatures.power`: weighted, +12% a rarity step).

- **Rarity** (`Traits.RARITY`): Common, Uncommon, Rare, Epic, Legendary (name colours: grey, green, blue, purple,
  gold), the tree's odds and the work it does above.
- **A passive of its own** (`passive`: a name and its effects, every kind's different): shares at work (anywhere, or
  at farms, fishing, lumber or shops), eating less, selling for more, charm, a faster tree or a luckier one ("Snappy
  Pincers: +15% at fishing, +30% sell price", "Diving Beak: +25% at fishing, +4% tree speed"). The tree
  and luck shares count only from a driftling in a hut.
- **Mutations** (`Data/Traits`, `Pal.muts`): a driftling is born with up to three (about one in three none), kept for
  life. Ten families of four tiers, each tier rarer and stronger (the fighting families were turned into island ones
  on 2026-11-12, keeping their ids so old saves read them): Light Eater / Frugal / Lean / Sunfed (eats 15 / 30 / 50 /
  80% less), Shiny / Glossy / Golden / Radiant (sells for 30 / 70 / 150 / 300% more), Cute / Sweet / Adorable /
  Beloved (+1 / 2 / 3 / 5 charm), Leafy / Blooming / Lush / Evergreen (the tree grows 4 / 8 / 14 / 22% faster), Lucky
  / Blessed / Fortunate / Starborn (+5 / 10 / 18 / 30% tree luck), Busy .. Workaholic (+8 .. 40% work anywhere), and
  Green Thumb .. Bountiful, Angler .. Sea Sage, Chopper .. Forest Heart, Chatty .. Tycoon (+12 .. 65% at farms,
  fishing, lumber, shops). Tier weights 46 / 25 / 10 / 3 (and 16 for a **flaw**: Greedy eats 25% more, Dull sells
  for 20% less, Grumpy takes a charm, Sluggish and Lazy work 8 and 15% less; never beside its own family's strength);
  a rarer driftling rolls fewer flaws and more of the top tiers. Four at most (a Hatchery child can gain one, §6.1).
  Their names show in tier colours (with stars) on the Driftlings panel.

The **Index** lists all fifty-five: a dark shape and its rarity until one has grown on your tree (or hatched), then
its name, passive and knack.

### 6.1 The Hatchery (`Logic/Breed`, the Hatchery panel)

> The request (2026-11-10): "make a breeding system that also works like in palworld that unlocks after a certain
> island level". The genre's system (two parents, a feast, an egg, the child's kind from the parents' strength, their
> traits passed on) in our own buildings, numbers and words.

- **The Hatchery** (Huts tab, island tier 3: a warm nursery with a nest of speckled eggs and a heat lamp): one egg at a
  time each; several may stand. The Driftlings panel's **Hatchery** button opens its panel.
- **Laying an egg**: tap each slot, pick a parent from your driftlings (not the other one); the
  panel shows what they would likely hatch (its portrait once met, else a dark shape and ???) with its rarity, and the
  feast and the turns it takes; **Breed** pays the feast (`BreedFood` 40 / 70 / 120 / 200 / 400 food by the child's
  rarity) and lays the egg (`BreedTurns` 3 / 4 / 6 / 9 / 14 island turns). The parents carry on as before.
- **What hatches** (`Breed.child`): a pair of one kind hatches its kind; any other pair the kind whose power is nearest
  their average (so two strong ones can make a kind the player never met); a legend only from two legends.
- **What it inherits** (`Breed.inherit`): a mutation both parents carry always passes on, the better tier, and with
  `BreedTierUp` (30%) a tier better still (a shared flaw becomes its family's first tier); one only a parent carries
  passes on half the time (`BreedKeep`); with `BreedNew` (15%) it gains one of its own (tier 1 or 2); the best four.
  Breeding two that share a mutation, again and again, climbs it to the top tier.
- **Hatching**: at each turn's end the eggs count down; a ready one hatches into the pen (from where the pen sends it
  on to a hut like the tree's; in the Index; "Floe hatched!" in the turn's banner), else waits while the pen is full
  ("Ready to hatch. It needs room in the pen.").
  The panel shows each egg: its rarity's egg, "Hatches in 3 turns" over a bar, its parents. A Hatchery holding an egg
  is not cleared away ("An egg is still warming in that Hatchery."). On the island the hatchling cheers where it
  appears, its name floating up in pink.

## 7. Expeditions and battles (gone)

The request at the top of this file (2026-11-12) took them out: the wild places on the island (the Tide Pool, the
caves and the rest) and the walk in, the paths of stops, the timed battles, snacks and befriending, the guardians, the
captain, the snack pouch, every level and its xp, the skills and skill points, and the Training Yard. Taken out of
the code with them: `Data/Sites`, `Data/Skills`, `Logic/Sites`, `Logic/Expedition`, `Logic/Battle`, `UI/ExpeditionUI`,
`UI/MicroStage`, `UI/Voyage`, their actions and their sounds. Driftlings come from the Tree of Life now (§6).

What stayed: the nine kinds of island (`Data/Islets`) name the driftlings' families and open with the island's tier;
the driftlings' models, moving parts and work moods; the day and night on the islands (§8). This section's earlier
text (the requests and how each was met) is in the history of this file, up to commit f667462.

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
  pier's pond and the fountain move the same way.
- **Day and night** (the request of 2026-11-10: "make an actual day night cycle, causing things to go dark and then bright
  as time goes on"): the island's day clock grades the whole picture (`Controllers/DayLight`): a rosy dawn as the day
  begins, plain daylight, a golden dusk (from 0.6 of the day), a violet twilight and a deep blue night (from 0.81)
  that brightens into the next dawn. At night the lamps, torches, the campfire, lanterns and lit windows keep their
  colour and pool warm light round them in three stepped rings on the pixel grid (the pools move with the picture as
  the view follows you), only as strong as the dark is deep (no orange rings in the late afternoon), never all the
  way back to the day. As it gets dark pale things lose more of their light than dark ones (their brightness over a
  knee is pressed down), so white and pink shells, the sand and the sails stay in the night instead of glowing blue.
  The change steps (a few steps between keys, never a smear). With the pixel filter off
  Roblox's own clock follows the day instead.

  > The bug report (2026-11-10): "lighting also seems buggy, especially with shells"
- **Detail everywhere:** palms that lean, rocks, shells, starfish, driftwood, seaweed and flowering tufts strewn by
  each island's own seed; the boardwalk's planks on beams and posts with rope rails and lanterns; a pier with your
  moored boat. Every building has its doors, windows, ridged roofs with eaves, crates, barrels, sacks and pots, its own
  touches (the patch's scarecrow, the pier's fishing hut and pond, the hut on stilts, the stall's awning, the
  lighthouse's lamp) and, at Lv 3, a lamp and a pennant. Driftlings have shiny eyes, cheeks and a mouth.
- **Boats** (`Models/BoatSpec`: one plan for the boat at the pier and the sailboats crossing the sea), bigger and finer with each boat level: a planked hull with
  seams, a painted band (gold trim from level 4), a rim, a bow (tall against the hull, flush with the rim, its keel
  sloping up to the stem's point), a stern with its rudder and tiller and a planked deck;
  a rowboat's oars at level 1; a cabin with a door, windows and a life ring from 2; a bowsprit and jib from 3; a
  foremast, a crow's nest and a figurehead from 4; a chimney and a stern lantern from 5; a mizzen and blue sails at
  6; striped sails, a flag and pennants, a lantern, fenders, a crate and barrels.
  With the sea chart and the expeditions gone (§7) the boat at the pier is scenery: the first boat, moored
  there for good; the sailboats crossing the sea still come in every size.

  > The request (2026-11-10): "polish everything even further, such as more detailed boat models, flags rippling in
  > the wind, and swaying leaves."; the bug report: "it seems like the boats are buggy, the triangle part here is
  > supposed to be reversed" (the bow's wedge stood tall at its tip: turned over)

- **The wind:** leaves sway and flags ripple (the pixel filter, a few times a second like the water: palms, trees,
  bushes and tufts lean a pixel one way, rest and lean back, the sway drifting across the island; flags and pennants
  ripple along their length, a lifted fold a shade darker). The boats' flags flutter as they sail.
- **The camera** follows your founder and always keeps them in the middle of the view between the HUD's strips, at one
  zoom on every tier; Build mode frees it to pan.
- Up to `MaxPlots` (6) islands sit in a row along the boardwalk; an unclaimed lot is open water with a sandbar and a
  sign. Sailboats cross the sea, gulls fly over and cloud shadows drift across. You can walk onto anyone's island
  (the shore's edge holds you back from the sea); Home sends you back to your own. A tap on a sign shows that island's
  day, villagers, driftlings and charm.

## 9. Your founder, settings and the tips

The Looks panel sets the founder's skin, hair, style and shirt (every client sees it). The founder walks and jumps
(`JumpHeight`) on the islands; jumping is held in Build mode (the phone's jump button hides with it).

> The request (2026-11-10): "allow the player to jump in their own island as well"; the bug report: "jumping seems
> bugged. also, the player can walk on water" (the chibi stood still on the ground while the character jumped: it now
> rises with it, knees up, and lands in a puff; the coast's invisible walls stood a little under a jump, so a jump
> cleared them onto the sea: they now stand far higher)

Settings: the pixel filter's quality, and the music (the note in the HUD's top right corner, on or off, kept with the
profile). **The tips** (the banner over the menu bar, or over the build tray in Build mode: §4), each saying where
the stores come from:

> The request (2026-11-10): "the tutorial should also state how to get food, wood and shells. start with enough shells
> to buy all the facilities required."

1 "Everyone here eats. Tap Build and place a Veggie Patch to grow food."; 2 "Bigger buildings need wood. Place a
Lumber Camp."; 3 "Shells come from visitors. Place a Snack Stall and they'll buy food."; 4 "Now put up a Tent. A
castaway moves in straight away to work." (the first home on an island nobody lives on yet: a castaway moves in the
moment it is built, not at a turn's end); 5 "The Tree of Life grows a driftling every few seconds. Build a Driftling
Hut so they can work." (in Build mode: "Place a Driftling Hut. The pen sends its best driftlings there."); 6 "Tap the
Tree of Life and buy a level of Speed or Luck." (a label and an arrow bob over the tree); 7 "The pen sends its best
driftlings to huts with room. Sell the ones you don't need." (OK ends the tips). A new island starts with
`StartShells` (300) shells: the patch, the camp, the stall, the tent and the hut of the tips cost 280. (The tips that
taught fighting and befriending went with them, 2026-11-12: an old save past them starts at tip 5.)

> The request (2026-11-11): "also, please rewrite all text and dialogue to be less ai-like. research what are the
> telltale signs of ai writing and avoid them. note this from further on as well"

> The request (2026-11-11): "make a questline such that players are guided throughout the features of the game, such
> as assigning creatures to different work areas"

**The questline** (`Data/Quests`, `Logic/Quest`): once the tips are over, one quest at a time in a card down the left
under the chips (it steps aside for a panel). The card has the quest's icon and title, which of the twenty it is, what
to do and where, and its progress with **Go**, which opens the place it needs (the Driftlings or Villagers panel, the
Tree panel, Build mode on the right tab, the Index, the Hatchery). When the goal is met, Go turns into **Claim**
(shining) next to the reward; Claim pays it, says so, and the next quest slides in. Each goal counts what the island
has now, so one already met can be claimed at once. Rewritten for the tree (2026-11-12), in order: put a driftling to
work; sell a driftling; speed up the tree (Speed 2); make room for a newcomer (2 villagers); give everyone a job (2 at
work); build another hut (2 huts); make the tree luckier (Luck 2); grow more food (a second farm or pier); lay a path
(8 tiles); decorate (2 pieces); grow a rare one; grow your island (tier 2); build a boost; ten driftlings at work; meet
twelve kinds; grow the island again (tier 3); build a Hatchery; hatch an egg; grow an epic one; a lucky tree (Luck 5).
The rewards are small (40 to 3,000 shells, some food and wood) next to what each step costs; the career's player (§10)
doesn't claim them, so the economy's bounds are measured without them. An old save starts the new questline at its
first quest.

**How the game talks** (every tip, notice, card and blurb; CLAUDE.md "Writing" keeps it as a standing rule). The
researched tells of machine-written text, and what replaced them here: an exclamation mark on nearly every line
(now only where something earns it, like an egg hatching); colons and semicolons gluing two thoughts into one line
("Food: tap Build...", "It grows food; everyone eats it") now plain sentences ("Everyone here eats. Tap Build and
place a Veggie Patch to grow food."); stock game phrases ("springs into action", "blocks the way", "appears!") now
said plainly ("Everyone goes at once.", "is in the way.", "That's a legendary Pyrelord."); tidy quips built on a
pattern, a mirrored pair or a list of three ("Snaps first, makes friends later.", "Half gull, half fish, all
appetite.") now one plain observation ("Pinches anyone who gets close. It means well.", "Part gull, part fish.
Always hungry."); empty praise ("Every driftling's dream.", "Visitors love it.") now what the thing is or does; a
tip that ended on a moral ("sail often") now just stops. None of the stock AI words were in the game's text (the
Sun Beacon is a name). Stat lines keep their "label: value" form.

## 10. Saves and the economy, checked

The save is version 10 (`Logic/Schema`). A version 9 save loses its wild places, the captain, the snack pouch and
every level and skill; a Training Yard comes down with its whole price back (450 shells, 50 wood); the Tree of Life is
planted (the free spot nearest the one behind the campfire; on an island built full the pieces nearest it make room,
paths first, then decor, then anything that houses nobody, each with its whole price back), each driftling moves into a hut the way the nests were filled before (the comfiest first, in the
order they came) and the rest go into the pen; its tips on the old sailing steps go to the hut's step; the questline
starts again at its first quest. Its driftlings and their mutations, its villagers, buildings, paths and stores are kept
(a cleared wild place goes with the rest). A version 8 save also drops its boat and its sea chart; a version 7 save also starts the
questline; a version 6 save's driftlings each roll their mutations once (from their kind and id: the same every load);
a version 5 save's tips move to the new steps; an older save (the game studio's) keeps the founder's look, the settings
and its start date and begins a fresh island with the tips.

`tests/Career.luau` plays a sensible player through the same rules (`Logic/*`) for three seeds and three hours: it
builds what the island lacks, a hut while fewer driftlings are housed than the buildings can take, buys the tree's
cheaper upgrade when it can, sells the pen's commons when it fills and grows the island when it can.
`tests/specs/Economy.spec.luau` holds the economy to these bounds:

- a villager and a driftling at work within 3 minutes (about 40 and 30 seconds), a rare one within 20;
- the tree's Speed and Luck both at 3 or more by 40 minutes;
- selling helps but the island earns: under two thirds of the shells over three hours come from selling (about 55%);
- the island's second tier within 45 minutes (about 27 to 33), the third within 90 (about 71 to 80); at an hour, at
  least 8 villagers and 8 driftlings in huts; Harbor Town (tier 4) never before 100 minutes and no city (tier 5)
  within three hours;
- nobody starves for long, and the stores stay finite.

## 11. Polish and animation

> The request (2026-11-12, later): "detail the island on the loading screen more, it should be uneven like the actual
> island. the reflection of the sun on the water should be polished more, same with the dithered gradient of the
> background, dither it better"

- **The loading card's island** has the real island's coast: the oval pushed in and out by the same four sines as a
  first tier island (Data/Street), seen from the world camera's height. Inland of the shore: wet sand, a beach that is
  wider in front (lit along its back edge, a small dark step down to the wet sand in front, grains and a few shells),
  then grass in darker and lighter patches with tufts and flowers, its front edge a darker lip. Out from the shore: a
  broken line of foam, the shallows lighter near the shore with a broken line of surf further out, dithered into the
  sea. Rocks with an ink outline sit at the waterline, driftwood lies on the beach, and a dirt path runs from the
  campfire down to the jetty. The sprites on it were moved where the new coast came too close.
- **The sun's path:** the sea round it is lifted into warm tones, wide along the horizon and closing to the path's
  width toward us. On that glow lie lines of light, close together near the horizon and further apart nearer the
  island, narrowing, broken where the swell dips, pale gold at the top, then gold, then coral, each line's ends a tone
  down. Small waves and wave crests stay out of the glow, and glints only land on the lines. On a phone the path is
  never shorter than 14 rows.
- **The dither:** every gradient (sky, sea, the sun's glow, the sun's halo, the shallows' edge) goes from one tone to
  the next in three even steps of clean patterns: single dots (a quarter), a checkerboard (a half), the dots' gaps
  (three quarters). Each band is flat for its first part. The old 4 x 4 Bayer dither mixed its levels inside each row,
  so the steps looked ragged. The sky has long low clouds (rounded lobes a tone or two darker than the sky round them,
  their bases lit gold near the sun and pink further off, thin streaks trailing out), the horizon line is brightest
  under the sun, and the far islands are low hills with palm silhouettes, lit on the side facing the sun.

> The request (2026-11-12): "the loading screen isnt centered. also, the transition that happens when entering a cave
> also seems to only affect a smaller part of the screen sometimes. can you also make the loading screen more
> detailed, like the bakery game, with baked in models and animations?"

- **The loading card** (`src/first/LoadingCard`, put up by ReplicatedFirst's Boot before the rest of the game has
  arrived, Random Bakery's way): Driftling Isle at dusk. A sky in dithered bands from night blue to a warm orange, stars
  in the dark of it, the sun going down on the horizon with far islands either side, a banded sea with the sun's path
  on it and small waves; in the middle the island (its shallows, a ring of foam, wet sand, the sand with its cliff in
  front, the grass, a jetty). On it the game's own models, drawn ahead of time through the game's picture path (the
  preview scenario `ploadingart` bakes them frame by frame into `src/first/LoadingArt`): three palms, a Grass Shack, a
  Tent, Tiki Torches, Flower Beds and Round Bushes, the Tree of Life with its pen (its hollow and fruit glowing, then
  dimmer: it took the Tide Pool's place on 2026-11-12), the campfire flickering and throwing
  embers, a villager cheering by it, two villagers strolling up and down the island with a Mossbun and a Clawdle at
  their heels, a Gullfin hopping along the front; the old boat rocking past out at sea, gulls crossing the
  sky, stars twinkling, wave crests and glints of sun coming and going. Over the sky, centred: "Driftling Isle" in the
  pixel font's big face, a status that follows the real loading ("Waking up your island", "Finding your island",
  "Drawing your island", dots counting after it), a progress bar in a frame of planks, and at the foot a tip on an
  ink plate, a new one every few seconds. Everything is laid out from the screen's size each time it changes (the old
  curtain took its size once, so on a window still settling its words sat left of the middle). Roblox's touch
  buttons are hidden while it is up. When the first picture is on screen the bar fills and the card fades into it.
  Without EditableImages it is a plain card (sky, sea, island, title, bar).
- **Blinds that cover the screen:** the walk-in's blinds and the places' curtains were laid out against the screen's
  edges, three screens deep. They went with the wild places (§7).

> The requests (2026-11-06, 2026-11-09): "make the it more polished and animated as well"; "Polish everything to the
> max. Add animations and details to everything, including the minigames"

> The request (2026-11-10): "lastly, polish the whole game as much as possible, and fix any bugs you encounter." In
> this pass: the island only gains land as it grows; charm (paths add fractions) shows whole; a hatchling cheers on the island;
> the new buildings looked over in the `gallery` preview (the Crystal Fountain's water over its gold rim, stepped
> roofs on the Clock Tower and the Water Tower, a lighter brick road); a flaw's words ("-10% health", not "-11%")
> and a flaw never beside its own family's strength.

- **Buttons** lighten under the mouse, sink a pixel while pressed, click when used and buzz when disabled; panels and
  cards fade and rise in; notices slide down.
- **The HUD:** the stores count up and their chip flashes when they change, shells coming in rise from their chip
  ("+12"); the day chip's clock bar creeps along and its sun sets into a moon; the food chip blinks red while hungry;
  the tree's card fills its bar and pulses while the pen is full; a new tip bounces in; a newcomer's banner drops in with a fanfare
  and bits, and a new day's (every few hours) with a ding.
- **The island lives:** villagers walk to their work and back and do it, wander when resting; driftlings hop beside
  their buildings or round the huts, and the pen's wander inside its fence (a new one pops out of the tree's hollow
  with a cheer); a newcomer is welcomed with a word and confetti.

  > The request (2026-11-11): "there are also no proper animations for creatures and villagers that are working on
  > something in the island"

  Work is a loop of real moves now (`CharacterModels` WORK, `DriftModels`' work moods), each building its own. A
  villager swings a hoe up and down into a field (a puff of soil at each stroke), picks fruit one hand then the
  other up on their toes in an orchard, holds a line out off a pier with a tug now and then (a splash), chops at the
  lumber camp with the axe back over the shoulder (wood chips fly), saws to and fro at a sawmill, hands things over
  the counter and waves at a stall or bakery (a glint of a coin), carries a tray and bows at a cafe, inn or hotel,
  taps with a hammer at a toolshed or water tower (sparks), and crouches to tend
  at a greenhouse, a hatchery, a windmill, a smokehouse or the beacon. A driftling pecks at the ground in the fields,
  dips its head for fish at a pier, leans in and pushes at the wood, waves and chatters at the shops, and naps at a hut (eyes shut, low and breathing slowly, for longer). Workers stand along the
  building's front, apart, turned three-quarters to the view so the work reads.
- **The sea lives:** the water rolls and the foam laps the shore (§8; the crests a light blue, as asked on 2026-11-10: "can the green lines of the sea be more of a light
  blue instead?"), leaves
  sway and flags ripple in the wind, sailboats (the boats of §8, their flags fluttering) rock on the swell as they
  cross both ways, gulls cross now and then (from either side, at their own height, weaving and gliding, a
  different crossing each time); each island's campfire flickers and smokes. (No clouds' shadows: the
  player asked for the "random shadow that appears sometimes" gone.)
- **Night falls** and the lamps light up (§8).
- **Sounds** (`Controllers/Audio`): every event plays a free Creator Store sound from Roblox's licensed libraries
  (ProSoundEffects, and APM Music's stingers), none of Random Bakery's, its pitch varied a little, repeats inside a
  short cooldown dropped.

  > The request (2026-11-10): "dont use sounds from the old versions, find and use new ones that fit the island theme"

  The interface is wood and bamboo: a temple-block tap for a click, a bamboo swish as a panel opens and closes, a low
  wooden knock for "no", wind chimes for a notice; shells coming in clack like pebbles (a handful for many); a bubble
  pops; pages turn; a shaker for a cheer. Building is two quick hammer taps.

  > The requests (2026-11-10): "remove the victory sound whenever a fight finishes"; "the victory sound and wherever
  > it plays in such as a villager coming is too noisy, find one with a small short chime instead"; "the building
  > sound is also too, long, make it short"

  > The request (2026-11-12): "use different sounds for newcomer, victory and other sounds that use sounds made by
  > you or was default roblox sounds. use sounds from the free roblox library instead"

  The happy moments each have their own small, short sound from the library, measured for length and loudness before
  going in (no more one music-box note pitched up or down to stand in for the others): a door bell's ding-dong for a
  newcomer moving in; a bell-tree run as the island grows, or as an epic or legendary driftling grows on the tree; a
  sparkling sweep for a rare one; a soft cluster of chimes when an egg hatches; a few bright sparkle tones when a
  piece is replaced by a better one; one triangle ting for a reward (a quest claimed); a music box winding up as an
  egg is laid. (The sounds of the places and the fights went with them, 2026-11-12.) Longer takes play only their first moment and fade out.

  Your founder's feet are the game's own too: Roblox's built-in footstep, jump and landing sounds are switched off
  (an empty `RbxCharacterSounds` script takes their place) and the founder steps softly on the lawn, crunches on the
  sand and knocks on the boards of the boardwalk, the jetty and the pier, a step a stride (quicker when running,
  several takes so no two steps in a row are the same), with a cloth flap for a jump and a soft thump on landing.

  > The request (2026-11-10): "also, find new sounds from the roblox free library to use. try to find fitting ones"

  The islands and the sea: a hammer on wood when a building goes up, gulls squawking as a flock passes over, the
  surf on the sand always, crickets through the night and birds at dawn.
- **Music** (`Audio.music`): APM Music's library on the Creator Store, shuffled, one track after another, crossfaded,
  quiet: calm, drumless music that sits in the background. Soft acoustic island guitar by day (Campfire Stories,
  Tender Reflection, Home Camp), soft solo piano from the twilight (Gymnopedie No. 1, two Live Piano Stories), each
  evened out to the same loudness. Chosen by measuring the tracks (notes a second, the drums' share, the beat's strength, the
  loudness section by section), not by their names. The note in the HUD's corner switches it off and on.

  > The requests (2026-11-10): "also, find cozy background music"; "the background track is too upbeat and noisy.
  > find one that would fit well as background noise and is cozy"

## 12. Out of scope for this version

Trading between players, visiting with gifts, offline progress, purchases (no game passes or products:
`Config/Monetization.luau` holds only the sound and music ids), other languages (English only; every string goes through
`Locale/Lang.t`).
