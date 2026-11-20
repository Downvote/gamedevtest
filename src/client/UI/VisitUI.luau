--!strict
-- The Visit panel (GAME_DESIGN 8): the islands float apart in the sky since the request of 2026-11-20 ("Never mind,
-- make it a floating island instead, with a 2d skybox. Expanding makes the island bigger."), so nobody walks or swims
-- over to a neighbour any more; the HUD's Visit button (beside the top bar while the founder is home) opens a list of
-- the other islands on the server, each with its name, its owner and its tier's name, and a Visit button that takes
-- the founder there (char.visit), in front of its Tree of Life. Home brings them back.
--   VisitUI.init(), VisitUI.islands() -> { { plot, name, owner, tier } } (the islands listed: the HUD and the sims)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Street = require(ReplicatedStorage.Shared.Data.Street)
local Office = require(ReplicatedStorage.Shared.Data.Office)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local UIKit = require(script.Parent.UIKit)

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

local function go(plot: number)
	local res = StateClient.request("char.visit", { plot = plot })
	if res.ok then
		UIKit.closePanel()
	elseif res.err == "cooldown" then
		UIKit.notice("Wait a moment, then try again.", UIKit.color("bad"))
	else
		UIKit.notice("That island isn't there any more.", UIKit.color("bad"))
	end
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
