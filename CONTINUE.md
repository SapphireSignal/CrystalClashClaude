# Continue here

Paste into a new chat: **"Read CLAUDE.md and CONTINUE.md, then continue."**

## State (2026-09-17, checkpoint 26)
- Phases 1-3 done, 799 tests pass. Sandbox `game/main.tscn`: blue deck on keys 1-9,0,-,= or by clicking a card
  (drops/spells then need a left click on the ground, spawners go to the next free field); red AI plays Black.
- **Phase 4 (HUD): step 1 done.** `game/ui/` holds the code-built HUD from `docs/hud.md`: top bar (clock, nexus
  bars), resource panel (rows, income fill, tier book + tech timer), deck panel (stage groups, locked tier plates
  with countdown, ready glow, darken, radial cooldown + seconds, charge/hotkey badges, spawner jump button),
  minimap (WorldToMiniMap port with the original angle/scale, icons by kind, camera ground quad, menu button
  without a menu yet), unit info panel on left click (portrait + league icon, name, health/mana or ammo, DPS,
  armor caption, ability keywords; spawners show the produced unit), `Selection.png` ground decal.
  `tools/screenshot.gd` runs the game and saves `.tmp/shot_<s>.png` (`-- 30 31 select` selects a unit first).
- Verified by screenshot against `reference/media/ingame/*.webp` (those use the client's small layout; ours is
  the normal 1920x1080 layout, so sizes differ but the structure matches).

## Next step (in order, one at a time, run the game after each)
1. Card hint on hover (`MainMenu/Shared/Card/CardHUD.dui` + `shared_card.scss`, 334 wide, 260 px above the
   bottom): card name, cost, tier, short description (`card_short_description_<ident>`), ability names.
2. Announcements (`AnnouncementBackground.png` 1189x206, 150 px from the top): warm-up countdown / "Game is
   about to begin" (`core_game_commencing`), stage 2/3 and showdown titles (`core_announcement_title_*`).
3. In-world health bars over units (`Visuals.pas` `THealthbarComponent`: quads above the unit, team colour,
   segment ticks) and floating combat text.
4. **Settings menu (the gear button on the minimap): do NOT build it yet.** The owner will add screenshots of the
   live client's settings screens to `reference/media/` first; build it only after they exist.
5. Later: audit the Steam patch notes newer than 2022-01-19 (CLAUDE.md Decisions) and apply via the extractor.

## Rules that bit us
- Run `--import` before `-s tests/run_tests.gd` when new class_name scripts or assets were added.
- `TextureRect`: set `expand_mode = EXPAND_IGNORE_SIZE` **before** `texture`/`size`, else the texture's
  minimum size sticks and the node stays 256 px (use `HudStyle.picture`).
- Card icon file names differ in case from script names (`BlackVoidbane.tga` vs `VoidBane`): `HudStyle.card_atlas`
  matches the folder listing case-insensitively; never `load()` those paths directly.
- Card frames (`Card_<Color>.tga`) are opaque: draw the frame first, the round icon on top.
- Children of a Control draw above the Control's own `_draw`: minimap icons go on an overlay child.
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
- The owner's in-game screenshots use the client's *small* HUD layout (window < 1710 px wide); our 1920x1080
  uses the normal sizes in `docs/hud.md`. Lang keys are case-insensitive (stored lowercase).
