-- MysticPets: BadgeService.lua
-- Place in: ServerScriptService > Server > BadgeService (ModuleScript)

local Players   = game:GetService("Players")
local GameConfig = require(game.ReplicatedStorage.Shared.GameConfig)

local BadgeService = {}
local RE_BadgeEarned = nil  -- set by GameServer after remotes created

-- ============================================================
-- BADGE DEFINITIONS
-- ============================================================
local Badges = {
	-- Joining
	{ id = "welcome",         icon = "🌟", title = "Welcome!",           desc = "Joined MysticPets for the first time",         rarity = "Common"    },
	-- Pets
	{ id = "first_pet",       icon = "🐾", title = "New Best Friend",    desc = "Hatched your very first pet",                rarity = "Common"    },
	{ id = "collector_5",     icon = "📦", title = "Collector",          desc = "Own 5 pets",                                 rarity = "Common"    },
	{ id = "collector_25",    icon = "🎒", title = "Hoarder",            desc = "Own 25 pets",                                rarity = "Uncommon"  },
	{ id = "collector_50",    icon = "🏠", title = "Pet House",          desc = "Own 50 pets",                                rarity = "Rare"      },
	{ id = "first_rare",      icon = "💙", title = "Rare Find",          desc = "Hatched your first Rare pet",                rarity = "Rare"      },
	{ id = "first_epic",      icon = "💜", title = "Epic Pull",          desc = "Hatched your first Epic pet",                rarity = "Epic"      },
	{ id = "first_legendary", icon = "🏆", title = "Legendary!",        desc = "Hatched your first Legendary pet",           rarity = "Legendary" },
	{ id = "first_mythic",    icon = "✨", title = "MYTHIC!",           desc = "Hatched your first Mythic pet",              rarity = "Mythic"    },
	-- Eggs
	{ id = "hatch_10",        icon = "🥚", title = "Hatch Addict",       desc = "Hatched 10 eggs",                            rarity = "Common"    },
	{ id = "hatch_100",       icon = "🍳", title = "Egg Maniac",         desc = "Hatched 100 eggs",                           rarity = "Uncommon"  },
	{ id = "hatch_500",       icon = "🎰", title = "Slot Machine",       desc = "Hatched 500 eggs",                           rarity = "Rare"      },
	-- Coins
	{ id = "coins_1k",        icon = "💰", title = "First Thousand",     desc = "Earn 1,000 coins",                           rarity = "Common"    },
	{ id = "coins_100k",      icon = "💵", title = "Hundred K",          desc = "Earn 100,000 coins",                         rarity = "Uncommon"  },
	{ id = "coins_1m",        icon = "💎", title = "Millionaire",        desc = "Earn 1,000,000 coins",                       rarity = "Rare"      },
	{ id = "coins_1b",        icon = "🤑", title = "Billionaire",        desc = "Earn 1,000,000,000 coins",                   rarity = "Legendary" },
	-- Areas
	{ id = "unlock_forest",   icon = "🌲", title = "Into the Woods",     desc = "Unlocked Mystic Forest",                     rarity = "Common"    },
	{ id = "unlock_desert",   icon = "🏜️", title = "Desert Explorer",   desc = "Unlocked Golden Desert",                     rarity = "Uncommon"  },
	{ id = "unlock_volcano",  icon = "🌋", title = "Lava Walker",        desc = "Unlocked Inferno Volcano",                   rarity = "Rare"      },
	{ id = "unlock_space",    icon = "🚀", title = "Space Cadet",        desc = "Unlocked Star Space",                        rarity = "Legendary" },
	-- Rebirths
	{ id = "first_rebirth",   icon = "♻️", title = "Born Again",        desc = "Completed your first Rebirth",               rarity = "Rare"      },
	{ id = "rebirth_3",       icon = "🔄", title = "Triple Threat",      desc = "Completed 3 Rebirths",                       rarity = "Epic"      },
	{ id = "rebirth_6",       icon = "👑", title = "Grandmaster",        desc = "Reached max Rebirth level",                  rarity = "Mythic"    },
	-- Speed
	{ id = "speed_demon",     icon = "⚡", title = "Speed Demon",        desc = "Unlocked Forest within 5 minutes of joining",rarity = "Rare"      },
	-- Secret
	{ id = "secret_finder",   icon = "🗝️", title = "Secret Finder",     desc = "Found the hidden secret of Mystic Pets...",  rarity = "Legendary" },
}

-- Build lookup by id
local BadgeLookup = {}
for _, b in ipairs(Badges) do BadgeLookup[b.id] = b end

function BadgeService.GetAll() return Badges end
function BadgeService.Get(id) return BadgeLookup[id] end

-- ============================================================
-- GRANT
-- ============================================================
function BadgeService.Grant(player, badgeId)
	local data = require(script.Parent.DataManager).GetData(player)
	if not data then return end

	data.Badges = data.Badges or {}
	-- Already earned?
	for _, earned in ipairs(data.Badges) do
		if earned == badgeId then return end
	end

	local badge = BadgeLookup[badgeId]
	if not badge then return end

	table.insert(data.Badges, badgeId)

	if RE_BadgeEarned then
		RE_BadgeEarned:FireClient(player, badge)
	end
	print("[BadgeService] " .. player.Name .. " earned: " .. badge.title)
end

function BadgeService.SetRemote(remote)
	RE_BadgeEarned = remote
end

-- ============================================================
-- CHECK ALL CONDITIONS for a player (call after any data change)
-- ============================================================
function BadgeService.CheckAll(player)
	local data = require(script.Parent.DataManager).GetData(player)
	if not data then return end

	data.Badges = data.Badges or {}

	local function grant(id) BadgeService.Grant(player, id) end
	local function has(id)
		for _, b in ipairs(data.Badges) do if b == id then return true end end
		return false
	end

	-- Welcome (always on first check)
	if not has("welcome") then grant("welcome") end

	-- Pet count
	local petCount = #(data.Pets or {})
	if petCount >= 1  then grant("first_pet")    end
	if petCount >= 5  then grant("collector_5")  end
	if petCount >= 25 then grant("collector_25") end
	if petCount >= 50 then grant("collector_50") end

	-- Rarity milestones
	local rarityFound = { Rare=false, Epic=false, Legendary=false, Mythic=false }
	for _, pet in ipairs(data.Pets or {}) do
		if rarityFound[pet.rarity] ~= nil then rarityFound[pet.rarity] = true end
	end
	if rarityFound.Rare      then grant("first_rare")      end
	if rarityFound.Epic      then grant("first_epic")      end
	if rarityFound.Legendary then grant("first_legendary") end
	if rarityFound.Mythic    then grant("first_mythic")    end

	-- Eggs hatched
	local eggsHatched = data.EggsHatched or 0
	if eggsHatched >= 10  then grant("hatch_10")  end
	if eggsHatched >= 100 then grant("hatch_100") end
	if eggsHatched >= 500 then grant("hatch_500") end

	-- Coins earned
	local total = data.TotalCoinsEarned or 0
	if total >= 1000        then grant("coins_1k")  end
	if total >= 100000      then grant("coins_100k") end
	if total >= 1000000     then grant("coins_1m")   end
	if total >= 1000000000  then grant("coins_1b")   end

	-- Areas unlocked
	local areaSet = {}
	for _, a in ipairs(data.UnlockedAreas or {}) do areaSet[a] = true end
	if areaSet.Forest  then grant("unlock_forest")  end
	if areaSet.Desert  then grant("unlock_desert")  end
	if areaSet.Volcano then grant("unlock_volcano") end
	if areaSet.Space   then grant("unlock_space")   end

	-- Rebirths
	local rebirths = data.Rebirths or 0
	if rebirths >= 1 then grant("first_rebirth") end
	if rebirths >= 3 then grant("rebirth_3")     end
	if rebirths >= 6 then grant("rebirth_6")     end
end

return BadgeService
