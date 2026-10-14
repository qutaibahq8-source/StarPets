-- StarPets: LevelService.lua
-- Place in: ServerScriptService > Server > LevelService (ModuleScript)
--
-- Player experience. Everything that grants XP calls Add, here, on the server;
-- the client is only ever shown the result. XP is lifetime: rebirth resets
-- what a player owns, not what they have done.

local GameConfig  = require(game:GetService("ReplicatedStorage").Shared.GameConfig)
local DataManager = require(script.Parent.DataManager)

local LevelService = {}
local notify = nil

-- GameServer hands over how to tell a player something, once its remotes exist.
function LevelService.SetNotifier(fn)
	notify = fn
end

-- Add XP. Returns the level after, and the level before.
function LevelService.Add(player, amount)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then return nil end
	local data = DataManager.GetData(player)
	if not data then return nil end
	local before = GameConfig.LevelFromXP(data.XP)
	data.XP = (tonumber(data.XP) or 0) + amount
	local after = GameConfig.LevelFromXP(data.XP)
	if after > before and notify then
		local bonus = math.floor((after - 1) * GameConfig.Levels.coinBonus * 100 + 0.5)
		local extra = ""
		if before < GameConfig.AutoHatch.level and after >= GameConfig.AutoHatch.level then
			extra = " Auto Hatch is unlocked!"
		end
		notify(player, "success", ("⭐ Level %d! Your pets earn +%d%% coins.%s"):format(after, bonus, extra))
	end
	return after, before
end

-- XP for an egg: eggs further down the list (pricier, later worlds) give more.
function LevelService.ForHatch(eggId, count)
	local R = GameConfig.XPRewards
	for i, egg in ipairs(GameConfig.Eggs) do
		if egg.id == eggId then
			return (R.hatchBase + R.hatchPerTier * (i - 1)) * (count or 1)
		end
	end
	return R.hatchBase * (count or 1)
end

-- XP for a world: the Forest is tier 1.
function LevelService.ForWorld(areaId)
	for i, a in ipairs(GameConfig.Areas) do
		if a.id == areaId then return GameConfig.XPRewards.worldPerTier * (i - 1) end
	end
	return 0
end

return LevelService
