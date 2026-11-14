--!strict
-- The island growing into its next tier, around the picture (GAME_DESIGN 4; Pixel/Grow moves the coast on the pixel
-- layer): the request (2026-11-14), "expanding the island dosent have a good transition, it simply make the new land
-- appear out of nowhere. could you make a transition such that it feels like the island grows out the new land
-- smoothly?". While it grows, sea spray jumps up where the moving shore pushes into the water (Puffs' drops, 1 px), the
-- surf rushes (the Waves clip) and the sand settles with a few soft thumps; Build mode's cheer waits for the end
-- (PixelRenderer.afterGrow). Client only; nothing while the pixel filter is off.
local RunService = game:GetService("RunService")

local Street = require(game:GetService("ReplicatedStorage").Shared.Data.Street)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local Audio = require(script.Parent.Audio)
local Puffs = require(script.Parent.Puffs)

local GrowFx = {}

local was = false
local thumpAt = 0
local sprays = 0 -- bursts thrown up so far (previews and sims)

local function step()
	local on, k = PixelRenderer.growing()
	local active = on and PixelRenderer.growStats().active
	if active and not was then
		Audio.play("grow_surf")
		thumpAt = os.clock()
	end
	was = active
	if not active then
		PixelRenderer.growFront()
		return
	end
	-- a few soft thumps of sand as the land pushes up, slowing as it settles
	local now = os.clock()
	if k < 0.7 and now >= thumpAt then
		Audio.play("grow_sand")
		thumpAt = now + 0.22 + k * 0.5
	end
	for i, p in PixelRenderer.growFront() do
		if i > 4 then
			break
		end
		-- (at the water's surface where the shore meets it)
		Puffs.burst("drop", Vector3.new(p.X, Street.WATER_Y + 0.1, p.Z), 3, 0.5)
		sprays += 1
	end
end

function GrowFx.start()
	RunService.Heartbeat:Connect(step)
end

-- Previews and sims: the spray bursts thrown up so far.
function GrowFx.sprays(): number
	return sprays
end

return GrowFx
