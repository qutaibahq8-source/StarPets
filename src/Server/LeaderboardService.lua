-- MysticPets: LeaderboardService.lua
-- Place in: ServerScriptService > Server > LeaderboardService (ModuleScript)

local DataStoreService = game:GetService("DataStoreService")
local Players          = game:GetService("Players")
local GameConfig       = require(game.ReplicatedStorage.Shared.GameConfig)
local DataManager      = require(script.Parent.DataManager)

local LeaderboardService = {}

-- OrderedDataStores for each category
local Stores = {
	Coins = DataStoreService:GetOrderedDataStore("MysticPets_LB_Coins_v1"),
	Pets  = DataStoreService:GetOrderedDataStore("MysticPets_LB_Pets_v1"),
	Rebirths = DataStoreService:GetOrderedDataStore("MysticPets_LB_Rebirths_v1"),
}

local CachedBoards = {
	Coins    = {},
	Pets     = {},
	Rebirths = {},
}

-- ============================================================
-- UPDATE A PLAYER'S SCORE
-- ============================================================
function LeaderboardService.UpdatePlayer(player)
	local data = DataManager.GetData(player)
	if not data then return end

	local userId = tostring(player.UserId)

	pcall(function()
		Stores.Coins:SetAsync(userId, math.floor(data.TotalCoinsEarned or 0))
	end)
	pcall(function()
		Stores.Pets:SetAsync(userId, #(data.Pets or {}))
	end)
	pcall(function()
		Stores.Rebirths:SetAsync(userId, data.Rebirths or 0)
	end)
end

-- ============================================================
-- FETCH TOP 10
-- ============================================================
local function fetchTop(store, count)
	local results = {}
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, count)
	end)
	if not ok then return results end

	local ok2, data = pcall(function()
		return pages:GetCurrentPage()
	end)
	if not ok2 then return results end

	for rank, entry in ipairs(data) do
		local userId  = tonumber(entry.key)
		local score   = entry.value
		local name    = "[Unknown]"
		pcall(function()
			name = game:GetService("Players"):GetNameFromUserIdAsync(userId)
		end)
		table.insert(results, { rank=rank, name=name, score=score, userId=userId })
	end
	return results
end

function LeaderboardService.GetTop(category, count)
	count = count or 10
	local store = Stores[category]
	if not store then return {} end
	return fetchTop(store, count)
end

-- ============================================================
-- CACHED BOARDS  (refresh every 60s)
-- ============================================================
task.spawn(function()
	while true do
		for category, store in pairs(Stores) do
			local ok, result = pcall(fetchTop, store, 10)
			if ok then CachedBoards[category] = result end
			task.wait(1)
		end
		task.wait(57)
	end
end)

function LeaderboardService.GetCached(category)
	return CachedBoards[category] or {}
end

-- ============================================================
-- TITLE CALCULATOR
-- ============================================================
function LeaderboardService.GetTitle(data)
	local best = GameConfig.Titles[1]  -- default "Rookie"
	for _, titleDef in ipairs(GameConfig.Titles) do
		local ok, result = pcall(titleDef.req, data)
		if ok and result then
			best = titleDef
		end
	end
	return best
end

-- Auto-update all players every 90s
task.spawn(function()
	while true do
		task.wait(90)
		for _, player in ipairs(Players:GetPlayers()) do
			pcall(LeaderboardService.UpdatePlayer, player)
		end
	end
end)

return LeaderboardService
