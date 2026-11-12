--!strict
-- Client bootstrap (docs/ARCHITECTURE.md 8): the server's mirror first, then the camera and the pixel filter, the
-- day and night, the interface, the island's life and the HUD.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

-- the loading card first (ReplicatedFirst's Boot has put it up already; if it could not, it goes up here: ReplicatedFirst
-- has arrived before any StarterPlayerScripts run)
local LoadingCard = require(game:GetService("ReplicatedFirst").Loading.LoadingCard)
do
	local show: any = LoadingCard.show
	pcall(show)
end

local _ = ReplicatedStorage
local StateClient = require(script.Parent.Controllers.StateClient)
local CameraController = require(script.Parent.Controllers.CameraController)
local PixelRenderer = require(script.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.UI.UIKit)
local WorldView = require(script.Parent.Controllers.WorldView)
local AvatarView = require(script.Parent.Controllers.AvatarView)
local StreetLife = require(script.Parent.Controllers.StreetLife)
local Hud = require(script.Parent.UI.Hud)
local DayLight = require(script.Parent.Controllers.DayLight)

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

StateClient.init()
PixelRenderer.init()
CameraController.init()
LoadingCard.phase("island")
StateClient.waitView()
CameraController.start()
PixelRenderer.start()
DayLight.start()
UIKit.init()
WorldView.init()
WorldView.start()
AvatarView.start()
StreetLife.start()
Hud.start()

-- the card follows the first picture's bake and fades into it once it is on screen (or after a while regardless)
LoadingCard.phase("picture")
task.spawn(function()
	local t0 = os.clock()
	while true do
		local done, progress = PixelRenderer.firstPicture()
		LoadingCard.progress(progress)
		if done or os.clock() - t0 > 30 then
			break
		end
		task.wait(0.05)
	end
	LoadingCard.finish()
end)
