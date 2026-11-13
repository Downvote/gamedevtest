--!strict
-- The Tree of Life's eggs (GAME_DESIGN 6; docs/ARCHITECTURE.md 10.2): "bring back the tree of life ... it now spawns
-- eggs around it that the player can choose to hatch for some shells". Every island's eggs come from its plot's "Eggs"
-- attribute (PlotService.sync: "id.rarity;..."), so a neighbour's tree has its eggs too. Each egg is a model of parts
-- (a speckled shell on a little bed of straw: white with spots of its rarity's colour, a legendary one gold; a rare one
-- or better has glowing spots, a light at night), lying on the tree's lawn on a ring round its stones
-- (Models/DecorModels.EGG_RING), spaced evenly along the side the view looks at. A new lot rises out of the lawn one
-- egg after another; the old ones left sink back into it. Now and then an egg rocks a little. Over each of the own
-- island's floats its price on a button (its spots show its rarity; where they crowd, the rarer one's tag shows): tapping it, or the egg itself, hatches it (EggView.hatch: egg.hatch; every hut full, the tree
-- panel's swap picker opens). A hatched egg shakes, cracks, its top flies off and what hatched stands there a moment
-- before its walker takes over (Controllers/WorldView: it walks off to work from the egg's place).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local Creatures = require(ReplicatedStorage.Shared.Data.Creatures)
local Traits = require(ReplicatedStorage.Shared.Data.Traits)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local Plot = require(ReplicatedStorage.Shared.Logic.Plot)
local Blocks = require(ReplicatedStorage.Shared.Models.Blocks)
local DecorModels = require(ReplicatedStorage.Shared.Models.DecorModels)
local StateClient = require(script.Parent.StateClient)
local Audio = require(script.Parent.Audio)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local PixelSprites = require(script.Parent.Parent.UI.PixelSprites)
local Words = require(script.Parent.Parent.UI.Words)

local EggView = {}

-- one egg under a tree: its island, its place on the ring, its model and how it moves
type Egg = {
	key: string,
	id: number,
	plot: number,
	r: number,
	slot: number,
	n: number,
	model: Model?,
	parts: { { p: BasePart, off: CFrame } },
	top: { BasePart }, -- the shell's upper half (it flies off when it hatches)
	ph: number,
	born: number, -- when it rose out of the lawn
	sink: number?, -- when it started sinking back (a new lot replaced it)
	crack: number?, -- when it started hatching
	tag: GuiObject?,
	name: TextLabel?,
}

local eggs: { [string]: Egg } = {}
local hatching: { [number]: number } = {} -- own egg ids just hatched (they crack instead of sinking)
local lastHatch: { [number]: Vector3 } = {} -- each island's egg that hatched last: where its driftling stands
local myPlot = 0
local NEAR = 100 -- studs from the view's centre an island's eggs are drawn within
local RISE = 0.6 -- seconds an egg takes to rise out of the lawn (one after another, STAGGER apart)
local STAGGER = 0.12
local SINK = 0.5 -- seconds an old one takes to sink back
local CRACK = 0.9 -- seconds a hatching one takes: a shake, the top off, the bottom gone
local DEEP = 1.4 -- studs under the lawn an egg starts (and ends) at
local SIZE: { [number]: number } = { 1.25, 1.3, 1.38, 1.48, 1.62 } -- rarer eggs are a little bigger
local SPOTS: { [number]: string } = { "sand_dark", "green", "blue", "purple", "orange" }

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

-- The Tree of Life on island i (its decor model's name: "uid:tree:x:z:rot:lvl"): its middle on the lawn (world) and
-- its turn (radians). Nil without one.
local function treeAt(i: number): (Vector3?, number)
	local m = plotModel(i)
	local decor = if m then m:FindFirstChild("Decor", true) else nil
	if decor == nil then
		return nil, 0
	end
	local ox, oz = Street.origin(i)
	for _, c in decor:GetChildren() do
		local x, z, rot = string.match(c.Name, "^%d+:tree:(%-?%d+):(%-?%d+):(%d+)")
		local xx, zz, r = tonumber(x), tonumber(z), tonumber(rot)
		if xx and zz and r then
			local w, d = Plot.footprint("tree", r)
			return Vector3.new(ox + xx + w / 2, Street.LAWN_Y, oz + zz + d / 2), math.rad(r)
		end
	end
	return nil, 0
end

-- Where slot k of n lies under island i's tree (world, on the lawn): on an arc round the side of the tree the view
-- looks at (the south and east, whichever way the tree is turned), so no egg hides behind its trunk.
local ARC0, ARC1 = math.rad(-62), math.rad(152) -- (0: south, toward the view's bottom left; 90: east)
local function spotOf(i: number, k: number, n: number): Vector3?
	local c = treeAt(i)
	if c == nil then
		return nil
	end
	local a = ARC0 + (ARC1 - ARC0) * (if n <= 1 then 0.5 else (k - 1) / (n - 1))
	return c + Vector3.new(math.sin(a) * DecorModels.EGG_RING, 0, math.cos(a) * DecorModels.EGG_RING)
end

-- An egg of rarity r: a shell of stacked slices (round from the side), spots of its rarity's colour (glowing on a rare
-- one or better), a bed of straw. Its parts' offsets from its foot.
local function eggOf(r: number): (Model, { { p: BasePart, off: CFrame } }, { BasePart })
	local m = Blocks.model(nil, "TreeEgg")
	local parts: { { p: BasePart, off: CFrame } } = {}
	local top: { BasePart } = {}
	local s = SIZE[r] or 1
	local body = if r >= 5 then "gold" else "white"
	local spot = SPOTS[r] or "sand_dark"
	local glow = r >= 3
	local function add(size: Vector3, off: CFrame, color: string, neon: boolean?, upper: boolean?)
		local p = Blocks.part(m, { size = size, cf = off, color = color, collide = false, query = false, neon = neon, name = if upper then "Top" else "Shell" })
		table.insert(parts, { p = p, off = off })
		if upper then
			table.insert(top, p)
		end
	end
	-- the bed of straw
	add(Vector3.new(1.1 * s, 0.08, 0.55 * s), CFrame.new(0, 0.04, -0.25 * s), "sand")
	add(Vector3.new(0.55 * s, 0.08, 1.1 * s), CFrame.new(0.25 * s, 0.05, 0), "sand_dark")
	add(Vector3.new(1.0 * s, 0.06, 0.5 * s), CFrame.new(-0.05 * s, 0.06, 0.3 * s), "sand")
	-- the shell: a broad round bottom and a smaller round top, overlapping (an egg's curve); the top the half that flies
	-- off when it hatches
	local y0 = 0.06
	local function ball(dia: number, off: CFrame, color: string, neon: boolean?, upper: boolean?)
		local p = Blocks.part(m, { size = Vector3.new(dia, dia, dia), cf = off, color = color, collide = false, query = false, neon = neon, shape = "Ball", name = if upper then "Top" else "Shell" })
		table.insert(parts, { p = p, off = off })
		if upper then
			table.insert(top, p)
		end
	end
	ball(0.86 * s, CFrame.new(0, y0 + 0.4 * s, 0), body)
	ball(0.66 * s, CFrame.new(0, y0 + 0.7 * s, 0), body, nil, true)
	-- spots on the side facing the view (glowing on a rare one or better), little round dabs set into the shell
	local sp = { { 0.3, 0.3, 0.22 }, { 0.48, 0.05, 0.4 }, { 0.56, 0.38, -0.02 }, { 0.36, -0.2, 0.33 }, { 0.82, 0.18, 0.2 } }
	for k, d in sp do
		ball(0.17 * s, CFrame.new(d[2] * s, y0 + d[1] * s, d[3] * s), spot, glow, k == 5)
	end
	if r >= 5 then
		-- a legendary egg: a band of light round its middle
		add(Vector3.new(0.62 * s, 0.06, 0.62 * s), CFrame.new(0, y0 + 0.4 * s, 0), "yellow", true)
		add(Vector3.new(0.06, 0.06, 0.9 * s), CFrame.new(0, y0 + 0.4 * s, 0), "yellow", true)
		add(Vector3.new(0.9 * s, 0.06, 0.06), CFrame.new(0, y0 + 0.4 * s, 0), "yellow", true)
	end
	return m, parts, top
end

local function untag(e: Egg)
	for _, g in { e.tag, e.name } :: { GuiObject? } do
		if g then
			g:Destroy()
		end
	end
	e.tag, e.name = nil, nil
end

local function dress(e: Egg)
	if e.model then
		return
	end
	local m, parts, top = eggOf(e.r)
	m.Parent = dyn()
	PixelRenderer.registerDynamic(m)
	e.model, e.parts, e.top = m, parts, top
end

local function drop(e: Egg)
	local m = e.model
	if m then
		PixelRenderer.unregisterDynamic(m)
		m:Destroy()
	end
	untag(e)
	eggs[e.key] = nil
end

------------------------------------------------------------------ hatching
-- Hatch the own tree's egg `id` (egg.hatch): into a hut, or every hut full, the tree panel's swap picker (swap 0);
-- with `swap`, in that one's place (it's sold).
function EggView.hatch(id: number, swap: number?)
	-- (where it lies: its driftling steps out there)
	local e = eggs[myPlot .. ":e" .. id]
	local spot = if e then spotOf(myPlot, e.slot, e.n) else nil
	local res = StateClient.request("egg.hatch", { id = id, swap = swap or 0 })
	if res.ok then
		hatching[id] = os.clock()
		if spot then
			lastHatch[myPlot] = spot
		end
		local data = if type(res.data) == "table" then res.data else {}
		local def = if type(data.sp) == "string" then Creatures.byId[data.sp] else nil
		local rar = Traits.RARITY[if def then def.rarity else 1] or Traits.RARITY[1]
		Audio.play(if def and def.rarity >= 3 then "rare" else "pop")
		local name = if def then def.name else "a driftling"
		local sold = tonumber(data.sold) or 0
		local a = if def and (def.rarity == 4 or def.rarity == 2) then "an" else "a"
		local what = if def then string.format("%s %s %s", a, string.lower(rar.name), name) else name
		UIKit.notice(if sold > 0 then string.format("It hatched %s! The one it replaced sold for %s shells.", what, Numbers.coins(sold)) else string.format("It hatched %s!", what), UIKit.color(rar.color), 4)
		if UIKit.currentPanel() == "tree" then
			UIKit.openPanel("tree")
		end
	elseif res.err == "full" then
		UIKit.openPanel("tree", { hatch = id })
	else
		Audio.play("deny")
		UIKit.notice(Words.errText(res.err), UIKit.color("bad"))
	end
end

-- The own tree's best few eggs for the HUD's card: the rarest first, the cheaper first among them; if the shells cover
-- none of those, the best one they cover in the last place.
function EggView.best(v: Types.ClientView, n: number): { Types.Laid }
	local list: { Types.Laid } = table.clone(v.clutch)
	table.sort(list, function(a, b): boolean
		if a.r ~= b.r then
			return a.r > b.r
		end
		return a.id < b.id
	end)
	local out: { Types.Laid } = {}
	local can = false
	for i = 1, math.min(n, #list) do
		table.insert(out, list[i])
		can = can or v.shells >= (list[i].cost or math.huge)
	end
	if not can and #out > 0 then
		for i = n + 1, #list do
			if v.shells >= (list[i].cost or math.huge) then
				out[#out] = list[i]
				break
			end
		end
	end
	return out
end

------------------------------------------------------------------ keeping up with the islands

-- One island's eggs from its attribute (near the view only): new ones rise, ones gone sink (or crack, hatched). A lot
-- keeps its slots on the ring while it lasts (slot: its place in the order it was laid; a bigger island's extra eggs
-- take the next ones), the ring as many slots as the island lays (Tuning.EggCount by its tier).
local lotFirst: { [number]: number } = {}
local function syncPlot(i: number, near: boolean, t: number)
	local m = plotModel(i)
	if not near or m == nil then
		for _, e in eggs do
			if e.plot == i then
				drop(e)
			end
		end
		lotFirst[i] = nil
		return
	end
	local raw = m:GetAttribute("Eggs")
	local list: { { id: number, r: number } } = {}
	local inList: { [number]: boolean } = {}
	local low = math.huge
	if type(raw) == "string" then
		for entry in string.gmatch(raw, "[^;]+") do
			local id, r = string.match(entry, "^(%d+)%.(%d)$")
			local n, rr = tonumber(id), tonumber(r)
			if n and rr then
				table.insert(list, { id = n, r = math.clamp(rr, 1, 5) })
				inList[n] = true
				low = math.min(low, n)
			end
		end
	end
	local live: { Egg } = {}
	for _, e in eggs do
		if e.plot == i and e.sink == nil and e.crack == nil then
			table.insert(live, e)
		end
	end
	local gone: { Egg } = {}
	for _, e in live do
		if not inList[e.id] then
			table.insert(gone, e)
		end
	end
	local newOnes = 0
	for _, x in list do
		if eggs[i .. ":e" .. x.id] == nil then
			newOnes += 1
		end
	end
	-- (a whole new lot: every egg there gone at once and new ones in)
	local fresh = #list > 0 and (#live == 0 or (#gone == #live and newOnes > 0))
	if (fresh or lotFirst[i] == nil) and low < math.huge then
		lotFirst[i] = low
	end
	local first = lotFirst[i] or 1
	local tier = (m:GetAttribute("Tier") :: number?) or 1
	local n = Tuning.EggCount[math.clamp(tier, 1, #Tuning.EggCount)]
	for _, e in gone do
		if hatching[e.id] or not fresh then
			-- (one gone while the rest stay: hatched)
			e.crack = t
			local p = spotOf(i, e.slot, e.n)
			if p then
				lastHatch[i] = p
			end
		else
			e.sink = t
		end
	end
	local came = 0
	for _, x in list do
		local key = i .. ":e" .. x.id
		local e = eggs[key]
		if e == nil then
			eggs[key] = { key = key, id = x.id, plot = i, r = x.r, slot = math.max(1, x.id - first + 1), n = n, parts = {}, top = {}, ph = (x.id * 0.618) % 1 * 6.28, born = t + came * STAGGER }
			came += 1
		else
			e.n = math.max(n, e.slot)
		end
	end
end

-- Where an egg is now (world foot) and how far under the lawn: rising, lying (rocking now and then), sinking, cracking.
local function placeOf(e: Egg, t: number): (CFrame?, number)
	local p = spotOf(e.plot, e.slot, e.n)
	if p == nil then
		return nil, 0
	end
	local under = 0
	if t < e.born + RISE then
		under = (1 - ease((t - e.born) / RISE)) * DEEP
	end
	if e.sink then
		under = math.max(under, ease((t - (e.sink :: number)) / SINK) * DEEP)
	end
	local tilt = 0
	local cycle = (t + e.ph) % 7
	if cycle < 0.6 then
		tilt = math.sin(cycle / 0.6 * math.pi * 3) * 0.12 * (1 - cycle / 0.6)
	end
	if e.crack then
		local k = (t - (e.crack :: number)) / CRACK
		if k < 0.45 then
			tilt = math.sin(k * 60) * 0.18
		end
	end
	-- (every egg turned the same way, its spots to the view)
	return CFrame.new(p.X, p.Y - under, p.Z) * CFrame.Angles(tilt, 0, tilt * 0.6), under
end

local function stepEgg(e: Egg, t: number)
	if e.sink and t - (e.sink :: number) > SINK then
		drop(e)
		return
	end
	if e.crack and t - (e.crack :: number) > CRACK then
		drop(e)
		return
	end
	local at = placeOf(e, t)
	if at == nil then
		drop(e)
		return
	end
	dress(e)
	local cf = at :: CFrame
	local k = if e.crack then (t - (e.crack :: number)) / CRACK else 0
	for _, rp in e.parts do
		local here = cf * rp.off
		if e.crack and k >= 0.45 then
			if table.find(e.top, rp.p) then
				-- (the top flies up and off, turning)
				local u = (k - 0.45) / 0.55
				here = cf * CFrame.new(0.6 * u, 2.2 * u - 1.6 * u * u, 0) * CFrame.Angles(0, 0, -2.2 * u) * rp.off
			else
				-- (the rest sinks into the lawn)
				here = here - Vector3.new(0, ease((k - 0.45) / 0.55) * 1.2, 0)
			end
		end
		rp.p.CFrame = here
	end
end

-- The own island's tags over the eggs near the view and above the lawn: the price on a button (green when the shells
-- are there). The rarest eggs' tags go first; one that would cover a rarer one's waits. The tips' step 4 bobs an arrow over the cheapest shown.
local tutArrow: ImageLabel? = nil
local function overlaps(a: { number }, list: { { number } }): boolean
	for _, b in list do
		if a[1] < b[3] + 2 and b[1] < a[3] + 2 and a[2] < b[4] + 1 and b[2] < a[4] + 1 then
			return true
		end
	end
	return false
end

local function updateTags(t: number)
	local v = StateClient.view()
	local costOf: { [number]: number } = {}
	if v then
		for _, x in v.clutch do
			costOf[x.id] = x.cost or 0
		end
	end
	local mine: { Egg } = {}
	for _, e in eggs do
		if e.plot == myPlot and e.sink == nil and e.crack == nil and e.model ~= nil and costOf[e.id] ~= nil then
			table.insert(mine, e)
		else
			untag(e)
		end
	end
	table.sort(mine, function(a: Egg, b: Egg): boolean
		if a.r ~= b.r then
			return a.r > b.r
		end
		return a.id < b.id
	end)
	local shown: { { number } } = {}
	local cheapest: Egg? = nil
	for _, e in mine do
		local cost = costOf[e.id]
		local can = v ~= nil and v.shells >= cost
		local text = Numbers.coins(cost)
		local tag = e.tag
		if tag == nil or tag:GetAttribute("Cost") ~= cost or tag:GetAttribute("Can") ~= can then
			if tag then
				tag:Destroy()
			end
			local w = UIKit.textWidth(text) + 18
			local id = e.id
			local b = UIKit.button(UIKit.canvas("World"), text, UDim2.fromOffset(w, 12), UDim2.fromOffset(0, 0), function()
				EggView.hatch(id)
			end, { name = "EggHatch_" .. e.id, color = if can then UIKit.color("button_ok") else UIKit.color("plate_light") })
			local words = b:FindFirstChild("Words")
			if words and words:IsA("GuiObject") then
				words.Position = UDim2.fromOffset(2, 0)
				words.Size = UDim2.new(1, -16, 1, 0)
			end
			PixelSprites.image(b, "mini_shell", UDim2.new(1, -13, 0, 0), 6).Name = "PriceIcon"
			b:SetAttribute("Cost", cost)
			b:SetAttribute("Can", can)
			e.tag = b
			tag = b
		end
		local at, under = placeOf(e, t)
		local foot = if at then (at :: CFrame).Position else Vector3.zero
		local px, py, on = PixelRenderer.projectPixel(foot + Vector3.new(0, under + 1.25 * (SIZE[e.r] or 1) + 0.35, 0))
		local tg = tag :: GuiObject
		local tw = tg.Size.X.Offset
		local rect = { px - math.floor(tw / 2), py - 12, px - math.floor(tw / 2) + tw, py }
		local nm = e.name
		if nm then
			local nw = nm.Size.X.Offset
			rect = { math.min(rect[1], px - math.floor(nw / 2)), py - 23, math.max(rect[3], px - math.floor(nw / 2) + nw), py }
		end
		on = on and at ~= nil and under < 0.3 and not overlaps(rect, shown)
		if on then
			table.insert(shown, rect)
		end
		tg.Visible = on
		tg.Position = UDim2.fromOffset(px - math.floor(tw / 2), py - 12)
		if nm then
			nm.Visible = on
			nm.Position = UDim2.fromOffset(px - math.floor(nm.Size.X.Offset / 2), py - 23)
		end
		if on and can and (cheapest == nil or cost < (costOf[(cheapest :: Egg).id] or math.huge)) then
			cheapest = e
		end
	end
	-- the tips: hatch an egg (step 4)
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

-- A tap on the screen (`pos`: an InputObject's, below the top bar) on one of the own tree's eggs hatches it, tag or
-- not (WorldView's taps ask here first). True when it hit one.
function EggView.tapAt(pos: Vector2): boolean
	local inset = GuiService:GetGuiInset()
	local sx, sy = pos.X + inset.X, pos.Y + inset.Y
	local t = os.clock()
	local best: Egg? = nil
	local bestD = math.huge
	for _, e in eggs do
		if e.plot ~= myPlot or e.sink ~= nil or e.crack ~= nil or e.model == nil then
			continue
		end
		local at, under = placeOf(e, t)
		if at == nil or under > 0.3 then
			continue
		end
		local foot, on = PixelRenderer.project((at :: CFrame).Position)
		local head = PixelRenderer.project((at :: CFrame).Position + Vector3.new(0, 1.1 * (SIZE[e.r] or 1), 0))
		local h = math.max(8, foot.Y - head.Y)
		local dx, dy = sx - foot.X, sy - (foot.Y + head.Y) / 2
		if on and math.abs(dx) <= h * 0.6 and math.abs(dy) <= h * 0.7 then
			local dist = dx * dx + dy * dy
			if dist < bestD then
				best, bestD = e, dist
			end
		end
	end
	if best then
		task.spawn(EggView.hatch, best.id)
		return true
	end
	return false
end

------------------------------------------------------------------ lifecycle
local syncAt = 0
-- Every frame from WorldView's Heartbeat (`focusX`: the view's centre, world x): the islands near it synced twice a
-- second, every egg moved, the own island's tags kept over them.
function EggView.step(t: number, focusX: number)
	local v = StateClient.view()
	if v then
		myPlot = v.plot
	end
	if t >= syncAt then
		syncAt = t + 0.5
		for i = 1, Street.MAX do
			syncPlot(i, math.abs(Street.origin(i) - focusX) <= NEAR, t)
		end
		for id, at in hatching do
			if t - at > 10 then
				hatching[id] = nil
			end
		end
	end
	for _, e in eggs do
		stepEgg(e, t)
	end
	updateTags(t)
end

-- Sims and previews: the eggs drawn now (all islands', or one island's), not counting ones sinking or cracking.
function EggView.count(plot: number?): number
	local n = 0
	for _, e in eggs do
		if (plot == nil or e.plot == plot) and e.sink == nil and e.crack == nil then
			n += 1
		end
	end
	return n
end

-- Sims and previews: where island `plot`'s egg `id` lies (world foot; nil: not drawn).
function EggView.where(plot: number, id: number): Vector3?
	local e = eggs[plot .. ":e" .. id]
	if e == nil then
		return nil
	end
	local at = placeOf(e, os.clock())
	return if at then (at :: CFrame).Position else nil
end

-- Where island i's last hatched egg was (world, on the lawn): where its driftling comes from. Else in front of the
-- tree's hollow, else the jetty's island end.
function EggView.hatchPoint(i: number): (number, number)
	local p = lastHatch[i]
	if p then
		return p.X, p.Z
	end
	local c, turn = treeAt(i)
	if c then
		local f = CFrame.new(c) * CFrame.Angles(0, turn, 0) * Vector3.new(DecorModels.HOLLOW.X, 0, DecorModels.HOLLOW.Z + 1)
		return f.X, f.Z
	end
	local m = plotModel(i)
	local tier = if m then (m:GetAttribute("Tier") :: number?) or 1 else 1
	local ox, oz = Street.origin(i)
	return ox, oz + Street.jetty(tier).z0 + 0.5
end

return EggView
