-- MysticPets: LeaderboardPanel.lua
-- Place in: StarterPlayerScripts > Client > UI > LeaderboardPanel (ModuleScript)

local TweenService = game:GetService("TweenService")
local Players      = game:GetService("Players")
local PlayerGui    = Players.LocalPlayer.PlayerGui

local LeaderboardPanel = {}

local function G() return _G.MysticPets end
local function fmt(n) return G().fmt(n) end

local RF_GetLeaderboard = nil

local tabColors = {
	Coins    = Color3.fromRGB(255,215,0),
	Pets     = Color3.fromRGB(140,80,255),
	Rebirths = Color3.fromRGB(0,200,255),
}
local tabIcons = { Coins="💰", Pets="🐾", Rebirths="♻️" }

local function buildList(scroll, entries, category, color)
	for _, child in ipairs(scroll:GetChildren()) do
		if not child:IsA("UIListLayout") then child:Destroy() end
	end

	if #entries == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size=UDim2.new(1,0,0,60); empty.BackgroundTransparency=1
		empty.Text="No data yet — keep playing!"; empty.TextColor3=Color3.fromRGB(150,150,180)
		empty.TextScaled=true; empty.Font=Enum.Font.Gotham; empty.Parent=scroll
		return
	end

	for _, entry in ipairs(entries) do
		local row = Instance.new("Frame")
		row.Size=UDim2.new(1,-8,0,52); row.BackgroundColor3=Color3.fromRGB(20,16,36)
		row.BorderSizePixel=0; row.Parent=scroll
		Instance.new("UICorner",row).CornerRadius=UDim.new(0,10)

		-- Rank medal
		local medalColors = {Color3.fromRGB(255,215,0), Color3.fromRGB(192,192,192), Color3.fromRGB(205,127,50)}
		local rankBg = Instance.new("Frame")
		rankBg.Size=UDim2.new(0,48,0,48); rankBg.Position=UDim2.new(0,2,0,2)
		rankBg.BackgroundColor3=medalColors[entry.rank] or Color3.fromRGB(40,35,60)
		rankBg.BackgroundTransparency = entry.rank > 3 and 0.7 or 0.2
		rankBg.BorderSizePixel=0; rankBg.Parent=row
		Instance.new("UICorner",rankBg).CornerRadius=UDim.new(0,8)

		local rankLbl=Instance.new("TextLabel")
		rankLbl.Size=UDim2.new(1,0,1,0); rankLbl.BackgroundTransparency=1
		rankLbl.Text=entry.rank<=3 and ({"🥇","🥈","🥉"})[entry.rank] or ("#"..entry.rank)
		rankLbl.TextColor3=Color3.new(1,1,1); rankLbl.TextScaled=true
		rankLbl.Font=Enum.Font.GothamBold; rankLbl.Parent=rankBg

		-- Name
		local nameLbl=Instance.new("TextLabel")
		nameLbl.Size=UDim2.new(0.55,0,1,0); nameLbl.Position=UDim2.new(0,58,0,0)
		nameLbl.BackgroundTransparency=1; nameLbl.Text=entry.name
		nameLbl.TextColor3=Color3.new(1,1,1); nameLbl.TextScaled=true
		nameLbl.Font=Enum.Font.GothamBold; nameLbl.TextXAlignment=Enum.TextXAlignment.Left
		nameLbl.Parent=row

		-- Score
		local scoreLbl=Instance.new("TextLabel")
		scoreLbl.Size=UDim2.new(0.38,0,1,0); scoreLbl.Position=UDim2.new(0.62,0,0,0)
		scoreLbl.BackgroundTransparency=1; scoreLbl.Text=tabIcons[category].." "..fmt(entry.score)
		scoreLbl.TextColor3=color; scoreLbl.TextScaled=true
		scoreLbl.Font=Enum.Font.GothamBold; scoreLbl.TextXAlignment=Enum.TextXAlignment.Right
		scoreLbl.Parent=row
	end
end

function LeaderboardPanel.Build(data)
	RF_GetLeaderboard = RF_GetLeaderboard
		or game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("GetLeaderboard")

	local screen = Instance.new("ScreenGui")
	screen.Name="LeaderboardPanel"; screen.ResetOnSpawn=false
	screen.DisplayOrder=50; screen.IgnoreGuiInset=true; screen.Parent=PlayerGui

	local panel = Instance.new("Frame")
	panel.Size=UDim2.new(0,520,0,520)
	panel.Position=UDim2.new(0.5,-260,0.5,600)
	panel.BackgroundColor3=Color3.fromRGB(12,9,24)
	panel.BorderSizePixel=0; panel.Parent=screen
	Instance.new("UICorner",panel).CornerRadius=UDim.new(0,16)
	local stroke=Instance.new("UIStroke",panel)
	stroke.Color=Color3.fromRGB(255,215,0); stroke.Thickness=2.5

	TweenService:Create(panel,TweenInfo.new(0.35,Enum.EasingStyle.Back),{
		Position=UDim2.new(0.5,-260,0.5,-260)
	}):Play()

	-- Header
	local header=Instance.new("Frame")
	header.Size=UDim2.new(1,0,0,54); header.BackgroundColor3=Color3.fromRGB(40,28,80)
	header.BorderSizePixel=0; header.Parent=panel
	Instance.new("UICorner",header).CornerRadius=UDim.new(0,16)

	local title=Instance.new("TextLabel")
	title.Size=UDim2.new(1,-60,1,0); title.Position=UDim2.new(0,15,0,0)
	title.BackgroundTransparency=1; title.Text="🏆  Leaderboard"
	title.TextColor3=Color3.fromRGB(255,215,0); title.TextScaled=true
	title.Font=Enum.Font.GothamBold; title.TextXAlignment=Enum.TextXAlignment.Left
	title.Parent=header

	local closeBtn=Instance.new("TextButton")
	closeBtn.Size=UDim2.new(0,40,0,40); closeBtn.Position=UDim2.new(1,-48,0,7)
	closeBtn.BackgroundColor3=Color3.fromRGB(180,40,40); closeBtn.Text="✕"
	closeBtn.TextColor3=Color3.new(1,1,1); closeBtn.TextScaled=true
	closeBtn.Font=Enum.Font.GothamBold; closeBtn.BorderSizePixel=0; closeBtn.Parent=header
	Instance.new("UICorner",closeBtn).CornerRadius=UDim.new(0,8)
	closeBtn.MouseButton1Click:Connect(function() screen:Destroy() end)

	-- Tab buttons
	local tabRow=Instance.new("Frame")
	tabRow.Size=UDim2.new(1,-16,0,40); tabRow.Position=UDim2.new(0,8,0,60)
	tabRow.BackgroundTransparency=1; tabRow.Parent=panel

	local scroll=Instance.new("ScrollingFrame")
	scroll.Size=UDim2.new(1,-16,1,-112); scroll.Position=UDim2.new(0,8,0,108)
	scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0
	scroll.ScrollBarThickness=4; scroll.CanvasSize=UDim2.new(0,0,0,0)
	scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.Parent=panel
	local ll=Instance.new("UIListLayout",scroll); ll.Padding=UDim.new(0,6)

	local activeTab = "Coins"
	local tabBtns   = {}

	local function switchTab(category)
		activeTab = category
		for cat, btn in pairs(tabBtns) do
			btn.BackgroundTransparency = cat==category and 0.1 or 0.55
		end
		-- Fetch
		local ok, entries = pcall(function()
			return RF_GetLeaderboard:InvokeServer(category)
		end)
		buildList(scroll, ok and entries or {}, category, tabColors[category])
	end

	local tabs = {"Coins","Pets","Rebirths"}
	for i, cat in ipairs(tabs) do
		local btn=Instance.new("TextButton")
		btn.Size=UDim2.new(1/#tabs,-6,1,0)
		btn.Position=UDim2.new((i-1)/#tabs,3,0,0)
		btn.BackgroundColor3=tabColors[cat]
		btn.BackgroundTransparency=0.55
		btn.Text=tabIcons[cat].." "..cat
		btn.TextColor3=Color3.new(1,1,1); btn.TextScaled=true
		btn.Font=Enum.Font.GothamBold; btn.BorderSizePixel=0
		btn.Parent=tabRow
		Instance.new("UICorner",btn).CornerRadius=UDim.new(0,8)
		tabBtns[cat]=btn
		btn.MouseButton1Click:Connect(function() switchTab(cat) end)
	end

	switchTab("Coins")
	return screen
end

function LeaderboardPanel.Refresh(data) end

return LeaderboardPanel
