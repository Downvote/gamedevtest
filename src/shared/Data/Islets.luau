--!strict
-- The kinds of land the driftlings come from (GAME_DESIGN 6). Pure. The driftlings of every kind open at the island's
-- tier (`tier`) hatch from the tree's eggs: beaches and meadows from the start, then two more kinds with the second
-- tier, two with the third, and one with each tier after, so expanding the island brings new driftlings. The Index
-- lists the driftlings kind by kind.
--   wild: the kind's driftlings (Data/Creatures' islet: every one of the kind, the commonest first)
local Creatures = require(script.Parent.Creatures)
export type IsletDef = {
	id: number,
	name: string, -- the kind ("Beach")
	plural: string, -- ("Beaches")
	tier: number, -- the island tier its driftlings start hatching at
	wild: { string },
	color: string,
	blurb: string,
}

-- stylua: ignore start
local LIST: { IsletDef } = {
	{ id = 1, name = "Beach", plural = "Beaches", tier = 1, wild = {}, color = "sand", blurb = "Warm sand, tide pools and grumpy crabs." },
	{ id = 2, name = "Meadow", plural = "Meadows", tier = 1, wild = {}, color = "leaf", blurb = "A green maze of ferns and mossy stones." },
	{ id = 3, name = "Volcano", plural = "Volcanoes", tier = 3, wild = {}, color = "orange", blurb = "A smoking volcano with hot sands." },
	{ id = 4, name = "Snowfield", plural = "Snowfields", tier = 2, wild = {}, color = "window", blurb = "Snowy peaks where nothing stays still." },
	{ id = 5, name = "Reef", plural = "Reefs", tier = 4, wild = {}, color = "blue", blurb = "A sunken reef that glows at the bottom of the sea." },
	{ id = 6, name = "Mangrove", plural = "Mangroves", tier = 2, wild = {}, color = "leaf_dark", blurb = "Tangled roots over warm brown water." },
	{ id = 7, name = "Grotto", plural = "Grottoes", tier = 3, wild = {}, color = "purple", blurb = "Glowing crystals in a cave by the sea." },
	{ id = 8, name = "Bluffs", plural = "Bluffs", tier = 5, wild = {}, color = "wood", blurb = "Grassy cliffs high in the sea wind." },
	{ id = 9, name = "Ruins", plural = "Ruins", tier = 6, wild = {}, color = "sand_dark", blurb = "The broken stones of an old city." },
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
