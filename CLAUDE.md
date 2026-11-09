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
`sim.luau` 307, `sim_save.luau` 128, `sim_clock.luau` 114, `sim_world.luau` 247, `sim_micro.luau` 232). Previews:
`sh tools/preview/render.sh <scenario> <outdir outside the repo> "desktop phone"` with a scenario of `office reveal
office2 office3 make launch street visit build plot3 late`, `panel=<ideas|index|upgrades|games|looks>` or
`micro=<idea>[_<modifier>]` (e.g. `micro=space_haunted`). The place file is `ByteSizeStudio-<short hash>.rbxl` (binary,
the format the user asked for) in the repository root (git-ignored).

The repository `Downvote/test` (Random Bakery) is the reference this game was built from: read it, never change it.

## Pixel art (always)

The user's standing rule: "for pixel art, always dont use mixels. use pixel art techniques such as anti-aliasing,
avoiding jaggies, and avoiding mixels, and use a 1 pixel outline. respect the pixel art grid." So every sprite, icon,
scene and effect (GAME_DESIGN 2 has the rules): never drawn scaled (a smaller or bigger thing is its own sprite; Tiny
uses `_t` sprites), at whole UI px (tweens snap, particles are 1 px), a 1 px ink outline, anti-aliased steps, shaded
ramps lit from the top left. New sprites go in `scripts/gen_art.py` (run it; `--png <file>` for a contact sheet to
look at) and are drawn with `UI/PixelSprites.image` / `anim`.

## Language

English only in this version. Every player-visible string still goes through `Locale/Lang.t` (and `Lang.fmt` for
templates), so translations can be added the Random Bakery way later. Latin and Cyrillic text is drawn in the pixel
font: a letter it lacks needs a glyph in `scripts/gen_pixelfont.py`.
