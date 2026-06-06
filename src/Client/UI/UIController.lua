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

function UIController.CloseAll()
	if CurrentPanel and CurrentPanel.Parent then
		-- Find the main Frame inside the ScreenGui to tween
		local mainFrame = nil
		for _, child in ipairs(CurrentPanel:GetChildren()) do
			if child:IsA("Frame") then mainFrame = child break end
		end
		if mainFrame then
			TweenService:Create(mainFrame, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
				Position = UDim2.new(
					mainFrame.Position.X.Scale,
					mainFrame.Position.X.Offset,
					0.5, 500
				),
			}):Play()
		end
		task.delay(0.25, function()
			if CurrentPanel then CurrentPanel:Destroy() end
			CurrentPanel = nil
			CurrentPanelName = nil
		end)
	else
		CurrentPanel = nil
		CurrentPanelName = nil
	end
end

function UIController.TogglePanel(panelName, data)
	if CurrentPanelName == panelName then
		UIController.CloseAll()
		return
	end
	UIController.CloseAll()

	task.wait(0.05)

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
