-- MysticPets: EggService.lua
-- Place in: ServerScriptService > Server > EggService (ModuleScript)

local TweenService = game:GetService("TweenService")

local GameConfig  = require(game.ReplicatedStorage.Shared.GameConfig)
local DataManager = require(script.Parent.DataManager)

local EggService = {}

-- ============================================================
-- RARITY ROLLER
-- ============================================================
local function rollRarity(weights, luckyBoost)
	local totalWeight = 0
	for rarity, w in pairs(weights) do
		totalWeight = totalWeight + math.floor(w * (luckyBoost or 1))
	end

	local roll = math.random(1, totalWeight)
	local cumulative = 0
	-- Roll in order from rarest to common so lucky boost works properly
	local rarityOrder = { "Mythic", "Legendary", "Epic", "Rare", "Uncommon", "Common" }
	for _, rarity in ipairs(rarityOrder) do
		local w = math.floor((weights[rarity] or 0) * (luckyBoost or 1))
		cumulative = cumulative + w
		if roll <= cumulative then
			return rarity
		end
	end
	return "Common"
end

local function getPetsOfRarity(rarity)
	local results = {}
	for _, pet in ipairs(GameConfig.Pets) do
		if pet.rarity == rarity then
			table.insert(results, pet)
		end
	end
	return results
end

local function generateUniqueId()
	return tostring(math.random(100000, 999999)) .. tostring(os.time()):sub(-4)
end

-- ============================================================
-- HATCH
-- ============================================================
function EggService.HatchEgg(player, eggId)
	local data = DataManager.GetData(player)
	if not data then return nil, "No data" end

	-- Find egg config
	local eggConfig = nil
	for _, egg in ipairs(GameConfig.Eggs) do
		if egg.id == eggId then
			eggConfig = egg
			break
		end
	end
	if not eggConfig then return nil, "Invalid egg" end

	-- Determine actual cost (one-time free egg logic)
	local actualCost = eggConfig.cost
	if eggConfig.id == "StarterEgg" then
		if not data.HasClaimedFreeEgg then
			actualCost = 0  -- FREE first time only
		else
			actualCost = eggConfig.costAfterFirst or 150
		end
	end

	-- Check cost
	if eggConfig.currency == "Coins" then
		if data.Coins < actualCost then
			local needed = actualCost - data.Coins
			return nil, "Need " .. needed .. " more Coins!"
		end
		data.Coins = data.Coins - actualCost
	elseif eggConfig.currency == "Gems" then
		if data.Gems < actualCost then
			return nil, "Not enough Gems"
		end
		data.Gems = data.Gems - actualCost
	end

	-- Mark free egg as claimed
	if eggConfig.id == "StarterEgg" and not data.HasClaimedFreeEgg then
		data.HasClaimedFreeEgg = true
	end

	-- Check inventory cap
	if #data.Pets >= GameConfig.Settings.MaxPetsInInventory then
		-- Refund
		if eggConfig.currency == "Coins" then data.Coins = data.Coins + eggConfig.cost
		elseif eggConfig.currency == "Gems" then data.Gems = data.Gems + eggConfig.cost end
		return nil, "Pet inventory full (max " .. GameConfig.Settings.MaxPetsInInventory .. ")"
	end

	-- Lucky boost
	local luckyBoost = data.GP_LuckyBoost and GameConfig.Settings.LuckyBoostMultiplier or 1

	-- Roll rarity then pick a random pet of that rarity
	local rarity = rollRarity(eggConfig.rarityWeights, luckyBoost)
	local options = getPetsOfRarity(rarity)
	if #options == 0 then
		-- fallback
		rarity = "Common"
		options = getPetsOfRarity("Common")
	end

	local chosen = options[math.random(1, #options)]

	-- Add to inventory
	local newPet = {
		name     = chosen.name,
		rarity   = chosen.rarity,
		uniqueId = generateUniqueId(),
	}
	table.insert(data.Pets, newPet)
	data.EggsHatched = (data.EggsHatched or 0) + 1

	return newPet, nil
end

-- ============================================================
-- BATCH HATCH (up to 10 at once)
-- ============================================================
function EggService.HatchMultiple(player, eggId, count)
	count = math.clamp(count, 1, 10)
	local results = {}
	local errors  = {}

	for i = 1, count do
		local pet, err = EggService.HatchEgg(player, eggId)
		if pet then
			table.insert(results, pet)
		else
			table.insert(errors, err)
			break -- stop on first error (e.g. out of coins)
		end
	end

	return results, errors
end

return EggService
