# Continue here

Paste into a new chat: **"Read CLAUDE.md and CONTINUE.md, then continue."**

## State (2026-09-16, checkpoint 13)
- Phase 2 core sim works and is tested (265 tests). All 12 White units and 6 White spells work, plus
  overheal, projectile splash and the dynamic drop zone. Generic factory spawns
  (`TWelaEffectFactoryComponent`), unit-property target efficiency and multi-target attacks
  (`eiWelaTargetCount` + `TModifierWelaTargetCountComponent`) are wired in `wela.gd`/`simulation.gd`
  but have no tests yet; they get exercised by Black.
- `game/sim/`: `simulation.gd` (loop, think chain over welas, chained fire groups, auras, splash, spells,
  combat hooks, projectiles, buffs, economy, movement, spawners, card play, ammo, tech-ups, lane nodes,
  charms), `wela.gd` (weapon/ability groups parsed from unit and spell components), `buff.gd` (modifier,
  link and spell payload scripts), `commander.gd`, `cards.gd`, `projectile.gd`, `pathfinding.gd`, `lanes.gd`,
  `sim_map.gd`, `build_zone.gd`, `sim_entity.gd` (stat Read chain), `blackboard.gd`, `unit_db.gd`
  (symbolic group map), `sim_constants.gd`. Data: `game/data/units.json`, `cards.json`, `modifiers.json`,
  `maps/*.json` from `tools/extract_units.py` and `tools/extract_maps.py`.
- Sandbox `game/main.tscn`: capsules, 12-slot white deck on keys 1-9,0,-,= , simple red AI. Renderer: Compatibility.
- `docs/factions/black.md`: complete Black faction spec (souls, 12 units, 7 spells, component semantics).
- `reference/media/` (local, gitignored): folder for real-game screenshots/videos the owner drops in.

## Next step (in order, one at a time, test after each)
1. **Black faction** using `docs/factions/black.md`. Implement in this order, each with a test against the
   numbers in the doc:
   a. Souls: every unit death spawns a soul (`GROUP_SOUL`) that flies to a random non-full `upSoulGatherer`
      within 12 (allies preferred); `reMana` = souls. Unit test with VoidSkeleton (cap 1) + dying Footman.
   b. VoidSkeleton Undying (prevent death paying 1 mana, `Undying.dws`), VoidBane cleave (cone splash on
      group 1: `eiWelaAreaOfEffectCone`) + Reaper (+15 max HP per soul: `TAutoBrainOnResourceComponent`)
      + death-rattle soul donation, VoidBowman Grievous Wounds (`BlessingGrievousWounds.dws` -> Bleeding).
   c. Frozen/Banished/Bleeding modifiers (already in modifiers.json; check `buff.gd` handles their
      beacon/immunity groups), VoidWorm frostshot projectile (`TAutoBrainOnDealDamageComponent`), Frostgoyle
      fury, VoidCauldron blast, VoidSlime status mirror (skip the 25 generated groups if too big: note it),
      FrostgoyleFountain (spawn every 4 souls, TimedLife 17 s, building lifetime 90 s), Tyrus, Vecra prison
      and aura, VoidWraith frost nova, VoidAltar.
   d. Spells: Frenzy, Frostspear, Freeze, OnTheEdge, PermaFrost (`TWelaEffectRemoveBeaconComponent`),
      RipOutSoul (percent max HP), ShatterIce.
2. Green, Blue, Golems the same way (spawn a research agent per faction to write `docs/factions/<x>.md`
   first, like Black; the coverage audit snippet is in git history, commit b937743).
3. Then the sandbox should show a full deck including spells (main.gd: `ctEntity` spells need a unit under
   the mouse), then phase 3 deck rules (12 slots, 2 colors, 1 epic) and phase 4 HUD.

## Rules that bit us
- Run `--import` before `-s tests/run_tests.gd` when new class_name scripts were added.
- Lambdas connected to sim signals must be disconnected in tests; lambdas capture ints by value (use Arrays).
- `alive_entities(-1)` = all teams; team 0 is the neutral team (lane nodes).
- Spell cards are keyed with their `.sps` suffix (`Spells/White/LightPulse.sps`), effects without it.
- Footman Shieldblock absorbs any hit of 10+ damage every 5 s; tests that want to kill a footman use
  `sim._kill()` or a unit without it (Monk).
- Buff lambdas: counters inside closures must live in a Dictionary/Array (see `buff.gd` group ids).
- Original quirks kept: lanetowers one-shot tier-1 units; legendary cards have 1 charge at league 4;
  a primed lane node keeps charging for the last single team seen until contested.
