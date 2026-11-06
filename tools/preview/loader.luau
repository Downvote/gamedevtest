-- DataModel construction, per-context module loading, scripts, players/characters/clients, frame stepping.
local E = require("./engine")
local I = require("./inst")
require("./classes")
require("./services")
local v3, v2 = E.v3, E.v2
local CF = E.cf
local typeOf = E.typeof
local Enum = E.Enum
local task = E.task
local getD = I.getD
local REAL_OS = os

------------------------------------------------------------------ contexts
function E.newCtx(kind, name, player)
	return { kind = kind, name = name, player = player, alive = true, modules = {}, globals = nil }
end

local function argsText(...)
	local n = select("#", ...)
	local parts = table.create(n)
	for i = 1, n do
		parts[i] = tostring((select(i, ...)))
	end
	return table.concat(parts, " ")
end

E.patches = {} -- full module name -> { {old, new}, ... } harness-only source patches (e.g. test ids)
-- (Random Bakery patched Locale/Lang here to capture its string catalog; this game's Lang has no catalog yet)
E.langSeen = {}

local function makeGlobals(ctx)
	local G = {}
	-- standard library
	for _, k in { "math", "string", "table", "bit32", "buffer", "utf8", "debug", "pcall", "xpcall", "error", "assert", "select", "type", "tostring", "tonumber", "pairs", "ipairs", "next", "rawget", "rawset", "rawequal", "rawlen", "setmetatable", "getmetatable", "newproxy", "gcinfo" } do
		G[k] = _G[k] or getfenv(0)[k]
	end
	G.unpack = table.unpack
	G.typeof = E.typeof
	G.os = {
		time = function(t)
			if t ~= nil then
				return REAL_OS.time(t)
			end
			return math.floor(E.SIM.now)
		end,
		clock = function()
			return E.simClock()
		end,
		date = function(fmt, t)
			return REAL_OS.date(fmt, t or math.floor(E.SIM.now))
		end,
		difftime = REAL_OS.difftime,
	}
	local co = coroutine
	G.coroutine = {
		create = function(f)
			local th = co.create(f)
			E.tagThread(th, E.curCtx())
			return th
		end,
		wrap = function(f)
			local th = co.create(f)
			E.tagThread(th, E.curCtx())
			return function(...)
				local r = table.pack(co.resume(th, ...))
				if not r[1] then
					error(r[2], 2)
				end
				return table.unpack(r, 2, r.n)
			end
		end,
		resume = co.resume,
		yield = co.yield,
		running = co.running,
		status = co.status,
		isyieldable = co.isyieldable,
		close = co.close,
	}
	G.print = function(...)
		local s = argsText(...)
		table.insert(E.prints, { ctx = ctx.name, text = s, t = E.SIM.now })
		if string.find(s, "handler error", 1, true) then
			E.recordError("signal-handler", s, debug.traceback("", 2), ctx)
		elseif E.verbose then
			E.out(string.format("[%s] %s", ctx.name, s))
		end
	end
	G.warn = function(...)
		local s = argsText(...)
		table.insert(E.warnings, { ctx = ctx.name, text = s, t = E.SIM.now - (E.t0 or E.SIM.now), phase = E.phase })
		E.out(string.format("[%8.2f] WARN (%s): %s", E.SIM.now - (E.t0 or E.SIM.now), ctx.name, s))
	end
	G.tick = function()
		E.issue("contract", "tick() used")
		return E.SIM.now
	end
	G.time = function()
		return E.SIM.now - (E.t0 or E.SIM.now)
	end
	G.elapsedTime = G.time
	G.wait = function(t)
		E.issue("contract", "deprecated global wait() used")
		return task.wait(t)
	end
	G.spawn = function(f)
		E.issue("contract", "deprecated global spawn() used")
		return task.defer(f)
	end
	G.delay = function(t, f)
		E.issue("contract", "deprecated global delay() used")
		return task.delay(t, f)
	end
	G.task = task
	G.game = E.game
	G.workspace = E.workspace
	G.Workspace = E.workspace
	G.Instance = E.Instance
	for k, v in E.types do
		G[k] = v
	end
	G.Enum = E.Enum
	G.shared = setmetatable({}, { __newindex = function(t, k, v)
		E.issue("contract", "shared." .. tostring(k) .. " written")
		rawset(t, k, v)
	end })
	G._G = setmetatable({}, { __newindex = function(t, k, v)
		E.issue("contract", "_G." .. tostring(k) .. " written")
		rawset(t, k, v)
	end })
	G.require = function(m)
		return E.requireIn(ctx, m)
	end
	G.__LANG_SEEN = E.langSeen
	G.loadstring = nil
	G.settings = function()
		E.gap("settings()")
	end
	G.UserSettings = function()
		E.gap("UserSettings()")
	end
	G.DateTime = setmetatable({}, { __index = function(_, k)
		E.gap("DateTime." .. tostring(k))
	end })
	G.BrickColor = setmetatable({}, { __index = function(_, k)
		E.gap("BrickColor." .. tostring(k))
	end })
	G.PhysicalProperties = setmetatable({}, { __index = function(_, k)
		E.gap("PhysicalProperties." .. tostring(k))
	end })
	G.stats = function()
		E.gap("stats()")
	end
	return G
end

local function envFor(ctx, scriptInst)
	if not ctx.globals then
		ctx.globals = makeGlobals(ctx)
	end
	local env = {}
	for k, v in ctx.globals do
		env[k] = v
	end
	env.script = scriptInst
	-- harness-only globals for every script (profiling hooks)
	for k, v in E.extraGlobals or {} do
		env[k] = v
	end
	return env
end

local function compile(inst)
	local d = getD(inst)
	local src = d.src
	if not src then
		error("no source for " .. I.fullName(inst))
	end
	local name = I.fullName(inst)
	local canonical = d.canonical or name
	local p = E.patches[canonical]
	if p then
		for _, pair in p do
			local a, b = pair[1], pair[2]
			local i, j = string.find(src, a, 1, true)
			if not i then
				error("harness patch did not apply to " .. canonical .. ": " .. a)
			end
			src = string.sub(src, 1, i - 1) .. b .. string.sub(src, j + 1)
		end
	end
	local fn, err = loadstring(src, "=" .. name)
	if not fn then
		error("compile error in " .. name .. ": " .. tostring(err))
	end
	return fn
end

function E.requireIn(ctx, m)
	if not I.isInst(m) then
		error("Attempted to call require with invalid argument(s).", 2)
	end
	local d = getD(m)
	if d.cls ~= "ModuleScript" then
		error("Attempted to call require with a non-ModuleScript (" .. d.cls .. ")", 2)
	end
	local cache = ctx.modules
	local entry = cache[m]
	if entry then
		if entry.loading then
			error("Requested module was required recursively: " .. I.fullName(m), 2)
		end
		if entry.failed then
			error("Requested module experienced an error while loading: " .. I.fullName(m), 2)
		end
		return entry.value
	end
	entry = { loading = true }
	cache[m] = entry
	local fn = compile(m)
	setfenv(fn, envFor(ctx, m))
	local res = table.pack(xpcall(fn, debug.traceback))
	entry.loading = false
	if not res[1] then
		entry.failed = true
		E.recordError("module-load", res[2], "", ctx)
		error("Requested module experienced an error while loading: " .. I.fullName(m) .. ": " .. tostring(res[2]), 2)
	end
	if res.n ~= 2 then
		entry.failed = true
		error("Module code did not return exactly one value: " .. I.fullName(m), 2)
	end
	entry.value = res[2]
	return res[2]
end

function E.runScript(ctx, inst)
	local fn = compile(inst)
	setfenv(fn, envFor(ctx, inst))
	local co = E.newThread(function()
		local ok, err = xpcall(fn, debug.traceback)
		if not ok then
			E.recordError("script", err, "", ctx)
		end
	end, ctx)
	E.resume(co)
	E.flushDeferred()
end

------------------------------------------------------------------ DataModel
local SERVICE_LIST = {
	"Workspace", "Players", "ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterPlayer", "StarterGui",
	"StarterPack", "Lighting", "RunService", "TweenService", "UserInputService", "GuiService", "SoundService",
	"TextChatService", "MarketplaceService", "DataStoreService", "AnalyticsService", "BadgeService", "SocialService",
	"PolicyService", "GroupService", "HttpService", "ExperienceNotificationService", "AssetService", "ConfigService",
	"CollectionService", "ContextActionService", "ContentProvider", "ReplicatedFirst",
}
E.services = {}

local function buildNode(node, parent, prefix)
	local inst
	local existing = E.services[node.name]
	if existing and node.className == node.name then
		inst = existing
	else
		inst = I.new(node.className)
		getD(inst).props.Name = node.name
		if node.src then
			getD(inst).src = node.src
			getD(inst).chunkFile = node.file
		end
		inst.Parent = parent
	end
	local canonical = if prefix == "" then node.name else prefix .. "." .. node.name
	getD(inst).canonical = canonical
	for _, c in node.children or {} do
		buildNode(c, inst, canonical)
	end
	return inst
end

function E.boot(tree)
	E.game = I.new("DataModel")
	getD(E.game).props.Name = "Byte-Size Studio"
	for _, name in SERVICE_LIST do
		local s = I.new(name)
		getD(s).props.Name = name
		s.Parent = E.game
		E.services[name] = s
	end
	E.workspace = E.services.Workspace
	local cam = I.new("Camera")
	getD(cam).props.Name = "Camera"
	cam.Parent = E.workspace
	getD(E.workspace).props.CurrentCamera = cam
	E.camera = cam
	-- ground stand-in for raycast hits (not parented: no Interact attribute anywhere above it)
	E.groundPart = I.new("Part")
	getD(E.groundPart).props.Name = "SimGround"
	-- StarterPlayer children
	local sps = I.new("StarterPlayerScripts")
	getD(sps).props.Name = "StarterPlayerScripts"
	sps.Parent = E.services.StarterPlayer
	local scs = I.new("StarterCharacterScripts")
	getD(scs).props.Name = "StarterCharacterScripts"
	scs.Parent = E.services.StarterPlayer
	-- TextChatService channels
	local tcs = I.new("Folder")
	getD(tcs).props.Name = "TextChannels"
	tcs.Parent = E.services.TextChatService
	local gen = I.new("TextChannel")
	getD(gen).props.Name = "RBXGeneral"
	gen.Parent = tcs
	-- project tree
	for _, c in tree.children do
		if c.className == "StarterPlayer" then
			for _, cc in c.children or {} do
				if cc.className == "StarterPlayerScripts" then
					for _, x in cc.children or {} do
						buildNode(x, sps, "StarterPlayer.StarterPlayerScripts")
					end
				end
			end
		else
			buildNode(c, E.game, "")
		end
	end
	E.serverCtx = E.newCtx("server", "server", nil)
	E.t0 = E.SIM.now
end

function E.find(path)
	local cur = E.game
	for part in string.gmatch(path, "[^%.]+") do
		local nxt = cur:FindFirstChild(part)
		if not nxt then
			error("E.find: no " .. part .. " in " .. I.fullName(cur))
		end
		cur = nxt
	end
	return cur
end

function E.startServer()
	E.phase = "server-boot"
	local main = E.find("ServerScriptService.Server.Main")
	E.runScript(E.serverCtx, main)
end

------------------------------------------------------------------ players / characters / clients
local nextPlayerCtx = 0
function E.spawnCharacter(player)
	local pd = getD(player)
	local old = pd.props.Character
	if old then
		old:Destroy()
		-- respawn: PlayerGui children with ResetOnSpawn (default true) are removed (StarterGui is re-cloned)
		local pg = player:FindFirstChild("PlayerGui")
		for _, g in (pg and pg:GetChildren() or {}) do
			local gd = getD(g)
			if I.isA(gd.cls, "LayerCollector") and gd.props.ResetOnSpawn ~= false then
				E.out("[respawn] PlayerGui." .. gd.props.Name .. " reset (ResetOnSpawn)")
				g:Destroy()
			end
		end
	end
	local model = I.new("Model")
	getD(model).props.Name = pd.props.Name
	local root = I.new("Part")
	getD(root).props.Name = "HumanoidRootPart"
	getD(root).props.Size = v3(2, 2, 1)
	getD(root).props.Transparency = 1
	I.setPartCF(root, getD(root), CF.new(0, 50, 0))
	root.Parent = model
	local torso = I.new("Part")
	getD(torso).props.Name = "UpperTorso"
	getD(torso).props.Size = v3(2, 1.6, 1)
	I.setPartCF(torso, getD(torso), CF.new(0, 50.2, 0))
	torso.Parent = model
	local head = I.new("Part")
	getD(head).props.Name = "Head"
	getD(head).props.Size = v3(1.2, 1.2, 1.2)
	I.setPartCF(head, getD(head), CF.new(0, 51.6, 0))
	head.Parent = model
	local hum = I.new("Humanoid")
	getD(hum).props.Name = "Humanoid"
	hum.Parent = model
	getD(model).props.PrimaryPart = root
	I.setRaw(player, "Character", model)
	model.Parent = E.workspace
	I.fire(I.getSig(player, "CharacterAdded"), model)
	E.flushDeferred()
	return model
end

function E.addPlayer(opts)
	local p = I.new("Player")
	local pd = getD(p)
	pd.props.Name = opts.name
	pd.props.DisplayName = opts.displayName or opts.name
	pd.props.LocaleId = opts.locale or E.locale or "en-us" -- (docs/LOCALIZATION.md 2: Auto follows it)
	pd.props.UserId = opts.userId
	pd.props.AccountAge = opts.accountAge or 30
	pd.joinData = opts.joinData or {}
	E.cloud.names[opts.userId] = opts.name
	local pg = I.new("PlayerGui")
	getD(pg).props.Name = "PlayerGui"
	pg.Parent = p
	local bp = I.new("Backpack")
	getD(bp).props.Name = "Backpack"
	bp.Parent = p
	local ps = I.new("PlayerScripts")
	getD(ps).props.Name = "PlayerScripts"
	ps.Parent = p
	p.Parent = E.services.Players
	I.fire(I.getSig(E.services.Players, "PlayerAdded"), p)
	E.flushDeferred()
	local mode = opts.client
	if mode == nil then
		mode = "full"
	end
	if mode then
		E.startClient(p, mode)
	end
	local delay = opts.charDelay or 0.3
	E.schedule(E.now() + delay, function()
		if p.Parent then
			E.spawnCharacter(p)
		end
	end, E.serverCtx)
	return p
end

function E.startClient(p, mode)
	nextPlayerCtx += 1
	local ctx = E.newCtx("client", "client:" .. getD(p).props.Name, p)
	ctx.mode = mode
	E.clientCtxs[p] = { ctx }
	local ps = p:FindFirstChild("PlayerScripts")
	local src = E.find("StarterPlayer.StarterPlayerScripts.Client")
	local copy = src:Clone()
	-- keep canonical names for harness patches
	local function canon(a, b)
		getD(b).canonical = getD(a).canonical
		for i, c in getD(a).children do
			canon(c, getD(b).children[i])
		end
	end
	canon(src, copy)
	copy.Parent = ps
	ctx.root = copy
	if mode == "full" then
		-- ReplicatedFirst's LocalScripts first (the loading card: Roblox runs them before anything else has arrived; here
		-- the whole game is there already), each in this client's context like the PlayerScripts below
		for _, x in I.descendants(E.services.ReplicatedFirst, {}) do
			if getD(x).cls == "LocalScript" then
				E.runScript(ctx, x)
			end
		end
		for _, x in I.descendants(copy, {}) do
			if getD(x).cls == "LocalScript" then
				E.runScript(ctx, x)
			end
		end
	elseif mode == "lite" then
		local co = E.newThread(function()
			local ok, err = xpcall(function()
				local Net = E.requireIn(ctx, E.find("ReplicatedStorage.Shared.Net"))
				Net.clientInit()
				local SC = E.requireIn(ctx, copy.Controllers.StateClient)
				SC.init()
			end, debug.traceback)
			if not ok then
				E.recordError("lite-client", err, "", ctx)
			end
		end, ctx)
		E.resume(co)
		E.flushDeferred()
	end
	return ctx
end

function E.removePlayer(p, reason)
	if p.Parent == nil then
		return
	end
	E.out(string.format("[%8.2f] player %s leaves (%s)", E.SIM.now - E.t0, getD(p).props.Name, tostring(reason)))
	I.fire(I.getSig(E.services.Players, "PlayerRemoving"), p)
	for _, ctx in E.clientCtxs[p] or {} do
		ctx.alive = false
		E.renderBinds[ctx] = nil
		-- client-only instances vanish with the client (they were never replicated)
		for inst in ctx.created or {} do
			local d = getD(inst)
			local parent = d.props.Parent
			if not d.destroyed and parent ~= nil and getD(parent).ctx ~= ctx then
				pcall(inst.Destroy, inst)
			end
		end
	end
	E.clientCtxs[p] = nil
	local char = getD(p).props.Character
	if char then
		char:Destroy()
		I.setRaw(p, "Character", nil)
	end
	p.Parent = nil
	E.flushDeferred()
end

function E.clientCtx(p)
	local l = E.clientCtxs[p]
	return l and l[1]
end

------------------------------------------------------------------ stepping
function E.step(dt)
	E.frame += 1
	E.SIM.now += dt
	E.runTimers()
	E.flushDeferred()
	local RS = E.services.RunService
	for ctx, binds in E.renderBinds do
		if ctx.alive then
			for _, b in table.clone(binds) do
				local co = E.newThread(b.fn, ctx)
				E.resume(co, dt)
			end
		end
	end
	E.flushDeferred()
	I.fireNow(getD(RS).sigs.RenderStepped, dt)
	I.fireNow(getD(RS).sigs.PreRender, dt)
	E.flushDeferred()
	I.fireNow(getD(RS).sigs.Stepped, E.SIM.now - E.t0, dt)
	I.fireNow(getD(RS).sigs.PreSimulation, dt)
	I.fireNow(getD(RS).sigs.PostSimulation, dt)
	E.flushDeferred()
	I.fireNow(getD(RS).sigs.Heartbeat, dt)
	E.flushDeferred()
end

E.dt = 0.1
function E.run(seconds, dt)
	dt = dt or E.dt
	local n = math.max(1, math.floor(seconds / dt + 0.5))
	for _ = 1, n do
		E.step(dt)
	end
end

function E.runUntil(pred, timeout, dt)
	dt = dt or E.dt
	local t = 0
	while t < timeout do
		if pred() then
			return true
		end
		E.step(dt)
		t += dt
	end
	return pred()
end

-- Runs fn(...) in a new thread of ctx and steps the world until it finishes; returns its results.
function E.call(ctx, timeout, fn, ...)
	local done, res = false, nil
	local args = table.pack(...)
	local co = E.newThread(function()
		res = table.pack(xpcall(function()
			return fn(table.unpack(args, 1, args.n))
		end, debug.traceback))
		done = true
	end, ctx)
	E.resume(co)
	E.flushDeferred()
	local t = 0
	while not done and t < timeout do
		E.step(E.dt)
		t += E.dt
	end
	if not done then
		error("E.call timed out after " .. timeout .. "s", 2)
	end
	if not res[1] then
		error("E.call failed: " .. tostring(res[2]), 2)
	end
	return table.unpack(res, 2, res.n)
end

function E.moduleIn(ctx, inst)
	return E.call(ctx, 5, function()
		return E.requireIn(ctx, inst)
	end)
end

return E
