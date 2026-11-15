--!strict
-- The questline (GAME_DESIGN 9: "make a questline such that players are guided throughout the features of the game,
-- such as assigning creatures to different work areas"). Pure data. After the tips, one quest at a time, in order:
-- each names something to do, says where to do it, and pays a small reward when the player claims it (Logic/Quest).
--   goal: what it counts (Logic/Quest.count) and how many; `of` a building kind for "built".
--     "helpers" driftlings at work, "housed" driftlings in huts, "paths" path tiles, "decor" decorations, "built"
--     pieces of a kind, "taken" the tree's eggs hatched, "sold" driftlings sold, "best" the rarest driftling
--     had (1 .. 5), "tier" the island's tier, "seen" kinds in the Index, "hatched" eggs hatched
--   go: where its Go button takes the player: a panel ("pals" "index" "hatch" "tree") or Build mode ("build",
--     or "build:<tab>")
--   reward: shells (the one store since 2026-11-14; a quest that paid wood pays the same in shells)
export type Goal = { kind: string, n: number, of: string? }
export type Reward = { shells: number? }
export type Quest = { id: string, title: string, text: string, goal: Goal, reward: Reward, go: string, icon: string }

local Quests = {}

local list: { Quest } = {
	{
		id = "help",
		title = "Put a driftling to work",
		text = "A driftling in a hut can work at any farm, camp or shop. Open Driftlings to pick where.",
		goal = { kind = "helpers", n = 1 },
		reward = { shells = 70 },
		go = "pals",
		icon = "pal",
	},
	{
		id = "sell",
		title = "Sell a driftling",
		text = "Open Driftlings and sell one you don't need. Rarer ones fetch more.",
		goal = { kind = "sold", n = 1 },
		reward = { shells = 40 },
		go = "pals",
		icon = "shell",
	},
	{
		id = "take3",
		title = "Hatch three eggs",
		text = "The Tree of Life lays eggs round its roots. Tap the tree to pick one to hatch.",
		goal = { kind = "taken", n = 3 },
		reward = { shells = 100 },
		go = "tree",
		icon = "tree",
	},
	{
		id = "camp",
		title = "Another camp",
		text = "Build a second Lumber Camp. It sells what it cuts for shells.",
		goal = { kind = "built", n = 2, of = "wood" },
		reward = { shells = 80 },
		go = "build:wood",
		icon = "wood",
	},
	{
		id = "three",
		title = "Three at work",
		text = "Get three driftlings working. Each needs a bed in a hut (a hut sleeps two) and a farm, camp or shop to work at.",
		goal = { kind = "helpers", n = 3 },
		reward = { shells = 120 },
		go = "pals",
		icon = "pal",
	},
	{
		id = "huts",
		title = "Build another hut",
		text = "Huts are on the Huts tab. A driftling needs a free bed before you can take it in.",
		goal = { kind = "built", n = 2, of = "nest" },
		reward = { shells = 100 },
		go = "build:nest",
		icon = "nest",
	},
	{
		id = "uncommon",
		title = "An uncommon one",
		text = "Green eggs with a white zigzag hatch uncommon ones. They cost more and work faster.",
		goal = { kind = "best", n = 2 },
		reward = { shells = 100 },
		go = "tree",
		icon = "star",
	},
	{
		id = "farm",
		title = "Another farm",
		text = "Build a second farm or a fishing pier. They sell what they grow for shells.",
		goal = { kind = "built", n = 2, of = "farm" },
		reward = { shells = 120 },
		go = "build:farm",
		icon = "shell",
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
		text = "Place two things from the Decor tab. More charm, more shells from every building.",
		goal = { kind = "decor", n = 2 },
		reward = { shells = 100 },
		go = "build:decor",
		icon = "decor",
	},
	{
		id = "rare",
		title = "A rare one",
		-- (the user's words of 2026-11-14: "Get a rare egg from the tree! Save some shells for one.", and the tree
		-- keeps one under it while this quest is on: Logic/Tree.ensure)
		text = "Get a rare egg from the tree! There's always one under it while this quest is on. Save some shells for it.",
		goal = { kind = "best", n = 3 },
		reward = { shells = 200 },
		go = "tree",
		icon = "star",
	},
	{
		id = "expand",
		title = "Grow your island",
		text = "In Build mode tap Expand. A bigger island fits more, and the tree lays more eggs, and better ones.",
		goal = { kind = "tier", n = 2 },
		reward = { shells = 600 },
		go = "build",
		icon = "home",
	},
	{
		id = "boost",
		title = "Build a boost",
		text = "Boosts make every building of one kind work faster. They're on the Boosts tab.",
		goal = { kind = "built", n = 1, of = "gen" },
		reward = { shells = 400 },
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
		-- (the user's words of 2026-11-14)
		title = "Discover 12 unique creatures",
		text = "The Index lists every creature you discovered. Expanding your island lets you discover more.",
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
		reward = { shells = 2300 },
		go = "build",
		icon = "home",
	},
	{
		id = "hatchery",
		title = "Build a Hatchery",
		text = "It's on the Huts tab. Breed two driftlings there for an egg.",
		goal = { kind = "built", n = 1, of = "breed" },
		reward = { shells = 800 },
		go = "build:nest",
		icon = "nest",
	},
	{
		id = "egg",
		title = "Hatch an egg",
		text = "Breed two driftlings for an egg. Rarer parents tend to make rarer eggs. Mutations both carry pass on.",
		goal = { kind = "hatched", n = 1 },
		reward = { shells = 1200 },
		go = "hatch",
		icon = "nest",
	},
	{
		id = "epic",
		title = "An epic one",
		text = "Epic driftlings work more than three times as fast as common ones.",
		goal = { kind = "best", n = 4 },
		reward = { shells = 3000 },
		go = "tree",
		icon = "star",
	},
	{
		id = "crowd",
		title = "Sixty hatched",
		text = "Hatch sixty eggs in all. Swap out the weak ones as better ones come.",
		goal = { kind = "taken", n = 60 },
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
