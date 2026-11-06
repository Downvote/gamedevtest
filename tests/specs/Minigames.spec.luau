-- The minigames' rules (Logic/Minigames; GAME_DESIGN 14): pushes earned at the build milestones, the grades, what a
-- push adds, what Bug Squash removes, and starting and finishing (a push spent at the start, so a replay never rerolls).
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Minigames = require("../../build/luautest/shared/Logic/Minigames")
local Studio = require("../../build/luautest/shared/Logic/Studio")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Util = require("../../build/luautest/shared/Logic/Util")

local function withGame(size: string?): any
	local p = Schema.default(0, 1)
	p.money = 1e6
	local ok, err = Studio.start(p, { genre = "action", topic = "space", platform = "pc", size = size or "small", focus = "fun", seed = 1 })
	assert(ok, err)
	return p
end

return function()
	T.it("milestones: Tuning.MiniMilestones per size, spread over the build, never its last week", function()
		for size, spec in Tuning.Sizes do
			local ms = Minigames.milestones(size)
			T.eq(#ms, Tuning.MiniMilestones[size], size)
			for i, w in ms do
				T.truthy(w >= 1 and w < spec.weeks, size .. " milestone inside the build")
				if i > 1 then
					T.truthy(w > ms[i - 1], size .. " milestones rise")
				end
			end
		end
		T.eq(table.concat(Minigames.milestones("small"), ","), "3,5")
	end)
	T.it("a build earns its pushes week by week, at most Tuning.MiniMaxPushes banked", function()
		local p = withGame("large")
		local rng = Util.newRng(5)
		local earned, pushes = 0, 0
		while p.project and p.project.phase == "build" do
			for _, e in Studio.week(p, rng) do
				if e.kind == "push" then
					pushes += 1
					T.eq(e.title, p.project.title)
				end
			end
			earned = p.project.nextPush
		end
		T.eq(earned, Tuning.MiniMilestones.large, "every milestone reached")
		T.eq(pushes, Tuning.MiniMilestones.large, "one push event each")
		T.eq(p.project.pushes, Tuning.MiniMaxPushes, "banked up to the cap")
		-- polishing earns none
		for _ = 1, 4 do
			for _, e in Studio.week(p, rng) do
				T.truthy(e.kind ~= "push", "no push while polishing")
			end
		end
	end)
	T.it("grades", function()
		T.eq(Minigames.grade(100), "S")
		T.eq(Minigames.grade(Tuning.MiniGrades.S), "S")
		T.eq(Minigames.grade(Tuning.MiniGrades.S - 1), "A")
		T.eq(Minigames.grade(Tuning.MiniGrades.B), "B")
		T.eq(Minigames.grade(Tuning.MiniGrades.B - 1), "C")
		T.eq(Minigames.grade(0), "C")
	end)
	T.it("a push adds up to Tuning.MiniWeeks weeks of the crew's output on its score", function()
		local p = withGame()
		local proj = p.project
		local week = Minigames.weekOutput(p.staff, "fun", proj.focus)
		T.truthy(week > 0)
		T.eq(Minigames.axisPoints(p.staff, "fun", proj.focus, 100), math.floor(week * Tuning.MiniWeeks + 0.5))
		T.eq(Minigames.axisPoints(p.staff, "fun", proj.focus, 0), 0)
		T.eq(Minigames.axisPoints(p.staff, "fun", proj.focus, 500), Minigames.axisPoints(p.staff, "fun", proj.focus, 100), "clamped")
		T.truthy(Minigames.weekOutput(p.staff, "fun", "fun") > Minigames.weekOutput(p.staff, "fun", "sound"), "the focus counts")
		local tired = Util.deepCopy(p.staff)
		for _, s in tired do
			s.energy = 0
		end
		T.near(Minigames.weekOutput(tired, "fun", "fun"), Minigames.weekOutput(p.staff, "fun", "fun") * Tuning.TiredRate, 1e-6, "tired crews half")
	end)
	T.it("Bug Squash: up to Tuning.SquashWeeks weeks of the crew's fixing", function()
		local staff = Schema.default(0, 1).staff
		local week = Minigames.fixWeek(staff)
		T.eq(week, #staff * Tuning.FixBase + staff[1].skills.code // Tuning.FixCode + staff[2].skills.code // Tuning.FixCode)
		local full = math.floor(week * Tuning.SquashWeeks + 0.5)
		T.eq(Minigames.squashed(staff, 999, 100), full)
		T.eq(Minigames.squashed(staff, 2, 100), math.min(2, full), "never more than there are")
		T.eq(Minigames.squashed(staff, 999, 0), 0)
		T.eq(Minigames.squashed(staff, 0, 100), 0)
		T.eq(Minigames.squashed(staff, 999, 1), 1, "any hit squashes one")
	end)
	T.it("start: a push for the score games, a polish with bugs off cooldown for Bug Squash", function()
		local p = Schema.default(0, 1)
		T.eq(select(2, Minigames.canStart(p, "code")), "no_project")
		T.eq(select(2, Minigames.canStart(p, "nope")), "bad_payload")
		p = withGame()
		local proj = p.project
		T.eq(select(2, Minigames.start(p, "code")), "cooldown", "no push banked")
		proj.pushes = 1
		T.truthy(Minigames.start(p, "code"))
		T.eq(proj.pushes, 0, "spent at the start")
		T.eq(proj.played, 1)
		T.eq(select(2, Minigames.start(p, "ideas")), "cooldown")
		T.eq(select(2, Minigames.start(p, "bugs")), "not_built", "not while building")
		proj.phase = "polish"
		proj.bugs = 0
		T.eq(select(2, Minigames.start(p, "bugs")), "not_built", "no bugs")
		proj.bugs = 4
		T.truthy(Minigames.start(p, "bugs"))
		T.eq(proj.squashWeek, p.week + Tuning.SquashCooldown)
		T.eq(select(2, Minigames.start(p, "bugs")), "cooldown")
		p.week += Tuning.SquashCooldown
		T.truthy(Minigames.canStart(p, "bugs"), "off cooldown")
	end)
	T.it("finish: the points on the game's score, the bugs off the project", function()
		local p = withGame()
		local proj = p.project
		local before = proj.scores.graphics
		local ok, data = Minigames.finish(p, "pixels", 80)
		T.truthy(ok)
		T.eq(data.axis, "graphics")
		T.eq(data.grade, "A")
		T.eq(data.points, Minigames.axisPoints(p.staff, "graphics", proj.focus, 80))
		T.eq(proj.scores.graphics, before + data.points)
		proj.bugs = 2
		ok, data = Minigames.finish(p, "bugs", 100)
		T.truthy(ok)
		T.eq(data.removed, 2)
		T.eq(proj.bugs, 0)
		T.eq(select(2, Minigames.finish(Schema.default(0, 1), "code", 50)), "no_project")
		ok, data = Minigames.finish(p, "beats", -20)
		T.eq(data.score, 0, "scores clamp")
	end)
	T.it("every kind is named, and the four push games cover the four scores", function()
		local axes = {}
		for _, id in Minigames.PUSH_ORDER do
			local def = Minigames.KINDS[id]
			T.truthy(def and def.axis, id)
			axes[def.axis] = true
		end
		T.truthy(axes.fun and axes.ideas and axes.graphics and axes.sound)
		T.truthy(Minigames.KINDS.bugs and Minigames.KINDS.bugs.axis == nil)
	end)
end
