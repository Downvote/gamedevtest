--!strict
-- The ideas the idea team can think of (GAME_DESIGN 4). Pure.
--   odds:    the idea's own "1 in N" (Logic/Ideas.odds: Rare and rarer roll at luck / odds, Uncommon at 1 / odds, the
--            Commons share what is left, so their N is about right at luck x1)
--   micro:   the microgame engine its minigame runs on (UI/MicroGames), variant: that engine's theme for it
--   word:    the microgame's instruction (WarioWare style), shown big before it starts
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
	{ id = "action", name = "Action", kind = "Genre", odds = 7, micro = "dodge", variant = "blocks", word = "Dodge!", reuse = 0, color = "berry_red", words = { "Blast", "Rush", "Strike" } },
	{ id = "puzzle", name = "Puzzle", kind = "Genre", odds = 8, micro = "pick", variant = "match", word = "Match!", reuse = 0, color = "ideas", words = { "Blocks", "Tiles", "Logic" } },
	{ id = "animals", name = "Animals", kind = "Theme", odds = 9, micro = "mash", variant = "pet", word = "Pet!", reuse = 0, color = "orange", words = { "Kitty", "Puppy", "Critter" } },
	{ id = "space", name = "Space", kind = "Theme", odds = 10, micro = "whack", variant = "space", word = "Shoot!", reuse = 0, color = "blue", words = { "Galaxy", "Star", "Cosmo" } },
	{ id = "cooking", name = "Cooking", kind = "Theme", odds = 11, micro = "timing", variant = "flip", word = "Flip!", reuse = 0, color = "yellow", words = { "Pancake", "Chef", "Kitchen" } },
	{ id = "school", name = "School", kind = "Theme", odds = 12, micro = "pick", variant = "answer", word = "Answer!", reuse = 1, color = "green", words = { "Class", "Homework", "Recess" } },
	-- Uncommon
	{ id = "adventure", name = "Adventure", kind = "Genre", odds = 15, micro = "jump", variant = "leap", word = "Leap!", reuse = 0, color = "leaf", words = { "Quest", "Journey", "Trail" } },
	{ id = "racing", name = "Racing", kind = "Genre", odds = 18, micro = "dodge", variant = "race", word = "Steer!", reuse = 1, color = "orange", words = { "Turbo", "Drift", "Rally" } },
	{ id = "sports", name = "Sports", kind = "Genre", odds = 20, micro = "timing", variant = "kick", word = "Kick!", reuse = 1, color = "green", words = { "Goal", "Champion", "League" } },
	{ id = "pirates", name = "Pirates", kind = "Theme", odds = 25, micro = "catch", variant = "loot", word = "Loot!", reuse = 0, color = "gold", words = { "Pirate", "Treasure", "Captain" } },
	{ id = "farming", name = "Farming", kind = "Theme", odds = 30, micro = "whack", variant = "water", word = "Water!", reuse = 1, color = "leaf", words = { "Farm", "Harvest", "Garden" } },
	{ id = "ocean", name = "Ocean", kind = "Theme", odds = 40, micro = "catch", variant = "fish", word = "Catch!", reuse = 1, color = "screen_on", words = { "Ocean", "Reef", "Tide" } },
	-- Rare
	{ id = "rpg", name = "RPG", kind = "Genre", odds = 60, micro = "timing", variant = "strike", word = "Strike!", reuse = 2, color = "purple", words = { "Legends", "Saga", "Heroes" } },
	{ id = "fantasy", name = "Fantasy", kind = "Theme", odds = 70, micro = "sequence", variant = "cast", word = "Cast!", reuse = 0, color = "pink", words = { "Dragon", "Wizard", "Mystic" } },
	{ id = "rhythm", name = "Rhythm", kind = "Genre", odds = 80, micro = "rhythm", variant = "beat", word = "Tap the beat!", reuse = 0, color = "sound", words = { "Beat", "Groove", "Tempo" } },
	{ id = "robots", name = "Robots", kind = "Theme", odds = 100, micro = "sequence", variant = "program", word = "Program!", reuse = 1, color = "steel", words = { "Robo", "Mecha", "Circuit" } },
	{ id = "ninjas", name = "Ninjas", kind = "Theme", odds = 120, micro = "slice", variant = "fruit", word = "Slice!", reuse = 0, color = "black", words = { "Ninja", "Shadow", "Blade" } },
	{ id = "zombies", name = "Zombies", kind = "Theme", odds = 150, micro = "whack", variant = "zombie", word = "Whack!", reuse = 2, color = "green", words = { "Zombie", "Undead", "Graveyard" } },
	-- Epic
	{ id = "strategy", name = "Strategy", kind = "Genre", odds = 400, micro = "pick", variant = "count", word = "Count!", reuse = 1, color = "blue", words = { "Empire", "Tactics", "Kingdom" } },
	{ id = "horror", name = "Horror", kind = "Genre", odds = 600, micro = "hide", variant = "ghost", word = "Sneak!", reuse = 0, color = "purple", words = { "Haunted", "Midnight", "Phantom" } },
	{ id = "dinosaurs", name = "Dinosaurs", kind = "Theme", odds = 800, micro = "jump", variant = "dino", word = "Jump!", reuse = 2, color = "leaf", words = { "Dino", "Jurassic", "Raptor" } },
	{ id = "detectives", name = "Detectives", kind = "Theme", odds = 1000, micro = "pick", variant = "spot", word = "Spot it!", reuse = 2, color = "wood", words = { "Detective", "Mystery", "Clue" } },
	-- Legendary
	{ id = "simulation", name = "Simulation", kind = "Genre", odds = 3000, micro = "stack", variant = "tower", word = "Build!", reuse = 0, color = "steel", words = { "Tycoon", "City", "Sim" } },
	{ id = "music", name = "Music", kind = "Theme", odds = 6000, micro = "sequence", variant = "simon", word = "Repeat!", reuse = 2, color = "pink", words = { "Melody", "Encore", "Band" } },
}
-- stylua: ignore end

local BY_ID: { [string]: IdeaDef } = {}
for _, d in LIST do
	BY_ID[d.id] = d
end

return table.freeze({ list = LIST, byId = BY_ID })
