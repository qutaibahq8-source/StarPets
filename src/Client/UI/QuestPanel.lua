-- StarPets: QuestPanel.lua
-- Place in: StarterPlayerScripts > Client > UI > QuestPanel (ModuleScript)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerGui         = Players.LocalPlayer.PlayerGui

local Remotes      = ReplicatedStorage:WaitForChild("Remotes")
local RF_GetQuests = Remotes:WaitForChild("GetQuests")
local RE_ClaimQuest= Remotes:WaitForChild("ClaimQuest")

local QuestPanel = {}

local function fmt(n)
	if n>=1e6 then return string.format("%.1fM",n/1e6)
	elseif n>=1e3 then return string.format("%.1fK",n/1e3) else return tostring(math.floor(n)) end
end

local function rewardText(r)
	r = r or {}
	if r.coins then return "💰 "..fmt(r.coins) end
	if r.gems  then return "💎 "..fmt(r.gems) end
	if r.pet   then return "🐾 "..r.pet end
	return ""
end

function QuestPanel.Build()
	local screen = Instance.new("ScreenGui")
	screen.Name="QuestPanel"; screen.ResetOnSpawn=false
	screen.DisplayOrder=55; screen.IgnoreGuiInset=true; screen.Parent=PlayerGui

	local panel = Instance.new("Frame")
	panel.Size=UDim2.new(0,560,0,500); panel.Position=UDim2.new(0.5,-280,0.5,-250)
	panel.BackgroundColor3=Color3.fromRGB(16,13,28); panel.BorderSizePixel=0; panel.Parent=screen
	Instance.new("UICorner",panel).CornerRadius=UDim.new(0,14)
	local st=Instance.new("UIStroke",panel); st.Color=Color3.fromRGB(120,200,255); st.Thickness=2

	local hd=Instance.new("TextLabel")
	hd.Size=UDim2.new(1,0,0,50); hd.BackgroundColor3=Color3.fromRGB(30,50,90)
	hd.Text="📜  Quests"; hd.TextColor3=Color3.new(1,1,1); hd.TextScaled=true
	hd.Font=Enum.Font.GothamBold; hd.BorderSizePixel=0; hd.Parent=panel
	Instance.new("UICorner",hd).CornerRadius=UDim.new(0,14)

	local close=Instance.new("TextButton")
	close.Size=UDim2.new(0,40,0,40); close.Position=UDim2.new(1,-48,0,5)
	close.BackgroundColor3=Color3.fromRGB(200,40,40); close.Text="✕"; close.TextScaled=true
	close.Font=Enum.Font.GothamBold; close.TextColor3=Color3.new(1,1,1); close.BorderSizePixel=0; close.Parent=panel
	Instance.new("UICorner",close).CornerRadius=UDim.new(0,8)
	close.MouseButton1Click:Connect(function() screen:Destroy() end)

	local scroll=Instance.new("ScrollingFrame")
	scroll.Size=UDim2.new(1,-16,1,-60); scroll.Position=UDim2.new(0,8,0,56)
	scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0; scroll.ScrollBarThickness=5
	scroll.CanvasSize=UDim2.new(0,0,0,0); scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.Parent=panel
	local list=Instance.new("UIListLayout",scroll); list.Padding=UDim.new(0,8); list.SortOrder=Enum.SortOrder.LayoutOrder

	local function render()
		for _,c in ipairs(scroll:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
		local quests = RF_GetQuests:InvokeServer()
		for i, q in ipairs(quests or {}) do
			local card=Instance.new("Frame")
			card.Size=UDim2.new(1,-6,0,84); card.BackgroundColor3=Color3.fromRGB(24,20,40)
			card.BorderSizePixel=0; card.LayoutOrder=i; card.Parent=scroll
			Instance.new("UICorner",card).CornerRadius=UDim.new(0,10)

			local name=Instance.new("TextLabel")
			name.Size=UDim2.new(0.62,0,0,26); name.Position=UDim2.new(0,12,0,8); name.BackgroundTransparency=1
			name.Text=q.name; name.TextColor3=Color3.new(1,1,1); name.TextScaled=true
			name.Font=Enum.Font.GothamBold; name.TextXAlignment=Enum.TextXAlignment.Left; name.Parent=card

			local desc=Instance.new("TextLabel")
			desc.Size=UDim2.new(0.62,0,0,20); desc.Position=UDim2.new(0,12,0,34); desc.BackgroundTransparency=1
			desc.Text=q.desc.."   ("..fmt(q.progress).."/"..fmt(q.goal)..")"; desc.TextColor3=Color3.fromRGB(170,170,190)
			desc.TextScaled=true; desc.Font=Enum.Font.Gotham; desc.TextXAlignment=Enum.TextXAlignment.Left; desc.Parent=card

			-- progress bar
			local barBg=Instance.new("Frame")
			barBg.Size=UDim2.new(0.6,0,0,10); barBg.Position=UDim2.new(0,12,0,60)
			barBg.BackgroundColor3=Color3.fromRGB(45,42,62); barBg.BorderSizePixel=0; barBg.Parent=card
			Instance.new("UICorner",barBg).CornerRadius=UDim.new(1,0)
			local fill=Instance.new("Frame")
			fill.Size=UDim2.new(math.clamp(q.progress/q.goal,0,1),0,1,0)
			fill.BackgroundColor3=q.done and Color3.fromRGB(60,200,90) or Color3.fromRGB(90,160,255)
			fill.BorderSizePixel=0; fill.Parent=barBg
			Instance.new("UICorner",fill).CornerRadius=UDim.new(1,0)

			local btn=Instance.new("TextButton")
			btn.Size=UDim2.new(0,140,0,60); btn.Position=UDim2.new(1,-150,0,12); btn.BorderSizePixel=0
			btn.TextColor3=Color3.new(1,1,1); btn.TextScaled=true; btn.Font=Enum.Font.GothamBold; btn.Parent=card
			Instance.new("UICorner",btn).CornerRadius=UDim.new(0,8)
			if q.claimed then
				btn.BackgroundColor3=Color3.fromRGB(50,55,70); btn.Text="✅ Claimed"; btn.Active=false
			elseif q.done then
				btn.BackgroundColor3=Color3.fromRGB(50,170,80); btn.Text="Claim\n"..rewardText(q.reward)
				btn.MouseButton1Click:Connect(function()
					RE_ClaimQuest:FireServer(q.id)
					task.wait(0.3); render()
				end)
			else
				btn.BackgroundColor3=Color3.fromRGB(40,38,58); btn.Text=rewardText(q.reward); btn.Active=false
			end
		end
	end
	render()
	return screen
end

function QuestPanel.Refresh() end
return QuestPanel
