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
> be put into a pen. ..." (the expeditions' code is gone; the Tree of Life and its pen, `Logic/Tree`, went in turn on
> 2026-11-13, below)

> The request (2026-11-12, later): "remove villagers, only creatures should be enough" (no `Villager`, `folk`, homes,
> `folk.*` actions or Folk attribute; save version 11)

> The requests (2026-11-13, GAME_DESIGN quotes them with the talk before): "good idea, use the drifting in idea. you
> can remove the tree of life, there should now be a steady stream of driftlings, with rarities that players can pick
> up"; "also, make wood the main resource for building/expanding and shells the main resource of getting new
> driftlings. remove food as a resource" (`Logic/Tree` is now `Logic/Tide`: no tree piece, pen, levels, stages or
> Equip best; the tide is each session's `s.tide`, never saved, mirrored as `ClientView.tide` and the plot's `Tide`
> attribute, drawn by `Controllers/TideView`; the action `tide.take` instead of `pen.sell`, `pen.best` and
> `tree.upgrade`; no `food`, eating or hunger; every piece priced in wood, `TierCost` in wood, the Hatchery's feast in
> shells; save version 12)

> The request (2026-11-13, later, GAME_DESIGN 6): "make them float by just like a conveyer belt instead of drifting
> towards the island and stopping, with one every second" (`TideSecs` 1 and `TideLife` 16, no `TideMax` or
> `TideStart`; `TideRare` thins the rarer ones; the tide runs on the server's time and each `Drift` keeps `at` and
> `life`, so every client puts it at the same place along `Street.TIDE`; Fx "tide" patches the client's
> `ClientView.tide` in place (`StateClient.TideChanged`) and `PlotService.syncTide` the plot's `Tide` attribute, with
> no whole view a second; no `tideT` or `tideFrac`; `TierCost[4]` 150,000)

## 1. Layout and tooling

```
default.project.json   Rojo: Shared -> ReplicatedStorage, Server -> ServerScriptService, Client -> StarterPlayerScripts;
                       characters on (the founder walks and jumps on the islands: JumpHeight 7.2)
src/shared/            Types, Net, Config (Tuning, Monetization), Data (content), Logic (pure rules), Render (pure pixel
                       maths, copied), Models (procedural models), Locale (Lang: English only)
src/server/            Main.server.luau, Services/* (DataService, Session, Router, IslandService, PlotService)
src/client/            Main.client.luau, Controllers/* (StateClient, CameraController, WorldView, TideView,
                       AvatarView, StreetLife, Audio, DayLight), Pixel/* (PixelRenderer, BakeCast, PixelText, Snapshot, ImageMemory), UI/* (UIKit, Hud,
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
a level kept from an older save), `PlotSave` (`{ placed }`), `Pal` (a driftling: `{ id, sp, home (a hut's Piece uid;
0: no hut, as when its hut was cleared away or made smaller: it waits for room, `Tide.settle`), work (a Piece uid, 0
resting; only one in a hut works), muts? (its mutations, Data/Traits ids) }`; no `held` since the pen went), `Drift`
(one floating past on the tide, the session's and never saved: `{ id (the session's drift id, not a Pal id), sp,
muts, cost (shells: `Tide.cost` on this island), at (the tide's clock when it came in: the server's time,
`workspace:GetServerTimeNow`), life (the seconds it takes to float past, `Tide.life`) }`), `Settings` (`{ pixel, music? }`: music "on" | "off"),
`Stats` (`{ days, built, earned, taken (driftlings taken in off the tide; the ones the tree grew before version 12),
sold (driftlings sold), best (the rarest had), hatched }`), `Egg` (`{ uid (its Hatchery), a, b (the parents' ids),
sp, muts, left (turns) }`, one a Hatchery), `Profile` (the save, version 12: `shells` (what driftlings cost), `wood`
(what building costs), `day`, `tier`, `founder`, `pals`, `plot`, `seen` (species -> 1 seen on the tide, 2 had one:
the Index), `eggs`, `nextId` (driftlings and pieces share it), `tut` (1 .. 6, 0 done), `quest` (the questline's quest
on the go, Data/Quests; one past the last: all done), `stats`, `settings`, `createdAt`; no `food` or `tree`),
`ClientView` (the profile's fields plus `dayFrac`, `plot` (the plot index), `pieces`, `rates` (`{ wood, shells }` a
turn), `charm`, `nests` (the huts' room), `visitors`; `pals` is every driftling; `tide` the `Drift`s floating past,
the oldest (the furthest along) first, each with its cost on this island; `tideSecs` the seconds between two,
`Tide.secs`; no `tideT` since the conveyor (each `Drift`'s `at` and `life` say where it is), no `penN`, `penCommons`
or `tree`), `ErrCode` (with `no_hut`: no hut
built to take one in; `full`: no room in that hut, or every hut full for a `tide.take` with no swap; no `food` or
`fixed`), `Response`, and the utility types `Connection`, `Signal<T...>`, `Rng`, `PixelTier`. The file is the
reference for every field.

## 4. Config

- `Config/Tuning.luau`: persistence (`DataStoreName = "BSS_Profile_v1"`, never renamed), the island (`StartWood`
  (300: the tips' buildings and a little over), `StartShells` (60: the first driftlings), `TurnSeconds` (the island's
  pace), `DaySeconds` (the sea's day: hours), `IdleOutput` (a building's work with nobody at it), `PalWork` (a common
  driftling's), `RarityWork` (a driftling's work by its rarity), `HelpMax` (driftlings a building), `VisitorCharm`,
  `VisitorsMax`, `ShopVisitors`, `Refund`, `UpgradeMult` (a level from an older save; no upgrades since 2026-11-11),
  `TierCost` (the wood to grow to each tier: 0, 600, 9,000, 150,000, 320,000, 800,000), `ComfortLvl`, `BoostMax`; no
  `StartFood`, `EatPal` or `Hungry` since food went), the tide (GAME_DESIGN 6: `TideSecs` (1: seconds between two
  coming in), `TideLife` (16: the seconds one takes to float past the island), `TidePrice` (shells by rarity),
  `TideTier` (the price's multiplier by the island's tier), `TideRare` (1, 0.7, 0.3, 0.1, 0.06: each rarity's weight
  times this, thinning the rarer ones), `TideLuck` (the luck by the island's tier), `TideMutTier`
  (tiers for a mutation roll one rarity up), `HutTide`, `HutLuck` (the huts' arrival and luck shares at most),
  `SellPrice` (by rarity), `SellTier` (a mutation tier's share on a price); no `TideMax` or `TideStart` since the
  conveyor; the tree's `TreeSecs`, `TreeLuck`,
  `TreeMutLuck`, `TreeSpeedCost`, `TreeLuckCost`, `PenSafe`, `PenShown`, `TreeStages` and `HutTree` are gone),
  breeding (`BreedShells` (the feast by the child's rarity), `BreedTurns`, `BreedKeep`, `BreedTierUp`, `BreedNew`), the
  server's step and rate limit, the sea (`MaxPlots`, `PlotSpacing`, `PlotPieces`, `PathPieces`, `HomeCooldown`,
  `WalkSpeed`, `JumpHeight`), and the camera and pixel filter values (Random Bakery's `CamYaw` 45, `CamPitch` 30,
  `PixelTiers`, `PixelScaleMin` / `PixelScaleSides`; this game's `CamRayBack`, `PixelMaxRayDist`, `CamFollowBox`,
  `CamGlide`, `CamBuildPan`, `PixelPanRays`, `PixelInvalidateRaysFrame`, `PixelMaxDyn`).
- `Config/Monetization.luau`: `GamePasses`, `DevProducts`, `Badges` (empty or 0), `Sounds` (the Creator Store
  library ids `Controllers/Audio` plays: Roblox's free licensed ProSoundEffects clips and APM Music stingers, none of
  Random Bakery's, each named in a comment) and `Music` (`{ day, night }`: lists of `{ id, gain }`, APM Music
  tracks, each named; `gain` evens their loudness out).

## 5. Data (pure content tables)

| Module | Holds |
|---|---|
| `Data/Palette` | the LUT colours (`order`, `colors`), the shore's `shallow`, `foam`, `rock` and `rock_dark`, the older rooms' floor and wall themes (`themes`, still in the LUT), the light modes, and the UI's colours (`ui`, `axis`, `match`) |
| `Data/Buildings` | the 65 pieces (GAME_DESIGN 4) `{ id, name, kind (farm wood shop nest breed gen path decor), shells (0 for every piece since 2026-11-13, kept for a price in both), wood (the price: the old shells and wood added up), w, d, rate (a turn with one common driftling at it: wood for kind wood, shells for farm and shop), knack, slots (a hut's room), charm (a path's may be a fraction), comfort (a hut's share), boost ("farm" "fish" "wood" "shop" "all": a "gen" piece's knack), boostBy, tier (1 .. 6), blurb }`; kind "farm" (the old "food": it sells what it grows or catches for shells), "nest" the huts (Driftling Hut .. Driftling Palace); no `eats` and no "tree" piece since the tide; `list`, `byId` |
| `Data/Creatures` | the 55 driftlings (GAME_DESIGN 6) `{ id, name, islet (its kind, Data/Islets), rarity (1 common .. 5 legendary), hp, atk, def, spd (kept only for `power`), knack, shape (its MicroModels body plan), body, accent, blurb, passive ({ name, fx }: its own, Data/Traits effects), power (its stats weighted, +12% a rarity step: the breeding rank) }`; `list`, `byId` |
| `Data/Traits` | what makes one driftling unlike another (GAME_DESIGN 6): `MAX` (4 mutations), `KEYS` (the effects: work farm fish wood shop (shares at work), cost (its own price off the tide: below 0 cheaper), sell (the price), charm (whole points), tide, luck (more arrivals and a luckier tide, from a driftling in a hut); 0.1 = +10%; `cost` and `tide` were `eat` and `tree` before the tide), `RARITY` (`{ name, color, weight }` x 5: the tide's weights before luck, 100 45 16 5 1.2), `TIER_COLOR`, `TIER_STARS`, `list`, `byId` (mutations `{ id ("sturdy3"), family, tier (1 .. 4; 0 a flaw), name, blurb, fx }`: ten families x four tiers and five flaws; the families keep their old ids, "sturdy" now Thrifty .. Selfless (cost) and "swift" Breezy .. Moonpull (tide), so older saves read them), `families`, `at(family, tier)`, `roll(rng, rarity) -> { id }` (0 .. 3, no family twice, a rarer one rolls fewer flaws and higher tiers), `sum(passive?, muts?) -> Fx`, `workAt(fx, knack)` (work + the knack's share, at least -0.5), `clean(muts)` (known ids, a family once, at most MAX), `describe(fx)` ("+24% at farms, costs 30% less, +2 charm, +4% arrivals", "+5% tide luck") |
| `Data/Quests` | the questline (GAME_DESIGN 9) `{ id, title, text (what to do and where), goal { kind, n, of? }, reward { shells?, wood? }, go (its Go: a panel "pals" "index" "hatch" "tide", or "build" / "build:<tab>"), icon (a `mini_` sprite) }`, twenty in order; `list`, `byId`. Goal kinds: helpers (driftlings at work) housed (in huts) built (of a building kind) paths decor taken (off the tide) sold best (the rarest had) tier seen hatched; the tree's `luck`, `speed` and `grown` are gone |
| `Data/Islets` | the 9 kinds of land the driftlings come from (GAME_DESIGN 6) `{ id, name ("Beach"), plural, tier (the island tier its driftlings start coming on the tide at: Beach, Meadow 1; Snowfield, Mangrove 2; Volcano, Grotto 3; Reef 4; Bluffs 5; Ruins 6), wild (every driftling of its kind, from Data/Creatures, the commonest first), color, blurb }`; `list` |
| `Data/Looks` | skin, hair, hair style and shirt lists (`Types.Look` indexes them: the founders and the visitors; `Data/Names`, the villagers' names, went with them) |
| `Data/Office` | the island's six tiers (`plans[tier]`: `{ tier, name }`, Castaway Cay, Palm Isle, Grand Isle, Harbor Town, Coral City, Sunspire Capital: the island card's title), `plan(tier)`, `origin(plot)` (Data/Street's). The island has no house (GAME_DESIGN 8) |
| `Data/Street` | the islands and the sea (GAME_DESIGN 8): `warm(tier)` (works a tier's cells out now: tens of ms at the top tiers, so never at an expansion), `MAX`, `SPACING`; the heights `LAWN_Y` (-0.5: the grass), `SAND_Y`, `WET_Y`, `FOAM_Y`, `SHALLOW_Y`, `WATER_Y` (each band a little lower than the one inside it); the cell layers `GRASS SAND WET FOAM SHALLOW SEA_CELL` and how far past the coast each reaches, `BANDS` (`sand` 2.5, `wet` 3.5, `foam` 4.5, `shallow` 8 studs); `BOARD` / `SEA` (plot-local z bands), `FAR` / `END_FAR` (water past the invisible walls: no sky at the world's edges), `LOT` (a plot's lot: x +-40, z -64 .. 30, room north for the city tiers), `CENTER`, `PLAZA` (the campfire's plaza), `PATH` (the path to the jetty), `TIDE` (the tide's lane: plot-local `z` 26 between the foam and the boardwalk, from `x0` -40 to `x1` 40, west to east, the length of the lot; `clear` 2.5: no shallow rocks within that of `z`); the coast: `isle(tier)` (its oval: centre, radii, wobble phases), `coast(tier, x, z)` (studs from the coast, below 0 inland: the oval's radius times a wobble of four sines, joined
to every smaller tier's shape (the least distance) so an island only gains land as it grows), `layerAt(d)`, and per whole-stud cell (cached per tier; `cellKey`) `layer`, `cellDist`, `cellBounds(tier)`, `buildable(tier, x, z)` (grass a stud or more inside the coast), `walkable` (grass, sand, wet sand), `plot(tier)` (the grass's bounding box); `origin(i)` (plots centred on x = 0), `plotAt(x, z)`, `bounds()`, `footpath()`, `jetty(tier)` (planks from the island's sand to the boardwalk), `spawn()` (on the path below the plaza), `sign()` / `mailbox()` (either side of the jetty's foot), `LAMPS`, `PIER_X` / `PIER_Z` / `PIER_W`, `pier()` |

Coordinates in `Data/Street` are studs, plot-local, +Y up. The camera looks from the south-east (+X, +Z), so an
island's back is its north-west. A piece's `rot` turns its model (built facing +Z: south, toward the viewer).

## 6. Logic and models

Pure rules (`src/shared/Logic`), all specced in `tests/specs`; every action returns `(true, data?)` or `(false,
ErrCode)` and changes the profile only on success:

| Module | API |
|---|---|
| `Util` | copied from Random Bakery: `hash32`, `newRng(seed)` (xorshift32: `next int range chance weighted`), `pick`, `shuffle`, `Signal`, `round clamp lerp isFinite sig2 deepCopy count` |
| `Island` | the turn and the day (GAME_DESIGN 3): `piece(p, uid)`, `nests` (the huts' room), `fxOf(pal) -> Fx` (its passive and mutations, `Traits.sum`), `charm` (every piece's, and each driftling in a hut: 1 + its charm share), `visitors`, `works(id)` (a building that makes something: kind farm, wood or shop), `homes(p) -> { [key]: { uid, comfort } }` (each hut driftling's hut and its comfort (the hut's plus `ComfortLvl` by level), "p<id>", none for one with no hut), `boosts(p) -> { farm fish wood shop all }` (each kind of boost building once), `boostAt(b, knack)` (its own and "all", `BoostMax` at most), `palWork(p, pal) -> number` (its work share at its building's knack, `Traits.workAt`), `palBoost(p, pal, comfort?)` (`PalWork` x `RarityWork[rarity]` x max(0, 1 + `palWork` + the hut's comfort): what a driftling puts in), `rates(p) -> Rates` (`{ wood, shells }` a turn; a building makes its rate times its driftlings' `palBoost` summed (`IdleOutput` with nobody), times 1 + `boostAt`, times `UpgradeMult` by level: a wood building wood, a farm shells, a shop shells times min(2, visitors / `ShopVisitors`); nothing eats), `step(p, dt) -> Rates` (the stores; the shells counted in `stats.earned`), `randomLook(rng)` (a visitor's), `freeJob(p, knack) -> uid` (the emptiest building of that knack with fewer than `HelpMax` driftlings, farms first, then wood, then shops; 0 none), `newDay(p)`, `setHelp` (only a driftling in a hut, at a building of its knack: `HelpMax` a building, the first there sent back to rest; bad_payload for one with no hut), `expandCost(tier) -> { shells = 0, wood }?` (`TierCost`, nil at the top), `expand(p)` (max, wood; data `{ tier, moved, cleared }`: `Plot.refit`), `setFounder` |
| `Plot` | building (GAME_DESIGN 4): `ROTS`, `limit(tier)`, `footprint(id, rot)`, `rect`, `blockers(tier)` (the campfire's plaza and the path to the jetty), `fits(tier, placed, id, x, z, rot, skip?) -> (ok, "outside" (a footprint cell not `Street.buildable`) / "blocked" / "overlap" / "unknown")`, `spot(tier, placed, id, x, z, rot) -> (x?, z?, rot?)` (the free spot nearest x, z: `refit` moves with it), `unhouse(p, uid, keep?)` (a hut's driftlings past its first `keep` left with no hut, resting; `Tide.settle` moves them in again; was `toPen`), `pathLimit(tier)` (`PathPieces`), `isPath(id)`, `used(p, id) -> (n, limit)` (the pieces of its count: paths, or the rest), `place` (bad_payload (an unknown piece, a home of the old saves), locked, full (by its count), money (a price in shells: none has one now), wood, blocked), `move` (blocked for the spot; no upgrades: taken out 2026-11-11; a level from an older save stays and counts), `replaceCost(q, id)` (the new price less `Refund` of the old, never below nothing), `replacements(q, tier)` (the others of its kind open at the tier), `replace(p, i, id)` (bad_payload (another kind, the same piece), locked, money, wood, blocked (the new footprint where the old stands); a smaller hut keeps the driftlings it has room for, the rest left with no hut; the uid kept, the level 1, driftlings of another knack back to rest), `store` (egg; `Refund` back; a hut's driftlings left with no hut), `refit(p) -> (moved, cleared)` (pieces that do not fit move to the nearest free spot, or are cleared with their whole price back: after the island grew and when a save loads); drawn paths (GAME_DESIGN 4: Build mode's draw bar): `PATH_STEP` (2: a path tile's cell, even studs), `PAINT_MAX` (40 cells a request), `cells(s) -> { {x, z} }` and `cellString(cells)` (the payload's "x,z;x,z"), `paint(p, id, cells) -> (ok, { placed, skipped })` (a path piece only; each free cell gets a tile at rotation 0, a cell that doesn't fit is skipped; locked, full, money, wood or blocked (none laid)), `unpaint(p, cells) -> (ok, { removed })` (every path tile covering a cell comes up with `Refund` back; not_found); no `isFixed` since the tree went |
| `Tide` | the tide and the huts (GAME_DESIGN 6; `Logic/Tree` until 2026-11-13): `hutFx(p) -> (tide, luck)` (the huts' driftlings' shares, at most `HutTide` / `HutLuck`), `secs(p)` (`TideSecs` / (1 + the tide share): seconds between two), `life(p)` (`TideLife` x `secs(p)` / `TideSecs`: seconds one takes to float past, faster with the same share, so they stay as far apart), `luck(p, tier?)` (1 + `TideLuck[tier]` + the luck share), `pool(tier) -> { { sp } }` (by rarity, the kinds open at the tier), `odds(p, tier?) -> { share }` (each rarity's weight x `TideRare[r]` x luck^(r - 1), a rarity the pool lacks given to the next commoner one), `worth(pal)` (`RarityWork` x (1 + its share at its knack): the lists' order and the weakest in a swap, kept per driftling table in a weak table, its kind and mutations never changing), `better(a, b)` (the better worker first, then the older), `price(pal)` (what it sells for: `SellPrice` x (1 + `SellTier` x its mutation tiers) x max(0.2, 1 + its sell share), whole shells, at least 1), `cost(p, sp, muts?)` (what one off the tide costs: `TidePrice` x (1 + `SellTier` x its mutation tiers) x max(0.2, 1 + its cost share) x `TideTier[tier]`, whole shells, at least 1), `huts(p) -> { Hut }` (`{ uid, room, comfort, n }`, the comfiest first, then the first built), `room(p)` (the huts' free places), `settle(p) -> { id }` (the driftlings with no hut, the best first, into the huts with room, the comfiest first, each taking a free job of its knack: who moved), `fillJobs(p)` (resting hut driftlings to free jobs), `add(p, sp, muts) -> Pal` (a hatchling: the comfiest hut with room, or none; a free job; `seen` 2, `stats.best`), `State` (`{ clock, t, list: { Drift }, next }`: a session's tide; `clock` the tide's clock (the server's time on the server), `t` the seconds since the last one came in, `list` the ones floating past, the oldest (the furthest along) first), `new(clock?) -> State` (`clock` 0 when not given: the specs), `roll(p, rng, rarity?, knack?) -> (sp, muts)` (a rarity by `odds` or the one asked, a kind of it (of `knack` when asked and the rarity has one), `Traits.roll` at the rarity + (tier - 1) // `TideMutTier`), `drift(p, s, rng, at, rarity?, knack?) -> Drift` (one comes in at the tide's clock `at` with `life(p)`, `seen` at least 1; with no rarity or knack asked, while the island has taken nothing in and has no driftling, every third one (`s.next % 3 == 1`) is a common with the knack "wood" or "farm" by turns), `start(p, s, rng)` (the belt full: floor(`life` / `secs`) drifts `secs` apart, the newest at `clock`), `step(p, s, dt, rng) -> (came, gone)` (`clock` + dt; one every `secs`, its `at` the exact moment; each one with `clock - at >= life` leaves, its id in `gone`), `along(d, now) -> number` (0 just come in .. 1 gone past), `entry(p, d) -> Drift` (the client's copy, its cost on this island now), `view(p, s) -> { Drift }` (every `entry`), `take(p, s, id, swap)` (not_found (it floated off), no_hut (no hut built), money, full (every hut full and swap 0), bad_payload (a swap that isn't in a hut); the shells paid; a swapped one sold (`price`, `stats.sold`, `stats.earned`) and its hut taken, else the comfiest with room; a free job; `seen` 2, `stats.taken`, `stats.best`; data `{ id, sp, cost, sold, swapped }`), `sell(p, id)` (not_found; its price, `stats.sold`, `stats.earned`, then `settle` and `fillJobs`; data `{ shells, sold }`), `house(p, id, uid, swap)` (to another hut, a job of its knack if one is free; a full hut only in a swap with `swap` (one living there), which goes where this one was; not_found, bad_payload (not a hut, a swap not living there), full; then `settle` and `fillJobs`; data `{ moved }`). Gone with the tree: `ID`, `SPOT`, `inPen`, `resting`, `penView`, `stage`, `nextStage`, `upgradeCost`, `upgrade`, `sellPen`, `equipBest`, `piece`, `plant` |
| `Breed` | the Hatchery (GAME_DESIGN 6.1): `child(a, b) -> sp` (a pair of one kind its kind, else the kind (no legend unless both are) of power nearest their average; the commoner, then the first id, on a tie), `cost(sp) -> (shells, turns)` (`BreedShells`, `BreedTurns` by its rarity), `inherit(ma, mb, rng) -> muts` (shared: always, the better tier, `BreedTierUp` one better; one parent's: `BreedKeep`; `BreedNew` a tier 1 or 2 of a new family; the best four), `eggAt(p, uid)`, `start(p, uid, a, b, rng)` (not_found, egg, bad_payload, money; the feast paid in shells, `p.eggs` + 1), `turn(p) -> { Pal }` (each egg a turn nearer; a ready one hatches into a hut with room, or none (`Tide.add`), `stats.hatched`) |
| `Quest` | the questline's rules (GAME_DESIGN 9): `Facts` (`{ pals, pieces, tier, seen, stats }`: a profile's, `facts(p)`, or the client view's, same names), `count(facts, goal)` (how far: driftlings at work (`helpers`), path tiles, decor, pieces of a kind, driftlings in huts (`housed`), the stats' counts (`taken`, `sold`, `hatched`), the rarest had (`best`), the tier, kinds in the Index), `current(tut, i) -> (Quest?, i)` (none while the tips are on, or past the last), `progress(facts, q) -> (have, need)`, `done(facts, q)`, `claim(p)` (not_found, not_done; the reward paid in shells and wood, `p.quest` + 1; data `{ id, shells, wood, next }`) |
| `Schema` | `VERSION` (12: the tide), `default(now, seed)` (`StartShells`, `StartWood`, no driftling and no piece), `migrate(raw)` (1 -> 2: a founder; 2..4 -> 5: the studio gone, the founder, settings and start kept; 5 -> 6: the tips' steps moved (3 -> 5, 4 -> 6); 6 -> 7: each driftling rolls its mutations once, seeded by its kind and id; 7 -> 8: the questline; 8 -> 9: `boat` and `chart` gone; 9 -> 10: `cap`, `islets`, `sea`, `wilds` and `pouch` gone, a Training Yard refunded (450 shells, 50 wood), the driftlings put in the nests (now huts) in the old order (the comfiest first, in the order they came), the rest to the pen (sold at 11 -> 12), `tut` past 5 back to 5, `quest` 1, `stats.grown` from the old `befriended`, `stats.best` the rarest kept; 10 -> 11: `folk` gone, every home (Tent .. Manor) taken down with its whole price back, `tut` past 4 back one, `stats.movedIn` gone; 11 -> 12: `tree` and `food` gone, the tree's piece taken off the plot, every driftling with no hut (the pen's) sold for `Tide.price` (shells, `stats.sold`, `stats.earned`), `held` dropped, `stats.grown` renamed `stats.taken`; the tips keep their numbers), `reconcile(raw, now, seed)` (any table -> a valid Profile: pieces that exist with unique uids and valid turns, driftlings with unique ids (at most `MAX_PALS`, 5000) (a driftling's `home` a standing hut with room or 0, `work` only from a hut at a building of its knack, `muts` through `Traits.clean`), the Index's species, `nextId` past every id, `tut` 0 .. 6; then `Plot.refit` and `Tide.settle`) |
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
  by the plot's own seed (no rocks in the shallows within `Street.TIDE.clear` of the tide's lane: one rolled there is
  built and thrown away, so the rest of the coast keeps its seed's layout); `Blocks.windy`), `emptyLot(parent, origin)` (open water and a sandbar), `ends(parent)` (the sea past the
  ends, sandbars, the boardwalk's last lantern, the invisible walls along each end's own stretch of boardwalk, and
  the walls round the world, 40 studs high (past any jump); the pier's things, `PierProps`: bollards, crates, a barrel, rope, and the
  moored `Boat` don't collide). Every wall is
  in the collision group `Bounds`, which the pixel filter's rays (group `PixelRays`) pass through.
- `DecorModels.build(id, at, lvl?) -> Model` (every building and piece of decor; `at`: the footprint's centre on the
  grass, turned; each with its doors, windows, ridged roofs with eaves and its own props (crates, barrels, sacks, pots,
  fences, lamps); a lamp and a pennant (`PennantPole`) at Lv 3; the pier's pond and the fountain's water `PixelWater`
  2; parts don't collide; `Blocks.windy`), `has`. The homes (Tent .. Manor) went with the villagers, and the Tree of
  Life (`tree`, its stages and `DecorModels.HOLLOW`) with the tide on 2026-11-13.
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
  (`Wing*` flap, `Tail*` wag, `Eye*` blink...; `flap(t, cf, phase, glide?)`). WorldView, TideView and StreetLife call
  it every frame.
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
changed), `Fx` (RemoteEvent, S->C `{ kind = "tick", shells, wood, dayFrac, tideSecs (`Tide.secs`) }` every second (no
`tideT` since the conveyor), `{ kind = "tide", came (the Drifts that came in, each `Tide.entry`: its cost on this
island, `at`, `life`), gone (the ids of the ones gone past) }` every time one comes in or goes (about one a second;
no whole view is sent for it, the client patches its own), `{ kind = "taken", data }` (`tide.take`'s data) when one is taken in, `{ kind =
"turn", hatched? (the Pals hatched: Breed.turn) }` at each turn's end, `{ kind = "day", day }` at each of the sea's
days, `{ kind = "quest", data }` on a claim; no "tree" or "treegrew" since the tide). `Net.serverInit()` creates them;
`Net.clientInit()` waits for them.

### 7.2 `Session`
`create(player, profile, plot) -> S` (`{ player, profile, plot, rng, ready, turnClock, dayIndex, tickClock, tide
(`Tide.State`: the session's tide, never saved, `Tide.new(workspace:GetServerTimeNow())`; `Tide.start` fills the belt),
dirty, tideDirty (the tide changed and the plot's `Tide` attribute is behind: Main calls `PlotService.syncTide`; true
at create), saveAt, reqTimes }`), `get`, `remove`, `all`, `view(s) -> ClientView` (every driftling, `tide` from
`Tide.view`, `tideSecs`; no `tideT`),
`markDirty`, `flush` (sends State when dirty), `fx(s, msg)`, `allow(s, now)` (the rate limit).

### 7.3 `Router` and the action catalogue
`Router.on(action, fn(s, payload) -> (ok, data|err))`, `Router.onSignal(kind, fn)`, `Router.handle(player, action,
payload) -> Response` (not ready -> `not_ready`; over `Tuning.RateLimitPerSec` -> `rate`; `Validate.request`; the
handler under pcall; success marks the session dirty).

| Action | Payload | Rule | Errors |
|---|---|---|---|
| `plot.place` | `id x z rot` (coords whole studs in [-64, 64], rot a quarter turn) | `Plot.place` (paid in wood), the buildings rebuilt by difference, then `Tide.settle` and `Tide.fillJobs`, the tips | locked, full, wood, blocked, bad_payload |
| `plot.move` | `i x z rot` | `Plot.move` | blocked, bad_payload |
| `plot.paint` | `id cells` ("x,z;x,z": 1 .. 40 cells, whole studs in [-64, 64]) | `Plot.paint` (data `{ placed, skipped }`), the buildings rebuilt | locked, full, wood, blocked |
| `plot.unpaint` | `cells` | `Plot.unpaint` (data `{ removed }`), the buildings rebuilt | not_found |
| `plot.replace` | `i`, `id` | `Plot.replace` (data `{ i, uid, id }`; the island's pieces rebuilt) | bad_payload, locked, wood, blocked |
| `plot.store` | `i` | `Plot.store` (clear away; a hut's driftlings left with no hut, then into any hut with room) | egg (a Hatchery holding an egg), bad_payload |
| `breed.start` | `uid`, `a`, `b` | `Breed.start` (an egg at the Hatchery `uid` from driftlings `a` and `b`; the feast in shells) | not_found, egg, money, bad_payload |
| `island.expand` | - | `Island.expand` (paid in wood), the island rebuilt (data `{ tier, moved, cleared }`) | max, wood |
| `pal.work` | `id uid` (0: rest) | `Island.setHelp` | not_found, bad_payload |
| `pal.house` | `id uid swap` (swap 0: none) | `Tide.house` | not_found, bad_payload, full |
| `pal.sell` | `id` | `Tide.sell` (data `{ shells, sold }`) | not_found |
| `tide.take` | `id swap` (a drift id on the session's tide; swap 0: none, else a hut driftling sold to make room) | `Tide.take`, the tips, Fx taken (data `{ id, sp, cost, sold, swapped }`) | not_found (it floated off), no_hut, money, full (every hut full and no swap: the client opens the swap picker), bad_payload |
| `founder.set` | `skin hair style shirt` | `Island.setFounder` (the `Founder` attribute follows on the next sync) | bad_payload |
| `settings.set` | `k` ("pixel" or "music"), `v` | the pixel tier (high, medium, low, off) or the music (on, off) | bad_payload |
| `tut.next` | - | the tips go away for good | - |
| `quest.claim` | - | `Quest.claim` (data `{ id, shells, wood, next }`) | not_found, not_done |
| `char.home` | - | PlotService puts the founder on their path | cooldown (`Tuning.HomeCooldown`), not_ready |

The building actions and `island.expand` still check shells (`money`) for a price in shells, which no piece or tier
has now. The expedition actions (`exp.*`, `pouch.upgrade`) and `pal.release` are gone (2026-11-12), the villagers'
`folk.work` and `folk.dismiss` with them later that day, and the tree's `pen.sell`, `pen.best` and `tree.upgrade` on
2026-11-13: `Validate` answers them `unknown_action`.

### 7.4 `IslandService`
Registers the actions above. `step(dt)` (Main's fixed 10 Hz step), for every ready session: `Island.step` (wood and
shells), `Tide.step` on the session's tide, run on the server's time (dt = `workspace:GetServerTimeNow()` less the tide's
`clock`; a stall over 5 s is skipped, not caught up), then Fx "tide" with what came and went (`Tide.entry` each) and
`s.tideDirty` set (the session is not marked dirty for it: no whole view a second), a turn every `TurnSeconds` (`Breed.turn`: Fx "turn"), a day each time the sea's clock passes a day's end (`WorldClock.dayIndex`
past the session's `dayIndex`: `Island.newDay`, Fx "day"), the stores every second (Fx "tick" with
`WorldClock.dayFrac` and `tideSecs`: the whole view is not sent for them). `WorldClock` (server): the
sea's clock, `os.time()` at start advanced by every step (`now`, `advance`, `shift(seconds)` for the sims and
previews, `dayIndex`, `dayFrac`); a day is `Tuning.DaySeconds` (4 hours). The tips (`tips(s)`, `TIP_KIND`): 1 moves on
when a wood building stands, 2 a farm, 3 a hut, 4 when a driftling has been had (`stats.taken` above 0 or any
driftling), 5 a shop, 6 on OK (`tut.next`); a step whose task is already done moves on at once, several in a row if
need be (a save from before the tide). Every building change (`rebuilt`) runs `Tide.settle` and `Tide.fillJobs`
before the island's models are rebuilt; `tide.take` runs the tips and sends Fx "taken". Nothing happens while the
player is away.

### 7.5 `PlotService` (the sea)
`init()` registers the collision groups `Bounds` (the invisible walls) and `PixelRays` (the pixel filter's rays),
not colliding with each other, and builds the whole sea: `Workspace.Plots.Street` (every plot's boardwalk stretch,
`Road_<i>` with its pier's `Boat`, always level 1 scenery since the boat upgrades went, and the sea's ends) and open
water on every plot (`Plot_<i>.Static.Land` = `EmptyLot`, attribute `Owner` 0). `claim(player) -> plot` (the lowest
free index, 0 when the sea is full: Main kicks), `release(i)` (back to open water, every attribute cleared).
`build(s)`: `Plot_<i>` gets `Owner`, `OwnerName`, `StudioName` ("Name's Isle"); its `Static` gets
`Land` for the island's tier (rebuilt only when `Static`'s `Built` attribute differs: the island for that tier built
ahead is swapped in when it is ready, else it is built there and then) and `Decor` by difference
(`buildDecor(s)`: one model a piece, named `uid:id:x:z:rot:lvl`; models whose key is unchanged stay), then `sync(s)`:
the attributes `Tier`, `Day`, `Charm`, `Pals` (the hut driftlings, `;`-separated `id.species.work.home`; one with no
hut is left out until it moves in; no `Folk` since the villagers went), `Tide` (by `syncTide(s)`, which `sync` calls too: the session's
tide, `;`-separated `id.species.at.life` with `at` (the tide's clock when it came in, the server's time) and `life`
(the seconds it takes to float past) in tenths of a second as whole numbers, the oldest first, set only when it
changed, `s.tideDirty` cleared: every client draws each island's at the same place along the way,
`Controllers/TideView`), and the player's `Founder` (`skin.hair.style.shirt`) and `Plot` (Main syncs every dirty
session before sending its view, and a session whose only change is its tide (`tideDirty`) gets `syncTide` alone;
only changed values replicate). The founder: `watchCharacters(player)`,
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
from the card's one Heartbeat: stills (a tall palm, `palm_b`, at the back in the middle, or at the back on the left when
its fronds, `BACK_TOP` art px over its foot, would reach the bar; the Tree of Life stood there until 2026-11-13); the
fire, the boat (drifting right, wrapping), the cheering Conchy (a burst, a rest), walkers (driftlings up and down a lane, a pause at each end, the
sequence's name left and `<name>_r` right),
followers (a driftling `gap` px behind its walker), gulls, stars, crests and glints (a run, hidden, a new spot: open
sea at least 26 ground px past `shoreR`, or the sun's path as wide as its lines at that row), embers.
The words: `textImage` rasterises a line with `PixelFont.mask`
(the title in `BIG` with the "title" under layer and `PixelFont.smooth`'s anti-aliasing steps, the status and the tip
in `SMALL` with a drop shadow) into an EditableImage, centred on the canvas; the status's dots and the bar are Frames.
Without EditableImages (`fallback`): Frames and an Arcade TextLabel. `LoadingArt` (generated: `W`, `H`, `palette`,
`seqs[name] = { w, h, ax, ay, dur, at, pal, px, base?, head?, flame? }`): `frond`, `frond_r`, `pebble`, `pebble_r`,
`crab`, `crab_r`, `bun`, `bun_r`, `gullfin`, `gullfin_r`, `cheer` (a Conchy), `fire`, `palm`, `palm_b`, `nest`,
`burrow`, `torch`, `flowers`, `bush`, `boat` (no `tree` since the tide), and the hand-made `gull`, `star`, `crest`, `ember`, `glint`.

### 8.1 `StateClient`
`init`, `view() -> ClientView?`, `waitView`, `Changed: Signal<ClientView>`, `Fx: Signal<msg>`, `Tick:
Signal<ClientView>` (Fx "tick": the view's `shells`, `wood`, `dayFrac` and `tideSecs` are patched in place, no whole
view comes), `TideChanged: Signal<ClientView>` (Fx "tide": the view's `tide` patched in place, the `gone` ids dropped
and the `came` ones added after a check of each field (numbers, not NaN), none twice; fired after the patch),
`tideNow() -> number` (the tide's clock: `workspace:GetServerTimeNow()`, the same on every client), `along(d) ->
number` (how far along one is now, 0 just come in .. 1 gone past), `request(action, payload) -> Response` (never
errors), `signal(kind, payload)`. (`tideFrac` went with the conveyor, `treeFrac` with the tree.)

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
(`DoorChime`; nothing plays it since the villagers went), `grow` (the island grows, or an epic or legendary driftling comes in on the tide: `BellTreeRun`), `friend`
(an egg hatched: `ChimeCluster`), `level_up` (a piece replaced: `SparkleTones`), `reward` (a quest claimed:
`Triangle`), `egg` (`MusicBoxWind`), `rare` (one rare or better taken in: `SparklePass`; a rare one coming in has no sound since the conveyor); the founder's feet (AvatarView):
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
contact shade at the foot of upright faces. The **dynamic layer** is the islanders (the hut driftlings, the tide's driftlings on their rafts and the visitors) and the founders: every tick (the tier's Hz) their parts
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

### 10.2 `WorldView` and `TideView`
The islanders: a walker per hut driftling (`MicroModels.driftling` in its species' shape and colours), parsed from
each owned plot's `Pals` attribute and placed among the buildings read from its `Static.Decor` models' names
(`uid:id:x:z:rot:lvl`). A driftling goes to the building it works at (or its hut) and works there by its kind
(`palMoodOf`: `dip` at a pier or kelp farm, `peck` at the other farms, `push` at the wood and the boosts, `wave` at the
shops, `nap` at a hut or the hatchery, for longer: `DriftModels.animate`'s work moods), now and then a stroll
(`strollPoint`: a buildable cell away from the campfire). One new in a hut on an island already peopled was just
taken in off the tide (or hatched): it comes ashore at the jetty (`TideView.ashore`) with a cheer and walks off to
work (`born`). Workers stand along the building's front, turned three-quarters to the view (east or south). Only
islands within 100 studs of the view's centre are drawn (synced every half second); each near owned island's
campfire gets a flickering flame and rising smoke (`fireOn`, dynamic models). Each island's sign gets a World-root
label (its name, the own in gold, or "Unclaimed isle"); a tap (`onTap`: a press let go within 8 px, not on the
interface, not in Build mode) goes to `TideView.tapAt` first (one of the own island's driftlings floating by: taken
in); otherwise its ray (`PixelRenderer.screenRay` in the `PixelRays` collision group, as the picture's, so it passes
the invisible coast walls, which Roblox hits whatever their CanQuery says because they collide) on a sign shows
`signCard(i)` (the day, driftlings at home, charm). Fx "taken" (`takenOne`) bursts bits of the newcomer's rarity's
colour at the jetty, a rare or better one's name floating up; a hatchling (Fx "turn" `hatched`) gets its name and
pink bits over the Hatchery; `cheer(words, color)` makes the own islanders cheer. Its Heartbeat runs `TideView.step`
with the view's centre (world x). `rigCount()` / `ownRigCount()` / `ownCount()` (the walkers drawn: all, the own
island's) and `tapScreen(pos)` (a tap at screen px, handled as a player's) for the sims. (The tree's tap `treeOf`, its
label `updateTreeLabel`, `hollowPoint` and `grownOne` went with the tree.)
`TideView` (client, GAME_DESIGN 6): every island's tide from its plot's `Tide` attribute (`id.species.at.life`,
tenths of a second on the server's time; the islands within `NEAR` (100) studs of the view's centre, synced every half
second). Each one rides the lane `Street.TIDE` (plot-local z 26) from `x0` to `x1`, west to east: `k` =
`along` on `StateClient.tideNow()`, plot-local x = x0 + 80 k, so every client puts it at the same place. `depth(x, k)`
(how far under, in studs: up to `DEPTH` (4.4, the tallest rider's head under) while within `UNDER` (2.4) of the jetty's
middle, easing down over the `DUCK` (1.5) studs before it, and coming up over the first and going down over the last
`ENDS` (0.035) of the way). Only the ones within `VIEW` (62) studs along x of the view's centre have models: its
driftling (`MicroModels.driftling`, facing the way it goes and turned a little toward the view, idling with a cheer
now and then) standing on a `TideRaft` (three driftwood planks; for a rare, epic or legendary one a pole and a Neon lantern at
its back corner in blue, purple or gold, so a light pool at night), both in `Workspace.PixelDynamic`, bobbing and
tilting; the rest are followed without models. One that leaves the attribute before 0.93 of the way (1 - 2 x
`ENDS`), or the own player just took, was taken in: it hops onto its island's jetty in `HOP` (0.6) s, cheering, as its
raft sinks; one that leaves at the end runs on out of sight and is dropped there. Over the own island's ones with
models it keeps World-root tags: a price button (`TideTake_<id>`: the cost and `mini_shell`, `button_ok` when the
shells are there, else `plate_light`) and, for an uncommon one or better, a name (`TideName_<id>`, in its rarity's
colour). The best workers' tags go first (`Tide.worth`, kept on the drift); a tag hides while its driftling is under
(depth 0.6 or more), off screen, or where it would overlap a better one's tag shown already, so not every one has a
visible tag at every moment. On tip 4 the `arrow_down_t` bobs over the cheapest shown tag the shells cover.
`take(id, swap?)` (sends `tide.take`; a notice with who moved in and what a swap sold for, the "rare" sound for a rare
or better one, else "pop"; `full` opens the tide panel's swap picker `{ take = id }`; other refusals in words),
`best(v, n) -> { Drift }` (the view's tide by `Tide.worth`, the best n; when the shells cover none of those, the best
one they cover takes the last place: the HUD's card and the tide panel), `tapAt(pos) -> boolean` (a tap at an
InputObject's position, which is below the top bar, so the inset is added back: of the own island's driftlings with
models and not under (depth 1 or less), the nearest one whose body's box on screen holds the tap is taken in; true when
it hit one), `step(t, focusX)` (WorldView's
Heartbeat: the near islands synced, every drift moved, dressed or undressed by `VIEW`, the tags kept), `depth(x, k)`,
`count(plot?) -> (followed, drawn)` (all islands' or one's: the sims and previews), `where(plot, id) -> (x?, y?, z?)`
(where one is now, world; nil when not followed: the sims), `ashore(i) -> (x, z)` (the jetty's island end on island
i: where one taken in comes ashore).
`StreetLife` (client, started after AvatarView): four boats (`MicroModels` "ship" at BoatSpec levels 1, 2, 1, 3, blob shadows) crossing
both ways on two lanes out at sea, rocking on the swell in whole steps, wrapping round the sea's ends; a flock of three
gulls crossing every 14-24 s, each crossing its own (east or west, a slant, a height, a weave, each gull a little
behind the next), every gull turned the way it flies (the model's head is +Z) and gliding now and then (no clouds'
shadows: the player asked for them gone). `count()` for the CLI.

### 10.3 `Hud`
The island's looks (GAME_DESIGN 2): the chips are carved boards in thin frames of planks (`CHIP_Y` 5), the cards in
thick ones with their names on planks (`CARD_Y` = `TOP_H` + 15, 7 px in from the right), the menu bar stands on a
`Dock` (a dark board in a thin frame, `DOCK` 6 px round the buttons); the camera's strips are kept clear of all of it.
Chips (`Chip_wood`, `Chip_shells`, each an 11 px icon and the store easing to its value, flashing when it changes; no
food chip since 2026-11-13; `Chip_day`, "Day 3" with the day's clock along its edge and a sun that sets into a moon;
then `Home`, a button shown while the founder is off their own island, sending `char.home`; `MusicToggle` in the top
right corner, the `mini_note`, sending `settings.set` music on / off, the note greyed while off), the menu bar
(`Menu_build`, `Menu_pals`, `Menu_index`, `Menu_looks`, each with its icon; while Build mode is open the bar and the
cards step aside and the tips banner rises over the tray with a Build mode wording (`TIPS_BUILD`)), the `IslandCard`
on the right (the island's name for its tier, driftlings in huts / the huts' room (`Pals`), visitors, charm, and what
a turn makes of wood and shells a minute, `Rate_wood` and `Rate_shell`: `Numbers.perMin`), the `TideCard` under it
(GAME_DESIGN 6: the `mini_tide`, "Tide" and `TideOpen` opening the "tide" panel, then a row each of
`TideView.best(v, 3)` (on a phone `best(v, 1)`): `TideName_<id>` in its rarity's colour, under it `TideLeft_<id>`
(an ink bar whose `Fill`, in its rarity's colour, Heartbeat sets to the time it has left from `StateClient.along`) and
`CardTake_<id>` (its cost and `PriceIcon`, sending `TideView.take`; green when the shells are there), or "Nothing
yet"; no `TideBar` since the conveyor; built again from `StateClient.TideChanged` and each view only when the rows'
ids, costs or whether the shells cover them change (its `Key` attribute); on a phone the card at the top left; hidden
in Build mode and while the "tide" panel is open), the questline's card `Quest` (GAME_DESIGN 9: down the left at `CARD_Y`, `QUEST_W`
150, under the `TideCard` on a phone; hidden while the tips are on and for a panel; `updateQuest(v)` from the view
through `Quest.current` / `Quest.progress`, laid out again when the quest or its count changes, sliding in: the
quest's `mini_` icon, `Title`, `Which` ("3/20"), `Words`, then the `Bar` and `Progress` with `QuestGo` (`goTo(go)`: a
panel, "tide" included, or `BuildUI.open(tab)`), or once done the reward (`Reward_<store>`, wood then shells) and
`QuestClaim` (shining; `quest.claim`, then a notice of what it paid)), the tips banner (`Tips`: the steps of
GAME_DESIGN 9 (`tut` 1 .. 6: a Lumber Camp, a farm, a hut, a driftling off the tide, a Snack Stall, the last; Build
mode's own words for 1, 2, 3 and 5); tip 6 has `TipsOk`, sending `tut.next`; a parchment note in a thin frame; on a
phone it keeps to the room left of the island card, wrapping to two lines), and the `DayBanner` (Fx "day" and "turn":
the day, what hatched; over a panel or in Build mode a notice instead); Fx "tide" with an epic or legendary one coming
in: a notice in its rarity's colour ("An epic Sunsprite is floating by."), the `grow` sound and a burst over the
`TideCard` (`onTide`; a rare one gets nothing since the conveyor, one comes about every half a minute). Shells coming in rise from their chip
("+12", at most every 2 s, from `StateClient.Tick`). Every frame it holds the founder's `JumpHeight` at 0 while Build
mode or a panel is up, else `Tuning.JumpHeight` (the phone's jump button hides with it), and sets the music's mood
(`Audio.music`). It reports its blocks to the camera (on PC the top strip, the menu bar and the card's place; on a
phone Roblox's top bar and the menu bar).

### 10.4 Menus
`Menus` registers the panels (the villagers' "folk" went with them): "pals" (`OpenTide` and, when a Hatchery stands,
`OpenHatch` at the top, the hint beside them in up to three lines (`UIKit.lines`: "6 in huts (room for 8). New ones
float past the island."); a row a driftling, every one, the hardest workers first (`Tide.better`) and those with no
hut last, `Pal_<id>`: portrait, name in its rarity's colour, its rarity, passive and its effects, mutations (`Mut_<id>`
each), where it lives and helps (`Where`; "No hut. It moves in when one has room." in orange); `Move_<id>` opens the
hut picker (the same panel with `{ move = id }`: a row a hut with its room, `Move_<uid>`; a full hut lists its
driftlings with `SwapWith_<id>`, sending `pal.house { id, uid, swap }`; no pen row), `Help_<id>` the picker of the
buildings of its knack (a driftling in a hut only), `Sell_<id>` (two taps, `Tide.price`); no `EquipBest` or
`OpenTree`), "tide" (GAME_DESIGN 6, 380 x 196: on the left `Pace` ("One floats by every second", else "One floats by every
0.8s", from `tideSecs`), `Room` ("In huts 6/8", orange when full), "What comes in now" and the odds of each rarity
(`Odds_<r>`, `Tide.odds`; "<0.1%" under a tenth of a percent) and, below tier 6, "A bigger island brings new kinds and
rarer ones."; on the right `Jetty` ("Floating by") and a row each of `TideView.best(v, 4)`, `Drift_<id>`: portrait,
name, rarity and how fast it works, mutations, `PanelTake_<id>` (its cost and `PriceIcon`, sending `TideView.take`)
and `Left` (the time it has left, its fill run down every Heartbeat from `StateClient.along`); no `TideBar` or
`Leaving` since the conveyor; on `StateClient.TideChanged` the panel is built again (`UIKit.refreshPanel`) only when
what it shows changes (`tideKeyOf`: the best four's ids, costs and whether the shells cover them; in the swap picker,
whether the one being taken is still there); with `{ take = id }`, every hut full, the swap picker: a hint naming the newcomer and its cost, `Back`, and a row a hut
driftling, the weakest first, `SwapOut_<id>`: portrait, name, rarity, how fast it works, mutations, "Sells for n" and
`SwapTake_<id>`, sending `tide.take { id, swap }`; once the newcomer has floated off, "That one has floated off." and
back to the tide panel), "hatch" (a row a Hatchery `Hatch_<uid>`: its egg (`egg_<rarity>`,
`EggName`, `EggLeft` ("Hatches in 3 turns"), `EggBar`, its parents) or the slots `Slot_a_<uid>` / `Slot_b_<uid>` (the
picker: the same panel with `{ hatch = uid, slot }`, a row `Parent_<id>`, `PickParent_<id>`), the likely child
(`Child`: its portrait if seen, else its shape and ???, its rarity), `Cost` ("A feast for 300 shells, 6 turns. ..."),
`Breed_<uid>`, on while the shells are there), "index" (`Entry_<species>`: portrait or silhouette, name or "???", the
kind of island it comes from, its passive once seen; "Seen n of 55 kinds"; a kind not open yet says the island tier
it floats by from: "These float by from island Lv 4.") and "looks" (the founder's portrait, `Prev_<k>` / `Next_<k>` for skin, hair, style and shirt,
`SaveLook` sends `founder.set`). `Words.errText(err)` words every ErrCode (`no_hut`: "Build a hut first. Driftlings
need somewhere to live."; `full`: "Every hut is full. Swap one out, or build another hut."; `not_found`: "That one has
floated off."; no `food` or `fixed`).

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
bottom (a workbench in a frame of planks, `wood = 3`, its tabs on a `plank`; the cards carved boards): the tabs `Tab_farm Tab_wood Tab_shop Tab_nest Tab_gen Tab_path Tab_decor` (Farms, Wood, Shops, Huts, Boosts, Paths, Decor; their icons
alone on a narrow screen; it opens on Wood), the count (`Count`: the pieces, or the path tiles on the Paths tab, against their limit), `Expand` (`island.expand`, its price under it; the fanfare and "Your island grew." wait for `PixelRenderer.afterBake`, 1.5 s at most) and `BuildDone`; a card a piece of the tab (`Buy_<id>`:
its price in wood with its icon (shells too only for a piece priced in them: none is now), red when short; a locked one says the island tier it needs). With a
piece picked (`pick(id, rot?)`), a ghost model (`Ghost` in `Workspace.PixelDynamic`: the piece and its `Footprint`, a
raised neon frame of four edges just above the grass, cyan (`screen_on`) where `Plot.fits`
says it fits, red (`berry_red`) where not) stands on the cell under the pointer (mouse) or the last tap; the bar shows
`Rotate`, `Place` / `Move here`, `Replace` (when another of its kind is open) and `Store` ("Clear away")
when moving a building, `Cancel`, and the `Info` plate (what it is and makes, a hut's room and comfort, its
charm, its price or the next level's). `Replace` turns the bar to `ReplaceBack`, `ReplaceWhat` and a card a
replacement (`Swap_<id>`: its name with its room, `SwapTo_<id>` with `Plot.replaceCost`), a tap sends
`plot.replace`. A tap on a placed piece of the own
island (a ray into its `Static.Decor`) picks it up (`Store`, Clear away, is always on: no piece is fixed since the
tree went). A press dragged more than 8 px pans the view
(`CameraController.panBy`). `confirm()` sends `plot.place` (the piece stays picked for another copy) or `plot.move`;
`close()`; `isOpen()`; `Changed: Signal<boolean>`; `tapScreen(pos, mouse?)` (the sims' and previews' tap). The tray
is laid out again when what can be afforded changes (`StateClient.Tick`). The tips (`TUT`: tip 1 wood / lumber, 2
farm / patch, 3 nest / nest, 5 shop / stall; tip 4, a driftling off the tide, has no building): opening, and each new tip while open (`followTut`, from
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
food wood sun moon charm folk pal visitor home nest tree train boost path decor start loot chest wild rest boss star
boat tide`; `tide` a wave curling over, the tide's (its card, panel and quests); `food` the Farms tab's; `tree`, the
Tree of Life's, unused since the tide; `train`, `start`, `loot`, `chest`, `wild`, `rest`, `boss` and `boat` unused
since the expeditions went), the arrows `arrow_<dir>` (13x13) and `arrow_<dir>_t` (7x7), `note`, `heart`, `spark_1..3`, `bombfuse`. `PixelSprites`:
`has(name)`, `size(name) -> (w, h)`, `image(parent, name, pos?, z?) -> GuiObject` (an ImageLabel `Sprite_<name>`
showing the sprite's EditableImage, made once and shared, `ResampleMode` Pixelated, at the sprite's own size: no
scale; without EditableImages a Frame of 1 px run rects), `anim(parent, names, pos?, z?) -> Anim { f, w, h, set(i),
flash(seconds?), moveTo(x, y) }`.

## 11. Verification

- `bash scripts/check.sh`: Rojo sourcemap, luau-lsp strict analysis (0 errors), luau-compile, the specs (`tests/run.luau`
  lists them: Util, Validate, Numbers, DataIntegrity, Traits, Island, Tide, Breed, Economy, Plot, Quest, Schema,
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
