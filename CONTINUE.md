# Continue here

Paste into a new chat: **"Read CLAUDE.md and CONTINUE.md, then continue."**

## State (2026-09-16, checkpoint 7)
- Phase 2 core sim works and is tested (180 tests). `game/sim/`: `simulation.gd` (loop, think chain over
  welas, combat hooks, projectiles, buffs, economy, movement, spawners, card play, ammo, tech-ups, lane
  nodes), `wela.gd` (weapon/ability groups parsed from unit components), `buff.gd` (modifier scripts),
  `commander.gd`, `cards.gd`, `projectile.gd`, `pathfinding.gd`, `lanes.gd`, `sim_map.gd`, `build_zone.gd`,
  `sim_entity.gd` (stat Read chain: `damage()`, `speed()`, `armor()`, `cooldown()`, `has()`), `blackboard.gd`,
  `unit_db.gd`, `sim_constants.gd`. Data: `game/data/units.json` (values + server components, compact JSON),
  `cards.json`, `modifiers.json`, `maps/*.json`, all from `tools/extract_units.py` / `tools/extract_maps.py`.
- Sandbox `game/main.tscn`: capsules, 12-slot white deck on keys 1-9,0,-,=, simple red AI. Renderer: Compatibility.

## Next step (in order, one at a time, test after each)
1. **Coverage audit of White faction components**: for each `Units/White/*.ets` list component classes that
   `wela.gd` / `buff.gd` do not yet interpret (write a tiny Python or GDScript report), then implement the
   most common ones: `TWelaEffectFireComponent` (chain-fire another group), `TAutoBrainOnDeathComponent`
   with `TWelaEffectFactoryComponent` (spawn on death), `TWelaTargetConstraintCompareUnitPropertyComponent`
   (BothMustHaveAny ground/flying), `TWelaReadyEnemiesNearbyComponent`, links/auras (`eiLinkPattern`,
   `Scripts/Links/*Aura.ets`: apply a modifier script to allies in range while alive, e.g. Suntower Homeland).
2. **Spells** (`Scripts/Spells/White/*.sps` + `.ets`): extend the extractor for `.sps` (`PrepareSpellData`,
   `eiAbilityTargetType`, cost -20), then spell effect entities (LightPulse: stun 8 in radius 2, blind 14 in 5).
3. Splash damage (`eiWelaAreaOfEffect`, `eiWelaSplashfactor`) for lanetower/nexus projectiles; overheal.
4. Dynamic drop zone (`dzNexus`/`dzDrop`, radius 31.5 around own nexus and lanetowers) replacing the static
   `Drop` polygon check.
5. Then Black, Green, Blue, Golems factions the same way, then phase 3 deck rules and phase 4 HUD.

## Rules that bit us
- Run `--import` before `-s tests/run_tests.gd` when new class_name scripts were added.
- Lambdas connected to sim signals must be disconnected in tests; lambdas capture ints by value (use Arrays
  or Dictionaries for counters, also inside `buff.gd`-style closures).
- `alive_entities(-1)` = all teams; team 0 is the neutral team (lane nodes).
- Footman Shieldblock absorbs any hit of 10+ damage every 5 s: tests that want to kill a footman use
  `sim._kill()` or a unit without it (Monk).
- Original quirks kept: lanetowers one-shot tier-1 units; legendary cards have 1 charge at league 4;
  a primed lane node keeps charging for the last single team seen until contested.
