--!strict
-- The questline's rules (GAME_DESIGN 9; Data/Quests). Pure: the server claims, the client shows the same progress
-- from its view (the view carries the same facts under the same names).
--   `p.quest` is the quest on the go (1 .. #Quests.list; one past the last: all done). It counts only once the tips
--   are over (`tut` 0). A quest's goal is counted from what the island has now (Facts), so one
--   already met is done the moment it comes up; claiming pays its reward and moves on to the next.
local Types = require(script.Parent.Parent.Types)
local Buildings = require(script.Parent.Parent.Data.Buildings)
local Quests = require(script.Parent.Parent.Data.Quests)

type Profile = Types.Profile

-- What a quest's goal is counted from (a profile's own fields, or the client view's: `pieces` is the island's pieces).
export type Facts = {
	pals: { Types.Pal },
	pieces: { Types.Piece },
	tier: number,
	seen: { [string]: number },
	stats: Types.Stats,
}

local Quest = {}

function Quest.facts(p: Profile): Facts
	return {
		pals = p.pals,
		pieces = p.plot.placed,
		tier = p.tier,
		seen = p.seen,
		stats = p.stats,
	}
end

local function kindOf(id: string): string
	local b = Buildings.byId[id]
	return if b then b.kind else ""
end

-- How far a goal has come (not capped at its number).
function Quest.count(f: Facts, g: Quests.Goal): number
	local k = g.kind
	local n = 0
	if k == "helpers" then
		for _, x in f.pals do
			if x.work ~= 0 then
				n += 1
			end
		end
	elseif k == "paths" or k == "decor" then
		local kind = if k == "paths" then "path" else "decor"
		for _, q in f.pieces do
			if kindOf(q.id) == kind then
				n += 1
			end
		end
	elseif k == "built" then
		for _, q in f.pieces do
			if kindOf(q.id) == g.of then
				n += 1
			end
		end
	elseif k == "housed" then
		for _, x in f.pals do
			if x.home ~= 0 then
				n += 1
			end
		end
	elseif k == "taken" then
		n = f.stats.taken
	elseif k == "sold" then
		n = f.stats.sold
	elseif k == "best" then
		n = f.stats.best
	elseif k == "tier" then
		n = f.tier
	elseif k == "seen" then
		for _ in f.seen do
			n += 1
		end
	elseif k == "hatched" then
		n = f.stats.hatched
	end
	return n
end

-- The quest on the go (nil while the tips are on, or once every quest is done) and its number.
function Quest.current(tut: number, i: number): (Quests.Quest?, number)
	if tut ~= 0 then
		return nil, i
	end
	return Quests.list[i], i
end

-- A quest's progress: how far (at most its number) and its number.
function Quest.progress(f: Facts, q: Quests.Quest): (number, number)
	return math.min(Quest.count(f, q.goal), q.goal.n), q.goal.n
end

function Quest.done(f: Facts, q: Quests.Quest): boolean
	return Quest.count(f, q.goal) >= q.goal.n
end

-- Claim the quest on the go: its reward paid, the next one up. Errors: "not_found" (the tips are on, or every quest
-- is done), "not_done" (its goal isn't met yet).
function Quest.claim(p: Profile): (boolean, any)
	local q = Quest.current(p.tut, p.quest)
	if q == nil then
		return false, "not_found"
	end
	if not Quest.done(Quest.facts(p), q) then
		return false, "not_done"
	end
	local r = q.reward
	p.shells += r.shells or 0
	p.quest += 1
	return true, { id = q.id, shells = r.shells or 0, next = p.quest }
end

return Quest
