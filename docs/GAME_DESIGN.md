# Driftling Isle: Game Design

> The request (2026-11-14, the latest): "could you also remove the transition that happens when clicking to hatch an
> egg? you can simply render the floating egg in a 2d background. also, make the player click to hatch the egg, each
> click revealing a mutation or a tier up upgrade if there is any, otherwise it just hatches"

So the hatch scene opens at once, with no blinds and nothing to wait for: the egg floats on its own in front of the
painted sky. Each tap takes the next thing waiting inside it, every step up in rarity first, then each mutation; with
nothing left, the next tap hatches it (§6.2). The islet the egg used to sit on is gone.

> The request (2026-11-14): "when i meant pastel color, i didnt mean desaturated it, i meant use more cozy colors.
> saturate the game back more. also, no need to use so much grass on the floor, it just looks noisy" (§2)

> The request (2026-11-14): "Can you use different eyes for each? Also, apply texture to each of them"

> The requests (2026-11-13): "The creatures look blocky and unrealistic. Look at the cakes in the bakery
> game to reference how detailed they should be"; "Also, could everything use a more pastelish colour pallette?"

> The request (2026-11-13): "There is no need to make things limited by squares and spheres, make
> everything more detailed with various shapes and textured objects. Also, like the bakery game, you can use 2d details
> to add to the athmosphere, such as grass, wood detail, birds and other details"

> The request (2026-11-13): "the egg hatching scene isnt detailed enough. add much much more detail to it, especially
> the egg. you are allowed to use 2d elements as well for the background"

> The request (2026-11-13): "make the entire game feel more cozy, such as the pallette and other details to emphasize
> it. also, remove these, the eggs should be buyable only after the player clicks on the tree or enters the tree menu.
> also, make a cutscene for eggs hatching and shows the creature hatched, listing the mutations it has as it hatches,
> with eggs having a chance to skip to the next rarity during the cutscene. the cutscenes become more glorious as the
> rarity of egg increases." (with a picture of the price tags over the eggs under the tree)

So the eggs carry no price tags any more: a tap on an egg, on the tree or on the HUD's Tree card opens the Tree panel,
and the eggs are bought there (§6). Hatch plays the **hatch scene** (§6.2): the egg up close in a painted sky,
perhaps turning rarer (`Tuning.EggUp`), cracking, and what hatched with its mutations listed beside it, grander the
rarer it is. The light of day is a little warmer, and the greens and the sand with it (§2). The sky behind the egg is
drawn in 2D, with birds and shooting stars crossing it. (The islet the egg sat on then, its nest and props, went on
2026-11-14, the request at the top.)

> The request (2026-11-13): "could you bevel these to make them smoother, with rounded corners? for the trees, you
> should also make the trunk connected smoothly as well without the stepped boxes" (with pictures of the stepped coast
> and a palm's stepped trunk)

So the coast's layers are bevelled into diagonals and every stepped trunk is one smooth curve (§8).

> The request (2026-11-13): "make it much cheaper to buy work and hut buildings"

So everything on the Work tab (farms, lumber, shops, boosts) and the Huts tab (the huts and the Hatchery) costs about
a third of what it did (`Tuning.BuildingPrice` 0.3, to two figures: a Lumber Camp 21 wood, a Veggie Patch 12, a
Driftling Hut 17, a Snack Stall 30, a Sawmill 190, a Hatchery 1,200, a Driftling Palace 18,000). Decor, paths, fences
and water keep their prices, and growing the island costs what it did.

> The request (2026-11-13): "remove the docks area, it should just be an island. players can swim around
> in water to reach other player islands."

So the boardwalk, the jetty, the path down to it, the pier with its moored boat and the mailbox are gone. Each island
stands alone in the sea, and the land where the path ran is the island's to build on. Nothing holds a founder on the
beach any more: they walk off the sand into the sea and swim (§8), head and shoulders above the water, a ring of foam
round them, crawling when they move and treading water when they stop, slower than on land and with no jump. They swim
over to anyone's island and climb out on its beach. The island's sign moved to its south beach and still carries its
name; a founder now appears on the plaza, and Home brings them back there.

> The request (2026-11-13): "make it such that each creature can work at any place, and is no longer
> restricted."

So any driftling can work at any farm, fishing pier, lumber camp or shop. Its **knack** stays as what it's best at:
its passive usually helps at buildings of its knack ("+15% at farms"), so it works a little faster there, and a new
driftling goes to a free place of its knack first, else to the free place where it works fastest, rather than
resting. The Driftlings panel's Work picker lists every workplace on the island with how fast this driftling works at
each (x1.1, x1.0), the fastest first (§6).

> The request (2026-11-13): "add a search button for the building ui."

So the build tray has a search button now: a magnifier just before the search box (§4.5). Tapping it puts the cursor
in the box, and it lights up while a search is on.

> The request (2026-11-13): "Make much, much more building options, like paths and fences. Polish the
> build ui more, just like the bakery game, and reference bloxburg. Also, add effects and polish when putting down
> decor and other amenities. There should be enough paths, fences and other detail to make a lot of vastly different
> themed islands. Also, add the ability to add water to make rivers. Make more island progression and allow the
> player to expand their land even more."

So Build mode is a catalog now, like the bakery's decor box: 245 pieces on eight tabs (Work, Huts, Paths, Fences,
Water, Nature, Decor and Fun), each tab split into rows, each card a small picture of the piece drawn from its own
model. Paths, water and fences are drawn in a line or a box. Water makes rivers and ponds, with bridges over them and
lily pads on them. Decor comes in 13 themes, enough for a beach island and a frozen one that look nothing alike. A
piece put down drops in and lands in a puff of dust with bits of what it's made of flying up. The island grows through
ten tiers now, four longer islands past Sunspire Capital, and each brings more room and better eggs (§4).

> Before it, the same day: "Also, color each egg differently with different effects to allow players to distinguish
> easily between egg rarities"

Each rarity's egg has its own colour and marks, and the rarer ones their own lights: a common egg is cream with brown
freckles, an uncommon one green with a white zigzag band, a rare one sky blue with glowing stars, an epic one purple
with glowing spots and two motes of light circling it, and a legendary one gold with a beam of light standing up out
of it (§6).

> Earlier that day: "never mind, bring back the tree of life and remove the converyer belt system. it now spawns eggs
> around it that the player can choose to hatch for some shells. it spawns in 5 eggs around it, which refreshes every
> few minutes to spawn in another 5 eggs, replacing any existing eggs that were not taken. expanding the island
> increases the quality of eggs spawned and amount of eggs spawned"

So the Tree of Life is back on every island and the tide is gone. Every three minutes the tree lays a lot of eggs
round its roots: five on a new island, one more with each tier up to ten on the capital and the islands past it. The
eggs nobody hatched go when the new lot comes. Each egg's colour shows its rarity and its price in shells hangs over
it; tap it and pay, and what hatches moves into a hut and goes to work (§6). A bigger island lays more eggs and rarer
ones, and growing the island lays the extra eggs at once. A save from the tide gets its tree back, with a first lot
laid as the player arrives (§10).

> And after it: "Also, make a limit of huts per island expansion level"

Each tier allows so many huts (4 on a new island, two more a tier, 22 on the biggest). Past that, more room for
driftlings comes from growing the island or from a bigger hut in a small one's place (§4).

> Before them, the same day: "this system of getting creatures might not be working. can you come up with ideas that
> allow the player to get creatures without much complexity?", then "can you look at other popular roblox games and
> suggest a way?", and to the suggestion that came back (driftlings drift in on the tide, the way pets ride a conveyor
> past the player in the popular Roblox pet games): "good idea, use the drifting in idea. you can remove the tree of
> life, there should now be a steady stream of driftlings, with rarities that players can pick up"; then "make them
> float by just like a conveyer belt instead of drifting towards the island and stopping, with one every second"

For a few hours driftlings floated past the island on the tide, each on a raft with its price over it, at the end one
a second like a conveyor belt (this file's history has it, up to commit 9d34e42). What stayed: shells pay for new
driftlings, a rarer one costs more, and a full set of huts takes a better one in a swap for a weak one. Harbor Town
went up to 150,000 wood with the tide and stayed there until the ten tiers brought it down to 60,000 (§4.4, §10). The
tree came back without its pen, its Speed and Luck upgrades and Equip best.

> With the tide (2026-11-13): "also, make wood the main resource for building/expanding and shells the main resource
> of getting new driftlings. remove food as a resource"

That still holds: wood builds everything and grows the island, shells hatch the tree's eggs (§3). Food is gone. A save
from before keeps its huts' driftlings and gets the old pen's back as shells (§10).

> The request (2026-11-12, later): "remove villagers, only creatures should be enough"

So the villagers are gone and the driftlings do all the work. The homes went with them (Tent to Manor; an old save
gets each one's whole price back, §10). A building with nobody at it still works a little (`IdleOutput`, 0.3 of its
rate) so a new island gets going; each driftling at it adds more.

> The request (2026-11-12): "scrap the entire cave, fighting, level, skill and expedition system. instead, players
> start with a tree of life: it creates a creature every few seconds to be put into a pen. the pen will automatically
> send the best creatures into huts if there is space, and the player can also select which creatures are sent to
> which hut. players can upgrade the incubator's luck and speed. creatures work faster based on their rarity and can
> also have mutations like before"

Asked what the huts are, the answer was **"Nests become huts"**: the Nests tab's buildings are the huts, and a
driftling in a hut helps at a farm, pier, lumber camp or shop (any of them since 2026-11-13, faster at its knack's),
faster the rarer it is. Asked about
breeding: **"Keep it"**: the Hatchery stays, without levels (§6.1). The huts, the rarities' work and the mutations
are still the game's, and so is the tree, laying eggs now (above). Its pen, its upgrades and Equip best went with the
tide on 2026-11-13; before that the tree had grown bigger and grander, the pen had lost its room limit and was only a
list, and Equip best filled the huts with the best driftlings.

> The request (2026-11-10): "scrap this idea. could you make replicate beasty bay from kariosoft instead? still use the
> test repo as a reference"

We do not copy another studio's game (its name, creatures, islands, story or art). Asked which way to go, the answers
were: **an original game in the same genre** ("Yes, original game"); its loop **"Island building + farming, Creature
taming, Expeditions + battles, Villagers moving in"** (the expeditions and battles went on 2026-11-12, above); its
world **"Shared sea of islands"**. Earlier requests still hold where they apply: the first ("reference game dev story
from kariosoft and make a simplified version of it in gamedevtest. dont touch the "test" repo at all, only use it for
reference"), the pixel art rules (§2) and the polish requests (§11). The game studio of the earlier versions is gone
(§10: an old save starts a fresh island).

Driftling Isle is a small island-village management game for Roblox. You wash up on a little island with a campfire on
its grass and a Tree of Life behind the fire, the sea all round. Every few minutes the tree lays **eggs**
round its roots, each coloured and marked by its rarity with its price in shells over it: mostly cream commons, now and
then a blue rare one with glowing stars. Hatch one and a **driftling** comes out. Build a Lumber Camp for wood, farms
and shops for shells, and huts for the driftlings you hatch; each one works wherever you send it, a little faster at
the kind of building it's good at, more the rarer it is. Paths, fences, rivers and decor in 13 themes give it a look of its own. The driftlings do all the work: there are
no villagers. Wood pays for every building and for growing the island, shells pay for eggs, and once the huts are full a
better hatchling can take a weak one's place. The islands of everyone on the server sit side by side on a shared sea, and
you swim from one to the next. The look, the build system and the file formats come from our own Random Bakery (`Downvote/test`): the
2:1 pixel-art isometric diorama seen through the pixel filter, the pixel font, Rojo with strict Luau, a server that
decides everything, pure Data/Logic modules with specs, and the fake-engine simulator and preview tools.

## 1. The loop in one paragraph

Build a Lumber Camp for wood, a Veggie Patch that sells what it grows for shells, and a Driftling Hut; each building
works a little on its own. Every turn (Tuning.TurnSeconds while you play) the island makes its wood and shells. All the
while the Tree of Life lays a new lot of eggs every three minutes, five on a new island, and the ones left from the last
lot go. Tap the tree (or an egg, or the Tree card) to see them and hatch one there: out comes a driftling of the
egg's rarity, now and then of a rarer one, with mutations of its own, shown off in a short hatch scene. It
moves into a hut and takes a place at a farm, pier, lumber camp or shop (its knack's first), adding to what it makes, a
legendary seven times what a common one adds. Rarer eggs cost more, and on a bigger island every egg costs more, the
tree lays more of them and the rare ones come more often. When every hut is full, the new one takes the place of one you
pick, and that one is sold. Spend wood on more buildings, huts (so many a tier), and on decor, paths, fences and water
(charm brings the visitors who buy at the shops), and expand the island for bigger buildings, more huts, more eggs and
new kinds of driftling, and past the capital for more room and better eggs. Nothing happens while you are away (no
offline progress).

## 2. Look and feel

- **World:** one island per player in a row on the open sea (no docks: you swim between them), each of its own shape with a campfire at
  its heart, its grass, a sand beach and a shore stepping down into a moving sea (§8), seen from the Random Bakery
  camera: orthographic, yaw 45°, pitch 30°, the 2:1 pixel-art "isometric" grid, always centred on your founder. Everything is built from parts in code (no
  meshes, decals or uploaded images).
- **Pixel filter:** the same pipeline as Random Bakery's: a raycast G-buffer baked progressively, three toon bands
  from one sun, sun shadows, a palette LUT, a 1 px ink outline, and the characters drawn analytically every tick on
  top with the same projection. One pixel size K for the world, the UI and the text. Shadows keep the grid: the sun's
  ray is cast once for each 2x2 pixels, and every pixel on a shadow's edge then casts its own, so a shadow's edge
  steps one pixel at a time (the bug report, 2026-11-10: "some shadows appear to be blocky and have mixels, not
  respecting the pixel grid").
- **Cozy light** (the request of 2026-11-13 at the top): the day's light is a little warm, like a late summer
  afternoon (`Palette.modes.day` 1.03, 1, 0.95: the same warmth the moving things always had), the grass and leaves a
  touch more golden and the sand a touch warmer. Dusk, twilight and night keep their grades (§8). The hatch scene's
  skies (§6.2) are the warmest of all: a sunset, a golden afternoon, moonlit nights.
- **Cozy colours** (the request of 2026-11-13, "could everything use a more pastelish colour pallette?", then of
  2026-11-14: "when i meant pastel color, i didnt mean desaturated it, i meant use more cozy colors. saturate the game
  back more"): the colours are rich and warm, a little more saturated than the cozy pass of 2026-11-13 left them (the
  colourful hues of `Data/Palette` 15% fuller, greys, ink and white as they were): sunny greens, warm sand and wood,
  a clear aqua sea, bright berry reds and butter yellows. The interface, the sprites, the hatch scene's skies and the
  loading card keep their own warm colours.
- **Surfaces** (the request of 2026-11-13, "textured objects" and "wood detail"): the filter gives the world's materials a texture as it bakes, the way Random Bakery gives its wood a
  grain: 1 px marks in a darker or lighter tone of the surface's own colour, few and quiet, so a lawn reads as grass
  and a plank as wood up close while the island still looks calm from afar. Grass, moss and leaves get a few little blades
(about one 6 x 4 px cell in five, and the lawn's 2D tufts one cell in twenty: "no need to use so much grass on the
floor, it just looks noisy", 2026-11-14),
  tufts and flecks of light on the faces that look up; sand gets specks and grains; stone and paving get specks and
  now and then a short crack; wood gets broken grain lines along each plank, post and log; straw gets rows of short
  strokes like thatch on roofs and the sides of bales; brick gets courses and joints on the sides of walls; metal a
  streak of light where the sun hits it; window glass a darker pane with two streaks of reflection. The marks belong
  to the place on the island, not to the screen, so they never crawl when the view moves, and two marks never touch
  into a blob. A thing too small to carry its pattern stays plain. In a shadow the marks fade into the shade with the
  rest of the face. The water keeps its own moving waves, and what moves (the driftlings, the eggs, the founders)
  stays plain: a mark would slide over it as it walks. None of it costs a ray.
- **The founders** (yours and your neighbours') and the **visitors** are little chibis: shorts over bare shins, shoes
  on light soles, a shirt with a collar, buttons and a belt with a buckle, sleeves over bare forearms and fists, ears,
  brows, a mouth and a glint in each eye; knees and elbows bend, and the face changes. **Driftlings** are small 3D
  creatures of our own design walking to their work and doing it, each with its own details (moss and stubby arms on
  the pebble, bubbles on the crab, whiskers and a sprout on the bun, wing bones on the bat...) and limbs that move
  (§7). The driftlings live on the island, and the tree's eggs lie on the lawn round its roots (§6).
- **Interface:** pixel-art plates with stepped corners and a 1 px ink outline following them, the pixel font; the
  panels, cards, notices, the tip and the build tray cast a 2 px drop shadow; buttons are bevelled (a lit top row, a
  shaded lip) and sink a pixel when pressed; each panel has a title band with its icon, and each menu button its
  icon. Every driftling has a 32x32 portrait, every piece in the build catalog a 24x24 picture and the island's
  things 11x11 icons, drawn by the rules below.

  > The request (2026-11-12): "instead of character sprites for the creatures, can you take their pixellated models
  > in a 3/4 angle, and polish them to follow pixel art rules if required?"

  > And after the first try: "most of those sprites look unreadable. try to tweak them so they look more readable"

  > Then: "the eyes are too big in the sprites and the eyes all look the same"

  So a portrait is the driftling itself: its 3D model drawn by the game's own picture path (the palette, the toon
  bands, the shadows and the ink outline the island draws it with), standing at rest with its eyes open, turned 30
  degrees past the world's view so its face turns toward us and its side still shows, fitted to 32 x 32. The first
  try, the model as the island shows it at 24 x 24, came out as small muddy shapes: a face was two or three pixels,
  black crease lines ran all through each creature, dark bodies sank into the outline and the eyes' shines came out
  as grey squares. So a portrait has its own proportions, the way portrait art exaggerates: the head and everything
  on it 1.45 times bigger about the neck, and the camera at 15 degrees instead of the world's 30, so the face shows
  more and the top of the head less. The eyes grow with the head and only a little more (1.1), and each body plan has
  its own: a stone and a mole squint (flat, no glint), crabs, snails, birds and turtles have small beads, buns and
  pups taller round ones, seals and jellies round ones, each with a small glint that glows white. Lizards, wyrms and
  drakes have a coloured eye with a slit pupil, owls a big coloured one with a round pupil, frogs a bar pupil, yetis
  a pale icy one, bats and moths a red or coloured eye with no pupil, and a sprite's eyes glow. The colour is the
  species' own accent when it shows against the body (a dull or pale accent, or one too near the body's colour, falls
  back to the plan's own), so two drakes don't share a stare. Then it is
  tidied to the rules below: no half see-through pixels, the outline made again 1 px wide on the four sides only
  (cut corners, no doubled pixels at a turn), lone pixels sticking out and one-pixel notches gone, the bands' dither
  settled where one pixel stands alone in another tone, the creases inside 1 px and a step darker than the colour
  beside them instead of black (selective outlining), a body too dark to read against the outline lifted (never the
  eyes), a little more colour so it doesn't go grey on the brown panels, tones closer than a step made one, the
  curves softened a step inside the outline. A long body (a wyrm, a drake with its wings out) is fitted by its widest
  side, so it sits smaller in the square. The rows, cards and slots that show one grew to fit it. The hand-drawn
  16x16 portraits of the request below are gone.

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
- **The founder:** you walk your island and swim the sea as a chibi founder (§9).

**The pixel art rules** (they hold for every sprite, icon, scene and effect, now and from now on):

> The request (2026-11-09): "for pixel art, always dont use mixels. use pixel art techniques such as anti-aliasing,
> avoiding jaggies, and avoiding mixels, and use a 1 pixel outline. respect the pixel art grid. polish the minigames
> much much more"

- **No mixels.** One art pixel is one UI px is one K-sized block on the screen: nothing is ever drawn scaled up
  (no 2x or 3x sprites). A bigger or smaller thing is its own sprite drawn at its own size: a driftling's portrait is
  32x32 (drawn from its model at that size, never shrunk or blown up), a build catalog picture 24x24 (the piece's
  model seen as the island shows it, drawn at that size and tidied the portraits' way), a small icon 11x11. The world and the driftlings are 3D and drawn by the pixel filter, so they keep the same
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
- **Calm and readable:** a material reads first from its colour and silhouette. The world's surface texture (above) is
  sparse 1 px marks in the colour's own tones, never a grain or speckle noise, and the sprites stay clean. Every
  sprite is first a silhouette that tells what it is on its own: each driftling its own outline (the crab's raised
  pincers, the bun's long ears, the pup's floppy ears and flame, the fox's tall ears and pointed chin, the mole's
  claws, the owl's tufts and round eyes, the jelly's tentacles...), each icon a plain object (an apple, a log, a
  scallop shell, a house, an egg in a nest, a dumbbell, a flower, a sack, a paw print, a campfire, a hat on the
  visitor, a round tree for the Tree of Life).

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
  something makes its rate a turn times what its driftlings put in (the island card shows it a minute: "+57/min"):
  `IdleOutput` (0.3) with nobody at it, else the sum of its driftlings' work (each `PalWork`, 0.6, times its rarity's
  `RarityWork` and its shares: §6), more again at Lv 2 and 3 (`UpgradeMult`: only a building upgraded in an older
  save is above Lv 1, since upgrades were taken out, §4). Nothing eats.
- **Two stores** (the request of 2026-11-13 at the top: "make wood the main resource for building/expanding and
  shells the main resource of getting new driftlings. remove food as a resource"). **Wood** comes from the wood
  buildings and pays for every piece, path and replacement and for growing the island (§4). **Shells** come from the
  farms, which sell what they grow or catch, and the shops, which sell to the visitors; they pay for the tree's
  eggs (§6) and the Hatchery's feasts (§6.1). With food gone the buildings' rates moved: the Lumber Camp makes
  30 wood a turn (it made 6), the other wood buildings three times what they made, and each farm sells three times
  what it grew in food (a Veggie Patch 36 shells a turn). The shops kept their rates and no longer use anything up.
  Hunger, eating and the food chip went with the food.
- **A day** is `DaySeconds` (4 hours) of the sea's clock (`WorldClock`: one time of day for every island on the
  server, carried on across visits: it follows the real clock): the HUD shows the day count and its clock (a sun, a
  moon for the evening); day and night follow it (§8); each day's end while you play counts a day (a banner).
- **Shops** sell to the visitors: their rate times visitors / `ShopVisitors` (at most double). **Visitors** a turn:
  1 + charm / `VisitorCharm`, at most `VisitorsMax`.
- **Charm:** every piece's charm, and one for each driftling living in a hut plus its charm share (Cute and its
  family; `Island.charm`). Charm brings visitors; nobody moves in any more.
- The stores reach the client every second; a new day brings its banner ("Day 12").

## 4. Building (`Data/Buildings`, `Logic/Plot`, Build mode)

> From the request at the top (2026-11-13): "Make much, much more building options, like paths and fences. ... There
> should be enough paths, fences and other detail to make a lot of vastly different themed islands."

**The catalog** (`Data/Buildings`): 245 pieces, each opening at an island tier (1 .. 10; a locked card says "Lv7"),
and the Tree of Life, which every island has and nobody buys (§6). Build mode lists them on eight tabs, and each tab's
pieces in rows (a piece's `tab` and `sub`), so an island can keep to one look:

| Tab | Its rows | Pieces |
|---|---|---|
| **Work** | Farms 7, Wood 5, Shops 6, Boosts 7 | 25 |
| **Huts** | the six huts and the Hatchery | 7 |
| **Paths** | (one row) | 22 |
| **Fences** | (one row) | 17 |
| **Water** | Water 7 (the tiles), Bridges 7, On the water 8 | 22 |
| **Nature** | Trees 11, Plants 17, Rocks 8 | 36 |
| **Decor** | 13 themes: Beach 7, Garden 9, Farm 8, Harbour 8, Town 8, Jungle 5, Frost 5, Autumn 5, Desert 5, Fairy 5, Zen 6, Volcano 4, Grand 9 | 84 |
| **Fun** | Seats 7, Lights 8, Play 7, Treats 5, Fountains 5 | 32 |

The buildings that work or house (the tier each opens at in brackets):

| Kind | Pieces |
|---|---|
| **farms** | Veggie Patch, Fishing Pier (1), Fruit Orchard (2), Greenhouse (3), Rice Terrace (4), Kelp Farm (5), Sky Garden (6) |
| **wood** | Lumber Camp (1), Sawmill (2), Timber Works (3), Bamboo Grove (4), Grand Mill (5) |
| **shops** | Snack Stall (1), Beach Cafe (2), Seaside Inn (3), Bakery (4), Grand Bazaar (5), Grand Hotel (6) |
| **huts** (room, comfort: §6) | Driftling Hut 2, Cozy Burrow 4 +5% (2), Driftling Den 5 +8% (3), Treetop Roost 6 +12% (4), Spring Grotto 8 +18% (5), Driftling Palace 12 +25% (6) |
| **boosts** | Tool Shed (wood +10%), Windmill (farms +10%), Smokehouse (fishing +10%) (2), Market Hall (shops +12%) (3), Water Tower (all +6%) (4), Town Hall (all +10%) (5), Sun Beacon (all +15%) (6) |
| the **Hatchery** (3, §6.1) | |

The rest are there for charm (§3) and for the look of the place:

| Row | Pieces |
|---|---|
| Paths (2 x 2 tiles) | Dirt Path, Sand Trail, Gravel Path, Shell Path, Plank Walk (1); Stone Path, Flagstones, Cobblestones, Mossy Stones, Leaf Litter, Flower Meadow (2); Raked Gravel, Snowy Path, Sandstone Tiles, Terracotta Tiles, Checker Tiles (3); Brick Road (4); Crystal Path, Basalt Steps, Marble Walk (5); Gilded Walk (7); Starlit Path (8) |
| Fences (2-stud lengths, §4.2) | Rope Fence, Picket Fence, Split Rail (1); Bamboo Fence, Driftwood Fence, Woven Fence, Hedgerow, Garden Gate (2); Low Stone Wall, Log Palisade (3); Iron Railing, Lantern Rope (4); Brick Wall, Adobe Wall (5); Snowbank, Shell Wall (6); Crystal Fence (8) |
| Water (2 x 2 tiles, §4.3) | Stream (1); Deep River, Lily Pond (2); Swamp Water (3); Lagoon (4); Hot Spring (5); Frozen Pond (6) |
| Bridges (over water) | Plank Bridge (1); Little Dock (2); Rope Bridge, Stone Bridge (3); Waterwheel (4); Canal Bridge (5); Moon Bridge (6) |
| On the water | Lily Pads, Reeds, Stepping Stones (1); Duck Decoy, Rowboat (2); Lotus Flowers, Little Waterfall (3); Floating Lanterns (4) |
| Trees | Pine Tree, Oak Tree, Palm Tree (1); Bare Tree, Birch Tree (2); Cherry Blossom, Maple Tree, Jungle Tree (3); Willow (4); Great Oak (5); Snowy Pine (6) |
| Plants | Fern, Tall Grass, Round Bush, Berry Bush, Tulip Row, Flower Bed (1); Mushrooms, Rose Bush, Sunflowers, Lavender, Pumpkin Patch (2); Cactus, Big Leaf Plant (3); Tall Cactus, Giant Mushroom, Bonsai (4); Glow Mushrooms (6) |
| Rocks | Boulder, Rock Pile (1); Mossy Rock (2); Desert Rock (3); Crystal Cluster (5); Snowy Rock, Basalt Columns (6); Lava Rock (7) |
| Beach | Coconut Pile, Sandcastle, Deck Chair, Beach Umbrella, Shell Pile (1); Surfboard Rack (2); Lifeguard Chair (3) |
| Garden | Garden Gnome, Wheelbarrow, Birdbath (1); Beehive, Rose Trellis, Flower Arch (2); Sundial, Gazebo (3); Topiary (4) |
| Farm | Milk Churns, Hay Bale, Scarecrow, Barrel Stack (1); Haystack, Water Trough, Farm Cart, Stone Well (2) |
| Harbour | Mooring Post, Buoy, Crate Stack (1); Lobster Pots, Net Rack, Anchor (2); Ship's Wheel, Lighthouse (3) |
| Town | Bin, Signpost (1); Planter Box, Post Box, Notice Board (2); Newsstand, Bandstand, Clock Tower (4) |
| Jungle | Tiki Mask, Totem Pole (2); Parrot Perch, Vine Arch (3); Mossy Idol (4) |
| Frost | Snowman (2); Sled, Ice Lantern, Ice Sculpture, Igloo (6) |
| Autumn | Leaf Pile, Harvest Basket, Pumpkin Stack (2); Corn Stalks, Carved Pumpkin (3) |
| Desert | Water Jars, Clay Pots (3); Market Rug, Striped Tent, Sandstone Arch (5) |
| Fairy | Fairy Lantern, Mushroom Ring (5); Moonstone, Wishing Well (6); Crystal Arch (8) |
| Zen | Rock Garden (1); Bamboo Screen, Wind Chimes, Stone Lantern (4); Water Basin (5); Lantern Tower (7) |
| Volcano | Fire Basin, Steam Vent (7); Obsidian Spire (8); Lava Pool (9) |
| Grand | Guardian Statue (3); Grand Arch, Observatory (5); Sun Spire, Founder Monument (6); Golden Driftling (7); Sky Bell Tower (8); Crystal Spire (9); Rainbow Arch (10) |
| Seats | Log Seats, Bench, Hammock (1); Park Bench, Picnic Table (2); Stone Bench, Porch Swing (3) |
| Lights | Garden Lights, Tiki Torch, Fire Pit (1); Candles, Paper Lanterns, Lamp Post (2); String Lights (3); Street Lamp (4) |
| Play | Sandbox (1); Seesaw, Swing Set (2); Slide (3); Trampoline, Merry-Go-Round (4); Climbing Frame (5) |
| Treats | Grill, Lemonade Stand (2); Ice Cream Cart (3); Telescope, Tiki Bar (4) |
| Fountains | Drinking Fountain, Little Fountain, Fountain (2); Koi Pond (5); Crystal Fountain (6) |

A tree's trunk is never a stack of steps (2026-11-13, §8): the Palm Tree's is a smooth curve of round rings, the Bare
Tree's and the Bonsai's crooked trunks are round segments joined by balls at their bends, and the Great Oak's trunk
is one column from the ground instead of a wide drum under a narrower one.

The old decor went into these rows (the Palm Tree to Trees, the Bench to Seats, the Lighthouse to Harbour, the Canal
Bridge to Bridges and so on); the old one-piece Picket Fence and Hedge became drawn fences (Picket Fence, Hedgerow; a
save's old ones come up with their price back, §10). Every piece also has a **feel** (`feel`: wood, stone, plant,
water, metal, magic, sand, snow, cloth or fire), which picks what flies up and what it sounds like when it goes down
(§4.5).

Each is paid in wood when placed (since 2026-11-13 its old price in shells and wood added up and rounded; later that
day the Work and Huts tabs' buildings went to `Tuning.BuildingPrice` (0.3) of that, to two figures: a Lumber Camp 21,
a Veggie Patch 12, a Driftling Hut 17, a Snack Stall 30; the other pieces from 4 wood for a tile of Sand Trail to
1,500,000 for the Rainbow Arch), on whole studs of the island's grass (a stud or more in from the sand), turned a
quarter at a time, off the campfire's plaza, off every other piece and off water unless it
is made to go over or on it (§4.3). Paths are the one thing decor may share a spot with (a paved yard, below).

**The limits.** Each sort of thing has its own limit, and each grows with the island (§4.4 has them by tier): the
pieces (`PlotPieces`: 36 on a new island, 540 on Driftling Haven), the path and water tiles together (`PathPieces`: 80
to 1,200), the fence lengths (`FencePieces`: 40 to 600) and, among the pieces, the huts (below). The Tree of Life
counts toward none of them. At a limit the server refuses one more (`full`) and nothing is paid, while the other
limits still take theirs. Build mode's count shows the tab's own: the pieces on Work, Nature, Decor and Fun, the tiles
on Paths and Water, the lengths on Fences and the huts on Huts, orange when full.

> The request (2026-11-13): "Also, make a limit of huts per island expansion level"

**The huts' limit** (`HutLimit`, `Plot.hutLimit`): an island may have 4 huts, then two more each tier up to 22 on
Driftling Haven. At the limit the Huts tab's cards are greyed with "No room", and placing one more is refused ("No room
for another hut here. Grow the island, or replace a hut with a bigger one."). Replace still works there: a bigger hut
can take a small one's place (§4.1). The Huts tab's count shows the huts against the limit ("6/6"). A save with more
huts than its tier allows keeps them all, and it can't build another until it is under the limit. With the best hut of
each tier in every place, the most driftlings an island can house is 8 on Castaway Cay (four Driftling Huts), then 24
(six Cozy Burrows), 40 (eight Driftling Dens), 60 (ten Treetop Roosts), 96 (twelve Spring Grottoes) and 168 (fourteen
Driftling Palaces) on the capital, and 192, 216, 240 and 264 (sixteen to twenty-two Palaces) on the islands past it.

> The request (2026-11-11): "paths should be able to be drawn or made in a box like the original interface in the
> bakery game. also, fights should be shown in the same view as pokemon or beasty bay, in an angle like the image
> shown, and the party will also walk forward in the view like the image shown. polish the battle experience and
> interface much much more"

**Drawing.** Paths, water and fences are drawn, the way the bakery's floors were. Picking one opens the draw bar
instead of the usual placing: **Line** (drag and the tiles follow the finger, filling the gaps between cells; a fence
follows the grid lines), **Box** (drag a box and every free cell inside it is filled, or a fence runs all the way round
it), **Erase** (drag over them to take them up, half their price back), **Look around** (drag the view without
drawing) and **Cancel**. While dragging, each 2 x 2 cell (or each length of fence) shows as a glowing plate: cyan where
one goes down, yellow where one of another look is swapped for it, orange where one comes up, red where it can't (off
the grass, on a piece, past the limit or the wood); the bar says how many and what they cost ("12 tiles, 180 wood").
Letting go lays them in one go (`plot.paint` or `plot.fence`, up to `PAINT_MAX` (40) a request: a long stroke goes in
a few) or takes them up (`plot.unpaint`, `plot.unfence`). A cell that can't take one is skipped, never refused as a
whole; running out of wood or room stops where it runs out. Tiles lie on the even studs (a tile's corner at even x and
z), so they always meet edge to edge, and one moved in Build mode snaps to them. Drawing another look over a path, a
water tile or a fence swaps it where it lies: half the old one's price back, the new one's paid.

**A paved yard** (`Plot.onPaths`): a piece from the Decor, Nature or Fun tab may stand on path tiles, and paths may be
drawn under one that stands already, so a themed yard can be paved in its own ground: a snowman on snow, a deck chair
on sand, a stone lantern on raked gravel. Huts, workplaces, the Tree of Life, fences and the pieces for the water never
stand on paths, and a path is never drawn under them. Taking the paving up leaves the decor where it stands, and two
pieces still never share a spot. Water keeps its own rules (§4.3).

### 4.1 The town and the city

> The request (2026-11-10): "make much much more progression, allowing the player to build much more decorations,
> generators/work areas, better houses for villagers and creatures which improve their stats and work productivity,
> paths and other details, that unlock more as the island is expanded. increase the progression to the point where a
> big island that is well decorated should look like a well developed city. give players the ability to
> replace/upgrade buildings as well, including homes of creatures and villagers"

- **The tiers** (`TierCost`, in wood): Castaway Cay, Palm Isle (600 wood), Grand Isle (9,000), then **Harbor Town**
  (60,000), **Coral City** (160,000) and **Sunspire Capital** (380,000), and since 2026-11-13 four longer islands past
  the capital (§4.4), each coming about when the island before it is built up. (They were paid in shells and wood
  until 2026-11-13; the first two were made cheaper on 2026-11-12: "expanding island costs too much, make them cheaper
  early on"; Harbor Town went from 130,000 to 150,000 with the conveyor tide and down to 60,000 with the ten tiers,
  §10.) The island grows north each time (its south shore stays where it is), to twice tier 3's grass at the capital and
  nearly four times at Driftling Haven, and only ever gains land (each tier's shape joined to the smaller ones':
  nothing built near an old shore has to move); more driftlings live there in more and bigger huts, the tree lays more
  eggs and better ones, and new kinds hatch up to the capital (§6). (The homes for villagers this request asked for
  went with the villagers on 2026-11-12.)
- **Comfort** (huts): a driftling hatched goes to the comfiest hut with room. A driftling's comfort (its hut's, plus
  4% / 8% at a level 2 / 3 hut kept from an older save) makes it work that much more (`Island.palBoost`: 1 plus its
  share plus its comfort). The Driftlings panel shows each one's hut.
- **Boost buildings**: every building of a knack makes more (`Island.boosts`); each kind of boost building counts
  once however many stand, the "all" ones count at every knack, and the boosts at one knack stop at `BoostMax` (60%).
- **Paths** in 22 looks (§4), drawn in lines and boxes, apart from the piece limit: roads through a town (the dearer
  ones bring a little charm, a quarter of a point a tile up to two on the Gilded Walk and the Starlit Path).
- **No upgrades** (taken out 2026-11-11: "remove the ability to upgrade buildings"). A better building is a
  **Replace** away, and a level from an older save is kept and still counts.
- **Replace**: a standing piece picked up shows **Replace**: the tray lists what it can become at the tier, each with
  its picture, its room or charm and its price less half the old one's (`Plot.replaceCost`). A building's choices are
  the others of its kind (room for huts); a piece of decor's are the others in its own row, a tree for a tree and a
  bench for a bench (`Plot.replacements`). A tap swaps it where it stands (the new footprint must fit there; it drops
  in with sparkle tones): its driftlings stay (a smaller hut keeps as many as it has room for, and the rest are left
  with no hut, §6), its level starts again. A patch becomes an orchard, a hut a palace (at the huts' limit, the way to
  more room). A path, water tile or fence has no Replace: draw the new look over it (§4).
- A big island well built reads as a city: roads in a grid with street lamps, a town hall and a clock tower, markets
  and a grand hotel, dens and roosts, parks with topiaries and fountains (the `city` preview). Built in one theme it
  reads as that place instead: a beach of sand trails, driftwood fences and a lagoon, a frozen island of snowy paths,
  snowbanks and an igloo, a zen garden of raked gravel and a moon bridge, a volcano of basalt steps and lava pools (the
  `theme=<name>` previews).

### 4.2 Fences (`Plot.fence`, `Models/FenceModels`)

A fence is drawn, not placed one at a time: it goes up in 2-stud lengths along the island's grid lines on the even
studs, each length running east or south from a corner (`rot` 0 or 90). A length has a post at each end (a pier, a
lump of stone or a cane, by the fence) that the next length shares, so a run joins up and a corner closes with no gap.
**Line** puts lengths along the grid lines the drag passes (along x, then along z from the last corner, so a slanting
drag makes steps); **Box** runs a fence all the way round the box from the press to the finger; **Erase** takes
lengths down, half their price back. Drawing another fence over a length swaps it. A length goes where each of its two
studs has grass on one side or the other, so a fence can run along the island's edge; it never runs through a
building or the plaza, but it may run along a building's side and past paths and water, and a
building can't be put down across a fence. A length picked up turns between east and south with Rotate (R). The
seventeen run from a rope sagging between two posts to a crystal fence with glowing points, by way of white pickets,
split rails, a bamboo screen, bleached driftwood, woven willow, a clipped hedgerow, a garden gate under a little arch,
a low wall of field stones, a log palisade, iron railing with gold spear tips, a lantern rope whose lights glow at
night, brick, adobe, a snowbank hung with icicles and a shell wall.

### 4.3 Water (`Plot.paint`, `Models/GroundModels`, `PlotService.waterMasks`)

> From the request at the top: "Also, add the ability to add water to make rivers."

Water is drawn like paths, in 2 x 2 tiles on the even studs: a line digs a river, a box fills a pond. There are seven:
a Stream with pebbles, a darker Deep River with current streaks, a Lily Pond, Swamp Water with reeds, a Lagoon with
sandy banks, a steaming Hot Spring and a Frozen Pond. A tile draws its bank only on the sides where the water ends and
rounds the corner where two banks meet, so a river of many tiles reads as one body of water: the server works out each
tile's neighbours (`PlotService.waterMasks`), and a tile is built again when water is dug or taken up next to it. The
water moves the way the shallows do (§8). Water shares its limit with the paths (`PathPieces`), and each eraser takes
up only its own kind (Erase with a path picked leaves the water alone).

What goes with water: a piece made to go **over** it (the bridges, the dock, the waterwheel, the little waterfall)
stands on grass, on water or across both; one made to go **on** it (lily pads, reeds, stepping stones, the duck decoy,
the rowboat, lotus flowers, floating lanterns) only on water, every stud of it ("Tap the water where it should float.";
on the grass its frame is red). Nothing else stands on water, and water can still be dug under a bridge or round a
lily pad already there. Taking water up takes what floats on it with it, half its price back too; a bridge stays where
it is. The founder wades through rivers: each step splashes a few drops and makes a soft watery pop (`step_water`).

### 4.4 Growing the island (`Data/Office`, `Data/Street`, `TierCost`)

> From the request at the top: "Make more island progression and allow the player to expand their land even more."

Ten tiers. The first six are the old ones with lower walls: Harbor Town 60,000 wood (was 150,000), Coral City 160,000
(was 320,000), Sunspire Capital 380,000 (was 800,000), so the town comes in the second hour again and a city can come
in the third (§10). Past the capital four more islands grow north, each as wide as the capital and longer than the one
before (`Data/Street`'s isles 7 to 10; the lot reaches 136 studs north of the island's origin for the biggest one's
shallows): Moonlit Bay, Evergreen Isle, Skyreach Isle and Driftling Haven. On Driftling Haven the grass reaches more
than a hundred studs north of the campfire, 6,608 cells of it, nearly four times a Grand Isle's and 1.8 times the
capital's.

| Tier | Island | Wood to grow to it | Grass (cells) | Pieces | Path and water tiles | Fence lengths | Huts | Eggs a lot |
|---|---|---|---|---|---|---|---|---|
| 1 | Castaway Cay | (the start) | 489 | 36 | 80 | 40 | 4 | 5 |
| 2 | Palm Isle | 600 | 1,044 | 60 | 150 | 80 | 6 | 6 |
| 3 | Grand Isle | 9,000 | 1,707 | 90 | 240 | 130 | 8 | 7 |
| 4 | Harbor Town | 60,000 | 2,367 | 130 | 340 | 180 | 10 | 8 |
| 5 | Coral City | 160,000 | 3,002 | 180 | 460 | 240 | 12 | 9 |
| 6 | Sunspire Capital | 380,000 | 3,658 | 240 | 600 | 300 | 14 | 10 |
| 7 | Moonlit Bay | 800,000 | 4,368 | 300 | 750 | 370 | 16 | 10 |
| 8 | Evergreen Isle | 1,600,000 | 5,129 | 370 | 900 | 440 | 18 | 10 |
| 9 | Skyreach Isle | 3,000,000 | 5,977 | 450 | 1,050 | 520 | 20 | 10 |
| 10 | Driftling Haven | 5,000,000 | 6,608 | 540 | 1,200 | 600 | 22 | 10 |

No new buildings or huts open past the capital and no new kinds hatch there. What a bigger island brings instead is
room (the limits above, up to 264 driftlings in Palaces), the dearest decor (Gilded Walk, Lava Rock, the Lantern
Tower, the Fire Basin, the Steam Vent and the Golden Driftling at 7; Starlit Path, the Crystal Fence, the Crystal Arch,
the Obsidian Spire and the Sky Bell Tower at 8; the Lava Pool and the Crystal Spire at 9; the Rainbow Arch at 10) and
better eggs. The tree lays ten a lot as on the capital, but luckier ones (`EggLuck` 1.6, 1.9, 2.2, 2.6: on Driftling
Haven more than one egg in five is legendary), dearer ones (`EggTier` 160, 270, 420, 640), and a hatchling's mutations
roll three rarities up on Moonlit Bay and Evergreen Isle and four on the last two (§6). The tree stays at its last
stage (`TreeStage` 4).

- **Expand** (in the tray's header, its price in wood under it; "Island max" on Driftling Haven): the island grows,
  its coast reaching further out round the same campfire. A piece that no longer fits moves to the nearest free spot
  (none is lost; one with no spot left would be cleared with its whole price back, and so would a path, water tile or
  fence that no longer fits, since those are never moved). The Tree of Life keeps its place, the rest make room round
  it, and it lays the bigger island's extra eggs at once (§6). Once the bigger island is on screen: "Your island grew
  into Moonlit Bay. There's more to build now."

  > The request (2026-11-11): "also, expanding the island causes the game to lag abit before the actual expansion"

  The pause came from three places. The server built the whole bigger island (about 1,200 parts at the top sizes)
  in the frame of the tap. The pixel filter then waited half a second and re-baked the picture, and the screen
  stood still the whole time it baked. And the fanfare played at the tap, before anything had changed. Now the
  server builds each island's next size in the background, a few dozen parts a frame, and Expand only swaps it in.
  The filter re-bakes sooner, with more time a frame, behind the old picture, and the island keeps moving
  meanwhile (driftlings, the founder, water and wind). The fanfare and "Your island grew into ..." wait until the
  bigger island is on screen. Every size's coast cells are worked out when the server starts, and the next size's on
  the client a few seconds after each change, so the tap never waits for them either.

### 4.5 Build mode (`UI/BuildUI`, `Controllers/BuildFx`)

> From the request at the top: "Polish the build ui more, just like the bakery game, and reference bloxburg. Also,
> add effects and polish when putting down decor and other amenities."

- **The tray** (the HUD's Build): the view frees to pan over the island (drag it), and a workbench along the bottom
  holds the catalog. Along its top plank: the eight tabs, each with its icon (the icons alone when the names don't fit,
  as on a phone), the tab's count, **Expand** with its price under it, and **Done**. Under them the tab's rows as chips
  (All first, then each row: Decor's fourteen fit one line on a computer, and scroll sideways on a phone). A **search
  button** (a magnifier) and the **search box** after it sit on the tabs' plank when there's room there (on a narrow
  screen, at the end of the chips' row): the button puts the cursor in the box and lights up while a search is on; the
  box's words
  list the matching pieces from every tab, by name, row or tab ("lantern" finds the lanterns on every tab), like the
  bakery's decor box. It opens on Work's Wood row. Then the cards: each a 24 x 24 picture of the piece drawn from its
  own model (§2) over its price in wood (red when you are short), the cheapest first, then the locked ones by the tier
  they open at, each with "Lv7" in place of a price. A mouse over a card shows its tooltip: the name, its size ("3 x 3",
  "2 x 2 tiles", "2-stud lengths"), what it is and what it makes, a hut's room and comfort, its charm, "Goes over
  water." or "Goes on water.", its price and, while locked, "Opens at island level 7." A tap on a locked card says
  "Expand your island to level 7 to build this."
- **Placing**: a picked piece is a ghost on a raised frame where the mouse is (or the last tap): cyan where it fits, red
  where not; **Place** (a second click on the same spot, or E) builds it and keeps it picked for another; **Rotate** (R)
  turns it a quarter. A tap on a standing piece picks it up to **Move** it, **Copy** it (another of the same, turned the
  same way: C), **Replace** it (§4.1) or **Clear it away** (X or Delete; half its price back; not a Hatchery warming an
  egg; a hut's driftlings are left with no hut and move into the next hut with room, §6). Esc drops what is picked, and
  with nothing picked closes Build mode. Under the buttons an info plate shows the piece's picture, its name, what it is
  and its price, and with a keyboard the keys ("R turns it. E puts it down. Esc stops."). While a piece is picked or a
  stroke drawn, the tray shrinks to the height of that plate, so more of the island shows (the tip's banner comes down
  with it). The Tree of Life only moves: it has no Copy, Clear away is greyed and nothing replaces it ("The Tree of Life
  stays on your island. You can move it.").
- **Putting a piece down** (`Controllers/BuildFx`, its particles in `Controllers/Puffs`): it drops in from a stud and
  a half up, falling faster as it comes, and hops once as it lands (a stand-in falls while the server's own model is
  held back, then the real one takes its place). As it lands, a ring of six little dust clouds puffs round its
  footprint, a burst of what it's made of flies up by its feel (wood chips, chips of stone, leaves, drops of water,
  glints of metal, magic motes and stars, sand, snow, confetti for cloth, embers for fire), a twinkle shows over its
  top, it makes its sound and "+N" floats up with the charm heart when it brings a point of charm or more. A stroke of
  path, water or fence puffs along its tiles or lengths (at most 24 puffs, spread along it) with its sound in a quick
  run of up to six; taking them up puffs dust. A piece cleared away goes in a puff. The particles are 1 px bits and
  small sprites at whole pixels (at most 260 at once); with the pixel filter off there are none.
- **The sounds** go by feel, cut from clips the game already has: a hammer's tap for wood, pebbles for stone, rustling
  grass for plants, a low bubble pop for water, a chime's clink for metal, a sparkle of chimes for magic, footsteps in
  sand for sand (higher for snow), a cloth flap for cloth and a shaker for fire.
- **The tips in Build mode:** the tip's banner stays up, over the tray; opening Build mode (or a tip moving on while it
  is open) turns the tray to the tab and row of the building the tip asks for (the Lumber Camp on Work's Wood row, the
  Veggie Patch on Farms, the Driftling Hut on Huts, the Snack Stall on Shops), and that building's card (and its tab,
  while another tab is shown) pulses until it stands on the island; placing it goes straight on to the next tip's tab.
  The quests' Go opens Build mode on its tab (an old tab's name, "build:wood", opens Work on that row).

  > The request (2026-11-10): "make the tutorial show while in the build menu as well, and auto switches the player to
  > the tab where the required buildings are in"

## 5. Villagers (gone)

The request of 2026-11-12 quoted at the top of this file took them out: "remove villagers, only creatures should be
enough". Gone with them: the homes and their beds, moving in (`MoveInCharm`), jobs and the Villagers panel
(`folk.work`, `folk.dismiss`), `Data/Names`, the Folk attribute, the first tips' Tent and the castaway, and the menu's
Villagers button. Visitors still come for the charm and buy at the shops. A building's work is its driftlings' (§3,
§6).

## 6. Driftlings and the Tree of Life (`Logic/Tree`, `Data/Creatures`, `Data/Traits`, the Tree panel, the Driftlings panel, the Index)

The request of 2026-11-13 near the top of this file brought the tree back to lay eggs: "it spawns in 5 eggs around it,
which refreshes every few minutes to spawn in another 5 eggs, replacing any existing eggs that were not taken.
expanding the island increases the quality of eggs spawned and amount of eggs spawned". (Before it, for a few hours,
driftlings floated past on the tide; before that the tree grew one every few seconds into a pen, with Speed and Luck
to buy.)

**The Tree of Life** (`Logic/Tree`; its own piece in `Data/Buildings`: "tree", 8 x 8 studs, charm 6, never in the
build tray). Every island has one. A new island has it behind the campfire (`Tree.SPOT`, the nearest free spot); a
save from the tide gets one there too, and if the island is built full the pieces nearest that spot make room (paths
first, then decor, then the buildings nobody lives in, each with its whole price back). Build mode can move it but
not clear it away (`fixed`) or replace it, and it doesn't count toward the piece limit. When the island grows it keeps
its place and the rest make room round it.

What it looks like (`DecorModels` "tree", drawn for the request of 2026-11-12: "make the tree of life more like a tree
of life, reference references for it, make it look bigger and more grand"): we read about the tree of life in old art
and kept what makes it read at a glance. The Celtic tree of life is drawn inside a circle, its roots spread as wide as
its branches, "as above, so below"
([The Irish Jewelry Company](https://www.theirishjewelrycompany.com/blog/post/discovering-the-magic-of-the-tree-of-life-in-nature-and-spirituality),
[1000 Logos](https://1000logos.net/celtic-tree-of-life-meaning/amp/),
[Celtic Art Studio](https://celticartstudio.com/about/treeoflife/123/)). The Norse world tree, Yggdrasil, is vast,
its crown over everything, its roots reaching down into other worlds
([New World Encyclopedia](https://newworldencyclopedia.org/entry/Yggdrasil),
[Encyclopedia.com](https://encyclopedia.com/humanities/news-wires-white-papers-and-books/yggdrasill),
[World Tree Project](https://worldtreeproject.org/exhibits/show/yggdrasill/modern_illustrations)). Games draw a
sacred tree with a glow of its own and something hanging from it
([a pixel tileset's glowing tree](https://winlu.itch.io/winlu-fantasy-tileset-exterior/devlog/528816/giant-glowing-tree)).
So ours stands about 13 studs tall: a ring of standing stones round its foot (pale blue marks glowing on some, a gap at
the front), roots spreading out as far as the crown, a trunk of three braided strands round a core with pale blue
runes glowing on it (since 2026-11-13 the core one smooth column and each strand one round tube rising from the
ground and twisting up it, no stacked drums), the hollow in front with a gold glow in a frame of lintel and posts, and a crown of leaf clouds
on forked limbs, each with a dark underside, blossom, hanging vines and gold fruit under it; a ring of gold light on
the ground, motes in the air, mushrooms and flowers at its foot. Round the stones a wide round lawn of moss holds its
eggs (the footprint grew from 6 x 6 to 8 x 8 for them).

**It grows with the island** (`Tree.stage`, `TreeStage` by tier: 1, 2, 2, 3, 3, then 4): stage 2 on a Palm Isle and a
Grand Isle, 3 on Harbor Town and Coral City, 4 from the capital on. Each stage the trunk thickens, the crown spreads
wider (half as wide again at the last) and climbs (the top cloud from 12 studs to 19), the leaf clouds grow, and more of
it glows: more runes up the bark, more of the standing stones lit (every third, every other, then all), more blossom,
longer vines. From the second stage lanterns of light hang in its lower limbs; from the third the ring of clouds is
eight with an upper ring of four, and every cloud carries three gold fruit; at the last the crown is in full blossom, a
ring of gold light floats over it, the stones wear gold caps and a second ring of light glows on the ground. When the
island grows into a new stage, the tree is built again at it.

- **Its eggs** (`Tree.step`, `Tree.lay`): every `EggSecs` (180) seconds the tree lays a new lot round its roots,
  `EggCount` by the island's tier: 5, 6, 7, 8, 9, then 10 from the capital on. The eggs still there from the last lot
  go as the new ones come.
  The huts' tree shares (Leafy and its family, and a few passives; `HutTree`: 50% at most) bring the next lot sooner,
  at the most every two minutes. The clock runs only while you are on the server, and the eggs and the time left are
  saved, so leaving and coming back lays no new lot. A new island, and a save from before the eggs, gets its first lot
  the moment it arrives. On a brand-new island (nothing hatched yet and no driftling) the first lot has two commons in
  it, so the tips' first hatch is cheap.
- **Rarity** (`Tree.odds`, rolled when the egg is laid): each rarity step's weight (`Traits.RARITY`: 100, 45, 16, 5,
  1.2) times the island's luck to the power of the steps. The luck is 1 plus `EggLuck` by the island's tier (0, 0.25,
  0.5, 0.75, 1, 1.3, 1.6, 1.9, 2.2, 2.6) plus the huts' luck shares (Lucky and its family: `HutLuck`, 0.5 at most). A
  rarity none of the kinds open at the island's tier has falls to the next commoner one. Before the huts' shares (in
  brackets, about how often an egg of that rarity is laid):

  | Island tier | Eggs a lot | Common | Uncommon | Rare | Epic | Legendary |
  |---|---|---|---|---|---|---|
  | 1 | 5 | 59.8% | 26.9% | 9.6% (6 min) | 3.7% (16 min) | none (beaches and meadows have no legendary: its share goes to the epics) |
  | 2 | 6 | 51.6% | 29.0% | 12.9% (4 min) | 5.0% (10 min) | 1.5% (33 min) |
  | 3 | 7 | 44.2% | 29.8% | 15.9% (2.7 min) | 7.5% (6 min) | 2.7% (16 min) |
  | 4 | 8 | 37.6% | 29.6% | 18.4% (2 min) | 10.1% (3.7 min) | 4.2% (9 min) |
  | 5 | 9 | 31.9% | 28.7% | 20.4% (1.6 min) | 12.8% (2.6 min) | 6.1% (5.4 min) |
  | 6 | 10 | 26.1% | 27.1% | 22.1% (1.4 min) | 15.9% (1.9 min) | 8.8% (3.4 min) |
  | 7 | 10 | 21.4% | 25.0% | 23.1% (1.3 min) | 18.8% (1.6 min) | 11.7% (2.6 min) |
  | 8 | 10 | 17.5% | 22.8% | 23.5% (1.3 min) | 21.3% (1.4 min) | 14.8% (2 min) |
  | 9 | 10 | 14.3% | 20.6% | 23.5% (1.3 min) | 23.5% (1.3 min) | 18.0% (1.7 min) |
  | 10 | 10 | 11.1% | 17.9% | 22.9% (1.3 min) | 25.8% (1.2 min) | 22.3% (1.3 min) |

- **A bigger island at once** (`Tree.fill`): growing the island tops the lot up to the new count straight away, the
  new eggs rolled at the new odds ("The tree laid 1 more egg."); the eggs already there stay.
- **The price** (`Tree.cost`): `EggPrice` by rarity (20, 90, 400, 2,000, 10,000 shells) times `EggTier` by the island's
  tier (1, 3, 8, 20, 45, 90, 160, 270, 420, 640), less the huts' cost shares (Thrifty and its family: `HutCost`, half
  off at most; a Greedy one takes some of that share back but never makes eggs dearer). A bigger island earns more and
  lays better eggs, so its eggs cost more:

  | Island tier | Common | Uncommon | Rare | Epic | Legendary |
  |---|---|---|---|---|---|
  | 1 Castaway Cay | 20 | 90 | 400 | 2,000 | (none laid) |
  | 2 Palm Isle | 60 | 270 | 1,200 | 6,000 | 30,000 |
  | 3 Grand Isle | 160 | 720 | 3,200 | 16,000 | 80,000 |
  | 4 Harbor Town | 400 | 1,800 | 8,000 | 40,000 | 200,000 |
  | 5 Coral City | 900 | 4,050 | 18,000 | 90,000 | 450,000 |
  | 6 Sunspire Capital | 1,800 | 8,100 | 36,000 | 180,000 | 900,000 |
  | 7 Moonlit Bay | 3,200 | 14,400 | 64,000 | 320,000 | 1,600,000 |
  | 8 Evergreen Isle | 5,400 | 24,300 | 108,000 | 540,000 | 2,700,000 |
  | 9 Skyreach Isle | 8,400 | 37,800 | 168,000 | 840,000 | 4,200,000 |
  | 10 Driftling Haven | 12,800 | 57,600 | 256,000 | 1,280,000 | 6,400,000 |

- **Hatching one** (`egg.hatch`): Hatch on its row in the Tree panel, and only there (a tap on an egg under the tree, on
  the tree itself or on the HUD's Tree card opens the panel). You pay its price. The egg may turn rarer first
  (`Tree.rise`): one rarity up with `Tuning.EggUp` (a common 6%, an uncommon 4%, a rare 2.5%, an epic 1.2%), and on
  again from there while the rolls hold, never to a rarity none of the island's kinds has, and never for the tips'
  first two. The result says what it was laid as (`r`) and what it hatched as (`hr`). What hatches (`Tree.roll`) is
  one of that rarity's kinds among those
  open at the island's tier (`Data/Islets` tier: beaches and meadows from the start, snowfields and mangroves at 2,
  volcanoes and grottoes at 3, reefs at 4, bluffs at 5, ruins at 6), with mutations of its own (below), rolled as one
  rarity rarer every `EggMutTier` (2) tiers past the first (one step on a Grand Isle or Harbor Town, two on the city
  tiers, three on Moonlit Bay and Evergreen Isle, four on the last two, never past a legendary's roll). It moves
  into the comfiest hut with room and takes a free place (`HelpMax`: 2 driftlings a building; `Island.freeJob`: a
  building of its knack first, else wherever it works fastest, then the emptiest), or rests in its hut until one is
  free; the hatch scene plays (§6.2), then "It hatched a rare Wispwing." in its rarity's colour, and it goes in
  the Index. A new island's first two hatches are good with wood and then at a farm, so the tips' Lumber Camp and Veggie
  Patch have help waiting. With no hut built the answer is "Build a hut first. Driftlings need somewhere to live."; an
  egg a new lot replaced before the tap reached the server, "That egg is gone. The tree laid new ones."
- **Every hut full** (`full`): the Tree panel's swap picker opens, listing every driftling in a hut, the weakest first,
  each with what it sells for. Pick one and it is sold for its price (`Tree.price`, below) and the hatchling takes its
  place ("It hatched an epic Pyredrake! The one it replaced sold for 7 shells."). If a new lot replaced the egg while
  the picker is open, it says so and goes back to the Tree panel.
- **A driftling with no hut**: one whose hut was cleared away or replaced by a smaller one, or a Hatchery's hatchling
  with no room, waits with no hut (`home` 0). It works nowhere and is not drawn on the island; the Driftlings panel
  lists it last ("No hut. It moves in when one has room.") and it moves in the moment a hut has room (`Tree.settle`).
- **In the world** (`Controllers/EggView`): an egg is two spheres on a little bed of straw, a broad one below and a
  smaller one on top for an egg's curve, a rarer egg a little bigger. Each rarity has its own colour, marks and lights
  (`EggView.LOOK`), so a player can tell the eggs apart at a glance:

  > The request (2026-11-13): "Also, color each egg differently with different effects to allow players to
  > distinguish easily between egg rarities"

  | Rarity | Shell | Marks | Lights |
  |---|---|---|---|
  | Common | cream | brown freckles | none |
  | Uncommon | green | a white zigzag band round its middle | a leaf drifts up off it now and then |
  | Rare | sky blue | white stars that glow | white and cyan twinkles blink round it |
  | Epic | purple | pink spots that glow | a purple glow on the lawn under it, two motes of light (pink and white) circling and bobbing, pink and white sparks rising |
  | Legendary | gold | a glowing yellow zigzag band, and a band of light round its middle | a beam of light standing up out of its top, breathing taller and shorter, a gold glow on the lawn, gold sparks and stars rising |

  The glowing marks pool light on the lawn at night. The sparks are 1 px dots and small twinkle and spark sprites at
  whole pixels over the world, the rarer the egg the more often (from one every 0.8 s or so off an uncommon egg to
  several a second off a legendary one), only over eggs lying still and at most 140 at once; the motes and the beam go
  out under the lawn when the egg sinks or hatches. The egg icons (`egg_1` .. `egg_5`: the Tree card, the Tree panel and
  the Hatchery) are drawn to match. The eggs lie on the tree's lawn on a ring round its stones, spaced evenly along the
  side the view looks at (its south and east, whichever way the tree is turned), so none hides behind the trunk. A new
  lot rises out of the lawn one egg after another and the old eggs left sink back into it; now and then an egg rocks a
  little. No price tags float over them and no names: the egg's colour tells the rarity, and a tap on one opens the
  Tree panel. A hatched egg is gone from under the tree when the hatch scene ends; the driftling steps out where it lay
  and walks off to its work. A neighbour's tree lays its eggs too; only the islands near the view have theirs drawn.
  While the tips ask for a hatch (step 4) an arrow bobs over your tree. A tap on your own tree opens the Tree panel; on
  a neighbour's, "Someone else's Tree of Life. Yours is on your own island."
- **The HUD's Tree card** (under the island card; on a phone at the top left): the tree's icon, "Tree of Life"
  ("Eggs" on a phone) and Open, "New eggs in 2:41" over a bar running down to the next lot, then the best three eggs
  now, the rarest first and the cheaper among them (if you can pay for none of them, the best one you can pay for takes
  the last row): each with its egg, its rarity's name in its colour and its price (green when you have the shells). A
  tap anywhere on the card opens the Tree panel; the card buys nothing itself. On a phone only one row; "No eggs right now" once all are hatched. A new lot gets a notice ("The Tree of Life laid new
  eggs."), and one with an epic or legendary egg in it is news: "An epic egg is waiting under the tree." in its
  rarity's colour with a bell-tree run and sparkles over the card. The card steps aside in Build mode and while the
  Tree panel is open.
- **The Tree panel** (Open on the card, a tap on the tree, Eggs in the Driftlings panel, a quest's Go): on the left
  "New eggs every 3:00" (sooner with the huts' tree shares), "Next in 2:41" over a bar, "7 eggs a lot. In huts 6/8"
  (orange when full), the odds of each rarity now under "What it lays now" ("<0.1%" under a tenth of a percent, "not
  yet" for a rarity none of the open kinds has), below tier 6 "A bigger island lays more eggs, and better ones." and
  "Now and then an egg turns rarer as it hatches.";
  on the right, under "Under the tree", every egg there, the rarest first, each with its egg, "Rare egg", "Hatches a
  rare one" and its price on a button that hatches it.
- **The huts** (the Huts tab in Build mode, so many a tier: §4; the old nests: Driftling Hut 2 places, Cozy Burrow 4,
  Driftling Den 5, Treetop Roost 6, Spring Grotto 8, Driftling Palace 12; the home once called Grass Hut is now the
  Grass Shack so the names don't clash). A driftling in a hut adds its charm.
- **Your pick:** the Driftlings panel lists every driftling, the hardest workers first, with **Move** (a picker: each
  hut with its room; a full hut offers to swap with one of its driftlings), **Work** (any workplace on the island,
  each with how fast this driftling works there, the fastest first, or rest) and **Sell**; its buttons open the Tree panel (Eggs) and, when one stands, the Hatchery.
- **Selling** (`Tree.sell`, and a swap) pays `SellPrice` shells by rarity (2, 7, 25, 85, 320), times 1 + 0.25 a
  mutation tier (`SellTier`), times 1 + its sell share (Shiny and its family). It gives a little back and no more: a
  common hatched for 20 sells for 2. Over the career it comes to well under a thousandth of the shells earned (§10).

**How much a driftling works:** each one at a building puts in `PalWork` (0.6) times `RarityWork` by rarity (1, 1.6,
2.5, 4, 7: the request's "creatures work faster based on their rarity") times 1 plus its work share at that building
(its passive and mutations, `Island.palWork`) and its hut's comfort (`Island.palBoost`); the building makes its rate
times the sum (`IdleOutput` with nobody), so a legendary woodsy driftling at a lumber camp is worth many commons
there.

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

**Built like the bakery's cakes** (the request of 2026-11-13 at the top: "The creatures look blocky and unrealistic.
Look at the cakes in the bakery game to reference how detailed they should be"): a driftling is made the way Random
Bakery makes a cake, from round pieces on a fine grid and many small ones (`Models/DriftKit`). Bodies are egg-round;
necks, limbs, tails, ears and horns are smooth tubes that taper and bend; shells and pads are round pillows; spots,
blush, stripes and the inside of an ear lie flat on the surface; leaves, feathers, fins and spikes are thin pointed
blades. The eyes are big and glossy: a dark oval, a coloured iris low in it and two shines, and when they blink a
soft curved lid takes their place. A closed mouth is a little smile that opens when the driftling cheers or yawns.
**Their own eyes and textures** (the request of 2026-11-14 at the top: "Can you use different eyes for each? Also,
apply texture to each of them"): every kind of driftling has its own eyes, and no two that share a body plan look out
the same way. There are twenty styles of eye: glossy sparkling ovals, the same with lashes, plain buttons, little beads
and dots, a star or a heart in the shine, round cartoon eyes with a coloured iris, wide startled ones, reading glasses
(the owl that reads old carvings), a cat's slit and a goat's bar, ringed owl eyes, heavy sleepy lids, a fierce brow,
eyes shut in a happy arch, eyes that glow, crystal gems, a glowing visor slot (the guardian golem) and a moth's cluster
of beads, each in the iris colour that suits the kind. All of them blink except the happy arches. And each wears a
texture on its body: fur, fluffy curls, feathers, scales, a shell's growth lines, stone specks and cracks, a fallen
wall's courses of brick, bark, crystal facets, skin with pores, streaks of ice, velvet fuzz, a crab's pitted shell,
a jelly's bubbles or cooled lava's bright cracks; a snail's or a turtle's shell and a crystal creature's crystals wear
theirs too. The texture is one-pixel marks a shade lighter or darker than the colour under them, drawn on the
driftling itself, so it turns and walks with it and never slides. It shows wherever a driftling is drawn big (the
hatch scene, close looks); on the islands, where a driftling is a figure a few pixels tall, it is left off, as it
would only be noise.

Up close (the hatch scene, the portraits) a driftling has 90 to 200 pieces: toes, whiskers, fur tufts, flecks and
cracks. On the islands, where it is a small figure among dozens, it is the same shape with fewer, bigger pieces
(45 to 72), and one far from the view is posed every fourth frame.

**Their bodies** (`Models/DriftModels`, `Models/DriftPlans*`): each of the twenty body plans is built to read as its animal. The turtle has
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

Fifty-five driftlings of our own, five to seven to each of the nine kinds of island (`Data/Islets`: a kind's
driftlings hatch once the island reaches that kind's tier, above):

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

Each has a **knack** (farms, fishing piers, lumber camps or shops: what it's best at; it may work anywhere, its
passive usually helping at its knack's buildings), a 3D model built from parts
(twenty body plans: blob, crab, bird, bun, lizard, owl, pup, mole, jelly, fox, wyrm, seal, bat, sprite, yeti, snail,
turtle, frog, moth, golem and drake) and a 32x32 portrait drawn from that model. Its old fighting numbers stay only to rank the kinds for
the Hatchery (`Creatures.power`: weighted, +12% a rarity step).

- **Rarity** (`Traits.RARITY`): Common, Uncommon, Rare, Epic, Legendary (name colours: grey, green, blue, purple,
  gold), the eggs' odds and the work it does above.
- **A passive of its own** (`passive`: a name and its effects, every kind's different): shares at work (anywhere, or
  at farms, fishing, lumber or shops), selling for more, charm, or for the whole island eggs sooner, luckier eggs or
  cheaper eggs ("Snappy Pincers: +15% at fishing, +30% sell price", "Diving Beak: +25% at fishing, eggs 4% sooner").
  The tree, luck and cost shares count only from a driftling in a hut. (Until 2026-11-13 the cost share was food
  eaten; on the tide it was the driftling's own price, and the tree share its arrivals.)
- **Mutations** (`Data/Traits`, `Pal.muts`): a driftling comes with up to three (about one in three none), kept for
  life. Ten families of four tiers, each tier rarer and stronger (the fighting families became island ones on
  2026-11-12 and the eating one the eggs' price on 2026-11-13, keeping their ids so old saves read them): Thrifty /
  Frugal / Modest / Selfless (eggs cost 15 / 30 / 50 / 80% less, the huts' together half off at most), Shiny / Glossy
  / Golden / Radiant (sells for 30 / 70 / 150 / 300% more), Cute / Sweet / Adorable / Beloved (+1 / 2 / 3 / 5 charm),
  Leafy / Blooming / Lush / Evergreen (eggs 4 / 8 / 14 / 22% sooner), Lucky / Blessed / Fortunate / Starborn (+5 /
  10 / 18 / 30% egg luck),
  Busy .. Workaholic (+8 .. 40% work anywhere), and Green Thumb .. Bountiful, Angler .. Sea Sage, Chopper .. Forest
  Heart, Chatty .. Tycoon (+12 .. 65% at farms, fishing, lumber, shops). Tier weights 46 / 25 / 10 / 3 (and 16 for a
  **flaw**: Greedy makes eggs cost 25% more, Dull sells for 20% less, Grumpy takes a charm, Sluggish and Lazy work 8 and 15%
  less; never beside its own family's strength); a rarer driftling rolls fewer flaws and more of the top tiers. Four
  at most (a Hatchery child can gain one, §6.1). Their names show in tier colours (with stars) on the Driftlings
  panel.

The **Index** lists all fifty-five ("Seen 12 of 55 kinds"): a dark shape and its rarity until you have had one (a
save from the tide keeps the ones it saw float by, on a lighter plate), then its name and passive. A kind not open yet
says the island tier it hatches from ("These hatch from island Lv 4.").

### 6.1 The Hatchery (`Logic/Breed`, the Hatchery panel)

> The request (2026-11-10): "make a breeding system that also works like in palworld that unlocks after a certain
> island level". The genre's system (two parents, a feast, an egg, the child's kind from the parents' strength, their
> traits passed on) in our own buildings, numbers and words.

- **The Hatchery** (Huts tab, island tier 3: a warm nursery with a nest of speckled eggs and a heat lamp): one egg at a
  time each; several may stand. The Driftlings panel's **Hatchery** button opens its panel.
- **Laying an egg**: tap each slot, pick a parent from your driftlings (not the other one); the
  panel shows what they would likely hatch (its portrait once met, else a dark shape and ???) with its rarity, and the
  feast and the turns it takes; **Breed** pays the feast (`BreedShells` 20 / 80 / 300 / 1,200 / 5,000 shells by the
  child's rarity; food till 2026-11-13) and lays the
  egg (`BreedTurns` 3 / 4 / 6 / 9 / 14 island turns). The parents carry on as before.
- **What hatches** (`Breed.child`): a pair of one kind hatches its kind; any other pair the kind whose power is nearest
  their average (so two strong ones can make a kind the player never met); a legend only from two legends.
- **What it inherits** (`Breed.inherit`): a mutation both parents carry always passes on, the better tier, and with
  `BreedTierUp` (30%) a tier better still (a shared flaw becomes its family's first tier); one only a parent carries
  passes on half the time (`BreedKeep`); with `BreedNew` (15%) it gains one of its own (tier 1 or 2); the best four.
  Breeding two that share a mutation, again and again, climbs it to the top tier.
- **Hatching**: at each turn's end the eggs count down; a ready one hatches and moves into the comfiest hut with room
  (with none it waits with no hut, §6), and goes in the Index ("Floe hatched!" in the turn's banner). The panel shows
  each egg: its rarity's egg, "Hatches in 3 turns" over a bar, its parents. A Hatchery holding an egg is not cleared
  away ("An egg is still warming in that Hatchery."). On the island its name floats up over the Hatchery in pink.

### 6.2 The hatch scene (`UI/HatchScene`, `UI/HatchBackdrop`, `EggModels.hero`)

The egg bought is shown up close the moment Hatch is pressed (the requests at the top). There are no blinds and no
wait: the egg floats on its own in front of a painted sky, and the player taps it open.

- **The sky** is a picture drawn pixel by pixel in 2D, its own for each rarity: a sunset with a banded sun and outlined
  clouds (common), a golden afternoon (uncommon), a blue twilight with a crescent moon (rare), a violet night with a
  full moon and aurora (epic), a deep gold night with a great setting sun throwing beams (legendary). Every sky has
  three ranges of hills going darker toward the front, the nearest with round and pointed trees in outline, two little
  islets floating far off, and a glow round the egg in dithered rings. Little flocks of birds flap by (day and
  twilight), shooting stars cross the night skies and stars twinkle. Seeds and petals blow across by day, fireflies
  rise at night.
- **The egg** (`EggModels.hero`, 2.3 to 2.8 studs by rarity): a smooth shell of 25 overlapping slices, a white shine
  high on its lit side, and its rarity's work painted on it as flat marks: freckles and sandy patches (common), a white
  zigzag band and a vine with leaves and a sprout on top (uncommon), white four-pointed stars and a frosty band with
  icicles (rare), two pink stripes spiralling up it with runes between them and three motes of light circling (epic), a
  band of gold set with red, blue and green gems, glints, a crown of points, a halo of light turning over it and a beam
  of light (legendary). It hangs in the middle of the picture with nothing under it, bobbing and swaying, and every
  few seconds it gives a little wobble, as if asking to be tapped.
- **The taps**: the title names the egg ("An epic egg") and "Tap the egg" blinks at the foot of the screen. Each tap
  takes the next thing waiting inside. First each step up in rarity (`Tuning.EggUp`, the result's `hr`): a hard shake,
  a flash, sparks and a ring of stars, "It turned legendary" and the next rarity's egg floating there, the sky and the
  light changing with it. Then each mutation: a shake, a new crack, and its plate sliding in at the right with its name
  and stars in its tier's colour and what it does ("Lucky *", "+5% egg luck"). Each of these taps runs the cracks a
  little further (three stages). Once nothing is left the cracks glow from inside and the hint says "Tap to hatch it".
  An egg with no step up and no mutation starts out like that, so its first tap hatches it.
- **The hatch**: a flash, the top flies off, bits of shell scatter and the rest of the shell falls away, and what
  hatched pops out where the egg was with a hop and a cheer. "It hatched", its name in its rarity's colour and "Rare,
  good at farms" under it, and "No mutations" on a plate if it has none. "Tap to go on" shows after a moment; that tap
  goes straight back to the island (its picture was kept, so it is there at once), the Tree panel back if Hatch was
  pressed there. The scene waits for that tap and never closes by itself.
- **Grander by rarity** (`GLORY`, by the rarity it is at that moment): the light of dusk for the commoner ones, a blue,
  violet or deep gold night for the rarer, the egg's own lights pooling round it; rays of light turning behind the egg
  (8 from rare, 12 epic, 16 legendary); more sparks and shell; the picture jolts (rare up); confetti (epic up); a ring
  of stars (uncommon up); the sounds grow with it.
- Two taps closer together than a fifth of a second count as one, so a double tap never skips a reveal. Space, Enter
  and a gamepad's A tap too. One scene at a time. With the pixel filter off (the classic look) the egg floats the same
  way without the painted sky.

## 7. Expeditions and battles (gone)

The request of 2026-11-12 quoted at the top of this file took them out: the wild places on the island (the Tide Pool,
the caves and the rest) and the walk in, the paths of stops, the timed battles, snacks and befriending, the guardians,
the captain, the snack pouch, every level and its xp, the skills and skill points, and the Training Yard. Taken out of
the code with them: `Data/Sites`, `Data/Skills`, `Logic/Sites`, `Logic/Expedition`, `Logic/Battle`, `UI/ExpeditionUI`,
`UI/MicroStage`, `UI/Voyage`, their actions and their sounds. Driftlings came from the Tree of Life after that, for a
few hours on 2026-11-13 off the tide, and since then hatch from the tree's eggs (§6).

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
- **Rounded shores** (the request of 2026-11-13, with a picture of the stepped shore and a palm's trunk of stacked
  boxes):

  > "could you bevel these to make them smoother, with rounded corners? for the trees, you should also make the trunk
  > connected smoothly as well without the stepped boxes"

  Each band's edge was a staircase of whole studs. Now every inner corner of the stairs is filled with a flat
  triangle of that band, and a square outer corner is cut back the same way, so each edge runs straight along the
  grid or on a diagonal and turns in 45 degree steps: the island reads round, and a stretch at 45 degrees is one clean
  line. The lawn's dark rim and darker patches, the shallows, the foam and the plaza's ring of sand are bevelled the
  same way, and the moving water runs over the new corners like the rest of it. You walk and swim exactly where you
  did: the triangles are only looked at. The palms' trunks are one smooth curve of round rings joined end to end,
  rising from the sand, leaning out and straightening under the crown, the rings in two woods in turn and a little
  narrower going up; the catalog's trees lost their steps too (§4).
- **No house:** the island's heart is a plaza round a campfire (fire stones, logs, a flame with smoke, seats, a flag
  and torches). Your sign stands on the south beach with the island's name over it. Visitors stroll the grass round
  it. There are no docks (2026-11-13): the island stands alone in the sea.
- **The water moves:** the sea, the shallows and the foam are redrawn a few times a second by the pixel filter: swells
  roll across in bands with crests catching the light and dark troughs, and the foam laps at the sand. The fishing
  pier's pond, the fountains and the rivers and ponds drawn on the island (§4.3) move the same way.
- **Day and night** (the request of 2026-11-10: "make an actual day night cycle, causing things to go dark and then bright
  as time goes on"): the island's day clock grades the whole picture (`Controllers/DayLight`): a rosy dawn as the day
  begins, plain daylight, a golden dusk (from 0.6 of the day), a violet twilight and a deep blue night (from 0.81)
  that brightens into the next dawn. At night the lamps, torches, the campfire, lanterns and lit windows keep their
  colour and pool warm light round them in three stepped rings on the pixel grid (the pools move with the picture as
  the view follows you), only as strong as the dark is deep (no orange rings in the late afternoon), never all the
  way back to the day. Each pool is as big as its light:

  > The request (2026-11-12): "also, lights seem off, the all have the same size even though the light source might
  > be smaller or bigger"

  Every light had the same pool, so a one-pixel glint lit as far as the campfire and a canopy hung with small lights
  came out in bright rings (the Tree of Life's, then). Now a light is the patch of lit pixels it shows (or a moving
  model's lit parts together, a fire's flames or a driftling's glowing eyes), and its pool's radius goes with that
  patch's size to the power 0.6: a glint gets a two-pixel halo, a pier lantern 7, a torch 11 and the campfire about 21
  (the biggest 22). As it gets dark pale things lose more of their light than dark ones (their brightness over a knee
  is pressed down), so white and pink shells, the sand and the sails stay in the night instead of glowing blue. The
  change steps (a few steps between keys, never a smear). With the pixel filter off Roblox's own clock follows the day
  instead.

  > The bug report (2026-11-10): "lighting also seems buggy, especially with shells"
- **Detail everywhere:** palms that lean on curved trunks, rocks, shells, starfish, driftwood, seaweed and flowering tufts strewn by
  each island's own seed. Every building has its doors, windows, ridged roofs with eaves, crates,
  barrels, sacks and pots, its own touches (the patch's scarecrow, the pier's fishing hut and pond, the hut on stilts,
  the stall's awning, the lighthouse's lamp) and, at Lv 3, a lamp and a pennant. Driftlings have shiny eyes, cheeks
  and a mouth.
- **Boats** (`Models/BoatSpec`: one plan for the sailboats crossing the sea), bigger and finer with each boat level: a planked hull with
  seams, a painted band (gold trim from level 4), a rim, a bow (tall against the hull, flush with the rim, its keel
  sloping up to the stem's point), a stern with its rudder and tiller and a planked deck;
  a rowboat's oars at level 1; a cabin with a door, windows and a life ring from 2; a bowsprit and jib from 3; a
  foremast, a crow's nest and a figurehead from 4; a chimney and a stern lantern from 5; a mizzen and blue sails at
  6; striped sails, a flag and pennants, a lantern, fenders, a crate and barrels.
  With the sea chart and the expeditions gone (§7) the boat at the pier was scenery, and it went with the docks on
  2026-11-13; the sailboats crossing the sea still come in every size, and a swimmer passes through them.

  > The request (2026-11-10): "polish everything even further, such as more detailed boat models, flags rippling in
  > the wind, and swaying leaves."; the bug report: "it seems like the boats are buggy, the triangle part here is
  > supposed to be reversed" (the bow's wedge stood tall at its tip: turned over)

- **The wind:** leaves sway and flags ripple (the pixel filter, a few times a second like the water: palms, trees,
  bushes and tufts lean a pixel one way, rest and lean back, the sway drifting across the island; flags and pennants
  ripple along their length, a lifted fold a shade darker). The boats' flags flutter as they sail.
- **The camera** follows your founder and always keeps them in the middle of the view between the HUD's strips, at one
  zoom on every tier; Build mode frees it to pan.
- Up to `MaxPlots` (6) islands sit in a row on the sea, 80 studs apart; an unclaimed lot is open water with a sandbar
  and a sign. Sailboats cross the sea, gulls fly over and cloud shadows drift across. **Swimming:** you walk off any
  beach into the sea and swim to anyone's island (the water lets you through to an invisible seabed under the whole
  sea, an invisible shelf under the foam is the step back up onto the wet sand, and only the world's edge stops you).
  In the water the founder shows from the chest up with a ring of foam round them, crawls when moving and treads water
  when still, splashing, the strokes heard; they swim at `SwimSpeed` (11, against 16 on land) and can't jump. Home
  sends you back to your own plaza. A tap on a sign shows that island's
  day, driftlings at home and charm.

### 8.1 The island's small lives (`Controllers/AmbientView`, `Render/Fx`)

> The request (2026-11-13): "There is no need to make things limited by squares and spheres, make everything more
> detailed with various shapes and textured objects. Also, like the bakery game, you can use 2d details to add to the
> athmosphere, such as grass, wood detail, birds and other details"

The models' shapes and textures are other work; this is the 2D part. Small things live on every island near the view,
drawn as pixel-art sprites in the pixel layer itself (like Random Bakery's garden): they sit in the world, hide
behind what stands in front of them and are drawn on whole art pixels like everything else.

- **Birds:** little island birds of our own, a teal pip with a crest and a cream breast and a sandy wren with a coral
  breast and a cocked tail, fly in and alight on the lawn, a fence post, a roof's ridge, the island's sign or the
  beach, near the middle of the view. They hop along their perch, peck and look round, and fly off when you (or a
  driftling) come within a few studs, coming back a while later. Now and then a gull glides in from the sea and
  stands on the beach. They go at dusk and come back at dawn.
- **Grass and flowers:** tufts of grass in patches (a lush stretch here, bare grass there) and little flowers in
  clusters on the lawn, in the lawn's own green, leaning as gusts roll across the island. They show only where the
  lawn itself shows: never on a path, a building or anything in front.
- **Butterflies** flit between the flowers (the decor's flower beds and the lawn's own) by day and rest on one now and
  then; **fireflies** drift over the lawn at night, blinking, their light keeping its colour in the dark.
- **Trees** let a leaf or a petal go now and then, in their own colour; it drifts down, lands on what is under it and
  fades. **Smoke** curls from the chimneys, the smokehouse's vent and the grills, **steam** from the hot springs and
  the teapots.
- **The sea:** glints of light on the water now and then (fewer at night), and once in a while a fish jumps out of
  the water near the shore with a splash and a ring where it goes in.
- None of it shows on the hatch scene's stage, and it stops with the picture. A lower graphics setting has fewer of
  everything (birds, tufts, smoke); a phone, where the island shows small, gets smaller sprites. Roblox's reduced
  motion setting keeps the birds still and leaves out what flies, falls and sways.

## 9. Your founder, settings and the tips

The Looks panel sets the founder's skin, hair, style and shirt (every client sees it). The founder walks and jumps
(`JumpHeight`) on the islands; jumping is held in Build mode (the phone's jump button hides with it).

> The request (2026-11-10): "allow the player to jump in their own island as well"; the bug report: "jumping seems
> bugged. also, the player can walk on water" (the chibi stood still on the ground while the character jumped: it now
> rises with it, knees up, and lands in a puff; the coast's invisible walls stood a little under a jump, so a jump
> cleared them onto the sea: they then stood far higher; since 2026-11-13 there are no coast walls, the founders swim)

Settings: the pixel filter's quality, and the music (the note in the HUD's top right corner, on or off, kept with the
profile). **The tips** (the banner over the menu bar, or over the build tray in Build mode: §4.5), each saying where
the stores come from:

> The request (2026-11-10): "the tutorial should also state how to get food, wood and shells. start with enough shells
> to buy all the facilities required." (Since 2026-11-13 the stores are wood and shells, and the buildings take wood.)

1 "Wood pays for everything you build. Tap Build and place a Lumber Camp."; 2 "Shells hatch eggs. Place a Veggie
Patch. It sells what it grows."; 3 "Driftlings need somewhere to live. Place a Driftling Hut."; 4 "The Tree of Life
laid eggs round its roots. Tap the tree to pick one to hatch." (an arrow bobs over your tree); 5 "Visitors
buy snacks too. Place a Snack Stall for more shells."; 6 "The tree lays new eggs every few minutes. When the huts are
full, swap a weak one for a better one." (OK ends the tips). Tips 1, 2, 3 and 5 have their own words in Build mode
("Place a Lumber Camp. Wood pays for everything you build."). Each moves on once what it asks is done, tip 4 once an
egg has hatched. A new island starts with `StartWood` (300) wood and `StartShells` (60) shells: the camp, the patch,
the hut and the stall of the tips cost 265 wood, and the shells pay for the first eggs (the first lot has two commons
at 20 shells, and the first two hatches are good with wood and at a farm). (Until 2026-11-13 the tips asked for a
patch, a camp, a stall, a hut and a level of the tree. A save from before keeps its step's number, and a step whose
task is already done moves on at once.)

> The request (2026-11-11): "also, please rewrite all text and dialogue to be less ai-like. research what are the
> telltale signs of ai writing and avoid them. note this from further on as well"

> The request (2026-11-11): "make a questline such that players are guided throughout the features of the game, such
> as assigning creatures to different work areas"

**The questline** (`Data/Quests`, `Logic/Quest`): once the tips are over, one quest at a time in a card down the left
under the chips (it steps aside for a panel). The card has the quest's icon and title, which of the twenty it is, what
to do and where, and its progress with **Go**, which opens the place it needs (the Driftlings panel, the Tree panel,
Build mode on the right tab, the Index, the Hatchery). When the goal is met, Go turns into **Claim** (shining) next to
the reward; Claim pays it, says so, and the next quest slides in. Each goal counts what the island has now or what its
stats have kept (eggs hatched from the tree, sold, the Hatchery's hatched, the rarest had), so one already met can be
claimed at once. Rewritten for the eggs (2026-11-13), in order: put a driftling to work; sell a driftling; hatch three
eggs; more wood (a second Lumber Camp); three at work; build another hut (2 huts); an uncommon one ("Green-spotted
eggs hatch uncommon ones."); another farm (a second farm or pier); lay a path (8 tiles); decorate (2 pieces); a rare
one; grow your island (tier 2); build a boost; ten driftlings at work; meet twelve kinds; grow the island again (tier
3); build a Hatchery; hatch an egg in it; an epic one; sixty hatched.
The rewards are small (40 to 3,000: wood for the building quests, shells for the driftling ones, some both) next to
what each step costs; the career's player (§10) doesn't claim them, so the economy's bounds are measured without them.
A save from before keeps its place in the list.

**How the game talks** (every tip, notice, card and blurb; CLAUDE.md "Writing" keeps it as a standing rule). The
researched tells of machine-written text, and what replaced them here: an exclamation mark on nearly every line
(now only where something earns it, like an egg hatching); colons and semicolons gluing two thoughts into one line
("Food: tap Build...", "It grows food; everyone eats it") now plain sentences ("Wood pays for everything you build.
Tap Build and place a Lumber Camp."); stock game phrases ("springs into action", "blocks the way", "appears!") now
said plainly ("Everyone goes at once.", "is in the way.", "That's a legendary Pyrelord."); tidy quips built on a
pattern, a mirrored pair or a list of three ("Snaps first, makes friends later.", "Half gull, half fish, all
appetite.") now one plain observation ("Pinches anyone who gets close. It means well.", "Part gull, part fish.
Always hungry."); empty praise ("Every driftling's dream.", "Visitors love it.") now what the thing is or does; a
tip that ended on a moral ("sail often") now just stops. None of the stock AI words were in the game's text (the
Sun Beacon is a name). Stat lines keep their "label: value" form.

## 10. Saves and the economy, checked

The save is version 14 (`Logic/Schema`). It holds the tree's eggs (`clutch`: each egg's id and rarity, and the seconds
to the next lot), checked on every load: rarities 1 to 5, ids unique, no more eggs than the island lays, the clock
between nothing and three minutes. Its pieces are checked on every load too: each count against its own limit (the
pieces, the path and water tiles together, the fence lengths, one Tree of Life), their places between -160 and 64 studs
(the far islands reach that far north), a fence starting on an even corner and running east or south (any other is
dropped), and a path or water tile off the even studs cleared with its whole price back. A version 13 save (before the
catalog) loses the old one-piece Picket Fence and Hedge: fences are drawn now (§4.2), so each one standing comes up with
its whole price back in wood (25 for the fence, 120 for the hedge). A version 12 save (the tide's) gets its Tree of Life
back behind the campfire (on an island built full, the nearest pieces make room with their whole price back) and no eggs
yet, its clock at nothing, so the tree lays its first lot as the player arrives; the driftlings it took in off the tide
count as hatched (`stats.taken`). A version 11 save loses the old tree's levels and growth and its food, and gets a new
tree as a version 12 save does. Every driftling waiting in its pen is sold for its price (`Tree.price`: the shells added
and counted as sold and earned); the driftlings in huts stay where they are, at their jobs, without `held`; and the
driftlings the old tree grew count as hatched (`stats.taken`). Its tips keep their step's number (a step whose task is
already done moves on at once) and the questline its place. A save with more huts than its tier now allows keeps them
(§4). A version 10 save also loses its villagers: every home comes down with its whole price back (Tent 30 shells, Grass
Shack 140 and 20 wood, Cottage 700 and 80, Longhouse 2,400 and 260, Townhouse 7,000 and 700, Villa 20,000 and 2,000,
Manor 60,000 and 5,000), its tips on a step past the Tent's move back one, and `movedIn` leaves the stats. A version 9
save also loses its wild places, the captain, the snack pouch and every level and skill; a Training Yard comes down with
its whole price back (450 shells, 50 wood); each driftling moves into a hut the way the nests were filled before (the
comfiest first, in the order they came) and the ones left over are sold as the pen's are; its tips on the old sailing
steps move on with the rest; the questline starts again at its first quest. Its driftlings and their mutations, its
buildings, paths and stores are kept (a cleared wild place goes with the rest). A version 8 save also drops its boat and
its sea chart; a version 7 save also starts the questline; a version 6 save's driftlings each roll their mutations once
(from their kind and id: the same every load); a version 5 save's tips move to the new steps; an older save (the game
studio's) keeps the founder's look, the settings and its start date and begins a fresh island with the tips.

`tests/Career.luau` plays a sensible player through the same rules (`Logic/*`) for three seeds and three hours. Every
five seconds they hatch the rarest egg under the tree they can afford (the cheaper first among eggs of one rarity):
into a hut with room while a building has a free place or the egg is better than common, or, with every hut full, in a
swap for their weakest when the egg is two rarities better than it. Then they build what the island lacks: the tips'
buildings first (a camp, a patch, a hut, a stall), then a hut while every hut is full and there are places at work
(at the huts' limit, a bigger hut in the smallest one's place, or where there is room once the small one is cleared),
wood while it comes slowly or while saving for the next building would take over half an hour, a shop a tier, a farm more than the tier, a building for the knack with the most
driftlings resting or working away from their knack (moving those to it once it stands, as a player would), and decor
with wood to spare. The catalog has plenty of cheap decor, so the decor stops at a
third of the piece limit and two thirds stay for buildings (a player decorates, but not before the huts), and the
player builds nothing that needs water. Once the island is going they save up for the next tier, and they
expand as soon as they can (the extra eggs laid at once). Its random numbers are seeded through a hash, as the server
seeds a session (a small seed's first draws are weak). `tests/specs/Economy.spec.luau` holds the economy to these
bounds (in brackets what the three seeds measure):

- a driftling at work within 3 minutes (20 seconds), a rare one hatched within 20 (3 to 4 minutes);
- a steady supply: at least 12 hatched by half an hour (37 to 47), an epic within two hours (11 to 17 minutes); a
  legendary comes at 23 to 37 minutes (no bound);
- selling helps but the island earns: under two thirds of the shells over three hours come from selling (under a
  thousandth: 330 to 440 shells of 0.9 to 1.4 million);
- the island's second tier within 25 minutes (5 to 6), the third within 50 (26 to 32); at an hour, at least 12
  driftlings in huts (40 to 50); Harbor Town (tier 4) not before 50 minutes (57 to 65), Coral City (tier 5) not before
  90 (98 to 107), Sunspire Capital (tier 6) not before two and a half hours (2 hours 33 to 2 hours 47), and nothing
  past it within three hours;
- both stores are being made at every ten minutes of the three hours, they stay finite, and the save has no food.

Harbor Town went from 130,000 to 150,000 wood with the conveyor tide, when one seed reached it in 91 minutes. With the
eggs and the huts' limit it moved out of reach (one seed at 118 minutes, the other two not in three hours), and the
islands sat on a Grand Isle for most of the second and third hours. The ten tiers brought it down to 60,000 and the
city tiers with it, so every seed has the town in the second hour and one reaches Coral City in the third. Letting any
driftling work anywhere (2026-11-13) changed little: a driftling with no room at its knack now works somewhere else
instead of resting, and the Career still builds for its knack and moves it there once that stands, so Harbor Town came
about ten minutes later than before and Coral City half an hour later.

The cheaper work and hut buildings (2026-11-13, `Tuning.BuildingPrice` 0.3) moved everything up. At the new prices the
old Career ran short of wood: it built wood only while wood came in slowly, a few cheap camps were enough for that, and
then it sat saving for the next tier (one seed never reached the town in three hours). It now builds wood too while
the next thing would take over half an hour to save for. With that Career at the old prices the town came at 71 to 83 minutes and Coral City at 125 to
137; at the new prices they come at 57 to 60 and 100 to 105, and every seed reaches Sunspire Capital before three hours.
So the bounds moved by about a quarter. Eggs turning rarer as they hatch (`Tuning.EggUp`, the same day) moved little
on its own: at 10%, 8%, 6% and 4% a step one seed reached the capital a minute inside the bound, so the chances went
down to 6%, 4%, 2.5% and 1.2%; the first legendary moved earlier (from 80 minutes for one seed to 23 to 37 for all
three), mostly because every hatch draws one more random number and the seeds' later rolls fall differently. By three
hours the seeds have hatched 162 to 168 driftlings and house 100,
the huts' limit, and the shells get spent: they hold 24,000 to 284,000.

## 11. Polish and animation

> The request (2026-11-12, later): "detail the island on the loading screen more, it should be uneven like the actual
> island. the reflection of the sun on the water should be polished more, same with the dithered gradient of the
> background, dither it better"

- **The loading card's island** has the real island's coast: the oval pushed in and out by the same four sines as a
  first tier island (Data/Street), seen from the world camera's height. Inland of the shore: wet sand, a beach that is
  wider in front (lit along its back edge, a small dark step down to the wet sand in front, grains and a few shells),
  then grass in darker and lighter patches with tufts and flowers, its front edge a darker lip. Out from the shore: a
  broken line of foam, the shallows lighter near the shore with a broken line of surf further out, dithered into the
  sea. Rocks with an ink outline sit at the waterline and driftwood lies on the beach (the dirt path and the jetty went
  with the docks on 2026-11-13). The sprites on it were moved where the new coast came too close.
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
  front, the grass). On it the game's own models, drawn ahead of time through the game's picture path (the
  preview scenario `ploadingart` bakes them frame by frame into `src/first/LoadingArt`): the Tree of Life at the
  back rising over the sea, its hollow, fruit and runes glowing and dimming (on a short screen, a phone held flat, it
  stands at the back on the left so its crown stays clear of the bar; a tall palm stood there while the tide ran),
  palms, a Driftling Hut, a Cozy Burrow, Tiki
  Torches, Flower Beds and Round Bushes, the campfire flickering and throwing embers, a Conchy cheering by it, a
  Frondle and a Pebblit wandering up and down the island with a Mossbun and a Clawdle at their heels, a Gullfin
  hopping along the front (no villagers since 2026-11-12); the old boat rocking past out at sea, gulls crossing the
  sky, stars twinkling, wave crests and glints of sun coming and going. Over the sky, centred: "Driftling Isle" in the
  pixel font's big face, a status that follows the real loading ("Waking up your island", "Finding your island",
  "Drawing your island", dots counting after it), a progress bar in a frame of planks, and at the foot a tip on an
  ink plate, a new one every few seconds ("Wood pays for building. Shells hatch eggs.", "The Tree of Life lays new
  eggs every few minutes.", "Rare driftlings work much faster than common ones.", "When the huts are full, swap a weak
  one for a better one.", "Blue-spotted eggs hatch rare ones. Keep some shells for them.", "Grow the island and the
  tree lays more eggs, and better ones."). Everything is laid out from the screen's size each time it changes (the old
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
  ("+12"); the day chip's clock bar creeps along and its sun sets into a moon; the bar on the tree's card runs down to
  its next eggs; a new tip bounces in; a new day's banner (every few hours) drops in with a ding.
- **The island lives:** the hut driftlings walk to their buildings and back and work there, and nap at their huts with
  nothing to do; one just hatched steps out of its egg under the tree with a cheer and walks off to work. Round each
  tree new eggs rise out of the lawn every few minutes and the old ones sink, the eggs rock now and then, and a hatched
  one shakes and cracks open (§6).

  > The request (2026-11-11): "there are also no proper animations for creatures and villagers that are working on
  > something in the island"

  Work is a loop of real moves now (`DriftModels`' work moods), each building its own. (Until 2026-11-12 villagers
  worked beside the driftlings with a hoe, an axe, a line and a tray; their poses are still in `CharacterModels`.)
  A driftling pecks at the ground in the fields,
  dips its head for fish at a pier, leans in and pushes at the wood, waves and chatters at the shops, and naps at a hut (eyes shut, low and breathing slowly, for longer). Workers stand along the
  building's front, apart, turned three-quarters to the view so the work reads.
- **The sea lives:** the water rolls and the foam laps the shore (§8; the crests a light blue, as asked on 2026-11-10: "can the green lines of the sea be more of a light
  blue instead?"), leaves
  sway and flags ripple in the wind, sailboats (the boats of §8, their flags fluttering) rock on the swell as they
  cross both ways, gulls cross now and then (from either side, at their own height, weaving and gliding, a
  different crossing each time); each island's campfire flickers and smokes. (No clouds' shadows: the player asked for the "random
  shadow that appears sometimes" gone.)
- **Small lives** (§8.1): birds alight, peck and fly off as you come near, a gull lands on the beach, tufts and
  flowers lean in the gusts, butterflies by day and fireflies at night, leaves drift down from the trees, chimneys
  smoke, the sea glints and a fish jumps now and then.
- **Night falls** and the lamps light up (§8).
- **Sounds** (`Controllers/Audio`): every event plays a free Creator Store sound from Roblox's licensed libraries
  (ProSoundEffects, and APM Music's stingers), none of Random Bakery's, its pitch varied a little, repeats inside a
  short cooldown dropped.

  > The request (2026-11-10): "dont use sounds from the old versions, find and use new ones that fit the island theme"

  The interface is wood and bamboo: a temple-block tap for a click, a bamboo swish as a panel opens and closes, a low
  wooden knock for "no", wind chimes for a notice; shells coming in clack like pebbles (a handful for many); a bubble
  pops; pages turn; a shaker for a cheer. Building was two quick hammer taps; since 2026-11-13 a piece put down
  sounds like what it's made of (§4.5), a wooden one still with the hammer's tap.

  > The requests (2026-11-10): "remove the victory sound whenever a fight finishes"; "the victory sound and wherever
  > it plays in such as a villager coming is too noisy, find one with a small short chime instead"; "the building
  > sound is also too, long, make it short"

  > The request (2026-11-12): "use different sounds for newcomer, victory and other sounds that use sounds made by
  > you or was default roblox sounds. use sounds from the free roblox library instead"

  The happy moments each have their own small, short sound from the library, measured for length and loudness before
  going in (no more one music-box note pitched up or down to stand in for the others): a door bell's ding-dong that
  welcomed a newcomer (silent since the villagers went); a bell-tree run as the island grows, or when the tree lays an
  epic or legendary egg; a sparkling sweep for a new lot of eggs and for a rare one or better hatched; a soft cluster of
  chimes when a Hatchery's egg hatches; a few bright sparkle tones when a piece is replaced by a better one; one triangle ting for a
  reward (a quest claimed); a music box winding up as a Hatchery's egg is laid. (The sounds of the places and the fights went
  with them, 2026-11-12.) Longer takes play only their first moment and fade out.

  Your founder's feet are the game's own too: Roblox's built-in footstep, jump and landing sounds are switched off
  (an empty `RbxCharacterSounds` script takes their place) and the founder steps softly on the lawn, crunches on the
  sand and knocks on wooden boards, splashes through a river and strokes through the sea, a step a stride (quicker when running,
  several takes so no two steps in a row are the same), with a cloth flap for a jump and a soft thump on landing.

  > The request (2026-11-10): "also, find new sounds from the roblox free library to use. try to find fitting ones"

  The islands and the sea: a hammer on wood when a wooden piece goes up, gulls squawking as a flock passes over, the
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
