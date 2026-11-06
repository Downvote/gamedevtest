--!strict
-- The studio's rules over a profile (GAME_DESIGN 3-8; docs/ARCHITECTURE.md 6): one game week, and every player
-- action. Pure: StudioService calls these with the session's profile and its own Rng and sends what they return;
-- the Economy spec plays whole careers through the very same functions.
-- Every action returns (true, data?) or (false, ErrCode) and changes the profile only when it succeeds.
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Genres = require(script.Parent.Parent.Data.Genres)
local Topics = require(script.Parent.Parent.Data.Topics)
local Platforms = require(script.Parent.Parent.Data.Platforms)
local Calendar = require(script.Parent.Calendar)
local Crew = require(script.Parent.Crew)
local Dev = require(script.Parent.Dev)

type Profile = Types.Profile
type Rng = Types.Rng
type ErrCode = Types.ErrCode

-- What a week did, for the client's notices and popups (Fx messages; docs/ARCHITECTURE.md 7.4).
export type Event = {
	kind: string, -- "pay" | "candidates" | "work" | "built" | "ready" | "sales" | "award" | "platform" | "broke"
	pops: { Types.WorkPop }?,
	amount: number?, -- pay: what was paid; sales: the week's money
	copies: number?, -- sales: the week's copies
	fans: number?, -- sales / award: fans won
	title: string?, -- award: the game; platform: the platform's name
	award: string?, -- "goty" | "pick"
	total: number?,
	year: number?,
}

local Studio = {}

------------------------------------------------------------------ helpers
function Studio.year(p: Profile): number
	return Calendar.year(p.week)
end

function Studio.desks(p: Profile): number
	return Tuning.Offices[p.office].desks
end

function Studio.staffById(p: Profile, id: number): Types.Staff?
	for _, s in p.staff do
		if s.id == id then
			return s
		end
	end
	return nil
end

function Studio.canAd(p: Profile): boolean
	return p.lastAd < Calendar.month(p.week)
end

function Studio.canParty(p: Profile): boolean
	return p.lastParty < Calendar.month(p.week)
end

-- The tips banner (GAME_DESIGN 9) moves on when its step is done.
local function tutTo(p: Profile, from: number, to: number)
	if p.tut == from then
		p.tut = to
	end
end

------------------------------------------------------------------ the week
-- One game week (GAME_DESIGN 3): on a month's first week the salaries and rent are paid and new candidates arrive;
-- the crew works on the project (or rests); every release on sale sells; after a year's last week the awards
-- night. Then the calendar moves on.
function Studio.week(p: Profile, rng: Rng): { Event }
	local events: { Event } = {}
	local week = p.week
	local year = Calendar.year(week)
	if Calendar.isMonthStart(week) then
		local bill = Crew.payroll(p.staff) + Tuning.Offices[p.office].rent
		if week > 0 then
			p.money -= bill
			table.insert(events, { kind = "pay", amount = bill })
			if p.money < 0 then
				table.insert(events, { kind = "broke" })
			end
		end
		local month = Calendar.month(week)
		if p.candMonth ~= month then
			p.candidates = Crew.candidates(rng, year)
			p.candMonth = month
			table.insert(events, { kind = "candidates" })
		end
		-- a new platform on the year's first week
		if week % Calendar.WEEKS_PER_YEAR == 0 and year > 1 then
			for _, pl in Platforms.list do
				if pl.from == year then
					table.insert(events, { kind = "platform", title = pl.name })
				end
			end
		end
	end
	local proj = p.project
	if proj then
		local before = proj.phase
		local hadBugs = proj.bugs > 0
		local pops, rp = Dev.workWeek(proj, p.staff, rng)
		p.rp += rp
		table.insert(events, { kind = "work", pops = pops })
		if before == "build" and proj.phase == "polish" then
			table.insert(events, { kind = "built", title = proj.title })
			tutTo(p, 2, 3)
		elseif before == "polish" and hadBugs and proj.bugs == 0 then
			table.insert(events, { kind = "ready", title = proj.title })
		end
	end
	for _, s in p.staff do
		Crew.energyWeek(s, proj ~= nil)
	end
	local copies, money, fans = 0, 0, 0
	for _, r in p.releases do
		if r.onSale then
			local c, m, f = Dev.salesWeek(r)
			copies += c
			money += m
			fans += f
		end
	end
	if copies > 0 then
		p.money += money
		p.fans += fans
		p.stats.copies += copies
		p.stats.revenue += money
		table.insert(events, { kind = "sales", copies = copies, amount = money, fans = fans })
	end
	if Calendar.isYearEnd(week) then
		local kind, best = Dev.award(p.releases, year, Calendar.WEEKS_PER_YEAR)
		if kind and best then
			local share = if kind == "goty" then Tuning.GotyFans else Tuning.PickFans
			local prize = (if kind == "goty" then Tuning.GotyMoney else Tuning.PickMoney) * year
			local won = math.floor(p.fans * share + 0.5)
			p.fans += won
			p.money += prize
			table.insert(p.awards, { year = year, kind = kind, title = best.title, total = best.total })
			table.insert(events, { kind = "award", award = kind, title = best.title, total = best.total, fans = won, amount = prize, year = year })
		end
	end
	p.week += 1
	return events
end

------------------------------------------------------------------ actions
-- The safety net (GAME_DESIGN 4): a broke studio can always start a small Home PC game, for free, so no studio is
-- ever stuck with nothing to sell.
function Studio.rescue(p: Profile, size: string, platform: string): boolean
	return p.money < 0 and size == Tuning.RescueSize and platform == Tuning.RescuePlatform
end

export type StartArgs = { genre: string, topic: string, platform: string, size: string, focus: Types.Axis, seed: number }

-- The title a start with this seed would get (the Shuffle button previews it).
function Studio.titleFor(p: Profile, genre: string, topic: string, seed: number): string
	return Dev.sequelTitle(Dev.title(genre, topic, seed), p.releases, nil)
end

function Studio.start(p: Profile, a: StartArgs): (boolean, any)
	if p.project ~= nil then
		return false, "busy" :: ErrCode
	end
	if Genres.byId[a.genre] == nil or Topics.byId[a.topic] == nil or Tuning.Sizes[a.size] == nil then
		return false, "bad_payload" :: ErrCode
	end
	if not p.genres[a.genre] or not p.topics[a.topic] then
		return false, "locked" :: ErrCode
	end
	local pl = Platforms.byId[a.platform]
	if pl == nil or not Dev.onSale(pl, Studio.year(p)) then
		return false, "unavailable" :: ErrCode
	end
	local cost = Dev.startCost(a.size, a.platform)
	if Studio.rescue(p, a.size, a.platform) then
		cost = 0
	elseif p.money < cost then
		return false, "money" :: ErrCode
	end
	p.money -= cost
	local title = Studio.titleFor(p, a.genre, a.topic, a.seed)
	p.project = Dev.newProject(a.genre, a.topic, a.platform, a.size, a.focus, title, p.week)
	tutTo(p, 1, 2)
	return true, { title = title, cost = cost }
end

-- Ship the project (any time after the build is done): the reviews, the match learned, the release on sale.
function Studio.release(p: Profile, rng: Rng): (boolean, any)
	local proj = p.project
	if proj == nil then
		return false, "no_project" :: ErrCode
	end
	if proj.phase ~= "polish" then
		return false, "not_built" :: ErrCode
	end
	local reviews: { number }, total: number, m: Types.Match = Dev.reviews(proj, Studio.year(p), p.releases, rng)
	local r = Dev.release(proj, p.nextRelease, p.week, reviews, total, m, p.fans)
	p.nextRelease += 1
	table.insert(p.releases, r)
	while #p.releases > Tuning.ReleasesKept do
		table.remove(p.releases, 1)
	end
	p.matches[Dev.matchKey(proj.genre, proj.topic)] = m
	p.project = nil
	p.stats.games += 1
	if r.hof then
		p.stats.hof += 1
	end
	p.stats.best = math.max(p.stats.best, total)
	tutTo(p, 3, 4)
	tutTo(p, 2, 4)
	return true, r
end

function Studio.hire(p: Profile, i: number): (boolean, any)
	local c = p.candidates[i]
	if c == nil then
		return false, "bad_payload" :: ErrCode
	end
	local desk = Crew.freeDesk(p.staff, Studio.desks(p))
	if desk == nil then
		return false, "full" :: ErrCode
	end
	local fee = Crew.salary(c.skills)
	if p.money < fee then
		return false, "money" :: ErrCode
	end
	p.money -= fee
	local s = Crew.hire(c, p.nextStaff, desk)
	p.nextStaff += 1
	table.insert(p.staff, s)
	table.remove(p.candidates, i)
	tutTo(p, 4, 0)
	return true, s
end

function Studio.fire(p: Profile, id: number): (boolean, any)
	if #p.staff <= 1 then
		return false, "last" :: ErrCode
	end
	for i, s in p.staff do
		if s.id == id then
			table.remove(p.staff, i)
			return true, nil
		end
	end
	return false, "bad_payload" :: ErrCode
end

function Studio.train(p: Profile, id: number, skill: Types.SkillKey): (boolean, any)
	local s = Studio.staffById(p, id)
	if s == nil then
		return false, "bad_payload" :: ErrCode
	end
	local level = (s.skills :: any)[skill] :: number
	if level >= Tuning.SkillMax then
		return false, "max" :: ErrCode
	end
	if p.rp < Tuning.TrainRp then
		return false, "rp" :: ErrCode
	end
	if p.money < Tuning.TrainMoney then
		return false, "money" :: ErrCode
	end
	p.rp -= Tuning.TrainRp
	p.money -= Tuning.TrainMoney
	local gain = Crew.trainGain(level)
	;(s.skills :: any)[skill] = math.min(Tuning.SkillMax, level + gain)
	s.salary = Crew.salary(s.skills)
	s.energy = math.max(0, s.energy - Tuning.TrainEnergy)
	s.trained += 1
	return true, { gain = gain }
end

function Studio.party(p: Profile): (boolean, any)
	if not Studio.canParty(p) then
		return false, "cooldown" :: ErrCode
	end
	local cost = Crew.partyCost(#p.staff)
	if p.money < cost then
		return false, "money" :: ErrCode
	end
	p.money -= cost
	p.lastParty = Calendar.month(p.week)
	for _, s in p.staff do
		s.energy = Tuning.EnergyMax
	end
	return true, { cost = cost }
end

local function unlock(p: Profile, set: { [string]: boolean }, id: string, cost: number, known: boolean): (boolean, any)
	if not known then
		return false, "bad_payload" :: ErrCode
	end
	if set[id] then
		return false, "max" :: ErrCode
	end
	if p.rp < cost then
		return false, "rp" :: ErrCode
	end
	p.rp -= cost
	set[id] = true
	return true, { cost = cost }
end

function Studio.unlockGenre(p: Profile, id: string): (boolean, any)
	return unlock(p, p.genres, id, Dev.genreCost(id), Genres.byId[id] ~= nil)
end

function Studio.unlockTopic(p: Profile, id: string): (boolean, any)
	return unlock(p, p.topics, id, Dev.topicCost(id), Topics.byId[id] ~= nil)
end

function Studio.move(p: Profile): (boolean, any)
	local nextTier = p.office + 1
	local spec = Tuning.Offices[nextTier]
	if spec == nil then
		return false, "max" :: ErrCode
	end
	if p.fans < spec.fans then
		return false, "fans" :: ErrCode
	end
	if p.money < spec.cost then
		return false, "money" :: ErrCode
	end
	p.money -= spec.cost
	p.office = nextTier
	return true, { office = nextTier }
end

function Studio.ad(p: Profile): (boolean, any)
	if not Studio.canAd(p) then
		return false, "cooldown" :: ErrCode
	end
	local cost = Dev.adCost(p.office)
	if p.money < cost then
		return false, "money" :: ErrCode
	end
	local fans = Dev.adFans(p.office)
	p.money -= cost
	p.fans += fans
	p.lastAd = Calendar.month(p.week)
	return true, { cost = cost, fans = fans }
end

return Studio
