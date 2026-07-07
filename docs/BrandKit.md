# Rift Tamer — Brand & Launch Kit

The single source of truth for the game's identity, store presence, key-art
direction, and pricing. An interactive version of this kit (with rendered icon
and thumbnail mockups) is published as an Artifact — regenerate it from
`scratchpad/rift-tamer-kit.html` if you need to reshare.

---

## 1. Identity

- **Name:** Rift Tamer: Pet & Loot Simulator
- **One-liner:** Hatch. Fuse. Cross the Rift.
- **Hook:** Most pet sims trap you in one world. Rift Tamer tears open four —
  a haunted forest, a molten core, a crystal skyway, and a neon abyss — and
  your pets cross every rift with you.
- **Why the name works:** "Rift" sells the multi-world premise in one word and
  gives you a permanent excuse to keep shipping new zones ("open the next
  Rift") without the name ever feeling dated. "Tamer" signals pet collection.
  "Simulator" keeps it in Roblox genre search.

## 2. Visual identity

**Palette** (deep-violet-black ground makes the neon biome colors pop):

| Token | Hex | Use |
|---|---|---|
| Void | `#0B0714` | Primary background, everywhere |
| Surface | `#160E2A` | Cards, panels |
| Mystic Forest | `#4FD98A` | Rift 1 / category color |
| Magma Core | `#FF5A38` | Rift 2 / category color |
| Crystal Skyway | `#8FB6FF` | Rift 3 / category color |
| Cyber-Abyss | `#C763FF` | Rift 4 / category color |
| Loot Gold | `#FFC23D` | **Brand accent** — loot, currency, rim-light, CTAs |
| Ink | `#EDE7FA` | Text |

The four biome colors form a spectrum (green → blue → gold → orange → violet)
used as a "rift tear" motif across the store presence. **Gold is the single
through-accent** — reserve it for loot, value, and the hero pet's rim light.

**Type:** heavy grotesque display (uppercase, tight tracking) for the wordmark;
system sans for body; monospace with tabular figures for prices and stats.

## 3. Key-art direction (icon + thumbnails)

On Roblox the icon and thumbnails drive >50% of click-through. Hand your
artist these five rules:

1. **One hero pet, huge** — a single expressive creature filling 55–65% of the
   icon, big eyes, gold rim-light. Players click faces, not scenes.
2. **The rift is the backdrop** — a vertical spectrum tear (green→gold→violet)
   behind the pet, readable at thumbnail size, ties every asset together.
3. **Gold = value** — gold accent only on loot sparkle and the pet's rim.
4. **Thumbnails sell the update**, not the game — "Rainbow Pets Are Here,"
   "New Rift," "2× Luck Weekend." Refresh every patch to re-trigger discovery.
5. **Deep violet-black ground** (`#0B0714`) on every asset so the store
   presence reads unmistakably as one game.

Icon spec: 512×512. Thumbnails: 1920×1080 (16:9), 2–3 at launch.

## 4. Store listing (paste-ready)

Drop into the Roblox experience description. First line is the hook; the group
CTA drives the +10% coins bonus and community joins.

```
🌌 TEAR OPEN THE RIFT in Rift Tamer — hatch pets, smash loot, and battle bosses across 4 wild worlds!

⚔️ Break nodes & defeat enemies to earn Gold
🥚 Hatch 13 pets — can YOU pull a 0.5% Mythic?
🌈 FUSE pets into Golden & Rainbow beasts (6.25× power!)
🔁 Rebirth for permanent Coin & Luck multipliers
🗺️ Unlock 4 Rifts: Mystic Forest → Magma Core → Crystal Skyway → Cyber-Abyss
🤝 TRADE pets with friends · 🏆 Top the global leaderboards

✨ NEW players get a FREE egg + daily rewards!
👑 Join the group for +10% Coins & daily Gems!

⭐ Like & Favorite to help us open the next Rift!
```

**Tags:** Simulator · Pets · PetSimulator · RPG · Hatching · Loot · Trading ·
Rebirth · Adventure

## 5. Pricing model

All prices land on known Robux psychological breakpoints. Full justification
lives in `docs/LaunchPlaybook.md`; the summary:

**Gamepasses (one-time, permanent)**

| Pass | Robux | Rationale |
|---|--:|---|
| 2× Coins | 199 | The gateway buy — cheap, casual, doubles gold forever |
| VIP Luck | 249 | Sold from the egg screen next to base odds |
| +2 Pet Slots | 299 | Visible, direct power spike for engaged players |
| Auto-Hatch | 349 | Retention-cohort pass; only valuable to volume hatchers |

**Developer products (repeatable)**

| Product | Robux | Rationale |
|---|--:|---|
| Starter Pack (one-time) | 99 | First-session anchor: coins + gems + Mega Egg Roll |
| 100 Coins | 25 | Micro-impulse |
| 500 Coins | 99 | Impulse tier |
| 5,000 Coins | 399 | Best-value coin pack, surfaced at zone walls |
| 50,000 Coins | 1499 | Skip-the-grind whale pack |
| 100 Gems | 149 | Feeds Royal Egg + fusion gem sink |
| 1,000 Gems | 999 | Gem vault for Rainbow-tier fusion |
| Mega Egg Roll | 149 | Rare-or-better guaranteed pool |
| 2× Offline Earnings | 49 | Contextual — prompted only on the welcome-back screen |

**Fair-play principle:** nothing is locked behind Robux. Every pet, zone,
weapon, and fusion is reachable free — purchases buy *speed and convenience*,
not exclusive power. This is what keeps the rating high enough to stay in the
Roblox discovery algorithm.

## 6. Post-launch content cadence

The live-ops hooks are already coded — new content is a config edit:
- **Weekend events** — edit `GameConfig.Events` (2× Coins / 2× Luck), republish.
- **New pets/eggs** — add entries to `GameConfig.Pets` / `GameConfig.Eggs`.
- **New rift** — Zones 2–4 ship as weekly "New Rift" updates; each update post
  re-triggers Roblox discovery.

Suggested week 1–4: Zone 2 → first 2× Luck weekend → Zone 3 + new egg → Zone 4.
