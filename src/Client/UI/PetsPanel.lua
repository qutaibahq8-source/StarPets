-- MysticPets: PetsPanel.lua
-- Place in: StarterPlayerScripts > Client > UI > PetsPanel (ModuleScript)

local Players      = game:GetService("Players")
local PlayerGui    = Players.LocalPlayer.PlayerGui

local PetsPanel  = {}
local ActiveGui  = nil
local ActiveData = nil

local function G() return _G.MysticPets end
local function fmt(n) return (G().formatNum or G().fmt or tostring)(n) end

local rarityOrder = { "Mythic", "Legendary", "Epic", "Rare", "Uncommon", "Common" }
local rarityRank  = {}
for i, r in ipairs(rarityOrder) do rarityRank[r] = i end

-- A pet icon that shows the pet: its real 3D model, still, in a ViewportFrame.
--
-- This used to show a model only when an imported mesh existed in PetMeshes.
-- None ship, so every pet in every inventory was the first letter of its name.
-- PetView builds the same model the pet has in the world — an imported mesh if
-- there is one, the procedural one otherwise — and the letter is left only for
-- a species no model can be made for.
local function makePetIcon(petName, rarityColor, mutation)
	local holder = Instance.new("Frame")
	holder.Name = "PetIcon"
	holder.Size = UDim2.new(0,60,0,60); holder.Position = UDim2.new(0.5,-30,0,10)
	holder.BackgroundColor3 = rarityColor; holder.BackgroundTransparency = 0.55; holder.BorderSizePixel = 0
	Instance.new("UICorner", holder).CornerRadius = UDim.new(1,0)

	local ok, PetView = pcall(function() return require(script.Parent.PetView) end)
	local shown = ok and PetView and PetView.Show(holder, petName, { mutation = mutation })
	if not shown then
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1,0,1,0); lbl.BackgroundTransparency = 1
		lbl.Text = string.upper(string.sub(petName,1,1)); lbl.TextColor3 = Color3.new(1,1,1)
		lbl.TextScaled = true; lbl.Font = Enum.Font.GothamBold; lbl.Parent = holder
	end
	return holder
end

-- Signature of what the panel actually shows (pets + equipped). Used so the
-- panel only rebuilds when these change — NOT on every per-second coin tick.
local lastSig
local function sigOf(data)
	return tostring(#((data or {}).Pets or {})) .. "|" .. table.concat((data or {}).EquippedPets or {}, ",")
end

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
	lastSig = sigOf(data)

	local screen = Instance.new("ScreenGui")
	screen.Name           = "PetsPanel"
	screen.ResetOnSpawn   = false
	screen.DisplayOrder   = 50
	screen.IgnoreGuiInset = true
	screen.Parent         = PlayerGui

	-- Main panel
	local panel = Instance.new("Frame")
	panel.Size             = UDim2.new(0, 600, 0, 500)
	panel.Position         = UDim2.new(0.5, -300, 0.5, -250)
	panel.BackgroundColor3 = Color3.fromRGB(18, 14, 35)
	panel.BorderSizePixel  = 0
	panel.Parent           = screen
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)

	-- Slide in
	-- No slide-in: UIController gives every panel the same entrance, and a
	-- Position tween here fought the phone fit and dragged the panel off screen.

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
		slotFrame.Name             = "EquippedSlot"
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
					-- The pet, as in the grid below. This was the first three
					-- letters of its name.
					local okV, PetView = pcall(function() return require(script.Parent.PetView) end)
					if okV and PetView and PetView.Show(slotFrame, pet.name, { mutation = pet.mutation }) then
						break
					end
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

	-- QoL action bar (equip best / mass-delete by rarity; equipped & locked are safe)
	local actionBar = Instance.new("Frame")
	actionBar.Size = UDim2.new(1,-20,0,30); actionBar.Position = UDim2.new(0,10,0,123)
	actionBar.BackgroundTransparency = 1; actionBar.Parent = panel
	local al = Instance.new("UIListLayout", actionBar)
	al.FillDirection = Enum.FillDirection.Horizontal; al.Padding = UDim.new(0,6)
	local function actBtn(text, w, color, fn)
		local b = Instance.new("TextButton"); b.Size = UDim2.new(0,w,1,0); b.BackgroundColor3 = color
		b.Text=text; b.TextColor3=Color3.new(1,1,1); b.TextScaled=true; b.Font=Enum.Font.GothamBold
		b.BorderSizePixel=0; b.Parent=actionBar
		Instance.new("UICorner",b).CornerRadius=UDim.new(0,6); b.MouseButton1Click:Connect(fn)
	end
	actBtn("⭐ Equip Best", 110, Color3.fromRGB(50,150,90), function() G().RE_PetCmd:FireServer("equipBest") end)
	actBtn("🗑 Common", 92, Color3.fromRGB(120,55,55), function() G().RE_PetCmd:FireServer("deleteRarity","Common") end)
	actBtn("🗑 Uncommon", 112, Color3.fromRGB(120,55,55), function() G().RE_PetCmd:FireServer("deleteRarity","Uncommon") end)
	actBtn("🗑 Rare", 70, Color3.fromRGB(120,55,55), function() G().RE_PetCmd:FireServer("deleteRarity","Rare") end)

	-- Pet grid scroll
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size              = UDim2.new(1, -20, 1, -165)
	scroll.Position          = UDim2.new(0, 10, 0, 160)
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

		-- Pet icon — real 3D model (falls back to a letter circle)
		local icon = makePetIcon(pet.name, rarityColor, pet.mutation)
		icon.Parent = cell

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
	local existing = PlayerGui:FindFirstChild("PetsPanel")
	if not existing then return end
	-- Only rebuild if the pet list / equipped set actually changed (NOT every
	-- coin tick). This stops the panel flickering once a second.
	local sig = sigOf(data)
	if sig ~= lastSig then
		lastSig = sig
		-- Through UIController, which keeps the phone fit, the scroll position, and
		-- the panel itself when nothing on it actually changed.
		require(script.Parent.UIController).Rebuild("PetsPanel", data)
	end
end

return PetsPanel
