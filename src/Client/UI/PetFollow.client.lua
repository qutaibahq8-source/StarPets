-- StarPets: PetFollow.client.lua
-- Place in: StarterPlayerScripts > Client > UI > PetFollow (LocalScript)
--
-- Every equipped pet in the server, moved HERE, on each player's own machine.
--
-- The server used to move them: a Heartbeat loop calling PivotTo on every
-- equipped pet, sixty times a second. A pet is an anchored model of up to
-- thirty parts, and moving one sets the CFrame of every part — each of which
-- is replicated to every player. Twelve players with four pets each was over
-- fifty thousand property updates a second pushed to every client, which
-- Roblox throttles, so pets (and everything queued behind them) arrived late
-- and in steps. Your own pets were worst of all: the server only learns where
-- you are after a round trip, and then tells you where your pet is after
-- another, so they trailed you and stuttered.
--
-- The server now spawns each pet once, into workspace.Pets.<UserId>, and never
-- touches it again. This moves every one of them, for every owner, locally:
-- at the frame rate, from where each character is on THIS screen, with no
-- traffic at all. A change made by a client to an anchored part stays on that
-- client, so each player sees smooth pets and costs the server nothing.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local okCfg, GameConfig = pcall(function() return require(ReplicatedStorage.Shared.GameConfig) end)
local SPEED = (okCfg and GameConfig.Settings and GameConfig.Settings.PetFollowSpeed) or 18

-- Beyond this from the camera a pet is not worth moving this frame.
local CULL = 300
-- Further than this from where it should be — a respawn, a teleport between
-- worlds — and a pet jumps there rather than flying across the map.
local SNAP = 60

-- Where pet `index` of `total` sits: a semicircle behind the owner, a second
-- row further back past five. The same layout the server used.
local function followOffset(index, total)
	local angle = math.pi + ((index - 1) - (total - 1) / 2) * 0.6
	local radius = 4 + math.floor((index - 1) / 5) * 2
	return Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
end

local function byName(a, b) return a.Name < b.Name end

local function near(pos)
	local cam = workspace.CurrentCamera
	local cf = cam and cam.CFrame
	if not cf then return true end
	return (cf.Position - pos).Magnitude < CULL
end

local petsFolder = workspace:FindFirstChild("Pets")
if not petsFolder then
	-- Created by the server when it starts; a client can get here first.
	-- Not a WaitForChild: nothing else in this script should wait on it.
	workspace.ChildAdded:Connect(function(c)
		if c.Name == "Pets" and c:IsA("Folder") then petsFolder = c end
	end)
end

local t = 0
RunService.RenderStepped:Connect(function(dt)
	t = t + dt
	if not petsFolder or not petsFolder.Parent then
		petsFolder = workspace:FindFirstChild("Pets")
		if not petsFolder then return end
	end
	local alpha = math.min(dt * SPEED, 1)

	for _, owner in ipairs(petsFolder:GetChildren()) do
		local player = Players:GetPlayerByUserId(tonumber(owner.Name) or 0)
		local char = player and player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and near(root.Position) then
			local models = owner:GetChildren()
			-- A stable order, so pets keep their places in the semicircle
			-- instead of swapping whenever the list is read.
			table.sort(models, byName)
			local total = #models
			local _, yaw = root.CFrame:ToOrientation()
			local facing = CFrame.Angles(0, yaw, 0)
			for i, model in ipairs(models) do
				if model:IsA("Model") then
					local pos = root.Position + followOffset(i, total)
						+ Vector3.new(0, math.sin(t * 2 + i * 1.2) * 0.3, 0)
					local target = CFrame.new(pos) * facing
					local current = model:GetPivot()
					if (current.Position - pos).Magnitude > SNAP then
						model:PivotTo(target)
					else
						model:PivotTo(current:Lerp(target, alpha))
					end
				end
			end
		end
	end
end)
