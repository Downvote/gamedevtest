# Byte-Size Studio: notes for Claude

## How work is done

Read `docs/WORKFLOW.md` (the routine for every request, the rules, the conventions) and `tools/README.md` (installing
the tools, the check, the simulator, the previews) first. Install the tools with `sh tools/setup.sh` when
`~/.local/rbx-tools/bin` is missing them.

`docs/GAME_DESIGN.md` is the design (quote the request in it when a feature changes), `docs/ARCHITECTURE.md` the
contract (update it with every API, type or data change), `src/shared/Config/Tuning.luau` every number. When a number
changes, run the specs: `tests/specs/Economy.spec.luau` holds the economy to the bounds GAME_DESIGN 10 promises.

This game's simulator baselines (`sh tools/sim/par.sh`, `SIM REPORT`): every scenario 0 findings, 0 errors, 0 issues,
0 warnings (`sim.luau` lists its 2 deliberate malicious non-finite payloads apart, `sim_world.luau` its 1; checks today:
`sim.luau` 393, `sim_save.luau` 162, `sim_clock.luau` 122, `sim_world.luau` 247, `sim_micro.luau` 284 to 286: a couple of its checks depend on how the auto-played rounds go). Previews:
`sh tools/preview/render.sh <scenario> <outdir outside the repo> "desktop phone"` with a scenario of `office reveal
office2 office3 make launch street visit build plot3 late`, `panel=<ideas|index|upgrades|games|looks>` or
`micro=<idea>[_<modifier>]` (e.g. `micro=space_shrinking`). The place file is `ByteSizeStudio-<short hash>.rbxl` (binary,
the format the user asked for) in the repository root (git-ignored).

The repository `Downvote/test` (Random Bakery) is the reference this game was built from: read it, never change it.

## Pixel art (always)

The user's standing rule: "for pixel art, always dont use mixels. use pixel art techniques such as anti-aliasing,
avoiding jaggies, and avoiding mixels, and use a 1 pixel outline. respect the pixel art grid." So every sprite, icon,
scene and effect (GAME_DESIGN 2 has the rules): never drawn scaled (a smaller or bigger thing is its own sprite: the
11x11 `mini_` icons, the 7x7 `_t` arrows), at whole UI px (tweens snap, particles are 1 px), a 1 px ink outline,
anti-aliased steps, shaded ramps lit from the top left. New sprites go in `scripts/gen_art.py` (run it; `--png <file>`
for a contact sheet to look at) and are drawn with `UI/PixelSprites.image` / `anim`. The minigames are 3D (the user's request: "make the
minigames full screen, have depth and are 3d, using the player's avatar"): stages and things built from parts
(`UI/MicroStage`, `Models/MicroModels`), world-aligned on the iso grid, drawn by the pixel filter like the office,
with the player's founder as the hero against rival founders in party rounds (`UI/MicroArena`, `UI/MicroGames`).

## Language

English only in this version. Every player-visible string still goes through `Locale/Lang.t` (and `Lang.fmt` for
templates), so translations can be added the Random Bakery way later. Latin and Cyrillic text is drawn in the pixel
font: a letter it lacks needs a glyph in `scripts/gen_pixelfont.py`.
