-- MysticPets: GameServer.server.lua
local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Lighting     = game:GetService("Lighting")
local RunService   = game:GetService("RunService")
local HttpService  = game:GetService("HttpService")

local DataManager     = require(script.Parent.DataManager)
local PetService      = require(script.Parent.PetService)
local EggService      = require(script.Parent.EggService)
local CurrencyService = require(script.Parent.CurrencyService)
local RebirthService  = require(script.Parent.RebirthService)
local GamepassService = require(script.Parent.GamepassService)
local BadgeService         = require(script.Parent.BadgeService)
local UpgradeService       = require(script.Parent.UpgradeService)
local LeaderboardService   = require(script.Parent.LeaderboardService)
local QuestService         = require(script.Parent.QuestService)
local MerchantService      = require(script.Parent.MerchantService)
local EventService         = require(script.Parent.EventService)
local TradeService         = require(script.Parent.TradeService)
local CodeService          = require(script.Parent.CodeService)
local DailyService         = require(script.Parent.DailyService)
local BoostService         = require(script.Parent.BoostService)
local FusionService        = require(script.Parent.FusionService)
local PlaytimeService      = require(script.Parent.PlaytimeService)
local SpinService          = require(script.Parent.SpinService)
local MapPersist           = require(script.Parent.MapPersist)
local RateLimit            = require(script.Parent.RateLimit)
local MapProps             = require(script.Parent.MapProps)
local GameConfig           = require(game.ReplicatedStorage.Shared.GameConfig)

-- ============================================================
-- REMOTES
-- ============================================================
local Remotes = Instance.new("Folder")
Remotes.Name  = "Remotes"
Remotes.Parent = game.ReplicatedStorage

-- EVERY REMOTE IS RATE LIMITED, WITHOUT TOUCHING THIRTY HANDLERS.
--
-- There are thirty OnServerEvent / OnServerInvoke handlers in this file and
-- not one of them had a limit. Each one validates what it is asked to do, so
-- an exploiter cannot hatch an egg they cannot afford — but validation does
-- not cost nothing. Firing a remote thousands of times a second still burns
-- the server's frame budget, still hammers DataStores, and still gives a race
-- every chance it needs to land.
--
-- Adding a check to thirty call sites means remembering it thirty times, and
-- again for the thirty-first. So the guard goes where the remotes are MADE:
-- these hand back a proxy that wraps whatever callback you attach. Anything
-- else on the object passes straight through to the real instance, and the
-- real instance is what gets parented, so the client sees nothing different.
local function guardEvent(e, name)
	return setmetatable({}, {
		__index = function(_, k)
			if k == "OnServerEvent" then
				return {
					Connect = function(_, fn)
						return e.OnServerEvent:Connect(function(player, ...)
							if not RateLimit.Allow(player, name) then return end
							fn(player, ...)
						end)
					end,
				}
			end
			local v = e[k]
			if type(v) == "function" then
				-- Called as remote:FireClient(...), so swallow the proxy that
				-- arrives as self and pass the real instance instead.
				return function(_, ...) return v(e, ...) end
			end
			return v
		end,
		__newindex = function(_, k, v) e[k] = v end,
	})
end

local function guardFunction(f, name)
	return setmetatable({}, {
		__index = function(_, k)
			local v = f[k]
			if type(v) == "function" then
				return function(_, ...) return v(f, ...) end
			end
			return v
		end,
		__newindex = function(_, k, fn)
			-- OnServerInvoke is ASSIGNED rather than connected, so the guard
			-- has to live in __newindex. Missing that would leave every
			-- RemoteFunction — including the one that hands out player data —
			-- completely unlimited while the events looked covered.
			if k == "OnServerInvoke" and type(fn) == "function" then
				f.OnServerInvoke = function(player, ...)
					if not RateLimit.Allow(player, name) then return nil end
					return fn(player, ...)
				end
				return
			end
			f[k] = fn
		end,
	})
end

local function makeEvent(name)
	local e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = Remotes
	return guardEvent(e, name)
end
local function makeFunction(name)
	local f = Instance.new("RemoteFunction"); f.Name = name; f.Parent = Remotes
	return guardFunction(f, name)
end

local RE_DataUpdated     = makeEvent("DataUpdated")
local RE_HatchResult     = makeEvent("HatchResult")
local RE_Notification    = makeEvent("Notification")
local RE_BadgeEarned     = makeEvent("BadgeEarned")
local RE_RebirthConfirm  = makeEvent("RebirthConfirm")
local RE_BuyUpgrade      = makeEvent("BuyUpgrade")
local RE_SecretFound     = makeEvent("SecretFound")
local RE_TitleUpdate     = makeEvent("TitleUpdate")
local RF_GetLeaderboard  = makeFunction("GetLeaderboard")
local RE_HatchEgg     = makeEvent("HatchEgg")
local RE_EquipPet     = makeEvent("EquipPet")
local RE_UnequipPet   = makeEvent("UnequipPet")
local RE_BuyArea      = makeEvent("BuyArea")
local RE_Rebirth      = makeEvent("Rebirth")
local RE_DeletePet    = makeEvent("DeletePet")
local RE_BuyGamepass  = makeEvent("BuyGamepass")
local RF_GetData      = makeFunction("GetData")
local RF_Admin        = makeFunction("AdminCmd")
local RF_GetQuests    = makeFunction("GetQuests")
local RE_ClaimQuest   = makeEvent("ClaimQuest")
local RF_GetMerchant  = makeFunction("GetMerchant")
local RE_BuyMerchant  = makeEvent("BuyMerchant")
local RF_GetEvent     = makeFunction("GetEvent")
local RE_BuyEvent     = makeEvent("BuyEvent")
local RE_RedeemCode   = makeEvent("RedeemCode")
local RE_PetCmd       = makeEvent("PetCmd")
local RF_GetDaily     = makeFunction("GetDaily")
local RE_ClaimDaily   = makeEvent("ClaimDaily")
local RE_SetMuted     = makeEvent("SetMuted")
local RF_GetBoosts    = makeFunction("GetBoosts")
local RE_BuyBoost     = makeEvent("BuyBoost")
local RF_GetFusion    = makeFunction("GetFusion")
local RE_Fuse         = makeEvent("Fuse")
local RF_GetPlaytime  = makeFunction("GetPlaytime")
local RE_ClaimPlaytime= makeEvent("ClaimPlaytime")
local RE_OfflineEarnings = makeEvent("OfflineEarnings")
local RF_GetSpin      = makeFunction("GetSpin")
local RF_Spin         = makeFunction("Spin")
local RE_Trade        = makeEvent("Trade")        -- client -> server commands
local RE_TradeState   = makeEvent("TradeState")   -- server -> client live state
local RE_TradeReq     = makeEvent("TradeReq")     -- server -> client incoming request

-- ============================================================
-- LIGHTING & ATMOSPHERE
-- ============================================================
local function setupLighting()
	-- Warm natural daylight — the old bluish ambient tinted the grass purple
	Lighting.Ambient        = Color3.fromRGB(120, 118, 110)
	Lighting.OutdoorAmbient = Color3.fromRGB(165, 162, 150)
	Lighting.Brightness     = 2.2
	Lighting.ClockTime      = 14
	Lighting.ShadowSoftness = 0.4
	Lighting.GlobalShadows  = true
	-- Best-quality lighting engine — biggest free visual upgrade for the look
	pcall(function() Lighting.Technology = Enum.Technology.ShadowMap end)  -- good quality, far lighter than Future (fixes lag)
	Lighting.ExposureCompensation = 0.15
	pcall(function()
		Lighting.EnvironmentDiffuseScale  = 0.65
		Lighting.EnvironmentSpecularScale = 0.5
	end)
	if not Lighting:FindFirstChildOfClass("Sky") then
		local sky = Instance.new("Sky")
		sky.SunAngularSize = 11; sky.StarCount = 4000
		sky.Parent = Lighting
	end

	-- Clean grass green (terrain grass base was rendering dull/tinted)
	-- Turn OFF the tall overgrown grass blades FIRST, on its own, so it always
	-- runs even if SetMaterialColor errors (that's why it didn't take before).
	pcall(function() workspace.Terrain.Decoration = false end)
	pcall(function()
		workspace.Terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(95, 160, 70))
		workspace.Terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(90, 155, 65))
	end)

	local atmo = Instance.new("Atmosphere")
	atmo.Density  = 0.3; atmo.Offset = 0.1
	atmo.Color    = Color3.fromRGB(220, 225, 230)
	atmo.Decay    = Color3.fromRGB(150, 170, 200)
	atmo.Glare    = 0.0; atmo.Haze = 1.4
	atmo.Parent   = Lighting

	-- Minimal bloom so nothing looks "glowy"
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.04; bloom.Size = 24; bloom.Threshold = 1.6
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Brightness = 0.0; cc.Contrast = 0.05; cc.Saturation = 0.15
	cc.TintColor  = Color3.fromRGB(255, 250, 240)  -- warm white, not blue
	cc.Parent     = Lighting

	local sun = Instance.new("SunRaysEffect")
	sun.Intensity = 0.03; sun.Spread = 0.3; sun.Parent = Lighting
end

-- ============================================================
-- MAP HELPERS
-- ============================================================
-- Everything the builder makes lands in the StarPetsMap folder rather than
-- loose in Workspace. That is what lets a person select the map in the Explorer
-- and copy it in one go — and it is what lets an old generated map be replaced
-- without touching anything else somebody has put in their Workspace.
--
-- The StarPetsBuilt stamp identifies our own work positively, so cleanup never
-- has to GUESS from a part's name whether it is ours. Guessing is how a purge
-- ends up deleting a part somebody called "Wall".
local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true; p.CastShadow = false
	for k,v in pairs(props) do p[k] = v end
	p:SetAttribute("StarPetsBuilt", true)
	if p.Parent == nil then p.Parent = MapPersist.Container() end
	return p
end

local function glow(p, color, brightness)
	-- Subtle by default — too many bright PointLights washed the map out
	local l = Instance.new("PointLight")
	l.Color = color; l.Brightness = (brightness or 2) * 0.15; l.Range = 7; l.Parent = p
end

local function particles(p, color, rate)
	local att = Instance.new("Attachment"); att.Parent = p
	local pe = Instance.new("ParticleEmitter")
	pe.Parent        = att
	pe.Color         = ColorSequence.new({ColorSequenceKeypoint.new(0,color),ColorSequenceKeypoint.new(1,Color3.new(1,1,1))})
	pe.LightEmission = 0.8; pe.LightInfluence = 0.2
	pe.Size          = NumberSequence.new({NumberSequenceKeypoint.new(0,0.25),NumberSequenceKeypoint.new(1,0)})
	pe.Transparency  = NumberSequence.new({NumberSequenceKeypoint.new(0,0.2),NumberSequenceKeypoint.new(1,1)})
	pe.Speed         = NumberRange.new(1,3); pe.Lifetime = NumberRange.new(1,2)
	pe.Rate          = rate or 12; pe.SpreadAngle = Vector2.new(180,180)
	pe.RotSpeed      = NumberRange.new(-60,60); pe.Rotation = NumberRange.new(0,360)
end

local function billboard(adornee, line1, col1, line2, col2, size, maxDist)
	size = size or UDim2.new(0,180,0,70)
	local bb = Instance.new("BillboardGui")
	bb.Size = size; bb.StudsOffset = Vector3.new(0,4,0)
	bb.MaxDistance = maxDist or 55  -- only show the sign when the player is near
	bb.Adornee = adornee; bb.AlwaysOnTop = false; bb.Parent = adornee
	local t1 = Instance.new("TextLabel"); t1.Size = UDim2.new(1,0,0.55,0)
	t1.BackgroundTransparency=1; t1.Text=line1; t1.TextColor3=col1
	t1.TextScaled=true; t1.Font=Enum.Font.GothamBold
	t1.TextStrokeTransparency=0.4; t1.TextStrokeColor3=Color3.new(0,0,0); t1.Parent=bb
	if line2 then
		local t2 = Instance.new("TextLabel"); t2.Size=UDim2.new(1,0,0.45,0)
		t2.Position=UDim2.new(0,0,0.55,0); t2.BackgroundTransparency=1
		t2.Text=line2; t2.TextColor3=col2 or Color3.fromRGB(255,215,0)
		t2.TextScaled=true; t2.Font=Enum.Font.Gotham
		t2.TextStrokeTransparency=0.4; t2.TextStrokeColor3=Color3.new(0,0,0); t2.Parent=bb
	end
end

-- ============================================================
-- MAP BUILD  (sized for 20 players)
-- Layout (X axis = progression east):
--   Spawn x=0      Egg area z=-90
--   Meadow   orbs x=-50..50,  z=20..110
--   Forest   x=80..210,  z=-95..95
--   Desert   x=210..340, z=-95..95
--   Volcano  x=340..470, z=-95..95
--   Space    x=470..590, z=-95..95
--   Rebirth machine at x=-60 (left of spawn)
--   Boundary walls around x=-90..610, z=-110..130
-- ============================================================
-- ============================================================
-- WORLD DECORATION HELPERS (fill biomes so they aren't empty)
-- ============================================================
local function tree(x, z, baseY, trunkColor, leafColor, scale)
	scale = scale or 1
	local h = 9 * scale
	part({Name="TreeTrunk",Size=Vector3.new(1.5*scale,h,1.5*scale),
		Position=Vector3.new(x, baseY + h/2, z),Color=trunkColor,
		Material=Enum.Material.Wood,CanCollide=false})
	part({Name="TreeLeaf",Shape=Enum.PartType.Ball,Size=Vector3.new(8*scale,8*scale,8*scale),
		Position=Vector3.new(x, baseY + h + scale, z),Color=leafColor,
		Material=Enum.Material.Grass,CanCollide=false})
end

local function rock(x, z, baseY, color, scale)
	scale = scale or 1
	local s = (3 + math.random()*2.5) * scale
	local r = part({Name="Rock",Size=Vector3.new(s,s*0.7,s),
		Position=Vector3.new(x, baseY + s*0.35, z),Color=color,
		Material=Enum.Material.Slate,CanCollide=false})
	r.CFrame = r.CFrame * CFrame.Angles(math.rad(math.random(-12,12)),
		math.rad(math.random(0,360)),math.rad(math.random(-12,12)))
end

local FLOWER_COLORS = {
	Color3.fromRGB(255,120,150), Color3.fromRGB(255,220,90),
	Color3.fromRGB(180,130,255), Color3.fromRGB(255,160,80), Color3.fromRGB(120,200,255),
}
local function flower(x, z, baseY)
	local c = FLOWER_COLORS[math.random(#FLOWER_COLORS)]
	part({Name="FStem",Size=Vector3.new(0.12,0.9,0.12),Position=Vector3.new(x,baseY+0.45,z),
		Color=Color3.fromRGB(70,150,70),Material=Enum.Material.Grass,CanCollide=false})
	part({Name="FTop",Shape=Enum.PartType.Ball,Size=Vector3.new(0.55,0.45,0.55),
		Position=Vector3.new(x,baseY+0.95,z),Color=c,Material=Enum.Material.SmoothPlastic,CanCollide=false})
	part({Name="FCenter",Shape=Enum.PartType.Ball,Size=Vector3.new(0.22,0.22,0.22),
		Position=Vector3.new(x,baseY+1.05,z),Color=Color3.fromRGB(255,235,140),Material=Enum.Material.SmoothPlastic,CanCollide=false})
end

-- WHAT EACH WORLD IS MADE OF NOW LIVES IN MapProps.
--
-- This used to be a chain of if/elseif with the prop shapes written inline: one
-- kind of tree for Forest, a green BOX called Cactus for Desert, rocks and flat
-- discs for Volcano, and for Space a handful of neon balls placed between five
-- and twenty-six studs IN THE AIR — so the ground a player actually walks on
-- had nothing on it at all.
--
-- Every prop was also placed by uniform math.random across the whole slab,
-- which reads as noise however many you use. MapProps places clumps instead,
-- with a minimum spacing per world so features several parts wide do not land
-- inside one another.
local PROP_SET = {
	Meadow  = "meadow",
	Forest  = "forest",
	Desert  = "desert",
	Volcano = "volcano",
	Space   = "space",
}

local function decorateBiome(id, cx, baseY, opts)
	local set = PROP_SET[id]
	if not set then return 0 end
	local halfW = (opts and opts.halfW) or 60
	local halfD = (opts and opts.halfD) or 90
	local seed = 7000 + #id * 131 + string.byte(id, 1) * 17
	local n, placed = MapProps.Populate(
		{ part = part },
		set, cx, 0, halfW, halfD, baseY,
		{
			-- Seeded from the world id so a world looks the same on every
			-- server, and two worlds never get the same layout.
			seed = seed,
			clusters = (opts and opts.clusters) or 14,
			blocked = opts and opts.blocked or nil,
		})
	-- Then the small stuff, in the gaps the features leave. Same seed family,
	-- so this is identical on every server too.
	if MapProps.SCATTER[set] then
		n = n + MapProps.Scatter({ part = part }, set, cx, 0, halfW, halfD, baseY, {
			seed = seed + 911,
			count = (opts and opts.scatter) or 44,
			blocked = opts and opts.blocked or nil,
			avoid = placed,
		})
	end
	return n
end


local function comma(n)
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function buildMap()
	-- ---- GROUND: flat static green floor (no terrain grass blades) ----
	pcall(function() workspace.Terrain:Clear() end)  -- remove any terrain grass
	part({Name="GroundFloor",Size=Vector3.new(820,2,300),Position=Vector3.new(260,-1.6,5),  -- well below other floors (no z-fight flicker)
		Color=Color3.fromRGB(96,168,76),Material=Enum.Material.Grass})

	-- ---- SPAWN PLATFORM (60x60, fits 20 players) ----
	part({Name="SpawnPlat",Size=Vector3.new(60,2,60),Position=Vector3.new(0,-1,0),
		Color=Color3.fromRGB(188,182,170),Material=Enum.Material.Cobblestone})
	part({Name="SpawnRing",Size=Vector3.new(62,0.25,62),Position=Vector3.new(0,0.12,0),
		Color=Color3.fromRGB(205,180,120),Material=Enum.Material.SmoothPlastic,CanCollide=false})

	-- SpawnLocation — invisible
	local sp = Instance.new("SpawnLocation")
	sp.Size=Vector3.new(6,0.2,6); sp.Position=Vector3.new(0,0,0)
	-- Inside the map folder, not loose in Workspace, so copying the map takes
	-- the spawn point with it.
	sp.Name="StarPetsSpawn"
	sp.Transparency=1; sp.Anchored=true; sp.Parent=MapPersist.Container()

	-- Subtle decorative crystals around spawn (no glow — were glowing purple)
	for i=1,10 do
		local ang=(i/10)*math.pi*2; local r=30
		local h=math.random(3,6)
		part({Name="Crystal"..i,Size=Vector3.new(1.0,h,1.0),
			Position=Vector3.new(math.cos(ang)*r,h/2-1,math.sin(ang)*r),
			Color=Color3.fromRGB(120,195,160),Material=Enum.Material.Glass,CanCollide=false})
	end

	-- ---- EGG AREA (behind spawn, 130 wide x 60 deep) ----
	part({Name="EggPlat",Size=Vector3.new(130,2,60),Position=Vector3.new(0,-1,-90),
		Color=Color3.fromRGB(182,176,164),Material=Enum.Material.Cobblestone})
	-- Connecting strip between spawn and egg area
	part({Name="EggConnector",Size=Vector3.new(60,2,60),Position=Vector3.new(0,-1,-60),
		Color=Color3.fromRGB(182,176,164),Material=Enum.Material.Cobblestone})

	local eggSign=part({Name="EggSignA",Size=Vector3.new(1,1,1),Position=Vector3.new(0,9,-100),
		Transparency=1,CanCollide=false})
	billboard(eggSign,"🥚  HATCH EGGS",Color3.fromRGB(255,220,100),"Click an egg to start!",
		Color3.fromRGB(200,200,200),UDim2.new(0,240,0,60))

	-- Egg stands. One builder for all of them, so a world egg out in the
	-- Volcano is the same object as the four at spawn: same click, same
	-- MapPersist stamp, same sign.
	local function eggStand(eggCfg, pos)
		local x, y0, z = pos.X, pos.Y, pos.Z
		part({Name="EggBase_"..eggCfg.id,Size=Vector3.new(7,0.5,7),
			Position=Vector3.new(x,y0-0.75,z),Color=Color3.fromRGB(32,28,52),Material=Enum.Material.SmoothPlastic})
		part({Name="EggRing_"..eggCfg.id,Size=Vector3.new(7.4,0.3,7.4),
			Position=Vector3.new(x,y0-0.3,z),Color=eggCfg.color,Material=Enum.Material.SmoothPlastic,CanCollide=false})
		part({Name="EggCol_"..eggCfg.id,Size=Vector3.new(2.8,2.2,2.8),
			Position=Vector3.new(x,y0+0.6,z),Color=Color3.fromRGB(120,110,135),Material=Enum.Material.Slate})

		-- Actual egg: smooth tapered oval (no glow), with spots welded so they bob with it
		local eggPos = Vector3.new(x,y0+3.8,z)
		local egg=part({Name="Egg_"..eggCfg.id,Shape=Enum.PartType.Ball,
			Size=Vector3.new(3,4.2,3),Position=eggPos,
			Color=eggCfg.color,Material=Enum.Material.SmoothPlastic,CanCollide=false})
		for _,off in ipairs({Vector3.new(0.55,0.5,0.95),Vector3.new(-0.7,-0.2,0.85),Vector3.new(0.15,1.3,0.7)}) do
			local spot=part({Name="EggSpot",Shape=Enum.PartType.Ball,Size=Vector3.new(0.95,0.95,0.5),
				Position=eggPos+off,Color=Color3.fromRGB(255,255,255),Material=Enum.Material.SmoothPlastic,CanCollide=false})
			spot.Anchored=false; spot.CanQuery=false  -- don't block clicks on the egg
			local w=Instance.new("WeldConstraint"); w.Part0=egg; w.Part1=spot; w.Parent=egg
		end

		local costText = eggCfg.id=="StarterEgg"
			and ("🆓 FREE → then 💰 "..(eggCfg.costAfterFirst or 150))
			or ((eggCfg.currency=="Gems" and "💎 " or "💰 ")..comma(eggCfg.cost).." "..eggCfg.currency)
		billboard(egg,eggCfg.name,Color3.new(1,1,1),costText,Color3.fromRGB(255,215,0),UDim2.new(0,180,0,72))

		-- No motion here. The bob and spin are done by each client
		-- (WorldMotion.client.lua): a server loop replicated every frame of it to
		-- every player, and never ran at all on a baked map.
		local cd=Instance.new("ClickDetector"); cd.MaxActivationDistance=32; cd.Parent=egg
		-- Stamped rather than closed over, so this egg still hatches when the map
		-- has been baked into the place and this line never ran. See MapPersist.
		MapPersist.Bind(cd, "HatchEgg", eggCfg.id)
		return egg
	end

	-- The four at spawn (spread 26 studs apart).
	local eggDefs={{id="StarterEgg"},{id="CoolEgg"},{id="RareEgg"},{id="LegendaryEgg"}}
	for i,eDef in ipairs(eggDefs) do
		for _,e in ipairs(GameConfig.Eggs) do
			if e.id==eDef.id then
				eggStand(e, Vector3.new(-39+(i-1)*26, 0, -90))
				break
			end
		end
	end

	-- ---- EGG PLAZA DRESSING ----
	-- The plaza was a 130x60 slab of bare cobble with four stands on it — the
	-- first place every new player is sent, and the emptiest place on the map,
	-- right next to a hub full of hedges, benches and flowers. Same vocabulary
	-- here, so the two read as one place.
	--
	-- Three things are kept clear: each stand (they are what you click), the
	-- south path where it arrives at x=0, and the line of sight to the eggs.
	-- Everything low or behind the egg row, and nothing here can be clicked
	-- (CanQuery off), so no flower ever eats a click meant for an egg.
	local PLAZA_Y = 0
	local function deco(props)
		props.CanQuery = false
		return part(props)
	end

	-- A stone kerb along the back edge: gives the slab an edge to stop at.
	deco({Name="PlazaKerb",Size=Vector3.new(128,0.8,1.6),Position=Vector3.new(0,PLAZA_Y+0.1,-119),
		Color=Color3.fromRGB(150,144,134),Material=Enum.Material.Slate})

	-- Planters behind the egg row, one behind each gap and one at each end.
	local BLOOM = { Color3.fromRGB(240,120,150), Color3.fromRGB(250,210,90),
	                Color3.fromRGB(150,130,240), Color3.fromRGB(255,255,255) }
	for i, x in ipairs({-52, -26, 0, 26, 52}) do
		local z = -109
		deco({Name="Planter",Size=Vector3.new(9,1.4,3.4),Position=Vector3.new(x,PLAZA_Y+0.2,z),
			Color=Color3.fromRGB(122,84,54),Material=Enum.Material.Wood})
		deco({Name="PlanterSoil",Size=Vector3.new(8.2,0.3,2.6),Position=Vector3.new(x,PLAZA_Y+0.95,z),
			Color=Color3.fromRGB(70,50,36),Material=Enum.Material.Ground})
		for k = 0, 4 do
			local bx = x - 3.2 + k * 1.6
			local bz = z + ((k % 2 == 0) and -0.5 or 0.5)
			deco({Name="PlanterStem",Size=Vector3.new(0.18,1.1,0.18),
				Position=Vector3.new(bx,PLAZA_Y+1.6,bz),Color=Color3.fromRGB(70,130,60),
				Material=Enum.Material.SmoothPlastic,CanCollide=false})
			deco({Name="PlanterBloom",Shape=Enum.PartType.Ball,Size=Vector3.new(0.9,0.9,0.9),
				Position=Vector3.new(bx,PLAZA_Y+2.25,bz),Color=BLOOM[((i + k) % #BLOOM) + 1],
				Material=Enum.Material.SmoothPlastic,CanCollide=false})
		end
	end

	-- Clipped shrubs at the four corners.
	for _, c in ipairs({ {-60,-114}, {60,-114}, {-60,-66}, {60,-66} }) do
		deco({Name="PlazaShrub",Shape=Enum.PartType.Ball,Size=Vector3.new(6,5,6),
			Position=Vector3.new(c[1],PLAZA_Y+2.2,c[2]),Color=Color3.fromRGB(52,118,54),
			Material=Enum.Material.Grass,CanCollide=false})
	end

	-- Benches on each side, facing in, so the plaza has somewhere to stand
	-- and watch a hatch.
	for _, side in ipairs({-1, 1}) do
		for _, z in ipairs({-82, -98}) do
			local x = side * 59
			deco({Name="PlazaBench",Size=Vector3.new(1.8,0.4,6),Position=Vector3.new(x,PLAZA_Y+1.3,z),
				Color=Color3.fromRGB(150,104,66),Material=Enum.Material.Wood})
			deco({Name="PlazaBenchBack",Size=Vector3.new(0.4,1.6,6),
				Position=Vector3.new(x+side*0.9,PLAZA_Y+2.2,z),
				Color=Color3.fromRGB(140,96,60),Material=Enum.Material.Wood})
			for _, dz in ipairs({-2.4, 2.4}) do
				deco({Name="PlazaBenchLeg",Size=Vector3.new(1.4,1.1,0.4),
					Position=Vector3.new(x,PLAZA_Y+0.55,z+dz),Color=Color3.fromRGB(70,70,76),
					Material=Enum.Material.Metal})
			end
		end
	end

	-- Low flower beds in the two gaps between the outer eggs. Not in the middle
	-- gap: that is where the south path arrives.
	for _, x in ipairs({-26, 26}) do
		deco({Name="PlazaBed",Size=Vector3.new(6,0.5,4),Position=Vector3.new(x,PLAZA_Y,-90),
			Color=Color3.fromRGB(82,140,66),Material=Enum.Material.Grass})
		for k = 0, 3 do
			deco({Name="PlanterBloom",Shape=Enum.PartType.Ball,Size=Vector3.new(0.8,0.8,0.8),
				Position=Vector3.new(x-1.8+k*1.2,PLAZA_Y+0.7,-90+((k%2==0) and -0.8 or 0.8)),
				Color=BLOOM[(k % #BLOOM) + 1],Material=Enum.Material.SmoothPlastic,CanCollide=false})
		end
	end

	-- ---- MEADOW ORB AREA (behind spawn between z=20 and z=110) ----
	-- (no separate platform needed, orbs float on terrain)
	-- Decorate the starter meadow so it isn't bare
	for _=1,10 do
		tree(math.random(-48,48), math.random(30,108), 0,
			Color3.fromRGB(95,65,35), Color3.fromRGB(60,160,50), 0.8+math.random()*0.6)
	end
	for _=1,28 do
		flower(math.random(-48,48), math.random(24,110), 0)
	end

	-- ---- SPAWN HUB: stone paths + centerpiece fountain ----
	local function path(cx, cz, sx, sz)
		part({Name="Path",Size=Vector3.new(sx,0.3,sz),Position=Vector3.new(cx,0.16,cz),
			Color=Color3.fromRGB(122,114,102),Material=Enum.Material.Slate,CanCollide=false})
	end
	path(40, 0, 80, 9)    -- east, toward the gates
	path(-44, 0, 80, 9)   -- west, toward shop + rebirth
	path(0, -46, 9, 92)   -- south, toward the eggs
	path(0, 26, 9, 56)    -- north, toward the fountain & meadow
	-- (fountain removed)

	-- ---- HUB DECOR: hedges and benches ----
	-- The six lamp posts are gone. Their heads were NEON balls sitting right
	-- beside the walking routes at (+/-30, 0) and the four diagonals, which is
	-- the "light on the path" — six small suns at head height on the way to
	-- every destination in the game.
	-- hedge ring around the plaza (gaps where the 4 paths exit)
	for a=0,11 do
		local ang=(a/12)*math.pi*2; local r=32
		local x=math.cos(ang)*r; local z=math.sin(ang)*r
		if math.abs(x)>9 or math.abs(z)>9 then
			part({Name="Hedge",Size=Vector3.new(5,3.2,3),Position=Vector3.new(x,0.6,z),Color=Color3.fromRGB(42,108,46),Material=Enum.Material.Grass,CanCollide=false})
		end
	end
	-- benches facing the fountain
	local function bench(x,z,rot)
		part({Name="BenchSeat",Size=Vector3.new(5,0.4,1.3),Position=Vector3.new(x,1.0,z),Orientation=Vector3.new(0,rot,0),Color=Color3.fromRGB(120,82,46),Material=Enum.Material.Wood,CanCollide=false})
		part({Name="BenchBack",Size=Vector3.new(5,1.3,0.3),Position=Vector3.new(x,1.7,z-0.5),Orientation=Vector3.new(0,rot,0),Color=Color3.fromRGB(120,82,46),Material=Enum.Material.Wood,CanCollide=false})
	end
	bench(12,16,0); bench(-12,16,0); bench(0,38,180)

	-- ---- NATURE: low-poly trees, boulders & flowers (gives the world life) ----
	local function tree(x,z,scale)
		scale = scale or 1
		part({Name="TreeTrunk",Size=Vector3.new(1.4,5,1.4)*scale,Position=Vector3.new(x,2.5*scale,z),Color=Color3.fromRGB(96,64,38),Material=Enum.Material.Wood,CanCollide=false})
		part({Name="TreeLeaf",Shape=Enum.PartType.Ball,Size=Vector3.new(7,6.5,7)*scale,Position=Vector3.new(x,6.4*scale,z),Color=Color3.fromRGB(56,130,54),Material=Enum.Material.Grass,CanCollide=false})
		part({Name="TreeLeaf",Shape=Enum.PartType.Ball,Size=Vector3.new(5,4.5,5)*scale,Position=Vector3.new(x+1.4*scale,8.6*scale,z),Color=Color3.fromRGB(66,144,60),Material=Enum.Material.Grass,CanCollide=false})
	end
	local function rock(x,z,s)
		part({Name="Rock",Shape=Enum.PartType.Ball,Size=Vector3.new(4.2,3,4.2)*s,Position=Vector3.new(x,0.5,z),Color=Color3.fromRGB(118,120,126),Material=Enum.Material.Slate,CanCollide=false})
	end
	local function flower(x,z,col)
		part({Name="FlowerStem",Size=Vector3.new(0.2,1.1,0.2),Position=Vector3.new(x,0.7,z),Color=Color3.fromRGB(60,130,55),Material=Enum.Material.Grass,CanCollide=false})
		-- Plastic, not Neon. A glowing flower is a light source, and there are
		-- dozens of them; together they were lighting the plaza.
		part({Name="FlowerTop",Shape=Enum.PartType.Ball,Size=Vector3.new(0.9,0.9,0.9),Position=Vector3.new(x,1.4,z),Color=col,Material=Enum.Material.SmoothPlastic,CanCollide=false})
	end
	-- A ring of trees around the plaza — but NOT on the paths.
	--
	-- The four paths run out along the axes: east and west to x = +/-80, south
	-- to the eggs, north to the meadow, each 9 studs wide. The ring sat at
	-- radius 47-57, so the trees on the axes stood in the middle of the
	-- walkway you take to every destination in the game. You walked into them.
	--
	-- Skipping any position whose x or z is inside a path corridor leaves the
	-- ring intact everywhere it was not in the way.
	local PATH_HALF = 9          -- half-width of a path, plus clearance
	for a=0,17 do
		local ang=(a/18)*math.pi*2; local r=47 + (a%3)*5
		local x, z = math.cos(ang)*r, math.sin(ang)*r
		if math.abs(x) > PATH_HALF and math.abs(z) > PATH_HALF then
			tree(x, z, 0.85 + (a%3)*0.18)
		end
	end
	-- scattered boulders
	for _,p in ipairs({{55,18,1.1},{-58,22,0.8},{60,-30,1.3},{-62,-26,0.9},{44,42,0.7},{-46,40,1.0},{20,52,0.8},{-22,54,1.1}}) do rock(p[1],p[2],p[3]) end
	-- colourful flower patches near the benches/paths
	local fcols={Color3.fromRGB(255,90,120),Color3.fromRGB(255,210,70),Color3.fromRGB(150,110,255),Color3.fromRGB(90,200,255)}
	for i=0,23 do
		local ang=(i/24)*math.pi*2; local r=20 + (i%4)*1.5
		flower(math.cos(ang)*r, 14+math.sin(ang)*r*0.4, fcols[(i%4)+1])
	end

	-- ---- THE MEADOW ITSELF ----
	--
	-- This call was lost when the shop building was removed: it happened to sit
	-- inside the block that was excised, and went with it. Meadow props fell
	-- from 111 to 29 and the spawn field went back to being bare lawn — the
	-- exact thing fixed several commits ago. Caught by the per-world count in
	-- check_map, which is why that check exists.
	--
	-- Placed here, after the hand-built plaza furniture, so it can never be
	-- caught inside a removal of one of those again.
	--
	-- The box is 100 x 130 rather than 60 x 90: the plaza keep-outs take the
	-- middle out, so a box barely wider than the plaza forced every cluster
	-- into a narrow band around the stone, and in 3D it read as a thicket on
	-- one side with bare lawn everywhere else.
	local PLAZA_KEEPOUT = {
		{ x = 0,   z = 0,   rx = 46, rz = 46 },    -- spawn platform and ring
		{ x = 0,   z = -75, rx = 74, rz = 60 },    -- egg terrace and connector
		{ x = -55, z = 0,   rx = 26, rz = 24 },    -- rebirth machine
		{ x = 0,   z = 32,  rx = 24, rz = 24 },    -- crystal monument
		{ x = -82, z = 118, rx = 16, rz = 16 },    -- the secret, left findable
	}
	decorateBiome("Meadow", 0, 0, {
		clusters = 26,
		halfW = 100, halfD = 130,
		blocked = function(x, z)
			-- Never on a path: the four walkways run along the axes.
			if math.abs(x) <= 11 or math.abs(z) <= 11 then return true end
			for _, k in ipairs(PLAZA_KEEPOUT) do
				if math.abs(x - k.x) < k.rx and math.abs(z - k.z) < k.rz then
					return true
				end
			end
			return false
		end,
	})

	-- ---- CENTERPIECE: crystal monument on the north lawn ----
	local cmX, cmZ = 0, 32
	part({Name="MonBase",Size=Vector3.new(11,1.2,11),Position=Vector3.new(cmX,0.7,cmZ),
		Color=Color3.fromRGB(118,114,108),Material=Enum.Material.Marble})
	part({Name="MonStep",Size=Vector3.new(8,1.0,8),Position=Vector3.new(cmX,1.7,cmZ),
		Color=Color3.fromRGB(96,92,88),Material=Enum.Material.Slate})
	local function crystal(x,z,h,col)
		local c=part({Name="Crystal",Size=Vector3.new(1.5,h,1.5),Position=Vector3.new(x,2.2+h/2,z),
			Color=col,Material=Enum.Material.Glass,Transparency=0.1,CanCollide=false}); c.Reflectance=0.25
		local tip=part({Name="CrystalTip",Size=Vector3.new(1.5,1.5,1.5),Position=Vector3.new(x,2.2+h,z),
			Orientation=Vector3.new(45,0,45),Color=col,Material=Enum.Material.Glass,Transparency=0.1,CanCollide=false}); tip.Reflectance=0.25
	end
	crystal(cmX,cmZ,6.5,Color3.fromRGB(150,90,230))
	crystal(cmX-2,cmZ+1,4.0,Color3.fromRGB(120,80,220))
	crystal(cmX+2,cmZ-1,4.6,Color3.fromRGB(180,130,245))

	-- ---- LAWN DECOR: trees, rocks, garden beds around the plaza ----
	for _,t in ipairs({{18,44},{-18,44},{30,34},{-30,34},{14,56},{-14,56},{26,52},{-26,52}}) do
		tree(t[1],t[2],0,Color3.fromRGB(96,64,40),Color3.fromRGB(46,120,52),0.85)
	end
	local function decorRock(x,z,s)
		part({Name="Rock",Size=Vector3.new(2.4*s,1.6*s,2.2*s),Position=Vector3.new(x,0.7*s,z),
			Orientation=Vector3.new(0,(x*13)%360,0),Color=Color3.fromRGB(108,104,98),
			Material=Enum.Material.Slate,CanCollide=false})
	end
	for _,r in ipairs({{24,8,1},{-24,8,0.8},{28,-12,1.1},{-28,-12,0.9},{20,-22,0.7}}) do decorRock(r[1],r[2],r[3]) end
	local function flowerbed(x,z)
		local cols={Color3.fromRGB(220,80,110),Color3.fromRGB(240,190,70),Color3.fromRGB(150,110,235),Color3.fromRGB(235,235,245)}
		part({Name="FlowerBed",Size=Vector3.new(4,0.25,4),Position=Vector3.new(x,0.26,z),
			Color=Color3.fromRGB(70,50,35),Material=Enum.Material.Ground,CanCollide=false})
		for i=1,4 do
			part({Name="Bloom",Size=Vector3.new(0.7,0.5,0.7),
				Position=Vector3.new(x+math.random(-15,15)/10,0.5,z+math.random(-15,15)/10),
				Color=cols[math.random(1,#cols)],Material=Enum.Material.Grass,CanCollide=false})
		end
	end
	for _,f in ipairs({{16,20},{-16,20},{22,-18},{-22,-18}}) do flowerbed(f[1],f[2]) end

	-- ---- BIOMES (each 130 wide x 190 deep, 130 studs apart) ----
	local AreaBarriers = Instance.new("Folder")
	-- Inside StarPetsMap: as a sibling in Workspace, copying "the map" would
	-- take the scenery and silently leave every buy-gate behind.
	AreaBarriers.Name = "AreaBarriers"; AreaBarriers.Parent = MapPersist.Container()
	-- Each world gets a floor colour, a cliff colour and a stone colour rather
	-- than one flat tone. Cliffs a shade off the floor are what make a raised
	-- terrace read as rock holding up ground, instead of the same slab twice.
	local biomes={
		{id="Forest",  cx=145, col=Color3.fromRGB(30,96,34),
			cliff=Color3.fromRGB(86,72,54),  stone=Color3.fromRGB(104,114,102),
			mat=Enum.Material.Grass},
		{id="Desert",  cx=275, col=Color3.fromRGB(198,168,104),
			cliff=Color3.fromRGB(170,132,82), stone=Color3.fromRGB(190,164,120),
			mat=Enum.Material.Sand},
		{id="Volcano", cx=405, col=Color3.fromRGB(78,44,38),
			cliff=Color3.fromRGB(62,44,40),  stone=Color3.fromRGB(92,70,64),
			mat=Enum.Material.Basalt},
		{id="Space",   cx=535, col=Color3.fromRGB(112,114,128),
			cliff=Color3.fromRGB(86,88,102), stone=Color3.fromRGB(152,154,168),
			mat=Enum.Material.Slate},
	}
	for _,b in ipairs(biomes) do
		-- Biome floor (130 wide x 190 deep = fits 4-5 players comfortably)
		part({Name="Biome_"..b.id,Size=Vector3.new(130,2,190),
			Position=Vector3.new(b.cx,-1,0),Color=b.col,Material=b.mat})

		-- Elevation. Every world used to be one flat slab at a single height,
		-- so you saw the whole thing at once from the gate and there was
		-- nothing to walk towards. A terrace across the back, a cliff behind
		-- it and steps up the middle cost about a dozen parts and give each
		-- world a foreground, a stage and an edge.
		local th = { ground = b.col, cliff = b.cliff, stone = b.stone,
			groundMat = b.mat }
		MapProps.Terrain({ part = part }, b.cx, 0, th)

		-- One large thing per world, on the terrace, tall enough to be seen
		-- from the world before it — so you can see where you are going before
		-- you can afford to go there.
		local lm = MapProps.LANDMARKS[PROP_SET[b.id] or ""]
		if lm then
			lm({ part = part }, b.cx, MapProps.TERRACE_Z, MapProps.TERRACE_Y, th)
		end

		-- Props on the walkable front half. The terrace is where the landmark
		-- stands, so scattering trees over it would bury the thing the world
		-- is supposed to be remembered for.
		-- 20 clusters, not 14. The terrace takes the back third of the island
		-- out of play for props, so the same cluster count over half the area
		-- leaves the walkable part thinner than it was before the terrace
		-- existed — which would make the world feel emptier, not fuller.
		-- This world's own egg, just inside the gate and north of the walk-in
		-- lane, so it is the first thing a player meets after unlocking it.
		-- Props keep a square around it clear, or a basalt column grows out of
		-- the pedestal.
		local worldEgg = nil
		for _, e in ipairs(GameConfig.Eggs) do
			if e.world == b.id then worldEgg = e break end
		end
		local eggX, eggZ = b.cx - 42, 24
		-- 16, not 10. This tests where a prop is ANCHORED, and a feature
		-- spreads its parts several studs around its anchor — a rock cluster
		-- anchored at 11 studs put a rock 6 from the egg, close enough to take
		-- the click meant for it. check_map measures the actual parts.
		local function nearEgg(x, z)
			return worldEgg ~= nil and math.abs(x - eggX) < 16 and math.abs(z - eggZ) < 16
		end

		decorateBiome(b.id, b.cx, 0, {
			clusters = 20,
			blocked = function(x, z) return z < -30 or nearEgg(x, z) end,
		})
		if worldEgg then
			eggStand(worldEgg, Vector3.new(eggX, 0, eggZ))
		end

		local areaConfig=nil
		for _,a in ipairs(GameConfig.Areas) do if a.id==b.id then areaConfig=a break end end
		if not areaConfig then continue end

		-- Big world-name sign floating over the middle of the biome
		local nameAnchor=part({Name="BiomeName_"..b.id,Size=Vector3.new(1,1,1),
			Position=Vector3.new(b.cx,30,0),Transparency=1,CanCollide=false})
		-- Smaller, and it stops rendering before the next world's sign starts.
		-- The worlds sit 130 studs apart; at 140 studs of draw distance every
		-- sign on the map was on screen at once, all of them 440 wide, written
		-- across each other into one unreadable pile. 95 keeps a sign to its
		-- own world.
		billboard(nameAnchor,areaConfig.name,Color3.fromRGB(255,255,255),
			areaConfig.description,Color3.fromRGB(210,210,235),UDim2.new(0,260,0,84),95)

		local gateX=b.cx-65  -- gate sits at left edge of biome

		local cost=areaConfig.unlockCost==0 and "FREE" or ("💰 "..comma(areaConfig.unlockCost).." Coins")

		-- BLACK WALL that closes off the locked island (no gate/door arch).
		-- Click it to unlock; it vanishes per-player once unlocked (updateBarriers).
		local barrier=part({Name="Barrier_"..b.id,Size=Vector3.new(3,36,250),
			Position=Vector3.new(gateX,16,5),Color=Color3.fromRGB(22,20,30),
			Material=Enum.Material.SmoothPlastic,Transparency=0,CanCollide=false})
		barrier.Parent=AreaBarriers
		part({Name="BStripe",Size=Vector3.new(3.2,3.5,250),Position=Vector3.new(gateX,33,5),
			Color=b.col,Material=Enum.Material.SmoothPlastic,CanCollide=false}).Parent=barrier
		local cd=Instance.new("ClickDetector"); cd.MaxActivationDistance=32; cd.Parent=barrier
		MapPersist.Bind(cd, "BuyArea", b.id)
		-- requirement sign on the wall
		local sign=Instance.new("BillboardGui")
		-- 640x240 at 400 studs was the single worst thing on screen. Four
		-- locked worlds meant four of these drawn at once from anywhere on the
		-- map, each one bigger than a world, overlapping every other sign and
		-- the world names on top of that. A price tag should be readable when
		-- you walk up to the wall it is on, and invisible from three worlds
		-- away.
		sign.Name="WallSign"; sign.Size=UDim2.new(0,380,0,150); sign.StudsOffset=Vector3.new(0,12,0)
		sign.MaxDistance=95; sign.Adornee=barrier; sign.Parent=barrier
		local t1=Instance.new("TextLabel"); t1.Size=UDim2.new(1,0,0.42,0); t1.BackgroundTransparency=1
		t1.Text="🔒 "..areaConfig.name; t1.TextColor3=Color3.new(1,1,1); t1.TextScaled=true
		t1.Font=Enum.Font.GothamBold; t1.TextStrokeTransparency=0.25; t1.TextStrokeColor3=Color3.new(0,0,0); t1.Parent=sign
		local t2=Instance.new("TextLabel"); t2.Size=UDim2.new(1,0,0.4,0); t2.Position=UDim2.new(0,0,0.42,0)
		t2.BackgroundTransparency=1; t2.Text="Costs "..cost; t2.TextColor3=Color3.fromRGB(255,215,0); t2.TextScaled=true
		t2.Font=Enum.Font.GothamBold; t2.TextStrokeTransparency=0.25; t2.TextStrokeColor3=Color3.new(0,0,0); t2.Parent=sign
		local t3=Instance.new("TextLabel"); t3.Size=UDim2.new(1,0,0.18,0); t3.Position=UDim2.new(0,0,0.82,0)
		t3.BackgroundTransparency=1; t3.Text="Click to unlock"; t3.TextColor3=Color3.fromRGB(185,205,255)
		t3.TextScaled=true; t3.Font=Enum.Font.Gotham; t3.Parent=sign
	end

	-- ============================================================
	-- PHYSICAL SHOP BUILDING — REMOVED
	-- ============================================================
	-- The building, its neon roof strip and the six glowing upgrade pads are
	-- gone at the owner's request. Nothing is lost: the HUD dock already has
	-- both a Shop and an Upgrade button, so every panel the building opened is
	-- one tap away, and the spawn is no longer a shed with a purple glow on it.
	-- ---- BOUNDARY WALLS (solid + invisible extension so no climbing out) ----
	local wallH = 25

	-- The border, themed per world.
	--
	-- It used to be one 720-stud green hedge running the whole length of the
	-- map, with a leafy ball every 16 studs, on top of a strip of green lawn —
	-- straight past the desert, the volcano and the space station. A volcano
	-- with a garden hedge round it, and a moon base on a lawn. Each world now
	-- gets a wall, a cap and a ground apron that belong to it.
	--
	-- The visible wall is built in segments so each can take its world's look,
	-- but the invisible extension that stops players jumping out stays one
	-- continuous part per side: segments meeting edge to edge are fine to look
	-- at, and a gap between two of them is a hole in the map.
	local BORDER = {
		{ x0=-103, x1=80,  wall=Color3.fromRGB(46,104,46),  wallMat=Enum.Material.Grass,
		  cap=Color3.fromRGB(56,122,56),  capMat=Enum.Material.Grass,     capShape="ball" },   -- Meadow
		{ x0=80,   x1=210, wall=Color3.fromRGB(34,82,36),   wallMat=Enum.Material.Grass,
		  cap=Color3.fromRGB(40,96,42),   capMat=Enum.Material.Grass,     capShape="ball" },   -- Forest
		{ x0=210,  x1=340, wall=Color3.fromRGB(176,142,86), wallMat=Enum.Material.Sandstone,
		  cap=Color3.fromRGB(196,162,104),capMat=Enum.Material.Sandstone, capShape="block",
		  apron=Color3.fromRGB(198,168,104), apronMat=Enum.Material.Sand },                    -- Desert
		{ x0=340,  x1=470, wall=Color3.fromRGB(52,34,30),   wallMat=Enum.Material.Basalt,
		  cap=Color3.fromRGB(40,28,26),   capMat=Enum.Material.Basalt,    capShape="rock",
		  apron=Color3.fromRGB(64,40,34), apronMat=Enum.Material.Basalt },                     -- Volcano
		{ x0=470,  x1=617, wall=Color3.fromRGB(88,90,104),  wallMat=Enum.Material.Slate,
		  cap=Color3.fromRGB(104,106,120),capMat=Enum.Material.Slate,     capShape="rock",
		  apron=Color3.fromRGB(100,102,116), apronMat=Enum.Material.Slate },                   -- Space
	}

	local function themeAt(x)
		for _, t in ipairs(BORDER) do
			if x >= t.x0 and x < t.x1 then return t end
		end
		return BORDER[#BORDER]
	end

	local function cap(theme, at)
		if theme.capShape == "ball" then
			part({Name="Hedge",Shape=Enum.PartType.Ball,Size=Vector3.new(7,6,7),
				Position=at,Color=theme.cap,Material=theme.capMat,CanCollide=false})
		elseif theme.capShape == "block" then
			-- Sandstone merlons: a desert wall reads as built, not grown.
			part({Name="BorderCap",Size=Vector3.new(5,3,5),
				Position=at+Vector3.new(0,-1,0),Color=theme.cap,Material=theme.capMat,CanCollide=false})
		else
			-- Rough boulders, two to a spot and not quite aligned, so the line
			-- reads as rock rather than a row of identical balls.
			part({Name="BorderCap",Shape=Enum.PartType.Ball,Size=Vector3.new(6,4.5,6),
				Position=at+Vector3.new(0,-0.8,0),Color=theme.cap,Material=theme.capMat,CanCollide=false})
			part({Name="BorderCap",Size=Vector3.new(3.4,2.6,3.2),
				Position=at+Vector3.new(2.2,-1.2,0.9),Color=theme.wall,Material=theme.capMat,CanCollide=false})
		end
	end

	-- A wall running along X, split into one visible segment per world.
	local function buildWallX(name, z, xFrom, xTo)
		local y = wallH/2-1
		for _, t in ipairs(BORDER) do
			local a, b = math.max(xFrom, t.x0), math.min(xTo, t.x1)
			if b > a then
				local mid, len = (a+b)/2, b-a
				part({Name=name,Size=Vector3.new(len,wallH,4),Position=Vector3.new(mid,y,z),
					Color=t.wall,Material=t.wallMat})
				-- Spaced INSIDE the segment, never on its ends. With i/n the last
				-- cap sat exactly on the boundary, and the boundary is the first
				-- stud of the next world — so the Forest put a green hedge on the
				-- Desert's wall at each end.
				local n = math.max(1, math.floor(len/16))
				for i=0,n do
					cap(t, Vector3.new(a + ((i+0.5)/(n+1))*len, y+wallH/2, z))
				end
			end
		end
		-- One continuous invisible extension: no seams for anyone to climb through.
		part({Name=name.."Ext",Size=Vector3.new(xTo-xFrom,40,4),
			Position=Vector3.new((xFrom+xTo)/2,y+30,z),Transparency=1,CanCollide=true})
	end

	-- A short end wall along Z, in the theme of whichever world it closes off.
	local function buildWallZ(name, x, len)
		local t = themeAt(x)
		local y = wallH/2-1
		local pos = Vector3.new(x,y,5)
		part({Name=name,Size=Vector3.new(4,wallH,len),Position=pos,Color=t.wall,Material=t.wallMat})
		part({Name=name.."Ext",Size=Vector3.new(4,40,len),Position=pos+Vector3.new(0,30,0),
			Transparency=1,CanCollide=true})
		local n = math.max(1, math.floor(len/16))
		for i=0,n do
			cap(t, Vector3.new(x, y+wallH/2, 5 - len/2 + (i/n)*len))
		end
	end

	buildWallX("WallN",  126, -103, 617)
	buildWallX("WallS", -116, -103, 617)
	buildWallZ("WallW", -91, 246)
	buildWallZ("WallE", 606, 246)

	-- Ground aprons: the strip between each world's floor and its walls was the
	-- shared green lawn. Desert, Volcano and Space each cover theirs. Laid just
	-- above the ground slab and below the world floor, so neither is disturbed.
	-- Out to the edge of the ground slab, not just to the wall: a player cannot
	-- walk past the wall, but they can see over it, and a strip of lawn behind
	-- a volcano is still a strip of lawn behind a volcano. The last world runs
	-- on to the slab's far end for the same reason.
	for idx, t in ipairs(BORDER) do
		if t.apron then
			local x0 = math.max(t.x0, -103)
			local x1 = (idx == #BORDER) and 670 or t.x1
			for _, strip in ipairs({ {z0=95, z1=155}, {z0=-145, z1=-95} }) do
				part({Name="Apron",Size=Vector3.new(x1-x0, 0.4, strip.z1-strip.z0),
					Position=Vector3.new((x0+x1)/2, -0.55, (strip.z0+strip.z1)/2),
					Color=t.apron, Material=t.apronMat})
			end
		end
	end

	-- ============================================================
	-- 🗝️ SECRET SPOT  (hidden — tell nobody)
	-- Location: northwest corner, tight against north wall at z=122, x=-82
	-- Looks like a plain dark rock, tiny glow only visible up close
	-- ============================================================
	-- INVISIBLE in the far corner — no shape, no glow, nothing to spot from a distance.
	-- Only a faint "Search" prompt appears when a player wanders right onto the spot.
	local secretChest=part({Name="SecretChest",Size=Vector3.new(1,1,1),
		Position=Vector3.new(-82,0.6,118),Color=Color3.fromRGB(86,82,78),Material=Enum.Material.Slate})
	secretChest.Transparency=1      -- cannot be seen; must be stumbled upon
	secretChest.CanCollide=false

	-- Hold-to-search prompt, tiny range — you must be standing right on it
	local secretPrompt=Instance.new("ProximityPrompt")
	secretPrompt.ActionText="Search"
	secretPrompt.ObjectText="???"
	secretPrompt.HoldDuration=1.2
	secretPrompt.MaxActivationDistance=6
	secretPrompt.RequiresLineOfSight=false
	secretPrompt.Parent=secretChest
	MapPersist.Bind(secretPrompt, "SecretChest")

	-- ============================================================
	-- PHYSICAL LEADERBOARD BOARD — REMOVED
	-- ============================================================
	-- The board, its gold neon frame and the live SurfaceGui are gone at the
	-- owner's request. The HUD dock has a Ranks button, so the leaderboard is
	-- still one tap away; it simply no longer occupies the spawn.
	-- ============================================================
	-- REBIRTH MACHINE
	-- ============================================================
	local machinePos = Vector3.new(-55, 0, 0)  -- left of spawn, not blocking egg area or biomes

	-- Base slab
	part({Name="RMBase",Size=Vector3.new(14,1,14),Position=machinePos+Vector3.new(0,-0.5,0),
		Color=Color3.fromRGB(74,72,82),Material=Enum.Material.Slate})

	-- Base glow ring
	-- Was a neon ring with a PointLight and a particle emitter. Now a plain
	-- metal trim: the shape still reads as a machine base, without the purple
	-- glow washing over the plaza.
	part({Name="RMRing",Size=Vector3.new(15,0.3,15),Position=machinePos+Vector3.new(0,0.15,0),
		Color=Color3.fromRGB(196,166,104),Material=Enum.Material.Metal,CanCollide=false})

	-- Four corner pillars
	-- Stone, not purple. Taking the neon off left the machine still reading
	-- as a purple object, because the pillars, the arch and the core body
	-- were all violet underneath it.
	local pillarColor = Color3.fromRGB(92,88,102)
	local corners = {Vector3.new(5,0,5),Vector3.new(-5,0,5),Vector3.new(5,0,-5),Vector3.new(-5,0,-5)}
	for i,c in ipairs(corners) do
		local pil = part({Name="RMPillar"..i,Size=Vector3.new(2,8,2),
			Position=machinePos+c+Vector3.new(0,4,0),Color=pillarColor,Material=Enum.Material.SmoothPlastic})
		-- Pillar top glow cap
		part({Name="RMCap"..i,Size=Vector3.new(2.4,0.5,2.4),
			Position=machinePos+c+Vector3.new(0,8.3,0),Color=Color3.fromRGB(196,166,104),
			Material=Enum.Material.Metal,CanCollide=false})
	end

	-- Top arch connecting pillars
	part({Name="RMArchFront",Size=Vector3.new(12,1.5,2),Position=machinePos+Vector3.new(0,8.5,5),
		Color=pillarColor,Material=Enum.Material.SmoothPlastic})
	part({Name="RMArchBack",Size=Vector3.new(12,1.5,2),Position=machinePos+Vector3.new(0,8.5,-5),
		Color=pillarColor,Material=Enum.Material.SmoothPlastic})

	-- Central glowing core (the machine itself)
	local core = part({Name="RMCore",Size=Vector3.new(4,6,4),
		Position=machinePos+Vector3.new(0,3.5,0),Color=Color3.fromRGB(80,78,90),
		Material=Enum.Material.Slate})
	-- Core neon inner
	-- Glass rather than neon: it still reads as "something is inside this"
	-- without being a light source. Neon on a 3x5 block is the single
	-- brightest thing in the plaza.
	part({Name="RMCoreGlow",Size=Vector3.new(3,5,3),
		Position=machinePos+Vector3.new(0,3.5,0),Color=Color3.fromRGB(118,96,160),
		Material=Enum.Material.Glass,CanCollide=false,Transparency=0.35})
	-- Spinning energy ball on top
	-- Kept a little colour on purpose: this ball is one of the two things you
	-- CLICK to rebirth, and a machine with no highlight anywhere reads as
	-- scenery. Glass, one soft light, no particles.
	local orb = part({Name="RMOrb",Shape=Enum.PartType.Ball,Size=Vector3.new(2.5,2.5,2.5),
		Position=machinePos+Vector3.new(0,7.5,0),Color=Color3.fromRGB(198,176,236),
		Material=Enum.Material.Glass,CanCollide=false,Transparency=0.2})
	-- No light on it. This PointLight was the last light source left in the
	-- whole map and it sat on the rebirth machine, which is the one thing the
	-- owner said they did not want glowing. The orb still reads as the thing to
	-- click: it is glass, it is pale against the slate, it bobs and it turns.
	-- check_map fails if any light source comes back.

	-- Orbit rings around the orb
	for i=1,3 do
		part({Name="RMOrbRing"..i,Size=Vector3.new(4+i*0.5,0.15,4+i*0.5),
			Position=machinePos+Vector3.new(0,7.5,0),Color=Color3.fromRGB(176,150,96),
			Material=Enum.Material.Metal,CanCollide=false})
	end

	-- The rings orbit and the orb bobs on each client (WorldMotion.client.lua),
	-- not here: a server loop sent every frame of that motion to every player.

	-- Sign billboard
	local signAnchor = part({Name="RMSign",Size=Vector3.new(1,1,1),
		Position=machinePos+Vector3.new(0,12,0),Transparency=1,CanCollide=false})
	local bb = Instance.new("BillboardGui")
	bb.Size=UDim2.new(0,220,0,80); bb.StudsOffset=Vector3.new(0,0,0)
	-- MaxDistance was never set, and the default is infinite: the magenta
	-- REBIRTH sign was drawn over the map from every world on it.
	bb.MaxDistance=70
	bb.Adornee=signAnchor; bb.AlwaysOnTop=false; bb.Parent=signAnchor

	local t1=Instance.new("TextLabel"); t1.Size=UDim2.new(1,0,0.5,0)
	t1.BackgroundTransparency=1; t1.Text="♻️  REBIRTH"
	t1.TextColor3=Color3.fromRGB(220,100,255); t1.TextScaled=true
	t1.Font=Enum.Font.GothamBold
	t1.TextStrokeTransparency=0.3; t1.TextStrokeColor3=Color3.new(0,0,0); t1.Parent=bb

	local t2=Instance.new("TextLabel"); t2.Size=UDim2.new(1,0,0.5,0)
	t2.Position=UDim2.new(0,0,0.5,0); t2.BackgroundTransparency=1
	t2.Text="Click to reset & multiply!"; t2.TextColor3=Color3.fromRGB(200,200,220)
	t2.TextScaled=true; t2.Font=Enum.Font.Gotham
	t2.TextStrokeTransparency=0.4; t2.TextStrokeColor3=Color3.new(0,0,0); t2.Parent=bb

	-- Click detector on core
	local cd = Instance.new("ClickDetector"); cd.MaxActivationDistance=20; cd.Parent=core
	MapPersist.Bind(cd, "Rebirth")   -- opens the confirmation popup on the client
	-- Also clickable on the orb
	local cd2 = Instance.new("ClickDetector"); cd2.MaxActivationDistance=20; cd2.Parent=orb
	MapPersist.Bind(cd2, "Rebirth")

	-- ============================================================
	-- CLEANUP: remove leftover imported-map junk that overlapped the built-in
	-- map and broke the floor (caused fall-death). The built-in map stays intact.
	-- ============================================================
	local function nukeContainerOf(childName)
		local c = workspace:FindFirstChild(childName, true)
		if c then
			while c.Parent and c.Parent ~= workspace do c = c.Parent end
			if c and c.Parent == workspace then c:Destroy() end
		end
	end
	for _, n in ipairs({"CustomMap","Folder","Snow Map","Stone Map","Desert Map","Forest Map",
		"Map Border","ThumbnailCamera","SpawnLocationw","maps"}) do
		nukeContainerOf(n)
	end
end

-- ============================================================
-- DATA SYNC
-- ============================================================
local function syncData(player)
	local data = DataManager.GetData(player)
	if data then RE_DataUpdated:FireClient(player,data) end
end

-- ============================================================
-- WHAT CLICKING A THING IN THE MAP MEANS
-- ============================================================
-- One table, one definition per action. The map only records WHICH action a
-- part performs, as an attribute; it never carries the code. That is what lets
-- the map be saved into the place as ordinary parts and still work.
--
-- Every one of these used to be an anonymous closure written inline next to the
-- part it belonged to, several hundred lines apart — and the secret chest one
-- called a `syncData` that was not in scope where it was written. Being 200
-- lines above this declaration, it resolved to a nil global, so finding the
-- secret threw immediately after granting the badge and the player's coin
-- counter did not move. Collecting them here is what made that visible.
-- ClickDetectors never pass through any guard around the remotes, because no
-- remote is involved on the way in. SecretChest writes to player data.
MapPersist.SetRateLimit(RateLimit)
MapPersist.Handlers({
	HatchEgg = function(player, eggId)
		RE_HatchEgg:FireClient(player, eggId)
	end,
	BuyArea = function(player, areaId)
		RE_BuyArea:FireClient(player, areaId)
	end,
	UpgradePad = function(player, key)
		RE_HatchEgg:FireClient(player, "__upgrade__" .. tostring(key))
	end,
	OpenLeaderboard = function(player)
		RE_TitleUpdate:FireClient(player, "__openleaderboard__")
	end,
	Rebirth = function(player)
		RE_Rebirth:FireClient(player)
	end,
	SecretChest = function(player)
		local data = DataManager.GetData(player)
		if not data then return end
		if data.FoundSecret then
			RE_Notification:FireClient(player, "info", "You already found this secret! 🗝️")
			return
		end
		data.FoundSecret = true
		local reward = GameConfig.SecretReward
		data.Coins = data.Coins + (reward.coins or 0)
		data.Gems = data.Gems + (reward.gems or 0)
		DataManager.IncrementData(player, "TotalCoinsEarned", reward.coins or 0)
		RE_SecretFound:FireClient(player, reward)
		BadgeService.Grant(player, "secret_finder")
		syncData(player)
		print("[Secret] " .. player.Name .. " found the secret spot!")
	end,
})

task.spawn(function()
	while true do
		task.wait(2)
		for _,p in ipairs(Players:GetPlayers()) do syncData(p) end
	end
end)

-- ============================================================
-- PLAYER JOIN / LEAVE
-- ============================================================
local function onPlayerAdded(player)
	local data0, loadErr = DataManager.LoadPlayer(player)
	if not data0 then
		-- Their save could not be read. Letting them play would mean an hour of
		-- progress on data that DataManager will correctly refuse to write —
		-- and, before that refusal existed, would have meant their real record
		-- being overwritten with defaults. Better to say so and let them
		-- rejoin: the outage is usually over in minutes, and their save is
		-- untouched.
		warn(("[StarPets] load failed for %s (%s) — asking them to rejoin.")
			:format(player.Name, tostring(loadErr)))
		player:Kick("Your save could not be loaded right now, so the game has "
			.. "stopped rather than risk your pets and coins.\n\nYour data is "
			.. "SAFE and untouched. Please rejoin in a minute.")
		return
	end
	-- Saves made before the Pet Index had a permanent record: everything they
	-- currently hold counts as discovered, so nobody's collection appears to
	-- reset on the update that introduced it.
	pcall(PetService.BackfillDiscovery, data0)

	-- OFFLINE EARNINGS: pay out coins earned while the player was away (50% rate, 8h cap)
	do
		local data = DataManager.GetData(player)
		if data and (data.LastSeen or 0) > 0 then
			local away = math.clamp(os.time() - data.LastSeen, 0, 8*3600)
			local rate = PetService.GetPlayerIncome(player)   -- coins/sec
			local earned = math.floor((rate or 0) * away * 0.5)
			if earned > 0 then
				data.Coins = (data.Coins or 0) + earned
				data.TotalCoinsEarned = (data.TotalCoinsEarned or 0) + earned
				task.delay(3.5, function()
					if player.Parent then RE_OfflineEarnings:FireClient(player, earned, away) end
				end)
			end
		end
		if data then data.LastSeen = os.time() end
	end
	GamepassService.CheckAllForPlayer(player)
	-- Check badges on join (gives Welcome badge + any already earned)
	task.delay(2, function()
		BadgeService.CheckAll(player)
	end)
	local function applyTitle(char, data)
		-- Remove existing title GUI
		local existing = char:FindFirstChild("TitleGui")
		if existing then existing:Destroy() end

		local titleDef = LeaderboardService.GetTitle(data)
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		local bg = Instance.new("BillboardGui")
		bg.Name          = "TitleGui"
		bg.Size          = UDim2.new(0, 160, 0, 28)
		bg.StudsOffset   = Vector3.new(0, 3.2, 0)
		-- A rank title is for the person standing next to you, not for someone
		-- three worlds away. Unset, this drew every player's title across the
		-- whole map.
		bg.MaxDistance   = 60
		bg.Adornee       = hrp
		bg.AlwaysOnTop   = false
		bg.Parent        = char

		local lbl = Instance.new("TextLabel")
		lbl.Size             = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundColor3 = Color3.fromRGB(12, 9, 24)
		lbl.BackgroundTransparency = 0.25
		lbl.Text             = titleDef.label
		lbl.TextColor3       = titleDef.color
		lbl.TextScaled       = true
		lbl.Font             = Enum.Font.GothamBold
		lbl.TextStrokeTransparency = 0.4
		lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
		lbl.Parent           = bg
		Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 6)
		local stroke = Instance.new("UIStroke", lbl)
		stroke.Color = titleDef.color; stroke.Transparency = 0.5
	end

	player.CharacterAdded:Connect(function(char)
		char:WaitForChild("HumanoidRootPart")
		task.wait(0.5)
		PetService.RestoreEquipped(player)
		UpgradeService.ApplyToCharacter(player)
		local d = DataManager.GetData(player)
		if d then applyTitle(char, d) end
		syncData(player)
	end)

	-- Re-apply title whenever data syncs (title can change mid-session)
	local lastTitleId = ""
	task.spawn(function()
		while player.Parent do
			task.wait(10)
			local d = DataManager.GetData(player)
			if d and player.Character then
				local titleDef = LeaderboardService.GetTitle(d)
				if titleDef.id ~= lastTitleId then
					lastTitleId = titleDef.id
					applyTitle(player.Character, d)
				end
			end
		end
	end)
	if player.Character then
		task.wait(0.5)
		PetService.RestoreEquipped(player)
		local d = DataManager.GetData(player)
		if d then applyTitle(player.Character, d) end
	end
	-- Submit initial scores
	task.delay(3, function() pcall(LeaderboardService.UpdatePlayer, player) end)
	syncData(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	local d = DataManager.GetData(player); if d then d.LastSeen = os.time() end
	PetService.DespawnAllPets(player)
	DataManager.RemovePlayer(player)
end)
for _,p in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded,p) end

-- ============================================================
-- REMOTE HANDLERS
-- ============================================================
RF_GetData.OnServerInvoke = function(player)
	return DataManager.GetData(player)
end

RE_HatchEgg.OnServerEvent:Connect(function(player,eggId,count)
	count = type(count)=="number" and math.clamp(count,1,10) or 1
	local results,errors = EggService.HatchMultiple(player,eggId,count)
	if #results>0 then
		-- A hatched pet goes straight into a FREE slot.
		--
		-- Nothing equipped a hatched pet before. PetService.EquipBest existed
		-- and was never called, so a brand-new player hatched their free egg,
		-- got a pet, and it sat in the inventory earning nothing until they
		-- found the Pets panel and pressed Equip — which nothing told them to
		-- do. Only free slots are filled: a pet the player chose to equip is
		-- never pushed out by one they just hatched. EquipPet refuses once the
		-- slots are full, so a ten-hatch stops filling at the limit.
		for _, pet in ipairs(results) do
			local ok = PetService.EquipPet(player, pet.uniqueId)
			if not ok then break end
		end
		RE_HatchResult:FireClient(player,results,eggId)
		-- A batch that stopped early says why. It used to drop the reason, so
		-- an x10 that ran out of coins after three showed three pets and
		-- nothing else, which looks like the other seven were eaten.
		if #results < count and errors[1] then
			RE_Notification:FireClient(player,"info",
				("Hatched %d of %d — %s"):format(#results, count, tostring(errors[1])))
		end
		syncData(player)
		BadgeService.CheckAll(player)
	else
		RE_Notification:FireClient(player,"error",errors[1] or "Hatch failed")
	end
end)

RE_EquipPet.OnServerEvent:Connect(function(player,uniqueId)
	local ok,msg = PetService.EquipPet(player,uniqueId)
	if ok then syncData(player)
	else RE_Notification:FireClient(player,"error",msg or "Cannot equip") end
end)

RE_UnequipPet.OnServerEvent:Connect(function(player,uniqueId)
	PetService.UnequipPet(player,uniqueId); syncData(player)
end)

RE_BuyArea.OnServerEvent:Connect(function(player,areaId)
	local data = DataManager.GetData(player)
	if not data then return end
	for _,id in ipairs(data.UnlockedAreas) do
		if id==areaId then RE_Notification:FireClient(player,"info","Already unlocked!"); return end
	end
	local areaConfig, prev = nil, nil
	for i,a in ipairs(GameConfig.Areas) do
		if a.id==areaId then areaConfig=a; prev=GameConfig.Areas[i-1]; break end
	end
	if not areaConfig then return end
	-- In order. The gates enforce this physically, but a gate's collision is
	-- the client's to decide; the remote is anyone's to fire. Without this a
	-- direct call could buy Space before ever seeing the Forest.
	if prev then
		local hasPrev = false
		for _,id in ipairs(data.UnlockedAreas) do if id==prev.id then hasPrev=true break end end
		if not hasPrev then
			RE_Notification:FireClient(player,"error","Unlock "..prev.name.." first!"); return
		end
	end
	if areaConfig.currency=="Coins" then
		if data.Coins<areaConfig.unlockCost then
			RE_Notification:FireClient(player,"error","Need 💰 "..areaConfig.unlockCost.." Coins!"); return
		end
		data.Coins=data.Coins-areaConfig.unlockCost
	elseif areaConfig.currency=="Gems" then
		if data.Gems<areaConfig.unlockCost then
			RE_Notification:FireClient(player,"error","Need 💎 "..areaConfig.unlockCost.." Gems!"); return
		end
		data.Gems=data.Gems-areaConfig.unlockCost
	end
	table.insert(data.UnlockedAreas,areaId)
	RE_Notification:FireClient(player,"success","🎉 Unlocked "..areaConfig.name.."!")
	syncData(player)
	BadgeService.CheckAll(player)
end)

-- Machine click → server fires RE_Rebirth:FireClient(player) to open the
-- rebirth popup on the client (the client handles RE_Rebirth.OnClientEvent).

-- Client confirms rebirth → server executes
RE_RebirthConfirm.OnServerEvent:Connect(function(player)
	local ok,result = RebirthService.DoRebirth(player)
	if ok then
		RE_Notification:FireClient(player,"success","♻️ Reborn as "..result.title.."! "..result.multiplier.."x earnings!")
		syncData(player)
		BadgeService.CheckAll(player)
	else RE_Notification:FireClient(player,"error",result) end
end)

RE_DeletePet.OnServerEvent:Connect(function(player,uniqueId)
	local data = DataManager.GetData(player)
	if not data then return end
	PetService.UnequipPet(player,uniqueId)
	for i,pet in ipairs(data.Pets) do
		if pet.uniqueId==uniqueId then table.remove(data.Pets,i); break end
	end
	syncData(player)
end)

RE_BuyGamepass.OnServerEvent:Connect(function(player,gpKey)
	local ok, why = GamepassService.PromptPurchase(player,gpKey)
	if not ok then RE_Notification:FireClient(player,"info",why) end
end)

RF_GetLeaderboard.OnServerInvoke = function(player, category)
	return LeaderboardService.GetTop(category or "Coins", 10)
end

RE_BuyUpgrade.OnServerEvent:Connect(function(player,upgradeKey)
	local ok,result = UpgradeService.Buy(player,upgradeKey)
	if ok then
		RE_Notification:FireClient(player,"success","✅ "..result.label.." upgrade bought!")
		syncData(player)
	else
		RE_Notification:FireClient(player,"error",result)
	end
end)

-- ============================================================
-- QUESTS
-- ============================================================
RF_GetQuests.OnServerInvoke = function(player)
	return QuestService.GetAll(player)
end
-- Sound on or off. A boolean and nothing else: the value goes straight into
-- the save, so anything that is not true or false is dropped rather than
-- stored.
RE_SetMuted.OnServerEvent:Connect(function(player, muted)
	if type(muted) ~= "boolean" then return end
	local data = DataManager.GetData(player)
	if data then data.Muted = muted end
end)

RE_ClaimQuest.OnServerEvent:Connect(function(player, id)
	local ok, res = QuestService.Claim(player, id)
	if ok then
		RE_Notification:FireClient(player, "success", "🎉 Quest complete: " .. res.name .. "!")
		syncData(player)
		pcall(BadgeService.CheckAll, player)
	else
		RE_Notification:FireClient(player, "error", typeof(res) == "string" and res or "Cannot claim")
	end
end)

-- ============================================================
-- TRAVELING MERCHANT
-- ============================================================
RF_GetMerchant.OnServerInvoke = function(player)
	return MerchantService.GetState()
end
RE_BuyMerchant.OnServerEvent:Connect(function(player, index)
	local ok, res = MerchantService.Buy(player, index)
	if ok then
		RE_Notification:FireClient(player, "success", "🛒 Bought " .. tostring(res) .. "!")
		syncData(player); pcall(BadgeService.CheckAll, player)
	else
		RE_Notification:FireClient(player, "error", typeof(res) == "string" and res or "Cannot buy")
	end
end)

-- ============================================================
-- LUCKY SPIN WHEEL
-- ============================================================
RF_GetSpin.OnServerInvoke = function(player) return SpinService.GetState(player) end
RF_Spin.OnServerInvoke = function(player, useFree)
	local ok, res = SpinService.Spin(player, useFree == true)
	if ok then
		syncData(player)
		return { ok = true, index = res.index, prize = res.prize }
	else
		return { ok = false, err = typeof(res) == "string" and res or "Cannot spin" }
	end
end

-- ============================================================
-- PLAYTIME REWARDS
-- ============================================================
RF_GetPlaytime.OnServerInvoke = function(player) return PlaytimeService.GetState(player) end
RE_ClaimPlaytime.OnServerEvent:Connect(function(player, index)
	if type(index) ~= "number" then return end
	local ok, res = PlaytimeService.Claim(player, index)
	if ok then
		local msg = res.coins and ("+"..comma(res.coins).." coins") or res.gems and ("+"..res.gems.." gems") or "Boost!"
		RE_Notification:FireClient(player, "success", "\u{23F1}\u{FE0F} Playtime reward: "..msg)
		syncData(player)
	else
		RE_Notification:FireClient(player, "error", typeof(res)=="string" and res or "Cannot claim")
	end
end)

-- ============================================================
-- PET FUSION
-- ============================================================
RF_GetFusion.OnServerInvoke = function(player) return FusionService.GetFusable(player) end
RE_Fuse.OnServerEvent:Connect(function(player, name)
	if type(name) ~= "string" then return end
	local ok, res = FusionService.FuseByName(player, name)
	if ok then
		RE_Notification:FireClient(player, "success", "\u{1F9EC} Fused into a stronger "..name.."!")
		syncData(player)
	else
		RE_Notification:FireClient(player, "error", typeof(res)=="string" and res or "Cannot fuse")
	end
end)

-- ============================================================
-- BOOSTS
-- ============================================================
RF_GetBoosts.OnServerInvoke = function(player) return BoostService.GetState(player) end
RE_BuyBoost.OnServerEvent:Connect(function(player, id)
	local ok, res = BoostService.Buy(player, id)
	if ok then
		RE_Notification:FireClient(player, "success", "⚡ "..tostring(res).." active!")
		syncData(player)
	else
		RE_Notification:FireClient(player, "error", typeof(res)=="string" and res or "Cannot buy")
	end
end)

-- ============================================================
-- DAILY REWARD
-- ============================================================
RF_GetDaily.OnServerInvoke = function(player)
	return DailyService.GetState(player)
end
RE_ClaimDaily.OnServerEvent:Connect(function(player)
	local ok, res = DailyService.Claim(player)
	if ok then
		RE_Notification:FireClient(player, "success", "🎁 Daily reward claimed! (Day "..tostring(res)..")")
		syncData(player)
	else
		RE_Notification:FireClient(player, "error", typeof(res)=="string" and res or "Not ready")
	end
end)

-- ============================================================
-- PET QUALITY OF LIFE
-- ============================================================
RE_PetCmd.OnServerEvent:Connect(function(player, cmd, arg)
	if cmd == "equipBest" then
		PetService.EquipBest(player); syncData(player)
	elseif cmd == "deleteRarity" and arg then
		local n = PetService.DeleteByRarity(player, arg)
		RE_Notification:FireClient(player, "info", "🗑️ Deleted " .. n .. " " .. arg .. " pets")
		syncData(player)
	elseif cmd == "lock" and arg then
		PetService.ToggleLock(player, arg); syncData(player)
	end
end)

-- ============================================================
-- CODES
-- ============================================================
RE_RedeemCode.OnServerEvent:Connect(function(player, code)
	local ok, res = CodeService.Redeem(player, code)
	if ok then
		RE_Notification:FireClient(player, "success", "🎁 "..tostring(res).." redeemed!")
		syncData(player)
	else
		RE_Notification:FireClient(player, "error", typeof(res) == "string" and res or "Cannot redeem")
	end
end)

-- ============================================================
-- TRADING
-- ============================================================
TradeService.Init(
	function(player, state) RE_TradeState:FireClient(player, state) end,
	function(player, fromName, fromId) RE_TradeReq:FireClient(player, fromName, fromId) end
)
TradeService.onComplete = function(p)
	syncData(p); RE_Notification:FireClient(p, "success", "✅ Trade complete!")
end
RE_Trade.OnServerEvent:Connect(function(player, cmd, a)
	if cmd == "request" then TradeService.Request(player, a)
	elseif cmd == "respond" then TradeService.Respond(player, a)
	elseif cmd == "add" then TradeService.Add(player, a)
	elseif cmd == "remove" then TradeService.Remove(player, a)
	elseif cmd == "accept" then TradeService.Accept(player, a)
	elseif cmd == "cancel" then TradeService.Cancel(player)
	end
end)

-- ============================================================
-- LIMITED-TIME EVENTS
-- ============================================================
RF_GetEvent.OnServerInvoke = function(player)
	return EventService.GetState(player)
end
RE_BuyEvent.OnServerEvent:Connect(function(player, index)
	local ok, res = EventService.Buy(player, index)
	if ok then
		RE_Notification:FireClient(player, "success", "🎟️ Bought " .. tostring(res) .. "!")
		syncData(player); pcall(BadgeService.CheckAll, player)
	else
		RE_Notification:FireClient(player, "error", typeof(res) == "string" and res or "Cannot buy")
	end
end)

-- ============================================================
-- ADMIN / DEV PANEL  (server-authoritative — UI can't be trusted)
-- ============================================================
local AUTHORIZED = {
	-- [123456789] = true,   -- add extra admin UserIds here
}
local function isAdmin(player)
	if RunService:IsStudio() then return true end                 -- you, while testing
	if game.CreatorId ~= 0 and player.UserId == game.CreatorId then return true end
	return AUTHORIZED[player.UserId] == true
end

local ADMIN_AREA_POS = {
	Meadow=Vector3.new(0,6,65), Forest=Vector3.new(145,6,0), Desert=Vector3.new(275,6,0),
	Volcano=Vector3.new(405,6,0), Space=Vector3.new(535,6,0),
}
local ADMIN_GP = {"GP_2xCoins","GP_AutoCollect","GP_VIP","GP_PetSlots","GP_LuckyBoost"}

RF_Admin.OnServerInvoke = function(player, action, arg)
	if action == "check" then return isAdmin(player) end
	if not isAdmin(player) then return false end          -- hard server gate
	arg = arg or {}
	-- Resolve target player (blank = yourself). Matches by name prefix / display name.
	local target = player
	if arg.target and arg.target ~= "" then
		local q = string.lower(arg.target)
		for _, p in ipairs(Players:GetPlayers()) do
			if string.sub(string.lower(p.Name), 1, #q) == q or string.lower(p.DisplayName) == q then
				target = p; break
			end
		end
	end
	local data = DataManager.GetData(target)

	if action == "give" and data then
		if arg.coins then
			data.Coins = math.max(0, (data.Coins or 0) + arg.coins)
			if arg.coins > 0 then data.TotalCoinsEarned = (data.TotalCoinsEarned or 0) + arg.coins end
		end
		if arg.gems then data.Gems = math.max(0, (data.Gems or 0) + arg.gems) end
		syncData(target)
	elseif action == "givePet" and data and arg.name then
		PetService.GrantPet(target, { name=arg.name, rarity=arg.rarity or "Common" }, true)
		syncData(target); pcall(BadgeService.CheckAll, target)
	elseif action == "unlockAll" and data then
		data.UnlockedAreas = {}
		for _, a in ipairs(GameConfig.Areas) do table.insert(data.UnlockedAreas, a.id) end
		syncData(target)
	elseif action == "maxUpgrades" and data then
		data.Upgrades = data.Upgrades or {}
		for _, u in ipairs(GameConfig.Upgrades) do data.Upgrades[u.key] = #u.levels end
		syncData(target)
	elseif action == "toggleGamepass" and data and arg.key then
		data[arg.key] = not data[arg.key]; syncData(target)
	elseif action == "godMode" and data then
		data.Coins = 1e9; data.Gems = 1e6
		data.TotalCoinsEarned = math.max(data.TotalCoinsEarned or 0, 1e9)
		data.UnlockedAreas = {}
		for _, a in ipairs(GameConfig.Areas) do table.insert(data.UnlockedAreas, a.id) end
		data.Upgrades = data.Upgrades or {}
		for _, u in ipairs(GameConfig.Upgrades) do data.Upgrades[u.key] = #u.levels end
		for _, k in ipairs(ADMIN_GP) do data[k] = true end
		syncData(target)
	elseif action == "teleport" and arg.area then
		local pos, char = ADMIN_AREA_POS[arg.area], target.Character
		if pos and char and char:FindFirstChild("HumanoidRootPart") then char:PivotTo(CFrame.new(pos)) end
	elseif action == "bringPlayers" then
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= player and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
					p.Character:PivotTo(hrp.CFrame * CFrame.new(math.random(-6,6), 0, math.random(4,9)))
				end
			end
		end
	elseif action == "resetData" and data then
		for k, v in pairs(GameConfig.DefaultData) do
			if typeof(v) == "table" then
				local t = {}; for kk, vv in pairs(v) do t[kk] = vv end; data[k] = t
			else data[k] = v end
		end
		data.Pets = {}; data.EquippedPets = {}; data.UnlockedAreas = { "Meadow" }
		pcall(PetService.DespawnAllPets, target); syncData(target)
	elseif action == "broadcast" and arg.msg then
		RE_Notification:FireAllClients("info", "📢 " .. tostring(arg.msg))
	elseif action == "kick" and arg.userId then
		local t = Players:GetPlayerByUserId(arg.userId)
		if t and t ~= player then t:Kick("Kicked by an admin") end
	elseif action == "stats" then
		local out = {}
		for _, p in ipairs(Players:GetPlayers()) do
			local d = DataManager.GetData(p)
			if d then table.insert(out, {name=p.Name, userId=p.UserId, coins=d.Coins or 0, gems=d.Gems or 0, pets=#(d.Pets or {}), rebirths=d.Rebirths or 0}) end
		end
		return out
	elseif action == "claimQuests" then
		QuestService.ClaimAll(target); syncData(target)
	elseif action == "resetQuests" then
		QuestService.Reset(target); syncData(target)
	elseif action == "spawnMerchant" then
		MerchantService.ForceSpawn()
		RE_Notification:FireAllClients("info", "🛒 The Traveling Merchant has arrived!")
	elseif action == "despawnMerchant" then
		MerchantService.ForceDespawn()
	elseif action == "startEvent" and arg.id then
		if EventService.Start(arg.id) then
			local d = GameConfig.Events[arg.id]
			RE_Notification:FireAllClients("success", "🎉 Event started: " .. (d and d.name or arg.id) .. "!")
		end
	elseif action == "stopEvent" then
		EventService.Stop()
		RE_Notification:FireAllClients("info", "The event has ended.")
	elseif action == "addRebirth" and data then
		local maxR = #GameConfig.Rebirths
		data.Rebirths = math.clamp((data.Rebirths or 0) + (arg.n or 1), 0, maxR)
		data.RebirthMultiplier = (data.Rebirths > 0 and GameConfig.Rebirths[data.Rebirths].multiplier) or 1.0
		syncData(target); pcall(BadgeService.CheckAll, target)
	elseif action == "giveAllPets" and data then
		for _, pet in ipairs(GameConfig.Pets) do
			PetService.GrantPet(player, { name=pet.name, rarity=pet.rarity }, true)
		end
		syncData(target); pcall(BadgeService.CheckAll, target)
	elseif action == "clearPets" and data then
		data.Pets = {}; data.EquippedPets = {}
		pcall(PetService.DespawnAllPets, target); syncData(target)
	elseif action == "giveBoost" and data then
		data.ActiveBoosts = data.ActiveBoosts or {}
		local id, dur = arg.id or "x5_10", 600
		for _, b in ipairs(GameConfig.Boosts or {}) do if b.id == id then dur = b.duration end end
		data.ActiveBoosts[id] = math.max(os.time(), data.ActiveBoosts[id] or 0) + dur
		syncData(target)
	elseif action == "resetDaily" and data then
		data.LastDailyClaim = 0; syncData(target)
	elseif action == "giveTokens" and data then
		data.EventTokens = (data.EventTokens or 0) + (arg.n or 1000); syncData(target)
	elseif action == "speed" then
		local char = target.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = math.clamp(arg.v or 16, 0, 500) end
	elseif action == "kickName" and target ~= player then
		target:Kick("Kicked by an admin")
	end
	return true
end

-- ============================================================
-- INIT
-- ============================================================
-- Move the imported pet-model pack into ReplicatedStorage if it was left in
-- Workspace. PROTECTED — this must never be able to kill the rest of init.
pcall(function()
	local wsPM = workspace:FindFirstChild("PetMeshes") or workspace:FindFirstChild("PetMashes")
	if wsPM then
		local rsPM = ReplicatedStorage:FindFirstChild("PetMeshes")
		if rsPM and rsPM ~= wsPM then
			for _, m in ipairs(wsPM:GetChildren()) do m.Parent = rsPM end
			wsPM:Destroy()
		else
			wsPM.Name = "PetMeshes"; wsPM.Parent = ReplicatedStorage
		end
	end
end)

setupLighting()
PetService.Init()
CurrencyService.Init()

-- ============================================================
-- BUILD THE MAP, OR KEEP THE ONE YOU MADE
-- ============================================================
-- If the place has a StarPetsMap folder flagged StarPetsBaked, the map is a
-- BUILD — somebody laid it out in Studio and saved it — and rebuilding would
-- throw their work away every single time a server started. That is the exact
-- failure this exists to end: edits made during Play vanished on Stop, and
-- there was nothing to edit outside Play because the map was only ever code.
--
-- On a baked map nothing is generated. Behaviour is re-attached from the
-- attributes the builder stamped, so clicking an egg still hatches it even
-- though not one line of the builder ran.
local baked = MapPersist.Boot()
local mapOk, mapErr = true, nil
local rewired = 0

-- Yours, and never touched by any of this, baked or not.
pcall(MapPersist.EnsureCustomFolder)

if baked then
	local ok, n = pcall(MapPersist.Rewire)
	if ok then rewired = n or 0 else mapOk, mapErr = false, n end
	print(("[StarPets] using YOUR baked map — %d interactive part(s) re-armed, "
		.. "nothing rebuilt."):format(rewired))
else
	-- Replace a previously generated map rather than laying a new one on top.
	pcall(MapPersist.ResetWorld)
	mapOk, mapErr = pcall(buildMap)
	if not mapOk then warn("[StarPets] buildMap error: " .. tostring(mapErr)) end
end

-- ============================================================
-- COINS ON THE GROUND
-- ============================================================
-- Seeded here, once the map exists — built or baked — and never by the map
-- builder: they are not part of the map, and a baked map is exactly the case
-- where the builder does not run. After it, because each coin is dropped onto
-- whatever ground is really under it.
--
-- This used to live in the builder, next to the old leaderboard board, and
-- the commit that removed the board took these lines with it. From then on
-- there was not one coin in any world: the onboarding banner that says "walk
-- over the coins on the ground" pointed at nothing, the Coin Bonus upgrade
-- ("multiply coins earned from orbs") bought nothing, and Auto Collect had
-- nothing to collect. check_firstplay walks a new player into them now.
do
	local ORIGINS = {
		Meadow  = Vector3.new(0, 1, 65),
		Forest  = Vector3.new(145, 1, 0),
		Desert  = Vector3.new(275, 1, 0),
		Volcano = Vector3.new(405, 1, 0),
		Space   = Vector3.new(535, 1, 0),
	}
	for areaId, origin in pairs(ORIGINS) do
		CurrencyService.SeedArea(areaId, origin, 45)
	end
	CurrencyService.SetupOrbTouches()
end

-- Say how to keep a map you build, IN STUDIO, at the moment it is relevant —
-- not once in a document nobody has open. Nobody should have to be told twice
-- that Play-mode edits are discarded; the game itself is the right place to
-- say it, and it costs a player nothing because it never runs for them.
if game:GetService("RunService"):IsStudio() and not baked then
	print(table.concat({
		"",
		"[StarPets] THIS MAP IS GENERATED. Anything you move or add while you",
		"           are testing is DISCARDED when you press Stop — that is",
		"           Studio, not a bug, and it is why your edits vanished.",
		"",
		"           TO KEEP A MAP YOU BUILD, do this once:",
		"             1. While still running, click StarPetsMap in the Explorer",
		"                and press Ctrl+C.",
		"             2. Press Stop.",
		"             3. Click Workspace, press Ctrl+V.",
		"             4. Paste this into the Command Bar and press Enter:",
		"                workspace.StarPetsMap:SetAttribute(\"StarPetsBaked\", true)",
		"             5. Save the place (Ctrl+S).",
		"",
		"           From then on the map is YOURS: ordinary parts you can drag,",
		"           delete and add to in edit mode, saved with the place, and",
		"           never rebuilt over. Every egg and gate still works, because",
		"           each one carries its own SPAction attribute that the server",
		"           re-arms on startup.",
		"",
		"           (Or build in workspace.MyBuild, which is never touched",
		"            either way.)",
		"",
	}, "\n"))
end
BadgeService.SetRemote(RE_BadgeEarned)
CurrencyService.StartPassiveIncome(PetService)
MerchantService.Start(function()
	RE_Notification:FireAllClients("info", "🛒 The Traveling Merchant has arrived — limited stock!")
end)
EventService.Init()
print("[MysticPets] Server ready!")
