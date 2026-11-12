--!strict
-- The HUD's panels (docs/ARCHITECTURE.md 10.4; GAME_DESIGN 5-9): Villagers (who lives here, their jobs, dismissing),
-- Driftlings (the befriended ones, where they help, releasing), the Hatchery (two parents, an egg), a wild place's
-- card (what lives there, the party, the snack pouch: Explore), Index
-- (every driftling met or befriended) and Looks (the founder's look). Every action is a request; the panel rebuilds
-- from the next view. A job or help picker is the same panel with an argument ({ folk = id } / { pal = id }).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Buildings = require(ReplicatedStorage.Shared.Data.Buildings)
local Creatures = require(ReplicatedStorage.Shared.Data.Creatures)
local Islets = require(ReplicatedStorage.Shared.Data.Islets)
local Traits = require(ReplicatedStorage.Shared.Data.Traits)
local Looks = require(ReplicatedStorage.Shared.Data.Looks)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local Battle = require(ReplicatedStorage.Shared.Logic.Battle)
local Island = require(ReplicatedStorage.Shared.Logic.Island)
local Expedition = require(ReplicatedStorage.Shared.Logic.Expedition)
local SiteData = require(ReplicatedStorage.Shared.Data.Sites)
local Breed = require(ReplicatedStorage.Shared.Logic.Breed)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local ExpeditionUI = require(script.Parent.ExpeditionUI)
local Words = require(script.Parent.Words)

local Menus = {}

local hatcheries: (v: Types.ClientView) -> { Types.Piece } -- (the Hatchery's, below)

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
			local label = m.name .. Traits.TIER_STARS[m.tier] .. (if i < #muts then "," else "")
			local lw = UIKit.textWidth(label)
			if cx + lw > x + w then
				break
			end
			UIKit.text(parent, label, UDim2.fromOffset(lw + 2, 10), UDim2.fromOffset(cx, y), { color = UIKit.color(Traits.TIER_COLOR[m.tier] or "text"), z = 4, name = "Mut_" .. id })
			cx += lw + 5
		end
	end
end

-- Who lives where and their comfort (Logic/Island.homes over the view's pieces, villagers and driftlings).
local function homesOf(v: Types.ClientView): { [string]: Island.Home }
	return Island.homes({ plot = { placed = v.pieces }, folk = v.folk, pals = v.pals } :: any)
end

-- "the Villa, comfort +18%" for a resident; "" when it has no bed.
local function homeLine(v: Types.ClientView, h: Island.Home?): string
	if h == nil then
		return ""
	end
	local q = nil
	for _, x in v.pieces do
		if x.uid == h.uid then
			q = x
		end
	end
	local d = if q then Buildings.byId[q.id] else nil
	if d == nil then
		return ""
	end
	return if h.comfort > 0 then string.format("%s, comfort +%d%%", d.name, math.round(h.comfort * 100)) else d.name
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
		UIKit.text(f, if knack then "No " .. (KNACKS[knack] or "spots") .. " on the island yet. Build one first." else "Nothing to work at yet. Build a patch or a camp first.", UDim2.new(1, -10, 1, -4), UDim2.fromOffset(5, 2), { color = UIKit.color("text_dim"), z = 4, wrap = true })
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
		UIKit.text(f, "Nobody lives here yet. Build a Tent and a castaway may turn up at dawn.", UDim2.new(1, -10, 1, -4), UDim2.fromOffset(5, 2), { color = UIKit.color("text_dim"), z = 4, wrap = true })
	end
	local homes = homesOf(v)
	for i, x in v.folk do
		local f = row(list, i, 44)
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
		-- its home (the best beds go first) and the comfort it gives: more work, stronger in battle
		local h = homes["v" .. x.id]
		local c = if h then h.comfort else 0
		UIKit.text(f, statLine(Battle.villager(x, if c > 0 then { hp = c, atk = c, def = c } else nil)), UDim2.new(1, -150, 0, 10), UDim2.fromOffset(36, 21), { color = UIKit.color("text_dim"), z = 4 })
		local hl = homeLine(v, h)
		UIKit.text(f, if hl ~= "" then "Home: " .. hl else "No bed", UDim2.new(1, -150, 0, 10), UDim2.fromOffset(36, 31), { color = if c > 0 then UIKit.color("good") else UIKit.color("text_dim"), z = 4, name = "Home" })
		local jb = UIKit.button(f, "Job", UDim2.fromOffset(46, 13), UDim2.new(1, -104, 0, 10), function()
			UIKit.openPanel("folk", { folk = x.id })
		end, { name = "Job_" .. x.id, color = UIKit.color("button_ok"), enabled = not gone })
		jb.ZIndex = 4
		if not gone then
			confirmButton(f, "Dismiss", UDim2.fromOffset(52, 13), UDim2.new(1, -55, 0, 10), function()
				local res = ask("folk.dismiss", { id = x.id }, x.name .. " sailed off.")
				if res.ok then
					Audio.play("close")
				end
			end, "Dismiss_" .. x.id)
		end
	end
end

------------------------------------------------------------------ the Hatchery
-- (GAME_DESIGN 6.1; Logic/Breed) Each Hatchery standing: its egg (the rarity's egg, the turns left, its parents), or
-- two parents to pick (a picker of the driftlings at home), what they would likely hatch (its kind if met, else its
-- shape, and its rarity), the feast and the turns it takes, and Breed.
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

-- The parent picker: the driftlings at home (not the other parent), each with its passive and mutations.
local function buildParentPicker(body: Frame, v: Types.ClientView, uid: number, slot: string)
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local top = hint(body, "Pick a parent. Its kind and mutations can pass to the egg.", W)
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - top), UDim2.fromOffset(0, top))
	UIKit.vlist(list, 2)
	local pick: Pick = breedPick[uid] or {}
	local other = if slot == "a" then pick.b else pick.a
	local n = 0
	for _, x in v.pals do
		local d = Creatures.byId[x.sp]
		if d == nil or x.id == other or away(v, "p" .. x.id) then
			continue
		end
		n += 1
		local f = row(list, n, 34)
		f.Name = "Parent_" .. x.id
		PixelSprites.image(f, "icon_" .. x.sp, UDim2.fromOffset(4, 4), 4)
		local rar = Traits.RARITY[d.rarity] or Traits.RARITY[1]
		UIKit.text(f, string.format("%s  Lv %d", d.name, x.lvl), UDim2.fromOffset(W - 90, 10), UDim2.fromOffset(24, 1), { color = UIKit.color(rar.color), z = 4 })
		UIKit.text(f, d.passive.name, UDim2.fromOffset(W - 90, 10), UDim2.fromOffset(24, 11), { color = UIKit.color("accent"), z = 4 })
		mutLine(f, x.muts or {}, 24, 21, W - 90)
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
	end
	if n == 0 then
		local f = row(list, 1, 24)
		UIKit.text(f, "No driftling at home to pick.", UDim2.new(1, -10, 1, -4), UDim2.fromOffset(5, 2), { color = UIKit.color("text_dim"), z = 4 })
	end
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
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local top = hint(body, "Two driftlings and a feast of food make an egg. It hatches in a few turns into a free nest.", W)
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - top), UDim2.fromOffset(0, top))
	UIKit.vlist(list, 2)
	local hs = hatcheries(v)
	if #hs == 0 then
		local f = row(list, 1, 24)
		UIKit.text(f, "Build a Hatchery (the Nests tab, Island Lv3) to breed driftlings.", UDim2.new(1, -10, 1, -4), UDim2.fromOffset(5, 2), { color = UIKit.color("text_dim"), z = 4, wrap = true })
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
		local f = row(list, i, 48)
		f.Name = "Hatch_" .. q.uid
		if egg then
			-- an egg: its rarity's egg, the turns left (a bar), its parents
			local d = Creatures.byId[egg.sp]
			local r = if d then d.rarity else 1
			local rar = Traits.RARITY[r] or Traits.RARITY[1]
			PixelSprites.image(f, "egg_" .. r, UDim2.fromOffset(5, 6), 4)
			UIKit.text(f, string.format("%s %s egg", if r == 4 then "An" else "A", rar.name), UDim2.fromOffset(W - 40, 10), UDim2.fromOffset(26, 2), { color = UIKit.color(rar.color), z = 4, name = "EggName" })
			local _, total = Breed.cost(egg.sp)
			local line = if egg.left > 0 then string.format("Hatches in %d turn%s", egg.left, if egg.left == 1 then "" else "s") else "Ready to hatch. It needs a free nest."
			UIKit.text(f, line, UDim2.fromOffset(W - 40, 10), UDim2.fromOffset(26, 12), { color = if egg.left > 0 then UIKit.color("text") else UIKit.color("orange"), z = 4, name = "EggLeft" })
			local bw = math.min(140, W - 40)
			local back = UIKit.rect(f, UDim2.fromOffset(bw, 4), UDim2.fromOffset(26, 24), UIKit.color("ink"), 4)
			back.Name = "EggBar"
			local done = math.clamp(1 - egg.left / math.max(1, total), 0, 1)
			UIKit.rect(back, UDim2.fromOffset(math.floor((bw - 2) * done), 2), UDim2.fromOffset(1, 1), UIKit.color("pink"), 5)
			local pa, pb = palById(v, egg.a), palById(v, egg.b)
			local function nm(x: Types.Pal?): string
				local cd = if x then Creatures.byId[x.sp] else nil
				return if cd then cd.name else "a friend"
			end
			UIKit.text(f, "From " .. nm(pa) .. " and " .. nm(pb), UDim2.fromOffset(W - 40, 10), UDim2.fromOffset(26, 32), { color = UIKit.color("text_dim"), z = 4 })
		else
			-- two parents to pick, what they would hatch, Breed
			local pick: Pick = breedPick[q.uid] or {}
			local pa, pb = palById(v, pick.a), palById(v, pick.b)
			if pa and away(v, "p" .. pa.id) then
				pa = nil
			end
			if pb and away(v, "p" .. pb.id) then
				pb = nil
			end
			local function slot(x: Types.Pal?, key: string, sx: number)
				local b = UIKit.button(f, "", UDim2.fromOffset(84, 18), UDim2.fromOffset(sx, 3), function()
					UIKit.openPanel("hatch", { hatch = q.uid, slot = key })
				end, { name = "Slot_" .. key .. "_" .. q.uid, color = UIKit.color("plate") })
				b.ZIndex = 4
				if x then
					PixelSprites.image(b, "icon_" .. x.sp, UDim2.fromOffset(2, 3), 5)
					local cd = Creatures.byId[x.sp]
					UIKit.text(b, if cd then cd.name else x.sp, UDim2.fromOffset(66, 10), UDim2.fromOffset(16, 4), { color = UIKit.color("text"), z = 6 })
				else
					UIKit.text(b, "Pick a parent", UDim2.fromScale(1, 1), nil, { x = "center", color = UIKit.color("text_dim"), z = 6 })
				end
			end
			slot(pa, "a", 4)
			UIKit.text(f, "+", UDim2.fromOffset(8, 10), UDim2.fromOffset(91, 7), { color = UIKit.color("text"), z = 4 })
			slot(pb, "b", 100)
			if pa and pb then
				local sp = Breed.child(pa.sp, pb.sp)
				local d = Creatures.byId[sp]
				local food, turns = Breed.cost(sp)
				local met = (v.seen[sp] or 0) >= 1
				local rar = Traits.RARITY[if d then d.rarity else 1] or Traits.RARITY[1]
				PixelSprites.image(f, if met then "icon_" .. sp else "icon_" .. sp .. "_sil", UDim2.fromOffset(190, 4), 4)
				UIKit.text(f, if met and d then d.name else "???", UDim2.fromOffset(W - 214, 10), UDim2.fromOffset(208, 2), { color = UIKit.color(rar.color), z = 4, name = "Child" })
				UIKit.text(f, rar.name, UDim2.fromOffset(W - 214, 10), UDim2.fromOffset(208, 11), { color = UIKit.color(rar.color), z = 4 })
				UIKit.text(f, string.format("A feast of %d food, %d turns. Shared mutations always pass on.", food, turns), UDim2.fromOffset(W - 8, 10), UDim2.fromOffset(4, 24), { color = UIKit.color("text_dim"), z = 4, name = "Cost" })
				UIKit.button(f, "Breed", UDim2.fromOffset(60, 13), UDim2.new(1, -64, 0, 33), function()
					local res = ask("breed.start", { uid = q.uid, a = pa.id, b = pb.id }, "There's an egg warming in the Hatchery.")
					if res.ok then
						breedPick[q.uid] = nil
						Audio.play("egg")
					end
				end, { name = "Breed_" .. q.uid, color = UIKit.color("button_ok"), enabled = v.food >= food }).ZIndex = 4
			else
				UIKit.text(f, "Pick two driftlings at home.", UDim2.fromOffset(W - 8, 10), UDim2.fromOffset(4, 24), { color = UIKit.color("text_dim"), z = 4 })
			end
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
	-- a Hatchery standing: its button beside the hint (GAME_DESIGN 6.1)
	local hasHatch = #hatcheries(v) > 0
	local top = hint(body, string.format("%d driftlings, nests for %d. Befriend more on expeditions with a snack.", #v.pals, v.nests), if hasHatch then W - 64 else W)
	if hasHatch then
		UIKit.button(body, "Hatchery", UDim2.fromOffset(60, 13), UDim2.fromOffset(W - 60, 0), function()
			UIKit.openPanel("hatch")
		end, { name = "OpenHatch", color = UIKit.color("pink") })
		top = math.max(top, 16)
	end
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - top), UDim2.fromOffset(0, top))
	UIKit.vlist(list, 2)
	if #v.pals == 0 then
		local f = row(list, 1, 24)
		UIKit.text(f, "No driftlings yet. Build a nest, go exploring and throw snacks at hurt wild ones.", UDim2.new(1, -10, 1, -4), UDim2.fromOffset(5, 2), { color = UIKit.color("text_dim"), z = 4, wrap = true })
	end
	local homes = homesOf(v)
	for i, x in v.pals do
		local d = Creatures.byId[x.sp]
		if d == nil then
			continue
		end
		local f = row(list, i, 54)
		f.Name = "Pal_" .. x.id
		PixelSprites.image(f, "icon_" .. x.sp, UDim2.fromOffset(4, 4), 4)
		local gone = away(v, "p" .. x.id)
		local rar = Traits.RARITY[d.rarity] or Traits.RARITY[1]
		local tw = W - 130
		-- its name in its rarity's colour, its level and skill; its passive; its mutations; where it is; its stats
		UIKit.text(f, d.name, UDim2.fromOffset(90, 10), UDim2.fromOffset(24, 1), { color = UIKit.color(rar.color), z = 4, name = "Name" })
		UIKit.text(f, string.format("Lv %d  %s", x.lvl, Creatures.skills[d.skill] or d.skill), UDim2.fromOffset(math.max(10, tw - UIKit.textWidth(d.name) - 6), 10), UDim2.fromOffset(24 + UIKit.textWidth(d.name) + 6, 1), { color = UIKit.color("text"), z = 4 })
		UIKit.text(f, d.passive.name .. ": " .. Traits.describe(d.passive.fx), UDim2.fromOffset(tw, 10), UDim2.fromOffset(24, 11), { color = UIKit.color("accent"), z = 4, name = "Passive" })
		mutLine(f, x.muts or {}, 24, 21, tw)
		local where = if gone then "Away on an expedition" elseif x.work ~= 0 then "Helping at the " .. (buildingName(v, x.work) or "?") else "Resting (helps at " .. (KNACKS[d.knack] or d.knack) .. ")"
		UIKit.text(f, where, UDim2.fromOffset(tw, 10), UDim2.fromOffset(24, 31), { color = if gone then UIKit.color("orange") elseif x.work ~= 0 then UIKit.color("good") else UIKit.color("text_dim"), z = 4, name = "Where" })
		local h = homes["p" .. x.id]
		local c = if h then h.comfort else 0
		local nest = homeLine(v, h)
		UIKit.text(f, statLine(Battle.pal(x, if c > 0 then { hp = c, atk = c, def = c } else nil)) .. (if nest ~= "" then "  " .. nest else ""), UDim2.fromOffset(W - 30, 10), UDim2.fromOffset(24, 41), { color = UIKit.color("text_dim"), z = 4, name = "Stats" })
		local hb = UIKit.button(f, "Help", UDim2.fromOffset(46, 13), UDim2.new(1, -104, 0, 20), function()
			UIKit.openPanel("pals", { pal = x.id })
		end, { name = "Help_" .. x.id, color = UIKit.color("button_ok"), enabled = not gone })
		hb.ZIndex = 4
		if not gone then
			confirmButton(f, "Release", UDim2.fromOffset(52, 13), UDim2.new(1, -55, 0, 20), function()
				local res = ask("pal.release", { id = x.id }, d.name .. " went home to the wild.")
				if res.ok then
					Audio.play("close")
				end
			end, "Release_" .. x.id)
		end
	end
end

------------------------------------------------------------------ a wild place: what lives there, the party
-- A wild place's card (GAME_DESIGN 7: "You can tap on them to enter an expedition just like an island before"): a tap
-- on one on the island opens it (`arg`: its piece uid; none: the lowest wild one). Its name, kind and level, wild or
-- cleared, what clearing it pays, who lives there and its guardian; the snack pouch; the party (the strongest go in
-- by themselves); Explore.
local chosenSite = 0
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

-- The place a card opens on when none was tapped (a quest's Go): the lowest wild one, else the lowest cleared one.
local function defaultSite(v: Types.ClientView): number
	local best, bestLvl, bestWild = 0, math.huge, false
	for _, q in v.pieces do
		local sd, wild = SiteData.of(q.id)
		if sd and ((wild and not bestWild) or (wild == bestWild and q.lvl < bestLvl)) then
			best, bestLvl, bestWild = q.uid, q.lvl, wild
		end
	end
	return best
end
Menus.defaultSite = defaultSite

local function buildSite(body: Frame, arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	if type(arg) == "number" then
		chosenSite = arg
	end
	local q: Types.Piece? = nil
	for _, x in v.pieces do
		if x.uid == chosenSite then
			q = x
		end
	end
	if q == nil or SiteData.of(q.id) == nil then
		chosenSite = defaultSite(v)
		for _, x in v.pieces do
			if x.uid == chosenSite then
				q = x
			end
		end
	end
	if q == nil then
		UIKit.text(body, "No wild places on the island right now.", UDim2.fromOffset(W, 10), UDim2.fromOffset(0, 0), { color = UIKit.color("text_dim"), name = "NoSites" })
		return
	end
	local piece = q :: Types.Piece
	local sd, wild = SiteData.of(piece.id)
	local site = sd :: SiteData.SiteDef
	for i = #party, 1, -1 do
		if not memberOk(v, party[i]) then
			table.remove(party, i)
		end
	end
	-- the party's slots: the strongest go in by themselves when the card opens (GAME_DESIGN 7: "party slots should
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
	local isle = Expedition.isleOf(v :: any, piece)
	local kind = Islets.list[isle.kind]
	local cap = math.max(1, v.cap.lvl)
	-- the place on the left
	local LW = math.floor(W * 0.46)
	UIKit.text(body, isle.name, UDim2.fromOffset(LW, 12), UDim2.fromOffset(0, 0), { color = UIKit.color("accent"), face = "big", name = "SiteName" })
	local lvCol = if piece.lvl <= cap then UIKit.color("good") elseif piece.lvl <= cap + 3 then UIKit.color("accent") else UIKit.color("bad")
	-- (and how far in it goes: the same every time, the guardian at the last stop)
	UIKit.text(body, string.format("%s, level %d, %d stops", site.name, piece.lvl, Tuning.BossEvery), UDim2.fromOffset(LW, 10), UDim2.fromOffset(0, 15), { color = lvCol, name = "SiteKind" })
	UIKit.text(body, site.blurb, UDim2.fromOffset(LW, 10), UDim2.fromOffset(0, 26), { color = UIKit.color("text_dim"), name = "SiteBlurb" })
	UIKit.text(body, if wild then "Wild. Nothing can be built close to it." else "Cleared. You can move it or clear it away in Build mode.", UDim2.fromOffset(LW, 10), UDim2.fromOffset(0, 38), { color = if wild then UIKit.color("orange") else UIKit.color("good"), name = "SiteState" })
	-- what beating its guardian pays
	local reward = Expedition.rewardOf(isle, wild)
	local rt = Numbers.coins(reward)
	PixelSprites.image(body, "mini_shell", UDim2.fromOffset(0, 50), 4)
	UIKit.text(body, string.format("%s %s", if wild then "First clear:" else "Clear it again:", rt), UDim2.fromOffset(LW - 12, 10), UDim2.fromOffset(12, 51), { color = UIKit.color("accent"), name = "Reward" })
	-- who lives there, the commonest first (seen ones in colour), and its guardian
	UIKit.text(body, "Lives here", UDim2.fromOffset(LW, 10), UDim2.fromOffset(0, 64), { color = UIKit.color("text_dim"), name = "LivesHere" })
	local ix, iy = 0, 75
	local perRow = math.max(1, math.floor(LW / 18))
	for i, sp in isle.wild do
		if i > perRow * 2 then
			break
		end
		local seen = (v.seen[sp] or 0) > 0
		PixelSprites.image(body, if seen then "icon_" .. sp else "icon_" .. sp .. "_sil", UDim2.fromOffset(ix, iy), 4)
		ix += 18
		if i % perRow == 0 then
			ix, iy = 0, iy + 18
		end
	end
	local gy = iy + (if ix > 0 then 19 else 1)
	local bossSeen = (v.seen[isle.boss] or 0) > 0
	PixelSprites.image(body, if bossSeen then "icon_" .. isle.boss else "icon_" .. isle.boss .. "_sil", UDim2.fromOffset(0, gy), 4)
	UIKit.text(body, "Guardian: " .. isle.bossName, UDim2.fromOffset(LW - 20, 10), UDim2.fromOffset(19, gy + 4), { color = UIKit.color("bad"), name = "Guardian" })
	local _ = kind
	-- the snack pouch (GAME_DESIGN 7: snacks a trip, 5 up to 30): a bigger one for shells and wood
	local pouch = v.pouch or 1
	UIKit.text(body, string.format("Snacks: %d a trip", Tuning.SnackBase * pouch), UDim2.fromOffset(LW, 10), UDim2.fromOffset(0, H - 30), { color = UIKit.color("pink"), name = "Snacks" })
	local pc = Tuning.PouchCost[pouch + 1]
	if pc then
		local bw = UIKit.buttonWidth("Bigger pouch", 5)
		local short = v.shells < pc.shells or v.wood < pc.wood
		local st, wt = Numbers.coins(pc.shells), Numbers.coins(pc.wood)
		PixelSprites.image(body, "mini_shell", UDim2.fromOffset(0, H - 15), 4)
		UIKit.text(body, st, UDim2.fromOffset(UIKit.textWidth(st) + 2, 10), UDim2.fromOffset(11, H - 14), { color = if v.shells < pc.shells then UIKit.color("bad") else UIKit.color("text"), name = "PouchShells" })
		local wx = 13 + UIKit.textWidth(st)
		PixelSprites.image(body, "mini_wood", UDim2.fromOffset(wx, H - 15), 4)
		UIKit.text(body, wt, UDim2.fromOffset(UIKit.textWidth(wt) + 2, 10), UDim2.fromOffset(wx + 11, H - 14), { color = if v.wood < pc.wood then UIKit.color("bad") else UIKit.color("text"), name = "PouchWood" })
		UIKit.button(body, "Bigger pouch", UDim2.fromOffset(bw, 13), UDim2.fromOffset(LW - bw, H - 16), function()
			local res = ask("pouch.upgrade", {})
			if res.ok then
				Audio.play("level_up")
				UIKit.notice(string.format("Bigger pouch. %d snacks a trip now.", Tuning.SnackBase * (pouch + 1)), UIKit.color("good"), 3)
				UIKit.refreshPanel()
			end
		end, { name = "PouchUp", color = if short then UIKit.color("button_off") else UIKit.color("button_ok"), enabled = v.exp == nil })
	else
		UIKit.text(body, "The biggest pouch", UDim2.fromOffset(LW, 10), UDim2.fromOffset(0, H - 14), { color = UIKit.color("good"), name = "PouchMax" })
	end
	-- the party on the right: the captain, then up to PartyMax picks
	local x0 = LW + 8
	local RW = W - x0
	UIKit.text(body, string.format("Party %d/%d (you always go)", 1 + #party, 1 + Tuning.PartyMax), UDim2.fromOffset(RW, 10), UDim2.fromOffset(x0, 0), { color = UIKit.color("text_dim"), name = "PartyHint" })
	local listY = 12
	local pl = UIKit.scroll(body, UDim2.fromOffset(RW, H - 32 - listY), UDim2.fromOffset(x0, listY))
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
				UIKit.notice(string.format("A party is you and %d more.", Tuning.PartyMax), UIKit.color("bad"))
				return
			end
			Audio.play("flip")
			UIKit.refreshPanel()
		end)
		b.Parent = pl
	end
	local captain = Battle.founder({ cap = v.cap, founder = v.founder } :: any)
	member(0, "f", "You (leader)", v.cap.lvl, captain, nil, v.founder)
	for i, cand in rankMembers(v) do
		member(i, cand.key, cand.name, cand.lvl, cand.f, cand.icon, cand.look)
	end
	-- supplies and Explore (an expedition under way elsewhere: back to it)
	local need = Tuning.Supplies * (1 + #party)
	local enough = v.food >= need
	UIKit.text(body, string.format("Supplies: %d food (you have %s)", need, Numbers.coins(v.food)), UDim2.fromOffset(RW, 10), UDim2.fromOffset(x0, H - 30), { color = if enough then UIKit.color("text_dim") else UIKit.color("bad"), name = "Supplies" })
	local busy = v.exp ~= nil
	UIKit.button(body, if busy then "Back to the expedition" else "Explore", UDim2.fromOffset(RW, 15), UDim2.fromOffset(x0, H - 16), function()
		if busy then
			UIKit.closePanel()
			ExpeditionUI.open()
			return
		end
		local keys = table.clone(party) -- (closing the panel clears the picks)
		local res = ask("exp.start", { site = piece.uid, party = table.concat(keys, ",") })
		if res.ok then
			UIKit.closePanel()
			ExpeditionUI.enter(piece.uid, keys, if type(res.data) == "table" then res.data.isle else nil)
		end
	end, { name = "Explore", color = UIKit.color("button_ok"), enabled = busy or enough })
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
	grid.CellSize = UDim2.fromOffset(math.floor((W - 6 - (cols - 1) * 3) / cols), 52)
	grid.CellPadding = UDim2.fromOffset(3, 3)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list
	for i, d in Creatures.list do
		local n = v.seen[d.id] or 0
		local f = UIKit.plate(list, UDim2.fromOffset(60, 52), nil, if n >= 2 then UIKit.color("plate") else UIKit.color("plate_light"), 0, 2, { bevel = true })
		f.Name = "Entry_" .. d.id
		f.LayoutOrder = i
		local rar = Traits.RARITY[d.rarity] or Traits.RARITY[1]
		PixelSprites.image(f, if n >= 1 then "icon_" .. d.id else "icon_" .. d.id .. "_sil", UDim2.fromOffset(3, 3), 4)
		UIKit.text(f, if n >= 1 then d.name else "???", UDim2.new(1, -24, 0, 10), UDim2.fromOffset(21, 1), { color = if n >= 1 then UIKit.color(rar.color) else UIKit.color("text_dim"), z = 4, name = "Name" })
		-- its rarity (always: a rare one is worth looking for) and where it lives once met (the kind of wild place)
		local isl = SiteData.byIslet[d.islet]
		UIKit.text(f, if n >= 1 and isl then rar.name .. ", " .. string.lower(isl.plural) else rar.name, UDim2.new(1, -24, 0, 10), UDim2.fromOffset(21, 10), { color = UIKit.color(rar.color), z = 4, name = "Rarity" })
		if n >= 2 then
			PixelSprites.image(f, "mini_charm", UDim2.new(1, -13, 0, 2), 4)
			-- befriended: its passive
			UIKit.text(f, d.passive.name, UDim2.new(1, -6, 0, 10), UDim2.fromOffset(3, 21), { color = UIKit.color("accent"), z = 4, name = "Passive" })
			UIKit.text(f, Traits.describe(d.passive.fx), UDim2.new(1, -6, 0, 20), UDim2.fromOffset(3, 31), { color = UIKit.color("text_dim"), wrap = true, z = 4, name = "PassiveFx" })
		else
			UIKit.text(f, if n >= 1 then "Seen but not caught. Befriend one to learn its passive." else "Not met yet.", UDim2.new(1, -6, 0, 30), UDim2.fromOffset(3, 21), { color = UIKit.color("text_dim"), wrap = true, z = 4 })
		end
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
	UIKit.registerPanel("hatch", { title = "Hatchery", icon = "nest", w = 320, h = 186, build = buildHatch })
	UIKit.registerPanel("site", { title = "Wild place", icon = "boss", w = 460, h = 250, build = buildSite })
	UIKit.registerPanel("index", { title = "Index", icon = "star", w = 320, h = 186, build = buildIndex })
	UIKit.registerPanel("looks", { title = "Looks", icon = "visitor", w = 200, h = 106, build = buildLooks })
	UIKit.PanelChanged:Connect(function(name: string?)
		if name ~= "looks" then
			draft = nil
		end
		if name ~= "site" then
			table.clear(party)
			partyFilled = false
		end
	end)
end

-- Sims and previews: the party picked on a wild place's card.
function Menus.party(): { string }
	return table.clone(party)
end

-- Sims and previews: the wild place whose card is open (its piece uid).
function Menus.chosen(): number
	return chosenSite
end

return Menus
