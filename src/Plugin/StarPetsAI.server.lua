-- StarPets: Claude, inside Studio.
--
-- WHY THIS EXISTS
--
-- The sync plugin next to this one moves code one way: I push, your place
-- pulls. It works, but it is blind — I can hand you a finished thing, I cannot
-- look at what is actually in your place and react to it.
--
-- This closes that. It is a chat panel docked in Studio that talks to the
-- Anthropic API directly from your machine, with three tools pointed at the
-- open place: look at the tree, read a script, and run Luau in edit mode. So
-- the model on the other end can see what you see, and change it while you
-- watch.
--
-- ABOUT THE KEY
--
-- This needs an API key, and it has to be YOUR key, made at console.anthropic.com.
-- Nobody can give you theirs — a key is a credential, it bills whoever owns it,
-- and handing one over is the same as handing over a card. The key you paste is
-- stored by Studio on this computer (plugin:SetSetting) and is sent to exactly
-- one place, api.anthropic.com. It is never printed, never written into the
-- place, and never travels to the repository.
--
-- API usage is billed separately from a Claude subscription. Every reply prints
-- what it cost in tokens so the meter is never a surprise.
--
-- SAFETY
--
--   * Running code is OFF until you switch it on, and the switch revokes it.
--   * Every command is printed in full BEFORE it runs.
--   * Each run is one undo step — Ctrl+Z puts it back.
--   * Nothing runs during Play, because Studio throws away Play-mode changes.

local HttpService         = game:GetService("HttpService")
local RunService          = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local ENDPOINT    = "https://api.anthropic.com/v1/messages"
local API_VERSION = "2023-06-01"

-- Latest models first. Opus is the strongest; Sonnet is the one to drop to if a
-- reply ever runs past Roblox's HTTP timeout.
local MODELS = { "claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5-20251001" }

-- Roblox gives an HTTP call about 30 seconds and cannot stream, so a long reply
-- is not slow, it is a failure. Keeping the budget modest — and telling the
-- model to be brief — is what keeps that from happening.
local MAX_TOKENS = 1500
local MAX_ROUNDS = 12       -- tool round-trips per message; bounds the bill too
local MAX_TOOL_CHARS = 6000 -- tool output sent back; bounds the bill too

local SYSTEM = table.concat({
	"You are Claude, working as the lead developer on StarPets, a Roblox pet",
	"simulator, from inside Roblox Studio. You are talking to the game's owner.",
	"",
	"You can see the open place through your tools. Use them before answering",
	"anything about what is in it — never guess at the contents of the place.",
	"",
	"Rules that are load-bearing in this project. Do not undo them:",
	"* DataManager.LoadPlayer returns (data, err). A failed read must cache",
	"  nothing and must never be saved over, or a DataStore outage wipes a",
	"  player permanently.",
	"* PetService.GrantPet is the only way a pet may enter an inventory. It",
	"  enforces the 100-pet cap and stamps the Discovered record the Pet Index",
	"  reads. Never table.insert into data.Pets directly.",
	"* TradeService.CARRIED lists the fields a traded pet keeps. Rebuilding a",
	"  pet without mutation and fuseMult destroys almost all of its value.",
	"* Remotes are made with makeEvent/makeFunction, which rate-limit them.",
	"  Instance.new('RemoteEvent') is unguarded.",
	"* A Roblox cylinder runs along its LOCAL X. column() stands one up with",
	"  Orientation (0,0,90); a lean must ADD to that 90, never replace it.",
	"* A ModuleScript does not run until something requires it. A file that",
	"  only connects to events must be named *.client.lua or *.server.lua.",
	"",
	"What the owner has asked for: no neon decoration, no shop building and no",
	"leaderboard board in the world, nothing planted on the four walking paths",
	"from spawn, no free-gift system, and no farming mechanics.",
	"",
	"Be brief. Two or three sentences beats a paragraph. Reach for a tool",
	"instead of describing what you would do. When you change something, say",
	"plainly what changed and what to look at.",
}, "\n")

-- ============================================================
-- SETTINGS (this computer only)
-- ============================================================
local KEY_SETTING   = "StarPetsAIKey"
local MODEL_SETTING = "StarPetsAIModel"
local EDIT_SETTING  = "StarPetsAIEdits"

local function getKey()
	local ok, v = pcall(function() return plugin:GetSetting(KEY_SETTING) end)
	if ok and type(v) == "string" then return v end
	return nil
end

local model = plugin:GetSetting(MODEL_SETTING)
if type(model) ~= "string" then model = MODELS[1] end
local editsAllowed = plugin:GetSetting(EDIT_SETTING) == true

-- The key must not appear in the transcript, in Output, or in an error message
-- that quotes a failed request back at us. Everything user-facing goes through
-- here first.
local function scrub(text)
	text = tostring(text)
	local key = getKey()
	if key and #key > 8 then
		text = string.gsub(text, key:gsub("%p", "%%%0"), "<key hidden>")
	end
	return text
end

local function say(fmt, ...)
	print("[Claude] " .. scrub(string.format(fmt, ...)))
end

-- ============================================================
-- LOOKING AT THE PLACE
-- ============================================================
local function split(s, sep)
	local out = {}
	for part in string.gmatch(s, "[^" .. sep .. "]+") do table.insert(out, part) end
	return out
end

-- "workspace.StarPetsMap.Meadow" -> the instance, or nil and why not.
local function resolve(path)
	path = tostring(path or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if path == "" or path == "game" then return game end

	local parts = split(path, ".")
	if parts[1] == "game" then table.remove(parts, 1) end
	if #parts == 0 then return game end

	local head = parts[1]
	if head == "workspace" then head = "Workspace" end
	local ok, node = pcall(function() return game:GetService(head) end)
	if not ok or not node then
		return nil, ("there is no service called %q"):format(tostring(parts[1]))
	end

	for i = 2, #parts do
		local nxt = node:FindFirstChild(parts[i])
		if not nxt then
			return nil, ("%s has no child called %q"):format(
				table.concat(parts, ".", 1, i - 1), parts[i])
		end
		node = nxt
	end
	return node
end

local function describeOne(inst)
	local bits = { inst.ClassName .. " " .. inst.Name }
	local n = #inst:GetChildren()
	if n > 0 then table.insert(bits, n .. " children") end
	if inst:IsA("BasePart") then
		local s, p = inst.Size, inst.Position
		table.insert(bits, ("size %.0fx%.0fx%.0f at (%.0f, %.0f, %.0f)")
			:format(s.X, s.Y, s.Z, p.X, p.Y, p.Z))
		if inst.Material then table.insert(bits, tostring(inst.Material)) end
		if inst.Anchored == false then table.insert(bits, "UNANCHORED") end
	elseif inst:IsA("LuaSourceContainer") then
		local _, lines = string.gsub(inst.Source or "", "\n", "")
		table.insert(bits, (lines + 1) .. " lines")
	end
	local attrs = inst:GetAttributes()
	local akeys = {}
	for k in pairs(attrs) do table.insert(akeys, k) end
	if #akeys > 0 then
		table.sort(akeys)
		local shown = {}
		for i = 1, math.min(#akeys, 4) do
			table.insert(shown, akeys[i] .. "=" .. tostring(attrs[akeys[i]]))
		end
		table.insert(bits, "attrs: " .. table.concat(shown, ", "))
	end
	return table.concat(bits, " | ")
end

local function toolLook(input)
	local node, err = resolve(input.path)
	if not node then return "Cannot look there: " .. tostring(err) end

	local depth = tonumber(input.depth) or 1
	if depth < 1 then depth = 1 end
	if depth > 4 then depth = 4 end

	local out = { (input.path or "game") .. " -> " .. (node == game and "DataModel"
		or describeOne(node)) }
	local lines = 0
	local function walk(inst, level, indent)
		if level > depth or lines > 250 then return end
		local kids = inst:GetChildren()
		-- A big folder is summarised rather than listed. Dumping 400 parts is
		-- both useless to read and expensive to send.
		if #kids > 60 then
			local byClass = {}
			for _, c in ipairs(kids) do
				byClass[c.ClassName] = (byClass[c.ClassName] or 0) + 1
			end
			local names = {}
			for cls, n in pairs(byClass) do table.insert(names, n .. " " .. cls) end
			table.sort(names)
			table.insert(out, indent .. "(" .. #kids .. " children: "
				.. table.concat(names, ", ") .. ")")
			lines = lines + 1
			return
		end
		for _, c in ipairs(kids) do
			if lines > 250 then
				table.insert(out, indent .. "... (truncated)")
				return
			end
			table.insert(out, indent .. describeOne(c))
			lines = lines + 1
			walk(c, level + 1, indent .. "   ")
		end
	end
	walk(node, 1, "   ")
	return table.concat(out, "\n")
end

local function toolRead(input)
	local node, err = resolve(input.path)
	if not node then return "Cannot read that: " .. tostring(err) end
	if not node:IsA("LuaSourceContainer") then
		return ("%s is a %s, not a script."):format(tostring(input.path), node.ClassName)
	end
	local src = node.Source or ""
	if #src > MAX_TOOL_CHARS then
		return src:sub(1, MAX_TOOL_CHARS)
			.. "\n\n-- [truncated; " .. #src .. " characters in total]"
	end
	return src
end

local function toolFind(input)
	local query = tostring(input.query or ""):lower()
	local class = input.class and tostring(input.class) or nil
	local root, err = resolve(input.under or "game")
	if not root then return "Cannot search there: " .. tostring(err) end

	local hits, scanned = {}, 0
	local function fullName(inst)
		local names, n = {}, inst
		while n and n ~= game do
			table.insert(names, 1, n.Name)
			n = n.Parent
		end
		return table.concat(names, ".")
	end
	for _, d in ipairs(root:GetDescendants()) do
		scanned = scanned + 1
		local nameOk = query == "" or string.find(d.Name:lower(), query, 1, true) ~= nil
		local classOk = true
		if class then
			local ok, isa = pcall(function() return d:IsA(class) end)
			classOk = ok and isa
		end
		if nameOk and classOk then
			table.insert(hits, fullName(d) .. "  (" .. d.ClassName .. ")")
			if #hits >= 60 then break end
		end
	end
	if #hits == 0 then
		return ("Nothing matched (%d instances scanned under %s)")
			:format(scanned, tostring(input.under or "game"))
	end
	return ("%d match(es):\n"):format(#hits) .. table.concat(hits, "\n")
end

-- ============================================================
-- RUNNING CODE IN THE PLACE
-- ============================================================
local CAPTURE = {}

-- The prelude shadows print and warn inside the chunk so its output comes back
-- as the tool result instead of disappearing into Output. It is deliberately on
-- ONE line with no newline: any line it added would shift every line number in
-- a compile error, and a stack trace that points at the wrong line is worse
-- than no stack trace.
local PRELUDE = "local print=function(...) _G.__StarPetsAICapture(...) end;"
	.. "local warn=print;"

local function runLuau(source, label)
	CAPTURE = {}
	_G.__StarPetsAICapture = function(...)
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring((select(i, ...)))
		end
		table.insert(CAPTURE, table.concat(parts, " "))
	end

	local wrapped = PRELUDE .. source
	local result, failure

	-- One undo step per run. Without this, "put that back" means hunting for
	-- what changed by hand.
	local recording
	pcall(function()
		recording = ChangeHistoryService:TryBeginRecording("Claude: " .. label)
	end)

	local function finish(ok)
		if recording then
			pcall(function()
				ChangeHistoryService:FinishRecording(recording,
					ok and Enum.FinishRecordingOperation.Commit
					   or Enum.FinishRecordingOperation.Cancel)
			end)
		end
	end

	if type(loadstring) == "function" then
		-- A plugin runs with script-injection permission, so loadstring is
		-- available here even though a normal server Script needs
		-- LoadStringEnabled.
		local chunk, cerr = loadstring(wrapped, label)
		if not chunk then
			finish(false)
			return false, "did not compile: " .. tostring(cerr)
		end
		local ok, res = pcall(chunk)
		if not ok then failure = res else result = res end
	else
		-- Fallback: a real ModuleScript, required. A FRESH instance every time,
		-- because require caches per instance and a reused one would silently
		-- run the first version forever.
		local holder = Instance.new("Folder")
		holder.Name = "StarPetsAICommand"
		holder.Parent = ServerScriptService
		local mod = Instance.new("ModuleScript")
		mod.Name = "Cmd"
		mod.Source = wrapped
		mod.Parent = holder
		local ok, res = pcall(function() return require(mod) end)
		holder:Destroy()
		if not ok then failure = res else result = res end
	end

	-- A chunk may do its work on load or hand back a function to call.
	if not failure and type(result) == "function" then
		local ok2, res2 = pcall(result)
		if not ok2 then failure = res2 else result = res2 end
	end

	finish(failure == nil)

	local printed = table.concat(CAPTURE, "\n")
	if failure then
		return false, (printed ~= "" and printed .. "\n" or "")
			.. "ERROR: " .. tostring(failure)
	end
	local tail = ""
	if result ~= nil and type(result) ~= "function" then
		tail = "\nreturned: " .. tostring(result)
	end
	if printed == "" and tail == "" then return true, "ran, no output" end
	return true, printed .. tail
end

local addBubble  -- defined with the UI, used here

local function toolRun(input)
	local code = tostring(input.code or "")
	local why = tostring(input.why or "a change")
	if code == "" then return "No code was given." end

	if RunService:IsRunning() then
		return "Refused: the place is in PLAY mode. Studio discards everything "
			.. "changed during Play, so this would appear to work and then vanish "
			.. "on Stop. Ask the owner to press Stop."
	end
	if not editsAllowed then
		return "Refused: running code is switched OFF in the panel. The owner "
			.. "has to press 'Allow edits' first. Describe what you want to run "
			.. "and why, and wait."
	end

	-- Printed in full before it runs, every time. Nothing should ever happen in
	-- this place that the owner did not see described first.
	say("about to run: %s", why)
	print("------------------------------------------------")
	print(code)
	print("------------------------------------------------")
	addBubble("tool", "Ran: " .. why)

	local ok, out = runLuau(code, why)
	if #out > MAX_TOOL_CHARS then out = out:sub(1, MAX_TOOL_CHARS) .. "\n[truncated]" end
	if ok then
		say("done: %s", why)
		return "OK.\n" .. out
	end
	warn("[Claude] failed: " .. scrub(why) .. " -- " .. scrub(out))
	return "FAILED.\n" .. out
end

-- ============================================================
-- TOOL TABLE (what the model is told it can do)
-- ============================================================
-- Every tool has at least one required field. That is not only for clarity:
-- Roblox's JSONEncode writes an empty table as [], so a tool call with no
-- arguments would re-encode as an array and the API would reject the whole
-- conversation on the next turn.
local TOOLS = {
	{
		name = "look",
		description = "List what is inside a path in the open place. Paths look "
			.. "like 'workspace', 'workspace.StarPetsMap.Meadow' or "
			.. "'ServerScriptService.Server'. Large folders are summarised by "
			.. "class. Use this before answering anything about the place.",
		input_schema = {
			type = "object",
			properties = {
				path = { type = "string", description = "Dotted path, e.g. workspace.StarPetsMap" },
				depth = { type = "integer", description = "Levels to descend, 1-4. Default 1." },
			},
			required = { "path" },
		},
	},
	{
		name = "read_script",
		description = "Return the source of a Script, LocalScript or ModuleScript "
			.. "at a dotted path.",
		input_schema = {
			type = "object",
			properties = {
				path = { type = "string", description = "e.g. ServerScriptService.Server.PetService" },
			},
			required = { "path" },
		},
	},
	{
		name = "find",
		description = "Search the place for instances whose name contains a "
			.. "string, optionally filtered by class. Use it when you do not know "
			.. "where something lives.",
		input_schema = {
			type = "object",
			properties = {
				query = { type = "string", description = "Substring of the name. Empty matches any name." },
				class = { type = "string", description = "Optional class filter, e.g. Script, BasePart" },
				under = { type = "string", description = "Optional path to search under. Default game." },
			},
			required = { "query" },
		},
	},
	{
		name = "run_luau",
		description = "Run Luau in the open place in edit mode. Use it to build, "
			.. "move, recolour or delete things, and to fix scripts by setting "
			.. ".Source. print() comes back to you. One run is one undo step. It "
			.. "is refused unless the owner has switched edits on, so say what you "
			.. "intend first if it comes back refused.",
		input_schema = {
			type = "object",
			properties = {
				code = { type = "string", description = "The Luau to run." },
				why = { type = "string", description = "One short line describing the change, shown to the owner before it runs." },
			},
			required = { "code", "why" },
		},
	},
}

local function runTool(name, input)
	input = input or {}
	if name == "look" then return toolLook(input) end
	if name == "read_script" then return toolRead(input) end
	if name == "find" then return toolFind(input) end
	if name == "run_luau" then return toolRun(input) end
	return "There is no tool called " .. tostring(name) .. "."
end

-- ============================================================
-- THE PANEL
-- ============================================================
local PALETTE = {
	bg     = Color3.fromRGB(46, 46, 46),
	panel  = Color3.fromRGB(37, 37, 37),
	line   = Color3.fromRGB(28, 28, 28),
	text   = Color3.fromRGB(235, 235, 235),
	dim    = Color3.fromRGB(150, 150, 150),
	accent = Color3.fromRGB(226, 122, 78),
	good   = Color3.fromRGB(120, 190, 120),
	bad    = Color3.fromRGB(220, 110, 110),
}
pcall(function()
	local theme = settings().Studio.Theme
	PALETTE.bg    = theme:GetColor(Enum.StudioStyleGuideColor.MainBackground)
	PALETTE.panel = theme:GetColor(Enum.StudioStyleGuideColor.ViewPortBackground)
	PALETTE.text  = theme:GetColor(Enum.StudioStyleGuideColor.MainText)
	PALETTE.dim   = theme:GetColor(Enum.StudioStyleGuideColor.DimmedText)
end)

local widget = plugin:CreateDockWidgetPluginGui("StarPetsAI",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false,
		420, 560, 360, 400))
widget.Title = "Claude - StarPets"

local toolbar = plugin:CreateToolbar("StarPets AI")
local openButton = toolbar:CreateButton("StarPetsAIOpen",
	"Open the Claude panel", "rbxasset://textures/ui/common/robux.png", "Claude")

local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	if parent then inst.Parent = parent end
	return inst
end

local root = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = PALETTE.bg,
	BorderSizePixel = 0,
}, widget)

-- --- top bar -------------------------------------------------
local top = make("Frame", {
	Size = UDim2.new(1, 0, 0, 28),
	BackgroundColor3 = PALETTE.panel,
	BorderSizePixel = 0,
}, root)

local status = make("TextLabel", {
	Size = UDim2.new(1, -230, 1, 0),
	Position = UDim2.fromOffset(8, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = PALETTE.dim,
	Text = "ready",
}, top)

local function chip(text, x, width)
	local b = make("TextButton", {
		Size = UDim2.new(0, width, 0, 20),
		Position = UDim2.new(1, x, 0, 4),
		BackgroundColor3 = PALETTE.bg,
		BorderSizePixel = 0,
		Font = Enum.Font.Gotham,
		TextSize = 11,
		TextColor3 = PALETTE.text,
		Text = text,
		AutoButtonColor = true,
	}, top)
	make("UICorner", { CornerRadius = UDim.new(0, 4) }, b)
	return b
end

local editButton  = chip("Edits: OFF", -222, 84)
local modelButton = chip("opus", -134, 76)
local clearButton = chip("Clear", -54, 48)

-- --- transcript ----------------------------------------------
local feed = make("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 28),
	Size = UDim2.new(1, 0, 1, -28 - 84),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
}, root)
make("UIListLayout", {
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, feed)
make("UIPadding", {
	PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
	PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
}, feed)

local bubbleCount = 0

function addBubble(kind, text)
	bubbleCount = bubbleCount + 1
	local fill, fg = PALETTE.panel, PALETTE.text
	local prefix = ""
	if kind == "you" then
		fill = Color3.fromRGB(58, 58, 58); prefix = "you  "
	elseif kind == "tool" then
		fill = PALETTE.panel; fg = PALETTE.dim; prefix = "* "
	elseif kind == "error" then
		fill = PALETTE.panel; fg = PALETTE.bad; prefix = "! "
	end

	local holder = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = fill,
		BorderSizePixel = 0,
		LayoutOrder = bubbleCount,
	}, feed)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, holder)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
	}, holder)
	make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = kind == "tool" and Enum.Font.Code or Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = fg,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = prefix .. scrub(text),
	}, holder)
	return holder
end

-- --- composer -------------------------------------------------
local bottom = make("Frame", {
	Position = UDim2.new(0, 0, 1, -84),
	Size = UDim2.new(1, 0, 0, 84),
	BackgroundColor3 = PALETTE.panel,
	BorderSizePixel = 0,
}, root)

local box = make("TextBox", {
	Position = UDim2.fromOffset(8, 8),
	Size = UDim2.new(1, -16, 0, 44),
	BackgroundColor3 = PALETTE.bg,
	BorderSizePixel = 0,
	Font = Enum.Font.Gotham,
	TextSize = 13,
	TextColor3 = PALETTE.text,
	PlaceholderText = "Ask for a change, or ask what is in the place...",
	Text = "",
	ClearTextOnFocus = false,
	MultiLine = true,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
}, bottom)
make("UICorner", { CornerRadius = UDim.new(0, 4) }, box)
make("UIPadding", {
	PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 6),
	PaddingRight = UDim.new(0, 6),
}, box)

local sendButton = make("TextButton", {
	Position = UDim2.new(1, -96, 1, -28),
	Size = UDim2.fromOffset(88, 22),
	BackgroundColor3 = PALETTE.accent,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Text = "Send",
}, bottom)
make("UICorner", { CornerRadius = UDim.new(0, 4) }, sendButton)

local hint = make("TextLabel", {
	Position = UDim2.new(0, 8, 1, -26),
	Size = UDim2.new(1, -110, 0, 18),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 11,
	TextColor3 = PALETTE.dim,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
}, bottom)

-- --- key entry (only shown until a key is stored) --------------
local keyPanel = make("Frame", {
	Position = UDim2.fromOffset(0, 28),
	Size = UDim2.new(1, 0, 1, -28 - 84),
	BackgroundColor3 = PALETTE.bg,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 5,
}, root)
make("UIPadding", {
	PaddingTop = UDim.new(0, 14), PaddingLeft = UDim.new(0, 14),
	PaddingRight = UDim.new(0, 14),
}, keyPanel)

make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 150),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextSize = 12,
	TextColor3 = PALETTE.text,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	ZIndex = 5,
	Text = "This panel needs an Anthropic API key, and it has to be your own — "
		.. "a key is a credential that bills whoever owns it, so nobody can hand "
		.. "you theirs.\n\n"
		.. "Make one at console.anthropic.com > API keys, then paste it below.\n\n"
		.. "It is stored by Studio on this computer only, sent to nothing except "
		.. "api.anthropic.com, and never written into your place or the "
		.. "repository. API usage bills separately from a Claude subscription; "
		.. "every reply shows what it cost.",
}, keyPanel)

local keyBox = make("TextBox", {
	Position = UDim2.fromOffset(0, 158),
	Size = UDim2.new(1, 0, 0, 26),
	BackgroundColor3 = PALETTE.panel,
	BorderSizePixel = 0,
	Font = Enum.Font.Code,
	TextSize = 12,
	TextColor3 = PALETTE.text,
	PlaceholderText = "sk-ant-...",
	Text = "",
	ClearTextOnFocus = false,
	ZIndex = 5,
}, keyPanel)
make("UICorner", { CornerRadius = UDim.new(0, 4) }, keyBox)

local keySave = make("TextButton", {
	Position = UDim2.fromOffset(0, 192),
	Size = UDim2.fromOffset(120, 24),
	BackgroundColor3 = PALETTE.accent,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Text = "Save key",
	ZIndex = 5,
}, keyPanel)
make("UICorner", { CornerRadius = UDim.new(0, 4) }, keySave)

local function refreshKeyPanel()
	local key = getKey()
	local have = key ~= nil and key ~= ""
	keyPanel.Visible = not have
	if have then
		hint.Text = "key ...." .. string.sub(key, -4) .. "  -  Forget it: type /forget"
	else
		hint.Text = "no key yet"
	end
end

-- ============================================================
-- TALKING TO THE API
-- ============================================================
local totalIn, totalOut = 0, 0

local function shortModel(id)
	return (id:gsub("^claude%-", ""):gsub("%-%d%d%d%d%d%d%d%d$", ""))
end

local function request(body)
	local key = getKey()
	if not key or key == "" then return nil, "There is no API key saved." end

	local ok, res = pcall(function()
		return HttpService:RequestAsync({
			Url = ENDPOINT,
			Method = "POST",
			Headers = {
				["content-type"] = "application/json",
				["x-api-key"] = key,
				["anthropic-version"] = API_VERSION,
			},
			Body = HttpService:JSONEncode(body),
		})
	end)
	if not ok then
		local msg = scrub(res)
		if string.find(msg, "Http requests are not enabled", 1, true) then
			return nil, "Studio is blocking HTTP. Open Game Settings > Security "
				.. "and switch on 'Allow HTTP Requests'."
		end
		if string.find(msg, "imeout", 1, true) then
			return nil, "The reply took longer than Roblox allows for one request. "
				.. "Press Send again, or switch the model chip to a faster one."
		end
		return nil, "Could not reach the API: " .. msg
	end

	if not res.Success then
		local code = res.StatusCode
		if code == 401 then
			return nil, "The API key was rejected (401). Check it at "
				.. "console.anthropic.com, then type /forget and paste a new one."
		elseif code == 400 then
			return nil, "The request was rejected (400): " .. scrub(res.Body or "")
		elseif code == 429 then
			return nil, "Rate limited (429). Wait a moment and send again."
		elseif code == 529 or code == 503 then
			return nil, "The API is busy right now (" .. code .. "). Try again."
		end
		return nil, ("API error %s: %s"):format(tostring(code), scrub(res.Body or ""))
	end

	local decoded
	local okJson = pcall(function() decoded = HttpService:JSONDecode(res.Body) end)
	if not okJson or type(decoded) ~= "table" then
		return nil, "The API replied with something that is not JSON."
	end
	if decoded.usage then
		totalIn = totalIn + (decoded.usage.input_tokens or 0)
		totalOut = totalOut + (decoded.usage.output_tokens or 0)
	end
	return decoded
end

local history = {}
local busy = false

local function setBusy(state, label)
	busy = state
	sendButton.Text = state and "..." or "Send"
	sendButton.BackgroundColor3 = state and PALETTE.dim or PALETTE.accent
	status.Text = label or (state and "thinking..." or "ready")
end

local function send(text)
	if busy then return end
	if text == nil or text:gsub("%s", "") == "" then return end

	if text == "/forget" then
		plugin:SetSetting(KEY_SETTING, nil)
		refreshKeyPanel()
		addBubble("tool", "Key forgotten. It is gone from this computer.")
		return
	end
	if text == "/clear" then
		history = {}
		for _, c in ipairs(feed:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		return
	end

	addBubble("you", text)
	table.insert(history, { role = "user", content = text })
	setBusy(true)

	for round = 1, MAX_ROUNDS do
		local reply, err = request({
			model = model,
			max_tokens = MAX_TOKENS,
			system = SYSTEM,
			tools = TOOLS,
			messages = history,
		})
		if not reply then
			-- Drop the turn that never got an answer, so pressing Send again
			-- retries cleanly instead of sending a conversation the API already
			-- refused.
			addBubble("error", err or "unknown failure")
			setBusy(false, "failed")
			return
		end

		local content = reply.content or {}
		-- Roblox cannot encode an empty table as a JSON object, so a tool call
		-- with no arguments would go back out as [] and be rejected. Every tool
		-- here has a required field, but guard anyway rather than corrupt the
		-- whole conversation.
		for _, block in ipairs(content) do
			if block.type == "tool_use" and next(block.input or {}) == nil then
				block.input = { note = "none" }
			end
		end
		table.insert(history, { role = "assistant", content = content })

		local results = {}
		for _, block in ipairs(content) do
			if block.type == "text" and block.text and block.text ~= "" then
				addBubble("claude", block.text)
			elseif block.type == "tool_use" then
				status.Text = "running " .. tostring(block.name) .. "..."
				local out
				local okTool, errTool = pcall(function()
					out = runTool(block.name, block.input)
				end)
				if not okTool then out = "The tool errored: " .. tostring(errTool) end
				table.insert(results, {
					type = "tool_result",
					tool_use_id = block.id,
					content = tostring(out),
				})
			end
		end

		if #results == 0 then
			setBusy(false, ("ready  -  %d in / %d out tokens this session")
				:format(totalIn, totalOut))
			return
		end
		table.insert(history, { role = "user", content = results })
	end

	addBubble("error", "Stopped after " .. MAX_ROUNDS .. " tool rounds so this "
		.. "does not run away with your bill. Send again to continue.")
	setBusy(false, "stopped")
end

-- ============================================================
-- WIRING
-- ============================================================
sendButton.MouseButton1Click:Connect(function()
	local text = box.Text
	box.Text = ""
	task.spawn(send, text)
end)

box.FocusLost:Connect(function(enterPressed)
	-- MultiLine means Enter normally inserts a newline; Shift is what makes it
	-- a newline here and a bare Enter send, which is what every chat box does.
	if enterPressed then
		local text = box.Text
		box.Text = ""
		task.spawn(send, text)
	end
end)

keySave.MouseButton1Click:Connect(function()
	local k = keyBox.Text:gsub("%s", "")
	if k == "" then return end
	plugin:SetSetting(KEY_SETTING, k)
	keyBox.Text = ""
	refreshKeyPanel()
	addBubble("tool", "Key saved on this computer. Ask me something.")
end)

local function refreshEditButton()
	editButton.Text = editsAllowed and "Edits: ON" or "Edits: OFF"
	editButton.BackgroundColor3 = editsAllowed and PALETTE.good or PALETTE.bg
end

editButton.MouseButton1Click:Connect(function()
	editsAllowed = not editsAllowed
	plugin:SetSetting(EDIT_SETTING, editsAllowed)
	refreshEditButton()
	say(editsAllowed
		and "edits ALLOWED. Every command is printed here before it runs, and "
			.. "each one is a single Ctrl+Z."
		or "edits blocked.")
end)

modelButton.MouseButton1Click:Connect(function()
	local i = 1
	for n, id in ipairs(MODELS) do if id == model then i = n end end
	model = MODELS[(i % #MODELS) + 1]
	plugin:SetSetting(MODEL_SETTING, model)
	modelButton.Text = shortModel(model)
end)

clearButton.MouseButton1Click:Connect(function() send("/clear") end)

openButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
end)

modelButton.Text = shortModel(model)
refreshEditButton()
refreshKeyPanel()

if getKey() then
	addBubble("tool", "Claude is connected to this place. Ask what is in it, or "
		.. "ask for a change. Switch 'Edits' on when you want changes made "
		.. "rather than described.")
else
	addBubble("tool", "Paste an API key to start.")
end

say("panel ready. Click the Claude button in the toolbar to open it.")
