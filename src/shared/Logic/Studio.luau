--!strict
-- The studio's rules over a profile (GAME_DESIGN 3-7; docs/ARCHITECTURE.md 6): the idea team's next idea, making a
-- game from three board ideas, its minigames' results, the launch, the two upgrades and the founder's look. Pure:
-- StudioService calls these with the session's profile and its own Rng; the Economy spec plays whole sessions through
-- the very same functions. Every action returns (true, data?) or (false, ErrCode) and changes the profile only when it
-- succeeds.
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Looks = require(script.Parent.Parent.Data.Looks)
local Names = require(script.Parent.Parent.Data.Names)
local Ideas = require(script.Parent.Ideas)
local Util = require(script.Parent.Util)

type Profile = Types.Profile
type Card = Types.Card
type Rng = Types.Rng
type ErrCode = Types.ErrCode

local Studio = {}

-- What a new idea did (the server's Fx "idea" message).
export type Rolled = { card: Card, slot: number, replaced: Card?, oneIn: number, tier: number, first: boolean }

function Studio.rollEvery(p: Profile): number
	return Ideas.rollEvery(p.upgrades.speed)
end

function Studio.luck(p: Profile): number
	return Ideas.luck(p.upgrades.luck)
end

-- The idea team's next idea: rolled at the profile's luck, counted in the Index, put on the board (Ideas.place).
function Studio.rollIdea(p: Profile, rng: Rng): Rolled
	local c = Ideas.roll(rng, Studio.luck(p))
	local key = Ideas.key(c)
	local first = (p.found[key] or 0) == 0
	p.found[key] = (p.found[key] or 0) + 1
	p.stats.rolls += 1
	local n = Ideas.oneIn(c)
	p.stats.best = math.max(p.stats.best, n)
	local slot, replaced = Ideas.place(p.ideas, c)
	return { card = c, slot = slot, replaced = replaced, oneIn = n, tier = Ideas.tierOf(n), first = first }
end

-- Make a game from three board ideas (board indices a, b, c, all different): they leave the board for the project.
function Studio.make(p: Profile, a: number, b: number, c: number, seed: number): (boolean, any)
	if p.project ~= nil then
		return false, "busy" :: ErrCode
	end
	local picks = { a, b, c }
	for i, k in picks do
		if k < 1 or k > #p.ideas or k ~= math.floor(k) then
			return false, "bad_payload" :: ErrCode
		end
		for j = 1, i - 1 do
			if picks[j] == k then
				return false, "bad_payload" :: ErrCode
			end
		end
	end
	local cards = { p.ideas[a], p.ideas[b], p.ideas[c] }
	-- remove from the highest index down so the others keep their places meanwhile
	local order = table.clone(picks)
	table.sort(order, function(x, y)
		return x > y
	end)
	for _, k in order do
		table.remove(p.ideas, k)
	end
	p.project = { title = Ideas.title(cards, seed), ideas = cards, won = { -1, -1, -1 }, seed = seed }
	if p.tut == 1 then
		p.tut = 2
	end
	return true, p.project
end

-- A minigame's result for slot 1..3: the best one counts (a retry never loses a win).
function Studio.result(p: Profile, slot: number, won: boolean): (boolean, any)
	local proj = p.project
	if proj == nil then
		return false, "no_project" :: ErrCode
	end
	if slot < 1 or slot > 3 then
		return false, "bad_payload" :: ErrCode
	end
	proj.won[slot] = math.max(proj.won[slot], if won then 1 else 0)
	return true, { slot = slot, won = proj.won[slot] == 1 }
end

function Studio.wins(proj: Types.Making): number
	local n = 0
	for _, w in proj.won do
		if w == 1 then
			n += 1
		end
	end
	return n
end

-- Launch the game once every minigame has been played: it earns its rate for good.
function Studio.launch(p: Profile, now: number): (boolean, any)
	local proj = p.project
	if proj == nil then
		return false, "no_project" :: ErrCode
	end
	for _, w in proj.won do
		if w < 0 then
			return false, "not_built" :: ErrCode
		end
	end
	local wins = Studio.wins(proj)
	local game: Types.Game = { id = p.nextGame, title = proj.title, ideas = proj.ideas, rate = Ideas.rate(proj.ideas, wins), wins = wins, at = now }
	p.nextGame += 1
	p.rate += game.rate
	table.insert(p.games, game)
	while #p.games > Tuning.GamesKept do
		table.remove(p.games, 1)
	end
	p.stats.games += 1
	p.project = nil
	if p.tut == 2 then
		p.tut = 3
	end
	return true, game
end

-- The coins the games made (the server's income tick).
function Studio.earn(p: Profile, coins: number)
	if coins > 0 then
		p.coins += coins
		p.stats.earned += coins
	end
end

-- An upgrade's next level's price ("speed" or "luck").
function Studio.upgradeCost(k: string, level: number): number
	if k == "speed" then
		return math.floor(Tuning.SpeedCost * Tuning.SpeedGrowth ^ level + 0.5)
	end
	return math.floor(Tuning.LuckCost * Tuning.LuckGrowth ^ level + 0.5)
end

-- Whether roll speed has reached Tuning.RollMin.
function Studio.speedMaxed(p: Profile): boolean
	return Ideas.rollEvery(p.upgrades.speed) <= Tuning.RollMin
end

function Studio.buyUpgrade(p: Profile, k: string): (boolean, any)
	if k ~= "speed" and k ~= "luck" then
		return false, "bad_payload" :: ErrCode
	end
	if k == "speed" and Studio.speedMaxed(p) then
		return false, "max" :: ErrCode
	end
	local level = if k == "speed" then p.upgrades.speed else p.upgrades.luck
	local cost = Studio.upgradeCost(k, level)
	if p.coins < cost then
		return false, "money" :: ErrCode
	end
	p.coins -= cost
	if k == "speed" then
		p.upgrades.speed += 1
	else
		p.upgrades.luck += 1
	end
	return true, { level = level + 1, cost = cost }
end

function Studio.randomLook(rng: Rng): Types.Look
	return { skin = rng:int(1, #Looks.skin), hair = rng:int(1, #Looks.hair), style = rng:int(1, #Looks.styles), shirt = rng:int(1, #Looks.shirt) }
end

-- A new idea team of n, one to a desk.
function Studio.newTeam(rng: Rng, n: number): { Types.Member }
	local out = {}
	for i = 1, n do
		table.insert(out, { id = i, name = Util.pick(rng, Names.first) .. " " .. Util.pick(rng, Names.last), look = Studio.randomLook(rng), desk = i })
	end
	return out
end

-- The founder's look (free).
function Studio.setFounder(p: Profile, skin: number, hair: number, style: number, shirt: number): (boolean, any)
	if skin > #Looks.skin or hair > #Looks.hair or style > #Looks.styles or shirt > #Looks.shirt then
		return false, "bad_payload" :: ErrCode
	end
	p.founder = { skin = skin, hair = hair, style = style, shirt = shirt }
	return true, nil
end

return Studio
