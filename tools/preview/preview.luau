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

-- The islands' small lives in the pixel layer (GAME_DESIGN 8; Controllers/AmbientView): a harbour island with
-- chimneys, a smokehouse, a grill, trees and a picket fence by the plaza. The birds called in (`debugHurry`) and landed
-- (ambient), then a frame every eighth of a second for two seconds (ambient_000 .. 015: hops, pecks, tufts swaying,
-- smoke curling, a glint or a fish; `make_gif.py <outdir> ambient <device> 8`); the founder put next to a perched bird
-- and a frame every tenth of a second as it flies off (ambient_flee_000 .. 009); the same island at night with its
-- fireflies (ambient_night). Then the timing: 90 frames at 60 Hz on the real clock with the ambient layer and 90
-- without (AmbientView.setSuspended), the client's whole frame each time, and the effect layer's own numbers
-- (PixelRenderer.fxStats: the layers' ms, the books' ms, pixels written and changed, rects and pixels uploaded).
local AMBIENT = {
	{ "inn", 7, 11, 0, 2 }, { "cafe", -12, 9 }, { "smokehouse", 13, 2 }, { "grill", 5, 1 }, { "stall", -6, 13 },
	{ "oak", -10, 1 }, { "cherry", 9, -5 }, { "palm", -16, 6 }, { "flowers", -4, 15 }, { "flowers", 4, -1 },
	{ "nest", -9, -6 }, { "nest", -14, -2 }, { "patch", 16, -6 }, { "torch", 5, 6 }, { "bench", -5, -3 },
	{ "picket", -6, 0, 0, 1, true }, { "picket", -4, 0, 0, 1, true }, { "picket", -2, 0, 0, 1, true },
	{ "picket", 0, 0, 0, 1, true }, { "picket", 2, 0, 0, 1, true },
}
function SCEN.ambient()
	seedProfile(2, 3, { pieces = AMBIENT, pals = { "clawdle", "mossbun", "pebblit", "gullfin" }, shells = 60000, wood = 5000 })
	local p = join(2, "Wren")
	settle(p)
	local AV = modOr(p, "Controllers.AmbientView")
	local PR = modOr(p, "Pixel.PixelRenderer")
	local DL = modOr(p, "Controllers.DayLight")
	if AV == nil or PR == nil then
		log("ambient: no AmbientView or PixelRenderer")
		return p
	end
	if DL then
		H.inClient(p, DL.debugSet, 0.3)
	end
	local plot = H.session(p).plot
	local function birdsLine(label)
		local list = H.inClient(p, AV.birds, plot)
		local parts = {}
		for _, b in list do
			-- (where it shows: full-screen px, as the PNG has it)
			local sx, sy = H.inClient(p, function()
				local pos = PR.project(E.v3(b.x, b.y, b.z))
				return pos.X, pos.Y
			end)
			table.insert(parts, string.format("%s %s%s at %d,%d", b.sp, b.state, if b.on ~= "" then " on " .. b.on else "", sx, sy))
		end
		local st = H.inClient(p, AV.stats)
		log("ambient %s: birds [%s]; %d decos (%d drawn), %d perches, %d smoke spots (%d wisps), %d leafy crowns (%d leaves), %d glints, butterflies drawn %d, fish drawn %d, fireflies %d",
			label, table.concat(parts, ", "), st.decos, st.drawnDecos, st.perches, st.puffs, st.wisps, st.canopies, st.leaves, st.glints, st.drawnButterflies, st.drawnFish, st.fireflies)
	end
	H.inClient(p, AV.debugHurry)
	E.run(4)
	birdsLine("landed")
	capture(p, "ambient")
	H.inClient(p, AV.debugHurry)
	local seen = {}
	for k = 0, 15 do
		capture(p, string.format("ambient_%03d", k))
		local st = H.inClient(p, AV.stats)
		local fishOn = ""
		if st.fishAt then
			local fx, fy = H.inClient(p, function()
				local pos = PR.project(E.v3(st.fishAt[1], st.fishAt[2], st.fishAt[3]))
				return pos.X, pos.Y
			end)
			fishOn = string.format(" at %d,%d", fx, fy)
		end
		table.insert(seen, string.format("%03d: fish %d%s glints %d butterflies %d leaves %d decos %d", k, st.drawnFish, fishOn, st.drawnGlints, st.drawnButterflies, st.leaves, st.drawnDecos))
		E.run(1 / 8)
	end
	log("ambient frames: %s", table.concat(seen, "; "))
	birdsLine("two seconds on")
	-- the founder walks up to a perched bird: it flies off
	local target = nil
	for _, b in H.inClient(p, AV.birds, plot) do
		if b.state == "perched" and b.sp ~= "gull" then
			target = b
			break
		end
	end
	if target and p.Character then
		p.Character:PivotTo(E.cf.new(target.x + 1.2, 3, target.z + 1.2))
		for k = 0, 9 do
			E.run(0.1)
			capture(p, string.format("ambient_flee_%03d", k))
		end
		birdsLine("the founder by a " .. target.sp)
	else
		log("ambient: no perched bird to walk up to")
	end
	-- at night: the fireflies over the lawn
	if DL then
		H.inClient(p, DL.debugSet, 0.88)
		E.run(4)
		birdsLine("night")
		capture(p, "ambient_night")
		H.inClient(p, DL.debugSet, 0.3)
	end
	-- the timing: back home by day, the lives back, then the real clock
	local hx, hz = H.sharedServer("Data.Street").spawn()
	local hox = H.sharedServer("Data.Street").origin(plot)
	p.Character:PivotTo(E.cf.new(hox + hx, 3, hz))
	E.run(2)
	settle(p, 20, 1)
	H.inClient(p, AV.debugHurry)
	E.run(4)
	local realClock = os.clock
	local sim0 = E.simClock
	local off = E.SIM.lastClock - realClock() + 1
	E.simClock = function()
		local v = realClock() + off
		E.SIM.lastClock = v
		return v
	end
	local function frames(n, label)
		local sum, worst, fxMs, bookMs, written, changed, rects, up, ticks = 0, 0, 0, 0, 0, 0, 0, 0, 0
		local mLife, mDecos, mParticles, mCreatures = 0, 0, 0, 0
		local t0 = H.inClient(p, PR.fxStats).ticks
		for _ = 1, n do
			local a = realClock()
			E.step(1 / 60)
			local ms = (realClock() - a) * 1000
			sum += ms
			worst = math.max(worst, ms)
			local fs = H.inClient(p, PR.fxStats)
			if fs.ticks ~= t0 then
				t0 = fs.ticks
				ticks += 1
				fxMs += fs.ms
				bookMs += fs.bookMs
				written += fs.px
				changed += fs.changed
				rects += fs.rects
				up += fs.upPx
				local st = H.inClient(p, AV.stats)
				mLife += st.msLife
				mDecos += st.msDecos
				mParticles += st.msParticles
				mCreatures += st.msCreatures
			end
		end
		local k = math.max(1, ticks)
		log("ambient timing %s: %d frames, client frame mean %.2f ms, worst %.2f ms; %d ticks: layers %.3f ms, books %.3f ms, %d px written, %d changed, %.1f rects, %d px uploaded a tick",
			label, n, sum / n, worst, ticks, fxMs / k, bookMs / k, written // k, changed // k, rects / k, up // k)
		if fxMs > 0 then
			log("ambient timing %s, the layer's parts a tick: life %.3f ms, tufts %.3f ms, sea and particles %.3f ms, creatures %.3f ms", label, mLife / k, mDecos / k, mParticles / k, mCreatures / k)
		end
	end
	frames(90, "with the lives")
	H.inClient(p, AV.setSuspended, true)
	E.run(0.2)
	frames(90, "without")
	H.inClient(p, AV.setSuspended, false)
	frames(90, "with the lives again")
	E.simClock = sim0
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
	-- what a look at the island's models for its small lives costs (AmbientView.scan, after a piece comes or goes)
	local AVc = modOr(p, "Controllers.AmbientView")
	if AVc then
		local realClock = os.clock
		local sim0 = E.simClock
		local off = E.SIM.lastClock - realClock() + 1
		E.simClock = function()
			local v = realClock() + off
			E.SIM.lastClock = v
			return v
		end
		local ms, again, found = H.inClient(p, AVc.debugScan)
		E.simClock = sim0
		log("city: the ambient scan of the islands' models took %.1f ms from scratch, %.1f ms again (%d spots found)", ms, again, found)
	end
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
		if name == "work" then
			-- the work picker for the first driftling (Work on its card): every workplace with its speed there
			H.openPanel(p, "pals", { pal = H.profile(p).pals[1].id })
		else
			H.openPanel(p, name)
		end
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
	-- one hatched from the tree's panel (the hatch scene ends at once here: the hatch=<r><hr> scenario shows it): it
	-- cracks and its driftling steps out
	local v = H.inClient(p, function()
		return modOr(p, "Controllers.StateClient").view()
	end)
	local HS = modOr(p, "UI.HatchScene")
	if HS then
		H.inClient(p, HS.setQuick, true)
	end
	local pick = nil
	for _, e in (v and v.clutch or {}) do
		if prof.shells >= (e.cost or 0) and (pick == nil or (e.cost or 0) > (pick.cost or 0)) then
			pick = e
		end
	end
	if pick then
		H.openPanel(p, "tree")
		H.clickNamed(p, "PanelHatch_" .. pick.id, { wait = 0.1 })
		H.closePanel(p)
		E.run(0.3)
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

-- The founder swimming in the sea between two islands (no docks since 2026-11-13: the neighbour's village at work,
-- boats out at sea); then the same pan baked from scratch, to compare a scrolled picture with a fresh one.
function SCEN.sea()
	local p = join(50, "Walker")
	seedProfile(51, 2, { pieces = VILLAGE, pals = PALS})
	join(51, "Neighbour", { client = false })
	settle(p)
	local Street = H.sharedServer("Data.Street")
	local x1 = Street.origin(1)
	local x2 = Street.origin(2)
	walkTo(p, (x1 + x2) / 2 + 2, 16)
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

-- "buildui": the build catalog (GAME_DESIGN 4: "Polish the build ui more, just like the bakery game, and reference
-- bloxburg"): the Decor tab on its Garden row with a card's tooltip (buildui_decor), the search box finding every
-- lantern (buildui_search), a picket fence drawn round a box
-- (its markers: buildui_fence), a stream dug in two rows (buildui_river), a plank bridge dropping in over it with its
-- dust (buildui_drop), and the island after (buildui_done).
function SCEN.buildui()
	seedProfile(57, 3, { pieces = VILLAGE, pals = { "mossbun" }, shells = 50000, wood = 200000 })
	local p = join(57, "Planner")
	settle(p, 30, 1)
	local BuildUI = modOr(p, "UI.BuildUI")
	local PR = modOr(p, "Pixel.PixelRenderer")
	local Street = H.sharedServer("Data.Street")
	local Plot = H.sharedServer("Logic.Plot")
	local prof = H.profile(p)
	local ox, oz = Street.origin(H.session(p).plot)
	H.clickNamed(p, "Menu_build", { optional = true, wait = 0.5 })
	H.clickNamed(p, "Tab_decor", { optional = true, wait = 0.3 })
	H.clickNamed(p, "Chip_garden", { optional = true, wait = 0.3 })
	settle(p, 10, 0.5)
	if BuildUI then
		H.inClient(p, function()
			BuildUI.debugTip("birdbath")
		end)
	end
	E.run(0.2)
	capture(p, "buildui_decor")
	if BuildUI == nil or PR == nil then
		return p
	end
	-- the search box: everything with "lantern" in its name, from every tab
	H.inClient(p, function()
		BuildUI.debugSearch("lantern")
	end)
	E.run(0.3)
	capture(p, "buildui_search")
	H.inClient(p, function()
		BuildUI.debugSearch("")
	end)
	E.run(0.2)
	-- a box of grass w x d where every tile fits, the nearest to (tx, tz) (the fence goes round one, the river
	-- through another, clear of the first)
	local function freeBox(w, d, tx, tz, avoid)
		local r = Street.plot(prof.tier)
		local best, bx, bz = math.huge, nil, nil
		for z = r.z0 - r.z0 % 2, r.z1, 2 do
			for x = r.x0 - r.x0 % 2, r.x1, 2 do
				local dist = (x + w / 2 - tx) ^ 2 + (z + d / 2 - tz) ^ 2
				if dist >= best then
					continue
				end
				local ok = avoid == nil or (x + w <= avoid[1] - 2 or x >= avoid[1] + avoid[3] + 2 or z + d <= avoid[2] - 2 or z >= avoid[2] + avoid[4] + 2)
				for dz = 0, d - 2, 2 do
					for dx = 0, w - 2, 2 do
						ok = ok and Plot.fits(prof.tier, prof.plot.placed, "stream", x + dx, z + dz, 0)
					end
				end
				if ok then
					best, bx, bz = dist, x, z
				end
			end
		end
		return bx, bz
	end
	-- the founder walks over (Build mode's view starts on them), then Build mode again on a tab
	local function goTo(x, z, tabName)
		H.clickNamed(p, "Cancel", { optional = true, wait = 0.2 })
		H.clickNamed(p, "BuildDone", { optional = true, wait = 0.3 })
		if p.Character then
			p.Character:PivotTo(E.cf.new(ox + x, 3, oz + z + 3))
		end
		E.run(1)
		settle(p, 20, 0.5)
		H.clickNamed(p, "Menu_build", { optional = true, wait = 0.5 })
		H.clickNamed(p, "Tab_" .. tabName, { optional = true, wait = 0.3 })
	end
	local fx, fz = freeBox(8, 6, 10, -4)
	if fx then
		goTo(fx + 4, fz + 3, "fence")
		H.clickNamed(p, "Buy_picket", { optional = true, wait = 0.3 })
		H.inClient(p, function()
			BuildUI.debugDraw({ { fx, fz }, { fx + 8, fz + 6 } }, "box", true)
		end)
		settle(p, 10, 0.4)
		capture(p, "buildui_fence")
		H.inClient(p, function()
			BuildUI.debugDraw({ { fx, fz }, { fx + 8, fz + 6 } }, "box")
		end)
		E.run(0.6)
	end
	-- a stream two tiles wide, east to west, away from the fence
	local rx, rz = freeBox(12, 8, -12, -4, if fx then { fx, fz, 8, 6 } else nil)
	if rx then
		goTo(rx + 6, rz + 4, "water")
		H.clickNamed(p, "Buy_stream", { optional = true, wait = 0.3 })
		H.inClient(p, function()
			BuildUI.debugDraw({ { rx, rz + 2 }, { rx + 10, rz + 4 } }, "box")
		end)
		settle(p, 10, 0.5)
		capture(p, "buildui_river")
		-- a plank bridge across it: picked, tapped where it fits, put down (caught as it lands)
		H.clickNamed(p, "Cancel", { optional = true, wait = 0.2 })
		local bx, bz = nil, nil
		-- (from the stream's east end: its west end runs in behind the Tree of Life in this view)
		for x = rx + 8, rx + 2, -1 do
			if bx == nil and Plot.fits(prof.tier, prof.plot.placed, "plankbridge", x, rz + 1, 0) then
				bx, bz = x, rz + 1
			end
		end
		log("buildui: river at %d,%d, bridge at %s,%s", rx, rz, tostring(bx), tostring(bz))
		if bx and bz then
			H.inClient(p, function()
				BuildUI.pick("plankbridge", 0)
				local pos = PR.project(E.v3(ox + bx + 1, Street.LAWN_Y, oz + bz + 3))
				BuildUI.tapScreen(E.v2(pos.X, pos.Y - E.inset), false)
				BuildUI.confirm()
			end)
			-- (the bridge stays picked for another, its ghost over the new one: put it down to see the landing)
			H.clickNamed(p, "Cancel", { optional = true, wait = 0 })
			E.run(0.15)
			capture(p, "buildui_drop")
			E.run(1)
			local found = false
			for _, q in prof.plot.placed do
				found = found or q.id == "plankbridge"
			end
			log("buildui: the bridge %s", if found then "stands" else "was not placed")
		end
	end
	H.clickNamed(p, "Cancel", { optional = true, wait = 0.2 })
	H.clickNamed(p, "BuildDone", { optional = true, wait = 0.5 })
	settle(p, 10, 0.5)
	capture(p, "buildui_done")
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
				local th = MM.species(d.id, "world")
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

-- "pthumbs": the build catalog's pictures drawn from the pieces' models (tools/preview/thumbs.luau; gen_thumbs.py tidies
-- them into scripts/thumbs.txt for scripts/gen_art.py: sh tools/preview/thumbs.sh). "pthumbs=<k>of<n>": every n-th
-- piece from the k-th (thumbs.sh runs a few at once); "pthumbs=<id>,<id>": those pieces, to try a change.
local function thumbsScenario(arg: string?)
	local env = { E = E, H = H, log = log, capture = capture, join = join, settle = settle, cshared = cshared, modOr = modOr }
	local k, n = string.match(arg or "", "^(%d+)of(%d+)$")
	if k then
		env.part, env.parts = tonumber(k), tonumber(n)
	elseif arg then
		env.only = {}
		for id in string.gmatch(arg, "[^,]+") do
			table.insert(env.only, id)
		end
	end
	return require("./thumbs")(env)
end
SCEN.pthumbs = thumbsScenario
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

-- "catalog=<group>": every piece of a group of the build catalog laid out on the biggest island for a close look at its
-- models (GAME_DESIGN 4): a group is a model module's ("ground" paths and water, "fence" fences, bridges and floating
-- things, "nature", "theme" (beach to jungle), "theme2" (frost to volcano), "fun" with the grand pieces), a Build mode tab ("path", "water", "decor", ...) or ids
-- joined by commas. A path or water is laid as a 2 x 2 block of tiles (its banks show), a fence as a run east and a
-- turn south, a floating piece on a pond, a bridge across a stream. Frames catalog_1 .. n, rows of about 14 studs.
local CATALOG_GROUPS: { [string]: (d: any) -> boolean } = {
	ground = function(d)
		return d.kind == "path" or d.kind == "water"
	end,
	fence = function(d)
		return d.kind == "fence" or d.tab == "water"
	end,
	nature = function(d)
		return d.tab == "nature"
	end,
	theme = function(d)
		return d.tab == "decor" and (d.sub == "beach" or d.sub == "garden" or d.sub == "farm" or d.sub == "harbour" or d.sub == "town" or d.sub == "jungle")
	end,
	theme2 = function(d)
		return d.tab == "decor" and (d.sub == "frost" or d.sub == "autumn" or d.sub == "desert" or d.sub == "fairy" or d.sub == "zen" or d.sub == "volcano")
	end,
	fun = function(d)
		return d.tab == "fun" or d.sub == "grand"
	end,
}
local function catalogScenario(group: string)
	local Buildings = H.sharedServer("Data.Buildings")
	local want: { [string]: boolean } = {}
	for id in string.gmatch(group, "[^,]+") do
		want[id] = true
	end
	local pick = CATALOG_GROUPS[group]
	local ids = {}
	for _, d in Buildings.list do
		if d.kind ~= "tree" and ((pick and pick(d)) or want[d.id] or (pick == nil and d.tab == group)) then
			table.insert(ids, d.id)
		end
	end
	-- the layout: rows across the island's middle, each piece with room round it (exact places: d[6]). Each spot is
	-- checked with the game's own rules (Plot.fits, against the tree and the pieces laid so far) and kept off the
	-- founder's spot in each frame, so nothing lands in the sea or under the founder; a piece that doesn't fit moves on.
	local Plot = H.sharedServer("Logic.Plot")
	local Schema = H.sharedServer("Logic.Schema")
	local placed = Schema.default(0, 19).plot.placed
	local pieces = {}
	local clear = {}
	for sz = -80, 60, 14 do
		for _, sx in { -13, 13 } do
			table.insert(clear, { x0 = sx - 3, z0 = sz + 2, x1 = sx + 3, z1 = sz + 7 })
		end
	end
	local function blockOf(id: string, ex: number, ez: number, x: number, z: number): { { any } }
		local d = Buildings.byId[id]
		local list = {}
		if d.kind == "path" or d.kind == "water" then
			for k = 0, 3 do
				table.insert(list, { id, ex + (k % 2) * 2, ez + (k // 2) * 2, 0 })
			end
		elseif d.kind == "fence" then
			table.insert(list, { id, ex, ez, 0 })
			table.insert(list, { id, ex + 2, ez, 0 })
			table.insert(list, { id, ex + 4, ez, 0 })
			table.insert(list, { id, ex + 6, ez, 90 })
			table.insert(list, { id, ex + 6, ez + 2, 90 })
		elseif d.water == "on" then
			-- a pond under it, a tile wider all round
			for tz = ez, ez + math.max(d.d + 2, 4), 2 do
				for tx = ex, ex + math.max(d.w + 2, 4), 2 do
					table.insert(list, { "stream", tx, tz, 0 })
				end
			end
			table.insert(list, { id, ex + 2, ez + 2, 0 })
		elseif d.water == "over" then
			-- a stream two tiles wide running east under its middle
			local mz = ez + 2 + math.floor(d.d / 2) - 2
			mz -= mz % 2
			for tx = ex, ex + d.w + 2, 2 do
				table.insert(list, { "stream", tx, mz, 0 })
				table.insert(list, { "stream", tx, mz + 2, 0 })
			end
			table.insert(list, { id, ex + 1, ez + 1, 0 })
		else
			table.insert(list, { id, x, z, 0 })
		end
		return list
	end
	local function tryBlock(list: { { any } }, w: number, dd: number, x: number, z: number): boolean
		for _, r in clear do
			if x - 1 < r.x1 and r.x0 < x + w + 1 and z - 1 < r.z1 and r.z0 < z + dd + 1 then
				return false
			end
		end
		local n = #placed
		local ok = true
		for _, q in list do
			if ok and Plot.fits(10, placed, q[1], q[2], q[3], q[4]) then
				table.insert(placed, { uid = 0, id = q[1], x = q[2], z = q[3], rot = q[4], lvl = 1 })
			else
				ok = false
			end
		end
		if not ok then
			for i = #placed, n + 1, -1 do
				placed[i] = nil
			end
		end
		return ok
	end
	-- (rows across the island's wide middle: its north tip is beach)
	local x, z = -22, -84
	local rowD = 0
	local dropped = 0
	local firstZ: number? = nil
	for _, id in ids do
		local d = Buildings.byId[id]
		local w = if d.kind == "path" or d.kind == "water" then 4 elseif d.kind == "fence" then 6 elseif d.water ~= "" then math.max(d.w + 2, 6) else d.w
		local dd = if d.kind == "path" or d.kind == "water" then 4 elseif d.kind == "fence" then 4 elseif d.water ~= "" then math.max(d.d + 2, 6) else d.d
		local done = false
		while not done and z < 60 do
			if x + w > 22 then
				x = -22
				z += math.max(rowD, 2) + 4
				rowD = 0
			end
			local ex, ez = x - x % 2, z - z % 2
			local list = blockOf(id, ex, ez, x, z)
			if tryBlock(list, w, dd, ex, ez) then
				for _, q in list do
					table.insert(pieces, { q[1], q[2], q[3], q[4], 1, true })
				end
				done = true
				firstZ = firstZ or z
				x += w + 3
				rowD = math.max(rowD, dd)
			else
				x += 2
			end
		end
		if not done then
			dropped += 1
			log("catalog: no room for %s", id)
		end
	end
	seedProfile(19, 10, { pieces = pieces, shells = 900000, wood = 900000 })
	local p = join(19, "Catalog")
	settle(p)
	local Street = H.sharedServer("Data.Street")
	local ox = Street.origin(H.session(p).plot)
	local k = 0
	-- (the frames on the founder's spots kept clear above, from the first row with a piece in it; at least one)
	local sz0 = -80 + 14 * math.floor(((firstZ or -84) + 4 + 80) / 14)
	for sz = sz0, math.max(sz0, z + rowD), 14 do
		for _, sx in { -13, 13 } do
			if p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
				p.Character:PivotTo(E.cf.new(ox + sx, 3, sz + 4))
				E.run(1.5)
				settle(p, 30, 1)
			end
			k += 1
			capture(p, "catalog_" .. k)
		end
	end
	log("catalog %s: %d pieces in %d frames (%d with no room)", group, #ids, k, dropped)
	return p
end

-- "theme=<name>" (or "themes": all of them, a job each): a Sunspire Capital built in one of the catalog's themes, to
-- show how different two islands can look (GAME_DESIGN 4: "enough paths, fences and other detail to make a lot of
-- vastly different themed islands"): its paths in a ring round the plaza and an avenue north, a river under a bridge,
-- a pond with what floats on it, a fenced garden with a gate, trees and plants, the theme's decor and its fun pieces,
-- and a few huts and workplaces. Frames theme_<name> (the middle) and theme_<name>_north.
local THEMES: { [string]: { [string]: any } } = {
	beach = { ground = "sandtrail", path = { "sandtrail", "shellpath" }, fence = { "driftwood", "ropefence" }, water = "lagoon", floats = { "duckfloat", "rowboat" }, bridge = "dock", trees = { "palm", "palm", "jungletree" }, plants = { "bush", "monstera", "tallgrass", "fern" }, decor = { "umbrella", "deckchair", "deckchair", "surfboards", "sandcastle", "shellpile", "coconuts", "lifeguard", "buoy" }, fun = { "tikibar", "hammock", "firepit", "torch", "torch" } },
	garden = { ground = "flagstone", path = { "flagstone", "stonepath" }, fence = { "picket", "hedgerow", "gardengate" }, water = "lilypond", floats = { "lilypads", "duckfloat" }, bridge = "plankbridge", trees = { "oak", "birch", "cherry" }, plants = { "rosebush", "tulips", "sunflowers", "lavender", "flowers", "berrybush" }, decor = { "gnome", "birdbath", "beehive", "trellis", "sundial", "flowerarch", "topiary", "gazebo", "wheelbarrow" }, fun = { "parkbench", "gardenlights", "gardenlights", "smallfountain", "porchswing" } },
	frost = { ground = "snowpath", path = { "snowpath", "cobble" }, fence = { "icewall", "splitrail" }, water = "icepond", floats = {}, bridge = "plankbridge", trees = { "snowpine", "snowpine", "pine" }, plants = { "snowrock", "boulder", "deadtree" }, decor = { "snowman", "snowman", "sled", "icelantern", "icelantern", "icesculpture", "igloo" }, fun = { "firepit", "candles", "logseats", "stringlights" } },
	zen = { ground = "raked", path = { "raked", "flagstone" }, fence = { "bamboofence" }, water = "lilypond", floats = { "lotus", "steppingstones", "lilypads" }, bridge = "moonbridge", trees = { "cherry", "willow", "pine" }, plants = { "bonsai", "mossrock", "fern", "tallgrass" }, decor = { "stonelantern", "stonelantern", "windchime", "bambooscreen", "zenbasin", "lanterntower", "rockgarden" }, fun = { "stonebench", "paperlanterns", "paperlanterns" } },
	volcano = { ground = "basalt", path = { "basalt", "gravel" }, fence = { "stonewall", "palisade" }, water = "hotspring", floats = { "steppingstones" }, bridge = "stonebridge", trees = { "deadtree", "deadtree", "jungletree" }, plants = { "basaltcols", "lavarock", "rockpile", "fern" }, decor = { "firebasin", "firebasin", "steamvent", "obsidian", "lavapool", "idol", "tikimask" }, fun = { "firepit", "torch", "torch", "grill" } },
	fairy = { ground = "meadow", path = { "crystalpath", "meadow" }, fence = { "crystalfence", "hedgerow" }, water = "lilypond", floats = { "waterlanterns", "lotus", "lilypads" }, bridge = "ropebridge", trees = { "cherry", "willow", "bigoak" }, plants = { "giantshroom", "glowshroom", "mushrooms", "crystals", "lavender" }, decor = { "fairylantern", "fairylantern", "mushroomring", "moonstone", "wishingwell", "crystalarch" }, fun = { "swing", "candles", "stringlights" } },
}
local THEME_ORDER = { "beach", "garden", "frost", "zen", "volcano", "fairy" }
local function themeScenario(name: string)
	local T = THEMES[name]
	if T == nil then
		error("no theme " .. name)
	end
	local pieces = {}
	local function exact(id, x, z, rot)
		table.insert(pieces, { id, x, z, rot or 0, 1, true })
	end
	local function near(id, x, z, rot)
		table.insert(pieces, { id, x, z, rot or 0, 1 })
	end
	-- the river (two tiles wide, west to east across the island's middle) and its bridge over the avenue
	for x = -24, 22, 2 do
		exact(T.water, x, -20)
		exact(T.water, x, -18)
	end
	exact(T.bridge, -1, -22)
	-- a pond west of the avenue, what floats on it
	for z = -36, -28, 2 do
		for x = -26, -16, 2 do
			exact(T.water, x, z)
		end
	end
	for k, id in T.floats do
		exact(id, -24 + (k - 1) * 4, -34 + (k % 2) * 2)
	end
	-- paths: a ring round the plaza, the avenue north to the garden
	for x = -14, 12, 2 do
		exact(T.path[1], x, -8)
	end
	for z = -6, 12, 2 do
		exact(T.path[1], -14, z)
		exact(T.path[1], 12, z)
	end
	for z = -46, -10, 2 do
		exact(T.path[2] or T.path[1], 0, z)
	end
	-- a fenced garden north-east, its gate on the side facing the avenue
	local fx0, fz0, fx1, fz1 = 6, -44, 22, -28
	for x = fx0, fx1 - 2, 2 do
		exact(T.fence[1], x, fz0, 0)
		exact(if x == fx0 + 6 and T.fence[3] then T.fence[3] else T.fence[1], x, fz1, 0)
	end
	for z = fz0, fz1 - 2, 2 do
		exact(T.fence[2] or T.fence[1], fx0, z, 90)
		exact(T.fence[2] or T.fence[1], fx1, z, 90)
	end
	-- the theme's ground paving the yard inside the fence and the strip between the river and the plaza (decor, plants
	-- and benches stand on it: a snowman on snow)
	for z = fz0, fz1 - 2, 2 do
		for x = fx0, fx1 - 2, 2 do
			exact(T.ground, x, z)
		end
	end
	for z = -16, -12, 2 do
		for x = -14, 12, 2 do
			if x ~= 0 then
				exact(T.ground, x, z)
			end
		end
	end
	-- inside the garden: the theme's decor in rows; the rest round the plaza and along the river
	local spots = { { 8, -42 }, { 12, -42 }, { 16, -42 }, { 19, -41 }, { 8, -37 }, { 13, -37 }, { 18, -36 }, { 9, -32 }, { 15, -32 }, { 19, -31 } }
	for k, id in T.decor do
		local sp = spots[(k - 1) % #spots + 1]
		near(id, sp[1], sp[2])
	end
	local funSpots = { { -11, -4 }, { 7, -4 }, { -11, 12 }, { 8, 12 }, { -6, -14 }, { 4, -14 } }
	for k, id in T.fun do
		local sp = funSpots[(k - 1) % #funSpots + 1]
		near(id, sp[1], sp[2])
	end
	-- trees round the edges, plants by the paths
	local treeSpots = { { -24, -6 }, { -22, 4 }, { 20, -8 }, { 22, 2 }, { -8, -44 }, { -20, -46 }, { 26, -24 }, { -28, -16 }, { 18, -50 }, { -12, -52 } }
	for k, sp in treeSpots do
		near(T.trees[(k - 1) % #T.trees + 1], sp[1], sp[2])
	end
	local plantSpots = { { -17, -2 }, { 15, -2 }, { -17, 8 }, { 15, 8 }, { -4, -26 }, { 4, -26 }, { -4, -38 }, { 4, -38 }, { -12, -14 }, { 10, -14 }, { -14, -42 }, { 26, -16 } }
	for k, sp in plantSpots do
		near(T.plants[(k - 1) % #T.plants + 1], sp[1], sp[2])
	end
	-- a few huts and workplaces, so it is somebody's island
	near("burrow", -22, -12)
	near("nest", -18, 12)
	near("den", 18, -12)
	near("lumber", 22, 8)
	near("patch", -26, 6)
	seedProfile(70 + table.find(THEME_ORDER, name) :: number, 6, { pieces = pieces, pals = { "mossbun", "clawdle", "pebblit", "gullfin" }, shells = 90000, wood = 90000 })
	local p = join(70 + table.find(THEME_ORDER, name) :: number, string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2))
	settle(p)
	local Street = H.sharedServer("Data.Street")
	local ox = Street.origin(H.session(p).plot)
	for _, view in { { "theme_" .. name, -2, -14 }, { "theme_" .. name .. "_north", 4, -36 } } do
		if p.Character then
			p.Character:PivotTo(E.cf.new(ox + view[2], 3, view[3]))
		end
		E.run(1.5)
		settle(p, 30, 1)
		capture(p, view[1])
	end
	log("theme %s: %d pieces placed of %d", name, #H.profile(p).plot.placed, #pieces)
	return p
end

-- "hatch=<r><hr>": the hatch scene (UI/HatchScene; GAME_DESIGN 6.2) for an egg laid as rarity r that hatches as hr
-- (hr > r: it turns rarer on the way), a tier 10 island's kind of that rarity with a set of mutations by rarity. The
-- request of 2026-11-14: "could you also remove the transition that happens when clicking to hatch an egg? you can
-- simply render the floating egg in a 2d background. also, make the player click to hatch the egg, each click
-- revealing a mutation or a tier up upgrade if there is any, otherwise it just hatches". Frames: the egg floating at
-- once, the frame it opens (hatch_egg), after each tap's reveal (hatch_rise<k> for a step up, hatch_mut<k> for a
-- mutation), the tap that hatches it (hatch_crack, just after) and what hatched with its mutations listed
-- (hatch_reveal), then the island after one more tap (hatch_back).
local function hatchScenario(code)
	local r = tonumber(string.sub(code, 1, 1)) or 1
	local hr = tonumber(string.sub(code, 2, 2)) or r
	seedProfile(61, 10, { pieces = VILLAGE, pals = { "mossbun" }, shells = 9e6 })
	local p = join(61, "Hatcher")
	settle(p)
	local HS = modOr(p, "UI.HatchScene")
	if HS == nil then
		log("no HatchScene")
		return p
	end
	local Creatures = H.sharedServer("Data.Creatures")
	local sp = nil
	for _, d in Creatures.list do
		if d.rarity == hr and sp == nil then
			sp = d.id
		end
	end
	local MUTS = { {}, { "busy1" }, { "grower2", "bright1" }, { "fierce3", "swift2", "lazy" }, { "bright4", "busy3", "armor2", "trader1" } }
	local muts = MUTS[hr] or {}
	H.inClient(p, function()
		HS.play({ sp = sp or "mossbun", muts = muts, r = r, hr = hr }, nil)
	end)
	local function state()
		return H.inClient(p, HS.debugState)
	end
	-- (no blinds: the egg is there in the very next frames; a few frames for the picture)
	E.run(0.12)
	local PR = modOr(p, "Pixel.PixelRenderer")
	local ready = PR and H.inClient(p, PR.ready)
	local st = state()
	log("hatch %s: opened at once: phase %s, renderer ready %s, %d reveals to tap", code, st.phase, tostring(ready), st.reveals)
	E.run(0.2)
	capture(p, "hatch_rising")
	log("hatch %s: rising: %.2f studs under its spot", code, -state().lift)
	E.run(0.9)
	capture(p, "hatch_egg")
	local rises, mutsShown = 0, 0
	for _ = 1, st.reveals do
		local before = state()
		H.inClient(p, HS.skip)
		E.run(0.3)
		local after = state()
		if after.r > before.r then
			rises += 1
			capture(p, "hatch_rise" .. rises)
		else
			mutsShown += 1
			capture(p, "hatch_mut" .. mutsShown)
		end
	end
	st = state()
	log("hatch %s: after %d taps: rarity %d, %d mutations shown, cracks %d, glowing %s, title %q", code, st.reveals, st.r, st.shown, st.crack, tostring(st.glowing), st.title)
	H.inClient(p, HS.skip)
	E.run(0.18)
	capture(p, "hatch_crack")
	E.run(1.4)
	st = state()
	capture(p, "hatch_reveal")
	log("hatch %s: laid %d, hatched %d as %s: phase %s, %d mutations of %d, %s, title %q, name %q", code, r, st.r, tostring(sp), st.phase, st.shown, st.muts, if st.pal then "what hatched is there" else "nothing hatched", st.title, st.name)
	H.inClient(p, HS.skip)
	E.run(0.2)
	log("hatch %s: closed %s", code, tostring(not state().open))
	settle(p, 10, 0.3)
	capture(p, "hatch_back")
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
	local theme = string.match(name, "^theme=(%w+)$")
	if theme then
		fn = function()
			return themeScenario(theme)
		end
	end
	local group = string.match(name, "^catalog=([%w_,]+)$")
	if group then
		fn = function()
			return catalogScenario(group)
		end
	end
	local palsArg = string.match(name, "^pals=([%w_,]+)$")
	if palsArg then
		fn = function()
			return palsScenario(palsArg)
		end
	end
	local hatch = string.match(name, "^hatch=(%d%d)$")
	if hatch then
		fn = function()
			return hatchScenario(hatch)
		end
	end
	local thumbs = string.match(name, "^pthumbs=([%w_,]+)$")
	if thumbs then
		fn = function()
			return thumbsScenario(thumbs)
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
