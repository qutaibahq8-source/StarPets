-- StarPets: EventService.lua
-- Place in: ServerScriptService > Server > EventService (ModuleScript)
-- Limited-time events: admin toggles one on; players earn event tokens
-- (passively while it runs) and spend them in the event shop.

local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local GameConfig  = require(game.ReplicatedStorage.Shared.GameConfig)
local DataManager = require(script.Parent.DataManager)

local EventService = {}
local state = { active = false, id = nil }

local function def() return state.id and GameConfig.Events[state.id] or nil end

function EventService.GetState(player)
	local d = def()
	if not state.active or not d then return { active = false } end
	local data = player and DataManager.GetData(player)
	return {
		active = true,
		name = d.name, tokenName = d.tokenName, tokenIcon = d.tokenIcon,
		tokens = (data and data.EventTokens) or 0,
		shop = d.shop,
	}
end

function EventService.Start(id)
	if not GameConfig.Events[id] then return false end
	state.active = true; state.id = id
	return true
end
function EventService.Stop()
	state.active = false
end
function EventService.IsActive() return state.active end

-- passive token trickle while an event runs (scales with equipped pets)
function EventService.Init()
	task.spawn(function()
		while true do
			task.wait(3)
			if state.active then
				for _, p in ipairs(Players:GetPlayers()) do
					local data = DataManager.GetData(p)
					if data then
						local eq = #(data.EquippedPets or {})
						data.EventTokens = (data.EventTokens or 0) + math.max(1, eq)
					end
				end
			end
		end
	end)
end

-- returns ok, label|errString
function EventService.Buy(player, index)
	local d = def()
	if not state.active or not d then return false, "No event running" end
	local item = d.shop[index]
	if not item then return false, "No such item" end
	local data = DataManager.GetData(player); if not data then return false, "no data" end
	if (data.EventTokens or 0) < item.cost then return false, "Not enough " .. d.tokenName end
	data.EventTokens = data.EventTokens - item.cost
	if item.kind == "pet" then
		table.insert(data.Pets, { name=item.name, rarity=item.rarity or "Common", uniqueId=HttpService:GenerateGUID(false) })
	elseif item.kind == "coins" then
		data.Coins = (data.Coins or 0) + item.amount; data.TotalCoinsEarned = (data.TotalCoinsEarned or 0) + item.amount
	elseif item.kind == "gems" then
		data.Gems = (data.Gems or 0) + item.amount
	end
	return true, item.label or "Purchased!"
end

return EventService
