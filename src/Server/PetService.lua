-- MysticPets: PetService.lua
-- Place in: ServerScriptService > Server > PetService (ModuleScript)

local TweenService = game:GetService("TweenService")

local GameConfig  = require(game.ReplicatedStorage.Shared.GameConfig)
local DataManager = require(script.Parent.DataManager)
-- Shared, not Server: the client builds the same models for the hatch reveal.
local PetModels   = require(game.ReplicatedStorage.Shared.PetModels)
local BoostService = require(script.Parent.BoostService)

local PetService   = {}
local PetsFolder   = nil      -- Workspace.Pets
local ActiveModels = {}       -- [player.UserId] -> { [uniqueId] -> Model }

-- Lookup helper: pet name -> config entry
local PetLookup = {}
for _, petData in ipairs(GameConfig.Pets) do
	PetLookup[petData.name] = petData
end

-- The geometric builder that used to live here was never called: every model
-- comes from PetModels.Build. It was 110 lines of dead code carrying a
-- PointLight, Neon eyes and a ParticleEmitter per pet — the exact things being
-- removed from the live builder — so leaving it invited someone to "restore"
-- it. Deleted.

-- ============================================================
-- POSITION HELPERS
-- ============================================================
local function getFollowOffset(index, total)
	-- Arrange pets in a semi-circle behind player
	local angle = math.pi + ((index - 1) - (total - 1) / 2) * 0.6
	local radius = 4 + math.floor((index - 1) / 5) * 2
	return Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
end

local function updateModelCFrames(model, cf, size)
	-- The model is fully assembled (all parts positioned relative to the root),
	-- so move it as one rigid unit. PivotTo keeps every part's offset intact.
	if model.PrimaryPart then
		model:PivotTo(cf)
		return
	end
	local body = model:FindFirstChild("HumanoidRootPart")
	if body then body.CFrame = cf end
end

-- ============================================================
-- SPAWN / DESPAWN
-- ============================================================
function PetService.Init()
	PetsFolder = Instance.new("Folder")
	PetsFolder.Name = "Pets"
	PetsFolder.Parent = workspace

	-- No follow loop here. Pets are placed once, when they spawn, and every
	-- client moves them from then on (PetFollow.client.lua).
	--
	-- This used to PivotTo every equipped pet on every Heartbeat. Each pet is
	-- an anchored model of up to thirty parts and every part's CFrame was
	-- replicated to every player, sixty times a second — over fifty thousand
	-- updates a second to each client on a busy server. Roblox throttles that,
	-- so pets moved late and in steps, and a player's own pets trailed them by
	-- a full round trip.
end

function PetService.SpawnPet(player, petEntry, slotIndex, totalSlots)
	local userId = player.UserId
	if not ActiveModels[userId] then
		ActiveModels[userId] = {}
	end

	if ActiveModels[userId][petEntry.uniqueId] then return end

	local petData = PetLookup[petEntry.name]
	if not petData then
		warn("[PetService] Unknown pet: " .. petEntry.name)
		return
	end

	local rarityInfo = GameConfig.Rarities[petData.rarity]
	local mut = GameConfig.GetMutation and GameConfig.GetMutation(petEntry.mutation)
	local model = PetModels.Build(petData, petEntry.uniqueId, rarityInfo, mut)

	-- Placed once, at its spot behind the player, and never moved by the server
	-- again; clients take it from here. Placed where it belongs rather than
	-- inside the player, so the first frame anyone sees of it is already right.
	local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if rootPart then
		local _, yaw = rootPart.CFrame:ToOrientation()
		local spot = rootPart.Position + getFollowOffset(slotIndex or 1, math.max(totalSlots or 1, 1))
		updateModelCFrames(model, CFrame.new(spot) * CFrame.Angles(0, yaw, 0), petData.size or 1)
	end

	local folder = PetsFolder:FindFirstChild(tostring(userId))
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = tostring(userId)
		folder.Parent = PetsFolder
	end
	model.Parent = folder

	ActiveModels[userId][petEntry.uniqueId] = model
end

function PetService.DespawnPet(player, uniqueId)
	local userId = player.UserId
	if not ActiveModels[userId] then return end
	local model = ActiveModels[userId][uniqueId]
	if model then
		model:Destroy()
		ActiveModels[userId][uniqueId] = nil
	end
end

function PetService.DespawnAllPets(player)
	local userId = player.UserId
	if not ActiveModels[userId] then return end
	for uniqueId, model in pairs(ActiveModels[userId]) do
		model:Destroy()
	end
	-- nil, not an empty table.
	--
	-- This runs on PlayerRemoving, and leaving an empty table behind meant the
	-- entry stayed in ActiveModels for the life of the server. When the server
	-- still ran the follow loop, that loop walked this table sixty times a
	-- second and called GetPlayerByUserId on every key, so after a few hundred
	-- sessions it was doing tens of thousands of lookups a second for players
	-- who left hours ago. The loop is gone; a table that only grows is still
	-- a leak.
	ActiveModels[userId] = nil
	local folder = PetsFolder:FindFirstChild(tostring(userId))
	if folder then folder:Destroy() end
end

-- How many players and models the follow loop is actually working on. Useful
-- from the admin panel, and it is what makes the leak above testable at all:
-- ActiveModels is a local, so without this the only way to see it grow is to
-- watch the server slow down.
function PetService.ActiveCounts()
	local players, models = 0, 0
	for _, set in pairs(ActiveModels) do
		players = players + 1
		for _ in pairs(set) do models = models + 1 end
	end
	return players, models
end

-- ============================================================
-- EQUIP / UNEQUIP (updates data + models)
-- ============================================================
function PetService.EquipPet(player, uniqueId)
	local data = DataManager.GetData(player)
	if not data then return false, "No data" end

	local maxSlots = data.GP_PetSlots and GameConfig.Settings.VIPPetSlots or GameConfig.Settings.DefaultPetSlots
	if #data.EquippedPets >= maxSlots then
		return false, "Pet slots full"
	end

	for _, id in ipairs(data.EquippedPets) do
		if id == uniqueId then return false, "Already equipped" end
	end

	-- Find in inventory
	local petEntry = nil
	for _, pet in ipairs(data.Pets) do
		if pet.uniqueId == uniqueId then
			petEntry = pet
			break
		end
	end
	if not petEntry then return false, "Pet not found" end

	table.insert(data.EquippedPets, uniqueId)
	PetService.SpawnPet(player, petEntry, #data.EquippedPets, #data.EquippedPets)
	return true
end

function PetService.UnequipPet(player, uniqueId)
	local data = DataManager.GetData(player)
	if not data then return false end

	for i, id in ipairs(data.EquippedPets) do
		if id == uniqueId then
			table.remove(data.EquippedPets, i)
			PetService.DespawnPet(player, uniqueId)
			return true
		end
	end
	return false
end

-- ============================================================
-- PASSIVE INCOME
-- ============================================================
function PetService.GetPlayerIncome(player)
	local data = DataManager.GetData(player)
	if not data then return 0, 0 end

	local totalCoinMult = 0
	local totalGemMult  = 0

	for _, uniqueId in ipairs(data.EquippedPets) do
		for _, pet in ipairs(data.Pets) do
			if pet.uniqueId == uniqueId then
				local petData = PetLookup[pet.name]
				if petData then
					local mut = GameConfig.GetMutation and GameConfig.GetMutation(pet.mutation)
					local mm = (mut and mut.mult) or 1
					local fm = pet.fuseMult or 1
					totalCoinMult = totalCoinMult + petData.coinMult * mm * fm
					totalGemMult  = totalGemMult  + petData.gemMult * mm * fm
				end
				break
			end
		end
	end

	local rebirthMult = data.RebirthMultiplier or 1
	local coinBoost   = (data.GP_2xCoins and 2 or 1)
	local gemBoost    = (data.GP_VIP and GameConfig.Settings.VIPGemMultiplier or 1)

	local coins = math.floor(totalCoinMult * rebirthMult * coinBoost * BoostService.GetCoinMult(data))
	local gems  = math.floor(totalGemMult  * rebirthMult * gemBoost  * 0.01) -- gems are rare

	return coins, gems
end

-- Restore pets on rejoin
function PetService.RestoreEquipped(player)
	local data = DataManager.GetData(player)
	if not data then return end
	for i, uniqueId in ipairs(data.EquippedPets) do
		for _, pet in ipairs(data.Pets) do
			if pet.uniqueId == uniqueId then
				PetService.SpawnPet(player, pet, i, #data.EquippedPets)
				break
			end
		end
	end
end

-- ============================================================
-- QUALITY OF LIFE
-- ============================================================
function PetService.EquipBest(player)
	local data = DataManager.GetData(player); if not data then return end
	local slots = data.GP_PetSlots and GameConfig.Settings.VIPPetSlots or GameConfig.Settings.DefaultPetSlots
	local scored = {}
	for _, pet in ipairs(data.Pets) do
		local pd = PetLookup[pet.name]
		local mut = GameConfig.GetMutation and GameConfig.GetMutation(pet.mutation)
		local score = (pd and pd.coinMult or 0) * ((mut and mut.mult) or 1) * (pet.fuseMult or 1)
		table.insert(scored, { uid = pet.uniqueId, score = score })
	end
	table.sort(scored, function(a, b) return a.score > b.score end)
	PetService.DespawnAllPets(player)
	data.EquippedPets = {}
	for i = 1, math.min(slots, #scored) do table.insert(data.EquippedPets, scored[i].uid) end
	PetService.RestoreEquipped(player)
end

function PetService.DeleteByRarity(player, rarity)
	local data = DataManager.GetData(player); if not data then return 0 end
	local equipped = {}
	for _, uid in ipairs(data.EquippedPets or {}) do equipped[uid] = true end
	local removed = 0
	for i = #data.Pets, 1, -1 do
		local p = data.Pets[i]
		if p.rarity == rarity and not p.locked and not equipped[p.uniqueId] then
			table.remove(data.Pets, i); removed = removed + 1
		end
	end
	return removed
end

function PetService.ToggleLock(player, uid)
	local data = DataManager.GetData(player); if not data then return end
	for _, p in ipairs(data.Pets) do
		if p.uniqueId == uid then p.locked = not p.locked; return p.locked end
	end
end

-- ============================================================
-- THE ONE WAY A PET ENTERS AN INVENTORY
-- ============================================================
-- There were ELEVEN places that did `table.insert(data.Pets, ...)` — eggs,
-- fusion, codes, events, the merchant, quests, gamepasses, trading and two
-- admin commands — spread across nine files. Two things went wrong because of
-- that, and both are the kind of thing a spread-out rule always produces.
--
-- ONE: the inventory cap was enforced in exactly ONE of them. EggService
-- checked MaxPetsInInventory; every other path let a player go straight past
-- it. A hundred pets is a balance number and also a performance one, since
-- each equipped pet is a model the server replicates.
--
-- TWO: the Pet Index counted what you CURRENTLY OWN. Fuse three pets and the
-- species vanishes from your collection; trade it away, same; delete it, same.
-- A collection record that forgets what you collected is not a collection
-- record — and there was nowhere to write "seen it" even if you wanted to,
-- because nothing sat between a pet and the inventory.
--
-- So: one function. Everything goes through here.
local function recordDiscovery(data, name)
	if not name then return end
	data.Discovered = data.Discovered or {}
	if data.Discovered[name] == nil then
		data.Discovered[name] = true
		return true          -- newly discovered, for the "first time!" banner
	end
	return false
end

PetService.RecordDiscovery = recordDiscovery

-- Grants a pet. Returns pet, isNewSpecies — or nil, reason if it was refused.
--
-- `force` skips the cap, and exists for exactly one case: a pet the player has
-- already paid for or already owns arriving back (a trade the server has
-- already validated, a gamepass re-grant). Refusing those would destroy the
-- item rather than protect the player.
-- Before anything is paid for a pet, or a reward that includes one is marked
-- as given: is it a real species, and is there room for it? Returns the
-- species' config, or nil and what to tell the player.
--
-- Every shop used to charge first and grant after, ignoring the result. With a
-- full inventory the player paid and got nothing. Worse, the merchant and the
-- event shops were selling pets that were no longer in the game at all —
-- names left over from before the roster was replaced — and GrantPet took
-- them anyway: up to 12,000 gems for a pet with no model, no earnings and no
-- place in the Index.
function PetService.CanReceive(player, name)
	local data = DataManager.GetData(player)
	if not data then return nil, "no data" end
	local species = PetLookup[name]
	if not species then return nil, "That pet is no longer in the game" end
	local cap = GameConfig.Settings.MaxPetsInInventory or math.huge
	if #(data.Pets or {}) >= cap then return nil, "Make room in your inventory first" end
	return species
end

function PetService.Species(name)
	return PetLookup[name]
end

function PetService.GrantPet(player, pet, force)
	local data = DataManager.GetData(player)
	if not data then return nil, "no data" end
	if type(pet) ~= "table" or not pet.name then return nil, "bad pet" end

	data.Pets = data.Pets or {}
	local cap = GameConfig.Settings.MaxPetsInInventory or math.huge
	if not force and #data.Pets >= cap then
		return nil, ("Pet inventory full (max %d)"):format(cap)
	end

	if not pet.uniqueId then
		pet.uniqueId = game:GetService("HttpService"):GenerateGUID(false)
	end
	local isNew = recordDiscovery(data, pet.name)
	table.insert(data.Pets, pet)
	return pet, isNew
end

-- How many distinct species this player has ever owned. Reads the permanent
-- record first and falls back to the live inventory for saves made before
-- Discovered existed, so nobody's collection appears to reset on update.
function PetService.DiscoveredCount(data)
	if not data then return 0 end
	local seen = {}
	for name in pairs(data.Discovered or {}) do seen[name] = true end
	for _, p in ipairs(data.Pets or {}) do
		if p.name then seen[p.name] = true end
	end
	local n = 0
	for _ in pairs(seen) do n = n + 1 end
	return n
end

-- Backfill for existing saves: everything currently held counts as discovered.
function PetService.BackfillDiscovery(data)
	if not data then return 0 end
	local added = 0
	for _, p in ipairs(data.Pets or {}) do
		if recordDiscovery(data, p.name) then added = added + 1 end
	end
	return added
end

return PetService
