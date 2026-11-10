-- Prints one session (tests/Career.luau) every ten minutes: luau tests/career.luau -a <seed> [minutes]
local Career = require("./Career")
local args = { ... }
local r = Career.play(tonumber(args[1]) or 1, (tonumber(args[2]) or 60) * 60, { log = print })
local _ = r
