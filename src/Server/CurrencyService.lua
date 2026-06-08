-- MysticPets: CurrencyService.lua
-- Place in: ServerScriptService > Server > CurrencyService (ModuleScript)

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local GameConfig  = require(game.ReplicatedStorage.Shared.GameConfig)
local DataManager = require(script.Parent.DataManager)

local CurrencyService = {}

local OrbsFolder = nil
local OrbData    = {}   -- [Part] -> { value, isgem, areaId, respawnTime }
local OrbCooldown = {}  -- [Part] -> bool (collected, waiting to respawn)

-- ============================================================
-- ORB CREATION
-- ============================================================
local function createOrb(position, value, isGem, areaId)
	local orb = Instance.new("Part")
	if isGem then
		-- gem: shiny cyan crystal
		orb.Name     = "GemOrb"
		orb.Shape    = Enum.PartType.Ball
		orb.Size     = Vector3.new(1.2, 1.6, 1.2)
		orb.Color    = Color3.fromRGB(70, 215, 255)
		orb.Material  = Enum.Material.Glass
		orb.Reflectance = 0.3
	else
		-- coin: VERTICAL gold disc with a paw emblem on each face
		orb.Name     = "CoinOrb"
		orb.Shape    = Enum.PartType.Cylinder
		orb.Size     = Vector3.new(0.4, 2.0, 2.0)   -- thin disc, axis on X = stands vertical
		orb.Color    = Color3.fromRGB(255, 200, 40)
		orb.Material  = Enum.Material.Foil
		orb.Reflectance = 0.15
		-- one cool minted face: gold ring border + a paw stamped in the middle
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Right; sg.Adornee = orb; sg.CanvasSize = Vector2.new(140,140)
		sg.LightInfluence = 1; sg.Parent = orb
		local ring = Instance.new("Frame")
		ring.Size = UDim2.new(0.92,0,0.92,0); ring.Position = UDim2.new(0.04,0,0.04,0)
		ring.BackgroundColor3 = Color3.fromRGB(210,160,30); ring.BorderSizePixel = 0; ring.Parent = sg
		Instance.new("UICorner", ring).CornerRadius = UDim.new(1,0)
		local inner = Instance.new("Frame")
		inner.Size = UDim2.new(0.84,0,0.84,0); inner.Position = UDim2.new(0.08,0,0.08,0)
		inner.BackgroundColor3 = Color3.fromRGB(255,212,70); inner.BorderSizePixel = 0; inner.Parent = ring
		Instance.new("UICorner", inner).CornerRadius = UDim.new(1,0)
		local paw = Instance.new("TextLabel")
		paw.Size = UDim2.new(0.8,0,0.8,0); paw.Position = UDim2.new(0.1,0,0.1,0)
		paw.BackgroundTransparency = 1; paw.Text = "🐾"; paw.TextColor3 = Color3.fromRGB(120,80,5)
		paw.TextScaled = true; paw.Font = Enum.Font.GothamBold; paw.Parent = inner
	end
	orb.Anchored   = true
	orb.CanCollide = false
	orb.CastShadow = false
	orb.Position   = position
	orb.Parent     = OrbsFolder
	OrbData[orb] = { value = value, isGem = isGem, areaId = areaId }
	return orb
end

-- ============================================================
-- MAP ORB SEEDING
-- ============================================================
function CurrencyService.SeedArea(areaId, areaOrigin, orbCount)
	local areaConfig = nil
	for _, a in ipairs(GameConfig.Areas) do
		if a.id == areaId then areaConfig = a break end
	end
	if not areaConfig then return end

	for i = 1, orbCount do
		local x = areaOrigin.X + math.random(-58, 58)
		local z = areaOrigin.Z + math.random(-85, 85)
		local y = areaOrigin.Y + 3.5  -- float above the tall grass so orbs are visible
		local pos = Vector3.new(x, y, z)

		local isGem = (math.random() < (areaConfig.gemOrbChance or 0.01))
		local value = isGem and 1 or areaConfig.coinOrbValue
		createOrb(pos, value, isGem, areaId)
	end
end

-- ============================================================
-- COLLECTION (touch detection on server)
-- ============================================================
local function collectOrb(player, orb)
	if OrbCooldown[orb] then return end
	local orbInfo = OrbData[orb]
	if not orbInfo then return end

	local data = DataManager.GetData(player)
	if not data then return end

	-- Check player is in this area
	local unlockedSet = {}
	for _, areaId in ipairs(data.UnlockedAreas) do
		unlockedSet[areaId] = true
	end
	if not unlockedSet[orbInfo.areaId] then return end

	OrbCooldown[orb] = true
	orb.Transparency = 1  -- hide immediately
	for _, d in ipairs(orb:GetChildren()) do if d:IsA("SurfaceGui") then d.Enabled = false end end

	-- Apply multipliers
	local rebirthMult = data.RebirthMultiplier or 1
	local coinBoost   = (data.GP_2xCoins and 2 or 1)
	local gemBoost    = (data.GP_VIP and GameConfig.Settings.VIPGemMultiplier or 1)

	if orbInfo.isGem then
		local earned = math.max(1, math.floor(orbInfo.value * rebirthMult * gemBoost))
		DataManager.IncrementData(player, "Gems", earned)
		DataManager.IncrementData(player, "TotalGemsEarned", earned)
	else
		local earned = math.max(1, math.floor(orbInfo.value * rebirthMult * coinBoost))
		DataManager.IncrementData(player, "Coins", earned)
		DataManager.IncrementData(player, "TotalCoinsEarned", earned)
	end

	-- Respawn
	task.delay(GameConfig.Settings.CoinOrbRespawnTime, function()
		orb.Transparency = 0
		for _, d in ipairs(orb:GetChildren()) do if d:IsA("SurfaceGui") then d.Enabled = true end end
		OrbCooldown[orb] = false
	end)
end

function CurrencyService.SetupOrbTouches()
	for orb, _ in pairs(OrbData) do
		orb.Touched:Connect(function(hit)
			local character = hit.Parent
			local player = Players:GetPlayerFromCharacter(character)
			if player then
				collectOrb(player, orb)
			end
		end)
	end
end

-- ============================================================
-- AUTO-COLLECT (for GP_AutoCollect owners)
-- ============================================================
RunService.Heartbeat:Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local data = DataManager.GetData(player)
		if not data or not data.GP_AutoCollect then continue end
		local char = player.Character
		if not char then continue end
		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then continue end

		for orb, info in pairs(OrbData) do
			if OrbCooldown[orb] then continue end
			if (orb.Position - root.Position).Magnitude <= GameConfig.Settings.OrbCollectRadius then
				collectOrb(player, orb)
			end
		end
	end
end)

-- ============================================================
-- PASSIVE PET INCOME
-- ============================================================
function CurrencyService.StartPassiveIncome(PetService)
	task.spawn(function()
		while true do
			task.wait(GameConfig.Settings.PetIncomeInterval)
			for _, player in ipairs(Players:GetPlayers()) do
				local coins, gems = PetService.GetPlayerIncome(player)
				if coins > 0 then
					DataManager.IncrementData(player, "Coins", coins)
					DataManager.IncrementData(player, "TotalCoinsEarned", coins)
				end
				if gems > 0 then
					DataManager.IncrementData(player, "Gems", gems)
					DataManager.IncrementData(player, "TotalGemsEarned", gems)
				end
			end
		end
	end)
end

-- ============================================================
-- TRANSACTIONS
-- ============================================================
function CurrencyService.SpendCoins(player, amount)
	local data = DataManager.GetData(player)
	if not data then return false end
	if data.Coins < amount then return false end
	data.Coins = data.Coins - amount
	return true
end

function CurrencyService.SpendGems(player, amount)
	local data = DataManager.GetData(player)
	if not data then return false end
	if data.Gems < amount then return false end
	data.Gems = data.Gems - amount
	return true
end

function CurrencyService.Init()
	OrbsFolder = Instance.new("Folder")
	OrbsFolder.Name = "Orbs"
	OrbsFolder.Parent = workspace
end

return CurrencyService
