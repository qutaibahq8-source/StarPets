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

	-- A pet reward is checked BEFORE anything is given. It used to be granted
	-- last and its result ignored: with a full inventory the coins were paid,
	-- the code was spent, and the pet was simply never given. And its rarity
	-- came from the code entry, defaulting to Common, rather than from the
	-- species itself.
	local petCfg
	if reward.pet then
		for _, p in ipairs(GameConfig.Pets) do
			if p.name == reward.pet then petCfg = p break end
		end
		if not petCfg then return false, "This code's pet is no longer in the game" end
		local cap = GameConfig.Settings.MaxPetsInInventory or math.huge
		if #(data.Pets or {}) >= cap then
			return false, "Make room in your inventory first, then try again"
		end
	end

	if reward.coins then data.Coins = (data.Coins or 0) + reward.coins; data.TotalCoinsEarned = (data.TotalCoinsEarned or 0) + reward.coins end
	if reward.gems  then data.Gems  = (data.Gems  or 0) + reward.gems end
	if petCfg then PetService.GrantPet(player, { name = petCfg.name, rarity = petCfg.rarity }) end
	data.RedeemedCodes[code] = true
	return true, reward.label or "Redeemed!"
end

return CodeService
