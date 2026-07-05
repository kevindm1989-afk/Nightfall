--!strict
--------------------------------------------------------------------------------
-- GameConfig
-- ReplicatedStorage.Config.GameConfig
--
-- Single source of truth for every balance number in the game.
-- Both the server (authoritative) and the client (display only) read this.
-- The server NEVER trusts a value sent by a client; it re-reads from here.
--------------------------------------------------------------------------------

local GameConfig = {}

--------------------------------------------------------------------------------
-- MONETIZATION IDS
-- Replace the placeholder numbers with your live IDs from the Creator Dashboard.
--------------------------------------------------------------------------------
GameConfig.Gamepasses = {
	DoubleCoins = {
		Id = 7654321,
		Name = "2x Coins",
		Description = "Permanently doubles all Gold earned from nodes, enemies and bosses!",
		Effect = { CoinMultiplier = 2 },
	},
	VIPLuck = {
		Id = 1234567, -- <== the luck pass checked inside PetSystem (rare odds x1.5)
		Name = "VIP Luck",
		Description = "Multiplies your Rare, Epic and Mythic hatch odds by 1.5x, forever!",
		Effect = { RareOddsMultiplier = 1.5 },
	},
	AutoHatch = {
		Id = 7654323,
		Name = "Auto-Hatch",
		Description = "Automatically re-hatches your last egg every 3 seconds. AFK-friendly!",
		Effect = { AutoHatch = true },
	},
}

GameConfig.DeveloperProducts = {
	Coins100 = {
		Id = 1111111,
		Name = "100 Coins",
		Grant = { Gold = 100 },
	},
	Coins500 = {
		Id = 1111112,
		Name = "500 Coins",
		Grant = { Gold = 500 },
	},
	MegaEggRoll = {
		Id = 1111113,
		Name = "Mega Egg Roll",
		-- Grants one hatch from the premium "MegaEgg" table (see Eggs below).
		Grant = { EggRoll = "MegaEgg" },
	},
}

--------------------------------------------------------------------------------
-- WEAPONS
-- BaseDamage feeds CoreEngine's damage formula:
--   Damage = Weapon.BaseDamage + sum(equipped pet StatBonus)
--------------------------------------------------------------------------------
GameConfig.Weapons = {
	WoodenSword   = { BaseDamage = 5,    Cost = 0,        Zone = 1, DisplayName = "Wooden Sword" },
	IronCleaver   = { BaseDamage = 14,   Cost = 750,      Zone = 1, DisplayName = "Iron Cleaver" },
	MysticBlade   = { BaseDamage = 32,   Cost = 4200,     Zone = 1, DisplayName = "Mystic Blade" },
	MagmaEdge     = { BaseDamage = 75,   Cost = 18500,    Zone = 2, DisplayName = "Magma Edge" },
	ObsidianFang  = { BaseDamage = 160,  Cost = 62000,    Zone = 2, DisplayName = "Obsidian Fang" },
	CrystalPike   = { BaseDamage = 340,  Cost = 210000,   Zone = 3, DisplayName = "Crystal Pike" },
	PrismSaber    = { BaseDamage = 720,  Cost = 690000,   Zone = 3, DisplayName = "Prism Saber" },
	NeonKatana    = { BaseDamage = 1500, Cost = 2300000,  Zone = 4, DisplayName = "Neon Katana" },
	VoidReaver    = { BaseDamage = 3200, Cost = 7800000,  Zone = 4, DisplayName = "Void Reaver" },
}
GameConfig.DefaultWeapon = "WoodenSword"

--------------------------------------------------------------------------------
-- PETS
-- Tier weights are the LIVE hatch odds (must be maintained here, PetSystem
-- consumes them). StatBonus is flat damage added to every swing.
--------------------------------------------------------------------------------
GameConfig.PetTiers = {
	-- Order matters for UI sorting only; PetSystem uses Weight.
	{ Tier = "Common",   Weight = 50.0, Color = Color3.fromRGB(190, 190, 190) },
	{ Tier = "Uncommon", Weight = 30.0, Color = Color3.fromRGB( 80, 200,  80) },
	{ Tier = "Rare",     Weight = 15.0, Color = Color3.fromRGB( 60, 120, 255) },
	{ Tier = "Epic",     Weight = 4.5,  Color = Color3.fromRGB(170,  60, 255) },
	{ Tier = "Mythic",   Weight = 0.5,  Color = Color3.fromRGB(255, 170,   0) },
}

-- Tiers considered "rare-tier" for the VIP Luck gamepass (odds x1.5)
GameConfig.RareTierSet = { Rare = true, Epic = true, Mythic = true }

GameConfig.Pets = {
	-- Common
	ForestBunny  = { Tier = "Common",   StatBonus = 2,    Mesh = "MDL_Pet_ForestBunny"  },
	PebbleTurtle = { Tier = "Common",   StatBonus = 3,    Mesh = "MDL_Pet_PebbleTurtle" },
	EmberMouse   = { Tier = "Common",   StatBonus = 4,    Mesh = "MDL_Pet_EmberMouse"   },
	-- Uncommon
	MossFox      = { Tier = "Uncommon", StatBonus = 8,    Mesh = "MDL_Pet_MossFox"      },
	CinderCat    = { Tier = "Uncommon", StatBonus = 11,   Mesh = "MDL_Pet_CinderCat"    },
	GlimmerBat   = { Tier = "Uncommon", StatBonus = 14,   Mesh = "MDL_Pet_GlimmerBat"   },
	-- Rare
	ShardWolf    = { Tier = "Rare",     StatBonus = 30,   Mesh = "MDL_Pet_ShardWolf"    },
	LavaHound    = { Tier = "Rare",     StatBonus = 38,   Mesh = "MDL_Pet_LavaHound"    },
	SkyKoi       = { Tier = "Rare",     StatBonus = 46,   Mesh = "MDL_Pet_SkyKoi"       },
	-- Epic
	PrismGolem   = { Tier = "Epic",     StatBonus = 110,  Mesh = "MDL_Pet_PrismGolem"   },
	NovaDrake    = { Tier = "Epic",     StatBonus = 145,  Mesh = "MDL_Pet_NovaDrake"    },
	-- Mythic
	VoidSeraph   = { Tier = "Mythic",   StatBonus = 500,  Mesh = "MDL_Pet_VoidSeraph"   },
	ChronoLion   = { Tier = "Mythic",   StatBonus = 650,  Mesh = "MDL_Pet_ChronoLion"   },
}

--------------------------------------------------------------------------------
-- EGGS
-- Pool = which pets can hatch. PetSystem intersects the pool with tier weights.
--------------------------------------------------------------------------------
GameConfig.Eggs = {
	ForestEgg = {
		Cost = 250, Currency = "Gold", Zone = 1,
		Pool = { "ForestBunny", "PebbleTurtle", "MossFox", "ShardWolf", "PrismGolem", "VoidSeraph" },
	},
	MagmaEgg = {
		Cost = 12000, Currency = "Gold", Zone = 2,
		Pool = { "EmberMouse", "CinderCat", "LavaHound", "NovaDrake", "VoidSeraph" },
	},
	CrystalEgg = {
		Cost = 480000, Currency = "Gold", Zone = 3,
		Pool = { "PebbleTurtle", "GlimmerBat", "SkyKoi", "PrismGolem", "ChronoLion" },
	},
	CyberEgg = {
		Cost = 5200000, Currency = "Gold", Zone = 4,
		Pool = { "GlimmerBat", "CinderCat", "ShardWolf", "NovaDrake", "VoidSeraph", "ChronoLion" },
	},
	-- Premium egg ONLY obtainable through the MegaEggRoll developer product.
	MegaEgg = {
		Cost = 0, Currency = "Robux", Zone = 0,
		Pool = { "ShardWolf", "LavaHound", "SkyKoi", "PrismGolem", "NovaDrake", "VoidSeraph", "ChronoLion" },
		-- Mega eggs use boosted base weights (still passed through luck/gamepass).
		WeightOverride = {
			Common = 0, Uncommon = 0, Rare = 60, Epic = 32, Mythic = 8,
		},
	},
}

--------------------------------------------------------------------------------
-- ZONES / RESOURCE NODES / ENEMIES / BOSSES
--------------------------------------------------------------------------------
GameConfig.Zones = {
	[1] = {
		Name = "Mystic Forest",
		UnlockCost = 0,
		Nodes = {
			OakNode     = { Health = 40,   GoldReward = 8,    RespawnSeconds = 6  },
			MossyRock   = { Health = 90,   GoldReward = 20,   RespawnSeconds = 9  },
			ElderTrunk  = { Health = 250,  GoldReward = 65,   RespawnSeconds = 14 },
		},
		Enemies = {
			ThornSprite = { Health = 120,  GoldReward = 30,   RespawnSeconds = 10 },
			BarkGolem   = { Health = 400,  GoldReward = 120,  RespawnSeconds = 18 },
		},
		Boss = "VerdantColossus",
	},
	[2] = {
		Name = "Magma Core",
		UnlockCost = 25000,
		Nodes = {
			BasaltChunk = { Health = 600,   GoldReward = 150,  RespawnSeconds = 7  },
			LavaGeode   = { Health = 1400,  GoldReward = 380,  RespawnSeconds = 10 },
			ObsidianVein= { Health = 3600,  GoldReward = 1050, RespawnSeconds = 15 },
		},
		Enemies = {
			MagmaImp    = { Health = 1800,  GoldReward = 520,  RespawnSeconds = 11 },
			CinderBrute = { Health = 5500,  GoldReward = 1700, RespawnSeconds = 20 },
		},
		Boss = "InfernalTitan",
	},
	[3] = {
		Name = "Crystal Skyway",
		UnlockCost = 900000,
		Nodes = {
			QuartzSpire  = { Health = 9000,   GoldReward = 2400,  RespawnSeconds = 8  },
			PrismCluster = { Health = 22000,  GoldReward = 6300,  RespawnSeconds = 11 },
			AuroraShard  = { Health = 56000,  GoldReward = 17000, RespawnSeconds = 16 },
		},
		Enemies = {
			ShardWisp    = { Health = 28000,  GoldReward = 8600,  RespawnSeconds = 12 },
			GlassSentinel= { Health = 84000,  GoldReward = 27000, RespawnSeconds = 22 },
		},
		Boss = "PrismarchSeraph",
	},
	[4] = {
		Name = "Cyber-Abyss",
		UnlockCost = 30000000,
		Nodes = {
			DataNode     = { Health = 140000,  GoldReward = 40000,   RespawnSeconds = 8  },
			NeonConduit  = { Health = 350000,  GoldReward = 105000,  RespawnSeconds = 12 },
			CoreFragment = { Health = 900000,  GoldReward = 290000,  RespawnSeconds = 17 },
		},
		Enemies = {
			GlitchStalker = { Health = 450000,  GoldReward = 145000, RespawnSeconds = 13 },
			AbyssWarform  = { Health = 1350000, GoldReward = 470000, RespawnSeconds = 24 },
		},
		Boss = "OmegaNull",
	},
}

--------------------------------------------------------------------------------
-- BOSSES
-- HP formula (server-authoritative, also documented in docs/MapSpecifications.md):
--   BossHP(zone, rebirths) = BaseHP * (HPGrowth ^ (zone - 1)) * (1 + 0.35 * rebirths)
-- BaseHP = 2500, HPGrowth = 6.0 -- yields 2.5k / 15k / 90k / 540k pre-rebirth,
-- then each zone entry below overrides with its final tuned value.
--------------------------------------------------------------------------------
GameConfig.BossBaseHP = 2500
GameConfig.BossHPGrowth = 6.0
GameConfig.BossRebirthHPScalar = 0.35

GameConfig.Bosses = {
	VerdantColossus = {
		Zone = 1,
		Health = 2500,
		GoldReward = 900,
		RespawnSeconds = 90,
		-- Weighted loot rolls: every kill rolls this table exactly twice.
		RollsPerKill = 2,
		LootTable = {
			{ Item = "Gold_Small",       Type = "Gold",   Amount = 350,       Weight = 40.0 },
			{ Item = "Gold_Large",       Type = "Gold",   Amount = 1200,      Weight = 20.0 },
			{ Item = "Gems_Handful",     Type = "Gems",   Amount = 5,         Weight = 18.0 },
			{ Item = "IronCleaver",      Type = "Weapon", Amount = 1,         Weight = 10.0 },
			{ Item = "ForestEgg_Free",   Type = "Egg",    Egg = "ForestEgg",  Weight = 8.0  },
			{ Item = "MysticBlade",      Type = "Weapon", Amount = 1,         Weight = 3.5  },
			{ Item = "ShardWolf",        Type = "Pet",    Amount = 1,         Weight = 0.5  },
		},
	},
	InfernalTitan = {
		Zone = 2,
		Health = 15000,
		GoldReward = 6500,
		RespawnSeconds = 120,
		RollsPerKill = 2,
		LootTable = {
			{ Item = "Gold_Small",       Type = "Gold",   Amount = 2500,      Weight = 38.0 },
			{ Item = "Gold_Large",       Type = "Gold",   Amount = 9000,      Weight = 20.0 },
			{ Item = "Gems_Handful",     Type = "Gems",   Amount = 15,        Weight = 18.0 },
			{ Item = "MagmaEdge",        Type = "Weapon", Amount = 1,         Weight = 11.0 },
			{ Item = "MagmaEgg_Free",    Type = "Egg",    Egg = "MagmaEgg",   Weight = 8.0  },
			{ Item = "ObsidianFang",     Type = "Weapon", Amount = 1,         Weight = 4.0  },
			{ Item = "LavaHound",        Type = "Pet",    Amount = 1,         Weight = 0.8  },
			{ Item = "NovaDrake",        Type = "Pet",    Amount = 1,         Weight = 0.2  },
		},
	},
	PrismarchSeraph = {
		Zone = 3,
		Health = 90000,
		GoldReward = 52000,
		RespawnSeconds = 150,
		RollsPerKill = 3,
		LootTable = {
			{ Item = "Gold_Small",       Type = "Gold",   Amount = 20000,     Weight = 36.0 },
			{ Item = "Gold_Large",       Type = "Gold",   Amount = 70000,     Weight = 20.0 },
			{ Item = "Gems_Handful",     Type = "Gems",   Amount = 40,        Weight = 18.0 },
			{ Item = "CrystalPike",      Type = "Weapon", Amount = 1,         Weight = 11.0 },
			{ Item = "CrystalEgg_Free",  Type = "Egg",    Egg = "CrystalEgg", Weight = 9.0  },
			{ Item = "PrismSaber",       Type = "Weapon", Amount = 1,         Weight = 4.5  },
			{ Item = "PrismGolem",       Type = "Pet",    Amount = 1,         Weight = 1.2  },
			{ Item = "ChronoLion",       Type = "Pet",    Amount = 1,         Weight = 0.3  },
		},
	},
	OmegaNull = {
		Zone = 4,
		Health = 540000,
		GoldReward = 400000,
		RespawnSeconds = 180,
		RollsPerKill = 3,
		LootTable = {
			{ Item = "Gold_Small",       Type = "Gold",   Amount = 160000,    Weight = 34.0 },
			{ Item = "Gold_Large",       Type = "Gold",   Amount = 550000,    Weight = 20.0 },
			{ Item = "Gems_Handful",     Type = "Gems",   Amount = 100,       Weight = 18.0 },
			{ Item = "NeonKatana",       Type = "Weapon", Amount = 1,         Weight = 12.0 },
			{ Item = "CyberEgg_Free",    Type = "Egg",    Egg = "CyberEgg",   Weight = 9.0  },
			{ Item = "VoidReaver",       Type = "Weapon", Amount = 1,         Weight = 5.0  },
			{ Item = "VoidSeraph",       Type = "Pet",    Amount = 1,         Weight = 1.5  },
			{ Item = "ChronoLion",       Type = "Pet",    Amount = 1,         Weight = 0.5  },
		},
	},
}

--------------------------------------------------------------------------------
-- COMBAT / ANTI-EXPLOIT TUNING
--------------------------------------------------------------------------------
GameConfig.Combat = {
	SwingCooldown = 0.35,      -- server-enforced seconds between accepted swings
	MaxHitDistance = 22,       -- studs; server rejects hits beyond this range
	MaxEquippedPets = 4,       -- pets contributing StatBonus simultaneously
	MaxOwnedPets = 200,        -- inventory hard cap
}

--------------------------------------------------------------------------------
-- REBIRTH
--------------------------------------------------------------------------------
GameConfig.Rebirth = {
	-- Cost of the Nth rebirth: BaseCost * (CostGrowth ^ currentRebirths)
	BaseCost = 100000,
	CostGrowth = 3.5,
	-- Each rebirth adds +0.5x to CoinMultiplier and +0.1x to LuckMultiplier.
	CoinMultiplierPerRebirth = 0.5,
	LuckMultiplierPerRebirth = 0.1,
}

GameConfig.AutoSaveIntervalSeconds = 300

return GameConfig
