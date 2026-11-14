--!strict
-- A mutation's name with its tier in small star sprites (GAME_DESIGN 7; the request of 2026-11-14: "the * in mutations
-- should be replaced with small star sprites to show the rarity of mutations"). The name in its tier's colour
-- (Traits.TIER_COLOR), then one 7 x 7 "star_t<tier>" a tier (gen_art.py: white, green, teal, gold), a pixel apart; a
-- tier 0 mutation has none. The stars are the label's children, so the label's Text is the name alone.
--   TierStars.label(parent, text, tier, x, y, opts?) -> (TextLabel, number)   the label (opts.name) and the width it
--       takes; opts: { color?, z?, name?, suffix? } (suffix: words after the stars, such as ",")
--   TierStars.measure(text, tier, suffix?) -> number   that width, before drawing
--   TierStars.width(tier) -> number                     the stars alone
--   TierStars.shown(label) -> number                    the stars a label shows (sims and previews)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Traits = require(ReplicatedStorage.Shared.Data.Traits)
local PixelSprites = require(script.Parent.PixelSprites)
local UIKit = require(script.Parent.UIKit)

local TierStars = {}

local STEP = 8 -- a star (7 px) and a pixel between
local GAP = 2 -- between the name and its stars

export type Opts = { color: Color3?, z: number?, name: string?, suffix: string? }

local function count(tier: number): number
	return math.clamp(math.floor(tier), 0, 4)
end

function TierStars.width(tier: number): number
	local n = count(tier)
	return if n > 0 then n * STEP - 1 else 0
end

function TierStars.measure(text: string, tier: number, suffix: string?): number
	local w = UIKit.textWidth(text)
	local sw = TierStars.width(tier)
	if sw > 0 then
		w += GAP + sw
	end
	if suffix and suffix ~= "" then
		w += UIKit.textWidth(suffix)
	end
	return w
end

function TierStars.label(parent: Instance, text: string, tier: number, x: number, y: number, opts: Opts?): (TextLabel, number)
	local o: Opts = opts or {}
	local color = o.color or UIKit.color(Traits.TIER_COLOR[tier] or "text")
	local z = o.z or 2
	local lw = UIKit.textWidth(text)
	local lab = UIKit.text(parent, text, UDim2.fromOffset(lw + 2, 10), UDim2.fromOffset(x, y), { color = color, z = z, name = o.name })
	local n = count(tier)
	local w = lw
	if n > 0 then
		for k = 1, n do
			local img = PixelSprites.image(lab, "star_t" .. n, UDim2.fromOffset(lw + GAP + (k - 1) * STEP, 1), z)
			img.Name = "Star_" .. k
		end
		w += GAP + n * STEP - 1
	end
	local suffix = o.suffix
	if suffix and suffix ~= "" then
		local sw = UIKit.textWidth(suffix)
		UIKit.text(lab, suffix, UDim2.fromOffset(sw + 2, 10), UDim2.fromOffset(w, 0), { color = color, z = z, name = "Suffix" })
		w += sw
	end
	return lab, w
end

-- How many stars a label drawn here shows (sims and previews).
function TierStars.shown(lab: Instance?): number
	if lab == nil then
		return 0
	end
	local n = 0
	for _, c in lab:GetChildren() do
		if string.match(c.Name, "^Star_%d+$") then
			n += 1
		end
	end
	return n
end

return TierStars
