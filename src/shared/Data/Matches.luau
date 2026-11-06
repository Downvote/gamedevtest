--!strict
-- How well each genre and topic go together (GAME_DESIGN 6.1). Pure. Per genre: the topics that are a great, a good
-- and a poor match; every other pair is okay. Players learn a pair's match by releasing a game with it.
export type MatchDef = { great: { string }, good: { string }, poor: { string } }

local BY_GENRE: { [string]: MatchDef } = {
	action = { great = { "ninjas", "zombies", "robots" }, good = { "space", "pirates", "dinosaurs" }, poor = { "cooking", "school", "farming" } },
	puzzle = { great = { "animals", "space", "music" }, good = { "cooking", "school", "ocean" }, poor = { "zombies", "ninjas" } },
	adventure = { great = { "pirates", "fantasy", "detectives" }, good = { "dinosaurs", "ocean", "space" }, poor = { "cooking", "farming" } },
	rpg = { great = { "fantasy", "space", "robots" }, good = { "pirates", "ninjas", "school" }, poor = { "cooking", "music" } },
	racing = { great = { "robots", "space", "animals" }, good = { "dinosaurs", "ocean" }, poor = { "detectives", "school", "farming" } },
	sports = { great = { "animals", "school", "robots" }, good = { "ninjas", "ocean" }, poor = { "zombies", "detectives", "fantasy" } },
	simulation = { great = { "farming", "cooking", "school" }, good = { "animals", "ocean", "space" }, poor = { "ninjas", "zombies" } },
	strategy = { great = { "space", "fantasy", "dinosaurs" }, good = { "pirates", "robots", "zombies" }, poor = { "music", "cooking", "animals" } },
	rhythm = { great = { "music", "robots", "animals" }, good = { "space", "school", "ninjas" }, poor = { "detectives", "dinosaurs", "farming" } },
	horror = { great = { "zombies", "detectives", "school" }, good = { "ocean", "space", "robots" }, poor = { "animals", "cooking", "music" } },
}

return table.freeze({ byGenre = BY_GENRE })
