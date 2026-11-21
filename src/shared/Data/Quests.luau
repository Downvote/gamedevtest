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
-- (No second Lumber Camp any more, 2026-11-18: "this quest is uncompletable without removing a work building. thus,
-- remove the quest that asks you to make a second lumber camp". The first island has 8 work spaces, 2 a workplace: the
-- tips' camp, farm and stall and the second camp filled them, so "Another farm" could not be built. The questline
-- before the first expansion has to fit the first island's work spaces: Quest.spec checks it. No "Build another hut"
-- since 2026-11-21: the questline opens on four huts, and the tips build one workplace, not three.)
export type Goal = { kind: string, n: number, of: string? }
export type Reward = { shells: number? }
export type Quest = { id: string, title: string, text: string, goal: Goal, reward: Reward, go: string, icon: string }

local Quests = {}

local list: { Quest } = {
	{
		-- (the request of 2026-11-21: "the first goal after the tutorial should be "Place down 4 huts"": the tips build
		-- one, and four fill the first island's room for driftlings, Tuning.HousingLimit[1]; Quest.spec checks it)
		id = "huts4",
		title = "Place down 4 huts",
		text = "It's on the Huts tab. Each driftling needs a bed.",
		goal = { kind = "built", n = 4, of = "nest" },
		reward = { shells = 100 },
		go = "build:nest",
		icon = "nest",
	},
	{
		id = "help",
		title = "Put a driftling to work",
		text = "Open Driftlings to pick where one works.",
		goal = { kind = "helpers", n = 1 },
		reward = { shells = 70 },
		go = "pals",
		icon = "pal",
	},
	{
		id = "sell",
		title = "Sell a driftling",
		text = "Sell a spare one in Driftlings. Rarer ones fetch more.",
		goal = { kind = "sold", n = 1 },
		reward = { shells = 40 },
		go = "pals",
		icon = "coin",
	},
	{
		id = "take3",
		title = "Hatch three eggs",
		text = "Tap the tree to pick an egg.",
		goal = { kind = "taken", n = 3 },
		reward = { shells = 100 },
		go = "tree",
		icon = "tree",
	},
	{
		id = "three",
		title = "Three at work",
		text = "Each one needs a bed in a hut and a place to work.",
		goal = { kind = "helpers", n = 3 },
		reward = { shells = 120 },
		go = "pals",
		icon = "pal",
	},
	{
		id = "uncommon",
		title = "An uncommon one",
		text = "Look for green eggs with a white zigzag. They work faster.",
		goal = { kind = "best", n = 2 },
		reward = { shells = 100 },
		go = "tree",
		icon = "star",
	},
	{
		-- (a second farm till every workplace became one kind of work, 2026-11-19: the tips' camp, patch and stall and
		-- one more; since the tips build one workplace, 2026-11-21: the tips' one, the one "Three at work" needed and
		-- one more)
		id = "farm",
		title = "Another workplace",
		text = "Build one more on the Work tab.",
		goal = { kind = "built", n = 3, of = "work" },
		reward = { shells = 120 },
		go = "build:work",
		icon = "coin",
	},
	{
		id = "paths",
		title = "Lay a path",
		text = "Open Paths in Build mode and drag across the grass.",
		goal = { kind = "paths", n = 8 },
		reward = { shells = 60 },
		go = "build:path",
		icon = "path",
	},
	{
		id = "decor",
		title = "Decorate",
		text = "Place two from the Decor tab. Charm brings in more coins.",
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
		text = "Get a rare egg from the tree! Save some coins for one.",
		goal = { kind = "best", n = 3 },
		reward = { shells = 200 },
		go = "tree",
		icon = "star",
	},
	{
		id = "expand",
		title = "Grow your island",
		text = "Tap Expand in Build mode. Bigger islands get more and better eggs.",
		goal = { kind = "tier", n = 2 },
		reward = { shells = 600 },
		go = "build",
		icon = "home",
	},
	{
		id = "boost",
		title = "Build a boost",
		text = "Boosts help every workplace. Find them under Work.",
		goal = { kind = "built", n = 1, of = "gen" },
		reward = { shells = 400 },
		go = "build:gen",
		icon = "boost",
	},
	{
		id = "housed",
		title = "Ten at work",
		text = "Build more huts and workplaces.",
		goal = { kind = "helpers", n = 10 },
		reward = { shells = 600 },
		go = "pals",
		icon = "pal",
	},
	{
		id = "index",
		-- ("Discover 12 unique creatures", the user's words of 2026-11-14, cut short on 2026-11-19: "Across all text,
		-- humanize it and shorten it as much as possible")
		title = "Find 12 kinds",
		text = "The Index lists every kind you've found. Bigger islands hatch new ones.",
		goal = { kind = "seen", n = 12 },
		reward = { shells = 500 },
		go = "index",
		icon = "star",
	},
	{
		id = "town",
		title = "Expand again",
		text = "The Hatchery needs the room.",
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
		text = "Breed two driftlings for an egg. Rarer parents, rarer eggs. Mutations pass on.",
		goal = { kind = "hatched", n = 1 },
		reward = { shells = 1200 },
		go = "hatch",
		icon = "nest",
	},
	{
		id = "epic",
		title = "An epic one",
		text = "Epics work over three times as fast as commons.",
		goal = { kind = "best", n = 4 },
		reward = { shells = 3000 },
		go = "tree",
		icon = "star",
	},
	{
		id = "crowd",
		title = "Sixty hatched",
		text = "Swap weak ones out as better ones hatch.",
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
