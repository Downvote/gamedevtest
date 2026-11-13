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
`sim.luau` about 2672, `sim_save.luau` about 911, `sim_clock.luau` about 1228, `sim_world.luau` about 2484,
`sim_tree.luau` about 1722).
Previews: `sh tools/preview/render.sh <scenario> <outdir outside the repo> "desktop phone"` with a scenario of `island
village island2 island3 city gallery tree day dusk night dawn sea visit build buildui expand zoo paths water work late
loading themes`, `panel=<pals|tree|hatch|index|looks>`, `catalog=<group>` (a group of the build catalog: `ground fence
nature theme theme2 fun`, a Build mode tab or ids) or `theme=<beach|garden|frost|zen|volcano|fairy>`. The loading card's
art is generated: `sh tools/preview/loading_art.sh` (after changing a model it shows). The place file is
`DriftlingIsle-<short hash>.rbxl` (binary, the format the user asked for) in the repository root (git-ignored).

The game is our own (the user's request named another studio's game; the user chose an original game in its genre):
never copy another game's names, creatures, islands, story or art. Driftlings, islets and buildings are this game's.

The repository `Downvote/test` (Random Bakery) is the reference this game was built from: read it, never change it.

## Pixel art (always)

The user's standing rule: "for pixel art, always dont use mixels. use pixel art techniques such as anti-aliasing,
avoiding jaggies, and avoiding mixels, and use a 1 pixel outline. respect the pixel art grid." So every sprite, icon,
scene and effect (GAME_DESIGN 2 has the rules): never drawn scaled (a smaller or bigger thing is its own sprite: the
11x11 `mini_` icons, the 7x7 `_t` arrows; a driftling's portrait is 32x32, drawn from its 3D model: after changing a
driftling's model, run `sh tools/preview/portraits.sh`; a build catalog card's picture is 24x24, drawn from the piece's
model: after changing a piece's model, run `sh tools/preview/thumbs.sh`), at whole UI px (tweens snap, particles are
1 px), a 1 px ink outline, anti-aliased steps, shaded ramps lit from the top left. New sprites go in `scripts/gen_art.py`
(run it; `--png <file>` for a contact sheet to look at) and are drawn with `UI/PixelSprites.image` / `anim`. The world
is 3D: the islands, the buildings (the Tree of Life among them), the build catalog's pieces, the tree's eggs and the
driftlings are built from parts (`Models/DecorModels` with the catalog's `Models/GroundModels`, `FenceModels`,
`NatureModels`, `ThemeModels`, `ThemeMoreModels` and `FunModels` on `Models/Parts`, `Models/MicroModels`,
`Models/DriftModels`, the eggs in `Controllers/EggView`), world-aligned on the iso grid and drawn by the pixel filter.
(The expeditions and their 3D stages went on 2026-11-12. On 2026-11-13 the tide took the Tree of Life's place for a few
hours; the tree is back, laying the eggs the driftlings hatch from.)

## Writing (always)

The user's standing rule (2026-11-11): "please rewrite all text and dialogue to be less ai-like. research what are
the telltale signs of ai writing and avoid them. note this from further on as well". Every player-visible string,
tip, line of dialogue and notice, and the docs too, reads like a person wrote it: plain words; no em or en dashes;
none of the stock AI words ("delve", "embark", "unleash", "vibrant", "bustling", "journey", "realm", "tapestry",
"seamless", "elevate"); no "it's not X, it's Y"; no reflexive groups of three; no exclamation on every line; no
hype ("epic adventure awaits!"); no stated morals. Short and specific, the way a game's own characters would say
it. Read new text aloud once before it goes in.

## Language

English only in this version. Every player-visible string still goes through `Locale/Lang.t` (and `Lang.fmt` for
templates), so translations can be added the Random Bakery way later. Latin and Cyrillic text is drawn in the pixel
font: a letter it lacks needs a glyph in `scripts/gen_pixelfont.py`.
