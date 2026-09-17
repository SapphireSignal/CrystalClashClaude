# Continue here

Paste into a new chat: **"Read CLAUDE.md and CONTINUE.md, then continue."**

## State (2026-09-16, checkpoint 6)
- Phase 2 core sim works and is tested (161 tests): `game/sim/` = `simulation.gd` (tick loop, think chain,
  combat, projectiles, economy, movement, spawners/waves, card play, ammo, tech-ups, lane nodes),
  `commander.gd`, `cards.gd`, `projectile.gd`, `pathfinding.gd`, `lanes.gd`, `sim_map.gd`, `build_zone.gd`,
  `sim_entity.gd`, `blackboard.gd`, `unit_db.gd`, `sim_constants.gd`. Data: `game/data/units.json` (units +
  projectiles), `cards.json`, `maps/*.json` (from `tools/extract_units.py`, `tools/extract_maps.py`).
- Sandbox `game/main.tscn`: capsules, 12-slot white deck on keys 1-9,0,-,=, simple red AI. Renderer: Compatibility.

## Next step (in order, one at a time, test after each)
1. **Modifier Read-chain**: port the eventbus "Read" pipeline for `eiWelaDamage`, `eiWelaRange`, `eiCooldown`,
   `eiSpeed`, `eiArmorType`, `eiTakeDamage` so buffs/auras can modify stats. Source: `BaseConflict.Entity.pas`
   eventbus + `EntityComponents.Shared.Wela.pas` `TModifier*Component` (lines 32-221). Then timed buffs
   (`Scripts/Modifiers/*.dws`, e.g. `SummoningSickness.dws`), then auras (`Scripts/Links/*Aura.ets`).
2. **Unit abilities** from the `.ets` server sections (extend the extractor to list component names per group):
   Footman Shieldblock (`TAutoBrainOnTakeDamageComponent`, group 2, absorbs 10 dmg, 5 s cd), Archer
   Relentless (x1.5 dmg vs state effects, x2 vs stunned), deathrattles, Priest heal, etc. Do White first.
3. **Spells** (`Scripts/Spells/White/*.sps` + `.ets`): extend the extractor for `.sps`, `PrepareSpellData`
   (SpellTemplate.dws), target types (`ctCoordinate/ctEntity`), Walkzone constraint, then effects.
4. Splash damage (`eiWelaAreaOfEffect`, `eiWelaSplashfactor`) for lanetower/nexus projectiles.
5. Dynamic drop zone (`dzNexus`/`dzDrop`, `TDynamicZoneRadialEmitterComponent` radius 31.5 around nexus and
   lanetowers of the team) replacing the static `Drop` polygon check.

## Rules that bit us
- Run `--import` before `-s tests/run_tests.gd` when new class_name scripts were added.
- Lambdas connected to sim signals must be disconnected in tests; lambdas capture ints by value (use Arrays).
- `alive_entities(-1)` = all teams; team 0 is the neutral team (lane nodes).
- Template includes carry defaults (`upSpawner`, `eiSpeed`...); the extractor merges them. Keep it that way.
- Original quirks kept: lanetowers one-shot tier-1 units; legendary cards have 1 charge at league 4;
  a primed lane node keeps charging for the last single team seen until another team contests it.
