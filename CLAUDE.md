# Byte-Size Studio: notes for Claude

## How work is done

Read `docs/WORKFLOW.md` (the routine for every request, the rules, the conventions) and `tools/README.md` (installing
the tools, the check, the simulator, the previews) first. Install the tools with `sh tools/setup.sh` when
`~/.local/rbx-tools/bin` is missing them.

`docs/GAME_DESIGN.md` is the design (quote the request in it when a feature changes), `docs/ARCHITECTURE.md` the
contract (update it with every API, type or data change), `src/shared/Config/Tuning.luau` every number. When a number
changes, run the specs: `tests/specs/Economy.spec.luau` holds the economy to the bounds GAME_DESIGN 10 promises.

This game's simulator baselines (`sh tools/sim/par.sh`, `SIM REPORT`): every scenario 0 findings, 0 errors, 0 issues,
0 warnings (`sim.luau` lists its 2 deliberate malicious non-finite payloads apart; checks today: `sim.luau` 510,
`sim_save.luau` 126, `sim_clock.luau` 79). Previews: `sh tools/preview/render.sh <office|dev|office2|office3|review|
panel=<newgame|staff|research|office|games>> <outdir outside the repo> "desktop phone"`. The place file is
`ByteSizeStudio-<short hash>.rbxlx` in the repository root (git-ignored).

The repository `Downvote/test` (Random Bakery) is the reference this game was built from: read it, never change it.

## Language

English only in this version. Every player-visible string still goes through `Locale/Lang.t` (and `Lang.fmt` for
templates), so translations can be added the Random Bakery way later. Latin and Cyrillic text is drawn in the pixel
font: a letter it lacks needs a glyph in `scripts/gen_pixelfont.py`.
