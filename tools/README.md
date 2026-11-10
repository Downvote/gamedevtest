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
| `sim.luau` | a new island (its stores, the hut under `Workspace.Plots.Plot_1.Static`, "Pixel's Isle", the founder, the menu bar, the first tips without OK); building food, a tent, a nest and a camp (prices in shells and wood, the tips moving on, "locked" for a bigger island's building, not enough shells or wood refused; the view's pieces, beds and nests; a model a piece); the first day (an Fx day, a castaway moving into the tent and taking a job at once, an Fx tick every second, the villager walking the island, food and wood coming in); a job through the Villagers panel (`Job_<id>`, `Go_<uid>`); an expedition through the Explore panel (`Member_v<id>`, `SetSail`: supplies, the tips, the villager away), the islet's screen (the curtain lifting on the party, `GoOn` / `SailHome`), its stops and battles played through `ExpeditionUI.debugGo` / `debugAct` (treats on hurt wild ones, a guard, `ResultOk`), home with the loot (half after a fall), Pebble Beach cleared; the Driftlings panel (`Help_<id>`, the picker, Release asking Sure? first); the looks; every panel; settings; the last tip's OK; Expand from the build tray (the lodge rebuilt); a malicious client (unknown and old actions, NaN, infinity, huge strings, extra fields, string payloads, bad parties, a villager not there, a locked islet, steps and battles with no expedition, an unknown battle move, a bad look, a flood against the rate limit: each refused with its ErrCode, nothing changed); a second player on island 2 | 0 findings, 0 errors, 0 issues (the 2 deliberate non-finite payloads are listed apart); about 474 checks (a few more or fewer as the auto-played battles go) |
| `sim_save.luau` | play (buildings, a villager moved in, a driftling, an upgrade), leave (saved, lock released, the island back to open water), rejoin to the very same profile; leaving mid-expedition (the loot gathered comes home, no expedition after the rejoin); a save never overwrites another server's live lock; a join waits out another server's lock and then takes over; a corrupt record (bad stores, an unknown tier, junk villagers, an unknown species, pieces off the island) loads into a valid profile keeping only what makes sense; a version 4 save (the game studio) starts a fresh island keeping the founder, settings and start | 0 findings, 0 errors, 0 issues; 218 checks |
| `sim_world.luau` | the sea at start (a boardwalk stretch per plot, the sea's ends, open water with Owner 0 on all six plots); two islands on plots 1 and 2 (Static.Office / Static.Land, the island's name, Tier, Day, Sailing, the players' Founder and Plot attributes, each founder on their path); villagers and driftlings on both drawn by each client (own and the neighbour's, both founders; the Folk and Pals attributes), the signs' labels; a founder walked onto the neighbour's island (the camera pans, Home shows), char.home back and its cooldown; building: place (shells and wood paid; "blocked" on a piece, the hut, the path, off the island; "locked" a bigger island's building), Static.Decor's models named uid:id:x:z:rot:lvl, move turned, upgrade to Lv 2 and 3 (its price; no Lv 4; a home has none), clear away (half back; the only home with villagers stays), the piece limit; Build mode through the HUD (the Food and Decor tabs, a locked card, a ghost on a cyan frame where tapped, Place, red on the hut, Cancel, picking decor up (Clear away, no Upgrade) and a building (Upgrade), Done); malicious plot payloads; a player leaving (their islanders gone from the other client); a newcomer on the freed island; a full sea kicking the seventh player | 0 findings, 0 errors, 0 issues (its deliberate NaN payload is listed apart); 226 checks |
| `sim_clock.luau` | a day every `DaySeconds` (an Fx day each, an Fx tick every second), villagers moving into the beds; ten seconds of making and eating matching `Island.rates` (food, wood, the stall's shells), the view's rates and food following; a panel and Build mode holding nothing; hunger (the food at none, the shops shut, the view saying so) and fed again; moving in (no free bed, not charming enough, then decor raising the charm), the island expanded twice round its buildings; the training yard training a resting villager; a working villager away on an expedition (the island making without them, the Folk attribute marking them away, back at work at home); two islands on their own clocks | 0 findings, 0 errors, 0 issues; 306 checks |
| `sim_exp.luau` | the server's rules (supplies for four, Mossgrove locked, the captain and three set sail, one expedition at a time, a member away can't be dismissed, no fight before a battle, no stepping on or sailing home mid-battle, a treat's food and free nest), treats until a wild one is befriended (in the Index), a flight, the guardian (no treat, no flight); the islet's screen (the HUD's card `ExpContinue`, Fight and Guard but no Treat or Flee against the guardian, the party and the guardian on the stage, a round fought and played back without errors, Back to island leaving the expedition waiting); the guardian beaten (the next islet opens, all the loot home); every islet cleared in turn by a strong party (each guardian's reward in full); Pebble Beach again (half the reward); a defeat (half the loot home, everyone back) | 0 findings, 0 errors, 0 issues; 335 checks |

`boot.luau` is a smoke test with no checks: it boots one player and prints what is there.

Known quirks: `os.clock` is simulated (timing checks are about the game's own clock, not real frame cost); the
engine's GUI hit test ignores `UIScale`; the pixel renderer runs in the sims without a real picture (the sims set no
EditableImages: the classic style, so `PixelRenderer.project` / `screenRay` go through the fake camera; the picture
is checked in the previews instead); `workspace:Raycast` hits only a ground plane at y = 0 unless a scenario sets
`E.raycastParts = true` (then every part, slowly: sim_world turns it on just around a tap that must hit a piece); the
fake engine shares one DataModel between the clients, so a client-only folder such as `Workspace.PixelDynamic` holds
every client's rigs (count them through the modules: `WorldView.rigCount` / `ownRigCount`, `AvatarView.count`).

## The previews: `tools/preview`

Boots the game in the same fake engine (copies with three hooks: part geometry changes, reparenting, property
writes) with the real `PixelRenderer`, lets it cast its rays against the real office (`raycast.luau`: exact Block /
Ball / Cylinder / Wedge / CornerWedge intersection, a BVH), captures what it writes into its `EditableImage`
(`capture.luau`), lays out the real `PlayerGui` (`guiengine.luau`) and writes PNGs at device sizes (`topng.py`).

```sh
PREVIEW_KEEP=1 sh tools/preview/render.sh <scenario> <outdir> "desktop phone" [tier]
```

| Scenario | Frames | What happens |
|---|---|---|
| `island` | `island` | a brand-new island: the castaway's hut, the founder, the HUD with the first tip |
| `village` | `village` | a tier-1 village a dozen days in (nineteen pieces, four villagers at work, three driftlings helping and hopping), the island card |
| `island2`, `island3` | `island2`, `island3` | a Driftwood Lodge island with the village's pieces / a Harbor Hall island with every kind of building (upgraded makers, the lighthouse, the statue, the fountain), villagers and eight driftlings |
| `day` | `day` | a new day's banner (a visitor moving in) |
| `panel=<name>` | `panel_<name>` | the panel `UIKit.openPanel(name)` opened (`folk`, `pals`, `explore` with a villager and a driftling picked, `index`, `looks`) for a village with two islets cleared |
| `exp=<islet>[_<what>]` | `exp_<spec>` | an expedition to islet 1-5 on its 3D stage with a party of four: `battle` (default: the first battle, a round played), `boss` (the guardian), `win` (a won battle's results card), `loot` (a stop's narration); e.g. `exp=4_boss` |
| `sea` | `sea`, `sea_fresh` | the founder walked onto the boardwalk between their island and a neighbour's village (a server-side player), the camera following; then the same pan baked from scratch (`PixelRenderer.rebake`) to compare a scrolled picture with a fresh one |
| `visit` | `visit` | the founder on the neighbour's island while their villagers work |
| `build` | `build_tray`, `build`, `build_red` | Build mode opened from the HUD (the tray's Food tab), a lumber camp picked and its ghost tapped onto a cell where it fits (cyan), then onto the hut (red, Place off) |
| `late` | `late_inset`, `late_turn` | the screen's size settling after the HUD is built, the two ways Roblox does it: the top bar's inset arriving with no ViewportSize event (the roots shrink on their own), then the screen turning with ViewportSize fired before the roots are laid out again (`E.guiViewport`); the log line `late <case>: menu bar at y .. on a WxH screen: ON SCREEN / HIDDEN` says whether the HUD's menu bar is still wholly on screen at the bottom |
| `all` | | `island`, `village`, `island3`, `sea`, `build`, `day` |

Devices: `desktop` 1920x1080 mouse, `phone` 844x390 touch, also `laptop`, `tablet`, `portrait`, `android`, `iphone8`,
`desktop1440`. Tier: `auto` (the game's default, high), `low`, `medium`, `high`, `off`. `REPO=<dir>` renders another
tree, `PREVIEW_JOBS` sets the parallel runs (4), `PREVIEW_FLAGS="--ui --boxes --no-core"` adds the GUI alone, every
GuiObject outlined with its name, or hides the approximate Roblox core UI. `PREVIEW_KEEP=1` keeps each run's log in
`<outdir>/_logs`: the `settled` line (tier, layer size, K, bake rays) and the `camera` line (art px per stud, pan, the
lodge's box on screen) are there. Put renders outside the repository (`tools/preview/work/` and `out*/` are
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
