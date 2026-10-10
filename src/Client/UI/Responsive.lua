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

-- When the last button press began, while it is still held (see Busy, below).
-- Declared up here because Liven, next, is what sets it.
local pressedAt = nil
-- A press that never sees its Up (the button vanished, a finger slid off the
-- screen) must not freeze a panel for good.
local PRESS_HOLD = 0.8

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

	-- Sound, from the same place as the spring, for the same reason: this is
	-- the one line every button in the game passes through. Wiring a click into
	-- eighteen panels by hand would mean the nineteenth panel is silent and
	-- nobody notices for a month.
	local clickSound
	pcall(function() clickSound = require(script.Parent.Sfx) end)

	-- Active is how the panels mark a button as unavailable ("Claimed", "Can't
	-- afford"). A dead button that still springs under the cursor is a lie
	-- about what pressing it will do.
	button.MouseEnter:Connect(function()
		if button.Active ~= false then to(HOVER) end
	end)
	button.MouseLeave:Connect(function() pressedAt = nil; to(1) end)
	button.MouseButton1Down:Connect(function()
		pressedAt = os.clock()
		if button.Active ~= false then
			to(PRESS)
			-- Only a live button makes a noise. A click out of a button marked
			-- "Claimed" or "Can't afford" tells the player something happened
			-- when nothing did.
			if clickSound then clickSound.Play("click", 0.06) end
		end
	end)
	button.MouseButton1Up:Connect(function()
		-- Released on the next frame, not now: MouseButton1Click fires after
		-- Up, and its handler is what tells the server. A redraw squeezed in
		-- between would still lose the click.
		task.defer(function() pressedAt = nil end)
		if button.Active ~= false then to(HOVER) end
	end)
	return true
end

-- ============================================================
-- PANELS THAT REDRAW THEMSELVES
-- ============================================================
-- Fusion, Event, Playtime, Merchant and Boosts ask the server for their state
-- every second or so and redraw from scratch: every button destroyed and made
-- again. A press is a Down and an Up on the SAME button; a redraw between the
-- two leaves the Up on a button that no longer exists, and the click is lost.
-- At one redraw a second that is roughly one press in fifteen — "I pressed
-- Buy and nothing happened".
--
-- Two rules fix it without touching how any panel draws:
--   * never redraw while a button is held down
--   * never redraw when the server's answer is exactly what it was


function Responsive.Busy()
	return pressedAt ~= nil and (os.clock() - pressedAt) < PRESS_HOLD
end

-- Returns a function to call with each fresh server state: true means redraw.
function Responsive.Poller()
	local HttpService = game:GetService("HttpService")
	local last = nil
	return function(state)
		if Responsive.Busy() then return false end
		local ok, key = pcall(function() return HttpService:JSONEncode(state) end)
		if not ok then return true end
		if key == last then return false end
		last = key
		return true
	end
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
