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

-- What each button opens. Hatching is not here on purpose: it happens at the
-- eggs in the world.
local NAV = {
	{ name = "Home",    icon = "🏠", label = "Home" },
	{ name = "Pets",    icon = "🐾", label = "Pets",    panel = "PetsPanel" },
	{ name = "Shop",    icon = "🛒", label = "Shop",    panel = "ShopPanel" },
	{ name = "Upgrade", icon = "⚡", label = "Upgrades", short = "Upgrade", panel = "UpgradePanel" },
	{ name = "Quests",  icon = "📜", label = "Quests",  panel = "QuestPanel" },
	{ name = "Index",   icon = "📖", label = "Pet Index", short = "Index", panel = "PetIndexPanel" },
	{ name = "Ranks",   icon = "🏆", label = "Ranks",   panel = "LeaderboardPanel" },
	{ name = "More",    icon = "☰",  label = "More" },
}
local CORNER_BUTTONS = {
	{ name = "Daily", icon = "📅", label = "Daily", panel = "DailyPanel" },
	{ name = "Trade", icon = "🤝", label = "Trade", panel = "TradePanel" },
	{ name = "Codes", icon = "🎁", label = "Codes", panel = "CodesPanel" },
}
local MORE = {
	{ name = "Merchant", icon = "🪙", label = "Merchant", panel = "MerchantPanel" },
	{ name = "Event",    icon = "🎉", label = "Event",    panel = "EventPanel" },
	{ name = "Boosts",   icon = "🚀", label = "Boosts",   panel = "BoostsPanel" },
	{ name = "Fusion",   icon = "🧬", label = "Fusion",   panel = "FusionPanel" },
	{ name = "Playtime", icon = "⏱️", label = "Playtime", panel = "PlaytimePanel" },
	{ name = "Spin",     icon = "🎡", label = "Spin",     panel = "SpinWheelPanel" },
}
-- The featured banner. Each slide is a real feature with a real panel behind
-- its button; the words say only what that feature actually does.
local FEATURED = {
	{ tag = "LIMITED", icon = "🪙", title = "Traveling Merchant",
	  sub = "Rare pets for coins. Stock changes every visit.", panel = "MerchantPanel" },
	{ tag = "EVERY 12H", icon = "🎡", title = "Lucky Spin",
	  sub = "A free spin every 12 hours. Jackpot: 250 gems.", panel = "SpinWheelPanel" },
	{ tag = "PLAY ON", icon = "⏱️", title = "Playtime Rewards",
	  sub = "The longer you play, the better the prizes.", panel = "PlaytimePanel" },
	{ tag = "BOOST", icon = "🚀", title = "Coin Boosts",
	  sub = "Up to 5x coins for ten minutes, for gems.", panel = "BoostsPanel" },
	{ tag = "NEW!", icon = "🧬", title = "Pet Fusion",
	  sub = "Fuse three of a kind into one stronger pet.", panel = "FusionPanel" },
}

-- ============================================================
-- STATE
-- ============================================================
local ctx = {}           -- from GameClient: fmt, getData, onMute, onAutoCollect, isMuted
local gui                -- MysticPetsHUD
local root               -- everything built here; replaced on a layout switch
local mode               -- "full" or "compact"
local s = 1              -- full layout's scale
local refs = {}
local selectedUid = nil
local slide = 1
local questsCache, eventCache = nil, nil
local petSig, questSig = nil, nil
local deleteArmed = nil

local PET = {}
for _, p in ipairs(GameConfig.Pets) do PET[p.name] = p end

local function fmt(n)
	if ctx.fmt then return ctx.fmt(n) end
	return tostring(math.floor(n or 0))
end

local function data()
	return ctx.getData and ctx.getData() or nil
end

local function controller()
	return require(script.Parent.UIController)
end

local function open(panel)
	if refs.more then refs.more.Visible = false end
	controller().TogglePanel(panel, data())
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
		Color = color or C.edge, Thickness = thickness or 2, Transparency = 0,
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
local function shrink(label, max)
	label.TextScaled = true
	new("UITextSizeConstraint", { MaxTextSize = max, MinTextSize = 8 }, label)
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
		math.floor(h * 0.48), C.text, HEAD), math.floor(h * 0.48))
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

local function moreMenu()
	local m = new("Frame", {
		Name = "MoreMenu", Size = UDim2.fromOffset(300, 238), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = C.card,
		BackgroundTransparency = 0.02, BorderSizePixel = 0, Visible = false, ZIndex = 5,
	}, root)
	round(m, 18); edge(m, C.violet, 2)
	new("UIScale", { Name = "Fit", Scale = 1 }, m)
	text(m, "Title", "More", 18, 8, 200, 36, 24, C.text, HEAD)
	local close = button(m, "MoreClose", 300 - 50, 4, 44, 44, C.raised)
	round(close, 10)
	close.Text = "✕"; close.Font = BODY; close.TextSize = 18; close.TextColor3 = C.soft
	close.MouseButton1Click:Connect(function() m.Visible = false end)
	for i, item in ipairs(MORE) do
		local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
		local b = button(m, "Dock_" .. item.name, 10 + col * 96, 52 + row * 90, 88, 82, C.raised)
		round(b, 14); edge(b, C.edge, 2)
		text(b, "Icon", item.icon, 0, 8, 88, 38, 30, nil, BODY, CENTER)
		text(b, "Label", item.label, 2, 50, 84, 24, 15, C.soft, BODY, CENTER)
		b.MouseButton1Click:Connect(function() open(item.panel) end)
	end
	refs.more = m
	return m
end

local function toggleMore()
	if not refs.more then return end
	local show = not refs.more.Visible
	if show then controller().CloseAll() end
	refs.more.Visible = show
end

-- What each switch shows. `state` is "on", "off", "get" or "go".
local function switchState(kind)
	local d = data() or {}
	if kind == "Mute" then
		local muted = ctx.isMuted and ctx.isMuted() or false
		return muted and "off" or "on"
	elseif kind == "AutoCollect" then
		if not d.GP_AutoCollect then return "get" end
		return d.AutoCollectOff and "off" or "on"
	end
	return "go"
end

local PILL_LOOK = {
	on  = { "ON",  C.green },
	off = { "OFF", C.grey },
	get = { "GET", C.gold },
	go  = { "EQUIP", C.blue },
}

local function pressSwitch(kind)
	if kind == "Mute" then
		if ctx.onMute then ctx.onMute() end
	elseif kind == "AutoCollect" then
		local st = switchState("AutoCollect")
		if st == "get" then
			open("ShopPanel")
		elseif ctx.onAutoCollect then
			ctx.onAutoCollect(st == "off")
		end
	elseif kind == "EquipBest" then
		local rf = remote("PetCmd")
		if rf then rf:FireServer("equipBest") end
	end
	HUD.RefreshSwitches()
end

local SWITCHES = {
	{ kind = "AutoCollect", name = "HUD_AutoCollect", icon = "🧲", label = "Auto Collect", short = "Collect" },
	{ kind = "EquipBest",   name = "HUD_EquipBest",   icon = "⭐", label = "Equip Best", short = "Best" },
	{ kind = "Mute",        name = "HUD_Mute",        icon = "🔊", label = "Sound", short = "Sound" },
}

-- ============================================================
-- FULL LAYOUT
-- ============================================================
local function buildNav(parent)
	local nav = card(parent, "Nav", 0, 134, 265, 430)
	refs.nav = {}
	for i, item in ipairs(NAV) do
		local b = button(nav, "Dock_" .. item.name, 8, 7 + (i - 1) * 52, 249, 49, C.blue, 1)
		round(b, 12)
		text(b, "Icon", item.icon, 10, 8, 34, 34, 24, nil, BODY, CENTER)
		text(b, "Label", item.label, 56, 0, 180, 49, 21, C.text, HEAD)
		b.MouseButton1Click:Connect(function()
			if item.name == "Home" then
				if refs.more then refs.more.Visible = false end
				controller().CloseAll()
			elseif item.name == "More" then
				toggleMore()
			else
				open(item.panel)
			end
		end)
		refs.nav[item.name] = b
	end
end

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
		122, 14, 222, 32, 26, C.text, HEAD), 26)
	local vip = new("TextLabel", {
		Name = "VIP", Text = "👑 VIP", Position = UDim2.fromOffset(266, 18), Size = UDim2.fromOffset(78, 24),
		BackgroundColor3 = Color3.fromRGB(72, 54, 12), BackgroundTransparency = 0.1, BorderSizePixel = 0,
		TextColor3 = C.gold, Font = HEAD, TextSize = 16, Visible = false,
	}, prof)
	round(vip, 8)
	refs.vip = vip
	refs.rank = shrink(text(prof, "Rank", "", 122, 50, 222, 24, 17, C.soft, BODY), 17)
	local bar = new("Frame", {
		Name = "RebirthBar", Position = UDim2.fromOffset(122, 84), Size = UDim2.fromOffset(222, 24),
		BackgroundColor3 = C.track, BorderSizePixel = 0,
	}, prof)
	round(bar, 12)
	refs.barFill = new("Frame", {
		Name = "Fill", Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = C.text, BorderSizePixel = 0,
	}, bar)
	round(refs.barFill, 12)
	gradient(refs.barFill, C.blue, C.cyan)
	refs.barText = text(bar, "Progress", "", 6, 0, 210, 24, 13, C.text, BODY, CENTER)
	refs.barText.TextStrokeTransparency = 0.55
end

local function buildEvent(parent)
	local ev = button(parent, "HUD_Event", 0, 576, 265, 105, C.text)
	round(ev, 18); edge(ev, C.violet, 2)
	gradient(ev, Color3.fromRGB(140, 70, 255), Color3.fromRGB(70, 28, 160), 20)
	text(ev, "Tag", "LIMITED EVENT", 16, 10, 230, 20, 13, C.gold, BODY)
	refs.eventName = shrink(text(ev, "EventName", "", 16, 32, 233, 32, 22, C.text, HEAD), 22)
	refs.eventInfo = shrink(text(ev, "EventInfo", "", 16, 68, 233, 24, 15, C.soft, BODY), 15)
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
	local st = edge(t, C.edge, 2)
	st.Name = "Edge"
	text(t, "Icon", sw.icon, 0, 10, 118, 44, 34, nil, BODY, CENTER)
	text(t, "Label", sw.label, 4, 56, 110, 24, 16, C.text, HEAD, CENTER)
	local p = new("TextLabel", {
		Name = "State", Position = UDim2.fromOffset(25, 86), Size = UDim2.fromOffset(68, 22),
		BackgroundColor3 = C.green, BorderSizePixel = 0, Text = "ON", TextColor3 = C.text,
		Font = BODY, TextSize = 13,
	}, t)
	round(p)
	t.MouseButton1Click:Connect(function() pressSwitch(sw.kind) end)
	return t
end

local function buildQuests(parent)
	local q = card(parent, "Quests", 0, 0, 357, 260)
	text(q, "Title", "📜 Active Quests", 16, 12, 230, 34, 22, C.text, HEAD)
	local all = button(q, "HUD_AllQuests", 262, 14, 80, 30, C.raised)
	round(all, 10)
	all.Text = "View all"; all.Font = BODY; all.TextSize = 13; all.TextColor3 = C.soft
	all.MouseButton1Click:Connect(function() open("QuestPanel") end)
	refs.questRows = {}
	for i = 1, 3 do
		local row = button(q, "HUD_Quest_" .. i, 10, 52 + (i - 1) * 66, 337, 60, C.raised, 1)
		round(row, 12)
		local ring = new("Frame", {
			Name = "Check", Position = UDim2.fromOffset(8, 17), Size = UDim2.fromOffset(26, 26),
			BackgroundColor3 = C.green, BackgroundTransparency = 1, BorderSizePixel = 0,
		}, row)
		round(ring)
		local ringEdge = edge(ring, C.dim, 2)
		local tick = text(ring, "Tick", "✓", 0, 0, 26, 26, 16, C.text, BODY, CENTER)
		local name = shrink(text(row, "QuestName", "", 44, 6, 200, 22, 16, C.text, BODY), 16)
		local amount = text(row, "Amount", "", 244, 6, 86, 22, 14, C.soft, BODY, RIGHT)
		local track = new("Frame", {
			Name = "Track", Position = UDim2.fromOffset(44, 36), Size = UDim2.fromOffset(286, 12),
			BackgroundColor3 = C.track, BorderSizePixel = 0,
		}, row)
		round(track)
		local fill = new("Frame", {
			Name = "Fill", Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = C.blue, BorderSizePixel = 0,
		}, track)
		round(fill)
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
	gradient(f, Color3.fromRGB(150, 70, 255), Color3.fromRGB(60, 26, 150), 25)
	local tag = new("TextLabel", {
		Name = "Tag", Position = UDim2.fromOffset(14, 12), Size = UDim2.fromOffset(92, 22),
		BackgroundColor3 = C.gold, BorderSizePixel = 0, Text = "", TextColor3 = Color3.fromRGB(60, 30, 0),
		Font = BODY, TextSize = 13,
	}, f)
	round(tag, 8)
	local icon = text(f, "Icon", "", 14, 46, 92, 92, 64, nil, BODY, CENTER)
	local title = shrink(text(f, "FeatureTitle", "", 116, 40, 228, 30, 22, C.text, HEAD), 22)
	local sub = text(f, "FeatureSub", "", 116, 70, 228, 40, 13, Color3.fromRGB(225, 215, 255), BODY)
	sub.TextWrapped = true; sub.TextYAlignment = Enum.TextYAlignment.Top
	local view = button(f, "HUD_FeatureView", 116, 116, 112, 34, Color3.fromRGB(255, 255, 255))
	round(view, 10)
	view.Text = "View"; view.Font = HEAD; view.TextSize = 18; view.TextColor3 = C.purple
	local prev = button(f, "HUD_FeaturePrev", 270, 118, 30, 30, Color3.fromRGB(40, 16, 100), 0.2)
	round(prev)
	prev.Text = "‹"; prev.Font = HEAD; prev.TextSize = 24; prev.TextColor3 = C.text
	local nxt = button(f, "HUD_FeatureNext", 310, 118, 30, 30, Color3.fromRGB(40, 16, 100), 0.2)
	round(nxt)
	nxt.Text = "›"; nxt.Font = HEAD; nxt.TextSize = 24; nxt.TextColor3 = C.text
	refs.feature = { tag = tag, icon = icon, title = title, sub = sub }
	view.MouseButton1Click:Connect(function()
		local item = FEATURED[slide]
		if item then open(item.panel) end
	end)
	prev.MouseButton1Click:Connect(function() HUD.ShowSlide(slide - 1) end)
	nxt.MouseButton1Click:Connect(function() HUD.ShowSlide(slide + 1) end)
end

local function buildDetail(parent)
	local d = card(parent, "Detail", 0, 471, 357, 382)
	local portrait = new("Frame", {
		Name = "Portrait", Position = UDim2.fromOffset(16, 16), Size = UDim2.fromOffset(120, 120),
		BackgroundColor3 = C.raised, BorderSizePixel = 0,
	}, d)
	round(portrait, 16)
	local pe = edge(portrait, C.edge, 2)
	local name = shrink(text(d, "DetailName", "", 148, 16, 150, 34, 24, C.text, HEAD), 24)
	local lock = button(d, "HUD_Lock", 305, 16, 36, 36, C.raised)
	round(lock, 10)
	lock.Text = "🔓"; lock.Font = BODY; lock.TextSize = 18
	local rarity = new("TextLabel", {
		Name = "Rarity", Position = UDim2.fromOffset(148, 58), Size = UDim2.fromOffset(104, 24),
		BackgroundColor3 = C.grey, BorderSizePixel = 0, Text = "", TextColor3 = C.text,
		Font = BODY, TextSize = 13,
	}, d)
	round(rarity)
	local extra = new("TextLabel", {
		Name = "Extra", Position = UDim2.fromOffset(258, 58), Size = UDim2.fromOffset(83, 24),
		BackgroundColor3 = C.violet, BorderSizePixel = 0, Text = "", TextColor3 = C.text,
		Font = BODY, TextSize = 13, Visible = false,
	}, d)
	round(extra)
	local status = text(d, "Status", "", 148, 92, 193, 22, 14, C.green, BODY)
	local stats = new("Frame", {
		Name = "Stats", Position = UDim2.fromOffset(16, 150), Size = UDim2.fromOffset(325, 138),
		BackgroundColor3 = C.raised, BorderSizePixel = 0,
	}, d)
	round(stats, 14)
	local rows = {}
	local STATS = { { "💰", "Coins" }, { "💎", "Gems" }, { "✨", "Bonus" } }
	for i, st in ipairs(STATS) do
		local y = 8 + (i - 1) * 42
		text(stats, "Icon" .. i, st[1], 12, y + 4, 30, 30, 20, nil, BODY, CENTER)
		text(stats, "Stat" .. i, st[2], 50, y, 130, 38, 17, C.soft, BODY)
		rows[i] = text(stats, "Value" .. i, "", 150, y, 163, 38, 18, C.text, HEAD, RIGHT)
	end
	local unequip = button(d, "HUD_Unequip", 16, 306, 132, 52, C.blue)
	round(unequip, 14)
	unequip.Text = "Unequip"; unequip.Font = HEAD; unequip.TextSize = 20; unequip.TextColor3 = C.text
	local fuse = button(d, "HUD_Fuse", 156, 306, 124, 52, C.purple)
	round(fuse, 14)
	fuse.Text = "🧬 Fuse"; fuse.Font = HEAD; fuse.TextSize = 20; fuse.TextColor3 = C.text
	local del = button(d, "HUD_Delete", 288, 306, 53, 52, C.red)
	round(del, 14)
	del.Text = "🗑"; del.Font = BODY; del.TextSize = 22; del.TextColor3 = C.text
	local empty = text(d, "Empty", "Equip a pet to see it here.\nHatch eggs out in the world!",
		16, 150, 325, 140, 17, C.soft, BODY, CENTER)
	empty.TextWrapped = true
	refs.detail = { box = d, portrait = portrait, portraitEdge = pe, name = name, lock = lock,
		rarity = rarity, extra = extra, status = status, stats = stats, rows = rows,
		unequip = unequip, fuse = fuse, del = del, empty = empty }

	unequip.MouseButton1Click:Connect(function()
		local rf = remote("UnequipPet")
		if rf and selectedUid then rf:FireServer(selectedUid) end
	end)
	fuse.MouseButton1Click:Connect(function() open("FusionPanel") end)
	lock.MouseButton1Click:Connect(function()
		local rf = remote("PetCmd")
		if rf and selectedUid then rf:FireServer("lock", selectedUid) end
	end)
	-- Two presses, like bulk delete: a pet is the one thing in this game
	-- that cannot be bought back.
	del.MouseButton1Click:Connect(function()
		if not selectedUid or del.Active == false then return end
		if deleteArmed ~= selectedUid then
			deleteArmed = selectedUid
			del.Text = "Sure?"; del.TextSize = 13
			local armedFor = selectedUid
			task.delay(3, function()
				if deleteArmed == armedFor then
					deleteArmed = nil
					if del.Parent then del.Text = "🗑"; del.TextSize = 22 end
				end
			end)
			return
		end
		deleteArmed = nil
		del.Text = "🗑"; del.TextSize = 22
		local rf = remote("DeletePet")
		if rf then rf:FireServer(selectedUid) end
	end)
end

local function buildFull()
	local pills = group("TopPills", 718, 58, Vector2.new(0.5, 0))
	local p1, coins, add1 = pill(pills, "Coins", "💰", 230, 58, "HUD_AddCoins", C.blue)
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
	buildQuests(right)
	buildFeatured(right)
	buildDetail(right)

	refs.groups = { pills = pills, corner = corner_, left = left, bottom = bottom, right = right }
	moreMenu()
end

-- ============================================================
-- COMPACT LAYOUT
-- ============================================================
local RAIL = 52
local RAIL_GAP = 6

local function railButton(name, icon, label)
	local b = button(root, name, 0, 0, RAIL, RAIL, C.card, 0.04)
	round(b, 14)
	local st = edge(b, C.edge, 2)
	st.Name = "Edge"
	text(b, "Icon", icon, 0, 3, RAIL, 30, 22, nil, BODY, CENTER)
	text(b, "Label", label, 1, 32, RAIL - 2, 16, 10, C.soft, BODY, CENTER)
	return b
end

local function buildCompact()
	local p1, coins = pill(root, "Coins", "💰", 120, 40)
	local p2, gems = pill(root, "Gems", "💎", 120, 40)
	local p3, pets = pill(root, "PetsPill", "🐾", 120, 40)
	refs.coins, refs.gems, refs.pets = coins, gems, pets
	refs.compactPills = { p1, p2, p3 }

	local chip = new("Frame", {
		Name = "RebirthChip", Size = UDim2.fromOffset(176, 26), AnchorPoint = Vector2.new(0.5, 0),
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
				if item.name == "More" then toggleMore() else open(item.panel) end
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
	refs.switches = {}
	for _, sw in ipairs(SWITCHES) do
		local b = railButton(sw.name, sw.icon, sw.short)
		b.MouseButton1Click:Connect(function() pressSwitch(sw.kind) end)
		table.insert(refs.rightRail, b)
		refs.switches[sw.kind] = b
	end
	moreMenu()
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
	g.left.Position = UDim2.fromOffset(15 * s, math.max(84 * s, barH + 6))
	g.bottom.Position = UDim2.fromOffset(296 * s, H - 59 * s)

	local rightTop = math.max(85 * s, cornerTop + 68 * s)
	local rs = s
	if rightTop + 853 * rs > H - 8 then rs = math.max(0.3, (H - 8 - rightTop) / 853) end
	setScale(g.right, rs)
	g.right.Position = UDim2.fromOffset(W - 16 * s, rightTop)

	if refs.more then
		setScale(refs.more, math.max(s, 0.75))
		refs.more.AnchorPoint = Vector2.new(0, 1)
		refs.more.Position = UDim2.fromOffset((15 + 265 + 12) * s,
			math.max(84 * s, barH + 6) + (134 + 7 + 8 * 52 - 14) * s)
	end
end

local function placeCompact(W, H)
	local minX = topbar(W)
	local gap = 6
	local left = math.max(minX, 100)
	local avail = W - left - 8
	local pw = math.min(170, math.floor((avail - 2 * gap) / 3))
	local x0 = left + math.floor((avail - (3 * pw + 2 * gap)) / 2)
	for i, p in ipairs(refs.compactPills) do
		p.Size = UDim2.fromOffset(pw, 40)
		p.Position = UDim2.fromOffset(x0 + (i - 1) * (pw + gap), 8)
	end
	refs.chip.Position = UDim2.fromOffset(W / 2, 54)

	-- The onboarding card hangs at the top centre while a new player learns
	-- the game. On a narrow screen it spans the width, so the rails start
	-- below it instead of underneath it.
	local railTop = 88
	if W < 470 + 2 * (RAIL + 16) then railTop = 176 end
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

	if refs.more then
		setScale(refs.more, math.min(1, (W - 16) / 300, (H - 16) / 238))
		refs.more.AnchorPoint = Vector2.new(0.5, 0.5)
		refs.more.Position = UDim2.fromScale(0.5, 0.5)
	end
end

-- ============================================================
-- FILLING IN (runs on every data update)
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

-- What one pet earns a second, the way PetService.GetPlayerIncome counts it.
local function income(pet, d)
	local pd = PET[pet.name]
	if not pd then return 0, 0, 1 end
	local mut = GameConfig.GetMutation and GameConfig.GetMutation(pet.mutation)
	local bonus = ((mut and mut.mult) or 1) * (tonumber(pet.fuseMult) or 1)
	local reb = d.RebirthMultiplier or 1
	local coins = pd.coinMult * bonus * reb * (d.GP_2xCoins and 2 or 1) * boostMult(d)
	local gems = (pd.gemMult or 0) * bonus * reb
		* (d.GP_VIP and GameConfig.Settings.VIPGemMultiplier or 1) * 0.01
	return coins, gems, bonus
end

local function blend(a, b, t)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

local function rarityColor(r)
	local info = GameConfig.Rarities[r or ""]
	return info and info.color or C.grey
end

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
		table.insert(parts, tostring(p.uniqueId) .. (p.locked and "L" or "") .. tostring(p.mutation))
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
				Name = "View", Position = UDim2.fromOffset(16, 4), Size = UDim2.fromOffset(70, 64),
				BackgroundTransparency = 1, BorderSizePixel = 0,
			}, cell)
			showPet(view, pet)
			shrink(text(cell, "PetName", nice(pet.name), 4, 68, 94, 22, 14, C.text, BODY, CENTER), 14)
			local r = new("TextLabel", {
				Name = "Rarity", Position = UDim2.fromOffset(6, 94), Size = UDim2.fromOffset(90, 20),
				BackgroundColor3 = rarityColor(pet.rarity), BorderSizePixel = 0,
				Text = tostring(pet.rarity or ""), TextColor3 = C.text, Font = BODY, TextSize = 13,
			}, cell)
			round(r)
			if pet.locked then text(cell, "Locked", "🔒", 76, 4, 22, 22, 14, nil, BODY, CENTER) end
			if pet.mutation then
				local m = GameConfig.GetMutation and GameConfig.GetMutation(pet.mutation)
				text(cell, "Mutation", m and m.emoji or "✨", 4, 4, 22, 22, 14, nil, BODY, CENTER)
			end
			local uid = pet.uniqueId
			cell.MouseButton1Click:Connect(function()
				selectedUid = uid
				deleteArmed = nil
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
	for _, k in ipairs({ "stats", "unequip", "fuse", "del", "lock", "rarity", "status" }) do
		v[k].Visible = has
	end
	v.empty.Visible = not has
	v.extra.Visible = false
	if not has then
		v.name.Text = "No pet selected"
		if v.shown ~= "none" then
			v.shown = "none"
			v.portrait:ClearAllChildren()
			round(v.portrait, 16)
			v.portraitEdge = edge(v.portrait, C.edge, 2)
			v.portrait.BackgroundColor3 = C.raised
		end
		return
	end
	if v.shown ~= pet.uniqueId .. tostring(pet.mutation) then
		v.shown = pet.uniqueId .. tostring(pet.mutation)
		v.portrait:ClearAllChildren()
		round(v.portrait, 16)
		v.portraitEdge = edge(v.portrait, rarityColor(pet.rarity), 3)
		showPet(v.portrait, pet)
	end
	v.portrait.BackgroundColor3 = blend(rarityColor(pet.rarity), C.raised, 0.65)
	v.name.Text = nice(pet.name)
	v.lock.Text = pet.locked and "🔒" or "🔓"
	v.rarity.Text = string.upper(tostring(pet.rarity or ""))
	v.rarity.BackgroundColor3 = rarityColor(pet.rarity)
	local mut = GameConfig.GetMutation and GameConfig.GetMutation(pet.mutation)
	local fm = tonumber(pet.fuseMult) or 1
	if mut then
		v.extra.Visible = true
		v.extra.Text = (mut.emoji or "") .. " " .. mut.name
		v.extra.BackgroundColor3 = mut.color or C.violet
	elseif fm > 1 then
		v.extra.Visible = true
		v.extra.Text = "🧬 Fused"
		v.extra.BackgroundColor3 = C.violet
	end
	local slot = 0
	for i, uid in ipairs(d.EquippedPets or {}) do if uid == pet.uniqueId then slot = i end end
	v.status.Text = "● Equipped · slot " .. slot
	local coins, gems, bonus = income(pet, d)
	v.rows[1].Text = fmt(coins) .. "/s"
	v.rows[2].Text = gems > 0 and (gems >= 10 and fmt(gems) or string.format("%.2f", gems)) .. "/s" or "—"
	v.rows[3].Text = "×" .. (bonus == math.floor(bonus) and tostring(bonus) or string.format("%.1f", bonus))
	v.del.Active = not pet.locked
	v.del.BackgroundTransparency = pet.locked and 0.6 or 0
	if deleteArmed ~= pet.uniqueId and v.del.Text ~= "🗑" then
		v.del.Text = "🗑"; v.del.TextSize = 22
	end
end

local function drawProgress(d)
	if not refs.barFill then return end
	local reb = d.Rebirths or 0
	local nextTier
	for _, t in ipairs(GameConfig.Rebirths) do
		if t.level == reb + 1 then nextTier = t end
	end
	local earned = d.TotalCoinsEarned or 0
	if nextTier then
		local f = math.clamp(earned / nextTier.requirement, 0, 1)
		refs.barFill.Size = UDim2.new(f, 0, 1, 0)
		refs.barFill.Visible = f > 0.001
		refs.barText.Text = (mode == "compact" and "♻️ " or "Rebirth  ")
			.. fmt(math.min(earned, nextTier.requirement)) .. " / " .. fmt(nextTier.requirement)
	else
		refs.barFill.Size = UDim2.new(1, 0, 1, 0)
		refs.barFill.Visible = true
		refs.barText.Text = "♻️ MAX REBIRTH"
	end
	if refs.rank then
		local title = "No rebirths yet"
		if reb > 0 then
			title = "Rebirth " .. reb
			for _, t in ipairs(GameConfig.Rebirths) do
				if t.level == reb then title = title .. " · " .. t.title end
			end
		end
		refs.rank.Text = "♻️ " .. title
		refs.vip.Visible = d.GP_VIP == true
		refs.playerName.Size = UDim2.fromOffset(d.GP_VIP and 138 or 222, 32)
	end
end

local function drawQuests()
	local rows = refs.questRows
	if not rows then return end
	local open_ = {}
	for _, q in ipairs(questsCache or {}) do
		if type(q) == "table" and not q.claimed then table.insert(open_, q) end
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
	sig = table.concat(sig, "|") .. "|" .. tostring(questsCache ~= nil)
	if sig == questSig then return end
	questSig = sig
	for i, r in ipairs(rows) do
		local q = open_[i]
		r.row.Visible = q ~= nil
		if q then
			local goal = math.max(1, tonumber(q.goal) or 1)
			local prog = math.min(goal, tonumber(q.progress) or 0)
			r.name.Text = tostring(q.name or q.desc or "Quest")
			r.fill.Size = UDim2.new(prog / goal, 0, 1, 0)
			r.fill.Visible = prog > 0
			if q.done then
				r.amount.Text = "Completed!"; r.amount.TextColor3 = C.green
				r.fill.BackgroundColor3 = C.green
				r.ring.BackgroundTransparency = 0; r.ringEdge.Color = C.green
				r.tick.Visible = true
			else
				r.amount.Text = fmt(prog) .. "/" .. fmt(goal); r.amount.TextColor3 = C.soft
				r.fill.BackgroundColor3 = C.blue
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
		refs.eventName.Text = tostring(e.name or "Event")
		refs.eventInfo.Text = tostring(e.tokenIcon or "🎟️") .. " " .. fmt(tonumber(e.tokens) or 0)
			.. " " .. tostring(e.tokenName or "tokens") .. "  ·  Tap to shop"
	end
end

function HUD.RefreshSwitches()
	for _, sw in ipairs(SWITCHES) do
		local b = refs.switches and refs.switches[sw.kind]
		if b and b.Parent then
			local st = switchState(sw.kind)
			local look = PILL_LOOK[st]
			local edge_ = b:FindFirstChild("Edge")
			local pillLabel = b:FindFirstChild("State")
			if pillLabel then
				pillLabel.Text = look[1]; pillLabel.BackgroundColor3 = look[2]
			end
			if edge_ then
				edge_.Color = st == "on" and C.green or C.edge
				edge_.Thickness = st == "on" and 3 or 2
			end
			if sw.kind == "Mute" then
				local icon = b:FindFirstChild("Icon")
				if icon then icon.Text = st == "off" and "🔇" or "🔊" end
			end
		end
	end
end

function HUD.ShowSlide(i)
	local n = #FEATURED
	slide = ((i - 1) % n + n) % n + 1
	local f, item = refs.feature, FEATURED[slide]
	if not f or not item then return end
	f.tag.Text = item.tag; f.icon.Text = item.icon
	f.title.Text = item.title; f.sub.Text = item.sub
end

-- ============================================================
-- KEEPING UP (cheap, on a timer; never every frame)
-- ============================================================
local lastQuests, lastEvent = -math.huge, -math.huge

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
	lastEvent = os.clock()
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
	refs.coins.Text = fmt(d.Coins or 0)
	refs.gems.Text = fmt(d.Gems or 0)
	refs.pets.Text = #(d.EquippedPets or {}) .. "/" .. slotsFor(d)
	if refs.petCount then refs.petCount.Text = #(d.EquippedPets or {}) .. "/" .. slotsFor(d) end
	drawProgress(d)
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
	return 86
end

function HUD.Mode() return mode end

return HUD
