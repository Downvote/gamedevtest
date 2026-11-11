--!strict
-- The questline (GAME_DESIGN 9: "make a questline such that players are guided throughout the features of the game,
-- such as assigning creatures to different work areas"). Pure data. After the tips, one quest at a time, in order:
-- each names something to do, says where to do it, and pays a small reward when the player claims it (Logic/Quest).
--   goal: what it counts (Logic/Quest.count) and how many; `of` a building kind for "built".
--     "helpers" driftlings at work, "folk" villagers, "workers" villagers at work, "paths" path tiles, "decor" decorations, "built" pieces of a kind, "befriended" driftlings befriended,
--     "battles" battles won, "skills" skills used, "charted" wild places cleared, "tier" the island's tier, "pouch"
--     the snack pouch's level, "seen" kinds in the Index, "hatched" eggs hatched
--   go: where its Go button takes the player: a panel ("pals" "folk" "index" "hatch"), "site" (the nearest wild place
--     to explore, its card open: the trip under way if there is one) or Build mode ("build", or "build:<tab>")
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
		id = "food",
		title = "Grow more food",
		text = "Build a second farm or a fishing pier. More villagers means more mouths.",
		goal = { kind = "built", n = 2, of = "food" },
		reward = { shells = 120, wood = 20 },
		go = "build:food",
		icon = "food",
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
		text = "Explore a wild place and throw snacks at hurt wild ones. Friends can work at home.",
		goal = { kind = "befriended", n = 3 },
		reward = { shells = 150, food = 40 },
		go = "site",
		icon = "pal",
	},
	{
		id = "skill",
		title = "Use a skill",
		text = "In a fight, tap Skills and pick one. Skill points fill up as the fight goes on.",
		goal = { kind = "skills", n = 1 },
		reward = { shells = 80 },
		go = "site",
		icon = "star",
	},
	{
		id = "battles",
		title = "Win ten fights",
		text = "Each wild place on the island has driftlings to fight. Win ten fights.",
		goal = { kind = "battles", n = 10 },
		reward = { shells = 150 },
		go = "site",
		icon = "wild",
	},
	{
		id = "pouch",
		title = "Carry more snacks",
		text = "Tap a wild place and get a bigger pouch there.",
		goal = { kind = "pouch", n = 2 },
		reward = { shells = 120, wood = 20 },
		go = "site",
		icon = "food",
	},
	{
		id = "guardian",
		title = "Clear a wild place",
		text = "Every wild place has a guardian at the end. Beat it and the place is yours to build round.",
		goal = { kind = "charted", n = 1 },
		reward = { shells = 300 },
		go = "site",
		icon = "boss",
	},
	{
		id = "expand",
		title = "Grow your island",
		text = "In Build mode tap Expand. A bigger island fits more, and new wild places turn up.",
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
		id = "clear2",
		title = "Clear two wild places",
		text = "The new ones are tougher. Bring your strongest.",
		goal = { kind = "charted", n = 2 },
		reward = { shells = 600 },
		go = "site",
		icon = "boss",
	},
	{
		id = "index",
		title = "Meet twelve kinds",
		text = "The Index lists every kind you've met. Each kind of wild place has its own.",
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
		title = "Clear five wild places",
		text = "Beat the guardians of five wild places.",
		goal = { kind = "charted", n = 5 },
		reward = { shells = 2000 },
		go = "site",
		icon = "boss",
	},
}

Quests.list = list
Quests.byId = {} :: { [string]: Quest }
for _, q in list do
	Quests.byId[q.id] = q
end

return Quests
