-- tests/specs/EyeTex.spec.luau: the driftlings' painted eyes (Render/EyeTex): each part of an eye lies where it should
-- on the eyeball (the pupil in the middle, the iris round it, the white beyond, the dark rim at the edge), a cat's slit
-- is tall and a goat's bar wide, the catchlights glow, the lids cover what they should (a sleepy lid over the top, a
-- fierce one lower on the inner side, a shut eye all lid but its dark line), and edges are smoothed (a pixel on an edge
-- is part one colour, part the other).
local T = require("../TestKit")
local EyeTex = require("../../build/luautest/shared/Render/EyeTex")

local IRIS, DARK, LID, WHITE = 0x3060C0, 0x101018, 0xC09060, 0xF4F4F4
local S = EyeTex.STYLE

-- the colour covering most of the pixel at (u, v), and whether it glows
local function at(code: number, u: number, v: number, side: number?, ppu: number?): (number, number, boolean)
	local a1, l1, g1, a2, l2, g2, k = EyeTex.sample(code, u, v, side or 1, ppu or 40, IRIS, DARK, LID, WHITE)
	if k >= 0.5 then
		return a2, l2, g2
	end
	return a1, l1, g1
end

return function()
	T.it("every style of Data/Creatures has a painting, and a shut lid", function()
		for _, name in { "sparkle", "lashes", "button", "bead", "dot", "star", "heart", "round", "wide", "specs", "slit", "bar", "ringed", "sleepy", "fierce", "happy", "glow", "gem", "visor", "compound", "closed" } do
			T.truthy(S[name] ~= nil, name)
		end
	end)

	T.it("a cartoon eye: the pupil in the middle, the iris round it, the white beyond, the dark rim at its edge", function()
		T.eq((at(S.round, 0, -0.06)), DARK, "pupil")
		T.eq((at(S.round, 0.36, -0.06)), IRIS, "iris")
		T.eq((at(S.round, 0.68, -0.3)), WHITE, "white")
		T.eq((at(S.round, 0.89, 0)), DARK, "rim")
		local _, _, glow = at(S.round, -0.2, 0.18)
		T.truthy(glow, "a catchlight up toward the light glows")
	end)

	T.it("a cat's slit is tall and narrow, a goat's bar wide and low", function()
		T.eq((at(S.slit, 0, 0.5)), DARK, "the slit reaches up")
		T.eq((at(S.slit, 0.3, 0)), IRIS, "and is narrow")
		T.eq((at(S.bar, 0.45, 0)), DARK, "the bar reaches out")
		T.eq((at(S.bar, 0, 0.3)), IRIS, "and is low")
	end)

	T.it("the dark eye of a cute creature: dark, the iris low in it, a glowing catchlight up toward the light", function()
		T.eq((at(S.sparkle, 0, 0.5)), DARK, "dark over the top")
		T.eq((at(S.sparkle, 0, -0.6)), IRIS, "the iris low")
		local _, _, glow = at(S.sparkle, -0.3, 0.32)
		T.truthy(glow, "catchlight")
	end)

	T.it("lids: a sleepy one over the top, a fierce one lower on the inner side, a shut eye all lid but its line", function()
		T.eq((at(S.sleepy, 0, 0.6)), LID, "sleepy lid over the top")
		T.eq((at(S.sleepy, 0, -0.5)) ~= LID, true, "the eye below it")
		-- (the right eye's inner side is toward -u)
		T.eq((at(S.fierce, -0.6, 0.35, 1)), LID, "lower on the inner side")
		T.eq((at(S.fierce, 0.6, 0.35, 1)) ~= LID, true, "open on the outer side")
		T.eq((at(S.fierce, 0.6, 0.35, -1)), LID, "the left eye's inner side is +u")
		T.eq((at(S.closed, 0, 0.5)), LID, "a shut eye is lid")
		T.eq((at(S.closed, 0, -0.28)), DARK, "with its dark line across")
		T.eq((at(S.happy, 0, 0.32)), DARK, "a happy one's arch bows up")
		T.eq((at(S.happy, 0, -0.5)), LID, "lid under the arch")
	end)

	T.it("edges are smoothed: on the pupil's edge a pixel is part dark, part iris", function()
		-- (the round eye's pupil, radius 0.24 about (0, -0.06); at 10 pixels a unit its edge is a pixel or so wide)
		local _, _, _, a2, _, _, k = EyeTex.sample(S.round, 0.239, -0.06, 1, 10, IRIS, DARK, LID, WHITE)
		T.truthy(k > 0.2 and k < 0.8, "partly covered: " .. k)
		T.truthy(a2 == DARK or a2 == IRIS, "between the pupil and the iris")
	end)

	T.it("a tiny eye keeps its main colour and one catchlight", function()
		T.eq((at(S.round, 0.36, -0.06, 1, 2)), IRIS, "still the iris")
		local _, _, glow = at(S.button, -0.3, 0.32, 1, 2)
		T.truthy(glow, "and a catchlight")
	end)
end
