--!strict
-- The things to do, seats, lights and the grand pieces (GAME_DESIGN 4; Data/Buildings): placeholder shapes until each is modelled. Roblox module.
-- Builders(m, f, lvl): f is the footprint's centre on the grass, turned; +Z faces the view before the turn.
local Parts = require(script.Parent.Parts)

local M: { [string]: Parts.Builder } = {}

M.goldstatue = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 3, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 1.7999999999999998, "wood", "Body")
end
M.bellspire = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 3, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 1.7999999999999998, "wood", "Body")
end
M.crystalspire = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 3, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 1.7999999999999998, "wood", "Body")
end
M.rainbowarch = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 5, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 3.0, 0.8, 1.2, "wood", "Body")
end
M.logseats = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.parkbench = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 0.6, "wood", "Body")
end
M.stonebench = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 0.6, "wood", "Body")
end
M.porchswing = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 1.2, "wood", "Body")
end
M.gardenlights = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.firepit = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.candles = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.paperlanterns = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 0.6, "wood", "Body")
end
M.stringlights = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 0.6, "wood", "Body")
end
M.sandbox = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.seesaw = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 0.6, "wood", "Body")
end
M.swing = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 1.2, "wood", "Body")
end
M.slide = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 1.2, "wood", "Body")
end
M.trampoline = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 3, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 1.7999999999999998, "wood", "Body")
end
M.carousel = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 3, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 1.7999999999999998, "wood", "Body")
end
M.climbframe = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 3, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 1.7999999999999998, "wood", "Body")
end
M.grill = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.lemonade = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 0.6, "wood", "Body")
end
M.icecream = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 0.6, "wood", "Body")
end
M.telescope = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.tikibar = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 1.2, "wood", "Body")
end
M.drinkfountain = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.smallfountain = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.koipond = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 3, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 1.7999999999999998, "wood", "Body")
end

return M
