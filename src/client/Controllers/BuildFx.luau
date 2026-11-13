--!strict
-- What putting a piece down looks and sounds like in Build mode (GAME_DESIGN 4: "add effects and polish when putting
-- down decor and other amenities"; the bakery's Decorate mode does the same). A piece placed or moved drops in from a
-- little above its spot and hops once as it lands: a stand-in of its model falls (a dynamic model the pixel layer draws
-- every frame) while the server's own model is held back, then the real one takes its place. As it lands: a ring of
-- little dust clouds round its footprint, a burst of what it is made of (Data/Buildings feel: wood chips, stone chips,
-- leaves, water drops, glints of metal, magic motes, sand, snow, confetti for cloth, embers for fire), a twinkle over
-- its top, its sound, and "+N" charm floating up when it adds charm. A stroke of path, water or fence puffs along its
-- tiles or lengths with its sound in a quick run; a piece cleared away goes in a puff. Puffs draws the particles.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Buildings = require(ReplicatedStorage.Shared.Data.Buildings)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local Plot = require(ReplicatedStorage.Shared.Logic.Plot)
local DecorModels = require(ReplicatedStorage.Shared.Models.DecorModels)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Audio = require(script.Parent.Audio)
local Puffs = require(script.Parent.Puffs)

local BuildFx = {}

local DROP_H, DROP_T, BOUNCE_H, BOUNCE_T = 1.6, 0.16, 0.25, 0.14

-- what a feel throws up as it lands (two kinds of particle) and how it sounds
local FEEL: { [string]: { kinds: { string }, sound: string } } = {
	wood = { kinds = { "wood", "dust" }, sound = "place_wood" },
	stone = { kinds = { "chips", "dust" }, sound = "place_stone" },
	plant = { kinds = { "leaf", "dust" }, sound = "place_plant" },
	water = { kinds = { "drop", "drop" }, sound = "place_water" },
	metal = { kinds = { "glint", "dust" }, sound = "place_metal" },
	magic = { kinds = { "magic", "star" }, sound = "place_magic" },
	sand = { kinds = { "dust", "dust" }, sound = "place_sand" },
	snow = { kinds = { "snow", "snow" }, sound = "place_snow" },
	cloth = { kinds = { "confetti", "dust" }, sound = "place_cloth" },
	fire = { kinds = { "ember", "dust" }, sound = "place_fire" },
}

local shows = 0 -- drops under way (sims and previews)

local function feelOf(id: string): { kinds: { string }, sound: string }
	local d = Buildings.byId[id]
	return FEEL[if d then d.feel else "wood"] or FEEL.wood
end

local function dyn(): Instance
	return workspace:FindFirstChild("PixelDynamic") or workspace
end

local function decorOf(plot: number): Instance?
	local plots = workspace:FindFirstChild("Plots")
	local m = if plots then plots:FindFirstChild("Plot_" .. plot) else nil
	return if m then m:FindFirstChild("Decor", true) else nil
end

-- Where a piece stands (world): its footprint's centre on the lawn, turned.
local function anchor(plot: number, id: string, x: number, z: number, rot: number): CFrame
	local ox, oz = Street.origin(plot)
	local w, d = Plot.footprint(id, rot)
	return CFrame.new(ox + x + w / 2, Street.LAWN_Y, oz + z + d / 2) * CFrame.Angles(0, math.rad(rot), 0)
end

-- The landing: dust round the footprint, what it's made of, a twinkle on top, its sound, its charm.
local function land(id: string, at: CFrame, height: number)
	local def = Buildings.byId[id]
	local w, d = if def then def.w else 1, if def then def.d else 1
	local r = math.clamp(math.max(w, d) * 0.55, 0.5, 3.2)
	local base = at.Position + Vector3.new(0, 0.15, 0)
	for k = 0, 5 do
		local a = k * math.pi / 3
		Puffs.burst("poof", base + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), 1)
	end
	local f = feelOf(id)
	Puffs.burst(f.kinds[1], base, 8, r * 0.8)
	Puffs.burst(f.kinds[2], base, 6, r)
	Puffs.burst("twinkle", at.Position + Vector3.new(0, height + 0.3, 0), 2, 0.4)
	Audio.play(f.sound)
	if def and def.charm >= 1 then
		Puffs.float("+" .. math.floor(def.charm), at.Position + Vector3.new(0, height + 0.6, 0), UIKit.color("pink"), "mini_charm")
	end
end

-- A piece put down (placed, or moved there) on island `plot`: its stand-in drops in and hops while the server's model
-- (named "uid:id:x:z:rot:lvl") is held back, then the real one takes its place.
function BuildFx.drop(plot: number, uid: number, id: string, x: number, z: number, rot: number, lvl: number?)
	local at = anchor(plot, id, x, z, rot)
	if not PixelRenderer.isActive() then
		land(id, at, 1)
		return
	end
	local prefix = string.format("%d:%s:%d:%d:%d:", uid, id, x, z, rot)
	local decor = decorOf(plot)
	local held: Instance? = nil
	local function hold()
		if held ~= nil or decor == nil then
			return
		end
		for _, c in (decor :: Instance):GetChildren() do
			if string.sub(c.Name, 1, #prefix) == prefix then
				held = c
				pcall(function()
					c.Parent = nil
				end)
				return
			end
		end
	end
	hold()
	local ok, made = pcall(DecorModels.build, id, at * CFrame.new(0, DROP_H, 0), lvl or 1)
	if not ok or typeof(made) ~= "Instance" then
		land(id, at, 1)
		return
	end
	local m = made :: Model
	m.Name = "DropIn"
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanQuery = false
			p.CanCollide = false
		end
	end
	local height = 1
	pcall(function()
		local _, size = m:GetBoundingBox()
		height = size.Y
	end)
	m.Parent = dyn()
	PixelRenderer.registerDynamic(m)
	local p0 = m:GetPivot()
	shows += 1
	local t0 = os.clock()
	local landed = false
	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - t0
		hold()
		if t > DROP_T + BOUNCE_T or m.Parent == nil then
			PixelRenderer.unregisterDynamic(m)
			m:Destroy()
			local h = held
			if h and decor then
				pcall(function()
					h.Parent = decor
				end)
			end
			if not landed then
				land(id, at, height)
			end
			shows -= 1
			local c = conn
			if c then
				c:Disconnect()
			end
			return
		end
		local dy
		if t < DROP_T then
			local u = t / DROP_T
			dy = DROP_H * (1 - u * u) -- falling faster as it goes
		else
			if not landed then
				landed = true
				land(id, at, height)
			end
			local u = (t - DROP_T) / BOUNCE_T
			dy = BOUNCE_H * math.sin(u * math.pi) -- one small hop
		end
		m:PivotTo(p0 * CFrame.new(0, dy - DROP_H, 0))
	end)
end

-- A stroke of tiles (paths or water: cells, plot-local north-west corners) or fence lengths (edges {x, z, rot}) laid
-- (or taken up: `clearing`): a little cloud and a burst at each (at most 24, spread along it), a twinkle over the last,
-- the sound in a quick run.
function BuildFx.stroke(plot: number, id: string, places: { { number } }, fence: boolean, clearing: boolean)
	local n = #places
	if n == 0 then
		return
	end
	local ox, oz = Street.origin(plot)
	local f = feelOf(id)
	local step = math.max(1, math.ceil(n / 24))
	local last: Vector3? = nil
	local k = 0
	for i = 1, n, step do
		local c = places[i]
		local w: Vector3
		if fence then
			local ex, ez = if c[3] == 90 then c[1] else c[1] + 1, if c[3] == 90 then c[2] + 1 else c[2]
			w = Vector3.new(ox + ex, Street.LAWN_Y + 0.6, oz + ez)
		else
			w = Vector3.new(ox + c[1] + 1, Street.LAWN_Y + 0.15, oz + c[2] + 1)
		end
		Puffs.burst("poof", w, 1)
		Puffs.burst(if clearing then "dust" else f.kinds[1], w, 3, 0.6)
		last = w
		-- (the sound in a quick run: at most six, 0.05 s apart)
		if k < 6 then
			local snd = if clearing then "close" else f.sound
			task.delay(k * 0.05, function()
				Audio.play(snd)
			end)
		end
		k += 1
	end
	if last and not clearing then
		Puffs.burst("twinkle", last + Vector3.new(0, 0.6, 0), 2, 0.3)
	end
end

-- A piece cleared away from island `plot` (where it stood): it goes in a puff.
function BuildFx.cleared(plot: number, id: string, x: number, z: number, rot: number)
	local at = anchor(plot, id, x, z, rot)
	local def = Buildings.byId[id]
	local r = math.clamp(math.max(if def then def.w else 1, if def then def.d else 1) * 0.5, 0.5, 3)
	Puffs.burst("poof", at.Position + Vector3.new(0, 0.6, 0), 6, r)
	Puffs.burst("dust", at.Position + Vector3.new(0, 0.2, 0), 8, r)
	Audio.play("close")
end

-- Sims and previews: drops under way.
function BuildFx.showing(): number
	return shows
end

return BuildFx
