-- StarPets: WorldMotion.client.lua
-- Place in: StarterPlayerScripts > Client > UI > WorldMotion (LocalScript)
--
-- The bobbing eggs and the rebirth machine's orbiting rings, animated HERE, on
-- each player's own machine.
--
-- They used to be animated by the server: twelve loops setting CFrame about
-- thirty times a second. Every one of those changes is replicated to every
-- client, so a server was pushing roughly 430 property updates a second to
-- each player, forever, to make decoration move — on a twenty-player server,
-- some 8,600 a second of outbound traffic for nothing a player could tell
-- from motion done locally.
--
-- It was also invisible in a baked place. The loops were started by the map
-- builder, and a baked map is exactly the case where the builder never runs —
-- so the eggs in a baked place just sat still.
--
-- Done here, it costs the server nothing, runs at the frame rate instead of a
-- network tick, works on any map whether it was built or baked, and skips
-- anything too far away to see on a low-end device.

local RunService = game:GetService("RunService")

local camera = workspace.CurrentCamera

-- How far away motion is still worth computing. Beyond this an egg bobbing
-- half a stud is a fraction of a pixel.
local CULL = 260

local eggs, rings, orbs = {}, {}, {}
local known = {}

local function track(p)
	if known[p] or not p:IsA("BasePart") then return end
	local n = p.Name
	if string.sub(n, 1, 4) == "Egg_" then
		known[p] = true
		table.insert(eggs, { part = p, home = p.Position, phase = #eggs * 0.9 })
	elseif string.sub(n, 1, 9) == "RMOrbRing" then
		known[p] = true
		local i = tonumber(string.sub(n, 10)) or (#rings + 1)
		table.insert(rings, { part = p, home = p.Position, i = i })
	elseif n == "RMOrb" then
		known[p] = true
		table.insert(orbs, { part = p, home = p.Position })
	end
end

for _, d in ipairs(workspace:GetDescendants()) do track(d) end
-- A map that streams in, or is rebuilt, after this script starts.
workspace.DescendantAdded:Connect(track)

local function near(pos)
	local cam = camera or workspace.CurrentCamera
	if not cam then return true end
	return (cam.CFrame.Position - pos).Magnitude < CULL
end

local t = 0
RunService.RenderStepped:Connect(function(dt)
	t = t + dt

	for i = #eggs, 1, -1 do
		local e = eggs[i]
		local p = e.part
		if not p.Parent then
			table.remove(eggs, i); known[p] = nil
		elseif near(e.home) then
			local tt = t + e.phase
			p.CFrame = CFrame.new(e.home + Vector3.new(0, math.sin(tt * 1.5) * 0.5, 0))
				* CFrame.Angles(0, tt * 0.7, math.sin(tt * 0.4) * 0.08)
		end
	end

	for i = #rings, 1, -1 do
		local r = rings[i]
		local p = r.part
		if not p.Parent then
			table.remove(rings, i); known[p] = nil
		elseif near(r.home) then
			local spin = (r.i / 3) * math.pi * 2 + t * 0.8
			p.CFrame = CFrame.new(r.home) * CFrame.Angles(r.i * 0.6, spin, r.i * 0.4)
		end
	end

	for i = #orbs, 1, -1 do
		local o = orbs[i]
		local p = o.part
		if not p.Parent then
			table.remove(orbs, i); known[p] = nil
		elseif near(o.home) then
			p.CFrame = CFrame.new(o.home + Vector3.new(0, math.sin(t * 1.2) * 0.5, 0))
				* CFrame.Angles(0, t * 0.6, 0)
		end
	end
end)

-- For the checks: what this client is animating. Nothing in the game reads it.
_G.StarPetsWorldMotion = {
	counts = function() return #eggs, #rings, #orbs end,
}
