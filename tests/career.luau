-- Prints one career (tests/Career.luau) year by year: luau tests/career.luau -a <seed> [years]
local Career = require("./Career")
local args = { ... }
Career.play(tonumber(args[1]) or 1, tonumber(args[2]) or 12, print)
