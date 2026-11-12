#!/bin/sh
# Every scenario of Driftling Isle's simulator: regenerate the sources once, then run them in parallel and print each
# SIM REPORT head. Baselines (CLAUDE.md): 0 findings, 0 errors, 0 issues everywhere.
#   sim.luau        the main run: a new island (the loading card, the campfire, the Tree of Life, the HUD, the tips),
#                   building what the tips ask (food, a camp, a stall, a tent, a hut), the days turning (a villager moves
#                   in and works), the tree growing driftlings into its pen and the pen sending the best to the hut, the
#                   tree's card and panel (Speed, selling from the pen), the Driftlings panel (move, swap, help, sell),
#                   the Villagers and Index panels, looks, settings, expanding, the questline, a malicious client (its
#                   deliberate NaN / infinity payloads are listed apart), a second player
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
#   sim_tree.luau   the Tree of Life: growing and waiting with a full pen, the pen sending its best to the huts (a sold
#                   one's place filled, a hut cleared away), Speed and Luck to the top with every refusal, a rare one
#                   announced, expanding (a bigger pen, new kinds), a swap through the hut picker, Equip best (a held
#                   better one in from the Tree panel, then nothing to move), the tree moved, a neighbour's client
#                   drawing the pen
SIM=$(cd "$(dirname "$0")" && pwd)
sh "$SIM/one.sh" --gen "sim.luau:out_main.log" "sim_save.luau:out_save.log" "sim_clock.luau:out_clock.log" "sim_world.luau:out_world.log" "sim_tree.luau:out_tree.log"
