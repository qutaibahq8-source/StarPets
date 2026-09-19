-- StarPets: TradeService.lua
-- Place in: ServerScriptService > Server > TradeService (ModuleScript)
-- Secure 2-player trading: both must accept, 3s confirm countdown, any change
-- resets accepts (anti-scam), ownership re-validated at swap (no duplication).

local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local DataManager = require(script.Parent.DataManager)
local PetService  = require(script.Parent.PetService)
local GameConfig  = require(game.ReplicatedStorage.Shared.GameConfig)

-- EVERYTHING A PET IS, BESIDES ITS NAME.
--
-- The swap used to rebuild the received pet as { name, rarity, uniqueId } and
-- nothing else, which silently threw away every field that gives a pet its
-- value. EggService rolls a `mutation` (Rainbow x10, Shiny x4, Golden x2);
-- FusionService gives a `fuseMult` that compounds, since three fused pets sum
-- their multipliers and take a further x1.25 and a fused pet can be fused
-- again. PetService scores a pet as coinMult * mutationMult * fuseMult.
--
-- Measured: a Rainbow pet three fusions deep went from power 3,516 to 60 —
-- 98.3% of its value destroyed by trading it, with nothing anywhere to say so.
--
-- Listed rather than deep-copied wholesale so that a field which must NOT
-- survive a trade has to be added here deliberately. `locked` is the example:
-- it is the receiving player's choice to make, not the sender's.
local CARRIED = {
	"name", "rarity", "mutation", "fuseMult", "level", "xp", "stage",
	"variant", "shiny", "size", "petId", "world", "source",
}

local function clonePet(pet)
	local out = {}
	for _, k in ipairs(CARRIED) do out[k] = pet[k] end
	-- A fresh id: two players must never hold the same uniqueId, or every
	-- lookup that matches by id becomes ambiguous.
	out.uniqueId = HttpService:GenerateGUID(false)
	out.locked = false
	return out
end

local TradeService = {}
local sessions = {}        -- [userId] -> session (shared by both traders)
local pending  = {}        -- [targetUserId] -> fromUserId
local pushState, pushReq   -- callbacks set by GameServer

function TradeService.Init(stateFn, reqFn) pushState = stateFn; pushReq = reqFn end

local function petByUid(data, uid)
	if not data then return nil end
	for _, p in ipairs(data.Pets) do if p.uniqueId == uid then return p end end
end

local function offerList(owner, ids)
	local data = DataManager.GetData(owner); local out = {}
	for _, uid in ipairs(ids) do
		local pet = petByUid(data, uid)
		if pet then table.insert(out, { name=pet.name, rarity=pet.rarity, uniqueId=uid }) end
	end
	return out
end

local function viewFor(s, me)
	local them = (me == s.a) and s.b or s.a
	return {
		active = true, partner = them.Name,
		yourOffer  = offerList(me,   s.offer[me.UserId]),
		theirOffer = offerList(them, s.offer[them.UserId]),
		youAccepted = s.accept[me.UserId] == true,
		theyAccepted = s.accept[them.UserId] == true,
		confirmLeft = s.confirmEndsAt and math.max(0, math.ceil(s.confirmEndsAt - os.time())) or nil,
	}
end

local function push(s)
	if not pushState then return end
	pushState(s.a, viewFor(s, s.a)); pushState(s.b, viewFor(s, s.b))
end

local function resetAccepts(s)
	s.accept[s.a.UserId] = false; s.accept[s.b.UserId] = false; s.confirmEndsAt = nil
end

function TradeService.Request(player, targetName)
	if sessions[player.UserId] then return end
	local q = string.lower(targetName or ""); if q == "" then return end
	local target
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and string.sub(string.lower(p.Name), 1, #q) == q then target = p; break end
	end
	if not target or sessions[target.UserId] then return end
	pending[target.UserId] = player.UserId
	if pushReq then pushReq(target, player.Name, player.UserId) end
end

function TradeService.Respond(player, accept)
	local fromId = pending[player.UserId]; pending[player.UserId] = nil
	if not accept or not fromId then return end
	local from = Players:GetPlayerByUserId(fromId)
	if not from or sessions[from.UserId] or sessions[player.UserId] then return end
	local s = { a=from, b=player, offer={[from.UserId]={},[player.UserId]={}}, accept={[from.UserId]=false,[player.UserId]=false} }
	sessions[from.UserId] = s; sessions[player.UserId] = s
	push(s)
end

function TradeService.Add(player, uid)
	local s = sessions[player.UserId]; if not s then return end
	local data = DataManager.GetData(player)
	local pet = petByUid(data, uid)
	if not pet then return end
	-- Locking is how a player says "this never leaves". If trade ignores it,
	-- the protection is decorative — and it was ignored: a locked pet could be
	-- offered and swapped away with no warning.
	if pet.locked then return end
	local ids = s.offer[player.UserId]
	for _, x in ipairs(ids) do if x == uid then return end end
	if #ids >= 8 then return end
	table.insert(ids, uid); resetAccepts(s); push(s)
end

function TradeService.Remove(player, uid)
	local s = sessions[player.UserId]; if not s then return end
	local ids = s.offer[player.UserId]
	for i, x in ipairs(ids) do if x == uid then table.remove(ids, i); break end end
	resetAccepts(s); push(s)
end

local function doSwap(s)
	if sessions[s.a.UserId] ~= s then return end
	if not (s.accept[s.a.UserId] and s.accept[s.b.UserId]) then return end
	local da, db = DataManager.GetData(s.a), DataManager.GetData(s.b)
	-- re-validate BOTH still own everything they offered
	local function collect(data, ids)
		local pets = {}
		for _, uid in ipairs(ids) do
			local p = petByUid(data, uid)
			if not p then return nil end
			-- Checked AGAIN here, not only when the pet was added. A pet can be
			-- locked from the inventory panel during the three-second confirm
			-- window, and the check that ran on Add is long past by then.
			if p.locked then return nil end
			table.insert(pets, p)
		end
		return pets
	end
	local petsA = da and collect(da, s.offer[s.a.UserId])
	local petsB = db and collect(db, s.offer[s.b.UserId])
	if not petsA or not petsB then resetAccepts(s); push(s); return end  -- abort, no dupe

	-- Neither side may be pushed past the inventory cap. Checked BEFORE
	-- anything is removed, so a refused trade leaves both inventories exactly
	-- as they were rather than half-applied.
	local cap = GameConfig.Settings.MaxPetsInInventory or math.huge
	local afterA = #da.Pets - #petsA + #petsB
	local afterB = #db.Pets - #petsB + #petsA
	if afterA > cap or afterB > cap then
		resetAccepts(s); push(s)
		if TradeService.onBlocked then
			TradeService.onBlocked(s.a, "Not enough inventory space for this trade.")
			TradeService.onBlocked(s.b, "Not enough inventory space for this trade.")
		end
		return
	end
	local function moveOut(data, ids)
		for _, uid in ipairs(ids) do
			for i, p in ipairs(data.Pets) do if p.uniqueId == uid then table.remove(data.Pets, i); break end end
			for i, eid in ipairs(data.EquippedPets or {}) do if eid == uid then table.remove(data.EquippedPets, i); break end end
		end
	end
	moveOut(da, s.offer[s.a.UserId]); moveOut(db, s.offer[s.b.UserId])
	-- force: the cap was already checked above for BOTH sides, before anything
	-- was removed. Re-checking here could reject half a completed swap.
	for _, p in ipairs(petsA) do PetService.GrantPet(s.b, clonePet(p), true) end
	for _, p in ipairs(petsB) do PetService.GrantPet(s.a, clonePet(p), true) end
	local a, b = s.a, s.b
	sessions[a.UserId] = nil; sessions[b.UserId] = nil
	pcall(PetService.RestoreEquipped, a); pcall(PetService.RestoreEquipped, b)
	if pushState then pushState(a, { active=false, done=true }); pushState(b, { active=false, done=true }) end
	if TradeService.onComplete then TradeService.onComplete(a); TradeService.onComplete(b) end
end

function TradeService.Accept(player, val)
	local s = sessions[player.UserId]; if not s then return end
	s.accept[player.UserId] = val and true or false
	if s.accept[s.a.UserId] and s.accept[s.b.UserId] then
		s.confirmEndsAt = os.time() + 3; push(s)
		task.delay(3, function() doSwap(s) end)
	else
		s.confirmEndsAt = nil; push(s)
	end
end

function TradeService.Cancel(player)
	pending[player.UserId] = nil
	local s = sessions[player.UserId]; if not s then return end
	sessions[s.a.UserId] = nil; sessions[s.b.UserId] = nil
	if pushState then pushState(s.a, { active=false }); pushState(s.b, { active=false }) end
end

Players.PlayerRemoving:Connect(function(p) TradeService.Cancel(p) end)

return TradeService
