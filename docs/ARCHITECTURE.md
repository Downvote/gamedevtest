# Byte-Size Studio: Architecture and Implementation Contract

The contract for the code in this repository (GitHub `Downvote/gamedevtest`). `docs/GAME_DESIGN.md` says what the game
does and why; this file says how the code is laid out, what each module offers and which data goes where. Where the
two disagree on an API, a type or a name, this file wins; on a number, `src/shared/Config/Tuning.luau` wins.

The build system, the conventions and much of the rendering code come from Random Bakery (`Downvote/test`, used
read-only as the reference: nothing there was changed). What was copied, and how it was changed, is listed in §12.

> The request (2026-11-06): "use its pixel art style and filters and isometric style, along with its build system
> and formats. reference game dev story from kariosoft and make a simplified version of it in gamedevtest"

## 1. Layout and tooling

```
default.project.json   Rojo: Shared -> ReplicatedStorage, Server -> ServerScriptService, Client -> StarterPlayerScripts;
                       characters on (the founder walks the street; jump power 0)
src/shared/            Types, Net, Config (Tuning, Monetization), Data (content), Logic (pure rules), Render (pure pixel
                       maths, copied), Models (procedural models), Locale (Lang: English only)
src/server/            Main.server.luau, Services/* (DataService, Session, Router, StudioService, PlotService)
src/client/            Main.client.luau, Controllers/* (StateClient, CameraController, WorldView, AvatarView),
                       Pixel/* (PixelRenderer, BakeCast, PixelText, Snapshot, ImageMemory), UI/* (UIKit, Hud, Menus,
                       NewGameUI, ReviewUI, BuildUI)
tests/                 run.luau (spec runner), TestKit.luau, Career.luau (the Economy spec's player), specs/*.spec.luau
scripts/check.sh       the gate every change passes (§11)
scripts/gen_pixelfont.py  the pixel font's glyph tables (copied; README "Fonts and licences")
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

`Axis` (`fun ideas graphics sound`), `SkillKey` (`code design art sound`), `Match` (`great good okay poor`), `Phase`
(`build polish`), `Skills`, `Scores`, `Look`, `Staff`, `Candidate`, `Project`, `Release`, `Award`, `Settings`,
`Stats`, `Piece` (a piece of decor on the plot: `{ id, x, z, rot }`), `PlotSave` (`{ owned, placed }`), `Profile` (the
save; `founder: Look`, `plot: PlotSave` since version 2), `ClientView` (what the client sees; `founder`, `decor`),
`ErrCode` (with `blocked`), `Response`, `WorkPop` (a popup over a developer: `{ id, axis, n, spark }`), and the utility types `Connection`, `Signal<T...>`, `Rng`, `PixelTier`. The
file is the reference for every field; the comments there say what each holds.

## 4. Config

- `Config/Tuning.luau`: persistence (`DataStoreName = "BSS_Profile_v1"`, never renamed), the clock (`WeekSec`), money,
  crew, development, reviews, sales, offices (`Offices[tier] = { desks, rent, cost, fans }`), sizes
  (`Sizes[id] = { weeks, cost, price, expect, sales }`), the safety net (`RescueSize`, `RescuePlatform`), research
  costs, the server's step and rate limit, the street (`MaxPlots` 6, `PlotSpacing` 80, `PlotPieces` by office,
  `HomeCooldown`), and the camera and pixel filter values (from Random Bakery: `CamYaw` 45, `CamPitch` 30,
  `PixelTiers`, `PixelScaleMin` / `PixelScaleSides`; this game's `CamRayBack` 500 and `PixelMaxRayDist` 1400 so the
  whole street lies in front of the rays' plane, `CamFollowBox`, `CamGlide`, `CamBuildPan`, `PixelPanRays`,
  `PixelInvalidateRaysFrame`).
- `Config/Monetization.luau`: `GamePasses`, `DevProducts`, `Badges`, `Sounds`, all empty or 0 in this version.

## 5. Data (pure content tables)

| Module | Holds |
|---|---|
| `Data/Palette` | the LUT colours (`order`, `colors`), the office tiers' floor and wall themes (`themes`), the light modes, and the UI's colours (`ui`), the scores' (`axis`) and the matches' (`match`) |
| `Data/Genres`, `Data/Topics` | `{ id, name, tier, words }` (+ a colour for genres); `list` and `byId` |
| `Data/Matches` | per genre: its great, good and poor topics (the rest are okay) |
| `Data/Platforms` | `{ id, name, short, from, to, licence, market, loves, color, accent, kind }` |
| `Data/Critics` | the four critics `{ name, outlet, axis }` in review order |
| `Data/Names`, `Data/Looks` | developer names; skin, hair, hair style and shirt lists (`Types.Look` indexes them) |
| `Data/Office` | the three rooms (`plans[tier]`: bounds, wall height, lot, desk anchors, props, windows, `OUTLINE` boxes), `origin(plot)` (Data/Street's), `seat(anchor)`, `outlinePts(tier, ox, oz)` and the desk and seat sizes |
| `Data/Street` | the street (§12 of GAME_DESIGN): `MAX`, `SPACING`, `LAWN_Y` (-0.5), `ROAD` / `PAVE_N` / `PAVE_S` / `VERGE` (plot-local z bands), `FAR` / `END_FAR` (ground past the invisible walls: no sky at the world's edges), `LOT`, `plot(tier)` (the plot's rect), `origin(i)` (plots centred on x = 0), `plotAt(x, z)`, `bounds()`, `door` / `footpath` / `spawn` / `sign` / `mailbox` (from the room's `maxX`, `maxZ`), `LAMPS`, `TREES` |
| `Data/Decor` | the plot's decor `{ id, name, price, fans, w, d, office }` (footprint in whole studs facing south) |

Coordinates in `Data/Office` are studs, plot-local, +Y up. The camera looks from the south-east, so the back walls are
the north (`minZ`) and west (`minX`) ones; a developer sits on a desk's north side facing south (toward the camera),
the monitor at the desk's south-west corner with its back to the camera. A prop's `rot` turns its model (built facing
+Z): 0 faces south (north-wall pieces), 90 faces east (west-wall pieces).

## 6. Logic and models

Pure rules (`src/shared/Logic`), all specced in `tests/specs`:

| Module | API |
|---|---|
| `Util` | copied from Random Bakery: `hash32`, `newRng(seed)` (xorshift32: `next int range chance weighted`), `pick`, `shuffle`, `Signal`, `round clamp lerp isFinite sig2 deepCopy count` |
| `Calendar` | `parts(week) -> (year, month, week)`, `year`, `month` (absolute month index), `yearStart`, `isMonthStart`, `isYearEnd`, `label` ("Y1 M3 W2"), `long`, `WEEKS_PER_YEAR` |
| `Numbers` | `int` ("1,234"), `short` ("12.3K"), `money` ("$12.3K", exact "$12,345") |
| `Crew` | `SKILLS`, `SKILL_NAMES`, `ROLES`, `total`, `salary`, `role`, `randomLook`, `randomName`, `candidate(rng, year)`, `candidates(rng, year, n?)`, `hire(c, id, desk)`, `freeDesk`, `trainGain(level)`, `tired`, `rate`, `energyWeek(s, working)`, `partyCost(n)`, `payroll` |
| `Dev` | `AXES`, `AXIS_NAMES`, `MATCH_NAMES`, `SIZE_ORDER`, `SIZE_NAMES`; `match(genre, topic)`, `matchKey`, `onSale(p, year)`, `platformsIn(year)`, `genreCost`, `topicCost`, `startCost(size, platform)`, `title(genre, topic, seed)`, `sequelTitle(base, releases, inProgress?)`, `newProject(...)`, `focusMult`, `output(skills)`, `teamFactor(n)`, `workWeek(project, staff, rng) -> (pops, rp)`, `progress`, `novelty`, `love`, `quality(project, releases) -> (Q, match)`, `expectation(size, year)`, `baseScore(Q, E)`, `reviews(project, year, releases, rng) -> (reviews, total, match)`, `salesPlan(total, fans, platform, size) -> (peak, decay)`, `release(...)`, `salesWeek(release) -> (copies, money, fans)`, `award(releases, year, weeksPerYear) -> (kind?, release?)`, `adCost`, `adFans` |
| `Studio` | the rules over a profile, every action returning `(true, data?)` or `(false, ErrCode)` and changing the profile only on success: `week(profile, rng) -> { Event }` (month start: pay, candidates, a new platform on a year's first week; the work week; energy; sales; the awards night after a year's last week; then `week += 1`), `start`, `titleFor`, `rescue`, `release`, `hire`, `fire`, `train`, `party`, `unlockGenre`, `unlockTopic`, `move`, `ad`, and helpers `year`, `desks`, `staffById`, `canAd`, `canParty`. `Event.kind` is `pay candidates work built ready sales award platform broke` |
| `Plot` | the plot's rules: `ROTS`, `limit(tier)`, `footprint(id, rot)`, `rect`, `blockers(tier)` (the office with a stud round it, the footpath, the sign, the mailbox), `fits(tier, placed, id, x, z, rot, skip?) -> (ok, "outside" / "blocked" / "overlap" / "unknown")`, and the actions `buy` (once; its fans join), `place` (an owned piece, up to the limit), `move`, `store`, `clean` (after a move: pieces the bigger room covers go back in the box) |
| `Schema` | `VERSION` (2: the founder and the plot), `default(now, seed)`, `migrate(raw)` (1 -> 2: nothing moves; reconcile gives a founder and an empty plot), `reconcile(raw, now, seed)` (any table -> a valid Profile: types and ranges checked, unknown ids dropped, desks unique and inside the office, the starting genres and topics always open, releases capped at `Tuning.ReleasesKept`, owned decor that exists, placed pieces that are owned and fit, up to the limit) |
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
C->S `(kind, payload)`), `State` (RemoteEvent, S->C the whole `ClientView` when it changed), `Fx` (RemoteEvent, S->C
`{ kind = "week", week, events }`). `Net.serverInit()` creates them; `Net.clientInit()` waits for them.

### 7.2 `Session`
`create(player, profile, plot) -> S` (`{ player, profile, plot, rng, ready, clock, paused, dirty, saveAt, reqTimes }`),
`get`, `remove`, `all`, `isPaused`, `view(s) -> ClientView` (the newest `Tuning.ViewReleases` releases, `canAd`,
`canParty`, `paused`), `markDirty`, `flush` (sends State when dirty), `fx(s, msg)`, `allow(s, now)` (the rate limit).

### 7.3 `Router` and the action catalogue
`Router.on(action, fn(s, payload) -> (ok, data|err))`, `Router.onSignal(kind, fn)`, `Router.handle(player, action,
payload) -> Response` (not ready -> `not_ready`; over `Tuning.RateLimitPerSec` -> `rate`; `Validate.request`; the
handler under pcall; success marks the session dirty).

| Action | Payload | Rule (`Logic/Studio`) | Errors |
|---|---|---|---|
| `project.start` | `genre topic platform size focus seed` | `start` | busy, locked, unavailable, money, bad_payload |
| `project.release` | - | `release` (data: the Release) | no_project, not_built |
| `staff.hire` | `i` (candidate 1..) | `hire` | full, money, bad_payload |
| `staff.fire` | `id` | `fire` | last, bad_payload |
| `staff.train` | `id skill` | `train` (data: `{ gain }`) | max, rp, money, bad_payload |
| `staff.party` | - | `party` | cooldown, money |
| `research.genre` / `research.topic` | `id` | `unlockGenre` / `unlockTopic` | max, rp, bad_payload |
| `office.move` | - | `move`, then PlotService rebuilds the office | max, fans, money |
| `office.ad` | - | `ad` | cooldown, money |
| `settings.set` | `k` ("pixel"), `v` | the pixel tier: high, medium, low, off | bad_payload |
| `tut.next` | - | the tips banner goes away for good | - |
| `plot.buy` | `id` | `Plot.buy` (data: `{ fans }`) | max, locked, money, bad_payload |
| `plot.place` | `id x z rot` (coords whole studs in [-64, 64], rot a quarter turn) | `Plot.place`, then PlotService rebuilds the decor by difference (data: `{ i }`) | locked, full, blocked |
| `plot.move` | `i x z rot` | `Plot.move`, the decor rebuilt | blocked, bad_payload |
| `plot.store` | `i` | `Plot.store`, the decor rebuilt | bad_payload |
| `char.home` | - | PlotService puts the founder on their footpath | cooldown (`Tuning.HomeCooldown`), not_ready |

Signal `pause` `{ key, on }`: the client holds the player's clock while a menu or a card is open (at most 4 keys).

### 7.4 `StudioService`
Registers the actions above; `step(dt)` (Main's fixed 10 Hz step) moves every ready, unpaused session on a week every
`Tuning.WeekSec`, runs `Studio.week` and sends `Fx { kind = "week", week, events }`.

### 7.5 `PlotService` (the street)
`init()` builds the whole street: `Workspace.Plots.Street` (every plot's road stretch and the street's ends) and an
empty lot on every plot (`Plot_<i>.Static.Land` = `EmptyLot`, attribute `Owner` 0). `claim(player) -> plot` (the lowest
free index, 0 when the street is full: Main kicks), `release(i)` (back to an empty lot, attributes cleared).
`build(s)`: `Plot_<i>` gets `Owner`, `OwnerName`, `StudioName`; its `Static` gets `Office` and `Land` for the session's
tier (rebuilt only when `Static`'s `Built` attribute differs: a new folder goes up before the old comes down) and
`Decor` by difference (`buildDecor(s)`: one model a piece, named `id:x:z:rot`; models whose piece is still there stay,
gone ones are destroyed, new ones built), then `sync(s)`: the attributes `Tier`, `Games`, `Best`, `Crew` (a crew
member a `;`-separated entry `desk.skin.hair.style.shirt.tired`) and `Working`, and the player's `Founder`
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
`init`, `view() -> ClientView?`, `waitView`, `Changed: Signal<ClientView>`, `Fx: Signal<msg>`, `request(action,
payload) -> Response` (never errors), `signal(kind, payload)`.

## 9. The pixel filter and the camera

### 9.1 Principle (Random Bakery's, cut down: one fitted scale, pans, no Actors)
One EditableImage, shown full screen through an ImageLabel with `ResampleMode = Pixelated` from the screen's top-left
corner: one art pixel is K × K screen px. K is the game's one pixel size (2 on phones and 768p, 3 at 1080p, 4 at
1440p; a tier only makes it coarser). The **static layer** is a raycast G-buffer of the view: progressive passes (one
ray per 4×4 block, per 2×2, then every pixel; `Pixel/BakeCast`), time-sliced (`Tuning.PixelBakeMsPerFrame`, more
behind the first curtain), sun visibility cast at each 2×2 block's even-even anchor and shared by the other three
pixels when they show the same part and normal (their own shadow ray otherwise), shaded with `Render/Shading`'s three
toon bands and the palette LUT (the indoor tint inside the room), then the ink outline (`Shading.outline`) and the
contact shade at the foot of upright faces. The **dynamic layer** is the crew: every tick (the tier's Hz) their parts
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
`setButtonColor`, `buttonWidth`, `bar -> (frame, set)`, `clear`, `vlist`, `hlist`, `scroll`, panels
(`registerPanel(name, { title, w, h, build })`, `openPanel(name, arg)`, `closePanel`, `currentPanel`,
`refreshPanel`, `PanelChanged`, `bodyWidth`, `bodyHeight`), `notice(text, color, seconds)` (a toast at the top; while a
panel is open, its status line next to the title instead, and opening a panel clears the toasts, so nothing covers
a panel), `clearNotices`, `floatText(world, text, color, big)`, `portrait(parent, look, size, pos)`, `tween`,
`Resized`.

### 10.2 `WorldView`
A rig per developer at their desk (rebuilt when their look, desk, office or plot changes), registered with the
renderer and posed every frame: typing while a game is in the works, idle otherwise, dozing with a "z" when tired,
cheering on a spark. The own crew comes from the view (keys `own:<staff id>`; the week's `work` pops float over their
heads: "+12" in the score's colour, "Spark! +N" in gold); every other studio's from its plot's `Crew` and `Working`
attributes (keys `<plot>:<desk>`). Only rigs on plots within 90 studs of the view's centre are posed. Each plot sign
gets a World-root label (the studio's name, the own in gold, or "Empty lot"); a tap on a sign (a press let go within
8 px, not on the interface, not in Build mode) shows `signCard(i)`. `rigCount()` / `ownRigCount()` for the sims.

### 10.3 `Hud`
Chips (date, with "II" while paused; money; fans; RP; then `Home`, a button shown while the founder is off their own
lot, sending `char.home`), the menu bar (`Menu_newgame`, `Menu_staff`, `Menu_research`, `Menu_office`, `Menu_games`,
`Menu_build`; New game is off while a game is in the works; while Build mode is open the bar, the cards and the tips
step aside), the project card
(`ProjectCard`: title, topic, genre and platform, phase and progress, the four scores, bugs, `Release!` once built),
the tips banner (`Tips`, "OK" sends `tut.next`), the loading curtain (until `PixelRenderer.firstPicture`), the week's
notices, money popups and the awards card. With no game in the works the card's place shows the games on sale
(`SalesCard`). It reports its blocks to the camera: on PC the top strip, the menu bar and the card's place (kept
whether a game is in the works or not, so the view never moves when one starts); on a phone only Roblox's top bar
and the menu bar (Random Bakery's rule), so the office fills the screen and the chips and the card (100 UI px wide,
no bars) may overlap its margins. Any open panel holds the clock
(`pause` signal, key "menu").

### 10.4 Menus
`NewGameUI` (panel "newgame": five pages, Start sends `project.start`; `errText(err)` words every ErrCode) and `Menus`
(panels "staff" with tabs crew and hire, "research" with genres, topics and notebook, "office", "games").

### 10.5 `ReviewUI`
`release()` sends `project.release` and shows `show(release)`: the critics one by one, the total, Hall of Fame, the
match learned; `award(event)` shows the awards night. Both hold the clock (key "card") until "Nice!".

### 10.6 `AvatarView`
A founder per player (`CharacterModels.buildStanding`, look from the player's `Founder` attribute, else one from the
UserId), registered with the renderer and posed every frame at their character: feet on the ground under the
HumanoidRootPart (a raycast down past characters and rigs), facing the root's look direction, walking at the speed
the root moves. The Roblox avatar is hidden on every client (`LocalTransparencyModifier` 1 on its parts and decals).
Other players' names float over their heads (World root). `founderPos()`, `count()`.

### 10.7 `BuildUI` (Build mode)
`open()` (the HUD's Build button): closes any panel, `CameraController.setFree(true)`, holds the clock (pause key
"build"), the tray `BuildTray` along the bottom (a card a piece: `Buy_<id>` buys it or, when owned, picks it; the line
"Pieces n/limit"; `BuildDone`). With a piece picked (`pick(id, rot?)`), a ghost model (`Ghost` in
`Workspace.PixelDynamic`: the piece and its `Footprint`, a raised neon frame of four edges from the lawn to just above
the office floor, cyan (`screen_on`) where `Plot.fits` says it fits, red (`berry_red`) where not: a flat green one was
lost in the lawn's ramp and hidden under the office floor)
stands on the cell under the pointer (mouse) or the last tap; the bar shows `Rotate`, `Place` / `Move here`, `Store`
(when moving) and `Cancel`. A tap on a placed piece of the own plot (a ray into its `Static.Decor`) picks it up to
move. A press dragged more than 8 px pans the view (`CameraController.panBy`). `confirm()` sends `plot.place` (the
piece stays picked for another copy) or `plot.move`; `close()`; `isOpen()`; `Changed: Signal<boolean>`;
`tapScreen(pos, mouse?)` (the sims' and previews' tap).

## 11. Verification

- `bash scripts/check.sh`: Rojo sourcemap, luau-lsp strict analysis (0 errors), luau-compile, the specs (`tests/run.luau`
  lists them: Util, Validate, Numbers, Calendar, DataIntegrity, Crew, Dev, Economy, Plot, Schema, Shading, Raster,
  Rim, PixelFont), the Rojo build. Must end with `ALL CHECKS PASSED`.
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
