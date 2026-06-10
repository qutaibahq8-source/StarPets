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
local GameConfig           = require(game.ReplicatedStorage.Shared.GameConfig)

-- ============================================================
-- REMOTES
-- ============================================================
local Remotes = Instance.new("Folder")
Remotes.Name  = "Remotes"
Remotes.Parent = game.ReplicatedStorage

local function makeEvent(name)
	local e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = Remotes; return e
end
local function makeFunction(name)
	local f = Instance.new("RemoteFunction"); f.Name = name; f.Parent = Remotes; return f
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
local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true; p.CastShadow = false
	for k,v in pairs(props) do p[k] = v end
	p.Parent = workspace; return p
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

local function decorateBiome(id, cx, baseY)
	local function rx() return cx + math.random(-56,56) end
	local function rz() return math.random(-88,88) end
	for _=1,16 do flower(rx(),rz(),baseY) end
	if id=="Forest" then
		for i=1,18 do tree(rx(),rz(),baseY,Color3.fromRGB(70,45,25),Color3.fromRGB(25,90,30),0.8+math.random()*0.7) end
		for i=1,12 do rock(rx(),rz(),baseY,Color3.fromRGB(95,100,105),0.9) end
	elseif id=="Desert" then
		for i=1,12 do
			local h=5+math.random()*4
			part({Name="Cactus",Size=Vector3.new(1.6,h,1.6),Position=Vector3.new(rx(),baseY+h/2,rz()),
				Color=Color3.fromRGB(55,120,60),Material=Enum.Material.Grass,CanCollide=false})
		end
		for i=1,16 do rock(rx(),rz(),baseY,Color3.fromRGB(205,170,95),1.1) end
	elseif id=="Volcano" then
		for i=1,18 do rock(rx(),rz(),baseY,Color3.fromRGB(38,26,22),1.2) end
		for i=1,6 do
			local d=8+math.random()*7
			part({Name="LavaPool",Shape=Enum.PartType.Cylinder,Size=Vector3.new(0.4,d,d),
				Position=Vector3.new(rx(),baseY+0.25,rz()),Color=Color3.fromRGB(255,90,0),
				Material=Enum.Material.Neon,Orientation=Vector3.new(0,0,90),CanCollide=false})
		end
	elseif id=="Space" then
		for i=1,22 do
			local s=2+math.random()*3
			local c=part({Name="Star",Shape=Enum.PartType.Ball,Size=Vector3.new(s,s,s),
				Position=Vector3.new(rx(),baseY+math.random(5,26),rz()),
				Color=Color3.fromRGB(150,180,255),Material=Enum.Material.Neon,CanCollide=false})
			glow(c,Color3.fromRGB(120,160,255),1)
		end
	end
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
	sp.Transparency=1; sp.Anchored=true; sp.Parent=workspace

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

	-- Egg stands (4 eggs spread 26 studs apart)
	local eggDefs={{id="StarterEgg"},{id="CoolEgg"},{id="RareEgg"},{id="LegendaryEgg"}}
	for i,eDef in ipairs(eggDefs) do
		local eggCfg=nil
		for _,e in ipairs(GameConfig.Eggs) do if e.id==eDef.id then eggCfg=e break end end
		if not eggCfg then continue end
		local x=-39+(i-1)*26

		part({Name="EggBase_"..eDef.id,Size=Vector3.new(7,0.5,7),
			Position=Vector3.new(x,-0.75,-90),Color=Color3.fromRGB(32,28,52),Material=Enum.Material.SmoothPlastic})
		local rng=part({Name="EggRing_"..eDef.id,Size=Vector3.new(7.4,0.3,7.4),
			Position=Vector3.new(x,-0.3,-90),Color=eggCfg.color,Material=Enum.Material.SmoothPlastic,CanCollide=false})
		part({Name="EggCol_"..eDef.id,Size=Vector3.new(2.8,2.2,2.8),
			Position=Vector3.new(x,0.6,-90),Color=Color3.fromRGB(120,110,135),Material=Enum.Material.Slate})

		-- Actual egg: smooth tapered oval (no glow), with spots welded so they bob with it
		local egg=part({Name="Egg_"..eDef.id,Shape=Enum.PartType.Ball,
			Size=Vector3.new(3,4.2,3),Position=Vector3.new(x,3.8,-90),
			Color=eggCfg.color,Material=Enum.Material.SmoothPlastic,CanCollide=false})
		for _,off in ipairs({Vector3.new(0.55,0.5,0.95),Vector3.new(-0.7,-0.2,0.85),Vector3.new(0.15,1.3,0.7)}) do
			local spot=part({Name="EggSpot",Shape=Enum.PartType.Ball,Size=Vector3.new(0.95,0.95,0.5),
				Position=Vector3.new(x,3.8,-90)+off,Color=Color3.fromRGB(255,255,255),Material=Enum.Material.SmoothPlastic,CanCollide=false})
			spot.Anchored=false; spot.CanQuery=false  -- don't block clicks on the egg
			local w=Instance.new("WeldConstraint"); w.Part0=egg; w.Part1=spot; w.Parent=egg
		end

		local costText = eggCfg.id=="StarterEgg"
			and ("🆓 FREE → then 💰 "..(eggCfg.costAfterFirst or 150))
			or ("💰 "..eggCfg.cost.." "..eggCfg.currency)
		billboard(egg,eggCfg.name,Color3.new(1,1,1),costText,Color3.fromRGB(255,215,0),UDim2.new(0,180,0,72))

		local sp2=Vector3.new(x,3.8,-90)
		task.spawn(function()
			local t=0
			while egg and egg.Parent do
				t=t+task.wait(0.03)
				egg.CFrame=CFrame.new(sp2+Vector3.new(0,math.sin(t*1.5)*0.5,0))*CFrame.Angles(0,t*0.7,math.sin(t*0.4)*0.08)
			end
		end)
		local cd=Instance.new("ClickDetector"); cd.MaxActivationDistance=32; cd.Parent=egg
		cd.MouseClick:Connect(function(player) RE_HatchEgg:FireClient(player,eDef.id) end)
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
	local fp = Vector3.new(0, 0, 26)
	local STONE = Color3.fromRGB(150,145,135)
	local WATER = Color3.fromRGB(90,170,230)
	-- stone tiers
	part({Name="FtnBase", Size=Vector3.new(1.6,16,16),Position=fp+Vector3.new(0,0.8,0),Orientation=Vector3.new(0,0,90),Color=STONE,Material=Enum.Material.Slate})
	part({Name="FtnRim",  Size=Vector3.new(1.4,16.8,16.8),Position=fp+Vector3.new(0,1.5,0),Orientation=Vector3.new(0,0,90),Color=Color3.fromRGB(172,167,158),Material=Enum.Material.Slate,CanCollide=false})
	part({Name="FtnCol",  Size=Vector3.new(3.6,3,3),Position=fp+Vector3.new(0,3.2,0),Orientation=Vector3.new(0,0,90),Color=STONE,Material=Enum.Material.Slate,CanCollide=false})
	part({Name="FtnBowl", Size=Vector3.new(0.7,7,7),Position=fp+Vector3.new(0,4.9,0),Orientation=Vector3.new(0,0,90),Color=STONE,Material=Enum.Material.Slate,CanCollide=false})
	part({Name="FtnSpout",Size=Vector3.new(2.2,0.8,0.8),Position=fp+Vector3.new(0,6.2,0),Orientation=Vector3.new(0,0,90),Color=STONE,Material=Enum.Material.Slate,CanCollide=false})
	-- glassy, reflective water pools (look like water, not plastic discs)
	local wL=part({Name="FtnWaterL",Size=Vector3.new(0.35,14,14),Position=fp+Vector3.new(0,1.7,0),Orientation=Vector3.new(0,0,90),Color=WATER,Material=Enum.Material.Glass,Transparency=0.4,CanCollide=false}); wL.Reflectance=0.25
	local wU=part({Name="FtnWaterU",Size=Vector3.new(0.3,6,6),Position=fp+Vector3.new(0,5.3,0),Orientation=Vector3.new(0,0,90),Color=WATER,Material=Enum.Material.Glass,Transparency=0.4,CanCollide=false}); wU.Reflectance=0.25
	-- water spray that arcs up from the top and falls (a real fountain jet)
	local sprayA=part({Name="FtnSpray",Size=Vector3.new(0.4,0.4,0.4),Position=fp+Vector3.new(0,6.8,0),Transparency=1,CanCollide=false})
	local att=Instance.new("Attachment"); att.Parent=sprayA
	local pe=Instance.new("ParticleEmitter"); pe.Parent=att
	pe.Color=ColorSequence.new(Color3.fromRGB(160,215,255),Color3.fromRGB(225,240,255))
	pe.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0.5),NumberSequenceKeypoint.new(1,0.15)})
	pe.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.25),NumberSequenceKeypoint.new(1,1)})
	pe.Lifetime=NumberRange.new(1.0,1.5); pe.Rate=45; pe.Speed=NumberRange.new(9,12)
	pe.SpreadAngle=Vector2.new(16,16); pe.Acceleration=Vector3.new(0,-32,0)
	pe.EmissionDirection=Enum.NormalId.Top; pe.LightEmission=0.25; pe.Rotation=NumberRange.new(0,360)

	-- ---- HUB DECOR: lamp posts, hedges, benches ----
	local function lamp(x, z)
		part({Name="LampPost",Size=Vector3.new(0.5,7,0.5),Position=Vector3.new(x,3.5,z),Color=Color3.fromRGB(38,38,46),Material=Enum.Material.Metal,CanCollide=false})
		part({Name="LampArm",Size=Vector3.new(1.6,0.4,0.4),Position=Vector3.new(x,6.9,z),Color=Color3.fromRGB(38,38,46),Material=Enum.Material.Metal,CanCollide=false})
		part({Name="LampHead",Shape=Enum.PartType.Ball,Size=Vector3.new(1.2,1.2,1.2),Position=Vector3.new(x,6.6,z),Color=Color3.fromRGB(255,238,180),Material=Enum.Material.Neon,CanCollide=false})
	end
	for _, p in ipairs({{26,26},{-26,26},{26,-26},{-26,-26},{30,0},{-30,0}}) do lamp(p[1],p[2]) end
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

	-- ---- BIOMES (each 130 wide x 190 deep, 130 studs apart) ----
	local AreaBarriers = Instance.new("Folder")
	AreaBarriers.Name = "AreaBarriers"; AreaBarriers.Parent = workspace
	local biomes={
		{id="Forest",  cx=145, col=Color3.fromRGB(22,85,22)},
		{id="Desert",  cx=275, col=Color3.fromRGB(160,132,35)},
		{id="Volcano", cx=405, col=Color3.fromRGB(120,22,0)},
		{id="Space",   cx=535, col=Color3.fromRGB(8,8,38)},
	}
	for _,b in ipairs(biomes) do
		-- Biome floor (130 wide x 190 deep = fits 4-5 players comfortably)
		part({Name="Biome_"..b.id,Size=Vector3.new(130,2,190),
			Position=Vector3.new(b.cx,-1,0),Color=b.col,Material=Enum.Material.SmoothPlastic})
		decorateBiome(b.id, b.cx, 0)

		local areaConfig=nil
		for _,a in ipairs(GameConfig.Areas) do if a.id==b.id then areaConfig=a break end end
		if not areaConfig then continue end

		-- Big world-name sign floating over the middle of the biome
		local nameAnchor=part({Name="BiomeName_"..b.id,Size=Vector3.new(1,1,1),
			Position=Vector3.new(b.cx,30,0),Transparency=1,CanCollide=false})
		billboard(nameAnchor,areaConfig.name,Color3.fromRGB(255,255,255),
			areaConfig.description,Color3.fromRGB(210,210,235),UDim2.new(0,440,0,130),140)

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
		cd.MouseClick:Connect(function(player) RE_BuyArea:FireClient(player,b.id) end)
		-- requirement sign on the wall
		local sign=Instance.new("BillboardGui")
		sign.Name="WallSign"; sign.Size=UDim2.new(0,640,0,240); sign.StudsOffset=Vector3.new(0,20,0)
		sign.MaxDistance=400; sign.Adornee=barrier; sign.Parent=barrier
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
	-- PHYSICAL SHOP BUILDING (east side of spawn, x=65)
	-- ============================================================
	local shopPos = Vector3.new(-55, 0, 34)  -- next to the rebirth machine (west of spawn)

	-- Shop floor
	part({Name="ShopFloor",Size=Vector3.new(22,2,22),Position=shopPos+Vector3.new(0,-1,0),
		Color=Color3.fromRGB(45,38,68),Material=Enum.Material.SmoothPlastic})
	-- Walls
	part({Name="ShopWallF",Size=Vector3.new(22,10,1),Position=shopPos+Vector3.new(0,4,-11),
		Color=Color3.fromRGB(38,32,58),Material=Enum.Material.SmoothPlastic})
	part({Name="ShopWallB",Size=Vector3.new(22,10,1),Position=shopPos+Vector3.new(0,4,11),
		Color=Color3.fromRGB(38,32,58),Material=Enum.Material.SmoothPlastic})
	part({Name="ShopWallL",Size=Vector3.new(1,10,22),Position=shopPos+Vector3.new(-11,4,0),
		Color=Color3.fromRGB(38,32,58),Material=Enum.Material.SmoothPlastic})
	part({Name="ShopWallR",Size=Vector3.new(1,10,22),Position=shopPos+Vector3.new(11,4,0),
		Color=Color3.fromRGB(38,32,58),Material=Enum.Material.SmoothPlastic})
	-- Roof
	local roof=part({Name="ShopRoof",Size=Vector3.new(24,1,24),Position=shopPos+Vector3.new(0,9.5,0),
		Color=Color3.fromRGB(80,50,130),Material=Enum.Material.SmoothPlastic})
	-- Roof neon trim
	local roofNeon=part({Name="ShopRoofNeon",Size=Vector3.new(24.5,0.5,24.5),Position=shopPos+Vector3.new(0,10.1,0),
		Color=Color3.fromRGB(160,80,255),Material=Enum.Material.Neon,CanCollide=false})
	glow(roofNeon,Color3.fromRGB(160,80,255),2)
	-- Door opening (gap in front wall left side)
	-- Sign above door
	local shopSign=part({Name="ShopSign",Size=Vector3.new(1,1,1),Position=shopPos+Vector3.new(0,12,-11),
		Transparency=1,CanCollide=false})
	billboard(shopSign,"🛒  UPGRADE SHOP",Color3.fromRGB(255,180,50),"Click inside to upgrade!",
		Color3.fromRGB(200,200,255),UDim2.new(0,240,0,70))

	-- Interior upgrade pads (4 colored circles on the floor)
	local upgradeColors = {
		SpeedBoost = Color3.fromRGB(255,200,0),
		JumpBoost  = Color3.fromRGB(100,200,255),
		LuckyCharm = Color3.fromRGB(50,220,80),
		CoinBonus  = Color3.fromRGB(255,140,0),
	}
	local upgradePositions = {
		Vector3.new(-4,0,-4), Vector3.new(4,0,-4),
		Vector3.new(-4,0,4),  Vector3.new(4,0,4),
	}
	for i, upg in ipairs(GameConfig.Upgrades) do
		local pos = shopPos + upgradePositions[i] + Vector3.new(0,-0.9,0)
		local col = upgradeColors[upg.key] or Color3.fromRGB(200,200,200)
		local pad = part({Name="UpgPad_"..upg.key,Size=Vector3.new(5,0.3,5),Position=pos,
			Color=col,Material=Enum.Material.Neon,CanCollide=false})
		glow(pad,col,1.5)

		-- Floating icon above pad
		local iconAnchor=part({Name="UpgIcon_"..upg.key,Size=Vector3.new(1,1,1),
			Position=pos+Vector3.new(0,3,0),Transparency=1,CanCollide=false})
		local currentLevelCost = upg.levels[1].cost
		billboard(iconAnchor,upg.icon.." "..upg.name,col,
			"Lvl 1: 💰 "..currentLevelCost,Color3.fromRGB(220,220,220),UDim2.new(0,180,0,65))

		-- Click to buy
		local cd=Instance.new("ClickDetector"); cd.MaxActivationDistance=16; cd.Parent=pad
		cd.MouseClick:Connect(function(player)
			-- Fire to client to open the upgrade panel
			RE_HatchEgg:FireClient(player, "__upgrade__"..upg.key)
		end)
	end

	-- ---- BOUNDARY WALLS (solid + invisible extension so no climbing out) ----
	local wallColor = Color3.fromRGB(46,104,46)    -- hedge green (was gray concrete slab)
	local wallH = 25

	local function buildWall(name, size, pos)
		part({Name=name,Size=size,Position=pos,Color=wallColor,Material=Enum.Material.Grass})
		-- Invisible tall extension above (blocks jumping over)
		part({Name=name.."Ext",Size=Vector3.new(size.X,40,size.Z),
			Position=pos+Vector3.new(0,30,0),Transparency=1,CanCollide=true})
		-- Bushy hedge top so it reads as a hedge, not a flat wall
		local alongX = size.X > size.Z
		local len = alongX and size.X or size.Z
		local n = math.max(1, math.floor(len/16))
		for i=0,n do
			local t = -len/2 + (i/n)*len
			local bpos = alongX and Vector3.new(pos.X+t, pos.Y+wallH/2, pos.Z)
			                     or Vector3.new(pos.X, pos.Y+wallH/2, pos.Z+t)
			part({Name="Hedge",Shape=Enum.PartType.Ball,Size=Vector3.new(7,6,7),
				Position=bpos,Color=Color3.fromRGB(56,122,56),Material=Enum.Material.Grass,CanCollide=false})
		end
	end

	buildWall("WallN", Vector3.new(720,wallH,4), Vector3.new(257,wallH/2-1, 126))
	buildWall("WallS", Vector3.new(720,wallH,4), Vector3.new(257,wallH/2-1,-116))
	buildWall("WallW", Vector3.new(4,wallH,246), Vector3.new(-91,wallH/2-1,  5))
	buildWall("WallE", Vector3.new(4,wallH,246), Vector3.new(606,wallH/2-1,  5))

	-- ============================================================
	-- 🗝️ SECRET SPOT  (hidden — tell nobody)
	-- Location: northwest corner, tight against north wall at z=122, x=-82
	-- Looks like a plain dark rock, tiny glow only visible up close
	-- ============================================================
	local secretPos = Vector3.new(-82, 0.5, 118)

	-- The "rock" — blends with wall color
	local secretChest=part({Name="SecretChest",Size=Vector3.new(2.2,2.2,2.2),
		Position=secretPos,Color=Color3.fromRGB(28,22,44),Material=Enum.Material.SmoothPlastic})
	-- Very faint glow — only visible when you're within 8 studs
	local secretLight=Instance.new("PointLight")
	secretLight.Color=Color3.fromRGB(255,215,0)
	secretLight.Brightness=0.15  -- barely visible
	secretLight.Range=6
	secretLight.Parent=secretChest

	-- Click detector with very short range — must be RIGHT next to it
	local secretCD=Instance.new("ClickDetector")
	secretCD.MaxActivationDistance=7
	secretCD.Parent=secretChest
	secretCD.MouseClick:Connect(function(player)
		local data=DataManager.GetData(player)
		if not data then return end
		if data.FoundSecret then
			RE_Notification:FireClient(player,"info","You already found this secret! 🗝️")
			return
		end
		data.FoundSecret=true
		local reward=GameConfig.SecretReward
		data.Coins=data.Coins+(reward.coins or 0)
		data.Gems=data.Gems+(reward.gems or 0)
		DataManager.IncrementData(player,"TotalCoinsEarned",reward.coins or 0)
		RE_SecretFound:FireClient(player,reward)
		BadgeService.Grant(player,"secret_finder")
		syncData(player)
		print("[Secret] "..player.Name.." found the secret spot!")
	end)

	-- ============================================================
	-- PHYSICAL LEADERBOARD BOARD (left side of spawn, z=-35)
	-- ============================================================
	local boardPos = Vector3.new(-55, 0, -35)

	-- Board backing
	part({Name="LBBase",Size=Vector3.new(28,1,14),Position=boardPos+Vector3.new(0,-0.5,0),
		Color=Color3.fromRGB(25,18,45),Material=Enum.Material.SmoothPlastic})
	local boardBack=part({Name="LBBack",Size=Vector3.new(28,20,1),Position=boardPos+Vector3.new(0,10,-7),
		Color=Color3.fromRGB(20,14,38),Material=Enum.Material.SmoothPlastic})
	-- Neon frame
	local lbFrame=part({Name="LBFrame",Size=Vector3.new(30,22,0.5),Position=boardPos+Vector3.new(0,11,-7.3),
		Color=Color3.fromRGB(255,215,0),Material=Enum.Material.Neon,CanCollide=false})
	glow(lbFrame,Color3.fromRGB(255,215,0),2)

	-- Title sign on board
	local lbTitleAnchor=part({Name="LBTitle",Size=Vector3.new(1,1,1),
		Position=boardPos+Vector3.new(0,21,-6),Transparency=1,CanCollide=false})
	billboard(lbTitleAnchor,"🏆  TOP PLAYERS",Color3.fromRGB(255,215,0),
		"Updates every 90s",Color3.fromRGB(180,180,200),UDim2.new(0,260,0,60))

	-- Clickable board to open leaderboard UI
	local lbClick=Instance.new("ClickDetector"); lbClick.MaxActivationDistance=30; lbClick.Parent=boardBack
	lbClick.MouseClick:Connect(function(player)
		RE_TitleUpdate:FireClient(player,"__openleaderboard__")
	end)

	-- Live leaderboard text painted FLAT on the board face (SurfaceGui)
	local lbSurface = Instance.new("SurfaceGui")
	lbSurface.Name        = "LBSurface"
	lbSurface.Face        = Enum.NormalId.Front
	lbSurface.SizingMode   = Enum.SurfaceGuiSizingMode.FixedSize
	lbSurface.CanvasSize   = Vector2.new(560, 400)
	lbSurface.LightInfluence = 0
	lbSurface.Adornee     = boardBack
	lbSurface.Parent      = boardBack

	local lbPad = Instance.new("UIPadding", lbSurface)
	lbPad.PaddingTop=UDim.new(0,18); lbPad.PaddingBottom=UDim.new(0,18)
	lbPad.PaddingLeft=UDim.new(0,24); lbPad.PaddingRight=UDim.new(0,24)
	local lbList = Instance.new("UIListLayout", lbSurface)
	lbList.SortOrder=Enum.SortOrder.LayoutOrder
	lbList.Padding=UDim.new(0,12)
	lbList.VerticalAlignment=Enum.VerticalAlignment.Center

	local lbRows = {}
	for i=1,5 do
		local lbl=Instance.new("TextLabel")
		lbl.Size=UDim2.new(1,0,0,60); lbl.BackgroundTransparency=1
		lbl.Text="Loading..."; lbl.TextColor3=Color3.fromRGB(200,200,200)
		lbl.TextScaled=true; lbl.Font=Enum.Font.GothamBold
		lbl.TextXAlignment=Enum.TextXAlignment.Left
		lbl.TextStrokeTransparency=0.4; lbl.TextStrokeColor3=Color3.new(0,0,0)
		lbl.LayoutOrder=i; lbl.Parent=lbSurface
		table.insert(lbRows, lbl)
	end

	-- Update board every 90s
	task.spawn(function()
		local medals = {"🥇","🥈","🥉","4.","5."}
		while true do
			task.wait(5) -- initial delay for DataStore
			local ok, entries = pcall(function()
				return LeaderboardService.GetTop("Coins", 5)
			end)
			if ok then
				for i,row in ipairs(lbRows) do
					local e = entries[i]
					if e then
						local name = e.name:sub(1,14)
						row.Text = medals[i].." "..name.." — 💰 "..tostring(e.score)
						local rColors={Color3.fromRGB(255,215,0),Color3.fromRGB(192,192,192),Color3.fromRGB(205,127,50)}
						row.TextColor3 = rColors[i] or Color3.fromRGB(200,200,200)
					else
						row.Text = medals[i].." —"
					end
				end
			end
			task.wait(85)
		end
	end)

	-- ---- ORB SEEDING (100 per area for 20 players) ----
	local origins={
		Meadow  = Vector3.new(0,1,65),
		Forest  = Vector3.new(145,1,0),
		Desert  = Vector3.new(275,1,0),
		Volcano = Vector3.new(405,1,0),
		Space   = Vector3.new(535,1,0),
	}
	for areaId,origin in pairs(origins) do
		CurrencyService.SeedArea(areaId,origin,45)  -- fewer orbs = less lag
	end
	CurrencyService.SetupOrbTouches()

	-- ============================================================
	-- REBIRTH MACHINE
	-- ============================================================
	local machinePos = Vector3.new(-55, 0, 0)  -- left of spawn, not blocking egg area or biomes

	-- Base slab
	part({Name="RMBase",Size=Vector3.new(14,1,14),Position=machinePos+Vector3.new(0,-0.5,0),
		Color=Color3.fromRGB(30,20,50),Material=Enum.Material.SmoothPlastic})

	-- Base glow ring
	local rmRing = part({Name="RMRing",Size=Vector3.new(15,0.3,15),Position=machinePos+Vector3.new(0,0.15,0),
		Color=Color3.fromRGB(180,0,255),Material=Enum.Material.Neon,CanCollide=false})
	glow(rmRing,Color3.fromRGB(180,0,255),2)
	particles(rmRing,Color3.fromRGB(180,0,255),8)

	-- Four corner pillars
	local pillarColor = Color3.fromRGB(40,30,65)
	local corners = {Vector3.new(5,0,5),Vector3.new(-5,0,5),Vector3.new(5,0,-5),Vector3.new(-5,0,-5)}
	for i,c in ipairs(corners) do
		local pil = part({Name="RMPillar"..i,Size=Vector3.new(2,8,2),
			Position=machinePos+c+Vector3.new(0,4,0),Color=pillarColor,Material=Enum.Material.SmoothPlastic})
		-- Pillar top glow cap
		local cap = part({Name="RMCap"..i,Size=Vector3.new(2.4,0.5,2.4),
			Position=machinePos+c+Vector3.new(0,8.3,0),Color=Color3.fromRGB(180,0,255),
			Material=Enum.Material.Neon,CanCollide=false})
		glow(cap,Color3.fromRGB(180,0,255),1.5)
	end

	-- Top arch connecting pillars
	part({Name="RMArchFront",Size=Vector3.new(12,1.5,2),Position=machinePos+Vector3.new(0,8.5,5),
		Color=pillarColor,Material=Enum.Material.SmoothPlastic})
	part({Name="RMArchBack",Size=Vector3.new(12,1.5,2),Position=machinePos+Vector3.new(0,8.5,-5),
		Color=pillarColor,Material=Enum.Material.SmoothPlastic})

	-- Central glowing core (the machine itself)
	local core = part({Name="RMCore",Size=Vector3.new(4,6,4),
		Position=machinePos+Vector3.new(0,3.5,0),Color=Color3.fromRGB(50,30,80),
		Material=Enum.Material.SmoothPlastic})
	-- Core neon inner
	local coreGlow = part({Name="RMCoreGlow",Size=Vector3.new(3,5,3),
		Position=machinePos+Vector3.new(0,3.5,0),Color=Color3.fromRGB(150,0,255),
		Material=Enum.Material.Neon,CanCollide=false})
	glow(coreGlow,Color3.fromRGB(150,0,255),4)
	particles(coreGlow,Color3.fromRGB(200,50,255),30)
	-- Spinning energy ball on top
	local orb = part({Name="RMOrb",Shape=Enum.PartType.Ball,Size=Vector3.new(2.5,2.5,2.5),
		Position=machinePos+Vector3.new(0,7.5,0),Color=Color3.fromRGB(220,100,255),
		Material=Enum.Material.Neon,CanCollide=false})
	glow(orb,Color3.fromRGB(220,100,255),5)
	particles(orb,Color3.fromRGB(255,200,255),40)

	-- Orbit rings around the orb
	for i=1,3 do
		local ring = part({Name="RMOrbRing"..i,Size=Vector3.new(4+i*0.5,0.15,4+i*0.5),
			Position=machinePos+Vector3.new(0,7.5,0),Color=Color3.fromRGB(180,0,255),
			Material=Enum.Material.Neon,CanCollide=false})
		glow(ring,Color3.fromRGB(180,0,255),1)
		task.spawn(function()
			local t = (i/3)*math.pi*2
			while ring and ring.Parent do
				t=t+task.wait(0.03)*0.8
				ring.CFrame = CFrame.new(machinePos+Vector3.new(0,7.5,0))
					* CFrame.Angles(i*0.6, t, i*0.4)
			end
		end)
	end

	-- Orb bob animation
	task.spawn(function()
		local t=0
		while orb and orb.Parent do
			t=t+task.wait(0.03)
			orb.Position = machinePos+Vector3.new(0, 7.5+math.sin(t*1.2)*0.5, 0)
			orb.CFrame = CFrame.new(orb.Position)*CFrame.Angles(0,t*0.6,0)
		end
	end)

	-- Sign billboard
	local signAnchor = part({Name="RMSign",Size=Vector3.new(1,1,1),
		Position=machinePos+Vector3.new(0,12,0),Transparency=1,CanCollide=false})
	local bb = Instance.new("BillboardGui")
	bb.Size=UDim2.new(0,220,0,80); bb.StudsOffset=Vector3.new(0,0,0)
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
	cd.MouseClick:Connect(function(player)
		RE_Rebirth:FireClient(player)  -- send to client to show confirmation popup
	end)
	-- Also clickable on the orb
	local cd2 = Instance.new("ClickDetector"); cd2.MaxActivationDistance=20; cd2.Parent=orb
	cd2.MouseClick:Connect(function(player)
		RE_Rebirth:FireClient(player)
	end)
end

-- ============================================================
-- DATA SYNC
-- ============================================================
local function syncData(player)
	local data = DataManager.GetData(player)
	if data then RE_DataUpdated:FireClient(player,data) end
end

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
	DataManager.LoadPlayer(player)
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
		RE_HatchResult:FireClient(player,results,eggId)
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
	local areaConfig=nil
	for _,a in ipairs(GameConfig.Areas) do if a.id==areaId then areaConfig=a break end end
	if not areaConfig then return end
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
	GamepassService.PromptPurchase(player,gpKey)
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
		table.insert(data.Pets, { name=arg.name, rarity=arg.rarity or "Common", uniqueId=HttpService:GenerateGUID(false) })
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
local mapOk, mapErr = pcall(buildMap)
if not mapOk then warn("[StarPets] buildMap error: " .. tostring(mapErr)) end
BadgeService.SetRemote(RE_BadgeEarned)
CurrencyService.StartPassiveIncome(PetService)
MerchantService.Start(function()
	RE_Notification:FireAllClients("info", "🛒 The Traveling Merchant has arrived — limited stock!")
end)
EventService.Init()
print("[MysticPets] Server ready!")
