-- StarPets: PlaytimeService.lua
-- Place in: ServerScriptService > Server > PlaytimeService (ModuleScript)
-- Escalating session rewards — the longer a player stays, the more they earn.
-- Per-session (resets on rejoin) so it rewards both long sessions AND returning.

local Players      = game:GetService("Players")
local GameConfig   = require(game.ReplicatedStorage.Shared.GameConfig)
local DataManager  = require(script.Parent.DataManager)

local PlaytimeService = {}

local joinAt  = {}   -- [userId] = os.time() when this session started
local claimed = {}   -- [userId] = { [index] = true }

local function reset(p)
	joinAt[p.UserId]  = os.time()
	claimed[p.UserId] = {}
end

Players.PlayerAdded:Connect(reset)
Players.PlayerRemoving:Connect(function(p)
	joinAt[p.UserId]  = nil
	claimed[p.UserId] = nil
end)
for _, p in ipairs(Players:GetPlayers()) do reset(p) end  -- already-joined (hot reload)

local function elapsedFor(player)
	return os.time() - (joinAt[player.UserId] or os.time())
end

function PlaytimeService.GetState(player)
	local elapsed = elapsedFor(player)
	local cl = claimed[player.UserId] or {}
	local rewards = {}
	for i, r in ipairs(GameConfig.PlaytimeRewards) do
		rewards[i] = {
			seconds = r.seconds, coins = r.coins, gems = r.gems, boost = r.boost,
			claimed = cl[i] == true,
			ready   = elapsed >= r.seconds,
		}
	end
	return { elapsed = elapsed, rewards = rewards }
end

-- returns ok, reward|errString
function PlaytimeService.Claim(player, index)
	local r = GameConfig.PlaytimeRewards[index]
	if not r then return false, "Invalid reward" end
	if elapsedFor(player) < r.seconds then return false, "Keep playing!" end
	claimed[player.UserId] = claimed[player.UserId] or {}
	if claimed[player.UserId][index] then return false, "Already claimed" end
	local data = DataManager.GetData(player)
	if not data then return false, "no data" end

	if r.coins then
		data.Coins = (data.Coins or 0) + r.coins
		data.TotalCoinsEarned = (data.TotalCoinsEarned or 0) + r.coins
	end
	if r.gems then data.Gems = (data.Gems or 0) + r.gems end
	if r.boost then
		local dur = 600
		for _, b in ipairs(GameConfig.Boosts or {}) do if b.id == r.boost then dur = b.duration end end
		data.ActiveBoosts = data.ActiveBoosts or {}
		data.ActiveBoosts[r.boost] = math.max(os.time(), data.ActiveBoosts[r.boost] or 0) + dur
	end
	claimed[player.UserId][index] = true
	return true, r
end

return PlaytimeService
