-- StarPets: Sfx.lua
-- Place in: StarterPlayerScripts > Client > UI > Sfx (ModuleScript)
--
-- Sound. The game had none — not one Sound instance anywhere in the project.
-- An egg hatch, which is the whole point of a pet simulator, happened in
-- total silence. SoundService was even imported in HatchUI and never used.
--
-- WHY THESE IDS
--
-- Every sound here is an `rbxasset://` built into the Roblox client. Not a
-- catalogue upload. That is deliberate:
--
--   * they cannot 404, and they cannot be moderated out from under the game
--     six months from now, which is how a game ends up silent again without
--     anyone touching it
--   * they need no upload, no asset permissions and no Robux
--   * they work the moment this file lands, with nothing to configure
--
-- They are placeholders in the sense that a better library would sound better,
-- but they are not stubs: these play. Swapping any of them for a catalogue
-- sound is one string in the table below, and nothing else changes.
--
-- Pitch is doing a lot of the work. The same short ping at 0.8, 1.0 and 1.5 is
-- three different events to a player's ear, which is how a handful of built-in
-- files covers a dozen moments.

local SoundService = game:GetService("SoundService")

local Sfx = {}

-- volume, pitch. Volumes are deliberately low: this is a game people leave
-- running, and a coin ping at full volume every half second is why people
-- mute tabs.
local SOUNDS = {
	click      = { id = "rbxasset://sounds/clickfast.wav",           vol = 0.25, pitch = 1.00 },
	open       = { id = "rbxasset://sounds/switch3.wav",             vol = 0.30, pitch = 1.10 },
	close      = { id = "rbxasset://sounds/switch.wav",              vol = 0.25, pitch = 0.95 },
	coin       = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.22, pitch = 1.55 },
	gem        = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.26, pitch = 1.90 },
	buy        = { id = "rbxasset://sounds/switch3.wav",             vol = 0.35, pitch = 0.85 },
	error      = { id = "rbxasset://sounds/switch.wav",              vol = 0.30, pitch = 0.55 },
	equip      = { id = "rbxasset://sounds/snap.wav",                vol = 0.30, pitch = 1.20 },
	unequip    = { id = "rbxasset://sounds/snap.wav",                vol = 0.22, pitch = 0.80 },
	-- The hatch build-up and the four reveal weights. A Mythic has to sound
	-- different from a Common or the rarest moment in the game lands as
	-- nothing.
	hatch      = { id = "rbxasset://sounds/bass.wav",                vol = 0.35, pitch = 1.60 },
	reveal1    = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.30, pitch = 1.30 },
	reveal2    = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.38, pitch = 1.00 },
	reveal3    = { id = "rbxasset://sounds/bass.wav",                vol = 0.45, pitch = 1.20 },
	reveal4    = { id = "rbxasset://sounds/bass.wav",                vol = 0.60, pitch = 0.75 },
	rebirth    = { id = "rbxasset://sounds/bass.wav",                vol = 0.55, pitch = 0.60 },
	unlock     = { id = "rbxasset://sounds/unsheath.wav",            vol = 0.45, pitch = 0.90 },
	reward     = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.40, pitch = 1.15 },
	badge      = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.50, pitch = 0.80 },
}

-- Every id above must be one of these. A built-in file that turns out not to
-- exist does not error: the Sound loads nothing, Output prints "Failed to load
-- sound" where nobody looks, and that moment of the game goes silent again.
-- Holding the ids to a list of files that have shipped in the client for years
-- turns "is this one real" from a guess into a decision someone made.
Sfx.KNOWN_BUILTIN = {
	["rbxasset://sounds/clickfast.wav"] = true,
	["rbxasset://sounds/switch.wav"] = true,
	["rbxasset://sounds/switch3.wav"] = true,
	["rbxasset://sounds/electronicpingshort.wav"] = true,
	["rbxasset://sounds/snap.wav"] = true,
	["rbxasset://sounds/bass.wav"] = true,
	["rbxasset://sounds/unsheath.wav"] = true,
}

-- Which reveal weight a rarity gets. Anything not listed is the quiet one.
local REVEAL = {
	Common = "reveal1", Uncommon = "reveal1",
	Rare = "reveal2", Epic = "reveal3",
	Legendary = "reveal4", Mythic = "reveal4",
}

-- A small ring per sound rather than one instance, and rather than a fresh
-- Sound per play.
--
-- One instance means a second coin inside half a second cuts off the first,
-- and collecting coins is the thing a player does most. A fresh instance per
-- play means allocating and destroying an Instance several times a second
-- forever, which is exactly the kind of churn that makes a client stutter
-- after twenty minutes. Four is enough to overlap without either problem.
local RING = 4
local pools = {}
local cursor = {}

local function poolFor(name)
	local def = SOUNDS[name]
	if not def then return nil end
	local pool = pools[name]
	if pool then return pool end

	pool = {}
	for i = 1, RING do
		local s = Instance.new("Sound")
		s.Name = "SP_" .. name .. i
		s.SoundId = def.id
		s.Volume = def.vol
		s.PlaybackSpeed = def.pitch
		-- Parented to SoundService so it is 2D: UI feedback must not get
		-- quieter because the player walked away from where it was triggered.
		s.Parent = SoundService
		pool[i] = s
	end
	pools[name] = pool
	cursor[name] = 0
	return pool
end

local warned = {}

-- The player's mute switch. Checked at the door rather than by turning volumes
-- down, so a muted player's client does no sound work at all.
local muted = false
function Sfx.SetMuted(m) muted = m == true end
function Sfx.IsMuted() return muted end

-- Play a sound by name. `jitter` varies the pitch a little, so a run of the
-- same sound does not sound like a machine.
function Sfx.Play(name, jitter)
	if muted then return nil end
	local def = SOUNDS[name]
	if not def then
		if not warned[name] then
			warned[name] = true
			warn("[Sfx] no sound called " .. tostring(name))
		end
		return nil
	end
	local pool = poolFor(name)
	if not pool then return nil end

	local i = (cursor[name] % RING) + 1
	cursor[name] = i
	local s = pool[i]
	if jitter and jitter > 0 then
		s.PlaybackSpeed = def.pitch * (1 + (math.random() - 0.5) * 2 * jitter)
	else
		s.PlaybackSpeed = def.pitch
	end
	-- TimePosition reset: a Sound asked to play while already playing carries
	-- on from where it was, so a rapid second press is silent.
	s.TimePosition = 0
	s:Play()
	return s
end

-- The hatch reveal, weighted by what came out.
function Sfx.Reveal(rarity)
	return Sfx.Play(REVEAL[rarity] or "reveal1")
end

-- A toast's sound, chosen from the toast's own type, so every notification the
-- game already shows gains a sound without a single call site changing.
local TOAST = { success = "reward", error = "error", info = "open" }
function Sfx.Toast(kind)
	return Sfx.Play(TOAST[tostring(kind)] or "open")
end

-- Exposed for the checks: how many Sound instances this module has made. A
-- pool that grows without limit is a leak that only shows up after an hour of
-- play, which is too late to notice.
function Sfx.InstanceCount()
	local n = 0
	for _, pool in pairs(pools) do
		for _ in ipairs(pool) do n = n + 1 end
	end
	return n
end

function Sfx.Names()
	local out = {}
	for name in pairs(SOUNDS) do table.insert(out, name) end
	table.sort(out)
	return out
end

function Sfx.IdOf(name)
	return SOUNDS[name] and SOUNDS[name].id or nil
end

return Sfx
