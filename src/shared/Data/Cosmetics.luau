--!strict
-- What a founder can wear besides their skin, hair and shirt colour (GAME_DESIGN 14; the request of 2026-11-14: "make
-- much more cosmetics, and a rotating shop for cosmetics"). Pure.
--   Every piece goes in one slot (SLOTS: a hat, something on the face, round the neck, on the back, in the hand, or a
--   top worn over the shirt) and has a rarity (1 common .. 5 legendary: Data/Traits.RARITY's names and colours) and a
--   source (`src`):
--     "shop"   on sale in the rotating shop now and then (Logic/Store.shopNow), for shells (Tuning.CosmeticPrice by
--              rarity, times Tuning.EggTier by the island's tier)
--     "track"  a reward on the pass track's free side (Data/Track), "trackp" on its premium side
--     "vip"    comes with the VIP pass, "starter" with the starter pack
--   Owned pieces are Profile.owned[id]; the founder wears at most one a slot (Types.Look's slot fields, "" for none).
--   Models/CharacterModels draws each on the founder's rig by its id (`kind` says what it is, for the model).
export type Piece = { id: string, slot: string, name: string, rarity: number, src: string }

local SLOTS: { { id: string, name: string } } = {
	{ id = "hat", name = "Hat" },
	{ id = "face", name = "Face" },
	{ id = "neck", name = "Neck" },
	{ id = "back", name = "Back" },
	{ id = "hand", name = "Hand" },
	{ id = "top", name = "Top" },
}

local LIST: { Piece } = {}
local BY_ID: { [string]: Piece } = {}
local function P(slot: string, id: string, name: string, rarity: number, src: string?)
	local p: Piece = { id = id, slot = slot, name = name, rarity = rarity, src = src or "shop" }
	assert(BY_ID[id] == nil, "Cosmetics: duplicate id " .. id)
	table.insert(LIST, p)
	BY_ID[id] = p
end

-- hats
P("hat", "strawhat", "Straw Hat", 1)
P("hat", "buckethat", "Bucket Hat", 1)
P("hat", "bandana", "Bandana", 1)
P("hat", "beanie", "Knit Beanie", 1)
P("hat", "sunvisor", "Sun Visor", 1)
P("hat", "flowercrown", "Flower Crown", 2)
P("hat", "captaincap", "Captain's Cap", 2)
P("hat", "leafhat", "Big Leaf", 2)
P("hat", "shellcap", "Shell Cap", 2)
P("hat", "tricorn", "Tricorn Hat", 3)
P("hat", "froghood", "Frog Hood", 3)
P("hat", "coconuthelm", "Coconut Helmet", 3)
P("hat", "wizardhat", "Star Wizard Hat", 4)
P("hat", "halo", "Halo", 4)
P("hat", "fishbowl", "Fishbowl", 4)
P("hat", "eggshellcap", "Eggshell Cap", 4)
P("hat", "explorerhat", "Explorer Hat", 3, "starter")
P("hat", "driftears", "Driftling Ears", 3, "track")
P("hat", "tidecrown", "Tide Crown", 5, "trackp")
P("hat", "goldcrown", "Gold Crown", 5, "vip")
-- the face
P("face", "sunglasses", "Sunglasses", 1)
P("face", "roundglasses", "Round Glasses", 1)
P("face", "rosycheeks", "Rosy Cheeks", 1)
P("face", "snorkel", "Snorkel Mask", 2)
P("face", "eyepatch", "Eye Patch", 2)
P("face", "moustache", "Curly Moustache", 2)
P("face", "monocle", "Monocle", 3)
P("face", "heartshades", "Heart Shades", 3)
P("face", "stargoggles", "Star Goggles", 3)
P("face", "leafpaint", "Leaf Paint", 2, "track")
P("face", "glowvisor", "Glow Visor", 4, "trackp")
P("face", "goldshades", "Gold Shades", 5, "vip")
-- round the neck
P("neck", "lei", "Flower Lei", 1)
P("neck", "scarf", "Striped Scarf", 1)
P("neck", "shellnecklace", "Shell Necklace", 1)
P("neck", "whistle", "Whistle", 1)
P("neck", "bowtie", "Bow Tie", 2)
P("neck", "bell", "Little Bell", 2)
P("neck", "medal", "Medal", 3)
P("neck", "anchorpendant", "Anchor Pendant", 3)
P("neck", "pearls", "Pearl String", 3)
P("neck", "crystalamulet", "Crystal Amulet", 4)
P("neck", "feathercollar", "Feather Collar", 3, "track")
P("neck", "goldchain", "Gold Chain", 5, "vip")
-- on the back
P("back", "backpack", "Backpack", 1)
P("back", "surfboard", "Surfboard", 2)
P("back", "shellpack", "Shell Pack", 2)
P("back", "redcape", "Red Cape", 2)
P("back", "butterflywings", "Butterfly Wings", 3)
P("back", "kite", "Kite", 3)
P("back", "turtleshell", "Turtle Shell", 3)
P("back", "leafwings", "Leaf Wings", 3)
P("back", "featherwings", "Feather Wings", 4)
P("back", "rocketpack", "Coconut Rocket", 4)
P("back", "eggbasket", "Egg Basket", 2, "track")
P("back", "drakewings", "Drake Wings", 4, "trackp")
P("back", "starcape", "Starry Cape", 5, "trackp")
P("back", "royalcape", "Royal Cape", 5, "vip")
-- in the hand
P("hand", "bugnet", "Bug Net", 1)
P("hand", "shovel", "Sand Shovel", 1)
P("hand", "icecream", "Ice Cream", 1)
P("hand", "lantern", "Paper Lantern", 2)
P("hand", "umbrella", "Paper Umbrella", 2)
P("hand", "fishingrod", "Fishing Rod", 2)
P("hand", "balloon", "Balloon", 2)
P("hand", "ukulele", "Ukulele", 3)
P("hand", "starwand", "Star Wand", 4)
P("hand", "tikitorch", "Tiki Torch", 3, "track")
P("hand", "trident", "Trident", 4, "trackp")
P("hand", "scepter", "Shell Scepter", 5, "vip")
-- tops, worn over the shirt
P("top", "sailor", "Sailor Shirt", 1)
P("top", "stripes", "Striped Tee", 1)
P("top", "flowershirt", "Flower Shirt", 2)
P("top", "overalls", "Overalls", 2)
P("top", "fishingvest", "Fishing Vest", 2)
P("top", "hoodie", "Hoodie", 2)
P("top", "raincoat", "Raincoat", 3)
P("top", "tuxedo", "Tuxedo", 4)
P("top", "starrobe", "Star Robe", 4)
P("top", "lifevest", "Life Vest", 3, "track")
P("top", "explorershirt", "Explorer Shirt", 3, "starter")
P("top", "tiderobe", "Tide Robe", 5, "trackp")
P("top", "goldjacket", "Gold Jacket", 5, "vip")

local SLOT_IDS: { [string]: boolean } = {}
for _, s in SLOTS do
	SLOT_IDS[s.id] = true
end
for _, p in LIST do
	assert(SLOT_IDS[p.slot], "Cosmetics: unknown slot " .. p.slot)
end

local BY_SLOT: { [string]: { Piece } } = {}
for _, s in SLOTS do
	BY_SLOT[s.id] = {}
end
for _, p in LIST do
	table.insert(BY_SLOT[p.slot], p)
end

-- The pieces a source gives, in list order ("vip", "starter", ...).
local function from(src: string): { string }
	local out: { string } = {}
	for _, p in LIST do
		if p.src == src then
			table.insert(out, p.id)
		end
	end
	return out
end

return table.freeze({
	SLOTS = SLOTS,
	list = LIST,
	byId = BY_ID,
	bySlot = BY_SLOT,
	from = from,
})
