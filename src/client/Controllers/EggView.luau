--!strict
-- The Tree of Life's eggs (GAME_DESIGN 6; docs/ARCHITECTURE.md 10.2): "bring back the tree of life ... it now spawns
-- eggs around it that the player can choose to hatch for some shells". Every island's eggs come from its plot's "Eggs"
-- attribute (PlotService.sync: "id.rarity;..."), so a neighbour's tree has its eggs too. Each egg is a model of parts
-- (a shell on a little bed of straw, coloured and patterned by its rarity so one can tell them apart at a glance: "color
-- each egg differently with different effects to allow players to distinguish easily between egg rarities". A common
-- egg is cream with brown freckles; an uncommon one green with a white zigzag band and a leaf drifting up off it now
-- and then; a rare one sky blue with glowing white stars and twinkles round it; an epic one purple with glowing pink
-- spots, two motes of light circling it, a purple glow on the lawn and pink sparks rising; a legendary one gold with a
-- gold glow on the lawn, gold sparks rising and gold stars twinkling round it: no band or beam of light since
-- 2026-11-14), lying on the
-- tree's lawn on a ring round its stones
-- (Models/DecorModels.EGG_RING), spaced evenly along the side the view looks at. A new lot rises out of the lawn one
-- egg after another; the old ones left sink back into it. Now and then an egg rocks a little. The eggs carry no price
-- tags and a tap on one opens the tree's panel, where they are bought (the request of 2026-11-13: "remove these, the
-- eggs should be buyable only after the player clicks on the tree or enters the tree menu"). Hatch there runs
-- EggView.hatch (egg.hatch; every hut full, the panel's swap picker) and then the hatch scene (UI/HatchScene: the
-- egg up close, perhaps turning rarer, cracking, what hatched and its mutations). Back on the island the egg is gone
-- and what hatched walks off to work from its place (Controllers/WorldView).
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
local EggModels = require(ReplicatedStorage.Shared.Models.EggModels)
local StateClient = require(script.Parent.StateClient)
local Audio = require(script.Parent.Audio)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local PixelSprites = require(script.Parent.Parent.UI.PixelSprites)
local Words = require(script.Parent.Parent.UI.Words)
local HatchScene = require(script.Parent.Parent.UI.HatchScene)

local EggView = {}
-- (what a hatch refused for shells does: UI/Menus sets it to StoreUI.eggInstead, the egg for Robux instead)
EggView.onShort = nil :: ((r: number) -> ())?

-- one egg under a tree: its island, its place on the ring, its model and how it moves
type Egg = {
	key: string,
	id: number,
	plot: number,
	r: number,
	wx: string?, -- the weather that touched it (its mark: Models/EggModels; GAME_DESIGN 13)
	slot: number,
	n: number,
	model: Model?,
	parts: { { p: BasePart, off: CFrame } },
	top: { BasePart }, -- the shell's upper half (it flies off when it hatches)
	fx: { { p: BasePart, kind: string, k: number } }, -- the rarity's moving lights (motes, a beam)
	ph: number,
	spawnAt: number, -- when its next spark (the overlay's) comes
	born: number, -- when it rose out of the lawn
	sink: number?, -- when it started sinking back (a new lot replaced it)
	crack: number?, -- when it started hatching
	cf: CFrame?, -- where its parts were last put (unchanged: they are left alone)
	fxT: number?, -- the twelfth of a second its lights were last put in
	moveParts: { BasePart }?, -- its parts and their places, moved in one call (Workspace:BulkMoveTo)
	moveCfs: { CFrame }?,
}

local eggs: { [string]: Egg } = {}
local hatching: { [number]: number } = {} -- own egg ids just hatched (they crack instead of sinking)
local lastHatch: { [number]: Vector3 } = {} -- each island's egg that hatched last: where its driftling stands
local myPlot = 0
-- studs from the view's centre an island's eggs are drawn within: the next island either side (100 when they were 80
-- apart)
local NEAR = Tuning.PlotSpacing + 20
local RISE = 0.6 -- seconds an egg takes to rise out of the lawn (one after another, STAGGER apart)
local STAGGER = 0.12
local SINK = 0.5 -- seconds an old one takes to sink back
local CRACK = 0.9 -- seconds a hatching one takes: a shake, the top off, the bottom gone
local DEEP = 1.4 -- studs under the lawn an egg starts (and ends) at
local SIZE = EggModels.SIZE -- rarer eggs are a little bigger
EggView.LOOK = EggModels.LOOK

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
-- its turn (radians). Nil without one. Every egg asks every frame, so the answer is kept with the tree's model and
-- worked out again only once that model is gone (the request of 2026-11-19, "Expansion is very slow and laggy,
-- especially at higher levels": an expansion builds the tree again at its next stage, last among the island's pieces,
-- and each egg then read every piece's name each frame before reaching it, 38 ms a frame on a full tier 15 island).
type TreeSpot = { model: Instance, at: Vector3, rot: number }
local treeSpots: { [number]: TreeSpot } = {}
local function treeAt(i: number): (Vector3?, number)
	local hit = treeSpots[i]
	if hit and hit.model.Parent ~= nil then
		return hit.at, hit.rot
	end
	treeSpots[i] = nil
	local m = plotModel(i)
	local st = if m then m:FindFirstChild("Static") else nil
	local decor = if st then st:FindFirstChild("Decor") else nil
	if decor == nil then
		return nil, 0
	end
	local ox, oz = Street.origin(i)
	for _, c in decor:GetChildren() do
		local x, z, rot = string.match(c.Name, "^%d+:tree:(%-?%d+):(%-?%d+):(%d+)")
		local xx, zz, r = tonumber(x), tonumber(z), tonumber(rot)
		if xx and zz and r then
			local w, d = Plot.footprint("tree", r)
			local at = Vector3.new(ox + xx + w / 2, Street.LAWN_Y, oz + zz + d / 2)
			treeSpots[i] = { model = c, at = at, rot = math.rad(r) }
			return at, math.rad(r)
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

local function dress(e: Egg)
	if e.model then
		return
	end
	local m, parts, top, fx = EggModels.build(e.r, nil, nil, e.wx)
	m.Parent = dyn()
	PixelRenderer.registerDynamic(m)
	e.model, e.parts, e.top, e.fx = m, parts, top, fx
	local list: { BasePart } = table.create(#parts)
	for i, rp in parts do
		list[i] = rp.p
	end
	e.moveParts, e.moveCfs = list, table.create(#parts)
end

local function drop(e: Egg)
	local m = e.model
	if m then
		PixelRenderer.unregisterDynamic(m)
		m:Destroy()
	end
	eggs[e.key] = nil
end

------------------------------------------------------------------ hatching
-- Hatch the own tree's egg `id` (egg.hatch): into a hut, or every hut full, the tree panel's swap picker (swap 0);
-- with `swap`, in that one's place (it's sold). Done, the hatch scene plays (UI/HatchScene: the egg up close, perhaps
-- turning rarer, cracking, what hatched and its mutations); after it the tree's panel comes back if it was open (the
-- next egg a tap away) and a notice says what hatched.
-- What hatched (egg.hatch's or bag.hatch's data): the hatch scene, then the tree's panel back when it was open and a
-- notice of what came out.
-- (`panel`: the panel to bring back after it, the tree's or the Hatchery's, when one was open)
local function played(data: { [string]: any }, panel: string?)
	local def = if type(data.sp) == "string" then Creatures.byId[data.sp] else nil
	local rar = Traits.RARITY[if def then def.rarity else 1] or Traits.RARITY[1]
	local name = if def then def.name else "a driftling"
	local sold = tonumber(data.sold) or 0
	-- ("an" before a rarity starting with a vowel: an uncommon, an epic, an ancient, an eternal one)
	local a = if def and string.match(string.lower(rar.name), "^[aeiou]") then "an" else "a"
	local what = if def then string.format("%s %s %s", a, string.lower(rar.name), name) else name
	local muts: { string } = {}
	if type(data.muts) == "table" then
		for _, m in data.muts do
			if type(m) == "string" then
				table.insert(muts, m)
			end
		end
	end
	local r = math.clamp(tonumber(data.r) or 1, 1, Traits.RMAX)
	-- (a kind never had before: "New!" by its name in the scene and in front of the notice)
	local fresh = data.new == true
	UIKit.closePanel()
	HatchScene.play({ sp = if type(data.sp) == "string" then data.sp else "", muts = muts, r = r, hr = math.clamp(tonumber(data.hr) or r, r, Traits.RMAX), new = fresh }, function()
		-- (the panel first: opening it clears the notices, so what hatched goes on the new panel's status line; not while
		-- another hatch waits to play, whose scene comes next: then what hatched shows as a notice over it)
		if panel and StateClient.view() ~= nil and HatchScene.waiting() == 0 then
			UIKit.openPanel(panel)
		end
		local said = if sold > 0 then string.format("Hatched %s. The old one sold for %s shells.", what, Numbers.coins(sold)) else string.format("Hatched %s.", what)
		UIKit.notice((if fresh then "New! " else "") .. said, UIKit.color(rar.color), 4)
	end)
end

function EggView.hatch(id: number, swap: number?)
	-- (where it lies: its driftling steps out there)
	local e = eggs[myPlot .. ":e" .. id]
	local spot = if e then spotOf(myPlot, e.slot, e.n) else nil
	local panel = if UIKit.currentPanel() == "tree" then "tree" else nil
	local res = StateClient.request("egg.hatch", { id = id, swap = swap or 0 })
	if res.ok then
		hatching[id] = os.clock()
		if spot then
			lastHatch[myPlot] = spot
		end
		played(if type(res.data) == "table" then res.data else {}, panel)
	elseif res.err == "full" then
		UIKit.openPanel("tree", { hatch = id })
	elseif res.err == "money" and EggView.onShort then
		-- (short of shells: the egg of its rarity for Robux instead; UI/Menus sets the hook to StoreUI.eggInstead)
		local hook = EggView.onShort :: (r: number) -> ()
		hook(if e then e.r else 1)
	else
		Audio.play("deny")
		UIKit.notice(Words.errText(res.err), UIKit.color("bad"))
	end
end

-- Hatch the bag's egg `id` (bag.hatch: bought, won on the pass track or a gift; GAME_DESIGN 14): no shells, into a
-- hut, or every hut full, the tree panel's swap picker for it; the same hatch scene. It never lay under the tree, so
-- no egg on the ring cracks.
function EggView.hatchBag(id: number, swap: number?)
	local panel = if UIKit.currentPanel() == "tree" then "tree" else nil
	local res = StateClient.request("bag.hatch", { id = id, swap = swap or 0 })
	if res.ok then
		played(if type(res.data) == "table" then res.data else {}, panel)
	elseif res.err == "full" then
		UIKit.openPanel("tree", { hatch = id, bag = true })
	else
		Audio.play("deny")
		UIKit.notice(Words.errText(res.err), UIKit.color("bad"))
	end
end

-- The own island's Hatchery `uid`: the point on the ground just in front of it (world), where its hatchling steps out.
local function hatcheryFront(uid: number): Vector3?
	local m = plotModel(myPlot)
	local st = if m then m:FindFirstChild("Static") else nil
	local decor = if st then st:FindFirstChild("Decor") else nil
	if decor == nil then
		return nil
	end
	local ox, oz = Street.origin(myPlot)
	for _, c in decor:GetChildren() do
		local u, id, x, z, rot = string.match(c.Name, "^(%d+):([%w_]+):(%-?%d+):(%-?%d+):(%d+)")
		local xx, zz, r = tonumber(x), tonumber(z), tonumber(rot)
		if tonumber(u) == uid and id and xx and zz and r then
			local w, d = Plot.footprint(id, r)
			return Vector3.new(ox + xx + w / 2, Street.LAWN_Y, oz + zz + d + 0.8)
		end
	end
	return nil
end

-- The egg at the own Hatchery `uid` (the view's), if any.
function EggView.hatcheryEgg(uid: number): Types.Egg?
	local v = StateClient.view()
	local eggs: { Types.Egg } = (if v then v.eggs else nil) or {}
	for _, e in eggs do
		if e.uid == uid then
			return e
		end
	end
	return nil
end

-- Hatch the ready egg at the own Hatchery `uid` (breed.hatch; the request of 2026-11-20: "the hatchery should have the
-- timer above its building, and show ready! once the egg is ready. clicking it while ready shows the hatching screen
-- just like hatching an egg normally, but with the resultant creature"): the same hatch scene as the tree's eggs with
-- what came out (laid as its kind's rarity, it hatches as that: no rarer roll), then the Hatchery's panel back when it
-- was open and a notice of what hatched. Its driftling steps out in front of the Hatchery.
function EggView.hatchery(uid: number): boolean
	local panel = if UIKit.currentPanel() == "hatch" then "hatch" else nil
	local res = StateClient.request("breed.hatch", { uid = uid })
	if not res.ok then
		Audio.play("deny")
		UIKit.notice(Words.errText(res.err), UIKit.color("bad"))
		return false
	end
	local at = hatcheryFront(uid)
	if at then
		lastHatch[myPlot] = at
	end
	local data: { [string]: any } = if type(res.data) == "table" then res.data else {}
	local r = math.clamp(tonumber(data.r) or 1, 1, Traits.RMAX)
	played({ sp = data.sp, muts = data.muts, r = r, hr = r, new = data.new == true }, panel)
	return true
end

-- A tap on the own Hatchery `uid` (on the building or its tag): a ready egg hatches; otherwise its panel opens (the
-- request of 2026-11-14: "allow clicking on a hatchery to open the hatchery menu").
function EggView.tapHatchery(uid: number)
	local e = EggView.hatcheryEgg(uid)
	if e and e.left <= 0 then
		EggView.hatchery(uid)
	else
		UIKit.openPanel("hatch")
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
-- take the free ones), the ring as many slots as the island lays (Tuning.EggCount by its tier).
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
	local list: { { id: number, r: number, wx: string? } } = {}
	local inList: { [number]: boolean } = {}
	local low = math.huge
	if type(raw) == "string" then
		for entry in string.gmatch(raw, "[^;]+") do
			-- ("id.r", or "id.r.wx": the weather that touched it, GAME_DESIGN 13)
			local id, r, wx = string.match(entry, "^(%d+)%.(%d)%.?(%a*)$")
			local n, rr = tonumber(id), tonumber(r)
			if n and rr then
				table.insert(list, { id = n, r = math.clamp(rr, 1, Traits.RMAX), wx = if wx and wx ~= "" then wx else nil })
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
	-- (the ring shows the rarest Tuning.EggShown of a lot: Logic/Tree.shown)
	local n = math.min(Tuning.EggShown, Tuning.EggCount[math.clamp(tier, 1, #Tuning.EggCount)])
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
	-- (a new egg takes its place in the lot's order when that slot is on the ring and free, else the first free one: the
	-- extra eggs of an expansion after a hatch, or a lot first seen with gaps in it, never land on another egg's spot)
	local held: { [number]: boolean } = {}
	for _, e in eggs do
		if e.plot == i and e.sink == nil and e.crack == nil then
			held[e.slot] = true
		end
	end
	local came = 0
	for _, x in list do
		local key = i .. ":e" .. x.id
		local e = eggs[key]
		if e == nil then
			local slot = math.max(1, x.id - first + 1)
			if slot > n or held[slot] then
				slot = 1
				while held[slot] do
					slot += 1
				end
			end
			held[slot] = true
			eggs[key] = { key = key, id = x.id, plot = i, r = x.r, wx = x.wx, slot = slot, n = n, parts = {}, top = {}, fx = {}, ph = (x.id * 0.618) % 1 * 6.28, born = t + came * STAGGER, spawnAt = 0 }
			came += 1
		else
			e.n = math.max(n, e.slot)
			if e.r ~= x.r then
				-- (the same egg turned another rarity: the quest's egg, Logic/Tree.ensure): its new shell rises in its
				-- place
				local old = e.model
				if old then
					PixelRenderer.unregisterDynamic(old)
					old:Destroy()
				end
				e.model, e.parts, e.top, e.fx = nil, {}, {}, {}
				e.r = x.r
				e.born = t
			end
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
		local u = (t - e.born) / RISE
		under = (1 - ease(u)) * DEEP
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
	-- (an egg lying still keeps its place frame after frame: its parts are put again only when it moved, rocks, rises,
	-- sinks or cracks; every egg's dozens of parts written every frame came to about 2 ms a frame on a full island)
	local moved = e.crack ~= nil or e.cf ~= cf
	e.cf = cf
	local k = if e.crack then (t - (e.crack :: number)) / CRACK else 0
	if moved then
		local cfs = e.moveCfs :: { CFrame }
		for i, rp in e.parts do
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
			cfs[i] = here
		end
		workspace:BulkMoveTo(e.moveParts :: { BasePart }, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	-- the rarity's lights: an epic or mythic egg's motes circle it, bobbing; a celestial egg's ring of lights orbits it,
	-- tilted like a planet's ring. Hatching or sinking, they go out (under the lawn).
	local s = SIZE[e.r] or 1
	local quiet = e.crack ~= nil or e.sink ~= nil
	-- (they move twelve times a second: in between the pixel filter shows the egg's kept picture, and they are left
	-- where they are)
	t = math.floor(t * 12) / 12
	if not moved and e.fxT == t then
		return
	end
	e.fxT = t
	for _, f in e.fx do
		if quiet then
			f.p.CFrame = CFrame.new(cf.Position - Vector3.new(0, 6, 0))
		elseif f.kind == "mote" then
			local a = t * 1.7 + e.ph + f.k * math.pi
			local y = 0.06 + (0.62 + 0.12 * math.sin(t * 2.3 + f.k * 2)) * s
			f.p.CFrame = cf * CFrame.new(math.cos(a) * 0.78 * s, y, math.sin(a) * 0.78 * s)
		elseif f.kind == "orbit" then
			local a = t * 0.9 + e.ph + f.k / 9 * math.pi * 2
			f.p.CFrame = cf * CFrame.new(math.cos(a) * 0.85 * s, (0.62 + math.cos(a) * 0.2) * s, math.sin(a) * 0.85 * s)
		elseif f.kind == "orbit2" then
			-- (an eternal egg's second ring: the other way round, tilted against the first)
			local a = -t * 0.7 + e.ph + f.k / 9 * math.pi * 2
			f.p.CFrame = cf * CFrame.new(math.cos(a) * 0.95 * s, (0.62 - math.sin(a) * 0.24) * s, math.sin(a) * 0.95 * s)
		elseif f.kind == "beam" then
			local h = 2.2 + 0.5 * math.sin(t * 1.9 + e.ph)
			local baseY = 0.06 + 1.1 * s
			f.p.Size = Vector3.new(0.25, Blocks.snap(h), 0.25)
			f.p.CFrame = cf * CFrame.new(0, baseY + Blocks.snap(h) / 2, 0)
		end
	end
end

-- The rarities' sparks over the eggs (2D, on the World canvas, at whole UI px: "particles are 1 px"): an uncommon egg
-- lets a green leaf drift up now and then, a rare one twinkles (white and cyan stars blink round it), an epic one sends
-- pink and white sparks up, a legendary one gold sparks and gold stars, a mythic one pink stars and pink and white
-- sparks, a celestial one long white and cyan glints and motes of every colour rising, an ancient one embers rising and
-- flaring, an eternal one motes in every rarity's colour and glints of light with rainbow tips (2026-11-20). Only round
-- eggs lying still (not rising, sinking or hatching), at most SPARKS at once.
type Spark = { egg: string, at: Vector3, vel: Vector3, born: number, life: number, kind: string, gui: GuiObject, frames: { GuiObject }?, sway: number }
local sparks: { Spark } = {}
local SPARKS = 140
local EVERY: { [number]: number } = { 0, 0.8, 0.42, 0.26, 0.14, 0.11, 0.08, 0.07, 0.06 } -- seconds between an egg's sparks, by rarity (0: none)

local function newSpark(e: Egg, foot: Vector3, t: number)
	if #sparks >= SPARKS then
		return
	end
	local s = SIZE[e.r] or 1
	local canvas = UIKit.canvas("World")
	local a = math.random() * math.pi * 2
	local function dot(color: string, at: Vector3, vel: Vector3, life: number)
		local g = UIKit.rect(canvas, UDim2.fromOffset(1, 1), nil, Blocks.color(color), 3)
		g.Name = "EggSpark"
		local sp: Spark = { egg = e.key, at = at, vel = vel, born = t, life = life, kind = "dot", gui = g, frames = nil, sway = math.random() * 6.28 }
		table.insert(sparks, sp)
	end
	local function star(names: { string }, at: Vector3, life: number)
		local holder = Instance.new("Frame")
		holder.Name = "EggStar"
		holder.BackgroundTransparency = 1
		local w, h = PixelSprites.size(names[1])
		holder.Size = UDim2.fromOffset(w, h)
		local frames: { GuiObject } = {}
		for k, n in names do
			local im = PixelSprites.image(holder, n, UDim2.fromOffset(0, 0), 3)
			im.Visible = k == 1
			frames[k] = im
		end
		holder.Parent = canvas
		local sp: Spark = { egg = e.key, at = at, vel = Vector3.zero, born = t, life = life, kind = "star", gui = holder, frames = frames, sway = 0 }
		table.insert(sparks, sp)
	end
	if e.r == 2 then
		-- a leaf off the top, drifting up and to the side
		dot(if math.random() < 0.5 then "green" else "leaf", foot + Vector3.new(math.cos(a) * 0.3 * s, 1.0 * s, math.sin(a) * 0.3 * s), Vector3.new(0, 0.6, 0), 1.6)
	elseif e.r == 3 then
		-- a star blinking somewhere round the shell
		local at = foot + Vector3.new(math.cos(a) * 0.62 * s, (0.25 + math.random()) * s, math.sin(a) * 0.62 * s)
		star({ "twinkle_1", "twinkle_2", "twinkle_1" }, at, 0.6)
	elseif e.r == 4 then
		dot(if math.random() < 0.6 then "pink" else "white", foot + Vector3.new(math.cos(a) * 0.55 * s, 0.3 * s, math.sin(a) * 0.55 * s), Vector3.new(0, 0.9 + math.random() * 0.4, 0), 1.3)
	elseif e.r == 6 then
		-- pink and white sparks rising, now and then a pink star blinking round it
		dot(if math.random() < 0.6 then "cherry" else "white", foot + Vector3.new(math.cos(a) * 0.6 * s, 0.25 * s, math.sin(a) * 0.6 * s), Vector3.new(0, 1.1 + math.random() * 0.5, 0), 1.3)
		if math.random() < 0.35 then
			star({ "twinkle_p1", "twinkle_p2", "twinkle_p3", "twinkle_p2" }, foot + Vector3.new(math.cos(a + 1.3) * 0.7 * s, (0.3 + math.random() * 1.1) * s, math.sin(a + 1.3) * 0.7 * s), 0.6)
		end
	elseif e.r >= 9 then
		-- motes in every rarity's colour rising, glints with rainbow tips opening and closing round it
		dot(({ "white", "r_mythic", "r_legend", "r_uncommon", "r_rare", "r_epic" })[math.random(1, 6)], foot + Vector3.new(math.cos(a) * 0.75 * s, 0.2 * s, math.sin(a) * 0.75 * s), Vector3.new(0, 0.8 + math.random() * 0.6, 0), 1.7)
		if math.random() < 0.4 then
			star({ "prism_1", "prism_2", "prism_3", "prism_2", "prism_1" }, foot + Vector3.new(math.cos(a + 2) * 0.85 * s, (0.3 + math.random() * 1.3) * s, math.sin(a + 2) * 0.85 * s), 0.8)
		end
	elseif e.r == 8 then
		-- embers rising off it, swaying, and now and then one flaring by it
		dot(if math.random() < 0.55 then "lava" elseif math.random() < 0.5 then "oven_glow" else "yellow", foot + Vector3.new(math.cos(a) * 0.6 * s, 0.25 * s, math.sin(a) * 0.6 * s), Vector3.new(0, 1.0 + math.random() * 0.6, 0), 1.5)
		if math.random() < 0.35 then
			star({ "ember_1", "ember_2", "ember_3" }, foot + Vector3.new(math.cos(a + 1.5) * 0.7 * s, (0.3 + math.random() * 1.1) * s, math.sin(a + 1.5) * 0.7 * s), 0.6)
		end
	elseif e.r >= 7 then
		-- motes of every colour rising, long glints opening and closing round it
		dot(({ "white", "screen_on", "crystal", "yellow" })[math.random(1, 4)], foot + Vector3.new(math.cos(a) * 0.7 * s, 0.2 * s, math.sin(a) * 0.7 * s), Vector3.new(0, 0.8 + math.random() * 0.6, 0), 1.6)
		if math.random() < 0.4 then
			star({ "glint_1", "glint_2", "glint_3", "glint_2", "glint_1" }, foot + Vector3.new(math.cos(a + 2) * 0.8 * s, (0.3 + math.random() * 1.3) * s, math.sin(a + 2) * 0.8 * s), 0.75)
		end
	else
		dot(if math.random() < 0.7 then "yellow" else "white", foot + Vector3.new(math.cos(a) * 0.6 * s, 0.2 * s, math.sin(a) * 0.6 * s), Vector3.new(0, 1.3 + math.random() * 0.6, 0), 1.2)
		if math.random() < 0.3 then
			star({ "spark_1", "spark_2", "spark_3" }, foot + Vector3.new(math.cos(a + 1) * 0.7 * s, (0.4 + math.random() * 1.2) * s, math.sin(a + 1) * 0.7 * s), 0.55)
		end
	end
end

local function stepSparks(t: number)
	-- new ones from the eggs lying still on the lawn
	if PixelRenderer.isActive() then
		for _, e in eggs do
			local every = EVERY[e.r] or 0
			if every <= 0 or e.model == nil or e.sink ~= nil or e.crack ~= nil then
				continue
			end
			if t >= e.spawnAt then
				local at, under = placeOf(e, t)
				if at and under < 0.05 then
					newSpark(e, (at :: CFrame).Position, t)
				end
				e.spawnAt = t + every * (0.6 + math.random() * 0.8)
			end
		end
	end
	local keep: { Spark } = {}
	for _, sp in sparks do
		local age = t - sp.born
		local e = eggs[sp.egg]
		if age >= sp.life or e == nil or e.crack ~= nil or e.sink ~= nil then
			sp.gui:Destroy()
			continue
		end
		local w = sp.at + sp.vel * age + Vector3.new(math.sin(sp.sway + age * 4) * 0.12 * (if sp.kind == "dot" then 1 else 0), 0, 0)
		local px, py, on = PixelRenderer.projectPixel(w)
		if sp.kind == "star" then
			local frames = sp.frames :: { GuiObject }
			local k = math.clamp(math.floor(age / sp.life * #frames) + 1, 1, #frames)
			for i, f in frames do
				f.Visible = i == k
			end
			local g = sp.gui
			g.Position = UDim2.fromOffset(math.floor(px) - math.floor(g.Size.X.Offset / 2), math.floor(py) - math.floor(g.Size.Y.Offset / 2))
		else
			sp.gui.Position = UDim2.fromOffset(math.floor(px), math.floor(py))
		end
		sp.gui.Visible = on
		table.insert(keep, sp)
	end
	sparks = keep
end

-- The tips' step 4 (hatch an egg): an arrow bobbing over the own Tree of Life (a tap on it opens its panel, where the
-- eggs are bought); with the tree off the screen, an arrow at the screen's edge pointing the way to it. The request of
-- 2026-11-14: "auto close the build tab when going to the hatching step and point towards the tree of life for the
-- player to click" (the full-size arrow, 13 px: the small one was easy to miss; Build mode closes itself: BuildUI).
local tutArrow: ImageLabel? = nil
local tutArrowName = ""
local function updateArrow(t: number)
	local v = StateClient.view()
	local c = if v and v.tut == 4 and not HatchScene.isOpen() and UIKit.currentPanel() == nil then treeAt(myPlot) else nil
	if c == nil then
		if tutArrow then
			tutArrow:Destroy()
			tutArrow = nil
		end
		return
	end
	local px, py, on = PixelRenderer.projectPixel((c :: Vector3) + Vector3.new(0, 4.5, 0))
	local size = UIKit.size("World")
	local W, H = size.X, size.Y
	local M = 14 -- (how far in from the edges the edge arrow keeps)
	local bob = if math.floor(t * 3) % 2 == 0 then 0 else 2
	local name, x, y
	if on and px >= M and px <= W - M and py >= M + 13 and py <= H - M then
		-- over the tree, pointing down at it
		name, x, y = "arrow_down", px - 6, py - 15 + bob
	else
		-- at the edge, pointing the way from the middle of the screen
		local dx, dy = px - W / 2, py - H / 2
		local k = math.min((W / 2 - M) / math.max(1, math.abs(dx)), (H / 2 - M) / math.max(1, math.abs(dy)))
		local ex, ey = W / 2 + dx * math.min(1, k), H / 2 + dy * math.min(1, k)
		if math.abs(dx) * H >= math.abs(dy) * W then
			name = if dx > 0 then "arrow_right" else "arrow_left"
			x, y = ex - 6 + (if dx > 0 then bob else -bob), ey - 6
		else
			name = if dy > 0 then "arrow_down" else "arrow_up"
			x, y = ex - 6, ey - 6 + (if dy > 0 then bob else -bob)
		end
	end
	if tutArrow == nil or tutArrowName ~= name then
		if tutArrow then
			tutArrow:Destroy()
		end
		tutArrow = PixelSprites.image(UIKit.canvas("World"), name, UDim2.fromOffset(0, 0), 5) :: any
		tutArrowName = name
	end
	local arrow = tutArrow :: ImageLabel
	arrow.Name = "TutArrow"
	arrow.Visible = true
	arrow.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
end

-- A tap on the screen (`pos`: an InputObject's, below the top bar) on one of the own tree's eggs opens the tree's
-- panel, where the eggs are bought (WorldView's taps ask here first). True when it hit one.
-- How far (screen px squared, from the egg's middle) the nearest own egg under a tap at `pos` lies, or nil: WorldView
-- weighs it against a driftling under the same tap, the nearer one taken.
function EggView.hitDist(pos: Vector2): number?
	local inset = GuiService:GetGuiInset()
	local sx, sy = pos.X + inset.X, pos.Y + inset.Y
	local t = os.clock()
	local bestD: number? = nil
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
			if bestD == nil or dist < bestD then
				bestD = dist
			end
		end
	end
	return bestD
end

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
		Audio.play("click")
		UIKit.openPanel("tree")
		return true
	end
	return false
end

------------------------------------------------------------------ lifecycle
local syncAt = 0
-- Every frame from WorldView's Heartbeat (`focusX`: the view's centre, world x): the islands near it synced twice a
-- second, every egg moved, the tips' arrow kept over the tree.
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
	stepSparks(t)
	updateArrow(t)
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
-- tree's hollow, else where a founder appears on an island with no tree.
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
	local ox, oz = Street.origin(i)
	local sx, sz = Street.spawn()
	return ox + sx, oz + sz
end

return EggView
