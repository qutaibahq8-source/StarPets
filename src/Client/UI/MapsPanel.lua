-- StarPets: MapsPanel.lua
-- Place in: StarterPlayerScripts > Client > UI > MapsPanel (ModuleScript)
--
-- The worlds, and a way to get to them. A world you own: Go, and you are
-- there. The next world you do not own yet: To gate, which takes you to its
-- gate in the world before it, where it is bought as always. Anything further
-- is shown locked. The server checks all of this (GameServer, RE_Teleport);
-- this panel only asks.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerGui         = Players.LocalPlayer.PlayerGui

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local MapsPanel = {}

local ICONS = { Meadow = "🌼", Forest = "🌲", Desert = "🏜️", Volcano = "🌋", Space = "🚀" }

local C = {
	card   = Color3.fromRGB(15, 22, 48),
	raised = Color3.fromRGB(24, 33, 68),
	edge   = Color3.fromRGB(38, 53, 95),
	soft   = Color3.fromRGB(184, 195, 224),
	green  = Color3.fromRGB(47, 190, 100),
	gold   = Color3.fromRGB(230, 170, 40),
	grey   = Color3.fromRGB(70, 82, 115),
}

local function G() return _G.MysticPets end

local function comma(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	if string.sub(out, 1, 1) == "," then out = string.sub(out, 2) end
	return out
end

local function label(parent, text, x, y, w, h, size, color, font, align)
	local l = Instance.new("TextLabel")
	l.Position = UDim2.new(0, x, 0, y); l.Size = UDim2.new(0, w, 0, h)
	l.BackgroundTransparency = 1; l.Text = text; l.TextColor3 = color or Color3.new(1, 1, 1)
	l.Font = font or Enum.Font.GothamBold; l.TextSize = size
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function teleport(areaId, toGate)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local rf = remotes and remotes:FindFirstChild("Teleport")
	if rf then rf:FireServer(areaId, toGate == true) end
end

function MapsPanel.Build(data)
	data = data or (G() and G().getData()) or {}
	local owned = {}
	for _, id in ipairs(data.UnlockedAreas or {}) do owned[id] = true end

	local screen = Instance.new("ScreenGui")
	screen.Name = "MapsPanel"; screen.ResetOnSpawn = false
	screen.DisplayOrder = 50; screen.IgnoreGuiInset = true; screen.Parent = PlayerGui

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 520, 0, 436)
	panel.Position = UDim2.new(0.5, -260, 0.5, -218)
	panel.BackgroundColor3 = C.card; panel.BorderSizePixel = 0; panel.Parent = screen
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
	local st = Instance.new("UIStroke"); st.Color = C.edge; st.Thickness = 2
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; st.Parent = panel

	label(panel, "🗺️  Maps", 20, 10, 300, 40, 26, nil, Enum.Font.FredokaOne)
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Size = UDim2.new(0, 44, 0, 44); close.Position = UDim2.new(1, -54, 0, 8)
	close.BackgroundColor3 = C.raised; close.Text = "✕"; close.TextSize = 20
	close.Font = Enum.Font.GothamBold; close.TextColor3 = C.soft; close.BorderSizePixel = 0
	close.Parent = panel
	Instance.new("UICorner", close).CornerRadius = UDim.new(0, 10)
	close.MouseButton1Click:Connect(function() screen:Destroy() end)

	local list = Instance.new("ScrollingFrame")
	list.Name = "Worlds"
	list.Size = UDim2.new(1, -24, 1, -70); list.Position = UDim2.new(0, 12, 0, 60)
	list.BackgroundTransparency = 1; list.BorderSizePixel = 0; list.ScrollBarThickness = 4
	list.CanvasSize = UDim2.new(0, 0, 0, #GameConfig.Areas * 80)
	list.Parent = panel

	local nextLocked = true
	for i, area in ipairs(GameConfig.Areas) do
		local row = Instance.new("Frame")
		row.Name = "World_" .. area.id
		row.Size = UDim2.new(1, -8, 0, 72); row.Position = UDim2.new(0, 0, 0, (i - 1) * 80)
		row.BackgroundColor3 = C.raised; row.BorderSizePixel = 0; row.Parent = list
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 12)

		local have = owned[area.id] == true
		label(row, ICONS[area.id] or "🌍", 10, 10, 52, 52, 34, nil, nil, Enum.TextXAlignment.Center)
		local name = label(row, area.name, 70, 8, 260, 28, 20, have and Color3.new(1, 1, 1) or C.soft,
			Enum.Font.FredokaOne)
		name.TextScaled = true
		local lim = Instance.new("UITextSizeConstraint"); lim.MaxTextSize = 20; lim.Parent = name
		local desc = label(row, area.description or "", 70, 36, 280, 28, 13, C.soft)
		desc.TextWrapped = true; desc.TextYAlignment = Enum.TextYAlignment.Top

		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 120, 0, 48); btn.Position = UDim2.new(1, -130, 0.5, -24)
		btn.BorderSizePixel = 0; btn.TextColor3 = Color3.new(1, 1, 1)
		btn.Font = Enum.Font.FredokaOne; btn.TextSize = 18
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)
		if have then
			btn.Name = "Go_" .. area.id
			btn.Text = "📍 Go"; btn.BackgroundColor3 = C.green
			btn.Parent = row
			btn.MouseButton1Click:Connect(function()
				teleport(area.id, false)
				screen:Destroy()
			end)
		elseif nextLocked then
			nextLocked = false
			btn.Name = "Gate_" .. area.id
			btn.Text = "🚪 To gate"; btn.BackgroundColor3 = C.gold
			btn.Parent = row
			btn.MouseButton1Click:Connect(function()
				teleport(area.id, true)
				screen:Destroy()
			end)
			label(row, "💰 " .. comma(area.unlockCost), 70, 50, 200, 18, 13, Color3.fromRGB(255, 215, 90))
			desc.Size = UDim2.new(0, 280, 0, 16)
		else
			local lock = label(row, "🔒 Locked", 0, 0, 120, 48, 16, C.soft, Enum.Font.FredokaOne,
				Enum.TextXAlignment.Center)
			lock.Position = UDim2.new(1, -130, 0.5, -24)
			lock.BackgroundColor3 = C.grey; lock.BackgroundTransparency = 0.3
			Instance.new("UICorner", lock).CornerRadius = UDim.new(0, 12)
		end
	end
	return screen
end

function MapsPanel.Refresh(data)
	require(script.Parent.UIController).Rebuild("MapsPanel", data)
end

return MapsPanel
