-- MysticPets: EggService.lua
-- Place in: ServerScriptService > Server > EggService (ModuleScript)

local TweenService = game:GetService("TweenService")

local GameConfig  = require(game.ReplicatedStorage.Shared.GameConfig)
local DataManager = require(script.Parent.DataManager)
local PetService  = require(script.Parent.PetService)

local EggService = {}

-- ============================================================
-- RARITY ROLLER
-- ============================================================
local RARITY_ORDER = { "Mythic", "Legendary", "Epic", "Rare", "Uncommon", "Common" }

-- Pick a rarity, with luck actually raising the odds of the good ones.
--
-- The previous version multiplied EVERY weight by the luck value and then drew
-- from the new total. Scaling every term of a distribution by the same number
-- leaves that distribution exactly as it was, so the Lucky Boost gamepass —
-- 349 Robux, sold as "1.5x better egg luck always!" — changed nothing at all.
-- Measured over 300,000 rolls with and without it, every rarity moved by less
-- than a tenth of a percent, which is sampling noise; Mythic came out LOWER
-- with the boost than without.
--
-- Luck now scales the rare tiers only. Common is left alone and absorbs the
-- difference, which is what makes the proportions actually move.
local function rollRarity(weights, luck)
	luck = math.max(1, tonumber(luck) or 1)

	local scaled, total = {}, 0
	for _, rarity in ipairs(RARITY_ORDER) do
		local w = weights[rarity] or 0
		if rarity ~= "Common" then w = w * luck end
		scaled[rarity] = w
		total = total + w
	end
	if total <= 0 then return "Common" end

	-- A float draw rather than math.random(1, total): the weights are no longer
	-- whole numbers once luck has been applied, and math.random(1, 0) throws
	-- outright on an egg whose weights are all zero.
	local roll = math.random() * total
	local cumulative = 0
	for _, rarity in ipairs(RARITY_ORDER) do
		cumulative = cumulative + scaled[rarity]
		if roll <= cumulative then return rarity end
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
	-- Both sources of luck, multiplied. The Lucky Charm upgrade was read by
	-- nothing anywhere in the project: three levels, 54,000 coins to max, and
	-- the only thing buying it changed was the number drawn on the panel.
	local luckyBoost = (data.GP_LuckyBoost and GameConfig.Settings.LuckyBoostMultiplier or 1)
		* (GameConfig.UpgradeValue(data, "LuckyCharm") or 1)

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
	-- Roll a mutation (rarest-first; lucky boost improves odds)
	for _, mut in ipairs(GameConfig.Mutations) do
		if math.random() < (mut.chance * luckyBoost) then
			newPet.mutation = mut.id
			break
		end
	end
	-- Through the choke point: it stamps the Pet Index and enforces the cap.
	PetService.GrantPet(player, newPet)
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
