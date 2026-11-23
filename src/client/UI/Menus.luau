--!strict
-- The HUD's panels (docs/ARCHITECTURE.md 10.4; GAME_DESIGN 5-9): Driftlings (every one: where each lives and works,
-- moving and selling), the Tree of Life (its eggs with their prices, when it lays the next, the odds; every hut full, the swap
-- picker), the Hatchery (two parents, an egg) and Index (every driftling seen); Looks is UI/StoreUI's. Every
-- action is a request; the panel rebuilds from the next view. The work picker is the same panel with an argument
-- ({ pal = id }), the hut picker too ({ move = id }), the swap picker the tree's ({ hatch = id }).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Buildings = require(ReplicatedStorage.Shared.Data.Buildings)
local Creatures = require(ReplicatedStorage.Shared.Data.Creatures)
local Islets = require(ReplicatedStorage.Shared.Data.Islets)
local Traits = require(ReplicatedStorage.Shared.Data.Traits)
local WeatherData = require(ReplicatedStorage.Shared.Data.Weather)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local Island = require(ReplicatedStorage.Shared.Logic.Island)
local Tree = require(ReplicatedStorage.Shared.Logic.Tree)
local Breed = require(ReplicatedStorage.Shared.Logic.Breed)
local Lang = require(ReplicatedStorage.Shared.Locale.Lang)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local EggView = require(script.Parent.Parent.Controllers.EggView)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local TierStars = require(script.Parent.TierStars)
local Words = require(script.Parent.Words)
local StoreUI = require(script.Parent.StoreUI)
local PalTip = require(script.Parent.PalTip)
local RunService = game:GetService("RunService")

local Menus = {}

local hatcheries: (v: Types.ClientView) -> { Types.Piece } -- (the Hatchery's, below)

-- Ask the server; tell the player when it says no.
local function ask(action: string, payload: { [string]: any }?, ok: string?): Types.Response
	local res = StateClient.request(action, payload)
	if res.ok then
		if ok then
			UIKit.notice(ok, UIKit.color("good"))
		end
	else
		Audio.play("deny")
		UIKit.notice(Words.errText(res.err), UIKit.color("bad"))
	end
	return res
end

-- A panel's hint over its list: one line, or up to three when it is too long for the panel (it never runs off the edge).
-- Returns where the list under it starts.
local function hint(body: Instance, text: string, w: number): number
	-- (up to three lines, 10 px apart)
	local n = math.clamp(UIKit.lines(text, w), 1, 3)
	local h = 2 + 10 * n
	UIKit.text(body, text, UDim2.fromOffset(w, h), UDim2.fromOffset(0, 0), { color = UIKit.color("text_dim"), name = "Hint", wrap = n > 1 })
	return h + 2
end

-- A driftling's mutations in a line (Data/Traits): each name in its tier's colour with its stars; "No mutations".
local function mutLine(parent: Instance, muts: { string }, x: number, y: number, w: number)
	if #muts == 0 then
		UIKit.text(parent, "No mutations", UDim2.fromOffset(w, 10), UDim2.fromOffset(x, y), { color = UIKit.color("text_dim"), z = 4, name = "Muts" })
		return
	end
	local cx = x
	for i, id in muts do
		local m = Traits.byId[id]
		if m then
			local suffix = if i < #muts then "," else nil
			local lw = TierStars.measure(m.name, m.tier, suffix)
			if cx + lw > x + w then
				break
			end
			TierStars.label(parent, m.name, m.tier, cx, y, { z = 4, name = "Mut_" .. id, suffix = suffix })
			cx += lw + 5
		end
	end
end

-- A row of a panel's list: a faint veil over the panel's glass (the look since 2026-11-14), 2 px from the next.
local function row(list: Instance, order: number, h: number): Frame
	local f = UIKit.row(list, UDim2.new(1, -6, 0, h), nil)
	f.Name = "Row"
	f.LayoutOrder = order
	return f
end

-- The view as a profile for the shared rules that read the island (Logic/Island, Logic/Tree).
local function asProfile(v: Types.ClientView): any
	return { plot = { placed = v.pieces }, pals = v.pals, tier = v.tier, shells = v.shells, boosts = v.boosts }
end

-- A driftling's portrait is 32 x 32 (drawn from its model: scripts/gen_art.py), at 4 px in a row: the row's words start
-- right of it.
local PX = 40

local function pieceOf(v: Types.ClientView, uid: number): Types.Piece?
	for _, q in v.pieces do
		if q.uid == uid then
			return q
		end
	end
	return nil
end

local function buildingName(v: Types.ClientView, uid: number): string?
	local q = pieceOf(v, uid)
	local d = if q then Buildings.byId[q.id] else nil
	return if d then d.name else nil
end

-- A two-tap button (Sell): the first tap asks "Sure?", a second within 3 s does it.
local function confirmButton(parent: Instance, text: string, size: UDim2, pos: UDim2, go: () -> (), name: string)
	local armed = 0
	local b: TextButton
	b = UIKit.button(parent, text, size, pos, function()
		if os.clock() - armed < 3 then
			go()
		else
			armed = os.clock()
			UIKit.setButtonText(b, "Sure?")
			Audio.play("notice")
			task.delay(3, function()
				if b.Parent and os.clock() - armed >= 3 then
					UIKit.setButtonText(b, text)
				end
			end)
		end
	end, { name = name, color = UIKit.color("button_warn") })
	b.ZIndex = 4
end

-- How fast a driftling works ("Works x2.8": its rarity's speed and its work share, the same at every workplace since
-- 2026-11-19, Logic/Tree.worth).
local function workWord(x: Types.Pal): string
	return string.format("Works x%.1f", Tree.worth(x))
end

------------------------------------------------------------------ the work picker
-- Every workplace on the island (any driftling works anywhere: the request of 2026-11-13; one kind of work since
-- 2026-11-19, so it works as fast at each), the best first (its rate and level: what this one makes there a minute),
-- the one there now, and Rest.
local function buildPicker(body: Frame, v: Types.ClientView, palId: number, back: string, backArg: any?)
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local me: Types.Pal? = nil
	local name = "?"
	local current = 0
	for _, x in v.pals do
		if x.id == palId then
			local d = Creatures.byId[x.sp]
			name = if d then d.name else x.sp
			current = x.work
			me = x
		end
	end
	local pinned = me ~= nil and me.pin == true
	local top = hint(body, string.format("Where should %s work?", name), W - 50)
	UIKit.button(body, "Back", UDim2.fromOffset(44, 12), UDim2.fromOffset(W - 44, 0), function()
		UIKit.openPanel(back, backArg)
	end, { name = "Back", color = UIKit.color("plate_light") })
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - top), UDim2.fromOffset(0, top))
	UIKit.vlist(list, 2)
	local order = 0
	local function choose(uid: number)
		local res = ask("pal.work", { id = palId, uid = uid })
		if res.ok then
			Audio.play("ding")
			UIKit.openPanel(back, backArg)
		end
	end
	-- Auto first: it works wherever it makes the most and moves by itself when the island changes (Island.arrange;
	-- the request of 2026-11-14). Picking a spot below keeps it there instead.
	do
		order += 1
		local f = row(list, order, 22)
		f.Name = "Auto"
		UIKit.text(f, "Auto: its best spot", UDim2.new(1, -90, 0, 10), UDim2.fromOffset(6, 1), { color = UIKit.color("accent"), z = 4 })
		UIKit.text(f, if pinned then "You picked this. Auto moves it for you." else "On. It moves when you build or hatch.", UDim2.new(1, -90, 0, 10), UDim2.fromOffset(6, 11), { color = UIKit.color("text_dim"), z = 4 })
		-- ("On@@auto": Auto is on, a status, apart from Settings' On button: Locale/Lang)
		UIKit.button(f, if pinned then "Auto" else "On@@auto", UDim2.fromOffset(60, 14), UDim2.new(1, -64, 0, 4), function()
			local res = ask("pal.auto", { id = palId })
			if res.ok then
				Audio.play("ding")
				UIKit.openPanel(back, backArg)
			end
		end, { name = "Go_auto", color = UIKit.color("button_ok"), enabled = pinned }).ZIndex = 4
	end
	-- the workplaces with what this one makes at each a minute (its speed is the same everywhere), the best first
	local spots: { { q: Types.Piece, d: any, speed: number, k: number } } = {}
	local worth = if me then Tree.worth(me) * Tuning.PalWork else Tuning.PalWork
	for i, q in v.pieces do
		local d = Buildings.byId[q.id]
		if d and Island.works(q.id) then
			table.insert(spots, { q = q, d = d, speed = d.rate * (Tuning.UpgradeMult[q.lvl or 1] or 1) * worth * 60 / Tuning.TurnSeconds, k = i })
		end
	end
	table.sort(spots, function(a, b)
		if math.abs(a.speed - b.speed) > 1e-9 then
			return a.speed > b.speed
		end
		return a.k < b.k
	end)
	local fastest = if #spots > 0 then spots[1].speed else 0
	for _, sp in spots do
		local q, d = sp.q, sp.d
		order += 1
		local f = row(list, order, 22)
		f.Name = "Spot_" .. q.uid
		-- (by how its workers look at work: a farm's veggies, a shop's shell, a wood building's tools)
		local icon = if d.act == "shop" then "coin" elseif d.act == "farm" then "food" else "work"
		PixelSprites.image(f, "mini_" .. (if PixelSprites.has("mini_" .. icon) then icon else "work"), UDim2.fromOffset(4, 5), 4)
		UIKit.text(f, d.name .. (if q.lvl > 1 then " Lv" .. q.lvl else ""), UDim2.new(1, -124, 0, 10), UDim2.fromOffset(18, 1), { color = UIKit.color("text"), z = 4 })
		-- (its `jobs` a building; one more sends the first there back to rest)
		local n = 0
		for _, x in v.pals do
			if x.work == q.uid and x.id ~= palId then
				n += 1
			end
		end
		local full = n >= d.jobs
		local status = if q.uid == current then "Here now" elseif full then "Full: bumps one to rest" elseif n > 0 then string.format("%d of %d working", n, d.jobs) else "Nobody yet"
		UIKit.text(f, status, UDim2.new(1, -124, 0, 10), UDim2.fromOffset(18, 11), { color = if status == "Nobody yet" then UIKit.color("good") else UIKit.color("text_dim"), z = 4 })
		-- what it would make here a minute (before the boosts and charm): the best in the accent colour
		UIKit.text(f, Numbers.short(math.floor(sp.speed + 0.5)) .. "/min", UDim2.fromOffset(40, 10), UDim2.new(1, -108, 0, 6), { x = "right", color = if sp.speed >= fastest - 1e-9 then UIKit.color("accent") else UIKit.color("text_dim"), z = 4, name = "Speed" })
		local b = UIKit.button(f, if q.uid == current then "Here" elseif full then "Swap" else "Go", UDim2.fromOffset(60, 14), UDim2.new(1, -64, 0, 4), function()
			choose(q.uid)
		end, { name = "Go_" .. q.uid, color = UIKit.color("button_ok"), enabled = q.uid ~= current })
		b.ZIndex = 4
	end
	if #spots == 0 then
		order += 1
		local f = row(list, order, 22)
		UIKit.text(f, "No workplaces yet. Build one first.", UDim2.new(1, -10, 1, -4), UDim2.fromOffset(5, 2), { color = UIKit.color("text_dim"), z = 4, wrap = true })
	end
	local f = row(list, order + 1, 22)
	f.Name = "Rest"
	UIKit.text(f, "Rest in its hut", UDim2.new(1, -90, 0, 10), UDim2.fromOffset(6, 6), { color = UIKit.color("text"), z = 4 })
	UIKit.button(f, "Rest", UDim2.fromOffset(60, 14), UDim2.new(1, -64, 0, 4), function()
		choose(0)
	end, { name = "Go_0", enabled = current ~= 0 or not pinned }).ZIndex = 4
end

------------------------------------------------------------------ the Hatchery
-- (GAME_DESIGN 6.1; Logic/Breed) Each Hatchery standing: its egg (the rarity's egg, the turns left, its parents), or
-- two parents to pick (a picker of the driftlings at home), what they would likely hatch (its kind if met, else its
-- shape, and its rarity), its price and the turns it takes, and Breed.
type Pick = { a: number?, b: number? }
local breedPick: { [number]: Pick } = {}

hatcheries = function(v: Types.ClientView): { Types.Piece }
	local out: { Types.Piece } = {}
	for _, q in v.pieces do
		local b = Buildings.byId[q.id]
		if b and b.kind == "breed" then
			table.insert(out, q)
		end
	end
	return out
end

local function palById(v: Types.ClientView, id: number?): Types.Pal?
	for _, x in v.pals do
		if x.id == id then
			return x
		end
	end
	return nil
end

-- The parent picker's search and order (the request of 2026-11-19: "for hatchery, make a search function, and a sort
-- by mutation rarity or creature rarity"). Both stay while the game runs, so the second parent's list opens the way the
-- first one's was left.
local pickQuery = ""
-- the picker's search box (kept across rebuilds) and the list its typing fills now
local pickSearch: Frame? = nil
local pickFill: (() -> ())? = nil
local pickSort = "rarity" -- "rarity": the rarest kind first; "muts": the rarest mutations first

-- A driftling's mutations as tiers, the highest first (the key the mutation order compares).
local function mutTiers(x: Types.Pal): { number }
	local out: { number } = {}
	for _, id in Traits.clean(x.muts) do
		local m = Traits.byId[id]
		if m then
			table.insert(out, m.tier)
		end
	end
	table.sort(out, function(a, b)
		return a > b
	end)
	return out
end

-- Whose mutations are rarer: the highest tier decides, then the next, then whoever has more. -1: a's, 1: b's, 0: even.
local function cmpMuts(a: { number }, b: { number }): number
	for i = 1, math.max(#a, #b) do
		local x, y = a[i] or 0, b[i] or 0
		if x ~= y then
			return if x > y then -1 else 1
		end
	end
	return 0
end

-- What the search looks through: the kind's name, its rarity, its passive and its mutations' names, in lower case, in
-- English and in the language on show.
local function searchWords(x: Types.Pal, d: any): string
	local rar = Traits.RARITY[d.rarity] or Traits.RARITY[1]
	local words = { d.name, rar.name, d.passive.name }
	for _, id in Traits.clean(x.muts) do
		local m = Traits.byId[id]
		if m then
			table.insert(words, m.name)
		end
	end
	if Lang.code() ~= "en" then
		for i = 1, #words do
			table.insert(words, Lang.t(words[i]))
		end
	end
	return string.lower(table.concat(words, " "))
end

-- The driftlings the picker lists for a search and an order (not the other parent): the rarest first by the order
-- picked, the other order breaking ties, then by name and the oldest first. Sims read it too.
local function parentList(v: Types.ClientView, other: number?, q: string, sort: string): { Types.Pal }
	type Entry = { x: Types.Pal, d: any, tiers: { number } }
	local found: { Entry } = {}
	for _, x in v.pals do
		local d = Creatures.byId[x.sp]
		if d == nil or x.id == other then
			continue
		end
		if q ~= "" and string.find(searchWords(x, d), q, 1, true) == nil then
			continue
		end
		table.insert(found, { x = x, d = d, tiers = mutTiers(x) })
	end
	table.sort(found, function(a, b)
		local byMuts = cmpMuts(a.tiers, b.tiers)
		if sort == "muts" and byMuts ~= 0 then
			return byMuts < 0
		end
		if a.d.rarity ~= b.d.rarity then
			return a.d.rarity > b.d.rarity
		end
		if byMuts ~= 0 then
			return byMuts < 0
		end
		if a.d.name ~= b.d.name then
			return a.d.name < b.d.name
		end
		return a.x.id < b.x.id
	end)
	local out: { Types.Pal } = {}
	for _, e in found do
		table.insert(out, e.x)
	end
	return out
end

-- The parent picker: the island's driftlings (not the other parent), each with its passive and mutations; a search box
-- and the two orders over the list. Typing or a new order fills the list again (the box stays, so the keyboard does
-- too).
local SORTS = { { id = "rarity", text = "Rarity" }, { id = "muts", text = "Mutations" } }
local function buildParentPicker(body: Frame, v: Types.ClientView, uid: number, slot: string)
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local top = hint(body, "Pick a parent. Its kind and mutations pass on.", W)
	local pick: Pick = breedPick[uid] or {}
	local other = if slot == "a" then pick.b else pick.a
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - top - 14), UDim2.fromOffset(0, top + 14))
	-- (the rows made only near what shows, UIKit.lazyList: every driftling on the island can be a parent)
	local lazy: UIKit.LazyList? = nil
	local function fill()
		if lazy then
			lazy.clear()
			lazy = nil
		end
		for _, c in list:GetChildren() do
			if c:IsA("GuiObject") or c:IsA("UIListLayout") then
				c:Destroy()
			end
		end
		list.CanvasPosition = Vector2.zero
		local shown = parentList(v, other, pickQuery, pickSort)
		local function parentRow(x: Types.Pal): GuiObject?
			local d = Creatures.byId[x.sp]
			if d == nil then
				return nil
			end
			local f = row(list, 0, 38)
			f.Name = "Parent_" .. x.id
			PalTip.attach(f, x)
			PixelSprites.image(f, "icon_" .. x.sp, UDim2.fromOffset(4, 3), 4)
			local rar = Traits.RARITY[d.rarity] or Traits.RARITY[1]
			UIKit.text(f, Lang.f("{1}  {2}", d.name, Lang.t(rar.name)), UDim2.fromOffset(W - 106, 10), UDim2.fromOffset(PX, 4), { color = UIKit.color(rar.color), z = 4 })
			UIKit.text(f, d.passive.name, UDim2.fromOffset(W - 106, 10), UDim2.fromOffset(PX, 14), { color = UIKit.color("accent"), z = 4 })
			mutLine(f, x.muts or {}, PX, 24, W - 106)
			UIKit.button(f, "Pick", UDim2.fromOffset(46, 13), UDim2.new(1, -50, 0, 10), function()
				local cur: Pick = breedPick[uid] or {}
				if slot == "a" then
					cur.a = x.id
				else
					cur.b = x.id
				end
				breedPick[uid] = cur
				Audio.play("pop")
				UIKit.openPanel("hatch")
			end, { name = "PickParent_" .. x.id, color = UIKit.color("button_ok") }).ZIndex = 4
			return f
		end
		if #shown > 0 then
			lazy = UIKit.lazyList(list, #shown, function(): number
				return 38
			end, function(i: number): GuiObject?
				return parentRow(shown[i])
			end, 2)
		else
			list.AutomaticCanvasSize = Enum.AutomaticSize.Y
			list.CanvasSize = UDim2.new()
			UIKit.vlist(list, 2)
			local f = row(list, 1, 24)
			f.Name = "NoParent"
			local words = if pickQuery ~= "" then "No match. Try a kind, rarity or mutation." else "No driftling to pick yet."
			UIKit.text(f, words, UDim2.new(1, -10, 1, -4), UDim2.fromOffset(5, 2), { color = UIKit.color("text_dim"), z = 4, wrap = true })
		end
	end
	-- the orders at the right ("Sort by" and a button each, the picked one teal), the search box in the room left
	local x = W
	local sortButtons: { [string]: TextButton } = {}
	for k = #SORTS, 1, -1 do
		local s = SORTS[k]
		local bw = UIKit.buttonWidth(s.text, 5)
		x -= bw
		sortButtons[s.id] = UIKit.button(body, s.text, UDim2.fromOffset(bw, 12), UDim2.fromOffset(x, top), function()
			if pickSort ~= s.id then
				pickSort = s.id
				Audio.play("pop")
				for id, b in sortButtons do
					UIKit.setButtonColor(b, if id == pickSort then UIKit.color("button") else UIKit.color("plate_light"))
				end
				fill()
			end
		end, { name = "Sort_" .. s.id, color = if pickSort == s.id then UIKit.color("button") else UIKit.color("plate_light") })
		x -= 2
	end
	local lead = "Sort by"
	local lw = UIKit.textWidth(lead) + 2
	x -= lw + 2
	UIKit.text(body, lead, UDim2.fromOffset(lw, 10), UDim2.fromOffset(x, top + 1), { color = UIKit.color("text_dim"), name = "SortLead" })
	-- (the box is kept while the sheet is rebuilt, as the Rewards' code box is: a view coming every turn rebuilt it and
	-- took the keyboard away mid-word. Its typing fills whichever list is up now.)
	pickFill = fill
	local sb = pickSearch
	if sb == nil or sb.Parent ~= body then
		if sb then
			sb:Destroy()
		end
		local nb = UIKit.searchBox(body, x - 6, UDim2.fromOffset(0, top), function(q: string)
			pickQuery = q
			local f = pickFill
			if f then
				f()
			end
		end, "PalSearch", pickQuery)
		nb:SetAttribute("Keep", true)
		pickSearch = nb
	else
		sb.Position = UDim2.fromOffset(0, top)
		sb.Size = UDim2.fromOffset(x - 6, 12)
	end
	fill()
end

-- Sims and previews: what the parent picker lists for a search and an order, and the order it opens with.
function Menus.debugParents(other: number?, q: string, sort: string): { number }
	local v = StateClient.view()
	local out: { number } = {}
	if v then
		for _, x in parentList(v, other, q, sort) do
			table.insert(out, x.id)
		end
	end
	return out
end

local function buildHatch(body: Frame, arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	if type(arg) == "table" and type(arg.hatch) == "number" and (arg.slot == "a" or arg.slot == "b") then
		buildParentPicker(body, v, arg.hatch, arg.slot)
		return
	end
	-- (no picker: its kept search box goes)
	local sb = pickSearch
	if sb then
		sb:Destroy()
		pickSearch, pickFill = nil, nil
	end
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	-- (eggs warming: Finish now, the Finish Hatcheries product, GAME_DESIGN 14)
	-- (the request of 2026-11-15: "say Breed two driftlings for an egg. also, specify what happens to the result, such
	-- as mutations and rarity": the rarity here, the mutations on each pair's line; Finish now in the first warming
	-- egg's row, so the words have the whole width)
	local warming = false
	local readyN = 0
	local allEggs: { Types.Egg } = v.eggs or {}
	for _, e in allEggs do
		if e.left > 0 then
			warming = true
		else
			readyN += 1
		end
	end
	local finishShown = false
	-- (two or more ready: Hatch all, the request of 2026-11-22: "and hatchery as well, make a open all hatchery eggs";
	-- no hatch scene for each, the Hatched panel shows them all: EggView.hatcheryAll)
	local allW = 0
	if readyN >= 2 then
		local allText = Lang.f("Hatch all ({1})", readyN)
		allW = math.max(70, UIKit.textWidth(allText) + 12)
		UIKit.button(body, allText, UDim2.fromOffset(allW, 13), UDim2.fromOffset(W - allW, 0), function()
			EggView.hatcheryAll()
		end, { name = "HatchAll", color = UIKit.color("button_ok") }).ZIndex = 4
		allW += 4
	end
	-- (the request of 2026-11-19: "In hatchery, show the resultant mutation combination the pet will have. Always take
	-- the highest tier mutations to combine with each other if possible": Logic/Breed.preview, shown before Breed)
	local top = hint(body, "Breed two driftlings for an egg. It gets their best mutations.", W - allW)
	if allW > 0 then
		top = math.max(top, 16)
	end
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - top), UDim2.fromOffset(0, top))
	UIKit.vlist(list, 2)
	local hs = hatcheries(v)
	if #hs == 0 then
		local f = row(list, 1, 24)
		UIKit.text(f, "Build a Hatchery to breed (Huts tab, island Lv3).", UDim2.new(1, -10, 1, -4), UDim2.fromOffset(5, 2), { color = UIKit.color("text_dim"), z = 4, wrap = true })
		return
	end
	for i, q in hs do
		local egg: Types.Egg? = nil
		local eggs: { Types.Egg } = v.eggs or {}
		for _, e in eggs do
			if e.uid == q.uid then
				egg = e
			end
		end
		local f = row(list, i, 66)
		f.Name = "Hatch_" .. q.uid
		if egg then
			-- an egg: its rarity's egg, the turns left (a bar), its parents
			local d = Creatures.byId[egg.sp]
			local r = if d then d.rarity else 1
			local rar = Traits.RARITY[r] or Traits.RARITY[1]
			PixelSprites.image(f, "egg_" .. r, UDim2.fromOffset(5, 6), 4)
			UIKit.text(f, rar.name, UDim2.fromOffset(W - 40, 10), UDim2.fromOffset(26, 2), { color = UIKit.color(rar.color), z = 4, name = "EggName" })
			local _, total = Breed.cost(egg.sp, asProfile(v))
			-- (in minutes or hours: its turns left, Tuning.TurnSeconds each while you are on the island; ready, it waits
			-- for Hatch here or a tap on the Hatchery: the request of 2026-11-20)
			local ready = egg.left <= 0
			local line = if ready then "Ready to hatch." else "Hatches in " .. Numbers.duration(StateClient.eggLeft(egg))
			UIKit.text(f, line, UDim2.fromOffset(W - 40, 10), UDim2.fromOffset(26, 12), { color = if ready then UIKit.color("good") else UIKit.color("text"), z = 4, name = "EggLeft" })
			local bw = math.min(140, W - 40)
			local back = UIKit.rect(f, UDim2.fromOffset(bw, 4), UDim2.fromOffset(26, 24), UIKit.color("glass"), 4)
			back.BackgroundTransparency = 0.25
			back.Name = "EggBar"
			local done = math.clamp(1 - egg.left / math.max(1, total), 0, 1)
			UIKit.rect(back, UDim2.fromOffset(math.floor((bw - 2) * done), 2), UDim2.fromOffset(1, 1), UIKit.color("pink"), 5)
			local pa, pb = palById(v, egg.a), palById(v, egg.b)
			local function nm(x: Types.Pal?): string
				local cd = if x then Creatures.byId[x.sp] else nil
				return if cd then cd.name else "a friend"
			end
			UIKit.text(f, "From " .. nm(pa) .. " and " .. nm(pb), UDim2.fromOffset(W - 40, 10), UDim2.fromOffset(26, 32), { color = UIKit.color("text_dim"), z = 4 })
			-- the mutations it hatches with (decided when it was laid)
			mutLine(f, Traits.clean(egg.muts), 26, 44, W - 26 - 100)
			if ready then
				UIKit.button(f, "Hatch", UDim2.fromOffset(60, 13), UDim2.new(1, -64, 0, 49), function()
					EggView.hatchery(q.uid)
				end, { name = "HatchNow_" .. q.uid, color = UIKit.color("button_ok") }).ZIndex = 4
			elseif warming and not finishShown then
				finishShown = true
				UIKit.button(f, "Finish now", UDim2.fromOffset(88, 13), UDim2.new(1, -92, 0, 49), function()
					StoreUI.buy("HatcheryNow")
				end, { name = "FinishNow", color = UIKit.color("button_warn") }).ZIndex = 4
			end
		else
			-- two parents to pick, what they would hatch, Breed
			local pick: Pick = breedPick[q.uid] or {}
			local pa, pb = palById(v, pick.a), palById(v, pick.b)
			local function slot(x: Types.Pal?, key: string, sx: number)
				local b = UIKit.button(f, "", UDim2.fromOffset(96, 36), UDim2.fromOffset(sx, 3), function()
					UIKit.openPanel("hatch", { hatch = q.uid, slot = key })
				end, { name = "Slot_" .. key .. "_" .. q.uid, color = UIKit.color("plate") })
				b.ZIndex = 4
				if x then
					PalTip.attach(b, x)
					PixelSprites.image(b, "icon_" .. x.sp, UDim2.fromOffset(2, 2), 5)
					local cd = Creatures.byId[x.sp]
					UIKit.text(b, if cd then cd.name else x.sp, UDim2.fromOffset(58, 10), UDim2.fromOffset(36, 13), { color = UIKit.color("text"), z = 6 })
				else
					UIKit.text(b, "Pick a parent", UDim2.fromScale(1, 1), nil, { x = "center", color = UIKit.color("text_dim"), z = 6 })
				end
			end
			slot(pa, "a", 4)
			UIKit.text(f, "+", UDim2.fromOffset(8, 10), UDim2.fromOffset(103, 16), { color = UIKit.color("text"), z = 4 })
			slot(pb, "b", 112)
			local pv = if pa and pb then Breed.preview(asProfile(v), pa.id, pb.id) else nil
			if pa and pb and pv then
				-- what hatches (a kind never met stays a shadow), the mutations it will have, the price and the time
				local sp = pv.sp
				local d = Creatures.byId[sp]
				local met = (v.seen[sp] or 0) >= 1
				local rar = Traits.RARITY[if d then d.rarity else 1] or Traits.RARITY[1]
				PixelSprites.image(f, if met then "icon_" .. sp else "icon_" .. sp .. "_sil", UDim2.fromOffset(214, 5), 4)
				UIKit.text(f, if met and d then d.name else "???", UDim2.fromOffset(W - 256, 10), UDim2.fromOffset(250, 10), { color = UIKit.color(rar.color), z = 4, name = "Child" })
				UIKit.text(f, rar.name, UDim2.fromOffset(W - 256, 10), UDim2.fromOffset(250, 19), { color = UIKit.color(rar.color), z = 4 })
				local lead = "Hatches with:"
				local lw = UIKit.textWidth(lead) + 4
				UIKit.text(f, lead, UDim2.fromOffset(lw, 10), UDim2.fromOffset(4, 42), { color = UIKit.color("text_dim"), z = 4, name = "MutsLead" })
				mutLine(f, pv.muts, 4 + lw, 42, W - 12 - lw)
				local costWords = string.format("%s coins, hatches in %s.", Numbers.coins(pv.price), Numbers.duration(pv.turns * Tuning.TurnSeconds))
				UIKit.text(f, costWords, UDim2.fromOffset(W - 76, 10), UDim2.fromOffset(4, 53), { color = UIKit.color("text_dim"), z = 4, name = "Cost" })
				UIKit.button(f, "Breed", UDim2.fromOffset(60, 13), UDim2.new(1, -64, 0, 51), function()
					local res = ask("breed.start", { uid = q.uid, a = pa.id, b = pb.id }, "An egg is already warming here.")
					if res.ok then
						breedPick[q.uid] = nil
						Audio.play("egg")
					end
				end, { name = "Breed_" .. q.uid, color = UIKit.color("button_ok"), enabled = v.shells >= pv.price }).ZIndex = 4
			else
				UIKit.text(f, "Pick two parents.", UDim2.fromOffset(W - 8, 10), UDim2.fromOffset(4, 42), { color = UIKit.color("text_dim"), z = 4 })
			end
		end
	end
end

------------------------------------------------------------------ the hut picker
-- Where a driftling lives (GAME_DESIGN 6: "the player can also select which creatures are sent to which hut"): every
-- hut, the comfiest first, with its room and comfort. One with room: Move here. A full one: each of its driftlings, to
-- swap with (it goes to where this one was).
local function buildHutPicker(body: Frame, v: Types.ClientView, id: number, back: string, backArg: any?)
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local me = palById(v, id)
	local md = if me then Creatures.byId[me.sp] else nil
	if me == nil or md == nil then
		UIKit.openPanel(back, backArg)
		return
	end
	local top = hint(body, string.format("Where should %s live?", md.name), W - 50)
	UIKit.button(body, "Back", UDim2.fromOffset(44, 12), UDim2.fromOffset(W - 44, 0), function()
		UIKit.openPanel(back, backArg)
	end, { name = "Back", color = UIKit.color("plate_light") })
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - top), UDim2.fromOffset(0, top))
	-- (each hut and each driftling of a full one a row of the list, made only near what shows: UIKit.lazyList; with
	-- every hut full that was every driftling on the island)
	local rows: { { h: number, make: () -> GuiObject } } = {}
	local order = 0
	local function move(uid: number, swap: number)
		local res = ask("pal.house", { id = id, uid = uid, swap = swap })
		if res.ok then
			Audio.play("pop")
			UIKit.openPanel(back, backArg)
		end
	end
	local function hutRow(uid: number, title: string, n: number, room: number, comfort: number): GuiObject
		local f = row(list, 0, 22)
		f.Name = "Hut_" .. uid
		PixelSprites.image(f, "mini_nest", UDim2.fromOffset(4, 5), 4)
		UIKit.text(f, title, UDim2.new(1, -110, 0, 10), UDim2.fromOffset(18, 1), { color = UIKit.color("text"), z = 4 })
		local sub = string.format("%d/%d", n, room) .. (if comfort > 0 then string.format(", comfort +%d%%", math.round(comfort * 100)) else "")
		UIKit.text(f, sub, UDim2.new(1, -110, 0, 10), UDim2.fromOffset(18, 11), { color = if n >= room then UIKit.color("orange") else UIKit.color("text_dim"), z = 4 })
		local here = me.home == uid
		UIKit.button(f, if here then "Here now" elseif n >= room then "Full" else "Move here", UDim2.fromOffset(70, 14), UDim2.new(1, -74, 0, 4), function()
			move(uid, 0)
		end, { name = "Move_" .. uid, color = UIKit.color("button_ok"), enabled = not here and n < room }).ZIndex = 4
		return f
	end
	local function swapRow(uid: number, x: Types.Pal, d: any): GuiObject
		local r = row(list, 0, 36)
		r.Name = "Swap_" .. x.id
		PalTip.attach(r, x)
		PixelSprites.image(r, "icon_" .. x.sp, UDim2.fromOffset(14, 2), 4)
		local rar = Traits.RARITY[d.rarity] or Traits.RARITY[1]
		UIKit.text(r, Lang.f("{1}  {2}", d.name, Lang.t(workWord(x))), UDim2.new(1, -126, 0, 10), UDim2.fromOffset(50, 13), { color = UIKit.color(rar.color), z = 4 })
		UIKit.button(r, "Swap", UDim2.fromOffset(50, 12), UDim2.new(1, -54, 0, 12), function()
			move(uid, x.id)
		end, { name = "SwapWith_" .. x.id, color = UIKit.color("plate") }).ZIndex = 4
		return r
	end
	-- (the island's driftlings by hut, once)
	local byHut: { [number]: { Types.Pal } } = {}
	for _, x in v.pals do
		if x.home ~= 0 then
			local l = byHut[x.home]
			if l == nil then
				l = {}
				byHut[x.home] = l
			end
			table.insert(l, x)
		end
	end
	local p = asProfile(v)
	for _, h in Tree.huts(p) do
		local uid, title, n, room, comfort = h.uid, buildingName(v, h.uid) or "Hut", h.n, h.room, h.comfort
		table.insert(rows, { h = 22, make = function(): GuiObject
			return hutRow(uid, title, n, room, comfort)
		end })
		order += 1
		-- a full one: swap with any of its driftlings
		if me.home ~= uid and n >= room then
			local inHut: { Types.Pal } = byHut[uid] or {}
			for _, x in inHut do
				local d = Creatures.byId[x.sp]
				if d then
					table.insert(rows, { h = 36, make = function(): GuiObject
						return swapRow(uid, x, d)
					end })
				end
			end
		end
	end
	if order == 0 then
		UIKit.vlist(list, 2)
		local f = row(list, 1, 22)
		UIKit.text(f, "No huts yet. Build one from the Huts tab.", UDim2.new(1, -10, 1, -4), UDim2.fromOffset(5, 2), { color = UIKit.color("text_dim"), z = 4, wrap = true })
		return
	end
	UIKit.lazyList(list, #rows, function(i: number): number
		return rows[i].h
	end, function(i: number): GuiObject?
		return rows[i].make()
	end, 2)
end

------------------------------------------------------------------ Driftlings
-- Every driftling, the hardest workers first (one with no hut, its hut cleared away, last). Each: its name in its
-- rarity's colour, its rarity and how fast it works, its passive, its mutations, where it lives and works; Move (the
-- hut picker), Work (where it works) and Sell (two taps).
-- (how many lines a row's words take, kept by the words, the width, the language and the text style: the Driftlings
-- list measures every row before it makes any, UIKit.lazyList)
local lineMemo: { [string]: number } = {}
local lineMemoKey = ""
local function linesOf(text: string, w: number): number
	local key = Lang.code() .. (if UIKit.smooth() then "s" else "p")
	if key ~= lineMemoKey then
		table.clear(lineMemo)
		lineMemoKey = key
	end
	local k = text .. "\0" .. w
	local n = lineMemo[k]
	if n == nil then
		n = math.clamp(UIKit.lines(text, w), 1, 2)
		lineMemo[k] = n
	end
	return n
end

-- What a driftling's row shows and how tall it is (measured before the row is made).
type PalPlan = { d: any, h: number, pl: number, wl: number, passive: string, where: string, color: Color3 }
local function palPlan(v: Types.ClientView, x: Types.Pal, W: number): PalPlan?
	local d = Creatures.byId[x.sp]
	if d == nil then
		return nil
	end
	local tw = W - 108
	-- (its passive on two lines when one is too narrow, the row a line taller: "there is a few boxes where text
	-- overflows. can you prevent this?", 2026-11-14)
	local passive = Lang.f("{1}: {2}@@pair", Lang.t(d.passive.name), Lang.t(Traits.describe(d.passive.fx)))
	local pl = linesOf(passive, tw)
	local where: string
	local color = UIKit.color("text_dim")
	if x.home == 0 then
		where = "No hut. Waiting for room."
		color = UIKit.color("orange")
	else
		local hut = buildingName(v, x.home) or "a hut"
		if x.work ~= 0 then
			where = string.format("%s, working at the %s", hut, buildingName(v, x.work) or "?")
			color = UIKit.color("good")
		else
			where = string.format("%s, resting", hut)
		end
	end
	-- (where it lives and works on two lines as well when the names are long: "Driftling Palace, working at the
	-- Grand Bazaar" ran past its box)
	local wl = linesOf(where, tw)
	local dy = (pl - 1) * 10 + (wl - 1) * 10
	-- (a touch screen's Move, Work and Sell taller, the row taller with them: GAME_DESIGN 2.1)
	local h = math.max(44 + dy, if UIKit.touch() then 50 else 0)
	return { d = d, h = h, pl = pl, wl = wl, passive = passive, where = where, color = color }
end

local function palRow(list: Instance, v: Types.ClientView, x: Types.Pal, plan: PalPlan, W: number, back: string): Frame
	local d = plan.d
	local rar = Traits.RARITY[d.rarity] or Traits.RARITY[1]
	local tw = W - 108
	local passive, pl = plan.passive, plan.pl
	local dy = (pl - 1) * 10
	local touch = UIKit.touch()
	local bh, bw = if touch then 14 else 12, if touch then 56 else 52
	local f = row(list, 0, plan.h)
	f.Name = "Pal_" .. x.id
	-- (hover or hold: what its numbers mean, the request of 2026-11-15)
	PalTip.attach(f, x)
	PixelSprites.image(f, "icon_" .. x.sp, UDim2.fromOffset(4, 6), 4)
	UIKit.text(f, d.name, UDim2.fromOffset(90, 10), UDim2.fromOffset(PX, 1), { color = UIKit.color(rar.color), z = 4, name = "Name" })
	UIKit.text(f, Lang.f("{1}, works x{2}", Lang.t(rar.name), string.format("%.1f", Tree.worth(x))), UDim2.fromOffset(math.max(10, tw - UIKit.textWidth(d.name) - 6), 10), UDim2.fromOffset(PX + UIKit.textWidth(d.name) + 6, 1), { color = UIKit.color("text"), z = 4, name = "Rarity" })
	UIKit.text(f, passive, UDim2.fromOffset(tw, 10 * pl), UDim2.fromOffset(PX, 11), { color = UIKit.color("accent"), z = 4, name = "Passive", wrap = pl > 1, y = "top" })
	mutLine(f, x.muts or {}, PX, 21 + dy, tw)
	local where, color, wl = plan.where, plan.color, plan.wl
	UIKit.text(f, where, UDim2.fromOffset(tw, 10 * wl), UDim2.fromOffset(PX, 31 + dy), { color = color, z = 4, name = "Where", wrap = wl > 1, y = "top" })
	UIKit.button(f, "Move", UDim2.fromOffset(bw, bh), UDim2.new(1, -(bw + 3), 0, 2), function()
		UIKit.openPanel("pals", { move = x.id, back = back })
	end, { name = "Move_" .. x.id, color = UIKit.color("button_ok") }).ZIndex = 4
	UIKit.button(f, "Work", UDim2.fromOffset(bw, bh), UDim2.new(1, -(bw + 3), 0, 4 + bh), function()
		UIKit.openPanel("pals", { pal = x.id })
	end, { name = "Help_" .. x.id, enabled = x.home ~= 0 }).ZIndex = 4
	confirmButton(f, "Sell " .. Numbers.coins(Tree.price(x)), UDim2.fromOffset(bw, bh), UDim2.new(1, -(bw + 3), 0, 6 + 2 * bh), function()
		local res = ask("pal.sell", { id = x.id })
		if res.ok then
			Audio.play("coins")
			local got = if type(res.data) == "table" then tonumber(res.data.shells) or 0 else 0
			UIKit.notice(string.format("Sold %s for %s coins.", d.name, Numbers.coins(got)), UIKit.color("good"))
		end
	end, "Sell_" .. x.id)
	return f
end

-- A row of the rarities' small eggs (the bulk hatch's and Auto Hatch's pick: the request of 2026-11-22), each a
-- button 12 px wide: those at `floor` or rarer drawn whole (with `only`, that one alone: the bulk sell's, which draws
-- whole too the rarities `whole` says), the others as silhouettes, a line under the ones picked.
-- With `off`, an Off button first (floor 0). Returns the row's width.
local function rarityRow(parent: Instance, x: number, y: number, floor: number, off: boolean, prefix: string, pick: (r: number) -> (), only: boolean?, whole: ((r: number) -> boolean)?): number
	local cx = x
	if off then
		local ow = math.max(26, UIKit.textWidth(Lang.t("Off")) + 10)
		local ob = UIKit.button(parent, "Off", UDim2.fromOffset(ow, 11), UDim2.fromOffset(cx, y), function()
			pick(0)
		end, { name = prefix .. "0", color = if floor <= 0 then UIKit.color("button_ok") else UIKit.color("plate_light") })
		ob.ZIndex = 4
		cx += ow + 2
	end
	for r = 1, Traits.RMAX do
		local b = Instance.new("TextButton")
		b.Name = prefix .. r
		b.Text = ""
		b.BackgroundTransparency = 1
		b.BorderSizePixel = 0
		-- (on: a button with it off reads as disabled, UIKit's way; with no background it tints nothing)
		b.AutoButtonColor = true
		b.Size = UDim2.fromOffset(12, 13)
		b.Position = UDim2.fromOffset(cx, y)
		b.ZIndex = 4
		b.Parent = parent
		-- (a commoner one as its silhouette: the sprite may be an image or, without EditableImage, a frame of pixels,
		-- so it is drawn dark rather than faded)
		local on = floor >= 1 and (r == floor or (r > floor and not only))
		local drawn = on or (whole ~= nil and whole(r))
		PixelSprites.image(b, "mini_egg_" .. r .. (if drawn then "" else "_sil"), UDim2.fromOffset(0, 0), 5)
		if on then
			UIKit.rect(b, UDim2.fromOffset(if r < Traits.RMAX then 12 else 11, 1), UDim2.fromOffset(0, 12), UIKit.color("accent"), 5).Name = "Picked"
		end
		b.Activated:Connect(function()
			Audio.play("click")
			pick(r)
		end)
		cx += 12
	end
	return cx - x
end

-- the bulk sell's rarity (the egg row over the list; kept while the game runs, 1: Common)
local sellRarity = 1

local function buildPals(body: Frame, arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	-- (from a driftling's details, { back = "pal" }: Back and a choice go back to its details)
	if type(arg) == "table" and type(arg.pal) == "number" then
		if arg.back == "pal" then
			buildPicker(body, v, arg.pal, "pal", { id = arg.pal })
		else
			buildPicker(body, v, arg.pal, "pals")
		end
		return
	end
	if type(arg) == "table" and type(arg.move) == "number" then
		if arg.back == "pal" then
			buildHutPicker(body, v, arg.move, "pal", { id = arg.move })
		else
			buildHutPicker(body, v, arg.move, "pals")
		end
		return
	end
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local housed = 0
	for _, x in v.pals do
		if x.home ~= 0 then
			housed += 1
		end
	end
	-- the tree's panel and a Hatchery's beside the hint (GAME_DESIGN 6, 6.1)
	local hasHatch = #hatcheries(v) > 0
	local buttons = if hasHatch then 128 else 66
	local top = hint(body, string.format("%d in huts, room for %d. Hatch more at the tree.", housed, v.nests), W - buttons)
	UIKit.button(body, "Eggs", UDim2.fromOffset(60, 13), UDim2.fromOffset(W - 60, 0), function()
		UIKit.openPanel("tree")
	end, { name = "OpenTree", color = UIKit.color("button_ok") })
	if hasHatch then
		UIKit.button(body, "Hatchery", UDim2.fromOffset(60, 13), UDim2.fromOffset(W - 122, 0), function()
			UIKit.openPanel("hatch")
		end, { name = "OpenHatch", color = UIKit.color("pink") })
	end
	top = math.max(top, 16)
	-- the bulk sell (the request of 2026-11-22: "make a bulksell by rarity option for creatures"): a tap on one of the
	-- rarities' eggs picks it, and Sell (two taps) sells every driftling of that rarity (Logic/Tree.sellRarity; the
	-- button says how many and what they bring: Tree.rarityWorth). The row sits in a frame of its own and a pick
	-- remakes only that frame, not the list (it remade every row: "selecting based on rarity ... is very laggy").
	if #v.pals > 0 then
		local bar = Instance.new("Frame")
		bar.Name = "SellBar"
		bar.BackgroundTransparency = 1
		bar.BorderSizePixel = 0
		bar.Size = UDim2.fromOffset(W, 13)
		bar.Position = UDim2.fromOffset(0, top)
		bar.Parent = body
		-- (the rarities the island has driftlings of drawn whole, the rest as silhouettes)
		local have: { [number]: boolean } = {}
		for _, x in v.pals do
			local d = Creatures.byId[x.sp]
			if d then
				have[d.rarity] = true
			end
		end
		local function fillBar()
			UIKit.clear(bar)
			local r = math.clamp(sellRarity, 1, Traits.RMAX)
			local lead = Lang.t("Sell by rarity")
			local lw = UIKit.textWidth(lead) + 6
			local x0 = 0
			if lw + 12 * Traits.RMAX + 4 + 90 <= W then
				UIKit.text(bar, lead, UDim2.fromOffset(lw, 13), UDim2.fromOffset(0, 0), { color = UIKit.color("text_dim"), name = "SellLead" })
				x0 = lw
			end
			local rowW = rarityRow(bar, x0, 0, r, false, "SellR_", function(nr: number)
				if nr ~= sellRarity then
					sellRarity = nr
					fillBar()
				end
			end, true, function(k: number): boolean
				return have[k] == true
			end)
			local n, worth = Tree.rarityWorth(asProfile(v), r)
			local bx = x0 + rowW + 4
			local sw = math.min(150, W - bx)
			if n > 0 then
				confirmButton(bar, Lang.f("Sell {1}: {2}", n, Numbers.coins(worth)), UDim2.fromOffset(sw, 13), UDim2.fromOffset(bx, 0), function()
					local res = ask("pal.sellAll", { r = r })
					if res.ok then
						Audio.play("coins")
						local data = if type(res.data) == "table" then res.data else {}
						local got, sold = tonumber(data.shells) or 0, tonumber(data.sold) or 0
						UIKit.notice(if sold == 1 then Lang.f("Sold 1 driftling for {1} coins.", Numbers.coins(got)) else Lang.f("Sold {1} driftlings for {2} coins.", sold, Numbers.coins(got)), UIKit.color("good"))
					end
				end, "SellRarity")
			else
				UIKit.button(bar, "None to sell", UDim2.fromOffset(sw, 13), UDim2.fromOffset(bx, 0), function()
					Audio.play("deny")
					UIKit.notice("No driftlings of that rarity.", UIKit.color("bad"))
				end, { name = "SellRarity", color = UIKit.color("plate_light") }).ZIndex = 4
			end
		end
		fillBar()
		top += 16
	end
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - top), UDim2.fromOffset(0, top))
	if #v.pals == 0 then
		UIKit.vlist(list, 2)
		local f = row(list, 1, 24)
		UIKit.text(f, if v.nests == 0 then "No driftlings yet. Build a hut, then hatch an egg at the tree." else "No driftlings yet. Tap the Tree of Life to hatch one.", UDim2.new(1, -10, 1, -4), UDim2.fromOffset(5, 2), { color = UIKit.color("text_dim"), z = 4, wrap = true })
		return
	end
	local order: { Types.Pal } = table.clone(v.pals)
	table.sort(order, function(a: Types.Pal, b: Types.Pal): boolean
		if (a.home == 0) ~= (b.home == 0) then
			return a.home ~= 0
		end
		return Tree.better(a, b)
	end)
	-- (every row measured, only those near what shows made: UIKit.lazyList)
	local plans: { PalPlan? } = table.create(#order)
	for i, x in order do
		plans[i] = palPlan(v, x, W)
	end
	UIKit.lazyList(list, #order, function(i: number): number
		local pl = plans[i]
		return if pl then pl.h else 0
	end, function(i: number): GuiObject?
		local pl = plans[i]
		return if pl then palRow(list, v, order[i], pl, W, "pals") else nil
	end, 2)
end

------------------------------------------------------------------ one driftling's details
-- The request of 2026-11-14, "allow players to click on creatures to open up a menu seeing their details": a tap on a
-- driftling on an island (Controllers/WorldView's pick) opens this. Its portrait, its name big in its rarity's colour,
-- its rarity with its stars, its kind of land and how fast it works, its line of description; on the left its passive
-- and every mutation (name and stars in its tier's colour, what it does; a weather's with that weather's icon); on the
-- right where it works and how fast (Tree.worth: the same at every workplace), its hut, what it sells for. The own island's
-- ({ id }) has Work (the work picker), Move (the hut picker) and Sell (two taps) along the foot; a neighbour's
-- ({ id, plot, sp, muts, work, home, isle }: the building ids from its island) is only looked at.
local WEATHER_ICON: { [string]: string } = {} -- a weather family -> its weather's mini icon
for _, k in WeatherData.KINDS do
	if k.family then
		WEATHER_ICON[k.family] = k.icon
	end
end

local function buildPal(body: Frame, arg: any?)
	local v = StateClient.view()
	if v == nil or type(arg) ~= "table" then
		return
	end
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local own = arg.plot == nil or arg.plot == v.plot
	-- the driftling: the own one from the view (gone: sold, or the view moved on), a neighbour's as its island told it
	local x: Types.Pal?
	if own then
		x = palById(v, tonumber(arg.id))
	elseif type(arg.sp) == "string" then
		x = { id = tonumber(arg.id) or 0, sp = arg.sp, home = 0, work = 0, muts = Traits.clean(arg.muts) }
	end
	local d = if x then Creatures.byId[x.sp] else nil
	if x == nil or d == nil then
		UIKit.text(body, "That driftling is gone.", UDim2.fromOffset(W, 12), UDim2.fromOffset(0, 0), { color = UIKit.color("text_dim"), name = "Gone" })
		UIKit.button(body, "All driftlings", UDim2.fromOffset(80, 13), UDim2.fromOffset(0, 16), function()
			UIKit.openPanel("pals")
		end, { name = "AllPals", color = UIKit.color("button_ok") })
		return
	end
	local pal = x :: Types.Pal
	local rar = Traits.RARITY[d.rarity] or Traits.RARITY[1]
	local muts: { string } = pal.muts or {}
	-- its portrait (32 x 32, drawn from its model) on a veil, its name, rarity and kind beside it
	local frame = UIKit.row(body, UDim2.fromOffset(38, 38), UDim2.fromOffset(0, 0), nil, 0.84)
	frame.Name = "Portrait"
	PixelSprites.image(frame, "icon_" .. pal.sp, UDim2.fromOffset(3, 3), 4)
	UIKit.text(body, d.name, UDim2.fromOffset(W - 44, 18), UDim2.fromOffset(44, -1), { face = "big", kind = "title", color = UIKit.color(rar.color), name = "Name" })
	UIKit.text(body, Lang.keep(Lang.t(rar.name) .. " " .. string.rep("*", d.rarity)), UDim2.fromOffset(W - 44, 10), UDim2.fromOffset(44, 17), { color = UIKit.color(rar.color), name = "Rarity" })
	local land = Islets.list[d.islet]
	local worth = string.format("%.1f", Tree.worth(pal))
	local kind = if land then Lang.f("{1} kind, works x{2}", Lang.t(land.name), worth) else Lang.f("A driftling, works x{1}", worth)
	UIKit.text(body, kind, UDim2.fromOffset(W - 44, 10), UDim2.fromOffset(44, 27), { color = UIKit.color("text"), name = "Kind" })
	-- (its line of description when the panel is tall enough: a phone's is not)
	local top = 41
	if H >= 150 then
		UIKit.text(body, d.blurb, UDim2.fromOffset(W, 10), UDim2.fromOffset(0, 40), { color = UIKit.color("text_dim"), name = "Blurb" })
		top = 52
	end
	-- the left half: its passive (what it does over two lines), then its mutations, one a line
	local L = math.floor((W - 4) / 2)
	local R0, RW = L + 4, W - L - 4
	local pv = UIKit.row(body, UDim2.fromOffset(L, 32), UDim2.fromOffset(0, top))
	pv.Name = "PassiveRow"
	PixelSprites.image(pv, "mini_star", UDim2.fromOffset(3, 5), 4)
	UIKit.text(pv, d.passive.name, UDim2.fromOffset(L - 18, 10), UDim2.fromOffset(16, 1), { color = UIKit.color("accent"), z = 4, name = "Passive" })
	UIKit.text(pv, Traits.describe(d.passive.fx), UDim2.fromOffset(L - 18, 20), UDim2.fromOffset(16, 11), { color = UIKit.color("text_dim"), z = 4, wrap = true, y = "top", name = "PassiveFx" })
	if #muts == 0 then
		UIKit.text(body, "No mutations", UDim2.fromOffset(L, 10), UDim2.fromOffset(2, top + 35), { color = UIKit.color("text_dim"), name = "MutsTitle" })
	end
	-- (a mutation whose words don't fit beside its name and stars has them on a line of their own under it)
	local my = top + 35
	for _, id in muts do
		local m = Traits.byId[id]
		if m then
			local y = my
			local icon = WEATHER_ICON[m.family]
			local nx = 2
			if icon and PixelSprites.has("mini_" .. icon) then
				PixelSprites.image(body, "mini_" .. icon, UDim2.fromOffset(1, y), 4).Name = "MutIcon_" .. id
				nx = 14
			end
			local _, lw = TierStars.label(body, m.name, m.tier, nx, y, { name = "Mut_" .. id })
			local room = L - nx - lw - 6
			-- (on a line of its own only while that leaves room above the foot's buttons: longer words in another
			-- language, or smooth text, would push the last ones under them; else beside the name, cut to fit)
			if UIKit.textWidth(m.blurb) <= room or my + 21 > H - 15 then
				UIKit.text(body, m.blurb, UDim2.fromOffset(math.max(10, room), 10), UDim2.fromOffset(nx + lw + 6, y), { color = UIKit.color("text_dim"), name = "MutFx_" .. id })
				my += 11
			else
				UIKit.text(body, m.blurb, UDim2.fromOffset(L - nx - 2, 10), UDim2.fromOffset(nx + 2, y + 10), { color = UIKit.color("text_dim"), name = "MutFx_" .. id })
				my += 21
			end
		end
	end
	-- the right half: where it works and how fast, its hut, its price
	-- (a row grows a line for words too long for one, so nothing runs past its edge: the request of 2026-11-14, "there
	-- is a few boxes where text overflows. can you prevent this?"; it returns its height, the rows stacking under it)
	local function info(y: number, icon: string, top: string, sub: string, color: Color3, name: string): number
		local tw = RW - 18
		local tl, sl = math.max(1, UIKit.lines(top, tw)), math.max(1, UIKit.lines(sub, tw))
		local h = 2 + 10 * (tl + sl)
		local f = UIKit.row(body, UDim2.fromOffset(RW, h), UDim2.fromOffset(R0, y))
		f.Name = name
		PixelSprites.image(f, "mini_" .. icon, UDim2.fromOffset(3, 5), 4)
		UIKit.text(f, top, UDim2.fromOffset(tw, 10 * tl), UDim2.fromOffset(16, 1), { color = color, z = 4, name = "Top", wrap = tl > 1, y = "top" })
		UIKit.text(f, sub, UDim2.fromOffset(tw, 10 * sl), UDim2.fromOffset(16, 1 + 10 * tl), { color = UIKit.color("text_dim"), z = 4, name = "Sub", wrap = sl > 1, y = "top" })
		return h
	end
	local workId: string? = nil
	local hutName: string? = nil
	if own then
		local q = if pal.work ~= 0 then pieceOf(v, pal.work) else nil
		workId = if q then q.id else nil
		hutName = if pal.home ~= 0 then buildingName(v, pal.home) or "hut" else nil
	else
		workId = if type(arg.work) == "string" and arg.work ~= "" then arg.work else nil
		local hd = if type(arg.home) == "string" then Buildings.byId[arg.home] else nil
		hutName = if hd then hd.name else "hut"
	end
	local wd = if workId then Buildings.byId[workId] else nil
	local ry = top
	-- (its speed: the same at every workplace, its passive and mutations counted)
	local speed = Tree.worth(pal)
	if wd then
		-- (in the language on show: "auto" is the Auto button's word there)
		local how = if own and pal.pin then Lang.t("your pick") elseif Lang.code() == "en" then "auto" else Lang.t("Auto")
		ry += info(ry, "work", Lang.f("Works at the {1}", Lang.t(wd.name)), Lang.keep(string.format("x%.1f, ", speed) .. how), UIKit.color("good"), "Where") + 2
	else
		ry += info(ry, "rest", if hutName then "Resting" else "Waiting for a hut", string.format("Works x%.1f", speed), UIKit.color("text"), "Where") + 2
	end
	ry += info(ry, "nest", if hutName then "Lives in the " .. hutName else "No hut yet", if hutName then "Home" else "Waits for room", if hutName then UIKit.color("text") else UIKit.color("orange"), "Hut")
	local price = Tree.price(pal)
	info(ry, "coin", Lang.f("{1} {2} coins", Lang.t(if own then "Sells for" else "Worth"), Numbers.coins(price)), if own then "Tap Sell twice" else "Not yours to sell", UIKit.color("accent"), "Price")
	-- the foot: the own one's buttons; a neighbour's says whose it is
	local fy = H - 14
	if own then
		local bw = 52
		UIKit.button(body, "All driftlings", UDim2.fromOffset(80, 13), UDim2.fromOffset(0, fy), function()
			UIKit.openPanel("pals")
		end, { name = "PalAll" })
		UIKit.button(body, "Work", UDim2.fromOffset(bw, 13), UDim2.fromOffset(W - 3 * bw - 8 - 12, fy), function()
			UIKit.openPanel("pals", { pal = pal.id, back = "pal" })
		end, { name = "PalWork", enabled = pal.home ~= 0 })
		UIKit.button(body, "Move", UDim2.fromOffset(bw, 13), UDim2.fromOffset(W - 2 * bw - 4 - 12, fy), function()
			UIKit.openPanel("pals", { move = pal.id, back = "pal" })
		end, { name = "PalMove", color = UIKit.color("button_ok") })
		confirmButton(body, "Sell " .. Numbers.coins(price), UDim2.fromOffset(bw + 12, 13), UDim2.fromOffset(W - bw - 12, fy), function()
			local res = ask("pal.sell", { id = pal.id })
			if res.ok then
				Audio.play("coins")
				local got = if type(res.data) == "table" then tonumber(res.data.shells) or 0 else 0
				UIKit.openPanel("pals")
				UIKit.notice(string.format("Sold %s for %s coins.", d.name, Numbers.coins(got)), UIKit.color("good"))
			end
		end, "PalSell")
	else
		local isle = if type(arg.isle) == "string" and arg.isle ~= "" then arg.isle else "another island"
		UIKit.text(body, string.format("Lives on %s.", isle), UDim2.fromOffset(W, 12), UDim2.fromOffset(0, fy), { color = UIKit.color("text_dim"), name = "ReadOnly" })
	end
end

------------------------------------------------------------------ the Tree of Life
-- (GAME_DESIGN 6) On the left: how often it lays and how long till the next lot (a bar running down), how many eggs a
-- lot, the huts' room, and the odds of each rarity of egg now. On the right: its eggs now, the rarest first, each with
-- its egg, its rarity, what it hatches and Hatch (its price in shells). With { hatch = id } (every hut full) the swap
-- picker instead: the island's driftlings in huts, the weakest first, each with what it sells for and Swap (egg.hatch
-- with it: it's sold and what hatches takes its place).
local function buildSwap(body: Frame, v: Types.ClientView, id: number, bag: boolean?)
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local egg: Types.Laid? = nil
	for _, e in (if bag then v.bag or {} else v.clutch) :: { any } do
		if e.id == id then
			egg = e
		end
	end
	if egg == nil then
		-- (the list first: opening a panel clears the notices, so the notice goes on the new panel's status line)
		UIKit.openPanel("tree")
		UIKit.notice("That egg is gone.", UIKit.color("text_dim"))
		return
	end
	local e = egg :: Types.Laid
	local rar = Traits.RARITY[e.r] or Traits.RARITY[1]
	-- (the rarity in lower case in English, the language's own word otherwise: Locale/Lang)
	local rw = if Lang.code() == "en" then string.lower(rar.name) else Lang.t(rar.name)
	local top = hint(body, if bag then Lang.f("Huts full. Pick one to sell for the {1} egg from your bag.", rw) else Lang.f("Huts full. Pick one to sell for the {1} egg ({2} coins).", rw, Numbers.coins(e.cost or 0)), W - 50)
	UIKit.button(body, "Back", UDim2.fromOffset(44, 12), UDim2.fromOffset(W - 44, 0), function()
		UIKit.openPanel("tree")
	end, { name = "Back", color = UIKit.color("plate_light") })
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - top), UDim2.fromOffset(0, top))
	local order: { Types.Pal } = {}
	for _, x in v.pals do
		if x.home ~= 0 then
			table.insert(order, x)
		end
	end
	table.sort(order, function(a: Types.Pal, b: Types.Pal): boolean
		return Tree.better(b, a)
	end)
	-- (every housed driftling: the rows made only near what shows, UIKit.lazyList)
	local function swapOutRow(x: Types.Pal): GuiObject?
		local d = Creatures.byId[x.sp]
		if d == nil then
			return nil
		end
		local f = row(list, 0, 38)
		f.Name = "SwapOut_" .. x.id
		PalTip.attach(f, x)
		PixelSprites.image(f, "icon_" .. x.sp, UDim2.fromOffset(4, 3), 4)
		local xr = Traits.RARITY[d.rarity] or Traits.RARITY[1]
		local tw = W - 106
		UIKit.text(f, d.name, UDim2.fromOffset(tw, 10), UDim2.fromOffset(PX, 1), { color = UIKit.color(xr.color), z = 4, name = "Name" })
		UIKit.text(f, Lang.f("{1}, works x{2}", Lang.t(xr.name), string.format("%.1f", Tree.worth(x))), UDim2.fromOffset(tw, 10), UDim2.fromOffset(PX, 11), { color = UIKit.color("text_dim"), z = 4 })
		mutLine(f, x.muts or {}, PX, 21, tw)
		UIKit.button(f, "Swap", UDim2.fromOffset(56, 12), UDim2.new(1, -59, 0, 3), function()
			if bag then
				EggView.hatchBag(id, x.id)
			else
				EggView.hatch(id, x.id)
			end
		end, { name = "SwapTake_" .. x.id, color = UIKit.color("button_ok") }).ZIndex = 4
		UIKit.text(f, "Sells for " .. Numbers.coins(Tree.price(x)), UDim2.fromOffset(56, 10), UDim2.new(1, -59, 0, 19), { x = "center", color = UIKit.color("text_dim"), z = 4 })
		return f
	end
	UIKit.lazyList(list, #order, function(): number
		return 38
	end, function(i: number): GuiObject?
		return swapOutRow(order[i])
	end, 2)
end

------------------------------------------------------------------ Hatched: what a bulk hatch brought
-- (EggView.hatchMany; the request of 2026-11-22: "make a bulk open eggs button, where you open all eggs at once in
-- the tree") How many hatched and for how much, the eggs left (for coins, for room), then a card for each that came
-- out, the rarest first: its portrait, name and rarity, "New!" for a kind never had, its mutations. The cards turn up
-- one after another the first time (a rare one or a new kind with bits); the panel built again shows them all.
local HATCHED_STEP = 0.09
local function buildHatched(body: Frame, arg: any?)
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local data: { [string]: any } = if type(arg) == "table" then arg else {}
	local list: { any } = {}
	for _, x in (if type(data.list) == "table" then data.list else {}) :: { any } do
		if type(x) == "table" and type(x.sp) == "string" and Creatures.byId[x.sp] then
			table.insert(list, x)
		end
	end
	table.sort(list, function(a: any, b: any): boolean
		local ra, rb = Creatures.byId[a.sp].rarity, Creatures.byId[b.sp].rarity
		if ra ~= rb then
			return ra > rb
		end
		if (a.new == true) ~= (b.new == true) then
			return a.new == true
		end
		return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
	end)
	local n = #list
	local cost = tonumber(data.cost) or 0
	local head = if data.breed
		then (if n == 1 then Lang.t("Hatched 1 egg from your Hatchery.") else Lang.f("Hatched {1} eggs from your Hatcheries.", n))
		elseif data.bag then (if n == 1 then Lang.t("Hatched 1 egg from your bag.") else Lang.f("Hatched {1} eggs from your bag.", n))
		else (if n == 1 then Lang.f("Hatched 1 egg for {1} coins.", Numbers.coins(cost)) else Lang.f("Hatched {1} eggs for {2} coins.", n, Numbers.coins(cost)))
	UIKit.text(body, head, UDim2.fromOffset(W - 50, 12), UDim2.fromOffset(0, 0), { color = UIKit.color("text"), name = "Head" })
	UIKit.button(body, "Back", UDim2.fromOffset(44, 12), UDim2.fromOffset(W - 44, 0), function()
		UIKit.openPanel(if data.breed then "hatch" else "tree")
	end, { name = "Back", color = UIKit.color("plate_light") }).ZIndex = 4
	-- the eggs left, and why
	local top = 14
	local room, short = tonumber(data.room) or 0, tonumber(data.short) or 0
	if room > 0 then
		UIKit.text(body, if room == 1 then "1 egg left: huts full." else Lang.f("{1} eggs left: huts full.", room), UDim2.fromOffset(W, 10), UDim2.fromOffset(0, top), { color = UIKit.color("orange"), name = "LeftRoom" })
		top += 11
	end
	if short > 0 then
		UIKit.text(body, if short == 1 then "1 egg left: not enough coins." else Lang.f("{1} eggs left: not enough coins.", short), UDim2.fromOffset(W, 10), UDim2.fromOffset(0, top), { color = UIKit.color("orange"), name = "LeftCoins" })
		top += 11
	end
	local scroll = UIKit.scroll(body, UDim2.fromOffset(W, H - top), UDim2.fromOffset(0, top))
	scroll.Name = "List"
	local cols = if W >= 440 then 3 elseif W >= 300 then 2 else 1
	local cw = math.floor((W - 6 - (cols - 1) * 3) / cols)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(cw, 38)
	grid.CellPadding = UDim2.fromOffset(3, 3)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	local v = StateClient.view()
	local byId: { [number]: Types.Pal } = {}
	for _, x in (if v then v.pals else {}) :: { Types.Pal } do
		byId[x.id] = x
	end
	local first = data.shown ~= true
	data.shown = true
	for i, x in list do
		local d = Creatures.byId[x.sp]
		local rar = Traits.RARITY[d.rarity] or Traits.RARITY[1]
		local f = UIKit.row(scroll, UDim2.fromOffset(cw, 38), nil, nil, 0.84)
		f.Name = "Got_" .. tostring(x.id)
		f.LayoutOrder = i
		local muts: { string } = {}
		for _, m in (if type(x.muts) == "table" then x.muts else {}) :: { any } do
			if type(m) == "string" then
				table.insert(muts, m)
			end
		end
		local pal = byId[tonumber(x.id) or -1]
		if pal then
			PalTip.attach(f, pal)
		end
		PixelSprites.image(f, "icon_" .. x.sp, UDim2.fromOffset(4, 3), 4)
		local tw = cw - PX - 4
		UIKit.text(f, d.name, UDim2.fromOffset(tw, 10), UDim2.fromOffset(PX, 1), { color = UIKit.color(rar.color), z = 4, name = "Name" })
		UIKit.text(f, rar.name, UDim2.fromOffset(tw, 10), UDim2.fromOffset(PX, 11), { color = UIKit.color(rar.color), z = 4, name = "Rarity" })
		if x.new == true then
			UIKit.text(f, "New!", UDim2.fromOffset(tw, 10), UDim2.fromOffset(PX, 11), { x = "right", color = UIKit.color("yellow"), z = 4, name = "New" })
		end
		mutLine(f, muts, PX, 23, tw)
		if first then
			-- (one after another: a pop each, a rare one or a new kind with bits of its colour)
			f.Visible = false
			task.delay(HATCHED_STEP * i, function()
				if f.Parent == nil then
					return
				end
				f.Visible = true
				local big = d.rarity >= 3 or x.new == true
				Audio.play(if d.rarity >= 5 then "rare" else "pop")
				if big then
					UIKit.burstOn(f, { rar.color, "white", "good" }, if d.rarity >= 5 then 16 else 8)
				end
			end)
		end
	end
end

local function clock(secs: number): string
	local s = math.max(0, math.ceil(secs))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- the bulk hatch's lowest rarity (the egg row over the list; kept while the game runs, 1: every egg)
local bulkFloor = 1

local function buildTree(body: Frame, arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	if type(arg) == "table" and type(arg.hatch) == "number" then
		buildSwap(body, v, arg.hatch, arg.bag == true)
		return
	end
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local p = asProfile(v)
	local LW = math.min(150, math.floor(W * 0.42))
	-- (the left column scrolls: on a phone it is taller than the screen, the request of 2026-11-19, "make mobile and
	-- tablet as responsive and catered to as possible")
	local col = UIKit.scroll(body, UDim2.fromOffset(LW + 4, H), UDim2.fromOffset(0, 0))
	col.Name = "Left"
	local RX = LW + 8
	local RW = W - RX
	-- how often, and the bar to the next lot (run down by the client between the server's ticks)
	UIKit.text(col, "New eggs every " .. clock(v.clutchSecs), UDim2.fromOffset(LW, 10), UDim2.fromOffset(0, 0), { color = UIKit.color("text"), name = "Pace" })
	local next = UIKit.text(col, "Next in 0:00", UDim2.fromOffset(LW, 10), UDim2.fromOffset(0, 10), { color = UIKit.color("text_dim"), name = "Next" })
	local back = UIKit.rect(col, UDim2.fromOffset(LW, 4), UDim2.fromOffset(0, 21), UIKit.color("glass"), 3)
	back.BackgroundTransparency = 0.25
	back.Name = "TreeBar"
	local fill = UIKit.rect(back, UDim2.fromOffset(LW - 2, 2), UDim2.fromOffset(1, 1), UIKit.color("good"), 4)
	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function()
		if fill.Parent == nil then
			if conn then
				conn:Disconnect()
			end
			return
		end
		local left, secs = StateClient.clutchLeft()
		fill.Size = UDim2.fromOffset(math.floor((LW - 2) * math.clamp(left / math.max(1, secs), 0, 1) + 0.5), 2)
		local text = "Next in " .. clock(left)
		if next.Text ~= text then
			next.Text = text
		end
	end)
	-- under the bar, new eggs now (a product) and, without it, the Quick Tree pass: the request of 2026-11-14, "make a
	-- developer product to refresh eggs in the tree of life, and put the gamepass to cut the tree of life time to 5
	-- min in the tree of life menu as well"
	local dy = 28
	local nb = UIKit.button(col, "New eggs now " .. StoreUI.robuxText("RefreshEggs"), UDim2.fromOffset(LW, 12), UDim2.fromOffset(0, dy), function()
		StoreUI.buy("RefreshEggs")
	end, { name = "TreeRefresh", color = UIKit.color("button_ok") })
	nb.ZIndex = 4
	dy += 14
	if not (v.passes and v.passes.QuickTree) then
		-- (the user's words of 2026-11-14: "Shorten cooldown permanently: R$"; two lines on a button too narrow for one)
		local words = "Shorten cooldown permanently: " .. StoreUI.robuxText("QuickTree")
		local qh = if UIKit.textWidth(words) > LW - 6 then 22 else 12
		local qb = UIKit.button(col, words, UDim2.fromOffset(LW, qh), UDim2.fromOffset(0, dy), function()
			StoreUI.buy("QuickTree")
		end, { name = "TreeQuick", color = UIKit.color("button_warn") })
		qb.ZIndex = 4
		local ql = qb:FindFirstChild("Words")
		if qh > 12 and ql and ql:IsA("TextLabel") then
			ql.TextWrapped = true
		end
		dy += qh + 2
	end
	-- Auto Hatch (the AutoHatch pass; the request of 2026-11-22, "make an auto buy gamepass, which lets you auto buy
	-- eggs that appear above a rarity of your choosing"): without it, a button to buy it; with it, the rarity a new
	-- egg needs to hatch by itself, picked on a row of the rarities' eggs (Off first)
	if v.passes and v.passes.AutoHatch then
		local floor = v.settings.auto or 0
		local rar = Traits.RARITY[floor]
		local words = if floor >= 1 and rar then Lang.f("Auto Hatch: {1} and up", Lang.t(rar.name)) else Lang.t("Auto Hatch: off")
		-- (two lines when a language's words are wider than the column)
		local wl = math.clamp(UIKit.lines(words, LW), 1, 2)
		UIKit.text(col, Lang.keep(words), UDim2.fromOffset(LW, 10 * wl), UDim2.fromOffset(0, dy), { color = if floor >= 1 and rar then UIKit.color(rar.color) else UIKit.color("text_dim"), wrap = wl > 1, name = "AutoWords" })
		rarityRow(col, 0, dy + 1 + 10 * wl, floor, true, "Auto_", function(r: number)
			if r ~= floor then
				ask("egg.auto", { r = r })
			end
		end)
		dy += 17 + 10 * wl
	else
		local ab = UIKit.button(col, Lang.f("Auto Hatch {1}", StoreUI.robuxText("AutoHatch")), UDim2.fromOffset(LW, 12), UDim2.fromOffset(0, dy), function()
			StoreUI.buy("AutoHatch")
		end, { name = "TreeAuto", color = UIKit.color("button_warn") })
		ab.ZIndex = 4
		dy += 14
	end
	local housed = 0
	for _, x in v.pals do
		if x.home ~= 0 then
			housed += 1
		end
	end
	-- (two lines when a language's words run wider than the column)
	local roomText = string.format("%d eggs a lot. In huts %d/%d", Tree.lot(p), housed, v.nests)
	local rl = math.clamp(UIKit.lines(roomText, LW), 1, 2)
	UIKit.text(col, roomText, UDim2.fromOffset(LW, 10 * rl), UDim2.fromOffset(0, dy + 1), { color = if v.nests > 0 and housed >= v.nests then UIKit.color("orange") else UIKit.color("text"), wrap = rl > 1, name = "Room" })
	dy += 10 * (rl - 1)
	-- the odds now, rarity by rarity
	UIKit.text(col, "Odds now", UDim2.fromOffset(LW, 10), UDim2.fromOffset(0, dy + 13), { color = UIKit.color("text_dim") })
	local odds = Tree.odds(p)
	local y = dy + 23
	for r = 1, Traits.RMAX do
		local rar = Traits.RARITY[r]
		local pct = odds[r] * 100
		-- (every rarity can come at every size of island since the request of 2026-11-19: "Make all eggs obtainable
		-- regardless of expansion level, but at a very low chance if they are higher rarity")
		local txt = if odds[r] <= 0 then "none" elseif pct < 0.01 then "<0.01%" elseif pct < 0.1 then string.format("%.2f%%", pct) elseif pct < 1 then string.format("%.1f%%", pct) else string.format("%d%%", math.round(pct))
		UIKit.text(col, rar.name, UDim2.fromOffset(LW - 40, 10), UDim2.fromOffset(0, y), { color = UIKit.color(rar.color), name = "Odds_" .. r })
		UIKit.text(col, txt, UDim2.fromOffset(40, 10), UDim2.fromOffset(LW - 40, y), { x = "right", color = if odds[r] > 0 then UIKit.color("text") else UIKit.color("text_dim") })
		y += 10
	end
	-- (Tuning.EggCount grows on some tiers, EggTier and EggLuck on every one to the last island; one line in place of
	-- the two that were here, the request of 2026-11-14: "Change the two green and yellow texts below the egg rarities
	-- to ...")
	if v.tier < #Tuning.TierCost then
		local growText = "Grow your island for rarer eggs and bigger lots."
		UIKit.text(col, growText, UDim2.fromOffset(LW, 2 + 10 * math.max(2, UIKit.lines(growText, LW))), UDim2.fromOffset(0, y + 2), { color = UIKit.color("good"), wrap = true, name = "Grow" })
	end
	-- the eggs now, the rarest first: the bag's (bought, won or given: GAME_DESIGN 14, free to hatch) over the tree's
	UIKit.text(body, "Under the tree", UDim2.fromOffset(RW, 12), UDim2.fromOffset(RX, 0), { color = UIKit.color("accent"), name = "Eggs" })
	-- the bulk hatch (the request of 2026-11-22: "make a bulk open eggs button, where you open all eggs at once in the
	-- tree", then "selecting as in: bulk buy over a certain rarity"): a tap on one of the rarities' eggs picks the
	-- lowest it takes, and Hatch takes every egg under the tree of that rarity or rarer, the rarest first, as far as
	-- the coins and huts go (EggView.hatchMany; the button says how many and what they cost now: Tree.bulkPlan)
	-- (the count, the egg row and Hatch in a frame of their own: a pick remakes only that frame, not the whole sheet)
	local bulkBar = Instance.new("Frame")
	bulkBar.Name = "BulkBar"
	bulkBar.BackgroundTransparency = 1
	bulkBar.BorderSizePixel = 0
	bulkBar.Size = UDim2.fromOffset(RW, 27)
	bulkBar.Position = UDim2.fromOffset(RX, 0)
	bulkBar.Parent = body
	local function fillBulk()
		UIKit.clear(bulkBar)
		local floorR = math.clamp(bulkFloor, 1, Traits.RMAX)
		local picked = Tree.atLeast(v.clutch :: any, floorR)
		local plain = floorR <= 1
		local countWords = if plain then (if #v.clutch == 1 then Lang.t("1 egg") else Lang.f("{1} eggs", #v.clutch)) else Lang.f("{1} and up: {2}", Lang.t(Traits.RARITY[floorR].name), #picked)
		UIKit.text(bulkBar, Lang.keep(countWords), UDim2.fromOffset(RW - 4, 12), UDim2.fromOffset(0, 0), { x = "right", color = if plain then UIKit.color("text_dim") else UIKit.color(Traits.RARITY[floorR].color), name = "EggCount" })
		local rowW = rarityRow(bulkBar, 0, 14, floorR, false, "Bulk_", function(r: number)
			if r ~= bulkFloor then
				bulkFloor = r
				fillBulk()
			end
		end)
		local pp = asProfile(v)
		pp.clutch = { list = v.clutch }
		local plan = Tree.bulkPlan(pp, picked, false)
		local bw = RW - rowW - 8
		local bulkText = if plan.n > 0 then Lang.f("Hatch {1}: {2}", plan.n, Numbers.coins(plan.cost)) else Lang.t("Hatch all")
		local hb = UIKit.button(bulkBar, bulkText, UDim2.fromOffset(bw, 12), UDim2.fromOffset(rowW + 4, 14), function()
			local now = StateClient.view()
			if now == nil then
				return
			end
			local np = asProfile(now)
			np.clutch = { list = now.clutch }
			local ids = Tree.atLeast(now.clutch :: any, math.clamp(bulkFloor, 1, Traits.RMAX))
			local pl = Tree.bulkPlan(np, ids, false)
			if pl.n > 0 then
				EggView.hatchMany(bulkFloor, false)
				return
			end
			Audio.play("deny")
			local why = if #ids == 0 then "No eggs that rare under the tree." elseif pl.room > 0 then Words.errText(if now.nests > 0 then "full" else "no_hut") else Words.errText("money")
			UIKit.notice(why, UIKit.color("bad"))
		end, { name = "BulkHatch", color = if plan.n > 0 then UIKit.color("button_ok") else UIKit.color("plate_light") })
		hb.ZIndex = 4
		if plan.n > 0 then
			local words = hb:FindFirstChild("Words")
			if words and words:IsA("GuiObject") then
				words.Position = UDim2.fromOffset(2, 0)
				words.Size = UDim2.new(1, -16, 1, 0)
			end
			PixelSprites.image(hb, "mini_coin", UDim2.new(1, -13, 0, 0), 6).Name = "PriceIcon"
		end
	end
	fillBulk()
	local list = UIKit.scroll(body, UDim2.fromOffset(RW, H - 30), UDim2.fromOffset(RX, 30))
	list.Name = "List"
	UIKit.vlist(list, 2)
	local bag: { Types.Bagged } = table.clone(v.bag or {})
	table.sort(bag, function(a: Types.Bagged, b: Types.Bagged): boolean
		if a.r ~= b.r then
			return a.r > b.r
		end
		return a.id < b.id
	end)
	local base = 0
	if #bag > 0 then
		local hf = row(list, 1, 12)
		hf.Name = "BagHead"
		UIKit.text(hf, string.format("Your eggs: %d", #bag), UDim2.new(1, -8, 1, 0), UDim2.fromOffset(4, 1), { color = UIKit.color("good"), z = 4, name = "BagTitle" })
		-- (every one at once, free: the bulk hatch of the bag's eggs)
		if #bag >= 2 then
			local aw = math.max(56, UIKit.buttonWidth(Lang.t("Hatch all"), 6))
			UIKit.button(hf, "Hatch all", UDim2.fromOffset(aw, 10), UDim2.new(1, -aw - 3, 0, 1), function()
				EggView.hatchMany(1, true)
			end, { name = "BagHatchAll", color = UIKit.color("button_ok") }).ZIndex = 4
		end
		for k, e in bag do
			local rar = Traits.RARITY[e.r] or Traits.RARITY[1]
			local f = row(list, 1 + k, 26)
			f.Name = "BagEgg_" .. e.id
			PixelSprites.image(f, "egg_" .. math.clamp(e.r, 1, Traits.RMAX), UDim2.fromOffset(6, 5), 4)
			UIKit.text(f, rar.name, UDim2.fromOffset(RW - 86, 10), UDim2.fromOffset(24, 2), { color = UIKit.color(rar.color), z = 4, name = "Name" })
			UIKit.text(f, "Free to hatch", UDim2.fromOffset(RW - 30, 10), UDim2.fromOffset(24, 14), { color = UIKit.color("text_dim"), z = 4 })
			local id = e.id
			UIKit.button(f, "Hatch", UDim2.fromOffset(56, 12), UDim2.new(1, -59, 0, 1), function()
				EggView.hatchBag(id)
			end, { name = "BagHatch_" .. e.id, color = UIKit.color("button_ok") }).ZIndex = 4
		end
		base = 1 + #bag
	end
	local shown = EggView.best(v, #v.clutch)
	if #shown == 0 then
		local f = row(list, base + 1, 24)
		UIKit.text(f, "No eggs left. More soon.", UDim2.new(1, -10, 1, -4), UDim2.fromOffset(5, 2), { color = UIKit.color("text_dim"), z = 4, wrap = true })
	end
	for i0, e in shown do
		local i = base + i0
		local rar = Traits.RARITY[e.r] or Traits.RARITY[1]
		-- (an egg the weather touched, GAME_DESIGN 13: where it was laid, and the mutation it hatches with on a third
		-- line, the weather's icon before it)
		local wdef = if e.wx then WeatherData.byId[e.wx] else nil
		local wm = if wdef then Traits.byId[Traits.at(wdef.family or "", e.wt or 1)] else nil
		local f = row(list, i, if wm then 36 else 26)
		f.Name = "Egg_" .. e.id
		PixelSprites.image(f, "egg_" .. math.clamp(e.r, 1, Traits.RMAX), UDim2.fromOffset(6, 5), 4)
		local tw = RW - 86
		UIKit.text(f, rar.name, UDim2.fromOffset(tw, 10), UDim2.fromOffset(24, 2), { color = UIKit.color(rar.color), z = 4, name = "Name" })
		if wdef and wm then
			UIKit.text(f, wdef.laid, UDim2.fromOffset(tw, 10), UDim2.fromOffset(24, 12), { color = UIKit.color("text_dim"), z = 4, name = "Laid" })
			PixelSprites.image(f, "mini_" .. wdef.icon, UDim2.fromOffset(24, 23), 4).Name = "WeatherIcon"
			local tc = Traits.TIER_COLOR[wm.tier] or "text"
			TierStars.label(f, wm.name, wm.tier, 37, 22, { color = UIKit.color(tc), z = 4, name = "WeatherMut" })
		else
			-- ("Hatches an x creature": the request of 2026-11-15, in place of "an x one"; under the price, the row's
			-- whole width)
			UIKit.text(f, Lang.an("Hatches an {1} creature", "Hatches a {1} creature", rar.name), UDim2.fromOffset(RW - 30, 10), UDim2.fromOffset(24, 14), { color = UIKit.color("text_dim"), z = 4, name = "Hatches" })
		end
		-- Hatch: its price (the shells and the shell icon after them)
		local cost = e.cost or 0
		local text = Numbers.coins(cost)
		local can = v.shells >= cost
		local id = e.id
		-- (beside the rarity's name, so the words under it have the row's width)
		local r = e.r
		local b = UIKit.button(f, text, UDim2.fromOffset(56, 12), UDim2.new(1, -59, 0, 1), function()
			-- (short of shells: the egg for Robux instead, StoreUI.eggInstead)
			local now = StateClient.view()
			if now and now.shells < cost then
				StoreUI.eggInstead(r)
				return
			end
			EggView.hatch(id)
		end, { name = "PanelHatch_" .. e.id, color = if can then UIKit.color("button_ok") else UIKit.color("plate_light") })
		b.ZIndex = 4
		local words = b:FindFirstChild("Words")
		if words and words:IsA("GuiObject") then
			words.Position = UDim2.fromOffset(2, 0)
			words.Size = UDim2.new(1, -16, 1, 0)
		end
		PixelSprites.image(b, "mini_coin", UDim2.new(1, -13, 0, 0), 6).Name = "PriceIcon"
	end
	-- under the eggs, eggs to buy (into the bag above, free to hatch: StoreUI.eggRows)
	StoreUI.eggRows(list, base + math.max(1, #shown) + 1, RW)
end

------------------------------------------------------------------ Index: the driftlings
local function buildIndex(body: Frame, _arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local seen = 0
	for _, d in Creatures.list do
		if (v.seen[d.id] or 0) >= 1 then
			seen += 1
		end
	end
	UIKit.text(body, string.format("Seen %d of %d kinds", seen, #Creatures.list), UDim2.fromOffset(W, 12), UDim2.fromOffset(0, 0), { color = UIKit.color("text_dim"), name = "Found" })
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - 14), UDim2.fromOffset(0, 14))
	local cols = if W >= 300 then 3 else 2
	local grid = Instance.new("UIGridLayout")
	-- (90 tall: a passive's effects take up to four lines at a card's width, "+7.5% work, Hatchery eggs 4% sooner, +20%
	-- sell price" three; they had two and ended in "...", the request of 2026-11-19: "it seems like the text gets cut
	-- off for some alerts")
	grid.CellSize = UDim2.fromOffset(math.floor((W - 6 - (cols - 1) * 3) / cols), 90)
	grid.CellPadding = UDim2.fromOffset(3, 3)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list
	for i, d in Creatures.list do
		local n = v.seen[d.id] or 0
		-- (a veil over the glass; a stronger one once it has been met)
		local f = UIKit.row(list, UDim2.fromOffset(60, 90), nil, nil, if n >= 2 then 0.84 else 0.92)
		f.Name = "Entry_" .. d.id
		f.LayoutOrder = i
		local rar = Traits.RARITY[d.rarity] or Traits.RARITY[1]
		-- (the words start right of the 32 px portrait, 65 px for them: Glimmerfleece's name is 65)
		PixelSprites.image(f, if n >= 1 then "icon_" .. d.id else "icon_" .. d.id .. "_sil", UDim2.fromOffset(2, 3), 4)
		UIKit.text(f, if n >= 1 then d.name else "???", UDim2.new(1, -35, 0, 10), UDim2.fromOffset(35, 4), { color = if n >= 1 then UIKit.color(rar.color) else UIKit.color("text_dim"), z = 4, name = "Name" })
		-- its rarity (always: a rare one is worth hoping for) and its kind of land, each a line beside the portrait
		local kind = Islets.list[d.islet]
		if kind then
			UIKit.text(f, kind.plural, UDim2.new(1, -35, 0, 10), UDim2.fromOffset(35, 22), { color = UIKit.color("text_dim"), z = 4, name = "Land" })
		end
		UIKit.text(f, rar.name, UDim2.new(1, -35, 0, 10), UDim2.fromOffset(35, 13), { color = UIKit.color(rar.color), z = 4, name = "Rarity" })
		if n >= 1 then
			-- seen: its passive
			UIKit.text(f, d.passive.name, UDim2.new(1, -6, 0, 10), UDim2.fromOffset(3, 38), { color = UIKit.color("accent"), z = 4, name = "Passive" })
			UIKit.text(f, Traits.describe(d.passive.fx), UDim2.new(1, -6, 0, 40), UDim2.fromOffset(3, 48), { color = UIKit.color("text_dim"), wrap = true, y = "top", z = 4, name = "PassiveFx" })
		else
			local from = if kind and kind.tier > v.tier then string.format("From island Lv %d.", kind.tier) else "Not seen yet."
			UIKit.text(f, from, UDim2.new(1, -6, 0, 30), UDim2.fromOffset(3, 38), { color = UIKit.color("text_dim"), wrap = true, z = 4 })
		end
	end
end

-- What the tips' arrow points at in the Tree of Life's panel while the tips ask for an egg hatched (UI/Hud,
-- UI/TutArrow): one of the player's own eggs (free to hatch) if there is one, else the cheapest egg under the tree
-- the coins cover (a new player's first egg, not the rare one that would take the coins the island needs), the
-- highest in the list of those; worked out again when the panel is built again.
local tipBtn: GuiObject? = nil
local tipFrame: Frame? = nil
function Menus.tipTarget(): GuiObject?
	local f = if UIKit.currentPanel() == "tree" then UIKit.currentPanelFrame() else nil
	local v = StateClient.view()
	if f == nil or v == nil then
		tipBtn, tipFrame = nil, nil
		return nil
	end
	local b = tipBtn
	if f == tipFrame and b and b.Parent then
		return b
	end
	local cost: { [string]: number } = {}
	for _, e in v.clutch do
		cost[tostring(e.id)] = e.cost or 0
	end
	local best: GuiObject? = nil
	local bestCost, bestOrder = math.huge, math.huge
	for _, d in f:GetDescendants() do
		if d:IsA("GuiButton") then
			local c: number? = nil
			if string.sub(d.Name, 1, 9) == "BagHatch_" then
				c = 0
			elseif string.sub(d.Name, 1, 11) == "PanelHatch_" then
				c = cost[string.sub(d.Name, 12)]
			end
			if c and c <= v.shells then
				local rowF = d.Parent
				local order = if rowF and rowF:IsA("GuiObject") then rowF.LayoutOrder else 0
				if c < bestCost or (c == bestCost and order < bestOrder) then
					best, bestCost, bestOrder = d, c, order
				end
			end
		end
	end
	tipBtn, tipFrame = best, f
	return best
end

function Menus.init()
	-- (a hatch the server refuses for shells, the swap picker's among them: the egg for Robux instead)
	EggView.onShort = StoreUI.eggInstead
	UIKit.registerPanel("pals", { title = "Driftlings", icon = "pal", w = 320, h = 186, props = { "leaf", "pal" }, build = buildPals })
	UIKit.registerPanel("pal", { title = "Driftling", icon = "pal", w = 320, h = 182, build = buildPal })
	UIKit.registerPanel("hatch", { title = "Hatchery", icon = "nest", w = 320, h = 186, props = { "egg_2", "egg_5" }, build = buildHatch })
	UIKit.registerPanel("tree", { title = "Tree of Life", icon = "tree", w = 380, h = 226, props = { "egg_1", "egg_3", "egg_6" }, build = buildTree })
	-- ("Hatched@@panel": the panel's title, apart from the stats' "Hatched", a count in some languages: Locale/Lang)
	UIKit.registerPanel("hatched", { title = "Hatched@@panel", icon = "egg", w = 380, h = 226, props = { "egg_2", "egg_4", "egg_7" }, build = buildHatched })
	UIKit.registerPanel("index", { title = "Index", icon = "star", w = 320, h = 186, props = { "search", "star" }, build = buildIndex })
	-- (Looks, with the founder's pieces and titles, is UI/StoreUI's since 2026-11-14)

end

return Menus
