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
	StarterPack = {
		Id = 1111118,
		Name = "Starter Pack",
		Description = "ONE-TIME OFFER: 2,500 Coins + 25 Gems + a free Mega Egg Roll!",
		Grant = { Gold = 2500, Gems = 25, EggRoll = "MegaEgg" },
		OneTime = true,
		Order = 1,
	},
	Coins100 = {
		Id = 1111111,
		Name = "100 Coins",
		Description = "Instantly grants 100 Coins.",
		Grant = { Gold = 100 },
		Order = 2,
	},
	Coins500 = {
		Id = 1111112,
		Name = "500 Coins",
		Description = "Instantly grants 500 Coins.",
		Grant = { Gold = 500 },
		Order = 3,
	},
	Coins5000 = {
		Id = 1111114,
		Name = "5,000 Coins",
		Description = "Instantly grants 5,000 Coins. Best value for zone unlocks!",
		Grant = { Gold = 5000 },
		Order = 4,
	},
	Coins50000 = {
		Id = 1111115,
		Name = "50,000 Coins",
		Description = "Instantly grants 50,000 Coins. Skip straight to Magma Core!",
		Grant = { Gold = 50000 },
		Order = 5,
	},
	Gems100 = {
		Id = 1111116,
		Name = "100 Gems",
		Description = "Instantly grants 100 Gems for Royal Egg hatches.",
		Grant = { Gems = 100 },
		Order = 6,
	},
	Gems1000 = {
		Id = 1111117,
		Name = "1,000 Gems",
		Description = "Instantly grants 1,000 Gems. The whale-sized gem vault!",
		Grant = { Gems = 1000 },
		Order = 7,
	},
	MegaEggRoll = {
		Id = 1111113,
		Name = "Mega Egg Roll",
		Description = "One premium roll on the Mega Egg — Rare or better guaranteed pool!",
		-- Grants one hatch from the premium "MegaEgg" table (see Eggs below).
		Grant = { EggRoll = "MegaEgg" },
		Order = 8,
	},
}

-- Roblox Premium members earn bonus coins (advertised on the shop page).
GameConfig.PremiumCoinBonus = 1.25

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
	-- The Gem sink: always available, boosted odds. Gems come from bosses,
	-- daily streaks and the Gems developer products.
	RoyalEgg = {
		Cost = 50, Currency = "Gems", Zone = 1,
		Pool = { "MossFox", "GlimmerBat", "ShardWolf", "SkyKoi", "PrismGolem", "NovaDrake", "VoidSeraph", "ChronoLion" },
		WeightOverride = {
			Common = 0, Uncommon = 40, Rare = 42, Epic = 15, Mythic = 3,
		},
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

--------------------------------------------------------------------------------
-- ZONE AMBIENCE (runtime version of docs/MapSpecifications.md)
-- Applied by ZoneLightingController when the player crosses into a zone's
-- ZoneRegion part. MusicIds are placeholders — swap in licensed tracks.
--------------------------------------------------------------------------------
GameConfig.ZoneAmbience = {
	[1] = {
		Ambient = Color3.fromRGB(70, 90, 75),
		OutdoorAmbient = Color3.fromRGB(110, 130, 110),
		FogColor = Color3.fromRGB(200, 220, 200),
		FogStart = 40, FogEnd = 450,
		Brightness = 2.2,
		ColorShift_Top = Color3.fromRGB(120, 160, 120),
		ClockTime = 14.5,
		MusicId = "rbxassetid://1848354536", -- REPLACE: calm forest track
	},
	[2] = {
		Ambient = Color3.fromRGB(120, 45, 30),
		OutdoorAmbient = Color3.fromRGB(90, 30, 20),
		FogColor = Color3.fromRGB(80, 20, 20),
		FogStart = 25, FogEnd = 300,
		Brightness = 1.4,
		ColorShift_Top = Color3.fromRGB(255, 90, 40),
		ClockTime = 0,
		MusicId = "rbxassetid://1837879082", -- REPLACE: percussive volcanic track
	},
	[3] = {
		Ambient = Color3.fromRGB(150, 150, 190),
		OutdoorAmbient = Color3.fromRGB(180, 180, 220),
		FogColor = Color3.fromRGB(230, 230, 250),
		FogStart = 60, FogEnd = 700,
		Brightness = 2.8,
		ColorShift_Top = Color3.fromRGB(200, 190, 255),
		ClockTime = 10.2,
		MusicId = "rbxassetid://1848183670", -- REPLACE: airy crystalline track
	},
	[4] = {
		Ambient = Color3.fromRGB(20, 12, 40),
		OutdoorAmbient = Color3.fromRGB(15, 10, 30),
		FogColor = Color3.fromRGB(10, 5, 20),
		FogStart = 20, FogEnd = 260,
		Brightness = 0.9,
		ColorShift_Top = Color3.fromRGB(90, 40, 255),
		ClockTime = 0,
		MusicId = "rbxassetid://1837324424", -- REPLACE: synthwave endgame track
	},
}

--------------------------------------------------------------------------------
-- DAILY REWARDS (7-day streak, resets after 48h of absence)
-- Gold amounts scale x(1 + Rebirths) so the streak stays relevant forever.
--------------------------------------------------------------------------------
GameConfig.DailyRewards = {
	[1] = { Gold = 500 },
	[2] = { Gold = 1200 },
	[3] = { Gems = 5 },
	[4] = { Gold = 4000 },
	[5] = { Gems = 15 },
	[6] = { Gold = 15000 },
	[7] = { Gems = 25, EggRoll = "RoyalEgg" }, -- streak capstone: free Royal hatch
}
GameConfig.DailyRewardCooldown = 20 * 60 * 60      -- claimable every 20h
GameConfig.DailyRewardStreakBreak = 48 * 60 * 60   -- streak resets after 48h

--------------------------------------------------------------------------------
-- LEADERBOARDS
--------------------------------------------------------------------------------
GameConfig.Leaderboards = {
	RefreshSeconds = 120,
	TopN = 10,
	Boards = {
		{ Key = "TotalGold", Store = "Leaderboard_TotalGold_V1", Title = "Richest Players", Stat = "TotalGoldEarned" },
		{ Key = "Rebirths",  Store = "Leaderboard_Rebirths_V1",  Title = "Most Rebirths",   Stat = "Rebirths" },
	},
}

return GameConfig
