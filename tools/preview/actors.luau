-- Parallel Luau stand-ins for the preview tool (run serially, which is a legal schedule): Instance:GetActor,
-- Actor:BindToMessage / BindToMessageParallel / SendMessage, and LocalScripts that start when they are parented into a
-- client container after the client started (e.g. a worker cloned into an Actor under PlayerScripts).
-- task.desynchronize / task.synchronize are already no-ops in the engine.
local E = require("./engine")
local I = require("./inst")
local getD = I.getD
local isA = I.isA

local A = {}
A.stats = { messages = 0, scriptsStarted = 0 }

I.IMPL.Instance.GetActor = function(self)
	local cur = getD(self).props.Parent
	while cur do
		local d = getD(cur)
		if d.cls == "Actor" then
			return cur
		end
		cur = d.props.Parent
	end
	return nil
end

local ConnMT = {}
ConnMT.__index = ConnMT
E.TYPEOF_REGISTER(ConnMT, "RBXScriptConnection")
function ConnMT:Disconnect()
	self.Connected = false
end

local function bind(self, topic, fn)
	if type(topic) ~= "string" or type(fn) ~= "function" then
		error("BindToMessage: (string, function) expected", 3)
	end
	local d = getD(self)
	d.msgHandlers = d.msgHandlers or {}
	local list = d.msgHandlers[topic] or {}
	d.msgHandlers[topic] = list
	local c = setmetatable({ Connected = true, fn = fn, ctx = E.curCtx() }, ConnMT)
	table.insert(list, c)
	return c
end
I.IMPL.Actor = {
	BindToMessage = function(self, topic, fn)
		return bind(self, topic, fn)
	end,
	BindToMessageParallel = function(self, topic, fn)
		return bind(self, topic, fn)
	end,
	SendMessage = function(self, topic, ...)
		local d = getD(self)
		local list = d.msgHandlers and d.msgHandlers[topic]
		A.stats.messages += 1
		if not list then
			return
		end
		local args = table.pack(...)
		for _, c in table.clone(list) do
			if c.Connected then
				E.pushDeferred({ fn = c.fn, ctx = c.ctx, Connected = true }, args)
			end
		end
	end,
}

-- BindableEvent:Fire (deferred, like Roblox's default SignalBehavior)
I.IMPL.BindableEvent = I.IMPL.BindableEvent or {}
I.IMPL.BindableEvent.Fire = function(self, ...)
	I.fire(I.getSig(self, "Event"), ...)
end

-- LocalScripts parented into the local player's PlayerScripts / PlayerGui / Backpack after the client started.
local CONTAINERS = { PlayerScripts = true, PlayerGui = true, Backpack = true }
local function playerContainer(inst)
	local cur = inst
	local container = nil
	while cur do
		local d = getD(cur)
		if CONTAINERS[d.cls] then
			container = cur
		elseif d.cls == "Player" then
			return cur, container
		end
		cur = d.props.Parent
	end
	return nil, nil
end
local prevReparent = I.onReparent
I.onReparent = function(subtree, old, new)
	if prevReparent then
		prevReparent(subtree, old, new)
	end
	if new == nil then
		return
	end
	for _, x in subtree do
		local d = getD(x)
		if d.cls == "LocalScript" and not d.ran and d.props.Disabled ~= true and d.props.Enabled ~= false then
			local player, container = playerContainer(x)
			local ctx = player and E.clientCtx(player)
			if ctx and container and ctx.root then
				d.ran = true
				A.stats.scriptsStarted += 1
				E.task.defer(function()
					if x.Parent ~= nil then
						E.runScript(ctx, x)
					end
				end)
			end
		end
	end
end

return A
