--!strict
-- How full the own island's buildings are (GAME_DESIGN 4.6; docs/ARCHITECTURE.md 10.2). The request of 2026-11-14:
-- "show capacities of work buildings when hovered over. if noone is working on a building, make a alert on top of said
-- work building stating so. do the same for huts and housing".
--   The card: with a mouse, a workplace or a hut under the pointer gets a small glass card over its roof, its name in
--   the accent and how full it is ("Workers 1/2", "Living here 2/2"); a tap on one shows the same card for a few
--   seconds (a phone has no pointer). One card at a time, nothing while a panel is open or in Build mode.
--   The request of 2026-11-15: "when hovering over a boost building, show how much the total boosts of the certain of
--   building it is boosting with all other same type boost buildings together. also, while hovering over a work
--   building, show how much it is earning". So a workplace's card says what it earns a minute too (Island.output, times
--   the view's charm bonus and income multiplier), and a boost building gets a card of its own: the boost at its knack
--   from every boost building there together ("Farms +15% from 2 boost buildings", Island.boostInfo; an "all" one,
--   the "all" boosts together) and what one more of its kind would add (they stack, less each time: Tuning.BoostStack).
--   No alerts over empty buildings any more: the request of 2026-11-17, "remove the empty alert that appears above
--   huts and work places" (they said "Empty" over every workplace nobody worked at and every hut nobody lived in).
-- Only the own island's: the card on the Popup root over the HUD (nothing while the camera has a stage). WorldView drives it: step every
-- frame, hover from the pointer, tapAt from a tap.
--   step(t, plot, hoverPos?, palHovered), tapAt(pos) -> boolean, debugState(), debugSpots()
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Buildings = require(ReplicatedStorage.Shared.Data.Buildings)
local Island = require(ReplicatedStorage.Shared.Logic.Island)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
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

-- One building of the own island that houses, employs or boosts: its uid, piece id, model, the point over its roof
-- (world), what it is ("work", "nest" or "boost"; `work` true for a workplace), its room (0 for a boost building), how
-- many work or live there now, and its card's other lines (a workplace's earnings, a boost building's two lines).
type Spot = { uid: number, id: string, model: Model, top: Vector3, work: boolean, kind: string, room: number, n: number, extra: { string } }

local spots: { [number]: Spot } = {}
local plotNow = 0
local scanAt = 0
local decorOf: Instance? = nil
local pickList: { Instance } = {} -- what the pointer's ray may meet: the workplaces, the huts and the tree (decor in
-- front of a hut, a bench or a lamp, never hides it; the tree does)
local card: Frame? = nil
local cardUid = 0
local cardUntil = 0 -- a tap's card: shown till then (0: the pointer's)
local hoverUid = 0
local hoverAt = 0
local lastHit = "" -- what the last pick ray met (debugState)

-- A boost building's knack in words, and a share as a percentage (whole, or to a tenth).
local KNACK_WORD: { [string]: string } = { farm = "Farms", wood = "Wood", shop = "Shops", all = "Everything" }
local function pct(x: number): string
	local v = math.floor(x * 1000 + 0.5) / 10
	return if v == math.floor(v) then string.format("%d%%", v) else string.format("%.1f%%", v)
end

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
			local boost = def.kind == "gen" and def.boost ~= ""
			if not work and not boost and def.kind ~= "nest" then
				continue
			end
			local s = spots[u]
			if s == nil or s.model ~= c then
				local cf, size = c:GetBoundingBox()
				local kind = if work then "work" elseif boost then "boost" else "nest"
				s = { uid = u, id = id, model = c, top = cf.Position + Vector3.new(0, size.Y / 2 + 0.4, 0), work = work, kind = kind, room = if work then Tuning.HelpMax elseif boost then 0 else def.slots, n = 0, extra = {} }
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
		if h and h.kind == "nest" then
			h.n += 1
		end
	end
	-- the cards' other lines: what each workplace earns a minute, what each boost building's knack gets from them all
	local prof: any = { plot = { placed = v.pieces }, pals = v.pals, tier = v.tier }
	local made = Island.output(prof)
	local mult = (1 + (v.charmBonus or 0)) * (v.incomeMult or 1) * 60 / Tuning.TurnSeconds
	for _, s in spots do
		if s.kind == "work" then
			s.extra = { string.format("Earns %s shells/min", Numbers.short(math.floor((made[s.uid] or 0) * mult + 0.5))) }
		elseif s.kind == "boost" then
			local b = Island.boostInfo(prof, s.id)
			local first = string.format("%s +%s from %d boost building%s", KNACK_WORD[b.knack] or "Everything", pct(b.total), b.count, if b.count == 1 then "" else "s")
			local second = if b.raw >= Tuning.BoostMax - 1e-9 then string.format("Boosts top out at %s", pct(Tuning.BoostMax)) else string.format("One more adds +%s", pct(b.more))
			s.extra = { first, second }
		else
			s.extra = {}
		end
	end
end

-- The words of a building's card.
local function fullness(s: Spot): string
	return string.format(if s.work then "Workers %d/%d" else "Living here %d/%d", s.n, s.room)
end

local function dropCard()
	local c = card
	if c then
		c:Destroy()
	end
	card, cardUid, cardUntil = nil, 0, 0
end

-- The card over spot s: its name over its lines (a workplace: how full, what it earns; a hut: how full; a boost
-- building: the boost at its knack, what one more adds), each with its icon, rebuilt when the words change.
local function showCard(s: Spot)
	local def = Buildings.byId[s.id]
	local name = if def then def.name else s.id
	type Line = { icon: string, text: string, color: string }
	local lines: { Line } = {}
	if s.kind == "boost" then
		table.insert(lines, { icon = "mini_boost", text = s.extra[1] or "", color = "good" })
		table.insert(lines, { icon = "mini_star", text = s.extra[2] or "", color = "text_dim" })
	else
		local full = s.n >= s.room
		table.insert(lines, { icon = if s.work then "mini_work" else "mini_nest", text = fullness(s), color = if s.n == 0 then "bad" elseif full then "good" else "text" })
		if s.work and s.extra[1] then
			table.insert(lines, { icon = "mini_shell", text = s.extra[1], color = "text" })
		end
	end
	local words = name
	for _, l in lines do
		words ..= "|" .. l.text
	end
	local c = card
	if c and cardUid == s.uid and c:GetAttribute("Words") == words then
		return
	end
	if c then
		c:Destroy()
	end
	local w = UIKit.textWidth(name)
	for _, l in lines do
		w = math.max(w, 13 + UIKit.textWidth(l.text))
	end
	w += 2 * UIKit.PAD
	-- (on the Popup root, over the HUD's cards: on a phone a building near the edge put its card under them)
	local f = UIKit.glass(UIKit.canvas("Popup"), UDim2.fromOffset(w, 16 + 10 * #lines), nil, 2)
	-- (nearly solid: it can sit over the HUD's cards)
	UIKit.setPlate(f, nil, 0.1)
	f.Name = "BuildingCard"
	f.ZIndex = 6
	f:SetAttribute("Words", words)
	f:SetAttribute("Uid", s.uid)
	UIKit.text(f, name, UDim2.fromOffset(w - 2 * UIKit.PAD, 10), UDim2.fromOffset(UIKit.PAD, 2), { color = UIKit.color("accent"), name = "Name", z = 7 })
	for i, l in lines do
		local y = 13 + (i - 1) * 10
		PixelSprites.image(f, l.icon, UDim2.fromOffset(UIKit.PAD - 1, y), 7)
		UIKit.text(f, l.text, UDim2.fromOffset(w - 2 * UIKit.PAD - 13, 10), UDim2.fromOffset(UIKit.PAD + 12, y), { color = UIKit.color(l.color), name = if i == 1 then "Line" else "Line" .. i, z = 7 })
	end
	card, cardUid = f, s.uid
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

-- Every frame: the card over the building under the pointer (or tapped).
function BuildingTags.step(t: number, plot: number, hoverPos: Vector2?, palHovered: boolean)
	local v = StateClient.view()
	if plot ~= plotNow then
		plotNow = plot
		table.clear(spots)
		dropCard()
		scanAt = 0
	end
	if v and t >= scanAt then
		scanAt = t + SCAN_SECS
		scan(v)
	end
	local busy = CameraController.stage() ~= nil
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
	-- (the card sits just over the roof, kept on the screen and below the top bar's chips; worked out on the World
	-- canvas, which is full screen, then moved onto the Popup root's, which starts under the top bar's inset)
	place(c, s.top, 2)
	if c.Visible then
		local d = (UIKit.canvasOrigin("Popup") - UIKit.canvasOrigin("World")) / UIKit.P()
		local size = UIKit.size("Popup")
		local x = math.clamp(c.Position.X.Offset - math.floor(d.X + 0.5), 2, math.max(2, size.X - c.Size.X.Offset - 2))
		local y = math.clamp(c.Position.Y.Offset - math.floor(d.Y + 0.5), CARD_TOP, math.max(CARD_TOP, size.Y - c.Size.Y.Offset - 2))
		c.Position = UDim2.fromOffset(x, y)
	end
end

-- Sims and previews: each workplace and hut of the own island (its uid, piece id, whether it is a workplace, how many
-- work or live there of its room) with the point a tap on its middle would have (an InputObject's: below the top bar),
-- nil when off the screen.
function BuildingTags.debugSpots(): { { uid: number, id: string, work: boolean, kind: string, n: number, room: number, tap: Vector2? } }
	local out = {}
	local inset = game:GetService("GuiService"):GetGuiInset()
	for _, s in spots do
		local cf = s.model:GetBoundingBox()
		local at, on = PixelRenderer.project(cf.Position)
		table.insert(out, { uid = s.uid, id = s.id, work = s.work, kind = s.kind, n = s.n, room = s.room, tap = if on then Vector2.new(at.X - inset.X, at.Y - inset.Y) else nil })
	end
	table.sort(out, function(a, b): boolean
		return a.uid < b.uid
	end)
	return out
end

-- Sims and previews: the own island's workplaces and huts, the alerts showing (none since 2026-11-17: any tag left
-- named BuildingAlert in the World root counts) and the card's words.
function BuildingTags.debugState(): { spots: number, alerts: number, words: { string }, card: string, card2: string, cardUid: number, hit: string }
	local words: { string } = {}
	local n = 0
	for _, f in UIKit.canvas("World"):GetDescendants() do
		if f.Name == "BuildingAlert" then
			n += 1
			local l = f:FindFirstChild("Words")
			if l and l:IsA("TextLabel") then
				table.insert(words, l.Text)
			end
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
	local line2 = if c then c:FindFirstChild("Line2") else nil
	return {
		spots = count,
		alerts = n,
		words = words,
		card = if c and line and line:IsA("TextLabel") and nm and nm:IsA("TextLabel") then nm.Text .. " " .. line.Text else "",
		card2 = if line2 and line2:IsA("TextLabel") then line2.Text else "",
		cardUid = cardUid,
		hit = lastHit,
	}
end

return BuildingTags
