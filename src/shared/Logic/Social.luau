--!strict
-- Leaderboards and friends (GAME_DESIGN 16; Services/SocialService). The request (2026-11-21): "Make a leaderboard
-- system, along with friend invite bonuses". Pure: SocialService calls these with the session's profile and the real
-- clock (`now`: os.time, seconds; a day is a UTC day, floor(now / 86400), and a save's age is now - createdAt).
--   The boards (`BOARDS`, `score`, `scores`): coins earned in all, the island's charm, eggs hatched (the tree's and the
--   Hatcheries'). Whole numbers, as OrderedDataStores keep them.
--   A friend invited (`canJoin`, `join`, `play`, `due`, `reward`): a save younger than Tuning.ReferralMaxAgeSec takes
--   the inviter from the join (never itself, once) and gets Data/Rewards.REFERRAL.invitee at once; its seconds of play
--   count from then, and at Tuning.ReferralMinPlaySec the inviter's reward is due (REFERRAL.inviter: given by
--   `reward`, at most Tuning.ReferralDailyCap a UTC day; SocialService gives it live or queues it).
--   Friends on the server (`Island.friendsMult` reads Profile.social.here, which SocialService keeps): more coins while
--   they play together.
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local RewardsData = require(script.Parent.Parent.Data.Rewards)
local Rewards = require(script.Parent.Rewards)
local Island = require(script.Parent.Island)

type Profile = Types.Profile
type Given = any

local Social = {}

-- The boards, in the Top sheet's order.
Social.BOARDS = { "coins", "charm", "hatched" } :: { string }

function Social.fresh(): Types.Social
	return { referredBy = 0, refPaid = false, refPlay = 0, invited = 0, refDay = -1, refToday = 0, here = 0 }
end

------------------------------------------------------------------ the boards
-- A player's score on a board (0 for an unknown board).
function Social.score(p: Profile, board: string): number
	if board == "coins" then
		return math.max(0, math.floor(p.stats.earned))
	elseif board == "charm" then
		return math.max(0, math.floor(Island.charm(p, Island.isle(p))))
	elseif board == "hatched" then
		return math.max(0, math.floor(p.stats.taken + p.stats.hatched))
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
