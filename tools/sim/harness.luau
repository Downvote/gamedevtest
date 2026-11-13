-- Harness helpers for Byte-Size Studio's simulations (trimmed from Random Bakery's): module access, client requests,
-- UI driving, this game's invariants (profile and client mirror), findings. The fake engine (loader, engine, inst,
-- classes, services) is game-agnostic.
local E = require("./loader")
local I = require("./inst")
local getD = I.getD

local H = {}
H.E = E
H.findings = {}
H.checks = 0

function H.log(fmt, ...)
	E.out(string.format("[%8.2f] %s", E.SIM.now - E.t0, string.format(fmt, ...)))
end

function H.finding(kind, msg, evidence)
	table.insert(H.findings, { kind = kind, msg = msg, evidence = evidence or "", t = E.SIM.now - E.t0, phase = E.phase })
	E.out(string.format("[%8.2f] ##FINDING [%s] (%s) %s %s", E.SIM.now - E.t0, kind, tostring(E.phase), msg, evidence and ("| " .. tostring(evidence)) or ""))
end

function H.expect(cond, kind, msg, evidence)
	H.checks += 1
	if not cond then
		H.finding(kind, msg, evidence)
	end
	return cond
end

------------------------------------------------------------------ boot / patches
-- Gives every disabled Monetization id ("Key = 0") a unique test id, as a published game would have. Harness-only:
-- the source in the repo is untouched. A Monetization module with no such ids (or empty tables) is fine.
function H.patchMonetizationIds(tree)
	H.ids = {}
	local function walk(n)
		if n.src and n.name == "Monetization" and n.className == "ModuleScript" then
			local id = 1000
			local section = ""
			local ids = {}
			local lines = string.split(n.src, "\n")
			for i, line in lines do
				local sec = string.match(line, "^%s*(%u%a+) = %(?{")
				if sec then
					section = sec
				end
				lines[i] = string.gsub(line, "(%u%w*) = 0([,%s])", function(k, tail)
					id += 1
					ids[section .. "." .. k] = id
					return k .. " = " .. id .. tail
				end)
			end
			n.src = table.concat(lines, "\n")
			H.ids = ids
			return true
		end
		for _, c in n.children or {} do
			if walk(c) then
				return true
			end
		end
		return false
	end
	walk(tree)
end

-- A player joins with a full client and, like Roblox with Players.CharacterAutoLoads on, a character half a second
-- later (the founder AvatarView draws, placed on their own footpath by PlotService). opts.noCharacter: no character
-- at all (the fake engine does not read project properties, so the harness decides); opts.charDelay: another delay.
function H.addPlayer(opts)
	if opts.noCharacter then
		opts.charDelay = 1e9
	elseif opts.charDelay == nil then
		opts.charDelay = 0.5
	end
	if opts.client == nil then
		opts.client = "full"
	end
	return E.addPlayer(opts)
end

------------------------------------------------------------------ modules
function H.smod(name)
	local inst = E.find("ServerScriptService.Server.Services." .. name)
	local e = E.serverCtx.modules[inst]
	return e and e.value
end
function H.sharedServer(path)
	local inst = E.find("ReplicatedStorage.Shared." .. path)
	local e = E.serverCtx.modules[inst]
	if e then
		return e.value
	end
	return E.moduleIn(E.serverCtx, inst)
end
function H.cmod(p, rel)
	local ctx = E.clientCtx(p)
	assert(ctx, "no client for " .. p.Name)
	local inst = ctx.root
	for part in string.gmatch(rel, "[^%.]+") do
		inst = inst:FindFirstChild(part)
		assert(inst, "no client module " .. rel)
	end
	local e = ctx.modules[inst]
	if e then
		return e.value
	end
	return E.moduleIn(ctx, inst)
end
function H.session(p)
	return H.smod("Session").get(p)
end
function H.profile(p)
	local s = H.session(p)
	return s and s.profile
end
function H.view(p)
	local SC = H.cmod(p, "Controllers.StateClient")
	local ok, v = pcall(SC.view)
	return ok and v or nil
end
-- Mark the session dirty after a test changed its profile on the server, and let the view reach the client.
function H.push(p, wait)
	local s = H.session(p)
	if s then
		H.smod("Session").markDirty(s)
	end
	E.run(wait or 0.4)
end

------------------------------------------------------------------ requests (through the real client API)
H.reqLog = {}
-- StateClient.request in the player's client context (exactly what UI code does). Returns the Response.
function H.req(p, action, payload, timeout)
	local ctx = E.clientCtx(p)
	assert(ctx, "no client context for " .. p.Name)
	local SC = H.cmod(p, "Controllers.StateClient")
	local res = E.call(ctx, timeout or 15, function()
		return SC.request(action, payload)
	end)
	table.insert(H.reqLog, { p = p.Name, action = action, ok = res and res.ok, err = res and res.err, t = E.SIM.now - E.t0 })
	if E.verboseReq then
		H.log("REQ %s %s -> %s %s", p.Name, action, tostring(res and res.ok), tostring(res and res.err))
	end
	return res
end
-- Raw remote invocation (bypasses StateClient): the malicious-client path. Returns ok, result-or-error.
function H.raw(p, action, payload, timeout)
	local ctx = E.clientCtx(p)
	local remote = E.find("ReplicatedStorage.Remotes.Request")
	return E.call(ctx, timeout or 15, function()
		return pcall(function()
			return remote:InvokeServer(action, payload)
		end)
	end)
end
function H.rawArgs(p, ...)
	local ctx = E.clientCtx(p)
	local remote = E.find("ReplicatedStorage.Remotes.Request")
	local args = table.pack(...)
	return E.call(ctx, 15, function()
		return pcall(function()
			return remote:InvokeServer(table.unpack(args, 1, args.n))
		end)
	end)
end
function H.signal(p, kind, payload)
	local ctx = E.clientCtx(p)
	local SC = H.cmod(p, "Controllers.StateClient")
	E.call(ctx, 5, function()
		SC.signal(kind, payload)
	end)
end
function H.rawSignal(p, ...)
	local ctx = E.clientCtx(p)
	local remote = E.find("ReplicatedStorage.Remotes.Signal")
	local args = table.pack(...)
	E.call(ctx, 5, function()
		remote:FireServer(table.unpack(args, 1, args.n))
	end)
end

------------------------------------------------------------------ the client's Fx messages
-- Every Fx message a client receives (StateClient.Fx), from now on: H.fxLog[p] = { msg, ... }.
H.fxLog = {}
function H.watchFx(p)
	local SC = H.cmod(p, "Controllers.StateClient")
	local list = {}
	H.fxLog[p] = list
	H.inClient(p, function()
		SC.Fx:Connect(function(msg)
			table.insert(list, msg)
		end)
	end)
	return list
end

------------------------------------------------------------------ UI driving
local function guiVisible(g)
	local cur = g
	while cur do
		local d = getD(cur)
		if I.isA(d.cls, "GuiObject") and d.props.Visible == false then
			return false
		end
		if I.isA(d.cls, "LayerCollector") then
			return d.props.Enabled ~= false
		end
		cur = d.props.Parent
	end
	return false
end
H.guiVisible = guiVisible
local function textsOf(b)
	local out = { getD(b).props.Text or "" }
	for _, x in I.descendants(b, {}) do
		local xd = getD(x)
		if xd.cls == "TextLabel" then
			table.insert(out, xd.props.Text or "")
		end
	end
	return out
end
H.textsOf = textsOf
-- Visible buttons in the player's PlayerGui whose text (or a child label) matches `pattern` (plain, case-insensitive).
function H.buttons(p, pattern, includeDisabled)
	local pg = p:FindFirstChild("PlayerGui")
	local out = {}
	for _, x in I.descendants(pg, {}) do
		local xd = getD(x)
		if (xd.cls == "TextButton" or xd.cls == "ImageButton") and guiVisible(x) then
			local enabled = xd.props.AutoButtonColor ~= false
			if enabled or includeDisabled then
				if pattern == nil then
					table.insert(out, x)
				else
					for _, t in textsOf(x) do
						if string.find(string.lower(t), string.lower(pattern), 1, true) then
							table.insert(out, x)
							break
						end
					end
				end
			end
		end
	end
	return out
end
function H.click(p, pattern, opts)
	opts = opts or {}
	local list = H.buttons(p, pattern, opts.includeDisabled)
	local b = list[opts.index or 1]
	if not b then
		if not opts.optional then
			local vis = {}
			for _, x in H.buttons(p, nil, true) do
				local t = table.concat(textsOf(x), "/")
				if #t > 0 then
					table.insert(vis, t)
				end
			end
			H.finding("ui-driver", "no visible button matching '" .. pattern .. "'", "visible: " .. string.sub(table.concat(vis, " | "), 1, 900))
		end
		return false
	end
	if E.verboseUi then
		H.log("CLICK %s '%s'", p.Name, table.concat(textsOf(b), "/"))
	end
	I.fire(I.getSig(b, "Activated"), nil, 1)
	I.fire(I.getSig(b, "MouseButton1Click"))
	E.flushDeferred()
	E.run(opts.wait or 0.6)
	return true
end
-- Dismisses the cards the HUD puts up (the reviews, the awards night: they hold the game clock until dismissed) by
-- their buttons' words. Returns how many it dismissed.
H.CARD_WORDS = { "Nice!", "Got it", "OK" }
function H.dismissCards(p, max)
	local n = 0
	for _ = 1, max or 6 do
		local hit = false
		for _, w in H.CARD_WORDS do
			local list = H.buttons(p, w)
			if #list > 0 then
				I.fire(I.getSig(list[1], "Activated"), nil, 1)
				E.flushDeferred()
				E.run(0.3)
				n += 1
				hit = true
				break
			end
		end
		if not hit then
			break
		end
	end
	return n
end
-- The visible button named `name` (its Instance name: Menu_build, Place, BuildDone...), or nil.
function H.buttonNamed(p, name, includeDisabled)
	for _, x in H.buttons(p, nil, includeDisabled) do
		if getD(x).props.Name == name then
			return x
		end
	end
	return nil
end
function H.clickNamed(p, name, opts)
	opts = opts or {}
	local b = H.buttonNamed(p, name, opts.includeDisabled)
	if not b then
		if not opts.optional then
			H.finding("ui-driver", "no visible button named '" .. name .. "'")
		end
		return false
	end
	I.fire(I.getSig(b, "Activated"), nil, 1)
	I.fire(I.getSig(b, "MouseButton1Click"))
	E.flushDeferred()
	E.run(opts.wait or 0.6)
	return true
end
function H.dumpButtons(p, label)
	local vis = {}
	for _, x in H.buttons(p, nil, true) do
		local t = table.concat(textsOf(x), "/")
		if #t > 0 then
			table.insert(vis, t .. (if getD(x).props.AutoButtonColor == false then "[off]" else ""))
		end
	end
	H.log("BUTTONS %s: %s", label or "", table.concat(vis, " | "))
end
function H.inClient(p, fn, ...)
	return E.call(E.clientCtx(p), 15, fn, ...)
end
function H.openPanel(p, name, arg)
	local UIKit = H.cmod(p, "UI.UIKit")
	H.inClient(p, function()
		UIKit.openPanel(name, arg)
	end)
	E.run(0.4)
end
function H.closePanel(p)
	local UIKit = H.cmod(p, "UI.UIKit")
	H.inClient(p, function()
		UIKit.closePanel()
	end)
	E.run(0.2)
end
function H.currentPanel(p)
	local UIKit = H.cmod(p, "UI.UIKit")
	return UIKit.currentPanel()
end

------------------------------------------------------------------ invariants (Types.Profile / ClientView)
local function finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
H.finite = finite

-- The profile is valid: finite non-negative stores, pieces that fit the island with unique uids,
-- driftlings with unique ids working only where they may (a driftling from a hut, Tuning.HelpMax a building), the huts
-- within their room, one Tree of Life with its eggs in range, no food, no level left on anyone, the tips in range.
function H.checkProfile(p, label)
	local prof = H.profile(p)
	if not H.expect(prof ~= nil, "profile", label .. ": no profile") then
		return
	end
	local Tuning = H.sharedServer("Config.Tuning")
	local Buildings = H.sharedServer("Data.Buildings")
	local Creatures = H.sharedServer("Data.Creatures")
	local Office = H.sharedServer("Data.Office")
	local Traits = H.sharedServer("Data.Traits")
	local Plot = H.sharedServer("Logic.Plot")
	local Island = H.sharedServer("Logic.Island")
	for _, k in { "shells", "wood", "day", "tier", "nextId", "tut", "quest" } do
		H.expect(finite(prof[k]), "profile", string.format("%s: %s is not a finite number", label, k), tostring(prof[k]))
	end
	H.expect(prof.shells >= 0 and prof.wood >= 0, "profile", label .. ": a negative store", string.format("%s %s", tostring(prof.shells), tostring(prof.wood)))
	H.expect(prof.food == nil and prof.tree == nil, "profile", label .. ": food or the old tree levels left in the save")
	H.expect(Office.plans[prof.tier] ~= nil, "profile", label .. ": tier out of range", tostring(prof.tier))
	for _, k in { "boat", "chart", "cap", "pouch", "islets", "sea", "wilds" } do
		H.expect(prof[k] == nil, "profile", label .. ": " .. k .. " left in the save (gone with the expeditions)")
	end
	H.expect(prof.tut >= 0 and prof.tut <= 6, "profile", label .. ": tips out of range", tostring(prof.tut))
	-- the pieces: one Tree of Life, the rest within the island's limits (each count to its own: the pieces, the tiles
	-- (paths and water together), the fences); tiles and fences on the even grid, fences east or south
	local placed = prof.plot.placed
	local n: { [string]: number } = { piece = 0, tile = 0, fence = 0, fixed = 0 }
	for _, q in placed do
		local g = Plot.group(q.id)
		n[g] = (n[g] or 0) + 1
		if g == "tile" or g == "fence" then
			H.expect(q.x % 2 == 0 and q.z % 2 == 0, "profile", label .. ": a tile or fence off the even grid", string.format("%s at %d,%d", q.id, q.x, q.z))
		end
		if g == "fence" then
			H.expect(q.rot == 0 or q.rot == 90, "profile", label .. ": a fence turned " .. tostring(q.rot))
		end
	end
	H.expect(n.fixed == 1, "profile", label .. ": one Tree of Life", tostring(n.fixed))
	for _, g in { "piece", "tile", "fence" } do
		H.expect(n[g] <= Plot.groupLimit(g, prof.tier), "profile", label .. ": more " .. g .. "s than the island holds", string.format("%d of %d", n[g], Plot.groupLimit(g, prof.tier)))
	end
	-- the tree's eggs: no more than it lays, ids unique and below the next one's, a rarity each, its clock in range
	local c = prof.clutch
	local Tree = H.sharedServer("Logic.Tree")
	if H.expect(type(c) == "table" and type(c.list) == "table", "profile", label .. ": no clutch") then
		H.expect(#c.list <= Tree.count(prof.tier), "profile", label .. ": more eggs than the tree lays", string.format("%d of %d", #c.list, Tree.count(prof.tier)))
		H.expect(finite(c.left) and c.left >= -1 and c.left <= Tuning.EggSecs + 1, "profile", label .. ": the eggs' clock out of range", tostring(c.left))
		local eggIds = {}
		for _, e in c.list do
			H.expect(e.id > 0 and e.id < c.next and not eggIds[e.id] and e.r >= 1 and e.r <= 5 and e.r == math.floor(e.r), "profile", label .. ": a bad egg", string.format("%s r%s", tostring(e.id), tostring(e.r)))
			eggIds[e.id] = true
		end
	end
	local uids = {}
	local rest = {}
	for i, q in placed do
		H.expect(Buildings.byId[q.id] ~= nil, "profile", label .. ": an unknown piece", tostring(q.id))
		H.expect(q.uid > 0 and q.uid < prof.nextId and not uids[q.uid], "profile", label .. ": a bad or shared uid", tostring(q.uid))
		uids[q.uid] = q
		H.expect(q.lvl >= 1 and q.lvl <= #Tuning.UpgradeMult, "profile", label .. ": a bad level", tostring(q.lvl))
		local ok = Plot.fits(prof.tier, rest, q.id, q.x, q.z, q.rot)
		H.expect(ok, "profile", label .. ": piece " .. i .. " does not fit", string.format("%s at %d,%d", q.id, q.x, q.z))
		table.insert(rest, q)
	end
	-- driftlings (no villagers since 2026-11-12)
	H.expect(prof.folk == nil, "profile", label .. ": villagers in the save (they're gone)")
	local ids = {}
	local helps = {}
	local inHut = {}
	local noHut = 0
	for _, x in prof.pals do
		H.expect(x.id > 0 and x.id < prof.nextId and not ids[x.id] and not uids[x.id], "profile", label .. ": a bad or shared driftling id", tostring(x.id))
		ids[x.id] = true
		local d = Creatures.byId[x.sp]
		H.expect(d ~= nil, "profile", label .. ": an unknown species", tostring(x.sp))
		H.expect(x.lvl == nil and x.xp == nil, "profile", label .. ": a driftling with a level (levels are gone)")
		H.expect((prof.seen[x.sp] or 0) == 2, "profile", label .. ": a driftling not in the Index", tostring(x.sp))
		local clean = Traits.clean(x.muts)
		H.expect(type(x.muts) == "table" and #clean == #x.muts, "profile", label .. ": a driftling's mutations not a clean list (known, a family once, at most four)", tostring(x.muts and #x.muts))
		H.expect(x.held == nil, "profile", label .. ": a hold left on a driftling (the pen is gone)")
		if x.home == 0 then
			noHut += 1
			H.expect(x.work == 0, "profile", label .. ": a driftling with no hut at work", tostring(x.work))
		else
			local hq = uids[x.home]
			local hd = hq and Buildings.byId[hq.id]
			H.expect(hd ~= nil and hd.kind == "nest", "profile", label .. ": a driftling in a hut that isn't one", tostring(x.home))
			inHut[x.home] = (inHut[x.home] or 0) + 1
		end
		if x.work ~= 0 then
			local q = uids[x.work]
			local b = q and Buildings.byId[q.id]
			-- (any workplace, whatever its knack: a farm, a lumber camp or a shop)
			H.expect(b ~= nil and d ~= nil and (b.kind == "farm" or b.kind == "wood" or b.kind == "shop") and (helps[x.work] or 0) < Tuning.HelpMax, "profile", label .. ": a driftling at a bad or full spot", tostring(x.work))
			helps[x.work] = (helps[x.work] or 0) + 1
		end
	end
	for uid, n in inHut do
		local q = uids[uid]
		local hd = q and Buildings.byId[q.id]
		H.expect(hd ~= nil and n <= hd.slots, "profile", label .. ": a hut over its room", string.format("%d in %s", n, tostring(q and q.id)))
	end
	-- (one with no hut only waits while every hut is full)
	if noHut > 0 then
		local room = 0
		for uid, q in uids do
			local hd = Buildings.byId[q.id]
			if hd and hd.kind == "nest" then
				room += hd.slots - (inHut[uid] or 0)
			end
		end
		H.expect(room == 0, "profile", label .. ": a driftling with no hut while a hut has room", string.format("%d waiting, %d room", noHut, room))
	end
	for k, n in prof.seen do
		H.expect(Creatures.byId[k] ~= nil and (n == 1 or n == 2), "profile", label .. ": a bad Index entry", tostring(k))
	end
end

-- The client's view mirrors the server's profile (the stores may trail by a tick).
function H.checkMirror(p, label)
	local prof = H.profile(p)
	local v = H.view(p)
	if not H.expect(prof ~= nil and v ~= nil, "mirror", label .. ": no profile or no view") then
		return
	end
	for _, k in { "tier", "tut", "day" } do
		H.expect(v[k] == prof[k], "mirror", string.format("%s: view.%s differs", label, k), string.format("view %s, server %s", tostring(v[k]), tostring(prof[k])))
	end
	local r = H.sharedServer("Logic.Island").rates(prof)
	local tick = H.sharedServer("Config.Tuning").TurnSeconds
	for _, k in { "shells", "wood" } do
		local slack = math.max(2, math.abs(r[k]) * 2 / tick + 1)
		H.expect(math.abs(v[k] - prof[k]) <= slack, "mirror", string.format("%s: view %s differ by more than a tick", label, k), string.format("%s vs %s", tostring(v[k]), tostring(prof[k])))
	end
	-- (the view holds every driftling)
	H.expect(#v.pals == #prof.pals and v.folk == nil and v.penN == nil and v.tree == nil, "mirror", label .. ": driftlings differ", string.format("%d vs %d", #v.pals, #prof.pals))
	H.expect(#v.pieces == #prof.plot.placed, "mirror", label .. ": pieces differ", string.format("%d vs %d", #v.pieces, #prof.plot.placed))
	-- (the tree's eggs: the same ones, each with its price on this island)
	local Tree = H.sharedServer("Logic.Tree")
	local same = type(v.clutch) == "table" and #v.clutch == #prof.clutch.list
	if same then
		for i, e in prof.clutch.list do
			local c = v.clutch[i]
			same = same and c ~= nil and c.id == e.id and c.r == e.r and c.cost == Tree.cost(prof, e.r)
		end
	end
	H.expect(same, "mirror", label .. ": the eggs differ", string.format("%d vs %d", type(v.clutch) == "table" and #v.clutch or -1, #prof.clutch.list))
	local homes = {}
	for _, x in prof.pals do
		homes[x.id] = x.home
	end
	for _, x in v.pals do
		H.expect(homes[x.id] == x.home, "mirror", label .. ": a driftling's hut differs", tostring(x.id))
	end
end

function H.errorsSince(i0)
	local out = {}
	for i = i0 + 1, #E.errors do
		table.insert(out, E.errors[i])
	end
	return out
end

-- A deep comparison (nil when equal, else the first path that differs).
function H.diff(a, b, path)
	path = path or ""
	if type(a) ~= type(b) then
		return path .. " (" .. type(a) .. " vs " .. type(b) .. ")"
	end
	if type(a) ~= "table" then
		if a ~= b then
			return path .. " (" .. tostring(a) .. " vs " .. tostring(b) .. ")"
		end
		return nil
	end
	for k, v in a do
		local d = H.diff(v, b[k], path .. "." .. tostring(k))
		if d then
			return d
		end
	end
	for k in b do
		if a[k] == nil then
			return path .. "." .. tostring(k) .. " (missing)"
		end
	end
	return nil
end

return H
