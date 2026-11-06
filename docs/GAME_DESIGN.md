# Byte-Size Studio: Game Design

> The request (2026-11-06): "Read docs/WORKFLOW.md and tools/README.md, then let's design a new game using its style
> and rules as a base. use its pixel art style and filters and isometric style, along with its build system and
> formats. reference game dev story from kariosoft and make a simplified version of it in gamedevtest. dont touch the
> "test" repo at all, only use it for reference"

Byte-Size Studio is a small game-studio management sim for Roblox. Kairosoft's *Game Dev Story* is its reference
for the **loop**: hire a crew, pick what to make, watch them work, then sweat through the reviews and the sales.
The content is our own: the names, platforms, critics, genres, numbers and art are not taken from that game. The look,
the build system and the file formats come from our own Random Bakery (`Downvote/test`): the 2:1 pixel-art
isometric diorama seen through the pixel filter, the pixel font, Rojo with strict Luau, a server that decides
everything, pure Data/Logic modules with specs, and the fake-engine simulator and preview tools.

Numbers below are the starting balance. `src/shared/Config/Tuning.luau` holds every number the game uses and wins
when this document disagrees.

## 1. The loop in one paragraph

You open a tiny studio in a garage with two developers and a little money. You pick a **genre**, a **topic**, a
**platform**, a **size** and a **focus**, and your crew sit down at their desks and type. Every game week they add
points to the game's four scores (Fun, Ideas, Graphics, Sound), and now and then one of them has a spark and a big
number pops out of their head. Bugs creep in too. When the build is done you can polish (fix bugs) or ship at once.
Four critics review it out of 10 each; a total of 32 or more puts it in the Hall of Fame. Then it sells week after
week, bringing money and fans. Money pays salaries and rent, trains your crew and moves you into a bigger office
with more desks; research points (earned while developing) unlock new genres and topics; new platforms come out as
the years go by. Each year ends with an awards night for your best game.

## 2. Look and feel

- **World:** one office per player, a cut-away diorama (floor, two back walls, furniture, desks with monitors) on a
  small lot, seen whole and centred from the Random Bakery camera: orthographic, yaw 45°, pitch 30°, the 2:1
  pixel-art "isometric" grid where floor edges step two pixels across for one down. Everything is built from parts
  in code (no meshes, decals or uploaded images).
- **Pixel filter:** the same pipeline as Random Bakery's: a raycast G-buffer baked progressively (4×4, 2×2, every
  pixel), three toon bands from one sun, sun shadows, a 48-colour palette LUT, a 1 px ink outline where parts meet,
  and the crew drawn analytically every tick on top with the same projection. One pixel size K for the world, the UI
  and the text (2 screen px on phones, 3 at 1080p, 4 at 1440p).
- **Crew:** little chibi developers sitting at their desks: they type (arms bob), glance at the screen, stretch, and
  doze off with a "z" when they are worn out. Their monitors flicker with code while a game is in development.
- **Interface:** pixel-art plates with stepped corners, the pixel font from Random Bakery, no borders. Popups float
  up over the crew's heads in the score's colour ("+12" Fun in pink, Ideas in yellow, Graphics in blue, Sound in
  green, "Spark!" bigger and gold).
- **The founder:** you walk the street as a chibi founder in the crew's style (§12); the camera holds still on your
  office while you are home and follows you when you walk out.

## 3. Time

- The calendar is Year / Month / Week: 4 weeks a month, 12 months a year, starting Year 1, Month 1, Week 1.
- One game week passes every `Tuning.WeekSec` (4 s) of real time while you are in the game. Time stops when you
  leave: nothing happens offline (salaries included), so nobody comes back to a bankrupt studio. It also stops while
  a menu or a card (the reviews, the awards) is open: the client tells the server, which holds that player's clock,
  so reading a menu on a phone never costs weeks.
- Monthly (on week 1 of each month): salaries and rent are paid, three new job candidates arrive.
- Yearly (after the last week of month 12): the awards night.

## 4. Money, fans and research

- **Money** starts at $40,000. It can go negative (salaries are always paid); while it is negative you cannot hire,
  train, move or advertise, and the only game you can start is the **safety net**: a Small game for the Home PC,
  free. So no studio is ever stuck with nothing to sell (the first tuning runs went broke in year one and could never
  start another game).
- **Fans** grow from sales (`FanPerCopy` per copy sold, more for a Hall of Fame game) and ad campaigns. Fans buy your
  next game in its first weeks and unlock the bigger offices.
- **Research points (RP)** come from development: every developer earns 1 RP per week of work, a spark 2 more.
  RP unlock genres and topics and pay for training.

## 5. The crew

Each developer has four skills, an energy bar, a salary and a look.

| Skill | Feeds |
|---|---|
| Code | Fun (half), bug fixing, fewer bugs |
| Design | Fun (half), Ideas |
| Art | Graphics |
| Sound | Sound |

- **Hiring:** three candidates a month, their skills 4-40 each plus 3 a year after Year 1. Hiring costs one month's
  salary up front. You can have as many developers as your office has desks (3, 5, 8).
- **Salary** per month: $300 + $12 per skill point (a beginner with 80 skill points costs $1,260 a month).
- **Energy** 0-100: -6 a week while working, +12 a week while idle. Under 25 a developer works at half speed and
  dozes at the desk. A **pizza party** ($400 a developer, once a month) fills everyone's energy.
- **Training:** 15 RP and $2,000: +4 to +6 in one skill (more for a lower skill), -20 energy. Skills top out at 250.
- **Letting go:** a developer can be let go at any time (nothing is refunded). The last developer stays.
- Two developers start with you.

## 6. Making a game

### 6.1 Choices

- **Genre** (10): Action, Puzzle, Adventure, RPG, Racing, Sports, Simulation, Strategy, Rhythm, Horror. Action,
  Puzzle and Adventure are open at the start; the others cost 30 or 60 RP.
- **Topic** (14): Space, Fantasy, Animals, Pirates, Robots, Ninjas, Cooking, School, Zombies, Dinosaurs, Detectives,
  Farming, Music, Ocean. Four are open at the start; the others cost 20 or 40 RP.
- **Combo:** every genre and topic pair is a Great, Good, Okay or Poor match (×1.3, ×1.1, ×1.0, ×0.8 on quality).
  You only learn a pair's match by releasing a game with it; the Research screen's notebook keeps what you learned.
- **Platform:** each has a licence fee (paid when the game starts), a market size (how many people can buy it), one
  or two genres its players love (×1.1 quality) and the years it is on sale:

| Platform | Years | Licence | Market | Loves |
|---|---|---|---|---|
| Home PC | 1- | $0 | 1.0 | Strategy, Simulation |
| Pocket Pal (handheld) | 1-10 | $6,000 | 1.2 | Puzzle, RPG |
| Byte Box (console) | 3-14 | $20,000 | 1.8 | Action, Sports |
| Smartphone | 5- | $8,000 | 2.2 | Puzzle, Rhythm |
| Orbit VR (headset) | 9- | $60,000 | 2.0 | Action, Simulation |
| Cloud Arcade (streaming) | 13- | $120,000 | 3.2 | Racing, Adventure |

- **Size:** Small (8 weeks of build, $2,000), Medium (14 weeks, $12,000), Large (22 weeks, $40,000). Bigger games
  sell for more per copy ($10 / $18 / $30) and the critics expect more of them.
- **Focus:** one of the four scores; that score gets +30% and the others -10%.
- **Title:** made from the topic's and genre's words ("Galaxy Blocks", "Pirate Quest"); Shuffle picks another. A
  second game with the same title is a sequel ("Galaxy Blocks 2").

### 6.2 Development

- **Build:** every week each developer adds to the four scores: Fun `(Code + Design) / 2 × 0.5`, Ideas
  `Design × 0.5`, Graphics `Art × 0.5`, Sound `Sound × 0.5`, each times a random 0.7-1.3, times 0.5 when tired,
  times the focus. A crew of n works like n^0.75 developers (they talk, they wait for each other), so a bigger crew
  is better but not linearly. With 8% chance a week a developer has a **spark**: one score gets 3× that week and
  +2 RP.
- **Bugs:** each developer adds a bug a week with chance `1 - Code / 150` (at least 10%).
- **Polish:** once the build weeks are done the game is ready to ship. While you wait, every developer fixes
  `1 + Code / 30` bugs a week (rounded down) and adds a little to the scores (a fifth of the build rate).
  Release is up to you; a game with no bugs left says "Ready to ship!".
- A game in progress cannot be cancelled in this version.

### 6.3 Reviews

- **Quality** `Q = (Fun + 0.8 Ideas + 0.8 Graphics + 0.6 Sound) × combo × platform love × novelty - 25 × bugs`.
  Novelty is ×0.85 when the same genre and topic pair was one of your last three games.
- **Expectation** `E = 600 × size factor (1, 1.8, 3) × (1 + 0.3 × (year - 1))`: the critics expect more each year.
- **Base score** `s = 1 + 9 × (1 - 2^(-Q / E))` (Q = E gives 5.5).
- **Four critics**, each with a favourite score: Pixel Pete (Fun), Ada Quill (Ideas), Max Render (Graphics) and
  Echo Lane (Sound). Each gives `s` plus up to ±1 for how much of the game is their favourite score, plus a small
  seeded wobble (±0.6), rounded, 1-10.
- **Hall of Fame:** a total of 32 or more out of 40.

### 6.4 Sales

- Week 1 copies: `(800 × market × size factor (1, 1.5, 2.2) + 0.1 × fans) × (average / 5)^2`, where average is the
  total / 4. Each later week sells `decay` times the week before, `decay = 0.70 + 0.025 × average` (0.725-0.95).
  Fans buy a share of week one rather than raising the base: an earlier draft fed fans into sales into fans and
  grew without bound.
- A game is on sale until a week sells under 5 copies or 40 weeks pass.
- The studio keeps 70% of the price of every copy; fans grow by 0.08 per copy (0.1 for a Hall of Fame game).
- Several released games sell at once; the Games screen lists every game with its scores, copies and money.

## 7. The office

| Office | Desks | Rent / month | Move | Needs |
|---|---|---|---|---|
| Garage | 3 | $1,000 | start | - |
| Loft | 5 | $3,000 | $120,000 | 3,000 fans |
| Studio Floor | 8 | $8,000 | $500,000 | 25,000 fans |

- Moving rebuilds the diorama: a bigger room, a new floor and walls, more desks and more furniture.
- **Ad campaign** (once a month): `$4,000 × office` → `250 × office` new fans (a flat amount: a share of the fans
  compounded every month).
- **Pizza party** (once a month): see §5.

## 8. Awards

After the last week of each year the studio's best game released that year is judged: a total of 34 or more wins
**Game of the Year** (+30% fans, +$20,000 × year); 28 or more wins **Critics' Choice** (+10% fans,
+$5,000 × year). Otherwise the night passes quietly.

## 9. First steps (the tips banner)

A short banner guides a new studio: (1) "Tap New game to make your first game", (2) while it is in development
"Your crew is working: watch the ideas pop!", (3) when the build is done "Polish fixes bugs. Release when you're
ready!", (4) after the first reviews "Hire more crew in Staff", then it goes away for good.

## 10. The economy, checked

`tests/specs/Economy.spec.luau` plays six ten-year careers with a sensible player (`tests/Career.luau`) through the
server's own rules (`Logic/Studio`) and holds the balance to these bounds: two or more games in year 1 with middling
reviews (an average total of 15-28) and the studio in the black; the Loft in years 2-4 and the Studio Floor by year 6;
reviews 5 or more points better late than in year 1 and at least one Hall of Fame game; fans that never shrink and at
most ×2.5 a year once past 50,000 (no runaway). Print a career with `luau tests/career.luau -a <seed>` after the
check has built `build/luautest`. A typical career: reviews average about 21/40 in year 1, 25 in year 4, 31 in year 8.

## 11. Out of scope for this first version

Own consoles, game shows and expos, job classes, staff levels, cancelling a project, offline progress, purchases
(no game passes or products yet: `Config/Monetization.luau` is empty), other languages (English only; every string
goes through `Locale/Lang.t` so translations can be added the Random Bakery way). Drawing paths, water and fences on
the plot (Random Bakery has them) and dressing the founder are left for later.

## 12. The street

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
- **A studio's plot** (§13) is lawn round the office, a shade lighter than the meadow so the land shows; a footpath of
  stepping stones runs from the office's doorway down to the pavement, the plot sign (the studio's name floats over
  it: "Ava's Studio") and a mailbox stand by the pavement.
- **The founder:** each player walks as a little chibi in the crew's style (a random look of their own, kept in the
  save), on their Roblox character (jumping is off; the avatar itself is hidden). They appear on their own footpath.
  Their name floats over them for the others.
- **The camera** keeps the office-sized view: at home (on your own lot, in the home view's middle) it holds the home
  view; off your lot it follows you, keeping you out of the screen's edges, and glides home when you come back. The
  pixel filter scrolls its picture with the view and casts only what comes into sight (no re-bake while you walk).
  A **Home** button shows while you are away and puts you back on your footpath (once every 3 s).
- **Visiting:** you can walk into any studio and watch its crew at work (typing while it has a game in the works,
  dozing when tired). Tapping a plot sign shows a card: "Bo's Studio: Loft, 12 games, best 34/40, a game in the
  works". You can't touch another studio's things: every action only ever changes your own profile.
- Your studio runs on while you walk: the clock keeps going (only menus, cards and Build mode hold it).

## 13. The plot and Build mode

- **The plot grows with the office** (`Data/Street` PLOT): the Garage's is 40 x 42 studs, the Loft's 50 x 44, the Studio
  Floor's 60 x 46, always down to the pavement and mostly in front of and east of the office (the sides the camera
  sees). The office stands near its back.
- **Decor** (`Data/Decor`, 15 pieces): Garden Gnome, Flower Bed, Round Bush, Park Bench, Street Lamp, Oak Tree, Pine
  Tree, Bike Rack, Picnic Table (from the Garage), Arcade Kiosk, Fountain, Hero Statue (from the Loft), Satellite
  Dish, Billboard, Food Truck (from the Studio Floor). A piece is **bought once** ($200 to $40,000) and its fans join
  the studio then (5 to 1,000: a small, one-off bonus); you then place as many copies of it as you like, up to the
  plot's piece limit (20 / 32 / 48 by office).
- **Where a piece stands** (`Logic/Plot`): on whole studs at a quarter turn, wholly on the plot a stud in from its
  edges, off the office (its room, walls and a stud round them), the footpath, the sign and the mailbox, and off every
  other piece. Pieces don't block the founder.
- **Build mode** (the HUD's Build button): the clock holds; the view stops following the founder and shows your plot
  (a drag pans it over the plot); a tray lists every piece: buy one with a tap, or pick an owned one and tap the lawn:
  its ghost stands there on a footprint, green where it fits and red where it doesn't. Place (or a second click on the
  same spot) puts it there and keeps it picked for another copy; Rotate turns it. Tapping a piece on the plot picks it
  up: Move here, Rotate, Store (back in the box) or Cancel. Done closes it.
- **A bigger office** (a move): the plot grows, and pieces the bigger room now covers go back in the box.
