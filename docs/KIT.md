# Actor kit

Enemies, hazards, destructibles, platforms and collectibles in the spirit of Duke
Nukem 1 and Secret Agent. Reusable scenes in `scenes/kit/`, scripts in
`scripts/kit/`, art in `assets/sprites/kit/<actor>/` with one manifest,
`assets/sprites/kit/kit_manifest.json`. Everything is `@export`-tuned.

Try it: open `scenes/lab/kit_lab.tscn` (fifteen small arenas, one per actor), or add
`?start=kit` to a **debug** web build (`OS.is_debug_build()` gates it). Lab keys:
`F1` toggle shockwave, `F2`..`F5` Surge/Spring/Phase/Impact, `F6` clear power,
`[` / `]` previous / next arena, `R` reset the arena.

Audit: `godot --headless --path . --fixed-fps 60 --script res://tools/audit/kit_audit.gd`
(first run `godot --headless --path . --import` on a fresh checkout so the new
`class_name`s register). Frames and strips: `tools/audit/kit_shots.gd`,
`tools/art/kit_strips.py`.

## The player is movement-only

No actor assumes a weapon. The ways the cat can affect a robot:

| Source | Needs | Notes |
|---|---|---|
| stomp | any power, or the shockwave unlocked | a plain cat only bounces off with a clank |
| shock | shockwave unlocked (Room 3 conduit) | the double jump's burst, radius 64 |
| pound | Impact power (Room 4) | landing from a ground pound, radius 46 |
| blast | an explosive barrel or bomb | `Blast.explode`, chain reactions |

Powers arrive one at a time (Room 1 none, Room 2 Surge, Room 3 Spring + shockwave,
Room 4 Phase + Impact), so early rooms use enemies as avoidance and timing puzzles
and later rooms add defeat. Enemies *may* shoot.

## Size: everything is size-agnostic

Chris wants tighter sprites (enemies about 1 to 1.5 tiles of 32 px). Every actor has
`@export var sprite_scale` (0 = the manifest default for that actor) and takes its
art and its collision boxes from the manifest:

* `kit_manifest.json` gives each actor `scale`, `pivot`, `bounds` (opaque pixels
  relative to the origin) and `parts` (sheet, cell size, pivot, animations).
* `KitArt` builds `SpriteFrames` / `AnimatedSprite2D` from it. Colliders are
  `bounds * sprite_scale` (body shrunk a little, hit box +4 px).
* Default scales put walkers at 40-50 px (patrol bot 0.7, mech 0.75, the rest 1.0).

To resize one actor in a room set `sprite_scale` on the instance. To resize the whole
kit change the `scale` fields in the manifest (or `scale=` in `tools/art/kit_art.py`).

## Defeat rules (KitEnemy)

Each source maps to `none` (clank), `stun` or `destroy`; `@export_enum` per enemy.
A stunned enemy is finished by a stomp or a pound (`stun_destroys`). `armour_hits`
> 0 makes that many harming hits necessary first.

| Enemy | stomp | shock | pound | blast | Reward |
|---|---|---|---|---|---|
| SentryTurret | clank | stun | destroy | destroy | 250 |
| KitPatrolBot | stun, then destroy | stun | destroy | destroy | 200 |
| HoverDrone | destroy | stun (falls) | destroy | destroy | 150 |
| HopperBot | stun, then destroy | stun | destroy | destroy | 200 |
| CrawlerBot | stun, then destroy | stun (ceiling: shaken off) | destroy | destroy | 200 |
| SecurityCamera | clank | stun (blind) | destroy | destroy | 150 |
| HeavyMech | clank | clank | stun, 3 hits | stun, 1 hit | 2000, chip guaranteed |

A plain cat's stomp is a clank for everyone (it bounces off). "Stomp" in the table is
with a power.

Defeat: hit-flash (0.12 s, white) then `ExplosionFX`: fireball (CC0 Warped City
frames), debris chunks that fly, bounce off the floor and fade, a smoke puff, a
screen shake scaled to `explosion_size`, a `+N` pop-up. Then the score, a
`defeated(enemy)` signal, and a data chip with probability `chip_chance`. Stunned
enemies show orbiting stars, sparks and a flickering fizzle that speeds up and
gutters before they recover.

Every enemy has a **telegraph** (`begin_telegraph` / `end_telegraph`): the measured
length of the last one is `last_telegraph`, never under 0.4 s in the audit.

## Enemies

All extend `KitEnemy` (`CharacterBody2D`; groups `enemy`, `kit_enemy`,
`shock_receiver`). Origin = the feet (or the mount point). Shared exports:
`sprite_scale`, `stomp_effect`, `shock_effect`, `pound_effect`, `blast_effect`,
`armour_hits`, `stun_destroys`, `stun_time`, `points`, `explosion_size`,
`chip_chance`, `touch_damage`, `stompable`, `body_shrink`.
Shared API: `hit(source) -> "clank" | "stun" | "destroy" | "ignored"`, `stun(t)`,
`defeat()`, `is_stunned()`, `is_dead()`, signals `defeated`, `stunned`.

* **SentryTurret** (`sentry_turret.tscn`). `mount` FLOOR / CEILING / WALL_LEFT /
  WALL_RIGHT (rotates the node), `detect_range`, `charge_time` (0.9), `cooldown`,
  `bolt_speed` (110), `aim_lock`, `dormant`. Tracks, charges (barrel glows, whine),
  locks aim for the last 25 % of the charge, fires one slow bolt. `alert(seconds)`
  wakes a dormant turret and speeds up all of them. Group `kit_turret`.
* **KitPatrolBot** (`kit_patrol_bot.tscn`, the Legacy biped at 0.7). `speed`,
  `laser_range`, `aim_time` (0.7), `burst_time`, `cooldown`, `line_half_height`,
  `shoots`. Walks, turns at walls/edges; cat in its line: stops, eyes flare, fires a
  short `KitBeam` laser burst forward. (The room `PatrolBot` is unchanged except for
  a new `sprite_scale` export, default 1.)
* **HoverDrone** (`hover_drone.tscn`). `patrol_range`, `speed`, `drop_window`,
  `drop_range`, `arm_time`, `cooldown`, `drop_kind` BOMB / SPARK. Patrols a sine
  bob; cat below: hangs still, bomb bay glows, drops. Stunned: falls, fizzles, rises
  again. Hum loop `drone_hover`.
* **HopperBot** (`hopper_bot.tscn`). `detect_range`, `squat_time` (0.55), `hop_speed`,
  `hop_height`, `rest_time`. Squats (the telegraph), hops in an arc at where the cat
  was.
* **CrawlerBot** (`crawler_bot.tscn`). `crawl_range`, `crawl_speed`, `trigger_half`,
  `drop_range`, `tell_time` (0.6), `roll_speed`, `roll_time`, `mount_floor`. Origin =
  the ceiling surface. Cat beneath: shudders, drops, rolls as a spiked ball, burns
  out (stunned, harmless).
* **SecurityCamera** (`security_camera.tscn`). `sweep_min`, `sweep_max` (deg, 90 =
  down), `sweep_speed`, `half_angle`, `view_range`, `spot_time` (0.7), `alarm_time`,
  `alarm_radius`, `shutters` (NodePaths of `KitShutter`s). Spots (lens turns amber,
  ticks), then the alarm: turrets in range `alert()`, `KitShutter`s `close_for()`.
  A phasing cat is not seen.
* **HeavyMech** (`heavy_mech.tscn`, the Legacy mech at 0.75). `walk_speed`,
  `charge_speed`, `charge_time`, `tell_time` (0.9), `cooldown`, `daze_time`,
  `detect_range`; `armour_hits` 3. Charge: crouch + steam, then runs; a wall slam dazes
  it (the window to pound it).
* **KitShutter** (`kit_shutter.tscn`, extends `Shutter`). Starts open;
  `close_for(seconds)`. Group `alarm_shutter`.

## Projectiles

`Projectile` (Area2D on the hazards layer, mask player + world + breakables):
`Projectile.spawn(parent, global_pos, velocity, Kind.BOLT | BOMB | SPARK)`.
Exports `lifetime`, `max_range`, `sprite_scale`, `blast_radius`, `fall_gravity`.
Trail, glow (`PointLight2D` + HDR), impact FX, `despawned(reason)` with reason
`lifetime`, `range`, `impact_cat`, `impact_world`, `impact_target`. A phasing (dashing)
cat passes through. A body with `on_projectile_hit(p)` (barrels) is set off by it.
A BOMB blasts (`Blast.explode`) on impact. Group `kit_projectile`.

`KitBeam` (Hazard) is the patrol bot's short laser: `fire(seconds)`, phase-through.

## Blasts and chain reactions

`Blast.explode(ctx, pos, radius, source)` hurts the cat once if inside the radius
(not if phasing), calls `on_blast` on groups `enemy` and `blast_receiver` (walls),
and `trigger(delay)` on group `explosive` (barrels), so a row of barrels goes off in
turn. Receivers expose `shock_offset` and `shock_half` (box centre and half size).

## Destructibles

* **PushBarrel** (`barrel_plain.tscn`): `RigidBody2D`, pushable, counts as `pushable`.
* **KitBarrel** (`barrel_explosive.tscn`, `barrel_acid.tscn`): `blast_radius` (84),
  `fuse`, `pool_width`, `pool_life`, `persist`. Set off by shock, pound, a bolt, a bomb
  or a blast. Explosive: blast + chain. Acid: breaks into an `AcidPool`.
* **KitWall** (`wall_cracked.tscn`, `wall_reinforced.tscn`, `wall_blast.tscn`):
  `size_tiles` (Vector2i, default 1x2), `persist`, `reward` (a `Collectible.Kind`, or
  -1). CRACKED: shock, pound or blast. REINFORCED: pound only. BLAST: an explosive
  blast only. A wrong hit clanks and sparks. `breaks_with(source)` for tooling.

## Hazards

Timed hazards extend `KitHazard` (Area2D, layer 8): phases IDLE, WARN, LIVE with
`idle_time`, `warn_time`, `live_time`, `start_offset`. **The warning is never under
0.4 s** (`MIN_WARN`; `warn_seconds()` clamps). Hits hurt one pip and knock back; they
never kill. Hooks: `is_warning()`, `is_dangerous()`, `last_warn`.

* **ElectricFloor**: `width_tiles`, `arc_height`. Phase passes through the arcs.
* **Crusher**: `width_tiles`, `stroke`, `slam_time`, `retract_time`. Origin on the
  ceiling; set `stroke` so the head reaches the floor.
* **SpikeTrap**: `width_tiles`, `spike_height`.
* **VentHazard**: `kind` STEAM / FLAME, `column_height`, `column_width`, `rise_time`
  (the rooms' `SteamHazard` is unchanged).
* **AcidPool** (not timed): `width`, `lifetime` (0 = permanent), `spread_time`.
* **FallingDebris**: `trigger_half`, `trigger_depth`, `warn_time`, `respawn_time`.
  Drops a `FallingRock` when the cat passes beneath; the crack shudders first.
* **KitConveyor**: `width_tiles`, `speed` (px/s, negative reverses), `set_speed()`.
* **KitPlatform** (`platform_horizontal`, `platform_vertical`, `platform_falling`):
  `mode`, `width_tiles`, `travel`, `speed`, `pause`, `fall_delay` (>= 0.4),
  `respawn_time`. One-way. FALLING shakes while stood on, drops, returns.

## Collectibles

Replace the plain diamond. Keep the C-A-T letters (`Pickup.Kind.LETTER`). The old
`gem.tscn` / `fish.tscn` keep working: the gem is drawn as a ball of yarn (still 100),
the fish with the fish sprite.

| Scene | Kind | Score | SFX | Notes |
|---|---|---|---|---|
| `pickup_fish` | FISH | heals 2 pips | `pickup_heal` | |
| `pickup_yarn` | YARN | 100 | `pickup_small` | the common |
| `pickup_bell` | BELL | 250 | `pickup_big` | |
| `pickup_mouse` | MOUSE | 500 | `pickup_big` | |
| `pickup_chip` | CHIP | 1000 | `pickup_big` | robot loot (`Collectible.drop`) |
| `pickup_bone` | BONE | 2000 | `pickup_rare` | golden fish bone |
| `pickup_memory` | MEMORY | 5000 | `pickup_rare`, `memory_fragment` | plays `memory_id` (a Monologue set) or speaks `line` |

`Collectible`: `kind`, `persist`, `sprite_scale`, `memory_id`, `line`; signal
`collected(kind)`. Each has a sparkle (debris burst; a refracting ring for the rare
ones), a score pop-up, a glint, and rarer items glow brighter.

### Placement guideline

* **Commons (yarn, fish) on the main path.** They are the breadcrumb: the player sees
  one every few seconds without risk. A fish where the previous section hurt.
* **Mid-value (bell, mouse) over hazards or after optional jumps.** A bell above a
  spike trap, a mouse on the far side of an electric floor, on a short moving
  platform, or at the end of a one-jump detour. The risk is a pip, never a death.
* **Rares (golden bone, memory fragment) in secret areas.** Behind a destructible
  wall (a cracked wall for the first, a reinforced or blast-only wall for the
  deeper ones), above a crusher's slam zone, or at the end of a moving-platform
  detour. Show a hint: a glint through a crack, a single bell leading to the wall.
* **Data chips come from robots**, never placed. A mech guarantees one.
* One rare per room at most; the memory fragment is for story beats.
* Never make a *required* path depend on breaking a wall that needs a power the
  player does not have yet (see the power order above).

## SFX hooks (logical names)

Call `KitSfx.play(self, "turret_fire")` (loops: `KitSfx.loop(self, "drone_hover")`).
Resolution: the audio library's manifest (`res://assets/audio/sfx_manifest.json`,
`{"name": "path"}` or `{"sounds": {...}}`), then `assets/audio/sfx_lib/<name>.ogg|wav|mp3`,
then a stand-in from the shipped 8-bit set, else silence. A missing name never errors.
Set `KitSfx.use_placeholders = false` to hear only the real library.

The existing `Sfx.play(ctx, name, ...)` is untouched; `KitSfx` is the one seam, so when the
ElevenLabs library lands it needs only files and a manifest, no actor changes.

Names: `turret_charge` `turret_fire` `laser_charge` `laser_zap` `drone_hover` (loop)
`bomb_drop` `robot_explode` `robot_stun` `robot_clank` `debris` `barrel_explode`
`barrel_fuse` `acid_hiss` `acid_splash` `electric_arc` (loop) `electric_warn`
`crusher_warn` `crusher_slam` `spike_warn` `spike_pop` `steam_hiss` `flame_burst`
`hopper_squat` `hopper_land` `crawler_drop` `camera_alarm` (loop) `camera_spot`
`mech_charge` `mech_slam` `wall_break` `wall_clank` `platform_shake` `platform_fall`
`conveyor_hum` (loop) `rock_fall` `rock_land` `pickup_small` `pickup_big`
`pickup_rare` `pickup_heal` `memory_fragment`. (`KitSfx.LOGICAL_NAMES` is the code's list.)

## The art pass

Placeholder art is drawn by `tools/art/kit_art.py` in the palette. To replace an actor:

1. Draw a horizontal strip PNG with the same cell size and frame order and put it at
   the `file` path in the manifest (`assets/sprites/kit/<actor>/<part>.png`), or point
   the manifest `file` at a new path.
2. Keep (or edit in the manifest) `cell`, `pivot` (origin inside a cell: feet for
   walkers, centre for flyers) and each animation's `frames`.
3. Update `bounds` (opaque pixels relative to the pivot: `tools/art/kit_art.py` computes
   it; rerun it or edit by hand). Colliders follow.
4. Set the actor's `scale` in the manifest (or `sprite_scale` on an instance).

Reusing existing CC0 art: `patrol_bot` and `heavy_mech` use the Legacy Collection
sheets in `assets/art_hd/robots/`; the explosion fireball is Warped City's
`enemy-explosion`. Everything else is scripted placeholder art that DaVinci should
replace: turret (body + head), hover drone, hopper, crawler (walk + roll), camera,
the three barrels, the three wall tiles, electric panel, crusher head and rod, spike
trap, vent nozzles, acid pool, debris rock and crack, conveyor, platform, bolt, bomb,
spark, debris chunks and the seven collectibles.
