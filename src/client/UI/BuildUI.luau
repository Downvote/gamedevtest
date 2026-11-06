--!strict
-- Build mode (GAME_DESIGN 13; docs/ARCHITECTURE.md 10.7): decorating the plot. The HUD's Build button opens it: the
-- clock holds (pause key "build"), the view stops following the founder and shows the own plot (a drag on the world
-- pans it, CameraController.setFree / panBy), and a tray along the bottom lists every piece of decor: the ones not
-- bought yet with their price and fans (a tap buys it: plot.buy), the owned ones ready to place. With a piece picked,
-- a ghost of it stands where the pointer is (mouse) or was tapped (touch), on a footprint that is green where it fits
-- (Logic/Plot.fits, the server's own rule) and red where it does not; Place (or a second click on the same spot) asks
-- the server (plot.place), Rotate turns it a quarter. Tapping a piece standing on the plot picks it up to move
-- (plot.move) or Store (plot.store). Done closes it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local Decor = require(ReplicatedStorage.Shared.Data.Decor)
local Office = require(ReplicatedStorage.Shared.Data.Office)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local Plot = require(ReplicatedStorage.Shared.Logic.Plot)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local Blocks = require(ReplicatedStorage.Shared.Models.Blocks)
local DecorModels = require(ReplicatedStorage.Shared.Models.DecorModels)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.UIKit)
local NewGameUI = require(script.Parent.NewGameUI)

local BuildUI = {}
BuildUI.Changed = Util.Signal() :: Types.Signal<boolean>

local TRAY_H = 46

type Pick = { id: string, rot: number, move: number?, x: number, z: number, set: boolean }

local open = false
local tray: Frame? = nil
local pick: Pick? = nil
local ghost: Model? = nil
local ghostKey = ""
local marker: BasePart? = nil
local conns: { { Disconnect: (any) -> () } } = {}

local function view(): Types.ClientView?
	return StateClient.view()
end

local function placed(): { Types.Piece }
	local v = view()
	return if v then v.decor.placed else {}
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
		UIKit.notice(if res.err == "blocked" then "It doesn't fit there." else NewGameUI.errText(res.err), UIKit.color("bad"))
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
	ghostKey = ""
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
	return (Plot.fits(v.office, placed(), p.id, p.x, p.z, p.rot, p.move))
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
	local m = DecorModels.build(p.id, CFrame.new(cx, Street.LAWN_Y, cz) * CFrame.Angles(0, math.rad(p.rot), 0))
	for _, part in m:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanQuery = false
			part.CanCollide = false
		end
	end
	-- the footprint: a raised neon frame round it (cyan where it fits, red where not), from the lawn to just above the
	-- office floor, so it shows on the lawn and on a floor alike
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
	ghostKey = p.id
	PixelRenderer.registerDynamic(m)
end

------------------------------------------------------------------ the tray
local rebuild: () -> () = function() end

local function actionBar(f: Frame, p: Pick)
	local def = Decor.byId[p.id]
	local x = 4
	local function btn(text: string, color: Color3?, enabled: boolean, click: () -> (), name: string)
		local w = UIKit.buttonWidth(text, 5)
		UIKit.button(f, text, UDim2.fromOffset(w, 13), UDim2.fromOffset(x, 2), click, { color = color, enabled = enabled, name = name })
		x += w + 3
	end
	UIKit.text(f, (if p.move then "Moving: " else "Placing: ") .. (if def then def.name else p.id), UDim2.fromOffset(150, 13), UDim2.new(1, -200, 0, 2), { x = "right", color = UIKit.color("accent") })
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
	if p.move then
		btn("Store", UIKit.color("button_warn"), true, function()
			local q = pick
			if q and q.move then
				ask("plot.store", { i = q.move }, "Back in the box.")
				pick = nil
				clearGhost()
				task.defer(rebuild)
			end
		end, "Store")
	end
	btn("Cancel", UIKit.color("plate_light"), true, function()
		pick = nil
		clearGhost()
		rebuild()
	end, "Cancel")
end

local function cards(list: ScrollingFrame, v: Types.ClientView)
	UIKit.hlist(list, 3)
	for k, def in Decor.list do
		local owned = v.decor.owned[def.id] == true
		local locked = v.office < def.office
		local text = if owned then "Place" elseif locked then Office.plan(def.office).name else Numbers.money(def.price)
		local card = UIKit.plate(list, UDim2.fromOffset(62, 27), nil, if pick and pick.id == def.id then UIKit.color("accent") else UIKit.color("plate_light"), 0, 2)
		card.Name = "Card_" .. def.id
		card.LayoutOrder = k
		UIKit.text(card, def.name, UDim2.fromOffset(60, 10), UDim2.fromOffset(2, 1), { color = if locked then UIKit.color("text_dim") else UIKit.color("text") })
		UIKit.button(card, text, UDim2.fromOffset(58, 13), UDim2.fromOffset(2, 12), function()
			if owned then
				pick = { id = def.id, rot = 0, move = nil, x = 0, z = 0, set = false }
				clearGhost()
				UIKit.notice("Tap the lawn where it should go.", UIKit.color("text_dim"), 2.5)
				rebuild()
			else
				ask("plot.buy", { id = def.id }, string.format("%s bought: +%d fans!", def.name, def.fans))
			end
		end, {
			name = "Buy_" .. def.id,
			color = if owned then UIKit.color("button_ok") else nil,
			enabled = owned or (not locked and v.money >= def.price),
		})
	end
end

rebuild = function()
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
	local canvas = UIKit.canvas("Hud")
	local s = UIKit.size("Hud")
	local f = UIKit.plate(canvas, UDim2.fromOffset(s.X - 8, TRAY_H), UDim2.fromOffset(4, s.Y - TRAY_H - 2), UIKit.color("plate"), 0.05, 3)
	f.Name = "BuildTray"
	local p = pick
	if p then
		actionBar(f, p)
	else
		UIKit.text(f, string.format("Build: pick a piece, then tap the lawn. Pieces %d/%d", #v.decor.placed, Plot.limit(v.office)), UDim2.new(1, -60, 0, 13), UDim2.fromOffset(5, 2), { color = UIKit.color("text") })
	end
	UIKit.button(f, "Done", UDim2.fromOffset(40, 13), UDim2.new(1, -44, 0, 2), function()
		BuildUI.close()
	end, { color = UIKit.color("accent"), name = "BuildDone" })
	local list = UIKit.scroll(f, UDim2.new(1, -8, 0, 30), UDim2.fromOffset(4, 16))
	list.ScrollingDirection = Enum.ScrollingDirection.X
	list.AutomaticCanvasSize = Enum.AutomaticSize.X
	cards(list, v)
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
	local id, x, z, rot = string.match(m.Name, "^(%w+):(%-?%d+):(%-?%d+):(%d+)$")
	for i, q in placed() do
		if q.id == id and q.x == tonumber(x) and q.z == tonumber(z) and q.rot == tonumber(rot) then
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
	if p.move then
		res = ask("plot.move", { i = p.move, x = p.x, z = p.z, rot = p.rot })
	else
		res = ask("plot.place", { id = p.id, x = p.x, z = p.z, rot = p.rot })
	end
	if res.ok then
		if p.move then
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
	CameraController.setFree(true, TRAY_H)
	StateClient.signal("pause", { key = "build", on = true })
	local downAt: Vector2? = nil
	local last: Vector2? = nil
	local dragged = false
	table.insert(conns, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			downAt = Vector2.new(input.Position.X, input.Position.Y)
			last = downAt
			dragged = false
		end
	end))
	table.insert(conns, UserInputService.InputChanged:Connect(function(input, processed)
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local d, l = downAt, last
			if d and l then
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
			if d and not dragged and not processed then
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
	if tray then
		tray:Destroy()
		tray = nil
	end
	CameraController.setFree(false)
	StateClient.signal("pause", { key = "build", on = false })
	BuildUI.Changed:Fire(false)
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

return BuildUI
