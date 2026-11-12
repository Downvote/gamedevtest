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
villagers take jobs. Wild places stand on the island itself (a tide pool and some tall grass at first; a volcano, a
cave, a frozen peak and more as the island grows): tap one and take a party of villagers in, befriend the wild
**driftlings** there with snacks in timed battles, and bring them home to help at the buildings of their knack.
Beating a place's guardian clears it, and the ground round it opens up for building. The islands of everyone on the server sit side by side along one boardwalk on a
shared sea. The look, the build system and the file formats come from our own Random Bakery (`Downvote/test`): the
2:1 pixel-art isometric diorama seen through the pixel filter, the pixel font, Rojo with strict Luau, a server that
decides everything, pure Data/Logic modules with specs, and the fake-engine simulator and preview tools.

## 1. The loop in one paragraph

Build a Veggie Patch so the island has food, a Tent so a castaway can move in, a Lumber Camp for wood and a
Snack Stall to sell food to the visitors for shells. Every turn (Tuning.TurnSeconds while you play) the island makes and
eats; a visitor moves into a free bed when the charm is high enough and takes a free job. Build a Driftling Nest,
then tap the Tide Pool on your island: its card shows what lives there; pick a party (you, the captain, and up to
three villagers or driftlings), pay the supplies in food and tap Explore: your founder walks up to it and the blinds
close on its name. Walk its path of stops (loot, chests, a rest, battles with wild driftlings, the guardian at the
end); battles fight themselves on timers: throw a snack (a hurt wild one may join you), use a skill, or flee. Beat the
guardian and the place is cleared: the first clear pays three times its reward and frees the ground round it. Head
home with the loot. Spend shells and wood on more buildings and decor (charm), and expand the island for bigger
buildings; every expansion brings new wild places, higher in level. Nothing happens while you are away (no offline
progress).

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
  coral Close), over the island seen through a sea-dark veil; the island card and the expedition card the same, their
  names on planks; the chips, the notices and the tip (a parchment note) thin frames; the chips and the rows in the
  panels are carved boards (a lit top row, a shaded bottom one); the menu bar stands on a wooden dock; the build tray is
  a workbench with its tabs on a plank; the islet's screen has dark boards top and bottom with plank trims facing the
  island, and its skill window, alerts and results card are framed. The loading curtain is the open sea at night.
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

## 3. The island's turns and the sea's days (`Logic/Island`, `WorldClock`)

> The requests (2026-11-10): "days go by too fast, it should take a few hours at least for a day to pass. also,
> lighting seems to not follow along with the camera as the camera moves"

- **A turn** is `TurnSeconds` (40 s) while you are on the server: the island's pace. Each building that makes
  something makes its rate a turn (the island card shows it a minute: "+57/min"): full with a villager working there,
  half with nobody (`IdleOutput`), more with a driftling of its knack helping (`PalBoost`), more again at Lv 2 and 3
  (`UpgradeMult`: only a building upgraded in an older save is above Lv 1, since upgrades were taken out, §4).
  Villagers eat `EatFolk` food a turn, driftlings `EatPal`. At each turn's end a visitor may move in
  and the yard trains.
- **A day** is `DaySeconds` (4 hours) of the sea's clock (`WorldClock`: one time of day for every island on the
  server, carried on across visits: it follows the real clock): the HUD shows the day count and its clock (a sun, a
  moon for the evening); day and night follow it (§8); each day's end while you play counts a day (a banner).
- **Shops** sell food to the visitors: their rate times visitors / `ShopVisitors` (at most double), eating food the
  same way. **Visitors** a turn: 1 + charm / `VisitorCharm`, at most `VisitorsMax`.
- **Charm:** every piece's charm (a cleared place's included), one for each driftling, `ClearCharm` (3) for each wild
  place cleared, up to `ClearCharmMax` (15).
- **Hunger:** when the food runs out everything makes half and the shops shut until there is food again; the food
  chip blinks red.
- The stores reach the client every second; a newcomer brings a banner (who moved in), the yard's training a word, a
  new day its own banner ("Day 12").

## 4. Building (`Data/Buildings`, `Logic/Plot`, Build mode)

73 pieces in ten kinds, opening as the island grows (tier 1 .. 6, the build tray's "Island Lv"):

| Kind | Pieces (the tier they open at) |
|---|---|
| **food** | Veggie Patch, Fishing Pier (1), Fruit Orchard (2), Greenhouse (3), Rice Terrace (4), Kelp Farm (5), Sky Garden (6) |
| **wood** | Lumber Camp (1), Sawmill (2), Timber Works (3), Bamboo Grove (4), Grand Mill (5) |
| **shops** | Snack Stall (1), Beach Cafe (2), Seaside Inn (3), Bakery (4), Grand Bazaar (5), Grand Hotel (6) |
| **homes** (beds, comfort) | Tent 1, Grass Hut 2 +3% (1), Cottage 4 +6% (2), Longhouse 5 +8% (3), Townhouse 6 +12% (4), Villa 6 +18% (5), Manor 10 +25% (6) |
| **nests** (room, comfort) | Driftling Nest 2, Cozy Burrow 4 +5% (2), Driftling Den 5 +8% (3), Treetop Roost 6 +12% (4), Spring Grotto 8 +18% (5), Driftling Palace 12 +25% (6) |
| **boosts** | Tool Shed (wood +10%), Windmill (farms +10%), Smokehouse (fishing +10%) (2), Market Hall (shops +12%) (3), Water Tower (all +6%) (4), Town Hall (all +10%) (5), Sun Beacon (all +15%) (6) |
| **paths** (2 x 2 tiles) | Dirt Path (1), Stone Path (2), Brick Road (4), Marble Walk (5) |
| the **Training Yard** (2), the **Hatchery** (3, §6.1) | |
| **decor** (charm) | Flower Bed, Round Bush, Picket Fence, Tiki Torch, Sandcastle, Rock Garden, Shell Pile, Palm Tree, Bench, Hammock (1); Hedge, Lamp Post, Picnic Table, Flower Arch, Totem Pole, Fountain (2); Gazebo, Lighthouse, Guardian Statue (3); Street Lamp, Topiary, Bandstand, Clock Tower (4); Canal Bridge, Grand Arch, Observatory (5); Crystal Fountain, Sun Spire, Founder Monument (6) |

Each is paid in shells and wood when placed, on whole studs of the island's grass (a stud or more in from the sand),
turned a quarter at a time, off the campfire's plaza and the path to the jetty, and off every other piece, up to the
island's piece limit (`PlotPieces`: 24, 40, 60, 85, 115, 150; path tiles apart, `PathPieces`: 60 .. 500).

**Wild places** (§7) stand on the grass too, and nothing new goes down within `SiteRadius` (2) studs of one while it
is wild: Build mode outlines each ring in orange, and a piece or path held over one says "Too close to the Tide
Pool". A wild place can't be moved, cleared away or replaced. Once its guardian is beaten it is an ordinary piece:
it keeps its look (a flag planted on it), adds charm, can be moved, or cleared away for nothing back. Wild places
don't count toward the piece limit.

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
  tier's shape joined to the smaller ones': nothing built near an old shore has to move); more villagers (`FolkMax` 40) and
  driftlings (`PalsMax` 40) live there.
- **Comfort** (homes and nests): the best homes are filled first, each villager in the order they came (the same for
  driftlings in the nests). A resident's comfort (its home's, plus 4% / 8% at a level 2 / 3 home kept from an older
  save) makes them work
  that much more (`Island.rates`: a worker's output times 1 + its comfort; a helper's boost grows by it too) and fight
  stronger (health, attack and defence times 1 + it). The Villagers panel shows each one's home and comfort ("Home:
  Villa, comfort +18%"), the Driftlings panel its nest.
- **Boost buildings**: every building of a knack makes more (`Island.boosts`); each kind of boost building counts
  once however many stand, the "all" ones count at every knack, and the boosts at one knack stop at `BoostMax` (60%).
- **Paths** in four materials, laid tile after tile (the piece stays picked), apart from the piece limit: roads
  through a town (a Brick Road brings a little charm, a Marble Walk more).
- **No upgrades** (taken out 2026-11-11: "remove the ability to upgrade buildings"). A better building is a
  **Replace** away, and a level from an older save is kept and still counts.
- **Replace**: a standing piece picked up shows **Replace**: the tray lists the others of its kind open at the tier
  (beds or room for homes and nests), each for its price less half the old one's (`Plot.replaceCost`); a tap swaps it
  where it stands (the new footprint must fit there; a home or nest must still house everyone): its workers stay, its
  level starts again. A tent becomes a cottage, a patch an orchard, a nest a palace.
- A big island well built reads as a city: roads in a grid with street lamps, townhouses and villas, a town hall and a
  clock tower, markets and a grand hotel, parks with hedges, topiaries and fountains (the `city` preview).

- **Build mode** (the HUD's Build): the view frees to pan over the island; a tray of tabs (Food, Wood, Shops, Homes,
  Nests, Boosts, Paths, Decor: icons alone on a phone) lists every piece with its price (red when you are short, locked ones greyed with the tier they
  need). A picked piece is a ghost on a cyan footprint where it fits, red where not; Place (or a second click on the
  same spot) builds it. Tapping a standing piece picks it up to move, **Replace** it (§4.1) or **Clear it away** (half its price back; not a home or nest whose beds are
  needed, not a Hatchery warming an egg). The header counts the pieces (the path tiles on the Paths tab).
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
The Villagers panel lists each one (portrait, level, job, battle stats) with **Job** (a picker of the buildings that
take workers: Go, Swap with whoever is there, or Rest) and **Dismiss** (two taps: they sail off, freeing the bed).
Each villager has their own fighting stats (from their seed) and a skill (Big Bonk, Soothe or Shell Guard), and grows
with levels (xp from battles and the yard).

## 6. Driftlings (`Data/Creatures`, `Data/Traits`, the Driftlings panel, the Index)

> The requests (2026-11-10): "make each creature have a different passive ability. some can have different mutations
> which allow them to do different things better, such as better health, attack speed, etc. mutations also have
> tiers, so a rarer mutation gives better benefits. mimic the system in palworld. some creatures also have passives
> that make them better workers in logging, shells, etc. and mutations also helping in that."; "make much more
> creatures, some rarer than others, and more islands as well". The system is the genre's (a passive of each kind,
> rolled traits in tiers, workers better at some jobs); every name, number and creature is our own.

> The requests (2026-11-11): "alot of the creatures are just simple shapes meshed together. can they be more
> detailed and look more like the animals /creatures that they are referencing?" (with a picture of a green turtle
> that read as a blob); "you should also add more expressive idle and other animations to the creatures, the whole
> mesh seems to move as one throughout all their animations. you can make different moving parts for creatures to
> allow for more expressiveness"

**Their bodies** (`Models/DriftModels`): each of the twenty body plans is rebuilt to read as its animal from the
battle's side-on view. The turtle has a domed shell with a ring of plates and a rim, a head on a neck with a beak, and
flippered legs. The fox pup has a snout and nose, tall ears with dark tips, a fluffy chest and a bushy tail with a white
tip. The crab has eyes on stalks, big claws with a hinged pincer and three legs a side. The gull has a beak in two
halves, wings with a white bar and webbed feet. The rest follow the same way: the rabbit's long ears and big feet, the
gecko's crest and banded tail, the owl's facial discs and ear tufts, the mole's star nose and digging claws, the bat's
two-part wings with finger bones, the yeti's face and horns, the seal's flippers and flukes, the snail's spiral shell
and eye stalks, the frog's bulging eyes and wide jaw, the moth's feathery antennae and spotted wings, the golem's gem
core and slit eyes, the drake's horns, two-part wings and spaded tail, and the sea serpent's coils and toothed jaw.

**Their moving parts:** every driftling stands on a small skeleton (body, head, jaw, ears, arms, legs, wings, fins,
tail segments, eye stalks, pincers, tendrils, antennae), and each joint moves on its own. Idle, a driftling breathes,
looks about now and then, yawns, twitches its ears, sways its tail and blinks. Walking, its legs step in pairs (a
rabbit or frog hops on both hind legs, a crab scuttles, a seal or snail sways, a bat or moth flaps). On an attack it
winds up, then lunges head first with its jaw open, arms and pincers up and its tail raised. Hit, it recoils with its
ears down and eyes shut; cheering, it looks up with its arms up and wags fast; knocked out, it goes limp. The battle
screen's own lean, squash and hops still play on top.

Fifty-five driftlings of our own, five to seven living on each of the nine kinds of island (§7):

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

Each has battle stats, a skill, a **knack** (farms, fishing piers, lumber camps or shops: where it helps), a trust (how
readily a snack befriends it), a 3D model built from parts (twenty body plans: blob, crab, bird, bun, lizard, owl,
pup, mole, jelly, fox, wyrm, seal, bat, sprite, yeti, and the new snail, turtle, frog, moth, golem and drake) and a
16x16 portrait.

- **Rarity** (`Traits.RARITY`): Common, Uncommon, Rare, Epic, Legendary (name colours: grey, green, blue, purple,
  gold). A wild one turns up by weight (100, 45, 16, 5, 1.2: `Expedition.pickWild`), so the commons are met at every
  stop and a legend once in a long while; the rarer are stronger (their stats) and slower to trust. The guardians are
  the rares and epics of their kind (never a legend); when a wild epic or legend turns up the screen says so ("An
  epic Wispwing appears!", "A legendary Solwyrm appears!", in its rarity's colour, with a fanfare).
  Its **power** (`Creatures.power`: its stats weighted, +12% a rarity step) ranks the kinds.
- **A passive of its own** (`passive`: a name and its effects, every kind's different): shares added to health,
  attack, defence, speed (its timer fills faster), learning, or work (at any building, or at farms, fishing, lumber or
  shops: "Snappy Pincers: +10% attack, +15% at fishing", "Fertile Trail: +30% at farms"). In battle the shares scale
  its stats (`Battle.applyFx`; a wild one has its passive too); at work a helper adds `PalBoost` x (1 + its share at
  that building's knack) (`Island.palWork`), so a woodsy driftling at the lumber camp is worth more than any other there.
- **Mutations** (`Data/Traits`, `Pal.muts`): every wild driftling is born with up to three (about one in three none),
  rolled when it appears (`Traits.roll`; a guardian rolls as one rarity rarer) and kept when it is befriended, so
  the player picks whom to befriend: the fighter cards show them as pips in their tier's colour (best first), and
  aiming a snack names the pick's ("Magmole: Savage, Nimble"). Ten families of four tiers, each tier rarer and
  stronger: Sturdy / Hardy / Ironhide / Titanic (health +8 / 15 / 25 / 40%), Feisty .. Ferocious (attack), Thickskin
  .. Fortress (defence), Nimble .. Lightning (speed +6 .. 32%), Curious .. Genius (learning +10 .. 60%: more xp from
  every win), Busy .. Workaholic (work anywhere), and Green Thumb .. Bountiful, Angler .. Sea Sage, Chopper .. Forest
  Heart, Chatty .. Tycoon (+12 .. 65% at farms, fishing, lumber, shops). Tier weights 46 / 25 / 10 / 3 (and 16 for a
  **flaw**: Frail, Timid, Clumsy, Sluggish, Lazy, a little worse, never beside its own family's strength); a rarer
  kind rolls fewer flaws and more of the top tiers. A driftling carries four at most (a Hatchery child can gain one,
  §6.1). Each counts in battle and at work like the passive, and their names show in tier colours (with stars) on
  the Driftlings panel; a new friend's alert says what it was born with ("Born Savage, Nimble").

A befriended driftling needs a free nest slot (`PalsMax` at most) and starts helping where its knack is needed. The
Driftlings panel shows each (portrait, its name in its rarity's colour, level, skill, its passive, its mutations, where
it helps, stats) with **Help** (a picker of the buildings of its knack, or Rest) and **Release** (two taps). The
**Index** lists all fifty-five: a dark shape and its rarity until met, named once met, its passive once befriended
(and a heart).

### 6.1 The Hatchery (`Logic/Breed`, the Hatchery panel)

> The request (2026-11-10): "make a breeding system that also works like in palworld that unlocks after a certain
> island level". The genre's system (two parents, a feast, an egg, the child's kind from the parents' strength, their
> traits passed on) in our own buildings, numbers and words.

- **The Hatchery** (Nests tab, Island Lv3: a warm nursery with a nest of speckled eggs and a heat lamp): one egg at a
  time each; several may stand. The Driftlings panel's **Hatchery** button opens its panel.
- **Laying an egg**: tap each slot, pick a parent from the driftlings at home (not the other one, not one away); the
  panel shows what they would likely hatch (its portrait once met, else a dark shape and ???) with its rarity, and the
  feast and the turns it takes; **Breed** pays the feast (`BreedFood` 40 / 70 / 120 / 200 / 400 food by the child's
  rarity) and lays the egg (`BreedTurns` 3 / 4 / 6 / 9 / 14 island turns). The parents carry on as before.
- **What hatches** (`Breed.child`): a pair of one kind hatches its kind; any other pair the kind whose power is nearest
  their average (so two strong ones can make a kind the player never met); a legend only from two legends.
- **What it inherits** (`Breed.inherit`): a mutation both parents carry always passes on, the better tier, and with
  `BreedTierUp` (30%) a tier better still (a shared flaw becomes its family's first tier); one only a parent carries
  passes on half the time (`BreedKeep`); with `BreedNew` (15%) it gains one of its own (tier 1 or 2); the best four.
  Breeding two that share a mutation, again and again, climbs it to the top tier.
- **Hatching**: at each turn's end the eggs count down; a ready one hatches into a free nest (level 1, helping where
  its knack is needed, in the Index; "An egg hatched!" with its name), else waits ("Ready! It needs a free nest.").
  The panel shows each egg: its rarity's egg, "Hatches in 3 turns" over a bar, its parents. A Hatchery holding an egg
  is not cleared away ("An egg is still warming in that Hatchery."). On the island the hatchling cheers where it
  appears, its name floating up in pink.

## 7. Expeditions and battles (`Data/Sites`, `Data/Islets`, `Logic/Sites`, `Logic/Expedition`, `Logic/Battle`, the walk in, the place's screen)

> The request (2026-11-11): "Remove the exploration system. Instead, caves and tall grass and volcanoes and other
> areas will spawn on the island when it is first created, with an area for each island we are removing. These caves
> and other structures will take up space around them, preventing you from building in a radius around them. You can
> tap on them to enter an expedition just like an island before. Clearing one of them will remove this restriction, nd
> allow you to destroy or move them around as a building block. Expanding your island will cause more of these caves
> to spawn, with higher level per expansion. Also, caves are no longer infinite, they are cleared once the boss is
> defeated, and give bigger first time clear rewards."

- **Wild places** (`Data/Sites`, `Logic/Sites`): one kind of place for each kind of island the sea chart had, each
  with that kind's driftlings and 3D stage: the **Tide Pool** (beach), **Tall Grass** (meadow), **Bog** (mangrove),
  **Volcano**, **Cave** (grotto), **Frost Peak** (snowfield), **Windy Bluff**, **Coral Pool** (reef) and **Old
  Ruins**. A new island has two (a level 1 Tide Pool and a level 3 Tall Grass); each expansion brings three more,
  every one higher in level than any before it:

  | Tier | Places (level) |
  |---|---|
  | 1 (a new island) | Tide Pool 1, Tall Grass 3 |
  | 2 | Bog 6, Tide Pool 8, Volcano 10 |
  | 3 | Cave 13, Tall Grass 15, Frost Peak 17 |
  | 4 | Windy Bluff 20, Coral Pool 23, Volcano 26 |
  | 5 | Old Ruins 29, Cave 32, Frost Peak 35 |
  | 6 | Coral Pool 38, Windy Bluff 41, Old Ruins 45 |

  A place comes up where its footprint fits on the grass with its ring clear of the other wild places' rings. It
  prefers a ring with nothing built in it, the land the expansion just added and the island's edge (the middle is
  where the village grows); where depends only on the island's seed. Pieces already standing are never moved for
  one; a place with no room anywhere is passed over. An old save gets every place of the tiers it has reached when it
  loads.
- **On the island:** each wild place is a small diorama of its kind, with two eyes glowing out of it (a rock pool with
  crabs' claws; a round clump of grass taller than you; brown water under mangrove roots; a stepped cone with a lava
  crater; a boulder with a dark mouth and crystals; a frozen heap of rock; a windswept crag; a blue pool on coral; a
  broken arch of old stones). Its name and level float over it (orange). Cleared, the eyes go, the place calms down
  (the lava cools, a plank bridge crosses the bog, the grass is cut back with a path trodden through) and a flag is
  planted on it; it loses its label.
- **Tap a place** (yours, on your own island) to open its card: its name ("Seashell Tide Pool"), kind and level
  (green up to the captain's level, yellow up to three over, red above), what it is like, whether it is wild ("Wild.
  Nothing can be built close to it.") or cleared, what its guardian pays (First clear, or Clear it again), who lives
  there and its guardian, how many stops in, the snack pouch, and the party. Explore sets off. The tips' arrow bobs
  over the island's lowest wild place while they point at it.
- **The walk in** (`UI/Voyage`, skippable with Skip, Space or Return): letterbox bars slide in, the HUD steps aside,
  your founder walks up to the place (the view following), and ink blinds close on its name and kind. The place's
  screen opens behind them with the party already there.
- **Home again:** the blinds close over the place's screen, the island comes back behind them with your founder
  standing in front of the place, the blinds open, the founder cheers, and the HUD and the loot come back.
- **A place has an end:** the landing, then `BossEvery` (7) stages: six stops (battles, loot, chests, maybe a rest;
  at least three battles) and the guardian at the seventh. The header shows the whole path. The guardian's fall clears
  the place and ends the trip: the **Cleared** card ("Seashell Tide Pool cleared") lists the reward, what comes home
  and the party's xp and levels; Head home takes everyone back. The first clear pays `FirstClear` (3) times the
  place's reward and frees its ring; a cleared place can be explored again for `ReplayReward` (0.4) of it (its
  driftlings are still there to befriend). The party can head home at any point, as before, with everything found.

The sea chart, the boat and its upgrades are gone. What follows is the history of the expedition rules; where it
still speaks of islands, the chart or sailing, read wild places and walking in.

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
  island out of range says "Too far for your boat. A bigger one could make it."
- **The boat** (levels 1 to 6, `BoatRadius`, `BoatCost`): Upgrade, under the chart, pays shells and wood (500 and 60,
  then 1,800 and 200, 7,000 and 800, 18,000 and 1,800, 40,000 and 4,000) for the next level and a wider range; the
  boat at the pier, the one that sails you out and the one at the islands' shores is the new one (§8).
- **What an island holds** (`Logic/Expedition.chart`, from its level and its own seed):
  - **its kind**, one of those open at the level, picked by its seed: **beaches** from the start, **meadows** from 5,
    **mangroves** from 7, **volcanoes** from 10, **grottoes** from 13, **snowfields** from 16, **bluffs** from 20,
    **reefs** from 23, **ruins** from 28 (each its own 3D stage: a murky bog of mangroves on stilted roots and a
    water channel; a dark cave floor of glowing crystals; grassy clifftops of stacked rock and a cairn; sandstone
    flags of broken columns and arches);
  - **its name**, two words of its kind ("Gull Key", "Willow Thicket", "Scorch Peak", "Frost Drift", "Brine
    Hollow");
  - **its driftlings**: every one of its kind (the rarer met less often, by weight) and a common or uncommon one
    that strayed in from any kind open at the level; its **guardian** is one of its own rares or epics, titled
    ("Grumpy Shellback", "Elder Glacior"), two levels up with a friend from level 4 (and always from the second
    guardian on);
  - **what it holds**, growing with the level: a loot stop's food and wood, a chest's shells, the guardian's reward
    (`Isle*`).

> The request (2026-11-10): "make all islands infinite, with monsters scaling in difficulty every level and bosses
> every few stages. make an autobattle function as well that clicks fight every turn. make an option to stop when
> party is low in health and likely to lose in the next fight as well"

  - **It never ends:** after the landing the island's stages come in blocks of `BossEvery` (7): six stops (battles,
    loot, chests, maybe a rest late on; at least three battles) and then a guardian, block after block, each from the
    island's seed (the same island every time, however far anyone goes). The header shows the stage and the path a
    few stops ahead (the next guardian's crown); the HUD's card the stage.
  - **Harder every stage:** the wild ones start a level under the island's and grow `StageLvl` (half a level) and
    `StageBoost` (2% health and attack) every stage, past the captain's own levels; loot and chests grow too
    (`StageLoot`).
  - **A guardian every few stages:** the first charts the island the first time (its whole reward; half on later
    trips); each later one pays more (`BossRewardGrow`: the n-th 1 + 0.6 x (n - 1) times the island's reward). A
    guardian's fall is an alert (charted, or "Guardian 2 beaten!") and the party walks on: sail home whenever you like
    (any time, a battle included: below); a fall ends the trip, and all the loot still comes home.
  - **Battles fight themselves** (the timed battles below; the earlier auto battle is what every battle does now), and
    the party walks on between stops by itself.

    > The request (2026-11-10): "no need to add the option that autopauses if the next fight will be losing. remove
    > the penalty that happens if you lose. also, make the skill options yellow instead of blue. also, some items in
    > uis clip out such as the skill menu"

    So there is no Stop if losing (the party never waits for a fight it may lose) and no penalty for a fall: the
    party comes home with everything it found. The skills are yellow (the Skills button, the skill points and each
    skill in the window); the skill window fits the screen between the header and the footer (a member's skills wrap
    onto further lines, and the window scrolls when they still don't fit), and no panel's words run off its edge.
  Clearing counts each place once (`islets` in the save; each is charm up to `ClearCharmMax`).
- **The sailing cutscene** (gone: the walk in above replaced it) (`UI/Voyage`, skippable with Skip, Space or Return): letterbox bars slide in and the HUD steps
  aside; your founder walks from where they stand down the path, across the boardwalk and along the pier (or starts
  on the jetty when far away) and hops into the expedition boat, where the rest of the party waits on deck and
  cheers; the boat casts off and sails out to sea, the view following it; ink blinds close on the island's name and
  kind. The islet's screen opens behind them and the boat glides in to the island's shore where the trail starts;
  the party hops off and walks up it to its places, the camera coming with them. The boat stays away from the pier while the expedition does.
- **Home again by boat** (gone: the walk home above replaced it) (`UI/Voyage.home`):

  > The request (2026-11-10): "make a transition instead of an instant cut back to the island after an exploration."

  Sail home (or a won or lost expedition's end) closes the ink blinds over the islet on "<name>'s Isle" (or "Home
  again!"); behind them the island comes back, the blinds open on the boat sailing in from the sea with the party on
  deck, the view following it to the pier; your founder hops onto the middle of the pier and walks off it freely.
  (The bug behind "the player gets stuck at the bay": the sea's east end ran its two invisible walls along the whole
  boardwalk, across every pier and jetty; they now stand only along that end's own stretch. The pier's crates, barrel,
  rope, bollards and the moored boat are scenery and don't collide.)
  the party cheers, the HUD comes back and the loot is shown. Back to island (the expedition waits) closes and opens the blinds the same way, without the
  boat. The view starts on the boat: behind the closed blinds it jumps straight to the boat (no swing over from the
  island's middle) and the blinds open only once it has settled there; then it follows the boat in, and the founder
  as they hop off.
- **The party:** the captain (you) and up to `PartyMax` villagers or driftlings, picked on the place's card (the
  strongest listed first). Supplies: `Supplies` food each. While away they neither work nor eat; they can't be
  dismissed or released. One expedition at a time; leaving the game brings it home with its loot.
- **Battles, timed:**

  > The request (2026-11-10): "make fights happen in this fashion: the characters have a timer above their heads that
  > is shown as a bar, and will attack or use its skill once a timer is done, and reset the timer. using a snack greys
  > and pauses the fighting, and allows you to select an enemy, with your leader having an arrow marked on the floor
  > to whoever you are selecting in a circle. you are also only allowed to use snacks 5 times an expedition, which can
  > be upgraded to 30. this causes the leader to reset its attack timer and throw a snack at the enemy, catching it if
  > it can."

  Everyone has a timer, a small bar over their head (gold for the party, orange for the wild ones), filling in
  `AtbTime` seconds at an average speed (quicker for the quick, `AtbMin` .. `AtbMax`). Full, the fighter acts: an
  attack (the party the weakest foe, a wild one a random member) or, every `SkillEvery` actions, its own skill; then
  its timer starts again. One action plays at a time (`ActLock`: as long as it takes on screen; the timers fill on
  meanwhile, flashing when full and waiting). So that the fighters act as their timers fill rather than wait in line,
  a crowded fight fills every timer a little slower (`Battle.crowd`: the actions the timers ask for take about
  `AtbShare` of the time; both sides alike, so the odds stay the same): with a full party a full timer waits about a
  tenth of the time. The server runs the battle; a new one waits until its wild ones have landed, and a battle waits
  while the screen is closed.
  - **Snacks** (`Snack x5`; S or 1): the picture greys and the battle pauses; your leader stands in a glowing ring on
    the floor with a dashed arrow running all the way to the wild one picked, which stands in a ring of its own, a
    pointer over its head (the most hurt first).

    > The request (2026-11-10): "make the arrows extend all the way to the targeted character and have a better
    > transition. also, make it a hover or tap thing, tapping on the selected enemy will use it on it"

    The arrow's dashes march toward the pick; when the aim opens the arrow grows out of the leader's ring, and on a new
    pick its end glides over (the arrow swinging and stretching with it) while the pick's ring pops in. Pick by
    pointing at a wild one (a mouse: hovering picks it), tapping it, tapping its card, or the arrow keys; a tap or
    click on the one picked throws (as does Throw!). Throw!: the leader's timer starts again and the snack flies; the wild one catches it, and
    joins you, as often as its trust says (more the more hurt it is, less the higher its level); else it shakes its
    head. A snack needs a free nest. `SnackBase` (5) snacks a trip with the first pouch; a **bigger pouch** (the Explore
    panel, `PouchCost` in shells and wood) holds 5 more a level, up to 30.
  - **Skills** (K or 2): see below. **Flee** (F or 3): a chance by speed; a miss starts the leader's timer again.
  A guardian takes no snack and is not fled from. A win gives xp to the party (levels; new skills learnt are named)
  and shells; the knocked-out get up with a quarter of their health. If the party falls, the expedition is over and
  all the loot comes home (no penalty; the Expedition Complete! card below).
- **Skills:**

  > The request (2026-11-10): "also, make skills: you can select a menu in battle anytime that opens a skill window.
  > you can choose different skills that act like the snack interface, doing so causes your teammates to do something
  > like rally, heal team, heal selected member, do aoe damage, etc. they learn these skills on level up, including the
  > leader as well. however, these cost skill points, which charge up over time in battle. stronger skills will cost
  > more skill points"

  The party shares **skill points** (the SP bar under Skills): they charge `SpRate` a second while a battle runs, up
  to `SpMax` (10). They carry on from one battle to the next on a trip (a new trip starts at none). **Skills** opens the skill window any time in a battle: it
  greys and pauses the battle like a snack; each member standing lists the skills they have learnt, with their cost
  (greyed when the points don't cover it yet, or there is nobody to aim at). Picking one aiming at nobody uses it at
  once; one aiming at a member, a fallen member or a wild one opens the aim like a snack's (the user's ring, the
  arrow to the pick and the pick's ring on the floor; hover or tap to pick, tap the pick to use it). The one using it acts at once and their timer starts again. Who learns what, by level
  (`Data/Skills`): the leader Rally Cry (Lv1, 3: the team hits harder), First Aid (Lv3, 3: mends one member), Group
  Hug (Lv6, 5: mends the team) and Charge! (Lv10, 7: every ally acts at once); everyone else the family of their own
  battle skill: bash (Power Bonk, Spin Swipe on every wild one, Mega Bonk), quick (Flurry of three hits, Zoom Zoom
  past every wild one, Tailwind: every ally's timer jumps ahead), zap (Spark, Tide Wave, Squall on every wild one),
  heal (Mend, Soothing Rain on the team, Revive a fallen member) and shell (Shell Up, Coral Wall: a long guard and a
  little mending, Dizzy Shell: every wild one's timer starts over). The stronger, the costlier (3 to 9 points).
- **The islet's screen** (3D, full screen): the island's own stage, its kind's set laid out by its seed (an island
  of its own, its shore stepping down into the moving sea: a beach with palms leaning out, a treasure chest, tide
  pools, maybe a rowboat, starfish and shells; a mossy meadow with trees, ferns, mushrooms, a winding stepping-stone
  path and maybe a fallen log; dark volcanic sand by a volcano with lava running down it, a rocky mound, obsidian and
  vents; a snowfield by a snowy peak with pines, ice crystals, maybe a frozen pond; the sea floor's corals, kelp,
  anemones, clams and maybe a sunken anchor), drawn by the pixel filter, with the party near the bottom left (your
  founder, villagers as their chibis, driftlings as their models), their backs to you, and the wild ones far off at
  the top right facing them (the battle view below). Along the top:
  the island's name and level, the loot so far, the path of stops (the ones ahead hidden but
  the guardian's crown) and Back to island (the expedition waits; the HUD's card brings you back). Along the bottom:
  the commands at the left (Skills and the skill points' bar under it, Snack and Flee in battle; Next stop and Sail
  home between stops; while aiming Throw! / Use! and Back, arrows to switch, Space to go) and the party's boxes at
  the right (the battle's boxes below). A win shows its xp, shells and level-ups, a new friend its portrait with
  confetti, a guardian's fall the island charted.

> The request (2026-11-10): "after returning home, the player gets stuck at the bay. also, make animations much more
> expressive and detailed, such as attack animations. make character and creature models much more detailed as
> wellmake it such that there is no need to click on "go on", it automatically goes on. also, make an actual day
> night cycle, causing things to go dark and then bright as time goes on"

- **It goes on by itself:** between stops there is no Go on to tap: the next stop comes up at once (since the
  2026-11-11 request below there is no bar to wait on either). A won battle is a small alert under the
  header (Victory!, the xp and shells, level-ups, a new friend's portrait) that goes by itself after `AUTO_CARD`
  (3 s), with no button. A fall shows the Expedition Complete! card (below), which waits for Sail home.

> The requests (2026-11-10): "the player is still stuck here. can you remove the invisible wall?"; "day night cycles
> should also affect islands the player is battling on. also, the onward popup should just be a small alert with no
> need for the player to press a button to continue"
- **Battles move:** a round plays back blow by blow. An attacker winds up (crouching back, squashed, the founder and
  villagers drawing a fist back with a fierce face), dashes right up to its target (stretched, kicking up dust),
  strikes (a lunge and a swing with a shout, a bite or a ram leaning in), and hops back home. The blow freezes the
  action for a few frames, shakes the picture, flashes the one hit and bursts into sparks; the one hit is knocked
  back leaning away (a flinch, a cry, eyes shut), or, when it is down, sent flying with a spin to lie flat (dust and
  stars). Skills have their own moves: a bash leaps high and slams down (a bigger shake, dust and debris), quick
  strikes three times in a blur of afterimages, a zap charges up in sparks where it stands and throws a bolt, a heal
  spins up with green bits and the healed one bounces, Shell Guard has everyone hunker down behind a glint, Rally
  sets them jumping; a learnt skill shouts its name in a flourish of sparks, a revive brings the fallen up in a
  shower of green, Tailwind sets the party springing, Dizzy Shell has the wild ones stumbling; a snack is thrown in an
  arc and the wild one hops
  for joy with hearts, or shakes its head; fleeing turns everyone round to sprint off, or trip over their feet; a win
  has the party jumping and spinning in turn. Every driftling's limbs move with it: wings flap, claws and pincers
  snap open on the strike, tails wag, ears twitch (and droop when hurt), eyes blink and shut when hurt, mouths open to
  bite, cry or cheer.

> The request (2026-11-11): "also, instead of having creatures pop out of the island, make the party run to the right
> in an endless island after clearing one area to reach the next encounter"

- **The run on** (replaced on 2026-11-11 by one area, below): the island goes on ahead, one area after another (each laid out from the island's seed and its own
  number, the land running from one into the next as one long road). When a stop is done the party walks on up the
  road to the next area (up and to the right on the screen, since the 2026-11-11 battle view below), everyone a
  moment behind the one before, and the camera follows. The next stop is
  already there: the wild ones stand waiting in the new area, a chest sits in its sand, and the battle starts a
  moment after the party gets to their places (a guardian a moment longer). Nothing drops from the sky any more.
  The landmark (the volcano, the snowy peak, the big tree, the cave, the arch) stands only on the landing's shore,
  so it falls behind as the party runs on. Nothing tall stands on the road (props keep to its two sides), and Back
  to island works on the way too.

> The request (2026-11-11): "paths should be able to be drawn or made in a box like the original interface in the
> bakery game. also, fights should be shown in the same view as pokemon or beasty bay, in an angle like the image
> shown, and the party will also walk forward in the view like the image shown. polish the battle experience and
> interface much much more"

- **The battle view:** the fight is seen the way the monster-catching games show it, at the game's own 2:1 angle
  (other angles would break the pixel grid). The party stands on the trail at the bottom left, their backs to you, in
  a loose row across the screen so nobody hides anyone; the wild ones stand further up it at the top right, facing
  them, the guardian in the middle of its side. The camera sits close enough for the fighters to read big, and the
  party walks forward up the trail into the next area between stops. On the way in, the boat comes up behind the
  party: the picture opens over it, it glides in with its bow in the foam, the party hops off onto the beach and
  walks up the trail to its places, and the camera comes up with them to the fight. (The round platforms each side
  first stood on are gone: below.)

> The request (2026-11-11): "remove the circles in the islands. also, detail them more, and make them look more like
> a path with actual terrain and detsils"

- **The trail:** each island is a trail through real ground now, not a tiled floor. The path winds up the island a
  little lower than the land beside it, with a ragged, worn verge, wheel ruts where carts would go, pebbles and
  footprints, and it opens into a trampled clearing where each side of a fight stands. The land beside it comes in
  two tones in patches, with tufts of grass, stones along the verge and flowers, and runs on past the old floor's
  edge to a wobbly rim above the beach. Each kind has its own: a sandy track with footprints, shells and driftwood on
  a beach; a dirt road through grass with mushrooms in a meadow; a road of ash with glowing embers and lava cracks by
  a volcano; trodden snow with footprints and sled ruts and snow lumps on a snowfield; pale sand with coral and
  seaweed on a reef; a plank boardwalk with posts over the mud, reeds and lily puddles in a mangrove (its channel
  runs alongside); gravel through dark rock with glowing crystals in a grotto; a dirt track over grass on the bluffs;
  and a straight road of old flagstones, a few missing, with rubble in the ruins. On the landing the trail runs on
  out to the beach where the boat comes in. Things from the old floors that crossed the road (a row of stepping
  stones, a snowbank, a kelp hedge, a lava crack) keep to its sides.
- **The battle's boxes:** laid out the way those games lay theirs. The wild ones' boxes go down the top left (they
  stand at the top right): portrait, name, mutation pips, level, and "HP" with the bar, plus a crown beside the
  guardian's and a nest beside any kind you've already befriended. The party's boxes sit two by two at the bottom
  right: the same, plus the health in numbers and the member's timer as a thin line under the bar (it blinks when
  full). The commands sit two by two at the bottom left. A bar runs down when hit rather than jumping (about a second
  for a whole bar), the part just lost stays pale a moment then follows, it turns yellow under half and red under a
  fifth, and a party member's numbers count down with it and go red when low. A box jolts side to side when its
  fighter is hit; a wild one's box slides back out once its bar is empty.
- **The encounter:** the wild ones' boxes slide in from the edge one after another (no white flash: taken out
  2026-11-11), and a line names them ("A wild Mossbun appeared.", "Wild Mossbun,
  Floe and Pebblit appeared."; a guardian "King Frostdrake is in the way.").

> The requests (2026-11-11): "no need to make the party walk anymore, the creatures will appear in a single area.
> also, zoom out a bit during battle"; "make each character have a short unique attack animation, no need for them
> to charge towards who they are attacking, they now attack in place. also, the attack sounds seem delayed. also, no
> need for the "next stop" pause between every part, just go on to the next immediately in the expeditions"; "when in
> battle, transition and darken everything in the background except the combatants"

- **One area:** every stop plays out where the party landed. The party stays on the trail (anyone knocked down gets
  back up in their place), and each battle's wild ones come running down the trail from out of sight to their
  places, one a moment after another, the dust flying; the fight starts once they're there (a guardian a moment
  later). The camera holds still, and sits a little further back than before, so the battle is a bit smaller with
  more of the island round it.
- **No waiting between stops:** the "Next stop" bar is gone. When a stop is done the next one comes up straight
  away; between stops the footer only has Sail home.
- **Each fighter attacks its own way, where it stands:** nobody runs up to the target any more. A driftling moves the
  way its body does: a blob bounces, a bunny or frog pounces, a crab snaps twice, a drake rears and roars sparks
  across, a golem or yeti stomps, a jelly or moth puffs up and lets go a burst of twinkles, a lizard or wyrm whips
  round with its tail, a mole or pup headbutts, an owl or bird pecks three times, a sprite spins up, a snail or turtle
  spins in its shell, a bat dives. Each kind has its own tempo, height and turn, so no two look the same. The founder
  punches; a villager kicks, swings, slings a pebble or hops and stomps, by who they are. The skills' moves (a
  bash's leap and slam, quick's three jabs, a zap's bolt) are played in place too. The blow lands at the target the
  moment it's struck.
- **Sounds on time:** a swing is heard as it starts and the hit at the blow. The battle's sounds are loaded when the
  game starts, so the first ones aren't late either.
- **The spotlight:** while a fight is on, the background fades darker and a little cooler over about half a second,
  and the fighters, their effects and anything glowing stay at full colour. It fades back when the fight ends, unless
  the next stop is another fight: then it stays dark through to it, so going from fight to fight doesn't blink.

> The requests (2026-11-11): "make skill points cary on across stages. also, make a less loud sound for attacking.
> make attacking cooldowns much faster across all creatures. also, remove the ability to upgrade buildings"; "also,
> show what skills do while hovering or pressing onto it"; "remove the flashing that happens after and before battles
> as well"; "zoom out more in the expeditions even more"; "also, make the party members stand further apart in
> battles"

- **Skill points carry on:** what the party has left at the end of a fight is what it starts the next one with, all
  through a trip (up to `SpMax`).
- **Quicker fights:** every timer fills in about half the time it did (`AtbTime` 1.3 s at an average speed, from
  `AtbMin` 0.6 to `AtbMax` 2.8), for every fighter alike. The moves are snappier to match: an attack plays in about
  half a second (`Battle.EVENT_SECS`), the next action starts as a blow settles, and if actions queue up the playback
  runs a little faster until it has caught up. Wild ones give a little less xp (`XpPerFoe` 4.5, from 6) so that more
  fights a minute don't rush the island's growth past GAME_DESIGN 10's bounds.
- **Softer blows:** the swings, hits, bites and zaps play at about half their old volume.
- **What a skill does:** rest the pointer on a skill in the skill window, or put a finger on it, and a small plate
  shows its name and cost, its line ("Mends one member."), what its numbers do ("Mends 40% of their health.", "3
  hits, each 80% of an attack, on one wild one."), who uses it and how it aims ("Pick a member.", "No aiming."). A
  quick tap still uses the skill; a finger held on it for about half a second only reads it, and lifting it then
  does nothing.
- **No flashing:** the white flash when a fight starts is gone, and the spotlight no longer lightens and darkens
  again between two fights in a row.
- **Further out:** the camera sits further back again, about 54 studs across the screen, so the fight is small in
  the middle of the island with the sea round it.
- **Spread out:** the party stands about 4 studs apart instead of about 2.7, and the trail's clearing is wider to
  hold them (anyone standing on the grass beside the path stands on the grass, not sunk to the path's level).


> The requests (2026-11-11): "make the first snack throw in the tutorial always catch. also, the camera bugs out
> whenever the player returns home, make it center to the ship and the player instead of the land. also, allow
> players to see mutations and details of a creature in battle by hovering over it or holding onto it on mobile.
> also, allow players to exit and return to the island at any point. also, make it such that attacks are paused when
> you are selecting a skill or throwing a snack, even if they are mid attack. if a snack is thrown, the attack is
> cancelled if it is mid attack"; "instead of the screen that says your party fell, say "Expedition Complete!" along
> with the resources you collected, and the xp and lvls gained from the expidition"

- **The tutorial's catch:** on the tips' fight and catch steps (6 and 7) a thrown snack always lands, so the first
  catch can't miss. After the tips the odds are the usual ones.
- **A closer look:** point at a fighter (or its card) with the mouse, or hold a finger on it for about half a second,
  and a plate shows over its head: name and level, rarity (and whether it is wild), health, attack, defence and
  speed, its passive, and each mutation with its tier stars in the tier's colour. The plate follows the fighter and
  goes when the pointer moves off or the finger lifts.
- **Leave any time:** Back to island also works mid-battle. The battle holds while a card asks "Leave the battle?"
  ("Head back?" between stops): Sail home now (the trip ends there and the loot comes home), Leave it here for now
  (the screen closes and the trip waits, as before; not offered once the trip is over) or Stay (the battle picks up
  where it stopped).
- **A pause stops everything:** the skill window, aiming a snack or a skill, and the leave card stop the battle's
  clock on both sides. That covers the timers and any attack already playing: it freezes mid-swing and finishes
  after. A snack thrown while a wild one is mid-attack cancels the attack. Its damage is undone (the server keeps what
  the attack changed until it has played out), the attacker hops back to its place, its timer starts over, and then
  the snack flies.
- **Expedition Complete!:** a fallen party no longer gets "The party fell". The card says "Expedition Complete!" and
  lists what the trip brought home: shells, food and wood, the party's xp, and each member's levels ("Mossbun: Lv 3
  to Lv 5"), or "No new levels this time." Sail home takes everyone home as usual.

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
  colour and pool warm light round them in three stepped rings on the pixel grid (the pools move with the picture as
  the view follows you), only as strong as the dark is deep (no orange rings in the late afternoon), never all the
  way back to the day. As it gets dark pale things lose more of their light than dark ones (their brightness over a
  knee is pressed down), so white and pink shells, the sand and the sails stay in the night instead of glowing blue.
  The change steps (a few steps between keys, never a smear). The islands you battle on
  follow the same clock: a night battle is fought in the dark by the volcano's lava and the party's own light; with
  the pixel filter off Roblox's own clock follows the day instead.

  > The bug report (2026-11-10): "lighting also seems buggy, especially with shells"
- **Detail everywhere:** palms that lean, rocks, shells, starfish, driftwood, seaweed and flowering tufts strewn by
  each island's own seed; the boardwalk's planks on beams and posts with rope rails and lanterns; a pier with your
  moored boat. Every building has its doors, windows, ridged roofs with eaves, crates, barrels, sacks and pots, its own
  touches (the patch's scarecrow, the pier's fishing hut and pond, the hut on stilts, the stall's awning, the
  lighthouse's lamp) and, at Lv 3, a lamp and a pennant. Driftlings have shiny eyes, cheeks and a mouth.
- **Boats** (`Models/BoatSpec`: one plan for the boat at the pier, the one that sails you out and home, the one at
  an island's shore and the sailboats crossing the sea), bigger and finer with each boat level: a planked hull with
  seams, a painted band (gold trim from level 4), a rim, a bow (tall against the hull, flush with the rim, its keel
  sloping up to the stem's point), a stern with its rudder and tiller and a planked deck;
  a rowboat's oars at level 1; a cabin with a door, windows and a life ring from 2; a bowsprit and jib from 3; a
  foremast, a crow's nest and a figurehead from 4; a chimney and a stern lantern from 5; a mizzen and blue sails at
  6; striped sails, a flag and pennants, a lantern, fenders, a crate and barrels.
  With the sea chart gone (§7) the boat at the pier is scenery: the first boat, moored there for good; the
  sailboats crossing the sea still come in every size.

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
  day, villagers, driftlings, charm and wild places cleared.

## 9. Your founder, settings and the tips

The Looks panel sets the founder's skin, hair, style and shirt (every client sees it). The founder walks and jumps
(`JumpHeight`) on the islands; jumping is held in Build mode, on a place's screen and during the walk in and home (the phone's jump
button hides with it).

> The request (2026-11-10): "allow the player to jump in their own island as well"; the bug report: "jumping seems
> bugged. also, the player can walk on water" (the chibi stood still on the ground while the character jumped: it now
> rises with it, knees up, and lands in a puff; the coast's invisible walls stood a little under a jump, so a jump
> cleared them onto the sea: they now stand far higher)

Settings: the pixel filter's quality, and the music (the note in the HUD's top right corner, on or off, kept with the
profile). **The tips** (the banner over the menu bar, or over the build tray in Build mode: §4), each saying where
the stores come from:

> The request (2026-11-10): "the tutorial should also state how to get food, wood and shells. start with enough shells
> to buy all the facilities required."

> The request (2026-11-10): "make the tutorial also cover fighting, and catching creatures. the player should be able
> to go to the first island with a party member that instantly moves in after a tent is built. also, party slots
> should auto equip with the strongest party members"

1 "Everyone here eats. Tap Build and place a Veggie Patch to grow food."; 2 "Bigger buildings need wood. Place a
Lumber Camp."; 3 "Shells come from visitors. Place a Snack Stall and they'll buy food."; 4 "Now put up a Tent. A
castaway moves in straight away to work and sail with you." (the first home on an island nobody lives on yet: a castaway
moves in the moment it is built, not at a turn's end, so the first trip has a party member); 5 "Build a Driftling
Nest, then tap the Tide Pool. Your villager comes along." (an arrow bobs over the island's lowest wild place); 6
"Tap the Tide Pool and tap Explore. In there your party fights on its own.", then the first fight (on the place's screen a note over
the footer: "Fights run on their own. Each fighter acts when the bar over its head fills. Tap Skills to step in."); 7
catching (after the first battle: "Want one? Wait till a wild one is hurt, then tap Snack, pick it and throw.", the
Snack button shining while one is hurt; against a guardian it says to try the next fight); 8 "You made a friend."
(once a driftling is befriended; OK ends the tips). On the island the same steps have their own words (and "tap Continue"
while an expedition waits). A place's card fills the party's slots with the strongest (level, then health) each
time it opens; a tap still swaps one out. A new island starts with `StartShells` (300) shells: the patch, the camp, the
stall, the tent and the nest of the tips cost 280.

> The request (2026-11-11): "also, please rewrite all text and dialogue to be less ai-like. research what are the
> telltale signs of ai writing and avoid them. note this from further on as well"

> The request (2026-11-11): "make a questline such that players are guided throughout the features of the game, such
> as assigning creatures to different work areas"

**The questline** (`Data/Quests`, `Logic/Quest`): once the tips are over, one quest at a time in a card down the left
under the chips (under the trip's card on a phone; it steps aside for an expedition and for a panel). The card has
the quest's icon and title, which of the twenty it is, what to do and where, and its progress with **Go**, which opens
the place it needs (the Driftlings or Villagers panel, Build mode on the right tab, the island's lowest wild place's card, the Index,
the Hatchery). When the goal is met, Go turns into **Claim** (shining) next to the reward; Claim pays it, says so, and
the next quest slides in. Each goal counts what the island has now, so one already met can be claimed at once. In
order: put a driftling to work; make room for a newcomer (2 villagers); give everyone a job (2 at work); grow more
food (a second farm or pier); lay a path (8 tiles); decorate (2 pieces); befriend three driftlings; use a skill; win ten fights; carry
more snacks (a bigger pouch); clear a wild place; grow your island (tier 2); build a boost; build the Training
Yard; clear two wild places; meet twelve kinds; grow the island again (tier 3); build a Hatchery; hatch an egg; clear
five wild places. The rewards are small (60 to 2,000 shells, some food and wood) next to what each step costs; the career's
player (§10) doesn't claim them, so the economy's bounds are measured without them.

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
menu's "Explore" and the Sun Beacon are names). Stat lines keep their "label: value" form.

## 10. Saves and the economy, checked

The save is version 9 (`Logic/Schema`): a version 8 save drops its boat and its sea chart (the islands it charted
stay counted as places cleared, their charm kept) and gets the wild places of every tier its island has reached; a
version 7 save keeps everything and starts the questline at its first quest
(any already met can be claimed straight away) with no skills counted yet; a version 6 save keeps everything and each of its driftlings rolls its
mutations once (from its kind and id: the same every load); a version 5 save keeps everything, its tips moved to the
new steps, and gets its sea seed, a level 1 boat and an empty chart; an older save (the game studio's) keeps the founder's look, the
settings and its start date and begins a fresh island with the tips. `tests/Career.luau` plays a sensible player through the same
rules (`Logic/*`) for three seeds and three hours; `tests/specs/Economy.spec.luau` holds the economy to these bounds:

- a villager within 3 minutes, a driftling friend within 15;
- the first wild place cleared within 15 minutes (the Tide Pool, about 6); the level 6 Bog within 60 (about 25 to
  55), the level 13 Cave within 100 (about 55 to 85); the town's places (level 20 and up) a long-term goal, past 100
  minutes (about 110 to 145); Harbor Town (tier 4) never before 100 minutes and no city (tier 5) within three hours.
  The career's player befriends kinds of driftling it has not befriended yet (or any while it has fewer than six
  friends: a friend gives no experience), and goes into the highest wild place its party looks strong enough for
  (asking for more after each defeat), else the highest cleared one it can take, else the lowest;
- the island's second tier within 45 minutes, the third within 90; at an hour, at least 8 villagers and 8 driftlings;
- nobody starves for long, and the stores stay finite.

## 11. Polish and animation

> The requests (2026-11-06, 2026-11-09): "make the it more polished and animated as well"; "Polish everything to the
> max. Add animations and details to everything, including the minigames"

> The request (2026-11-10): "lastly, polish the whole game as much as possible, and fix any bugs you encounter." In
> this pass: on a phone held sideways the battle frames the band the fighters stand in and draws it a scale bigger;
> the island only gains land as it grows; charm (paths add fractions) shows whole; a hatchling cheers on the island;
> the new buildings looked over in the `gallery` preview (the Crystal Fountain's water over its gold rim, stepped
> roofs on the Clock Tower and the Water Tower, a lighter brick road); a flaw's words ("-10% health", not "-11%")
> and a flaw never beside its own family's strength.

- **Buttons** lighten under the mouse, sink a pixel while pressed, click when used and buzz when disabled; panels and
  cards fade and rise in; notices slide down.
- **The HUD:** the stores count up and their chip flashes when they change, shells coming in rise from their chip
  ("+12"); the day chip's clock bar creeps along and its sun sets into a moon; the food chip blinks red while hungry;
  the expedition card's Continue pulses and gleams; a new tip bounces in; a newcomer's banner drops in with a fanfare
  and bits, and a new day's (every few hours) with a ding.
- **The island lives:** villagers walk to their work and back and do it, wander when resting; driftlings hop beside
  their buildings or round the nests; a newcomer is welcomed with a word and confetti.

  > The request (2026-11-11): "there are also no proper animations for creatures and villagers that are working on
  > something in the island"

  Work is a loop of real moves now (`CharacterModels` WORK, `DriftModels`' work moods), each building its own. A
  villager swings a hoe up and down into a field (a puff of soil at each stroke), picks fruit one hand then the
  other up on their toes in an orchard, holds a line out off a pier with a tug now and then (a splash), chops at the
  lumber camp with the axe back over the shoulder (wood chips fly), saws to and fro at a sawmill, hands things over
  the counter and waves at a stall or bakery (a glint of a coin), carries a tray and bows at a cafe, inn or hotel,
  taps with a hammer at a toolshed or water tower (sparks), throws punches at the Training Yard, and crouches to tend
  at a greenhouse, a hatchery, a windmill, a smokehouse or the beacon. A driftling pecks at the ground in the fields,
  dips its head for fish at a pier, leans in and pushes at the wood, waves and chatters at the shops, hops at the
  Training Yard, and naps at a nest (eyes shut, low and breathing slowly, for longer). Workers stand along the
  building's front, apart, turned three-quarters to the view so the work reads.
- **The sea lives:** the water rolls and the foam laps the shore (§8; the crests a light blue, as asked in §7), leaves
  sway and flags ripple in the wind, sailboats (the boats of §8, their flags fluttering) rock on the swell as they
  cross both ways, gulls cross now and then (from either side, at their own height, weaving and gliding, a
  different crossing each time); each island's campfire flickers and smokes. (No clouds' shadows: the
  player asked for the "random shadow that appears sometimes" gone.)
- **Coming home:** blinds close over the islet and open on the boat sailing home to the pier, the founder hopping
  off and the party cheering (§7).
- **Battles** play blow by blow (§7): wind-ups, dashes, strikes with hit-stop and shake, knock-backs, knock-outs,
  each skill its own move, the driftlings' limbs alive; the islands' driftlings blink, wag and step too.
- **Night falls** and the lamps light up (§8).
- **The islet's screen:** ink blinds open from the middle on the island's name; after the cutscene the boat brings
  the party ashore (back from the island they drop in from above in puffs of dust), the wild ones stand waiting in the next area as the party runs up (§7, the run on); each stage has its ambient life (gulls and a glinting chest on the beach, butterflies
  in the meadow, volcano smoke, falling snow, bubbles and a crab on the sea floor; a bird faces the way it flies and
  never flies the same loop twice: its round drifts and swells, it rises and dips, glides now and then, and some go
  one way round and some the other, as asked on 2026-11-11: "background birds fly backwards and only in one loop"); hits lunge, flash and spark,
  numbers float up, skills shout their names, heals and shells twinkle, a treat bursts into hearts, a friend leaves in
  confetti, a win cheers and throws confetti.
- **Sounds** (`Controllers/Audio`): every event plays a free Creator Store sound from Roblox's licensed libraries
  (ProSoundEffects, and APM Music's stingers), none of Random Bakery's, its pitch varied a little, repeats inside a
  short cooldown dropped.

  > The request (2026-11-10): "dont use sounds from the old versions, find and use new ones that fit the island theme"

  The interface is wood and bamboo: a temple-block tap for a click, a bamboo swish as a panel opens and closes, a low
  wooden knock for "no", wind chimes for a notice; shells coming in clack like pebbles (a handful for many); a bubble
  pops; pages turn; a shaker for a cheer or a skill; the conch's call for the boat and a rally. A won fight makes no
  sound of its own (the party's jump for joy and the small alert say it). Building is two quick hammer taps.

  > The requests (2026-11-10): "remove the victory sound whenever a fight finishes"; "the victory sound and wherever
  > it plays in such as a villager coming is too noisy, find one with a small short chime instead"; "the building
  > sound is also too, long, make it short"

  > The request (2026-11-12): "use different sounds for newcomer, victory and other sounds that use sounds made by
  > you or was default roblox sounds. use sounds from the free roblox library instead"

  The happy moments each have their own small, short sound from the library, measured for length and loudness before
  going in (no more one music-box note pitched up or down to stand in for the others): a door bell's ding-dong for a
  newcomer moving in; a bell tree's shimmer when a place is cleared; a lower bell-tree run as the island grows; a
  soft cluster of chimes when a driftling joins (befriended, or hatched); a few bright sparkle tones for a level up;
  one triangle ting for a reward (a quest claimed, home with the loot, the Expedition Complete card); a short drum
  roll as a guardian steps up; a music box winding up as an egg is laid; a sparkling sweep when an epic or legendary
  wild one turns up. Longer takes play only their first moment and fade out.

  Your founder's feet are the game's own too: Roblox's built-in footstep, jump and landing sounds are switched off
  (an empty `RbxCharacterSounds` script takes their place) and the founder steps softly on the lawn, crunches on the
  sand and knocks on the boards of the boardwalk, the jetty and the pier, a step a stride (quicker when running,
  several takes so no two steps in a row are the same), with a cloth flap for a jump and a soft thump on landing. The
  walk up to a wild place has its steps too.

  > The request (2026-11-10): "also, find new sounds from the roblox free library to use. try to find fitting ones"

  Battles: a swoosh on every dash (a heavier whoosh for a bash), a beefy punch on each blow (a heavier one for a bash
  or a knock-out), a snap of teeth when a driftling strikes, a thud when someone falls, an electric zap, a soft magic
  chime for a heal, a shield's clang for Shell Guard and Guard, a magic poof for Rally, a swoosh as a treat is thrown
  or the party flees. The islands and the sea: a wooden chest creaking open, a splash as the party hops off the boat
  into the shallows, a boat horn as the boat casts off and comes home, a hammer on wood when a building goes up,
  gulls squawking as a flock passes over, the surf on the sand always, crickets through the night and birds at dawn.
- **Music** (`Audio.music`): APM Music's library on the Creator Store, shuffled, one track after another, crossfaded,
  quiet: calm, drumless music that sits in the background. Soft acoustic island guitar by day (Campfire Stories,
  Tender Reflection, Home Camp), soft solo piano from the twilight (Gymnopedie No. 1, two Live Piano Stories), gentle
  and a little more open on an islet and while sailing (Quietness Sustained, Daydreaming On A Hammock), each evened out
  to the same loudness. Chosen by measuring the tracks (notes a second, the drums' share, the beat's strength, the
  loudness section by section), not by their names. The note in the HUD's corner switches it off and on.

  > The requests (2026-11-10): "also, find cozy background music"; "the background track is too upbeat and noisy.
  > find one that would fit well as background noise and is cozy"

## 12. Out of scope for this version

Trading between players, visiting with gifts, offline progress, purchases (no game passes or products:
`Config/Monetization.luau` holds only the sound and music ids), other languages (English only; every string goes through
`Locale/Lang.t`).
