-- tests/specs/DynTex.spec.luau: the driftlings' surface textures (Render/DynTex): every kind named and found, the
-- same answer for the same pixel, a step of at most one band, marks sparse enough to read as texture (never a fill),
-- a pattern measured in pixels (the same marks at any zoom), a part laid out flat round its own axis.
local T = require("../TestKit")
local DynTex = require("../../build/luautest/shared/Render/DynTex")

return function()
	T.it("every kind has a name and a number", function()
		T.truthy(#DynTex.NAMES >= 12, "a dozen kinds or more")
		for i, name in DynTex.NAMES do
			T.eq(DynTex.kind(name), i, name)
		end
		T.eq(DynTex.kind(nil), 0, "none")
		T.eq(DynTex.kind("no such texture"), 0, "unknown")
		T.eq(DynTex.lift(0, 1, 1, 0.05, 3), 0, "kind 0 is plain")
	end)

	T.it("each kind steps at most one band, the same for the same pixel, and stays sparse", function()
		local px = 1 / 30
		for kind = 1, #DynTex.NAMES do
			local marked, light, dark = 0, 0, 0
			for i = 0, 59 do
				for j = 0, 59 do
					local u, v = (i + 0.5) * px, (j + 0.5) * px
					local l = DynTex.lift(kind, u, v, px, 5)
					T.truthy(l == -1 or l == 0 or l == 1, "one band")
					if i % 13 == 0 and j % 11 == 0 then
						T.eq(DynTex.lift(kind, u, v, px, 5), l, "deterministic")
					end
					if l ~= 0 then
						marked += 1
					end
					if l > 0 then
						light += 1
					elseif l < 0 then
						dark += 1
					end
				end
			end
			local share = marked / 3600
			T.truthy(share > 0.02, DynTex.NAMES[kind] .. " shows (" .. share .. ")")
			T.truthy(share < 0.4, DynTex.NAMES[kind] .. " is a texture, not a fill (" .. share .. ")")
		end
	end)

	T.it("the pattern is measured in pixels: the same marks at twice the zoom", function()
		for kind = 1, #DynTex.NAMES do
			for i = 0, 40 do
				local a = DynTex.lift(kind, (i + 0.5) * 0.04, 0.3 * 0.04, 0.04, 2)
				local b = DynTex.lift(kind, (i + 0.5) * 0.02, 0.3 * 0.02, 0.02, 2)
				T.eq(a, b, DynTex.NAMES[kind] .. " at pixel " .. i)
			end
		end
	end)

	T.it("parts are laid out round their own axis", function()
		local u, v = DynTex.uv("Ball", 1, 0.3, 0)
		T.near(u, 0, 1e-9, "a ball's u starts on its +X")
		T.near(v, 0.3, 1e-9, "a ball's v is its height")
		local u2 = DynTex.uv("Ball", 0, 0, 1)
		T.near(u2, math.pi / 2, 1e-9, "a quarter turn round a unit ball")
		local cu, cv = DynTex.uv("Cylinder", 0.7, 0, 0.5)
		T.near(cu, math.pi / 2 * 0.5, 1e-9, "round a cylinder's own X")
		T.near(cv, 0.7, 1e-9, "along a cylinder's own X")
		T.truthy(DynTex.MIN_PX_PER_STUD > 8, "no texture at the islands' zoom")
	end)
end
