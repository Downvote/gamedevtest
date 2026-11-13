# Driftling Isle: Architecture and Implementation Contract

The contract for the code in this repository (GitHub `Downvote/gamedevtest`). `docs/GAME_DESIGN.md` says what the game
does and why; this file says how the code is laid out, what each module offers and which data goes where. Where the
two disagree on an API, a type or a name, this file wins; on a number, `src/shared/Config/Tuning.luau` wins.

The build system, the conventions and much of the rendering code come from Random Bakery (`Downvote/test`, used
read-only as the reference: nothing there was changed). What was copied, and how it was changed, is listed in §12.

> The request (2026-11-13, GAME_DESIGN quotes it): "add a search button for the building ui." (`BuildUI`'s
> `SearchButton` and `focusSearch`, the `mini_search` sprite: §10.7)

> The request (2026-11-10, GAME_DESIGN quotes it with the choices made): "scrap this idea. could you make replicate
> beasty bay from kariosoft instead? still use the test repo as a reference" (an original island-village game in the
> genre: island building and farming, creature taming, expeditions and battles, villagers moving in, a shared sea)

> The request (2026-11-12, GAME_DESIGN quotes it with the choices made): "scrap the entire cave, fighting, level,
> skill and expedition system. instead, players start with a tree of life: it creates a creature every few seconds to
> be put into a pen. ..." (the expeditions' code is gone; the tree's pen, its levels and Equip best went on
> 2026-11-13, and the tree came back that day laying eggs, below)

> The request (2026-11-12, later): "remove villagers, only creatures should be enough" (no `Villager`, `folk`, homes,
> `folk.*` actions or Folk attribute; save version 11)

> The requests (2026-11-13, GAME_DESIGN quotes them with the talk before): "good idea, use the drifting in idea. you
> can remove the tree of life, there should now be a steady stream of driftlings, with rarities that players can pick
> up"; "also, make wood the main resource for building/expanding and shells the main resource of getting new
> driftlings. remove food as a resource"; later "make them float by just like a conveyer belt instead of drifting
> towards the island and stopping, with one every second" (what still holds: no `food`, eating or hunger; every piece
> priced in wood, `TierCost` in wood (its `TierCost[4]` was 150,000 then, 60,000 since the ten tiers), the Hatchery's
> feast in shells; the tide itself is gone again, below; its code is in this file's history up to commit 9d34e42)

> The request (2026-11-13, GAME_DESIGN 6): "never mind, bring back the tree of life and remove the
> converyer belt system. it now spawns eggs around it that the player can choose to hatch for some shells. ..."
> (`Logic/Tide` is `Logic/Tree` again: the tree a fixed 8 x 8 piece on every island (`Plot.isFixed`, ErrCode
> `fixed`), its eggs the profile's `clutch` (saved), mirrored as `ClientView.clutch` and the plot's `Eggs` attribute,
> drawn by `Controllers/EggView`; the action `egg.hatch` instead of `tide.take`; Fx "eggs" and "hatched"; no `Drift`,
> `s.tide`, `Street.TIDE`, `Tide` attribute, `TideView` or `Tide*` numbers; save version 13)

> And after it: "Also, make a limit of huts per island expansion level" (`Tuning.HutLimit`, `Plot.hutLimit`,
> `Plot.huts`, ErrCode `huts`)

> Then (2026-11-13, GAME_DESIGN 6): "Also, color each egg differently with different effects to allow players to
> distinguish easily between egg rarities" (`EggView.LOOK` and its sparks; the `egg_1` .. `egg_5` and `twinkle_*`
> sprites)

> The request (2026-11-13, the latest, GAME_DESIGN 4): "Make much, much more building options, like paths and fences.
> Polish the build ui more, just like the bakery game, and reference bloxburg. Also, add effects and polish when
> putting down decor and other amenities. There should be enough paths, fences and other detail to make a lot of
> vastly different themed islands. Also, add the ability to add water to make rivers. Make more island progression
> and allow the player to expand their land even more." (`Data/Buildings` with 245 pieces, their `tab`, `sub`, `water`
> and `feel` and the kinds `water` and `fence`; `Plot`'s tiles, water and fences with `plot.fence` and `plot.unfence`;
> ten tiers and `Tuning.FencePieces`; the model modules `Parts`, `GroundModels`, `FenceModels`, `NatureModels`,
> `ThemeModels`, `ThemeMoreModels` and `FunModels`; `BuildUI`'s catalog, `Controllers/BuildFx`, `Controllers/Puffs`
> and `UI/ThumbData`; save version 14)

> The requests (2026-11-13, GAME_DESIGN 2 and 6): "make the entire game feel more cozy, such as the pallette and other
> details to emphasize it. also, remove these, the eggs should be buyable only after the player clicks on the tree or
> enters the tree menu. also, make a cutscene for eggs hatching ..."; then "the egg hatching scene isnt detailed
> enough. add much much more detail to it, especially the egg. you are allowed to use 2d elements as well for the
> background"; then "There is no need to make things limited by squares and spheres, make everything more detailed
> with various shapes and textured objects. Also, like the bakery game, you can use 2d details ..." (no `EggHatch_`
> tags or `CardHatch_` buttons: `EggView.tapAt` and the HUD's `TreeCardTap` open the tree panel; `Tree.rise` and
> `Tuning.EggUp`, the result's `hr`; `Models/EggModels` (`build`, `hero`); `UI/HatchScene`, `UI/HatchBackdrop`;
> `Stage.clear` and the renderer's see-through sky; `Palette.modes.day` warm)

## 1. Layout and tooling

```
default.project.json   Rojo: Shared -> ReplicatedStorage, Server -> ServerScriptService, Client -> StarterPlayerScripts;
                       characters on (the founder walks and jumps on the islands: JumpHeight 7.2)
src/shared/            Types, Net, Config (Tuning, Monetization), Data (content), Logic (pure rules), Render (pure pixel
                       maths, copied; Fx, the effects in the pixel layer), Models (procedural models), Locale (Lang: English only)
src/server/            Main.server.luau, Services/* (DataService, Session, Router, IslandService, PlotService)
src/client/            Main.client.luau, Controllers/* (StateClient, CameraController, WorldView, EggView,
                       AvatarView, StreetLife, AmbientView, Audio, DayLight, BuildFx, Puffs), Pixel/* (PixelRenderer, BakeCast, PixelText, Snapshot, ImageMemory), UI/* (UIKit, Hud,
                       Menus, BuildUI, PixelSprites, ArtData and ThumbData (generated), Words)
src/first/             ReplicatedFirst.Loading (with Render/PixelFont and PixelFontData mapped beside it): Boot.client
                       (puts the loading card up first), LoadingCard, LoadingArt (generated: tools/preview/loading_art.sh)
src/RbxCharacterSounds.client.luau  an empty LocalScript in StarterPlayerScripts under the name Roblox would give its own
                       character sounds, so Roblox doesn't insert them (the founder's feet: Audio's step events)
tests/                 run.luau (spec runner), TestKit.luau, Career.luau (the Economy spec's player), career.luau (prints
                       its runs), specs/*.spec.luau
scripts/check.sh       the gate every change passes (§11)
scripts/gen_pixelfont.py  the pixel font's glyph tables (copied; README "Fonts and licences")
scripts/gen_art.py     every interface sprite as a text mask -> UI/ArtData.luau (outline, anti-aliasing, shading;
                       `--png <file>` writes a contact sheet; GAME_DESIGN 2's rules; §10.10), and the build catalog's
                       pictures (scripts/thumbs.txt, drawn by tools/preview/thumbs.sh) -> UI/ThumbData.luau
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
  "office"): `Data/Street` is the islands and the sea (no docks since 2026-11-13), `Data/Office` the island's tiers (their names),
  `Models/DecorModels` builds every building, `Models/StreetModels` the islands and the sea,
  `Models/MicroModels` the driftlings and the island's small moving things.

## 3. Types (`src/shared/Types.luau`)

`Look`, `Piece` (`{ uid, id, x, z, rot, lvl }`: anything standing on the island; `uid` stays while it stands; `lvl` a
level kept from an older save, else 1; (x, z) its footprint's north-west corner, plot-local, -160 .. 64; a path or water
tile's on even studs at rot 0; a fence length's an even grid corner and `rot` its way, 0 east or 90 south), `PlotSave`
(`{ placed }`), `Pal` (a driftling: `{ id, sp, home (a hut's Piece uid; 0: no hut, as when its hut was cleared away or
made smaller: it waits for room, `Tree.settle`), work (a Piece uid, 0 resting; only one in a hut works), muts? (its
mutations, Data/Traits ids) }`; no `held` since the pen went), `Laid` (an egg the Tree of Life laid: `{ id (its own id,
not a Pal id), r (its rarity, 1 .. 5: its look, `EggView.LOOK`), cost? (only on the client's copy: `Tree.cost` on this
island now) }`; what hatches is rolled when it is hatched), `Clutch` (the tree's eggs, saved: `{ left (seconds till the
next lot), list: { Laid }, next (the next egg's id) }`), `Settings` (`{ pixel, music? }`: music "on" | "off"), `Stats`
(`{ days, built, earned, taken (eggs hatched from the tree; the driftlings taken in off the tide and the ones the old
tree grew before version 13), sold (driftlings sold), best (the rarest had), hatched (the Hatcheries' eggs hatched) }`),
`Egg` (a Hatchery's: `{ uid (its Hatchery), a, b (the parents' ids), sp, muts, left (turns) }`, one a Hatchery),
`Profile` (the save, version 14: `shells` (what eggs cost), `wood` (what building costs), `day`, `tier`, `founder`,
`pals`, `plot`, `seen` (species -> 2 had one, the Index; 1, seen on the tide, only in a save from then), `eggs` (the
Hatcheries'), `clutch` (the tree's), `nextId` (driftlings and pieces share it), `tut` (1 .. 6, 0 done), `quest` (the
questline's quest on the go, Data/Quests; one past the last: all done), `stats`, `settings`, `createdAt`; no `food` or
`tree` levels), `ClientView` (the profile's fields plus `dayFrac`, `plot` (the plot index), `pieces`, `rates` (`{ wood,
shells }` a turn), `charm`, `nests` (the huts' room), `visitors`; `pals` is every driftling; `clutch` the tree's eggs
now (`{ Laid }`, each with its `cost`), `clutchLeft` the seconds till the next lot, `clutchSecs` the seconds between two
(`Tree.secs`); no `tide` or `tideSecs`), `ErrCode` (with `no_hut`: no hut built to hatch into; `full`: no room in that
hut, every hut full for an `egg.hatch` with no swap, or the island's piece, tile or fence limit reached; `fixed`: the
Tree of Life can't be cleared away; `huts`: the island's huts' limit reached; no `food`),
`Response`, and the utility types `Connection`, `Signal<T...>`, `Rng`, `PixelTier`. The file is the reference for
every field.

## 4. Config

- `Config/Tuning.luau`: persistence (`DataStoreName = "BSS_Profile_v1"`, never renamed), the island (`StartWood` (300:
  the tips' buildings and plenty over), `BuildingPrice` (0.3: the Work and Huts tabs' buildings cost this share of
  their listed price, Data/Buildings `priceOf`: "make it much cheaper to buy work and hut buildings"), `StartShells`
  (60: the first eggs), `TurnSeconds` (the island's pace),
  `DaySeconds` (the sea's day: hours), `IdleOutput` (a building's work with nobody at it), `PalWork` (a common
  driftling's), `RarityWork` (a driftling's work by its rarity), `HelpMax` (driftlings a building), `VisitorCharm`,
  `VisitorsMax`, `ShopVisitors`, `Refund`, `UpgradeMult` (a level from an older save; no upgrades since 2026-11-11),
  `TierCost` (the wood to grow to each of the ten tiers: 0, 600, 9,000, 60,000, 160,000, 380,000, 800,000, 1,600,000,
  3,000,000, 5,000,000; every table by tier has ten entries, GAME_DESIGN 4.4), `ComfortLvl`, `BoostMax`; no `StartFood`,
  `EatPal` or `Hungry` since food went), the Tree of Life's eggs (GAME_DESIGN 6: `EggSecs` (180: seconds between two
  lots), `EggCount` (eggs a lot by the island's tier: 5, 6, 7, 8, 9, then 10), `EggPrice` (shells by rarity: 20, 90,
  400, 2,000, 10,000), `EggTier` (the price's multiplier by the island's tier: 1, 3, 8, 20, 45, 90, 160, 270, 420, 640),
  `EggLuck` (the luck by tier: 0, 0.25, 0.5, 0.75, 1, 1.3, 1.6, 1.9, 2.2, 2.6), `EggMutTier` (2: tiers for a hatchling's
  mutation roll one rarity up), `EggUp` (an egg's chance a step to turn rarer as it hatches, by rarity: 0.06, 0.04, 0.025, 0.012), `HatchSceneWait` (4 s: the hatch scene's blinds wait at most this for its picture), `HatchSceneHold` (6 s: it waits this on what hatched before going back by itself), `TreeStage` (the tree model's stage by tier: 1, 2, 2, 3, 3, then 4), `HutTree`,
  `HutLuck`, `HutCost` (the huts' tree, luck and cost shares at most: 0.5 each), `SellPrice` (by rarity), `SellTier` (a
  mutation tier's share on a price); none of the tide's `TideSecs`, `TideLife`, `TidePrice`, `TideTier`, `TideRare`,
  `TideLuck`, `TideMutTier` or `HutTide`, and none of the old tree's `TreeSecs`, `TreeLuck`, `TreeMutLuck`,
  `TreeSpeedCost`, `TreeLuckCost`, `PenSafe`, `PenShown` or `TreeStages`), breeding (`BreedShells` (the feast by the
  child's rarity), `BreedTurns`, `BreedKeep`, `BreedTierUp`, `BreedNew`), the server's step and rate limit, the sea
  (`MaxPlots`, `PlotSpacing`, `PlotPieces` (buildings and decor by tier: 36, 60, 90, 130, 180, 240, 300, 370, 450, 540),
  `HutLimit` (huts an island may have by its tier: 4, 6, 8 .. 22), `PathPieces` (path and water tiles together: 80, 150,
  240, 340, 460, 600, 750, 900, 1,050, 1,200), `FencePieces` (fence lengths: 40, 80, 130, 180, 240, 300, 370, 440, 520,
  600), `HomeCooldown`, `WalkSpeed`, `SwimSpeed` (11: in the sea), `JumpHeight`), and the camera and pixel filter values (Random Bakery's `CamYaw` 45,
  `CamPitch` 30, `PixelTiers`, `PixelScaleMin` / `PixelScaleSides`; this game's `CamRayBack`, `PixelMaxRayDist`,
  `CamFollowBox`, `CamGlide`, `CamBuildPan`, `PixelPanRays`, `PixelInvalidateRaysFrame`, `PixelMaxDyn`).
- `Config/Monetization.luau`: `GamePasses`, `DevProducts`, `Badges` (empty or 0), `Sounds` (the Creator Store
  library ids `Controllers/Audio` plays: Roblox's free licensed ProSoundEffects clips and APM Music stingers, none of
  Random Bakery's, each named in a comment) and `Music` (`{ day, night }`: lists of `{ id, gain }`, APM Music
  tracks, each named; `gain` evens their loudness out).

## 5. Data (pure content tables)

| Module | Holds |
|---|---|
| `Data/Palette` | the LUT colours (`order`, `colors`), the shore's `shallow`, `foam`, `rock` and `rock_dark`, the older rooms' floor and wall themes (`themes`, still in the LUT), the build catalog's 16 theme colours (`moss maple bamboo clay slate snow ice lava basalt crystal cherry teal swamp coral straw brick`, in `order` and so in the LUT), the light modes (`modes.day` a little warm, 1.03, 1, 0.95: GAME_DESIGN 2's cozy light), and the UI's colours (`ui`, `axis`, `match`) |
| `Data/Buildings` | the 245 pieces (GAME_DESIGN 4) and the Tree of Life `{ id, name, kind (farm wood shop nest breed gen path water fence decor tree), shells (0 for every piece since 2026-11-13, kept for a price in both), wood (the price: the old shells and wood added up; a Work or Huts tab building's, kinds farm wood shop gen nest breed, times `Tuning.BuildingPrice` to two figures, 5 at least: `priceOf`), w, d (a path or water tile 2 x 2; a fence length w 2, d 0: a line along the grid), rate (a turn with one common driftling at it: wood for kind wood, shells for farm and shop), knack, slots (a hut's room), charm (a path's, water's or fence's may be a fraction), comfort (a hut's share), boost ("farm" "fish" "wood" "shop" "all": a "gen" piece's knack), boostBy, tier (1 .. 10), blurb, tab (Build mode's tab: `work nest path fence water nature decor fun`; from the kind when not given: farm, wood, shop and gen "work", nest and breed "nest", path, water and fence their own, decor "decor"), sub (its row of chips: a Decor piece's theme `beach garden farm harbour town jungle frost autumn desert fairy zen volcano grand`, Nature's `trees plants rocks`, Fun's `seats lights play treats fountains`, Water's `tiles bridge float`, Work's the kind `farm wood shop gen`; "" for the huts, paths and fences), water ("" none; "over": may stand over water tiles as well as grass, the bridges, the dock, the waterwheel and the little waterfall; "on": only on water tiles, lily pads, reeds, stepping stones, the duck decoy, the rowboat, lotus flowers, floating lanterns), feel (what putting it down throws up and sounds like, `Controllers/BuildFx`: `wood stone plant water metal magic sand snow cloth fire`; from the kind when not given: path stone, water water, farm plant, else wood) }`; kind "farm" (the old "food": it sells what it grows or catches for shells), "nest" the huts (Driftling Hut .. Driftling Palace), "path" and "water" the drawn tiles, "fence" the drawn lengths, "decor" everything for charm on the Nature, Decor, Fun and Water tabs (the bridges and floating pieces among them), "tree" the Tree of Life (`tree`: 8 x 8, charm 6, no price, tier 99 so no tab of the tray shows it; every island's, `Logic/Tree`); no `eats`, and no one-piece `fence` or `hedge` since save version 14; `list`, `byId` |
| `Data/Creatures` | the 55 driftlings (GAME_DESIGN 6) `{ id, name, islet (its kind, Data/Islets), rarity (1 common .. 5 legendary), hp, atk, def, spd (kept only for `power`), knack, shape (its MicroModels body plan), body, accent, blurb, passive ({ name, fx }: its own, Data/Traits effects), power (its stats weighted, +12% a rarity step: the breeding rank) }`; `list`, `byId` |
| `Data/Traits` | what makes one driftling unlike another (GAME_DESIGN 6): `MAX` (4 mutations), `KEYS` (the effects: work farm fish wood shop (shares at work), cost (the eggs' price: below 0 cheaper), sell (the price), charm (whole points), tree (the next eggs sooner), luck (luckier eggs); cost, tree and luck count from a driftling in a hut, for the whole island; 0.1 = +10%; `cost` was `eat` before the tide and the driftling's own price on it, `tree` was `tide` on it), `RARITY` (`{ name, color, weight }` x 5: the tree's weights before luck, 100 45 16 5 1.2), `TIER_COLOR`, `TIER_STARS`, `list`, `byId` (mutations `{ id ("sturdy3"), family, tier (1 .. 4; 0 a flaw), name, blurb, fx }`: ten families x four tiers and five flaws; the families keep their old ids, "sturdy" now Thrifty .. Selfless (cost) and "swift" Leafy .. Evergreen (tree), so older saves read them), `families`, `at(family, tier)`, `roll(rng, rarity) -> { id }` (0 .. 3, no family twice, a rarer one rolls fewer flaws and higher tiers), `sum(passive?, muts?) -> Fx`, `workAt(fx, knack)` (work + the knack's share, at least -0.5), `clean(muts)` (known ids, a family once, at most MAX), `describe(fx)` ("+24% at farms, eggs cost 30% less, +2 charm, eggs 4% sooner", "+5% egg luck") |
| `Data/Quests` | the questline (GAME_DESIGN 9) `{ id, title, text (what to do and where), goal { kind, n, of? }, reward { shells?, wood? }, go (its Go: a panel "pals" "index" "hatch" "tree", or "build" / "build:<tab>"), icon (a `mini_` sprite) }`, twenty in order; `list`, `byId`. Goal kinds: helpers (driftlings at work) housed (in huts) built (of a building kind) paths decor taken (eggs hatched from the tree) sold best (the rarest had) tier seen hatched; the tree's `luck`, `speed` and `grown` are gone |
| `Data/Islets` | the 9 kinds of land the driftlings come from (GAME_DESIGN 6) `{ id, name ("Beach"), plural, tier (the island tier its driftlings start hatching at: Beach, Meadow 1; Snowfield, Mangrove 2; Volcano, Grotto 3; Reef 4; Bluffs 5; Ruins 6), wild (every driftling of its kind, from Data/Creatures, the commonest first), color, blurb }`; `list` |
| `Data/Looks` | skin, hair, hair style and shirt lists (`Types.Look` indexes them: the founders and the visitors; `Data/Names`, the villagers' names, went with them) |
| `Data/Office` | the island's ten tiers (`plans[tier]`: `{ tier, name }`, Castaway Cay, Palm Isle, Grand Isle, Harbor Town, Coral City, Sunspire Capital, Moonlit Bay, Evergreen Isle, Skyreach Isle, Driftling Haven: the island card's title and Expand's cheer), `plan(tier)`, `origin(plot)` (Data/Street's). The island has no house (GAME_DESIGN 8) |
| `Data/Street` | the islands and the sea (GAME_DESIGN 8): `warm(tier)` (works a tier's cells out now: tens of ms at the top tiers, so never at an expansion), `MAX`, `SPACING`; the heights `LAWN_Y` (-0.5: the grass), `SAND_Y`, `WET_Y`, `FOAM_Y`, `SHALLOW_Y`, `WATER_Y` (each band a little lower than the one inside it), `SEABED_Y` (-1.6: the invisible floor under the whole sea the founders swim on, a step below the wet sand); the cell layers `GRASS SAND WET FOAM SHALLOW SEA_CELL` and how far past the coast each reaches, `BANDS` (`sand` 2.5, `wet` 3.5, `foam` 4.5, `shallow` 8 studs); `SEA` (the open sea south of the lots, plot-local z 30 .. 58; no `BOARD`, `PATH`, jetty, pier or mailbox since the docks went on 2026-11-13: "remove the docks area, it should just be an island. players can swim around in water to reach other player islands"), `FAR` / `END_FAR` (water past the world's walls: no sky at the world's edges), `LOT` (a plot's lot: x +-40, z -136 .. 30, room north for the biggest island's shallows), `CENTER`, `PLAZA` (the campfire's plaza); the coast: `isle(tier)` (its oval: centre, radii, wobble phases; `ISLES` has ten, the last four as wide as the capital's (`rx` 31) and longer, their centres further north: `cz` -27, -34, -41, -48, `rz` 41, 47, 53, 59), `coast(tier, x, z)` (studs from the coast, below 0 inland: the oval's radius times a wobble of four sines, joined
to every smaller tier's shape (the least distance) so an island only gains land as it grows), `layerAt(d)`, and per whole-stud cell (cached per tier; `cellKey`) `layer`, `cellDist`, `cellBounds(tier)`, `buildable(tier, x, z)` (grass a stud or more inside the coast), `walkable` (grass, sand, wet sand), `plot(tier)` (the grass's bounding box); `origin(i)` (plots centred on x = 0), `plotAt(x, z)` (the open sea south of a lot counts as that lot's), `bounds()` (every lot and the sea south of them: where a founder can swim), `spawn()` (on the plaza, south of the campfire), `sign(tier)` (the island's sign on its south beach, west of the plaza) |

Coordinates in `Data/Street` are studs, plot-local, +Y up. The camera looks from the south-east (+X, +Z), so an
island's back is its north-west. A piece's `rot` turns its model (built facing +Z: south, toward the viewer).

## 6. Logic and models

Pure rules (`src/shared/Logic`), all specced in `tests/specs`; every action returns `(true, data?)` or `(false,
ErrCode)` and changes the profile only on success:

| Module | API |
|---|---|
| `Util` | copied from Random Bakery: `hash32`, `newRng(seed)` (xorshift32: `next int range chance weighted`), `pick`, `shuffle`, `Signal`, `round clamp lerp isFinite sig2 deepCopy count` |
| `Island` | the turn and the day (GAME_DESIGN 3): `piece(p, uid)`, `nests` (the huts' room), `fxOf(pal) -> Fx` (its passive and mutations, `Traits.sum`), `charm` (every piece's, and each driftling in a hut: 1 + its charm share), `visitors`, `works(id)` (a building that makes something: kind farm, wood or shop), `homes(p) -> { [key]: { uid, comfort } }` (each hut driftling's hut and its comfort (the hut's plus `ComfortLvl` by level), "p<id>", none for one with no hut), `boosts(p) -> { farm fish wood shop all }` (each kind of boost building once), `boostAt(b, knack)` (its own and "all", `BoostMax` at most), `palWork(p, pal) -> number` (its work share at its building's knack, `Traits.workAt`), `palBoost(p, pal, comfort?)` (`PalWork` x `RarityWork[rarity]` x max(0, 1 + `palWork` + the hut's comfort): what a driftling puts in), `rates(p) -> Rates` (`{ wood, shells }` a turn; a building makes its rate times its driftlings' `palBoost` summed (`IdleOutput` with nobody), times 1 + `boostAt`, times `UpgradeMult` by level: a wood building wood, a farm shells, a shop shells times min(2, visitors / `ShopVisitors`); nothing eats), `step(p, dt) -> Rates` (the stores; the shells counted in `stats.earned`), `randomLook(rng)` (a visitor's), `freeJob(p, knack, fx?) -> uid` (a workplace with fewer than `HelpMax` driftlings: one of that knack first, else the one where `fx` works fastest (`Traits.workAt`), then the emptiest, farms before wood before shops, the first built; 0 none), `newDay(p)`, `setHelp` (only a driftling in a hut, at any workplace whatever its knack (2026-11-13: "make it such that each creature can work at any place, and is no longer restricted"): `HelpMax` a building, the first there sent back to rest; bad_payload for one with no hut or a building that makes nothing), `expandCost(tier) -> { shells = 0, wood }?` (`TierCost`, nil at the top), `expand(p)` (max, wood; data `{ tier, moved, cleared }`: `Plot.refit`), `setFounder` |
| `Plot` | building (GAME_DESIGN 4): `ROTS`, the limits by tier `limit(tier)` (`PlotPieces`), `hutLimit(tier)` (`HutLimit`: huts the island may have), `pathLimit(tier)` (`PathPieces`: path and water tiles together), `fenceLimit(tier)` (`FencePieces`); `huts(placed)` (the huts standing); what a piece is: `isPath(id)`, `isWater(id)`, `isTile(id)` (a path or water: 2 x 2, drawn on the even studs), `isFence(id)`, `isDrawn(id)` (a tile or a fence: Build mode's draw bar, never placed one at a time from a card), `isFixed(id)` (the Tree of Life: moved, never bought, cleared away or replaced), `onPaths(id)` (a piece of the Decor, Nature or Fun tab with no `water` mark, never the tree: it may stand on path tiles, and paths may be drawn under it; no hut, workplace, fence or water piece), `group(id)` ("tile", "fence", "fixed" (the tree: never counted) or "piece": the limit it counts toward), `groupLimit(group, tier)`, `used(p, id) -> (n, limit)` (the pieces of its group and that group's limit); `footprint(id, rot)`, `rect`, `blockers(tier)` (the campfire's plaza; the path to the jetty went with the docks), `fits(tier, placed, id, x, z, rot, skip?) -> (ok, "outside" (a footprint cell not `Street.buildable`, a tile off the even studs, a fence off the grid, a piece marked "on" not wholly on water tiles) / "blocked" / "overlap" / "unknown")` (one piece never on another but: a piece marked `water` "over" or "on" on water tiles, and water dug under one; an `onPaths` piece on path tiles, and paths drawn under one; tiles and fences never in each other's way; a fence length (`fenceFits`: from an even corner, rot 0 east or 90 south, each of its two studs with buildable grass on one side or the other, not through the plaza, the path or a piece's footprint but free to run along its side, not on another length) never inside a piece's footprint, so no piece goes down across a fence), `spot(tier, placed, id, x, z, rot) -> (x?, z?, rot?)` (the free spot nearest x, z: `Tree.plant` plants with it, `refit` moves with it), `unhouse(p, uid, keep?)` (a hut's driftlings past its first `keep` left with no hut, resting; `Tree.settle` moves them in again; was `toPen`), `place` (bad_payload (an unknown piece, a home of the old saves, the tree), locked, full (its group's limit), huts (a hut past `hutLimit`), money (a price in shells: none has one now), wood, blocked; data `{ i, uid }`), `move` (the tree too; blocked for the spot; no upgrades: taken out 2026-11-11; a level from an older save stays and counts), `replaceCost(q, id)` (the new price less `Refund` of the old, never below nothing), `replacements(q, tier)` (the others of its kind open at the tier, a decor piece's only from its own row: the same `tab` and `sub`, a tree for a tree, a bench for a bench; none for the tree or a drawn piece, which is drawn over instead), `replace(p, i, id)` (bad_payload (another kind, the same piece, the tree), locked, money, wood, blocked (the new footprint where the old stands); a smaller hut keeps the driftlings it has room for, the rest left with no hut; the uid kept, the level 1, its driftlings staying (any driftling works anywhere); bad_payload too for a drawn piece or a decor piece from another row, the same rows `replacements` offers), `store` (fixed (the tree), egg; `Refund` back; a hut's driftlings left with no hut), `refit(p) -> (moved, cleared)` (the tree first, keeping its place; pieces that do not fit move to the nearest free spot, or are cleared with their whole price back; a tile or a fence is never moved, only cleared; never the tree: after the island grew and when a save loads); a hut past `hutLimit` in a save is kept; drawing (GAME_DESIGN 4: Build mode's draw bar): `PATH_STEP` (2: a tile's cell and a fence's length, on the even studs), `PAINT_MAX` (40 cells or edges a request), `cells(s) -> { {x, z} }` and `cellString(cells)` (the payload's "x,z;x,z": tiles' north-west corners), `edges(s) -> { {x, z, rot} }` and `edgeString(edges)` ("x,z,r;...": a length's corner and its way), `paint(p, id, cells) -> (ok, { placed, swapped, skipped })` (a path or water piece only; the cells in order: one with a tile of the same look passed over (skipped), one with a tile of another look of the same kind swapped for it (`Refund` of the old back, the new one paid, the uid kept, `stats.built`), a free cell that fits given a tile at rotation 0, one that doesn't fit skipped; it stops at the tile limit or when the stores run out; bad_payload, locked, or full / money / wood / blocked when none changed), `unpaint(p, cells, kind?) -> (ok, { removed, floated })` (every tile of `kind` ("path", "water" or "all") covering one of the cells' studs comes up with `Refund` back; anything marked "on" no longer wholly on water comes up with it, `Refund` back too; a piece on path tiles stays where it stands; not_found), `fence(p, id, edges) -> (ok, { placed, swapped, skipped })` (a fence piece only; `paint`'s rules along the edges: another fence on an edge swapped, a new length where `fenceFits`, the fence limit; an edge turned other than 0 or 90 skipped), `unfence(p, edges) -> (ok, { removed })` (the lengths on those edges down, `Refund` back each; not_found) |
| `Tree` | the Tree of Life, its eggs and the huts (GAME_DESIGN 6; `Logic/Tide` for a few hours on 2026-11-13): `ID` ("tree"), `SPOT` (-4, -6: behind the campfire), `hutFx(p) -> (tree, luck, cost)` (the huts' driftlings' shares, at most `HutTree` / `HutLuck` / `HutCost`; cost as a share off, 0 .. `HutCost`), `secs(p)` (`EggSecs` / (1 + the tree share): seconds between two lots), `count(tier)` (`EggCount[tier]`: eggs a lot), `stage(tier)` (`TreeStage[tier]`: the tree model's stage), `luck(p, tier?)` (1 + `EggLuck[tier]` + the luck share), `pool(tier) -> { { sp } }` (by rarity, the kinds open at the tier), `odds(p, tier?) -> { share }` (each rarity's weight x luck^(r - 1), a rarity the pool lacks given to the next commoner one), `worth(pal)` (`RarityWork` x (1 + its share at its knack): the lists' order and the weakest in a swap, kept per driftling table in a weak table, its kind and mutations never changing), `worthAt(pal, knack)` (the same at a building of `knack`: the work picker's speed at each workplace), `better(a, b)` (the better worker first, then the older), `price(pal)` (what it sells for: `SellPrice` x (1 + `SellTier` x its mutation tiers) x max(0.2, 1 + its sell share), whole shells, at least 1), `cost(p, r)` (an egg of rarity r: `EggPrice[r]` x `EggTier[tier]` x (1 - the cost share), whole shells, at least 1), `huts(p) -> { Hut }` (`{ uid, room, comfort, n }`, the comfiest first, then the first built), `room(p)` (the huts' free places), `settle(p) -> { id }` (the driftlings with no hut, the best first, into the huts with room, the comfiest first, each taking a free job, its knack's first (`Island.freeJob` with its effects): who moved), `fillJobs(p)` (resting hut driftlings to free jobs), `add(p, sp, muts) -> Pal` (a Hatchery's hatchling: the comfiest hut with room, or none; a free job; `seen` 2, `stats.best`), `roll(p, rng, rarity, knack?) -> (sp, muts)` (a kind of that rarity open at the tier, a commoner rarity when none is; of `knack` when asked and it has one; `Traits.roll` at the rarity + (tier - 1) // `EggMutTier`), `fill(p, rng) -> { Laid }` (eggs up to `count(tier)`, each rarity by `odds`; on a new island (`stats.taken` 0, no driftling) the lot's first two commons; the new ones), `lay(p, rng) -> { Laid }` (a new lot: the list cleared, `left` = `secs(p)`, then `fill`), `step(p, dt, rng) -> { Laid }?` (`left` - dt; at 0 or below, `lay`; nil when nothing was laid), `view(p) -> { Laid }` (the client's copy, each egg with its `cost`), `rise(p, rng, r) -> number` (the rarity an egg of rarity r hatches as: up one with `Tuning.EggUp[r]` and on while the rolls hold, never to a rarity `pool(tier)` lacks), `hatch(p, id, swap, rng)` (not_found (no such egg: a new lot came), no_hut (no hut built), money, full (every hut full and swap 0), bad_payload (a swap that isn't in a hut); the shells paid, the egg gone, a swapped one sold (`price`, `stats.sold`, `stats.earned`) and its hut taken, else the comfiest with room; `rise` (not for the first two on a new island), then `roll` at that rarity (the first two of the knack "wood", then "farm"); a free job; `seen` 2, `stats.taken`, `stats.best`; data `{ id, sp, muts, egg, r, hr, cost, sold, swapped }`: `r` the rarity laid, `hr` the one it hatched as), `sell(p, id)` (not_found; its price, `stats.sold`, `stats.earned`, then `settle` and `fillJobs`; data `{ shells, sold }`), `house(p, id, uid, swap)` (to another hut and a free job there, its knack's first; a full hut only in a swap with `swap` (one living there), which goes where this one was; not_found, bad_payload (not a hut, a swap not living there), full; then `settle` and `fillJobs`; data `{ moved }`), `piece(p) -> Piece?` (the tree's), `plant(p) -> Piece?` (an island with no tree gets one at the free spot nearest `SPOT`; on one built full the pieces nearest it make room, paths first, then decor, then the rest that houses nobody, each cleared with its whole price back). None of the tide's `State`, `new`, `start`, `drift`, `life`, `along`, `entry` or `take`, nor the old tree's pen, levels and `equipBest` |
| `Breed` | the Hatchery (GAME_DESIGN 6.1): `child(a, b) -> sp` (a pair of one kind its kind, else the kind (no legend unless both are) of power nearest their average; the commoner, then the first id, on a tie), `cost(sp) -> (shells, turns)` (`BreedShells`, `BreedTurns` by its rarity), `inherit(ma, mb, rng) -> muts` (shared: always, the better tier, `BreedTierUp` one better; one parent's: `BreedKeep`; `BreedNew` a tier 1 or 2 of a new family; the best four), `eggAt(p, uid)`, `start(p, uid, a, b, rng)` (not_found, egg, bad_payload, money; the feast paid in shells, `p.eggs` + 1), `turn(p) -> { Pal }` (each egg a turn nearer; a ready one hatches into a hut with room, or none (`Tree.add`), `stats.hatched`) |
| `Quest` | the questline's rules (GAME_DESIGN 9): `Facts` (`{ pals, pieces, tier, seen, stats }`: a profile's, `facts(p)`, or the client view's, same names), `count(facts, goal)` (how far: driftlings at work (`helpers`), path tiles, decor, pieces of a kind, driftlings in huts (`housed`), the stats' counts (`taken`, `sold`, `hatched`), the rarest had (`best`), the tier, kinds in the Index), `current(tut, i) -> (Quest?, i)` (none while the tips are on, or past the last), `progress(facts, q) -> (have, need)`, `done(facts, q)`, `claim(p)` (not_found, not_done; the reward paid in shells and wood, `p.quest` + 1; data `{ id, shells, wood, next }`) |
| `Schema` | `VERSION` (14: the build catalog), `default(now, seed)` (`StartShells`, `StartWood`, no driftling, `clutch` `{ left 0, list {}, next 1 }` (the first lot laid on the first step), then `Tree.plant`), `migrate(raw)` (1 -> 2: a founder; 2..4 -> 5: the studio gone, the founder, settings and start kept; 5 -> 6: the tips' steps moved (3 -> 5, 4 -> 6); 6 -> 7: each driftling rolls its mutations once, seeded by its kind and id; 7 -> 8: the questline; 8 -> 9: `boat` and `chart` gone; 9 -> 10: `cap`, `islets`, `sea`, `wilds` and `pouch` gone, a Training Yard refunded (450 shells, 50 wood), the driftlings put in the nests (now huts) in the old order (the comfiest first, in the order they came), the rest to the pen (sold at 11 -> 12), `tut` past 5 back to 5, `quest` 1, `stats.grown` from the old `befriended`, `stats.best` the rarest kept; 10 -> 11: `folk` gone, every home (Tent .. Manor) taken down with its whole price back, `tut` past 4 back one, `stats.movedIn` gone; 11 -> 12: `tree` and `food` gone, the tree's piece taken off the plot, every driftling with no hut (the pen's) sold for `Tree.price` (shells, `stats.sold`, `stats.earned`), `held` dropped, `stats.grown` renamed `stats.taken`; the tips keep their numbers; 12 -> 13: `clutch` dropped (reconcile makes it: the tree planted, its first lot laid when the player arrives); 13 -> 14: the old one-piece fence and hedge (ids `fence` and `hedge`, now drawn: Picket Fence, Hedgerow) taken off the plot with their whole price back in wood (25 and 120 each)), `reconcile(raw, now, seed)` (any table -> a valid Profile: pieces that exist with unique uids, each group to its own limit (`Plot.group`: the pieces, the tiles, the fences, one tree), x and z clamped to -160 .. 64, valid turns (a fence's 0 or 90 from an even corner, any other dropped; a tile off the even studs is cleared by `Plot.refit` below, its whole price back), driftlings with unique ids (at most `MAX_PALS`, 5000) (a driftling's `home` a standing hut with room or 0, `work` only from a hut at a workplace (a farm, wood or shop building, any knack), `muts` through `Traits.clean`), the Index's species, `nextId` past every id, `tut` 0 .. 6; then `Plot.refit`, `Tree.plant`, the clutch (rarities 1 .. 5, ids unique, at most `Tree.count(tier)` eggs, `left` 0 .. `EggSecs`, `next` past every egg id) and `Tree.settle`) |
| `Validate` | `ACTIONS` (the action catalogue, §7.3: `egg.hatch` `{ id = int, swap = int }` in place of `tide.take`; `plot.fence` and `plot.unfence`; `plot.unpaint` with its `kind`), `request(action, payload) -> (ok, err?)`: exact schemas, unknown and missing fields refused. Field kinds of the building actions: `coord` a whole number in [-160, 64] (a plot-local stud: the far islands reach that far north), `index` [1, 4096] (a placed piece: pieces, tiles and fences), `cells` 1 to 40 cells "x,z" joined by ";" (each a coord), `edges` 1 to 40 edges "x,z,r" (each a coord, r 0 or 90), `tiles` "path", "water" or "all" (which tiles an eraser takes up) |
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
  `poseAction(rig, base, t, speed, action, k?)` (`cheer hurt swing reach pet cast jump sneak dance`, `swim` (in the
  sea: a crawl when `speed` > 1, the arms turning over in turn and the legs kicking, leaning 30°; else treading
  water, the arms sweeping out and back with a slow bob), the
  fights' `windup strike guard throw run victory ko` (nothing plays them now), and the island's work, each a loop with `k` the beat's phase:
  `dig pick fish chop saw sell serve hammer train tend`), `WORK_HIT` (where in a beat a work's blows land:
  `{ [action]: { phase } }`), `STAND_TOP`.
- `Blocks.windy(root)`: the wind's tags for the pixel filter (§9.3): every part named `Flag...` or `Pennant...` (not
  a `...Pole`) gets `PixelWind` 2, every part in `leaf` or `leaf_dark` `PixelWind` 1 (water parts left alone). Called
  by `StreetModels.land` and `DecorModels.build` on their models.
- `BoatSpec` (the boat's plan for the sailboats: GAME_DESIGN 8; the ambient boats are levels 1 to 3; the pier's boat
  and `moor` went with the docks on 2026-11-13): `MAX` (6), `dims(level) -> { L, W, H }`,
  `deck(level)` (the four places on deck, founder first: deck-top coordinates, +Z the bow), `deckOverWater(level)`, `parts(level) -> { { name, shape ("Block" "Wedge" "CylY"), size, cf (from the
  deck top's centre; the `Bow` wedge turned over: tall at the hull, its keel sloping up to the point), color, neon?,
  wind? } }` (the hull and every detail of GAME_DESIGN 8 by level; flags named `Flag...`). Every user applies `cf`'s
  rotation (MicroModels.ship, StreetModels.boat).
- `StreetModels` (no docks since 2026-11-13: no boardwalk, pier, boat, jetty, path, mailbox or coast walls): `road(parent,
  origin)` (a plot's water, `PixelWater` 1, `CanCollide` false, and the `Seabed` under it: an invisible floor, top at
  `Street.SEABED_Y`, over the lot and the sea south of it), `land(parent, origin, tier)` (the island: its cells meshed
  into rectangles layer by layer (the shallows `PixelWater` 2 and the foam 3, neither colliding, an invisible `Shelf`
  under the foam halfway between the seabed and the wet sand as the step out of the sea; the wet sand, the beach, the
  grass in two tones), the campfire's plaza (`FireStone`s, logs, a flame, seats, a flag, torches), the sign with its
  `SignBoard` on the south beach (`Street.sign`), and palms, rocks, shells, starfish, driftwood, seaweed and tufts
  strewn by the plot's own seed, kept clear of the sign; `Blocks.windy`), `emptyLot(parent, origin)` (open water and a
  sandbar), `ends(parent)` (the sea past the ends with its seabed, sandbars past the walls, and the walls round the
  world, 40 studs high). The seabed, the shelves and the walls are invisible, in the collision group `Bounds`, which
  the pixel filter's rays (group `PixelRays`) pass through; the water lets a founder through, so they swim anywhere
  inside the world's walls and climb out on any beach.
  The layers are bevelled (2026-11-13, GAME_DESIGN 8: "could you bevel these to make them smoother, with rounded
  corners?"; `coast` and `bevelled`, the plaza's `PlazaSand` too). Each layer is a region of cells with a label (the
  shallows, foam, wet sand and beach each the cells at or inside that band, every one running on under the bands
  inside it, the foam included; the lawn 1 light, 2 dark, its rim of cells next to anything else always dark), and a
  cell is four quarters (`quarters`): where both sides of a corner border another label the half at that corner takes
  it, a higher label filling a notch, a lower one cutting a square corner only where no notch beside it is filled (so
  the edge never zigzags). Whole cells are merged into boxes as before (`greedy`: by rows or by columns, whichever
  makes fewer); a half cell is a `WedgePart` lying on its side (`flat`: its triangle flat, the prism's length upright
  and as deep as the layer, the same name, colour and `PixelWater` kind as the layer's boxes), a run of half cells
  along a diagonal one big wedge where the cells it also covers are the layer's own in that label, a lone quarter two
  half-stud wedges. Coplanar parts of different colours never overlap (the lawn's tones split a cell between them).
  Collision is as it was: a filled notch never collides, a cell still wholly covered does (two wedges), and a cut cell
  of a solid layer keeps an invisible part where it stood (in `Bounds`, named as its layer). Parts at tiers 1, 5 and 10:
  462, 1046 and 1517 before, about 660, 1540 and 2280 after (the island model, its props included). The palms
  (`palm`, and `emptyLot`'s and `ends`') have one smooth trunk (`palmTrunk`: six round `Trunk` segments along a curve
  from the foot into the crown, a `Trunk` ball at each joint as wide as the segment below, the two woods in turn,
  widths on the 1/8-stud grid and lengths exact so the joints meet); the crown, fronds and coconuts where they were.
- `DecorModels.build(id, at, lvl?) -> Model` (every piece in `Data/Buildings`; `lvl` goes to the builder: a level
  kept from an older save, the tree's stage, or a water tile's neighbour mask plus 1; `at`: the footprint's centre on
  the grass, turned; each building with its doors, windows, ridged roofs with eaves and its own props (crates, barrels,
  sacks, pots, fences, lamps); a pennant (`PennantPole`, red at lvl 2, gold at 3) and a lamp at Lv 3, only on a
  building (never on the tree, a path, a water tile or a fence, whose `lvl` means something else or nothing); the
  pier's pond and the fountain's water `PixelWater` 2; parts don't collide; `Blocks.windy`), `has`. It holds the
  builders of the old pieces and the tree (64) and takes the rest from the catalog's model modules below, by id (a
  builder of its own wins). The homes (Tent .. Manor) went with the villagers. `tube(m, f, pts, dia, color, name,
  cap?)`: a round trunk or strand through points, a cylinder between each two and a ball at each joint as wide as the
  segment below (widths on the 1/8-stud grid, lengths exact, so it bends with no gap or step); the Palm Tree's trunk is
  one (`palmTrunk`, as StreetModels' palms). The Tree of Life
  (`tree`, 8 x 8; GAME_DESIGN 6 has the references it was drawn after): an `EggLawn` (7.8 studs across: its eggs lie
  on it), a `Lawn` and `Moss`; a ring of standing `Stone`s (`StoneMoss` caps, a Neon `Glyph` on some, a gap at the
  front); `Root`s in eight directions; a `Trunk` core (one cylinder from the ground, a ball on top) and three
  braided `Strand`s (each a `tube`: upright from the ground, then round segments along a twist round the core, a ball
  at each joint and on its top, the two woods in turn; nothing below the ground, so the model's box is as it was),
  Neon `Rune`s up it; the
  `Hollow` at the front with its glowing `Pod` (Neon), a `Lintel` and two `Jamb`s; `Branch` limbs forking out to the
  leaf clouds (`Leaves`, `LeavesUnder`), each with `Blossom`, a `Vine` and `VineTip` hanging and Neon gold `Fruit`
  under it; a `Ring` of gold Neon dashes on the ground, `Mote`s, mushrooms (`Stalk`, `Cap`) and `Flower`s; the
  ground, the stones and the roots inside the inner 6 x 6, the eggs' lawn round them. Its stage (`lvl` 1 .. 4,
  `Tree.stage`) scales it above that ground: the trunk's girth, the limbs' and the ring of clouds' height, the top
  cloud's height (12.2 studs x 1, 1.18, 1.36, 1.55), the crown's spread and each cloud's size; more `Rune`s, lit
  `Glyph`s, `Blossom` and `Mote`s; `Lantern`s (Neon) from stage 2; eight ring clouds, four more above them and three
  `Fruit` a cloud from stage 3; at stage 4 blossom on every cloud, a `Halo` of gold Neon over the crown, gold caps on
  the stones and a second ring of light; no Lv 3 pennant (its `lvl` is a stage). `DecorModels.HOLLOW` (the hollow's
  foot in the model's frame: where a hatchling steps out when its egg's place is unknown, `EggView.hatchPoint`) and
  `DecorModels.EGG_RING` (3.45: the studs from its middle to the eggs' circle, `EggView`).
- The build catalog's model modules (GAME_DESIGN 4), each a table of builders `(m, f, lvl)` by piece id (`f` the
  footprint's centre on the grass, turned; +Z faces the view before the turn), merged into `DecorModels`:
  `GroundModels` (the 18 new paths: each tile covers its square or keeps the same gap at every edge, so tiles side by
  side join with no seam, its small things moved about by `Parts.hash` so a long run never repeats, at most 8 parts a
  tile; and the 7 waters: `lvl` - 1 is the tile's neighbour mask (north 1, east 2, south 4, west 8,
  `PlotService.waterMasks`), the water over the whole tile, a bank only along the sides with no water next to it and
  a block rounding the corner where two banks meet), `FenceModels` (the 17 fences: one length along X from -1 to +1
  at z = 0 with a post at each end that the next length shares, within about 0.35 of its line and at most 8 parts; six
  of the bridges, along Z, landing on the grass at z -3 and +3 (the Canal Bridge is DecorModels' own); the 8 pieces for
  the water, floating at its surface), `NatureModels` (33 trees, plants and rocks; the Palm Tree, Round Bush and
  Flower Bed are DecorModels' own; blossom, maple leaves, snow and grass marked to sway as leaves do; no trunk is a
  stack of steps: one column from the ground (on a flat plate of `Root` at most), or a `tube` through its bends (the
  Bare Tree, the Bonsai), as DecorModels' `tube`; nothing reaches lower into the ground than before, since the
  catalog's pictures and the loading card stand a model on its box), `ThemeModels`
  (36 pieces of the beach, garden, farm, harbour, town and jungle rows) and `ThemeMoreModels` (29 of frost, autumn,
  desert, fairy, zen and volcano), each theme in its own colours, its lights Neon so they glow at night, and
  `FunModels` (the 24 seats, lights, play pieces, treats and fountains not modelled before, and the four grand pieces
  of tiers 7 to 10). They build through `Parts` (the same shapes `DecorModels` uses, through `Blocks`: anchored, no
  collision, palette colours, the 0.25-stud grid, never thinner than 0.25, in the piece's frame: `box`, `turned`, `at`,
  `ball`, `cyl`, `log`, `logZ`, `wedge`, `glow` (Neon), `water` (a flat water part with `PixelWater` 2, moving like the
  shallows), `hash(f, k?)` (a number 0 .. 1 from the tile's place)).
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
  (`Wing*` flap, `Tail*` wag, `Eye*` blink...; `flap(t, cf, phase, glide?)`). WorldView and StreetLife call
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
changed), `Fx` (RemoteEvent, S->C `{ kind = "tick", shells, wood, dayFrac, clutchLeft (`p.clutch.left`), clutchSecs
(`Tree.secs`) }` every second, `{ kind = "eggs", laid (`Tree.view`: every egg now, each with its cost), more (0: a
new lot; n: the eggs added when the island grew) }` when the tree lays (the session is marked dirty with it, so the
whole view follows), `{ kind = "hatched", data }` (`egg.hatch`'s data) when an egg is hatched, `{ kind = "turn",
hatched? (the Pals hatched: Breed.turn) }` at each turn's end, `{ kind = "day", day }` at each of the sea's days,
`{ kind = "quest", data }` on a claim; no "tide" or "taken" since the tide went, and none of the old tree's "tree" or
"treegrew"). `Net.serverInit()` creates them; `Net.clientInit()` waits for them.

### 7.2 `Session`
`create(player, profile, plot) -> S` (`{ player, profile, plot, rng, ready, turnClock, dayIndex, tickClock, dirty,
saveAt, reqTimes }`; no `tide` or `tideDirty`: the tree's eggs are the profile's), `get`, `remove`, `all`, `view(s)
-> ClientView` (every driftling, `clutch` from `Tree.view`, `clutchLeft`, `clutchSecs`), `markDirty`, `flush` (sends
State when dirty), `fx(s, msg)`, `allow(s, now)` (the rate limit).

### 7.3 `Router` and the action catalogue
`Router.on(action, fn(s, payload) -> (ok, data|err))`, `Router.onSignal(kind, fn)`, `Router.handle(player, action,
payload) -> Response` (not ready -> `not_ready`; over `Tuning.RateLimitPerSec` -> `rate`; `Validate.request`; the
handler under pcall; success marks the session dirty).

| Action | Payload | Rule | Errors |
|---|---|---|---|
| `plot.place` | `id x z rot` (coords whole studs in [-160, 64], rot a quarter turn) | `Plot.place` (paid in wood), the buildings rebuilt by difference, then `Tree.settle` and `Tree.fillJobs`, the tips | locked, full (its group's limit), huts (the huts' limit), wood, blocked, bad_payload (the tree, an unknown piece) |
| `plot.move` | `i x z rot` | `Plot.move` (the tree too) | blocked, bad_payload |
| `plot.paint` | `id cells` (a path or water piece; "x,z;x,z": 1 .. 40 cells, whole studs in [-160, 64]) | `Plot.paint` (data `{ placed, swapped, skipped }`), the buildings rebuilt | bad_payload, locked, full, wood, blocked |
| `plot.unpaint` | `cells kind` (kind "path", "water" or "all") | `Plot.unpaint` (data `{ removed, floated }`), the buildings rebuilt | not_found |
| `plot.fence` | `id edges` (a fence piece; "x,z,r;...": 1 .. 40 edges, r 0 or 90) | `Plot.fence` (data `{ placed, swapped, skipped }`), the buildings rebuilt | bad_payload, locked, full, wood, blocked |
| `plot.unfence` | `edges` | `Plot.unfence` (data `{ removed }`), the buildings rebuilt | not_found |
| `plot.replace` | `i`, `id` | `Plot.replace` (data `{ i, uid, id }`; the island's pieces rebuilt; a hut for a bigger one at the huts' limit too) | bad_payload (the tree), locked, wood, blocked |
| `plot.store` | `i` | `Plot.store` (clear away; a hut's driftlings left with no hut, then into any hut with room) | fixed (the tree), egg (a Hatchery holding an egg), bad_payload |
| `breed.start` | `uid`, `a`, `b` | `Breed.start` (an egg at the Hatchery `uid` from driftlings `a` and `b`; the feast in shells) | not_found, egg, money, bad_payload |
| `island.expand` | - | `Island.expand` (paid in wood), `Tree.fill` (the bigger island's extra eggs, Fx eggs with `more`), the island rebuilt (data `{ tier, moved, cleared }`) | max, wood |
| `pal.work` | `id uid` (0: rest) | `Island.setHelp` | not_found, bad_payload |
| `pal.house` | `id uid swap` (swap 0: none) | `Tree.house` | not_found, bad_payload, full |
| `pal.sell` | `id` | `Tree.sell` (data `{ shells, sold }`) | not_found |
| `egg.hatch` | `id swap` (an egg id under the tree; swap 0: none, else a hut driftling sold to make room) | `Tree.hatch`, the tips, Fx hatched (data `{ id, sp, muts, egg, r, hr, cost, sold, swapped }`) | not_found (a new lot replaced it), no_hut, money, full (every hut full and no swap: the client opens the swap picker), bad_payload |
| `founder.set` | `skin hair style shirt` | `Island.setFounder` (the `Founder` attribute follows on the next sync) | bad_payload |
| `settings.set` | `k` ("pixel" or "music"), `v` | the pixel tier (high, medium, low, off) or the music (on, off) | bad_payload |
| `tut.next` | - | the tips go away for good | - |
| `quest.claim` | - | `Quest.claim` (data `{ id, shells, wood, next }`) | not_found, not_done |
| `char.home` | - | PlotService puts the founder on their path | cooldown (`Tuning.HomeCooldown`), not_ready |

The building actions and `island.expand` still check shells (`money`) for a price in shells, which no piece or tier
has now. The expedition actions (`exp.*`, `pouch.upgrade`) and `pal.release` are gone (2026-11-12), the villagers'
`folk.work` and `folk.dismiss` with them later that day, the tree's `pen.sell`, `pen.best` and `tree.upgrade` on
2026-11-13, and the tide's `tide.take` later that day: `Validate` answers them `unknown_action`.

### 7.4 `IslandService`
Registers the actions above (the building ones, `plot.fence` and `plot.unfence` among them, through `rebuilt`).
`step(dt)` (Main's fixed 10 Hz step), for every ready session: `Island.step` (wood and shells), `Tree.step(p, dt,
s.rng)` (a new lot when its time comes: the session marked dirty and Fx "eggs" with `more` 0), a turn every
`TurnSeconds` (`Breed.turn`: Fx "turn"), a day each time the sea's clock passes a day's end (`WorldClock.dayIndex` past
the session's `dayIndex`: `Island.newDay`, Fx "day"), the stores every second (Fx "tick" with `WorldClock.dayFrac`,
`clutchLeft` and `clutchSecs`: the whole view is not sent for them). `WorldClock` (server): the sea's clock, `os.time()`
at start advanced by every step (`now`, `advance`, `shift(seconds)` for the sims and previews, `dayIndex`, `dayFrac`); a
day is `Tuning.DaySeconds` (4 hours). The tips (`tips(s)`, `TIP_KIND`): 1 moves on when a wood building stands, 2 a
farm, 3 a hut, 4 when an egg has hatched (`stats.taken` above 0 or any driftling), 5 a shop, 6 on OK (`tut.next`); a
step whose task is already done moves on at once, several in a row if need be (an older save). Every building change
(`rebuilt`) runs `Tree.settle` and `Tree.fillJobs` before the island's models are rebuilt; `egg.hatch` runs the tips and
sends Fx "hatched"; `island.expand` runs `Tree.fill` and, when it laid any, sends Fx "eggs" with `more` the count.
Nothing happens while the player is away: the tree's clock runs only in a ready session.

### 7.5 `PlotService` (the sea)
`init()` registers the collision groups `Bounds` (the invisible seabed, shelves and world walls) and `PixelRays` (the
pixel filter's rays), not colliding with each other, and builds the whole sea: `Workspace.Plots.Street` (every plot's
water and seabed, `Road_<i>`, and the sea's ends) and open
water on every plot (`Plot_<i>.Static.Land` = `EmptyLot`, attribute `Owner` 0). `claim(player) -> plot` (the lowest
free index, 0 when the sea is full: Main kicks), `release(i)` (back to open water, every attribute cleared).
`build(s)`: `Plot_<i>` gets `Owner`, `OwnerName`, `StudioName` ("Name's Isle"); its `Static` gets
`Land` for the island's tier (rebuilt only when `Static`'s `Built` attribute differs: the island for that tier built
ahead is swapped in when it is ready, else it is built there and then) and `Decor` by difference
(`buildDecor(s)`: one model a piece, named `uid:id:x:z:rot:lvl`; models whose key is unchanged stay; the Tree of
Life's `lvl` is its stage, `Tree.stage(tier)`, so a new stage builds it again; a water tile's is 1 plus its neighbour
mask, `waterMasks(placed) -> { [Street.cellKey(x, z)]: number }` (a bit for each side with a water tile next to it on
the even grid: north 1, east 2, south 4, west 8), so a tile is built again when water is dug or taken up beside it),
then `sync(s)`: the attributes `Tier`,
`Day`, `Charm`, `Pals` (the hut driftlings, `;`-separated `id.species.work.home`; one with no hut is left out until
it moves in; no `Folk` since the villagers went), `Eggs` (the tree's eggs, `;`-separated `id.rarity`, in the order
they were laid: every client draws every island's, `Controllers/EggView`; no `Tide` or `syncTide` since the tide
went), and the player's `Founder` (`skin.hair.style.shirt`) and `Plot` (Main syncs every dirty session before sending
its view; only changed values replicate). A player leaving clears every attribute, `Eggs` with them, so their eggs
go from every client. The founder: `watchCharacters(player)`,
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
`AvatarView.start`, `StreetLife.start`, `AmbientView.start`, `Hud.start` (which starts `Menus`), then the card's phase
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
the sand round the fire (no path or jetty since 2026-11-13). `buildAtlas()` decodes `LoadingArt` into one atlas EditableImage (the run-length
format of `gen_loading_art.py`), `placeScene(L)` lays the actors (ImageLabels on the atlas, `ImageRectOffset` per
frame, whole UI px, ZIndex by their foot's row) and `step(dt)` moves them at most `SCENE_FPS` (24) times a second
from the card's one Heartbeat: stills (the Tree of Life, `tree`, at the back in the middle, or at the back on the left
when its crown, `TREE_TOP` (77) art px over its foot, would reach the bar; a "blink" still: its second frame, the
hollow, fruit and marks dimmer, for a fifth of a second every 4.2 s; a tall palm, `palm_b`, stood there while the tide
ran and now stands on the right); the
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
`burrow`, `torch`, `flowers`, `bush`, `tree` (65 x 85, two frames: lit and dimmer), `boat`, and the hand-made `gull`, `star`, `crest`, `ember`, `glint`.

### 8.1 `StateClient`
`init`, `view() -> ClientView?`, `waitView`, `Changed: Signal<ClientView>`, `Fx: Signal<msg>`, `Tick:
Signal<ClientView>` (Fx "tick": the view's `shells`, `wood`, `dayFrac`, `clutchLeft` and `clutchSecs` are patched in
place after a check (numbers, not NaN), no whole view comes), `clutchLeft() -> (left, secs)` (the seconds till the
tree's next lot, the server's last word (a tick or a view) run down by the client's clock, and the seconds between two
lots), `request(action, payload) -> Response` (never errors), `signal(kind, payload)`. (No `TideChanged`, `tideNow`
or `along` since the tide went; `treeFrac` went with the old tree.)

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
(`DoorChime`; nothing plays it since the villagers went), `grow` (the island grows, or the tree lays an epic or legendary egg: `BellTreeRun`), `friend`
(a Hatchery's egg hatched: `ChimeCluster`), `level_up` (a piece replaced: `SparkleTones`), `reward` (a quest claimed:
`Triangle`), `egg` (`MusicBoxWind`), `rare` (a new lot of eggs, or one rare or better hatched: `SparklePass`; a common or uncommon one hatched plays `pop`); the founder's feet (AvatarView):
`step_grass step_sand step_wood` (two or three takes each, `ids`), `step_water` (wading through a river: `Pop`
pitched low), `jump`, `land`; putting a piece down in Build mode (`Controllers/BuildFx`, by its `feel`, cut from
the clips above): `place_wood` (the hammer's taps), `place_stone` (`CoinsMany`, pebbles, low), `place_plant`
(`StepGrass` takes), `place_water` (`Pop`), `place_metal` (`Notice`'s clinks, high), `place_magic` (`Sparkle`),
`place_sand` and `place_snow` (`StepSand` takes, the snow higher), `place_cloth` (`Hop`, a cloth flap) and
`place_fire` (`Combo`, a shaker, low); the world's `hammer gull birds` (nothing plays `hammer` since `place_wood` took
its clip); the fights' sounds and their ids went on 2026-11-12), each one `Monetization.Sounds` id (0 =
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
toon bands and the palette LUT (the indoor tint inside the room) with each material's surface texture (9.3), then the
ink outline (`Shading.outline`) and the contact shade at the foot of upright faces. The **dynamic layer** is the islanders (the hut driftlings and the visitors), the tree's eggs and the founders: every tick (the tier's Hz) their parts
are drawn analytically with `Raster.drawPart` and the same orthographic camera, depth-tested against the static
layer and outlined; only the old and new dirty rects are restored and uploaded. The **effect layers** (9.3,
`Render/Fx`) draw over both every tick: 2D sprites and pixels in the world (the islands' small lives,
`AmbientView`), depth-tested, colour only. Without EditableImages (or with Classic picked) the layer hides and the
Roblox camera shows the 3D world.

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
(and the tips banner), on any island or swimming in the sea; the pan glides `CamGlide` of the way a frame, never more a frame
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
**Stage mode** (the hatch scene's, `UI/HatchScene`): `setStage(Stage?)` with `Stage = { name, origin, pts, tight?, top, bottom, clear? }` fits the
stage's points (`tight` instead on a screen under 600 px tall: a phone held sideways, the action's band drawn at a
bigger scale) full screen clear of the play overlay's top and bottom strips (art px), the ray plane at the stage's origin,
the key `stage:<name>|...`, no indoor room; the view holds still (`view().stage` true; `view().clear` when the stage's
sky is see-through, `Stage.clear`: the renderer leaves what its rays miss empty); `setStage(nil)` goes back
to the street; `stage()`. `setStageShift(shift, snap?)`: an endless islet's camera, the stage's framing moved by
`shift` studs (the target is the home pan plus the shift's grid px); on a stage the view glides, so the renderer
scrolls to the next area and never re-bakes (reset by `setStage`); `snap` puts it there at once (behind the curtain,
before the first picture: only the boat arrival, unused now, asked for it).

### 9.3 `PixelRenderer`
`init`, `start`, `setTier(t)`, `tier`, `isActive`, `unavailableReason`, `pixelScale` (K), `firstPicture() -> (shown,
progress)`, `registerDynamic(model)`, `unregisterDynamic`, `refreshDynamic`, `rebake`, `setPaused`,
On a view with `clear` the pixels its rays miss are 0 (alpha 0) and the grade and dim pass them by, so a picture behind
the layer shows round the stage (`UI/HatchBackdrop`, a ScreenGui at `PixelDisplayOrder` - 2, its sky life at - 1).
`watchStage(root)` (unused now: a stage's static parts that come or go while it is in view re-cast their rects; a rect over one
already queued joins it while their box is no bigger than the two apart, so an endless islet's area landing in view,
hundreds of boxes, re-casts its union once instead of re-baking the whole picture over their overlaps),
`afterBake(fn)` (fn runs once the picture shows the world as it is now: after the pending or running bake, at once
when none is coming or the filter is off; Build mode's expansion cheers then), `project(world) -> (Vector2 full-screen px, on)`, `projectPixel(world) -> (i, j, on)`, `pixelAt(pos) -> (i, j)` (the
art pixel under an InputObject's Position, as `projectPixel` gives them), `screenRay(pos) -> (origin,
direction * length)` (pos = an InputObject's Position: the pick ray through what the layer shows), `debugStatic()`
(CLI checks: layer, pan, bakes, ticks, `scrolls`, `scrollRays`, `recasts`, `queued`), `Changed: Signal<PixelTier>`,
`addFxLayer(name, draw) -> remove` and `fxStats()` (below).
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
- **Water**: a part with a `PixelWater` attribute (1 the sea, 2 the shallows, and the ponds, fountains and the rivers
  drawn on the island through `Parts.water`, 3 the foam, and a waterfall's white water) marks its pixels in the bake
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
- **Surface textures** (GAME_DESIGN 2: "textured objects", "wood detail"; Random Bakery's material texture, widened):
  a static pixel of a textured colour may be shaded a band darker or lighter on its own ramp (`Shading.toonAt`'s
  `lift`) as it is shaded at bake time (`shadeAt`: the bake, a pan's strips, a re-cast, `refineShadows`), so it costs
  no ray. `Shading.texKind(rgb)` names the kind from the palette (`TEX_WOOD`: wood, wood_dark, bamboo, desk;
  `TEX_METAL`: steel, steel_dark; `TEX_GLASS`: window; `TEX_GRASS`: grass, grass_dark, moss, leaf, leaf_dark, swamp;
  `TEX_SAND`: sand, sand_dark; `TEX_STONE`: rock, rock_dark, slate, basalt, pavement; `TEX_THATCH`: straw;
  `TEX_BRICK`: brick; clay stays plain: here it is pots, jars, tent stripes and roof tiles). The first time the bake
  meets a part (`castSample`) it works out its `TexInfo` once (`texInfoOf`): the kind, its colour, its screen box in
  global art px (its centre's `Raster.gridPoint` and its box's projected half extents, from one `GetComponents`: the
  same at every pan), how its long axis runs on screen (`fam`: 1 upright, 2 level, 3 and 4 the two 2:1 slopes) and a
  `seed` from where it stands (never its id: a fresh bake numbers the parts afresh). `NO_TEX` for a part with none: a
  plain colour, a glowing one, water (`PixelWater` 1 to 3: animated on its own), a round brick thing, or one too small
  on screen for its pattern to read (`TEX_MIN`, e.g. 6 x 4 art px for wood, 8 x 5 for grass). The table (`texs`) lives
  with the other id tables (`staticIds`, `albedos`, `waters`): a bake behind the picture has its own
  (`backTabs.texs`), a stage's stash keeps the street's, and a new id clears its entry. `texLift` picks the pattern:
  `Shading.grassMark` (faces whose normal's y is 0.7 or more only), `sandMark`, `stoneMark`, `thatchMark` (faces whose
  normal's y is under 0.9 only: a roof's slope, a bale's side, never a slab of sandstone path), `grain(fam, seed, gx,
  gy)`, `mortar(courseFam, gx, gy)` (`Shading.courseFam` of the face's normal and the view's rotation, cached per
  normal index; none on faces that look up or down), `streak` and `glass` (from the part's box). A lighter mark shows
  only on a face in full sun (`Shading.band` 1: it turns that pixel `SUNLIT`), a darker one wherever a darker band is
  left, so in a shadow the texture fades into the shade like the rest of the face. A pixel tinted by glass in front
  shows none. The grid patterns are hashed from the global art pixel (`Shading.texHash`) in cells, at most one mark a
  cell and never on a cell's last row or column, so marks never touch into a blob. The blob shadows and the contact
  shade draw a pixel's shadow tone as before (a darker mark at the shade band is the shade band). The dynamic layer
  has none: a pattern on the screen's grid would slide over a model as it moves.
- **Effects** (`addFxLayer(name, draw: (Fx.Ctx) -> ()) -> () -> ()`; `Render/Fx`; the request of 2026-11-13: "use 2d
  details to add to the athmosphere, such as grass, wood detail, birds and other details"): each tick, after the
  dynamic models and their outline and before the upload, every layer (the newest first) gets a `Fx.Ctx` over the
  frame: the frame (colour, depth, ids), its camera, the static buffers (`sColor`, `sId`, `sNormal`, `sAlbedo`,
  `sDepth`, `sWClass`), art px per stud (`ppu`), `ver` (`staticVer`, bumped by `staticChanged()` at every bake's end,
  scroll step, finished re-cast, stash return and new layer: what a layer works out from the static picture may be
  kept until it changes), `now`, `dt` (clamped to 0.25), `idOf(part)` and its book of written pixels. Effects write
  colour only (`Fx.put`; a light's pixel also writes `Fx.GLOW_ID`, 65535, which `isGlow` treats as Neon, so the
  night's grade keeps its colour). Two books swap every tick: last tick's pixels go back to the static picture
  (`fxRestore`, colour and id) before the dynamic layer is drawn. `fxShown` (u32 a pixel) holds the effect colour the
  image shows there, its top byte the tick's mark (1 or 2): a pixel written this tick in a new colour, or one last
  tick's effects left, marks its 16 x 8 tile (`FX_TW`, `FX_TH`); the tiles go up in runs along their rows (a gap of one
  tile joins two; over `FX_MAX_RUNS` (40) runs, one rect a row of tiles), so an effect at rest costs no upload.
  **Sticky** pixels (`ctx.stick(i, c)` / `ctx.unstick(i)`, through `Fx.stickSprite` / `Fx.unstick`): things that stay
  put on the picture (the lawn's tufts and flowers) are kept in `stickCol` (u32 a pixel) and `stickList` and put back
  over the static picture wherever the frame takes it back (`restoreRect`, `fxRestore`, a full compose's copy), so they
  are drawn once and again only when they change; their changes mark their tiles; `staticChanged()` drops them all
  (every caller uploads the whole picture), as does removing a layer. A layer that errors is removed with a warning.
  They run inside `compose`: paused with the renderer, at its tier's rate, never in the classic style.
  `fxStats() -> { ms, bookMs, px, changed, rects, upPx, ticks, layers }` (the last tick's: the layers' ms, the books'
  ms, pixels written, changed, the rects and pixels uploaded).
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

### 10.2 `WorldView` and `EggView`
The islanders: a walker per hut driftling (`MicroModels.driftling` in its species' shape and colours), parsed from
each owned plot's `Pals` attribute and placed among the buildings read from its `Static.Decor` models' names
(`uid:id:x:z:rot:lvl`). A driftling goes to the building it works at (or its hut) and works there by its kind
(`palMoodOf`: `dip` at a pier or kelp farm, `peck` at the other farms, `push` at the wood and the boosts, `wave` at the
shops, `nap` at a hut or the hatchery, for longer: `DriftModels.animate`'s work moods), now and then a stroll
(`strollPoint`: a buildable cell away from the campfire). One new in a hut on an island already peopled has just
hatched: it steps out where its egg lay (`EggView.hatchPoint`) with a cheer and walks off to work (`born`). Workers
stand along the building's front, turned three-quarters to the view (east or south). Only islands within 100 studs of
the view's centre are drawn (synced every half second); each near owned island's campfire gets a flickering flame and
rising smoke (`fireOn`, dynamic models). Each island's sign gets a World-root label (its name, the own in gold, or
"Unclaimed isle"); a tap (`onTap`: a press let go within 8 px, not on the interface, not in Build mode) goes to
`EggView.tapAt` first (an egg under the own tree: the tree panel); otherwise its ray (`PixelRenderer.screenRay` in the
`PixelRays` collision group, as the picture's, so it passes the invisible seabed, shelves and world walls, which Roblox hits whatever
their CanQuery says because they collide) on a Tree of Life (`treeOf`: a model with the `Decor` attribute "tree")
opens the "tree" panel for the own one, or for a neighbour's says "Someone else's Tree of Life. Yours is on your own
island."; on a sign it shows `signCard(i)` (the day, driftlings at home, charm). Fx "hatched" (`hatchedOne`) bursts
bits of the hatchling's rarity's colour at `EggView.hatchPoint`, a rare or better one's name floating up; a
Hatchery's hatchling (Fx "turn" `hatched`) gets its name and pink bits over the Hatchery; `cheer(words, color)` makes
the own islanders cheer. Its Heartbeat runs `EggView.step` with the view's centre (world x). `rigCount()` /
`ownRigCount()` / `ownCount()` (the walkers drawn: all, the own island's) and `tapScreen(pos)` (a tap at screen px,
handled as a player's) for the sims. (No `TideView.ashore`; the old tree's label `updateTreeLabel` and `grownOne`
stay gone.)
`EggView` (client, GAME_DESIGN 6): every island's eggs from its plot's `Eggs` attribute (`id.rarity`; the islands
within `NEAR` (100) studs of the view's centre, synced every half second) round its tree, found from the tree's decor
model name (`uid:tree:x:z:rot:lvl`). Each egg is a `TreeEgg` model (`Models/EggModels.build(r)`, shared with the hatch
scene) in `Workspace.PixelDynamic` (registered with the renderer): a bed of straw, three `Shell` balls (the upper one
`Top`, its top half) and its marks, by `LOOK[r]` (`EggModels.LOOK`, also `EggView.LOOK`)
(GAME_DESIGN 6: "color each egg differently with different effects"; `{ body, mark, marks, glow, lawn? }`: common
`cream` with `sand_dark` spots, uncommon `green` with a `white` band, rare `blue` with `white` spots, epic `purple`
with `pink` spots, legendary `gold` with a `yellow` band; "spots" six dabs on the side facing the view, "band" twelve
dabs a little up and down in turn round its middle; the marks Neon from rare up, so a light pool at night); the epic and
legendary a thin Neon disc of `lawn` colour on the grass under it; the legendary also a Neon yellow band of light round
its middle and a `Beam` standing up out of its top, the epic two Neon `Mote`s (pink, white). The motes and the beam
are the egg's `fx`, moved every frame (`stepEgg`: the motes circle and bob, the beam breathes 2.2 +- 0.5 studs tall,
both put under the lawn while the egg sinks or cracks). `SIZE[r]` (1.25 .. 1.62) a rarer one bigger. Its sparks
(`stepSparks`, 2D on the World canvas at whole UI px): every `EVERY[r]` seconds or so (none, 0.8, 0.42, 0.26, 0.14)
an egg lying still (risen, not sinking or cracking) sends one up: an uncommon a green 1 px leaf drifting up, a rare a
`twinkle_1`/`twinkle_2` star blinking round it, an epic pink and white 1 px sparks rising, a legendary gold and white
ones and now and then a `spark_1..3` star; at most `SPARKS` (140) at once, none with the pixel filter off, each gone
with its egg. Slot k of a lot of n lies on the
lawn at `DecorModels.EGG_RING` from the tree's middle, spread evenly over the arc from `ARC0` (-62°) to `ARC1` (152°)
(the south and east, the side the view looks at); a lot keeps its slots while it lasts (an egg's slot its place in
the lot's order from its first id, `lotFirst`, or, when that slot is taken or past the ring, the first free one: an
expansion's extra eggs after a hatch never land on another egg's spot), the ring as many slots as `Tuning.EggCount`
by the island's tier. A
whole new lot (every egg gone at once and new ones in) rises out of the lawn (`RISE` 0.6 s, `STAGGER` 0.12 s apart,
from `DEEP` 1.4 studs under) while the old eggs sink (`SINK` 0.5 s); one gone while the rest stay, or one the own
player just hatched, cracks (`CRACK` 0.9 s: a shake, then `Top` flies off turning and the rest sinks); every egg rocks
for a moment every 7 s. No price tags or names over them (the request of 2026-11-13: "remove these, the eggs should be
buyable only after the player clicks on the tree or enters the tree menu"). On tip 4 the `arrow_down_t` bobs over the
own tree (unless a panel or the hatch scene is open). `hatch(id, swap?)` (sends `egg.hatch`; done, the panel shuts and
`HatchScene.play({ sp, muts, r, hr }, after)` runs; `after` opens the tree panel again if Hatch was pressed there and
says "It hatched a rare Wispwing." in its rarity's colour, with what a swap sold for; the egg's place kept as the
island's hatch point; `full` opens the tree panel's swap picker `{ hatch = id }`; other refusals in words), `best(v, n) -> { Laid }` (the view's eggs, the rarest first, then the lower id; when the shells cover none of
the best n, the best one they cover takes the last place: the HUD's card and the tree panel), `tapAt(pos) -> boolean`
(a tap at an InputObject's position, below the top bar, so the inset is added back: when it lands on one of the own
island's eggs, risen and not leaving, the "tree" panel opens; nothing is bought; true when it hit one), `step(t,
focusX)` (WorldView's Heartbeat: the near islands synced, every egg moved, the tips' arrow kept), `count(plot?) -> number`
(the eggs drawn, not counting ones sinking or cracking: the sims and previews), `where(plot, id) -> Vector3?` (an
egg's foot now, world; nil when not drawn), `hatchPoint(i) -> (x, z)` (where island i's last hatched egg lay; else in
front of the tree's hollow, `DecorModels.HOLLOW`; else the plaza's south edge).
`StreetLife` (client, started after AvatarView): four boats (`MicroModels` "ship" at BoatSpec levels 1, 2, 1, 3, blob shadows; nothing
in them collides, so a swimmer passes through) crossing both ways on two lanes out at sea (`Street.SEA.z0` + 17 and + 23), rocking on the swell in whole steps, wrapping round the sea's ends; a flock of three
gulls crossing every 14-24 s, each crossing its own (east or west, a slant, a height, a weave, each gull a little
behind the next), every gull turned the way it flies (the model's head is +Z) and gliding now and then (no clouds'
shadows: the player asked for them gone). `count()` for the CLI.
`AmbientView` (client, started after StreetLife; GAME_DESIGN 8.1): the islands' small lives, one effect layer
("ambient", `PixelRenderer.addFxLayer`) drawn with `Render/Fx` and UI/ArtData's `fx_` sprites (`Fx.define`: the frames
`fx_<group>_1..n`; a group's small sprites `fx_<group>s_*` where the island shows small, `ppu` under `BIG_PPU` 7).
Every claimed plot whose island's box (its cells and shallows, `Street.cellBounds`) lies on the layer gets an `Isle`
(made when it comes into view, let go `ISLE_KEEP` 10 s after it leaves; looked at every `ISLE_EVERY` 0.5 s): its cells
by the tier's shape (`buildLand`: tufts sown in patches, `Fx.patch(x, z) * 0.4` a grass cell, kept in 8-stud
chunks culled to the screen; little flowers in clusters, 2.5 % of the cells; the dry beach; water cells 0.8 to 11 studs
past the foam), and what its models hold (`scan`, again 0.6 s after a piece comes or goes in its `Static.Decor`: the
highest `Post`, `Rail` or `Top` of each fence, each `Ridge`, flat `Roof` and the sign's `Top` to perch on; `Flower`,
`Bloom`, `Blossom`, `Petals`, `FlowerHeart` parts for the butterflies; `Leaves`, `Blossom` and `Leaf` parts a stud or
more across, their colour, a blossom or a pale pink one dropping petals; `Chimney`, `Smoke`, `Coals` (and the
smokehouse's `Vent`) smoking, `Steam`, `Teapot`, `Mug` steaming; the cells the pieces cover, so no bird stands in a
building). A tick (`draw`, nothing while `CameraController.view().stage`): `stepLife` (the birds, the butterflies,
leaves, wisps, a fish, fireflies), then the tufts and flowers (`drawDecos`: once per `ver`, whether the lawn itself
shows at the tuft's foot (an up-facing static pixel at its depth whose albedo is the grass or the dark grass) and the
lawn's tones there (`Fx.tones` of the static colour); stuck with `Fx.stickSprite` in the frame of the gust passing
(`Fx.gust`, `Fx.swayFrame`) and stuck again only when that frame changes; a lower tier keeps a share), the sea's
glints (a few a second on random sea or shallows pixels, by `sWClass`; fewer at night), splash rings, the fish, the
particles (`Fx.step`: drops, wisps, leaves), the birds and the butterflies, the fireflies last. Birds (`stepBird`;
4 an island at high, 3 medium, 2 low, pips and wrens in turn, and a gull): away, then in (flown in from one side of
the screen over 1.6 s, a gull from the sea over 2.4 s) to a perch picked on screen round its middle (an ellipse
0.24 x 0.3 of the screen, a gull's 0.3 x 0.36: never under the HUD's cards), nobody within 3.5 studs (a gull 5) and no
other bird on it (`pickPerch`: a rail, ridge or the sign 45 %, else a lawn cell, sometimes the beach; a gull the beach
only), perched (pecks, hops along the perch, looks round, 20 to 70 s, a gull 12 to 30), then off (`flee`: away from
whoever came near, or when bored; at dusk) and away 6 to 16 s (a gull 25 to 60). Who walks: every player's character
and the models in `Workspace.PixelDynamic` on the lawn (`PixelGroundY` the lawn's: the driftlings), every
`RIGS_EVERY` 0.15 s. Butterflies (3 an island at high) by day (`DayLight.frac` 0.06 to 0.68) between the flowers,
resting on one now and then; fireflies (22 at high) at night (0.78 to 0.97) over the lawn's spots; birds by day (0.03
to 0.72). Fish: an island on screen every 9 to 22 s (divided by the tier's scale), a jump of 1.7 studs along the shore
from a water cell round the screen's middle. Reduced motion (`GuiService.ReducedMotionEnabled`): no particles, flights
or sway. `stats()` (what is alive and drawn, and the last tick's parts in ms: `msLife`, `msDecos`, `msParticles`,
`msCreatures`), `birds(plot)` (`{ sp, state, x, y, z, on }`), `debugRun(on)` (the sims: the lives stepped on
Heartbeat with the view's own camera while no picture is drawn), `debugHurry()` (every bird, gull, fish and leaf due
now), `setSuspended(on)` (a timing's A/B).

### 10.3 `Hud`
The island's looks (GAME_DESIGN 2): the chips are carved boards in thin frames of planks (`CHIP_Y` 5), the cards in
thick ones with their names on planks (`CARD_Y` = `TOP_H` + 15, 7 px in from the right), the menu bar stands on a
`Dock` (a dark board in a thin frame, `DOCK` 6 px round the buttons); the camera's strips are kept clear of all of it.
Chips (`Chip_wood`, `Chip_shells`, each an 11 px icon and the store easing to its value, flashing when it changes; no
food chip since 2026-11-13; `Chip_day`, "Day 3" with the day's clock along its edge and a sun that sets into a moon;
then `Home`, a button shown while the founder is off their own island, sending `char.home`; `MusicToggle` in the top
right corner, the `mini_note`, sending `settings.set` music on / off, the note greyed while off), the menu bar
(`Menu_build`, `Menu_pals`, `Menu_index`, `Menu_looks`, each with its icon; while Build mode is open the bar and the
cards step aside and the tips banner sits on the tray (`BuildUI.trayHeight()`: lower while a piece is picked) with a
Build mode wording (`TIPS_BUILD`)), the `IslandCard`
on the right (the island's name for its tier, driftlings in huts / the huts' room (`Pals`), visitors, charm, and what
a turn makes of wood and shells a minute, `Rate_wood` and `Rate_shell`: `Numbers.perMin`), the `TreeCard` under it
(GAME_DESIGN 6: the `mini_tree`, "Tree of Life" ("Eggs" on a phone) and `TreeOpen` opening the "tree" panel,
`TreeNext` ("New eggs in 2:41") over `TreeBar` (an ink bar whose fill Heartbeat runs down from
`StateClient.clutchLeft`), then a row each of `EggView.best(v, 3)` (on a phone `best(v, 1)`): `EggIcon_<id>` (the
`egg_<rarity>` sprite), `EggName_<id>` (the rarity's name in its colour) and `CardPrice_<id>` (its cost, a label with
`PriceIcon`, `good` when the shells are there, else `text_dim`), or "No eggs right now", and over the rows the
see-through `TreeCardTap` opening the "tree" panel (the card buys nothing itself); built again from each
view only when the rows' ids, costs, whether the shells cover them or the number of eggs change (its `Key`
attribute); on a phone the card at the top left; hidden in Build mode and while the "tree" panel is open), the questline's card `Quest` (GAME_DESIGN 9: down the left at `CARD_Y`, `QUEST_W`
150, under the `TreeCard` on a phone; hidden while the tips are on and for a panel; `updateQuest(v)` from the view
through `Quest.current` / `Quest.progress`, laid out again when the quest or its count changes, sliding in: the
quest's `mini_` icon, `Title`, `Which` ("3/20"), `Words`, then the `Bar` and `Progress` with `QuestGo` (`goTo(go)`: a
panel, "tree" included, or `BuildUI.open(tab)`), or once done the reward (`Reward_<store>`, wood then shells) and
`QuestClaim` (shining; `quest.claim`, then a notice of what it paid)), the tips banner (`Tips`: the steps of
GAME_DESIGN 9 (`tut` 1 .. 6: a Lumber Camp, a farm, a hut, an egg hatched, a Snack Stall, the last; Build
mode's own words for 1, 2, 3 and 5); tip 6 has `TipsOk`, sending `tut.next`; a parchment note in a thin frame; on a
phone it keeps to the room left of the island card, wrapping to two lines), and the `DayBanner` (Fx "day" and "turn":
the day, what hatched; over a panel or in Build mode a notice instead); Fx "eggs" (`onEggs`): "The Tree of Life laid new eggs." (with `more`, "The tree laid 2 more eggs.") and the `rare`
sound, or, with an epic or legendary egg among them, "An epic egg is waiting under the tree." in its rarity's colour,
the `grow` sound and a burst over the `TreeCard`. Shells coming in rise from their chip
("+12", at most every 2 s, from `StateClient.Tick`). Every frame it holds the founder's `JumpHeight` at 0 while Build
mode or a panel is up, else `Tuning.JumpHeight` (the phone's jump button hides with it), and sets the music's mood
(`Audio.music`). It reports its blocks to the camera (on PC the top strip, the menu bar and the card's place; on a
phone Roblox's top bar and the menu bar).

### 10.4 Menus
`Menus` registers the panels (the villagers' "folk" went with them; each is built again with every view): "pals"
(`OpenTree` ("Eggs") and, when a Hatchery stands, `OpenHatch` at the top, the hint beside them in up to three lines
(`UIKit.lines`: "6 in huts (room for 8). New ones hatch from the Tree of Life's eggs."); a row a driftling, every one,
the hardest workers first (`Tree.better`) and those with no hut last, `Pal_<id>`: portrait, name in its rarity's
colour, its rarity, passive and its effects, mutations (`Mut_<id>` each), where it lives and helps (`Where`; "No hut.
It moves in when one has room." in orange); `Move_<id>` opens the hut picker (the same panel with `{ move = id }`: a
row a hut with its room, `Move_<uid>`; a full hut lists its driftlings with `SwapWith_<id>`, sending `pal.house { id,
uid, swap }`), `Help_<id>` the work picker (a driftling in a hut only): every workplace on the island whatever its knack, the fastest for this driftling first (`Tree.worthAt`), each `Spot_<uid>` with its name, who works there, its speed `Speed` ("x1.1", the fastest in the accent colour) and `Go_<uid>` ("Here", "Swap" when full, else "Go"), then `Rest` (`Go_0`), `Sell_<id>` (two
taps, `Tree.price`); with no driftling, "No driftlings yet. Tap an egg under the Tree of Life to hatch it." (or "Build
a hut, then hatch an egg under the Tree of Life." with no hut)), "tree" (GAME_DESIGN 6, title "Tree of Life", 380 x
196: on the left `Pace` ("New eggs every 3:00", from `clutchSecs`), `Next` ("Next in 2:41") over `TreeBar` (its fill
run down every Heartbeat from `StateClient.clutchLeft`), `Room` ("7 eggs a lot. In huts 6/8", orange when full),
"What it lays now" and the odds of each rarity (`Odds_<r>`, `Tree.odds`; "<0.1%" under a tenth of a percent, "not
yet" at 0) and, below tier 6, "A bigger island lays more eggs, and better ones."; on the right `Eggs` ("Under the
tree") and a row each of `EggView.best(v, #v.clutch)` (every egg, the rarest first), `Egg_<id>`: the `egg_<rarity>`
sprite, "Rare egg" in its colour, "Hatches a rare one" ("an" before uncommon and epic) and `PanelHatch_<id>` (its cost
and `PriceIcon`, sending `EggView.hatch`), or "No eggs left. The tree lays more soon."; with `{ hatch = id }`, every
hut full, the swap picker: a hint naming the egg's rarity and cost ("Every hut is full. Swap one out for the rare egg
(1,200 shells): the one you pick is sold."), `Back`, and a row a hut driftling, the weakest first, `SwapOut_<id>`:
portrait, name, rarity, how fast it works, mutations, "Sells for n" and `SwapTake_<id>`, sending `egg.hatch { id,
swap }`; once a new lot has replaced the egg, "That egg is gone. The tree laid new ones." and back to the tree
panel), "hatch" (a row a Hatchery `Hatch_<uid>`: its egg (`egg_<rarity>`,
`EggName`, `EggLeft` ("Hatches in 3 turns"), `EggBar`, its parents) or the slots `Slot_a_<uid>` / `Slot_b_<uid>` (the
picker: the same panel with `{ hatch = uid, slot }`, a row `Parent_<id>`, `PickParent_<id>`), the likely child
(`Child`: its portrait if seen, else its shape and ???, its rarity), `Cost` ("A feast for 300 shells, 6 turns. ..."),
`Breed_<uid>`, on while the shells are there), "index" (`Entry_<species>`: portrait or silhouette, name or "???", the
kind of island it comes from, its passive once seen; "Seen n of 55 kinds"; a kind not open yet says the island tier
it hatches from: "These hatch from island Lv 4.") and "looks" (the founder's portrait, `Prev_<k>` / `Next_<k>` for skin, hair, style and shirt,
`SaveLook` sends `founder.set`). `Words.errText(err)` words every ErrCode (`no_hut`: "Build a hut first. Driftlings
need somewhere to live."; `full`: "Every hut is full. Swap one out, or build another hut."; `not_found`: "That egg is
gone. The tree laid new ones."; `fixed`: "The Tree of Life stays on your island. You can move it."; `huts`: "No room
for another hut here. Grow the island, or replace a hut with a bigger one."; no `food`). In Build mode `BuildUI`
words a refusal itself first (`buildErr`): `blocked` "It doesn't fit there.", and `full` by the count that ran out
(`Plot.group` of the piece: the paths and water, the fencing, or the island's pieces, each with "Grow the island");
the rest go to `Words.errText`.

### 10.6 `AvatarView`
A founder per player (`CharacterModels.buildStanding`, look from the player's `Founder` attribute, else one from the
UserId), registered with the renderer and posed every frame at their character: feet on the ground under the
HumanoidRootPart (a raycast down past characters and rigs) while the Humanoid stands (its `FloorMaterial`), in the air
(`FloorMaterial` Air) at the root's height less its rest offset (learnt while it stands), posed "jump"
(`CharacterModels.poseAction`), with a puff of dust on landing; facing the root's look direction, walking at the speed
the root moves. The own founder's feet are heard (Roblox's own character sounds are off: `RbxCharacterSounds`): a
step every `5.4 / speed` seconds (0.24 .. 0.5) while it moves faster than 4 studs a second, `step_wood` on a plank,
beam or edge part, `step_water` on a part with `PixelWater` no lower than 0.3 under the lawn (a river or pond drawn on
the island, GAME_DESIGN 4.3; walking there kicks up `Puffs` "drop" splashes in place of dust, every 0.24 s, 0.14 s
running); lower water (the sea, the shallows, the foam) or the `Seabed` / `Shelf` under it means swimming (floor
"swim", GAME_DESIGN 8): the rig drawn `SWIM_SINK` (1.8) under the water's surface, `poseAction` "swim" (a crawl when
moving, treading water when still), a `Ripple` (a ring of foam, four flat "foam" strips round them on the water,
growing and shrinking in two steps; deep under the sea otherwise), a splash going in (`Puffs` "drop" 10 and a loud
`step_water`), a stroke every 0.55 s while moving (drops ahead and a soft `step_water`), a few drops every 1.2 s when
still; `swimming()` (the own founder now: the HUD sets `WalkSpeed` to `Tuning.SwimSpeed` and `JumpHeight` 0 while it
is true); `step_sand` on ground under the lawn's height (the beach),
else `step_grass`; `jump` as it leaves the ground, `land` (on the boards a firmer `step_wood`) as it comes down. The Roblox avatar is hidden on every client (`LocalTransparencyModifier` 1 on its parts and decals).
Other players' names float over their heads (World root). `founderPos()`, `count()`, `lookOf(player)`,
`setOverride(fn?)` (a cutscene poses the own rig instead: `fn(rig, t, dt)` every frame; nil gives it back).

### 10.7 `BuildUI` (Build mode), `BuildFx` and `Puffs`
`open(tab?)` (the HUD's Build button; `tab`: the tray opens on that tab, the quests' Go; an old tab's name, `farm`
`wood` `shop` or `gen`, opens Work on that row; a tip's tab still wins): closes any panel,
`CameraController.setFree(true, TRAY_H + 8)` and lays out the tray `BuildTray` along the bottom (a workbench in a frame
of planks, `wood = 3`, its tabs on a `plank`; `TRAY_H` (82) tall, shorter while a piece is picked, below). With nothing
picked it holds: the tabs `Tab_work Tab_nest Tab_path Tab_fence Tab_water Tab_nature Tab_decor Tab_fun` (Work, Huts,
Paths, Fences, Water, Nature, Decor, Fun, each with its `mini_` icon `work nest path fence water nature decor fun`; the
icons alone when the names don't fit; it opens on Work's Wood row); the count (`Count`: the tab's group against its
limit, `Plot.group` and `groupLimit`: the pieces on Work, Nature, Decor and Fun, the tiles on Paths and Water, the
fence lengths on Fences, the huts against `hutLimit` on Huts; orange when full); `Expand` ("Island max", greyed, at the
top tier; `island.expand`, its price under it in `ExpandCost`; the fanfare and "Your island grew into Moonlit Bay.
There's more to build now." (or how many buildings had to move), named from the answer's `tier`, wait for
`PixelRenderer.afterBake`, 1.5 s at most) and `BuildDone`; the search box `BuildSearch` (a TextBox `Box` under a
pixel-font copy of its words, `Query`, "Search" while empty, and `ClearSearch`), with the search button `SearchButton`
just before it (16 wide, the 11 x 11 `mini_search` magnifier; it calls `focusSearch()`, the cursor into `Box`; the
accent colour while a search is on): both on the tabs' plank right of the tabs when there are 80 px free there (the box
62 to 110 wide), so Decor's fourteen chips fit one line on a computer, else at the end of the chips' row, the box 96
wide or 70 on a screen under 500; the box kept across rebuilds so typing keeps the keyboard, cleared when Build mode
closes; under the tabs the tab's rows (`Chips`, scrolling sideways: `Chip_all` and a `Chip_<sub>` a row,
`CHIPS`: Work's `farm wood shop gen`, Water's `tiles bridge float` ("Water", "Bridges", "On the water"), Nature's
`trees plants rocks`, Decor's 13 themes, Fun's `seats lights play treats fountains`; a tab with one row shows a
`TabHint` instead), or, while the search box has words, "Everything called "lantern":" and every piece whose name, row
or tab holds them; then the cards (`Cards`, scrolling sideways, the scroll kept while the tab, row and words stay):
`Card_<id>` (38 x 46, a carved board; `TutGoal` on the tip's) holding `Buy_<id>`: the piece's picture (`thumb_<id>`,
24 x 24; its tab's `mini_` icon when there is none) over its price in wood (`Wood`, red when short), or `Lock` ("Lv7"
on a locked card, "No room" on a hut at the huts' limit); the list from `Data/Buildings` (never the tree) by tab and
row, the open ones first by price, then the locked ones by tier. A mouse over a card shows `BuildTip` (172 wide, over
the tray: `TipName`, its size ("3 x 3", "2 x 2 tiles", "2-stud lengths"), `TipAbout` (its blurb, what it makes a
minute for each common driftling, a hut's room and comfort, its charm, "Goes over water." or "Goes on water."),
`TipLocked` ("Opens at island level 7.") and its price). A tap on a card: a locked one says "Expand your island to
level 7 to build this.", a hut at the limit `Words.errText("huts")`; any other is picked, with a word on what to do
("Tap the grass where it should go.", "Tap the water where it should float.", "Drag along the grid lines to put up a
fence."...).

With a piece picked (`pick(id, rot?)`), a ghost model (`Ghost` in `Workspace.PixelDynamic`: the piece and its
`Footprint`, a raised neon frame of four edges just above the grass (for a fence length, a bar along its line), cyan
(`screen_on`) where `Plot.fits` says it fits, red (`berry_red`) where not) stands on the cell under the pointer
(mouse) or the last tap (a tile snaps to the even studs, a fence length to the nearest grid corner); the bar shows
`Rotate`, `Place` / `Move here` (on while it fits) and, for a piece picked up off the island, `Copy` (not for the
tree), `Replace` (when `Plot.replacements` has any) and `Store` ("Clear away", greyed for the tree, `Plot.isFixed`),
then `Cancel`; under them the `Info` plate (its picture, `What` ("Placing: Oak Tree", "Moving: Lumber Camp Lv2"),
`Blurb` (what it is), the price of a new piece and, with a keyboard, `Keys`: "R turns it. E puts it down. Esc
stops.", "R turns it. C copies it. X clears it away. Esc puts it back." or "Esc stops drawing."), as tall as its
words, and the tray shrinks to the plate's height so more of the island shows (`trayHeight()`: the tray's height now,
`TRAY_H` with nothing picked; Hud's tips banner sits on it). `Replace` turns the bar to `ReplaceBack`, `ReplaceWhat`
and a card a replacement (`Swap_<id>`: its picture, its name, its room or charm, and `SwapTo_<id>` with
`Plot.replaceCost`; the tray keeps its full height for them); a tap sends `plot.replace` (the `level_up` sound, "The
Driftling Hut is a Cozy Burrow now.", `BuildFx.drop`). A tap on a placed piece of the own island (a ray into its
`Static.Decor`) picks it up. A press dragged more than 8 px pans the view (`CameraController.panBy`). The keys (input
not already taken, so never while typing in the search box): R (`rotatePicked`: a quarter turn, a fence length between
0 and 90), E or Return (`confirm`), C (`copyPicked`: a new pick of the same piece, turned the same way), X or Delete
(`storePicked`: `plot.store`, then `BuildFx.cleared`), Esc (drops the pick, or with none closes Build mode).
`confirm()` sends `plot.place` (the piece stays picked for another copy, unless it was the tip's) or `plot.move`, then
`BuildFx.drop`; `close()`; `isOpen()`; `Changed: Signal<boolean>`. The tray is laid out again on each view, on
`UIKit.Resized` and when what can be afforded changes (`StateClient.Tick`). The tips (`TUT`: tip 1 Work's Wood row and
the lumber camp, 2 Farms and the patch, 3 Huts and the hut, 5 Shops and the stall; tip 4, an egg hatched, has no
building): opening, and each new tip while open (`followTut`, from the rebuild; it waits while a piece is picked),
turns the tray to the tip's tab and row; the tip's card (`TutGoal`) and its tab, while another is shown, pulse to the
accent and shine; placing the tip's building drops the pick so the tray goes on to the next tab. `TRAY_H` (82),
`debugState() -> { tab, chip, goal? }`, `debugTip(id) -> boolean` (a card's tooltip, as a mouse over it),
`debugSearch(text)` (typed into the box), `focusSearch()` (the search button's work), `tapScreen(pos, mouse?)` (the sims'
and previews' tap).

**Drawing paths, water and fences** (GAME_DESIGN 4): picking a drawn piece (`Plot.isDrawn`) opens the draw bar
(`DrawLine`, `DrawBox`, `DrawErase`, `DrawLook`, `Cancel`, `BuildDone`, and the `Info` plate with the `Stroke` label:
"12 tiles, 180 wood", "5 lengths, 40 wood", "5 to take up") instead of the ghost. A press starts a stroke (not in
`DrawLook`, which pans), a drag adds to it (`strokeTo`; a tile's cell is its north-west corner on the even studs, a
fence's edge `{ x, z, rot }` a length from a grid corner: Line fills the gaps between the cells it passes, or runs
along x then z from the last corner; Box every cell of the rectangle from the press, or the edges all the way round
it; `DRAW_MOST` 240 a stroke), the mouse alone previews one cell (or the first length east), and the release sends it
(`finishStroke`: the cells the plan can change, in batches of `PAINT_MAX`, through `plot.paint`, `plot.unpaint` with
the picked piece's kind, `plot.fence` or `plot.unfence`; the refusals in words; then `BuildFx.stroke`).
`strokePlan(cells) -> ({ "lay" | "swap" | "lift" | "no" }, n, cost)` (cell by cell, by the server's rules: one of
another look swapped, `Plot.fits` for a new one, the group's limit and the wood); `showDrawGhost` lays a flat neon
plate a cell, or a bar an edge (`DrawGhost` in `Workspace.PixelDynamic`, parts `Cell`): cyan to lay, yellow to swap,
orange to lift, red where it can't. `debugDraw(cells, mode, keep?) -> plan` (the sims' and previews' stroke through
tiles' cells or fences' corners, mode "line", "box" or "erase"; `keep` leaves the markers up without sending).

`Controllers/BuildFx` (GAME_DESIGN 4.5): `drop(plot, uid, id, x, z, rot, lvl?)` (a piece put down: the server's model
(found in the plot's `Decor` by its name's prefix `uid:id:x:z:rot:`) is held back, unparented, while a stand-in built
by `DecorModels.build` (`DropIn`, registered with the renderer) falls `DROP_H` (1.6) studs in `DROP_T` (0.16 s),
faster as it goes, and hops `BOUNCE_H` (0.25) in `BOUNCE_T` (0.14 s); then the real one goes back. At the landing
(`land`): six `poof` clouds on a ring round the footprint, bursts of its feel's two particle kinds (`FEEL`: wood `wood
dust`, stone `chips dust`, plant `leaf dust`, water `drop drop`, metal `glint dust`, magic `magic star`, sand `dust
dust`, snow `snow snow`, cloth `confetti dust`, fire `ember dust`), two `twinkle`s over its top, its `place_<feel>`
sound and, for a charm of 1 or more, `Puffs.float("+N", ...)` in pink with `mini_charm`; with the pixel filter off,
only the landing), `stroke(plot, id, places, fence, clearing)` (a `poof` and three particles at each tile or length,
at most 24 spread along the stroke, the sound in a run of up to six 0.05 s apart, two twinkles over the last; taking
up: dust and the `close` sound), `cleared(plot, id, x, z, rot)` (a puff and dust where it stood, `close`), `showing()`
(drops under way, for the sims). `Controllers/Puffs`: `burst(kind, at, n, radius?)` (n particles of a kind from a
world point, spread flat over `radius`: `KINDS` `dust chips wood leaf petal drop ember snow confetti magic glint` (1 px
rects in their palette colours, each kind with its speed up and out, gravity, life and sway) and the sprite kinds
`twinkle` (`spark_1..3`), `star` (`twinkle_1`, `twinkle_2`) and `poof` (`poof_1..3`); moved in world studs every
Heartbeat and drawn on the World canvas at whole UI px where `PixelRenderer.projectPixel` puts them; at most `MOST`
(260) at once; nothing while the pixel filter is off), `float(text, at, color, icon?)` (words rising 14 px over 0.6 s
from a world point and blinking out by 1.1 s), `count()`.

### 10.11 The hatch scene (`UI/HatchScene`, `UI/HatchBackdrop`, `Models/EggModels`; GAME_DESIGN 6.2)
`HatchScene.play(res, after?)` (`res = { sp, muts, r, hr }` from `egg.hatch`; one scene at a time; `after` runs when it
ends), `skip()` (a tap: to the crack, then the whole list, then away), `isOpen()`, `setQuick(on)` (sims: it ends at
once, `after` still runs), `setWait(secs?)` (previews: the blinds wait longer for the stage's picture), `debugState()`
(`{ open, phase ("curtain", "egg", "rise", "build", "crack", "reveal", "done"), r, hr, clock, crackAt, endAt, shown,
muts, rays, shards, pal, egg, title, name }`).
It builds its stage in a `HatchStage` folder at `ORIGIN` (0, 0, 9000): the floating islet (`ISLE` 4.2 studs), the
woven nest, the props (cylinders for twigs and stems, Wedge blades marked `PixelWind` for fern fronds and grass,
CornerWedge pyramids for the lantern roofs and rock chips, Wedge roots), and the moving things in `HatchDynamic`, each
registered with the renderer: the egg (`EggModels.hero(r, EGG_H[r])`: `EGG_H` 2.3 .. 2.8), the rays (`HatchRays`:
thin Neon blades in the camera's own plane, turning, behind the egg), the bits of shell (`HatchShards`: falling,
bouncing on the nest and the grass, sinking after 2.2 s) and what hatched (`MicroModels.driftling`, scaled up to
`PAL_SCALE` 1.35 with an overshoot, "cheer" then "idle"). `CameraController.setStage({ name = "hatch", ..., top = 30,
bottom = 40, clear = true })` frames the islet; the HUD and World roots are disabled meanwhile; `DayLight.hold`
holds the rarity's `GRADE`; `PixelRenderer.setDim` dims the islet in the build-up (`GLORY[hr].dim`) and `setOffset`
jolts the picture at the crack. The overlay is a `HatchScene` frame on the `Stage` canvas: the curtain (`HatchCurtain`,
blinds over the bake, up to `Tuning.HatchSceneWait` 4 s), `HatchTitle`, `HatchName`, `HatchLine`, the plates
`HatchMut_<i>` (`Name`, `Blurb`), `HatchHint`, `HatchFlash`, 1 px `HatchDot`s and `HatchStar` sprites, and the
see-through `HatchTap`; after the list it waits `Tuning.HatchSceneHold` (6 s) and closes by itself. The timeline
(`plan`): `INTRO` 0.7 s, the rocks (`GLORY[r].rocks` x `ROCK` 0.55 s), a step up each `RISE` 1.7 s (its flash at
0.9 s), the build-up `GLORY[hr].build`, the crack, the name 0.35 s after it, the list from 1.1 s after it, half a second
a mutation. `GLORY` by rarity: rocks, build, rays, rayLen, sparks, shards, flash, dim, jolt, confetti, stars.
`EggModels.hero(r, h) -> (model, parts, top, fx, cracks)`: the shell 25 balls along the axis sized to `PROFILE`,
marks as flat Cylinder discs on the shell (`dab`), beads (`bead`: gems, the crown's points), strips (leaves, icicles),
the shine (white), the fx (`mote` x3 epic, `halo` x20 and `beam` legendary: with the cracks' light the only Neon parts, since Neon pools light round it at night) and the cracks (`Crack = { p, off,
stage }`: stage 1 at the egg's second rock, 2 at the build-up, 3 halfway through it, Neon in the rarity's light from
60% of it; out of sight until then). Parts above `SPLIT` (0.56) are the top.
`HatchBackdrop.paint(r, W, H, ex, ey) -> buffer` (the sky picture, RGBA at the art grid: banded sky with dithered
seams (`SKIES[r].stops`), aurora, stars, sun or moon with its halo, clouds, the egg's glow at (ex, ey), two far islets,
three ranges of hills with trees outlined in ink), `show(r, ex, ey)` (paints it into an `EditableImage` on the
`HatchBackdrop` ScreenGui and starts the sky's life on `HatchSky`), `step(dt)` (birds in `WINGS` beats, a shooting
star, twinkles: K x K frames at whole art px), `hide()`.

### 10.8 and 10.9 (gone)
The walk in and home (`Voyage`) and the islet's screen (`ExpeditionUI`, `MicroStage`: the stages, the battles, the
skill window, the cards) went with the expeditions (GAME_DESIGN 7, 2026-11-12). Their text is in this file's history,
up to commit f667462.

### 10.10 Sprites (`PixelSprites`, `ArtData`, `ThumbData`)
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
The islands' small lives (`AmbientView`, drawn by `Render/Fx` into the pixel layer, not the interface) are `fx_`
sprites in `ArtData`, hand-shaded with digit tones (`FX` and `GROUND` in `gen_art.py`; no `_flash`): `fx_pip`,
`fx_wren`, `fx_gull` (four frames: sitting or standing, pecking, wings up, wings down; teal `T` and coral `Q` ramps),
`fx_fish` (nose up, level, nose down), each with a small version (`fx_pips` ...) for a screen that shows the island
small, all outlined in ink; and without an outline (ground and light, like the sparks) `fx_tuft` (upright, leaning
with the wind, leaning back), `fx_flower`, their small `fx_tufts` and `fx_flowers`, `fx_bfly`, `fx_leaf`,
`fx_petal`, `fx_glint`, `fx_ripple`. The pixels a tinted sprite draws in `tn0` .. `tn3` (the same values as
`Fx.TONES`) take the tones of a colour given at draw time (`Fx.tones`, Render/Ramp's ramp).
The overlay's sprites also have a white `<name>_flash`; the icons have a dark `<name>_sil` (not met yet); an
animation's frames `<name>_1`, `<name>_2`... share one canvas (bottom centre). The sprites: the driftlings' portraits
`icon_<species>` (32x32: drawn from its model; `Menus` puts a row's words at `PX` 40, right of one), the small icons
`mini_<name>` (11x11: `shell food wood sun moon charm folk pal visitor home nest tree train boost path decor work fence
water nature fun start loot chest wild rest boss star boat`; `tree` the Tree of Life's (its card, panel and quests: a
round crown with glowing fruit on a short trunk); Build mode's tabs `work` (a hammer), `nest`, `path`, `fence`,
`water`, `nature` (a pine), `decor` and `fun` (a balloon); `charm` (a heart) the "+N" over a piece put down; no `tide`
since the tide went; `food` unused since the Work tab took the Farms tab's place; `train`, `start`, `loot`, `chest`,
`wild`, `rest`, `boss` and `boat` unused since the expeditions went), the eggs `egg_1` .. `egg_5` (12x15, matching
`EggView.LOOK`: cream with brown freckles, green with a white zigzag band, sky blue with white stars, purple with pink
spots, gold with a band of light; the tree's card and panel and the Hatchery), the arrows `arrow_<dir>` (13x13) and
`arrow_<dir>_t` (7x7), `note`, `heart`, `spark_1..3` (a gold spark: a legendary egg's, Build mode's twinkle),
`twinkle_1`, `twinkle_2` (7x7: a small white star opening and closing, cyan at its tips: a rare egg's), `poof_1..3`
(7x7: a little cloud that swells, thins and breaks up: `Puffs`' `poof`), `bombfuse`.

The build catalog's pictures are in `ThumbData` (generated by `scripts/gen_art.py` from `scripts/thumbs.txt`; do not
edit), ArtData's format in a module of its own so ArtData stays small: `thumb_<id>` (24x24) for every piece in
`Data/Buildings` but the Tree of Life, no `_sil` or `_flash`. Each is the piece's model drawn by `Pixel/Snapshot` from
the world's camera (yaw 45, pitch 30) at lvl 1 in the preview scenario `pthumbs` (`tools/preview/thumbs.luau`): a path
or water tile as a 2 x 2 block (the water tiles' lvl from `PlotService.waterMasks`, so the banks run round the block;
`DecorModels.build` flies no pennant on a water tile now, and `thumbs.luau` still takes any pennant parts off), a fence
as a corner (rot 0 and rot 90 from one post), a piece with `water` "over" on a stream two tiles wide at right angles to
its long side, one with `water` "on" on a pond a stud wider all round (in whole tiles). It is drawn on canvases of 24 to
28 px, each at its own scale, and `tools/preview/gen_thumbs.py` keeps the biggest drawing that fits 24 x 24 (the outline
in the outer pixel), tidies it with `gen_portraits.tidy(px, thin=True)` (the portraits' rules, but a 1 px pole, a
spire's tip and a tile's points stay, and a gap deeper than a pixel stays open) and centres it by whole pixels.
`sh tools/preview/thumbs.sh` runs the lot (about 8 s); run it again after a piece's model changes.

`PixelSprites` (a name starting `thumb_` is looked up in `ThumbData`, any other in `ArtData`):
`has(name)`, `size(name) -> (w, h)`, `image(parent, name, pos?, z?) -> GuiObject` (an ImageLabel `Sprite_<name>`
showing the sprite's EditableImage, made once and shared, `ResampleMode` Pixelated, at the sprite's own size: no
scale; without EditableImages a Frame of 1 px run rects), `anim(parent, names, pos?, z?) -> Anim { f, w, h, set(i),
flash(seconds?), moveTo(x, y) }`.

## 11. Verification

- `bash scripts/check.sh`: Rojo sourcemap, luau-lsp strict analysis (0 errors), luau-compile, the specs (`tests/run.luau`
  lists them: Util, Validate, Numbers, DataIntegrity, Traits, Island, Tree, Breed, Economy, Plot, Quest, Schema,
  Shading, Raster, Rim, Fx, PixelFont), the Rojo build. Must end with `ALL CHECKS PASSED`.
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
steps; builds `build/ByteSizeStudio.rbxlx` as its check), `Net`, `Render/Fx` (the effect layer, cut down: no
seasons or places, no weather or shelters; sprites from `ArtData` instead of legends, tinted sprites, sticky pixels,
a light's glow id; the renderer's books upload only the pixels that changed). Written new for this game: everything else, including a much smaller
`PixelRenderer` (one fitted scale with pans and rect re-casts, no Actors, no Hold, no per-plot indoor light) and
`CameraController` (the fitted home view, following the founder, Build mode's free pan), and the sea of islands
(`Data/Street`, `StreetModels`, PlotService's plots and open water, AvatarView's founders), modelled on Random Bakery's
street of bakeries and its plot (ROUND3.md 6.6, 9) but smaller: buildings on a whole-stud grid, with paths, water and
fences drawn in lines and boxes the way the bakery's floors are.
