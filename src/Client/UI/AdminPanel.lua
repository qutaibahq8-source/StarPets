-- StarPets: AdminPanel.lua  (client UI; all actions are server-validated)
-- Place in: StarterPlayerScripts > Client > UI > AdminPanel (ModuleScript)

local Players   = game:GetService("Players")
local PlayerGui = Players.LocalPlayer.PlayerGui

local AdminPanel = {}
local function G() return _G.MysticPets end

function AdminPanel.Build(data)
	local targetBox  -- set after helpers; lets the admin act on another player
	local R = function(action, arg)
		arg = arg or {}
		if targetBox and targetBox.Text ~= "" then arg.target = targetBox.Text end
		return G().RF_Admin:InvokeServer(action, arg)
	end

	local screen = Instance.new("ScreenGui")
	screen.Name="AdminPanel"; screen.ResetOnSpawn=false
	screen.DisplayOrder=90; screen.IgnoreGuiInset=true; screen.Parent=PlayerGui

	local panel = Instance.new("Frame")
	panel.Size=UDim2.new(0,430,0,540); panel.Position=UDim2.new(0,20,0.5,-270)
	panel.BackgroundColor3=Color3.fromRGB(16,14,24); panel.BorderSizePixel=0; panel.Parent=screen
	Instance.new("UICorner",panel).CornerRadius=UDim.new(0,12)
	local st=Instance.new("UIStroke",panel); st.Color=Color3.fromRGB(255,70,70); st.Thickness=2

	local hd=Instance.new("TextLabel")
	hd.Size=UDim2.new(1,0,0,46); hd.BackgroundColor3=Color3.fromRGB(120,24,24)
	hd.Text="🛠  ADMIN PANEL"; hd.TextColor3=Color3.new(1,1,1); hd.TextScaled=true
	hd.Font=Enum.Font.GothamBold; hd.BorderSizePixel=0; hd.Parent=panel
	Instance.new("UICorner",hd).CornerRadius=UDim.new(0,12)

	local close=Instance.new("TextButton")
	close.Size=UDim2.new(0,38,0,38); close.Position=UDim2.new(1,-44,0,4)
	close.BackgroundColor3=Color3.fromRGB(200,40,40); close.Text="✕"; close.TextScaled=true
	close.Font=Enum.Font.GothamBold; close.TextColor3=Color3.new(1,1,1); close.BorderSizePixel=0; close.Parent=panel
	Instance.new("UICorner",close).CornerRadius=UDim.new(0,8)
	close.MouseButton1Click:Connect(function() screen:Destroy() end)

	local scroll=Instance.new("ScrollingFrame")
	scroll.Size=UDim2.new(1,-12,1,-54); scroll.Position=UDim2.new(0,6,0,50)
	scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0; scroll.ScrollBarThickness=5
	scroll.CanvasSize=UDim2.new(0,0,0,0); scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.Parent=panel
	local list=Instance.new("UIListLayout",scroll); list.Padding=UDim.new(0,6); list.SortOrder=Enum.SortOrder.LayoutOrder
	local order=0

	local function section(t)
		order=order+1
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-8,0,26); l.BackgroundTransparency=1
		l.Text=t; l.TextColor3=Color3.fromRGB(255,180,180); l.TextScaled=true; l.Font=Enum.Font.GothamBold
		l.TextXAlignment=Enum.TextXAlignment.Left; l.LayoutOrder=order; l.Parent=scroll
	end
	local function button(t,color,fn)
		order=order+1
		local b=Instance.new("TextButton"); b.Size=UDim2.new(1,-8,0,38); b.BackgroundColor3=color or Color3.fromRGB(40,36,60)
		b.Text=t; b.TextColor3=Color3.new(1,1,1); b.TextScaled=true; b.Font=Enum.Font.GothamBold
		b.BorderSizePixel=0; b.LayoutOrder=order; b.Parent=scroll
		Instance.new("UICorner",b).CornerRadius=UDim.new(0,8)
		b.MouseButton1Click:Connect(fn); return b
	end
	local function textbox(ph)
		order=order+1
		local tb=Instance.new("TextBox"); tb.Size=UDim2.new(1,-8,0,34); tb.BackgroundColor3=Color3.fromRGB(30,28,44)
		tb.PlaceholderText=ph; tb.Text=""; tb.TextColor3=Color3.new(1,1,1); tb.TextScaled=true
		tb.Font=Enum.Font.Gotham; tb.BorderSizePixel=0; tb.ClearTextOnFocus=false; tb.LayoutOrder=order; tb.Parent=scroll
		Instance.new("UICorner",tb).CornerRadius=UDim.new(0,8); return tb
	end

	section("🎯 Target player (blank = yourself)")
	targetBox = textbox("Type a player's name to give to them")

	section("💰 Currency")
	button("+10,000 Coins", Color3.fromRGB(120,90,20), function() R("give",{coins=10000}) end)
	button("+1,000,000 Coins", Color3.fromRGB(120,90,20), function() R("give",{coins=1000000}) end)
	button("+1,000 Gems", Color3.fromRGB(20,90,120), function() R("give",{gems=1000}) end)
	button("+100,000 Gems", Color3.fromRGB(20,90,120), function() R("give",{gems=100000}) end)

	section("🐾 Pets — tap to give")
	local cfg = G().GameConfig
	if cfg and cfg.Pets then
		for _, pet in ipairs(cfg.Pets) do
			button(pet.name.."   ("..pet.rarity..")", Color3.fromRGB(70,40,110), function()
				R("givePet", {name=pet.name, rarity=pet.rarity})
			end)
		end
	end

	section("🌍 Worlds")
	button("Unlock ALL Worlds", Color3.fromRGB(40,90,40), function() R("unlockAll") end)
	for _,a in ipairs({"Meadow","Forest","Desert","Volcano","Space"}) do
		button("Teleport → "..a, Color3.fromRGB(36,60,90), function() R("teleport",{area=a}) end)
	end

	section("⚡ Boosts / Passes")
	button("Max All Upgrades", Color3.fromRGB(120,100,20), function() R("maxUpgrades") end)
	for _,gp in ipairs({{"GP_VIP","VIP"},{"GP_2xCoins","2x Coins"},{"GP_AutoCollect","Auto Collect"},{"GP_PetSlots","+Pet Slots"},{"GP_LuckyBoost","Lucky Boost"}}) do
		button("Toggle "..gp[2], Color3.fromRGB(70,40,90), function() R("toggleGamepass",{key=gp[1]}) end)
	end

	section("📜 Quests")
	button("Complete ALL Quests", Color3.fromRGB(40,80,120), function() R("claimQuests") end)
	button("Reset My Quests", Color3.fromRGB(80,60,40), function() R("resetQuests") end)

	section("🛒 Merchant")
	button("Force Spawn Merchant", Color3.fromRGB(120,90,40), function() R("spawnMerchant") end)
	button("Despawn Merchant", Color3.fromRGB(80,60,40), function() R("despawnMerchant") end)

	section("🦸 Power")
	button("⭐ GOD MODE (everything)", Color3.fromRGB(160,40,40), function() R("godMode") end)

	section("📢 Server")
	local msgBox=textbox("Broadcast message...")
	button("Broadcast", Color3.fromRGB(40,70,120), function() if msgBox.Text~="" then R("broadcast",{msg=msgBox.Text}) end end)
	button("Bring All Players To Me", Color3.fromRGB(40,70,120), function() R("bringPlayers") end)

	section("🧨 Danger")
	local resetConfirm=false
	local rb
	rb=button("🔄 Reset MY Data", Color3.fromRGB(150,30,30), function()
		if not resetConfirm then resetConfirm=true; rb.Text="⚠ Click AGAIN to confirm reset"
		else R("resetData"); rb.Text="✅ Data reset"; resetConfirm=false end
	end)

	section("📊 Players")
	order=order+1
	local statsLbl=Instance.new("TextLabel")
	statsLbl.Size=UDim2.new(1,-8,0,130); statsLbl.BackgroundColor3=Color3.fromRGB(24,22,36)
	statsLbl.Text="(click refresh)"; statsLbl.TextColor3=Color3.fromRGB(200,200,210)
	statsLbl.TextWrapped=true; statsLbl.Font=Enum.Font.Code; statsLbl.TextSize=14
	statsLbl.TextXAlignment=Enum.TextXAlignment.Left; statsLbl.TextYAlignment=Enum.TextYAlignment.Top
	statsLbl.BorderSizePixel=0; statsLbl.LayoutOrder=order; statsLbl.Parent=scroll
	Instance.new("UICorner",statsLbl).CornerRadius=UDim.new(0,8)
	button("Refresh Stats", Color3.fromRGB(40,60,80), function()
		local s=R("stats"); local txt=""
		if type(s)=="table" then
			for _,p in ipairs(s) do
				txt=txt..p.name.."  💰"..tostring(p.coins).."  💎"..tostring(p.gems).."  🐾"..tostring(p.pets).."  ♻"..tostring(p.rebirths).."\n"
			end
		end
		statsLbl.Text = (txt~="" and txt) or "(no players)"
	end)

	return screen
end

function AdminPanel.Refresh() end
return AdminPanel
