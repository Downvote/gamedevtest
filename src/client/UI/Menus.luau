--!strict
-- The HUD's panels (docs/ARCHITECTURE.md 10.4; GAME_DESIGN 5-9): Villagers (who lives here, their jobs, dismissing),
-- Driftlings (the befriended ones, where they help, releasing), Explore (the sea chart: an island to sail to, the
-- boat's upgrade, the party: Set sail), Index
-- (every driftling met or befriended) and Looks (the founder's look). Every action is a request; the panel rebuilds
-- from the next view. A job or help picker is the same panel with an argument ({ folk = id } / { pal = id }).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Buildings = require(ReplicatedStorage.Shared.Data.Buildings)
local Creatures = require(ReplicatedStorage.Shared.Data.Creatures)
local Islets = require(ReplicatedStorage.Shared.Data.Islets)
local Looks = require(ReplicatedStorage.Shared.Data.Looks)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local Battle = require(ReplicatedStorage.Shared.Logic.Battle)
local Island = require(ReplicatedStorage.Shared.Logic.Island)
local Chart = require(ReplicatedStorage.Shared.Logic.Chart)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local SeaMap = require(script.Parent.SeaMap)
local ExpeditionUI = require(script.Parent.ExpeditionUI)
local Words = require(script.Parent.Words)

local Menus = {}

local KNACKS: { [string]: string } = { farm = "farms", fish = "fishing piers", wood = "lumber camps", shop = "shops" }

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

-- A panel's hint over its list: one line, or two when it is too long for the panel (it never runs off the edge).
-- Returns where the list under it starts.
local function hint(body: Instance, text: string, w: number): number
	local two = UIKit.textWidth(text) > w
	UIKit.text(body, text, UDim2.fromOffset(w, if two then 22 else 12), UDim2.fromOffset(0, 0), { color = UIKit.color("text_dim"), name = "Hint", wrap = two })
	return if two then 24 else 14
end

local function row(list: Instance, order: number, h: number): Frame
	local f = UIKit.plate(list, UDim2.new(1, -6, 0, h), nil, UIKit.color("plate_light"), 0, 2, { bevel = true })
	f.Name = "Row"
	f.LayoutOrder = order
	return f
end

local function away(v: Types.ClientView, key: string): boolean
	local e = v.exp
	if e == nil then
		return false
	end
	for _, f in e.party do
		if f.key == key then
			return true
		end
	end
	return false
end

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

-- A two-tap button (Dismiss, Release): the first tap asks "Sure?", a second within 3 s does it.
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

-- The stats line of a fighter: "HP 30 ATK 8 DEF 5 SPD 6".
local function statLine(f: Types.Fighter): string
	return string.format("HP %d  ATK %d  DEF %d  SPD %d", f.maxHp, f.atk, f.def, f.spd)
end

------------------------------------------------------------------ the job / help picker
-- The buildings a villager (pal == nil) or a driftling (its knack) can work at, the one there now, and Rest.
local function buildPicker(body: Frame, v: Types.ClientView, folkId: number?, palId: number?)
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local knack: string? = nil
	local name = "?"
	local current = 0
	if palId then
		for _, x in v.pals do
			if x.id == palId then
				local d = Creatures.byId[x.sp]
				knack = if d then d.knack else nil
				name = if d then d.name else x.sp
				current = x.work
			end
		end
	else
		for _, x in v.folk do
			if x.id == folkId then
				name = x.name
				current = x.work
			end
		end
	end
	local top = hint(body, if palId then string.format("Where should %s help? (%s)", name, KNACKS[knack or ""] or "") else string.format("Where should %s work?", name), W - 50)
	UIKit.button(body, "Back", UDim2.fromOffset(44, 12), UDim2.fromOffset(W - 44, 0), function()
		UIKit.openPanel(if palId then "pals" else "folk")
	end, { name = "Back", color = UIKit.color("plate_light") })
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - top), UDim2.fromOffset(0, top))
	UIKit.vlist(list, 2)
	local who: { [number]: string } = {}
	if palId then
		for _, x in v.pals do
			if x.work ~= 0 then
				local d = Creatures.byId[x.sp]
				who[x.work] = if d then d.name else x.sp
			end
		end
	else
		for _, x in v.folk do
			if x.work ~= 0 then
				who[x.work] = x.name
			end
		end
	end
	local order = 0
	local function choose(uid: number)
		local res = if palId then ask("pal.work", { id = palId, uid = uid }) else ask("folk.work", { id = folkId, uid = uid })
		if res.ok then
			Audio.play("ding")
			UIKit.openPanel(if palId then "pals" else "folk")
		end
	end
	for _, q in v.pieces do
		local d = Buildings.byId[q.id]
		if d and Island.works(q.id) and (knack == nil or d.knack == knack) then
			order += 1
			local f = row(list, order, 22)
			f.Name = "Spot_" .. q.uid
			PixelSprites.image(f, "mini_" .. (if d.kind == "shop" then "shell" else d.kind), UDim2.fromOffset(4, 5), 4)
			UIKit.text(f, d.name .. (if q.lvl > 1 then " Lv" .. q.lvl else ""), UDim2.new(1, -90, 0, 10), UDim2.fromOffset(18, 1), { color = UIKit.color("text"), z = 4 })
			local there = who[q.uid]
			UIKit.text(f, if there then (if q.uid == current then "Here now" else there .. " is here") else "Nobody yet", UDim2.new(1, -90, 0, 10), UDim2.fromOffset(18, 11), { color = if there then UIKit.color("text_dim") else UIKit.color("good"), z = 4 })
			local b = UIKit.button(f, if q.uid == current then "Here" elseif there then "Swap" else "Go", UDim2.fromOffset(60, 14), UDim2.new(1, -64, 0, 4), function()
				choose(q.uid)
			end, { name = "Go_" .. q.uid, color = UIKit.color("button_ok"), enabled = q.uid ~= current })
			b.ZIndex = 4
		end
	end
	if order == 0 then
		local f = row(list, 1, 22)
		UIKit.text(f, if knack then "No " .. (KNACKS[knack] or "spots") .. " on the island yet: build one." else "Nothing to work at yet: build a patch or a camp.", UDim2.new(1, -10, 1, -4), UDim2.fromOffset(5, 2), { color = UIKit.color("text_dim"), z = 4, wrap = true })
	end
	local f = row(list, order + 1, 22)
	f.Name = "Rest"
	UIKit.text(f, if palId then "Rest at the nest (trains at a yard)" else "Rest (trains at a yard)", UDim2.new(1, -90, 0, 10), UDim2.fromOffset(6, 6), { color = UIKit.color("text"), z = 4 })
	UIKit.button(f, "Rest", UDim2.fromOffset(60, 14), UDim2.new(1, -64, 0, 4), function()
		choose(0)
	end, { name = "Go_0", enabled = current ~= 0 }).ZIndex = 4
end

------------------------------------------------------------------ Villagers
local function buildFolk(body: Frame, arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	if type(arg) == "table" and type(arg.folk) == "number" then
		buildPicker(body, v, arg.folk, nil)
		return
	end
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local top = hint(body, string.format("%d villagers, %d beds. A visitor moves into a free bed at dawn when the charm is high enough.", #v.folk, v.beds), W)
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - top), UDim2.fromOffset(0, top))
	UIKit.vlist(list, 2)
	if #v.folk == 0 then
		local f = row(list, 1, 24)
		UIKit.text(f, "Nobody lives here yet. Build a Tent: a castaway may move in at dawn.", UDim2.new(1, -10, 1, -4), UDim2.fromOffset(5, 2), { color = UIKit.color("text_dim"), z = 4, wrap = true })
	end
	for i, x in v.folk do
		local f = row(list, i, 34)
		f.Name = "Folk_" .. x.id
		UIKit.portrait(f, x.look, 30, UDim2.fromOffset(2, 2))
		local gone = away(v, "v" .. x.id)
		UIKit.text(f, x.name, UDim2.fromOffset(90, 10), UDim2.fromOffset(36, 1), { color = UIKit.color("accent"), z = 4, name = "Name" })
		UIKit.text(f, string.format("Lv %d", x.lvl), UDim2.fromOffset(34, 10), UDim2.fromOffset(36 + UIKit.textWidth(x.name) + 6, 1), { color = UIKit.color("text"), z = 4 })
		local job = if gone then "Away on an expedition" elseif x.work ~= 0 then (function(): string
			local q = pieceOf(v, x.work)
			local d = if q then Buildings.byId[q.id] else nil
			return if d then d.job .. " at the " .. d.name else "Working"
		end)() else "Resting"
		UIKit.text(f, job, UDim2.new(1, -150, 0, 10), UDim2.fromOffset(36, 11), { color = if gone then UIKit.color("orange") elseif x.work ~= 0 then UIKit.color("good") else UIKit.color("text_dim"), z = 4, name = "Job" })
		UIKit.text(f, statLine(Battle.villager(x)), UDim2.new(1, -150, 0, 10), UDim2.fromOffset(36, 21), { color = UIKit.color("text_dim"), z = 4 })
		local jb = UIKit.button(f, "Job", UDim2.fromOffset(46, 13), UDim2.new(1, -104, 0, 10), function()
			UIKit.openPanel("folk", { folk = x.id })
		end, { name = "Job_" .. x.id, color = UIKit.color("button_ok"), enabled = not gone })
		jb.ZIndex = 4
		if not gone then
			confirmButton(f, "Dismiss", UDim2.fromOffset(52, 13), UDim2.new(1, -55, 0, 10), function()
				local res = ask("folk.dismiss", { id = x.id }, x.name .. " sailed off. Bye!")
				if res.ok then
					Audio.play("close")
				end
			end, "Dismiss_" .. x.id)
		end
	end
end

------------------------------------------------------------------ Driftlings
local function buildPals(body: Frame, arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	if type(arg) == "table" and type(arg.pal) == "number" then
		buildPicker(body, v, nil, arg.pal)
		return
	end
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local top = hint(body, string.format("%d driftlings, nests for %d. Befriend more on expeditions with a snack.", #v.pals, v.nests), W)
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - top), UDim2.fromOffset(0, top))
	UIKit.vlist(list, 2)
	if #v.pals == 0 then
		local f = row(list, 1, 24)
		UIKit.text(f, "No driftlings yet. Build a nest, then Explore: a snack in battle may befriend one.", UDim2.new(1, -10, 1, -4), UDim2.fromOffset(5, 2), { color = UIKit.color("text_dim"), z = 4, wrap = true })
	end
	for i, x in v.pals do
		local d = Creatures.byId[x.sp]
		if d == nil then
			continue
		end
		local f = row(list, i, 34)
		f.Name = "Pal_" .. x.id
		PixelSprites.image(f, "icon_" .. x.sp, UDim2.fromOffset(4, 9), 4)
		local gone = away(v, "p" .. x.id)
		UIKit.text(f, d.name, UDim2.fromOffset(90, 10), UDim2.fromOffset(24, 1), { color = UIKit.color("accent"), z = 4, name = "Name" })
		UIKit.text(f, string.format("Lv %d  %s", x.lvl, Creatures.skills[d.skill] or d.skill), UDim2.new(1, -140, 0, 10), UDim2.fromOffset(24 + UIKit.textWidth(d.name) + 6, 1), { color = UIKit.color("text"), z = 4 })
		local where = if gone then "Away on an expedition" elseif x.work ~= 0 then "Helping at the " .. (buildingName(v, x.work) or "?") else "Resting (helps at " .. (KNACKS[d.knack] or d.knack) .. ")"
		UIKit.text(f, where, UDim2.new(1, -140, 0, 10), UDim2.fromOffset(24, 11), { color = if gone then UIKit.color("orange") elseif x.work ~= 0 then UIKit.color("good") else UIKit.color("text_dim"), z = 4, name = "Where" })
		UIKit.text(f, statLine(Battle.pal(x)), UDim2.new(1, -140, 0, 10), UDim2.fromOffset(24, 21), { color = UIKit.color("text_dim"), z = 4 })
		local hb = UIKit.button(f, "Help", UDim2.fromOffset(46, 13), UDim2.new(1, -104, 0, 10), function()
			UIKit.openPanel("pals", { pal = x.id })
		end, { name = "Help_" .. x.id, color = UIKit.color("button_ok"), enabled = not gone })
		hb.ZIndex = 4
		if not gone then
			confirmButton(f, "Release", UDim2.fromOffset(52, 13), UDim2.new(1, -55, 0, 10), function()
				local res = ask("pal.release", { id = x.id }, d.name .. " went home to the wild.")
				if res.ok then
					Audio.play("close")
				end
			end, "Release_" .. x.id)
		end
	end
end

------------------------------------------------------------------ Explore: the sea chart, an island, the party
-- The chart (GAME_DESIGN 7; Logic/Chart): the player's own islands round home, the boat's range a dotted ring (the
-- next boat's a dim one), islands past it dark; a tap picks one (its kind, level, driftlings, guardian), Set sail.
local chosenIsle = 0
local party: { string } = {} -- member keys in the order picked ("v3", "p7")

local function memberOk(v: Types.ClientView, key: string): boolean
	local kind, id = string.match(key, "^([vp])(%d+)$")
	local n = tonumber(id) or 0
	for _, x in (if kind == "v" then v.folk else v.pals) :: { any } do
		if x.id == n then
			return true
		end
	end
	return false
end

-- Who could join the party, the strongest first (level, then health): the list's order and the party's first picks.
type Cand = { key: string, name: string, lvl: number, f: Types.Fighter, icon: string?, look: Types.Look? }
local function rankMembers(v: Types.ClientView): { Cand }
	local cands: { Cand } = {}
	for _, x in v.folk do
		table.insert(cands, { key = "v" .. x.id, name = x.name, lvl = x.lvl, f = Battle.villager(x), look = x.look })
	end
	for _, x in v.pals do
		local cd = Creatures.byId[x.sp]
		table.insert(cands, { key = "p" .. x.id, name = if cd then cd.name else x.sp, lvl = x.lvl, f = Battle.pal(x), icon = "icon_" .. x.sp })
	end
	table.sort(cands, function(a, b)
		if a.lvl ~= b.lvl then
			return a.lvl > b.lvl
		end
		if a.f.maxHp ~= b.f.maxHp then
			return a.f.maxHp > b.f.maxHp
		end
		return a.key < b.key
	end)
	return cands
end

-- (the party's slots fill themselves with the strongest when the chart opens; the player can change them after)
local partyFilled = false

local function buildExplore(body: Frame, _arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	for i = #party, 1, -1 do
		if not memberOk(v, party[i]) then
			table.remove(party, i)
		end
	end
	-- the party's slots: the strongest go in by themselves when the chart opens (GAME_DESIGN 7: "party slots should
	-- auto equip with the strongest party members"); the player can swap them after
	if not partyFilled then
		partyFilled = true
		if v.exp == nil then
			table.clear(party)
			for _, c in rankMembers(v) do
				if #party >= Tuning.PartyMax then
					break
				end
				table.insert(party, c.key)
			end
		end
	end
	local isles = Chart.islands(v.sea)
	local range = Chart.radius(v.boat)
	local function charted(id: number): boolean
		return table.find(v.chart, id) ~= nil
	end
	-- the island picked: kept while it is in range, else the strongest one not charted yet in range, else the nearest
	if not (isles[chosenIsle] and isles[chosenIsle].dist <= range) then
		chosenIsle = 1
		for _, c in isles do
			if c.dist <= range and not charted(c.id) and c.lvl <= math.max(1, v.cap.lvl) + 1 and c.lvl >= isles[chosenIsle].lvl then
				chosenIsle = c.id
			end
		end
	end
	-- the chart on the left: the islands drawn as a map (UI/SeaMap); a tap picks one
	local S = math.min(H - 16, math.floor(W * 0.58))
	local cap = math.max(1, v.cap.lvl)
	SeaMap.draw(body, S, UDim2.fromOffset(0, 0), {
		sea = v.sea,
		boat = v.boat,
		chart = v.chart,
		cap = cap,
		chosen = chosenIsle,
		onPick = function(id: number)
			chosenIsle = id
			Audio.play("flip")
			UIKit.refreshPanel()
		end,
		onFar = function(_id: number)
			Audio.play("deny")
			UIKit.notice(Words.errText("far"), UIKit.color("bad"))
		end,
	})
	-- the boat under the chart: its level and the next one's price
	local lvText = string.format("Lv %d", v.boat)
	local bc = Chart.boatCost(v.boat)
	local px = 0
	if bc then
		local bw = UIKit.buttonWidth("Upgrade", 6)
		local st, wt = Numbers.coins(bc.shells), Numbers.coins(bc.wood)
		px = S - bw - 3 - UIKit.textWidth(wt) - 12 - UIKit.textWidth(st) - 13
	end
	if px < 12 + UIKit.textWidth(lvText) + 3 then
		-- a narrow chart (a phone): the boat's level sits on a small board in the chart's corner, so the price and
		-- Upgrade keep the row under it
		local tag = UIKit.plate(body, UDim2.fromOffset(UIKit.textWidth(lvText) + 18, 13), UDim2.fromOffset(2, 2), UIKit.color("plate"), 0.1, 2, { bevel = true })
		tag.ZIndex = 5
		PixelSprites.image(tag, "mini_boat", UDim2.fromOffset(2, 1), 6)
		UIKit.text(tag, lvText, UDim2.fromOffset(UIKit.textWidth(lvText) + 2, 10), UDim2.fromOffset(14, 1), { color = UIKit.color("accent"), name = "BoatLv", z = 6 })
		px = math.max(0, px)
	else
		PixelSprites.image(body, "mini_boat", UDim2.fromOffset(0, S + 3), 4)
		UIKit.text(body, lvText, UDim2.fromOffset(UIKit.textWidth(lvText) + 2, 10), UDim2.fromOffset(12, S + 4), { color = UIKit.color("accent"), name = "BoatLv" })
	end
	if bc then
		local short = v.shells < bc.shells or v.wood < bc.wood
		local bw = UIKit.buttonWidth("Upgrade", 6)
		local bx = S - bw
		-- the price: shells and wood, red where short
		local st, wt = Numbers.coins(bc.shells), Numbers.coins(bc.wood)
		PixelSprites.image(body, "mini_shell", UDim2.fromOffset(px, S + 3), 4)
		UIKit.text(body, st, UDim2.fromOffset(UIKit.textWidth(st) + 2, 10), UDim2.fromOffset(px + 11, S + 4), { color = if v.shells < bc.shells then UIKit.color("bad") else UIKit.color("text"), name = "BoatShells" })
		local wx = px + 13 + UIKit.textWidth(st)
		PixelSprites.image(body, "mini_wood", UDim2.fromOffset(wx, S + 3), 4)
		UIKit.text(body, wt, UDim2.fromOffset(UIKit.textWidth(wt) + 2, 10), UDim2.fromOffset(wx + 11, S + 4), { color = if v.wood < bc.wood then UIKit.color("bad") else UIKit.color("text"), name = "BoatWood" })
		UIKit.button(body, "Upgrade", UDim2.fromOffset(bw, 13), UDim2.fromOffset(bx, S + 2), function()
			local res = ask("boat.upgrade", {})
			if res.ok then
				Audio.play("level_up")
				UIKit.notice("A bigger boat: it sails further now!", UIKit.color("good"), 3)
				UIKit.refreshPanel()
			end
		end, { name = "BoatUp", color = if short then UIKit.color("button_off") else UIKit.color("button_ok"), enabled = v.exp == nil })
	else
		UIKit.text(body, "The finest boat afloat", UDim2.fromOffset(S - 60, 10), UDim2.fromOffset(60, S + 4), { color = UIKit.color("good"), x = "right", name = "BoatMax" })
	end
	-- the island picked, on the right
	local x0 = S + 5
	local RW = W - x0
	local c = isles[chosenIsle]
	local isle = Chart.isle(v.sea, chosenIsle) :: Types.Isle
	local kind = Islets.list[isle.kind]
	UIKit.text(body, isle.name, UDim2.fromOffset(RW, 10), UDim2.fromOffset(x0, 0), { color = UIKit.color("accent"), name = "IsleName" })
	local lvCol = if c.lvl <= cap then UIKit.color("good") elseif c.lvl <= cap + 3 then UIKit.color("accent") else UIKit.color("bad")
	UIKit.text(body, string.format("%s, level %d", kind.name, c.lvl), UDim2.fromOffset(RW, 10), UDim2.fromOffset(x0, 10), { color = lvCol, name = "IsleKind" })
	local ix = x0
	for _, sp in isle.wild do
		local seen = (v.seen[sp] or 0) > 0
		PixelSprites.image(body, if seen then "icon_" .. sp else "icon_" .. sp .. "_sil", UDim2.fromOffset(ix, 21), 4)
		ix += 18
	end
	local done = charted(chosenIsle)
	local reward = if done then math.floor(isle.reward / 2) else isle.reward
	local rt = Numbers.coins(reward)
	local rw = UIKit.textWidth(rt)
	PixelSprites.image(body, "mini_shell", UDim2.fromOffset(W - rw - 14, 24), 4)
	UIKit.text(body, rt, UDim2.fromOffset(rw + 2, 10), UDim2.fromOffset(W - rw - 2, 25), { color = UIKit.color("accent"), name = "Reward" })
	UIKit.text(body, if done then "Charted" else "Not charted", UDim2.fromOffset(math.max(10, W - rw - 16 - ix - 2), 10), UDim2.fromOffset(ix + 2, 25), { color = if done then UIKit.color("good") else UIKit.color("text_dim"), name = "Charted" })
	local y0 = -2
	-- the party: the captain, then up to PartyMax picks
	-- (on a phone the count sits at the end of the island's kind line: the list gets the room)
	local listY = y0 + 51
	if UIKit.phone() then
		UIKit.text(body, string.format("Party %d/%d", 1 + #party, 1 + Tuning.PartyMax), UDim2.fromOffset(RW, 10), UDim2.fromOffset(x0, 10), { color = UIKit.color("text_dim"), name = "PartyHint", x = "right" })
		listY = y0 + 39
	else
		UIKit.text(body, string.format("Party %d/%d (the captain always goes)", 1 + #party, 1 + Tuning.PartyMax), UDim2.fromOffset(RW, 10), UDim2.fromOffset(x0, y0 + 40), { color = UIKit.color("text_dim"), name = "PartyHint" })
	end
	local pl = UIKit.scroll(body, UDim2.fromOffset(RW, H - 46 - listY - 1), UDim2.fromOffset(x0, listY))
	UIKit.vlist(pl, 2)
	local function member(order: number, key: string, name: string, lvl: number, f: Types.Fighter, icon: string?, look: Types.Look?)
		local picked = key == "f" or table.find(party, key) ~= nil
		local gone = key ~= "f" and v.exp ~= nil
		local b = Instance.new("TextButton")
		b.Name = "Member_" .. key
		b.Text = ""
		b.AutoButtonColor = key ~= "f"
		b.BackgroundTransparency = 1
		b.Size = UDim2.new(1, -6, 0, 20)
		b.LayoutOrder = order
		b.ZIndex = 3
		UIKit.plate(b, UDim2.fromScale(1, 1), nil, if picked then UIKit.color("button_ok") else UIKit.color("plate_light"), 0, 2, { bevel = true }).ZIndex = 3
		if icon then
			PixelSprites.image(b, icon, UDim2.fromOffset(2, 2), 4)
		elseif look then
			UIKit.portrait(b, look, 16, UDim2.fromOffset(2, 2)).ZIndex = 4
		end
		UIKit.text(b, string.format("%s  Lv %d", name, lvl), UDim2.new(1, -24, 0, 10), UDim2.fromOffset(21, 0), { color = UIKit.color("text"), z = 4 })
		UIKit.text(b, string.format("HP %d  ATK %d  DEF %d", f.maxHp, f.atk, f.def), UDim2.new(1, -24, 0, 10), UDim2.fromOffset(21, 9), { color = UIKit.color("text_dim"), z = 4 })
		b.Activated:Connect(function()
			if key == "f" or gone then
				return
			end
			local k = table.find(party, key)
			if k then
				table.remove(party, k)
			elseif #party < Tuning.PartyMax then
				table.insert(party, key)
				UIKit.burstOn(b, { "good", "white" }, 8, 30)
			else
				Audio.play("deny")
				UIKit.notice(string.format("A party is the captain and %d more.", Tuning.PartyMax), UIKit.color("bad"))
				return
			end
			Audio.play("flip")
			UIKit.refreshPanel()
		end)
		b.Parent = pl
	end
	local captain = Battle.founder({ cap = v.cap, founder = v.founder } :: any)
	member(0, "f", "You (captain)", v.cap.lvl, captain, nil, v.founder)
	-- the strongest first
	for i, cand in rankMembers(v) do
		member(i, cand.key, cand.name, cand.lvl, cand.f, cand.icon, cand.look)
	end
	-- the snack pouch (GAME_DESIGN 7: snacks a trip, 5 up to 30): a bigger one for shells and wood
	local pouch = v.pouch or 1
	UIKit.text(body, string.format("Snacks: %d a trip", Tuning.SnackBase * pouch), UDim2.fromOffset(90, 10), UDim2.fromOffset(x0, H - 43), { color = UIKit.color("pink"), name = "Snacks" })
	local pc = Tuning.PouchCost[pouch + 1]
	if pc then
		local bw = UIKit.buttonWidth("Bigger pouch", 5)
		local short = v.shells < pc.shells or v.wood < pc.wood
		local st, wt = Numbers.coins(pc.shells), Numbers.coins(pc.wood)
		local px = W - bw - 3 - UIKit.textWidth(wt) - 12 - UIKit.textWidth(st) - 13
		PixelSprites.image(body, "mini_shell", UDim2.fromOffset(px, H - 44), 4)
		UIKit.text(body, st, UDim2.fromOffset(UIKit.textWidth(st) + 2, 10), UDim2.fromOffset(px + 11, H - 43), { color = if v.shells < pc.shells then UIKit.color("bad") else UIKit.color("text"), name = "PouchShells" })
		local wx = px + 13 + UIKit.textWidth(st)
		PixelSprites.image(body, "mini_wood", UDim2.fromOffset(wx, H - 44), 4)
		UIKit.text(body, wt, UDim2.fromOffset(UIKit.textWidth(wt) + 2, 10), UDim2.fromOffset(wx + 11, H - 43), { color = if v.wood < pc.wood then UIKit.color("bad") else UIKit.color("text"), name = "PouchWood" })
		UIKit.button(body, "Bigger pouch", UDim2.fromOffset(bw, 13), UDim2.fromOffset(W - bw, H - 45), function()
			local res = ask("pouch.upgrade", {})
			if res.ok then
				Audio.play("level_up")
				UIKit.notice(string.format("A bigger pouch: %d snacks a trip!", Tuning.SnackBase * (pouch + 1)), UIKit.color("good"), 3)
				UIKit.refreshPanel()
			end
		end, { name = "PouchUp", color = if short then UIKit.color("button_off") else UIKit.color("button_ok"), enabled = v.exp == nil })
	else
		UIKit.text(body, "The biggest pouch", UDim2.fromOffset(100, 10), UDim2.fromOffset(W - 100, H - 43), { color = UIKit.color("good"), x = "right", name = "PouchMax" })
	end
	-- supplies and Set sail
	local need = Tuning.Supplies * (1 + #party)
	local enough = v.food >= need
	UIKit.text(body, string.format("Supplies: %d food (you have %s)", need, Numbers.coins(v.food)), UDim2.fromOffset(RW, 10), UDim2.fromOffset(x0, H - 28), { color = if enough then UIKit.color("text_dim") else UIKit.color("bad"), name = "Supplies" })
	local busy = v.exp ~= nil
	UIKit.button(body, if busy then "Continue the expedition" else "Set sail!", UDim2.fromOffset(RW, 15), UDim2.fromOffset(x0, H - 16), function()
		if busy then
			UIKit.closePanel()
			ExpeditionUI.open()
			return
		end
		local keys = table.clone(party) -- (closing the panel clears the picks)
		local res = ask("exp.start", { isle = chosenIsle, party = table.concat(keys, ",") })
		if res.ok then
			UIKit.closePanel()
			ExpeditionUI.sail(keys, if type(res.data) == "table" then res.data.isle else nil)
		end
	end, { name = "SetSail", color = UIKit.color("button_ok"), enabled = busy or enough })
end

------------------------------------------------------------------ Index: the driftlings
local function buildIndex(body: Frame, _arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local seen, friends = 0, 0
	for _, d in Creatures.list do
		local n = v.seen[d.id] or 0
		if n >= 1 then
			seen += 1
		end
		if n >= 2 then
			friends += 1
		end
	end
	UIKit.text(body, string.format("Met %d of %d   Befriended %d", seen, #Creatures.list, friends), UDim2.fromOffset(W, 12), UDim2.fromOffset(0, 0), { color = UIKit.color("text_dim"), name = "Found" })
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - 14), UDim2.fromOffset(0, 14))
	local cols = if W >= 300 then 3 else 2
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(math.floor((W - 6 - (cols - 1) * 3) / cols), 42)
	grid.CellPadding = UDim2.fromOffset(3, 3)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list
	for i, d in Creatures.list do
		local n = v.seen[d.id] or 0
		local f = UIKit.plate(list, UDim2.fromOffset(60, 42), nil, if n >= 2 then UIKit.color("plate") else UIKit.color("plate_light"), 0, 2, { bevel = true })
		f.Name = "Entry_" .. d.id
		f.LayoutOrder = i
		PixelSprites.image(f, if n >= 1 then "icon_" .. d.id else "icon_" .. d.id .. "_sil", UDim2.fromOffset(3, 3), 4)
		UIKit.text(f, if n >= 1 then d.name else "???", UDim2.new(1, -24, 0, 10), UDim2.fromOffset(21, 1), { color = if n >= 1 then UIKit.color("text") else UIKit.color("text_dim"), z = 4 })
		local isl = Islets.list[d.islet]
		UIKit.text(f, if n >= 1 and isl then isl.plural else "", UDim2.new(1, -24, 0, 10), UDim2.fromOffset(21, 10), { color = UIKit.color("text_dim"), z = 4 })
		if n >= 2 then
			PixelSprites.image(f, "mini_charm", UDim2.new(1, -13, 0, 2), 4)
		end
		UIKit.text(f, if n >= 2 then d.blurb elseif n >= 1 then "Met: befriend one with a snack." else "Not met yet.", UDim2.new(1, -6, 0, 20), UDim2.fromOffset(3, 21), { color = UIKit.color("text_dim"), wrap = true, z = 4 })
	end
end

------------------------------------------------------------------ Looks: the founder
local draft: Types.Look? = nil
local LOOK_ROWS: { { key: string, label: string, n: number } } = {
	{ key = "skin", label = "Skin", n = #Looks.skin },
	{ key = "hair", label = "Hair", n = #Looks.hair },
	{ key = "style", label = "Style", n = #Looks.styles },
	{ key = "shirt", label = "Shirt", n = #Looks.shirt },
}

local function buildLooks(body: Frame, _arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	local d: Types.Look = draft or table.clone(v.founder)
	draft = d
	UIKit.portrait(body, d, 48, UDim2.fromOffset(4, 4))
	for i, r in LOOK_ROWS do
		local y = (i - 1) * 16
		UIKit.text(body, r.label, UDim2.fromOffset(40, 12), UDim2.fromOffset(64, y), { color = UIKit.color("text") })
		local function step(delta: number)
			local cur = (d :: any)[r.key] :: number
			;(d :: any)[r.key] = (cur - 1 + delta) % r.n + 1
			Audio.play("flip")
			UIKit.refreshPanel()
		end
		UIKit.button(body, "<", UDim2.fromOffset(14, 12), UDim2.fromOffset(106, y), function()
			step(-1)
		end, { name = "Prev_" .. r.key, color = UIKit.color("plate_light") })
		UIKit.text(body, string.format("%d/%d", (d :: any)[r.key], r.n), UDim2.fromOffset(30, 12), UDim2.fromOffset(122, y), { x = "center", color = UIKit.color("text_dim") })
		UIKit.button(body, ">", UDim2.fromOffset(14, 12), UDim2.fromOffset(154, y), function()
			step(1)
		end, { name = "Next_" .. r.key, color = UIKit.color("plate_light") })
	end
	UIKit.button(body, "Save look", UDim2.fromOffset(104, 14), UDim2.fromOffset(64, 66), function()
		local res = ask("founder.set", { skin = d.skin, hair = d.hair, style = d.style, shirt = d.shirt }, "Looking good!")
		if res.ok then
			Audio.play("reward")
		end
	end, { name = "SaveLook", color = UIKit.color("button_ok") })
end

function Menus.init()
	UIKit.registerPanel("folk", { title = "Villagers", icon = "folk", w = 320, h = 186, build = buildFolk })
	UIKit.registerPanel("pals", { title = "Driftlings", icon = "pal", w = 320, h = 186, build = buildPals })
	UIKit.registerPanel("explore", { title = "Sea chart", icon = "boat", w = 620, h = 350, build = buildExplore })
	UIKit.registerPanel("index", { title = "Index", icon = "star", w = 320, h = 186, build = buildIndex })
	UIKit.registerPanel("looks", { title = "Looks", icon = "visitor", w = 200, h = 106, build = buildLooks })
	UIKit.PanelChanged:Connect(function(name: string?)
		if name ~= "looks" then
			draft = nil
		end
		if name ~= "explore" then
			table.clear(party)
			partyFilled = false
		end
	end)
end

-- Sims and previews: the party picked in Explore.
function Menus.party(): { string }
	return table.clone(party)
end

-- Sims and previews: the chart's island picked in Explore.
function Menus.chosen(): number
	return chosenIsle
end

return Menus
