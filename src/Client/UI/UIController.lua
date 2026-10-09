-- MysticPets: UIController.lua
-- Place in: StarterPlayerScripts > Client > UI > UIController (ModuleScript)
-- Central panel manager — only one panel open at a time

local Players   = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local PlayerGui = Players.LocalPlayer.PlayerGui

local UIController = {}
local CurrentPanel = nil
local CurrentPanelName = nil

local PanelModules = {
	PetsPanel    = "PetsPanel",
	HatchPanel   = "HatchPanel",
	ShopPanel    = "ShopPanel",
	RebirthPanel = "RebirthPanel",
}

-- Every panel's ScreenGui is named after its module, so we can sweep them all
local PANEL_NAMES = {
	"PetsPanel","HatchPanel","ShopPanel","RebirthPanel","UpgradePanel","LeaderboardPanel","AdminPanel","QuestPanel","MerchantPanel","EventPanel","TradePanel","PetIndexPanel","CodesPanel","DailyPanel","BoostsPanel","FusionPanel","PlaytimePanel","SpinWheelPanel",
}

local function destroyAllPanels()
	for _, name in ipairs(PANEL_NAMES) do
		local g = PlayerGui:FindFirstChild(name)
		if g then g:Destroy() end
	end
	CurrentPanel = nil
	CurrentPanelName = nil
end

function UIController.CloseAll()
	destroyAllPanels()
end

local function moduleFor(panelName)
	local ok, module = pcall(function()
		return require(script.Parent[panelName])
	end)
	if not ok or not module then
		warn("[UIController] Failed to load panel: " .. panelName)
		return nil
	end
	return module
end

-- Every panel in the game passes through here, on open AND on rebuild, which
-- is why the responsive pass lives here rather than in eighteen Build
-- functions. Applied BEFORE parenting, so nothing is ever shown at the wrong
-- size for a frame.
local function fit(panel)
	pcall(function()
		require(script.Parent.Responsive).Apply(panel)
	end)
end

-- The one entrance animation, for every panel: a quick pop, done with a
-- UIScale so it never touches Position or Size.
--
-- Six panels used to slide in by tweening Position to a pixel offset. The
-- responsive pass centres a panel by setting Position itself — and a playing
-- tween writes its property every frame until it ends, so it ended at the old
-- offset, now measured from the panel's centre. On a phone that put Pets,
-- Shop, Upgrade, Rebirth, Hatch and Ranks almost entirely off the left of the
-- screen; on a laptop it cut off the top, close button included.
local function enter(panel)
	for _, child in ipairs(panel:GetChildren()) do
		if child:IsA("Frame") then
			local s = Instance.new("UIScale")
			s.Name = "SPEnter"
			s.Scale = 0.88
			s.Parent = child
			TweenService:Create(s, TweenInfo.new(0.22, Enum.EasingStyle.Back,
				Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end
end

local function open(panelName, data, ...)
	destroyAllPanels()  -- guarantees only one panel is ever open
	local module = moduleFor(panelName)
	if not module then return end

	local panel = module.Build(data, ...)
	if not panel then return end
	fit(panel)
	enter(panel)

	panel.Parent = PlayerGui
	CurrentPanel = panel
	CurrentPanelName = panelName
end

-- What a panel shows, as a string: every element's text, colour, size and
-- place. Two builds that give the same string look the same to the player.
local function show(v)
	local t = typeof(v)
	if t == "Color3" then return string.format("%.3f,%.3f,%.3f", v.R, v.G, v.B) end
	if t == "UDim2" then
		return string.format("%g,%g,%g,%g", v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset)
	end
	return tostring(v)
end

local function looks(gui)
	local out = {}
	for _, d in ipairs(gui:GetDescendants()) do
		-- A UIScale is mid-animation state (the entrance pop, a pressed
		-- button), not something the panel shows.
		if d:IsA("UIScale") then continue end
		local row = { d.ClassName, d.Name }
		if d:IsA("GuiObject") then
			table.insert(row, show(d.Size)); table.insert(row, show(d.Position))
			table.insert(row, show(d.BackgroundColor3)); table.insert(row, show(d.Visible))
			table.insert(row, show(d.Active))
		end
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			table.insert(row, show(d.Text)); table.insert(row, show(d.TextColor3))
		end
		if d:IsA("UIStroke") then table.insert(row, show(d.Color)) end
		out[#out + 1] = table.concat(row, "|")
	end
	return table.concat(out, "\n")
end

local function scrollsOf(gui)
	local list = {}
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("ScrollingFrame") then list[#list + 1] = d end
	end
	return list
end

-- Rebuild an open panel from new data, in place.
--
-- Panels used to do this themselves: destroy, Build, done. That skipped the
-- responsive pass (a rebuilt panel was back to raw pixels, off a phone),
-- replayed the slide-in, and threw away the scroll position. Rebirth, Shop and
-- Upgrade did it on every data sync — every two seconds — so they bounced,
-- jumped back to the top, and ate any click that landed mid-rebuild.
--
-- Now a rebuild is fitted like an open, never animated, keeps scroll, and is
-- thrown away unused if it would look exactly like what is already there.
function UIController.Rebuild(panelName, data, ...)
	local old = PlayerGui:FindFirstChild(panelName)
	if not old then return end
	local module = moduleFor(panelName)
	if not module then return end

	-- Build parents its ScreenGui to PlayerGui, so take the old one out of the
	-- way first; it goes back if nothing changed. Build must not yield (none
	-- of the rebuilt panels call the server while building), or the old panel
	-- would be missing from the screen for the length of the call.
	local before = looks(old)
	old.Parent = nil
	local panel = module.Build(data, ...)
	-- Put back only if Build left it alone. A Build that destroys its previous
	-- panel would leave nothing to put back, and in Roblox a destroyed
	-- instance cannot be re-parented at all.
	local intact = looks(old) == before
	if not panel then
		if intact then old.Parent = PlayerGui end
		return
	end
	fit(panel)

	if intact and looks(panel) == before then
		panel:Destroy()
		old.Parent = PlayerGui
		return
	end

	local was = scrollsOf(old)
	for i, sc in ipairs(scrollsOf(panel)) do
		if was[i] then sc.CanvasPosition = was[i].CanvasPosition end
	end
	old:Destroy()
	panel.Parent = PlayerGui
	if CurrentPanelName == panelName then CurrentPanel = panel end
end

-- A HUD button: pressing it again closes its panel.
function UIController.TogglePanel(panelName, data, ...)
	if CurrentPanelName == panelName and PlayerGui:FindFirstChild(panelName) then
		destroyAllPanels()
		return
	end
	open(panelName, data, ...)
end

-- Something in the world: it always opens, never closes. Clicking a second egg
-- while the hatch panel is up should show that egg, not shut the panel.
function UIController.Open(panelName, data, ...)
	open(panelName, data, ...)
end

function UIController.RefreshCurrent(data)
	if not CurrentPanelName then return end
	local ok, module = pcall(function()
		return require(script.Parent[CurrentPanelName])
	end)
	if ok and module and module.Refresh then
		module.Refresh(data)
	end
end

return UIController
