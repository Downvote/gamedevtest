--!strict
-- The trees, plants and rocks (GAME_DESIGN 4; Data/Buildings): placeholder shapes until each is modelled. Roblox module.
-- Builders(m, f, lvl): f is the footprint's centre on the grass, turned; +Z faces the view before the turn.
local Parts = require(script.Parent.Parts)

local M: { [string]: Parts.Builder } = {}

M.pine = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.oak = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 3, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 1.7999999999999998, "wood", "Body")
end
M.deadtree = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.birch = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.cherry = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 3, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 1.7999999999999998, "wood", "Body")
end
M.maple = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 3, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 1.7999999999999998, "wood", "Body")
end
M.jungletree = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 3, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 1.7999999999999998, "wood", "Body")
end
M.willow = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 4, 0.12, 4, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 2.4, 0.8, 2.4, "wood", "Body")
end
M.bigoak = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 5, 0.12, 5, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 3.0, 0.8, 3.0, "wood", "Body")
end
M.snowpine = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.fern = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.tallgrass = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.berrybush = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.tulips = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 0.6, "wood", "Body")
end
M.mushrooms = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.rosebush = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.sunflowers = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.lavender = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 0.6, "wood", "Body")
end
M.pumpkins = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.cactus = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.monstera = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.bigcactus = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.giantshroom = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.bonsai = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.glowshroom = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.boulder = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.rockpile = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.mossrock = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.sandrock = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.crystals = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.snowrock = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.basaltcols = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.lavarock = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end

return M
