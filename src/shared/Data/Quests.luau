--!strict
-- The questline (GAME_DESIGN 9: "make a questline such that players are guided throughout the features of the game,
-- such as assigning creatures to different work areas"). Pure data. After the tips, one quest at a time, in order:
-- each names something to do, says where to do it, and pays a small reward when the player claims it (Logic/Quest).
--   goal: what it counts (Logic/Quest.count) and how many; `of` a building kind for "built".
--     "helpers" driftlings at work, "housed" driftlings in huts, "paths" path tiles, "decor" decorations, "built" pieces of a kind, "grown" driftlings the tree grew, "sold" driftlings
--     sold, "best" the rarest driftling had (1 .. 5), "luck" / "speed" the Tree of Life's levels, "tier" the island's
--     tier, "seen" kinds in the Index, "hatched" eggs hatched
--   go: where its Go button takes the player: a panel ("pals" "index" "hatch" "tree") or Build mode ("build",
--     or "build:<tab>")
export type Goal = { kind: string, n: number, of: string? }
export type Reward = { shells: number?, food: number?, wood: number? }
export type Quest = { id: string, title: string, text: string, goal: Goal, reward: Reward, go: string, icon: string }

local Quests = {}

local list: { Quest } = {
	{
		id = "help",
		title = "Put a driftling to work",
		text = "A driftling in a hut helps at a building that suits it. Open Driftlings to see where.",
		goal = { kind = "helpers", n = 1 },
		reward = { shells = 60, food = 20 },
		go = "pals",
		icon = "pal",
	},
	{
		id = "sell",
		title = "Sell a driftling",
		text = "Tap the Tree of Life. Sell one from the pen you don't need. Rarer ones fetch more.",
		goal = { kind = "sold", n = 1 },
		reward = { shells = 40 },
		go = "tree",
		icon = "shell",
	},
	{
		id = "speed",
		title = "Speed up the tree",
		text = "Tap the Tree of Life and buy a level of Speed. It grows driftlings faster.",
		goal = { kind = "speed", n = 2 },
		reward = { shells = 80, wood = 10 },
		go = "tree",
		icon = "tree",
	},
	{
		id = "camp",
		title = "More wood",
		text = "Build a second Lumber Camp. Driftlings good with wood will go and work there.",
		goal = { kind = "built", n = 2, of = "wood" },
		reward = { shells = 80, wood = 15 },
		go = "build:wood",
		icon = "wood",
	},
	{
		id = "three",
		title = "Three at work",
		text = "Get three driftlings working. Each hut sends its driftlings to a building that suits them.",
		goal = { kind = "helpers", n = 3 },
		reward = { shells = 80 },
		go = "pals",
		icon = "pal",
	},
	{
		id = "huts",
		title = "Build another hut",
		text = "Huts are on the Huts tab. The pen sends driftlings there when a building needs one.",
		goal = { kind = "built", n = 2, of = "nest" },
		reward = { shells = 100, wood = 15 },
		go = "build:nest",
		icon = "nest",
	},
	{
		id = "luck",
		title = "Make the tree luckier",
		text = "Tap the Tree of Life and buy a level of Luck. Rare driftlings grow more often.",
		goal = { kind = "luck", n = 2 },
		reward = { shells = 100 },
		go = "tree",
		icon = "star",
	},
	{
		id = "food",
		title = "Grow more food",
		text = "Build a second farm or a fishing pier. Every driftling in a hut eats.",
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
		id = "rare",
		title = "Grow a rare one",
		text = "Keep the tree growing. Luck makes rare ones turn up sooner.",
		goal = { kind = "best", n = 3 },
		reward = { shells = 200 },
		go = "tree",
		icon = "star",
	},
	{
		id = "expand",
		title = "Grow your island",
		text = "In Build mode tap Expand. A bigger island fits more, and the tree grows new kinds.",
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
		id = "housed",
		title = "Ten driftlings at work",
		text = "Build huts and buildings for them. Each building takes two helpers.",
		goal = { kind = "helpers", n = 10 },
		reward = { shells = 600 },
		go = "pals",
		icon = "pal",
	},
	{
		id = "index",
		title = "Meet twelve kinds",
		text = "The Index lists every kind the tree has grown. A bigger island grows more kinds.",
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
		text = "It's on the Huts tab. Two driftlings and a feast make an egg there.",
		goal = { kind = "built", n = 1, of = "breed" },
		reward = { shells = 800 },
		go = "build:nest",
		icon = "nest",
	},
	{
		id = "egg",
		title = "Hatch an egg",
		text = "Open the Hatchery, pick two driftlings and give them a feast. It hatches a few turns later.",
		goal = { kind = "hatched", n = 1 },
		reward = { shells = 1200 },
		go = "hatch",
		icon = "nest",
	},
	{
		id = "epic",
		title = "Grow an epic one",
		text = "Epic driftlings work more than three times as fast as common ones.",
		goal = { kind = "best", n = 4 },
		reward = { shells = 2000 },
		go = "tree",
		icon = "star",
	},
	{
		id = "luck5",
		title = "A lucky tree",
		text = "Bring the tree's Luck up to level 5.",
		goal = { kind = "luck", n = 5 },
		reward = { shells = 3000 },
		go = "tree",
		icon = "tree",
	},
}

Quests.list = list
Quests.byId = {} :: { [string]: Quest }
for _, q in list do
	Quests.byId[q.id] = q
end

return Quests
