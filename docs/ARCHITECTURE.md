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
                       Players.CharacterAutoLoads false (no avatar: the game is played from the menus)
src/shared/            Types, Net, Config (Tuning, Monetization), Data (content), Logic (pure rules), Render (pure pixel
                       maths, copied), Models (procedural models), Locale (Lang: English only)
src/server/            Main.server.luau, Services/* (DataService, Session, Router, StudioService, PlotService)
src/client/            Main.client.luau, Controllers/* (StateClient, CameraController, WorldView),
                       Pixel/* (PixelRenderer, BakeCast, PixelText, Snapshot, ImageMemory), UI/* (UIKit, Hud, Menus,
                       NewGameUI, ReviewUI)
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
`Stats`, `Profile` (the save), `ClientView` (what the client sees), `ErrCode`, `Response`, `WorkPop` (a popup over a
developer: `{ id, axis, n, spark }`), and the utility types `Connection`, `Signal<T...>`, `Rng`, `PixelTier`. The
file is the reference for every field; the comments there say what each holds.

## 4. Config

- `Config/Tuning.luau`: persistence (`DataStoreName = "BSS_Profile_v1"`, never renamed), the clock (`WeekSec`), money,
  crew, development, reviews, sales, offices (`Offices[tier] = { desks, rent, cost, fans }`), sizes
  (`Sizes[id] = { weeks, cost, price, expect, sales }`), the safety net (`RescueSize`, `RescuePlatform`), research
  costs, the server's step and rate limit, the plot spacing, and the camera and pixel filter values copied from
  Random Bakery (`CamYaw` 45, `CamPitch` 30, `PixelTiers`, `PixelScaleMin` / `PixelScaleSides`, ...).
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
| `Data/Office` | the three rooms (`plans[tier]`: bounds, wall height, lot, desk anchors, props, windows, `OUTLINE` boxes), `origin(plot)`, `seat(anchor)`, `outlinePts(tier, ox, oz)` and the desk and seat sizes |

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
| `Schema` | `VERSION` (1), `default(now, seed)`, `migrate(raw)`, `reconcile(raw, now, seed)` (any table -> a valid Profile: types and ranges checked, unknown ids dropped, desks unique and inside the office, the starting genres and topics always open, releases capped at `Tuning.ReleasesKept`) |
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
  `type idle tired cheer`; `HEAD_TOP` is where popups start.

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

Signal `pause` `{ key, on }`: the client holds the player's clock while a menu or a card is open (at most 4 keys).

### 7.4 `StudioService`
Registers the actions above; `step(dt)` (Main's fixed 10 Hz step) moves every ready, unpaused session on a week every
`Tuning.WeekSec`, runs `Studio.week` and sends `Fx { kind = "week", week, events }`.

### 7.5 `PlotService`
`claim(player) -> plot` (the lowest free index; plots in a row along X, `Tuning.PlotSpacing` apart), `release(i)`,
`build(s)`: `Workspace.Plots.Plot_<i>` (attributes `Owner`, `Tier`) gets a new `Static` folder with the office of the
session's tier, before the old one is destroyed.

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
first view, `CameraController.start`, `PixelRenderer.start`, `UIKit.init`, `WorldView.start`, `Hud.start`.

### 8.1 `StateClient`
`init`, `view() -> ClientView?`, `waitView`, `Changed: Signal<ClientView>`, `Fx: Signal<msg>`, `request(action,
payload) -> Response` (never errors), `signal(kind, payload)`.

## 9. The pixel filter and the camera

### 9.1 Principle (Random Bakery's, cut down to one still view)
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
whose placement is clear (`Raster.place`), its box centred where the fit puts it. `view()`, `refit()`,
`ViewChanged: Signal<View>` (when the key changes), `pixelK(size?)`, `setPixelLimit(h, classic)`. The Roblox camera
is posed on the view: far away at `CamFov` with the filter on, at `CamOffFov` in the classic style.

### 9.3 `PixelRenderer`
`init`, `start`, `setTier(t)`, `tier`, `isActive`, `unavailableReason`, `pixelScale` (K), `firstPicture() -> (shown,
progress)`, `registerDynamic(model)`, `unregisterDynamic`, `refreshDynamic`, `rebake`, `setPaused`,
`project(world) -> (Vector2 full-screen px, on)`, `projectPixel(world) -> (i, j, on)`, `debugStatic()` (CLI checks),
`Changed: Signal<PixelTier>`. A change under `Workspace.Plots` (a move) re-bakes behind the old picture. Raycasts
exclude `Workspace.PixelDynamic`, where the crew live.

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
cheering on a spark. The week's `work` pops float over their heads ("+12" in the score's colour, "Spark! +N" in gold).
`rigCount()` for the sims.

### 10.3 `Hud`
Chips (date, with "II" while paused; money; fans; RP), the menu bar (`Menu_newgame`, `Menu_staff`,
`Menu_research`, `Menu_office`, `Menu_games`; New game is off while a game is in the works), the project card
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

## 11. Verification

- `bash scripts/check.sh`: Rojo sourcemap, luau-lsp strict analysis (0 errors), luau-compile, the specs (`tests/run.luau`
  lists them: Util, Validate, Numbers, Calendar, DataIntegrity, Crew, Dev, Economy, Schema, Shading, Raster, Rim,
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
`PixelRenderer` (one still view, no street, no pans, no Actors) and `CameraController` (one fitted view).
