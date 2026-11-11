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
- invariants: `H.checkProfile(p, label)` (finite, non-negative stores; the tier, islets and tips in range; pieces
  that exist and fit the island with unique uids and levels 1..3; villagers and driftlings with unique ids, within
  their limits, levels in range, working only where they may, one a building; driftlings marked befriended; the
  Index's species; an expedition's party all from the island with sane health) and `H.checkMirror(p, label)` (the
  client's view equals the server's tier, tips, day and islets; its stores within a tick's change; the same villagers,
  driftlings and pieces; the expedition on both or neither, at the same stop); `H.expect` /
  `H.finding`, `H.diff` (a deep compare).

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
| `sim.luau` | a new island (the tent's castaway moving in at once and announced; the sea chart's party filled with the strongest by itself; the tips' fighting note in the first battle and the catching one after, a snack made certain once to catch a driftling and reach the last tip; its stores, the land under `Workspace.Plots.Plot_1.Static` with the campfire's stones and the jetty's planks, "Pixel's Isle", the founder, the menu bar, the first tips without OK; the island's music playing, `MusicToggle` switching it off and on, kept in `settings.music`); Build mode at the first tip (the tray on the Food tab with the patch to build, the tip's banner over the tray, the other tabs still open to look at; the patch placed: the tray turned to the Wood tab and the lumber camp, the next tip over it; Done: the tray gone, the tip still up); building a patch, a camp, a stall, a tent and a nest out of the starting shells (prices in shells and wood, the tips moving on from food to wood, shells, the tent and the nest, "locked" for a bigger island's building, not enough shells or wood refused; the view's pieces, beds and nests; a model a piece); the first turn (an Fx turn, not a day, a castaway moving into the tent and taking a job at once, an Fx tick every second of the turn; the sea's clock jumped to a day's end counting a day (Fx day) and the view's clock at dawn; the villager walking the island, food and wood coming in); a job through the Villagers panel (`Job_<id>`, `Go_<uid>`); an expedition through the Explore panel's sea chart (the map and an island picked, the islands in range with their `Isle_<id>` buttons, one out of range saying it is too far; `BoatUp` buying boat 2 (shells and wood paid, the pier's `Boat` rebuilt at `Level` 2); `Isle_1` picked, `Member_v<id>`, `SetSail`: island 1 with a name, supplies, the tips, the villager away), the sailing cutscene (the boat at the pier, then gone from it, the screen waiting; walk, hop aboard, sail), the islet's screen after it (the curtain lifting on the party, the boat bringing them ashore, no Go on button: the expedition going on by itself to the next stop), its stops and timed battles running by themselves (a timer over the fighters' heads; snacks thrown at hurt wild ones through `ExpeditionUI.debugSnack`, Rally Cry through `debugSkill` once the skill points cover it; no Onward card to tap after a win) until the island's first guardian falls (the path goes on) or the party does, home with the loot (half after a fall), the island charted, its driftlings in the Index; the way home (the blinds over the stage, `Voyage.home`'s arrive, hop and land, the boat back at the pier, the founder on it, clear of the pier's walls and able to walk again, the HUD back); the Driftlings panel (its mutations on its row by name, `Mut_<id>`; `Help_<id>`, the picker, Release asking Sure? first); the looks; every panel; settings; the last tip's OK; Expand from the build tray (the next island built ahead in the background and ready, the
expansion swapping it in (`PlotService.debugNext`), one `Land` after it, the island after that planned, "Your island
grew!" within 1.5 s; the filter is off here, so it comes at once); a malicious client (unknown and old actions, NaN, infinity, huge strings, extra fields, string payloads, bad parties, a villager not there, an infinite island, an island past the boat's range (far), one not on the chart, the old level field, steps and battles with no expedition, the old battle move, a snack with no expedition or at the leader, a wild one's skill, a skill with no expedition, a pause that is not on or off, a bad look, a flood against the rate limit: each refused with its ErrCode, nothing changed); a second player on island 2 | 0 findings, 0 errors, 0 issues (the 2 deliberate non-finite payloads are listed apart); about 640 checks (a few more or fewer as the battles go) |
| `sim_save.luau` | play (buildings, a villager moved in, a driftling with two mutations kept through the save, an upgrade), leave (saved, lock released, the island back to open water), rejoin to the very same profile; leaving mid-expedition (the loot gathered comes home, no expedition after the rejoin); a save never overwrites another server's live lock; a join waits out another server's lock and then takes over; a corrupt record (bad stores, an unknown tier, junk villagers, an unknown species, a piece off the island, an unknown piece) loads into a valid profile keeping only what makes sense (the piece off the island moved onto it); a version 4 save (the game studio) starts a fresh island keeping the founder, settings and start | 0 findings, 0 errors, 0 issues; about 227 checks (the profile checks count the Index's entries) |
| `sim_world.luau` | the sea at start (a boardwalk stretch per plot, the sea's ends, open water with Owner 0 on all six plots); two islands on plots 1 and 2 (no house: Static.Land alone; its coast of grass, foam and shallows, the foam animated (`PixelWater` 3), the invisible coast walls in the `Bounds` collision group; the island's name, Tier, Day, Sailing, the players' Founder and Plot attributes, each founder on their path; the walls round the world higher than a jump); villagers and driftlings on both drawn by each client (own and the neighbour's, both founders; the Folk and Pals attributes), the signs' labels; the way from the jetty across the boardwalk to the pier's end open (no collidable part in its middle, on an island's plot and an empty one); the camera keeping the founder in the middle of the screen between the HUD's strips at home, on the neighbour's island and across the own (`Render.Raster.gridPoint` at the camera's pan); a founder walked onto the neighbour's island (Home shows), char.home back and its cooldown; building: place (shells and wood paid; "blocked" on a piece, the plaza, the path; "outside" off the grass; "locked" a bigger island's building), Static.Decor's models named uid:id:x:z:rot:lvl, move turned, upgrade to Lv 2 and 3 (its price; no Lv 4; a home has none), clear away (half back; the only home with villagers stays), the piece limit; Build mode through the HUD (the Food and Decor tabs, a locked card, a ghost on a cyan frame where tapped, Place, red on the plaza, Cancel, picking decor up (Clear away, no Upgrade) and a building (Upgrade), Done); malicious plot payloads; a player leaving (their islanders gone from the other client); a newcomer on the freed island; a full sea kicking the seventh player; homes upgrade (comfort), decor does not; replacing refused for another kind, a past-the-pieces index, an unknown piece, a capital's home on a small island; a farm replaced through the UI (`Replace`, `SwapTo_<id>`: where it stood, its uid kept, the new model built); drawing paths (a path picked opens the draw bar: Line, Box, Erase, Look around, Cancel; a box stroke's plan and its glowing plates, `plot.paint` laying the tiles and paying, cells off the grass skipped, `plot.unpaint` lifting them with the refund, bad cell strings refused) | 0 findings, 0 errors, 0 issues (its deliberate NaN payload is listed apart); 257 checks |
| `sim_clock.luau` | a turn every `TurnSeconds` (an Fx turn each, not a day; an Fx tick every second), villagers moving into the beds; ten seconds of making and eating matching `Island.rates` (food, wood, the stall's shells), the view's rates and food following; a panel and Build mode holding nothing; hunger (the food at none, the shops shut, the view saying so) and fed again; moving in (no free bed, not charming enough, then decor raising the charm), the island expanded twice round its buildings (none moved or lost); the training yard training a resting villager; a working villager away on an expedition (the island making without them, the Folk attribute marking them away, back at work at home); two islands each on its own turn clock under one sea's time of day; day and night (`DayLight.at`: no grade at noon, dark with the lamps lit at night, a warm dusk; the sea's clock jumped to noon, night and morning: plain, dark, bright, through Roblox's own clock with the filter off as here); the Hatchery (expanded to the third tier, a Hatchery and a burrow; through the panels as a player: the Driftlings panel's `OpenHatch`, a parent in each slot (`Slot_a_<uid>`, `PickParent_<id>`, the first not offered again), `Breed_<uid>`: an egg of their kind, the feast eaten, the shared mutation passed on; refused: a second egg, no Hatchery, the same parent twice, a bad payload, clearing it away with the egg in it; the egg's turns, then hatched (the turn's news), a level-1 driftling of its kind in a nest, the Hatchery cleared away once empty) | 0 findings, 0 errors, 0 issues; 445 checks |
| `sim_exp.luau` | the server's rules (supplies for four, no island past the boat's range (far), no boat or pouch upgrade while away (busy), the captain and three set sail (the answer names the island, five snacks for the trip), one expedition at a time, a member away can't be dismissed, no snack, skill or pause before a battle, no stepping on or sailing home mid-battle); the timed battle (a new one waits paused till let run, then the timers fill and the fighters act, the actions and the timers reach the client as Fx, paused again all stops); snacks (a free nest needed, none left none thrown, thrown until a wild one is befriended (in the Index), the leader's timer starting again each throw); skills (a skill waits for its points, only one the user has learnt, Rally Cry paid in three points); a flight; the guardian (no snack, no flight); the islet's screen (the HUD's card `ExpContinue`, the music turned to the sea's, a timer over every head, the battle running once the screen is up with no taps, Skills but no Snack or Flee against the guardian, no Fight, Guard or Auto, blows landing by themselves; the skill window pausing it and Back letting it run, the leader's skills learnt by level; First Aid aimed with the leader's ring and an arrow on the floor reaching all the way to the pick, paused while aiming; the pointer over another member picking them (hovering: not used yet) and the arrow gliding over, a tap on a wild one no pick for a mend, a tap on the pick using it (paid in points); Use! doing the same; Back to island leaving the expedition waiting, paused); a bigger pouch (ten snacks a trip); the guardian beaten (the island charted, all the loot home); the boat upgraded to the top (then max), and eight islands across the chart (2, 8, 16, 24, 32 and the three furthest) each charted by a strong party (a kind open at its level, the island the chart's, only its own driftlings, one more charted, the guardian's reward; at least three kinds); a closer look (`debugInspect`: the plate over a
fighter's head with its stats and mutations, gone again); the battle clock standing still while aiming, in the
skill window and under the leave card, and running again after; the leave card (Back to island mid-battle: the
battle held, `LeaveStay` letting it run on, `LeaveWait` closing the screen with the trip waiting); mid-battle on the
server (a snack thrown while an attack plays cancels it: the `cancel` event first, the attacker's damage undone,
its timer from nothing; `LeaveHome` mid-battle: the trip over, the screen closed, the founder home with Build back);
the tutorial's sure catch (steps 6 and 7) and the usual odds after the tips; the run on (Go on: the party runs to the
next area, Back to island open on the way, everyone at their places after, the camera gone right with them, the
areas ahead built and the ones behind dropped, a battle's wild ones standing in the area on its right with none
dropping in, the battle starting once the party is there); island 2 sailed to again (the same island, half the reward, charted once); the endless path (on past the first guardian to a second at the second block's end, paying more, the wild ones growing, and on); a defeat at the chart's furthest island (all the loot home: no penalty, everyone back; the defeat's `loot` and
`gained` for the Expedition Complete! card); a friend made on the screen (a snack befriending the last wild one: the battle over on the server at once, the wild one still on the stage through the throw, the arc and the hearts, then gone in its poof) | 0 findings, 0 errors, 0 issues; about 500 checks (the profile checks count the Index's entries, which the battles decide) |

`boot.luau` is a smoke test with no checks: it boots one player and prints what is there.

Known quirks: `os.clock` is simulated (timing checks are about the game's own clock, not real frame cost); the
engine's GUI hit test ignores `UIScale`; the pixel renderer runs in the sims without a real picture (the sims set no
EditableImages: the classic style, so `PixelRenderer.project` / `screenRay` go through the fake camera; the picture
is checked in the previews instead); `workspace:Raycast` hits only a ground plane at y = 0 unless a scenario sets
`E.raycastParts = true` (then every part, slowly: sim_world turns it on just around a tap that must hit a piece); the
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
| `village` | `village` | a tier-1 village a dozen days in (nineteen pieces, four villagers at work, three driftlings helping and hopping), the island card |
| `island2`, `island3` | `island2`, `island3` | a Palm Isle (tier 2) with the village's pieces / a Grand Isle (tier 3) with every kind of building (upgraded makers, the lighthouse, the statue, the fountain), villagers and eight driftlings |
| `day` | `day` | a new day's banner (a visitor moving in) |
| `panel=<name>` | `panel_<name>` | the panel `UIKit.openPanel(name)` opened (`folk`, `pals`, `explore` (the sea chart) with a villager and a driftling picked, `index`, `looks`) for a village with two islets cleared; `hatch`: a harbour island (tier 3) with two Hatcheries, one warming a Rare egg, the other with two parents picked through the panel (the likely child unmet: its shape and ???) |
| `exp=<kind>[_<what>]` | `exp_<spec>` | an expedition to an island of a kind (1 beach, 2 meadow, 3 volcano, 4 snowfield, 5 reef, 6 mangrove, 7 grotto, 8 bluffs, 9 ruins) a level past where it turns up, the first seed that charts it (the same layout every run), on its 3D stage with a party of four: `battle` (default: the first battle a few seconds in, the timers over the heads), `boss` (the guardian), `snack` (aiming a snack: the picture greyed and paused, the leader's ring and the arrow on the floor all the way to the wild one picked, its ring, the pointer over it, the plate saying how to pick), `tut` (a battle in the tips' catching step: its note over the footer), `throw` (a snack befriending the last wild one frame by frame, `exp_<n>_throw_000` .. `039` every 0.06 s: the throw, the arc, the hearts, the happy hop and the poof), `aim` (aiming frame by frame, `exp_<n>_aim_000` .. `039` every 0.06 s: the arrow growing out of the leader's ring to the pick, then swinging over to the last wild one as the pointer moves over it; `make_gif.py <outdir> exp_<n>_aim desktop 16`), `skills` (the skill window: each fighter's skills learnt by level and their points), `win` (a won battle's results card), `lose` (the party falls to wild ones made unbeatable: the Expedition Complete! card with the loot, xp and levels), `inspect` (a closer look: the first wild one given three mutations and the plate over its head as a hover shows it), `run` (the run on to the next area frame by frame, `exp_<n>_run_000` .. `023` every 0.12 s, the auto Go on held: the party walking forward up the road from one platform to the next, the camera following, then the stop's wild ones standing there; `make_gif.py <outdir> exp_<n>_run desktop 8`), `loot` (a stop's narration), `fight` (the battle frame by frame, `exp_<n>_fight_000` .. `039` every 0.07 s: the timers filling, the wind-ups, dashes, strikes, hit-stops and knock-backs; `make_gif.py <outdir> exp_<n>_fight desktop 14` makes a GIF); e.g. `exp=4_boss`; a battle's log names the party's area and the areas built round it (`battle: area 2, areas built 1,2,3,4`) |
| `sea` | `sea`, `sea_fresh` | the founder walked onto the boardwalk between their island and a neighbour's village (a server-side player), the camera following; then the same pan baked from scratch (`PixelRenderer.rebake`) to compare a scrolled picture with a fresh one |
| `visit` | `visit` | the founder on the neighbour's island while their villagers work |
| `build` | `build_tray`, `build`, `build_red`, `build_tip`, `build_replace` | Build mode opened from the HUD (the tray's Food tab), a lumber camp picked and its ghost tapped onto a cell where it fits (cyan), then onto the campfire's plaza (red, Place off); then the second tip under way: Build mode opened again on the Wood tab, the lumber camp's card pulsing, the tip's banner over the tray; then on a tier-2 island the tent tapped and Replace: the tray listing the homes of its kind with their beds and prices after the tent's refund |
| `expand` | `expand_before`, `expand_after` | a tier-1 village in Build mode; the next island is ready (built ahead on the server), Expand: the log says whether it was swapped in, how many frames passed before "Your island grew.", how long the filter's re-bake took and how many times the picture was composed meanwhile (it keeps moving: not 0); then the bigger island |
| `paths` | `paths_draw`, `paths_box` | Build mode's draw bar on a village: a path picked (Line, Box, Erase, Look around), then a box stroke laying a block of Stone Path tiles; the log counts the tiles laid |
| `zoo` | `zoo_<n>_idle`, `zoo_<n>_attack` | every driftling (Models/DriftModels) on a meadow islet's stage in batches of 20, five a row, turned three-quarters to the viewer, idle and mid-attack; the log lists each batch's species in order |
| `city` | `city`, `city_north` | a tier-6 capital (GAME_DESIGN 4.1): brick roads in a grid, marble walks round the plaza, the blocks filled with the town and city buildings (townhouses, villas, a manor, the town hall, a clock tower, the bazaar, the grand hotel, the beacon, parks), street lamps, hedges and trees; 40 villagers and 16 driftlings about; by the plaza, then the founder further north in the heart of the city |
| `gallery` | `gallery_1` .. `gallery_6` | every piece from tier 3 up, the boosts, the paths and the newer decor laid out in rows on a capital (nobody living there yet), captured from six spots: a close look at each model |
| `voyage` | `voyage_panel`, `voyage_000` .., `voyage_walk`, `voyage_board`, `voyage_arrive`, `voyage_home` | the Explore panel (the sea chart, island 2 picked, a villager and a driftling), then after Set sail a frame every fifth of a second: the founder walking down to the pier, hopping aboard, the boat sailing off with the view, the blinds on the island's name, the islet's screen with the boat bringing the party ashore (the curtain waits for the picture: `ExpeditionUI.debugWait`); then the expedition ended and the way home: the blinds closing over the stage, opening on the sea, the boat sailing in to the pier and the founder hopping ashore (`voyage_home`); `make_gif.py <outdir> voyage desktop 5` makes a GIF |
| `dusk`, `night`, `dawn` | `dusk`, `night` (and `night_pan_1` .. `6`), `dawn` | the village with the day held at a golden dusk (0.7), at night with its lamps, torches and fire lit (0.88; then the founder walks on and the view pans, the lamps' pools going with the picture), at a rosy dawn (0.02) (`DayLight.debugSet`) |
| `water` | `water_000` .. `water_011` | the village, then a frame every sixth of a second for two seconds: the sea, the shallows and the foam moving, the leaves swaying and the flags rippling (`python3 tools/preview/make_gif.py <outdir> water desktop 6 0.6666667` makes a 1280x720 GIF, two screen px an art px) |
| `late` | `late_inset`, `late_turn` | the screen's size settling after the HUD is built, the two ways Roblox does it: the top bar's inset arriving with no ViewportSize event (the roots shrink on their own), then the screen turning with ViewportSize fired before the roots are laid out again (`E.guiViewport`); the log line `late <case>: menu bar at y .. on a WxH screen: ON SCREEN / HIDDEN` says whether the HUD's menu bar is still wholly on screen at the bottom |
| `all` | | `island`, `village`, `island3`, `sea`, `build`, `day` |

Devices: `desktop` 1920x1080 mouse, `phone` 844x390 touch, also `laptop`, `tablet`, `portrait`, `android`, `iphone8`,
`desktop1440`. Tier: `auto` (the game's default, high), `low`, `medium`, `high`, `off`. `REPO=<dir>` renders another
tree, `PREVIEW_JOBS` sets the parallel runs (4), `PREVIEW_FLAGS="--ui --boxes --no-core"` adds the GUI alone, every
GuiObject outlined with its name, or hides the approximate Roblox core UI. `PREVIEW_KEEP=1` keeps each run's log in
`<outdir>/_logs`: the `settled` line (tier, layer size, K, bake rays) and the `camera` line (art px per stud, pan, the
framing box on screen) are there. Put renders outside the repository (`tools/preview/work/` and `out*/` are
git-ignored).

A new scenario is a function in `preview.luau`'s `SCEN` table: `join(userId, name, opts)` (opts as `H.addPlayer`'s:
`client = false` for a neighbour), or `seedProfile(userId, tier, opts)` first for a saved island (pieces, villagers,
driftlings, islets, stores),
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
