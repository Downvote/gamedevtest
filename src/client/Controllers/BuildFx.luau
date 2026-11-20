--!strict
-- What putting a piece down looks and sounds like in Build mode (GAME_DESIGN 4: "add effects and polish when putting
-- down decor and other amenities"; the bakery's Decorate mode does the same). A piece placed or moved drops in from a
-- little above its spot and hops once as it lands: a stand-in of its model falls (a dynamic model the pixel layer draws
-- every frame) while the server's own model is held back, then the real one takes its place. The stand-in falls
-- straight down in the world (its pivot set upright at its spot and moved by world height alone, never along a turned
-- part's axis), and once it lands it rests where it is until the pixel filter has cast the real one's rect, so the piece
-- is on screen every moment from the tap on (the report of 2026-11-20: "when a building is placed, it seems to shift
-- right instead of shifting down. also, they seem to vanish for awhile before appearing, especially for bigger
-- buildings": the stand-in went at the landing while a big building's rect took several frames to cast, and the
-- server's model could reach the island and be drawn before its drop began). BuildUI calls BuildFx.expect before it
-- asks, so the model is held out of the island the moment it arrives. As it lands: a ring of
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
local StateClient = require(script.Parent.StateClient)

local BuildFx = {}

local DROP_H, DROP_T, BOUNCE_H, BOUNCE_T = 1.6, 0.16, 0.25, 0.14
local SETTLE_MAX = 3 -- seconds a landed stand-in waits at most for the picture to have the real model
local EXPECT_SECS = 5 -- how long a piece about to be put down is watched for (the ask refused: nothing comes)
local LEAD = 0.2 -- studs nearer the stand-in is put down on the frame than it stands (PixelRenderer's "PixelLead")

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
	local st = if m then m:FindFirstChild("Static") else nil
	return if st then st:FindFirstChild("Decor") else nil
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
	-- (its charm on this island now: a decor piece's grows with the island, Buildings.charmOf)
	local v = StateClient.view()
	local charm = if def then Buildings.charmOf(def, if v then v.tier else 1) else 0
	if charm >= 1 then
		Puffs.float("+" .. math.floor(charm), at.Position + Vector3.new(0, height + 0.6, 0), UIKit.color("pink"), "mini_charm")
	end
end

-- The part of a piece's model name ("uid:id:x:z:rot:lvl") that says which piece stands where (a new piece's uid is not
-- known until the server answers; one piece stands on a spot).
local function spotKey(id: string, x: number, z: number, rot: number): string
	return string.format(":%s:%d:%d:%d:", id, x, z, rot)
end

-- Pieces about to be put down: their spot's key -> the island's Decor folder, the model held out of it once it came,
-- and the watch on the folder.
type Wait = { decor: Instance, held: Instance?, conn: RBXScriptConnection? }
local waits: { [string]: Wait } = {}

local function putBack(m: Instance?, decor: Instance?)
	if m and decor and m.Parent == nil then
		pcall(function()
			m.Parent = decor
		end)
	end
end

-- Stop watching for the piece at `key`; what was held goes back into the island.
local function release(key: string)
	local w = waits[key]
	if w == nil then
		return
	end
	waits[key] = nil
	local c = w.conn
	if c then
		c:Disconnect()
	end
	putBack(w.held, w.decor)
end

-- A piece is about to be put down at (x, z, rot) on island `plot` (BuildUI, before it asks): its model is held out of the
-- island the moment the server's copy arrives, so the pixel filter never draws it before its stand-in drops in (the
-- answer can come a frame after the model). Let go after EXPECT_SECS when no drop takes it (the ask refused). Nothing
-- with the pixel filter off. Returns the key BuildFx.release takes.
function BuildFx.expect(plot: number, id: string, x: number, z: number, rot: number): string
	local key = spotKey(id, x, z, rot)
	release(key)
	local decor = decorOf(plot)
	if decor == nil or not PixelRenderer.isActive() then
		return key
	end
	local w: Wait = { decor = decor, held = nil, conn = nil }
	w.conn = decor.ChildAdded:Connect(function(c: Instance)
		if w.held == nil and string.find(c.Name, key, 1, true) then
			w.held = c
			-- (out of the island at once; deferred if the engine refuses a new parent while it is being parented)
			local ok = pcall(function()
				c.Parent = nil
			end)
			if not ok then
				task.defer(function()
					if waits[key] == w then
						pcall(function()
							c.Parent = nil
						end)
					end
				end)
			end
		end
	end)
	waits[key] = w
	task.delay(EXPECT_SECS, function()
		if waits[key] == w then
			release(key)
		end
	end)
	return key
end

-- The ask was refused: stop watching (anything held goes back).
function BuildFx.release(key: string)
	release(key)
end

-- A piece put down (placed, or moved there) on island `plot`: its stand-in drops in and hops while the server's model
-- (named "uid:id:x:z:rot:lvl") is held back, then the real one goes back into the island and the stand-in rests on its
-- spot until the pixel filter has cast it (PixelRenderer.casting), at most SETTLE_MAX.
function BuildFx.drop(plot: number, uid: number, id: string, x: number, z: number, rot: number, lvl: number?)
	local _ = uid
	local at = anchor(plot, id, x, z, rot)
	local key = spotKey(id, x, z, rot)
	local w = waits[key]
	local decor = decorOf(plot)
	local held: Instance? = nil
	if w then
		waits[key] = nil
		local c = w.conn
		if c then
			c:Disconnect()
		end
		held = w.held
		decor = w.decor
	end
	if not PixelRenderer.isActive() then
		putBack(held, decor)
		land(id, at, 1)
		return
	end
	-- the server's model in the island now, if it is there
	local function find(): Instance?
		if decor == nil then
			return nil
		end
		for _, c in (decor :: Instance):GetChildren() do
			if string.find(c.Name, key, 1, true) then
				return c
			end
		end
		return nil
	end
	local back = false -- (the real model is back in the island: no more holding)
	local function hold()
		if held ~= nil or back then
			return
		end
		local c = find()
		if c then
			held = c
			pcall(function()
				c.Parent = nil
			end)
		end
	end
	hold()
	-- the stand-in, a drop's height over its spot; its pivot set there upright, so moving it changes its height alone (a
	-- new model's pivot is not set, and moved along a turned part's up it went sideways)
	local top = at * CFrame.new(0, DROP_H, 0)
	local ok, made = pcall(DecorModels.build, id, top, lvl or 1)
	if not ok or typeof(made) ~= "Instance" then
		putBack(held, decor)
		land(id, at, 1)
		return
	end
	local m = made :: Model
	m.Name = "DropIn"
	m.WorldPivot = top
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
	-- (a little nearer than it stands: once it rests on its spot, the real model's pixels cast so far, at the same depth,
	-- never show through it)
	m:SetAttribute("PixelLead", LEAD)
	m.Parent = dyn()
	PixelRenderer.registerDynamic(m)
	shows += 1
	local t0 = os.clock()
	local landed = false
	local restAt = 0 -- (when it came to rest on its spot)
	local quiet = 0 -- (frames in a row the picture has had the real model)
	local conn: RBXScriptConnection? = nil
	local function finish()
		PixelRenderer.unregisterDynamic(m)
		m:Destroy()
		if not back then
			back = true
			putBack(held, decor)
		end
		if not landed then
			landed = true
			land(id, at, height)
		end
		shows -= 1
		local c = conn
		if c then
			c:Disconnect()
		end
	end
	conn = RunService.Heartbeat:Connect(function()
		if m.Parent == nil then
			finish()
			return
		end
		local t = os.clock() - t0
		if t < DROP_T + BOUNCE_T then
			hold()
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
			-- (straight up and down in the world: its spot moved by height alone)
			m:PivotTo(at + Vector3.new(0, dy, 0))
			return
		end
		if not back then
			-- at rest on its spot: the real model back into the island, the stand-in kept over it while it is cast
			m:PivotTo(at)
			if not landed then
				landed = true
				land(id, at, height)
			end
			back = true
			putBack(held, decor)
			restAt = os.clock()
			return
		end
		-- (the server's model not here yet, or its rect still to be cast: the stand-in stays; two frames in a row with
		-- the picture caught up, so the frame that drops the stand-in has the real one)
		local real = if held and held.Parent ~= nil then held else find()
		if real ~= nil and not PixelRenderer.casting(real) then
			quiet += 1
		else
			quiet = 0
		end
		if quiet >= 2 or os.clock() - restAt > SETTLE_MAX then
			finish()
		end
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
