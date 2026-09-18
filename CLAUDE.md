# StarPets — notes for whoever picks this up

A Roblox pet simulator (Rojo). This file exists so a new session does not
re-derive the architecture, and does not undo things that were fixed the hard
way. Read it before changing anything; it is short on purpose.

## Run this first

```bash
bash tools/scan_all.sh        # 11 checks, ~2 minutes, no Studio needed
```

They boot the real server and the real client against a Roblox mock (`lupa`),
build the map, play the core loop, and simulate DataStore outages. Every check
exists because of a bug that actually shipped, and every one was verified by
reintroducing that bug. If one fails, something is genuinely broken.

`pip install lupa pillow` if they will not start.

## Layout

```
src/Server/GameServer.server.lua   the one Script. Builds the map, owns the remotes.
src/Server/*.lua                   ModuleScripts, required by GameServer
src/Client/GameClient.client.lua   the one LocalScript
src/Client/UI/*.lua                panels, required by UIController
src/Shared/GameConfig.lua          all tunable data: pets, eggs, worlds, prices
default.project.json               the manifest. A file missing from here does NOT ship.
tools/                             the checks and the renderers
```

## Traps this project has actually fallen into

**A Roblox cylinder runs along its LOCAL X.** `column()` stands one up with
`Orientation (0,0,90)`. Anything wanting a lean must ADD to that 90 — passing a
bare angle REPLACES it and lays the part flat. This has produced flat tree
trunks once and a horizontal log through every cactus once.

**A ModuleScript does not run until something requires it.** `BadgePopup` sat
shipped-but-never-executed for the life of the project because its filename made
it a ModuleScript and nothing required it. A file that connects to an event and
returns nothing must be named `*.client.lua`.

**Studio discards everything changed during Play.** The map used to be generated
only at runtime, so it could only be edited during Play, so edits always
vanished. See `MapPersist.lua`: bake the map into the place once and the server
keeps it. Clickable parts carry an `SPAction` attribute instead of a closure,
which is what lets a saved map still work when the builder never runs.

**Anything created before a client `WaitForChild` must exist.** The client waits
on `workspace` folders by name; moving one into `StarPetsMap` without updating
the client left every world barrier frozen. `check_map` cross-references these
now.

## Rules that are load-bearing — do not quietly undo them

- **Never save a session whose load failed.** `DataManager.LoadPlayer` returns
  `(data, err)`; a failed read caches nothing and `saveWithRetry` refuses it.
  Removing this reintroduces a bug that wiped 10,000,000 coins permanently.
- **`PetService.GrantPet` is the only way a pet enters an inventory.** It
  enforces the 100-pet cap and stamps the permanent `Discovered` record the Pet
  Index reads. Direct `table.insert(data.Pets, ...)` bypasses both; `check_pets`
  sweeps for it.
- **`TradeService.CARRIED`** lists the fields a traded pet keeps. Rebuilding a
  pet without `mutation` and `fuseMult` destroys ~98% of its value silently.
- **Remotes are created through `makeEvent` / `makeFunction`**, which wrap them
  in a rate-limit guard. A remote made with `Instance.new` directly is
  unguarded.

## What the owner has asked for

- **No neon.** It was stripped back to 13 parts across the whole map — lava, a
  volcano crater, and the station's window band. Do not decorate with it.
- **No shop building and no leaderboard board in the world.** Both were removed;
  the HUD dock already has Shop, Upgrade and Ranks buttons.
- **Nothing planted on the walking paths.** The four paths run along the axes
  from spawn; props are excluded from those corridors.
- **No free-gift system.** The game is meant to be a little harder.
- Do not add plant/farming mechanics — that is a different project.

## Seeing the map without Studio

```bash
python3 tools/render_iso.py out.png Meadow   # 3D, one world
python3 tools/render_map.py out.png          # top-down, whole map
```

A top-down diagram answers "is it there". The isometric one answers "does it
look right", which is the question that actually gets asked.

## Shipping to Studio

`python3 tools/build_installer.py` writes `build/StarPets_Install.rbxmx`:
insert into Workspace, then run `require(workspace.StarPetsInstall.Install)()`
in the Command Bar. It deletes the old folders first — skipping that leaves two
GameServer scripts running, which looks exactly like the update did nothing.

With Studio's MCP server connected, none of that is needed: edit the place
directly. The checks above still apply and still catch what Studio cannot show
you — a save wiped by a DataStore outage, a trade that quietly destroys a pet.
