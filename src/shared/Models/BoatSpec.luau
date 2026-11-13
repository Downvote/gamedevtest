--!strict
-- The boat by its level (GAME_DESIGN 8; docs/ARCHITECTURE.md 6): one description of every part, for the sailboats
-- crossing the sea (Models/MicroModels "ship", dynamic; the boat moored at the pier went with the docks on
-- 2026-11-13). Pure data from a level:
--   parts(level) -> { Part }   (boat space: x across, y up from the deck's top, z toward the bow; all world-aligned)
--   dims(level) -> Dims         (length, width, the hull's depth under the deck)
--   deck(level) -> { Vector3 }  (where the party stands: the founder first, then three)
-- Level 1 is a rowing sloop; 2 brings a cabin, a striped sail, a lantern, fenders and a life ring; 3 a bigger hull, a
-- bowsprit and jib, barrels; 4 a foremast, a crow's nest, a figurehead and gold trim; 5 a chimney and a stern
-- lantern; 6 a mizzen mast and blue sails. Flags and pennants are named "Flag..." (they flutter:
-- MicroModels.flutter; marked PixelWind 2 for a static one in the pixel filter's wind).

export type Part = { name: string, shape: string, size: Vector3, cf: CFrame, color: string, neon: boolean?, wind: number? }
export type Dims = { L: number, W: number, H: number }

local BoatSpec = {}

BoatSpec.MAX = 6

local DIMS: { Dims } = {
	{ L = 4.5, W = 2.6, H = 0.9 },
	{ L = 5, W = 3, H = 1 },
	{ L = 6, W = 3.25, H = 1.1 },
	{ L = 7, W = 3.5, H = 1.2 },
	{ L = 8, W = 4, H = 1.25 },
	{ L = 9, W = 4.25, H = 1.35 },
}

function BoatSpec.dims(level: number): Dims
	return DIMS[math.clamp(math.floor(level), 1, #DIMS)]
end

-- The deck's front, where the party stands (behind it the cabin, if any).
local function cabinDepth(level: number): number
	return if level >= 3 then 1.75 elseif level >= 2 then 1.5 else 0
end

local function frontOf(level: number): number
	local d = BoatSpec.dims(level)
	local cd = cabinDepth(level)
	return if cd > 0 then -d.L / 2 + 0.5 + cd + 0.55 else -d.L / 2 + 1
end

function BoatSpec.deck(level: number): { Vector3 }
	local zf = frontOf(level)
	return { Vector3.new(0, 0, zf), Vector3.new(-0.8, 0, zf + 1.1), Vector3.new(0.8, 0, zf + 1.1), Vector3.new(0, 0, zf + 2.2) }
end

-- The deck's top over the sea's surface.
function BoatSpec.deckOverWater(level: number): number
	return BoatSpec.dims(level).H - 0.35
end

function BoatSpec.parts(level: number): { Part }
	local lv = math.clamp(math.floor(level), 1, BoatSpec.MAX)
	local d = BoatSpec.dims(lv)
	local L, W, H = d.L, d.W, d.H
	local out: { Part } = {}
	local function box(name: string, sx: number, sy: number, sz: number, x: number, y: number, z: number, color: string, neon: boolean?, wind: number?)
		table.insert(out, { name = name, shape = "Block", size = Vector3.new(sx, sy, sz), cf = CFrame.new(x, y, z), color = color, neon = neon, wind = wind })
	end
	local function cyl(name: string, dia: number, h: number, x: number, y: number, z: number, color: string)
		table.insert(out, { name = name, shape = "CylY", size = Vector3.new(dia, h, dia), cf = CFrame.new(x, y, z), color = color })
	end
	local trim = if lv >= 4 then "gold" else "berry_red"
	local sailB = if lv >= 6 then "blue" elseif lv >= 2 then "berry_red" else "white"
	-- the hull: planks with seams, a band, the gunwale, a pointed bow, a transom with its rudder
	box("Hull", W, H, L, 0, -H / 2, 0, "wood")
	-- (parts snap to quarter studs: a seam is a dark quarter-stud band between the planks)
	for i, y in { -0.5, -0.875 } do
		if -y < H - 0.2 then
			box("Seam" .. i, W + 0.04, 0.25, L - 0.1, 0, y, 0, "wood_dark")
		end
	end
	box("Band", W + 0.1, 0.25, L + 0.1, 0, -0.125, 0, trim)
	box("Rim", W + 0.25, 0.25, L + 0.25, 0, 0.125, 0, "wood_dark")
	-- the bow: a wedge turned over (Roblox's wedge stands tall at its back, +Z): tall against the hull's front, flush
	-- with the rim on top, its keel sloping up to the stem's point
	local bowLen = 1.25 + lv * 0.1
	table.insert(out, { name = "Bow", shape = "Wedge", size = Vector3.new(W, H + 0.25, bowLen), cf = CFrame.new(0, -H / 2 + 0.125, L / 2 + bowLen / 2) * CFrame.Angles(math.pi, 0, 0), color = "wood" })
	box("Stern", W, 0.25, 0.12, 0, 0.1, -L / 2 - 0.06, trim)
	box("Rudder", 0.15, H, 0.5, 0, -H / 2, -L / 2 - 0.3, "wood_dark")
	box("Tiller", 0.12, 0.12, 0.8, 0, 0.35, -L / 2 + 0.3, "wood_dark")
	-- the deck: planks with seams across
	box("Deck", W - 0.5, 0.25, L - 0.5, 0, -0.125, 0, "sand_dark")
	local n = 0
	local z = -L / 2 + 1
	while z < L / 2 - 0.5 do
		n += 1
		box("Plank" .. n, W - 0.5, 0.25, 0.25, 0, -0.12, z, "wood")
		z += 1
	end
	-- a cabin with a door, windows, a roof (a chimney from 5)
	local cd = cabinDepth(lv)
	if cd > 0 then
		local cw, ch = math.min(W - 0.9, 1.75 + (lv - 2) * 0.15), 1.25 + (lv - 2) * 0.08
		local cz = -L / 2 + 0.5 + cd / 2
		box("Cabin", cw, ch, cd, 0, ch / 2, cz, "cream")
		box("Roof", cw + 0.25, 0.2, cd + 0.25, 0, ch + 0.1, cz, trim)
		box("Door", 0.55, 0.85, 0.06, 0, 0.45, cz + cd / 2 + 0.03, "wood_dark")
		box("Knob", 0.08, 0.08, 0.04, 0.18, 0.45, cz + cd / 2 + 0.07, "gold")
		box("Window", 0.06, 0.45, 0.6, cw / 2 + 0.03, ch * 0.6, cz, "window")
		box("WindowL", 0.06, 0.45, 0.6, -cw / 2 - 0.03, ch * 0.6, cz, "window")
		-- a life ring on the cabin's side: four bars round a hole
		local rx, ry, rz = cw / 2 + 0.06, ch * 0.45, cz - cd / 2 + 0.45
		if cd >= 1.5 then
			box("Ring1", 0.06, 0.15, 0.55, rx, ry + 0.2, rz, "white")
			box("Ring2", 0.06, 0.15, 0.55, rx, ry - 0.2, rz, "white")
			box("Ring3", 0.06, 0.25, 0.15, rx, ry, rz - 0.2, "berry_red")
			box("Ring4", 0.06, 0.25, 0.15, rx, ry, rz + 0.2, "berry_red")
		end
		if lv >= 5 then
			box("Chimney", 0.3, 0.6, 0.3, cw / 2 - 0.4, ch + 0.5, cz - cd / 2 + 0.4, "black")
		end
	end
	-- the masts: a sail of bands beside each (the founder's side kept clear), a flag on the main
	local zf = frontOf(lv)
	local masts: { { z: number, h: number } } = { { z = zf + 1.1, h = 4.2 + (lv - 1) * 0.6 } }
	if lv >= 4 then
		table.insert(masts, { z = zf + 3.1, h = 3.4 + (lv - 4) * 0.5 })
	end
	if lv >= 6 then
		table.insert(masts, { z = -L / 2 + 0.6, h = 3.6 })
	end
	for i, m in masts do
		local mz = math.min(m.z, L / 2 - 0.4)
		box("Mast" .. i, 0.25, m.h, 0.25, 0, m.h / 2, mz, "wood_dark")
		local sw = math.min(2.0 + lv * 0.15, 3)
		local sh = m.h * 0.55
		local y0 = m.h - sh - 0.4
		box("Boom" .. i, 0.15, 0.15, sw + 0.3, 0.12, y0 - 0.1, mz - sw / 2, "wood_dark")
		box("Yard" .. i, 0.12, 0.12, sw + 0.2, 0.12, y0 + sh + 0.08, mz - sw / 2, "wood_dark")
		local bands = if lv >= 2 then 5 else 3
		for k = 1, bands do
			local col = if lv >= 2 and k % 2 == 0 then sailB else "white"
			box("Sail" .. i .. "_" .. k, 0.1, sh / bands, sw, 0.15, y0 + (k - 0.5) * sh / bands, mz - sw / 2, col)
		end
		if i == 1 then
			box("FlagPole", 0.1, 0.5, 0.1, 0, m.h + 0.25, mz, "wood_dark")
			box("Flag", 0.06, 0.45, 0.9, 0, m.h + 0.25, mz - 0.5, trim, nil, 2)
			if lv >= 4 then
				box("Crow", 0.8, 0.35, 0.8, 0, m.h - 0.6, mz, "wood")
				box("CrowRim", 0.9, 0.1, 0.9, 0, m.h - 0.4, mz, "wood_dark")
			end
		else
			box("FlagPennant" .. i, 0.06, 0.25, 0.6, 0, m.h + 0.1, mz - 0.3, "white", nil, 2)
		end
	end
	-- the bowsprit and its jib (from 3), the figurehead (from 4)
	if lv >= 3 then
		box("Bowsprit", 0.2, 0.2, 1.6, 0, 0.3, L / 2 + bowLen - 0.2, "wood_dark")
		table.insert(out, { name = "Jib", shape = "Wedge", size = Vector3.new(0.08, masts[1].h * 0.45, 1.4), cf = CFrame.new(0.1, 0.5 + masts[1].h * 0.225, L / 2 + bowLen - 0.4), color = "white" })
	end
	if lv >= 4 then
		box("Figurehead", 0.35, 0.45, 0.35, 0, -0.1, L / 2 + bowLen - 0.05, "gold")
	end
	-- deck things: oars (1), a crate, barrels (from 3), a lantern and fenders (from 2), a stern lantern (from 5)
	if lv == 1 then
		box("OarL", 0.12, 0.12, 2.4, -W / 2 - 0.1, 0.15, -0.2, "wood")
		box("OarR", 0.12, 0.12, 2.4, W / 2 + 0.1, 0.15, -0.2, "wood")
	end
	box("Crate", 0.7, 0.5, 0.7, W / 2 - 0.6, 0.25, L / 2 - 0.7, "wood")
	box("CrateBand", 0.75, 0.1, 0.75, W / 2 - 0.6, 0.3, L / 2 - 0.7, "wood_dark")
	if lv >= 3 then
		cyl("Barrel1", 0.6, 0.75, -W / 2 + 0.55, 0.375, L / 2 - 0.7, "wood")
		cyl("Barrel2", 0.6, 0.75, -W / 2 + 0.55, 0.375, L / 2 - 1.4, "wood")
	end
	if lv >= 2 then
		box("LanternPost", 0.1, 1, 0.1, W / 2 - 0.35, 0.5, -L / 2 + 0.3, "wood_dark")
		box("Lantern", 0.3, 0.35, 0.3, W / 2 - 0.35, 1.1, -L / 2 + 0.3, "yellow", true)
		box("Fender1", 0.15, 0.5, 0.4, -W / 2 - 0.1, -0.45, -L / 4, "white")
		box("Fender2", 0.15, 0.5, 0.4, -W / 2 - 0.1, -0.45, L / 4, "white")
	end
	if lv >= 5 then
		box("SternLantern", 0.35, 0.4, 0.2, 0, 0.75, -L / 2 - 0.2, "yellow", true)
	end
	return out
end

return BoatSpec
