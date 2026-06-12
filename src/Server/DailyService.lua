-- StarPets: DailyService.lua
-- Place in: ServerScriptService > Server > DailyService (ModuleScript)

local GameConfig  = require(game.ReplicatedStorage.Shared.GameConfig)
local DataManager = require(script.Parent.DataManager)

local DailyService = {}
local DAY   = 20 * 3600   -- claimable again after 20h
local RESET = 40 * 3600   -- streak resets if you miss > 40h

local function now() return os.time() end

function DailyService.GetState(player)
	local data = DataManager.GetData(player); if not data then return { ready=false } end
	local last = data.LastDailyClaim or 0
	local since = now() - last
	local ready = (last == 0) or (since >= DAY)
	local streak = data.DailyStreak or 0
	if last ~= 0 and since >= RESET then streak = 0 end
	local nextDay = (streak % #GameConfig.DailyRewards) + 1
	return {
		ready = ready,
		secondsLeft = ready and 0 or math.max(0, DAY - since),
		streak = streak,
		nextDay = nextDay,
		rewards = GameConfig.DailyRewards,
	}
end

-- returns ok, dayNumber|errString
function DailyService.Claim(player)
	local data = DataManager.GetData(player); if not data then return false, "no data" end
	local last = data.LastDailyClaim or 0
	local since = now() - last
	if last ~= 0 and since < DAY then return false, "Not ready yet" end
	local streak = data.DailyStreak or 0
	if last ~= 0 and since >= RESET then streak = 0 end
	streak = (streak % #GameConfig.DailyRewards) + 1
	local r = GameConfig.DailyRewards[streak] or {}
	if r.coins then data.Coins = (data.Coins or 0) + r.coins; data.TotalCoinsEarned = (data.TotalCoinsEarned or 0) + r.coins end
	if r.gems  then data.Gems  = (data.Gems  or 0) + r.gems end
	data.DailyStreak = streak
	data.LastDailyClaim = now()
	return true, streak
end

return DailyService
