--!strict
-- The questline (GAME_DESIGN 9: "make a questline such that players are guided throughout the features of the game,
-- such as assigning creatures to different work areas"). Pure data. After the tips, one quest at a time, in order:
-- each names something to do, says where to do it, and pays a small reward when the player claims it (Logic/Quest).
--   goal: what it counts (Logic/Quest.count) and how many; `of` a building kind for "built".
--     "helpers" driftlings at work, "housed" driftlings in huts, "paths" path tiles, "decor" decorations, "built"
--     pieces of a kind, "taken" driftlings taken in off the tide, "sold" driftlings sold, "best" the rarest driftling
--     had (1 .. 5), "tier" the island's tier, "seen" kinds in the Index, "hatched" eggs hatched
--   go: where its Go button takes the player: a panel ("pals" "index" "hatch" "tide") or Build mode ("build",
--     or "build:<tab>")
--   reward: wood for the building quests, shells for the driftling ones (what each pays for)
export type Goal = { kind: string, n: number, of: string? }
export type Reward = { shells: number?, wood: number? }
export type Quest = { id: string, title: string, text: string, goal: Goal, reward: Reward, go: string, icon: string }

local Quests = {}

local list: { Quest } = {
	{
		id = "help",
		title = "Put a driftling to work",
		text = "A driftling in a hut works at a building that suits it. Open Driftlings to see where.",
		goal = { kind = "helpers", n = 1 },
		reward = { shells = 40, wood = 30 },
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
		title = "Three off the tide",
		text = "Driftlings float past the island. Tap one to take it in.",
		goal = { kind = "taken", n = 3 },
		reward = { shells = 60, wood = 40 },
		go = "tide",
		icon = "tide",
	},
	{
		id = "camp",
		title = "More wood",
		text = "Build a second Lumber Camp. Wood pays for everything you build.",
		goal = { kind = "built", n = 2, of = "wood" },
		reward = { wood = 80 },
		go = "build:wood",
		icon = "wood",
	},
	{
		id = "three",
		title = "Three at work",
		text = "Get three driftlings working. Each one goes to a building that suits it.",
		goal = { kind = "helpers", n = 3 },
		reward = { shells = 60, wood = 60 },
		go = "pals",
		icon = "pal",
	},
	{
		id = "huts",
		title = "Build another hut",
		text = "Huts are on the Huts tab. A driftling needs a free bed before you can take it in.",
		goal = { kind = "built", n = 2, of = "nest" },
		reward = { wood = 100 },
		go = "build:nest",
		icon = "nest",
	},
	{
		id = "uncommon",
		title = "An uncommon one",
		text = "Uncommon ones float by now and then. They cost more and work faster.",
		goal = { kind = "best", n = 2 },
		reward = { shells = 100 },
		go = "tide",
		icon = "star",
	},
	{
		id = "farm",
		title = "Another farm",
		text = "Build a second farm or a fishing pier. They sell what they grow for shells.",
		goal = { kind = "built", n = 2, of = "farm" },
		reward = { wood = 120 },
		go = "build:farm",
		icon = "shell",
	},
	{
		id = "paths",
		title = "Lay a path",
		text = "In Build mode open Paths, pick one and drag across the grass.",
		goal = { kind = "paths", n = 8 },
		reward = { wood = 60 },
		go = "build:path",
		icon = "path",
	},
	{
		id = "decor",
		title = "Decorate",
		text = "Place two things from the Decor tab. Charm brings in more visitors.",
		goal = { kind = "decor", n = 2 },
		reward = { wood = 100 },
		go = "build:decor",
		icon = "decor",
	},
	{
		id = "rare",
		title = "A rare one",
		text = "Rare ones carry a lantern. Save some shells for one.",
		goal = { kind = "best", n = 3 },
		reward = { shells = 200 },
		go = "tide",
		icon = "star",
	},
	{
		id = "expand",
		title = "Grow your island",
		text = "In Build mode tap Expand. A bigger island fits more, and new kinds float by.",
		goal = { kind = "tier", n = 2 },
		reward = { shells = 200, wood = 400 },
		go = "build",
		icon = "home",
	},
	{
		id = "boost",
		title = "Build a boost",
		text = "Boosts make every building of one kind work faster. They're on the Boosts tab.",
		goal = { kind = "built", n = 1, of = "gen" },
		reward = { wood = 400 },
		go = "build:gen",
		icon = "boost",
	},
	{
		id = "housed",
		title = "Ten driftlings at work",
		text = "Build huts and buildings for them. Each building takes two helpers.",
		goal = { kind = "helpers", n = 10 },
		reward = { shells = 300, wood = 300 },
		go = "pals",
		icon = "pal",
	},
	{
		id = "index",
		title = "Meet twelve kinds",
		text = "The Index lists every kind that has floated by. A bigger island brings more kinds.",
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
		reward = { shells = 800, wood = 1500 },
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
		text = "Open the Hatchery, pick two driftlings and pay for a feast. It hatches a few turns later.",
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
		reward = { wood = 3000 },
		go = "tide",
		icon = "star",
	},
	{
		id = "crowd",
		title = "Sixty off the tide",
		text = "Take in sixty driftlings in all. Swap out the weak ones as better ones come.",
		goal = { kind = "taken", n = 60 },
		reward = { shells = 3000 },
		go = "tide",
		icon = "tide",
	},
}

Quests.list = list
Quests.byId = {} :: { [string]: Quest }
for _, q in list do
	Quests.byId[q.id] = q
end

return Quests
