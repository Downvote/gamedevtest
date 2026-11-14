--!strict
-- The client's mirror of the server (docs/ARCHITECTURE.md 8.1): the latest ClientView (State messages), the server's
-- news (Fx messages: the island's stores and the time to the Tree of Life's next eggs every second, a new day, a new
-- lot of eggs, an egg hatched) and requests. The client never trusts itself: every change is a Router request.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Logic.Util)

local StateClient = {}

local current: Types.ClientView? = nil
StateClient.Changed = Util.Signal() :: Types.Signal<Types.ClientView>
StateClient.Fx = Util.Signal() :: Types.Signal<{ [string]: any }>
-- The island's store every second (Fx "tick"): the view's shells and time of day are patched in place, no whole
-- view is sent.
StateClient.Tick = Util.Signal() :: Types.Signal<Types.ClientView>
-- the time to the tree's next eggs as the server last said, and when (the client runs it down between its ticks)
local clutchLeft, clutchAt = 0, 0
-- the sea's clock as the server last said, and when (run on between ticks: the season and weather, Logic/Weather)
local seaAt, seaClock = 0, 0
local function tookClock(c: any)
	if type(c) == "number" and c == c then
		seaClock, seaAt = c, os.clock()
	end
end

function StateClient.init()
	local r = Net.clientInit()
	r.State.OnClientEvent:Connect(function(v: any)
		if type(v) == "table" then
			current = v :: Types.ClientView
			local left = (v :: any).clutchLeft
			if type(left) == "number" and left == left then
				clutchLeft, clutchAt = left, os.clock()
			end
			tookClock((v :: any).clock)
			StateClient.Changed:Fire(v :: Types.ClientView)
		end
	end)
	r.Fx.OnClientEvent:Connect(function(msg: any)
		if type(msg) == "table" then
			local cur = current
			if msg.kind == "tick" and cur then
				for _, k in { "shells", "dayFrac" } do
					local x = msg[k]
					if type(x) == "number" and x == x then
						(cur :: any)[k] = x
					end
				end
				if type(msg.clutchLeft) == "number" and msg.clutchLeft == msg.clutchLeft then
					clutchLeft, clutchAt = msg.clutchLeft, os.clock()
					cur.clutchLeft = msg.clutchLeft
				end
				if type(msg.clutchSecs) == "number" and msg.clutchSecs == msg.clutchSecs and msg.clutchSecs > 0 then
					cur.clutchSecs = msg.clutchSecs
				end
				if type(msg.clock) == "number" and msg.clock == msg.clock then
					tookClock(msg.clock)
					cur.clock = msg.clock
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

-- Seconds till the Tree of Life lays its next eggs (the server's last word run down by the clock) and the seconds
-- between two lots.
function StateClient.clutchLeft(): (number, number)
	local v = current
	local secs = if v then v.clutchSecs else 1
	return math.max(0, clutchLeft - (os.clock() - clutchAt)), secs
end

-- The sea's clock now (seconds: the server's last word run on by this client's clock; 0 before the first view): the
-- season and the weather come from it (Logic/Weather.at).
function StateClient.seaClock(): number
	if seaAt == 0 then
		return 0
	end
	return seaClock + (os.clock() - seaAt)
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
