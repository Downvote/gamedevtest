-- Harness helpers for the preview (a copy of tools/sim/harness.luau over the preview's engine copies); Byte-Size Studio's simulations (trimmed from Random Bakery's): module access, client requests,
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

-- This game never loads characters (Players.CharacterAutoLoads false in default.project.json; the fake engine does
-- not read project properties), so a player joins with no character unless opts.charDelay says otherwise.
function H.addPlayer(opts)
	if opts.charDelay == nil then
		opts.charDelay = 1e9
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

-- The profile is valid: finite numbers, staff within the office's desks on unique desks, energy 0..100, every
-- release's reviews 1..10 summing to its total, the project's weeks and phase consistent.
function H.checkProfile(p, label)
	local prof = H.profile(p)
	if not H.expect(prof ~= nil, "profile", label .. ": no profile") then
		return
	end
	local Tuning = H.sharedServer("Config.Tuning")
	for _, k in { "money", "fans", "rp", "week", "office", "nextStaff", "nextRelease" } do
		H.expect(finite(prof[k]), "profile", string.format("%s: %s is not a finite number", label, k), tostring(prof[k]))
	end
	H.expect(prof.fans >= 0 and prof.rp >= 0 and prof.week >= 0, "profile", label .. ": negative fans/rp/week", string.format("%s/%s/%s", prof.fans, prof.rp, prof.week))
	local spec = Tuning.Offices[prof.office]
	if H.expect(spec ~= nil, "profile", label .. ": office tier out of range", tostring(prof.office)) then
		H.expect(#prof.staff >= 1 and #prof.staff <= spec.desks, "profile", label .. ": staff count outside 1..desks", string.format("%d of %d", #prof.staff, spec.desks))
		local desks, ids = {}, {}
		for _, s in prof.staff do
			H.expect(s.desk >= 1 and s.desk <= spec.desks and not desks[s.desk], "profile", label .. ": desk out of range or shared", tostring(s.desk))
			desks[s.desk] = true
			H.expect(not ids[s.id], "profile", label .. ": staff id used twice", tostring(s.id))
			ids[s.id] = true
			H.expect(s.id < prof.nextStaff, "profile", label .. ": staff id >= nextStaff", tostring(s.id))
			H.expect(finite(s.energy) and s.energy >= 0 and s.energy <= Tuning.EnergyMax, "profile", label .. ": energy outside 0..100", tostring(s.energy))
			for _, k in { "code", "design", "art", "sound" } do
				local v = s.skills[k]
				H.expect(finite(v) and v >= 0 and v <= Tuning.SkillMax, "profile", label .. ": skill out of range " .. k, tostring(v))
			end
		end
	end
	for _, r in prof.releases do
		local sum = 0
		for _, v in r.reviews do
			H.expect(finite(v) and v >= 1 and v <= 10 and v == math.floor(v), "profile", label .. ": review outside 1..10", tostring(v))
			sum += v
		end
		H.expect(#r.reviews == 4 and sum == r.total, "profile", label .. ": reviews do not sum to the total", r.title)
		H.expect(finite(r.copies) and r.copies >= 0 and finite(r.revenue) and r.revenue >= 0, "profile", label .. ": bad sales numbers", r.title)
	end
	H.expect(#prof.releases <= Tuning.ReleasesKept, "profile", label .. ": too many releases kept", tostring(#prof.releases))
	local proj = prof.project
	if proj then
		H.expect(proj.weeksDone >= 0 and (proj.phase == "build") == (proj.weeksDone < proj.buildWeeks), "profile", label .. ": project phase and weeks disagree", string.format("%s %d/%d", proj.phase, proj.weeksDone, proj.buildWeeks))
		H.expect(proj.bugs >= 0, "profile", label .. ": negative bugs")
	end
end

-- The client's view mirrors the server's profile.
function H.checkMirror(p, label)
	local prof = H.profile(p)
	local v = H.view(p)
	if not H.expect(prof ~= nil and v ~= nil, "mirror", label .. ": no profile or no view") then
		return
	end
	for _, k in { "money", "fans", "rp", "week", "office", "tut" } do
		H.expect(v[k] == prof[k], "mirror", string.format("%s: view.%s differs", label, k), string.format("view %s, server %s", tostring(v[k]), tostring(prof[k])))
	end
	H.expect(#v.staff == #prof.staff, "mirror", label .. ": view staff count differs", string.format("%d vs %d", #v.staff, #prof.staff))
	H.expect((v.project == nil) == (prof.project == nil), "mirror", label .. ": project presence differs")
	if v.project and prof.project then
		H.expect(v.project.weeksDone == prof.project.weeksDone and v.project.title == prof.project.title, "mirror", label .. ": project differs")
	end
	local n = math.min(#prof.releases, 30)
	H.expect(#v.releases == n, "mirror", label .. ": view releases differ", string.format("%d vs %d", #v.releases, n))
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
