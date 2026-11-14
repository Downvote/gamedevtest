--!strict
-- Game passes and developer products (docs/ARCHITECTURE.md 7.7; GAME_DESIGN 14). Every id comes from
-- Config/Monetization; an id of 0 is not on sale: its pass is never checked and its product never resolved (no
-- MarketplaceService call is made with 0).
--   Passes: at every join each enabled pass is checked (UserOwnsGamePassAsync, in parallel); the answer goes into the
--   profile (Logic/Store.setPass: Profile.passes, VIP's welcome gift the first time). A failed check leaves what the
--   save had (a player keeps a pass through a Roblox hiccup). A pass bought here (PromptGamePassPurchaseFinished) is on
--   at once. The client hears of each (Fx "pass", and Fx "rewards" for VIP's gift).
--   Products: paid only in ProcessReceipt, once each: the purchase id is kept with the profile (Store.remember: the
--   last Store.RECEIPTS) and PurchaseGranted is answered only once the save holds it. A receipt Roblox sends again is
--   known and granted without paying twice; one for a player not here (left, still loading) waits for a later try.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Store = require(ReplicatedStorage.Shared.Logic.Store)
local Session = require(script.Parent.Session)
local DataService = require(script.Parent.DataService)
local WorldClock = require(script.Parent.WorldClock)

local MonetizationService = {}

local RECEIPT_WAIT = 10 -- seconds ProcessReceipt waits for the buyer's session to be ready

local productKeys: { [number]: string } = {} -- an enabled product's id -> its key
local passKeys: { [number]: string } = {} -- an enabled pass's id -> its key

-- A pass is owned now (found at the join, or bought). Its effects follow from the profile; the client hears of it.
local function applyPass(s: Session.S, key: string, bought: boolean)
	if Session.get(s.player) ~= s then
		return
	end
	local changed, gift = Store.setPass(s.profile, key, true)
	if changed or gift then
		Session.markDirty(s)
		Session.fx(s, { kind = "pass", key = key, bought = bought })
	end
	if gift then
		Session.fx(s, { kind = "rewards", from = key, given = gift })
	end
end

-- The join's checks (Main, once the session is ready): each enabled pass, in parallel.
function MonetizationService.join(s: Session.S)
	for key, id in Monetization.GamePasses do
		if Monetization.isEnabled(id) then
			task.spawn(function()
				local ok, owns = pcall(function(): boolean
					return MarketplaceService:UserOwnsGamePassAsync(s.player.UserId, id)
				end)
				if not ok then
					warn(string.format("[MonetizationService] couldn't check pass %s: %s", key, tostring(owns)))
					return
				end
				if owns then
					applyPass(s, key, false)
				elseif Session.get(s.player) == s and Store.owns(s.profile, key) then
					-- (the save said owned, Roblox says not: a refund)
					Store.setPass(s.profile, key, false)
					Session.markDirty(s)
				end
			end)
		end
	end
end

-- Pay product `key` to a ready session once (the sims call this the way ProcessReceipt does). Returns whether it was
-- paid (or had been) and whether the save holds it.
function MonetizationService.grant(s: Session.S, key: string, purchaseId: string): (boolean, boolean)
	local p = s.profile
	if Store.paid(p, purchaseId) then
		return true, true
	end
	local ok, data = Store.product(p, key, WorldClock.now())
	if not ok then
		return false, false
	end
	Store.remember(p, purchaseId)
	Session.markDirty(s)
	Session.fx(s, { kind = "rewards", from = key, given = data.given })
	local saved = DataService.save(s.player.UserId, p)
	return true, saved
end

local function processReceipt(info: { [string]: any }): Enum.ProductPurchaseDecision
	local NOT_YET = Enum.ProductPurchaseDecision.NotProcessedYet
	local key = productKeys[info.ProductId]
	if key == nil then
		warn("[MonetizationService] a receipt for an unknown product: " .. tostring(info.ProductId))
		return NOT_YET
	end
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if player == nil then
		return NOT_YET
	end
	local s = Session.get(player)
	local t = 0
	while (s == nil or not s.ready) and t < RECEIPT_WAIT and player.Parent ~= nil do
		task.wait(0.25)
		t += 0.25
		s = Session.get(player)
	end
	if s == nil or not s.ready then
		return NOT_YET
	end
	local paid, saved = MonetizationService.grant(s, key, tostring(info.PurchaseId))
	if paid and saved then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return NOT_YET
end

function MonetizationService.init()
	for key, id in Monetization.DevProducts do
		if Monetization.isEnabled(id) then
			productKeys[id] = key
		end
	end
	for key, id in Monetization.GamePasses do
		if Monetization.isEnabled(id) then
			passKeys[id] = key
		end
	end
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, bought: boolean)
		local key = passKeys[passId]
		local s = Session.get(player)
		if bought and key and s and s.ready then
			applyPass(s, key, true)
		end
	end)
end

return MonetizationService
