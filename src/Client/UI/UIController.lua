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

local function open(panelName, data, ...)
	destroyAllPanels()  -- guarantees only one panel is ever open

	-- Load the panel module
	local ok, module = pcall(function()
		return require(script.Parent[panelName])
	end)
	if not ok or not module then
		warn("[UIController] Failed to load panel: " .. panelName)
		return
	end

	local panel = module.Build(data, ...)
	if not panel then return end

	-- Every panel in the game passes through this line, which is why the
	-- responsive pass lives here rather than in eighteen Build functions.
	-- Applied BEFORE parenting, so nothing is ever shown at the wrong size
	-- for a frame.
	pcall(function()
		require(script.Parent.Responsive).Apply(panel)
	end)

	panel.Parent = PlayerGui
	CurrentPanel = panel
	CurrentPanelName = panelName
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
