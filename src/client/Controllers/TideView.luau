--!strict
-- The tide past the island (GAME_DESIGN 6; docs/ARCHITECTURE.md 10.2): "use the drifting in idea ... there should now
-- be a steady stream of driftlings, with rarities that players can pick up", then "make them float by just like a
-- conveyer belt instead of drifting towards the island and stopping, with one every second". Every island's tide
-- comes from its plot's "Tide" attribute (PlotService.syncTide: "id.species.at.life", in tenths of a second on the
-- server's time), so every client puts each one at the same place along the way, and a neighbour's tide floats by
-- too. Each is its 3D model (Models/MicroModels) standing on a raft of driftwood, riding the lane between the island's
-- foam and the boardwalk (Street.TIDE) from the lot's west end to its east end: it comes up out of the water at the
-- start, ducks under the jetty on the way and goes down again at the end, where the next island's tide comes up. A
-- rare one or better carries a lantern in its rarity's colour (a light pool at night). Over each of the own island's
-- floats its price on a button (an uncommon one or better its name too, in its rarity's colour; where they crowd, the
-- better one's tag shows): tapping it, or the driftling itself, takes it in (TideView.take: tide.take; every hut full,
-- the tide panel's swap picker opens). One taken hops ashore at the
-- jetty, where its walker appears (Controllers/WorldView); a neighbour's taken one hops onto theirs. Only the ones
-- near the view have models.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

local Types = require(ReplicatedStorage.Shared.Types)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local Creatures = require(ReplicatedStorage.Shared.Data.Creatures)
local Traits = require(ReplicatedStorage.Shared.Data.Traits)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local Tide = require(ReplicatedStorage.Shared.Logic.Tide)
local MicroModels = require(ReplicatedStorage.Shared.Models.MicroModels)
local Blocks = require(ReplicatedStorage.Shared.Models.Blocks)
local StateClient = require(script.Parent.StateClient)
local Audio = require(script.Parent.Audio)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local PixelSprites = require(script.Parent.Parent.UI.PixelSprites)
local Words = require(script.Parent.Parent.UI.Words)

local TideView = {}

-- one on the tide: its island, when it came in and how long it takes to float past, its models while near the view
type Drift = {
	key: string,
	id: number,
	plot: number,
	sp: string,
	rarity: number,
	at: number,
	life: number,
	thing: MicroModels.Thing?,
	raft: Model?,
	raftParts: { { p: BasePart, off: CFrame } },
	ph: number,
	done: boolean, -- gone from its island's tide at the end of the way: it runs on out of sight
	hop: number?, -- when it was taken (it hops ashore)
	hopFrom: Vector3?,
	tag: GuiObject?,
	name: TextLabel?,
	worth: number?, -- how good a worker it would be (Logic/Tide.worth; the own island's, for whose tag shows first)
}

local drifts: { [string]: Drift } = {}
local taken: { [number]: number } = {} -- own drift ids just taken (they hop ashore)
local LANE = Street.TIDE
local NEAR = 100 -- studs from the view's centre an island's tide is followed within
local VIEW = 62 -- studs along the lane from the view's centre one is drawn within
local DEPTH = 4.4 -- studs one sinks to go under (the tallest rider's head under the water)
local UNDER = 2.4 -- plot-local |x| within which it is under the jetty (Street.PATH, and a little)
local DUCK = 1.5 -- studs before the jetty it starts to duck
local ENDS = 0.035 -- the share of the way it takes to come up at the start, and to go down at the end
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

local function ease(u: number): number
	local k = math.clamp(u, 0, 1)
	return k * k * (3 - 2 * k)
end

-- How far under the water one is (studs) at plot-local x, `k` of the way along: under the jetty, and at both ends.
function TideView.depth(x: number, k: number): number
	local d = ease((UNDER + DUCK - math.abs(x)) / DUCK)
	if k < ENDS then
		d = math.max(d, ease(1 - k / ENDS))
	elseif k > 1 - ENDS then
		d = math.max(d, ease((k - (1 - ENDS)) / ENDS))
	end
	return d * DEPTH
end

-- How far along one is now (0 just come in .. 1 gone past), on the server's time.
local function along(d: Drift, now: number): number
	return math.clamp((now - d.at) / math.max(0.1, d.life), 0, 1)
end

-- Plot-local x along the lane, `k` of the way.
local function laneX(k: number): number
	return LANE.x0 + (LANE.x1 - LANE.x0) * k
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
		add(Vector3.new(0.25, 1.5, 0.25), CFrame.new(-0.875, 0.75, -0.5), "wood_dark")
		add(Vector3.new(0.5, 0.5, 0.5), CFrame.new(-0.875, 1.625, -0.5), glow, true)
	end
	return m, parts
end

local function rarityOf(sp: string): number
	local d = Creatures.byId[sp]
	return if d then d.rarity else 1
end

-- Its models (when it comes near the view) and away again.
local function dress(d: Drift)
	if d.thing then
		return
	end
	local def = Creatures.byId[d.sp]
	local t = MicroModels.driftling(if def then def.shape else "blob", if def then def.body else "steel", if def then def.accent else "steel_dark")
	t.model.Parent = dyn()
	PixelRenderer.registerDynamic(t.model)
	local raft, parts = raftOf(d.rarity)
	raft.Parent = dyn()
	PixelRenderer.registerDynamic(raft)
	d.thing, d.raft, d.raftParts = t, raft, parts
end

local function untag(d: Drift)
	for _, g in { d.tag, d.name } :: { GuiObject? } do
		if g then
			g:Destroy()
		end
	end
	d.tag, d.name = nil, nil
end

local function undress(d: Drift)
	local t, r = d.thing, d.raft
	for _, m in { if t then t.model else nil, r } :: { Model? } do
		if m then
			PixelRenderer.unregisterDynamic(m)
			m:Destroy()
		end
	end
	d.thing, d.raft, d.raftParts = nil, nil, {}
	untag(d)
end

local function drop(d: Drift)
	undress(d)
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

-- The own tide's best few for the HUD's card and the tide panel: the best workers first (Logic/Tide.worth), and if
-- none of those can be paid for, the best one that can in the last place.
function TideView.best(v: Types.ClientView, n: number): { Types.Drift }
	local list: { { d: Types.Drift, w: number } } = {}
	for _, d in v.tide do
		local x: Types.Pal = { id = 0, sp = d.sp, home = 0, work = 0, muts = d.muts }
		table.insert(list, { d = d, w = Tide.worth(x) })
	end
	table.sort(list, function(a, b): boolean
		if math.abs(a.w - b.w) > 1e-9 then
			return a.w > b.w
		end
		return a.d.id > b.d.id
	end)
	local out: { Types.Drift } = {}
	local can = false
	for i = 1, math.min(n, #list) do
		table.insert(out, list[i].d)
		can = can or v.shells >= list[i].d.cost
	end
	if not can and #out > 0 then
		for i = n + 1, #list do
			if v.shells >= list[i].d.cost then
				out[#out] = list[i].d
				break
			end
		end
	end
	return out
end

------------------------------------------------------------------ keeping up with the islands
local myPlot = 0

-- One island's tide from its attribute (near the view only).
local function syncPlot(i: number, near: boolean, now: number)
	local m = plotModel(i)
	local want: { [string]: boolean } = {}
	local raw = if m and near then m:GetAttribute("Tide") else nil
	if type(raw) == "string" then
		for entry in string.gmatch(raw, "[^;]+") do
			local id, sp, at, life = string.match(entry, "^(%d+)%.([%w_]+)%.(%d+)%.(%d+)$")
			local n, a, l = tonumber(id), tonumber(at), tonumber(life)
			if n and sp and a and l and l > 0 then
				local key = i .. ":t" .. n
				want[key] = true
				if drifts[key] == nil then
					drifts[key] = { key = key, id = n, plot = i, sp = sp, rarity = rarityOf(sp), at = a / 10, life = l / 10, raftParts = {}, ph = (n * 0.618) % 1 * 6.28, done = false }
				end
			end
		end
	end
	for key, d in drifts do
		if d.plot == i and not want[key] and d.hop == nil and not d.done then
			if not near then
				drop(d)
			elseif (d.plot == myPlot and taken[d.id]) or along(d, now) < 1 - 2 * ENDS then
				-- (gone before the end of the way: taken in by its island's player)
				d.hop = os.clock()
			else
				d.done = true
			end
		end
	end
end

-- Where one is now (world) and how far under: riding the lane, ducking under the jetty, coming up and going down at
-- the ends.
local function placeOf(d: Drift, t: number, now: number): (number, number, number, number)
	local ox, oz = Street.origin(d.plot)
	local k = along(d, now)
	local lx = laneX(k)
	local depth = TideView.depth(lx, k)
	local y = Street.WATER_Y + 0.12 + math.sin(t * 1.8 + d.ph) * 0.08 - depth
	return ox + lx, y, oz + LANE.z, depth
end

local function stepDrift(d: Drift, t: number, now: number, focusX: number)
	if d.hop and t - (d.hop :: number) > HOP then
		drop(d)
		return
	end
	if d.hop == nil and along(d, now) >= 1 then
		drop(d)
		return
	end
	local x, y, z = placeOf(d, t, now)
	if d.hop == nil and math.abs(x - focusX) > VIEW then
		undress(d)
		return
	end
	dress(d)
	local thing = d.thing :: MicroModels.Thing
	local tilt = math.sin(t * 1.3 + d.ph) * 0.06
	-- (it rides facing the way it goes, turned a little toward the view)
	local yaw = math.rad(62) + math.sin(t * 0.5 + d.ph) * 0.2
	if d.hop then
		-- (a hop up and onto the jetty, then it's gone: its walker comes ashore there)
		local k = math.clamp((t - (d.hop :: number)) / HOP, 0, 1)
		local from = d.hopFrom or Vector3.new(x, math.max(y, Street.WATER_Y) + 0.125, z)
		d.hopFrom = from
		local ax, az = TideView.ashore(d.plot)
		local to = Vector3.new(ax, Street.LAWN_Y, az)
		local p = from:Lerp(to, k) + Vector3.new(0, math.sin(k * math.pi) * 2.5, 0)
		MicroModels.animate(thing, t + d.id, "cheer", 0)
		MicroModels.place(thing, CFrame.new(p) * CFrame.Angles(0, yaw, 0))
		local raftAt = CFrame.new(from.X, Street.WATER_Y + 0.12 - k * DEPTH, from.Z)
		for _, rp in d.raftParts do
			rp.p.CFrame = raftAt * rp.off
		end
		return
	end
	local raftAt = CFrame.new(x, y, z) * CFrame.Angles(tilt, 0, tilt * 0.5)
	for _, rp in d.raftParts do
		rp.p.CFrame = raftAt * rp.off
	end
	local feet = raftAt * CFrame.new(0, 0.125, 0)
	MicroModels.animate(thing, t + d.id, if (t + d.ph) % 9 < 1.2 then "cheer" else "idle", 0)
	MicroModels.place(thing, CFrame.new(feet.Position) * CFrame.Angles(0, yaw, 0))
end

-- The own island's tags over the ones near the view and above the water: the price on a button (green when the
-- shells are there), an uncommon one or better its name too. The best workers' tags go first; one that would cover a
-- better one's waits (they all float the same way at the same speed, so who shows stays put). The tips' step 4 bobs
-- an arrow over the cheapest shown.
local tutArrow: ImageLabel? = nil
local function overlaps(a: { number }, list: { { number } }): boolean
	for _, b in list do
		if a[1] < b[3] + 2 and b[1] < a[3] + 2 and a[2] < b[4] + 1 and b[2] < a[4] + 1 then
			return true
		end
	end
	return false
end

local function updateTags(t: number, now: number)
	local v = StateClient.view()
	local entryOf: { [number]: Types.Drift } = {}
	if v then
		for _, e in v.tide do
			entryOf[e.id] = e
		end
	end
	local mine: { Drift } = {}
	for _, d in drifts do
		local e = entryOf[d.id]
		if d.plot == myPlot and d.hop == nil and not d.done and d.thing ~= nil and e ~= nil then
			if d.worth == nil then
				d.worth = Tide.worth({ id = 0, sp = e.sp, home = 0, work = 0, muts = e.muts })
			end
			table.insert(mine, d)
		else
			untag(d)
		end
	end
	table.sort(mine, function(a: Drift, b: Drift): boolean
		local wa, wb = a.worth or 0, b.worth or 0
		if math.abs(wa - wb) > 1e-9 then
			return wa > wb
		end
		return a.id < b.id
	end)
	local shownAt: { { number } } = {}
	local cheapest: Drift? = nil
	for _, d in mine do
		local cost = (entryOf[d.id] :: Types.Drift).cost
		local def = Creatures.byId[d.sp]
		local rar = Traits.RARITY[d.rarity] or Traits.RARITY[1]
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
		if d.name == nil and d.rarity >= 2 then
			local name = if def then def.name else "?"
			d.name = UIKit.text(UIKit.canvas("World"), name, UDim2.fromOffset(UIKit.textWidth(name) + 4, 10), nil, { x = "center", kind = "outline", color = UIKit.color(rar.color), name = "TideName_" .. d.id })
		end
		local x, y, z, depth = placeOf(d, t, now)
		local px, py, on = PixelRenderer.projectPixel(Vector3.new(x, y + depth + 2.9, z))
		local tg = tag :: GuiObject
		local tw = tg.Size.X.Offset
		local rect = { px - math.floor(tw / 2), py - 12, px - math.floor(tw / 2) + tw, py }
		local nm = d.name
		if nm then
			local nw = nm.Size.X.Offset
			rect = { math.min(rect[1], px - math.floor(nw / 2)), py - 23, math.max(rect[3], px - math.floor(nw / 2) + nw), py }
		end
		-- (hidden while it's under: the jetty, the ends; and where it would cover a better one's)
		on = on and depth < 0.6 and not overlaps(rect, shownAt)
		if on then
			table.insert(shownAt, rect)
		end
		tg.Visible = on
		tg.Position = UDim2.fromOffset(px - math.floor(tw / 2), py - 12)
		if nm then
			nm.Visible = on
			nm.Position = UDim2.fromOffset(px - math.floor(nm.Size.X.Offset / 2), py - 23)
		end
		if on and can and (cheapest == nil or cost < ((entryOf[(cheapest :: Drift).id] :: Types.Drift).cost)) then
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
		local top = if c.name then 33 else 22
		local arrow = a :: ImageLabel
		arrow.Visible = true
		arrow.Position = UDim2.fromOffset(tg.Position.X.Offset + math.floor(tg.Size.X.Offset / 2) - 3, tg.Position.Y.Offset - top + bob)
	elseif tutArrow then
		tutArrow:Destroy()
		tutArrow = nil
	end
end

-- A tap on the screen (`pos`: an InputObject's, below the top bar) on one of the own island's driftlings floating by
-- takes it in, tag or not (WorldView's taps ask here first). True when it hit one.
function TideView.tapAt(pos: Vector2): boolean
	local inset = GuiService:GetGuiInset()
	local sx, sy = pos.X + inset.X, pos.Y + inset.Y
	local t, now = os.clock(), StateClient.tideNow()
	local best: Drift? = nil
	local bestD = math.huge
	for _, d in drifts do
		if d.plot ~= myPlot or d.hop ~= nil or d.done or d.thing == nil then
			continue
		end
		local x, y, z, depth = placeOf(d, t, now)
		if depth > 1 then
			continue
		end
		local feet, on = PixelRenderer.project(Vector3.new(x, y + depth, z))
		local head = PixelRenderer.project(Vector3.new(x, y + depth + 2.4, z))
		local h = math.max(8, feet.Y - head.Y)
		local dx, dy = sx - feet.X, sy - (feet.Y + head.Y) / 2
		if on and math.abs(dx) <= h * 0.45 and math.abs(dy) <= h * 0.6 then
			local dist = dx * dx + dy * dy
			if dist < bestD then
				best, bestD = d, dist
			end
		end
	end
	if best then
		task.spawn(TideView.take, best.id)
		return true
	end
	return false
end

------------------------------------------------------------------ lifecycle
local syncAt = 0
-- Every frame from WorldView's Heartbeat (`focusX`: the view's centre, world x): the islands near it synced twice a
-- second, every drift moved (the ones near the view drawn), the own island's tags kept over them.
function TideView.step(t: number, focusX: number)
	local v = StateClient.view()
	if v then
		myPlot = v.plot
	end
	local now = StateClient.tideNow()
	if t >= syncAt then
		syncAt = t + 0.5
		for i = 1, Street.MAX do
			syncPlot(i, math.abs(Street.origin(i) - focusX) <= NEAR, now)
		end
		for id, at in taken do
			if t - at > 10 then
				taken[id] = nil
			end
		end
	end
	for _, d in drifts do
		stepDrift(d, t, now, focusX)
	end
	updateTags(t, now)
end

-- Sims and previews: the ones followed now (all islands', or one island's), and of those the ones drawn.
function TideView.count(plot: number?): (number, number)
	local n, drawn = 0, 0
	for _, d in drifts do
		if plot == nil or d.plot == plot then
			n += 1
			if d.thing then
				drawn += 1
			end
		end
	end
	return n, drawn
end

-- Sims and previews: where one of island `plot`'s is now (world x, y, z; nil: not followed).
function TideView.where(plot: number, id: number): (number?, number?, number?)
	local d = drifts[plot .. ":t" .. id]
	if d == nil then
		return nil, nil, nil
	end
	local x, y, z = placeOf(d, os.clock(), StateClient.tideNow())
	return x, y, z
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
