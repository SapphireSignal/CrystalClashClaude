# Continue here

Paste into a new chat: **"Read CLAUDE.md and CONTINUE.md, then continue."**

## State (2026-09-16, checkpoint 15)
- Phase 2 core sim works and is tested (370 tests). All 12 White units and 6 White spells work, plus
  overheal, projectile splash and the dynamic drop zone.
- Black steps 1a+1b done: souls (`_release_soul`, `gain_mana`, `Wela.Kind.ON_RESOURCE`), VoidSkeleton
  Undying (`Wela.Kind.PREVENT_DEATH`, buff `instant_heal`/`kills_on_expiry`), VoidBane cone cleave
  (`eiWelaAreaOfEffectCone` in `_fire_splash`), Reaper (`changes_max`), soul-donor deathrattle
  (`_on_before_death` with counts/allies/repetition), VoidBowman Grievous Wounds (buff `on_hit_*`,
  Bleeding `charges`, `taken_heal_mult`, percent DoT). Extractor now maps template `GROUP_*` symbols
  (GROUP_SOUL=11) and parses `function ApplyEffect` modifier bodies.
- Black step 1c done (all 12 units): buff `late_properties` (immunity groups), projectile `on_hit_script`,
  `Wela.chain_first`, `Kind.SELF_PASSIVE` + `_think_passives` (passive brains think while frozen),
  `produced_scripts`, `lifetime_ms`, `projectile_reverse`, `activates_groups`/`active`, `removes_groups`,
  entity `group_properties`, link entities (`Links/*.ets` in units.json, `Buff.link_damage`), `mirror_pairs`,
  `on_deal_groups`, extractor `inline_local_procedures` (VoidSlime) and `fix_pattern_case`.
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
1. **Black faction** using `docs/factions/black.md` (units a-c are done):
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
- The Bash tool mangles backslashes inside heredocs: write patch scripts with the Write tool, then run them.
- Legendary units are invincible + untargetable during their LegendarySpawn lockout (Tyrus 3300 ms).
- Passive brains (`_think_passives`) run while frozen/stunned, like the original's FPassiveThinking.
