--!strict
-- Client bootstrap (docs/ARCHITECTURE.md 8): the server's mirror first, then the camera and the pixel filter, the
-- day and night, the interface, the island's life (its models, then its small lives in the pixel layer) and the HUD.
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
local AmbientView = require(script.Parent.Controllers.AmbientView)
local Hud = require(script.Parent.UI.Hud)
local DayLight = require(script.Parent.Controllers.DayLight)
local WeatherView = require(script.Parent.Controllers.WeatherView)
local Spinners = require(script.Parent.Controllers.Spinners)
local WeatherChip = require(script.Parent.UI.WeatherChip)
local SkyBackdrop = require(script.Parent.UI.SkyBackdrop)
local SettingsUI = require(script.Parent.UI.SettingsUI)
local Lang = require(ReplicatedStorage.Shared.Locale.Lang)

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
-- the language and the text (Settings, the request of 2026-11-20: "like the bakery game, make translations for
-- different languages, and an option to turn off pixel text"): the saved choice now ("auto": the player's Roblox
-- language), before the HUD is built, and again whenever it changes (UIKit.applyLanguage does nothing when it has not)
-- (SettingsUI.value: a tap the server hasn't answered yet wins over the view, so a tick never turns it back)
SettingsUI.applyLanguage()
StateClient.Changed:Connect(SettingsUI.applyLanguage)
-- (the loading card's words too, and again after a change)
LoadingCard.useLang(Lang, UIKit.smooth)
UIKit.LanguageChanged:Connect(LoadingCard.reword)
-- the shells on every sheet's awning on a touch screen (the request of 2026-11-19: "Make menus fill the screen on
-- mobile with currency showing and an exit button")
UIKit.setWallet(function(): number?
	local v = StateClient.view()
	return if v then v.shells else nil
end, StateClient.Changed)
WorldView.init()
WorldView.start()
AvatarView.start()
StreetLife.start()
AmbientView.start()
Hud.start()
-- the season and the weather (GAME_DESIGN 13): on the islands, then their lines in the HUD's status panel
WeatherView.start()
-- the painted sky round the floating islands (behind the pixel layer; it follows the weather)
SkyBackdrop.start()
Spinners.start()
WeatherChip.start()

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
