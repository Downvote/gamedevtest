--!strict
-- The themed decor: frost, autumn, desert, fairy glade, zen garden, volcano (GAME_DESIGN 4; Data/Buildings): placeholder shapes until each is modelled. Roblox module.
-- Builders(m, f, lvl): f is the footprint's centre on the grass, turned; +Z faces the view before the turn.
local Parts = require(script.Parent.Parts)

local M: { [string]: Parts.Builder } = {}

M.snowman = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.sled = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 0.6, "wood", "Body")
end
M.icelantern = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.icesculpture = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.igloo = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 3, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 1.7999999999999998, "wood", "Body")
end
M.leafpile = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.basket = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.pumpkinstack = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.cornstalks = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 0.6, "wood", "Body")
end
M.jackolantern = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.waterjars = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.claypots = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 0.6, "wood", "Body")
end
M.rug = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.stripedtent = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 3, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 1.7999999999999998, "wood", "Body")
end
M.sandarch = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 0.6, "wood", "Body")
end
M.fairylantern = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.mushroomring = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 3, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 1.7999999999999998, "wood", "Body")
end
M.moonstone = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.wishingwell = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.crystalarch = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 0.6, "wood", "Body")
end
M.bambooscreen = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 0.6, "wood", "Body")
end
M.windchime = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.stonelantern = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.zenbasin = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.lanterntower = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.firebasin = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.steamvent = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.obsidian = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.lavapool = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 3, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 1.7999999999999998, "wood", "Body")
end

return M
