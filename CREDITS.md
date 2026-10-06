# Credits

Wake Cycle uses the following third-party assets. Every pack below is released
under CC0 (public domain), so attribution is not required, but credit is given
as a courtesy.

## Sprites, tiles and backgrounds

| Pack | Author | Source | License | Location |
|---|---|---|---|---|
| Pet Cats Pack (Cat-6: recoloured to a brown tabby by `tools/recolor_cat.py`, doubled with Scale2x and outlined by `tools/art/cat_hd.py`; Meow VFX) | luizmelo | https://luizmelo.itch.io/pet-cat-pack | CC0 1.0 | `assets/sprites/cat/` |
| Sci-fi platformer tiles 32x32 (recoloured to the Wake Cycle palette by `tools/art/recolor_tiles.py`) | bart | https://opengameart.org/content/sci-fi-platformer-tiles-32x32 | CC0 1.0 | `assets/art_hd/tiles_wake_hd.png` |
| Extension for Sci-fi platformer tiles 32x32 (the 16-colour variant sheet the recolour reads) | rubberduck | https://opengameart.org/content/extension-for-sci-fi-platformer-tiles-32x32 | CC0 1.0 | `assets/art_hd/tiles_wake_hd.png` |
| Legacy Collection (Warped sci-fi interior wall, Scifi lab support column, cyberpunk detective props, bipedal and mech units), harmonised by `tools/art/harmonize_bg.py` | Luis Zuno (ansimuz) | https://ansimuz.itch.io/ ("Legacy Collection" free download) | CC0 1.0 | `assets/art_hd/bg/`, `assets/art_hd/props/`, `assets/art_hd/robots/` |
| Warped City (night skyline layers, towers, drone, turret), harmonised by `tools/art/harmonize_bg.py` | Luis Zuno (ansimuz) | https://ansimuz.itch.io/warped-city | CC0 1.0 | `assets/art_hd/bg/`, `assets/art_hd/robots/` |

The ansimuz packs ship a `public-license.pdf` stating CC0; copies are in
`assets/art_hd/`. The warning lamp (`lamp_base.png`, `lamp_glass.png`) is cut from the
bart/rubberduck hazard sheet; the pad plate is drawn by `tools/art/make_pad_hd.py`
in the steel ramp. The Home ending's street, houses, interior, sky and credits
room (`assets/art_hd/home/`) are drawn by `tools/art/home_art.py`, with no
third-party source.

## Font

| Pack | Author | Source | License | Location |
|---|---|---|---|---|
| monogram | datagoblin | https://datagoblin.itch.io/monogram | CC0 1.0 | `assets/fonts/monogram.ttf` |

## Audio

All of the game's sound is generated with ElevenLabs (Creator plan, which includes a
commercial-use licence for the output). Nothing in it is from a third-party pack except
the two bird chirps listed at the bottom.

| What | Generated with | Location |
|---|---|---|
| Narration of the cat's inner monologue: every line of `data/monologue.json`, voiced by the premade voice "Will - Relaxed Optimist", model `eleven_v4_turbo`; settings in `voice.json` | ElevenLabs Text to Speech | `assets/audio/voice/` |
| Sound effects: footsteps, movement, powers, pickups, doors, lasers, robots, the goo transformation, thunder, UI-less map sounds. `sfx.json` maps the logical names to files | ElevenLabs Sound Effects API (`/v1/sound-generation`) | `assets/audio/sfx/` |
| Ambience loops per scene (warehouse, yard, stacks, perimeter, home, map) and a smooth rain loop | ElevenLabs Sound Effects API (loop mode) | `assets/audio/amb/` |
| Music: warehouse, yard, stacks, perimeter, home (also the credits) and map, each cut into a seamless loop with an ffmpeg crossfade | ElevenLabs Music API (`/v1/music`, instrumental) | `assets/audio/music/wc_*.ogg` |

The prompts and scripts that made them are in `tools/audio/` (`sfx_spec.py`, `gen_sfx.py`,
`gen_voice.py`, `gen_music.py`, `make_manifest.py`). The API key is read from a file outside
the repository and is never stored in it.

### CC0 audio that remains

| Pack | Author | Source | License | Location |
|---|---|---|---|---|
| Blackbird singing in garden with rustling trees (one chirp cut from it) | Cinetony | https://freesound.org/people/Cinetony/sounds/565058/ | CC0 1.0 | `assets/audio/sfx/bird_chirp_1.ogg` |
| Ambient Bird Sounds (one chirp cut from it) | isaiah658 | https://opengameart.org/content/ambient-bird-sounds | CC0 1.0 | `assets/audio/sfx/bird_chirp_2.ogg` |

The earlier CC0 audio (8-bit sound effects, Kenney impact sounds, rubberduck's SFX loops,
the qubodup drip loop, the Juhani Junkala tracks) was replaced and removed from the project.

License text: https://creativecommons.org/publicdomain/zero/1.0/
