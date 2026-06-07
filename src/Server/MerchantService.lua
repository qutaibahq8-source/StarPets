-- StarPets: MerchantService.lua
-- Place in: ServerScriptService > Server > MerchantService (ModuleScript)
-- Traveling merchant: appears on a cycle with rotating stock, then leaves.

local HttpService = game:GetService("HttpService")
local GameConfig  = require(game.ReplicatedStorage.Shared.GameConfig)
local DataManager = require(script.Parent.DataManager)

local MerchantService = {}
local cfg   = GameConfig.Merchant
local state = { active = false, stock = {}, changeAt = 0 }

local function now() return os.time() end

local function pickStock()
	local pool = {}
	for _, it in ipairs(GameConfig.MerchantPool) do table.insert(pool, it) end
	for i = #pool, 2, -1 do local j = math.random(i); pool[i], pool[j] = pool[j], pool[i] end
	local s = {}
	for i = 1, math.min(cfg.StockSize, #pool) do table.insert(s, pool[i]) end
	return s
end

function MerchantService.GetState()
	return {
		active = state.active,
		secondsLeft = math.max(0, state.changeAt - now()),
		stock = state.active and state.stock or nil,
	}
end

function MerchantService.Start(onArrive)
	task.spawn(function()
		while true do
			state.active = false; state.stock = {}; state.changeAt = now() + cfg.GapTime
			task.wait(cfg.GapTime)
			state.active = true; state.stock = pickStock(); state.changeAt = now() + cfg.StayTime
			if onArrive then pcall(onArrive) end
			task.wait(cfg.StayTime)
		end
	end)
end

function MerchantService.ForceSpawn()
	state.active = true; state.stock = pickStock(); state.changeAt = now() + cfg.StayTime
end
function MerchantService.ForceDespawn()
	state.active = false; state.stock = {}; state.changeAt = now() + cfg.GapTime
end

-- returns ok, label|errString
function MerchantService.Buy(player, index)
	if not state.active then return false, "The merchant is away" end
	local item = state.stock[index]
	if not item then return false, "No such item" end
	local data = DataManager.GetData(player); if not data then return false, "no data" end
	local bal = (item.cur == "Gems") and (data.Gems or 0) or (data.Coins or 0)
	if bal < item.cost then return false, "Not enough " .. item.cur end
	if item.cur == "Gems" then data.Gems = data.Gems - item.cost else data.Coins = data.Coins - item.cost end
	if item.kind == "pet" then
		table.insert(data.Pets, { name=item.name, rarity=item.rarity or "Common", uniqueId=HttpService:GenerateGUID(false) })
	elseif item.kind == "coins" then
		data.Coins = (data.Coins or 0) + item.amount; data.TotalCoinsEarned = (data.TotalCoinsEarned or 0) + item.amount
	elseif item.kind == "gems" then
		data.Gems = (data.Gems or 0) + item.amount
	elseif item.kind == "boost" then
		data[item.key] = true
	end
	return true, item.label or "Purchased!"
end

return MerchantService
