-- MysticPets: ShopPanel.lua
-- Place in: StarterPlayerScripts > Client > UI > ShopPanel (ModuleScript)

local TweenService = game:GetService("TweenService")
local Players      = game:GetService("Players")
local PlayerGui    = Players.LocalPlayer.PlayerGui

local ShopPanel = {}
local ActiveGui = nil

local function G() return _G.MysticPets end

-- ============================================================
-- BUILD
-- ============================================================
function ShopPanel.Build(data)
	if ActiveGui then ActiveGui:Destroy() end

	local screen = Instance.new("ScreenGui")
	screen.Name           = "ShopPanel"
	screen.ResetOnSpawn   = false
	screen.DisplayOrder   = 50
	screen.IgnoreGuiInset = true
	screen.Parent         = PlayerGui
	ActiveGui             = screen

	local panel = Instance.new("Frame")
	panel.Size             = UDim2.new(0, 620, 0, 500)
	panel.Position         = UDim2.new(0.5, -310, 0.5, 400)
	panel.BackgroundColor3 = Color3.fromRGB(18, 14, 35)
	panel.BorderSizePixel  = 0
	panel.Parent           = screen
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)

	TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
		Position = UDim2.new(0.5, -310, 0.5, -250)
	}):Play()

	-- Header
	local header = Instance.new("Frame")
	header.Size            = UDim2.new(1, 0, 0, 50)
	header.BackgroundColor3 = Color3.fromRGB(40, 10, 80)
	header.BorderSizePixel = 0
	header.Parent          = panel
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, 14)

	local title = Instance.new("TextLabel")
	title.Size             = UDim2.new(1, -60, 1, 0)
	title.Position         = UDim2.new(0, 15, 0, 0)
	title.BackgroundTransparency = 1
	title.Text             = "🛒  Gamepass Shop"
	title.TextColor3       = Color3.new(1, 1, 1)
	title.TextScaled       = true
	title.Font             = Enum.Font.GothamBold
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

	-- Scroll area
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
	listLayout.Padding = UDim.new(0, 10)
	listLayout.Parent  = scroll

	local gpColors = {
		GP_2xCoins     = Color3.fromRGB(255, 180, 0),
		GP_AutoCollect = Color3.fromRGB(0, 200, 120),
		GP_VIP         = Color3.fromRGB(200, 50, 200),
		GP_PetSlots    = Color3.fromRGB(50, 150, 255),
		GP_LuckyBoost  = Color3.fromRGB(255, 100, 50),
	}

	local gpEmoji = {
		GP_2xCoins     = "💰",
		GP_AutoCollect = "🧲",
		GP_VIP         = "👑",
		GP_PetSlots    = "🐾",
		GP_LuckyBoost  = "🍀",
	}

	for _, gpCfg in ipairs(G().GameConfig.Gamepasses) do
		local owned   = data and data[gpCfg.key] or false
		local color   = gpColors[gpCfg.key] or Color3.fromRGB(100, 100, 200)
		local emoji   = gpEmoji[gpCfg.key] or "⭐"

		local card = Instance.new("Frame")
		card.Size             = UDim2.new(1, -8, 0, 90)
		card.BackgroundColor3 = Color3.fromRGB(28, 22, 50)
		card.BorderSizePixel  = 0
		card.Parent           = scroll
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

		-- Color strip
		local strip = Instance.new("Frame")
		strip.Size             = UDim2.new(0, 6, 1, 0)
		strip.BackgroundColor3 = color
		strip.BorderSizePixel  = 0
		strip.Parent           = card
		Instance.new("UICorner", strip).CornerRadius = UDim.new(0, 4)

		-- Emoji
		local emojiLbl = Instance.new("TextLabel")
		emojiLbl.Size             = UDim2.new(0, 60, 0, 60)
		emojiLbl.Position         = UDim2.new(0, 14, 0.5, -30)
		emojiLbl.BackgroundTransparency = 1
		emojiLbl.Text             = emoji
		emojiLbl.TextScaled       = true
		emojiLbl.Font             = Enum.Font.Gotham
		emojiLbl.Parent           = card

		-- Info
		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size             = UDim2.new(0, 260, 0, 35)
		nameLbl.Position         = UDim2.new(0, 82, 0, 10)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text             = gpCfg.name
		nameLbl.TextColor3       = color
		nameLbl.TextScaled       = true
		nameLbl.Font             = Enum.Font.GothamBold
		nameLbl.TextXAlignment   = Enum.TextXAlignment.Left
		nameLbl.Parent           = card

		local benefitLbl = Instance.new("TextLabel")
		benefitLbl.Size          = UDim2.new(0, 260, 0, 35)
		benefitLbl.Position      = UDim2.new(0, 82, 0, 46)
		benefitLbl.BackgroundTransparency = 1
		benefitLbl.Text          = gpCfg.benefit
		benefitLbl.TextColor3    = Color3.fromRGB(200, 200, 220)
		benefitLbl.TextScaled    = true
		benefitLbl.Font          = Enum.Font.Gotham
		benefitLbl.TextXAlignment = Enum.TextXAlignment.Left
		benefitLbl.TextWrapped   = true
		benefitLbl.Parent        = card

		-- Price / Owned button
		local buyBtn = Instance.new("TextButton")
		buyBtn.Size             = UDim2.new(0, 110, 0, 44)
		buyBtn.Position         = UDim2.new(1, -120, 0.5, -22)
		buyBtn.BackgroundColor3 = owned and Color3.fromRGB(50, 140, 50) or color
		buyBtn.Text             = owned and "✔ Owned" or "R$ " .. gpCfg.price
		buyBtn.TextColor3       = Color3.new(1, 1, 1)
		buyBtn.TextScaled       = true
		buyBtn.Font             = Enum.Font.GothamBold
		buyBtn.BorderSizePixel  = 0
		buyBtn.Active           = not owned
		buyBtn.Parent           = card
		Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 8)

		if not owned then
			buyBtn.MouseButton1Click:Connect(function()
				G().RE_BuyGamepass:FireServer(gpCfg.key)
				G().showToast("info", "Opening Roblox purchase window...")
			end)
		end
	end

	return screen
end

function ShopPanel.Refresh(data)
	local existing = PlayerGui:FindFirstChild("ShopPanel")
	if existing then
		existing:Destroy()
		ShopPanel.Build(data)
	end
end

return ShopPanel
