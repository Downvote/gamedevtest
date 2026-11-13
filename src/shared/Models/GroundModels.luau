--!strict
-- The paths and the water tiles (GAME_DESIGN 4; Data/Buildings): placeholder shapes until each is modelled. Roblox module.
-- Builders(m, f, lvl): f is the footprint's centre on the grass, turned; +Z faces the view before the turn.
local Parts = require(script.Parent.Parts)

local M: { [string]: Parts.Builder } = {}

M.sandtrail = function(m, f)
	Parts.box(m, f, 0, 0.02, 0, 2, 0.04, 2, "sand_dark", "Path")
end
M.gravel = function(m, f)
	Parts.box(m, f, 0, 0.02, 0, 2, 0.04, 2, "sand_dark", "Path")
end
M.shellpath = function(m, f)
	Parts.box(m, f, 0, 0.02, 0, 2, 0.04, 2, "sand_dark", "Path")
end
M.plankwalk = function(m, f)
	Parts.box(m, f, 0, 0.02, 0, 2, 0.04, 2, "sand_dark", "Path")
end
M.flagstone = function(m, f)
	Parts.box(m, f, 0, 0.02, 0, 2, 0.04, 2, "sand_dark", "Path")
end
M.cobble = function(m, f)
	Parts.box(m, f, 0, 0.02, 0, 2, 0.04, 2, "sand_dark", "Path")
end
M.mossstone = function(m, f)
	Parts.box(m, f, 0, 0.02, 0, 2, 0.04, 2, "sand_dark", "Path")
end
M.leafpath = function(m, f)
	Parts.box(m, f, 0, 0.02, 0, 2, 0.04, 2, "sand_dark", "Path")
end
M.meadow = function(m, f)
	Parts.box(m, f, 0, 0.02, 0, 2, 0.04, 2, "sand_dark", "Path")
end
M.raked = function(m, f)
	Parts.box(m, f, 0, 0.02, 0, 2, 0.04, 2, "sand_dark", "Path")
end
M.snowpath = function(m, f)
	Parts.box(m, f, 0, 0.02, 0, 2, 0.04, 2, "sand_dark", "Path")
end
M.sandstone = function(m, f)
	Parts.box(m, f, 0, 0.02, 0, 2, 0.04, 2, "sand_dark", "Path")
end
M.terracotta = function(m, f)
	Parts.box(m, f, 0, 0.02, 0, 2, 0.04, 2, "sand_dark", "Path")
end
M.checker = function(m, f)
	Parts.box(m, f, 0, 0.02, 0, 2, 0.04, 2, "sand_dark", "Path")
end
M.crystalpath = function(m, f)
	Parts.box(m, f, 0, 0.02, 0, 2, 0.04, 2, "sand_dark", "Path")
end
M.basalt = function(m, f)
	Parts.box(m, f, 0, 0.02, 0, 2, 0.04, 2, "sand_dark", "Path")
end
M.goldpath = function(m, f)
	Parts.box(m, f, 0, 0.02, 0, 2, 0.04, 2, "sand_dark", "Path")
end
M.starpath = function(m, f)
	Parts.box(m, f, 0, 0.02, 0, 2, 0.04, 2, "sand_dark", "Path")
end
M.stream = function(m, f)
	Parts.water(m, f, 0, -0.1, 0, 2, 2)
end
M.river = function(m, f)
	Parts.water(m, f, 0, -0.1, 0, 2, 2)
end
M.lilypond = function(m, f)
	Parts.water(m, f, 0, -0.1, 0, 2, 2)
end
M.swamp = function(m, f)
	Parts.water(m, f, 0, -0.1, 0, 2, 2)
end
M.lagoon = function(m, f)
	Parts.water(m, f, 0, -0.1, 0, 2, 2)
end
M.hotspring = function(m, f)
	Parts.water(m, f, 0, -0.1, 0, 2, 2)
end
M.icepond = function(m, f)
	Parts.water(m, f, 0, -0.1, 0, 2, 2)
end

return M
