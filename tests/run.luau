-- tests/run.luau: runs every spec (scripts/check.sh builds build/luautest first). The Luau CLI cannot list folders,
-- so every spec is named here.
local TestKit = require("./TestKit")
local SPECS = {
	"Util", "Validate", "Numbers", -- helpers
	"DataIntegrity", "Traits", -- the content tables
	"Island", "Tree", "Breed", "Economy", "Plot", "Quest", "Store", -- the rules
	"Rewards", -- the rewards for coming back and playing (2026-11-19)
	"Schema", -- the save
	"Shading", "Raster", "Rim", "Fx", "DynTex", "Smooth", "EyeTex", -- the pixel filter (from Random Bakery), its effects, the driftlings' textures, smooth shading, their eyes
	"DriftMotion", -- the driftlings' motion on their skeletons
	"Weather", -- the seasons and the weather, and the eggs they touch
	"PixelFont", -- the pixel font
}
for _, name in SPECS do
	local ok, specOrErr = pcall(require, "./specs/" .. name .. ".spec")
	if not ok then
		TestKit.it(name .. " (load)", function()
			error(specOrErr)
		end)
	else
		TestKit.describe(name, specOrErr)
	end
end
if not TestKit.report() then
	error("tests failed")
end
