# Continue here

Paste into a new chat: **"Read CLAUDE.md and CONTINUE.md, then continue."**

## State (2026-09-16, checkpoint 11)
- Phase 2 core sim works and is tested (249 tests). All 12 White units and 6 White spells work. `game/sim/`: `simulation.gd` (loop, think chain over
  welas, chained fire groups, auras, splash, spells, combat hooks, projectiles, buffs, economy, movement,
  spawners, card play, ammo, tech-ups, lane nodes), `wela.gd` (weapon/ability groups parsed from unit and
  spell components; header lists covered classes), `buff.gd` (modifier + link payload scripts),
  `commander.gd`, `cards.gd`, `projectile.gd`, `pathfinding.gd`, `lanes.gd`, `sim_map.gd`, `build_zone.gd`,
  `sim_entity.gd` (stat Read chain), `blackboard.gd`, `unit_db.gd` (symbolic group map), `sim_constants.gd`.
  Data: `game/data/units.json` (units, projectiles, spell effects, `.sps` cards), `cards.json`,
  `modifiers.json` (Modifiers, Links, Spells payloads), `maps/*.json`; all from `tools/extract_units.py`
  and `tools/extract_maps.py`.
- Sandbox `game/main.tscn`: capsules, 12-slot white deck on keys 1-9,0,-,=, simple red AI. Renderer: Compatibility.

## Next step (in order, one at a time, test after each)
1. **Overheal** (`reOverheal`, `OVERHEAL_LIMIT_FACTOR 2.0`, `dtOverheal` heals above max, decays?) in `heal()`.
2. **Splash on projectiles** (`eiWelaAreaOfEffect` on HeavyGunner infused shot, PatronSaint, lanetower
   projectiles): pass the projectile script's AoE + `eiWelaSplashfactor` into `Projectile` and splash on impact.
3. **Dynamic drop zone** (`dzNexus`/`dzDrop`, radius 31.5 around own nexus and own lanetowers) replacing the
   static `Drop` polygon check in `play_card`.
4. Then Black, Green, Blue, Golems: run the component coverage audit (see git history for the Python
   snippet), implement missing component classes faction by faction, with tests per unit.
5. Then the sandbox should show the whole White deck including spells (main.gd: `ctEntity` spells need a
   unit under the mouse).

## Rules that bit us
- Run `--import` before `-s tests/run_tests.gd` when new class_name scripts were added.
- Lambdas connected to sim signals must be disconnected in tests; lambdas capture ints by value (use Arrays).
- `alive_entities(-1)` = all teams; team 0 is the neutral team (lane nodes).
- Spell cards are keyed with their `.sps` suffix (`Spells/White/LightPulse.sps`), effects without it.
- Footman Shieldblock absorbs any hit of 10+ damage every 5 s; tests that want to kill a footman use
  `sim._kill()` or a unit without it (Monk).
- Original quirks kept: lanetowers one-shot tier-1 units; legendary cards have 1 charge at league 4;
  a primed lane node keeps charging for the last single team seen until contested.
