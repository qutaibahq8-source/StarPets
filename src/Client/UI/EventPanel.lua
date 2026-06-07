-- StarPets: EventPanel.lua
-- Place in: StarterPlayerScripts > Client > UI > EventPanel (ModuleScript)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerGui         = Players.LocalPlayer.PlayerGui

local Remotes      = ReplicatedStorage:WaitForChild("Remotes")
local RF_GetEvent  = Remotes:WaitForChild("GetEvent")
local RE_BuyEvent  = Remotes:WaitForChild("BuyEvent")

local EventPanel = {}

local function fmt(n)
	if n>=1e6 then return string.format("%.1fM",n/1e6)
	elseif n>=1e3 then return string.format("%.1fK",n/1e3) else return tostring(math.floor(n)) end
end

function EventPanel.Build()
	local screen = Instance.new("ScreenGui")
	screen.Name="EventPanel"; screen.ResetOnSpawn=false
	screen.DisplayOrder=55; screen.IgnoreGuiInset=true; screen.Parent=PlayerGui

	local panel = Instance.new("Frame")
	panel.Size=UDim2.new(0,520,0,460); panel.Position=UDim2.new(0.5,-260,0.5,-230)
	panel.BackgroundColor3=Color3.fromRGB(20,16,32); panel.BorderSizePixel=0; panel.Parent=screen
	Instance.new("UICorner",panel).CornerRadius=UDim.new(0,14)
	local st=Instance.new("UIStroke",panel); st.Color=Color3.fromRGB(255,120,200); st.Thickness=2

	local hd=Instance.new("TextLabel")
	hd.Size=UDim2.new(1,0,0,50); hd.BackgroundColor3=Color3.fromRGB(120,40,90)
	hd.Text="🎉  Event"; hd.TextColor3=Color3.new(1,1,1); hd.TextScaled=true
	hd.Font=Enum.Font.GothamBold; hd.BorderSizePixel=0; hd.Parent=panel
	Instance.new("UICorner",hd).CornerRadius=UDim.new(0,14)

	local close=Instance.new("TextButton")
	close.Size=UDim2.new(0,40,0,40); close.Position=UDim2.new(1,-48,0,5)
	close.BackgroundColor3=Color3.fromRGB(200,40,40); close.Text="✕"; close.TextScaled=true
	close.Font=Enum.Font.GothamBold; close.TextColor3=Color3.new(1,1,1); close.BorderSizePixel=0; close.Parent=panel
	Instance.new("UICorner",close).CornerRadius=UDim.new(0,8)

	local tokens=Instance.new("TextLabel")
	tokens.Size=UDim2.new(1,-16,0,26); tokens.Position=UDim2.new(0,8,0,54); tokens.BackgroundTransparency=1
	tokens.TextColor3=Color3.fromRGB(255,220,150); tokens.TextScaled=true; tokens.Font=Enum.Font.GothamBold
	tokens.Text=""; tokens.Parent=panel

	local scroll=Instance.new("ScrollingFrame")
	scroll.Size=UDim2.new(1,-16,1,-90); scroll.Position=UDim2.new(0,8,0,84)
	scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0; scroll.ScrollBarThickness=5
	scroll.CanvasSize=UDim2.new(0,0,0,0); scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.Parent=panel
	local list=Instance.new("UIListLayout",scroll); list.Padding=UDim.new(0,8); list.SortOrder=Enum.SortOrder.LayoutOrder

	local alive=true
	close.MouseButton1Click:Connect(function() alive=false; screen:Destroy() end)

	local function render(s)
		for _,c in ipairs(scroll:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
		if not s.active then
			hd.Text="🎉  Event"; tokens.Text="No event running right now"
			local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-6,0,80); l.BackgroundTransparency=1
			l.Text="Check back later for limited-time events\nwith exclusive pets!"; l.TextColor3=Color3.fromRGB(170,170,180)
			l.TextScaled=true; l.Font=Enum.Font.Gotham; l.Parent=scroll
			return
		end
		hd.Text=s.name
		tokens.Text="You have "..(s.tokenIcon or "🎟️").." "..fmt(s.tokens).." "..(s.tokenName or "Tokens")
		for i, item in ipairs(s.shop or {}) do
			local card=Instance.new("Frame")
			card.Size=UDim2.new(1,-6,0,66); card.BackgroundColor3=Color3.fromRGB(40,26,48)
			card.BorderSizePixel=0; card.LayoutOrder=i; card.Parent=scroll
			Instance.new("UICorner",card).CornerRadius=UDim.new(0,10)
			local name=Instance.new("TextLabel")
			name.Size=UDim2.new(0.6,0,1,0); name.Position=UDim2.new(0,12,0,0); name.BackgroundTransparency=1
			name.Text=item.label or "Item"; name.TextColor3=Color3.new(1,1,1); name.TextScaled=true
			name.Font=Enum.Font.GothamBold; name.TextXAlignment=Enum.TextXAlignment.Left; name.Parent=card
			local buy=Instance.new("TextButton")
			buy.Size=UDim2.new(0,160,0,46); buy.Position=UDim2.new(1,-170,0.5,-23); buy.BorderSizePixel=0
			buy.BackgroundColor3=Color3.fromRGB(180,60,140)
			buy.Text=(s.tokenIcon or "🎟️").." "..fmt(item.cost); buy.TextColor3=Color3.new(1,1,1)
			buy.TextScaled=true; buy.Font=Enum.Font.GothamBold; buy.Parent=card
			Instance.new("UICorner",buy).CornerRadius=UDim.new(0,8)
			buy.MouseButton1Click:Connect(function() RE_BuyEvent:FireServer(i) end)
		end
	end

	task.spawn(function()
		while alive and screen.Parent do
			local ok, s = pcall(function() return RF_GetEvent:InvokeServer() end)
			if ok and s then render(s) end
			task.wait(1.5)
		end
	end)

	return screen
end

function EventPanel.Refresh() end
return EventPanel
