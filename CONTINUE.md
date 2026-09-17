# Continue here

Paste into a new chat: **"Read CLAUDE.md and CONTINUE.md, then continue."**

## State (2026-09-17, checkpoint 19)
- Phase 2 core sim works and is tested (650 tests). White, Black, Green and **Blue** factions complete.
- Blue done this checkpoint: ObserverDrone (self-target links, `TWelaReadyEntityNearbyComponent` cloak, range aura;
  stealthed/banished units ignore capture points), Atlas (`reCardTimesPlayed` per deck slot -> `reLevel`, extractor
  resolves `if CurrentLevel < N` chains and CreateData locals into `by_level` / `level_expr` values; on-hit chains
  `FireSelfInGroup` + `TThinkImpulseFireComponent`, `ThinksLocal` groups only fire when chained, percentage heals),
  PhaseDrone (teleport warhead, `TriggersAfterDamage` hook, skin-conditional components keep the default branch),
  Inductioner, ShieldDrone (`TBrainFollowComponent`, `Links/ProjectileReflector`: projectiles fly back to their creator
  at 40 % with dtReflected, link owner pays via `CreatorGroup`, `CantBeReflected`), Airdominator, Bombardier
  (`LineFromOwner` splash, wave gun), Aegis (extractor expands `for i := 3 to 6` loops, cone link targeting,
  `TThinkImpulseImmediateComponent`, kill projectiles). The invented ground-only rule (`upRangedGroundOnly`) is gone:
  the engine never reads it, `BothMustHaveAny([upGround, upFlying])` does the work.
- Blue spells: AmmoRefill (chain-only spell groups, `AmountIsPercentage` mana), EnergyRift (buff fight groups may shoot
  enemies: `shard_enemies`), Relocate (two-point ctCoordinate casts, `TWelaTargetConstraintMaxTargetDistanceComponent`,
  zone padding via `SimMap.in_zone_padded`, `saved_targets` + `PassSavedTargetPosition`/`PassOffsetToOwner`, buff
  `teleport_at`/`teleport_to`, `ResolveTier` heal/refill, buildings re-block their footprint through a counted
  pathfinding layer), FactoryReset (`removes_all_buffs`, `reset_resources`, `lifetime_started_at`, `stops_wela`),
  FluxField (`CheckHasResource`, buff `mana_cap_add`), InverseGravity (worked unchanged), OrbitalStrike (buff
  `bomb_script` with `Cooldown(1000).Once` delay, splash timer buffs).
- `game/sim/`: `simulation.gd` (loop, think chain over welas, chained fire groups, auras/links, splash, spells,
  combat hooks, projectiles incl. reflection, buffs, economy, movement, spawners, card play, ammo, tech-ups, lane
  nodes, charms), `wela.gd` (weapon/ability groups parsed from unit and spell components), `buff.gd` (modifier, link
  and spell payload scripts), `commander.gd`, `cards.gd`, `projectile.gd`, `pathfinding.gd`, `lanes.gd`, `sim_map.gd`,
  `build_zone.gd`, `sim_entity.gd` (stat Read chain), `blackboard.gd`, `unit_db.gd` (symbolic group map, level
  resolution), `sim_constants.gd`. Data: `game/data/units.json`, `cards.json`, `modifiers.json`, `maps/*.json` from
  `tools/extract_units.py` and `tools/extract_maps.py`.
- Sandbox `game/main.tscn`: capsules, 12-slot white deck on keys 1-9,0,-,= , red AI plays Black; right-drag pans,
  arrows nudge, wheel zooms; label shows Mana / Essence / tier like the live client. Renderer: Compatibility.
- `docs/factions/*.md`: complete specs for Black, Green, Blue (Blue: `docs/factions/blue.md`). `docs/reference-material.md`:
  live-client screenshots, UI captures, trailer, patch-note archive for phases 3-5.
- `reference/media/` (local, gitignored): the owner's live-client screenshots, `lobby/` (36) and `ingame/` (21).
  Only the owner adds files there; never copy from their Pictures folders.

## Next step (in order, one at a time, test after each)
1. Golems / Crystal Legion (`docs/factions/golems.md`; the source folder is `Scripts/Units/Golems`, `Colorless` holds
   the neutral golem variants): units then spells, each with a test against the doc's numbers. `CrystalPowerSpark`
   now has params `[TeamID, Front]` (extractor fix). Read `docs/reference-material.md` for live-client facts.
2. Then the sandbox should show a full deck including spells (main.gd: `ctEntity` spells need a unit under
   the mouse, Relocate needs two clicks), then phase 3 deck rules (12 slots, 2 colors, 1 epic) and phase 4 HUD.
3. Late phase: audit Crystal Clash Steam patch notes newer than the repo snapshot (2022-01-19) and apply
   balance changes via the extractor (see CLAUDE.md Decisions).

## Rules that bit us
- Run `--import` before `-s tests/run_tests.gd` when new class_name scripts were added.
- Lambdas connected to sim signals must be disconnected in tests; lambdas capture ints by value (use Arrays).
- `alive_entities(-1)` = all teams; team 0 is the neutral team (lane nodes).
- Spell cards are keyed with their `.sps` suffix (`Spells/White/LightPulse.sps`), effects without it.
- Footman Shieldblock absorbs any hit of 10+ damage every 5 s; tests that want to kill a footman use
  `sim._kill()` or a unit without it (Monk). Monks are unarmored and have a 4-energy pool (not "no energy").
- Buff lambdas: counters inside closures must live in a Dictionary/Array (see `buff.gd` group ids).
- Original quirks kept: lanetowers one-shot tier-1 units; legendary cards have 1 charge at league 4;
  a primed lane node keeps charging for the last single team seen until contested.
- The Bash tool mangles backslashes inside heredocs: write patch scripts with the Write tool, then run them.
- Legendary units are invincible + untargetable during their LegendarySpawn lockout (Tyrus 3300 ms, Aegis 1400,
  Atlas 2200): step past it before casting on them or hitting them in tests.
- Passive brains (`_think_passives`) run while frozen/stunned, like the original's FPassiveThinking.
- `locked_until` on a test unit stops its main-weapon thinking: lock only the victims, not the attacker.
- `TWelaHelperActivateTimerComponent` must not decide a group's kind (it creates a SUB wela; the brain sets the kind).
- Inserting a `for` loop between an `if` and its `elif` in buff.gd breaks the parse: keep chains intact.
- The `_blue_spell_sim()` deck: AmmoRefill 0, EnergyRift 1, Relocate 2, FactoryReset 3, FluxField 4, InverseGravity 5,
  OrbitalStrike 6 (free cards, tier 3).
