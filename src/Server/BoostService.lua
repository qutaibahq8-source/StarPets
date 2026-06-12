-- StarPets: BoostService.lua
-- Place in: ServerScriptService > Server > BoostService (ModuleScript)

local GameConfig  = require(game.ReplicatedStorage.Shared.GameConfig)
local DataManager = require(script.Parent.DataManager)

local BoostService = {}
local function now() return os.time() end

local function defById(id)
	for _, b in ipairs(GameConfig.Boosts) do if b.id == id then return b end end
end

-- product of every active coin boost (1 if none)
function BoostService.GetCoinMult(data)
	if not data or not data.ActiveBoosts then return 1 end
	local m = 1
	for id, expire in pairs(data.ActiveBoosts) do
		if expire > now() then
			local d = defById(id); if d then m = m * d.mult end
		end
	end
	return m
end

function BoostService.GetState(player)
	local data = DataManager.GetData(player); if not data then return { boosts = {} } end
	data.ActiveBoosts = data.ActiveBoosts or {}
	local active = {}
	for id, expire in pairs(data.ActiveBoosts) do
		if expire > now() then active[id] = expire - now() end
	end
	return { boosts = GameConfig.Boosts, active = active }
end

-- returns ok, name|errString
function BoostService.Buy(player, id)
	local d = defById(id); if not d then return false, "Invalid boost" end
	local data = DataManager.GetData(player); if not data then return false, "no data" end
	if (data.Gems or 0) < d.cost then return false, "Not enough Gems" end
	data.Gems = data.Gems - d.cost
	data.ActiveBoosts = data.ActiveBoosts or {}
	local base = math.max(now(), data.ActiveBoosts[id] or 0)  -- stack if already active
	data.ActiveBoosts[id] = base + d.duration
	return true, d.name
end

return BoostService
