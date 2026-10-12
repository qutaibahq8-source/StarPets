-- MysticPets: GameClient.client.lua
local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")

local Player    = Players.LocalPlayer
local PlayerGui = Player.PlayerGui

-- A centred popup (rebirth, secret found, welcome back), fitted to the screen
-- and popped in.
--
-- These were 420 px wide in hard pixels and slid in by tweening Position, so
-- on a 390-wide phone they hung off both edges — and the rebirth popup's two
-- 180-wide buttons, pinned to opposite sides, overlapped by 34 px. They are
-- sized the way every panel is now (scale, clamped to the size they were
-- designed at), and pop in on a UIScale, which never touches Position.
local function popup(panel)
	local okR, Responsive = pcall(function() return require(script.Parent.UI.Responsive) end)
	if okR and Responsive then Responsive.FitFrame(panel) end
	local s = Instance.new("UIScale"); s.Name = "SPEnter"; s.Scale = 0.85; s.Parent = panel
	TweenService:Create(s, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
-- The HUD itself: counters, cards, menu and buttons. Built and laid out in its
-- own module; this script feeds it data and owns what its switches do.
local HUDView = require(script.Parent.UI.HUD)

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
local RE_SetSwitch    = Remotes:WaitForChild("SetSwitch", 10)
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

	-- Below the HUD's counters, not over them: a toast about coins used to
	-- cover the coin counter for the three seconds it was up.
	TweenService:Create(frame,TweenInfo.new(0.35,Enum.EasingStyle.Back),{
		Position=UDim2.new(0.5,-170,0,HUDView.ClearY() + 6)
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

-- Sound on/off, from the HUD's Sound switch. Saved with the player.
local function toggleMute()
	local m = not (Sfx and Sfx.IsMuted())
	if Sfx then Sfx.SetMuted(m) end
	HUDView.RefreshSwitches()
	if RE_SetMuted then RE_SetMuted:FireServer(m) end
end

-- The HUD's switches (Auto Hatch, Auto Collect, Fast Hatch). Shown flipped
-- at once; the server decides, and its update, sent straight back, is what
-- the switch then shows — so a refused switch (Auto Hatch below its level)
-- flips back.
local SWITCH_FIELD = {
	AutoCollect = function(d, on) d.AutoCollectOff = not on end,
	AutoHatch   = function(d, on) d.AutoHatch = on end,
	FastHatch   = function(d, on) d.FastHatch = on end,
}
local function setSwitch(name, on)
	if CurrentData and SWITCH_FIELD[name] then SWITCH_FIELD[name](CurrentData, on) end
	if RE_SetSwitch then RE_SetSwitch:FireServer(name, on) end
	HUDView.RefreshSwitches()
end

local function buildHUD()
	HUD = Instance.new("ScreenGui")
	HUD.Name="MysticPetsHUD"; HUD.ResetOnSpawn=false
	HUD.DisplayOrder=10; HUD.IgnoreGuiInset=true
	HUD.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; HUD.Parent=PlayerGui
	HUDView.Init({
		fmt = fmt,
		getData = function() return CurrentData end,
		isMuted = function() return Sfx ~= nil and Sfx.IsMuted() end,
		onMute = toggleMute,
		onSwitch = setSwitch,
	}, HUD)
end

-- Lay the HUD out for the screen it is on. HUDView picks the layout: the
-- mockup's cards on a computer, side rails of touch-sized buttons on a phone.
local function layoutHUD()
	HUDView.Layout()
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
	HUDView.Update(data)
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

-- A world gate was clicked → ask, and buy on yes.
--
-- Nothing listened for this. Clicking a gate made the server send BuyArea to
-- the client, and no version of the client ever had a handler for it, or ever
-- asked the server to buy an area at all: the purchase code on the server was
-- unreachable. No player could leave the Meadow except through the admin
-- panel's "Unlock ALL Worlds". check_firstplay now walks a player through
-- the Forest gate.
RE_BuyArea.OnClientEvent:Connect(function(areaId)
	if not CurrentData then return end
	local area, prev
	for i, a in ipairs(GameConfig.Areas) do
		if a.id == areaId then area = a; prev = GameConfig.Areas[i - 1]; break end
	end
	if not area then return end
	local owned = {}
	for _, id in ipairs(CurrentData.UnlockedAreas or {}) do owned[id] = true end
	if owned[areaId] then return end

	local existing = PlayerGui:FindFirstChild("AreaUnlockGui")
	if existing then existing:Destroy() end
	local screen = Instance.new("ScreenGui")
	screen.Name = "AreaUnlockGui"; screen.ResetOnSpawn = false
	screen.DisplayOrder = 80; screen.IgnoreGuiInset = true; screen.Parent = PlayerGui

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 420, 0, 260)
	panel.BackgroundColor3 = Color3.fromRGB(14, 18, 30); panel.BorderSizePixel = 0
	panel.Parent = screen
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)
	local stroke = Instance.new("UIStroke", panel)
	stroke.Color = area.groundColor or Color3.fromRGB(120, 200, 120); stroke.Thickness = 3
	popup(panel)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -20, 0, 46); title.Position = UDim2.new(0, 10, 0, 10)
	title.BackgroundTransparency = 1; title.Text = "🔓  " .. area.name
	title.TextColor3 = Color3.new(1, 1, 1); title.TextScaled = true
	title.Font = Enum.Font.GothamBold; title.Parent = panel

	local icon = area.currency == "Gems" and "💎 " or "💰 "
	local have = area.currency == "Gems" and (CurrentData.Gems or 0) or (CurrentData.Coins or 0)
	local needPrev = prev and not owned[prev.id]
	local canPay = have >= (area.unlockCost or 0)

	local body = Instance.new("TextLabel")
	body.Size = UDim2.new(1, -30, 0, 110); body.Position = UDim2.new(0, 15, 0, 60)
	body.BackgroundTransparency = 1; body.TextWrapped = true; body.TextScaled = true
	body.Font = Enum.Font.Gotham; body.TextColor3 = Color3.fromRGB(200, 205, 220)
	body.Text = (area.description or "") .. "\n\n"
		.. (needPrev and ("Unlock " .. prev.name .. " first.")
			or ("Costs " .. icon .. fmt(area.unlockCost) .. (canPay and ""
				or ("  —  you have " .. icon .. fmt(have)))))
	body.Parent = panel

	local yes = Instance.new("TextButton")
	yes.Name = "Unlock"
	yes.Size = UDim2.new(0.5, -30, 0, 50); yes.Position = UDim2.new(0, 20, 1, -66)
	local ready = canPay and not needPrev
	yes.BackgroundColor3 = ready and Color3.fromRGB(50, 170, 80) or Color3.fromRGB(60, 62, 76)
	yes.Active = ready; yes.AutoButtonColor = ready
	yes.Text = "Unlock " .. icon .. fmt(area.unlockCost)
	yes.TextColor3 = Color3.new(1, 1, 1); yes.TextScaled = true
	yes.Font = Enum.Font.GothamBold; yes.BorderSizePixel = 0; yes.Parent = panel
	Instance.new("UICorner", yes).CornerRadius = UDim.new(0, 10)

	local no = Instance.new("TextButton")
	no.Name = "Cancel"
	no.Size = UDim2.new(0.5, -30, 0, 50); no.Position = UDim2.new(0.5, 10, 1, -66)
	no.BackgroundColor3 = Color3.fromRGB(80, 50, 60); no.Text = "Not yet"
	no.TextColor3 = Color3.new(1, 1, 1); no.TextScaled = true
	no.Font = Enum.Font.GothamBold; no.BorderSizePixel = 0; no.Parent = panel
	Instance.new("UICorner", no).CornerRadius = UDim.new(0, 10)

	yes.MouseButton1Click:Connect(function()
		if not ready then return end
		RE_BuyArea:FireServer(areaId)
		screen:Destroy()
	end)
	no.MouseButton1Click:Connect(function() screen:Destroy() end)
	pcall(function() require(script.Parent.UI.Responsive).Apply(screen) end)
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
	panel.BackgroundColor3=Color3.fromRGB(15,10,30)
	panel.BorderSizePixel=0; panel.Parent=screen
	Instance.new("UICorner",panel).CornerRadius=UDim.new(0,16)
	local stroke=Instance.new("UIStroke",panel)
	stroke.Color=Color3.fromRGB(180,0,255); stroke.Thickness=2.5
	popup(panel)

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
	-- Half the panel each, so they share a narrow screen instead of overlapping.
	confirmBtn.Size=UDim2.new(0.5,-30,0,50); confirmBtn.Position=UDim2.new(0,20,1,-70)
	confirmBtn.BackgroundColor3=canDo and Color3.fromRGB(150,0,255) or Color3.fromRGB(60,60,80)
	confirmBtn.Text=canDo and "♻️  REBIRTH!" or "Not Ready"
	confirmBtn.TextColor3=Color3.new(1,1,1); confirmBtn.TextScaled=true
	confirmBtn.Font=Enum.Font.GothamBold; confirmBtn.BorderSizePixel=0
	confirmBtn.Active=canDo; confirmBtn.Parent=panel
	Instance.new("UICorner",confirmBtn).CornerRadius=UDim.new(0,10)

	local cancelBtn=Instance.new("TextButton")
	cancelBtn.Size=UDim2.new(0.5,-30,0,50); cancelBtn.Position=UDim2.new(0.5,10,1,-70)
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
	panel.BackgroundColor3=Color3.fromRGB(12,8,24)
	panel.BorderSizePixel=0; panel.Parent=screen
	Instance.new("UICorner",panel).CornerRadius=UDim.new(0,16)
	local stroke=Instance.new("UIStroke",panel)
	stroke.Color=Color3.fromRGB(255,215,0); stroke.Thickness=3
	popup(panel)

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
	panel.Size=UDim2.new(0,420,0,240)
	panel.BackgroundColor3=Color3.fromRGB(12,18,28); panel.BorderSizePixel=0; panel.Parent=screen
	Instance.new("UICorner",panel).CornerRadius=UDim.new(0,16)
	local stroke=Instance.new("UIStroke",panel); stroke.Color=Color3.fromRGB(90,200,255); stroke.Thickness=3
	popup(panel)

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
	-- How far down the HUD reaches at the top centre, for anything that drops
	-- in from the top (the onboarding card) to sit below.
	hudClearY=function() return HUDView.ClearY() end,
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

		-- Anchored at its top centre, as wide as the screen allows up to the
		-- 400 it was designed at. It was 400 hard pixels: wider than a phone.
		local card = Instance.new("Frame")
		card.AnchorPoint = Vector2.new(0.5, 0)
		card.Size    = UDim2.new(0.94,0,0,130)
		card.Position= UDim2.new(0.5,0,1,10)  -- start below screen
		local cardMax = Instance.new("UISizeConstraint")
		cardMax.MaxSize = Vector2.new(400, 130); cardMax.Parent = card
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
			Position=UDim2.new(0.5,0,1,-145)
		}):Play()

		-- Slide back down after 6 seconds
		task.delay(6, function()
			if card and card.Parent then
				TweenService:Create(card,TweenInfo.new(0.4,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{
					Position=UDim2.new(0.5,0,1,10)
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
