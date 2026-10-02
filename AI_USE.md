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
| Art / 2D tool | TBD (not chosen yet) | TBD |
| 3D asset tool | TBD (not chosen yet) | TBD |
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
| `doctor` | Documentation | `README.md`, `AI_USE.md` |
| `miranda` | Git and GitHub | Repository creation and commits |

Planned (not yet used): `riker` (architecture), `jadzia` (research), `belanna`
(debugging), `tuvok` (testing), `icheb` then `davinci` (UI iteration, then polish).

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
