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
		hatch1.MouseButton1Click:Connect(function()
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
		hatch10.MouseButton1Click:Connect(function()
			G().RE_HatchEgg:FireServer(eggCfg.id, 10)
		end)
	end

	return screen
end

-- ============================================================
-- HATCH RESULT DISPLAY (dramatic reveal)
-- ============================================================
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

	-- Card display
	local isSingle = (#pets == 1)
	local cardWidth  = isSingle and 220 or 140
	local cardHeight = isSingle and 300 or 200
	local spacing    = 12

	local totalWidth = #pets * (cardWidth + spacing) - spacing
	local startX = -totalWidth / 2

	for i, pet in ipairs(pets) do
		local rarityColor = G().GameConfig.Rarities[pet.rarity].color
		local delay = (i - 1) * 0.15

		task.delay(delay, function()
			local card = Instance.new("Frame")
			card.Size             = UDim2.new(0, cardWidth, 0, cardHeight)
			card.Position         = UDim2.new(0.5, startX + (i - 1) * (cardWidth + spacing), 0.5, -cardHeight / 2)
			card.BackgroundColor3 = Color3.fromRGB(20, 15, 40)
			card.BackgroundTransparency = 0
			card.BorderSizePixel  = 0
			card.Parent           = screen
			card.Size             = UDim2.new(0, 0, 0, 0)  -- start tiny for pop animation
			Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

			-- Rarity border glow
			local stroke = Instance.new("UIStroke")
			stroke.Color     = rarityColor
			stroke.Thickness = 3
			stroke.Parent    = card

			TweenService:Create(card, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size     = UDim2.new(0, cardWidth, 0, cardHeight),
			}):Play()

			-- Rarity banner
			local rarityBanner = Instance.new("Frame")
			rarityBanner.Size             = UDim2.new(1, 0, 0, 30)
			rarityBanner.BackgroundColor3 = rarityColor
			rarityBanner.BorderSizePixel  = 0
			rarityBanner.Parent           = card
			Instance.new("UICorner", rarityBanner).CornerRadius = UDim.new(0, 10)

			local rarityLbl = Instance.new("TextLabel")
			rarityLbl.Size            = UDim2.new(1, 0, 1, 0)
			rarityLbl.BackgroundTransparency = 1
			rarityLbl.Text            = G().GameConfig.Rarities[pet.rarity].displayName
			rarityLbl.TextColor3      = Color3.new(1, 1, 1)
			rarityLbl.TextScaled      = true
			rarityLbl.Font            = Enum.Font.GothamBold
			rarityLbl.Parent          = rarityBanner

			-- Pet icon
			local petCircle = Instance.new("Frame")
			petCircle.Size            = UDim2.new(0, cardWidth - 30, 0, cardWidth - 30)
			petCircle.Position        = UDim2.new(0, 15, 0, 35)
			petCircle.BackgroundColor3 = rarityColor
			petCircle.BackgroundTransparency = 0.6
			petCircle.BorderSizePixel = 0
			petCircle.Parent          = card
			Instance.new("UICorner", petCircle).CornerRadius = UDim.new(1, 0)

			local petIcon = Instance.new("TextLabel")
			petIcon.Size             = UDim2.new(1, 0, 1, 0)
			petIcon.BackgroundTransparency = 1
			petIcon.Text             = string.upper(string.sub(pet.name, 1, 1))
			petIcon.TextColor3       = Color3.new(1, 1, 1)
			petIcon.TextScaled       = true
			petIcon.Font             = Enum.Font.GothamBold
			petIcon.Parent           = petCircle

			-- Pet name
			local nameLbl = Instance.new("TextLabel")
			nameLbl.Size            = UDim2.new(1, -10, 0, 40)
			nameLbl.Position        = UDim2.new(0, 5, 1, -50)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Text            = pet.name
			nameLbl.TextColor3      = rarityColor
			nameLbl.TextScaled      = true
			nameLbl.Font            = Enum.Font.GothamBold
			nameLbl.TextWrapped     = true
			nameLbl.Parent          = card

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

	-- Continue button
	task.delay(0.5 + #pets * 0.15, function()
		local continueBtn = Instance.new("TextButton")
		continueBtn.Size             = UDim2.new(0, 200, 0, 50)
		continueBtn.Position         = UDim2.new(0.5, -100, 0.8, 0)
		continueBtn.BackgroundColor3 = Color3.fromRGB(50, 200, 100)
		continueBtn.Text             = "Continue ▶"
		continueBtn.TextColor3       = Color3.new(1, 1, 1)
		continueBtn.TextScaled       = true
		continueBtn.Font             = Enum.Font.GothamBold
		continueBtn.BorderSizePixel  = 0
		continueBtn.Parent           = screen
		Instance.new("UICorner", continueBtn).CornerRadius = UDim.new(0, 10)
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
