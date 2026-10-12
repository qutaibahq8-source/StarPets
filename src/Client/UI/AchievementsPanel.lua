-- StarPets: AchievementsPanel.lua
-- Place in: StarterPlayerScripts > Client > UI > AchievementsPanel (ModuleScript)
--
-- Every achievement in the game and which ones you have. The list and the
-- ticks come from the server (BadgeService.List), which is what awards them;
-- this panel only draws what it is told.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerGui         = Players.LocalPlayer.PlayerGui

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local AchievementsPanel = {}

local C = {
	card   = Color3.fromRGB(15, 22, 48),
	raised = Color3.fromRGB(24, 33, 68),
	edge   = Color3.fromRGB(38, 53, 95),
	soft   = Color3.fromRGB(184, 195, 224),
	dim    = Color3.fromRGB(110, 120, 150),
	green  = Color3.fromRGB(47, 211, 107),
}

local function label(parent, text, x, y, w, h, size, color, font, align)
	local l = Instance.new("TextLabel")
	l.Position = UDim2.new(0, x, 0, y); l.Size = UDim2.new(0, w, 0, h)
	l.BackgroundTransparency = 1; l.Text = text; l.TextColor3 = color or Color3.new(1, 1, 1)
	l.Font = font or Enum.Font.GothamBold; l.TextSize = size
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function fill(list, header, items)
	list:ClearAllChildren()
	local got = 0
	for i, a in ipairs(items) do
		if a.earned then got = got + 1 end
		local row = Instance.new("Frame")
		row.Name = "Ach_" .. tostring(a.id)
		row.Size = UDim2.new(1, -8, 0, 58); row.Position = UDim2.new(0, 0, 0, (i - 1) * 64)
		row.BackgroundColor3 = C.raised; row.BackgroundTransparency = a.earned and 0 or 0.45
		row.BorderSizePixel = 0; row.Parent = list
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 12)
		local info = GameConfig.Rarities[a.rarity or ""]
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 6, 1, -16); stripe.Position = UDim2.new(0, 6, 0, 8)
		stripe.BackgroundColor3 = info and info.color or C.dim; stripe.BorderSizePixel = 0
		stripe.BackgroundTransparency = a.earned and 0 or 0.6; stripe.Parent = row
		Instance.new("UICorner", stripe).CornerRadius = UDim.new(1, 0)
		local icon = label(row, tostring(a.icon or "🏅"), 18, 7, 44, 44, 28, nil, nil, Enum.TextXAlignment.Center)
		icon.TextTransparency = a.earned and 0 or 0.6
		local title = label(row, tostring(a.title or ""), 70, 6, 300, 24, 18,
			a.earned and Color3.new(1, 1, 1) or C.dim, Enum.Font.FredokaOne)
		title.TextScaled = true
		local lim = Instance.new("UITextSizeConstraint"); lim.MaxTextSize = 18; lim.Parent = title
		local desc = label(row, tostring(a.desc or ""), 70, 30, 320, 20, 13, a.earned and C.soft or C.dim)
		desc.TextScaled = true
		local lim2 = Instance.new("UITextSizeConstraint"); lim2.MaxTextSize = 13; lim2.Parent = desc
		local tick = label(row, a.earned and "✓" or "", 0, 0, 40, 58, 24, C.green, nil, Enum.TextXAlignment.Center)
		tick.Position = UDim2.new(1, -46, 0, 0)
	end
	list.CanvasSize = UDim2.new(0, 0, 0, #items * 64)
	header.Text = ("🏅  Achievements  %d/%d"):format(got, #items)
end

function AchievementsPanel.Build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "AchievementsPanel"; screen.ResetOnSpawn = false
	screen.DisplayOrder = 50; screen.IgnoreGuiInset = true; screen.Parent = PlayerGui

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 520, 0, 460)
	panel.Position = UDim2.new(0.5, -260, 0.5, -230)
	panel.BackgroundColor3 = C.card; panel.BorderSizePixel = 0; panel.Parent = screen
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
	local st = Instance.new("UIStroke"); st.Color = C.edge; st.Thickness = 2
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; st.Parent = panel

	local header = label(panel, "🏅  Achievements", 20, 10, 400, 40, 26, nil, Enum.Font.FredokaOne)
	header.Name = "Header"
	header.TextScaled = true
	local lim = Instance.new("UITextSizeConstraint"); lim.MaxTextSize = 26; lim.Parent = header
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Size = UDim2.new(0, 44, 0, 44); close.Position = UDim2.new(1, -54, 0, 8)
	close.BackgroundColor3 = C.raised; close.Text = "✕"; close.TextSize = 20
	close.Font = Enum.Font.GothamBold; close.TextColor3 = C.soft; close.BorderSizePixel = 0
	close.Parent = panel
	Instance.new("UICorner", close).CornerRadius = UDim.new(0, 10)
	close.MouseButton1Click:Connect(function() screen:Destroy() end)

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Size = UDim2.new(1, -24, 1, -70); list.Position = UDim2.new(0, 12, 0, 60)
	list.BackgroundTransparency = 1; list.BorderSizePixel = 0; list.ScrollBarThickness = 4
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.Parent = panel
	label(list, "Loading…", 0, 0, 480, 40, 16, C.soft, nil, Enum.TextXAlignment.Center)

	-- Asked for once the panel is up, so opening it never waits on the server.
	task.spawn(function()
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local rf = remotes and remotes:FindFirstChild("GetAchievements")
		if not rf then return end
		local ok, items = pcall(function() return rf:InvokeServer() end)
		if ok and type(items) == "table" and list.Parent then
			fill(list, header, items)
		end
	end)
	return screen
end

function AchievementsPanel.Refresh() end

return AchievementsPanel
