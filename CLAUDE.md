# Crystal Clash — Godot Port

## Mission
Recreate **Crystal Clash** (originally *Rise of Legions*, by Broken Games, Berlin) in **Godot 4** as a faithful replica.
The original is a Windows-only Delphi game the developers can no longer maintain. They gave the owner of this
project explicit permission to use everything: all assets, the public repos, and anything found online.

Original source (public, use as the ground-truth spec):
- Game client + server: https://github.com/BrokenGamesUG/rise-of-legions
- Their custom engine: https://github.com/BrokenGamesUG/delphi3d-engine
- Steam (Crystal Clash, app 748940): https://store.steampowered.com/app/748940

## Your role
Act as two people at once:
1. A **senior Godot 4 developer** who specializes in RTS / tug-of-war / lane strategy games.
2. A **former Crystal Clash developer** who knows the original codebase inside out. Read their source to learn
   *exactly* how things work (unit stats, timers, formulas, lane logic, card/deck rules, matchmaking flow)
   and reproduce it faithfully. Do not invent mechanics. When the source has a number, use that number.

## Approach: port by re-implementation
- Delphi cannot be auto-converted to Godot. Rebuild system by system, using the original source as the spec.
- Order of work: (1) read + document the original architecture, (2) core simulation (lanes, units, spawning,
  combat, economy), (3) cards/decks/factions, (4) UI/HUD, (5) assets/VFX/audio, (6) multiplayer, (7) polish.
- Convert assets from the original formats where possible; write conversion scripts and keep them in `tools/`.
  Only redo an asset by hand when conversion is genuinely impossible, and note it in `docs/assets.md`.
- Keep a running `docs/original-architecture.md` describing how the Delphi version does each system, with
  file/line references into the original repo. This is the shared memory for the whole port.

## Workflow
- The owner wants to sit back and watch. Do not ask questions unless truly stuck. Make reasonable decisions,
  record them under **Decisions** below, and never re-ask them.
- Nothing global. Only edit files inside this project folder.
- Build in small working steps. Run the game after each step. Fix anything broken before moving on.
- Keep this file short and current: engine, structure, how to run, decisions. Don't bloat it.

## Tools & installs
- You may install any tool the project needs (Godot 4, Git, Python, Blender, etc.). Prefer `winget`.
- **Check before installing.** Look for an existing install first (on PATH, in Program Files, via `winget list`,
  Steam library, etc.) and reuse it. Never reinstall or upgrade something already present without being asked.
- Record every tool and its located path/version under **Decisions** so it is never searched for again.

## Errors
- Exploratory / probing commands (checking whether files, tools, or settings exist) must NOT return a
  non-zero exit when the item is simply missing. No red "failed" blocks for absent things.
- Real failures (builds, tests, crashes, import errors) must fail loudly and visibly. Never hide them.
- Always use absolute paths in shell commands. Never rely on the shell's current directory, and prefer the
  dedicated file read/edit tools over shell edits.

## Context efficiency
- Search or read a section instead of whole large files. Summarize logs; never paste big dumps into chat.
- Use subagents for broad research / repo reading / reviews and report only conclusions.
- Don't re-verify anything already recorded in this file or in `docs/`.
- Keep replies short. One line of progress narration at most.

## Tech decisions (fill in before the first line of game code, then don't re-ask)
- Godot version: **4.7.1 stable** at `D:\Godot\Godot_v4.7.1-stable_win64_console.exe` (already installed, reused)
- Language: GDScript (C# only if a system genuinely needs it; record why)
- Simulation: fixed tick rate **decoupled from render**. Match the original's tick rate if the source defines
  one; otherwise 30 Hz for RTS determinism. Simulation must be deterministic (needed for multiplayer + replays).
- Target platform: Windows desktop (primary). Renderer: Forward+.
- Folder structure:
  - `game/` — scenes, scripts, resources (`sim/`, `units/`, `cards/`, `ui/`, `maps/`, `net/`)
  - `assets/` — converted art, audio, VFX
  - `tools/` — asset conversion + data extraction scripts
  - `docs/` — original-architecture notes, asset status, design notes
  - `tests/` — GUT or gdUnit tests for the simulation
- How to run: `D:\Godot\Godot_v4.7.1-stable_win64_console.exe --path D:\Games\CrystalClashClaude --log-file D:\Games\CrystalClashClaude\.tmp\godot.log`
  (always pass an absolute `--log-file`; the default user:// log path caused access-violation dialogs on this PC).
  Headless tests: same command plus `--headless -s tests/run_tests.gd`.

## Code quality
- Simple readable code over clever code. Data-driven design: unit/card stats live in Resources, not in code.
- No unused files, libraries, placeholder scenes, or leftover debug code.
- Tests for simulation logic (damage, spawning, lane movement, economy). UI needs no tests.

## Decisions
- 2026-09-16 Tools: Git 2.55 (PATH), Python 3.14.6 (`python` on PATH), Godot 4.7.1 at `D:\Godot\`. Blender: not yet located.
- 2026-09-16 `reference/` holds read-only clones of the two original repos (gitignored, `.gdignore`). Never edit.
- 2026-09-16 Codex's earlier attempt in `D:\Games\CrystalClash` is read-only. Lesson: it built launcher/accounts/shop
  and never combat. We build combat first. Reusable there: `game/data/reference_cards.json` (139 cards extracted from
  the original), `tools/build_reference_catalog.ps1`. We re-extract from `reference/` ourselves instead.
- 2026-09-16 **Fidelity rule**: everything the player sees or feels is a 1:1 replica (stats, timers, formulas, units,
  animations, maps, HUD layout, sounds). Engineering underneath may improve only where invisible to gameplay.
  Upgrades/new features come only after the game is fully playable as a replica.
- 2026-09-16 Simulation: fixed **32 ms** tick (the original's TARGET_FRAMETIME), seeded per-match RNG, integer
  milliseconds for all timers (original used variable-dt frames and unseeded random; player-invisible change).
  Game tick 1000 ms, warm-up 10000 ms as original. Server-authoritative + event replication like original.
- 2026-09-16 Performance is a priority (original had poor FPS). Forward+ renderer, pooled units, no per-frame
  allocations in sim. In-game settings menu kept simple.
- 2026-09-16 Sim is pure GDScript classes (no Nodes) in `game/sim/`; rendering nodes mirror sim state.
  Unit/card data: `game/data/units.json` + `cards.json`, generated by `python tools/extract_units.py` from the
  original `.ets` scripts and card registry. Never hand-edit; fix the extractor instead.
- 2026-09-16 Tests: own tiny runner `tests/run_tests.gd` (no GUT/gdUnit install needed). Run after `--import`:
  `godot --headless --path <proj> -s tests/run_tests.gd --log-file <proj>/.tmp/godot.log`.
- 2026-09-16 Team ids as in the scenario scripts: Blue = 1 at -x, Red = 2 at +x. Zones in map files are not
  team-suffixed (`Walkzone`, `Drop`, `Camera`, `Spell1`, `Spell2`). `RVector2.nXY` negates X only.
- 2026-09-16 Checkpoint routine: tests green, game runs, CLAUDE.md Status updated, `CONTINUE.md` rewritten
  (the prompt to paste into a new chat), commit + push.
- 2026-09-16 Git identity in this repo is `SapphireSignal` (never the owner's personal name/email). Remote:
  github.com/SapphireSignal/CrystalClashClaude. Commit + push at each working checkpoint.

## Status
Phase 1 done (docs written). Phase 2 in progress: `game/sim/` has fixed-tick Simulation, Blackboard stats from
`units.json` (233 unit scripts, league arrays, inheritance), armor formula, attack timing, nearest-target
picking, economy tick with gold-cap overflow to wood, tech events, nexus death = loss, map zones from
`game/data/maps/*.json`, original lane waypoints, A* tile pathfinding with space-time reservations and
path following (TMovementComponent port), base spawning (nexus + lanetowers). 61 tests pass.
`game/main.tscn` is a sandbox with capsule units (keys 1-4 drop squads). See `CONTINUE.md` for the next step.
