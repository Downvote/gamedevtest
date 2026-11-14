--!strict
-- How full the own island's buildings are (GAME_DESIGN 4.6; docs/ARCHITECTURE.md 10.2). The request of 2026-11-14:
-- "show capacities of work buildings when hovered over. if noone is working on a building, make a alert on top of said
-- work building stating so. do the same for huts and housing".
--   The card: with a mouse, a workplace or a hut under the pointer gets a small glass card over its roof, its name in
--   the accent and how full it is ("Workers 1/2", "Living here 2/2"); a tap on one shows the same card for a few
--   seconds (a phone has no pointer). One card at a time, nothing while a panel is open or in Build mode.
--   The alerts: over every workplace no driftling works at, and every hut no driftling lives in, a small glass tag
--   floats with the alert icon and "Empty" (the user's words, in place of "No workers" and "No one home"), bobbing a
--   pixel. They go the moment one moves in.
-- Only the own island's, drawn in the World root (hidden with it on the hatch scene). WorldView drives it: step every
-- frame, hover from the pointer, tapAt from a tap.
--   step(t, plot, hoverPos?, palHovered), tapAt(pos) -> boolean, debugState(), debugSpots()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Buildings = require(ReplicatedStorage.Shared.Data.Buildings)
local Island = require(ReplicatedStorage.Shared.Logic.Island)
local StateClient = require(script.Parent.StateClient)
local CameraController = require(script.Parent.CameraController)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local PixelSprites = require(script.Parent.Parent.UI.PixelSprites)

local BuildingTags = {}

local CARD_SECS = 3 -- a tap's card stays this long
local SCAN_SECS = 0.5 -- the island's buildings looked over this often (they change rarely)
local HOVER_SECS = 0.1 -- the pointer's building looked for this often
local CARD_TOP = 22 -- the card stays this far below the top of the HUD's canvas (UI px: the top bar's chips)

-- One building of the own island that houses or employs: its uid, piece id, model, the point over its roof (world),
-- whether it is a workplace (else a hut), its room, and how many work or live there now.
type Spot = { uid: number, id: string, model: Model, top: Vector3, work: boolean, room: number, n: number }

local spots: { [number]: Spot } = {}
local plotNow = 0
local scanAt = 0
local decorOf: Instance? = nil
local pickList: { Instance } = {} -- what the pointer's ray may meet: the workplaces, the huts and the tree (decor in
-- front of a hut, a bench or a lamp, never hides it; the tree does)
local alerts: { [number]: Frame } = {} -- uid -> its alert tag
local card: Frame? = nil
local cardUid = 0
local cardUntil = 0 -- a tap's card: shown till then (0: the pointer's)
local hoverUid = 0
local hoverAt = 0
local lastHit = "" -- what the last pick ray met (debugState)

local function plotModel(i: number): Model?
	local plots = workspace:FindFirstChild("Plots")
	local m = if plots then plots:FindFirstChild("Plot_" .. i) else nil
	return if m and m:IsA("Model") then m else nil
end

-- The island's workplaces and huts from its Decor folder (a model a piece, named "uid:id:x:z:rot"), each with the point
-- over its roof (its bounding box, kept while the model stays), and how many work or live there (the view's driftlings).
local function scan(v: Types.ClientView)
	local m = plotModel(plotNow)
	local decor = if m then m:FindFirstChild("Decor", true) else nil
	decorOf = decor
	local seen: { [number]: boolean } = {}
	if decor then
		for _, c in decor:GetChildren() do
			if not c:IsA("Model") then
				continue
			end
			local uid, id = string.match(c.Name, "^(%d+):([%w_]+):")
			local u = tonumber(uid)
			local def = if id then Buildings.byId[id] else nil
			if u == nil or id == nil or def == nil then
				continue
			end
			local work = Island.works(id)
			if not work and def.kind ~= "nest" then
				continue
			end
			local s = spots[u]
			if s == nil or s.model ~= c then
				local cf, size = c:GetBoundingBox()
				s = { uid = u, id = id, model = c, top = cf.Position + Vector3.new(0, size.Y / 2 + 0.4, 0), work = work, room = if work then Tuning.HelpMax else def.slots, n = 0 }
				spots[u] = s
			end
			seen[u] = true
		end
	end
	for u in spots do
		if not seen[u] then
			spots[u] = nil
		end
	end
	table.clear(pickList)
	for _, sp in spots do
		table.insert(pickList, sp.model)
	end
	if decor then
		for _, c in decor:GetChildren() do
			if c:IsA("Model") and c:GetAttribute("Decor") == "tree" then
				table.insert(pickList, c)
			end
		end
	end
	for _, s in spots do
		s.n = 0
	end
	for _, pal in v.pals do
		local w = spots[pal.work]
		if w and w.work then
			w.n += 1
		end
		local h = spots[pal.home]
		if h and not h.work then
			h.n += 1
		end
	end
end

-- The words of a building's card and its alert.
local function fullness(s: Spot): string
	return string.format(if s.work then "Workers %d/%d" else "Living here %d/%d", s.n, s.room)
end
-- ("Empty" over both: the user's words of 2026-11-14, "Make it say "Empty" instead of no one home or no workers")
local function alertWords(_s: Spot): string
	return "Empty"
end

local function dropAlert(u: number)
	local f = alerts[u]
	if f then
		f:Destroy()
		alerts[u] = nil
	end
end

local function dropCard()
	local c = card
	if c then
		c:Destroy()
	end
	card, cardUid, cardUntil = nil, 0, 0
end

-- The card over spot s: its name over how full it is, rebuilt when the words change.
local function showCard(s: Spot)
	local def = Buildings.byId[s.id]
	local name = if def then def.name else s.id
	local line = fullness(s)
	local c = card
	if c and cardUid == s.uid and c:GetAttribute("Words") == name .. "|" .. line then
		return
	end
	if c then
		c:Destroy()
	end
	local w = math.max(UIKit.textWidth(name), 13 + UIKit.textWidth(line)) + 2 * UIKit.PAD
	local f = UIKit.glass(UIKit.canvas("World"), UDim2.fromOffset(w, 26), nil, 2)
	f.Name = "BuildingCard"
	f.ZIndex = 6
	f:SetAttribute("Words", name .. "|" .. line)
	f:SetAttribute("Uid", s.uid)
	UIKit.text(f, name, UDim2.fromOffset(w - 2 * UIKit.PAD, 10), UDim2.fromOffset(UIKit.PAD, 2), { color = UIKit.color("accent"), name = "Name", z = 7 })
	PixelSprites.image(f, if s.work then "mini_work" else "mini_nest", UDim2.fromOffset(UIKit.PAD - 1, 13), 7)
	local full = s.n >= s.room
	UIKit.text(f, line, UDim2.fromOffset(w - 2 * UIKit.PAD - 13, 10), UDim2.fromOffset(UIKit.PAD + 12, 13), { color = UIKit.color(if s.n == 0 then "bad" elseif full then "good" else "text"), name = "Line", z = 7 })
	card, cardUid = f, s.uid
end

-- The alert over spot s (made once; the words stay).
local function alertFor(s: Spot): Frame
	local old = alerts[s.uid]
	if old then
		return old
	end
	local words = alertWords(s)
	local w = 13 + UIKit.textWidth(words) + 2 * UIKit.PAD - 1
	local f = UIKit.glass(UIKit.canvas("World"), UDim2.fromOffset(w, 15), nil, 2)
	f.Name = "BuildingAlert"
	f.ZIndex = 5
	f:SetAttribute("Uid", s.uid)
	PixelSprites.image(f, "mini_alert", UDim2.fromOffset(UIKit.PAD - 2, 2), 6)
	UIKit.text(f, words, UDim2.fromOffset(w - 13 - UIKit.PAD, 10), UDim2.fromOffset(UIKit.PAD + 10, 2), { color = UIKit.color("text"), name = "Words", z = 6 })
	alerts[s.uid] = f
	return f
end

-- Puts a frame centred over a world point, `up` UI px above it; hidden off the screen.
local function place(f: GuiObject, at: Vector3, up: number)
	local x, y, on = PixelRenderer.projectPixel(at)
	f.Visible = on
	if on then
		f.Position = UDim2.fromOffset(x - math.floor(f.Size.X.Offset / 2), y - f.Size.Y.Offset - up)
	end
end

-- The own building under a screen point (InputObject.Position): the model the ray meets first, if it is one of ours.
local function spotAt(pos: Vector2): Spot?
	local decor = decorOf
	if decor == nil or CameraController.stage() ~= nil then
		return nil
	end
	local origin, dir = PixelRenderer.screenRay(pos)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = pickList
	params.CollisionGroup = "PixelRays"
	local hit = workspace:Raycast(origin, dir, params)
	lastHit = if hit then hit.Instance:GetFullName() else "nothing"
	if hit == nil then
		return nil
	end
	local inst: Instance? = hit.Instance
	while inst and inst.Parent ~= decor do
		inst = inst.Parent
	end
	if inst == nil then
		return nil
	end
	for _, s in spots do
		if s.model == inst then
			return s
		end
	end
	return nil
end

-- A tap on the world (WorldView, after the eggs, the driftlings, the tree and the Hatchery): on one of the own
-- workplaces or huts, its card for a few seconds. True when it showed one.
function BuildingTags.tapAt(pos: Vector2): boolean
	local s = spotAt(pos)
	if s == nil then
		return false
	end
	showCard(s)
	cardUntil = os.clock() + CARD_SECS
	return true
end

-- Every frame: the alerts over the empty buildings, the card over the one under the pointer (or tapped).
function BuildingTags.step(t: number, plot: number, hoverPos: Vector2?, palHovered: boolean)
	local v = StateClient.view()
	if plot ~= plotNow then
		plotNow = plot
		table.clear(spots)
		for u in alerts do
			dropAlert(u)
		end
		dropCard()
		scanAt = 0
	end
	if v and t >= scanAt then
		scanAt = t + SCAN_SECS
		scan(v)
	end
	local busy = CameraController.stage() ~= nil
	-- the alerts (none while a panel is open: they showed faintly through its glass)
	local hidden = busy or UIKit.currentPanel() ~= nil
	local bob = if math.floor(t * 2) % 2 == 0 then 0 else 1
	for u, s in spots do
		if s.n == 0 and s.room > 0 and not hidden then
			place(alertFor(s), s.top, 2 + bob)
		else
			dropAlert(u)
		end
	end
	for u in alerts do
		if spots[u] == nil then
			dropAlert(u)
		end
	end
	-- the card: a tap's while it lasts, else the pointer's (a mouse, no panel, not Build mode, no driftling under it)
	if t >= hoverAt then
		hoverAt = t + HOVER_SECS
		local hp = hoverPos
		local ok = hp ~= nil and UserInputService.MouseEnabled and not palHovered and UIKit.currentPanel() == nil and not CameraController.isFree() and not busy
		local s = if ok and hp then spotAt(hp) else nil
		hoverUid = if s then s.uid else 0
	end
	local want = 0
	if cardUntil > 0 then
		if t < cardUntil and UIKit.currentPanel() == nil and not busy then
			want = cardUid
		else
			cardUntil = 0
		end
	end
	if want == 0 then
		want = hoverUid
	end
	local s = spots[want]
	if s == nil then
		if card then
			dropCard()
		end
		return
	end
	local keep = cardUntil
	showCard(s)
	cardUntil = keep
	local c = card :: Frame
	-- (the card sits over the alert when there is one, kept on the screen and below the top bar's chips)
	place(c, s.top, if alerts[s.uid] then 19 else 2)
	if c.Visible then
		local size = UIKit.size("World")
		-- (the World canvas is full screen, the HUD's starts under the top bar's inset)
		local top = math.ceil(UIKit.canvasOrigin("Hud").Y / UIKit.P()) + CARD_TOP
		local x = math.clamp(c.Position.X.Offset, 2, math.max(2, size.X - c.Size.X.Offset - 2))
		local y = math.clamp(c.Position.Y.Offset, top, math.max(top, size.Y - c.Size.Y.Offset - 2))
		c.Position = UDim2.fromOffset(x, y)
	end
end

-- Sims and previews: each workplace and hut of the own island (its uid, piece id, whether it is a workplace, how many
-- work or live there of its room) with the point a tap on its middle would have (an InputObject's: below the top bar),
-- nil when off the screen.
function BuildingTags.debugSpots(): { { uid: number, id: string, work: boolean, n: number, room: number, tap: Vector2? } }
	local out = {}
	local inset = game:GetService("GuiService"):GetGuiInset()
	for _, s in spots do
		local cf = s.model:GetBoundingBox()
		local at, on = PixelRenderer.project(cf.Position)
		table.insert(out, { uid = s.uid, id = s.id, work = s.work, n = s.n, room = s.room, tap = if on then Vector2.new(at.X - inset.X, at.Y - inset.Y) else nil })
	end
	table.sort(out, function(a, b): boolean
		return a.uid < b.uid
	end)
	return out
end

-- Sims and previews: the own island's workplaces and huts, the alerts showing and the card's words.
function BuildingTags.debugState(): { spots: number, alerts: number, words: { string }, card: string, cardUid: number, hit: string }
	local words: { string } = {}
	local n = 0
	for _, f in alerts do
		n += 1
		local l = f:FindFirstChild("Words")
		if l and l:IsA("TextLabel") then
			table.insert(words, l.Text)
		end
	end
	table.sort(words)
	local count = 0
	for _ in spots do
		count += 1
	end
	local c = card
	local line = if c then c:FindFirstChild("Line") else nil
	local nm = if c then c:FindFirstChild("Name") else nil
	return {
		spots = count,
		alerts = n,
		words = words,
		card = if c and line and line:IsA("TextLabel") and nm and nm:IsA("TextLabel") then nm.Text .. " " .. line.Text else "",
		cardUid = cardUid,
		hit = lastHit,
	}
end

return BuildingTags
