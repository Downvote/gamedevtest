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
	prof.shells = opts.shells or 4800
	prof.food = opts.food or 160
	prof.wood = opts.wood or 420
	prof.day = opts.day or 12
	prof.tut = opts.tut or 0
	prof.islets = opts.islets or 0
	prof.cap = { lvl = opts.cap or 6, xp = 0 }
	for _, d in opts.pieces or {} do
		local done = false
		for r = 0, 8 do
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
		if not done then
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
		local x = { id = prof.nextId, sp = sp, lvl = 2 + (k * 2) % 6, xp = 0, work = 0 }
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
	{ "hammock", 8, -16 }, { "bench", -4, -7 }, { "shellpile", 10, 14 },
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

-- A new day's banner: a visitor moves in.
function SCEN.day()
	seedProfile(3, 1, { pieces = VILLAGE, folk = 2, pals = { "gullfin" } })
	local p = join(3, "Dawn")
	settle(p)
	local s = H.session(p)
	s.dayClock = H.sharedServer("Config.Tuning").DaySeconds - 0.3
	E.run(1.2)
	capture(p, "day")
	return p
end

-- A UI panel by name (UIKit.openPanel): folk, pals, explore (a party picked), index, looks.
local function panelScenario(name)
	seedProfile(20, 2, { pieces = VILLAGE, folk = 5, pals = { "clawdle", "gullfin", "mossbun", "emberpup" }, islets = 2, seen = { "pebblit", "frondle", "twiggle", "magmole" } })
	local p = join(20, "Menus")
	settle(p)
	local UIKit = modOr(p, "UI.UIKit")
	if UIKit and UIKit.openPanel then
		H.openPanel(p, name)
		E.run(0.8)
		if name == "explore" then
			local prof = H.profile(p)
			for _, key in { "v" .. prof.folk[1].id, "p" .. prof.pals[1].id } do
				H.clickNamed(p, "Member_" .. key, { wait = 0.2 })
			end
		end
		log("panel open: %s", tostring(UIKit.currentPanel and UIKit.currentPanel()))
	else
		log("no UIKit.openPanel: capturing the HUD")
	end
	capture(p, "panel_" .. name)
	return p
end

-- An island of a kind (Data/Islets 1-5) at a level: the first seed that charts that kind there.
local function seedOfKind(kind, lvl)
	local Expedition = H.sharedServer("Logic.Expedition")
	for seed = 1, 2000 do
		if Expedition.chart(lvl, seed * 101).kind == kind then
			return seed * 101
		end
	end
	return 1
end

-- exp=<kind>[_<what>]: an expedition to an island of that kind (1 beach .. 5 reef) at the level it first turns up
-- (+1), on its 3D stage. what: "battle" (default: the first battle), "boss" (the guardian), "win" (a battle won: the
-- results card), "loot" (a stop's narration). The island's seed is the first that charts the kind (a set seed, so
-- the same layout every run); the expedition is set on the session directly (exp.start makes up its own seed).
local function expScenario(spec)
	local kindS, what = string.match(spec, "^(%d)_?(%a*)$")
	local n = tonumber(kindS) or 1
	what = if what == nil or what == "" then "battle" else what
	local isleLvl = H.sharedServer("Data.Islets").list[n].lvl + 1
	-- a party a little above the island's level (a fair fight to watch; strong for "win")
	local lvl = isleLvl + (if what == "win" then 8 else 1)
	seedProfile(40, 2, { pieces = VILLAGE, folk = 4, pals = { "clawdle", "emberpup" }, islets = n - 1, food = 400, cap = lvl })
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
	local ok, e = Expedition.start(prof, isleLvl, { "v" .. prof.folk[1].id, "p" .. prof.pals[1].id, "v" .. prof.folk[2].id }, seedOfKind(n, isleLvl))
	if ok then
		H.smod("Session").setExp(s, e)
		log("island: %s (%s), level %d", e.isle.name, H.sharedServer("Data.Islets").list[e.isle.kind].name, e.isle.lvl)
	else
		log("exp start: %s", tostring(e))
	end
	H.push(p, 0.3)
	local EUI = modOr(p, "UI.ExpeditionUI")
	E.run(0.5)
	-- (a raw request skips the Explore panel's Set sail, which opens the islet's screen)
	if EUI then
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
	elseif what == "boss" then
		if s.exp then
			s.exp.node = #s.exp.nodes - 1
		end
		H.inClient(p, EUI.debugGo)
		E.run(2.5)
	else
		local guard = 0
		while s.exp and not s.exp.battle and guard < 12 do
			guard += 1
			H.inClient(p, EUI.debugGo)
			E.run(0.3)
		end
		E.run(2)
		if what == "win" and s.exp and s.exp.battle then
			for _, f in s.exp.battle.foes do
				f.hp = 1
			end
			H.inClient(p, EUI.debugAct, "fight")
			E.run(1.5)
		elseif s.exp and s.exp.battle then
			-- a round played: the numbers, the bars
			H.inClient(p, EUI.debugAct, "fight")
			E.run(0.3)
		end
	end
	settle(p, 10, 0.5)
	capture(p, "exp_" .. spec)
	return p
end

-- The sailing cutscene (GAME_DESIGN 7): the Explore panel (the level slider), Set sail, then a frame every fifth
-- of a second through the founder's walk down the jetty, the hop aboard, the boat sailing off, the blinds and the
-- islet's screen with the boat bringing the party ashore (voyage_000 ..; make_gif.py makes them a GIF), and stills
-- of the panel (voyage_panel) and the moments (voyage_walk, voyage_board, voyage_sail, voyage_arrive).
function SCEN.voyage()
	seedProfile(45, 2, { pieces = VILLAGE, folk = 4, pals = { "clawdle", "gullfin" }, islets = 3, food = 400, cap = 7 })
	local p = join(45, "Sailor")
	local prof = H.profile(p)
	for _, v in prof.folk do
		v.lvl = 8
	end
	for _, x in prof.pals do
		x.lvl = 8
	end
	H.push(p, 0.3)
	settle(p)
	H.clickNamed(p, "Menu_explore", { wait = 0.5 })
	local Menus = modOr(p, "UI.Menus")
	if Menus then
		H.inClient(p, Menus.setLevel, 5)
	end
	H.clickNamed(p, "Member_v" .. prof.folk[1].id, { wait = 0.2 })
	H.clickNamed(p, "Member_p" .. prof.pals[1].id, { wait = 0.2 })
	E.run(0.5)
	capture(p, "voyage_panel")
	local Voyage = modOr(p, "UI.Voyage")
	local EUI = modOr(p, "UI.ExpeditionUI")
	-- (the fake engine bakes the islet's picture slower than Tuning.StageWait: the curtain waits for it here)
	if EUI then
		H.inClient(p, EUI.debugWait, 30)
	end
	H.clickNamed(p, "SetSail", { wait = 0.1 })
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
			capture(p, "voyage_walk")
		elseif ph == "sail" and not shot.board then
			shot.board = true
			capture(p, "voyage_board")
		elseif ph == "close" and not shot.sail then
			shot.sail = true
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

-- Build mode: the tray (Food tab), a piece picked with its ghost on a cell where it fits (cyan), then on the hut (red).
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
	end
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
local list = if scenario == "all" then { "island", "village", "island3", "sea", "build", "day" } else { scenario }
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
