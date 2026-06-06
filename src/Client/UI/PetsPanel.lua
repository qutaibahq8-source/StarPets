-- MysticPets: PetsPanel.lua
-- Place in: StarterPlayerScripts > Client > UI > PetsPanel (ModuleScript)

local TweenService = game:GetService("TweenService")
local Players      = game:GetService("Players")
local PlayerGui    = Players.LocalPlayer.PlayerGui

local PetsPanel  = {}
local ActiveGui  = nil
local ActiveData = nil

local function G() return _G.MysticPets end
local function fmt(n) return G().formatNum(n) end

local rarityOrder = { "Mythic", "Legendary", "Epic", "Rare", "Uncommon", "Common" }
local rarityRank  = {}
for i, r in ipairs(rarityOrder) do rarityRank[r] = i end

local function sortPets(pets)
	local sorted = {}
	for _, p in ipairs(pets) do table.insert(sorted, p) end
	table.sort(sorted, function(a, b)
		local ra = rarityRank[a.rarity] or 99
		local rb = rarityRank[b.rarity] or 99
		return ra < rb
	end)
	return sorted
end

local function isEquipped(data, uniqueId)
	for _, id in ipairs(data.EquippedPets) do
		if id == uniqueId then return true end
	end
	return false
end

local function getRarityColor(rarity)
	local cfg = G().GameConfig.Rarities[rarity]
	return cfg and cfg.color or Color3.new(1, 1, 1)
end

function PetsPanel.Build(data)
	ActiveData = data

	local screen = Instance.new("ScreenGui")
	screen.Name           = "PetsPanel"
	screen.ResetOnSpawn   = false
	screen.DisplayOrder   = 50
	screen.IgnoreGuiInset = true
	screen.Parent         = PlayerGui

	-- Main panel
	local panel = Instance.new("Frame")
	panel.Size             = UDim2.new(0, 600, 0, 500)
	panel.Position         = UDim2.new(0.5, -300, 0.5, 400)
	panel.BackgroundColor3 = Color3.fromRGB(18, 14, 35)
	panel.BorderSizePixel  = 0
	panel.Parent           = screen
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)

	-- Slide in
	TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
		Position = UDim2.new(0.5, -300, 0.5, -250)
	}):Play()

	-- Header
	local header = Instance.new("Frame")
	header.Size            = UDim2.new(1, 0, 0, 50)
	header.BackgroundColor3 = Color3.fromRGB(30, 20, 60)
	header.BorderSizePixel = 0
	header.Parent          = panel
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, 14)

	local title = Instance.new("TextLabel")
	title.Size             = UDim2.new(1, -60, 1, 0)
	title.Position         = UDim2.new(0, 15, 0, 0)
	title.BackgroundTransparency = 1
	title.Text             = "🐾  My Pets  (" .. #(data.Pets or {}) .. ")"
	title.TextColor3       = Color3.new(1, 1, 1)
	title.Font             = Enum.Font.GothamBold
	title.TextScaled       = true
	title.TextXAlignment   = Enum.TextXAlignment.Left
	title.Parent           = header

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size            = UDim2.new(0, 40, 0, 40)
	closeBtn.Position        = UDim2.new(1, -48, 0, 5)
	closeBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
	closeBtn.Text            = "✕"
	closeBtn.TextColor3      = Color3.new(1, 1, 1)
	closeBtn.TextScaled      = true
	closeBtn.Font            = Enum.Font.GothamBold
	closeBtn.BorderSizePixel = 0
	closeBtn.Parent          = header
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)
	closeBtn.MouseButton1Click:Connect(function()
		screen:Destroy()
	end)

	-- Equipped slots bar
	local equippedBar = Instance.new("Frame")
	equippedBar.Size            = UDim2.new(1, -20, 0, 60)
	equippedBar.Position        = UDim2.new(0, 10, 0, 56)
	equippedBar.BackgroundColor3 = Color3.fromRGB(25, 20, 50)
	equippedBar.BorderSizePixel = 0
	equippedBar.Parent          = panel
	Instance.new("UICorner", equippedBar).CornerRadius = UDim.new(0, 8)

	local equippedTitle = Instance.new("TextLabel")
	equippedTitle.Size     = UDim2.new(0, 120, 1, 0)
	equippedTitle.BackgroundTransparency = 1
	equippedTitle.Text     = "Equipped:"
	equippedTitle.TextColor3 = Color3.fromRGB(180, 180, 255)
	equippedTitle.TextScaled = true
	equippedTitle.Font     = Enum.Font.GothamBold
	equippedTitle.Parent   = equippedBar

	local maxSlots = (data.GP_PetSlots and G().GameConfig.Settings.VIPPetSlots or G().GameConfig.Settings.DefaultPetSlots)
	for slotIdx = 1, maxSlots do
		local equippedId = (data.EquippedPets or {})[slotIdx]
		local slotFrame = Instance.new("Frame")
		slotFrame.Size             = UDim2.new(0, 50, 0, 50)
		slotFrame.Position         = UDim2.new(0, 110 + (slotIdx - 1) * 56, 0, 5)
		slotFrame.BackgroundColor3 = equippedId and Color3.fromRGB(40, 80, 140) or Color3.fromRGB(35, 35, 55)
		slotFrame.BorderSizePixel  = 0
		slotFrame.Parent           = equippedBar
		Instance.new("UICorner", slotFrame).CornerRadius = UDim.new(0, 6)

		if equippedId then
			-- Find the pet
			for _, pet in ipairs(data.Pets or {}) do
				if pet.uniqueId == equippedId then
					local lbl = Instance.new("TextLabel")
					lbl.Size             = UDim2.new(1, 0, 1, 0)
					lbl.BackgroundTransparency = 1
					lbl.Text             = string.sub(pet.name, 1, 3)
					lbl.TextColor3       = getRarityColor(pet.rarity)
					lbl.TextScaled       = true
					lbl.Font             = Enum.Font.GothamBold
					lbl.Parent           = slotFrame
					break
				end
			end
		end
	end

	-- Pet grid scroll
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size              = UDim2.new(1, -20, 1, -130)
	scroll.Position          = UDim2.new(0, 10, 0, 125)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel   = 0
	scroll.ScrollBarThickness = 4
	scroll.CanvasSize        = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent            = panel

	local grid = Instance.new("UIGridLayout")
	grid.CellSize    = UDim2.new(0, 100, 0, 120)
	grid.CellPadding = UDim2.new(0, 8, 0, 8)
	grid.Parent      = scroll

	local sorted = sortPets(data.Pets or {})
	for _, pet in ipairs(sorted) do
		local rarityColor = getRarityColor(pet.rarity)
		local equipped    = isEquipped(data, pet.uniqueId)

		local cell = Instance.new("Frame")
		cell.BackgroundColor3 = equipped and Color3.fromRGB(30, 60, 100) or Color3.fromRGB(28, 22, 50)
		cell.BorderSizePixel  = 0
		cell.Parent           = scroll
		Instance.new("UICorner", cell).CornerRadius = UDim.new(0, 8)

		-- Rarity strip at top
		local strip = Instance.new("Frame")
		strip.Size             = UDim2.new(1, 0, 0, 5)
		strip.BackgroundColor3 = rarityColor
		strip.BorderSizePixel  = 0
		strip.Parent           = cell
		Instance.new("UICorner", strip).CornerRadius = UDim.new(0, 4)

		-- Pet icon (colored circle)
		local icon = Instance.new("Frame")
		icon.Size             = UDim2.new(0, 60, 0, 60)
		icon.Position         = UDim2.new(0.5, -30, 0, 10)
		icon.BackgroundColor3 = rarityColor
		icon.BackgroundTransparency = 0.5
		icon.BorderSizePixel  = 0
		icon.Parent           = cell
		Instance.new("UICorner", icon).CornerRadius = UDim.new(1, 0)

		local iconLbl = Instance.new("TextLabel")
		iconLbl.Size             = UDim2.new(1, 0, 1, 0)
		iconLbl.BackgroundTransparency = 1
		iconLbl.Text             = string.upper(string.sub(pet.name, 1, 1))
		iconLbl.TextColor3       = Color3.new(1, 1, 1)
		iconLbl.TextScaled       = true
		iconLbl.Font             = Enum.Font.GothamBold
		iconLbl.Parent           = icon

		-- Name
		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size             = UDim2.new(1, -4, 0, 20)
		nameLbl.Position         = UDim2.new(0, 2, 0, 74)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text             = pet.name
		nameLbl.TextColor3       = rarityColor
		nameLbl.TextScaled       = true
		nameLbl.Font             = Enum.Font.GothamBold
		nameLbl.TextWrapped      = true
		nameLbl.Parent           = cell

		-- Rarity label
		local rarityLbl = Instance.new("TextLabel")
		rarityLbl.Size           = UDim2.new(1, -4, 0, 15)
		rarityLbl.Position       = UDim2.new(0, 2, 0, 94)
		rarityLbl.BackgroundTransparency = 1
		rarityLbl.Text           = pet.rarity
		rarityLbl.TextColor3     = rarityColor
		rarityLbl.TextScaled     = true
		rarityLbl.Font           = Enum.Font.Gotham
		rarityLbl.Parent         = cell

		-- Equip/Unequip button
		local equipBtn = Instance.new("TextButton")
		equipBtn.Size            = UDim2.new(1, -8, 0, 20)
		equipBtn.Position        = UDim2.new(0, 4, 1, -24)
		equipBtn.BackgroundColor3 = equipped and Color3.fromRGB(180, 50, 50) or Color3.fromRGB(50, 150, 50)
		equipBtn.Text            = equipped and "Unequip" or "Equip"
		equipBtn.TextColor3      = Color3.new(1, 1, 1)
		equipBtn.TextScaled      = true
		equipBtn.Font            = Enum.Font.GothamBold
		equipBtn.BorderSizePixel = 0
		equipBtn.Parent          = cell
		Instance.new("UICorner", equipBtn).CornerRadius = UDim.new(0, 5)

		local uid = pet.uniqueId
		equipBtn.MouseButton1Click:Connect(function()
			if isEquipped(ActiveData, uid) then
				G().RE_UnequipPet:FireServer(uid)
			else
				G().RE_EquipPet:FireServer(uid)
			end
		end)
	end

	return screen
end

function PetsPanel.Refresh(data)
	ActiveData = data
	-- Rebuild when data changes
	local existing = PlayerGui:FindFirstChild("PetsPanel")
	if existing then
		existing:Destroy()
		PetsPanel.Build(data)
	end
end

return PetsPanel
