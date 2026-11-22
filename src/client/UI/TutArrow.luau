--!strict
-- The tips' arrow (the request of 2026-11-22: "for the tutorial, make an arrow pointing to whatever is required, like an
-- arrow pointing to the build button"): one yellow arrow (the "tut_" sprites) on the top canvas, bobbing toward the
-- button, tab or card a tip asks the player to press. UI/Hud picks what it points at every frame; the Tree of Life, a
-- thing in the world, has the same arrow over the world (Controllers/EggView, with TutArrow.bob and TutArrow.SIZE).
--   TutArrow.point(target, side, avoid)  point at a GUI object from one side of it ("above" pointing down, the
--                                 default; "below", "left", "right"), another side when it has no room there or would
--                                 cover one of `avoid` (the tip's banner); nil (or a target not on the screen: hidden,
--                                 scrolled out of its list) puts it away
--   TutArrow.bob(t): number       how far toward its target it is at time t (whole UI px)
--   TutArrow.debug(): { shown, dir, x, y, target }  previews
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)

local TutArrow = {}

-- the sprite pointing up or down, W x H (turned to point across it is H x W)
TutArrow.SIZE = Vector2.new(15, 17)

local arrow: GuiObject? = nil
local arrowDir = ""
local last = { shown = false, dir = "", x = 0, y = 0, target = "" }

function TutArrow.bob(t: number): number
	local k = (math.sin(t * 2 * math.pi * Tuning.TutArrowHz) + 1) / 2
	return math.floor(k * Tuning.TutArrowBobPx + 0.5)
end

local function hide()
	if arrow then
		arrow:Destroy()
		arrow = nil
		arrowDir = ""
	end
	last.shown = false
end

-- Whether GUI object g shows on the screen: it and every frame it sits in visible, its ScreenGui on, and its middle
-- inside every frame that clips it (a card scrolled out of the tray's list does not count).
local function onScreen(g: GuiObject): boolean
	if g.Parent == nil or g.AbsoluteSize.X < 1 or g.AbsoluteSize.Y < 1 then
		return false
	end
	local mid = g.AbsolutePosition + g.AbsoluteSize / 2
	local cur: Instance? = g
	while cur do
		if cur:IsA("GuiObject") then
			if not cur.Visible then
				return false
			end
			if cur ~= g and cur.ClipsDescendants then
				local p, sz = cur.AbsolutePosition, cur.AbsoluteSize
				if mid.X < p.X or mid.Y < p.Y or mid.X > p.X + sz.X or mid.Y > p.Y + sz.Y then
					return false
				end
			end
		elseif cur:IsA("ScreenGui") then
			return cur.Enabled
		end
		cur = cur.Parent
	end
	return false
end

-- A GUI object's box on the canvas (UI px, inclusive), k canvas px a screen px from the canvas's corner cp.
local function boxOf(g: GuiObject, cp: Vector2, k: number): (number, number, number, number)
	local x0 = math.floor((g.AbsolutePosition.X - cp.X) / k + 0.5)
	local y0 = math.floor((g.AbsolutePosition.Y - cp.Y) / k + 0.5)
	return x0, y0, x0 + math.floor(g.AbsoluteSize.X / k + 0.5) - 1, y0 + math.floor(g.AbsoluteSize.Y / k + 0.5) - 1
end

local ORDER = { "above", "right", "left", "below" }

function TutArrow.point(target: GuiObject?, side: string?, avoid: { GuiObject }?)
	if target == nil or not onScreen(target) then
		hide()
		return
	end
	local canvas = UIKit.canvas("Popup")
	local size = UIKit.size("Popup")
	if size.X <= 0 or canvas.AbsoluteSize.X <= 0 then
		hide()
		return
	end
	local k = canvas.AbsoluteSize.X / size.X
	local cp = canvas.AbsolutePosition
	local x0, y0, x1, y1 = boxOf(target, cp, k)
	local W, H = TutArrow.SIZE.X, TutArrow.SIZE.Y
	local gap = Tuning.TutArrowGap
	local reach = Tuning.TutArrowBobPx
	local midX, midY = math.floor((x0 + x1 + 1) / 2), math.floor((y0 + y1 + 1) / 2)
	-- where the arrow stands on a side, `off` px back from the target: its direction and box
	local function at(sd: string, off: number): (string, number, number, number, number)
		if sd == "below" then
			return "up", midX - math.floor(W / 2), y1 + 1 + gap + off, W, H
		elseif sd == "left" then
			return "right", x0 - gap - off - H, midY - math.floor(W / 2), H, W
		elseif sd == "right" then
			return "left", x1 + 1 + gap + off, midY - math.floor(W / 2), H, W
		end
		return "down", midX - math.floor(W / 2), y0 - gap - off - H, W, H
	end
	-- (the boxes of what it must not cover, the tip's banner with its words: those on the screen)
	local keep: { { number } } = {}
	local avoidList: { GuiObject } = avoid or {}
	for _, g in avoidList do
		if g ~= target and onScreen(g) then
			local a0, b0, a1, b1 = boxOf(g, cp, k)
			table.insert(keep, { a0, b0, a1, b1 })
		end
	end
	-- the side asked for, else the first side where it stays on the canvas and off what it must not cover all through
	-- its bob; else the first where it stays on the canvas
	local sides = { side or "above" }
	for _, sd in ORDER do
		if sd ~= sides[1] then
			table.insert(sides, sd)
		end
	end
	local pick, fallback = nil :: string?, nil :: string?
	for _, sd in sides do
		local _, ax, ay, aw, ah = at(sd, reach)
		local _, bx, by = at(sd, 0)
		local ux0, uy0 = math.min(ax, bx), math.min(ay, by)
		local ux1, uy1 = math.max(ax, bx) + aw - 1, math.max(ay, by) + ah - 1
		if ux0 >= 0 and uy0 >= 0 and ux1 <= size.X - 1 and uy1 <= size.Y - 1 then
			fallback = fallback or sd
			local clear = true
			for _, r in keep do
				if ux0 <= r[3] and ux1 >= r[1] and uy0 <= r[4] and uy1 >= r[2] then
					clear = false
					break
				end
			end
			if clear then
				pick = sd
				break
			end
		end
	end
	local chosen = pick or fallback or sides[1]
	-- (it bobs toward the target: furthest from it at the bob's rest)
	local dir, x, y = at(chosen, reach - TutArrow.bob(os.clock()))
	if arrow == nil or arrowDir ~= dir then
		if arrow then
			arrow:Destroy()
		end
		local a = PixelSprites.image(canvas, "tut_" .. dir, UDim2.fromOffset(0, 0), 40)
		a.Name = "TutArrow"
		arrow, arrowDir = a, dir
	end
	local a = arrow :: GuiObject
	local pos = UDim2.fromOffset(x, y)
	if a.Position ~= pos then
		a.Position = pos
	end
	last.shown, last.dir, last.x, last.y, last.target = true, dir, x, y, target.Name
end

function TutArrow.debug(): { shown: boolean, dir: string, x: number, y: number, target: string }
	return table.clone(last)
end

return TutArrow
