--!strict
-- The client's mirror of the server (docs/ARCHITECTURE.md 8.1): the latest ClientView (State messages), the server's
-- news (Fx messages: the island's stores and the tree's growth every second, a new day, what the Tree of Life grew) and
-- requests. The client never trusts itself: every change is a Router request.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local Tree = require(ReplicatedStorage.Shared.Logic.Tree)

local StateClient = {}

local current: Types.ClientView? = nil
-- the tree's growth as the server last said (seconds grown, its seconds a driftling) and when (the client runs it on)
local grow, growSecs, growAt = 0, 1, 0
StateClient.Changed = Util.Signal() :: Types.Signal<Types.ClientView>
StateClient.Fx = Util.Signal() :: Types.Signal<{ [string]: any }>
-- The island's stores every second (Fx "tick"): the view's shells, food, wood and time of day are patched in place,
-- no whole view is sent.
StateClient.Tick = Util.Signal() :: Types.Signal<Types.ClientView>

function StateClient.init()
	local r = Net.clientInit()
	r.State.OnClientEvent:Connect(function(v: any)
		if type(v) == "table" then
			current = v :: Types.ClientView
			local tr = (v :: any).tree
			if type(tr) == "table" and type(tr.t) == "number" then
				grow, growAt = tr.t, os.clock()
				growSecs = Tree.secs(v :: any)
			end
			StateClient.Changed:Fire(v :: Types.ClientView)
		end
	end)
	r.Fx.OnClientEvent:Connect(function(msg: any)
		if type(msg) == "table" then
			local cur = current
			if msg.kind == "tick" and cur then
				for _, k in { "shells", "food", "wood", "dayFrac" } do
					local x = msg[k]
					if type(x) == "number" and x == x then
						(cur :: any)[k] = x
					end
				end
				if type(msg.grow) == "number" and msg.grow == msg.grow and type(msg.secs) == "number" and msg.secs > 0 then
					grow, growSecs, growAt = msg.grow, msg.secs, os.clock()
					cur.tree.t = msg.grow
				end
				StateClient.Tick:Fire(cur)
			end
			StateClient.Fx:Fire(msg)
		end
	end)
end

function StateClient.view(): Types.ClientView?
	return current
end

-- How far the Tree of Life is toward its next driftling now (0 .. 1: the server's last word run on by the clock) and
-- its seconds a driftling.
function StateClient.treeFrac(): (number, number)
	local v = current
	if v == nil then
		return 0, 1
	end
	local t = grow + (os.clock() - growAt)
	return math.clamp(t / math.max(0.1, growSecs), 0, 1), growSecs
end

-- Wait (yielding) for the first view.
function StateClient.waitView(): Types.ClientView
	while current == nil do
		task.wait(0.05)
	end
	return current :: Types.ClientView
end

-- One request to the server (yields). Never errors: a failed call comes back { ok = false, err = "not_ready" }.
function StateClient.request(action: string, payload: { [string]: any }?): Types.Response
	local ok, res = pcall(function()
		return Net.get().Request:InvokeServer(action, payload or {})
	end)
	if ok and type(res) == "table" then
		return res :: Types.Response
	end
	return { ok = false, err = "not_ready" }
end

function StateClient.signal(kind: string, payload: any?)
	pcall(function()
		Net.get().Signal:FireServer(kind, payload)
	end)
end

return StateClient
