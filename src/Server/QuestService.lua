-- StarPets: QuestService.lua
-- Place in: ServerScriptService > Server > QuestService (ModuleScript)
--
-- Two kinds of quest:
--
--   MILESTONES  the nine lifetime goals in GameConfig.Quests. Claim once, ever.
--   DAILIES     three rolled per player per UTC day from GameConfig.DailyQuests.
--
-- Neither needs an event hook. Progress is read from counters the game already
-- keeps, which is what made the original version so small — and also what made
-- it wrong, because two of those counters go BACKWARDS.
--
-- Rebirth sets TotalCoinsEarned to 0 and UnlockedAreas back to { Meadow }. Four
-- of the nine milestones read those directly, so rebirthing quietly undid them:
-- "Unlock all worlds" (400 gems) could not be finished again until every world
-- had been bought back, and a player who had earned 900k of the 1m coin quest
-- was returned to zero with nothing said. Rebirth is the game's main long-term
-- goal. It should not cost you the rewards for reaching it.
--
-- So progress is accumulated into data.Stats instead. A reset moves the
-- baseline; it never takes the total with it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig        = require(game.ReplicatedStorage.Shared.GameConfig)
local DataManager       = require(script.Parent.DataManager)
local PetService        = require(script.Parent.PetService)

local QuestService = {}

local DAY = 86400

-- Counters that only ever go up, and whose TOTAL is the thing being asked for
-- ("hatch 100 eggs" means 100 in your life, not 100 held at once).
local TOTALS = {
	hatch = function(d) return d.EggsHatched or 0 end,
	coins = function(d) return math.floor(d.TotalCoinsEarned or 0) end,
	fuse  = function(d) return d.PetsFused or 0 end,
	spin  = function(d) return d.SpinsUsed or 0 end,
}

-- States, where the question is "did you ever reach this at once". Accumulating
-- these would be wrong in the other direction: equipping and unequipping a pet
-- twenty times would finish "equip 3 pets at once" without ever equipping three.
local PEAKS = {
	areas   = function(d) return math.max(0, #(d.UnlockedAreas or {}) - 1) end,
	rebirth = function(d) return d.Rebirths or 0 end,
	equip   = function(d) return #(d.EquippedPets or {}) end,
}

-- Bring data.Stats up to date with the live counters.
--
-- Safe to call as often as you like and cheap to do so, which matters: it is
-- what makes the poll-based design correct. Nothing is lost by calling late,
-- because the delta is measured against the last call rather than against a
-- clock — the only way to lose progress is for a counter to reset between two
-- calls, which is why RebirthService calls this immediately before it resets.
function QuestService.Sync(data)
	if type(data) ~= "table" then return nil end
	local s = data.Stats
	if type(s) ~= "table" then s = {}; data.Stats = s end
	local last = s._last
	if type(last) ~= "table" then last = {}; s._last = last end

	for key, read in pairs(TOTALS) do
		local now = read(data)
		local prev = last[key]
		if prev == nil then
			-- First time this account has been seen by the new accounting.
			-- Seed from where it already is: counting from zero would undo
			-- every milestone an existing player has already earned.
			s[key] = math.max(s[key] or 0, now)
		elseif now >= prev then
			s[key] = (s[key] or 0) + (now - prev)
		end
		-- now < prev means the counter reset under us. The accumulated total
		-- stands; only the baseline moves.
		last[key] = now
	end

	for key, read in pairs(PEAKS) do
		s[key] = math.max(s[key] or 0, read(data))
	end
	return s
end

local function statOf(data, kind)
	local s = QuestService.Sync(data)
	return (s and s[kind]) or 0
end

local function ensure(data)
	if type(data.Quests) ~= "table" then data.Quests = {} end
	if type(data.Quests.claimed) ~= "table" then data.Quests.claimed = {} end
	return data.Quests
end

-- ============================================================
-- DAILIES
-- ============================================================
local DAILY_BY_ID = {}
for _, d in ipairs(GameConfig.DailyQuests or {}) do DAILY_BY_ID[d.id] = d end

local function dayNumber() return math.floor(os.time() / DAY) end

-- The same three quests on every server, all day.
--
-- math.random here would be a real bug rather than a cosmetic one: each server
-- would roll its own set, so hopping servers would reshuffle the day's quests —
-- and with them a fresh set of unclaimed rewards. Seeding from the player and
-- the day makes the roll a pure function of both, so every server agrees
-- without needing to store or share anything.
local function pickDaily(userId, day)
	local pool = GameConfig.DailyQuests or {}
	local want = math.min(GameConfig.DailyQuestCount or 3, #pool)
	local order = {}
	for i = 1, #pool do order[i] = i end

	local rng = Random.new(userId * 7919 + day * 104729)
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end

	-- One quest per type. Three coin quests in a day is not variety, it is the
	-- same quest three times at different prices.
	local ids, usedType = {}, {}
	for _, idx in ipairs(order) do
		local def = pool[idx]
		if def and not usedType[def.type] then
			usedType[def.type] = true
			table.insert(ids, def.id)
			if #ids >= want then break end
		end
	end
	return ids
end

local function ensureDaily(data, userId)
	local q = ensure(data)
	local day = dayNumber()
	local d = q.daily
	if type(d) ~= "table" or d.day ~= day or type(d.ids) ~= "table" then
		local stats = QuestService.Sync(data)
		d = { day = day, ids = pickDaily(userId, day), claimed = {}, base = {} }
		-- The baseline is taken per quest, not per type, so two quests that read
		-- the same counter still measure from the same start rather than one
		-- inheriting the other's.
		for _, id in ipairs(d.ids) do
			local def = DAILY_BY_ID[id]
			if def then d.base[id] = stats[def.type] or 0 end
		end
		q.daily = d
	end
	if type(d.claimed) ~= "table" then d.claimed = {} end
	if type(d.base) ~= "table" then d.base = {} end
	return d
end

local function dailyProgress(data, d, def)
	local have = statOf(data, def.type)
	return math.max(0, have - (d.base[def.id] or 0))
end

-- ============================================================
-- READING
-- ============================================================
local function milestoneProgress(data, def)
	return statOf(data, def.type)
end

function QuestService.GetAll(player)
	local data = DataManager.GetData(player)
	if not data then return {} end
	QuestService.Sync(data)

	local out = {}
	local d = ensureDaily(data, player.UserId or 0)
	local resetsIn = ((d.day + 1) * DAY) - os.time()

	-- Dailies first: they are the ones with a clock on them.
	for _, id in ipairs(d.ids) do
		local def = DAILY_BY_ID[id]
		if def then
			local p = dailyProgress(data, d, def)
			table.insert(out, {
				id = def.id, name = def.name, desc = def.desc, goal = def.goal,
				progress = math.min(p, def.goal), done = p >= def.goal,
				claimed = d.claimed[def.id] == true, reward = def.reward,
				kind = "daily", resetsIn = math.max(0, resetsIn),
			})
		end
	end

	for _, def in ipairs(GameConfig.Quests) do
		local q = ensure(data)
		local p = milestoneProgress(data, def)
		table.insert(out, {
			id = def.id, name = def.name, desc = def.desc, goal = def.goal,
			progress = math.min(p, def.goal), done = p >= def.goal,
			claimed = q.claimed[def.id] == true, reward = def.reward,
			kind = "milestone",
		})
	end
	return out
end

-- ============================================================
-- CLAIMING
-- ============================================================
local function payout(player, data, r)
	r = r or {}
	if r.coins then
		data.Coins = (data.Coins or 0) + r.coins
		data.TotalCoinsEarned = (data.TotalCoinsEarned or 0) + r.coins
	end
	if r.gems then data.Gems = (data.Gems or 0) + r.gems end
	if r.pet then
		-- Through GrantPet, never table.insert: it is what enforces the pet cap
		-- and stamps the permanent Discovered record the Pet Index reads.
		PetService.GrantPet(player, { name = r.pet, rarity = r.petRarity or "Common" })
	end
	-- A reward that pays coins has just moved a counter a quest might read, so
	-- fold it in before anything else looks.
	QuestService.Sync(data)
end

-- returns ok, questDef | errString
function QuestService.Claim(player, id)
	local data = DataManager.GetData(player)
	if not data then return false, "no data" end
	QuestService.Sync(data)

	local daily = DAILY_BY_ID[id]
	if daily then
		local d = ensureDaily(data, player.UserId or 0)
		local today = false
		for _, got in ipairs(d.ids) do if got == id then today = true end end
		if not today then return false, "that one is not today's" end
		if d.claimed[id] then return false, "already claimed" end
		if dailyProgress(data, d, daily) < daily.goal then
			return false, "not complete yet"
		end
		-- Marked BEFORE paying out. If payout throws half way, the worst case is
		-- an unpaid claim the player can report, not a reward that can be taken
		-- repeatedly.
		d.claimed[id] = true
		payout(player, data, daily.reward)
		return true, daily
	end

	local q = ensure(data)
	local def
	for _, cand in ipairs(GameConfig.Quests) do
		if cand.id == id then def = cand break end
	end
	if not def then return false, "unknown quest" end
	if q.claimed[id] then return false, "already claimed" end
	if milestoneProgress(data, def) < def.goal then return false, "not complete yet" end
	q.claimed[id] = true
	payout(player, data, def.reward)
	return true, def
end

-- admin helpers
function QuestService.ClaimAll(player)
	for _, def in ipairs(GameConfig.Quests) do
		pcall(QuestService.Claim, player, def.id)
	end
	local data = DataManager.GetData(player)
	if data then
		for _, id in ipairs(ensureDaily(data, player.UserId or 0).ids) do
			pcall(QuestService.Claim, player, id)
		end
	end
end

function QuestService.Reset(player)
	local data = DataManager.GetData(player)
	if data then
		ensure(data).claimed = {}
		data.Quests.daily = {}
	end
end

return QuestService
