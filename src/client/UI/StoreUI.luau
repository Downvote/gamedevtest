--!strict
-- The Store and the Looks panel (GAME_DESIGN 14.2; docs/ARCHITECTURE.md 10.13). The request (2026-11-14): "make
-- titles. make much more cosmetics, and a rotating shop for cosmetics. make gamepasses for double income, developer
-- products for hatching any rarity of egg, refreshing shop, a starter pack, speeding up hatcheries, a gamepass track
-- with eggs, money and cosmetics along with a premium track, a vip gamepass offering alot of rewards, and cosmetics, a
-- title and a percentage increase to income, a gamepass that speeds up the tree of life refresh to 5 minutes, and a
-- gamepass that allows for decor and paths to be free".
--   The Store panel ("store"; its argument a tab: "passes", "eggs", "shop", "track"): four tabs along its top.
--     Passes: the five game passes, what each does, its price in Robux (the live price once MarketplaceService has it,
--       else Config/Monetization.SuggestedRobux), Buy or Owned; VIP's row has the daily gift's button once it is owned.
--     Eggs and more: the six egg products, Shop Refresh, the Starter Pack (gone once bought) and Finish Hatcheries.
--     Shop: the rotating shop's six pieces (Logic/Store.shopNow, the view's shopList) with their pictures
--       (UI/CosmeticIcons), rarity, slot and price in shells; Buy (shop.buy), then Wear; when the next set comes, and a
--       button to buy a new set now.
--     Track: the pass track's level, a bar to the next one and the season's time left; each level's free and premium
--       reward with Claim (track.claim), the premium side locked without its pass (a button to buy it).
--   Buying: only an id that is set (Monetization.isEnabled) goes to MarketplaceService; one that isn't says so. What a
--   purchase gives comes back as Fx "pass" and "rewards" (MonetizationService), each told in a notice; a title earned
--   is told too (Fx "titles").
--   The Looks panel ("looks"; argument "pieces" or "titles"): the founder's portrait, the free colours and hair style
--   (Save look: founder.set), then the pieces they own slot by slot (Wear, Take off: look.wear) or the titles (Wear:
--   title.set; the ones not earned yet greyed, with what earns them).
--   The HUD's offers (StoreUI.offers, placed by UI/Hud): the Starter Pack until it is bought, VIP's gift on a day it
--   waits.
-- API: StoreUI.init(), StoreUI.buy(key), StoreUI.offers(parent, v, w) -> Frame?, StoreUI.offerKey(v) -> string,
-- StoreUI.rewardText(from, given) -> string, StoreUI.TABS.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Shared.Types)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Cosmetics = require(ReplicatedStorage.Shared.Data.Cosmetics)
local Titles = require(ReplicatedStorage.Shared.Data.Titles)
local Track = require(ReplicatedStorage.Shared.Data.Track)
local Traits = require(ReplicatedStorage.Shared.Data.Traits)
local Creatures = require(ReplicatedStorage.Shared.Data.Creatures)
local Looks = require(ReplicatedStorage.Shared.Data.Looks)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local Store = require(ReplicatedStorage.Shared.Logic.Store)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local CosmeticIcons = require(script.Parent.CosmeticIcons)
local Words = require(script.Parent.Words)

local StoreUI = {}

------------------------------------------------------------------ what is sold
type Item = { key: string, name: string, blurb: string, icon: string, pass: boolean }

local PASSES: { Item } = {
	{ key = "VIP", name = "VIP", blurb = "25% more shells, a big welcome gift, a gift every day, six pieces and the VIP title.", icon = "mini_crown", pass = true },
	{ key = "DoubleIncome", name = "Double Income", blurb = "Every shell your island makes counts twice.", icon = "mini_shell", pass = true },
	{ key = "QuickTree", name = "Quick Tree", blurb = "The Tree of Life lays new eggs every 5 minutes, not 10.", icon = "mini_tree", pass = true },
	{ key = "FreeDecor", name = "Free Decor", blurb = "Decor, paths, water and fences cost nothing to put down.", icon = "mini_decor", pass = true },
	{ key = "PremiumTrack", name = "Premium Track", blurb = "Opens the premium side of the pass track, this season and every one after.", icon = "mini_ticket", pass = true },
}

local PRODUCTS: { Item } = {
	{ key = "StarterPack", name = "Starter Pack", blurb = "An hour of shells, an epic and a legendary egg, the Explorer set and the Early Bird title. Once only.", icon = "mini_gift", pass = false },
	{ key = "HatcheryNow", name = "Finish Hatcheries", blurb = "Every egg warming in your Hatcheries hatches now.", icon = "mini_nest", pass = false },
	{ key = "RefreshShop", name = "Shop Refresh", blurb = "Six new pieces in the shop right away.", icon = "mini_refresh", pass = false },
}
-- (the egg products, Uncommon to Celestial)
for _, key in Store.PRODUCTS do
	local r = Store.EGG_R[key]
	if r then
		local rar = Traits.RARITY[r]
		table.insert(PRODUCTS, { key = key, name = rar.name .. " Egg", blurb = "Goes in your bag. Hatch it for nothing from the Tree of Life.", icon = "egg_" .. r, pass = false })
	end
end

local ITEM_BY: { [string]: Item } = {}
for _, it in PASSES do
	ITEM_BY[it.key] = it
end
for _, it in PRODUCTS do
	ITEM_BY[it.key] = it
end

StoreUI.TABS = {
	{ id = "passes", text = "Passes", icon = "crown" },
	{ id = "eggs", text = "Eggs and more", icon = "egg" },
	{ id = "shop", text = "Shop", icon = "store" },
	{ id = "track", text = "Track", icon = "ticket" },
}

------------------------------------------------------------------ prices and buying
local function idOf(key: string): (number, boolean)
	local passId = Monetization.GamePasses[key]
	if passId ~= nil then
		return passId, true
	end
	return Monetization.DevProducts[key] or 0, false
end

-- the live prices MarketplaceService gave (an id that is set), fetched once each in the background
local live: { [string]: number } = {}
local asked: { [string]: boolean } = {}
local function robux(key: string): number
	local id, pass = idOf(key)
	if Monetization.isEnabled(id) and not asked[key] then
		asked[key] = true
		task.spawn(function()
			local ok, info = pcall(function(): any
				return MarketplaceService:GetProductInfoAsync(id, if pass then Enum.InfoType.GamePass else Enum.InfoType.Product)
			end)
			if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
				live[key] = info.PriceInRobux
				if UIKit.currentPanel() == "store" then
					UIKit.refreshPanel()
				end
			end
		end)
	end
	return live[key] or Monetization.SuggestedRobux[key] or 0
end

local function robuxText(key: string): string
	return "R$ " .. Numbers.coins(robux(key))
end

-- Ask Roblox to sell `key` (a pass or a product): only one whose id is set; one that isn't says so.
function StoreUI.buy(key: string)
	local id, pass = idOf(key)
	if not Monetization.isEnabled(id) then
		Audio.play("deny")
		UIKit.notice("That isn't on sale yet.", UIKit.color("text_dim"))
		return
	end
	Audio.play("click")
	local ok, err = pcall(function()
		if pass then
			MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, id)
		else
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, id)
		end
	end)
	if not ok then
		warn("[StoreUI] couldn't open the purchase: " .. tostring(err))
	end
end

local function owns(v: Types.ClientView, key: string): boolean
	return v.passes ~= nil and v.passes[key] == true
end

-- whether VIP's daily gift waits today (the sea's clock's UTC day, as Logic/Store.vipDaily counts it)
local function vipWaiting(v: Types.ClientView): boolean
	return owns(v, "VIP") and v.vipDay ~= math.floor(StateClient.seaClock() / 86400)
end

local function claimVip()
	local res = StateClient.request("vip.daily", {})
	if res.ok then
		Audio.play("reward")
	else
		Audio.play("deny")
		UIKit.notice(if res.err == "cooldown" then "You already had today's gift. Come back tomorrow." else Words.errText(res.err), UIKit.color("bad"))
	end
end

------------------------------------------------------------------ words
local function an(word: string): string
	local c = string.lower(string.sub(word, 1, 1))
	return if c == "a" or c == "e" or c == "i" or c == "o" or c == "u" then "an" else "a"
end

-- A reward's words (Data/Track's shape) for this player now: "1,200 shells", "an epic egg", "Tide Crown", "Title:
-- Captain".
local function rewardWords(v: Types.ClientView, r: Track.Reward): string
	if r.kind == "shells" then
		return Numbers.coins(math.floor((v.minuteShells or 0) * (r.mins or 1))) .. " shells"
	elseif r.kind == "egg" then
		local rar = Traits.RARITY[math.clamp(r.r or 1, 1, Traits.RMAX)]
		return string.format("%s %s egg", an(rar.name), string.lower(rar.name))
	elseif r.kind == "look" then
		local c = Cosmetics.byId[r.id or ""]
		return if c then c.name else "a piece"
	elseif r.kind == "title" then
		local t = Titles.byId[r.id or ""]
		return "Title: " .. (if t then t.name else "?")
	end
	return ""
end

-- What a purchase or a reward gave (Fx rewards' `given`), in one plain line: each thing when there are three or fewer,
-- else counted ("2 eggs, 2 pieces").
local FROM: { [string]: string } = { vip = "Today's VIP gift", track = "Pass track", VIP = "VIP's welcome gift" }
function StoreUI.rewardText(from: string, given: { any }): string
	local head = FROM[from] or (if ITEM_BY[from] then ITEM_BY[from].name else "Got")
	local parts: { string } = {}
	local shells, eggs, looks, titles, pals = 0, 0, 0, 0, 0
	local one: { string } = {}
	for _, g in given do
		if type(g) ~= "table" then
			continue
		end
		if g.kind == "shells" then
			shells += tonumber(g.n) or 0
		elseif g.kind == "egg" then
			eggs += 1
			local rar = Traits.RARITY[math.clamp(tonumber(g.r) or 1, 1, Traits.RMAX)]
			table.insert(one, string.format("%s %s egg", an(rar.name), string.lower(rar.name)))
		elseif g.kind == "look" then
			looks += 1
			local c = Cosmetics.byId[tostring(g.id)]
			table.insert(one, if c then c.name else "a piece")
		elseif g.kind == "title" then
			titles += 1
			local t = Titles.byId[tostring(g.id)]
			table.insert(one, "the " .. (if t then t.name else "new") .. " title")
		elseif g.kind == "shop" then
			table.insert(one, "a new set in the shop")
		elseif g.kind == "pal" then
			pals += 1
			local d = Creatures.byId[tostring(g.id)]
			table.insert(one, if d then d.name .. " hatched" else "a driftling hatched")
		end
	end
	if shells > 0 then
		table.insert(parts, Numbers.coins(shells) .. " shells")
	end
	if #one + #parts <= 3 then
		for _, w in one do
			table.insert(parts, w)
		end
	else
		if eggs > 0 then
			table.insert(parts, if eggs == 1 then "an egg" else eggs .. " eggs")
		end
		if looks > 0 then
			table.insert(parts, if looks == 1 then "a piece" else looks .. " pieces")
		end
		if titles > 0 then
			table.insert(parts, if titles == 1 then "a title" else titles .. " titles")
		end
		if pals > 0 then
			table.insert(parts, if pals == 1 then "a driftling hatched" else pals .. " driftlings hatched")
		end
	end
	if #parts == 0 then
		return head .. "."
	end
	local list = parts[1]
	for i = 2, #parts do
		list ..= (if i == #parts then " and " else ", ") .. parts[i]
	end
	return head .. ": " .. list .. "."
end

-- What earns a title, plainly (Data/Titles `how`, `n`).
local function howWords(t: Titles.Title): string
	local h, n = t.how, t.n
	if h == "start" then
		return "Everyone starts with this one."
	elseif h == "tier" then
		return string.format("Grow your island to level %d.", n)
	elseif h == "taken" then
		return string.format("Hatch %s eggs.", Numbers.coins(n))
	elseif h == "best" then
		local rar = Traits.RARITY[math.clamp(n, 1, Traits.RMAX)]
		return string.format("Have %s %s driftling.", an(rar.name), string.lower(rar.name))
	elseif h == "seen" then
		return if n > 0 then string.format("Find %d kinds for the Index.", n) else "Find every kind for the Index."
	elseif h == "earned" then
		return string.format("Make %s shells in all.", Numbers.coins(n))
	elseif h == "hatched" then
		return string.format("Hatch %d Hatchery eggs.", n)
	elseif h == "days" then
		return string.format("Play on %d island days.", n)
	elseif h == "owned" then
		return string.format("Own %d pieces to wear.", n)
	elseif h == "vip" then
		return "Comes with VIP."
	elseif h == "starter" then
		return "Comes with the Starter Pack."
	elseif h == "track" then
		return "A pass track reward."
	end
	return ""
end
StoreUI.howWords = howWords

------------------------------------------------------------------ pieces of the panels
local function row(list: Instance, order: number, h: number, name: string?): Frame
	local f = UIKit.row(list, UDim2.new(1, -6, 0, h), nil)
	f.Name = name or "Row"
	f.LayoutOrder = order
	return f
end

-- A cosmetic's picture centred in a box of `box` px at (x, y).
local function pieceIcon(parent: Instance, id: string, x: number, y: number, box: number, z: number?): GuiObject
	local w, h = CosmeticIcons.size(id)
	local g = CosmeticIcons.image(parent, id, UDim2.fromOffset(x + math.floor((box - w) / 2), y + math.floor((box - h) / 2)), z or 4)
	g.Name = "Pic_" .. id
	return g
end

-- A sprite centred in a box.
local function spriteIn(parent: Instance, name: string, x: number, y: number, box: number, z: number?): GuiObject
	local w, h = PixelSprites.size(name)
	return PixelSprites.image(parent, name, UDim2.fromOffset(x + math.floor((box - w) / 2), y + math.floor((box - h) / 2)), z or 4)
end

-- The price button of a pass or product: its Robux, or Owned.
local function robuxButton(parent: Instance, key: string, x: number, y: number, w: number, owned: boolean?): GuiButton
	if owned then
		local b = UIKit.button(parent, "Owned", UDim2.fromOffset(w, 13), UDim2.fromOffset(x, y), function() end, { name = "Buy_" .. key, color = UIKit.color("plate_light"), enabled = false })
		b.ZIndex = 4
		return b
	end
	local b = UIKit.button(parent, robuxText(key), UDim2.fromOffset(w, 13), UDim2.fromOffset(x, y), function()
		StoreUI.buy(key)
	end, { name = "Buy_" .. key, color = UIKit.color("button_ok") })
	b.ZIndex = 4
	return b
end

-- A shells price with the small shell (red when there aren't enough).
local function shellPrice(parent: Instance, x: number, y: number, shells: number, have: number, z: number?)
	PixelSprites.image(parent, "mini_shell", UDim2.fromOffset(x, y), z or 4)
	local t = Numbers.coins(shells)
	UIKit.text(parent, t, UDim2.fromOffset(UIKit.textWidth(t) + 2, 10), UDim2.fromOffset(x + 12, y + 1), { color = if have >= shells then UIKit.color("text") else UIKit.color("bad"), z = z or 4, name = "Price" })
end

-- a countdown label kept up to date while it is on screen
local function countdown(label: TextLabel, left: () -> number, fmt: string)
	local conn: RBXScriptConnection? = nil
	local last = ""
	conn = RunService.Heartbeat:Connect(function()
		if label.Parent == nil then
			if conn then
				conn:Disconnect()
			end
			return
		end
		local secs = math.max(60, left())
		local t = string.format(fmt, if secs >= 2 * 86400 then string.format("%d days", math.floor(secs / 86400)) else Numbers.duration(secs))
		if t ~= last then
			last = t
			UIKit.setText(label, t)
		end
	end)
end

------------------------------------------------------------------ the tabs
local tab = "passes"

local function buildPasses(body: Frame, v: Types.ClientView, W: number, H: number, top: number)
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - top), UDim2.fromOffset(0, top))
	list.Name = "List"
	UIKit.vlist(list, 2)
	local BW = 62
	for i, it in PASSES do
		local has = owns(v, it.key)
		local f = row(list, i, 34, "Pass_" .. it.key)
		spriteIn(f, it.icon, 3, 4, 14)
		UIKit.text(f, it.name, UDim2.fromOffset(W - BW - 40, 10), UDim2.fromOffset(22, 2), { color = if it.key == "VIP" then UIKit.color("accent") else UIKit.color("text"), z = 4, name = "Name" })
		UIKit.text(f, it.blurb, UDim2.fromOffset(W - BW - 32, 20), UDim2.fromOffset(22, 12), { color = UIKit.color("text_dim"), z = 4, wrap = true, name = "Blurb" })
		local bx = W - BW - 10
		if it.key == "VIP" and has then
			-- (VIP owned: its daily gift here once a day)
			local waiting = vipWaiting(v)
			local b = UIKit.button(f, if waiting then "Daily gift" else "Owned", UDim2.fromOffset(BW, 13), UDim2.fromOffset(bx, 3), function()
				if vipWaiting(StateClient.view() or v) then
					claimVip()
				end
			end, { name = "VipGift", color = if waiting then UIKit.color("button_ok") else UIKit.color("plate_light"), enabled = waiting })
			b.ZIndex = 4
			if not waiting then
				UIKit.text(f, "Gift again tomorrow", UDim2.fromOffset(BW + 8, 10), UDim2.fromOffset(bx - 4, 18), { x = "center", color = UIKit.color("text_dim"), z = 4 })
			end
		else
			robuxButton(f, it.key, bx, 3, BW, has)
		end
	end
end

local function buildEggs(body: Frame, v: Types.ClientView, W: number, H: number, top: number)
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - top), UDim2.fromOffset(0, top))
	list.Name = "List"
	UIKit.vlist(list, 2)
	local BW = 62
	local order = 0
	for _, it in PRODUCTS do
		if it.key == "StarterPack" and v.gifts and v.gifts.starter then
			continue
		end
		order += 1
		local r = Store.EGG_R[it.key]
		local f = row(list, order, if r then 24 else 34, "Product_" .. it.key)
		spriteIn(f, it.icon, 2, if r then 3 else 4, 18)
		local color = if r then UIKit.color(Traits.RARITY[r].color) elseif it.key == "StarterPack" then UIKit.color("accent") else UIKit.color("text")
		UIKit.text(f, it.name, UDim2.fromOffset(W - BW - 40, 10), UDim2.fromOffset(24, 2), { color = color, z = 4, name = "Name" })
		local blurb = it.blurb
		if it.key == "HatcheryNow" then
			blurb = if #(v.eggs or {}) > 0 then string.format("Every egg warming in your Hatcheries hatches now (%d warming).", #v.eggs) else "Every egg warming in your Hatcheries hatches now. None warming at the moment."
		end
		UIKit.text(f, blurb, UDim2.fromOffset(W - BW - 34, if r then 10 else 20), UDim2.fromOffset(24, 12), { color = UIKit.color("text_dim"), z = 4, wrap = r == nil, name = "Blurb" })
		robuxButton(f, it.key, W - BW - 10, 3, BW)
	end
	-- (where bought eggs go)
	local n = #(v.bag or {})
	local f = row(list, order + 1, 14, "BagNote")
	UIKit.text(f, if n > 0 then string.format("%d %s in your bag. Hatch them from the Tree of Life.", n, if n == 1 then "egg" else "eggs") else "Eggs you buy wait in your bag at the Tree of Life.", UDim2.new(1, -8, 1, 0), UDim2.fromOffset(4, 1), { color = UIKit.color("text_dim"), z = 4 })
end

-- (Logic/Store.price reads only the tier)
local function asProfileLite(v: Types.ClientView): any
	return { tier = v.tier }
end

local function buildShop(body: Frame, v: Types.ClientView, W: number, H: number, top: number)
	-- the next set's countdown and the refresh
	local when = UIKit.text(body, "", UDim2.fromOffset(W - 120, 12), UDim2.fromOffset(0, top), { color = UIKit.color("text_dim"), name = "ShopLeft" })
	countdown(when, function(): number
		local _, left = Store.rotation(StateClient.seaClock())
		return left
	end, "New pieces in %s")
	local rb = UIKit.button(body, "New set " .. robuxText("RefreshShop"), UDim2.fromOffset(112, 13), UDim2.fromOffset(W - 114, top - 1), function()
		StoreUI.buy("RefreshShop")
	end, { name = "ShopRefresh", color = UIKit.color("button_warn") })
	rb.ZIndex = 4
	local y0 = top + 15
	local cols = if W >= 330 then 3 else 2
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - y0), UDim2.fromOffset(0, y0))
	list.Name = "List"
	local cw = math.floor((W - 6 - (cols - 1) * 3) / cols)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(cw, 62)
	grid.CellPadding = UDim2.fromOffset(3, 3)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list
	local ids: { string } = v.shopList or {}
	for i, id in ids do
		local c = Cosmetics.byId[id]
		if c == nil then
			continue
		end
		local rar = Traits.RARITY[c.rarity] or Traits.RARITY[1]
		local f = UIKit.row(list, UDim2.fromOffset(cw, 62), nil)
		f.Name = "Piece_" .. id
		f.LayoutOrder = i
		pieceIcon(f, id, 3, 3, 24)
		local tw = cw - 32
		UIKit.text(f, c.name, UDim2.fromOffset(tw, 10), UDim2.fromOffset(30, 3), { color = UIKit.color(rar.color), z = 4, name = "Name" })
		local slot = ""
		for _, s in Cosmetics.SLOTS do
			if s.id == c.slot then
				slot = s.name
			end
		end
		UIKit.text(f, rar.name .. ", " .. string.lower(slot), UDim2.fromOffset(tw, 10), UDim2.fromOffset(30, 13), { color = UIKit.color("text_dim"), z = 4, name = "Kind" })
		local has = v.owned and v.owned[id] == true
		if has then
			local worn = (v.founder :: any)[c.slot] == id
			local b = UIKit.button(f, if worn then "Wearing" else "Wear", UDim2.fromOffset(cw - 8, 13), UDim2.fromOffset(4, 45), function()
				local res = StateClient.request("look.wear", { slot = c.slot, id = id })
				if res.ok then
					Audio.play("flip")
					UIKit.notice("You're wearing the " .. c.name .. ".", UIKit.color("good"))
				else
					Audio.play("deny")
					UIKit.notice(Words.errText(res.err), UIKit.color("bad"))
				end
			end, { name = "Wear_" .. id, color = if worn then UIKit.color("plate_light") else UIKit.color("button"), enabled = not worn })
			b.ZIndex = 4
			UIKit.text(f, "Owned", UDim2.fromOffset(tw, 10), UDim2.fromOffset(30, 30), { color = UIKit.color("good"), z = 4, name = "Owned" })
		else
			local cost = Store.price(asProfileLite(v), id)
			shellPrice(f, 30, 29, cost, v.shells)
			local b = UIKit.button(f, "Buy", UDim2.fromOffset(cw - 8, 13), UDim2.fromOffset(4, 45), function()
				local res = StateClient.request("shop.buy", { id = id })
				if res.ok then
					Audio.play("reward")
					UIKit.notice("The " .. c.name .. " is yours. Wear it from Looks or here.", UIKit.color("good"))
				else
					Audio.play("deny")
					UIKit.notice(if res.err == "not_found" then "The shop changed. Have a look at the new set." else Words.errText(res.err), UIKit.color("bad"))
				end
			end, { name = "ShopBuy_" .. id, color = if v.shells >= cost then UIKit.color("button_ok") else UIKit.color("plate_light") })
			b.ZIndex = 4
		end
	end
end

local function buildTrack(body: Frame, v: Types.ClientView, W: number, H: number, top: number)
	local lvl, into, need = v.trackLevel or 0, v.trackInto or 0, v.trackNeed or 0
	local prem = owns(v, "PremiumTrack")
	UIKit.text(body, string.format("Level %d of %d", lvl, Track.LEVELS), UDim2.fromOffset(90, 10), UDim2.fromOffset(0, top), { color = UIKit.color("accent"), name = "TrackLevel" })
	local bw = math.max(60, W - 230)
	local back = UIKit.rect(body, UDim2.fromOffset(bw, 6), UDim2.fromOffset(92, top + 2), UIKit.color("glass"), 3)
	back.BackgroundTransparency = 0.25
	back.Name = "TrackBar"
	local k = if need > 0 then math.clamp(into / need, 0, 1) else 1
	UIKit.rect(back, UDim2.fromOffset(math.floor((bw - 2) * k + 0.5), 4), UDim2.fromOffset(1, 1), UIKit.color("good"), 4).Name = "Fill"
	UIKit.text(body, if need > 0 then string.format("%d/%d", math.floor(into), need) else "All done", UDim2.fromOffset(60, 10), UDim2.fromOffset(96 + bw, top), { color = UIKit.color("text_dim"), name = "TrackPoints" })
	local left = UIKit.text(body, "", UDim2.fromOffset(110, 10), UDim2.fromOffset(W - 110, top), { x = "right", color = UIKit.color("text_dim"), name = "TrackLeft" })
	countdown(left, function(): number
		local _, l = Store.season(StateClient.seaClock())
		return l
	end, "Ends in %s")
	-- the sides' headings, and the premium side's lock
	local y1 = top + 12
	local LW = 30
	local half = math.floor((W - LW - 10) / 2)
	UIKit.text(body, "Free", UDim2.fromOffset(half, 10), UDim2.fromOffset(LW, y1), { color = UIKit.color("text"), name = "FreeHead" })
	UIKit.text(body, "Premium", UDim2.fromOffset(half, 10), UDim2.fromOffset(LW + half + 4, y1), { color = UIKit.color("accent"), name = "PremHead" })
	if not prem then
		local b = UIKit.button(body, "Unlock " .. robuxText("PremiumTrack"), UDim2.fromOffset(110, 12), UDim2.fromOffset(W - 112, y1 - 1), function()
			StoreUI.buy("PremiumTrack")
		end, { name = "Buy_PremiumTrackTop", color = UIKit.color("button_warn") })
		b.ZIndex = 4
	end
	local y0 = y1 + 12
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - y0), UDim2.fromOffset(0, y0))
	list.Name = "List"
	UIKit.vlist(list, 2)
	local got: { number } = if v.track then v.track.got else {}
	local gotP: { number } = if v.track then v.track.gotP else {}
	local first: Frame? = nil
	for L, lv in Track.list do
		local f = row(list, L, 28, "Level_" .. L)
		local reached = L <= lvl
		UIKit.text(f, "Lv " .. L, UDim2.fromOffset(LW - 2, 10), UDim2.fromOffset(3, 9), { color = if reached then UIKit.color("accent") else UIKit.color("text_dim"), z = 4, name = "Lv" })
		local function side(r: Track.Reward, x: number, isPrem: boolean, claimed: boolean)
			local extra = if L == Track.LEVELS then (if isPrem then Track.extra.prem else Track.extra.free) else nil
			-- its picture: a piece's own, an egg, the shell, the star for a title
			if r.kind == "look" and r.id then
				pieceIcon(f, r.id, x, 2, 24)
			elseif r.kind == "egg" then
				spriteIn(f, "egg_" .. math.clamp(r.r or 1, 1, Traits.RMAX), x, 2, 24)
			elseif r.kind == "title" then
				spriteIn(f, "mini_star", x, 2, 24)
			else
				spriteIn(f, "mini_shell", x, 2, 24)
			end
			local words = rewardWords(v, r) .. (if extra then " + " .. rewardWords(v, extra) else "")
			local color = if r.kind == "egg" then UIKit.color(Traits.RARITY[math.clamp(r.r or 1, 1, Traits.RMAX)].color) elseif r.kind == "look" or r.kind == "title" then UIKit.color("accent") else UIKit.color("text")
			local tw = half - 26 - 46
			UIKit.text(f, words, UDim2.fromOffset(tw, 22), UDim2.fromOffset(x + 26, 3), { color = color, z = 4, wrap = true, name = if isPrem then "PremWords" else "FreeWords" })
			local bx = x + half - 46
			local name = (if isPrem then "ClaimP_" else "Claim_") .. L
			if claimed then
				UIKit.text(f, "Got it", UDim2.fromOffset(44, 10), UDim2.fromOffset(bx, 9), { x = "center", color = UIKit.color("good"), z = 4, name = name })
			elseif isPrem and not prem then
				spriteIn(f, "mini_ticket", bx + 16, 8, 12).Name = name
			elseif not reached then
				UIKit.text(f, "Lv " .. L, UDim2.fromOffset(44, 10), UDim2.fromOffset(bx, 9), { x = "center", color = UIKit.color("text_dim"), z = 4, name = name })
			else
				local b = UIKit.button(f, "Claim", UDim2.fromOffset(44, 13), UDim2.fromOffset(bx, 7), function()
					local res = StateClient.request("track.claim", { lvl = L, prem = isPrem })
					if res.ok then
						Audio.play("reward")
					else
						Audio.play("deny")
						UIKit.notice(Words.errText(res.err), UIKit.color("bad"))
					end
				end, { name = name, color = UIKit.color("button_ok") })
				b.ZIndex = 4
			end
		end
		side(lv.free, LW, false, table.find(got, L) ~= nil)
		side(lv.prem, LW + half + 4, true, table.find(gotP, L) ~= nil)
		if first == nil and reached and (table.find(got, L) == nil or (prem and table.find(gotP, L) == nil)) then
			first = f
		end
	end
	-- (the list opens at the first level with something to claim, else at the level reached)
	task.defer(function()
		if list.Parent == nil then
			return
		end
		local at = math.max(0, (if first then first.LayoutOrder else lvl + 1) - 2)
		list.CanvasPosition = Vector2.new(0, at * 30)
	end)
end

local function buildStore(body: Frame, arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	if type(arg) == "string" then
		for _, t in StoreUI.TABS do
			if t.id == arg then
				tab = arg
			end
		end
	end
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	-- the tabs: each its icon and words, the one open in the accent
	local x = 0
	for _, t in StoreUI.TABS do
		local w = UIKit.buttonWidth(t.text, 4) + 13
		local on = t.id == tab
		local b = UIKit.button(body, t.text, UDim2.fromOffset(w, 13), UDim2.fromOffset(x, 0), function()
			if tab ~= t.id then
				tab = t.id
				Audio.play("flip")
				UIKit.refreshPanel()
			end
		end, { name = "Tab_" .. t.id, color = if on then UIKit.color("button") else UIKit.color("plate_light") })
		b.ZIndex = 4
		PixelSprites.image(b, "mini_" .. t.icon, UDim2.fromOffset(2, 1), 6)
		local words = b:FindFirstChild("Words")
		if words and words:IsA("GuiObject") then
			words.Position = UDim2.fromOffset(13, 0)
			words.Size = UDim2.new(1, -15, 1, 0)
		end
		x += w + 2
	end
	local top = 16
	if tab == "passes" then
		buildPasses(body, v, W, H, top)
	elseif tab == "eggs" then
		buildEggs(body, v, W, H, top)
	elseif tab == "shop" then
		buildShop(body, v, W, H, top)
	else
		buildTrack(body, v, W, H, top)
	end
end

------------------------------------------------------------------ Looks: the founder, their pieces and titles
local draft: Types.Look? = nil -- the colours and hair style being tried (saved with Save look)
local looksTab = "pieces"
local slotTab = "hat"
local LOOK_ROWS: { { key: string, label: string, n: number } } = {
	{ key = "skin", label = "Skin", n = #Looks.skin },
	{ key = "hair", label = "Hair", n = #Looks.hair },
	{ key = "style", label = "Style", n = #Looks.styles },
	{ key = "shirt", label = "Shirt", n = #Looks.shirt },
}

local function wear(slot: string, id: string)
	local res = StateClient.request("look.wear", { slot = slot, id = id })
	if res.ok then
		Audio.play("flip")
	else
		Audio.play("deny")
		UIKit.notice(Words.errText(res.err), UIKit.color("bad"))
	end
end

local function buildPieces(body: Frame, v: Types.ClientView, x0: number, W: number, H: number)
	-- the slots along the top
	local x = x0
	for _, s in Cosmetics.SLOTS do
		local w = UIKit.buttonWidth(s.name, 3)
		local on = s.id == slotTab
		UIKit.button(body, s.name, UDim2.fromOffset(w, 12), UDim2.fromOffset(x, 15), function()
			if slotTab ~= s.id then
				slotTab = s.id
				Audio.play("flip")
				UIKit.refreshPanel()
			end
		end, { name = "Slot_" .. s.id, color = if on then UIKit.color("button") else UIKit.color("plate_light") }).ZIndex = 4
		x += w + 2
	end
	local list = UIKit.scroll(body, UDim2.fromOffset(W - x0, H - 30), UDim2.fromOffset(x0, 30))
	list.Name = "List"
	UIKit.vlist(list, 2)
	local worn = (v.founder :: any)[slotTab]
	local have: { Cosmetics.Piece } = {}
	local pool: { Cosmetics.Piece } = Cosmetics.bySlot[slotTab] or {}
	for _, c in pool do
		if v.owned and v.owned[c.id] then
			table.insert(have, c)
		end
	end
	table.sort(have, function(a, b): boolean
		if a.rarity ~= b.rarity then
			return a.rarity > b.rarity
		end
		return a.name < b.name
	end)
	local RW = W - x0
	if #have == 0 then
		local f = row(list, 1, 34, "NoPieces")
		UIKit.text(f, "None of these yet. The Store's shop has new pieces every few hours, and the pass track gives some.", UDim2.new(1, -10, 1, -4), UDim2.fromOffset(5, 2), { color = UIKit.color("text_dim"), z = 4, wrap = true })
		return
	end
	for i, c in have do
		local rar = Traits.RARITY[c.rarity] or Traits.RARITY[1]
		local f = row(list, i, 28, "Own_" .. c.id)
		pieceIcon(f, c.id, 2, 2, 24)
		UIKit.text(f, c.name, UDim2.fromOffset(RW - 90, 10), UDim2.fromOffset(28, 4), { color = UIKit.color(rar.color), z = 4, name = "Name" })
		UIKit.text(f, rar.name, UDim2.fromOffset(RW - 90, 10), UDim2.fromOffset(28, 14), { color = UIKit.color("text_dim"), z = 4 })
		local on = worn == c.id
		local b = UIKit.button(f, if on then "Take off" else "Wear", UDim2.fromOffset(52, 13), UDim2.new(1, -55, 0, 7), function()
			wear(c.slot, if on then "" else c.id)
		end, { name = "WearPiece_" .. c.id, color = if on then UIKit.color("plate_light") else UIKit.color("button_ok") })
		b.ZIndex = 4
	end
end

local function buildTitles(body: Frame, v: Types.ClientView, x0: number, W: number, H: number)
	local list = UIKit.scroll(body, UDim2.fromOffset(W - x0, H - 16), UDim2.fromOffset(x0, 16))
	list.Name = "List"
	UIKit.vlist(list, 2)
	local RW = W - x0
	local earned: { Titles.Title } = {}
	local locked: { Titles.Title } = {}
	for _, t in Titles.list do
		if v.titles and v.titles[t.id] then
			table.insert(earned, t)
		else
			table.insert(locked, t)
		end
	end
	local order = 0
	-- (none: no title over their head)
	order += 1
	local nf = row(list, order, 16, "Title_none")
	UIKit.text(nf, "No title", UDim2.fromOffset(RW - 70, 10), UDim2.fromOffset(5, 3), { color = UIKit.color("text_dim"), z = 4 })
	local noneOn = (v.title or "") == ""
	UIKit.button(nf, if noneOn then "Worn" else "Wear", UDim2.fromOffset(46, 12), UDim2.new(1, -49, 0, 2), function()
		local res = StateClient.request("title.set", { id = "" })
		if res.ok then
			Audio.play("flip")
		end
	end, { name = "WearTitle_none", color = if noneOn then UIKit.color("plate_light") else UIKit.color("button_ok"), enabled = not noneOn }).ZIndex = 4
	for _, t in earned do
		order += 1
		local f = row(list, order, 24, "Title_" .. t.id)
		UIKit.text(f, t.name, UDim2.fromOffset(RW - 70, 10), UDim2.fromOffset(5, 2), { color = UIKit.color(t.color), z = 4, name = "Name" })
		UIKit.text(f, howWords(t), UDim2.fromOffset(RW - 62, 10), UDim2.fromOffset(5, 12), { color = UIKit.color("text_dim"), z = 4 })
		local on = v.title == t.id
		UIKit.button(f, if on then "Worn" else "Wear", UDim2.fromOffset(46, 12), UDim2.new(1, -49, 0, 6), function()
			local res = StateClient.request("title.set", { id = t.id })
			if res.ok then
				Audio.play("flip")
				UIKit.notice("Your title is " .. t.name .. " now.", UIKit.color("good"))
			else
				Audio.play("deny")
				UIKit.notice(Words.errText(res.err), UIKit.color("bad"))
			end
		end, { name = "WearTitle_" .. t.id, color = if on then UIKit.color("plate_light") else UIKit.color("button_ok"), enabled = not on }).ZIndex = 4
	end
	for _, t in locked do
		order += 1
		local f = UIKit.row(list, UDim2.new(1, -6, 0, 24), nil, nil, 0.93)
		f.Name = "Locked_" .. t.id
		f.LayoutOrder = order
		UIKit.text(f, t.name, UDim2.fromOffset(RW - 20, 10), UDim2.fromOffset(5, 2), { color = UIKit.color("text_dim"), z = 4, name = "Name" })
		UIKit.text(f, howWords(t), UDim2.fromOffset(RW - 20, 10), UDim2.fromOffset(5, 12), { color = UIKit.color("text_dim"), z = 4 })
	end
end

local function buildLooks(body: Frame, arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	if arg == "pieces" or arg == "titles" then
		looksTab = arg
	end
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	-- the colours being tried, with the pieces worn now
	local d: Types.Look = draft or { skin = v.founder.skin, hair = v.founder.hair, style = v.founder.style, shirt = v.founder.shirt }
	draft = d
	local shown = table.clone(v.founder)
	shown.skin, shown.hair, shown.style, shown.shirt = d.skin, d.hair, d.style, d.shirt
	UIKit.portrait(body, shown, 48, UDim2.fromOffset(2, 2))
	local title = Titles.byId[v.title or ""]
	if title then
		UIKit.text(body, title.name, UDim2.fromOffset(52, 10), UDim2.fromOffset(0, 52), { x = "center", color = UIKit.color(title.color), name = "WornTitle" })
	end
	local LX = 54
	for i, r in LOOK_ROWS do
		local y = (i - 1) * 15
		UIKit.text(body, r.label, UDim2.fromOffset(32, 12), UDim2.fromOffset(LX, y), { color = UIKit.color("text") })
		local function step(delta: number)
			local cur = (d :: any)[r.key] :: number
			;(d :: any)[r.key] = (cur - 1 + delta) % r.n + 1
			Audio.play("flip")
			UIKit.refreshPanel()
		end
		UIKit.button(body, "<", UDim2.fromOffset(13, 12), UDim2.fromOffset(LX + 32, y), function()
			step(-1)
		end, { name = "Prev_" .. r.key, color = UIKit.color("plate_light") })
		UIKit.text(body, string.format("%d/%d", (d :: any)[r.key], r.n), UDim2.fromOffset(30, 12), UDim2.fromOffset(LX + 46, y), { x = "center", color = UIKit.color("text_dim") })
		UIKit.button(body, ">", UDim2.fromOffset(13, 12), UDim2.fromOffset(LX + 77, y), function()
			step(1)
		end, { name = "Next_" .. r.key, color = UIKit.color("plate_light") })
	end
	UIKit.button(body, "Save look", UDim2.fromOffset(90, 14), UDim2.fromOffset(LX, 62), function()
		local res = StateClient.request("founder.set", { skin = d.skin, hair = d.hair, style = d.style, shirt = d.shirt })
		if res.ok then
			Audio.play("reward")
			UIKit.notice("Looking good!", UIKit.color("good"))
		else
			Audio.play("deny")
			UIKit.notice(Words.errText(res.err), UIKit.color("bad"))
		end
	end, { name = "SaveLook", color = UIKit.color("button_ok") })
	-- how many pieces they own, and the Store's shop
	local n = 0
	local owned: { [string]: boolean } = v.owned or {}
	for _ in owned do
		n += 1
	end
	UIKit.text(body, string.format("%d of %d pieces", n, #Cosmetics.list), UDim2.fromOffset(150, 10), UDim2.fromOffset(0, 82), { color = UIKit.color("text_dim"), name = "PieceCount" })
	UIKit.button(body, "Shop for more", UDim2.fromOffset(90, 13), UDim2.fromOffset(0, 94), function()
		UIKit.openPanel("store", "shop")
	end, { name = "LooksShop", color = UIKit.color("button_warn") })
	-- the right side: pieces or titles
	local x0 = 152
	local x = x0
	for _, t in { { id = "pieces", text = "Pieces" }, { id = "titles", text = "Titles" } } do
		local w = UIKit.buttonWidth(t.text, 5)
		local on = looksTab == t.id
		UIKit.button(body, t.text, UDim2.fromOffset(w, 13), UDim2.fromOffset(x, 0), function()
			if looksTab ~= t.id then
				looksTab = t.id
				Audio.play("flip")
				UIKit.refreshPanel()
			end
		end, { name = "LooksTab_" .. t.id, color = if on then UIKit.color("button") else UIKit.color("plate_light") }).ZIndex = 4
		x += w + 2
	end
	if looksTab == "titles" then
		buildTitles(body, v, x0, W, H)
	else
		buildPieces(body, v, x0, W, H)
	end
end

------------------------------------------------------------------ the HUD's offers
-- What the offers show now (Hud rebuilds them when it changes).
function StoreUI.offerKey(v: Types.ClientView): string
	local starter = not (v.gifts and v.gifts.starter)
	return string.format("%s|%s", if starter then "s" else "", if vipWaiting(v) then "v" else "")
end

-- The offers' column (nil: none to show): the Starter Pack until bought (opens the Store's Eggs tab), VIP's gift on a
-- day it waits (claims it).
function StoreUI.offers(parent: Instance, v: Types.ClientView, w: number): Frame?
	local list: { { name: string, text: string, sub: string, icon: string, color: Color3, go: () -> () } } = {}
	if not (v.gifts and v.gifts.starter) then
		table.insert(list, { name = "Offer_StarterPack", text = "Starter Pack", sub = robuxText("StarterPack"), icon = "mini_gift", color = UIKit.color("accent"), go = function()
			UIKit.openPanel("store", "eggs")
		end })
	end
	if vipWaiting(v) then
		table.insert(list, { name = "Offer_VipGift", text = "VIP gift", sub = "Ready", icon = "mini_crown", color = UIKit.color("accent"), go = claimVip })
	end
	if #list == 0 then
		return nil
	end
	local H = 14
	local f = Instance.new("Frame")
	f.Name = "Offers"
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromOffset(w, #list * (H + 2) - 2)
	f.Parent = parent
	for i, o in list do
		local g = UIKit.glass(f, UDim2.fromOffset(w, H), UDim2.fromOffset(0, (i - 1) * (H + 2)), 2)
		g.Name = o.name
		local b = UIKit.button(g, "", UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), o.go, { name = o.name .. "_Go", ghost = true })
		b.ZIndex = 3
		PixelSprites.image(g, o.icon, UDim2.fromOffset(2, 1), 4)
		UIKit.text(g, o.text, UDim2.fromOffset(w - 16, 10), UDim2.fromOffset(15, 2), { color = o.color, z = 4, name = "Text" })
		-- (its price or state on the right, when both fit: a phone's column is narrower)
		if UIKit.textWidth(o.text) + UIKit.textWidth(o.sub) + 24 <= w then
			UIKit.text(g, o.sub, UDim2.fromOffset(w - 18, 10), UDim2.fromOffset(15, 2), { x = "right", color = UIKit.color("text"), z = 4, name = "Sub" })
		end
	end
	return f
end

------------------------------------------------------------------ init
local PASS_THANKS: { [string]: string } = {
	VIP = "Thanks! VIP is on: 25% more shells and a gift every day.",
	DoubleIncome = "Thanks! Every shell counts twice now.",
	QuickTree = "Thanks! The Tree of Life lays every 5 minutes now.",
	FreeDecor = "Thanks! Decor, paths, water and fences are free now.",
	PremiumTrack = "Thanks! The premium side of the track is open.",
}

function StoreUI.init()
	UIKit.registerPanel("store", { title = "Store", icon = "store", w = 380, h = 210, build = buildStore })
	UIKit.registerPanel("looks", { title = "Looks", icon = "visitor", w = 360, h = 200, build = buildLooks })
	UIKit.PanelChanged:Connect(function(name: string?)
		if name ~= "looks" then
			draft = nil
		end
	end)
	StateClient.Fx:Connect(function(msg)
		if msg.kind == "pass" and msg.bought then
			Audio.play("reward")
			UIKit.notice(PASS_THANKS[tostring(msg.key)] or "Thanks! Your pass is on.", UIKit.color("good"), 4)
		elseif msg.kind == "rewards" and type(msg.given) == "table" then
			Audio.play("reward")
			UIKit.notice(StoreUI.rewardText(tostring(msg.from), msg.given), UIKit.color("accent"), 5)
		elseif msg.kind == "titles" and type(msg.ids) == "table" then
			for _, id in msg.ids do
				local t = Titles.byId[tostring(id)]
				if t and t.how ~= "start" then
					UIKit.notice("New title: " .. t.name .. ". Wear it from Looks.", UIKit.color(t.color), 4)
				end
			end
		end
	end)
end

-- (for the sims: what is sold and the tab open)
StoreUI.PASSES = PASSES
StoreUI.PRODUCTS = PRODUCTS
StoreUI.tabOf = function(): string
	return tab
end
return StoreUI
