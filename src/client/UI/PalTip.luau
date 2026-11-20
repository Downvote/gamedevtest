--!strict
-- What a driftling's numbers mean (GAME_DESIGN 6; docs/ARCHITECTURE.md 10.5). The request of 2026-11-15: "when
-- hovering or holding onto each creature, show what their mutation and stats do". A row of a panel that shows one
-- driftling (the Driftlings panel, the tree's swap list, the Hatchery's parent picker, the hut picker's swaps) gets a
-- tip: with a mouse while the pointer is over it, on a phone while a finger holds it (HOLD_SECS). The tip, a glass card
-- on the Popup root next to the pointer (above the finger), says: its name and rarity; how fast it works (its rarity's
-- RarityWork times its passive and mutations: Tree.worth; the same at every workplace since 2026-11-19); its passive
-- and what it does; each mutation with its stars and what it does; when any of them counts for the whole island (egg
-- luck, egg cost, Hatchery time, boost buildings, charm and the wondrous ones: Data/Traits.ISLE), that it does while
-- the driftling lives in a hut; and what it sells for.
--   PalTip.attach(target, pal)   hover and hold on a GuiObject show the tip for that driftling
--   PalTip.show(pal, at), PalTip.hide()   at: a point on the Popup canvas (UI px)
--   PalTip.lines(pal) -> { { text, color, tier? } }   the tip's lines (sims and previews)
--   PalTip.debugState() -> { shown, texts }
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Creatures = require(ReplicatedStorage.Shared.Data.Creatures)
local Traits = require(ReplicatedStorage.Shared.Data.Traits)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local Tree = require(ReplicatedStorage.Shared.Logic.Tree)
local Lang = require(ReplicatedStorage.Shared.Locale.Lang)
local UIKit = require(script.Parent.UIKit)
local TierStars = require(script.Parent.TierStars)

local PalTip = {}

local TIP_W = 190 -- the widest a tip's words run (UI px)
local HOLD_SECS = 0.35 -- a finger held this long on a row shows its tip
-- what counts for the whole island, in the order it is named
local ISLAND_ORDER = { "luck", "cost", "hatch", "boost", "charm", "charmPct", "all", "aura", "eggs", "skip", "away" }
local ISLAND_KEYS: { [string]: string } = {
	luck = "egg luck",
	cost = "egg price",
	hatch = "Hatchery speed",
	boost = "boost",
	charm = "charm",
	charmPct = "charm share",
	all = "coins share",
	aura = "work for all",
	eggs = "extra eggs",
	skip = "rarer hatches",
	away = "offline coins",
}

export type Line = { text: string, color: string, tier: number?, title: string? }

local tip: Frame? = nil
local owner: GuiObject? = nil
local shownTexts: { string } = {}

-- "x1.1": a work speed to a tenth.
local function times(w: number): string
	return string.format("x%.1f", w)
end

function PalTip.lines(pal: Types.Pal): { Line }
	local out: { Line } = {}
	local d = Creatures.byId[pal.sp]
	if d == nil then
		return out
	end
	local rar = Traits.RARITY[d.rarity] or Traits.RARITY[1]
	local muts = Traits.clean(pal.muts)
	local fx = Traits.sum(d.passive.fx, muts)
	local base = Tuning.RarityWork[d.rarity] or 1
	-- its work (the same at every workplace)
	table.insert(out, { text = d.name, color = rar.color, title = rar.name })
	table.insert(out, { text = string.format("Works %s anywhere", times(base * (1 + Traits.work(fx)))), color = "text" })
	table.insert(out, { text = string.format("%s base speed %s", rar.name, times(base)), color = "text_dim" })
	table.insert(out, { text = Lang.f("{1}: {2}@@pair", Lang.t(d.passive.name), Lang.t(Traits.describe(d.passive.fx))), color = "accent" })
	local island: { [string]: boolean } = {}
	for k in d.passive.fx do
		if ISLAND_KEYS[k] then
			island[k] = true
		end
	end
	if #muts == 0 then
		table.insert(out, { text = "No mutations", color = "text_dim" })
	end
	for _, id in muts do
		local m = Traits.byId[id]
		if m then
			table.insert(out, { text = m.name, color = Traits.TIER_COLOR[m.tier] or "text", tier = m.tier, title = Traits.describe(m.fx) })
			for k in m.fx do
				if ISLAND_KEYS[k] then
					island[k] = true
				end
			end
		end
	end
	-- (what counts for the whole island, named: "Its egg luck counts while it lives in a hut")
	local names: { string } = {}
	for _, k in ISLAND_ORDER do
		if island[k] and table.find(names, ISLAND_KEYS[k]) == nil then
			table.insert(names, ISLAND_KEYS[k])
		end
	end
	if #names > 0 then
		-- (each name in the player's language, the list joined with the language's own "and", then a whole sentence for
		-- one and for many: Locale/Lang)
		local shown: { string } = {}
		for i, nm in names do
			shown[i] = Lang.t(nm)
		end
		local said = if #shown == 1 then shown[1] else table.concat(shown, ", ", 1, #shown - 1) .. Lang.t(" and ") .. shown[#shown]
		table.insert(out, { text = Lang.f(if #names == 1 then "Its {1} counts while in a hut" else "Its {1} count while in a hut", said), color = "text_dim" })
	end
	table.insert(out, { text = "Sells for " .. Numbers.coins(Tree.price(pal)) .. " coins", color = "text_dim" })
	return out
end

-- The tip's card for driftling pal (made once each time it shows).
local function build(pal: Types.Pal): Frame
	local lines = PalTip.lines(pal)
	-- (the widest line, the card no wider than TIP_W; a long one wraps)
	local w = 0
	for _, l in lines do
		local lw: number
		if l.tier then
			lw = TierStars.measure(l.text, l.tier, ":") + 4 + UIKit.textWidth(l.title or "")
		elseif l.title then
			lw = UIKit.textWidth(l.text) + 6 + UIKit.textWidth(l.title)
		else
			lw = UIKit.textWidth(l.text)
		end
		w = math.max(w, lw)
	end
	w = math.min(TIP_W, w)
	local f = UIKit.glass(UIKit.canvas("Popup"), UDim2.fromOffset(w + 2 * UIKit.PAD, 10), nil, 2)
	-- (solid: it sits over a panel's words)
	UIKit.setPlate(f, nil, 0)
	f.Name = "PalTip"
	f.ZIndex = 30
	local y = 3
	table.clear(shownTexts)
	for i, l in lines do
		local x = UIKit.PAD
		if l.tier then
			-- a mutation: its name and stars, then what it does (on the next line when it doesn't fit)
			local _, nw = TierStars.label(f, l.text, l.tier, x, y, { z = 31, name = "Mut_" .. i, suffix = ":" })
			local eff = l.title or ""
			if nw + 4 + UIKit.textWidth(eff) <= w then
				UIKit.text(f, eff, UDim2.fromOffset(w - nw - 4, 10), UDim2.fromOffset(x + nw + 4, y), { color = UIKit.color("text"), z = 31, name = "Eff_" .. i })
			else
				y += 10
				local n = math.clamp(UIKit.lines(eff, w - 8), 1, 3)
				UIKit.text(f, eff, UDim2.fromOffset(w - 8, 10 * n), UDim2.fromOffset(x + 8, y), { color = UIKit.color("text"), z = 31, name = "Eff_" .. i, wrap = n > 1, y = "top" })
				y += 10 * (n - 1)
			end
			table.insert(shownTexts, l.text .. ": " .. eff)
		elseif l.title then
			-- the name in its rarity's colour, the rarity after it
			local nw = UIKit.textWidth(l.text)
			UIKit.text(f, l.text, UDim2.fromOffset(nw + 2, 10), UDim2.fromOffset(x, y), { color = UIKit.color(l.color), z = 31, name = "Name" })
			UIKit.text(f, l.title, UDim2.fromOffset(math.max(10, w - nw - 6), 10), UDim2.fromOffset(x + nw + 6, y), { color = UIKit.color(l.color), z = 31, name = "Rarity" })
			table.insert(shownTexts, l.text .. " " .. l.title)
		else
			local n = math.clamp(UIKit.lines(l.text, w), 1, 3)
			UIKit.text(f, l.text, UDim2.fromOffset(w, 10 * n), UDim2.fromOffset(x, y), { color = UIKit.color(l.color), z = 31, name = "Line_" .. i, wrap = n > 1, y = "top" })
			y += 10 * (n - 1)
			table.insert(shownTexts, l.text)
		end
		y += 10
		-- (a little room under the name)
		if i == 1 then
			y += 2
		end
	end
	f.Size = UDim2.fromOffset(w + 2 * UIKit.PAD, y + 3)
	return f
end

-- Puts the tip near point `at` (Popup canvas px): right of and below a pointer, above a finger; kept on the screen.
local function placeAt(f: Frame, at: Vector2, touch: boolean)
	local size = UIKit.size("Popup")
	local w, h = f.Size.X.Offset, f.Size.Y.Offset
	local x = if touch then at.X - math.floor(w / 2) else at.X + 8
	local y = if touch then at.Y - h - 14 else at.Y + 10
	if not touch and y + h > size.Y - 2 then
		y = at.Y - h - 4
	end
	f.Position = UDim2.fromOffset(math.clamp(x, 2, math.max(2, size.X - w - 2)), math.clamp(y, 2, math.max(2, size.Y - h - 2)))
end

-- An input's point on the Popup canvas (an InputObject's Position is under the top bar's inset; the canvas starts at
-- its own origin, in UI px).
local function canvasPoint(pos: Vector3 | Vector2): Vector2
	local inset = GuiService:GetGuiInset()
	local o = UIKit.canvasOrigin("Popup")
	local k = UIKit.P()
	return Vector2.new(math.floor((pos.X + inset.X - o.X) / k), math.floor((pos.Y + inset.Y - o.Y) / k))
end

function PalTip.show(pal: Types.Pal, at: Vector2, touch: boolean?)
	PalTip.hide()
	local f = build(pal)
	placeAt(f, at, touch == true)
	tip = f
end

function PalTip.hide()
	local f = tip
	if f then
		f:Destroy()
	end
	tip, owner = nil, nil
	table.clear(shownTexts)
end

-- Hover (a mouse over target) and hold (a finger on it HOLD_SECS) show pal's tip; leaving, lifting the finger or the
-- row going away hides it.
function PalTip.attach(target: GuiObject, pal: Types.Pal)
	local holding = 0
	target.MouseEnter:Connect(function()
		if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
			return
		end
		-- (the pointer from the screen's very top: no inset to add)
		local ok, m = pcall(function(): Vector2
			return UserInputService:GetMouseLocation()
		end)
		local o, k = UIKit.canvasOrigin("Popup"), UIKit.P()
		local at = if ok then Vector2.new(math.floor((m.X - o.X) / k), math.floor((m.Y - o.Y) / k)) else Vector2.new(target.AbsolutePosition.X // k, target.AbsolutePosition.Y // k)
		PalTip.show(pal, at, false)
		owner = target
	end)
	target.MouseLeave:Connect(function()
		if owner == target then
			PalTip.hide()
		end
	end)
	target.InputChanged:Connect(function(input: InputObject)
		local f = tip
		if owner == target and f and input.UserInputType == Enum.UserInputType.MouseMovement then
			placeAt(f, canvasPoint(input.Position), false)
		end
	end)
	target.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		holding += 1
		local mine = holding
		task.delay(HOLD_SECS, function()
			if holding == mine and target.Parent ~= nil then
				PalTip.show(pal, canvasPoint(input.Position), true)
				owner = target
			end
		end)
	end)
	target.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			holding += 1
			if owner == target then
				PalTip.hide()
			end
		end
	end)
	target.Destroying:Connect(function()
		holding += 1
		if owner == target then
			PalTip.hide()
		end
	end)
end

-- Sims and previews: whether a tip shows, and its lines' words.
function PalTip.debugState(): { shown: boolean, texts: { string } }
	return { shown = tip ~= nil and tip.Parent ~= nil, texts = table.clone(shownTexts) }
end

return PalTip
