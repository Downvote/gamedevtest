--!strict
-- The idea team's rolls (GAME_DESIGN 4; docs/ARCHITECTURE.md 6). Pure: every random draw comes from the Rng argument.
-- An idea is rolled from Data/Ideas, then its modifier from Data/Modifiers, each by the same odds rule (Random
-- Bakery's): Rare and rarer entries (odds >= Tuning.RareOdds) at luck / odds, the others at 1 / odds, and the
-- commonest share (Commons; Plain for modifiers) takes what is left, never less than Tuning.CommonFloor (past that,
-- the lucky ones are scaled down to fit). An idea's combined "1 in N" is its odds times its modifier's, and its tier
-- (Common .. Mythic) and its minigame's difficulty come from that N.
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local IdeasData = require(script.Parent.Parent.Data.Ideas)
local Modifiers = require(script.Parent.Parent.Data.Modifiers)
local Util = require(script.Parent.Util)

type Card = Types.Card
type Rng = Types.Rng

local Ideas = {}

local function clampLuck(luck: number?): number
	local l = if type(luck) == "number" and Util.isFinite(luck) then luck else 1
	return math.max(1, l)
end

-- Chances for a list of { odds } entries at `luck`: the entries whose odds are below `common` share the rest by
-- 1 / odds. Returns one chance per entry, summing to 1.
local function chances(list: { { odds: number } }, luck: number, commonBelow: number): { number }
	local out = table.create(#list, 0)
	local lucky, fixed, com = 0, 0, 0
	for i, d in list do
		if d.odds >= Tuning.RareOdds then
			out[i] = luck / d.odds
			lucky += out[i]
		elseif d.odds >= commonBelow then
			out[i] = 1 / d.odds
			fixed += out[i]
		else
			com += 1 / d.odds
		end
	end
	local room = 1 - fixed - Tuning.CommonFloor
	local scale = if lucky > room then room / lucky else 1
	local rest = 1 - fixed - lucky * scale
	for i, d in list do
		if d.odds >= Tuning.RareOdds then
			out[i] *= scale
		elseif d.odds < commonBelow then
			out[i] = if com > 0 then rest * (1 / d.odds) / com else 0
		end
	end
	return out
end

-- The ideas' chances at `luck` (Data/Ideas order). Commons: odds under Tuning.CommonOdds.
function Ideas.ideaChances(luck: number?): { number }
	return chances(IdeasData.list :: any, clampLuck(luck), Tuning.CommonOdds)
end

-- The modifiers' chances at `luck` (Data/Modifiers order). Plain (odds 1) takes the rest.
function Ideas.modChances(luck: number?): { number }
	return chances(Modifiers.list :: any, clampLuck(luck), 2)
end

local function draw(rng: Rng, w: { number }): number
	local x = rng:next()
	local acc = 0
	for i, p in w do
		acc += p
		if x < acc then
			return i
		end
	end
	return #w
end

-- One idea from the team: an idea, then its modifier.
function Ideas.roll(rng: Rng, luck: number?): Card
	local idea = IdeasData.list[draw(rng, Ideas.ideaChances(luck))]
	local mod = Modifiers.list[draw(rng, Ideas.modChances(luck))]
	return { id = idea.id, mod = mod.id }
end

-- A card's combined 1 in N (the idea's odds times its modifier's).
function Ideas.oneIn(c: Card): number
	local d, m = IdeasData.byId[c.id], Modifiers.byId[c.mod]
	return (if d then d.odds else 1) * (if m then m.odds else 1)
end

-- The tier (1 Common .. 6 Mythic) of a 1 in N.
function Ideas.tierOf(oneIn: number): number
	local t = 1
	for i, n in Tuning.TierOneIn do
		if oneIn >= n then
			t = i + 1
		end
	end
	return t
end

function Ideas.tier(c: Card): number
	return Ideas.tierOf(Ideas.oneIn(c))
end

function Ideas.tierName(t: number): string
	return Tuning.TierNames[math.clamp(t, 1, #Tuning.TierNames)]
end

function Ideas.tierColor(t: number): string
	return Tuning.TierColors[math.clamp(t, 1, #Tuning.TierColors)]
end

-- A card's name: "Glitched Ninjas" ("Ninjas" when Plain).
function Ideas.name(c: Card): string
	local d, m = IdeasData.byId[c.id], Modifiers.byId[c.mod]
	local n = if d then d.name else "?"
	if m and m.id ~= "plain" then
		return m.name .. " " .. n
	end
	return n
end

-- The coins a second an idea earns in a launched game, before the minigame boost.
function Ideas.value(c: Card): number
	local d, m = IdeasData.byId[c.id], Modifiers.byId[c.mod]
	if d == nil then
		return 0
	end
	return Tuning.IdeaValue * d.odds ^ Tuning.IdeaValuePow * (if m then m.mult else 1)
end

-- The difficulty (1 .. Tuning.DiffMax) of an idea's minigame: its tier, plus its engine's reuse step.
function Ideas.difficulty(c: Card): number
	local d = IdeasData.byId[c.id]
	return math.clamp(Ideas.tier(c) + (if d then d.reuse else 0), 1, Tuning.DiffMax)
end

-- A game's title from its three ideas (themes first, then genres), a word of each, picked by `seed`.
function Ideas.title(cards: { Card }, seed: number): string
	local themes: { IdeasData.IdeaDef }, genres: { IdeasData.IdeaDef } = {}, {}
	for _, c in cards do
		local d = IdeasData.byId[c.id]
		if d then
			table.insert(if d.kind == "Genre" then genres else themes, d)
		end
	end
	local words: { string } = {}
	local k = math.abs(math.floor(seed))
	for _, list in { themes, genres } do
		for _, d in list do
			table.insert(words, d.words[k % #d.words + 1])
			k = k // 3 + 7
		end
	end
	if #words == 0 then
		return "Untitled"
	end
	return table.concat(words, " ")
end

-- A game's income a second from its ideas and the minigames won (each adds Tuning.WinBoost).
function Ideas.rate(cards: { Card }, wins: number): number
	local v = 0
	for _, c in cards do
		v += Ideas.value(c)
	end
	return v * (1 + Tuning.WinBoost * math.clamp(wins, 0, 3))
end

-- The seconds between two ideas at a speed level.
function Ideas.rollEvery(speed: number): number
	return math.max(Tuning.RollMin, Tuning.RollBase * Tuning.RollStep ^ math.max(0, speed))
end

-- The luck at a luck level.
function Ideas.luck(level: number): number
	return 1 + Tuning.LuckStep * math.max(0, level)
end

-- The board after a new idea: added when there is room; when full, it takes the place of the commonest idea if it is
-- rarer than that one. Returns the board index it went to (0: dropped) and the card it replaced.
function Ideas.place(board: { Card }, c: Card): (number, Card?)
	if #board < Tuning.BoardSize then
		table.insert(board, c)
		return #board, nil
	end
	local worst, wn = 0, math.huge
	for i, b in board do
		local n = Ideas.oneIn(b)
		if n < wn then
			worst, wn = i, n
		end
	end
	if worst > 0 and Ideas.oneIn(c) > wn then
		local old = board[worst]
		board[worst] = c
		return worst, old
	end
	return 0, nil
end

function Ideas.key(c: Card): string
	return c.id .. "|" .. c.mod
end

function Ideas.valid(c: any): boolean
	return type(c) == "table" and type(c.id) == "string" and IdeasData.byId[c.id] ~= nil and type(c.mod) == "string" and Modifiers.byId[c.mod] ~= nil
end

return Ideas
