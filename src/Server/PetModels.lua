-- StarPets: PetModels.lua
-- Properly ASSEMBLED multi-part pet models. Every part is positioned
-- relative to the root (HumanoidRootPart) at build time, the model gets a
-- PrimaryPart, and PetService moves the whole thing with model:PivotTo().
-- Place in: ServerScriptService > Server > PetModels (ModuleScript)

local PetModels = {}

-- Forward = -Z, Up = +Y. Root body sits at origin; everything is offset from it.

-- ============================================================
-- PART HELPERS
-- ============================================================
local function box(model, props, pos, size, rot)
	local p = Instance.new("Part")
	p.Anchored=true; p.CanCollide=false; p.CastShadow=false
	p.TopSurface=Enum.SurfaceType.Smooth; p.BottomSurface=Enum.SurfaceType.Smooth
	for k,v in pairs(props) do p[k]=v end
	p.Size=size
	p.CFrame=CFrame.new(pos) * (rot or CFrame.new())
	p.Parent=model
	return p
end

local function ball(model, props, pos, d)
	local p = Instance.new("Part")
	p.Shape=Enum.PartType.Ball
	p.Anchored=true; p.CanCollide=false; p.CastShadow=false
	for k,v in pairs(props) do p[k]=v end
	p.Size=Vector3.new(d,d,d)
	p.CFrame=CFrame.new(pos)
	p.Parent=model
	return p
end

local function wedge(model, props, pos, size, rot)
	local p = Instance.new("WedgePart")
	p.Anchored=true; p.CanCollide=false; p.CastShadow=false
	for k,v in pairs(props) do p[k]=v end
	p.Size=size
	p.CFrame=CFrame.new(pos) * (rot or CFrame.new())
	p.Parent=model
	return p
end

local function cyl(model, props, pos, size, rot)
	local p = Instance.new("Part")
	p.Shape=Enum.PartType.Cylinder
	p.Anchored=true; p.CanCollide=false; p.CastShadow=false
	for k,v in pairs(props) do p[k]=v end
	p.Size=size
	p.CFrame=CFrame.new(pos) * (rot or CFrame.new())
	p.Parent=model
	return p
end

local function addGlow(part, color, b)
	local l=Instance.new("PointLight")
	l.Color=color; l.Brightness=(b or 1)*0.4; l.Range=8; l.Parent=part
end

local function addAura(part, color, rate)
	local att=Instance.new("Attachment"); att.Parent=part
	local pe=Instance.new("ParticleEmitter"); pe.Parent=att
	pe.Color=ColorSequence.new(color, Color3.new(1,1,1))
	pe.LightEmission=0.8; pe.LightInfluence=0.1
	pe.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,0.3),NumberSequenceKeypoint.new(1,0)})
	pe.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0.3),NumberSequenceKeypoint.new(1,1)})
	pe.Speed=NumberRange.new(0.5,2); pe.Lifetime=NumberRange.new(0.7,1.4)
	pe.Rate=rate or 10; pe.SpreadAngle=Vector2.new(180,180)
end

local function eyes(model, headPos, s, eyeColor)
	eyeColor = eyeColor or Color3.fromRGB(26,28,52)  -- soft navy, not harsh black
	for _, x in ipairs({0.32, -0.32}) do
		-- white sclera
		ball(model,{Name="EyeW",Color=Color3.new(1,1,1),Material=Enum.Material.SmoothPlastic},
			headPos + Vector3.new(x,0.1,-0.5)*s, 0.40*s)
		-- iris
		ball(model,{Name="Eye",Color=eyeColor,Material=Enum.Material.SmoothPlastic},
			headPos + Vector3.new(x,0.08,-0.66)*s, 0.24*s)
		-- big shine
		ball(model,{Name="Shine",Color=Color3.new(1,1,1),Material=Enum.Material.SmoothPlastic},
			headPos + Vector3.new(x+0.08,0.18,-0.80)*s, 0.11*s)
		-- small shine
		ball(model,{Name="Shine2",Color=Color3.new(1,1,1),Material=Enum.Material.SmoothPlastic},
			headPos + Vector3.new(x-0.07,0.0,-0.80)*s, 0.055*s)
	end
	-- blush cheeks
	for _, x in ipairs({0.55, -0.55}) do
		local b = ball(model,{Name="Blush",Color=Color3.fromRGB(255,135,145),Material=Enum.Material.SmoothPlastic},
			headPos + Vector3.new(x,-0.12,-0.36)*s, 0.2*s)
		b.Size = Vector3.new(0.3,0.14,0.22)*s
	end
end

-- 4 legs at the body corners
local function legs(model, s, color, bodyW, bodyH, bodyLen, legLen)
	local lx, lz = bodyW*0.40, bodyLen*0.30
	local ly = -(bodyH*0.5 + legLen*0.5 - 0.1)
	for _, c in ipairs({{lx,-lz},{-lx,-lz},{lx,lz},{-lx,lz}}) do
		box(model,{Name="Leg",Color=color,Material=Enum.Material.SmoothPlastic},
			Vector3.new(c[1],ly,c[2])*s, Vector3.new(0.34,legLen,0.34)*s)
	end
end

local SMOOTH = Enum.Material.SmoothPlastic
local NEON   = Enum.Material.Neon

-- ============================================================
-- BUILDERS  (each returns the root part)
-- ============================================================
local function buildCat(model, s, color, rColor)
	local body = box(model,{Name="HumanoidRootPart",Color=color,Material=SMOOTH},
		Vector3.new(0,0,0), Vector3.new(1.3,1.1,2.0)*s)
	legs(model, s, color, 1.3,1.1,2.0, 0.8)
	local hp = Vector3.new(0,0.55,-1.15)*s
	ball(model,{Name="Head",Color=color,Material=SMOOTH}, hp, 1.2*s)
	-- pointy ears
	wedge(model,{Name="EarL",Color=color,Material=SMOOTH}, hp+Vector3.new(0.35,0.7,0)*s, Vector3.new(0.4,0.6,0.4)*s)
	wedge(model,{Name="EarR",Color=color,Material=SMOOTH}, hp+Vector3.new(-0.35,0.7,0)*s, Vector3.new(0.4,0.6,0.4)*s)
	-- snout + nose
	box(model,{Name="Snout",Color=color,Material=SMOOTH}, hp+Vector3.new(0,-0.1,-0.55)*s, Vector3.new(0.45,0.35,0.3)*s)
	ball(model,{Name="Nose",Color=Color3.fromRGB(255,150,170),Material=SMOOTH}, hp+Vector3.new(0,-0.05,-0.72)*s, 0.18*s)
	-- curled tail (3 segments rising at the back)
	box(model,{Name="Tail1",Color=color,Material=SMOOTH}, Vector3.new(0,0.2,1.05)*s, Vector3.new(0.3,0.3,0.7)*s)
	box(model,{Name="Tail2",Color=color,Material=SMOOTH}, Vector3.new(0,0.7,1.25)*s, Vector3.new(0.28,0.6,0.28)*s)
	ball(model,{Name="TailTip",Color=Color3.new(1,1,1),Material=SMOOTH}, Vector3.new(0,1.05,1.25)*s, 0.34*s)
	eyes(model, hp, s, Color3.fromRGB(60,180,90))
	return body
end

local function buildDog(model, s, color, rColor)
	local body = box(model,{Name="HumanoidRootPart",Color=color,Material=SMOOTH},
		Vector3.new(0,0,0), Vector3.new(1.4,1.2,2.1)*s)
	legs(model, s, color, 1.4,1.2,2.1, 0.85)
	local hp = Vector3.new(0,0.5,-1.25)*s
	box(model,{Name="Head",Color=color,Material=SMOOTH}, hp, Vector3.new(1.2,1.1,1.2)*s)
	-- floppy ears (flat, hanging at the sides)
	box(model,{Name="EarL",Color=Color3.fromRGB(150,100,55),Material=SMOOTH}, hp+Vector3.new(0.62,0.1,0)*s, Vector3.new(0.18,0.8,0.5)*s)
	box(model,{Name="EarR",Color=Color3.fromRGB(150,100,55),Material=SMOOTH}, hp+Vector3.new(-0.62,0.1,0)*s, Vector3.new(0.18,0.8,0.5)*s)
	-- snout + nose
	box(model,{Name="Snout",Color=color,Material=SMOOTH}, hp+Vector3.new(0,-0.15,-0.6)*s, Vector3.new(0.55,0.45,0.5)*s)
	ball(model,{Name="Nose",Color=Color3.new(0.05,0.05,0.05),Material=SMOOTH}, hp+Vector3.new(0,-0.1,-0.88)*s, 0.22*s)
	-- wagging tail
	box(model,{Name="Tail",Color=color,Material=SMOOTH}, Vector3.new(0,0.45,1.15)*s, Vector3.new(0.3,0.7,0.3)*s, CFrame.Angles(math.rad(-30),0,0))
	eyes(model, hp, s)
	return body
end

local function buildBunny(model, s, color, rColor)
	local body = ball(model,{Name="HumanoidRootPart",Color=color,Material=SMOOTH}, Vector3.new(0,0,0), 1.5*s)
	local hp = Vector3.new(0,0.6,-1.0)*s
	ball(model,{Name="Head",Color=color,Material=SMOOTH}, hp, 1.1*s)
	-- tall upright ears
	box(model,{Name="EarL",Color=color,Material=SMOOTH}, hp+Vector3.new(0.28,1.0,0)*s, Vector3.new(0.32,1.4,0.2)*s)
	box(model,{Name="EarR",Color=color,Material=SMOOTH}, hp+Vector3.new(-0.28,1.0,0)*s, Vector3.new(0.32,1.4,0.2)*s)
	box(model,{Name="EarInL",Color=Color3.fromRGB(255,190,200),Material=SMOOTH}, hp+Vector3.new(0.28,1.0,-0.08)*s, Vector3.new(0.16,1.1,0.12)*s)
	box(model,{Name="EarInR",Color=Color3.fromRGB(255,190,200),Material=SMOOTH}, hp+Vector3.new(-0.28,1.0,-0.08)*s, Vector3.new(0.16,1.1,0.12)*s)
	-- little feet + cotton tail
	box(model,{Name="FootL",Color=color,Material=SMOOTH}, Vector3.new(0.4,-0.7,-0.5)*s, Vector3.new(0.4,0.25,0.7)*s)
	box(model,{Name="FootR",Color=color,Material=SMOOTH}, Vector3.new(-0.4,-0.7,-0.5)*s, Vector3.new(0.4,0.25,0.7)*s)
	ball(model,{Name="CottonTail",Color=Color3.new(1,1,1),Material=SMOOTH}, Vector3.new(0,0,0.85)*s, 0.5*s)
	ball(model,{Name="Nose",Color=Color3.fromRGB(255,150,170),Material=SMOOTH}, hp+Vector3.new(0,-0.05,-0.55)*s, 0.16*s)
	eyes(model, hp, s, Color3.fromRGB(120,60,180))
	return body
end

local function buildBird(model, s, color, rColor, bigEyes)
	local body = ball(model,{Name="HumanoidRootPart",Color=color,Material=SMOOTH}, Vector3.new(0,0,0), 1.4*s)
	local hp = Vector3.new(0,0.85,-0.3)*s
	ball(model,{Name="Head",Color=color,Material=SMOOTH}, hp, 1.0*s)
	-- beak
	wedge(model,{Name="Beak",Color=Color3.fromRGB(255,180,40),Material=SMOOTH}, hp+Vector3.new(0,-0.05,-0.55)*s, Vector3.new(0.3,0.3,0.4)*s, CFrame.Angles(0,math.rad(180),0))
	-- stubby wings
	box(model,{Name="WingL",Color=color,Material=SMOOTH}, Vector3.new(0.78,0.05,0)*s, Vector3.new(0.18,0.9,0.9)*s, CFrame.Angles(0,0,math.rad(15)))
	box(model,{Name="WingR",Color=color,Material=SMOOTH}, Vector3.new(-0.78,0.05,0)*s, Vector3.new(0.18,0.9,0.9)*s, CFrame.Angles(0,0,math.rad(-15)))
	-- tail feathers
	box(model,{Name="TailF",Color=color,Material=SMOOTH}, Vector3.new(0,0.1,0.8)*s, Vector3.new(0.7,0.12,0.6)*s, CFrame.Angles(math.rad(20),0,0))
	-- little feet
	box(model,{Name="FootL",Color=Color3.fromRGB(255,180,40),Material=SMOOTH}, Vector3.new(0.3,-0.75,0)*s, Vector3.new(0.18,0.3,0.18)*s)
	box(model,{Name="FootR",Color=Color3.fromRGB(255,180,40),Material=SMOOTH}, Vector3.new(-0.3,-0.75,0)*s, Vector3.new(0.18,0.3,0.18)*s)
	if bigEyes then
		ball(model,{Name="EyeW",Color=Color3.new(1,1,1),Material=SMOOTH}, hp+Vector3.new(0.28,0.1,-0.42)*s, 0.5*s)
		ball(model,{Name="EyeW",Color=Color3.new(1,1,1),Material=SMOOTH}, hp+Vector3.new(-0.28,0.1,-0.42)*s, 0.5*s)
		ball(model,{Name="Eye",Color=Color3.fromRGB(255,180,40),Material=SMOOTH}, hp+Vector3.new(0.28,0.1,-0.6)*s, 0.26*s)
		ball(model,{Name="Eye",Color=Color3.fromRGB(255,180,40),Material=SMOOTH}, hp+Vector3.new(-0.28,0.1,-0.6)*s, 0.26*s)
	else
		eyes(model, hp, s)
	end
	return body
end

local function buildBear(model, s, color, rColor)
	local body = ball(model,{Name="HumanoidRootPart",Color=color,Material=SMOOTH}, Vector3.new(0,0,0), 1.9*s)
	legs(model, s, color, 1.7,1.7,1.9, 0.7)
	local hp = Vector3.new(0,0.75,-0.95)*s
	ball(model,{Name="Head",Color=color,Material=SMOOTH}, hp, 1.25*s)
	-- round ears
	ball(model,{Name="EarL",Color=Color3.new(0.1,0.1,0.1),Material=SMOOTH}, hp+Vector3.new(0.45,0.55,0)*s, 0.5*s)
	ball(model,{Name="EarR",Color=Color3.new(0.1,0.1,0.1),Material=SMOOTH}, hp+Vector3.new(-0.45,0.55,0)*s, 0.5*s)
	-- panda-style eye patches + snout
	ball(model,{Name="PatchL",Color=Color3.new(0.1,0.1,0.1),Material=SMOOTH}, hp+Vector3.new(0.3,0.05,-0.45)*s, 0.45*s)
	ball(model,{Name="PatchR",Color=Color3.new(0.1,0.1,0.1),Material=SMOOTH}, hp+Vector3.new(-0.3,0.05,-0.45)*s, 0.45*s)
	box(model,{Name="Snout",Color=Color3.new(1,1,1),Material=SMOOTH}, hp+Vector3.new(0,-0.25,-0.5)*s, Vector3.new(0.5,0.4,0.35)*s)
	ball(model,{Name="Nose",Color=Color3.new(0.05,0.05,0.05),Material=SMOOTH}, hp+Vector3.new(0,-0.2,-0.7)*s, 0.2*s)
	eyes(model, hp, s)
	return body
end

local function buildFox(model, s, color, rColor)
	local body = box(model,{Name="HumanoidRootPart",Color=color,Material=SMOOTH},
		Vector3.new(0,0,0), Vector3.new(1.2,1.0,2.0)*s)
	legs(model, s, Color3.new(0.12,0.12,0.14), 1.2,1.0,2.0, 0.8)
	local hp = Vector3.new(0,0.5,-1.15)*s
	box(model,{Name="Head",Color=color,Material=SMOOTH}, hp, Vector3.new(1.1,1.0,1.1)*s)
	wedge(model,{Name="Snout",Color=color,Material=SMOOTH}, hp+Vector3.new(0,-0.1,-0.7)*s, Vector3.new(0.5,0.4,0.6)*s, CFrame.Angles(0,math.rad(180),0))
	ball(model,{Name="Nose",Color=Color3.new(0.05,0.05,0.05),Material=SMOOTH}, hp+Vector3.new(0,-0.1,-1.0)*s, 0.16*s)
	wedge(model,{Name="EarL",Color=color,Material=SMOOTH}, hp+Vector3.new(0.35,0.65,0.1)*s, Vector3.new(0.4,0.7,0.3)*s)
	wedge(model,{Name="EarR",Color=color,Material=SMOOTH}, hp+Vector3.new(-0.35,0.65,0.1)*s, Vector3.new(0.4,0.7,0.3)*s)
	-- big bushy tail
	box(model,{Name="Tail1",Color=color,Material=SMOOTH}, Vector3.new(0,0.3,1.1)*s, Vector3.new(0.8,0.9,1.0)*s, CFrame.Angles(math.rad(-25),0,0))
	ball(model,{Name="TailTip",Color=Color3.new(1,1,1),Material=SMOOTH}, Vector3.new(0,0.8,1.5)*s, 0.7*s)
	eyes(model, hp, s, Color3.fromRGB(255,180,40))
	return body
end

local function buildWolf(model, s, color, rColor)
	local body = box(model,{Name="HumanoidRootPart",Color=color,Material=SMOOTH},
		Vector3.new(0,0,0), Vector3.new(1.5,1.3,2.3)*s)
	legs(model, s, color, 1.5,1.3,2.3, 1.0)
	box(model,{Name="Neck",Color=color,Material=SMOOTH}, Vector3.new(0,0.4,-1.0)*s, Vector3.new(0.8,0.9,0.8)*s)
	local hp = Vector3.new(0,0.7,-1.5)*s
	box(model,{Name="Head",Color=color,Material=SMOOTH}, hp, Vector3.new(1.2,1.1,1.3)*s)
	box(model,{Name="Snout",Color=color,Material=SMOOTH}, hp+Vector3.new(0,-0.15,-0.65)*s, Vector3.new(0.55,0.45,0.6)*s)
	ball(model,{Name="Nose",Color=Color3.new(0.04,0.04,0.04),Material=SMOOTH}, hp+Vector3.new(0,-0.12,-0.98)*s, 0.2*s)
	wedge(model,{Name="EarL",Color=color,Material=SMOOTH}, hp+Vector3.new(0.4,0.7,0.1)*s, Vector3.new(0.45,0.7,0.35)*s)
	wedge(model,{Name="EarR",Color=color,Material=SMOOTH}, hp+Vector3.new(-0.4,0.7,0.1)*s, Vector3.new(0.45,0.7,0.35)*s)
	box(model,{Name="Tail",Color=color,Material=SMOOTH}, Vector3.new(0,0.35,1.3)*s, Vector3.new(0.5,0.5,1.3)*s, CFrame.Angles(math.rad(-35),0,0))
	eyes(model, hp, s, Color3.fromRGB(255,220,60))
	if rColor then addGlow(body, rColor, 1) end
	return body
end

local function buildHorse(model, s, color, rColor, unicorn)
	local body = box(model,{Name="HumanoidRootPart",Color=color,Material=SMOOTH},
		Vector3.new(0,0,0), Vector3.new(1.4,1.5,2.4)*s)
	legs(model, s, color, 1.4,1.5,2.4, 1.2)
	box(model,{Name="Neck",Color=color,Material=SMOOTH}, Vector3.new(0,0.7,-1.0)*s, Vector3.new(0.8,1.3,0.8)*s, CFrame.Angles(math.rad(25),0,0))
	local hp = Vector3.new(0,1.3,-1.5)*s
	box(model,{Name="Head",Color=color,Material=SMOOTH}, hp, Vector3.new(0.9,0.9,1.4)*s)
	-- mane
	for i=0,3 do
		local mc = ({Color3.fromRGB(255,120,200),Color3.fromRGB(120,200,255),Color3.fromRGB(255,210,120)})[(i%3)+1]
		box(model,{Name="Mane",Color=mc,Material=unicorn and NEON or SMOOTH},
			Vector3.new(0,0.95-i*0.45,-1.0+i*0.0)*s, Vector3.new(0.4,0.5,0.25)*s)
	end
	-- tail
	box(model,{Name="Tail",Color=unicorn and (rColor or color) or color,Material=unicorn and NEON or SMOOTH},
		Vector3.new(0,0.2,1.25)*s, Vector3.new(0.35,1.4,0.35)*s, CFrame.Angles(math.rad(20),0,0))
	if unicorn then
		cyl(model,{Name="Horn",Color=rColor or Color3.new(1,1,1),Material=NEON}, hp+Vector3.new(0,0.7,-0.5)*s, Vector3.new(1.0,0.25,0.25)*s, CFrame.Angles(0,0,math.rad(90)))
		addGlow(body, rColor or Color3.fromRGB(200,150,255), 1.2)
		addAura(body, rColor or Color3.fromRGB(200,150,255), 12)
	end
	eyes(model, hp, s, Color3.fromRGB(120,70,180))
	return body
end

local function buildDragon(model, s, color, rColor)
	local body = box(model,{Name="HumanoidRootPart",Color=color,Material=SMOOTH},
		Vector3.new(0,0,0), Vector3.new(1.5,1.4,2.2)*s)
	legs(model, s, color, 1.5,1.4,2.2, 0.8)
	box(model,{Name="Neck",Color=color,Material=SMOOTH}, Vector3.new(0,0.5,-1.0)*s, Vector3.new(0.9,1.0,0.9)*s, CFrame.Angles(math.rad(20),0,0))
	local hp = Vector3.new(0,1.0,-1.5)*s
	box(model,{Name="Head",Color=color,Material=SMOOTH}, hp, Vector3.new(1.1,1.0,1.4)*s)
	-- horns
	wedge(model,{Name="HornL",Color=Color3.fromRGB(60,55,80),Material=SMOOTH}, hp+Vector3.new(0.3,0.6,0.2)*s, Vector3.new(0.22,0.7,0.22)*s)
	wedge(model,{Name="HornR",Color=Color3.fromRGB(60,55,80),Material=SMOOTH}, hp+Vector3.new(-0.3,0.6,0.2)*s, Vector3.new(0.22,0.7,0.22)*s)
	-- wings (angled flat slabs)
	box(model,{Name="WingL",Color=color,Material=SMOOTH}, Vector3.new(1.4,0.6,0.2)*s, Vector3.new(2.4,0.12,1.8)*s, CFrame.Angles(0,0,math.rad(35)))
	box(model,{Name="WingR",Color=color,Material=SMOOTH}, Vector3.new(-1.4,0.6,0.2)*s, Vector3.new(2.4,0.12,1.8)*s, CFrame.Angles(0,0,math.rad(-35)))
	box(model,{Name="WingLNeon",Color=rColor or color,Material=NEON}, Vector3.new(1.4,0.55,0.2)*s, Vector3.new(2.2,0.06,1.6)*s, CFrame.Angles(0,0,math.rad(35)))
	box(model,{Name="WingRNeon",Color=rColor or color,Material=NEON}, Vector3.new(-1.4,0.55,0.2)*s, Vector3.new(2.2,0.06,1.6)*s, CFrame.Angles(0,0,math.rad(-35)))
	-- spine spikes
	for i=0,3 do
		wedge(model,{Name="Spine",Color=rColor or color,Material=NEON}, Vector3.new(0,0.75,-0.4+i*0.6)*s, Vector3.new(0.18,0.45,0.3)*s)
	end
	-- tail
	box(model,{Name="Tail1",Color=color,Material=SMOOTH}, Vector3.new(0,0.2,1.2)*s, Vector3.new(0.6,0.6,1.2)*s)
	wedge(model,{Name="TailTip",Color=rColor or color,Material=NEON}, Vector3.new(0,0.2,1.95)*s, Vector3.new(0.5,0.7,0.6)*s)
	addGlow(body, rColor or Color3.fromRGB(255,100,0), 1.2)
	addAura(body, rColor or color, 14)
	eyes(model, hp, s, Color3.fromRGB(255,60,60))
	return body
end

local function buildPhoenix(model, s, color, rColor)
	local body = ball(model,{Name="HumanoidRootPart",Color=color,Material=NEON}, Vector3.new(0,0,0), 1.5*s)
	local hp = Vector3.new(0,0.9,-0.5)*s
	ball(model,{Name="Head",Color=color,Material=NEON}, hp, 1.0*s)
	wedge(model,{Name="Beak",Color=Color3.fromRGB(255,200,60),Material=SMOOTH}, hp+Vector3.new(0,-0.05,-0.55)*s, Vector3.new(0.28,0.3,0.4)*s, CFrame.Angles(0,math.rad(180),0))
	-- crest
	for i=0,2 do
		wedge(model,{Name="Crest",Color=rColor or color,Material=NEON}, hp+Vector3.new(0,0.55+i*0.15,0.1+i*0.05)*s, Vector3.new(0.2,0.5+i*0.15,0.15)*s)
	end
	-- big spread wings
	box(model,{Name="WingL",Color=color,Material=NEON}, Vector3.new(1.7,0.3,0.1)*s, Vector3.new(3.0,0.14,2.0)*s, CFrame.Angles(0,0,math.rad(20)))
	box(model,{Name="WingR",Color=color,Material=NEON}, Vector3.new(-1.7,0.3,0.1)*s, Vector3.new(3.0,0.14,2.0)*s, CFrame.Angles(0,0,math.rad(-20)))
	box(model,{Name="WingLTip",Color=rColor or Color3.new(1,1,1),Material=NEON}, Vector3.new(2.6,0.5,0.1)*s, Vector3.new(1.4,0.1,1.6)*s, CFrame.Angles(0,0,math.rad(20)))
	box(model,{Name="WingRTip",Color=rColor or Color3.new(1,1,1),Material=NEON}, Vector3.new(-2.6,0.5,0.1)*s, Vector3.new(1.4,0.1,1.6)*s, CFrame.Angles(0,0,math.rad(-20)))
	-- tail feathers
	for i=-1,1 do
		box(model,{Name="TailF",Color=(i==0) and (rColor or color) or color,Material=NEON}, Vector3.new(i*0.3,0.1,1.0)*s, Vector3.new(0.2,0.2,1.4+math.abs(i)*0.3)*s, CFrame.Angles(math.rad(18),0,0))
	end
	addGlow(body, rColor or Color3.fromRGB(255,120,0), 2)
	addAura(body, Color3.fromRGB(255,120,0), 24)
	eyes(model, hp, s, Color3.fromRGB(255,240,60))
	return body
end

local function buildGriffin(model, s, color, rColor)
	local body = box(model,{Name="HumanoidRootPart",Color=color,Material=SMOOTH},
		Vector3.new(0,0,0), Vector3.new(1.4,1.3,2.1)*s)
	legs(model, s, Color3.fromRGB(220,180,80), 1.4,1.3,2.1, 0.9)
	local hp = Vector3.new(0,0.7,-1.25)*s
	ball(model,{Name="Head",Color=color,Material=SMOOTH}, hp, 1.1*s)
	wedge(model,{Name="Beak",Color=Color3.fromRGB(255,200,60),Material=SMOOTH}, hp+Vector3.new(0,-0.1,-0.6)*s, Vector3.new(0.3,0.35,0.5)*s, CFrame.Angles(0,math.rad(180),0))
	wedge(model,{Name="EarL",Color=color,Material=SMOOTH}, hp+Vector3.new(0.3,0.6,0.1)*s, Vector3.new(0.3,0.5,0.25)*s)
	wedge(model,{Name="EarR",Color=color,Material=SMOOTH}, hp+Vector3.new(-0.3,0.6,0.1)*s, Vector3.new(0.3,0.5,0.25)*s)
	box(model,{Name="WingL",Color=color,Material=SMOOTH}, Vector3.new(1.5,0.5,0.1)*s, Vector3.new(2.6,0.12,1.8)*s, CFrame.Angles(0,0,math.rad(28)))
	box(model,{Name="WingR",Color=color,Material=SMOOTH}, Vector3.new(-1.5,0.5,0.1)*s, Vector3.new(2.6,0.12,1.8)*s, CFrame.Angles(0,0,math.rad(-28)))
	box(model,{Name="Tail",Color=Color3.fromRGB(220,180,80),Material=SMOOTH}, Vector3.new(0,0.2,1.2)*s, Vector3.new(0.35,0.35,1.0)*s)
	if rColor then addGlow(body, rColor, 1); addAura(body, rColor, 16) end
	eyes(model, hp, s, Color3.fromRGB(255,200,60))
	return body
end

local function buildSerpent(model, s, color, rColor)
	local body = box(model,{Name="HumanoidRootPart",Color=color,Material=SMOOTH},
		Vector3.new(0,0,0), Vector3.new(1.2,1.2,1.6)*s)
	-- segmented tail trailing behind, shrinking
	for i=1,6 do
		local seg = 1 - i*0.12
		box(model,{Name="Seg",Color=color,Material=SMOOTH},
			Vector3.new(0, math.sin(i*0.9)*0.3, 0.9+ (i-1)*0.85)*s,
			Vector3.new(1.1*seg,1.1*seg,0.9)*s)
	end
	local hp = Vector3.new(0,0.3,-1.1)*s
	box(model,{Name="Head",Color=color,Material=SMOOTH}, hp, Vector3.new(1.4,1.0,1.5)*s)
	-- cobra frill
	wedge(model,{Name="FrillL",Color=rColor or color,Material=NEON}, hp+Vector3.new(0.7,0.1,0.2)*s, Vector3.new(0.1,1.0,0.9)*s, CFrame.Angles(0,0,math.rad(-90)))
	wedge(model,{Name="FrillR",Color=rColor or color,Material=NEON}, hp+Vector3.new(-0.7,0.1,0.2)*s, Vector3.new(0.1,1.0,0.9)*s, CFrame.Angles(0,0,math.rad(90)))
	addGlow(body, rColor or Color3.fromRGB(140,60,255), 1.5)
	addAura(body, rColor or Color3.fromRGB(140,60,255), 22)
	eyes(model, hp, s, rColor or Color3.fromRGB(180,80,255))
	return body
end

local function buildGeneric(model, s, color, rColor)
	local body = ball(model,{Name="HumanoidRootPart",Color=color,Material=SMOOTH}, Vector3.new(0,0,0), 1.6*s)
	local hp = Vector3.new(0,0.7,-0.7)*s
	ball(model,{Name="Head",Color=color,Material=SMOOTH}, hp, 1.1*s)
	box(model,{Name="FootL",Color=color,Material=SMOOTH}, Vector3.new(0.45,-0.7,-0.2)*s, Vector3.new(0.4,0.3,0.6)*s)
	box(model,{Name="FootR",Color=color,Material=SMOOTH}, Vector3.new(-0.45,-0.7,-0.2)*s, Vector3.new(0.4,0.3,0.6)*s)
	if rColor then addGlow(body, rColor, 1); addAura(body, rColor, 8) end
	eyes(model, hp, s)
	return body
end

-- ============================================================
-- NAME -> BUILDER
-- ============================================================
local builders = {
	Kitten             = buildCat,
	Puppy              = buildDog,
	Bunny              = buildBunny,
	Chick              = function(m,s,c,r) return buildBird(m,s,c,r,false) end,
	Owl                = function(m,s,c,r) return buildBird(m,s,c,r,true)  end,
	Fox                = buildFox,
	Wolf               = buildWolf,
	Panda              = buildBear,
	Tiger              = buildCat,
	["Snow Leopard"]   = buildCat,
	Dragon             = buildDragon,
	Phoenix            = buildPhoenix,
	Kirin              = function(m,s,c,r) return buildHorse(m,s,c,r,true) end,
	Unicorn            = function(m,s,c,r) return buildHorse(m,s,c,r,true) end,
	["Cosmic Griffin"] = buildGriffin,
	["Shadow Wolf"]    = buildWolf,
	["Celestial Dragon"]= buildDragon,
	["Star Phoenix"]   = buildPhoenix,
	["Void Serpent"]   = buildSerpent,
}

-- ============================================================
-- PUBLIC
-- ============================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Turn an imported mesh (MeshPart or Model) into a movable pet:
-- anchor every part, pick a root, name it HumanoidRootPart, set PrimaryPart.
local function normalizeTemplate(inst)
	local model
	if inst:IsA("Model") then
		model = inst
	else
		model = Instance.new("Model")
		inst.Parent = model
	end
	-- Safety: strip any scripts / humanoids that ship inside Toolbox models
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Humanoid") or d:IsA("AnimationController") then
			d:Destroy()
		end
	end
	-- prep all parts
	local hasPart = false
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true; d.CanCollide = false; d.CastShadow = false; d.Massless = true
			hasPart = true
		end
	end
	if not hasPart then return nil end

	-- bounding box BEFORE adding our own root
	local bbCF, bbSize
	pcall(function() bbCF, bbSize = model:GetBoundingBox() end)
	local center = (bbCF and bbCF.Position) or Vector3.new()
	bbSize = bbSize or Vector3.new(3,3,3)

	-- a clean, UPRIGHT, centered root so the model isn't tilted by a random part
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"; root.Size = Vector3.new(0.4,0.4,0.4)
	root.Transparency = 1; root.CanCollide = false; root.Anchored = true; root.Massless = true
	root.CFrame = CFrame.new(center)
	root.Parent = model
	model.PrimaryPart = root

	-- scale to a consistent size
	local biggest = math.max(bbSize.X, bbSize.Y, bbSize.Z)
	if biggest > 0.01 then pcall(function() model:ScaleTo(1.6 / biggest) end) end  -- small pet-sim size
	return model, root
end

local function addNameTag(model, root, petData, rarityInfo, s, mut)
	local rColor = rarityInfo and rarityInfo.color or Color3.fromRGB(200,200,200)
	local bb = Instance.new("BillboardGui")
	bb.Size=UDim2.new(0,160,0,52); bb.StudsOffset=Vector3.new(0,2.6*s,0)
	bb.MaxDistance=20; bb.Adornee=root; bb.AlwaysOnTop=false; bb.Parent=model
	local n=Instance.new("TextLabel"); n.Size=UDim2.new(1,0,0.58,0); n.BackgroundTransparency=1
	n.Text=(mut and (mut.emoji.." "..mut.name.." ") or "")..petData.name
	n.TextColor3=(mut and mut.color) or rColor; n.TextScaled=true; n.Font=Enum.Font.GothamBold
	n.TextStrokeTransparency=0.3; n.TextStrokeColor3=Color3.new(0,0,0); n.Parent=bb
	local r=Instance.new("TextLabel"); r.Size=UDim2.new(1,0,0.42,0); r.Position=UDim2.new(0,0,0.58,0)
	r.BackgroundTransparency=1; r.Text=(rarityInfo and (rarityInfo.displayName or rarityInfo.name)) or petData.rarity
	r.TextColor3=rColor; r.TextScaled=true; r.Font=Enum.Font.Gotham
	r.TextStrokeTransparency=0.4; r.TextStrokeColor3=Color3.new(0,0,0); r.Parent=bb
end

function PetModels.Build(petData, uniqueId, rarityInfo, mut)
	local s = petData.size or 1.0
	local rColor = rarityInfo and rarityInfo.color or Color3.fromRGB(200,200,200)

	local model, root
	-- 1) Use a custom imported Blender mesh if one exists:
	--    ReplicatedStorage/PetMeshes/<PetName>  (MeshPart or Model)
	local folder = ReplicatedStorage:FindFirstChild("PetMeshes")
		or workspace:FindFirstChild("PetMeshes")
		or workspace:FindFirstChild("PetMashes")
	-- Some pets use a differently-named model (e.g. Void Serpent is a snake).
	local MESH_OVERRIDE = { ["Void Serpent"] = "desert snake" }
	local template
	if folder then
		local want = MESH_OVERRIDE[petData.name] or petData.name
		template = folder:FindFirstChild(want)
	end
	if template then
		model, root = normalizeTemplate(template:Clone())
	end
	-- 2) Otherwise fall back to the procedural part model
	if not model then
		model = Instance.new("Model")
		local builder = builders[petData.name] or buildGeneric
		root = builder(model, s, petData.color, rColor)
	end

	model.Name = petData.name .. "_" .. uniqueId
	addNameTag(model, root, petData, rarityInfo, s, mut)
	-- mutation sparkle effect
	if mut and root then
		local att = Instance.new("Attachment"); att.Parent = root
		local pe = Instance.new("ParticleEmitter"); pe.Parent = att
		pe.Color = ColorSequence.new(mut.color); pe.LightEmission = 0.7
		pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0,0.45),NumberSequenceKeypoint.new(1,0)})
		pe.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,0.2),NumberSequenceKeypoint.new(1,1)})
		pe.Lifetime = NumberRange.new(0.6,1.1); pe.Rate = 16; pe.Speed = NumberRange.new(1,2.5)
		pe.SpreadAngle = Vector2.new(180,180); pe.Rotation = NumberRange.new(0,360)
	end
	model.PrimaryPart = root
	return model, root
end

return PetModels
