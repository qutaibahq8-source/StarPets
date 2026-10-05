-- MysticPets: HatchUI.lua
-- Place in: StarterPlayerScripts > Client > UI > HatchUI (ModuleScript)

local TweenService   = game:GetService("TweenService")
local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local SoundService   = game:GetService("SoundService")
local PlayerGui      = Players.LocalPlayer.PlayerGui

local HatchUI = {}
local ActiveGui  = nil
local ActiveData = nil

local function G() return _G.MysticPets end
local function fmt(n) return G().formatNum(n) end

-- ============================================================
-- EGG SELECTION PANEL (shown when no specific egg chosen)
-- ============================================================
function HatchUI.Build(data)
	ActiveData = data
	if ActiveGui then ActiveGui:Destroy() end

	local screen = Instance.new("ScreenGui")
	screen.Name           = "HatchPanel"
	screen.ResetOnSpawn   = false
	screen.DisplayOrder   = 50
	screen.IgnoreGuiInset = true
	screen.Parent         = PlayerGui
	ActiveGui             = screen

	local panel = Instance.new("Frame")
	panel.Size             = UDim2.new(0, 600, 0, 400)
	panel.Position         = UDim2.new(0.5, -300, 0.5, 400)
	panel.BackgroundColor3 = Color3.fromRGB(18, 14, 35)
	panel.BorderSizePixel  = 0
	panel.Parent           = screen
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)

	TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
		Position = UDim2.new(0.5, -300, 0.5, -200)
	}):Play()

	local header = Instance.new("TextLabel")
	header.Size             = UDim2.new(1, 0, 0, 50)
	header.BackgroundColor3 = Color3.fromRGB(30, 20, 60)
	header.BackgroundTransparency = 0
	header.Text             = "🥚  Hatch Eggs"
	header.TextColor3       = Color3.new(1, 1, 1)
	header.TextScaled       = true
	header.Font             = Enum.Font.GothamBold
	header.BorderSizePixel  = 0
	header.Parent           = panel
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, 14)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size             = UDim2.new(0, 40, 0, 40)
	closeBtn.Position         = UDim2.new(1, -48, 0, 5)
	closeBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
	closeBtn.Text             = "✕"
	closeBtn.TextColor3       = Color3.new(1, 1, 1)
	closeBtn.TextScaled       = true
	closeBtn.Font             = Enum.Font.GothamBold
	closeBtn.BorderSizePixel  = 0
	closeBtn.Parent           = panel
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)
	closeBtn.MouseButton1Click:Connect(function()
		screen:Destroy()
	end)

	-- Egg cards
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size              = UDim2.new(1, -20, 1, -60)
	scroll.Position          = UDim2.new(0, 10, 0, 56)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel   = 0
	scroll.ScrollBarThickness = 4
	scroll.CanvasSize        = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent            = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent  = scroll

	for _, eggCfg in ipairs(G().GameConfig.Eggs) do
		local card = Instance.new("Frame")
		card.Size             = UDim2.new(1, -8, 0, 80)
		card.BackgroundColor3 = Color3.fromRGB(28, 22, 50)
		card.BorderSizePixel  = 0
		card.Parent           = scroll
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

		-- Egg icon
		local eggIcon = Instance.new("Frame")
		eggIcon.Size             = UDim2.new(0, 60, 0, 60)
		eggIcon.Position         = UDim2.new(0, 10, 0.5, -30)
		eggIcon.BackgroundColor3 = eggCfg.color
		eggIcon.BackgroundTransparency = 0.3
		eggIcon.BorderSizePixel  = 0
		eggIcon.Parent           = card
		Instance.new("UICorner", eggIcon).CornerRadius = UDim.new(1, 0)

		local eggEmoji = Instance.new("TextLabel")
		eggEmoji.Size             = UDim2.new(1, 0, 1, 0)
		eggEmoji.BackgroundTransparency = 1
		eggEmoji.Text             = "🥚"
		eggEmoji.TextScaled       = true
		eggEmoji.Font             = Enum.Font.Gotham
		eggEmoji.Parent           = eggIcon

		-- Info
		local infoFrame = Instance.new("Frame")
		infoFrame.Size            = UDim2.new(0, 280, 1, -16)
		infoFrame.Position        = UDim2.new(0, 80, 0, 8)
		infoFrame.BackgroundTransparency = 1
		infoFrame.Parent          = card

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size             = UDim2.new(1, 0, 0.45, 0)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text             = eggCfg.name
		nameLbl.TextColor3       = Color3.new(1, 1, 1)
		nameLbl.TextScaled       = true
		nameLbl.Font             = Enum.Font.GothamBold
		nameLbl.TextXAlignment   = Enum.TextXAlignment.Left
		nameLbl.Parent           = infoFrame

		local descLbl = Instance.new("TextLabel")
		descLbl.Size             = UDim2.new(1, 0, 0.45, 0)
		descLbl.Position         = UDim2.new(0, 0, 0.5, 0)
		descLbl.BackgroundTransparency = 1
		descLbl.Text             = eggCfg.description
		descLbl.TextColor3       = Color3.fromRGB(180, 180, 200)
		descLbl.TextScaled       = true
		descLbl.Font             = Enum.Font.Gotham
		descLbl.TextXAlignment   = Enum.TextXAlignment.Left
		descLbl.TextWrapped      = true
		descLbl.Parent           = infoFrame

		-- Determine display cost (account for one-time free egg)
		local displayCost, displayCost10
		if eggCfg.id == "StarterEgg" then
			local claimed = data and data.HasClaimedFreeEgg
			local afterCost = eggCfg.costAfterFirst or 150
			displayCost   = claimed and (fmt(afterCost) .. " Coins") or "🆓 FREE"
			displayCost10 = claimed and (fmt(afterCost * 10) .. " Coins") or "🆓 FREE x10"
		else
			displayCost   = fmt(eggCfg.cost) .. " " .. eggCfg.currency
			displayCost10 = fmt(eggCfg.cost * 10) .. " " .. eggCfg.currency
		end

		-- A world egg is SHOWN, not hidden: seeing what the next world holds is
		-- the reason to go and unlock it. But it cannot be pressed until the
		-- world is owned. The server refuses it either way; this says so before
		-- the player has to find out by trying and losing a click to an error.
		local locked = false
		if eggCfg.world then
			locked = true
			for _, a in ipairs((data and data.UnlockedAreas) or {}) do
				if a == eggCfg.world then locked = false break end
			end
		end
		if locked then
			displayCost   = "🔒 " .. eggCfg.world
			displayCost10 = "Locked"
		end

		-- Hatch x1 button
		local hatch1 = Instance.new("TextButton")
		hatch1.Size             = UDim2.new(0, 80, 0, 36)
		hatch1.Position         = UDim2.new(1, -180, 0.5, -18)
		hatch1.Text             = "Hatch\n" .. displayCost
		hatch1.BackgroundColor3 = eggCfg.color
		hatch1.TextColor3       = Color3.new(1, 1, 1)
		hatch1.TextScaled       = true
		hatch1.Font             = Enum.Font.GothamBold
		hatch1.BorderSizePixel  = 0
		hatch1.Parent           = card
		Instance.new("UICorner", hatch1).CornerRadius = UDim.new(0, 8)
		if locked then
			-- Active=false is what Responsive reads: a dead button neither
			-- springs nor clicks, so it does not pretend to have done something.
			hatch1.BackgroundColor3 = Color3.fromRGB(64, 60, 78)
			hatch1.Active = false
			hatch1.AutoButtonColor = false
		end
		hatch1.MouseButton1Click:Connect(function()
			if locked then return end
			G().RE_HatchEgg:FireServer(eggCfg.id, 1)
		end)

		-- Hatch x10 button
		local hatch10 = Instance.new("TextButton")
		hatch10.Size            = UDim2.new(0, 86, 0, 36)
		hatch10.Position        = UDim2.new(1, -90, 0.5, -18)
		hatch10.Text            = "x10\n" .. displayCost10
		hatch10.BackgroundColor3 = Color3.fromRGB(
			math.min(255, eggCfg.color.R * 255 + 40),
			math.min(255, eggCfg.color.G * 255 + 20),
			math.min(255, eggCfg.color.B * 255 + 20)
		)
		hatch10.TextColor3      = Color3.new(1, 1, 1)
		hatch10.TextScaled      = true
		hatch10.Font            = Enum.Font.GothamBold
		hatch10.BorderSizePixel = 0
		hatch10.Parent          = card
		Instance.new("UICorner", hatch10).CornerRadius = UDim.new(0, 8)
		if locked then
			hatch10.BackgroundColor3 = Color3.fromRGB(54, 50, 66)
			hatch10.Active = false
			hatch10.AutoButtonColor = false
		end
		hatch10.MouseButton1Click:Connect(function()
			if locked then return end
			G().RE_HatchEgg:FireServer(eggCfg.id, 10)
		end)
	end

	return screen
end

-- ============================================================
-- HATCH RESULT DISPLAY (dramatic reveal)
-- ============================================================
-- The pet itself, built from the same PetModels the server uses, turning
-- slowly in a ViewportFrame.
--
-- The reveal used to show the FIRST LETTER of the pet's name in a circle: hatch
-- a dragon and you got a "D". The moment the whole game is built around never
-- actually showed the player what they had won.
--
-- Returns a function that stops the turning, or nil if no model could be made
-- (in which case the caller falls back to the old letter rather than showing
-- an empty circle).
local function showModel(holder, pet, rarityInfo, mut)
	local okReq, PetModels = pcall(function()
		return require(game:GetService("ReplicatedStorage").Shared.PetModels)
	end)
	if not okReq or not PetModels then return nil end
	local petData
	for _, p in ipairs(G().GameConfig.Pets) do
		if p.name == pet.name then petData = p break end
	end
	if not petData then return nil end

	local okBuild, model = pcall(function()
		local m = PetModels.Build(petData, "reveal", rarityInfo, mut)
		return m
	end)
	if not okBuild or not model then return nil end

	local vf = Instance.new("ViewportFrame")
	vf.Name = "PetView"
	vf.Size = UDim2.new(1, 0, 1, 0)
	vf.BackgroundTransparency = 1
	vf.LightDirection = Vector3.new(-1, -1.4, -0.6)
	vf.Ambient = Color3.fromRGB(170, 170, 185)
	vf.Parent = holder
	model.Parent = vf

	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = vf
	vf.CurrentCamera = cam

	-- Frame the model from its own bounding box, so a tiny ant and a dragon
	-- both fill the circle rather than one vanishing and one overflowing it.
	local center, radius = Vector3.new(0, 0, 0), 2.5
	pcall(function()
		local cf, size = model:GetBoundingBox()
		center = cf.Position
		radius = math.max(1, size.Magnitude * 0.5)
	end)
	local dist = radius / math.tan(math.rad(cam.FieldOfView * 0.5)) * 1.05

	local function aim(t)
		local pos = center + Vector3.new(math.sin(t) * dist, radius * 0.35, math.cos(t) * dist)
		local ok = pcall(function() cam.CFrame = CFrame.lookAt(pos, center) end)
		if not ok then cam.CFrame = CFrame.new(pos, center) end
	end
	aim(0.6)

	local t = 0.6
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		-- Stop as soon as the card is gone. Left connected, every hatch would
		-- leave a dead spinner running behind it — thousands a session.
		if not vf.Parent then
			if conn then conn:Disconnect() end
			return
		end
		t = t + dt * 0.9
		aim(t)
	end)
	return function() if conn then conn:Disconnect() end end
end

function HatchUI.ShowHatchResult(pets, eggId)
	local screen = Instance.new("ScreenGui")
	screen.Name           = "HatchResultGui"
	screen.ResetOnSpawn   = false
	screen.DisplayOrder   = 200
	screen.IgnoreGuiInset = true
	screen.Parent         = PlayerGui

	-- Dark backdrop
	local backdrop = Instance.new("Frame")
	backdrop.Size             = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.BorderSizePixel  = 0
	backdrop.Parent           = screen

	-- A grid that fits the screen.
	--
	-- Cards used to sit in a single row: ten of them at 140 wide is 1,508
	-- pixels, past the edge of a laptop and far past a phone, so most of a
	-- ten-hatch was off screen. Now: up to five across, as many rows as it
	-- takes, each card shrunk to fit width AND height.
	local cam = workspace.CurrentCamera
	local W = (cam and cam.ViewportSize and cam.ViewportSize.X) or 1280
	local H = (cam and cam.ViewportSize and cam.ViewportSize.Y) or 720
	if type(W) ~= "number" or W <= 0 then W = 1280 end
	if type(H) ~= "number" or H <= 0 then H = 720 end

	local n = #pets
	local isSingle = (n == 1)
	local spacing = 12
	local cols = isSingle and 1 or math.min(n, 5, math.max(2, math.floor((W - 40) / 150)))
	local rows = math.ceil(n / cols)
	local maxW = isSingle and 220 or 140
	local maxH = isSingle and 300 or 200
	local cardWidth = math.min(maxW, math.floor((W - 40 - (cols - 1) * spacing) / cols))
	local cardHeight = math.min(maxH, math.floor((H * 0.7 - (rows - 1) * spacing) / rows))
	-- Keep a card taller than it is wide, so the model has room.
	cardWidth = math.min(cardWidth, math.floor(cardHeight * 0.78))

	local gridW = cols * cardWidth + (cols - 1) * spacing
	local gridH = rows * cardHeight + (rows - 1) * spacing
	local top = math.max(16, math.floor((H - gridH) / 2) - 24)

	for i, pet in ipairs(pets) do
		local rarityInfo = G().GameConfig.Rarities[pet.rarity]
		local rarityColor = rarityInfo.color
		local delay = (i - 1) * 0.15
		local col = (i - 1) % cols
		local row = math.floor((i - 1) / cols)
		local inRow = math.min(cols, n - row * cols)
		local rowW = inRow * cardWidth + (inRow - 1) * spacing
		local x = -rowW / 2 + col * (cardWidth + spacing)
		local y = top + row * (cardHeight + spacing)

		task.delay(delay, function()
			if not screen.Parent then return end
			local card = Instance.new("Frame")
			card.Name             = "HatchCard"
			card.Position         = UDim2.new(0.5, x, 0, y)
			card.BackgroundColor3 = Color3.fromRGB(20, 15, 40)
			card.BackgroundTransparency = 0
			card.BorderSizePixel  = 0
			card.Parent           = screen
			card.Size             = UDim2.new(0, 0, 0, 0)  -- start tiny for pop animation
			Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

			local stroke = Instance.new("UIStroke")
			stroke.Color     = rarityColor
			stroke.Thickness = 3
			stroke.Parent    = card

			TweenService:Create(card, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = UDim2.new(0, cardWidth, 0, cardHeight),
			}):Play()

			-- Rarity banner
			local bannerH = math.max(18, math.floor(cardHeight * 0.1))
			local rarityBanner = Instance.new("Frame")
			rarityBanner.Size             = UDim2.new(1, 0, 0, bannerH)
			rarityBanner.BackgroundColor3 = rarityColor
			rarityBanner.BorderSizePixel  = 0
			rarityBanner.Parent           = card
			Instance.new("UICorner", rarityBanner).CornerRadius = UDim.new(0, 10)

			local rarityLbl = Instance.new("TextLabel")
			rarityLbl.Size            = UDim2.new(1, 0, 1, 0)
			rarityLbl.BackgroundTransparency = 1
			rarityLbl.Text            = rarityInfo.displayName
			rarityLbl.TextColor3      = Color3.new(1, 1, 1)
			rarityLbl.TextScaled      = true
			rarityLbl.Font            = Enum.Font.GothamBold
			rarityLbl.Parent          = rarityBanner

			-- The pet, in a circle of its rarity's colour.
			local side = math.min(cardWidth - 16, cardHeight - bannerH - 52)
			local petCircle = Instance.new("Frame")
			petCircle.Name            = "PetCircle"
			petCircle.Size            = UDim2.new(0, side, 0, side)
			petCircle.Position        = UDim2.new(0.5, -side / 2, 0, bannerH + 6)
			petCircle.BackgroundColor3 = rarityColor
			petCircle.BackgroundTransparency = 0.6
			petCircle.BorderSizePixel = 0
			petCircle.Parent          = card
			Instance.new("UICorner", petCircle).CornerRadius = UDim.new(1, 0)

			local mut = pet.mutation and G().GameConfig.GetMutation and G().GameConfig.GetMutation(pet.mutation)

			if not showModel(petCircle, pet, rarityInfo, mut) then
				-- Only if the model could not be built. A letter is a poor
				-- picture of a pet, but it is better than an empty circle.
				local petIcon = Instance.new("TextLabel")
				petIcon.Size             = UDim2.new(1, 0, 1, 0)
				petIcon.BackgroundTransparency = 1
				petIcon.Text             = string.upper(string.sub(pet.name, 1, 1))
				petIcon.TextColor3       = Color3.new(1, 1, 1)
				petIcon.TextScaled       = true
				petIcon.Font             = Enum.Font.GothamBold
				petIcon.Parent           = petCircle
			end

			-- Pet name
			local nameLbl = Instance.new("TextLabel")
			nameLbl.Size            = UDim2.new(1, -10, 0, 40)
			nameLbl.Position        = UDim2.new(0, 5, 1, -46)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Text            = pet.name
			nameLbl.TextColor3      = rarityColor
			nameLbl.TextScaled      = true
			nameLbl.Font            = Enum.Font.GothamBold
			nameLbl.TextWrapped     = true
			nameLbl.Parent          = card

			if mut then
				nameLbl.Text = mut.emoji.." "..mut.name.."!\n"..pet.name
				nameLbl.TextColor3 = mut.color
				stroke.Color = mut.color; stroke.Thickness = 5
				petCircle.BackgroundColor3 = mut.color
			end

			-- First of its kind. The server knows (it stamps the Pet Index) and
			-- now says so, so a first-ever Dragon does not land like a fortieth
			-- cat.
			if pet.isNew then
				local ribbon = Instance.new("TextLabel")
				ribbon.Name = "NewRibbon"
				ribbon.Size = UDim2.new(0, math.max(44, cardWidth * 0.42), 0, math.max(18, bannerH))
				ribbon.Position = UDim2.new(1, -math.max(44, cardWidth * 0.42) + 6, 0, bannerH - 4)
				ribbon.BackgroundColor3 = Color3.fromRGB(255, 196, 40)
				ribbon.Text = "NEW!"
				ribbon.TextColor3 = Color3.fromRGB(60, 30, 0)
				ribbon.TextScaled = true
				ribbon.Font = Enum.Font.GothamBlack
				ribbon.Rotation = 8
				ribbon.ZIndex = 3
				ribbon.Parent = card
				Instance.new("UICorner", ribbon).CornerRadius = UDim.new(0, 6)
			end

			-- Sparkle effect for rare+
			if pet.rarity ~= "Common" and pet.rarity ~= "Uncommon" then
				for _ = 1, 8 do
					local spark = Instance.new("Frame")
					spark.Size             = UDim2.new(0, 4, 0, 4)
					spark.Position         = UDim2.new(math.random(), 0, math.random(), 0)
					spark.BackgroundColor3 = rarityColor
					spark.BackgroundTransparency = 0
					spark.BorderSizePixel  = 0
					spark.Parent           = card
					Instance.new("UICorner", spark).CornerRadius = UDim.new(1, 0)
					TweenService:Create(spark, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, -1, true), {
						BackgroundTransparency = 1,
						Size = UDim2.new(0, 8, 0, 8),
					}):Play()
				end
			end
		end)
	end

	-- Continue: under the grid, never off the bottom of the screen.
	task.delay(0.5 + n * 0.15, function()
		if not screen.Parent then return end
		local continueBtn = Instance.new("TextButton")
		continueBtn.Name             = "Continue"
		continueBtn.Size             = UDim2.new(0, 200, 0, 50)
		continueBtn.Position         = UDim2.new(0.5, -100, 0, math.min(H - 62, top + gridH + 16))
		continueBtn.BackgroundColor3 = Color3.fromRGB(50, 200, 100)
		continueBtn.Text             = "Continue ▶"
		continueBtn.TextColor3       = Color3.new(1, 1, 1)
		continueBtn.TextScaled       = true
		continueBtn.Font             = Enum.Font.GothamBold
		continueBtn.BorderSizePixel  = 0
		continueBtn.Parent           = screen
		Instance.new("UICorner", continueBtn).CornerRadius = UDim.new(0, 10)
		-- The reveal does not go through UIController, so it gets the same
		-- press feedback and click here. Liven only — Apply would resize the
		-- cards, which are positioned by hand above.
		pcall(function() require(script.Parent.Responsive).Liven(continueBtn) end)
		continueBtn.MouseButton1Click:Connect(function()
			screen:Destroy()
		end)
	end)

	-- Auto-close after 8 seconds
	task.delay(8, function()
		if screen and screen.Parent then
			screen:Destroy()
		end
	end)
end

-- Called when egg stand is clicked (from server fire)
function HatchUI.OpenForEgg(eggId, data, RE_HatchEgg, RE_Notification)
	local eggCfg = nil
	for _, e in ipairs(G().GameConfig.Eggs) do
		if e.id == eggId then eggCfg = e break end
	end
	if not eggCfg then return end

	-- If panel is already open just switch context; otherwise build
	HatchUI.Build(data)
end

function HatchUI.Refresh(data)
	ActiveData = data
end

return HatchUI
