-- Driftling Isle's preview driver: boots the real server and client scripts in the fake engine (with the real
-- raycast and a pixel-storing EditableImage), drives a scenario and dumps frames for topng.py.
-- Usage: luau preview.luau -a <workdir> <scenario> <device> [tier] [inset]
--   workdir: work/<run> (holds sources.luau); scenario: a SCEN key (below) or "panel=<name>"
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
-- when given), pals (species: into the huts with room, the best first, at work at their knack), shells, wood, day,
-- tut, seen (kinds seen in the Index).
local function seedProfile(userId, tier, opts)
	opts = opts or {}
	local Tuning = H.sharedServer("Config.Tuning")
	local Schema = H.sharedServer("Logic.Schema")
	local Plot = H.sharedServer("Logic.Plot")
	local now = math.floor(E.now())
	local prof = Schema.default(now, userId)
	prof.tier = tier
	local Tree = H.sharedServer("Logic.Tree")
	prof.shells = opts.shells or 4800
	prof.wood = opts.wood or 420
	prof.day = opts.day or 12
	prof.tut = opts.tut or 0
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
	for k, sp in opts.pals or {} do
		local Creatures = H.sharedServer("Data.Creatures")
		local d = Creatures.byId[sp]
		-- (a set of mutations each, so the panels show them: Data/Traits)
		local MUTS = { { "fierce3", "swift1" }, { "angler2" }, {}, { "sturdy4", "bright2", "lazy" } }
		local x = { id = prof.nextId, sp = sp, home = 0, work = 0, muts = MUTS[(k - 1) % #MUTS + 1] }
		prof.nextId += 1
		table.insert(prof.pals, x)
		prof.seen[sp] = 2
		local _ = d
	end
	-- into the huts with room, the best first, at work (Logic/Tree)
	Tree.settle(prof)
	Tree.fillJobs(prof)
	-- the tree's eggs: a lot laid a minute ago (opts.eggs: rarities to lay instead of rolling them)
	local Util = H.sharedServer("Logic.Util")
	Tree.lay(prof, Util.newRng(userId * 31 + 7))
	if opts.eggs then
		for k, r in opts.eggs do
			if prof.clutch.list[k] then
				prof.clutch.list[k].r = r
			end
		end
	end
	prof.clutch.left = opts.left or (Tuning.EggSecs - 60)
	for _, sp in opts.seen or {} do
		prof.seen[sp] = math.max(prof.seen[sp] or 0, 1)
	end
	prof.stats.days = prof.day - 1
	prof.stats.taken = #prof.pals
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

-- A tier-1 village round the plaza: farms and wood east, the driftlings' huts west, a stall and a pier by the path,
-- decor (plot-local NW corners; the seeder moves each to the nearest spot that fits the coast).
local VILLAGE = {
	{ "patch", 6, -1 }, { "patch", 10, -1 }, { "lumber", 6, 3 }, { "pier", 10, 3 }, { "stall", 5, 11 },
	{ "nest", -8, 0 }, { "nest", -11, 3 }, { "nest", -8, 5 }, { "nest", -6, 12 },
	{ "flowers", 4, 13 }, { "palm", -12, 7 }, { "torch", 5, 1 }, { "bench", -5, -3 }, { "shellpile", 9, 8 },
	{ "bush", -3, -4 }, { "hammock", 0, -4 }, { "flowers", -4, 14 }, { "torch", -5, 10 },
}
-- A tier-3 harbour island: every kind of building, upgraded makers, the grand decor.
local HARBOR = {
	{ "greenhouse", 14, -7, 0, 3 }, { "orchard", 19, -7, 0, 2 }, { "orchard", 19, -2, 0, 2 }, { "sawmill", 14, -2, 0, 2 }, { "lumber", 22, 3 },
	{ "inn", 7, 9, 0, 2 }, { "cafe", 13, 9, 0, 2 }, { "stall", 18, 9 }, { "pier", 22, 8 },
	{ "den", -14, -7 }, { "den", -14, -2 }, { "nest", -9, 4 }, { "burrow", -19, -7 }, { "burrow", -19, -2 },
	{ "fountain", -13, 6 }, { "lighthouse", 21, -13 }, { "statue", -22, 4 }, { "totem", 6, -12 }, { "picnic", -20, -12 },
	{ "palm", -25, 0 }, { "palm", 15, -14 }, { "flowers", 6, 3 }, { "flowers", -7, 12 }, { "torch", 5, 6 }, { "torch", -6, 6 },
	{ "hammock", 8, -16 }, { "bench", -4, -7 }, { "shellpile", 10, 14 }, { "hatchery", -1, -14 },
}
local PALS = { "clawdle", "gullfin", "mossbun", "pebblit", "frondle", "emberpup", "twiggle", "snowpuff" }

------------------------------------------------------------------ scenarios
local SCEN = {}

-- A brand-new island: the founder, the HUD with the first tip.
function SCEN.island()
	local p = join(1, "Pixel")
	settle(p)
	E.run(1)
	capture(p, "island")
	return p
end

-- A tier-1 village a dozen days in: driftlings at work and hopping about, the island card.
function SCEN.village()
	seedProfile(2, 1, { pieces = VILLAGE, pals = { "clawdle", "mossbun", "pebblit" }})
	local p = join(2, "Wren")
	settle(p)
	E.run(2.5)
	capture(p, "village")
	return p
end

-- At work (GAME_DESIGN 5, 6): the village a while on, its driftlings at their buildings (pecking in the fields,
-- pushing at the lumber camp, dipping off the pier, waving at the stall, napping at a hut, what they work at flying
-- off), then a frame every eighth of a second for two seconds (work_000 .. work_015; make_gif.py makes them a GIF).
function SCEN.work()
	seedProfile(2, 1, { pieces = VILLAGE, pals = { "clawdle", "mossbun", "pebblit" }})
	local p = join(2, "Wren")
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
	seedProfile(2, 1, { pieces = VILLAGE, pals = { "clawdle", "mossbun", "pebblit" }})
	local p = join(2, "Wren")
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
		seedProfile(2, 1, { pieces = VILLAGE, pals = { "clawdle", "mossbun", "pebblit" }})
		local p = join(2, "Wren")
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
		seedProfile(10 + tier, tier, { pieces = if tier == 3 then HARBOR else VILLAGE, pals = PALS, shells = 60000, wood = 5000 })
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
		"townhall", "hotel", "bazaar", "palace", "skygarden", "roost", "observatory", "crystalfountain", "grotto", "kelpfarm",
		"bakery", "grandmill", "den", "grotto", "clocktower", "monument", "paddy", "inn", "roost", "bandstand",
		"sunspire", "greenhouse", "palace", "den", "beacon", "watertower", "market", "hatchery", "gazebo", "burrow",
		"bamboo", "timber", "den", "windmill", "cafe", "roost", "palace", "grandarch", "canal", "smokehouse",
		"orchard", "burrow", "grotto", "toolshed", "lighthouse", "statue", "fountain", "hotel", "bazaar",
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
	seedProfile(17, 6, { pieces = pieces, shells = 900000, wood = 60000 })
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
	seedProfile(16, 6, { pieces = cityPieces(), pals = CITY_PALS, shells = 900000, wood = 60000})
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
	log("city: %d pieces, %d path tiles, %d driftlings", #prof.plot.placed - paths, paths, #prof.pals)
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
	-- the city at night: its windows, lamps and torches each lighting as far as its size
	local DL = modOr(p, "Controllers.DayLight")
	if DL then
		H.inClient(p, DL.debugSet, 0.88)
		E.run(1.5)
		capture(p, "city_night")
	end
	return p
end

-- A new day's banner: the sea's clock jumped to just before a day's end (a day is hours long).
function SCEN.day()
	seedProfile(3, 1, { pieces = VILLAGE, pals = { "gullfin" } })
	local p = join(3, "Dawn")
	settle(p)
	local WC = H.smod("WorldClock")
	local DS = H.sharedServer("Config.Tuning").DaySeconds
	WC.shift(DS - (WC.now() % DS) - 0.3)
	E.run(1.2)
	capture(p, "day")
	return p
end

-- A UI panel by name (UIKit.openPanel): pals, tree (its eggs with their prices, the odds), index,
-- looks, hatch (the Hatchery: a harbour island with two, one warming a rare egg, the other with two parents picked
-- through the panel).
local function panelScenario(name)
	if name == "hatch" then
		local pieces = table.clone(HARBOR)
		table.insert(pieces, { "hatchery", 4, -18 })
		seedProfile(20, 3, { pieces = pieces, pals = { "clawdle", "gullfin", "shellback", "frostling", "mossbun" }, egg = { "glacior", 4, { "swift2" } }, shells = 9000, seen = { "glacior" } })
	else
		seedProfile(20, 2, { pieces = VILLAGE, pals = { "clawdle", "gullfin", "mossbun", "emberpup", "shellback", "conchy" }, seen = { "pebblit", "frondle", "twiggle", "magmole" } })
	end
	local p = join(20, "Menus")
	settle(p)
	local UIKit = modOr(p, "UI.UIKit")
	if UIKit and UIKit.openPanel then
		H.openPanel(p, name)
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
		log("panel open: %s", tostring(UIKit.currentPanel and UIKit.currentPanel()))
	else
		log("no UIKit.openPanel: capturing the HUD")
	end
	capture(p, "panel_" .. name)
	return p
end

-- The Tree of Life and its eggs (GAME_DESIGN 6): a village's tree with its lot of eggs round its roots (a rare one and
-- an epic among them), their prices over them, the founder in front of it (tree); a new lot rising out of the lawn,
-- the old one sinking (tree_lay); one hatched by its price tag, cracking, its driftling stepping out (tree_hatch); the
-- glowing eggs at night (tree_night).
function SCEN.tree()
	seedProfile(21, 2, { pieces = VILLAGE, pals = { "clawdle", "mossbun", "gullfin" }, shells = 2000, eggs = { 1, 2, 3, 4, 5, 1 } })
	local p = join(21, "Grove")
	settle(p)
	local s = H.session(p)
	local Street = H.sharedServer("Data.Street")
	local Tree = H.sharedServer("Logic.Tree")
	local Plot = H.sharedServer("Logic.Plot")
	local prof = H.profile(p)
	local ox, oz = Street.origin(s.plot)
	local q = Tree.piece(prof)
	if q and p.Character then
		local w, d = Plot.footprint(q.id, q.rot)
		p.Character:PivotTo(E.cf.new(ox + q.x - 1, 3, oz + q.z + d + 2))
		E.run(2)
		settle(p, 30, 1)
	end
	capture(p, "tree")
	-- a new lot: the old eggs sink, the new ones rise one after another
	prof.clutch.left = 0.05
	E.run(0.9)
	capture(p, "tree_lay")
	E.run(2)
	settle(p, 10, 0.5)
	-- one hatched by its tag: it cracks and its driftling steps out
	local v = H.inClient(p, function()
		return modOr(p, "Controllers.StateClient").view()
	end)
	local pick = nil
	for _, e in (v and v.clutch or {}) do
		local tag = H.buttonNamed(p, "EggHatch_" .. e.id)
		if tag and prof.shells >= (e.cost or 0) and (pick == nil or (e.cost or 0) > (pick.cost or 0)) then
			pick = e
		end
	end
	if pick then
		H.clickNamed(p, "EggHatch_" .. pick.id, { wait = 0.45 })
	end
	capture(p, "tree_hatch")
	-- at night: the rare eggs' spots glow
	local DL = modOr(p, "Controllers.DayLight")
	if DL then
		E.run(1)
		H.inClient(p, DL.debugSet, 0.88)
		E.run(1.5)
		capture(p, "tree_night")
	end
	return p
end

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
	seedProfile(51, 2, { pieces = VILLAGE, pals = PALS})
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

-- The founder on the neighbour's island while their driftlings work.
function SCEN.visit()
	local p = join(52, "Visitor")
	seedProfile(53, 1, { pieces = VILLAGE, pals = { "frondle", "gullfin" } })
	join(53, "Host", { client = false })
	settle(p)
	local x2, z2 = H.sharedServer("Data.Street").origin(2)
	walkTo(p, x2 + 6, z2 + 12)
	capture(p, "visit")
	return p
end

-- Build mode: the tray (Wood tab), a piece picked with its ghost on a cell where it fits (cyan), then on the plaza
-- (red), then a tip under way (the tray on its tab, its building pulsing, the tip over the tray), then the Huts tab with
-- the island at its huts' limit (build_huts: "No room", 4/4), then a hut picked up and Replace (the bigger huts with
-- their prices).
function SCEN.build()
	seedProfile(54, 1, { pieces = { { "patch", 6, 5 }, { "nest", -8, 1 }, { "nest", -7, 11 }, { "flowers", 5, 13 } }, pals = { "mossbun" }, shells = 3000, wood = 300 })
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
		-- the tips in Build mode: the stall's tip (the island has none yet) turns the tray to the Shops tab, the stall
		-- pulsing
		H.clickNamed(p, "Cancel", { optional = true, wait = 0.2 })
		H.clickNamed(p, "BuildDone", { optional = true, wait = 0.3 })
		prof.tut = 5
		H.push(p, 0.4)
		H.clickNamed(p, "Menu_build", { optional = true, wait = 0.5 })
		settle(p, 10, 0.5)
		capture(p, "build_tip")
		-- the huts' limit: two more huts make four, all a tier 1 island holds (Tuning.HutLimit)
		prof.tut = 0
		for _, at in { { -11, 5 }, { -5, -3 } } do
			local done = false
			for r = 0, 8 do
				for dz = -r, r do
					for dx = -r, r do
						if not done and Plot.fits(1, prof.plot.placed, "nest", at[1] + dx, at[2] + dz, 0) then
							table.insert(prof.plot.placed, { uid = prof.nextId, id = "nest", x = at[1] + dx, z = at[2] + dz, rot = 0, lvl = 1 })
							prof.nextId += 1
							done = true
						end
					end
				end
			end
		end
		H.push(p, 0.4)
		H.clickNamed(p, "Tab_nest", { optional = true, wait = 0.3 })
		settle(p, 10, 0.5)
		capture(p, "build_huts")
		-- replacing a placed piece: a hut tapped, Replace, the huts of its kind with their prices
		prof.tier = 2
		H.push(p, 0.4)
		local tapped = false
		for _, q in prof.plot.placed do
			if q.id == "nest" and not tapped then
				tapped = true
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
	seedProfile(58, 2, { pieces = VILLAGE, shells = 1e6, wood = 1e5 })
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

-- "zoo": every driftling (Data/Creatures, Models/DriftModels) on the home island's lawn in batches of 20 (five a row,
-- four rows, turned three-quarters toward the viewer), each batch idle (zoo_<n>_idle) and cheering (zoo_<n>_cheer: the
-- jaw open, the arms up); the log lists each batch's species in order (left to right, back to front).
function SCEN.zoo()
	seedProfile(57, 1, {})
	local p = join(57, "Keeper")
	settle(p, 30, 1)
	local Street = H.sharedServer("Data.Street")
	local ox, oz = Street.origin(H.session(p).plot)
	-- (the founder on the open lawn behind the rows: the view follows them)
	walkTo(p, ox + 1, oz + 6)
	local ctx = E.clientCtx(p)
	local MM = E.moduleIn(ctx, E.find("ReplicatedStorage.Shared.Models.MicroModels"))
	local PR = H.cmod(p, "Pixel.PixelRenderer")
	local Creatures = H.sharedServer("Data.Creatures")
	-- (the HUD off: the creatures alone on the lawn)
	for _, g in p.PlayerGui:GetChildren() do
		if g:IsA("ScreenGui") and g.Name ~= "PixelLayer" then
			g.Enabled = false
		end
	end
	-- the ground's screen-right and toward-the-viewer directions (Tuning.CamYaw 45: Raster.rotation)
	local ux, uz = math.sqrt(0.5), -math.sqrt(0.5)
	local vx, vz = math.sqrt(0.5), math.sqrt(0.5)
	local faceViewer = math.atan2(vx, vz)
	local root = rootOf(p)
	local cx, cz = root.Position.X, root.Position.Z
	local things = {}
	local list = Creatures.list
	local batch = 0
	for i0 = 1, #list, 20 do
		batch += 1
		H.inClient(p, function()
			for _, x in things do
				PR.unregisterDynamic(x.t.model)
				x.t.model:Destroy()
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
				th.model:SetAttribute("PixelShadow", 1)
				th.model:SetAttribute("PixelGroundY", Street.LAWN_Y)
				th.model.Parent = E.workspace
				PR.registerDynamic(th.model)
				return th
			end)
			local u, v = -8 + (n % 5) * 4, -5.25 + math.floor(n / 5) * 3.5
			table.insert(things, { t = t, x = cx + ux * u + vx * v, z = cz + uz * u + vz * v })
		end
		log("zoo %d: %s", batch, table.concat(names, ", "))
		for _, mood in { "idle", "cheer" } do
			H.inClient(p, function()
				for j, x in things do
					MM.animate(x.t, 0.6 + j * 0.37, mood, 0)
					MM.place(x.t, E.cf.new(x.x, Street.LAWN_Y, x.z) * E.cf.Angles(0, faceViewer + math.rad(40), 0))
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
	seedProfile(56, 1, { pieces = VILLAGE, shells = 1e6, wood = 1e5 })
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

------------------------------------------------------------------ the loading card's art
-- A client's module of ReplicatedStorage.Shared (the client's own copy, as the game requires it there).
local function cshared(p, path)
	local ctx = E.clientCtx(p)
	local inst = E.find("ReplicatedStorage.Shared." .. path)
	local e = ctx.modules[inst]
	if e then
		return e.value
	end
	return E.moduleIn(ctx, inst)
end
-- "ploadingart": the loading card's scene art, drawn through the game's own picture path (tools/preview/loading_art.luau;
-- tools/preview/gen_loading_art.py turns its log into src/first/LoadingArt.luau: sh tools/preview/loading_art.sh)
function SCEN.ploadingart()
	return require("./loading_art")({ E = E, H = H, log = log, capture = capture, join = join, settle = settle, cshared = cshared, modOr = modOr })
end

-- "pportraits": the driftlings' portraits drawn from their models (tools/preview/portraits.luau; gen_portraits.py tidies
-- them into scripts/portraits.txt for scripts/gen_art.py: sh tools/preview/portraits.sh). "pportraits_try": one
-- driftling of each body plan, to try a change before baking them all.
function SCEN.pportraits()
	return require("./portraits")({ E = E, H = H, log = log, capture = capture, join = join, settle = settle, cshared = cshared, modOr = modOr })
end
function SCEN.pportraits_try()
	return require("./portraits")({ E = E, H = H, log = log, capture = capture, join = join, settle = settle, cshared = cshared, modOr = modOr, species = { "pebblit", "clawdle", "gullfin", "mossbun", "frondle", "crystowl", "emberpup", "magmole", "glowbat", "snowpuff", "floe", "sunsprite", "lumajelly", "tidewyrm", "conchy", "shellback", "hopsprout", "bloomoth", "elderbark", "pyredrake" }, yaws = { 30 } })
end

-- "loading": the loading card while the game loads (src/first/LoadingCard: ReplicatedFirst's Boot puts it up before the
-- rest has arrived): a still a second in (loading) and a frame every fifth of a second while it is up (loading_000 ..;
-- make_gif.py makes them a GIF); the log says how far it got (its phase, its bar, its actors, whether it painted).
function SCEN.loading()
	local p = H.addPlayer({ userId = 7400, name = "Loader" })
	setTier(p)
	local function card()
		local ctx = E.clientCtx(p)
		local inst = E.find("ReplicatedFirst.Loading.LoadingCard")
		local e = ctx and inst and ctx.modules[inst]
		return if e then e.value else nil
	end
	local k, shot = 0, false
	for i = 1, 60 do
		E.run(0.1)
		local c = card()
		local st = c and H.inClient(p, c.state)
		if st and st.up and not st.fading then
			if i >= 10 and not shot then
				shot = true
				capture(p, "loading")
				log("loading: phase %s, bar %.2f, actors %d, painted %s, fallback %s, K %d, size %dx%d", st.phase, st.bar, st.actors, tostring(st.painted), tostring(st.fallback), st.K, st.size.X, st.size.Y)
			end
			if i >= 4 and i % 2 == 0 and k < 16 then
				capture(p, string.format("loading_%03d", k))
				k += 1
			end
		elseif st and i > 4 then
			log("loading: the card is %s at %.1f s", if st.fading then "fading" else "down", i * 0.1)
			break
		end
	end
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
