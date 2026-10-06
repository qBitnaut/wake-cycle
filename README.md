# Wake Cycle

A game for Jamference 2026 (Oct 2-9). Theme: "Cat and Robot".

Itch.io page: _TBD_

## Pitch

A lost house cat wakes up curled in a corner of a huge automated logistics hub
at night. The machines are not evil, just indifferent: forklifts, sorting arms
and drones go about their routes. Find your way out. At the end of the first
level the cat falls into a pool of experimental nanotech goo, which wakes its
mind and augments it: from there the cat thinks in words, and the hub's robots
take it for the new supervisor. Some mirror its movements, so puzzles are solved
by steering them onto floor plates. Enhancement pads grant temporary powers, and
the cat gets home, curls up in a sunbeam, and sleeps. The game opens and closes
with sleep.

## The game

A 2D platformer in the spirit of Apogee's Secret Agent, at 640x360 (integer-scaled
to 1280x720 and up) with modern lighting. Five levels, joined by a world map:

1. **The Warehouse.** No powers. Plain movement: run, jump, double jump, crouch,
   stomp bots. The goo pool at the end is the transformation: it grants
   intelligence and augments, and the cat's inner monologue begins.
2. **The Yard.** The Surge pad (speed).
3. **The Stacks.** The Spring pad (high jump), then the shockwave unlocked at a
   power conduit, and a MirrorBot puzzle.
4. **The Perimeter.** The Phase and Impact pads, and the Master Gate finale,
   where the system accepts the cat as "supervisor". Night turns to dawn.
5. **Home.** A sunny morning. The cat gets in, curls up in a sunbeam, and the
   credits roll.

Between levels, a **world map** (parallax, with the time of day moving from night
to morning along the route) shows the way on. Finished levels can be revisited
for hidden C-A-T letters and gems. Locked bonus and secret nodes mark levels
that do not exist yet. Checkpoints and save/continue persist in the browser.

## How to play

Playable in the browser. Walk into things; that is the whole interface.

| Action | Keyboard | Gamepad |
|---|---|---|
| Move | A / D or Left / Right | D-pad or left stick |
| Up (doors, ladders, map nodes) | W or Up | D-pad or stick up |
| Crouch (ground pound in mid-air) | S or Down | D-pad or stick down |
| Jump | Space or Ctrl | A (south) |
| Dash | Shift | X or B |

Menus are rooms: walk onto the big START plate to begin. On the world map, walk
along the paths and press Up (or Jump) on a level to enter it. The camera
follows the cat automatically.

> Status: all five levels are built and playable end to end. The 3D prototype
> that came first is kept locally under the tag `3d-prototype`; see
> [AI_USE.md](AI_USE.md) for the design history.

Enhancement pads (after the nanotech pools):

| Pad | Colour | Effect |
|---|---|---|
| Surge | Blue | Speed |
| Spring | Green | Super jump: any press (tap or hold) clears 6 tiles, no jump cut; a press in the air adds a real second jump |
| Phase | Cyan | Shift dashes through enemies and laser fences |
| Impact | Violet | Down in mid-air ground-pounds; breaks cracked floors |

Pads give a timed charge (10 s) and recharge after a few seconds. The
double jump is always available; once the shockwave is unlocked, the second
jump also releases a short radial burst (breaks weak crates, kicks crates,
stuns small bots, flips shock switches). Checkpoints save to the browser's
storage; step on the glowing CONTINUE pad near the start to load it.

## Debug keys (test room only)

F1 toggles the shockwave, F2-F5 grant Surge / Spring / Phase / Impact, F6 clears
the power. These are not in the input map and are not part of the game.

## Jam restriction compliance

The jam restriction is movement input only. Every input in Wake Cycle is a
movement: walking, jumping, dashing, crouching/sliding, and ground-pounding
(crouching in mid-air). There are no attack, shoot or interact buttons, and no
clickable UI: menus are walkable rooms, the world map is navigated by walking,
levels are entered with Up or Jump, and pads, plates and pools trigger by
stepping on them. Attacks are movement too: a stomp, the double-jump shockwave,
a dash and a ground pound. The camera takes no input.

## AI use

AI did genuine work in this build and is disclosed in full in
[AI_USE.md](AI_USE.md): tools, agent roster, and a dated build log. The shipped
game makes no live LLM calls.

## Build from source

Requirements: Godot 4.7.x (standard build, not .NET), Compatibility renderer.

1. Clone the repo and open the project folder in Godot.
2. The project uses the Compatibility renderer (set in project settings).
3. To export for the web: Project > Export, choose the "Web" preset, and export.
   The preset is single-threaded, so it needs no special cross-origin headers.
4. Serve the export folder over HTTP (for example `python -m http.server`) and
   open it in a browser. Opening `index.html` directly from disk will not work.

Regenerating generated content (all optional; the results are committed):

- Art: `tools/art/` (recoloured tiles, harmonised backgrounds and props, the HD
  cat, the pad plate). The scripts take the downloaded CC0 packs as arguments;
  see each script's docstring.
- TileSet: `godot --headless --path . --script res://tools/build_tileset_hd.gd`
- Test room: `godot --headless --path . --script res://tools/build_test_room.gd`
- Rooms: `godot --headless --path . --script res://tools/build_room1.gd` (also Room 2), then
  `build_room3.gd`, `build_room4.gd` and `build_home.gd` the same way. Each room's exit
  is set in its builder, so a rebuild keeps the chain.

Audits (see `tools/audit/`): `reach.gd` measures jump reach, `playthrough.gd`
drives the cat through every beat of the test room in headless Godot, and
`web_playthrough.mjs` does the same in the web export with Playwright.
`room1_playthrough.gd` and `web_room1.mjs` play Room 1 start to finish with plain
movement only (wake-up, platforming, the pool, the transformation, the exit,
Room 2) and assert that no power was granted before the pool. `room1_tour.gd`
renders Room 1 stop by stop for a look.

The human-margin audit (`tools/audit/margins.gd`, spots in `spots.gd`, method in
`human_sweep.gd`; every room audit and `full_game.gd` run it too) sweeps every required
climb and long jump with ordinary input spread (take-off position, double-jump press time,
jump hold) and asserts the intended move lands in at least 90% of it and the unintended
ways (no power, the wrong power, a skip) in none. Looping sounds go through `LoopSfx`
(`scripts/systems/loop_sfx.gd`): a child of its source, volume set by hand from the
distance to the cat (the web export plays audio as samples, where positional audio is not
reliable), stopped out of range and freed with its source; the audits assert no looping
player outlives its scene (`LoopSfx.orphans`, published as `window.__wake.loops`).

## Room 1 and the powers

The game opens in Warehouse Room 1 (the main scene). It uses plain movement only:
run, jump, double jump, crouch, stomping bots. A fresh game starts with nothing
unlocked. The unavoidable dark pool at the end calls `TransformSequence.play(cat)`
(`scripts/systems/transform_sequence.gd`: the goo glow and the cinematic zoom) after
emitting `nanotech_absorbed_started` (on the level and on `GameState`); when it
finishes the level calls `GameState.awaken_mind()` (the goo grants intelligence, saved as `intelligence`, signal `mind_awakened`; no power is granted, powers arrive later via pads). `Monologue.say(text, duration)` is the hook for the cat's inner monologue. The exit fades to black
and loads the next room, which auto-saves on arrival (`RoomExit`,
`RoomTransition`). Pass `-- --skip-intro` to Godot to start Room 1 awake.

## The chain

Room 1 (the warehouse, the pool: the mind awakens) -> Room 2 "The Yard" (Surge) ->
Room 3 "The Stacks" (Spring, the conduit that unlocks the shockwave, the mirror bot) ->
Room 4 "The Perimeter" (Phase, Impact, the Master Gate, the dawn) -> Home -> the credits ->
a fresh Room 1. Every exit is a `RoomExit` that fades out and auto-saves the next room on
arrival; `GameState` (mind, shockwave, score, keys, letters, pickups, health) carries across.
Powers come only from pads and never survive an exit. In Room 4 the laser fences are solid
while they are on (`LaserFence.solid_when_on`): only a dashing Phase cat gets through, and a
Phase pad sits between any two fences. The Room 4 rain loop fades with the dawn.

`tools/audit/full_game.gd` plays the whole chain in one headless run, reusing every room's
playthrough routine, with continuity checks at each transition and continue-from-save checks
from a Room 3 and a Room 4 checkpoint.

Web deep links for audits: `index.html?start=room2` (or `room3`, `room4`, `home`),
and `index.html?start=map&completed=<level id>[&letters=3]` for the world map (all
handled once per page load in `Room1._web_start_override`).

## The world map

Every room exit leads to the world map (`scenes/ui/world_map.tscn`, see
`docs/WORLD_MAP.md`): the finished level is stamped, the route to the next one
draws itself and the cat walks there; Up on a plate goes in. Finished levels can be
revisited for hidden collectibles: Room 1 then starts awake (no intro, the pool
inert), Room 3's conduit only sparks and Room 4's relays stay lit and its gate open.
Home is the last node and plays the ending. Continue returns to the map when the
save was made there.

## Home, the ending

`scenes/levels/home.tscn` (built by `tools/build_home.gd`, art by
`tools/art/home_art.py`): the morning after the storm. A short, gentle walk
down a sunny, rain-washed street (puddles, glints, birds, no challenge) to the
cat's own house. Walking into the door takes the cat through the flap and the
front wall dissolves; walking into the sunbeam on its cushion locks input, and
the cat curls up and sleeps while the last lines play. Then the credits
(`scenes/ui/credits.tscn`, lines in `data/credits.json`): the title card, the
roll (holding any movement speeds it up), "The End", and a movement press
returns to Room 1 from the beginning. Finishing marks the game complete
(`user://complete.json`) and clears the checkpoint.

Audits: `tools/audit/home_playthrough.gd` plays it headless from the arrival
to the return to Room 1; `tools/audit/web_home.mjs` does the same in the web
export through the debug deep link `index.html?start=home`, with a screenshot
at every moment; `tools/audit/home_tour.gd` renders the street stop by stop.

## Credits

- Design, direction and development: Chris ([qBitnaut](https://github.com/qBitnaut))
- AI tooling: see [AI_USE.md](AI_USE.md)
- Asset credits (art, font, audio): see [CREDITS.md](CREDITS.md)
