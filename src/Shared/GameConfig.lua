-- MysticPets: GameConfig.lua
-- Place in: ReplicatedStorage > Shared > GameConfig (ModuleScript)

local GameConfig = {}

-- ============================================================
-- PETS
-- ============================================================
GameConfig.Pets = {
	-- Common
	{ name = "Kitten",          rarity = "Common",    coinMult = 1,    gemMult = 0,    size = 1.0,  color = Color3.fromRGB(220, 220, 220) },
	{ name = "Puppy",           rarity = "Common",    coinMult = 1.2,  gemMult = 0,    size = 1.0,  color = Color3.fromRGB(190, 150, 90)  },
	{ name = "Bunny",           rarity = "Common",    coinMult = 1.5,  gemMult = 0,    size = 0.9,  color = Color3.fromRGB(255, 255, 255) },
	{ name = "Chick",           rarity = "Common",    coinMult = 1.3,  gemMult = 0,    size = 0.8,  color = Color3.fromRGB(255, 230, 50)  },
	-- Uncommon
	{ name = "Fox",             rarity = "Uncommon",  coinMult = 3,    gemMult = 0.1,  size = 1.1,  color = Color3.fromRGB(230, 120, 30)  },
	{ name = "Wolf",            rarity = "Uncommon",  coinMult = 4,    gemMult = 0.1,  size = 1.2,  color = Color3.fromRGB(100, 100, 130) },
	{ name = "Owl",             rarity = "Uncommon",  coinMult = 3.5,  gemMult = 0.1,  size = 0.9,  color = Color3.fromRGB(120, 80, 40)   },
	-- Rare
	{ name = "Panda",           rarity = "Rare",      coinMult = 8,    gemMult = 0.5,  size = 1.3,  color = Color3.fromRGB(40, 40, 40)    },
	{ name = "Tiger",           rarity = "Rare",      coinMult = 10,   gemMult = 0.5,  size = 1.3,  color = Color3.fromRGB(255, 140, 0)   },
	{ name = "Snow Leopard",    rarity = "Rare",      coinMult = 12,   gemMult = 0.7,  size = 1.2,  color = Color3.fromRGB(220, 220, 255) },
	-- Epic
	{ name = "Dragon",          rarity = "Epic",      coinMult = 25,   gemMult = 2,    size = 1.5,  color = Color3.fromRGB(150, 0, 200)   },
	{ name = "Phoenix",         rarity = "Epic",      coinMult = 30,   gemMult = 2,    size = 1.4,  color = Color3.fromRGB(255, 80, 0)    },
	{ name = "Kirin",           rarity = "Epic",      coinMult = 28,   gemMult = 2.5,  size = 1.5,  color = Color3.fromRGB(0, 200, 150)   },
	-- Legendary
	{ name = "Unicorn",         rarity = "Legendary", coinMult = 75,   gemMult = 5,    size = 1.8,  color = Color3.fromRGB(255, 100, 255) },
	{ name = "Cosmic Griffin",  rarity = "Legendary", coinMult = 100,  gemMult = 7,    size = 1.8,  color = Color3.fromRGB(255, 215, 0)   },
	{ name = "Shadow Wolf",     rarity = "Legendary", coinMult = 90,   gemMult = 6,    size = 1.7,  color = Color3.fromRGB(30, 0, 60)     },
	-- Mythic
	{ name = "Celestial Dragon",rarity = "Mythic",    coinMult = 300,  gemMult = 20,   size = 2.2,  color = Color3.fromRGB(0, 200, 255)   },
	{ name = "Star Phoenix",    rarity = "Mythic",    coinMult = 500,  gemMult = 30,   size = 2.2,  color = Color3.fromRGB(255, 255, 100) },
	{ name = "Void Serpent",    rarity = "Mythic",    coinMult = 400,  gemMult = 25,   size = 2.4,  color = Color3.fromRGB(180, 0, 255)   },
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
		unlockCost = 5000,
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
		unlockCost = 75000,
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
		unlockCost = 2000000,
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
		unlockCost = 50000000,
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
