-- MysticPets: GamepassService.lua
-- Place in: ServerScriptService > Server > GamepassService (ModuleScript)
-- IMPORTANT: Replace robloxId values in GameConfig with real gamepass IDs after publishing

local MarketplaceService = game:GetService("MarketplaceService")
local Players            = game:GetService("Players")

local GameConfig  = require(game.ReplicatedStorage.Shared.GameConfig)
local DataManager = require(script.Parent.DataManager)

local GamepassService = {}

-- ============================================================
-- CHECK & GRANT
-- ============================================================
local function checkGamepass(player, gpConfig)
	local data = DataManager.GetData(player)
	if not data then return end

	-- Skip if no robloxId set yet (dev mode)
	if gpConfig.robloxId == 0 then return end

	local owns = false
	local ok, err = pcall(function()
		owns = MarketplaceService:UserOwnsGamePassAsync(player.UserId, gpConfig.robloxId)
	end)
	if not ok then
		warn("[GamepassService] Failed to check gamepass " .. gpConfig.key .. ": " .. tostring(err))
		return
	end

	if owns and not data[gpConfig.key] then
		data[gpConfig.key] = true
		print("[GamepassService] Granted " .. gpConfig.key .. " to " .. player.Name)

		-- VIP special: grant exclusive pet
		if gpConfig.key == "GP_VIP" then
			GamepassService.GrantVIPPet(player)
		end
	end
end

function GamepassService.CheckAllForPlayer(player)
	for _, gpConfig in ipairs(GameConfig.Gamepasses) do
		task.spawn(checkGamepass, player, gpConfig)
	end
end

-- ============================================================
-- PURCHASE PROMPT  (client requests, server opens prompt)
-- ============================================================
function GamepassService.PromptPurchase(player, gpKey)
	for _, gp in ipairs(GameConfig.Gamepasses) do
		if gp.key == gpKey then
			if gp.robloxId == 0 then
				warn("[GamepassService] Cannot prompt purchase: robloxId not set for " .. gpKey)
				return
			end
			MarketplaceService:PromptGamePassPurchase(player, gp.robloxId)
			return
		end
	end
end

-- ============================================================
-- PURCHASE COMPLETED CALLBACK
-- ============================================================
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if not wasPurchased then return end
	local data = DataManager.GetData(player)
	if not data then return end

	for _, gp in ipairs(GameConfig.Gamepasses) do
		if gp.robloxId == gamePassId then
			data[gp.key] = true
			print("[GamepassService] " .. player.Name .. " purchased " .. gp.key)
			if gp.key == "GP_VIP" then
				GamepassService.GrantVIPPet(player)
			end
			-- Notify client
			local remotes = game.ReplicatedStorage:FindFirstChild("Remotes")
			if remotes then
				local e = remotes:FindFirstChild("DataUpdated")
				if e then e:FireClient(player, data) end
			end
			break
		end
	end
end)

-- ============================================================
-- VIP PET GRANT
-- ============================================================
function GamepassService.GrantVIPPet(player)
	local data = DataManager.GetData(player)
	if not data then return end

	-- Check if already has VIP pet
	for _, pet in ipairs(data.Pets) do
		if pet.name == "Celestial Dragon" and pet.isVIPGrant then return end
	end

	local newPet = {
		name     = "Celestial Dragon",
		rarity   = "Mythic",
		uniqueId = "VIP_" .. player.UserId,
		isVIPGrant = true,
	}
	table.insert(data.Pets, newPet)
	print("[GamepassService] Granted VIP pet to " .. player.Name)
end

return GamepassService
