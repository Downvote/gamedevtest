-- Byte-Size Studio's preview driver: boots the real server and client scripts in the fake engine (with the real
-- raycast and a pixel-storing EditableImage), drives a scenario and dumps frames for topng.py.
-- Usage: luau preview.luau -a <workdir> <scenario> <device> [tier] [inset]
--   workdir: work/<run> (holds sources.luau); scenario: a SCEN key (below), "panel=<name>" or "all";
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
			log("camera: tier %d plot %d, %g art px per stud, pan %d,%d, office box %d,%d - %d,%d (screen px)", v.tier, v.plot, v.grid.a, v.grid.px, v.grid.py, v.box.x0, v.box.y0, v.box.x1, v.box.y1)
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

-- A saved profile for `userId` (put in the fake cloud before they join): office `tier`, `staff` developers, a game
-- in the works when `working`, and `decor` ({ id, x, z, rot } wanted spots: owned, and placed where Logic/Plot says
-- they fit, else at the nearest cell that does).
local function seedProfile(userId, tier, staff, working, decor)
	local Schema = H.sharedServer("Logic.Schema")
	local Crew = H.sharedServer("Logic.Crew")
	local Dev = H.sharedServer("Logic.Dev")
	local Util = H.sharedServer("Logic.Util")
	local Tuning = H.sharedServer("Config.Tuning")
	local now = math.floor(E.now())
	local prof = Schema.default(now, userId)
	local rng = Util.newRng(userId * 31 + 7)
	prof.office = tier
	prof.money = 250000 * tier
	prof.fans = Tuning.Offices[tier].fans + 1200
	prof.week = 52 * (tier - 1) + 9
	prof.tut = 0
	while #prof.staff < staff do
		local id = prof.nextStaff
		table.insert(prof.staff, Crew.hire(Crew.candidate(rng, tier), id, #prof.staff + 1))
		prof.nextStaff += 1
	end
	if working then
		local proj = Dev.newProject("rpg", "fantasy", "pc", "medium", "ideas", "Dragon Legends", prof.week - 4)
		proj.weeksDone = 4
		proj.scores = { fun = 120, ideas = 160, graphics = 90, sound = 70 }
		proj.bugs = 3
		prof.project = proj
		prof.genres.rpg = true
	end
	if decor then
		local Plot = H.sharedServer("Logic.Plot")
		for _, d in decor do
			prof.plot.owned[d.id] = true
			local done = false
			for r = 0, 6 do
				for dz = -r, r do
					for dx = -r, r do
						if not done and (math.abs(dx) == r or math.abs(dz) == r) and Plot.fits(tier, prof.plot.placed, d.id, d.x + dx, d.z + dz, d.rot or 0) then
							table.insert(prof.plot.placed, { id = d.id, x = d.x + dx, z = d.z + dz, rot = d.rot or 0 })
							done = true
						end
					end
				end
			end
			if not done then
				log("seed: %s does not fit near %d,%d", d.id, d.x, d.z)
			end
		end
	end
	local key = Tuning.DataStoreName .. "/global"
	E.cloud.stores[key] = E.cloud.stores[key] or {}
	E.cloud.stores[key]["u_" .. userId] = { value = { data = prof }, meta = {}, userIds = { userId }, version = 1, created = now, updated = now }
end

-- Steps until the next game week has been processed for the player (popups go up then).
local function nextWeek(p)
	local prof = H.profile(p)
	local w = prof.week
	E.runUntil(function()
		return prof.week ~= w
	end, 12, 0.05)
end

------------------------------------------------------------------ scenarios
local SCEN = {}

-- A brand-new studio: the garage with its two developers, the HUD.
function SCEN.office()
	local p = join(1, "Pixel")
	settle(p)
	capture(p, "office")
	return p
end

-- A game in the works: the crew typing, popups over their heads.
function SCEN.dev()
	local p = join(2, "Typer")
	local res = H.req(p, "project.start", { genre = "puzzle", topic = "animals", platform = "pc", size = "small", focus = "fun", seed = 0 })
	log("project.start: %s %s", tostring(res and res.ok), tostring(res and res.err))
	settle(p)
	for _ = 1, 2 do
		nextWeek(p)
	end
	nextWeek(p)
	E.run(0.35)
	capture(p, "dev")
	return p
end

local function officeScenario(tier, staff, label)
	return function()
		seedProfile(10 + tier, tier, staff, true)
		local p = join(10 + tier, "Studio" .. tier)
		settle(p)
		nextWeek(p)
		E.run(0.35)
		capture(p, label)
		return p
	end
end
SCEN.office2 = officeScenario(2, 5, "office2")
SCEN.office3 = officeScenario(3, 8, "office3")

-- A UI panel by name (UIKit.openPanel); without one, just the HUD.
local function panelScenario(name)
	local p = join(20, "Menus")
	-- a game in the works for every panel but the New game wizard (which only shows its steps with none)
	if name ~= "newgame" then
		H.req(p, "project.start", { genre = "action", topic = "space", platform = "pc", size = "small", focus = "fun", seed = 2 })
	end
	settle(p)
	local UIKit = modOr(p, "UI.UIKit")
	if UIKit and UIKit.openPanel then
		H.openPanel(p, name)
		E.run(1)
		log("panel open: %s", tostring(UIKit.currentPanel and UIKit.currentPanel()))
	else
		log("no UIKit.openPanel: capturing the HUD")
	end
	capture(p, "panel_" .. name)
	return p
end

-- The reviews: a finished build released through the HUD's Release button when there is one, else straight through
-- the request (and UI.ReviewUI.show with the release, when that module exists).
function SCEN.review()
	local p = join(30, "Shipper")
	H.req(p, "project.start", { genre = "puzzle", topic = "animals", platform = "pc", size = "small", focus = "fun", seed = 0 })
	settle(p)
	local prof = H.profile(p)
	local proj = prof.project
	if proj then
		proj.weeksDone = proj.buildWeeks
		proj.phase = "polish"
		proj.scores = { fun = 300, ideas = 220, graphics = 240, sound = 150 }
	end
	H.push(p, 1)
	if not H.click(p, "Release", { optional = true, wait = 0.5 }) then
		local res = H.req(p, "project.release", {})
		log("project.release: %s %s", tostring(res and res.ok), tostring(res and res.err))
		local RUI = modOr(p, "UI.ReviewUI")
		if RUI and RUI.show and res and res.ok then
			H.inClient(p, function()
				RUI.show(res.data)
			end)
		end
	end
	E.run(3)
	capture(p, "review")
	return p
end

------------------------------------------------------------------ the street and the plot (GAME_DESIGN 12, 13)
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

-- The founder walked onto the road between two studios (the neighbour in the Loft, at work); then the same pan
-- baked from scratch, to compare a scrolled picture with a fresh one.
function SCEN.street()
	local p = join(50, "Walker")
	seedProfile(51, 2, 5, true)
	join(51, "Neighbour", { client = false })
	settle(p)
	local Street = H.sharedServer("Data.Street")
	local x1 = Street.origin(1)
	local x2 = Street.origin(2)
	walkTo(p, (x1 + x2) / 2 + 6, (Street.ROAD.z0 + Street.ROAD.z1) / 2)
	E.run(0.5)
	settle(p, 10, 0.5)
	capture(p, "street")
	local PR = modOr(p, "Pixel.PixelRenderer")
	if PR and PR.isActive() then
		H.inClient(p, function()
			PR.rebake()
		end)
		settle(p, 40, 1)
		capture(p, "street_fresh")
	end
	return p
end

-- The founder inside the neighbour's office while their crew works.
function SCEN.visit()
	local p = join(52, "Visitor")
	seedProfile(53, 1, 3, true)
	join(53, "Host", { client = false })
	settle(p)
	local x2, z2 = H.sharedServer("Data.Street").origin(2)
	walkTo(p, x2 - 7, z2 + 7)
	capture(p, "visit")
	-- the scrolled picture against a fresh bake at the same pan (only the crew's typing should differ)
	local PR = modOr(p, "Pixel.PixelRenderer")
	if PR and PR.isActive() then
		H.inClient(p, function()
			PR.rebake()
		end)
		settle(p, 40, 1)
		capture(p, "visit_fresh")
	end
	return p
end

-- Build mode: pieces bought and placed, then one picked and its ghost on a cell where it fits (green), then on the
-- office (red).
function SCEN.build()
	local p = join(54, "Builder")
	local prof = H.profile(p)
	prof.money = 200000
	prof.fans = 500
	H.push(p, 0.5)
	for _, id in { "gnome", "flowers", "bush", "bench", "lamp", "oak", "pine", "bikes", "picnic" } do
		local res = H.req(p, "plot.buy", { id = id })
		if not (res and res.ok) then
			log("plot.buy %s: %s", id, tostring(res and res.err))
		end
		E.run(0.12)
	end
	local Plot = H.sharedServer("Logic.Plot")
	local wanted = {
		{ "oak", 14, -6, 0 },
		{ "pine", 19, 1, 0 },
		{ "bench", 13, 14, 0 },
		{ "flowers", -8, 13, 0 },
		{ "picnic", 14, 21, 0 },
		{ "lamp", 9, 12, 0 },
		{ "bush", -14, 22, 0 },
		{ "gnome", 1, 13, 0 },
		{ "bikes", -7, 22, 90 },
		{ "flowers", -2, 22, 0 },
	}
	for _, w in wanted do
		local id, x, z, rot = w[1], w[2], w[3], w[4]
		local okFit = Plot.fits(1, prof.plot.placed, id, x, z, rot)
		if okFit then
			local res = H.req(p, "plot.place", { id = id, x = x, z = z, rot = rot })
			if not (res and res.ok) then
				log("plot.place %s %d,%d: %s", id, x, z, tostring(res and res.err))
			end
		else
			log("plot.place %s %d,%d: does not fit (skipped)", id, x, z)
		end
		E.run(0.12)
	end
	settle(p, 30, 1)
	if not H.clickNamed(p, "Menu_build", { optional = true }) then
		log("no Build button")
	end
	E.run(0.5)
	local BuildUI = modOr(p, "UI.BuildUI")
	local PR = modOr(p, "Pixel.PixelRenderer")
	local Street = H.sharedServer("Data.Street")
	local ox, oz = Street.origin(1)
	local function tapWorld(world)
		H.inClient(p, function()
			local pos = PR.project(world)
			BuildUI.tapScreen(E.v2(pos.X, pos.Y - E.inset), false)
		end)
	end
	if BuildUI and PR then
		H.inClient(p, function()
			BuildUI.pick("oak", 0)
		end)
		-- a fitting cell in the east yard for the oak (3 x 3)
		local cx, cz = 18, 8
		for r = 0, 6 do
			local found = false
			for dz = -r, r do
				for dx = -r, r do
					if not found and Plot.fits(1, prof.plot.placed, "oak", 18 + dx, 8 + dz, 0) then
						cx, cz, found = 18 + dx, 8 + dz, true
					end
				end
			end
			if found then
				break
			end
		end
		tapWorld(E.v3(ox + cx + 1.5, Street.LAWN_Y, oz + cz + 1.5))
		settle(p, 10, 0.5)
		capture(p, "build")
		tapWorld(E.v3(ox + 2, 0, oz + 1))
		settle(p, 10, 0.5)
		capture(p, "build_red")
	end
	return p
end

-- A Studio Floor studio with a dozen pieces of decor on its plot, the home view.
function SCEN.plot3()
	seedProfile(55, 3, 8, true, {
		{ id = "fountain", x = 22, z = 16 },
		{ id = "statue", x = 29, z = 4 },
		{ id = "truck", x = 22, z = 24 },
		{ id = "billboard", x = 19, z = -14 },
		{ id = "dish", x = 30, z = -9 },
		{ id = "kiosk", x = 19, z = 4 },
		{ id = "oak", x = -22, z = 17 },
		{ id = "pine", x = -21, z = 24 },
		{ id = "bench", x = -9, z = 16 },
		{ id = "picnic", x = -3, z = 21 },
		{ id = "flowers", x = 1, z = 16 },
		{ id = "lamp", x = 15, z = 15 },
		{ id = "bush", x = -16, z = 25 },
		{ id = "bikes", x = 4, z = 24 },
	})
	local p = join(55, "Mogul")
	settle(p)
	nextWeek(p)
	E.run(0.35)
	capture(p, "plot3")
	return p
end

------------------------------------------------------------------ run
local list = if scenario == "all" then { "office", "dev", "review", "street", "build" } else { scenario }
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
