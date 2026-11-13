#!/bin/sh
# Every scenario of Driftling Isle's simulator: regenerate the sources once, then run them in parallel and print each
# SIM REPORT head. Baselines (CLAUDE.md): 0 findings, 0 errors, 0 issues everywhere.
#   sim.luau        the main run: a new island (the loading card, the campfire, the Tree of Life with its first lot of
#                   eggs, two cheap commons among them, the HUD's tree card, the tips), building in the tips' order for
#                   wood (a camp, a patch, a hut, an egg hatched by tapping it, a stall), the tree in Build mode (moved,
#                   never cleared away), the days turning, the eggs (the plot's Eggs attribute, the ring round the tree,
#                   the price tags and their rules, the card's best three and the time to the next lot, hatching from
#                   the card, a tag and the panel, the swap picker and its egg gone with a new lot, a new lot every
#                   Tree.secs, a tap on the tree opening its panel), the Driftlings panel (move to a second hut, swap
#                   back, work, sell in two taps), the Index panel, looks, settings, expanding for wood (the extra eggs,
#                   the huts' limit), the questline (Hatch three eggs), a malicious client (egg.hatch payloads; its
#                   deliberate NaN / infinity payloads are listed apart), a second player drawing both islands' eggs
#   sim_save.luau   saves: leave and rejoin to the same profile (an egg hatched, the same eggs and ids back, their clock
#                   where it stopped: nothing laid while away), a version 12 save (the tide) with its tree planted and
#                   a lot laid, a version 11 save (the old tree, its levels, food, the pen sold; a new tree, the patch
#                   making room), a version 9 save (the wild places and fights) loading with its huts, another
#                   server's lock, a takeover, a corrupt record, junk eggs cleaned, a version 4 save (the game studio)
#                   starting an island (its first lot with two cheap commons)
#   sim_clock.luau  the island's clock: the day's pace and its Fx, the tree's eggs (the first lot, the ticks' time to
#                   the next lot, a new lot with its Fx and a whole view, the old eggs gone, the Tree card counting
#                   down, the huts' tree shares bringing lots sooner, a lot every Tree.secs, the extra eggs when the
#                   island grows, the clock stopped while the player is away), wood and shells to the rates, open
#                   menus holding nothing, nothing eating, waiting for a hut and then for work, the Hatchery (a feast
#                   of shells, two eggs: one into a hut, one waiting), two islands, day and night
#   sim_world.luau  the sea and the islands: the sea built at start, two islands with their trees, their driftlings
#                   and both islands' eggs round the trees on every client (the plot's Eggs attribute), walking (the
#                   camera follows, Home), building for wood (place, move, no upgrades, clear away, every refusal, the
#                   huts' limit), Build mode's UI (the Huts tab at the limit), paths, malicious plot payloads, a leaving
#                   player (their eggs gone with the island), a full sea (a newcomer's tree and first lot), every
#                   island's eggs and price tags, the tree fixed (its panel, moved with its eggs, never cleared away)
#   sim_tide.luau   the tide: a new island's two commons at the jetty (the view, the plot's Tide attribute, the HUD's
#                   card, the rafts), refusals (no hut, gone, malformed, a shell short), the tips' buildings and one
#                   taken in from the card and one from its world tag, one every TideSecs up to TideMax with the
#                   oldest drifting off (the Index), every hut full (the swap picker), the tide panel, selling in two
#                   taps, a hut cleared away and another built, expanding (prices times TideTier), a neighbour's
#                   client drawing the first island's tide
SIM=$(cd "$(dirname "$0")" && pwd)
sh "$SIM/one.sh" --gen "sim.luau:out_main.log" "sim_save.luau:out_save.log" "sim_clock.luau:out_clock.log" "sim_world.luau:out_world.log" "sim_tide.luau:out_tide.log"
