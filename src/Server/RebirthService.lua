-- MysticPets: RebirthService.lua
-- Place in: ServerScriptService > Server > RebirthService (ModuleScript)

local GameConfig  = require(game.ReplicatedStorage.Shared.GameConfig)
local DataManager = require(script.Parent.DataManager)
local PetService  = require(script.Parent.PetService)

local RebirthService = {}

function RebirthService.CanRebirth(player)
	local data = DataManager.GetData(player)
	if not data then return false, "No data" end

	local currentRebirths = data.Rebirths or 0
	local nextLevel = currentRebirths + 1
	local rebirthConfig = nil

	for _, r in ipairs(GameConfig.Rebirths) do
		if r.level == nextLevel then
			rebirthConfig = r
			break
		end
	end

	if not rebirthConfig then
		return false, "Max rebirths reached"
	end

	if data.TotalCoinsEarned < rebirthConfig.requirement then
		return false, "Need " .. rebirthConfig.requirement .. " total coins earned (you have " .. data.TotalCoinsEarned .. ")"
	end

	return true, rebirthConfig
end

function RebirthService.DoRebirth(player)
	local canRebirth, rebirthConfig = RebirthService.CanRebirth(player)
	if not canRebirth then
		return false, rebirthConfig
	end

	local data = DataManager.GetData(player)

	-- Bank quest progress BEFORE anything is zeroed.
	--
	-- Quest totals are accumulated by polling, so a counter that resets between
	-- two polls loses whatever was earned in the gap — and the resets below are
	-- exactly that. A player who earned 900k coins and then rebirthed without
	-- opening the quest panel used to lose all 900k of it.
	local QuestService = require(script.Parent.QuestService)
	pcall(QuestService.Sync, data)

	-- Despawn all pet models
	PetService.DespawnAllPets(player)

	-- Reset progress but keep gamepasses and rebirth count
	data.Coins             = 0
	data.Gems              = data.Gems  -- keep gems
	data.Pets              = {}
	data.EquippedPets      = {}
	data.UnlockedAreas     = { "Meadow" }
	data.TotalCoinsEarned  = 0
	data.Rebirths          = data.Rebirths + 1
	data.RebirthMultiplier = rebirthConfig.multiplier

	return true, rebirthConfig
end

function RebirthService.GetNextRebirthInfo(player)
	local data = DataManager.GetData(player)
	if not data then return nil end

	local nextLevel = (data.Rebirths or 0) + 1
	for _, r in ipairs(GameConfig.Rebirths) do
		if r.level == nextLevel then
			return r
		end
	end
	return nil -- max rebirths
end

return RebirthService
