--!strict
-- The crew's rules (GAME_DESIGN 5): salaries, candidates, training, energy. Pure.
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Names = require(script.Parent.Parent.Data.Names)
local Looks = require(script.Parent.Parent.Data.Looks)
local Util = require(script.Parent.Util)

type Skills = Types.Skills
type Staff = Types.Staff
type Candidate = Types.Candidate
type Rng = Types.Rng

local Crew = {}

Crew.SKILLS = { "code", "design", "art", "sound" } :: { Types.SkillKey }
Crew.SKILL_NAMES = { code = "Code", design = "Design", art = "Art", sound = "Sound" } :: { [string]: string }
Crew.ROLES = { code = "Coder", design = "Designer", art = "Artist", sound = "Sound tech" } :: { [string]: string }

function Crew.total(s: Skills): number
	return s.code + s.design + s.art + s.sound
end

function Crew.salary(s: Skills): number
	return Tuning.SalaryBase + Tuning.SalaryPerSkill * Crew.total(s)
end

-- The developer's title: their best skill's role (ties in Crew.SKILLS order).
function Crew.role(s: Skills): string
	local best, bestKey = -1, "code"
	for _, k in Crew.SKILLS do
		local v = (s :: any)[k] :: number
		if v > best then
			best, bestKey = v, k
		end
	end
	return Crew.ROLES[bestKey]
end

function Crew.randomLook(rng: Rng): Types.Look
	return {
		skin = rng:int(1, #Looks.skin),
		hair = rng:int(1, #Looks.hair),
		style = rng:int(1, #Looks.styles),
		shirt = rng:int(1, #Looks.shirt),
	}
end

function Crew.randomName(rng: Rng): string
	return Util.pick(rng, Names.first) .. " " .. Util.pick(rng, Names.last)
end

-- One job candidate for `year`: every skill CandidateMin..CandidateMax plus CandidateYearly a year after Year 1,
-- with one skill they shine at (+50%).
function Crew.candidate(rng: Rng, year: number): Candidate
	local bonus = Tuning.CandidateYearly * math.max(0, year - 1)
	local s: Skills = { code = 0, design = 0, art = 0, sound = 0 }
	local star = Crew.SKILLS[rng:int(1, 4)]
	for _, k in Crew.SKILLS do
		local v = rng:int(Tuning.CandidateMin, Tuning.CandidateMax) + bonus
		if k == star then
			v = math.floor(v * 1.5)
		end
		(s :: any)[k] = math.min(Tuning.SkillMax, v)
	end
	return { name = Crew.randomName(rng), skills = s, salary = Crew.salary(s), look = Crew.randomLook(rng) }
end

function Crew.candidates(rng: Rng, year: number, n: number?): { Candidate }
	local out = {}
	for _ = 1, n or Tuning.Candidates do
		table.insert(out, Crew.candidate(rng, year))
	end
	return out
end

-- A hired developer from a candidate.
function Crew.hire(c: Candidate, id: number, desk: number): Staff
	return {
		id = id,
		name = c.name,
		skills = table.clone(c.skills),
		energy = Tuning.EnergyMax,
		salary = Crew.salary(c.skills),
		look = table.clone(c.look),
		desk = desk,
		trained = 0,
	}
end

-- The first free desk (1..desks) or nil.
function Crew.freeDesk(staff: { Staff }, desks: number): number?
	local used: { [number]: boolean } = {}
	for _, s in staff do
		used[s.desk] = true
	end
	for d = 1, desks do
		if not used[d] then
			return d
		end
	end
	return nil
end

-- How much a training session adds to a skill now at `level`: TrainMax at 0 down to TrainMin at SkillMax.
function Crew.trainGain(level: number): number
	local t = math.clamp(level / Tuning.SkillMax, 0, 1)
	return math.floor(Tuning.TrainMax - (Tuning.TrainMax - Tuning.TrainMin) * t + 0.5)
end

function Crew.tired(s: Staff): boolean
	return s.energy < Tuning.EnergyTired
end

-- The developer's output multiplier this week.
function Crew.rate(s: Staff): number
	return if Crew.tired(s) then Tuning.TiredRate else 1
end

-- A week of work or rest.
function Crew.energyWeek(s: Staff, working: boolean)
	if working then
		s.energy = math.max(0, s.energy - Tuning.EnergyWork)
	else
		s.energy = math.min(Tuning.EnergyMax, s.energy + Tuning.EnergyRest)
	end
end

function Crew.partyCost(n: number): number
	return Tuning.PartyPerStaff * n
end

function Crew.payroll(staff: { Staff }): number
	local t = 0
	for _, s in staff do
		t += s.salary
	end
	return t
end

return Crew
