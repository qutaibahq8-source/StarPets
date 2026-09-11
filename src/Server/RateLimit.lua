-- StarPets: RateLimit.lua
-- Place in: ServerScriptService > Server > RateLimit (ModuleScript)
--
-- A token bucket per player, per action.
--
-- The point is not to punish fast players — it is that a handler which writes
-- to player data must not be drivable at whatever rate a script can manage.
-- ClickDetectors are the sharpest case: no remote is involved on the way in, so
-- nothing that guards the remotes ever sees them. The client clicks and Roblox
-- fires MouseClick on the server directly.
--
-- Tuned so a HUMAN never notices. A person spamming a shop button manages
-- perhaps six clicks a second; the default allows fifteen sustained and a burst
-- of twenty-five, which leaves a wide margin above real play and still costs an
-- exploiter three orders of magnitude.

local Players = game:GetService("Players")

local RateLimit = {}

RateLimit.DEFAULT = { burst = 25, perSecond = 15 }

-- Anything genuinely expensive gets its own, tighter, entry.
RateLimit.RULES = {
	["map:SecretChest"] = { burst = 3, perSecond = 1 },
	["map:BuyArea"]     = { burst = 8, perSecond = 4 },
	["map:Rebirth"]     = { burst = 5, perSecond = 2 },
}

local buckets = {}   -- [userId] = { [action] = { tokens, last } }

local function ruleFor(action)
	return RateLimit.RULES[action] or RateLimit.DEFAULT
end

function RateLimit.Allow(player, action)
	-- Deliberately plain. The first version of this branched on `typeof` and
	-- table-vs-Instance to work out the user id, which was three ways of asking
	-- one question and would have behaved differently in Studio, in a live
	-- server and under test. A limiter that is hard to reason about is worse
	-- than none: you stop trusting what it is doing.
	if player == nil then return false end
	local ok, uid = pcall(function() return player.UserId end)
	if not ok or uid == nil then return false end

	local b = buckets[uid]
	if not b then b = {}; buckets[uid] = b end
	local rule = ruleFor(action)
	local slot = b[action]
	local now = os.clock()
	if not slot then
		slot = { tokens = rule.burst, last = now }
		b[action] = slot
	end
	-- Refill for the time that has passed, capped at the burst size.
	slot.tokens = math.min(rule.burst,
		slot.tokens + (now - slot.last) * rule.perSecond)
	slot.last = now
	if slot.tokens < 1 then
		return false
	end
	slot.tokens = slot.tokens - 1
	return true
end

-- Without this the table grows by one entry per player for the life of the
-- server, which on a busy game is a slow leak that never gets noticed because
-- each entry is tiny.
Players.PlayerRemoving:Connect(function(player)
	buckets[player.UserId] = nil
end)

function RateLimit.Reset(player)
	if player then buckets[player.UserId] = nil end
end

return RateLimit
