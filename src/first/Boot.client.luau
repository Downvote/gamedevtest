--!strict
-- ReplicatedFirst's one script (docs/ARCHITECTURE.md 8.0): runs on the client before the rest of the game has arrived,
-- puts the loading card up at once (the game's first frame is already the island's) and then removes Roblox's own
-- loading screen. The client's Main drives the card from there. If the card could not go up, Roblox's own screen stays
-- (Main puts the card up on its first line).
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local LoadingCard = require(script.Parent.LoadingCard)

local show: any = LoadingCard.show -- (typed through any: pcall mis-infers a () -> () function's returns)
local ok, err = pcall(show)
if ok and LoadingCard.state().up then
	ReplicatedFirst:RemoveDefaultLoadingScreen()
elseif not ok then
	warn("[Boot] loading card failed: " .. tostring(err))
end
