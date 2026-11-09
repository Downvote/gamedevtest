-- Byte-Size Studio's preview driver: boots the real server and client scripts in the fake engine (with the real
-- raycast and a pixel-storing EditableImage), drives a scenario and dumps frames for topng.py.
-- Usage: luau preview.luau -a <workdir> <scenario> <device> [tier] [inset]
--   workdir: work/<run> (holds sources.luau); scenario: a SCEN key (below), "panel=<name>", "micro=<idea>[_<mod>]"
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

-- A saved profile for `userId` (put in the fake cloud before they join): office `tier`; opts: board (a list of
-- "idea:mod" cards), games (how many launched games of three commons), project ({ "idea:mod" x3 } and won), coins,
-- found (every board and project card counted), decor ({ id, x, z, rot } wanted spots: owned, and placed where
-- Logic/Plot says they fit, else at the nearest cell that does), tut.
local function cardOf(spec)
	local id, mod = string.match(spec, "^(%w+):?(%w*)$")
	return { id = id, mod = if mod == nil or mod == "" then "plain" else mod }
end

local function seedProfile(userId, tier, opts)
	opts = opts or {}
	local Tuning = H.sharedServer("Config.Tuning")
	local Schema = H.sharedServer("Logic.Schema")
	local Studio = H.sharedServer("Logic.Studio")
	local Ideas = H.sharedServer("Logic.Ideas")
	local now = math.floor(E.now())
	local prof = Schema.default(now, userId)
	prof.office = tier
	prof.coins = opts.coins or 25000
	prof.tut = opts.tut or 0
	local Office = H.sharedServer("Data.Office")
	local desks = #Office.plan(tier).desks
	local rng = H.sharedServer("Logic.Util").newRng(userId)
	while #prof.team < math.min(desks, 3) do
		table.insert(prof.team, Studio.newTeam(rng, 1)[1])
		prof.team[#prof.team].id = #prof.team
		prof.team[#prof.team].desk = #prof.team
	end
	for _, spec in opts.board or {} do
		local c = cardOf(spec)
		table.insert(prof.ideas, c)
		prof.found[Ideas.key(c)] = (prof.found[Ideas.key(c)] or 0) + 1
		prof.stats.best = math.max(prof.stats.best, Ideas.oneIn(c))
	end
	for g = 1, opts.games or 0 do
		local cards = { cardOf("action"), cardOf("puzzle:turbo"), cardOf("space") }
		if g % 3 == 0 then
			cards[2] = cardOf("rpg:shaky")
		end
		local wins = g % 4
		local game = { id = g, title = Ideas.title(cards, g * 13), ideas = cards, rate = Ideas.rate(cards, math.min(3, wins)), wins = math.min(3, wins), at = now }
		table.insert(prof.games, game)
		prof.rate += game.rate
		prof.nextGame = g + 1
		prof.stats.games = g
		for _, c in cards do
			prof.found[Ideas.key(c)] = (prof.found[Ideas.key(c)] or 0) + 1
		end
	end
	if opts.project then
		local cards = {}
		for _, spec in opts.project do
			table.insert(cards, cardOf(spec))
		end
		prof.project = { title = Ideas.title(cards, 7), ideas = cards, won = opts.won or { -1, -1, -1 }, seed = 7 }
	end
	prof.upgrades = opts.upgrades or { speed = 3, luck = 2 }
	if opts.decor then
		local Plot = H.sharedServer("Logic.Plot")
		for _, d in opts.decor do
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

local BOARD = { "action", "puzzle:turbo", "animals", "space:tiny", "pirates", "rpg:shaky", "cooking", "ocean:glitched", "horror", "school" }

------------------------------------------------------------------ scenarios
local SCEN = {}

-- A brand-new studio: the garage with its idea team, a first idea or two popping out of their heads, the HUD.
function SCEN.office()
	local p = join(1, "Pixel")
	settle(p)
	E.run(9)
	E.run(0.4)
	capture(p, "office")
	return p
end

-- A studio at work: a board of ideas, games earning, and a Mythic idea's reveal dropping in.
function SCEN.reveal()
	seedProfile(2, 1, { board = BOARD, games = 6 })
	local p = join(2, "Lucky")
	settle(p)
	local s = H.session(p)
	E.call(E.serverCtx, 5, function()
		H.smod("Session").fx(s, { kind = "idea", card = { id = "music", mod = "haunted" }, slot = 0, oneIn = 1500000, tier = 6, first = true })
	end)
	E.run(0.6)
	capture(p, "reveal")
	return p
end

local function officeScenario(tier, label)
	return function()
		seedProfile(10 + tier, tier, { board = BOARD, games = 12 })
		local p = join(10 + tier, "Studio" .. tier)
		settle(p)
		E.run(1.5)
		capture(p, label)
		return p
	end
end
SCEN.office2 = officeScenario(2, "office2")
SCEN.office3 = officeScenario(3, "office3")

-- A UI panel by name (UIKit.openPanel); the idea board with three ideas picked.
local function panelScenario(name)
	seedProfile(20, 1, { board = BOARD, games = 9, upgrades = { speed = 6, luck = 4 } })
	local p = join(20, "Menus")
	settle(p)
	local UIKit = modOr(p, "UI.UIKit")
	if UIKit and UIKit.openPanel then
		H.openPanel(p, name)
		E.run(0.8)
		if name == "ideas" then
			for _, i in { 2, 6, 8 } do
				H.clickNamed(p, "Pick_" .. i, { wait = 0.2 })
			end
		end
		log("panel open: %s", tostring(UIKit.currentPanel and UIKit.currentPanel()))
	else
		log("no UIKit.openPanel: capturing the HUD")
	end
	capture(p, "panel_" .. name)
	return p
end

-- Making a game: three ideas picked on the board, Make, the making card.
function SCEN.make()
	seedProfile(30, 1, { board = BOARD, games = 2 })
	local p = join(30, "Maker")
	settle(p)
	H.clickNamed(p, "MakeGame", { wait = 0.6 })
	for _, i in { 1, 6, 9 } do
		H.clickNamed(p, "Pick_" .. i, { wait = 0.2 })
	end
	H.clickNamed(p, "Make", { wait = 1 })
	capture(p, "make")
	return p
end

-- The launch: a game with all three minigames played (two won), Launch! on its card, then the crew cheering.
function SCEN.launch()
	seedProfile(31, 1, { board = BOARD, games = 3, project = { "pirates:turbo", "rpg", "space" }, won = { 1, 0, 1 } })
	local p = join(31, "Shipper")
	settle(p)
	H.clickNamed(p, "CardLaunch", { wait = 0.6 })
	H.clickNamed(p, "Launch", { wait = 1.2 })
	capture(p, "launch")
	H.clickNamed(p, "Nice", { wait = 0.35 })
	capture(p, "launch_cheer")
	return p
end

-- micro=<idea>[_<mod>]: a game being made with that idea first; its microgame on its 3D stage a moment in (after the
-- stage's bake; MicroUI.debugAuto playing: a good player, not a perfect one), then the card back over the street.
local function microScenario(spec)
	local id, mod = string.match(spec, "^(%w+)_?(%w*)$")
	mod = if mod == nil or mod == "" then "plain" else mod
	seedProfile(40, 1, { board = { "action", "puzzle" }, games = 2, project = { id .. ":" .. mod, "space", "school" } })
	local p = join(40, "Player")
	settle(p)
	H.clickNamed(p, "CardPlay", { wait = 0.5 })
	H.clickNamed(p, "Play_1", { wait = 0.1 })
	local MUI = modOr(p, "UI.MicroUI")
	-- the timing games get a right move every frame (they are lost otherwise), the rest one now and then
	local k = 0
	local function autoStep()
		k += 1
		local kind = MUI and H.inClient(p, MUI.playing)
		local every = if kind == "rhythm" or kind == "jump" or kind == "dodge" or kind == "catch" then 1 else 3
		if MUI and k % every == 0 then
			H.inClient(p, MUI.debugAuto)
		end
	end
	-- the stage's picture bakes behind the curtain; the moves start as it lifts
	local function curtainUp(): boolean
		local pg = p:FindFirstChild("PlayerGui")
		local c = pg and pg:FindFirstChild("Curtain", true)
		return c == nil or (getD(c).props.BackgroundTransparency or 0) >= 0.99
	end
	local waited = 0
	while waited < 60 and not curtainUp() do
		E.run(0.05)
		waited += 0.05
		autoStep()
	end
	local PR = modOr(p, "Pixel.PixelRenderer")
	local st = PR and select(2, pcall(PR.debugStatic))
	log("curtain up after %.1fs; playing: %s; the stage's bake %s (%s bakes, %s rays)", waited, tostring(MUI and H.inClient(p, MUI.playing)),
		if type(st) == "table" and st.baking then "still under way" else "done", tostring(type(st) == "table" and st.bakes), tostring(type(st) == "table" and st.rays))
	local stop = E.SIM.now + 1.6
	while E.SIM.now < stop do
		E.run(0.05)
		autoStep()
	end
	capture(p, "micro_" .. spec)
	E.runUntil(function()
		if MUI then
			H.inClient(p, MUI.debugAuto)
		end
		return H.buttonNamed(p, "Retry_1") ~= nil
	end, 40, 0.05)
	E.run(0.5)
	capture(p, "micro_" .. spec .. "_card")
	return p
end

------------------------------------------------------------------ the street and the plot (GAME_DESIGN 8, 9)
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
	seedProfile(51, 2, { board = BOARD, games = 8 })
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
	seedProfile(53, 1, { board = BOARD, games = 4 })
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
	prof.coins = 1000000
	prof.tut = 0
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

function SCEN.plot3()
	seedProfile(55, 3, { board = BOARD, games = 20, decor = {
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
	} })
	local p = join(55, "Mogul")
	settle(p)
	E.run(1.5)
	capture(p, "plot3")
	return p
end

------------------------------------------------------------------ run
local list = if scenario == "all" then { "office", "reveal", "make", "launch", "street", "build" } else { scenario }
for _, name in list do
	local fn = SCEN[name]
	local panel = string.match(name, "^panel=(%w+)$")
	if panel then
		fn = function()
			return panelScenario(panel)
		end
	end
	local micro = string.match(name, "^micro=([%w_]+)$")
	if micro then
		fn = function()
			return microScenario(micro)
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
