-- Prints one session (tests/Career.luau) minute by minute: luau tests/career.luau -a <seed> [minutes] [skill]
local Career = require("./Career")
local args = { ... }
local r = Career.play(tonumber(args[1]) or 1, (tonumber(args[2]) or 60) * 60, { skill = tonumber(args[3]), log = print })
print(string.format("first game at %ss, first upgrade at %ss", tostring(r.firstGame), tostring(r.firstUpgrade)))
