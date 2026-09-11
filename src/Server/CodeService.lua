-- StarPets: CodeService.lua
-- Place in: ServerScriptService > Server > CodeService (ModuleScript)

local HttpService = game:GetService("HttpService")
local GameConfig  = require(game.ReplicatedStorage.Shared.GameConfig)
local DataManager = require(script.Parent.DataManager)
local PetService  = require(script.Parent.PetService)

local CodeService = {}

-- returns ok, label|errString
function CodeService.Redeem(player, codeStr)
	local data = DataManager.GetData(player); if not data then return false, "no data" end
	local code = string.upper(string.gsub(tostring(codeStr or ""), "%s", ""))
	if code == "" then return false, "Enter a code" end
	local reward = GameConfig.Codes[code]
	if not reward then return false, "Invalid code" end
	data.RedeemedCodes = data.RedeemedCodes or {}
	if data.RedeemedCodes[code] then return false, "Code already used" end

	if reward.coins then data.Coins = (data.Coins or 0) + reward.coins; data.TotalCoinsEarned = (data.TotalCoinsEarned or 0) + reward.coins end
	if reward.gems  then data.Gems  = (data.Gems  or 0) + reward.gems end
	if reward.pet   then PetService.GrantPet(player, { name=reward.pet, rarity=reward.petRarity or "Common" }) end
	data.RedeemedCodes[code] = true
	return true, reward.label or "Redeemed!"
end

return CodeService
