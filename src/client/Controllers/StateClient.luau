--!strict
-- The client's mirror of the server (docs/ARCHITECTURE.md 8.1): the latest ClientView (State messages), the server's
-- news (Fx messages: the island's stores and the tide's clock every second, a new day, the driftlings drifting in and
-- off) and requests. The client never trusts itself: every change is a Router request.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Logic.Util)

local StateClient = {}

local current: Types.ClientView? = nil
-- the tide's clock as the server last said (seconds since the last one came, its seconds between two) and when (the
-- client runs it on)
local tideT, tideSecs, tideAt = 0, 1, 0
StateClient.Changed = Util.Signal() :: Types.Signal<Types.ClientView>
StateClient.Fx = Util.Signal() :: Types.Signal<{ [string]: any }>
-- The island's stores every second (Fx "tick"): the view's shells, wood and time of day are patched in place, no whole
-- view is sent.
StateClient.Tick = Util.Signal() :: Types.Signal<Types.ClientView>

function StateClient.init()
	local r = Net.clientInit()
	r.State.OnClientEvent:Connect(function(v: any)
		if type(v) == "table" then
			current = v :: Types.ClientView
			local t, secs = (v :: any).tideT, (v :: any).tideSecs
			if type(t) == "number" and t == t and type(secs) == "number" and secs > 0 then
				tideT, tideSecs, tideAt = t, secs, os.clock()
			end
			StateClient.Changed:Fire(v :: Types.ClientView)
		end
	end)
	r.Fx.OnClientEvent:Connect(function(msg: any)
		if type(msg) == "table" then
			local cur = current
			if msg.kind == "tick" and cur then
				for _, k in { "shells", "wood", "dayFrac" } do
					local x = msg[k]
					if type(x) == "number" and x == x then
						(cur :: any)[k] = x
					end
				end
				if type(msg.tideT) == "number" and msg.tideT == msg.tideT and type(msg.tideSecs) == "number" and msg.tideSecs > 0 then
					tideT, tideSecs, tideAt = msg.tideT, msg.tideSecs, os.clock()
					cur.tideT, cur.tideSecs = msg.tideT, msg.tideSecs
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

-- How far the tide is toward its next driftling now (0 .. 1: the server's last word run on by the clock) and its
-- seconds between two.
function StateClient.tideFrac(): (number, number)
	local v = current
	if v == nil then
		return 0, 1
	end
	local t = tideT + (os.clock() - tideAt)
	return math.clamp(t / math.max(0.1, tideSecs), 0, 1), tideSecs
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
