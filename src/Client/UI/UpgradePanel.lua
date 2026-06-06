-- MysticPets: UpgradePanel.lua
-- Place in: StarterPlayerScripts > Client > UI > UpgradePanel (ModuleScript)

local TweenService = game:GetService("TweenService")
local Players      = game:GetService("Players")
local PlayerGui    = Players.LocalPlayer.PlayerGui

local UpgradePanel = {}

local function G() return _G.MysticPets end
local function fmt(n) return G().fmt(n) end

local COLORS = {
	SpeedBoost = Color3.fromRGB(255,200,0),
	JumpBoost  = Color3.fromRGB(100,200,255),
	LuckyCharm = Color3.fromRGB(50,220,80),
	CoinBonus  = Color3.fromRGB(255,140,0),
}

function UpgradePanel.Build(data)
	local screen = Instance.new("ScreenGui")
	screen.Name="UpgradePanel"; screen.ResetOnSpawn=false
	screen.DisplayOrder=50; screen.IgnoreGuiInset=true; screen.Parent=PlayerGui

	local panel = Instance.new("Frame")
	panel.Size=UDim2.new(0,580,0,480)
	panel.Position=UDim2.new(0.5,-290,0.5,500)
	panel.BackgroundColor3=Color3.fromRGB(14,10,28)
	panel.BorderSizePixel=0; panel.Parent=screen
	Instance.new("UICorner",panel).CornerRadius=UDim.new(0,14)
	local stroke=Instance.new("UIStroke",panel)
	stroke.Color=Color3.fromRGB(140,80,255); stroke.Thickness=2

	TweenService:Create(panel,TweenInfo.new(0.3,Enum.EasingStyle.Back),{
		Position=UDim2.new(0.5,-290,0.5,-240)
	}):Play()

	-- Header
	local header=Instance.new("Frame")
	header.Size=UDim2.new(1,0,0,52); header.BackgroundColor3=Color3.fromRGB(50,20,90)
	header.BorderSizePixel=0; header.Parent=panel
	Instance.new("UICorner",header).CornerRadius=UDim.new(0,14)

	local title=Instance.new("TextLabel")
	title.Size=UDim2.new(1,-60,1,0); title.Position=UDim2.new(0,15,0,0)
	title.BackgroundTransparency=1; title.Text="⚡  Upgrade Shop"
	title.TextColor3=Color3.new(1,1,1); title.TextScaled=true
	title.Font=Enum.Font.GothamBold; title.TextXAlignment=Enum.TextXAlignment.Left
	title.Parent=header

	local closeBtn=Instance.new("TextButton")
	closeBtn.Size=UDim2.new(0,40,0,40); closeBtn.Position=UDim2.new(1,-48,0,6)
	closeBtn.BackgroundColor3=Color3.fromRGB(180,40,40); closeBtn.Text="✕"
	closeBtn.TextColor3=Color3.new(1,1,1); closeBtn.TextScaled=true
	closeBtn.Font=Enum.Font.GothamBold; closeBtn.BorderSizePixel=0; closeBtn.Parent=header
	Instance.new("UICorner",closeBtn).CornerRadius=UDim.new(0,8)
	closeBtn.MouseButton1Click:Connect(function() screen:Destroy() end)

	-- Upgrade cards grid
	local scroll=Instance.new("ScrollingFrame")
	scroll.Size=UDim2.new(1,-16,1,-60); scroll.Position=UDim2.new(0,8,0,58)
	scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0
	scroll.ScrollBarThickness=4; scroll.CanvasSize=UDim2.new(0,0,0,0)
	scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.Parent=panel

	local grid=Instance.new("UIGridLayout"); grid.Parent=scroll
	grid.CellSize=UDim2.new(0.5,-8,0,200); grid.CellPadding=UDim2.new(0,8,0,8)

	local upgrades = G().GameConfig.Upgrades
	local upgradeData = (data and data.Upgrades) or {}

	for _, upg in ipairs(upgrades) do
		local col = COLORS[upg.key] or Color3.fromRGB(200,200,200)
		local currentLevel = upgradeData[upg.key] or 0
		local maxLevel = #upg.levels
		local isMaxed = currentLevel >= maxLevel
		local nextLevel = upg.levels[currentLevel+1]

		local card=Instance.new("Frame")
		card.BackgroundColor3=Color3.fromRGB(20,16,36)
		card.BorderSizePixel=0; card.Parent=scroll
		Instance.new("UICorner",card).CornerRadius=UDim.new(0,12)
		local cstroke=Instance.new("UIStroke",card)
		cstroke.Color=col; cstroke.Transparency=0.5

		-- Top color bar
		local topBar=Instance.new("Frame")
		topBar.Size=UDim2.new(1,0,0,5); topBar.BackgroundColor3=col
		topBar.BorderSizePixel=0; topBar.Parent=card
		Instance.new("UICorner",topBar).CornerRadius=UDim.new(0,4)

		-- Icon + name
		local iconLbl=Instance.new("TextLabel")
		iconLbl.Size=UDim2.new(1,0,0,50); iconLbl.Position=UDim2.new(0,0,0,8)
		iconLbl.BackgroundTransparency=1; iconLbl.Text=upg.icon
		iconLbl.TextScaled=true; iconLbl.Font=Enum.Font.Gotham; iconLbl.Parent=card

		local nameLbl=Instance.new("TextLabel")
		nameLbl.Size=UDim2.new(1,-10,0,24); nameLbl.Position=UDim2.new(0,5,0,56)
		nameLbl.BackgroundTransparency=1; nameLbl.Text=upg.name
		nameLbl.TextColor3=col; nameLbl.TextScaled=true
		nameLbl.Font=Enum.Font.GothamBold; nameLbl.Parent=card

		local descLbl=Instance.new("TextLabel")
		descLbl.Size=UDim2.new(1,-10,0,30); descLbl.Position=UDim2.new(0,5,0,80)
		descLbl.BackgroundTransparency=1; descLbl.Text=upg.desc
		descLbl.TextColor3=Color3.fromRGB(160,160,180); descLbl.TextScaled=true
		descLbl.Font=Enum.Font.Gotham; descLbl.TextWrapped=true; descLbl.Parent=card

		-- Level bar
		local levelText=Instance.new("TextLabel")
		levelText.Size=UDim2.new(1,-10,0,20); levelText.Position=UDim2.new(0,5,0,112)
		levelText.BackgroundTransparency=1
		levelText.Text=isMaxed and "✨ MAX LEVEL" or ("Level "..currentLevel.."/"..maxLevel)
		levelText.TextColor3=isMaxed and Color3.fromRGB(255,215,0) or Color3.fromRGB(180,180,200)
		levelText.TextScaled=true; levelText.Font=Enum.Font.GothamBold; levelText.Parent=card

		-- Progress dots
		for lv=1,maxLevel do
			local dot=Instance.new("Frame")
			dot.Size=UDim2.new(0,18,0,6)
			dot.Position=UDim2.new(0, 5+(lv-1)*22, 0, 132)
			dot.BackgroundColor3=lv<=currentLevel and col or Color3.fromRGB(50,50,70)
			dot.BorderSizePixel=0; dot.Parent=card
			Instance.new("UICorner",dot).CornerRadius=UDim.new(1,0)
		end

		-- Buy button
		local buyBtn=Instance.new("TextButton")
		buyBtn.Size=UDim2.new(1,-16,0,36); buyBtn.Position=UDim2.new(0,8,1,-46)
		buyBtn.BackgroundColor3=isMaxed and Color3.fromRGB(60,50,80) or col
		buyBtn.Text=isMaxed and "MAXED ✨"
			or ("Buy Lv"..currentLevel+1.." — 💰 "..fmt(nextLevel.cost))
		buyBtn.TextColor3=Color3.new(1,1,1); buyBtn.TextScaled=true
		buyBtn.Font=Enum.Font.GothamBold; buyBtn.BorderSizePixel=0
		buyBtn.Active=not isMaxed; buyBtn.Parent=card
		Instance.new("UICorner",buyBtn).CornerRadius=UDim.new(0,8)

		if not isMaxed then
			buyBtn.MouseButton1Click:Connect(function()
				G().RE_BuyUpgrade:FireServer(upg.key)
				-- Refresh after short delay
				task.delay(0.5,function()
					local existing=PlayerGui:FindFirstChild("UpgradePanel")
					if existing then existing:Destroy() end
				end)
			end)
		end
	end

	return screen
end

function UpgradePanel.Refresh(data)
	local existing=PlayerGui:FindFirstChild("UpgradePanel")
	if existing then existing:Destroy(); UpgradePanel.Build(data) end
end

return UpgradePanel
