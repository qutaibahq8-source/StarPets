-- StarPets: CodesPanel.lua
-- Place in: StarterPlayerScripts > Client > UI > CodesPanel (ModuleScript)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerGui         = Players.LocalPlayer.PlayerGui

local Remotes       = ReplicatedStorage:WaitForChild("Remotes")
local RE_RedeemCode = Remotes:WaitForChild("RedeemCode")

local CodesPanel = {}

function CodesPanel.Build()
	local screen = Instance.new("ScreenGui")
	screen.Name="CodesPanel"; screen.ResetOnSpawn=false
	screen.DisplayOrder=55; screen.IgnoreGuiInset=true; screen.Parent=PlayerGui

	local panel = Instance.new("Frame")
	panel.Size=UDim2.new(0,460,0,260); panel.Position=UDim2.new(0.5,-230,0.5,-130)
	panel.BackgroundColor3=Color3.fromRGB(16,18,30); panel.BorderSizePixel=0; panel.Parent=screen
	Instance.new("UICorner",panel).CornerRadius=UDim.new(0,14)
	Instance.new("UIStroke",panel).Color=Color3.fromRGB(90,200,150)

	local hd=Instance.new("TextLabel")
	hd.Size=UDim2.new(1,0,0,50); hd.BackgroundColor3=Color3.fromRGB(30,70,55)
	hd.Text="🎁  Codes"; hd.TextColor3=Color3.new(1,1,1); hd.TextScaled=true
	hd.Font=Enum.Font.GothamBold; hd.BorderSizePixel=0; hd.Parent=panel
	Instance.new("UICorner",hd).CornerRadius=UDim.new(0,14)

	local close=Instance.new("TextButton")
	close.Size=UDim2.new(0,40,0,40); close.Position=UDim2.new(1,-48,0,5)
	close.BackgroundColor3=Color3.fromRGB(200,40,40); close.Text="✕"; close.TextScaled=true
	close.Font=Enum.Font.GothamBold; close.TextColor3=Color3.new(1,1,1); close.BorderSizePixel=0; close.Parent=panel
	Instance.new("UICorner",close).CornerRadius=UDim.new(0,8)
	close.MouseButton1Click:Connect(function() screen:Destroy() end)

	local info=Instance.new("TextLabel")
	info.Size=UDim2.new(1,-30,0,30); info.Position=UDim2.new(0,15,0,62); info.BackgroundTransparency=1
	info.Text="Enter a code for free rewards:"; info.TextColor3=Color3.fromRGB(200,200,210)
	info.TextScaled=true; info.Font=Enum.Font.Gotham; info.TextXAlignment=Enum.TextXAlignment.Left; info.Parent=panel

	local box=Instance.new("TextBox")
	box.Size=UDim2.new(1,-30,0,52); box.Position=UDim2.new(0,15,0,98)
	box.BackgroundColor3=Color3.fromRGB(30,32,46); box.PlaceholderText="Type a code..."; box.Text=""
	box.TextColor3=Color3.new(1,1,1); box.TextScaled=true; box.Font=Enum.Font.GothamBold
	box.BorderSizePixel=0; box.ClearTextOnFocus=false; box.Parent=panel
	Instance.new("UICorner",box).CornerRadius=UDim.new(0,8)

	local redeem=Instance.new("TextButton")
	redeem.Size=UDim2.new(1,-30,0,54); redeem.Position=UDim2.new(0,15,0,160)
	redeem.BackgroundColor3=Color3.fromRGB(50,170,90); redeem.Text="Redeem"; redeem.TextColor3=Color3.new(1,1,1)
	redeem.TextScaled=true; redeem.Font=Enum.Font.GothamBold; redeem.BorderSizePixel=0; redeem.Parent=panel
	Instance.new("UICorner",redeem).CornerRadius=UDim.new(0,8)
	redeem.MouseButton1Click:Connect(function()
		if box.Text ~= "" then RE_RedeemCode:FireServer(box.Text); box.Text = "" end
	end)

	return screen
end

function CodesPanel.Refresh() end
return CodesPanel
