-- StarPets: TradeService.lua
-- Place in: ServerScriptService > Server > TradeService (ModuleScript)
-- Secure 2-player trading: both must accept, 3s confirm countdown, any change
-- resets accepts (anti-scam), ownership re-validated at swap (no duplication).

local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local DataManager = require(script.Parent.DataManager)
local PetService  = require(script.Parent.PetService)

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
	if not petByUid(data, uid) then return end
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
		for _, uid in ipairs(ids) do local p = petByUid(data, uid); if not p then return nil end; table.insert(pets, p) end
		return pets
	end
	local petsA = da and collect(da, s.offer[s.a.UserId])
	local petsB = db and collect(db, s.offer[s.b.UserId])
	if not petsA or not petsB then resetAccepts(s); push(s); return end  -- abort, no dupe
	local function moveOut(data, ids)
		for _, uid in ipairs(ids) do
			for i, p in ipairs(data.Pets) do if p.uniqueId == uid then table.remove(data.Pets, i); break end end
			for i, eid in ipairs(data.EquippedPets or {}) do if eid == uid then table.remove(data.EquippedPets, i); break end end
		end
	end
	moveOut(da, s.offer[s.a.UserId]); moveOut(db, s.offer[s.b.UserId])
	for _, p in ipairs(petsA) do table.insert(db.Pets, { name=p.name, rarity=p.rarity, uniqueId=HttpService:GenerateGUID(false) }) end
	for _, p in ipairs(petsB) do table.insert(da.Pets, { name=p.name, rarity=p.rarity, uniqueId=HttpService:GenerateGUID(false) }) end
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
