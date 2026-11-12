# Driftling Isle: Architecture and Implementation Contract

The contract for the code in this repository (GitHub `Downvote/gamedevtest`). `docs/GAME_DESIGN.md` says what the game
does and why; this file says how the code is laid out, what each module offers and which data goes where. Where the
two disagree on an API, a type or a name, this file wins; on a number, `src/shared/Config/Tuning.luau` wins.

The build system, the conventions and much of the rendering code come from Random Bakery (`Downvote/test`, used
read-only as the reference: nothing there was changed). What was copied, and how it was changed, is listed in §12.

> The request (2026-11-10, GAME_DESIGN quotes it with the choices made): "scrap this idea. could you make replicate
> beasty bay from kariosoft instead? still use the test repo as a reference" (an original island-village game in the
> genre: island building and farming, creature taming, expeditions and battles, villagers moving in, a shared sea)

> The request (2026-11-12, GAME_DESIGN quotes it with the choices made): "scrap the entire cave, fighting, level,
> skill and expedition system. instead, players start with a tree of life: it creates a creature every few seconds to
> be put into a pen. ..." (the Tree of Life, its pen and the huts: `Logic/Tree`; the expeditions' code is gone)

> The requests (2026-11-12, later): "remove villagers, only creatures should be enough. also, make the tree of life
> more like a tree of life, reference references for it, make it look bigger and more grand"; "also, pens should be
> infinite, and no need to render the pen, just a ui should be enough" (no `Villager`, `folk`, homes, `folk.*` actions
> or Folk attribute; the pen without a room limit and not drawn; the tree 6 x 6 in `DecorModels`; save version 11)

> The requests (2026-11-12, the evening): "remove the pen cap. also, make the tree look grander and bigger after
> certain level milestones for luck"; "the first few levels are too expensive ... no need to add the +10w" (no
> selling by the pen: only `Tuning.PenSafe`, the save's limit, rests the tree; the view carries the pen's best
> `PenShown` and `penN`; `Tree.stage` by `TreeStages`, the tree's model built by stage; the tree's levels in shells
> only, cheaper at first)

## 1. Layout and tooling

```
default.project.json   Rojo: Shared -> ReplicatedStorage, Server -> ServerScriptService, Client -> StarterPlayerScripts;
                       characters on (the founder walks and jumps on the islands: JumpHeight 7.2)
src/shared/            Types, Net, Config (Tuning, Monetization), Data (content), Logic (pure rules), Render (pure pixel
                       maths, copied), Models (procedural models), Locale (Lang: English only)
src/server/            Main.server.luau, Services/* (DataService, Session, Router, IslandService, PlotService)
src/client/            Main.client.luau, Controllers/* (StateClient, CameraController, WorldView, AvatarView, StreetLife,
                       Audio), Pixel/* (PixelRenderer, BakeCast, PixelText, Snapshot, ImageMemory), UI/* (UIKit, Hud,
                       Menus, BuildUI, PixelSprites, ArtData (generated), Words)
src/first/             ReplicatedFirst.Loading (with Render/PixelFont and PixelFontData mapped beside it): Boot.client
                       (puts the loading card up first), LoadingCard, LoadingArt (generated: tools/preview/loading_art.sh)
src/RbxCharacterSounds.client.luau  an empty LocalScript in StarterPlayerScripts under the name Roblox would give its own
                       character sounds, so Roblox doesn't insert them (the founder's feet: Audio's step events)
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
  `Models/DecorModels` builds every building, `Models/StreetModels` the islands and the sea,
  `Models/MicroModels` the driftlings and the island's small moving things.

## 3. Types (`src/shared/Types.luau`)

`Look`, `Piece` (`{ uid, id, x, z, rot, lvl }`: a building standing on the island; `uid` stays while it stands; `lvl`
a level kept from an older save), `PlotSave` (`{ placed }`), `Pal` (a driftling: `{ id, sp, home (a hut's Piece uid, 0: the Tree of Life's pen), work (a Piece uid,
0 resting; only one in a hut works), muts? (its mutations, Data/Traits ids), held? (1: the player put it in the pen,
which leaves it there) }`), `Tree` (`{ luck, speed (levels, 1 ..), t (seconds grown toward the next driftling) }`),
`Settings` (`{ pixel, music? }`: music "on" | "off"), `Stats` (`{ days, built, earned, grown, sold (shells from
selling driftlings), best (the rarest grown or hatched), hatched }`), `Egg` (`{ uid (its Hatchery), a, b (the
parents' ids), sp, muts, left (turns) }`, one a Hatchery), `Profile` (the save, version 11: `shells`, `food`, `wood`,
`day`, `tier`, `founder`, `pals`, `tree`, `plot`, `seen` (species -> 2: had one, the Index), `eggs`, `nextId`
(driftlings and pieces share it), `tut` (1 .. 6, 0 done), `quest` (the questline's quest on the go, Data/Quests;
one past the last: all done), `stats`, `settings`, `createdAt`), `ClientView` (the profile's fields plus `dayFrac`,
`plot` (the plot index), `pieces`, `rates` (a turn, after eating), `charm`, `nests` (the huts' room), `visitors`;
`pals` is every driftling in a hut and then the pen's best `Tuning.PenShown` in its order, `penN` how many wait in
the pen, `penCommons` how many of those are commons), `ErrCode` (with `fixed`: the Tree of Life can't be stored or cleared away; `full`: no room
in that hut), `Response`, and the utility types `Connection`, `Signal<T...>`, `Rng`, `PixelTier`. The
file is the reference for every field.

## 4. Config

- `Config/Tuning.luau`: persistence (`DataStoreName = "BSS_Profile_v1"`, never renamed), the island (`StartShells`,
  `StartFood`, `StartWood`, `TurnSeconds` (the island's pace), `DaySeconds` (the sea's day: hours), `EatPal`
  (a driftling in a hut), `Hungry`, `IdleOutput` (a building's work with nobody at it), `PalWork` (a common
  driftling's), `RarityWork` (a driftling's work by its rarity), `HelpMax` (driftlings a building), `VisitorCharm`,
  `VisitorsMax`, `ShopVisitors`, `Refund`, `UpgradeMult` (a level from an older save; no upgrades since 2026-11-11), `TierCost`,
  `ComfortLvl`, `BoostMax`), the Tree of Life (GAME_DESIGN 6: `TreeSecs` (seconds a driftling by Speed level),
  `TreeLuck` (luck a Luck level), `TreeMutLuck` (Luck levels for a mutation roll one rarity up), `TreeSpeedCost` /
  `TreeLuckCost` (shells a level, the first free; no wood), `PenSafe` (the save's limit: at this many waiting in the
  pen the tree rests), `PenShown` (the pen's best sent with the view), `TreeStages` (the Luck levels the tree grows
  bigger at), `HutTree`, `HutLuck` (the huts'
  tree and luck shares at most), `SellPrice` (by rarity), `SellTier` (a mutation tier's share on the price)), breeding
  (`BreedFood`, `BreedTurns`, `BreedKeep`, `BreedTierUp`, `BreedNew`), the server's step and rate limit, the sea
  (`MaxPlots`, `PlotSpacing`, `PlotPieces`, `PathPieces`, `HomeCooldown`, `WalkSpeed`, `JumpHeight`), and the camera and
  pixel filter values (Random Bakery's `CamYaw` 45, `CamPitch` 30, `PixelTiers`, `PixelScaleMin` / `PixelScaleSides`;
  this game's `CamRayBack`, `PixelMaxRayDist`, `CamFollowBox`, `CamGlide`, `CamBuildPan`, `PixelPanRays`,
  `PixelInvalidateRaysFrame`, `PixelMaxDyn`).
- `Config/Monetization.luau`: `GamePasses`, `DevProducts`, `Badges` (empty or 0), `Sounds` (the Creator Store
  library ids `Controllers/Audio` plays: Roblox's free licensed ProSoundEffects clips and APM Music stingers, none of
  Random Bakery's, each named in a comment) and `Music` (`{ day, night }`: lists of `{ id, gain }`, APM Music
  tracks, each named; `gain` evens their loudness out).

## 5. Data (pure content tables)

| Module | Holds |
|---|---|
| `Data/Palette` | the LUT colours (`order`, `colors`), the shore's `shallow`, `foam`, `rock` and `rock_dark`, the older rooms' floor and wall themes (`themes`, still in the LUT), the light modes, and the UI's colours (`ui`, `axis`, `match`) |
| `Data/Buildings` | the 66 pieces (GAME_DESIGN 4) `{ id, name, kind (food wood shop nest breed gen path decor tree), shells, wood, w, d, rate, eats, knack, slots (a hut's room), charm (a path's may be a fraction), comfort (a hut's share), boost ("farm" "fish" "wood" "shop" "all": a "gen" piece's knack), boostBy, tier (1 .. 6; the Tree of Life 99, so no tab of the tray shows it), blurb }`; kind "nest" is the huts (Driftling Hut .. Driftling Palace), "tree" the Tree of Life (one an island, Logic/Tree); `list`, `byId` |
| `Data/Creatures` | the 55 driftlings (GAME_DESIGN 6) `{ id, name, islet (its kind, Data/Islets), rarity (1 common .. 5 legendary), hp, atk, def, spd (kept only for `power`), knack, shape (its MicroModels body plan), body, accent, blurb, passive ({ name, fx }: its own, Data/Traits effects), power (its stats weighted, +12% a rarity step: the breeding rank) }`; `list`, `byId` |
| `Data/Traits` | what makes one driftling unlike another (GAME_DESIGN 6): `MAX` (4 mutations), `KEYS` (the effects: work farm fish wood shop (shares at work), eat (food eaten), sell (the price), charm (whole points), tree, luck (the Tree of Life's speed and luck, from a driftling in a hut); 0.1 = +10%), `RARITY` (`{ name, color, weight }` x 5: the tree's weights before luck, 100 45 16 5 1.2), `TIER_COLOR`, `TIER_STARS`, `list`, `byId` (mutations `{ id ("sturdy3"), family, tier (1 .. 4; 0 a flaw), name, blurb, fx }`: ten families x four tiers and five flaws; the families keep their old ids, "sturdy" now Light Eater and the rest, so older saves read them), `families`, `at(family, tier)`, `roll(rng, rarity) -> { id }` (0 .. 3, no family twice, a rarer one rolls fewer flaws and higher tiers), `sum(passive?, muts?) -> Fx`, `workAt(fx, knack)` (work + the knack's share, at least -0.5), `clean(muts)` (known ids, a family once, at most MAX), `describe(fx)` ("+24% at farms, eats 30% less, +2 charm") |
| `Data/Quests` | the questline (GAME_DESIGN 9) `{ id, title, text (what to do and where), goal { kind, n, of? }, reward { shells?, food?, wood? }, go (its Go: a panel "pals" "index" "hatch" "tree", or "build" / "build:<tab>"), icon (a `mini_` sprite) }`, twenty in order; `list`, `byId`. Goal kinds: helpers (driftlings at work) housed (in huts) sold speed luck built (of a building kind) paths decor grown best (a rarity grown) tier seen hatched |
| `Data/Islets` | the 9 kinds of land the driftlings come from (GAME_DESIGN 6) `{ id, name ("Beach"), plural, tier (the island tier its driftlings start growing on the tree at: Beach, Meadow 1; Snowfield, Mangrove 2; Volcano, Grotto 3; Reef 4; Bluffs 5; Ruins 6), wild (every driftling of its kind, from Data/Creatures, the commonest first), color, blurb }`; `list` |
| `Data/Looks` | skin, hair, hair style and shirt lists (`Types.Look` indexes them: the founders and the visitors; `Data/Names`, the villagers' names, went with them) |
| `Data/Office` | the island's six tiers (`plans[tier]`: `{ tier, name }`, Castaway Cay, Palm Isle, Grand Isle, Harbor Town, Coral City, Sunspire Capital: the island card's title), `plan(tier)`, `origin(plot)` (Data/Street's). The island has no house (GAME_DESIGN 8) |
| `Data/Street` | the islands and the sea (GAME_DESIGN 8): `warm(tier)` (works a tier's cells out now: tens of ms at the top tiers, so never at an expansion), `MAX`, `SPACING`; the heights `LAWN_Y` (-0.5: the grass), `SAND_Y`, `WET_Y`, `FOAM_Y`, `SHALLOW_Y`, `WATER_Y` (each band a little lower than the one inside it); the cell layers `GRASS SAND WET FOAM SHALLOW SEA_CELL` and how far past the coast each reaches, `BANDS` (`sand` 2.5, `wet` 3.5, `foam` 4.5, `shallow` 8 studs); `BOARD` / `SEA` (plot-local z bands), `FAR` / `END_FAR` (water past the invisible walls: no sky at the world's edges), `LOT` (a plot's lot: x +-40, z -64 .. 30, room north for the city tiers), `CENTER`, `PLAZA` (the campfire's plaza), `PATH` (the path to the jetty); the coast: `isle(tier)` (its oval: centre, radii, wobble phases), `coast(tier, x, z)` (studs from the coast, below 0 inland: the oval's radius times a wobble of four sines, joined
to every smaller tier's shape (the least distance) so an island only gains land as it grows), `layerAt(d)`, and per whole-stud cell (cached per tier; `cellKey`) `layer`, `cellDist`, `cellBounds(tier)`, `buildable(tier, x, z)` (grass a stud or more inside the coast), `walkable` (grass, sand, wet sand), `plot(tier)` (the grass's bounding box); `origin(i)` (plots centred on x = 0), `plotAt(x, z)`, `bounds()`, `footpath()`, `jetty(tier)` (planks from the island's sand to the boardwalk), `spawn()` (on the path below the plaza), `sign()` / `mailbox()` (either side of the jetty's foot), `LAMPS`, `PIER_X` / `PIER_Z` / `PIER_W`, `pier()` |

Coordinates in `Data/Street` are studs, plot-local, +Y up. The camera looks from the south-east (+X, +Z), so an
island's back is its north-west. A piece's `rot` turns its model (built facing +Z: south, toward the viewer).

## 6. Logic and models

Pure rules (`src/shared/Logic`), all specced in `tests/specs`; every action returns `(true, data?)` or `(false,
ErrCode)` and changes the profile only on success:

| Module | API |
|---|---|
| `Util` | copied from Random Bakery: `hash32`, `newRng(seed)` (xorshift32: `next int range chance weighted`), `pick`, `shuffle`, `Signal`, `round clamp lerp isFinite sig2 deepCopy count` |
| `Island` | the turn and the day (GAME_DESIGN 3): `piece(p, uid)`, `nests` (the huts' room), `fxOf(pal) -> Fx` (its passive and mutations, `Traits.sum`), `charm` (every piece's, and each driftling in a hut: 1 + its charm share), `visitors`, `works(id)` (a building that makes something), `homes(p) -> { [key]: { uid, comfort } }` (each hut driftling's hut and its comfort (the hut's plus `ComfortLvl` by level), "p<id>", none for the pen's), `boosts(p) -> { farm fish wood shop all }` (each kind of boost building once), `boostAt(b, knack)` (its own and "all", `BoostMax` at most), `palWork(p, pal) -> number` (its work share at its building's knack, `Traits.workAt`), `palBoost(p, pal, comfort?)` (`PalWork` x `RarityWork[rarity]` x max(0, 1 + `palWork` + the hut's comfort): what a driftling puts in), `rates(p) -> Rates` (`{ food, wood, shells, made, eaten }` a turn; a building makes its rate times its driftlings' `palBoost` summed (`IdleOutput` with nobody), times 1 + `boostAt`, times `UpgradeMult` by level, half while hungry; the huts' driftlings eat `EatPal` x (1 + their eat share), the pen's nothing), `step(p, dt)` (the stores, the food never below none), `randomLook(rng)` (a visitor's), `freeJob(p, knack) -> uid` (the emptiest building of that knack with fewer than `HelpMax` driftlings, 0 none), `newDay(p)`, `setHelp` (only a driftling in a hut, at a building of its knack: `HelpMax` a building, the first there sent back to rest; bad_payload for the pen's), `expandCost(tier)`, `expand(p)` (data `{ tier, moved, cleared }`: `Plot.refit`), `setFounder` |
| `Plot` | building (GAME_DESIGN 4): `ROTS`, `limit(tier)`, `footprint(id, rot)`, `rect`, `blockers(tier)` (the campfire's plaza and the path to the jetty), `isFixed(id)` (the Tree of Life), `fits(tier, placed, id, x, z, rot, skip?) -> (ok, "outside" (a footprint cell not `Street.buildable`) / "blocked" / "overlap" / "unknown")`, `spot(tier, placed, id, x, z, rot) -> (x?, z?, rot?)` (the free spot nearest x, z: Logic/Tree plants with it, `refit` moves with it), `toPen(p, uid, keep?)` (a hut's driftlings past its first `keep` back to the pen, resting), `pathLimit(tier)` (`PathPieces`), `isPath(id)`, `used(p, id) -> (n, limit)` (the pieces of its count: paths, or the rest; the tree counts like any piece), `place` (bad_payload (an unknown piece, a home of the old saves, the tree, or a piece of tier 99), locked, full (by its count), money, wood, blocked), `move` (the tree too; blocked for the spot; no upgrades: taken out 2026-11-11; a level from an older save stays and counts), `replaceCost(q, id)` (the new price less `Refund` of the old, never below nothing), `replacements(q, tier)` (the others of its kind open at the tier; none for the tree), `replace(p, i, id)` (bad_payload (another kind, the same piece, the tree), locked, money, wood, blocked (the new footprint where the old stands); a smaller hut sends its extra driftlings to the pen; the uid kept, the level 1, driftlings of another knack back to rest), `store` (fixed (the tree), egg; `Refund` back; a hut's driftlings back to the pen), `refit(p) -> (moved, cleared)` (pieces that do not fit move to the nearest free spot, or are cleared with their whole price back: after the island grew and when a save loads); drawn paths (GAME_DESIGN 4: Build mode's draw bar): `PATH_STEP` (2: a path tile's cell, even studs), `PAINT_MAX` (40 cells a request), `cells(s) -> { {x, z} }` and `cellString(cells)` (the payload's "x,z;x,z"), `paint(p, id, cells) -> (ok, { placed, skipped })` (a path piece only; each free cell gets a tile at rotation 0, a cell that doesn't fit is skipped; locked, full, money, wood or blocked (none laid)), `unpaint(p, cells) -> (ok, { removed })` (every path tile covering a cell comes up with `Refund` back; not_found) |
| `Tree` | the Tree of Life and its pen (GAME_DESIGN 6): `ID` ("tree"), `SPOT` (-3, -4: behind the campfire), `hutFx(p) -> (tree, luck)` (the huts' driftlings' shares, at most `HutTree` / `HutLuck`), `secs(p, level?)` (`TreeSecs[speed]` / (1 + the tree share)), `luck(p, level?)` (1 + `TreeLuck` x (level - 1) + the luck share), `pool(tier) -> { { sp } }` (by rarity, the kinds open at the tier), `odds(p, luckLevel?) -> { share }` (each rarity's weight x luck^(r - 1), a rarity the pool lacks given to the next commoner one), `inPen(p)`, `resting(p)` (`PenSafe` or more waiting: the tree rests), `worth(pal)` (`RarityWork` x (1 + its share at its knack): the pen's order, kept per driftling table in a weak table, its kind and mutations never changing), `penView(p, n) -> (best, count, commons)` (the pen's best n in order, picked in one pass, how many wait there and how many are commons: Session.view), `stage(p, luckLevel?)` (1 .. #`TreeStages`: the Luck milestones reached), `nextStage(p)` (the next milestone's Luck, nil at the last), `price(pal)` (`SellPrice` x (1 + `SellTier` x its mutation tiers) x (1 + its sell share), whole shells, at least 1), `huts(p) -> { Hut }` (`{ uid, room, comfort, n }`, the comfiest first, then the first built), `settle(p) -> { id }` (the pen's best by `worth`, not `held`, among those a building of their knack has a free place for (`Island.freeJob`), into the huts with room, the comfiest first, each taking that place: who moved; one with nowhere to work stays. Nothing when no hut has room; else one pass keeps each knack's best few, as many as its free places, so a big pen is never sorted whole), `fillJobs(p)` (resting hut driftlings to free jobs), `roll(p, rng) -> (sp, muts)` (a rarity by `odds`, a kind of it, `Traits.roll` at the rarity + (luck level - 1) // `TreeMutLuck`), `add(p, sp, muts) -> Pal` (into the pen: `seen` 2, `stats.grown`, `stats.best`), `step(p, dt, rng) -> (grown, sent)` (`t` grows by dt; at every `secs` a driftling grows into the pen, which has no room limit and sells nothing; while `resting` `t` waits at `secs`; then `settle`), `upgradeCost(p, what) -> shells?` (nil at the top), `upgrade(p, what)` ("luck" | "speed": max, money; shells only), `sell(p, id)` (not_found; its price, `stats.sold`, `stats.earned`; a hut's gap filled from the pen), `sellPen(p, r)` (every driftling in the pen of rarity r or commoner, or not_found), `house(p, id, uid, swap)` (uid 0: to the pen, `held` (it always has room); a hut: a job of its knack if one is free; a full hut only in a swap with `swap` (one living there), which goes where this one was; not_found, bad_payload (not a hut, a swap not living there), full; then `settle` and `fillJobs`), `equipBest(p) -> (ok, { moved, out, ids })` (Equip best, GAME_DESIGN 6: every `held` let go; the best by `worth` of all the driftlings, huts' and pen's, as many as the huts' room and each knack's places (`HelpMax` a building of its knack, none taken) allow, picked as `settle` picks; the chosen in a hut stay put with their job, the chosen in the pen move in, the best into the comfiest room left; the huts' others go back to the pen (home and work 0) only as many as the newcomers need room, the weakest first, and give up a job only to a chosen one of their knack with no free place, the weakest first; then `fillJobs`; `moved` in from the pen, `out` back to it, `ids` both; bad_payload with no hut), `piece(p)`, `plant(p) -> Piece?` (an island with no tree gets one at `Plot.spot` from `SPOT`; on an island with no spot left the pieces nearest make room, paths first, then decor, then the rest that houses nobody, each with its whole price back) |
| `Breed` | the Hatchery (GAME_DESIGN 6.1): `child(a, b) -> sp` (a pair of one kind its kind, else the kind (no legend unless both are) of power nearest their average; the commoner, then the first id, on a tie), `cost(sp) -> (food, turns)` (`BreedFood`, `BreedTurns` by its rarity), `inherit(ma, mb, rng) -> muts` (shared: always, the better tier, `BreedTierUp` one better; one parent's: `BreedKeep`; `BreedNew` a tier 1 or 2 of a new family; the best four), `eggAt(p, uid)`, `start(p, uid, a, b, rng)` (not_found, egg, bad_payload, food; the feast paid, `p.eggs` + 1), `turn(p) -> { Pal }` (each egg a turn nearer; a ready one hatches into the pen (`Tree.add`, `stats.hatched`), then `Tree.settle`) |
| `Quest` | the questline's rules (GAME_DESIGN 9): `Facts` (`{ pals, pieces, tier, tree, seen, stats }`: a profile's, `facts(p)`, or the client view's, same names), `count(facts, goal)` (how far: driftlings at work (`helpers`), path tiles, decor, pieces of a kind, driftlings in huts (`housed`), the stats' counts (`grown`, `sold`, `hatched`), the rarest grown (`best`), the tree's `luck` and `speed` levels, the tier, kinds in the Index), `current(tut, i) -> (Quest?, i)` (none while the tips are on, or past the last), `progress(facts, q) -> (have, need)`, `done(facts, q)`, `claim(p)` (not_found, not_done; the reward paid, `p.quest` + 1; data `{ id, shells, food, wood, next }`) |
| `Schema` | `VERSION` (11: no villagers), `default(now, seed)` (`tree` `{ luck 1, speed 1, t 0 }`, then `Tree.plant`), `migrate(raw)` (1 -> 2: a founder; 2..4 -> 5: the studio gone, the founder, settings and start kept; 5 -> 6: the tips' steps moved (3 -> 5, 4 -> 6); 6 -> 7: each driftling rolls its mutations once, seeded by its kind and id; 7 -> 8: the questline; 8 -> 9: `boat` and `chart` gone; 9 -> 10: `cap`, `islets`, `sea`, `wilds` and `pouch` gone, a Training Yard refunded (450 shells, 50 wood), the driftlings put in the nests (now huts) in the old order (the comfiest first, in the order they came), the rest to the pen, `tut` past 5 back to 5, `quest` 1, `stats.grown` from the old `befriended`, `stats.best` the rarest kept; 10 -> 11: `folk` gone, every home (Tent .. Manor) taken down with its whole price back, `tut` past 4 back one, `stats.movedIn` gone), `reconcile(raw, now, seed)` (any table -> a valid Profile: pieces that exist with unique uids and valid turns (one tree at most), driftlings with unique ids (at most `MAX_PALS`, `PenSafe` + 5000) (a driftling's `home` a hut with room or the pen, `work` only from a hut at a building of its knack, `held` 1 or none, `muts` through `Traits.clean`), `tree` levels in range and `t` finite, the Index's species, `nextId` past every id, `tut` 0 .. 6; then `Plot.refit`, `Tree.plant` and `Tree.settle`) |
| `Validate` | `ACTIONS` (the action catalogue, §7.3), `request(action, payload) -> (ok, err?)`: exact schemas, unknown and missing fields refused |
| `Numbers` | `int`, `short`, `coins`, `rate`, `perMin` ("+57/min"), `oneIn` |

Models (`src/shared/Models`, Roblox modules):

- `Blocks` (copied): `part(parent, spec)` (anchored, SmoothPlastic or Neon, sizes on the 0.25-stud grid, palette
  colours), `cylY`, `model`, `color`, `snap`. `pace(fn?, every?)`: from the thread that calls it, `part` calls `fn` (a
  `task.wait`) after every `every` (60) parts, so a big build spreads over frames; other threads are never paced;
  `pace(nil)` ends it (PlotService's next islands).
- `CharacterModels.build(look, name, seed) -> Rig` (a seated chibi, the portraits'; the head's parts with a glint in
  each eye, brows, a mouth and ears, sizes exact to the eighth of a stud), `buildStanding(look, name, seed)` (a
  standing chibi: the founders and the visitors: soles, shoes, bare shins under shorts, a shirt with a belt and buckle,
  a collar and two buttons, sleeves, bare forearms and fists, the head raised a stud), `posePose(rig, base, Pose)`
  (`Pose { lean, twist, crouch (the knees bend to keep the feet down), lift, hipL/R, kneeL/R, armL/R (CFrames about
  the shoulders), elbowL/R, head, mood }`; moods `calm fierce shout hurt happy ko` move the brows, open or shut the
  eyes and the mouth), `poseStanding(rig, base, t, speed)` (the walk: knees and elbows bending, or the stand),
  `poseAction(rig, base, t, speed, action, k?)` (`cheer hurt swing reach pet cast jump sneak dance`, the
  fights' `windup strike guard throw run victory ko` (nothing plays them now), and the island's work, each a loop with `k` the beat's phase:
  `dig pick fish chop saw sell serve hammer train tend`), `WORK_HIT` (where in a beat a work's blows land:
  `{ [action]: { phase } }`), `STAND_TOP`.
- `Blocks.windy(root)`: the wind's tags for the pixel filter (§9.3): every part named `Flag...` or `Pennant...` (not
  a `...Pole`) gets `PixelWind` 2, every part in `leaf` or `leaf_dark` `PixelWind` 1 (water parts left alone). Called
  by `StreetModels.land` and `DecorModels.build` on their models.
- `BoatSpec` (the boat's plan, one for every boat: GAME_DESIGN 8; the pier's boat is always level 1 scenery since the
  boat upgrades went, the ambient boats are levels 1 to 3): `MAX` (6), `dims(level) -> { L, W, H }`,
  `deck(level)` (the four places on deck, founder first: deck-top coordinates, +Z the bow), `moor(level)` (its x, z
  by the pier), `deckOverWater(level)`, `parts(level) -> { { name, shape ("Block" "Wedge" "CylY"), size, cf (from the
  deck top's centre; the `Bow` wedge turned over: tall at the hull, its keel sloping up to the point), color, neon?,
  wind? } }` (the hull and every detail of GAME_DESIGN 8 by level; flags named `Flag...`). Every user applies `cf`'s
  rotation (MicroModels.ship, StreetModels.boat).
- `StreetModels`: `road(parent, origin)` (a plot's stretch of the sea, `PixelWater` 1; the plank boardwalk on beams
  and posts with its rope rail and lanterns; its pier and moored boat, `boat` at level 1), `boat(parent, origin, level) -> Model` (a
  `BoatSpec` boat, attribute `Level`, its flags `PixelWind` 2), `land(parent, origin, tier)` (the island: its
  cells meshed into rectangles layer by layer (the shallows `PixelWater` 2, the foam 3, wet sand, the beach, the grass
  in two tones), the invisible coast walls round the walkable cells, the campfire's plaza (`FireStone`s, logs, a
  flame, seats, a flag, torches), the stepping-stone path and the jetty (`JettyPlank`s on beams and posts, a rope),
  the sign with its `SignBoard`, the mailbox, and palms, rocks, shells, starfish, driftwood, seaweed and tufts strewn
  by the plot's own seed; `Blocks.windy`), `emptyLot(parent, origin)` (open water and a sandbar), `ends(parent)` (the sea past the
  ends, sandbars, the boardwalk's last lantern, the invisible walls along each end's own stretch of boardwalk, and
  the walls round the world, 40 studs high (past any jump); the pier's things, `PierProps`: bollards, crates, a barrel, rope, and the
  moored `Boat` don't collide). Every wall is
  in the collision group `Bounds`, which the pixel filter's rays (group `PixelRays`) pass through.
- `DecorModels.build(id, at, lvl?) -> Model` (every building and piece of decor; `lvl` goes to the builder: the tree's
  is its stage; `at`: the footprint's centre on the
  grass, turned; each with its doors, windows, ridged roofs with eaves and its own props (crates, barrels, sacks, pots,
  fences, lamps); a lamp and a pennant (`PennantPole`) at Lv 3; the pier's pond and the fountain's water `PixelWater` 2; parts don't
  collide; `Blocks.windy`), `has`. The Tree of Life (`tree`, 6 x 6, 13 studs tall; GAME_DESIGN 6 has the references
  it was drawn after): a `Lawn` and `Moss`; a ring of ten `Stone`s (`StoneMoss` caps, a Neon `Glyph` on every third,
  a gap at the front); `Root`s in eight directions; a `Trunk` core with drums and three braided `Strand`s, Neon
  `Rune`s up it; the `Hollow` at the front with its glowing `Pod` (Neon), a `Lintel` and two `Jamb`s; `Branch` limbs
  forking out to seven leaf clouds (`Leaves`: a dark underside, a main ball, side puffs), each with a `Blossom`, a
  `Vine` and `VineTip` hanging and Neon gold `Fruit` under it; a `Ring` of gold Neon dashes on the ground, `Mote`s,
  mushrooms (`Stalk`, `Cap`) and `Flower`s. No pen. `DecorModels.HOLLOW` is the hollow's foot in the model's frame
  (WorldView brings a driftling the pen sent on out there). The homes (Tent .. Manor) are gone with the villagers.
  The tree's stage (`lvl` 1 .. 4, `Tree.stage`) scales it above its fixed ground: the trunk's girth, the limbs' and the
  ring of clouds' height, the top cloud's height, the crown's spread and each cloud's size; more `Rune`s, lit
  `Glyph`s, `Blossom` and `Mote`s; `Lantern`s (Neon) from stage 2; eight ring clouds, four more above them and three
  `Fruit` a cloud from stage 3; at stage 4 blossom on every cloud, a `Halo` of gold Neon over the crown, gold
  `StoneMoss` caps and a second `Ring`. No pennant for it.
- `MicroModels` (the driftlings and the island's small things): `build(kind, opts?) -> Thing` (`{ model, parts, rest, sizes,
  baseRest, baseSize, colors, h, r, kind }`, a few palette parts round the origin, facing +Z), `driftling(shape, body,
  accent)` (the 14 shapes `blob crab bird bun lizard owl pup mole bat yeti seal sprite jelly wyrm`), `sailboat`,
  `ship` (a boat from `BoatSpec` at `opts.level`: its origin on the waterline; StreetLife's boats), `flutter(thing, t)` (a
  thing's `Flag...` parts ripple: their depth and height step through four frames), ambient kinds (`bird
  butterfly light flame crab ...`), `slab`, `grid`, `hoop`, and the fights' `aim`, `aimpath` and `aimring` (nothing
  builds them now), `place(t, cf)`, `scale(t, k)`,
  `recolor(t, color?)`, `show(t, on)`, `has`. Parts keep their sizes to the eighth of a stud (about an art px), not
  Blocks' quarter. `driftling(shape, body, accent)` is `DriftModels.build` (below); `animate(t, time, mood, k?)` hands
  a driftling (`t.rig`) to `DriftModels.animate` with the squash of `scale`, and moves the other things' limbs by name
  (`Wing*` flap, `Tail*` wag, `Eye*` blink...; `flap(t, cf, phase, glide?)`). WorldView and StreetLife call it every
  frame.
- `DriftModels` (GAME_DESIGN 6, "more detailed ... look more like the animals", "different moving parts"): the 20
  body plans (`PLANS`: `blob crab bird bun lizard owl pup mole bat yeti seal sprite jelly wyrm snail turtle frog moth
  golem drake`), each 25 to 50 parts in its species' body and accent colours (eighth-stud sizes, wedges for beaks and
  tails), built on a skeleton: `Rig { joints (name -> { parent?, pivot, kind, side, phase }), order (parents first), of
  (part -> joint), gait ("quad" | "biped" | "hop" | "scuttle" | "slither" | "fly"), world }`. Joint kinds: `body` (the
  root), `head`, `neck`, `jaw`, `ear`, `arm`, `leg`, `tail` (segments in a chain, `phase` their order), `wing` (an
  outer segment as a child), `fin`, `stalk` (eye stalks), `pincer`, `tendril` (two segments), `antenna`, `shell`.
  `build(shape, body, accent) -> Thing` (with `rig`), `has(shape)`, `animate(t, time, mood, k?, squash)`: every joint's
  turn and shift about its pivot for the moment and the mood, composed down the chain (`world[j] = world[parent] *
  pivot * turn * pivot^-1`), then each part's rest pose (times the squash). Idle: breathing, a look about every 6 s,
  a yawn every 9 s, ear twitches, a slow tail sway and wing flutter, a blink every 3.4 s; walk by gait (legs in
  diagonal pairs, both hind legs and a hop, a sideways scuttle, a slither's sway, flight's flapping); attack (a
  wind-up at k 0, then the body and head lunging, the jaw open, arms and pincers up, the tail raised), hurt (a recoil,
  ears down, eyes shut), cheer (head up, arms up, ears wiggling, quick wags) and ko (limp). The island's work moods
  (WorldView): `peck` (bursts of pecks at the ground, jaw open at the bottom), `push` (leaning in, pacing on the spot,
  arms forward), `dip` (head dipping for fish, a snap every 4 s), `wave` (a raised arm waving, chattering, wings
  beating, quick wags), `nap` (low and breathing slowly, eyes shut, head down, wings folded) and `hop`. Later segments of a tail
  or wing swing less (the tip doesn't whip round). `Eye*` shut by size (their shines tucked behind), `Mouth` opens.

## 7. Server

### 7.1 Remotes (`Net`)
`ReplicatedStorage.Remotes`: `Request` (RemoteFunction, C->S `(action, payload) -> Response`), `Signal` (RemoteEvent,
C->S `(kind, payload)`; no handlers in this version), `State` (RemoteEvent, S->C the whole `ClientView` when it
changed), `Fx` (RemoteEvent, S->C `{ kind = "tick", shells, food, wood, dayFrac, grow (the tree's `t`), secs (`Tree.secs`) }`
every second, `{ kind = "tree", grown? (the Pals grown into the pen), sent? (the ids the pen or the player moved) }`
when the tree or the pen moved someone, `{ kind = "treegrew", stage }` when a Luck milestone made the tree bigger,
`{ kind = "turn", hatched? (the Pals hatched: Breed.turn) }` at each turn's
end, `{ kind = "day", day }` at each of the sea's days, `{ kind = "quest", data }` on a
claim). `Net.serverInit()` creates them; `Net.clientInit()` waits for them.

### 7.2 `Session`
`create(player, profile, plot) -> S` (`{ player, profile, plot, rng, ready, turnClock, dayIndex, tickClock, dirty, saveAt,
reqTimes }`), `get`, `remove`, `all`, `view(s) -> ClientView` (the hut driftlings and `Tree.penView`'s best `PenShown` of the pen, `penN`, `penCommons`), `markDirty`, `flush` (sends State when dirty), `fx(s, msg)`, `allow(s, now)` (the rate
limit).

### 7.3 `Router` and the action catalogue
`Router.on(action, fn(s, payload) -> (ok, data|err))`, `Router.onSignal(kind, fn)`, `Router.handle(player, action,
payload) -> Response` (not ready -> `not_ready`; over `Tuning.RateLimitPerSec` -> `rate`; `Validate.request`; the
handler under pcall; success marks the session dirty).

| Action | Payload | Rule | Errors |
|---|---|---|---|
| `plot.place` | `id x z rot` (coords whole studs in [-64, 64], rot a quarter turn) | `Plot.place`, the buildings rebuilt by difference, then `Tree.settle` and `Tree.fillJobs`, the tips | locked, full, money, wood, blocked, bad_payload (the tree) |
| `plot.move` | `i x z rot` | `Plot.move` (the tree too) | blocked, bad_payload |
| `plot.paint` | `id cells` ("x,z;x,z": 1 .. 40 cells, whole studs in [-64, 64]) | `Plot.paint` (data `{ placed, skipped }`), the buildings rebuilt | locked, full, money, wood, blocked |
| `plot.unpaint` | `cells` | `Plot.unpaint` (data `{ removed }`), the buildings rebuilt | not_found |
| `plot.replace` | `i`, `id` | `Plot.replace` (data `{ i, uid, id }`; the island's pieces rebuilt) | bad_payload, locked, money, wood, blocked |
| `plot.store` | `i` | `Plot.store` (clear away; a hut's driftlings to the pen) | fixed (the tree), egg (a Hatchery holding an egg), bad_payload |
| `breed.start` | `uid`, `a`, `b` | `Breed.start` (an egg at the Hatchery `uid` from driftlings `a` and `b`) | not_found, egg, food, bad_payload |
| `island.expand` | - | `Island.expand`, the island rebuilt (data `{ tier, moved, cleared }`) | max, money, wood |
| `pal.work` | `id uid` (0: rest) | `Island.setHelp` | not_found, bad_payload |
| `pal.house` | `id uid swap` (uid 0: the pen; swap 0: none) | `Tree.house` (Fx tree) | not_found, bad_payload, full |
| `pal.sell` | `id` | `Tree.sell` (data `{ shells, sold }`) | not_found |
| `pen.sell` | `r` (a rarity 1 .. 5) | `Tree.sellPen`: the pen's driftlings of rarity r or commoner (data `{ shells, sold }`) | not_found |
| `pen.best` | none | `Tree.equipBest`: the best of all the driftlings into the huts (data `{ moved, out, ids }`) | bad_payload (no hut) |
| `tree.upgrade` | `what` ("luck" or "speed") | `Tree.upgrade` (shells only), the tips; a Luck milestone builds the tree again at its new stage (Fx treegrew) | max, money |
| `founder.set` | `skin hair style shirt` | `Island.setFounder` (the `Founder` attribute follows on the next sync) | bad_payload |
| `settings.set` | `k` ("pixel" or "music"), `v` | the pixel tier (high, medium, low, off) or the music (on, off) | bad_payload |
| `tut.next` | - | the tips go away for good | - |
| `quest.claim` | - | `Quest.claim` (data `{ id, shells, food, wood, next }`) | not_found, not_done |
| `char.home` | - | PlotService puts the founder on their path | cooldown (`Tuning.HomeCooldown`), not_ready |

The expedition actions (`exp.*`, `pouch.upgrade`) and `pal.release` are gone (2026-11-12), and the villagers'
`folk.work` and `folk.dismiss` with them later that day: `Validate` answers them `unknown_action`.

### 7.4 `IslandService`
Registers the actions above. `step(dt)` (Main's fixed 10 Hz step), for every ready session: `Island.step`, the view
sent when the food runs out or comes back, `Tree.step` (what grew and who the pen sent on: Fx "tree", the session
dirty; at the save's limit, `Tuning.PenSafe` waiting, the tree rests), a turn every `TurnSeconds` (`Breed.turn`: Fx
"turn"), a day each time the sea's clock
passes a day's end (`WorldClock.dayIndex` past the session's `dayIndex`: `Island.newDay`, Fx "day"), the stores and
the tree's growth every second (Fx "tick" with `WorldClock.dayFrac`, `grow` and `secs`: the whole view is not sent
for them). `WorldClock` (server): the sea's clock, `os.time()` at start advanced by every step (`now`, `advance`,
`shift(seconds)` for the sims and previews, `dayIndex`, `dayFrac`); a day is `Tuning.DaySeconds` (4 hours). The tips
(`tips(s)`): 1 .. 4 move on when a building of the kind they ask for stands (food, wood, shop, a hut), 5 when the tree
has a level of Luck or Speed, 6 on OK (`tut.next`). Every building change (`rebuilt`) runs `Tree.fillJobs` and
`Tree.settle` before the island's models are rebuilt. Nothing happens while the player is away.

### 7.5 `PlotService` (the sea)
`init()` registers the collision groups `Bounds` (the invisible walls) and `PixelRays` (the pixel filter's rays),
not colliding with each other, and builds the whole sea: `Workspace.Plots.Street` (every plot's boardwalk stretch,
`Road_<i>` with its pier's `Boat`, always level 1 scenery since the boat upgrades went, and the sea's ends) and open
water on every plot (`Plot_<i>.Static.Land` = `EmptyLot`, attribute `Owner` 0). `claim(player) -> plot` (the lowest
free index, 0 when the sea is full: Main kicks), `release(i)` (back to open water, every attribute cleared).
`build(s)`: `Plot_<i>` gets `Owner`, `OwnerName`, `StudioName` ("Name's Isle"); its `Static` gets
`Land` for the island's tier (rebuilt only when `Static`'s `Built` attribute differs: the island for that tier built
ahead is swapped in when it is ready, else it is built there and then) and `Decor` by difference
(`buildDecor(s)`: one model a piece, named `uid:id:x:z:rot:lvl`, the Tree of Life's `lvl` its stage, `Tree.stage`; models whose key is unchanged stay), then `sync(s)`:
the attributes `Tier`, `Day`, `Charm`, `Pals` (the hut driftlings, `;`-separated `id.species.work.home`: the pen's are
left out, so it stays small however many wait there; no `Folk` since the villagers went), and the player's `Founder` (`skin.hair.style.shirt`) and `Plot` (Main syncs
every dirty session before sending its view; only changed values replicate). The founder: `watchCharacters(player)`,
`placeCharacter(s)`, `spawnCFrame(s)`, `home(s)` (`char.home`, once every `Tuning.HomeCooldown`).
**The next island, built ahead** (GAME_DESIGN 4: the lag before an expansion): after each `build` a plot that can
still grow queues its next tier's `Land`; one background thread builds the queue, paced by `Blocks.pace` (60 parts a
frame), into a model kept out of the workspace (`nextLand[i] = { tier, model, gen }`; a newer plan or `release`
drops an older build). `init` works out every tier's cells first (`Street.warm`). `debugNext(i) -> (tier?, ready,
swaps)` (the sims' check).

### 7.6 Persistence (`DataService`, `Logic/Schema`)
One key per player (`u_<userId>`) in `Tuning.DataStoreName`, a record `{ data = Profile, lock = { job, t }? }`.
`load(userId) -> (raw?, ok)` takes the lock: while another server holds a lock younger than `Tuning.LockTTL` it
waits and retries, and on the last of `Tuning.LoadRetries` attempts (about 10 s) takes it over. `save(userId, profile,
release?)` never overwrites a record whose lock another server holds. Main: join -> claim a plot, load (kick on
failure), `Schema.reconcile`, build the island, ready, send the view; leave -> save with the lock released, free the
plot; autosave every `Tuning.AutosaveSec`; BindToClose saves everyone. Without DataStores (Studio without API access) saves live in memory and a warning says so. A new save shape
needs a `Schema.VERSION` step in `migrate` and a spec that an older profile still loads.

## 8. Client bootstrap and the mirror

`Main.client`: the loading card's `show()` (ReplicatedFirst's, nothing when Boot put it up), `StateClient.init`
(remotes), `PixelRenderer.init` (lighting), `CameraController.init`, the card's phase "island", wait for the first
view, `CameraController.start`, `PixelRenderer.start`, `DayLight.start`, `UIKit.init`, `WorldView.start`,
`AvatarView.start`, `StreetLife.start`, `Hud.start` (which starts `Menus`), then the card's phase
"picture": `PixelRenderer.firstPicture()`'s progress every 0.05 s until it is on screen (or 30 s), then `finish()`.

### 8.0 The loading card (`src/first`, ReplicatedFirst.Loading)
`Boot.client`: ReplicatedFirst's one script, run before the rest of the game has arrived: `LoadingCard.show()`, then
`ReplicatedFirst:RemoveDefaultLoadingScreen()` once the card is up. Nothing in it touches ReplicatedStorage (not
there yet): the palette's colours are written out and `PixelFont` / `PixelFontData` are mapped beside it.
`LoadingCard` (GAME_DESIGN 11): `show()` (once: a `LoadingCard` ScreenGui, DisplayOrder 300, no inset; a canvas of
`ceil(screen / K)` UI px under a UIScale K, the game's pixel size (`PixelScaleMin` 2 plus one per `PixelScaleSides`
entry the screen's short side exceeds); Roblox's touch buttons off while it is up), `phase(name)` ("island",
"picture"; it starts in "start"), `progress(f)`, `finish()` (the bar fills, `FADE_STEPS` (5) steps over `FADE_SEC`
(0.45) to clear, destroyed, touch buttons back; by itself after `SAFETY_SEC` (45)), `state() -> { up, phase, bar,
finished, fading, painted, fallback, actors, ticks, K, size, title (the title's block rect), island }`. Laid out from
the canvas's size (`layoutFor`: the horizon at 0.46 of the height, the island's middle and radii, the sun, the title,
status, bar and tip rows, `pathEnd` the last row of the sun's path) and built again 0.15 s after the camera's
ViewportSize changes: `paint(L)` writes the still scene into one EditableImage of the canvas's size. Its gradients go
through `bandAt(list, u, x, y, zone?)` / `band(list, t, ...)` (flat, then three dither steps of `stepOn(x, y, s)`: a
quarter, a half, three quarters). It paints the sky's bands, stars, the sun cut by the horizon with its halo, clouds,
far islands with palms; the sea's bands with the sun's glow (`SEA_LIT`: the sea's tones after two warm ones, the index
lifted round `sunX`), the horizon, wave dashes, the sun's path lines; the island from a class grid over its box (sea,
shallows' edge, shallows, near shore, foam, wet sand, beach, grass) by its ground distance to the coast (`shoreR(L, a)`:
the oval of radii `rx`, `ry / PITCH` times Street's four sines, `PITCH` 0.5), then tufts, flowers, rocks, driftwood,
the path to the jetty, the sand round the fire and the jetty. `buildAtlas()` decodes `LoadingArt` into one atlas EditableImage (the run-length
format of `gen_loading_art.py`), `placeScene(L)` lays the actors (ImageLabels on the atlas, `ImageRectOffset` per
frame, whole UI px, ZIndex by their foot's row) and `step(dt)` moves them at most `SCENE_FPS` (24) times a second
from the card's one Heartbeat: stills (the Tree of Life at the back in the middle, or at the back on the left when
its crown, `TREE_TOP` art px over its foot, would reach the bar); the fire, the boat (drifting right, wrapping), the
blinking tree, the cheering Conchy (a burst, a rest), walkers (driftlings up and down a lane, a pause at each end, the
sequence's name left and `<name>_r` right),
followers (a driftling `gap` px behind its walker), gulls, stars, crests and glints (a run, hidden, a new spot: open
sea at least 26 ground px past `shoreR`, or the sun's path as wide as its lines at that row), embers.
The words: `textImage` rasterises a line with `PixelFont.mask`
(the title in `BIG` with the "title" under layer and `PixelFont.smooth`'s anti-aliasing steps, the status and the tip
in `SMALL` with a drop shadow) into an EditableImage, centred on the canvas; the status's dots and the bar are Frames.
Without EditableImages (`fallback`): Frames and an Arcade TextLabel. `LoadingArt` (generated: `W`, `H`, `palette`,
`seqs[name] = { w, h, ax, ay, dur, at, pal, px, base?, head?, flame? }`): `frond`, `frond_r`, `pebble`, `pebble_r`,
`crab`, `crab_r`, `bun`, `bun_r`, `gullfin`, `gullfin_r`, `cheer` (a Conchy), `fire`, `palm`, `palm_b`, `nest`,
`burrow`, `torch`, `flowers`, `bush`, `tree`, `boat`, and the hand-made `gull`, `star`, `crest`, `ember`, `glint`.

### 8.1 `StateClient`
`init`, `view() -> ClientView?`, `waitView`, `Changed: Signal<ClientView>`, `Fx: Signal<msg>`, `Tick:
Signal<ClientView>` (Fx "tick": the view's `shells`, `food`, `wood` and `dayFrac` are patched in place, no whole view
comes), `request(action, payload) -> Response` (never errors), `signal(kind, payload)`.

### 8.2 `DayLight` (the day and night)
`start()`: the view's `dayFrac` (each tick and view; run on smoothly by `Tuning.DaySeconds` between them) sets
`PixelRenderer.setGrade(at(frac))` every frame (with the filter off,
`Lighting.ClockTime` instead: 6 at dawn, 18 at dusk). `at(frac) -> Grade?`: the day's keys (`KEYS`: dawn 0, morning
0.07, afternoon 0.6, dusk 0.68, twilight 0.75, night 0.81 to 0.95, dawn again at 1), the step between two keys in
`STEPS` (6) steps; nil when it is plain daylight. `frac()` (the time of day now: the HUD's music), `hold(grade?)` (a grade held over the clock's; nothing
holds one since the fights went; nil lets go), `debugSet(frac?)`
(previews: a fixed time), `debugState() -> { frac, grade, clock }`.

### 8.3 `Audio`
`play(name, opts?) -> boolean` (opts `{ volume, pitch }` times the event's; a voice not loaded yet is asked to load
so the next play is on time), `preload(names)` (every voice of those events made and loaded now, on its own thread;
nothing calls it since the fights went), `has(name)`, `EVENTS`: every sound by name (`click open close deny notice
ding coin coins combo sparkle cheer tick flip pop`; the happy moments, each its own library sound: `newcomer`
(`DoorChime`; nothing plays it since the villagers went), `grow` (the island grows, or an epic or legendary driftling grows on the tree: `BellTreeRun`), `friend`
(an egg hatched: `ChimeCluster`), `level_up` (a piece replaced: `SparkleTones`), `reward` (a quest claimed:
`Triangle`), `egg` (`MusicBoxWind`), `rare` (a rare one grown: `SparklePass`); the founder's feet (AvatarView):
`step_grass step_sand step_wood` (two or three takes each, `ids`), `jump`, `land`; the world's `hammer gull birds`;
the fights' sounds and their ids went on 2026-11-12), each one `Monetization.Sounds` id (0 =
silent), or a few takes (`ids`: one voice each, picked at random, never the same twice running), with a volume, a
pitch range, a cooldown (a repeat inside it is dropped), a few voices and maybe a stretch of the clip (`from`, `len`:
the hammer's first two taps, the door chime's first ding-dong; its last `fade` seconds tweened down, a fade still
running cancelled when the voice plays again; the voice stops when it is over) (Sounds in `SoundService.UISounds`,
reused). `playCount(name)`: how many times an event has played on this client (the sims: the footsteps). `ambience(name, volume)`: a looped sound (`waves`, `crickets`) faded toward a volume
(DayLight: the surf always, crickets at night). `music(mood?)`: the background music, a mood's playlist of
`Monetization.Music` ("day", "night"; nil: quiet) shuffled once and played round, track after track
(`Music_<mood>` Sounds at `MUSIC_VOL` (0.2) times the track's `gain`); a change of mood and each track's last `MUSIC_FADE` seconds crossfade (a track
that ends early hands on at `Ended`); a mood still fading out fades back in when asked again. `setMusicOn(on)` fades
it all away or back; `musicState() -> { mood, on, tracks }`. The HUD sets the mood every frame (night from 0.74 of the day to the dawn, else day) and `on` from
`settings.music`.

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
contact shade at the foot of upright faces. The **dynamic layer** is the islanders (the hut driftlings and the visitors) and the founders: every tick (the tier's Hz) their parts
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
`setFocus(p?, snap?)`: a cutscene's world point the pan keeps in the middle instead of the founder (unused since the walk in went), nil gives the
founder back; `snap` jumps there at once (behind the blinds) instead of gliding. `settled()`: the pan has reached its
target. `refit` on a new key starts the pan on the target (the founder or the focus), not on the island's middle.
A new tier's cells and the next one's are worked out 3 s after the view's tier changes (`Street.warm`).
`gridAt(px, py)` (the grid at a pan), `centerWorld()` (the view's ground centre now), `view()`, `refit()`,
`ViewChanged` (a new key: a new bake), `pixelK(size?)`, `setPixelLimit(h, classic)`. The Roblox camera is posed on the
pan now: far away at `CamFov` with the filter on, at `CamOffFov` in the classic style.
**Stage mode** (a microgame's or an islet's; nothing opens one since the expeditions went): `setStage(Stage?)` with `Stage = { name, origin, pts, tight?, top, bottom }` fits the
stage's points (`tight` instead on a screen under 600 px tall: a phone held sideways, the action's band drawn at a
bigger scale) full screen clear of the play overlay's top and bottom strips (art px), the ray plane at the stage's origin,
the key `stage:<name>|...`, no indoor room; the view holds still (`view().stage` true); `setStage(nil)` goes back
to the street; `stage()`. `setStageShift(shift, snap?)`: an endless islet's camera, the stage's framing moved by
`shift` studs (the target is the home pan plus the shift's grid px); on a stage the view glides, so the renderer
scrolls to the next area and never re-bakes (reset by `setStage`); `snap` puts it there at once (behind the curtain,
before the first picture: only the boat arrival, unused now, asked for it).

### 9.3 `PixelRenderer`
`init`, `start`, `setTier(t)`, `tier`, `isActive`, `unavailableReason`, `pixelScale` (K), `firstPicture() -> (shown,
progress)`, `registerDynamic(model)`, `unregisterDynamic`, `refreshDynamic`, `rebake`, `setPaused`,
`watchStage(root)` (unused now: a stage's static parts that come or go while it is in view re-cast their rects; a rect over one
already queued joins it while their box is no bigger than the two apart, so an endless islet's area landing in view,
hundreds of boxes, re-casts its union once instead of re-baking the whole picture over their overlaps),
`afterBake(fn)` (fn runs once the picture shows the world as it is now: after the pending or running bake, at once
when none is coming or the filter is off; Build mode's expansion cheers then), `project(world) -> (Vector2 full-screen px, on)`, `projectPixel(world) -> (i, j, on)`, `pixelAt(pos) -> (i, j)` (the
art pixel under an InputObject's Position, as `projectPixel` gives them), `screenRay(pos) -> (origin,
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
  layer re-bake it (a new island), 0.15 s later and with 8 ms more a frame (`rush`); while that re-bake is pending a
  part's rect is not worked out (an island's rebuild is ~2,500 of them in one frame). After a re-cast and at the end of a bake the shadow edges are refined
  (`refineShadows`, the tiers with shadows). Rects in global px survive pans.
- **Re-bakes behind the picture**: a bake started while a finished picture is on screen (`Surf.ready`; not a jump,
  whose picture is of another place) casts into fresh buffers (`back`) with its own part ids (`backTabs`, swapped in
  only while `bakeSome` runs), so the frames go on meanwhile: the models, the water and the wind keep drawing over
  the old picture at its camera (no pans or re-casts until it ends). The finished bake's buffers become the layer's
  and the whole image uploads. Before, the screen stood still for the whole bake.
- The bake's rays are in the collision group `PixelRays` (the invisible walls never meet them) and exclude
  `Workspace.PixelDynamic` and every player's character (refreshed when characters come and
  go). Dynamic models whose first part lies more than `CULL` (48) art px off the layer are skipped; at most
  `PixelMaxDyn` are drawn a tick.
- **Stages** (nothing opens one now): a stage view bakes at the street's budget; the
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
- **A spotlight** (once the battles'; nothing sets it now: `setDim(k)`, `debugDim()`): the static picture darkened by `dim` (0 .. 1,
  in tenths: each step re-uploads the picture) in `gradeSpan` after the grade, a static pixel (`id < DYN_ID0`) only and
  never a glowing one (`dimOf`, cached per colour: greyer by 0.35 x dim, times 1 - 0.5 x dim, cooled); the dynamic
  things (the fighters, their effects) as they are.
- **The time of day** (GAME_DESIGN 8; `setGrade(Grade?)`, `debugGrade() -> string` its key, "" by day): the layers
  keep their daylight colours; every uploaded pixel (`uploadAll`, `uploadRect`) goes through `gradeOf` (cached per
  colour and light level, cleared when the grade changes, which also uploads the whole picture): desaturated by
  `sat`, times `mr mg mb`, plus a blue `lift` in the shadows. `Grade { mr, mg, mb, lift, sat, lamps }`. Neon parts
  (`EMISSIVE` statics, `dynGlow` dynamics) keep their colour; round them `lightMap` (u8 a pixel, 0..3, rebuilt by
  `buildLight` when the picture moved or a part came or went, at most every `LIGHT_EVERY` seconds, and every second
  for the moving lights; a pan shifts it with the static layer, the strips coming in dark until the rebuild) pools
  warm light in three stepped rings (`RING`: 0.35, 0.65 and 1 of the radius, twice as wide as tall: the ground at
  2:1), each pool as big as its light (`lightRadius(area)`: `LIGHT_K` 1.2 x area ^ `LIGHT_POW` 0.6, between
  `LIGHT_MIN` 2 and `LIGHT_MAX` 22 art px): a static light is a patch of `EMISSIVE` pixels touching 8 ways (a flood
  fill over the static layer; its pool at the patch's middle, 3 px lower), a dynamic one a model's Neon parts together
  (their area the two biggest faces of each on the screen, art px per stud `cam.s / cam.K`; the pool at their
  area-weighted middle, 3 px lower),
  `lamps` of the way back to the colour by day, warmed, times how dark the hour is (`dark`: from the light's colour,
  0 by day and in the golden dusk, 1 at night) and 0.85 at most. As it gets dark the luminance over a knee is pressed
  down (`press`: up to 0.45 of it for white at night), so pale colours (shells, sand, sails) don't glow.
- **Blob shadows**: a dynamic model with a `PixelShadow` attribute (radius, studs) shades the static pixels in an
  ellipse under its PrimaryPart on the ground at `PixelGroundY` as in the sun's shadow (the palette's own shadow tone;
  never an ink line or the sky), smaller the higher it is; none while its PrimaryPart is see-through or below its
  ground (a stage's thing put away under the floor); drawn before the models, restored with their rects. The
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
`lineHeight`, `lines(text, w, face?)` (how many lines a wrapped label breaks it into), `plate(parent, size, pos?, color?, alpha?, corner?, style?)` (stepped corners with a 1 px ink outline
following them: "Fill" rects inside "Edge" rects, none overlapping; `style { edge = false }` a flat swatch, `{ shadow
= true }` a 2 px drop shadow right and below, "Shadow"; the island's looks (GAME_DESIGN 2): `{ wood = t }` a frame of
planks t px wide outside the outline and an ink outline round it ("Wood": a "Board" behind, "Hi" / "Lo" bevel rows,
"Seam"s every `PLANK` px, a "Nail" in each corner; the plate then takes t + 1 px more on every side, the shadow moved
out with it), `{ bevel = true }` a lit top row and a shaded bottom one, "BevelHi" / "BevelLo"), `plank(frame, h, k?)`
(a title plank across a plate's top, rows 1 .. h: "TitleBand" rects lit along the top and shaded along the bottom,
"Grain", an ink "TitleRule" at row h + 1), `setPlate` (the fill), `rect`, `button` (a TextButton with
a child "Words" label over a plate with a bevel, "Shine" and "Lip", recoloured with it; disabled = `AutoButtonColor`
false; fires on `Activated`), `setEnabled`, `setButtonText`,
`setButtonColor`, `buttonWidth`, `bar -> (frame, set)`, `clear`, `vlist`, `hlist`, `scroll`, `confetti(parent, n?,
colors?)` (a burst of 1 px pieces and 1x2 sticks that fly, tumble and fade), panels
(`registerPanel(name, { title, icon?, w, h, build })`: a plate in a frame of planks (`wood = 3`) with a drop shadow over a `sea_shade` veil, as big as asked within the screen less 10 px each way (its frame fits), a `plank` title (the title in `paper`), a coral `Close` (`button_close`), a `TitleBand` with the
`mini_<icon>` and the title, a `TitleRule` under it; `openPanel(name, arg)`, `closePanel`, `currentPanel`,
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
The islanders: a walker per hut driftling (`MicroModels.driftling` in its species' shape and colours), parsed from
each owned plot's `Pals` attribute and placed among the buildings read from its `Static.Decor` models' names
(`uid:id:x:z:rot:lvl`). A driftling goes to the building it works at (or its hut) and works there by its kind
(`palMoodOf`: `peck` in the fields, `dip` at a pier or kelp farm, `push` at the wood and the boosts, `wave` at the
shops, `nap` at a hut or the hatchery, for longer: `DriftModels.animate`'s work moods), now and then a stroll
(`strollPoint`: a buildable cell away from the campfire). The pen is not drawn. One new in a hut on an island already
peopled was just sent from the pen: it pops out of the tree's hollow (`hollowPoint`, `DecorModels.HOLLOW`) with a
cheer and walks off to work (`born`). Workers stand along the building's front, turned three-quarters to the view
(east or south). Only islands within 100 studs of the view's centre are drawn (synced every half second); each
near owned island's campfire gets a flickering flame and rising smoke (`fireOn`, dynamic models). Each island's sign gets
a World-root label (its name, the own in gold, or "Unclaimed isle"); a tap (a press let go within 8 px, not on the
interface, not in Build mode; its ray `PixelRenderer.screenRay` in the `PixelRays` collision group, as the
picture's, so it passes the invisible coast walls, which Roblox hits whatever their CanQuery says because they collide)
on a sign shows `signCard(i)` (the day, driftlings at home, charm).
**The Tree of Life** (GAME_DESIGN 6): a tap on the own island's tree (`treeOf`: a part of its `Static.Decor` model)
opens the "tree" panel before the signs are looked at; while the tips are on step 5 (not in Build mode) a label
"Tree of Life" and the `arrow_down_t` sprite bob over it (`updateTreeLabel`). Fx "tree" (`grownOne`) gives a rare or
better newcomer its name floating up in its rarity's colour; a hatchling (Fx "turn" `hatched`) a cheer, its name and
pink bits; `cheer(words, color)` makes the own islanders cheer.
`rigCount()` / `ownRigCount()` / `ownCount()` (the walkers drawn: all, the own island's) and `tapScreen(pos)` (a tap
at screen px, handled as a player's) for the sims.
`StreetLife` (client, started after AvatarView): four boats (`MicroModels` "ship" at BoatSpec levels 1, 2, 1, 3, blob shadows) crossing
both ways on two lanes out at sea, rocking on the swell in whole steps, wrapping round the sea's ends; a flock of three
gulls crossing every 14-24 s, each crossing its own (east or west, a slant, a height, a weave, each gull a little
behind the next), every gull turned the way it flies (the model's head is +Z) and gliding now and then (no clouds'
shadows: the player asked for them gone). `count()` for the CLI.

### 10.3 `Hud`
The island's looks (GAME_DESIGN 2): the chips are carved boards in thin frames of planks (`CHIP_Y` 5), the cards in
thick ones with their names on planks (`CARD_Y` = `TOP_H` + 15, 7 px in from the right), the menu bar stands on a
`Dock` (a dark board in a thin frame, `DOCK` 6 px round the buttons); the camera's strips are kept clear of all of it.
Chips (`Chip_shells`, `Chip_food`, `Chip_wood`, each an 11 px icon and the store easing to its value, flashing when
it changes (the food's red and blinking while hungry); `Chip_day`, "Day 3" with the day's clock along its edge and a
sun that sets into a moon; then `Home`, a button shown while the founder is off their own island, sending
`char.home`; `MusicToggle` in the top right corner, the `mini_note`, sending `settings.set` music on / off, the note
greyed while off), the menu bar (`Menu_build`, `Menu_pals`, `Menu_index`, `Menu_looks`,
each with its icon; while Build mode is open the bar and the cards step aside and the tips banner rises over the
tray with a Build mode wording (`TIPS_BUILD`)), the `IslandCard` on the right (the island's name for its tier,
driftlings in huts / the huts' room (`Pals`), visitors, charm, and what a day makes of food, wood and shells a minute:
`Numbers.perMin`), the `TreeCard` under it (GAME_DESIGN 6: "Tree of Life", the `GrowBar` with its `Fill` laid out
every Heartbeat from `StateClient.treeFrac()`, `Pen` "Pen 1,204" (`penN`: no room limit; orange at `PenSafe`, where the tree rests), `TreeOpen` opening the "tree" panel;
on a phone at the top left), the questline's card `Quest` (GAME_DESIGN 9: down the left
at `CARD_Y`, `QUEST_W` 150, under the `TreeCard` on a phone; hidden while the tips are on and for a panel; `updateQuest(v)` from the view through `Quest.current` / `Quest.progress`, laid out
again when the quest or its count changes, sliding in: the quest's `mini_` icon, `Title`, `Which` ("3/20"), `Words`,
then the `Bar` and `Progress` with `QuestGo` (`goTo(go)`: a panel, "tree" included, or `BuildUI.open(tab)`), or once done the reward (`Reward_<store>`) and `QuestClaim` (shining; `quest.claim`, then a
notice of what it paid)), the tips banner (`Tips`: the steps of GAME_DESIGN 9 (`tut` 1 .. 6: food, wood, shells, a hut, a level of the tree,
the last); tip 6 has `TipsOk`, sending `tut.next`; a parchment note in a thin frame; on a phone it keeps to the room left of the island card, wrapping to two lines), and the `DayBanner` (Fx
"day" and "turn": the day, what hatched; over a panel or in Build mode a notice instead); Fx "tree" with
a rare or better one grown: a notice in its rarity's colour ("A rare Floe grew on the tree."), an epic or a legend a
burst over the `TreeCard` (`onTree`); Fx "treegrew": "The Tree of Life grew bigger." (the last stage: "fully
grown"), the `grow` sound and a burst over the `TreeCard` (`onTreeGrew`). Shells
coming in rise from their chip ("+12", at most every 2 s, from `StateClient.Tick`). Every frame it holds the
founder's `JumpHeight` at 0 while Build mode or a panel is up, else `Tuning.JumpHeight` (the
phone's jump button hides with it), and sets the music's mood (`Audio.music`). It reports its blocks to the
camera (on PC the top strip, the menu bar and the card's place; on a phone Roblox's top bar and the menu bar).

### 10.4 Menus
`Menus` registers the panels (the villagers' "folk" went with them): "pals" (`EquipBest`, `OpenTree` and, when a Hatchery stands, `OpenHatch` at the top, the hint beside them in up to three lines (`UIKit.lines`); a row a driftling
`Pal_<id>`: portrait, name in its rarity's colour, its rarity, passive and its effects, mutations (`Mut_<id>` each),
where it lives and helps (`Where`); `Move_<id>` opens the hut picker (the same panel with `{ move = id }`: a row a hut
with its room, `Move_<uid>`, and the pen, `Move_0`; a full hut lists its driftlings with `SwapWith_<id>`, sending
`pal.house { id, uid, swap }`), `Help_<id>` the picker of the buildings of its knack (a driftling in a hut only),
`Sell_<id>` (two taps, its price)), "tree" (GAME_DESIGN 6, 380 x 196: on the left how fast it grows (`Pace`: "Grows
one every 7.0s", or at `PenSafe` "Resting. Sell some to grow more."), the rows `Upgrade_speed` and `Upgrade_luck`
(the level, what the next does, the price button at the row's right: the shells and the `mini_shell` icon,
`PriceIcon`, no wood), `Stage` (the Luck it grows bigger at next, or fully grown) and the odds of each rarity at the luck now (`Odds_<r>`); on the right the
pen as a list, the island's only picture of it (`PenCount` "Pen n", `EquipBest` sending `pen.best {}` (on with a hut and someone in the pen; its notice says how many moved in and back), `SellCommons` sending `pen.sell { r = 1 }`, a row a
driftling, the best `PEN_ROWS` (40) first, with `ToHut_<id>` (the hut picker) and `PenSell_<id>`, then `PenMore`: how
many more, from `penN`; `SellCommons` on while `penCommons` > 0)), "hatch" (a row a Hatchery `Hatch_<uid>`: its egg (`egg_<rarity>`, `EggName`, `EggLeft` ("Hatches in
3 turns"), `EggBar`, its parents) or the slots `Slot_a_<uid>` /
`Slot_b_<uid>` (the picker: the same panel with `{ hatch = uid, slot }`, a row `Parent_<id>`, `PickParent_<id>`), the
likely child (`Child`: its portrait if grown, else its shape and ???, its rarity), `Cost`, `Breed_<uid>`), "index"
(`Entry_<species>`: portrait or silhouette, name or "???", the kind of island it comes from, its blurb; "Grown n of 55
kinds") and "looks" (the founder's portrait, `Prev_<k>` / `Next_<k>` for skin, hair, style and shirt, `SaveLook`
sends `founder.set`). `Words.errText(err)` words every ErrCode (`fixed`: "The Tree of Life stays on your island. You
can move it."; `full`: "There's no room for more.").

### 10.6 `AvatarView`
A founder per player (`CharacterModels.buildStanding`, look from the player's `Founder` attribute, else one from the
UserId), registered with the renderer and posed every frame at their character: feet on the ground under the
HumanoidRootPart (a raycast down past characters and rigs) while the Humanoid stands (its `FloorMaterial`), in the air
(`FloorMaterial` Air) at the root's height less its rest offset (learnt while it stands), posed "jump"
(`CharacterModels.poseAction`), with a puff of dust on landing; facing the root's look direction, walking at the speed
the root moves. The own founder's feet are heard (Roblox's own character sounds are off: `RbxCharacterSounds`): a
step every `5.4 / speed` seconds (0.24 .. 0.5) while it moves faster than 4 studs a second, `step_wood` on a plank,
beam, edge or pier part (the boardwalk, the jetty, the pier), `step_sand` on ground under the lawn's height (the beach),
else `step_grass`; `jump` as it leaves the ground, `land` (on the boards a firmer `step_wood`) as it comes down. The Roblox avatar is hidden on every client (`LocalTransparencyModifier` 1 on its parts and decals).
Other players' names float over their heads (World root). `founderPos()`, `count()`, `lookOf(player)`,
`setOverride(fn?)` (a cutscene poses the own rig instead: `fn(rig, t, dt)` every frame; nil gives it back).

### 10.7 `BuildUI` (Build mode)
`open(tab?)` (the HUD's Build button; `tab`: the tray opens on that tab, the quests' Go): closes any panel, `CameraController.setFree(true)`, the tray `BuildTray` along the
bottom (a workbench in a frame of planks, `wood = 3`, its tabs on a `plank`; the cards carved boards): the tabs `Tab_food Tab_wood Tab_shop Tab_nest Tab_gen Tab_path Tab_decor` (Food .. Huts .. Decor; their icons
alone on a narrow screen), the count (`Count`: the pieces, or the path tiles on the Paths tab, against their limit), `Expand` (`island.expand`, its price under it; the fanfare and "Your island grew." wait for `PixelRenderer.afterBake`, 1.5 s at most) and `BuildDone`; a card a piece of the tab (`Buy_<id>`:
its price in shells and wood with their icons, red when short; a locked one says the island tier it needs). With a
piece picked (`pick(id, rot?)`), a ghost model (`Ghost` in `Workspace.PixelDynamic`: the piece and its `Footprint`, a
raised neon frame of four edges just above the grass, cyan (`screen_on`) where `Plot.fits`
says it fits, red (`berry_red`) where not) stands on the cell under the pointer (mouse) or the last tap; the bar shows
`Rotate`, `Place` / `Move here`, `Replace` (when another of its kind is open) and `Store` ("Clear away")
when moving a building, `Cancel`, and the `Info` plate (what it is and makes, a hut's room and comfort, its
charm, its price or the next level's). `Replace` turns the bar to `ReplaceBack`, `ReplaceWhat` and a card a
replacement (`Swap_<id>`: its name with its room, `SwapTo_<id>` with `Plot.replaceCost`), a tap sends
`plot.replace`. A tap on a placed piece of the own
island (a ray into its `Static.Decor`) picks it up; the Tree of Life moves like any piece, but its `Store` (Clear away)
and `Replace` are off. A press dragged more than 8 px pans the view
(`CameraController.panBy`). `confirm()` sends `plot.place` (the piece stays picked for another copy) or `plot.move`;
`close()`; `isOpen()`; `Changed: Signal<boolean>`; `tapScreen(pos, mouse?)` (the sims' and previews' tap). The tray
is laid out again when what can be afforded changes (`StateClient.Tick`). The tips (`TUT`: tip 1 food / patch, 2
wood / lumber, 3 shop / stall, 4 nest / hut): opening, and each new tip while open (`followTut`, from
the rebuild; it waits while a piece is picked), turns the tray to the tip's tab; the tip's card (`TutGoal`) and its
tab, while another is shown, pulse to the accent and shine; placing the tip's building drops the pick so the tray goes
on to the next tab. `TRAY_H` (the HUD lifts the tip's banner over it), `debugState() -> { tab, goal? }`.
**Drawing paths** (GAME_DESIGN 4): picking a path piece opens the draw bar (`Draw`: `DrawLine`, `DrawBox`,
`DrawErase`, `DrawLook`, `Cancel`, `BuildDone`, the `Stroke` label with the count and price) instead of the ghost.
A press starts a stroke (not in `DrawLook`, which pans), a drag adds cells (`strokeTo`: Line fills the gaps between
the cells it passes, Box every cell of the rectangle from the press; `DRAW_MOST` 240 a stroke), the mouse alone
previews one cell, the release sends it (`finishStroke`: `plot.paint` or `plot.unpaint` in batches of `PAINT_MAX`,
the refusals in words). `strokePlan(cells) -> (plan "lay" | "lift" | "no", n, cost)`; `showDrawGhost` lays a flat neon
plate a cell (`DrawGhost` in `Workspace.PixelDynamic`): cyan to lay, orange to lift, red where it can't.
`debugDraw(cells, mode, keep?) -> plan` (the sims' and previews' stroke).

### 10.8 and 10.9 (gone)
The walk in and home (`Voyage`) and the islet's screen (`ExpeditionUI`, `MicroStage`: the stages, the battles, the
skill window, the cards) went with the expeditions (GAME_DESIGN 7, 2026-11-12). Their text is in this file's history,
up to commit f667462.

### 10.10 Sprites (`PixelSprites`, `ArtData`)
`ArtData` (generated by `scripts/gen_art.py`; do not edit): `{ [name]: { w, h, px, pal, alpha } }`, one character a
pixel (`.` clear, else an index into `pal` 0xRRGGBB with its `alpha`). How `gen_art.py` shades (GAME_DESIGN 2):
`cel_tones` over the whole silhouette (the base; a 1 px shadow along the bottom and right edges, two under a
portrait's belly; a short light on the upper half of the top-left edges of masses 3 px thick), close hue-shifted
ramps (`RAMPS`, `M` the magmole's warm basalt, `E` cream), no grain, curves inside the outline softened a step toward the
shadow; the outline is never anti-aliased on its outside. The driftlings' portraits are not masks: `PORTRAITS`, read
from `scripts/portraits.txt` (GAME_DESIGN 2: each driftling's 3D model drawn by `Pixel/Snapshot` at 32 x 32, turned
30 degrees, pitch 15, in the preview scenario `pportraits`, its head 1.45 times bigger and its eyes 1.1 again, in its
body plan's style (`portraitPose` with `EYE_STYLE`: a size, an iris in the species' accent unless it is in `DULL` or
too near the body, then the plan's own colour, a black `Pupil<L|R>` part as a dot, slit or bar, a Neon glint or none,
a Neon glow for a sprite; a golem keeps its slits), then tidied by `tools/preview/gen_portraits.py`: binary alpha, the outline made again 1 px on
the four sides, lone spikes and notches, the bands' dither settled, creases 1 px and a shade of the colour beside
them, dark bodies lifted (not the eyes), a little more saturation, near tones merged, curves softened inside; `sh tools/preview/portraits.sh` runs the three and remakes `ArtData`).
The overlay's sprites also have a white `<name>_flash`; the icons have a dark `<name>_sil` (not met yet); an
animation's frames `<name>_1`, `<name>_2`... share one canvas (bottom centre). The sprites: the driftlings' portraits
`icon_<species>` (32x32: drawn from its model; `Menus` puts a row's words at `PX` 40, right of one), the small icons `mini_<name>` (11x11: `shell
food wood sun moon charm folk pal visitor home nest tree train decor start loot chest wild rest boss star boat`; `tree`
the Tree of Life's; `train`, `start`, `loot`, `chest`, `wild`, `rest`, `boss` and `boat` unused since the expeditions
went), the arrows `arrow_<dir>` (13x13) and `arrow_<dir>_t` (7x7), `note`, `heart`, `spark_1..3`, `bombfuse`. `PixelSprites`:
`has(name)`, `size(name) -> (w, h)`, `image(parent, name, pos?, z?) -> GuiObject` (an ImageLabel `Sprite_<name>`
showing the sprite's EditableImage, made once and shared, `ResampleMode` Pixelated, at the sprite's own size: no
scale; without EditableImages a Frame of 1 px run rects), `anim(parent, names, pos?, z?) -> Anim { f, w, h, set(i),
flash(seconds?), moveTo(x, y) }`.

## 11. Verification

- `bash scripts/check.sh`: Rojo sourcemap, luau-lsp strict analysis (0 errors), luau-compile, the specs (`tests/run.luau`
  lists them: Util, Validate, Numbers, DataIntegrity, Traits, Island, Tree, Breed, Economy, Plot, Quest, Schema,
  Shading, Raster, Rim, PixelFont), the Rojo build. Must end with `ALL CHECKS PASSED`.
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
