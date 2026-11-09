--!strict
-- The game on sale's graph (GAME_DESIGN 6; docs/ARCHITECTURE.md 10.9), Game Dev Tycoon style: its players every
-- Tuning.LiveSampleSec as columns of whole UI px, the whole life wide (the days still to come a dotted floor), the
-- newest column lit, the peak marked; it fills in as the game sells. The HUD's sales card and the Games panel draw it,
-- each at its own size (a smaller graph is drawn again at its size, never scaled: the pixel art rules).
--   SalesGraph.new(parent, w, h, z) -> Graph;  graph.set(live)  (the client's view of Profile.live)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local UIKit = require(script.Parent.UIKit)

local SalesGraph = {}

export type Graph = { frame: Frame, set: (live: Types.Live?) -> () }

local SLOTS = math.floor(Tuning.LiveLife / Tuning.LiveSampleSec) + 1

function SalesGraph.new(parent: Instance, w: number, h: number, z: number): Graph
	local f = UIKit.rect(parent, UDim2.fromOffset(w, h), nil, UIKit.color("ink"), z)
	f.Name = "SalesGraph"
	local inner = UIKit.rect(f, UDim2.fromOffset(w - 2, h - 2), UDim2.fromOffset(1, 1), UIKit.hex(0x2B2238), z)
	inner.Name = "Back"
	local gw, gh = w - 2, h - 2
	-- a faint grid line at half height
	for x = 0, gw - 1, 3 do
		UIKit.rect(inner, UDim2.fromOffset(1, 1), UDim2.fromOffset(x, math.floor(gh / 2)), UIKit.hex(0x3B3048), z).Name = "Grid"
	end
	-- one column per UI px; a column shows the most players among the samples that fall in it
	local cols: { Frame } = {}
	local tops: { Frame } = {}
	for x = 0, gw - 1 do
		local c = UIKit.rect(inner, UDim2.fromOffset(1, 0), UDim2.fromOffset(x, gh), UIKit.color("good"), z)
		c.Name = "Col"
		c.Visible = false
		cols[x + 1] = c
		local tp = UIKit.rect(inner, UDim2.fromOffset(1, 1), UDim2.fromOffset(x, gh - 1), UIKit.color("good"):Lerp(UIKit.color("white"), 0.45), z)
		tp.Name = "Top"
		tp.Visible = false
		tops[x + 1] = tp
	end
	local floorDots: { Frame } = {}
	for x = 0, gw - 1, 2 do
		local d = UIKit.rect(inner, UDim2.fromOffset(1, 1), UDim2.fromOffset(x, gh - 1), UIKit.color("text_dim"), z)
		d.Name = "Floor"
		floorDots[x // 2 + 1] = d
	end
	local peakMark = UIKit.rect(inner, UDim2.fromOffset(3, 1), UDim2.fromOffset(0, 0), UIKit.color("accent"), z)
	peakMark.Name = "Peak"
	peakMark.Visible = false
	local g: Graph
	g = {
		frame = f,
		set = function(live: Types.Live?)
			if live == nil then
				for _, c in cols do
					c.Visible = false
				end
				for _, t in tops do
					t.Visible = false
				end
				peakMark.Visible = false
				return
			end
			local samples = live.samples
			local scale = math.max(1, live.peak, live.top)
			local n = #samples
			local over = live.age >= live.life
			local peakX, peakH = -1, -1
			for x = 0, gw - 1 do
				-- the samples that fall in this column
				local s0 = math.floor(x * SLOTS / gw) + 1
				local s1 = math.max(s0, math.floor((x + 1) * SLOTS / gw))
				local v = -1
				for i = s0, math.min(s1, n) do
					v = math.max(v, samples[i])
				end
				local c, tp = cols[x + 1], tops[x + 1]
				if v >= 0 then
					local ch = math.clamp(math.floor(v / scale * (gh - 2) + 0.5), if v > 0 then 1 else 0, gh - 1)
					c.Size = UDim2.fromOffset(1, ch)
					c.Position = UDim2.fromOffset(x, gh - ch)
					local newest = s1 >= n and s0 <= n and not over
					c.BackgroundColor3 = if newest then UIKit.color("white") elseif over then UIKit.color("text_dim") else UIKit.color("good")
					c.Visible = ch > 0
					tp.Position = UDim2.fromOffset(x, gh - ch)
					tp.Visible = ch > 1 and not newest and not over
					if ch > peakH then
						peakX, peakH = x, ch
					end
				else
					c.Visible = false
					tp.Visible = false
				end
			end
			-- the floor's dots only where the days are still to come
			local filled = math.floor(math.min(n, SLOTS) * gw / SLOTS)
			for i, d in floorDots do
				d.Visible = (i - 1) * 2 >= filled
			end
			if peakX >= 0 and peakH > 0 then
				peakMark.Position = UDim2.fromOffset(math.clamp(peakX - 1, 0, gw - 3), math.max(0, gh - peakH - 2))
				peakMark.Visible = true
			else
				peakMark.Visible = false
			end
		end,
	}
	return g
end

return SalesGraph
