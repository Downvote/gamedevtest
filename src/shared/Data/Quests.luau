--!strict
-- The questline (GAME_DESIGN 9: "make a questline such that players are guided throughout the features of the game,
-- such as assigning creatures to different work areas"). Pure data. After the tips, one quest at a time, in order:
-- each names something to do, says where to do it, and pays a small reward when the player claims it (Logic/Quest).
--   goal: what it counts (Logic/Quest.count) and how many; `of` a building kind for "built".
--     "helpers" driftlings at work, "folk" villagers, "workers" villagers at work, "upgraded" pieces at level 2 or
--     more, "paths" path tiles, "decor" decorations, "built" pieces of a kind, "befriended" driftlings befriended,
--     "battles" battles won, "skills" skills used, "charted" islands charted, "tier" the island's tier, "pouch" the
--     snack pouch's level, "boat" the boat's level, "seen" kinds in the Index, "hatched" eggs hatched
--   go: where its Go button takes the player: a panel ("pals" "folk" "index" "hatch" "explore") or Build mode
--     ("build", or "build:<tab>" on a tab of the tray)
export type Goal = { kind: string, n: number, of: string? }
export type Reward = { shells: number?, food: number?, wood: number? }
export type Quest = { id: string, title: string, text: string, goal: Goal, reward: Reward, go: string, icon: string }

local Quests = {}

local list: { Quest } = {
	{
		id = "help",
		title = "Put a driftling to work",
		text = "Open Driftlings and tap Help. A driftling works at a building that suits it.",
		goal = { kind = "helpers", n = 1 },
		reward = { shells = 60, food = 20 },
		go = "pals",
		icon = "pal",
	},
	{
		id = "home",
		title = "Make room for a newcomer",
		text = "Build another home. Someone moves in when there's a free bed.",
		goal = { kind = "folk", n = 2 },
		reward = { shells = 80, wood = 15 },
		go = "build:home",
		icon = "home",
	},
	{
		id = "jobs",
		title = "Give everyone a job",
		text = "Open Villagers and tap Work to choose where each one works.",
		goal = { kind = "workers", n = 2 },
		reward = { shells = 80 },
		go = "folk",
		icon = "folk",
	},
	{
		id = "upgrade",
		title = "Upgrade a building",
		text = "In Build mode tap one of your buildings, then Upgrade. Level 2 makes more.",
		goal = { kind = "upgraded", n = 1 },
		reward = { shells = 120, wood = 20 },
		go = "build",
		icon = "boost",
	},
	{
		id = "paths",
		title = "Lay a path",
		text = "In Build mode open Paths, pick one and drag across the grass.",
		goal = { kind = "paths", n = 8 },
		reward = { shells = 60 },
		go = "build:path",
		icon = "path",
	},
	{
		id = "decor",
		title = "Decorate",
		text = "Place two things from the Decor tab. Charm brings in more visitors.",
		goal = { kind = "decor", n = 2 },
		reward = { shells = 100 },
		go = "build:decor",
		icon = "decor",
	},
	{
		id = "friends",
		title = "Befriend three driftlings",
		text = "On an expedition, throw snacks at hurt wild ones. Friends can work at home.",
		goal = { kind = "befriended", n = 3 },
		reward = { shells = 150, food = 40 },
		go = "explore",
		icon = "pal",
	},
	{
		id = "skill",
		title = "Use a skill",
		text = "In a fight, tap Skills and pick one. Skill points fill up as the fight goes on.",
		goal = { kind = "skills", n = 1 },
		reward = { shells = 80 },
		go = "explore",
		icon = "star",
	},
	{
		id = "battles",
		title = "Win ten fights",
		text = "Every island has wild ones to fight. Win ten fights.",
		goal = { kind = "battles", n = 10 },
		reward = { shells = 150 },
		go = "explore",
		icon = "wild",
	},
	{
		id = "pouch",
		title = "Carry more snacks",
		text = "Open Explore and tap Bigger pouch.",
		goal = { kind = "pouch", n = 2 },
		reward = { shells = 120, wood = 20 },
		go = "explore",
		icon = "food",
	},
	{
		id = "guardian",
		title = "Beat a guardian",
		text = "Keep going on an island until its guardian turns up. Beating it charts the island.",
		goal = { kind = "charted", n = 1 },
		reward = { shells = 300 },
		go = "explore",
		icon = "boss",
	},
	{
		id = "expand",
		title = "Grow your island",
		text = "In Build mode tap Expand. A bigger island fits more and opens new buildings.",
		goal = { kind = "tier", n = 2 },
		reward = { shells = 400, wood = 50 },
		go = "build",
		icon = "home",
	},
	{
		id = "boost",
		title = "Build a boost",
		text = "Boosts make every building of one kind work faster. They're on the Boosts tab.",
		goal = { kind = "built", n = 1, of = "gen" },
		reward = { shells = 300 },
		go = "build:gen",
		icon = "boost",
	},
	{
		id = "yard",
		title = "Build the Training Yard",
		text = "Villagers and driftlings resting there get stronger. It's on the Nests tab.",
		goal = { kind = "built", n = 1, of = "train" },
		reward = { shells = 300 },
		go = "build:nest",
		icon = "train",
	},
	{
		id = "boat",
		title = "Upgrade your boat",
		text = "Open Explore and upgrade the boat. It reaches islands further out.",
		goal = { kind = "boat", n = 2 },
		reward = { shells = 600 },
		go = "explore",
		icon = "boat",
	},
	{
		id = "index",
		title = "Meet twelve kinds",
		text = "The Index lists every kind you've met. Islands further out have new ones.",
		goal = { kind = "seen", n = 12 },
		reward = { shells = 500 },
		go = "index",
		icon = "star",
	},
	{
		id = "town",
		title = "Grow the island again",
		text = "Expand once more. The Hatchery needs the room.",
		goal = { kind = "tier", n = 3 },
		reward = { shells = 1500, wood = 150 },
		go = "build",
		icon = "home",
	},
	{
		id = "hatchery",
		title = "Build a Hatchery",
		text = "It's on the Nests tab. Two driftlings and a feast make an egg there.",
		goal = { kind = "built", n = 1, of = "breed" },
		reward = { shells = 800 },
		go = "build:nest",
		icon = "nest",
	},
	{
		id = "egg",
		title = "Hatch an egg",
		text = "Open the Hatchery, pick two driftlings and give them a feast. It hatches in a few days.",
		goal = { kind = "hatched", n = 1 },
		reward = { shells = 1200 },
		go = "hatch",
		icon = "nest",
	},
	{
		id = "charts",
		title = "Chart three islands",
		text = "Beat the guardians of three islands.",
		goal = { kind = "charted", n = 3 },
		reward = { shells = 2000 },
		go = "explore",
		icon = "boss",
	},
}

Quests.list = list
Quests.byId = {} :: { [string]: Quest }
for _, q in list do
	Quests.byId[q.id] = q
end

return Quests
