--!strict
-- The HUD's panels (docs/ARCHITECTURE.md 10.4; GAME_DESIGN 5-9): Driftlings (every one: where each lives and works,
-- moving and selling), the Tide (the best few floating by with their prices, the odds; every hut full, the swap
-- picker), the Hatchery (two parents, an egg), Index (every driftling seen) and Looks (the founder's look). Every
-- action is a request; the panel rebuilds from the next view. The work picker is the same panel with an argument
-- ({ pal = id }), the hut picker too ({ move = id }), the swap picker the tide's ({ take = id }).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Buildings = require(ReplicatedStorage.Shared.Data.Buildings)
local Creatures = require(ReplicatedStorage.Shared.Data.Creatures)
local Islets = require(ReplicatedStorage.Shared.Data.Islets)
local Traits = require(ReplicatedStorage.Shared.Data.Traits)
local Looks = require(ReplicatedStorage.Shared.Data.Looks)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local Island = require(ReplicatedStorage.Shared.Logic.Island)
local Tide = require(ReplicatedStorage.Shared.Logic.Tide)
local Breed = require(ReplicatedStorage.Shared.Logic.Breed)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local TideView = require(script.Parent.Parent.Controllers.TideView)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local Words = require(script.Parent.Words)
local RunService = game:GetService("RunService")

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

local function row(list: Instance, order: number, h: number): Frame
	local f = UIKit.plate(list, UDim2.new(1, -6, 0, h), nil, UIKit.color("plate_light"), 0, 2, { bevel = true })
	f.Name = "Row"
	f.LayoutOrder = order
	return f
end

-- The view as a profile for the shared rules that read the island (Logic/Island, Logic/Tide).
local function asProfile(v: Types.ClientView): any
	return { plot = { placed = v.pieces }, pals = v.pals, tier = v.tier, shells = v.shells, wood = v.wood }
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

-- How fast a driftling works ("Works x2.8": its rarity's speed and its work share at its knack, Logic/Tide.worth).
local function workWord(x: Types.Pal): string
	return string.format("Works x%.1f", Tide.worth(x))
end

------------------------------------------------------------------ the work picker
-- The buildings of a driftling's knack it can work at, the one there now, and Rest.
local function buildPicker(body: Frame, v: Types.ClientView, palId: number)
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local knack: string? = nil
	local name = "?"
	local current = 0
	for _, x in v.pals do
		if x.id == palId then
			local d = Creatures.byId[x.sp]
			knack = if d then d.knack else nil
			name = if d then d.name else x.sp
			current = x.work
		end
	end
	local top = hint(body, string.format("Where should %s work? (%s)", name, KNACKS[knack or ""] or ""), W - 50)
	UIKit.button(body, "Back", UDim2.fromOffset(44, 12), UDim2.fromOffset(W - 44, 0), function()
		UIKit.openPanel("pals")
	end, { name = "Back", color = UIKit.color("plate_light") })
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - top), UDim2.fromOffset(0, top))
	UIKit.vlist(list, 2)
	local order = 0
	local function choose(uid: number)
		local res = ask("pal.work", { id = palId, uid = uid })
		if res.ok then
			Audio.play("ding")
			UIKit.openPanel("pals")
		end
	end
	for _, q in v.pieces do
		local d = Buildings.byId[q.id]
		if d and Island.works(q.id) and d.knack == knack then
			order += 1
			local f = row(list, order, 22)
			f.Name = "Spot_" .. q.uid
			PixelSprites.image(f, "mini_" .. (if d.kind == "shop" then "shell" else d.kind), UDim2.fromOffset(4, 5), 4)
			UIKit.text(f, d.name .. (if q.lvl > 1 then " Lv" .. q.lvl else ""), UDim2.new(1, -90, 0, 10), UDim2.fromOffset(18, 1), { color = UIKit.color("text"), z = 4 })
			-- (Tuning.HelpMax a building; one more sends the first there back to rest)
			local n = 0
			for _, x in v.pals do
				if x.work == q.uid and x.id ~= palId then
					n += 1
				end
			end
			local full = n >= Tuning.HelpMax
			local status = if q.uid == current then "Here now" elseif full then "Full: the first there would rest" elseif n > 0 then string.format("%d of %d working", n, Tuning.HelpMax) else "Nobody yet"
			UIKit.text(f, status, UDim2.new(1, -90, 0, 10), UDim2.fromOffset(18, 11), { color = if status == "Nobody yet" then UIKit.color("good") else UIKit.color("text_dim"), z = 4 })
			local b = UIKit.button(f, if q.uid == current then "Here" elseif full then "Swap" else "Go", UDim2.fromOffset(60, 14), UDim2.new(1, -64, 0, 4), function()
				choose(q.uid)
			end, { name = "Go_" .. q.uid, color = UIKit.color("button_ok"), enabled = q.uid ~= current })
			b.ZIndex = 4
		end
	end
	if order == 0 then
		local f = row(list, 1, 22)
		UIKit.text(f, "No " .. (KNACKS[knack or ""] or "spots") .. " on the island yet. Build one first.", UDim2.new(1, -10, 1, -4), UDim2.fromOffset(5, 2), { color = UIKit.color("text_dim"), z = 4, wrap = true })
	end
	local f = row(list, order + 1, 22)
	f.Name = "Rest"
	UIKit.text(f, "Rest in its hut", UDim2.new(1, -90, 0, 10), UDim2.fromOffset(6, 6), { color = UIKit.color("text"), z = 4 })
	UIKit.button(f, "Rest", UDim2.fromOffset(60, 14), UDim2.new(1, -64, 0, 4), function()
		choose(0)
	end, { name = "Go_0", enabled = current ~= 0 }).ZIndex = 4
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

-- The parent picker: the island's driftlings (not the other parent), each with its passive and mutations.
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
		if d == nil or x.id == other then
			continue
		end
		n += 1
		local f = row(list, n, 38)
		f.Name = "Parent_" .. x.id
		PixelSprites.image(f, "icon_" .. x.sp, UDim2.fromOffset(4, 3), 4)
		local rar = Traits.RARITY[d.rarity] or Traits.RARITY[1]
		UIKit.text(f, string.format("%s  %s", d.name, rar.name), UDim2.fromOffset(W - 106, 10), UDim2.fromOffset(PX, 4), { color = UIKit.color(rar.color), z = 4 })
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
	end
	if n == 0 then
		local f = row(list, 1, 24)
		UIKit.text(f, "No driftling to pick yet.", UDim2.new(1, -10, 1, -4), UDim2.fromOffset(5, 2), { color = UIKit.color("text_dim"), z = 4 })
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
	local top = hint(body, "Two driftlings and a feast make an egg. It hatches a few turns later and moves into a hut.", W)
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - top), UDim2.fromOffset(0, top))
	UIKit.vlist(list, 2)
	local hs = hatcheries(v)
	if #hs == 0 then
		local f = row(list, 1, 24)
		UIKit.text(f, "Build a Hatchery (the Huts tab, Island Lv3) to breed driftlings.", UDim2.new(1, -10, 1, -4), UDim2.fromOffset(5, 2), { color = UIKit.color("text_dim"), z = 4, wrap = true })
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
			UIKit.text(f, string.format("%s %s egg", if r == 4 then "An" else "A", rar.name), UDim2.fromOffset(W - 40, 10), UDim2.fromOffset(26, 2), { color = UIKit.color(rar.color), z = 4, name = "EggName" })
			local _, total = Breed.cost(egg.sp)
			local line = if egg.left > 0 then string.format("Hatches in %d turn%s", egg.left, if egg.left == 1 then "" else "s") else "Hatching now."
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
			local function slot(x: Types.Pal?, key: string, sx: number)
				local b = UIKit.button(f, "", UDim2.fromOffset(96, 36), UDim2.fromOffset(sx, 3), function()
					UIKit.openPanel("hatch", { hatch = q.uid, slot = key })
				end, { name = "Slot_" .. key .. "_" .. q.uid, color = UIKit.color("plate") })
				b.ZIndex = 4
				if x then
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
			if pa and pb then
				local sp = Breed.child(pa.sp, pb.sp)
				local d = Creatures.byId[sp]
				local feast, turns = Breed.cost(sp)
				local met = (v.seen[sp] or 0) >= 1
				local rar = Traits.RARITY[if d then d.rarity else 1] or Traits.RARITY[1]
				PixelSprites.image(f, if met then "icon_" .. sp else "icon_" .. sp .. "_sil", UDim2.fromOffset(214, 5), 4)
				UIKit.text(f, if met and d then d.name else "???", UDim2.fromOffset(W - 256, 10), UDim2.fromOffset(250, 10), { color = UIKit.color(rar.color), z = 4, name = "Child" })
				UIKit.text(f, rar.name, UDim2.fromOffset(W - 256, 10), UDim2.fromOffset(250, 19), { color = UIKit.color(rar.color), z = 4 })
				UIKit.text(f, string.format("A feast for %s shells, %d turns. Shared mutations always pass on.", Numbers.coins(feast), turns), UDim2.fromOffset(W - 8, 10), UDim2.fromOffset(4, 42), { color = UIKit.color("text_dim"), z = 4, name = "Cost" })
				UIKit.button(f, "Breed", UDim2.fromOffset(60, 13), UDim2.new(1, -64, 0, 51), function()
					local res = ask("breed.start", { uid = q.uid, a = pa.id, b = pb.id }, "There's an egg warming in the Hatchery.")
					if res.ok then
						breedPick[q.uid] = nil
						Audio.play("egg")
					end
				end, { name = "Breed_" .. q.uid, color = UIKit.color("button_ok"), enabled = v.shells >= feast }).ZIndex = 4
			else
				UIKit.text(f, "Pick two driftlings.", UDim2.fromOffset(W - 8, 10), UDim2.fromOffset(4, 42), { color = UIKit.color("text_dim"), z = 4 })
			end
		end
	end
end

------------------------------------------------------------------ the hut picker
-- Where a driftling lives (GAME_DESIGN 6: "the player can also select which creatures are sent to which hut"): every
-- hut, the comfiest first, with its room and comfort. One with room: Move here. A full one: each of its driftlings, to
-- swap with (it goes to where this one was).
local function buildHutPicker(body: Frame, v: Types.ClientView, id: number, back: string)
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local me = palById(v, id)
	local md = if me then Creatures.byId[me.sp] else nil
	if me == nil or md == nil then
		UIKit.openPanel(back)
		return
	end
	local top = hint(body, string.format("Where should %s live? It works from its hut.", md.name), W - 50)
	UIKit.button(body, "Back", UDim2.fromOffset(44, 12), UDim2.fromOffset(W - 44, 0), function()
		UIKit.openPanel(back)
	end, { name = "Back", color = UIKit.color("plate_light") })
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - top), UDim2.fromOffset(0, top))
	UIKit.vlist(list, 2)
	local order = 0
	local function move(uid: number, swap: number)
		local res = ask("pal.house", { id = id, uid = uid, swap = swap })
		if res.ok then
			Audio.play("pop")
			UIKit.openPanel(back)
		end
	end
	local function place(uid: number, title: string, n: number, room: number, comfort: number)
		order += 1
		local f = row(list, order, 22)
		f.Name = "Hut_" .. uid
		PixelSprites.image(f, "mini_nest", UDim2.fromOffset(4, 5), 4)
		UIKit.text(f, title, UDim2.new(1, -110, 0, 10), UDim2.fromOffset(18, 1), { color = UIKit.color("text"), z = 4 })
		local sub = string.format("%d/%d", n, room) .. (if comfort > 0 then string.format(", comfort +%d%%", math.round(comfort * 100)) else "")
		UIKit.text(f, sub, UDim2.new(1, -110, 0, 10), UDim2.fromOffset(18, 11), { color = if n >= room then UIKit.color("orange") else UIKit.color("text_dim"), z = 4 })
		local here = me.home == uid
		UIKit.button(f, if here then "Here now" elseif n >= room then "Full" else "Move here", UDim2.fromOffset(70, 14), UDim2.new(1, -74, 0, 4), function()
			move(uid, 0)
		end, { name = "Move_" .. uid, color = UIKit.color("button_ok"), enabled = not here and n < room }).ZIndex = 4
		-- a full one: swap with any of its driftlings
		if not here and n >= room then
			for _, x in v.pals do
				local d = Creatures.byId[x.sp]
				if x.home == uid and d then
					order += 1
					local r = row(list, order, 36)
					r.Name = "Swap_" .. x.id
					PixelSprites.image(r, "icon_" .. x.sp, UDim2.fromOffset(14, 2), 4)
					local rar = Traits.RARITY[d.rarity] or Traits.RARITY[1]
					UIKit.text(r, string.format("%s  %s", d.name, workWord(x)), UDim2.new(1, -126, 0, 10), UDim2.fromOffset(50, 13), { color = UIKit.color(rar.color), z = 4 })
					UIKit.button(r, "Swap", UDim2.fromOffset(50, 12), UDim2.new(1, -54, 0, 12), function()
						move(uid, x.id)
					end, { name = "SwapWith_" .. x.id, color = UIKit.color("plate") }).ZIndex = 4
				end
			end
		end
	end
	local p = asProfile(v)
	for _, h in Tide.huts(p) do
		place(h.uid, buildingName(v, h.uid) or "Hut", h.n, h.room, h.comfort)
	end
	if order == 0 then
		order += 1
		local f = row(list, order, 22)
		UIKit.text(f, "No huts yet. Build one from the Huts tab.", UDim2.new(1, -10, 1, -4), UDim2.fromOffset(5, 2), { color = UIKit.color("text_dim"), z = 4, wrap = true })
	end
end

------------------------------------------------------------------ Driftlings
-- Every driftling, the hardest workers first (one with no hut, its hut cleared away, last). Each: its name in its
-- rarity's colour, its rarity and how fast it works, its passive, its mutations, where it lives and works; Move (the
-- hut picker), Work (where it works) and Sell (two taps).
local function palRow(list: Instance, v: Types.ClientView, x: Types.Pal, order: number, W: number, back: string)
	local d = Creatures.byId[x.sp]
	if d == nil then
		return
	end
	local f = row(list, order, 44)
	f.Name = "Pal_" .. x.id
	PixelSprites.image(f, "icon_" .. x.sp, UDim2.fromOffset(4, 6), 4)
	local rar = Traits.RARITY[d.rarity] or Traits.RARITY[1]
	local tw = W - 108
	UIKit.text(f, d.name, UDim2.fromOffset(90, 10), UDim2.fromOffset(PX, 1), { color = UIKit.color(rar.color), z = 4, name = "Name" })
	UIKit.text(f, rar.name .. ", " .. string.lower(workWord(x)), UDim2.fromOffset(math.max(10, tw - UIKit.textWidth(d.name) - 6), 10), UDim2.fromOffset(PX + UIKit.textWidth(d.name) + 6, 1), { color = UIKit.color("text"), z = 4, name = "Rarity" })
	UIKit.text(f, d.passive.name .. ": " .. Traits.describe(d.passive.fx), UDim2.fromOffset(tw, 10), UDim2.fromOffset(PX, 11), { color = UIKit.color("accent"), z = 4, name = "Passive" })
	mutLine(f, x.muts or {}, PX, 21, tw)
	local where: string
	local color = UIKit.color("text_dim")
	if x.home == 0 then
		where = "No hut. It moves in when one has room."
		color = UIKit.color("orange")
	else
		local hut = buildingName(v, x.home) or "a hut"
		if x.work ~= 0 then
			where = string.format("%s, working at the %s", hut, buildingName(v, x.work) or "?")
			color = UIKit.color("good")
		else
			where = string.format("%s, resting (no free %s)", hut, KNACKS[d.knack] or d.knack)
		end
	end
	UIKit.text(f, where, UDim2.fromOffset(tw, 10), UDim2.fromOffset(PX, 31), { color = color, z = 4, name = "Where" })
	UIKit.button(f, "Move", UDim2.fromOffset(52, 12), UDim2.new(1, -55, 0, 2), function()
		UIKit.openPanel("pals", { move = x.id, back = back })
	end, { name = "Move_" .. x.id, color = UIKit.color("button_ok") }).ZIndex = 4
	UIKit.button(f, "Work", UDim2.fromOffset(52, 12), UDim2.new(1, -55, 0, 16), function()
		UIKit.openPanel("pals", { pal = x.id })
	end, { name = "Help_" .. x.id, enabled = x.home ~= 0 }).ZIndex = 4
	confirmButton(f, "Sell " .. Numbers.coins(Tide.price(x)), UDim2.fromOffset(52, 12), UDim2.new(1, -55, 0, 30), function()
		local res = ask("pal.sell", { id = x.id })
		if res.ok then
			Audio.play("coins")
			local got = if type(res.data) == "table" then tonumber(res.data.shells) or 0 else 0
			UIKit.notice(string.format("Sold %s for %s shells.", d.name, Numbers.coins(got)), UIKit.color("good"))
		end
	end, "Sell_" .. x.id)
end

local function buildPals(body: Frame, arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	if type(arg) == "table" and type(arg.pal) == "number" then
		buildPicker(body, v, arg.pal)
		return
	end
	if type(arg) == "table" and type(arg.move) == "number" then
		buildHutPicker(body, v, arg.move, "pals")
		return
	end
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local housed = 0
	for _, x in v.pals do
		if x.home ~= 0 then
			housed += 1
		end
	end
	-- the tide's panel and a Hatchery's beside the hint (GAME_DESIGN 6, 6.1)
	local hasHatch = #hatcheries(v) > 0
	local buttons = if hasHatch then 128 else 66
	local top = hint(body, string.format("%d in huts (room for %d). New ones float past the island.", housed, v.nests), W - buttons)
	UIKit.button(body, "Tide", UDim2.fromOffset(60, 13), UDim2.fromOffset(W - 60, 0), function()
		UIKit.openPanel("tide")
	end, { name = "OpenTide", color = UIKit.color("button_ok") })
	if hasHatch then
		UIKit.button(body, "Hatchery", UDim2.fromOffset(60, 13), UDim2.fromOffset(W - 122, 0), function()
			UIKit.openPanel("hatch")
		end, { name = "OpenHatch", color = UIKit.color("pink") })
	end
	top = math.max(top, 16)
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - top), UDim2.fromOffset(0, top))
	UIKit.vlist(list, 2)
	if #v.pals == 0 then
		local f = row(list, 1, 24)
		UIKit.text(f, if v.nests == 0 then "No driftlings yet. Build a hut, then tap one as it floats past." else "No driftlings yet. Tap one floating past to take it in.", UDim2.new(1, -10, 1, -4), UDim2.fromOffset(5, 2), { color = UIKit.color("text_dim"), z = 4, wrap = true })
	end
	local order: { Types.Pal } = table.clone(v.pals)
	table.sort(order, function(a: Types.Pal, b: Types.Pal): boolean
		if (a.home == 0) ~= (b.home == 0) then
			return a.home ~= 0
		end
		return Tide.better(a, b)
	end)
	for i, x in order do
		palRow(list, v, x, i, W, "pals")
	end
end

------------------------------------------------------------------ the tide
-- (GAME_DESIGN 6) On the left: how often one comes in, the huts' room, and the odds of each rarity now. On the right:
-- the best few floating by now (TideView.best), each with its portrait, name, rarity and how fast it works, its
-- mutations, Take (its price in shells) and a bar of the time it has left. With { take = id } (every
-- hut full) the swap picker instead: the island's driftlings in huts, the weakest first, each with what it sells for
-- and Swap (tide.take with it: it's sold and the new one takes its place).
local function buildSwap(body: Frame, v: Types.ClientView, id: number)
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local drift: Types.Drift? = nil
	for _, d in v.tide do
		if d.id == id then
			drift = d
		end
	end
	if drift == nil then
		UIKit.notice("That one has floated off.", UIKit.color("text_dim"))
		UIKit.openPanel("tide")
		return
	end
	local dr = drift :: Types.Drift
	local def = Creatures.byId[dr.sp]
	local name = if def then def.name else "It"
	local top = hint(body, string.format("Every hut is full. Swap one out for %s (%s shells): the one you pick is sold.", name, Numbers.coins(dr.cost)), W - 50)
	UIKit.button(body, "Back", UDim2.fromOffset(44, 12), UDim2.fromOffset(W - 44, 0), function()
		UIKit.openPanel("tide")
	end, { name = "Back", color = UIKit.color("plate_light") })
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - top), UDim2.fromOffset(0, top))
	UIKit.vlist(list, 2)
	local order: { Types.Pal } = {}
	for _, x in v.pals do
		if x.home ~= 0 then
			table.insert(order, x)
		end
	end
	table.sort(order, function(a: Types.Pal, b: Types.Pal): boolean
		return Tide.better(b, a)
	end)
	for i, x in order do
		local d = Creatures.byId[x.sp]
		if d == nil then
			continue
		end
		local f = row(list, i, 38)
		f.Name = "SwapOut_" .. x.id
		PixelSprites.image(f, "icon_" .. x.sp, UDim2.fromOffset(4, 3), 4)
		local rar = Traits.RARITY[d.rarity] or Traits.RARITY[1]
		local tw = W - 106
		UIKit.text(f, d.name, UDim2.fromOffset(tw, 10), UDim2.fromOffset(PX, 1), { color = UIKit.color(rar.color), z = 4, name = "Name" })
		UIKit.text(f, rar.name .. ", " .. string.lower(workWord(x)), UDim2.fromOffset(tw, 10), UDim2.fromOffset(PX, 11), { color = UIKit.color("text_dim"), z = 4 })
		mutLine(f, x.muts or {}, PX, 21, tw)
		UIKit.button(f, "Swap", UDim2.fromOffset(56, 12), UDim2.new(1, -59, 0, 3), function()
			TideView.take(id, x.id)
		end, { name = "SwapTake_" .. x.id, color = UIKit.color("button_ok") }).ZIndex = 4
		UIKit.text(f, "Sells for " .. Numbers.coins(Tide.price(x)), UDim2.fromOffset(56, 10), UDim2.new(1, -59, 0, 19), { x = "center", color = UIKit.color("text_dim"), z = 4 })
	end
end

-- What the tide panel shows (rebuilt only when it changes: the tide moves every second): the best few's ids, costs and
-- whether the shells cover them; in the swap picker, whether the one being taken is still there.
local tideArg: any = nil
local tideKey = ""
local function tideKeyOf(v: Types.ClientView, arg: any): string
	if type(arg) == "table" and type(arg.take) == "number" then
		for _, d in v.tide do
			if d.id == arg.take then
				return "swap:" .. d.id
			end
		end
		return "swap:gone"
	end
	local parts: { string } = {}
	for _, d in TideView.best(v, 4) do
		table.insert(parts, string.format("%d:%d:%s", d.id, d.cost, if v.shells >= d.cost then "y" else "n"))
	end
	return table.concat(parts, ",")
end

local function buildTide(body: Frame, arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	tideArg = arg
	tideKey = tideKeyOf(v, arg)
	if type(arg) == "table" and type(arg.take) == "number" then
		buildSwap(body, v, arg.take)
		return
	end
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local p = asProfile(v)
	local LW = math.min(150, math.floor(W * 0.42))
	local RX = LW + 8
	local RW = W - RX
	-- how often
	local pace = if math.abs(v.tideSecs - 1) < 0.05 then "One floats by every second" else string.format("One floats by every %.1fs", v.tideSecs)
	UIKit.text(body, pace, UDim2.fromOffset(LW, 10), UDim2.fromOffset(0, 0), { color = UIKit.color("text"), name = "Pace" })
	local housed = 0
	for _, x in v.pals do
		if x.home ~= 0 then
			housed += 1
		end
	end
	UIKit.text(body, string.format("In huts %d/%d", housed, v.nests), UDim2.fromOffset(LW, 10), UDim2.fromOffset(0, 12), { color = if v.nests > 0 and housed >= v.nests then UIKit.color("orange") else UIKit.color("text"), name = "Room" })
	-- the odds now, rarity by rarity
	UIKit.text(body, "What comes in now", UDim2.fromOffset(LW, 10), UDim2.fromOffset(0, 28), { color = UIKit.color("text_dim") })
	local odds = Tide.odds(p)
	local y = 38
	for r = 1, 5 do
		local rar = Traits.RARITY[r]
		local pct = odds[r] * 100
		local txt = if odds[r] <= 0 then "not yet" elseif pct < 0.1 then "<0.1%" elseif pct < 1 then string.format("%.1f%%", pct) else string.format("%d%%", math.round(pct))
		UIKit.text(body, rar.name, UDim2.fromOffset(LW - 40, 10), UDim2.fromOffset(0, y), { color = UIKit.color(rar.color), name = "Odds_" .. r })
		UIKit.text(body, txt, UDim2.fromOffset(40, 10), UDim2.fromOffset(LW - 40, y), { x = "right", color = if odds[r] > 0 then UIKit.color("text") else UIKit.color("text_dim") })
		y += 10
	end
	if v.tier < 6 and y + 24 <= H then
		local more = "A bigger island brings new kinds and rarer ones."
		UIKit.text(body, more, UDim2.fromOffset(LW, 22), UDim2.fromOffset(0, y + 2), { color = UIKit.color("good"), wrap = true })
	end
	-- the best few floating by, each with the time it has left
	UIKit.text(body, "Floating by", UDim2.fromOffset(RW, 12), UDim2.fromOffset(RX, 0), { color = UIKit.color("accent"), name = "Jetty" })
	local list = UIKit.scroll(body, UDim2.fromOffset(RW, H - 14), UDim2.fromOffset(RX, 14))
	UIKit.vlist(list, 2)
	local shown = TideView.best(v, 4)
	if #shown == 0 then
		local f = row(list, 1, 24)
		UIKit.text(f, "Nothing yet. The next one is on its way.", UDim2.new(1, -10, 1, -4), UDim2.fromOffset(5, 2), { color = UIKit.color("text_dim"), z = 4, wrap = true })
	end
	local bars: { { bar: Frame, d: Types.Drift } } = {}
	for i, d in shown do
		local def = Creatures.byId[d.sp]
		if def == nil then
			continue
		end
		local x: Types.Pal = { id = 0, sp = d.sp, home = 0, work = 0, muts = d.muts }
		local f = row(list, i, 38)
		f.Name = "Drift_" .. d.id
		PixelSprites.image(f, "icon_" .. d.sp, UDim2.fromOffset(4, 3), 4)
		local rar = Traits.RARITY[def.rarity] or Traits.RARITY[1]
		local tw = RW - 106
		UIKit.text(f, def.name, UDim2.fromOffset(tw, 10), UDim2.fromOffset(PX, 1), { color = UIKit.color(rar.color), z = 4, name = "Name" })
		UIKit.text(f, rar.name .. ", " .. string.lower(workWord(x)), UDim2.fromOffset(tw, 10), UDim2.fromOffset(PX, 11), { color = UIKit.color("text_dim"), z = 4 })
		mutLine(f, d.muts, PX, 21, tw)
		-- Take: its price (the shells and the shell icon after them)
		local text = Numbers.coins(d.cost)
		local can = v.shells >= d.cost
		local b = UIKit.button(f, text, UDim2.fromOffset(56, 12), UDim2.new(1, -59, 0, 3), function()
			TideView.take(d.id)
		end, { name = "PanelTake_" .. d.id, color = if can then UIKit.color("button_ok") else UIKit.color("plate_light") })
		b.ZIndex = 4
		local words = b:FindFirstChild("Words")
		if words and words:IsA("GuiObject") then
			words.Position = UDim2.fromOffset(2, 0)
			words.Size = UDim2.new(1, -16, 1, 0)
		end
		PixelSprites.image(b, "mini_shell", UDim2.new(1, -13, 0, 0), 6).Name = "PriceIcon"
		-- (the time it has left before it's gone past)
		local back = UIKit.rect(f, UDim2.fromOffset(56, 4), UDim2.new(1, -59, 0, 21), UIKit.color("ink"), 4)
		back.Name = "Left"
		local fill = UIKit.rect(back, UDim2.fromOffset(54, 2), UDim2.fromOffset(1, 1), UIKit.color(rar.color), 5)
		table.insert(bars, { bar = fill, d = d })
	end
	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function()
		if list.Parent == nil then
			if conn then
				conn:Disconnect()
			end
			return
		end
		for _, r in bars do
			local fw = math.floor(54 * (1 - StateClient.along(r.d)) + 0.5)
			if r.bar.Size.X.Offset ~= fw then
				r.bar.Size = UDim2.fromOffset(fw, 2)
			end
		end
	end)
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
	grid.CellSize = UDim2.fromOffset(math.floor((W - 6 - (cols - 1) * 3) / cols), 70)
	grid.CellPadding = UDim2.fromOffset(3, 3)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list
	for i, d in Creatures.list do
		local n = v.seen[d.id] or 0
		local f = UIKit.plate(list, UDim2.fromOffset(60, 70), nil, if n >= 2 then UIKit.color("plate") else UIKit.color("plate_light"), 0, 2, { bevel = true })
		f.Name = "Entry_" .. d.id
		f.LayoutOrder = i
		local rar = Traits.RARITY[d.rarity] or Traits.RARITY[1]
		PixelSprites.image(f, if n >= 1 then "icon_" .. d.id else "icon_" .. d.id .. "_sil", UDim2.fromOffset(3, 3), 4)
		UIKit.text(f, if n >= 1 then d.name else "???", UDim2.new(1, -40, 0, 10), UDim2.fromOffset(37, 4), { color = if n >= 1 then UIKit.color(rar.color) else UIKit.color("text_dim"), z = 4, name = "Name" })
		-- its rarity (always: a rare one is worth hoping for) and its kind of land, each a line beside the portrait
		local kind = Islets.list[d.islet]
		if kind then
			UIKit.text(f, kind.plural, UDim2.new(1, -40, 0, 10), UDim2.fromOffset(37, 22), { color = UIKit.color("text_dim"), z = 4, name = "Land" })
		end
		UIKit.text(f, rar.name, UDim2.new(1, -40, 0, 10), UDim2.fromOffset(37, 13), { color = UIKit.color(rar.color), z = 4, name = "Rarity" })
		if n >= 1 then
			-- seen: its passive
			UIKit.text(f, d.passive.name, UDim2.new(1, -6, 0, 10), UDim2.fromOffset(3, 38), { color = UIKit.color("accent"), z = 4, name = "Passive" })
			UIKit.text(f, Traits.describe(d.passive.fx), UDim2.new(1, -6, 0, 20), UDim2.fromOffset(3, 48), { color = UIKit.color("text_dim"), wrap = true, z = 4, name = "PassiveFx" })
		else
			local from = if kind and kind.tier > v.tier then string.format("These float by from island Lv %d.", kind.tier) else "Not seen yet."
			UIKit.text(f, from, UDim2.new(1, -6, 0, 30), UDim2.fromOffset(3, 38), { color = UIKit.color("text_dim"), wrap = true, z = 4 })
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
	UIKit.registerPanel("pals", { title = "Driftlings", icon = "pal", w = 320, h = 186, build = buildPals })
	UIKit.registerPanel("hatch", { title = "Hatchery", icon = "nest", w = 320, h = 186, build = buildHatch })
	UIKit.registerPanel("tide", { title = "Tide", icon = "tide", w = 380, h = 196, build = buildTide })
	UIKit.registerPanel("index", { title = "Index", icon = "star", w = 320, h = 186, build = buildIndex })
	UIKit.registerPanel("looks", { title = "Looks", icon = "visitor", w = 200, h = 106, build = buildLooks })
	UIKit.PanelChanged:Connect(function(name: string?)
		if name ~= "looks" then
			draft = nil
		end
	end)
	-- (the tide moves every second: its panel is rebuilt only when what it shows changes)
	StateClient.TideChanged:Connect(function(v: Types.ClientView)
		if UIKit.currentPanel() == "tide" and tideKeyOf(v, tideArg) ~= tideKey then
			UIKit.refreshPanel()
		end
	end)
end

return Menus
