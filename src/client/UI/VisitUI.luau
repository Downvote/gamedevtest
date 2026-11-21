--!strict
-- The Visit panel (GAME_DESIGN 8): the islands float apart in the sky since the request of 2026-11-20 ("Never mind,
-- make it a floating island instead, with a 2d skybox. Expanding makes the island bigger."), so nobody walks or swims
-- over to a neighbour any more; the HUD's Visit button (beside the top bar while the founder is home) opens a list of
-- the other islands on the server, each with its name, its owner and its tier's name, and a Visit button that takes
-- the founder there (char.visit), in front of its Tree of Life. Home brings them back.
-- Both go behind the loading card (the request of 2026-11-21: "make a loading screen when visiting other player
-- islands"): it covers the screen, the founder goes over, the other island's picture is drawn (the view jumps and the
-- pixel filter bakes it afresh), and the card opens on it. Its title is the island's name, its line "Flying over" (or
-- "Flying home"), then "Drawing the island" (or "Drawing your island") while the picture is drawn.
--   VisitUI.init(), VisitUI.islands() -> { { plot, name, owner, tier } } (the islands listed: the HUD and the sims)
--   VisitUI.travel(plot?)   over to that island, or home with nil, behind the card (Visit's buttons, the HUD's Home)
--   VisitUI.busy() -> boolean   a trip under way
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Street = require(ReplicatedStorage.Shared.Data.Street)
local Office = require(ReplicatedStorage.Shared.Data.Office)
local Lang = require(ReplicatedStorage.Shared.Locale.Lang)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.UIKit)
local LoadingCard = require(game:GetService("ReplicatedFirst").Loading.LoadingCard)

local VisitUI = {}

local PAD = 6
local ROW_H = 26
local MAX_ROWS = Street.MAX - 1

export type Isle = { plot: number, name: string, owner: string, tier: number }

-- The other players' islands now, by plot (Plot_<i>'s attributes: Owner, OwnerName, StudioName, Tier).
function VisitUI.islands(): { Isle }
	local out: { Isle } = {}
	local v = StateClient.view()
	local mine = if v then v.plot else 0
	local plots = workspace:FindFirstChild("Plots")
	if plots == nil then
		return out
	end
	for i = 1, Street.MAX do
		local m = plots:FindFirstChild("Plot_" .. i)
		local owner = if m then m:GetAttribute("Owner") else nil
		if i ~= mine and m and type(owner) == "number" and owner ~= 0 then
			local name = m:GetAttribute("StudioName")
			local who = m:GetAttribute("OwnerName")
			local tier = m:GetAttribute("Tier")
			table.insert(out, {
				plot = i,
				name = if type(name) == "string" then name else "An island",
				owner = if type(who) == "string" then who else "",
				tier = if type(tier) == "number" then tier else 1,
			})
		end
	end
	return out
end

local traveling = false

-- An island's name as its plot says (Plot_<i>'s StudioName), or "An island".
local function nameOf(plot: number): string
	local plots = workspace:FindFirstChild("Plots")
	local m = if plots then plots:FindFirstChild("Plot_" .. plot) else nil
	local n = if m then m:GetAttribute("StudioName") else nil
	return if type(n) == "string" and n ~= "" then n else Lang.t("An island")
end

-- Whether the founder stands on that plot now (the server has moved them and it has reached this client).
local function standsOn(plot: number): boolean
	local char = Players.LocalPlayer.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return false
	end
	return Street.plotAt(root.Position.X, root.Position.Z) == plot
end

local function failed(err: string?, home: boolean)
	if err == "cooldown" then
		UIKit.notice("Wait a moment, then try again.", UIKit.color("bad"))
	elseif home then
		UIKit.notice("Can't go home right now.", UIKit.color("bad"))
	else
		UIKit.notice("That island isn't there any more.", UIKit.color("bad"))
	end
end

function VisitUI.busy(): boolean
	return traveling
end

-- Over to island `plot`, or home (nil), behind the loading card: the card covers the screen, the server moves the
-- founder, the card waits until they stand there and the pixel filter has drawn the island (it bakes the picture
-- afresh once the view jumps), then opens on it. With no card (one already up) the founder simply goes.
function VisitUI.travel(plot: number?)
	if traveling then
		return
	end
	local v = StateClient.view()
	local home = plot == nil
	local target = plot or (if v then v.plot else 0)
	local function ask(): any
		return if home then StateClient.request("char.home", {}) else StateClient.request("char.visit", { plot = plot })
	end
	UIKit.closePanel()
	traveling = true
	local up = LoadingCard.cover({
		title = nameOf(target),
		status = Lang.t(if home then "Flying home" else "Flying over"),
		onCovered = function()
			-- (nobody sees the game now: the filter may take more of each frame)
			PixelRenderer.setHidden(true)
			local res = ask()
			if not res.ok then
				PixelRenderer.setHidden(false)
				LoadingCard.finish()
				failed(res.err, home)
				return
			end
			LoadingCard.progress(0.3)
			-- the founder over there, then the island's picture: a few frames for the view to jump and the filter to
			-- start its bake, then until it has nothing left to draw
			local t0 = os.clock()
			while not standsOn(target) and os.clock() - t0 < 4 do
				task.wait(0.05)
			end
			LoadingCard.progress(0.5)
			LoadingCard.status(Lang.t(if home then "Drawing your island" else "Drawing the island"))
			task.wait(0.2)
			local t1 = os.clock()
			while PixelRenderer.busy() and os.clock() - t1 < 8 do
				LoadingCard.progress(0.5 + 0.45 * math.min(1, (os.clock() - t1) / 3))
				task.wait(0.05)
			end
			PixelRenderer.setHidden(false)
			LoadingCard.finish()
		end,
		onOpened = function()
			traveling = false
		end,
	})
	if not up then
		local res = ask()
		traveling = false
		if not res.ok then
			failed(res.err, home)
		end
	end
end

local function go(plot: number)
	VisitUI.travel(plot)
end

local function build(body: Frame, _arg: any?)
	local bw = body:GetAttribute("W")
	local w = if type(bw) == "number" then bw else 228
	local list = VisitUI.islands()
	if #list == 0 then
		UIKit.text(body, "Nobody else is here yet.", UDim2.fromOffset(w - 2 * PAD, 12), UDim2.fromOffset(PAD, 8), { color = UIKit.color("text_dim"), name = "Empty" })
		return
	end
	local y = 4
	for _, isle in list do
		local bwid = UIKit.buttonWidth("Visit", 6)
		local tw = w - 2 * PAD - bwid - 4
		UIKit.text(body, isle.name, UDim2.fromOffset(tw, 12), UDim2.fromOffset(PAD, y), { color = UIKit.color("text"), name = "Name_" .. isle.plot })
		local sub = Office.plan(isle.tier).name
		if isle.owner ~= "" then
			sub = isle.owner .. " · " .. sub
		end
		UIKit.text(body, sub, UDim2.fromOffset(tw, 10), UDim2.fromOffset(PAD, y + 12), { color = UIKit.color("text_dim"), name = "Sub_" .. isle.plot })
		UIKit.button(body, "Visit", UDim2.fromOffset(bwid, 16), UDim2.fromOffset(w - PAD - bwid, y + 3), function()
			go(isle.plot)
		end, { name = "Visit_" .. isle.plot, color = UIKit.color("button") })
		y += ROW_H
	end
end

local function heightFor(_pw: number): number
	local n = math.max(1, math.min(MAX_ROWS, #VisitUI.islands()))
	return 8 + n * ROW_H + 20
end

function VisitUI.init()
	UIKit.registerPanel("visit", { title = "Visit", icon = "visitor", w = 220, hFor = heightFor, build = build })
end

return VisitUI
