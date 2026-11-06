--!strict
-- The save's shape (docs/ARCHITECTURE.md 7.6): default, migrate, reconcile, sanitize. Pure.
-- Never rename a field or the DataStore (Tuning.DataStoreName): change the shape with a new VERSION and a step in
-- migrate, and keep a profile from before loading (tests/specs/Schema.spec.luau).
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Genres = require(script.Parent.Parent.Data.Genres)
local Topics = require(script.Parent.Parent.Data.Topics)
local Platforms = require(script.Parent.Parent.Data.Platforms)
local Looks = require(script.Parent.Parent.Data.Looks)
local Decor = require(script.Parent.Parent.Data.Decor)
local Util = require(script.Parent.Util)
local Crew = require(script.Parent.Crew)
local Plot = require(script.Parent.Plot)

type Profile = Types.Profile

local Schema = {}

Schema.VERSION = 2 -- 1: the first shape; 2: the founder's look and the plot (GAME_DESIGN 12, 13)

local function num(v: any, default: number, lo: number?, hi: number?): number
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return default
	end
	if lo and v < lo then
		return lo
	end
	if hi and v > hi then
		return hi
	end
	return v
end

local function int(v: any, default: number, lo: number?, hi: number?): number
	return math.floor(num(v, default, lo, hi))
end

local function str(v: any, default: string, maxLen: number?): string
	if type(v) ~= "string" then
		return default
	end
	return string.sub(v, 1, maxLen or 60)
end

local AXIS: { [string]: boolean } = { fun = true, ideas = true, graphics = true, sound = true }
local MATCH: { [string]: boolean } = { great = true, good = true, okay = true, poor = true }

local function matchOf(v: any): Types.Match
	if v == "great" then
		return "great"
	elseif v == "good" then
		return "good"
	elseif v == "poor" then
		return "poor"
	end
	return "okay"
end

local function skills(v: any): Types.Skills
	local t = if type(v) == "table" then v else {}
	return {
		code = int(t.code, 1, 0, Tuning.SkillMax),
		design = int(t.design, 1, 0, Tuning.SkillMax),
		art = int(t.art, 1, 0, Tuning.SkillMax),
		sound = int(t.sound, 1, 0, Tuning.SkillMax),
	}
end

local function scores(v: any): Types.Scores
	local t = if type(v) == "table" then v else {}
	return { fun = int(t.fun, 0, 0), ideas = int(t.ideas, 0, 0), graphics = int(t.graphics, 0, 0), sound = int(t.sound, 0, 0) }
end

local function look(v: any): Types.Look
	local t = if type(v) == "table" then v else {}
	return {
		skin = int(t.skin, 1, 1, #Looks.skin),
		hair = int(t.hair, 1, 1, #Looks.hair),
		style = int(t.style, 1, 1, #Looks.styles),
		shirt = int(t.shirt, 1, 1, #Looks.shirt),
	}
end

local function sizeId(v: any): string
	return if type(v) == "string" and Tuning.Sizes[v] ~= nil then v else "small"
end

local function genreId(v: any): string
	return if type(v) == "string" and Genres.byId[v] ~= nil then v else "action"
end

local function topicId(v: any): string
	return if type(v) == "string" and Topics.byId[v] ~= nil then v else "space"
end

local function platformId(v: any): string
	return if type(v) == "string" and Platforms.byId[v] ~= nil then v else "pc"
end

local function axis(v: any): Types.Axis
	return if type(v) == "string" and AXIS[v] then (v :: any) :: Types.Axis else "fun"
end

------------------------------------------------------------------ default
-- A new studio: Tuning's start money, fans and research, StartStaff developers (from `seed`), the tier 1 genres
-- and topics open, the tips banner at step 1.
function Schema.default(now: number, seed: number): Profile
	local rng = Util.newRng(seed)
	local staff = {}
	for i = 1, Tuning.StartStaff do
		table.insert(staff, Crew.hire(Crew.candidate(rng, 1), i, i))
	end
	local founder = Crew.randomLook(rng)
	local genres, topics = {}, {}
	for _, g in Genres.list do
		if g.tier == 1 then
			genres[g.id] = true
		end
	end
	for _, t in Topics.list do
		if t.tier == 1 then
			topics[t.id] = true
		end
	end
	return {
		v = Schema.VERSION,
		money = Tuning.StartMoney,
		fans = Tuning.StartFans,
		rp = Tuning.StartRp,
		week = 0,
		office = 1,
		staff = staff,
		nextStaff = #staff + 1,
		candidates = {},
		candMonth = -1,
		project = nil,
		releases = {},
		nextRelease = 1,
		genres = genres,
		topics = topics,
		matches = {},
		lastAd = -1,
		lastParty = -1,
		awards = {},
		tut = 1,
		stats = { games = 0, copies = 0, revenue = 0, hof = 0, best = 0 },
		settings = { pixel = "high" },
		createdAt = now,
		founder = founder,
		plot = { owned = {}, placed = {} },
	}
end

------------------------------------------------------------------ migrate
-- Brings an older save up to VERSION (each step one version).
--   1 -> 2: a founder's look and an empty plot. Nothing in the old save moves; reconcile gives the founder the new
--           default's look (from the player's seed) and the plot no decor.
function Schema.migrate(raw: { [string]: any }): { [string]: any }
	local v = if type(raw.v) == "number" then raw.v else 1
	if v < 2 then
		raw.founder = nil
		raw.plot = nil
		v = 2
	end
	raw.v = math.max(v, Schema.VERSION)
	return raw
end

------------------------------------------------------------------ reconcile + sanitize
local function staffOf(v: any, desks: number): { Types.Staff }
	local out: { Types.Staff } = {}
	if type(v) ~= "table" then
		return out
	end
	local usedDesk: { [number]: boolean } = {}
	local usedId: { [number]: boolean } = {}
	for _, s in v do
		if type(s) == "table" and #out < desks then
			local id = int(s.id, 0, 0)
			if id > 0 and not usedId[id] then
				usedId[id] = true
				local sk = skills(s.skills)
				local desk = int(s.desk, 0, 0, desks)
				if desk < 1 or usedDesk[desk] then
					desk = 0
				end
				table.insert(out, {
					id = id,
					name = str(s.name, "Dev " .. id, 40),
					skills = sk,
					energy = num(s.energy, Tuning.EnergyMax, 0, Tuning.EnergyMax),
					salary = Crew.salary(sk),
					look = look(s.look),
					desk = desk,
					trained = int(s.trained, 0, 0),
				})
				if desk > 0 then
					usedDesk[desk] = true
				end
			end
		end
	end
	-- anyone without a desk takes the first free one
	for _, s in out do
		if s.desk == 0 then
			for d = 1, desks do
				if not usedDesk[d] then
					s.desk = d
					usedDesk[d] = true
					break
				end
			end
		end
	end
	return out
end

local function candidatesOf(v: any): { Types.Candidate }
	local out: { Types.Candidate } = {}
	if type(v) ~= "table" then
		return out
	end
	for _, c in v do
		if type(c) == "table" and #out < Tuning.Candidates then
			local sk = skills(c.skills)
			table.insert(out, { name = str(c.name, "Candidate", 40), skills = sk, salary = Crew.salary(sk), look = look(c.look) })
		end
	end
	return out
end

local function projectOf(v: any): Types.Project?
	if type(v) ~= "table" then
		return nil
	end
	local size = sizeId(v.size)
	local build = Tuning.Sizes[size].weeks
	local done = int(v.weeksDone, 0, 0)
	return {
		title = str(v.title, "Untitled", 40),
		genre = genreId(v.genre),
		topic = topicId(v.topic),
		platform = platformId(v.platform),
		size = size,
		focus = axis(v.focus),
		startWeek = int(v.startWeek, 0, 0),
		buildWeeks = build,
		weeksDone = done,
		phase = if v.phase == "polish" or done >= build then "polish" else "build",
		scores = scores(v.scores),
		bugs = int(v.bugs, 0, 0),
		rp = int(v.rp, 0, 0),
		sparks = int(v.sparks, 0, 0),
		cost = int(v.cost, 0, 0),
		pushes = int(v.pushes, 0, 0, Tuning.MiniMaxPushes),
		nextPush = int(v.nextPush, 0, 0, 8),
		squashWeek = int(v.squashWeek, 0, 0),
		played = int(v.played, 0, 0),
	}
end

local function releasesOf(v: any): { Types.Release }
	local out: { Types.Release } = {}
	if type(v) ~= "table" then
		return out
	end
	for _, r in v do
		if type(r) == "table" then
			local reviews = {}
			if type(r.reviews) == "table" then
				for i = 1, 4 do
					table.insert(reviews, int(r.reviews[i], 1, 1, 10))
				end
			else
				reviews = { 1, 1, 1, 1 }
			end
			local total = reviews[1] + reviews[2] + reviews[3] + reviews[4]
			table.insert(out, {
				id = int(r.id, #out + 1, 1),
				title = str(r.title, "Untitled", 40),
				genre = genreId(r.genre),
				topic = topicId(r.topic),
				platform = platformId(r.platform),
				size = sizeId(r.size),
				focus = axis(r.focus),
				week = int(r.week, 0, 0),
				scores = scores(r.scores),
				bugs = int(r.bugs, 0, 0),
				reviews = reviews,
				total = total,
				match = matchOf(r.match),
				hof = total >= Tuning.HallOfFame,
				peak = int(r.peak, 0, 0),
				decay = num(r.decay, 0.8, 0, 0.99),
				weeks = int(r.weeks, 0, 0),
				last = int(r.last, 0, 0),
				copies = int(r.copies, 0, 0),
				revenue = int(r.revenue, 0, 0),
				fans = int(r.fans, 0, 0),
				onSale = r.onSale == true,
			})
		end
	end
	while #out > Tuning.ReleasesKept do
		table.remove(out, 1)
	end
	return out
end

-- The plot: owned decor that exists; pieces of owned decor that fit the office's plot, in order, up to its limit.
local function plotOf(v: any, office: number): Types.PlotSave
	local t = if type(v) == "table" then v else {}
	local owned: { [string]: boolean } = {}
	if type(t.owned) == "table" then
		for id, on in t.owned do
			if type(id) == "string" and Decor.byId[id] ~= nil and on == true then
				owned[id] = true
			end
		end
	end
	local placed: { Types.Piece } = {}
	if type(t.placed) == "table" then
		for _, q in t.placed do
			if type(q) == "table" and type(q.id) == "string" and owned[q.id] and #placed < Plot.limit(office) then
				local x, z, rot = int(q.x, 0, -64, 64), int(q.z, 0, -64, 64), int(q.rot, 0)
				if Plot.fits(office, placed, q.id, x, z, rot) then
					table.insert(placed, { id = q.id, x = x, z = z, rot = rot })
				end
			end
		end
	end
	return { owned = owned, placed = placed }
end

local function setOf(v: any, valid: { [string]: any }): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(v) == "table" then
		for k, on in v do
			if type(k) == "string" and valid[k] ~= nil and on == true then
				out[k] = true
			end
		end
	end
	return out
end

-- Any table (a save, an older save, garbage) -> a valid Profile: known fields kept when their type and range are
-- right, everything else from the default. `seed` makes the default's crew when the save has none.
function Schema.reconcile(raw: any, now: number, seed: number): Profile
	local d = Schema.default(now, seed)
	if type(raw) ~= "table" then
		return d
	end
	local r = Schema.migrate(raw)
	local office = int(r.office, 1, 1, #Tuning.Offices)
	local desks = Tuning.Offices[office].desks
	local staff = staffOf(r.staff, desks)
	if #staff == 0 then
		staff = d.staff
	end
	local maxId = 0
	for _, s in staff do
		maxId = math.max(maxId, s.id)
	end
	local releases = releasesOf(r.releases)
	local maxRel = 0
	for _, x in releases do
		maxRel = math.max(maxRel, x.id)
	end
	local genres = setOf(r.genres, Genres.byId)
	local topics = setOf(r.topics, Topics.byId)
	for k in d.genres do
		genres[k] = true
	end
	for k in d.topics do
		topics[k] = true
	end
	local matches: { [string]: Types.Match } = {}
	if type(r.matches) == "table" then
		for k, m in r.matches do
			if type(k) == "string" and type(m) == "string" and MATCH[m] then
				local g, t = string.match(k, "^(%w+)|(%w+)$")
				if g and t and Genres.byId[g] and Topics.byId[t] then
					matches[k] = matchOf(m)
				end
			end
		end
	end
	local awards: { Types.Award } = {}
	if type(r.awards) == "table" then
		for _, a in r.awards do
			if type(a) == "table" and (a.kind == "goty" or a.kind == "pick") then
				local award: Types.Award = { year = int(a.year, 1, 1), kind = tostring(a.kind), title = str(a.title, "Untitled", 40), total = int(a.total, 0, 0, 40) }
				table.insert(awards, award)
			end
		end
	end
	local st = if type(r.stats) == "table" then r.stats else {}
	local settings = if type(r.settings) == "table" then r.settings else {}
	local pixel = settings.pixel
	return {
		v = Schema.VERSION,
		money = num(r.money, d.money),
		fans = int(r.fans, d.fans, 0),
		rp = int(r.rp, d.rp, 0),
		week = int(r.week, 0, 0),
		office = office,
		staff = staff,
		nextStaff = math.max(int(r.nextStaff, 1, 1), maxId + 1),
		candidates = candidatesOf(r.candidates),
		candMonth = int(r.candMonth, -1, -1),
		project = projectOf(r.project),
		releases = releases,
		nextRelease = math.max(int(r.nextRelease, 1, 1), maxRel + 1),
		genres = genres,
		topics = topics,
		matches = matches,
		lastAd = int(r.lastAd, -1, -1),
		lastParty = int(r.lastParty, -1, -1),
		awards = awards,
		tut = int(r.tut, 1, 0, 4),
		stats = {
			games = int(st.games, #releases, 0),
			copies = int(st.copies, 0, 0),
			revenue = int(st.revenue, 0, 0),
			hof = int(st.hof, 0, 0),
			best = int(st.best, 0, 0, 40),
		},
		settings = {
			pixel = if pixel == "high" or pixel == "medium" or pixel == "low" or pixel == "off" then pixel else "high",
		},
		createdAt = num(r.createdAt, now),
		founder = if type(r.founder) == "table" then look(r.founder) else d.founder,
		plot = plotOf(r.plot, office),
	}
end

return Schema
