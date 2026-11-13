--!strict
-- The fences, the bridges and what floats on the water (GAME_DESIGN 4; Data/Buildings): placeholder shapes until each is modelled. Roblox module.
-- Builders(m, f, lvl): f is the footprint's centre on the grass, turned; +Z faces the view before the turn.
local Parts = require(script.Parent.Parts)

local M: { [string]: Parts.Builder } = {}

M.ropefence = function(m, f)
	Parts.box(m, f, -1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 0, 0.55, 0, 2, 0.25, 0.25, "wood", "Rail")
end
M.picket = function(m, f)
	Parts.box(m, f, -1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 0, 0.55, 0, 2, 0.25, 0.25, "wood", "Rail")
end
M.splitrail = function(m, f)
	Parts.box(m, f, -1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 0, 0.55, 0, 2, 0.25, 0.25, "wood", "Rail")
end
M.bamboofence = function(m, f)
	Parts.box(m, f, -1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 0, 0.55, 0, 2, 0.25, 0.25, "wood", "Rail")
end
M.driftwood = function(m, f)
	Parts.box(m, f, -1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 0, 0.55, 0, 2, 0.25, 0.25, "wood", "Rail")
end
M.wattle = function(m, f)
	Parts.box(m, f, -1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 0, 0.55, 0, 2, 0.25, 0.25, "wood", "Rail")
end
M.hedgerow = function(m, f)
	Parts.box(m, f, -1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 0, 0.55, 0, 2, 0.25, 0.25, "wood", "Rail")
end
M.gardengate = function(m, f)
	Parts.box(m, f, -1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 0, 0.55, 0, 2, 0.25, 0.25, "wood", "Rail")
end
M.stonewall = function(m, f)
	Parts.box(m, f, -1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 0, 0.55, 0, 2, 0.25, 0.25, "wood", "Rail")
end
M.palisade = function(m, f)
	Parts.box(m, f, -1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 0, 0.55, 0, 2, 0.25, 0.25, "wood", "Rail")
end
M.ironrail = function(m, f)
	Parts.box(m, f, -1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 0, 0.55, 0, 2, 0.25, 0.25, "wood", "Rail")
end
M.lanternrope = function(m, f)
	Parts.box(m, f, -1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 0, 0.55, 0, 2, 0.25, 0.25, "wood", "Rail")
end
M.brickwall = function(m, f)
	Parts.box(m, f, -1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 0, 0.55, 0, 2, 0.25, 0.25, "wood", "Rail")
end
M.adobe = function(m, f)
	Parts.box(m, f, -1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 0, 0.55, 0, 2, 0.25, 0.25, "wood", "Rail")
end
M.icewall = function(m, f)
	Parts.box(m, f, -1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 0, 0.55, 0, 2, 0.25, 0.25, "wood", "Rail")
end
M.shellwall = function(m, f)
	Parts.box(m, f, -1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 0, 0.55, 0, 2, 0.25, 0.25, "wood", "Rail")
end
M.crystalfence = function(m, f)
	Parts.box(m, f, -1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 1, 0.4, 0, 0.25, 0.8, 0.25, "wood_dark", "Post")
	Parts.box(m, f, 0, 0.55, 0, 2, 0.25, 0.25, "wood", "Rail")
end
M.plankbridge = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 6, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 3.5999999999999996, "wood", "Body")
end
M.dock = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 4, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 2.4, "wood", "Body")
end
M.ropebridge = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 6, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 3.5999999999999996, "wood", "Body")
end
M.stonebridge = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 6, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 3.5999999999999996, "wood", "Body")
end
M.waterwheel = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 1.2, "wood", "Body")
end
M.moonbridge = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 6, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 3.5999999999999996, "wood", "Body")
end
M.lilypads = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.reeds = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.steppingstones = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.duckfloat = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.rowboat = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 4, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 2.4, "wood", "Body")
end
M.lotus = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.littlefall = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.waterlanterns = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end

return M
