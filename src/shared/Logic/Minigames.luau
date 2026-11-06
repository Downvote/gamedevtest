--!strict
-- Minigames (GAME_DESIGN 14; docs/ARCHITECTURE.md 6): the crew's pushes that make a game better. Pure.
-- A build earns pushes at its milestones (Tuning.MiniMilestones by size, spread evenly over the build weeks; at most
-- Tuning.MiniMaxPushes banked). A push is spent on one of four minigames, each for one score: Code Rush (Fun), Idea
-- Match (Ideas), Pixel Paint (Graphics), Beat Keeper (Sound). Its score (0-100) adds up to Tuning.MiniWeeks weeks of
-- the crew's output on that score. Bug Squash is played while polishing a game with bugs, once every
-- Tuning.SquashCooldown weeks, and squashes up to Tuning.SquashWeeks weeks of the crew's bug fixing. The server starts a game (spending the push or starting
-- the cooldown, so a replay never rerolls) and applies the finish; the client plays it.
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Crew = require(script.Parent.Crew)
local Dev = require(script.Parent.Dev)

type Profile = Types.Profile
type Project = Types.Project
type ErrCode = Types.ErrCode

export type KindDef = { id: string, name: string, axis: Types.Axis?, blurb: string }

local Minigames = {}

local KINDS: { [string]: KindDef } = {
	code = { id = "code", name = "Code Rush", axis = "fun", blurb = "Type the keys as they scroll in." },
	ideas = { id = "ideas", name = "Idea Match", axis = "ideas", blurb = "Find the pairs of ideas." },
	pixels = { id = "pixels", name = "Pixel Paint", axis = "graphics", blurb = "Paint the sprite to match." },
	beats = { id = "beats", name = "Beat Keeper", axis = "sound", blurb = "Tap as each note hits the line." },
	bugs = { id = "bugs", name = "Bug Squash", axis = nil, blurb = "Squash the bugs before they hide." },
}
Minigames.KINDS = KINDS
Minigames.PUSH_ORDER = { "code", "ideas", "pixels", "beats" }

-- The build weeks at which a project of `size` earns its pushes (evenly spread, never the last week).
function Minigames.milestones(size: string): { number }
	local sz = Tuning.Sizes[size]
	local n = Tuning.MiniMilestones[size] or 2
	local build = if sz then sz.weeks else 8
	local out = {}
	for k = 1, n do
		table.insert(out, math.max(1, math.floor(build * k / (n + 1) + 0.5)))
	end
	return out
end

-- After a work week: a push when the build reached its next milestone. Returns whether one was earned.
function Minigames.afterWeek(p: Project): boolean
	if p.weeksDone > p.buildWeeks then
		return false
	end
	local ms = Minigames.milestones(p.size)
	local nextWeek = ms[p.nextPush + 1]
	if nextWeek and p.weeksDone >= nextWeek then
		p.nextPush += 1
		p.pushes = math.min(Tuning.MiniMaxPushes, p.pushes + 1)
		return true
	end
	return false
end

function Minigames.grade(score: number): string
	local g = Tuning.MiniGrades
	if score >= g.S then
		return "S"
	elseif score >= g.A then
		return "A"
	elseif score >= g.B then
		return "B"
	end
	return "C"
end

-- The crew's output on a score in one week (no spread, the focus included, tired developers at half rate).
function Minigames.weekOutput(staff: { Types.Staff }, axis: Types.Axis, focus: Types.Axis): number
	local team = Dev.teamFactor(#staff)
	local t = 0
	for _, s in staff do
		local o = Dev.output(s.skills)
		t += (o :: any)[axis] * team * Crew.rate(s)
	end
	return t * Dev.focusMult(focus, axis)
end

-- What a push with this score adds to its score's points.
function Minigames.axisPoints(staff: { Types.Staff }, axis: Types.Axis, focus: Types.Axis, score: number): number
	return math.floor(Minigames.weekOutput(staff, axis, focus) * Tuning.MiniWeeks * math.clamp(score, 0, 100) / 100 + 0.5)
end

-- The bugs the crew fixes in a week of polish (Dev.workWeek's rule, tired developers included).
function Minigames.fixWeek(staff: { Types.Staff }): number
	local t = 0
	for _, s in staff do
		t += Tuning.FixBase + s.skills.code // Tuning.FixCode
	end
	return t
end

-- How many bugs a Bug Squash with this score removes: up to Tuning.SquashWeeks weeks of the crew's fixing (any hit at
-- all squashes one).
function Minigames.squashed(staff: { Types.Staff }, bugs: number, score: number): number
	local sc = math.clamp(score, 0, 100)
	if sc <= 0 or bugs <= 0 then
		return 0
	end
	return math.min(bugs, math.max(1, math.floor(Minigames.fixWeek(staff) * Tuning.SquashWeeks * sc / 100 + 0.5)))
end

-- Whether `kind` can be started now: a push banked for the four score games, a polish with bugs off cooldown for
-- Bug Squash.
function Minigames.canStart(p: Profile, kind: string): (boolean, ErrCode?)
	local def = KINDS[kind]
	local proj = p.project
	if def == nil then
		return false, "bad_payload"
	end
	if proj == nil then
		return false, "no_project"
	end
	if kind == "bugs" then
		if proj.phase ~= "polish" or proj.bugs <= 0 then
			return false, "not_built"
		end
		if p.week < proj.squashWeek then
			return false, "cooldown"
		end
		return true, nil
	end
	if proj.pushes <= 0 then
		return false, "cooldown"
	end
	return true, nil
end

-- Start a game: the push is spent (or Bug Squash's cooldown begins) now, so quitting or replaying never rerolls.
function Minigames.start(p: Profile, kind: string): (boolean, any)
	local ok, err = Minigames.canStart(p, kind)
	if not ok then
		return false, err
	end
	local proj = p.project :: Project
	if kind == "bugs" then
		proj.squashWeek = p.week + Tuning.SquashCooldown
	else
		proj.pushes -= 1
	end
	proj.played += 1
	return true, nil
end

-- Apply a finished game's score (0-100): the points it adds to its score, or the bugs it squashes.
function Minigames.finish(p: Profile, kind: string, score: number): (boolean, any)
	local def = KINDS[kind]
	local proj = p.project
	if def == nil or proj == nil then
		return false, "no_project" :: ErrCode
	end
	local sc = math.clamp(math.floor(score), 0, 100)
	local grade = Minigames.grade(sc)
	if def.axis then
		local pts = Minigames.axisPoints(p.staff, def.axis, proj.focus, sc)
		;(proj.scores :: any)[def.axis] += pts
		return true, { kind = kind, score = sc, grade = grade, axis = def.axis, points = pts }
	end
	local removed = Minigames.squashed(p.staff, proj.bugs, sc)
	proj.bugs -= removed
	return true, { kind = kind, score = sc, grade = grade, removed = removed }
end

return Minigames
