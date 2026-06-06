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
	orb.Name       = isGem and "GemOrb" or "CoinOrb"
	orb.Shape      = Enum.PartType.Ball
	orb.Size       = Vector3.new(1.4, 1.4, 1.4)
	orb.Color      = isGem and Color3.fromRGB(0, 200, 255) or Color3.fromRGB(255, 215, 0)
	orb.Material   = Enum.Material.Neon
	orb.Anchored   = true
	orb.CanCollide = false
	orb.CastShadow = false
	orb.Position   = position
	orb.Parent     = OrbsFolder

	-- NOTE: no per-orb PointLight. With hundreds of orbs that was ~500 lights
	-- washing the whole map out. The Neon material already makes them pop.

	-- Float bob (client handles visuals, server just positions)
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
