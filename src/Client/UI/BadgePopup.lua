-- MysticPets: BadgePopup.lua
-- Handles incoming badge earned events and shows animated popups
-- Place in: StarterPlayerScripts > Client > UI > BadgePopup (LocalScript)

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerGui = Players.LocalPlayer.PlayerGui
local Remotes   = ReplicatedStorage:WaitForChild("Remotes", 30)
local RE_BadgeEarned = Remotes:WaitForChild("BadgeEarned")

local rarityColors = {
	Common    = Color3.fromRGB(180, 180, 180),
	Uncommon  = Color3.fromRGB(50,  200, 50),
	Rare      = Color3.fromRGB(50,  100, 255),
	Epic      = Color3.fromRGB(150, 0,   200),
	Legendary = Color3.fromRGB(255, 165, 0),
	Mythic    = Color3.fromRGB(0,   200, 255),
}

local queue = {}
local showing = false

local function showNext()
	if showing or #queue == 0 then return end
	showing = true
	local badge = table.remove(queue, 1)
	local color = rarityColors[badge.rarity] or Color3.fromRGB(200, 200, 200)

	-- Container
	local screen = Instance.new("ScreenGui")
	screen.Name           = "BadgePopup"
	screen.ResetOnSpawn   = false
	screen.DisplayOrder   = 150
	screen.IgnoreGuiInset = true
	screen.Parent         = PlayerGui

	-- Slide-in card (bottom right)
	local card = Instance.new("Frame")
	card.Size             = UDim2.new(0, 320, 0, 90)
	card.Position         = UDim2.new(1, 20, 1, -160)  -- start off-screen right
	card.BackgroundColor3 = Color3.fromRGB(14, 10, 28)
	card.BorderSizePixel  = 0
	card.Parent           = screen
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)

	-- Rarity border
	local stroke = Instance.new("UIStroke")
	stroke.Color     = color
	stroke.Thickness = 2.5
	stroke.Parent    = card

	-- Left color bar
	local bar = Instance.new("Frame")
	bar.Size             = UDim2.new(0, 6, 1, 0)
	bar.BackgroundColor3 = color
	bar.BorderSizePixel  = 0
	bar.Parent           = card
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 4)

	-- Glow effect
	local glow = Instance.new("Frame")
	glow.Size             = UDim2.new(0, 6, 1, 0)
	glow.BackgroundColor3 = color
	glow.BackgroundTransparency = 0.6
	glow.BorderSizePixel  = 0
	glow.Parent           = card
	Instance.new("UICorner", glow).CornerRadius = UDim.new(0, 4)

	-- "BADGE EARNED" label
	local header = Instance.new("TextLabel")
	header.Size             = UDim2.new(1, -80, 0, 22)
	header.Position         = UDim2.new(0, 18, 0, 8)
	header.BackgroundTransparency = 1
	header.Text             = "🏅  BADGE EARNED"
	header.TextColor3       = color
	header.TextScaled       = true
	header.Font             = Enum.Font.GothamBold
	header.TextXAlignment   = Enum.TextXAlignment.Left
	header.Parent           = card

	-- Badge icon + title
	local iconLbl = Instance.new("TextLabel")
	iconLbl.Size            = UDim2.new(0, 44, 0, 44)
	iconLbl.Position        = UDim2.new(0, 12, 0, 30)
	iconLbl.BackgroundColor3= color
	iconLbl.BackgroundTransparency = 0.75
	iconLbl.Text            = badge.icon or "⭐"
	iconLbl.TextScaled      = true
	iconLbl.Font            = Enum.Font.Gotham
	iconLbl.BorderSizePixel = 0
	iconLbl.Parent          = card
	Instance.new("UICorner", iconLbl).CornerRadius = UDim.new(0, 8)

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size           = UDim2.new(1, -70, 0, 22)
	titleLbl.Position       = UDim2.new(0, 64, 0, 30)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text           = badge.title or "Badge"
	titleLbl.TextColor3     = Color3.new(1, 1, 1)
	titleLbl.TextScaled     = true
	titleLbl.Font           = Enum.Font.GothamBold
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.Parent         = card

	local descLbl = Instance.new("TextLabel")
	descLbl.Size            = UDim2.new(1, -70, 0, 18)
	descLbl.Position        = UDim2.new(0, 64, 0, 54)
	descLbl.BackgroundTransparency = 1
	descLbl.Text            = badge.desc or ""
	descLbl.TextColor3      = Color3.fromRGB(180, 180, 200)
	descLbl.TextScaled      = true
	descLbl.Font            = Enum.Font.Gotham
	descLbl.TextXAlignment  = Enum.TextXAlignment.Left
	descLbl.TextWrapped     = true
	descLbl.Parent          = card

	-- Rarity tag (top right)
	local rarTag = Instance.new("TextLabel")
	rarTag.Size             = UDim2.new(0, 90, 0, 22)
	rarTag.Position         = UDim2.new(1, -98, 0, 8)
	rarTag.BackgroundColor3 = color
	rarTag.BackgroundTransparency = 0.3
	rarTag.Text             = badge.rarity or ""
	rarTag.TextColor3       = Color3.new(1, 1, 1)
	rarTag.TextScaled       = true
	rarTag.Font             = Enum.Font.GothamBold
	rarTag.BorderSizePixel  = 0
	rarTag.Parent           = card
	Instance.new("UICorner", rarTag).CornerRadius = UDim.new(0, 6)

	-- Slide in from right
	TweenService:Create(card, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(1, -330, 1, -160)
	}):Play()

	-- Hold for 4 seconds then slide out
	task.delay(4, function()
		TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(1, 20, 1, -160)
		}):Play()
		task.delay(0.35, function()
			screen:Destroy()
			showing = false
			task.wait(0.3)
			showNext()
		end)
	end)
end

RE_BadgeEarned.OnClientEvent:Connect(function(badge)
	table.insert(queue, badge)
	showNext()
end)
