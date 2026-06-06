# StarPets — Setup Guide

## What Was Built

A complete Roblox pet simulator with:
- 19 pets across 6 rarities (Common → Mythic)
- 4 eggs (Starter, Cool, Rare, Legendary)
- 5 biomes (Meadow → Space) with coin orbs
- Pet following + bobbing animations
- Passive pet income (pets earn coins per second)
- Rebirth system (6 tiers, up to 25x multiplier)
- 5 gamepasses (2x Coins, Auto Collect, VIP, +3 Pet Slots, Lucky Boost)
- DataStore save/load with retry logic
- Full UI: HUD, Pets panel, Hatch panel, Shop panel, Rebirth panel
- Hatch animations with rarity reveals
- Toast notifications

---

## Option A — Rojo (Recommended, fastest)

1. Install Rojo: https://rojo.space
2. Install the Rojo Roblox Studio plugin from the Roblox Plugin Marketplace
3. In terminal:
   ```bash
   cd /Users/masterqutaibah/StarPets
   rojo serve
   ```
4. In Roblox Studio → Rojo plugin → Connect
5. All scripts sync automatically

---

## Option B — Manual Import

Create each script in Studio exactly as shown:

### ReplicatedStorage
```
ReplicatedStorage/
  Shared/               ← Folder
    GameConfig          ← ModuleScript  ← paste src/Shared/GameConfig.lua
```

### ServerScriptService
```
ServerScriptService/
  Server/               ← Folder
    GameServer          ← Script        ← paste src/Server/GameServer.lua
    DataManager         ← ModuleScript
    PetService          ← ModuleScript
    EggService          ← ModuleScript
    CurrencyService     ← ModuleScript
    RebirthService      ← ModuleScript
    GamepassService     ← ModuleScript
```

### StarterPlayerScripts
```
StarterPlayerScripts/
  Client/               ← Folder
    GameClient          ← LocalScript   ← paste src/Client/GameClient.lua
    UI/                 ← Folder
      UIController      ← ModuleScript
      PetsPanel         ← ModuleScript
      HatchPanel        ← ModuleScript  ← paste src/Client/UI/HatchUI.lua
      ShopPanel         ← ModuleScript
      RebirthPanel      ← ModuleScript
```

---

## Gamepass Setup (after publishing)

1. Publish your game to Roblox
2. Go to Creator Hub → your game → Passes
3. Create each pass (names: "2x Coins", "Auto Collect", "VIP", "+3 Pet Slots", "Lucky Boost")
4. Copy each pass's numeric ID
5. In `src/Shared/GameConfig.lua`, find `GameConfig.Gamepasses` and fill in the `robloxId` values:
   ```lua
   { key = "GP_2xCoins", robloxId = 12345678, ... },
   ```

---

## Things to Customize (Quick Wins)

| What | Where |
|------|-------|
| Pet names/rarities/multipliers | `GameConfig.Pets` |
| Egg costs and rarity odds | `GameConfig.Eggs` |
| Area unlock prices | `GameConfig.Areas` |
| Rebirth requirements | `GameConfig.Rebirths` |
| Pet inventory size | `GameConfig.Settings.MaxPetsInInventory` |
| Pet follow speed | `GameConfig.Settings.PetFollowSpeed` |
| Coin orb respawn time | `GameConfig.Settings.CoinOrbRespawnTime` |

---

## Next Steps (Phase 2 Upgrades)

- Replace geometric pet shapes with real 3D models (import from catalog or make in Studio)
- Add a Trading system
- Add Daily Rewards / Login streak
- Add Leaderboards (using OrderedDataStore)
- Add Codes system (free pets / coins)
- Add Lucky Egg events (limited time eggs)
- Add a Title/Rank system based on total rebirths
- Polish maps with real terrain, trees, lighting

---

## Architecture Overview

```
Client                          Server
──────                          ──────
GameClient.lua (main loop)      GameServer.lua (main orchestrator)
  └─ UIController               DataManager  (DataStore save/load)
       ├─ PetsPanel             PetService   (spawn, follow, income)
       ├─ HatchUI               EggService   (roll + award pets)
       ├─ ShopPanel             CurrencyService (orbs, passive)
       └─ RebirthPanel          RebirthService  (reset + mult)
                                GamepassService (owns check)

Shared (ReplicatedStorage)
  └─ GameConfig  (all game data — single source of truth)

Communication: RemoteEvents in ReplicatedStorage/Remotes/
  Server → Client: DataUpdated, HatchResult, Notification
  Client → Server: HatchEgg, EquipPet, UnequipPet, BuyArea, Rebirth, DeletePet, BuyGamepass
```
