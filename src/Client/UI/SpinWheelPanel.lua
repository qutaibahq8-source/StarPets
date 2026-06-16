-- StarPets: SpinWheelPanel.lua
-- Place in: StarterPlayerScripts > Client > UI > SpinWheelPanel (ModuleScript)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerGui         = Players.LocalPlayer.PlayerGui

local Remotes    = ReplicatedStorage:WaitForChild("Remotes")
local RF_GetSpin = Remotes:WaitForChild("GetSpin")
local RF_Spin    = Remotes:WaitForChild("Spin")

local SpinWheelPanel = {}

local function clock(s)
	s=math.max(0,math.floor(s)); return string.format("%dh %dm", s//3600, (s%3600)//60)
end

function SpinWheelPanel.Build()
	local screen = Instance.new("ScreenGui")
	screen.Name="SpinWheelPanel"; screen.ResetOnSpawn=false
	screen.DisplayOrder=55; screen.IgnoreGuiInset=true; screen.Parent=PlayerGui

	local panel = Instance.new("Frame")
	panel.Size=UDim2.new(0,520,0,470); panel.Position=UDim2.new(0.5,-260,0.5,-235)
	panel.BackgroundColor3=Color3.fromRGB(18,16,28); panel.BorderSizePixel=0; panel.Parent=screen
	Instance.new("UICorner",panel).CornerRadius=UDim.new(0,14)
	Instance.new("UIStroke",panel).Color=Color3.fromRGB(255,120,200)

	local hd=Instance.new("TextLabel")
	hd.Size=UDim2.new(1,0,0,48); hd.BackgroundColor3=Color3.fromRGB(110,40,90)
	hd.Text="🎡  Lucky Spin"; hd.TextColor3=Color3.new(1,1,1); hd.TextScaled=true
	hd.Font=Enum.Font.GothamBold; hd.BorderSizePixel=0; hd.Parent=panel
	Instance.new("UICorner",hd).CornerRadius=UDim.new(0,14)

	local close=Instance.new("TextButton")
	close.Size=UDim2.new(0,40,0,40); close.Position=UDim2.new(1,-46,0,4)
	close.BackgroundColor3=Color3.fromRGB(200,40,40); close.Text="✕"; close.TextScaled=true
	close.Font=Enum.Font.GothamBold; close.TextColor3=Color3.new(1,1,1); close.BorderSizePixel=0; close.Parent=panel
	Instance.new("UICorner",close).CornerRadius=UDim.new(0,8)
	local alive=true
	close.MouseButton1Click:Connect(function() alive=false; screen:Destroy() end)

	-- prize grid
	local grid=Instance.new("Frame")
	grid.Size=UDim2.new(1,-24,0,250); grid.Position=UDim2.new(0,12,0,58); grid.BackgroundTransparency=1; grid.Parent=panel
	local layout=Instance.new("UIGridLayout",grid)
	layout.CellSize=UDim2.new(0.25,-8,0,118); layout.CellPadding=UDim2.new(0,8,0,8)
	layout.SortOrder=Enum.SortOrder.LayoutOrder

	local cells={}
	local function buildCells(prizes)
		for _,c in ipairs(grid:GetChildren()) do if not c:IsA("UIGridLayout") then c:Destroy() end end
		cells={}
		for i,p in ipairs(prizes) do
			local cell=Instance.new("Frame"); cell.LayoutOrder=i; cell.BackgroundColor3=Color3.fromRGB(34,30,46)
			cell.BorderSizePixel=0; cell.Parent=grid
			Instance.new("UICorner",cell).CornerRadius=UDim.new(0,10)
			local st=Instance.new("UIStroke",cell); st.Color=p.color or Color3.fromRGB(120,120,140); st.Thickness=2
			local lbl=Instance.new("TextLabel"); lbl.Size=UDim2.new(1,-6,1,-6); lbl.Position=UDim2.new(0,3,0,3)
			lbl.BackgroundTransparency=1; lbl.Text=p.label; lbl.TextColor3=Color3.new(1,1,1)
			lbl.TextScaled=true; lbl.Font=Enum.Font.GothamBold; lbl.TextWrapped=true; lbl.Parent=cell
			cells[i]={cell=cell, stroke=st}
		end
	end

	local status=Instance.new("TextLabel")
	status.Size=UDim2.new(1,-24,0,28); status.Position=UDim2.new(0,12,0,312); status.BackgroundTransparency=1
	status.Text=""; status.TextColor3=Color3.fromRGB(255,200,230); status.TextScaled=true; status.Font=Enum.Font.GothamBold; status.Parent=panel

	local freeBtn=Instance.new("TextButton")
	freeBtn.Size=UDim2.new(0.5,-18,0,52); freeBtn.Position=UDim2.new(0,12,1,-66); freeBtn.BorderSizePixel=0
	freeBtn.TextColor3=Color3.new(1,1,1); freeBtn.TextScaled=true; freeBtn.Font=Enum.Font.GothamBold; freeBtn.Parent=panel
	Instance.new("UICorner",freeBtn).CornerRadius=UDim.new(0,10)

	local payBtn=Instance.new("TextButton")
	payBtn.Size=UDim2.new(0.5,-18,0,52); payBtn.Position=UDim2.new(0.5,6,1,-66); payBtn.BorderSizePixel=0
	payBtn.BackgroundColor3=Color3.fromRGB(20,120,170); payBtn.TextColor3=Color3.new(1,1,1)
	payBtn.TextScaled=true; payBtn.Font=Enum.Font.GothamBold; payBtn.Parent=panel
	Instance.new("UICorner",payBtn).CornerRadius=UDim.new(0,10)

	local spinning=false
	local function highlight(idx)
		for i,c in ipairs(cells) do
			c.stroke.Thickness = (i==idx) and 5 or 2
			c.cell.BackgroundColor3 = (i==idx) and Color3.fromRGB(70,60,90) or Color3.fromRGB(34,30,46)
		end
	end

	local function animateTo(landIdx)
		spinning=true
		local n=#cells
		local steps = n*3 + landIdx  -- ~3 loops then land
		for s=1,steps do
			highlight(((s-1)%n)+1)
			task.wait(0.05 + (s/steps)*0.12)  -- ease out
		end
		highlight(landIdx)
		spinning=false
	end

	local function doSpin(useFree)
		if spinning then return end
		spinning=true; status.Text="Spinning..."
		local ok, res = pcall(function() return RF_Spin:InvokeServer(useFree) end)
		if not (ok and res) then spinning=false; status.Text="Error, try again"; return end
		if not res.ok then spinning=false; status.Text=tostring(res.err); return end
		animateTo(res.index)
		status.Text="🎉 You won: "..tostring(res.prize.label).."!"
	end
	freeBtn.MouseButton1Click:Connect(function() if not freeBtn:GetAttribute("locked") then doSpin(true) end end)
	payBtn.MouseButton1Click:Connect(function() doSpin(false) end)

	local built=false
	task.spawn(function()
		while alive and screen.Parent do
			local ok, s = pcall(function() return RF_GetSpin:InvokeServer() end)
			if ok and s then
				if not built then buildCells(s.prizes); built=true end
				if not spinning then
					if s.freeReady then
						freeBtn.Text="🎡 FREE SPIN"; freeBtn.BackgroundColor3=Color3.fromRGB(220,60,150); freeBtn:SetAttribute("locked",false)
					else
						freeBtn.Text="Free in "..clock(s.nextFreeIn); freeBtn.BackgroundColor3=Color3.fromRGB(60,50,70); freeBtn:SetAttribute("locked",true)
					end
					payBtn.Text="Spin 💎"..tostring(s.cost)
				end
			end
			task.wait(1)
		end
	end)
	return screen
end

function SpinWheelPanel.Refresh() end
return SpinWheelPanel
