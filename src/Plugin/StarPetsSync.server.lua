-- StarPets: StarPetsSync — a Studio plugin that pulls the game from GitHub.
--
-- WHY THIS EXISTS
--
-- Every change I make has had to be handed over as a file for someone to
-- install by hand, and for a month that step is where the work stopped. I run
-- on a server; Roblox Studio runs on your computer; there is no route from one
-- to the other.
--
-- But there is a route from BOTH to GitHub. I can push to the repository, and
-- Studio can fetch a URL. So the repository becomes the bridge: I push, you
-- press one button (or leave auto-sync on and press nothing), and your place
-- updates itself.
--
-- WHAT IT TOUCHES
--
-- Exactly three folders: ServerScriptService.Server, ReplicatedStorage.Shared
-- and StarterPlayerScripts.Client. It replaces those and nothing else. Your
-- map, your models, your settings and anything you have built are never read
-- and never written.
--
-- It refuses to run during Play, because Studio discards everything changed
-- while playing — a sync that appeared to work and then vanished on Stop would
-- be worse than no sync at all.

local HttpService         = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local StarterPlayer       = game:GetService("StarterPlayer")
local RunService          = game:GetService("RunService")

local OWNER  = "qutaibahq8-source"
local REPO   = "StarPets"
local BRANCH = "claude/fable-5-game-dev-phjg17"

local RAW = ("https://raw.githubusercontent.com/%s/%s/refs/heads/%s/")
	:format(OWNER, REPO, BRANCH)
local MANIFEST = RAW .. "bridge/manifest.json"

local POLL_SECONDS = 20

local toolbar = plugin:CreateToolbar("StarPets")
local syncButton = toolbar:CreateButton(
	"StarPetsSync",
	"Pull the latest StarPets code from GitHub into this place",
	"rbxasset://textures/ui/common/download.png",
	"Sync now")
local autoButton = toolbar:CreateButton(
	"StarPetsAuto",
	"Check GitHub every 20 seconds and sync automatically",
	"rbxasset://textures/ui/common/robux.png",
	"Auto-sync")
-- OFF unless you turn it on, and it stays off until you do.
--
-- Syncing code is one thing; letting a remote author RUN code in your Studio
-- is another, and it should never be something that just starts happening.
-- Every command is printed before it runs, and this button revokes it
-- instantly.
local cmdButton = toolbar:CreateButton(
	"StarPetsCommands",
	"Let Claude run build commands in this place (prints each one first)",
	"rbxasset://textures/ui/common/settings.png",
	"Allow commands")

local function say(fmt, ...)
	print("[StarPetsSync] " .. string.format(fmt, ...))
end

-- ============================================================
-- FETCHING
-- ============================================================
-- Cache-busting matters more than it looks. raw.githubusercontent caches
-- aggressively, so a sync run moments after a push can quietly return the OLD
-- file — which presents as "I pushed a fix and nothing changed", the exact
-- failure this whole plugin exists to end.
local function fetch(url)
	local bust = url .. (string.find(url, "?", 1, true) and "&" or "?")
		.. "t=" .. tostring(os.time()) .. tostring(math.random(1e6))
	local ok, res = pcall(function()
		return HttpService:GetAsync(bust, true)
	end)
	if ok then return res end
	return nil, tostring(res)
end

-- ============================================================
-- BUILDING
-- ============================================================
local function classFor(path)
	if string.sub(path, -11) == ".server.lua" then return "Script" end
	if string.sub(path, -11) == ".client.lua" then return "LocalScript" end
	return "ModuleScript"
end

-- Build the folder OFF to the side first and only swap it in once every file
-- has arrived. A sync that dies half way through — a dropped connection, a
-- 404 on one file — must not leave the place with half the game in it, which
-- is far harder to notice and diagnose than a sync that plainly failed.
local function buildFolder(name, entries)
	local root = Instance.new("Folder")
	root.Name = name
	for _, e in ipairs(entries) do
		local src, err = fetch(RAW .. e.path)
		if not src then
			root:Destroy()
			return nil, ("could not fetch %s (%s)"):format(e.path, err or "?")
		end
		local parent = root
		for _, seg in ipairs(e.folders or {}) do
			local f = parent:FindFirstChild(seg)
			if not f then
				f = Instance.new("Folder"); f.Name = seg; f.Parent = parent
			end
			parent = f
		end
		local s = Instance.new(classFor(e.path))
		s.Name = e.name
		s.Source = src
		s.Parent = parent
	end
	return root
end

local DESTINATIONS = {
	Server = function() return ServerScriptService end,
	Shared = function() return ReplicatedStorage end,
	Client = function() return StarterPlayer:FindFirstChild("StarterPlayerScripts") end,
}

local function sync(quiet)
	if RunService:IsRunning() then
		if not quiet then
			warn("[StarPetsSync] You are in PLAY mode. Press Stop first — "
				.. "anything changed while playing is discarded on Stop, so the "
				.. "sync would appear to work and then vanish.")
		end
		return false, "play mode"
	end

	local raw, err = fetch(MANIFEST)
	if not raw then
		warn("[StarPetsSync] Could not reach GitHub: " .. tostring(err))
		warn("  If that says 'Http requests are not enabled', open "
			.. "Game Settings > Security and switch on 'Allow HTTP Requests'.")
		return false, "no network"
	end

	local ok, manifest = pcall(function() return HttpService:JSONDecode(raw) end)
	if not ok or type(manifest) ~= "table" or not manifest.files then
		warn("[StarPetsSync] The manifest did not parse. Nothing was changed.")
		return false, "bad manifest"
	end

	local version = tostring(manifest.version or "?")
	if quiet and plugin:GetSetting("StarPetsVersion") == version then
		return false, "already current"      -- auto-poll, nothing new
	end

	-- Group by which of the three folders each file belongs to.
	local groups = {}
	for _, e in ipairs(manifest.files) do
		groups[e.group] = groups[e.group] or {}
		table.insert(groups[e.group], e)
	end

	local built, failed = {}, nil
	for name, entries in pairs(groups) do
		local folder, ferr = buildFolder(name, entries)
		if not folder then failed = ferr; break end
		built[name] = folder
	end
	if failed then
		for _, f in pairs(built) do f:Destroy() end
		warn("[StarPetsSync] Sync aborted, nothing changed: " .. failed)
		return false, failed
	end

	-- Everything arrived. Now swap.
	local swapped, total = 0, 0
	for name, folder in pairs(built) do
		local dest = DESTINATIONS[name] and DESTINATIONS[name]()
		if not dest then
			folder:Destroy()
			warn("[StarPetsSync] no destination for " .. name .. " in this place")
		else
			local old = dest:FindFirstChild(name)
			if old then old:Destroy() end
			folder.Parent = dest
			swapped = swapped + 1
			for _, d in ipairs(folder:GetDescendants()) do
				if d:IsA("LuaSourceContainer") then total = total + 1 end
			end
		end
	end

	plugin:SetSetting("StarPetsVersion", version)
	say("synced %d folder(s), %d scripts, version %s", swapped, total,
		string.sub(version, 1, 8))
	say("press Play to see it. Ctrl+S to keep it.")
	return true, version
end

-- ============================================================
-- COMMANDS
-- ============================================================
-- The sync above moves CODE. This moves ACTIONS: a chunk of Luau that runs in
-- edit mode, so the map can be rebuilt, a part moved, a property changed —
-- while you watch, without anyone installing anything.
--
-- loadstring is not reliably available to a plugin, so the source is put into
-- a real ModuleScript and required. A fresh instance each time, because require
-- caches per instance and a reused one would silently run the first version
-- forever.
local function runLuau(source, label)
	-- loadstring first. A plugin runs with script-injection permission, so it
	-- is available here even though a normal server Script needs
	-- LoadStringEnabled. It is also the only path that works without creating
	-- an instance in the place.
	if type(loadstring) == "function" then
		local chunk, err = loadstring(source, label)
		if not chunk then
			warn(("[StarPetsSync] command %q did not compile: %s")
				:format(label, tostring(err)))
			return false, err
		end
		local ok, res = pcall(chunk)
		if not ok then
			warn(("[StarPetsSync] command %q failed: %s"):format(label, tostring(res)))
			return false, res
		end
		if type(res) == "function" then
			local ok2, res2 = pcall(res)
			if not ok2 then
				warn(("[StarPetsSync] command %q failed: %s")
					:format(label, tostring(res2)))
				return false, res2
			end
			return true, res2
		end
		return true, res
	end

	-- Fallback: a real ModuleScript, required. A FRESH instance every time,
	-- because require caches per instance and a reused one would silently run
	-- the first version of a command forever.
	local holder = Instance.new("Folder")
	holder.Name = "StarPetsCommand"
	holder.Parent = ServerScriptService

	local mod = Instance.new("ModuleScript")
	mod.Name = "Cmd"
	mod.Source = source
	mod.Parent = holder

	local ok, res = pcall(function() return require(mod) end)
	holder:Destroy()

	if not ok then
		warn(("[StarPetsSync] command %q failed: %s"):format(label, tostring(res)))
		return false, res
	end
	-- A command may return a function to call, or simply do its work on load.
	if type(res) == "function" then
		local ok2, res2 = pcall(res)
		if not ok2 then
			warn(("[StarPetsSync] command %q failed: %s"):format(label, tostring(res2)))
			return false, res2
		end
		return true, res2
	end
	return true, res
end

local function runCommands()
	if RunService:IsRunning() then return end

	local raw = fetch(RAW .. "bridge/commands.json")
	if not raw then return end
	local ok, doc = pcall(function() return HttpService:JSONDecode(raw) end)
	if not ok or type(doc) ~= "table" or type(doc.commands) ~= "table" then
		return
	end

	local done = plugin:GetSetting("StarPetsRanCommands") or ""
	for _, c in ipairs(doc.commands) do
		local id = tostring(c.id or "")
		if id ~= "" and not string.find(done, "[" .. id .. "]", 1, true) then
			say("running command: %s", tostring(c.label or id))
			-- Printed BEFORE it runs, every time, so nothing happens in your
			-- place that you did not see described first.
			local good = runLuau(tostring(c.luau or ""), tostring(c.label or id))
			done = done .. "[" .. id .. "]"
			plugin:SetSetting("StarPetsRanCommands", done)
			if good then say("  done: %s", tostring(c.label or id)) end
		end
	end
end

-- ============================================================
-- BUTTONS
-- ============================================================
syncButton.Click:Connect(function()
	syncButton:SetActive(true)
	sync(false)
	syncButton:SetActive(false)
end)

local auto = plugin:GetSetting("StarPetsAuto") == true
autoButton:SetActive(auto)

autoButton.Click:Connect(function()
	auto = not auto
	plugin:SetSetting("StarPetsAuto", auto)
	autoButton:SetActive(auto)
	say(auto and "auto-sync ON — checking every %d seconds"
		or "auto-sync OFF", POLL_SECONDS)
	if auto then sync(true) end
end)

local commandsOn = plugin:GetSetting("StarPetsCommandsOn") == true
cmdButton:SetActive(commandsOn)

cmdButton.Click:Connect(function()
	commandsOn = not commandsOn
	plugin:SetSetting("StarPetsCommandsOn", commandsOn)
	cmdButton:SetActive(commandsOn)
	if commandsOn then
		say("commands ALLOWED. Each one is printed here before it runs. "
			.. "Click the button again to revoke.")
		pcall(runCommands)
	else
		say("commands blocked.")
	end
end)

task.spawn(function()
	while true do
		task.wait(POLL_SECONDS)
		if not RunService:IsRunning() then
			if auto then pcall(sync, true) end
			if commandsOn then pcall(runCommands) end
		end
	end
end)

say("ready. Click 'Sync now' to pull the latest code from GitHub.")
if auto then
	say("auto-sync is on.")
	task.spawn(function() task.wait(2); pcall(sync, true) end)
end
