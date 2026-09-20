-- MysticPets: DataManager.lua
-- Place in: ServerScriptService > Server > DataManager (ModuleScript)
--
-- THE BUG THIS FILE EXISTS TO NEVER HAVE AGAIN
--
-- loadWithRetry returned nil in two completely different situations: a
-- genuinely new player, and five failed GetAsync calls in a row. LoadPlayer
-- treated both the same — it built a fresh default save and cached it. Sixty
-- seconds later the autosave loop wrote that default over the top of the real
-- record with SetAsync.
--
-- A player with ten million coins and two hundred pets who happened to join
-- during a DataStore incident was permanently wiped, silently, by their own
-- game. There is no undo for that and no way for them to prove it happened.
-- DataStore outages are not hypothetical and they hit every server at once, so
-- it is a whole-playerbase event rather than one unlucky person.
--
-- The rule that prevents it: DATA IS NEVER SAVED FOR A SESSION THAT DID NOT
-- LOAD CLEANLY. A failed load is a failure, not an empty inventory.

local DataStoreService = game:GetService("DataStoreService")
local Players          = game:GetService("Players")

local GameConfig = require(game.ReplicatedStorage.Shared.GameConfig)

local DataManager = {}

local PlayerStore = DataStoreService:GetDataStore("MysticPets_v1")
local Cache       = {}   -- userId -> data table
local Saving      = {}   -- userId -> true while a save is in flight
local Failed      = {}   -- userId -> true if the load failed; never save these
local Loaded      = {}   -- userId -> true once a load has completed cleanly

-- Shutdown gets about 30 seconds in total. Five attempts with doubling backoff
-- is 2+4+8+16+32 = 62 seconds for ONE player, and the loop is serial, so a
-- single failing save used to cost every player after it their data. Normal
-- saves can afford to be patient; a closing server cannot.
local NORMAL_ATTEMPTS, NORMAL_BACKOFF = 5, 2
local CLOSING_ATTEMPTS, CLOSING_BACKOFF = 3, 1
local closing = false

local function deepCopy(t)
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = (type(v) == "table") and deepCopy(v) or v
	end
	return copy
end

-- RECURSIVE, unlike the version this replaces. A shallow merge only fills in
-- top-level keys, so when a nested default gains a field — a new flag inside
-- Settings, a new counter inside Stats — every existing player is missing it
-- forever, and the first line of code to read it gets nil.
local function applyDefaults(data, default)
	default = default or GameConfig.DefaultData
	for key, value in pairs(default) do
		if data[key] == nil then
			data[key] = (type(value) == "table") and deepCopy(value) or value
		elseif type(value) == "table" and type(data[key]) == "table"
			and next(value) ~= nil and value[1] == nil then
			-- Only recurse into dictionaries. Arrays (Pets, EquippedPets) are
			-- the player's own content and must be left exactly as they are —
			-- merging defaults into those would inject phantom entries.
			applyDefaults(data[key], value)
		end
	end
	return data
end

-- A value of the wrong type is worse than a missing one: `data.Coins + 1` on a
-- string throws, and the throw lands in whatever gameplay code touched it. Bad
-- types come from old schema versions and from exploited writes. Repair to the
-- default rather than propagating.
local function coerce(data, default, path, report)
	for key, value in pairs(default) do
		local want, got = type(value), type(data[key])
		if data[key] ~= nil and want ~= got then
			table.insert(report, ("%s%s was %s, expected %s"):format(path, key, got, want))
			data[key] = (want == "table") and deepCopy(value) or value
		elseif want == "table" and got == "table" and value[1] == nil then
			coerce(data[key], value, path .. key .. ".", report)
		end
	end
	return data
end

local function loadWithRetry(userId)
	local data, ok, err
	for attempt = 1, 5 do
		ok, err = pcall(function()
			data = PlayerStore:GetAsync(tostring(userId))
		end)
		if ok then return true, data end
		warn(("[DataManager] load attempt %d failed for %s: %s")
			:format(attempt, userId, tostring(err)))
		task.wait(2 ^ attempt)
	end
	return false, nil, err
end

local function saveWithRetry(userId, data)
	-- THE TWO REFUSALS THAT MATTER.
	--
	-- A session whose load failed holds default data that is NOT this player's
	-- record. Writing it is the wipe. A session that never loaded at all is the
	-- same thing one step earlier.
	if Failed[userId] then
		warn(("[DataManager] refusing to save %s: their load failed, so the "
			.. "cached data is defaults and would overwrite their real save.")
			:format(userId))
		return false
	end
	if not Loaded[userId] then
		return false
	end

	-- WAIT for an in-flight save rather than returning. The old code returned
	-- immediately if one was running, and RemovePlayer cleared the cache the
	-- moment afterwards — so a player who left while the autosave was mid-flight
	-- lost everything earned since that autosave started.
	local waited = 0
	while Saving[userId] and waited < 10 do
		task.wait(0.1)
		waited = waited + 0.1
	end

	Saving[userId] = true
	local attempts = closing and CLOSING_ATTEMPTS or NORMAL_ATTEMPTS
	local backoff = closing and CLOSING_BACKOFF or NORMAL_BACKOFF
	for attempt = 1, attempts do
		local ok, err = pcall(function()
			PlayerStore:SetAsync(tostring(userId), data)
		end)
		if ok then
			Saving[userId] = false
			return true
		end
		warn(("[DataManager] save attempt %d failed for %s: %s")
			:format(attempt, userId, tostring(err)))
		if attempt < attempts then
			task.wait(backoff ^ attempt)
		end
	end
	Saving[userId] = false
	warn("[DataManager] ALL save attempts failed for " .. tostring(userId))
	return false
end

-- Returns data, err. A caller that ignores the second value behaves exactly as
-- before for a successful load, so this stays compatible with existing code —
-- but a caller that checks it can refuse to let the player play on data that is
-- not theirs.
function DataManager.LoadPlayer(player)
	local uid = player.UserId
	Failed[uid] = nil
	Loaded[uid] = nil

	local ok, raw, err = loadWithRetry(uid)
	if not ok then
		-- NOT a new player. Cache nothing, mark the session, and say so.
		Failed[uid] = true
		warn(("[DataManager] LOAD FAILED for %s (%s). Their data will NOT be "
			.. "touched and nothing will be saved for this session.")
			:format(player.Name, tostring(err)))
		return nil, err or "DataStore unavailable"
	end

	local data
	if raw then
		data = applyDefaults(raw)
		local report = {}
		coerce(data, GameConfig.DefaultData, "", report)
		if #report > 0 then
			warn(("[DataManager] repaired %d bad field(s) for %s: %s")
				:format(#report, player.Name, table.concat(report, ", ")))
		end
	else
		data = deepCopy(GameConfig.DefaultData)
		data.JoinTime = os.time()
	end

	Cache[uid] = data
	Loaded[uid] = true
	return data, nil
end

function DataManager.HasFailed(player)
	return Failed[player.UserId] == true
end

function DataManager.SavePlayer(player)
	local data = Cache[player.UserId]
	if not data then return false end
	return saveWithRetry(player.UserId, data)
end

function DataManager.GetData(player)
	return Cache[player.UserId]
end

function DataManager.SetData(player, key, value)
	local data = Cache[player.UserId]
	if data then data[key] = value end
end

function DataManager.IncrementData(player, key, amount)
	local data = Cache[player.UserId]
	if data and type(data[key]) == "number" then
		data[key] = data[key] + amount
	end
end

function DataManager.RemovePlayer(player)
	local uid = player.UserId
	local data = Cache[uid]
	if data then saveWithRetry(uid, data) end
	Cache[uid] = nil
	Saving[uid] = nil
	Failed[uid] = nil
	Loaded[uid] = nil
end

-- Autosave. Staggered rather than all-at-once: firing every player's save on
-- the same tick is what produces DataStore throttling, and throttling is what
-- produces the failed writes this file spends its length defending against.
task.spawn(function()
	while true do
		task.wait(GameConfig.Settings.DataSaveInterval)
		for userId, data in pairs(Cache) do
			local player = Players:GetPlayerByUserId(userId)
			if player then
				task.spawn(saveWithRetry, userId, data)
				task.wait(0.35)
			end
		end
	end
end)

-- Shutdown. In PARALLEL, with a shorter retry budget, and with a hard wait so
-- the server does not exit before the saves land. Serially, one failing player
-- used the entire allowance and everyone behind them lost their session.
game:BindToClose(function()
	closing = true
	local pending = 0
	for userId, data in pairs(Cache) do
		pending = pending + 1
		task.spawn(function()
			saveWithRetry(userId, data)
			pending = pending - 1
		end)
	end
	local waited = 0
	while pending > 0 and waited < 25 do
		task.wait(0.2)
		waited = waited + 0.2
	end
	if pending > 0 then
		warn(("[DataManager] shutdown ended with %d save(s) unfinished")
			:format(pending))
	end
end)

return DataManager
