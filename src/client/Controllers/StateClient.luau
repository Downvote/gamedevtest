--!strict
-- The client's mirror of the server (docs/ARCHITECTURE.md 8.1): the latest ClientView (State messages), the server's
-- news (Fx messages: the island's stores every second, a new day, the driftlings that came in on the tide and the ones
-- gone past, one a second: the view's tide is patched in place) and requests. The client never trusts itself: every
-- change is a Router request.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Logic.Util)

local StateClient = {}

local current: Types.ClientView? = nil
StateClient.Changed = Util.Signal() :: Types.Signal<Types.ClientView>
StateClient.Fx = Util.Signal() :: Types.Signal<{ [string]: any }>
-- The island's stores every second (Fx "tick"): the view's shells, wood and time of day are patched in place, no whole
-- view is sent.
StateClient.Tick = Util.Signal() :: Types.Signal<Types.ClientView>
-- The tide changed (Fx "tide": one came in, ones gone past): the view's tide is patched in place.
StateClient.TideChanged = Util.Signal() :: Types.Signal<Types.ClientView>

-- One on the tide from a message, checked (nil: not one).
local function driftOf(x: any): Types.Drift?
	if type(x) ~= "table" then
		return nil
	end
	local id, sp, cost, at, life = x.id, x.sp, x.cost, x.at, x.life
	if type(id) ~= "number" or type(sp) ~= "string" or type(cost) ~= "number" or type(at) ~= "number" or type(life) ~= "number" or at ~= at or life ~= life then
		return nil
	end
	local muts: { string } = {}
	if type(x.muts) == "table" then
		for _, m in x.muts do
			if type(m) == "string" then
				table.insert(muts, m)
			end
		end
	end
	return { id = id, sp = sp, muts = muts, cost = cost, at = at, life = life }
end

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
			if msg.kind == "tick" and cur then
				for _, k in { "shells", "wood", "dayFrac" } do
					local x = msg[k]
					if type(x) == "number" and x == x then
						(cur :: any)[k] = x
					end
				end
				if type(msg.tideSecs) == "number" and msg.tideSecs == msg.tideSecs and msg.tideSecs > 0 then
					cur.tideSecs = msg.tideSecs
				end
				StateClient.Tick:Fire(cur)
			elseif msg.kind == "tide" and cur and type(cur.tide) == "table" then
				local gone: { [number]: boolean } = {}
				if type(msg.gone) == "table" then
					for _, id in msg.gone do
						if type(id) == "number" then
							gone[id] = true
						end
					end
				end
				local list: { Types.Drift } = {}
				local have: { [number]: boolean } = {}
				for _, d in cur.tide do
					if not gone[d.id] then
						table.insert(list, d)
						have[d.id] = true
					end
				end
				if type(msg.came) == "table" then
					for _, x in msg.came do
						local d = driftOf(x)
						if d and not have[d.id] and not gone[d.id] then
							table.insert(list, d)
							have[d.id] = true
							-- (seen on the tide: in the Index, as the server marks it; no whole view comes for it)
							if type(cur.seen) == "table" then
								cur.seen[d.sp] = math.max(cur.seen[d.sp] or 0, 1)
							end
						end
					end
				end
				cur.tide = list
				StateClient.TideChanged:Fire(cur)
			end
			StateClient.Fx:Fire(msg)
		end
	end)
end

function StateClient.view(): Types.ClientView?
	return current
end

-- The tide's clock: the server's time, the same on every client (each one's place along the way, Controllers/TideView).
function StateClient.tideNow(): number
	return workspace:GetServerTimeNow()
end

-- How far along the tide one is now (0 just come in .. 1 gone past).
function StateClient.along(d: Types.Drift): number
	return math.clamp((workspace:GetServerTimeNow() - d.at) / math.max(0.1, d.life), 0, 1)
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
