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

DataService.init()
PlotService.init()
Router.init()
IslandService.init()

local function join(player: Player)
	PlotService.watchCharacters(player)
	local plot = PlotService.claim(player)
	if plot == 0 then
		player:Kick("Every island on this sea is taken. Please join another server.")
		return
	end
	local raw, ok = DataService.load(player.UserId)
	if player.Parent == nil then
		PlotService.release(plot)
		return
	end
	if not ok then
		PlotService.release(plot)
		player:Kick("We couldn't open your island's save. Please rejoin in a moment.")
		return
	end
	local seed = Util.hash32(tostring(player.UserId) .. ":start")
	local profile = Schema.reconcile(raw, os.time(), seed)
	local s = Session.create(player, profile, plot)
	PlotService.build(s)
	s.ready = true
	PlotService.placeCharacter(s)
	Session.markDirty(s)
	Session.flush(s)
end

local function leave(player: Player)
	local s = Session.get(player)
	if s == nil then
		return
	end
	Session.remove(player)
	s.ready = false
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
	local now = os.clock()
	for player, s in Session.all() do
		if s.dirty and s.ready then
			PlotService.sync(s)
		elseif s.tideDirty and s.ready then
			PlotService.syncTide(s)
		end
		Session.flush(s)
		if s.ready and now >= s.saveAt then
			s.saveAt = now + Tuning.AutosaveSec
			task.spawn(DataService.save, player.UserId, s.profile, false)
		end
	end
end)

game:BindToClose(function()
	local threads = {}
	for player, s in Session.all() do
		table.insert(threads, task.spawn(DataService.save, player.UserId, s.profile, true))
	end
	task.wait(2)
end)
