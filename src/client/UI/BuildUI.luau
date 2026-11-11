--!strict
-- Build mode (GAME_DESIGN 4; docs/ARCHITECTURE.md 10.7): building the island. The HUD's Build button opens it: the
-- view stops following the founder and shows the own island (a drag on the world pans it, CameraController.setFree /
-- panBy), and a tray along the bottom lists what can be built, a tab a kind (Food, Wood, Shops, Homes, Nests, Decor),
-- each with its price in shells and wood (locked until the island is big enough: Expand, in the tray's header). With
-- a piece picked, a ghost of it stands where the pointer is (mouse) or was tapped (touch), on a footprint that is
-- cyan where it fits (Logic/Plot.fits, the server's own rule) and red where it does not; Place (or a second click on
-- the same spot) asks the server (plot.place: paid then), Rotate turns it a quarter. Tapping a piece standing on the
-- island picks it up to move (plot.move), Upgrade it (plot.upgrade: a building that makes something) or Clear it
-- away (plot.store: half its price back). Done closes it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

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
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local Words = require(script.Parent.Words)

local RunService = game:GetService("RunService")

local BuildUI = {}
BuildUI.Changed = Util.Signal() :: Types.Signal<boolean>

local TRAY_H = 60
BuildUI.TRAY_H = TRAY_H
-- the tray's tabs: a kind (or two) of Data/Buildings each, with its small icon
local TABS: { { key: string, text: string, kinds: { string }, icon: string } } = {
	{ key = "food", text = "Food", kinds = { "food" }, icon = "food" },
	{ key = "wood", text = "Wood", kinds = { "wood" }, icon = "wood" },
	{ key = "shop", text = "Shops", kinds = { "shop" }, icon = "shell" },
	{ key = "home", text = "Homes", kinds = { "home" }, icon = "home" },
	{ key = "nest", text = "Nests", kinds = { "nest", "train", "breed" }, icon = "nest" },
	{ key = "gen", text = "Boosts", kinds = { "gen" }, icon = "boost" },
	{ key = "path", text = "Paths", kinds = { "path" }, icon = "path" },
	{ key = "decor", text = "Decor", kinds = { "decor" }, icon = "decor" },
}
local tab = "food"

-- The tips in Build mode (GAME_DESIGN 9: "make the tutorial show while in the build menu as well, and auto switches
-- the player to the tab where the required buildings are in"): the tip's banner stays above the tray (UI/Hud), and
-- opening Build mode, or a tip moving on while it is open, turns the tray to the tab of the building the tip asks
-- for; that building's card (and its tab, while another is shown) pulses until it stands on the island.
local TUT: { [number]: { tab: string, id: string } } = {
	[1] = { tab = "food", id = "patch" },
	[2] = { tab = "wood", id = "lumber" },
	[3] = { tab = "shop", id = "stall" },
	[4] = { tab = "home", id = "tent" },
	[5] = { tab = "nest", id = "nest" },
}
local tutSeen: number? = nil -- the tip the tray last turned for (nil: turn on the next look)
local goalCard: Frame? = nil
local goalTab: GuiButton? = nil
type Pick = { id: string, rot: number, move: number?, x: number, z: number, set: boolean, replace: boolean? }

local open = false
local tray: Frame? = nil
local pick: Pick? = nil
local ghost: Model? = nil
local marker: BasePart? = nil
local conns: { { Disconnect: (any) -> () } } = {}

-- Drawing paths (GAME_DESIGN 4: "paths should be able to be drawn or made in a box like the original interface in the
-- bakery game"): with a path tile picked, a press on the island starts a stroke instead of a pan. Line: the drag lays
-- tiles along the way (every 2-stud cell the pointer passes, no gaps when it jumps); Box: the drag fills the box
-- between the press and the pointer; Erase: the same strokes take path tiles up (half their price back); Look around:
-- a drag pans again. What the stroke would do shows on the island at once (a flat marker a cell: cyan where a tile
-- goes, red where it can't, orange where one comes up), and on release it goes to the server (plot.paint /
-- plot.unpaint, Plot.PAINT_MAX cells a request).
type Draw = { box: boolean, erase: boolean, look: boolean, start: { number }?, last: { number }?, cells: { { number } }, seen: { [string]: boolean } }
local draw: Draw = { box = false, erase = false, look = false, start = nil, last = nil, cells = {}, seen = {} }
local drawGhost: Model? = nil
local DRAW_MOST = 240 -- cells a stroke holds at most (a box is cut there)

local function view(): Types.ClientView?
	return StateClient.view()
end

local function placed(): { Types.Piece }
	local v = view()
	return if v then v.pieces else {}
end

-- What the current tip asks to build, while it is not built yet (the nest's tip waits for a sail as well).
local function tutGoal(v: Types.ClientView?): { tab: string, id: string }?
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
	if g and tab ~= g.tab then
		tab = g.tab
		return true
	end
	return false
end

local function origin(): (number, number)
	local v = view()
	return Office.origin(if v then v.plot else 1)
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

-- Draw the ghost and its footprint (green where it fits, red where not) where the pick stands: a fresh model each
-- time (a handful of parts), one dynamic model with its footprint.
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
	-- the footprint: a raised neon frame round it (cyan where it fits, red where not), from the grass to just above the
	-- lodge's floor, so it shows on the grass and on a floor alike
	local ok = fits(p)
	local color = if ok then "screen_on" else "berry_red"
	local y0, y1 = Street.LAWN_Y, 0.375
	local h = y1 - y0
	local frame = Blocks.model(m, "Footprint")
	for _, e in { { 0, -d / 2, w, 0.25 }, { 0, d / 2, w, 0.25 }, { -w / 2, 0, 0.25, d }, { w / 2, 0, 0.25, d } } do
		Blocks.part(frame, { size = Vector3.new(e[3], h, e[4]), cf = CFrame.new(cx + e[1], (y0 + y1) / 2, cz + e[2]), color = color, name = "Edge", neon = true, collide = false, query = false })
	end
	marker = frame:FindFirstChildWhichIsA("BasePart")
	m.Name = "Ghost"
	m.Parent = workspace:FindFirstChild("PixelDynamic") or workspace
	ghost = m
	PixelRenderer.registerDynamic(m)
end

------------------------------------------------------------------ drawing paths
local function drawing(): boolean
	local p = pick
	return p ~= nil and p.move == nil and Plot.isPath(p.id)
end

local function clearDrawGhost()
	if drawGhost then
		PixelRenderer.unregisterDynamic(drawGhost)
		drawGhost:Destroy()
		drawGhost = nil
	end
end

-- The path tiles standing on a cell (their indices).
local function pathsOn(c: { number }): { number }
	local out = {}
	for i, q in placed() do
		if Plot.isPath(q.id) then
			local r = Plot.rect(q.id, q.x, q.z, q.rot)
			if c[1] < r.x1 and c[1] + Plot.PATH_STEP > r.x0 and c[2] < r.z1 and c[2] + Plot.PATH_STEP > r.z0 then
				table.insert(out, i)
			end
		end
	end
	return out
end

-- What the stroke would do, cell by cell: "lay" (a tile goes down), "no" (it can't: taken, off the grass, no room or
-- not enough shells) or "lift" (Erase: a tile comes up); and how many tiles and their price.
local function strokePlan(cells: { { number } }): ({ string }, number, number)
	local v = view()
	local p = pick
	local out: { string } = {}
	if v == nil or p == nil then
		return out, 0, 0
	end
	local def = Buildings.byId[p.id]
	local used, most = 0, 0
	for _, q in v.pieces do
		if Plot.isPath(q.id) then
			used += 1
		end
	end
	most = Plot.pathLimit(v.tier)
	local shells, wood = v.shells, v.wood
	local n, cost = 0, 0
	for _, c in cells do
		if draw.erase then
			if #pathsOn(c) > 0 then
				table.insert(out, "lift")
				n += 1
			else
				table.insert(out, "no")
			end
		else
			local ok = def ~= nil and used < most and shells >= def.shells and wood >= def.wood and Plot.fits(v.tier, placed(), p.id, c[1], c[2], 0)
			if ok and def then
				used += 1
				shells -= def.shells
				wood -= def.wood
				cost += def.shells
				n += 1
			end
			table.insert(out, if ok then "lay" else "no")
		end
	end
	return out, n, cost
end

-- The stroke's markers: one flat plate a cell, just over the grass.
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
	if label and label:IsA("TextLabel") and #cells > 1 then
		UIKit.setText(label, if draw.erase then string.format("%d to take up", n) else string.format("%d tile%s, %s shells", n, if n == 1 then "" else "s", Numbers.coins(cost)))
	end
	local ox, oz = origin()
	local m = Blocks.model(nil, "PathGhost")
	for k, c in cells do
		local what = plan[k]
		local color = if what == "lay" then "screen_on" elseif what == "lift" then "orange" else "berry_red"
		Blocks.part(m, {
			size = Vector3.new(1.75, 0.125, 1.75),
			cf = CFrame.new(ox + c[1] + 1, Street.LAWN_Y + 0.2, oz + c[2] + 1),
			color = color,
			neon = true,
			collide = false,
			query = false,
			name = "Cell",
		})
	end
	m.Parent = workspace:FindFirstChild("PixelDynamic") or workspace
	drawGhost = m
	PixelRenderer.registerDynamic(m)
end

-- The 2-stud cell under a screen point (plot-local), or nil off the lawn plane.
local function drawCellAt(pos: Vector2): { number }?
	local o, dir = PixelRenderer.screenRay(pos)
	if math.abs(dir.Y) < 1e-6 then
		return nil
	end
	local t = (Street.LAWN_Y - o.Y) / dir.Y
	if t < 0 then
		return nil
	end
	local hit = o + dir * t
	local ox, oz = origin()
	local step = Plot.PATH_STEP
	return { math.floor((hit.X - ox) / step) * step, math.floor((hit.Z - oz) / step) * step }
end

local function addCell(c: { number })
	local key = c[1] .. "," .. c[2]
	if draw.seen[key] or #draw.cells >= DRAW_MOST then
		return
	end
	draw.seen[key] = true
	table.insert(draw.cells, c)
end

-- The stroke reaches cell c: a line joins every cell on the way from the last one; a box is the cells between its
-- first corner and c.
local function strokeTo(c: { number })
	local step = Plot.PATH_STEP
	if draw.box then
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

-- The stroke let go: its cells go to the server (in parts), and the island's markers go.
local function finishStroke()
	local cells = draw.cells
	local p = pick
	draw.start, draw.last, draw.cells, draw.seen = nil, nil, {}, {}
	clearDrawGhost()
	if p == nil or #cells == 0 then
		return
	end
	local plan = strokePlan(cells)
	local send: { { number } } = {}
	for k, c in cells do
		if plan[k] ~= "no" then
			table.insert(send, c)
		end
	end
	if #send == 0 then
		Audio.play("deny")
		UIKit.notice(if draw.erase then "No path there to take up." else "No tile fits there.", UIKit.color("bad"), 2)
		return
	end
	local laid, lifted = 0, 0
	for i = 1, #send, Plot.PAINT_MAX do
		local part = table.move(send, i, math.min(#send, i + Plot.PAINT_MAX - 1), 1, {})
		local res = if draw.erase then StateClient.request("plot.unpaint", { cells = Plot.cellString(part) }) else StateClient.request("plot.paint", { id = p.id, cells = Plot.cellString(part) })
		if res.ok and type(res.data) == "table" then
			laid += tonumber(res.data.placed) or 0
			lifted += tonumber(res.data.removed) or 0
		elseif not res.ok then
			UIKit.notice(Words.errText(res.err), UIKit.color("bad"))
			break
		end
	end
	if laid > 0 then
		Audio.play("hammer")
	elseif lifted > 0 then
		Audio.play("close")
	end
	task.defer(rebuild)
end

------------------------------------------------------------------ the tray

-- A price: its shells and wood with their small icons from x (red when there is not enough); returns the end x.
local function price(parent: Instance, x: number, y: number, shells: number, wood: number, v: Types.ClientView, z: number?): number
	PixelSprites.image(parent, "mini_shell", UDim2.fromOffset(x, y), z or 4)
	local t = Numbers.coins(shells)
	UIKit.text(parent, t, UDim2.fromOffset(UIKit.textWidth(t) + 2, 10), UDim2.fromOffset(x + 11, y + 1), { color = if v.shells >= shells then UIKit.color("text") else UIKit.color("bad"), z = z or 4, name = "Shells" })
	x += 13 + UIKit.textWidth(t) + 2
	if wood > 0 then
		PixelSprites.image(parent, "mini_wood", UDim2.fromOffset(x, y), z or 4)
		local tw = Numbers.coins(wood)
		UIKit.text(parent, tw, UDim2.fromOffset(UIKit.textWidth(tw) + 2, 10), UDim2.fromOffset(x + 11, y + 1), { color = if v.wood >= wood then UIKit.color("text") else UIKit.color("bad"), z = z or 4, name = "Wood" })
		x += 13 + UIKit.textWidth(tw) + 2
	end
	return x
end

-- Replacing a placed piece (GAME_DESIGN 4.1): the others of its kind open at the tier, each with what it adds and
-- what it costs after the old one's refund; a tap replaces it where it stands.
local function replaceBar(f: Frame, p: Pick, v: Types.ClientView, q: Types.Piece)
	local old = Buildings.byId[q.id]
	UIKit.button(f, "Back", UDim2.fromOffset(40, 13), UDim2.fromOffset(4, 2), function()
		local cur = pick
		if cur then
			cur.replace = nil
			rebuild()
		end
	end, { name = "ReplaceBack", color = UIKit.color("plate_light") })
	UIKit.text(f, "Replace the " .. (if old then old.name else q.id) .. " with:", UDim2.fromOffset(220, 13), UDim2.fromOffset(48, 2), { color = UIKit.color("accent"), name = "ReplaceWhat" })
	local list = UIKit.scroll(f, UDim2.new(1, -8, 0, 30), UDim2.fromOffset(4, 18))
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
		local card = UIKit.plate(list, UDim2.fromOffset(84, 28), nil, UIKit.color("plate_light"), 0, 2, { bevel = true })
		card.Name = "Swap_" .. id
		card.LayoutOrder = k
		local what = if d.beds > 0 then string.format("%s: %d beds", d.name, d.beds) elseif d.slots > 0 then string.format("%s: room %d", d.name, d.slots) else d.name
		UIKit.text(card, what, UDim2.fromOffset(82, 10), UDim2.fromOffset(2, 1), { color = UIKit.color("text"), z = 4 })
		local b = UIKit.button(card, "", UDim2.fromOffset(80, 14), UDim2.fromOffset(2, 12), function()
			local cur = pick
			if cur == nil or cur.move == nil then
				return
			end
			local res = ask("plot.replace", { i = cur.move, id = id })
			if res.ok then
				Audio.play("level_up")
				UIKit.notice(string.format("The %s is a %s now.", if old then old.name else "piece", d.name), UIKit.color("good"))
				pick = nil
				clearGhost()
				task.defer(rebuild)
			end
		end, { name = "SwapTo_" .. id, color = if afford then UIKit.color("button_ok") else nil })
		price(b, 3, 2, cost.shells, cost.wood, v, 6)
	end
end

-- Drawing paths: the tools, what the stroke does and its price.
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
	local info = UIKit.plate(f, UDim2.new(1, -8, 0, 28), UDim2.fromOffset(4, 18), UIKit.color("plate_light"), 0, 2, { bevel = true })
	info.Name = "Info"
	UIKit.text(info, (if draw.erase then "Taking up paths" else "Drawing: " .. (if def then def.name else p.id)), UDim2.new(1, -8, 0, 10), UDim2.fromOffset(4, 2), { color = UIKit.color("accent"), z = 4, name = "What" })
	local say
	if draw.look then
		say = "Drag to look around. Tap Look around again to draw."
	elseif draw.erase then
		say = if draw.box then "Drag a box over the paths to take them up. Half their price comes back." else "Drag along the paths to take them up. Half their price comes back."
	elseif draw.box then
		say = "Drag a box across the grass to fill it with tiles."
	else
		say = "Drag across the grass to lay a line of tiles."
	end
	UIKit.text(info, say, UDim2.new(1, -8, 0, 10), UDim2.fromOffset(4, 14), { color = UIKit.color("text_dim"), z = 4, name = "Blurb" })
	if def and not draw.erase then
		price(info, math.max(4, f.Size.X.Offset - 92), 1, def.shells, def.wood, v)
	end
	-- the stroke under way: how many tiles and what they cost (set as it changes: showDrawGhost)
	UIKit.text(info, "", UDim2.fromOffset(150, 10), UDim2.new(1, -154, 0, 14), { x = "right", color = UIKit.color("accent"), z = 4, name = "Stroke" })
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
	btn("Rotate", nil, true, function()
		local q = pick
		if q then
			q.rot = (q.rot + 90) % 360
			showGhost()
			rebuild()
		end
	end, "Rotate")
	btn(if p.move then "Move here" else "Place", UIKit.color("button_ok"), p.set and fits(p), function()
		BuildUI.confirm()
	end, "Place")
	local q = if p.move then placed()[p.move] else nil
	if q then
		local up = Plot.upgradeCost(q)
		if up then
			btn("Upgrade", UIKit.color("accent"), v.shells >= up.shells and v.wood >= up.wood, function()
				local cur = pick
				if cur and cur.move then
					local res = ask("plot.upgrade", { i = cur.move })
					if res.ok then
						Audio.play("level_up")
						UIKit.notice(string.format("%s is Lv %d now.", if def then def.name else "It", (res.data and res.data.lvl) or 2), UIKit.color("good"))
						pick = nil
						clearGhost()
						task.defer(rebuild)
					end
				end
			end, "Upgrade")
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
		btn("Clear away", UIKit.color("button_warn"), true, function()
			local cur = pick
			if cur and cur.move then
				local res = ask("plot.store", { i = cur.move })
				if res.ok then
					Audio.play("close")
					pick = nil
					clearGhost()
					task.defer(rebuild)
				end
			end
		end, "Store")
	end
	btn("Cancel", UIKit.color("plate_light"), true, function()
		pick = nil
		clearGhost()
		rebuild()
	end, "Cancel")
	-- what it is and costs (or its level and the next level's price)
	local info = UIKit.plate(f, UDim2.new(1, -8, 0, 28), UDim2.fromOffset(4, 18), UIKit.color("plate_light"), 0, 2, { bevel = true })
	info.Name = "Info"
	local name = (if def then def.name else p.id) .. (if q and q.lvl > 1 then " Lv" .. q.lvl else "")
	UIKit.text(info, (if p.move then "Moving: " else "Placing: ") .. name, UDim2.new(1, -8, 0, 10), UDim2.fromOffset(4, 2), { color = UIKit.color("accent"), z = 4, name = "What" })
	local say = if def then def.blurb else ""
	if def and def.rate > 0 then
		local lvl = if q then q.lvl else 1
		say = string.format("%s %s a minute with a %s.", say, (Numbers.perMin(def.rate * (Tuning.UpgradeMult[lvl] or 1) * 60 / Tuning.TurnSeconds):gsub("/min", "")), string.lower(def.job))
	end
	if def and (def.beds > 0 or def.slots > 0) then
		local lvl = if q then q.lvl else 1
		local c = def.comfort + (Tuning.ComfortLvl[lvl] or 0)
		say = string.format("%s %s %d.%s", say, if def.beds > 0 then "Beds" else "Room for", def.beds + def.slots, if c > 0 then string.format(" Comfort +%d%%.", math.round(c * 100)) else "")
	end
	if def and def.charm >= 1 then
		say ..= string.format(" Charm +%d.", math.floor(def.charm))
	end
	UIKit.text(info, say, UDim2.new(1, -8, 0, 10), UDim2.fromOffset(4, 14), { color = UIKit.color("text_dim"), z = 4, name = "Blurb" })
	if q then
		local up = Plot.upgradeCost(q)
		if up then
			UIKit.text(info, "Next level:", UDim2.fromOffset(60, 10), UDim2.new(1, -150, 0, 2), { x = "right", color = UIKit.color("text_dim"), z = 4 })
			price(info, math.max(4, f.Size.X.Offset - 92), 1, up.shells, up.wood, v)
		end
	elseif def then
		price(info, math.max(4, f.Size.X.Offset - 92), 1, def.shells, def.wood, v)
	end
end

local function cards(list: ScrollingFrame, v: Types.ClientView)
	UIKit.hlist(list, 3)
	local cur = TABS[1]
	for _, t in TABS do
		if t.key == tab then
			cur = t
		end
	end
	local k = 0
	for _, def in Buildings.list do
		if not table.find(cur.kinds, def.kind) then
			continue
		end
		k += 1
		local locked = def.tier > v.tier
		local afford = v.shells >= def.shells and v.wood >= def.wood
		local card = UIKit.plate(list, UDim2.fromOffset(72, 28), nil, if pick and pick.id == def.id then UIKit.color("accent") else UIKit.color("plate_light"), 0, 2, { bevel = true })
		card.Name = "Card_" .. def.id
		local goal = tutGoal(v)
		if goal and goal.id == def.id and not locked then
			card:SetAttribute("TutGoal", true)
			goalCard = card
		end
		card.LayoutOrder = (if locked then 100 else 0) + k
		UIKit.text(card, def.name, UDim2.fromOffset(70, 10), UDim2.fromOffset(2, 1), { color = if locked then UIKit.color("text_dim") else UIKit.color("text"), z = 4 })
		local b = UIKit.button(card, "", UDim2.fromOffset(68, 14), UDim2.fromOffset(2, 12), function()
			if locked then
				UIKit.notice("Expand your island to build this.", UIKit.color("bad"))
				Audio.play("deny")
				return
			end
			pick = { id = def.id, rot = 0, move = nil, x = 0, z = 0, set = false }
			clearGhost()
			clearDrawGhost()
			UIKit.notice(if def.kind == "path" then "Drag across the grass to lay tiles." else "Tap the grass where it should go.", UIKit.color("text_dim"), 2.5)
			rebuild()
		end, {
			name = "Buy_" .. def.id,
			color = if locked then UIKit.color("button_off") elseif afford then UIKit.color("button_ok") else nil,
		})
		if locked then
			UIKit.text(b, string.format("Island Lv%d", def.tier), UDim2.fromScale(1, 1), nil, { x = "center", color = UIKit.color("text_dim"), z = 6 })
		else
			price(b, 3, 2, def.shells, def.wood, v, 6)
		end
	end
end

rebuild = function()
	goalCard, goalTab = nil, nil
	if tray then
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
		-- the tabs (their icons alone on a narrow screen), the pieces count and Expand
		local x = 4
		local wide = 0
		for _, t in TABS do
			wide += UIKit.buttonWidth(t.text, 5) + 13
		end
		local short = wide > s.X - 8 - 152
		for _, t in TABS do
			local w = if short then 16 else UIKit.buttonWidth(t.text, 5) + 11
			local b = UIKit.button(f, if short then "" else t.text, UDim2.fromOffset(w, 13), UDim2.fromOffset(x, 2), function()
				tab = t.key
				Audio.play("flip")
				rebuild()
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
		local cost = Island.expandCost(v.tier)
		local ex = UIKit.button(f, if cost then "Expand" else "Island max", UDim2.fromOffset(54, 13), UDim2.new(1, -102, 0, 2), function()
			local res = ask("island.expand", {})
			if res.ok then
				-- cheer when the bigger island is on screen (the server swaps in the island it built ahead; the
				-- filter re-bakes it in a few frames), at most a moment later
				local moved = if type(res.data) == "table" then tonumber(res.data.moved) or 0 else 0
				local cheered = false
				local function cheer()
					if cheered then
						return
					end
					cheered = true
					Audio.play("fanfare")
					UIKit.notice(if moved > 0 then string.format("Your island grew. %d building%s had to move for the new lodge.", moved, if moved == 1 then "" else "s") else "Your island grew, and there's more you can build now.", UIKit.color("good"), 4)
				end
				PixelRenderer.afterBake(cheer)
				task.delay(1.5, cheer)
			end
		end, { name = "Expand", color = UIKit.color("button_warn"), enabled = cost ~= nil and v.shells >= cost.shells and v.wood >= cost.wood })
		local _ = ex
		-- the pieces standing (or the path tiles, on the Paths tab) and the island's limit
		local paths = 0
		for _, q in v.pieces do
			if Plot.isPath(q.id) then
				paths += 1
			end
		end
		local used, most = if tab == "path" then paths else #v.pieces - paths, if tab == "path" then Plot.pathLimit(v.tier) else Plot.limit(v.tier)
		UIKit.text(f, string.format("%d/%d", used, most), UDim2.fromOffset(40, 13), UDim2.new(1, -146, 0, 2), { x = "right", color = if used >= most then UIKit.color("orange") else UIKit.color("text_dim"), name = "Count" })
		if cost then
			local pf = Instance.new("Frame")
			pf.Name = "ExpandCost"
			pf.BackgroundTransparency = 1
			pf.Size = UDim2.fromOffset(100, 11)
			pf.Position = UDim2.new(1, -102, 0, 47)
			pf.Parent = f
			price(pf, 0, 0, cost.shells, cost.wood, v)
		end
	end
	UIKit.button(f, "Done", UDim2.fromOffset(40, 13), UDim2.new(1, -44, 0, 2), function()
		BuildUI.close()
	end, { color = UIKit.color("accent"), name = "BuildDone" })
	if p == nil then
		local list = UIKit.scroll(f, UDim2.new(1, -8, 0, 30), UDim2.fromOffset(4, 18))
		list.ScrollingDirection = Enum.ScrollingDirection.X
		list.AutomaticCanvasSize = Enum.AutomaticSize.X
		cards(list, v)
	end
	tray = f
end

------------------------------------------------------------------ pointer
-- The plot-local cell (footprint's north-west corner) under a screen point for a piece, or nil off the lawn plane.
local function cellAt(pos: Vector2, id: string, rot: number): (number?, number?)
	local o, dir = PixelRenderer.screenRay(pos)
	if math.abs(dir.Y) < 1e-6 then
		return nil, nil
	end
	local t = (Street.LAWN_Y - o.Y) / dir.Y
	if t < 0 then
		return nil, nil
	end
	local hit = o + dir * t
	local ox, oz = origin()
	local w, d = Plot.footprint(id, rot)
	return math.floor(hit.X - ox - w / 2 + 0.5), math.floor(hit.Z - oz - d / 2 + 0.5)
end

-- The index of the own plot's piece under a screen point, if any.
local function pieceAt(pos: Vector2): number?
	local o, dir = PixelRenderer.screenRay(pos)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local v = view()
	local plots = workspace:FindFirstChild("Plots")
	local plotModel = if plots and v then plots:FindFirstChild("Plot_" .. v.plot) else nil
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
	if p.move then
		res = ask("plot.move", { i = p.move, x = p.x, z = p.z, rot = p.rot })
	else
		res = ask("plot.place", { id = p.id, x = p.x, z = p.z, rot = p.rot })
	end
	if res.ok then
		Audio.play("hammer")
		-- (the tip's building placed: the tray goes on to the next tip's tab rather than offering another copy)
		if p.move or (goal and goal.id == p.id) then
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

function BuildUI.open()
	if open then
		return
	end
	open = true
	UIKit.closePanel()
	CameraController.setFree(true, TRAY_H + 8)
	local downAt: Vector2? = nil
	local last: Vector2? = nil
	local dragged = false
	local stroking = false -- a path stroke under way (drawing: the press doesn't pan)
	table.insert(conns, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			downAt = Vector2.new(input.Position.X, input.Position.Y)
			last = downAt
			dragged = false
			if drawing() and not draw.look then
				local c = drawCellAt(downAt :: Vector2)
				if c then
					stroking = true
					draw.start, draw.last, draw.cells, draw.seen = c, nil, {}, {}
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
				-- a mouse over the grass: the cell a press would start on
				local c = drawCellAt(pos)
				if c then
					showDrawGhost({ c })
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
		local key = {}
		for _, def in Buildings.list do
			table.insert(key, if v.shells >= def.shells and v.wood >= def.wood then "1" else "0")
		end
		local k = table.concat(key)
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
	clearGhost()
	clearDrawGhost()
	draw.start, draw.last, draw.cells, draw.seen = nil, nil, {}, {}
	if tray then
		tray:Destroy()
		tray = nil
	end
	CameraController.setFree(false)
	BuildUI.Changed:Fire(false)
end

-- Sims and previews: the tray's tab and the tip's building (nil when none).
function BuildUI.debugState(): { tab: string, goal: string? }
	local g = tutGoal(view())
	return { tab = tab, goal = if g then g.id else nil }
end

-- Sims and previews: tap a world point as a player would (the screen point the pixel layer shows it at).
function BuildUI.pick(id: string, rot: number?)
	pick = { id = id, rot = rot or 0, move = nil, x = 0, z = 0, set = false }
	clearGhost()
	rebuild()
end
function BuildUI.tapScreen(pos: Vector2, mouse: boolean?)
	onTap(pos, mouse == true)
end
-- Sims and previews: a path stroke as a player draws it, through plot-local cells (mode "line", "box" or "erase";
-- `keep` leaves the markers up without sending, for a preview's frame). Returns what the plan says a cell at a time.
function BuildUI.debugDraw(cells: { { number } }, mode: string, keep: boolean?): { string }
	draw.box = mode == "box"
	draw.erase = mode == "erase"
	draw.look = false
	draw.start, draw.last, draw.cells, draw.seen = cells[1], nil, {}, {}
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

return BuildUI
