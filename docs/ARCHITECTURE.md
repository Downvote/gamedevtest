# Byte-Size Studio: Architecture and Implementation Contract

The contract for the code in this repository (GitHub `Downvote/gamedevtest`). `docs/GAME_DESIGN.md` says what the game
does and why; this file says how the code is laid out, what each module offers and which data goes where. Where the
two disagree on an API, a type or a name, this file wins; on a number, `src/shared/Config/Tuning.luau` wins.

The build system, the conventions and much of the rendering code come from Random Bakery (`Downvote/test`, used
read-only as the reference: nothing there was changed). What was copied, and how it was changed, is listed in §12.

> The request (2026-11-06): "use its pixel art style and filters and isometric style, along with its build system
> and formats. reference game dev story from kariosoft and make a simplified version of it in gamedevtest"
>
> The redesign (2026-11-09, GAME_DESIGN quotes it whole): "scrap the whole system. ... rng system, where an idea team
> thinks of random ideas ... the player can combine 3 ideas into one game, in which the player has to play 3 minigames
> ... coins can be used to boost the idea team ..."

## 1. Layout and tooling

```
default.project.json   Rojo: Shared -> ReplicatedStorage, Server -> ServerScriptService, Client -> StarterPlayerScripts;
                       characters on (the founder walks the street; jump power 0)
src/shared/            Types, Net, Config (Tuning, Monetization), Data (content), Logic (pure rules), Render (pure pixel
                       maths, copied), Models (procedural models), Locale (Lang: English only)
src/server/            Main.server.luau, Services/* (DataService, Session, Router, StudioService, PlotService)
src/client/            Main.client.luau, Controllers/* (StateClient, CameraController, WorldView, AvatarView),
                       Audio, Pixel/* (PixelRenderer, BakeCast, PixelText, Snapshot, ImageMemory), UI/* (UIKit, Hud,
                       Menus, MicroUI, MicroGames, MicroScenes, PixelSprites, ArtData (generated), BuildUI, Words)
tests/                 run.luau (spec runner), TestKit.luau, Career.luau (the Economy spec's player), specs/*.spec.luau
scripts/check.sh       the gate every change passes (§11)
scripts/gen_pixelfont.py  the pixel font's glyph tables (copied; README "Fonts and licences")
scripts/gen_art.py     every interface sprite as a text mask -> UI/ArtData.luau (outline, anti-aliasing, shading;
                       `--png <file>` writes a contact sheet; GAME_DESIGN 2's rules; §10.9)
tools/                 setup.sh (installs rojo, luau, luau-lsp), defs/ (Roblox API types), sim/ (the fake engine and
                       this game's scenarios), preview/ (PNG renders of the real game); tools/README.md
```

Rojo 7.4.4 (`rokit.toml`), luau-lsp 1.70.1 with `tools/defs/globalTypes.d.luau`, the plain Luau CLI for the specs.
Every file is `--!strict` (`.luaurc`). `X.server.luau` is a Script, `X.client.luau` a LocalScript, everything else a
ModuleScript; there are no `init.luau` files.

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
- Player-visible text goes through `Locale/Lang.t` (English only for now; GAME_DESIGN 11).

## 3. Types (`src/shared/Types.luau`)

`Look`, `Member` (an idea team member: `{ id, name, look, desk }`), `Card` (an idea on the board: `{ id, mod }`, a
Data/Ideas id and a Data/Modifiers id), `Making` (the game being made: `{ title, ideas: { Card } x3, won: { -1 | 0 |
1 } x3, seed }`), `Game` (a launched game: `{ id, title, ideas, rate, wins, at }`), `Upgrades` (`{ speed, luck }`),
`Piece`, `PlotSave`, `Settings`, `Stats` (`{ games, rolls, best, earned }`), `Profile` (the save, version 3: `coins`,
`rate` (every launched game's coins a second), `ideas` (the board), `found` ("idea|mod" -> count: the Index),
`project`, `games`, `nextGame`, `upgrades`, `team`, `office`, `tut`, `stats`, `settings`, `createdAt`, `founder`,
`plot`), `ClientView` (the profile's fields plus `plot` (the plot index), `rollEvery`, `luck`, `decor`), `ErrCode`,
`Response`, and the utility types `Connection`, `Signal<T...>`, `Rng`, `PixelTier`. The file is the reference for
every field.

## 4. Config

- `Config/Tuning.luau`: persistence (`DataStoreName = "BSS_Profile_v1"`, never renamed; `GamesKept`), the idea team
  (`StartCoins`, `TeamSize`, `BoardSize`, `RollBase`, `RollStep`, `RollMin`, `LuckStep`, `RareOdds`, `CommonOdds`,
  `CommonFloor`, `TierOneIn` / `TierNames` / `TierColors`, `RevealTier`), the upgrades (`SpeedCost`, `SpeedGrowth`,
  `LuckCost`, `LuckGrowth`), the income (`IdeaValue`, `IdeaValuePow`, `WinBoost`, `IncomeTickSec`), the microgames
  (`MicroSeconds`, `MicroSecondsMin`, `MicroSecondsStep`, `MicroIntro`, `MicroMinSec`, `MicroMaxSec`, `DiffMax`,
  `TurboSpeed`, `TurboClock`), the server's step and rate limit, the street (`MaxPlots`, `PlotSpacing`, `PlotPieces`,
  `HomeCooldown`), and the camera and pixel filter values (Random Bakery's `CamYaw` 45, `CamPitch` 30, `PixelTiers`,
  `PixelScaleMin` / `PixelScaleSides`; this game's `CamRayBack`, `PixelMaxRayDist`, `CamFollowBox`, `CamGlide`,
  `CamBuildPan`, `PixelPanRays`, `PixelInvalidateRaysFrame`).
- `Config/Monetization.luau`: `GamePasses`, `DevProducts`, `Badges` (empty or 0) and `Sounds` (the Creator Store
  library ids `Controllers/Audio` plays: Random Bakery's).

## 5. Data (pure content tables)

| Module | Holds |
|---|---|
| `Data/Palette` | the LUT colours (`order`, `colors`), the office tiers' floor and wall themes (`themes`), the light modes, and the UI's colours (`ui`, `axis`, `match`) |
| `Data/Ideas` | the 24 ideas `{ id, name, kind (Genre / Theme), odds, micro (its engine), variant, word (its order), reuse, color, words }`; `list`, `byId` |
| `Data/Modifiers` | the 7 modifiers `{ id, name, odds, mult, effects (speed tiny shake glitch dark), color, blurb }`, Plain first |
| `Data/Names`, `Data/Looks` | the team's names; skin, hair, hair style and shirt lists (`Types.Look` indexes them) |
| `Data/Office` | the three rooms (`plans[tier]`: bounds, wall height, lot, desk anchors, props, windows, `OUTLINE` boxes), `origin(plot)` (Data/Street's), `seat(anchor)`, `outlinePts(tier, ox, oz)` and the desk and seat sizes |
| `Data/Street` | the street (§12 of GAME_DESIGN): `MAX`, `SPACING`, `LAWN_Y` (-0.5), `ROAD` / `PAVE_N` / `PAVE_S` / `VERGE` (plot-local z bands), `FAR` / `END_FAR` (ground past the invisible walls: no sky at the world's edges), `LOT`, `plot(tier)` (the plot's rect), `origin(i)` (plots centred on x = 0), `plotAt(x, z)`, `bounds()`, `door` / `footpath` / `spawn` / `sign` / `mailbox` (from the room's `maxX`, `maxZ`), `LAMPS`, `TREES` |
| `Data/Decor` | the plot's decor `{ id, name, price (coins), w, d }` (footprint in whole studs facing south) |

Coordinates in `Data/Office` are studs, plot-local, +Y up. The camera looks from the south-east, so the back walls are
the north (`minZ`) and west (`minX`) ones; a developer sits on a desk's north side facing south (toward the camera),
the monitor at the desk's south-west corner with its back to the camera. A prop's `rot` turns its model (built facing
+Z): 0 faces south (north-wall pieces), 90 faces east (west-wall pieces).

## 6. Logic and models

Pure rules (`src/shared/Logic`), all specced in `tests/specs`:

| Module | API |
|---|---|
| `Util` | copied from Random Bakery: `hash32`, `newRng(seed)` (xorshift32: `next int range chance weighted`), `pick`, `shuffle`, `Signal`, `round clamp lerp isFinite sig2 deepCopy count` |
| `Ideas` | the rolls (GAME_DESIGN 4): `ideaChances(luck)`, `modChances(luck)` (Rare and rarer at luck / odds, Uncommon at 1 / odds, the commonest share the rest, at least `CommonFloor`), `roll(rng, luck) -> Card`, `oneIn(card)` (the idea's odds times the modifier's), `tierOf(n)`, `tier`, `tierName`, `tierColor`, `name` ("Glitched Ninjas"), `value(card)` (coins a second), `difficulty(card)` (tier + reuse, 1..`DiffMax`), `title(cards, seed)`, `rate(cards, wins)`, `rollEvery(speed)`, `luck(level)`, `place(board, card) -> (slot, replaced?)` (room first; full: a rarer idea takes the commonest's place, else dropped), `key`, `valid` |
| `Studio` | the rules over a profile, every action returning `(true, data?)` or `(false, ErrCode)` and changing the profile only on success: `rollIdea(profile, rng) -> Rolled` (`{ card, slot, replaced?, oneIn, tier, first }`: counted in the Index and the stats, placed on the board), `make(profile, a, b, c, seed)` (busy, bad_payload), `result(profile, slot, won)` (the best result counts; no_project), `wins(making)`, `launch(profile, now) -> Game` (no_project, not_built), `earn(profile, coins)`, `upgradeCost(k, level)`, `speedMaxed`, `buyUpgrade(profile, k)` (money, max, bad_payload), `rollEvery(profile)`, `luck(profile)`, `randomLook(rng)`, `newTeam(rng, n)`, `setFounder(profile, skin, hair, style, shirt)` |
| `Plot` | the plot's rules: `ROTS`, `limit(tier)`, `footprint(id, rot)`, `rect`, `blockers(tier)` (the office with a stud round it, the footpath, the sign, the mailbox), `fits(tier, placed, id, x, z, rot, skip?) -> (ok, "outside" / "blocked" / "overlap" / "unknown")`, and the actions `buy` (once, with coins), `place` (an owned piece, up to the limit), `move`, `store` |
| `Schema` | `VERSION` (3: the idea loop), `default(now, seed)`, `migrate(raw)` (1 -> 2: a founder and a plot; 2 -> 3: the old studio's fields dropped, its staff kept as the idea team, the tips start over), `reconcile(raw, now, seed)` (any table -> a valid Profile: cards that exist, the board at most `BoardSize`, a project only with three valid ideas, games' rates worked out again from their ideas, the income never below the listed games', the team one to a desk inside the room, owned decor that exists and placed pieces that fit) |
| `Validate` | `ACTIONS` (the action catalogue, §7.3), `request(action, payload) -> (ok, err?)`: exact schemas, unknown and missing fields refused |

Models (`src/shared/Models`, Roblox modules):

- `Blocks` (copied): `part(parent, spec)` (anchored, SmoothPlastic or Neon, sizes on the 0.25-stud grid, palette
  colours), `cylY`, `model`, `color`, `snap`.
- `OfficeModels.build(parent, tier, origin) -> Model`: the lot (lawn and a path), the floor slab and its tiles in the
  tier's theme, the two back walls with skirting and crown, the north wall's windows, the low rim on the open sides,
  the desks (`Desk_<i>`: top, side panels, monitor with its power light, keyboard, mouse, mug, chair) and the props
  (`garage_door shelf boxes plant lamp beanbag cooler poster bookcase whiteboard coffee rug sofa server trophies tv
  arcade`). `paint(model, theme)` gives the floor and wall parts their theme's colours.
- `CharacterModels.build(look, name, seed) -> Rig` (`{ model, parts, rest, seed }`): a seated chibi developer facing
  +Z, origin on the seat's top centre; parts are not queryable or collidable. `pose(rig, base, t, state)` with state
  `type idle tired cheer`; `HEAD_TOP` is where popups start. `buildStanding(look, name, seed)`: a founder (the same
  head on a standing body, origin between the feet); `poseStanding(rig, base, t, speed)` (a walk cycle by speed,
  breathing and looking round when still); `STAND_TOP` (the name label).
- `StreetModels`: `road(parent, origin)` (a plot's stretch: pavements with kerbs, the road and its dashed line, the
  verge, lamp posts, trees), `land(parent, origin, tier)` (meadow, the plot's lawn, the stepping-stone footpath, the
  plot sign with its `SignBoard`, the mailbox), `emptyLot(parent, origin)`, `ends(parent)` (the street's ends and the
  invisible, unqueryable walls round the world). Tops: lawn -0.5, meadow -0.55, road -0.45, pavements -0.3.
- `DecorModels.build(id, at) -> Model` (`at`: the footprint's centre on the lawn, turned; parts don't collide), `has`.
- `OfficeModels` no longer builds a lawn (the street does); its low rim doesn't collide; a doorstep fills the gap.

## 7. Server

### 7.1 Remotes (`Net`)
`ReplicatedStorage.Remotes`: `Request` (RemoteFunction, C->S `(action, payload) -> Response`), `Signal` (RemoteEvent,
C->S `(kind, payload)`; no handlers in this version), `State` (RemoteEvent, S->C the whole `ClientView` when it
changed), `Fx` (RemoteEvent, S->C `{ kind = "idea", card, slot, replaced?, oneIn, tier, first }` for each new idea and
`{ kind = "coins", coins, paid }` after each income payment). `Net.serverInit()` creates them; `Net.clientInit()` waits for them.

### 7.2 `Session`
`create(player, profile, plot) -> S` (`{ player, profile, plot, rng, ready, rollClock, payClock, coinFrac, dirty,
saveAt, reqTimes, micro? }`; `micro: Micro = { slot, token, at, seed }` is the microgame in play), `get`, `remove`,
`all`, `view(s) -> ClientView` (with `rollEvery` and `luck`), `markDirty`, `flush` (sends State when dirty),
`fx(s, msg)`, `allow(s, now)` (the rate limit).

### 7.3 `Router` and the action catalogue
`Router.on(action, fn(s, payload) -> (ok, data|err))`, `Router.onSignal(kind, fn)`, `Router.handle(player, action,
payload) -> Response` (not ready -> `not_ready`; over `Tuning.RateLimitPerSec` -> `rate`; `Validate.request`; the
handler under pcall; success marks the session dirty).

| Action | Payload | Rule (`Logic/Studio`) | Errors |
|---|---|---|---|
| `game.make` | `a b c` (board indices 1..16) | `make` (data: the Making) | busy, bad_payload |
| `micro.start` | `slot` (1..3) | the session keeps `micro` (a new start replaces one in play: a retry at any time) (data: `{ slot, token, seed, diff, card }`) | no_project, bad_payload |
| `micro.finish` | `token won` (`won` 0 or 1) | `result` with the result, a loss when a win comes sooner than `MicroMinSec` or any result later than `MicroMaxSec` after the start; lets go of `micro` (data: `{ slot, won }`) | busy (no microgame or a wrong token) |
| `game.launch` | - | `launch` (data: the Game) | no_project, not_built |
| `upgrade.buy` | `k` ("speed" / "luck") | `buyUpgrade` (data: `{ level, cost }`) | money, max |
| `founder.set` | `skin hair style shirt` | `setFounder` (the `Founder` attribute follows on the next sync) | bad_payload |
| `settings.set` | `k` ("pixel"), `v` | the pixel tier: high, medium, low, off | bad_payload |
| `tut.next` | - | the tips banner goes away for good | - |
| `plot.buy` | `id` | `Plot.buy` | max, money, bad_payload |
| `plot.place` | `id x z rot` (coords whole studs in [-64, 64], rot a quarter turn) | `Plot.place`, then PlotService rebuilds the decor by difference (data: `{ i }`) | locked, full, blocked |
| `plot.move` | `i x z rot` | `Plot.move`, the decor rebuilt | blocked, bad_payload |
| `plot.store` | `i` | `Plot.store`, the decor rebuilt | bad_payload |
| `char.home` | - | PlotService puts the founder on their footpath | cooldown (`Tuning.HomeCooldown`), not_ready |

### 7.4 `StudioService`
Registers the actions above. `step(dt)` (Main's fixed 10 Hz step), for every ready session: the idea team's clock
(`roll(s)` every `Studio.rollEvery`: `Studio.rollIdea`, then `Fx "idea"`), the income (`rate x dt` accumulated, the
whole coins paid every `Tuning.IncomeTickSec` with `Fx "coins"`; the whole view is not sent for it), and a microgame
left open past `Tuning.MicroMaxSec` dropped. Nothing holds the clocks.

### 7.5 `PlotService` (the street)
`init()` builds the whole street: `Workspace.Plots.Street` (every plot's road stretch and the street's ends) and an
empty lot on every plot (`Plot_<i>.Static.Land` = `EmptyLot`, attribute `Owner` 0). `claim(player) -> plot` (the lowest
free index, 0 when the street is full: Main kicks), `release(i)` (back to an empty lot, attributes cleared).
`build(s)`: `Plot_<i>` gets `Owner`, `OwnerName`, `StudioName`; its `Static` gets `Office` and `Land` for the session's
tier (rebuilt only when `Static`'s `Built` attribute differs: a new folder goes up before the old comes down) and
`Decor` by difference (`buildDecor(s)`: one model a piece, named `id:x:z:rot`; models whose piece is still there stay,
gone ones are destroyed, new ones built), then `sync(s)`: the attributes `Tier`, `Games`, `Best` (the rarest idea's
1 in N), `Rate` (the whole coins a second), `Crew` (a team member a `;`-separated entry `desk.skin.hair.style.shirt.0`)
and `Working` (always true: the team is always thinking), and the player's `Founder`
(`skin.hair.style.shirt`) and `Plot` attributes (Main syncs every dirty session before sending its view; only changed
values replicate). The founder: `watchCharacters(player)` (a new character goes to its footpath once it has a root),
`placeCharacter(s)`, `spawnCFrame(s)`, `home(s)` (`char.home`, once every `Tuning.HomeCooldown`).

### 7.6 Persistence (`DataService`, `Logic/Schema`)
One key per player (`u_<userId>`) in `Tuning.DataStoreName`, a record `{ data = Profile, lock = { job, t }? }`.
`load(userId) -> (raw?, ok)` takes the lock: while another server holds a lock younger than `Tuning.LockTTL` it
waits and retries, and on the last of `Tuning.LoadRetries` attempts (about 10 s) takes it over (a server saving a
player on leave is done by then; a crashed one never lets go). `save(userId, profile, release?)` never overwrites a
record whose lock another server holds, so a late save from the old server is dropped instead of rolling back. Main: join -> claim a plot, load (kick on failure), `Schema.reconcile`, build the office, ready, send the view;
leave -> save with the lock released, free the plot; autosave every `Tuning.AutosaveSec`; BindToClose saves everyone.
Without DataStores (Studio without API access) saves live in memory and a warning says so. A new save shape needs a
`Schema.VERSION` step in `migrate` and a spec that an older profile still loads.

## 8. Client bootstrap and the mirror

`Main.client`: `StateClient.init` (remotes), `PixelRenderer.init` (lighting), `CameraController.init`, wait for the
first view, `CameraController.start`, `PixelRenderer.start`, `UIKit.init`, `WorldView.start`, `AvatarView.start`,
`Hud.start`.

### 8.1 `StateClient`
`init`, `view() -> ClientView?`, `waitView`, `Changed: Signal<ClientView>`, `Fx: Signal<msg>`, `Coins: Signal<number>`
(an income payment: the view's `coins` is patched in place, no whole view comes), `request(action, payload) ->
Response` (never errors), `signal(kind, payload)`.

### 8.2 `Audio`
`play(name, opts?) -> boolean` (opts `{ volume, pitch }` times the event's), `has(name)`, `EVENTS`: every sound by
name (`click hover open close deny notice ding coin coins level_up reward fanfare rare_fanfare combo sparkle cheer
applause trumpet sad drumroll tick key flip pop squish`), each one `Monetization.Sounds` id (0 = silent) with a volume,
a pitch range, a cooldown (a repeat inside it is dropped) and a few voices (Sounds in `SoundService.UISounds`, reused).

## 9. The pixel filter and the camera

### 9.1 Principle (Random Bakery's, cut down: one fitted scale, pans, no Actors)
One EditableImage, shown full screen through an ImageLabel with `ResampleMode = Pixelated` from the screen's top-left
corner: one art pixel is K × K screen px. K is the game's one pixel size (2 on phones and 768p, 3 at 1080p, 4 at
1440p; a tier only makes it coarser). The **static layer** is a raycast G-buffer of the view: progressive passes (one
ray per 4×4 block, per 2×2, then every pixel; `Pixel/BakeCast`), time-sliced (`Tuning.PixelBakeMsPerFrame`, more
behind the first curtain), sun visibility cast at each 2×2 block's even-even anchor and shared by the other three
pixels when they show the same part and normal (their own shadow ray otherwise), shaded with `Render/Shading`'s three
toon bands and the palette LUT (the indoor tint inside the room), then the ink outline (`Shading.outline`) and the
contact shade at the foot of upright faces. The **dynamic layer** is the idea teams and the founders: every tick (the tier's Hz) their parts
are drawn analytically with `Raster.drawPart` and the same orthographic camera, depth-tested against the static
layer and outlined; only the old and new dirty rects are restored and uploaded. Without EditableImages (or with
Classic picked) the layer hides and the Roblox camera shows the 3D world.

### 9.2 `CameraController`
`View = { rot12, center, look, viewH, grid: Raster.Grid, key, fullX, fullY, K, tier, plot, room, box }`.
Orthographic yaw 45° pitch 30°: floor edges step 2:1. The office's outline (`Office.outlinePts`) is fitted on screen
clear of the HUD's blocks (`setHudRects`), at the largest clean grid scale (`Raster.gridScale`, `Raster.gridPhase`)
whose placement is clear (`Raster.place`): that placement is the **home** pan (`view().grid.px/py`). The grid's ray plane
`l` is fixed per plot (`CamRayBack` behind the plot's origin), so the key (`plot|tier|a|phase|l|screen|K`) only
changes with the plot, the office, the screen or K: anything else (the HUD's blocks) only moves the home pan.
The **pan now** (`pan() -> (px, py)`, whole art px) follows the founder every frame (`RenderStepped`): on any lot (the
own or a neighbour's) that lot framed like the home view (`lotPan`: the home pan shifted by the grid offset between
the two plots' origins) as long as the founder shows there clear of the HUD's strips; on the road the least move
that keeps them `CamFollowBox` of the screen from its edges and clear of the HUD's top and bottom strips (and the tips
banner), gliding `CamGlide` of the way a frame, never more a frame than the renderer can scroll in one (`panCaps`:
`PixelPanRays` over 1.5 rays a pixel of a strip), so its picture never falls behind into a re-bake; a target more than three quarters of the screen away
snaps (one bake instead of a scroll that would bake several times). A new character is ignored until it has stood
on its own lot once or 3 s have passed (Roblox drops it mid-street before the server moves it home). Build mode: `setFree(true, down?)` starts at home lowered by
`down` art px (Build mode's tray height, so the front yard shows above it) and the view stays where `panBy(dx, dy)`
(full-screen px) drags it, its centre within `CamBuildPan` studs of the plot; `isFree()`.
`gridAt(px, py)` (the grid at a pan), `centerWorld()` (the view's ground centre now), `view()`, `refit()`,
`ViewChanged` (a new key: a new bake), `pixelK(size?)`, `setPixelLimit(h, classic)`. The Roblox camera is posed on the
pan now: far away at `CamFov` with the filter on, at `CamOffFov` in the classic style.

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
  layer re-bake it (a new office). Rects in global px survive pans.
- The bake's rays exclude `Workspace.PixelDynamic` and every player's character (refreshed when characters come and
  go). Dynamic models whose first part lies more than `CULL` (48) art px off the layer are skipped.

### 9.4 Text and pictures
`Pixel/PixelText` (copied): labels drawn in the pixel font into shared EditableImage atlas pages; a bound TextLabel
keeps its `Text`. `Pixel/Snapshot` (copied): pixel-art pictures of models drawn analytically (`Render/Picture`), for
UI icons: the Staff panel's portraits (`UIKit.portrait`: a developer's head and shoulders turned to face the viewer). `Pixel/ImageMemory` (copied): every EditableImage is made through
it.

## 10. Interface

### 10.1 `UIKit`
Roots `World` (DisplayOrder 7, full screen: popups over the office), `Hud` (10), `Modal` (20), `Popup` (25), each
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
a panel), `clearNotices`, `floatText(world, text, color, big)`, `portrait(parent, look, size, pos)`, `tween` (a UDim2 property
eases on Heartbeat snapped to whole UI px, Quad out, the newest tween of a property winning; the rest through
TweenService), `Resized`. Motion (GAME_DESIGN 15): a button lightens while hovered, its plate and words sink 1 UI px while pressed,
and `Activated` plays `click` (or `deny` when disabled); a panel's shade fades in and its frame rises 10 UI px into
place; a notice slides down into the stack and fades out.

### 10.2 `WorldView`
A rig per idea team member at their desk (rebuilt when their look, desk, office or plot changes), registered with the
renderer and posed every frame: typing away, cheering for a moment. The own team comes from the view (keys
`own:<member id>`): each new idea (`Fx "idea"`) pops out of the next member's head in its tier's colour (Rare and up
bigger, and they cheer); every other studio's team from its plot's `Crew` attributes (keys `<plot>:<desk>`). Only
rigs on plots within 90 studs of the view's centre are posed. Each plot sign gets a World-root label (the studio's
name, the own in gold, or "Empty lot"); a tap on a sign (a press let go within 8 px, not on the interface, not in
Build mode) shows `signCard(i)` (games, the rarest idea, the income). `rigCount()` / `ownRigCount()` for the sims.
A typing member sends a bit of code ("</>", "{ }", "01" ...) up from their screen every few seconds; `cheer(words,
color)` makes the own team cheer with the words over their heads in turn (a launch).

### 10.3 `Hud`
Chips (`Chip_coins`, easing to the coins and flashing when they change; `Chip_rate`, "+12.4/s"; `Chip_idea`, "Idea in
3.2s" with a bar along its edge, restarted by each `Fx "idea"`; `Chip_board`, "Board 7/12"; then `Home`, a button shown
while the founder is off their own lot, sending `char.home`), the menu bar (`Menu_ideas`, `Menu_index`,
`Menu_upgrades`, `Menu_games`, `Menu_looks`, `Menu_build`; while Build mode is open the bar, the card and the tips step
aside), the card on the right: `BoardCard` (the newest four ideas in their tiers' colours and `MakeGame`, on with three
ideas, opening the idea board) or, while a game is being made, `ProjectCard` (its title, its three ideas with WIN /
lose / -, the sales boost, and `CardPlay` / `CardLaunch` opening the making card); the main button pulses. The tips
banner (`Tips`, "OK" sends `tut.next`), the loading curtain (until `PixelRenderer.firstPicture`), and the reveal
(`Reveal`: a Rare idea or better drops in at the top with its icon, tier, name, 1 in N and "New!", a sound by tier,
confetti from Epic; over an open panel or the making card it is a notice in the status line instead). It reports its
blocks to the camera (on PC the top strip, the menu bar and the card's place; on a phone Roblox's top bar and the menu
bar). On `MicroUI.Launched` the team cheers (`WorldView.cheer`) with the new income.

### 10.4 Menus
`Menus` registers the panels: "ideas" (the board: a card per idea `Pick_<i>` with its icon, tier strip, modifier and
1 in N; three picks numbered in order; the preview of the income; `Make` sends `game.make` and opens the making card;
with a game in the works, `Continue`), "index" (`Entry_<id>` for every idea: its icon or its dark silhouette (`icon_<id>_sil`) and "???", its odds, a dot
per modifier lit once found; "Found n of 168"), "upgrades" (`Buy_speed`, `Buy_luck` with their prices, following the
coins as they come), "games" (the launched games, newest first, their ideas, rates and wins) and "looks" (the founder's
portrait, `Prev_<k>` / `Next_<k>` for skin, hair, style and shirt, `SaveLook` sends `founder.set`). `Words.errText(err)`
words every ErrCode.

### 10.6 `AvatarView`
A founder per player (`CharacterModels.buildStanding`, look from the player's `Founder` attribute, else one from the
UserId), registered with the renderer and posed every frame at their character: feet on the ground under the
HumanoidRootPart (a raycast down past characters and rigs), facing the root's look direction, walking at the speed
the root moves. The Roblox avatar is hidden on every client (`LocalTransparencyModifier` 1 on its parts and decals).
Other players' names float over their heads (World root). `founderPos()`, `count()`.

### 10.7 `BuildUI` (Build mode)
`open()` (the HUD's Build button): closes any panel, `CameraController.setFree(true)`, the tray `BuildTray` along the bottom (a card a piece: `Buy_<id>` buys it or, when owned, picks it; the line
"Pieces n/limit"; `BuildDone`). With a piece picked (`pick(id, rot?)`), a ghost model (`Ghost` in
`Workspace.PixelDynamic`: the piece and its `Footprint`, a raised neon frame of four edges from the lawn to just above
the office floor, cyan (`screen_on`) where `Plot.fits` says it fits, red (`berry_red`) where not: a flat green one was
lost in the lawn's ramp and hidden under the office floor)
stands on the cell under the pointer (mouse) or the last tap; the bar shows `Rotate`, `Place` / `Move here`, `Store`
(when moving) and `Cancel`. A tap on a placed piece of the own plot (a ray into its `Static.Decor`) picks it up to
move. A press dragged more than 8 px pans the view (`CameraController.panBy`). `confirm()` sends `plot.place` (the
piece stays picked for another copy) or `plot.move`; `close()`; `isOpen()`; `Changed: Signal<boolean>`;
`tapScreen(pos, mouse?)` (the sims' and previews' tap).

### 10.8 Making a game (`MicroUI`, `MicroGames`, `PixelSprites`)
`MicroUI`: `open()` (the making card `MicroCard`: the game's title, a row a slot with its icon, name, order word,
modifier, difficulty, WIN / LOSE and `Play_<i>` / `Retry_<i>`; the sales boost; `PlayAll`, `Launch` (on once all three
are played: `game.launch`, then the launch card with the income, confetti and `Nice`), `CloseMicro`; opened right
after `game.make`, it waits for the view with the project), `refresh()` (the card follows the view), `isOpen()`,
`Launched: Signal<Game>`, `play(slot, chain?)`, and for the sims and previews `playing() -> engine?`, `debugAuto()`
(one right move) and `debugCtx()` (the last microgame's diff, speed, tiny, seconds, effects, area). A microgame:
`micro.start`, the idea's icon (`WordIcon`) and order word (`Word`) drop in on `WordBand` for `Tuning.MicroIntro` over
the idea's scene (`MicroScenes.build` into `Area`, its own Rng from the seed + 7), then the engine runs in `Area`
while the `Fuse` rope burns down to `FuseBomb` with the `Spark` animation (seconds: `MicroSeconds - MicroSecondsStep x
(diff - 1)`, at least `MicroSecondsMin`, times the engine's `clock` and Turbo's `TurboClock`); the modifier's effects:
`speed` (ctx.speed `TurboSpeed`), `tiny` (ctx.tiny: the engines use the small sprites), `shake` (the area jitters),
`glitch` (`GlitchFlash` blinks over it), `dark` (`Dark1`..`Dark4` round a roving spotlight); a WIN / LOSE stamp (a
flash; confetti for a win), then `micro.finish` (no sooner than `MicroMinSec` after the start); Play all goes on to the
next unplayed slot. The runner owns the effects and keeps them (and the scene) moving under the stamp until the card
comes back: `Pop` words, `Bit` bursts (1 px, their own Rng from the seed + 101), floats, the area's `Flash`. Its keys
are bound through ContextActionService above the founder's walking keys (arrows, WASD, Space, Return, F, J, 1-6;
UserInputService when that is not available).
`MicroGames`: the twelve engines `dodge timing mash whack pick sequence catch jump rhythm slice hide stack`, each
`(ctx) -> Micro` with `ctx { area, w, h, rng (the server's seed), diff, speed, tiny, variant (the idea's theme), pop(x,
y, text, color), burst(x, y, colors, n?), float(gui, vx, vy, life, gravity?), flash(color), shake, win, lose, press }`
and `Micro { update(t, dt), key(k), survive?, clock?, pace? (px/s the scene scrolls at), auto() }`; every thing is a
sprite at its own size (`name`, or `name_t` when Tiny; the idea icons `icon_<id>` / `mini_<id>`), animated by frames;
named buttons `Pad_<key>`, `Hole_<i>`, `Opt_<i>`, `Fruit_<i>` / `Bomb_<i>`.
`MicroScenes`: `build(area, variant, w, h, rng) -> update(t, pace?)` (a `Scene` layer at ZIndex 4 under the game, one
scene a Data/Ideas variant, drawn from 1 px rects and sprites: dithered sky bands, discs with anti-aliased edges,
twinkling stars, scrolling kerbs, rising bubbles, flickering torches, flashing floor tiles, beams), `has(variant)`.

### 10.9 Sprites (`PixelSprites`, `ArtData`)
`ArtData` (generated by `scripts/gen_art.py`; do not edit): `{ [name]: { w, h, px, pal, alpha } }`, one character a
pixel (`.` clear, else an index into `pal` 0xRRGGBB with its `alpha`: 1, or 0.35 for the outline's anti-aliasing).
Every sprite also has a white `<name>_flash` (a hit, the same outline); the icons have a dark `<name>_sil` (not found
yet); an animation's frames `<name>_1`, `<name>_2`... share one canvas (bottom centre). The sprites: the idea icons
`icon_<id>` (16x16) and `mini_<id>` (11x11), Spot it's recoloured `icon_/mini_<detectives|pirates|horror|robots>_alt`,
the microgames' things (`hero_1/2`, `dino_1/2`, `coin_1..3`, `fish_1/2`, `jelly_1/2`, `bomb_1/2`, `alien_1/2`,
`slime_1/2`, `cat_1/2`, `block`, `cone`, `car`, `basket`, `sprout`, `flower`, `kid`, `fruit`, `fruit_cut`, `rock`,
`cactus`, `note`, `soldier`, `ghost` / `ghost_glare`, `door`, `pan`, `pancake`, `ball`, `goal`, `hole` / `_crater` /
`_grave`, `heart`, `star`, `spark_1..3`, `bombfuse`, the arrows `arrow_<dir>` 13x13), each with a `_t` small one
where Tiny shows it. `PixelSprites`: `has(name)`, `size(name) -> (w, h)`, `image(parent, name, pos?, z?) ->
GuiObject` (an ImageLabel `Sprite_<name>` showing the sprite's EditableImage, made once and shared, `ResampleMode`
Pixelated, at the sprite's own size: no scale; without EditableImages a Frame of 1 px run rects), `anim(parent, names,
pos?, z?) -> Anim { f, w, h, set(i), flash(seconds?), moveTo(x, y) }` (frames stacked in `Anim_<first>`; `flash`
shows the frame's `_flash`; `moveTo` rounds to whole UI px).

## 11. Verification

- `bash scripts/check.sh`: Rojo sourcemap, luau-lsp strict analysis (0 errors), luau-compile, the specs (`tests/run.luau`
  lists them: Util, Validate, Numbers, DataIntegrity, Ideas, Studio, Economy, Plot, Schema, Shading, Raster, Rim,
  PixelFont), the Rojo build. Must end with `ALL CHECKS PASSED`.
- `tools/sim`: the fake Roblox engine boots the real server and client; this game's scenarios and their baselines
  are in `tools/README.md` and `CLAUDE.md`.
- `tools/preview`: PNGs of the real renderer and UI at device sizes (`tools/README.md`).

## 12. What came from Random Bakery

Copied unchanged or nearly: `Render/Raster`, `Render/Picture`, `Render/PixelFont`, `Render/PixelFontData`,
`Render/Ramp`, `Pixel/BakeCast`, `Pixel/ImageMemory`, `Pixel/PixelText`, `Pixel/Snapshot`, `Logic/Util`,
`Models/Blocks`, the specs `Raster` (its framing fixture now a local outline instead of the bakery's Layout), `Rim`,
`PixelFont`, `Util`, `tests/TestKit.luau`, `scripts/gen_pixelfont.py`, `tools/setup.sh`, `tools/defs`, the sim and
preview engines, `docs/WORKFLOW.md`. Adapted: `Render/Shading` (its LUT colours are the palette and the office
themes; the bakery's wallpapers and land tiles are gone) and its spec, `scripts/check.sh` (no locale or server-codes
steps; builds `ByteSizeStudio.rbxlx`), `Net`. Written new for this game: everything else, including a much smaller
`PixelRenderer` (one fitted scale with pans and rect re-casts, no Actors, no Hold, no per-plot indoor light) and
`CameraController` (the fitted home view, following the founder, Build mode's free pan), and the street itself
(`Data/Street`, `StreetModels`, PlotService's plots and empty lots, AvatarView's founders), modelled on Random
Bakery's street of bakeries and its plot (ROUND3.md 6.6, 9) but smaller: decor on a whole-stud grid, no drawn paths,
water or fences.
