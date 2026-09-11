-- StarPets: MapProps.lua
-- Place in: ServerScriptService > Server > MapProps (ModuleScript)
--
-- What each world is made of.
--
-- WHAT THIS REPLACES
--
-- Every world was one flat coloured slab with props thrown across it by
-- uniform math.random, and each world had one prop shape. Forest: a trunk and
-- a ball. Desert: a green BOX, called Cactus. Volcano: rocks and flat discs.
-- Space: neon balls floating between five and twenty-six studs in the air, so
-- the surface a player actually walks on had nothing on it whatsoever.
--
-- Three things make the difference between that and terrain:
--
--   CLUSTERS, NOT SCATTER. Uniform random reads as noise; clumps read as
--   terrain, because real landscape is uneven — a stand of trees, then a
--   clearing. Same part count, completely different impression.
--
--   SEVERAL FEATURES PER WORLD, not one. A world with one prop repeated is a
--   pattern. Four features that share a palette is a place.
--
--   THINGS ON THE GROUND. A prop at eye level is worth ten in the sky,
--   because the player is standing on the floor looking across it.
--
-- Every prop is built through the ctx.part factory the caller supplies, so
-- everything lands in the map folder and carries the same stamp as the rest of
-- the map. This module never touches Workspace directly.

local MapProps = {}

local function C(r, g, b) return Color3.fromRGB(r, g, b) end

local function shade(c, f)
	return Color3.fromRGB(
		math.clamp(math.floor(c.R * 255 * f), 0, 255),
		math.clamp(math.floor(c.G * 255 * f), 0, 255),
		math.clamp(math.floor(c.B * 255 * f), 0, 255))
end

-- ============================================================
-- SHAPE HELPERS
-- ============================================================
local function box(ctx, name, pos, size, color, mat, extra)
	local p = { Name = name, Size = size, Position = pos, Color = color,
		Material = mat or Enum.Material.SmoothPlastic }
	if extra then for k, v in pairs(extra) do p[k] = v end end
	return ctx.part(p)
end

local function ball(ctx, name, pos, size, color, mat, extra)
	local p = { Name = name, Shape = Enum.PartType.Ball, Size = size,
		Position = pos, Color = color, Material = mat or Enum.Material.SmoothPlastic }
	if extra then for k, v in pairs(extra) do p[k] = v end end
	return ctx.part(p)
end

-- A Roblox cylinder runs along its own LOCAL X axis, so standing one upright
-- needs Orientation (0,0,90). Anything wanting a lean must ADD to that 90 —
-- passing a bare angle REPLACES it and lays the part flat on the ground. That
-- mistake has produced both flat tree trunks and a horizontal log skewered
-- through every cactus in a previous version of this game, so it is spelled out
-- here rather than left to be rediscovered.
local function column(ctx, name, pos, radius, height, color, mat, extra)
	local p = { Name = name, Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2), Position = pos,
		Orientation = Vector3.new(0, 0, 90), Color = color,
		Material = mat or Enum.Material.SmoothPlastic }
	if extra then for k, v in pairs(extra) do p[k] = v end end
	return ctx.part(p)
end

local function disc(ctx, name, pos, radius, thick, color, mat, extra)
	local p = { Name = name, Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thick, radius * 2, radius * 2), Position = pos,
		Orientation = Vector3.new(0, 0, 90), Color = color,
		Material = mat or Enum.Material.SmoothPlastic }
	if extra then for k, v in pairs(extra) do p[k] = v end end
	return ctx.part(p)
end

-- ============================================================
-- PROP SETS
-- ============================================================
MapProps.SETS = {}

local MEADOW_GREENS = { C(96, 176, 82), C(74, 156, 68), C(120, 190, 96), C(64, 138, 74) }
local BLOOMS = { C(250, 214, 96), C(244, 128, 168), C(160, 150, 236), C(248, 246, 240) }

function MapProps.SETS.meadow(ctx, x, z, y, i)
	local leaf = MEADOW_GREENS[(i % #MEADOW_GREENS) + 1]
	local kind = i % 4

	if kind == 0 then
		-- A round meadow oak: broad and low, deliberately unlike the Forest
		-- conifers next door so the two skylines cannot be confused.
		local h = 13 + (i % 3) * 4
		column(ctx, "Trunk", Vector3.new(x, y + h * 0.5, z), 1.6, h,
			C(132, 100, 68), Enum.Material.Wood,
			{ Orientation = Vector3.new(0, 0, 90 + ((i % 5) - 2) * 0.8) })
		for k, L in ipairs({ { 0, 3.6, 0, 16, 11 }, { -4, 2.2, 2.2, 11, 8 },
			{ 4, 2.5, -1.8, 10, 7 } }) do
			ball(ctx, "Leaves", Vector3.new(x + L[1], y + h + L[2], z + L[3]),
				Vector3.new(L[4], L[5], L[4]), shade(leaf, 0.9 + k * 0.06),
				Enum.Material.Grass, { CanCollide = false })
		end
	elseif kind == 1 then
		-- Wildflowers: the only non-green in the world, and what stops a field
		-- of bushes reading as flat texture.
		ball(ctx, "Bush", Vector3.new(x, y + 1.4, z), Vector3.new(6.5, 4.2, 6.5),
			shade(leaf, 0.96), Enum.Material.Grass, { CanCollide = false })
		for k = 0, 4 do
			local a = (k / 5) * math.pi * 2 + i
			local fx, fz = x + math.cos(a) * 4.2, z + math.sin(a) * 4.2
			column(ctx, "Stem", Vector3.new(fx, y + 1.1, fz), 0.16, 2.2,
				shade(leaf, 1.1), Enum.Material.Grass, { CanCollide = false })
			ball(ctx, "Bloom", Vector3.new(fx, y + 2.4, fz),
				Vector3.new(1.4, 1.0, 1.4), BLOOMS[((i + k) % #BLOOMS) + 1],
				nil, { CanCollide = false })
		end
	elseif kind == 2 then
		-- Tall grass. Cheap, and it is what makes ground look grown rather
		-- than painted.
		for k = 0, 6 do
			local a = (k / 7) * math.pi * 2 + i * 0.7
			local r = 1.4 + (k % 3) * 1.2
			box(ctx, "Tuft",
				Vector3.new(x + math.cos(a) * r, y + 1.7 + (k % 3) * 0.5,
					z + math.sin(a) * r),
				Vector3.new(0.32, 3.4 + (k % 3) * 1.1, 0.32),
				shade(leaf, 1.02 + (k % 3) * 0.06), Enum.Material.Grass,
				{ CanCollide = false })
		end
	else
		ball(ctx, "Boulder", Vector3.new(x, y + 1.5, z), Vector3.new(8, 4.8, 6.5),
			C(138, 136, 128), Enum.Material.Rock, { CanCollide = false })
		ball(ctx, "Boulder", Vector3.new(x + 5, y + 0.9, z - 3.2),
			Vector3.new(4.2, 2.8, 3.8), C(120, 118, 112), Enum.Material.Rock,
			{ CanCollide = false })
		ball(ctx, "Moss", Vector3.new(x - 1, y + 3.4, z + 1),
			Vector3.new(4.8, 1.5, 4.2), shade(leaf, 1.05), Enum.Material.Grass,
			{ CanCollide = false })
	end
end

local FOREST_GREENS = { C(38, 104, 46), C(28, 86, 38), C(52, 124, 56), C(44, 96, 50) }
local BARKS = { C(84, 60, 40), C(68, 48, 34), C(96, 72, 48) }

function MapProps.SETS.forest(ctx, x, z, y, i)
	local leaf = FOREST_GREENS[(i % #FOREST_GREENS) + 1]
	local bark = BARKS[(i % #BARKS) + 1]
	local kind = i % 3
	-- Degrees of lean, ADDED to the 90 that stands the cylinder up.
	local lean = ((i % 7) - 3) * 0.9

	if kind == 0 then
		-- Conifer: a stack of narrowing cones. Gives the treeline a jagged top
		-- edge rather than a level one.
		local h = 22 + (i % 4) * 6
		column(ctx, "Trunk", Vector3.new(x, y + h * 0.42, z), 1.4, h * 0.84, bark,
			Enum.Material.Wood, { Orientation = Vector3.new(0, 0, 90 + lean) })
		for k = 0, 3 do
			local t = k / 3
			ball(ctx, "Needles", Vector3.new(x, y + h * 0.52 + k * (h * 0.16), z),
				Vector3.new(15 - t * 10, 10 - t * 4.5, 15 - t * 10),
				shade(leaf, 0.9 + k * 0.06), Enum.Material.Grass,
				{ CanCollide = false })
		end
	elseif kind == 1 then
		-- Sapling: low and wide. Breaks up the bare band at eye level that a
		-- forest of tall trunks otherwise leaves.
		local h = 10 + (i % 3) * 3
		column(ctx, "Trunk", Vector3.new(x, y + h * 0.5, z), 1.0, h, bark,
			Enum.Material.Wood, { Orientation = Vector3.new(0, 0, 90 + lean * 1.6) })
		ball(ctx, "Leaves", Vector3.new(x, y + h + 2.2, z), Vector3.new(12, 8, 12),
			shade(leaf, 1.06), Enum.Material.Grass, { CanCollide = false })
		ball(ctx, "Leaves", Vector3.new(x + 2.8, y + h + 0.4, z - 1.8),
			Vector3.new(7.5, 6, 7.5), shade(leaf, 0.92), Enum.Material.Grass,
			{ CanCollide = false })
	else
		-- Broadleaf: a crown of offset lobes, so the silhouette is irregular
		-- rather than a sphere on a stick.
		local h = 19 + (i % 4) * 6
		column(ctx, "Trunk", Vector3.new(x, y + h * 0.5, z), 1.9, h, bark,
			Enum.Material.Wood, { Orientation = Vector3.new(0, 0, 90 + lean) })
		column(ctx, "TrunkFlare", Vector3.new(x, y + 1.5, z), 2.8, 3, bark,
			Enum.Material.Wood)
		for k, L in ipairs({ { 0, 4.2, 0, 17, 12 }, { -4.5, 2.4, 2.8, 12, 9 },
			{ 5, 3, -2.2, 11, 8 }, { 1.4, 6.8, 1.4, 12, 8 } }) do
			ball(ctx, "Leaves", Vector3.new(x + L[1], y + h + L[2], z + L[3]),
				Vector3.new(L[4], L[5], L[4]), shade(leaf, 0.88 + k * 0.05),
				Enum.Material.Grass, { CanCollide = false })
		end
	end

	-- Ground cover. The floor between the trees being bare is what made the
	-- old version look like a model rather than a place.
	if i % 2 == 0 then
		ball(ctx, "Fern", Vector3.new(x + 5.5, y + 1, z + 3.5),
			Vector3.new(5, 2.4, 5), shade(leaf, 1.14), Enum.Material.Grass,
			{ CanCollide = false })
	end
	if i % 3 == 0 then
		ball(ctx, "Rock", Vector3.new(x - 6, y + 0.8, z - 4.5),
			Vector3.new(4.2, 2.6, 3.6), C(128, 126, 120), Enum.Material.Rock,
			{ CanCollide = false })
	end
	if i % 4 == 1 then
		column(ctx, "MushStem", Vector3.new(x + 3.5, y + 0.7, z - 5), 0.35, 1.4,
			C(226, 216, 196), nil, { CanCollide = false })
		ball(ctx, "MushCap", Vector3.new(x + 3.5, y + 1.5, z - 5),
			Vector3.new(2.2, 1.4, 2.2), C(206, 68, 62), nil, { CanCollide = false })
	end
end

function MapProps.SETS.desert(ctx, x, z, y, i)
	local kind = i % 4
	local FLESH = C(62, 122, 66)
	local SAND = C(224, 196, 132)
	local STONE = C(196, 152, 96)

	if kind == 0 then
		-- A saguaro. The old "cactus" was a plain green box; real arms go OUT
		-- and then UP, which is two parts and an elbow, and it is the whole
		-- difference between a cactus and a rectangle.
		local h = 14 + (i % 3) * 5
		column(ctx, "Cactus", Vector3.new(x, y + h * 0.5, z), 2.1, h, FLESH,
			Enum.Material.Grass)
		ball(ctx, "CactusCap", Vector3.new(x, y + h, z), Vector3.new(4.2, 2.8, 4.2),
			shade(FLESH, 1.08), Enum.Material.Grass, { CanCollide = false })
		for k = 0, (i % 2) do
			local sx = (k == 0) and 1 or -1
			local ay = y + h * (0.52 + k * 0.16)
			local reach = 5
			box(ctx, "CactusArm", Vector3.new(x + sx * reach * 0.5, ay, z),
				Vector3.new(reach, 2.4, 2.4), FLESH, Enum.Material.Grass,
				{ CanCollide = false })
			local rise = 5.5 + (i % 3) * 2
			column(ctx, "CactusArmUp",
				Vector3.new(x + sx * reach, ay + rise * 0.5 - 0.8, z),
				1.2, rise, FLESH, Enum.Material.Grass, { CanCollide = false })
			ball(ctx, "CactusArmTip", Vector3.new(x + sx * reach, ay + rise - 0.8, z),
				Vector3.new(2.4, 1.7, 2.4), shade(FLESH, 1.08),
				Enum.Material.Grass, { CanCollide = false })
		end
	elseif kind == 1 then
		-- A dune RIDGE: overlapping crests of falling size with a darker lee
		-- face, so the sand has a direction the wind came from.
		for k = 0, 3 do
			local w = 22 - k * 4
			ball(ctx, "Dune", Vector3.new(x + k * 7.5, y + 0.5 + k * 0.3, z - k * 4),
				Vector3.new(w, 4 + k * 0.7, w * 0.78), shade(SAND, 1 - k * 0.03),
				Enum.Material.Sand, { CanCollide = false })
		end
		ball(ctx, "DuneShade", Vector3.new(x + 5, y + 0.4, z + 7.5),
			Vector3.new(20, 2.6, 12), shade(SAND, 0.88), Enum.Material.Sand,
			{ CanCollide = false })
	elseif kind == 2 then
		-- A banded sandstone mesa. Horizontal strata in slightly different
		-- tones is the entire visual identity of desert rock, and it costs
		-- four boxes of decreasing width.
		for k = 0, 3 do
			local w = 15 - k * 2.2
			box(ctx, "Mesa", Vector3.new(x, y + 2 + k * 3.8, z),
				Vector3.new(w, 3.8, w * 0.85), shade(STONE, 0.9 + k * 0.05),
				Enum.Material.Sandstone)
		end
		box(ctx, "MesaCap", Vector3.new(x, y + 17, z), Vector3.new(10, 1.6, 8.5),
			shade(STONE, 1.1), Enum.Material.Sandstone)
		ball(ctx, "Boulder", Vector3.new(x + 10, y + 1.4, z + 6),
			Vector3.new(5.5, 3.4, 4.8), shade(STONE, 0.85), Enum.Material.Rock,
			{ CanCollide = false })
	else
		-- A palm, in two frond segments so it droops instead of sticking out
		-- like a green sword.
		local h = 15 + (i % 3) * 4
		for k = 0, 3 do
			column(ctx, "PalmTrunk",
				Vector3.new(x + k * 0.4, y + 2 + k * (h / 4.4), z),
				0.95 - k * 0.07, h / 4, C(150, 116, 78), Enum.Material.Wood,
				{ Orientation = Vector3.new(0, 0, 90 + (k + 1) * 2.4) })
		end
		for k = 0, 6 do
			local a = (k / 7) * math.pi * 2
			local ca, sa = math.cos(a), math.sin(a)
			box(ctx, "Frond", Vector3.new(x + 1.6 + ca * 3, y + h + 0.8, z + sa * 3),
				Vector3.new(6, 0.45, 3.2), C(74, 132, 66), Enum.Material.Grass,
				{ CanCollide = false, Orientation = Vector3.new(0, math.deg(a), -12) })
			box(ctx, "FrondTip", Vector3.new(x + 1.6 + ca * 6.8, y + h - 1.2, z + sa * 6.8),
				Vector3.new(5, 0.4, 2.4), shade(C(74, 132, 66), 0.88),
				Enum.Material.Grass,
				{ CanCollide = false, Orientation = Vector3.new(0, math.deg(a), -46) })
		end
	end

	if i % 2 == 0 then
		for k = 0, 2 do
			box(ctx, "SandRipple", Vector3.new(x + 7, y + 0.25, z - 5 + k * 3),
				Vector3.new(11, 0.3, 1.2), shade(SAND, 0.94), Enum.Material.Sand,
				{ CanCollide = false,
				  Orientation = Vector3.new(0, (i * 23) % 60 - 30, 0) })
		end
	end
end

function MapProps.SETS.volcano(ctx, x, z, y, i)
	local kind = i % 4

	if kind == 0 then
		-- A lava pool with a cooled crust around it. The bare disc the old
		-- version used looked painted on; the crust is what sits it IN the
		-- ground.
		disc(ctx, "LavaCrust", Vector3.new(x, y + 0.6, z), 9.5, 0.9, C(38, 24, 22))
		disc(ctx, "LavaPool", Vector3.new(x, y + 0.9, z), 7, 1,
			C(255, 96, 20), Enum.Material.Neon, { CanCollide = false })
	elseif kind == 1 then
		-- Basalt columns. Volcanic rock genuinely fractures into uneven
		-- vertical pillars, and a cluster reads as terrain where a lump does
		-- not.
		for k = 0, 4 do
			local a = (k / 5) * math.pi * 2 + i
			local r = 2.4 + (k % 3) * 1.6
			local h = 6 + ((i + k) % 5) * 3.2
			column(ctx, "Basalt",
				Vector3.new(x + math.cos(a) * r, y + h * 0.5, z + math.sin(a) * r),
				2, h, shade(C(52, 36, 33), 0.86 + (k % 3) * 0.1),
				Enum.Material.Basalt)
		end
	elseif kind == 2 then
		-- A tree that burned. Nothing says the ground here used to be alive
		-- like the shape of a tree with no leaves on it.
		local h = 12 + (i % 3) * 4
		column(ctx, "CharTrunk", Vector3.new(x, y + h * 0.5, z), 1.2, h,
			C(34, 26, 24), Enum.Material.Wood,
			{ Orientation = Vector3.new(0, 0, 90 + ((i % 5) - 2) * 2.4) })
		for k = 0, 2 do
			local a = math.rad(k * 120 + i * 20)
			box(ctx, "CharBranch",
				Vector3.new(x + math.cos(a) * 3, y + h * 0.72 + k * 2,
					z + math.sin(a) * 3),
				Vector3.new(6, 0.6, 0.6), C(30, 23, 21), Enum.Material.Wood,
				{ CanCollide = false,
				  Orientation = Vector3.new(0, math.deg(a), 14) })
		end
		disc(ctx, "AshRing", Vector3.new(x, y + 0.3, z), 6, 0.4, C(122, 112, 106),
			nil, { CanCollide = false })
	else
		-- Obsidian: angular, near-black, glassy. The only sharp silhouette in
		-- a world otherwise made of domes.
		for k = 0, 3 do
			local a = (k / 4) * math.pi * 2 + i * 0.6
			local h = 8 + ((i + k) % 4) * 3.5
			box(ctx, "Obsidian",
				Vector3.new(x + math.cos(a) * 3, y + h * 0.5, z + math.sin(a) * 3),
				Vector3.new(3, h, 3), C(24, 18, 26), Enum.Material.Glass,
				{ Orientation = Vector3.new((k % 2) * 9 - 4, math.deg(a),
					(k % 3) * 7 - 7) })
		end
	end

	if i % 2 == 0 then
		disc(ctx, "AshPatch", Vector3.new(x + 6, y + 0.25, z - 5), 5.5, 0.35,
			C(134, 124, 118), nil, { CanCollide = false })
	end
	if i % 3 == 1 then
		-- A crack with light coming up through it. One thin part, and it makes
		-- the ground look like there is something underneath it.
		box(ctx, "Fissure", Vector3.new(x - 7, y + 0.3, z + 4.5),
			Vector3.new(10, 0.35, 1), C(230, 92, 26), Enum.Material.Neon,
			{ CanCollide = false, Orientation = Vector3.new(0, (i * 37) % 180, 0) })
	end
end

function MapProps.SETS.space(ctx, x, z, y, i)
	-- EVERY PROP IN THIS WORLD USED TO FLOAT.
	--
	-- Neon balls between five and twenty-six studs up, and nothing at all on
	-- the ground — so the surface a player walks across was an empty plane with
	-- specks hanging above it. A prop at eye level is worth ten in the sky.
	local kind = i % 4
	local REGOLITH = C(150, 152, 166)
	local DARKROCK = C(86, 88, 102)

	if kind == 0 then
		-- An impact crater: raised rim, sunken floor, ejecta thrown out around
		-- it. The most recognisable thing a moon has, and it costs three parts.
		disc(ctx, "CraterRim", Vector3.new(x, y + 0.5, z), 14, 1.2, REGOLITH)
		disc(ctx, "CraterFloor", Vector3.new(x, y + 0.35, z), 11, 1,
			shade(DARKROCK, 0.82), nil, { CanCollide = false })
		for k = 0, 5 do
			local a = (k / 6) * math.pi * 2 + i
			ball(ctx, "Ejecta",
				Vector3.new(x + math.cos(a) * 17, y + 0.7, z + math.sin(a) * 17),
				Vector3.new(3, 1.6, 2.6), DARKROCK, Enum.Material.Slate,
				{ CanCollide = false })
		end
	elseif kind == 1 then
		-- Moon rock. Angular, not domed — there is no weather up there to
		-- round anything off, and the sharp silhouette is what sells that.
		for k = 0, 3 do
			local a = (k / 4) * math.pi * 2 + i * 0.8
			local h = 4.5 + ((i + k) % 4) * 2.8
			box(ctx, "MoonRock",
				Vector3.new(x + math.cos(a) * 3.6, y + h * 0.45, z + math.sin(a) * 3.6),
				Vector3.new(5.5 - k * 0.6, h, 5 - k * 0.5),
				shade(DARKROCK, 0.88 + (k % 3) * 0.09), Enum.Material.Slate,
				{ Orientation = Vector3.new((k % 3) * 6 - 6, math.deg(a),
					(k % 2) * 8 - 4) })
		end
	elseif kind == 2 then
		-- A probe that landed and stayed. Legs, body, dish, one solar panel.
		for k = 0, 2 do
			local a = (k / 3) * math.pi * 2
			column(ctx, "ProbeLeg",
				Vector3.new(x + math.cos(a) * 3, y + 2, z + math.sin(a) * 3),
				0.3, 4.2, C(96, 98, 110), Enum.Material.Metal,
				{ Orientation = Vector3.new(12, math.deg(a), 90) })
		end
		box(ctx, "ProbeBody", Vector3.new(x, y + 5, z), Vector3.new(4.5, 3, 4.5),
			C(206, 202, 190), Enum.Material.Metal)
		box(ctx, "ProbePanel", Vector3.new(x + 5.6, y + 5.8, z),
			Vector3.new(7, 0.4, 4), C(58, 82, 148), Enum.Material.Glass,
			{ CanCollide = false })
		column(ctx, "ProbeMast", Vector3.new(x, y + 8.3, z), 0.22, 3.8,
			C(96, 98, 110), Enum.Material.Metal)
		ball(ctx, "ProbeDish", Vector3.new(x, y + 10.4, z), Vector3.new(3.8, 1.2, 3.8),
			C(226, 224, 216), Enum.Material.Metal, { CanCollide = false })
	else
		-- Ice in a crater shadow: a real thing, and the only cool colour on an
		-- otherwise bone-grey surface. Glass rather than neon — neon is for
		-- things a player can USE.
		for k = 0, 4 do
			local a = (k / 5) * math.pi * 2 + i
			local h = 3.5 + ((i + k) % 4) * 2.2
			box(ctx, "IceShard",
				Vector3.new(x + math.cos(a) * 2.8, y + h * 0.5, z + math.sin(a) * 2.8),
				Vector3.new(1.5, h, 1.5), C(178, 210, 232), Enum.Material.Glass,
				{ CanCollide = false, Transparency = 0.25,
				  Orientation = Vector3.new((k % 3) * 10 - 10, math.deg(a),
					(k % 2) * 12 - 6) })
		end
	end

	if i % 2 == 0 then
		disc(ctx, "Regolith", Vector3.new(x + 7, y + 0.25, z - 6), 6, 0.35,
			shade(REGOLITH, 1.04), nil, { CanCollide = false })
	end
	-- One asteroid overhead per few clusters, so the sky is not empty either —
	-- but it is the exception now, not the whole world.
	if i % 5 == 0 then
		ball(ctx, "Asteroid", Vector3.new(x, y + 24 + (i % 4) * 7, z),
			Vector3.new(6, 4.6, 6), DARKROCK, Enum.Material.Slate,
			{ CanCollide = false })
	end
end

-- ============================================================
-- PLACEMENT
-- ============================================================
-- Roughly how wide one placement of each set is, in studs. Measured from the
-- widest thing each function actually builds, not guessed: the desert mesa is
-- 15 across and the palm's fronds reach 14, so desert needs the most room; the
-- moon crater throws ejecta out to 17.
--
-- Without this, features several parts wide get dropped inside one another and
-- you get palm trees growing out of the side of a mesa.
MapProps.RADIUS = {
	meadow = 10, forest = 9, desert = 17, volcano = 13, space = 17,
}

-- A clump, not a scatter. Uniform random reads as noise however many props you
-- use; a handful of tight groups with space between them reads as terrain.
function MapProps.Populate(ctx, setName, cx, cz, halfW, halfD, baseY, opts)
	local fn = MapProps.SETS[setName]
	if not fn then return 0 end
	opts = opts or {}

	local rand = Random.new(opts.seed or 20260911)
	local radius = MapProps.RADIUS[setName] or 11
	local clusters = opts.clusters or 14
	local blocked = opts.blocked        -- function(x, z) -> true to skip

	local placed, n = {}, 0
	local function tooClose(x, z)
		for _, p in ipairs(placed) do
			local dx, dz = x - p[1], z - p[2]
			if dx * dx + dz * dz < radius * radius then return true end
		end
		return false
	end

	for _ = 1, clusters do
		local ax = cx + rand:NextNumber(-1, 1) * (halfW - radius)
		local az = cz + rand:NextNumber(-1, 1) * (halfD - radius)
		for k = 1, rand:NextInteger(3, 6) do
			local x = ax + rand:NextNumber(-1, 1) * 13
			local z = az + rand:NextNumber(-1, 1) * 13
			if math.abs(x - cx) <= halfW - 4 and math.abs(z - cz) <= halfD - 4
				and not tooClose(x, z)
				and not (blocked and blocked(x, z)) then
				table.insert(placed, { x, z })
				fn(ctx, x, z, baseY, n + k)
				n = n + 1
			end
		end
	end
	return n
end

return MapProps
