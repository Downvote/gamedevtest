--!strict
-- The tide at the jetty (GAME_DESIGN 6; docs/ARCHITECTURE.md 10.2): "use the drifting in idea ... there should now be
-- a steady stream of driftlings, with rarities that players can pick up". Every island's driftlings on the tide come
-- from its plot's "Tide" attribute (PlotService: "id.species;..."), so a neighbour's tide floats by too. Each is its
-- 3D model (Models/MicroModels) standing on a raft of driftwood in the water between the island's south shore and the
-- boardwalk, by the jetty, in one of Tuning.TideMax places (the one it came to it keeps). It drifts in along the
-- channel from the open side, bobs and looks about while it waits, and drifts off the same way when the next one
-- takes its place; a rare one or better carries a lantern in its rarity's colour (a light pool at night). Over each of
-- the own island's floats its name in its rarity's colour and its price on a button: tapping it takes it in
-- (TideView.take: tide.take; every hut full, the tide panel's swap picker opens). One just taken hops ashore at the
-- jetty, where its walker appears (Controllers/WorldView).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local Creatures = require(ReplicatedStorage.Shared.Data.Creatures)
local Traits = require(ReplicatedStorage.Shared.Data.Traits)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local MicroModels = require(ReplicatedStorage.Shared.Models.MicroModels)
local Blocks = require(ReplicatedStorage.Shared.Models.Blocks)
local StateClient = require(script.Parent.StateClient)
local Audio = require(script.Parent.Audio)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local PixelSprites = require(script.Parent.Parent.UI.PixelSprites)
local Words = require(script.Parent.Parent.UI.Words)

local TideView = {}

-- one on the tide: its island, its place by the jetty, its models and how it moves
type Drift = {
	key: string,
	id: number,
	plot: number,
	sp: string,
	slot: number,
	thing: MicroModels.Thing,
	raft: Model,
	raftParts: { { p: BasePart, off: CFrame } },
	came: number, -- when it started drifting in
	leaving: number?, -- when it started drifting off
	hop: number?, -- when it was taken (it hops ashore)
	ph: number,
	x: number,
	tag: GuiObject?,
	name: TextLabel?,
}

local drifts: { [string]: Drift } = {}
local taken: { [number]: number } = {} -- own drift ids just taken (they hop ashore instead of drifting off)
local SLOT_X = { -6, 6, -12.5, 12.5 } -- plot-local x of the places by the jetty (far enough apart for their tags)
local EDGE_Z = 29.5 -- plot-local z: the boardwalk's north edge (Street.BOARD.z0), less a little
-- The water by the jetty at plot-local x on an island of `tier`: the middle of the channel between the beach's foam
-- and the boardwalk, so a raft and its rider float clear of both (plot-local z).
local slotZ: { [string]: number } = {}
local function channelZ(tier: number, x: number): number
	local key = tier .. ":" .. x
	local z = slotZ[key]
	if z then
		return z
	end
	local north = EDGE_Z - 2
	local zz = math.floor(EDGE_Z)
	while zz > Street.CENTER.z do
		local l = Street.layer(tier, math.floor(x), zz)
		if l ~= Street.SHALLOW and l ~= Street.SEA_CELL then
			break
		end
		north = zz
		zz -= 1
	end
	local at = math.min(EDGE_Z - 1.75, (north + EDGE_Z) / 2)
	slotZ[key] = at
	return at
end
local FAR = 26 -- studs along the channel it drifts in from (and off to)
local TRAVEL = 3 -- seconds it takes
local HOP = 0.6 -- seconds a taken one takes to hop ashore
local LANTERN: { [number]: string } = { [3] = "blue", [4] = "purple", [5] = "gold" }

local function dyn(): Folder
	local found = workspace:FindFirstChild("PixelDynamic")
	if found and found:IsA("Folder") then
		return found
	end
	local nf = Instance.new("Folder")
	nf.Name = "PixelDynamic"
	nf.Parent = workspace
	return nf
end

local function plotModel(i: number): Model?
	local plots = workspace:FindFirstChild("Plots")
	local m = if plots then plots:FindFirstChild("Plot_" .. i) else nil
	return if m and m:IsA("Model") then m else nil
end

-- A raft of three driftwood planks (and a lantern on a pole for a rare one or better), its parts' offsets from its
-- middle at the waterline.
local function raftOf(rarity: number): (Model, { { p: BasePart, off: CFrame } })
	local m = Blocks.model(nil, "TideRaft")
	local parts: { { p: BasePart, off: CFrame } } = {}
	local function add(size: Vector3, off: CFrame, color: string, neon: boolean?)
		local p = Blocks.part(m, { size = size, cf = off, color = color, collide = false, query = false, neon = neon })
		table.insert(parts, { p = p, off = off })
	end
	add(Vector3.new(2.25, 0.25, 0.5), CFrame.new(0, 0, -0.5), "wood")
	add(Vector3.new(2.5, 0.25, 0.5), CFrame.new(0.125, 0, 0), "wood_dark")
	add(Vector3.new(2, 0.25, 0.5), CFrame.new(-0.125, 0, 0.5), "wood")
	local glow = LANTERN[rarity]
	if glow then
		add(Vector3.new(0.25, 1.5, 0.25), CFrame.new(0.875, 0.75, -0.5), "wood_dark")
		add(Vector3.new(0.5, 0.5, 0.5), CFrame.new(0.875, 1.625, -0.5), glow, true)
	end
	return m, parts
end

local function rarityOf(sp: string): number
	local d = Creatures.byId[sp]
	return if d then d.rarity else 1
end

local function newDrift(key: string, id: number, plot: number, sp: string, slot: number): Drift
	local def = Creatures.byId[sp]
	local t = MicroModels.driftling(if def then def.shape else "blob", if def then def.body else "steel", if def then def.accent else "steel_dark")
	t.model.Parent = dyn()
	PixelRenderer.registerDynamic(t.model)
	local raft, parts = raftOf(rarityOf(sp))
	raft.Parent = dyn()
	PixelRenderer.registerDynamic(raft)
	return { key = key, id = id, plot = plot, sp = sp, slot = slot, thing = t, raft = raft, raftParts = parts, came = os.clock(), ph = (id * 0.618) % 1 * 6.28, x = 0 }
end

local function drop(d: Drift)
	for _, m in { d.thing.model, d.raft } do
		PixelRenderer.unregisterDynamic(m)
		m:Destroy()
	end
	for _, g in { d.tag, d.name } :: { GuiObject? } do
		if g then
			g:Destroy()
		end
	end
	drifts[d.key] = nil
end

------------------------------------------------------------------ taking one in
-- Take the own tide's driftling `id` (tide.take): into a hut, or every hut full, the tide panel's swap picker (swap 0);
-- with `swap`, in that one's place (it's sold).
function TideView.take(id: number, swap: number?)
	local res = StateClient.request("tide.take", { id = id, swap = swap or 0 })
	if res.ok then
		taken[id] = os.clock()
		local data = if type(res.data) == "table" then res.data else {}
		local def = if type(data.sp) == "string" then Creatures.byId[data.sp] else nil
		local rar = Traits.RARITY[if def then def.rarity else 1] or Traits.RARITY[1]
		Audio.play(if def and def.rarity >= 3 then "rare" else "pop")
		local name = if def then def.name else "A driftling"
		local sold = tonumber(data.sold) or 0
		UIKit.notice(if sold > 0 then string.format("%s moved in. The one it replaced sold for %s shells.", name, Numbers.coins(sold)) else string.format("%s moved into a hut.", name), UIKit.color(rar.color), 3)
		if UIKit.currentPanel() == "tide" then
			UIKit.openPanel("tide")
		end
	elseif res.err == "full" then
		UIKit.openPanel("tide", { take = id })
	else
		Audio.play("deny")
		UIKit.notice(Words.errText(res.err), UIKit.color("bad"))
	end
end

------------------------------------------------------------------ keeping up with the islands
local myPlot = 0

-- One island's tide from its attribute (near the view only).
local function syncPlot(i: number, near: boolean)
	local m = plotModel(i)
	local want: { [string]: boolean } = {}
	local raw = if m and near then m:GetAttribute("Tide") else nil
	if type(raw) == "string" then
		local used: { [number]: boolean } = {}
		for _, d in drifts do
			if d.plot == i and d.leaving == nil and d.hop == nil then
				used[d.slot] = true
			end
		end
		for entry in string.gmatch(raw, "[^;]+") do
			local id, sp = string.match(entry, "^(%d+)%.([%w_]+)$")
			local n = tonumber(id)
			if n and sp then
				local key = i .. ":t" .. n
				want[key] = true
				if drifts[key] == nil then
					local slot = 1
					while used[slot] and slot < Tuning.TideMax do
						slot += 1
					end
					used[slot] = true
					drifts[key] = newDrift(key, n, i, sp, slot)
				end
			end
		end
	end
	for key, d in drifts do
		if d.plot == i and not want[key] and d.leaving == nil and d.hop == nil then
			if not near then
				drop(d)
			elseif d.plot == myPlot and taken[d.id] then
				d.hop = os.clock()
			else
				d.leaving = os.clock()
			end
		end
	end
end

-- Where a drift is now (world), and its raft's tilt: drifting in along the channel, bobbing, drifting off, or hopping
-- ashore.
local function placeOf(d: Drift, t: number): (number, number, number)
	local ox, oz = Street.origin(d.plot)
	local sx = SLOT_X[d.slot] or SLOT_X[1]
	local side = if sx < 0 then -1 else 1
	local x = ox + sx
	local k = math.clamp((t - d.came) / TRAVEL, 0, 1)
	x += side * FAR * (1 - k) ^ 2
	if d.leaving then
		local g = math.clamp((t - (d.leaving :: number)) / TRAVEL, 0, 1)
		x += side * FAR * g * g
	end
	local y = Street.WATER_Y + 0.12 + math.sin(t * 1.8 + d.ph) * 0.08
	local m = plotModel(d.plot)
	local tier = if m then (m:GetAttribute("Tier") :: number?) or 1 else 1
	return x, y, oz + channelZ(tier, sx)
end

local function stepDrift(d: Drift, t: number)
	if d.leaving and t - (d.leaving :: number) > TRAVEL then
		drop(d)
		return
	end
	if d.hop and t - (d.hop :: number) > HOP then
		drop(d)
		return
	end
	local x, y, z = placeOf(d, t)
	local tilt = math.sin(t * 1.3 + d.ph) * 0.06
	local yaw = math.rad(20) + math.sin(t * 0.5 + d.ph) * 0.25
	local raftAt = CFrame.new(x, y, z) * CFrame.Angles(tilt, 0, tilt * 0.5)
	for _, rp in d.raftParts do
		rp.p.CFrame = raftAt * rp.off
	end
	local feet = raftAt * CFrame.new(0, 0.125, 0)
	if d.hop then
		-- (a hop up and toward the jetty, then it's gone: its walker comes ashore there)
		local k = math.clamp((t - (d.hop :: number)) / HOP, 0, 1)
		local ax, az = TideView.ashore(d.plot)
		local to = Vector3.new(ax, Street.LAWN_Y, az)
		local from = feet.Position
		local p = from:Lerp(to, k) + Vector3.new(0, math.sin(k * math.pi) * 2.5, 0)
		MicroModels.animate(d.thing, t + d.id, "cheer", 0)
		MicroModels.place(d.thing, CFrame.new(p) * CFrame.Angles(0, yaw, 0))
	else
		MicroModels.animate(d.thing, t + d.id, if d.leaving then "idle" else (if (t + d.ph) % 9 < 1.2 then "cheer" else "idle"), 0)
		MicroModels.place(d.thing, CFrame.new(feet.Position) * CFrame.Angles(0, yaw, 0))
	end
end

-- The own island's tags: each one's name in its rarity's colour and its price on a button (green when the shells are
-- there), over its head; the tips' step 4 bobs an arrow over the cheapest.
local tutArrow: ImageLabel? = nil
local function updateTags(t: number)
	local v = StateClient.view()
	local costOf: { [number]: number } = {}
	if v then
		for _, e in v.tide do
			costOf[e.id] = e.cost
		end
	end
	local cheapest: Drift? = nil
	for _, d in drifts do
		local mine = d.plot == myPlot and d.leaving == nil and d.hop == nil and costOf[d.id] ~= nil
		if not mine then
			for _, g in { d.tag, d.name } :: { GuiObject? } do
				if g then
					g:Destroy()
				end
			end
			d.tag, d.name = nil, nil
			continue
		end
		local cost = costOf[d.id]
		local def = Creatures.byId[d.sp]
		local rar = Traits.RARITY[if def then def.rarity else 1] or Traits.RARITY[1]
		local can = v ~= nil and v.shells >= cost
		local text = Numbers.coins(cost)
		local tag = d.tag
		if tag == nil or tag:GetAttribute("Cost") ~= cost or tag:GetAttribute("Can") ~= can then
			if tag then
				tag:Destroy()
			end
			local w = UIKit.textWidth(text) + 18
			local id = d.id
			local b = UIKit.button(UIKit.canvas("World"), text, UDim2.fromOffset(w, 12), UDim2.fromOffset(0, 0), function()
				TideView.take(id)
			end, { name = "TideTake_" .. d.id, color = if can then UIKit.color("button_ok") else UIKit.color("plate_light") })
			local words = b:FindFirstChild("Words")
			if words and words:IsA("GuiObject") then
				words.Position = UDim2.fromOffset(2, 0)
				words.Size = UDim2.new(1, -16, 1, 0)
			end
			PixelSprites.image(b, "mini_shell", UDim2.new(1, -13, 0, 0), 6).Name = "PriceIcon"
			b:SetAttribute("Cost", cost)
			b:SetAttribute("Can", can)
			d.tag = b
			tag = b
		end
		if d.name == nil then
			local name = if def then def.name else "?"
			d.name = UIKit.text(UIKit.canvas("World"), name, UDim2.fromOffset(UIKit.textWidth(name) + 4, 10), nil, { x = "center", kind = "outline", color = UIKit.color(rar.color), name = "TideName_" .. d.id })
		end
		local x, y, z = placeOf(d, t)
		local px, py, on = PixelRenderer.projectPixel(Vector3.new(x, y + 2.9, z))
		local tg = tag :: GuiObject
		local nm = d.name :: TextLabel
		tg.Visible = on
		nm.Visible = on
		tg.Position = UDim2.fromOffset(px - math.floor(tg.Size.X.Offset / 2), py - 12)
		nm.Position = UDim2.fromOffset(px - math.floor(nm.Size.X.Offset / 2), py - 23)
		if cheapest == nil or cost < (costOf[(cheapest :: Drift).id] or math.huge) then
			cheapest = d
		end
	end
	-- the tips: take one in (step 4)
	local c = cheapest
	if v and v.tut == 4 and c and c.tag and c.tag.Visible then
		local a = tutArrow
		if a == nil then
			a = PixelSprites.image(UIKit.canvas("World"), "arrow_down_t", UDim2.fromOffset(0, 0), 5) :: any
			tutArrow = a
		end
		local bob = if math.floor(t * 3) % 2 == 0 then 0 else 2
		local tg = c.tag :: GuiObject
		local arrow = a :: ImageLabel
		arrow.Visible = true
		arrow.Position = UDim2.fromOffset(tg.Position.X.Offset + math.floor(tg.Size.X.Offset / 2) - 3, tg.Position.Y.Offset - 22 + bob)
	elseif tutArrow then
		tutArrow:Destroy()
		tutArrow = nil
	end
end

------------------------------------------------------------------ lifecycle
local syncAt = 0
-- Every frame from WorldView's Heartbeat: the islands near the view (`near(i)`) synced twice a second, every drift
-- moved, the own island's tags kept over them.
function TideView.step(t: number, near: (number) -> boolean)
	local v = StateClient.view()
	if v then
		myPlot = v.plot
	end
	if t >= syncAt then
		syncAt = t + 0.5
		for i = 1, Street.MAX do
			syncPlot(i, near(i))
		end
		for id, at in taken do
			if t - at > 10 then
				taken[id] = nil
			end
		end
	end
	for _, d in drifts do
		stepDrift(d, t)
	end
	updateTags(t)
end

-- Sims and previews: the drifts drawn now (all islands', or one island's).
function TideView.count(plot: number?): number
	local n = 0
	for _, d in drifts do
		if plot == nil or d.plot == plot then
			n += 1
		end
	end
	return n
end

-- The jetty's island end on island i (world x, z): where one taken in comes ashore.
function TideView.ashore(i: number): (number, number)
	local m = plotModel(i)
	local tier = if m then (m:GetAttribute("Tier") :: number?) or 1 else 1
	local ox, oz = Street.origin(i)
	local j = Street.jetty(tier)
	return ox, oz + j.z0 + 0.5
end

return TideView
