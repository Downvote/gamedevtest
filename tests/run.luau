-- tests/run.luau: runs every spec (scripts/check.sh builds build/luautest first). The Luau CLI cannot list folders,
-- so every spec is named here.
local TestKit = require("./TestKit")
local SPECS = {
	"Util", "Validate", "Numbers", -- helpers
	"DataIntegrity", "Traits", -- the content tables
	"Island", "Battle", "Expedition", "Breed", "Sites", "Economy", "Plot", "Quest", -- the rules
	"Schema", -- the save
	"Shading", "Raster", "Rim", -- the pixel filter (from Random Bakery)
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
