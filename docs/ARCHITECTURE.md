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
                       characters on (the founder walks and jumps on the islands: JumpHeight 7.2)
src/shared/            Types, Net, Config (Tuning, Monetization), Data (content), Logic (pure rules), Render (pure pixel
                       maths, copied), Models (procedural models), Locale (Lang: English only)
src/server/            Main.server.luau, Services/* (DataService, Session, Router, IslandService, PlotService)
src/client/            Main.client.luau, Controllers/* (StateClient, CameraController, WorldView, AvatarView, StreetLife,
                       Audio), Pixel/* (PixelRenderer, BakeCast, PixelText, Snapshot, ImageMemory), UI/* (UIKit, Hud,
                       Menus, BuildUI, ExpeditionUI, Voyage, MicroStage, PixelSprites, ArtData (generated), Words)
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
  `Models/DecorModels` builds every building, `Models/StreetModels` the islands and the sea, `UI/MicroStage` the islets' stages,
  `Models/MicroModels` the driftlings and the stages' things.

## 3. Types (`src/shared/Types.luau`)

`Look`, `Piece` (`{ uid, id, x, z, rot, lvl }`: a building standing on the island; `uid` stays while it stands; a
wild place's `lvl` is its level, Data/Sites),
`PlotSave` (`{ placed }`), `Villager` (`{ id, name, look, work (a Piece uid, 0 idle), lvl, xp, seed, day }`), `Pal` (a
befriended driftling: `{ id, sp, lvl, xp, work, muts? }`: `muts` its mutations, Data/Traits ids), `Captain` (`{ lvl, xp }`), `Settings` (`{ pixel, music? }`: music "on" | "off"), `Stats` (`{ days, built,
earned, befriended, battles, cleared, movedIn, hatched, skills }`: `skills` the skills used in battle), `Profile` (the save, version 9: `quest` the questline's quest on the go (Data/Quests; one past the last: all done; the view carries it too), `shells`, `food`, `wood`, `day`,
`tier`, `founder`, `cap`, `folk`, `pals`, `plot`, `islets` (wild places cleared the first time), `sea` (the
island's own seed: where its wild places come up and what each holds), `wilds` (the tiers whose wild places have come
up: 0 .. `tier`, Logic/Sites), `pouch` (the snack pouch: 1 .. 6), `seen` (species -> 1 met, 2 befriended), `eggs` (`Egg`: `{ uid (its Hatchery), a, b (the parents' ids), sp, muts, left (turns) }`, one a Hatchery),
`nextId` (villagers, driftlings and pieces share it), `tut`, `stats`, `settings`, `createdAt`), `Fighter` (`{ key ("f",
"v<id>", "p<id>", "w<i>"), name, kind, sp?, look?, lvl, hp, maxHp, atk, def, spd, skill, charge, gauge (its timer, 0 ..
1) }`), `Battle` (`{ foes, acts, boss, shield, foeShield (the shields' seconds), lock (an action playing: seconds),
paused, clock, sp (the party's skill points), undo? }`: `undo` (`Undo`) is how the battle stood before the action now
playing, kept while `lock` > 0 so a snack can cancel it: `{ by (the actor's key), charge, shield, foeShield, hp
(key -> hp), atk (key -> atk) }`), `Isle` (what a wild place holds: `{ id? (the place's piece uid), seed, lvl, kind (Data/Islets),
name, wild (its kind's species and a stray), boss, bossName, loot { food wood shells }, reward }`), `Expedition` (`{
isle, node, nodes (the place's whole path: the landing, six stops, the guardian last), done, party, loot { shells
food wood }, battle?, befriended, snacks (left on this trip), site? (the wild place explored: its piece uid), beaten?
(1: the guardian beaten), sp? (the party's skill points between battles: a new battle starts with them, `Battle.sp`, and
a battle's end keeps what is left; `next`'s wild or boss `out.sp` says how many), over? ("home" | "won" (the
guardian beaten: the place cleared) | "lost"), gained
(`{ xp, ups (key -> levels) }`: what the party gained on this trip, for the Cleared and Expedition Complete! cards) }`), `ClientView` (the profile's fields plus `dayFrac`, `plot`
(the plot index), `pieces`, `rates` (a day, after eating), `charm`, `beds`, `nests`, `visitors`, `sea`, `eggs`, `exp?`; no `wilds`), `ErrCode` (with `wild`: inside a
wild place's ring, or a wild place moved or cleared away),
`Response`, and the utility types `Connection`, `Signal<T...>`, `Rng`, `PixelTier`. The file is the reference for
every field.

## 4. Config

- `Config/Tuning.luau`: persistence (`DataStoreName = "BSS_Profile_v1"`, never renamed), the island (`StartShells`,
  `StartFood`, `StartWood`, `TurnSeconds` (the island's pace), `DaySeconds` (the sea's day: hours), `EatFolk`, `EatPal`, `Hungry`, `IdleOutput`, `PalBoost`, `VisitorCharm`,
  `VisitorsMax`, `ShopVisitors`, `MoveInCharm`, `FolkMax`, `PalsMax`, `Refund`, `UpgradeMult` (a level from an older save; no upgrades since 2026-11-11),
  `TierCost`), levels and battles (`LevelGrow`, `LevelMax`, `XpBase`, `XpPow`, `XpPerFoe`, `TrainXp`, `PartyMax`,
  `Supplies`, `SkillEvery`, `ShieldTake`, `ShieldSecs`, `FleeBase`, `BossBoost`, `RestHeal`, `StageWait`; the
  timed battles: `AtbTime`, `AtbRef`, `AtbMin`, `AtbMax` (a timer's seconds by speed), `AtbShare` (a crowd's
  timers slow so the actions take about this share of the time), `ActLock` (an action's play
  time), `SpRate`, `SpMax` (the skill points), `SnackBase`, `PouchCost` (the snack pouch: `{ shells, wood }` a level)), the wild places (GAME_DESIGN 7: `IsleFoodBase` / `IsleFoodLvl`, `IsleWoodBase` / `IsleWoodLvl`, `IsleChestBase` /
  `IsleChestLvl2`, `IsleRewardBase` / `IsleRewardLvl2`: a loot stop's food and wood, a chest's shells and the
  guardian's reward by the place's level; `FirstClear` (the reward times this the first time a place is cleared),
  `ReplayReward` (times this on a later trip), `SiteRadius` (studs round a wild place's footprint that nothing new may
  cover), `ClearCharm`, `ClearCharmMax` (charm a place cleared, up to the most)), a place's path (`BossEvery` (the
  guardian's stage: six stops, then the guardian, the last), `StageLvl`, `StageBoost`, `StageLoot`, `ClimbFull` (a place
  under this level climbs only its level over this of the way), `CatchBreath` (health back after a won fight in such a
  place, times the climb it lacks)), the server's step and rate limit, the sea (`MaxPlots`, `PlotSpacing`, `PlotPieces`, `HomeCooldown`),
  and the camera and pixel filter values (Random Bakery's `CamYaw` 45, `CamPitch` 30, `PixelTiers`, `PixelScaleMin` /
  `PixelScaleSides`; this game's `CamRayBack`, `PixelMaxRayDist`, `CamFollowBox`, `CamGlide`, `CamBuildPan`,
  `PixelPanRays`, `PixelInvalidateRaysFrame`, `PixelMaxDyn`, `PixelStageBakeMs`).
- `Config/Monetization.luau`: `GamePasses`, `DevProducts`, `Badges` (empty or 0), `Sounds` (the Creator Store
  library ids `Controllers/Audio` plays: Roblox's free licensed ProSoundEffects clips and APM Music stingers, none of
  Random Bakery's, each named in a comment) and `Music` (`{ day, night, sea }`: lists of `{ id, gain }`, APM Music
  tracks, each named; `gain` evens their loudness out).

## 5. Data (pure content tables)

| Module | Holds |
|---|---|
| `Data/Palette` | the LUT colours (`order`, `colors`), the shore's `shallow`, `foam`, `rock` and `rock_dark`, the older rooms' floor and wall themes (`themes`, still in the LUT), the light modes, and the UI's colours (`ui`, `axis`, `match`) |
| `Data/Buildings` | the 73 pieces (GAME_DESIGN 4) `{ id, name, kind (food wood shop home nest train breed gen path decor), shells, wood, w, d, rate, eats, job, knack, beds, slots, charm (a path's may be a fraction), comfort (a home's or nest's share), boost ("farm" "fish" "wood" "shop" "all": a "gen" piece's knack), boostBy, tier (1 .. 6), blurb }`, then two of kind "site" for each wild place of Data/Sites (`wild_<id>` and `done_<id>`: its name, footprint and blurb, no price, tier 99 so no tab of the tray shows them; a cleared one charm 3); `list`, `byId` |
| `Data/Sites` | the wild places on the island (GAME_DESIGN 7) `{ id, islet (its Data/Islets kind: its driftlings and stage), name, plural, w, d (its footprint, whole studs), blurb }`: `tidepool tallgrass bog volcano cave frostpeak bluff coralpool ruins`, one a kind of islet; `list`, `byId`, `byIslet`, `SPAWN` (what comes up at each tier, `{ id, lvl }`: tier 1 a tide pool Lv 1 and tall grass Lv 3, then three more each tier up to Lv 45 at tier 6, every kind by tier 5), `wildId(id)` / `doneId(id)` (the piece ids, `wild_<id>` / `done_<id>`), `of(pieceId) -> (SiteDef?, wild)`, `spawnAt(tier) -> { { id, lvl } }` (none past the last) |
| `Data/Skills` | the skills the party learns (GAME_DESIGN 7) `{ id, name, cost (skill points), target ("none" "ally" "down" "foe"), move (how it plays: attack bash quick zap cast), blurb, dmg?, hits?, all?, heal?, revive?, rally?, shield?, haste?, dizzy? }`; `LINES` (who learns what at which level: `lead` the founder's, and one per battle skill `bash quick zap heal shell`); `list`, `byId`, `lineOf(kind, skill)`, `known(line, lvl)`, `knows(line, lvl, id)`, `learnt(line, from, to)` |
| `Data/Creatures` | the 55 driftlings (GAME_DESIGN 6) `{ id, name, islet (the kind of island it lives on), rarity (1 common .. 5 legendary), hp, atk, def, spd, skill, knack, trust, shape (its MicroModels body plan), body, accent, blurb, passive ({ name, fx }: its own, Data/Traits effects), power (its stats weighted, +12% a rarity step: the breeding rank) }`; `list`, `byId`, `skills` (their names) |
| `Data/Traits` | what makes one driftling unlike another (GAME_DESIGN 6): `MAX` (4 mutations), `KEYS` (the effects: hp atk def spd xp work farm fish wood shop; 0.1 = +10%), `RARITY` (`{ name, color, weight }` x 5: the wild weights 100 45 16 5 1.2), `TIER_COLOR`, `TIER_STARS`, `list`, `byId` (mutations `{ id ("sturdy3"), family, tier (1 .. 4; 0 a flaw), name, blurb, fx }`: ten families x four tiers and five flaws), `families`, `at(family, tier)`, `roll(rng, rarity) -> { id }` (0 .. 3, no family twice, a rarer species rolls fewer flaws and higher tiers), `sum(passive?, muts?) -> Fx`, `workAt(fx, knack)` (work + the knack's share, at least -0.5), `clean(muts)` (known ids, a family once, at most MAX), `describe(fx)` ("+15% health, +24% at farms") |
| `Data/Quests` | the questline (GAME_DESIGN 9) `{ id, title, text (what to do and where), goal { kind, n, of? }, reward { shells?, food?, wood? }, go (its Go: a panel "pals" "folk" "index" "hatch", "site" (a wild place's card: the trip under way if there is one), or "build" / "build:<tab>"), icon (a `mini_` sprite) }`, twenty in order; `list`, `byId`. Goal kinds: helpers folk workers paths decor built (of a building kind) befriended battles skills charted (wild places cleared) tier pouch seen hatched |
| `Data/Islets` | the 9 kinds of ground behind the wild places (GAME_DESIGN 7; each Data/Sites kind names one as its `islet`) `{ id, name ("Beach"), plural, stage (its MicroStage set: loot leap dino frost fish swamp grotto bluffs ruins), lvl (the level it turns up from: 1, 5, 10, 16, 23, 7, 13, 20, 28; a place's strays come from the kinds open at its level), wild (every driftling of its kind, from Data/Creatures, by rarity then id), first / last (its names' words), color, blurb }`; `list`, `titles` (a guardian's) |
| `Data/Names`, `Data/Looks` | the villagers' names; skin, hair, hair style and shirt lists (`Types.Look` indexes them) |
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
| `Island` | the turn and the day (GAME_DESIGN 3, 5): `piece(p, uid)`, `beds`, `nests`, `charm` (every piece's, one a driftling, `ClearCharm` a place cleared up to `ClearCharmMax`), `visitors`, `works(id)`, `homes(p) -> { [key]: { uid, comfort } }` (GAME_DESIGN 4.1: the homes, best comfort (theirs plus `ComfortLvl` by level) first, then the first built, filled with the villagers in the order they came; the nests with the driftlings), `boosts(p) -> { farm fish wood shop all }` (each kind of boost building once), `boostAt(b, knack)` (its own and "all", `BoostMax` at most), `rates(p, away?) -> Rates` (`{ food, wood, shells, made, eaten }` a turn; a worker's output 1 + its comfort, a helper's share plus its nest's comfort, every building times 1 + `boostAt`), `step(p, dt, away?)` (the stores, the food never below none), `randomLook(rng)`, `freeJob(p, knack?)`, `palWork(p, pal) -> number` (a helper's work share at its building's knack: its passive and mutations, `Traits.workAt`; a helper adds `PalBoost` x (1 + that) to the building), `moveIn(p, rng) -> Villager` (a castaway into a free bed and job), `welcome(p, rng) -> Villager?` (the first home on an island nobody lives on: someone moves in at once; IslandService calls it after every building change), `turn(p, rng, away?) -> { movedIn?, trained? }` (a turn's end), `newDay(p)` (a calendar day: the count), `xpTo(lvl)`, `gain(who, xp) -> levels`, `setWork`, `setHelp` (one a building, swapping; driftlings at their knack), `dismiss`, `release`, `expandCost(tier)`, `expand(p)` (data `{ tier, moved, cleared, sites }`: `Plot.refit`, then `Sites.spawn` brings up the new tier's wild places, `sites` how many), `setFounder` |
| `Plot` | building (GAME_DESIGN 4): `ROTS`, `limit(tier)`, `footprint(id, rot)`, `rect`, `blockers(tier)` (the campfire's plaza and the path to the jetty), `isWild(id)` (a wild place, `wild_<id>`), `isSite(id)` (any place, wild or cleared), `zone(q) -> Rect` (a wild place's ring: its footprint and `SiteRadius` studs round it), `fits(tier, placed, id, x, z, rot, skip?, loose?) -> (ok, "outside" (a footprint cell not `Street.buildable`) / "blocked" / "overlap" / "wild" (inside a wild place's ring, unless `loose`: pieces already standing, a place coming up) / "unknown")`, `pathLimit(tier)` (`PathPieces`), `isPath(id)`, `used(p, id) -> (n, limit)` (the pieces of its count: paths, or the rest; the places never count), `place` (bad_payload (a place's id), locked, full (by its count), money, wood, wild, blocked; a building that takes workers gets an idle villager), `move` (wild (a wild place stays put), wild or blocked for the spot; no upgrades: taken out 2026-11-11; a level from an older save stays and counts), `replaceCost(q, id)` (the new price less `Refund` of the old, never below nothing), `replacements(q, tier)` (the others of its kind open at the tier; none for a place), `replace(p, i, id)` (bad_payload (another kind, the same piece, a place), locked, money, wood, blocked (the new footprint where the old stands; the rings `loose`), no_room (fewer beds or nests than needed); the uid kept, the level 1, helpers of another knack back to rest), `store` (wild (a wild place can't be cleared away), no_room, egg; `Refund` back, nothing for a cleared place), `refit(p) -> (moved, cleared)` (pieces that do not fit move to the nearest free spot, or are cleared with their whole price back: after the island grew and when a save loads; the rings `loose`); drawn paths (GAME_DESIGN 4: Build mode's draw bar): `PATH_STEP` (2: a path tile's cell, even studs), `PAINT_MAX` (40 cells a request), `cells(s) -> { {x, z} }` and `cellString(cells)` (the payload's "x,z;x,z"), `paint(p, id, cells) -> (ok, { placed, skipped })` (a path piece only; each free cell gets a tile at rotation 0, a cell that doesn't fit is skipped; locked, full, money, wood, wild or blocked (none laid)), `unpaint(p, cells) -> (ok, { removed })` (every path tile covering a cell comes up with `Refund` back; not_found) |
| `Battle` | timed battles (GAME_DESIGN 7): `FOUNDER`, `villagerBase(seed)`, `speciesBase(sp)`, `grow(v, lvl)`, `founder(p)`, `villager(v, extra?)` (`extra`: its home's comfort, from `Expedition.fighter`), `fxOf(sp, muts?) -> Fx` (its passive and mutations), `applyFx(f, fx)` (hp atk def spd times 1 + the share, at least 0.3), `pal(x, extra?)` (its species' base grown to its level, then its `fxOf` and the extra effects), `wild(sp, lvl, i, boss, name?, boost?, muts?)` (its passive and the mutations it was born with, kept on the fighter), `new(foes, boss, party?, rng?)` (paused; the timers a little way in), `alive`, `fillTime(f)` (`AtbTime x 2 x AtbRef / (AtbRef + spd)` within `AtbMin .. AtbMax`), `EVENT_SECS`, `moveOf(skill?)`, `playTime(events, from?)` (how long they play on screen, times `ActLock`), `crowd(party, foes)` (at least 1: how much slower every timer fills in this fight, the actions the timers ask for a second times a plain attack's play time over `AtbShare`), `step(party, b, dt, rng) -> (events, result?)` (in slices of 0.05 s: the timers fill (also while an action plays; each in `fillTime` x `crowd`), the skill points charge `SpRate`, the shields wear off; one full timer acts (the party first on a tie) when no action plays: an attack, or every `SkillEvery` its skill; its timer starts again and `lock` = the action's `playTime`; `undo` holds the state from before it until `lock` runs out), `treatChance(foe, party, boss)`, `fleeChance`, `snack(party, b, target, rng, sure?)` (an action still playing (`undo`) is cancelled first: its hp, attack, charge, timers and shields put back and a `cancel` event `{ by, hp }`; then the leader's timer again, a treat event, the wild one a friend as its chance says, always with `sure`; blocked on a guardian or with the leader down, not_found), `flee(party, b, rng)` (blocked on a guardian; a miss starts the leader's timer again), `useSkill(party, b, who, id, target?, rng)` (Data/Skills: not_found, locked (not learnt at their level), sp (not enough points); its events `skill` first, then `hit` (with the skill's id) `heal shield revive rally haste dizzy`; the user's timer again), `gauges(party, b) -> { g, lock, paused, sp, crowd }`; events `hit heal shield rally treat flee skill revive haste dizzy cancel`, results `win lose fled` |
| `Breed` | the Hatchery (GAME_DESIGN 6.1): `child(a, b) -> sp` (a pair of one kind its kind, else the kind (no legend unless both are) of power nearest their average; the commoner, then the first id, on a tie), `cost(sp) -> (food, turns)` (`BreedFood`, `BreedTurns` by its rarity), `inherit(ma, mb, rng) -> muts` (shared: always, the better tier, `BreedTierUp` one better; one parent's: `BreedKeep`; `BreedNew` a tier 1 or 2 of a new family; the best four), `eggAt(p, uid)`, `start(p, uid, a, b, rng)` (not_found, egg, bad_payload, food; the feast paid, `p.eggs` + 1), `turn(p) -> { Pal }` (each egg a turn nearer; a ready one hatches into a free nest at level 1: `seen` 2, `stats.hatched`; else waits) |
| `Quest` | the questline's rules (GAME_DESIGN 9): `Facts` (`{ folk, pals, pieces, tier, pouch, islets, seen, stats }`: a profile's, `facts(p)`, or the client view's, same names), `count(facts, goal)` (how far: driftlings or villagers at work, pieces at level 2+, path tiles, decor, pieces of a kind, the stats' counts, wild places cleared (`islets`), the tier, the pouch's level, kinds in the Index), `current(tut, i) -> (Quest?, i)` (none while the tips are on, or past the last), `progress(facts, q) -> (have, need)`, `done(facts, q)`, `claim(p)` (not_found, not_done; the reward paid, `p.quest` + 1; data `{ id, shells, food, wood, next }`) |
| `Sites` | the wild places coming up on the island (GAME_DESIGN 7; Data/Sites): `spawn(p) -> { Piece }` (the places of every tier reached and not yet done, `p.wilds` counting the tiers done (then set to `p.tier`): each a `wild_<id>` piece at rotation 0 with its `SPAWN` level as `lvl`, on the grass where its footprint fits (`Plot.fits` with `loose`) and its ring is clear of the other places' rings; the best spot by a score: nothing standing in its ring first, then the land that tier gained, then far from the island's middle, with a little of the seed's chance (`sea`, the tier, its order); a place with no room left is passed over), `pieceOf(p, uid) -> (Piece?, index)` (a place, wild or cleared, by its uid) |
| `Expedition` | expeditions into the wild places: `fighter(p, key)` (a villager or driftling with its home's comfort on health, attack and defence), `away(e)`, `supplies(n)`, `kindsAt(lvl)`, `speciesAt(lvl)`, `chart(lvl, seed, kindId?) -> Isle` (what a place holds; the same level, seed and kind make the same one: its kind `kindId` (a Data/Islets id), else one of those open at the level, a name (a word of its kind's and the place's own name, "Echo Cave"; two of its kind's words without a place), every driftling of its kind and a common or uncommon stray from any open kind, a titled guardian from its kind's rares and epics, loot and reward from `Tuning.Isle*`), `isleOf(p, q) -> Isle` (a place's piece: `chart` at its `lvl` and its islet, the seed from `sea` and its uid, `id` its uid), `nodesTo(isle, count?)` (the place's path, `count` unused: the landing, then `BossEvery - 1` stops from the seed with at least three battles and maybe a rest, then the guardian, the last), `pickWild(isle, rng) -> sp` (a wild one by its rarity's weight), `nodesOf(isle)` (the same path), `stageOf(node)`, `guardianAt(node)` (1 the guardian's node, 0 none), `climbOf(isle?)` (its level over `ClimbFull`, at most 1; 1 without a place), `levelAt(isle, node)` (a level under the place's at the first stage, `StageLvl` times the climb more every stage), `boostAt(node, isle?)` (`StageBoost` times the climb a stage), `guardianBoost(isle)` (a low place's guardian's share of `BossBoost`: (1 + (BossBoost - 1) x climb) / BossBoost), `rewardOf(isle, first)` (the guardian's: the place's reward times `FirstClear` the first time, `ReplayReward` on a later trip), `start(p, isle, members)` (full, not_found, food), `enter(p, uid, members)` (not_found (no place with that uid), then `start` with `isleOf`; `e.site` = uid), `next(p, e, rng)` (`{ kind, node, food?, wood?, shells?, foes? }`; the loot times 1 + `StageLoot` a stage, the wild ones at `levelAt` and `boostAt`, each born with `Traits.roll` (a guardian a rarity up and a level up); in a place under `ClimbFull`: no level up for the guardian or the others, mutations capped at a family's first tier, a rare or rarer wild one alone, the guardian at `guardianBoost`; in_battle, no_exp once over or past the guardian), `room(p)`, `tick(p, e, dt, rng) -> out?` (the battle runs on; nil when nothing happened), `snack(p, e, target, rng)` (blocked on a guardian, no_snacks, no_room; one of `e.snacks`; sure on the tips' fight and catch steps, `tut` 6 or 7; a friend keeps its mutations, `Traits.clean`) (the tips: setting out moves `tut` 5 to 6, a battle's end 6 to 7, a friend made 6 or 7 to 8), `skill(p, e, who, id, target?, rng)` (`stats.skills` + 1), `flee(p, e, rng)`, `pause(e, on) -> (ok, gauges)` (each with what came of it, `out` = `{ events, result, snacks, friend?, xp?, shells?, ups?, reward?, guardian?, first?, cleared?, charted?, loot?, gained?, g?, lock?, paused?, sp?, crowd? }`: the guardian beaten clears the place and ends the trip: `rewardOf` added to the loot (`reward`, `guardian` = 1, `first`: the place was still wild), on a first clear the piece turns `done_<id>`, `islets` + 1 and `cleared` = its uid; `charted` = `islets`, `stats.cleared` + 1, `beaten` = 1, `over` = "won", and `out` carries `loot` and `gained` (the Cleared card); the timers while it goes on), `snacksFor(p)` (`SnackBase` x the pouch's level), `upgradePouch(p)` (`PouchCost`: money, wood, max), `home(p, e)` (any time, a battle included (it is dropped); all the loot, after a defeat too: no penalty; `over` kept, else "home"). A win adds its xp and level-ups to `e.gained` (and in a place under `ClimbFull` everyone gets back `CatchBreath` x (1 - climb) of their health); a defeat's `out` also carries `loot` and `gained` (the Expedition Complete! card) |
| `Schema` | `VERSION` (9: the wild places; 8 -> 9 drops the boat and the chart), `default(now, seed)` (a random `sea`, `wilds` 0, then `Sites.spawn`: the first tier's places, a tide pool and tall grass), `migrate(raw)` (1 -> 2: a founder; 2..4 -> 5: the studio gone, the founder, settings and start kept; 5 -> 6: the tips' steps moved (3 -> 5, 4 -> 6); 6 -> 7: each driftling rolls its mutations once, seeded by its kind and id; 7 -> 8: the questline (reconcile starts it at quest 1 with no skills counted); 8 -> 9: `boat` and `chart` gone, `wilds` 0, the count of islands charted kept as `islets`), `reconcile(raw, now, seed)` (any table -> a valid Profile: pieces that exist with unique uids and valid turns (the places outside the piece limits, their `lvl` 1 .. `LevelMax`), then `Plot.refit` (one off the grass moves onto it) and `Sites.spawn` (an older save gets every tier's places), villagers and driftlings with unique ids working only where they may (a driftling's `muts` through `Traits.clean`), the Index's species, `nextId` past every id, `sea` a whole number in range, `wilds` 0 .. the tier) |
| `Validate` | `ACTIONS` (the action catalogue, §7.3), `request(action, payload) -> (ok, err?)`: exact schemas, unknown and missing fields refused |
| `Numbers` | `int`, `short`, `coins`, `rate`, `perMin` ("+57/min"), `oneIn` |

Models (`src/shared/Models`, Roblox modules):

- `Blocks` (copied): `part(parent, spec)` (anchored, SmoothPlastic or Neon, sizes on the 0.25-stud grid, palette
  colours), `cylY`, `model`, `color`, `snap`. `pace(fn?, every?)`: from the thread that calls it, `part` calls `fn` (a
  `task.wait`) after every `every` (60) parts, so a big build spreads over frames; other threads are never paced;
  `pace(nil)` ends it (PlotService's next islands).
- `CharacterModels.build(look, name, seed) -> Rig` (a seated chibi, the portraits'; the head's parts with a glint in
  each eye, brows, a mouth and ears, sizes exact to the eighth of a stud), `buildStanding(look, name, seed)` (a
  standing chibi: the founder and the villagers: soles, shoes, bare shins under shorts, a shirt with a belt and buckle,
  a collar and two buttons, sleeves, bare forearms and fists, the head raised a stud), `posePose(rig, base, Pose)`
  (`Pose { lean, twist, crouch (the knees bend to keep the feet down), lift, hipL/R, kneeL/R, armL/R (CFrames about
  the shoulders), elbowL/R, head, mood }`; moods `calm fierce shout hurt happy ko` move the brows, open or shut the
  eyes and the mouth), `poseStanding(rig, base, t, speed)` (the walk: knees and elbows bending, or the stand),
  `poseAction(rig, base, t, speed, action, k?)` (`cheer hurt swing reach pet cast jump sneak dance`, for the
  battles `windup strike guard throw run victory ko`, and the island's work, each a loop with `k` the beat's phase:
  `dig pick fish chop saw sell serve hammer train tend`), `WORK_HIT` (where in a beat a work's blows land:
  `{ [action]: { phase } }`), `STAND_TOP`.
- `Blocks.windy(root)`: the wind's tags for the pixel filter (§9.3): every part named `Flag...` or `Pennant...` (not
  a `...Pole`) gets `PixelWind` 2, every part in `leaf` or `leaf_dark` `PixelWind` 1 (water parts left alone). Called
  by `StreetModels.land`, `DecorModels.build` and `MicroStage` on their models.
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
- `DecorModels.build(id, at, lvl?) -> Model` (every building and piece of decor; `at`: the footprint's centre on the
  grass, turned; each with its doors, windows, ridged roofs with eaves and its own props (crates, barrels, sacks, pots,
  fences, lamps); a lamp and a pennant (`PennantPole`) at Lv 3; the pier's pond and the fountain's water `PixelWater` 2; parts don't
  collide; `Blocks.windy`), `has`. The wild places (`SITE`, a builder a Data/Sites kind, `(m, f, wild)`): a tide pool,
  tall grass, a bog, a volcano, a cave, a frost peak, a windy bluff, a coral pool and old ruins, each a small landscape
  in its footprint (their pools `PixelWater` 2); a wild one has a pair of glowing eyes in its dark heart, a cleared one
  no eyes, a tamer look and a planted `Flag` on a `FlagPole`; `build` gives a place's model the attributes `Site` (its
  Data/Sites id) and `Wild` (true while wild), no pennant (its `lvl` is the place's level).
- `MicroModels` (the driftlings and the stages' things): `build(kind, opts?) -> Thing` (`{ model, parts, rest, sizes,
  baseRest, baseSize, colors, h, r, kind }`, a few palette parts round the origin, facing +Z), `driftling(shape, body,
  accent)` (the 14 shapes `blob crab bird bun lizard owl pup mole bat yeti seal sprite jelly wyrm`), `sailboat`,
  `ship` (a boat from `BoatSpec` at `opts.level`: its origin on the waterline; StreetLife's boats), `flutter(thing, t)` (a
  thing's `Flag...` parts ripple: their depth and height step through four frames), ambient kinds (`bird
  butterfly light flame crab ...`), `slab`, `grid`, `hoop`, `aim` (the battle's ring round the one acting), `aimpath` (the
  arrow to the pick: `AIM_DASHES` dashes `D1` .. and `HeadL` / `HeadR`, laid out by the screen every frame), `aimring`
  (the ring under the pick: `AIM_RING` bars, laid out by the screen) (all Neon), `place(t, cf)`, `scale(t, k)`,
  `recolor(t, color?)`, `show(t, on)`, `has`. Parts keep their sizes to the eighth of a stud (about an art px), not
  Blocks' quarter. `driftling(shape, body, accent)` is `DriftModels.build` (below); `animate(t, time, mood, k?)` hands
  a driftling (`t.rig`) to `DriftModels.animate` with the squash of `scale`, and moves the other things' limbs by name
  (`Wing*` flap, `Tail*` wag, `Eye*` blink...: the stages' gulls and butterflies; MicroStage's `circler` turns a
  bird the way it flies, on a drifting, swelling loop with a smaller one riding on it, rising and dipping, some round
  one way and some the other, gliding now and then, `flap(t, cf, phase, glide?)`). WorldView and the islet's screen
  call it every frame.
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
  beating, quick wags), `nap` (low and breathing slowly, eyes shut, head down, wings folded) and `hop` (training
  hops). Later segments of a tail
  or wing swing less (the tip doesn't whip round). `Eye*` shut by size (their shines tucked behind), `Mouth` opens.

## 7. Server

### 7.1 Remotes (`Net`)
`ReplicatedStorage.Remotes`: `Request` (RemoteFunction, C->S `(action, payload) -> Response`), `Signal` (RemoteEvent,
C->S `(kind, payload)`; no handlers in this version), `State` (RemoteEvent, S->C the whole `ClientView` when it
changed), `Fx` (RemoteEvent, S->C `{ kind = "tick", shells, food, wood, dayFrac }` every second, `{ kind = "turn",
movedIn? (the Villager), trained?, hatched? (the Pals hatched: Breed.turn) }` at each turn's end, `{ kind = "day", day }` at each of the sea's days, `{ kind = "exp", step = "node" | "act" | "timers" | "home", data }` (act: a timed battle's action as it happens, its `out`; timers: the timers as they stand, twice a second while it runs) for each
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
| `plot.place` | `id x z rot` (coords whole studs in [-64, 64], rot a quarter turn) | `Plot.place`, the buildings rebuilt by difference, the tips | locked, full, money, wood, wild (in a wild place's ring), blocked, bad_payload (a place's id) |
| `plot.move` | `i x z rot` | `Plot.move` | wild (a wild place, or a spot in a ring), blocked, bad_payload |
| `plot.paint` | `id cells` ("x,z;x,z": 1 .. 40 cells, whole studs in [-64, 64]) | `Plot.paint` (data `{ placed, skipped }`), the buildings rebuilt | locked, full, money, wood, wild, blocked |
| `plot.unpaint` | `cells` | `Plot.unpaint` (data `{ removed }`), the buildings rebuilt | not_found |
| `plot.replace` | `i`, `id` | `Plot.replace` (data `{ i, uid, id }`; the island's pieces rebuilt) | bad_payload, locked, money, wood, blocked, no_room |
| `plot.store` | `i` | `Plot.store` (clear away) | busy (the place the party is in), wild (a wild place), no_room, egg (a Hatchery holding an egg), bad_payload |
| `breed.start` | `uid`, `a`, `b` | `Breed.start` (an egg at the Hatchery `uid` from driftlings `a` and `b`) | busy (a parent away), not_found, egg, food, bad_payload |
| `island.expand` | - | `Island.expand`, the island rebuilt with the new wild places (data `{ tier, moved, cleared, sites }`) | busy (an expedition under way), max, money, wood |
| `folk.work` / `pal.work` | `id uid` (0: rest) | `Island.setWork` / `setHelp` | not_found, bad_payload |
| `folk.dismiss` / `pal.release` | `id` | `Island.dismiss` / `release` | busy (away), not_found |
| `exp.start` | `site party` (a wild place's piece uid, wild or cleared; "v3,p7": up to three, "" the captain alone) | `Expedition.enter`, the session keeps it (data `{ isle, site }`) | busy, not_found (no such place, or a member), full, food, bad_payload (a member twice) |
| `exp.next` | - | `Expedition.next` (Fx exp node) | no_exp (none, the trip over, or past the guardian), in_battle |
| `exp.snack` | `target` ("w<i>") | `Expedition.snack` (Fx exp act) | no_exp, blocked, no_snacks, no_room, not_found |
| `exp.skill` | `who` ("f", "v<id>", "p<id>") `skill` (an id) `target` (a fighter's key or "") | `Expedition.skill` (Fx exp act) | no_exp, not_found, locked, sp |
| `exp.flee` | - | `Expedition.flee` (Fx exp act) | no_exp, blocked |
| `exp.pause` | `on` (true / false) | `Expedition.pause` (data: the timers) | no_exp |
| `pouch.upgrade` | - | `Expedition.upgradePouch` (data `{ pouch, snacks }`) | busy (away), money, wood, max |
| `exp.home` | - | `Expedition.home`, the session lets go (Fx exp home; data `{ got, over, befriended, isle (its name), site }`); any time, mid-battle too | no_exp |
| `founder.set` | `skin hair style shirt` | `Island.setFounder` (the `Founder` attribute follows on the next sync) | bad_payload |
| `settings.set` | `k` ("pixel" or "music"), `v` | the pixel tier (high, medium, low, off) or the music (on, off) | bad_payload |
| `tut.next` | - | the tips go away for good | - |
| `quest.claim` | - | `Quest.claim` (data `{ id, shells, food, wood, next }`) | not_found, not_done |
| `char.home` | - | PlotService puts the founder on their path | cooldown (`Tuning.HomeCooldown`), not_ready |

### 7.4 `IslandService`
Registers the actions above. `step(dt)` (Main's fixed 10 Hz step), for every ready session: `Island.step` (those away
left out), the view sent when the food runs out or comes back, a turn every `TurnSeconds` (`Island.turn`, Fx "turn"),
a day each time the sea's clock passes a day's end (`WorldClock.dayIndex` past the session's `dayIndex`:
`Island.newDay`, Fx "day"), the stores every second (Fx "tick" with `WorldClock.dayFrac`: the whole view is not sent
for them). `WorldClock` (server): the sea's clock, `os.time()` at start advanced by every step (`now`, `advance`,
`shift(seconds)` for the sims and previews, `dayIndex`, `dayFrac`); a day is `Tuning.DaySeconds` (4 hours). `leaving(s)`: an expedition under way comes
home with its loot (on leave and at shutdown). Nothing happens while the player is away. A battle's `out` with
`cleared` (a wild place cleared, from a move or from `step`'s `tick`) rebuilds the island's pieces
(`PlotService.buildDecor`: the place's model is its cleared one, its ring gone).

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
the attributes `Tier`, `Day`, `Charm`, `Islets`, `Folk` (a villager a `;`-separated `id.skin.hair.style.shirt.work.away`),
`Pals` (`id.species.work.away`), `Sailing` (an expedition under way: the old name kept), and the player's `Founder` (`skin.hair.style.shirt`) and `Plot` (Main syncs
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
failure), `Schema.reconcile`, build the island, ready, send the view; leave -> `IslandService.leaving`, save with the
lock released, free the plot; autosave every `Tuning.AutosaveSec`; BindToClose brings expeditions home and saves
everyone. Without DataStores (Studio without API access) saves live in memory and a warning says so. A new save shape
needs a `Schema.VERSION` step in `migrate` and a spec that an older profile still loads.

## 8. Client bootstrap and the mirror

`Main.client`: the loading card's `show()` (ReplicatedFirst's, nothing when Boot put it up), `StateClient.init`
(remotes), `PixelRenderer.init` (lighting), `CameraController.init`, the card's phase "island", wait for the first
view, `CameraController.start`, `PixelRenderer.start`, `DayLight.start`, `UIKit.init`, `WorldView.start`,
`AvatarView.start`, `StreetLife.start`, `Hud.start` (which starts `Menus` and `ExpeditionUI`), then the card's phase
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
from the card's one Heartbeat: stills; the fire, the boat (drifting right, wrapping), the blinking pool, the cheering
villager (a burst, a rest), walkers (up and down a lane, a pause at each end, `walk_*` left and `walk_*_r` right),
followers (a driftling `gap` px behind its walker), gulls, stars, crests and glints (a run, hidden, a new spot: open
sea at least 26 ground px past `shoreR`, or the sun's path as wide as its lines at that row), embers.
The words: `textImage` rasterises a line with `PixelFont.mask`
(the title in `BIG` with the "title" under layer and `PixelFont.smooth`'s anti-aliasing steps, the status and the tip
in `SMALL` with a drop shadow) into an EditableImage, centred on the canvas; the status's dots and the bar are Frames.
Without EditableImages (`fallback`): Frames and an Arcade TextLabel. `LoadingArt` (generated: `W`, `H`, `palette`,
`seqs[name] = { w, h, ax, ay, dur, at, pal, px, base?, head?, flame? }`): `walk_a`, `walk_a_r`, `walk_b`, `walk_b_r`,
`cheer`, `crab`, `crab_r`, `bun`, `bun_r`, `gullfin`, `gullfin_r`, `fire`, `palm`, `palm_b`, `hut`, `tent`, `torch`,
`flowers`, `bush`, `pool`, `boat`, and the hand-made `gull`, `star`, `crest`, `ember`, `glint`.

### 8.1 `StateClient`
`init`, `view() -> ClientView?`, `waitView`, `Changed: Signal<ClientView>`, `Fx: Signal<msg>`, `Tick:
Signal<ClientView>` (Fx "tick": the view's `shells`, `food`, `wood` and `dayFrac` are patched in place, no whole view
comes), `request(action, payload) -> Response` (never errors), `signal(kind, payload)`.

### 8.2 `DayLight` (the day and night)
`start()`: the view's `dayFrac` (each tick and view; run on smoothly by `Tuning.DaySeconds` between them) sets
`PixelRenderer.setGrade(at(frac))` every frame, on the islands and on an islet's stage alike (with the filter off,
`Lighting.ClockTime` instead: 6 at dawn, 18 at dusk). `at(frac) -> Grade?`: the day's keys (`KEYS`: dawn 0, morning
0.07, afternoon 0.6, dusk 0.68, twilight 0.75, night 0.81 to 0.95, dawn again at 1), the step between two keys in
`STEPS` (6) steps; nil when it is plain daylight. `frac()` (the time of day now: the HUD's music), `hold(grade?)` (a grade held over the clock's: an
expedition's aiming greys the picture; nil lets go), `debugSet(frac?)`
(previews: a fixed time), `debugState() -> { frac, grade, clock }`.

### 8.3 `Audio`
`play(name, opts?) -> boolean` (opts `{ volume, pitch }` times the event's; a voice not loaded yet is asked to load
so the next play is on time), `preload(names)` (every voice of those events made and loaded now, on its own thread:
`ExpeditionUI.init` loads the battle's, so a swing or a blow is never heard late), `has(name)`, `EVENTS`: every sound by
name (`click open close deny notice ding coin coins combo sparkle cheer trumpet tick flip pop`; the happy moments,
each its own library sound since 2026-11-12: `newcomer` (`DoorChime`), `victory` (a place cleared: `BellTree`), `grow`
(`BellTreeRun`), `friend` (befriended or hatched: `ChimeCluster`), `level_up` (`SparkleTones`), `reward`
(`Triangle`), `drumroll` (a guardian: `DrumRoll`), `egg` (`MusicBoxWind`), `rare` (an epic or legendary wild one:
`SparklePass`); the founder's feet (AvatarView, Voyage's walk): `step_grass step_sand step_wood` (two or three takes
each, `ids`), `jump`, `land`), the battles' `whoosh whoosh_heavy hit hit_heavy body_fall zap heal shield poof bite` (the blows soft: about half
the old volume since 2026-11-11, "make a less loud sound for attacking"),
the world's `chest splash hammer horn gull birds`), each one `Monetization.Sounds` id (0 =
silent), or a few takes (`ids`: one voice each, picked at random, never the same twice running), with a volume, a
pitch range, a cooldown (a repeat inside it is dropped), a few voices and maybe a stretch of the clip (`from`, `len`:
the hammer's first two taps, the door chime's first ding-dong; its last `fade` seconds tweened down, a fade still
running cancelled when the voice plays again; the voice stops when it is over) (Sounds in `SoundService.UISounds`,
reused). `playCount(name)`: how many times an event has played on this client (the sims: the footsteps). `ambience(name, volume)`: a looped sound (`waves`, `crickets`) faded toward a volume
(DayLight: the surf always, crickets at night). `music(mood?)`: the background music, a mood's playlist of
`Monetization.Music` ("day", "night", "sea"; nil: quiet) shuffled once and played round, track after track
(`Music_<mood>` Sounds at `MUSIC_VOL` (0.2) times the track's `gain`); a change of mood and each track's last `MUSIC_FADE` seconds crossfade (a track
that ends early hands on at `Ended`); a mood still fading out fades back in when asked again. `setMusicOn(on)` fades
it all away or back; `musicState() -> { mood, on, tracks }`. The HUD sets the mood every frame (sea while the islet's
screen is open or the walk in or home plays (`Voyage.isPlaying`), night from 0.74 of the day to the dawn, else day) and `on` from
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
`setFocus(p?, snap?)`: a cutscene's world point the pan keeps in the middle instead of the founder (`Voyage`), nil gives the
founder back; `snap` jumps there at once (behind the blinds) instead of gliding. `settled()`: the pan has reached its
target. `refit` on a new key starts the pan on the target (the founder or the focus), not on the island's middle.
A new tier's cells and the next one's are worked out 3 s after the view's tier changes (`Street.warm`).
`gridAt(px, py)` (the grid at a pan), `centerWorld()` (the view's ground centre now), `view()`, `refit()`,
`ViewChanged` (a new key: a new bake), `pixelK(size?)`, `setPixelLimit(h, classic)`. The Roblox camera is posed on the
pan now: far away at `CamFov` with the filter on, at `CamOffFov` in the classic style.
**Stage mode** (a microgame): `setStage(Stage?)` with `Stage = { name, origin, pts, tight?, top, bottom }` fits the
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
`watchStage(root)` (a stage's static parts that come or go while it is in view re-cast their rects; a rect over one
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
- **A battle's spotlight** (GAME_DESIGN 7; `setDim(k)`, `debugDim()`): the static picture darkened by `dim` (0 .. 1,
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
  warm light in three stepped rings (`RING`, twice as wide as tall: the ground at 2:1),
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
`lineHeight`, `plate(parent, size, pos?, color?, alpha?, corner?, style?)` (stepped corners with a 1 px ink outline
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
The islanders: a walker per villager (`CharacterModels.buildStanding` in their look) and per driftling
(`MicroModels.driftling` in its species' shape and colours), parsed from each owned plot's `Folk` and `Pals`
attributes (those away left out) and placed among the buildings read from its `Static.Decor` models' names
(`uid:id:x:z:rot:lvl`). Villagers walk to their building and work there (`WORK_ACTION` by building id: `poseAction`'s
work loops at `WORK_RATE` beats a second, from a phase of their own; at each `WORK_HIT` moment near the view the
blow's chips fly, `WORK_CHIPS`: soil, wood, sparks, a splash, a coin, dust, from `WorkBits`, a pool of 40 parts
registered once), wander the grass when resting (`strollPoint`: a buildable cell away from the campfire); driftlings
go to the building they help at (or a nest) and work there by its kind (`palMoodOf`: `peck` in the fields, `dip` at
a pier or kelp farm, `push` at the wood and the boosts, `wave` at the shops, `hop` at the yard, `nap` at a nest or
the hatchery, for longer: `DriftModels.animate`'s work moods). Workers stand along the building's front (a villager
in one of three places by id), turned three-quarters to the view (east or south). Only islands within 100 studs of the view's centre are drawn (synced every half second); each
near owned island's campfire gets a flickering flame and rising smoke (`fireOn`, dynamic models). Each island's sign gets
a World-root label (its name, the own in gold, or "Unclaimed isle"); a tap (a press let go within 8 px, not on the
interface, not in Build mode; its ray `PixelRenderer.screenRay` in the `PixelRays` collision group, as the
picture's, so it passes the invisible coast walls, which Roblox hits whatever their CanQuery says because they collide)
on a sign shows `signCard(i)` (the day, villagers, driftlings, charm, wild places cleared).
**The wild places** (GAME_DESIGN 7): over each wild one on the own island (a `Static.Decor` model with the `Site`
attribute and `Wild` true; none in Build mode) a World-root label `Site_<uid>` ("Tide Pool Lv 1", orange) above its
model; while the tips are on steps 5 and 6 (no trip under way) the `arrow_down_t` sprite bobs over the lowest wild one
(the Tide Pool on a new island). A tap on a place of the own island, wild or cleared, opens its card
(`UIKit.openPanel("site", uid)`, the uid from the model's name) before the signs are looked at. A newcomer
(Fx "day" `movedIn`) gets a welcome word and confetti, a hatchling (Fx "turn" `hatched`) a cheer, its name and pink
bits; `cheer(words, color)` makes the own islanders cheer.
`rigCount()` / `ownRigCount()` and `tapScreen(pos)` (a tap at screen px, handled as a player's) for the sims.
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
greyed while off), the menu bar (`Menu_build`, `Menu_folk`, `Menu_pals`, `Menu_index`, `Menu_looks`,
each with its icon; no Explore button: the player taps a wild place on the island; while Build mode or the islet's screen
is open the bar and the cards step aside (the cards also while a wild place's card is open), the tips only
for the islet's screen: in Build mode the banner rises over the tray with a Build mode wording (`TIPS_BUILD`)), the
`IslandCard` on the
right (the island's name for its tier, villagers / beds, driftlings / nests, visitors, charm, and what a day makes of food, wood and
shells a minute: `Numbers.perMin`), the `ExpCard` under it while an expedition is under way (`mini_wild`, the place's
name, `State`: "Stage n of m", "In a fight" or "Cleared", `ExpContinue` pulsing: `ExpeditionUI.open`; on a phone at the top left), the questline's card `Quest`
(GAME_DESIGN 9: down the left at `CARD_Y`, `QUEST_W` 150, under the `ExpCard` on a phone; hidden while the tips are on,
for an expedition and for a panel; `updateQuest(v)` from the view through `Quest.current` / `Quest.progress`, laid out
again when the quest or its count changes, sliding in: the quest's `mini_` icon, `Title`, `Which` ("3/20"), `Words`,
then the `Bar` and `Progress` with `QuestGo` (`goTo(go)`: a panel, "site" a wild place's card (`openPanel("site")`
with no uid: the place last shown, else `Menus.defaultSite`) or the trip under way, or
`BuildUI.open(tab)`), or once done the reward (`Reward_<store>`) and `QuestClaim` (shining; `quest.claim`, then a
notice of what it paid)), the tips banner (`Tips`: the steps of GAME_DESIGN 9 (`tut` 1 .. 8: food, wood, shells, a tent, a nest and the Tide Pool,
exploring it and the first fight, catching, the last; `TIPS_AWAY` while an expedition waits); tip 8 has `TipsOk`, sending `tut.next`; a parchment note in a thin frame; on a phone it keeps to the room left of the island card, wrapping to two lines), and the `DayBanner` (Fx
"day": the day and who moved in or trained; over a panel, Build mode or an expedition a notice instead). Shells
coming in rise from their chip ("+12", at most every 2 s, from `StateClient.Tick`). Every frame it holds the
founder's `JumpHeight` at 0 while Build mode, the islet's screen, the walk in or home (`Voyage`) or a panel is up, else `Tuning.JumpHeight` (the
phone's jump button hides with it), and sets the music's mood (`Audio.music`). It reports its blocks to the
camera (on PC the top strip, the menu bar and the card's place; on a phone Roblox's top bar and the menu bar).

### 10.4 Menus
`Menus` registers the panels: "folk" (a row a villager `Folk_<id>`: portrait, name, level, job or "Resting" or "Away
on an expedition", battle stats (with its comfort), its home (`Home`: "Home: Villa, comfort +18%", or "No bed"); `Job_<id>` opens the picker (the same panel with `{ folk = id }`: a row
`Spot_<uid>` a building that takes workers, `Go_<uid>` Go / Swap / Here, `Go_0` Rest, `Back`), `Dismiss_<id>` (two
taps: "Sure?")), "pals" (`Pal_<id>`: portrait, name in its rarity's colour, level, skill, passive, mutations
(`Mut_<id>` each, or "No mutations"), where it helps, stats and its nest (`Stats`); `Help_<id>` the picker of the buildings of its knack,
`Release_<id>` two taps; `OpenHatch` when a Hatchery stands), "hatch" (a row a Hatchery `Hatch_<uid>`: its egg
(`egg_<rarity>`, `EggName`, `EggLeft`, `EggBar`, its parents) or the slots `Slot_a_<uid>` / `Slot_b_<uid>` (the
picker: the same panel with `{ hatch = uid, slot }`, a row `Parent_<id>`, `PickParent_<id>`), the likely child
(`Child`: its portrait if met, else its shape and ???, its rarity), `Cost`, `Breed_<uid>`), "site" (a wild place's
card, "Wild place", GAME_DESIGN 7; `arg` the place's piece uid from a tap on the island (WorldView), none for the
place last shown, else `defaultSite(v)`: the lowest wild one, else the lowest cleared one; `NoSites` when the island
has none). On the left the place, `Expedition.isleOf` on the view: `SiteName`, `SiteKind` (its Data/Sites name and
level, coloured against the captain's), `SiteBlurb`, `SiteState` ("Wild. Nothing can be built close to it." or
"Cleared. You can move it or clear it away in Build mode."), `Reward` ("First clear:" or "Clear it again:" and
`Expedition.rewardOf(isle, wild)`), `LivesHere` and its wild ones' portraits (two rows at most; silhouettes for those
not met), `Guardian` (its portrait and name), `PathLength` (the stops to the guardian), and at the bottom the snack
pouch (`Snacks`, `PouchShells` / `PouchWood` (red when short) and `PouchUp` sending `pouch.upgrade`, off while away;
`PouchMax` "The biggest pouch" at the top). On the right the party (`PartyHint` "Party n/m (you always go)"; its slots
fill themselves with the strongest, `rankMembers`: level, then health, each time the card opens; `Member_f` the leader
always, `Member_v<id>` / `Member_p<id>` picked up to `PartyMax`, the strongest first), `Supplies` and `Explore`
(sends `exp.start { site, party }`, then `ExpeditionUI.enter(uid, keys, isle)`: the walk in; "Back to the expedition"
while one is under way: `ExpeditionUI.open`), "index" (`Entry_<species>`:
portrait or silhouette, name or "???", the kind of island it lives on, a heart once befriended, its blurb; "Met n of 15")
and "looks" (the founder's portrait, `Prev_<k>` / `Next_<k>` for skin, hair, style and shirt, `SaveLook` sends
`founder.set`). `Menus.party()`, `Menus.chosen()` (the uid of the place whose card is open), `Menus.defaultSite(v)`
for the sims. `Words.errText(err)` words every ErrCode (`wild`: "Too close to a wild place. Clear it first.").

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
bottom (a workbench in a frame of planks, `wood = 3`, its tabs on a `plank`; the cards carved boards): the tabs `Tab_food Tab_wood Tab_shop Tab_home Tab_nest Tab_gen Tab_path Tab_decor` (their icons alone on a narrow
screen), the count (`Count`: the pieces, or the path tiles on the Paths tab, against their limit), `Expand` (`island.expand`, its price under it; the fanfare and "Your island grew." wait for `PixelRenderer.afterBake`, 1.5 s at most) and `BuildDone`; a card a piece of the tab (`Buy_<id>`:
its price in shells and wood with their icons, red when short; a locked one says the island tier it needs). With a
piece picked (`pick(id, rot?)`), a ghost model (`Ghost` in `Workspace.PixelDynamic`: the piece and its `Footprint`, a
raised neon frame of four edges just above the grass, cyan (`screen_on`) where `Plot.fits`
says it fits, red (`berry_red`) where not) stands on the cell under the pointer (mouse) or the last tap; the bar shows
`Rotate`, `Place` / `Move here`, `Replace` (when another of its kind is open) and `Store` ("Clear away")
when moving a building, `Cancel`, and the `Info` plate (what it is and makes, its beds or room and comfort, its
charm, its price or the next level's). `Replace` turns the bar to `ReplaceBack`, `ReplaceWhat` and a card a
replacement (`Swap_<id>`: its name with its beds or room, `SwapTo_<id>` with `Plot.replaceCost`), a tap sends
`plot.replace`. A tap on a placed piece of the own
island (a ray into its `Static.Decor`) picks it up; a wild place stays put (the `deny` sound and a notice that it must
be cleared first), a cleared one is picked up like any piece. The wild places' rings (GAME_DESIGN 7): while Build mode
is open `showZones` keeps a `WildZones` model in `Workspace.PixelDynamic` (four orange neon `Ring` edges just above the
grass round each wild place's `Plot.zone`, rebuilt when the wild pieces change); a pick that doesn't fit for a ring
(`wildNear(p)`: the place's name) has its `Info` line say "Too close to the <name>. Clear it first, or build further
away.". A press dragged more than 8 px pans the view
(`CameraController.panBy`). `confirm()` sends `plot.place` (the piece stays picked for another copy) or `plot.move`;
`close()`; `isOpen()`; `Changed: Signal<boolean>`; `tapScreen(pos, mouse?)` (the sims' and previews' tap). The tray
is laid out again when what can be afforded changes (`StateClient.Tick`). The tips (`TUT`: tip 1 food / patch, 2
wood / lumber, 3 shop / stall, 4 home / tent, 5 nest / nest): opening, and each new tip while open (`followTut`, from
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

### 10.8 The walk in and home (`Voyage`)
`Voyage` (client; the module keeps its old name from the voyages by boat; `init()`, empty now, from
`ExpeditionUI.init`): `play(site, isle?, onDone)` after Explore on a wild place's card (`site`: its piece uid,
`isle`: exp.start's answer). The walk ends at the spot in front of the place (`frontOf(v, uid)`: 1.5 studs off the
middle of its footprint's south side, on the grass); with another cutscene playing or no such place in the view, `onDone` runs at once. Else the
panel closes, the `Hud` and `World` roots and the touch controls hide, the character's WalkSpeed and JumpHeight go to
0, and a `Voyage` frame on the `Stage` root slides in letterbox bars (laid out against the canvas's edges, the blinds full width and three screens deep: the pixel size changes under them as the place's screen opens or the island comes back) (`BarTop`, `BarBottom` with `Caption` "Into the
wild..." and `VoyageSkip`). Phases: "open" (0.3 s), "walk" (the own founder, posed through `AvatarView.setOverride`
(`poseStanding`), walks at `WALK` (13) studs/s from where they stand to the spot, or from 6 studs south of it when
they stand more than `MAX_WALK` (40) studs away; feet on the ground by a raycast in the `PixelRays` group; a footstep
every `5.4 / WALK` s, its sound by the ground's height (over the lawn: wood, under it: sand, else grass);
`CameraController.setFocus` follows them), "close" (facing the place, `whoosh_heavy`; the `Blind`s shut over `CLOSE`
(0.4) s with the `mini_wild` icon, the place's `IsleName`, its Data/Sites name and level), then `onDone`
(ExpeditionUI opens behind the closed blinds with its own closed curtain) and the overlay goes 0.1 s later.
`home(site?, onDone)` (the trip over: `site` the place's piece uid, `e.site`): the overlay starts with the blinds
closed on "<DisplayName>'s Isle" / "Home again." (`Caption` "Heading home..."); the character is put on the spot in
front of the place and the camera snapped there (`setFocus(spot, true)`); "wait" until 0.5 s have passed and the
renderer is `ready()` with no stage and the camera `settled()` (at most `OPEN_WAIT` (4) s), then the blinds open
from the middle and "land" (1 s: the founder cheers, `cheer`); then the character stands on the spot (WalkSpeed and
JumpHeight back, never to 0: 16 and 7.2 when they were held at 0), the HUD comes back and `onDone` (the loot's
notice). With no such place in the view (cleared away meanwhile) it does `reveal(onDone)`: closed blinds ("wait",
at least 0.3 s, until the picture is `ready()` with no stage, at most `OPEN_WAIT`) that open ("open") on the island
(while another cutscene plays, `reveal` only runs `onDone`). `skip()` (Skip, Space, Return): going in, the blinds shut at once and it finishes; coming
home, the blinds open and it lands at once. `isPlaying()`, `debugState() -> { dir ("out" | "home" | "reveal" | ""),
phase, pos (the founder's feet), spot }`.

### 10.9 The islet's screen (`ExpeditionUI`, `MicroStage`)
`ExpeditionUI`: `enter(site, keys, isle?)` (a wild place's Explore: `Voyage.play(site, isle)`, then `open`, the party
dropping in from above; `keys` unused), `open()` (the
HUD's card; right after `exp.start` it waits for the view with the expedition), `close(after?)` (the `LeaveCurtain`
blinds close over the stage in 0.4 s, then the stage goes and `after()` runs, or `Voyage.reveal()`: Back to island
(the expedition waits) and the end of one (`exp.home`: `after` plays `Voyage.home(e.site)`, then the loot's
notice and sound; it stays busy till then)), `isOpen()`, `active()`, `Changed: Signal<boolean>`, `init()` (the view's changes lay it out
again; an expedition gone closes it; the battle's Fx "exp" act messages play back in turn (`playQueue`), act and
timers messages set the timers; while they play the wild ones on the stage stay as they are (`buildFoes` waits:
a snack befriending the last wild one, or a battle's last blow, ends the battle on the server before its playback,
which still shows the throw, the hearts and the poof or the knock-out, then lays the screen out again)), and for the sims and previews `debugState() -> { open, lifted, actors, busy, node,
foes, ship, arrived (both false now: the boat arrival is unused), timers, paused, sp, snacks, aim, aimWho, aimTarget, marked, shown (the keys of those on
the stage, not gone in a poof), arrow (its dashes shown),
arrowGap (its end from the pick), menu, queue, gauge, clock (the battle clock), held (it stands still), inspect (the
key shown), leave (the leave card is up) }`, `debugInspect(key?)` (the plate on or off), `debugGo()`, `debugSnack(target?)`, `debugSkill(who, id,
target?)`, `debugFlee()`, `debugAim(kind)`, `debugPoint(key, tap) -> boolean` (the pointer over someone: a hover or a
tap), `debugScreenOf(key) -> (i, j)`, `debugHome()`, `debugWait(seconds?)` (a longer wait for
the picture: the fake engine bakes slowly). It hides the `Hud` and `World` roots and the touch controls, opens
`MicroStage.open(kind.stage, { top, bottom }, isle.seed, true)` (the camera's stage mode, the overlay's strips kept clear)
and draws on the `Stage` root (full screen: Roblox's top bar's height, `TopBar`, is kept clear; GAME_DESIGN 2's
island looks: the header and footer are dark boards, `HEAD_H` 25 and `FOOT_H` 47, each with a 3 px plank `Trim` on the
side facing the island, the footer's contents in `Footer` under its trim on the `FooterBoard`; the skill window, the
alert and the results card in frames of planks): the `Header` (the
place's name and level, `Loot_<kind>`, `Stage` ("Stage n of m"), the whole path's `Node<i>` icons (the ones ahead
hidden but the guardian's), `Here`, `BackToIsland`), the `Footer` (GAME_DESIGN 7 "the battle's boxes": the commands two by
two at its left, `CMD_W` 72 each: between stops only `SailHome` ("Head home"; the next stop comes up by itself `AUTO_GO` (0.2) s
after the last is done: `goOn`; Space at once), once the trip is over `SailHome` alone; in battle `Act_skills` with `SpBar` (the skill points) under
it, `Act_snack` ("Snack x<n>": the trip's snacks left) and `Act_flee` (both off against a guardian); aiming
`AimWhat`, `AimHint`, `Aim_use` (Throw! / Use!) and `Aim_back`; the party's boxes two by two at its right, `PARTY_W`
112), the wild ones' boxes down the stage's top left (`FOE_W` 104, those still in the battle; a new line-up's slide
in from the edge one after another, `boxesFor`; a tap on any box picks it while aiming). A box (`fighterCard(parent,
f, x, y, w, foe, badge?)`, `Card_<key>`): portrait or icon, `Name`, mutation pips, `Lv`, `HpTag` ("HP"), the bar
`HpBack` with `HpFill` and the pale `HpLost`; a party member's also `Hp` (the numbers) and `TimerBack` / `Timer`
(its timer, a line under the bar); a wild one's `Badge` beside it (`mini_boss` the guardian, `mini_nest` a kind
befriended: `view.seen` 2). `Bar { hp, maxHp, shown, lost, lostAt, hitAt, ghost, gauge, x, y, foe, out, ... }`:
`setBar(key, hp, instant?)` sets where it is going (a loss jolts the box and leaves the pale part), `updateBars(dt,
gaugeOf)` every frame drains `shown` toward `hp` (`maxHp` x 1.1 a second), the pale part after it 0.4 s later, jolts a
box hit in the last 0.24 s by a pixel side to side, fills the timers, and slides a wild one's empty box out;
`drawBar` colours the fill (green over half, yellow over a fifth, red under) and redraws the numbers a few times a
second (each new string is a new text picture), red when low; a laid-out-again box keeps its drain (`prevBars`).
A new fight's stop (no white flash since 2026-11-11) has `Say` name the wild ones ("A wild Mossbun appeared."); its
`data.sp` (the skill points carried on) sets the bar. The `SkillWindow` (`Skill_<who>_<id>`, yellow: each standing member's skills learnt, flowing from the name column
onto further lines when a row runs out of room, greyed when the points don't cover them or there is nobody to aim at;
`Skills_close`; it fits between the header and the footer, its rows in `SkillRows`, a ScrollingFrame when they don't;
a skill's tip `SkillTip` (GAME_DESIGN 7, "show what skills do while hovering or pressing onto it": its name and
cost `TipName` `TipCost`, its blurb, `skillWhat(d)` (its numbers in words), who uses it and `AIM_SAYS`; under the
button, over it near the bottom) shows while the mouse is over a skill (`MouseEnter` / `MouseLeave`) or a finger is
on it (`InputBegan` / `InputEnded`, touch); held `HOLD_SECS` it only reads (the release doesn't use it);
`debugSkillTip("<who>_<id>") -> (shown, lines)` shows it as a hover would), the timers' layer `Timers`
(`Timer_<key>` over every standing fighter's head every frame: gold, orange for the wild ones, flashing when full), the `Say` narration, a won battle's `Alert` (a small plate under the header: Victory!, its
lines, a new friend's portrait; gone by itself after `AUTO_CARD` s, no button), the `Result` card (`ResultOk`: Head
home, after the guardian or a fall) and the `Curtain` (ink blinds with `mini_wild`, the place's name, its Data/Sites
name and level until the stage is `ready()` and 1.2 s passed, at most `StageWait`; laid out against the canvas's
edges, the bands full width and three screens deep, the title and blurb centred on scale positions: the pixel size
changes under it as the stage comes up; `LeaveCurtain` the same). The actors: the founder (the stage's own), villagers (`stage.rival(look)`), driftlings
and wild ones (`MicroModels.driftling`, the guardian 1.6 times as big), posed every frame (drops, idle hops, lunges,
KO). The party drops in from above after the walk in as on a reopening (`enter` leaves `arriving` false). The boat
arrival that followed the old sailing cutscene is still in the code but never runs: with `arriving` the drop
happened behind the curtain and the expedition boat (`MicroModels` "ship", level 1 now) glided `SHIP_BACK` studs in
to moor with its bow in the foam (`SHIP_X`, `shipZ0` from `Stage.landing(SHIP_X)`, over `SHIP_IN` s; the picture
opening over it, `Stage.follow(-ARRIVE_CAM, true)`), the party on its deck (`DECK_SPOTS` from `BoatSpec.deck`)
hopping off one after another (`HOP_T`, `shipLand`) and walking to its places (`RUN` studs/s);
a round's events play back one by one as moves (GAME_DESIGN 7: `startMove(actor, kind, other?)`, `MOVES` their lengths,
`frameOf` what each does at a moment: `{ du, dv, dy, tilt, sq, spin, action, k, mood, speed }`; `attack quick bash
zap` in place (no run up to the target: "they now attack in place"): a plain attack is the fighter's own `Style`
(`styleFor(kind, sp, who)`, set on each actor as it joins: a driftling's by its shape, `SHAPE_STYLE` bounce pounce
pinch roar stomp flare tailwhip headbutt peck spin shellspin dive; the founder's punch; a villager's kick, swing,
sling or hop by name, `PERSON_STYLES`; `STYLE_BASE` the length, blows (shares of it) and what flies across at the
blow, `ranged` sparks twinkle pebble; each kind's own tempo, height and turn from `hashOf`), quick three jabs, bash a
leap and slam, zap a charge and bolt (`IMPACTS` their blows' moments); the swing is heard as it starts, the hit at
the blow), `hurt ko` (a
knock away from the attacker; `ko` flies, spins and lies down), `guard cast throw refuse happy flee stumble
victory`); a blow `freeze`s the moves (hit-stop: their clocks held) and `shake`s the picture
(`PixelRenderer.setOffset` by whole art px); the things squash by `MicroModels.scale` (whole eighths), lean by the
move's tilt and move their limbs (`MicroModels.animate` with the move's mood); the founder and villagers take the
move's action (`CharacterModels.poseAction`); keys: Space / Return go on; in battle 1 / S a snack, 2 / K the skills,
3 / F flee; aiming arrows or Tab switch the pick, Space / Return go, Escape / Backspace back. The header shows `Stage`
("Stage n of m") and the place's whole path (`Expedition.nodesOf`: the guardian's crown at its end). **Cleared**: the
guardian's fall clears the place and ends the trip (the server's `out.reward`): confetti, the fanfare and the `Result`
card "<name> cleared" ("First clear! +n shells" or "Cleared again. +n shells", "Brought home: ..." from `out.loot`,
the xp and level lines, a new friend's portrait, and on a first clear "You can build round it now, move it or clear
it away.") with `ResultOk` "Head home" (`goHome`). The party never waits before a fight. The tips' fighting and catching steps (`tut` 6 .. 8) show as a parchment note
over the footer (`TutTip`, worded for a battle, a guardian or the walk; `TutOk` on the last, sending `tut.next`; not
while aiming or in the skill window), and in the catching step the `Act_snack` button shines while a wild one is hurt.
The timed battle (GAME_DESIGN 7): the server runs it; the client keeps the timers as last told (`gaugeG` at
`gaugeAt`) and runs them on by each fighter's `Battle.fillTime` times the fight's `crowd` (the skill points by `SpRate`) between the server's
messages; the health shown follows the events (`shownHp`) until the view brings the battle's end. A new battle
(`exp.next`'s wild or boss) runs (`exp.pause` off) once its wild ones have landed (`runAt`); reopening the screen on
a battle under way runs it after the curtain; closing the screen pauses it. Aiming (`Aim { kind "snack" | "skill",
who, skill?, side "foe" | "ally" | "down" | "none", target? }`) and the skill window pause the battle and grey the
picture (`DayLight.hold(GREY)`); the one acting stands in `MicroModels` "aim" (a Neon ring on the floor, turning;
pink for a snack, cyan for a skill), "aimpath" runs from its edge all the way to the pick's "aimring" (the dashes
marching on, a dash past the end hidden) and the `arrow_down_t` pointer bobs over the pick's head; the arrow's end
glides to the pick every frame (`aimEndU`, `aimEndV`: out of the user's ring when the aim opens, over to a new pick),
so it swings and stretches, and the pick's ring pops in (`aimRingR`). The timers, the pointer and the floating words
go just over a figure's head (`headOf`: a person 4.75 studs, a driftling its model's height at its size). Picking:
the cards, the arrow keys, or the pointer on the stage (`pickAt(i, j)`: the nearest candidate whose figure, feet to
head on the screen, holds the point; `pointAt(i, j, tap)`): a mouse hovering over someone picks them
(UserInputService `InputChanged`), a tap or click picks them, and on the pick already chosen goes (`InputBegan` /
`InputEnded` within 16 px, not over a button: `PixelRenderer.pixelAt`). Throw! / Use! sends `exp.snack` / `exp.skill` (the battle runs on, its events come as the next act message),
Back sends `exp.pause` off. A skill aiming at nobody goes at once. A win's alert names the skills learnt on the way
up (`Skills.learnt`).
**The battle clock** (GAME_DESIGN 7, "a pause stops everything"): the client's moves, waits and timers run on
`bclock`, which stands still while `playHeld()` (aiming, the skill window or the leave card is up), so a blow
already playing freezes mid-swing and goes on after. `bwait(seconds)` waits on it and returns true when the playback
was cut: a snack that cancels an action on the server (its Fx comes while the old act plays) sets `cutPlay`, the
playing act stops where it is, and the next act starts with its `cancel` event (the attacker hops back to its place,
the health shown goes back to `hp`), then the throw.
**The battle view** (GAME_DESIGN 7): the places are MicroStage's (`PARTY_SPOTS`, `FOE_SPOTS`: `PARTY_XZ`, `FOE_XZ`
in u, v by `uvOf`), the party facing `FACE_FOES` and the wild ones `FACE_PARTY`; a move's offsets run along the
fighter's way forward (`fwdOf(a)`: one stud toward the other side in u, v, `FWD_U`, `FWD_V`), so a windup draws back,
a lunge goes in and a knock-back goes away along the battle's line.
**One area** (GAME_DESIGN 7: "no need to make the party walk anymore"): every stop plays out in the landing's area
(`baseU`, `baseV` 0). `goOn` (only between stops: never in a battle or once the trip is over) `regroup`s the party
(anyone down back up in their place), asks `exp.next` and plays the stop (`playNode`). A battle's wild ones come down
the trail (`buildFoes`: each a `run` from `ENTER_DIST` (16) studs up the trail to its place at `ENTER_SPEED` (12)
studs/s, 0.22 s apart; `runEnd` when the last gets there; behind the curtain they stand there already); the battle
runs 0.5 s after `runEnd` (a guardian's 1.2 s), the timers wait for it, and the line-up's key carries the stop's
number. While `walking` (the ask) Back to island stays open. `debugState` adds `area` (0), `running` (fighters still
running to their places), `behind` (members more than 20 studs behind the area's middle along the road), `foeU` (the
nearest wild one from it, along the road: ahead of it) and `dropping`; `debugAuto(on)` holds the auto Go on (previews,
sims). **The spotlight**: while a battle is on (lifted, not over, not closing), or between two fights (`fightToFight`:
the stop is a won fight and the next is a fight too), `dimNow` eases to 1 over `DIM_SECS` (0.45 s), else to 0
(`PixelRenderer.setDim`; 0 again on close).
**Quick fights** (GAME_DESIGN 7, 2026-11-11): the styles' lengths (`STYLE_BASE`, 0.4 .. 0.52 s), `MOVES` and
`IMPACTS` are about a fifth shorter, the hit-stop 0.05 s; a strike's playback ends just after its last blow
(`max(last impact, move - 0.14) + 0.04`), the swing home and the flinch going on under the next; while acts wait in
`playQueue` the battle clock runs 1.3x (one waiting) or 1.6x (two or more) until it has caught up.
**A closer look** (`inspect(key?)`): a mouse over a fighter on the stage (`fighterAt(i, j)`: the figure under the
point by the stage's `screen()` projection) or its card, or a finger held on either for `HOLD_SECS` (0.45 s), shows
`Inspect` (a plate over the figure's head, kept there every frame by `placeInspect`): name and level, rarity and
wild, `HP ATK DEF SPD`, the passive, each mutation with its tier's stars and colour. It goes when the pointer leaves
or the finger lifts; never while aiming.
**Leaving** (`leaveChoice()`, `BackToIsland` any time): the battle holds and `LeaveCard` asks "Leave the battle?" or
"Head back?": `LeaveHome` (`goHome`: `exp.home`, mid-battle too), `LeaveWait` (`close()`, the trip waits; not when it
is over) and `LeaveStay` (the battle goes on).
**The end of a fall**: the `Result` card titled "Expedition Complete!" (its width fits the big title) lists the loot
(`out.loot`), the party's xp and each member's levels (`out.gained`), then Head home.
`MicroStage` (client): `open(variant, margins?, seed?, endless?) -> Stage` (an islet set laid out by the island's seed), `current()`, `has(variant)`, the yaws `FACE_VIEWER
FACE_RIGHT FACE_LEFT FACE_AWAY FACE_FOES FACE_PARTY`, `U_DIR` (screen right) and `V_DIR` (toward the viewer), `uvOf(x, z)`
(u, v of a room-space point), the battle's places `PARTY_XZ` (four, the founder first, about 4 studs apart along u) and `FOE_XZ` (three, the
guardian first) in room space, `AREA_U`, `AREA_V`. A stage is a folder
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
**The endless islet** (`endless`, the expeditions: GAME_DESIGN 7 "the run on", "the battle view"; the name is
older than the wild places, whose paths end at their guardians): the set is built
area by area, area k a folder `Area<k>` at `AREA_OFF` x k in room space ((0, 0, -24): one floor on, so the floors meet
edge to edge into one road running up and to the right on the screen; whole studs, so every box stays on the grid),
`AREA_U` and `AREA_V` x k along u and v; each from the seed + 7919 k (the builder's `off`, `endless`), its landmark
only in area 0 (`lm`: later areas put it out of sight at `FAR_LM`: in the next area's place it would stand on this
one's floor). `room` lays no floor on an endless islet: after the set's props each area gets its **trail**
(GAME_DESIGN 7 "the trail": `trail(b, TRAIL[variant])`, the builder's `variant`): `TrailStyle { ground, patch, path,
verge, rut?, alt?, kind? ("planks" a boardwalk over mud, "flags" flagstones on a straight road), pebbles, stones,
tufts, flowers?, extra? ("shells" "embers" "snow" "coral" "reeds" "crystals" "rubble" "mushrooms"), prints? }`.
`trailAt(style, zw) -> (middle x, half width)` at a world z (the same either side of an area's edge; the island's own
bends from `trailPh`, set from the seed; a trampled clearing, wider (2.4 studs more each side) and straighter,
about 7 studs either side of an area's middle where the battle's sides stand, room for the party spread out). The land in two tones (`patchy`) as stud cells over the floor's
square and inland beyond it (the coast's distance under -1.5, wobbled), top `FLOOR`; the path's half-stud cells
`TRAIL_DIP` (0.125) under it and the ragged verge between at -0.06 (`cellAt`); then ruts, pebbles, verge stones,
tufts, flowers, footprints and the style's extra; `Builder.disc` (a standing cylinder: a clean pixel ellipse) makes
the mangrove's puddles. `trailCovers(b, x, z)`: the cells the trail lays (the square, and on area 0 the path on out
to the beach), which `shore` leaves out of its land layer so the path can sit lower. Everyone on an endless stage
stands `TRAIL_DIP` lower where the trail is under them (`standAt(u, v)`: on the path by `trailAt`, else on the land:
`place`, `pose`, the rivals; the shadows' ground is the trail's). Set features that crossed the old
floor (the meadow's stepping stones, the snowbank, the kelp's back row, a lava crack) are left out there, and the
mangrove's channel runs along the left side. A floor prop keeps off the road's middle (|x| over 6.5), a shore prop
off the neighbours' floors and the road's band, a tall one to the land beside the floor (`shoreSpot`). The camera frames the battle well back (the party's feet and heads, the wild ones', the island's sides 19 studs out
level with them: about 54 studs across the screen; "zoom out more in the expeditions even more", 2026-11-11). `Stage.landing(x) -> z`: where area 0's beach meets the foam behind the party at room-space x (the
arriving boat's bow: only the unused boat arrival asks). The sea is laid once (`SEA_AREAS`, 200 areas long: a part across the whole screen would re-bake it).
Areas 0 and 1 are built with the stage (before its first picture), the rest by `Stage.area(k)` (the areas up to
k + 2, one at a time on a background thread, `Blocks.pace` 40 parts a frame, out of sight; the ambient life moves to
area k: `ambOff`, `ambU`, `ambV`); `Stage.trim(k)` drops the areas below k - 1 (out of sight too);
`Stage.follow(units, snap?)` sets the camera's shift (`CameraController.setStageShift(AREA_OFF x units, snap)`: below
0 behind the landing). The renderer re-casts the rects of the
stage's parts that come or go (`PixelRenderer.watchStage`).

### 10.10 Sprites (`PixelSprites`, `ArtData`)
`ArtData` (generated by `scripts/gen_art.py`; do not edit): `{ [name]: { w, h, px, pal, alpha } }`, one character a
pixel (`.` clear, else an index into `pal` 0xRRGGBB with its `alpha`). How `gen_art.py` shades (GAME_DESIGN 2):
`cel_tones` over the whole silhouette (the base; a 1 px shadow along the bottom and right edges, two under a
portrait's belly; a short light on the upper half of the top-left edges of masses 3 px thick), close hue-shifted
ramps (`RAMPS`, `M` the magmole's warm basalt, `E` cream), no grain, curves inside the outline softened a step toward the
shadow; the outline is never anti-aliased on its outside. Each portrait is its body shape (`SHAPES`; the novafox's
is a `fox` of its own, its 3D model still the pup), all on one template (GAME_DESIGN 2): a three-quarter view turned
left, a big head, a narrow far eye and a 2 px near eye with a highlight (`k`, `w`), cream (`E`) muzzles and bellies,
blush (`p`); `A` the species' body ramp, `Z` its accent (`CREATURE_ICONS`), inside 14 x 14 so every icon is 16 x 16.
The overlay's sprites also have a white `<name>_flash`; the icons have a dark `<name>_sil` (not met yet); an
animation's frames `<name>_1`, `<name>_2`... share one canvas (bottom centre). The sprites: the driftlings' portraits
`icon_<species>` (16x16: a mask a body shape in the species' two ramps), the small icons `mini_<name>` (11x11: `shell
food wood sun moon charm folk pal visitor home nest train decor start loot chest wild rest boss star boat`; `boat`
unused since the Explore button went), the arrows `arrow_<dir>` (13x13) and `arrow_<dir>_t` (7x7), `note`, `heart`, `spark_1..3`, `bombfuse`. `PixelSprites`:
`has(name)`, `size(name) -> (w, h)`, `image(parent, name, pos?, z?) -> GuiObject` (an ImageLabel `Sprite_<name>`
showing the sprite's EditableImage, made once and shared, `ResampleMode` Pixelated, at the sprite's own size: no
scale; without EditableImages a Frame of 1 px run rects), `anim(parent, names, pos?, z?) -> Anim { f, w, h, set(i),
flash(seconds?), moveTo(x, y) }`.

## 11. Verification

- `bash scripts/check.sh`: Rojo sourcemap, luau-lsp strict analysis (0 errors), luau-compile, the specs (`tests/run.luau`
  lists them: Util, Validate, Numbers, DataIntegrity, Traits, Island, Battle, Expedition, Breed, Sites, Economy, Plot,
  Quest, Schema, Shading, Raster, Rim, PixelFont), the Rojo build. Must end with `ALL CHECKS PASSED`.
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
