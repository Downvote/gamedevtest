--!strict
-- Topics (GAME_DESIGN 6.1). Pure. tier: 1 = open at the start, 2-3 cost Tuning.TopicRp[tier] research points.
-- words: the topic's half of a game's title ("*Galaxy* Blocks").
export type TopicDef = { id: string, name: string, tier: number, words: { string } }

local LIST: { TopicDef } = {
	{ id = "space", name = "Space", tier = 1, words = { "Galaxy", "Star", "Cosmo", "Orbit", "Nova" } },
	{ id = "fantasy", name = "Fantasy", tier = 1, words = { "Dragon", "Wizard", "Mystic", "Elven", "Rune" } },
	{ id = "animals", name = "Animals", tier = 1, words = { "Kitty", "Puppy", "Bunny", "Panda", "Critter" } },
	{ id = "pirates", name = "Pirates", tier = 1, words = { "Pirate", "Buccaneer", "Treasure", "Cutlass", "Jolly" } },
	{ id = "robots", name = "Robots", tier = 2, words = { "Robo", "Mecha", "Cyber", "Gear", "Bolt" } },
	{ id = "ninjas", name = "Ninjas", tier = 2, words = { "Ninja", "Shadow", "Shuriken", "Shinobi", "Silent" } },
	{ id = "cooking", name = "Cooking", tier = 2, words = { "Kitchen", "Chef", "Snack", "Noodle", "Bakery" } },
	{ id = "school", name = "School", tier = 2, words = { "Campus", "Class", "Homework", "Recess", "Hall Pass" } },
	{ id = "zombies", name = "Zombies", tier = 2, words = { "Zombie", "Undead", "Brainy", "Rotten", "Ghoul" } },
	{ id = "dinosaurs", name = "Dinosaurs", tier = 3, words = { "Dino", "Raptor", "Rex", "Fossil", "Stomp" } },
	{ id = "detectives", name = "Detectives", tier = 3, words = { "Case", "Sleuth", "Mystery", "Gumshoe", "Alibi" } },
	{ id = "farming", name = "Farming", tier = 3, words = { "Farm", "Barnyard", "Sprout", "Tractor", "Meadow" } },
	{ id = "music", name = "Music", tier = 3, words = { "Disco", "Melody", "Rock", "Jazz", "Synth" } },
	{ id = "ocean", name = "Ocean", tier = 3, words = { "Ocean", "Coral", "Tidal", "Deep Sea", "Reef" } },
}

local BY_ID: { [string]: TopicDef } = {}
for _, t in LIST do
	BY_ID[t.id] = t
end

return table.freeze({ list = LIST, byId = BY_ID })
