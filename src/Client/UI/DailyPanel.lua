-- StarPets: DailyPanel.lua
-- Place in: StarterPlayerScripts > Client > UI > DailyPanel (ModuleScript)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerGui         = Players.LocalPlayer.PlayerGui

local Remotes       = ReplicatedStorage:WaitForChild("Remotes")
local RF_GetDaily   = Remotes:WaitForChild("GetDaily")
local RE_ClaimDaily = Remotes:WaitForChild("ClaimDaily")

local DailyPanel = {}

local function fmt(n)
	if n>=1e6 then return string.format("%.1fM",n/1e6)
	elseif n>=1e3 then return string.format("%.1fK",n/1e3) else return tostring(math.floor(n)) end
end
local function clock(s)
	s=math.max(0,math.floor(s)); return string.format("%dh %dm", s//3600, (s%3600)//60)
end
local function rewardText(r)
	r=r or {}
	if r.coins then return "💰 "..fmt(r.coins) end
	if r.gems then return "💎 "..fmt(r.gems) end
	return ""
end

function DailyPanel.Build()
	local screen = Instance.new("ScreenGui")
	screen.Name="DailyPanel"; screen.ResetOnSpawn=false
	screen.DisplayOrder=55; screen.IgnoreGuiInset=true; screen.Parent=PlayerGui

	local panel = Instance.new("Frame")
	panel.Size=UDim2.new(0,560,0,330); panel.Position=UDim2.new(0.5,-280,0.5,-165)
	panel.BackgroundColor3=Color3.fromRGB(16,18,30); panel.BorderSizePixel=0; panel.Parent=screen
	Instance.new("UICorner",panel).CornerRadius=UDim.new(0,14)
	Instance.new("UIStroke",panel).Color=Color3.fromRGB(255,210,90)

	local hd=Instance.new("TextLabel")
	hd.Size=UDim2.new(1,0,0,48); hd.BackgroundColor3=Color3.fromRGB(80,60,25)
	hd.Text="🎁  Daily Rewards"; hd.TextColor3=Color3.new(1,1,1); hd.TextScaled=true
	hd.Font=Enum.Font.GothamBold; hd.BorderSizePixel=0; hd.Parent=panel
	Instance.new("UICorner",hd).CornerRadius=UDim.new(0,14)

	local close=Instance.new("TextButton")
	close.Size=UDim2.new(0,40,0,40); close.Position=UDim2.new(1,-46,0,4)
	close.BackgroundColor3=Color3.fromRGB(200,40,40); close.Text="✕"; close.TextScaled=true
	close.Font=Enum.Font.GothamBold; close.TextColor3=Color3.new(1,1,1); close.BorderSizePixel=0; close.Parent=panel
	Instance.new("UICorner",close).CornerRadius=UDim.new(0,8)
	close.MouseButton1Click:Connect(function() screen:Destroy() end)

	local row=Instance.new("Frame")
	row.Size=UDim2.new(1,-20,0,150); row.Position=UDim2.new(0,10,0,58); row.BackgroundTransparency=1; row.Parent=panel
	local rl=Instance.new("UIListLayout",row); rl.FillDirection=Enum.FillDirection.Horizontal
	rl.Padding=UDim.new(0,6); rl.HorizontalAlignment=Enum.HorizontalAlignment.Center

	local status=Instance.new("TextLabel")
	status.Size=UDim2.new(1,-20,0,28); status.Position=UDim2.new(0,10,0,212); status.BackgroundTransparency=1
	status.TextColor3=Color3.fromRGB(255,220,150); status.TextScaled=true; status.Font=Enum.Font.GothamBold
	status.Text=""; status.Parent=panel

	local claim=Instance.new("TextButton")
	claim.Size=UDim2.new(1,-20,0,52); claim.Position=UDim2.new(0,10,1,-60); claim.BorderSizePixel=0
	claim.TextColor3=Color3.new(1,1,1); claim.TextScaled=true; claim.Font=Enum.Font.GothamBold; claim.Parent=panel
	Instance.new("UICorner",claim).CornerRadius=UDim.new(0,8)

	local function render(s)
		for _,c in ipairs(row:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
		for day, r in ipairs(s.rewards or {}) do
			local isNext = (day == s.nextDay)
			local claimed = (day < s.nextDay) or (day <= (s.streak or 0) and not s.ready)
			local card=Instance.new("Frame"); card.Size=UDim2.new(0,70,1,0)
			card.BackgroundColor3 = isNext and Color3.fromRGB(70,55,25) or Color3.fromRGB(26,28,42)
			card.BorderSizePixel=0; card.LayoutOrder=day; card.Parent=row
			Instance.new("UICorner",card).CornerRadius=UDim.new(0,8)
			if isNext then local st=Instance.new("UIStroke",card); st.Color=Color3.fromRGB(255,210,90); st.Thickness=2 end
			local d=Instance.new("TextLabel"); d.Size=UDim2.new(1,0,0,24); d.BackgroundTransparency=1
			d.Text="Day "..day; d.TextColor3=Color3.fromRGB(200,200,210); d.TextScaled=true; d.Font=Enum.Font.GothamBold; d.Parent=card
			local rw=Instance.new("TextLabel"); rw.Size=UDim2.new(1,-6,0,40); rw.Position=UDim2.new(0,3,0,30); rw.BackgroundTransparency=1
			rw.Text=rewardText(r); rw.TextColor3=Color3.new(1,1,1); rw.TextScaled=true; rw.Font=Enum.Font.GothamBold; rw.TextWrapped=true; rw.Parent=card
		end
		status.Text = "Streak: "..(s.streak or 0).." days"
		if s.ready then
			claim.BackgroundColor3=Color3.fromRGB(50,170,90); claim.Text="Claim Day "..(s.nextDay or 1).."!"; claim.Active=true
		else
			claim.BackgroundColor3=Color3.fromRGB(60,60,75); claim.Text="Next in "..clock(s.secondsLeft or 0); claim.Active=false
		end
	end

	local function refresh()
		local ok, s = pcall(function() return RF_GetDaily:InvokeServer() end)
		if ok and s then render(s) end
	end
	claim.MouseButton1Click:Connect(function()
		if claim.Active then RE_ClaimDaily:FireServer(); task.wait(0.3); refresh() end
	end)
	refresh()
	return screen
end

function DailyPanel.Refresh() end
return DailyPanel
