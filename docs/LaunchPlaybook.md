# Nightfall — Launch Playbook

The code is finished. This is the ordered checklist that takes the repo to a
published, earning game. Work top to bottom; don't skip the playtest phase.

---

## Phase 1 — Wire-up (~1 hour, do this first)

Everything on the Creator Dashboard (create.roblox.com), then paste IDs into
`src/ReplicatedStorage/Config/GameConfig.lua`:

- [ ] Create the game/place on Roblox (name, description, genre: Simulator)
- [ ] **Gamepasses** (4): 2x Coins, VIP Luck, Auto-Hatch, +2 Pet Slots
      → paste IDs into `GameConfig.Gamepasses`.
      Suggested launch prices: 199 / 249 / 349 / 299 R$
- [ ] **Developer Products** (9): Starter Pack, 100/500/5,000/50,000 Coins,
      100/1,000 Gems, Mega Egg Roll, 2x Offline Earnings
      → paste IDs into `GameConfig.DeveloperProducts`.
      Suggested prices: 99 / 25 / 99 / 399 / 1499 / 149 / 999 / 149 / 49 R$
- [ ] **Badges** (5) → paste IDs into `GameConfig.Badges` (0 = disabled, fine to defer)
- [ ] **Group**: create your Roblox group, paste ID into `GameConfig.Group.GroupId`
- [ ] **Music**: replace the 4 placeholder `MusicId`s in `GameConfig.ZoneAmbience`
      with licensed tracks from the Creator Marketplace audio library
- [ ] `rojo build -o Nightfall.rbxlx`, open in Studio
- [ ] Game Settings → Security → **Enable Studio Access to API Services**
      (DataStores will silently fail without this)
- [ ] Game Settings → Avatar → R15 (WeaponVisualizer grips expect RightHand,
      with an R6 fallback already coded)

## Phase 2 — Build Zone 1 only (the launch map)

Launch with ONE excellent biome. Zones 2–4 can ship in weekly updates (that's
your update calendar, not a launch blocker). Follow `docs/MapSpecifications.md`:

- [ ] `Workspace/Zones/Zone1` with `Nodes`, `Enemies`, `Boss`, `Scenery` folders
- [ ] Place 8–12 node models (mix of OakNode / MossyRock / ElderTrunk),
      each: `NodeType` attribute set, PrimaryPart assigned
- [ ] Place 3–5 enemies (`EnemyType`) and 1 boss arena (`BossName` = VerdantColossus)
- [ ] Invisible anchored `ZoneRegion` part spanning the zone (Transparency 1,
      CanCollide false) — drives lighting + music
- [ ] `ZoneSpawn` part — the World Map teleport target
- [ ] Set Lighting to the Zone 1 sheet as the place default
- [ ] Optional art: meshes into `ReplicatedStorage/PetMeshes`, `WeaponMeshes`,
      `LootMeshes` (everything falls back to glowing primitives until then)
- [ ] Stub `Zone2`–`Zone4` folders with just a ZoneRegion + ZoneSpawn + a
      "COMING SOON" sign so the World Map buttons don't teleport into void

## Phase 3 — Playtest checklist (needs 2 accounts for trading)

Run in Studio (F5), watch the Output window for red errors. Test every row:

**Core loop**
- [ ] Click a node → damage number pops, health bar drains, node breaks,
      loot flies to you, Gold increases
- [ ] Hold-click auto-swings; swinging faster than 0.35s does nothing (server cooldown)
- [ ] Kill the boss → loot rolls land, respawns after 90s
- [ ] Buy + equip a weapon → blade appears in hand, damage goes up

**Pets**
- [ ] Hatch a Forest Egg → cutscene plays → pet in inventory → equip → follower
      appears and damage rises
- [ ] Hatch until you have 5 of one pet → FUSE → Golden appears, 5 consumed, gems charged
- [ ] Delete a pet (two-click confirm)

**Economy & persistence**
- [ ] Claim daily reward, complete a quest, claim a playtime chest (5 min)
- [ ] Leave and rejoin → everything persisted; offline popup appears after ≥5 min away
- [ ] Rebirth → gold wiped, multipliers up, zones reset

**Monetization (Studio test purchases are free)**
- [ ] Buy each product → grant lands, receipt marked (buy twice fast → no double-grant)
- [ ] Buy each gamepass → effect applies immediately and after rejoin

**Trading (2 accounts, Studio "Start Server + 2 Players")**
- [ ] Request → accept → offer pets both sides → confirm both → 3s countdown → swap
- [ ] Change an offer after confirming → both confirmations reset
- [ ] Disconnect mid-countdown → trade cancels, no pets lost

**Mobile**
- [ ] Studio device emulator (phone) → tap-to-swing works, all windows fit on screen

## Phase 4 — Publish settings

- [ ] Icon (512×512) + 2–3 thumbnails: ONE big expressive pet + weapon + "NEW"
      energy. This is >50% of your click-through; spend real effort or commission it (~10–30 USD on creator marketplaces)
- [ ] Public server size 12–20 (trading and pet-envy need people)
- [ ] Description: first line = hook, then feature emoji list, then group link
      ("Join the group for +10% coins & daily gems!")
- [ ] Enable Studio → File → Publish; turn on public access

## Phase 5 — Launch week & live-ops

- [ ] Soft-launch quietly, watch first 50 sessions: where do people quit?
      Fix that before spending on visibility
- [ ] Ads: start ~20–50 USD-equivalent Robux on sponsored impressions; kill
      creatives with <3% CTR, scale the winner
- [ ] Week 2: ship Zone 2 (Magma Core) as "UPDATE 1 🔥" — update posts re-trigger discovery
- [ ] Week 3: first `GameConfig.Events` weekend (2x Luck), announce in group
- [ ] Week 4: Zone 3 + new egg
- [ ] Watch: D1 retention (>25% is healthy), average session (>15 min),
      % buyers (>1.5%), and which products sell (tune prices, don't add SKUs)

## Economy tuning knobs (post-launch, all in GameConfig)

| Symptom | Knob |
|---|---|
| Players hit zone 2 wall and quit | Lower `Zones[2].UnlockCost` or raise Zone 1 node rewards |
| Nobody fuses | Increase gem drops in quests/boss tables, or cut `Fusion.*.GemCost` |
| Gems too plentiful, gem packs don't sell | Reverse the above |
| Sessions too short | Add a 15-min playtime chest, richer quest golds |
| Whales max out fast | Raise `Rebirth.CostGrowth`, add Rainbow-tier content |
