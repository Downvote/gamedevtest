# Driftling Isle: Architecture and Implementation Contract

The contract for the code in this repository (GitHub `Downvote/gamedevtest`). `docs/GAME_DESIGN.md` says what the game
does and why; this file says how the code is laid out, what each module offers and which data goes where. Where the
two disagree on an API, a type or a name, this file wins; on a number, `src/shared/Config/Tuning.luau` wins.

The build system, the conventions and much of the rendering code come from Random Bakery (`Downvote/test`, used
read-only as the reference: nothing there was changed). What was copied, and how it was changed, is listed in §12.

> The request (2026-11-10, GAME_DESIGN quotes it with the choices made): "scrap this idea. could you make replicate
> beasty bay from kariosoft instead? still use the test repo as a reference" (an original island-village game in the
> genre: island building and farming, creature taming, expeditions and battles, villagers moving in, a shared sea)

## 1. Layout and tooling

```
default.project.json   Rojo: Shared -> ReplicatedStorage, Server -> ServerScriptService, Client -> StarterPlayerScripts;
                       characters on (the founder walks the islands; jump power 0)
src/shared/            Types, Net, Config (Tuning, Monetization), Data (content), Logic (pure rules), Render (pure pixel
                       maths, copied), Models (procedural models), Locale (Lang: English only)
src/server/            Main.server.luau, Services/* (DataService, Session, Router, IslandService, PlotService)
src/client/            Main.client.luau, Controllers/* (StateClient, CameraController, WorldView, AvatarView, StreetLife,
                       Audio), Pixel/* (PixelRenderer, BakeCast, PixelText, Snapshot, ImageMemory), UI/* (UIKit, Hud,
                       Menus, BuildUI, ExpeditionUI, Voyage, MicroStage, PixelSprites, ArtData (generated), Words)
tests/                 run.luau (spec runner), TestKit.luau, Career.luau (the Economy spec's player), career.luau (prints
                       its runs), specs/*.spec.luau
scripts/check.sh       the gate every change passes (§11)
scripts/gen_pixelfont.py  the pixel font's glyph tables (copied; README "Fonts and licences")
scripts/gen_art.py     every interface sprite as a text mask -> UI/ArtData.luau (outline, anti-aliasing, shading;
                       `--png <file>` writes a contact sheet; GAME_DESIGN 2's rules; §10.10)
tools/                 setup.sh (installs rojo, luau, luau-lsp), defs/ (Roblox API types), sim/ (the fake engine and
                       this game's scenarios), preview/ (PNG renders of the real game); tools/README.md
```

Rojo 7.4.4 (`rokit.toml`), luau-lsp 1.70.1 with `tools/defs/globalTypes.d.luau`, the plain Luau CLI for the specs.
Every file is `--!strict` (`.luaurc`). `X.server.luau` is a Script, `X.client.luau` a LocalScript, everything else a
ModuleScript; there are no `init.luau` files. (The Rojo project keeps its old name `byte-size-studio`; the place file
is `DriftlingIsle-<short hash>.rbxl`.)

## 2. Rules for the code

- Require by instance path only (`require(script.Parent.X)`, `require(ReplicatedStorage.Shared.Logic.X)`), never by
  string. Pure modules (`Types`, `Config/*`, `Data/*`, `Logic/*`, `Render/*`, `Locale/*`) use only the three forms
  `script.Parent.X`, `script.Parent.Parent.X`, `script.Parent.Parent.Folder.X`, because `scripts/check.sh` rewrites
  exactly those into string requires for the CLI copy the specs run on; they require only other pure modules and
  touch no Roblox API.
- The server decides everything. A client action is one Router request (a name and a payload) checked by
  `Logic/Validate`, answered `{ ok = true, data }` or `{ ok = false, err = ErrCode }`.
- Every number is in `Config/Tuning.luau`; every Roblox id is in `Config/Monetization.luau` (0 = not made yet).
- One function stays under 200 locals and upvalues (luau-compile checks it).
- Player-visible text goes through `Locale/Lang.t` (English only for now; GAME_DESIGN 12).
- Some modules keep the names of the games before this one (the plots along a "street", the island's tiers an
  "office"): `Data/Street` is the islands, the sea and the boardwalk, `Data/Office` the island's tiers (their names),
  `Models/DecorModels` builds every building, `Models/StreetModels` the islands and the sea, `UI/MicroStage` the islets' stages,
  `Models/MicroModels` the driftlings and the stages' things.

## 3. Types (`src/shared/Types.luau`)

`Look`, `Piece` (`{ uid, id, x, z, rot, lvl }`: a building standing on the island; `uid` stays while it stands),
`PlotSave` (`{ placed }`), `Villager` (`{ id, name, look, work (a Piece uid, 0 idle), lvl, xp, seed, day }`), `Pal` (a
befriended driftling: `{ id, sp, lvl, xp, work }`), `Captain` (`{ lvl, xp }`), `Settings`, `Stats` (`{ days, built,
earned, befriended, battles, cleared, movedIn }`), `Profile` (the save, version 6: `shells`, `food`, `wood`, `day`,
`tier`, `founder`, `cap`, `folk`, `pals`, `plot`, `islets` (islands charted: guardians beaten), `sea` (the sea
chart's seed), `boat` (1 .. 6), `chart` (the ids of the chart's islands charted), `seen` (species -> 1 met, 2 befriended),
`nextId` (villagers, driftlings and pieces share it), `tut`, `stats`, `settings`, `createdAt`), `Fighter` (`{ key ("f",
"v<id>", "p<id>", "w<i>"), name, kind, sp?, look?, lvl, hp, maxHp, atk, def, spd, skill, charge }`), `Battle` (`{ foes,
round, boss, shield, foeShield }`), `Isle` (an island at sea: `{ id? (its sea chart id), seed, lvl, kind (Data/Islets), name, wild
(three species), boss, bossName, loot { food wood shells }, reward }`), `Expedition` (`{ isle, node, nodes, done,
party, loot { shells food wood }, battle?, befriended, over? ("home" | "won" | "lost") }`), `ClientView` (the profile's fields plus `dayFrac`, `plot`
(the plot index), `pieces`, `rates` (a day, after eating), `charm`, `beds`, `nests`, `visitors`, `sea`, `boat`, `chart`, `exp?`), `ErrCode` (with `far`: out of the boat's
range),
`Response`, and the utility types `Connection`, `Signal<T...>`, `Rng`, `PixelTier`. The file is the reference for
every field.

## 4. Config

- `Config/Tuning.luau`: persistence (`DataStoreName = "BSS_Profile_v1"`, never renamed), the island (`StartShells`,
  `StartFood`, `StartWood`, `TurnSeconds` (the island's pace), `DaySeconds` (the sea's day: hours), `EatFolk`, `EatPal`, `Hungry`, `IdleOutput`, `PalBoost`, `VisitorCharm`,
  `VisitorsMax`, `ShopVisitors`, `MoveInCharm`, `FolkMax`, `PalsMax`, `Refund`, `UpgradeMult`, `UpgradeCost`,
  `TierCost`), levels and battles (`LevelGrow`, `LevelMax`, `XpBase`, `XpPow`, `XpPerFoe`, `TrainXp`, `PartyMax`,
  `Supplies`, `TreatFood`, `SkillEvery`, `GuardTake`, `ShieldTake`, `FleeBase`, `BossBoost`, `RestHeal`,
  `StageWait`), the islands at sea (`IsleFoodBase` / `IsleFoodLvl`, `IsleWoodBase` / `IsleWoodLvl`, `IsleChestBase` /
  `IsleChestLvl2`, `IsleRewardBase` / `IsleRewardLvl2`: a loot stop's food and wood, a chest's shells and the
  guardian's reward by the island's level; `ChartCharm`, `ChartCharmMax`), the sea chart (`ChartIslands`, `ChartNear`,
`ChartMinDist`, `ChartMaxDist`, `ChartSpacing`, `ChartLvlPerLeague`: GAME_DESIGN 7) and the boat (`BoatRadius`, its
range a level in leagues, `BoatCost` `{ shells, wood }` a level), the server's step and rate limit, the sea (`MaxPlots`, `PlotSpacing`, `PlotPieces`, `HomeCooldown`),
  and the camera and pixel filter values (Random Bakery's `CamYaw` 45, `CamPitch` 30, `PixelTiers`, `PixelScaleMin` /
  `PixelScaleSides`; this game's `CamRayBack`, `PixelMaxRayDist`, `CamFollowBox`, `CamGlide`, `CamBuildPan`,
  `PixelPanRays`, `PixelInvalidateRaysFrame`, `PixelMaxDyn`, `PixelStageBakeMs`).
- `Config/Monetization.luau`: `GamePasses`, `DevProducts`, `Badges` (empty or 0) and `Sounds` (the Creator Store
  library ids `Controllers/Audio` plays: Random Bakery's, and Roblox's free ProSoundEffects clips for the battles,
  the islands and the sea, each named in a comment).

## 5. Data (pure content tables)

| Module | Holds |
|---|---|
| `Data/Palette` | the LUT colours (`order`, `colors`), the shore's `shallow`, `foam`, `rock` and `rock_dark`, the older rooms' floor and wall themes (`themes`, still in the LUT), the light modes, and the UI's colours (`ui`, `axis`, `match`) |
| `Data/Buildings` | the 27 pieces `{ id, name, kind (food wood shop home nest train decor), shells, wood, w, d, rate, eats, job, knack, beds, slots, charm, tier, blurb }`; `list`, `byId` |
| `Data/Creatures` | the 15 driftlings `{ id, name, islet (the kind of island it lives on), hp, atk, def, spd, skill, knack, trust, shape, body, accent, blurb }`; `list`, `byId`, `skills` (their names) |
| `Data/Islets` | the 5 kinds of island found at sea (GAME_DESIGN 7) `{ id, name ("Beach"), plural, stage (its MicroStage set), lvl (the level it turns up from: 1, 5, 10, 16, 23), wild (its three driftlings), first / last (its names' words), color, blurb }`; `list`, `titles` (a guardian's) |
| `Data/Names`, `Data/Looks` | the villagers' names; skin, hair, hair style and shirt lists (`Types.Look` indexes them) |
| `Data/Office` | the island's three tiers (`plans[tier]`: `{ tier, name }`, Castaway Cay, Palm Isle, Grand Isle: the island card's title), `plan(tier)`, `origin(plot)` (Data/Street's). The island has no house (GAME_DESIGN 8) |
| `Data/Street` | the islands and the sea (GAME_DESIGN 8): `MAX`, `SPACING`; the heights `LAWN_Y` (-0.5: the grass), `SAND_Y`, `WET_Y`, `FOAM_Y`, `SHALLOW_Y`, `WATER_Y` (each band a little lower than the one inside it); the cell layers `GRASS SAND WET FOAM SHALLOW SEA_CELL` and how far past the coast each reaches, `BANDS` (`sand` 2.5, `wet` 3.5, `foam` 4.5, `shallow` 8 studs); `BOARD` / `SEA` (plot-local z bands), `FAR` / `END_FAR` (water past the invisible walls: no sky at the world's edges), `LOT` (a plot's lot), `CENTER`, `PLAZA` (the campfire's plaza), `PATH` (the path to the jetty); the coast: `isle(tier)` (its oval: centre, radii, wobble phases), `coast(tier, x, z)` (studs from the coast, below 0 inland: the oval's radius times a wobble of four sines), `layerAt(d)`, and per whole-stud cell (cached per tier; `cellKey`) `layer`, `cellDist`, `cellBounds(tier)`, `buildable(tier, x, z)` (grass a stud or more inside the coast), `walkable` (grass, sand, wet sand), `plot(tier)` (the grass's bounding box); `origin(i)` (plots centred on x = 0), `plotAt(x, z)`, `bounds()`, `footpath()`, `jetty(tier)` (planks from the island's sand to the boardwalk), `spawn()` (on the path below the plaza), `sign()` / `mailbox()` (either side of the jetty's foot), `LAMPS`, `PIER_X` / `PIER_Z` / `PIER_W`, `pier()` |

Coordinates in `Data/Street` are studs, plot-local, +Y up. The camera looks from the south-east (+X, +Z), so an
island's back is its north-west. A piece's `rot` turns its model (built facing +Z: south, toward the viewer).

## 6. Logic and models

Pure rules (`src/shared/Logic`), all specced in `tests/specs`; every action returns `(true, data?)` or `(false,
ErrCode)` and changes the profile only on success:

| Module | API |
|---|---|
| `Util` | copied from Random Bakery: `hash32`, `newRng(seed)` (xorshift32: `next int range chance weighted`), `pick`, `shuffle`, `Signal`, `round clamp lerp isFinite sig2 deepCopy count` |
| `Island` | the turn and the day (GAME_DESIGN 3, 5): `piece(p, uid)`, `beds`, `nests`, `charm`, `visitors`, `works(id)`, `rates(p, away?) -> Rates` (`{ food, wood, shells, made, eaten }` a turn), `step(p, dt, away?)` (the stores, the food never below none), `randomLook(rng)`, `freeJob(p, knack?)`, `turn(p, rng, away?) -> { movedIn?, trained? }` (a turn's end), `newDay(p)` (a calendar day: the count), `xpTo(lvl)`, `gain(who, xp) -> levels`, `setWork`, `setHelp` (one a building, swapping; driftlings at their knack), `dismiss`, `release`, `expandCost(tier)`, `expand(p)` (data `{ tier, moved, cleared }`: `Plot.refit`), `setFounder` |
| `Plot` | building (GAME_DESIGN 4): `ROTS`, `limit(tier)`, `footprint(id, rot)`, `rect`, `blockers(tier)` (the campfire's plaza and the path to the jetty), `fits(tier, placed, id, x, z, rot, skip?) -> (ok, "outside" (a footprint cell not `Street.buildable`) / "blocked" / "overlap" / "unknown")`, `place` (locked, full, money, wood, blocked; a building that takes workers gets an idle villager), `move`, `upgradeCost(q)`, `upgrade` (max, money, wood), `store` (no_room; `Refund` back), `refit(p) -> (moved, cleared)` (pieces that do not fit move to the nearest free spot, or are cleared with their whole price back: after the island grew and when a save loads) |
| `Battle` | battles (GAME_DESIGN 7): `FOUNDER`, `villagerBase(seed)`, `speciesBase(sp)`, `grow(v, lvl)`, `founder(p)`, `villager(v)`, `pal(x)`, `wild(sp, lvl, i, boss, name?)`, `new(foes, boss)`, `alive`, `treatChance(foe, party, boss)`, `fleeChance`, `round(party, b, act, target?, rng) -> (events, result?)` (events `hit heal shield rally guard treat flee`; result `win lose fled`) |
| `Chart` | the sea chart (GAME_DESIGN 7): `levelAt(dist)`, `islands(sea) -> { ChartIsle }` (`{ id, x, y, dist, lvl, seed }` in leagues from home, nearest first, cached per seed: `ChartNear` within the first boat's range, the rest out to `ChartMaxDist`, `ChartSpacing` apart), `isle(sea, id) -> Isle?` (`Expedition.chart(lvl, seed)` with its `id`), `radius(boat)`, `reachable(p, id)`, `charted(p, id)`, `boatCost(boat)` (the next level's `{ shells, wood }`, nil at the top), `sail(p, id, members)` (bad_payload (no such island), far (out of range), then `Expedition.start`), `upgradeBoat(p)` (max, money, wood; data `{ boat, radius }`) |
| `Expedition` | expeditions: `fighter(p, key)`, `away(e)`, `supplies(n)`, `kindsAt(lvl)`, `speciesAt(lvl)`, `chart(lvl, seed) -> Isle` (the same level and seed make the same island: its kind one of those open at the level, a name of its kind's words, two of its kind's driftlings and a stray from any open kind, a titled guardian of its own, loot and reward from `Tuning.Isle*`), `nodesOf(isle)` (its path from its seed: the landing, six to nine stops with one rest and at least three battles, one more from level 10, the guardian), `levelAt(isle, node)` (a level under the island's at the landing, one more every four stops), `start(p, isle, members)` (full, not_found, food; the island from `Chart.sail`), `next(p, e, rng)` (`{ kind, node, food?, wood?, shells?, foes? }`; in_battle, max), `room(p)`, `act(p, e, act, target?, rng)` (`{ events, result, friend?, xp?, shells?, ups?, reward?, charted? }`: the guardian beaten pays the island's reward and charts it (`first`: its id not yet in `chart`: the whole reward, the id added, `islets` + 1; sailed to again: half); a treat: blocked on a guardian, food, no_room), `home(p, e)` (half after a defeat) |
| `Schema` | `VERSION` (6: the sea chart), `default(now, seed)` (a random `sea`, `boat` 1, an empty `chart`), `migrate(raw)` (1 -> 2: a founder; 2..4 -> 5: the studio gone, the founder, settings and start kept; 5 -> 6: the tips' steps moved (3 -> 5, 4 -> 6)), `reconcile(raw, now, seed)` (any table -> a valid Profile: pieces that exist with unique uids and valid turns, then `Plot.refit` (one off the grass moves onto it), villagers and driftlings with unique ids working only where they may, the Index's species, `nextId` past every id, `sea` a whole number in range, `boat` 1 .. 6, `chart` unique ids of the chart) |
| `Validate` | `ACTIONS` (the action catalogue, §7.3), `request(action, payload) -> (ok, err?)`: exact schemas, unknown and missing fields refused |
| `Numbers` | `int`, `short`, `coins`, `rate`, `perMin` ("+57/min"), `oneIn` |

Models (`src/shared/Models`, Roblox modules):

- `Blocks` (copied): `part(parent, spec)` (anchored, SmoothPlastic or Neon, sizes on the 0.25-stud grid, palette
  colours), `cylY`, `model`, `color`, `snap`.
- `CharacterModels.build(look, name, seed) -> Rig` (a seated chibi, the portraits'; the head's parts with a glint in
  each eye, brows, a mouth and ears, sizes exact to the eighth of a stud), `buildStanding(look, name, seed)` (a
  standing chibi: the founder and the villagers: soles, shoes, bare shins under shorts, a shirt with a belt and buckle,
  a collar and two buttons, sleeves, bare forearms and fists, the head raised a stud), `posePose(rig, base, Pose)`
  (`Pose { lean, twist, crouch (the knees bend to keep the feet down), lift, hipL/R, kneeL/R, armL/R (CFrames about
  the shoulders), elbowL/R, head, mood }`; moods `calm fierce shout hurt happy ko` move the brows, open or shut the
  eyes and the mouth), `poseStanding(rig, base, t, speed)` (the walk: knees and elbows bending, or the stand),
  `poseAction(rig, base, t, speed, action, k?)` (`cheer hurt swing reach pet cast jump sneak dance` and for the
  battles `windup strike guard throw run victory ko`), `STAND_TOP`.
- `Blocks.windy(root)`: the wind's tags for the pixel filter (§9.3): every part named `Flag...` or `Pennant...` (not
  a `...Pole`) gets `PixelWind` 2, every part in `leaf` or `leaf_dark` `PixelWind` 1 (water parts left alone). Called
  by `StreetModels.land`, `DecorModels.build` and `MicroStage` on their models.
- `BoatSpec` (the boat's plan, one for every boat: GAME_DESIGN 8): `MAX` (6), `dims(level) -> { L, W, H }`,
  `deck(level)` (the four places on deck, founder first: deck-top coordinates, +Z the bow), `moor(level)` (its x, z
  by the pier), `deckOverWater(level)`, `parts(level) -> { { name, shape ("Block" "Wedge" "CylY"), size, cf (from the
  deck top's centre), color, neon?, wind? } }` (the hull and every detail of GAME_DESIGN 8 by level; flags named
  `Flag...`).
- `StreetModels`: `road(parent, origin)` (a plot's stretch of the sea, `PixelWater` 1; the plank boardwalk on beams
  and posts with its rope rail and lanterns; its pier and moored boat), `boat(parent, origin, level) -> Model` (a
  `BoatSpec` boat, attribute `Level`, its flags `PixelWind` 2), `land(parent, origin, tier)` (the island: its
  cells meshed into rectangles layer by layer (the shallows `PixelWater` 2, the foam 3, wet sand, the beach, the grass
  in two tones), the invisible coast walls round the walkable cells, the campfire's plaza (`FireStone`s, logs, a
  flame, seats, a flag, torches), the stepping-stone path and the jetty (`JettyPlank`s on beams and posts, a rope),
  the sign with its `SignBoard`, the mailbox, and palms, rocks, shells, starfish, driftwood, seaweed and tufts strewn
  by the plot's own seed; `Blocks.windy`), `emptyLot(parent, origin)` (open water and a sandbar), `ends(parent)` (the sea past the
  ends, sandbars, the boardwalk's last lantern, the invisible walls along each end's own stretch of boardwalk, and
  the walls round the world, 8 studs high; the pier's things, `PierProps`: bollards, crates, a barrel, rope, and the
  moored `Boat` don't collide). Every wall is
  in the collision group `Bounds`, which the pixel filter's rays (group `PixelRays`) pass through.
- `DecorModels.build(id, at, lvl?) -> Model` (every building and piece of decor; `at`: the footprint's centre on the
  grass, turned; each with its doors, windows, ridged roofs with eaves and its own props (crates, barrels, sacks, pots,
  fences, lamps); a lamp and a pennant (`PennantPole`) at Lv 3; the pier's pond and the fountain's water `PixelWater` 2; parts don't
  collide; `Blocks.windy`), `has`.
- `MicroModels` (the driftlings and the stages' things): `build(kind, opts?) -> Thing` (`{ model, parts, rest, sizes,
  baseRest, baseSize, colors, h, r, kind }`, a few palette parts round the origin, facing +Z), `driftling(shape, body,
  accent)` (the 14 shapes `blob crab bird bun lizard owl pup mole bat yeti seal sprite jelly wyrm`), `sailboat`,
  `ship` (the expedition boat from `BoatSpec` at `opts.level`: its origin on the waterline), `flutter(thing, t)` (a
  thing's `Flag...` parts ripple: their depth and height step through four frames), ambient kinds (`bird
  butterfly light flame crab ...`), `slab`, `grid`, `hoop`, `place(t, cf)`, `scale(t, k)`,
  `recolor(t, color?)`, `show(t, on)`, `has`. Parts keep their sizes to the eighth of a stud (about an art px), not
  Blocks' quarter. Each driftling shape gets its finer details (`DETAIL`, GAME_DESIGN 2), and `animate(t, time, mood,
  k?)` moves its limbs from their built pose (times the squash of `scale`), by name: `Wing*`/`Rib*` flap, `Claw*` and
  `Pincer*` snap open on a strike, `Tail*` wag, `Ear*` twitch and droop, `Arm*`/`Hand*` swing up, `Leg*`/`Foot*`/
  `Paw*`/`Toe*` step, `Tendril*` and side `Fin*` wave, `Eye*` blink (shut when hurt or down), `Mouth` opens; moods
  `idle walk attack hurt cheer ko`. WorldView, Voyage and the islet's screen call it every frame.

## 7. Server

### 7.1 Remotes (`Net`)
`ReplicatedStorage.Remotes`: `Request` (RemoteFunction, C->S `(action, payload) -> Response`), `Signal` (RemoteEvent,
C->S `(kind, payload)`; no handlers in this version), `State` (RemoteEvent, S->C the whole `ClientView` when it
changed), `Fx` (RemoteEvent, S->C `{ kind = "tick", shells, food, wood, dayFrac }` every second, `{ kind = "turn",
movedIn? (the Villager), trained? }` at each turn's end, `{ kind = "day", day }` at each of the sea's days, `{ kind = "exp", step = "node" | "round" | "home", data }` for each
expedition step). `Net.serverInit()` creates them; `Net.clientInit()` waits for them.

### 7.2 `Session`
`create(player, profile, plot) -> S` (`{ player, profile, plot, rng, ready, turnClock, dayIndex, tickClock, dirty, saveAt,
reqTimes, exp?, away }`: `exp` the expedition under way, `away` its party's keys), `get`, `remove`, `all`, `view(s) ->
ClientView`, `setExp(s, e?)`, `markDirty`, `flush` (sends State when dirty), `fx(s, msg)`, `allow(s, now)` (the rate
limit).

### 7.3 `Router` and the action catalogue
`Router.on(action, fn(s, payload) -> (ok, data|err))`, `Router.onSignal(kind, fn)`, `Router.handle(player, action,
payload) -> Response` (not ready -> `not_ready`; over `Tuning.RateLimitPerSec` -> `rate`; `Validate.request`; the
handler under pcall; success marks the session dirty).

| Action | Payload | Rule | Errors |
|---|---|---|---|
| `plot.place` | `id x z rot` (coords whole studs in [-64, 64], rot a quarter turn) | `Plot.place`, the buildings rebuilt by difference, the tips | locked, full, money, wood, blocked |
| `plot.move` | `i x z rot` | `Plot.move` | blocked, bad_payload |
| `plot.upgrade` | `i` | `Plot.upgrade` (data `{ lvl }`) | max, money, wood, bad_payload |
| `plot.store` | `i` | `Plot.store` (clear away) | no_room, bad_payload |
| `island.expand` | - | `Island.expand`, the island rebuilt (data `{ tier, moved, cleared }`) | max, money, wood |
| `folk.work` / `pal.work` | `id uid` (0: rest) | `Island.setWork` / `setHelp` | not_found, bad_payload |
| `folk.dismiss` / `pal.release` | `id` | `Island.dismiss` / `release` | busy (away), not_found |
| `exp.start` | `isle party` (a sea chart island's id, 1 .. 64; "v3,p7": up to three, "" the captain alone) | `Chart.sail`, the session keeps it (data `{ isle }`) | busy, far (out of the boat's range), full, not_found, food, bad_payload (no such island) |
| `boat.upgrade` | - | `Chart.upgradeBoat`, the pier's boat rebuilt (`PlotService.setBoat`; data `{ boat, radius }`) | busy (an expedition under way), max, money, wood |
| `exp.next` | - | `Expedition.next` (Fx exp node) | no_exp, in_battle, max |
| `exp.act` | `act target` (fight guard treat flee; "w<i>" or "") | `Expedition.act` (Fx exp round) | no_exp, blocked, food, no_room |
| `exp.home` | - | `Expedition.home`, the session lets go (Fx exp home; data `{ got, over, befriended, isle (its name) }`) | no_exp, in_battle |
| `founder.set` | `skin hair style shirt` | `Island.setFounder` (the `Founder` attribute follows on the next sync) | bad_payload |
| `settings.set` | `k` ("pixel"), `v` | the pixel tier: high, medium, low, off | bad_payload |
| `tut.next` | - | the tips go away for good | - |
| `char.home` | - | PlotService puts the founder on their path | cooldown (`Tuning.HomeCooldown`), not_ready |

### 7.4 `IslandService`
Registers the actions above. `step(dt)` (Main's fixed 10 Hz step), for every ready session: `Island.step` (those away
left out), the view sent when the food runs out or comes back, a turn every `TurnSeconds` (`Island.turn`, Fx "turn"),
a day each time the sea's clock passes a day's end (`WorldClock.dayIndex` past the session's `dayIndex`:
`Island.newDay`, Fx "day"), the stores every second (Fx "tick" with `WorldClock.dayFrac`: the whole view is not sent
for them). `WorldClock` (server): the sea's clock, `os.time()` at start advanced by every step (`now`, `advance`,
`shift(seconds)` for the sims and previews, `dayIndex`, `dayFrac`); a day is `Tuning.DaySeconds` (4 hours). `leaving(s)`: an expedition under way comes
home with its loot (on leave and at shutdown). Nothing happens while the player is away.

### 7.5 `PlotService` (the sea)
`init()` registers the collision groups `Bounds` (the invisible walls) and `PixelRays` (the pixel filter's rays),
not colliding with each other, and builds the whole sea: `Workspace.Plots.Street` (every plot's boardwalk stretch,
`Road_<i>` with its pier's expedition `Boat` (attribute `Level`), and the sea's ends) and open
water on every plot (`Plot_<i>.Static.Land` = `EmptyLot`, attribute `Owner` 0). `claim(player) -> plot` (the lowest
free index, 0 when the sea is full: Main kicks), `release(i)` (back to open water, every attribute cleared, the pier's
boat back to level 1). `setBoat(s)`: the pier's boat rebuilt at the profile's level when it differs, and the plot's
`Boat` attribute (called by `build` and `boat.upgrade`).
`build(s)`: `Plot_<i>` gets `Owner`, `OwnerName`, `StudioName` ("Name's Isle"); its `Static` gets
`Land` for the island's tier (rebuilt only when `Static`'s `Built` attribute differs) and `Decor` by difference
(`buildDecor(s)`: one model a piece, named `uid:id:x:z:rot:lvl`; models whose key is unchanged stay), then `sync(s)`:
the attributes `Tier`, `Day`, `Charm`, `Islets`, `Folk` (a villager a `;`-separated `id.skin.hair.style.shirt.work.away`),
`Pals` (`id.species.work.away`), `Sailing`, and the player's `Founder` (`skin.hair.style.shirt`) and `Plot` (Main syncs
every dirty session before sending its view; only changed values replicate). The founder: `watchCharacters(player)`,
`placeCharacter(s)`, `spawnCFrame(s)`, `home(s)` (`char.home`, once every `Tuning.HomeCooldown`).

### 7.6 Persistence (`DataService`, `Logic/Schema`)
One key per player (`u_<userId>`) in `Tuning.DataStoreName`, a record `{ data = Profile, lock = { job, t }? }`.
`load(userId) -> (raw?, ok)` takes the lock: while another server holds a lock younger than `Tuning.LockTTL` it
waits and retries, and on the last of `Tuning.LoadRetries` attempts (about 10 s) takes it over. `save(userId, profile,
release?)` never overwrites a record whose lock another server holds. Main: join -> claim a plot, load (kick on
failure), `Schema.reconcile`, build the island, ready, send the view; leave -> `IslandService.leaving`, save with the
lock released, free the plot; autosave every `Tuning.AutosaveSec`; BindToClose brings expeditions home and saves
everyone. Without DataStores (Studio without API access) saves live in memory and a warning says so. A new save shape
needs a `Schema.VERSION` step in `migrate` and a spec that an older profile still loads.

## 8. Client bootstrap and the mirror

`Main.client`: `StateClient.init` (remotes), `PixelRenderer.init` (lighting), `CameraController.init`, wait for the
first view, `CameraController.start`, `PixelRenderer.start`, `DayLight.start`, `UIKit.init`, `WorldView.start`,
`AvatarView.start`, `StreetLife.start`, `Hud.start` (which starts `Menus` and `ExpeditionUI`).

### 8.1 `StateClient`
`init`, `view() -> ClientView?`, `waitView`, `Changed: Signal<ClientView>`, `Fx: Signal<msg>`, `Tick:
Signal<ClientView>` (Fx "tick": the view's `shells`, `food`, `wood` and `dayFrac` are patched in place, no whole view
comes), `request(action, payload) -> Response` (never errors), `signal(kind, payload)`.

### 8.2 `DayLight` (the day and night)
`start()`: the view's `dayFrac` (each tick and view; run on smoothly by `Tuning.DaySeconds` between them) sets
`PixelRenderer.setGrade(at(frac))` every frame, on the islands and on an islet's stage alike (with the filter off,
`Lighting.ClockTime` instead: 6 at dawn, 18 at dusk). `at(frac) -> Grade?`: the day's keys (`KEYS`: dawn 0, morning
0.07, afternoon 0.6, dusk 0.68, twilight 0.75, night 0.81 to 0.95, dawn again at 1), the step between two keys in
`STEPS` (6) steps; nil when it is plain daylight. `debugSet(frac?)` (previews: a fixed time), `debugState() -> {
frac, grade, clock }`.

### 8.3 `Audio`
`play(name, opts?) -> boolean` (opts `{ volume, pitch }` times the event's), `has(name)`, `EVENTS`: every sound by
name (`click hover open close deny notice ding coin coins level_up reward fanfare rare_fanfare combo sparkle cheer
applause trumpet sad drumroll tick key flip pop squish`, the battles' `whoosh whoosh_heavy hit hit_heavy body_fall zap
heal shield poof bite`, the world's `chest splash hammer horn gull birds`), each one `Monetization.Sounds` id (0 =
silent) with a volume, a pitch range, a cooldown (a repeat inside it is dropped) and a few voices (Sounds in
`SoundService.UISounds`, reused). `ambience(name, volume)`: a looped sound (`waves`, `crickets`) faded toward a volume
(DayLight: the surf always, crickets at night).

## 9. The pixel filter and the camera

### 9.1 Principle (Random Bakery's, cut down: one fitted scale, pans, no Actors)
One EditableImage, shown full screen through an ImageLabel with `ResampleMode = Pixelated` from the screen's top-left
corner: one art pixel is K × K screen px. K is the game's one pixel size (2 on phones and 768p, 3 at 1080p, 4 at
1440p; a tier only makes it coarser). The **static layer** is a raycast G-buffer of the view: progressive passes (one
ray per 4×4 block, per 2×2, then every pixel; `Pixel/BakeCast`), time-sliced (`Tuning.PixelBakeMsPerFrame`, more
behind the first curtain), sun visibility cast at each 2×2 block's even-even anchor and shared by the other three
pixels when they show the same part and normal (their own shadow ray otherwise; then every shared pixel lit unlike a
neighbour casts its own, `refineShadows`, so shadow edges step one pixel: GAME_DESIGN 2), shaded with `Render/Shading`'s three
toon bands and the palette LUT (the indoor tint inside the room), then the ink outline (`Shading.outline`) and the
contact shade at the foot of upright faces. The **dynamic layer** is the islanders (villagers and driftlings) and the founders: every tick (the tier's Hz) their parts
are drawn analytically with `Raster.drawPart` and the same orthographic camera, depth-tested against the static
layer and outlined; only the old and new dirty rects are restored and uploaded. Without EditableImages (or with
Classic picked) the layer hides and the Roblox camera shows the 3D world.

### 9.2 `CameraController`
`View = { rot12, center, look, viewH, grid: Raster.Grid, key, fullX, fullY, K, tier, plot, room, box }`.
Orthographic yaw 45° pitch 30°: floor edges step 2:1. A fixed box round the island's heart (`FRAME`, the same on every
tier) is fitted on screen clear of the HUD's blocks (`setHudRects`), at the largest clean grid scale (`Raster.gridScale`,
`Raster.gridPhase`) whose placement is clear (`Raster.place`): that placement is the **home** pan (`view().grid.px/py`),
and its scale the one zoom. The grid's ray plane `l` is fixed per plot (`CamRayBack` behind the plot's origin), so the
key (`plot|a|phase|l|screen|K`) only changes with the plot, the screen or K: anything else (the HUD's blocks, the
island's tier) only moves the home pan.
The **pan now** (`pan() -> (px, py)`, whole art px) follows the founder every frame (`RenderStepped`): the target puts
the founder's ground point in the middle of the screen across and halfway between the HUD's top and bottom strips
(and the tips banner), on any island or the boardwalk; the pan glides `CamGlide` of the way a frame, never more a frame
than the renderer can scroll in one (`panCaps`: `PixelPanRays` over 1.5 rays a pixel of a strip), so its picture never
falls behind into a re-bake; a target more than three quarters of the screen away snaps (one bake instead of a scroll
that would bake several times). A new character is ignored until it has stood on its own lot once or 3 s have passed
(Roblox drops it mid-street before the server moves it home). Build mode: `setFree(true, down?)` starts from the pan
now lowered by `down` art px (Build mode's tray height) and the view stays where `panBy(dx, dy)` (full-screen px) drags
it, its centre within `CamBuildPan` studs of the plot; `isFree()`.
`setFocus(p?)`: a cutscene's world point the pan keeps in the middle instead of the founder (`Voyage`), nil gives the
founder back.
`gridAt(px, py)` (the grid at a pan), `centerWorld()` (the view's ground centre now), `view()`, `refit()`,
`ViewChanged` (a new key: a new bake), `pixelK(size?)`, `setPixelLimit(h, classic)`. The Roblox camera is posed on the
pan now: far away at `CamFov` with the filter on, at `CamOffFov` in the classic style.
**Stage mode** (a microgame): `setStage(Stage?)` with `Stage = { name, origin, pts, top, bottom }` fits the stage's
points full screen clear of the play overlay's top and bottom strips (art px), the ray plane at the stage's origin,
the key `stage:<name>|...`, no indoor room; the view holds still (`view().stage` true); `setStage(nil)` goes back
to the street; `stage()`.

### 9.3 `PixelRenderer`
`init`, `start`, `setTier(t)`, `tier`, `isActive`, `unavailableReason`, `pixelScale` (K), `firstPicture() -> (shown,
progress)`, `registerDynamic(model)`, `unregisterDynamic`, `refreshDynamic`, `rebake`, `setPaused`,
`project(world) -> (Vector2 full-screen px, on)`, `projectPixel(world) -> (i, j, on)`, `screenRay(pos) -> (origin,
direction * length)` (pos = an InputObject's Position: the pick ray through what the layer shows), `debugStatic()`
(CLI checks: layer, pan, bakes, ticks, `scrolls`, `scrollRays`, `recasts`, `queued`), `Changed: Signal<PixelTier>`.
- **Pans** (every frame): when `CameraController.pan()` differs from the layer's, every static buffer shifts by whole
  art px (`buffer.copy`, overlapping rows) and the uncovered strips are cast by the bake's last pass (each 2x2 block's
  even-even anchor first with its sun ray, then the pixels sharing it), re-outlined with a pixel round them; at most
  `Tuning.PixelPanRays` rays a frame (a longer pan catches up over frames); a pan of half the layer or more re-bakes
  at the new pan behind the old picture. The next compose copies the whole static layer and uploads the whole image.
- **Invalidation**: a part that comes or goes anywhere under `Workspace.Plots` queues the global-art-px rect it and its
  sun shadow on the lawn cover (`partRect`); queued rects are re-cast pixel by pixel by the same rule (anchors, then
  the rest), at most `Tuning.PixelInvalidateRaysFrame` rays a frame, then re-outlined; rects over a third of the
  layer re-bake it (a new island). After a re-cast and at the end of a bake the shadow edges are refined
  (`refineShadows`, the tiers with shadows). Rects in global px survive pans.
- The bake's rays are in the collision group `PixelRays` (the invisible walls never meet them) and exclude
  `Workspace.PixelDynamic` and every player's character (refreshed when characters come and
  go). Dynamic models whose first part lies more than `CULL` (48) art px off the layer are skipped; at most
  `PixelMaxDyn` are drawn a tick.
- **Stages**: a stage view bakes with `PixelStageBakeMs` more a frame (the play overlay's curtain covers it); the
  street's finished layer is kept aside (its buffers and part ids) and restored at once when the street's key comes
  back, unless a part under `Workspace.Plots` came or went meanwhile (then it bakes again). `ready()`: the view now has
  its finished picture (always true in the classic style). `setOffset(dx, dy)`: the layer shifted by whole art px
  (a hit's jolt in a minigame).
- **Water**: a part with a `PixelWater` attribute (1 the sea, 2 the shallows, 3 the foam) marks its pixels in the bake
  (`sWClass`) with a wave phase from their ground position (`sWave`: bands across the sea, bent by two sines);
  `WATER_HZ` (6) times a second, not on the low tier, every water pixel not under an ink line is shaded again from its
  baked tone: crests a light blue (`WATER_CREST`), troughs darker (`mixShaded` mixes in the layer's packed format,
  `Shading.pack`: red in the low byte), the foam's white coming and going (`waterColor`, cached per class, tone
  and phase), and the whole image uploads. Its shadows and the islanders over it stay put. A stage's water moves too.
- **Wind** (GAME_DESIGN 8): a part with `PixelWind` 1 (leaves) or 2 (flags; `Blocks.windy` tags them) gets the class 4
  or 5 in `sWClass` (never on water) and its own phase in `sWave` (leaves: slow, across the island; flags: quick,
  along their length). With the water, `animateWind(s, frame)` moves pixels on the static layer without a ray: a
  canopy leans a pixel each way and rests in between (its leading edge's outline and leaf moved out over what lies
  farther behind it, never over anything nearer; its trailing edge's taken by what lay behind it, the outline a
  pixel in); a flag's columns drop or lift a pixel along the wave (the lifted fold a shade darker). What it painted is
  kept (`windSaved` / `windWrote`) and undone (`windRestore`) before the next wind frame, a pan, a stage's stash and
  a bake; a pixel something else has painted since is left alone. They belong to their layer (`windOn`): another
  layer's are dropped, never restored onto it.
- **The time of day** (GAME_DESIGN 8; `setGrade(Grade?)`, `debugGrade() -> string` its key, "" by day): the layers
  keep their daylight colours; every uploaded pixel (`uploadAll`, `uploadRect`) goes through `gradeOf` (cached per
  colour and light level, cleared when the grade changes, which also uploads the whole picture): desaturated by
  `sat`, times `mr mg mb`, plus a blue `lift` in the shadows. `Grade { mr, mg, mb, lift, sat, lamps }`. Neon parts
  (`EMISSIVE` statics, `dynGlow` dynamics) keep their colour; round them `lightMap` (u8 a pixel, 0..3, rebuilt by
  `buildLight` when the picture moved or a part came or went, at most every `LIGHT_EVERY` seconds, and every second
  for the moving lights; a pan shifts it with the static layer, the strips coming in dark until the rebuild) pools
  warm light in three stepped rings (`RING`, twice as wide as tall: the ground at 2:1),
  `lamps` of the way back to the colour by day, warmed.
- **Blob shadows**: a dynamic model with a `PixelShadow` attribute (radius, studs) shades the static pixels in an
  ellipse under its PrimaryPart on the ground at `PixelGroundY` as in the sun's shadow (the palette's own shadow tone;
  never an ink line or the sky), smaller the higher it is; drawn before the models, restored with their rects. The
  shadowed tone of each static pixel is worked out once and cached (`sShadowC`) until the static layer changes (a
  bake, a pan, a re-cast), so a cloud's big shadow stays cheap.

### 9.4 Text and pictures
`Pixel/PixelText` (copied): labels drawn in the pixel font into shared EditableImage atlas pages; a bound TextLabel
keeps its `Text`. `Pixel/Snapshot` (copied): pixel-art pictures of models drawn analytically (`Render/Picture`), for
UI icons: the Staff panel's portraits (`UIKit.portrait`: a developer's head and shoulders turned to face the viewer). `Pixel/ImageMemory` (copied): every EditableImage is made through
it.

## 10. Interface

### 10.1 `UIKit`
Roots `World` (DisplayOrder 7, full screen: popups over the islands), `Hud` (10), `Modal` (20), `Popup` (25), each
with a `Canvas` frame in UI px (UIScale K) on the screen's grid. `color(key)`, `hex`, `P`, `size(root)`, `phone`,
`canvasOrigin`, `text(parent, text, size, pos, opts)` (PixelText-bound), `setText`, `setTextColor`, `textWidth`,
`lineHeight`, `plate` (stepped corners, Random Bakery's), `setPlate`, `rect`, `button` (a TextButton with a child
"Words" label; disabled = `AutoButtonColor` false; fires on `Activated`), `setEnabled`, `setButtonText`,
`setButtonColor`, `buttonWidth`, `bar -> (frame, set)`, `clear`, `vlist`, `hlist`, `scroll`, `confetti(parent, n?,
colors?)` (a burst of 1 px pieces and 1x2 sticks that fly, tumble and fade), panels
(`registerPanel(name, { title, w, h, build })`, `openPanel(name, arg)`, `closePanel`, `currentPanel`,
`refreshPanel`, `PanelChanged`, `bodyWidth`, `bodyHeight`), `Resized` (fired once a frame whenever a root's canvas
changes size: K or the viewport changed, or a root was laid out again on its own, as Roblox does after the camera's
ViewportSize event and when the top bar's inset or a safe area settles; everything laid out from the canvas's size
rebuilds on it, and the bottom pieces, the HUD's menu bar and tips and Build mode's tray, are anchored to the
canvas's bottom edge so they stay on screen meanwhile), `notice(text, color, seconds)` (a toast at the top; while a
panel is open, its status line next to the title instead, and opening a panel clears the toasts, so nothing covers
a panel), `clearNotices`, `floatText(world, text, color, big)`, `portrait(parent, look, size, pos)`, the `Stage` root (DisplayOrder
22, full screen: a microgame's overlay, its UI px the world's art px), `tween` (a UDim2 property
eases on Heartbeat snapped to whole UI px, Quad out, the newest tween of a property winning; the rest through
TweenService), `Resized`, the effects `burst(parent, x, y, colors, n?, speed?)` (1 px bits from a point of a frame), `burstOn(gui,
colors, n?, speed?)` (from a GUI object's middle, on its canvas: it outlives a rebuilt panel), `popText(parent, x, y,
text, color)` (a word rising and fading), `shine(button)` (a light band sweeping across its plate, clear of the
corners) and `bitsAt(world, colors, n, speed?, gravity?)` (bits on the World canvas from a world point). Motion
(GAME_DESIGN 15): a button lightens while hovered, its plate and words sink 1 UI px while pressed,
and `Activated` plays `click` (or `deny` when disabled); a panel's shade fades in and its frame rises 10 UI px into
place; a notice slides down into the stack and fades out.

### 10.2 `WorldView`
The islanders: a walker per villager (`CharacterModels.buildStanding` in their look) and per driftling
(`MicroModels.driftling` in its species' shape and colours), parsed from each owned plot's `Folk` and `Pals`
attributes (those away left out) and placed among the buildings read from its `Static.Decor` models' names
(`uid:id:x:z:rot:lvl`). Villagers walk to their building and work there (hoeing at a patch, chopping at a camp,
selling at a shop: `poseAction`), wander the grass when resting (`strollPoint`: a buildable cell away from the
campfire); driftlings hop beside the building they help at or round the
nests. Only islands within 100 studs of the view's centre are drawn (synced every half second); each
near owned island's campfire gets a flickering flame and rising smoke (`fireOn`, dynamic models). Each island's sign gets
a World-root label (its name, the own in gold, or "Unclaimed isle"); a tap on a sign (a press let go within 8 px, not
on the interface, not in Build mode) shows `signCard(i)` (the day, villagers, driftlings, charm, islets). A newcomer
(Fx "day" `movedIn`) gets a welcome word and confetti; `cheer(words, color)` makes the own islanders cheer.
`rigCount()` / `ownRigCount()` for the sims.
`StreetLife` (client, started after AvatarView): four sailboats (`MicroModels` "sailboat", blob shadows) crossing
both ways on two lanes out at sea, rocking on the swell in whole steps, wrapping round the sea's ends; a flock of three
gulls crossing every 14-24 s; two clouds: invisible models high up with a `PixelShadow` (their shadows drift east over
the islands). `count()` for the CLI.

### 10.3 `Hud`
Chips (`Chip_shells`, `Chip_food`, `Chip_wood`, each an 11 px icon and the store easing to its value, flashing when
it changes (the food's red and blinking while hungry); `Chip_day`, "Day 3" with the day's clock along its edge and a
sun that sets into a moon; then `Home`, a button shown while the founder is off their own island, sending
`char.home`), the menu bar (`Menu_build`, `Menu_folk`, `Menu_pals`, `Menu_explore`, `Menu_index`, `Menu_looks`;
while Build mode or the islet's screen is open the bar, the cards and the tips step aside), the `IslandCard` on the
right (the island's name for its tier, villagers / beds, driftlings / nests, visitors, charm, and what a day makes of food, wood and
shells a minute: `Numbers.perMin`), the `ExpCard` under it while an expedition is under way (the islet, the stop or "In a
battle!", `ExpContinue` pulsing: `ExpeditionUI.open`; on a phone at the top left), the tips banner (`Tips`: the steps of GAME_DESIGN 9 (`tut` 1 .. 6: food, wood, shells, a tent, a nest and sail,
islands and treats); tip 6 has `TipsOk`, sending `tut.next`), the loading curtain (until `PixelRenderer.firstPicture`) and the `DayBanner` (Fx
"day": the day and who moved in or trained; over a panel, Build mode or an expedition a notice instead). Shells
coming in rise from their chip ("+12", at most every 2 s, from `StateClient.Tick`). It reports its blocks to the
camera (on PC the top strip, the menu bar and the card's place; on a phone Roblox's top bar and the menu bar).

### 10.4 Menus
`Menus` registers the panels: "folk" (a row a villager `Folk_<id>`: portrait, name, level, job or "Resting" or "Away
on an expedition", battle stats; `Job_<id>` opens the picker (the same panel with `{ folk = id }`: a row
`Spot_<uid>` a building that takes workers, `Go_<uid>` Go / Swap / Here, `Go_0` Rest, `Back`), `Dismiss_<id>` (two
taps: "Sure?")), "pals" (`Pal_<id>`: portrait, name, level, skill, where it helps, stats; `Help_<id>` the picker of
the buildings of its knack, `Release_<id>` two taps), "explore" (the sea chart, a wide panel: on the left the map
(`SeaMap.draw`, as big as the panel's height allows) and under it the boat (`BoatLv`, the next level's price
`BoatShells` / `BoatWood` (red when short) and `BoatUp` sending `boat.upgrade`, off while an expedition is under way;
`BoatMax` at the top); on the right the island picked (`IsleName`, `IsleKind` (its kind and level, coloured against
the captain's), its wild ones' portraits, `Reward` (half once charted), `Charted`), the party (`PartyHint`,
`Member_f` the captain always, `Member_v<id>` / `Member_p<id>` picked up to `PartyMax`, the strongest first), the
supplies and `SetSail` (sends `exp.start { isle, party }` and plays the sailing cutscene: `ExpeditionUI.sail`; or
continues one under way). The island picked at first: the strongest uncharted one in range at most a level over the
captain's, else the nearest. `SeaMap` (client): `draw(parent, size, pos, { sea, boat, chart, cap, chosen, onPick,
onFar }) -> Frame` (`Chart`: the `MapImage`, a size x size EditableImage (`ImageMemory`, reused) drawn pixel by pixel
(GAME_DESIGN 7: each island a signed distance to its wobbly outline and its islets', its kind's land by
`landColor`, lit by the slope from the top left, textured by a value noise, hue-shifted ramps; the shallows, surf,
the sea's swells; the fog past the range, the dotted rings, the flags, the outline of the one picked); without
EditableImages the `chart_<kind>` sprites; a `Lv<n>` label under each island in range (over it, or none, where it would touch another's) and a hit button `Isle_<id>`
over every island (`onPick(id)`, or `onFar(id)` out of range)), "index" (`Entry_<species>`:
portrait or silhouette, name or "???", the kind of island it lives on, a heart once befriended, its blurb; "Met n of 15")
and "looks" (the founder's portrait, `Prev_<k>` / `Next_<k>` for skin, hair, style and shirt, `SaveLook` sends
`founder.set`). `Menus.party()`, `Menus.chosen()` (the island picked) for the sims. `Words.errText(err)` words every ErrCode.

### 10.6 `AvatarView`
A founder per player (`CharacterModels.buildStanding`, look from the player's `Founder` attribute, else one from the
UserId), registered with the renderer and posed every frame at their character: feet on the ground under the
HumanoidRootPart (a raycast down past characters and rigs), facing the root's look direction, walking at the speed
the root moves. The Roblox avatar is hidden on every client (`LocalTransparencyModifier` 1 on its parts and decals).
Other players' names float over their heads (World root). `founderPos()`, `count()`, `lookOf(player)`,
`setOverride(fn?)` (a cutscene poses the own rig instead: `fn(rig, t, dt)` every frame; nil gives it back).

### 10.7 `BuildUI` (Build mode)
`open()` (the HUD's Build button): closes any panel, `CameraController.setFree(true)`, the tray `BuildTray` along the
bottom: the tabs `Tab_food Tab_wood Tab_shop Tab_home Tab_nest Tab_decor` (their icons alone on a narrow screen), the
pieces count, `Expand` (`island.expand`, its price under it) and `BuildDone`; a card a piece of the tab (`Buy_<id>`:
its price in shells and wood with their icons, red when short; a locked one says the island tier it needs). With a
piece picked (`pick(id, rot?)`), a ghost model (`Ghost` in `Workspace.PixelDynamic`: the piece and its `Footprint`, a
raised neon frame of four edges just above the grass, cyan (`screen_on`) where `Plot.fits`
says it fits, red (`berry_red`) where not) stands on the cell under the pointer (mouse) or the last tap; the bar shows
`Rotate`, `Place` / `Move here`, `Upgrade` and `Store` ("Clear away") when moving a building, `Cancel`, and the
`Info` plate (what it is and makes, its charm, its price or the next level's). A tap on a placed piece of the own
island (a ray into its `Static.Decor`) picks it up. A press dragged more than 8 px pans the view
(`CameraController.panBy`). `confirm()` sends `plot.place` (the piece stays picked for another copy) or `plot.move`;
`close()`; `isOpen()`; `Changed: Signal<boolean>`; `tapScreen(pos, mouse?)` (the sims' and previews' tap). The tray
is laid out again when what can be afforded changes (`StateClient.Tick`).

### 10.8 The sailing cutscene (`Voyage`)
`Voyage` (client; `init()` from `ExpeditionUI.init`): `play(keys, isle?, onDone)` after Set sail (keys: the members
picked, `isle`: exp.start's answer): the HUD and the touch controls hide, the character's WalkSpeed and JumpHeight go
to 0, a `Voyage` frame on the `Stage` root slides in letterbox bars (`BarTop`, `BarBottom` with "Setting sail..."
and `VoyageSkip`). The plot's moored `Boat` (in `Street.Road_<i>`; its plan, deck places and mooring from
`BoatSpec` at its `Level`) leaves the street (the renderer re-casts the water there) and becomes a dynamic model, its
flags fluttering while it moves; the party's villagers (`CharacterModels.buildStanding`) and driftlings
(`MicroModels.driftling`, 0.8 as big) stand on its deck. Phases: "open" (0.3 s), "walk" (the own founder, posed
through `AvatarView.setOverride`, walks at 13 studs/s from where they stand on their island down to the path, the
boardwalk and the pier's end, feet on the ground by a raycast in the `PixelRays` group; a walk over 46 studs starts
on the jetty), "hop" (0.45 s arc onto the deck; the party cheers), "sail" (3.2 s: the boat eases out 30 studs south,
bobbing in whole eighth studs; `CameraController.setFocus` follows the founder, then the boat), "close" (the
`Blind`s shut over 0.4 s with the island's `IsleName`, its kind and level), then `onDone` (ExpeditionUI opens behind
the closed blinds with its own closed curtain) and the overlay goes. `skip()` (Skip, Space, Return) closes the blinds
at once and finishes. The boat stays away (`away`) until no expedition is under way and no stage is on screen, then
`dock()` moors it again (its parts back, under its road; not while a cutscene plays).
`home(members, onDone)` (the expedition over: `members` `{ look?, seed?, sp? }`, the party but the founder): the
overlay starts with the blinds closed on "<Name>'s Isle" / "Home again!" ("Sailing home..."); the boat, back at its
mooring's parts and moved `SAIL_Z` out to sea with the party on deck, waits ("wait") until the renderer is `ready()`
on the island with no stage (at most `OPEN_WAIT` s), the blinds open, "arrive" (`ARRIVE` s, easing in to the pier;
the view follows it), "hop" (the founder onto the pier), "land" (0.8 s, the party cheers), then the boat is docked,
the founder's character stands on the pier (its middle, two studs and more from its walls: a character put inside a
wall is stuck; WalkSpeed and JumpHeight back, never to 0), the HUD comes back and `onDone` (the loot's notice). Without the boat
away it does `reveal(onDone)`: closed blinds that open once the island's picture is there. `skip()` lands at once.
`isPlaying()`, `debugState() -> { dir ("out" | "home" | "reveal" | ""), phase, away, boat }`.

### 10.9 The islet's screen (`ExpeditionUI`, `MicroStage`)
`ExpeditionUI`: `sail(keys, isle?)` (Set sail: `Voyage.play`, then `open` with the boat arriving), `open()` (the
HUD's card; right after `exp.start` it waits for the view with the expedition), `close(after?)` (the `LeaveCurtain`
blinds close over the stage in 0.4 s, then the stage goes and `after()` runs, or `Voyage.reveal()`: Back to island
(the expedition waits) and the end of one (`exp.home`: `after` plays `Voyage.home` with the party, then the loot's
notice and sound; it stays busy till then)), `isOpen()`, `active()`, `Changed: Signal<boolean>`, `init()` (the view's changes lay it out
again; an expedition gone closes it), and for the sims and previews `debugState() -> { open, lifted, actors, busy,
node, foes, ship, arrived }`, `debugGo()`, `debugAct(kind)`, `debugHome()`, `debugWait(seconds?)` (a longer wait for
the picture: the fake engine bakes slowly). It hides the `Hud` and `World` roots and the touch controls, opens
`MicroStage.open(kind.stage, { top, bottom }, isle.seed)` (the camera's stage mode, the overlay's strips kept clear)
and draws on the `Stage` root (full screen: Roblox's top bar's height, `TopBar`, is kept clear): the `Header` (the
island's name and level, `Loot_<kind>`, the path's `Node<i>` icons (the ones ahead hidden
but the guardian's), `Here`, `BackToIsland`), the `Footer` (the party's cards `Card_<key>`: portrait or icon, name,
`Lv`, the health bar `HpFill`; between stops `AutoGo` (a bar filling over `AUTO_GO` s, then the next stop by itself:
`goOn`; a tap or Space at once) and `SailHome`; `Act_fight Act_guard Act_treat Act_flee` in battle (Treat and Flee off against a guardian), `TreatHint`), the foes' cards down the right (tap one:
the treat's target), the `Say` narration, a won battle's `Alert` (a small plate under the header: Victory!, its
lines, a new friend's portrait; gone by itself after `AUTO_CARD` s, no button), the `Result` card (`ResultOk`: Sail
home after the guardian or a fall) and the `Curtain` (ink blinds with the island's name, kind and level until the stage is `ready()` and 1.2 s
passed, at most `StageWait`). The actors: the founder (the stage's own), villagers (`stage.rival(look)`), driftlings
and wild ones (`MicroModels.driftling`, the guardian 1.6 times as big), posed every frame (drops, idle hops, lunges,
KO). Arriving after the cutscene the stage's drop happens behind the curtain (`lift()` at once) and the expedition
boat (`MicroModels` "ship" at the profile's boat level, its flags fluttering) glides in to the shallows off the floor's front-left edge (`SHIP_U`, `SHIP_V`, over
`SHIP_IN` s from the curtain's lift); the party stands on its deck (`DECK_SPOTS`), then one after another hops off
onto the shore (`HOP_T`, `LAND`) and runs to its places (`RUN` studs/s; the deck places from `BoatSpec.deck`);
a round's events play back one by one as moves (GAME_DESIGN 7: `startMove(actor, kind, other?)`, `MOVES` their lengths,
`frameOf` what each does at a moment: `{ du, dv, dy, tilt, sq, spin, action, k, mood, speed }`; `attack quick bash
zap` (the attacker's run up to `REACH` short of its target and back, `IMPACTS` the blows' moments), `hurt ko` (a
knock away from the attacker; `ko` flies, spins and lies down), `guard cast throw refuse happy flee stumble
victory`); a blow `freeze`s the moves (hit-stop: their clocks held) and `shake`s the picture
(`PixelRenderer.setOffset` by whole art px); the things squash by `MicroModels.scale` (whole eighths), lean by the
move's tilt and move their limbs (`MicroModels.animate` with the move's mood); the founder and villagers take the
move's action (`CharacterModels.poseAction`); keys: Space / Return go on or fight, 1-4 the battle's moves.
`MicroStage` (client): `open(variant, margins?, seed?) -> Stage` (an islet set laid out by the island's seed), `current()`, `has(variant)`, the yaws `FACE_VIEWER
FACE_RIGHT FACE_LEFT FACE_AWAY`, `U_DIR` (screen right) and `V_DIR` (toward the viewer). A stage is a folder
`MicroStage` at Z = 9000 (far from the islands: no ray of either view reaches the other): a 24 x 24 set and its props
(the kinds' `loot` beach, `leap` meadow, `dino` volcano sands, `frost` snowfield, `fish` sea floor; each but the sea
floor an islet of its own: `shore` rings the floor with land, beach, wet sand, foam and shallows on a wobbly outline
of the seed's phase (`blobRects` meshes the cells; `Builder.coast` the distance to it), the tall landmark (the
volcano, the snowy peak, a big tree) on its left shore (`VOLCANO`), beside the floor and clear of the top bar; the
rest placed by the seed (`Builder.rng`): `floorSpot(b, r)` on the floor off the band the battles cross and clear of
the actors' places (`ACTOR_SPOTS`) and other props, `shoreSpot(b, r, tall)` on the land round it (a tall one out of
the top bar's corner, from under the wild ones' cards, from in front of the floor and off the landmark; none on the
boat's landing); `marks` (the chest, for its glint); the water moves (`PixelWater`); the older themed rooms are
kept), the founder registered dynamic with a blob shadow, and `Stage { variant, floor, half, avatar,
rival(look, delay) -> Rival, at(u, v, y), spawn(kind, opts?, shadow?), adopt(thing, shadow?), place(thing, u, v, y,
yaw?, tilt?), remove, flash(thing, seconds?), glow, refresh, screen(pos) -> (x, y, on), hold, hat, pose(u, v, y, yaw,
t, speed, action, k?), puff(pos, kind, n?, color?) (3D bits from a pool of 56 parts: `dust spark debris confetti steam
smoke bubble petal ember twinkle splash snow heal heart`), lift(), step(t, dt) (the bits and the set's ambient life:
gulls, butterflies, smoke, snow, bubbles, a crab), ready(), close() }`. Stage space: u to the screen's right, v toward
the viewer, y up from the floor's top; everything is world-aligned on the iso grid.

### 10.10 Sprites (`PixelSprites`, `ArtData`)
`ArtData` (generated by `scripts/gen_art.py`; do not edit): `{ [name]: { w, h, px, pal, alpha } }`, one character a
pixel (`.` clear, else an index into `pal` 0xRRGGBB with its `alpha`). How `gen_art.py` shades (GAME_DESIGN 2):
`cel_tones` over the whole silhouette (the base; a 1 px shadow along the bottom and right edges, two under a
portrait's belly; a short light on the upper half of the top-left edges of masses 3 px thick), close hue-shifted
ramps (`RAMPS`, `M` the magmole's warm basalt), no grain, curves inside the outline softened a step toward the
shadow; the outline is never anti-aliased on its outside. Each portrait is its body shape (`SHAPES`; the novafox's
is a `fox` of its own, its 3D model still the pup).
The overlay's sprites also have a white `<name>_flash`; the icons have a dark `<name>_sil` (not met yet); an
animation's frames `<name>_1`, `<name>_2`... share one canvas (bottom centre). The sprites: the driftlings' portraits
`icon_<species>` (16x16: a mask a body shape in the species' two ramps), the small icons `mini_<name>` (11x11: `shell
food wood sun moon charm folk pal visitor home nest train decor start loot chest wild rest boss star boat`), the sea
chart's islands `chart_<home beach meadow volcano snow reef>` (13x10, with `_sil`: SeaMap's fallback), the arrows
`arrow_<dir>` (13x13) and `arrow_<dir>_t` (7x7), `note`, `heart`, `spark_1..3`, `bombfuse`. `PixelSprites`:
`has(name)`, `size(name) -> (w, h)`, `image(parent, name, pos?, z?) -> GuiObject` (an ImageLabel `Sprite_<name>`
showing the sprite's EditableImage, made once and shared, `ResampleMode` Pixelated, at the sprite's own size: no
scale; without EditableImages a Frame of 1 px run rects), `anim(parent, names, pos?, z?) -> Anim { f, w, h, set(i),
flash(seconds?), moveTo(x, y) }`.

## 11. Verification

- `bash scripts/check.sh`: Rojo sourcemap, luau-lsp strict analysis (0 errors), luau-compile, the specs (`tests/run.luau`
  lists them: Util, Validate, Numbers, DataIntegrity, Island, Battle, Expedition, Chart, Economy, Plot, Schema, Shading,
  Raster, Rim, PixelFont), the Rojo build. Must end with `ALL CHECKS PASSED`.
- `tools/sim`: the fake Roblox engine boots the real server and client; this game's scenarios and their baselines
  are in `tools/README.md` and `CLAUDE.md`.
- `tools/preview`: PNGs of the real renderer and UI at device sizes (`tools/README.md`).

## 12. What came from Random Bakery

Copied unchanged or nearly: `Render/Raster`, `Render/Picture`, `Render/PixelFont`, `Render/PixelFontData`,
`Render/Ramp`, `Pixel/BakeCast`, `Pixel/ImageMemory`, `Pixel/PixelText`, `Pixel/Snapshot`, `Logic/Util`,
`Models/Blocks`, the specs `Raster` (its framing fixture now a local outline instead of the bakery's Layout), `Rim`,
`PixelFont`, `Util`, `tests/TestKit.luau`, `scripts/gen_pixelfont.py`, `tools/setup.sh`, `tools/defs`, the sim and
preview engines, `docs/WORKFLOW.md`. Adapted: `Render/Shading` (its LUT colours are the palette and the older rooms'
themes; the bakery's wallpapers and land tiles are gone) and its spec, `scripts/check.sh` (no locale or server-codes
steps; builds `build/ByteSizeStudio.rbxlx` as its check), `Net`. Written new for this game: everything else, including a much smaller
`PixelRenderer` (one fitted scale with pans and rect re-casts, no Actors, no Hold, no per-plot indoor light) and
`CameraController` (the fitted home view, following the founder, Build mode's free pan), and the sea of islands
(`Data/Street`, `StreetModels`, PlotService's plots and open water, AvatarView's founders), modelled on Random Bakery's
street of bakeries and its plot (ROUND3.md 6.6, 9) but smaller: buildings on a whole-stud grid, no drawn paths or
fences.
