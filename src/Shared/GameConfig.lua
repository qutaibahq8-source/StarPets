-- MysticPets: GameConfig.lua
-- Place in: ReplicatedStorage > Shared > GameConfig (ModuleScript)

local GameConfig = {}

-- ============================================================
-- PETS
-- ============================================================
GameConfig.Pets = {
	-- Common
	{ name = "ant", rarity = "Common", coinMult = 60, gemMult = 0, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "worm", rarity = "Common", coinMult = 70, gemMult = 0, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "bee", rarity = "Common", coinMult = 90, gemMult = 0, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "rat", rarity = "Common", coinMult = 80, gemMult = 0, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "chicken", rarity = "Common", coinMult = 110, gemMult = 0, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "fish", rarity = "Common", coinMult = 100, gemMult = 0, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "cat", rarity = "Common", coinMult = 130, gemMult = 0, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "dog", rarity = "Common", coinMult = 140, gemMult = 0, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "rabbit", rarity = "Common", coinMult = 150, gemMult = 0, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "squirrel", rarity = "Common", coinMult = 120, gemMult = 0, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "ladybug", rarity = "Common", coinMult = 95, gemMult = 0, size = 1.0, color = Color3.fromRGB(200,200,200) },
	-- Uncommon
	{ name = "fox", rarity = "Uncommon", coinMult = 400, gemMult = 0.1, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "owl", rarity = "Uncommon", coinMult = 450, gemMult = 0.1, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "koala", rarity = "Uncommon", coinMult = 500, gemMult = 0.1, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "monkey", rarity = "Uncommon", coinMult = 520, gemMult = 0.1, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "parrot", rarity = "Uncommon", coinMult = 480, gemMult = 0.1, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "seal", rarity = "Uncommon", coinMult = 550, gemMult = 0.1, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "penguin", rarity = "Uncommon", coinMult = 600, gemMult = 0.1, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "raccoon", rarity = "Uncommon", coinMult = 560, gemMult = 0.1, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "bat", rarity = "Uncommon", coinMult = 620, gemMult = 0.1, size = 1.0, color = Color3.fromRGB(200,200,200) },
	-- Rare
	{ name = "panda", rarity = "Rare", coinMult = 1500, gemMult = 0.5, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "bear", rarity = "Rare", coinMult = 1800, gemMult = 0.5, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "wolf", rarity = "Rare", coinMult = 2000, gemMult = 0.5, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "eagle", rarity = "Rare", coinMult = 2200, gemMult = 0.5, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "dolphin", rarity = "Rare", coinMult = 2400, gemMult = 0.5, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "flamingo", rarity = "Rare", coinMult = 2600, gemMult = 0.5, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "camel", rarity = "Rare", coinMult = 2800, gemMult = 0.5, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "horse", rarity = "Rare", coinMult = 3000, gemMult = 0.5, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "hippo", rarity = "Rare", coinMult = 3200, gemMult = 0.5, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "elephant", rarity = "Rare", coinMult = 3500, gemMult = 0.5, size = 1.0, color = Color3.fromRGB(200,200,200) },
	-- Epic
	{ name = "dragon", rarity = "Epic", coinMult = 12000, gemMult = 2, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "crocodile", rarity = "Epic", coinMult = 9000, gemMult = 2, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "shark", rarity = "Epic", coinMult = 11000, gemMult = 2, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "scorpion", rarity = "Epic", coinMult = 10000, gemMult = 2, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "spider", rarity = "Epic", coinMult = 9500, gemMult = 2, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "buffalo", rarity = "Epic", coinMult = 13000, gemMult = 2, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "bull", rarity = "Epic", coinMult = 13500, gemMult = 2, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "snake", rarity = "Epic", coinMult = 10500, gemMult = 2, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "butterfly", rarity = "Epic", coinMult = 8500, gemMult = 2, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "axolotl", rarity = "Epic", coinMult = 14000, gemMult = 2, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "walrus", rarity = "Epic", coinMult = 15000, gemMult = 2, size = 1.0, color = Color3.fromRGB(200,200,200) },
	-- Legendary
	{ name = "peacock", rarity = "Legendary", coinMult = 45000, gemMult = 6, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "super fox", rarity = "Legendary", coinMult = 60000, gemMult = 6, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "snow ram", rarity = "Legendary", coinMult = 70000, gemMult = 6, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "ray fish", rarity = "Legendary", coinMult = 55000, gemMult = 6, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "fawn", rarity = "Legendary", coinMult = 48000, gemMult = 6, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "snowman", rarity = "Legendary", coinMult = 65000, gemMult = 6, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "desert snake", rarity = "Legendary", coinMult = 52000, gemMult = 6, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "wight bear", rarity = "Legendary", coinMult = 80000, gemMult = 6, size = 1.0, color = Color3.fromRGB(200,200,200) },
	-- Mythic
	{ name = "Reindeer", rarity = "Mythic", coinMult = 500000, gemMult = 25, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "goldenpeacock", rarity = "Mythic", coinMult = 900000, gemMult = 30, size = 1.0, color = Color3.fromRGB(200,200,200) },
	{ name = "Void Serpent", rarity = "Mythic", coinMult = 2000000, gemMult = 50, size = 1.0, color = Color3.fromRGB(180,0,255) },  -- THE BEST
}

-- ============================================================
-- MUTATIONS  (rolled on hatch; multiply a pet's earnings)
-- Listed rarest-first so the best one you roll wins.
-- ============================================================
GameConfig.Mutations = {
	{ id="Rainbow", name="Rainbow", emoji="🌈", mult=10, chance=0.004, color=Color3.fromRGB(255,120,220) },
	{ id="Shiny",   name="Shiny",   emoji="✨", mult=4,  chance=0.02,  color=Color3.fromRGB(120,230,255) },
	{ id="Golden",  name="Golden",  emoji="🌟", mult=2,  chance=0.06,  color=Color3.fromRGB(255,215,0)   },
}
function GameConfig.GetMutation(id)
	if not id then return nil end
	for _, m in ipairs(GameConfig.Mutations) do if m.id == id then return m end end
	return nil
end

-- ============================================================
-- CODES  (redeemable for rewards; add more any time)
-- ============================================================
-- Keep these modest — small early-game boosts, NOT game-breakers.
-- (No best pets, no huge sums that skip islands. Forest costs 250k, so
--  rewards stay well under that.)
GameConfig.Codes = {
	WELCOME = { coins=15000, gems=30,  label="Welcome gift" },
	RELEASE = { coins=30000, gems=60,  label="Release reward" },
	LUCKY   = { gems=120,              label="Lucky gems" },
	THANKS  = { coins=50000,           label="Thank you!" },
}

-- ============================================================
-- RARITIES
-- ============================================================
GameConfig.Rarities = {
	Common    = { color = Color3.fromRGB(180, 180, 180), displayName = "Common",    gradient = { Color3.fromRGB(180,180,180), Color3.fromRGB(220,220,220) } },
	Uncommon  = { color = Color3.fromRGB(50,  200, 50),  displayName = "Uncommon",  gradient = { Color3.fromRGB(30,150,30),   Color3.fromRGB(80,255,80)   } },
	Rare      = { color = Color3.fromRGB(50,  100, 255), displayName = "Rare",      gradient = { Color3.fromRGB(0,50,200),    Color3.fromRGB(100,160,255) } },
	Epic      = { color = Color3.fromRGB(150, 0,   200), displayName = "Epic",      gradient = { Color3.fromRGB(100,0,150),   Color3.fromRGB(220,50,255)  } },
	Legendary = { color = Color3.fromRGB(255, 165, 0),   displayName = "Legendary", gradient = { Color3.fromRGB(200,120,0),   Color3.fromRGB(255,220,50)  } },
	Mythic    = { color = Color3.fromRGB(0,   200, 255), displayName = "Mythic",    gradient = { Color3.fromRGB(0,100,200),   Color3.fromRGB(150,255,255) } },
}

-- ============================================================
-- EGGS
-- ============================================================
GameConfig.Eggs = {
	{
		id = "StarterEgg",
		name = "Starter Egg",
		cost = 0,           -- FREE only on first ever hatch (tracked by HasClaimedFreeEgg)
		costAfterFirst = 150, -- costs this after the free one
		currency = "Coins",
		color = Color3.fromRGB(100, 200, 100),
		description = "Your very first egg — FREE! Then 150 coins.",
		rarityWeights = { Common = 8000, Uncommon = 1700, Rare = 280, Epic = 18, Legendary = 2, Mythic = 0 },
	},
	{
		id = "CoolEgg",
		name = "Cool Egg",
		cost = 1500,
		currency = "Coins",
		color = Color3.fromRGB(50, 150, 255),
		description = "Better chances for rare pets!",
		rarityWeights = { Common = 5500, Uncommon = 3000, Rare = 1200, Epic = 260, Legendary = 39, Mythic = 1 },
	},
	{
		id = "RareEgg",
		name = "Rare Egg",
		cost = 20000,
		currency = "Coins",
		color = Color3.fromRGB(150, 50, 255),
		description = "High chance for epic and legendary pets!",
		rarityWeights = { Common = 1500, Uncommon = 3000, Rare = 3500, Epic = 1500, Legendary = 480, Mythic = 20 },
	},
	{
		id = "LegendaryEgg",
		name = "Legendary Egg",
		cost = 750,
		currency = "Gems",
		color = Color3.fromRGB(255, 215, 0),
		description = "The best egg in the game!",
		rarityWeights = { Common = 0, Uncommon = 500, Rare = 2000, Epic = 3500, Legendary = 3000, Mythic = 1000 },
	},
}

-- ============================================================
-- AREAS / BIOMES
-- ============================================================
GameConfig.Areas = {
	{
		id = "Meadow",
		name = "Starter Meadow",
		unlockCost = 0,
		currency = "Coins",
		coinOrbValue = 1,
		gemOrbChance = 0.01, -- 1% chance orb is a gem orb
		description = "The starting area. Fresh grass and friendly skies.",
		skyColor = Color3.fromRGB(135, 206, 235),
		groundColor = Color3.fromRGB(100, 180, 60),
	},
	{
		id = "Forest",
		name = "Mystic Forest",
		unlockCost = 250000,    -- ~10 min of Meadow income (commons)
		currency = "Coins",
		coinOrbValue = 8,
		gemOrbChance = 0.015,
		description = "Ancient trees hide great treasures.",
		skyColor = Color3.fromRGB(50, 100, 50),
		groundColor = Color3.fromRGB(40, 100, 40),
	},
	{
		id = "Desert",
		name = "Golden Desert",
		unlockCost = 4000000,   -- ~10 min of Forest income (uncommon/rare pets)
		currency = "Coins",
		coinOrbValue = 40,
		gemOrbChance = 0.025,
		description = "Sand and gold stretch to the horizon.",
		skyColor = Color3.fromRGB(220, 180, 80),
		groundColor = Color3.fromRGB(210, 180, 50),
	},
	{
		id = "Volcano",
		name = "Inferno Volcano",
		unlockCost = 20000000,  -- ~10 min of Desert income (epic pets)
		currency = "Coins",
		coinOrbValue = 200,
		gemOrbChance = 0.04,
		description = "Heat and power in the heart of the earth.",
		skyColor = Color3.fromRGB(60, 10, 0),
		groundColor = Color3.fromRGB(80, 20, 0),
	},
	{
		id = "Space",
		name = "Star Space",
		unlockCost = 200000000, -- last island
		currency = "Coins",
		coinOrbValue = 2000,
		gemOrbChance = 0.08,
		description = "Beyond the sky, infinite riches await.",
		skyColor = Color3.fromRGB(5, 5, 20),
		groundColor = Color3.fromRGB(20, 20, 60),
	},
}

-- ============================================================
-- GAMEPASSES  (IDs filled in after publishing on Roblox)
-- ============================================================
GameConfig.Gamepasses = {
	{ key = "GP_2xCoins",     name = "2x Coins",       price = 299,  robloxId = 0, benefit = "All coin earnings doubled forever!" },
	{ key = "GP_AutoCollect", name = "Auto Collect",    price = 199,  robloxId = 0, benefit = "Orbs fly to you automatically!"    },
	{ key = "GP_VIP",         name = "VIP",             price = 499,  robloxId = 0, benefit = "VIP tag + exclusive Mythic pet + 3x gems!" },
	{ key = "GP_PetSlots",    name = "+3 Pet Slots",    price = 399,  robloxId = 0, benefit = "Equip 6 pets instead of 3!"        },
	{ key = "GP_LuckyBoost",  name = "Lucky Boost",     price = 349,  robloxId = 0, benefit = "1.5x better egg luck always!"      },
}

-- ============================================================
-- TITLES  (checked in order — first match wins, so put best last)
-- ============================================================
GameConfig.Titles = {
	-- Default
	{ id="rookie",        label="Rookie",           color=Color3.fromRGB(180,180,180), req=function(d) return true end },
	-- Coin milestones
	{ id="coin_earner",   label="Coin Earner",       color=Color3.fromRGB(220,200,100), req=function(d) return (d.TotalCoinsEarned or 0)>=1000       end },
	{ id="rich",          label="Rich",               color=Color3.fromRGB(255,215,0),   req=function(d) return (d.TotalCoinsEarned or 0)>=100000      end },
	{ id="millionaire",   label="Millionaire 💰",     color=Color3.fromRGB(255,200,0),   req=function(d) return (d.TotalCoinsEarned or 0)>=1000000     end },
	{ id="billionaire",   label="Billionaire 🤑",     color=Color3.fromRGB(255,180,0),   req=function(d) return (d.TotalCoinsEarned or 0)>=1000000000  end },
	-- Pet milestones
	{ id="tamer",         label="Tamer 🐾",           color=Color3.fromRGB(100,220,100), req=function(d) return #(d.Pets or {})>=5   end },
	{ id="collector",     label="Collector 📦",       color=Color3.fromRGB(50,200,50),   req=function(d) return #(d.Pets or {})>=20  end },
	{ id="pet_hoarder",   label="Pet Hoarder 🏠",     color=Color3.fromRGB(0,200,100),   req=function(d) return #(d.Pets or {})>=50  end },
	-- Rarity titles
	{ id="rare_hunter",   label="Rare Hunter 💙",     color=Color3.fromRGB(50,100,255),  req=function(d)
		for _,p in ipairs(d.Pets or {}) do if p.rarity=="Rare" then return true end end return false end },
	{ id="epic_tamer",    label="Epic Tamer 💜",       color=Color3.fromRGB(150,0,220),   req=function(d)
		for _,p in ipairs(d.Pets or {}) do if p.rarity=="Epic" then return true end end return false end },
	{ id="legendary_lord",label="Legendary Lord 🏆",  color=Color3.fromRGB(255,165,0),   req=function(d)
		for _,p in ipairs(d.Pets or {}) do if p.rarity=="Legendary" then return true end end return false end },
	{ id="mythic_god",    label="Mythic God ✨",       color=Color3.fromRGB(0,220,255),   req=function(d)
		for _,p in ipairs(d.Pets or {}) do if p.rarity=="Mythic" then return true end end return false end },
	-- Rebirth titles
	{ id="reborn",        label="Reborn ♻️",          color=Color3.fromRGB(180,100,255), req=function(d) return (d.Rebirths or 0)>=1 end },
	{ id="rebirth_lord",  label="Rebirth Lord 🔄",    color=Color3.fromRGB(200,80,255),  req=function(d) return (d.Rebirths or 0)>=3 end },
	{ id="mystic_master", label="Mystic Master 🌙",   color=Color3.fromRGB(220,60,255),  req=function(d) return (d.Rebirths or 0)>=6 end },
	-- Secret
	{ id="secret_keeper", label="Secret Keeper 🗝️",  color=Color3.fromRGB(255,215,0),   req=function(d) return d.FoundSecret==true end },
	-- VIP
	{ id="vip",           label="⭐ VIP",             color=Color3.fromRGB(255,220,100), req=function(d) return d.GP_VIP==true end },
}

-- ============================================================
-- REBIRTHS
-- ============================================================
GameConfig.Rebirths = {
	{ level = 1,  requirement = 50000,       multiplier = 1.5,  title = "Novice"      },
	{ level = 2,  requirement = 500000,      multiplier = 2.0,  title = "Apprentice"  },
	{ level = 3,  requirement = 5000000,     multiplier = 3.0,  title = "Adept"       },
	{ level = 4,  requirement = 50000000,    multiplier = 5.0,  title = "Expert"      },
	{ level = 5,  requirement = 500000000,   multiplier = 10.0, title = "Master"      },
	{ level = 6,  requirement = 5000000000,  multiplier = 25.0, title = "Grandmaster" },
}

-- ============================================================
-- DEFAULT PLAYER DATA
-- ============================================================
GameConfig.DefaultData = {
	Coins              = 0,
	Gems               = 0,
	Pets               = {},
	EquippedPets       = {},
	UnlockedAreas      = { "Meadow" },
	Rebirths           = 0,
	RebirthMultiplier  = 1.0,
	TotalCoinsEarned   = 0,
	TotalGemsEarned    = 0,
	EggsHatched        = 0,
	HasClaimedFreeEgg  = false,   -- one free Starter Egg per account ever
	GP_2xCoins         = false,
	GP_AutoCollect     = false,
	GP_VIP             = false,
	GP_PetSlots        = false,
	GP_LuckyBoost      = false,
	Upgrades = {
		SpeedBoost = 0,
		JumpBoost  = 0,
		LuckyCharm = 0,
		CoinBonus  = 0,
	},
	FoundSecret = false,
	Quests = { claimed = {} },
	EventTokens = 0,
	EventClaimed = {},
	RedeemedCodes = {},
}

-- ============================================================
-- QUESTS  (progress is read from existing stats; claim for reward)
-- ============================================================
GameConfig.Quests = {
	{ id="hatch5",   name="First Hatches",  desc="Hatch 5 eggs",          type="hatch",   goal=5,        reward={coins=2500} },
	{ id="hatch25",  name="Egg Enjoyer",    desc="Hatch 25 eggs",         type="hatch",   goal=25,       reward={gems=100} },
	{ id="hatch100", name="Egg Master",     desc="Hatch 100 eggs",        type="hatch",   goal=100,      reward={gems=500} },
	{ id="coins10k", name="Coin Collector", desc="Earn 10,000 coins",     type="coins",   goal=10000,    reward={gems=50} },
	{ id="coins1m",  name="Coin Tycoon",    desc="Earn 1,000,000 coins",  type="coins",   goal=1000000,  reward={gems=300} },
	{ id="unlock2",  name="Explorer",       desc="Unlock 2 worlds",       type="areas",   goal=2,        reward={coins=15000} },
	{ id="unlock5",  name="Globetrotter",   desc="Unlock all worlds",     type="areas",   goal=4,        reward={gems=400} },
	{ id="rebirth1", name="Reborn",         desc="Rebirth once",          type="rebirth", goal=1,        reward={gems=250} },
	{ id="equip3",   name="Pet Squad",      desc="Equip 3 pets at once",  type="equip",   goal=3,        reward={coins=8000} },
}

-- ============================================================
-- TRAVELING MERCHANT  (spawns on a cycle, sells rotating stock)
-- ============================================================
GameConfig.Merchant = {
	StayTime = 120,   -- seconds the merchant stays
	GapTime  = 240,   -- seconds between visits
	StockSize = 4,    -- items offered per visit
}
-- Pool the merchant draws its rotating stock from
GameConfig.MerchantPool = {
	{ kind="pet",   name="Dragon",        rarity="Legendary", cost=4000,   cur="Gems",  label="🐉 Dragon" },
	{ kind="pet",   name="Phoenix",       rarity="Legendary", cost=6000,   cur="Gems",  label="🔥 Phoenix" },
	{ kind="pet",   name="Unicorn",       rarity="Legendary", cost=5000,   cur="Gems",  label="🦄 Unicorn" },
	{ kind="pet",   name="Shadow Wolf",   rarity="Epic",      cost=2500,   cur="Gems",  label="🐺 Shadow Wolf" },
	{ kind="pet",   name="Kirin",         rarity="Mythic",    cost=12000,  cur="Gems",  label="✨ Kirin" },
	{ kind="coins", amount=100000,        cost=300,    cur="Gems",  label="💰 100K Coins" },
	{ kind="coins", amount=1000000,       cost=2000,   cur="Gems",  label="💰 1M Coins" },
	{ kind="gems",  amount=500,           cost=200000, cur="Coins", label="💎 500 Gems" },
	{ kind="boost", key="GP_2xCoins",     cost=3000,   cur="Gems",  label="⚡ 2x Coins (perk)" },
	{ kind="boost", key="GP_LuckyBoost",  cost=3500,   cur="Gems",  label="🍀 Lucky Boost (perk)" },
}

-- ============================================================
-- LIMITED-TIME EVENTS  (toggle on/off; earn event tokens, spend in event shop)
-- ============================================================
GameConfig.Events = {
	summer = {
		name = "☀️ Summer Festival",
		tokenName = "Sun Tokens", tokenIcon = "☀️",
		shop = {
			{ kind="coins", amount=5000000,  cost=40,  label="💰 5M Coins" },
			{ kind="pet", name="Phoenix",      rarity="Legendary", cost=120, label="🔥 Phoenix" },
			{ kind="pet", name="Star Phoenix", rarity="Mythic",    cost=600, label="🌟 Star Phoenix (EVENT)" },
		},
	},
	winter = {
		name = "❄️ Winter Wonderland",
		tokenName = "Snowflakes", tokenIcon = "❄️",
		shop = {
			{ kind="coins", amount=5000000,  cost=40,  label="💰 5M Coins" },
			{ kind="pet", name="Snow Leopard", rarity="Rare",   cost=80,  label="🐆 Snow Leopard" },
			{ kind="pet", name="Celestial Dragon", rarity="Mythic", cost=600, label="🐉 Celestial Dragon (EVENT)" },
		},
	},
}

-- ============================================================
-- UPGRADES
-- ============================================================
GameConfig.Upgrades = {
	{
		key = "SpeedBoost", name = "Speed Boost", icon = "⚡",
		desc = "Move faster around the map",
		levels = {
			{ cost = 500,    value = 20,  label = "Swift"     },
			{ cost = 4000,   value = 24,  label = "Fast"      },
			{ cost = 15000,  value = 28,  label = "Blazing"   },
			{ cost = 50000,  value = 34,  label = "Lightning" },
		},
		default = 16,
	},
	{
		key = "JumpBoost", name = "Jump Boost", icon = "🦘",
		desc = "Jump higher across the map",
		levels = {
			{ cost = 300,    value = 65,  label = "Hopper"   },
			{ cost = 2500,   value = 80,  label = "Bouncer"  },
			{ cost = 10000,  value = 95,  label = "Leaper"   },
			{ cost = 35000,  value = 115, label = "Moonwalk" },
		},
		default = 50,
	},
	{
		key = "LuckyCharm", name = "Lucky Charm", icon = "🍀",
		desc = "Better egg odds on every hatch",
		levels = {
			{ cost = 2000,   value = 1.1,  label = "Fortunate" },
			{ cost = 12000,  value = 1.22, label = "Lucky"     },
			{ cost = 40000,  value = 1.38, label = "Blessed"   },
		},
		default = 1.0,
	},
	{
		key = "CoinBonus", name = "Coin Bonus", icon = "💰",
		desc = "Multiply coins earned from orbs",
		levels = {
			{ cost = 1000,   value = 1.25, label = "Thrifty" },
			{ cost = 7000,   value = 1.6,  label = "Wealthy" },
			{ cost = 28000,  value = 2.2,  label = "Rich"    },
			{ cost = 90000,  value = 3.5,  label = "Tycoon"  },
		},
		default = 1.0,
	},
}

-- Secret spot reward (one-time per account)
GameConfig.SecretReward = { coins = 750, gems = 5 }

-- ============================================================
-- SETTINGS
-- ============================================================
GameConfig.Settings = {
	MaxPetsInInventory    = 100,
	DefaultPetSlots       = 3,
	VIPPetSlots           = 6,
	CoinOrbRespawnTime    = 6,       -- slower respawn = harder grind
	PetIncomeInterval     = 1,
	DataSaveInterval      = 60,
	PetFollowSpeed        = 18,
	MaxPetFollowDistance  = 10,
	OrbCollectRadius      = 7,
	HatchAnimDuration     = 3,
	LuckyBoostMultiplier  = 1.5,
	VIPGemMultiplier      = 3.0,
}

return GameConfig
