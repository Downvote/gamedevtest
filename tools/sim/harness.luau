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

-- The profile is valid: finite non-negative stores, pieces that fit the island with unique uids, villagers and
-- driftlings with unique ids working only where they may (one a building), within the beds and nests' limits, the
-- islets and the tips in range.
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
	for _, k in { "shells", "food", "wood", "day", "tier", "islets", "nextId", "tut" } do
		H.expect(finite(prof[k]), "profile", string.format("%s: %s is not a finite number", label, k), tostring(prof[k]))
	end
	H.expect(prof.shells >= 0 and prof.food >= 0 and prof.wood >= 0, "profile", label .. ": a negative store", string.format("%s %s %s", tostring(prof.shells), tostring(prof.food), tostring(prof.wood)))
	H.expect(Office.plans[prof.tier] ~= nil, "profile", label .. ": tier out of range", tostring(prof.tier))
	H.expect(prof.islets >= 0 and prof.islets == math.floor(prof.islets), "profile", label .. ": islands charted out of range", tostring(prof.islets))
	H.expect(prof.tut >= 0 and prof.tut <= 8, "profile", label .. ": tips out of range", tostring(prof.tut))
	-- the pieces
	local placed = prof.plot.placed
	local nPaths = 0
	for _, q in placed do
		if Plot.isPath(q.id) then
			nPaths += 1
		end
	end
	H.expect(#placed - nPaths <= Plot.limit(prof.tier) and nPaths <= Plot.pathLimit(prof.tier), "profile", label .. ": more pieces than the island holds", string.format("%d pieces, %d paths", #placed - nPaths, nPaths))
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
	-- villagers and driftlings
	local ids = {}
	local jobs, helps = {}, {}
	H.expect(#prof.folk <= Tuning.FolkMax, "profile", label .. ": too many villagers", tostring(#prof.folk))
	for _, v in prof.folk do
		H.expect(v.id > 0 and v.id < prof.nextId and not ids[v.id] and not uids[v.id], "profile", label .. ": a bad or shared villager id", tostring(v.id))
		ids[v.id] = true
		H.expect(v.lvl >= 1 and v.lvl <= Tuning.LevelMax and finite(v.xp) and v.xp >= 0, "profile", label .. ": a villager's level", tostring(v.lvl))
		if v.work ~= 0 then
			local q = uids[v.work]
			H.expect(q ~= nil and Island.works(q.id) and not jobs[v.work], "profile", label .. ": a villager at a bad or taken job", tostring(v.work))
			jobs[v.work] = true
		end
	end
	for _, x in prof.pals do
		H.expect(x.id > 0 and x.id < prof.nextId and not ids[x.id] and not uids[x.id], "profile", label .. ": a bad or shared driftling id", tostring(x.id))
		ids[x.id] = true
		local d = Creatures.byId[x.sp]
		H.expect(d ~= nil, "profile", label .. ": an unknown species", tostring(x.sp))
		H.expect(x.lvl >= 1 and x.lvl <= Tuning.LevelMax and finite(x.xp) and x.xp >= 0, "profile", label .. ": a driftling's level", tostring(x.lvl))
		H.expect((prof.seen[x.sp] or 0) == 2, "profile", label .. ": a driftling not marked befriended", tostring(x.sp))
		local clean = Traits.clean(x.muts)
		H.expect(type(x.muts) == "table" and #clean == #x.muts, "profile", label .. ": a driftling's mutations not a clean list (known, a family once, at most four)", tostring(x.muts and #x.muts))
		if x.work ~= 0 then
			local q = uids[x.work]
			local b = q and Buildings.byId[q.id]
			H.expect(b ~= nil and d ~= nil and b.knack == d.knack and not helps[x.work], "profile", label .. ": a driftling at a bad or taken spot", tostring(x.work))
			helps[x.work] = true
		end
	end
	H.expect(#prof.pals <= Tuning.PalsMax, "profile", label .. ": too many driftlings", tostring(#prof.pals))
	for k, n in prof.seen do
		H.expect(Creatures.byId[k] ~= nil and (n == 1 or n == 2), "profile", label .. ": a bad Index entry", tostring(k))
	end
	H.expect(finite(prof.cap.lvl) and prof.cap.lvl >= 1 and finite(prof.cap.xp), "profile", label .. ": the captain's level", tostring(prof.cap.lvl))
	-- an expedition under way: its party are the profile's own
	local s = H.session(p)
	local e = s and s.exp
	if e then
		for _, f in e.party do
			local kind, id = string.match(f.key, "^([fvp])(%d*)$")
			H.expect(kind ~= nil and (kind == "f" or ids[tonumber(id)]), "profile", label .. ": a party member not on the island", tostring(f.key))
			H.expect(finite(f.hp) and f.hp >= 0 and f.hp <= f.maxHp, "profile", label .. ": a party member's health", tostring(f.hp))
		end
	end
end

-- The client's view mirrors the server's profile (the stores may trail by a tick).
function H.checkMirror(p, label)
	local prof = H.profile(p)
	local v = H.view(p)
	if not H.expect(prof ~= nil and v ~= nil, "mirror", label .. ": no profile or no view") then
		return
	end
	for _, k in { "tier", "tut", "day", "islets" } do
		H.expect(v[k] == prof[k], "mirror", string.format("%s: view.%s differs", label, k), string.format("view %s, server %s", tostring(v[k]), tostring(prof[k])))
	end
	local r = H.sharedServer("Logic.Island").rates(prof, H.session(p) and H.session(p).away)
	local tick = H.sharedServer("Config.Tuning").TurnSeconds
	for _, k in { "shells", "food", "wood" } do
		local slack = math.max(2, math.abs(r[k]) * 2 / tick + 1)
		H.expect(math.abs(v[k] - prof[k]) <= slack, "mirror", string.format("%s: view %s differ by more than a tick", label, k), string.format("%s vs %s", tostring(v[k]), tostring(prof[k])))
	end
	H.expect(#v.folk == #prof.folk and #v.pals == #prof.pals, "mirror", label .. ": villagers or driftlings differ", string.format("%d/%d vs %d/%d", #v.folk, #v.pals, #prof.folk, #prof.pals))
	H.expect(#v.pieces == #prof.plot.placed, "mirror", label .. ": pieces differ", string.format("%d vs %d", #v.pieces, #prof.plot.placed))
	local s = H.session(p)
	H.expect((v.exp == nil) == (s == nil or s.exp == nil), "mirror", label .. ": the expedition's presence differs")
	if v.exp and s and s.exp then
		H.expect(v.exp.node == s.exp.node and v.exp.islet == s.exp.islet, "mirror", label .. ": the expedition differs")
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
