--!strict
-- The Top sheet: the leaderboards and the friends (GAME_DESIGN 16; Logic/Social, Services/SocialService). The request
-- (2026-11-21): "Make a leaderboard system, along with friend invite bonuses".
--   The panel ("top"; its argument a tab: "coins", "charm", "hatched", "friends"):
--     Coins, Charm, Hatched, Driftlings: a board each (action "lb.get" { board }, asked again at most every REFRESH
--       seconds): the player's own place and score pinned on top, then the top Tuning.BoardRows, the first three in
--       gold, silver and bronze, players on this server in teal; on Driftlings each island's best driftling after the
--       name (the request of 2026-11-21: "make another tab on the leaderboard for driftlings. judge based on rarity
--       and mutation stars").
--     Friends: what an invite brings both sides (Data/Rewards.REFERRAL), the Invite button (Roblox's invite prompt,
--       its LaunchData {"r": <the player's id>} for when ReferredByPlayerId is missing), friends invited, today's
--       rewards left; the friends on the server and the coins they add.
--   On the HUD (UI/Hud): the menu bar's Top button, and a status line while friends play here (TopUI.status; a tap
--   opens the Friends tab).
-- API: TopUI.init(), TopUI.TABS, TopUI.tabOf() -> string, TopUI.status(v, line), TopUI.invite().
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local RewardsData = require(ReplicatedStorage.Shared.Data.Rewards)
local Creatures = require(ReplicatedStorage.Shared.Data.Creatures)
local Traits = require(ReplicatedStorage.Shared.Data.Traits)
local Social = require(ReplicatedStorage.Shared.Logic.Social)
local Lang = require(ReplicatedStorage.Shared.Locale.Lang)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local RewardsUI = require(script.Parent.RewardsUI)

local TopUI = {}

type View = Types.ClientView
type Row = Types.BoardRow
type Board = { at: number, rows: { Row }, you: { value: number, rank: number? }?, loading: boolean, failed: boolean }

TopUI.TABS = {
	{ id = "coins", text = "Coins", icon = "coin" },
	{ id = "charm", text = "Charm", icon = "charm" },
	{ id = "hatched", text = "Hatched", icon = "egg" },
	{ id = "driftlings", text = "Driftlings", icon = "pal" },
	{ id = "friends", text = "Friends", icon = "friends" },
}
local HINT: { [string]: string } = {
	coins = "Coins earned in all",
	charm = "The island's charm",
	hatched = "Eggs hatched",
	driftlings = "Best driftling: rarity and mutation stars",
}
local REFRESH = 60 -- seconds a board on this client is kept before it's asked for again
local tab = "coins"
local tabSeq = -1
local boards: { [string]: Board } = {}
local inviting = false

local PAD = 4
local ROW_H = 14

------------------------------------------------------------------ the boards
local function value(n: number): string
	return if n >= 100000 then Numbers.short(n) else Numbers.int(n)
end

local function rankColor(rank: number?): Color3
	if rank == 1 then
		return UIKit.color("accent")
	elseif rank == 2 then
		return UIKit.color("rank_silver")
	elseif rank == 3 then
		return UIKit.color("rank_bronze")
	end
	return UIKit.color("text_dim")
end

-- The board from the server, asked for in the background; the sheet is built again when it lands (if still on it).
local function fetch(name: string)
	local b = boards[name]
	if b == nil then
		b = { at = -math.huge, rows = {}, you = nil, loading = false, failed = false }
		boards[name] = b
	end
	local board = b :: Board
	if board.loading or os.clock() - board.at < REFRESH then
		return
	end
	board.loading = true
	task.spawn(function()
		local res = StateClient.request("lb.get", { board = name })
		board.loading = false
		local data = res.data
		if res.ok and type(data) == "table" and type(data.rows) == "table" then
			board.rows = data.rows
			board.you = if type(data.you) == "table" then data.you else nil
			board.at = os.clock()
			board.failed = false
		else
			board.failed = true
			board.at = os.clock() - REFRESH + 10 -- (again in 10 s)
		end
		if UIKit.currentPanel() == "top" and tab == name then
			UIKit.refreshPanel()
		end
	end)
end

-- One line of a board: the place, the name, the score. On the Driftlings board the score is read back
-- (Social.decode) into the points and the driftling, shown after the name: its kind's name in its rarity's colour, a
-- star and its mutation stars.
local function boardRow(list: Instance, y: number, W: number, rank: number?, name: string, score: number, opts: { mine: boolean?, here: boolean?, board: string? }): Frame
	local tint = if opts.mine then UIKit.color("accent") elseif rank and rank <= 3 then rankColor(rank) else nil
	local f = UIKit.row(list, UDim2.fromOffset(W, ROW_H), UDim2.fromOffset(0, y), tint, if opts.mine then 0.72 elseif tint then 0.86 else nil)
	f.Name = if opts.mine then "You" else "Row_" .. tostring(rank)
	local rw = 26
	if rank and rank <= 3 then
		PixelSprites.image(f, "mini_trophy", UDim2.fromOffset(PAD - 1, 1), 4)
	end
	UIKit.text(f, if rank then "#" .. rank else "-", UDim2.fromOffset(rw - 2, 10), UDim2.fromOffset(if rank and rank <= 3 then PAD + 11 else PAD, 2), {
		color = rankColor(rank),
		z = 4,
		name = "Rank",
	})
	local sp: string? = nil
	if opts.board == "driftlings" then
		score, sp = Social.decode(score)
	end
	local vs = value(score)
	local vw = UIKit.textWidth(vs) + 4
	local nx = PAD + rw + 12
	local nw = W - nx - vw - PAD - 4
	if opts.board == "driftlings" then
		local c = if sp then Creatures.byId[sp] else nil
		local pw = math.floor(nw * 0.55)
		nw -= pw
		local px = nx + nw + 4
		if c then
			local rar = Traits.RARITY[math.clamp(c.rarity, 1, Traits.RMAX)]
			local stars = math.max(0, (score - Tuning.BoardRarityPoints[math.clamp(c.rarity, 1, #Tuning.BoardRarityPoints)]) // Tuning.BoardStarPoints)
			local cw = math.min(UIKit.textWidth(c.name) + 2, pw - 24)
			UIKit.text(f, c.name, UDim2.fromOffset(cw, 10), UDim2.fromOffset(px, 2), { color = UIKit.color(rar.color), z = 4, name = "Pal" })
			if stars > 0 then
				PixelSprites.image(f, "star_t4", UDim2.fromOffset(px + cw + 3, 4), 4)
				UIKit.text(f, tostring(stars), UDim2.fromOffset(16, 10), UDim2.fromOffset(px + cw + 12, 2), { color = UIKit.color("accent"), z = 4, name = "Stars" })
			end
		else
			UIKit.text(f, "-", UDim2.fromOffset(10, 10), UDim2.fromOffset(px, 2), { color = UIKit.color("text_dim"), z = 4, name = "Pal" })
		end
	end
	UIKit.text(f, name, UDim2.fromOffset(nw, 10), UDim2.fromOffset(nx, 2), {
		color = if opts.mine then UIKit.color("accent") elseif opts.here then UIKit.color("sheet_head") else UIKit.color("text"),
		z = 4,
		name = "Name",
		raw = not opts.mine,
	})
	UIKit.text(f, vs, UDim2.fromOffset(vw, 10), UDim2.new(1, -vw - PAD, 0, 2), { x = "right", z = 4, name = "Score" })
	return f
end

local function buildBoard(body: Frame, top: number, W: number, H: number, name: string)
	fetch(name)
	local b = boards[name]
	local me = Players.LocalPlayer
	local every = "Updates every few minutes"
	local ew = math.min(UIKit.textWidth(every) + 4, math.floor(W / 2))
	UIKit.text(body, HINT[name] or "", UDim2.fromOffset(W - ew - 4, 10), UDim2.fromOffset(1, top), { color = UIKit.color("text_dim"), z = 4, name = "Hint" })
	UIKit.text(body, every, UDim2.fromOffset(ew, 10), UDim2.fromOffset(W - ew, top), { color = UIKit.color("text_dim"), x = "right", z = 4, name = "Every" })
	local y = top + 12
	-- the player's own line, pinned
	local you = b and b.you
	boardRow(body, y, W, you and you.rank, "You", if you then you.value else 0, { mine = true, board = name })
	y += ROW_H + 3
	local list = UIKit.scroll(body, UDim2.fromOffset(W, H - y), UDim2.fromOffset(0, y))
	list.AutomaticCanvasSize = Enum.AutomaticSize.None
	local cw = W - 6
	if b == nil or (#b.rows == 0 and b.loading) or (b.at < 0 and not b.failed) then
		UIKit.text(list, "Loading...", UDim2.fromOffset(cw, 10), UDim2.fromOffset(0, 8), { x = "center", color = UIKit.color("text_dim"), z = 4, name = "Loading" })
		list.CanvasSize = UDim2.fromOffset(0, 24)
		return
	end
	if #b.rows == 0 then
		local msg = if b.failed then "Couldn't load the board. Trying again soon." else "No one's on this board yet."
		UIKit.text(list, msg, UDim2.fromOffset(cw, 10), UDim2.fromOffset(0, 8), { x = "center", color = UIKit.color("text_dim"), z = 4, name = "Empty" })
		list.CanvasSize = UDim2.fromOffset(0, 24)
		return
	end
	local ry = 0
	for _, r in b.rows do
		local mine = r.userId == me.UserId
		local here = Players:GetPlayerByUserId(r.userId) ~= nil
		-- (a name Roblox couldn't give: "Player <id>", in the language on show)
		local shown = if mine then "You" elseif r.name == "" then Lang.f("Player {1}", tostring(r.userId)) else r.name
		boardRow(list, ry, cw, r.rank, shown, r.value, { here = here and not mine, mine = mine, board = name })
		ry += ROW_H + 2
	end
	list.CanvasSize = UDim2.fromOffset(0, ry + 2)
end

------------------------------------------------------------------ friends
-- Roblox's invite prompt, with the inviter's id in its LaunchData (read back by SocialService at the friend's join).
function TopUI.invite()
	if inviting then
		return
	end
	inviting = true
	task.spawn(function()
		local me = Players.LocalPlayer
		local okCan, can = pcall(function(): boolean
			return SocialService:CanSendGameInviteAsync(me)
		end)
		if not okCan or not can then
			Audio.play("deny")
			UIKit.notice("Invites aren't available right now.", UIKit.color("bad"))
			inviting = false
			return
		end
		Audio.play("click")
		local okPrompt = pcall(function()
			local opts = Instance.new("ExperienceInviteOptions")
			opts.PromptMessage = Lang.t("Come build an island with me.")
			opts.LaunchData = HttpService:JSONEncode({ r = me.UserId })
			SocialService:PromptGameInvite(me, opts)
		end)
		if not okPrompt then
			UIKit.notice("Invites aren't available right now.", UIKit.color("bad"))
		end
		inviting = false
	end)
end

-- A row: an icon, a line, a quieter line under it (wrapped to two lines when it needs them).
local function infoRow(parent: Instance, y: number, W: number, icon: string, head: string, sub: string, name: string, tint: Color3?): number
	local lines = UIKit.lines(sub, W - 26)
	local h = 14 + math.max(1, math.min(2, lines)) * 10
	local f = UIKit.row(parent, UDim2.fromOffset(W, h), UDim2.fromOffset(0, y), tint, if tint then 0.8 else nil)
	f.Name = name
	PixelSprites.image(f, "mini_" .. icon, UDim2.fromOffset(PAD + 1, math.floor((h - 11) / 2)), 4)
	UIKit.text(f, head, UDim2.fromOffset(W - 26, 10), UDim2.fromOffset(19, 2), { z = 4, name = "Top" })
	UIKit.text(f, sub, UDim2.fromOffset(W - 26, h - 14), UDim2.fromOffset(19, 12), { color = UIKit.color("text_dim"), wrap = true, y = "top", z = 4, name = "Sub" })
	return h
end

local function buildFriends(list: ScrollingFrame, v: View, W: number): number
	local so = v.social
	local y = 0
	UIKit.heading(list, "Invite friends", y, "friends")
	y += 14
	local gift = RewardsUI.bundle(v, RewardsData.REFERRAL.invitee)
	local mine = RewardsUI.bundle(v, RewardsData.REFERRAL.inviter)
	y += infoRow(list, y, W, "gift", "When a friend joins from your invite", Lang.f("They get {1}.", gift), "TheyGet") + 2
	y += infoRow(list, y, W, "trophy", "Once they've played " .. Numbers.duration(Tuning.ReferralMinPlaySec), Lang.f("You get {1}.", mine), "YouGet", UIKit.color("accent")) + 3
	local bw = math.max(90, UIKit.buttonWidth("Invite friends", 10) + 14)
	local b = UIKit.button(list, "Invite friends", UDim2.fromOffset(bw, 16), UDim2.fromOffset(math.floor((W - bw) / 2), y), TopUI.invite, {
		name = "Invite",
		color = UIKit.color("button_ok"),
	})
	b.ZIndex = 5
	PixelSprites.image(b, "mini_friends", UDim2.fromOffset(4, 2), 6)
	local words = b:FindFirstChild("Words")
	if words and words:IsA("GuiObject") then
		words.Position = UDim2.fromOffset(14, 0)
		words.Size = UDim2.new(1, -16, 1, 0)
	end
	y += 20
	local left = if so then so.todayLeft else Tuning.ReferralDailyCap
	UIKit.text(list, "Friends invited: " .. (if so then so.invited else 0), UDim2.fromOffset(math.floor(W / 2), 10), UDim2.fromOffset(1, y), { z = 4, name = "Invited" })
	UIKit.text(list, "Rewards left today: " .. left, UDim2.fromOffset(math.floor(W / 2) - 2, 10), UDim2.fromOffset(math.floor(W / 2), y), {
		color = if left > 0 then UIKit.color("text_dim") else UIKit.color("bad"),
		x = "right",
		z = 4,
		name = "TodayLeft",
	})
	y += 14
	UIKit.heading(list, "Play together", y, "boost")
	y += 14
	local here = if so then so.here else 0
	local each = math.floor(Tuning.FriendsBoostEach * 100 + 0.5)
	local cap = math.floor(Tuning.FriendsBoostMax * 100 + 0.5)
	local head = if here == 1 then "1 friend on this server" else here .. " friends on this server"
	local sub = "+" .. each .. "% coins for each friend here, up to +" .. cap .. "%."
	y += infoRow(list, y, W, "friends", head, sub, "Here", if here > 0 then UIKit.color("good") else nil) + 2
	if here > 0 and so then
		local f = list:FindFirstChild("Here")
		if f then
			local note = "+" .. math.floor(so.boost * 100 + 0.5) .. "% now"
			local tw = UIKit.textWidth(note)
			UIKit.text(f, note, UDim2.fromOffset(tw + 2, 10), UDim2.new(1, -tw - PAD - 2, 0, 2), { color = UIKit.color("good"), x = "right", z = 5, name = "Now" })
		end
	end
	if so and so.referred then
		UIKit.text(list, "You joined from a friend's invite.", UDim2.fromOffset(W, 10), UDim2.fromOffset(1, y), { color = UIKit.color("text_dim"), z = 4, name = "Referred" })
		y += 12
	end
	return y
end

------------------------------------------------------------------ the sheet
local function build(body: Frame, arg: any?)
	local v = StateClient.view()
	if v == nil then
		return
	end
	if type(arg) == "string" and tabSeq ~= UIKit.openCount() then
		for _, t in TopUI.TABS do
			if t.id == arg then
				tab = arg
			end
		end
	end
	tabSeq = UIKit.openCount()
	local W, H = UIKit.bodyWidth(body), UIKit.bodyHeight(body)
	local items: { UIKit.Tab } = {}
	for _, t in TopUI.TABS do
		table.insert(items, { id = t.id, text = t.text, icon = t.icon })
	end
	local top = UIKit.tabs(body, items, tab, 0, function(id: string)
		tab = id
		Audio.play("flip")
		UIKit.refreshPanel()
	end) + 3
	if tab == "friends" then
		local list = UIKit.scroll(body, UDim2.fromOffset(W, H - top), UDim2.fromOffset(0, top))
		list.AutomaticCanvasSize = Enum.AutomaticSize.None
		local cw = W - 6
		list:SetAttribute("W", cw)
		local h = buildFriends(list, v, cw)
		list.CanvasSize = UDim2.fromOffset(0, h + 2)
		return
	end
	buildBoard(body, top, W, H, tab)
end

------------------------------------------------------------------ the HUD's line
-- While friends play on this server: how many and the coins they add (a tap opens the Friends tab).
function TopUI.status(v: View?, line: (name: string, icon: string?, text: string?, color: Color3?, onTap: (() -> ())?) -> ())
	local so = v and v.social
	local n = if so then so.here else 0
	if so == nil or n <= 0 then
		line("friends", nil, nil)
		return
	end
	local pct = math.floor(so.boost * 100 + 0.5)
	local text = if n == 1 then "1 friend here, +" .. pct .. "% coins" else n .. " friends here, +" .. pct .. "% coins"
	line("friends", "friends", text, UIKit.color("good"), function()
		UIKit.openPanel("top", "friends")
	end)
end

function TopUI.tabOf(): string
	return tab
end

function TopUI.init()
	UIKit.registerPanel("top", { title = "Top@@board", icon = "trophy", w = 380, h = 214, props = { "trophy", "coin", "friends" }, build = build })
end

return TopUI
