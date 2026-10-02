# Wake Cycle

A game for Jamference 2026 (Oct 2-9). Theme: "Cat and Robot".

Itch.io page: _TBD_

## Pitch

A lost house cat wakes up curled in a corner of a huge automated logistics hub
at night. The machines are not evil, just indifferent: forklifts, sorting arms
and drones go about their routes. Find your way out. Near the exit, the cat must
cross pools of experimental nanotech fluid that slowly wrap it in glowing
veins, then leave it augmented. Enhancement pads grant temporary powers (speed,
high jump, dash, ground-pound), and the hub's robots take the cat for the new
supervisor: some mirror its movements, so puzzles are solved by steering them
onto floor plates. At the end the cat gets home, curls up in its spot, and
sleeps. The game opens and closes with sleep.

## How to play

Playable in the browser. Walk into things; that is the whole interface.

| Action | Keyboard | Gamepad |
|---|---|---|
| Move | WASD / arrow keys | Left stick |
| Jump | Space | A (south) |
| Dash | Shift | B or X |
| Crouch / slide | Ctrl or C | Left shoulder |
| Ground pound | Crouch while in mid-air | Same |

Menus are rooms: walk onto the big START plate to begin. The camera follows the
cat automatically.

Enhancement pads (after the nanotech pools):

| Pad | Colour | Effect |
|---|---|---|
| Surge | Blue | Speed |
| Spring | Green | High jump |
| Phase | Cyan | Dash through drones |
| Impact | Violet | Ground-pound shockwave |

## Jam restriction compliance

The jam restriction is movement input only. Every input in Wake Cycle is a
movement: walking, jumping, dashing, crouching/sliding, and ground-pounding
(crouching in mid-air). There are no attack, shoot or interact buttons, and no
clickable UI: menus are walkable rooms, and pads, plates and pools trigger by
stepping on them.

## AI use

AI did genuine work in this build and is disclosed in full in
[AI_USE.md](AI_USE.md): tools, agent roster, and a dated build log. The shipped
game makes no live LLM calls.

## Build from source

Requirements: Godot 4.7.x (standard build, not .NET).

1. Clone the repo and open the project folder in Godot.
2. The project uses the Compatibility renderer (set in project settings).
3. To export for the web: Project > Export, choose the "Web" preset, and export.
   The preset is single-threaded, so it needs no special cross-origin headers.
4. Serve the export folder over HTTP (for example `python -m http.server`) and
   open it in a browser. Opening `index.html` directly from disk will not work.

## Credits

- Design, direction and development: Chris ([qBitnaut](https://github.com/qBitnaut))
- AI tooling: see [AI_USE.md](AI_USE.md)
- Asset credits (art, 3D, audio, music): _TBD_
