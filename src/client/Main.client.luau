--!strict
-- Client bootstrap (docs/ARCHITECTURE.md 8): the server's mirror first, then the camera and the pixel filter, the
-- interface, the office's life and the HUD.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local _ = ReplicatedStorage
local StateClient = require(script.Parent.Controllers.StateClient)
local CameraController = require(script.Parent.Controllers.CameraController)
local PixelRenderer = require(script.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.UI.UIKit)
local WorldView = require(script.Parent.Controllers.WorldView)
local AvatarView = require(script.Parent.Controllers.AvatarView)
local StreetLife = require(script.Parent.Controllers.StreetLife)
local Hud = require(script.Parent.UI.Hud)

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

StateClient.init()
PixelRenderer.init()
CameraController.init()
StateClient.waitView()
CameraController.start()
PixelRenderer.start()
UIKit.init()
WorldView.init()
WorldView.start()
AvatarView.start()
StreetLife.start()
Hud.start()
