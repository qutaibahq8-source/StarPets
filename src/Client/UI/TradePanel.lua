-- StarPets: TradePanel.lua
-- Place in: StarterPlayerScripts > Client > UI > TradePanel (ModuleScript)
-- All trade logic is server-validated; this is just the window.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerGui         = Players.LocalPlayer.PlayerGui

local Remotes       = ReplicatedStorage:WaitForChild("Remotes")
local RE_Trade      = Remotes:WaitForChild("Trade")
local RE_TradeState = Remotes:WaitForChild("TradeState")
local RE_TradeReq   = Remotes:WaitForChild("TradeReq")

local TradePanel = {}
local function G() return _G.MysticPets end
local state = { active = false }
local rerender           -- set while a panel is open

-- ---- incoming request popup (works even if panel closed) ----
RE_TradeReq.OnClientEvent:Connect(function(fromName)
	local g = PlayerGui:FindFirstChild("TradeReqGui"); if g then g:Destroy() end
	local s = Instance.new("ScreenGui"); s.Name="TradeReqGui"; s.ResetOnSpawn=false; s.DisplayOrder=95; s.Parent=PlayerGui
	local f = Instance.new("Frame"); f.Size=UDim2.new(0,340,0,150); f.Position=UDim2.new(0.5,-170,0,80)
	f.BackgroundColor3=Color3.fromRGB(20,24,40); f.BorderSizePixel=0; f.Parent=s
	Instance.new("UICorner",f).CornerRadius=UDim.new(0,12)
	Instance.new("UIStroke",f).Color=Color3.fromRGB(90,200,120)
	local t=Instance.new("TextLabel"); t.Size=UDim2.new(1,-16,0,70); t.Position=UDim2.new(0,8,0,8); t.BackgroundTransparency=1
	t.Text="🤝 "..fromName.."\nwants to trade!"; t.TextColor3=Color3.new(1,1,1); t.TextScaled=true; t.Font=Enum.Font.GothamBold; t.Parent=f
	local function mk(txt,col,x,val)
		local b=Instance.new("TextButton"); b.Size=UDim2.new(0,150,0,46); b.Position=UDim2.new(0,x,1,-54)
		b.BackgroundColor3=col; b.Text=txt; b.TextColor3=Color3.new(1,1,1); b.TextScaled=true; b.Font=Enum.Font.GothamBold; b.BorderSizePixel=0; b.Parent=f
		Instance.new("UICorner",b).CornerRadius=UDim.new(0,8)
		b.MouseButton1Click:Connect(function() RE_Trade:FireServer("respond", val); s:Destroy() end)
	end
	mk("✓ Accept",Color3.fromRGB(50,170,80),12,true); mk("✕ Decline",Color3.fromRGB(180,50,50),178,false)
	task.delay(15,function() if s then s:Destroy() end end)
end)

RE_TradeState.OnClientEvent:Connect(function(s)
	state = s or { active=false }
	if state.active and not PlayerGui:FindFirstChild("TradePanel") then TradePanel.Build() end
	if rerender then rerender() end
end)

function TradePanel.Build()
	local existing = PlayerGui:FindFirstChild("TradePanel"); if existing then existing:Destroy() end
	local screen = Instance.new("ScreenGui"); screen.Name="TradePanel"; screen.ResetOnSpawn=false
	screen.DisplayOrder=58; screen.IgnoreGuiInset=true; screen.Parent=PlayerGui

	local panel=Instance.new("Frame"); panel.Size=UDim2.new(0,620,0,500); panel.Position=UDim2.new(0.5,-310,0.5,-250)
	panel.BackgroundColor3=Color3.fromRGB(16,18,30); panel.BorderSizePixel=0; panel.Parent=screen
	Instance.new("UICorner",panel).CornerRadius=UDim.new(0,14)
	Instance.new("UIStroke",panel).Color=Color3.fromRGB(90,200,120)

	local hd=Instance.new("TextLabel"); hd.Size=UDim2.new(1,0,0,48); hd.BackgroundColor3=Color3.fromRGB(30,70,45)
	hd.Text="🤝 Trade"; hd.TextColor3=Color3.new(1,1,1); hd.TextScaled=true; hd.Font=Enum.Font.GothamBold; hd.BorderSizePixel=0; hd.Parent=panel
	Instance.new("UICorner",hd).CornerRadius=UDim.new(0,14)
	local close=Instance.new("TextButton"); close.Size=UDim2.new(0,40,0,38); close.Position=UDim2.new(1,-46,0,5)
	close.BackgroundColor3=Color3.fromRGB(190,50,50); close.Text="✕"; close.TextScaled=true; close.Font=Enum.Font.GothamBold
	close.TextColor3=Color3.new(1,1,1); close.BorderSizePixel=0; close.Parent=panel
	Instance.new("UICorner",close).CornerRadius=UDim.new(0,8)
	close.MouseButton1Click:Connect(function()
		if state.active then RE_Trade:FireServer("cancel") end
		rerender=nil; screen:Destroy()
	end)

	local body=Instance.new("Frame"); body.Size=UDim2.new(1,-16,1,-58); body.Position=UDim2.new(0,8,0,52)
	body.BackgroundTransparency=1; body.Parent=panel

	local function clear() for _,c in ipairs(body:GetChildren()) do c:Destroy() end end

	local function renderRequest()
		clear()
		local info=Instance.new("TextLabel"); info.Size=UDim2.new(1,0,0,40); info.BackgroundTransparency=1
		info.Text="Enter a player's name to trade with:"; info.TextColor3=Color3.new(1,1,1); info.TextScaled=true; info.Font=Enum.Font.Gotham; info.Parent=body
		local box=Instance.new("TextBox"); box.Size=UDim2.new(1,0,0,44); box.Position=UDim2.new(0,0,0,46)
		box.BackgroundColor3=Color3.fromRGB(30,32,46); box.PlaceholderText="Player name..."; box.Text=""; box.TextColor3=Color3.new(1,1,1)
		box.TextScaled=true; box.Font=Enum.Font.Gotham; box.BorderSizePixel=0; box.ClearTextOnFocus=false; box.Parent=body
		Instance.new("UICorner",box).CornerRadius=UDim.new(0,8)
		local req=Instance.new("TextButton"); req.Size=UDim2.new(1,0,0,48); req.Position=UDim2.new(0,0,0,100)
		req.BackgroundColor3=Color3.fromRGB(50,170,80); req.Text="Send Trade Request"; req.TextColor3=Color3.new(1,1,1)
		req.TextScaled=true; req.Font=Enum.Font.GothamBold; req.BorderSizePixel=0; req.Parent=body
		Instance.new("UICorner",req).CornerRadius=UDim.new(0,8)
		req.MouseButton1Click:Connect(function() if box.Text~="" then RE_Trade:FireServer("request", box.Text) end end)
	end

	local function offerColumn(title, list, x, removable)
		local col=Instance.new("Frame"); col.Size=UDim2.new(0.5,-6,0,180); col.Position=UDim2.new(x,x>0 and 6 or 0,0,0)
		col.BackgroundColor3=Color3.fromRGB(24,26,40); col.BorderSizePixel=0; col.Parent=body
		Instance.new("UICorner",col).CornerRadius=UDim.new(0,10)
		local h=Instance.new("TextLabel"); h.Size=UDim2.new(1,0,0,26); h.BackgroundTransparency=1; h.Text=title
		h.TextColor3=Color3.fromRGB(150,220,160); h.TextScaled=true; h.Font=Enum.Font.GothamBold; h.Parent=col
		local sc=Instance.new("ScrollingFrame"); sc.Size=UDim2.new(1,-8,1,-32); sc.Position=UDim2.new(0,4,0,28)
		sc.BackgroundTransparency=1; sc.BorderSizePixel=0; sc.ScrollBarThickness=4; sc.CanvasSize=UDim2.new(0,0,0,0)
		sc.AutomaticCanvasSize=Enum.AutomaticSize.Y; sc.Parent=col
		local l=Instance.new("UIListLayout",sc); l.Padding=UDim.new(0,3)
		for i,pet in ipairs(list or {}) do
			local b=Instance.new("TextButton"); b.Size=UDim2.new(1,-4,0,26); b.BackgroundColor3=Color3.fromRGB(40,44,62)
			b.Text=pet.name.." ("..pet.rarity..")"; b.TextColor3=Color3.new(1,1,1); b.TextScaled=true; b.Font=Enum.Font.Gotham
			b.BorderSizePixel=0; b.LayoutOrder=i; b.Parent=sc
			Instance.new("UICorner",b).CornerRadius=UDim.new(0,6)
			if removable then b.MouseButton1Click:Connect(function() RE_Trade:FireServer("remove", pet.uniqueId) end) end
		end
	end

	local function renderTrade()
		clear()
		local title=Instance.new("TextLabel"); title.Size=UDim2.new(1,0,0,22); title.BackgroundTransparency=1
		title.Text="Trading with "..(state.partner or "?"); title.TextColor3=Color3.new(1,1,1); title.TextScaled=true; title.Font=Enum.Font.GothamBold; title.Parent=body
		local cols=Instance.new("Frame"); cols.Size=UDim2.new(1,0,0,180); cols.Position=UDim2.new(0,0,0,26); cols.BackgroundTransparency=1; cols.Parent=body
		local function colIn(parent) for _,c in ipairs({parent}) do end end
		-- offer columns
		do
			local holder=cols
			local function makeCol(title2,list,x,removable)
				local col=Instance.new("Frame"); col.Size=UDim2.new(0.5,-6,1,0); col.Position=UDim2.new(x, x>0 and 6 or 0,0,0)
				col.BackgroundColor3=Color3.fromRGB(24,26,40); col.BorderSizePixel=0; col.Parent=holder
				Instance.new("UICorner",col).CornerRadius=UDim.new(0,10)
				local h=Instance.new("TextLabel"); h.Size=UDim2.new(1,0,0,24); h.BackgroundTransparency=1; h.Text=title2
				h.TextColor3=Color3.fromRGB(150,220,160); h.TextScaled=true; h.Font=Enum.Font.GothamBold; h.Parent=col
				local sc=Instance.new("ScrollingFrame"); sc.Size=UDim2.new(1,-8,1,-30); sc.Position=UDim2.new(0,4,0,26)
				sc.BackgroundTransparency=1; sc.BorderSizePixel=0; sc.ScrollBarThickness=4; sc.CanvasSize=UDim2.new(0,0,0,0)
				sc.AutomaticCanvasSize=Enum.AutomaticSize.Y; sc.Parent=col
				local l=Instance.new("UIListLayout",sc); l.Padding=UDim.new(0,3)
				for i,pet in ipairs(list or {}) do
					local b=Instance.new("TextButton"); b.Size=UDim2.new(1,-4,0,26); b.BackgroundColor3=Color3.fromRGB(40,44,62)
					b.Text=pet.name; b.TextColor3=Color3.new(1,1,1); b.TextScaled=true; b.Font=Enum.Font.Gotham; b.BorderSizePixel=0; b.LayoutOrder=i; b.Parent=sc
					Instance.new("UICorner",b).CornerRadius=UDim.new(0,6)
					if removable then b.MouseButton1Click:Connect(function() RE_Trade:FireServer("remove", pet.uniqueId) end) end
				end
			end
			makeCol("Your offer"..(state.youAccepted and " ✅" or ""), state.yourOffer, 0, true)
			makeCol((state.partner or "Them").."'s offer"..(state.theyAccepted and " ✅" or ""), state.theirOffer, 0.5, false)
		end
		-- your inventory to add
		local invLbl=Instance.new("TextLabel"); invLbl.Size=UDim2.new(1,0,0,20); invLbl.Position=UDim2.new(0,0,0,212)
		invLbl.BackgroundTransparency=1; invLbl.Text="Your pets — tap to add:"; invLbl.TextColor3=Color3.fromRGB(180,180,200)
		invLbl.TextScaled=true; invLbl.Font=Enum.Font.Gotham; invLbl.Parent=body
		local inv=Instance.new("ScrollingFrame"); inv.Size=UDim2.new(1,0,0,120); inv.Position=UDim2.new(0,0,0,234)
		inv.BackgroundColor3=Color3.fromRGB(20,22,34); inv.BorderSizePixel=0; inv.ScrollBarThickness=4; inv.CanvasSize=UDim2.new(0,0,0,0)
		inv.AutomaticCanvasSize=Enum.AutomaticSize.Y; inv.Parent=body
		Instance.new("UICorner",inv).CornerRadius=UDim.new(0,8)
		local gl=Instance.new("UIGridLayout",inv); gl.CellSize=UDim2.new(0,140,0,28); gl.CellPadding=UDim2.new(0,4,0,4)
		local data=G().getData and G().getData()
		local inOffer={}; for _,p in ipairs(state.yourOffer or {}) do inOffer[p.uniqueId]=true end
		for _,pet in ipairs((data and data.Pets) or {}) do
			if not inOffer[pet.uniqueId] then
				local b=Instance.new("TextButton"); b.BackgroundColor3=Color3.fromRGB(40,44,62); b.Text=pet.name
				b.TextColor3=Color3.new(1,1,1); b.TextScaled=true; b.Font=Enum.Font.Gotham; b.BorderSizePixel=0; b.Parent=inv
				Instance.new("UICorner",b).CornerRadius=UDim.new(0,6)
				b.MouseButton1Click:Connect(function() RE_Trade:FireServer("add", pet.uniqueId) end)
			end
		end
		-- accept + countdown
		local acc=Instance.new("TextButton"); acc.Size=UDim2.new(1,0,0,52); acc.Position=UDim2.new(0,0,1,-56); acc.BorderSizePixel=0
		acc.TextColor3=Color3.new(1,1,1); acc.TextScaled=true; acc.Font=Enum.Font.GothamBold; acc.Parent=body
		Instance.new("UICorner",acc).CornerRadius=UDim.new(0,8)
		if state.confirmLeft then
			acc.BackgroundColor3=Color3.fromRGB(150,110,20); acc.Text="Confirming in "..state.confirmLeft.."..."; acc.Active=false
		elseif state.youAccepted then
			acc.BackgroundColor3=Color3.fromRGB(120,90,40); acc.Text="✅ Accepted (tap to un-accept)"
			acc.MouseButton1Click:Connect(function() RE_Trade:FireServer("accept", false) end)
		else
			acc.BackgroundColor3=Color3.fromRGB(50,170,80); acc.Text="Accept Trade"
			acc.MouseButton1Click:Connect(function() RE_Trade:FireServer("accept", true) end)
		end
	end

	rerender = function()
		if not screen.Parent then return end
		if state.active then renderTrade() else renderRequest() end
	end
	rerender()
	return screen
end

function TradePanel.Refresh() end
return TradePanel
