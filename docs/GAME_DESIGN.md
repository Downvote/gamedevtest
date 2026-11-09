# Byte-Size Studio: Game Design

> The first request (2026-11-06): "Read docs/WORKFLOW.md and tools/README.md, then let's design a new game using its
> style and rules as a base. use its pixel art style and filters and isometric style, along with its build system and
> formats. reference game dev story from kariosoft and make a simplified version of it in gamedevtest. dont touch the
> "test" repo at all, only use it for reference"

> The redesign (2026-11-09): "scrap the whole system. can  i make the gameplay loop as such: rng system, where an idea
> team thinks of random ideas to do, allowing players to discover genres and ideas with different modifiers that they
> can get randomly that boost certain aspects of it.  (1 in x, etc.) the player can then choose to make a game based on
> the ideas gotten which are listed in an idea board. the player can combine 3 ideas into one game, in which the player
> has to play 3 minigames based on the ideas they are using. there should a vast variety of minigames themed around the
> idea, just like warioware, and some can be reused but have a higher difficulty. modifiers also change the minigames
> to be played differently. the higher the rarity, the harder the minigames will be. succeeding in all 3 minigames
> will boost sales up to double, each one adding a 33% boost if won. the player can retry at any point or after they
> finish as well. Once the minigames are done, the game is launched, which generates income passively. coins can be
> used to boost the idea team, with an upgrade for increasing the roll speed of ideas and  another upgrade for chance
> of getting rarer ideas. there is no need for other details or upgrades of any kind, but customizing player and
> spending money to decorate your plot is still ok."

Byte-Size Studio is a small game-studio game for Roblox: an RNG game about ideas. Your idea team thinks up random
ideas, each one a genre or a theme with a modifier and a rarity ("1 in 3,200"); you make games out of three of them
by playing a short, themed microgame for each; a launched game earns coins for good; coins make the idea team faster
and luckier. The old studio (crew, research, reviews, platforms, offices) is gone. The look, the build system and the
file formats come from our own Random Bakery (`Downvote/test`): the 2:1 pixel-art isometric diorama seen through the
pixel filter, the pixel font, Rojo with strict Luau, a server that decides everything, pure Data/Logic modules with
specs, and the fake-engine simulator and preview tools. The microgames follow the WarioWare kind of game (a one-word
order, a few seconds, win or lose) with our own content.

Numbers below are the starting balance. `src/shared/Config/Tuning.luau` holds every number the game uses and wins
when this document disagrees.

## 1. The loop in one paragraph

The idea team (three chibis at their desks) thinks up an idea every few seconds: an idea (Puzzle, Pirates, Dinosaurs...)
with a modifier (Plain, Turbo, Tiny, Shaky, Glitched, Haunted, Cosmic), rolled by its odds. Ideas collect on the idea
board (12 places). Pick three and make a game: each idea brings its own microgame, harder the rarer the idea, played
differently under its modifier. Each microgame won adds a third to the game's sales (all three: double); retry any of
them as often as you like, then launch. The game earns coins every second from then on, its income set by how rare
its ideas are and how many microgames were won. Spend the coins on the idea team (faster ideas, luckier ideas) and on
decor for your plot.

## 2. Look and feel

- **World:** one office per player, a cut-away diorama (floor, two back walls, furniture, desks with monitors) on a
  plot along a shared street, seen from the Random Bakery camera: orthographic, yaw 45°, pitch 30°, the 2:1 pixel-art
  "isometric" grid. Everything is built from parts in code (no meshes, decals or uploaded images).
- **Pixel filter:** the same pipeline as Random Bakery's: a raycast G-buffer baked progressively, three toon bands
  from one sun, sun shadows, a 48-colour palette LUT, a 1 px ink outline, and the characters drawn analytically every
  tick on top with the same projection. One pixel size K for the world, the UI and the text.
- **The idea team:** little chibis typing away at their desks, bits of code ("</>", "{ }", "01") floating up from
  their screens. A new idea pops out of a head in its tier's colour; a rare one makes them cheer.
- **Interface:** pixel-art plates with stepped corners, the pixel font from Random Bakery, no borders; each idea has
  a 16x16 icon (and an 11x11 one for the HUD's lists and Tiny), drawn by the rules below.
- **The founder:** you walk the street as a chibi founder in the team's style (§8, §9).

**The pixel art rules** (they hold for every sprite, icon, scene and effect, now and from now on):

> The request (2026-11-09): "for pixel art, always dont use mixels. use pixel art techniques such as anti-aliasing,
> avoiding jaggies, and avoiding mixels, and use a 1 pixel outline. respect the pixel art grid. polish the minigames
> much much more"

- **No mixels.** One art pixel is one UI px is one K-sized block on the screen: nothing is ever drawn scaled up
  (no 2x or 3x sprites). A bigger or smaller thing is its own sprite drawn at its own size: an icon is 16x16, its
  small version 11x11. The microgames are 3D (§5) and drawn by the pixel filter like the office, so they keep the
  same grid, palette and outline.
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

## 3. The idea team and time

- The team thinks up an idea every `Studio.rollEvery` seconds: `Tuning.RollBase` (8 s) at the start, x0.92 for each
  level of the speed upgrade, down to `Tuning.RollMin` (1 s). The HUD's chip counts down to the next one.
- The clocks run while you are in the game, whatever you are doing (menus, cards, microgames, Build mode hold
  nothing). Nothing happens while you are away: no ideas, no income.
- The team is three (`Tuning.TeamSize`, the garage's desks). It never grows: the two upgrades make it better.

## 4. Ideas, modifiers and rarity

**Ideas** (`Data/Ideas`, 24): ten genres and fourteen themes, each with its own odds (its "1 in N") and its microgame
(§5).

| Commons (1 in 7-12) | Uncommon (1 in 15-40) | Rare (1 in 60-150) | Epic (1 in 400-1,000) | Legendary (1 in 3,000+) |
|---|---|---|---|---|
| Action, Puzzle, Animals, Space, Cooking, School | Adventure, Racing, Sports, Pirates, Farming, Ocean | RPG, Fantasy, Rhythm, Robots, Ninjas, Zombies | Strategy, Horror, Dinosaurs, Detectives | Simulation (1 in 3,000), Music (1 in 6,000) |

**Modifiers** (`Data/Modifiers`, rolled on their own after the idea): each multiplies the idea's income and changes
how its microgame plays.

| Modifier | Odds | Income | Its microgame |
|---|---|---|---|
| Plain | the rest (about 2 in 3) | x1 | as it is |
| Turbo | 1 in 5 | x1.2 | everything 1.35x faster, on a fuse 0.8x as long |
| Tiny | 1 in 12 | x1.4 | everything small: the targets shrink (3D things, still drawn on the pixel grid), the windows narrower |
| Shaky | 1 in 30 | x1.7 | the screen shakes |
| Glitched | 1 in 80 | x2.2 | it blinks out for a moment, now and then |
| Haunted | 1 in 250 | x3 | dark: only a roving spotlight shows it |
| Cosmic | 1 in 1,000 | x5 | Turbo, Shaky and Glitched at once |

- **The odds** (`Logic/Ideas`, Random Bakery's rule): ideas and modifiers rarer than 1 in 60 (`Tuning.RareOdds`) roll
  at luck / odds; the Uncommon ones (and Turbo, Tiny, Shaky) at 1 / odds; the commonest (the Commons; Plain) share what
  is left, never less than a tenth (`Tuning.CommonFloor`; past that the lucky ones are scaled down to fit). So at
  luck x1 a "1 in 3,000" idea really comes once in 3,000 ideas, and luck x3 makes it three times as likely.
- **An idea's rarity** is its idea's odds times its modifier's: Glitched Ninjas is 1 in 120 x 80 = 1 in 9,600. Its
  **tier** follows: Common (under 1 in 20), Uncommon (from 1 in 20), Rare (250), Epic (3,000), Legendary (40,000),
  Mythic (500,000), each with its colour.
- **The board** holds 12 (`Tuning.BoardSize`). When it is full a new idea takes the place of the board's commonest one
  if it is rarer; otherwise it is dropped. So an idle team keeps the board's best.
- **The Index** (the Index panel) counts every idea the team ever thought of, dropped ones too: each idea's icon (a
  dark "???" until found), its odds, and a dot per modifier lit once found with it. "Found 13 of 168".
- **Reveals:** a Rare idea or better drops a banner in at the top ("EPIC IDEA! New!" the first time, its name, its
  1 in N) with a sound to match and confetti from Epic; over an open panel it is a line in the panel's status bar.

## 5. Making a game: three ideas, three microgames

- **Pick three** ideas on the idea board (Make a game!). The panel shows what the game would earn (with no wins, and
  with three). Make: the three leave the board, and the game gets a title from a word of each ("Treasure Galaxy
  Saga"). One game at a time.
- **The making card** lists the three ideas, each with its microgame's order word, its modifier and its difficulty,
  and Play (or Retry) for each; Play all plays the unplayed ones in turn. Each one won adds a third to the game's sales
  (`Tuning.WinBoost`): all three double them. A retry, at any time (in the middle of one, or after all three), keeps a
  win: the best result counts. Launch! once all three have been played.
- **A microgame** (WarioWare style) plays **full screen, in 3D, with your own founder**:

  > The request (2026-11-09): "make the minigames full screen, have depth and are 3d, using the player's avatar"

  A curtain with the idea's icon and its order word ("Dodge!") covers the screen while the idea's stage is drawn, then
  lifts on it: a little diorama room built from parts like the office (a floor, two back walls cut away, props),
  drawn full screen by the same pixel filter (the 2:1 camera, toon bands, palette, sun shadows, 1 px ink outline),
  with your founder (your look) standing in it and doing the thing: dodging, flipping, petting, walking, sneaking,
  jumping. The HUD steps aside; a strip at the top names the idea, its difficulty and its modifier, and along the
  bottom a rope fuse burns down to its bomb for a few seconds: 6 s at difficulty 1, a quarter second less a level, at
  least 4 s (`Tuning.MicroSeconds...`; the longer ones get more: Repeat!, Sneak!, Build!, and Tap the beat! runs its
  song). WIN or LOSE stamps it while your founder cheers or stumbles, then the making card comes back over the
  street. Arrow keys / WASD, Space or F / J, 1-6, or the on-screen pads, and taps on the things themselves.
- **Each idea has its own stage** (UI/MicroStage): a rooftop in a night city, a road with red and white kerbs, a
  kitchen with a stove and a shelf of jars, a pitch with a crowd and a goal, a torch-lit dungeon, a living room, a
  deck among the stars with craters, a field of soil rows, a graveyard under the moon, a playroom, a classroom with a
  chalkboard, a war table's map, a detective's office, a wizard's tower, a lab with a board of pads, a stage with
  curtains, a beach with a palm and a chest, the sea floor, a meadow path, a desert with a volcano, a disco floor, a
  dojo, a haunted hall with a door, a building site with a crane. The things that move (crates, cones, coins, fish,
  aliens, the cat, the slime, the ghost, the floors) are 3D too and cast blob shadows on the floor.
- **The difficulty** (1 to 8) is the idea's tier, plus a step when its idea reuses an engine another (commoner) idea
  already has, so a reused game always comes back harder. Harder means faster, more of it, smaller windows.
- **Twelve engines, 24 themed microgames** (UI/MicroGames; the reused ones a step or two harder):

| Engine | Ideas (order) | What you do |
|---|---|---|
| dodge | Action (Dodge!), Racing (Steer!) | step your founder left and right between lanes as crates fall from the sky (their shadows show where), or steer the kart round cones coming down the road (a lane always stays open) |
| timing | Cooking (Flip!), Sports (Kick!), RPG (Strike!) | stop the sweeping needle on the green, once to three times: the pancake flips, the ball flies into the net, your founder dashes in and slashes the slime |
| mash | Animals (Pet!) | tap the cat fast enough: your founder pets it, hearts float up |
| whack | Space (Shoot!), Farming (Water!), Zombies (Whack!) | tap what rises out of the craters, soil or graves; from difficulty 4 rockets and kids rise too: leave them |
| pick | Puzzle (Match!), School (Answer!), Strategy (Count!), Detectives (Spot it!) | pick the shape on the pedestals that matches the one over your founder, the chalkboard sum's answer, how many toy soldiers stand on the map, the suspect in the odd coat |
| sequence | Fantasy (Cast!), Robots (Program!), Music (Repeat!) | type the arrows in order (your founder walks them across the lab's board to the flag; Robots' hide after a look; or casts them into the orb over their head); repeat the pads' tune: your founder hops onto each |
| catch | Pirates (Loot!), Ocean (Catch!) | move your founder (a basket on their head) under the falling coins or fish, never the bombs or jellies |
| jump | Adventure (Leap!), Dinosaurs (Jump!) | jump the rocks or cacti coming down the path |
| rhythm | Rhythm (Tap the beat!) | tap each lane as its gem reaches the pad; a few misses allowed |
| slice | Ninjas (Slice!) | tap the fruit thrown up over the dojo; from difficulty 3, not the bombs |
| hide | Horror (Sneak!) | step your founder toward the door only while the ghost looks away |
| stack | Simulation (Build!) | drop each floor swinging on the crane onto the last; what hangs over is cut off and falls |

- **Fair play:** the server starts each microgame (a token, a seed for its content, its difficulty) and records its
  result. A win sooner than 1 s after the start (`Tuning.MicroMinSec`) or a result later than a minute counts as a
  loss; a microgame left open is dropped after a minute. The result itself is the client's word, as in any minigame.

## 6. Launch and income

- **A launched game earns** the sum of its ideas' values times its boost, every second, for good:
  an idea is worth `0.5 x odds ^ 0.35 x its modifier's income` coins a second (Action: 1/s; Music: 10.5/s; Cosmic
  Music: 52/s), and the boost is `1 + wins / 3`. A first game of three Commons earns about 3/s, 6/s with three wins.
- The income is paid every second (`Tuning.IncomeTickSec`). The launch card shows it ("+8.4/s coins") and the team
  cheers with it over their heads. The Games panel lists the newest 50 games; every game ever launched keeps earning.

## 7. Upgrades (the idea team)

Two upgrades, nothing else (Upgrades panel):

- **Faster ideas:** an idea every 8 s x 0.92 per level, down to 1 s (about 25 levels). Price 50 x 2.5 ^ level.
- **Lucky ideas:** luck +0.2 per level (x1 at level 0): Rare and rarer ideas and modifiers come that much more often.
  Price 80 x 2.5 ^ level.

Coins also buy decor (§9).

## 8. The street

> The request (2026-11-06): "could you also make an overworld and plot, just like the baking game?" Asked how far the
> plot's decorating should go, the user chose "Street + build mode": the street, walking and visiting, plus a Build
> mode for outdoor decor; no path, water or fence drawing yet.

Like Random Bakery's street of bakeries, every studio on a server stands on its own plot in one row along a road
(`Data/Street`): six plots (`Tuning.MaxPlots`, the server's size), 80 studs apart, centred on the road's middle. An
empty plot is an empty lot: meadow, a low white fence along the front and an "Empty lot" sign. A player who joins
takes the lowest free plot; one who leaves leaves an empty lot (their save keeps everything).

- **The road** runs the street's whole length on the plots' south side (the side the camera sees): a pavement, the
  road with its dashed line, a second pavement, a grass verge with trees and lamp posts; a hedge and a lamp at both
  ends, and invisible walls round the world so nobody walks off its edge.
- **A studio's plot** (§9) is lawn round the office, a shade lighter than the meadow; a footpath of stepping stones
  runs from the office's doorway down to the pavement, the plot sign (the studio's name floats over it) and a mailbox
  stand by the pavement.
- **The founder:** each player walks as a little chibi in the team's style (their look is kept in the save and set in
  the Looks panel, §9), on their Roblox character (jumping is off; the avatar itself is hidden). They appear on their
  own footpath. Their name floats over them for the others.
- **The camera** keeps the office-sized view: on a lot it frames that lot like your home view; on the road it follows
  you, keeping you clear of the screen's edges and the HUD. The pixel filter scrolls its picture with the view and
  casts only what comes into sight. A **Home** button shows while you are away and puts you back on your footpath.
- **Visiting:** you can walk into any studio and watch its idea team at work. Tapping a plot sign shows a card: "Bo's
  Studio: 12 games, rarest idea 1 in 9,600, earning +340/s". Every action only ever changes your own profile.

## 9. The plot, Build mode and your looks

- **The plot** (`Data/Street` PLOT) is the garage's: 40 x 42 studs, down to the pavement and mostly in front of and
  east of the office. (A studio from before the redesign keeps the room it had, the Loft or the Studio Floor, and its
  bigger plot.)
- **Decor** (`Data/Decor`, 15 pieces, all on sale from the start): Garden Gnome, Flower Bed, Round Bush, Park Bench,
  Street Lamp, Oak Tree, Pine Tree, Bike Rack, Picnic Table, Arcade Kiosk, Fountain, Hero Statue, Satellite Dish,
  Billboard, Food Truck. A piece is **bought once** (1,000 to 200,000 coins); you then place as many copies of it as
  you like, up to the plot's piece limit (20 in the garage).
- **Where a piece stands** (`Logic/Plot`): on whole studs at a quarter turn, wholly on the plot a stud in from its
  edges, off the office, the footpath, the sign and the mailbox, and off every other piece.
- **Build mode** (the HUD's Build button): the view stops following the founder and shows your plot (a drag pans it);
  a tray lists every piece: buy one with a tap, or pick an owned one and tap the lawn: its ghost stands there on a
  footprint, cyan where it fits and red where it doesn't. Place puts it there and keeps it picked for another copy;
  Rotate turns it. Tapping a piece on the plot picks it up: Move here, Rotate, Store or Cancel. Done closes it.
- **Looks** (the Looks panel): the founder's skin, hair colour, hair style and shirt, each stepped with < and >, a
  portrait to preview; Save look. Free.

## 10. The economy, checked

`tests/specs/Economy.spec.luau` plays four three-hour sessions with a sensible player (`tests/Career.luau`: makes a
game of the board's three most valuable ideas as soon as there are three, wins a microgame with a chance falling
with its difficulty, retries a loss once, spends every coin on the cheaper upgrade) through the server's own rules and
holds the pacing to these bounds: a game launched within 90 s and an upgrade within 3 minutes; a Rare idea within 10
minutes, an Epic within 30, no Mythic in the first hour; about ten levels of each upgrade in the first hour (8 to 14)
and a few more by the third (at most 20); by hour three the next upgrade takes 5 to 40 minutes of income and the
income grows less than x6 from hour one to hour three (no runaway); a player who wins every microgame earns 1.5 to 2.8
times as much as one who loses them all. A typical session: the first game at about a minute, a Rare at 1-2 minutes,
an Epic at about 5, a Legendary somewhere between 20 minutes and a few hours; hour one ends at speed and luck level 11
earning about 1,500 a second, hour three at levels 13-14 earning about 5,000. Print one with
`luau tests/career.luau -a <seed> [minutes] [skill]` after the check has built `build/luautest`.

## 11. Out of scope for this version

Trading or selling ideas, more upgrades of any kind (the request: "no need for other details or upgrades"), offline
income, purchases (no game passes or products: `Config/Monetization.luau` holds only the sound ids), music, other
languages (English only; every string goes through `Locale/Lang.t`), drawing paths, water and fences on the plot.

## 12. Polish and animation

> The request (2026-11-06): "make the it more polished and animated as well".

- **Buttons** lighten under the mouse, sink a pixel while pressed, click when used and buzz when disabled.
- **Panels and cards** fade their shade in and rise into place; **notices** slide down into the stack and fade away.
- **The HUD:** the coins count up and their chip flashes when they change; the idea chip counts down to the next idea
  with a bar along its edge; the card's main button (Make a game!, Play!, Launch!) pulses when it is the thing to do.
- **The microgames** (3D, §5): the idea's icon and order word on the curtain; a rope fuse (twisted, ink-edged) burns
  toward its bomb with an animated spark, the bomb blinking near the end. Your founder walks, runs, jumps (knees up),
  swings a sword, hammer, blaster or watering can, pets, casts, dances, sneaks, cheers and stumbles. Coins spin, fish
  wiggle, aliens and zombies sway as they rise, the slime bounces with squash and stretch, the cat breathes, bombs
  fizz, things in the air cast shadows that grow as they fall. Every hit flashes the thing white and throws a burst
  of 1 px bits in its colours; words pop up over the things ("Perfect!" in yellow for a dead-centre hit); a bomb
  flashes the screen. The themes play out: the pancake flips over the stove, the ball arcs into the net, the slime
  is knocked back and bursts, crates smash on the floor, a watered sprout blooms, a laser flashes from the blaster,
  the orb over the wizard grows with each arrow, cut fruit falls in two halves behind a 1 px slash, the ghost bobs,
  turns with red eyes (the room goes red while it watches), floors swing on the crane's rope and what hangs over falls
  off, a perfect drop says so. A wrong move shakes the screen; WIN flashes and brings confetti. The launch card brings
  confetti and a fanfare and the team cheers with the new income over their heads.
- **The office:** bits of code float up from the screens; a new idea pops out of a head in its tier's colour; rare
  reveals drop in with a fanfare and confetti.
- **Sounds** (`Controllers/Audio`): every event plays a Creator Store library sound (the ones Random Bakery uses,
  `Config/Monetization.Sounds`), its pitch varied a little, repeats inside a short cooldown dropped.
