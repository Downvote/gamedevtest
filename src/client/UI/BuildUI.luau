--!strict
-- Build mode (GAME_DESIGN 4; docs/ARCHITECTURE.md 10.7): building the island, in the style of the bakery's Decorate
-- mode and a house-building game's catalog ("Polish the build ui more, just like the bakery game, and reference
-- bloxburg"). The HUD's Build button opens it: the view stops following the founder and shows the own island (a drag
-- on the world pans it, CameraController.setFree / panBy), and a tray along the bottom holds the catalog:
--   tabs     Work (farms, wood, shops, boosts), Huts, Paths, Fences, Water, Nature, Decor, Fun, each with its icon
--            (the icons alone on a narrow screen); on the right the tab's count against its limit, Expand and Done
--   chips    the tab's rows: Decor's themes (beach, garden, farm, harbour, town, jungle, frost, autumn, desert, fairy,
--            zen, volcano, grand), Nature's trees, plants and rocks, Fun's seats, lights, play, treats and fountains,
--            Work's kinds, Water's water, bridges and floating things
--   cards    a picture of each piece drawn from its 3D model (UI/ThumbData "thumb_<id>") and its price in wood, cheapest
--            first, the locked ones after with the island level they open at; a mouse over a card shows its name,
--            what it is, its charm and size
-- A piece picked: its ghost stands where the pointer is (mouse) or was tapped (touch), on a footprint that is cyan where
-- it fits (Logic/Plot.fits, the server's own rule) and red where it does not; Place (or a second click on the same spot,
-- or E) asks the server (plot.place: paid then) and keeps it picked for another; Rotate (R) turns it a quarter. Tapping a
-- piece on the island picks it up: Move it, Copy it (another of the same, C), Replace it with another of its row, or
-- Clear it away (X: half its price back). Esc drops what is picked, then leaves. Paths, water and fences are drawn (the
-- draw bar below). Putting anything down has its effects and sounds (Controllers/BuildFx). Done closes it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Shared.Types)
local Buildings = require(ReplicatedStorage.Shared.Data.Buildings)
local Office = require(ReplicatedStorage.Shared.Data.Office)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Plot = require(ReplicatedStorage.Shared.Logic.Plot)
local Island = require(ReplicatedStorage.Shared.Logic.Island)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local Blocks = require(ReplicatedStorage.Shared.Models.Blocks)
local DecorModels = require(ReplicatedStorage.Shared.Models.DecorModels)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local BuildFx = require(script.Parent.Parent.Controllers.BuildFx)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local Words = require(script.Parent.Words)

local BuildUI = {}
BuildUI.Changed = Util.Signal() :: Types.Signal<boolean>

local TRAY_H = 82
BuildUI.TRAY_H = TRAY_H
local CARD_W, CARD_H = 38, 46 -- an item card: its picture (24 x 24) on a plate, its price under it
local PIC = 24

-- the tray's tabs (Data/Buildings tab), each with its small icon, and their rows of chips (Data/Buildings sub; "" all)
type Tab = { key: string, text: string, icon: string }
local TABS: { Tab } = {
	{ key = "work", text = "Work", icon = "work" },
	{ key = "nest", text = "Huts", icon = "nest" },
	{ key = "path", text = "Paths", icon = "path" },
	{ key = "fence", text = "Fences", icon = "fence" },
	{ key = "water", text = "Water", icon = "water" },
	{ key = "nature", text = "Nature", icon = "nature" },
	{ key = "decor", text = "Decor", icon = "decor" },
	{ key = "fun", text = "Fun", icon = "fun" },
}
local CHIPS: { [string]: { { string } } } = {
	work = { { "", "All" }, { "farm", "Farms" }, { "wood", "Wood" }, { "shop", "Shops" }, { "gen", "Boosts" } },
	water = { { "", "All" }, { "tiles", "Water" }, { "bridge", "Bridges" }, { "float", "On the water" } },
	nature = { { "", "All" }, { "trees", "Trees" }, { "plants", "Plants" }, { "rocks", "Rocks" } },
	decor = {
		{ "", "All" },
		{ "beach", "Beach" },
		{ "garden", "Garden" },
		{ "farm", "Farm" },
		{ "harbour", "Harbour" },
		{ "town", "Town" },
		{ "jungle", "Jungle" },
		{ "frost", "Frost" },
		{ "autumn", "Autumn" },
		{ "desert", "Desert" },
		{ "fairy", "Fairy" },
		{ "zen", "Zen" },
		{ "volcano", "Volcano" },
		{ "grand", "Grand" },
	},
	fun = { { "", "All" }, { "seats", "Seats" }, { "lights", "Lights" }, { "play", "Play" }, { "treats", "Treats" }, { "fountains", "Fountains" } },
}
-- the old tabs (the quests' Go: "build:wood"): Work's chips now
local OLD_TABS: { [string]: string } = { farm = "farm", wood = "wood", shop = "shop", gen = "gen" }
local tab = "work"
local chip: { [string]: string } = { work = "wood" }

-- The tips in Build mode (GAME_DESIGN 9: "make the tutorial show while in the build menu as well, and auto switches
-- the player to the tab where the required buildings are in"): the tip's banner stays above the tray (UI/Hud), and
-- opening Build mode, or a tip moving on while it is open, turns the tray to the tab (and row) of the building the tip
-- asks for; that building's card (and its tab, while another is shown) pulses until it stands on the island.
local TUT: { [number]: { tab: string, chip: string, id: string } } = {
	[1] = { tab = "work", chip = "wood", id = "lumber" },
	[2] = { tab = "work", chip = "farm", id = "patch" },
	[3] = { tab = "nest", chip = "", id = "nest" },
	[5] = { tab = "work", chip = "shop", id = "stall" },
}
local tutSeen: number? = nil -- the tip the tray last turned for (nil: turn on the next look)
local goalCard: Frame? = nil
local goalTab: GuiButton? = nil
type Pick = { id: string, rot: number, move: number?, x: number, z: number, set: boolean, replace: boolean? }

local open = false
local tray: Frame? = nil
local tip: Frame? = nil
local pick: Pick? = nil
local ghost: Model? = nil
local marker: BasePart? = nil
local conns: { { Disconnect: (any) -> () } } = {}
local cardScroll = 0 -- the cards' scroll, kept across rebuilds of the same tab and row
local cardScrollKey = ""
-- the search box (the bakery's decor box has one): its words (lower case) list the matching pieces from every tab; the
-- box itself is kept across rebuilds, so typing never loses the keyboard
local query = ""
local search: Frame? = nil

-- Drawing paths, water and fences (GAME_DESIGN 4: "paths should be able to be drawn or made in a box like the original
-- interface in the bakery game"; fences and rivers the same way): with one picked, a press on the island starts a
-- stroke instead of a pan. Line: the drag lays it along the way (every 2-stud cell the pointer passes for a tile, every
-- grid line between the corners it passes for a fence, no gaps when it jumps); Box: the drag fills the box between the
-- press and the pointer with tiles, or runs a fence round it; Erase: the same strokes take them up (half their price
-- back); Look around: a drag pans again. What the stroke would do shows on the island at once (a flat marker a cell or
-- a bar an edge: cyan where one goes, yellow where one of another look is swapped, orange where one comes up, red where
-- it can't), and on release it goes to the server (plot.paint / plot.unpaint / plot.fence / plot.unfence,
-- Plot.PAINT_MAX a request).
type Draw = { box: boolean, erase: boolean, look: boolean, start: { number }?, last: { number }?, cells: { { number } }, seen: { [string]: boolean }, memo: { [string]: boolean } }
local draw: Draw = { box = false, erase = false, look = false, start = nil, last = nil, cells = {}, seen = {}, memo = {} }
local drawGhost: Model? = nil
local DRAW_MOST = 240 -- cells or edges a stroke holds at most (a box is cut there)

local function view(): Types.ClientView?
	return StateClient.view()
end

local function placed(): { Types.Piece }
	local v = view()
	return if v then v.pieces else {}
end

local function myPlot(): number
	local v = view()
	return if v then v.plot else 1
end

-- What the current tip asks to build, while it is not built yet.
local function tutGoal(v: Types.ClientView?): { tab: string, chip: string, id: string }?
	if v == nil then
		return nil
	end
	local g = TUT[v.tut]
	if g == nil then
		return nil
	end
	for _, q in v.pieces do
		if q.id == g.id then
			return nil
		end
	end
	return g
end

-- Turn the tray to the tip's tab when the tip is new to it (it waits while a piece is picked); true when it turned.
local function followTut(v: Types.ClientView?): boolean
	if v == nil or v.tut == tutSeen then
		return false
	end
	local g = tutGoal(v)
	if g and pick ~= nil then
		return false
	end
	tutSeen = v.tut
	if g and (tab ~= g.tab or (chip[g.tab] or "") ~= g.chip) then
		tab = g.tab
		chip[g.tab] = g.chip
		return true
	end
	return false
end

local function origin(): (number, number)
	return Office.origin(myPlot())
end

local function ask(action: string, payload: { [string]: any }, ok: string?): Types.Response
	local res = StateClient.request(action, payload)
	if res.ok then
		if ok then
			UIKit.notice(ok, UIKit.color("good"))
		end
	else
		UIKit.notice(if res.err == "blocked" then "It doesn't fit there." else Words.errText(res.err), UIKit.color("bad"))
	end
	return res
end

-- A piece's picture (its thumbnail, else its tab's icon) at pos, 24 x 24.
local function picture(parent: Instance, id: string, pos: UDim2, z: number?): GuiObject
	local name = "thumb_" .. id
	if PixelSprites.has(name) then
		return PixelSprites.image(parent, name, pos, z)
	end
	local d = Buildings.byId[id]
	local holder = Instance.new("Frame")
	holder.Name = "Picture"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(PIC, PIC)
	holder.Position = pos
	holder.Parent = parent
	local icon = "mini_" .. (if d then (if d.tab == "nest" then "nest" else d.tab) else "decor")
	PixelSprites.image(holder, if PixelSprites.has(icon) then icon else "mini_decor", UDim2.fromOffset(6, 6), z)
	return holder
end

------------------------------------------------------------------ the ghost
local function clearGhost()
	if ghost then
		PixelRenderer.unregisterDynamic(ghost)
		ghost:Destroy()
		ghost = nil
	end
	if marker then
		marker:Destroy()
		marker = nil
	end
end

local function fits(p: Pick): boolean
	local v = view()
	if v == nil then
		return false
	end
	return (Plot.fits(v.tier, placed(), p.id, p.x, p.z, p.rot, p.move))
end

-- Draw the ghost and its footprint (cyan where it fits, red where not) where the pick stands: a fresh model each time
-- (a handful of parts), one dynamic model with its footprint (a fence length: a bar along its grid line).
local function showGhost()
	local p = pick
	clearGhost()
	if p == nil or not p.set then
		return
	end
	local ox, oz = origin()
	local w, d = Plot.footprint(p.id, p.rot)
	local cx, cz = ox + p.x + w / 2, oz + p.z + d / 2
	local lvl = 1
	if p.move then
		local q = placed()[p.move]
		lvl = if q then q.lvl else 1
	end
	local m = DecorModels.build(p.id, CFrame.new(cx, Street.LAWN_Y, cz) * CFrame.Angles(0, math.rad(p.rot), 0), lvl)
	for _, part in m:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanQuery = false
			part.CanCollide = false
		end
	end
	-- the footprint: a raised neon frame round it (cyan where it fits, red where not), just over the grass
	local ok = fits(p)
	local color = if ok then "screen_on" else "berry_red"
	local y0, y1 = Street.LAWN_Y, 0.375
	local h = y1 - y0
	local frame = Blocks.model(m, "Footprint")
	local ww, dd = math.max(w, 0.25), math.max(d, 0.25)
	for _, e in { { 0, -dd / 2, ww, 0.25 }, { 0, dd / 2, ww, 0.25 }, { -ww / 2, 0, 0.25, dd }, { ww / 2, 0, 0.25, dd } } do
		Blocks.part(frame, { size = Vector3.new(e[3], h, e[4]), cf = CFrame.new(cx + e[1], (y0 + y1) / 2, cz + e[2]), color = color, name = "Edge", neon = true, collide = false, query = false })
	end
	marker = frame:FindFirstChildWhichIsA("BasePart")
	m.Name = "Ghost"
	m.Parent = workspace:FindFirstChild("PixelDynamic") or workspace
	ghost = m
	PixelRenderer.registerDynamic(m)
end

------------------------------------------------------------------ drawing paths, water and fences
local function drawing(): boolean
	local p = pick
	return p ~= nil and p.move == nil and Plot.isDrawn(p.id)
end

local function fenceDraw(): boolean
	local p = pick
	return p ~= nil and Plot.isFence(p.id)
end

local function clearDrawGhost()
	if drawGhost then
		PixelRenderer.unregisterDynamic(drawGhost)
		drawGhost:Destroy()
		drawGhost = nil
	end
end

local function key(c: { number }): string
	return if c[3] then c[1] .. "," .. c[2] .. "," .. c[3] else c[1] .. "," .. c[2]
end

-- The tile on a cell (its index), of a kind ("path", "water" or nil for either), and the tiles covering it.
local function tileAt(c: { number }, kind: string?): number?
	for i, q in placed() do
		local d = Buildings.byId[q.id]
		if d and (d.kind == "path" or d.kind == "water") and (kind == nil or d.kind == kind) and q.x == c[1] and q.z == c[2] then
			return i
		end
	end
	return nil
end
local function tilesOn(c: { number }, kind: string?): number
	local n = 0
	for _, q in placed() do
		local d = Buildings.byId[q.id]
		if d and (d.kind == "path" or d.kind == "water") and (kind == nil or d.kind == kind) then
			local r = Plot.rect(q.id, q.x, q.z, q.rot)
			if c[1] < r.x1 and c[1] + Plot.PATH_STEP > r.x0 and c[2] < r.z1 and c[2] + Plot.PATH_STEP > r.z0 then
				n += 1
			end
		end
	end
	return n
end
-- The fence length on an edge {x, z, rot} (its index).
local function fenceAt(e: { number }): number?
	for i, q in placed() do
		if Plot.isFence(q.id) and q.x == e[1] and q.z == e[2] and q.rot % 180 == e[3] % 180 then
			return i
		end
	end
	return nil
end

-- What the stroke would do, cell by cell (or edge by edge): "lay" (one goes down), "swap" (one of another look is
-- swapped for it), "lift" (Erase: one comes up) or "no" (it can't: taken, off the grass, no room or not enough wood);
-- and how many change and what they cost.
local function strokePlan(cells: { { number } }): ({ string }, number, number)
	local v = view()
	local p = pick
	local out: { string } = {}
	if v == nil or p == nil then
		return out, 0, 0
	end
	local def = Buildings.byId[p.id]
	if def == nil then
		return out, 0, 0
	end
	local fence = def.kind == "fence"
	local used = 0
	for _, q in v.pieces do
		if Plot.group(q.id) == Plot.group(p.id) then
			used += 1
		end
	end
	local most = Plot.groupLimit(Plot.group(p.id), v.tier)
	local wood = v.wood
	local n, cost = 0, 0
	for _, c in cells do
		if draw.erase then
			local hit = if fence then fenceAt(c) ~= nil else tilesOn(c, def.kind) > 0
			table.insert(out, if hit then "lift" else "no")
			if hit then
				n += 1
			end
			continue
		end
		local old = if fence then fenceAt(c) else tileAt(c, def.kind)
		local oq = if old then v.pieces[old] else nil
		if oq and oq.id == p.id then
			table.insert(out, "no")
		elseif oq and (fence or oq.rot == 0) then
			local od = Buildings.byId[oq.id]
			local price = def.wood - (if od then math.floor(od.wood * Tuning.Refund) else 0)
			if wood >= price then
				wood -= price
				cost += math.max(0, price)
				n += 1
				table.insert(out, "swap")
			else
				table.insert(out, "no")
			end
		else
			local k = key(c)
			local ok = draw.memo[k]
			if ok == nil then
				ok = (Plot.fits(v.tier, v.pieces, p.id, c[1], c[2], if fence then c[3] else 0))
				draw.memo[k] = ok
			end
			if ok and used < most and wood >= def.wood then
				used += 1
				wood -= def.wood
				cost += def.wood
				n += 1
				table.insert(out, "lay")
			else
				table.insert(out, "no")
			end
		end
	end
	return out, n, cost
end

-- The stroke's markers: a flat plate a cell, or a bar along an edge, just over the grass.
local function showDrawGhost(cells: { { number } })
	clearDrawGhost()
	local label = if tray then (tray :: Frame):FindFirstChild("Stroke", true) else nil
	if #cells == 0 then
		if label and label:IsA("TextLabel") then
			UIKit.setText(label, "")
		end
		return
	end
	local plan, n, cost = strokePlan(cells)
	local fence = fenceDraw()
	if label and label:IsA("TextLabel") and #cells > 1 then
		local what = if fence then "length" else "tile"
		UIKit.setText(label, if draw.erase then string.format("%d to take up", n) else string.format("%d %s%s, %s wood", n, what, if n == 1 then "" else "s", Numbers.coins(cost)))
	end
	local ox, oz = origin()
	local m = Blocks.model(nil, "DrawGhost")
	for k, c in cells do
		local what = plan[k]
		local color = if what == "lay" then "screen_on" elseif what == "swap" then "yellow" elseif what == "lift" then "orange" else "berry_red"
		local cf, size
		if fence then
			if c[3] == 90 then
				cf, size = CFrame.new(ox + c[1], Street.LAWN_Y + 0.35, oz + c[2] + 1), Vector3.new(0.25, 0.25, 1.75)
			else
				cf, size = CFrame.new(ox + c[1] + 1, Street.LAWN_Y + 0.35, oz + c[2]), Vector3.new(1.75, 0.25, 0.25)
			end
		else
			cf, size = CFrame.new(ox + c[1] + 1, Street.LAWN_Y + 0.2, oz + c[2] + 1), Vector3.new(1.75, 0.125, 1.75)
		end
		Blocks.part(m, { size = size, cf = cf, color = color, neon = true, collide = false, query = false, name = "Cell" })
	end
	m.Parent = workspace:FindFirstChild("PixelDynamic") or workspace
	drawGhost = m
	PixelRenderer.registerDynamic(m)
end

local function lawnAt(pos: Vector2): Vector3?
	local o, dir = PixelRenderer.screenRay(pos)
	if math.abs(dir.Y) < 1e-6 then
		return nil
	end
	local t = (Street.LAWN_Y - o.Y) / dir.Y
	if t < 0 then
		return nil
	end
	return o + dir * t
end

-- The 2-stud cell (a tile's north-west corner) or the grid corner (a fence's, the nearest even studs) under a screen
-- point, plot-local; nil off the lawn plane.
local function drawCellAt(pos: Vector2): { number }?
	local hit = lawnAt(pos)
	if hit == nil then
		return nil
	end
	local ox, oz = origin()
	local step = Plot.PATH_STEP
	if fenceDraw() then
		return { math.floor((hit.X - ox) / step + 0.5) * step, math.floor((hit.Z - oz) / step + 0.5) * step }
	end
	return { math.floor((hit.X - ox) / step) * step, math.floor((hit.Z - oz) / step) * step }
end

local function addCell(c: { number })
	local k = key(c)
	if draw.seen[k] or #draw.cells >= DRAW_MOST then
		return
	end
	draw.seen[k] = true
	table.insert(draw.cells, c)
end

-- The fence lengths along a straight run of the grid from corner a to corner b (along x, or along z).
local function addRun(a: { number }, b: { number })
	local step = Plot.PATH_STEP
	if a[2] == b[2] then
		for x = math.min(a[1], b[1]), math.max(a[1], b[1]) - step, step do
			addCell({ x, a[2], 0 })
		end
	elseif a[1] == b[1] then
		for z = math.min(a[2], b[2]), math.max(a[2], b[2]) - step, step do
			addCell({ a[1], z, 90 })
		end
	end
end

-- The stroke reaches cell (or corner) c. Tiles: a line joins every cell on the way from the last one; a box is the cells
-- between its first corner and c. Fences: a line goes along x then z from the last corner; a box runs round the
-- rectangle between its first corner and c.
local function strokeTo(c: { number })
	local step = Plot.PATH_STEP
	if fenceDraw() then
		if draw.box then
			local a = draw.start or c
			draw.cells, draw.seen = {}, {}
			addRun(a, { c[1], a[2] })
			addRun({ c[1], a[2] }, c)
			addRun(a, { a[1], c[2] })
			addRun({ a[1], c[2] }, c)
		else
			local l = draw.last or c
			addRun(l, { c[1], l[2] })
			addRun({ c[1], l[2] }, c)
		end
	elseif draw.box then
		local a = draw.start or c
		draw.cells, draw.seen = {}, {}
		local x0, x1 = math.min(a[1], c[1]), math.max(a[1], c[1])
		local z0, z1 = math.min(a[2], c[2]), math.max(a[2], c[2])
		for z = z0, z1, step do
			for x = x0, x1, step do
				addCell({ x, z })
			end
		end
	else
		local l = draw.last or c
		local nx, nz = math.abs(c[1] - l[1]) / step, math.abs(c[2] - l[2]) / step
		local n = math.max(nx, nz)
		for k = 0, n do
			local f = if n == 0 then 1 else k / n
			local x = math.floor((l[1] + (c[1] - l[1]) * f) / step + 0.5) * step
			local z = math.floor((l[2] + (c[2] - l[2]) * f) / step + 0.5) * step
			addCell({ x, z })
		end
	end
	draw.last = c
	showDrawGhost(draw.cells)
end

local rebuild: () -> () = function() end

-- The stroke let go: its cells or edges go to the server (in parts), and the island's markers go.
local function finishStroke()
	local cells = draw.cells
	local p = pick
	draw.start, draw.last, draw.cells, draw.seen, draw.memo = nil, nil, {}, {}, {}
	clearDrawGhost()
	if p == nil or #cells == 0 then
		return
	end
	local def = Buildings.byId[p.id]
	local fence = Plot.isFence(p.id)
	local plan = strokePlan(cells)
	local send: { { number } } = {}
	for k, c in cells do
		if plan[k] ~= "no" then
			table.insert(send, c)
		end
	end
	if #send == 0 then
		Audio.play("deny")
		local what = if fence then "fence" elseif def and def.kind == "water" then "water" else "path"
		UIKit.notice(if draw.erase then string.format("No %s there to take up.", what) else if fence then "No fence fits there." else "No tile fits there.", UIKit.color("bad"), 2)
		return
	end
	local changed, lifted = 0, 0
	local done: { { number } } = {}
	for i = 1, #send, Plot.PAINT_MAX do
		local part = table.move(send, i, math.min(#send, i + Plot.PAINT_MAX - 1), 1, {})
		local res
		if fence then
			res = if draw.erase then StateClient.request("plot.unfence", { edges = Plot.edgeString(part) }) else StateClient.request("plot.fence", { id = p.id, edges = Plot.edgeString(part) })
		else
			res = if draw.erase then StateClient.request("plot.unpaint", { cells = Plot.cellString(part), kind = if def then def.kind else "all" }) else StateClient.request("plot.paint", { id = p.id, cells = Plot.cellString(part) })
		end
		if res.ok and type(res.data) == "table" then
			changed += (tonumber(res.data.placed) or 0) + (tonumber(res.data.swapped) or 0)
			lifted += tonumber(res.data.removed) or 0
			table.move(part, 1, #part, #done + 1, done)
		elseif not res.ok then
			UIKit.notice(Words.errText(res.err), UIKit.color("bad"))
			break
		end
	end
	if changed > 0 or lifted > 0 then
		BuildFx.stroke(myPlot(), p.id, done, fence, lifted > 0)
	end
	task.defer(rebuild)
end

------------------------------------------------------------------ the tray

-- A price: its wood (and shells, when a piece asks for them: none do since wood pays for building) with their small
-- icons from x (red when there is not enough); returns the end x.
local function price(parent: Instance, x: number, y: number, shells: number, wood: number, v: Types.ClientView, z: number?): number
	if shells > 0 then
		PixelSprites.image(parent, "mini_shell", UDim2.fromOffset(x, y), z or 4)
		local t = Numbers.coins(shells)
		UIKit.text(parent, t, UDim2.fromOffset(UIKit.textWidth(t) + 2, 10), UDim2.fromOffset(x + 11, y + 1), { color = if v.shells >= shells then UIKit.color("text") else UIKit.color("bad"), z = z or 4, name = "Shells" })
		x += 13 + UIKit.textWidth(t) + 2
	end
	if wood > 0 or shells == 0 then
		PixelSprites.image(parent, "mini_wood", UDim2.fromOffset(x, y), z or 4)
		local tw = Numbers.coins(wood)
		UIKit.text(parent, tw, UDim2.fromOffset(UIKit.textWidth(tw) + 2, 10), UDim2.fromOffset(x + 11, y + 1), { color = if v.wood >= wood then UIKit.color("text") else UIKit.color("bad"), z = z or 4, name = "Wood" })
		x += 13 + UIKit.textWidth(tw) + 2
	end
	return x
end

-- What a piece is, in a line: its blurb, what it makes, its room and comfort, its charm, its size.
local function about(def: Buildings.BuildingDef, lvl: number?): string
	local say = def.blurb
	if def.rate > 0 then
		say = string.format("%s %s a minute for each common driftling working here.", say, (Numbers.perMin(def.rate * Tuning.PalWork * (Tuning.UpgradeMult[lvl or 1] or 1) * 60 / Tuning.TurnSeconds):gsub("/min", "")))
	end
	if def.slots > 0 then
		local c = def.comfort + (Tuning.ComfortLvl[lvl or 1] or 0)
		say = string.format("%s Room for %d.%s", say, def.slots, if c > 0 then string.format(" Comfort +%d%%.", math.round(c * 100)) else "")
	end
	if def.charm >= 1 then
		say ..= string.format(" Charm +%d.", math.floor(def.charm))
	end
	if def.water == "on" then
		say ..= " Goes on water."
	elseif def.water == "over" then
		say ..= " Goes over water."
	end
	return (string.gsub(say, "^%s+", ""))
end

local function closeTip()
	if tip then
		tip:Destroy()
		tip = nil
	end
end

-- A card's tooltip over the tray (a mouse over it): its name, what it is, its size, the island level it opens at.
local function showTip(card: GuiObject, def: Buildings.BuildingDef, v: Types.ClientView)
	closeTip()
	local canvas = UIKit.canvas("Hud")
	local s = UIKit.size("Hud")
	local w = 172
	local text = about(def)
	local nl = UIKit.lines(text, w - 8)
	local h = 26 + nl * 10 + (if def.tier > v.tier then 10 else 0)
	local at = card.AbsolutePosition - UIKit.canvasOrigin("Hud")
	local x = math.clamp(math.floor(at.X + CARD_W / 2 - w / 2), 4, s.X - w - 4)
	local f = UIKit.plate(canvas, UDim2.fromOffset(w, h), UDim2.fromOffset(x, s.Y - TRAY_H - 8 - h), UIKit.color("plate"), 0.03, 2, { bevel = true, shadow = true })
	f.Name = "BuildTip"
	f.ZIndex = 20
	UIKit.text(f, def.name, UDim2.fromOffset(w - 8, 10), UDim2.fromOffset(4, 3), { color = UIKit.color("accent"), z = 22, name = "TipName" })
	local size = if def.kind == "fence" then "2-stud lengths" elseif def.kind == "path" or def.kind == "water" then "2 x 2 tiles" else string.format("%d x %d", def.w, def.d)
	UIKit.text(f, size, UDim2.fromOffset(60, 10), UDim2.new(1, -64, 0, 3), { x = "right", color = UIKit.color("text_dim"), z = 22 })
	UIKit.text(f, text, UDim2.fromOffset(w - 8, nl * 10), UDim2.fromOffset(4, 13), { color = UIKit.color("text"), z = 22, wrap = true, name = "TipAbout" })
	if def.tier > v.tier then
		UIKit.text(f, string.format("Opens at island level %d.", def.tier), UDim2.fromOffset(w - 8, 10), UDim2.fromOffset(4, 13 + nl * 10), { color = UIKit.color("orange"), z = 22, name = "TipLocked" })
	end
	price(f, 4, h - 12, def.shells, def.wood, v, 22)
	tip = f
end

-- Replacing a placed piece (GAME_DESIGN 4.1): the others of its row open at the tier, each with its picture, what it
-- adds and what it costs after the old one's refund; a tap replaces it where it stands.
local function replaceBar(f: Frame, p: Pick, v: Types.ClientView, q: Types.Piece)
	local old = Buildings.byId[q.id]
	UIKit.button(f, "Back", UDim2.fromOffset(40, 13), UDim2.fromOffset(4, 2), function()
		local cur = pick
		if cur then
			cur.replace = nil
			rebuild()
		end
	end, { name = "ReplaceBack", color = UIKit.color("plate_light") })
	UIKit.text(f, "Replace the " .. (if old then old.name else q.id) .. " with:", UDim2.fromOffset(240, 13), UDim2.fromOffset(48, 2), { color = UIKit.color("accent"), name = "ReplaceWhat" })
	local list = UIKit.scroll(f, UDim2.new(1, -8, 0, CARD_H + 14), UDim2.fromOffset(4, 18))
	list.ScrollingDirection = Enum.ScrollingDirection.X
	list.AutomaticCanvasSize = Enum.AutomaticSize.X
	UIKit.hlist(list, 3)
	for k, id in Plot.replacements(q, v.tier) do
		local d = Buildings.byId[id]
		local cost = Plot.replaceCost(q, id)
		if d == nil or cost == nil then
			continue
		end
		local afford = v.shells >= cost.shells and v.wood >= cost.wood
		local card = UIKit.plate(list, UDim2.fromOffset(88, CARD_H + 10), nil, UIKit.color("plate_light"), 0, 2, { bevel = true })
		card.Name = "Swap_" .. id
		card.LayoutOrder = k
		picture(card, id, UDim2.fromOffset(3, 3), 4)
		local what = if d.slots > 0 then string.format("Room %d", d.slots) elseif d.charm >= 1 then string.format("Charm +%d", math.floor(d.charm)) else ""
		UIKit.text(card, d.name, UDim2.fromOffset(58, 10), UDim2.fromOffset(29, 3), { color = UIKit.color("text"), z = 4 })
		UIKit.text(card, what, UDim2.fromOffset(58, 10), UDim2.fromOffset(29, 14), { color = UIKit.color("text_dim"), z = 4 })
		local b = UIKit.button(card, "", UDim2.fromOffset(84, 14), UDim2.fromOffset(2, CARD_H - 6), function()
			local cur = pick
			if cur == nil or cur.move == nil then
				return
			end
			local res = ask("plot.replace", { i = cur.move, id = id })
			if res.ok then
				Audio.play("level_up")
				UIKit.notice(string.format("The %s is a %s now.", if old then old.name else "piece", d.name), UIKit.color("good"))
				BuildFx.drop(myPlot(), q.uid, id, q.x, q.z, q.rot, 1)
				pick = nil
				clearGhost()
				task.defer(rebuild)
			end
		end, { name = "SwapTo_" .. id, color = if afford then UIKit.color("button_ok") else nil })
		price(b, 3, 2, cost.shells, cost.wood, v, 6)
	end
end

-- The info plate under the action bars: the piece's picture, its name, what it is, its price (or the stroke's).
local function infoPlate(f: Frame, p: Pick, v: Types.ClientView, title: string, say: string, showPrice: boolean)
	local def = Buildings.byId[p.id]
	local info = UIKit.plate(f, UDim2.new(1, -8, 0, TRAY_H - 24), UDim2.fromOffset(4, 18), UIKit.color("plate_light"), 0, 2, { bevel = true })
	info.Name = "Info"
	picture(info, p.id, UDim2.fromOffset(4, 4), 4)
	local w = f.Size.X.Offset - 8
	UIKit.text(info, title, UDim2.new(1, -40, 0, 10), UDim2.fromOffset(32, 3), { color = UIKit.color("accent"), z = 4, name = "What" })
	local tw = w - 40 - (if showPrice then 96 else 0)
	local nl = math.min(4, UIKit.lines(say, tw))
	UIKit.text(info, say, UDim2.fromOffset(tw, nl * 10), UDim2.fromOffset(32, 14), { color = UIKit.color("text_dim"), z = 4, wrap = true, name = "Blurb" })
	if def and showPrice then
		price(info, math.max(4, w - 92), 3, def.shells, def.wood, v)
	end
	-- (with a keyboard: its keys, along the bottom)
	if UserInputService.KeyboardEnabled then
		local keys = if drawing() then "Esc stops drawing." elseif p.move then "R turns it. C copies it. X clears it away. Esc puts it back." else "R turns it. E puts it down. Esc stops."
		UIKit.text(info, keys, UDim2.new(1, -40, 0, 10), UDim2.new(0, 32, 1, -12), { color = UIKit.color("text_dim"), z = 4, name = "Keys" })
	end
	return info
end

-- Drawing paths, water or fences: the tools, what the stroke does and its price.
local function drawBar(f: Frame, p: Pick, v: Types.ClientView)
	local def = Buildings.byId[p.id]
	local x = 4
	local function tool(text: string, on: boolean, click: () -> (), name: string)
		local w = UIKit.buttonWidth(text, 5)
		UIKit.button(f, text, UDim2.fromOffset(w, 13), UDim2.fromOffset(x, 2), function()
			Audio.play("flip")
			click()
			rebuild()
		end, { color = if on then UIKit.color("accent") else UIKit.color("plate_light"), name = name })
		x += w + 3
	end
	local line = not draw.box and not draw.erase and not draw.look
	tool("Line", line, function()
		draw.box, draw.erase, draw.look = false, false, false
	end, "DrawLine")
	tool("Box", draw.box and not draw.look, function()
		draw.box, draw.look = true, false
	end, "DrawBox")
	tool("Erase", draw.erase and not draw.look, function()
		draw.erase, draw.look = not draw.erase, false
	end, "DrawErase")
	tool("Look around", draw.look, function()
		draw.look = not draw.look
	end, "DrawLook")
	UIKit.button(f, "Cancel", UDim2.fromOffset(UIKit.buttonWidth("Cancel", 5), 13), UDim2.fromOffset(x, 2), function()
		pick = nil
		clearDrawGhost()
		rebuild()
	end, { color = UIKit.color("plate_light"), name = "Cancel" })
	local fence = def ~= nil and def.kind == "fence"
	local noun = if fence then "fences" elseif def and def.kind == "water" then "water" else "paths"
	local say
	if draw.look then
		say = "Drag to look around. Tap Look around again to draw."
	elseif draw.erase then
		say = if draw.box then string.format("Drag a box over the %s to take them up. Half their price comes back.", noun) else string.format("Drag along the %s to take them up. Half their price comes back.", noun)
	elseif fence then
		say = if draw.box then "Drag a box to run a fence all the way round it." else "Drag along the grid lines to put up a fence."
	elseif def and def.kind == "water" then
		say = if draw.box then "Drag a box to fill it with water. Bridges and lily pads go on top." else "Drag across the grass to dig a river."
	else
		say = if draw.box then "Drag a box across the grass to fill it with tiles." else "Drag across the grass to lay a line of tiles."
	end
	if def and def.blurb ~= "" and not draw.erase and not draw.look then
		say = def.blurb .. " " .. say
	end
	local info = infoPlate(f, p, v, (if draw.erase then "Taking up " .. noun else "Drawing: " .. (if def then def.name else p.id)), say, def ~= nil and not draw.erase)
	-- the stroke under way: how many and what they cost (set as it changes: showDrawGhost)
	UIKit.text(info, "", UDim2.fromOffset(150, 10), UDim2.new(1, -154, 0, 15), { x = "right", color = UIKit.color("accent"), z = 4, name = "Stroke" })
end

local function storePicked()
	local cur = pick
	if cur and cur.move then
		local q = placed()[cur.move]
		if q == nil or Plot.isFixed(q.id) then
			Audio.play("deny")
			return
		end
		local res = ask("plot.store", { i = cur.move })
		if res.ok then
			BuildFx.cleared(myPlot(), q.id, q.x, q.z, q.rot)
			pick = nil
			clearGhost()
			task.defer(rebuild)
		end
	end
end

-- Another of the picked piece (a copy of one standing, turned the same way).
local function copyPicked()
	local cur = pick
	if cur and cur.move then
		local q = placed()[cur.move]
		if q == nil or Plot.isFixed(q.id) then
			Audio.play("deny")
			return
		end
		Audio.play("flip")
		pick = { id = q.id, rot = q.rot, move = nil, x = q.x, z = q.z, set = false }
		clearGhost()
		UIKit.notice(if Plot.isDrawn(q.id) then "Drag to draw more of it." else "Tap the grass where the copy should go.", UIKit.color("text_dim"), 2.5)
		rebuild()
	end
end

local function rotatePicked()
	local q = pick
	if q and not drawing() then
		-- (a fence length runs east or south)
		q.rot = if Plot.isFence(q.id) then (q.rot + 90) % 180 else (q.rot + 90) % 360
		Audio.play("flip")
		showGhost()
		rebuild()
	end
end

local function actionBar(f: Frame, p: Pick, v: Types.ClientView)
	if drawing() then
		drawBar(f, p, v)
		return
	end
	local def = Buildings.byId[p.id]
	local placedQ = if p.move then placed()[p.move] else nil
	if p.replace and placedQ then
		replaceBar(f, p, v, placedQ)
		return
	end
	local x = 4
	local function btn(text: string, color: Color3?, enabled: boolean, click: () -> (), name: string)
		local w = UIKit.buttonWidth(text, 5)
		UIKit.button(f, text, UDim2.fromOffset(w, 13), UDim2.fromOffset(x, 2), click, { color = color, enabled = enabled, name = name })
		x += w + 3
	end
	btn("Rotate", nil, true, rotatePicked, "Rotate")
	btn(if p.move then "Move here" else "Place", UIKit.color("button_ok"), p.set and fits(p), function()
		BuildUI.confirm()
	end, "Place")
	local q = placedQ
	if q then
		if not Plot.isFixed(q.id) then
			btn("Copy", UIKit.color("plate_light"), true, copyPicked, "Copy")
		end
		if #Plot.replacements(q, v.tier) > 0 then
			btn("Replace", UIKit.color("pink"), true, function()
				local cur = pick
				if cur and cur.move then
					cur.replace = true
					Audio.play("flip")
					rebuild()
				end
			end, "Replace")
		end
		btn("Clear away", UIKit.color("button_warn"), not Plot.isFixed(q.id), storePicked, "Store")
	end
	btn("Cancel", UIKit.color("plate_light"), true, function()
		pick = nil
		clearGhost()
		rebuild()
	end, "Cancel")
	-- what it is and costs
	local name = (if def then def.name else p.id) .. (if q and q.lvl > 1 then " Lv" .. q.lvl else "")
	infoPlate(f, p, v, (if p.move then "Moving: " else "Placing: ") .. name, if def then about(def, if q then q.lvl else 1) else "", q == nil and def ~= nil)
end

-- The tab's pieces in the chosen row: unlocked first, cheapest first; the locked ones after, by the level they open at.
local function matches(d: Buildings.BuildingDef, q: string): boolean
	return string.find(string.lower(d.name), q, 1, true) ~= nil or string.find(d.sub, q, 1, true) ~= nil or string.find(d.tab, q, 1, true) ~= nil
end

local function listFor(v: Types.ClientView): { Buildings.BuildingDef }
	local row = chip[tab] or ""
	local out: { Buildings.BuildingDef } = {}
	for _, d in Buildings.list do
		if d.kind == "tree" then
			continue
		end
		if (query ~= "" and matches(d, query)) or (query == "" and d.tab == tab and (row == "" or d.sub == row)) then
			table.insert(out, d)
		end
	end
	table.sort(out, function(a, b)
		local la, lb = a.tier > v.tier, b.tier > v.tier
		if la ~= lb then
			return not la
		end
		if la and a.tier ~= b.tier then
			return a.tier < b.tier
		end
		if a.wood ~= b.wood then
			return a.wood < b.wood
		end
		return a.id < b.id
	end)
	return out
end

local function cards(list: ScrollingFrame, v: Types.ClientView)
	UIKit.hlist(list, 3)
	local hutsFull = Plot.huts(v.pieces) >= Plot.hutLimit(v.tier)
	for k, def in listFor(v) do
		local locked = def.tier > v.tier
		-- (a hut past the island's huts' limit: a bigger hut can still replace a small one)
		local noRoom = def.kind == "nest" and hutsFull
		local afford = v.shells >= def.shells and v.wood >= def.wood
		local picked = pick ~= nil and pick.id == def.id
		local card = UIKit.plate(list, UDim2.fromOffset(CARD_W, CARD_H), nil, if picked then UIKit.color("accent") else UIKit.color("plate_light"), 0, 2, { bevel = true })
		card.Name = "Card_" .. def.id
		card.LayoutOrder = k
		local goal = tutGoal(v)
		if goal and goal.id == def.id and not locked then
			card:SetAttribute("TutGoal", true)
			goalCard = card
		end
		local b = UIKit.button(card, "", UDim2.fromOffset(CARD_W - 4, CARD_H - 4), UDim2.fromOffset(2, 2), function()
			if locked then
				UIKit.notice(string.format("Expand your island to level %d to build this.", def.tier), UIKit.color("bad"))
				Audio.play("deny")
				return
			end
			if noRoom then
				UIKit.notice(Words.errText("huts"), UIKit.color("bad"))
				Audio.play("deny")
				return
			end
			closeTip()
			pick = { id = def.id, rot = 0, move = nil, x = 0, z = 0, set = false }
			draw.erase, draw.look = false, false
			clearGhost()
			clearDrawGhost()
			Audio.play("flip")
			local say
			if def.kind == "fence" then
				say = "Drag along the grid lines to put up a fence."
			elseif def.kind == "water" then
				say = "Drag across the grass to dig a river or a pond."
			elseif def.kind == "path" then
				say = "Drag across the grass to lay tiles."
			elseif def.water == "on" then
				say = "Tap the water where it should float."
			else
				say = "Tap the grass where it should go."
			end
			UIKit.notice(say, UIKit.color("text_dim"), 2.5)
			rebuild()
		end, {
			name = "Buy_" .. def.id,
			color = if locked or noRoom then UIKit.color("button_off") elseif picked then UIKit.color("accent") elseif afford then UIKit.color("button_ok") else UIKit.color("plate_light"),
		})
		picture(b, def.id, UDim2.fromOffset(math.floor((CARD_W - 4 - PIC) / 2), 1), 6)
		if locked then
			UIKit.text(b, string.format("Lv%d", def.tier), UDim2.fromOffset(CARD_W - 4, 10), UDim2.fromOffset(0, PIC + 3), { x = "center", color = UIKit.color("text_dim"), z = 7, name = "Lock" })
		elseif noRoom then
			UIKit.text(b, "No room", UDim2.fromOffset(CARD_W - 4, 10), UDim2.fromOffset(0, PIC + 3), { x = "center", color = UIKit.color("text_dim"), z = 7, name = "Lock" })
		else
			local t = Numbers.coins(def.wood)
			local w = UIKit.textWidth(t) + 11
			local px = math.max(0, math.floor((CARD_W - 4 - w) / 2))
			PixelSprites.image(b, "mini_wood", UDim2.fromOffset(px, PIC + 3), 7)
			UIKit.text(b, t, UDim2.fromOffset(UIKit.textWidth(t) + 2, 10), UDim2.fromOffset(px + 11, PIC + 4), { color = if v.wood >= def.wood then UIKit.color("text") else UIKit.color("bad"), z = 7, name = "Wood" })
		end
		b.MouseEnter:Connect(function()
			showTip(card, def, v)
		end)
		b.MouseLeave:Connect(closeTip)
	end
end

-- The count shown for the tab: its pieces against its limit (huts, tiles and fences have their own).
local function countFor(v: Types.ClientView): (number, number)
	if tab == "nest" then
		return Plot.huts(v.pieces), Plot.hutLimit(v.tier)
	end
	local group = if tab == "path" or tab == "water" then "tile" elseif tab == "fence" then "fence" else "piece"
	local n = 0
	for _, q in v.pieces do
		if Plot.group(q.id) == group then
			n += 1
		end
	end
	return n, Plot.groupLimit(group, v.tier)
end

local function expandButton(f: Frame, v: Types.ClientView)
	local cost = Island.expandCost(v.tier)
	UIKit.button(f, if cost then "Expand" else "Island max", UDim2.fromOffset(54, 13), UDim2.new(1, -102, 0, 2), function()
		local res = ask("island.expand", {})
		if res.ok then
			-- cheer when the bigger island is on screen (the server swaps in the island it built ahead; the filter
			-- re-bakes it in a few frames), at most a moment later
			local moved = if type(res.data) == "table" then tonumber(res.data.moved) or 0 else 0
			-- (the island it grew into: the server's answer says, the view may still be the old one when this runs)
			local grown = if type(res.data) == "table" then tonumber(res.data.tier) else nil
			local cheered = false
			local function cheer()
				if cheered then
					return
				end
				cheered = true
				Audio.play("grow")
				local plan = Office.plan(grown or v.tier + 1)
				UIKit.notice(if moved > 0 then string.format("Your island grew into %s. %d building%s had to move.", plan.name, moved, if moved == 1 then "" else "s") else string.format("Your island grew into %s. There's more to build now.", plan.name), UIKit.color("good"), 4)
			end
			PixelRenderer.afterBake(cheer)
			task.delay(1.5, cheer)
		end
	end, { name = "Expand", color = UIKit.color("button_warn"), enabled = cost ~= nil and v.shells >= cost.shells and v.wood >= cost.wood })
	if cost then
		local pf = Instance.new("Frame")
		pf.Name = "ExpandCost"
		pf.BackgroundTransparency = 1
		pf.Size = UDim2.fromOffset(100, 11)
		pf.Position = UDim2.new(1, -102, 0, 17)
		pf.Parent = f
		price(pf, 0, 0, cost.shells, cost.wood, v)
	end
end

-- The search box: a TextBox under the pixel font's copy of its words, a clear mark while there are any.
local function searchField(parent: Frame, w: number, pos: UDim2): Frame
	local f = search
	if f == nil then
		local nf = UIKit.plate(nil, UDim2.fromOffset(w, 12), pos, UIKit.color("plate_light"), 0, 2, { bevel = true })
		nf.Name = "BuildSearch"
		local box = Instance.new("TextBox")
		box.Name = "Box"
		box.Text = ""
		box.PlaceholderText = ""
		box.ClearTextOnFocus = false
		box.MultiLine = false
		box.TextTransparency = 1
		box.TextStrokeTransparency = 1
		box.TextSize = 1
		box.BackgroundTransparency = 1
		box.BorderSizePixel = 0
		box.Size = UDim2.fromScale(1, 1)
		box.ZIndex = 8
		box.Parent = nf
		local mirror = UIKit.text(nf, "Search", UDim2.fromOffset(w - 16, 10), UDim2.fromOffset(4, 1), { color = UIKit.color("text_dim"), z = 7, name = "Query" })
		local clear = UIKit.button(nf, "x", UDim2.fromOffset(12, 10), UDim2.new(1, -13, 0, 1), function()
			box.Text = ""
		end, { name = "ClearSearch", color = UIKit.color("plate_light") })
		clear.Visible = false
		box:GetPropertyChangedSignal("Text"):Connect(function()
			local q = string.lower((string.gsub(box.Text, "^%s+", "")))
			clear.Visible = q ~= ""
			UIKit.setText(mirror, if q ~= "" then box.Text else "Search")
			UIKit.setTextColor(mirror, if q ~= "" then UIKit.color("text") else UIKit.color("text_dim"))
			if q ~= query then
				query = q
				cardScroll = 0
				rebuild()
			end
		end)
		search = nf
		f = nf
	end
	local sf = f :: Frame
	sf.Position = pos
	sf.Size = UDim2.fromOffset(w, 12)
	sf.Parent = parent
	return sf
end

rebuild = function()
	goalCard, goalTab = nil, nil
	-- (the search box stays: it moves to the new tray)
	if search then
		(search :: Frame).Parent = nil
	end
	closeTip()
	if tray then
		local list = (tray :: Frame):FindFirstChild("Cards")
		if list and list:IsA("ScrollingFrame") then
			cardScroll = list.CanvasPosition.X
		end
		tray:Destroy()
		tray = nil
	end
	if not open then
		return
	end
	local v = view()
	if v == nil then
		return
	end
	if followTut(v) and tutSeen ~= nil then
		Audio.play("flip")
	end
	local canvas = UIKit.canvas("Hud")
	local s = UIKit.size("Hud")
	-- a workbench of driftwood in a frame of planks (GAME_DESIGN 2: the island's looks), its tabs on a plank
	local f = UIKit.plate(canvas, UDim2.fromOffset(s.X - 16, TRAY_H), UDim2.new(0, 8, 1, -6), UIKit.color("plate"), 0.03, 3, { shadow = true, wood = 3 })
	f.AnchorPoint = Vector2.new(0, 1)
	f.Name = "BuildTray"
	UIKit.plank(f, 15, 3)
	local p = pick
	if p then
		actionBar(f, p, v)
	else
		-- the tabs (their icons alone on a narrow screen), the count, Expand
		local x = 4
		local wide = 0
		for _, t in TABS do
			wide += UIKit.buttonWidth(t.text, 5) + 13
		end
		local short = wide > s.X - 8 - 160
		for _, t in TABS do
			local w = if short then 16 else UIKit.buttonWidth(t.text, 5) + 11
			local b = UIKit.button(f, if short then "" else t.text, UDim2.fromOffset(w, 13), UDim2.fromOffset(x, 2), function()
				if tab ~= t.key then
					tab = t.key
					cardScroll = 0
					Audio.play("flip")
					rebuild()
				end
			end, { name = "Tab_" .. t.key, color = if tab == t.key then UIKit.color("accent") else UIKit.color("plate_light") })
			PixelSprites.image(b, "mini_" .. t.icon, UDim2.fromOffset(2, 1), 6)
			local goal = tutGoal(v)
			if goal and goal.tab == t.key and tab ~= t.key then
				goalTab = b
			end
			local l = b:FindFirstChildWhichIsA("TextLabel", true)
			if l and not short then
				l.Position = UDim2.fromOffset(6, 0)
			end
			x += w + 2
		end
		expandButton(f, v)
		local used, most = countFor(v)
		UIKit.text(f, string.format("%d/%d", used, most), UDim2.fromOffset(40, 13), UDim2.new(1, -146, 0, 2), { x = "right", color = if used >= most then UIKit.color("orange") else UIKit.color("text_dim"), name = "Count" })
		-- the tab's rows: chips (scrolling sideways when there are many)
		local rows: { { string } }? = CHIPS[tab]
		local sw = if s.X < 500 then 70 else 96
		searchField(f, sw, UDim2.new(1, -106 - sw, 0, 17))
		if query ~= "" then
			rows = nil
		end
		if rows then
			local cl = UIKit.scroll(f, UDim2.new(1, -112 - sw, 0, 13), UDim2.fromOffset(4, 17))
			cl.Name = "Chips"
			cl.ScrollingDirection = Enum.ScrollingDirection.X
			cl.AutomaticCanvasSize = Enum.AutomaticSize.X
			UIKit.hlist(cl, 2)
			for k, r in rows do
				local on = (chip[tab] or "") == r[1]
				local b = UIKit.button(cl, r[2], UDim2.fromOffset(UIKit.buttonWidth(r[2], 4), 12), nil, function()
					if (chip[tab] or "") ~= r[1] then
						chip[tab] = r[1]
						cardScroll = 0
						Audio.play("flip")
						rebuild()
					end
				end, { name = "Chip_" .. (if r[1] == "" then "all" else r[1]), color = if on then UIKit.color("accent") else UIKit.color("plate_light") })
				b.LayoutOrder = k
			end
		else
			local hint = if query ~= "" then string.format("Everything called \"%s\":", query) elseif tab == "path" then "Pick a path, then drag across the grass." elseif tab == "fence" then "Pick a fence, then drag along the grid lines." else "Pick a hut, then tap the grass."
			UIKit.text(f, hint, UDim2.new(1, -112 - sw, 0, 12), UDim2.fromOffset(6, 17), { color = UIKit.color("text_dim"), name = "TabHint" })
		end
	end
	UIKit.button(f, "Done", UDim2.fromOffset(40, 13), UDim2.new(1, -44, 0, 2), function()
		BuildUI.close()
	end, { color = UIKit.color("accent"), name = "BuildDone" })
	if p == nil then
		local list = UIKit.scroll(f, UDim2.new(1, -8, 0, CARD_H + 2), UDim2.fromOffset(4, 31))
		list.Name = "Cards"
		list.ScrollingDirection = Enum.ScrollingDirection.X
		list.AutomaticCanvasSize = Enum.AutomaticSize.X
		cards(list, v)
		local k = tab .. ":" .. (chip[tab] or "") .. ":" .. query
		if k == cardScrollKey then
			list.CanvasPosition = Vector2.new(cardScroll, 0)
		else
			cardScrollKey = k
			cardScroll = 0
		end
	end
	tray = f
end

------------------------------------------------------------------ pointer
-- The plot-local cell (footprint's north-west corner) under a screen point for a piece, or nil off the lawn plane. A
-- fence length snaps to the nearest grid corner (even studs).
local function cellAt(pos: Vector2, id: string, rot: number): (number?, number?)
	local hit = lawnAt(pos)
	if hit == nil then
		return nil, nil
	end
	local ox, oz = origin()
	if Plot.isFence(id) then
		local step = Plot.PATH_STEP
		local lx, lz = hit.X - ox - (if rot == 0 then 1 else 0), hit.Z - oz - (if rot == 90 then 1 else 0)
		return math.floor(lx / step + 0.5) * step, math.floor(lz / step + 0.5) * step
	end
	if Plot.isTile(id) then
		-- (a tile moved stays on the even studs)
		local step = Plot.PATH_STEP
		return math.floor((hit.X - ox) / step) * step, math.floor((hit.Z - oz) / step) * step
	end
	local w, d = Plot.footprint(id, rot)
	return math.floor(hit.X - ox - w / 2 + 0.5), math.floor(hit.Z - oz - d / 2 + 0.5)
end

-- The index of the own plot's piece under a screen point, if any.
local function pieceAt(pos: Vector2): number?
	local o, dir = PixelRenderer.screenRay(pos)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local plots = workspace:FindFirstChild("Plots")
	local plotModel = if plots then plots:FindFirstChild("Plot_" .. myPlot()) else nil
	local decor = if plotModel then plotModel:FindFirstChild("Decor", true) else nil
	if decor == nil then
		return nil
	end
	params.FilterDescendantsInstances = { decor }
	local hit = workspace:Raycast(o, dir, params)
	if hit == nil then
		return nil
	end
	local m: Instance? = hit.Instance
	while m and m.Parent ~= decor do
		m = m.Parent
	end
	if m == nil then
		return nil
	end
	local uid = tonumber(string.match(m.Name, "^(%d+):"))
	for i, q in placed() do
		if q.uid == uid then
			return i
		end
	end
	return nil
end

local function moveGhostTo(pos: Vector2): boolean
	local p = pick
	if p == nil then
		return false
	end
	local x, z = cellAt(pos, p.id, p.rot)
	if x == nil or z == nil then
		return false
	end
	local same = p.set and p.x == x and p.z == z
	p.x, p.z, p.set = x, z, true
	showGhost()
	return same
end

local function onTap(pos: Vector2, mouse: boolean)
	if pick then
		local same = moveGhostTo(pos)
		if same and mouse then
			BuildUI.confirm()
		else
			rebuild()
		end
		return
	end
	local i = pieceAt(pos)
	if i then
		local q = placed()[i]
		Audio.play("click")
		pick = { id = q.id, rot = q.rot, move = i, x = q.x, z = q.z, set = true }
		showGhost()
		rebuild()
	end
end

------------------------------------------------------------------ open, close, confirm
function BuildUI.confirm()
	local p = pick
	if p == nil or not p.set then
		return
	end
	local res
	local goal = tutGoal(view())
	local moving = p.move
	local lvl = 1
	local uid = 0
	if moving then
		local q = placed()[moving]
		if q then
			lvl, uid = q.lvl, q.uid
		end
		res = ask("plot.move", { i = moving, x = p.x, z = p.z, rot = p.rot })
	else
		res = ask("plot.place", { id = p.id, x = p.x, z = p.z, rot = p.rot })
		if res.ok and type(res.data) == "table" then
			uid = tonumber(res.data.uid) or 0
		end
	end
	if res.ok then
		-- (it drops in and lands with its dust, its sound and its charm)
		BuildFx.drop(myPlot(), uid, p.id, p.x, p.z, p.rot, lvl)
		-- (the tip's building placed: the tray goes on to the next tip's tab rather than offering another copy)
		if moving or (goal and goal.id == p.id) then
			pick = nil
			clearGhost()
		end
		-- placing: keep the piece picked for another copy
		task.defer(function()
			showGhost()
			rebuild()
		end)
	end
end

function BuildUI.isOpen(): boolean
	return open
end

local function setTab(onTab: string)
	local old = OLD_TABS[onTab]
	if old then
		tab = "work"
		chip.work = old
	else
		tab = onTab
	end
end

-- `onTab`: the tray opens on that tab (the quests' Go: GAME_DESIGN 9; an old kind's name opens Work on its row); a
-- tip's tab still wins.
function BuildUI.open(onTab: string?)
	if open then
		if onTab then
			setTab(onTab)
			rebuild()
		end
		return
	end
	open = true
	UIKit.closePanel()
	CameraController.setFree(true, TRAY_H + 8)
	local downAt: Vector2? = nil
	local last: Vector2? = nil
	local dragged = false
	local stroking = false -- a stroke under way (drawing: the press doesn't pan)
	table.insert(conns, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.Keyboard then
			-- the keys: R turns, C copies, X clears away, E places, Esc drops what is picked (then leaves)
			local k = input.KeyCode
			if k == Enum.KeyCode.R then
				rotatePicked()
			elseif k == Enum.KeyCode.C then
				copyPicked()
			elseif k == Enum.KeyCode.X or k == Enum.KeyCode.Delete then
				storePicked()
			elseif k == Enum.KeyCode.E or k == Enum.KeyCode.Return then
				BuildUI.confirm()
			elseif k == Enum.KeyCode.Escape then
				if pick then
					pick = nil
					clearGhost()
					clearDrawGhost()
					rebuild()
				else
					BuildUI.close()
				end
			end
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			downAt = Vector2.new(input.Position.X, input.Position.Y)
			last = downAt
			dragged = false
			closeTip()
			if drawing() and not draw.look then
				local c = drawCellAt(downAt :: Vector2)
				if c then
					stroking = true
					draw.start, draw.last, draw.cells, draw.seen, draw.memo = c, nil, {}, {}, {}
					strokeTo(c)
				end
			end
		end
	end))
	table.insert(conns, UserInputService.InputChanged:Connect(function(input, processed)
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local d, l = downAt, last
			if stroking then
				local c = drawCellAt(pos)
				if c and (draw.last == nil or c[1] ~= (draw.last :: { number })[1] or c[2] ~= (draw.last :: { number })[2]) then
					strokeTo(c)
				end
				last = pos
			elseif drawing() and d == nil and input.UserInputType == Enum.UserInputType.MouseMovement and not processed and not draw.look then
				-- a mouse over the grass: where a press would start (a cell, or a fence's first length east)
				local c = drawCellAt(pos)
				if c then
					showDrawGhost({ if fenceDraw() then { c[1], c[2], 0 } else c })
				end
			elseif d and l then
				if dragged or (pos - d).Magnitude > 8 then
					dragged = true
					CameraController.panBy(pos.X - l.X, pos.Y - l.Y)
				end
				last = pos
			elseif input.UserInputType == Enum.UserInputType.MouseMovement and not processed and pick then
				moveGhostTo(pos)
			end
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local d = downAt
			downAt, last = nil, nil
			if stroking then
				stroking = false
				finishStroke()
				return
			end
			if d and not dragged and not processed and not drawing() then
				onTap(Vector2.new(input.Position.X, input.Position.Y), input.UserInputType == Enum.UserInputType.MouseButton1)
			end
		end
	end))
	table.insert(conns, StateClient.Changed:Connect(function()
		if open then
			draw.memo = {}
			showGhost()
			rebuild()
		end
	end))
	-- the tip's building pulses (its card, and its tab while another is shown) and shines now and then
	local nextShine = 0
	table.insert(conns, RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local k = (math.sin(now * 5) + 1) / 2
		local shine = now >= nextShine
		if shine then
			nextShine = now + 2
		end
		local c = goalCard
		if c and c.Parent then
			UIKit.setPlate(c, UIKit.color("plate_light"):Lerp(UIKit.color("accent"), k))
			if shine then
				local b = c:FindFirstChildWhichIsA("GuiButton")
				if b then
					UIKit.shine(b)
				end
			end
		end
		local tb = goalTab
		if tb and tb.Parent then
			UIKit.setButtonColor(tb, UIKit.color("plate_light"):Lerp(UIKit.color("accent"), k))
		end
	end))
	-- the stores every second: the tray follows what can be afforded (rebuilt when that changes)
	local affordKey = ""
	table.insert(conns, StateClient.Tick:Connect(function(v: Types.ClientView)
		if not open then
			return
		end
		local keyParts = {}
		for _, def in Buildings.list do
			table.insert(keyParts, if v.shells >= def.shells and v.wood >= def.wood then "1" else "0")
		end
		local k = table.concat(keyParts)
		if k ~= affordKey then
			affordKey = k
			rebuild()
		end
	end))
	table.insert(conns, UIKit.Resized:Connect(function()
		if open then
			rebuild()
		end
	end))
	if onTab then
		setTab(onTab)
	end
	tutSeen = nil
	followTut(view())
	rebuild()
	BuildUI.Changed:Fire(true)
end

function BuildUI.close()
	if not open then
		return
	end
	open = false
	for _, c in conns do
		c:Disconnect()
	end
	conns = {}
	pick = nil
	closeTip()
	clearGhost()
	clearDrawGhost()
	draw.start, draw.last, draw.cells, draw.seen, draw.memo = nil, nil, {}, {}, {}
	-- (the search box is cleared for next time)
	query = ""
	if search then
		(search :: Frame):Destroy()
		search = nil
	end
	if tray then
		tray:Destroy()
		tray = nil
	end
	CameraController.setFree(false)
	BuildUI.Changed:Fire(false)
end

-- Sims and previews: the tray's tab, its row and the tip's building (nil when none).
function BuildUI.debugState(): { tab: string, chip: string, goal: string? }
	local g = tutGoal(view())
	return { tab = tab, chip = chip[tab] or "", goal = if g then g.id else nil }
end

-- Sims and previews: pick a piece to place as a player would (its card).
function BuildUI.pick(id: string, rot: number?)
	pick = { id = id, rot = rot or 0, move = nil, x = 0, z = 0, set = false }
	clearGhost()
	rebuild()
end
-- Sims and previews: tap a world point as a player would (the screen point the pixel layer shows it at).
function BuildUI.tapScreen(pos: Vector2, mouse: boolean?)
	onTap(pos, mouse == true)
end
-- Sims and previews: a stroke as a player draws it, through plot-local cells (tiles) or corners (fences) (mode "line",
-- "box" or "erase"; `keep` leaves the markers up without sending, for a preview's frame). Returns what the plan says a
-- cell (or an edge) at a time.
function BuildUI.debugDraw(cells: { { number } }, mode: string, keep: boolean?): { string }
	draw.box = mode == "box"
	draw.erase = mode == "erase"
	draw.look = false
	draw.start, draw.last, draw.cells, draw.seen, draw.memo = cells[1], nil, {}, {}, {}
	for _, c in cells do
		strokeTo(c)
	end
	local plan = strokePlan(draw.cells)
	if not keep then
		finishStroke()
	end
	rebuild()
	return plan
end
-- Sims and previews: type in the search box (as a player would).
function BuildUI.debugSearch(text: string)
	local f = search
	local box = if f then f:FindFirstChild("Box") else nil
	if box and box:IsA("TextBox") then
		box.Text = text
	end
end
-- Sims and previews: show a card's tooltip (as a mouse over it would).
function BuildUI.debugTip(id: string): boolean
	local list = if tray then (tray :: Frame):FindFirstChild("Cards", true) else nil
	local card = if list then list:FindFirstChild("Card_" .. id) else nil
	local v = view()
	local def = Buildings.byId[id]
	if card and card:IsA("GuiObject") and v and def then
		showTip(card, def, v)
		return true
	end
	return false
end

return BuildUI
