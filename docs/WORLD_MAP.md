# The world map

Between levels the cat crosses a map of the district, the way Secret Agent did
between missions: the warehouse, the container yard, the stacks, the perimeter
fence and the suburbs, side-on, with the route drawn across them. The game
still starts in the warehouse (Room 1). After each room's exit the map opens,
the new stretch of path draws itself in, and the cat walks to the next place.
Home is the last node, and going in plays the ending.

| What | Where |
|---|---|
| Level registry | `data/levels.json` |
| Registry and progress rules | `scripts/systems/level_registry.gd` (`LevelRegistry`) |
| The map | `scenes/ui/world_map.tscn`, `scripts/ui/world_map.gd` (`WorldMap`) |
| Node plates | `scripts/ui/map_marker.gd` (`MapMarker`) |
| Shaders | `shaders/map_layer.gdshader`, `map_glow.gdshader`, `map_sky.gdshader` |
| Art (generated) | `tools/art/map_art.py` writes `assets/art_hd/map/*` and `map_art.json` |
| Audits | `tools/audit/world_map_audit.gd` (headless), `tools/audit/web_map.mjs` (web), `tools/audit/map_tour.gd` (frames) |

## How it plays

- **Movement only.** Left and right walk the cat along open paths from node to
  node. Up and down walk the branches at a fork. On a level, **Up or Jump goes
  in**, like walking into a door. Nothing else is read: there are no buttons,
  no mouse and no Enter key.
- **Arriving** after a level: the finished plate stamps, the path to each newly
  opened level draws itself in while the camera follows the drawing head (the
  parallax pan), the new plate lights up, and the cat walks there. Then the
  player has control. Jump (or any direction) during the reveal speeds it up
  four times.
- **Going in**: the cat hops, the plate flares, the view eases in on the door
  (`CineZoom`), the screen fades and the level's scene loads.
- **Revisiting** finished levels is allowed (hidden collectibles).
- **Time of day follows the route**, per screen column: night and rain at the
  warehouse end, the rain easing over the stacks, violet pre-dawn at the fence,
  morning over the suburbs. Panning carries the dawn across the frame.
- **Plates**: gold and breathing = open, cream with a star = finished (with the
  C-A-T letters and gems found there underneath), dark with a padlock = locked.
  A secret draws nothing until it opens.

## API

```gdscript
WorldMap.open("yard")              # the yard is finished: fade out, open the map
WorldMap.SCENE                     # "res://scenes/ui/world_map.tscn"
```

- `open(completed_id)` completes the level in `LevelRegistry` (its `unlocks`
  open), fades out with `RoomTransition`, and opens the map, which plays the
  reveal. `open("")` just shows the map where the cat was.
- A `RoomExit` whose `next_scene` is `WorldMap.SCENE` works with no code: the
  map sees which level the cat came from (`SaveSystem.session_scene`) and
  treats it as finished.
- Signals on the map: `level_chosen(id, scene_path)` (the player went in, just
  before the transition), `reveal_finished`, `arrived(id)`.
- `enter_level(id) -> bool` goes into a level from code (false, and the padlock
  shakes, if it is not enterable).
- `WorldMap.load_levels = false` (tests) makes going in emit `level_chosen`
  without changing scene.

`LevelRegistry` answers questions about the data and the progress:
`id_for_scene(path)`, `scene_of(id)`, `is_open(id)`, `is_enterable(id)`,
`is_visible(id)`, `is_completed(id)`, `complete(id) -> newly opened ids`,
`route(a, b)`, `letters_found(id)`, `gems_found(id)`, `gems_total(id)`.

## Saving

Progress lives in `GameState`, so it is saved and restored with everything
else. Only new keys were added; every old field is unchanged.

- `GameState.map_completed`, `map_unlocked`, `map_node` (cleared by `new_game()`).
- `GameState.snapshot()` has a `"map"` key; `restore()` leaves map progress
  alone when given an older snapshot without one.
- `save.json` has `"map": {"completed": [...], "unlocked": [...], "node": "yard"}`.
  `continue_game()` carries it into the session snapshot.
- The map saves when it opens (the save's `scene` is the map, so Continue
  returns to the map) and whenever the cat stops on a level.

## Adding a level, a bonus or a secret

1. **Make the scene** (a `Level`, like the rooms), and give its exit a
   `RoomExit` whose `next_scene` is `res://scenes/ui/world_map.tscn` (or call
   `WorldMap.open("<id>")` where it ends).
2. **Add an entry to `levels` in `data/levels.json`:**

   ```json
   {
     "id": "rooftops",
     "name": "The Rooftops",
     "scene": "res://scenes/levels/rooftops.tscn",
     "root": "Rooftops",
     "order": 3.5,
     "bonus": true,
     "pos": [1146, 136],
     "landmark": "water_tower",
     "unlocks": [],
     "collectibles": {"letters": [], "gems": 12},
     "map_line": "rooftops_seen"
   }
   ```

   - `root` is the scene's root node name: gems are counted from the pickup
     ids under it (`/root/Rooftops/Gem...`). `gems` is the total in the
     scene (the audit checks it against the .tscn).
   - `order` is story order (decimals slot extras between the rooms).
   - `bonus: true` shows a greyed plate with a padlock until it opens.
     `secret: true` hides it (plate, path and stairs) until it opens.
   - `requires` adds conditions: `{"letters": 3}` (all C-A-T letters),
     `{"gems": 50}`, `{"collected": ["/root/Room2/Valve"]}`,
     `{"completed": ["stacks"]}`.
   - `map_line` (optional) is a `data/monologue.json` id, played once when
     the level first lights up on the map.
   - A bonus or secret with `"scene": ""` (or a scene that does not exist yet)
     stays shut: that is what the three placeholders (`drain`, `water_tower`,
     `signal_box`) are. Give one a scene and it opens with its parent.
3. **Unlock it**: add its id to the `unlocks` of the level that leads to it.
4. **Join it to the route** with an entry in `paths`:
   `{"a": "stacks", "b": "rooftops", "via": [[x, y], ...]}`. `via` points
   bend the path; where it leaves the street the map draws the stairs (slopes),
   ladders (vertical) and walkways (level) itself.
   - **A branch that goes UP must start at a junction, not at a level**,
     because Up on a level goes in. Add `{"id": "fork_x", "pos": [x, y]}` to
     `junctions` on the main path and run the branch from it (see
     `fork_tower`). Branches that go sideways or down can leave a level.
   - A junction with one way on is walked straight through; at a real fork
     the cat waits for a direction.
5. **Landmark art**: write a function in `tools/art/map_art.py` that returns a
   `Sheet` (albedo plus a glow sheet for lamps and windows) placed around the
   node, add it to `main()`, and run `python3 tools/art/map_art.py`. The map
   reads the placement from `map_art.json`. Paint in daylight albedo: the map
   tints it per column by time of day and adds the rim light. Or reuse an
   existing landmark name.
6. **Run the audit**: `godot --headless --path . --fixed-fps 60 --script res://tools/audit/world_map_audit.gd`.

Map size, the start and the final level are `size`, `start` and `final` at
the top of `levels.json`. The time of day runs from the start node's x (night)
to the final node's x (morning).

## Wiring the rooms to the map (for integration)

Nothing in the rooms, their exits or `RoomTransition` was changed. To route the
game through the map:

1. **Point every room exit at the map.** Either set `next_scene` (zero code):

   | Scene and builder | `next_scene` now | Set it to |
   |---|---|---|
   | `room1.tscn`, `tools/build_room1.gd` | `room2.tscn` | `res://scenes/ui/world_map.tscn` |
   | `room2.tscn`, `tools/build_room2.gd` | `room3.tscn` | `res://scenes/ui/world_map.tscn` |
   | `room3.tscn`, `tools/build_room3.gd` | `stubs/after_room3.tscn` | `res://scenes/ui/world_map.tscn` |
   | `room4.tscn`, `tools/build_room4.gd` | `stubs/after_room4.tscn` | `res://scenes/ui/world_map.tscn` |

   or, where a room ends in code (a finale), call `WorldMap.open("<level id>")`
   instead of `RoomTransition.go(...)`. The ids are `warehouse`, `yard`,
   `stacks`, `perimeter`, `home`. The `after_room3` / `after_room4` stubs are
   then unused.
2. **Room 1 revisits.** The map lets the cat go back into the warehouse.
   Room 1 must then start awake: when `RoomTransition.arriving` is true and
   `GameState.intelligence` is set, skip the intro, do not call
   `GameState.new_game()` (today it does whenever `intro_done` is false, which
   after a Continue would wipe the run, map progress included), start in the
   FREE beat with the pool inert, and keep the pool trigger off.
3. **Home** needs nothing: it arrives through `RoomTransition` as before. After
   the credits the run restarts in Room 1 with `new_game()`, which clears the
   map.
4. **Deep link** `index.html?start=map&completed=<id>[&letters=3]` already
   works (`SaveSystem._ready` calls `WorldMap.web_deep_link()`). It can move
   into `Room1._web_start_override` later if preferred (`if start == "map":
   WorldMap.web_deep_link(); return`); the call is guarded to run once.
5. **Check** with the audit above and `node tools/audit/web_map.mjs <export>
   <out>`; on the integrated branch every story scene exists, so all five
   plates can be entered and the gem totals are checked against the rooms.
