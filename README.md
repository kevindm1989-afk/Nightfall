# Nightfall — Loot & Explore RPG Simulator (Roblox)

A complete, production-ready Roblox simulator: break resource nodes, fight
enemies and zone bosses, hatch pets from weighted eggs, rebirth for permanent
multipliers, and monetize through Developer Products and Gamepasses.

## Project Layout (Rojo)

```
default.project.json                         Rojo mapping (rojo build / rojo serve)
src/
├── ReplicatedStorage/
│   ├── Config/GameConfig.lua                All balance data: weapons, pets, eggs,
│   │                                        zones, bosses, monetization IDs
│   └── Shared/Remotes.lua                   Remote manifest (server creates, client waits)
├── ServerScriptService/
│   ├── DataManager.lua          (Module)    Session-locked DataStore profiles,
│   │                                        300s auto-save, dupe protection
│   ├── CoreEngine.server.lua    (Script)    Node/combat loop, damage formula,
│   │                                        boss loot, zones, rebirth
│   ├── PetSystem.lua            (Module)    5-tier weighted hatching + VIP Luck
│   │                                        gamepass (ID 1234567) rare odds ×1.5
│   └── MonetizationManager.server.lua       ProcessReceipt (100/500 Coins, Mega
│                                            Egg Roll) + gamepass grants
├── StarterPlayerScripts/
│   ├── LootAnimator.client.lua              3D loot burst → Bezier vacuum into
│   │                                        the HumanoidRootPart
│   └── CombatController.client.lua          Click/hold-to-swing input + world
│                                            health bars
└── StarterGui/MainHUD/
    └── ShopController.client.lua            Self-building shop UI, instant
                                             MarketplaceService prompts
docs/
└── MapSpecifications.md                     4-biome lighting sheets, 60 mesh
                                             manifest, boss scaling & loot tables
```

## Build & Deploy

1. Install [Rojo](https://rojo.space) 7+.
2. `rojo build -o Nightfall.rbxlx` (or `rojo serve` + the Studio plugin).
3. In Studio, enable **Game Settings → Security → Enable Studio Access to API
   Services** so DataStores work in test sessions.
4. Create your Developer Products and Gamepasses on the Creator Dashboard,
   then paste the live IDs into `GameConfig.Gamepasses` / `GameConfig.DeveloperProducts`.
   (`VIPLuck` ships as `1234567` to match the PetSystem spec.)
5. Build the map following the Workspace contract in `docs/MapSpecifications.md`
   (`Workspace/Zones/Zone<N>/{Nodes,Enemies,Boss}` with `NodeType` /
   `EnemyType` / `BossName` attributes and a PrimaryPart on every model).
6. Optional: drop designer loot meshes into `ReplicatedStorage/LootMeshes`
   named by loot id (`Gold_Small`, `ForestEgg_Free`, …) — the LootAnimator
   falls back to glowing primitives until then.

## Player Data Contract

Every profile (DataStore `PlayerData_V1`, session-locked, auto-saved every
300 seconds, flushed on leave and `BindToClose`):

```lua
{
  Gold = 0, Gems = 0, Rebirths = 0,          -- currencies
  CurrentZone = 1, UnlockedZones = {[1]=true},
  CoinMultiplier = 1, LuckMultiplier = 1,
  EquippedWeapon = "WoodenSword",
  OwnedPets = { {UUID, PetName, StatBonus}, ... },
  EquippedPets = { uuid, ... },              -- max 4 contribute to damage
  OwnedGamepasses = {}, PurchaseLedger = {}, -- receipt idempotency
}
```

**Damage formula:** `Weapon.BaseDamage + Σ equipped pet StatBonus`, validated
server-side with a 0.35s swing cooldown and 22-stud distance check.

**Hatch odds:** Common 50% · Uncommon 30% · Rare 15% · Epic 4.5% · Mythic 0.5%;
VIP Luck multiplies the Rare/Epic/Mythic weights by 1.5 before normalization,
and `LuckMultiplier` (rebirths) stacks the same way.
