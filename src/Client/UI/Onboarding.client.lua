-- StarPets: Onboarding.client.lua
-- Place in: StarterPlayerScripts > Client > UI > Onboarding (LocalScript)
--
-- A brand-new player is told what to do. Nobody else ever sees this.
--
-- The join banner says "Welcome! Leave a like! Thank you! Share with friends!"
-- and nothing about how to play. A new player lands at spawn with no way to
-- know the eggs are to the south, that the first one is free, or that the
-- coins on the ground are theirs to pick up.
--
-- WHY THE STEP IS DERIVED, NOT SAVED
--
-- Which hint to show is worked out from the player's real progress every time
-- their data changes. There is no TutorialStep field. That buys three things:
--
--   * a returning player never sees it — they have already hatched eggs —
--     without any migration of existing saves
--   * it cannot be shown twice, because progress does not go backwards
--     (EggsHatched survives a rebirth, and a rebirth ends it anyway)
--   * a player who skips ahead on their own is never told to do a thing they
--     have already done
--
-- It is a LocalScript (*.client.lua) on purpose: it connects to events and
-- returns nothing, which is exactly the shape BadgePopup had when it shipped
-- as a ModuleScript that nothing required, and so never ran at all.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")
local Remotes   = ReplicatedStorage:WaitForChild("Remotes")

local STEPS = {
	{ title = "🥚  Hatch your first egg — it's FREE!",
	  body  = "Follow the arrow south to the eggs and click the green one." },
	{ title = "💰  Your pet earns coins for you",
	  body  = "Walk over the coins on the ground to collect even more." },
	{ title = "🌲  Keep going!",
	  body  = "Hatch more eggs, or save up to unlock the Forest." },
}

-- Which step this player is on, or nil when they are past all of it.
local function stepFor(d)
	if type(d) ~= "table" then return nil end
	if (d.Rebirths or 0) > 0 then return nil end
	if #(d.UnlockedAreas or {}) > 1 then return nil end
	local hatched = d.EggsHatched or 0
	if hatched == 0 then return 1 end
	if hatched >= 3 then return nil end
	local lifetime = math.max(
		tonumber(type(d.Stats) == "table" and d.Stats.coins) or 0,
		tonumber(d.TotalCoinsEarned) or 0)
	if lifetime < 300 then return 2 end
	return 3
end

-- ------------------------------------------------------------
-- The banner
-- ------------------------------------------------------------
local screen, card, titleLbl, bodyLbl
local shown = nil          -- the step on screen right now
local dismissed = {}       -- steps the player closed; the NEXT one still shows

local function buildBanner()
	screen = Instance.new("ScreenGui")
	screen.Name = "OnboardingGui"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 58
	screen.IgnoreGuiInset = false
	screen.Parent = PlayerGui

	card = Instance.new("Frame")
	-- Scale with a clamp, like every panel: it must fit a 390-point phone.
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, -120)          -- starts off screen
	card.Size = UDim2.new(0.92, 0, 0, 74)
	card.BackgroundColor3 = Color3.fromRGB(22, 18, 38)
	card.BackgroundTransparency = 0.05
	card.BorderSizePixel = 0
	card.Parent = screen
	local clamp = Instance.new("UISizeConstraint")
	clamp.MaxSize = Vector2.new(470, 74)
	clamp.Parent = card
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)
	local stroke = Instance.new("UIStroke", card)
	stroke.Color = Color3.fromRGB(255, 205, 90)
	stroke.Thickness = 2

	titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, -56, 0, 32)
	titleLbl.Position = UDim2.new(0, 14, 0, 8)
	titleLbl.BackgroundTransparency = 1
	titleLbl.TextColor3 = Color3.fromRGB(255, 225, 140)
	titleLbl.TextScaled = true
	titleLbl.Font = Enum.Font.GothamBold
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.Parent = card

	bodyLbl = Instance.new("TextLabel")
	bodyLbl.Size = UDim2.new(1, -56, 0, 24)
	bodyLbl.Position = UDim2.new(0, 14, 0, 42)
	bodyLbl.BackgroundTransparency = 1
	bodyLbl.TextColor3 = Color3.fromRGB(215, 210, 230)
	bodyLbl.TextScaled = true
	bodyLbl.Font = Enum.Font.Gotham
	bodyLbl.TextXAlignment = Enum.TextXAlignment.Left
	bodyLbl.Parent = card

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Size = UDim2.new(0, 34, 0, 34)
	close.Position = UDim2.new(1, -44, 0, 20)
	close.BackgroundColor3 = Color3.fromRGB(60, 52, 84)
	close.Text = "✕"
	close.TextColor3 = Color3.new(1, 1, 1)
	close.TextScaled = true
	close.Font = Enum.Font.GothamBold
	close.BorderSizePixel = 0
	close.Parent = card
	Instance.new("UICorner", close).CornerRadius = UDim.new(0, 8)
	close.MouseButton1Click:Connect(function()
		if shown then dismissed[shown] = true end
		TweenService:Create(card, TweenInfo.new(0.25), {
			Position = UDim2.new(0.5, 0, 0, -120) }):Play()
		shown = nil
	end)
end

-- ------------------------------------------------------------
-- The arrow over the Starter Egg (step 1 only)
-- ------------------------------------------------------------
-- Made here, on the client, so only this player sees it: a "START HERE" over
-- the egg for everyone on the server would be noise to anyone past step one.
local arrow

local function showArrow()
	if arrow and arrow.Parent then return end
	local egg = workspace:FindFirstChild("Egg_StarterEgg", true)
	if not egg then return end
	arrow = Instance.new("BillboardGui")
	arrow.Name = "OnboardingArrow"
	arrow.Size = UDim2.new(0, 170, 0, 64)
	arrow.StudsOffset = Vector3.new(0, 6, 0)
	-- Always on top and far-reaching on purpose: it is the one sign whose job
	-- is to be found from spawn. It exists only for a player on step one.
	arrow.AlwaysOnTop = true
	arrow.MaxDistance = 600
	arrow.Adornee = egg
	arrow.Parent = egg
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, 0, 1, 0)
	t.BackgroundTransparency = 1
	t.Text = "⬇  START HERE"
	t.TextColor3 = Color3.fromRGB(255, 225, 120)
	t.TextStrokeTransparency = 0.2
	t.TextStrokeColor3 = Color3.new(0, 0, 0)
	t.TextScaled = true
	t.Font = Enum.Font.GothamBold
	t.Parent = arrow
	-- A slow bob so the eye catches it.
	TweenService:Create(arrow, TweenInfo.new(0.8, Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut, -1, true),
		{ StudsOffset = Vector3.new(0, 7.2, 0) }):Play()
end

local function hideArrow()
	if arrow then arrow:Destroy(); arrow = nil end
end

-- ------------------------------------------------------------
local function apply(d)
	local step = stepFor(d)

	if step == 1 then showArrow() else hideArrow() end

	if not step then
		if screen then screen:Destroy(); screen = nil end
		shown = nil
		return
	end
	if step == shown or dismissed[step] then return end

	if not screen then buildBanner() end
	titleLbl.Text = STEPS[step].title
	bodyLbl.Text = STEPS[step].body
	shown = step
	TweenService:Create(card, TweenInfo.new(0.45, Enum.EasingStyle.Back), {
		Position = UDim2.new(0.5, 0, 0, 12) }):Play()
end

-- Expose the decision for the checks; nothing in the game reads this.
_G.StarPetsOnboarding = { stepFor = stepFor, apply = apply }

local ev = Remotes:WaitForChild("DataUpdated", 30)
if ev then
	ev.OnClientEvent:Connect(apply)
end

-- The first data may already have arrived before this script connected, and
-- an update is not guaranteed until something changes. Ask the client for what
-- it has, after the loading screen is gone so the banner is not hidden under it.
task.spawn(function()
	task.wait(3.2)
	for _ = 1, 20 do
		local g = _G.MysticPets
		local d = g and g.getData and g.getData()
		if d then apply(d) return end
		task.wait(0.5)
	end
end)
