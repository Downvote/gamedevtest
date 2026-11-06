#!/bin/sh
# Every scenario of Byte-Size Studio's simulator: regenerate the sources once, then run them four at a time (more in
# parallel makes the timing checks flaky) and print each SIM REPORT head. Baselines (CLAUDE.md): 0 findings, 0 errors,
# 0 issues everywhere.
#   sim.luau        the main run: a first game end to end, the crew, research, ads, the Loft, settings, tips, a
#                   malicious client (its deliberate NaN / infinity payloads are listed apart, not counted), a 2nd player
#   sim_save.luau   saves: leave and rejoin to the same profile, another server's lock, a takeover, a corrupt record
#   sim_clock.luau  the clock: its pace, pause keys, pay day, new candidates, the awards night
SIM=$(cd "$(dirname "$0")" && pwd)
sh "$SIM/one.sh" --gen "sim.luau:out_main.log" "sim_save.luau:out_save.log" "sim_clock.luau:out_clock.log"
