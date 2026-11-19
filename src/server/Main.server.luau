--!strict
-- Server bootstrap (docs/ARCHITECTURE.md 7): remotes, services, joining and leaving, the fixed-step clock, autosave.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Schema = require(ReplicatedStorage.Shared.Logic.Schema)
local Util = require(ReplicatedStorage.Shared.Logic.Util)

Net.serverInit()

local Services = script.Parent.Services
local DataService = require(Services.DataService)
local Session = require(Services.Session)
local Router = require(Services.Router)
local PlotService = require(Services.PlotService)
local IslandService = require(Services.IslandService)
local MonetizationService = require(Services.MonetizationService)
local WorldClock = require(Services.WorldClock)

DataService.init()
PlotService.init()
Router.init()
IslandService.init()
MonetizationService.init()

local function join(player: Player)
	PlotService.watchCharacters(player)
	local plot = PlotService.claim(player)
	if plot == 0 then
		player:Kick("This server is full. Try another one.")
		return
	end
	local raw, ok = DataService.load(player.UserId)
	if player.Parent == nil then
		-- (left while it loaded: the lock goes too, or their next join elsewhere waits it out)
		PlotService.release(plot)
		if ok then
			DataService.unlock(player.UserId)
		end
		return
	end
	if not ok then
		PlotService.release(plot)
		player:Kick("Couldn't load your save. Rejoin in a moment.")
		return
	end
	if type(raw) == "table" and type(raw.v) == "number" and raw.v > Schema.VERSION then
		-- a save from a newer version of the game: this older server would drop what it doesn't know on its first
		-- save (the server review of 2026-11-19), so the player goes to a new server instead
		PlotService.release(plot)
		DataService.unlock(player.UserId)
		player:Kick("This server is out of date. Rejoin to play.")
		return
	end
	local seed = Util.hash32(tostring(player.UserId) .. ":start")
	local profile = Schema.reconcile(raw, os.time(), seed)
	local s = Session.create(player, profile, plot)
	-- (offline earnings: what the island made while the player was away, GAME_DESIGN 14.3)
	IslandService.join(s)
	PlotService.build(s)
	s.ready = true
	PlotService.placeCharacter(s)
	Session.markDirty(s)
	Session.flush(s)
	-- the passes the player owns (GAME_DESIGN 14: checked at every join)
	MonetizationService.join(s)
end

local function leave(player: Player)
	local s = Session.get(player)
	if s == nil then
		return
	end
	Session.remove(player)
	s.ready = false
	IslandService.leave(s)
	DataService.save(player.UserId, s.profile, true)
	PlotService.release(s.plot)
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(join, player)
end)
for _, player in Players:GetPlayers() do
	task.spawn(join, player)
end
Players.PlayerRemoving:Connect(leave)

-- the fixed step: the clock, the views, autosave
local STEP = 1 / Tuning.StepHz
local acc = 0
RunService.Heartbeat:Connect(function(dt: number)
	acc += math.min(dt, 1)
	while acc >= STEP do
		acc -= STEP
		IslandService.step(STEP)
	end
	-- (the sea's clock never left behind the real one by a stall: WorldClock.keepUp)
	WorldClock.keepUp(os.time())
	local now = os.clock()
	for player, s in Session.all() do
		if s.dirty and s.ready then
			PlotService.sync(s)
		end
		Session.flush(s)
		if s.ready and now >= s.saveAt then
			s.saveAt = now + Tuning.AutosaveSec
			task.spawn(DataService.save, player.UserId, s.profile, false)
		end
	end
end)

-- Shutting down: everyone still here leaves (saved, their lock dropped), and the server waits for every save going,
-- the leaving ones of players already gone among them, up to 25 s (Roblox gives 30). It waited a fixed 2 s, and a save
-- still queued on the store died with the server (the server review of 2026-11-19).
game:BindToClose(function()
	local list: { Player } = {}
	for player in Session.all() do
		table.insert(list, player)
	end
	for _, player in list do
		task.spawn(leave, player)
	end
	local t0 = os.clock()
	repeat
		task.wait(0.25)
	until DataService.pending() == 0 or os.clock() - t0 > 25
end)
