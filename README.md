# Rift Tamer: Pet & Loot Simulator (Roblox)

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
│   │                                        boss loot, zones, rebirth, Premium
│   │                                        coin bonus, hit-VFX events
│   ├── PetSystem.lua            (Module)    5-tier weighted hatching + VIP Luck
│   │                                        gamepass (ID 1234567) rare odds ×1.5
│   ├── MonetizationManager.server.lua       ProcessReceipt for all 8 products
│   │                                        (coins, gems, Starter Pack, Mega
│   │                                        Egg Roll) + gamepass grants
│   ├── DailyRewardManager.server.lua        7-day streak rewards (20h cadence,
│   │                                        48h streak break, rebirth-scaled)
│   ├── LeaderboardManager.server.lua        Global OrderedDataStore top-10
│   │                                        (Richest / Most Rebirths)
│   ├── GameSignals.lua          (Module)    Server event bus (NodeBroken,
│   │                                        BossKilled, GoldEarned, ...)
│   ├── QuestManager.server.lua              Daily quests (deterministic per-day
│   │                                        roll), playtime chests, group gems
│   ├── TradeManager.server.lua              Secure pet trading: session locks,
│   │                                        confirm resets, 3s countdown,
│   │                                        atomic swap + force-save both sides
│   ├── OfflineEarningsManager.server.lua    Welcome-back gold (8h cap) + banks
│   │                                        the amount for the 2x Robux upsell
│   └── BadgeManager.server.lua              Milestone badges via GameSignals
│                                            (rebirth, mythic, zone 4, fusion)
├── StarterPlayerScripts/
│   ├── LootAnimator.client.lua              3D loot burst → Bezier vacuum into
│   │                                        the HumanoidRootPart
│   ├── CombatController.client.lua          Click/hold-to-swing input + world
│   │                                        health bars
│   ├── PetFollower.client.lua               Equipped pets orbit/bob behind every
│   │                                        player (attribute-driven, local-only)
│   ├── VFXController.client.lua             Damage numbers, hit sparks, kill
│   │                                        bursts, camera pulse
│   ├── WeaponVisualizer.client.lua          Held weapon in-hand for all players
│   │                                        + slash tween on landed hits
│   └── ZoneLightingController.client.lua    Per-biome lighting tweens + zone
│                                            music crossfade (ZoneRegion parts)
└── StarterGui/MainHUD/
    ├── ShopController.client.lua            Self-building shop UI, instant
    │                                        MarketplaceService prompts, upsells
    ├── HatchAnimator.client.lua             Full-screen egg wobble/crack/reveal
    │                                        cutscene (queued, click-to-skip)
    ├── PetInventoryController.client.lua    Pet list, equip/unequip, EQUIP BEST,
    │                                        two-click delete
    ├── DailyRewardController.client.lua     Streak calendar + glowing claim hook
    ├── LeaderboardController.client.lua     Global top-10 window
    ├── QuestController.client.lua           Daily quests + playtime chest track
    ├── FusionController.client.lua          Fusion lab: 5x pet + gems -> Golden
    │                                        / Rainbow variants (opens from Pets)
    ├── TradeController.client.lua           Player list, request banner, live
    │                                        trade window with offer grid
    ├── OfflineController.client.lua         Welcome-back popup + DOUBLE IT R$
    └── ZoneTravelController.client.lua      World map: unlock zones + teleport
docs/
└── MapSpecifications.md                     4-biome lighting sheets, 60 mesh
                                             manifest, boss scaling & loot tables
```

## Build & Deploy

1. Install [Rojo](https://rojo.space) 7+.
2. `rojo build -o RiftTamer.rbxlx` (or `rojo serve` + the Studio plugin).
3. In Studio, enable **Game Settings → Security → Enable Studio Access to API
   Services** so DataStores work in test sessions.
4. Create your Developer Products and Gamepasses on the Creator Dashboard,
   then paste the live IDs into `GameConfig.Gamepasses` / `GameConfig.DeveloperProducts`,
   and your Roblox group ID into `GameConfig.Group.GroupId`.
   (`VIPLuck` ships as `1234567` to match the PetSystem spec.)
5. Build the map following the Workspace contract in `docs/MapSpecifications.md`
   (`Workspace/Zones/Zone<N>/{Nodes,Enemies,Boss}` with `NodeType` /
   `EnemyType` / `BossName` attributes and a PrimaryPart on every model).
6. Optional: drop designer meshes into `ReplicatedStorage/LootMeshes`
   (loot ids like `Gold_Small`), `ReplicatedStorage/PetMeshes` (`MDL_Pet_*`)
   and `ReplicatedStorage/WeaponMeshes` (weapon keys like `MagmaEdge`) —
   every renderer falls back to glowing primitives until then.
7. Live-ops: run "2x Coins/Luck Weekend" events by editing `GameConfig.Events`
   and republishing — no code changes needed.
8. Create the five milestone badges on the Creator Dashboard and paste their
   IDs into `GameConfig.Badges` (IDs of 0 are skipped silently).

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
