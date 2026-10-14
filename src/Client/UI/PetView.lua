-- StarPets: PetView.lua
-- Place in: StarterPlayerScripts > Client > UI > PetView (ModuleScript)
--
-- A pet, drawn in the UI as the pet itself.
--
-- Three places showed pets, and none of them showed a pet. The hatch reveal
-- drew the first letter of the name. The inventory drew a 3D model only when
-- an imported mesh existed — none ship — so every pet in it was a letter too.
-- The Pet Index drew a coloured disc, and "?" for anything not yet found.
--
-- One builder for all three, so they cannot drift apart again. It is the same
-- PetModels.Build the server uses for the pet that follows you, so the pet in
-- the panel is the pet in the world: an imported mesh from PetMeshes if the
-- developer has added one, the procedural model otherwise. If neither can be
-- made it returns nil and leaves nothing behind, and the caller keeps its own
-- fallback.
--
-- Silhouette is for the Index: a species not yet found is shown as its real
-- shape in near-black, which says "there is something here" far better than
-- a question mark.
--
-- Spin is for the reveal only. A grid of a hundred turning models in the
-- inventory would cost a phone more than it is worth; a still model at a good
-- angle reads just as well there.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local PetView = {}

local SILHOUETTE = Color3.fromRGB(14, 12, 22)

local function shared(name)
	local ok, m = pcall(function() return require(ReplicatedStorage.Shared[name]) end)
	return ok and m or nil
end

local function buildModel(name, rarity, mutationId)
	local PM, cfg = shared("PetModels"), shared("GameConfig")
	if not PM or not cfg then return nil end
	local petData
	for _, p in ipairs(cfg.Pets or {}) do
		if p.name == name then petData = p break end
	end
	if not petData then return nil end
	local rarityInfo = cfg.Rarities and cfg.Rarities[rarity or petData.rarity]
	local mut = mutationId and cfg.GetMutation and cfg.GetMutation(mutationId) or nil
	local ok, m = pcall(function()
		local model = PM.Build(petData, "view", rarityInfo, mut)
		return model
	end)
	return ok and m or nil
end

-- Show `name` inside `holder`. Returns the ViewportFrame, or nil if no model
-- could be made (and nothing is left behind in `holder`).
--
-- opts.silhouette  draw it in near-black, for an undiscovered species
-- opts.spin        turn it slowly; stops by itself when the frame goes away
-- opts.rarity, opts.mutation
function PetView.Show(holder, name, opts)
	opts = opts or {}
	local model = buildModel(name, opts.rarity, opts.mutation)
	if not model then return nil end

	local vf = Instance.new("ViewportFrame")
	vf.Name = "PetView"
	vf.Size = UDim2.new(1, 0, 1, 0)
	vf.BackgroundTransparency = 1
	vf.LightDirection = Vector3.new(-1, -1.4, -0.6)
	vf.Ambient = opts.silhouette and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(170, 170, 185)
	vf.Parent = holder

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			if opts.silhouette then
				d.Color = SILHOUETTE
				d.Material = Enum.Material.SmoothPlastic
			end
		elseif d:IsA("BillboardGui") or d:IsA("ParticleEmitter") then
			-- The name tag is for the pet walking behind you; a viewport does
			-- not draw either of these anyway, and on a silhouette a floating
			-- name would give away the one thing it is hiding.
			d:Destroy()
		elseif opts.silhouette and (d:IsA("Decal") or d:IsA("Texture")) then
			d:Destroy()
		end
	end
	model.Parent = vf

	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = vf
	vf.CurrentCamera = cam

	-- Framed from the model's own bounds, so an ant and a dragon both fill the
	-- frame rather than one vanishing and one spilling out of it.
	local center, radius = Vector3.new(0, 0, 0), 2.5
	pcall(function()
		local cf, size = model:GetBoundingBox()
		center = cf.Position
		radius = math.max(1, size.Magnitude * 0.5)
	end)
	local dist = radius / math.tan(math.rad(cam.FieldOfView * 0.5)) * 1.05

	local function aim(t)
		local pos = center + Vector3.new(math.sin(t) * dist, radius * 0.35, math.cos(t) * dist)
		local ok = pcall(function() cam.CFrame = CFrame.lookAt(pos, center) end)
		if not ok then cam.CFrame = CFrame.new(pos, center) end
	end
	-- A three-quarter view: the angle a pet reads best from.
	local t = 0.6
	aim(t)

	if opts.spin then
		local conn
		conn = RunService.RenderStepped:Connect(function(dt)
			-- Stop the moment the frame is gone, or every reveal leaves a dead
			-- spinner behind it.
			if not vf.Parent then
				if conn then conn:Disconnect() end
				return
			end
			t = t + dt * 0.9
			aim(t)
		end)
	end
	return vf
end

return PetView
