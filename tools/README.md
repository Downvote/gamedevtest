# Tools

Command-line tools for building and testing Byte-Size Studio without Roblox Studio. `docs/WORKFLOW.md` says when to
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
- modules: `H.smod(name)` (a server service), `H.sharedServer("Logic.Studio")`, `H.cmod(p, "UI.UIKit")` (the client's
  copy), `H.session(p)`, `H.profile(p)`, `H.view(p)` (the client's ClientView), `H.push(p)` (after a test changed the
  server profile: mark it dirty and let the view arrive);
- requests: `H.req(p, action, payload)` (StateClient.request, exactly what the UI does), `H.raw` / `H.rawArgs` (the
  remote directly: the malicious path), `H.signal` / `H.rawSignal`, `H.watchFx(p)` (every Fx message from now on);
- UI: `H.buttons`, `H.click(p, text)` (by a button's visible words; disabled buttons have `AutoButtonColor` false),
  `H.buttonNamed(p, name)` / `H.clickNamed(p, name)` (by the button's Instance name: `Menu_build`, `Place`, `Store`,
  `BuildDone`, `Home`..., where words repeat), `H.openPanel` / `H.closePanel` / `H.currentPanel` (UIKit's registered
  panels), `H.dumpButtons`;
- invariants: `H.checkProfile(p, label)` (finite coins and income, valid cards on the board and in the Index, the team
  within the room's desks on unique desks, game records with three ideas and a rate, the income at least the listed
  games', a project's results -1 / 0 / 1) and `H.checkMirror(p, label)` (the client's view equals the server's office,
  tips step, income, board, team, project, games and upgrades; its coins within an income tick); `H.expect` /
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
| `sim.luau` | a new studio (an idea team of three, no coins, the garage built under `Workspace.Plots.Plot_1.Static`, a rig per member in `Workspace.PixelDynamic`, the founder); the first ideas on the clock (the `idea` Fx, the board, the Index); a game made through the UI (`MakeGame`, `Pick_1..3`, `Make`, the making card); its three microgames through `PlayAll` played by `MicroUI.debugAuto`; `Launch` (the income the ideas' worth times the wins' boost, the tips, the launch card, `Nice`); the income every second (the `coins` Fx, the view patched); the upgrades through their panel (prices, faster ideas, luck; no coins refused); the looks (`Next_skin`, `SaveLook`, the `Founder` attribute); every panel; settings; the tips banner; a malicious client (unknown and old actions, NaN, infinity, huge strings, extra fields, string payloads, a launch or a microgame with no game, a finish with no microgame, a board index past the board, a bad look or upgrade, unknown decor, a flood against the rate limit: each refused with its ErrCode, nothing changed); a second player on plot 2 | 0 findings, 0 errors, 0 issues (the 2 deliberate non-finite payloads are listed apart) |
| `sim_save.luau` | play (a game launched, a second in the works), leave (saved, lock released, plot freed), rejoin to the very same profile (plus only what was earned since); a save never overwrites another server's live lock; a join waits out another server's lock and then takes over; a corrupt record loads into a valid profile; a version 2 save (the old studio) loads into the idea loop with its room, crew, founder and decor | 0 findings, 0 errors, 0 issues |
| `sim_world.luau` | the street at start (a road stretch per plot, the street's ends, an empty lot with Owner 0 on all six plots); two studios on plots 1 and 2 (Static.Office / Static.Land, StudioName, Tier, Working, Crew matching the idea team, Games and Rate, the players' Founder and Plot attributes, each founder on their footpath); each client drawing its own team, the neighbour's and both founders, the plot signs' labels; a founder walked onto the neighbour's lot (the camera pans, Home shows), char.home back and its cooldown; decor: buy with coins (once, not enough coins), place ("blocked" on a piece, the office, the footpath, off the plot; "locked" not owned; a quarter turn), Static.Decor's models named id:x:z:rot with only the changed ones rebuilt, move, store, the piece limit; Build mode through the HUD (the view free, a ghost on a cyan frame where tapped, Place, red on the office, Cancel, picking a placed piece up, Store, Done); malicious plot payloads; a player leaving; a version 2 save in its Loft loading and its Loft built; a full street kicking the seventh player | 0 findings, 0 errors, 0 issues (its deliberate NaN payload is listed apart) |
| `sim_clock.luau` | an idea every `Tuning.RollBase` s, faster at speed level 10 (and the view says so); ideas keep coming with a panel open and the old pause signal holds nothing; a full board for 30 rolls replayed from the `idea` Fx (only a rarer idea takes the commonest's place, the rest dropped, every one counted in the Index); ten seconds of income at 12.5 a second; a microgame left open dropped after `MicroMaxSec`, its late finish refused; a second studio on its own clock | 0 findings, 0 errors, 0 issues |
| `sim_micro.luau` | each of the 24 ideas' microgames (full screen on its 3D stage, after the stage's bake) through the making card (`Play_1`) won by `MicroUI.debugAuto`, on its own engine at the difficulty its rarity gives; each of the 12 engines lost doing nothing; a lost `Retry_1` keeping a win; each modifier on Action (a harder game for a rarer card, Turbo's speed and shorter fuse, Tiny's small sprites (`ctx.tiny`), Haunted's dark, the glitch layer); `PlayAll` playing the three in turn and `Launch` only then; the server's rules (a new start replaces the one in play, the replaced or a wrong token refused, a win sooner than `MicroMinSec` a loss, a fair win counts, no second finish, junk payloads); a player leaving mid-game | 0 findings, 0 errors, 0 issues |

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
| `office` | `office` | a brand-new studio: the garage and its idea team, a first idea popping out of a head |
| `reveal` | `reveal` | a studio with a board and games, a Mythic idea's reveal dropping in |
| `office2`, `office3` | `office2`, `office3` | a studio from before the redesign in the Loft / on the Studio Floor, with a board and twelve games |
| `make`, `launch` | `make`; `launch`, `launch_cheer` | three ideas picked on the board and Make: the making card; a game with all three played, Launch!, the launch card, then the team cheering |
| `panel=<name>` | `panel_<name>` | the panel `UIKit.openPanel(name)` opened (`ideas` with three picked, `index`, `upgrades`, `games`, `looks`) for a studio with a board and nine games |
| `street` | `street`, `street_fresh` | the founder walked onto the road between their garage and a neighbour's Loft (a server-side player with a game in the works), the camera following; then the same pan baked from scratch (`PixelRenderer.rebake`) to compare a scrolled picture with a fresh one (the settle log line says how many scrolls and re-bakes the walk took) |
| `visit` | `visit`, `visit_fresh` | the founder inside the neighbour's garage while their crew types; the same pan baked fresh |
| `build` | `build`, `build_red` | a studio with nine pieces bought and ten placed through `plot.place`, Build mode opened from the HUD, the oak picked and its ghost tapped onto a lawn cell where it fits (green), then onto the office (red, Place off) |
| `plot3` | `plot3` | a Studio Floor studio with fourteen pieces of decor on its plot (seeded: owned and placed where Logic/Plot says they fit), the home view |
| `micro=<idea>[_<modifier>]` | `micro_<spec>`, `micro_<spec>_card` | a game being made with that idea first: its microgame full screen on its 3D stage, 1.6 s after the curtain lifts (a right move every few frames), then the making card back over the street (e.g. `micro=space_haunted`) |
| `late` | `late_inset`, `late_turn` | the screen's size settling after the HUD is built, the two ways Roblox does it: the top bar's inset arriving with no ViewportSize event (the roots shrink on their own), then the screen turning with ViewportSize fired before the roots are laid out again (`E.guiViewport`); the log line `late <case>: menu bar at y .. on a WxH screen: ON SCREEN / HIDDEN` says whether the HUD's menu bar is still wholly on screen at the bottom (it was HIDDEN before UIKit fired `Resized` on a root's own size change) |
| `all` | | `office`, `reveal`, `make`, `launch`, `street`, `build` |

Devices: `desktop` 1920x1080 mouse, `phone` 844x390 touch, also `laptop`, `tablet`, `portrait`, `android`, `iphone8`,
`desktop1440`. Tier: `auto` (the game's default, high), `low`, `medium`, `high`, `off`. `REPO=<dir>` renders another
tree, `PREVIEW_JOBS` sets the parallel runs (4), `PREVIEW_FLAGS="--ui --boxes --no-core"` adds the GUI alone, every
GuiObject outlined with its name, or hides the approximate Roblox core UI. `PREVIEW_KEEP=1` keeps each run's log in
`<outdir>/_logs`: the `settled` line (tier, layer size, K, bake rays) and the `camera` line (art px per stud, pan, the
office's box on screen) are there. Put renders outside the repository (`tools/preview/work/` and `out*/` are
git-ignored).

A new scenario is a function in `preview.luau`'s `SCEN` table: `join(userId, name, opts)` (opts as `H.addPlayer`'s:
`client = false` for a neighbour), or `seedProfile(userId, tier, staff, working, decor)` first for a saved studio,
drive it with `H.req` / `H.click` / `H.clickNamed` / `H.openPanel` / `walkTo(p, x, z)` (the founder put at a world
point, the view left to follow), `settle(p)` until the picture is baked and quiet (its pan caught up with the
camera's, no re-cast waiting), `capture(p, label)`; add its name to `render.sh`'s
list. To compare a scrolled picture with a fresh bake, capture, call `PixelRenderer.rebake()` in the client, settle
and capture again, then diff the two PNGs (only the animated rigs should differ).
`make_gif.py` turns consecutive frames into an animated GIF, `stitch.py` stitches frames, `label_cells.py` labels
contact-sheet cells.

Known gaps (from Random Bakery's preview): timing is not real (`os.clock` is simulated, so the bake's time slicing
runs but the picture looks finished sooner than in Studio); tweens jump to their end values; fonts other than the
game's pixel font are stand-ins (Press Start 2P, Montserrat, DejaVu); the Roblox core UI is approximate (a 58 px top
bar, the touch jump button); Actors run serially.
