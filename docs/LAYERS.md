# Physics layers

2D physics layers (named in `project.godot`). A body's *layer* is what it is;
its *mask* is what it collides with or detects.

| # | Name | Used by |
|---|---|---|
| 1 | world | Solid and one-way tiles in `warehouse_tileset.tres`, static level geometry |
| 2 | player | The cat |
| 3 | enemies | Robots |
| 4 | hazards | Spikes, lasers, toxic goo (Area2D triggers) |
| 5 | breakables | Crates and other things the shockwave destroys |
| 6 | pickups_pads | Pickups, enhancement pads, checkpoints |

Suggested masks: player = 1, 3, 4, 5 (plus Areas on 6); enemies = 1; breakables
sit on layer 5 and the player also collides with them. Pickups and pads are
Area2Ds on layer 6 with mask 2.

## TileSet (`assets/tiles/warehouse_tileset.tres`)

- Physics layer 0: collision layer 1 (world), mask 0.
- Occlusion layer 0: light mask 1. Solid tiles carry a `LightOccluder2D`
  polygon (via the TileSet occlusion layer) so 2D lights cast shadows without
  extra setup. One-way tiles deliberately do not occlude.
- Solid tiles: full 18x18 collider. Slope tiles: triangular collider and occluder.
- One-way tiles (platforms, catwalks): a 6 px strip along the top edge with
  one-way collision, margin 1.
- Everything else (pipes, signs, hooks, scenery) has no collider.
- Regenerate with `godot --headless --path . --script res://tools/build_tileset.gd`.
