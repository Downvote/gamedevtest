# Driftling Isle: notes for Claude

## How work is done

Read `docs/WORKFLOW.md` (the routine for every request, the rules, the conventions) and `tools/README.md` (installing
the tools, the check, the simulator, the previews) first. Install the tools with `sh tools/setup.sh` when
`~/.local/rbx-tools/bin` is missing them.

`docs/GAME_DESIGN.md` is the design (quote the request in it when a feature changes), `docs/ARCHITECTURE.md` the
contract (update it with every API, type or data change), `src/shared/Config/Tuning.luau` every number. When a number
changes, run the specs: `tests/specs/Economy.spec.luau` holds the economy to the bounds GAME_DESIGN 10 promises.

This game's simulator baselines (`sh tools/sim/par.sh`, `SIM REPORT`): every scenario 0 findings, 0 errors, 0 issues,
0 warnings (`sim.luau` lists its 2 deliberate malicious non-finite payloads apart, `sim_world.luau` its 1; checks today:
`sim.luau` about 640 (a few more or fewer as its battles go), `sim_save.luau` about 227, `sim_clock.luau` 445,
`sim_world.luau` 248, `sim_exp.luau` about 476 (its Index checks vary with the battles)). Previews: `sh tools/preview/render.sh <scenario> <outdir outside the repo>
"desktop phone"` with a scenario of `island village island2 island3 city day dusk night dawn sea visit build water voyage
late`, `panel=<folk|pals|hatch|explore|index|looks>` or `exp=<kind 1-9>[_battle|_boss|_snack|_skills|_aim|_throw|_tut|_win|_loot|_fight]` (e.g. `exp=4_boss`). The place
file is `DriftlingIsle-<short hash>.rbxl` (binary, the format the user asked for) in the repository root (git-ignored).

The game is our own (the user's request named another studio's game; the user chose an original game in its genre):
never copy another game's names, creatures, islands, story or art. Driftlings, islets and buildings are this game's.

The repository `Downvote/test` (Random Bakery) is the reference this game was built from: read it, never change it.

## Pixel art (always)

The user's standing rule: "for pixel art, always dont use mixels. use pixel art techniques such as anti-aliasing,
avoiding jaggies, and avoiding mixels, and use a 1 pixel outline. respect the pixel art grid." So every sprite, icon,
scene and effect (GAME_DESIGN 2 has the rules): never drawn scaled (a smaller or bigger thing is its own sprite: the
11x11 `mini_` icons, the 7x7 `_t` arrows; a driftling's portrait is 16x16), at whole UI px (tweens snap, particles are 1 px), a 1 px ink outline,
anti-aliased steps, shaded ramps lit from the top left. New sprites go in `scripts/gen_art.py` (run it; `--png <file>`
for a contact sheet to look at) and are drawn with `UI/PixelSprites.image` / `anim`. The islets' expeditions are 3D
and full screen (as the earlier request for the minigames: "make the minigames full screen, have depth and are 3d,
using the player's avatar"): stages and things built from parts (`UI/MicroStage`, `Models/MicroModels`: the
driftlings too), world-aligned on the iso grid, drawn by the pixel filter like the islands, with the player's founder
leading the party (`UI/ExpeditionUI`).

## Language

English only in this version. Every player-visible string still goes through `Locale/Lang.t` (and `Lang.fmt` for
templates), so translations can be added the Random Bakery way later. Latin and Cyrillic text is drawn in the pixel
font: a letter it lacks needs a glyph in `scripts/gen_pixelfont.py`.
