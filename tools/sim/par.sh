#!/bin/sh
# Every scenario of Driftling Isle's simulator: regenerate the sources once, then run them in parallel and print each
# SIM REPORT head. Baselines (CLAUDE.md): 0 findings, 0 errors, 0 issues everywhere.
#   sim.luau        the main run: a new island (the hut, the HUD, the tips), building food, a tent, a nest and a camp,
#                   the days turning (a villager moves in and works), an expedition from the Explore panel played
#                   through the islet's screen (battles, treats, home with the loot), the Villagers and Driftlings
#                   panels, looks, settings, expanding, a malicious client (its deliberate NaN / infinity payloads are
#                   listed apart), a second player
#   sim_save.luau   saves: leave and rejoin to the same profile, leaving mid-expedition (the loot comes home), another
#                   server's lock, a takeover, a corrupt record, a version 4 save (the game studio) starting an island
#   sim_clock.luau  the island's clock: the day's pace and its Fx, making and eating to the rates, open menus holding
#                   nothing, hunger, moving in (beds and charm), expanding round the buildings, the training yard, a
#                   party away, two islands
#   sim_world.luau  the sea and the islands: the sea built at start, two islands, their villagers and driftlings on
#                   every client, walking (the camera follows, Home), building (place, move, upgrade, clear away, every
#                   refusal), Build mode's UI, malicious plot payloads, a leaving player, a full sea
#   sim_exp.luau    expeditions: the server's rules (supplies, the party, busy members, battles, treats, flights, the
#                   guardian), a treat befriending, the islet's screen (closed and reopened, its buttons, a round
#                   played back), every islet cleared in turn, half the reward again, a defeat
SIM=$(cd "$(dirname "$0")" && pwd)
sh "$SIM/one.sh" --gen "sim.luau:out_main.log" "sim_save.luau:out_save.log" "sim_clock.luau:out_clock.log" "sim_world.luau:out_world.log" "sim_exp.luau:out_exp.log"
