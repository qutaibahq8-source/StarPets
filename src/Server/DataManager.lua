-- MysticPets: DataManager.lua
-- Place in: ServerScriptService > Server > DataManager (ModuleScript)

local DataStoreService = game:GetService("DataStoreService")
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")

local GameConfig = require(game.ReplicatedStorage.Shared.GameConfig)

local DataManager = {}

local PlayerStore = DataStoreService:GetDataStore("MysticPets_v1")
local Cache       = {}   -- player.UserId -> data table
local Saving      = {}   -- player.UserId -> bool (lock)

local function deepCopy(t)
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = (type(v) == "table") and deepCopy(v) or v
	end
	return copy
end

local function applyDefaults(data)
	local default = GameConfig.DefaultData
	for key, value in pairs(default) do
		if data[key] == nil then
			data[key] = (type(value) == "table") and deepCopy(value) or value
		end
	end
	return data
end

local function loadWithRetry(userId)
	local data, success, err
	for attempt = 1, 5 do
		success, err = pcall(function()
			data = PlayerStore:GetAsync(tostring(userId))
		end)
		if success then break end
		warn("[DataManager] Load attempt " .. attempt .. " failed for " .. userId .. ": " .. tostring(err))
		task.wait(2 ^ attempt)
	end
	if not success then
		warn("[DataManager] All load attempts failed for " .. userId .. ". Using defaults.")
	end
	return data
end

local function saveWithRetry(userId, data)
	if Saving[userId] then return end
	Saving[userId] = true
	for attempt = 1, 5 do
		local success, err = pcall(function()
			PlayerStore:SetAsync(tostring(userId), data)
		end)
		if success then
			Saving[userId] = false
			return true
		end
		warn("[DataManager] Save attempt " .. attempt .. " failed for " .. userId .. ": " .. tostring(err))
		task.wait(2 ^ attempt)
	end
	Saving[userId] = false
	warn("[DataManager] All save attempts failed for " .. userId)
	return false
end

function DataManager.LoadPlayer(player)
	local raw = loadWithRetry(player.UserId)
	local data
	if raw then
		data = applyDefaults(raw)
	else
		data = deepCopy(GameConfig.DefaultData)
		data.JoinTime = os.time()
	end
	Cache[player.UserId] = data
	return data
end

function DataManager.SavePlayer(player)
	local data = Cache[player.UserId]
	if not data then return end
	return saveWithRetry(player.UserId, data)
end

function DataManager.GetData(player)
	return Cache[player.UserId]
end

function DataManager.SetData(player, key, value)
	local data = Cache[player.UserId]
	if data then
		data[key] = value
	end
end

function DataManager.IncrementData(player, key, amount)
	local data = Cache[player.UserId]
	if data and type(data[key]) == "number" then
		data[key] = data[key] + amount
	end
end

function DataManager.RemovePlayer(player)
	local data = Cache[player.UserId]
	if data then
		saveWithRetry(player.UserId, data)
	end
	Cache[player.UserId] = nil
	Saving[player.UserId] = nil
end

-- Auto-save loop
task.spawn(function()
	while true do
		task.wait(GameConfig.Settings.DataSaveInterval)
		for userId, data in pairs(Cache) do
			local player = Players:GetPlayerByUserId(userId)
			if player then
				saveWithRetry(userId, data)
			end
		end
	end
end)

-- Save on server close
game:BindToClose(function()
	for userId, data in pairs(Cache) do
		saveWithRetry(userId, data)
	end
end)

return DataManager
