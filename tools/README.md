# Tools

Command-line tools for building and testing Driftling Isle without Roblox Studio. `docs/WORKFLOW.md` says when to
use which. They come from Random Bakery (`Downvote/test`): the fake engine is game-agnostic and copied as is; the
harness, the scenarios and the preview driver are this game's own.

## Install

```sh
sh tools/setup.sh
```

Puts `rojo`, `luau` (with `luau-analyze`, `luau-compile`), and `luau-lsp` into `~/.local/rbx-tools/bin` (or
`$TOOLS/bin`). Linux x86_64, needs `curl`, `unzip` and GitHub access. Versions: `ROJO_VERSION` (7.4.4, as in
`rokit.toml`), `LUAU_VERSION` (latest), `LUAU_LSP_VERSION` (1.70.1). Roblox's API types for luau-lsp are in
`tools/defs/globalTypes.d.luau` (from luau-lsp; regenerate it from a newer luau-lsp release when Roblox adds APIs).

For a cloud environment, put `sh tools/setup.sh` in the environment's setup script so every new session has the tools.
Every script below finds them through `TOOLS` (default `~/.local/rbx-tools`).

The previews also need Python 3 with Pillow and numpy (`pip install pillow numpy`) and the system fonts DejaVu.

## The check

```sh
bash scripts/check.sh
```

Rojo sourcemap, luau-lsp strict analysis of `src`, luau-compile (catches compiler limits luau-lsp cannot see, such as
200 locals or upvalues in one function), the spec tests in `tests/` (run with plain `luau` on a copy of
`src/shared`), the Rojo build. Must end with `ALL CHECKS PASSED`.

## The simulator: `tools/sim`

A fake Roblox engine (`engine.luau`, `inst.luau`, `classes.luau`, `services.luau`, `loader.luau`; `defs_gen.luau` is
generated from the API types by `gen_defs.py`) that boots the game's real server and client scripts from the Rojo
tree, with players, DataStores (`E.cloud.stores["BSS_Profile_v1/global"]`), remotes, GUI and time. `harness.luau`
gives scenarios their helpers and `report.luau` prints the result:

- players: `H.addPlayer({ userId, name })` joins one with a full client and, like Roblox with
  `Players.CharacterAutoLoads` on, a character half a second later (the founder: PlotService puts it on the player's
  footpath, AvatarView draws it); `noCharacter = true` joins without one, `charDelay` sets another delay,
  `client = false` joins with no client at all (a server-side player: a neighbour, a full street). The fake engine
  does not read project properties, so the harness decides;
- modules: `H.smod(name)` (a server service), `H.sharedServer("Logic.Island")`, `H.cmod(p, "UI.UIKit")` (the client's
  copy), `H.session(p)`, `H.profile(p)`, `H.view(p)` (the client's ClientView), `H.push(p)` (after a test changed the
  server profile: mark it dirty and let the view arrive);
- requests: `H.req(p, action, payload)` (StateClient.request, exactly what the UI does), `H.raw` / `H.rawArgs` (the
  remote directly: the malicious path), `H.signal` / `H.rawSignal`, `H.watchFx(p)` (every Fx message from now on);
- UI: `H.buttons`, `H.click(p, text)` (by a button's visible words; disabled buttons have `AutoButtonColor` false),
  `H.buttonNamed(p, name)` / `H.clickNamed(p, name)` (by the button's Instance name: `Menu_build`, `Place`, `Store`,
  `BuildDone`, `Home`..., where words repeat), `H.openPanel` / `H.closePanel` / `H.currentPanel` (UIKit's registered
  panels), `H.dumpButtons`;
- invariants: `H.checkProfile(p, label)` (finite, non-negative stores, shells and wood; the tier and tips in range;
  nothing of the expeditions left in the save, and no food or Tree of Life; pieces that exist and fit the island with
  unique uids and levels 1..3; no villagers; driftlings with unique ids, no levels and no `held`, working only at a
  building of their knack, at most `HelpMax` a building; a driftling in a hut that is one, never over its room; one
  with no hut never at work, and only while every hut is full; driftlings in the Index with clean mutations) and
  `H.checkMirror(p, label)` (the client's view equals the server's tier, tips and day; its stores within a tick's
  change; every driftling, with no `penN` or `tree`, their huts too; the same pieces; the view's tide the session's,
  drift by drift; no villagers); `H.expect` / `H.finding`, `H.diff` (a deep compare). (`H.treeUid` went with the
  tree.)

```sh
sh tools/sim/one.sh --gen "sim.luau:out_main.log" "sim_save.luau:out_save.log"
sh tools/sim/par.sh
```

`--gen` regenerates `sources.luau` from the current tree first (do it once after changing `src`; `REPO=<dir>` boots
another tree). Each `file:log[:arg]` runs one scenario in parallel and prints its `SIM REPORT`: checks, findings
(failed checks), errors, issues (things the engine flags, such as non-finite numbers sent over a remote), warnings.
`par.sh` runs every scenario. Run four or five at a time at most. Logs (`tools/sim/*.log`) and the generated sources
are git-ignored.

| Scenario | What it covers | Baseline |
|---|---|---|
| `sim.luau` | a new island end to end through the real client and its UI: the loading card up first and gone once the island shows (its title centred); the background music by the clock and the note switching it off and on; every sound event backed by a library sound, each of its takes too, the founder's footsteps heard; the starting wood and shells, nothing built, no food or tree; the campfire, the jetty and the HUD with the tips; the tide already full and floating past (one every `TideSecs`, `floor(life / secs)` at once, every third a cheap wood or farm common), the Tide card's best three (`TideView.best`) with their time-left bars, price tags only where they don't overlap a better one's and not while under the water, names for uncommon and better; a take with no hut refused (`no_hut`); building what the tips ask in wood (a camp, a patch, a hut, a stall), Build mode opening on the tip's tab with its building pulsing; a driftling taken by tapping it on the belt, hopping ashore and sent to work; the days turning (ticks with `tideSecs`, the rates in wood and shells); six seconds of the belt (one in every second, each gone after its life, no whole view sent for it, the plot's `Tide` attribute, each one on the lane where its time says); the Tide panel (Pace, Room, Odds, the best four with Take and their time left, rebuilt only when they change); the huts full and a world tag opening the swap picker, the picker going back to the list with a notice when its driftling floats off, the weakest sold for the new one; the Driftlings panel (mutations by name, Work, Move between huts and back in a swap, Sell in two taps, Tide); the Index panel, the founder's looks, settings; expanding for wood (refused short, the next island built ahead and swapped in, the cheer waiting for its picture); the questline (Go, a claim too early or during the tips refused, Claim paying and moving on); a malicious client (unknown and old actions, the pen and tree ones among them, NaN, infinity, huge strings, extra fields, bad `tide.take` payloads, a swap that isn't theirs, full with no swap; the shells checked apart, the island earning a little meanwhile); a flood (the rate limit); a second player drawing the first island's hut driftlings and both belts at the same places, with no price tags on the other's | 0 findings, 0 errors, 0 issues (its 2 deliberate non-finite payloads listed apart); about 960 checks |
| `sim_save.luau` | play (buildings, a driftling taken off the full belt into the hut, a mutated one beside it, more coming in and the oldest floating off), leave (saved with no tide, tree or food in the record, lock released, the island back to open water), rejoin to the very same profile with a fresh belt, full, its ids from 1 again; a version 11 save (a Tree of Life, food, driftlings in the pen) loading as version 12 with the tree and food gone and the pen sold for shells; a version 9 save (the wild places, the fights, the levels and a villager in a Tent) with its Training Yard's and its Tent's prices back, no villagers, its pen sold, its hut driftlings kept; a save never overwrites another server's live lock; a join waits out another server's lock and then takes over; a corrupt record loads into a valid profile keeping only what makes sense; a version 4 save (the game studio) starts a fresh island with the starting stores and every third one on its belt a cheap common | 0 findings, 0 errors, 0 issues; about 376 checks |
| `sim_world.luau` | the sea at start (a boardwalk stretch per plot, the sea's ends, open water with Owner 0 on all six plots); two islands on plots 1 and 2 (no house: Static.Land alone; its coast, the foam animated, the invisible coast walls in the `Bounds` collision group; the island's name, Tier, Day, the players' Founder and Plot attributes; the walls round the world higher than a jump), each with its belt in the plot's `Tide` attribute (`id.sp.at.life`, tenths of a second on the server's time, matching its session) and followed by both clients, the ones within 62 studs of the view drawn; the hut driftlings on both drawn by each client (no Folk attribute, the Pals attribute listing the hut driftlings), the signs' labels; the way from the jetty across the boardwalk to the pier's end open; the tide's lane clear of every tier's island (no part where a raft or a wide rider rides, the jetty apart); the camera keeping the founder in the middle of the screen; a founder walked onto the neighbour's island (Home shows), char.home back and its cooldown; building in wood: place, move, no upgrades, replace (a home refused: they are gone), clear away (half the wood back; a hut with driftlings in it cleared away leaves them waiting with no hut), the piece limit, with every refusal, Static.Decor following piece by piece; the same through Build mode's UI (tabs, a ghost on a cyan frame, red on the plaza, Replace); drawing paths (Line, Box, Erase refunding wood); malicious plot payloads; a player leaving (its `Tide` attribute cleared and its belt gone from every client within half a second, none hopping onto open water) and a newcomer on the freed island (a full belt, every third a cheap common, its own price tags only, names for uncommon and better, every kind of piece placed and cleared, no tree to buy) | 0 findings, 0 errors, 0 issues (its deliberate NaN payload is listed apart); 372 checks |
| `sim_clock.luau` | a turn every `TurnSeconds` (an Fx turn each, not a day; an Fx tick every second with `tideSecs`), two huts full of driftlings at work; eighty seconds of the belt on the server's time (one in a second, each `at` a beat after the last and heard within a quarter second, each gone at `at + life`, as many going as coming, only the turns' whole views sent, the view's tide and `StateClient.along` matching the session, the Tide card's time-left bars to a pixel); ten seconds of making matching `Island.rates` (wood and shells), the view's rates following; a panel and Build mode holding nothing; nothing eats (empty stores still grow, no food chip); a Clawdle waiting with no hut while the huts are full, moving into a new hut and fishing once a pier goes up, the island expanded round its buildings; two islands each on its own turn clock and its own full belt under one sea's time of day; day and night (`DayLight.at`; the sea's clock jumped to noon, night and morning); the Hatchery (through the panels as a player: a parent in each slot, `Breed_<uid>`, the feast paid in shells, refused with none; the shared mutation passed on; two eggs hatching, one into the last hut place and one waiting until a sale frees one; the Hatcheries cleared away once empty) | 0 findings, 0 errors, 0 issues; 1050 checks |
| `sim_tide.luau` | the belt end to end (`Logic/Tide`, the session's tide, `Controllers/TideView`, the HUD's Tide card, the Tide panel and its swap picker): full at join, `secs` apart on the server's time, every third a cheap wood or farm common until one is taken; `no_hut`, `not_found`, `money`, `full` and 14 bad payloads refused with nothing changed; six seconds of flow (one in and one gone a second, never one past its life, the attribute and the client's patched view matching, no whole view sent, the Index following, each floating east at 80 / life studs a second); taking from the card, a world tag and by tapping the driftling (a tap on the island takes nothing), each hopping ashore; the panel's best four with their time left, rebuilt only when they change; the swap picker, and its driftling floating off while it's open; the huts' tide shares running the belt faster; selling, a cleared hut and a new one; prices after an expansion; a neighbour's belt followed and drawn near the view with no price tags, its taken ones hopping off; and in every phase the world check (each one at x0 + 80k on the lane at the right depth, drawn near the view, tags over their driftling, never under, never overlapping, the best worker above water always tagged) | 0 findings, 0 errors, 0 issues; about 1391 checks |

`boot.luau` is a smoke test with no checks: it boots one player and prints what is there.

Known quirks: `os.clock` is simulated (timing checks are about the game's own clock, not real frame cost); the
engine's GUI hit test ignores `UIScale`; the pixel renderer runs in the sims without a real picture (the sims set no
EditableImages: the classic style, so `PixelRenderer.project` / `screenRay` go through the fake camera; the picture
is checked in the previews instead); `workspace:Raycast` hits only a ground plane at y = 0 unless a scenario sets
a Humanoid's `FloorMaterial` is Plastic (it stands on something; the sims never put one in the air);
`E.raycastParts = true` (then every part, slowly: sim_world turns it on just around a tap that must hit a piece; as in
Roblox, `CanQuery = false` only counts on a part that doesn't collide, and a part whose collision group doesn't
collide with the ray's `CollisionGroup` is passed through, so the island's invisible coast walls stop a ray that isn't
in the pixel filter's `PixelRays` group); the
fake engine shares one DataModel between the clients, so a client-only folder such as `Workspace.PixelDynamic` holds
every client's rigs (count them through the modules: `WorldView.rigCount` / `ownRigCount`, `AvatarView.count`).
The fake engine has a `PhysicsService` (collision groups registered, `CollisionGroupSetCollidable`); the previews'
raycaster honours a `RaycastParams.CollisionGroup` through `E.collisionGroupsCollide`, so the pixel filter's rays pass
the invisible walls as in Roblox.

## The previews: `tools/preview`

Boots the game in the same fake engine (copies with three hooks: part geometry changes, reparenting, property
writes) with the real `PixelRenderer`, lets it cast its rays against the real islands and stages (`raycast.luau`: exact Block /
Ball / Cylinder / Wedge / CornerWedge intersection, a BVH), captures what it writes into its `EditableImage`
(`capture.luau`), lays out the real `PlayerGui` (`guiengine.luau`) and writes PNGs at device sizes (`topng.py`).

```sh
PREVIEW_KEEP=1 sh tools/preview/render.sh <scenario> <outdir> "desktop phone" [tier]
```

| Scenario | Frames | What happens |
|---|---|---|
| `island` | `island` | a brand-new island: its shore, the campfire's plaza, the path and the jetty, the founder in the middle of the view, the HUD with the first tip |
| `village` | `village` | a tier-1 village a dozen days in (nineteen pieces, five huts, its driftlings working and hopping), the island card |
| `tide` | `tide`, `tide_flow`, `tide_take`, `tide_night` | the tide past a village (GAME_DESIGN 6), the founder at the jetty: driftlings on their rafts riding the lane between the foam and the boardwalk, one every 5 studs, a rare one with its lantern just west of the jetty and an epic just past it (put in the places of two already there), the price tags over them and the names over the uncommon and better ones (`tide`); two and a half seconds on, the whole belt moved along, one more come up at the west end and one gone down at the east (`tide_flow`); the dearest one with a tag shown that the shells cover taken in by its price tag (`TideTake_<id>`), hopping onto the jetty (`tide_take`); then the same at night (0.88), the lanterns lighting the water round them (`tide_night`) |
| `island2`, `island3` | `island2`, `island3` | a Palm Isle (tier 2) with the village's pieces / a Grand Isle (tier 3) with every kind of building (upgraded makers, the lighthouse, the statue, the fountain) and eight driftlings |
| `day` | `day` | a new day's banner |
| `panel=<name>` | `panel_<name>` | the panel `UIKit.openPanel(name)` opened (`pals`, `tide` (how often one comes, the huts' room, the odds, the best four floating by with their prices and the time each has left), `index`, `looks`) for a tier 2 village with driftlings in its huts; `hatch`: a harbour island (tier 3) with two Hatcheries, one warming a Rare egg, the other with two parents picked through the panel (the likely child not grown yet: its shape and ???) |
| `sea` | `sea`, `sea_fresh` | the founder walked onto the boardwalk between their island and a neighbour's village (a server-side player), the camera following; then the same pan baked from scratch (`PixelRenderer.rebake`) to compare a scrolled picture with a fresh one |
| `visit` | `visit` | the founder on the neighbour's island while their driftlings work |
| `build` | `build_tray`, `build`, `build_red`, `build_tip`, `build_replace` | Build mode opened from the HUD (the tray opens on the Wood tab), a lumber camp picked and its ghost tapped onto a cell where it fits (cyan), then onto the campfire's plaza (red, Place off); then the tips set to the stall's step (`tut` 5, the island has no stall yet) and Build mode opened again, the tip's banner over the tray, the tray turned to the Shops tab and the stall's card pulsing; then on a tier-2 island a Driftling Hut tapped and Replace: the tray listing the huts of its kind with their room and prices after the hut's refund |
| `expand` | `expand_before`, `expand_after` | a tier-1 village in Build mode; the next island is ready (built ahead on the server), Expand: the log says whether it was swapped in, how many frames passed before "Your island grew.", how long the filter's re-bake took and how many times the picture was composed meanwhile (it keeps moving: not 0); then the bigger island |
| `paths` | `paths_draw`, `paths_box` | Build mode's draw bar on a village: a path picked (Line, Box, Erase, Look around), then a box stroke laying a block of Stone Path tiles; the log counts the tiles laid |
| `zoo` | `zoo_<n>_idle`, `zoo_<n>_cheer` | every driftling (Models/DriftModels) on the home island's lawn in batches of 20, five a row, turned three-quarters to the viewer, idle and cheering (the HUD off); the log lists each batch's species in order |
| `city` | `city`, `city_north`, `city_night` | a tier-6 capital (GAME_DESIGN 4.1): brick roads in a grid, marble walks round the plaza, the blocks filled with the town and city buildings (the town hall, a clock tower, the bazaar, the grand hotel, the beacon, dens and burrows, parks), street lamps, hedges and trees; 16 driftlings about; by the plaza, then the founder further north in the heart of the city, then the same at night (each light's pool as big as the light) |
| `gallery` | `gallery_1` .. `gallery_6` | every piece from tier 3 up, the boosts, the paths and the newer decor laid out in rows on a capital (nobody living there yet), captured from six spots: a close look at each model |
| `dusk`, `night`, `dawn` | `dusk`, `night` (and `night_pan_1` .. `6`), `dawn` | the village with the day held at a golden dusk (0.7), at night with its lamps, torches and fire lit (0.88; then the founder walks on and the view pans, the lamps' pools going with the picture), at a rosy dawn (0.02) (`DayLight.debugSet`) |
| `water` | `water_000` .. `water_011` | the village, then a frame every sixth of a second for two seconds: the sea, the shallows and the foam moving, the leaves swaying and the flags rippling (`python3 tools/preview/make_gif.py <outdir> water desktop 6 0.6666667` makes a 1280x720 GIF, two screen px an art px) |
| `work` | `work`, `work_000` .. `work_015` | the village a while on, its driftlings at work at the fields, the lumber camp, the pier and the stall, or napping at a hut, then a frame every eighth of a second for two seconds (`python3 tools/preview/make_gif.py <outdir> work desktop`) |
| `late` | `late_inset`, `late_turn` | the screen's size settling after the HUD is built, the two ways Roblox does it: the top bar's inset arriving with no ViewportSize event (the roots shrink on their own), then the screen turning with ViewportSize fired before the roots are laid out again (`E.guiViewport`); the log line `late <case>: menu bar at y .. on a WxH screen: ON SCREEN / HIDDEN` says whether the HUD's menu bar is still wholly on screen at the bottom |
| `loading` | `loading`, `loading_000` .. `loading_015` | the loading card (src/first/LoadingCard) while a new player's game loads: a still a second in and a frame every fifth of a second while it is up (`make_gif.py <outdir> loading desktop 5`); the log gives its phase, bar, actors, whether it painted, its pixel size and canvas |
| `ploadingart` | `ploadingart_sheet` | the loading card's scene art drawn through the game's own picture path (`loading_art.luau`: the island's driftlings walking and a Conchy cheering, palms, huts, campfire and the boat through `Pixel/Snapshot`, plus the hand-made gull, star, crest, ember and glint), logged as `@@LART` / `@@LSEQ` / `@@LPT` lines; run it through `sh tools/preview/loading_art.sh [outdir]`, which packs them into `src/first/LoadingArt.luau` (`gen_loading_art.py`: one palette, a sequence's colours, run-length frames, an atlas) and keeps `sheet.png` and `atlas.png` in `outdir` |
| `pportraits` | `pportraits_sheet` | the driftlings' portraits drawn from their models (`portraits.luau`: each driftling's model at rest, eyes open, turned 30 degrees, its head made bigger, its eyes in its body plan's style (`EYE_STYLE`: size, an iris from the species' accent, a dot, slit or bar pupil, a glint or a glow) and the camera at 15 degrees so it reads small, fitted to 32 x 32 through `Pixel/Snapshot`), logged as `@@PORT <species> <w> <h> <RGBA hex>` lines; run it through `sh tools/preview/portraits.sh [outdir]`, which tidies them to the pixel art rules into `scripts/portraits.txt` (`gen_portraits.py`) and remakes `src/client/UI/ArtData.luau` (`scripts/gen_art.py`), keeping `sheet.png` (each portrait raw and tidied at 8x) in `outdir` |
| `pportraits_try` | `pportraits_sheet` | one driftling of each body plan at the chosen angle, to try a change before baking them all (`python3 tools/preview/gen_portraits.py <log> --no-out --raw --sheet <png>`) |
| `all` | | `island`, `village`, `island3`, `sea`, `build`, `day` |

Devices: `desktop` 1920x1080 mouse, `phone` 844x390 touch, also `laptop`, `tablet`, `portrait`, `android`, `iphone8`,
`desktop1440`. Tier: `auto` (the game's default, high), `low`, `medium`, `high`, `off`. `REPO=<dir>` renders another
tree, `PREVIEW_JOBS` sets the parallel runs (4), `PREVIEW_FLAGS="--ui --boxes --no-core"` adds the GUI alone, every
GuiObject outlined with its name, or hides the approximate Roblox core UI. `PREVIEW_KEEP=1` keeps each run's log in
`<outdir>/_logs`: the `settled` line (tier, layer size, K, bake rays) and the `camera` line (art px per stud, pan, the
framing box on screen) are there. Put renders outside the repository (`tools/preview/work/` and `out*/` are
git-ignored).

A new scenario is a function in `preview.luau`'s `SCEN` table: `join(userId, name, opts)` (opts as `H.addPlayer`'s:
`client = false` for a neighbour), or `seedProfile(userId, tier, opts)` first for a saved island (pieces,
driftlings (`pals`: into the huts with room, the best first), `shells`, `wood`, `day`, `tut`, `seen`, an `egg`),
drive it with `H.req` / `H.click` / `H.clickNamed` / `H.openPanel` / `walkTo(p, x, z)` (the founder put at a world
point, the view left to follow), `settle(p)` until the picture is baked and quiet (its pan caught up with the
camera's, no re-cast waiting), `capture(p, label)`; add its name to `render.sh`'s
list. To compare a scrolled picture with a fresh bake, capture, call `PixelRenderer.rebake()` in the client, settle
and capture again, then diff the two PNGs (only the animated islanders should differ).
`make_gif.py` turns consecutive frames into an animated GIF, `stitch.py` stitches frames, `label_cells.py` labels
contact-sheet cells.

Known gaps (from Random Bakery's preview): timing is not real (`os.clock` is simulated, so the bake's time slicing
runs but the picture looks finished sooner than in Studio); tweens jump to their end values; fonts other than the
game's pixel font are stand-ins (Press Start 2P, Montserrat, DejaVu); the Roblox core UI is approximate (a 58 px top
bar, the touch jump button); Actors run serially.
