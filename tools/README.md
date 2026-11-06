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
- invariants: `H.checkProfile(p, label)` (finite numbers, staff within the office's desks on unique desks, energy
  0..100, skills in range, reviews 1..10 summing to the total, the project's phase and weeks agreeing) and
  `H.checkMirror(p, label)` (the client's view equals the server's money, fans, rp, week, office, tips step, crew size,
  project and releases); `H.expect` / `H.finding`, `H.diff` (a deep compare).

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
| `sim.luau` | a new studio (2 developers, $40K, week 0, the garage built under `Workspace.Plots.Plot_1.Static`, a rig per developer in `Workspace.PixelDynamic`); the first game end to end through the client API (start, busy, not built, the build weeks and their Fx, polish, release with four reviews, the match learned, sales and fans week after week); the crew (hire, full office, let go, train, the party and its monthly cooldown); research and ads; the move to the Loft (refused for fans, then the office rebuilt for tier 2 and the client's camera on it); settings; the tips banner; a malicious client (unknown actions, wrong types, NaN, infinity, huge strings, extra fields, a release with no project, a locked genre, a platform not out yet, a full office, no money, a flood against the rate limit: each refused with its ErrCode, nothing changed); a second player on plot 2 | 0 findings, 0 errors, 0 issues (the 2 deliberate non-finite payloads are listed apart) |
| `sim_save.luau` | play, leave (saved, lock released, plot freed), rejoin to the very same profile; a save never overwrites another server's live lock; a join waits out another server's lock and then takes over; a corrupt record loads into a valid profile | 0 findings, 0 errors, 0 issues |
| `sim_world.luau` | the street at start (a road stretch per plot, the street's ends, an empty lot with Owner 0 on all six plots); two studios on plots 1 and 2 (Static.Office / Static.Land, StudioName, Tier, Working, Crew matching the staff, the players' Founder and Plot attributes, each founder on their footpath); each client drawing its own crew, the neighbour's (from the attributes) and both founders, the plot signs' labels; a founder walked onto the neighbour's lot (the camera pans, the founder on screen, Home shows), char.home back to the footpath and its cooldown, the view gliding home; decor: buy (money and fans by Data/Decor, once, a Loft piece locked, no money), place ("blocked" on a piece, the office, the footpath, off the plot; "locked" not owned; a quarter turn), Static.Decor's models named id:x:z:rot with only the changed ones rebuilt, move, store, the piece limit ("full"); Build mode through the HUD (Menu_build, the clock held, the view free, a tap on a lawn cell found with PixelRenderer.project puts a ghost there on a cyan frame, Place places it where tapped, a tap on the office turns it red and Place off, Cancel, tapping a placed piece picks it up, Store, Done); the move to the Loft putting the piece by the garage's east side back in the box and rebuilding Static.Office / Land; malicious plot payloads (fractions, out of range, 45° turns, NaN, index 0 / 999 / a piece not there, unknown ids, extra fields, a home with a payload, string coords: refused, nothing changed); a player leaving (an empty lot again, the neighbour's client drops their crew and founder); a version 1 save (no founder, no plot) loading; a full street kicking the seventh player | 0 findings, 0 errors, 0 issues (its deliberate NaN payload is listed apart) |
| `sim_clock.luau` | a week every `Tuning.WeekSec`; the pause keys (held until each is let go, junk ignored, at most four); pay day on a month's first week (and its Fx), new candidates each month; the awards night (a 30 is Critics' Choice, a 36 Game of the Year with its prize times the year, a 20 nothing; the awards card holds the clock until its Nice! button) | 0 findings, 0 errors, 0 issues |
| `sim_mini.luau` | the minigames: a small game earning its first push at its first milestone (the week's `push` event, the HUD's `Push` button), the picker (`Mini_<kind>`, its clock hold, Later), each of the four score games through the UI (the server starts it, spends the push and holds the clock; `MinigameUI.debugAuto` plays it to its results card; no week passes; its points land on its score and the card's reward line says so; Nice! lets the clock go); the server's refusals (no push, Bug Squash while building, an unknown game, two at once, a wrong token, a finish too soon counting 0, a second finish, a game left open dropped after `MiniMaxSec` and the clock running again, a client signal unable to lift the "mini" hold, a fair finish keeping its score); junk payloads; Bug Squash from the HUD while polishing (its cooldown, bugs squashed, the button disabled, the server refusing); a second player leaving mid-game | 0 findings, 0 errors, 0 issues |

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
| `office` | `office` | a brand-new studio: the garage and its two developers, once the pixel image is baked |
| `dev` | `dev` | a small game in the works, three weeks in: the crew typing, the week's popups over their heads |
| `office2`, `office3` | `office2`, `office3` | a saved studio in the Loft (5 developers) / on the Studio Floor (8), a game in the works, a week's popups |
| `review` | `review` | a finished build released (the HUD's Release button when there is one, else the request and `UI.ReviewUI.show` when that module exists), 3 s later |
| `panel=<name>` | `panel_<name>` | the panel `UIKit.openPanel(name)` opened (`newgame`, `staff`, `research`, `office`, `games`), with a game in the works for all but `newgame` |
| `street` | `street`, `street_fresh` | the founder walked onto the road between their garage and a neighbour's Loft (a server-side player with a game in the works), the camera following; then the same pan baked from scratch (`PixelRenderer.rebake`) to compare a scrolled picture with a fresh one (the settle log line says how many scrolls and re-bakes the walk took) |
| `visit` | `visit`, `visit_fresh` | the founder inside the neighbour's garage while their crew types; the same pan baked fresh |
| `build` | `build`, `build_red` | a studio with nine pieces bought and ten placed through `plot.place`, Build mode opened from the HUD, the oak picked and its ghost tapped onto a lawn cell where it fits (green), then onto the office (red, Place off) |
| `plot3` | `plot3` | a Studio Floor studio with fourteen pieces of decor on its plot (seeded: owned and placed where Logic/Plot says they fit), the home view |
| `mini=<kind>` | `mini_picker` (code only), `mini_<kind>`, `mini_<kind>_result`, `mini_cheer` (code only) | a game in the works with two pushes banked (polishing with 9 bugs for `bugs`): the HUD's Push! (or Squash) clicked, the picker, the game a few seconds in played by `MinigameUI.debugAuto`, its results card, and the crew cheering once it is closed (kinds: `code ideas pixels beats bugs`) |
| `late` | `late_inset`, `late_turn` | the screen's size settling after the HUD is built, the two ways Roblox does it: the top bar's inset arriving with no ViewportSize event (the roots shrink on their own), then the screen turning with ViewportSize fired before the roots are laid out again (`E.guiViewport`); the log line `late <case>: menu bar at y .. on a WxH screen: ON SCREEN / HIDDEN` says whether the HUD's menu bar is still wholly on screen at the bottom (it was HIDDEN before UIKit fired `Resized` on a root's own size change) |
| `all` | | `office`, `dev`, `review`, `street`, `build` |

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
camera's, no re-cast waiting), `nextWeek(p)` for a week's popups, `capture(p, label)`; add its name to `render.sh`'s
list. To compare a scrolled picture with a fresh bake, capture, call `PixelRenderer.rebake()` in the client, settle
and capture again, then diff the two PNGs (only the animated rigs should differ).
`make_gif.py` turns consecutive frames into an animated GIF, `stitch.py` stitches frames, `label_cells.py` labels
contact-sheet cells.

Known gaps (from Random Bakery's preview): timing is not real (`os.clock` is simulated, so the bake's time slicing
runs but the picture looks finished sooner than in Studio); tweens jump to their end values; fonts other than the
game's pixel font are stand-ins (Press Start 2P, Montserrat, DejaVu); the Roblox core UI is approximate (a 58 px top
bar, the touch jump button); Actors run serially.
