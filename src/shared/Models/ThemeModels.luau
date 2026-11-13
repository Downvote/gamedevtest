--!strict
-- The themed decor: beach, garden, farm, harbour, town, jungle (GAME_DESIGN 4; Data/Buildings): placeholder shapes until each is modelled. Roblox module.
-- Builders(m, f, lvl): f is the footprint's centre on the grass, turned; +Z faces the view before the turn.
local Parts = require(script.Parent.Parts)

local M: { [string]: Parts.Builder } = {}

M.coconuts = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.deckchair = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 1.2, "wood", "Body")
end
M.umbrella = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.surfboards = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 0.6, "wood", "Body")
end
M.lifeguard = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.gnome = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.wheelbarrow = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 0.6, "wood", "Body")
end
M.birdbath = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.beehive = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.trellis = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 0.6, "wood", "Body")
end
M.sundial = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.churns = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.haybale = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 0.6, "wood", "Body")
end
M.scarecrow = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.barrels = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.haystack = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.trough = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 0.6, "wood", "Body")
end
M.cart = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 1.2, "wood", "Body")
end
M.well = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.bollard = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.buoy = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.crates = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.lobsterpots = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.netrack = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 0.6, "wood", "Body")
end
M.anchor = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 0.6, "wood", "Body")
end
M.shipwheel = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.bin = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.signpost = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.planter = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 0.6, "wood", "Body")
end
M.postbox = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.noticeboard = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 0.6, "wood", "Body")
end
M.newsstand = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end
M.tikimask = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.parrotperch = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 1, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 0.6, 0.8, 0.6, "wood", "Body")
end
M.vinearch = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 3, 0.12, 1, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.7999999999999998, 0.8, 0.6, "wood", "Body")
end
M.idol = function(m, f)
	Parts.box(m, f, 0, 0.06, 0, 2, 0.12, 2, "rock", "Footing")
	Parts.box(m, f, 0, 0.5, 0, 1.2, 0.8, 1.2, "wood", "Body")
end

return M
