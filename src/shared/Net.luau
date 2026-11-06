--!strict
-- The only module that creates or looks up the remotes (docs/ARCHITECTURE.md 7.1).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type Remotes = {
	Request: RemoteFunction, -- C->S (action: string, payload: any?) -> Types.Response
	Signal: RemoteEvent, -- C->S (kind: string, payload: any?): fire and forget ("pause")
	State: RemoteEvent, -- S->C Types.ClientView (the whole view; sent when it changed)
	Fx: RemoteEvent, -- S->C { kind: string, ... } (a week's events, notices)
}

local Net = {}
Net.FOLDER = "Remotes"
Net.SPEC = {
	{ name = "Request", class = "RemoteFunction" },
	{ name = "Signal", class = "RemoteEvent" },
	{ name = "State", class = "RemoteEvent" },
	{ name = "Fx", class = "RemoteEvent" },
}

local remotes: Remotes? = nil

local function collect(folder: Instance, wait: boolean): Remotes
	local function get(name: string): Instance
		if wait then
			return folder:WaitForChild(name)
		end
		return folder:FindFirstChild(name) :: Instance
	end
	return {
		Request = get("Request") :: RemoteFunction,
		Signal = get("Signal") :: RemoteEvent,
		State = get("State") :: RemoteEvent,
		Fx = get("Fx") :: RemoteEvent,
	}
end

-- Server: create ReplicatedStorage.Remotes and every remote (idempotent). First thing in Main.server.
function Net.serverInit(): Remotes
	assert(RunService:IsServer(), "Net.serverInit is server-only")
	if remotes then
		return remotes
	end
	local folder = ReplicatedStorage:FindFirstChild(Net.FOLDER)
	if not folder then
		local f = Instance.new("Folder")
		f.Name = Net.FOLDER
		f.Parent = ReplicatedStorage
		folder = f
	end
	local f = folder :: Instance
	for _, spec in Net.SPEC do
		if not f:FindFirstChild(spec.name) then
			local r = Instance.new(spec.class :: any)
			r.Name = spec.name
			r.Parent = f
		end
	end
	local r = collect(f, false)
	remotes = r
	return r
end

-- Client: wait for the server's remotes.
function Net.clientInit(): Remotes
	if remotes then
		return remotes
	end
	local folder = ReplicatedStorage:WaitForChild(Net.FOLDER)
	local r = collect(folder, true)
	remotes = r
	return r
end

function Net.get(): Remotes
	assert(remotes, "Net not initialised")
	return remotes :: Remotes
end

return Net
