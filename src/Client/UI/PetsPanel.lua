-- MysticPets: PetsPanel.lua
-- Place in: StarterPlayerScripts > Client > UI > PetsPanel (ModuleScript)

local TweenService = game:GetService("TweenService")
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

-- Build a pet icon that shows the REAL 3D model (ViewportFrame); falls back to a letter.
local function makePetIcon(petName, rarityColor)
	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(0,60,0,60); holder.Position = UDim2.new(0.5,-30,0,10)
	holder.BackgroundColor3 = rarityColor; holder.BackgroundTransparency = 0.55; holder.BorderSizePixel = 0
	Instance.new("UICorner", holder).CornerRadius = UDim.new(1,0)

	local pm = game:GetService("ReplicatedStorage"):FindFirstChild("PetMeshes")
		or workspace:FindFirstChild("PetMeshes")
	local template
	if pm then
		template = pm:FindFirstChild(petName)
		if not template then
			local key = string.lower(string.gsub(petName,"%s",""))
			for _,c in ipairs(pm:GetChildren()) do
				if string.lower(string.gsub(c.Name,"%s","")) == key then template = c; break end
			end
		end
	end

	local shown = false
	if template then
		shown = pcall(function()
			local vf = Instance.new("ViewportFrame")
			vf.Size = UDim2.new(1,0,1,0); vf.BackgroundTransparency = 1; vf.Parent = holder
			local m = template:Clone()
			for _,d in ipairs(m:GetDescendants()) do
				if d:IsA("LuaSourceContainer") then d:Destroy()
				elseif d:IsA("BasePart") then d.Anchored=true; d.CanCollide=false end
			end
			m.Parent = vf
			local cam = Instance.new("Camera"); cam.Parent = vf; vf.CurrentCamera = cam
			local cf, size
			if m:IsA("Model") then
				if not m.PrimaryPart then
					local p = m:FindFirstChildWhichIsA("BasePart", true); if p then m.PrimaryPart = p end
				end
				cf, size = m:GetBoundingBox()
			elseif m:IsA("BasePart") then
				cf, size = m.CFrame, m.Size
			else cf, size = CFrame.new(), Vector3.new(4,4,4) end
			local ext = math.max(size.X, size.Y, size.Z, 1)
			local dist = ext*1.8 + 1.5
			cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(dist*0.45, ext*0.4, dist), cf.Position)
		end)
	end
	if not shown then
		for _,c in ipairs(holder:GetChildren()) do if c:IsA("ViewportFrame") then c:Destroy() end end
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
		local icon = makePetIcon(pet.name, rarityColor)
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
		existing:Destroy()
		PetsPanel.Build(data)
	end
end

return PetsPanel
