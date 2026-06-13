-- MysticPets: PetService.lua
-- Place in: ServerScriptService > Server > PetService (ModuleScript)

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameConfig  = require(game.ReplicatedStorage.Shared.GameConfig)
local DataManager = require(script.Parent.DataManager)
local PetModels   = require(script.Parent.PetModels)
local BoostService = require(script.Parent.BoostService)

local PetService   = {}
local PetsFolder   = nil      -- Workspace.Pets
local ActiveModels = {}       -- [player.UserId] -> { [uniqueId] -> Model }

-- Lookup helper: pet name -> config entry
local PetLookup = {}
for _, petData in ipairs(GameConfig.Pets) do
	PetLookup[petData.name] = petData
end

-- ============================================================
-- MODEL BUILDER  (geometric stand-in, replace with real models)
-- ============================================================
local function buildPetModel(petData, uniqueId)
	local rarityInfo = GameConfig.Rarities[petData.rarity]
	local size = (petData.size or 1.0)

	local model = Instance.new("Model")
	model.Name  = petData.name .. "_" .. uniqueId

	-- Body
	local body = Instance.new("Part")
	body.Name       = "HumanoidRootPart"
	body.Size       = Vector3.new(1.6 * size, 1.4 * size, 1.2 * size)
	body.Color      = petData.color
	body.Material   = Enum.Material.SmoothPlastic
	body.Anchored   = true
	body.CanCollide = false
	body.CastShadow = false
	body.Parent     = model

	-- Head
	local head = Instance.new("Part")
	head.Name       = "Head"
	head.Shape      = Enum.PartType.Ball
	head.Size       = Vector3.new(1.3 * size, 1.3 * size, 1.3 * size)
	head.Color      = petData.color
	head.Material   = Enum.Material.SmoothPlastic
	head.Anchored   = true
	head.CanCollide = false
	head.CastShadow = false
	head.Parent     = model

	-- Eyes
	for i, offset in ipairs({ Vector3.new(0.28, 0.15, -0.55), Vector3.new(-0.28, 0.15, -0.55) }) do
		local eye = Instance.new("Part")
		eye.Name      = "Eye" .. i
		eye.Shape     = Enum.PartType.Ball
		eye.Size      = Vector3.new(0.28*size, 0.28*size, 0.28*size)
		eye.Color     = Color3.new(1,1,1)
		eye.Material  = Enum.Material.Neon
		eye.Anchored  = true
		eye.CanCollide = false
		eye.CastShadow = false
		eye.Parent    = model
		-- Pupil
		local pupil = Instance.new("Part")
		pupil.Name    = "Pupil"..i
		pupil.Shape   = Enum.PartType.Ball
		pupil.Size    = Vector3.new(0.14*size,0.14*size,0.14*size)
		pupil.Color   = Color3.new(0,0,0)
		pupil.Material= Enum.Material.SmoothPlastic
		pupil.Anchored= true; pupil.CanCollide=false; pupil.CastShadow=false
		pupil.Parent  = model
	end

	-- Glow point light on body
	local ptLight = Instance.new("PointLight")
	ptLight.Color      = rarityInfo.color
	ptLight.Brightness = 1.5
	ptLight.Range      = 12
	ptLight.Parent     = body

	-- Particle aura for Rare+
	local rarityRank = {Common=1,Uncommon=2,Rare=3,Epic=4,Legendary=5,Mythic=6}
	if (rarityRank[petData.rarity] or 1) >= 3 then
		local att = Instance.new("Attachment"); att.Parent = body
		local pe = Instance.new("ParticleEmitter"); pe.Parent = att
		pe.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rarityInfo.color),
			ColorSequenceKeypoint.new(1, Color3.new(1,1,1))
		})
		pe.LightEmission  = 0.9; pe.LightInfluence = 0.1
		pe.Size           = NumberSequence.new({NumberSequenceKeypoint.new(0,0.2*size),NumberSequenceKeypoint.new(1,0)})
		pe.Transparency   = NumberSequence.new({NumberSequenceKeypoint.new(0,0.1),NumberSequenceKeypoint.new(1,1)})
		pe.Speed          = NumberRange.new(0.5, 2)
		pe.Lifetime       = NumberRange.new(0.8, 1.5)
		pe.Rate           = (rarityRank[petData.rarity] or 1) * 6
		pe.SpreadAngle    = Vector2.new(180,180)
		pe.RotSpeed       = NumberRange.new(-45,45)
	end

	-- Name billboard
	local billboard = Instance.new("BillboardGui")
	billboard.Size        = UDim2.new(0, 130, 0, 48)
	billboard.StudsOffset = Vector3.new(0, 1.8 * size, 0)
	billboard.Adornee     = body
	billboard.AlwaysOnTop = false
	billboard.Parent      = model

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size       = UDim2.new(1, 0, 0.6, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text       = petData.name
	nameLabel.TextColor3 = rarityInfo.color
	nameLabel.TextScaled = true
	nameLabel.Font       = Enum.Font.GothamBold
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.TextStrokeColor3 = Color3.new(0,0,0)
	nameLabel.Parent     = billboard

	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Size       = UDim2.new(1, 0, 0.4, 0)
	rarityLabel.Position   = UDim2.new(0, 0, 0.6, 0)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Text       = rarityInfo.displayName
	rarityLabel.TextColor3 = rarityInfo.color
	rarityLabel.TextScaled = true
	rarityLabel.Font       = Enum.Font.Gotham
	rarityLabel.Parent     = billboard

	model.PrimaryPart = body
	return model
end

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

	-- Follow loop
	RunService.Heartbeat:Connect(function(dt)
		for userId, models in pairs(ActiveModels) do
			local player = Players:GetPlayerByUserId(userId)
			if not player or not player.Character then continue end
			local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
			if not rootPart then continue end

			local modelList = {}
			for _, m in pairs(models) do table.insert(modelList, m) end
			local total = #modelList

			for i, model in ipairs(modelList) do
				local body = model:FindFirstChild("HumanoidRootPart")
				if not body then continue end

				local targetPos = rootPart.Position + getFollowOffset(i, total)
				local bobOffset = math.sin(tick() * 2 + i * 1.2) * 0.3
				targetPos = targetPos + Vector3.new(0, bobOffset, 0)

				local current = body.CFrame
				-- Face the same direction the player faces (so pets turn with you)
				local _, yaw = rootPart.CFrame:ToOrientation()
				local target  = CFrame.new(targetPos) * CFrame.Angles(0, yaw, 0)

				local speed = GameConfig.Settings.PetFollowSpeed
				local newCF = current:Lerp(target, math.min(dt * speed, 1))

				local petName = model.Name:match("^(.-)_")
				local petData = PetLookup[petName]
				local size = petData and (petData.size or 1) or 1
				updateModelCFrames(model, newCF, size)
			end
		end
	end)
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

	-- Start at player position
	local rootPart = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if rootPart then
		updateModelCFrames(model, rootPart.CFrame, petData.size or 1)
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
	ActiveModels[userId] = {}
	local folder = PetsFolder:FindFirstChild(tostring(userId))
	if folder then folder:Destroy() end
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

return PetService
