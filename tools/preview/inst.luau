-- Instance system for the fake engine: defs-validated members, properties, signals, tree, attributes, cloning.
local E = require("./engine")
local DEFS = require("./defs_gen")
local CLASSES = DEFS.classes
local v3, v2, c3 = E.v3, E.v2, E.c3
local CF = E.cf
local typeOf = E.typeof
local Enum = E.Enum
local task = E.task

local I = {}
E.I = I

------------------------------------------------------------------ class info
local memberCache = {}
local function memberOf(cls, k)
	local cache = memberCache[cls]
	if not cache then
		cache = {}
		memberCache[cls] = cache
	end
	local m = cache[k]
	if m ~= nil then
		return m or nil
	end
	local c = cls
	while c do
		local def = CLASSES[c]
		if not def then
			break
		end
		local pt = def.props[k]
		if pt then
			m = { kind = "prop", type = pt, owner = c }
			break
		end
		if def.methods[k] then
			m = { kind = "method", owner = c }
			break
		end
		if def.events[k] then
			m = { kind = "event", owner = c }
			break
		end
		c = def.super
	end
	cache[k] = m or false
	return m
end
I.memberOf = memberOf

local function isA(cls, target)
	local c = cls
	while c do
		if c == target then
			return true
		end
		local def = CLASSES[c]
		if not def then
			return false
		end
		c = def.super
	end
	return false
end
I.isA = isA

-- per-class extension tables, resolved along the class chain
local IMPL = {} -- IMPL[class][method] = fn(self, ...)
local GET = {} -- GET[class][prop] = fn(self, d) -> value
local SET = {} -- SET[class][prop] = fn(self, d, v)
local DEFAULT = {} -- DEFAULT[class][prop] = value or fn(self) -> value
local READONLY = {} -- READONLY[class][prop] = true
local INIT = {} -- INIT[class] = fn(self, d)
local EXTRA = {} -- EXTRA[class][member] = {kind=...} fake-only members (not in defs)
I.IMPL, I.GET, I.SET, I.DEFAULT, I.READONLY, I.INIT, I.EXTRA = IMPL, GET, SET, DEFAULT, READONLY, INIT, EXTRA

local function chainLookup(tbl, cls, k)
	local c = cls
	while c do
		local t = tbl[c]
		if t then
			local v = t[k]
			if v ~= nil then
				return v
			end
		end
		local def = CLASSES[c]
		if not def then
			return nil
		end
		c = def.super
	end
	return nil
end

------------------------------------------------------------------ signals
local SigMT = {}
SigMT.__index = SigMT
E.typeofRegister = nil
local ConnMT = {}
ConnMT.__index = ConnMT

function I.newSignal(name, owner)
	return setmetatable({ conns = {}, name = name, owner = owner }, SigMT)
end
function SigMT:Connect(fn)
	if type(fn) ~= "function" then
		error("Attempt to connect failed: Passed value is not a function", 2)
	end
	local ctx = E.curCtx()
	if self.guard then
		self.guard(ctx)
	end
	local c = setmetatable({ Connected = true, fn = fn, ctx = ctx, sig = self }, ConnMT)
	table.insert(self.conns, c)
	if self.onConnect then
		self.onConnect(c)
	end
	return c
end
function SigMT:Once(fn)
	local c
	c = self:Connect(function(...)
		c:Disconnect()
		fn(...)
	end)
	return c
end
SigMT.ConnectParallel = SigMT.Connect
function SigMT:Wait()
	local co = coroutine.running()
	local c
	c = self:Connect(function(...)
		c:Disconnect()
		E.resume(co, ...)
	end)
	return coroutine.yield()
end
function ConnMT:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local list = self.sig.conns
	local i = table.find(list, self)
	if i then
		table.remove(list, i)
	end
end
-- deferred firing (Roblox SignalBehavior.Deferred): handlers run at the next resumption point in new threads
function I.fire(sig, ...)
	if sig == nil or #sig.conns == 0 then
		return
	end
	local args = table.pack(...)
	for _, c in table.clone(sig.conns) do
		E.pushDeferred(c, args)
	end
end
-- immediate firing in new threads (RunService events, engine-driven callbacks)
function I.fireNow(sig, ...)
	if sig == nil then
		return
	end
	for _, c in table.clone(sig.conns) do
		if c.Connected and c.ctx.alive then
			local co = E.newThread(c.fn, c.ctx)
			E.resume(co, ...)
		end
	end
end
function I.disconnectAll(sig)
	for _, c in table.clone(sig.conns) do
		c:Disconnect()
	end
end

------------------------------------------------------------------ instances
local IMT = {}
I.IMT = IMT
E.TYPEOF_REGISTER(IMT, "Instance")
E.TYPEOF_REGISTER(SigMT, "RBXScriptSignal")
E.TYPEOF_REGISTER(ConnMT, "RBXScriptConnection")
local nextId = 0
local function isInst(v)
	return type(v) == "table" and getmetatable(v) == IMT
end
I.isInst = isInst

local function getD(self)
	return rawget(self, "__d")
end
I.getD = getD

local function getSig(self, d, name)
	local s = d.sigs[name]
	if not s then
		s = I.newSignal(name, self)
		local g = chainLookup(I.SIGGUARD, d.cls, name)
		if g then
			s.guard = g
		end
		local si = chainLookup(I.SIGINIT, d.cls, name)
		if si then
			si(self, s)
		end
		d.sigs[name] = s
	end
	return s
end
I.SIGGUARD = {}
I.SIGINIT = {}
I.getSig = function(self, name)
	return getSig(self, getD(self), name)
end

local function fullName(self)
	local parts = {}
	local cur = self
	local guard = 0
	while cur and guard < 100 do
		guard += 1
		local d = getD(cur)
		if d.cls == "DataModel" then
			break
		end
		table.insert(parts, 1, d.props.Name)
		cur = d.props.Parent
	end
	return table.concat(parts, ".")
end
I.fullName = fullName

-- type-based defaults for properties never assigned
local TYPE_DEFAULT = {
	number = 0,
	boolean = false,
	string = "",
	ContentId = "",
	Vector3 = v3(0, 0, 0),
	Vector2 = v2(0, 0),
	CFrame = CF.identity,
	Color3 = c3(0, 0, 0),
	UDim2 = E.types.UDim2.new(0, 0, 0, 0),
	UDim = E.types.UDim.new(0, 0),
	Content = E.types.Content.none,
	Font = E.types.Font.new("rbxasset://fonts/families/SourceSansPro.json"),
}
local function defaultFor(self, d, k, ptype)
	local dv = chainLookup(DEFAULT, d.cls, k)
	if dv ~= nil then
		if type(dv) == "function" then
			return dv(self, d)
		end
		return dv
	end
	local tv = TYPE_DEFAULT[ptype]
	if tv ~= nil then
		return tv
	end
	if string.sub(ptype, 1, 4) == "Enum" and not string.find(ptype, "[ |?]") then
		local ok, en = pcall(function()
			return Enum[string.sub(ptype, 5)]
		end)
		if ok then
			return en:GetEnumItems()[1]
		end
	end
	return nil
end

-- loose runtime type check of a property assignment, from the defs type string
local SIMPLE = {
	number = "number", boolean = "boolean", string = "string", ContentId = "string", Vector3 = "Vector3", Vector2 = "Vector2",
	CFrame = "CFrame", Color3 = "Color3", UDim2 = "UDim2", UDim = "UDim", Content = "Content", Font = "Font",
	ColorSequence = "ColorSequence", NumberSequence = "NumberSequence", NumberRange = "NumberRange", Rect = "Rect",
	TweenInfo = "TweenInfo",
}
local function checkAssign(self, d, k, ptype, v)
	local optional = string.sub(ptype, -1) == "?"
	local base = if optional then string.sub(ptype, 1, -2) else ptype
	if v == nil then
		if optional or not SIMPLE[base] then
			return
		end
		error(string.format("Unable to assign property %s. %s expected, got nil", k, base), 4)
	end
	local want = SIMPLE[base]
	local got = typeOf(v)
	if want then
		if want == "number" and got == "number" then
			if v ~= v then
				E.issue("nan-property", string.format("%s.%s assigned NaN", fullName(self), k))
			end
			return
		end
		if want ~= got then
			error(string.format("Unable to assign property %s. %s expected, got %s", k, want, got), 4)
		end
		return
	end
	if string.sub(base, 1, 4) == "Enum" and not string.find(base, "[ |]") then
		if got == "EnumItem" then
			local en = rawget(v, "EnumType")
			if rawget(en, "__name") ~= string.sub(base, 5) then
				error(string.format("Unable to assign property %s. %s expected, got %s", k, base, tostring(v)), 4)
			end
			return
		elseif got == "number" or got == "string" then
			return -- Roblox coerces numbers/names
		end
		error(string.format("Unable to assign property %s. %s expected, got %s", k, base, got), 4)
	end
	if CLASSES[base] then
		if not isInst(v) then
			error(string.format("Unable to assign property %s. Object expected, got %s", k, got), 4)
		end
		if not isA(getD(v).cls, base) then
			error(string.format("Unable to assign property %s. %s expected, got %s", k, base, getD(v).cls), 4)
		end
		return
	end
	if string.find(base, "->") then
		if type(v) ~= "function" then
			error(string.format("Unable to assign property %s. function expected, got %s", k, got), 4)
		end
	end
end

IMT.__index = function(self, k)
	local d = getD(self)
	if type(k) ~= "string" then
		error(string.format("invalid instance member %s (%s)", tostring(k), type(k)), 2)
	end
	local m = memberOf(d.cls, k)
	if m == nil then
		m = chainLookup(EXTRA, d.cls, k)
	end
	if m then
		if m.kind == "prop" then
			local g = chainLookup(GET, d.cls, k)
			if g then
				return g(self, d)
			end
			local v = d.props[k]
			if v ~= nil then
				return v
			end
			if d.propsNil and d.propsNil[k] then
				return nil
			end
			return defaultFor(self, d, k, m.type or "")
		elseif m.kind == "method" then
			local f = chainLookup(IMPL, d.cls, k)
			if f then
				return f
			end
			return function()
				error(string.format("FAKE-GAP: method %s:%s not implemented", d.cls, k), 2)
			end
		elseif m.kind == "event" then
			if d.destroyed and not d.sigs[k] then
				return getSig(self, d, k)
			end
			return getSig(self, d, k)
		end
	end
	for _, c in d.children do
		if getD(c).props.Name == k then
			return c
		end
	end
	error(string.format("%s is not a valid member of %s \"%s\"", k, d.cls, fullName(self)), 2)
end

local function firePropChanged(self, d, k)
	local ps = d.propSigs[k]
	if ps then
		I.fire(ps)
	end
	local ch = d.sigs.Changed
	if ch then
		-- ValueBase (NumberValue, StringValue, ...) Changed passes the new Value and fires only for Value; every
		-- other Instance passes the property name
		if isA(d.cls, "ValueBase") then
			if k == "Value" then
				I.fire(ch, d.props.Value)
			end
		else
			I.fire(ch, k)
		end
	end
end
I.firePropChanged = firePropChanged

IMT.__newindex = function(self, k, v)
	local d = getD(self)
	local m = memberOf(d.cls, k) or chainLookup(EXTRA, d.cls, k)
	if not m or m.kind ~= "prop" then
		error(string.format("%s is not a valid member of %s \"%s\"", tostring(k), d.cls, fullName(self)), 2)
	end
	if chainLookup(READONLY, d.cls, k) and not E.engineWrite then
		error(string.format("Unable to assign property %s. Property is read only", k), 2)
	end
	if m.type then
		checkAssign(self, d, k, m.type, v)
	end
	local s = chainLookup(SET, d.cls, k)
	if s then
		s(self, d, v)
		return
	end
	local old = d.props[k]
	if v == nil then
		d.propsNil = d.propsNil or {}
		d.propsNil[k] = true
	elseif d.propsNil then
		d.propsNil[k] = nil
	end
	d.props[k] = v
	if old ~= v then
		if I.onPropWrite then
			I.onPropWrite(self, d, k)
		end
		firePropChanged(self, d, k)
	end
end
IMT.__tostring = function(self)
	return getD(self).props.Name
end
IMT.__eq = nil

-- raw property write by the engine (bypasses read-only)
function I.setRaw(self, k, v)
	local d = getD(self)
	local old = d.props[k]
	d.props[k] = v
	if old ~= v then
		firePropChanged(self, d, k)
	end
end

local function descendants(self, outList)
	for _, c in getD(self).children do
		table.insert(outList, c)
		descendants(c, outList)
	end
	return outList
end
I.descendants = descendants

local function ancestorsOf(self)
	local list = {}
	local p = getD(self).props.Parent
	while p do
		table.insert(list, p)
		p = getD(p).props.Parent
	end
	return list
end

function I.new(cls, opts)
	nextId += 1
	local d = {
		cls = cls,
		props = { Name = cls },
		children = {},
		attrs = {},
		sigs = {},
		propSigs = {},
		attrSigs = {},
		destroyed = false,
		parentLocked = false,
		id = nextId,
	}
	local self = setmetatable({ __d = d }, IMT)
	local cctx = E.curCtx()
	if cctx.kind == "client" then
		d.ctx = cctx
		cctx.created = cctx.created or setmetatable({}, { __mode = "k" })
		cctx.created[self] = true
	end
	local c = cls
	local inits = {}
	while c do
		local f = INIT[c]
		if f then
			table.insert(inits, 1, f)
		end
		local def = CLASSES[c]
		c = def and def.super
	end
	for _, f in inits do
		f(self, d, opts)
	end
	return self
end

-- Parent assignment (validates, maintains children, fires tree signals)
local function setParent(self, d, newParent)
	if newParent ~= nil and not isInst(newParent) then
		error("Unable to assign property Parent. Object expected, got " .. typeOf(newParent), 3)
	end
	local old = d.props.Parent
	if old == newParent then
		return
	end
	if d.parentLocked then
		error(
			string.format("The Parent property of %s is locked, current parent: %s, new parent %s", d.props.Name, if old then getD(old).props.Name else "NULL", if newParent then getD(newParent).props.Name else "NULL"),
			3
		)
	end
	if newParent then
		local p = newParent
		while p do
			if p == self then
				error(string.format("Attempt to set parent of %s to %s would result in circular reference", fullName(self), fullName(newParent)), 3)
			end
			p = getD(p).props.Parent
		end
		if getD(newParent).destroyed and getD(newParent).parentLocked then
			-- legal in Roblox, but a likely bug: the new parent is destroyed and can never be shown
			E.issue("parent-destroyed", string.format("%s parented into destroyed %s", d.props.Name, getD(newParent).props.Name))
		end
	end
	local subtree = { self }
	descendants(self, subtree)
	if old then
		local od = getD(old)
		local i = table.find(od.children, self)
		if i then
			table.remove(od.children, i)
		end
		I.fire(od.sigs.ChildRemoved, self)
		for _, anc in { old, table.unpack(ancestorsOf(old)) } do
			local ad = getD(anc)
			if ad.sigs.DescendantRemoving then
				for _, x in subtree do
					I.fire(ad.sigs.DescendantRemoving, x)
				end
			end
		end
	end
	d.props.Parent = newParent
	if newParent then
		local nd = getD(newParent)
		table.insert(nd.children, self)
		I.fire(nd.sigs.ChildAdded, self)
		for _, anc in { newParent, table.unpack(ancestorsOf(newParent)) } do
			local ad = getD(anc)
			if ad.sigs.DescendantAdded then
				for _, x in subtree do
					I.fire(ad.sigs.DescendantAdded, x)
				end
			end
			if ad.onDescendantAdded then
				for _, x in subtree do
					ad.onDescendantAdded(anc, x)
				end
			end
		end
	end
	if I.onReparent then
		I.onReparent(subtree, old, newParent)
	end
	for _, x in subtree do
		local xd = getD(x)
		I.fire(xd.sigs.AncestryChanged, self, newParent)
	end
	firePropChanged(self, d, "Parent")
end
SET.Instance = {
	Parent = setParent,
	Name = function(self, d, v)
		if type(v) ~= "string" then
			error("Unable to assign property Name. string expected, got " .. typeOf(v), 3)
		end
		local old = d.props.Name
		d.props.Name = v
		if old ~= v then
			firePropChanged(self, d, "Name")
		end
	end,
}
READONLY.Object = { ClassName = true }
GET.Object = {
	ClassName = function(_, d)
		return d.cls
	end,
}

------------------------------------------------------------------ Instance methods
local M = {}
IMPL.Object = {
	IsA = function(self, cls)
		return isA(getD(self).cls, cls)
	end,
	GetPropertyChangedSignal = function(self, prop)
		local d = getD(self)
		local m = memberOf(d.cls, prop) or chainLookup(EXTRA, d.cls, prop)
		if not m or m.kind ~= "prop" then
			error(string.format("%s is not a valid property name.", tostring(prop)), 2)
		end
		local s = d.propSigs[prop]
		if not s then
			s = I.newSignal("Changed:" .. prop, self)
			d.propSigs[prop] = s
		end
		return s
	end,
}
M.FindFirstChild = function(self, name, recursive)
	if type(name) ~= "string" then
		error("Argument 1 missing or nil", 2)
	end
	for _, c in getD(self).children do
		if getD(c).props.Name == name then
			return c
		end
	end
	if recursive then
		for _, c in getD(self).children do
			local r = M.FindFirstChild(c, name, true)
			if r then
				return r
			end
		end
	end
	return nil
end
M.FindFirstChildOfClass = function(self, cls)
	for _, c in getD(self).children do
		if getD(c).cls == cls then
			return c
		end
	end
	return nil
end
M.FindFirstChildWhichIsA = function(self, cls, recursive)
	for _, c in getD(self).children do
		if isA(getD(c).cls, cls) then
			return c
		end
	end
	if recursive then
		for _, c in getD(self).children do
			local r = M.FindFirstChildWhichIsA(c, cls, true)
			if r then
				return r
			end
		end
	end
	return nil
end
M.FindFirstAncestor = function(self, name)
	for _, a in ancestorsOf(self) do
		if getD(a).props.Name == name then
			return a
		end
	end
	return nil
end
M.FindFirstAncestorOfClass = function(self, cls)
	for _, a in ancestorsOf(self) do
		if getD(a).cls == cls then
			return a
		end
	end
	return nil
end
M.FindFirstAncestorWhichIsA = function(self, cls)
	for _, a in ancestorsOf(self) do
		if isA(getD(a).cls, cls) then
			return a
		end
	end
	return nil
end
M.FindFirstDescendant = function(self, name)
	for _, c in descendants(self, {}) do
		if getD(c).props.Name == name then
			return c
		end
	end
	return nil
end
M.GetChildren = function(self)
	return table.clone(getD(self).children)
end
M.GetDescendants = function(self)
	return descendants(self, {})
end
M.IsDescendantOf = function(self, anc)
	if anc == nil then
		error("Argument 1 missing or nil", 2)
	end
	for _, a in ancestorsOf(self) do
		if a == anc then
			return true
		end
	end
	return false
end
M.IsAncestorOf = function(self, desc)
	return M.IsDescendantOf(desc, self)
end
M.GetFullName = function(self)
	return fullName(self)
end
M.GetDebugId = function(self)
	return tostring(getD(self).id)
end
M.WaitForChild = function(self, name, timeout)
	if type(name) ~= "string" then
		error("Argument 1 missing or nil", 2)
	end
	local found = M.FindFirstChild(self, name)
	if found then
		return found
	end
	if not coroutine.isyieldable() then
		error("WaitForChild called from a non-yieldable thread", 2)
	end
	local start = E.now()
	local warned = false
	while true do
		task.wait(0.03)
		found = M.FindFirstChild(self, name)
		if found then
			return found
		end
		local el = E.now() - start
		if timeout and el >= timeout then
			return nil
		end
		if not timeout and el >= 5 and not warned then
			warned = true
			E.issue("infinite-yield", string.format("Infinite yield possible on '%s:WaitForChild(\"%s\")'", fullName(self), name))
		end
	end
end
M.ClearAllChildren = function(self)
	for _, c in table.clone(getD(self).children) do
		M.Destroy(c)
	end
end
M.Destroy = function(self)
	local d = getD(self)
	if d.destroyed then
		return
	end
	-- Destroying fires immediately, whatever the signal behaviour (Roblox: handlers run before the instance goes)
	I.fireNow(d.sigs.Destroying)
	for _, c in table.clone(d.children) do
		M.Destroy(c)
	end
	if d.props.Parent ~= nil then
		setParent(self, d, nil)
	end
	d.destroyed = true
	d.parentLocked = true
	if d.onDestroy then
		d.onDestroy(self, d)
	end
	-- Roblox disconnects all connections of a destroyed instance
	for _, s in d.sigs do
		I.disconnectAll(s)
	end
	for _, s in d.propSigs do
		I.disconnectAll(s)
	end
	for _, s in d.attrSigs do
		I.disconnectAll(s)
	end
end
M.Remove = function(self)
	setParent(self, getD(self), nil)
end
local ATTR_TYPES = {
	boolean = true, number = true, string = true, UDim = true, UDim2 = true, BrickColor = true, Color3 = true,
	Vector2 = true, Vector3 = true, CFrame = true, NumberSequence = true, ColorSequence = true, NumberRange = true,
	Rect = true, Font = true, EnumItem = true,
}
M.SetAttribute = function(self, name, value)
	if type(name) ~= "string" or #name == 0 or #name > 100 or not string.match(name, "^[%w_]+$") or string.sub(name, 1, 3) == "RBX" then
		error("SetAttribute: invalid attribute name " .. tostring(name), 2)
	end
	if value ~= nil and not ATTR_TYPES[typeOf(value)] then
		error(string.format("%s is not a supported attribute type", typeOf(value)), 2)
	end
	local d = getD(self)
	local old = d.attrs[name]
	d.attrs[name] = value
	if old ~= value then
		I.fire(d.sigs.AttributeChanged, name)
		if d.attrSigs[name] then
			I.fire(d.attrSigs[name])
		end
	end
end
M.GetAttribute = function(self, name)
	return getD(self).attrs[name]
end
M.GetAttributes = function(self)
	return table.clone(getD(self).attrs)
end
M.GetAttributeChangedSignal = function(self, name)
	local d = getD(self)
	local s = d.attrSigs[name]
	if not s then
		s = I.newSignal("AttrChanged:" .. name, self)
		d.attrSigs[name] = s
	end
	return s
end
M.AddTag = function(self, tag)
	getD(self).tags = getD(self).tags or {}
	getD(self).tags[tag] = true
end
M.HasTag = function(self, tag)
	return getD(self).tags ~= nil and getD(self).tags[tag] == true
end
M.RemoveTag = function(self, tag)
	if getD(self).tags then
		getD(self).tags[tag] = nil
	end
end
M.GetTags = function(self)
	local out = {}
	for t in getD(self).tags or {} do
		table.insert(out, t)
	end
	return out
end
local function cloneInst(self)
	local d = getD(self)
	if d.props.Archivable == false then
		return nil
	end
	local c = I.new(d.cls, { cloning = true })
	local cd = getD(c)
	for k, v in d.props do
		if k ~= "Parent" then
			cd.props[k] = v
		end
	end
	if d.propsNil then
		cd.propsNil = table.clone(d.propsNil)
	end
	for k, v in d.attrs do
		cd.attrs[k] = v
	end
	cd.src = d.src
	cd.chunkFile = d.chunkFile
	if d.cloneExtra then
		d.cloneExtra(self, d, c, cd)
	end
	for _, ch in d.children do
		local cc = cloneInst(ch)
		if cc then
			setParent(cc, getD(cc), c)
		end
	end
	return c
end
M.Clone = cloneInst
IMPL.Instance = M

E.Instance = {
	new = function(cls, parent)
		if type(cls) ~= "string" then
			error("Instance.new: class name expected", 2)
		end
		if not DEFS.creatable[cls] and not I.CREATABLE_EXTRA[cls] then
			error(string.format("Unable to create an Instance of type \"%s\"", cls), 2)
		end
		local inst = I.new(cls)
		if parent ~= nil then
			inst.Parent = parent
		end
		return inst
	end,
	fromExisting = function(x)
		return cloneInst(x)
	end,
}
I.CREATABLE_EXTRA = {}

return I
