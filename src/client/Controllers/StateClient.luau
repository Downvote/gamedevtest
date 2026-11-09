--!strict
-- The client's mirror of the server (docs/ARCHITECTURE.md 8.1): the latest ClientView (State messages), the server's
-- news (Fx messages: a new idea, an income payment) and requests. The client never trusts itself: every change is a Router request.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Logic.Util)

local StateClient = {}

local current: Types.ClientView? = nil
StateClient.Changed = Util.Signal() :: Types.Signal<Types.ClientView>
StateClient.Fx = Util.Signal() :: Types.Signal<{ [string]: any }>
-- The coins after an income payment (Fx "coins"): the view's coins are patched in place, no whole view is sent.
StateClient.Coins = Util.Signal() :: Types.Signal<number>

function StateClient.init()
	local r = Net.clientInit()
	r.State.OnClientEvent:Connect(function(v: any)
		if type(v) == "table" then
			current = v :: Types.ClientView
			StateClient.Changed:Fire(v :: Types.ClientView)
		end
	end)
	r.Fx.OnClientEvent:Connect(function(msg: any)
		if type(msg) == "table" then
			local cur = current
			if msg.kind == "coins" and type(msg.coins) == "number" and cur then
				cur.coins = msg.coins
				StateClient.Coins:Fire(msg.coins)
			end
			StateClient.Fx:Fire(msg)
		end
	end)
end

function StateClient.view(): Types.ClientView?
	return current
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
