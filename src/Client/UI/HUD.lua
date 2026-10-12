-- StarPets: HUD.lua
-- Place in: StarterPlayerScripts > Client > UI > HUD (ModuleScript)
--
-- Everything on screen around the world: the counters, the profile card, the
-- menu, your pets, your quests and the pet you have selected. Laid out after
-- the owner's mockup, which was drawn at 1536x1024, and scaled from there.
--
-- TWO LAYOUTS, because one cannot serve both screens:
--
--   full     a computer or a big tablet. The mockup, as drawn: cards down
--            both sides, your pets along the bottom. Each corner is one group
--            with a UIScale, anchored to its own corner of the screen, so a
--            wider screen spreads the groups apart instead of stretching them.
--   compact  a phone. The same mockup at a phone's size would be a postage
--            stamp, so the cards are left out and their buttons become two
--            rails of 52-point buttons down the sides, clear of Roblox's
--            thumbstick and jump button.
--
-- Switching layouts rebuilds this module's frames from scratch. It happens
-- when a phone rotates or a window is resized across the line, never during
-- play, and a rebuild means neither layout carries the other's leftovers.
--
-- Every button has a fixed name (Dock_Pets, HUD_Mute, ...), the same in both
-- layouts where it exists in both, so the checks can find and press it.
--
-- Nothing here decides anything. Levels, prices and what a switch is allowed
-- to do are the server's; this shows them, and asks.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Player    = Players.LocalPlayer
local PlayerGui = Player.PlayerGui

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local HUD = {}

-- ============================================================
-- LOOK
-- ============================================================
local C = {
	card   = Color3.fromRGB(15, 22, 48),
	raised = Color3.fromRGB(24, 33, 68),
	edge   = Color3.fromRGB(38, 53, 95),
	text   = Color3.fromRGB(255, 255, 255),
	soft   = Color3.fromRGB(184, 195, 224),
	dim    = Color3.fromRGB(120, 132, 168),
	blue   = Color3.fromRGB(42, 125, 255),
	cyan   = Color3.fromRGB(70, 200, 255),
	purple = Color3.fromRGB(125, 60, 255),
	violet = Color3.fromRGB(165, 95, 255),
	green  = Color3.fromRGB(47, 211, 107),
	red    = Color3.fromRGB(232, 57, 77),
	gold   = Color3.fromRGB(255, 204, 51),
	track  = Color3.fromRGB(32, 42, 80),
	grey   = Color3.fromRGB(70, 82, 115),
}
local HEAD = Enum.Font.FredokaOne
local BODY = Enum.Font.GothamBold
local LEFT, CENTER, RIGHT = Enum.TextXAlignment.Left, Enum.TextXAlignment.Center, Enum.TextXAlignment.Right

-- The mockup's canvas. Full layout sizes are written in these pixels.
local REF_W = 1536
-- Below this the cards are too small to read (the smallest label, 13 at
-- design size, would fall under 9 pixels); a finger needs bigger rows than a
-- mouse does, so a touch screen switches to the rails sooner.
local MIN_FULL, MIN_FULL_TOUCH = 0.7, 0.8

-- The menu, as the mockup draws it: eight rows. Eggs opens the hatch screen
-- from anywhere (the owner's call); the world's eggs still work as before.
local NAV = {
	{ name = "Home",        icon = "🏠", label = "Home" },
	{ name = "Pets",        icon = "🐾", label = "Pets",        panel = "PetsPanel" },
	{ name = "Eggs",        icon = "🥚", label = "Eggs",        panel = "HatchPanel" },
	{ name = "Shop",        icon = "🛒", label = "Shop",        panel = "ShopPanel" },
	{ name = "Maps",        icon = "🗺️", label = "Maps",        panel = "MapsPanel" },
	{ name = "Quests",      icon = "📜", label = "Quests",      panel = "QuestPanel" },
	{ name = "Leaderboard", icon = "🏆", label = "Leaderboard", short = "Ranks", panel = "LeaderboardPanel" },
	{ name = "More",        icon = "☰",  label = "More" },
}
local CORNER_BUTTONS = {
	{ name = "Daily", icon = "📅", label = "Daily", panel = "DailyPanel" },
	{ name = "Trade", icon = "👥", label = "Trade", panel = "TradePanel" },
}
local MORE = {
	{ name = "Upgrade",      icon = "⚡", label = "Upgrades",     panel = "UpgradePanel" },
	{ name = "Index",        icon = "📖", label = "Pet Index",    panel = "PetIndexPanel" },
	{ name = "Achievements", icon = "🏅", label = "Achievements", panel = "AchievementsPanel" },
	{ name = "Codes",        icon = "🎁", label = "Codes",        panel = "CodesPanel" },
	{ name = "Merchant",     icon = "🪙", label = "Merchant",     panel = "MerchantPanel" },
	{ name = "Event",        icon = "🎉", label = "Event",        panel = "EventPanel" },
	{ name = "Boosts",       icon = "🚀", label = "Boosts",       panel = "BoostsPanel" },
	{ name = "Fusion",       icon = "🧬", label = "Fusion",       panel = "FusionPanel" },
	{ name = "Playtime",     icon = "⏱️", label = "Playtime",     panel = "PlaytimePanel" },
	{ name = "Spin",         icon = "🎡", label = "Spin",         panel = "SpinWheelPanel" },
}
-- The featured banner, after the egg slides (see slides()). Each is a real
-- feature with a real panel behind its button, described only by what it does.
local FEATURED = {
	{ tag = "LIMITED", icon = "🪙", title = "Traveling Merchant",
	  sub = "Rare pets for coins. Stock changes every visit.", panel = "MerchantPanel" },
	{ tag = "EVERY 12H", icon = "🎡", title = "Lucky Spin",
	  sub = "A free spin every 12 hours. Jackpot: 250 gems.", panel = "SpinWheelPanel" },
	{ tag = "PLAY ON", icon = "⏱️", title = "Playtime Rewards",
	  sub = "The longer you play, the better the prizes.", panel = "PlaytimePanel" },
	{ tag = "BOOST", icon = "🚀", title = "Coin Boosts",
	  sub = "Up to 5x coins for ten minutes, for gems.", panel = "BoostsPanel" },
	{ tag = "FUSE", icon = "🧬", title = "Pet Fusion",
	  sub = "Fuse three of a kind into one stronger pet.", panel = "FusionPanel" },
}
-- The three switches under the mockup's pets.
local SWITCHES = {
	{ kind = "AutoHatch",   name = "HUD_AutoHatch",   icon = "🎯", label = "Auto Hatch",   short = "Hatch" },
	{ kind = "AutoCollect", name = "HUD_AutoCollect", icon = "🧲", label = "Auto Collect", short = "Collect" },
	{ kind = "FastHatch",   name = "HUD_FastHatch",   icon = "👆", label = "Fast Hatch",   short = "Fast" },
}

-- ============================================================
-- STATE
-- ============================================================
local ctx = {}           -- from GameClient: fmt, getData, isMuted, onMute, onSwitch
local gui                -- MysticPetsHUD
local root               -- everything built here; replaced on a layout switch
local mode               -- "full" or "compact"
local s = 1              -- full layout's scale
local refs = {}
local selectedUid = nil
local slide = 1
local questsCache, eventCache = nil, nil
local petSig, questSig = nil, nil
local deleteArmed, shinyArmed = nil, nil
local cardsHidden = false

local PET = {}
for _, p in ipairs(GameConfig.Pets) do PET[p.name] = p end

local function fmt(n)
	if ctx.fmt then return ctx.fmt(n) end
	return tostring(math.floor(n or 0))
end

-- 1,245,678: the counters show the whole number, as the mockup does, until
-- it is too long to be read at a glance.
local function commas(n)
	n = math.floor(tonumber(n) or 0)
	if n >= 1e9 then return fmt(n) end
	local str = tostring(n)
	local out = string.reverse((string.gsub(string.reverse(str), "(%d%d%d)", "%1,")))
	if string.sub(out, 1, 1) == "," then out = string.sub(out, 2) end
	return out
end

local function data()
	return ctx.getData and ctx.getData() or nil
end

local function controller()
	return require(script.Parent.UIController)
end

local function closePopovers()
	if refs.more then refs.more.Visible = false end
	if refs.settings then refs.settings.Visible = false end
end

local function open(panel, ...)
	closePopovers()
	controller().TogglePanel(panel, data(), ...)
end

local function remote(name)
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	return folder and folder:FindFirstChild(name) or nil
end

local function nice(name)
	return (string.gsub(tostring(name or "?"), "(%a)([%w']*)", function(a, b)
		return string.upper(a) .. b
	end))
end

-- ============================================================
-- BUILDING BLOCKS
-- ============================================================
local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	if parent then inst.Parent = parent end
	return inst
end

local function round(inst, px)
	return new("UICorner", { CornerRadius = px and UDim.new(0, px) or UDim.new(1, 0) }, inst)
end

local function edge(inst, color, thickness)
	return new("UIStroke", {
		Name = "Edge", Color = color or C.edge, Thickness = thickness or 2, Transparency = 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, inst)
end

local function text(parent, name, str, x, y, w, h, size, color, font, xa)
	return new("TextLabel", {
		Name = name, Text = str, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
		BackgroundTransparency = 1, BorderSizePixel = 0, TextColor3 = color or C.text,
		Font = font or BODY, TextSize = size, TextXAlignment = xa or LEFT,
		TextYAlignment = Enum.TextYAlignment.Center,
	}, parent)
end

-- A label whose text can grow ("1.2T") shrinks to fit instead of spilling.
local function shrink(label, max, min)
	label.TextScaled = true
	new("UITextSizeConstraint", { MaxTextSize = max, MinTextSize = min or 8 }, label)
	return label
end

local function live(button)
	pcall(function() require(script.Parent.Responsive).Liven(button) end)
	return button
end

local function button(parent, name, x, y, w, h, color, transparency)
	return live(new("TextButton", {
		Name = name, Text = "", AutoButtonColor = false, BorderSizePixel = 0,
		Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = color or C.card, BackgroundTransparency = transparency or 0,
	}, parent))
end

local function card(parent, name, x, y, w, h)
	local f = new("Frame", {
		Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = C.card, BackgroundTransparency = 0.06, BorderSizePixel = 0,
	}, parent)
	round(f, 18); edge(f)
	return f
end

local function gradient(inst, a, b, rotation)
	return new("UIGradient", {
		Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b) }),
		Rotation = rotation or 0,
	}, inst)
end

local function bar(parent, name, x, y, w, h, a, b)
	local track = new("Frame", {
		Name = name, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = C.track, BorderSizePixel = 0,
	}, parent)
	round(track)
	local fill = new("Frame", {
		Name = "Fill", Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = C.text, BorderSizePixel = 0,
	}, track)
	round(fill)
	gradient(fill, a or C.blue, b or C.cyan)
	return track, fill
end

local function setFill(fill, f)
	f = math.clamp(tonumber(f) or 0, 0, 1)
	fill.Size = UDim2.new(f, 0, 1, 0)
	fill.Visible = f > 0.001
end

-- One corner of the screen: a transparent frame of fixed design size, zoomed
-- by its UIScale about its anchor, which is the corner it is pinned to.
local function group(name, w, h, anchor)
	local f = new("Frame", {
		Name = name, Size = UDim2.fromOffset(w, h), AnchorPoint = anchor,
		BackgroundTransparency = 1, BorderSizePixel = 0,
	}, root)
	new("UIScale", { Name = "Fit", Scale = 1 }, f)
	return f
end

local function setScale(f, k)
	local u = f and f:FindFirstChild("Fit")
	if u then u.Scale = k end
end

local function blend(a, b, t)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

-- ============================================================
-- WHAT THE NUMBERS ARE
-- ============================================================
local function slotsFor(d)
	return (d.GP_PetSlots and GameConfig.Settings.VIPPetSlots) or GameConfig.Settings.DefaultPetSlots
end

local function equippedPets(d)
	local byId = {}
	for _, p in ipairs(d.Pets or {}) do byId[p.uniqueId] = p end
	local out = {}
	for _, uid in ipairs(d.EquippedPets or {}) do
		if byId[uid] then table.insert(out, byId[uid]) end
	end
	return out
end

local function boostMult(d)
	local m, now = 1, os.time()
	for id, expire in pairs(d.ActiveBoosts or {}) do
		if type(expire) == "number" and expire > now then
			for _, b in ipairs(GameConfig.Boosts) do
				if b.id == id then m = m * b.mult end
			end
		end
	end
	return m
end

-- What one pet earns a second, counted the way PetService.GetPlayerIncome
-- counts it: the same GameConfig.PetPower and LevelMult, so the card and the
-- coins that arrive can never disagree.
local function income(pet, d)
	local pd = PET[pet.name]
	if not pd then return 0, 0, 1 end
	local power = GameConfig.PetPower(pet)
	local reb = d.RebirthMultiplier or 1
	local coins = pd.coinMult * power * reb * (d.GP_2xCoins and 2 or 1) * boostMult(d)
		* GameConfig.LevelMult(d)
	local gems = (pd.gemMult or 0) * power * reb
		* (d.GP_VIP and GameConfig.Settings.VIPGemMultiplier or 1) * 0.01
	return coins, gems, power
end

local function rarityColor(r)
	local info = GameConfig.Rarities[r or ""]
	return info and info.color or C.grey
end

local function playerLevel(d)
	return GameConfig.LevelFromXP(d and d.XP or 0)
end

local function owns(d, areaId)
	for _, id in ipairs(d.UnlockedAreas or {}) do
		if id == areaId then return true end
	end
	return false
end

local function areaName(id)
	for _, a in ipairs(GameConfig.Areas) do
		if a.id == id then return a.name end
	end
	return id
end

-- The banner's slides: the best egg you can hatch, the next one you cannot
-- yet, then the features.
local function slides()
	local d = data() or {}
	local best, nextEgg
	for _, egg in ipairs(GameConfig.Eggs) do
		if not egg.world or owns(d, egg.world) then
			if egg.currency == "Coins" then best = egg end
		elseif not nextEgg then
			nextEgg = egg
		end
	end
	local out = {}
	if best then
		table.insert(out, { tag = "NEW!", egg = best, title = best.name, sub = best.description,
			eggId = best.id })
	end
	if nextEgg then
		table.insert(out, { tag = "COMING UP", egg = nextEgg, title = nextEgg.name,
			sub = "Unlock " .. areaName(nextEgg.world) .. " to hatch it.", panel = "MapsPanel" })
	end
	for _, f in ipairs(FEATURED) do table.insert(out, f) end
	return out
end

-- What each switch shows: "on", "off", "get" (a pass to buy), or "locked".
local function switchState(kind)
	local d = data() or {}
	if kind == "Mute" then
		local muted = ctx.isMuted and ctx.isMuted() or false
		return muted and "off" or "on"
	elseif kind == "AutoCollect" then
		if not d.GP_AutoCollect then return "get" end
		return d.AutoCollectOff and "off" or "on"
	elseif kind == "AutoHatch" then
		if playerLevel(d) < GameConfig.AutoHatch.level then return "locked" end
		return d.AutoHatch and "on" or "off"
	elseif kind == "FastHatch" then
		return d.FastHatch and "on" or "off"
	elseif kind == "Cards" then
		return cardsHidden and "off" or "on"
	end
	return "off"
end

local function pillLook(kind, st)
	if st == "on" then return "ON", C.green end
	if st == "get" then return "GET", C.gold end
	if st == "locked" then return "LV " .. GameConfig.AutoHatch.level, C.gold end
	return "OFF", C.grey
end

local function pressSwitch(kind)
	local st = switchState(kind)
	if kind == "Mute" then
		if ctx.onMute then ctx.onMute() end
	elseif kind == "Cards" then
		cardsHidden = not cardsHidden
		if refs.groups and refs.groups.right then refs.groups.right.Visible = not cardsHidden end
	elseif st == "get" then
		open("ShopPanel")
	elseif st == "locked" then
		local G = _G.MysticPets
		if G and G.showToast then
			G.showToast("info", ("Auto Hatch opens at Level %d"):format(GameConfig.AutoHatch.level))
		end
	elseif ctx.onSwitch then
		ctx.onSwitch(kind, st ~= "on")
	end
	HUD.RefreshSwitches()
end

-- ============================================================
-- PIECES SHARED BY BOTH LAYOUTS
-- ============================================================
local function pill(parent, name, icon, w, h, plus, plusColor)
	local p = new("Frame", {
		Name = name, Size = UDim2.fromOffset(w, h), BackgroundColor3 = C.card,
		BackgroundTransparency = 0.04, BorderSizePixel = 0,
	}, parent)
	round(p, math.floor(h * 0.3)); edge(p)
	local icon_ = h * 0.66
	text(p, "Icon", icon, h * 0.16, (h - icon_) / 2, icon_, icon_, math.floor(h * 0.5), nil, BODY, CENTER)
	-- Inner pieces are placed from the pill's edges, not at fixed x, so the
	-- compact layout can resize a pill to its share of a phone's width and
	-- the value and the + button still sit inside it.
	local right = plus and (h * 0.69 + 12) or 8
	local value = shrink(text(p, "Value", "0", h * 0.92, 4, 0, h - 8,
		math.floor(h * 0.46), C.text, HEAD), math.floor(h * 0.46))
	value.Size = UDim2.new(1, -(h * 0.92 + right), 0, h - 8)
	local b
	if plus then
		b = button(p, plus, 0, h * 0.155, h * 0.69, h * 0.69, plusColor)
		b.Position = UDim2.new(1, -(h * 0.69 + 6), 0, h * 0.155)
		round(b)
		b.Text = "+"; b.Font = HEAD; b.TextSize = math.floor(h * 0.5); b.TextColor3 = C.text
	end
	return p, value, b
end

local function popover(name, w, h, title)
	local m = new("Frame", {
		Name = name, Size = UDim2.fromOffset(w, h), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = C.card,
		BackgroundTransparency = 0.02, BorderSizePixel = 0, Visible = false, ZIndex = 5,
	}, root)
	round(m, 18); edge(m, C.violet, 2)
	new("UIScale", { Name = "Fit", Scale = 1 }, m)
	text(m, "Title", title, 18, 8, 200, 36, 24, C.text, HEAD)
	local close = button(m, name .. "Close", w - 50, 4, 44, 44, C.raised)
	round(close, 10)
	close.Text = "✕"; close.Font = BODY; close.TextSize = 18; close.TextColor3 = C.soft
	close.MouseButton1Click:Connect(function() m.Visible = false end)
	return m
end

local function moreMenu()
	local cols = 4
	local rows = math.ceil(#MORE / cols)
	local m = popover("MoreMenu", 20 + cols * 96 - 8, 56 + rows * 90, "More")
	for i, item in ipairs(MORE) do
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		local b = button(m, "Dock_" .. item.name, 10 + col * 96, 52 + row * 90, 88, 82, C.raised)
		round(b, 14); edge(b, C.edge, 2)
		text(b, "Icon", item.icon, 0, 8, 88, 38, 30, nil, BODY, CENTER)
		shrink(text(b, "Label", item.label, 3, 50, 82, 24, 14, C.soft, BODY, CENTER), 14, 9)
		b.MouseButton1Click:Connect(function() open(item.panel) end)
	end
	refs.more = m
end

local function settingsMenu()
	local m = popover("SettingsMenu", 320, 196, "Settings")
	local rowsDef = {
		{ kind = "Mute", name = "HUD_Mute", icon = "🔊", label = "Sound" },
		{ kind = "Cards", name = "HUD_HideCards", icon = "📋", label = "Quest & pet cards" },
	}
	refs.settingRows = {}
	for i, r in ipairs(rowsDef) do
		local y = 56 + (i - 1) * 64
		local rowIcon = text(m, "Icon" .. i, r.icon, 16, y + 8, 36, 40, 24, nil, BODY, CENTER)
		local rowLabel = shrink(text(m, "Label" .. i, r.label, 60, y + 8, 150, 40, 18, C.text, HEAD), 18, 10)
		local b = button(m, r.name, 214, y + 6, 92, 44, C.grey)
		round(b)
		b.Text = "ON"; b.Font = HEAD; b.TextSize = 18; b.TextColor3 = C.text
		b.MouseButton1Click:Connect(function() pressSwitch(r.kind) end)
		refs.settingRows[r.kind] = { button = b, icon = rowIcon, label = rowLabel }
	end
	refs.settings = m
end

local function togglePopover(m)
	if not m then return end
	local show = not m.Visible
	closePopovers()
	if show then controller().CloseAll() end
	m.Visible = show
end

-- ============================================================
-- FULL LAYOUT
-- ============================================================
local function buildProfile(parent)
	local prof = card(parent, "Profile", 0, 0, 358, 124)
	local av = new("Frame", {
		Name = "Avatar", Position = UDim2.fromOffset(16, 16), Size = UDim2.fromOffset(92, 92),
		BackgroundColor3 = C.raised, BorderSizePixel = 0,
	}, prof)
	round(av); edge(av, C.blue, 3)
	local face = new("ImageLabel", {
		Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
		-- A content URL rather than GetUserThumbnailAsync: no yield, no
		-- network call from this thread, and Roblox fills it in when ready.
		Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(Player.UserId) .. "&w=150&h=150",
	}, av)
	round(face)
	refs.playerName = shrink(text(prof, "PlayerName", Player.DisplayName or Player.Name,
		122, 10, 222, 32, 26, C.text, HEAD), 26)
	refs.vip = text(prof, "VIP", "👑 VIP", 122, 42, 100, 22, 17, C.gold, HEAD)
	refs.level = text(prof, "Level", "Level 1", 122, 64, 222, 22, 16, C.soft, HEAD)
	local _, fill = bar(prof, "XPBar", 122, 90, 222, 22)
	refs.barFill = fill
	refs.barText = text(prof.XPBar, "Progress", "", 6, 0, 210, 22, 13, C.text, BODY, CENTER)
	refs.barText.TextStrokeTransparency = 0.55
end

local function buildNav(parent)
	local nav = card(parent, "Nav", 0, 134, 265, 430)
	refs.nav = {}
	for i, item in ipairs(NAV) do
		local y = 7 + (i - 1) * 52
		if i > 1 then
			new("Frame", {
				Name = "Rule" .. i, Position = UDim2.fromOffset(18, y - 2), Size = UDim2.fromOffset(229, 1),
				BackgroundColor3 = C.edge, BackgroundTransparency = 0.2, BorderSizePixel = 0,
			}, nav)
		end
		local b = button(nav, "Dock_" .. item.name, 8, y, 249, 49, C.blue, 1)
		round(b, 12)
		text(b, "Icon", item.icon, 10, 8, 34, 34, 24, nil, BODY, CENTER)
		text(b, "Label", item.label, 56, 0, 180, 49, 21, C.text, HEAD)
		b.MouseButton1Click:Connect(function()
			if item.name == "Home" then
				closePopovers()
				controller().CloseAll()
			elseif item.name == "More" then
				togglePopover(refs.more)
			else
				open(item.panel)
			end
		end)
		refs.nav[item.name] = b
	end
end

local function buildEvent(parent)
	local ev = button(parent, "HUD_Event", 0, 576, 265, 105, C.text)
	round(ev, 18); edge(ev, C.violet, 2)
	gradient(ev, Color3.fromRGB(140, 70, 255), Color3.fromRGB(70, 28, 160), 20)
	refs.eventIcon = text(ev, "EventIcon", "🎉", 8, 20, 66, 66, 44, nil, BODY, CENTER)
	text(ev, "Tag", "LIMITED EVENT", 82, 12, 170, 20, 13, C.gold, BODY)
	refs.eventName = shrink(text(ev, "EventName", "", 82, 32, 170, 32, 22, C.text, HEAD), 22, 12)
	refs.eventInfo = shrink(text(ev, "EventInfo", "", 82, 68, 170, 24, 15, C.soft, BODY), 15, 11)
	ev.Visible = false
	ev.MouseButton1Click:Connect(function() open("EventPanel") end)
	refs.event = ev
end

local function buildMyPets(parent)
	local box = card(parent, "MyPets", 0, 0, 354, 328)
	text(box, "Title", "🐾 My Pets", 16, 12, 190, 36, 24, C.text, HEAD)
	refs.petCount = text(box, "Count", "0/3", 196, 12, 96, 36, 20, C.soft, HEAD, RIGHT)
	local add = button(box, "HUD_OpenPets", 302, 12, 36, 36, C.blue)
	round(add)
	add.Text = "+"; add.Font = HEAD; add.TextSize = 26; add.TextColor3 = C.text
	add.MouseButton1Click:Connect(function() open("PetsPanel") end)
	refs.slots = new("Frame", {
		Name = "Slots", Position = UDim2.fromOffset(15, 58), Size = UDim2.fromOffset(324, 256),
		BackgroundTransparency = 1, BorderSizePixel = 0,
	}, box)
end

local function buildSwitchTile(parent, sw, x, y)
	local t = button(parent, sw.name, x, y, 118, 118, C.card, 0.06)
	round(t, 18)
	edge(t, C.edge, 2)
	text(t, "Icon", sw.icon, 0, 10, 118, 44, 34, nil, BODY, CENTER)
	text(t, "Label", sw.label, 4, 56, 110, 24, 16, C.text, HEAD, CENTER)
	local p = new("TextLabel", {
		Name = "State", Position = UDim2.fromOffset(25, 86), Size = UDim2.fromOffset(68, 22),
		BackgroundColor3 = C.green, BorderSizePixel = 0, Text = "ON", TextColor3 = C.text,
		Font = BODY, TextSize = 13,
	}, t)
	round(p)
	t:SetAttribute("HomeX", x); t:SetAttribute("HomeY", y)
	t.MouseButton1Click:Connect(function() pressSwitch(sw.kind) end)
	return t
end

local function buildQuests(parent)
	local q = card(parent, "Quests", 0, 0, 357, 260)
	local head = button(q, "HUD_AllQuests", 8, 8, 341, 40, C.card, 1)
	round(head, 10)
	text(head, "Title", "📋 Active Quests", 8, 2, 240, 36, 22, C.text, HEAD)
	refs.questCount = text(head, "Count", "", 250, 2, 84, 36, 18, C.soft, HEAD, RIGHT)
	head.MouseButton1Click:Connect(function() open("QuestPanel") end)
	refs.questRows = {}
	for i = 1, 3 do
		local row = button(q, "HUD_Quest_" .. i, 10, 52 + (i - 1) * 66, 337, 60, C.raised, 1)
		round(row, 12)
		if i > 1 then
			new("Frame", {
				Name = "Rule", Position = UDim2.fromOffset(8, -4), Size = UDim2.fromOffset(321, 1),
				BackgroundColor3 = C.edge, BackgroundTransparency = 0.2, BorderSizePixel = 0,
			}, row)
		end
		local ring = new("Frame", {
			Name = "Check", Position = UDim2.fromOffset(8, 17), Size = UDim2.fromOffset(26, 26),
			BackgroundColor3 = C.green, BackgroundTransparency = 1, BorderSizePixel = 0,
		}, row)
		round(ring)
		local ringEdge = edge(ring, C.dim, 2)
		local tick = text(ring, "Tick", "✓", 0, 0, 26, 26, 16, C.text, BODY, CENTER)
		local name = shrink(text(row, "QuestName", "", 44, 6, 190, 22, 16, C.text, BODY), 16, 10)
		local amount = shrink(text(row, "Amount", "", 236, 6, 94, 22, 14, C.soft, BODY, RIGHT), 14, 10)
		local _, fill = bar(row, "Track", 44, 36, 286, 12)
		row.MouseButton1Click:Connect(function() open("QuestPanel") end)
		refs.questRows[i] = { row = row, ring = ring, ringEdge = ringEdge, tick = tick,
			name = name, amount = amount, fill = fill }
	end
	refs.questEmpty = text(q, "Empty", "", 16, 60, 325, 180, 16, C.soft, BODY, CENTER)
	refs.questEmpty.TextWrapped = true
end

local function buildFeatured(parent)
	local f = new("Frame", {
		Name = "Featured", Position = UDim2.fromOffset(0, 280), Size = UDim2.fromOffset(357, 162),
		BackgroundColor3 = C.text, BorderSizePixel = 0,
	}, parent)
	round(f, 18); edge(f, C.violet, 2)
	gradient(f, Color3.fromRGB(150, 70, 255), Color3.fromRGB(46, 20, 120), 25)
	local orb = new("Frame", {
		Name = "Art", Position = UDim2.fromOffset(34, 31), Size = UDim2.fromOffset(100, 100),
		BackgroundColor3 = C.violet, BackgroundTransparency = 0.35, BorderSizePixel = 0,
	}, f)
	round(orb)
	local orbEdge = edge(orb, C.text, 2)
	orbEdge.Transparency = 0.6
	local icon = text(orb, "Icon", "", 0, 0, 100, 100, 60, nil, BODY, CENTER)
	local tag = text(f, "Tag", "", 146, 18, 200, 20, 14, C.gold, Enum.Font.GothamBlack)
	local title = shrink(text(f, "FeatureTitle", "", 146, 38, 176, 32, 24, C.text, HEAD), 24, 12)
	local sub = text(f, "FeatureSub", "", 146, 70, 178, 36, 13, Color3.fromRGB(225, 215, 255), BODY)
	sub.TextWrapped = true; sub.TextYAlignment = Enum.TextYAlignment.Top
	local view = button(f, "HUD_FeatureView", 146, 112, 176, 38, C.purple)
	round(view, 12); edge(view, C.violet, 2)
	view.Text = "View"; view.Font = HEAD; view.TextSize = 20; view.TextColor3 = C.text
	local prev = button(f, "HUD_FeaturePrev", 4, 58, 26, 46, C.card, 1)
	prev.Text = "‹"; prev.Font = HEAD; prev.TextSize = 34; prev.TextColor3 = C.text
	local nxt = button(f, "HUD_FeatureNext", 327, 58, 26, 46, C.card, 1)
	nxt.Text = "›"; nxt.Font = HEAD; nxt.TextSize = 34; nxt.TextColor3 = C.text
	refs.feature = { tag = tag, icon = icon, orb = orb, title = title, sub = sub }
	view.MouseButton1Click:Connect(function()
		local item = slides()[slide]
		if not item then return end
		if item.eggId then
			closePopovers()
			controller().Open("HatchPanel", data(), item.eggId)
		else
			open(item.panel)
		end
	end)
	prev.MouseButton1Click:Connect(function() HUD.ShowSlide(slide - 1) end)
	nxt.MouseButton1Click:Connect(function() HUD.ShowSlide(slide + 1) end)
end

local function buildDetail(parent)
	local d = card(parent, "Detail", 0, 471, 357, 382)
	local portrait = new("Frame", {
		Name = "Portrait", Position = UDim2.fromOffset(16, 16), Size = UDim2.fromOffset(104, 104),
		BackgroundColor3 = C.raised, BorderSizePixel = 0,
	}, d)
	round(portrait, 16)
	edge(portrait, C.edge, 2)
	local name = shrink(text(d, "DetailName", "", 132, 16, 166, 32, 24, C.text, HEAD), 24, 12)
	local lock = button(d, "HUD_Lock", 305, 14, 36, 36, C.raised)
	round(lock, 10)
	lock.Text = "🔓"; lock.Font = BODY; lock.TextSize = 18
	local rarity = new("TextLabel", {
		Name = "Rarity", Position = UDim2.fromOffset(132, 54), Size = UDim2.fromOffset(100, 24),
		BackgroundColor3 = C.grey, BorderSizePixel = 0, Text = "", TextColor3 = C.text,
		Font = BODY, TextSize = 13,
	}, d)
	round(rarity, 8)
	local lvl = new("TextLabel", {
		Name = "PetLevel", Position = UDim2.fromOffset(238, 54), Size = UDim2.fromOffset(103, 24),
		BackgroundColor3 = C.raised, BorderSizePixel = 0, Text = "", TextColor3 = C.text,
		Font = HEAD, TextSize = 15,
	}, d)
	round(lvl, 8)
	local _, xpFill = bar(d, "PetXP", 132, 86, 209, 12)
	local xpText = shrink(text(d, "PetXPText", "", 132, 100, 209, 20, 13, C.soft, BODY), 13, 10)
	local stats = new("Frame", {
		Name = "Stats", Position = UDim2.fromOffset(16, 136), Size = UDim2.fromOffset(325, 138),
		BackgroundColor3 = C.raised, BorderSizePixel = 0,
	}, d)
	round(stats, 14)
	local rows = {}
	local STATS = { { "💰", "Coins" }, { "💎", "Gems" }, { "✨", "Bonus" } }
	for i, st in ipairs(STATS) do
		local y = 8 + (i - 1) * 42
		if i > 1 then
			new("Frame", {
				Name = "Rule" .. i, Position = UDim2.fromOffset(12, y - 3), Size = UDim2.fromOffset(301, 1),
				BackgroundColor3 = C.edge, BackgroundTransparency = 0.2, BorderSizePixel = 0,
			}, stats)
		end
		text(stats, "Icon" .. i, st[1], 12, y + 4, 30, 30, 20, nil, BODY, CENTER)
		text(stats, "Stat" .. i, st[2], 50, y, 120, 38, 17, C.soft, BODY)
		rows[i] = shrink(text(stats, "Value" .. i, "", 150, y, 163, 38, 18, C.green, HEAD, RIGHT), 18, 11)
	end
	local unequip = button(d, "HUD_Unequip", 16, 290, 136, 52, C.blue)
	round(unequip, 14)
	unequip.Text = "Unequip"; unequip.Font = HEAD; unequip.TextSize = 20; unequip.TextColor3 = C.text
	local shiny = button(d, "HUD_Shiny", 160, 290, 128, 52, C.purple)
	round(shiny, 14)
	shiny.Text = "✨ Shiny"; shiny.Font = HEAD; shiny.TextSize = 20; shiny.TextColor3 = C.text
	local del = button(d, "HUD_Delete", 296, 290, 45, 52, C.red)
	round(del, 14)
	del.Text = "🗑"; del.Font = BODY; del.TextSize = 22; del.TextColor3 = C.text
	local hint = shrink(text(d, "ShinyHint", "", 16, 348, 325, 22, 13, C.soft, BODY, CENTER), 13, 10)
	local empty = text(d, "Empty", "Equip a pet to see it here.\nPress Eggs to hatch one!",
		16, 140, 325, 140, 17, C.soft, BODY, CENTER)
	empty.TextWrapped = true
	refs.detail = { box = d, portrait = portrait, name = name, lock = lock, rarity = rarity,
		lvl = lvl, xpFill = xpFill, xpText = xpText, xpBar = d.PetXP, stats = stats, rows = rows,
		unequip = unequip, shiny = shiny, del = del, hint = hint, empty = empty }

	unequip.MouseButton1Click:Connect(function()
		local rf = remote("UnequipPet")
		if rf and selectedUid then rf:FireServer(selectedUid) end
	end)
	lock.MouseButton1Click:Connect(function()
		local rf = remote("PetCmd")
		if rf and selectedUid then rf:FireServer("lock", selectedUid) end
	end)
	-- Both spend something that cannot be bought back, so both ask first.
	local function twoPress(btn, armedName, label, size, fire)
		btn.MouseButton1Click:Connect(function()
			if not selectedUid or btn.Active == false then return end
			local armed = armedName == "delete" and deleteArmed or shinyArmed
			if armed ~= selectedUid then
				if armedName == "delete" then deleteArmed = selectedUid else shinyArmed = selectedUid end
				btn.Text = label(); btn.TextSize = 13
				local armedFor = selectedUid
				task.delay(3, function()
					local still = armedName == "delete" and deleteArmed or shinyArmed
					if still == armedFor then
						if armedName == "delete" then deleteArmed = nil else shinyArmed = nil end
						HUD.Update(data())
					end
				end)
				return
			end
			if armedName == "delete" then deleteArmed = nil else shinyArmed = nil end
			btn.TextSize = size
			fire(selectedUid)
		end)
	end
	twoPress(del, "delete", function() return "Sure?" end, 22, function(uid)
		del.Text = "🗑"
		local rf = remote("DeletePet")
		if rf then rf:FireServer(uid) end
	end)
	twoPress(shiny, "shiny", function()
		local d_ = data() or {}
		for _, p in ipairs(d_.Pets or {}) do
			if p.uniqueId == selectedUid then
				return "Sure? " .. commas(GameConfig.ShinyCost[p.rarity] or 0) .. " 💎"
			end
		end
		return "Sure?"
	end, 20, function(uid)
		shiny.Text = "✨ Shiny"
		local rf = remote("PetCmd")
		if rf then rf:FireServer("makeShiny", uid) end
	end)
end

local function buildFull()
	local pills = group("TopPills", 718, 58, Vector2.new(0.5, 0))
	local p1, coins, add1 = pill(pills, "Coins", "🪙", 230, 58, "HUD_AddCoins", C.blue)
	local p2, gems, add2 = pill(pills, "Gems", "💎", 230, 58, "HUD_AddGems", C.purple)
	local p3, pets, add3 = pill(pills, "PetsPill", "🐾", 230, 58, "HUD_AddPets", C.grey)
	p1.Position = UDim2.fromOffset(0, 0); p2.Position = UDim2.fromOffset(244, 0)
	p3.Position = UDim2.fromOffset(488, 0)
	refs.coins, refs.gems, refs.pets = coins, gems, pets
	-- Coins and gems are not sold for Robux in this game; the Shop is where
	-- the passes that multiply them are.
	add1.MouseButton1Click:Connect(function() open("ShopPanel") end)
	add2.MouseButton1Click:Connect(function() open("ShopPanel") end)
	add3.MouseButton1Click:Connect(function() open("PetsPanel") end)

	local corner_ = group("TopRight", 180, 58, Vector2.new(1, 0))
	for i, item in ipairs(CORNER_BUTTONS) do
		local b = button(corner_, "Dock_" .. item.name, (i - 1) * 61, 0, 58, 58, C.card, 0.04)
		round(b, 16); edge(b)
		text(b, "Icon", item.icon, 0, 0, 58, 58, 28, nil, BODY, CENTER)
		b.MouseButton1Click:Connect(function() open(item.panel) end)
	end
	local gear = button(corner_, "HUD_Settings", 122, 0, 58, 58, C.card, 0.04)
	round(gear, 16); edge(gear)
	text(gear, "Icon", "⚙️", 0, 0, 58, 58, 28, nil, BODY, CENTER)
	gear.MouseButton1Click:Connect(function() togglePopover(refs.settings) end)

	local left = group("LeftColumn", 358, 681, Vector2.new(0, 0))
	buildProfile(left)
	buildNav(left)
	buildEvent(left)

	local bottom = group("BottomGroup", 798, 328, Vector2.new(0, 1))
	buildMyPets(bottom)
	refs.switches = {}
	for i, sw in ipairs(SWITCHES) do
		refs.switches[sw.kind] = buildSwitchTile(bottom, sw, 412 + (i - 1) * 134, 210)
	end

	local right = group("RightColumn", 357, 853, Vector2.new(1, 0))
	right.Visible = not cardsHidden
	buildQuests(right)
	buildFeatured(right)
	buildDetail(right)

	refs.groups = { pills = pills, corner = corner_, left = left, bottom = bottom, right = right }
	moreMenu()
	settingsMenu()
end

-- ============================================================
-- COMPACT LAYOUT
-- ============================================================
local RAIL = 52
local RAIL_GAP = 6

local function railButton(name, icon, label)
	local b = button(root, name, 0, 0, RAIL, RAIL, C.card, 0.04)
	round(b, 14)
	edge(b, C.edge, 2)
	text(b, "Icon", icon, 0, 3, RAIL, 30, 22, nil, BODY, CENTER)
	shrink(text(b, "Label", label, 1, 32, RAIL - 2, 16, 10, C.soft, BODY, CENTER), 10, 9)
	return b
end

local function buildCompact()
	local p1, coins = pill(root, "Coins", "🪙", 120, 40)
	local p2, gems = pill(root, "Gems", "💎", 120, 40)
	local p3, pets = pill(root, "PetsPill", "🐾", 120, 40)
	refs.coins, refs.gems, refs.pets = coins, gems, pets
	refs.compactPills = { p1, p2, p3 }

	local chip = new("Frame", {
		Name = "LevelChip", Size = UDim2.fromOffset(176, 26), AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = C.card, BackgroundTransparency = 0.04, BorderSizePixel = 0,
	}, root)
	round(chip); edge(chip)
	local fill = new("Frame", {
		Name = "Fill", Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = C.text,
		BackgroundTransparency = 0.25, BorderSizePixel = 0,
	}, chip)
	round(fill)
	gradient(fill, C.blue, C.cyan)
	refs.barFill = fill
	refs.barText = text(chip, "Progress", "", 6, 0, 164, 26, 12, C.text, BODY, CENTER)
	refs.barText.TextStrokeTransparency = 0.55
	refs.chip = chip

	refs.leftRail, refs.rightRail, refs.nav = {}, {}, {}
	for _, item in ipairs(NAV) do
		if item.name ~= "Home" then
			local b = railButton("Dock_" .. item.name, item.icon, item.short or item.label)
			b.MouseButton1Click:Connect(function()
				if item.name == "More" then togglePopover(refs.more) else open(item.panel) end
			end)
			table.insert(refs.leftRail, b)
			refs.nav[item.name] = b
		end
	end
	for _, item in ipairs(CORNER_BUTTONS) do
		local b = railButton("Dock_" .. item.name, item.icon, item.label)
		b.MouseButton1Click:Connect(function() open(item.panel) end)
		table.insert(refs.rightRail, b)
	end
	local gear = railButton("HUD_Settings", "⚙️", "Settings")
	gear.MouseButton1Click:Connect(function() togglePopover(refs.settings) end)
	table.insert(refs.rightRail, gear)
	refs.switches = {}
	for _, sw in ipairs(SWITCHES) do
		local b = railButton(sw.name, sw.icon, sw.short)
		b.MouseButton1Click:Connect(function() pressSwitch(sw.kind) end)
		table.insert(refs.rightRail, b)
		refs.switches[sw.kind] = b
	end
	moreMenu()
	settingsMenu()
end

-- ============================================================
-- PLACING (runs on every screen size change)
-- ============================================================
local function viewport()
	local cam = workspace.CurrentCamera
	local v = cam and cam.ViewportSize
	local w, h = v and v.X, v and v.Y
	if type(w) ~= "number" or w <= 0 then w = 1280 end
	if type(h) ~= "number" or h <= 0 then h = 720 end
	return w, h
end

local function touchOnly()
	local ok, res = pcall(function()
		local uis = game:GetService("UserInputService")
		return uis.TouchEnabled == true and uis.KeyboardEnabled ~= true
	end)
	return ok and res == true
end

-- Where Roblox's own top bar leaves room: x from minX to maxX, below height.
local function topbar(W)
	local minX, maxX, height = 104, W, 58
	pcall(function()
		local r = game:GetService("GuiService").TopbarInset
		if typeof(r) == "Rect" and r.Height > 0 then
			minX, maxX, height = r.Min.X, r.Max.X, r.Height
		end
	end)
	return math.max(minX, 0), maxX, height
end

-- The full layout's zoom. Width as drawn; height by what actually has to fit,
-- which is the right-hand column (938 tall, top margin included), so a
-- 16:9 screen gets cards as big as its height allows rather than as big as
-- the mockup's 3:2 canvas would allow.
local function fullScale(W, H)
	return math.min(W / REF_W, (H - 8) / 938)
end

local function wantMode(W, H)
	local k = fullScale(W, H)
	local need = touchOnly() and MIN_FULL_TOUCH or MIN_FULL
	return k >= need and "full" or "compact"
end

local function placeFull(W, H)
	s = fullScale(W, H)
	local _, maxX, barH = topbar(W)
	local g = refs.groups
	for _, f in pairs(g) do setScale(f, s) end

	g.pills.Position = UDim2.fromOffset(W / 2, 30 * s)
	-- Roblox puts nothing at the top right unless something is enabled there;
	-- if it has, the corner buttons drop below its bar instead of under it.
	local cornerTop = 16 * s
	if maxX < W - 20 then cornerTop = barH + 6 end
	g.corner.Position = UDim2.fromOffset(W - 14 * s, cornerTop)
	local leftTop = math.max(84 * s, barH + 6)
	g.left.Position = UDim2.fromOffset(15 * s, leftTop)
	g.bottom.Position = UDim2.fromOffset(296 * s, H - 59 * s)

	local rightTop = math.max(85 * s, cornerTop + 68 * s)
	local rs = s
	if rightTop + 853 * rs > H - 8 then rs = math.max(0.3, (H - 8 - rightTop) / 853) end
	setScale(g.right, rs)
	g.right.Position = UDim2.fromOffset(W - 16 * s, rightTop)

	-- More opens beside the menu, level with its bottom row; Settings drops
	-- down from the gear.
	setScale(refs.more, math.max(s, 0.75))
	refs.more.AnchorPoint = Vector2.new(0, 1)
	refs.more.Position = UDim2.fromOffset((15 + 265 + 12) * s, leftTop + (134 + 430) * s)
	setScale(refs.settings, math.max(s, 0.75))
	refs.settings.AnchorPoint = Vector2.new(1, 0)
	refs.settings.Position = UDim2.fromOffset(W - 14 * s, cornerTop + 66 * s)
end

local narrow = false

local function placeCompact(W, H)
	local minX = topbar(W)
	local gap = 6
	local left = math.max(minX, 100)
	local avail = W - left - 8
	local pw = math.min(170, math.floor((avail - 2 * gap) / 3))
	-- Three counters in what is left of an upright phone's top row are under
	-- a hundred points each, too narrow for "123.5M" at a size anyone can
	-- read. There, coins and gems share the top row and the pet count drops
	-- to the second, beside the level bar, where Roblox's buttons are not.
	narrow = pw < 110
	local pills = refs.compactPills
	if narrow then
		local w2 = math.floor((avail - gap) / 2)
		for i = 1, 2 do
			pills[i].Size = UDim2.fromOffset(w2, 40)
			pills[i].Position = UDim2.fromOffset(left + (i - 1) * (w2 + gap), 8)
		end
		pills[3].Size = UDim2.fromOffset(104, 40)
		pills[3].Position = UDim2.fromOffset(8, 54)
		refs.chip.AnchorPoint = Vector2.new(0, 0)
		refs.chip.Size = UDim2.fromOffset(W - 128, 26)
		refs.chip.Position = UDim2.fromOffset(120, 61)
		refs.barText.Size = UDim2.fromOffset(W - 140, 26)
	else
		local x0 = left + math.floor((avail - (3 * pw + 2 * gap)) / 2)
		for i, p in ipairs(pills) do
			p.Size = UDim2.fromOffset(pw, 40)
			p.Position = UDim2.fromOffset(x0 + (i - 1) * (pw + gap), 8)
		end
		refs.chip.AnchorPoint = Vector2.new(0.5, 0)
		refs.chip.Size = UDim2.fromOffset(176, 26)
		refs.chip.Position = UDim2.fromOffset(W / 2, 54)
		refs.barText.Size = UDim2.fromOffset(164, 26)
	end

	-- The onboarding card hangs at the top centre while a new player learns
	-- the game. On a narrow screen it spans the width, so the rails start
	-- below it instead of underneath it.
	local railTop = 88
	if W < 470 + 2 * (RAIL + 16) then railTop = narrow and 190 or 176 end
	-- Room above the thumbstick (left) and the jump button (right): the
	-- bottom quarter of the screen is left to Roblox's own touch controls.
	local railBottom = math.floor(H * 0.75)
	local perCol = math.max(1, math.floor((railBottom - railTop + RAIL_GAP) / (RAIL + RAIL_GAP)))

	local function rail(list, fromRight)
		for i, b in ipairs(list) do
			local col, row = math.floor((i - 1) / perCol), (i - 1) % perCol
			local x = 8 + col * (RAIL + RAIL_GAP)
			if fromRight then x = W - 8 - RAIL - col * (RAIL + RAIL_GAP) end
			b.Position = UDim2.fromOffset(x, railTop + row * (RAIL + RAIL_GAP))
		end
	end
	rail(refs.leftRail, false)
	rail(refs.rightRail, true)

	for _, m in ipairs({ refs.more, refs.settings }) do
		local size = m.Size
		setScale(m, math.min(1, (W - 16) / size.X.Offset, (H - 16) / size.Y.Offset))
		m.AnchorPoint = Vector2.new(0.5, 0.5)
		m.Position = UDim2.fromScale(0.5, 0.5)
	end
end

-- ============================================================
-- FILLING IN (runs on every data update)
-- ============================================================
local function showPet(holder, pet)
	local ok, PetView = pcall(function() return require(script.Parent.PetView) end)
	local shown = ok and PetView and PetView.Show(holder, pet.name, { mutation = pet.mutation })
	if not shown then
		text(holder, "Letter", string.upper(string.sub(tostring(pet.name), 1, 1)),
			0, 0, holder.Size.X.Offset, holder.Size.Y.Offset, 30, C.text, HEAD, CENTER)
	end
end

local buildSlots

local function drawSlots(d)
	if not refs.slots then return end
	local pets = equippedPets(d)
	local slots = slotsFor(d)
	-- The selection is NOT part of this: picking a pet restyles two borders,
	-- it does not rebuild six 3D previews.
	local parts = { tostring(slots) }
	for _, p in ipairs(pets) do
		table.insert(parts, tostring(p.uniqueId) .. (p.locked and "L" or "") .. tostring(p.mutation)
			.. ":" .. tostring(p.level or 1))
	end
	local sig = table.concat(parts, "|")
	if sig ~= petSig then
		petSig = sig
		buildSlots(pets, slots)
	end
	for uid, e in pairs(refs.cellEdges or {}) do
		local chosen = uid == selectedUid
		e.stroke.Color = chosen and C.text or e.color
		e.stroke.Thickness = chosen and 3 or 2
	end
end

buildSlots = function(pets, slots)
	refs.slots:ClearAllChildren()
	refs.cellEdges = {}
	for i = 1, GameConfig.Settings.VIPPetSlots do
		local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
		local x, y = col * 111, row * 132
		local pet = pets[i]
		if pet then
			local cell = button(refs.slots, "HUD_Pet_" .. i, x, y, 102, 124, C.raised)
			round(cell, 14)
			refs.cellEdges[pet.uniqueId] = {
				stroke = edge(cell, rarityColor(pet.rarity), 2), color = rarityColor(pet.rarity) }
			local view = new("Frame", {
				Name = "View", Position = UDim2.fromOffset(18, 4), Size = UDim2.fromOffset(66, 56),
				BackgroundTransparency = 1, BorderSizePixel = 0,
			}, cell)
			showPet(view, pet)
			shrink(text(cell, "PetName", nice(pet.name), 4, 60, 94, 18, 14, C.text, BODY, CENTER), 14, 9)
			text(cell, "PetLevel", "Level " .. (tonumber(pet.level) or 1), 4, 78, 94, 16, 13, C.soft, BODY, CENTER)
			local r = new("TextLabel", {
				Name = "Rarity", Position = UDim2.fromOffset(6, 98), Size = UDim2.fromOffset(90, 20),
				BackgroundColor3 = rarityColor(pet.rarity), BorderSizePixel = 0,
				Text = tostring(pet.rarity or ""), TextColor3 = C.text, Font = BODY, TextSize = 13,
			}, cell)
			round(r)
			if pet.locked then text(cell, "Locked", "🔒", 78, 4, 20, 20, 14, nil, BODY, CENTER) end
			if pet.mutation then
				local m = GameConfig.GetMutation and GameConfig.GetMutation(pet.mutation)
				text(cell, "Mutation", m and m.emoji or "✨", 4, 4, 20, 20, 14, nil, BODY, CENTER)
			end
			local uid = pet.uniqueId
			cell.MouseButton1Click:Connect(function()
				selectedUid = uid
				deleteArmed, shinyArmed = nil, nil
				HUD.Update(data())
			end)
		elseif i <= slots then
			local cell = button(refs.slots, "HUD_Slot_" .. i, x, y, 102, 124, C.raised, 0.35)
			round(cell, 14); edge(cell, C.edge, 2)
			text(cell, "Plus", "+", 0, 20, 102, 44, 40, C.dim, HEAD, CENTER)
			text(cell, "Label", "Equip Pet", 0, 70, 102, 24, 14, C.dim, BODY, CENTER)
			cell.MouseButton1Click:Connect(function() open("PetsPanel") end)
		else
			local cell = button(refs.slots, "HUD_SlotLocked_" .. i, x, y, 102, 124, C.card, 0.5)
			round(cell, 14); edge(cell, C.edge, 1)
			text(cell, "Lock", "🔒", 0, 22, 102, 40, 28, nil, BODY, CENTER)
			text(cell, "Label", "+3 Slots", 0, 70, 102, 24, 14, C.dim, BODY, CENTER)
			cell.MouseButton1Click:Connect(function() open("ShopPanel") end)
		end
	end
end

local function pct(mult)
	return "+" .. math.floor((mult - 1) * 100 + 0.5) .. "%"
end

local function drawDetail(d)
	local v = refs.detail
	if not v then return end
	local pets = equippedPets(d)
	local pet
	for _, p in ipairs(pets) do if p.uniqueId == selectedUid then pet = p end end
	if not pet then
		pet = pets[1]
		selectedUid = pet and pet.uniqueId or nil
	end
	local has = pet ~= nil
	for _, k in ipairs({ "stats", "unequip", "shiny", "del", "lock", "rarity", "lvl", "xpBar",
		"xpText", "hint" }) do
		v[k].Visible = has
	end
	v.empty.Visible = not has
	if not has then
		v.name.Text = "No pet selected"
		if v.shown ~= "none" then
			v.shown = "none"
			v.portrait:ClearAllChildren()
			round(v.portrait, 16)
			edge(v.portrait, C.edge, 2)
			v.portrait.BackgroundColor3 = C.raised
		end
		return
	end
	local mut = GameConfig.GetMutation and GameConfig.GetMutation(pet.mutation)
	if v.shown ~= pet.uniqueId .. tostring(pet.mutation) then
		v.shown = pet.uniqueId .. tostring(pet.mutation)
		v.portrait:ClearAllChildren()
		round(v.portrait, 16)
		edge(v.portrait, (mut and mut.color) or rarityColor(pet.rarity), 3)
		showPet(v.portrait, pet)
	end
	v.portrait.BackgroundColor3 = blend(rarityColor(pet.rarity), C.raised, 0.65)
	v.name.Text = (mut and (mut.emoji .. " ") or "") .. nice(pet.name)
	v.lock.Text = pet.locked and "🔒" or "🔓"
	v.rarity.Text = tostring(pet.rarity or "")
	v.rarity.BackgroundColor3 = rarityColor(pet.rarity)

	local P = GameConfig.PetLevels
	local level = tonumber(pet.level) or 1
	v.lvl.Text = "Level " .. level
	if level >= P.max then
		setFill(v.xpFill, 1)
		v.xpText.Text = "Max Level (" .. P.max .. ")"
	else
		local need = GameConfig.PetXPForLevel(level)
		local into = math.floor(tonumber(pet.xp) or 0)
		setFill(v.xpFill, into / need)
		v.xpText.Text = commas(into) .. " / " .. commas(need) .. " XP to Level " .. (level + 1)
	end

	local coins, gems, power = income(pet, d)
	v.rows[1].Text = "+" .. fmt(coins) .. "/s"
	v.rows[2].Text = gems > 0 and ("+" .. (gems >= 10 and fmt(gems) or string.format("%.2f", gems)) .. "/s") or "—"
	v.rows[3].Text = pct(power)

	-- Delete: never a locked pet.
	v.del.Active = not pet.locked
	v.del.BackgroundTransparency = pet.locked and 0.6 or 0
	if deleteArmed ~= pet.uniqueId and v.del.Text ~= "🗑" then
		v.del.Text = "🗑"; v.del.TextSize = 22
	end

	-- Shiny: a plain or Golden pet, for gems by rarity.
	local cost = GameConfig.ShinyCost[pet.rarity]
	local gemsHave = d.Gems or 0
	local why
	if pet.mutation == "Shiny" then why = "Already Shiny: x4 coins"
	elseif pet.mutation == "Rainbow" then why = "Rainbow already beats Shiny"
	elseif not cost then why = "Cannot be made Shiny"
	elseif gemsHave < cost then why = "Shiny x4 coins: need " .. commas(cost - gemsHave) .. " more 💎"
	end
	v.shiny.Active = why == nil
	v.shiny.BackgroundTransparency = why and 0.55 or 0
	v.hint.Text = why or ("Shiny: x4 coins for " .. commas(cost) .. " 💎")
	if shinyArmed ~= pet.uniqueId and v.shiny.Text ~= "✨ Shiny" then
		v.shiny.Text = "✨ Shiny"; v.shiny.TextSize = 20
	end
end

local function drawProfile(d)
	if not refs.barFill then return end
	local level, into, need = playerLevel(d)
	if need then
		setFill(refs.barFill, into / need)
	else
		setFill(refs.barFill, 1)
	end
	if mode == "compact" then
		refs.barText.Text = "⭐ Level " .. level .. (need and ("  ·  " .. fmt(into) .. "/" .. fmt(need)) or "  ·  MAX")
		return
	end
	refs.barText.Text = need and (commas(into) .. " / " .. commas(need) .. " XP") or "MAX LEVEL"
	local reb = d.Rebirths or 0
	refs.level.Text = "Level " .. level .. (reb > 0 and ("   ♻️ Rebirth " .. reb) or "")
	refs.vip.Visible = d.GP_VIP == true
	-- Without the VIP line the level moves up into its place.
	refs.level.Position = UDim2.fromOffset(122, d.GP_VIP and 64 or 46)
	refs.barText.Parent.Position = UDim2.fromOffset(122, d.GP_VIP and 90 or 74)
end

local function drawQuests()
	local rows = refs.questRows
	if not rows then return end
	local open_, dailyDone, dailyAll = {}, 0, 0
	for _, q in ipairs(questsCache or {}) do
		if type(q) == "table" then
			if q.kind == "daily" then
				dailyAll = dailyAll + 1
				if q.done or q.claimed then dailyDone = dailyDone + 1 end
			end
			if not q.claimed then table.insert(open_, q) end
		end
	end
	-- Ready to claim first, then today's, then whatever is closest to done.
	local function rank(q)
		local f = (tonumber(q.progress) or 0) / math.max(1, tonumber(q.goal) or 1)
		return (q.done and 2 or 0) + (q.kind == "daily" and 1 or 0) + f * 0.99
	end
	table.sort(open_, function(a, b) return rank(a) > rank(b) end)
	local sig = {}
	for i = 1, 3 do
		local q = open_[i]
		sig[i] = q and (tostring(q.id) .. ":" .. tostring(q.progress) .. ":" .. tostring(q.done)) or "-"
	end
	sig = table.concat(sig, "|") .. "|" .. tostring(questsCache ~= nil) .. "|" .. dailyDone
	if sig == questSig then return end
	questSig = sig
	refs.questCount.Text = dailyAll > 0 and (dailyDone .. "/" .. dailyAll) or ""
	for i, r in ipairs(rows) do
		local q = open_[i]
		r.row.Visible = q ~= nil
		if q then
			local goal = math.max(1, tonumber(q.goal) or 1)
			local prog = math.min(goal, tonumber(q.progress) or 0)
			r.name.Text = tostring(q.name or q.desc or "Quest")
			setFill(r.fill, prog / goal)
			if q.done then
				r.amount.Text = "Completed!"; r.amount.TextColor3 = C.green
				r.ring.BackgroundTransparency = 0; r.ringEdge.Color = C.green
				r.tick.Visible = true
			else
				r.amount.Text = commas(prog) .. " / " .. commas(goal); r.amount.TextColor3 = C.soft
				r.ring.BackgroundTransparency = 1; r.ringEdge.Color = C.dim
				r.tick.Visible = false
			end
		end
	end
	if questsCache == nil then
		refs.questEmpty.Text = "Loading quests…"
	elseif #open_ == 0 then
		refs.questEmpty.Text = "🎉 Every quest claimed!\nNew daily quests at midnight (UTC)."
	else
		refs.questEmpty.Text = ""
	end
	refs.questEmpty.Visible = #open_ == 0
end

local function drawEvent()
	if not refs.event then return end
	local e = eventCache
	local on = type(e) == "table" and e.active == true
	refs.event.Visible = on
	if on then
		refs.eventIcon.Text = tostring(e.tokenIcon or "🎉")
		refs.eventName.Text = tostring(e.name or "Event")
		refs.eventInfo.Text = commas(tonumber(e.tokens) or 0) .. " " .. tostring(e.tokenName or "tokens")
			.. "  ·  Shop"
	end
end

function HUD.RefreshSwitches()
	for _, sw in ipairs(SWITCHES) do
		local b = refs.switches and refs.switches[sw.kind]
		if b and b.Parent then
			local st = switchState(sw.kind)
			local label, color = pillLook(sw.kind, st)
			local e = b:FindFirstChild("Edge")
			local pillLabel = b:FindFirstChild("State")
			if pillLabel then
				pillLabel.Text = label; pillLabel.BackgroundColor3 = color
			end
			if e then
				e.Color = st == "on" and C.green or C.edge
				e.Thickness = st == "on" and 3 or 2
			end
			-- The mockup's switched-on tile stands out: a little bigger, with
			-- a green ring. Grown about its centre so it never reaches a neighbour.
			local hx, hy = b:GetAttribute("HomeX"), b:GetAttribute("HomeY")
			if hx and hy then
				local grow = st == "on" and 6 or 0
				b.Position = UDim2.fromOffset(hx - grow, hy - grow)
				b.Size = UDim2.fromOffset(118 + 2 * grow, 118 + grow)
				b.BackgroundColor3 = st == "on" and Color3.fromRGB(18, 44, 46) or C.card
			end
			if mode == "compact" then
				local lbl = b:FindFirstChild("Label")
				if lbl then lbl.Text = st == "locked" and ("Lv " .. GameConfig.AutoHatch.level) or sw.short end
			end
		end
	end
	for kind, r in pairs(refs.settingRows or {}) do
		local st = switchState(kind)
		r.button.Text = st == "on" and (kind == "Cards" and "SHOWN" or "ON") or (kind == "Cards" and "HIDDEN" or "OFF")
		r.button.BackgroundColor3 = st == "on" and C.green or C.grey
		if kind == "Mute" then r.icon.Text = st == "off" and "🔇" or "🔊" end
	end
end

function HUD.ShowSlide(i)
	local list = slides()
	local n = #list
	slide = ((i - 1) % n + n) % n + 1
	local f, item = refs.feature, list[slide]
	if not f or not item then return end
	f.tag.Text = item.tag
	f.title.Text = item.title; f.sub.Text = item.sub
	if item.egg then
		f.icon.Text = "🥚"
		f.orb.BackgroundColor3 = item.egg.color or C.violet
	else
		f.icon.Text = item.icon
		f.orb.BackgroundColor3 = C.violet
	end
end

-- ============================================================
-- KEEPING UP (cheap, on a timer; never every frame)
-- ============================================================
local lastQuests = -math.huge

local function fetchQuests(force)
	if mode ~= "full" then return end
	local now = os.clock()
	if not force and now - lastQuests < 4 then return end
	lastQuests = now
	local rf = remote("GetQuests")
	if not rf then return end
	task.spawn(function()
		local ok, list = pcall(function() return rf:InvokeServer() end)
		if ok and type(list) == "table" then
			questsCache = list
			drawQuests()
		end
	end)
end

local function fetchEvent()
	if mode ~= "full" then return end
	local rf = remote("GetEvent")
	if not rf then return end
	task.spawn(function()
		local ok, st = pcall(function() return rf:InvokeServer() end)
		if ok and type(st) == "table" then
			eventCache = st
			drawEvent()
		end
	end)
end

-- Which panel is open, shown on its button. Read off PlayerGui rather than
-- tracked, so a panel closed by its own ✕ is never left highlighted.
local function markOpen()
	if not refs.nav then return end
	local current = nil
	for _, item in ipairs(NAV) do
		if item.panel and PlayerGui:FindFirstChild(item.panel) then current = item.name end
	end
	if refs.more and refs.more.Visible then current = "More" end
	if mode == "full" and not current then current = "Home" end
	for name, b in pairs(refs.nav) do
		local on = name == current
		if mode == "full" then
			b.BackgroundTransparency = on and 0 or 1
		else
			local e = b:FindFirstChild("Edge")
			if e then e.Color = on and C.blue or C.edge; e.Thickness = on and 3 or 2 end
		end
	end
end

-- ============================================================
-- PUBLIC
-- ============================================================
function HUD.Init(context, screen)
	ctx = context or {}
	gui = screen
	local acc, slideAcc, questAcc, eventAcc = 0, 0, 0, 0
	RunService.Heartbeat:Connect(function(dt)
		dt = tonumber(dt) or 0
		acc = acc + dt
		if acc >= 0.3 then acc = 0; markOpen() end
		if mode ~= "full" then return end
		slideAcc = slideAcc + dt
		if slideAcc >= 7 then slideAcc = 0; HUD.ShowSlide(slide + 1) end
		questAcc = questAcc + dt
		if questAcc >= 20 then questAcc = 0; fetchQuests(true) end
		eventAcc = eventAcc + dt
		if eventAcc >= 30 then eventAcc = 0; fetchEvent() end
	end)
	HUD.Layout()
end

function HUD.Layout()
	if not gui then return end
	local W, H = viewport()
	local want = wantMode(W, H)
	if want ~= mode or not root or not root.Parent then
		if root then root:Destroy() end
		refs = {}
		petSig, questSig = nil, nil
		mode = want
		root = new("Frame", {
			Name = "HUDRoot", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, gui)
		if mode == "full" then buildFull() else buildCompact() end
		local d = data()
		if d then HUD.Update(d) end
		HUD.ShowSlide(slide)
		HUD.RefreshSwitches()
		if mode == "full" then
			drawQuests(); drawEvent()
			fetchQuests(true); fetchEvent()
		end
	end
	if mode == "full" then placeFull(W, H) else placeCompact(W, H) end
	markOpen()
end

function HUD.Update(d)
	if not d or not refs.coins then return end
	-- A phone's pill is a third of a narrow screen: 1.2M reads there,
	-- 1,250,000 would be squeezed to nothing.
	local count = mode == "full" and commas or fmt
	refs.coins.Text = count(d.Coins or 0)
	refs.gems.Text = count(d.Gems or 0)
	refs.pets.Text = #(d.EquippedPets or {}) .. "/" .. slotsFor(d)
	if refs.petCount then refs.petCount.Text = #(d.EquippedPets or {}) .. "/" .. slotsFor(d) end
	drawProfile(d)
	-- The detail card first: it settles which pet is selected (the first one
	-- out, if none is), and the pet cards then mark that one.
	drawDetail(d)
	drawSlots(d)
	HUD.RefreshSwitches()
	fetchQuests(false)
end

-- The lowest point of the HUD across the top centre, for anything that drops
-- in from the top (toasts, the onboarding card) to sit below.
function HUD.ClearY()
	if mode == "full" then return math.floor(96 * s) end
	return narrow and 100 or 86
end

function HUD.Mode() return mode end

return HUD
