-- StarPets: FusionService.lua
-- Place in: ServerScriptService > Server > FusionService (ModuleScript)
-- Combine 3 duplicate pets into ONE stronger pet (frees inventory + grants a fuse bonus).

local GameConfig  = require(game.ReplicatedStorage.Shared.GameConfig)
local DataManager = require(script.Parent.DataManager)

local FusionService = {}

local FUSE_COUNT = 3      -- pets consumed per fusion
local FUSE_BONUS = 1.25   -- combined power gets a +25% bonus

local function newUniqueId()
	return tostring(math.random(100000, 999999)) .. tostring(os.time()):sub(-4)
end

local function mutMult(id)
	local m = GameConfig.GetMutation and GameConfig.GetMutation(id)
	return (m and m.mult) or 1
end

-- eligible = owned, NOT equipped, NOT locked
local function eligibleByName(data)
	local equipped = {}
	for _, uid in ipairs(data.EquippedPets or {}) do equipped[uid] = true end
	local groups = {}
	for _, p in ipairs(data.Pets or {}) do
		if not p.locked and not equipped[p.uniqueId] then
			groups[p.name] = groups[p.name] or {}
			table.insert(groups[p.name], p)
		end
	end
	return groups
end

-- list of fusable pet-types (count >= FUSE_COUNT) for the UI
function FusionService.GetFusable(player)
	local data = DataManager.GetData(player); if not data then return { list = {}, need = FUSE_COUNT } end
	local groups = eligibleByName(data)
	local list = {}
	for name, pets in pairs(groups) do
		if #pets >= FUSE_COUNT then
			table.insert(list, { name = name, rarity = pets[1].rarity, count = #pets })
		end
	end
	table.sort(list, function(a, b) return a.count > b.count end)
	return { list = list, need = FUSE_COUNT, bonus = FUSE_BONUS }
end

-- fuse 3 eligible pets of the given name -> 1 stronger pet
-- returns ok, newPet | errString
function FusionService.FuseByName(player, name)
	local data = DataManager.GetData(player); if not data then return false, "no data" end
	local groups = eligibleByName(data)
	local pool = groups[name]
	if not pool or #pool < FUSE_COUNT then return false, "Need "..FUSE_COUNT.." spare "..tostring(name).."s" end

	-- consume the FUSE_COUNT WEAKEST copies (lowest fuse power), keep the strongest mutation among them
	table.sort(pool, function(a, b)
		return (a.fuseMult or 1) * mutMult(a.mutation) < (b.fuseMult or 1) * mutMult(b.mutation)
	end)
	local inputs = {}
	for i = 1, FUSE_COUNT do inputs[i] = pool[i] end

	local sumFuse, bestMut, bestMutScore, rarity = 0, nil, 0, name
	for _, p in ipairs(inputs) do
		sumFuse = sumFuse + (p.fuseMult or 1)
		rarity = p.rarity
		local ms = mutMult(p.mutation)
		if ms > bestMutScore then bestMutScore = ms; bestMut = p.mutation end
	end

	-- remove consumed pets from inventory
	local remove = {}
	for _, p in ipairs(inputs) do remove[p.uniqueId] = true end
	for i = #data.Pets, 1, -1 do
		if remove[data.Pets[i].uniqueId] then table.remove(data.Pets, i) end
	end

	local fused = {
		name     = name,
		rarity   = rarity,
		uniqueId = newUniqueId(),
		mutation = bestMut,
		fuseMult = sumFuse * FUSE_BONUS,
		fused    = true,
	}
	table.insert(data.Pets, fused)
	return true, fused
end

return FusionService
