# Physics layers

2D physics layers (named in `project.godot`). A body's *layer* is what it is;
its *mask* is what it collides with or detects.

| # | Name | Used by |
|---|---|---|
| 1 | world | Solid and one-way tiles in `wake_hd.tres`, static level geometry |
| 2 | player | The cat |
| 3 | enemies | Robots |
| 4 | hazards | Spikes, lasers, toxic goo (Area2D triggers) |
| 5 | breakables | Crates and other things the shockwave destroys |
| 6 | pickups_pads | Pickups, enhancement pads, checkpoints |

Suggested masks: player = 1, 3, 4, 5 (plus Areas on 6); enemies = 1; breakables
sit on layer 5 and the player also collides with them. Pickups and pads are
Area2Ds on layer 6 with mask 2.

## Groups

| Group | Meaning |
|---|---|
| `player` | The cat |
| `shock_receiver` | Implements `on_shockwave(origin, radius, source)`; `source` is `"shock"` (double jump) or `"pound"` (ground pound). Also exposes `shock_offset` and `shock_half` for range checks. |
| `breakable` | Crates and cracked floors |
| `pushable` | RigidBody2D crates; also counted by floor plates |
| `enemy` | Patrol bots |
| `checkpoint` | Checkpoint pads |
| `kit_enemy` | Actor-kit robots (also in `enemy`); see `docs/KIT.md` |
| `kit_turret` | Sentry turrets (a security camera's alarm calls `alert()` on them) |
| `explosive` | Barrels with `trigger(delay)`: the chain reaction |
| `blast_receiver` | Walls and crates with `on_blast(origin, radius)` |
| `projectile_target` | Things a `Projectile` may set off (`on_projectile_hit`) |
| `kit_projectile` | Live `Projectile`s |
| `alarm_shutter` | `KitShutter`s a camera can close |
| `collectible` | Kit collectibles |

## TileSet (`assets/tiles/wake_hd.tres`)

32 px tiles from `assets/art_hd/tiles_wake_hd.png`: seven 16x10 material blocks
(steel, bulkhead, rust, maroon, teal, violet, hazard) stacked vertically. A tile
keeps its (col, row) in every block, so the atlas position is
`(col, row + 10 * block)`.

- Physics layer 0: collision layer 1 (world), mask 0.
- Occlusion layer 0: light mask 1. Solid tiles carry a full-cell
  `OccluderPolygon2D`; `TileOccluderBaker` merges them and insets the edges that
  face open air (5 px at 32 px). Girder trusses carry a rail-only occluder (the
  open lattice lets light through); the baker keeps those as they are.
- Solid tiles: full 32x32 collider. Slope tiles (three opaque corners): a
  triangular collider and occluder.
- One-way tiles (girder deck at (13,4), grating at (10..12,7)): an 8 px strip
  along the top, one-way, margin 1. They cast no cell occluder.
- Everything else is art only (domes, studs, marks, truss posts).
- Regenerate with `godot --headless --path . --script res://tools/build_tileset_hd.gd`.

## Physics layers added for the HD room

| # | Name | Used by |
|---|---|---|
| 7 | bot_bounds | Invisible stoppers, solid only to the patrol bot and pushable crates (the cat passes through) |
