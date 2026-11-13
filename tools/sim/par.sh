#!/bin/sh
# Every scenario of Driftling Isle's simulator: regenerate the sources once, then run them in parallel and print each
# SIM REPORT head. Baselines (CLAUDE.md): 0 findings, 0 errors, 0 issues everywhere.
#   sim.luau        the main run: a new island (the loading card, the campfire, the jetty's first two driftlings, the
#                   HUD's tide card, the tips), building in the tips' order for wood (a camp, a patch, a hut, one taken
#                   off the tide from the card, a stall), the days turning, the tide (one every TideSecs up to TideMax,
#                   the Index, the card, the world's price tags, the tide panel, the swap picker, one taken in walking
#                   the island), the Driftlings panel (move to a second hut, swap back, work, sell in two taps), the
#                   Index panel, looks, settings, expanding for wood, the questline, a malicious client (its deliberate
#                   NaN / infinity payloads are listed apart), a second player
#   sim_save.luau   saves: leave and rejoin to the same profile (the tree's levels, one kept in the pen), a version 9
#                   save (the wild places and fights) loading with its tree and huts, another server's lock, a takeover,
#                   a corrupt record, a version 4 save (the game studio) starting an island
#   sim_clock.luau  the island's clock: the day's pace and its Fx, making and eating to the rates, open menus holding
#                   nothing, hunger, moving in (beds and charm), expanding round the buildings, two islands, day and
#                   night, the Hatchery's egg hatching into the pen
#   sim_world.luau  the sea and the islands: the sea built at start, two islands, their villagers and driftlings on
#                   every client, walking (the camera follows, Home), building (place, move, no upgrades, clear away, every
#                   refusal), Build mode's UI, paths, malicious plot payloads, a leaving player, a full sea, a newcomer's
#                   Tree of Life (moved, never cleared away)
#   sim_tide.luau   the tide: a new island's two commons at the jetty (the view, the plot's Tide attribute, the HUD's
#                   card, the rafts), refusals (no hut, gone, malformed, a shell short), the tips' buildings and one
#                   taken in from the card and one from its world tag, one every TideSecs up to TideMax with the
#                   oldest drifting off (the Index), every hut full (the swap picker), the tide panel, selling in two
#                   taps, a hut cleared away and another built, expanding (prices times TideTier), a neighbour's
#                   client drawing the first island's tide
SIM=$(cd "$(dirname "$0")" && pwd)
sh "$SIM/one.sh" --gen "sim.luau:out_main.log" "sim_save.luau:out_save.log" "sim_clock.luau:out_clock.log" "sim_world.luau:out_world.log" "sim_tide.luau:out_tide.log"
