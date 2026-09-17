# Continue here

Paste into a new chat: **"Read CLAUDE.md and CONTINUE.md, then continue."**

## State (2026-09-16, checkpoint 5)
- Phase 2 core sim works and is tested (131 tests): `game/sim/` = `simulation.gd` (tick loop, think chain,
  combat, economy, movement, spawners/waves, card play), `commander.gd` (resources, deck slots, charges,
  auto income upgrade), `cards.gd` (registry + cost/charge formulas), `pathfinding.gd`, `lanes.gd`,
  `sim_map.gd`, `build_zone.gd`, `sim_entity.gd`, `blackboard.gd`, `unit_db.gd`, `sim_constants.gd`.
  Data: `game/data/units.json`, `cards.json`, `maps/*.json` (from `tools/extract_units.py`, `tools/extract_maps.py`).
- Sandbox `game/main.tscn`: capsules, 12-slot white deck on keys 1-9,0,-,=, simple red AI.

## Next step (in order, one at a time, test after each)
1. **Projectiles**: ranged units currently hit instantly. Port `Scripts/Projectiles/*` + the projectile
   components (`GameServer/*.Welas.pas` TWelaEffectProjectileComponent, `Shared.pas` projectile movement):
   speed, homing, hit on arrival, damage applied on impact.
2. **Nexus tech replacement** (`NexusLevel1` -> `NexusLevel2/3` at tech events, keep taken damage) and the
   nexus/lanetower weapons with ammo (`reWelaCharge`, recharge `eiCooldown[6]`), lanetower showdown shots.
3. **Modifier Read-chain** (buffs/auras/`Scripts/Modifiers`, `Scripts/Links`) then unit abilities
   (Footman Shieldblock, Archer Relentless...), then spells (`.sps`: extend the extractor).
4. Dynamic drop zone (`dzNexus`/`dzDrop`, expands with lane pushes) and lane nodes (`LaneNode.ets`).

## Rules that bit us
- Run `--import` before `-s tests/run_tests.gd` when new class_name scripts were added.
- Lambdas connected to sim signals must be disconnected in tests (reference cycle = leak warning).
- Template includes carry defaults (`upSpawner`, `eiSpeed`...); the extractor merges them. Keep it that way.
- Original quirks kept: lanetowers one-shot tier-1 units; legendary cards have 1 charge at league 4.
