-- StarPets: SpinService.lua
-- Place in: ServerScriptService > Server > SpinService (ModuleScript)
-- Lucky Spin Wheel — 1 free spin per 12h, or pay gems. Weighted prizes.

local GameConfig  = require(game.ReplicatedStorage.Shared.GameConfig)
local DataManager = require(script.Parent.DataManager)

local SpinService = {}

local function cfg() return GameConfig.SpinWheel end

function SpinService.GetState(player)
	local data = DataManager.GetData(player)
	local c = cfg()
	local last = (data and data.LastFreeSpin) or 0
	local sinceFree = os.time() - last
	return {
		prizes      = c.prizes,
		cost        = c.cost,
		freeReady   = sinceFree >= c.freeCooldown,
		nextFreeIn  = math.max(0, c.freeCooldown - sinceFree),
	}
end

-- weighted random index into prizes
local function rollIndex()
	local prizes = cfg().prizes
	local total = 0
	for _, p in ipairs(prizes) do total = total + (p.weight or 1) end
	local r = math.random() * total
	local acc = 0
	for i, p in ipairs(prizes) do
		acc = acc + (p.weight or 1)
		if r <= acc then return i end
	end
	return #prizes
end

-- returns ok, { index, prize } | errString
function SpinService.Spin(player, useFree)
	local data = DataManager.GetData(player); if not data then return false, "no data" end
	local c = cfg()
	if useFree then
		if (os.time() - (data.LastFreeSpin or 0)) < c.freeCooldown then return false, "Free spin not ready" end
		data.LastFreeSpin = os.time()
	else
		if (data.Gems or 0) < c.cost then return false, "Not enough Gems" end
		data.Gems = data.Gems - c.cost
	end

	local idx = rollIndex()
	local prize = c.prizes[idx]
	if prize.coins then
		data.Coins = (data.Coins or 0) + prize.coins
		data.TotalCoinsEarned = (data.TotalCoinsEarned or 0) + prize.coins
	end
	if prize.gems then data.Gems = (data.Gems or 0) + prize.gems end
	if prize.boost then
		local dur = 600
		for _, b in ipairs(GameConfig.Boosts or {}) do if b.id == prize.boost then dur = b.duration end end
		data.ActiveBoosts = data.ActiveBoosts or {}
		data.ActiveBoosts[prize.boost] = math.max(os.time(), data.ActiveBoosts[prize.boost] or 0) + dur
	end
	return true, { index = idx, prize = prize }
end

return SpinService
