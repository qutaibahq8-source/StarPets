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

-- Area barriers: block locked areas for THIS player only (client-side collision)
local AreaBarriers = workspace:WaitForChild("AreaBarriers", 30)
local function updateBarriers(data)
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
		return valLbl
	end

	-- Right-aligned so they clear the Roblox menu/chat/voice icons (top-left).
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
	}
	local btnSize = 56
	local btnGap  = 7
	local cols    = 2
	local rows    = math.ceil(#navButtons / cols)
	local totalH  = rows * btnSize + (rows-1) * btnGap

	for i, btn in ipairs(navButtons) do
		local col = (i-1) % cols            -- 0 = left, 1 = right (edge)
		local row = math.floor((i-1) / cols)

		local b = Instance.new("TextButton")
		b.Size     = UDim2.new(0, btnSize, 0, btnSize)
		b.Position = UDim2.new(1, -(btnSize+10) - (cols-1-col)*(btnSize+btnGap),
			0.5, -totalH/2 + row*(btnSize+btnGap))
		b.BackgroundColor3 = Color3.fromRGB(18,14,35)
		b.BackgroundTransparency = 0.15
		b.Text     = btn.emoji.."\n"..btn.name
		b.TextColor3 = Color3.new(1,1,1)
		b.TextScaled = true
		b.Font     = Enum.Font.GothamBold
		b.BorderSizePixel = 0
		b.Parent   = HUD
		Instance.new("UICorner",b).CornerRadius = UDim.new(0,14)

		local stroke = Instance.new("UIStroke",b)
		stroke.Color = btn.color; stroke.Thickness = 2; stroke.Transparency = 0.4

		b.MouseButton1Click:Connect(function()
			local UIController = require(script.Parent.UI.UIController)
			UIController.TogglePanel(btn.panel, CurrentData)
		end)
		b.MouseEnter:Connect(function()
			TweenService:Create(b,TweenInfo.new(0.15),{BackgroundTransparency=0}):Play()
			TweenService:Create(stroke,TweenInfo.new(0.15),{Transparency=0}):Play()
		end)
		b.MouseLeave:Connect(function()
			TweenService:Create(b,TweenInfo.new(0.15),{BackgroundTransparency=0.15}):Play()
			TweenService:Create(stroke,TweenInfo.new(0.15),{Transparency=0.4}):Play()
		end)
	end
end

-- ============================================================
-- DATA UPDATE
-- ============================================================
local lastInvSig = ""
local function onDataUpdated(data)
	local newCoins = data.Coins or 0
	if CurrentData and newCoins > prevCoins then
		local diff = newCoins - prevCoins
		if diff > 0 and diff < 100000 then
			floatText("+"..fmt(diff).." 💰", Color3.fromRGB(255,215,0))
		end
	end
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

RE_HatchResult.OnClientEvent:Connect(function(pets,eggId)
	local HatchUI = require(script.Parent.UI.HatchPanel)
	HatchUI.ShowHatchResult(pets,eggId)
end)

RE_Notification.OnClientEvent:Connect(function(t,msg) showToast(t,msg) end)

RE_HatchEgg.OnClientEvent:Connect(function(eggId)
	if eggId and eggId:sub(1,11) == "__upgrade__" then
		-- Shop pad clicked — open upgrade panel
		local UIController = require(script.Parent.UI.UIController)
		UIController.TogglePanel("UpgradePanel", CurrentData)
		return
	end
	local HatchUI = require(script.Parent.UI.HatchPanel)
	HatchUI.Build(CurrentData)
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

-- Globals for UI modules
_G.MysticPets = {
	fmt=fmt, GameConfig=GameConfig, showToast=showToast,
	RE_HatchEgg=RE_HatchEgg, RE_EquipPet=RE_EquipPet, RE_UnequipPet=RE_UnequipPet,
	RE_BuyArea=RE_BuyArea, RE_Rebirth=RE_Rebirth, RE_DeletePet=RE_DeletePet,
	RE_BuyGamepass=RE_BuyGamepass, RE_BuyUpgrade=RE_BuyUpgrade,
	RF_Admin=RF_Admin, RE_PetCmd=RE_PetCmd,
	getPlayer=function() return Player end,
	getData=function() return CurrentData end,
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

print("[MysticPets] Client ready!")
