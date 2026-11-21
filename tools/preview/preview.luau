-- Pixel Island's preview driver: boots the real server and client scripts in the fake engine (with the real
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
-- ("f32:<scenario>": the scenario with the raycaster's ball test in single precision, as Roblox's is)
if string.sub(scenario, 1, 4) == "f32:" then
	scenario = string.sub(scenario, 5)
	require("./engine").f32Rays = true
end
-- ("lang=<code>:<scenario>": the scenario with the player's language set to that one; "smooth:<scenario>": with
-- Settings' Text on Smooth, every word in Roblox's own font; both can be given, either order)
local LANG_ARG: string? = nil
local SMOOTH_ARG = false
while true do
	local code, rest = string.match(scenario, "^lang=(%a+):(.+)$")
	if code and rest then
		LANG_ARG, scenario = code, rest
	elseif string.sub(scenario, 1, 7) == "smooth:" then
		SMOOTH_ARG, scenario = true, string.sub(scenario, 8)
	else
		break
	end
end
-- (the players' Roblox language is that one too, so a profile the scenario didn't seed, on Auto, follows it: the
-- loading card's)
if LANG_ARG then
	E.locale = LANG_ARG
end
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
		-- (words too big for their box: "there is a few boxes where text overflows", 2026-11-14)
		if PT.overflows then
			local okO, over = pcall(PT.overflows)
			if okO and type(over) == "table" then
				for _, o in over do
					log("OVERFLOW %s: %s %q needs %dx%d, box %dx%d%s", name, o.name, o.text, o.w, o.h, o.bw, o.bh, if o.clipped then " (clipped)" else "")
				end
			else
				log("overflow check %s failed: %s", name, tostring(over))
			end
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
	-- (smooth: on a profile the scenario didn't seed too, set as a player's tap would)
	if SMOOTH_ARG then
		local res = H.req(p, "settings.set", { k = "text", v = "smooth" })
		if not (res and res.ok) then
			log("settings.set text smooth: %s", tostring(res and res.err))
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
-- when given), pals (species: into the huts with room, the best first, at work at their knack), shells (the one store), day,
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
	-- (opts.inv: Build mode's inventory, { [id] = how many })
	prof.inv = opts.inv or prof.inv
	prof.day = opts.day or 12
	prof.tut = opts.tut or 0
	-- (the language and the text style the scenario asked for: lang=<code>:, smooth:)
	if LANG_ARG then
		prof.settings.lang = LANG_ARG
	end
	if SMOOTH_ARG then
		prof.settings.text = "smooth"
	end
	-- (opts.fill(prof): lays pieces itself, the stress test's full island)
	if opts.fill then
		opts.fill(prof)
	end
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
		local MUTS = { { "fierce3", "swift1" }, { "grower2" }, {}, { "sturdy4", "bright2", "lazy" } }
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
	-- (opts.touch: { kind, season, { egg, tier }, ... }: those eggs laid in that season and touched by that weather,
	-- GAME_DESIGN 13)
	if opts.touch then
		for k = 3, #opts.touch do
			local e = prof.clutch.list[opts.touch[k][1]]
			if e then
				e.ss, e.wx, e.wt = opts.touch[2], opts.touch[1], opts.touch[k][2]
			end
		end
	end
	prof.clutch.left = opts.left or (Tuning.EggSecs - 60)
	-- (opts.away: seconds since the island was last open, so it has offline earnings waiting: GAME_DESIGN 14.3)
	if opts.away then
		prof.seenAt = now - opts.away
	end
	for _, sp in opts.seen or {} do
		prof.seen[sp] = math.max(prof.seen[sp] or 0, 1)
	end
	prof.stats.days = prof.day - 1
	prof.stats.taken = #prof.pals
	prof.stats.built = #prof.plot.placed
	-- an egg warming in the first Hatchery (opts.egg: { sp, left, muts }), and one in the second (opts.egg2)
	for k, e in { opts.egg or false, opts.egg2 or false } do
		if e then
			for _, q in prof.plot.placed do
				if q.id == "hatchery" and #prof.eggs == k - 1 and #prof.pals >= 2 and (prof.eggs[1] == nil or prof.eggs[1].uid ~= q.uid) then
					table.insert(prof.eggs, { uid = q.uid, a = prof.pals[1].id, b = prof.pals[2].id, sp = e[1], left = e[2], muts = e[3] or {} })
				end
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
	-- the founder on the island's south rim, the rock under its edge and the painted sky in view (the request of
	-- 2026-11-20: "make it a floating island instead, with a 2d skybox"): island_edge
	local Street = H.sharedServer("Data.Street")
	local ox, oz = Street.origin(H.session(p).plot)
	local sx, sz = Street.sign(1)
	if p.Character then
		p.Character:PivotTo(E.cf.new(ox + sx + 4, 3, oz + sz - 0.5))
		E.run(2)
		settle(p, 30, 1)
		E.run(1)
		capture(p, "island_edge")
	end
	local SB = modOr(p, "UI.SkyBackdrop")
	if SB then
		local d = H.inClient(p, SB.debugState)
		log("island sky: %s, %dx%d art px, painted %d times, the sea of clouds at %d", d.kind, d.W, d.H, d.paints, d.seaOff)
	end
	return p
end

-- A tier-1 village a dozen days in: driftlings at work and hopping about, the island card.
function SCEN.village()
	seedProfile(2, 1, { pieces = VILLAGE, pals = { "clawdle", "mossbun", "pebblit" }})
	local p = join(2, "Wren")
	settle(p)
	E.run(2.5)
	capture(p, "village")
	-- (how full the buildings are, the request of 2026-11-14: alerts over the empty ones, and a tap on a hut with
	-- driftlings in it showing its card, village_card)
	local BT = modOr(p, "Controllers.BuildingTags")
	if BT then
		local st = H.inClient(p, BT.debugState)
		log("village: %d workplaces and huts, %d alerts (%s)", st.spots, st.alerts, table.concat(st.words, ", "))
		local pick
		for _, sp in H.inClient(p, BT.debugSpots) do
			if not sp.work and sp.n > 0 and sp.tap and pick == nil then
				pick = sp
			end
		end
		if pick then
			local shown = H.inClient(p, BT.tapAt, pick.tap)
			E.run(0.3)
			log("village: a tap on the %s (uid %d): card %s %q", pick.id, pick.uid, tostring(shown), H.inClient(p, BT.debugState).card)
			capture(p, "village_card")
		end
		-- (a workplace's card: how full, what it earns a minute; the request of 2026-11-15)
		E.run(3.2)
		local work
		for _, sp in H.inClient(p, BT.debugSpots) do
			if sp.work and sp.n > 0 and sp.tap and work == nil then
				work = sp
			end
		end
		if work then
			E.raycastParts = true
			local shown = H.inClient(p, BT.tapAt, work.tap)
			E.raycastParts = nil
			E.run(0.3)
			local st = H.inClient(p, BT.debugState)
			log("village: a tap on the %s (uid %d): card %s %q / %q", work.id, work.uid, tostring(shown), st.card, st.card2)
			capture(p, "village_work")
		end
	end
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

-- What moves on its own (the request of 2026-11-14: "animate models better, such as trees swaying, instead of just
-- shiftiing side to side, make them actually rustle like leaves. other models should be animated if possible too,
-- such as windmills being able to spin and waterfalls having flowing water"): the village on a tier 3 island with a
-- windmill, a waterwheel, a little waterfall and the Grand Mill by the palms, and (the request of 2026-11-19: "detail
-- all decor more, some having animations") a swing set, a fire pit and a little fountain; the log lists the moving
-- copies (Controllers/Spinners); then a frame every sixth of a second for two seconds (motion_000 .. motion_011: the
-- leaves rustling, the sails and wheels turning, the falls running, the swings swinging, sparks off the fire and spray
-- off the fountain).
function SCEN.motion()
	local pieces = table.clone(VILLAGE)
	for _, q in { { "windmill", -2, -10 }, { "waterwheel", -12, -6 }, { "littlefall", 13, 6 }, { "grandmill", 13, -9 }, { "palm", 2, -6 }, { "palm", -6, -9 }, { "swing", 6, 2 }, { "firepit", 9, 3 }, { "smallfountain", 3, 4 } } do
		table.insert(pieces, q)
	end
	seedProfile(2, 3, { pieces = pieces, pals = { "clawdle", "mossbun", "pebblit" } })
	local p = join(2, "Wren")
	settle(p)
	E.run(2)
	local SP = modOr(p, "Controllers.Spinners")
	if SP then
		local st = H.inClient(p, SP.debugState)
		log("motion: %d turning copies (%s), %d parts turning, still %s", st.count, table.concat(st.ids, ", "), st.parts, tostring(st.still))
	end
	for k = 0, 11 do
		capture(p, string.format("motion_%03d", k))
		E.run(1 / 6)
	end
	-- (the windmill's card: the farms' boost from every boost building there, what one more adds; 2026-11-15)
	local BT = modOr(p, "Controllers.BuildingTags")
	if BT then
		local mill
		for _, sp in H.inClient(p, BT.debugSpots) do
			if sp.kind == "boost" and sp.tap and mill == nil then
				mill = sp
			end
		end
		if mill then
			E.raycastParts = true
			local shown = H.inClient(p, BT.tapAt, mill.tap)
			E.raycastParts = nil
			E.run(0.3)
			local st = H.inClient(p, BT.debugState)
			log("motion: a tap on the %s: card %s %q / %q", mill.id, tostring(shown), st.card, st.card2)
			capture(p, "motion_boost")
		end
	end
	return p
end

-- The camera on the move (the report of 2026-11-15: "the camera moving is always very laggy. can this be fixed?"): the
-- village, the founder walked east then north at walking speed (the camera following it), the renderer's frames timed
-- (PixelRenderer.debugPerf: the scrolls, the composes, the full uploads and their grade, the whole frame), then as long
-- standing still; pan_000 .. pan_005 a frame every half second of the walk.
-- The biggest island at every limit, walked across (the request of 2026-11-17: "As the game requires you to walk around
-- in bigger islands and bigger islands will have more buildings, do a stress test with the maximum amount of decor and
-- buildings at the highest expansion level. Try walking around to move the camera. It should be smooth."): Everdrift
-- (tier 20) with its piece limit filled (42 Citadels for the 840 driftlings the huts may hold, the Hatcheries it may
-- have, the boost buildings twice over, workplaces of every kind, then decor to the limit), a pond of water tiles,
-- every path tile it may have and every fence length that fits, walkways two studs wide left between the blocks; 840
-- driftlings. The founder walks the island's length and back across it at walking speed on the real clock; the log has
-- the frames (the slowest, how many over 25 ms), the pixel filter's share and every script's (E.coTime: each
-- connection's time by its source line, the server's and the client's).
local function fillMax(prof)
	local tier = prof.tier
	local Plot = H.sharedServer("Logic.Plot")
	local Buildings = H.sharedServer("Data.Buildings")
	local Street = H.sharedServer("Data.Street")
	local placed = prof.plot.placed
	local occ = {}
	local function key(x, z)
		return (x + 512) * 4096 + (z + 2048)
	end
	local function mark(id, x, z, rot)
		local r = Plot.rect(id, x, z, rot)
		for cz = r.z0, r.z1 - 1 do
			for cx = r.x0, r.x1 - 1 do
				occ[key(cx, cz)] = true
			end
		end
	end
	local function free(id, x, z, rot)
		local r = Plot.rect(id, x, z, rot)
		for cz = r.z0, r.z1 - 1 do
			for cx = r.x0, r.x1 - 1 do
				if occ[key(cx, cz)] then
					return false
				end
			end
		end
		return true
	end
	local function add(id, x, z, rot)
		table.insert(placed, { uid = prof.nextId, id = id, x = x, z = z, rot = rot, lvl = 1 })
		prof.nextId += 1
	end
	for _, q in placed do
		mark(q.id, q.x, q.z, q.rot)
	end
	-- the island's cells (north first), walkways every 14 studs north-south and every 16 east-west kept clear
	local X0, X1, Z0, Z1 = -34, 33, -198, 17
	for z = Z0, Z1 do
		for x = X0, X1 do
			if (z % 14 == 0 or z % 14 == 1) or (x % 16 == 0 or x % 16 == 1) then
				occ[key(x, z)] = true
			end
		end
	end
	-- a pond of water tiles, west of the middle
	local water = 0
	for z = -110, -100, 2 do
		for x = -26, -14, 2 do
			local id = if (x + z) % 4 == 0 then "lagoon" else "lilypond"
			if free(id, x, z, 0) and Plot.fits(tier, placed, id, x, z, 0) then
				add(id, x, z, 0)
				mark(id, x, z, 0)
				water += 1
			end
		end
	end
	-- the pieces, in proportion as they go (so each kind is spread over the whole island)
	local groups = { huts = {}, breed = {}, boost = {}, work = {}, decor = {} }
	-- (the citadel at the top tiers; a smaller island has its roomiest hut instead: the crowd preview)
	local hutId = "citadel"
	if Buildings.byId.citadel.tier > tier then
		local best = nil
		for _, d in Buildings.list do
			if d.kind == "nest" and d.tier <= tier and (best == nil or (d.slots or 0) > (best.slots or 0)) then
				best = d
			end
		end
		hutId = best.id
	end
	for _, d in Buildings.list do
		if d.tier <= tier then
			if d.kind == "nest" and d.id == hutId then
				table.insert(groups.huts, d.id)
			elseif d.kind == "breed" then
				table.insert(groups.breed, d.id)
			elseif d.kind == "gen" then
				table.insert(groups.boost, d.id)
			elseif d.kind == "work" then
				table.insert(groups.work, d.id)
			elseif d.kind == "decor" and (d.water or "") == "" then
				table.insert(groups.decor, d.id)
			end
		end
	end
	local limit = Plot.limit(tier)
	local want = { huts = math.ceil(Plot.housingLimit(tier) / Buildings.byId[hutId].slots), breed = Plot.hatcheryLimit(tier), boost = 2 * #groups.boost, work = 0 }
	-- (the workplaces round their list, their places up to the work cap, Plot.workLimit: the request of 2026-11-18; one
	-- that would pass it is skipped for the smaller ones after it, until the cap is full)
	local workIds: { string } = {}
	local workPlaces, k, misses = 0, 0, 0
	while #groups.work > 0 and misses < #groups.work do
		local id = groups.work[k % #groups.work + 1]
		k += 1
		local d = Buildings.byId[id]
		if workPlaces + d.jobs <= Plot.workLimit(tier) then
			workPlaces += d.jobs
			table.insert(workIds, id)
			misses = 0
		else
			misses += 1
		end
	end
	groups.work = workIds
	want.work = #workIds
	want.decor = limit - want.huts - want.breed - want.boost - want.work
	local got = { huts = 0, breed = 0, boost = 0, work = 0, decor = 0 }
	local ORDER = { "huts", "breed", "boost", "work", "decor" }
	local cells = {}
	for z = Z0, Z1 do
		for x = X0, X1 do
			if Street.buildable(tier, x, z) then
				table.insert(cells, x * 65536 + (z + 32768))
			end
		end
	end
	local cursor = 1
	local failed = 0
	for k = 1, limit do
		local pick, best = nil, -math.huge
		for _, g in ORDER do
			if got[g] < want[g] then
				local owed = want[g] * k / limit - got[g]
				if owed > best then
					pick, best = g, owed
				end
			end
		end
		if pick == nil then
			break
		end
		local list = groups[pick]
		local id = list[got[pick] % #list + 1]
		got[pick] += 1
		local done = false
		for n = 0, #cells - 1 do
			local c = cells[(cursor + n - 1) % #cells + 1]
			local x, z = c // 65536, c % 65536 - 32768
			if free(id, x, z, 0) and Plot.fits(tier, placed, id, x, z, 0) then
				add(id, x, z, 0)
				mark(id, x, z, 0)
				cursor = (cursor + n - 1) % #cells + 1
				done = true
				break
			end
		end
		if not done then
			failed += 1
		end
	end
	-- every path tile it may have, over the whole island (under the buildings too), then the fences
	local PATHS = { "cobble", "marblewalk", "brickroad", "goldpath", "starpath", "flagstone" }
	local tiles = water
	for z = Z0, Z1, 2 do
		for x = X0 + (X0 % 2), X1, 2 do
			if tiles >= Plot.pathLimit(tier) then
				break
			end
			local id = PATHS[((x // 2) + (z // 2)) % #PATHS + 1]
			if Plot.fits(tier, placed, id, x, z, 0) then
				add(id, x, z, 0)
				tiles += 1
			end
		end
	end
	local FENCES = { "picket", "hedgerow", "lanternrope", "crystalfence", "stonewall" }
	local fences = 0
	for z = Z0, Z1, 2 do
		for x = X0 + (X0 % 2), X1, 2 do
			for _, rot in { 0, 90 } do
				if fences < Plot.fenceLimit(tier) then
					local id = FENCES[((x // 2) * 3 + (z // 2)) % #FENCES + 1]
					if Plot.fits(tier, placed, id, x, z, rot) then
						add(id, x, z, rot)
						fences += 1
					end
				end
			end
		end
	end
	log("stress fill: %d huts, %d hatcheries, %d boost buildings, %d workplaces (%d places of %d), %d decor (%d of %d pieces, %d did not fit), %d water and %d path tiles (of %d), %d fence lengths (of %d)",
		got.huts, got.breed, got.boost, got.work, Plot.work(placed), Plot.workLimit(tier), got.decor, got.huts + got.breed + got.boost + got.work + got.decor - failed, limit, failed, water, tiles - water, Plot.pathLimit(tier), fences, Plot.fenceLimit(tier))
end

-- The incremental compose against a whole one (PixelRenderer.debugIncCheck), every `every` frames of a walk: `step`
-- arms the next check and tallies the last one's result; `line` says how they went.
local function incTally(p, PR, every)
	local t = { n = 0, off = 0, worst = 0, px = 0, ties = 0 }
	function t.step(i)
		if PR.debugIncCheck == nil or i % every ~= 0 then
			return
		end
		local r = H.inClient(p, PR.debugIncCheck)
		if r.off >= 0 and r.checked > 0 and r ~= t.last then
			t.n += 1
			t.off += r.off
			t.ties += r.ties or 0
			t.worst = math.max(t.worst, r.off)
			t.px += r.px
			if r.off > 0 and r.seen then
				log("incremental check off: %d px; %s", r.off, r.seen)
			end
		end
		t.last = r
	end
	function t.line(): string
		return string.format("%d incremental composes checked against whole ones: %d pixels off in all (the worst %d; %d more where two models meet within the depth bias), %d px redone each on average", t.n, t.off, t.worst, t.ties, t.px // math.max(1, t.n))
	end
	return t
end

-- "crowd": a busy town's driftlings on the move (the request of 2026-11-18: "make it such that overworld creatures
-- move smoother"). A Harbor Town (tier 4) filled to its limits with driftlings, walking to work and back; the world at
-- 60 frames a second of its own time (the renderer's and WorldView's budgets on the real clock, as in stress). For
-- three seconds every frame notes where each walking driftling's picture went down (PixelRenderer.debugShown): the
-- log says how many times a second a walker's picture moved (the median and the slowest tenth) and how far it jumped
-- (art px: the median jump and the largest), with the frame's cost; frames crowd_000 .. crowd_011, the last twelve
-- at 30 a second (`make_gif.py <outdir> crowd <device> 30`).
function SCEN.crowd()
	local Creatures = H.sharedServer("Data.Creatures")
	local Plot = H.sharedServer("Logic.Plot")
	local tier = 4
	local pals = {}
	for k = 1, Plot.housingLimit(tier) do
		table.insert(pals, Creatures.list[(k * 7 - 1) % #Creatures.list + 1].id)
	end
	seedProfile(23, tier, { fill = fillMax, pals = pals, shells = 9e6 })
	local p = join(23, "Crowd")
	settle(p, 60, 2)
	E.run(6)
	local PR = modOr(p, "Pixel.PixelRenderer")
	local WV = modOr(p, "Controllers.WorldView")
	if PR == nil or WV == nil or PR.debugShown == nil or WV.debugMoving == nil then
		log("crowd: no debug hooks")
		return p
	end
	local housed, working = 0, 0
	for _, x in H.profile(p).pals do
		housed += if x.home ~= 0 then 1 else 0
		working += if x.work ~= 0 then 1 else 0
	end
	log("crowd: %d driftlings, %d in huts, %d at work; %d drawn on the islands near the view, %d dressed", #H.profile(p).pals, housed, working, H.inClient(p, WV.rigCount), #H.inClient(p, WV.debugMoving))
	local realClock = os.clock
	if PR.debugClock then
		H.inClient(p, PR.debugClock, realClock)
	end
	H.inClient(p, function()
		WV.clock = realClock
	end)
	H.inClient(p, PR.debugPerf)
	local seen = {} -- model -> { last x, y, moves, jumps = { ... }, frames }
	local frames = 0
	local wall0 = os.clock()
	local function note()
		for _, m in H.inClient(p, WV.debugMoving) do
			if m.walking then
				local x, y = H.inClient(p, PR.debugShown, m.model)
				if x then
					local r = seen[m.model]
					if r == nil then
						seen[m.model] = { x = x, y = y, moves = 0, jumps = {}, frames = 0 }
					else
						r.frames += 1
						if x ~= r.x or y ~= r.y then
							r.moves += 1
							table.insert(r.jumps, math.max(math.abs(x - r.x), math.abs(y - r.y)))
							r.x, r.y = x, y
						end
					end
				end
			end
		end
	end
	local tally = incTally(p, PR, 10)
	for f = 1, 180 do
		E.step(1 / 60)
		note()
		tally.step(f)
		frames += 1
		if f > 156 and f % 2 == 0 then
			capture(p, string.format("crowd_%03d", (f - 158) // 2))
		end
	end
	local wall = os.clock() - wall0
	local rates, jumps = {}, {}
	for _, r in seen do
		if r.frames >= 60 then
			table.insert(rates, r.moves / (r.frames / 60))
			for _, j in r.jumps do
				table.insert(jumps, j)
			end
		end
	end
	table.sort(rates)
	table.sort(jumps)
	local function at(t, q)
		if #t == 0 then
			return 0
		end
		return t[math.clamp(math.floor(#t * q) + 1, 1, #t)]
	end
	local st = H.inClient(p, PR.debugPerf)
	local wc = H.inClient(p, WV.debugCost)
	local fr = math.max(1, st.frames)
	log("crowd: %d driftlings, %d dressed; %d walkers followed a second or more: their pictures moved %.1f times a second (median), %.1f for the slowest tenth; jumps of %d art px (median), %d (the largest tenth), %d at most", #H.profile(p).pals, wc.dressed or 0, #rates, at(rates, 0.5), at(rates, 0.1), at(jumps, 0.5), at(jumps, 0.9), at(jumps, 1))
	log("crowd: the pixel filter %.2f ms a frame (the slowest %.1f), models %.2f; %d kept pictures, %d drawn; WorldView poses %.2f ms a frame; %d frames in %.1f s", st.stepMs / fr, st.maxMs or 0, st.dynMs / fr, st.hits, st.draws, (wc.pose or 0) * 1000 / math.max(1, wc.frames or 1), frames, wall)
	log("crowd: %s", tally.line())
	-- a driftling held just behind a shop (the report of 2026-11-18, "also, shadows clip through buildings": its blob
	-- shadow darkened the shop's awning in front of it): crowd_shadow, the log saying where
	local Street = H.sharedServer("Data.Street")
	local Buildings = H.sharedServer("Data.Buildings")
	local plot = H.session(p).plot
	local ox, oz = Street.origin(plot)
	local prof = H.profile(p)
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	local shop, best = nil, math.huge
	for _, q in prof.plot.placed do
		local b = Buildings.byId[q.id]
		if b and b.act == "shop" and root then
			local w, d = Plot.footprint(q.id, q.rot)
			local dist = (E.v3(ox + q.x + w / 2, root.Position.Y, oz + q.z + d / 2) - root.Position).Magnitude
			if dist < best then
				shop, best = q, dist
			end
		end
	end
	local pal = prof.pals[1]
	if shop and pal then
		local w = Plot.footprint(shop.id, shop.rot)
		local x, z = ox + shop.x + w / 2, oz + shop.z - 0.6
		H.inClient(p, WV.holdPal, plot, pal.id, 30, x, z)
		E.run(1.5)
		log("crowd: driftling %d (%s) held just behind the %s at (%.1f, %.1f), %.0f studs from the founder", pal.id, pal.sp, shop.id, x, z, best)
		capture(p, "crowd_shadow")
		if PR.debugShadowCheck then
			local sc = H.inClient(p, PR.debugShadowCheck)
			log("crowd: %d blob shadows on the frame: %d pixels of roofs, awnings and walls in their ellipses, %d of them darkened; %d ground pixels darkened", sc.shadows, sc.high, sc.darkened, sc.ground)
		end
	end
	return p
end

function SCEN.stress(legs: number?)
	local Tuning = H.sharedServer("Config.Tuning")
	local Creatures = H.sharedServer("Data.Creatures")
	local Plot = H.sharedServer("Logic.Plot")
	local top = #Tuning.TierCost
	local pals = {}
	for k = 1, Plot.housingLimit(top) do
		table.insert(pals, Creatures.list[(k - 1) % #Creatures.list + 1].id)
	end
	local t0 = os.clock()
	seedProfile(19, top, { fill = fillMax, pals = pals, shells = 9e9 })
	log("stress: seeded in %.1f s", os.clock() - t0)
	t0 = os.clock()
	local p = join(19, "Stress")
	settle(p, 120, 2)
	E.run(2)
	local prof = H.profile(p)
	local working = 0
	for _, x in prof.pals do
		if x.work ~= 0 then
			working += 1
		end
	end
	log("stress: joined and settled in %.1f s: tier %d, %d pieces placed in all, %d driftlings (%d at work)", os.clock() - t0, prof.tier, #prof.plot.placed, #prof.pals, working)
	capture(p, "stress_start")
	local PR = modOr(p, "Pixel.PixelRenderer")
	if PR == nil or PR.debugPerf == nil then
		return p
	end
	local Street = H.sharedServer("Data.Street")
	local ox = Street.origin(H.session(p).plot)
	-- (the world at 60 frames a second of its own time, however long a frame takes here: the moving things change as
	-- often as they would in the game. The renderer's budgets and timings read the real clock: PixelRenderer.debugClock)
	local realClock = os.clock
	local sim0 = E.simClock
	if PR.debugClock then
		H.inClient(p, PR.debugClock, realClock)
	end
	local WV0 = modOr(p, "Controllers.WorldView")
	if WV0 then
		H.inClient(p, function()
			WV0.clock = realClock
		end)
	end
	local dt = 1 / 60
	local speed = 16
	-- the route: north up the middle, across to the west, back south along the west side, across east
	local route = { { -2, 4 }, { -2, -180 }, { -26, -180 }, { -26, -30 }, { 24, -30 }, { 24, -120 } }
	local lastMarks = nil
	local function report(label, frames, wall)
		local st = H.inClient(p, PR.debugPerf)
		lastMarks = (st.markBy or "") .. string.format("; %d models left out of a compose (no picture to show: %s)", st.skips or 0, st.skipWhy or "")
		local f = math.max(1, st.frames)
		local pf = math.max(1, st.panFrames)
		log("stress %s: %d frames in %.1f s (%.1f ms a frame of everything); the pixel filter %.2f ms a frame, the slowest %.1f ms, %d over 25 ms; scroll %.2f ms a pan (cast %.2f), composes %.2f (copy %.2f, models %.2f, outlines %.2f, rims %.2f, effects %.2f, grading %.2f, uploads %.2f; %d uploads), water %.2f, wind %.2f; %d kept pictures used, %d models drawn; %d incremental composes (%d px each), %d whole",
			label, frames, wall, wall * 1000 / math.max(1, frames), st.stepMs / f, st.maxMs or 0, st.slow or 0, st.scrollMs / pf, st.castMs / pf, st.composeMs / f, st.copyMs / f, st.dynMs / f, st.outlineMs / f, st.rimMs / f, st.fxMs / f, st.gradeMs / f, st.uploadMs / f, st.uploads, st.waterMs / f, st.windMs / f, st.hits, st.draws, st.incFrames or 0, (st.incPx or 0) // math.max(1, st.incFrames or 0), st.fullFrames or 0)
	end
	local tally = incTally(p, PR, 20)
	local function scripts(label, frames)
		local ct = E.coTime or {}
		if lastMarks then
			log("stress %s tiles marked (all frames): %s", label, lastMarks)
		end
		local rows = {}
		for k, v in ct do
			table.insert(rows, { k = k, v = v })
		end
		table.sort(rows, function(a, b)
			return a.v > b.v
		end)
		local parts = {}
		for i = 1, math.min(14, #rows) do
			table.insert(parts, string.format("%s %.2f", (string.gsub(rows[i].k, "^.*%.", "")), rows[i].v * 1000 / math.max(1, frames)))
		end
		log("stress %s scripts (ms a frame): %s", label, table.concat(parts, "; "))
		local WV = modOr(p, "Controllers.WorldView")
		if WV and WV.debugCost then
			local c = H.inClient(p, WV.debugCost)
			local n = math.max(1, c.frames)
			log("stress %s world view (ms a frame): driftlings %.2f, poses %.2f, fires/chips/signs %.2f, building cards %.2f, eggs %.2f; %d models out, %d pooled", label, c.walk * 1000 / n, c.pose * 1000 / n, c.rest * 1000 / n, c.tags * 1000 / n, c.eggs * 1000 / n, c.dressed, c.pooled)
		end
	end
	H.inClient(p, PR.debugPerf)
	E.coTime = {}
	local wall0 = realClock()
	local frames = 0
	local segWall, segFrames = realClock(), 0
	local worstFrame, worstAt = 0, ""
	for leg = 1, math.min(#route - 1, legs or #route) do
		local a, b = route[leg], route[leg + 1]
		local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local n = math.max(1, math.floor(len / (speed * dt)))
		for i = 1, n do
			local u = i / n
			local qx, qz = a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u
			p.Character:PivotTo(E.cf.new(ox + qx, 3, qz))
			local f0 = realClock()
			E.step(dt)
			local ms = (realClock() - f0) * 1000
			if ms > worstFrame then
				worstFrame, worstAt = ms, string.format("leg %d at %.0f, %.0f", leg, qx, qz)
			end
			frames += 1
			segFrames += 1
			-- (the checks on one leg only: each composes the whole frame once more, which the timings would carry)
			if leg == 2 then
				tally.step(frames)
			end
		end
		report("leg " .. leg, segFrames, realClock() - segWall)
		scripts("leg " .. leg, segFrames)
		capture(p, string.format("stress_leg%d", leg))
		E.coTime = {}
		H.inClient(p, PR.debugPerf)
		segWall, segFrames = realClock(), 0
	end
	log("stress: the whole walk %d frames, its slowest whole frame %.1f ms (%s)", frames, worstFrame, worstAt)
	log("stress: %s", tally.line())
	local _ = wall0
	-- standing in the middle of it a few seconds
	E.coTime = {}
	H.inClient(p, PR.debugPerf)
	local st0 = realClock()
	for _ = 1, 180 do
		E.step(dt)
	end
	report("standing", 180, realClock() - st0)
	scripts("standing", 180)
	E.coTime = nil
	E.simClock = sim0
	if PR.debugClock then
		H.inClient(p, PR.debugClock, nil)
	end
	return p
end

function SCEN.pan()
	seedProfile(2, 1, { pieces = VILLAGE, pals = { "clawdle", "mossbun", "pebblit" } })
	local p = join(2, "Wren")
	settle(p, 30, 1)
	E.run(1)
	local PR = modOr(p, "Pixel.PixelRenderer")
	if PR == nil or PR.debugPerf == nil then
		return p
	end
	local function report(label, secs)
		local st = H.inClient(p, PR.debugPerf)
		local f = math.max(1, st.frames)
		local pf = math.max(1, st.panFrames)
		log("pan %s: the slowest frame %.1f ms, %d over 25 ms", label, st.maxMs or 0, st.slow or 0)
		log("pan %s: %d frames in %.1f s, %d panned; a frame %.2f ms; a pan's scroll %.2f ms (cast %.2f, ink %.2f); composes %.2f ms a frame (copy %.2f, models %.2f, outlines %.2f, rims %.2f, effects %.2f, grading %.2f); %d uploads, %d whole regrades; water %.2f ms and wind %.2f ms a frame; %d kept pictures used, %d models drawn; %d incremental composes (%d px each), %d whole", label, st.frames, secs, st.panFrames, st.stepMs / f, st.scrollMs / pf, st.castMs / pf, st.inkMs / pf, st.composeMs / f, st.copyMs / f, st.dynMs / f, st.outlineMs / f, st.rimMs / f, st.fxMs / f, st.gradeMs / f, st.uploads, st.regrades, st.waterMs / f, st.windMs / f, st.hits, st.draws, st.incFrames or 0, (st.incPx or 0) // math.max(1, st.incFrames or 0), st.fullFrames or 0)
		if st.byModel then
			log("pan %s by model: %s", label, st.byModel)
		end
		local c = st.cache
		if c then
			log("pan %s cache: %d strip pixels copied back, %d cast, %d saved, %d tiles kept (%d dropped, %d let go)", label, c.loaded, c.missed, c.saved, c.tiles, c.dropped, c.evicted)
		end
		if PR.debugGradeCheck then
			local g = H.inClient(p, PR.debugGradeCheck)
			log("pan %s grade check: %d of %d static pixels off, image %d off%s", label, g.off, g.checked, g.image, if g.recasting then " (a re-cast going)" else "")
		end
	end
	-- (on the real clock, 60 frames a second, so the renderer's own timings are real ones: as the ambient timing does)
	local realClock = os.clock
	local sim0 = E.simClock
	local off = E.SIM.lastClock - realClock() + 1
	E.simClock = function()
		local v = realClock() + off
		E.SIM.lastClock = v
		return v
	end
	local dt = 1 / 60
	H.inClient(p, PR.debugPerf)
	local tally = incTally(p, PR, 20)
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	local at = root and root.Position or E.v3(0, 3, 0)
	local speed = 16
	local shot = 0
	local wall0 = realClock()
	for i = 1, 240 do
		-- (round a square 12 studs a side: east, north, west, south, at walking speed)
		local d = (i * dt * speed) % 48
		local ox, oz
		if d < 12 then
			ox, oz = d, 0
		elseif d < 24 then
			ox, oz = 12, -(d - 12)
		elseif d < 36 then
			ox, oz = 12 - (d - 24), -12
		else
			ox, oz = 0, -12 + (d - 36)
		end
		p.Character:PivotTo(E.cf.new(at.X + ox, at.Y, at.Z + oz))
		E.step(dt)
		tally.step(i)
	end
	report("walking", realClock() - wall0)
	local function castCheck(label)
		if PR.debugWaterCheck then
			local w = H.inClient(p, PR.debugWaterCheck)
			log("pan %s water check: %d of %d water pixels show a tone not the frame's; the wind's paint on %d pixels", label, w.off, w.checked, w.wind or 0)
		end
		if PR.debugCastCheck then
			local c = H.inClient(p, PR.debugCastCheck)
			log("pan %s cast check: %d of %d static pixels differ from one whole cast (part %d, light %d, shade %d)", label, c.off, c.checked, c.ids, c.lits, c.shades)
		end
	end
	castCheck("walking")
	-- (the same loop again: the ground has been seen once, so a pan's strips can come back from the pan cache)
	H.inClient(p, PR.debugPerf)
	wall0 = realClock()
	for i = 241, 480 do
		local d = (i * dt * speed) % 48
		local ox, oz
		if d < 12 then
			ox, oz = d, 0
		elseif d < 24 then
			ox, oz = 12, -(d - 12)
		elseif d < 36 then
			ox, oz = 12 - (d - 24), -12
		else
			ox, oz = 0, -12 + (d - 36)
		end
		p.Character:PivotTo(E.cf.new(at.X + ox, at.Y, at.Z + oz))
		E.step(dt)
	end
	report("walking again", realClock() - wall0)
	castCheck("walking again")
	H.inClient(p, PR.debugPerf)
	wall0 = realClock()
	for i = 481, 720 do
		E.step(dt)
		tally.step(i)
	end
	report("standing", realClock() - wall0)
	castCheck("standing")
	log("pan: %s", tally.line())
	E.simClock = sim0
	if PR.debugKeepCheck then
		local kc = H.inClient(p, PR.debugKeepCheck)
		log("pan kept pictures: %d of %d pixels differ from drawing every model afresh (%d kept pictures used)", kc.off, kc.checked, kc.hits)
	end
	-- (a few frames of the walk to look at)
	for i = 1, 6 do
		local d = (i * 0.5 * speed) % 48
		p.Character:PivotTo(E.cf.new(at.X + math.min(d, 12), at.Y, at.Z - math.max(0, d - 12)))
		E.run(0.5)
		capture(p, string.format("pan_%03d", shot))
		shot += 1
	end
	return p
end

-- A founder standing about (the requests of 2026-11-15: "the players eyes look too big, can they be 2 vertical lines
-- instead? also, add more motion to the player, just like in the bakery game, like dozing off while afk"): up close
-- on a lawn far from the islands, in rows of four (CharacterModels.poseFounder at the moment each one shows): standing
-- with its line eyes, a look round, a toe tap and a yawn (idle_1); a scratch, a hum, rocking and a stretch (idle_2);
-- the doze halfway down a nod and at the bottom of one, a blink and the cheer (idle_3). Then the player's own founder
-- on its island through Controllers/AvatarView, as the game draws it: standing a while (the log lists the fidgets
-- each second), then left alone past Tuning.DozeSecs (AvatarView.debugAway), dozing with its Z's floating up
-- (idle_doze_000 .. 005, a frame every third of a second).
function SCEN.idle()
	seedProfile(2, 1, { pieces = VILLAGE, pals = { "clawdle", "mossbun", "pebblit" } })
	local p = join(2, "Wren")
	settle(p, 30, 1)
	local ctx = E.clientCtx(p)
	local CM = E.moduleIn(ctx, E.find("ReplicatedStorage.Shared.Models.CharacterModels"))
	local Blocks = E.moduleIn(ctx, E.find("ReplicatedStorage.Shared.Models.Blocks"))
	local PR = H.cmod(p, "Pixel.PixelRenderer")
	local CC = H.cmod(p, "Controllers.CameraController")
	local hidden = {}
	for _, g in p.PlayerGui:GetChildren() do
		if g:IsA("ScreenGui") and g.Name ~= "PixelLayer" and g.Name ~= "SkyBackdrop" and g.Name ~= "World" and g.Enabled then
			g.Enabled = false
			table.insert(hidden, g)
		end
	end
	local OX, OZ = 0, 9400
	local ux, uz = math.sqrt(0.5), -math.sqrt(0.5)
	local vx, vz = math.sqrt(0.5), math.sqrt(0.5)
	local faceViewer = math.atan2(vx, vz)
	H.inClient(p, function()
		local m = Blocks.model(E.workspace, "IdleLawn")
		Blocks.part(m, { size = E.v3(30, 1, 30), cf = E.cf.new(OX, -0.5, OZ), color = "grass" })
	end)
	-- the time a rig shows fidget `name` at progress u (FIDGET_SEC slots, picked by the slot and the seed)
	local function timeFor(rig, name, u)
		for slot = 2, 600 do
			local tt = slot * CM.FIDGET_SEC + u * CM.FIDGET_LEN
			local t = tt - (rig.seed % 11) * 0.6
			local got = CM.fidgetAt(rig, t, 999)
			if got == name then
				return t
			end
		end
		return nil
	end
	local rows = {
		{ { "stand" }, { "look", 0.3 }, { "tap", 0.5 }, { "yawn", 0.55 } },
		{ { "scratch", 0.5 }, { "hum", 0.5 }, { "rock", 0.4 }, { "stretch", 0.5 } },
		{ { "doze", 0.45 }, { "doze", 0.84 }, { "blink" }, { "cheer" } },
	}
	local looks = {
		{ skin = 1, hair = 2, style = 1, shirt = 1 }, { skin = 3, hair = 5, style = 6, shirt = 4 },
		{ skin = 2, hair = 1, style = 3, shirt = 7 }, { skin = 4, hair = 7, style = 9, shirt = 2 },
	}
	for row, list in rows do
		local things = {}
		H.inClient(p, function()
			for k, what in list do
				local rig = CM.buildStanding(looks[k], "Idle_" .. row .. "_" .. k, row * 10 + k)
				rig.model.Parent = E.workspace
				PR.registerDynamic(rig.model, if k == 1 then "self" else "player")
				local u = -5.4 + (k - 1) * 3.6
				table.insert(things, { rig = rig, what = what, x = OX + ux * u, z = OZ + uz * u })
			end
			local pts = {}
			for _, q in { { -7.4, -1.6 }, { 7.4, -1.6 }, { -7.4, 1.6 }, { 7.4, 1.6 } } do
				for _, y in { 0, 5.2 } do
					table.insert(pts, OX + ux * q[1] + vx * q[2])
					table.insert(pts, y)
					table.insert(pts, OZ + uz * q[1] + vz * q[2])
				end
			end
			CC.setStage({ name = "idle" .. row, origin = E.v3(OX, 0, OZ), pts = pts, tight = nil, top = 12, bottom = 8 })
		end)
		local names = {}
		local function pose()
			for _, x in things do
				local base = E.cf.new(x.x, 0, x.z) * E.cf.Angles(0, faceViewer + math.rad(25), 0)
				local kind, u = x.what[1], x.what[2]
				if kind == "stand" then
					-- (a moment with the eyes open and no fidget)
					local t = 0.05
					while CM.blinking(x.rig.seed, t) or CM.fidgetAt(x.rig, t, 999) ~= nil do
						t += 0.37
					end
					CM.poseFounder(x.rig, base, t, 0, 999, false, false, 0)
				elseif kind == "blink" then
					local t = 0.05
					while not CM.blinking(x.rig.seed, t) or CM.fidgetAt(x.rig, t, 999) ~= nil do
						t += 0.01
					end
					CM.poseFounder(x.rig, base, t, 0, 999, false, false, 0)
				elseif kind == "doze" then
					local t = CM.NOD_SEC * (10 + u) - (x.rig.seed % 5) * 0.4
					CM.poseFounder(x.rig, base, t, 0, 999, true, false, 0)
				elseif kind == "cheer" then
					CM.poseAction(x.rig, base, 0.6, 0, "cheer")
				else
					local t = timeFor(x.rig, kind, u)
					if t then
						CM.poseFounder(x.rig, base, t, 0, 999, false, false, 0)
					end
				end
			end
		end
		H.inClient(p, pose)
		settle(p, 60, 0.5)
		H.inClient(p, pose)
		for _, x in things do
			table.insert(names, x.what[1] .. (if x.what[2] then string.format("@%.2f", x.what[2]) else ""))
		end
		log("idle row %d: %s", row, table.concat(names, ", "))
		E.step(E.dt)
		capture(p, string.format("idle_%d", row))
		H.inClient(p, function()
			for _, x in things do
				PR.unregisterDynamic(x.rig.model)
				x.rig.model:Destroy()
			end
		end)
	end
	-- the own founder on its island, as the game draws it
	for _, g in hidden do
		g.Enabled = true
	end
	H.inClient(p, function()
		CC.setStage(nil)
	end)
	settle(p, 30, 1)
	local AV = modOr(p, "Controllers.AvatarView")
	if AV then
		local seen = {}
		for _ = 1, 14 do
			E.run(1)
			local st = H.inClient(p, function()
				return AV.debugIdle(p)
			end)
			table.insert(seen, string.format("%.0fs:%s", st.idle, st.fidget or "-"))
		end
		log("idle: standing %s", table.concat(seen, " "))
		H.inClient(p, function()
			AV.debugAway(60)
		end)
		E.run(2)
		for k = 0, 5 do
			local st = H.inClient(p, function()
				return AV.debugIdle(p)
			end)
			log("idle doze %d: dozing %s, %d Z's in the air", k, tostring(st.dozing), st.zeds)
			capture(p, string.format("idle_doze_%03d", k))
			E.run(1 / 3)
		end
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
	seedProfile(2, 3, { pieces = AMBIENT, pals = { "clawdle", "mossbun", "pebblit", "gullfin" }, shells = 65000 })
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
		log("ambient %s: birds [%s]; %d decos (%d drawn), %d perches, %d smoke spots (%d wisps), %d leafy crowns (%d leaves), %d glints, butterflies drawn %d, fireflies %d",
			label, table.concat(parts, ", "), st.decos, st.drawnDecos, st.perches, st.puffs, st.wisps, st.canopies, st.leaves, st.glints, st.drawnButterflies, st.fireflies)
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
		table.insert(seen, string.format("%03d: glints %d butterflies %d leaves %d decos %d", k, st.drawnGlints, st.drawnButterflies, st.leaves, st.drawnDecos))
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
		seedProfile(10 + tier, tier, { pieces = if tier == 3 then HARBOR else VILLAGE, pals = PALS, shells = 65000 })
		local p = join(10 + tier, "Isle" .. tier)
		settle(p)
		E.run(2.5)
		capture(p, label)
		return p
	end
end
SCEN.island2 = islandScenario(2, "island2")
SCEN.island3 = islandScenario(3, "island3")

-- "zoom=<n>": the harbour island (island3's) with the Settings panel's View slider on notch n (the request of
-- 2026-11-18: "make a view slider for zooming the camera in and out, with 10 notches"), set as a drag to it would
-- (SettingsUI.setZoom) and the island baked again at that scale. Frames zoom<n>_panel (the panel open on it) and
-- zoom<n>.
local function zoomScenario(n: number)
	seedProfile(13, 3, { pieces = HARBOR, pals = PALS, shells = 65000 })
	local p = join(13, "Isle3")
	settle(p)
	E.run(1)
	H.openPanel(p, "settings")
	E.run(0.4)
	local SU = modOr(p, "UI.SettingsUI")
	if SU then
		H.inClient(p, SU.setZoom, n)
	end
	E.run(0.8)
	settle(p, 60, 1)
	E.run(1)
	local CC = modOr(p, "Controllers.CameraController")
	log("zoom: notch %s, saved %s", tostring(CC and H.inClient(p, CC.zoom)), tostring(H.profile(p).settings.zoom))
	capture(p, string.format("zoom%d_panel", n))
	H.closePanel(p)
	E.run(0.5)
	settle(p, 20, 0.5)
	E.run(1)
	capture(p, string.format("zoom%d", n))
	return p
end

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
	seedProfile(17, 6, { pieces = pieces, shells = 960000 })
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
	seedProfile(16, 6, { pieces = cityPieces(), pals = CITY_PALS, shells = 960000})
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

-- "everdrift": the biggest island (Everdrift, the top tier: the request of 2026-11-14, "allow expansion up to level
-- 20 ... add decor, huts, work buildings") built up along its whole length: the work buildings, huts and decor of the
-- tiers past Driftling Haven in rows with a few of the city's between them, street lamps along the middle. Frames
-- everdrift_1 (the south shore, the tree and the plaza) .. everdrift_5 (the far north tip), the founder walking north.
function SCEN.everdrift()
	local Buildings = H.sharedServer("Data.Buildings")
	local Tuning = H.sharedServer("Config.Tuning")
	local top = #Tuning.TierCost
	local NEW: { string } = {}
	for _, d in Buildings.list do
		if d.tier > 10 and d.tier <= top and d.kind ~= "path" and d.kind ~= "fence" then
			table.insert(NEW, d.id)
		end
	end
	local OLD = { "hotel", "palace", "skygarden", "grandmill", "beacon", "bazaar", "townhall", "rainbowarch", "crystalspire", "bigoak" }
	local pieces = {}
	local k = 0
	for z = -192, -6, 9 do
		for _, x in { -27, -18, -9, 2, 11, 21 } do
			k += 1
			local id = if k % 4 == 0 then OLD[(k // 4 - 1) % #OLD + 1] else NEW[(k - 1 - k // 4) % #NEW + 1]
			table.insert(pieces, { id, x, z })
		end
		table.insert(pieces, { "streetlamp", -3, z + 4 })
	end
	local PALS = { "clawdle", "gullfin", "mossbun", "pebblit", "frondle", "emberpup", "twiggle", "snowpuff", "conchy", "bloomoth", "glowbat", "breezle", "relicrab", "cloudbun", "hopsprout", "murkle" }
	seedProfile(18, top, { pieces = pieces, pals = PALS, shells = 9e8 })
	local p = join(18, "Everdrift")
	settle(p)
	E.run(2.5)
	local prof = H.profile(p)
	log("everdrift: tier %d (%s), %d pieces, %d driftlings", prof.tier, H.sharedServer("Data.Office").plan(prof.tier).name, #prof.plot.placed, #prof.pals)
	local Street = H.sharedServer("Data.Street")
	local ox = Street.origin(H.session(p).plot)
	for i, z in { 4, -45, -95, -145, -190 } do
		if p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
			p.Character:PivotTo(E.cf.new(ox - 2, 3, z))
			E.run(2)
			settle(p, 30, 1)
		end
		E.run(1.5)
		-- (the incremental compose's base in step with the frame after each jump's re-bake: none off)
		local PR = modOr(p, "Pixel.PixelRenderer")
		if PR and PR.debugBaseCheck then
			local bc = H.inClient(p, PR.debugBaseCheck)
			log("everdrift %d: the frame against its base, %d pixels off%s", i, bc.n, if bc.rows ~= "" then " (rows " .. string.sub(bc.rows, 1, 200) .. ")" else "")
		end
		capture(p, "everdrift_" .. i)
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
	-- (panel=store:<tab> / looks:<tab>: the Store on a tab, the My founder screen on a tab: skin, style, bangs, hair, eyes,
	-- shirt, top, apron, hat, face, neck, back, hand, outfits or titles; GAME_DESIGN 14)
	local arg = nil
	local base, sub = string.match(name, "^(%w+):(%w+)$")
	if base then
		name, arg = base, sub
	end
	if name == "hatch" then
		local pieces = table.clone(HARBOR)
		table.insert(pieces, { "hatchery", 4, -18 })
		seedProfile(20, 3, { pieces = pieces, pals = { "clawdle", "gullfin", "shellback", "frostling", "mossbun" }, egg = { "glacior", 4, { "swift2" } }, shells = 9000, seen = { "glacior" } })
	else
		-- (panel=welcome: away nine hours and twenty minutes, the welcome-back card with its offline earnings)
		seedProfile(20, 2, { pieces = VILLAGE, pals = { "clawdle", "gullfin", "mossbun", "emberpup", "shellback", "conchy" }, seen = { "pebblit", "frondle", "twiggle", "magmole" }, away = if name == "welcome" then 9 * 3600 + 1200 else nil })
	end
	-- (the harness's test ids sell at their suggested prices, as the Creator Dashboard would set them: before the join,
	-- so the HUD's offers read them too)
	local M = H.sharedServer("Config.Monetization")
	if M and M.SuggestedRobux then
		E.cloud.prices = E.cloud.prices or {}
		for _, group in { M.GamePasses, M.DevProducts } do
			for key, id in group do
				if M.SuggestedRobux[key] then
					E.cloud.prices[id] = M.SuggestedRobux[key]
				end
			end
		end
	end
	local p = join(20, "Menus")
	settle(p)
	if name == "tree" then
		-- (two eggs in the bag over the tree's lot: GAME_DESIGN 14)
		local TreeB = H.sharedServer("Logic.Tree")
		if TreeB then
			TreeB.bagAdd(H.profile(p), 6)
			TreeB.bagAdd(H.profile(p), 4)
		end
		H.push(p, 0.3)
	end
	if name == "store" or name == "looks" then
		-- a player some way in: pieces owned (one of each slot worn), titles earned, three eggs in the bag, the pass
		-- track at level 6 with level 1 claimed, VIP owned with today's gift waiting (a view first: the server starts
		-- the track's season, Logic/Store.sync, so the points set below stay)
		H.push(p, 0.3)
		local prof = H.profile(p)
		for _, id in { "strawhat", "flowercrown", "tricorn", "sunglasses", "heartshades", "lei", "pearls", "backpack", "butterflywings", "ukulele", "lantern", "sailor", "flowershirt" } do
			prof.owned[id] = true
		end
		prof.founder.hat, prof.founder.face, prof.founder.neck = "flowercrown", "sunglasses", "lei"
		prof.founder.back, prof.founder.hand, prof.founder.top = "butterflywings", "ukulele", "sailor"
		for _, id in { "settler", "islander", "eggfinder", "luckyfind", "collector" } do
			prof.titles[id] = true
		end
		prof.title = "islander"
		local TreeL = H.sharedServer("Logic.Tree")
		if TreeL then
			TreeL.bagAdd(prof, 5)
			TreeL.bagAdd(prof, 3)
			TreeL.bagAdd(prof, 2)
		end
		local StoreL = H.sharedServer("Logic.Store")
		if StoreL then
			local xp = 0
			for L = 1, 6 do
				xp += StoreL.levelCost(L)
			end
			prof.track.xp = xp + 40
			prof.track.got = { 1 }
		end
		prof.passes.VIP = true
		prof.vipDay = -1
		prof.gifts.vip = true
		prof.shells = 250000
		if name == "looks" then
			-- the My founder screen (UI/FounderUI): a few of the bakery's pieces owned too, a gold beret over twin tails
			-- with side bangs and a white streak, odd eyes, a candy stripe apron in sky blue, the wand held tipped
			-- forward, and three saved outfits
			for _, id in { "magic_wand", "golden_crown", "angel_wings", "pearl_necklace", "bouquet" } do
				if H.sharedServer("Data.Cosmetics").byId[id] then
					prof.owned[id] = true
				end
			end
			local LooksD = H.sharedServer("Data.Looks")
			local f = prof.founder
			f.style, f.bangs, f.hair2, f.eye, f.eye2 = 7, 3, 9, 6, 4
			f.hat, f.hatTint = "beret", 5
			f.face, f.neck = "glasses", nil
			f.apron, f.apronTint = 10, 8
			f.hand, f.turn = "magic_wand", 2
			prof.outfits = {
				LooksD.encode({ skin = 2, hair = 3, style = 2, shirt = 4, hat = "flowercrown", back = "butterflywings" }),
				LooksD.encode({ skin = 4, hair = 2, style = 12, shirt = 8, hat = "toque", apron = 2 }),
				LooksD.encode({ skin = 3, hair = 4, style = 6, shirt = 6, face = "sunglasses", neck = "lei", top = "sailor" }),
			}
		end
		H.push(p, 0.6)
	end
	if name == "rewards" then
		-- (panel=rewards[:<tab>]: a player on day 4 of a streak with today's reward waiting and day 7's gift ahead,
		-- twelve minutes in today (two gifts for playing taken, the third waiting), today's tasks with one done and one
		-- claimed, two spins, 12 kinds with the first Index gift taken, the Lucky Hour running; GAME_DESIGN 15)
		H.push(p, 0.3)
		local prof = H.profile(p)
		local now = H.smod("WorldClock").now()
		local today = math.floor(now / 86400)
		local rw = prof.rewards
		rw.daily.last, rw.daily.streak, rw.daily.best = today - 1, 3, 5
		rw.daily.miles = { 3 }
		rw.play.day, rw.play.secs, rw.play.got = today, 12 * 60 + 20, { 1, 2 }
		rw.tasks.day = -1
		local RewardsL = H.sharedServer("Logic.Rewards")
		RewardsL.sync(prof, now)
		if rw.tasks.list[1] then
			rw.tasks.list[1].at -= rw.tasks.list[1].n
			rw.tasks.got[1] = true
		end
		if rw.tasks.list[2] then
			rw.tasks.list[2].at -= rw.tasks.list[2].n
		end
		rw.spin.day, rw.spin.extra = today - 1, 1
		rw.index.got = { 5 }
		for _, sp in { "pebblit", "frondle", "twiggle", "magmole", "clawdle", "gullfin", "mossbun", "emberpup", "shellback", "conchy", "frostling", "glacior" } do
			prof.seen[sp] = 2
		end
		prof.boosts.luck = 14 * 60 + 5
		H.push(p, 0.6)
	end
	if name == "top" then
		-- (panel=top[:<tab>]: the boards with fourteen other islands on them and this player 6th on Coins, 9th on Charm
		-- and outside the Hatched board's rows; three friends invited, one of today's rewards taken, two friends on the
		-- server: GAME_DESIGN 16)
		local DataS = H.smod("DataService")
		local prof = H.profile(p)
		local others = {
			{ 9101, "MossyTern", 4.2e6, 980, 812 }, { 9102, "pebble_kat", 2.9e6, 1210, 640 }, { 9103, "Lumen_Rook", 1.8e6, 760, 905 },
			{ 9104, "sunnyfern22", 960000, 1405, 377 }, { 9105, "TidalBramble", 612000, 690, 512 }, { 9106, "quill_and_kip", 240000, 540, 298 },
			{ 9107, "OwlMarrow", 188000, 430, 260 }, { 9108, "ziggy_pond", 97000, 512, 181 }, { 9109, "Hollowmint", 64000, 300, 150 },
			{ 9110, "brisk_lark", 41000, 260, 133 }, { 9111, "CopperDune", 22500, 210, 96 }, { 9112, "fen_and_fig", 9800, 150, 71 },
			{ 9113, "marlowe_b", 4300, 90, 44 }, { 9114, "PipTheBold", 1200, 40, 20 },
		}
		E.cloud.names = E.cloud.names or {}
		for _, o in others do
			E.cloud.names[o[1]] = o[2]
		end
		prof.stats.earned = 400000
		prof.stats.taken, prof.stats.hatched = 3, 2
		-- (the writes yield on the store, as in the game: in the server's context)
		-- (the Driftlings board: each island's best driftling, a kind of a rarity with some mutation stars, written as
		-- Logic/Social writes it)
		local SocialL = H.sharedServer("Logic.Social")
		local CreaturesD = H.sharedServer("Data.Creatures")
		local TuningD = H.sharedServer("Config.Tuning")
		local kinds: { [number]: { string } } = {}
		for _, c in CreaturesD.list do
			kinds[c.rarity] = kinds[c.rarity] or {}
			table.insert(kinds[c.rarity], c.id)
		end
		local best = { { 9, 3 }, { 7, 8 }, { 8, 0 }, { 6, 5 }, { 5, 9 }, { 5, 4 }, { 4, 7 }, { 4, 2 }, { 3, 6 }, { 3, 1 }, { 2, 4 }, { 2, 0 }, { 1, 3 }, { 1, 0 } }
		local function palValue(i: number): number
			local r, stars = best[i][1], best[i][2]
			local list = kinds[r] or kinds[1]
			local sp = list[(i - 1) % #list + 1]
			return (TuningD.BoardRarityPoints[r] + stars * TuningD.BoardStarPoints) * SocialL.KIND_CODES + SocialL.kindCode(sp)
		end
		E.call(E.serverCtx, 15, function()
			for i, o in others do
				DataS.writeBoards(o[1], { coins = o[3], charm = o[4], hatched = o[5], driftlings = palValue(i) }, {})
			end
			DataS.writeBoards(p.UserId, { coins = 400000, charm = 455, hatched = 5, driftlings = SocialL.score(prof, "driftlings") }, {})
		end)
		-- (today by the game's clock: the fake engine's, not this script's)
		prof.social.invited, prof.social.refDay, prof.social.refToday = 3, math.floor(E.now() / 86400), 1
		prof.social.here = 2
		H.push(p, 0.4)
	end
	local UIKit = modOr(p, "UI.UIKit")
	if UIKit and UIKit.openPanel then
		if name == "store" or name == "looks" or name == "rewards" or name == "top" then
			H.openPanel(p, name, arg)
			if name == "top" then
				-- (the board's answer and the sheet built again with it)
				E.run(1.2)
			end
		elseif name == "work" then
			-- the work picker for the first driftling (Work on its card): every workplace with its speed there
			H.openPanel(p, "pals", { pal = H.profile(p).pals[1].id })
		elseif name == "paltip" then
			-- a driftling's tip over the Driftlings panel (the request of 2026-11-15: "when hovering or holding onto each
			-- creature, show what their mutation and stats do"): the first one with a flaw and two mutations, one of
			-- them for the whole island; the tip where a pointer over its row would put it
			local prof = H.profile(p)
			prof.pals[1].muts = { "bright2", "grower3", "lazy" }
			H.push(p, 0.3)
			H.openPanel(p, "pals")
			E.run(0.3)
			local PT = modOr(p, "UI.PalTip")
			if PT then
				H.inClient(p, function()
					PT.show(prof.pals[1], E.v2(150, 70), false)
				end)
				local st = H.inClient(p, PT.debugState)
				log("paltip: %s", table.concat(st.texts, " | "))
			end
		elseif name == "pal" then
			-- one driftling's details (the request of 2026-11-14, "allow players to click on creatures to open up a
			-- menu seeing their details"), opened as a player would, by a tap on it where it stands on the island
			-- (Controllers/WorldView's pick); four mutations, a weather's among them
			local prof = H.profile(p)
			local x = prof.pals[1]
			x.muts = { "crown6", "busy2", "rainy2", "lazy" }
			H.push(p, 0.6)
			local WV = modOr(p, "Controllers.WorldView")
			local s = H.session(p)
			local how = "opened directly"
			if WV and WV.palScreen then
				H.inClient(p, WV.holdPal, s.plot, x.id, 8)
				E.run(0.3)
				local pos = H.inClient(p, WV.palScreen, s.plot, x.id)
				if pos then
					H.inClient(p, WV.tapScreen, pos)
					E.run(0.1)
					if H.currentPanel(p) == "pal" then
						how = string.format("a tap at %d,%d", pos.X, pos.Y)
					end
				end
			end
			if H.currentPanel(p) ~= "pal" then
				H.openPanel(p, "pal", { id = x.id })
			end
			log("panel pal: %s (%s)", x.sp, how)
		else
			H.openPanel(p, name)
		end
		E.run(0.8)
		if name == "looks" then
			-- (the stage's eight angles and the tab's thumbnails drawn: Pixel/Snapshot's pictures, a few a frame)
			E.run(3)
		end
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
	capture(p, "panel_" .. name .. (if arg then "_" .. arg else ""))
	if name == "hatch" and UIKit and UIKit.openPanel then
		-- the parent picker (the request of 2026-11-19: "for hatchery, make a search function, and a sort by mutation
		-- rarity or creature rarity"): the rarest kind first (panel_hatch_picker), then the rarest mutations first with a
		-- search typed in (panel_hatch_search)
		local prof = H.profile(p)
		local slot = nil
		for _, q in prof.plot.placed do
			if q.id == "hatchery" and q.uid ~= (prof.eggs[1] and prof.eggs[1].uid or -1) then
				slot = q.uid
			end
		end
		if slot then
			H.clickNamed(p, "Slot_a_" .. slot, { wait = 0.4 })
			E.run(0.4)
			capture(p, "panel_hatch_picker")
			H.clickNamed(p, "Sort_muts", { wait = 0.3 })
			local box = p.PlayerGui:FindFirstChild("PalSearch", true)
			local tb = if box then box:FindFirstChild("Box") else nil
			if tb then
				H.inClient(p, function()
					(tb :: any).Text = "Gull"
				end)
			end
			E.run(0.4)
			capture(p, "panel_hatch_search")
		end
	end
	if name == "pal" and UIKit and UIKit.openPanel then
		-- a neighbour's driftling, only to look at: what its island's Pals attribute says
		H.openPanel(p, "pal", { id = 9, plot = 99, sp = "gullfin", muts = { "trader2", "rainy3" }, work = "patch", home = "nest", isle = "Bo's Isle" })
		E.run(0.8)
		capture(p, "panel_pal_visit")
	end
	return p
end

-- The Hatcheries' tags (the request of 2026-11-20: "the hatchery should have the timer above its building, and show
-- ready! once the egg is ready. clicking it while ready shows the hatching screen just like hatching an egg normally,
-- but with the resultant creature"): a harbour island with two, a rare egg warming in one (its timer) and an uncommon
-- one ready in the other (Ready!), the founder by them (hatchery); then a tap on Ready! and the hatch scene starting
-- (hatchery_tap), and the scene a few taps on (hatchery_scene).
function SCEN.hatchery()
	local pieces = table.clone(HARBOR)
	table.insert(pieces, { "hatchery", 4, -18 })
	seedProfile(20, 3, { pieces = pieces, pals = { "clawdle", "gullfin", "shellback", "frostling", "mossbun" }, egg = { "glacior", 4, { "swift2" } }, egg2 = { "gullfin", 0, { "bright2" } }, shells = 9000, seen = { "glacior" } })
	local p = join(20, "Hatch")
	settle(p)
	local s = H.session(p)
	local Street = H.sharedServer("Data.Street")
	local ox, oz = Street.origin(s.plot)
	if p.Character then
		p.Character:PivotTo(E.cf.new(ox + 2, 3, oz - 8))
		E.run(2)
		settle(p, 30, 1)
	end
	E.run(1)
	capture(p, "hatchery")
	local BT = modOr(p, "Controllers.BuildingTags")
	local tags = if BT then H.inClient(p, BT.debugHatch) else {}
	for _, t in tags do
		log("hatchery tag %d: %s%s", t.uid, t.words, if t.shown then "" else " (off the screen)")
	end
	for _, t in tags do
		if t.ready then
			H.clickNamed(p, "HatchTap_" .. t.uid, { wait = 0.1 })
			break
		end
	end
	E.run(1.2)
	capture(p, "hatchery_tap")
	local HS = modOr(p, "UI.HatchScene")
	if HS then
		for _ = 1, 6 do
			H.inClient(p, HS.skip)
			E.run(0.5)
		end
	end
	capture(p, "hatchery_scene")
	return p
end

-- "treeink": the Tree of Life's edges pixel by pixel (the request of 2026-11-20: "the tree has alot of jaggied
-- outlines, and stray pixels around the outline, especially near the fruits"). The village's tree at the default
-- zoom (treeink=<n>: on the View slider's notch n; treeink=<n>,<tier>: on an island of that tier, the tree at its
-- stage), held at midday, then every pixel round it printed (TREEPX rows: colour, the
-- part's name, its depth, its id) for tools/preview/tree_ink.py.
local function treeModelOf(p)
	local s = H.session(p)
	local plots = E.workspace:FindFirstChild("Plots")
	local pm = plots and plots:FindFirstChild("Plot_" .. tostring(s and s.plot))
	if pm == nil then
		return nil
	end
	for _, d in pm:GetDescendants() do
		if d:IsA("Model") and string.find(d.Name, ":tree:", 1, true) then
			return d
		end
	end
	return nil
end

function SCEN.treeink(zoomTo: number?, tier: number?, turn: number?)
	seedProfile(21, tier or 2, { pieces = VILLAGE, pals = { "clawdle", "mossbun", "gullfin" }, shells = 2000, eggs = { 1, 6, 3, 4, 5, 7, 8, 9 } })
	local p = join(21, "Grove")
	settle(p)
	-- (in daylight, as the island is seen most: the night's low contrast hid the outline's shades)
	local DLt = modOr(p, "Controllers.DayLight")
	if DLt and DLt.debugSky then
		H.inClient(p, DLt.debugSky, 0.45)
		E.run(0.5)
	end
	local s = H.session(p)
	local Street = H.sharedServer("Data.Street")
	local Tree = H.sharedServer("Logic.Tree")
	local Plot = H.sharedServer("Logic.Plot")
	local prof = H.profile(p)
	local ox, oz = Street.origin(s.plot)
	local q = Tree.piece(prof)
	-- (turned on its lot, as a player can turn it in Build mode)
	if q and turn and turn ~= 0 then
		for i, pq in prof.plot.placed do
			if pq == q then
				local res = H.req(p, "plot.move", { i = i, x = q.x, z = q.z, rot = turn })
				log("treeink: the tree turned %d: %s", turn, tostring(res and (res.ok or res.err)))
			end
		end
		settle(p, 30, 1)
		q = Tree.piece(prof)
	end
	if q and p.Character then
		local _, d = Plot.footprint(q.id, q.rot)
		p.Character:PivotTo(E.cf.new(ox + q.x - 1, 3, oz + q.z + d + 2))
		E.run(2)
		settle(p, 30, 1)
	end

	local SU = modOr(p, "UI.SettingsUI")
	if zoomTo and SU then
		H.inClient(p, SU.setZoom, zoomTo)
		E.run(1)
		settle(p, 30, 1)
	end
	capture(p, "treeink")
	local PR = modOr(p, "Pixel.PixelRenderer")
	local m = treeModelOf(p)
	if PR == nil or m == nil or PR.debugStaticIds == nil then
		log("treeink: no renderer or no tree")
		return
	end
	local fr, ids, isInk = H.inClient(p, PR.debugStaticIds, m)
	if fr == nil then
		log("treeink: no picture")
		return
	end
	local W, Hh = fr.W, fr.H
	local x0, y0, x1, y1 = W, Hh, -1, -1
	for i = 0, W * Hh - 1 do
		if ids[buffer.readu16(fr.id, i * 2)] then
			local x, y = i % W, i // W
			x0, y0, x1, y1 = math.min(x0, x), math.min(y0, y), math.max(x1, x), math.max(y1, y)
		end
	end
	if x1 < 0 then
		log("treeink: the tree is not in the picture")
		return
	end
	x0, y0, x1, y1 = math.max(0, x0 - 3), math.max(0, y0 - 3), math.min(W - 1, x1 + 3), math.min(Hh - 1, y1 + 3)
	local names, nameIx = {}, {}
	local function ixOf(id)
		local part = ids[id]
		if part == nil then
			return 0
		end
		local nm = part.Name
		if nameIx[nm] == nil then
			table.insert(names, nm)
			nameIx[nm] = #names
		end
		return nameIx[nm]
	end
	print(string.format("TREEBOX %d %d %d %d", x0, y0, x1, y1))
	for y = y0, y1 do
		local row = table.create(x1 - x0 + 1)
		for x = x0, x1 do
			local i = y * W + x
			local c = buffer.readu32(fr.color, i * 4) % 16777216
			local id = buffer.readu16(fr.id, i * 2)
			local dpt = math.clamp(math.floor(buffer.readf32(fr.depth, i * 4) * 8 + 0.5), 0, 65535)
			local full = buffer.readu32(fr.color, i * 4)
			table.insert(row, string.format("%06x%02x%04x%04x%01x", c, ixOf(id), dpt, id, if isInk(full) then 1 else 0))
		end
		print("TREEPX " .. y .. " " .. table.concat(row, ""))
	end
	print("TREENAMES " .. table.concat(names, ","))
	-- the check: the glowing marks (runes, glyphs) and motes within 2 px of an outline (another part's ink, or a pixel
	-- well behind them), and the bits of the tree standing apart from the rest of it (8-connected groups of its pixels
	-- under 40): 249 and 2 on this tree before the request of 2026-11-20 was seen to, 1 and 0 after
	local function partAt(i: number): BasePart?
		return ids[buffer.readu16(fr.id, i * 2)]
	end
	local edges, loose, treePx = 0, 0, 0
	local seen: { [number]: boolean } = {}
	for i = 0, W * Hh - 1 do
		local part = partAt(i)
		if part then
			treePx += 1
			local x, y = i % W, i // W
			local nm = part.Name
			if nm == "Rune" or nm == "Glyph" or nm == "Mote" then
				local dep = buffer.readf32(fr.depth, i * 4)
				local id0 = buffer.readu16(fr.id, i * 2)
				local hit = false
				for yy = math.max(0, y - 2), math.min(Hh - 1, y + 2) do
					for xx = math.max(0, x - 2), math.min(W - 1, x + 2) do
						local j = yy * W + xx
						if buffer.readf32(fr.depth, j * 4) > dep + 0.75 or (buffer.readu16(fr.id, j * 2) ~= id0 and isInk(buffer.readu32(fr.color, j * 4))) then
							hit = true
						end
					end
				end
				if hit then
					edges += 1
				end
			end
			if not seen[i] then
				local stack, n = { i }, 0
				seen[i] = true
				while #stack > 0 do
					local k = table.remove(stack) :: number
					n += 1
					local kx, ky = k % W, k // W
					for dy = -1, 1 do
						for dx = -1, 1 do
							local nx, ny = kx + dx, ky + dy
							if (dx ~= 0 or dy ~= 0) and nx >= 0 and ny >= 0 and nx < W and ny < Hh then
								local j = ny * W + nx
								if not seen[j] and partAt(j) then
									seen[j] = true
									table.insert(stack, j)
								end
							end
						end
					end
				end
				if n < 40 then
					loose += 1
				end
			end
		end
	end
	log("treeink: %d of the tree's pixels, %d mark pixels at an outline, %d loose bits", treePx, edges, loose)
	if treePx < 2000 or edges > 6 or loose > 0 then
		table.insert(E.warnings, { ctx = "preview", text = string.format("TREEINK: %d of the tree's pixels, %d mark pixels at an outline, %d loose bits", treePx, edges, loose), t = 0, phase = "treeink" })
	end
end

-- The Tree of Life and its eggs (GAME_DESIGN 6): a village's tree with its lot of eggs round its roots (a common, a
-- rare, an epic, a legendary, a mythic, a celestial, an ancient and an eternal one, so each rarity's shell and lights show), their prices over them, the founder in front of it (tree); a new lot rising out of the lawn,
-- the old one sinking (tree_lay); one hatched by its price tag, cracking, its driftling stepping out (tree_hatch); the
-- glowing eggs at night (tree_night).
function SCEN.tree()
	seedProfile(21, 2, { pieces = VILLAGE, pals = { "clawdle", "mossbun", "gullfin" }, shells = 2000, eggs = { 1, 6, 3, 4, 5, 7, 8, 9 } })
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

-- The weather (GAME_DESIGN 13): the tree's village in one weather ("weather=rain", "snow", "storm", "fog", "blossom",
-- "leaves", "haze", "breezy", "sunny"). The sea's clock jumps to a spell of it, so the HUD's status lines (the season
-- and the weather with their time left) and the islands agree; WeatherView holds it at full strength (its streaks,
-- flakes, petals, leaves, motes or fog banks in the pixel layer, its light on the picture); two of the eggs under the
-- tree were laid in it and touched (their beads in its colour) when it touches eggs. weather=storm also catches a
-- flash of lightning (weather_storm_flash); "weathers" runs each in turn.
local function weatherScenario(kind: string)
	local WD = H.sharedServer("Data.Weather")
	local WL = H.sharedServer("Logic.Weather")
	local def = WD.byId[kind]
	if def == nil then
		error("no weather " .. kind)
	end
	local WC = H.smod("WorldClock")
	-- the first spell of it ahead on the sea's clock (the seeded eggs keep that spell's season)
	local start, season = nil, "spring"
	for k = 0, 2000 do
		local t = WC.now() + k * H.sharedServer("Config.Tuning").WeatherSecs
		local st = WL.at(t)
		if st.kind == kind then
			start = H.sharedServer("Config.Tuning").WeatherEpoch + st.spell * H.sharedServer("Config.Tuning").WeatherSecs
			season = st.season
			break
		end
	end
	local touch = if def.family then { kind, season, { 2, 2 }, { 4, 3 } } else nil
	seedProfile(22, 2, { pieces = VILLAGE, pals = { "clawdle", "mossbun", "gullfin" }, shells = 2000, eggs = { 1, 3, 2, 4, 1, 2 }, touch = touch })
	local p = join(22, "Rainy")
	if start then
		WC.shift(math.max(0, start + 20 - WC.now()))
	end
	local s = H.session(p)
	local Street = H.sharedServer("Data.Street")
	local Tree = H.sharedServer("Logic.Tree")
	local Plot = H.sharedServer("Logic.Plot")
	local prof = H.profile(p)
	local ox, oz = Street.origin(s.plot)
	local q = Tree.piece(prof)
	if q and p.Character then
		local _, d = Plot.footprint(q.id, q.rot)
		p.Character:PivotTo(E.cf.new(ox + q.x - 1, 3, oz + q.z + d + 2))
	end
	E.run(1)
	settle(p, 30, 1)
	local WV = modOr(p, "Controllers.WeatherView")
	if WV then
		H.inClient(p, WV.debugSet, kind)
	end
	-- (the banner and the notice for the jump go by; the snow and the petals fill the screen)
	E.run(5.5)
	settle(p, 10, 0.5)
	if WV then
		local st = H.inClient(p, WV.debugState)
		log("weather %s: season %s, strength %.2f, drops %d, flakes %d, fog %d, lines %d", st.kind, st.season, st.strength, st.drops, st.flakes, st.fog, st.lines)
	end
	local chip = modOr(p, "UI.WeatherChip")
	if chip then
		local cs = H.inClient(p, chip.debugState)
		log("status lines: %s", tostring(cs.text))
	end
	capture(p, "weather_" .. kind)
	if kind == "fog" then
		-- (the clouds a few seconds on: drifted downwind)
		E.run(6)
		settle(p, 10, 0.5)
		capture(p, "weather_fog_later")
	end
	if kind == "storm" and WV then
		H.inClient(p, WV.debugFlash, 1)
		E.run(0.2)
		settle(p, 2, 0.1)
		capture(p, "weather_storm_flash")
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

-- The founder on their island's east rim with the neighbour's island floating off in the sky (the request of
-- 2026-11-20: "make it a floating island instead, with a 2d skybox"), the view at its farthest notch; then the same
-- pan baked from scratch, to compare a scrolled picture with a fresh one.
function SCEN.sky()
	local p = join(50, "Walker")
	seedProfile(51, 2, { pieces = VILLAGE, pals = PALS})
	join(51, "Neighbour", { client = false })
	settle(p)
	local Street = H.sharedServer("Data.Street")
	local x1, z1 = Street.origin(1)
	local b = Street.plot(1)
	local SU = modOr(p, "UI.SettingsUI")
	if SU then
		H.inClient(p, SU.setZoom, 1)
	end
	walkTo(p, x1 + b.x1 - 2, z1 + Street.CENTER.z)
	E.run(0.5)
	settle(p, 10, 0.5)
	capture(p, "sky")
	local PR = modOr(p, "Pixel.PixelRenderer")
	if PR and PR.isActive() then
		H.inClient(p, function()
			PR.rebake()
		end)
		settle(p, 40, 1)
		capture(p, "sky_fresh")
	end
	return p
end

-- The sky's day (the request of 2026-11-20: "polish the skybox more. it should be of the same quality as the ones in
-- the egg hatching screen, with day and night cycles with moon and sun rising"): a first island at the widest View
-- notch, the sky held at each hour in turn (sky_<hour name>), the other two days' variations (sky_<hour>_v2, _v3), then
-- the moon in three more phases and the sky in rain,
-- storm, snow and fog. The log gives each frame's SkyBackdrop state (the notch, the stars, where the sun and moon are)
-- and how long the shapes and a notch take to paint.
function SCEN.skies()
	local p = join(1, "Pixel")
	settle(p)
	local SU = modOr(p, "UI.SettingsUI")
	if SU then
		H.inClient(p, SU.setZoom, 1)
	end
	E.run(1)
	settle(p, 20, 1)
	local SB = modOr(p, "UI.SkyBackdrop")
	local WV = modOr(p, "Controllers.WeatherView")
	if SB == nil then
		log("skies: no SkyBackdrop")
		return p
	end
	local function shot(name, h, night, kind)
		if WV then
			H.inClient(p, WV.debugSet, kind)
		end
		H.inClient(p, SB.debugHour, h, night or 0)
		E.run(0.4)
		settle(p, 6, 0.3)
		local d = H.inClient(p, SB.debugState)
		log("skies %s: hour %.3f, %s, notch %s, stars %.2f, sun %s at %d,%d, moon %s at %d,%d, %d twinkles, %d birds, painted %d, shapes %d", name, d.hour, d.kind, d.key, d.stars, tostring(d.sun), d.sunX, d.sunY, tostring(d.moon), d.moonX, d.moonY, d.twinkles, d.birds, d.paints, d.geos)
		capture(p, "sky_" .. name)
	end
	for _, s in { { "night", 0.02 }, { "firstlight", 0.2 }, { "sunrise", 0.235 }, { "morning", 0.29 }, { "noon", 0.5 }, { "afternoon", 0.7 }, { "sunset", 0.765 }, { "dusk", 0.81 }, { "midnight", 0.95 } } do
		shot(s[1], s[2], 0, "sunny")
	end
	-- (the other two days' variations: their dawn, sunset and night)
	shot("sunrise_v2", 0.24, 1, "sunny")
	shot("sunset_v2", 0.765, 1, "sunny")
	shot("night_v2", 0.95, 1, "sunny")
	shot("sunrise_v3", 0.24, 2, "sunny")
	shot("sunset_v3", 0.765, 2, "sunny")
	shot("night_v3", 0.95, 2, "sunny")
	shot("moon_half", 0.95, 2, "sunny")
	shot("moon_crescent", 0.95, 3, "sunny")
	shot("moon_waxing", 0.95, 5, "sunny")
	shot("rain_noon", 0.5, 0, "rain")
	shot("storm_dusk", 0.81, 0, "storm")
	shot("snow_morning", 0.3, 0, "snow")
	shot("fog_night", 0.02, 0, "fog")
	-- what a new notch and new shapes cost, timed in the client (os.clock)
	local realClock = os.clock
	local ms = H.inClient(p, function()
		local a, b = SB.debugTimes(640, 360, realClock)
		return { a, b }
	end)
	log("skies at 640x360: the shapes %.1f ms, a notch %.1f ms (spread over a few frames)", ms[1], ms[2])
	if WV then
		H.inClient(p, WV.debugSet, nil)
	end
	H.inClient(p, SB.debugHour, nil)
	return p
end

-- Visit: the HUD's Visit button, the list of the other islands (visit_list), then Visit on the neighbour's: the
-- founder there while its driftlings work (visit), Home showing.
function SCEN.visit()
	local p = join(52, "Visitor")
	seedProfile(53, 1, { pieces = VILLAGE, pals = { "frondle", "gullfin" } })
	join(53, "Host", { client = false })
	settle(p)
	E.run(1)
	if H.clickNamed(p, "Visit", { optional = true }) then
		E.run(0.5)
		capture(p, "visit_list")
		H.clickNamed(p, "Visit_2", { optional = true })
		E.run(1)
	else
		log("visit: no Visit button")
	end
	settle(p, 30, 1)
	capture(p, "visit")
	return p
end

-- Build mode: the tray (Wood tab), a piece picked with its ghost on a cell where it fits (cyan), then on the plaza
-- (red), then a tip under way (the tray on its tab, its building pulsing, the tip over the tray), then the Huts tab with
-- the island at its huts' limit (build_huts: "No room", 4/4), then a hut picked up and Replace (the bigger huts with
-- their prices).
function SCEN.build()
	seedProfile(54, 1, { pieces = { { "patch", 6, 5 }, { "nest", -8, 1 }, { "nest", -7, 11 }, { "flowers", 5, 13 } }, pals = { "mossbun" }, shells = 3300 })
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
		-- (the camp's rect was cast again where it landed: its shadow's edges against one whole cast, which refines
		-- every edge; the report of 2026-11-18, "some shadows still appear stepped like this")
		if PR.debugCastCheck then
			local c = H.inClient(p, PR.debugCastCheck)
			log("build cast check: %d of %d static pixels differ from one whole cast (part %d, light %d, shade %d)", c.off, c.checked, c.ids, c.lits, c.shades)
			-- (a rect cast again on its own, as when a part comes or goes: one building part hidden, its rect and its shadow's
			-- re-cast, then the same check)
			local st0 = H.inClient(p, PR.debugStatic)
			local plotM = E.workspace:FindFirstChild("Plots") and E.workspace.Plots:FindFirstChild("Plot_" .. tostring(H.session(p).plot))
			local hid = 0
			if plotM then
				local best, bestV = nil, 0
				for _, d in plotM:GetDescendants() do
					if d:IsA("BasePart") and d.Transparency < 0.5 and d.Size.Y > 1 and d.Size.Y < 6 and d.Size.X * d.Size.Z > bestV and d.Size.X * d.Size.Z < 40 and d.Position.Y > Street.LAWN_Y + 1 then
						best, bestV = d, d.Size.X * d.Size.Z
					end
				end
				if best then
					H.inClient(p, PR.hideStatic, best)
					hid = 1
				end
			end
			settle(p, 10, 0.5)
			local st1 = H.inClient(p, PR.debugStatic)
			local c2 = H.inClient(p, PR.debugCastCheck)
			log("build re-cast check (%d part hidden, %d re-casts, %d bakes): %d of %d static pixels differ from one whole cast (part %d, light %d, shade %d)", hid, st1.recasts - st0.recasts, st1.bakes - st0.bakes, c2.off, c2.checked, c2.ids, c2.lits, c2.shades)
		end
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
		-- the hut's tip done in Build mode, the tips moving on to hatching: Build mode closes itself and an arrow points
		-- at the Tree of Life ("auto close the build tab when going to the hatching step and point towards the tree of
		-- life for the player to click")
		H.clickNamed(p, "BuildDone", { optional = true, wait = 0.3 })
		prof.tut = 3
		H.push(p, 0.4)
		H.clickNamed(p, "Menu_build", { optional = true, wait = 0.5 })
		prof.tut = 4
		H.push(p, 0.4)
		settle(p, 10, 1.4)
		capture(p, "tip_tree")
		-- the housing limit: two more huts make four, all the room a tier 1 island has (Tuning.HousingLimit: 8)
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

-- "drop": a big building put down in Build mode, watched frame by frame (the report of 2026-11-20: "when a building is
-- placed, it seems to shift right instead of shifting down. also, they seem to vanish for awhile before appearing,
-- especially for bigger buildings"). An orchard (4 by 4) by the founder: each frame logs where the falling stand-in is
-- drawn (layer px), whether the server's model is in the island, the re-casts waiting, and how many of the building's
-- pixels differ from the frame before it was put down; frames drop_0 (just after) to drop_6 and drop_done.
-- "dropdrag": the same, the view dragged away fast (Build mode's drag, CameraController.panBy) from the frame after the
-- tap for 12 frames (the report of 2026-11-20: "putting down a building/anything leaves a clone of it that lingers awhile
-- if you drag away while doing it"); frames dropdrag_0 .. and dropdrag_done.
local function dropScenario(drag: boolean)
	local tag = if drag then "dropdrag" else "drop"
	seedProfile(58, 2, { pieces = { { "nest", -8, 1 } }, pals = { "mossbun" }, shells = 250000 })
	local p = join(58, "Dropper")
	settle(p, 30, 1)
	local BuildUI = modOr(p, "UI.BuildUI")
	local PR = modOr(p, "Pixel.PixelRenderer")
	local BuildFx = modOr(p, "Controllers.BuildFx")
	local CC = modOr(p, "Controllers.CameraController")
	local Street = H.sharedServer("Data.Street")
	local Plot = H.sharedServer("Logic.Plot")
	local prof = H.profile(p)
	local plot = H.session(p).plot
	local ox, oz = Street.origin(plot)
	H.clickNamed(p, "Menu_build", { optional = true, wait = 0.5 })
	settle(p, 10, 0.5)
	if BuildUI == nil or PR == nil or BuildFx == nil then
		return p
	end
	local id = "orchard"
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	local fx = if root then root.Position.X - ox else 0
	local fz = if root then root.Position.Z - oz else 0
	local bx, bz, best = nil, nil, math.huge
	for z = math.floor(fz) - 12, math.floor(fz) + 12 do
		for x = math.floor(fx) - 12, math.floor(fx) + 12 do
			local dd = (x + 2 - fx) ^ 2 + (z + 2 - fz - 4) ^ 2
			if dd < best and Plot.fits(prof.tier, prof.plot.placed, id, x, z, 0) then
				bx, bz, best = x, z, dd
			end
		end
	end
	if bx == nil then
		log("drop: no room for an orchard")
		return p
	end
	-- the building's box on the layer: its footprint's corners from the grass to 6 studs up
	local st0 = H.inClient(p, PR.debugStatic)
	local W, H0 = st0.W, st0.H
	local K = st0.K
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, c in { { 0, 0 }, { 4, 0 }, { 0, 4 }, { 4, 4 } } do
		for _, up in { 0, 6 } do
			local sp = H.inClient(p, PR.project, E.v3(ox + bx + c[1], Street.LAWN_Y + up, oz + bz + c[2]))
			x0, y0 = math.min(x0, sp.X / K), math.min(y0, sp.Y / K)
			x1, y1 = math.max(x1, sp.X / K), math.max(y1, sp.Y / K)
		end
	end
	x0, y0 = math.max(0, math.floor(x0)), math.max(0, math.floor(y0))
	x1, y1 = math.min(W - 1, math.ceil(x1)), math.min(H0 - 1, math.ceil(y1))
	local function snap()
		local st = H.inClient(p, PR.debugStatic)
		local b = st.color
		local out = {}
		if b then
			for y = y0, y1 do
				for x = x0, x1 do
					out[#out + 1] = buffer.readu32(b, (y * st.W + x) * 4)
				end
			end
		end
		return out, st
	end
	local base = snap()
	local function differs()
		local now, st = snap()
		local n = 0
		for i, c in now do
			if c ~= base[i] then
				n += 1
			end
		end
		return n, st
	end
	log("drop: an orchard at %d,%d (founder at %.1f,%.1f), its box on the layer %d,%d - %d,%d (%d px)", bx, bz, fx, fz, x0, y0, x1, y1, (x1 - x0 + 1) * (y1 - y0 + 1))
	H.inClient(p, function()
		BuildUI.pick(id, 0)
		local pos = PR.project(E.v3(ox + bx + 2, Street.LAWN_Y, oz + bz + 2))
		BuildUI.tapScreen(E.v2(pos.X, pos.Y - E.inset), false)
	end)
	E.run(0.1)
	-- (the piece stays picked for another copy, the pointer still over the spot: no ghost there while it drops in)
	H.inClient(p, BuildUI.confirm)
	local dynF = E.workspace:FindFirstChild("PixelDynamic")
	local plots = E.workspace:FindFirstChild("Plots")
	local plotM = plots and plots:FindFirstChild("Plot_" .. plot)
	local decor = plotM and plotM:FindFirstChild("Static") and plotM.Static:FindFirstChild("Decor")
	local caps = { [1] = tag .. "_0", [3] = tag .. "_1", [5] = tag .. "_2", [6] = tag .. "_3", [7] = tag .. "_4", [8] = tag .. "_5", [12] = tag .. "_6" }
	if drag then
		caps = { [1] = "dropdrag_0", [4] = "dropdrag_1", [8] = "dropdrag_2", [12] = "dropdrag_3", [16] = "dropdrag_4", [22] = "dropdrag_5", [30] = "dropdrag_6", [45] = "dropdrag_7", [60] = "dropdrag_8" }
	end
	for f = 1, 60 do
		-- (the view dragged away fast: 60 screen px left and 24 up a frame for 12 frames, past what the picture scrolls in
		-- a frame, so it catches up over the frames after)
		if drag and CC and f >= 2 and f <= 13 then
			H.inClient(p, CC.panBy, -60, -24)
		end
		E.step(E.dt)
		local stand = dynF and dynF:FindFirstChild("DropIn")
		local sx, sy = nil, nil
		local px, py = nil, nil
		if stand then
			sx, sy = H.inClient(p, PR.debugShown, stand)
			local sp = H.inClient(p, PR.project, stand:GetPivot().Position)
			px, py = sp.X / K, sp.Y / K
		end
		local real = false
		if decor then
			for _, c in decor:GetChildren() do
				if string.find(c.Name, ":" .. id .. ":", 1, true) then
					real = true
				end
			end
		end
		local n, st = differs()
		if drag and stand then
			-- (where the server's model stands on the layer now, against where the stand-in was drawn)
			local rp = H.inClient(p, PR.project, E.v3(ox + bx + 2, Street.LAWN_Y, oz + bz + 2))
			log("dropdrag frame %d: the spot at %.1f,%.1f on the layer; casting %s", f, rp.X / K, rp.Y / K, tostring(real and decor and H.inClient(p, function()
				for _, c in decor:GetChildren() do
					if string.find(c.Name, ":" .. id .. ":", 1, true) then
						return PR.casting(c)
					end
				end
				return nil
			end)))
		end
		log("drop frame %d: showing %d, stand-in %s drawn at %s,%s pivot at %s,%s; real model %s; ghost %s; re-casts waiting %d; %d of the box's px differ", f, H.inClient(p, BuildFx.showing), tostring(stand ~= nil), tostring(sx), tostring(sy), if px then string.format("%.1f", px) else "-", if py then string.format("%.1f", py) else "-", tostring(real), tostring(dynF ~= nil and dynF:FindFirstChild("Ghost") ~= nil), st.queued, n)
		if caps[f] then
			capture(p, caps[f])
		end
	end
	settle(p, 10, 0.5)
	capture(p, tag .. "_done")
	return p
end

function SCEN.drop()
	return dropScenario(false)
end

function SCEN.dropdrag()
	return dropScenario(true)
end

-- "buildui": the build catalog (GAME_DESIGN 4: "Polish the build ui more, just like the bakery game, and reference
-- bloxburg"): the Decor tab on its Garden row with a card's tooltip (buildui_decor), the search box finding every
-- lantern (buildui_search), a picket fence drawn round a box
-- (its markers: buildui_fence), a stream dug in two rows (buildui_river), a plank bridge dropping in over it with its
-- dust (buildui_drop), and the island after (buildui_done).
function SCEN.buildui()
	seedProfile(57, 3, { pieces = VILLAGE, pals = { "mossbun" }, shells = 250000 })
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

-- "inventory": Build mode's inventory (GAME_DESIGN 4.5, the request of 2026-11-14: "add an inventory system to build
-- mode ... a button to remove all buildings, remove all path/water etc, and a tool to quick remove buildings and
-- paths"): the Inventory tab with the pieces put away and how many, Remove all buildings asking for its second tap
-- (inventory_tab); Sell on, each card showing its share of the price (inventory_sell); the Nature tab's Trees with a
-- card saying Free for the oaks waiting (inventory_free); Quick remove on, a box dragged over paths with its orange
-- markers (inventory_quick).
function SCEN.inventory()
	local inv = { lumber = 1, nest = 2, oak = 3, lantern = 1, dirtpath = 30, picket = 12, bench = 2, umbrella = 1, gnome = 4 }
	seedProfile(59, 3, { pieces = VILLAGE, pals = { "mossbun" }, shells = 250000, inv = inv })
	local p = join(59, "Keeper")
	settle(p, 30, 1)
	local BuildUI = modOr(p, "UI.BuildUI")
	local Street = H.sharedServer("Data.Street")
	local Plot = H.sharedServer("Logic.Plot")
	local prof = H.profile(p)
	local ox, oz = Street.origin(H.session(p).plot)
	-- (paths in a box of grass near the plaza, laid from the inventory, and the founder beside them: Build mode's view
	-- starts on them)
	local r = Street.plot(prof.tier)
	local best, bx, bz = math.huge, nil, nil
	for z = r.z0 - r.z0 % 2, r.z1, 2 do
		for x = r.x0 - r.x0 % 2, r.x1, 2 do
			local dist = (x + 3 - 2) ^ 2 + (z + 2 - 6) ^ 2
			if dist < best then
				local ok = true
				for dz = 0, 4, 2 do
					for dx = 0, 6, 2 do
						ok = ok and Plot.fits(prof.tier, prof.plot.placed, "stream", x + dx, z + dz, 0)
					end
				end
				if ok then
					best, bx, bz = dist, x, z
				end
			end
		end
	end
	if bx and bz then
		local cells = {}
		for dz = 0, 4, 2 do
			for dx = 0, 6, 2 do
				table.insert(cells, { bx + dx, bz + dz })
			end
		end
		H.req(p, "plot.paint", { id = "dirtpath", cells = Plot.cellString(cells) })
		if p.Character then
			p.Character:PivotTo(E.cf.new(ox + bx + 4, 3, oz + bz + 6))
		end
		E.run(1)
		settle(p, 20, 0.5)
	end
	H.clickNamed(p, "Menu_build", { optional = true, wait = 0.5 })
	H.clickNamed(p, "Tab_inv", { optional = true, wait = 0.3 })
	H.clickNamed(p, "Clear_pieces", { optional = true, wait = 0.3 })
	settle(p, 10, 0.5)
	capture(p, "inventory_tab")
	-- (Remove all left waiting: it goes back by itself)
	E.run(4.5)
	H.clickNamed(p, "InvSell", { optional = true, wait = 0.3 })
	capture(p, "inventory_sell")
	H.clickNamed(p, "InvSell", { optional = true, wait = 0.3 })
	H.clickNamed(p, "Tab_nature", { optional = true, wait = 0.3 })
	H.clickNamed(p, "Chip_trees", { optional = true, wait = 0.3 })
	capture(p, "inventory_free")
	if BuildUI and bx and bz then
		H.clickNamed(p, "QuickRemove", { optional = true, wait = 0.3 })
		H.inClient(p, function()
			BuildUI.debugDraw({ { bx + 2, bz }, { bx + 6, bz + 4 } }, "box", true)
		end)
		settle(p, 10, 0.4)
		capture(p, "inventory_quick")
	end
	return p
end

-- "paths": drawing paths in Build mode (GAME_DESIGN 4): a box being dragged (its markers: cyan where a tile goes,
-- red where one can't), then the tiles laid (paths_box), then a hut and a farm standing on them (paths_built).
function SCEN.paths()
	seedProfile(58, 2, { pieces = VILLAGE, shells = 1100000 })
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
	-- a hut and a farm on the paving (the request of 2026-11-14: "make it such that paths can be put below buildings,
	-- and buildings can be put on to paths"): paths_built
	local hut = H.req(p, "plot.place", { id = "nest", x = c0[1] + 1, z = c0[2] + 1, rot = 0 })
	local farm = H.req(p, "plot.place", { id = "patch", x = c0[1] + 5, z = c0[2] + 1, rot = 0 })
	log("paths: a hut on the paving %s, a farm %s", tostring(hut and hut.ok), tostring(farm and farm.ok))
	settle(p, 10, 0.5)
	capture(p, "paths_built")
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
		if g:IsA("ScreenGui") and g.Name ~= "PixelLayer" and g.Name ~= "SkyBackdrop" then
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

-- "expand": the island grows from the build tray (GAME_DESIGN 4) behind the loading card (the request of 2026-11-20:
-- "make a transition for expansion, hiding the game with a loading transition"). Frames expand_before, the bank of
-- cloud bringing the card in (expand_cover_00 .., every 0.1 s), the card up (expand_card), the bank taking it away
-- (expand_open_00 ..), expand_after; then Build mode still following the founder as they walk on a few studs
-- (build_walk), then an expansion straight from the server with a hatch over the re-bake (expand_hatch ..). The log
-- says when the card covered the screen, when the server was asked, when it went and when the cheer came.
function SCEN.expand()
	seedProfile(56, 1, { pieces = VILLAGE, shells = 1100000 })
	local p = join(56, "Grower")
	settle(p, 30, 1)
	local PS = H.smod("PlotService")
	local PR = modOr(p, "Pixel.PixelRenderer")
	local CC = modOr(p, "Controllers.CameraController")
	local EV = modOr(p, "Controllers.EggView")
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
	local eggs0 = EV and EV.count(1) or 0
	-- Expand behind the loading card (the request of 2026-11-20: "make a transition for expansion, hiding the game
	-- with a loading transition"): the bank of cloud brings the card in, the server is asked under it, the card holds
	-- until the new land is drawn, then the bank takes it away and the cheer comes. Frames expand_cover_00 .. as it
	-- comes (every 0.1 s), expand_card once it covers the screen, expand_open_00 .. as it goes.
	local LCm = nil
	do
		local ctx = E.clientCtx(p)
		local inst = E.find("ReplicatedFirst.Loading.LoadingCard")
		local e = ctx and inst and ctx.modules[inst]
		LCm = e and e.value
	end
	local function cardSt()
		return if LCm then H.inClient(p, LCm.state) else nil
	end
	local tier0 = H.profile(p).tier
	local t0 = E.now()
	H.clickNamed(p, "Expand", { optional = true, wait = 0 })
	local shots, openShots, carded = 0, 0, false
	local coveredAt, tierAt, openAt, goneAt, cheerAt = -1, -1, -1, -1, -1
	local lastShot = -1
	local n = 0
	while n < 3000 do
		E.step(E.dt)
		n += 1
		local now = E.now() - t0
		local st = cardSt()
		if tierAt < 0 and H.profile(p).tier > tier0 then
			tierAt = now
		end
		if st and st.up then
			if st.cover == "closing" and now - lastShot >= 0.1 and shots < 10 then
				capture(p, string.format("expand_cover_%02d", shots))
				shots += 1
				lastShot = now
			elseif st.cover == "held" then
				if coveredAt < 0 then
					coveredAt = now
				end
				-- (what the filter still has to do while the card is up, twice a second)
				if now - lastShot >= 0.5 then
					lastShot = now
					local ds = PR.debugStatic()
					log("expand: %.2f s, card up: busy %s, baking %s, queued %d, bakes %d, recasts %d", now, tostring(H.inClient(p, PR.busy)), tostring(ds.baking), ds.queued or 0, ds.bakes, ds.recasts)
				end
				if not carded and now - coveredAt > 0.3 then
					carded = true
					capture(p, "expand_card")
					log("expand: the card up, status %q, bar %.2f, painted %s, K %d, size %dx%d", tostring(st.status), st.bar, tostring(st.painted), st.K, st.size.X, st.size.Y)
				end
			elseif st.cover == "opening" then
				if openAt < 0 then
					openAt = now
					lastShot = -1
				end
				if now - lastShot >= 0.1 and openShots < 10 then
					capture(p, string.format("expand_open_%02d", openShots))
					openShots += 1
					lastShot = now
				end
			end
		elseif goneAt < 0 and n > 2 then
			goneAt = now
		end
		if cheerAt < 0 then
			for _, d in p.PlayerGui:GetDescendants() do
				if d:IsA("TextLabel") and string.find(d.Text, "Your island grew", 1, true) then
					cheerAt = now
				end
			end
		end
		if cheerAt >= 0 and goneAt >= 0 then
			break
		end
	end
	local _, _, swaps = PS.debugNext(1)
	log("expand: tier %d -> %d, swaps %d; covered at %.2f s, the server asked under it (tier at %.2f s), the bank took it at %.2f s, gone at %.2f s, the cheer at %.2f s; bakes %d -> %d, %d re-casts, composed %d times", tier0, H.profile(p).tier, swaps, coveredAt, tierAt, openAt, goneAt, cheerAt, bakes0, PR.debugStatic().bakes, PR.debugStatic().recasts, PR.debugStatic().ticks - ticks0)
	settle(p, 10, 1.5)
	log("expand: eggs drawn %d before, %d after", eggs0, EV and EV.count(1) or -1)
	capture(p, "expand_after")
	-- Build mode keeps following the founder as they walk (lowered a little for the tray)
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if root and CC then
		local x0, z0 = root.Position.X, root.Position.Z
		local px0, py0 = CC.pan()
		for k = 1, 24 do
			p.Character:PivotTo(E.cf.new(x0 + k * 0.35, 3, z0 + k * 0.25))
			E.run(0.06)
		end
		settle(p, 6, 1)
		local px1, py1 = CC.pan()
		local dx, dy = CC.buildDrag()
		log("build: the founder walked %.1f studs; the view moved from (%d, %d) to (%d, %d); still free %s, drag %d %d", math.sqrt((24 * 0.35) ^ 2 + (24 * 0.25) ^ 2), px0, py0, px1, py1, tostring(CC.isFree()), dx, dy)
		capture(p, "build_walk")
	end
	-- the report of 2026-11-18: "a glitch happens when expanding and then immediately hatching somthing after, which
	-- causes the filter to be disabled". Expand again and open a hatch while the bigger island still bakes behind
	-- the picture: the island's picture must come back the moment the scene ends (kept while the scene had the view,
	-- the bake going on behind it), then the island grows as before (expand_hatch with the scene up, expand_hatch_back
	-- two frames after it ends, expand_hatch_grown once it has grown)
	local HS = modOr(p, "UI.HatchScene")
	local g3 = 0
	while not select(2, PS.debugNext(1)) and g3 < 400 do
		g3 += 1
		E.step(E.dt)
	end
	local tier0b = H.profile(p).tier
	-- (straight to the server, as the tray did before the loading card covered it: what the filter does with a bake
	-- cut short by a scene)
	H.req(p, "island.expand", {})
	local k = 0
	while k < 600 and not PR.debugStatic().baking do
		E.step(E.dt)
		k += 1
	end
	local st0 = PR.debugStatic()
	log("expand+hatch: tier %d -> %d; the re-bake under way %s (behind the picture %s) %d frames after Expand", tier0b, H.profile(p).tier, tostring(st0.baking), tostring(st0.behind), k)
	if HS then
		H.inClient(p, function()
			HS.play({ sp = "mossbun", muts = {}, r = 1, hr = 1, new = false }, nil)
		end)
		E.run(0.6)
		capture(p, "expand_hatch")
		local taps = 0
		while taps < 80 and H.inClient(p, HS.isOpen) do
			H.inClient(p, HS.skip)
			E.run(0.25)
			taps += 1
		end
		local layer = p.PlayerGui:FindFirstChild("PixelLayer")
		local im = layer and layer:FindFirstChild("Image")
		local function pic()
			local st = PR.debugStatic()
			return string.format("baking %s behind %s shown %s image %s/%.2f", tostring(st.baking), tostring(st.behind), tostring(st.shown), tostring(im and im.Visible), im and im.ImageTransparency or -1)
		end
		log("expand+hatch: the scene closed after %d taps (open %s): %s", taps, tostring(H.inClient(p, HS.isOpen)), pic())
		E.step(E.dt)
		E.step(E.dt)
		log("expand+hatch: two frames on: %s", pic())
		capture(p, "expand_hatch_back")
		local blank, f = 0, 0
		while f < 3000 and PR.debugStatic().baking do
			local st = PR.debugStatic()
			if st.baking and not st.behind then
				blank += 1
			end
			E.step(E.dt)
			f += 1
		end
		log("expand+hatch: baked after %d frames, %d of them with no island picture behind the bake: %s", f, blank, pic())
		settle(p, 6, 1)
		capture(p, "expand_hatch_grown")
	end
	return p
end

-- "expandperf=<tier>": what an expansion costs (the request of 2026-11-19: "Expansion is very slow and laggy,
-- especially at higher levels. Is it possible to optimize and speed it up? No need for the transition anymore"): an
-- island at that tier filled the way the stress test fills one, its next island built ahead; Expand clicked, then
-- frame by frame on the real clock (60 frames a second of the world's own time) until the bigger island's picture is
-- up and the island is quiet: the frames and seconds that took, the slowest frames, the land's parts before and after,
-- every script's share. Frames expandperf_before and expandperf_after.
local function expandPerf(tier: number)
	local Tuning = H.sharedServer("Config.Tuning")
	local Creatures = H.sharedServer("Data.Creatures")
	local Plot = H.sharedServer("Logic.Plot")
	local pals = {}
	for k = 1, math.min(Plot.housingLimit(tier), 60) do
		table.insert(pals, Creatures.list[(k - 1) % #Creatures.list + 1].id)
	end
	seedProfile(58, tier, { fill = fillMax, pals = pals, shells = 9e9 })
	local p = join(58, "Grower")
	settle(p, 120, 2)
	E.run(2)
	local PS = H.smod("PlotService")
	local PR = modOr(p, "Pixel.PixelRenderer")
	local guard = 0
	while not select(2, PS.debugNext(1)) and guard < 4000 do
		guard += 1
		E.step(E.dt)
	end
	local function landParts(): number
		local plots = E.workspace:FindFirstChild("Plots")
		local pm = plots and plots:FindFirstChild("Plot_1")
		local st = pm and pm:FindFirstChild("Static")
		local land = st and st:FindFirstChild("Land")
		local n = 0
		if land then
			for _, d in land:GetDescendants() do
				if d:IsA("BasePart") then
					n += 1
				end
			end
		end
		return n
	end
	local prof = H.profile(p)
	log("expandperf: tier %d, %d pieces, %d driftlings, %d land parts; the next island built ahead after %d frames", prof.tier, #prof.plot.placed, #prof.pals, landParts(), guard)
	H.clickNamed(p, "Menu_build", { optional = true, wait = 0.5 })
	settle(p, 20, 1)
	capture(p, "expandperf_before")
	-- the real clock from here (PixelRenderer.debugClock: its budgets and timings)
	local realClock = os.clock
	local sim0 = E.simClock
	if PR and PR.debugClock then
		H.inClient(p, PR.debugClock, realClock)
	end
	local WV0 = modOr(p, "Controllers.WorldView")
	if WV0 then
		H.inClient(p, function()
			WV0.clock = realClock
		end)
	end
	local dt = 1 / 60
	-- frames on the real clock: their times, the scripts' shares and the pixel filter's
	local function run(label: string, maxFrames: number, stop: ((f: number) -> boolean)?, first: (() -> ())?): number
		if PR then
			H.inClient(p, PR.debugPerf)
		end
		E.coTime = {}
		local rs = E.raycastStats
		local builds0, buildMs0 = rs and rs.builds or 0, rs and rs.buildMs or 0
		local ms: { number } = {}
		local w0 = realClock()
		local f = 0
		while f < maxFrames do
			local f0 = realClock()
			if f == 0 and first then
				local p0, b0, bm0 = realClock(), rs and rs.builds or 0, rs and rs.buildMs or 0
				first() -- (the press itself counts in the first frame: the server's swap answers it at once here)
				log("expandperf %s: the press (the server's answer, run at once here) %.0f ms; the simulator's raycast index %d rebuilds %.0f ms in it", label, (realClock() - p0) * 1000, (rs and rs.builds or 0) - b0, (rs and rs.buildMs or 0) - bm0)
			end
			local rb0, rbMs0 = rs and rs.builds or 0, rs and rs.buildMs or 0
			local co0 = table.clone(E.coTime or {})
			E.step(dt)
			f += 1
			table.insert(ms, (realClock() - f0) * 1000)
			if first and f <= 3 then
				-- (the first frames after the press, script by script: where an expansion's hitch goes)
				local rows = {}
				for k, v in E.coTime or {} do
					local d = v - (co0[k] or 0)
					if d > 0.0005 then
						table.insert(rows, { k = (string.gsub(k, "^.*%.", "")), v = d * 1000 })
					end
				end
				table.sort(rows, function(x, y)
					return x.v > y.v
				end)
				local out = {}
				for i = 1, math.min(8, #rows) do
					table.insert(out, string.format("%s %.1f", rows[i].k, rows[i].v))
				end
				local BU = modOr(p, "UI.BuildUI")
				log("expandperf %s frame %d: %.0f ms; scripts %s; the simulator's raycast index %d rebuilds %.0f ms; the Build tray built %d times so far", label, f, ms[#ms], table.concat(out, "; "), (rs and rs.builds or 0) - rb0, (rs and rs.buildMs or 0) - rbMs0, BU and BU.rebuilds or -1)
			end
			if stop and stop(f) then
				break
			end
		end
		local wall = realClock() - w0
		local sorted = table.clone(ms)
		table.sort(sorted, function(a, b)
			return a > b
		end)
		local over = 0
		for _, x in ms do
			if x > 25 then
				over += 1
			end
		end
		local top = {}
		for i = 1, math.min(6, #sorted) do
			table.insert(top, string.format("%.0f", sorted[i]))
		end
		local worstAt = {}
		for i, x in ms do
			if x >= (sorted[math.min(4, #sorted)] or 0) and #worstAt < 5 then
				table.insert(worstAt, string.format("%d: %.0f", i, x))
			end
		end
		log("expandperf %s: %d frames in %.2f s (%.1f ms a frame), %d over 25 ms; the slowest %s ms (frames %s)", label, f, wall, wall * 1000 / math.max(1, f), over, table.concat(top, ", "), table.concat(worstAt, "; "))
		if PR then
			local st = H.inClient(p, PR.debugPerf)
			local fr = math.max(1, st.frames)
			log("expandperf %s: the pixel filter %.2f ms a frame, the slowest %.1f ms; composes %.2f", label, st.stepMs / fr, st.maxMs or 0, st.composeMs / fr)
			log("expandperf %s: %d parts came or went, their rects %.1f ms in all", label, st.pokes or 0, st.pokeMs or 0)
			log("expandperf %s: re-casts %.2f (their finish %.2f), pans %.2f, uploads %.2f (%d), grades %.2f, water %.2f, wind %.2f; %d full composes (ms a frame)", label, (st.invMs or 0) / fr, (st.invFinMs or 0) / fr, st.scrollMs / fr, st.uploadMs / fr, st.uploads or 0, st.gradeMs / fr, st.waterMs / fr, st.windMs / fr, st.fullFrames or 0)
		end
		if rs then
			-- (the simulator rebuilds its raycast index whenever a part comes or goes; Roblox's own raycasts do not,
			-- so this time is in the frames above but would not be in the game's)
			log("expandperf %s: the simulator's raycast index rebuilt %d times, %.0f ms in all (not a cost in Roblox)", label, rs.builds - builds0, (rs.buildMs or 0) - buildMs0)
		end
		local rows = {}
		for k, v in E.coTime or {} do
			table.insert(rows, { k = k, v = v })
		end
		table.sort(rows, function(a, b)
			return a.v > b.v
		end)
		local parts = {}
		for i = 1, math.min(12, #rows) do
			table.insert(parts, string.format("%s %.2f", (string.gsub(rows[i].k, "^.*%.", "")), rows[i].v * 1000 / math.max(1, f)))
		end
		log("expandperf %s scripts (ms a frame): %s", label, table.concat(parts, "; "))
		if WV0 and WV0.debugCost then
			local c = H.inClient(p, WV0.debugCost)
			local n = math.max(1, c.frames)
			log("expandperf %s world view (ms a frame): driftlings %.2f, poses %.2f, fires/chips/signs %.2f, building cards %.2f, eggs %.2f; %d models out, %d pooled", label, c.walk * 1000 / n, c.pose * 1000 / n, c.rest * 1000 / n, c.tags * 1000 / n, c.eggs * 1000 / n, c.dressed, c.pooled)
		end
		E.coTime = nil
		return f
	end
	if WV0 and WV0.debugCost then
		H.inClient(p, WV0.debugCost)
	end
	run("standing before", 120)
	-- the next tier's picture cast ahead in the frames' spare time (PixelRenderer's pre-cast): until it has every tile
	-- near the view
	if PR and PR.debugPre then
		H.inClient(p, PR.debugPre)
		local f, w0 = 0, realClock()
		local st = H.inClient(p, PR.debugPre)
		while f < 3000 do
			E.step(dt)
			f += 1
			local now = H.inClient(p, PR.debugPre)
			for k, v in now do
				if type(v) == "number" then
					st[k] = (st[k] or 0) + v
				end
			end
			st.job = now.job
			if now.job and now.job.done > 0 and now.job.queued == 0 then
				break
			end
		end
		local j = st.job
		log("expandperf pre-cast: %d frames (%.1f s on the real clock), %d tiles cast (%d rays), %d resets; the job: tier %s, %d staged models over %d replaced, %d of the swap's %d tiles cast ahead", f, realClock() - w0, st.tiles or 0, st.rays or 0, st.reset or 0, j and tostring(j.tier) or "none", j and j.news or 0, j and j.olds or 0, j and j.done or 0, j and j.region or 0)
	end
	local bakes0 = PR and PR.debugStatic().bakes or 0
	local tier0 = prof.tier
	local tierAt, shownAt = -1, -1
	local frames = run("expanding", 700, function(f: number): boolean
		if tierAt < 0 and H.profile(p).tier > tier0 then
			tierAt = f
		end
		local st = PR and PR.debugStatic()
		-- (the new land drawn: a re-bake behind the picture finished, or the rects it changed re-cast; none when it
		-- changed off the screen)
		local busy = PR ~= nil and st ~= nil and (st.baking or (st.queued or 0) > 0)
		if shownAt < 0 and tierAt > 0 and f > tierAt + 20 and not busy then
			shownAt = f
		end
		return shownAt > 0
	end, function()
		-- (the server's swap and the filter's work, timed: straight to the server, the tray's loading card left out)
		H.req(p, "island.expand", {})
	end)
	local bakes = PR and PR.debugStatic().bakes or 0
	log("expandperf: tier %d -> %d: the tier changed on frame %d, the new land drawn by frame %d (%d re-bakes); %d land parts now", tier0, H.profile(p).tier, tierAt, shownAt, bakes - bakes0, landParts())
	if PR and PR.debugPre then
		local st = H.inClient(p, PR.debugPre)
		log("expandperf swap: %d tiles pasted from the pre-cast, %d cast the old way, %d parts' comings and goings cast nothing; %d others, %d of the replaced models' before it; the view at the pre-cast %d,%d, at the swap %d,%d", st.pasted or 0, st.cast or 0, st.skipped or 0, st.other or 0, st.early or 0, st.qx or 0, st.qy or 0, st.ax or 0, st.ay or 0)
		-- (the picture the swap pasted against a fresh cast of the whole layer)
		local cc = H.inClient(p, PR.debugCastCheck)
		log("expandperf swap check: %d of %d layer pixels differ from a fresh cast (%d part ids, %d of them two faces at one depth, %d sun, %d shades); others: %s", cc.off, cc.checked, cc.ids, cc.ties or 0, cc.lits, cc.shades, tostring(cc.ex))
	end
	run("standing after", 120)
	E.coTime = nil
	E.simClock = sim0
	settle(p, 20, 1)
	capture(p, "expandperf_after")
	return p
end
SCEN.expandperf = expandPerf

-- "expandrim=<tier>" (or "expandrim=<tier>:ui", through Build mode's Expand and its loading card): the report of
-- 2026-11-20, "there are artifacts that appear around after expanding" (a dark row across the rim into the sky, and
-- square blocks of night sky cut into the rim's rocks). An island at that tier, at night in the rain, in Build mode:
-- the view dragged round the whole island first (so the pan cache holds the island as it was), the next island built
-- ahead and its picture cast ahead, then Expand, and the view dragged round again, the layer checked against a fresh
-- cast at every step (PixelRenderer.debugCastCheck with the ink: the pixels off, sorted into sky where a part is,
-- a part where there is sky, and ink alone, with the 32 px tiles they fall in). Frames expandrim_before,
-- expandrim_after and expandrim_worst (the step with the most pixels off, if any).
local function expandRim(arg: string)
	local tier = tonumber(string.match(arg, "^(%d+)")) or 1
	local viaUi = string.find(arg, ":ui", 1, true) ~= nil
	local times = tonumber(string.match(arg, ":x(%d+)")) or 1
	local quick = string.find(arg, ":quick", 1, true) ~= nil
	-- (":replica": the tree swapped in is replaced by a copy of itself the moment it lands, the way a client receives
	-- a model the server parented to nil on the way)
	local replica = string.find(arg, ":replica", 1, true) ~= nil
	-- (":midbake": a whole bake is under way, behind the picture, when the expansion lands)
	local midbake = string.find(arg, ":midbake", 1, true) ~= nil
	seedProfile(59, tier, { pieces = VILLAGE, pals = { "mossbun" }, shells = 9e9 })
	local p = join(59, "Rimmer")
	settle(p, 60, 2)
	local PS = H.smod("PlotService")
	local PR = modOr(p, "Pixel.PixelRenderer")
	local CC = modOr(p, "Controllers.CameraController")
	local WV = modOr(p, "Controllers.WeatherView")
	local DL = modOr(p, "Controllers.DayLight")
	if PR == nil or CC == nil then
		log("expandrim: no pixel filter")
		return p
	end
	if WV then
		H.inClient(p, WV.debugSet, "rain")
	end
	if DL and DL.debugSky then
		H.inClient(p, DL.debugSky, 0.02)
	end
	H.clickNamed(p, "Menu_build", { optional = true, wait = 0.5 })
	settle(p, 20, 1)
	local st0 = H.inClient(p, PR.debugStatic)
	local K = st0.K
	local STEP = 40 * K -- screen px a step of the drag (40 art px)
	-- the drag round the island: a ring out to the drag's limit and back to the middle
	local path = {}
	local function go(dx, dy, n)
		for _ = 1, n do
			table.insert(path, { dx, dy })
		end
	end
	if quick then
		-- (out to the side and back: the layer's strips cast and taken back from the pan cache)
		go(1, 0, 4)
		go(-1, 0, 4)
	else
		go(1, 0, 7)
		go(0, 1, 5)
		go(-1, 0, 14)
		go(0, -1, 10)
		go(1, 0, 14)
		go(0, 1, 5)
		go(-1, 0, 7)
	end
	-- the Tree of Life's box on the layer (layer px), and the pixels off a fresh cast inside it
	local Street = H.sharedServer("Data.Street")
	local function treeModel(): Instance?
		local plots = E.workspace:FindFirstChild("Plots")
		local pm = plots and plots:FindFirstChild("Plot_1")
		local st = pm and pm:FindFirstChild("Static")
		local decor = st and st:FindFirstChild("Decor")
		if decor then
			for _, c in decor:GetChildren() do
				if string.find(c.Name, ":tree:", 1, true) then
					return c
				end
			end
		end
		return nil
	end
	local function treeOff(cc): (number, number, number)
		local m = treeModel()
		local mk = cc.mask
		if m == nil or mk == nil then
			return -1, 0, 0
		end
		local cf, size = (m :: any):GetBoundingBox()
		local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
		for _, sx in { -0.5, 0.5 } do
			for _, sy in { -0.5, 0.5 } do
				for _, sz in { -0.5, 0.5 } do
					local w = cf * E.cf.new(sx * size.X, sy * size.Y, sz * size.Z)
					local sp = H.inClient(p, PR.project, w.Position)
					x0, y0 = math.min(x0, sp.X / K), math.min(y0, sp.Y / K)
					x1, y1 = math.max(x1, sp.X / K), math.max(y1, sp.Y / K)
				end
			end
		end
		local W, Hh = st0.W, st0.H
		x0, y0 = math.max(0, math.floor(x0) - 2), math.max(0, math.floor(y0) - 2)
		x1, y1 = math.min(W - 1, math.ceil(x1) + 2), math.min(Hh - 1, math.ceil(y1) + 2)
		local off, ties, area = 0, 0, 0
		for y = y0, y1 do
			for x = x0, x1 do
				area += 1
				local c = buffer.readu8(mk, y * W + x)
				if c == 5 then
					ties += 1
				elseif c ~= 0 then
					off += 1
				end
			end
		end
		return off, ties, area
	end
	local treeTotal = 0
	local function sweep(label: string, check: boolean): (number, number)
		local worst, worstAt, total = 0, -1, 0
		local x, y = 0, 0
		for i, d in path do
			-- (a drag of the pointer by d: the world follows it, so the view goes the other way)
			H.inClient(p, CC.panBy, -d[1] * STEP, -d[2] * STEP)
			x += d[1]
			y += d[2]
			settle(p, 10, 0.1)
			if check then
				local cc = H.inClient(p, PR.debugCastCheck, true, true)
				-- (two faces at one depth are the ray index's to pick between: not counted)
				local bad = (cc.off or 0) - (cc.ties or 0) + (cc.inkOff or 0)
				total += bad
				local tOff, tTies, tArea = treeOff(cc)
				if tOff > 0 then
					treeTotal += tOff
					log("expandrim %s step %d: the tree's box (%d px) has %d off a fresh cast and %d ties", label, i, tArea, tOff, tTies)
				end
				if bad > 0 then
					log("expandrim %s step %d (%d,%d): %d off (%d sky over a part, %d a part over sky, %d ink alone, %d ties) in %d tiles, box %s; %s", label, i, x, y, bad, cc.skyOver or 0, cc.ghost or 0, cc.inkOff or 0, cc.ties or 0, cc.tiles or 0, if cc.box then table.concat(cc.box, ",") else "-", tostring(cc.ex))
				end
				if bad > worst then
					worst, worstAt = bad, i
					capture(p, "expandrim_worst")
				end
			end
		end
		log("expandrim %s: %d steps, %d pixels off in all, the most at one step %d (step %d)", label, #path, total, worst, worstAt)
		return total, worst
	end
	-- the island as it is, all round (the pan cache fills with it), and checked once
	sweep("before", true)
	capture(p, "expandrim_before")
	local grand = 0
	for round = 1, times do
	-- the next island built ahead and its picture cast ahead
	local guard = 0
	while not select(2, PS.debugNext(1)) and guard < 4000 do
		guard += 1
		E.step(E.dt)
	end
	local preFrames, preJob = 0, nil
	if PR.debugPre then
		while preFrames < 1500 do
			E.step(E.dt)
			preFrames += 1
			local now = H.inClient(p, PR.debugPre)
			preJob = now.job
			if now.job and not now.job.switched and now.job.done > 0 and now.job.queued == 0 then
				break
			end
		end
	end
	log("expandrim round %d pre-cast: after %d frames the job is %s", round, preFrames, if preJob then string.format("tier %d, %d of %d tiles done, %d queued, switched %s", preJob.tier, preJob.done, preJob.region, preJob.queued, tostring(preJob.switched)) else "none")
	local tier0 = H.profile(p).tier
	if midbake then
		H.inClient(p, PR.rebake)
		for _ = 1, 6 do
			E.step(E.dt)
		end
		log("expandrim round %d: a bake under way when it expands: %s", round, tostring(H.inClient(p, PR.debugStatic).baking))
	end
	if viaUi then
		H.clickNamed(p, "Expand", { optional = true, wait = 0 })
		local LCm = nil
		do
			local ctx = E.clientCtx(p)
			local inst = E.find("ReplicatedFirst.Loading.LoadingCard")
			local e = ctx and inst and ctx.modules[inst]
			LCm = e and e.value
		end
		local n = 0
		while n < 4000 do
			E.step(E.dt)
			n += 1
			local st = LCm and H.inClient(p, LCm.state)
			if H.profile(p).tier > tier0 and (st == nil or not st.up) then
				break
			end
		end
	else
		H.req(p, "island.expand", {})
	end
	if replica then
		local t = treeModel()
		if t then
			local c = (t :: any):Clone()
			local par = (t :: any).Parent
			t:Destroy()
			c.Parent = par
			log("expandrim round %d: the tree %s came in again as a copy of itself", round, c.Name)
		end
	end
	settle(p, 30, 1)
	local pre = H.inClient(p, PR.debugPre)
	log("expandrim round %d: tier %d -> %d; the swap pasted %d tiles, cast %d the old way, skipped %d parts' comings and goings", round, tier0, H.profile(p).tier, pre.pasted or 0, pre.cast or 0, pre.skipped or 0)
	local cc = H.inClient(p, PR.debugCastCheck, true, true)
	local tOff, tTies, tArea = treeOff(cc)
	treeTotal += math.max(0, tOff)
	log("expandrim round %d: the tree's box (%d px) right after the swap: %d off a fresh cast, %d ties", round, tArea, tOff, tTies)
	log("expandrim round %d after the swap, where it stood: %d off (%d sky over a part, %d a part over sky, %d ink alone, %d ties) in %d tiles; %s; ties: %s", round, (cc.off or 0) + (cc.inkOff or 0), cc.skyOver or 0, cc.ghost or 0, cc.inkOff or 0, cc.ties or 0, cc.tiles or 0, tostring(cc.ex), tostring(cc.tieEx))
	if round == 1 then
		capture(p, "expandrim_after")
	end
	local total, worst = sweep("after " .. round, true)
	grand += total
	end
	log("expandrim: %d pixels off a fresh cast after the expansions, %d of them over the tree", grand, treeTotal)
	if grand > 0 or treeTotal > 0 then
		table.insert(E.warnings, { ctx = "preview", text = string.format("EXPANDRIM: %d pixels off a fresh cast after the expansions, %d over the tree", grand, treeTotal), t = 0, phase = "expandrim" })
	end
	return p
end

-- "late": the screen's size settles after the HUD is built, the two ways Roblox does it: (1) the top bar's inset
-- arrives with no ViewportSize event (the roots shrink by it on their own), (2) a phone turns and the camera's
-- ViewportSize event comes before the roots are laid out again. The menu bar must stay wholly on screen, at the
-- bottom, each time (frames late_inset, late_turn; the log says where it is).
-- "treewalk[=<tier>][:expand][:sim]" (the report of 2026-11-20, "the tree still looks like this": creases inside
-- the trunk and a ragged outline in play, which no fresh picture showed). An island at that tier (11 unless given) at
-- midday, the founder walking as a player does with the view following: a loop round the Tree of Life, out across
-- the island and back, standing still, an egg hatched (the hatch scene's stage and back), the View slider moved and
-- put back, Build mode opened and shut (":expand": after one expansion first). The renderer's budgets read the real
-- clock, as in the game (":sim": the simulator's). Every few frames the layer is checked against a fresh cast in the
-- tree's box (PixelRenderer.debugCastCheck with the ink): the pixels off, by kind, the layer's outermost row and
-- column apart. Frames treewalk_start, treewalk_worst (the check with the most pixels off inside the layer over the
-- tree, if any), treewalk_end and treewalk_fresh (the same view baked afresh); TWMASK rows print the worst check's
-- mask over the tree's box for tools/preview/tree_walk.py.
local function treeWalk(arg: string)
	local tier = tonumber(string.match(arg, "^(%d+)")) or 11
	local expand = string.find(arg, ":expand", 1, true) ~= nil
	-- (":sim": the renderer's budgets on the simulator's clock, so a bake or a re-cast finishes in the frame it starts;
	-- by default they read the real clock, as in the game, and spread over frames the way a player sees them)
	local simClock = string.find(arg, ":sim", 1, true) ~= nil
	seedProfile(23, tier, { pieces = VILLAGE, pals = { "clawdle", "mossbun", "gullfin" }, shells = 9e9, eggs = { 1, 6, 3, 4, 5, 7, 8, 9 } })
	local p = join(23, "Walker")
	settle(p, 60, 2)
	local PR = modOr(p, "Pixel.PixelRenderer")
	local SU = modOr(p, "UI.SettingsUI")
	local DLt = modOr(p, "Controllers.DayLight")
	if PR == nil or PR.debugCastCheck == nil then
		log("treewalk: no pixel filter")
		return p
	end
	if DLt and DLt.debugSky then
		H.inClient(p, DLt.debugSky, 0.45)
	end
	local s = H.session(p)
	local Street = H.sharedServer("Data.Street")
	local Tree = H.sharedServer("Logic.Tree")
	local Plot = H.sharedServer("Logic.Plot")
	if expand then
		local PS = H.smod("PlotService")
		local guard = 0
		while not select(2, PS.debugNext(1)) and guard < 4000 do
			guard += 1
			E.step(E.dt)
		end
		for _ = 1, 600 do
			E.step(E.dt)
		end
		local t0 = H.profile(p).tier
		H.req(p, "island.expand", {})
		settle(p, 60, 2)
		log("treewalk: expanded from tier %d to %d", t0, H.profile(p).tier)
		local plots = E.workspace:FindFirstChild("Plots")
		local pm = plots and plots:FindFirstChild("Plot_" .. tostring(s.plot))
		local trees = {}
		for _, d in (if pm then pm:GetDescendants() else {}) do
			if d:IsA("Model") and string.find(d.Name, ":tree:", 1, true) then
				table.insert(trees, d:GetFullName() .. " (" .. #d:GetDescendants() .. ")")
			end
		end
		log("treewalk: tree models after the expansion: %s", table.concat(trees, "; "))
	end
	local prof = H.profile(p)
	local ox, oz = Street.origin(s.plot)
	local q = Tree.piece(prof)
	local tx, tz = ox, oz
	if q then
		local w, d = Plot.footprint(q.id, q.rot)
		tx, tz = ox + q.x - 1 + w / 2, oz + q.z - 1 + d / 2
	end
	local function walkLine(x0, z0, x1, z1, every, check)
		local len = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
		local n = math.max(1, math.floor(len / (16 / 60)))
		for i = 1, n do
			local u = i / n
			p.Character:PivotTo(E.cf.new(x0 + (x1 - x0) * u, 3, z0 + (z1 - z0) * u))
			E.step(1 / 60)
			if i % every == 0 then
				check(string.format("walk %.0f,%.0f", x0 + (x1 - x0) * u - tx, z0 + (z1 - z0) * u - tz))
			end
		end
	end
	p.Character:PivotTo(E.cf.new(tx - 12, 3, tz + 12))
	E.run(1)
	settle(p, 30, 1)
	capture(p, "treewalk_start")
	local realClock = os.clock
	if not simClock and PR.debugClock then
		H.inClient(p, PR.debugClock, realClock)
	end
	local st0 = H.inClient(p, PR.debugStatic)
	local K, W, Hh = st0.K, st0.W, st0.H
	local function treeBox(): (number, number, number, number)
		local m = treeModelOf(p)
		if m == nil then
			return 0, 0, -1, -1
		end
		local cf, size = (m :: any):GetBoundingBox()
		local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
		for _, sx in { -0.5, 0.5 } do
			for _, sy in { -0.5, 0.5 } do
				for _, sz in { -0.5, 0.5 } do
					local w = cf * E.cf.new(sx * size.X, sy * size.Y, sz * size.Z)
					local sp = H.inClient(p, PR.project, w.Position)
					x0, y0 = math.min(x0, sp.X / K), math.min(y0, sp.Y / K)
					x1, y1 = math.max(x1, sp.X / K), math.max(y1, sp.Y / K)
				end
			end
		end
		return math.max(0, math.floor(x0) - 2), math.max(0, math.floor(y0) - 2), math.min(W - 1, math.ceil(x1) + 2), math.min(Hh - 1, math.ceil(y1) + 2)
	end
	local worst, worstLabel, total, checks, skipped, rimTotal = 0, "", 0, 0, 0, 0
	local byKind = { 0, 0, 0, 0, 0 }
	local tieLogged = false
	local function check(label: string)
		local cc = H.inClient(p, PR.debugCastCheck, true, true)
		if (cc.off or -1) < 0 then
			skipped += 1
			return
		end
		checks += 1
		local mk = cc.mask
		local x0, y0, x1, y1 = treeBox()
		local kinds = { 0, 0, 0, 0, 0 }
		local off, rim = 0, 0
		if mk and x1 >= x0 then
			for y = y0, y1 do
				for x = x0, x1 do
					local c = buffer.readu8(mk, y * W + x)
					if c > 0 then
						kinds[c] += 1
						if c ~= 5 then
							-- (the layer's outermost row and column: a fresh cast inks them against nothing past the edge)
							if x == 0 or y == 0 or x == W - 1 or y == Hh - 1 then
								rim += 1
							else
								off += 1
							end
						end
					end
				end
			end
		end
		for k = 1, 5 do
			byKind[k] += kinds[k]
		end
		total += off
		rimTotal += rim
		if kinds[5] > 0 and not tieLogged then
			tieLogged = true
			log("treewalk %s: %d ties in the tree's box, e.g. %s", label, kinds[5], tostring(cc.tieEx))
		end
		if off > 0 then
			log("treewalk %s: the tree's box %d,%d-%d,%d has %d off a fresh cast inside the layer and %d on its edge (%d sky over a part, %d a part over sky, %d other, %d ink alone; %d ties); %s", label, x0, y0, x1, y1, off, rim, kinds[1], kinds[2], kinds[3], kinds[4], kinds[5], tostring(cc.ex))
		end
		if off > worst then
			worst, worstLabel = off, label
			capture(p, "treewalk_worst")
			print(string.format("TWBOX %d %d %d %d", x0, y0, x1, y1))
			for y = y0, y1 do
				local row = table.create(x1 - x0 + 1)
				for x = x0, x1 do
					table.insert(row, tostring(buffer.readu8(mk :: buffer, y * W + x)))
				end
				print("TWMASK " .. y .. " " .. table.concat(row, ""))
			end
		end
	end
	check("start")
	-- the loop round the tree (in front of it, past its side, behind it, back), then out across the island and back
	local R = 12
	walkLine(tx - R, tz + R, tx + R, tz + R, 8, check)
	walkLine(tx + R, tz + R, tx + R, tz - R, 8, check)
	walkLine(tx + R, tz - R, tx - R, tz - R, 8, check)
	walkLine(tx - R, tz - R, tx - R, tz + R, 8, check)
	walkLine(tx - R, tz + R, tx + 40, tz + 30, 8, check)
	walkLine(tx + 40, tz + 30, tx - 30, tz + 20, 8, check)
	walkLine(tx - 30, tz + 20, tx - 2, tz + 9, 8, check)
	-- standing still in front of it
	for k = 1, 6 do
		for _ = 1, 30 do
			E.step(1 / 60)
		end
		check("standing " .. k)
	end
	-- an egg hatched (the hatch scene is a stage of its own: the island's picture is kept aside and comes back when
	-- it closes)
	local HS = modOr(p, "UI.HatchScene")
	if HS then
		H.inClient(p, function()
			HS.play({ sp = "mossbun", muts = {}, r = 1, hr = 1, new = false }, nil)
		end)
		E.run(1.5)
		for _ = 1, 40 do
			if not H.inClient(p, HS.debugState).open then
				break
			end
			H.inClient(p, HS.skip)
			E.run(0.8)
		end
		for k = 1, 4 do
			for _ = 1, 10 do
				E.step(1 / 60)
			end
			check("after a hatch " .. k)
		end
		settle(p, 30, 1)
		check("after a hatch, settled")
	end
	-- the View slider moved and put back
	if SU then
		for _, n in { 5, 9, 7 } do
			H.inClient(p, SU.setZoom, n)
			for k = 1, 8 do
				for _ = 1, 15 do
					E.step(1 / 60)
				end
				check(string.format("notch %d, %d", n, k))
			end
			settle(p, 30, 1)
			check(string.format("notch %d settled", n))
		end
	end
	-- Build mode opened and shut
	H.clickNamed(p, "Menu_build", { optional = true, wait = 0.5 })
	settle(p, 30, 1)
	check("build mode")
	H.clickNamed(p, "BuildDone", { optional = true, wait = 0.5 })
	settle(p, 30, 1)
	check("build mode shut")
	walkLine(tx - 2, tz + 9, tx + 6, tz + 10, 4, check)
	settle(p, 30, 1)
	check("end")
	capture(p, "treewalk_end")
	if PR.debugClock then
		H.inClient(p, PR.debugClock, nil)
	end
	-- the same view baked afresh, to compare the whole picture (the moving models and effects over it too)
	H.inClient(p, PR.rebake)
	settle(p, 60, 1)
	capture(p, "treewalk_fresh")
	log("treewalk: %d checks (%d skipped while a bake ran), %d pixels off over the tree inside the layer and %d on its outermost row or column (by kind, both: %d sky over a part, %d a part over sky, %d other, %d ink alone; %d ties), the most at one check %d (%s)", checks, skipped, total, rimTotal, byKind[1], byKind[2], byKind[3], byKind[4], byKind[5], worst, worstLabel)
	-- (a pixel or two at a shadow's edge, lit one way on the layer and the other in a fresh cast, is the usual: the
	-- 2x2 blocks' shared sun rays; past 6 at one check something else is off)
	if worst > 6 then
		table.insert(E.warnings, { ctx = "preview", text = string.format("TREEWALK: %d pixels off a fresh cast over the tree, the most at one check %d (%s)", total, worst, worstLabel), t = 0, phase = "treewalk" })
	end
	return p
end

-- "treesplit[=<tier>]" (the reports of 2026-11-20, "the tree outlines are still broken, not like the screenshot you
-- sent" and "this only happens to the tree of life"): in the game the Tree of Life's 400 to 800 parts reach the client
-- over several frames, never all at once as here. An island at that tier (11 unless given) at midday, drawn; then the
-- tree taken away and its parts brought back in five batches a few frames apart (a sixth of them first), the way
-- replication hands them over; then the layer checked against a fresh cast over the tree's box
-- (PixelRenderer.debugCastCheck with the ink). Frames treesplit_after and treesplit_fresh.
local function treeSplit(arg: string)
	local tier = tonumber(string.match(arg, "^(%d+)")) or 11
	seedProfile(23, tier, { pieces = VILLAGE, pals = { "clawdle", "mossbun", "gullfin" }, shells = 9e9 })
	local p = join(23, "Splitter")
	settle(p, 60, 2)
	local PR = modOr(p, "Pixel.PixelRenderer")
	local DLt = modOr(p, "Controllers.DayLight")
	if PR == nil or PR.debugCastCheck == nil then
		log("treesplit: no pixel filter")
		return p
	end
	if DLt and DLt.debugSky then
		H.inClient(p, DLt.debugSky, 0.45)
	end
	local m = treeModelOf(p)
	if m == nil then
		log("treesplit: no tree")
		return p
	end
	local s = H.session(p)
	local Street = H.sharedServer("Data.Street")
	local Tree = H.sharedServer("Logic.Tree")
	local Plot = H.sharedServer("Logic.Plot")
	local ox, oz = Street.origin(s.plot)
	local q = Tree.piece(H.profile(p))
	local tx, tz = ox, oz
	if q then
		local w, d = Plot.footprint(q.id, q.rot)
		tx, tz = ox + q.x - 1 + w / 2, oz + q.z - 1 + d / 2
	end
	p.Character:PivotTo(E.cf.new(tx - 12, 3, tz + 12))
	E.run(1)
	settle(p, 30, 1)
	-- the tree away, its parts held aside with where they were
	local home = m.Parent
	local parts: { any } = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, { part = d, parent = d.Parent })
		end
	end
	m.Parent = nil
	settle(p, 30, 1)
	-- (a new model, as the server's rebuilt tree is: the renderer has never seen it, so nothing of it is gathered yet)
	local nm = I.new("Model")
	nm.Name = m.Name
	for k, v in m:GetAttributes() do
		nm:SetAttribute(k, v)
	end
	local holder = I.new("Folder")
	for i, e in parts do
		e.parent = nm
		e.part.Parent = if i > #parts // 6 then holder else nm
	end
	m = nm
	-- a sixth of it lands, drawn, then the rest in four batches
	m.Parent = home
	for _ = 1, 4 do
		E.step(1 / 60)
	end
	settle(p, 20, 1)
	local per = math.ceil((#parts - #parts // 6) / 4)
	local i = #parts // 6 + 1
	for _ = 1, 4 do
		for _ = 1, per do
			local e = parts[i]
			if e then
				e.part.Parent = e.parent
			end
			i += 1
		end
		for _ = 1, 3 do
			E.step(1 / 60)
		end
	end
	settle(p, 60, 2)
	local st = H.inClient(p, PR.debugStatic)
	local K, W, Hh = st.K, st.W, st.H
	local cf, size = (m :: any):GetBoundingBox()
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, sx in { -0.5, 0.5 } do
		for _, sy in { -0.5, 0.5 } do
			for _, sz in { -0.5, 0.5 } do
				local w = cf * E.cf.new(sx * size.X, sy * size.Y, sz * size.Z)
				local sp = H.inClient(p, PR.project, w.Position)
				x0, y0 = math.min(x0, sp.X / K), math.min(y0, sp.Y / K)
				x1, y1 = math.max(x1, sp.X / K), math.max(y1, sp.Y / K)
			end
		end
	end
	x0, y0 = math.max(1, math.floor(x0) - 2), math.max(1, math.floor(y0) - 2)
	x1, y1 = math.min(W - 2, math.ceil(x1) + 2), math.min(Hh - 2, math.ceil(y1) + 2)
	local cc = H.inClient(p, PR.debugCastCheck, true, true)
	local off, kinds = 0, { 0, 0, 0, 0, 0 }
	local mk = cc.mask
	if mk and (cc.off or -1) >= 0 then
		for y = y0, y1 do
			for x = x0, x1 do
				local c = buffer.readu8(mk, y * W + x)
				if c > 0 then
					kinds[c] += 1
					if c ~= 5 then
						off += 1
					end
				end
			end
		end
	end
	capture(p, "treesplit_after")
	log("treesplit: %d parts in %d batches; the tree's box %d,%d-%d,%d has %d pixels off a fresh cast (%d sky over a part, %d a part over sky, %d other, %d ink alone; %d ties)%s", #parts, 5, x0, y0, x1, y1, off, kinds[1], kinds[2], kinds[3], kinds[4], kinds[5], if (cc.off or -1) < 0 then " (a bake still running: not checked)" else "")
	H.inClient(p, PR.rebake)
	settle(p, 60, 1)
	capture(p, "treesplit_fresh")
	if off > 6 then
		table.insert(E.warnings, { ctx = "preview", text = string.format("TREESPLIT: %d pixels off a fresh cast over the tree after its parts came in batches", off), t = 0, phase = "treesplit" })
	end
	return p
end

-- "treebake[=<tier>]" (the reports of 2026-11-20, "the tree is the only thing that has this problem", "the fruits
-- seem to be affected the most": in the game the small round pieces had spikes and loose outline pixels): the
-- harness bakes on the simulator's clock, which stands still inside a frame, so a bake always finished in one; the
-- game reads the real clock and spreads a bake over many frames, coarse passes first. An island at that tier (1
-- unless given) at midday, its picture baked again on the real clock frame by frame, then the layer checked against
-- a fresh cast over the tree's box. Frames treebake_after and treebake_fresh.
local function treeBake(arg: string)
	local tier = tonumber(string.match(arg, "^(%d+)")) or 1
	seedProfile(23, tier, { pieces = VILLAGE, pals = { "clawdle", "mossbun", "gullfin" }, shells = 9e9 })
	local p = join(23, "Baker")
	settle(p, 60, 2)
	local PR = modOr(p, "Pixel.PixelRenderer")
	local DLt = modOr(p, "Controllers.DayLight")
	if PR == nil or PR.debugCastCheck == nil or PR.debugClock == nil then
		log("treebake: no pixel filter")
		return p
	end
	if DLt and DLt.debugSky then
		H.inClient(p, DLt.debugSky, 0.45)
	end
	local m = treeModelOf(p)
	local s = H.session(p)
	local Street = H.sharedServer("Data.Street")
	local Tree = H.sharedServer("Logic.Tree")
	local Plot = H.sharedServer("Logic.Plot")
	local ox, oz = Street.origin(s.plot)
	local q = Tree.piece(H.profile(p))
	local tx, tz = ox, oz
	if q then
		local w, d = Plot.footprint(q.id, q.rot)
		tx, tz = ox + q.x - 1 + w / 2, oz + q.z - 1 + d / 2
	end
	p.Character:PivotTo(E.cf.new(tx - 6, 3, tz + 6))
	E.run(1)
	settle(p, 30, 1)
	-- the bake again on the real clock, a frame at a time
	H.inClient(p, PR.debugClock, os.clock)
	H.inClient(p, PR.rebake)
	local frames = 0
	for _ = 1, 3000 do
		E.step(1 / 60)
		frames += 1
		if not H.inClient(p, PR.debugStatic).baking and frames > 5 then
			break
		end
	end
	for _ = 1, 30 do
		E.step(1 / 60)
	end
	local st = H.inClient(p, PR.debugStatic)
	local K, W, Hh = st.K, st.W, st.H
	local x0, y0, x1, y1 = 1, 1, W - 2, Hh - 2
	if m then
		local cf, size = (m :: any):GetBoundingBox()
		local a0, b0, a1, b1 = math.huge, math.huge, -math.huge, -math.huge
		for _, sx in { -0.5, 0.5 } do
			for _, sy in { -0.5, 0.5 } do
				for _, sz in { -0.5, 0.5 } do
					local w = cf * E.cf.new(sx * size.X, sy * size.Y, sz * size.Z)
					local sp = H.inClient(p, PR.project, w.Position)
					a0, b0 = math.min(a0, sp.X / K), math.min(b0, sp.Y / K)
					a1, b1 = math.max(a1, sp.X / K), math.max(b1, sp.Y / K)
				end
			end
		end
		x0, y0 = math.max(1, math.floor(a0) - 2), math.max(1, math.floor(b0) - 2)
		x1, y1 = math.min(W - 2, math.ceil(a1) + 2), math.min(Hh - 2, math.ceil(b1) + 2)
	end
	local cc = H.inClient(p, PR.debugCastCheck, true, true)
	local off, kinds = 0, { 0, 0, 0, 0, 0 }
	local mk = cc.mask
	if mk and (cc.off or -1) >= 0 then
		for y = y0, y1 do
			local row = {}
			local any = false
			for x = x0, x1 do
				local c = buffer.readu8(mk, y * W + x)
				if c > 0 then
					kinds[c] += 1
					if c ~= 5 then
						off += 1
						any = true
					end
				end
				table.insert(row, if c > 0 and c ~= 5 then tostring(c) else ".")
			end
			if any then
				print(string.format("TBMASK %d %s", y, table.concat(row)))
			end
		end
	end
	capture(p, "treebake_after")
	log("treebake: baked again over %d frames on the real clock; the tree's box %d,%d-%d,%d has %d pixels off a fresh cast (%d sky over a part, %d a part over sky, %d other, %d ink alone; %d ties)%s; %s", frames, x0, y0, x1, y1, off, kinds[1], kinds[2], kinds[3], kinds[4], kinds[5], if (cc.off or -1) < 0 then " (a bake still running: not checked)" else "", tostring(cc.ex))
	H.inClient(p, PR.debugClock, nil)
	H.inClient(p, PR.rebake)
	settle(p, 60, 1)
	capture(p, "treebake_fresh")
	if off > 6 then
		table.insert(E.warnings, { ctx = "preview", text = string.format("TREEBAKE: %d pixels off a fresh cast over the tree after a bake spread over frames", off), t = 0, phase = "treebake" })
	end
	return p
end

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
local function loadingArtScenario(arg: string?)
	local env = { E = E, H = H, log = log, capture = capture, join = join, settle = settle, cshared = cshared, modOr = modOr, seedProfile = seedProfile, pieces = VILLAGE, pals = { "clawdle", "mossbun", "pebblit", "gullfin", "frondle" } }
	-- ("ploadingart=<tier>,<big notch>,<small notch>,<drop>": to try another island or framing)
	local t, b, sm, d = string.match(arg or "", "^(%d+),(%d+),(%d+),?(%d*)$")
	if t then
		env.tier, env.big, env.small, env.drop = tonumber(t), tonumber(b), tonumber(sm), tonumber(d)
	end
	return require("./loading_art")(env)
end
SCEN.ploadingart = function()
	return loadingArtScenario(nil)
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
-- "cthumbs" / "cthumbs=<k>of<n>" / "cthumbs=<id>,<id>": the cosmetics' pictures (tools/preview/cosmetic_thumbs.luau;
-- sh tools/preview/cosmetic_thumbs.sh runs it and makes UI/CosmeticThumbData)
local function cthumbsScenario(arg: string?)
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
	return require("./cosmetic_thumbs")(env)
end
SCEN.cthumbs = cthumbsScenario
-- "picons" / "picons=<id>,<id>": the game passes' and developer products' icons' subjects
-- (tools/preview/product_icons.luau; sh tools/preview/product_icons.sh lays them on their badges)
local function piconsScenario(arg: string?)
	local env = { E = E, H = H, log = log, capture = capture, join = join, settle = settle, cshared = cshared, modOr = modOr }
	if arg then
		env.only = {}
		for id in string.gmatch(arg, "[^,]+") do
			table.insert(env.only, id)
		end
	end
	return require("./product_icons")(env)
end
SCEN.picons = piconsScenario
-- "gthumbs" / "gthumbs=<shot>,<shot>" (tree crowd town work) / "gthumbs=cast" / "gthumbs=cast:<id>,<id>" / "gthumbs=day1" / "gthumbs=day100" / "gthumbs=icon": the game's
-- thumbnails' scenes and the driftlings drawn over them (tools/preview/game_thumbs.luau; sh tools/preview/game_thumbs.sh
-- lays them out with the title and the captions)
local function gthumbsScenario(arg: string?)
	local env = { E = E, H = H, log = log, capture = capture, join = join, settle = settle, cshared = cshared, modOr = modOr, seedProfile = seedProfile, harbor = HARBOR, pals = PALS }
	if arg and (string.sub(arg, 1, 4) == "cast" or arg == "hatch" or arg == "lawn" or arg == "sky" or arg == "day1" or arg == "icon" or string.sub(arg, 1, 6) == "day100") then
		env.mode = arg
	elseif arg then
		env.only = {}
		for id in string.gmatch(arg, "[^,]+") do
			env.only[id] = true
		end
	end
	return require("./game_thumbs")(env)
end
SCEN.gthumbs = gthumbsScenario
-- "showcase=<tier>": a well decorated town on an island of that tier (the request of 2026-11-19: "could you make an
-- example of a well decorated town across all expansions?"), laid out by tools/preview/showcase.luau within the game's
-- rules and limits, its huts full of driftlings. Frames: showcase<tier>_far_1 .. (the View slider all the way out,
-- the founder walking north up the avenue so every part of the island is seen once) and showcase<tier>_near_1 ..
-- (the usual view: the plaza, then a few blocks up the island).
local function showcaseScenario(tier: number)
	local Plot = H.sharedServer("Logic.Plot")
	local Creatures = H.sharedServer("Data.Creatures")
	local plan = require("./showcase")({ Plot = Plot, Buildings = H.sharedServer("Data.Buildings"), Street = H.sharedServer("Data.Street"), log = log })
	local info = nil
	local pals = {}
	for k = 1, math.min(Plot.housingLimit(tier), 40) do
		table.insert(pals, Creatures.list[(k * 7 - 1) % #Creatures.list + 1].id)
	end
	local uid = 40 + tier
	seedProfile(uid, tier, {
		fill = function(prof)
			info = plan(prof)
		end,
		pals = pals,
		shells = 9e9,
	})
	local p = join(uid, "Showcase")
	settle(p, 90, 2)
	E.run(3)
	local Street = H.sharedServer("Data.Street")
	local ox = Street.origin(H.session(p).plot)
	local zN = if info then info.zN else -10
	local function walkTo(x: number, z: number)
		if p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
			p.Character:PivotTo(E.cf.new(ox + x, 3, z))
			E.run(2)
			settle(p, 60, 1)
		end
		E.run(1.5)
	end
	-- far out: the View slider's first notch
	local SU = modOr(p, "UI.SettingsUI")
	H.openPanel(p, "settings")
	E.run(0.4)
	if SU then
		H.inClient(p, SU.setZoom, 1)
	end
	E.run(0.8)
	H.closePanel(p)
	E.run(0.5)
	local k = 0
	local z = 2
	while true do
		k += 1
		walkTo(-1, z)
		capture(p, string.format("showcase%d_far_%d", tier, k))
		if z - 40 < zN + 10 then
			break
		end
		z -= 60
	end
	-- the usual view: the plaza and a few blocks north
	H.openPanel(p, "settings")
	E.run(0.4)
	if SU then
		H.inClient(p, SU.setZoom, H.sharedServer("Config.Tuning").CamZoomDefault)
	end
	E.run(0.8)
	H.closePanel(p)
	E.run(0.5)
	local near = { { -1, 4 }, { -14, -18 }, { 14, -18 }, { -14, -38 }, { 14, -38 } }
	for i, s in near do
		if s[2] >= zN + 4 then
			walkTo(s[1], s[2])
			capture(p, string.format("showcase%d_near_%d", tier, i))
		end
	end
	return p
end

-- "alerts": the alerts with their longest words, so the log's OVERFLOW lines catch any cut short (the request of
-- 2026-11-19, "it seems like the text gets cut off for some alerts", with "An egg hat..." over "Blazemane hatched!"):
-- the banner for one egg hatched (alerts_hatch), for three with the longest kind's name, new (alerts_hatch3), the
-- longest error as a notice (alerts_notice), and with the Driftlings panel open a short notice in its awning's line
-- and a long one over the screen's top (alerts_panel).
function SCEN.alerts()
	seedProfile(23, 2, { pieces = VILLAGE, pals = { "clawdle", "mossbun", "gullfin" }, shells = 2000 })
	local p = join(23, "Alert")
	settle(p)
	local SC = modOr(p, "Controllers.StateClient")
	local UIKitC = modOr(p, "UI.UIKit")
	local WordsC = modOr(p, "UI.Words")
	local Creatures = H.sharedServer("Data.Creatures")
	if SC == nil or UIKitC == nil or WordsC == nil then
		log("alerts: no StateClient, UIKit or Words")
		return p
	end
	local longest = Creatures.list[1]
	for _, d in Creatures.list do
		if #d.name > #longest.name then
			longest = d
		end
	end
	local function fx(msg)
		H.inClient(p, function()
			SC.Fx:Fire(msg)
		end)
	end
	fx({ kind = "turn", hatched = { { sp = "blazemane" } } })
	E.run(0.6)
	capture(p, "alerts_hatch")
	E.run(4)
	fx({ kind = "turn", hatched = { { sp = longest.id }, { sp = "blazemane" }, { sp = "gullfin" } }, fresh = { longest.id } })
	E.run(0.6)
	capture(p, "alerts_hatch3")
	E.run(5)
	H.inClient(p, UIKitC.notice, WordsC.errText("work"), UIKitC.color("bad"))
	E.run(0.4)
	capture(p, "alerts_notice")
	E.run(4)
	H.openPanel(p, "pals")
	E.run(0.6)
	H.inClient(p, UIKitC.notice, WordsC.errText("money"), UIKitC.color("bad"))
	H.inClient(p, UIKitC.notice, WordsC.errText("full"), UIKitC.color("bad"))
	E.run(0.4)
	capture(p, "alerts_panel")
	return p
end

-- "screen=<125|150|175|200>": the Settings panel's Screen at that scale (Pixel/DisplayScale; the report of 2026-11-20,
-- a tree whose every pixel was 2.5 of the screen's): the village, then the log says the pixel size in units and in the
-- screen's own pixels, and where the pixel layer's image and each interface root's canvas sit and how big they are, in
-- the screen's pixels (`screen:` lines; every one should be whole). The harness draws at 100%, so the PNG's pixels are
-- uneven by design: the numbers are the check.
function SCEN.screen(choice: string)
	seedProfile(2, 1, { pieces = VILLAGE, pals = { "clawdle", "mossbun", "pebblit" } })
	local p = join(2, "Pixel")
	settle(p)
	local res = H.req(p, "settings.set", { k = "screen", v = choice })
	local SU = modOr(p, "UI.SettingsUI")
	if SU then
		H.inClient(p, SU.apply)
	end
	E.run(1.5)
	settle(p, 60, 1)
	local DS = H.cmod(p, "Pixel.DisplayScale")
	local PR = H.cmod(p, "Pixel.PixelRenderer")
	local d = H.inClient(p, DS.factor)
	local k = H.inClient(p, PR.pixelScale)
	log("screen: choice %s (%s), scale %g, pixel size %g units = %g screen px", choice, tostring(res and (res.ok or res.err)), d, k, k * d)
	local bad = 0
	local function whole(v)
		local q = v * d
		return math.abs(q - math.floor(q + 0.5)) < 1e-3
	end
	-- (measured from the screen's corner, where the pixel layer's image starts: Roblox's own origin sits under the top
	-- bar)
	local layerGui = p.PlayerGui:FindFirstChild("PixelLayer")
	local layerImg = layerGui and layerGui:FindFirstChild("Image")
	local corner = if layerImg and layerImg:IsA("GuiObject") then layerImg.AbsolutePosition else Vector2.zero
	for _, g in p.PlayerGui:GetChildren() do
		if g:IsA("ScreenGui") and (g.Name == "PixelLayer" or g:FindFirstChild("Canvas") ~= nil) then
			local o = if g.Name == "PixelLayer" then g:FindFirstChild("Image") else g:FindFirstChild("Canvas")
			if o and o:IsA("GuiObject") then
				local ap, as = o.AbsolutePosition - corner, o.AbsoluteSize
				local ok = whole(ap.X) and whole(ap.Y) and whole(as.X) and whole(as.Y)
				if not ok then
					bad += 1
				end
				log("screen: %s %s at %g,%g size %g x %g units: %s", g.Name, o.Name, ap.X, ap.Y, as.X, as.Y, if ok then "whole screen px" else "NOT whole")
			end
		end
	end
	log("screen: %d not on whole screen px", bad)
	capture(p, "screen")
	return p
end

-- "loading": the loading card while the game loads (src/first/LoadingCard: ReplicatedFirst's Boot puts it up before the
-- rest has arrived): a still a second in (loading) and a frame every fifth of a second while it is up (loading_000 ..;
-- make_gif.py makes them a GIF); the log says how far it got (its phase, its bar, the island's picture, whether it
-- painted).
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
				log("loading: phase %s, bar %.2f, picture %s, painted %s, fallback %s, K %d, size %dx%d", st.phase, st.bar, if st.still then string.format("%s %dx%d at %d,%d", st.still.name, st.still.w, st.still.h, st.still.x0, st.still.y0) else "none", tostring(st.painted), tostring(st.fallback), st.K, st.size.X, st.size.Y)
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
	-- (the top tier, so every piece is open: Everdrift since the request of 2026-11-14)
	local TOP = #H.sharedServer("Config.Tuning").TierCost
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
			if ok and Plot.fits(TOP, placed, q[1], q[2], q[3], q[4]) then
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
	seedProfile(19, TOP, { pieces = pieces, shells = 1e9 })
	local p = join(19, "Catalog")
	settle(p)
	local Street = H.sharedServer("Data.Street")
	local ox = Street.origin(H.session(p).plot)
	do
		-- each piece's parts, and how many of them move (Models/Parts.move), as the server built it
		local plots = E.workspace:FindFirstChild("Plots")
		local pm = plots and plots:FindFirstChild("Plot_" .. tostring(H.session(p).plot))
		local st = pm and pm:FindFirstChild("Static")
		local decor = st and st:FindFirstChild("Decor")
		local seen = {}
		for _, c in (if decor then decor:GetChildren() else {}) do
			local id = c:GetAttribute("Decor")
			if type(id) == "string" and not seen[id] and table.find(ids, id) then
				seen[id] = true
				local n, moving = 0, 0
				-- (and how far past its footprint any part reaches, in studs: the worst part's name)
				local at = c:GetAttribute("At")
				local d = H.sharedServer("Data.Buildings").byId[id]
				local over, worst = 0, ""
				for _, q in c:GetDescendants() do
					if q:IsA("BasePart") then
						n += 1
						if q:GetAttribute("Move") ~= nil then
							moving += 1
						end
						if typeof(at) == "CFrame" and d and string.sub(q.Name, 1, 7) ~= "Pennant" then
							local cf, sz = at:ToObjectSpace(q.CFrame), q.Size / 2
							for _, sx in { -1, 1 } do
								for _, sy in { -1, 1 } do
									for _, sz2 in { -1, 1 } do
										local pt = cf * Vector3.new(sx * sz.X, sy * sz.Y, sz2 * sz.Z)
										local o = math.max(math.abs(pt.X) - d.w / 2, math.abs(pt.Z) - math.max(d.d, 0.5) / 2)
										if o > over then
											over, worst = o, q.Name
										end
									end
								end
							end
						end
					end
				end
				log("catalog parts: %s %d (%d moving)%s", id, n, moving, if over > 0.3 then string.format(", reaches %.2f past its footprint (%s)", over, worst) else "")
			end
		end
	end
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
	seedProfile(70 + table.find(THEME_ORDER, name) :: number, 6, { pieces = pieces, pals = { "mossbun", "clawdle", "pebblit", "gullfin" }, shells = 180000 })
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
-- (hr > r: it turns rarer on the way; 1 .. 9, mythic 6, celestial 7, ancient 8, eternal 9), the first kind of that rarity with a set of
-- mutations by rarity. The
-- request of 2026-11-14: "could you also remove the transition that happens when clicking to hatch an egg? you can
-- simply render the floating egg in a 2d background. also, make the player click to hatch the egg, each click
-- revealing a mutation or a tier up upgrade if there is any, otherwise it just hatches"; then of 2026-11-15, "make the
-- egg revealing much more grander with more animations and effects". Frames: its shadow growing on the pedestal before
-- it falls (hatch_wait), the egg dropping onto its pedestal (hatch_dropping), its first bounce (hatch_landing), resting
-- there with rings spreading from under it (hatch_egg), each tap's reveal a tenth of a second in (hatch_rise<k>_hit,
-- hatch_mut<k>_hit) and a moment later (hatch_rise<k> for a step up, hatch_mut<k> for a mutation), the tap that hatches
-- it (hatch_shake: the egg shaking open, "Make eggs shake while being cracked open"; hatch_blaze near the end of its
-- build-up; hatch_crack, just after the shell opens), what hatched coming out (hatch_pop), landed (hatch_out), its card
-- coming in (hatch_card) and what hatched with its mutations listed (hatch_reveal), then the island after one more tap
-- (hatch_back).
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
	local MUTS = { {}, { "busy1" }, { "grower2", "bright1" }, { "fierce3", "sturdy2", "lazy" }, { "bright4", "busy3", "armor2", "trader1" }, { "busy4", "grower3", "bright2" }, { "bright4", "sturdy3", "trader3", "fierce2" }, { "golden5", "busy4", "bright3" }, { "crown6", "golden5", "bright4", "busy3" } }
	local muts = MUTS[hr] or {}
	H.inClient(p, function()
		HS.play({ sp = sp or "mossbun", muts = muts, r = r, hr = hr, new = (sp or "mossbun") ~= "mossbun" }, nil)
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
	-- (before it falls its shadow grows on the pedestal; then it drops in from above onto its pedestal and bounces:
	-- "Make the egg drop down and bounce a bit instead of appearing by going up", 2026-11-14; it lands squashing, a
	-- ring of dust over the pedestal)
	local function runTo(t)
		E.runUntil(function()
			return state().clock >= t
		end, 10, 0.05)
	end
	runTo(st.wait * 0.7)
	capture(p, "hatch_wait")
	runTo(st.wait + 0.3)
	capture(p, "hatch_dropping")
	log("hatch %s: dropping: %.2f studs over its spot (it waited %.2f s)", code, state().lift, st.wait)
	runTo(st.wait + 0.6)
	capture(p, "hatch_landing")
	log("hatch %s: landing: squash %.2f, jolt %d", code, state().squash, state().jolt)
	runTo(st.wait + 1.35)
	capture(p, "hatch_egg")
	log("hatch %s: landed: %.2f over its spot, %d rings spreading, %d god rays lit", code, state().lift, state().rings, state().light)
	-- (the screen changes size while the egg waits, a window widened, then back: the title stays centred and the sky
	-- follows the egg; the user's report of 2026-11-14, "it sometimes doesnt center the text here")
	do
		local cam = E.workspace.CurrentCamera
		local old = E.viewport
		log("hatch %s: title %.0f px off the middle on %dx%d", code, state().titleOff, old.X, old.Y)
		E.viewport = v2(math.floor(old.X * 1.25), old.Y)
		I.firePropChanged(cam, getD(cam), "ViewportSize")
		E.flushDeferred()
		E.run(0.6)
		log("hatch %s: screen widened to %dx%d: title %.0f px off the middle", code, E.viewport.X, E.viewport.Y, state().titleOff)
		capture(p, "hatch_wide")
		E.viewport = old
		I.firePropChanged(cam, getD(cam), "ViewportSize")
		E.flushDeferred()
		E.run(0.6)
		log("hatch %s: back to %dx%d: title %.0f px off the middle", code, old.X, old.Y, state().titleOff)
	end
	-- (each tap: a frame mid effect, "_hit", and one a moment later)
	local rises, mutsShown = 0, 0
	for _ = 1, st.reveals do
		local before = state()
		H.inClient(p, HS.skip)
		E.run(0.1)
		local mid = state()
		local label = if mid.r > before.r then "hatch_rise" .. (rises + 1) else "hatch_mut" .. (mutsShown + 1)
		capture(p, label .. "_hit")
		log("hatch %s: %s: squash %.2f, jolt %d, god rays %d", code, label, mid.squash, mid.jolt, mid.light)
		E.run(0.2)
		if mid.r > before.r then
			rises += 1
		else
			mutsShown += 1
		end
		capture(p, label)
	end
	st = state()
	log("hatch %s: after %d taps: rarity %d, %d mutations shown, cracks %d, glowing %s, title %q", code, st.reveals, st.r, st.shown, st.crack, tostring(st.glowing), st.title)
	-- (the tap that hatches it: the build-up, the break, what hatched coming out, its card)
	H.inClient(p, HS.skip)
	E.run(0.35)
	st = state()
	capture(p, "hatch_shake")
	log("hatch %s: shaking open: phase %s, shake %.2f, cracks %d, build %.2f s, hush %.2f, god rays %d", code, st.phase, st.shake, st.crack, st.build, st.hush, st.light)
	runTo(st.clock - 0.35 + st.build * 0.85)
	st = state()
	capture(p, "hatch_blaze")
	log("hatch %s: about to break: shake %.2f, hush %.2f, god rays %d", code, st.shake, st.hush, st.light)
	E.runUntil(function()
		return state().phase ~= "breaking"
	end, 5, 0.05)
	st = state()
	capture(p, "hatch_crack")
	log("hatch %s: the break: slow %s, jolt %d, god rays %d", code, tostring(st.slow), st.jolt, st.light)
	local t0 = st.clock
	runTo(t0 + 0.12)
	capture(p, "hatch_pop")
	runTo(t0 + 0.55)
	capture(p, "hatch_out")
	log("hatch %s: out: %d stars circling, letters %d", code, state().stars, state().letters)
	runTo(t0 + 0.75)
	capture(p, "hatch_card")
	E.runUntil(function()
		return state().phase == "done"
	end, 5, 0.05)
	E.run(0.4)
	st = state()
	capture(p, "hatch_reveal")
	log("hatch %s: laid %d, hatched %d as %s: phase %s, %d mutations of %d, %s, title %q, name %q, New! %s, ribbon %s, %d letters, %d stars, god rays %d", code, r, st.r, tostring(sp), st.phase, st.shown, st.muts, if st.pal then "what hatched is there" else "nothing hatched", st.title, st.name, tostring(st.fresh), tostring(st.ribbon), st.letters, st.stars, st.light)
	H.inClient(p, HS.skip)
	E.run(0.2)
	log("hatch %s: closed %s", code, tostring(not state().open))
	settle(p, 10, 0.3)
	capture(p, "hatch_back")
	return p
end

-- "pals=<n>" or "pals=<id>,<id>,..." ("palsw=" at the islands' level of detail; an id "shape.body.accent" builds a
-- body plan in those colours): driftlings up close (Models/DriftModels, built "full" as the hatch scene and the
-- portraits show them), eight to a picture in two rows of four on a patch of lawn far from the islands, framed by the
-- camera's stage view; idle (pals_idle), cheering (pals_cheer) and hurt (pals_hurt: the lids shut, the mouth open). Batch n is Data/Creatures.list's species 8n-7 ..
-- 8n; the log lists them left to right, back row first, with each one's part count.
local function palsScenario(arg, lod)
	seedProfile(62, 1, {})
	local p = join(62, "Keeper")
	settle(p, 30, 1)
	local Creatures = H.sharedServer("Data.Creatures")
	local ids = {}
	local n = tonumber(arg)
	if n then
		for i = (n - 1) * 8 + 1, n * 8 do
			local d = Creatures.list[i]
			if d then
				table.insert(ids, d.id)
			end
		end
	else
		for id in string.gmatch(arg, "[^,]+") do
			table.insert(ids, id)
		end
	end
	local ctx = E.clientCtx(p)
	local MM = E.moduleIn(ctx, E.find("ReplicatedStorage.Shared.Models.MicroModels"))
	local Blocks = E.moduleIn(ctx, E.find("ReplicatedStorage.Shared.Models.Blocks"))
	local PR = H.cmod(p, "Pixel.PixelRenderer")
	local CC = H.cmod(p, "Controllers.CameraController")
	for _, g in p.PlayerGui:GetChildren() do
		if g:IsA("ScreenGui") and g.Name ~= "PixelLayer" and g.Name ~= "SkyBackdrop" then
			g.Enabled = false
		end
	end
	local OX, OZ = 0, 9400
	-- (the ground's screen-right and toward-the-viewer directions, as the zoo)
	local ux, uz = math.sqrt(0.5), -math.sqrt(0.5)
	local vx, vz = math.sqrt(0.5), math.sqrt(0.5)
	local faceViewer = math.atan2(vx, vz)
	local things = {}
	H.inClient(p, function()
		local m = Blocks.model(E.workspace, "PalsLawn")
		Blocks.part(m, { size = E.v3(30, 1, 30), cf = E.cf.new(OX, -0.5, OZ), color = "grass" })
		local names = {}
		for i, id in ids do
			-- (an id "shape.body.accent" builds a body plan in those colours, no species needed)
			local plan = string.split(id, ".")
			local d = Creatures.byId[id] or (if #plan >= 2 then { id = id, shape = plan[1], body = plan[2], accent = plan[3] or plan[2] } else nil)
			if d then
				-- (a fourth and fifth part pick the eyes' style and iris colour: "pup.orange.cream.slit.yellow")
				local look = if plan[4] then { eye = plan[4], iris = plan[5] } else nil
				local th = if #plan >= 2 then MM.driftling(plan[1], plan[2], plan[3] or plan[2], lod, look) else MM.species(d.id, lod)
				th.model:SetAttribute("PixelShadow", 1)
				th.model:SetAttribute("PixelGroundY", 0)
				th.model.Parent = E.workspace
				PR.registerDynamic(th.model)
				local k = i - 1
				local u, v = -4.8 + (k % 4) * 3.2, -2.2 + math.floor(k / 4) * 4.4
				table.insert(things, { t = th, x = OX + ux * u + vx * v, z = OZ + uz * u + vz * v })
				local c = 0
				for _ in th.parts do
					c += 1
				end
				table.insert(names, string.format("%s (%s, %d parts)", id, d.shape, c))
			end
		end
		log("pals %s: %s", arg, table.concat(names, ", "))
		local pts = {}
		for _, q in { { -6.8, -3.8 }, { 6.8, -3.8 }, { -6.8, 5.4 }, { 6.8, 5.4 } } do
			for _, y in { 0, 2.6 } do
				table.insert(pts, OX + ux * q[1] + vx * q[2])
				table.insert(pts, y)
				table.insert(pts, OZ + uz * q[1] + vz * q[2])
			end
		end
		CC.setStage({ name = "pals", origin = E.v3(OX, 0, OZ), pts = pts, tight = nil, top = 8, bottom = 8 })
	end)
	-- (and hurt, its eyes shut and its mouth open: the lids of a blink)
	for _, mood in { "idle", "cheer", "hurt" } do
		H.inClient(p, function()
			for j, x in things do
				MM.animate(x.t, 0.6 + j * 0.37, mood, 0)
				MM.place(x.t, E.cf.new(x.x, 0, x.z) * E.cf.Angles(0, faceViewer + math.rad(30), 0))
			end
		end)
		settle(p, 60, 0.5)
		capture(p, "pals_" .. mood)
	end
	-- (what drawing them costs up close: posed afresh every frame for a second, the renderer's model time a frame)
	local PR = modOr(p, "Pixel.PixelRenderer")
	if PR and PR.debugPerf then
		-- (on the real clock, so the renderer's own timings are real ones: as the pan scenario does)
		local realClock = os.clock
		local sim0 = E.simClock
		local off = E.SIM.lastClock - realClock() + 1
		E.simClock = function()
			local v = realClock() + off
			E.SIM.lastClock = v
			return v
		end
		H.inClient(p, PR.debugPerf)
		for f = 1, 30 do
			H.inClient(p, function()
				for j, x in things do
					MM.animate(x.t, 1 + f / 30 + j * 0.37, "cheer", f / 30)
					MM.place(x.t, E.cf.new(x.x, 0, x.z) * E.cf.Angles(0, faceViewer + math.rad(30), 0))
				end
			end)
			E.run(1 / 30)
		end
		local st = H.inClient(p, PR.debugPerf)
		E.simClock = sim0
		log("pals perf: %d frames, models %.2f ms a frame (%d drawn)", st.frames, st.dynMs / math.max(1, st.frames), st.draws)
	end
	return p
end

-- "looks=<n>" or "looks=<id>,<id>,...": eight founders up close wearing the pieces of Data/Cosmetics (GAME_DESIGN 14.1:
-- Models/CosmeticModels on Models/CharacterModels' standing rig), each outlined in white (the pixel filter's rim; the
-- first one as the player's own, "self") with a name tag and a title over its head (Controllers/NameTags), in two rows
-- of four on a lawn far from the islands; standing (looks_stand) and walking (looks_walk). Batch n dresses founder i
-- (8n-7 .. 8n) in each slot's piece i (round the slot's list), with skin, hair colour, hair style and shirt colour
-- turning too, so batches 1 to 4 show every piece and every style; an id list puts one piece on each founder. The log
-- lists each founder's pieces and part count. "looks=f<k>" shows the features of the bakery's customization screen (the
-- request of 2026-11-20): f1 the newer hair styles, f2 bangs and a second hair colour, f3 aprons and eye colours, f4
-- tinted bakery pieces and a turned held one, f5 the hats that cover the hair or are the head.
local FEATURE_LOOKS: { [string]: { { [string]: any } } } = {
	f1 = {
		{ skin = 1, hair = 1, style = 11, shirt = 1 }, { skin = 2, hair = 2, style = 12, shirt = 2 }, { skin = 3, hair = 3, style = 13, shirt = 3 },
		{ skin = 4, hair = 4, style = 14, shirt = 4 }, { skin = 5, hair = 11, style = 15, shirt = 5 }, { skin = 6, hair = 13, style = 16, shirt = 6 },
		{ skin = 9, hair = 15, style = 17, shirt = 7 }, { skin = 3, hair = 16, style = 18, shirt = 9 },
	},
	f2 = {
		{ skin = 1, hair = 1, style = 1, shirt = 1, bangs = 2 }, { skin = 2, hair = 2, style = 2, shirt = 2, bangs = 3, hair2 = 6 },
		{ skin = 3, hair = 3, style = 9, shirt = 3, bangs = 4 }, { skin = 4, hair = 4, style = 3, shirt = 4, bangs = 5, hair2 = 5 },
		{ skin = 5, hair = 11, style = 15, shirt = 5, bangs = 6 }, { skin = 6, hair = 13, style = 4, shirt = 6, bangs = 7, hair2 = 8 },
		{ skin = 2, hair = 9, style = 5, shirt = 7, bangs = 8 }, { skin = 1, hair = 2, style = 1, shirt = 9, bangs = 9, hair2 = 17 },
	},
	f3 = {
		{ skin = 1, hair = 1, style = 1, shirt = 1, apron = 2, eye = 5 }, { skin = 2, hair = 2, style = 2, shirt = 2, apron = 4, eye = 4, eye2 = 5 },
		{ skin = 3, hair = 3, style = 6, shirt = 3, apron = 10 }, { skin = 4, hair = 4, style = 3, shirt = 4, apron = 11, apronTint = 7 },
		{ skin = 5, hair = 11, style = 7, shirt = 5, apron = 12, eye = 10 }, { skin = 6, hair = 13, style = 4, shirt = 6, apron = 13, eye = 13 },
		{ skin = 2, hair = 9, style = 5, shirt = 7, apron = 15 }, { skin = 1, hair = 2, style = 1, shirt = 9, apron = 16 },
	},
	f4 = {
		{ skin = 1, hair = 1, style = 1, shirt = 1, hat = "beret", hatTint = 9 }, { skin = 2, hair = 2, style = 2, shirt = 2, back = "luna_wings", backTint = 13 },
		{ skin = 3, hair = 3, style = 6, shirt = 3, face = "glasses", faceTint = 2 }, { skin = 4, hair = 4, style = 3, shirt = 4, hat = "strawhat", hatTint = 10 },
		{ skin = 5, hair = 11, style = 7, shirt = 5, top = "tuxedo", topTint = 2 }, { skin = 6, hair = 13, style = 4, shirt = 6, hand = "rain_umbrella", turn = 2 },
		{ skin = 2, hair = 9, style = 5, shirt = 7, hand = "cupcake_treat", turn = 4 }, { skin = 1, hair = 2, style = 1, shirt = 9, back = "bat_wings" },
	},
	f5 = {
		{ skin = 1, hair = 1, style = 1, shirt = 1, hat = "toque" }, { skin = 2, hair = 2, style = 2, shirt = 2, hat = "tall_toque", bangs = 2 },
		{ skin = 3, hair = 3, style = 4, shirt = 3, hat = "cap" }, { skin = 4, hair = 4, style = 5, shirt = 4, hat = "cuffed_beanie" },
		{ skin = 5, hair = 11, style = 12, shirt = 5, hat = "cupcake" }, { skin = 6, hair = 13, style = 3, shirt = 6, hat = "pumpkin_head" },
		{ skin = 2, hair = 9, style = 5, shirt = 7, hat = "headless" }, { skin = 1, hair = 2, style = 1, shirt = 9, hat = "cat_ears" },
	},
}
local function looksScenario(arg)
	seedProfile(64, 1, {})
	local p = join(64, "Dresser")
	settle(p, 30, 1)
	local Cosmetics = H.sharedServer("Data.Cosmetics")
	local Looks = H.sharedServer("Data.Looks")
	local Titles = H.sharedServer("Data.Titles")
	local ctx = E.clientCtx(p)
	local CM = E.moduleIn(ctx, E.find("ReplicatedStorage.Shared.Models.CharacterModels"))
	local Blocks = E.moduleIn(ctx, E.find("ReplicatedStorage.Shared.Models.Blocks"))
	local PR = H.cmod(p, "Pixel.PixelRenderer")
	local CC = H.cmod(p, "Controllers.CameraController")
	local NT = H.cmod(p, "Controllers.NameTags")
	for _, g in p.PlayerGui:GetChildren() do
		if g:IsA("ScreenGui") and g.Name ~= "PixelLayer" and g.Name ~= "SkyBackdrop" and g.Name ~= "World" then
			g.Enabled = false
		end
	end
	local looks = {}
	local n = tonumber(arg)
	for k = 1, if FEATURE_LOOKS[arg] then 0 else 8 do
		local look = {}
		if n then
			local i = (n - 1) * 8 + k
			look = { skin = (i - 1) % #Looks.skin + 1, hair = (i * 3) % #Looks.hair + 1, style = (i - 1) % #Looks.styles + 1, shirt = (i - 1) % #Looks.shirt + 1 }
			for _, slot in Looks.worn do
				local list = Cosmetics.bySlot[slot]
				look[slot] = list[(i - 1) % #list + 1].id
			end
		else
			local ids = {}
			for id in string.gmatch(arg, "[^,]+") do
				table.insert(ids, id)
			end
			local id = ids[k]
			if id == nil then
				break
			end
			look = { skin = k % #Looks.skin + 1, hair = k % #Looks.hair + 1, style = k % #Looks.styles + 1, shirt = k % #Looks.shirt + 1 }
			local c = Cosmetics.byId[id]
			if c then
				look[c.slot] = id
			end
		end
		table.insert(looks, look)
	end
	for _, look in FEATURE_LOOKS[arg] or {} do
		table.insert(looks, look)
	end
	local OX, OZ = 0, 9400
	local ux, uz = math.sqrt(0.5), -math.sqrt(0.5)
	local vx, vz = math.sqrt(0.5), math.sqrt(0.5)
	local faceViewer = math.atan2(vx, vz)
	H.inClient(p, function()
		local m = Blocks.model(E.workspace, "LooksLawn")
		Blocks.part(m, { size = E.v3(30, 1, 30), cf = E.cf.new(OX, -0.5, OZ), color = "grass" })
	end)
	-- a row of four at a time (the tags of a row in front would cover the faces behind)
	for row = 1, 2 do
		local things = {}
		H.inClient(p, function()
			local names = {}
			for k = 1, 4 do
				local i = (row - 1) * 4 + k
				local look = looks[i]
				if look == nil then
					break
				end
				local rig = CM.buildStanding(look, "Look_" .. i, i * 7)
				rig.model.Parent = E.workspace
				PR.registerDynamic(rig.model, if i == 1 then "self" else "player")
				local u = -5.4 + (k - 1) * 3.6
				-- (a stand-in player for the name tag: its name and the title it wears)
				local title = Titles.list[(i * 5) % #Titles.list + 1]
				local fake = { DisplayName = "Founder " .. i, UserId = 70000 + i, GetAttribute = function(_, key)
					return if key == "Title" then title.id else nil
				end }
				local tag = NT.make(fake)
				table.insert(things, { rig = rig, tag = tag, x = OX + ux * u, z = OZ + uz * u })
				local c, worn = 0, {}
				for _ in rig.parts do
					c += 1
				end
				for _, slot in Looks.worn do
					if look[slot] then
						table.insert(worn, look[slot])
					end
				end
				table.insert(names, string.format("%d: %s / %s (%d parts, %s)", i, Looks.styles[look.style], table.concat(worn, ","), c, title.name))
			end
			log("looks %s row %d: %s", arg, row, table.concat(names, "; "))
			local pts = {}
			for _, q in { { -7.4, -1.6 }, { 7.4, -1.6 }, { -7.4, 1.6 }, { 7.4, 1.6 } } do
				for _, y in { 0, 6.2 } do
					table.insert(pts, OX + ux * q[1] + vx * q[2])
					table.insert(pts, y)
					table.insert(pts, OZ + uz * q[1] + vz * q[2])
				end
			end
			CC.setStage({ name = "looks" .. row, origin = E.v3(OX, 0, OZ), pts = pts, tight = nil, top = 14, bottom = 8 })
		end)
		if #things == 0 then
			break
		end
		for _, mode in { "stand", "walk" } do
			local function pose()
				for j, x in things do
					CM.poseStanding(x.rig, E.cf.new(x.x, 0, x.z) * E.cf.Angles(0, faceViewer + math.rad(25), 0), 1.3 + j * 0.41, if mode == "walk" then 9 else 0)
				end
			end
			H.inClient(p, pose)
			settle(p, 60, 0.5)
			H.inClient(p, function()
				pose()
				for _, x in things do
					NT.place(x.tag, (E.cf.new(x.x, 0, x.z) * E.cf.new(0, CM.topOf(x.rig) + 0.2, 0)).Position)
				end
			end)
			E.step(E.dt)
			local okR, rims = pcall(PR.debugRims)
			if okR and type(rims) == "table" then
				log("looks row %d %s: %d rims drawn (%d registered), %d white px, %.2f ms", row, mode, rims.drawn, rims.registered, rims.px, rims.ms)
			end
			capture(p, string.format("looks_%d_%s", row, mode))
		end
		H.inClient(p, function()
			for _, x in things do
				PR.unregisterDynamic(x.rig.model)
				x.rig.model:Destroy()
				NT.drop(x.tag)
			end
		end)
	end
	return p
end

-- "anim=<id>" or "anim=<id>:<mood>,<mood>": one driftling up close (built "full") moving on its skeleton
-- (Models/DriftRig, Models/DriftMotion: the request of 2026-11-14, "please use bones and rigging to make more realistic
-- and detailed movement. follow and use as many animation principles when animating as well"). It is posed every
-- frame at 60 a second, so its springs and the blends between moods run as in the game; eight frames are kept through
-- each mood (anim_<mood>_<k>), the mood changing straight from the last (the blend shows in its first frames). The log
-- gives its bones, springs, parts and the parts two bones share.
local function animScenario(arg)
	local id, moodArg = string.match(arg, "^([%w_]+):?([%w_,]*)$")
	seedProfile(63, 1, {})
	local p = join(63, "Animator")
	settle(p, 30, 1)
	local Creatures = H.sharedServer("Data.Creatures")
	local def = Creatures.byId[id or ""] or Creatures.list[1]
	local ctx = E.clientCtx(p)
	local MM = E.moduleIn(ctx, E.find("ReplicatedStorage.Shared.Models.MicroModels"))
	local DR = E.moduleIn(ctx, E.find("ReplicatedStorage.Shared.Models.DriftRig"))
	local Blocks = E.moduleIn(ctx, E.find("ReplicatedStorage.Shared.Models.Blocks"))
	local PR = H.cmod(p, "Pixel.PixelRenderer")
	local CC = H.cmod(p, "Controllers.CameraController")
	for _, g in p.PlayerGui:GetChildren() do
		if g:IsA("ScreenGui") and g.Name ~= "PixelLayer" and g.Name ~= "SkyBackdrop" then
			g.Enabled = false
		end
	end
	local OX, OZ = 0, 9600
	local ux, uz = math.sqrt(0.5), -math.sqrt(0.5)
	local vx, vz = math.sqrt(0.5), math.sqrt(0.5)
	local face = math.atan2(vx, vz) + math.rad(30)
	local th = H.inClient(p, function()
		local m = Blocks.model(E.workspace, "AnimLawn")
		Blocks.part(m, { size = E.v3(16, 1, 16), cf = E.cf.new(OX, -0.5, OZ), color = "grass" })
		local x = MM.species(def.id)
		x.model:SetAttribute("PixelShadow", 1)
		x.model:SetAttribute("PixelGroundY", 0)
		x.model.Parent = E.workspace
		PR.registerDynamic(x.model)
		local pts = {}
		for _, q in { { -2.4, -2.4 }, { 2.4, -2.4 }, { -2.4, 2.4 }, { 2.4, 2.4 } } do
			for _, y in { 0, 3.4 } do
				table.insert(pts, OX + ux * q[1] + vx * q[2])
				table.insert(pts, y)
				table.insert(pts, OZ + uz * q[1] + vz * q[2])
			end
		end
		CC.setStage({ name = "anim", origin = E.v3(OX, 0, OZ), pts = pts, tight = nil, top = 8, bottom = 8 })
		return x
	end)
	local st = H.inClient(p, function()
		MM.animate(th, 0, "idle", 0)
		return DR.stats(th)
	end)
	log("anim %s (%s, gait %s): %d bones, %d springs, %d parts, %d shared by two bones", def.id, def.shape, tostring(th.rig and th.rig.gait), st.bones, st.springs, st.parts, st.shared)
	settle(p, 60, 0.5)
	local GAP: { [string]: number } = { hooray = 0.25, idle = 0.3, walk = 0.0875, cheer = 0.0825, hop = 0.11, peck = 0.21, hurt = 0.1, nap = 0.4, wave = 0.1, dip = 0.375, push = 0.2, attack = 0.1, ko = 0.3 }
	-- ("act_<name>" plays one idle act of DriftMotion through, nine frames from its start to its end; "idlelong" 24 frames of
	-- idle 0.4 s apart)
	local Motion = E.moduleIn(ctx, E.find("ReplicatedStorage.Shared.Models.DriftMotion"))
	local styleName = th.rig and th.rig.style or "default"
	log("anim style %s", tostring(styleName))
	H.inClient(p, function()
		local quiet = table.clone(Motion.style(styleName))
		quiet.acts = {}
		Motion.STYLE.__quiet = quiet
		local orig = Motion.program
		Motion.program = function(mood, t, age, k, gait, tempo, seed, out, style)
			local forced = string.match(mood, "^act_(.+)$")
			if forced then
				local o = orig("idle", t, age, k, gait, tempo, seed, out, "__quiet")
				local A = Motion.ACTS[forced]
				local u = math.clamp((age - 0.1) * tempo / A.dur, 0, 1)
				Motion.act(o, forced, u, t * tempo, 1, style)
				if o.jaw > 0.12 then
					o.open = true
				end
				o.mood = mood
				return o
			end
			if mood == "idlelong" then
				mood = "idle"
			end
			return orig(mood, t, age, k, gait, tempo, seed, out, style)
		end
	end)
	local tempo = H.inClient(p, function()
		return DR.skeleton(th).tempo
	end)
	local moods = {}
	for m in string.gmatch(if moodArg and moodArg ~= "" then moodArg else "idle,walk,cheer,peck,hurt", "[^,]+") do
		table.insert(moods, m)
	end
	local clock = 1
	for _, mood in moods do
		local gap = GAP[mood] or 0.12
		local nf = 8
		local forced = string.match(mood, "^act_(.+)$")
		if forced then
			local dur = H.inClient(p, function()
				return Motion.ACTS[forced].dur
			end)
			nf = 9
			gap = dur / tempo / 8
		elseif mood == "idlelong" then
			nf, gap = 24, 0.4
		end
		for k = 1, nf do
			local steps = math.max(1, math.floor(gap * 60 + 0.5))
			if forced and k == 1 then
				steps = 6
			end
			H.inClient(p, function()
				for _ = 1, steps do
					clock += 1 / 60
					MM.animate(th, clock, mood, (k - 1) / 7)
					MM.place(th, E.cf.new(OX, 0, OZ) * E.cf.Angles(0, face, 0))
				end
			end)
			E.step(E.dt)
			capture(p, string.format("anim_%s_%d", mood, k))
			local sp = H.inClient(p, function()
				return DR.debugSprings(th)
			end)
			local bits = {}
			for name, a in sp do
				table.insert(bits, name .. " " .. a)
			end
			table.sort(bits)
			log("anim %s %d: springs %s", mood, k, table.concat(bits, ", "))
		end
	end
	return p
end

------------------------------------------------------------------ run
local list = if scenario == "all" then { "island", "village", "island3", "city", "sky", "build", "day" } else { scenario }
for _, name in list do
	local fn = SCEN[name]
	local panel = string.match(name, "^panel=([%w:]+)$")
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
	local animArg = string.match(name, "^anim=([%w_:,]+)$")
	if animArg then
		fn = function()
			return animScenario(animArg)
		end
	end
	local looksArg = string.match(name, "^looks=([%w_,]+)$")
	if looksArg then
		fn = function()
			return looksScenario(looksArg)
		end
	end
	local palsArg = string.match(name, "^pals=([%w_,%.]+)$")
	if palsArg then
		fn = function()
			return palsScenario(palsArg)
		end
	end
	-- (palsw=: the same, built at the islands' lighter level of detail)
	local palswArg = string.match(name, "^palsw=([%w_,%.]+)$")
	if palswArg then
		fn = function()
			return palsScenario(palswArg, "world")
		end
	end
	-- (stress=<n>: the stress walk's first n legs only)
	local stressLegs = string.match(name, "^stress=(%d)$")
	if stressLegs then
		fn = function()
			return SCEN.stress(tonumber(stressLegs))
		end
	end
	local erArg = string.match(name, "^expandrim=([%d:%a]+)$")
	if erArg then
		fn = function()
			return expandRim(erArg)
		end
	end
	local twArg = string.match(name, "^treewalk=?([%d:%a]*)$")
	if twArg then
		fn = function()
			return treeWalk(twArg)
		end
	end
	local epArg = string.match(name, "^expandperf=(%d+)$")
	if epArg then
		fn = function()
			return expandPerf(tonumber(epArg) :: number)
		end
	end
	local showArg = string.match(name, "^showcase=(%d+)$")
	if showArg then
		fn = function()
			return showcaseScenario(tonumber(showArg) :: number)
		end
	end
	local tiArg, tiTier, tiTurn = string.match(name, "^treeink=(%d+),?(%d*),?(%d*)$")
	if tiArg then
		fn = function()
			return SCEN.treeink(tonumber(tiArg), tonumber(tiTier), tonumber(tiTurn))
		end
	end
	local zoomArg = string.match(name, "^zoom=(%d+)$")
	if zoomArg then
		fn = function()
			return zoomScenario(tonumber(zoomArg) :: number)
		end
	end
	local scArg = string.match(name, "^screen=(%d+)$")
	if scArg then
		fn = function()
			return SCEN.screen(scArg)
		end
	end
	local tbArg = string.match(name, "^treebake=?(%d*)$")
	if tbArg then
		fn = function()
			return treeBake(tbArg)
		end
	end
	local tsArg = string.match(name, "^treesplit=?(%d*)$")
	if tsArg then
		fn = function()
			return treeSplit(tsArg)
		end
	end
	local laArg = string.match(name, "^ploadingart=(.+)$")
	if laArg then
		fn = function()
			return loadingArtScenario(laArg)
		end
	end
	local wxArg = string.match(name, "^weather=(%a+)$")
	if wxArg then
		fn = function()
			return weatherScenario(wxArg)
		end
	end
	local hatch = string.match(name, "^hatch=(%d%d)$")
	if hatch then
		fn = function()
			return hatchScenario(hatch)
		end
	end
	local picons = string.match(name, "^picons=([%w_,]+)$")
	if picons then
		fn = function()
			return piconsScenario(picons)
		end
	end
	local gthumbs = string.match(name, "^gthumbs=([%w_,:@%.]+)$")
	if gthumbs then
		fn = function()
			return gthumbsScenario(gthumbs)
		end
	end
	local cthumbs = string.match(name, "^cthumbs=([%w_,]+)$")
	if cthumbs then
		fn = function()
			return cthumbsScenario(cthumbs)
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
