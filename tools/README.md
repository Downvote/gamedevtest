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

- players: `H.addPlayer({ userId, name })` joins one with a full client and no character (the game sets
  `Players.CharacterAutoLoads` false; the fake engine does not read project properties, so the harness does it);
- modules: `H.smod(name)` (a server service), `H.sharedServer("Logic.Studio")`, `H.cmod(p, "UI.UIKit")` (the client's
  copy), `H.session(p)`, `H.profile(p)`, `H.view(p)` (the client's ClientView), `H.push(p)` (after a test changed the
  server profile: mark it dirty and let the view arrive);
- requests: `H.req(p, action, payload)` (StateClient.request, exactly what the UI does), `H.raw` / `H.rawArgs` (the
  remote directly: the malicious path), `H.signal` / `H.rawSignal`, `H.watchFx(p)` (every Fx message from now on);
- UI: `H.buttons`, `H.click(p, text)` (by a button's visible words; disabled buttons have `AutoButtonColor` false),
  `H.openPanel` / `H.closePanel` / `H.currentPanel` (UIKit's registered panels), `H.dumpButtons`;
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
| `sim_clock.luau` | a week every `Tuning.WeekSec`; the pause keys (held until each is let go, junk ignored, at most four); pay day on a month's first week (and its Fx), new candidates each month; the awards night (a 30 is Critics' Choice, a 36 Game of the Year with its prize times the year, a 20 nothing; the awards card holds the clock until its Nice! button) | 0 findings, 0 errors, 0 issues |

`boot.luau` is a smoke test with no checks: it boots one player and prints what is there.

Known quirks: `os.clock` is simulated (timing checks are about the game's own clock, not real frame cost); the
engine's GUI hit test ignores `UIScale`; the pixel renderer usually runs in the sims without a real picture (it is
checked in the previews instead).

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
| `all` | | `office`, `dev`, `review` |

Devices: `desktop` 1920x1080 mouse, `phone` 844x390 touch, also `laptop`, `tablet`, `portrait`, `android`, `iphone8`,
`desktop1440`. Tier: `auto` (the game's default, high), `low`, `medium`, `high`, `off`. `REPO=<dir>` renders another
tree, `PREVIEW_JOBS` sets the parallel runs (4), `PREVIEW_FLAGS="--ui --boxes --no-core"` adds the GUI alone, every
GuiObject outlined with its name, or hides the approximate Roblox core UI. `PREVIEW_KEEP=1` keeps each run's log in
`<outdir>/_logs`: the `settled` line (tier, layer size, K, bake rays) and the `camera` line (art px per stud, pan, the
office's box on screen) are there. Put renders outside the repository (`tools/preview/work/` and `out*/` are
git-ignored).

A new scenario is a function in `preview.luau`'s `SCEN` table: `join(userId, name)` (or `seedProfile` first, for a
saved studio), drive it with `H.req` / `H.click` / `H.openPanel`, `settle(p)` until the picture is baked and quiet,
`nextWeek(p)` for a week's popups, `capture(p, label)`; add its name to `render.sh`'s list.
`make_gif.py` turns consecutive frames into an animated GIF, `stitch.py` stitches frames, `label_cells.py` labels
contact-sheet cells.

Known gaps (from Random Bakery's preview): timing is not real (`os.clock` is simulated, so the bake's time slicing
runs but the picture looks finished sooner than in Studio); tweens jump to their end values; fonts other than the
game's pixel font are stand-ins (Press Start 2P, Montserrat, DejaVu); the Roblox core UI is approximate (a 58 px top
bar, the touch jump button); Actors run serially.
