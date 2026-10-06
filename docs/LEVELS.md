# Building levels, tall ones included

Rooms are built by scripts in `tools/build_*.gd` and saved as `.tscn`. Everything a level needs
from the engine is in `scripts/systems/level.gd` (read the header there), `level_camera.gd` and
`camera_zone.gd`. `scenes/levels/tall_demo.tscn` (`tools/build_tall_demo.gd`) is a minimal working
example: 20 x 34 tiles, three screens high, a stair of girders, a locked top screen.

## Build and rebuild

```
godot --headless --path . res://tools/build_runner.tscn -- --builder=res://tools/build_room3.gd
```

A builder is a `RefCounted` script with `func build()` and `var errors`; copy the shape of
`build_tall_demo.gd`. The runner loads the autoloads, runs it, restores the previous unique_ids and
resource ids so rebuilds do not churn, and exits 0 (ok), 1 (a save failed) or 2 (bad builder).
After adding a `class_name` script, run `godot --headless --path . --import` once so builders can
see it (a fresh clone needs the same import).

## Size

A room is any size. Put the camera rectangle in the room's bounds, in world px:

```gdscript
room.set("limits", Rect2i(0, 0, COLS * T, ROWS * T))     # or Level.tile_limits(tiles)
room.set("camera_follow", Level.CameraFollow.TIERS)      # for anything taller than a screen
```

The viewport is 640 x 360 (20 x 11.25 tiles of 32 px). A room 360 px tall pins the camera
vertically; wider than 640 scrolls sideways. The cat dies `death_margin` (64) px under the
bottom of `limits`, so put basements inside `limits`.

## The camera

| `camera_follow` | Behaviour |
|---|---|
| `CENTRED` (default) | The camera sits on the cat. Rooms 1 to 4, home, the test room and Room 3 use this and are unchanged. `deep_bottom` and a room script's own `limit_bottom` easing (Room 1 pool, Room 4 hatch) only work here. Limit rect convention: `Rect2i(0, 24, w, 360)` (the view sits 25 px above the limits). |
| `TIERS` | Vertical dead zone: `dead_zone_up` (80) px above the view centre and `dead_zone_down` (48) below, in which the view stands still. A plain jump (95 px) never scrolls; a double jump, a climb or a fall does. A fast fall looks ahead downward (up to 80 px). Standing on a new tier, the view drifts back until the cat is within 16 px of the middle. The view centre is whole pixels; horizontally the view is on the cat. `limits` is the exact view rect. Do not use `deep_bottom`. |

`LevelCamera` (`Level.camera_rig`) does this in a late physics step (after the cat) so there is no
lag or jitter. It stays out of the way during a CineZoom cutscene, which lifts and restores the
limits, and resumes after it.

A `ScreenShake` on the camera (a pound, an explosion) restores its own base offset every frame; the
driver keeps that base on its own view each physics step, so a shake never freezes the tier camera
(`camera_audit.gd` checks it). A cutscene pan (the Master Gate finale) sets `LevelCamera.pan_to` (world
px) and tweens `pan_blend` 0..1: the view centre blends from the follow position to the target.

### Camera zones

```gdscript
var zone := CameraZone.new()
zone.position = Vector2(x, y)        # top-left, world px
zone.size = Vector2(640, 360)        # the trigger; also the camera rect unless limits_override is set
zone.lock_framing = true             # hold the view centre on the rect's middle (a one-screen puzzle)
zone.zone_priority = 0               # overlapping zones: highest wins, later entry among equals
room.add_child(zone); zone.owner = room
```

While the cat's body centre is inside the trigger, the camera limits become the zone's rect (eased
12 px a frame, `Level.zone_ease_px`). With `lock_framing` the view also glides to the centre of the
rect and holds. A rect exactly 640 x 360 is a fixed single screen. Leaving restores the level's
limits and the normal follow. Zones work in either mode; in CENTRED mode a zone makes the driver
active and the rect is exact (the 25 px shift above does not apply in that room).

## Backdrop, rain, lights

* `NightBackdrop.extend_vertically = true`: the layers tile and drift vertically (same scroll
  scales) so the view is covered at any height. `DayBackdrop` is already pinned to the view.
* `RainFX.follow_camera = true`: a window on the camera view (width and floor are taken from the
  view, drops die at the bottom of it); do not move the node. For rain that must stay out from under
  roofs, see `room3.gd` (`covered`).
* `LightingRig` uses directional light and a CanvasModulate, so it covers any height. Moon shafts
  and lamps are placed in world coordinates as usual. Vignette and HUD are on the screen layer.

## Checklist for a new or redesigned room

1. Build with the builder and the runner; commit the regenerated `.tscn` (the diff should show only
   real changes).
2. `ROOMS=<id> godot --headless --path . --script res://tools/audit/softlock.gd`: zero soft-locks,
   zero pockets. It reads any scene in `scenes/levels/` and has no height limit. Give the room a
   checkpoint or exit.
3. Margins: add the room's required climbs and long jumps to `tools/audit/spots.gd` and run
   `margins.gd` (at least 90% for the intended move, 0% for the skips).
4. The power order: no required path may need a power the player does not have yet (see the power
   order in `docs/KIT.md`); pads grant only what the room teaches; run the room's playthrough.
5. Place actors with the placement guideline in `docs/KIT.md` (Collectibles, Placement guideline).
6. `tools/audit/camera_audit.gd` for the framework, then `full_game.gd`, and the web audit for the
   rooms you touched.

Jump numbers to size against (`tools/audit/reach.gd`): a plain jump rises 95 px (3 tiles), a double
jump 171 px (5.3 tiles); Spring 211 / 284; plain travel 122 / 223 px.
