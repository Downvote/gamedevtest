-- Driftling Isle's preview driver: boots the real server and client scripts in the fake engine (with the real
-- raycast and a pixel-storing EditableImage), drives a scenario and dumps frames for topng.py.
-- Usage: luau preview.luau -a <workdir> <scenario> <device> [tier] [inset]
--   workdir: work/<run> (holds sources.luau); scenario: a SCEN key (below), "panel=<name>", "exp=<kind>[_<what>]"
--   or "all";
--   device: a DEVICES key; tier: auto | low | medium | high | off
-- A scenario is a function in SCEN: it joins players (join / joinWith), drives them through H.req or the UI
-- (H.click, H.openPanel), waits for the pixel layer (settle) and calls capture(p, label) for every frame it wants.
local args = { ... }
local workdir = args[1] or error("workdir expected")
local scenario = args[2] or "office"
local device = args[3] or "desktop"
local tierArg = args[4] or "auto"
local insetArg = tonumber(args[5] or "")

local E = require("./loader")
local I = require("./inst")
local H = require("./harness")
local R = require("./raycast")
local C = require("./capture")
local A = require("./actors")
local tree = require("./" .. workdir .. "/sources")
local getD = I.getD
local v2 = E.v2
local _ = R
local _a = A

local function log(fmt, ...)
	print(string.format("[preview %8.2f] " .. fmt, E.SIM.now - (E.t0 or E.SIM.now), ...))
end

------------------------------------------------------------------ device
E.verbose = false
E.verboseUi = false
E.dt = 0.05
E.editableImageMode = "ok"
local DEVICES = {
	desktop = { w = 1920, h = 1080, inset = 58, touch = false },
	laptop = { w = 1366, h = 768, inset = 58, touch = false },
	phone = { w = 844, h = 390, inset = 58, touch = true },
	tablet = { w = 1024, h = 768, inset = 58, touch = true },
	portrait = { w = 390, h = 844, inset = 58, touch = true },
	android = { w = 800, h = 360, inset = 58, touch = true },
	iphone8 = { w = 667, h = 375, inset = 58, touch = true },
	desktop1440 = { w = 2560, h = 1440, inset = 58, touch = false },
}
local dev = DEVICES[device] or error("unknown device " .. device)
E.viewport = v2(dev.w, dev.h)
E.inset = insetArg or dev.inset

H.patchMonetizationIds(tree)
E.boot(tree)
if dev.touch then
	local UIS = E.services.UserInputService
	getD(UIS).props.TouchEnabled = true
	getD(UIS).props.KeyboardEnabled = false
	getD(UIS).props.MouseEnabled = false
end
E.phase = "preview-boot"
E.startServer()
E.run(1)

------------------------------------------------------------------ helpers
local function modOr(p, rel)
	local ok, m = pcall(H.cmod, p, rel)
	return if ok then m else nil
end

local function pixelImageState(p)
	-- the visible ImageLabel that shows an EditableImage (the pixel layer), if any
	local pg = p:FindFirstChild("PlayerGui")
	local layer = pg and pg:FindFirstChild("PixelLayer")
	local img = layer and layer:FindFirstChild("Image")
	if img and H.guiVisible(img) then
		return img, getD(img).props.ImageTransparency or 0
	end
	return nil, 1
end

-- Steps until the pixel renderer has its picture on screen and is quiet (no bake under way, its pan caught up with
-- the camera's, no re-cast waiting), or `maxSec` passed.
local function settle(p, maxSec, minSec)
	local PR = modOr(p, "Pixel.PixelRenderer")
	local CC0 = modOr(p, "Controllers.CameraController")
	local t, quiet = 0, 0
	local minT = minSec or 0.5
	while t < (maxSec or 40) do
		E.step(E.dt)
		t += E.dt
		local st = PR and select(2, pcall(PR.debugStatic))
		local active = PR ~= nil and select(2, pcall(PR.isActive)) == true
		local caught = true
		if CC0 and CC0.pan and type(st) == "table" and st.px ~= nil then
			local cx, cy = CC0.pan()
			caught = st.px == cx and st.py == cy and (st.queued or 0) == 0
		end
		if not active then
			if t >= math.max(minT, 1.5) then
				break
			end
		elseif type(st) == "table" and st.shown and not st.baking and caught then
			local _, tr = pixelImageState(p)
			if tr < 0.01 then
				quiet += 1
				if quiet >= 6 and t >= minT then
					break
				end
			end
		else
			quiet = 0
		end
	end
	local img, tr = pixelImageState(p)
	local st = PR and select(2, pcall(PR.debugStatic))
	if type(st) == "table" then
		log("settled after %.1fs: tier %s, layer %dx%d K %d, image %s transparency %.2f, bake rays %d, bakes %d, ticks %d, compose %.2f ms, dynamic %d, pan %s,%s, scrolls %s (%s rays), recasts %s, queued %s",
			t, tostring(PR.tier()), st.W, st.H, st.K, tostring(img ~= nil), tr, st.rays, st.bakes, st.ticks, st.composeMs, st.dyn,
			tostring(st.px), tostring(st.py), tostring(st.scrolls), tostring(st.scrollRays), tostring(st.recasts), tostring(st.queued))
	else
		log("settled after %.1fs (no pixel renderer stats)", t)
	end
	local CC = modOr(p, "Controllers.CameraController")
	if CC and CC.view then
		local okV, v = pcall(CC.view)
		if okV and type(v) == "table" and v.grid then
			log("camera: tier %d plot %d, %g art px per stud, pan %d,%d, frame box %d,%d - %d,%d (screen px)", v.tier, v.plot, v.grid.a, v.grid.px, v.grid.py, v.box.x0, v.box.y0, v.box.x1, v.box.y1)
		end
	end
end

local frames = 0
local function capture(p, label)
	frames += 1
	local name = string.format("%s_%s", label, device)
	log("capture %s", name)
	local okPT, PT = pcall(H.cmod, p, "Pixel.PixelText")
	if okPT and type(PT) == "table" and PT.stats then
		local okS, st = pcall(PT.stats)
		if okS and type(st) == "table" then
			log("pixeltext %s: %d pages, %d entries, %d labels, %d draws, %d failures", name, st.pages or 0, st.entries or 0, st.labels or 0, st.draws or 0, st.failures or 0)
		end
	end
	C.dump(p, name, string.format(',"device":%s,"scenario":%s,"tier":%s', C.jstr(device), C.jstr(scenario), C.jstr(tierArg)))
end

local function setTier(p)
	if tierArg ~= "auto" then
		local res = H.req(p, "settings.set", { k = "pixel", v = tierArg })
		if not (res and res.ok) then
			log("settings.set pixel %s: %s", tierArg, tostring(res and res.err))
		end
		E.run(0.5)
	end
end

local function join(userId, name, opts)
	opts = opts or {}
	opts.userId, opts.name = userId, name
	local p = H.addPlayer(opts)
	E.run(3)
	if p.Parent == nil then
		log("player %s was kicked or left while joining", name)
	elseif H.session(p) == nil or not H.session(p).ready then
		log("player %s has no ready session after 3 s", name)
	end
	if opts.client ~= false then
		setTier(p)
	end
	return p
end

-- A saved profile for `userId` (put in the fake cloud before they join): an island of `tier`; opts: pieces ({ id, x,
-- z, rot? } wanted spots, placed where Logic/Plot says they fit, else at the nearest cell that does; upgraded to lvl
-- when given), folk (how many villagers: jobs where free), pals (species: helping where their knack is needed),
-- islets, shells, food, wood, day, tut, cap (the captain's level).
local function seedProfile(userId, tier, opts)
	opts = opts or {}
	local Tuning = H.sharedServer("Config.Tuning")
	local Schema = H.sharedServer("Logic.Schema")
	local Island = H.sharedServer("Logic.Island")
	local Plot = H.sharedServer("Logic.Plot")
	local Names = H.sharedServer("Data.Names")
	local Util = H.sharedServer("Logic.Util")
	local now = math.floor(E.now())
	local prof = Schema.default(now, userId)
	prof.tier = tier
	-- the wild places of every tier reached (GAME_DESIGN 7), the lowest `islets` of them cleared (a player who has
	-- cleared that many); opts.site = { islet kind, level }: one more of that kind, wild (the exp scenarios go in)
	local Sites = H.sharedServer("Logic.Sites")
	local SiteData = H.sharedServer("Data.Sites")
	local Street = H.sharedServer("Data.Street")
	Sites.spawn(prof)
	local ws = {}
	for _, q in prof.plot.placed do
		if Plot.isSite(q.id) then
			table.insert(ws, q)
		end
	end
	table.sort(ws, function(a, b)
		return a.lvl < b.lvl
	end)
	for k = 1, math.min(opts.islets or 0, #ws) do
		ws[k].id = SiteData.doneId(SiteData.of(ws[k].id).id)
	end
	if opts.site then
		local sd = SiteData.byIslet[opts.site[1]]
		local pid = SiteData.wildId(sd.id)
		local land = Street.plot(tier)
		local spot = nil
		for z = math.floor(land.z0), math.floor(land.z1) do
			for x = math.floor(land.x0), math.floor(land.x1) do
				if spot == nil and Plot.fits(tier, prof.plot.placed, pid, x, z, 0, nil, true) then
					spot = { x, z }
				end
			end
		end
		if spot then
			table.insert(prof.plot.placed, { uid = prof.nextId, id = pid, x = spot[1], z = spot[2], rot = 0, lvl = opts.site[2] })
			prof.nextId += 1
		else
			log("seed: no room for the %s", sd.name)
		end
	end
	prof.shells = opts.shells or 4800
	prof.food = opts.food or 160
	prof.wood = opts.wood or 420
	prof.day = opts.day or 12
	prof.tut = opts.tut or 0
	prof.islets = opts.islets or 0
	prof.cap = { lvl = opts.cap or 6, xp = 0 }
	for _, d in opts.pieces or {} do
		local done = false
		for r = 0, if d[6] then 0 else 8 do
			for dz = -r, r do
				for dx = -r, r do
					if not done and (math.abs(dx) == r or math.abs(dz) == r) and Plot.fits(tier, prof.plot.placed, d[1], d[2] + dx, d[3] + dz, d[4] or 0) then
						table.insert(prof.plot.placed, { uid = prof.nextId, id = d[1], x = d[2] + dx, z = d[3] + dz, rot = d[4] or 0, lvl = d[5] or 1 })
						prof.nextId += 1
						done = true
					end
				end
			end
		end
		if not done and not d[6] then
			log("seed: %s does not fit near %d,%d", d[1], d[2], d[3])
		end
	end
	local rng = Util.newRng(userId * 7 + 1)
	for k = 1, math.min(opts.folk or 0, Island.beds(prof)) do
		local v = { id = prof.nextId, name = Util.pick(rng, Names.first), look = Island.randomLook(rng), work = 0, lvl = 2 + (k * 3) % 7, xp = 0, seed = rng:int(1, 99999), day = 1 }
		prof.nextId += 1
		v.work = Island.freeJob(prof)
		table.insert(prof.folk, v)
	end
	for k, sp in opts.pals or {} do
		local Creatures = H.sharedServer("Data.Creatures")
		local d = Creatures.byId[sp]
		-- (a set of mutations each, so the panels show them: Data/Traits)
		local MUTS = { { "fierce3", "swift1" }, { "angler2" }, {}, { "sturdy4", "bright2", "lazy" } }
		local x = { id = prof.nextId, sp = sp, lvl = 2 + (k * 2) % 6, xp = 0, work = 0, muts = MUTS[(k - 1) % #MUTS + 1] }
		prof.nextId += 1
		if d then
			x.work = Island.freeJob(prof, d.knack)
		end
		table.insert(prof.pals, x)
		prof.seen[sp] = 2
	end
	for _, sp in opts.seen or {} do
		prof.seen[sp] = math.max(prof.seen[sp] or 0, 1)
	end
	prof.stats.days = prof.day - 1
	prof.stats.movedIn = #prof.folk
	prof.stats.befriended = #prof.pals
	prof.stats.built = #prof.plot.placed
	-- an egg warming in the first Hatchery (opts.egg: { sp, left, muts })
	if opts.egg then
		for _, q in prof.plot.placed do
			if q.id == "hatchery" and #prof.eggs == 0 and #prof.pals >= 2 then
				table.insert(prof.eggs, { uid = q.uid, a = prof.pals[1].id, b = prof.pals[2].id, sp = opts.egg[1], left = opts.egg[2], muts = opts.egg[3] or {} })
			end
		end
	end
	local key = Tuning.DataStoreName .. "/global"
	E.cloud.stores[key] = E.cloud.stores[key] or {}
	E.cloud.stores[key]["u_" .. userId] = { value = { data = prof }, meta = {}, userIds = { userId }, version = 1, created = now, updated = now }
end

-- A tier-1 village round the plaza: food and wood east, homes and nests west, a stall and a pier by the path, decor
-- (plot-local NW corners; the seeder moves each to the nearest spot that fits the coast).
local VILLAGE = {
	{ "patch", 6, -1 }, { "patch", 10, -1 }, { "lumber", 6, 3 }, { "pier", 10, 3 }, { "stall", 5, 11 },
	{ "tent", -8, 0 }, { "hut", -12, 2 }, { "hut", -8, 4 }, { "nest", -6, 12 }, { "nest", -10, 9 },
	{ "flowers", 4, 13 }, { "palm", -12, 7 }, { "torch", 5, 1 }, { "bench", -5, -3 }, { "shellpile", 9, 8 },
	{ "bush", -3, -4 }, { "hammock", 0, -4 }, { "flowers", -4, 14 }, { "torch", -5, 10 },
}
-- A tier-3 harbour island: every kind of building, upgraded makers, the grand decor.
local HARBOR = {
	{ "greenhouse", 14, -7, 0, 3 }, { "orchard", 19, -7, 0, 2 }, { "orchard", 19, -2, 0, 2 }, { "sawmill", 14, -2, 0, 2 }, { "lumber", 22, 3 },
	{ "inn", 7, 9, 0, 2 }, { "cafe", 13, 9, 0, 2 }, { "stall", 18, 9 }, { "pier", 22, 8 },
	{ "cottage", -14, -7 }, { "cottage", -14, -2 }, { "hut", -9, 4 }, { "burrow", -19, -7 }, { "burrow", -19, -2 }, { "yard", -8, -12 },
	{ "fountain", -13, 6 }, { "lighthouse", 21, -13 }, { "statue", -22, 4 }, { "totem", 6, -12 }, { "picnic", -20, -12 },
	{ "palm", -25, 0 }, { "palm", 15, -14 }, { "flowers", 6, 3 }, { "flowers", -7, 12 }, { "torch", 5, 6 }, { "torch", -6, 6 },
	{ "hammock", 8, -16 }, { "bench", -4, -7 }, { "shellpile", 10, 14 }, { "hatchery", -1, -14 },
}
local PALS = { "clawdle", "gullfin", "mossbun", "pebblit", "frondle", "emberpup", "twiggle", "snowpuff" }

------------------------------------------------------------------ scenarios
local SCEN = {}

-- A brand-new island: the castaway's hut, the founder, the HUD with the first tip.
function SCEN.island()
	local p = join(1, "Pixel")
	settle(p)
	E.run(1)
	capture(p, "island")
	return p
end

-- A tier-1 village a dozen days in: villagers at work, driftlings helping and hopping, the island card.
function SCEN.village()
	seedProfile(2, 1, { pieces = VILLAGE, folk = 4, pals = { "clawdle", "mossbun", "pebblit" }, islets = 1 })
	local p = join(2, "Villager")
	settle(p)
	E.run(2.5)
	capture(p, "village")
	return p
end

-- At work (GAME_DESIGN 5, 6): the village a while on, its villagers at their buildings (a hoe in the fields, an axe at
-- the lumber camp, a line off the pier, the stall) and its driftlings with them (pecking, pushing, napping at a
-- nest), then a frame every eighth of a second for two seconds (work_000 .. work_015; make_gif.py makes them a GIF).
function SCEN.work()
	seedProfile(2, 1, { pieces = VILLAGE, folk = 4, pals = { "clawdle", "mossbun", "pebblit" }, islets = 1 })
	local p = join(2, "Villager")
	settle(p)
	E.run(14)
	capture(p, "work")
	for k = 0, 15 do
		capture(p, string.format("work_%03d", k))
		E.run(1 / 8)
	end
	return p
end

-- The water moving (GAME_DESIGN 8): the village, then a frame every sixth of a second for two seconds (water_000 ..
-- water_011; `python3 tools/preview/make_gif.py <outdir> water <device>` makes them a GIF).
function SCEN.water()
	seedProfile(2, 1, { pieces = VILLAGE, folk = 4, pals = { "clawdle", "mossbun", "pebblit" }, islets = 1 })
	local p = join(2, "Villager")
	settle(p)
	E.run(1)
	for k = 0, 11 do
		capture(p, string.format("water_%03d", k))
		E.run(1 / 6)
	end
	return p
end

-- The day and night (GAME_DESIGN 8): the village at dusk (dusk), at night with its lamps, torches and fire lit
-- (night), and at dawn (dawn): UI/DayLight held at that time of day.
local function timeScenario(frac, name)
	return function()
		seedProfile(2, 1, { pieces = VILLAGE, folk = 4, pals = { "clawdle", "mossbun", "pebblit" }, islets = 1 })
		local p = join(2, "Villager")
		settle(p)
		local DL = modOr(p, "Controllers.DayLight")
		if DL then
			H.inClient(p, DL.debugSet, frac)
		end
		E.run(1.5)
		capture(p, name)
		if name == "night" then
			-- the founder walks on: the camera pans and the lamps' pools go with the picture (night_pan_1 ..)
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root then
				local x0, z0 = root.Position.X, root.Position.Z
				for k = 1, 6 do
					p.Character:PivotTo(E.cf.new(x0 - k * 0.9, 3, z0 + k * 0.6))
					E.run(0.25)
					capture(p, "night_pan_" .. k)
				end
			end
		end
		return p
	end
end
SCEN.dusk = timeScenario(0.7, "dusk")
SCEN.night = timeScenario(0.88, "night")
SCEN.dawn = timeScenario(0.02, "dawn")

local function islandScenario(tier, label)
	return function()
		seedProfile(10 + tier, tier, { pieces = if tier == 3 then HARBOR else VILLAGE, folk = if tier == 3 then 12 else 6, pals = PALS, islets = tier + 1, shells = 60000, wood = 5000 })
		local p = join(10 + tier, "Isle" .. tier)
		settle(p)
		E.run(2.5)
		capture(p, label)
		return p
	end
end
SCEN.island2 = islandScenario(2, "island2")
SCEN.island3 = islandScenario(3, "island3")

-- A tier-6 capital (GAME_DESIGN 4.1: "a big island that is well decorated should look like a well developed city"):
-- brick roads in a grid (marble round the plaza, stone lanes between), the blocks filled with the town and city
-- buildings, lamps and trees along the roads. Roads go exactly where they fit (else nowhere); buildings nearest.
local function cityPieces()
	local out = {}
	local function road(id, x, z)
		table.insert(out, { id, x, z, 0, 1, true })
	end
	for _, z in { -44, -32, -20, -8 } do
		for x = -32, 32, 2 do
			road("brickroad", x, z)
		end
	end
	for _, x in { -28, -16, 14, 26 } do
		for z = -50, 14, 2 do
			road("brickroad", x, z)
		end
	end
	for x = -14, 12, 2 do
		road("marblewalk", x, 12)
		road("marblewalk", x, 0)
	end
	for _, x in { -8, 6 } do
		for z = 2, 10, 2 do
			road("marblewalk", x, z)
		end
	end
	-- the blocks: the city's buildings, then trees, lamps and hedges in what is left
	local BIG = {
		"townhall", "hotel", "bazaar", "manor", "skygarden", "palace", "observatory", "crystalfountain", "villa", "kelpfarm",
		"bakery", "grandmill", "townhouse", "grotto", "clocktower", "monument", "paddy", "inn", "roost", "bandstand",
		"sunspire", "greenhouse", "villa", "townhouse", "beacon", "watertower", "market", "hatchery", "gazebo", "longhouse",
		"bamboo", "timber", "den", "windmill", "cafe", "townhouse", "manor", "grandarch", "canal", "smokehouse",
		"orchard", "cottage", "villa", "toolshed", "lighthouse", "statue", "fountain", "hotel", "bazaar", "yard",
	}
	local k = 0
	for _, z in { -49, -40, -28, -16, -4, 4 } do
		for _, x in { -34, -25, -12, -4, 4, 18, 30 } do
			k += 1
			table.insert(out, { BIG[(k - 1) % #BIG + 1], x, z })
		end
	end
	for _, x in { -30, -18, 12, 24 } do
		for _, z in { -46, -34, -22, -10 } do
			table.insert(out, { "streetlamp", x, z })
		end
	end
	local SMALL = { "topiary", "palm", "lamppost", "flowers", "hedge", "bench", "flowerarch", "topiary", "fence", "palm" }
	k = 0
	for z = -50, 10, 5 do
		for x = -34, 34, 7 do
			k += 1
			table.insert(out, { SMALL[(k - 1) % #SMALL + 1], x, z })
		end
	end
	return out
end

-- Every piece of the town and the city on a capital, in rows by kind (the tier they open at), for a close look at
-- each model: captured from four spots (gallery_1 .. gallery_4).
function SCEN.gallery()
	local Buildings = H.sharedServer("Data.Buildings")
	local ids = {}
	for _, d in Buildings.list do
		if d.kind ~= "site" and (d.tier >= 3 or d.kind == "gen" or d.kind == "path" or d.id == "fence" or d.id == "sandcastle" or d.id == "rockgarden" or d.id == "hedge" or d.id == "lamppost" or d.id == "flowerarch") then
			table.insert(ids, d.id)
		end
	end
	local pieces = {}
	local x, z = -30, -48
	for _, id in ids do
		local d = Buildings.byId[id]
		table.insert(pieces, { id, x, z })
		x += d.w + 3
		if x > 26 then
			x = -30
			z += 8
		end
	end
	-- (the island's wild places too: the lowest eight cleared, so both looks show)
	seedProfile(17, 6, { pieces = pieces, folk = 0, islets = 8, shells = 900000, wood = 60000, food = 5000 })
	local p = join(17, "Gallery")
	settle(p)
	local Street = H.sharedServer("Data.Street")
	local ox = Street.origin(H.session(p).plot)
	for k, spot in { { -14, -42 }, { 14, -42 }, { -14, -26 }, { 14, -26 }, { -14, -10 }, { 14, -10 } } do
		if p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
			p.Character:PivotTo(E.cf.new(ox + spot[1], 3, spot[2]))
			E.run(2)
			settle(p, 30, 1)
		end
		capture(p, "gallery_" .. k)
	end
	return p
end

function SCEN.city()
	local CITY_PALS = { "clawdle", "gullfin", "mossbun", "pebblit", "frondle", "emberpup", "twiggle", "snowpuff", "conchy", "bloomoth", "glowbat", "breezle", "relicrab", "cloudbun", "hopsprout", "murkle" }
	seedProfile(16, 6, { pieces = cityPieces(), folk = 40, pals = CITY_PALS, islets = 30, shells = 900000, wood = 60000, food = 5000, cap = 40 })
	local p = join(16, "Capital")
	settle(p)
	E.run(2.5)
	local prof = H.profile(p)
	local paths = 0
	for _, q in prof.plot.placed do
		if H.sharedServer("Logic.Plot").isPath(q.id) then
			paths += 1
		end
	end
	log("city: %d pieces, %d path tiles, %d villagers, %d driftlings", #prof.plot.placed - paths, paths, #prof.folk, #prof.pals)
	capture(p, "city")
	-- the heart of the city, further north
	local Street = H.sharedServer("Data.Street")
	local ox = Street.origin(H.session(p).plot)
	if p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
		p.Character:PivotTo(E.cf.new(ox - 2, 3, -14))
		E.run(2)
		settle(p, 30, 1)
	end
	E.run(1.5)
	capture(p, "city_north")
	return p
end

-- A new day's banner: the sea's clock jumped to just before a day's end (a day is hours long).
function SCEN.day()
	seedProfile(3, 1, { pieces = VILLAGE, folk = 2, pals = { "gullfin" } })
	local p = join(3, "Dawn")
	settle(p)
	local WC = H.smod("WorldClock")
	local DS = H.sharedServer("Config.Tuning").DaySeconds
	WC.shift(DS - (WC.now() % DS) - 0.3)
	E.run(1.2)
	capture(p, "day")
	return p
end

-- The uid of the island's lowest wild place (0 with none).
local function lowestWild(prof)
	local Plot = H.sharedServer("Logic.Plot")
	local best, uid = math.huge, 0
	for _, q in prof.plot.placed do
		if Plot.isWild(q.id) and q.lvl < best then
			best, uid = q.lvl, q.uid
		end
	end
	return uid
end

-- A UI panel by name (UIKit.openPanel): folk, pals, site (the card of the island's lowest wild place: a party
-- picked), index, looks, hatch (the Hatchery: a harbour island with two, one warming a rare egg, the other with two
-- parents picked through the panel).
local function panelScenario(name)
	if name == "hatch" then
		local pieces = table.clone(HARBOR)
		table.insert(pieces, { "hatchery", 4, -18 })
		seedProfile(20, 3, { pieces = pieces, folk = 6, pals = { "clawdle", "gullfin", "shellback", "frostling", "mossbun" }, islets = 4, egg = { "glacior", 4, { "swift2" } }, food = 600, seen = { "glacior" } })
	else
		seedProfile(20, 2, { pieces = VILLAGE, folk = 5, pals = { "clawdle", "gullfin", "mossbun", "emberpup" }, islets = 2, seen = { "pebblit", "frondle", "twiggle", "magmole" } })
	end
	local p = join(20, "Menus")
	settle(p)
	local UIKit = modOr(p, "UI.UIKit")
	if UIKit and UIKit.openPanel then
		H.openPanel(p, name, if name == "site" then lowestWild(H.profile(p)) else nil)
		E.run(0.8)
		if name == "hatch" then
			-- the second Hatchery: two parents picked as a player would
			local prof = H.profile(p)
			local free = 0
			for _, q in prof.plot.placed do
				if q.id == "hatchery" and q.uid ~= (prof.eggs[1] and prof.eggs[1].uid or -1) then
					free = q.uid
				end
			end
			H.clickNamed(p, "Slot_a_" .. free, { wait = 0.4 })
			H.clickNamed(p, "PickParent_" .. prof.pals[3].id, { wait = 0.4 })
			H.clickNamed(p, "Slot_b_" .. free, { wait = 0.4 })
			H.clickNamed(p, "PickParent_" .. prof.pals[4].id, { wait = 0.4 })
			E.run(0.5)
		end
		-- (a wild place's party fills itself with the strongest)
		log("panel open: %s", tostring(UIKit.currentPanel and UIKit.currentPanel()))
	else
		log("no UIKit.openPanel: capturing the HUD")
	end
	capture(p, "panel_" .. name)
	return p
end

-- exp=<kind>[_<what>]: an expedition into a wild place of that kind (Data/Islets 1 beach .. 9 ruins: the Tide Pool ..
-- the Old Ruins, Data/Sites) a level over the one its driftlings first turn up at, on its 3D stage. what: "battle"
-- (default: the first battle), "boss" (the guardian), "clear" (the guardian beaten: the Cleared card), "win" (a battle
-- won), "lose" (the party beaten: the Expedition Complete card), "loot" (a stop's narration), "fight" (frame by
-- frame), "snack" (aiming one), "skills" (the skill window, the pointer resting on Rally Cry: its tip), "aim" (aiming
-- frame by frame: the arrow growing out to the pick, then swinging to another wild one hovered), "throw" (a snack
-- befriending the last wild one, frame by frame), "tut" (a battle in the tips' catching step: its note), "inspect",
-- "run". The place is put on the island for the scenario (the island's seed and its uid make its layout: the same
-- every run); the expedition is set on the session directly (Expedition.enter, as exp.start does).
local function expScenario(spec)
	local kindS, what = string.match(spec, "^(%d)_?(%a*)$")
	local n = tonumber(kindS) or 1
	what = if what == nil or what == "" then "battle" else what
	local isleLvl = H.sharedServer("Data.Islets").list[n].lvl + 1
	-- a party a little above the island's level (a fair fight to watch; strong for "win")
	local lvl = isleLvl + (if what == "win" then 8 else 1)
	seedProfile(40, 2, { pieces = VILLAGE, folk = 4, pals = { "clawdle", "emberpup" }, islets = n - 1, food = 400, cap = lvl, tut = if what == "tut" then 7 else nil, site = { n, isleLvl } })
	local p = join(40, "Captain")
	settle(p)
	local prof = H.profile(p)
	for _, v in prof.folk do
		v.lvl = lvl
	end
	for _, x in prof.pals do
		x.lvl = lvl
	end
	local s = H.session(p)
	local Expedition = H.sharedServer("Logic.Expedition")
	local SiteData = H.sharedServer("Data.Sites")
	local siteUid = 0
	for _, q in prof.plot.placed do
		if q.id == SiteData.wildId(SiteData.byIslet[n].id) and q.lvl == isleLvl then
			siteUid = q.uid
		end
	end
	local ok, e = Expedition.enter(prof, siteUid, { "v" .. prof.folk[1].id, "p" .. prof.pals[1].id, "v" .. prof.folk[2].id })
	if ok then
		H.smod("Session").setExp(s, e)
		log("island: %s (%s), level %d", e.isle.name, H.sharedServer("Data.Islets").list[e.isle.kind].name, e.isle.lvl)
	else
		log("exp start: %s", tostring(e))
	end
	H.push(p, 0.3)
	local EUI = modOr(p, "UI.ExpeditionUI")
	E.run(0.5)
	-- (a raw request skips the card's Explore and the walk in, which open the place's screen)
	if EUI then
		if what == "run" then
			H.inClient(p, EUI.debugAuto, false)
		end
		H.inClient(p, EUI.open)
	end
	local function curtainUp(): boolean
		local st = EUI and H.inClient(p, EUI.debugState)
		return st ~= nil and st.lifted
	end
	local waited = 0
	while waited < 40 and not curtainUp() do
		E.run(0.1)
		waited += 0.1
	end
	settle(p, 30, 1)
	log("curtain up after %.1fs", waited)
	if what == "run" then
		-- one area: the next stop's wild ones come running down the trail to the party, frame by frame
		-- (exp_<n>_run_000 ..: make_gif.py makes a GIF), then the encounter (the auto Go on is held: it starts here)
		if s.exp then
			for i = s.exp.node + 1, math.min(#s.exp.nodes, s.exp.node + 3) do
				s.exp.nodes[i] = "wild"
			end
			log("run: from node %d of %s", s.exp.node, table.concat(s.exp.nodes, ","))
		end
		H.inClient(p, function()
			E.task.spawn(EUI.debugGo)
		end)
		for k = 0, 23 do
			capture(p, string.format("exp_%s_%03d", spec, k))
			E.run(0.12)
		end
		local st = H.inClient(p, EUI.debugState)
		log("run: area %s, running %s, behind %s, nearest wild one %s studs up the trail from the area's middle, dropping %s", tostring(st.area), tostring(st.running), tostring(st.behind), tostring(st.foeU), tostring(st.dropping))
		H.inClient(p, EUI.debugAuto, true)
		settle(p, 10, 0.5)
		capture(p, "exp_" .. spec)
		return p
	end
	if what == "loot" then
		local guard = 0
		while s.exp and s.exp.nodes[s.exp.node + 1] ~= "loot" and s.exp.nodes[s.exp.node + 1] ~= "chest" and guard < 12 do
			guard += 1
			if s.exp.battle then
				for _, f in s.exp.battle.foes do
					f.hp = 0
				end
				s.exp.battle = nil
			end
			s.exp.node += 1
		end
		H.inClient(p, EUI.debugGo)
		E.run(1.2)
	elseif what == "boss" or what == "clear" then
		if s.exp then
			s.exp.node = #s.exp.nodes - 1
		end
		H.inClient(p, EUI.debugGo)
		E.run(2.5)
		if what == "clear" then
			-- the guardian falls (the party sturdy, the guardian worn down): the place is cleared, the Cleared card
			-- (the first clear's reward, the trip's loot, xp and levels)
			for _ = 1, 40 do
				if s.exp == nil or s.exp.battle then
					break
				end
				E.run(0.25)
			end
			if s.exp and s.exp.battle then
				for _, f in s.exp.party do
					f.hp, f.maxHp = math.max(f.maxHp, 400), math.max(f.maxHp, 400)
				end
				for _, f in s.exp.battle.foes do
					f.hp = 1
				end
			end
			for _ = 1, 60 do
				E.run(0.5)
				local pg = p:FindFirstChild("PlayerGui")
				if pg and pg:FindFirstChild("Result", true) then
					break
				end
			end
			E.run(1)
			local q = H.sharedServer("Logic.Sites").pieceOf(prof, siteUid)
			log("clear: the place is now %s, cleared %d", tostring(q and q.id), prof.islets)
		end
	else
		local guard = 0
		while s.exp and not s.exp.battle and guard < 12 do
			guard += 1
			H.inClient(p, EUI.debugGo)
			E.run(0.3)
		end
		E.run(2)
		-- (the endless islet: the party's area and the areas built round it)
		local built = {}
		local stf = E.workspace:FindFirstChild("MicroStage")
		if stf then
			for _, c in stf:GetChildren() do
				local k = string.match(c.Name, "^Area(%d+)$")
				if k then
					table.insert(built, k)
				end
			end
		end
		table.sort(built)
		log("battle: area %s, areas built %s", tostring(EUI and H.inClient(p, EUI.debugState).area), table.concat(built, ","))
		-- (the battle runs by itself once its wild ones land: the party made sturdy so a frame shows it under way)
		if s.exp then
			for _, f in s.exp.party do
				f.hp, f.maxHp = math.max(f.maxHp, 200), math.max(f.maxHp, 200)
			end
		end
		if what == "win" and s.exp and s.exp.battle then
			for _, f in s.exp.battle.foes do
				f.hp = 1
			end
			E.run(3)
		elseif what == "lose" and s.exp and s.exp.battle then
			-- the party falls: the Expedition Complete card (the trip's loot, xp and levels: some set here)
			s.exp.loot.shells, s.exp.loot.food, s.exp.loot.wood = 264, 38, 21
			local ups = {}
			for k, f in s.exp.party do
				if k <= 2 then
					ups[f.key] = k
				end
			end
			s.exp.gained = { xp = 412, ups = ups }
			for _, f in s.exp.party do
				f.hp, f.def = 1, 0
			end
			for _, f in s.exp.battle.foes do
				f.atk, f.hp, f.maxHp = 999, 99999, 99999
			end
			-- (till the card is up: the playback catches up with the battle the server has ended)
			local EUIx = modOr(p, "UI.ExpeditionUI")
			for _ = 1, 60 do
				E.run(0.5)
				local pg = p:FindFirstChild("PlayerGui")
				if pg and pg:FindFirstChild("Result", true) then
					break
				end
			end
			E.run(1)
			local _ = EUIx
		elseif what == "fight" and s.exp and s.exp.battle then
			-- the battle frame by frame (exp_<n>_fight_000 ..: make_gif.py makes a GIF): the timers filling over the
			-- heads, the wind-ups, dashes, strikes, hit-stops and knock-backs of both sides
			settle(p, 10, 0.5)
			for k = 0, 39 do
				capture(p, string.format("exp_%s_%03d", spec, k))
				E.run(0.07)
			end
			return p
		elseif what == "throw" and s.exp and s.exp.battle then
			-- a snack that befriends the last wild one, frame by frame: the throw, the arc, the hearts and the poof,
			-- the wild one on the stage till its playback is done
			local Battle = H.sharedServer("Logic.Battle")
			local chance = Battle.treatChance
			Battle.treatChance = function()
				return 1
			end
			local foes = s.exp.battle.foes
			while #foes > 1 do
				table.remove(foes)
			end
			foes[1].hp = math.max(1, math.floor(foes[1].maxHp * 0.3))
			H.push(p, 0.3)
			settle(p, 10, 0.5)
			H.inClient(p, EUI.debugAim, "snack")
			E.run(0.4)
			H.inClient(p, EUI.debugSnack, foes[1].key)
			for k = 0, 39 do
				capture(p, string.format("exp_%s_%03d", spec, k))
				E.run(0.06)
			end
			Battle.treatChance = chance
			return p
		elseif what == "aim" and s.exp and s.exp.battle then
			E.run(2)
			if s.exp.battle then
				for _, f in s.exp.battle.foes do
					f.hp = math.max(1, math.floor(f.maxHp * 0.4))
				end
				s.exp.battle.foes[1].hp = math.max(1, math.floor(s.exp.battle.foes[1].maxHp * 0.2))
			end
			H.push(p, 0.3)
			settle(p, 10, 0.5)
			H.inClient(p, EUI.debugAim, "snack")
			for k = 0, 39 do
				if k == 14 and s.exp.battle then
					-- the pointer moves over the last wild one: the arrow swings over to it
					local foes = s.exp.battle.foes
					H.inClient(p, EUI.debugPoint, foes[#foes].key, false)
				end
				capture(p, string.format("exp_%s_%03d", spec, k))
				E.run(0.06)
			end
			return p
		elseif (what == "snack" or what == "skills") and s.exp and s.exp.battle then
			-- aiming a snack (greyed, paused, the leader's ring and arrow toward the pick) or the skill window
			E.run(2)
			if s.exp.battle then
				s.exp.battle.sp = 8
				for _, f in s.exp.battle.foes do
					f.hp = math.max(1, math.floor(f.maxHp * 0.4))
				end
			end
			H.push(p, 0.3)
			H.inClient(p, EUI.debugAim, what)
			E.run(0.6)
			if what == "skills" then
				-- the pointer resting on the leader's first skill: what it does
				local shown = H.inClient(p, EUI.debugSkillTip, "f_cry")
				log("skill tip: %s", tostring(shown))
				E.run(0.2)
			end
		elseif what == "inspect" and s.exp and s.exp.battle then
			-- a closer look: the first wild one given three mutations, the plate over its head (as a hover shows it)
			local foe = s.exp.battle.foes[1]
			foe.muts = { "fierce3", "swift2", "lazy" }
			H.push(p, 0.3)
			E.run(1)
			local key, lines = H.inClient(p, EUI.debugInspect, foe.key)
			log("inspect %s: %s", tostring(key), table.concat(lines, " | "))
			E.run(0.2)
		elseif s.exp and s.exp.battle then
			-- a battle under way: the timers, the numbers, the bars
			E.run(2.5)
		end
	end
	settle(p, 10, 0.5)
	capture(p, "exp_" .. spec)
	return p
end

-- Into a wild place (GAME_DESIGN 7): the island's lowest wild place tapped (its card: the party, the snack pouch,
-- Explore), Explore, then a frame every fifth of a second through the founder's walk to the place, the blinds closing
-- on its name and the place's screen with the party dropped in (voyage_000 ..; make_gif.py makes them a GIF); then
-- the way home (the blinds opening on the island, the founder in front of the place, cheering). Stills: the card
-- (voyage_panel), the walk (voyage_walk), the blinds (voyage_close), on the stage (voyage_arrive), home (voyage_home).
function SCEN.voyage()
	seedProfile(45, 2, { pieces = VILLAGE, folk = 4, pals = { "clawdle", "gullfin" }, islets = 3, food = 400, cap = 9 })
	local p = join(45, "Sailor")
	local prof = H.profile(p)
	for _, v in prof.folk do
		v.lvl = 9
	end
	for _, x in prof.pals do
		x.lvl = 9
	end
	H.push(p, 0.3)
	settle(p)
	local uid = lowestWild(prof)
	local q = H.sharedServer("Logic.Sites").pieceOf(prof, uid)
	log("voyage: into %s (level %s)", tostring(q and q.id), tostring(q and q.lvl))
	-- the founder a few steps from it, as if walked up to it
	if q and p.Character then
		local Street = H.sharedServer("Data.Street")
		local ox, oz = Street.origin(H.session(p).plot)
		local w, d = H.sharedServer("Logic.Plot").footprint(q.id, q.rot)
		p.Character:PivotTo(E.cf.new(ox + q.x + w / 2 + 6, 3, oz + q.z + d + 10))
		E.run(2)
		settle(p, 30, 1)
	end
	capture(p, "voyage_place")
	H.openPanel(p, "site", uid)
	-- (the party's slots fill themselves with the strongest)
	E.run(0.5)
	capture(p, "voyage_panel")
	local Voyage = modOr(p, "UI.Voyage")
	local EUI = modOr(p, "UI.ExpeditionUI")
	-- (the fake engine bakes the place's picture slower than Tuning.StageWait: the curtain waits for it here)
	if EUI then
		H.inClient(p, EUI.debugWait, 30)
	end
	H.clickNamed(p, "Explore", { wait = 0.1 })
	local shot: { [string]: boolean } = {}
	local k = 0
	local onStage = 0
	for _ = 1, 110 do
		E.run(0.2)
		local ph = if Voyage then H.inClient(p, Voyage.debugState).phase else ""
		capture(p, string.format("voyage_%03d", k))
		k += 1
		local st = EUI and H.inClient(p, EUI.debugState)
		if ph == "walk" and not shot.walk then
			shot.walk = true
			E.run(0.3)
			capture(p, "voyage_walk")
		elseif ph == "close" and not shot.close then
			shot.close = true
			E.run(0.5)
			capture(p, "voyage_close")
		end
		if st and st.lifted then
			onStage += 1
			if onStage == 7 then
				capture(p, "voyage_arrive")
			end
			if onStage >= 14 then
				break
			end
		end
	end
	-- the way home: the curtain, the blinds opening on the island, the founder in front of the place
	if EUI then
		local s = H.session(p)
		if s.exp then
			s.exp.over = "won"
			s.exp.battle = nil
		end
		H.push(p, 0.2)
		H.inClient(p, EUI.debugHome)
		local homeShot = false
		for _ = 1, 70 do
			E.run(0.2)
			capture(p, string.format("voyage_%03d", k))
			k += 1
			local d = Voyage and H.inClient(p, Voyage.debugState)
			if d and d.phase == "land" and not homeShot and d.dir == "home" then
				homeShot = true
				E.run(0.5)
				capture(p, "voyage_home")
			end
			if d and d.phase == "" and homeShot then
				break
			end
		end
	end
	log("voyage: %d frames", k)
	return p
end

------------------------------------------------------------------ the sea and the islands (GAME_DESIGN 4, 8)
local function rootOf(p)
	return p.Character and p.Character:FindFirstChild("HumanoidRootPart")
end

-- Put a player's founder at a world point (as if they had walked there) and let the view follow and settle.
local function walkTo(p, x, z)
	local root = rootOf(p)
	if root == nil then
		log("walkTo: %s has no character", p.Name)
		return
	end
	p.Character:PivotTo(E.cf.new(x, 3, z))
	E.run(2)
	settle(p, 30, 1)
end

-- The founder on the boardwalk between two islands (the neighbour's village at work, boats out at sea); then the
-- same pan baked from scratch, to compare a scrolled picture with a fresh one.
function SCEN.sea()
	local p = join(50, "Walker")
	seedProfile(51, 2, { pieces = VILLAGE, folk = 6, pals = PALS, islets = 3 })
	join(51, "Neighbour", { client = false })
	settle(p)
	local Street = H.sharedServer("Data.Street")
	local x1 = Street.origin(1)
	local x2 = Street.origin(2)
	walkTo(p, (x1 + x2) / 2 + 6, (Street.BOARD.z0 + Street.BOARD.z1) / 2)
	E.run(0.5)
	settle(p, 10, 0.5)
	capture(p, "sea")
	local PR = modOr(p, "Pixel.PixelRenderer")
	if PR and PR.isActive() then
		H.inClient(p, function()
			PR.rebake()
		end)
		settle(p, 40, 1)
		capture(p, "sea_fresh")
	end
	return p
end

-- The founder on the neighbour's island while their villagers work.
function SCEN.visit()
	local p = join(52, "Visitor")
	seedProfile(53, 1, { pieces = VILLAGE, folk = 4, pals = { "frondle", "gullfin" } })
	join(53, "Host", { client = false })
	settle(p)
	local x2, z2 = H.sharedServer("Data.Street").origin(2)
	walkTo(p, x2 + 6, z2 + 12)
	capture(p, "visit")
	return p
end

-- Build mode: the tray (Food tab), a piece picked with its ghost on a cell where it fits (cyan), then on the hut (red),
-- then a tip under way (the tray on its tab, its building pulsing, the tip over the tray).
function SCEN.build()
	seedProfile(54, 1, { pieces = { { "patch", 6, 5 }, { "tent", -8, 1 }, { "nest", -7, 11 }, { "flowers", 5, 13 } }, folk = 1, shells = 3000, wood = 300 })
	local p = join(54, "Builder")
	settle(p, 30, 1)
	if not H.clickNamed(p, "Menu_build", { optional = true }) then
		log("no Build button")
	end
	E.run(0.5)
	local BuildUI = modOr(p, "UI.BuildUI")
	local PR = modOr(p, "Pixel.PixelRenderer")
	local Street = H.sharedServer("Data.Street")
	local Plot = H.sharedServer("Logic.Plot")
	local prof = H.profile(p)
	local ox, oz = Street.origin(1)
	local function tapWorld(world)
		H.inClient(p, function()
			local pos = PR.project(world)
			BuildUI.tapScreen(E.v2(pos.X, pos.Y - E.inset), false)
		end)
	end
	settle(p, 10, 0.5)
	capture(p, "build_tray")
	if BuildUI and PR then
		H.inClient(p, function()
			BuildUI.pick("lumber", 0)
		end)
		local cx, cz = 8, 0
		for r = 0, 6 do
			local found = false
			for dz = -r, r do
				for dx = -r, r do
					if not found and Plot.fits(1, prof.plot.placed, "lumber", 8 + dx, 0 + dz, 0) then
						cx, cz, found = 8 + dx, 0 + dz, true
					end
				end
			end
			if found then
				break
			end
		end
		tapWorld(E.v3(ox + cx + 2, Street.LAWN_Y, oz + cz + 1.5))
		settle(p, 10, 0.5)
		capture(p, "build")
		tapWorld(E.v3(ox + 0.5, Street.LAWN_Y, oz + 6.5))
		settle(p, 10, 0.5)
		capture(p, "build_red")
		-- the tips in Build mode: the second tip (wood) turns the tray to the Wood tab, the lumber camp pulsing
		H.clickNamed(p, "Cancel", { optional = true, wait = 0.2 })
		H.clickNamed(p, "BuildDone", { optional = true, wait = 0.3 })
		prof.tut = 2
		H.push(p, 0.4)
		H.clickNamed(p, "Menu_build", { optional = true, wait = 0.5 })
		settle(p, 10, 0.5)
		capture(p, "build_tip")
		-- replacing a placed piece: the tent tapped, Replace, the homes of its kind with their prices
		prof.tut = 0
		prof.tier = 2
		H.push(p, 0.4)
		for _, q in prof.plot.placed do
			if q.id == "tent" then
				local w, d = Plot.footprint(q.id, q.rot)
				tapWorld(E.v3(ox + q.x + w / 2, Street.LAWN_Y + 0.3, oz + q.z + d / 2))
			end
		end
		E.run(0.4)
		H.clickNamed(p, "Replace", { optional = true, wait = 0.4 })
		settle(p, 10, 0.5)
		capture(p, "build_replace")
	end
	return p
end

-- "paths": drawing paths in Build mode (GAME_DESIGN 4): a box being dragged (its markers: cyan where a tile goes,
-- red where one can't), then the tiles laid (paths_box).
function SCEN.paths()
	seedProfile(58, 2, { pieces = VILLAGE, folk = 2, shells = 1e6, wood = 1e5 })
	local p = join(58, "Paver")
	settle(p, 30, 1)
	local BuildUI = modOr(p, "UI.BuildUI")
	local Plot = H.sharedServer("Logic.Plot")
	local Street = H.sharedServer("Data.Street")
	local prof = H.profile(p)
	H.clickNamed(p, "Menu_build", { optional = true, wait = 0.5 })
	H.clickNamed(p, "Tab_path", { optional = true, wait = 0.3 })
	H.clickNamed(p, "Buy_stonepath", { optional = true, wait = 0.3 })
	-- a box of open grass (the first 4 x 3 tiles where every tile fits), one row of it running past its edge
	local c0, c1 = { 0, 0 }, { 0, 0 }
	local r = Street.plot(prof.tier)
	local found = false
	for z = r.z0 - r.z0 % 2, r.z1, 2 do
		for x = r.x0 - r.x0 % 2, r.x1, 2 do
			if not found then
				local ok = true
				for dz = 0, 4, 2 do
					for dx = 0, 6, 2 do
						ok = ok and Plot.fits(prof.tier, prof.plot.placed, "stonepath", x + dx, z + dz, 0)
					end
				end
				if ok then
					c0, c1, found = { x, z }, { x + 6, z + 6 }, true
				end
			end
		end
	end
	log("paths: box %d,%d to %d,%d", c0[1], c0[2], c1[1], c1[2])
	H.inClient(p, BuildUI.debugDraw, { c0, c1 }, "box", true)
	settle(p, 10, 0.5)
	capture(p, "paths_draw")
	H.inClient(p, BuildUI.debugDraw, { c0, c1 }, "box")
	E.run(0.6)
	settle(p, 10, 0.5)
	capture(p, "paths_box")
	local n = 0
	for _, q in prof.plot.placed do
		if Plot.isPath(q.id) then
			n += 1
		end
	end
	log("paths: %d tiles down", n)
	return p
end

-- "zoo": every driftling (Data/Creatures, Models/DriftModels) on a meadow islet's stage in batches of 20 (five a row,
-- four rows, turned three-quarters toward the viewer), each batch idle (zoo_<n>_idle) and mid-attack (zoo_<n>_attack:
-- the jaw open, the head and arms forward); the log lists each batch's species in order (left to right, back to front).
function SCEN.zoo()
	seedProfile(57, 1, {})
	local p = join(57, "Keeper")
	settle(p, 30, 1)
	local ctx = E.clientCtx(p)
	local MS = modOr(p, "UI.MicroStage")
	local MM = E.moduleIn(ctx, E.find("ReplicatedStorage.Shared.Models.MicroModels"))
	local Creatures = H.sharedServer("Data.Creatures")
	-- (the HUD off: the creatures alone on the stage)
	for _, g in p.PlayerGui:GetChildren() do
		if g:IsA("ScreenGui") and g.Name ~= "PixelLayer" then
			g.Enabled = false
		end
	end
	local st = H.inClient(p, MS.open, "leap", { top = 4, bottom = 4 }, 3)
	local things = {}
	local list = Creatures.list
	local batch = 0
	for i0 = 1, #list, 20 do
		batch += 1
		H.inClient(p, function()
			for _, x in things do
				st.remove(x.t)
			end
		end)
		things = {}
		local names = {}
		for n = 0, 19 do
			local d = list[i0 + n]
			if d == nil then
				break
			end
			table.insert(names, d.id)
			local t = H.inClient(p, function()
				local th = MM.driftling(d.shape, d.body, d.accent)
				return st.adopt(th, 1)
			end)
			table.insert(things, { t = t, u = -9 + (n % 5) * 4.5, v = -6 + math.floor(n / 5) * 4 })
		end
		log("zoo %d: %s", batch, table.concat(names, ", "))
		for _, mood in { "idle", "attack" } do
			H.inClient(p, function()
				for j, x in things do
					MM.animate(x.t, 0.6 + j * 0.37, mood, if mood == "attack" then 0.5 else 0)
					st.place(x.t, x.u, x.v, 0, MS.FACE_VIEWER + math.rad(40))
				end
			end)
			settle(p, 30, 0.5)
			capture(p, string.format("zoo_%d_%s", batch, mood))
		end
	end
	return p
end

-- "expand": the island grows from the build tray. The server swaps in the island it built ahead; the filter re-bakes
-- it (rushed); the cheer waits for the new picture. Frames expand_before and expand_after; the log says whether the
-- next island was ready, and how many frames and bakes passed before the cheer.
function SCEN.expand()
	seedProfile(56, 1, { pieces = VILLAGE, folk = 3, shells = 1e6, wood = 1e5 })
	local p = join(56, "Grower")
	settle(p, 30, 1)
	local PS = H.smod("PlotService")
	local PR = modOr(p, "Pixel.PixelRenderer")
	local guard = 0
	while not select(2, PS.debugNext(1)) and guard < 200 do
		guard += 1
		E.step(E.dt)
	end
	local nt, ready = PS.debugNext(1)
	log("expand: next island for tier %s ready %s after %d frames", tostring(nt), tostring(ready), guard)
	H.clickNamed(p, "Menu_build", { optional = true, wait = 0.5 })
	settle(p, 10, 0.5)
	capture(p, "expand_before")
	local bakes0, ticks0 = PR.debugStatic().bakes, PR.debugStatic().ticks
	H.clickNamed(p, "Expand", { optional = true, wait = 0 })
	local n, cheered = 0, false
	while n < 600 and not cheered do
		E.step(E.dt)
		n += 1
		for _, d in p.PlayerGui:GetDescendants() do
			if d:IsA("TextLabel") and string.find(d.Text, "Your island grew", 1, true) then
				cheered = true
			end
		end
	end
	local _, _, swaps = PS.debugNext(1)
	log("expand: tier %d, swaps %d, cheer after %d frames (%s), bakes %d -> %d, baking %s, queued %s", H.profile(p).tier, swaps, n, tostring(cheered), bakes0, PR.debugStatic().bakes, tostring(PR.debugStatic().baking), tostring(PR.debugStatic().queued))
	local m = 0
	while m < 2000 and PR.debugStatic().bakes == bakes0 do
		E.step(E.dt)
		m += 1
	end
	log("expand: the re-bake finished %d frames after that (E.dt %.3f); the picture composed %d times meanwhile (it kept living)", m, E.dt, PR.debugStatic().ticks - ticks0)
	settle(p, 10, 0.3)
	capture(p, "expand_after")
	return p
end

-- "late": the screen's size settles after the HUD is built, the two ways Roblox does it: (1) the top bar's inset
-- arrives with no ViewportSize event (the roots shrink by it on their own), (2) a phone turns and the camera's
-- ViewportSize event comes before the roots are laid out again. The menu bar must stay wholly on screen, at the
-- bottom, each time (frames late_inset, late_turn; the log says where it is).
local function menuBarReport(p, tag)
	local bar
	for _, x in I.descendants(p:FindFirstChild("PlayerGui"), {}) do
		if getD(x).props.Name == "MenuBar" then
			bar = x
		end
	end
	if bar == nil then
		log("late %s: no MenuBar", tag)
		return
	end
	local top = bar.AbsolutePosition.Y + E.inset
	local bottom = top + bar.AbsoluteSize.Y
	local ok = H.guiVisible(bar) and bottom <= E.viewport.Y and bottom >= E.viewport.Y - 3 * 20
	log("late %s: menu bar at y %d..%d on a %dx%d screen (inset %d): %s", tag, math.floor(top), math.floor(bottom), E.viewport.X, E.viewport.Y, E.inset, if ok then "ON SCREEN" else "HIDDEN")
end

function SCEN.late()
	local inset = E.inset
	E.inset = 0
	local p = join(7, "Late")
	settle(p, 30, 1)
	-- (1) the top bar's inset arrives on its own
	E.inset = inset
	E.run(1.5)
	menuBarReport(p, "inset")
	capture(p, "late_inset")
	-- (2) the screen turns; ViewportSize fires while the roots still have the old size
	local old = E.viewport
	local turned = v2(math.floor(old.X * 0.8), old.Y)
	E.guiViewport = old
	E.viewport = turned
	local cam = E.workspace.CurrentCamera
	I.firePropChanged(cam, getD(cam), "ViewportSize")
	E.flushDeferred()
	E.guiViewport = nil
	E.run(1.5)
	menuBarReport(p, "turn")
	capture(p, "late_turn")
	return p
end

------------------------------------------------------------------ run
local list = if scenario == "all" then { "island", "village", "island3", "city", "sea", "build", "day" } else { scenario }
for _, name in list do
	local fn = SCEN[name]
	local panel = string.match(name, "^panel=(%w+)$")
	if panel then
		fn = function()
			return panelScenario(panel)
		end
	end
	local exp = string.match(name, "^exp=([%w_]+)$")
	if exp then
		fn = function()
			return expScenario(exp)
		end
	end
	if fn == nil then
		error("unknown scenario " .. name)
	end
	E.phase = "preview-" .. name
	local ok, err = xpcall(fn, debug.traceback)
	if not ok then
		log("scenario %s failed: %s", name, tostring(err))
	end
end
log("done: %d frames, %d errors, %d warnings, rays %d, bvh builds %d refits %d", frames, #E.errors, #E.warnings, E.raycastStats.rays, E.raycastStats.builds, E.raycastStats.refits)
for i, e in E.errors do
	if i > 20 then
		break
	end
	log("ERROR %s (%s): %s", e.kind, e.ctx, string.sub(e.msg, 1, 300))
end
