-- Enough of the Roblox API to run this game's server code outside Studio.
--
-- The point is to be able to RUN the thing and look at what came out, rather
-- than assert that it probably works. Only the surface the project actually
-- touches is implemented.
--
-- Two rules learned the hard way:
--   * EnumItems are singletons. Minting a fresh table per lookup makes every
--     identity comparison (`m == Enum.Material.Neon`, `KEEP[mat]`) silently
--     false, and any check built on one measures nothing forever.
--   * Signals must be real and per-instance. A single shared stub whose
--     Connect throws the callback away makes every test that fires an event
--     vacuously green.

-- ============================================================
-- Vector3
-- ============================================================
local V3MT = {}
local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3MT)
end
local Vector3 = { new = v3 }
V3MT.__index = function(t, k)
	if k == "Magnitude" then
		return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
	elseif k == "Unit" then
		local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
		if m == 0 then return v3(0, 0, 0) end
		return v3(t.X / m, t.Y / m, t.Z / m)
	end
	return nil
end
V3MT.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3MT.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3MT.__unm = function(a) return v3(-a.X, -a.Y, -a.Z) end
V3MT.__mul = function(a, b)
	if type(a) == "number" then return v3(b.X * a, b.Y * a, b.Z * a) end
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3MT.__div = function(a, b)
	if type(b) == "number" then return v3(a.X / b, a.Y / b, a.Z / b) end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end

-- ============================================================
-- CFrame
-- ============================================================
local CFMT = {}
local function cf(p) return setmetatable({ p = p or v3(0, 0, 0) }, CFMT) end
local CFrame = {}
function CFrame.new(a, b, c)
	if type(a) == "number" then return cf(v3(a, b, c)) end
	if a == nil then return cf(v3(0, 0, 0)) end
	return cf(v3(a.X, a.Y, a.Z))
end
function CFrame.Angles() return cf(v3(0, 0, 0)) end
function CFrame.fromEulerAnglesXYZ() return cf(v3(0, 0, 0)) end
CFMT.__index = function(t, k)
	if k == "Position" or k == "p" then return rawget(t, "p") end
	if k == "LookVector" then return v3(0, 0, -1) end
	return nil
end
CFMT.__mul = function(a, b)
	if getmetatable(b) == CFMT then return cf(rawget(a, "p") + rawget(b, "p")) end
	if getmetatable(b) == V3MT then return rawget(a, "p") + b end
	return a
end
CFMT.__add = function(a, b) return cf(rawget(a, "p") + b) end
CFMT.__sub = function(a, b) return cf(rawget(a, "p") - b) end

-- ============================================================
-- Color3 / UDim2 / misc value types
-- ============================================================
local C3MT = { __index = function() return nil end }
local function c3(r, g, b) return setmetatable({ R = r, G = g, B = b }, C3MT) end
local Color3 = {}
function Color3.new(r, g, b) return c3(r or 0, g or 0, b or 0) end
function Color3.fromRGB(r, g, b) return c3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end
function Color3.fromHSV(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	local m = i % 6
	if m == 0 then return c3(v, t, p) elseif m == 1 then return c3(q, v, p)
	elseif m == 2 then return c3(p, v, t) elseif m == 3 then return c3(p, q, v)
	elseif m == 4 then return c3(t, p, v) else return c3(v, p, q) end
end

local function simple(name)
	return setmetatable({}, { __index = function() return function() return {} end end,
		__call = function() return {} end, __tostring = function() return name end })
end
local UDim  = { new = function(s, o) return { Scale = s or 0, Offset = o or 0 } end }
local UDim2 = { new = function(sx, ox, sy, oy)
	return { X = { Scale = sx or 0, Offset = ox or 0 },
	         Y = { Scale = sy or 0, Offset = oy or 0 } }
end, fromScale = function(x, y) return UDim2.new(x, 0, y, 0) end,
     fromOffset = function(x, y) return UDim2.new(0, x, 0, y) end }
local Vector2 = { new = function(x, y) return { X = x or 0, Y = y or 0 } end }
local TweenInfo = { new = function(t, style, dir, reps, reverse, delay)
	return { Time = t or 1, EasingStyle = style, EasingDirection = dir,
	         RepeatCount = reps or 0, Reverses = reverse or false,
	         DelayTime = delay or 0 }
end }
local Ray = { new = function(o, d) return { Origin = o, Direction = d } end }
local NumberRange = { new = function(a, b) return { Min = a, Max = b or a } end }
local NumberSequenceKeypoint = { new = function(t, v) return { Time = t, Value = v } end }
local ColorSequenceKeypoint = { new = function(t, v) return { Time = t, Value = v } end }
local NumberSequence = { new = function(...) return { ... } end }
local ColorSequence = { new = function(...) return { ... } end }

-- ============================================================
-- Enum — items are SINGLETONS, which identity comparisons depend on
-- ============================================================
local ENUM_CACHE, ENUM_CATS = {}, {}
local function enumItem(name)
	local e = ENUM_CACHE[name]
	if not e then
		e = setmetatable({ Name = name:match("[^.]+$") or name, Value = 0 },
			{ __tostring = function() return name end })
		ENUM_CACHE[name] = e
	end
	return e
end
local Enum = setmetatable({}, {
	__index = function(_, cat)
		local c = ENUM_CATS[cat]
		if not c then
			c = setmetatable({}, {
				__index = function(_, item) return enumItem(cat .. "." .. item) end })
			ENUM_CATS[cat] = c
		end
		return c
	end,
})

-- ============================================================
-- Random (Luau class; seeded so two runs are comparable)
-- ============================================================
local Random = {}
Random.__index = Random
function Random.new(seed)
	local r = setmetatable({ s = (seed or 0) % 2147483647 }, Random)
	if r.s <= 0 then r.s = r.s + 2147483646 end
	return r
end
function Random:NextNumber(a, b)
	self.s = (self.s * 16807) % 2147483647
	local u = (self.s - 1) / 2147483646
	if a and b then return a + u * (b - a) end
	return u
end
function Random:NextInteger(a, b)
	return math.floor(self:NextNumber() * (b - a + 1)) + a
end

-- ============================================================
-- Instance
-- ============================================================
local InstMT = {}
local Methods = {}
local MODULES = {}

local function newInst(class)
	local t = setmetatable({}, InstMT)
	rawset(t, "_p", { ClassName = class, Name = class, Parent = nil })
	rawset(t, "_c", {})
	rawset(t, "_a", {})
	if class == "RemoteEvent" or class == "UnreliableRemoteEvent" then
		local p = rawget(t, "_p")
		p.FireClient = function() end
		p.FireAllClients = function() end
		p.FireServer = function() end
	elseif class == "RemoteFunction" then
		local p = rawget(t, "_p")
		p.InvokeClient = function() end
		p.InvokeServer = function() end
	end
	return t
end

function Methods.GetChildren(self)
	local out = {}
	for i, c in ipairs(rawget(self, "_c")) do out[i] = c end
	return out
end

function Methods.GetDescendants(self)
	local out = {}
	local function walk(n)
		for _, c in ipairs(rawget(n, "_c")) do
			table.insert(out, c); walk(c)
		end
	end
	walk(self)
	return out
end

function Methods.Destroy(self)
	-- Detach from the PARENT's list too. Clearing only our own children leaves
	-- the instance reachable through GetDescendants, so code that destroys
	-- something and then counts what is left sees no change.
	local parent = rawget(self, "_p").Parent
	if parent then
		local c = rawget(parent, "_c")
		for i, ch in ipairs(c) do
			if ch == self then table.remove(c, i); break end
		end
	end
	rawget(self, "_p").Parent = nil
	rawset(self, "_c", {})
end
Methods.Remove = Methods.Destroy
function Methods.ClearAllChildren(self) rawset(self, "_c", {}) end

function Methods.FindFirstChild(self, name, recursive)
	for _, c in ipairs(rawget(self, "_c")) do
		if rawget(c, "_p").Name == name then return c end
	end
	if recursive then
		for _, c in ipairs(rawget(self, "_c")) do
			local f = Methods.FindFirstChild(c, name, true)
			if f then return f end
		end
	end
	return nil
end
function Methods.WaitForChild(self, name) return Methods.FindFirstChild(self, name, false) end
function Methods.FindFirstChildOfClass(self, cls)
	for _, c in ipairs(rawget(self, "_c")) do
		if rawget(c, "_p").ClassName == cls then return c end
	end
	return nil
end
function Methods.FindFirstChildWhichIsA(self, cls) return Methods.FindFirstChildOfClass(self, cls) end
function Methods.FindFirstAncestor(self, name)
	local n = rawget(self, "_p").Parent
	while n do
		if rawget(n, "_p").Name == name then return n end
		n = rawget(n, "_p").Parent
	end
	return nil
end

function Methods.IsA(self, cls)
	local c = rawget(self, "_p").ClassName
	if c == cls then return true end
	if cls == "BasePart" then
		return c == "Part" or c == "MeshPart" or c == "WedgePart" or c == "SpawnLocation"
	end
	if cls == "GuiObject" then
		return c:find("Frame") ~= nil or c:find("Label") ~= nil or c:find("Button") ~= nil
	end
	-- Scripts answer to LuaSourceContainer, and plenty of real code counts
	-- them that way rather than by ClassName. Without this every such sweep
	-- quietly returns zero, which reads as "the folder is empty" — the exact
	-- wrong answer, delivered confidently.
	if cls == "LuaSourceContainer" then
		return c == "Script" or c == "LocalScript" or c == "ModuleScript"
	end
	if cls == "Instance" then return true end
	return false
end

function Methods.SetAttribute(self, k, v) rawget(self, "_a")[k] = v end
function Methods.GetAttribute(self, k) return rawget(self, "_a")[k] end
function Methods.GetAttributes(self) return rawget(self, "_a") end
function Methods.Clone(self)
	local copy = newInst(rawget(self, "_p").ClassName)
	for k, v in pairs(rawget(self, "_p")) do rawget(copy, "_p")[k] = v end
	for k, v in pairs(rawget(self, "_a")) do rawget(copy, "_a")[k] = v end
	rawget(copy, "_p").Parent = nil
	return copy
end
function Methods.GetFullName(self) return rawget(self, "_p").Name end
function Methods.ScaleTo(self, f) rawget(self, "_p").Scale = f end
function Methods.PivotTo(self, c) rawget(self, "_p").CFrame = c end
function Methods.GetPivot(self) return rawget(self, "_p").CFrame or CFrame.new(0, 0, 0) end
function Methods.SetPrimaryPartCFrame(self, c) rawget(self, "_p").CFrame = c end
function Methods.GetBoundingBox(self) return CFrame.new(0, 0, 0), v3(3, 3, 3) end
function Methods.GetExtentsSize(self) return v3(3, 3, 3) end
function Methods.BreakJoints(self) end
function Methods.MakeJoints(self) end
function Methods.ApplyImpulse(self) end

-- Signals: real, per-instance, and they actually call what you connect.
local SIGNALS = {
	MouseClick = true, MouseHoverEnter = true, MouseHoverLeave = true,
	Touched = true, TouchEnded = true, Changed = true, Triggered = true,
	MouseButton1Click = true, Activated = true, ChildAdded = true,
	DescendantAdded = true, DescendantRemoving = true,
	ChildRemoved = true, AncestryChanged = true, Destroying = true,
	OnServerEvent = true, OnClientEvent = true,
	CharacterAdded = true, CharacterRemoving = true, Died = true,
	PlayerAdded = true, PlayerRemoving = true, Heartbeat = true,
	Stepped = true, RenderStepped = true, Completed = true,
	PromptGamePassPurchaseFinished = true, InputBegan = true, InputEnded = true,
	-- GUI signals. Missing MouseEnter alone was enough to throw the client on
	-- the line that builds its button dock, which in game is a player with no
	-- HUD at all.
	MouseEnter = true, MouseLeave = true, MouseMoved = true,
	MouseButton1Down = true, MouseButton1Up = true, MouseButton2Click = true,
	InputChanged = true, SelectionGained = true, SelectionLost = true,
	FocusLost = true, TouchTap = true, TouchSwipe = true,
	MouseWheelForward = true, MouseWheelBackward = true,
	AttributeChanged = true, GetPropertyChangedSignal = true,
	PromptButtonHoldBegan = true, PromptButtonHoldEnded = true,
	PromptShown = true, PromptHidden = true, ChildrenChanged = true,
	-- Plugin toolbar buttons. Without Click here, every plugin button is a
	-- dead table and the test can never press one.
	Click = true,
}
local function liveSignal()
	local handlers = {}
	local sig
	sig = {
		Connect = function(_, fn)
			table.insert(handlers, fn)
			local i = #handlers
			return { Disconnect = function() handlers[i] = function() end end,
			         Connected = true }
		end,
		Wait = function() end,
		Fire = function(_, ...) for _, fn in ipairs(handlers) do fn(...) end end,
		Count = function() return #handlers end,
	}
	sig.connect = sig.Connect
	sig.Once = sig.Connect
	return sig
end

InstMT.__index = function(t, k)
	local m = Methods[k]
	if m then return m end
	if SIGNALS[k] then
		local sigs = rawget(t, "_sig")
		if not sigs then sigs = {}; rawset(t, "_sig", sigs) end
		if not sigs[k] then sigs[k] = liveSignal() end
		return sigs[k]
	end
	if k == "Position" then
		local cfr = rawget(t, "_p").CFrame
		return cfr and cfr.Position or nil
	end
	local p = rawget(t, "_p")[k]
	if p ~= nil then return p end
	-- Child-by-name access, which is how ReplicatedStorage.Shared.GameConfig
	-- and similar paths are written throughout this project.
	return Methods.FindFirstChild(t, k, false)
end

InstMT.__newindex = function(t, k, val)
	if k == "Parent" then
		local p = rawget(t, "_p")
		if p.Parent then
			local c = rawget(p.Parent, "_c")
			for i, ch in ipairs(c) do
				if ch == t then table.remove(c, i); break end
			end
		end
		p.Parent = val
		if val then
			table.insert(rawget(val, "_c"), t)
			-- ChildAdded on the parent, DescendantAdded all the way up.
			--
			-- Without these, any code that reacts to something appearing —
			-- styling every button as it is created, wiring a part as it is
			-- added — looks like it works and does nothing, and the check that
			-- covers it passes for the wrong reason.
			local sigs = rawget(val, "_sig")
			if sigs and sigs.ChildAdded then sigs.ChildAdded:Fire(t) end
			local up = val
			while up do
				local s = rawget(up, "_sig")
				if s and s.DescendantAdded then s.DescendantAdded:Fire(t) end
				up = rawget(up, "_p").Parent
			end
		end
		return
	end
	if k == "Position" then
		rawget(t, "_p").CFrame = CFrame.new(val)
		rawget(t, "_p").Position = val
		return
	end
	rawget(t, "_p")[k] = val
end

local Instance = {
	new = function(class, parent)
		local i = newInst(class)
		if parent then i.Parent = parent end
		return i
	end,
}

-- ============================================================
-- Services
-- ============================================================
local Workspace = newInst("Workspace"); Workspace.Name = "Workspace"
local Terrain = newInst("Terrain"); Terrain.Name = "Terrain"; Terrain.Parent = Workspace
rawget(Terrain, "_p").Clear = function() end
rawget(Terrain, "_p").SetMaterialColor = function() end
rawget(Terrain, "_p").FillBlock = function() end

local ReplicatedStorage = newInst("ReplicatedStorage"); ReplicatedStorage.Name = "ReplicatedStorage"
local ServerStorage = newInst("ServerStorage"); ServerStorage.Name = "ServerStorage"
local ServerScriptService = newInst("ServerScriptService"); ServerScriptService.Name = "ServerScriptService"
local Lighting = newInst("Lighting"); Lighting.Name = "Lighting"
local StarterGui = newInst("StarterGui"); StarterGui.Name = "StarterGui"
rawget(StarterGui, "_p").SetCore = function() end
rawget(StarterGui, "_p").SetCoreGuiEnabled = function() end

local RunService = newInst("RunService"); RunService.Name = "RunService"
do
	local p = rawget(RunService, "_p")
	p.IsStudio  = function() return RunService.__studio == true end
	p.IsClient  = function() return false end
	p.IsServer  = function() return true end
	p.IsRunning = function() return true end
	p.IsEdit    = function() return false end
end

local PlayerList = {}
local function signal()
	local handlers = {}
	return {
		Connect = function(_, fn) table.insert(handlers, fn)
			return { Disconnect = function() end, Connected = true } end,
		Fire = function(_, ...) for _, fn in ipairs(handlers) do fn(...) end end,
	}
end
local Players = {
	Name = "Players",
	GetPlayers = function() return PlayerList end,
	GetPlayerByUserId = function(_, id)
		for _, p in ipairs(PlayerList) do if p.UserId == id then return p end end
		return nil
	end,
	GetPlayerFromCharacter = function() return nil end,
	GetNameFromUserIdAsync = function(_, id) return "User" .. tostring(id) end,
	GetUserThumbnailAsync = function() return "", true end,
	PlayerAdded = signal(),
	PlayerRemoving = signal(),
	CharacterAutoLoads = true,
}

local CollectionService = {
	GetTagged = function() return {} end,
	AddTag = function() end,
	RemoveTag = function() end,
	HasTag = function() return false end,
	GetInstanceAddedSignal = function() return signal() end,
	GetInstanceRemovedSignal = function() return signal() end,
}

local HttpService = {
	JSONEncode = function(_, t) return tostring(t) end,
	JSONDecode = function() return {} end,
	GenerateGUID = function()
		local n = 0
		return function(_, braces)
			n = n + 1
			return string.format("%s%08x-mock-%04d%s",
				braces == false and "" or "{", n * 2654435761 % 0xFFFFFFFF, n,
				braces == false and "" or "}")
		end
	end,
}
HttpService.GenerateGUID = HttpService.GenerateGUID()

local STORE = {}
local function makeStore(name)
	STORE[name] = STORE[name] or {}
	local data = STORE[name]
	return {
		GetAsync = function(_, k) return data[k] end,
		SetAsync = function(_, k, v) data[k] = v end,
		UpdateAsync = function(_, k, fn) local nv = fn(data[k]); data[k] = nv; return nv end,
		RemoveAsync = function(_, k) local v = data[k]; data[k] = nil; return v end,
		IncrementAsync = function(_, k, d) data[k] = (data[k] or 0) + (d or 1); return data[k] end,
		SetAsync_Ordered = function() end,
		GetSortedAsync = function()
			return { GetCurrentPage = function() return {} end, IsFinished = true,
			         AdvanceToNextPageAsync = function() end }
		end,
	}
end
local DataStoreService = {
	GetDataStore = function(_, n) return makeStore(n) end,
	GetOrderedDataStore = function(_, n) return makeStore("ord:" .. n) end,
}

local MarketplaceService = {
	UserOwnsGamePassAsync = function() return false end,
	GetProductInfo = function() return { Name = "Item", PriceInRobux = 0 } end,
	PromptGamePassPurchase = function() end,
	PromptProductPurchase = function() end,
	PromptGamePassPurchaseFinished = signal(),
	ProcessReceipt = nil,
}

local TweenService = {
	Create = function()
		return { Play = function() end, Cancel = function() end, Completed = signal() }
	end,
}
local BadgeService = {
	AwardBadge = function() end,
	UserHasBadgeAsync = function() return false end,
}
local MessagingService = {
	PublishAsync = function() end,
	SubscribeAsync = function() return { Disconnect = function() end } end,
}
-- Studio-only. A plugin that changes the place wraps each change in a recording
-- so one change is one Ctrl+Z; if this is missing the wrapper silently degrades
-- to no undo at all, which is exactly the thing worth testing.
local ChangeHistoryService = {
	Recordings = {},
	TryBeginRecording = function(self, name)
		local id = "rec" .. tostring(#self.Recordings + 1)
		table.insert(self.Recordings, { id = id, name = name, state = "open" })
		return id
	end,
	FinishRecording = function(self, id, op)
		for _, r in ipairs(self.Recordings) do
			if r.id == id then r.state = tostring(op) end
		end
	end,
	SetWaypoint = function() end,
}

local Debris = { AddItem = function() end }
local SoundService = { PlayLocalSound = function() end }
local PhysicsService = {
	RegisterCollisionGroup = function() end,
	CollisionGroupSetCollidable = function() end,
}

local SERVICES = {
	Workspace = Workspace,
	ReplicatedStorage = ReplicatedStorage,
	ServerStorage = ServerStorage,
	ServerScriptService = ServerScriptService,
	Lighting = Lighting,
	StarterGui = StarterGui,
	RunService = RunService,
	Players = Players,
	CollectionService = CollectionService,
	HttpService = HttpService,
	DataStoreService = DataStoreService,
	MarketplaceService = MarketplaceService,
	TweenService = TweenService,
	BadgeService = BadgeService,
	MessagingService = MessagingService,
	Debris = Debris,
	SoundService = SoundService,
	PhysicsService = PhysicsService,
	ChangeHistoryService = ChangeHistoryService,
}

local BOUND_TO_CLOSE = {}
local game = {
	Workspace = Workspace,
	ReplicatedStorage = ReplicatedStorage,
	ServerScriptService = ServerScriptService,
	Lighting = Lighting,
	Players = Players,
	GetService = function(_, name)
		local svc = SERVICES[name]
		if not svc then
			svc = newInst(name); svc.Name = name; SERVICES[name] = svc
		end
		return svc
	end,
	BindToClose = function(_, fn) BOUND_TO_CLOSE[#BOUND_TO_CLOSE + 1] = fn end,
	Name = "MockPlace", JobId = "", CreatorId = 0, PlaceId = 0,
	GetFullName = function() return "game" end,
}

local function robloxRequire(target)
	local m = MODULES[target]
	if m ~= nil then return m end
	-- A ModuleScript created at runtime carries its code in .Source and has
	-- never been registered here. Roblox can require it; so can this. Without
	-- it, any code path that builds a module on the fly — which is how a plugin
	-- runs a command — looks broken when it is not.
	if type(target) == "table" then
		local p = rawget(target, "_p")
		if p and p.ClassName == "ModuleScript" and type(p.Source) == "string" then
			local chunk = load(p.Source, "@" .. tostring(p.Name))
			if chunk then
				local v = chunk()
				MODULES[target] = v
				return v
			end
		end
	end
	error("mock require: unknown module " ..
		tostring(target and target.Name or target))
end

-- ============================================================
-- Studio-only globals a plugin reaches for
-- ============================================================
local DockWidgetPluginGuiInfo = {
	new = function(dockState, enabled, override, w, h, minW, minH)
		return { InitialDockState = dockState, InitialEnabled = enabled,
		         InitialEnabledShouldOverrideRestore = override,
		         FloatingXSize = w, FloatingYSize = h,
		         MinWidth = minW, MinHeight = minH }
	end,
}

local StudioTheme = {
	Name = "Dark",
	GetColor = function(_, _guide, _modifier) return c3(0.2, 0.2, 0.2) end,
}
local function settingsFn()
	return { Studio = { Theme = StudioTheme } }
end

return {
	Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Enum = Enum,
	DockWidgetPluginGuiInfo = DockWidgetPluginGuiInfo, settings = settingsFn,
	ChangeHistoryService = ChangeHistoryService,
	Instance = Instance, game = game, workspace = Workspace, Workspace = Workspace,
	Random = Random, UDim = UDim, UDim2 = UDim2, Vector2 = Vector2,
	NumberRange = NumberRange, NumberSequence = NumberSequence,
	TweenInfo = TweenInfo, Ray = Ray,
	ColorSequence = ColorSequence,
	NumberSequenceKeypoint = NumberSequenceKeypoint,
	ColorSequenceKeypoint = ColorSequenceKeypoint,
	ReplicatedStorage = ReplicatedStorage, ServerScriptService = ServerScriptService,
	ServerStorage = ServerStorage, Lighting = Lighting, Players = Players,
	PlayerList = PlayerList, RunService = RunService,
	MODULES = MODULES, newInst = newInst, robloxRequire = robloxRequire,
	BOUND_TO_CLOSE = BOUND_TO_CLOSE, STORE = STORE,
}
