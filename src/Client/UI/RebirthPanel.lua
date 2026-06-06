-- MysticPets: RebirthPanel.lua
-- Place in: StarterPlayerScripts > Client > UI > RebirthPanel (ModuleScript)

local TweenService = game:GetService("TweenService")
local Players      = game:GetService("Players")
local PlayerGui    = Players.LocalPlayer.PlayerGui

local RebirthPanel = {}

local function G() return _G.MysticPets end
local function fmt(n) return G().formatNum(n) end

function RebirthPanel.Build(data)
	local screen = Instance.new("ScreenGui")
	screen.Name           = "RebirthPanel"
	screen.ResetOnSpawn   = false
	screen.DisplayOrder   = 50
	screen.IgnoreGuiInset = true
	screen.Parent         = PlayerGui

	local panel = Instance.new("Frame")
	panel.Size             = UDim2.new(0, 480, 0, 520)
	panel.Position         = UDim2.new(0.5, -240, 0.5, 400)
	panel.BackgroundColor3 = Color3.fromRGB(18, 14, 35)
	panel.BorderSizePixel  = 0
	panel.Parent           = screen
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)

	TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
		Position = UDim2.new(0.5, -240, 0.5, -260)
	}):Play()

	-- Header
	local header = Instance.new("Frame")
	header.Size            = UDim2.new(1, 0, 0, 50)
	header.BackgroundColor3 = Color3.fromRGB(60, 0, 100)
	header.BorderSizePixel = 0
	header.Parent          = panel
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, 14)

	local title = Instance.new("TextLabel")
	title.Size             = UDim2.new(1, -60, 1, 0)
	title.Position         = UDim2.new(0, 15, 0, 0)
	title.BackgroundTransparency = 1
	title.Text             = "♻️  Rebirth"
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

	-- Current rebirth status
	local currentRebirths = data.Rebirths or 0
	local currentMult     = data.RebirthMultiplier or 1

	local statusBox = Instance.new("Frame")
	statusBox.Size             = UDim2.new(1, -20, 0, 80)
	statusBox.Position         = UDim2.new(0, 10, 0, 58)
	statusBox.BackgroundColor3 = Color3.fromRGB(40, 0, 80)
	statusBox.BackgroundTransparency = 0.3
	statusBox.BorderSizePixel  = 0
	statusBox.Parent           = panel
	Instance.new("UICorner", statusBox).CornerRadius = UDim.new(0, 10)

	local statusText = Instance.new("TextLabel")
	statusText.Size            = UDim2.new(1, -20, 1, 0)
	statusText.Position        = UDim2.new(0, 10, 0, 0)
	statusText.BackgroundTransparency = 1
	statusText.Text            = "Current Rebirths: " .. currentRebirths .. "\nEarnings Multiplier: " .. currentMult .. "x\nTotal Coins Earned: " .. fmt(data.TotalCoinsEarned or 0)
	statusText.TextColor3      = Color3.fromRGB(220, 180, 255)
	statusText.TextScaled      = true
	statusText.Font            = Enum.Font.GothamBold
	statusText.TextXAlignment  = Enum.TextXAlignment.Left
	statusText.Parent          = statusBox

	-- Warning
	local warnBox = Instance.new("Frame")
	warnBox.Size             = UDim2.new(1, -20, 0, 70)
	warnBox.Position         = UDim2.new(0, 10, 0, 148)
	warnBox.BackgroundColor3 = Color3.fromRGB(100, 50, 0)
	warnBox.BackgroundTransparency = 0.3
	warnBox.BorderSizePixel  = 0
	warnBox.Parent           = panel
	Instance.new("UICorner", warnBox).CornerRadius = UDim.new(0, 10)

	local warnText = Instance.new("TextLabel")
	warnText.Size            = UDim2.new(1, -20, 1, 0)
	warnText.Position        = UDim2.new(0, 10, 0, 0)
	warnText.BackgroundTransparency = 1
	warnText.Text            = "⚠️ Rebirthing RESETS your coins, pets, and areas!\nYou keep: Gems, Gamepasses, Rebirth count."
	warnText.TextColor3      = Color3.fromRGB(255, 200, 100)
	warnText.TextScaled      = true
	warnText.Font            = Enum.Font.Gotham
	warnText.TextWrapped     = true
	warnText.Parent          = warnBox

	-- Rebirth tiers list
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size              = UDim2.new(1, -20, 0, 200)
	scroll.Position          = UDim2.new(0, 10, 0, 228)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel   = 0
	scroll.ScrollBarThickness = 4
	scroll.CanvasSize        = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent            = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.Parent  = scroll

	for _, tier in ipairs(G().GameConfig.Rebirths) do
		local isCompleted = currentRebirths >= tier.level
		local isCurrent   = currentRebirths + 1 == tier.level
		local tierColor   = isCompleted and Color3.fromRGB(50, 150, 50) or (isCurrent and Color3.fromRGB(200, 100, 0) or Color3.fromRGB(60, 60, 80))

		local tierCard = Instance.new("Frame")
		tierCard.Size             = UDim2.new(1, -4, 0, 44)
		tierCard.BackgroundColor3 = tierColor
		tierCard.BackgroundTransparency = 0.4
		tierCard.BorderSizePixel  = 0
		tierCard.Parent           = scroll
		Instance.new("UICorner", tierCard).CornerRadius = UDim.new(0, 8)

		local tierText = Instance.new("TextLabel")
		tierText.Size             = UDim2.new(1, -10, 1, 0)
		tierText.Position         = UDim2.new(0, 8, 0, 0)
		tierText.BackgroundTransparency = 1
		local prefix = isCompleted and "✔ " or (isCurrent and "▶ " or "  ")
		tierText.Text             = prefix .. tier.title .. " | " .. fmt(tier.requirement) .. " Total Coins | " .. tier.multiplier .. "x Earnings"
		tierText.TextColor3       = Color3.new(1, 1, 1)
		tierText.TextScaled       = true
		tierText.Font             = Enum.Font.GothamBold
		tierText.TextXAlignment   = Enum.TextXAlignment.Left
		tierText.Parent           = tierCard
	end

	-- Rebirth button
	local nextTier = nil
	for _, tier in ipairs(G().GameConfig.Rebirths) do
		if tier.level == currentRebirths + 1 then
			nextTier = tier
			break
		end
	end

	local canRebirth = nextTier and (data.TotalCoinsEarned or 0) >= nextTier.requirement
	local rebirthBtn = Instance.new("TextButton")
	rebirthBtn.Size             = UDim2.new(1, -20, 0, 54)
	rebirthBtn.Position         = UDim2.new(0, 10, 1, -64)
	rebirthBtn.BackgroundColor3 = canRebirth and Color3.fromRGB(150, 0, 255) or Color3.fromRGB(60, 60, 80)
	rebirthBtn.Text             = nextTier
		and (canRebirth and "♻️  REBIRTH NOW → " .. nextTier.title or "Need " .. fmt(nextTier.requirement) .. " total coins")
		or "Max Rebirth Reached!"
	rebirthBtn.TextColor3       = Color3.new(1, 1, 1)
	rebirthBtn.TextScaled       = true
	rebirthBtn.Font             = Enum.Font.GothamBold
	rebirthBtn.BorderSizePixel  = 0
	rebirthBtn.Active           = canRebirth
	rebirthBtn.Parent           = panel
	Instance.new("UICorner", rebirthBtn).CornerRadius = UDim.new(0, 10)

	if canRebirth then
		rebirthBtn.MouseButton1Click:Connect(function()
			G().RE_Rebirth:FireServer()
			screen:Destroy()
		end)
	end

	return screen
end

function RebirthPanel.Refresh(data)
	local existing = Players.LocalPlayer.PlayerGui:FindFirstChild("RebirthPanel")
	if existing then
		existing:Destroy()
		RebirthPanel.Build(data)
	end
end

return RebirthPanel
