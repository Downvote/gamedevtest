--!strict
-- The season and the weather on the HUD (GAME_DESIGN 13; docs/ARCHITECTURE.md 10.12): two chips on the top bar's one
-- line after the shells (Hud.topChip; the request of 2026-11-14: "also, this can be compressed into one line. remove
-- the "day 1" as well"): the season's icon, its name and the time left in it ("Winter · 2 h"), then the weather's
-- icon, its name and the time left in this spell ("Rain · 6 min"),
-- from the sea's clock (Logic/Weather.at). A weather that can touch an egg is written in a light tone of its own
-- colour (Data/Weather `mark`), any other in plain white. A notice when the weather turns ("It started to
-- rain.") or a new season comes ("Summer is here. Beach, volcano and reef kinds come more often."). Main starts it
-- after the HUD.
--   start(), debugState() -> { season, weather, text }
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Data = require(ReplicatedStorage.Shared.Data.Weather)
local Weather = require(ReplicatedStorage.Shared.Logic.Weather)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local UIKit = require(script.Parent.UIKit)
local Hud = require(script.Parent.Hud)

local WeatherChip = {}

local started = false
local shown = { season = "", weather = "", text = "" }
local nextAt = 0

-- The weather line's colour: a touching weather's mark, lifted toward white so it reads on the black glass.
local function tone(def: Data.Kind): Color3
	if def.family == nil then
		return UIKit.color("text")
	end
	return UIKit.color(def.mark):Lerp(Color3.new(1, 1, 1), 0.45)
end

local function update()
	local c = StateClient.seaClock()
	if c <= 0 then
		if shown.text ~= "" then
			Hud.topChip("season", nil, nil)
			Hud.topChip("weather", nil, nil)
			shown.season, shown.weather, shown.text = "", "", ""
		end
		return
	end
	local st = Weather.at(c)
	local sdef = Data.seasonById[st.season]
	local wdef = Data.byId[st.kind]
	if sdef == nil or wdef == nil then
		return
	end
	local sText = sdef.name .. " · " .. Weather.left(st.seasonLeft)
	local wText = wdef.name .. " · " .. Weather.left(st.kindLeft)
	local key = st.season .. "|" .. st.kind .. "|" .. sText .. "|" .. wText
	if key == shown.text then
		return
	end
	shown.season, shown.weather, shown.text = st.season, st.kind, key
	Hud.topChip("season", sdef.icon, sText)
	Hud.topChip("weather", wdef.icon, wText, tone(wdef))
end

function WeatherChip.start()
	if started then
		return
	end
	started = true
	update()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now >= nextAt then
			nextAt = now + 0.5
			update()
		end
	end)
	-- a notice as the weather turns or a new season comes
	StateClient.Fx:Connect(function(msg)
		if type(msg) ~= "table" or msg.kind ~= "weather" then
			return
		end
		if msg.newSeason and type(msg.season) == "string" and Data.seasonById[msg.season] then
			local s = Data.seasonById[msg.season]
			UIKit.notice(s.name .. " is here. " .. s.blurb, UIKit.color("accent"), 5)
		elseif type(msg.wx) == "string" and Data.byId[msg.wx] then
			UIKit.notice(Data.byId[msg.wx].starts, UIKit.color("text"), 4)
		end
		nextAt = 0
	end)
end

-- What the lines show now (sims and previews).
function WeatherChip.debugState(): { season: string, weather: string, text: string }
	return table.clone(shown)
end

return WeatherChip
