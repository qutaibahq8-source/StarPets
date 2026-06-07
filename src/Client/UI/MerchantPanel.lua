-- StarPets: MerchantPanel.lua
-- Place in: StarterPlayerScripts > Client > UI > MerchantPanel (ModuleScript)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerGui         = Players.LocalPlayer.PlayerGui

local Remotes        = ReplicatedStorage:WaitForChild("Remotes")
local RF_GetMerchant = Remotes:WaitForChild("GetMerchant")
local RE_BuyMerchant = Remotes:WaitForChild("BuyMerchant")

local MerchantPanel = {}

local function fmt(n)
	if n>=1e6 then return string.format("%.1fM",n/1e6)
	elseif n>=1e3 then return string.format("%.1fK",n/1e3) else return tostring(math.floor(n)) end
end
local function clock(s)
	s = math.max(0, math.floor(s)); return string.format("%d:%02d", s//60, s%60)
end

function MerchantPanel.Build()
	local screen = Instance.new("ScreenGui")
	screen.Name="MerchantPanel"; screen.ResetOnSpawn=false
	screen.DisplayOrder=55; screen.IgnoreGuiInset=true; screen.Parent=PlayerGui

	local panel = Instance.new("Frame")
	panel.Size=UDim2.new(0,520,0,460); panel.Position=UDim2.new(0.5,-260,0.5,-230)
	panel.BackgroundColor3=Color3.fromRGB(24,16,30); panel.BorderSizePixel=0; panel.Parent=screen
	Instance.new("UICorner",panel).CornerRadius=UDim.new(0,14)
	local st=Instance.new("UIStroke",panel); st.Color=Color3.fromRGB(255,180,90); st.Thickness=2

	local hd=Instance.new("TextLabel")
	hd.Size=UDim2.new(1,0,0,50); hd.BackgroundColor3=Color3.fromRGB(90,55,25)
	hd.Text="🛒  Traveling Merchant"; hd.TextColor3=Color3.new(1,1,1); hd.TextScaled=true
	hd.Font=Enum.Font.GothamBold; hd.BorderSizePixel=0; hd.Parent=panel
	Instance.new("UICorner",hd).CornerRadius=UDim.new(0,14)

	local close=Instance.new("TextButton")
	close.Size=UDim2.new(0,40,0,40); close.Position=UDim2.new(1,-48,0,5)
	close.BackgroundColor3=Color3.fromRGB(200,40,40); close.Text="✕"; close.TextScaled=true
	close.Font=Enum.Font.GothamBold; close.TextColor3=Color3.new(1,1,1); close.BorderSizePixel=0; close.Parent=panel
	Instance.new("UICorner",close).CornerRadius=UDim.new(0,8)

	local timer=Instance.new("TextLabel")
	timer.Size=UDim2.new(1,-16,0,24); timer.Position=UDim2.new(0,8,0,54); timer.BackgroundTransparency=1
	timer.TextColor3=Color3.fromRGB(255,210,140); timer.TextScaled=true; timer.Font=Enum.Font.GothamBold
	timer.Text=""; timer.Parent=panel

	local scroll=Instance.new("ScrollingFrame")
	scroll.Size=UDim2.new(1,-16,1,-90); scroll.Position=UDim2.new(0,8,0,84)
	scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0; scroll.ScrollBarThickness=5
	scroll.CanvasSize=UDim2.new(0,0,0,0); scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.Parent=panel
	local list=Instance.new("UIListLayout",scroll); list.Padding=UDim.new(0,8); list.SortOrder=Enum.SortOrder.LayoutOrder

	local alive=true
	close.MouseButton1Click:Connect(function() alive=false; screen:Destroy() end)

	local function render(stateData)
		for _,c in ipairs(scroll:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
		if not stateData.active then
			timer.Text = "Away — returns in "..clock(stateData.secondsLeft)
			local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-6,0,80); l.BackgroundTransparency=1
			l.Text="The merchant is travelling...\nCheck back soon!"; l.TextColor3=Color3.fromRGB(170,170,180)
			l.TextScaled=true; l.Font=Enum.Font.Gotham; l.Parent=scroll
			return
		end
		timer.Text = "Leaving in "..clock(stateData.secondsLeft).."  —  grab it while you can!"
		for i, item in ipairs(stateData.stock or {}) do
			local card=Instance.new("Frame")
			card.Size=UDim2.new(1,-6,0,66); card.BackgroundColor3=Color3.fromRGB(36,26,44)
			card.BorderSizePixel=0; card.LayoutOrder=i; card.Parent=scroll
			Instance.new("UICorner",card).CornerRadius=UDim.new(0,10)

			local name=Instance.new("TextLabel")
			name.Size=UDim2.new(0.6,0,1,0); name.Position=UDim2.new(0,12,0,0); name.BackgroundTransparency=1
			name.Text=item.label or "Item"; name.TextColor3=Color3.new(1,1,1); name.TextScaled=true
			name.Font=Enum.Font.GothamBold; name.TextXAlignment=Enum.TextXAlignment.Left; name.Parent=card

			local buy=Instance.new("TextButton")
			buy.Size=UDim2.new(0,160,0,46); buy.Position=UDim2.new(1,-170,0.5,-23); buy.BorderSizePixel=0
			buy.BackgroundColor3=(item.cur=="Gems") and Color3.fromRGB(20,120,170) or Color3.fromRGB(150,110,20)
			buy.Text=(item.cur=="Gems" and "💎 " or "💰 ")..fmt(item.cost); buy.TextColor3=Color3.new(1,1,1)
			buy.TextScaled=true; buy.Font=Enum.Font.GothamBold; buy.Parent=card
			Instance.new("UICorner",buy).CornerRadius=UDim.new(0,8)
			buy.MouseButton1Click:Connect(function()
				RE_BuyMerchant:FireServer(i)
			end)
		end
	end

	-- live refresh loop while panel is open
	task.spawn(function()
		while alive and screen.Parent do
			local ok, s = pcall(function() return RF_GetMerchant:InvokeServer() end)
			if ok and s then render(s) end
			task.wait(1)
		end
	end)

	return screen
end

function MerchantPanel.Refresh() end
return MerchantPanel
