-- StarPets: PetIndexPanel.lua  (Pet Index / collection)
-- Place in: StarterPlayerScripts > Client > UI > PetIndexPanel (ModuleScript)

local Players   = game:GetService("Players")
local PlayerGui = Players.LocalPlayer.PlayerGui

local PetIndexPanel = {}
local function G() return _G.MysticPets end

function PetIndexPanel.Build(data)
	local cfg = G().GameConfig
	data = data or (G().getData and G().getData()) or {}

	-- count how many of each pet the player owns
	local ownedCount = {}
	for _, p in ipairs(data.Pets or {}) do
		ownedCount[p.name] = (ownedCount[p.name] or 0) + 1
	end

	local screen = Instance.new("ScreenGui")
	screen.Name="PetIndexPanel"; screen.ResetOnSpawn=false
	screen.DisplayOrder=55; screen.IgnoreGuiInset=true; screen.Parent=PlayerGui

	local panel = Instance.new("Frame")
	panel.Size=UDim2.new(0,600,0,500); panel.Position=UDim2.new(0.5,-300,0.5,-250)
	panel.BackgroundColor3=Color3.fromRGB(16,14,26); panel.BorderSizePixel=0; panel.Parent=screen
	Instance.new("UICorner",panel).CornerRadius=UDim.new(0,14)
	Instance.new("UIStroke",panel).Color=Color3.fromRGB(150,120,255)

	local total, have = #cfg.Pets, 0
	for _, pet in ipairs(cfg.Pets) do if ownedCount[pet.name] then have = have + 1 end end

	local hd=Instance.new("TextLabel")
	hd.Size=UDim2.new(1,0,0,50); hd.BackgroundColor3=Color3.fromRGB(50,30,90)
	hd.Text="📖  Pet Index   ("..have.."/"..total..")"; hd.TextColor3=Color3.new(1,1,1)
	hd.TextScaled=true; hd.Font=Enum.Font.GothamBold; hd.BorderSizePixel=0; hd.Parent=panel
	Instance.new("UICorner",hd).CornerRadius=UDim.new(0,14)

	local close=Instance.new("TextButton")
	close.Size=UDim2.new(0,40,0,40); close.Position=UDim2.new(1,-48,0,5)
	close.BackgroundColor3=Color3.fromRGB(200,40,40); close.Text="✕"; close.TextScaled=true
	close.Font=Enum.Font.GothamBold; close.TextColor3=Color3.new(1,1,1); close.BorderSizePixel=0; close.Parent=panel
	Instance.new("UICorner",close).CornerRadius=UDim.new(0,8)
	close.MouseButton1Click:Connect(function() screen:Destroy() end)

	local scroll=Instance.new("ScrollingFrame")
	scroll.Size=UDim2.new(1,-16,1,-60); scroll.Position=UDim2.new(0,8,0,56)
	scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0; scroll.ScrollBarThickness=6
	scroll.CanvasSize=UDim2.new(0,0,0,0); scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.Parent=panel
	local grid=Instance.new("UIGridLayout"); grid.CellSize=UDim2.new(0,138,0,120)
	grid.CellPadding=UDim2.new(0,8,0,8); grid.Parent=scroll

	for i, pet in ipairs(cfg.Pets) do
		local rar = cfg.Rarities and cfg.Rarities[pet.rarity]
		local rcol = (rar and rar.color) or Color3.fromRGB(200,200,200)
		local owned = ownedCount[pet.name]

		local card=Instance.new("Frame")
		card.BackgroundColor3=owned and Color3.fromRGB(28,24,44) or Color3.fromRGB(18,16,28)
		card.BorderSizePixel=0; card.LayoutOrder=i; card.Parent=scroll
		Instance.new("UICorner",card).CornerRadius=UDim.new(0,10)
		local st=Instance.new("UIStroke",card); st.Color=rcol; st.Transparency=owned and 0.2 or 0.7

		-- color swatch (the pet's color) as a quick icon
		local swatch=Instance.new("Frame")
		swatch.Size=UDim2.new(0,54,0,54); swatch.Position=UDim2.new(0.5,-27,0,10)
		swatch.BackgroundColor3=owned and (pet.color or rcol) or Color3.fromRGB(40,40,50)
		swatch.BorderSizePixel=0; swatch.Parent=card
		Instance.new("UICorner",swatch).CornerRadius=UDim.new(1,0)
		if not owned then
			local q=Instance.new("TextLabel"); q.Size=UDim2.new(1,0,1,0); q.BackgroundTransparency=1
			q.Text="?"; q.TextColor3=Color3.fromRGB(120,120,140); q.TextScaled=true; q.Font=Enum.Font.GothamBold; q.Parent=swatch
		end

		local name=Instance.new("TextLabel")
		name.Size=UDim2.new(1,-6,0,22); name.Position=UDim2.new(0,3,0,68); name.BackgroundTransparency=1
		name.Text=owned and pet.name or "???"; name.TextColor3=Color3.new(1,1,1); name.TextScaled=true
		name.Font=Enum.Font.GothamBold; name.Parent=card

		local rl=Instance.new("TextLabel")
		rl.Size=UDim2.new(1,-6,0,18); rl.Position=UDim2.new(0,3,0,92); rl.BackgroundTransparency=1
		rl.Text=owned and (pet.rarity..(ownedCount[pet.name]>1 and "  x"..ownedCount[pet.name] or "")) or "🔒 Not found"
		rl.TextColor3=owned and rcol or Color3.fromRGB(120,120,140); rl.TextScaled=true; rl.Font=Enum.Font.Gotham; rl.Parent=card
	end

	return screen
end

function PetIndexPanel.Refresh() end
return PetIndexPanel
