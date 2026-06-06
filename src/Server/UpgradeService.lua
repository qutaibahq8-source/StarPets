-- MysticPets: UpgradeService.lua
-- Place in: ServerScriptService > Server > UpgradeService (ModuleScript)

local Players    = game:GetService("Players")
local GameConfig = require(game.ReplicatedStorage.Shared.GameConfig)
local DataManager = require(script.Parent.DataManager)

local UpgradeService = {}

-- Build lookup by key
local UpgradeLookup = {}
for _, upg in ipairs(GameConfig.Upgrades) do
	UpgradeLookup[upg.key] = upg
end

-- ============================================================
-- BUY UPGRADE
-- ============================================================
function UpgradeService.Buy(player, upgradeKey)
	local data = DataManager.GetData(player)
	if not data then return false, "No data" end

	data.Upgrades = data.Upgrades or {}

	local upg = UpgradeLookup[upgradeKey]
	if not upg then return false, "Invalid upgrade" end

	local currentLevel = data.Upgrades[upgradeKey] or 0
	local nextLevel    = currentLevel + 1

	if nextLevel > #upg.levels then
		return false, "Already max level!"
	end

	local levelData = upg.levels[nextLevel]
	if data.Coins < levelData.cost then
		return false, "Need 💰 " .. levelData.cost .. " Coins!"
	end

	data.Coins = data.Coins - levelData.cost
	data.Upgrades[upgradeKey] = nextLevel

	-- Apply immediately
	UpgradeService.ApplyToCharacter(player)
	return true, levelData
end

-- ============================================================
-- APPLY TO CHARACTER (call on CharacterAdded + after purchase)
-- ============================================================
function UpgradeService.ApplyToCharacter(player)
	local data = DataManager.GetData(player)
	if not data then return end
	local char = player.Character
	if not char then return end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	data.Upgrades = data.Upgrades or {}

	-- Speed
	local speedUpg = UpgradeLookup["SpeedBoost"]
	local speedLvl = data.Upgrades["SpeedBoost"] or 0
	humanoid.WalkSpeed = speedLvl > 0 and speedUpg.levels[speedLvl].value or speedUpg.default

	-- Jump
	local jumpUpg = UpgradeLookup["JumpBoost"]
	local jumpLvl = data.Upgrades["JumpBoost"] or 0
	humanoid.JumpPower = jumpLvl > 0 and jumpUpg.levels[jumpLvl].value or jumpUpg.default
end

return UpgradeService
