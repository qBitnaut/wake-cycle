# AI Use Disclosure: Wake Cycle

Entry for Jamference (Oct 2-9, 2026). Theme: "Cat and Robot". This document
discloses which AI tools were used, what they did, and where. It is updated as
the build progresses.

## Summary

Wake Cycle is a solo project: one human (Chris, GitHub: qBitnaut) directing a
squad of specialised AI agents. The human sets the vision, makes the design
calls, and reviews and accepts or rejects what the agents produce. The agents do
the bulk of the concept evaluation, planning, implementation, debugging, testing
and documentation work.

AI is used in the build. There is no live LLM at runtime: the shipped game makes
no model calls. This is a deliberate choice. It keeps the browser build free to
run, deterministic, and reliable for judges, with no API keys, latency or
per-player cost. The AI work is in the game's code, structure and design, not in
a chat box bolted on.

## Tools

| Tool | What it did | Where in the project |
|---|---|---|
| Claude Code (Anthropic CLI agent), Claude Opus 5.5 | Concept brainstorming and evaluation; scope planning; fitting the design to the movement-only restriction; project scaffolding; documentation. Further use (implementation, debugging, tests, UI) will be logged below. | Whole project: design decisions, Godot project structure, `README.md`, `AI_USE.md` |
| Art / 2D tool | No generative art. CC0 pixel packs, selected and licence-vetted by AI (`jadzia`). The HD look is made by small deterministic Pillow/numpy scripts written by AI (`davinci`, `data`): explicit palette swaps of the tile sheet and the ansimuz layers (no quantising, no model in the loop), and a Scale2x + gradient-map + outline pipeline for the cat. | `assets/art_hd/`, `assets/sprites/cat/`, `tools/art/`, `tools/recolor_cat.py`, `tools/build_tileset_hd.gd` |
| Audio / SFX tool | TBD (not chosen yet) | TBD |
| Music tool | TBD (not chosen yet) | TBD |

Claude Code is configured as "Intrepid": an orchestrator agent that routes work
to specialised sub-agents, each with its own role and instructions.

## Agent roster

Agents actually used so far. Rows are added as more are used.

| Agent | Role | Used for |
|---|---|---|
| Captain Janeway (orchestrator) | Routes work to the squad and reports to the human | Concept brainstorming and evaluation, scope cut, restriction fit; dispatching all work below |
| `data` | Implementation and builds | Project scaffolding, web export pipeline and browser test |
| `jadzia` | Research | Asset sourcing and license vetting |
| `davinci` | Visual design and polish | Lighting, toon shader, VFX (moonbeams, drips, puddles, nanotech veins); in progress |
| `doctor` | Documentation | `README.md`, `AI_USE.md` |
| `miranda` | Git and GitHub | Repository creation and commits |

Planned (not yet used): `riker` (architecture), `belanna` (debugging), `tuvok`
(testing), `icheb` (UI iteration).

## What the human did

- Chose the theme interpretation and the core concept.
- Set the constraints: movement-only input, browser-playable, one week, solo.
- Reviews and decides on every design and scope call the agents raise.
- Will choose and direct the art, 3D and audio tools (see placeholders above).

## Build Log

Append-only. Add a dated entry for each working day. Do not edit past entries.

### 2026-10-02

- Concept work: brainstormed and evaluated game concepts against the theme and
  the movement-only restriction. Settled on a lost house cat in an automated
  logistics hub, with nanotech-based enhancement pads and robots that mirror the
  cat's movement.
- Scoping: agents helped cut the idea down to what one person can finish in a
  week.
- Restriction fit: every mechanic mapped to movement (jump, dash, crouch/slide,
  ground-pound from mid-air crouch). Menus become walkable rooms instead of
  clickable UI.
- Scaffolding: Godot 4.7 project (3D, Compatibility renderer, single-threaded
  web export) set up by the `data` agent.
- Docs: `README.md` and this file drafted by the `doctor` agent.
- Restriction revealed: the jam's rule is MOVEMENT INPUT ONLY. Janeway and Chris
  adapted the design to fit: enhancements come from stepping on floor pads,
  attacks are movement (dash-through, ground pound), menus are walkable rooms,
  and the follow camera takes no camera input.
- Story rework: the AI pointed out how close the first concept was to *Stray*
  (2022), and the story was reworked. Final concept: a lost house cat in an
  automated warehouse, where robots register the nanotech-augmented cat as
  "supervisor" and mirror its movement.
- Asset research: `jadzia` ran two parallel asset searches. Candidates were
  downloaded and inspected in headless Godot (triangle counts, animation clips)
  and licenses were vetted for redistribution in a public repo. Rejected: Fab and
  Unity Store licenses, Sonniss bundles, and game-ripped models mislabelled
  CC-BY on Sketchfab. No free, permissively licensed cat with sleep animations
  exists, so the sleep scenes are posed by hand.
- Human decision, informed by the AI: Chris chose a chunky stylized look (Kenney,
  Quaternius and KayKit, all CC0), preferring a consistent style over a
  realistic cat.
- Implementation: `data` imported the curated assets and began the cat
  controller. `davinci` began the atmosphere pass (in progress).

### 2026-10-04

- Art direction: Chris approved the HD direction ("Mock C": 640x360 view, 32 px
  tiles, night lighting). `davinci` made the palette, the recoloured tile sheet
  and the harmonised background layers; every colour mapping is written out by
  hand in `tools/art/` (no generative art).
- Port: `data` moved the whole game to it: new TileSet, the cat's twelve
  animations through the HD pipeline, the movement tuning scaled by 32/18, the
  FX kit wired in (shockwave, pad, checkpoint, laser beam), the test room
  rebuilt and a slim HUD.
- Verification: `data` wrote two audits that drive the real cat through every
  beat of the test room with scripted input, one in headless Godot
  (`tools/audit/playthrough.gd`) and one in the web export with Playwright
  (`tools/audit/web_playthrough.mjs`). A jump-reach measurement
  (`tools/audit/reach.gd`) sized the pits and walls.
- Room 1: `data` built Warehouse Room 1, the opening level (plain movement only),
  from a level generator (`tools/build_room1.gd`) sized against the measured jump
  reach; the room transition system, a stub Room 2, and the hooks for the goo
  transformation (`TransformSequence`, a timed placeholder). `data` also wrote a
  scripted playthrough of Room 1 in headless Godot
  (`tools/audit/room1_playthrough.gd`) and in the web export
  (`tools/audit/web_room1.mjs`).
