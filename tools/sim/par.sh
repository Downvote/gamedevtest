#!/bin/sh
# Every scenario of Byte-Size Studio's simulator: regenerate the sources once, then run them four at a time (more in
# parallel makes the timing checks flaky) and print each SIM REPORT head. Baselines (CLAUDE.md): 0 findings, 0 errors,
# 0 issues everywhere.
#   sim.luau        the main run: a new studio's first ideas, making a game through the board, its three microgames
#                   (MicroUI.debugAuto), the launch, the income, the upgrades, the founder's looks, the panels, settings,
#                   tips, a malicious client (its deliberate NaN / infinity payloads are listed apart), a 2nd player
#   sim_save.luau   saves: leave and rejoin to the same profile, another server's lock, a takeover, a corrupt record,
#                   a version 2 save (the old studio) loading into the idea loop
#   sim_clock.luau  the clocks: the idea pace and the speed upgrade, nothing holding them, the full board's rule, the
#                   income pace, a microgame left open, two studios
#   sim_world.luau  the street and the plot: the street built at start, two studios, teams and founders on every
#                   client, walking (the camera follows, Home), decor (buy with coins, place, move, store, every
#                   refusal), Build mode's UI, malicious plot payloads, a leaving player, an old save, a full street
#   sim_micro.luau  the microgames: all 24 won by the auto player, each engine lost doing nothing, retries, the
#                   modifiers' effects, Play all and Launch, the server's rules, a player leaving mid-game
SIM=$(cd "$(dirname "$0")" && pwd)
sh "$SIM/one.sh" --gen "sim.luau:out_main.log" "sim_save.luau:out_save.log" "sim_clock.luau:out_clock.log" "sim_world.luau:out_world.log" "sim_micro.luau:out_micro.log"
