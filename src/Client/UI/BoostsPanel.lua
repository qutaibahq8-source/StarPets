-- StarPets: BoostsPanel.lua
-- Place in: StarterPlayerScripts > Client > UI > BoostsPanel (ModuleScript)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerGui         = Players.LocalPlayer.PlayerGui

local Remotes       = ReplicatedStorage:WaitForChild("Remotes")
local RF_GetBoosts  = Remotes:WaitForChild("GetBoosts")
local RE_BuyBoost   = Remotes:WaitForChild("BuyBoost")

local BoostsPanel = {}

local function clock(s)
	s=math.max(0,math.floor(s)); return string.format("%d:%02d", s//60, s%60)
end

function BoostsPanel.Build()
	local screen = Instance.new("ScreenGui")
	screen.Name="BoostsPanel"; screen.ResetOnSpawn=false
	screen.DisplayOrder=55; screen.IgnoreGuiInset=true; screen.Parent=PlayerGui

	local panel = Instance.new("Frame")
	panel.Size=UDim2.new(0,500,0,420); panel.Position=UDim2.new(0.5,-250,0.5,-210)
	panel.BackgroundColor3=Color3.fromRGB(18,16,28); panel.BorderSizePixel=0; panel.Parent=screen
	Instance.new("UICorner",panel).CornerRadius=UDim.new(0,14)
	Instance.new("UIStroke",panel).Color=Color3.fromRGB(255,170,60)

	local hd=Instance.new("TextLabel")
	hd.Size=UDim2.new(1,0,0,48); hd.BackgroundColor3=Color3.fromRGB(90,55,20)
	hd.Text="⚡  Boosts"; hd.TextColor3=Color3.new(1,1,1); hd.TextScaled=true
	hd.Font=Enum.Font.GothamBold; hd.BorderSizePixel=0; hd.Parent=panel
	Instance.new("UICorner",hd).CornerRadius=UDim.new(0,14)

	local close=Instance.new("TextButton")
	close.Size=UDim2.new(0,40,0,40); close.Position=UDim2.new(1,-46,0,4)
	close.BackgroundColor3=Color3.fromRGB(200,40,40); close.Text="✕"; close.TextScaled=true
	close.Font=Enum.Font.GothamBold; close.TextColor3=Color3.new(1,1,1); close.BorderSizePixel=0; close.Parent=panel
	Instance.new("UICorner",close).CornerRadius=UDim.new(0,8)

	local active=Instance.new("TextLabel")
	active.Size=UDim2.new(1,-16,0,26); active.Position=UDim2.new(0,8,0,52); active.BackgroundTransparency=1
	active.TextColor3=Color3.fromRGB(255,210,140); active.TextScaled=true; active.Font=Enum.Font.GothamBold
	active.Text=""; active.Parent=panel

	local scroll=Instance.new("ScrollingFrame")
	scroll.Size=UDim2.new(1,-16,1,-90); scroll.Position=UDim2.new(0,8,0,84)
	scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0; scroll.ScrollBarThickness=5
	scroll.CanvasSize=UDim2.new(0,0,0,0); scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.Parent=panel
	local list=Instance.new("UIListLayout",scroll); list.Padding=UDim.new(0,8); list.SortOrder=Enum.SortOrder.LayoutOrder

	local alive=true
	close.MouseButton1Click:Connect(function() alive=false; screen:Destroy() end)

	local function render(s)
		for _,c in ipairs(scroll:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
		local act = s.active or {}
		local txt = ""
		for id, left in pairs(act) do txt = txt..id.." ("..clock(left)..")  " end
		active.Text = txt ~= "" and ("Active: "..txt) or "No boosts active"
		for i, b in ipairs(s.boosts or {}) do
			local card=Instance.new("Frame")
			card.Size=UDim2.new(1,-6,0,60); card.BackgroundColor3=Color3.fromRGB(34,28,44)
			card.BorderSizePixel=0; card.LayoutOrder=i; card.Parent=scroll
			Instance.new("UICorner",card).CornerRadius=UDim.new(0,10)
			local name=Instance.new("TextLabel")
			name.Size=UDim2.new(0.6,0,1,0); name.Position=UDim2.new(0,12,0,0); name.BackgroundTransparency=1
			name.Text=b.name; name.TextColor3=Color3.new(1,1,1); name.TextScaled=true
			name.Font=Enum.Font.GothamBold; name.TextXAlignment=Enum.TextXAlignment.Left; name.Parent=card
			local buy=Instance.new("TextButton")
			buy.Size=UDim2.new(0,150,0,42); buy.Position=UDim2.new(1,-160,0.5,-21); buy.BorderSizePixel=0
			buy.BackgroundColor3=Color3.fromRGB(20,120,170); buy.Text="💎 "..b.cost; buy.TextColor3=Color3.new(1,1,1)
			buy.TextScaled=true; buy.Font=Enum.Font.GothamBold; buy.Parent=card
			Instance.new("UICorner",buy).CornerRadius=UDim.new(0,8)
			buy.MouseButton1Click:Connect(function() RE_BuyBoost:FireServer(b.id) end)
		end
	end

	task.spawn(function()
		while alive and screen.Parent do
			local ok, s = pcall(function() return RF_GetBoosts:InvokeServer() end)
			if ok and s then render(s) end
			task.wait(1)
		end
	end)
	return screen
end

function BoostsPanel.Refresh() end
return BoostsPanel
