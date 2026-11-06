--!strict
-- Making, reviewing and selling games (GAME_DESIGN 6, 8). Pure: the server calls it with its own Rng, the client for
-- previews (titles, costs, what is open), the specs with fixed seeds.
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Genres = require(script.Parent.Parent.Data.Genres)
local Topics = require(script.Parent.Parent.Data.Topics)
local Matches = require(script.Parent.Parent.Data.Matches)
local Platforms = require(script.Parent.Parent.Data.Platforms)
local Critics = require(script.Parent.Parent.Data.Critics)
local Crew = require(script.Parent.Crew)

type Project = Types.Project
type Release = Types.Release
type Staff = Types.Staff
type Scores = Types.Scores
type Rng = Types.Rng
type Match = Types.Match

local Dev = {}

local AXES: { Types.Axis } = { "fun", "ideas", "graphics", "sound" }
Dev.AXES = AXES
Dev.AXIS_NAMES = { fun = "Fun", ideas = "Ideas", graphics = "Graphics", sound = "Sound" } :: { [string]: string }
Dev.MATCH_NAMES = { great = "Great", good = "Good", okay = "Okay", poor = "Poor" } :: { [string]: string }
Dev.SIZE_ORDER = { "small", "medium", "large" }
Dev.SIZE_NAMES = { small = "Small", medium = "Medium", large = "Large" } :: { [string]: string }

------------------------------------------------------------------ choices
function Dev.match(genre: string, topic: string): Match
	local m = Matches.byGenre[genre]
	if m == nil then
		return "okay"
	end
	if table.find(m.great, topic) then
		return "great"
	elseif table.find(m.good, topic) then
		return "good"
	elseif table.find(m.poor, topic) then
		return "poor"
	end
	return "okay"
end

function Dev.matchKey(genre: string, topic: string): string
	return genre .. "|" .. topic
end

-- Whether a platform is on sale in `year`.
function Dev.onSale(p: Platforms.PlatformDef, year: number): boolean
	return year >= p.from and (p.to == 0 or year <= p.to)
end

function Dev.platformsIn(year: number): { Platforms.PlatformDef }
	local out = {}
	for _, p in Platforms.list do
		if Dev.onSale(p, year) then
			table.insert(out, p)
		end
	end
	return out
end

function Dev.genreCost(id: string): number
	local g = Genres.byId[id]
	return if g then Tuning.GenreRp[g.tier] or 0 else 0
end

function Dev.topicCost(id: string): number
	local t = Topics.byId[id]
	return if t then Tuning.TopicRp[t.tier] or 0 else 0
end

-- What starting a game costs: the size's budget plus the platform's licence.
function Dev.startCost(size: string, platform: string): number
	local sz = Tuning.Sizes[size]
	local p = Platforms.byId[platform]
	return (if sz then sz.cost else 0) + (if p then p.licence else 0)
end

-- The title for a seed: a topic word and a genre word ("Galaxy Blocks"); seeds walk every pair.
function Dev.title(genre: string, topic: string, seed: number): string
	local g = Genres.byId[genre]
	local t = Topics.byId[topic]
	if g == nil or t == nil then
		return "Untitled"
	end
	local n = #g.words * #t.words
	local k = math.floor(seed) % n
	return t.words[k // #g.words + 1] .. " " .. g.words[k % #g.words + 1]
end

-- A sequel number when the studio already released a game with this title: "Galaxy Blocks 2", "... 3".
function Dev.sequelTitle(base: string, releases: { Release }, inProgress: string?): string
	local taken: { [string]: boolean } = {}
	for _, r in releases do
		taken[r.title] = true
	end
	if inProgress then
		taken[inProgress] = true
	end
	if not taken[base] then
		return base
	end
	local n = 2
	while taken[base .. " " .. n] do
		n += 1
	end
	return base .. " " .. n
end

function Dev.newProject(genre: string, topic: string, platform: string, size: string, focus: Types.Axis, title: string, week: number): Project
	local sz = Tuning.Sizes[size]
	return {
		title = title,
		genre = genre,
		topic = topic,
		platform = platform,
		size = size,
		focus = focus,
		startWeek = week,
		buildWeeks = sz.weeks,
		weeksDone = 0,
		phase = "build",
		scores = { fun = 0, ideas = 0, graphics = 0, sound = 0 },
		bugs = 0,
		rp = 0,
		sparks = 0,
		cost = Dev.startCost(size, platform),
	}
end

function Dev.focusMult(focus: string, axis: string): number
	return if focus == axis then Tuning.FocusBoost else Tuning.FocusOther
end

------------------------------------------------------------------ development
-- One developer's raw output a week on each score (before spread, rate and focus).
function Dev.output(s: Types.Skills): Scores
	local r = Tuning.WorkRate
	return {
		fun = (s.code + s.design) / 2 * r,
		ideas = s.design * r,
		graphics = s.art * r,
		sound = s.sound * r,
	}
end

-- Each developer's share of the work in a crew of n: n ^ TeamPower developers' worth, split n ways.
function Dev.teamFactor(n: number): number
	if n <= 1 then
		return 1
	end
	return n ^ Tuning.TeamPower / n
end

-- One week of work on the project by the crew (GAME_DESIGN 6.2). Mutates the project; returns the popups (one per
-- developer: their biggest score this week) and the research points earned. The weeks count up; when the build
-- weeks are done the phase turns to "polish".
function Dev.workWeek(p: Project, staff: { Staff }, rng: Rng): ({ Types.WorkPop }, number)
	local pops: { Types.WorkPop } = {}
	local rp = 0
	local polish = p.phase == "polish"
	local team = Dev.teamFactor(#staff)
	for _, s in staff do
		local out = Dev.output(s.skills)
		local rate = Crew.rate(s) * team * (if polish then Tuning.PolishRate else 1)
		local spark = (not polish) and rng:chance(Tuning.SparkChance)
		local sparkAxis: Types.Axis = AXES[rng:int(1, 4)]
		local bestAxis: Types.Axis, best = "fun", -1
		for _, a in AXES do
			local v = (out :: any)[a] * rate * Dev.focusMult(p.focus, a) * rng:range(1 - Tuning.WorkSpread, 1 + Tuning.WorkSpread)
			if spark and a == sparkAxis then
				v *= Tuning.SparkMult
			end
			v = math.floor(v + 0.5)
			;(p.scores :: any)[a] += v
			-- the popup shows the spark's score, else the week's biggest
			if (spark and a == sparkAxis) or (not spark and v > best) then
				best, bestAxis = v, (a :: any) :: Types.Axis
			end
		end
		if spark then
			p.sparks += 1
			rp += Tuning.SparkRp
		end
		if polish then
			local fix = Tuning.FixBase + s.skills.code // Tuning.FixCode
			p.bugs = math.max(0, p.bugs - fix)
		else
			local chance = math.max(Tuning.BugMin, Tuning.BugBase - s.skills.code / Tuning.BugCode)
			if rng:chance(chance) then
				p.bugs += 1
			end
		end
		rp += Tuning.RpPerWeek
		table.insert(pops, { id = s.id, axis = bestAxis, n = math.max(0, best), spark = spark })
	end
	p.rp += rp
	p.weeksDone += 1
	if p.phase == "build" and p.weeksDone >= p.buildWeeks then
		p.phase = "polish"
	end
	return pops, rp
end

-- 0..1: how far along the build is (1 while polishing).
function Dev.progress(p: Project): number
	if p.phase == "polish" then
		return 1
	end
	return math.clamp(p.weeksDone / math.max(1, p.buildWeeks), 0, 1)
end

------------------------------------------------------------------ reviews
-- The novelty multiplier: NoveltyMult when the pair was one of the last NoveltyLookback releases.
function Dev.novelty(genre: string, topic: string, releases: { Release }): number
	local n = #releases
	for i = n, math.max(1, n - Tuning.NoveltyLookback + 1), -1 do
		local r = releases[i]
		if r.genre == genre and r.topic == topic then
			return Tuning.NoveltyMult
		end
	end
	return 1
end

function Dev.love(platform: string, genre: string): number
	local p = Platforms.byId[platform]
	if p and table.find(p.loves, genre) then
		return Tuning.LoveMult
	end
	return 1
end

-- The game's quality (GAME_DESIGN 6.3) and its match.
function Dev.quality(p: Project, releases: { Release }): (number, Match)
	local w = Tuning.QualityWeights
	local s = p.scores
	local raw = s.fun * w.fun + s.ideas * w.ideas + s.graphics * w.graphics + s.sound * w.sound
	local m: Match = Dev.match(p.genre, p.topic)
	local q = raw * Tuning.MatchMult[m] * Dev.love(p.platform, p.genre) * Dev.novelty(p.genre, p.topic, releases)
	return math.max(0, q - Tuning.BugPenalty * p.bugs), m
end

function Dev.expectation(size: string, year: number): number
	local sz = Tuning.Sizes[size]
	return Tuning.ExpectBase * (if sz then sz.expect else 1) * (1 + Tuning.ExpectYearly * (math.max(1, year) - 1))
end

-- 1..10 (not rounded): Q = E gives 5.5.
function Dev.baseScore(q: number, e: number): number
	return 1 + 9 * (1 - 2 ^ (-q / math.max(1, e)))
end

-- The four critics' reviews (Data/Critics order), their total and the match. Each critic gives the base score plus
-- up to CriticLean for how much of the game is their favourite score (a quarter is neutral), plus a wobble.
function Dev.reviews(p: Project, year: number, releases: { Release }, rng: Rng): ({ number }, number, Match)
	local q: number, m: Match = Dev.quality(p, releases)
	local base = Dev.baseScore(q, Dev.expectation(p.size, year))
	local s = p.scores
	local sum = math.max(1, s.fun + s.ideas + s.graphics + s.sound)
	local out = {}
	local total = 0
	for _, c in Critics.list do
		local share = (s :: any)[c.axis] / sum
		local lean = math.clamp((share - 0.25) * 8, -1, 1) * Tuning.CriticLean
		local wob = rng:range(-Tuning.CriticWobble, Tuning.CriticWobble)
		local v = math.clamp(math.floor(base + lean + wob + 0.5), 1, 10)
		table.insert(out, v)
		total += v
	end
	return out, total, m
end

------------------------------------------------------------------ sales
-- Week-one copies and the weekly decay of a game with this review total (GAME_DESIGN 6.4).
function Dev.salesPlan(total: number, fans: number, platform: string, size: string): (number, number)
	local avg = total / 4
	local p = Platforms.byId[platform]
	local sz = Tuning.Sizes[size]
	local qf = (avg / Tuning.SalesPivot) ^ Tuning.SalesPower
	local peak = (Tuning.SalesBase * (if p then p.market else 1) * (if sz then sz.sales else 1) + Tuning.FanBuy * fans) * qf
	return math.floor(peak + 0.5), Tuning.DecayBase + Tuning.DecayPerPoint * avg
end

-- A release from a finished project.
function Dev.release(p: Project, id: number, week: number, reviews: { number }, total: number, m: Match, fans: number): Release
	local peak, decay = Dev.salesPlan(total, fans, p.platform, p.size)
	return {
		id = id,
		title = p.title,
		genre = p.genre,
		topic = p.topic,
		platform = p.platform,
		size = p.size,
		focus = p.focus,
		week = week,
		scores = table.clone(p.scores),
		bugs = p.bugs,
		reviews = reviews,
		total = total,
		match = m,
		hof = total >= Tuning.HallOfFame,
		peak = peak,
		decay = decay,
		weeks = 0,
		last = 0,
		copies = 0,
		revenue = 0,
		fans = 0,
		onSale = true,
	}
end

-- One week of sales of a release on sale: mutates it, returns (copies, money, fans) for the week.
function Dev.salesWeek(r: Release): (number, number, number)
	if not r.onSale then
		return 0, 0, 0
	end
	local copies = math.floor(r.peak * r.decay ^ r.weeks + 0.5)
	r.weeks += 1
	if copies < Tuning.SalesMinWeek or r.weeks >= Tuning.SalesMaxWeeks then
		r.onSale = false
	end
	local sz = Tuning.Sizes[r.size]
	local money = math.floor(copies * (if sz then sz.price else 10) * Tuning.StudioCut + 0.5)
	local fans = math.floor(copies * Tuning.FanPerCopy * (if r.hof then Tuning.FanHofMult else 1) + 0.5)
	r.last = copies
	r.copies += copies
	r.revenue += money
	r.fans += fans
	return copies, money, fans
end

------------------------------------------------------------------ awards
-- The awards night for `year` (GAME_DESIGN 8): the best release of that year and what it won ("goty" / "pick"), or
-- nil. Ties go to the earlier game.
function Dev.award(releases: { Release }, year: number, weeksPerYear: number): (string?, Release?)
	local best: Release? = nil
	for _, r in releases do
		if r.week // weeksPerYear + 1 == year and (best == nil or r.total > best.total) then
			best = r
		end
	end
	if best == nil then
		return nil, nil
	end
	if best.total >= Tuning.GotyTotal then
		return "goty", best
	elseif best.total >= Tuning.PickTotal then
		return "pick", best
	end
	return nil, best
end

function Dev.adCost(office: number): number
	return Tuning.AdCost * office
end

function Dev.adFans(office: number): number
	return Tuning.AdFans * office
end

return Dev
