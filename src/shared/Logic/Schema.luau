--!strict
-- The save's shape (docs/ARCHITECTURE.md 7.6): default, migrate, reconcile. Pure.
-- Never rename a field or the DataStore (Tuning.DataStoreName): change the shape with a new VERSION and a step in
-- migrate, and keep a profile from before loading (tests/specs/Schema.spec.luau).
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Looks = require(script.Parent.Parent.Data.Looks)
local Decor = require(script.Parent.Parent.Data.Decor)
local Office = require(script.Parent.Parent.Data.Office)
local Modifiers = require(script.Parent.Parent.Data.Modifiers)
local Util = require(script.Parent.Util)
local Ideas = require(script.Parent.Ideas)
local Studio = require(script.Parent.Studio)
local Live = require(script.Parent.Live)
local Plot = require(script.Parent.Plot)

type Profile = Types.Profile
type Card = Types.Card

local Schema = {}

-- 1: the first shape; 2: the founder's look and the plot; 3: the idea loop (GAME_DESIGN 1: the old studio is gone);
-- 4: one game on sale at a time (GAME_DESIGN 6: Profile.live, no more income from every game)
Schema.VERSION = 4

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

local function look(v: any): Types.Look
	local t = if type(v) == "table" then v else {}
	return {
		skin = int(t.skin, 1, 1, #Looks.skin),
		hair = int(t.hair, 1, 1, #Looks.hair),
		style = int(t.style, 1, 1, #Looks.styles),
		shirt = int(t.shirt, 1, 1, #Looks.shirt),
	}
end

-- A modifier id, renamed when it is one that went (Data/Modifiers.renamed: the one with its odds took its place).
local function modId(m: any): any
	return if type(m) == "string" and Modifiers.renamed[m] then Modifiers.renamed[m] else m
end

local function card(v: any): Card?
	if type(v) == "table" and Ideas.valid({ id = v.id, mod = modId(v.mod) }) then
		return { id = v.id, mod = modId(v.mod) }
	end
	return nil
end

local function cards(v: any, max: number): { Card }
	local out: { Card } = {}
	if type(v) == "table" then
		for _, c in v do
			local ok = card(c)
			if ok and #out < max then
				table.insert(out, ok)
			end
		end
	end
	return out
end

local function desksOf(office: number): number
	return #Office.plan(office).desks
end

------------------------------------------------------------------ default
-- A new studio: Tuning.StartCoins, an idea team of Tuning.TeamSize (from `seed`) in the garage, an empty board.
function Schema.default(now: number, seed: number): Profile
	local rng = Util.newRng(seed)
	local team = Studio.newTeam(rng, math.min(Tuning.TeamSize, desksOf(1)))
	return {
		v = Schema.VERSION,
		coins = Tuning.StartCoins,
		ideas = {},
		found = {},
		project = nil,
		games = {},
		live = nil,
		nextGame = 1,
		upgrades = { speed = 0, luck = 0 },
		team = team,
		office = 1,
		tut = 1,
		stats = { games = 0, rolls = 0, best = 0, earned = 0 },
		settings = { pixel = "high" },
		createdAt = now,
		founder = Studio.randomLook(rng),
		plot = { owned = {}, placed = {} },
	}
end

------------------------------------------------------------------ migrate
-- Brings an older save up to VERSION (each step one version).
--   1 -> 2: a founder's look and an empty plot (reconcile fills them in).
--   2 -> 3: the idea loop. The old studio's money, fans, research, releases and crew rules are gone; the founder, the
--           decor bought and placed, the office's room and the crew's names and looks (now the idea team) stay.
--   3 -> 4: the games no longer all earn for good: the newest one goes on sale afresh (reconcile), the rate is gone.
function Schema.migrate(raw: { [string]: any }): { [string]: any }
	local v = if type(raw.v) == "number" then raw.v else 1
	if v < 2 then
		raw.founder = nil
		raw.plot = nil
		v = 2
	end
	if v < 3 then
		raw.team = raw.staff
		for _, k in { "money", "fans", "rp", "week", "staff", "nextStaff", "candidates", "candMonth", "project", "releases", "nextRelease", "genres", "topics", "matches", "lastAd", "lastParty", "awards", "stats" } do
			raw[k] = nil
		end
		raw.tut = 1
		v = 3
	end
	if v < 4 then
		raw.rate = nil
		raw.live = nil
		raw.liveNewest = true
		v = 4
	end
	raw.v = math.max(v, Schema.VERSION)
	return raw
end

------------------------------------------------------------------ reconcile
local function teamOf(v: any, desks: number): { Types.Member }
	local out: { Types.Member } = {}
	if type(v) ~= "table" then
		return out
	end
	local usedDesk: { [number]: boolean } = {}
	for _, m in v do
		if type(m) == "table" and #out < math.min(desks, Tuning.TeamSize) then
			local desk = int(m.desk, 0, 0, desks)
			if desk < 1 or usedDesk[desk] then
				desk = 0
			end
			if desk > 0 then
				usedDesk[desk] = true
			end
			table.insert(out, { id = #out + 1, name = str(m.name, "Thinker", 40), look = look(m.look), desk = desk })
		end
	end
	for _, m in out do
		if m.desk == 0 then
			for d = 1, desks do
				if not usedDesk[d] then
					m.desk = d
					usedDesk[d] = true
					break
				end
			end
		end
	end
	return out
end

local function projectOf(v: any): Types.Making?
	if type(v) ~= "table" then
		return nil
	end
	local list = cards(v.ideas, 3)
	if #list ~= 3 then
		return nil
	end
	local won = {}
	for i = 1, 3 do
		won[i] = int(if type(v.won) == "table" then v.won[i] else nil, -1, -1, 1)
	end
	return { title = str(v.title, "Untitled", 60), ideas = list, won = won, seed = int(v.seed, 0, 0) }
end

local function gamesOf(v: any): { Types.Game }
	local out: { Types.Game } = {}
	if type(v) ~= "table" then
		return out
	end
	for _, g in v do
		if type(g) == "table" then
			local list = cards(g.ideas, 3)
			if #list == 3 then
				local wins = int(g.wins, 0, 0, 3)
				table.insert(out, {
					id = int(g.id, #out + 1, 1),
					title = str(g.title, "Untitled", 60),
					ideas = list,
					rate = Ideas.rate(list, wins),
					wins = wins,
					at = int(g.at, 0, 0),
					peak = int(g.peak, 0, 0),
					earned = int(g.earned, 0, 0),
				})
			end
		end
	end
	while #out > Tuning.GamesKept do
		table.remove(out, 1)
	end
	return out
end

-- The game on sale: kept when it is one of the listed games and its numbers make sense (its curve's height follows
-- the game's rate, so a retune moves it too).
local function liveOf(v: any, games: { Types.Game }): Types.Live?
	if type(v) ~= "table" then
		return nil
	end
	local id = int(v.id, 0, 0)
	local game: Types.Game? = nil
	for _, g in games do
		if g.id == id then
			game = g
		end
	end
	if game == nil then
		return nil
	end
	local l = Live.new(game, int(v.seed, 0, 0))
	l.age = num(v.age, 0, 0, l.life)
	l.players = Live.playersAt(l, l.age)
	l.earned = num(v.earned, 0, 0)
	l.peak = math.max(int(v.peak, 0, 0), l.players)
	local samples: { number } = {}
	if type(v.samples) == "table" then
		for _, n in v.samples do
			if #samples < Tuning.LiveSamples then
				table.insert(samples, int(n, 0, 0))
			end
		end
	end
	l.samples = if #samples > 0 then samples else { l.players }
	return l
end

local function foundOf(v: any): { [string]: number }
	local out: { [string]: number } = {}
	if type(v) == "table" then
		for k, n in v do
			if type(k) == "string" then
				local id, old = string.match(k, "^(%w+)|(%w+)$")
				local mod = modId(old)
				if id and mod and Ideas.valid({ id = id, mod = mod }) then
					local c = int(n, 0, 0)
					if c > 0 then
						local key = id .. "|" .. mod
						out[key] = (out[key] or 0) + c
					end
				end
			end
		end
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

-- Any table (a save, an older save, garbage) -> a valid Profile: known fields kept when their type and range are
-- right, everything else from the default. `seed` makes the default's team when the save has none.
function Schema.reconcile(raw: any, now: number, seed: number): Profile
	local d = Schema.default(now, seed)
	if type(raw) ~= "table" then
		return d
	end
	local r = Schema.migrate(raw)
	local office = int(r.office, 1, 1, #Office.plans)
	local team = teamOf(r.team, desksOf(office))
	if #team == 0 then
		team = d.team
	end
	local games = gamesOf(r.games)
	local maxId = 0
	for _, g in games do
		maxId = math.max(maxId, g.id)
	end
	local live = liveOf(r.live, games)
	if r.liveNewest and #games > 0 then
		local g = games[#games]
		live = Live.new(g, g.id * 7919 + g.at)
	end
	local st = if type(r.stats) == "table" then r.stats else {}
	local up = if type(r.upgrades) == "table" then r.upgrades else {}
	local settings = if type(r.settings) == "table" then r.settings else {}
	local pixel = settings.pixel
	return {
		v = Schema.VERSION,
		coins = int(r.coins, d.coins, 0),
		ideas = cards(r.ideas, Tuning.BoardSize),
		found = foundOf(r.found),
		project = projectOf(r.project),
		games = games,
		live = live,
		nextGame = math.max(int(r.nextGame, 1, 1), maxId + 1),
		upgrades = { speed = int(up.speed, 0, 0, 200), luck = int(up.luck, 0, 0, 1000) },
		team = team,
		office = office,
		tut = int(r.tut, 1, 0, 3),
		stats = {
			games = int(st.games, #games, 0),
			rolls = int(st.rolls, 0, 0),
			best = int(st.best, 0, 0),
			earned = int(st.earned, 0, 0),
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
