-- StarPets: Responsive.lua
-- Place in: StarterPlayerScripts > Client > UI > Responsive (ModuleScript)
--
-- Two things every panel in this game was missing, applied from one place.
--
-- 1. THEY DID NOT FIT ON A PHONE.
--
-- Every panel was sized in hard pixels — 620x500, 600x500, 580x480 — and
-- centred by hand with Position = UDim2.new(0.5, -width/2, ...). On a desktop
-- that is fine. A phone in portrait is around 390 points wide, so a 620-wide
-- panel hung 115 points off each edge of the screen: the close button and half
-- the buttons were simply not reachable. Most Roblox play is on a phone, so
-- for most players most of this game's UI was unusable.
--
-- The fix keeps the desktop look exactly as it was. The panel is given a size
-- in SCALE, so it can shrink, and a UISizeConstraint whose MaxSize is the
-- original pixel size, so it never grows past what it was designed for. On a
-- desktop the scale size is larger than MaxSize and the clamp wins — nothing
-- moves. On a phone the scale size is smaller and the panel fits.
--
-- 2. THE BUTTONS DID NOT REACT.
--
-- Two hover handlers across twenty-one UI files. Pressing a button and having
-- nothing happen under your finger is most of the difference between a UI that
-- feels cheap and one that feels made.

local TweenService = game:GetService("TweenService")

local Responsive = {}

-- How much of the screen a panel may take before the clamp stops it.
local FILL_X, FILL_Y = 0.94, 0.90
-- Below this it stops being a panel and starts being a postage stamp.
local MIN_SIZE = Vector2.new(260, 200)
-- Panels are big. Anything smaller than this is a card or a badge and is laid
-- out by its parent, so resizing it here would fight whoever placed it.
local PANEL_MIN_W, PANEL_MIN_H = 200, 160

local HOVER, PRESS = 1.05, 0.94
local QUICK = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function Responsive.FitFrame(frame)
	local size = frame.Size
	-- Only frames sized in pure pixels. One already written in scale is doing
	-- something deliberate and is left alone.
	if size.X.Scale ~= 0 or size.Y.Scale ~= 0 then return false end
	local w, h = size.X.Offset, size.Y.Offset
	if w < PANEL_MIN_W or h < PANEL_MIN_H then return false end

	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(FILL_X, FILL_Y)

	local clamp = frame:FindFirstChildOfClass("UISizeConstraint")
		or Instance.new("UISizeConstraint")
	clamp.Name = "SPFit"
	clamp.MaxSize = Vector2.new(w, h)
	clamp.MinSize = MIN_SIZE
	clamp.Parent = frame
	return true
end

function Responsive.Liven(button)
	if button:FindFirstChild("SPScale") then return false end

	-- A UIScale rather than tweening Size. Size here is written as scale,
	-- offset, or a mix of both depending on the panel, and a tween that assumes
	-- one shape quietly mangles the other — a button written as
	-- UDim2.new(1, -150, 0, 60) would lose its right margin the first time it
	-- was hovered.
	local scale = Instance.new("UIScale")
	scale.Name = "SPScale"
	scale.Scale = 1
	scale.Parent = button

	local function to(v)
		TweenService:Create(scale, QUICK, { Scale = v }):Play()
	end

	-- Active is how the panels mark a button as unavailable ("Claimed", "Can't
	-- afford"). A dead button that still springs under the cursor is a lie
	-- about what pressing it will do.
	button.MouseEnter:Connect(function()
		if button.Active ~= false then to(HOVER) end
	end)
	button.MouseLeave:Connect(function() to(1) end)
	button.MouseButton1Down:Connect(function()
		if button.Active ~= false then to(PRESS) end
	end)
	button.MouseButton1Up:Connect(function()
		if button.Active ~= false then to(HOVER) end
	end)
	return true
end

local function isButton(inst)
	return inst:IsA("TextButton") or inst:IsA("ImageButton")
end

-- Apply to a whole ScreenGui: fit its panels, liven its buttons, and keep
-- livening buttons that appear later.
--
-- That last part is not optional. Panels rebuild their contents constantly —
-- QuestPanel destroys and re-creates every card on each claim — so a one-shot
-- pass would cover the buttons that existed for a few milliseconds at startup
-- and none of the ones anybody actually presses.
function Responsive.Apply(gui)
	if gui:GetAttribute("SPResponsive") then return end
	gui:SetAttribute("SPResponsive", true)

	local fitted, livened = 0, 0
	for _, child in ipairs(gui:GetChildren()) do
		if child:IsA("Frame") and Responsive.FitFrame(child) then
			fitted = fitted + 1
		end
	end
	for _, d in ipairs(gui:GetDescendants()) do
		if isButton(d) and Responsive.Liven(d) then livened = livened + 1 end
	end

	gui.DescendantAdded:Connect(function(d)
		if isButton(d) then Responsive.Liven(d) end
	end)
	return fitted, livened
end

return Responsive
