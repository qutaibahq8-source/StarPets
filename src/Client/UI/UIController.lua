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
	"PetsPanel","HatchPanel","ShopPanel","RebirthPanel","UpgradePanel","LeaderboardPanel","AdminPanel","QuestPanel","MerchantPanel","EventPanel","TradePanel",
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

function UIController.TogglePanel(panelName, data)
	-- Clicking the same open panel's button closes it
	if CurrentPanelName == panelName and PlayerGui:FindFirstChild(panelName) then
		destroyAllPanels()
		return
	end
	destroyAllPanels()  -- guarantees only one panel is ever open

	-- Load the panel module
	local ok, module = pcall(function()
		return require(script.Parent[panelName])
	end)
	if not ok or not module then
		warn("[UIController] Failed to load panel: " .. panelName)
		return
	end

	local panel = module.Build(data)
	if not panel then return end

	panel.Parent = PlayerGui
	CurrentPanel = panel
	CurrentPanelName = panelName
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
