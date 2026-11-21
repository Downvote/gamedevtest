--!strict
-- The kinds of land the driftlings come from (GAME_DESIGN 6). Pure. The driftlings of every kind open at the island's
-- tier (`tier`) hatch from the tree's eggs: dunes and meadows from the start, then two more kinds with the second
-- tier, two with the third, and one with each tier after to the sixth, so expanding the island brings new driftlings;
-- past the capital the moonwoods at tier 11 (the first mythic driftling), the cloudtops at 14 (the first celestial one)
-- and the starfalls at 17. The Index lists the driftlings kind by kind.
--   wild: the kind's driftlings (Data/Creatures' islet: every one of the kind, the commonest first)
local Creatures = require(script.Parent.Creatures)
export type IsletDef = {
	id: number,
	name: string, -- the kind ("Dune")
	plural: string, -- ("Dunes")
	tier: number, -- the island tier its driftlings start hatching at
	wild: { string },
	color: string,
	blurb: string,
}

-- stylua: ignore start
local LIST: { IsletDef } = {
	{ id = 1, name = "Dune", plural = "Dunes", tier = 1, wild = {}, color = "sand", blurb = "Warm sand and grumpy crabs." },
	{ id = 2, name = "Meadow", plural = "Meadows", tier = 1, wild = {}, color = "leaf", blurb = "Ferns and mossy stones." },
	{ id = 3, name = "Volcano", plural = "Volcanoes", tier = 3, wild = {}, color = "orange", blurb = "Smoke and hot sand." },
	{ id = 4, name = "Snowfield", plural = "Snowfields", tier = 2, wild = {}, color = "window", blurb = "Cold, windy peaks." },
	{ id = 5, name = "Sky Reef", plural = "Sky Reefs", tier = 4, wild = {}, color = "blue", blurb = "It glows among the clouds." },
	{ id = 6, name = "Rootwood", plural = "Rootwoods", tier = 2, wild = {}, color = "leaf_dark", blurb = "Roots trailing into the warm mist." },
	{ id = 7, name = "Grotto", plural = "Grottoes", tier = 3, wild = {}, color = "purple", blurb = "A cave in the rock, full of crystals." },
	{ id = 8, name = "Bluffs", plural = "Bluffs", tier = 5, wild = {}, color = "wood", blurb = "Grassy cliffs in the wind." },
	{ id = 9, name = "Ruins", plural = "Ruins", tier = 6, wild = {}, color = "sand_dark", blurb = "What's left of an old city." },
	{ id = 10, name = "Moonwood", plural = "Moonwoods", tier = 11, wild = {}, color = "crystal", blurb = "A silver forest that wakes at dusk." },
	{ id = 11, name = "Cloudtop", plural = "Cloudtops", tier = 14, wild = {}, color = "white", blurb = "Fields of soft cloud, high up." },
	{ id = 12, name = "Starfall", plural = "Starfalls", tier = 17, wild = {}, color = "night", blurb = "Fallen stars, still glowing." },
}
-- stylua: ignore end
-- Each kind's driftlings: every species of its kind, the commonest first.
for _, d in LIST do
	local out: { string } = {}
	for _, c in Creatures.list do
		if c.islet == d.id then
			table.insert(out, c.id)
		end
	end
	table.sort(out, function(a, b)
		local ra, rb = Creatures.byId[a].rarity, Creatures.byId[b].rarity
		if ra ~= rb then
			return ra < rb
		end
		return a < b
	end)
	d.wild = out
end

return table.freeze({ list = LIST })
