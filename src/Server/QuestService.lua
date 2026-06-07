-- StarPets: QuestService.lua
-- Place in: ServerScriptService > Server > QuestService (ModuleScript)
-- Quest progress is computed from existing player stats (no event hooks
-- needed), and rewards are granted once on claim.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")
local GameConfig        = require(game.ReplicatedStorage.Shared.GameConfig)
local DataManager       = require(script.Parent.DataManager)

local QuestService = {}

local function progress(data, q)
	if q.type == "hatch"   then return data.EggsHatched or 0
	elseif q.type == "coins"   then return math.floor(data.TotalCoinsEarned or 0)
	elseif q.type == "areas"   then return math.max(0, #(data.UnlockedAreas or {}) - 1)
	elseif q.type == "rebirth" then return data.Rebirths or 0
	elseif q.type == "equip"   then return #(data.EquippedPets or {})
	end
	return 0
end

local function ensure(data)
	data.Quests = data.Quests or { claimed = {} }
	data.Quests.claimed = data.Quests.claimed or {}
	return data.Quests
end

function QuestService.GetAll(player)
	local data = DataManager.GetData(player); if not data then return {} end
	local q = ensure(data)
	local out = {}
	for _, def in ipairs(GameConfig.Quests) do
		local p = progress(data, def)
		table.insert(out, {
			id = def.id, name = def.name, desc = def.desc, goal = def.goal,
			progress = math.min(p, def.goal), done = p >= def.goal,
			claimed = q.claimed[def.id] == true, reward = def.reward,
		})
	end
	return out
end

-- returns ok, questDef|errString
function QuestService.Claim(player, id)
	local data = DataManager.GetData(player); if not data then return false, "no data" end
	local q = ensure(data)
	local def; for _, d in ipairs(GameConfig.Quests) do if d.id == id then def = d break end end
	if not def then return false, "unknown quest" end
	if q.claimed[id] then return false, "already claimed" end
	if progress(data, def) < def.goal then return false, "not complete yet" end
	local r = def.reward or {}
	if r.coins then data.Coins = (data.Coins or 0) + r.coins; data.TotalCoinsEarned = (data.TotalCoinsEarned or 0) + r.coins end
	if r.gems  then data.Gems  = (data.Gems  or 0) + r.gems end
	if r.pet   then table.insert(data.Pets, { name=r.pet, rarity=r.petRarity or "Common", uniqueId=HttpService:GenerateGUID(false) }) end
	q.claimed[id] = true
	return true, def
end

-- admin helpers
function QuestService.ClaimAll(player)
	for _, def in ipairs(GameConfig.Quests) do pcall(QuestService.Claim, player, def.id) end
end
function QuestService.Reset(player)
	local data = DataManager.GetData(player); if data then ensure(data).claimed = {} end
end

return QuestService
