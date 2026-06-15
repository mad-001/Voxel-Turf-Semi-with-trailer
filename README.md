# Voxel Turf — Semi with Trailer

A driveable semi-truck for [Voxel Turf](https://store.steampowered.com/app/404530/Voxel_Turf/):
a low-poly tractor cab that tows a bending grain trailer.

![semi](https://img.shields.io/badge/Voxel%20Turf-mod-red)

## Features

- **Driveable tractor** — buy it in-game or `/give SemiTruck`. Heavy, slow-building
  acceleration tuned for a semi.
- **Model wheels that animate** — all six cab wheels spin with travel, the front
  pair steer (even at a crawl), each with a chromed rim, dished rear/trailer rims,
  and tiny grey lug nuts. The front wheels' *visual* steer is scaled down so they
  never clip the body — the actual handling is unchanged.
- **A trailer that trails and bends** — the grain trailer is drawn as part of the
  cab's render, hinged at the fifth wheel, so it swings out through turns. Its
  tandem wheels spin too. Because it's derived from the cab's own (already-synced)
  transform each frame, it can't desync in multiplayer and nothing extra has to be
  spawned.
- **Faithful colours** via a palette texture (red body, white rims/stairs/straps,
  grey grille, black tyres/windows, amber markers).
- **Air horn** sound effect.

## Install

Copy the `SemiTruckMod` folder into your Voxel Turf `mods/` directory:

```
…/steamapps/common/Voxel Turf/mods/SemiTruckMod/
```

Then start the game with mods enabled. The truck appears in the buy menu under the
**Semi Truck** category, or spawn one with `/give SemiTruck`.

> Geometry/texture changes only load at game **startup** — a full restart is needed
> after updating, not just a world reload.

## From a mission (server Lua)

```lua
local cab = spawnEntity(SEMI_CAB_ENTITY_ID, worldId, x, y, z, rotDeg, miid, owner)
```

The trailer is drawn with the cab automatically.

## Contents

- `scripts/semitruck.lua` — all the mod logic (entity types, wheel/trailer render).
- `models/` — cab, trailer, the six wheels, collision hulls.
- `textures/entities/tex0.tga` — the overridden palette texture.
- `db/meshes.txt` — base game mesh list + this mod's meshes (360–370).
- `sfx/` — the air-horn sound.

## Credits / License

The tractor cab geometry is derived from **"Low Poly Red Semi Truck" by Jura
(@JuraPicksHisNose)** on Sketchfab, licensed **CC-BY 4.0**
(https://creativecommons.org/licenses/by/4.0/) — converted to Voxel Turf format
(scaled, palette-coloured, wheels split out to animate).

The trailer, the Lua, and all other assets are original to this mod.
