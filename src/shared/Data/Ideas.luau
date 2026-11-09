--!strict
-- The ideas the idea team can think of (GAME_DESIGN 4). Pure.
--   odds:    the idea's own "1 in N" (Logic/Ideas.odds: Rare and rarer roll at luck / odds, Uncommon at 1 / odds, the
--            Commons share what is left, so their N is about right at luck x1)
--   micro:   the minigame engine it runs on (UI/MicroGames: a party round), variant: that engine's theme for it
--   word:    the minigame's order, shown big on the curtain before it starts
--   reuse:   difficulty added when an idea reuses an engine another idea already has (GAME_DESIGN 5)
--   color:   a UIKit colour key for its card; words: for the game's title (Logic/Ideas.title)
export type IdeaDef = {
	id: string,
	name: string,
	kind: string, -- "Genre" | "Theme"
	odds: number,
	micro: string,
	variant: string,
	word: string,
	reuse: number,
	color: string,
	words: { string },
}

-- stylua: ignore start
local LIST: { IdeaDef } = {
	-- Common
	{ id = "action", name = "Action", kind = "Genre", odds = 7, micro = "bombs", variant = "blocks", word = "Dodge!", reuse = 0, color = "berry_red", words = { "Blast", "Rush", "Strike" } },
	{ id = "puzzle", name = "Puzzle", kind = "Genre", odds = 8, micro = "tiles", variant = "match", word = "Match!", reuse = 0, color = "ideas", words = { "Blocks", "Tiles", "Logic" } },
	{ id = "animals", name = "Animals", kind = "Theme", odds = 9, micro = "collect", variant = "pet", word = "Fetch!", reuse = 0, color = "orange", words = { "Kitty", "Puppy", "Critter" } },
	{ id = "space", name = "Space", kind = "Theme", odds = 10, micro = "bombs", variant = "space", word = "Take cover!", reuse = 1, color = "blue", words = { "Galaxy", "Star", "Cosmo" } },
	{ id = "cooking", name = "Cooking", kind = "Theme", odds = 11, micro = "tiles", variant = "flip", word = "Hop!", reuse = 1, color = "yellow", words = { "Pancake", "Chef", "Kitchen" } },
	{ id = "school", name = "School", kind = "Theme", odds = 12, micro = "quiz", variant = "answer", word = "Answer!", reuse = 0, color = "green", words = { "Class", "Homework", "Recess" } },
	-- Uncommon
	{ id = "adventure", name = "Adventure", kind = "Genre", odds = 15, micro = "sweep", variant = "leap", word = "Jump!", reuse = 0, color = "leaf", words = { "Quest", "Journey", "Trail" } },
	{ id = "racing", name = "Racing", kind = "Genre", odds = 18, micro = "sumo", variant = "race", word = "Bump!", reuse = 0, color = "orange", words = { "Turbo", "Drift", "Rally" } },
	{ id = "sports", name = "Sports", kind = "Genre", odds = 20, micro = "zone", variant = "kick", word = "Hold the ring!", reuse = 0, color = "green", words = { "Goal", "Champion", "League" } },
	{ id = "pirates", name = "Pirates", kind = "Theme", odds = 25, micro = "collect", variant = "loot", word = "Loot!", reuse = 1, color = "gold", words = { "Pirate", "Treasure", "Captain" } },
	{ id = "farming", name = "Farming", kind = "Theme", odds = 30, micro = "paint", variant = "water", word = "Water!", reuse = 0, color = "leaf", words = { "Farm", "Harvest", "Garden" } },
	{ id = "ocean", name = "Ocean", kind = "Theme", odds = 40, micro = "collect", variant = "fish", word = "Catch!", reuse = 1, color = "screen_on", words = { "Ocean", "Reef", "Tide" } },
	-- Rare
	{ id = "rpg", name = "RPG", kind = "Genre", odds = 60, micro = "barrage", variant = "strike", word = "Dodge!", reuse = 0, color = "purple", words = { "Legends", "Saga", "Heroes" } },
	{ id = "fantasy", name = "Fantasy", kind = "Theme", odds = 70, micro = "sweep", variant = "cast", word = "Jump!", reuse = 1, color = "pink", words = { "Dragon", "Wizard", "Mystic" } },
	{ id = "rhythm", name = "Rhythm", kind = "Genre", odds = 80, micro = "tiles", variant = "beat", word = "Dance!", reuse = 2, color = "sound", words = { "Beat", "Groove", "Tempo" } },
	{ id = "robots", name = "Robots", kind = "Theme", odds = 100, micro = "sweep", variant = "program", word = "Jump!", reuse = 2, color = "steel", words = { "Robo", "Mecha", "Circuit" } },
	{ id = "ninjas", name = "Ninjas", kind = "Theme", odds = 120, micro = "barrage", variant = "fruit", word = "Dodge!", reuse = 1, color = "black", words = { "Ninja", "Shadow", "Blade" } },
	{ id = "zombies", name = "Zombies", kind = "Theme", odds = 150, micro = "horde", variant = "zombie", word = "Survive!", reuse = 0, color = "green", words = { "Zombie", "Undead", "Graveyard" } },
	-- Epic
	{ id = "strategy", name = "Strategy", kind = "Genre", odds = 400, micro = "paint", variant = "count", word = "Claim!", reuse = 1, color = "blue", words = { "Empire", "Tactics", "Kingdom" } },
	{ id = "horror", name = "Horror", kind = "Genre", odds = 600, micro = "sneak", variant = "ghost", word = "Sneak!", reuse = 0, color = "purple", words = { "Haunted", "Midnight", "Phantom" } },
	{ id = "dinosaurs", name = "Dinosaurs", kind = "Theme", odds = 800, micro = "bombs", variant = "dino", word = "Run!", reuse = 2, color = "leaf", words = { "Dino", "Jurassic", "Raptor" } },
	{ id = "detectives", name = "Detectives", kind = "Theme", odds = 1000, micro = "quiz", variant = "spot", word = "Spot it!", reuse = 1, color = "wood", words = { "Detective", "Mystery", "Clue" } },
	-- Legendary
	{ id = "simulation", name = "Simulation", kind = "Genre", odds = 3000, micro = "paint", variant = "tower", word = "Build!", reuse = 2, color = "steel", words = { "Tycoon", "City", "Sim" } },
	{ id = "music", name = "Music", kind = "Theme", odds = 6000, micro = "zone", variant = "simon", word = "Spotlight!", reuse = 1, color = "pink", words = { "Melody", "Encore", "Band" } },
}
-- stylua: ignore end

local BY_ID: { [string]: IdeaDef } = {}
for _, d in LIST do
	BY_ID[d.id] = d
end

return table.freeze({ list = LIST, byId = BY_ID })
