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
local ServerStorage       = game:GetService("ServerStorage")
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

-- Snapshot: the return leg. Off to the side of everything else, because it is
-- the one button here that sends information OUT rather than bringing code in.
local snapButton = toolbar:CreateButton(
	"StarPetsSnapshot",
	"Describe this place as text you can paste back to Claude",
	"rbxasset://textures/ui/common/search.png",
	"Snapshot")

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

-- "UI/ShopPanel" — a path relative to the folder being replaced, so the old and
-- the new copy of the same file can be lined up. GetFullName would do it in
-- Studio, but it answers with the whole path from the DataModel down, which is
-- the wrong thing to key on when the two folders live in different places.
function relPath(inst, root)
	local parts, n = {}, inst
	while n and n ~= root do
		table.insert(parts, 1, n.Name)
		n = n.Parent
	end
	return table.concat(parts, "/")
end

local BACKUPS_KEPT = 3

-- Park the folder being replaced rather than deleting it. ServerStorage is the
-- right shelf: nothing in there runs, so a kept copy cannot become a second
-- GameServer quietly running alongside the real one.
function archive(old)
	local shelf = ServerStorage:FindFirstChild("StarPetsBackup")
	if not shelf then
		shelf = Instance.new("Folder")
		shelf.Name = "StarPetsBackup"
		shelf.Parent = ServerStorage
	end

	-- One slot per sync, never shared. Two syncs inside the same second would
	-- otherwise both land in one folder and the second copy of Server would sit
	-- beside the first, which is not a backup, it is a mess.
	local stamp = os.date("!%Y-%m-%d %H-%M-%S")
	local base, n = stamp, 1
	while shelf:FindFirstChild(stamp) do
		n = n + 1
		stamp = base .. " (" .. n .. ")"
	end
	local slot = Instance.new("Folder")
	slot.Name = stamp
	slot.Parent = shelf
	old.Parent = slot

	-- Keep the last few and no more. An unbounded shelf turns into a place file
	-- that grows by the whole codebase on every sync.
	local slots = shelf:GetChildren()
	if #slots > BACKUPS_KEPT then
		table.sort(slots, function(a, b) return a.Name < b.Name end)
		for i = 1, #slots - BACKUPS_KEPT do slots[i]:Destroy() end
	end
	return "StarPetsBackup > " .. stamp
end

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
	--
	-- The old folder is SET ASIDE, never destroyed. A sync replaces the three
	-- code folders wholesale, so anything edited by hand in Studio is replaced
	-- too — and the first anyone knows about it is "everything I customised went
	-- back to normal", with the work already gone. It cannot go now: the
	-- previous version is parked in ServerStorage, and the count of files that
	-- differed is printed so a silent overwrite is not possible either.
	local swapped, total, edited = 0, 0, 0
	local backupNote = nil
	for name, folder in pairs(built) do
		local dest = DESTINATIONS[name] and DESTINATIONS[name]()
		if not dest then
			folder:Destroy()
			warn("[StarPetsSync] no destination for " .. name .. " in this place")
		else
			local old = dest:FindFirstChild(name)
			if old then
				local oldSrc = {}
				for _, d in ipairs(old:GetDescendants()) do
					if d:IsA("LuaSourceContainer") then
						oldSrc[relPath(d, old)] = d.Source
					end
				end
				for _, d in ipairs(folder:GetDescendants()) do
					if d:IsA("LuaSourceContainer") then
						local was = oldSrc[relPath(d, folder)]
						if was ~= nil and was ~= d.Source then edited = edited + 1 end
					end
				end
				backupNote = archive(old)
			end
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
	if edited > 0 then
		say("%d file(s) were different from what is now installed. If any of "
			.. "that was yours, it is not lost:", edited)
	end
	if backupNote then
		say("  the previous version is in ServerStorage > %s", backupNote)
	end
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
-- SNAPSHOT — the return leg of the bridge
-- ============================================================
-- Everything above carries work INTO the place. This carries a description of
-- the place back OUT, as text you select and paste into the conversation.
--
-- That closes the loop with no API key and no token: whoever is on the other end
-- can see what is actually in here instead of inferring it from what they last
-- pushed. "I pushed a fix and nothing changed" has been the most expensive
-- sentence in this project's history, and until now it was unanswerable from the
-- outside — the cause is always one of a handful of things, and every one of
-- them is visible from in here.
--
-- It only reads. It cannot leak a credential even by accident: Studio keeps
-- plugin settings per plugin, so this plugin cannot see the AI panel's stored
-- API key, and the only setting printed below is the sync version stamp.

local function lineCount(src)
	if type(src) ~= "string" or src == "" then return 0 end
	local _, n = string.gsub(src, "\n", "")
	return n + 1
end

local function comma(n)
	local s = tostring(n)
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- "Client/UI/ShopPanel" for anything under a managed folder, which is the same
-- shape the manifest describes files in. Comparing those two sets is what turns
-- "it looks synced" into "these three files are missing".
local function pathsUnder(root, prefix, out)
	if not root then return out end
	for _, c in ipairs(root:GetChildren()) do
		local here = prefix .. "/" .. c.Name
		if c:IsA("LuaSourceContainer") then
			out[here] = c
		elseif c:IsA("Folder") then
			pathsUnder(c, here, out)
		end
	end
	return out
end

local function buildReport()
	local L = {}
	local function w(fmt, ...)
		if select("#", ...) > 0 then
			table.insert(L, string.format(fmt, ...))
		else
			table.insert(L, fmt)
		end
	end
	local warnings = {}

	w("STARPETS SNAPSHOT   %s UTC", os.date("!%Y-%m-%d %H:%M"))
	w("place: %s   PlaceId %s", tostring(game.Name), tostring(game.PlaceId))
	w("mode: %s", RunService:IsRunning() and "PLAY (press Stop before syncing)"
		or "edit")
	local okHttp, httpOn = pcall(function() return HttpService.HttpEnabled end)
	w("http requests: %s", (okHttp and httpOn ~= nil) and tostring(httpOn) or "unknown")
	w("auto-sync: %s   commands: %s",
		plugin:GetSetting("StarPetsAuto") == true and "on" or "off",
		plugin:GetSetting("StarPetsCommandsOn") == true and "on" or "off")

	-- ---- what the place holds vs what was pushed ----------------
	local here = pathsUnder(ServerScriptService:FindFirstChild("Server"), "Server", {})
	pathsUnder(ReplicatedStorage:FindFirstChild("Shared"), "Shared", here)
	local sps = StarterPlayer:FindFirstChild("StarterPlayerScripts")
	pathsUnder(sps and sps:FindFirstChild("Client"), "Client", here)

	local stamp = plugin:GetSetting("StarPetsVersion")
	w("")
	w("CODE IN THE PLACE")
	local raw = fetch(MANIFEST)
	local manifest
	if raw then
		local ok, doc = pcall(function() return HttpService:JSONDecode(raw) end)
		if ok and type(doc) == "table" and doc.files then manifest = doc end
	end

	if manifest then
		local expect, missing = {}, {}
		for _, e in ipairs(manifest.files) do
			local key = e.group
			for _, seg in ipairs(e.folders or {}) do key = key .. "/" .. seg end
			key = key .. "/" .. e.name
			expect[key] = true
			if not here[key] then table.insert(missing, key) end
		end
		local extra = {}
		for key in pairs(here) do
			if not expect[key] then table.insert(extra, key) end
		end
		table.sort(missing); table.sort(extra)

		local live = tostring(manifest.version or "?"):sub(1, 8)
		local mine = stamp and tostring(stamp):sub(1, 8) or "never synced"
		w("  on GitHub: %d files, version %s", #manifest.files, live)
		w("  in place:  %d files, last synced %s",
			(function() local n = 0 for _ in pairs(here) do n = n + 1 end return n end)(),
			mine)
		if mine ~= live then
			table.insert(warnings, ("this place is on %s but GitHub has %s — press "
				.. "'Sync now'"):format(mine, live))
		end
		if #missing > 0 then
			w("  MISSING (%d):", #missing)
			for i = 1, math.min(#missing, 25) do w("    %s", missing[i]) end
			table.insert(warnings, #missing .. " file(s) from the manifest are not "
				.. "in the place")
		end
		if #extra > 0 then
			w("  not in the manifest (%d):", #extra)
			for i = 1, math.min(#extra, 25) do w("    %s", extra[i]) end
		end
	else
		w("  could not reach GitHub, so this is what is here with nothing to")
		w("  compare against. last synced: %s",
			stamp and tostring(stamp):sub(1, 8) or "never")
		table.insert(warnings, "GitHub was unreachable — turn on Game Settings > "
			.. "Security > Allow HTTP Requests")
	end

	-- Two copies of the game running at once looks EXACTLY like an update that
	-- did nothing, and it is the single most common way an install goes wrong.
	for _, pair in ipairs({ { ServerScriptService, "Server" },
	                        { ReplicatedStorage, "Shared" },
	                        { sps, "Client" } }) do
		local parent, name = pair[1], pair[2]
		if parent then
			local n = 0
			for _, c in ipairs(parent:GetChildren()) do
				if c.Name == name then n = n + 1 end
			end
			if n == 0 then
				table.insert(warnings, ("there is no %s folder in %s at all")
					:format(name, parent.Name))
			elseif n > 1 then
				table.insert(warnings, ("%d copies of %s — two copies of the game "
					.. "run at once, which looks exactly like nothing changed")
					:format(n, name))
			end
		end
	end

	local gs = ServerScriptService:FindFirstChild("Server")
	gs = gs and gs:FindFirstChild("GameServer")
	if not gs then
		table.insert(warnings, "GameServer is missing — the map never builds")
	elseif gs.ClassName ~= "Script" then
		table.insert(warnings, "GameServer is a " .. gs.ClassName
			.. ", not a Script, so it never runs")
	end

	w("")
	w("  per folder:")
	for _, name in ipairs({ "Server", "Shared", "Client" }) do
		local n, lines = 0, 0
		for key, inst in pairs(here) do
			if key:sub(1, #name) == name then
				n = n + 1
				lines = lines + lineCount(inst.Source)
			end
		end
		w("    %-7s %3d scripts  %s lines", name, n, comma(lines))
	end

	-- ---- the world ----------------------------------------------
	w("")
	w("WORKSPACE")
	local map = workspace:FindFirstChild("StarPetsMap")
	local parts, neon = 0, 0
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") then
			parts = parts + 1
			if d.Material == Enum.Material.Neon then neon = neon + 1 end
		end
	end
	w("  parts in Workspace: %s   neon: %d", comma(parts), neon)
	if map then
		w("  StarPetsMap: present, baked=%s",
			tostring(map:GetAttribute("StarPetsBaked") == true))
		local loose = 0
		for _, world in ipairs(map:GetChildren()) do
			if world:IsA("Folder") or world:IsA("Model") then
				local n = 0
				for _, d in ipairs(world:GetDescendants()) do
					if d:IsA("BasePart") then n = n + 1 end
				end
				w("    %-12s %4d parts", world.Name, n)
			elseif world:IsA("BasePart") then
				loose = loose + 1
			end
		end
		if loose > 0 then
			w("    (%d part(s) sitting loose in StarPetsMap, in no world)", loose)
		end
		if map:GetAttribute("StarPetsBaked") ~= true then
			table.insert(warnings, "the map is not baked, so it is rebuilt every "
				.. "Play and your edits to it are discarded on Stop")
		end
	else
		w("  StarPetsMap: NOT PRESENT (the map has never been baked into this place)")
	end
	w("  top level: ")
	local names = {}
	for _, c in ipairs(workspace:GetChildren()) do table.insert(names, c.Name) end
	table.sort(names)
	w("    %s", table.concat(names, ", "))

	-- ---- the folders the client blocks on ------------------------
	-- Read out of the client's own source rather than from a list kept here. A
	-- hardcoded list goes stale the moment someone renames a folder, and the
	-- symptom of that is a player frozen on join with no error at all.
	local waits, seen = {}, {}
	for key, inst in pairs(here) do
		if key:sub(1, 6) == "Client" then
			for n in string.gmatch(tostring(inst.Source or ""),
					'workspace:WaitForChild%(%s*"([%w_]+)"') do
				if not seen[n] then seen[n] = true; table.insert(waits, n) end
			end
		end
	end
	table.sort(waits)
	if #waits > 0 then
		w("")
		w("FOLDERS THE CLIENT WAITS FOR")
		for _, n in ipairs(waits) do
			local found = workspace:FindFirstChild(n) ~= nil
			w("  %-16s %s", n, found and "ok" or "MISSING")
			if not found then
				table.insert(warnings, ("the client waits for workspace.%s and it "
					.. "is not there — joining players hang on that line"):format(n))
			end
		end
	end

	w("")
	if #warnings == 0 then
		w("WARNINGS: none")
	else
		w("WARNINGS (%d)", #warnings)
		for _, ww in ipairs(warnings) do w("  - %s", ww) end
	end
	return table.concat(L, "\n"), #warnings
end

local reportWidget, reportBox

local function ensureReportUI()
	if reportWidget then return end
	reportWidget = plugin:CreateDockWidgetPluginGui("StarPetsSnapshot",
		DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, true,
			620, 640, 380, 300))
	reportWidget.Title = "StarPets snapshot - click inside, Ctrl+A, Ctrl+C, paste to Claude"

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(37, 37, 37)
	frame.BorderSizePixel = 0
	frame.Parent = reportWidget

	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = frame

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = scroll

	reportBox = Instance.new("TextBox")
	reportBox.Size = UDim2.new(1, 0, 0, 0)
	reportBox.AutomaticSize = Enum.AutomaticSize.Y
	reportBox.BackgroundTransparency = 1
	reportBox.Font = Enum.Font.Code
	reportBox.TextSize = 13
	reportBox.TextColor3 = Color3.fromRGB(230, 230, 230)
	reportBox.TextXAlignment = Enum.TextXAlignment.Left
	reportBox.TextYAlignment = Enum.TextYAlignment.Top
	-- Editable on purpose: a read-only TextBox cannot be focused, and without
	-- focus there is no Ctrl+A and no copy, which is the entire point of it.
	-- Every snapshot overwrites the text, so edits here cost nothing.
	reportBox.TextEditable = true
	reportBox.ClearTextOnFocus = false
	reportBox.MultiLine = true
	reportBox.TextWrapped = false
	reportBox.Text = ""
	reportBox.Parent = scroll
end

local function snapshot()
	ensureReportUI()
	local ok, report, warnings = pcall(buildReport)
	if not ok then
		warn("[StarPetsSync] the snapshot failed: " .. tostring(report))
		return
	end
	reportBox.Text = report
	reportWidget.Enabled = true
	say("snapshot ready: %d warning(s). Click inside the panel, Ctrl+A, Ctrl+C, "
		.. "and paste it to Claude.", warnings or 0)
end

-- ============================================================
-- BUTTONS
-- ============================================================
snapButton.Click:Connect(function()
	snapButton:SetActive(true)
	snapshot()
	snapButton:SetActive(false)
end)

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
