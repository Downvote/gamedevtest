--!strict
-- Every client request (docs/ARCHITECTURE.md 7.3): one RemoteFunction, an action name and a payload, checked by
-- Logic/Validate, rate limited, then handed to the service that registered the action, answered {ok, data} or
-- {ok = false, err}. The server decides everything; the client only asks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Net = require(ReplicatedStorage.Shared.Net)
local Validate = require(ReplicatedStorage.Shared.Logic.Validate)
local Session = require(script.Parent.Session)

type Handler = (s: Session.S, payload: any) -> (boolean, any)

local Router = {}

local handlers: { [string]: Handler } = {}
local signals: { [string]: (s: Session.S, payload: any) -> () } = {}

function Router.on(action: string, fn: Handler)
	assert(Validate.ACTIONS[action] ~= nil, "Router.on: no Validate schema for " .. action)
	handlers[action] = fn
end

function Router.onSignal(kind: string, fn: (s: Session.S, payload: any) -> ())
	signals[kind] = fn
end

-- Handle one request (Request.OnServerInvoke; the sims call it the same way).
function Router.handle(player: Player, action: any, payload: any): Types.Response
	local s = Session.get(player)
	if s == nil or not s.ready then
		return { ok = false, err = "not_ready" }
	end
	if not Session.allow(s, os.clock()) then
		return { ok = false, err = "rate" }
	end
	local ok, err = Validate.request(action, payload)
	if not ok then
		return { ok = false, err = err :: any }
	end
	local fn = handlers[action :: string]
	if fn == nil then
		return { ok = false, err = "unknown_action" }
	end
	local okCall, good, data = pcall(fn, s, payload or {})
	if not okCall then
		warn(string.format("[Router] %s failed: %s", tostring(action), tostring(good)))
		return { ok = false, err = "bad_payload" }
	end
	if good then
		Session.markDirty(s)
		return { ok = true, data = data }
	end
	return { ok = false, err = data }
end

function Router.init()
	local r = Net.get()
	r.Request.OnServerInvoke = function(player: Player, action: any, payload: any): any
		return Router.handle(player, action, payload)
	end
	r.Signal.OnServerEvent:Connect(function(player: Player, kind: any, payload: any)
		local s = Session.get(player)
		local fn = if type(kind) == "string" then signals[kind] else nil
		if s and s.ready and fn then
			pcall(fn, s, payload)
		end
	end)
end

return Router
