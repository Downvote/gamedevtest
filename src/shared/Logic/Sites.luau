--!strict
-- The wild places coming up on the island (GAME_DESIGN 7; Data/Sites). Pure.
--   spawn(p) -> { Piece }   (the places of every tier the island has reached that haven't come up yet: `p.wilds`
--                            counts the tiers done; a new island's first, then each expansion's)
--   pieceOf(p, uid) -> (Piece?, index)
-- A place comes up on the island's grass where its footprint fits (off the plaza, the path and every piece) and its
-- ring (Tuning.SiteRadius round it) is clear of the other wild places' rings; it prefers a ring with nothing built
-- in it, the land the island has just gained (an expansion's), and the edge of the island over its middle (the
-- middle is where the village grows). Where it comes up depends only on the island's seed and what stands there. A
-- place with no room left anywhere is passed over.
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Street = require(script.Parent.Parent.Data.Street)
local SiteData = require(script.Parent.Parent.Data.Sites)
local Util = require(script.Parent.Util)
local Plot = require(script.Parent.Plot)

type Profile = Types.Profile
type Piece = Types.Piece
type Rect = Street.Rect

local Sites = {}

local function overlaps(a: Rect, b: Rect): boolean
	return a.x0 < b.x1 and b.x0 < a.x1 and a.z0 < b.z1 and b.z0 < a.z1
end

-- The best spot for a place of piece id `pid` on the island at `tier` (it came with tier `from`: its new land is
-- preferred), or nil.
local function spotFor(p: Profile, pid: string, tier: number, from: number, rng: Types.Rng): (number?, number?)
	local w, d = Plot.footprint(pid, 0)
	local k = Tuning.SiteRadius
	local land = Street.plot(tier)
	local placed = p.plot.placed
	local zones: { Rect } = {}
	for _, q in placed do
		if Plot.isSite(q.id) then
			table.insert(zones, Plot.zone(q))
		end
	end
	local cx, cz = Street.CENTER.x, Street.CENTER.z
	local best, bx, bz = -math.huge, nil :: number?, nil :: number?
	for z = math.floor(land.z0), math.floor(land.z1) - d do
		for x = math.floor(land.x0), math.floor(land.x1) - w do
			if Plot.fits(tier, placed, pid, x, z, 0, nil, true) then
				local zone = { x0 = x - k, z0 = z - k, x1 = x + w + k, z1 = z + d + k }
				local apart = true
				for _, r in zones do
					if overlaps(zone, r) then
						apart = false
						break
					end
				end
				if apart then
					-- what stands in its ring (a ring with nothing in it is far better)
					local inRing = 0
					for _, q in placed do
						if overlaps(zone, Plot.rect(q.id, q.x, q.z, q.rot)) then
							inRing += 1
						end
					end
					-- how much of it is on the land the island has just gained
					local fresh = 0
					if from > 1 then
						for zz = z, z + d - 1 do
							for xx = x, x + w - 1 do
								if not Street.buildable(from - 1, xx, zz) then
									fresh += 1
								end
							end
						end
						fresh /= w * d
					end
					local mx, mz = x + w / 2 - cx, z + d / 2 - cz
					local score = (if inRing == 0 then 1000 else -60 * inRing) + 200 * fresh + 2 * math.sqrt(mx * mx + mz * mz) + 30 * rng:next()
					if score > best then
						best, bx, bz = score, x, z
					end
				end
			end
		end
	end
	return bx, bz
end

-- Bring up the places of every tier reached and not done yet. Returns the new pieces.
function Sites.spawn(p: Profile): { Piece }
	local out: { Piece } = {}
	local done = math.max(0, math.floor(p.wilds or 0))
	while done < p.tier do
		local t = done + 1
		for i, e in SiteData.spawnAt(t) do
			local pid = SiteData.wildId(e.id)
			local rng = Util.newRng(Util.hash32((p.sea or 1) + t * 7919 + i * 104729))
			local x, z = spotFor(p, pid, p.tier, t, rng)
			if x and z then
				local q: Piece = { uid = p.nextId, id = pid, x = x, z = z, rot = 0, lvl = e.lvl }
				p.nextId += 1
				table.insert(p.plot.placed, q)
				table.insert(out, q)
			end
		end
		done = t
	end
	p.wilds = done
	return out
end

-- A place on the island by its uid (wild or cleared), and its index in the pieces.
function Sites.pieceOf(p: Profile, uid: number): (Piece?, number)
	for i, q in p.plot.placed do
		if q.uid == uid and Plot.isSite(q.id) then
			return q, i
		end
	end
	return nil, 0
end

return Sites
