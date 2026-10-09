-- MysticPets: GameClient.client.lua
local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")

local Player    = Players.LocalPlayer
local PlayerGui = Player.PlayerGui
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

-- ============================================================
-- LOADING SCREEN
-- ============================================================
local loadScreen = Instance.new("ScreenGui")
loadScreen.Name = "LoadScreen"; loadScreen.DisplayOrder = 999
loadScreen.IgnoreGuiInset = true; loadScreen.ResetOnSpawn = false
loadScreen.Parent = PlayerGui

local loadBg = Instance.new("Frame")
loadBg.Size = UDim2.new(1,0,1,0)
loadBg.BackgroundColor3 = Color3.fromRGB(10,8,20)
loadBg.BorderSizePixel = 0; loadBg.Parent = loadScreen

local loadGrad = Instance.new("UIGradient")
loadGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(30,10,60)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(5,5,20)),
})
loadGrad.Rotation = 135; loadGrad.Parent = loadBg

local loadTitle = Instance.new("TextLabel")
loadTitle.Size = UDim2.new(0,400,0,80)
loadTitle.Position = UDim2.new(0.5,-200,0.35,0)
loadTitle.BackgroundTransparency = 1
loadTitle.Text = "⭐ MYSTIC PETS"
loadTitle.TextColor3 = Color3.fromRGB(255,215,0)
loadTitle.Font = Enum.Font.GothamBold
loadTitle.TextScaled = true
loadTitle.TextStrokeTransparency = 0.3
loadTitle.TextStrokeColor3 = Color3.fromRGB(150,80,0)
loadTitle.Parent = loadBg

local loadSub = Instance.new("TextLabel")
loadSub.Size = UDim2.new(0,300,0,30)
loadSub.Position = UDim2.new(0.5,-150,0.5,10)
loadSub.BackgroundTransparency = 1
loadSub.Text = "Loading..."
loadSub.TextColor3 = Color3.fromRGB(180,180,220)
loadSub.Font = Enum.Font.Gotham
loadSub.TextScaled = true; loadSub.Parent = loadBg

-- Animated dots on loading bar
local barBg = Instance.new("Frame")
barBg.Size = UDim2.new(0,300,0,8)
barBg.Position = UDim2.new(0.5,-150,0.5,50)
barBg.BackgroundColor3 = Color3.fromRGB(40,35,60)
barBg.BorderSizePixel = 0; barBg.Parent = loadBg
Instance.new("UICorner",barBg).CornerRadius = UDim.new(1,0)

local barFill = Instance.new("Frame")
barFill.Size = UDim2.new(0,0,1,0)
barFill.BackgroundColor3 = Color3.fromRGB(140,80,255)
barFill.BorderSizePixel = 0; barFill.Parent = barBg
Instance.new("UICorner",barFill).CornerRadius = UDim.new(1,0)

TweenService:Create(barFill, TweenInfo.new(2, Enum.EasingStyle.Quad), {
	Size = UDim2.new(1,0,1,0)
}):Play()

-- ============================================================
-- WAIT FOR REMOTES
-- ============================================================
local Remotes = ReplicatedStorage:WaitForChild("Remotes",30)
local RE_DataUpdated  = Remotes:WaitForChild("DataUpdated")
local RE_HatchResult  = Remotes:WaitForChild("HatchResult")
local RE_Notification = Remotes:WaitForChild("Notification")
-- With a timeout. A bare WaitForChild on a remote the server does not have
-- yields forever, and this is the script that builds the whole HUD.
local RE_SetMuted     = Remotes:WaitForChild("SetMuted", 10)
local RE_HatchEgg     = Remotes:WaitForChild("HatchEgg")
local RE_EquipPet     = Remotes:WaitForChild("EquipPet")
local RE_UnequipPet   = Remotes:WaitForChild("UnequipPet")
local RE_BuyArea      = Remotes:WaitForChild("BuyArea")
local RE_Rebirth        = Remotes:WaitForChild("Rebirth")
local RE_RebirthConfirm = Remotes:WaitForChild("RebirthConfirm")
local RE_DeletePet      = Remotes:WaitForChild("DeletePet")
local RE_BuyGamepass    = Remotes:WaitForChild("BuyGamepass")
local RE_BuyUpgrade     = Remotes:WaitForChild("BuyUpgrade")
local RE_SecretFound    = Remotes:WaitForChild("SecretFound")
local RE_TitleUpdate    = Remotes:WaitForChild("TitleUpdate")
local RF_GetData        = Remotes:WaitForChild("GetData")
local RF_Admin          = Remotes:WaitForChild("AdminCmd")
local RE_PetCmd         = Remotes:WaitForChild("PetCmd")
local RE_OfflineEarnings = Remotes:WaitForChild("OfflineEarnings")

-- Area barriers: block locked areas for THIS player only (client-side collision)
-- Resolved on demand, and from inside StarPetsMap.
--
-- The barriers moved into the map folder so that selecting StarPetsMap in the
-- Explorer and copying it takes the buy-gates with it. This line still waited
-- for workspace.AreaBarriers, which no longer exists — it would have timed out
-- and returned nil, and then every locked world would have stayed sealed
-- forever because nothing ever updated a barrier again. My own change, caught
-- reading the file back.
--
-- On demand rather than captured once: a reference grabbed before the map
-- existed, or held across a rebuild, points at a folder no longer in the world.
local barrierCache = nil
local function areaBarriers()
	if barrierCache and barrierCache.Parent then return barrierCache end
	local root = workspace:FindFirstChild("StarPetsMap")
	barrierCache = (root and root:FindFirstChild("AreaBarriers"))
		or workspace:FindFirstChild("AreaBarriers")
	return barrierCache
end

local function updateBarriers(data)
	local AreaBarriers = areaBarriers()
	if not AreaBarriers or not data then return end
	local unlocked = {}
	for _, id in ipairs(data.UnlockedAreas or {}) do unlocked[id] = true end
	for _, bar in ipairs(AreaBarriers:GetChildren()) do
		if string.sub(bar.Name, 1, 8) == "Barrier_" then
			local id = string.gsub(bar.Name, "^Barrier_", "")
			local locked = not unlocked[id]
			bar.CanCollide = locked
			bar.Transparency = locked and 0 or 1
			-- hide the stripe + name/price sign too once unlocked
			for _, d in ipairs(bar:GetDescendants()) do
				if d:IsA("BasePart") then d.Transparency = locked and 0 or 1
				elseif d:IsA("BillboardGui") then d.Enabled = locked end
			end
		end
	end
end

-- Slowly spin the coins (client-side, visual only — no lag, no replication)
task.spawn(function()
	local Orbs = workspace:WaitForChild("Orbs", 30)
	if not Orbs then return end
	game:GetService("RunService").RenderStepped:Connect(function(dt)
		local spin = CFrame.Angles(0, dt * 1.1, 0)
		for _, orb in ipairs(Orbs:GetChildren()) do
			if orb.Name == "CoinOrb" then orb.CFrame = orb.CFrame * spin end
		end
	end)
end)

local CurrentData = nil

-- ============================================================
-- UTILS
-- ============================================================
local function fmt(n)
	if n>=1e12 then return string.format("%.1fT",n/1e12)
	elseif n>=1e9 then return string.format("%.1fB",n/1e9)
	elseif n>=1e6 then return string.format("%.1fM",n/1e6)
	elseif n>=1e3 then return string.format("%.1fK",n/1e3)
	else return tostring(math.floor(n)) end
end

-- ============================================================
-- FLOATING COIN TEXT
-- ============================================================
local function floatText(text, color)
	local char = Player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local sg = Instance.new("ScreenGui")
	sg.Name="FloatText"; sg.ResetOnSpawn=false; sg.DisplayOrder=80; sg.Parent=PlayerGui

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0,120,0,36)
	lbl.Position = UDim2.new(0.5,-60,0.4,0)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = color or Color3.fromRGB(255,215,0)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.TextStrokeTransparency = 0.3
	lbl.TextStrokeColor3 = Color3.new(0,0,0)
	lbl.Parent = sg

	local t1 = TweenService:Create(lbl, TweenInfo.new(1.2,Enum.EasingStyle.Quad), {
		Position = UDim2.new(0.5,-60,0.28,0),
		TextTransparency = 1,
	})
	t1:Play()
	t1.Completed:Connect(function() sg:Destroy() end)
end

-- ============================================================
-- TOAST NOTIFICATIONS
-- ============================================================
local ToastGui
local function showToast(notifType, message)
	if ToastGui then ToastGui:Destroy() end
	local screen = Instance.new("ScreenGui")
	screen.Name="ToastGui"; screen.ResetOnSpawn=false
	screen.DisplayOrder=100; screen.IgnoreGuiInset=true
	screen.Parent=PlayerGui; ToastGui=screen

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0,340,0,60)
	frame.Position = UDim2.new(0.5,-170,0,-70)
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = notifType=="error" and Color3.fromRGB(180,40,40)
		or notifType=="success" and Color3.fromRGB(40,160,70)
		or Color3.fromRGB(40,80,180)
	frame.Parent = screen
	Instance.new("UICorner",frame).CornerRadius = UDim.new(0,12)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1,1,1); stroke.Transparency = 0.7; stroke.Parent = frame

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1,-20,1,0); lbl.Position = UDim2.new(0,10,0,0)
	lbl.BackgroundTransparency = 1; lbl.Text = message
	lbl.TextColor3 = Color3.new(1,1,1); lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBold; lbl.TextWrapped = true; lbl.Parent = frame

	TweenService:Create(frame,TweenInfo.new(0.35,Enum.EasingStyle.Back),{
		Position=UDim2.new(0.5,-170,0,18)
	}):Play()
	task.delay(3,function()
		if frame and frame.Parent then
			TweenService:Create(frame,TweenInfo.new(0.25),{
				Position=UDim2.new(0.5,-170,0,-70)
			}):Play()
			task.delay(0.3,function() if screen then screen:Destroy() end end)
		end
	end)
end

-- ============================================================
-- HUD BUILD
-- ============================================================
local HUD
local CoinLabel, GemLabel, RebirthLabel, PetCountLabel
local prevCoins = 0

-- Sound. Required through pcall so a broken sound module can never take the
-- HUD down with it — a silent game is a worse game, a game with no buttons is
-- no game at all.
local Sfx = nil
pcall(function() Sfx = require(script.Parent.UI.Sfx) end)
local function sfx(name, jitter) if Sfx then Sfx.Play(name, jitter) end end

-- What the last data update looked like, so each change can be heard once.
local prevGems, prevAreas, prevRebirths, prevEquipped = nil, nil, nil, nil
-- Coins can arrive several times a second while a player runs through orbs.
-- One ping per pickup at that rate is a buzz, not a sound.
local lastCoinPing = 0

-- The HUD's movable pieces, kept so layoutHUD can rearrange them when the
-- screen changes size.
local statChips = {}
local dockButtons = {}
local moreBtn = nil
local dockExpanded = false
local muteBtn = nil

local function buildHUD()
	HUD = Instance.new("ScreenGui")
	HUD.Name="MysticPetsHUD"; HUD.ResetOnSpawn=false
	HUD.DisplayOrder=10; HUD.IgnoreGuiInset=true; HUD.Parent=PlayerGui

	-- TOP BAR
	local topBar = Instance.new("Frame")
	topBar.Size = UDim2.new(1,0,0,58)
	topBar.BackgroundColor3 = Color3.fromRGB(12,10,22)
	topBar.BackgroundTransparency = 0.1; topBar.BorderSizePixel=0
	topBar.Parent = HUD
	local tg = Instance.new("UIGradient"); tg.Parent=topBar
	tg.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(35,18,70)),ColorSequenceKeypoint.new(1,Color3.fromRGB(10,8,25))})
	tg.Rotation=90

	local function statChip(pos, icon, defaultText, textColor, bgColor)
		local chip = Instance.new("Frame")
		chip.Size=UDim2.new(0,155,0,42); chip.Position=pos
		chip.BackgroundColor3=bgColor; chip.BackgroundTransparency=0.25
		chip.BorderSizePixel=0; chip.Parent=topBar
		Instance.new("UICorner",chip).CornerRadius=UDim.new(0,10)
		local stroke = Instance.new("UIStroke"); stroke.Color=textColor
		stroke.Transparency=0.7; stroke.Parent=chip

		local iconLbl = Instance.new("TextLabel")
		iconLbl.Size=UDim2.new(0,34,1,0); iconLbl.BackgroundTransparency=1
		iconLbl.Text=icon; iconLbl.TextScaled=true; iconLbl.Font=Enum.Font.Gotham
		iconLbl.Parent=chip

		local valLbl = Instance.new("TextLabel")
		valLbl.Size=UDim2.new(1,-38,1,0); valLbl.Position=UDim2.new(0,36,0,0)
		valLbl.BackgroundTransparency=1; valLbl.Text=defaultText
		valLbl.TextColor3=textColor; valLbl.TextScaled=true
		valLbl.Font=Enum.Font.GothamBold; valLbl.TextXAlignment=Enum.TextXAlignment.Left
		valLbl.Parent=chip
		table.insert(statChips, chip)
		return valLbl
	end

	-- Right-aligned so they clear the Roblox menu/chat/voice icons (top-left).
	-- These are the DESKTOP positions; layoutHUD moves them on a narrow screen.
	CoinLabel   = statChip(UDim2.new(1,-493,0,8), "💰","0",   Color3.fromRGB(255,215,0),  Color3.fromRGB(50,35,10))
	GemLabel    = statChip(UDim2.new(1,-328,0,8), "💎","0",   Color3.fromRGB(0,200,255),  Color3.fromRGB(0,20,40))
	PetCountLabel = statChip(UDim2.new(1,-163,0,8),"🐾","0/0", Color3.fromRGB(200,150,255),Color3.fromRGB(30,15,50))

	-- Center rebirth badge (top bar, stays)
	RebirthLabel = Instance.new("TextLabel")
	RebirthLabel.Size=UDim2.new(0,160,0,38); RebirthLabel.Position=UDim2.new(0.5,-80,0,10)
	RebirthLabel.BackgroundColor3=Color3.fromRGB(80,0,130); RebirthLabel.BackgroundTransparency=0.25
	RebirthLabel.Text="⭐ No Rebirth"; RebirthLabel.TextColor3=Color3.fromRGB(220,180,255)
	RebirthLabel.TextScaled=true; RebirthLabel.Font=Enum.Font.GothamBold
	RebirthLabel.BorderSizePixel=0; RebirthLabel.Parent=topBar
	Instance.new("UICorner",RebirthLabel).CornerRadius=UDim.new(0,10)
	Instance.new("UIStroke",RebirthLabel).Color=Color3.fromRGB(150,80,255)

	-- RIGHT SIDE NAV (vertical stack, no Rebirth — that's in the world)
	local navButtons = {
		{ name="Pets",    emoji="🐾", panel="PetsPanel",        color=Color3.fromRGB(140,80,255) },
		{ name="Index",   emoji="📖", panel="PetIndexPanel",    color=Color3.fromRGB(150,120,255) },
		{ name="Quests",  emoji="📜", panel="QuestPanel",       color=Color3.fromRGB(90,160,255) },
		-- Hatch removed from HUD on purpose: hatching is via the physical eggs in the world
		{ name="Ranks",   emoji="🏆", panel="LeaderboardPanel", color=Color3.fromRGB(255,215,0)  },
		{ name="Upgrade", emoji="⚡", panel="UpgradePanel",     color=Color3.fromRGB(255,200,0)  },
		{ name="Shop",    emoji="🛒", panel="ShopPanel",        color=Color3.fromRGB(255,140,0)  },
		{ name="Merchant",emoji="🪙", panel="MerchantPanel",   color=Color3.fromRGB(255,180,90) },
		{ name="Event",   emoji="🎉", panel="EventPanel",      color=Color3.fromRGB(255,120,200) },
		{ name="Trade",   emoji="🤝", panel="TradePanel",      color=Color3.fromRGB(90,200,120) },
		{ name="Codes",   emoji="🎁", panel="CodesPanel",      color=Color3.fromRGB(90,200,150) },
		{ name="Daily",   emoji="📅", panel="DailyPanel",      color=Color3.fromRGB(255,200,80) },
		{ name="Boosts",  emoji="⚡", panel="BoostsPanel",     color=Color3.fromRGB(255,170,60) },
		{ name="Fusion",  emoji="🧬", panel="FusionPanel",     color=Color3.fromRGB(150,90,240) },
		{ name="Playtime",emoji="⏱️", panel="PlaytimePanel",   color=Color3.fromRGB(90,200,255) },
		{ name="Spin",    emoji="🎡", panel="SpinWheelPanel",   color=Color3.fromRGB(255,120,200) },
	}
	-- Button DOCK along the bottom. Buttons are made once here and PLACED by
	-- layoutHUD, which runs again whenever the screen changes size.
	--
	-- The old dock was eight across at 50px: 442 points wide. A portrait phone
	-- is about 390, so the outer buttons hung off both edges and the rest sat
	-- on top of Roblox's own thumbstick and jump button.
	local PRIMARY = { Pets=true, Index=true, Quests=true, Upgrade=true, Shop=true }

	local function dockButton(label, color)
		local b = Instance.new("TextButton")
		b.BackgroundColor3 = Color3.fromRGB(18,14,35)
		b.BackgroundTransparency = 0.15
		b.Text     = label
		b.TextColor3 = Color3.new(1,1,1)
		b.TextScaled = true
		b.Font     = Enum.Font.GothamBold
		b.BorderSizePixel = 0
		b.Parent   = HUD
		Instance.new("UICorner",b).CornerRadius = UDim.new(0,14)
		local stroke = Instance.new("UIStroke",b)
		stroke.Color = color; stroke.Thickness = 2; stroke.Transparency = 0.4
		b.MouseEnter:Connect(function()
			TweenService:Create(b,TweenInfo.new(0.15),{BackgroundTransparency=0}):Play()
			TweenService:Create(stroke,TweenInfo.new(0.15),{Transparency=0}):Play()
		end)
		b.MouseLeave:Connect(function()
			TweenService:Create(b,TweenInfo.new(0.15),{BackgroundTransparency=0.15}):Play()
			TweenService:Create(stroke,TweenInfo.new(0.15),{Transparency=0.4}):Play()
		end)
		return b
	end

	for _, btn in ipairs(navButtons) do
		local b = dockButton(btn.emoji.."\n"..btn.name, btn.color)
		b.Name = "Dock_"..btn.name
		b.MouseButton1Click:Connect(function()
			local UIController = require(script.Parent.UI.UIController)
			UIController.TogglePanel(btn.panel, CurrentData)
		end)
		table.insert(dockButtons, { b = b, primary = PRIMARY[btn.name] == true })
	end

	-- "More": only shown on a narrow screen, where it opens the rest of the dock.
	moreBtn = dockButton("⋯\nMore", Color3.fromRGB(200,200,220))
	moreBtn.Name = "Dock_More"
	moreBtn.Visible = false

	-- Sound on/off. Not a dock button: it opens no panel, and it is reached
	-- for in a hurry.
	muteBtn = Instance.new("TextButton")
	muteBtn.Name = "HUD_Mute"
	muteBtn.BackgroundColor3 = Color3.fromRGB(18,14,35)
	muteBtn.BackgroundTransparency = 0.15
	muteBtn.Text = "🔊"
	muteBtn.TextScaled = true
	muteBtn.Font = Enum.Font.GothamBold
	muteBtn.TextColor3 = Color3.new(1,1,1)
	muteBtn.BorderSizePixel = 0
	muteBtn.Parent = HUD
	Instance.new("UICorner", muteBtn).CornerRadius = UDim.new(0,10)
end

-- Lay the HUD out for the screen it is on.
--
-- A desktop keeps exactly the layout it always had. Below COMPACT points wide:
--   * the three counters share the width to the right of Roblox's own menu
--     button, instead of sitting at fixed offsets from the right edge — which
--     on a phone put the COIN counter 103 points off the left of the screen
--   * the rebirth badge drops below the bar instead of being drawn on top of
--     the gem and pet counters
--   * the dock shows its five most used buttons plus "More", sized to the
--     44-point touch target, and wraps to fit rather than hanging off the edge
local COMPACT = 700
local DESKTOP_CHIPS = { -493, -328, -163 }

local function viewportWidth()
	local cam = workspace.CurrentCamera
	local w = cam and cam.ViewportSize and cam.ViewportSize.X
	if type(w) ~= "number" or w <= 0 then return 1280 end
	return w
end

local function layoutHUD()
	if not HUD then return end
	local W = viewportWidth()
	local compact = W < COMPACT

	-- ---- top bar ----
	if compact then
		-- Clear of Roblox's own menu AND chat icons, which sit at the
		-- top-left of a phone. 64 cleared the menu and sat under chat.
		local left = 100
		local gap = 6
		local cw = math.max(70, math.floor((W - left - 8 - gap * 2) / 3))
		for i, chip in ipairs(statChips) do
			chip.Size = UDim2.new(0, cw, 0, 40)
			chip.Position = UDim2.new(0, left + (i - 1) * (cw + gap), 0, 9)
		end
		if RebirthLabel then
			RebirthLabel.Size = UDim2.new(0, 150, 0, 26)
			RebirthLabel.Position = UDim2.new(0.5, -75, 0, 62)
		end
	else
		for i, chip in ipairs(statChips) do
			chip.Size = UDim2.new(0, 155, 0, 42)
			chip.Position = UDim2.new(1, DESKTOP_CHIPS[i] or -163, 0, 8)
		end
		if RebirthLabel then
			RebirthLabel.Size = UDim2.new(0, 160, 0, 38)
			RebirthLabel.Position = UDim2.new(0.5, -80, 0, 10)
		end
	end

	if muteBtn then
		if compact then
			-- Below the bar at the right, opposite the rebirth badge.
			muteBtn.Size = UDim2.new(0, 44, 0, 30)
			muteBtn.Position = UDim2.new(1, -52, 0, 60)
		else
			-- In the bar, just right of Roblox's icons, nowhere near the counters.
			muteBtn.Size = UDim2.new(0, 42, 0, 40)
			muteBtn.Position = UDim2.new(0, 104, 0, 9)
		end
	end

	-- ---- dock ----
	local size = compact and 44 or 50
	local gap = compact and 5 or 6
	local visible = {}
	for _, d in ipairs(dockButtons) do
		local show = (not compact) or dockExpanded or d.primary
		d.b.Visible = show
		if show then table.insert(visible, d.b) end
	end
	if moreBtn then
		moreBtn.Visible = compact
		moreBtn.Text = dockExpanded and "✕\nLess" or "⋯\nMore"
		if compact then table.insert(visible, moreBtn) end
	end

	local perRow = compact
		and math.max(1, math.floor((W - 24 + gap) / (size + gap)))
		or 8
	perRow = math.min(perRow, 8)
	local n = #visible
	local numRows = math.ceil(n / perRow)
	local bottomMargin = 16
	for i, b in ipairs(visible) do
		local row      = math.floor((i-1) / perRow)
		local idxInRow = (i-1) % perRow
		local rowCount = math.min(perRow, n - row*perRow)
		local rowW     = rowCount*size + (rowCount-1)*gap
		local xoff     = -rowW/2 + idxInRow*(size+gap)
		local rowsFromBottom = (numRows-1) - row
		local yoff     = -bottomMargin - size - rowsFromBottom*(size+gap)
		b.Size     = UDim2.new(0, size, 0, size)
		b.Position = UDim2.new(0.5, xoff, 1, yoff)
	end
end

-- ============================================================
-- DATA UPDATE
-- ============================================================
local lastInvSig = ""
local function onDataUpdated(data)
	-- The saved mute preference, applied BEFORE any sound for this update
	-- could play, so a muted player is not greeted by a coin ping on join.
	if Sfx and data.Muted ~= nil and Sfx.IsMuted() ~= (data.Muted == true) then
		Sfx.SetMuted(data.Muted == true)
		if muteBtn then muteBtn.Text = data.Muted and "🔇" or "🔊" end
	end

	local newCoins = data.Coins or 0
	if CurrentData and newCoins > prevCoins then
		local diff = newCoins - prevCoins
		if diff > 0 and diff < 100000 then
			floatText("+"..fmt(diff).." 💰", Color3.fromRGB(255,215,0))
		end
	end
	-- Each of these fires only on a CHANGE between two updates, never on the
	-- first one. The first update is the save loading in, and a player joining
	-- to a burst of unlock, rebirth and coin sounds for things they did last
	-- week is noise, not feedback.
	if CurrentData then
		if newCoins > prevCoins and (os.clock() - lastCoinPing) > 0.12 then
			lastCoinPing = os.clock()
			sfx("coin", 0.08)
		end
		local gems = data.Gems or 0
		if prevGems and gems > prevGems then sfx("gem", 0.05) end
		local areas = #(data.UnlockedAreas or {})
		if prevAreas and areas > prevAreas then sfx("unlock") end
		local reb = data.Rebirths or 0
		if prevRebirths and reb > prevRebirths then sfx("rebirth") end
		local eq = #(data.EquippedPets or {})
		if prevEquipped and eq ~= prevEquipped then
			sfx(eq > prevEquipped and "equip" or "unequip")
		end
	end
	prevGems = data.Gems or 0
	prevAreas = #(data.UnlockedAreas or {})
	prevRebirths = data.Rebirths or 0
	prevEquipped = #(data.EquippedPets or {})

	prevCoins = newCoins
	CurrentData = data
	updateBarriers(data)
	if not CoinLabel then return end
	CoinLabel.Text    = fmt(data.Coins or 0)
	GemLabel.Text     = fmt(data.Gems or 0)
	local maxSlots = (data.GP_PetSlots and GameConfig.Settings.VIPPetSlots or GameConfig.Settings.DefaultPetSlots)
	PetCountLabel.Text = #(data.EquippedPets or {}).."/"..maxSlots
	local r = data.Rebirths or 0
	RebirthLabel.Text = r>0 and ("♻️ "..r.."x Rebirth") or "⭐ No Rebirth"
	-- Only refresh an OPEN panel when the inventory actually changed — rebuilding
	-- it every coin tick is what made the Pets tab flicker/pop.
	local sig = #(data.Pets or {}) .. "|" .. table.concat(data.EquippedPets or {}, ",")
		.. "|" .. tostring(data.Rebirths or 0) .. "|" .. #(data.UnlockedAreas or {})
	if sig ~= lastInvSig then
		lastInvSig = sig
		require(script.Parent.UI.UIController).RefreshCurrent(data)
	end
end

RE_DataUpdated.OnClientEvent:Connect(onDataUpdated)

-- Rarest first, so a ten-hatch reveal is announced by the best thing in it.
local RARITY_RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6 }

RE_HatchResult.OnClientEvent:Connect(function(pets,eggId)
	-- The moment the whole game is built around. It was silent.
	sfx("hatch")
	local best = "Common"
	for _, p in ipairs(type(pets) == "table" and pets or {}) do
		local r = type(p) == "table" and p.rarity or nil
		if r and (RARITY_RANK[r] or 0) > (RARITY_RANK[best] or 0) then best = r end
	end
	task.delay(0.35, function() if Sfx then Sfx.Reveal(best) end end)

	local HatchUI = require(script.Parent.UI.HatchPanel)
	HatchUI.ShowHatchResult(pets,eggId)
end)

RE_Notification.OnClientEvent:Connect(function(t,msg)
	-- Every toast the game already shows now has a sound, chosen from the
	-- toast's own type, without changing any of the forty places that send one.
	if Sfx then Sfx.Toast(t) end
	showToast(t,msg)
end)

RE_HatchEgg.OnClientEvent:Connect(function(eggId)
	if eggId and eggId:sub(1,11) == "__upgrade__" then
		-- Shop pad clicked — open upgrade panel
		local UIController = require(script.Parent.UI.UIController)
		UIController.TogglePanel("UpgradePanel", CurrentData)
		return
	end
	-- Through UIController, like every other panel, and opened ON the egg that
	-- was clicked. This called HatchUI.Build directly: it skipped the pass that
	-- fits panels to a phone (a 600-wide panel on a 390-wide screen), could
	-- stack on top of another open panel, and threw away which egg was clicked,
	-- so clicking the Volcano egg opened the same list as clicking any other.
	local UIController = require(script.Parent.UI.UIController)
	UIController.Open("HatchPanel", CurrentData, eggId)
end)

-- Machine fires this → show rebirth confirmation popup
RE_Rebirth.OnClientEvent:Connect(function()
	if not CurrentData then return end

	-- Remove existing popup
	local existing = PlayerGui:FindFirstChild("RebirthConfirmGui")
	if existing then existing:Destroy() end

	local data = CurrentData
	local nextTier = nil
	for _, tier in ipairs(GameConfig.Rebirths) do
		if tier.level == (data.Rebirths or 0) + 1 then nextTier = tier break end
	end

	local screen = Instance.new("ScreenGui")
	screen.Name="RebirthConfirmGui"; screen.ResetOnSpawn=false
	screen.DisplayOrder=80; screen.IgnoreGuiInset=true; screen.Parent=PlayerGui

	local panel = Instance.new("Frame")
	panel.Size=UDim2.new(0,420,0,300)
	panel.Position=UDim2.new(0.5,-210,0.5,400)
	panel.BackgroundColor3=Color3.fromRGB(15,10,30)
	panel.BorderSizePixel=0; panel.Parent=screen
	Instance.new("UICorner",panel).CornerRadius=UDim.new(0,16)
	local stroke=Instance.new("UIStroke",panel)
	stroke.Color=Color3.fromRGB(180,0,255); stroke.Thickness=2.5

	TweenService:Create(panel,TweenInfo.new(0.35,Enum.EasingStyle.Back),{
		Position=UDim2.new(0.5,-210,0.5,-150)
	}):Play()

	-- Title
	local title=Instance.new("TextLabel")
	title.Size=UDim2.new(1,0,0,50); title.BackgroundTransparency=1
	title.Text="♻️  REBIRTH MACHINE"; title.TextColor3=Color3.fromRGB(200,100,255)
	title.TextScaled=true; title.Font=Enum.Font.GothamBold; title.Parent=panel

	-- Info
	local infoText
	if nextTier then
		local canRebirth = (data.TotalCoinsEarned or 0) >= nextTier.requirement
		local progress = math.min(100, math.floor(((data.TotalCoinsEarned or 0)/nextTier.requirement)*100))
		infoText = canRebirth
			and ("✅ Ready to rebirth!\nNext: "..nextTier.title.." ("..nextTier.multiplier.."x earnings)\n\n⚠️ Resets coins, pets & areas\nYou keep: Gems + Gamepasses")
			or ("Progress: "..progress.."%\nNeed "..fmt(nextTier.requirement).." total coins\nYou have "..fmt(data.TotalCoinsEarned or 0).."\n\nKeep grinding!")
	else
		infoText = "👑 You've reached max Rebirth!\n25x earnings forever."
	end

	local info=Instance.new("TextLabel")
	info.Size=UDim2.new(1,-30,0,120); info.Position=UDim2.new(0,15,0,55)
	info.BackgroundTransparency=1; info.Text=infoText
	info.TextColor3=Color3.fromRGB(200,200,220); info.TextScaled=true
	info.Font=Enum.Font.Gotham; info.TextWrapped=true
	info.TextYAlignment=Enum.TextYAlignment.Top; info.Parent=panel

	-- Buttons
	local canDo = nextTier and (data.TotalCoinsEarned or 0) >= nextTier.requirement
	local confirmBtn=Instance.new("TextButton")
	confirmBtn.Size=UDim2.new(0,180,0,50); confirmBtn.Position=UDim2.new(0,20,1,-70)
	confirmBtn.BackgroundColor3=canDo and Color3.fromRGB(150,0,255) or Color3.fromRGB(60,60,80)
	confirmBtn.Text=canDo and "♻️  REBIRTH!" or "Not Ready"
	confirmBtn.TextColor3=Color3.new(1,1,1); confirmBtn.TextScaled=true
	confirmBtn.Font=Enum.Font.GothamBold; confirmBtn.BorderSizePixel=0
	confirmBtn.Active=canDo; confirmBtn.Parent=panel
	Instance.new("UICorner",confirmBtn).CornerRadius=UDim.new(0,10)

	local cancelBtn=Instance.new("TextButton")
	cancelBtn.Size=UDim2.new(0,180,0,50); cancelBtn.Position=UDim2.new(1,-200,1,-70)
	cancelBtn.BackgroundColor3=Color3.fromRGB(180,40,40)
	cancelBtn.Text="✕  Cancel"; cancelBtn.TextColor3=Color3.new(1,1,1)
	cancelBtn.TextScaled=true; cancelBtn.Font=Enum.Font.GothamBold
	cancelBtn.BorderSizePixel=0; cancelBtn.Parent=panel
	Instance.new("UICorner",cancelBtn).CornerRadius=UDim.new(0,10)

	if canDo then
		confirmBtn.MouseButton1Click:Connect(function()
			RE_RebirthConfirm:FireServer()
			screen:Destroy()
		end)
	end
	cancelBtn.MouseButton1Click:Connect(function() screen:Destroy() end)
end)

-- Board click / title update → open leaderboard panel
RE_TitleUpdate.OnClientEvent:Connect(function(msg)
	if msg == "__openleaderboard__" then
		local UIController = require(script.Parent.UI.UIController)
		UIController.TogglePanel("LeaderboardPanel", CurrentData)
	end
end)

-- Secret found popup
RE_SecretFound.OnClientEvent:Connect(function(reward)
	local screen=Instance.new("ScreenGui")
	screen.Name="SecretFoundGui"; screen.ResetOnSpawn=false
	screen.DisplayOrder=200; screen.IgnoreGuiInset=true; screen.Parent=PlayerGui

	local bg=Instance.new("Frame")
	bg.Size=UDim2.new(1,0,1,0); bg.BackgroundColor3=Color3.new(0,0,0)
	bg.BackgroundTransparency=0.5; bg.BorderSizePixel=0; bg.Parent=screen

	local panel=Instance.new("Frame")
	panel.Size=UDim2.new(0,420,0,240)
	panel.Position=UDim2.new(0.5,-210,0.5,300)
	panel.BackgroundColor3=Color3.fromRGB(12,8,24)
	panel.BorderSizePixel=0; panel.Parent=screen
	Instance.new("UICorner",panel).CornerRadius=UDim.new(0,16)
	local stroke=Instance.new("UIStroke",panel)
	stroke.Color=Color3.fromRGB(255,215,0); stroke.Thickness=3

	TweenService:Create(panel,TweenInfo.new(0.5,Enum.EasingStyle.Back),{
		Position=UDim2.new(0.5,-210,0.5,-120)
	}):Play()

	local t1=Instance.new("TextLabel")
	t1.Size=UDim2.new(1,0,0,60); t1.BackgroundTransparency=1
	t1.Text="🗝️  SECRET FOUND!"; t1.TextColor3=Color3.fromRGB(255,215,0)
	t1.TextScaled=true; t1.Font=Enum.Font.GothamBold; t1.Parent=panel

	local t2=Instance.new("TextLabel")
	t2.Size=UDim2.new(1,-20,0,60); t2.Position=UDim2.new(0,10,0,65)
	t2.BackgroundTransparency=1
	t2.Text="You found the hidden secret of Mystic Pets!\n💰 +"..fmt(reward.coins or 0).."  💎 +"..fmt(reward.gems or 0)
	t2.TextColor3=Color3.new(1,1,1); t2.TextScaled=true
	t2.Font=Enum.Font.GothamBold; t2.TextWrapped=true; t2.Parent=panel

	local hint=Instance.new("TextLabel")
	hint.Size=UDim2.new(1,-20,0,30); hint.Position=UDim2.new(0,10,0,130)
	hint.BackgroundTransparency=1; hint.Text="Share the secret with your friends... or keep it 🤫"
	hint.TextColor3=Color3.fromRGB(150,150,180); hint.TextScaled=true
	hint.Font=Enum.Font.Gotham; hint.TextWrapped=true; hint.Parent=panel

	local okBtn=Instance.new("TextButton")
	okBtn.Size=UDim2.new(0,160,0,44); okBtn.Position=UDim2.new(0.5,-80,1,-56)
	okBtn.BackgroundColor3=Color3.fromRGB(255,180,0); okBtn.Text="Awesome! 🎉"
	okBtn.TextColor3=Color3.new(0,0,0); okBtn.TextScaled=true
	okBtn.Font=Enum.Font.GothamBold; okBtn.BorderSizePixel=0; okBtn.Parent=panel
	Instance.new("UICorner",okBtn).CornerRadius=UDim.new(0,10)
	okBtn.MouseButton1Click:Connect(function() screen:Destroy() end)

	task.delay(8,function() if screen and screen.Parent then screen:Destroy() end end)
end)

-- Welcome Back (offline earnings) popup
RE_OfflineEarnings.OnClientEvent:Connect(function(coins, awaySeconds)
	local screen=Instance.new("ScreenGui")
	screen.Name="WelcomeBackGui"; screen.ResetOnSpawn=false
	screen.DisplayOrder=200; screen.IgnoreGuiInset=true; screen.Parent=PlayerGui

	local bg=Instance.new("Frame")
	bg.Size=UDim2.new(1,0,1,0); bg.BackgroundColor3=Color3.new(0,0,0)
	bg.BackgroundTransparency=0.5; bg.BorderSizePixel=0; bg.Parent=screen

	local panel=Instance.new("Frame")
	panel.Size=UDim2.new(0,420,0,240); panel.Position=UDim2.new(0.5,-210,0.5,300)
	panel.BackgroundColor3=Color3.fromRGB(12,18,28); panel.BorderSizePixel=0; panel.Parent=screen
	Instance.new("UICorner",panel).CornerRadius=UDim.new(0,16)
	local stroke=Instance.new("UIStroke",panel); stroke.Color=Color3.fromRGB(90,200,255); stroke.Thickness=3
	TweenService:Create(panel,TweenInfo.new(0.5,Enum.EasingStyle.Back),{Position=UDim2.new(0.5,-210,0.5,-120)}):Play()

	local hrs = math.floor(awaySeconds/3600)
	local mins = math.floor((awaySeconds%3600)/60)
	local awayTxt = (hrs>0 and (hrs.."h "..mins.."m") or (mins.."m"))

	local t1=Instance.new("TextLabel")
	t1.Size=UDim2.new(1,0,0,60); t1.BackgroundTransparency=1
	t1.Text="👋  WELCOME BACK!"; t1.TextColor3=Color3.fromRGB(120,220,255)
	t1.TextScaled=true; t1.Font=Enum.Font.GothamBold; t1.Parent=panel

	local t2=Instance.new("TextLabel")
	t2.Size=UDim2.new(1,-20,0,70); t2.Position=UDim2.new(0,10,0,68); t2.BackgroundTransparency=1
	t2.Text="Your pets earned while you were away ("..awayTxt.."):\n💰 +"..fmt(coins).." coins"
	t2.TextColor3=Color3.new(1,1,1); t2.TextScaled=true; t2.Font=Enum.Font.GothamBold
	t2.TextWrapped=true; t2.Parent=panel

	local okBtn=Instance.new("TextButton")
	okBtn.Size=UDim2.new(0,180,0,46); okBtn.Position=UDim2.new(0.5,-90,1,-58)
	okBtn.BackgroundColor3=Color3.fromRGB(60,180,255); okBtn.Text="Collect! 💰"
	okBtn.TextColor3=Color3.new(0,0,0); okBtn.TextScaled=true; okBtn.Font=Enum.Font.GothamBold
	okBtn.BorderSizePixel=0; okBtn.Parent=panel
	Instance.new("UICorner",okBtn).CornerRadius=UDim.new(0,10)
	okBtn.MouseButton1Click:Connect(function() screen:Destroy() end)
	task.delay(12,function() if screen and screen.Parent then screen:Destroy() end end)
end)

-- Globals for UI modules
_G.MysticPets = {
	-- Both names, on purpose. HatchUI and RebirthPanel call G().formatNum(n)
	-- with no fallback, and this table only ever exported `fmt` — so the first
	-- number either of them tried to format threw, Build never returned, and
	-- the Hatch and Rebirth buttons did nothing at all when pressed. Nothing in
	-- Output but a red line nobody was reading, and the egg-opening screen —
	-- the core of the game — simply would not open.
	fmt=fmt, formatNum=fmt,
	GameConfig=GameConfig, showToast=showToast,
	RE_HatchEgg=RE_HatchEgg, RE_EquipPet=RE_EquipPet, RE_UnequipPet=RE_UnequipPet,
	RE_BuyArea=RE_BuyArea, RE_Rebirth=RE_Rebirth, RE_DeletePet=RE_DeletePet,
	RE_BuyGamepass=RE_BuyGamepass, RE_BuyUpgrade=RE_BuyUpgrade,
	RF_Admin=RF_Admin, RE_PetCmd=RE_PetCmd,
	getPlayer=function() return Player end,
	getData=function() return CurrentData end,
	layoutHUD=function() layoutHUD() end,
}

-- Admin button — only appears for authorized users (server decides)
task.spawn(function()
	local ok, isAdm = pcall(function() return RF_Admin:InvokeServer("check") end)
	if not (ok and isAdm) then return end
	local btn = Instance.new("TextButton")
	btn.Name="AdminBtn"; btn.Size=UDim2.new(0,96,0,40); btn.Position=UDim2.new(0,10,1,-52)
	btn.BackgroundColor3=Color3.fromRGB(150,30,30); btn.Text="🛠 Admin"
	btn.TextColor3=Color3.new(1,1,1); btn.TextScaled=true; btn.Font=Enum.Font.GothamBold
	btn.BorderSizePixel=0; btn.Parent=HUD
	Instance.new("UICorner",btn).CornerRadius=UDim.new(0,10)
	Instance.new("UIStroke",btn).Color=Color3.fromRGB(255,120,120)
	btn.MouseButton1Click:Connect(function()
		require(script.Parent.UI.UIController).TogglePanel("AdminPanel", CurrentData)
	end)
end)

-- ============================================================
-- INIT
-- ============================================================
buildHUD()
layoutHUD()

if moreBtn then
	moreBtn.MouseButton1Click:Connect(function()
		dockExpanded = not dockExpanded
		layoutHUD()
	end)
end

local function showMute(m)
	if muteBtn then muteBtn.Text = m and "🔇" or "🔊" end
end
if muteBtn then
	muteBtn.MouseButton1Click:Connect(function()
		local m = not (Sfx and Sfx.IsMuted())
		-- Click sound BEFORE muting when switching off, so the switch itself is
		-- heard once; switching back on is heard by the click Responsive plays.
		if Sfx then Sfx.SetMuted(m) end
		showMute(m)
		if RE_SetMuted then RE_SetMuted:FireServer(m) end
	end)
end

-- Follow the screen: rotating a phone, resizing a window, or the camera
-- arriving after this script ran all change the viewport.
local function watchCamera(cam)
	if not cam then return end
	pcall(function()
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(layoutHUD)
	end)
	layoutHUD()
end
watchCamera(workspace.CurrentCamera)
pcall(function()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		watchCamera(workspace.CurrentCamera)
	end)
end)

local ok, data = pcall(function() return RF_GetData:InvokeServer() end)
if ok and data then onDataUpdated(data) end

-- Fade out loading screen then show welcome message
task.delay(2, function()
	TweenService:Create(loadBg,    TweenInfo.new(0.8), {BackgroundTransparency=1}):Play()
	TweenService:Create(loadTitle, TweenInfo.new(0.8), {TextTransparency=1}):Play()
	TweenService:Create(loadSub,   TweenInfo.new(0.8), {TextTransparency=1}):Play()
	TweenService:Create(barBg,     TweenInfo.new(0.8), {BackgroundTransparency=1}):Play()
	task.delay(0.85, function() loadScreen:Destroy() end)

	-- Welcome + like reminder banner
	task.delay(1.2, function()
		local wScreen = Instance.new("ScreenGui")
		wScreen.Name="WelcomeGui"; wScreen.ResetOnSpawn=false
		wScreen.DisplayOrder=60; wScreen.IgnoreGuiInset=true
		wScreen.Parent=PlayerGui

		local card = Instance.new("Frame")
		card.Size    = UDim2.new(0,400,0,130)
		card.Position= UDim2.new(0.5,-200,1,10)  -- start below screen
		card.BackgroundColor3 = Color3.fromRGB(12,9,25)
		card.BackgroundTransparency = 0.05
		card.BorderSizePixel = 0
		card.Parent = wScreen
		Instance.new("UICorner",card).CornerRadius=UDim.new(0,14)
		local stroke=Instance.new("UIStroke",card)
		stroke.Color=Color3.fromRGB(180,80,255); stroke.Thickness=2.5

		-- Gradient background
		local grad=Instance.new("UIGradient",card)
		grad.Color=ColorSequence.new({
			ColorSequenceKeypoint.new(0,Color3.fromRGB(40,15,80)),
			ColorSequenceKeypoint.new(1,Color3.fromRGB(12,9,25)),
		})
		grad.Rotation=135

		-- Lines of text
		local lines = {
			{ text="🌙  Welcome to Mystic Pets!",  color=Color3.fromRGB(200,120,255), font=Enum.Font.GothamBold, size=UDim2.new(1,-20,0,38), pos=UDim2.new(0,10,0,8)  },
			{ text="👍  If you enjoy the game, please leave a Like!", color=Color3.fromRGB(255,215,0),  font=Enum.Font.GothamBold, size=UDim2.new(1,-20,0,28), pos=UDim2.new(0,10,0,48) },
			{ text="❤️  Thank you so much for playing — it means everything!",  color=Color3.fromRGB(200,200,220), font=Enum.Font.Gotham,     size=UDim2.new(1,-20,0,24), pos=UDim2.new(0,10,0,78) },
			{ text="✨  Share with friends & help us grow!",          color=Color3.fromRGB(150,220,255), font=Enum.Font.Gotham,     size=UDim2.new(1,-20,0,22), pos=UDim2.new(0,10,0,102)},
		}
		for _, l in ipairs(lines) do
			local lbl=Instance.new("TextLabel")
			lbl.Size=l.size; lbl.Position=l.pos
			lbl.BackgroundTransparency=1; lbl.Text=l.text
			lbl.TextColor3=l.color; lbl.TextScaled=true
			lbl.Font=l.font; lbl.TextXAlignment=Enum.TextXAlignment.Left
			lbl.TextWrapped=true; lbl.Parent=card
		end

		-- Slide up from bottom
		TweenService:Create(card,TweenInfo.new(0.5,Enum.EasingStyle.Back),{
			Position=UDim2.new(0.5,-200,1,-145)
		}):Play()

		-- Slide back down after 6 seconds
		task.delay(6, function()
			if card and card.Parent then
				TweenService:Create(card,TweenInfo.new(0.4,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{
					Position=UDim2.new(0.5,-200,1,10)
				}):Play()
				task.delay(0.5,function()
					if wScreen then wScreen:Destroy() end
				end)
			end
		end)
	end)
end)

-- ============================================================
-- BUILD BADGE  (Studio only — players never see it)
-- ============================================================
-- "Nothing changed" and "the new code did not install" look identical from
-- inside the game, and the difference matters enormously: one is a complaint
-- about the work, the other is a complaint about a folder being in the wrong
-- place. Reading the Output window is not a reasonable thing to ask, so the
-- answer is on screen for two seconds.
--
-- It shows the map part count, which is the number that actually moves when
-- the map changes — config counts like "5 worlds" stay identical across every
-- revision and settle nothing.
task.spawn(function()
	if not game:GetService("RunService"):IsStudio() then return end

	local map = workspace:WaitForChild("StarPetsMap", 25)
	local parts, props = 0, 0
	if map then
		for _, d in ipairs(map:GetDescendants()) do
			if d:IsA("BasePart") then
				parts = parts + 1
				if d:GetAttribute("StarPetsBuilt") then props = props + 1 end
			end
		end
	end

	local sg = Instance.new("ScreenGui")
	sg.Name = "StarPetsBuildBadge"
	sg.ResetOnSpawn = false
	sg.DisplayOrder = 999
	sg.IgnoreGuiInset = true
	sg.Parent = PlayerGui

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0, 300, 0, 26)
	lbl.Position = UDim2.new(0, 8, 1, -34)
	lbl.BackgroundColor3 = Color3.fromRGB(14, 12, 22)
	lbl.BackgroundTransparency = 0.25
	lbl.BorderSizePixel = 0
	lbl.Font = Enum.Font.Code
	lbl.TextSize = 13
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = map
		and ("  StarPets build OK  -  " .. parts .. " map parts")
		or "  StarPets: NO StarPetsMap - the server code did not run"
	lbl.TextColor3 = map and Color3.fromRGB(150, 235, 160)
		or Color3.fromRGB(255, 140, 140)
	lbl.Parent = sg
	Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 6)

	task.delay(12, function()
		if sg then sg:Destroy() end
	end)
end)

print("[MysticPets] Client ready!")
