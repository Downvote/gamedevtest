local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Crew = require("../../build/luautest/shared/Logic/Crew")
local Util = require("../../build/luautest/shared/Logic/Util")
return function()
	T.it("salary: base plus per skill point", function()
		T.eq(Crew.salary({ code = 20, design = 20, art = 20, sound = 20 }), Tuning.SalaryBase + 80 * Tuning.SalaryPerSkill)
	end)
	T.it("candidates: skills in range for the year, one skill that shines", function()
		local rng = Util.newRng(7)
		for year = 1, 12 do
			for _, c in Crew.candidates(rng, year, 5) do
				local bonus = Tuning.CandidateYearly * (year - 1)
				local over = 0
				for _, k in Crew.SKILLS do
					local v = (c.skills :: any)[k]
					T.truthy(v >= Tuning.CandidateMin + bonus and v <= Tuning.SkillMax, k .. " in range")
					if v > Tuning.CandidateMax + bonus then
						over += 1
					end
				end
				T.truthy(over <= 1, "at most one star skill")
				T.eq(c.salary, Crew.salary(c.skills))
				T.truthy(#c.name > 3)
			end
		end
	end)
	T.it("free desks", function()
		local staff = { { desk = 1 }, { desk = 3 } } :: any
		T.eq(Crew.freeDesk(staff, 3), 2)
		T.eq(Crew.freeDesk(staff, 1), nil)
	end)
	T.it("training gains shrink as a skill grows", function()
		T.eq(Crew.trainGain(0), Tuning.TrainMax)
		T.eq(Crew.trainGain(Tuning.SkillMax), Tuning.TrainMin)
		T.truthy(Crew.trainGain(100) <= Crew.trainGain(20))
	end)
	T.it("energy: work drains, rest refills, tired halves the output", function()
		local s = { energy = 100 } :: any
		for _ = 1, 20 do
			Crew.energyWeek(s, true)
		end
		T.eq(s.energy, 0)
		T.truthy(Crew.tired(s))
		T.eq(Crew.rate(s), Tuning.TiredRate)
		for _ = 1, 20 do
			Crew.energyWeek(s, false)
		end
		T.eq(s.energy, Tuning.EnergyMax)
		T.eq(Crew.rate(s), 1)
	end)
	T.it("roles follow the best skill", function()
		T.eq(Crew.role({ code = 5, design = 9, art = 2, sound = 1 }), "Designer")
		T.eq(Crew.role({ code = 5, design = 5, art = 2, sound = 1 }), "Coder")
	end)
end
