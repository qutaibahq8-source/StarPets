-- StarPets: FusionPanel.lua
-- Place in: StarterPlayerScripts > Client > UI > FusionPanel (ModuleScript)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerGui         = Players.LocalPlayer.PlayerGui

local Remotes       = ReplicatedStorage:WaitForChild("Remotes")
local RF_GetFusion  = Remotes:WaitForChild("GetFusion")
local RE_Fuse       = Remotes:WaitForChild("Fuse")

local RARITY_COLOR = {
	Common=Color3.fromRGB(180,180,180), Uncommon=Color3.fromRGB(90,200,120),
	Rare=Color3.fromRGB(80,150,255), Epic=Color3.fromRGB(180,90,240),
	Legendary=Color3.fromRGB(255,170,40), Mythic=Color3.fromRGB(255,70,120),
}

local FusionPanel = {}

function FusionPanel.Build()
	local screen = Instance.new("ScreenGui")
	screen.Name="FusionPanel"; screen.ResetOnSpawn=false
	screen.DisplayOrder=55; screen.IgnoreGuiInset=true; screen.Parent=PlayerGui

	local panel = Instance.new("Frame")
	panel.Size=UDim2.new(0,520,0,440); panel.Position=UDim2.new(0.5,-260,0.5,-220)
	panel.BackgroundColor3=Color3.fromRGB(18,16,28); panel.BorderSizePixel=0; panel.Parent=screen
	Instance.new("UICorner",panel).CornerRadius=UDim.new(0,14)
	Instance.new("UIStroke",panel).Color=Color3.fromRGB(150,90,240)

	local hd=Instance.new("TextLabel")
	hd.Size=UDim2.new(1,0,0,48); hd.BackgroundColor3=Color3.fromRGB(70,40,110)
	hd.Text="🧬  Pet Fusion"; hd.TextColor3=Color3.new(1,1,1); hd.TextScaled=true
	hd.Font=Enum.Font.GothamBold; hd.BorderSizePixel=0; hd.Parent=panel
	Instance.new("UICorner",hd).CornerRadius=UDim.new(0,14)

	local close=Instance.new("TextButton")
	close.Size=UDim2.new(0,40,0,40); close.Position=UDim2.new(1,-46,0,4)
	close.BackgroundColor3=Color3.fromRGB(200,40,40); close.Text="✕"; close.TextScaled=true
	close.Font=Enum.Font.GothamBold; close.TextColor3=Color3.new(1,1,1); close.BorderSizePixel=0; close.Parent=panel
	Instance.new("UICorner",close).CornerRadius=UDim.new(0,8)

	local sub=Instance.new("TextLabel")
	sub.Size=UDim2.new(1,-16,0,26); sub.Position=UDim2.new(0,8,0,52); sub.BackgroundTransparency=1
	sub.TextColor3=Color3.fromRGB(200,180,240); sub.TextScaled=true; sub.Font=Enum.Font.Gotham
	sub.Text="Combine 3 spare duplicates → 1 stronger pet (+25% power)"; sub.Parent=panel

	local scroll=Instance.new("ScrollingFrame")
	scroll.Size=UDim2.new(1,-16,1,-92); scroll.Position=UDim2.new(0,8,0,86)
	scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0; scroll.ScrollBarThickness=5
	scroll.CanvasSize=UDim2.new(0,0,0,0); scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.Parent=panel
	local list=Instance.new("UIListLayout",scroll); list.Padding=UDim.new(0,8); list.SortOrder=Enum.SortOrder.LayoutOrder

	local empty=Instance.new("TextLabel")
	empty.Size=UDim2.new(1,-20,0,40); empty.Position=UDim2.new(0,10,0,96); empty.BackgroundTransparency=1
	empty.TextColor3=Color3.fromRGB(150,150,170); empty.TextScaled=true; empty.Font=Enum.Font.Gotham
	empty.Text="No duplicates to fuse yet — hatch more eggs!"; empty.Visible=false; empty.Parent=panel

	local alive=true
	close.MouseButton1Click:Connect(function() alive=false; screen:Destroy() end)

	local function render(s)
		for _,c in ipairs(scroll:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
		local items = (s and s.list) or {}
		empty.Visible = (#items == 0)
		for i, it in ipairs(items) do
			local card=Instance.new("Frame")
			card.Size=UDim2.new(1,-6,0,58); card.BackgroundColor3=Color3.fromRGB(34,28,44)
			card.BorderSizePixel=0; card.LayoutOrder=i; card.Parent=scroll
			Instance.new("UICorner",card).CornerRadius=UDim.new(0,10)
			local dot=Instance.new("Frame")
			dot.Size=UDim2.new(0,10,1,-20); dot.Position=UDim2.new(0,10,0,10); dot.BorderSizePixel=0
			dot.BackgroundColor3=RARITY_COLOR[it.rarity] or Color3.fromRGB(180,180,180); dot.Parent=card
			Instance.new("UICorner",dot).CornerRadius=UDim.new(0,4)
			local name=Instance.new("TextLabel")
			name.Size=UDim2.new(0.55,0,1,0); name.Position=UDim2.new(0,30,0,0); name.BackgroundTransparency=1
			name.Text=string.format("%s  (x%d spare)", it.name, it.count)
			name.TextColor3=Color3.new(1,1,1); name.TextScaled=true; name.Font=Enum.Font.GothamBold
			name.TextXAlignment=Enum.TextXAlignment.Left; name.Parent=card
			local btn=Instance.new("TextButton")
			btn.Size=UDim2.new(0,140,0,42); btn.Position=UDim2.new(1,-150,0.5,-21); btn.BorderSizePixel=0
			btn.BackgroundColor3=Color3.fromRGB(150,90,240); btn.Text="🧬 Fuse 3"; btn.TextColor3=Color3.new(1,1,1)
			btn.TextScaled=true; btn.Font=Enum.Font.GothamBold; btn.Parent=card
			Instance.new("UICorner",btn).CornerRadius=UDim.new(0,8)
			btn.MouseButton1Click:Connect(function() RE_Fuse:FireServer(it.name) end)
		end
	end

	task.spawn(function()
		while alive and screen.Parent do
			local ok, s = pcall(function() return RF_GetFusion:InvokeServer() end)
			if ok then render(s) end
			task.wait(1.5)
		end
	end)
	return screen
end

function FusionPanel.Refresh() end
return FusionPanel
