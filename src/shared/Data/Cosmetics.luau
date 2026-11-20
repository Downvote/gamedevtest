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
--     "free"   everyone has it (the bakery's own hats and faces: the chef hats, the beret, glasses ...)
--   Owned pieces are Profile.owned[id] (a "free" one always: `owns`); the founder wears at most one a slot (Types.Look's
--   slot fields, "" for none). Models/CosmeticModels draws this game's pieces on the founder's rig by their id.
--   Random Bakery's accessories (the request of 2026-11-20: "Port the entire character customization menu from the
--   bakery game to this game, such accessory colors and other features, along with the accessories it has"): every hat,
--   face, back, neck and hand piece of the bakery's Boutique, Costume Rack, contests, Weekly Cup and rewards, and its
--   own free hats and faces. Each carries `kind` (its model in Models/AccessoryModels), `color` and `accent` (its two
--   palette keys, what a tint changes: Data/Looks.tinted), and for a hat `covers` (it hides the hair that sticks up),
--   `bottom` (a covering hat's lower edge in the bakery's head space) and `head` (it is the whole head: the Pumpkin
--   Head, Headless); `rainbow` pieces keep their colours under a tint. Their ids are the bakery's, but for the few
--   that clashed with ours (dotted_bandana, cuffed_beanie, bright_halo, plain_moustache, gold_monocle, black_eyepatch,
--   gold_medal, rain_umbrella); a few names changed for the same reason (Rose Crown, Wire Glasses, Hero Cape ...) or
--   because they named a baker (Bushy Beard, Headless). Their rarity: Common .. Legendary as sold, Mythic and Divine
--   as Mythic and Celestial (6, 7), an event's or a contest's Epic, a Weekly Cup prize Mythic, a reward look Celestial.
export type Piece = {
	id: string,
	slot: string,
	name: string,
	rarity: number,
	src: string,
	kind: string?,
	color: string?,
	accent: string?,
	covers: string?,
	bottom: number?,
	head: boolean?,
	rainbow: boolean?,
}

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

-- (a bakery piece: drawn by Models/AccessoryModels as `kind`)
local function B(slot: string, id: string, name: string, rarity: number, src: string, kind: string, color: string?, accent: string?, extra: { covers: string?, bottom: number?, head: boolean?, rainbow: boolean? }?)
	local p: Piece = { id = id, slot = slot, name = name, rarity = rarity, src = src, kind = kind, color = color, accent = accent }
	if extra then
		p.covers, p.bottom, p.head, p.rainbow = extra.covers, extra.bottom, extra.head, extra.rainbow
	end
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

-- stylua: ignore start
------------------------------------------------------------------ Random Bakery's accessories (Models/AccessoryModels)
-- hats
B("hat", "toque", "Chef Hat", 1, "free", "b_toque", "white", nil, { covers = "top" })
B("hat", "tall_toque", "Head Chef Hat", 1, "free", "b_tall_toque", "white", nil, { covers = "top" })
B("hat", "beret", "Beret", 1, "free", "b_beret", "berry_red", nil)
B("hat", "dotted_bandana", "Dotted Bandana", 1, "free", "b_bandana", "berry_red", "white", { covers = "top" })
B("hat", "cap", "Cap", 1, "free", "b_cap", "blue", "white", { covers = "top" })
B("hat", "cuffed_beanie", "Cuffed Beanie", 1, "free", "b_beanie", "orange", "cream", { covers = "top" })
B("hat", "cupcake", "Cupcake Hat", 1, "free", "b_cupcake", "pink", "cream", { covers = "top" })
B("hat", "bunny_ears", "Bunny Ears", 1, "free", "b_bunny_ears", "white", "pink")
B("hat", "cat_ears", "Cat Ears", 1, "free", "b_cat_ears", nil, "pink")
B("hat", "flower", "Flower", 1, "free", "b_flower", "pink", "yellow")
B("hat", "witch_hat", "Witch Hat", 4, "shop", "b_witch_hat", "purple", "black")
B("hat", "pumpkin_head", "Pumpkin Head", 4, "shop", "b_pumpkin_head", "orange", "green", { head = true })
B("hat", "headless", "Headless", 4, "shop", "b_headless", "orange", "yellow", { head = true })
B("hat", "moth_antennae", "Moth Antennae", 4, "shop", "b_moth_antennae", "sponge", "chocolate")
B("hat", "devil_horns", "Devil Horns", 4, "shop", "b_devil_horns", "berry_red", "plate_lacquer")
B("hat", "floating_jacks", "Floating Pumpkins", 4, "shop", "floating_jacks", "orange", "yellow")
B("hat", "cauldron_hat", "Bubbling Cauldron Hat", 4, "shop", "cauldron_hat", "black", "green", { covers = "top", bottom = 4.3 })
B("hat", "soulflame_halo", "Soulflame Halo", 4, "shop", "soulflame_halo", "green", "purple", { rainbow = true })
B("hat", "crown_gold", "Golden Crown", 5, "shop", "crown", "gold", "berry_red")
B("hat", "crown_silver", "Silver Crown", 4, "shop", "crown", "steel", "r_rare")
B("hat", "tiara", "Tiara", 4, "shop", "tiara", "plate_gold", "r_mythic")
B("hat", "flower_crown", "Rose Crown", 3, "shop", "flower_crown", "pink", "green")
B("hat", "sunflower_crown", "Sunflower Crown", 3, "shop", "sunflower_crown", "yellow", "green")
B("hat", "top_hat", "Top Hat", 3, "shop", "top_hat", "black", "berry_red", { covers = "top", bottom = 4.5 })
B("hat", "lilac_top_hat", "Lilac Top Hat", 4, "shop", "top_hat", "purple", "gold", { covers = "top", bottom = 4.5 })
B("hat", "party_hat", "Party Hat", 1, "shop", "party_hat", "pink", "yellow")
B("hat", "blue_party_hat", "Blue Party Hat", 1, "shop", "party_hat", "blue", "white")
B("hat", "cowboy_hat", "Cowboy Hat", 2, "shop", "cowboy_hat", "wood", "chocolate", { covers = "top", bottom = 4.4 })
B("hat", "pirate_hat", "Pirate Hat", 3, "shop", "pirate_hat", "black", "plate_gold", { covers = "top", bottom = 4.4 })
B("hat", "wizard_hat", "Wizard Hat", 4, "shop", "wizard_hat", "sky_night", "gold", { covers = "top", bottom = 4.4 })
B("hat", "bright_halo", "Bright Halo", 5, "shop", "halo", "gold", "white")
B("hat", "propeller_cap", "Propeller Cap", 2, "shop", "propeller_cap", "r_rare", "yellow", { covers = "top", bottom = 4.25 })
B("hat", "bear_ears", "Bear Ears", 1, "shop", "bear_ears", "chocolate", "pink")
B("hat", "fox_ears", "Fox Ears", 2, "shop", "fox_ears", "orange", "white")
B("hat", "mouse_ears", "Mouse Ears", 1, "shop", "mouse_ears", "black", "pink")
B("hat", "antlers", "Antlers", 2, "shop", "antlers", "wood", "wood_dark")
B("hat", "unicorn_horn", "Unicorn Horn", 4, "shop", "unicorn_horn", "white", "gold")
B("hat", "headphones", "Headphones", 2, "shop", "headphones", "steel_dark", "r_mythic")
B("hat", "sun_hat", "Sun Hat", 2, "shop", "sun_hat", "sponge", "pink", { covers = "top", bottom = 4.45 })
B("hat", "mint_beanie", "Mint Pompom Beanie", 1, "shop", "pompom_beanie", "green", "white", { covers = "top", bottom = 4.1 })
B("hat", "red_beanie", "Red Pompom Beanie", 1, "shop", "pompom_beanie", "berry_red", "white", { covers = "top", bottom = 4.1 })
B("hat", "viking_helmet", "Viking Helmet", 3, "shop", "viking_helmet", "steel", "cream", { covers = "top", bottom = 4.2 })
B("hat", "hard_hat", "Hard Hat", 1, "shop", "hard_hat", "yellow", "orange", { covers = "top", bottom = 4.3 })
B("hat", "graduation_cap", "Graduation Cap", 2, "shop", "graduation_cap", "black", "gold", { covers = "top", bottom = 4.35 })
B("hat", "santa_hat", "Santa Hat", 2, "shop", "santa_hat", "berry_red", "white", { covers = "top", bottom = 4.15 })
B("hat", "frog_hat", "Frog Hat", 3, "shop", "frog_hat", "green", "white", { covers = "top", bottom = 4.15 })
B("hat", "pink_bow_band", "Pink Bow Headband", 1, "shop", "bow_headband", "pink", "white")
B("hat", "blue_bow_band", "Blue Bow Headband", 1, "shop", "bow_headband", "blue", "white")
B("hat", "sweatband", "Sweatband", 1, "shop", "sweatband", "white", "berry_red")
B("hat", "cherry_clips", "Cherry Clips", 1, "shop", "cherry_clips", "berry_red", "green")
B("hat", "rat_buddy", "Rat Buddy", 7, "shop", "rat_buddy", "steel", "pink")
B("hat", "chick_nest", "Chick Nest", 7, "shop", "chick_nest", "wood", "yellow")
B("hat", "sleepy_kitten", "Sleepy Kitten", 7, "shop", "sleepy_kitten", "orange", "cream")
B("hat", "heart_boppers", "Heart Boppers", 6, "shop", "heart_boppers", "berry_red", "pink")
B("hat", "cloud_beanie", "Cloud Beanie", 4, "shop", "cloud_beanie", "white", "pink", { covers = "top", bottom = 4.1 })
B("hat", "gummy_crown", "Gummy Crown", 4, "shop", "gummy_crown", "purple", "pink")
B("hat", "brittle_crown", "Brittle Crown", 4, "shop", "brittle_crown", "wood", "r_legend")
B("hat", "matcha_sun_hat", "Matcha Sun Hat", 4, "shop", "sun_hat", "green", "cream", { covers = "top", bottom = 4.45 })
B("hat", "dream_puff_halo", "Dream Puff Halo", 6, "shop", "dream_puff_halo", "white", "pink")
B("hat", "caramel_drip_crown", "Caramel Drip Crown", 6, "shop", "caramel_drip_crown", "orange", "pink", { covers = "top", bottom = 4.3 })
B("hat", "wafer_spire_crown", "Wafer Spire Crown", 6, "shop", "wafer_spire_crown", "sponge", "gold", { covers = "top", bottom = 4.35 })
B("hat", "steaming_teacup_hat", "Steaming Teacup Hat", 6, "shop", "steaming_teacup_hat", "green", "pink", { covers = "top", bottom = 4.4 })
B("hat", "bonbon_tiara", "Bonbon Tiara", 6, "shop", "bonbon_tiara", "berry_red", "pink")
B("hat", "sprinkle_storm_crown", "Sprinkle Storm Crown", 6, "shop", "sprinkle_storm_crown", "purple", "yellow")
B("hat", "four_leaf_crown", "Clover Crown", 7, "shop", "four_leaf_crown", "gold", "r_uncommon")
B("hat", "croissant_crown", "Croissant Crown", 7, "shop", "croissant_crown", "r_legend", "yellow")
-- the face
B("face", "blush", "Blush", 1, "free", "b_blush", "pink", nil)
B("face", "glasses", "Glasses", 1, "free", "b_glasses", "black", nil)
B("face", "shades", "Shades", 1, "free", "b_shades", "black", nil)
B("face", "freckles", "Freckles", 1, "free", "b_freckles", "chocolate", nil)
B("face", "plain_moustache", "Moustache", 1, "free", "b_moustache", nil, nil)
B("face", "vampire_fangs", "Vampire Fangs", 4, "shop", "b_vampire_fangs", "white", "plate_lacquer")
B("face", "masquerade_mask", "Masquerade Mask", 4, "shop", "b_masquerade_mask", "purple", "gold")
B("face", "glowing_eyes", "Glowing Eyes", 4, "shop", "glowing_eyes", "green", "white")
B("face", "ghost_breath", "Ghostly Breath", 4, "shop", "ghost_breath", "white", "sky_day")
B("face", "gold_monocle", "Gold Monocle", 3, "shop", "monocle", "gold", "window")
B("face", "black_eyepatch", "Black Eyepatch", 2, "shop", "eyepatch", "black", "black")
B("face", "star_glasses", "Star Glasses", 3, "shop", "star_glasses", "yellow", "ink")
B("face", "heart_glasses", "Heart Glasses", 3, "shop", "heart_glasses", "r_mythic", "ink")
B("face", "round_glasses", "Wire Glasses", 2, "shop", "round_glasses", "gold", "window")
B("face", "goggles", "Goggles", 2, "shop", "goggles", "wood", "sky_day")
B("face", "clown_nose", "Clown Nose", 1, "shop", "clown_nose", "berry_red", "white")
B("face", "whiskers", "Whiskers", 1, "shop", "whiskers", "ink", "pink")
B("face", "bandage", "Bandage", 1, "shop", "bandage", "cream", "pink")
B("face", "curly_moustache", "Twirly Moustache", 2, "shop", "curly_moustache", "black", "black")
B("face", "beard", "Bushy Beard", 2, "shop", "beard", "chocolate", "choco_dark")
B("face", "heart_paint", "Heart Face Paint", 1, "shop", "heart_paint", "r_mythic", "pink")
B("face", "star_paint", "Star Face Paint", 1, "shop", "star_paint", "yellow", "gold")
B("face", "sweat_drop", "Sweat Drop", 1, "shop", "sweat_drop", "sky_day", "white")
B("face", "visor", "Cool Visor", 3, "shop", "visor", "r_rare", "white")
B("face", "icing_smudge", "Icing Smudge", 1, "shop", "icing_smudge", "cream", "pink")
B("face", "bubble_gum", "Bubble Gum", 6, "shop", "bubble_gum", "pink", "white")
B("face", "floaty_hearts", "Floaty Hearts", 6, "shop", "floaty_hearts", "berry_red", "pink")
B("face", "bunny_nose", "Bunny Nose", 6, "shop", "bunny_nose", "pink", "white")
B("face", "twinkle_sparkles", "Twinkle Sparkles", 6, "shop", "twinkle_sparkles", "yellow", "white")
B("face", "tea_monocle", "Tea Monocle", 4, "shop", "tea_monocle", "green", "window")
B("face", "sweetheart_glasses", "Sweetheart Glasses", 4, "shop", "sweetheart_glasses", "berry_red", "pink")
B("face", "sunrise_shades", "Sunrise Shades", 7, "shop", "sunrise_shades", "orange", "r_mythic")
-- on the back
B("back", "moth_wings", "Moth Wings", 4, "shop", "b_moth_wings", "sponge", "chocolate")
B("back", "luna_wings", "Luna Moth Wings", 4, "shop", "b_luna_wings", "green", "purple")
B("back", "bat_wings", "Bat Wings", 4, "shop", "b_bat_wings", "black", "purple")
B("back", "phantom_cape", "Phantom Cape", 4, "shop", "phantom_cape", "white", "sky_night")
B("back", "pumpkin_balloons", "Pumpkin Balloons", 4, "shop", "pumpkin_balloons", "orange", "green")
B("back", "red_backpack", "Red Backpack", 1, "shop", "backpack", "berry_red", "chocolate")
B("back", "blue_backpack", "Blue Backpack", 1, "shop", "backpack", "blue", "sponge")
B("back", "red_cape", "Hero Cape", 3, "shop", "cape", "berry_red", "gold")
B("back", "royal_cape", "Velvet Cape", 4, "shop", "royal_cape", "purple", "plate_gold")
B("back", "angel_wings", "Angel Wings", 5, "shop", "angel_wings", "white", "gold")
B("back", "pink_fairy_wings", "Pink Fairy Wings", 4, "shop", "fairy_wings", "r_mythic", "white")
B("back", "mint_fairy_wings", "Mint Fairy Wings", 4, "shop", "fairy_wings", "r_uncommon", "white")
B("back", "butterfly_wings", "Monarch Wings", 3, "shop", "butterfly_wings", "orange", "black")
B("back", "dragon_wings", "Dragon Wings", 5, "shop", "dragon_wings", "green", "choco_dark")
B("back", "jetpack", "Jetpack", 5, "shop", "jetpack", "steel", "oven_glow")
B("back", "big_bow", "Big Bow", 2, "shop", "big_bow", "pink", "r_mythic")
B("back", "turtle_shell", "Turtle Pack", 3, "shop", "turtle_shell", "green", "sponge")
B("back", "teddy_backpack", "Teddy Backpack", 3, "shop", "teddy_backpack", "chocolate", "cream")
B("back", "guitar", "Guitar", 3, "shop", "guitar", "wood", "black")
B("back", "cake_backpack", "Cake Backpack", 3, "shop", "cake_backpack", "pink", "sponge")
B("back", "bee_wings", "Bee Wings", 2, "shop", "bee_wings", "window", "yellow")
B("back", "baguette_bag", "Baguette Bag", 2, "shop", "baguette_bag", "wood", "sponge")
B("back", "star_backpack", "Star Backpack", 2, "shop", "star_backpack", "yellow", "orange")
B("back", "candy_pinwheels", "Candy Pinwheels", 6, "shop", "candy_pinwheels", "pink", "yellow")
B("back", "balloon_bunch", "Balloon Bunch", 7, "shop", "balloon_bunch", "sky_day", "pink")
B("back", "dream_cloud", "Dream Cloud", 7, "shop", "dream_cloud", "white", "pink")
B("back", "bunny_backpack", "Bunny Backpack", 6, "shop", "bunny_backpack", "cream", "pink")
B("back", "rainbow_cape", "Rainbow Cape", 4, "shop", "rainbow_cape", "purple", "white", { rainbow = true })
B("back", "cloud_nine_wings", "Cloud Nine Wings", 6, "shop", "cloud_nine_wings", "white", "pink")
B("back", "taffy_ribbon_wings", "Taffy Ribbon Wings", 6, "shop", "taffy_ribbon_wings", "pink", "orange")
B("back", "brittle_shard_wings", "Brittle Shard Wings", 6, "shop", "brittle_shard_wings", "r_legend", "yellow")
B("back", "lotus_aura", "Lotus Aura", 6, "shop", "lotus_aura", "green", "cream")
B("back", "heartbeat_wings", "Heartbeat Wings", 6, "shop", "heartbeat_wings", "berry_red", "pink")
B("back", "rainbow_comet_trail", "Rainbow Comet Trail", 6, "shop", "rainbow_comet_trail", "r_epic", "yellow", { rainbow = true })
B("back", "shooting_star_wings", "Shooting Star Wings", 7, "shop", "shooting_star_wings", "gold", "yellow")
B("back", "jam_jar_backpack", "Jam Jar Backpack", 7, "shop", "jam_jar_backpack", "berry_red", "white")
B("back", "phoenix_wings", "Phoenix Wings", 7, "shop", "phoenix_wings", "oven_glow", "yellow")
-- round the neck
B("neck", "bat_familiar", "Bat Familiar", 4, "shop", "bat_familiar", "black", "purple")
B("neck", "red_neckerchief", "Red Neckerchief", 1, "shop", "neckerchief", "berry_red", "berry_red")
B("neck", "mint_scarf", "Mint Scarf", 1, "shop", "scarf", "green", "white")
B("neck", "cherry_scarf", "Cherry Scarf", 1, "shop", "scarf", "berry_red", "white")
B("neck", "red_bow_tie", "Red Bow Tie", 1, "shop", "bow_tie", "berry_red", "berry_red")
B("neck", "gold_bow_tie", "Gold Bow Tie", 2, "shop", "bow_tie", "gold", "plate_gold")
B("neck", "blue_necktie", "Blue Necktie", 1, "shop", "necktie", "blue", "sky_night")
B("neck", "pearl_necklace", "Pearl Necklace", 3, "shop", "pearls", "white", "cream")
B("neck", "gold_chain", "Chunky Chain", 3, "shop", "gold_chain", "gold", "plate_gold")
B("neck", "bell_collar", "Bell Collar", 2, "shop", "bell_collar", "berry_red", "gold")
B("neck", "ruff", "Ruff", 2, "shop", "ruff", "white", "cream")
B("neck", "flower_lei", "Hibiscus Lei", 2, "shop", "lei", "pink", "yellow")
B("neck", "gold_medal", "Gold Medal", 4, "shop", "medal", "gold", "blue")
B("neck", "heart_locket", "Heart Locket", 3, "shop", "locket", "gold", "r_mythic")
B("neck", "choker", "Gem Choker", 2, "shop", "choker", "black", "r_epic")
B("neck", "star_pendant", "Star Pendant", 3, "shop", "pendant", "yellow", "gold")
B("neck", "feather_boa", "Feather Boa", 4, "shop", "boa", "pink", "r_mythic")
B("neck", "lace_collar", "Lace Collar", 2, "shop", "lace_collar", "white", "cream")
B("neck", "firefly_necklace", "Firefly Necklace", 6, "shop", "firefly_necklace", "green", "yellow")
B("neck", "hamster_scarf", "Hamster Scarf", 6, "shop", "hamster_scarf", "berry_red", "sponge")
B("neck", "candy_necklace", "Candy Necklace", 6, "shop", "candy_necklace", "pink", "green")
B("neck", "butterfly_bow", "Butterfly Bow", 6, "shop", "butterfly_bow", "purple", "yellow")
B("neck", "marshmallow_boa", "Marshmallow Boa", 4, "shop", "marshmallow_boa", "white", "pink")
B("neck", "crumble_scarf", "Crumble Scarf", 4, "shop", "crumble_scarf", "wood", "orange")
B("neck", "bonbon_necklace", "Bonbon Necklace", 4, "shop", "bonbon_necklace", "pink", "berry_red")
B("neck", "lucky_charm_necklace", "Lucky Charm Necklace", 7, "shop", "lucky_charm_necklace", "gold", "grass")
-- in the hand
B("hand", "candy_scythe", "Candy Corn Scythe", 4, "shop", "candy_scythe", "orange", "yellow")
B("hand", "spatula", "Spatula", 1, "shop", "spatula", "steel", "wood")
B("hand", "whisk", "Whisk", 1, "shop", "whisk", "steel", "steel_dark")
B("hand", "rolling_pin", "Rolling Pin", 1, "shop", "rolling_pin", "wood", "wood_dark")
B("hand", "wooden_spoon", "Wooden Spoon", 1, "shop", "wooden_spoon", "wood", "wood_dark")
B("hand", "piping_bag", "Piping Bag", 2, "shop", "piping_bag", "white", "pink")
B("hand", "cupcake_treat", "Cupcake", 2, "shop", "cupcake", "pink", "sponge")
B("hand", "ice_cream_cone", "Ice Cream Cone", 2, "shop", "ice_cream_cone", "pink", "sponge")
B("hand", "lollipop", "Lollipop", 2, "shop", "lollipop", "r_mythic", "white")
B("hand", "red_balloon", "Red Balloon", 3, "shop", "balloon", "berry_red", "white")
B("hand", "blue_balloon", "Blue Balloon", 3, "shop", "balloon", "blue", "white")
B("hand", "bouquet", "Bouquet", 3, "shop", "bouquet", "pink", "green")
B("hand", "magic_wand", "Magic Wand", 4, "shop", "magic_wand", "yellow", "black")
B("hand", "rain_umbrella", "Rain Umbrella", 3, "shop", "umbrella", "sky_day", "wood")
B("hand", "teddy_bear", "Teddy Bear", 3, "shop", "teddy_bear", "chocolate", "cream")
B("hand", "baguette", "Baguette", 1, "shop", "baguette", "sponge", "wood")
B("hand", "coffee_cup", "Coffee Cup", 1, "shop", "coffee_cup", "white", "chocolate")
B("hand", "golden_whisk", "Golden Whisk", 5, "shop", "whisk", "gold", "plate_gold")
B("hand", "bubble_wand", "Bubble Wand", 6, "shop", "bubble_wand", "sky_day", "white")
B("hand", "puppy_plush", "Puppy Plush", 7, "shop", "puppy_plush", "cream", "chocolate")
B("hand", "ribbon_wand", "Ribbon Wand", 6, "shop", "ribbon_wand", "berry_red", "yellow")
B("hand", "bunny_lantern", "Bunny Lantern", 6, "shop", "bunny_lantern", "white", "pink")
B("hand", "taffy_spoon", "Taffy Spoon", 4, "shop", "taffy_spoon", "pink", "orange")
B("hand", "swirl_lollipop", "Swirl Lollipop", 4, "shop", "swirl_lollipop", "purple", "yellow", { rainbow = true })
B("hand", "marshmallow_wand", "Marshmallow Wand", 6, "shop", "marshmallow_wand", "white", "pink")
B("hand", "taffy_twirl_pop", "Taffy Twirl Pop", 6, "shop", "taffy_twirl_pop", "pink", "orange")
B("hand", "biscuit_scepter", "Biscuit Scepter", 6, "shop", "biscuit_scepter", "sponge", "gold")
B("hand", "bamboo_whisk_wand", "Bamboo Whisk Wand", 6, "shop", "bamboo_whisk_wand", "green", "cream")
B("hand", "cupid_whisk", "Cupid's Whisk", 6, "shop", "cupid_whisk", "berry_red", "pink")
B("hand", "rocket_pop_wand", "Rocket Pop Wand", 6, "shop", "rocket_pop_wand", "purple", "yellow")
B("hand", "horseshoe_wand", "Horseshoe Wand", 7, "shop", "horseshoe_wand", "gold", "r_uncommon")
B("hand", "golden_rolling_pin", "Golden Rolling Pin", 7, "shop", "golden_rolling_pin", "gold", "berry_red")
-- stylua: ignore end

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

-- Whether the player has piece `id` (owned, or everyone's: "free").
local function owns(owned: { [string]: boolean }?, id: string): boolean
	local p = BY_ID[id]
	if p == nil then
		return false
	end
	return p.src == "free" or (owned ~= nil and owned[id] == true)
end

-- (no two pieces with one name: the screens tell them apart by it)
local NAMES: { [string]: string } = {}
for _, p in LIST do
	local k = string.lower(p.name)
	assert(NAMES[k] == nil, "Cosmetics: two pieces named " .. p.name .. ": " .. tostring(NAMES[k]) .. ", " .. p.id)
	NAMES[k] = p.id
end

return table.freeze({
	SLOTS = SLOTS,
	list = LIST,
	byId = BY_ID,
	bySlot = BY_SLOT,
	from = from,
	owns = owns,
})
