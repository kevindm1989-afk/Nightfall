# Rift Tamer — 4-Biome Modular Map Specifications

World-building design sheet for the Loot & Explore RPG. Every value here is
production-final and matches `src/ReplicatedStorage/Config/GameConfig.lua`
exactly — the engine reads the config; this document tells the builders and
lighting artists how to assemble each zone.

## Workspace Layout Contract (read first)

CoreEngine discovers all interactive content by this exact hierarchy:

```
Workspace
└── Zones
    ├── Zone1
    │   ├── Nodes      (Models, attribute NodeType  = "OakNode" | "MossyRock" | "ElderTrunk")
    │   ├── Enemies    (Models, attribute EnemyType = "ThornSprite" | "BarkGolem")
    │   ├── Boss       (Model,  attribute BossName  = "VerdantColossus")
    │   ├── ZoneRegion (invisible anchored Part spanning the whole zone —
    │   │               drives runtime lighting + music via ZoneLightingController)
    │   ├── ZoneSpawn  (anchored Part — teleport target for the World Map UI)
    │   └── Scenery    (decorative meshes, ignored by the engine)
    ├── Zone2 … Zone4 (same structure)
```

Every Node/Enemy/Boss model **must have a PrimaryPart** (the engine measures
hit distance to it and anchors health bars on it). The engine stamps
`MaxHealth` / `CurrentHealth` attributes at runtime — do not set them by hand.

Zone lighting and music are applied at runtime by
`ZoneLightingController.client.lua`, which point-tests the player against each
zone's `ZoneRegion` part and tweens `Lighting` to the sheets below (mirrored in
`GameConfig.ZoneAmbience`) over 1.5 seconds, crossfading the zone music track.
Set `ZoneRegion.Transparency = 1`, `CanCollide = false`, `Anchored = true`.

Optional art hookups (both fall back to glowing primitives until filled):
- `ReplicatedStorage/LootMeshes/<lootId>` — 3D loot pickups for LootAnimator
- `ReplicatedStorage/PetMeshes/<MDL_Pet_*>` — follower models for PetFollower

---

## Zone 1 — Mystic Forest

**Theme:** Ancient bioluminescent woodland; god-rays through canopy, floating
spores, moss-swallowed ruins.

### Lighting Configuration
| Property | Value |
|---|---|
| Ambient (RGB) | `70, 90, 75` |
| OutdoorAmbient (RGB) | `110, 130, 110` |
| FogColor (RGB) | `200, 220, 200` |
| FogStart / FogEnd | `40` / `450` |
| Brightness | `2.2` |
| ColorShift_Top (RGB) | `120, 160, 120` |
| ClockTime | `14.5` |
| EnvironmentDiffuseScale | `0.6` |
| Atmosphere Density / Haze | `0.35` / `1.8` |
| Post FX | Bloom (Intensity 0.6, Size 32), SunRays (Intensity 0.12) |

### Modular Mesh Asset Manifest (15)
1. `MDL_MF_OakTrunk_Large`
2. `MDL_MF_OakTrunk_Twisted`
3. `MDL_MF_CanopyCluster_A`
4. `MDL_MF_CanopyCluster_B`
5. `MDL_MF_GlowMushroom_Cluster`
6. `MDL_MF_MossBoulder_Small`
7. `MDL_MF_MossBoulder_Large`
8. `MDL_MF_RuinArch_Overgrown`
9. `MDL_MF_RuinPillar_Broken`
10. `MDL_MF_FernPatch_Dense`
11. `MDL_MF_HangingVines_Curtain`
12. `MDL_MF_WoodBridge_Rope`
13. `MDL_MF_StonePath_Segment`
14. `MDL_MF_FireflyEmitter_Bush`
15. `MDL_MF_ElderTree_Landmark`

### Boss — Verdant Colossus
- **Base HP:** `2,500`
- **HP scaling:** `HP = 2,500 × (1 + 0.35 × playerRebirths)` (formula constants:
  `BossBaseHP 2500`, `BossHPGrowth 6.0`, `BossRebirthHPScalar 0.35`)
- **Gold reward:** 900 × CoinMultiplier per participant · **Respawn:** 90s · **Loot rolls per kill:** 2

| Roll | Type | Payout | Weight | Effective % |
|---|---|---|---|---|
| Gold_Small | Gold | 350 | 40.0 | 40.0% |
| Gold_Large | Gold | 1,200 | 20.0 | 20.0% |
| Gems_Handful | Gems | 5 | 18.0 | 18.0% |
| IronCleaver | Weapon | 1 | 10.0 | 10.0% |
| ForestEgg_Free | Free egg hatch | ForestEgg | 8.0 | 8.0% |
| MysticBlade | Weapon | 1 | 3.5 | 3.5% |
| ShardWolf | Pet (direct) | 1 | 0.5 | 0.5% |

---

## Zone 2 — Magma Core

**Theme:** Volcanic cavern network; lava falls, cooling basalt columns,
ember particles rising on heat shimmer.

### Lighting Configuration
| Property | Value |
|---|---|
| Ambient (RGB) | `120, 45, 30` |
| OutdoorAmbient (RGB) | `90, 30, 20` |
| FogColor (RGB) | `80, 20, 20` |
| FogStart / FogEnd | `25` / `300` |
| Brightness | `1.4` |
| ColorShift_Top (RGB) | `255, 90, 40` |
| ClockTime | `0` (cavern — no sun) |
| EnvironmentDiffuseScale | `0.25` |
| Atmosphere Density / Haze | `0.5` / `2.6` |
| Post FX | Bloom (Intensity 1.1, Size 40), ColorCorrection (Contrast +0.08, TintColor 255,225,210) |

### Modular Mesh Asset Manifest (15)
1. `MDL_MC_BasaltColumn_Hex`
2. `MDL_MC_BasaltColumn_Cluster`
3. `MDL_MC_LavaFall_Sheet`
4. `MDL_MC_LavaPool_Round`
5. `MDL_MC_ObsidianShard_Spike`
6. `MDL_MC_CharredRock_Small`
7. `MDL_MC_CharredRock_Large`
8. `MDL_MC_EmberVent_Floor`
9. `MDL_MC_MagmaCrack_Decal`
10. `MDL_MC_ForgeRuin_Anvil`
11. `MDL_MC_ChainBridge_Iron`
12. `MDL_MC_StalactiteBurnt_Set`
13. `MDL_MC_CoolingCrust_Platform`
14. `MDL_MC_FireCrystal_Formation`
15. `MDL_MC_TitanRibcage_Landmark`

### Boss — Infernal Titan
- **Base HP:** `15,000` (= 2,500 × 6.0¹)
- **HP scaling:** `HP = 15,000 × (1 + 0.35 × playerRebirths)`
- **Gold reward:** 6,500 × CoinMultiplier · **Respawn:** 120s · **Loot rolls per kill:** 2

| Roll | Type | Payout | Weight | Effective % |
|---|---|---|---|---|
| Gold_Small | Gold | 2,500 | 38.0 | 38.0% |
| Gold_Large | Gold | 9,000 | 20.0 | 20.0% |
| Gems_Handful | Gems | 15 | 18.0 | 18.0% |
| MagmaEdge | Weapon | 1 | 11.0 | 11.0% |
| MagmaEgg_Free | Free egg hatch | MagmaEgg | 8.0 | 8.0% |
| ObsidianFang | Weapon | 1 | 4.0 | 4.0% |
| LavaHound | Pet (direct) | 1 | 0.8 | 0.8% |
| NovaDrake | Pet (direct) | 1 | 0.2 | 0.2% |

---

## Zone 3 — Crystal Skyway

**Theme:** Floating crystalline islands linked by light-bridges; prismatic
refraction everywhere, soft pastel skybox, low gravity feel.

### Lighting Configuration
| Property | Value |
|---|---|
| Ambient (RGB) | `150, 150, 190` |
| OutdoorAmbient (RGB) | `180, 180, 220` |
| FogColor (RGB) | `230, 230, 250` |
| FogStart / FogEnd | `60` / `700` |
| Brightness | `2.8` |
| ColorShift_Top (RGB) | `200, 190, 255` |
| ClockTime | `10.2` |
| EnvironmentDiffuseScale | `0.8` |
| Atmosphere Density / Haze | `0.28` / `1.2` |
| Post FX | Bloom (Intensity 0.9, Size 56), DepthOfField (FarIntensity 0.15), SunRays (Intensity 0.2) |

### Modular Mesh Asset Manifest (15)
1. `MDL_CS_FloatingIsland_Small`
2. `MDL_CS_FloatingIsland_Large`
3. `MDL_CS_QuartzSpire_Tall`
4. `MDL_CS_QuartzSpire_Cluster`
5. `MDL_CS_PrismShard_Floating`
6. `MDL_CS_LightBridge_Segment`
7. `MDL_CS_CrystalArch_Gate`
8. `MDL_CS_GeodeOpen_Half`
9. `MDL_CS_CloudBank_Volumetric`
10. `MDL_CS_RunestonePlatform_Round`
11. `MDL_CS_AuroraRibbon_Emitter`
12. `MDL_CS_ShatteredStair_Spiral`
13. `MDL_CS_GlassFlora_Patch`
14. `MDL_CS_SkyShrine_Ruin`
15. `MDL_CS_Prismarch_Throne_Landmark`

### Boss — Prismarch Seraph
- **Base HP:** `90,000` (= 2,500 × 6.0²)
- **HP scaling:** `HP = 90,000 × (1 + 0.35 × playerRebirths)`
- **Gold reward:** 52,000 × CoinMultiplier · **Respawn:** 150s · **Loot rolls per kill:** 3

| Roll | Type | Payout | Weight | Effective % |
|---|---|---|---|---|
| Gold_Small | Gold | 20,000 | 36.0 | 36.0% |
| Gold_Large | Gold | 70,000 | 20.0 | 20.0% |
| Gems_Handful | Gems | 40 | 18.0 | 18.0% |
| CrystalPike | Weapon | 1 | 11.0 | 11.0% |
| CrystalEgg_Free | Free egg hatch | CrystalEgg | 9.0 | 9.0% |
| PrismSaber | Weapon | 1 | 4.5 | 4.5% |
| PrismGolem | Pet (direct) | 1 | 1.2 | 1.2% |
| ChronoLion | Pet (direct) | 1 | 0.3 | 0.3% |

---

## Zone 4 — Cyber-Abyss

**Theme:** Endgame digital void; neon circuitry canyons, glitching geometry,
data-rain particles, hard black fog closing in.

### Lighting Configuration
| Property | Value |
|---|---|
| Ambient (RGB) | `20, 12, 40` |
| OutdoorAmbient (RGB) | `15, 10, 30` |
| FogColor (RGB) | `10, 5, 20` |
| FogStart / FogEnd | `20` / `260` |
| Brightness | `0.9` |
| ColorShift_Top (RGB) | `90, 40, 255` |
| ClockTime | `0` |
| EnvironmentDiffuseScale | `0.1` |
| Atmosphere Density / Haze | `0.6` / `3.0` |
| Post FX | Bloom (Intensity 1.6, Size 48), ColorCorrection (Saturation +0.15, Contrast +0.12), Blur pulse on boss spawn (Size 4, 0.4s) |

### Modular Mesh Asset Manifest (15)
1. `MDL_CA_CircuitFloor_Tile`
2. `MDL_CA_CircuitWall_Panel`
3. `MDL_CA_NeonPylon_Vertical`
4. `MDL_CA_NeonPylon_Broken`
5. `MDL_CA_DataStream_Column`
6. `MDL_CA_HoloBillboard_Glitch`
7. `MDL_CA_ServerMonolith_Black`
8. `MDL_CA_CablesBundle_Hanging`
9. `MDL_CA_GlitchCube_Floating`
10. `MDL_CA_FirewallGate_Hex`
11. `MDL_CA_GridBridge_Light`
12. `MDL_CA_CorruptedTerrain_Spikes`
13. `MDL_CA_VoidRift_Portal`
14. `MDL_CA_DroneWreck_Pile`
15. `MDL_CA_OmegaCore_Landmark`

### Boss — Omega Null
- **Base HP:** `540,000` (= 2,500 × 6.0³)
- **HP scaling:** `HP = 540,000 × (1 + 0.35 × playerRebirths)`
- **Gold reward:** 400,000 × CoinMultiplier · **Respawn:** 180s · **Loot rolls per kill:** 3

| Roll | Type | Payout | Weight | Effective % |
|---|---|---|---|---|
| Gold_Small | Gold | 160,000 | 34.0 | 34.0% |
| Gold_Large | Gold | 550,000 | 20.0 | 20.0% |
| Gems_Handful | Gems | 100 | 18.0 | 18.0% |
| NeonKatana | Weapon | 1 | 12.0 | 12.0% |
| CyberEgg_Free | Free egg hatch | CyberEgg | 9.0 | 9.0% |
| VoidReaver | Weapon | 1 | 5.0 | 5.0% |
| VoidSeraph | Pet (direct) | 1 | 1.5 | 1.5% |
| ChronoLion | Pet (direct) | 1 | 0.5 | 0.5% |

---

## Cross-Zone Progression Metrics

| Zone | Unlock Cost (Gold) | Node HP range | Boss HP (0 rebirths) | Boss HP growth vs previous |
|---|---|---|---|---|
| 1 Mystic Forest | free | 40 – 250 | 2,500 | — |
| 2 Magma Core | 25,000 | 600 – 3,600 | 15,000 | ×6.0 |
| 3 Crystal Skyway | 900,000 | 9,000 – 56,000 | 90,000 | ×6.0 |
| 4 Cyber-Abyss | 30,000,000 | 140,000 – 900,000 | 540,000 | ×6.0 |

Boss HP additionally scales `× (1 + 0.35 × Rebirths)` so rebirthed players
never trivialize endgame content while their `+0.5 CoinMultiplier` and
`+0.1 LuckMultiplier` per rebirth keep net progression positive.

## Monetization Placement Notes (Executive Strategy)

- **First purchase funnel:** The Mega Egg Roll product card is pinned first in
  the Robux tab; its pool starts at Rare tier, so the first roll always beats
  anything a Zone-1 player owns.
- **2x Coins** pays back fastest in Zone 2+ where unlock walls (25K → 900K →
  30M) create natural "double my income" moments — surface the pass prompt on
  every failed zone-unlock attempt.
- **VIP Luck** (ID 1234567) is advertised on the egg UI itself: showing the
  boosted 1.5× Rare/Epic/Mythic odds next to base odds converts hatch-streak
  frustration directly.
- **Auto-Hatch** targets the retention cohort: it only has value to players
  already hatching in volume, making it a clean late-funnel sink.
