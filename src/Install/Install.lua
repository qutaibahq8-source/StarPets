-- StarPets: Install.lua
-- Ships inside StarPets_Install.rbxmx. Not part of the running game.
--
-- WHY THIS EXISTS
--
-- Installing this project by hand is six steps across three services, and one
-- of them is a DELETE that is easy to skip. Skipping it is not harmless:
-- "Insert from File" ADDS rather than replaces, so an old Server folder beside
-- a new one means two GameServer scripts, both running, both building a map on
-- top of each other. The result looks exactly like the update did nothing —
-- which then gets blamed on the update rather than on the install.
--
-- So: insert one model into Workspace, run one line in the Command Bar, done.
-- This does the deleting, the moving and the tidying up, and prints what it
-- did so there is no doubt about whether it worked.
--
--   require(workspace.StarPetsInstall.Install)()
--
-- Run it in EDIT MODE, not while playing. Changes made during Play are
-- discarded when you press Stop, which is the same trap that loses map edits.

local ServerScriptService   = game:GetService("ServerScriptService")
local ReplicatedStorage     = game:GetService("ReplicatedStorage")
local StarterPlayer         = game:GetService("StarterPlayer")
local RunService            = game:GetService("RunService")

-- folder name in the model  ->  where it belongs
local function destinations()
	local sps = StarterPlayer:FindFirstChild("StarterPlayerScripts")
	return {
		{ name = "Server", parent = ServerScriptService },
		{ name = "Shared", parent = ReplicatedStorage },
		{ name = "Client", parent = sps },
	}
end

return function()
	local log = { "", "[StarPets] installing..." }
	local function say(fmt, ...)
		table.insert(log, "  " .. string.format(fmt, ...))
	end

	if RunService:IsRunning() then
		warn("[StarPets] You are in PLAY mode. Press Stop first — anything "
			.. "changed while playing is discarded, so the install would not "
			.. "stick.")
		return false
	end

	local bundle = workspace:FindFirstChild("StarPetsInstall")
	if not bundle then
		warn("[StarPets] Could not find StarPetsInstall in Workspace. Insert "
			.. "StarPets_Install.rbxmx into Workspace first, then run this again.")
		return false
	end

	local moved, replaced, missing = 0, 0, {}
	for _, d in ipairs(destinations()) do
		local incoming = bundle:FindFirstChild(d.name)
		if not incoming then
			table.insert(missing, d.name)
		elseif not d.parent then
			table.insert(missing, d.name .. " (no StarterPlayerScripts in this place)")
		else
			-- Delete the old one FIRST. This is the step that gets skipped by
			-- hand, and skipping it is what produces two copies of the game
			-- running at once.
			local old = d.parent:FindFirstChild(d.name)
			if old then
				old:Destroy()
				replaced = replaced + 1
				say("replaced the existing %s in %s", d.name, d.parent.Name)
			else
				say("added %s to %s", d.name, d.parent.Name)
			end
			incoming.Parent = d.parent
			moved = moved + 1
		end
	end

	if #missing > 0 then
		warn("[StarPets] the model is missing: " .. table.concat(missing, ", "))
	end

	-- Leave nothing behind in Workspace, whether or not every folder moved.
	-- An earlier version only cleaned up when the wrapper was empty, and it
	-- never was — this module is still inside it. So the installer left itself
	-- in Workspace, and running the line a second time found a wrapper with
	-- nothing in it and reported all three folders missing, which reads like a
	-- failure when the install actually worked.
	--
	-- Destroying the ModuleScript from inside its own returned function is
	-- fine: the closure is already loaded.
	local strays = {}
	for _, child in ipairs(bundle:GetChildren()) do
		if child.Name ~= "Install" then table.insert(strays, child.Name) end
	end
	if #strays > 0 then
		warn("[StarPets] these did not move and are being discarded: "
			.. table.concat(strays, ", "))
	end
	bundle:Destroy()
	say("cleaned up the installer")

	-- Count what is now installed, so the result is a fact rather than a hope.
	-- Counted by concrete class rather than by the LuaSourceContainer base.
	-- If that base name were ever wrong the count would silently read 0, and a
	-- successful install would print "0 scripts now present" — which is exactly
	-- the sort of alarming-but-meaningless number that makes somebody think an
	-- update failed when it did not.
	local scripts = 0
	for _, svc in ipairs({ ServerScriptService, ReplicatedStorage, StarterPlayer }) do
		for _, x in ipairs(svc:GetDescendants()) do
			if x:IsA("Script") or x:IsA("LocalScript") or x:IsA("ModuleScript") then
				scripts = scripts + 1
			end
		end
	end

	-- The duplicate check, stated plainly, because this is the one failure that
	-- looks like "nothing changed".
	local servers = 0
	for _, x in ipairs(ServerScriptService:GetDescendants()) do
		if x:IsA("Script") and x.Name == "GameServer" then servers = servers + 1 end
	end

	say("%d folder(s) installed, %d replaced, %d scripts now present",
		moved, replaced, scripts)
	if servers == 1 then
		say("exactly one GameServer — correct")
	else
		say("PROBLEM: %d copies of GameServer. Delete the extras or the map "
			.. "builds twice and looks unchanged.", servers)
	end
	table.insert(log, "  Now press Play. Save the place (Ctrl+S) to keep it.")
	table.insert(log, "")
	print(table.concat(log, "\n"))
	return servers == 1
end
