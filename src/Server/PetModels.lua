-- MysticPets: PetModels.lua
-- Unique multi-part models for every pet
-- Place in: ServerScriptService > Server > PetModels (ModuleScript)

local PetModels = {}

-- ============================================================
-- SHARED HELPERS
-- ============================================================
local function p(model, props)
	local part = Instance.new("Part")
	part.Anchored   = true
	part.CanCollide = false
	part.CastShadow = false
	for k,v in pairs(props) do part[k] = v end
	part.Parent = model
	return part
end

local function wedge(model, props)
	local part = Instance.new("WedgePart")
	part.Anchored   = true
	part.CanCollide = false
	part.CastShadow = false
	for k,v in pairs(props) do part[k] = v end
	part.Parent = model
	return part
end

local function addGlow(part, color, brightness)
	local l = Instance.new("PointLight")
	l.Color = color; l.Brightness = brightness or 2; l.Range = 14; l.Parent = part
end

local function addParticles(part, color, rate)
	local att = Instance.new("Attachment"); att.Parent = part
	local pe = Instance.new("ParticleEmitter"); pe.Parent = att
	pe.Color = ColorSequence.new({ColorSequenceKeypoint.new(0,color),ColorSequenceKeypoint.new(1,Color3.new(1,1,1))})
	pe.LightEmission=0.9; pe.LightInfluence=0.1
	pe.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0.3),NumberSequenceKeypoint.new(1,0)})
	pe.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.2),NumberSequenceKeypoint.new(1,1)})
	pe.Speed=NumberRange.new(1,3); pe.Lifetime=NumberRange.new(0.8,1.6)
	pe.Rate=rate or 15; pe.SpreadAngle=Vector2.new(180,180)
	pe.RotSpeed=NumberRange.new(-60,60); pe.Rotation=NumberRange.new(0,360)
end

local function addTrail(part, color)
	local a0=Instance.new("Attachment"); a0.Position=Vector3.new(0,0.5,0); a0.Parent=part
	local a1=Instance.new("Attachment"); a1.Position=Vector3.new(0,-0.5,0); a1.Parent=part
	local trail=Instance.new("Trail"); trail.Parent=part
	trail.Attachment0=a0; trail.Attachment1=a1
	trail.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,color),ColorSequenceKeypoint.new(1,Color3.new(1,1,1))})
	trail.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.3),NumberSequenceKeypoint.new(1,1)})
	trail.Lifetime=0.4; trail.LightEmission=0.8; trail.MinLength=0.1
end

local function orbitingStars(anchor, model, color, count)
	for i=1,count do
		local star = p(model, {
			Name="OrbitStar"..i,
			Shape=Enum.PartType.Ball,
			Size=Vector3.new(0.3,0.3,0.3),
			Color=color,
			Material=Enum.Material.Neon,
		})
		addGlow(star,color,1)
		task.spawn(function()
			local t=(i/#({}) or 0)*math.pi*2
			while star and star.Parent and anchor and anchor.Parent do
				t=t+task.wait(0.03)*1.5
				local r=2.5; local y=math.sin(t*0.5)*1.2
				if anchor.Parent then
					star.CFrame=anchor.CFrame*CFrame.new(math.cos(t)*r,y,math.sin(t)*r)
				end
			end
		end)
	end
end

-- ============================================================
-- EYE BUILDER
-- ============================================================
local function eyes(model, headPart, size, eyeColor)
	eyeColor = eyeColor or Color3.new(1,1,1)
	for i, xOff in ipairs({0.28,-0.28}) do
		local eye = p(model,{Name="Eye"..i,Shape=Enum.PartType.Ball,
			Size=Vector3.new(0.3*size,0.3*size,0.3*size),
			Color=eyeColor,Material=Enum.Material.Neon})
		local pupil = p(model,{Name="Pupil"..i,Shape=Enum.PartType.Ball,
			Size=Vector3.new(0.15*size,0.15*size,0.15*size),
			Color=Color3.new(0,0,0),Material=Enum.Material.SmoothPlastic})
		-- Positions set in update loop via offsets stored on parts
		eye:SetAttribute("XOff",xOff)
		eye:SetAttribute("YOff",0.18)
		eye:SetAttribute("ZOff",-0.55)
		pupil:SetAttribute("XOff",xOff)
		pupil:SetAttribute("YOff",0.18)
		pupil:SetAttribute("ZOff",-0.62)
	end
end

-- ============================================================
-- PET BUILDERS  (each returns root = HumanoidRootPart)
-- ============================================================

local function buildCat(model, size, color)
	local body = p(model,{Name="HumanoidRootPart",
		Size=Vector3.new(1.8*size,1.4*size,1.2*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local head = p(model,{Name="Head",Shape=Enum.PartType.Ball,
		Size=Vector3.new(1.4*size,1.4*size,1.4*size),Color=color,Material=Enum.Material.SmoothPlastic})
	-- Pointy ears
	local earL = wedge(model,{Name="EarL",Size=Vector3.new(0.4*size,0.7*size,0.4*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local earR = wedge(model,{Name="EarR",Size=Vector3.new(0.4*size,0.7*size,0.4*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local earInL = p(model,{Name="EarInL",Shape=Enum.PartType.Ball,
		Size=Vector3.new(0.2*size,0.35*size,0.2*size),Color=Color3.fromRGB(255,180,180),Material=Enum.Material.SmoothPlastic})
	-- Tail (3 segments curling up)
	local t1 = p(model,{Name="Tail1",Size=Vector3.new(0.3*size,0.8*size,0.3*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local t2 = p(model,{Name="Tail2",Size=Vector3.new(0.25*size,0.6*size,0.25*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local tailTip = p(model,{Name="TailTip",Shape=Enum.PartType.Ball,
		Size=Vector3.new(0.4*size,0.4*size,0.4*size),Color=Color3.fromRGB(255,255,255),Material=Enum.Material.SmoothPlastic})
	-- Offsets stored as attributes (read by PetService update loop)
	head:SetAttribute("BodyOffset",true)
	earL:SetAttribute("IsEarL",true)
	earR:SetAttribute("IsEarR",true)
	body:SetAttribute("RootPart",true)
	eyes(model,head,size)
	return body
end

local function buildDog(model, size, color)
	local body = p(model,{Name="HumanoidRootPart",
		Size=Vector3.new(2.0*size,1.4*size,1.3*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local head = p(model,{Name="Head",
		Size=Vector3.new(1.3*size,1.2*size,1.4*size),Color=color,Material=Enum.Material.SmoothPlastic})
	-- Floppy ears (flat wedges hanging down)
	local earL = p(model,{Name="EarL",
		Size=Vector3.new(0.5*size,0.9*size,0.15*size),Color=Color3.fromRGB(160,110,60),Material=Enum.Material.SmoothPlastic})
	local earR = p(model,{Name="EarR",
		Size=Vector3.new(0.5*size,0.9*size,0.15*size),Color=Color3.fromRGB(160,110,60),Material=Enum.Material.SmoothPlastic})
	-- Snout
	local snout = p(model,{Name="Snout",
		Size=Vector3.new(0.7*size,0.55*size,0.5*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local nose = p(model,{Name="Nose",Shape=Enum.PartType.Ball,
		Size=Vector3.new(0.22*size,0.18*size,0.22*size),Color=Color3.new(0,0,0),Material=Enum.Material.SmoothPlastic})
	-- Stubby wagging tail
	local tail = p(model,{Name="Tail",Size=Vector3.new(0.3*size,0.7*size,0.3*size),Color=color,Material=Enum.Material.SmoothPlastic})
	eyes(model,head,size)
	return body
end

local function buildBunny(model, size, color)
	local body = p(model,{Name="HumanoidRootPart",Shape=Enum.PartType.Ball,
		Size=Vector3.new(1.6*size,1.6*size,1.4*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local head = p(model,{Name="Head",Shape=Enum.PartType.Ball,
		Size=Vector3.new(1.2*size,1.2*size,1.2*size),Color=color,Material=Enum.Material.SmoothPlastic})
	-- Long upright ears
	local earL = p(model,{Name="EarL",
		Size=Vector3.new(0.35*size,1.4*size,0.2*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local earR = p(model,{Name="EarR",
		Size=Vector3.new(0.35*size,1.4*size,0.2*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local earInL = p(model,{Name="EarInL",
		Size=Vector3.new(0.2*size,1.1*size,0.1*size),Color=Color3.fromRGB(255,180,180),Material=Enum.Material.SmoothPlastic})
	local earInR = p(model,{Name="EarInR",
		Size=Vector3.new(0.2*size,1.1*size,0.1*size),Color=Color3.fromRGB(255,180,180),Material=Enum.Material.SmoothPlastic})
	-- Cotton tail
	local cottontail = p(model,{Name="CottonTail",Shape=Enum.PartType.Ball,
		Size=Vector3.new(0.5*size,0.5*size,0.5*size),Color=Color3.new(1,1,1),Material=Enum.Material.SmoothPlastic})
	eyes(model,head,size,Color3.fromRGB(200,100,255))
	return body
end

local function buildFox(model, size, color)
	local body = p(model,{Name="HumanoidRootPart",
		Size=Vector3.new(1.8*size,1.2*size,1.1*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local head = p(model,{Name="Head",
		Size=Vector3.new(1.2*size,1.1*size,1.3*size),Color=color,Material=Enum.Material.SmoothPlastic})
	-- Pointy snout
	local snout = wedge(model,{Name="Snout",
		Size=Vector3.new(0.6*size,0.5*size,0.8*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local noseTip = p(model,{Name="Nose",Shape=Enum.PartType.Ball,
		Size=Vector3.new(0.18*size,0.14*size,0.18*size),Color=Color3.new(0,0,0),Material=Enum.Material.SmoothPlastic})
	-- Triangular pointy ears
	local earL = wedge(model,{Name="EarL",
		Size=Vector3.new(0.4*size,0.7*size,0.3*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local earR = wedge(model,{Name="EarR",
		Size=Vector3.new(0.4*size,0.7*size,0.3*size),Color=color,Material=Enum.Material.SmoothPlastic})
	-- MASSIVE bushy tail
	local tail1 = p(model,{Name="Tail1",Size=Vector3.new(0.8*size,1.2*size,0.8*size),
		Color=color,Material=Enum.Material.SmoothPlastic})
	local tailTip = p(model,{Name="TailTip",Shape=Enum.PartType.Ball,
		Size=Vector3.new(0.9*size,0.9*size,0.9*size),Color=Color3.new(1,1,1),Material=Enum.Material.SmoothPlastic})
	eyes(model,head,size,Color3.fromRGB(255,200,50))
	return body
end

local function buildWolf(model, size, color)
	local body = p(model,{Name="HumanoidRootPart",
		Size=Vector3.new(2.2*size,1.6*size,1.3*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local neck = p(model,{Name="Neck",
		Size=Vector3.new(0.8*size,0.8*size,0.8*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local head = p(model,{Name="Head",
		Size=Vector3.new(1.4*size,1.3*size,1.5*size),Color=color,Material=Enum.Material.SmoothPlastic})
	-- Angular snout
	local snout = p(model,{Name="Snout",
		Size=Vector3.new(0.7*size,0.6*size,0.9*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local earL = wedge(model,{Name="EarL",Size=Vector3.new(0.45*size,0.8*size,0.35*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local earR = wedge(model,{Name="EarR",Size=Vector3.new(0.45*size,0.8*size,0.35*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local tail = p(model,{Name="Tail",Size=Vector3.new(0.5*size,1.4*size,0.5*size),Color=color,Material=Enum.Material.SmoothPlastic})
	eyes(model,head,size,Color3.fromRGB(255,220,50))
	return body
end

local function buildDragon(model, size, color, rarityColor)
	local body = p(model,{Name="HumanoidRootPart",
		Size=Vector3.new(2.0*size,1.6*size,1.4*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local neck = p(model,{Name="Neck",
		Size=Vector3.new(0.9*size,1.2*size,0.9*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local head = p(model,{Name="Head",
		Size=Vector3.new(1.5*size,1.2*size,1.8*size),Color=color,Material=Enum.Material.SmoothPlastic})
	-- Horns
	local hornL = wedge(model,{Name="HornL",Size=Vector3.new(0.25*size,0.8*size,0.25*size),
		Color=Color3.fromRGB(50,50,80),Material=Enum.Material.SmoothPlastic})
	local hornR = wedge(model,{Name="HornR",Size=Vector3.new(0.25*size,0.8*size,0.25*size),
		Color=Color3.fromRGB(50,50,80),Material=Enum.Material.SmoothPlastic})
	-- Spine spikes
	for i=1,5 do
		local spike = wedge(model,{Name="Spine"..i,
			Size=Vector3.new(0.2*size,(0.6-i*0.07)*size,0.2*size),
			Color=rarityColor,Material=Enum.Material.Neon})
		addGlow(spike,rarityColor,0.8)
	end
	-- WINGS (flat angled wedges)
	local wingL = wedge(model,{Name="WingL",
		Size=Vector3.new(2.8*size,0.15*size,2.0*size),
		Color=color,Material=Enum.Material.SmoothPlastic})
	local wingR = wedge(model,{Name="WingR",
		Size=Vector3.new(2.8*size,0.15*size,2.0*size),
		Color=color,Material=Enum.Material.SmoothPlastic})
	local wingLNeon = p(model,{Name="WingLNeon",
		Size=Vector3.new(2.6*size,0.08*size,1.8*size),
		Color=rarityColor,Material=Enum.Material.Neon,CanCollide=false})
	local wingRNeon = p(model,{Name="WingRNeon",
		Size=Vector3.new(2.6*size,0.08*size,1.8*size),
		Color=rarityColor,Material=Enum.Material.Neon,CanCollide=false})
	-- Tail
	local tail1 = p(model,{Name="Tail1",Size=Vector3.new(0.7*size,0.7*size,1.4*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local tail2 = p(model,{Name="Tail2",Size=Vector3.new(0.5*size,0.5*size,1.0*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local tailTip = wedge(model,{Name="TailTip",Size=Vector3.new(0.4*size,0.7*size,0.6*size),Color=rarityColor,Material=Enum.Material.Neon})
	addGlow(tailTip,rarityColor,1.2)
	-- Mouth fire particles
	local mouthAtt = Instance.new("Attachment"); mouthAtt.Parent=head
	local firePE = Instance.new("ParticleEmitter"); firePE.Parent=mouthAtt
	firePE.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,100,0)),ColorSequenceKeypoint.new(1,Color3.fromRGB(255,255,0))})
	firePE.LightEmission=1; firePE.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0.4*size),NumberSequenceKeypoint.new(1,0)})
	firePE.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(1,1)})
	firePE.Speed=NumberRange.new(2,5); firePE.Lifetime=NumberRange.new(0.3,0.7)
	firePE.Rate=20; firePE.SpreadAngle=Vector2.new(15,15)
	addGlow(head,Color3.fromRGB(255,100,0),1.5)
	addParticles(body,rarityColor,10)
	eyes(model,head,size,Color3.fromRGB(255,50,50))
	return body
end

local function buildPhoenix(model, size, color, rarityColor)
	local body = p(model,{Name="HumanoidRootPart",
		Size=Vector3.new(1.8*size,1.4*size,1.2*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local head = p(model,{Name="Head",Shape=Enum.PartType.Ball,
		Size=Vector3.new(1.2*size,1.2*size,1.2*size),Color=color,Material=Enum.Material.SmoothPlastic})
	-- Crest feathers on head
	for i=1,3 do
		local crest = wedge(model,{Name="Crest"..i,
			Size=Vector3.new(0.2*size,(0.6+i*0.15)*size,0.15*size),
			Color=rarityColor,Material=Enum.Material.Neon})
		addGlow(crest,rarityColor,0.6)
	end
	-- Wide spread wings
	local wingL = p(model,{Name="WingL",
		Size=Vector3.new(3.5*size,0.2*size,2.4*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local wingR = p(model,{Name="WingR",
		Size=Vector3.new(3.5*size,0.2*size,2.4*size),Color=color,Material=Enum.Material.SmoothPlastic})
	-- Wing neon trim
	local wlNeon = p(model,{Name="WingLNeon",Size=Vector3.new(3.3*size,0.1*size,2.2*size),Color=rarityColor,Material=Enum.Material.Neon})
	local wrNeon = p(model,{Name="WingRNeon",Size=Vector3.new(3.3*size,0.1*size,2.2*size),Color=rarityColor,Material=Enum.Material.Neon})
	addGlow(wlNeon,rarityColor,1); addGlow(wrNeon,rarityColor,1)
	-- Tail feathers (5 long streaks)
	for i=1,5 do
		local feather = p(model,{Name="Feather"..i,
			Size=Vector3.new(0.18*size,0.18*size,(1.0+i*0.3)*size),
			Color=i%2==0 and rarityColor or color,Material=Enum.Material.Neon})
		addGlow(feather,rarityColor,0.5)
	end
	-- Fire body aura
	addParticles(body,Color3.fromRGB(255,120,0),25)
	addParticles(wingL,rarityColor,10)
	addParticles(wingR,rarityColor,10)
	addGlow(body,Color3.fromRGB(255,100,0),2)
	eyes(model,head,size,Color3.fromRGB(255,255,50))
	return body
end

local function buildUnicorn(model, size, color, rarityColor)
	local body = p(model,{Name="HumanoidRootPart",
		Size=Vector3.new(2.4*size,1.6*size,1.3*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local neck = p(model,{Name="Neck",
		Size=Vector3.new(0.9*size,1.4*size,0.9*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local head = p(model,{Name="Head",
		Size=Vector3.new(1.2*size,1.2*size,1.6*size),Color=color,Material=Enum.Material.SmoothPlastic})
	-- PROMINENT HORN (3 tapering cylinders)
	local horn1 = p(model,{Name="Horn1",
		Size=Vector3.new(0.4*size,1.2*size,0.4*size),Color=rarityColor,Material=Enum.Material.Neon})
	local horn2 = p(model,{Name="Horn2",
		Size=Vector3.new(0.25*size,0.9*size,0.25*size),Color=Color3.new(1,1,1),Material=Enum.Material.Neon})
	local hornTip = p(model,{Name="HornTip",Shape=Enum.PartType.Ball,
		Size=Vector3.new(0.2*size,0.2*size,0.2*size),Color=Color3.new(1,1,1),Material=Enum.Material.Neon})
	addGlow(horn1,rarityColor,2); addGlow(hornTip,rarityColor,1.5)
	-- Flowing mane (colored parts along neck)
	local maneColors = {Color3.fromRGB(255,100,255),Color3.fromRGB(100,200,255),Color3.fromRGB(255,200,100)}
	for i=1,4 do
		local mane = p(model,{Name="Mane"..i,
			Size=Vector3.new(0.4*size,0.5*size,0.2*size),
			Color=maneColors[(i%3)+1],Material=Enum.Material.Neon})
		addGlow(mane,maneColors[(i%3)+1],0.5)
	end
	-- Legs
	for i=1,4 do
		local leg = p(model,{Name="Leg"..i,Size=Vector3.new(0.4*size,1.0*size,0.4*size),Color=color,Material=Enum.Material.SmoothPlastic})
		local hoof = p(model,{Name="Hoof"..i,Size=Vector3.new(0.45*size,0.3*size,0.45*size),Color=Color3.fromRGB(80,70,100),Material=Enum.Material.SmoothPlastic})
	end
	-- Tail
	local tail = p(model,{Name="Tail",Size=Vector3.new(0.6*size,1.4*size,0.3*size),Color=rarityColor,Material=Enum.Material.Neon})
	addGlow(tail,rarityColor,1)
	addParticles(body,rarityColor,15)
	addParticles(horn1,rarityColor,12)
	eyes(model,head,size,Color3.fromRGB(180,100,255))
	return body
end

local function buildCelestialDragon(model, size, color, rarityColor)
	local body = p(model,{Name="HumanoidRootPart",
		Size=Vector3.new(2.8*size,2.0*size,2.0*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local neck1 = p(model,{Name="Neck1",Size=Vector3.new(1.2*size,1.4*size,1.2*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local neck2 = p(model,{Name="Neck2",Size=Vector3.new(1.0*size,1.0*size,1.0*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local head = p(model,{Name="Head",Size=Vector3.new(2.0*size,1.6*size,2.4*size),Color=color,Material=Enum.Material.SmoothPlastic})
	-- Crown of 6 horns
	for i=1,6 do
		local ang = (i/6)*math.pi*2
		local horn = wedge(model,{Name="Crown"..i,Size=Vector3.new(0.3*size,1.0*size,0.3*size),Color=rarityColor,Material=Enum.Material.Neon})
		addGlow(horn,rarityColor,0.8)
	end
	-- Double wings
	for _, side in ipairs({"L","R"}) do
		local wingUp = p(model,{Name="WingUp"..side,Size=Vector3.new(4.0*size,0.2*size,2.8*size),Color=color,Material=Enum.Material.SmoothPlastic})
		local wingLow = p(model,{Name="WingLow"..side,Size=Vector3.new(3.0*size,0.2*size,2.0*size),Color=color,Material=Enum.Material.SmoothPlastic})
		local wingNeon = p(model,{Name="WingNeon"..side,Size=Vector3.new(3.8*size,0.1*size,2.6*size),Color=rarityColor,Material=Enum.Material.Neon})
		addGlow(wingNeon,rarityColor,1.5)
	end
	-- Glowing spine all the way down
	for i=1,8 do
		local spine = wedge(model,{Name="Spine"..i,Size=Vector3.new(0.3*size,0.9*size,0.3*size),Color=rarityColor,Material=Enum.Material.Neon})
		addGlow(spine,rarityColor,1)
	end
	-- Serpentine tail
	for i=1,4 do
		local ts = p(model,{Name="TailSeg"..i,Size=Vector3.new((1.2-i*0.2)*size,(1.2-i*0.2)*size,(1.0-i*0.15)*size),Color=color,Material=Enum.Material.SmoothPlastic})
	end
	local tailTip = p(model,{Name="TailTip",Shape=Enum.PartType.Ball,Size=Vector3.new(0.6*size,0.6*size,0.6*size),Color=rarityColor,Material=Enum.Material.Neon})
	addGlow(tailTip,rarityColor,2)
	-- Massive particle aura
	addParticles(body,rarityColor,40)
	addParticles(head,Color3.fromRGB(200,240,255),20)
	addGlow(body,rarityColor,3)
	addGlow(head,rarityColor,3)
	addTrail(tailTip,rarityColor)
	eyes(model,head,size*1.2,Color3.fromRGB(0,220,255))
	return body
end

local function buildStarPhoenix(model, size, color, rarityColor)
	local body = p(model,{Name="HumanoidRootPart",
		Size=Vector3.new(2.2*size,1.8*size,1.5*size),Color=color,Material=Enum.Material.Neon})
	local head = p(model,{Name="Head",Shape=Enum.PartType.Ball,
		Size=Vector3.new(1.6*size,1.6*size,1.6*size),Color=color,Material=Enum.Material.Neon})
	-- Giant wings (3 layers each side)
	for i,sz in ipairs({5.0,3.8,2.6}) do
		for _,side in ipairs({"L","R"}) do
			local wing = p(model,{Name="Wing"..i..side,
				Size=Vector3.new(sz*size,0.12*size,(2.5-i*0.3)*size),
				Color=i==1 and rarityColor or Color3.new(1,1,1),Material=Enum.Material.Neon})
			addGlow(wing,rarityColor,1.2)
		end
	end
	-- Crown of 8 crest feathers
	for i=1,8 do
		local crest=wedge(model,{Name="Crest"..i,Size=Vector3.new(0.2*size,(0.8+i*0.1)*size,0.15*size),Color=rarityColor,Material=Enum.Material.Neon})
		addGlow(crest,rarityColor,1)
	end
	-- Comet tail
	for i=1,7 do
		local ft=p(model,{Name="FTail"..i,Size=Vector3.new(0.2*size,0.2*size,(1.2+i*0.4)*size),Color=rarityColor,Material=Enum.Material.Neon})
		addGlow(ft,rarityColor,0.8)
		addTrail(ft,rarityColor)
	end
	addParticles(body,rarityColor,50)
	addParticles(head,Color3.new(1,1,1),30)
	addGlow(body,rarityColor,4); addGlow(head,rarityColor,4)
	eyes(model,head,size*1.3,Color3.fromRGB(255,255,0))
	return body
end

local function buildVoidSerpent(model, size, color, rarityColor)
	-- Serpentine body with 6 segments
	local body = p(model,{Name="HumanoidRootPart",
		Size=Vector3.new(1.4*size,1.4*size,2.0*size),Color=color,Material=Enum.Material.SmoothPlastic})
	for i=2,6 do
		local seg=p(model,{Name="Seg"..i,
			Size=Vector3.new((1.6-i*0.15)*size,(1.6-i*0.15)*size,(2.0-i*0.1)*size),
			Color=color,Material=Enum.Material.SmoothPlastic})
	end
	local head = p(model,{Name="Head",
		Size=Vector3.new(1.8*size,1.4*size,2.2*size),Color=color,Material=Enum.Material.SmoothPlastic})
	-- Frill (like a cobra hood)
	local frillL = wedge(model,{Name="FrillL",Size=Vector3.new(1.2*size,0.1*size,1.0*size),Color=rarityColor,Material=Enum.Material.Neon})
	local frillR = wedge(model,{Name="FrillR",Size=Vector3.new(1.2*size,0.1*size,1.0*size),Color=rarityColor,Material=Enum.Material.Neon})
	addGlow(frillL,rarityColor,1.5); addGlow(frillR,rarityColor,1.5)
	-- Back fins
	for i=1,4 do
		local fin=wedge(model,{Name="Fin"..i,Size=Vector3.new(0.1*size,0.8*size,0.6*size),Color=rarityColor,Material=Enum.Material.Neon})
		addGlow(fin,rarityColor,0.7)
	end
	local tailTip=wedge(model,{Name="TailTip",Size=Vector3.new(0.4*size,0.4*size,1.0*size),Color=rarityColor,Material=Enum.Material.Neon})
	addGlow(tailTip,rarityColor,2); addTrail(tailTip,rarityColor)
	addParticles(body,rarityColor,35)
	addGlow(body,rarityColor,2.5); addGlow(head,rarityColor,2)
	eyes(model,head,size*1.1,rarityColor)
	return body
end

local function buildGeneric(model, size, color, rarityColor)
	local body = p(model,{Name="HumanoidRootPart",Shape=Enum.PartType.Ball,
		Size=Vector3.new(1.8*size,1.8*size,1.8*size),Color=color,Material=Enum.Material.SmoothPlastic})
	local head = p(model,{Name="Head",Shape=Enum.PartType.Ball,
		Size=Vector3.new(1.3*size,1.3*size,1.3*size),Color=color,Material=Enum.Material.SmoothPlastic})
	addParticles(body,rarityColor,10)
	addGlow(body,rarityColor,1.5)
	eyes(model,head,size)
	return body
end

-- ============================================================
-- PUBLIC: Build a pet model by name
-- ============================================================
local builders = {
	Kitten           = buildCat,
	Puppy            = buildDog,
	Bunny            = buildBunny,
	Chick            = buildGeneric,
	Fox              = buildFox,
	Wolf             = buildWolf,
	Owl              = buildGeneric,
	Panda            = buildGeneric,
	Tiger            = buildGeneric,
	["Snow Leopard"] = buildGeneric,
	Dragon           = buildDragon,
	Phoenix          = buildPhoenix,
	Kirin            = buildGeneric,
	Unicorn          = buildUnicorn,
	["Cosmic Griffin"]  = buildGeneric,
	["Shadow Wolf"]     = buildWolf,
	["Celestial Dragon"]= buildCelestialDragon,
	["Star Phoenix"]    = buildStarPhoenix,
	["Void Serpent"]    = buildVoidSerpent,
}

function PetModels.Build(petData, uniqueId, rarityInfo)
	local model   = Instance.new("Model")
	model.Name    = petData.name .. "_" .. uniqueId
	local size    = petData.size or 1.0
	local rColor  = rarityInfo and rarityInfo.color or Color3.fromRGB(200,200,200)

	local builder = builders[petData.name] or buildGeneric
	local root    = builder(model, size, petData.color, rColor)

	-- Billboard name tag
	local bb = Instance.new("BillboardGui")
	bb.Size        = UDim2.new(0,150,0,52)
	bb.StudsOffset = Vector3.new(0,2.2*size,0)
	bb.MaxDistance = 35  -- pet name tag only shows when you're close
	bb.Adornee     = root
	bb.AlwaysOnTop = false
	bb.Parent      = model

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size=UDim2.new(1,0,0.58,0); nameLbl.BackgroundTransparency=1
	nameLbl.Text=petData.name; nameLbl.TextColor3=rColor
	nameLbl.TextScaled=true; nameLbl.Font=Enum.Font.GothamBold
	nameLbl.TextStrokeTransparency=0.3; nameLbl.TextStrokeColor3=Color3.new(0,0,0)
	nameLbl.Parent=bb

	local rarLbl = Instance.new("TextLabel")
	rarLbl.Size=UDim2.new(1,0,0.42,0); rarLbl.Position=UDim2.new(0,0,0.58,0)
	rarLbl.BackgroundTransparency=1; rarLbl.Text=petData.rarity
	rarLbl.TextColor3=rColor; rarLbl.TextScaled=true; rarLbl.Font=Enum.Font.Gotham
	rarLbl.TextStrokeTransparency=0.4; rarLbl.TextStrokeColor3=Color3.new(0,0,0)
	rarLbl.Parent=bb

	model.PrimaryPart = root
	return model, root
end

return PetModels
