#!/bin/sh
# Every scenario of Driftling Isle's simulator: regenerate the sources once, then run them in parallel and print each
# SIM REPORT head. Baselines (CLAUDE.md): 0 findings, 0 errors, 0 issues everywhere.
#   sim.luau        the main run: a new island (the loading card, the campfire, the Tree of Life with its first lot of
#                   eggs, two cheap commons among them, the HUD's tree card, the tips), building in the tips' order for
#                   wood (a camp, a patch, a hut, an egg hatched by tapping it, a stall; the tray turning to Work's
#                   Wood row, Farms, Huts, Shops), the tree in Build mode (moved, never cleared away), the days
#                   turning, the eggs (the plot's Eggs attribute, the ring round the tree, the price tags and their
#                   rules, the card's best three and the time to the next lot, hatching from the card, a tag and the
#                   panel, the swap picker and its egg gone with a new lot, a new lot every Tree.secs, a tap on the
#                   tree opening its panel), the Driftlings panel (move to a second hut, swap back, work, sell in two
#                   taps), the Index panel, looks, settings, expanding for wood (the extra eggs, the huts' limit, the
#                   cheer naming the island), the build catalog (tabs and icons, chips, Decor's 13 themes, cards
#                   cheapest first and locked after, tooltips, the search box, each tab's count), fences drawn (a
#                   line, a box, one over another, Erase), a river with a bridge and lily pads (refused on grass,
#                   taken up with their tile, the banks in the tiles' model names), decor put down with its effects,
#                   Copy, Replace in its row, the keys R and Esc, the questline (Hatch three eggs, Go on build:wood),
#                   a malicious client (egg.hatch, plot.fence, plot.unfence and plot.unpaint payloads; its deliberate
#                   NaN / infinity payloads are listed apart), a second player drawing both islands' eggs, then
#                   Expand on to Everdrift (tier 20, Island max, land north of Driftling Haven's end, tiers 7 to 20)
#   sim_save.luau   saves: leave and rejoin to the same profile (an egg hatched, the same eggs and ids back, their clock
#                   where it stopped: nothing laid while away), a version 12 save (the tide) with its tree planted and
#                   a lot laid, a version 11 save (the old tree, its levels, food, the pen sold; a new tree, the patch
#                   making room), a version 9 save (the wild places and fights) loading with its huts, another
#                   server's lock, a takeover, a corrupt record, junk eggs cleaned, a version 13 save's old one-piece
#                   fence and hedge gone with their wood back, fences, water and lily pads through leave and rejoin
#                   (bad fences dropped, an odd tile cleared), a tier 20 island's far-north pieces kept, a version 4
#                   save (the game studio) starting an island (its first lot with two cheap commons)
#   sim_clock.luau  the island's clock: the day's pace and its Fx, the tree's eggs (the first lot, the ticks' time to
#                   the next lot, a new lot with its Fx and a whole view, the old eggs gone, the Tree card counting
#                   down, the huts' tree shares bringing lots sooner, a lot every Tree.secs, the extra eggs when the
#                   island grows, the clock stopped while the player is away), wood and shells to the rates, open
#                   menus holding nothing, nothing eating, waiting for a hut and then for work, the Hatchery (a feast
#                   of shells, two eggs: one into a hut, one waiting), two islands, day and night
#   sim_world.luau  the sea and the islands: the sea built at start, two islands with their trees, their driftlings
#                   and both islands' eggs round the trees on every client (the plot's Eggs attribute), walking (the
#                   camera follows, Home), building for wood (place, move, no upgrades, clear away, every refusal, the
#                   huts' limit), Build mode's catalog (tabs and rows, a locked card's tooltip, the Huts tab at the
#                   limit, paths, fences as a line and a box, water, erasing by kind), fences and water on both islands
#                   (their models, the water's neighbour masks, lily pads, fences beside buildings, wading), the piece,
#                   tile and fence limits each on its own, malicious plot payloads (fences too), a leaving player
#                   (their eggs gone with the island), a full sea (a newcomer's tree and first lot), every island's
#                   eggs and price tags, the tree fixed (its panel, moved with its eggs, never cleared away), a tier
#                   20 island (its land far north, pieces of tiers 11 to 20 up there, Island max)
#   sim_tree.luau   the Tree of Life's eggs: a new island's tree (one fixed piece, moved but never cleared away,
#                   bought or replaced, outside the piece limit) and its first lot laid at once (two commons first,
#                   the plot's Eggs attribute, EggView's arc round the tree, the HUD's Tree card, the price tags),
#                   refusals (no hut, gone, malformed, a shell short, full), hatching from the card, a world tag, the
#                   egg itself and the panel (wood, then a farm), the swap picker, new lots on the tree's clock (a
#                   hatched-down lot, every egg left unhatched replaced), the eggs saved over a rejoin, the huts'
#                   shares, expanding (more eggs at once, dearer, better), tapping the tree, a neighbour's eggs
SIM=$(cd "$(dirname "$0")" && pwd)
sh "$SIM/one.sh" --gen "sim.luau:out_main.log" "sim_save.luau:out_save.log" "sim_clock.luau:out_clock.log" "sim_world.luau:out_world.log" "sim_tree.luau:out_tree.log"
