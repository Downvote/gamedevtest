--!strict
-- Genres (GAME_DESIGN 6.1). Pure. tier: 1 = open at the start, 2-3 cost Tuning.GenreRp[tier] research points.
-- words: the genre's half of a game's title ("Galaxy *Blocks*"); colour: the genre chip's colour (Palette key).
export type GenreDef = { id: string, name: string, tier: number, words: { string }, color: string }

local LIST: { GenreDef } = {
	{ id = "action", name = "Action", tier = 1, words = { "Blast", "Rush", "Strike", "Fury", "Dash" }, color = "berry_red" },
	{ id = "puzzle", name = "Puzzle", tier = 1, words = { "Blocks", "Puzzle", "Match", "Tiles", "Logic" }, color = "blue" },
	{ id = "adventure", name = "Adventure", tier = 1, words = { "Quest", "Journey", "Tales", "Odyssey", "Saga" }, color = "green" },
	{ id = "rpg", name = "RPG", tier = 2, words = { "Legends", "Chronicles", "Heroes", "Kingdom", "Fate" }, color = "purple" },
	{ id = "racing", name = "Racing", tier = 2, words = { "Racer", "Rally", "Drift", "Speedway", "Turbo" }, color = "orange" },
	{ id = "sports", name = "Sports", tier = 2, words = { "League", "Cup", "Champions", "Kickoff", "Slam" }, color = "yellow" },
	{ id = "simulation", name = "Simulation", tier = 2, words = { "Tycoon", "Life", "Sim", "Manager", "World" }, color = "leaf" },
	{ id = "strategy", name = "Strategy", tier = 3, words = { "Tactics", "Command", "Empire", "Conquest", "Front" }, color = "steel_dark" },
	{ id = "rhythm", name = "Rhythm", tier = 3, words = { "Beats", "Groove", "Jam", "Rhythm", "Dance" }, color = "pink" },
	{ id = "horror", name = "Horror", tier = 3, words = { "Nightmare", "Dread", "Shadows", "Haunt", "Fear" }, color = "black" },
}

local BY_ID: { [string]: GenreDef } = {}
for _, g in LIST do
	BY_ID[g.id] = g
end

return table.freeze({ list = LIST, byId = BY_ID })
