--!strict
-- Leaderboards and friends (GAME_DESIGN 16; Services/SocialService). The request (2026-11-21): "Make a leaderboard
-- system, along with friend invite bonuses". Pure: SocialService calls these with the session's profile and the real
-- clock (`now`: os.time, seconds; a day is a UTC day, floor(now / 86400), and a save's age is now - createdAt).
--   The boards (`BOARDS`, `score`, `scores`): coins earned in all, the island's charm, eggs hatched (the tree's and the
--   Hatcheries'), and the island's best driftling (`palPoints`: its rarity's Tuning.BoardRarityPoints plus
--   Tuning.BoardStarPoints a mutation star; the request of 2026-11-21: "make another tab on the leaderboard for
--   driftlings. judge based on rarity and mutation stars"). Whole numbers, as OrderedDataStores keep them: the
--   Driftlings board's is points x KIND_CODES + the kind's code (`kindCode`), so the board can say which driftling it
--   was (`decode`).
--   A friend invited (`canJoin`, `join`, `play`, `due`, `reward`): a save younger than Tuning.ReferralMaxAgeSec takes
--   the inviter from the join (never itself, once) and gets Data/Rewards.REFERRAL.invitee at once; its seconds of play
--   count from then, and at Tuning.ReferralMinPlaySec the inviter's reward is due (REFERRAL.inviter: given by
--   `reward`, at most Tuning.ReferralDailyCap a UTC day; SocialService gives it live or queues it).
--   Friends on the server (`Island.friendsMult` reads Profile.social.here, which SocialService keeps): more coins while
--   they play together.
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local RewardsData = require(script.Parent.Parent.Data.Rewards)
local Creatures = require(script.Parent.Parent.Data.Creatures)
local Traits = require(script.Parent.Parent.Data.Traits)
local Util = require(script.Parent.Util)
local Rewards = require(script.Parent.Rewards)
local Island = require(script.Parent.Island)

type Profile = Types.Profile
type Given = any

local Social = {}

-- The boards, in the Top sheet's order.
Social.BOARDS = { "coins", "charm", "hatched", "driftlings" } :: { string }
-- The Driftlings board's value: points x KIND_CODES + the kind's code.
Social.KIND_CODES = 1000000

function Social.fresh(): Types.Social
	return { referredBy = 0, refPaid = false, refPlay = 0, invited = 0, refDay = -1, refToday = 0, here = 0 }
end

------------------------------------------------------------------ the boards
-- A driftling's mutation stars: its mutations' tiers added up (a flaw is tier 0).
function Social.stars(pal: Types.Pal): number
	local n = 0
	local muts: { string } = pal.muts or {}
	for _, id in muts do
		local m = Traits.byId[id]
		if m then
			n += math.max(0, m.tier)
		end
	end
	return n
end

-- A driftling's points on the Driftlings board: its rarity's and its stars'.
function Social.palPoints(pal: Types.Pal): number
	local c = Creatures.byId[pal.sp]
	if c == nil then
		return 0
	end
	local r = math.clamp(c.rarity, 1, #Tuning.BoardRarityPoints)
	return Tuning.BoardRarityPoints[r] + Tuning.BoardStarPoints * Social.stars(pal)
end

-- The island's best driftling and its points (0, nil with none). Equal points: the more stars, then the first.
function Social.bestPal(p: Profile): (number, Types.Pal?)
	local best, top = 0, nil
	for _, pal in p.pals do
		local pts = Social.palPoints(pal)
		if top == nil or pts > best or (pts == best and Social.stars(pal) > Social.stars(top)) then
			best, top = pts, pal
		end
	end
	return best, top
end

-- A kind's code in the Driftlings board's value (its id hashed; Social.spec checks no two kinds share one).
function Social.kindCode(sp: string): number
	return Util.hash32(sp) % Social.KIND_CODES
end

local byCode: { [number]: string }? = nil
-- The Driftlings board's value read back: (points, kind id or nil).
function Social.decode(value: number): (number, string?)
	if byCode == nil then
		local t: { [number]: string } = {}
		for _, c in Creatures.list do
			t[Social.kindCode(c.id)] = c.id
		end
		byCode = t
	end
	local v = math.max(0, math.floor(value))
	return v // Social.KIND_CODES, (byCode :: { [number]: string })[v % Social.KIND_CODES]
end

-- A player's score on a board (0 for an unknown board).
function Social.score(p: Profile, board: string): number
	if board == "coins" then
		return math.max(0, math.floor(p.stats.earned))
	elseif board == "charm" then
		return math.max(0, math.floor(Island.charm(p, Island.isle(p))))
	elseif board == "hatched" then
		return math.max(0, math.floor(p.stats.taken + p.stats.hatched))
	elseif board == "driftlings" then
		local pts, pal = Social.bestPal(p)
		return if pal then pts * Social.KIND_CODES + Social.kindCode(pal.sp) else 0
	end
	return 0
end

function Social.scores(p: Profile): { [string]: number }
	local out: { [string]: number } = {}
	for _, b in Social.BOARDS do
		out[b] = Social.score(p, b)
	end
	return out
end

function Social.isBoard(board: any): boolean
	return type(board) == "string" and table.find(Social.BOARDS, board) ~= nil
end

------------------------------------------------------------------ a friend invited
local function day(now: number): number
	return math.floor(now / 86400)
end

-- Whether this save takes `inviter` as the friend who invited it: none taken yet, a real user who isn't the player,
-- and a save young enough (an old player joining from a friend's invite is welcome but brings no gifts).
function Social.canJoin(p: Profile, inviter: number?, selfId: number, now: number): boolean
	if type(inviter) ~= "number" or inviter ~= math.floor(inviter) or inviter <= 0 or inviter == selfId then
		return false
	end
	return p.social.referredBy == 0 and now - p.createdAt < Tuning.ReferralMaxAgeSec
end

-- The invite taken: the inviter noted and the welcome gift given. Returns what was given.
function Social.join(p: Profile, inviter: number): { Given }
	p.social.referredBy = inviter
	p.social.refPlay = 0
	p.social.refPaid = false
	local out: { Given } = {}
	for _, r in RewardsData.REFERRAL.invitee do
		table.insert(out, Rewards.give(p, r))
	end
	return out
end

-- dt seconds of play: counted while the inviter's reward isn't out yet. True when it became due just now.
function Social.play(p: Profile, dt: number): boolean
	local s = p.social
	if s.referredBy == 0 or s.refPaid then
		return false
	end
	local before = s.refPlay
	s.refPlay = math.min(Tuning.ReferralMinPlaySec, s.refPlay + math.max(0, dt))
	return before < Tuning.ReferralMinPlaySec and s.refPlay >= Tuning.ReferralMinPlaySec
end

-- The invited friend has played long enough and the inviter's reward hasn't gone out.
function Social.due(p: Profile): boolean
	local s = p.social
	return s.referredBy ~= 0 and not s.refPaid and s.refPlay >= Tuning.ReferralMinPlaySec
end

-- How many more invited friends can be rewarded today.
function Social.todayLeft(p: Profile, now: number): number
	local s = p.social
	local used = if s.refDay == day(now) then s.refToday else 0
	return math.max(0, Tuning.ReferralDailyCap - used)
end

-- The inviter's side: one friend more, and the reward, unless today's are all taken (false: try another day).
function Social.reward(p: Profile, now: number): (boolean, { Given }?)
	if Social.todayLeft(p, now) <= 0 then
		return false, nil
	end
	local s = p.social
	local d = day(now)
	if s.refDay ~= d then
		s.refDay = d
		s.refToday = 0
	end
	s.refToday += 1
	s.invited += 1
	local out: { Given } = {}
	for _, r in RewardsData.REFERRAL.inviter do
		table.insert(out, Rewards.give(p, r))
	end
	return true, out
end

------------------------------------------------------------------ the view
function Social.view(p: Profile, now: number): { invited: number, todayLeft: number, here: number, boost: number, referred: boolean }
	local s = p.social
	return {
		invited = s.invited,
		todayLeft = Social.todayLeft(p, now),
		here = s.here,
		boost = Island.friendsMult(p) - 1,
		referred = s.referredBy ~= 0,
	}
end

return Social
