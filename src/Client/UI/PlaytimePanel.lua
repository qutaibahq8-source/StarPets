-- StarPets: PlaytimePanel.lua
-- Place in: StarterPlayerScripts > Client > UI > PlaytimePanel (ModuleScript)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerGui         = Players.LocalPlayer.PlayerGui

local Remotes        = ReplicatedStorage:WaitForChild("Remotes")
local RF_GetPlaytime = Remotes:WaitForChild("GetPlaytime")
local RE_ClaimPlaytime = Remotes:WaitForChild("ClaimPlaytime")

local PlaytimePanel = {}

local function clock(s)
	s = math.max(0, math.floor(s))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function rewardText(r)
	if r.coins then return "💰 "..tostring(r.coins).." coins"
	elseif r.gems then return "💎 "..tostring(r.gems).." gems"
	elseif r.boost then return "⚡ "..tostring(r.boost).." boost"
	else return "Reward" end
end

function PlaytimePanel.Build()
	local screen = Instance.new("ScreenGui")
	screen.Name="PlaytimePanel"; screen.ResetOnSpawn=false
	screen.DisplayOrder=55; screen.IgnoreGuiInset=true; screen.Parent=PlayerGui

	local panel = Instance.new("Frame")
	panel.Size=UDim2.new(0,500,0,440); panel.Position=UDim2.new(0.5,-250,0.5,-220)
	panel.BackgroundColor3=Color3.fromRGB(18,16,28); panel.BorderSizePixel=0; panel.Parent=screen
	Instance.new("UICorner",panel).CornerRadius=UDim.new(0,14)
	Instance.new("UIStroke",panel).Color=Color3.fromRGB(90,200,255)

	local hd=Instance.new("TextLabel")
	hd.Size=UDim2.new(1,0,0,48); hd.BackgroundColor3=Color3.fromRGB(30,70,110)
	hd.Text="⏱️  Playtime Rewards"; hd.TextColor3=Color3.new(1,1,1); hd.TextScaled=true
	hd.Font=Enum.Font.GothamBold; hd.BorderSizePixel=0; hd.Parent=panel
	Instance.new("UICorner",hd).CornerRadius=UDim.new(0,14)

	local close=Instance.new("TextButton")
	close.Size=UDim2.new(0,40,0,40); close.Position=UDim2.new(1,-46,0,4)
	close.BackgroundColor3=Color3.fromRGB(200,40,40); close.Text="✕"; close.TextScaled=true
	close.Font=Enum.Font.GothamBold; close.TextColor3=Color3.new(1,1,1); close.BorderSizePixel=0; close.Parent=panel
	Instance.new("UICorner",close).CornerRadius=UDim.new(0,8)

	local timeLbl=Instance.new("TextLabel")
	timeLbl.Size=UDim2.new(1,-16,0,26); timeLbl.Position=UDim2.new(0,8,0,52); timeLbl.BackgroundTransparency=1
	timeLbl.TextColor3=Color3.fromRGB(150,220,255); timeLbl.TextScaled=true; timeLbl.Font=Enum.Font.GothamBold
	timeLbl.Text="Played: 0:00"; timeLbl.Parent=panel

	local scroll=Instance.new("ScrollingFrame")
	scroll.Size=UDim2.new(1,-16,1,-92); scroll.Position=UDim2.new(0,8,0,84)
	scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0; scroll.ScrollBarThickness=5
	scroll.CanvasSize=UDim2.new(0,0,0,0); scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.Parent=panel
	local list=Instance.new("UIListLayout",scroll); list.Padding=UDim.new(0,8); list.SortOrder=Enum.SortOrder.LayoutOrder

	local alive=true
	close.MouseButton1Click:Connect(function() alive=false; screen:Destroy() end)

	local function render(s)
		for _,c in ipairs(scroll:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
		local elapsed = (s and s.elapsed) or 0
		timeLbl.Text = "Played this session: "..clock(elapsed)
		for i, r in ipairs((s and s.rewards) or {}) do
			local card=Instance.new("Frame")
			card.Size=UDim2.new(1,-6,0,56); card.LayoutOrder=i; card.BorderSizePixel=0
			card.BackgroundColor3 = r.claimed and Color3.fromRGB(26,40,30)
				or (r.ready and Color3.fromRGB(34,52,44) or Color3.fromRGB(30,28,42))
			card.Parent=scroll
			Instance.new("UICorner",card).CornerRadius=UDim.new(0,10)
			local info=Instance.new("TextLabel")
			info.Size=UDim2.new(0.58,0,1,0); info.Position=UDim2.new(0,12,0,0); info.BackgroundTransparency=1
			info.Text=clock(r.seconds).."  →  "..rewardText(r)
			info.TextColor3=Color3.new(1,1,1); info.TextScaled=true; info.Font=Enum.Font.GothamBold
			info.TextXAlignment=Enum.TextXAlignment.Left; info.Parent=card
			local btn=Instance.new("TextButton")
			btn.Size=UDim2.new(0,150,0,42); btn.Position=UDim2.new(1,-160,0.5,-21); btn.BorderSizePixel=0
			btn.TextColor3=Color3.new(1,1,1); btn.TextScaled=true; btn.Font=Enum.Font.GothamBold; btn.Parent=card
			Instance.new("UICorner",btn).CornerRadius=UDim.new(0,8)
			if r.claimed then
				btn.Text="✓ Claimed"; btn.BackgroundColor3=Color3.fromRGB(40,90,50); btn.AutoButtonColor=false
			elseif r.ready then
				btn.Text="CLAIM"; btn.BackgroundColor3=Color3.fromRGB(40,170,90)
				btn.MouseButton1Click:Connect(function() RE_ClaimPlaytime:FireServer(i) end)
			else
				btn.Text=clock(r.seconds - elapsed); btn.BackgroundColor3=Color3.fromRGB(50,46,66); btn.AutoButtonColor=false
			end
		end
	end

	task.spawn(function()
		while alive and screen.Parent do
			local ok, s = pcall(function() return RF_GetPlaytime:InvokeServer() end)
			if ok then render(s) end
			task.wait(1)
		end
	end)
	return screen
end

function PlaytimePanel.Refresh() end
return PlaytimePanel
