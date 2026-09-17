# Continue here

Paste into a new chat: **"Read CLAUDE.md and CONTINUE.md, then continue."**

## State (2026-09-17, checkpoint 22)
- Phase 2 core sim works and is tested (757 tests). **All five factions are complete**: White, Black, Green, Blue and
  Golems / Crystal Legion (`docs/factions/*.md` are the specs; Golems: `docs/factions/golems.md`).
- Golems done this checkpoint: BigMeleeGolem Splinter (`checks_damage_threshold` on on-hit chains, `chain_to_ground` +
  `ground_jitter` from `RedirectToGround.RandomizeGroundtarget`, `SimMap.clamp_to_zone`, `Projectile.spawn_pattern` /
  `produced_scripts`: a projectile aimed at a point (`target_id = -1`) spawns its factory unit on landing),
  SmallCasterGolem Crystal Speed (`build_check_group`: one new link per 3 s, `max_new_targets`, link entities carrying
  `TWarheadLinkApplyScriptComponent` payloads), BigCasterGolem beam (`Buff.link_charge*`: +1 per 3 s to 3, damage
  x `link_damage_mult` x charge), SiegeGolem (`fire_at_self` = ChangeTargetToMyself, `preemptive` fight groups stop
  the think chain while waiting, non-blocking plain self-target brains fire and let the chain go on, `ready_cost`:
  a cost without `TWelaReadyCostComponent` is only paid, `charge_consumes_all` on the main weapon / entity pool,
  `reWelaCharge` spotty gain, `CheckNotFull(reWelaCharge)`).
- Golem spells: Petrify (`Buff.hot_type` carries dtOverheal), StoneCircle (`_remove_silently` breaks auras and
  `_think_passives` skips dead entities: a field that dies resolving its fire must not re-link), Earthquake
  (`timer_ready` = `TimerIsReady`: first timer think at creation), Cataclysm (`CardDef.epic`: ready at the gold cap,
  pays all gold as wood, no charges, `_in_nexus_zone` = Drop polygon within the nexus' eiWelaRange[3];
  `SimEntity.stage` + `range_scales_with_stage`: 6 + 0.5 x first commander's tier), EchoesOfTheFuture
  (`override_target_to_owner`: spell applies to the Commander: `properties` with expiry block the recast,
  `start_income_loan` / `pay_income(now)` = x2 for 30 s then x0 for 30 s; `CardDef.charge_cooldown_mult` x3).
- `game/sim/`: `simulation.gd` (loop, think chain over welas, chained fire groups, auras/links, splash, spells,
  combat hooks, projectiles incl. reflection and ground landings, buffs, economy, movement, spawners, card play, ammo,
  tech-ups, lane nodes, charms), `wela.gd`, `buff.gd`, `commander.gd`, `cards.gd`, `projectile.gd`, `pathfinding.gd`,
  `lanes.gd`, `sim_map.gd`, `build_zone.gd`, `sim_entity.gd`, `blackboard.gd`, `unit_db.gd`, `sim_constants.gd`.
  Data: `game/data/units.json`, `cards.json`, `modifiers.json`, `maps/*.json` from `tools/extract_units.py` and
  `tools/extract_maps.py`.
- Sandbox `game/main.tscn`: capsules, 12-slot white deck on keys 1-9,0,-,= , red AI plays Black; right-drag pans,
  arrows nudge, wheel zooms; label shows Mana / Essence / tier like the live client. Renderer: Compatibility.
- `docs/reference-material.md`: live-client screenshots, UI captures, trailer, patch-note archive for phases 3-5.
- `reference/media/` (local, gitignored): the owner's live-client screenshots, `lobby/` (36) and `ingame/` (21).
  Only the owner adds files there; never copy from their Pictures folders.

- Sandbox (`game/main.gd`) now plays spells: blue deck = 8 White units + LightPulse, ShieldsUp, SolarFlare (unit under
  the mouse), HailOfArrows on keys 9, 0, -, =; red AI rotates through a Black deck incl. Frenzy, Freeze, Shatter Ice
  (spells target a random unit of the side the card is for, epics the own nexus, two-point spells press the key twice).

## Next step (in order, one at a time, test after each)
1. Phase 3 deck rules (12 slots, 2 colors, 1 epic; `BaseConflict.Constants.Cards.pas` + the deck validation in the
   original client) and the commander/deck data model. Read `docs/reference-material.md` for live-client facts.
2. Phase 4 HUD (card bar, resources, tier button, minimap) replicating the live-client screenshots in `reference/media/`.
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
- Timed checks in tests must allow the 32 ms tick: a "5 s later" wave lands at 5024 ms, so check at 4800 not 4900.
- Test victims die fast against ramping/splash damage: give them `max_health = 100000` and measure deltas.
- Modifier script keys: `Stun`, `Frozen`, `Petrified` (no `Modifiers/` prefix), links `Links/Spellshield`.
- The `_golems_spell_sim()` deck: Cataclysm 0, EchoesOfTheFuture 1, Petrify 2, StoneCircle 3, Earthquake 4
  (free cards, tier 3); `_blue_spell_sim()`: AmmoRefill 0, EnergyRift 1, Relocate 2, FactoryReset 3, FluxField 4,
  InverseGravity 5, OrbitalStrike 6.
