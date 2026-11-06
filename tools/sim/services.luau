-- Services for the fake engine: remotes (with Roblox serialization rules), DataStores, Marketplace, Analytics,
-- Badges, Social, Policy, Group, Http, TextChat, notifications, AssetService/EditableImage.
local E = require("./engine")
local I = require("./inst")
local v3, v2 = E.v3, E.v2
local typeOf = E.typeof
local Enum = E.Enum
local task = E.task
local getD = I.getD
local IMPL, GET, SET, DEFAULT, READONLY, INIT = I.IMPL, I.GET, I.SET, I.DEFAULT, I.READONLY, I.INIT

-- persistent "cloud" state (survives player leave/rejoin)
E.cloud = {
	stores = {}, -- name -> { [key] = {value, meta, userIds, version, created, updated} }
	ordered = {}, -- name -> { [key] = number }
	passes = {}, -- userId -> { [passId] = true }
	badges = {}, -- userId -> { [badgeId] = true }
	groups = {}, -- userId -> { [groupId] = true }
	friends = {}, -- "a:b" -> true
	policy = {}, -- userId -> { ArePaidRandomItemsRestricted = bool }
	names = {}, -- userId -> name
	premium = {}, -- userId -> bool
}
E.ds = { latency = 0.12, failNext = 0, failRate = 0, calls = 0, budget = 100 }
E.analytics = { calls = {}, counts = {}, funnels = {}, customNames = {}, skus = {}, currencies = {} }
E.prompts = {}
E.receipts = {}
E.systemMessages = {}
E.invites = {}
E.editableImageMode = "fail" -- "fail" | "nil" | "ok"

local function serverOnly(what)
	if E.curCtx().kind ~= "server" then
		error(what .. " can only be called from the server", 3)
	end
end
local function clientOnly(what)
	if E.curCtx().kind ~= "client" then
		error(what .. " can only be called from the client", 3)
	end
end
local function webYield(sec)
	if coroutine.isyieldable() then
		task.wait(sec or 0.05)
	else
		error("web call from a non-yieldable thread", 3)
	end
end

------------------------------------------------------------------ remote serialization
local DATATYPES = {
	Vector3 = true, Vector2 = true, CFrame = true, Color3 = true, UDim = true, UDim2 = true, EnumItem = true,
	Rect = true, NumberRange = true, NumberSequence = true, ColorSequence = true, Font = true, Content = true, BrickColor = true,
	Ray = true, TweenInfo = true,
}
-- Copies a value the way a RemoteEvent / RemoteFunction would, recording every lossy conversion as an issue.
local function netCopy(v, path, ctx, seen, size)
	local t = typeOf(v)
	if t == "nil" or t == "boolean" then
		size.n += 1
		return v
	elseif t == "string" then
		size.n += #v + 2
		return v
	elseif t == "number" then
		size.n += 8
		if v ~= v or v == math.huge or v == -math.huge then
			E.issue("net-nonfinite", string.format("%s: non-finite number at %s", ctx, path))
		end
		return v
	elseif t == "Instance" then
		size.n += 8
		return v
	elseif DATATYPES[t] then
		size.n += 16
		return v
	elseif t == "table" then
		if seen[v] then
			error(string.format("%s: tables cannot be cyclic (at %s)", ctx, path), 0)
		end
		seen[v] = true
		local mt = getmetatable(v)
		if mt ~= nil then
			E.issue("net-metatable", string.format("%s: metatable stripped at %s", ctx, path))
		end
		local n = #v
		local count, strKeys, intKeys, other = 0, 0, 0, 0
		for k in pairs(v) do
			count += 1
			if type(k) == "string" then
				strKeys += 1
			elseif type(k) == "number" and k == math.floor(k) and k >= 1 and k <= n then
				intKeys += 1
			else
				other += 1
			end
		end
		local out = {}
		if count == 0 then
			size.n += 2
		elseif intKeys == count then
			for i = 1, n do
				out[i] = netCopy(v[i], path .. "[" .. i .. "]", ctx, seen, size)
			end
		elseif intKeys == 0 and other == 0 then
			for k, x in pairs(v) do
				size.n += #k + 1
				out[k] = netCopy(x, path .. "." .. k, ctx, seen, size)
			end
		elseif intKeys > 0 and (strKeys > 0 or other > 0) then
			E.issue("net-mixed", string.format("%s: mixed/sparse table at %s (%d array keys, %d string keys, %d other keys); non-array keys lost", ctx, path, intKeys, strKeys, other))
			for i = 1, n do
				out[i] = netCopy(v[i], path .. "[" .. i .. "]", ctx, seen, size)
			end
		else
			E.issue("net-keys", string.format("%s: dictionary with non-string keys at %s (converted to strings)", ctx, path))
			for k, x in pairs(v) do
				out[tostring(k)] = netCopy(x, path .. "." .. tostring(k), ctx, seen, size)
			end
		end
		seen[v] = nil
		return out
	end
	E.issue("net-type", string.format("%s: %s value at %s cannot be sent (becomes nil)", ctx, t, path))
	return nil
end
local function packCopy(ctxName, ...)
	local n = select("#", ...)
	local outv = { n = n }
	local size = { n = 0 }
	for i = 1, n do
		outv[i] = netCopy((select(i, ...)), "arg" .. i, ctxName, {}, size)
	end
	return outv, size.n
end
E.netCopy = function(v, label)
	return netCopy(v, "value", label or "copy", {}, { n = 0 })
end

------------------------------------------------------------------ remotes
E.clientCtxs = {} -- player -> { ctx, ... }
local function ctxsOf(player)
	return E.clientCtxs[player] or {}
end
local function deliver(remote, sigName, targetCtx, args)
	local d = getD(remote)
	local sig = I.getSig(remote, sigName)
	local delivered = false
	for _, c in table.clone(sig.conns) do
		if c.Connected and c.ctx == targetCtx then
			delivered = true
			E.pushDeferred(c, args)
		end
	end
	if not delivered then
		d.pending = d.pending or {}
		d.pending[targetCtx] = d.pending[targetCtx] or {}
		table.insert(d.pending[targetCtx], { sig = sigName, args = args })
		if #d.pending[targetCtx] == 256 then
			E.issue("remote-queue", string.format("Remote event invocation queue exhausted for %s (%s); no listener", I.fullName(remote), targetCtx.name))
		end
	end
	E.flushDeferred()
end
local function onRemoteConnect(remote, sigName)
	return function(c)
		local d = getD(remote)
		local q = d.pending and d.pending[c.ctx]
		if q then
			d.pending[c.ctx] = nil
			for _, ev in q do
				if ev.sig == sigName then
					E.pushDeferred(c, ev.args)
				end
			end
		end
	end
end
local function remoteSig(remote, name)
	local s = I.getSig(remote, name)
	if not s.onConnect then
		s.onConnect = onRemoteConnect(remote, name)
	end
	return s
end
E.netLog = { c2s = 0, s2c = 0, bytesS2C = 0, bytesC2S = 0 }
-- per remote and message kind (the first argument's string, or its table's t / k field): { n, bytes }
E.netKinds = {}
local function approxSize(v, depth)
	local t = type(v)
	if t == "string" then
		return #v + 2
	elseif t == "number" then
		return 8
	elseif t == "boolean" then
		return 1
	elseif t == "table" and depth < 12 then
		local n = 2
		for k, x in v do
			n += approxSize(k, depth + 1) + approxSize(x, depth + 1)
		end
		return n
	end
	return 4
end
local function netKind(dir, remote, args, size, copies)
	local a = args[1]
	-- a state patch: its ops by key path (the first two levels)
	if type(a) == "table" and a.kind == "patch" and type(a.ops) == "table" then
		for _, op in a.ops do
			local p = op.p or {}
			local key = dir .. " patch:" .. tostring(p[1]) .. (if p[2] ~= nil then ".*" else "")
			local e = E.netKinds[key]
			if not e then
				e = { n = 0, bytes = 0 }
				E.netKinds[key] = e
			end
			e.n += copies
			e.bytes += approxSize(op.v, 0) * copies
		end
	end
	local kind = if type(a) == "string" then a elseif type(a) == "table" then tostring(a.t or a.k or a.key or "?") else "?"
	local key = dir .. " " .. getD(remote).props.Name .. ":" .. kind
	local e = E.netKinds[key]
	if not e then
		e = { n = 0, bytes = 0 }
		E.netKinds[key] = e
	end
	e.n += copies
	e.bytes += size * copies
end
local UNRELIABLE_LIMIT = 900
local function remoteEventImpl(unreliable)
	return {
		FireServer = function(self, ...)
			local ctx = E.curCtx()
			if ctx.kind ~= "client" then
				error("FireServer can only be called from the client", 2)
			end
			local args, size = packCopy("FireServer " .. getD(self).props.Name, ...)
			if unreliable and size > UNRELIABLE_LIMIT then
				E.issue("unreliable-size", string.format("UnreliableRemoteEvent %s payload ~%d bytes > %d: dropped by Roblox", getD(self).props.Name, size, UNRELIABLE_LIMIT))
				return
			end
			E.netLog.c2s += 1
			E.netLog.bytesC2S += size
			netKind("c2s", self, args, size, 1)
			local player = ctx.player
			local remote = self
			E.schedule(E.now() + E.netLatency, function()
				if player.Parent == nil then
					return
				end
				local a = table.pack(player, table.unpack(args, 1, args.n))
				deliver(remote, "OnServerEvent", E.serverCtx, a)
			end, E.serverCtx)
		end,
		FireClient = function(self, player, ...)
			if E.curCtx().kind ~= "server" then
				error("FireClient can only be called from the server", 2)
			end
			if not I.isInst(player) or getD(player).cls ~= "Player" then
				error("FireClient: player argument must be a Player object", 2)
			end
			local args, size = packCopy("FireClient " .. getD(self).props.Name, ...)
			if unreliable and size > UNRELIABLE_LIMIT then
				E.issue("unreliable-size", string.format("UnreliableRemoteEvent %s payload ~%d bytes > %d: dropped by Roblox", getD(self).props.Name, size, UNRELIABLE_LIMIT))
				return
			end
			E.netLog.s2c += 1
			E.netLog.bytesS2C += size
			netKind("s2c", self, args, size, 1)
			local remote = self
			for _, ctx in ctxsOf(player) do
				E.schedule(E.now() + E.netLatency, function()
					if ctx.alive then
						deliver(remote, "OnClientEvent", ctx, args)
					end
				end, ctx)
			end
		end,
		FireAllClients = function(self, ...)
			if E.curCtx().kind ~= "server" then
				error("FireAllClients can only be called from the server", 2)
			end
			local args, size = packCopy("FireAllClients " .. getD(self).props.Name, ...)
			if unreliable and size > UNRELIABLE_LIMIT then
				E.issue("unreliable-size", "UnreliableRemoteEvent payload too large: dropped")
				return
			end
			local remote = self
			local copies = 0
			for _ in E.clientCtxs do
				copies += 1
			end
			E.netLog.s2c += copies
			E.netLog.bytesS2C += size * copies
			netKind("s2c*", self, args, size, copies)
			for player, list in E.clientCtxs do
				for _, ctx in list do
					E.schedule(E.now() + E.netLatency, function()
						if ctx.alive then
							deliver(remote, "OnClientEvent", ctx, args)
						end
					end, ctx)
				end
			end
		end,
	}
end
IMPL.RemoteEvent = remoteEventImpl(false)
IMPL.UnreliableRemoteEvent = remoteEventImpl(true)
I.SIGINIT.BaseRemoteEvent = {
	OnServerEvent = function(remote, s)
		s.onConnect = onRemoteConnect(remote, "OnServerEvent")
	end,
	OnClientEvent = function(remote, s)
		s.onConnect = onRemoteConnect(remote, "OnClientEvent")
	end,
}
I.SIGGUARD.BaseRemoteEvent = {
	OnClientEvent = function(ctx)
		if ctx.kind == "server" then
			error("OnClientEvent can only be used on the client", 3)
		end
	end,
	OnServerEvent = function(ctx)
		if ctx.kind == "client" then
			error("OnServerEvent can only be used on the server", 3)
		end
	end,
}
E.remoteSig = remoteSig

IMPL.RemoteFunction = {
	InvokeServer = function(self, ...)
		local ctx = E.curCtx()
		if ctx.kind ~= "client" then
			error("InvokeServer can only be called from the client", 2)
		end
		local co = coroutine.running()
		if not coroutine.isyieldable() then
			error("InvokeServer from a non-yieldable thread", 2)
		end
		local args, size = packCopy("InvokeServer " .. getD(self).props.Name, ...)
		E.netLog.c2s += 1
		E.netLog.bytesC2S += size
		local player = ctx.player
		local remote = self
		local function call()
			local d = getD(remote)
			local cb = d.props.OnServerInvoke
			if cb == nil then
				-- Roblox queues the invocation until a callback is set
				task.wait(0.1)
				return call()
			end
			if E.invokeHook then
				E.invokeHook("before", player, args)
			end
			local res = table.pack(pcall(cb, player, table.unpack(args, 1, args.n)))
			if E.invokeHook then
				E.invokeHook("after", player, args, res)
			end
			local ok = res[1]
			if not ok then
				E.recordError("OnServerInvoke", res[2], debug.traceback())
			end
			local outv
			if ok then
				outv = packCopy("InvokeServer return " .. d.props.Name, table.unpack(res, 2, res.n))
			end
			E.schedule(E.now() + E.netLatency, function()
				if ok then
					E.resume(co, true, outv)
				else
					E.resume(co, false, res[2])
				end
			end, ctx)
		end
		E.schedule(E.now() + E.netLatency, function()
			if player.Parent == nil then
				return
			end
			call()
		end, E.serverCtx)
		local ok, outv = coroutine.yield()
		if not ok then
			error(outv, 2)
		end
		return table.unpack(outv, 1, outv.n)
	end,
	InvokeClient = function()
		error("CONTRACT: InvokeClient used (ARCHITECTURE 9.1 forbids it)", 2)
	end,
}

------------------------------------------------------------------ JSON (HttpService)
local function jsonEncode(v, seen)
	local t = typeOf(v)
	if t == "nil" then
		return "null"
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return "null"
		end
		if v == math.floor(v) and math.abs(v) < 1e15 then
			return string.format("%d", v)
		end
		return string.format("%.14g", v)
	elseif t == "string" then
		return '"' .. string.gsub(v, '[%c"\\]', function(c)
			local m = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
			return m[c] or string.format("\\u%04x", string.byte(c))
		end) .. '"'
	elseif t == "table" then
		seen = seen or {}
		if seen[v] then
			error("JSONEncode: cyclic table", 0)
		end
		seen[v] = true
		local n = #v
		local count = 0
		for _ in pairs(v) do
			count += 1
		end
		local parts = {}
		local res
		if count == n and (n > 0 or next(v) == nil) then
			for i = 1, n do
				parts[i] = jsonEncode(v[i], seen)
			end
			res = "[" .. table.concat(parts, ",") .. "]"
		else
			for k, x in pairs(v) do
				table.insert(parts, jsonEncode(tostring(k)) .. ":" .. jsonEncode(x, seen))
			end
			res = "{" .. table.concat(parts, ",") .. "}"
		end
		seen[v] = nil
		return res
	end
	error("JSONEncode: cannot encode " .. t, 0)
end
local function jsonDecode(s)
	local pos = 1
	local function ws()
		pos = string.find(s, "[^%s]", pos) or (#s + 1)
	end
	local val
	local function str()
		local out = {}
		pos += 1
		while true do
			local c = string.sub(s, pos, pos)
			if c == "" then
				error("JSONDecode: unterminated string", 0)
			elseif c == '"' then
				pos += 1
				break
			elseif c == "\\" then
				local e = string.sub(s, pos + 1, pos + 1)
				local map = { n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f" }
				if e == "u" then
					table.insert(out, utf8.char(tonumber(string.sub(s, pos + 2, pos + 5), 16)))
					pos += 6
				else
					table.insert(out, map[e] or e)
					pos += 2
				end
			else
				table.insert(out, c)
				pos += 1
			end
		end
		return table.concat(out)
	end
	val = function()
		ws()
		local c = string.sub(s, pos, pos)
		if c == "{" then
			pos += 1
			local t = {}
			ws()
			if string.sub(s, pos, pos) == "}" then
				pos += 1
				return t
			end
			while true do
				ws()
				local k = str()
				ws()
				pos += 1 -- :
				t[k] = val()
				ws()
				local d = string.sub(s, pos, pos)
				pos += 1
				if d == "}" then
					return t
				end
			end
		elseif c == "[" then
			pos += 1
			local t = {}
			ws()
			if string.sub(s, pos, pos) == "]" then
				pos += 1
				return t
			end
			while true do
				table.insert(t, val())
				ws()
				local d = string.sub(s, pos, pos)
				pos += 1
				if d == "]" then
					return t
				end
			end
		elseif c == '"' then
			return str()
		elseif string.sub(s, pos, pos + 3) == "true" then
			pos += 4
			return true
		elseif string.sub(s, pos, pos + 4) == "false" then
			pos += 5
			return false
		elseif string.sub(s, pos, pos + 3) == "null" then
			pos += 4
			return nil
		else
			local num = string.match(s, "^-?[%d%.eE+-]+", pos)
			if not num then
				error("JSONDecode: unexpected character at " .. pos, 0)
			end
			pos += #num
			return tonumber(num)
		end
	end
	local ok, r = pcall(val)
	if not ok then
		error("Can't parse JSON", 2)
	end
	return r
end
E.jsonEncode, E.jsonDecode = jsonEncode, jsonDecode
local guidN = 0
IMPL.HttpService = {
	GenerateGUID = function(self, wrap)
		guidN += 1
		local g = string.format("%08X-%04X-4%03X-8%03X-%012X", 0xA11CE000 + guidN, guidN % 65536, guidN % 4096, (guidN * 7) % 4096, guidN * 7919)
		if wrap == false then
			return g
		end
		return "{" .. g .. "}"
	end,
	JSONEncode = function(self, v)
		return jsonEncode(v)
	end,
	JSONDecode = function(self, s)
		if type(s) ~= "string" then
			error("JSONDecode: string expected", 2)
		end
		return jsonDecode(s)
	end,
	UrlEncode = function(self, s)
		return (string.gsub(s, "[^%w%-_%.~]", function(c)
			return string.format("%%%02X", string.byte(c))
		end))
	end,
	GetAsync = function()
		error("HttpService:GetAsync: Http requests are not enabled (sim)", 2)
	end,
	PostAsync = function()
		error("HttpService:PostAsync: Http requests are not enabled (sim)", 2)
	end,
	RequestAsync = function()
		error("HttpService:RequestAsync: Http requests are not enabled (sim)", 2)
	end,
}

------------------------------------------------------------------ DataStores
local function dsFail(op)
	E.ds.calls += 1
	if E.ds.failNext > 0 then
		E.ds.failNext -= 1
		error("502: API Services rejected request with error. HTTP 500 (sim " .. op .. ")", 3)
	end
	if E.ds.failRate > 0 and math.random() < E.ds.failRate then
		error("502: API Services rejected request (sim random " .. op .. ")", 3)
	end
end
-- JSON-like storage copy: DataStores reject functions/Instances/userdata and non-finite numbers; flag lossy tables
local function storeCopy(v, path, seen)
	local t = typeOf(v)
	if t == "nil" or t == "boolean" or t == "string" then
		return v
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			E.issue("ds-nonfinite", "DataStore value has a non-finite number at " .. path)
		end
		return v
	elseif t == "table" then
		if seen[v] then
			error("104: Cannot store cyclic table in data store (" .. path .. ")", 0)
		end
		seen[v] = true
		local n = #v
		local count, intKeys, strKeys = 0, 0, 0
		for k in pairs(v) do
			count += 1
			if type(k) == "number" and k == math.floor(k) and k >= 1 and k <= n then
				intKeys += 1
			elseif type(k) == "string" then
				strKeys += 1
			end
		end
		local outv = {}
		if count > 0 and intKeys ~= count and strKeys ~= count then
			E.issue("ds-mixed", "DataStore value has a mixed/sparse/non-string-key table at " .. path)
		end
		for k, x in pairs(v) do
			outv[k] = storeCopy(x, path .. "." .. tostring(k), seen)
		end
		seen[v] = nil
		return outv
	end
	error("104: Cannot store " .. t .. " in data store (" .. path .. ")", 0)
end
local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local o = {}
	for k, x in pairs(v) do
		o[k] = deepCopy(x)
	end
	return o
end
E.deepCopy = deepCopy
local function storeOf(d)
	local name = d.storeName
	local s = E.cloud.stores[name]
	if not s then
		s = {}
		E.cloud.stores[name] = s
	end
	return s
end
local function mkKeyInfo(entry)
	local ki = I.new("DataStoreKeyInfo")
	local kd = getD(ki)
	kd.entry = { meta = deepCopy(entry.meta or {}), userIds = deepCopy(entry.userIds or {}) }
	kd.props.Version = tostring(entry.version)
	kd.props.CreatedTime = entry.created * 1000
	kd.props.UpdatedTime = entry.updated * 1000
	return ki
end
IMPL.DataStoreKeyInfo = {
	GetMetadata = function(self)
		return deepCopy(getD(self).entry.meta)
	end,
	GetUserIds = function(self)
		return deepCopy(getD(self).entry.userIds)
	end,
}
local function checkKey(key)
	if type(key) ~= "string" or #key == 0 or #key > 50 then
		error("101: Key name can't be empty or longer than 50 characters", 3)
	end
end
local function runTransform(fn, old, keyInfo)
	local co = coroutine.create(fn)
	local res = table.pack(coroutine.resume(co, old, keyInfo))
	if not res[1] then
		error(res[2], 0)
	end
	if coroutine.status(co) ~= "dead" then
		E.issue("ds-yield", "UpdateAsync transform function yielded")
		error("UpdateAsync callbacks cannot yield", 0)
	end
	return res[2], res[3], res[4]
end
IMPL.GlobalDataStore = {
	GetAsync = function(self, key)
		serverOnly("DataStore:GetAsync")
		checkKey(key)
		webYield(E.ds.latency)
		dsFail("GetAsync")
		local e = storeOf(getD(self))[key]
		if not e then
			return nil, nil
		end
		return deepCopy(e.value), mkKeyInfo(e)
	end,
	SetAsync = function(self, key, value, userIds, options)
		serverOnly("DataStore:SetAsync")
		checkKey(key)
		webYield(E.ds.latency)
		dsFail("SetAsync")
		local st = storeOf(getD(self))
		local e = st[key] or { created = os.time(), version = 0 }
		e.value = storeCopy(value, key, {})
		e.userIds = userIds or {}
		e.version += 1
		e.updated = E.now()
		st[key] = e
		return tostring(e.version)
	end,
	UpdateAsync = function(self, key, fn)
		serverOnly("DataStore:UpdateAsync")
		checkKey(key)
		if type(fn) ~= "function" then
			error("UpdateAsync: function expected", 2)
		end
		webYield(E.ds.latency)
		dsFail("UpdateAsync")
		local st = storeOf(getD(self))
		local e = st[key]
		local old = if e then deepCopy(e.value) else nil
		local ki = if e then mkKeyInfo(e) else nil
		local new, userIds, meta = runTransform(fn, old, ki)
		if new == nil then
			return nil, nil
		end
		if meta ~= nil then
			local okMeta, metaJson = pcall(jsonEncode, meta)
			if okMeta and #metaJson > 300 then
				error("DataStore metadata too large", 0)
			end
		end
		local stored = storeCopy(new, key, {})
		local okSize, json = pcall(jsonEncode, stored)
		if okSize and #json > 4194304 then
			error("105: Serialized value exceeds 4MB limit", 0)
		end
		e = e or { created = E.now(), version = 0 }
		e.value = stored
		e.userIds = deepCopy(userIds or {})
		e.meta = deepCopy(meta or {})
		e.version += 1
		e.updated = E.now()
		st[key] = e
		E.ds.lastSize = if okSize then #json else -1
		return deepCopy(stored), mkKeyInfo(e)
	end,
	RemoveAsync = function(self, key)
		serverOnly("DataStore:RemoveAsync")
		webYield(E.ds.latency)
		dsFail("RemoveAsync")
		local st = storeOf(getD(self))
		local e = st[key]
		st[key] = nil
		return if e then e.value else nil
	end,
	IncrementAsync = function(self, key, delta)
		serverOnly("DataStore:IncrementAsync")
		webYield(E.ds.latency)
		dsFail("IncrementAsync")
		local st = storeOf(getD(self))
		local e = st[key] or { value = 0, created = E.now(), version = 0 }
		e.value = (e.value or 0) + (delta or 1)
		e.updated = E.now()
		st[key] = e
		return e.value
	end,
}
local function orderedOf(d)
	local s = E.cloud.ordered[d.storeName]
	if not s then
		s = {}
		E.cloud.ordered[d.storeName] = s
	end
	return s
end
IMPL.OrderedDataStore = {
	SetAsync = function(self, key, value)
		serverOnly("OrderedDataStore:SetAsync")
		checkKey(key)
		if type(value) ~= "number" or value ~= math.floor(value) or value ~= value then
			error("OrderedDataStore:SetAsync value must be an integer, got " .. tostring(value), 2)
		end
		webYield(E.ds.latency)
		dsFail("OrderedSetAsync")
		orderedOf(getD(self))[key] = value
		return "1"
	end,
	GetAsync = function(self, key)
		webYield(E.ds.latency)
		return orderedOf(getD(self))[key]
	end,
	UpdateAsync = function(self, key, fn)
		serverOnly("OrderedDataStore:UpdateAsync")
		checkKey(key)
		webYield(E.ds.latency)
		dsFail("OrderedUpdateAsync")
		local st = orderedOf(getD(self))
		local new = runTransform(fn, st[key], nil)
		if new ~= nil then
			if type(new) ~= "number" or new ~= math.floor(new) or new ~= new then
				error("OrderedDataStore:UpdateAsync value must be an integer, got " .. tostring(new), 2)
			end
			st[key] = new
		end
		return new
	end,
	RemoveAsync = function(self, key)
		local st = orderedOf(getD(self))
		local v = st[key]
		st[key] = nil
		return v
	end,
	GetSortedAsync = function(self, ascending, pageSize, minV, maxV)
		serverOnly("OrderedDataStore:GetSortedAsync")
		if type(pageSize) ~= "number" or pageSize < 1 or pageSize > 100 then
			error("GetSortedAsync: pageSize must be 1..100", 2)
		end
		webYield(E.ds.latency)
		dsFail("GetSortedAsync")
		local rows = {}
		for k, v in orderedOf(getD(self)) do
			if (minV == nil or v >= minV) and (maxV == nil or v <= maxV) then
				table.insert(rows, { key = k, value = v })
			end
		end
		table.sort(rows, function(a, b)
			if a.value ~= b.value then
				if ascending then
					return a.value < b.value
				end
				return a.value > b.value
			end
			return a.key < b.key
		end)
		local pages = I.new("DataStorePages")
		local pd = getD(pages)
		pd.rows = rows
		pd.size = pageSize
		pd.page = 1
		pd.web = true -- (its next page is a web call, like Roblox's)
		return pages
	end,
}
-- E.ds.failPages (opt-in): the next n DataStore page advances fail (a long board read that has to resume).
E.ds.failPages = 0
IMPL.Pages = {
	GetCurrentPage = function(self)
		local pd = getD(self)
		local out = {}
		for i = (pd.page - 1) * pd.size + 1, math.min(#pd.rows, pd.page * pd.size) do
			table.insert(out, table.clone(pd.rows[i]))
		end
		return out
	end,
	AdvanceToNextPageAsync = function(self)
		local pd = getD(self)
		if pd.web then
			webYield(E.ds.latency)
			dsFail("AdvanceToNextPageAsync")
			if E.ds.failPages > 0 then
				E.ds.failPages -= 1
				error("502: API Services rejected request (sim page)", 2)
			end
		end
		pd.page += 1
	end,
}
GET.Pages = {
	IsFinished = function(self, d)
		return d.page * d.size >= #d.rows
	end,
}
local dsCache = {}
IMPL.DataStoreService = {
	GetDataStore = function(self, name, scope)
		serverOnly("DataStoreService:GetDataStore")
		if type(name) ~= "string" or #name == 0 or #name > 50 then
			error("GetDataStore: invalid name", 2)
		end
		local full = name .. "/" .. tostring(scope or "global")
		local ds = dsCache[full]
		if not ds then
			ds = I.new("DataStore")
			getD(ds).storeName = full
			getD(ds).props.Name = name
			dsCache[full] = ds
		end
		return ds
	end,
	GetOrderedDataStore = function(self, name, scope)
		serverOnly("DataStoreService:GetOrderedDataStore")
		local full = "ordered:" .. name .. "/" .. tostring(scope or "global")
		local ds = dsCache[full]
		if not ds then
			ds = I.new("OrderedDataStore")
			getD(ds).storeName = full
			getD(ds).props.Name = name
			dsCache[full] = ds
		end
		return ds
	end,
	GetGlobalDataStore = function()
		E.gap("DataStoreService:GetGlobalDataStore")
	end,
	GetRequestBudgetForRequestType = function(self, kind)
		if not E.Enum or typeOf(kind) ~= "EnumItem" then
			error("GetRequestBudgetForRequestType: Enum.DataStoreRequestType expected", 2)
		end
		return E.ds.budget
	end,
}

------------------------------------------------------------------ Players helpers (web)
IMPL.Players = {
	GetPlayers = function(self)
		local out = {}
		for _, c in getD(self).children do
			if getD(c).cls == "Player" then
				table.insert(out, c)
			end
		end
		return out
	end,
	GetPlayerByUserId = function(self, id)
		for _, c in getD(self).children do
			if getD(c).cls == "Player" and getD(c).props.UserId == id then
				return c
			end
		end
		return nil
	end,
	GetPlayerFromCharacter = function(self, model)
		for _, c in getD(self).children do
			if getD(c).cls == "Player" and getD(c).props.Character == model and model ~= nil then
				return c
			end
		end
		return nil
	end,
	GetNameFromUserIdAsync = function(self, id)
		if type(id) ~= "number" or id <= 0 then
			error("Players:GetNameFromUserIdAsync() failed: Unknown user", 2)
		end
		webYield(0.05)
		return E.cloud.names[id] or ("User" .. id)
	end,
	GetUserIdFromNameAsync = function(self, name)
		webYield(0.05)
		for id, n in E.cloud.names do
			if n == name then
				return id
			end
		end
		error("Players:GetUserIdFromNameAsync() failed: Unknown user", 2)
	end,
	GetFriendsAsync = function()
		E.gap("Players:GetFriendsAsync")
	end,
}
GET.Players = {
	LocalPlayer = function()
		local ctx = E.curCtx()
		if ctx.kind == "client" then
			return ctx.player
		end
		return nil
	end,
}
READONLY.Players = { LocalPlayer = true }
READONLY.Player = { UserId = true }
DEFAULT.Player = { AccountAge = 30, HasRobloxSubscription = false, MembershipType = function()
	return Enum.MembershipType.None
end }
IMPL.Player = {
	Kick = function(self, msg)
		E.kicks = E.kicks or {}
		table.insert(E.kicks, { userId = getD(self).props.UserId, msg = msg, t = E.now(), ctx = E.curCtx().name })
		E.out(string.format("[%s] KICK %s: %s", E.curCtx().name, getD(self).props.Name, tostring(msg)))
		task.defer(function()
			E.removePlayer(self, "kicked")
		end)
	end,
	GetJoinData = function(self)
		serverOnly("Player:GetJoinData")
		return deepCopy(getD(self).joinData or {})
	end,
	IsFriendsWithAsync = function(self, otherId)
		if type(otherId) ~= "number" then
			error("IsFriendsWithAsync: number expected", 2)
		end
		webYield(0.05)
		local a = getD(self).props.UserId
		return E.cloud.friends[math.min(a, otherId) .. ":" .. math.max(a, otherId)] == true
	end,
	IsInGroupAsync = function(self, gid)
		if type(gid) ~= "number" or gid == 0 then
			error("IsInGroupAsync: invalid group id " .. tostring(gid), 2)
		end
		webYield(0.05)
		local g = E.cloud.groups[getD(self).props.UserId]
		return g ~= nil and g[gid] == true
	end,
	GetRankInGroupAsync = function(self, gid)
		webYield(0.05)
		local g = E.cloud.groups[getD(self).props.UserId]
		return if g and g[gid] then 1 else 0
	end,
	LoadCharacter = function(self)
		serverOnly("Player:LoadCharacter")
		E.spawnCharacter(self)
	end,
	GetMouse = function()
		E.gap("Player:GetMouse")
	end,
	GetNetworkPing = function()
		return E.netLatency
	end,
}
GET.Player = {
	HasRobloxSubscription = function(self, d)
		return E.cloud.premium[d.props.UserId] == true
	end,
	MembershipType = function(self, d)
		if E.cloud.premium[d.props.UserId] then
			return Enum.MembershipType.Premium
		end
		return Enum.MembershipType.None
	end,
}

------------------------------------------------------------------ Marketplace
local function checkId(id, what)
	if type(id) ~= "number" or id <= 0 or id ~= math.floor(id) then
		E.issue("bad-asset-id", what .. " called with id " .. tostring(id))
		error(what .. ": invalid id " .. tostring(id), 3)
	end
end
IMPL.MarketplaceService = {
	UserOwnsGamePassAsync = function(self, userId, passId)
		checkId(passId, "UserOwnsGamePassAsync")
		webYield(0.08)
		local p = E.cloud.passes[userId]
		return p ~= nil and p[passId] == true
	end,
	PlayerOwnsAsset = function()
		E.gap("MarketplaceService:PlayerOwnsAsset")
	end,
	PromptGamePassPurchase = function(self, player, id)
		checkId(id, "PromptGamePassPurchase")
		table.insert(E.prompts, { kind = "pass", id = id, player = player, ctx = E.curCtx().name })
	end,
	PromptProductPurchase = function(self, player, id)
		checkId(id, "PromptProductPurchase")
		table.insert(E.prompts, { kind = "product", id = id, player = player, ctx = E.curCtx().name })
	end,
	PromptPurchase = function()
		E.gap("MarketplaceService:PromptPurchase")
	end,
	GetProductInfoAsync = function(self, id, infoType)
		checkId(id, "GetProductInfoAsync")
		webYield(0.05)
		local price = (E.cloud.prices and E.cloud.prices[id]) or 99 -- (a scenario can set E.cloud.prices[id])
		return { PriceInRobux = price, Name = "Item " .. id, IsForSale = true, Description = "", ProductId = id, AssetId = id }
	end,
	GetProductInfo = function(self, id, infoType)
		E.issue("deprecated", "MarketplaceService:GetProductInfo (deprecated) used")
		return { PriceInRobux = 99, Name = "Item " .. id, IsForSale = true }
	end,
}

------------------------------------------------------------------ Analytics / badges / social / policy / group
local function anaRecord(kind, rec)
	E.analytics.counts[kind] = (E.analytics.counts[kind] or 0) + 1
	if #E.analytics.calls < 20000 then
		table.insert(E.analytics.calls, rec)
	end
end
local function checkFields(cf, what)
	if cf == nil then
		return
	end
	if type(cf) ~= "table" then
		E.issue("analytics", what .. ": customFields must be a table")
		return
	end
	for k, v in cf do
		if k ~= "CustomField01" and k ~= "CustomField02" and k ~= "CustomField03" then
			E.issue("analytics", what .. ": bad custom field key " .. tostring(k))
		end
		if type(v) ~= "string" then
			E.issue("analytics", what .. ": custom field value must be a string, got " .. typeOf(v))
		end
	end
end
local function checkPlayer(p, what)
	if not I.isInst(p) or getD(p).cls ~= "Player" then
		error(what .. ": Player expected", 3)
	end
end
IMPL.AnalyticsService = {
	LogOnboardingFunnelStepEvent = function(self, player, step, stepName, cf)
		serverOnly("AnalyticsService")
		checkPlayer(player, "LogOnboardingFunnelStepEvent")
		if type(step) ~= "number" or step < 1 or step ~= math.floor(step) then
			E.issue("analytics", "onboarding step must be a positive integer: " .. tostring(step))
		end
		checkFields(cf, "LogOnboardingFunnelStepEvent")
		anaRecord("onboarding", { k = "onboarding", userId = player.UserId, step = step, name = stepName })
	end,
	LogFunnelStepEvent = function(self, player, funnel, sessionId, step, stepName, cf)
		serverOnly("AnalyticsService")
		checkPlayer(player, "LogFunnelStepEvent")
		if type(funnel) ~= "string" or funnel == "" then
			E.issue("analytics", "funnel name must be a non-empty string")
		end
		if type(sessionId) ~= "string" or sessionId == "" then
			E.issue("analytics", "LogFunnelStepEvent without funnelSessionId (event ignored by Roblox): " .. tostring(funnel))
		end
		checkFields(cf, "LogFunnelStepEvent")
		E.analytics.funnels[funnel] = true
		anaRecord("funnel", { k = "funnel", userId = player.UserId, funnel = funnel, sid = sessionId, step = step, name = stepName })
	end,
	LogEconomyEvent = function(self, player, flow, currency, amount, ending, tx, sku, cf)
		serverOnly("AnalyticsService")
		checkPlayer(player, "LogEconomyEvent")
		if typeOf(flow) ~= "EnumItem" then
			E.issue("analytics", "LogEconomyEvent flowType must be Enum.AnalyticsEconomyFlowType")
		end
		if type(currency) ~= "string" then
			E.issue("analytics", "LogEconomyEvent currencyType must be a string")
		end
		if type(amount) ~= "number" or amount <= 0 or amount ~= amount then
			E.issue("analytics", "LogEconomyEvent amount must be > 0: " .. tostring(amount))
		end
		if type(ending) ~= "number" or ending < 0 or ending ~= ending then
			E.issue("analytics", "LogEconomyEvent endingBalance must be >= 0: " .. tostring(ending))
		end
		if type(tx) ~= "string" then
			E.issue("analytics", "LogEconomyEvent transactionType must be a string")
		end
		checkFields(cf, "LogEconomyEvent")
		E.analytics.currencies[currency] = true
		if sku then
			E.analytics.skus[sku] = true
		end
		anaRecord("economy", { k = "economy", userId = player.UserId, flow = tostring(flow), currency = currency, amount = amount, ending = ending, tx = tx, sku = sku })
	end,
	LogCustomEvent = function(self, player, name, value, cf)
		serverOnly("AnalyticsService")
		checkPlayer(player, "LogCustomEvent")
		if type(name) ~= "string" or name == "" then
			E.issue("analytics", "custom event name must be a string")
		end
		if value ~= nil and (type(value) ~= "number" or value ~= value) then
			E.issue("analytics", "custom event value must be a number: " .. tostring(value))
		end
		checkFields(cf, "LogCustomEvent")
		E.analytics.customNames[name] = true
		anaRecord("custom", { k = "custom", userId = player.UserId, name = name, value = value, fields = cf })
	end,
	GetPlayerSegmentsAsync = function()
		E.gap("AnalyticsService:GetPlayerSegmentsAsync")
	end,
}
E.badgeAwards = {}
IMPL.BadgeService = {
	UserHasBadgeAsync = function(self, userId, badgeId)
		checkId(badgeId, "UserHasBadgeAsync")
		webYield(0.05)
		local b = E.cloud.badges[userId]
		return b ~= nil and b[badgeId] == true
	end,
	AwardBadgeAsync = function(self, userId, badgeId)
		serverOnly("BadgeService:AwardBadgeAsync")
		checkId(badgeId, "AwardBadgeAsync")
		webYield(0.05)
		E.cloud.badges[userId] = E.cloud.badges[userId] or {}
		E.cloud.badges[userId][badgeId] = true
		table.insert(E.badgeAwards, { userId = userId, badgeId = badgeId, t = E.now() })
		return true
	end,
	GetBadgeInfoAsync = function(self, id)
		webYield(0.05)
		return { Name = "Badge " .. id, IsEnabled = true }
	end,
}
IMPL.SocialService = {
	CanSendGameInviteAsync = function(self, player, recipient)
		clientOnly("SocialService:CanSendGameInviteAsync")
		webYield(0.05)
		return true
	end,
	PromptGameInvite = function(self, player, options)
		clientOnly("SocialService:PromptGameInvite")
		checkPlayer(player, "PromptGameInvite")
		local rec = { player = player, t = E.now() }
		if options ~= nil then
			if not I.isInst(options) or getD(options).cls ~= "ExperienceInviteOptions" then
				error("PromptGameInvite: ExperienceInviteOptions expected", 2)
			end
			rec.launchData = options.LaunchData
			rec.messageId = options.InviteMessageId
			rec.prompt = options.PromptMessage
			if #rec.launchData > 200 then
				E.issue("invite", "LaunchData longer than 200 characters")
			end
		end
		table.insert(E.invites, rec)
	end,
	CanSendCallInviteAsync = function()
		return false
	end,
}
IMPL.PolicyService = {
	GetPolicyInfoForPlayerAsync = function(self, player)
		checkPlayer(player, "GetPolicyInfoForPlayerAsync")
		webYield(0.08)
		if E.policyFail then
			error("GetPolicyInfoForPlayerAsync failed (sim)", 2)
		end
		local p = E.cloud.policy[player.UserId] or {}
		return {
			ArePaidRandomItemsRestricted = p.ArePaidRandomItemsRestricted == true,
			AllowedExternalLinkReferences = {},
			IsPaidItemTradingAllowed = true,
			IsSubjectToChinaPolicies = false,
			IsContentSharingAllowed = true,
		}
	end,
}
IMPL.GroupService = {
	PromptJoinAsync = function(self, gid)
		clientOnly("GroupService:PromptJoinAsync")
		checkId(gid, "PromptJoinAsync")
		webYield(0.2)
		local p = E.curCtx().player
		E.cloud.groups[p.UserId] = E.cloud.groups[p.UserId] or {}
		E.cloud.groups[p.UserId][gid] = true
		table.insert(E.prompts, { kind = "group", id = gid, player = p })
		return Enum.GroupMembershipStatus.Joined
	end,
	GetGroupInfoAsync = function(self, gid)
		webYield(0.05)
		return { Name = "Group " .. gid, Id = gid }
	end,
}
IMPL.TextChannel = {
	DisplaySystemMessage = function(self, text, meta)
		clientOnly("TextChannel:DisplaySystemMessage")
		if type(text) ~= "string" then
			error("DisplaySystemMessage: string expected", 2)
		end
		table.insert(E.systemMessages, { text = text, ctx = E.curCtx().name, t = E.now() })
		return nil
	end,
	SendAsync = function()
		E.gap("TextChannel:SendAsync")
	end,
}
IMPL.ExperienceNotificationService = {
	CanPromptOptInAsync = function(self)
		clientOnly("ExperienceNotificationService:CanPromptOptInAsync")
		webYield(0.05)
		return true
	end,
	PromptOptIn = function(self)
		clientOnly("ExperienceNotificationService:PromptOptIn")
		table.insert(E.prompts, { kind = "optin", player = E.curCtx().player })
	end,
}
-- StarterGui core GUI toggles: no-ops in the fake (the real calls are client-only and may throw before CoreGui loads)
E.coreGui = {}
IMPL.StarterGui = {
	SetCoreGuiEnabled = function(self, kind, on)
		clientOnly("StarterGui:SetCoreGuiEnabled")
		E.coreGui[tostring(kind)] = on
	end,
	GetCoreGuiEnabled = function(self, kind)
		local v = E.coreGui[tostring(kind)]
		return v == nil or v
	end,
}
IMPL.ConfigService = {
	GetConfigAsync = function()
		E.gap("ConfigService:GetConfigAsync")
	end,
}

------------------------------------------------------------------ AssetService / EditableImage
E.imageWrites = 0
-- E.imageBudget (opt-in): the device's image memory in bytes (4 a pixel); past it CreateEditableImage returns nil,
-- as Roblox does when a device runs out. E.imageFails counts those.
E.imageBudget = nil :: number?
E.imageFails = 0
local liveImages = setmetatable({}, { __mode = "k" })
-- bytes of the images not destroyed yet
function E.imageLive(): number
	local used = 0
	for im, bytes in liveImages do
		if getD(im).destroyed then
			liveImages[im] = nil
		else
			used += bytes
		end
	end
	return used
end
IMPL.AssetService = {
	CreateEditableImage = function(self, opts)
		clientOnly("AssetService:CreateEditableImage")
		local mode = E.editableImageMode
		if mode == "fail" then
			error("CreateEditableImage: Editable images are not enabled for this experience (sim)", 2)
		elseif mode == "nil" then
			return nil
		end
		local size = opts and opts.Size or v2(512, 512)
		if typeOf(size) ~= "Vector2" or size.X < 1 or size.Y < 1 or size.X > 1024 or size.Y > 1024 or size.X ~= math.floor(size.X) or size.Y ~= math.floor(size.Y) then
			error("CreateEditableImage: invalid Size " .. tostring(size), 2)
		end
		local budget = E.imageBudget
		if budget and E.imageLive() + size.X * size.Y * 4 > budget then
			E.imageFails += 1
			return nil
		end
		local img = I.new("EditableImage")
		liveImages[img] = size.X * size.Y * 4
		getD(img).props.Size = size
		getD(img).props.Name = "EditableImage"
		return img
	end,
}
READONLY.EditableImage = { Size = true }
IMPL.EditableImage = {
	WritePixelsBuffer = function(self, pos, size, buf)
		local d = getD(self)
		if d.destroyed then
			error("EditableImage was destroyed", 2)
		end
		if typeOf(pos) ~= "Vector2" or typeOf(size) ~= "Vector2" or type(buf) ~= "buffer" then
			error("WritePixelsBuffer: (Vector2, Vector2, buffer) expected", 2)
		end
		local isz = d.props.Size
		if pos.X < 0 or pos.Y < 0 or pos.X + size.X > isz.X or pos.Y + size.Y > isz.Y then
			error("WritePixelsBuffer: region out of bounds", 2)
		end
		if buffer.len(buf) ~= size.X * size.Y * 4 then
			error(string.format("WritePixelsBuffer: buffer length %d does not match %dx%dx4", buffer.len(buf), size.X, size.Y), 2)
		end
		E.imageWrites += 1
		d.lastWrite = E.frame
	end,
	ReadPixelsBuffer = function(self, pos, size)
		return buffer.create(size.X * size.Y * 4)
	end,
	Destroy = function(self)
		getD(self).destroyed = true
	end,
}

return true
