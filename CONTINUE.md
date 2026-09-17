# Continue here

Paste into a new chat: **"Read CLAUDE.md and CONTINUE.md, then continue."**

## State (2026-09-17, checkpoint 25)
- Phases 1-3 done, 799 tests pass. All five factions, deck rules and per-card league/level are complete
  (see CLAUDE.md Status). Sandbox `game/main.tscn` plays capsules; blue deck on keys 1-9,0,-,= ; red AI plays Black.
- **Phase 4 (HUD) started: research done, no HUD code yet.** `docs/hud.md` is the complete pixel spec read from the
  original `.dui` / `.scss` / view-model (top bar, resource panel, deck panel with tier-locked groups, minimap
  projection, unit info panel, tech panel, announcements). Read it instead of the original again.
- Done this checkpoint:
  - `tools/copy_ui_assets.py`: copies the original HUD images 1:1 into `assets/ui/<path under Graphics/GUI>` (254 files:
    HUD panels, card icons, league/faction icons, selection decals) and Proza Libre fonts into `assets/fonts/`.
    Card icon `.tga`s are 512x256 mip atlases: use an `AtlasTexture` region (0,0,256,256).
  - `tools/extract_lang.py`: `Lang/*.csv` -> `game/data/lang/en.json` (keys lowercased, `§key` refs resolved, HTML
    stripped). Keys: `card_name_<ident>[_drop|_spawner]`, `unitability_name_<ability>`, `armortype_<atx>_caption`,
    `core_*` HUD strings, `card_description_<spell>`.
  - `tools/extract_units.py` now records `abilities` per script (names of `TTooltipUnitAbilityComponent`s, inherited),
    e.g. Footman `["ShieldBlock"]`, for the unit panel's keyword line.
  - `docs/assets.md` rows GUI / Fonts / Lang updated.

## Next step (in order, one at a time, run the game after each)
1. Build the HUD from `docs/hud.md` in `game/ui/` (pure code Controls on the `HUD` CanvasLayer of `main.tscn`,
   `project.godot` stretch `canvas_items` at 1920x1080): `lang.gd` (key lookup + card name rule), `hud_style.gd`
   (fonts, textures, card icon/frame atlases, team colours, `IntToTime`, roman numerals), `game_info_bar.gd`,
   `resource_panel.gd`, `deck_panel.gd` (slot views, tier plates, click -> play, spawner jump), `minimap.gd`
   (`WorldToMiniMap` port, entity icons, camera view quad, menu button), `info_panel.gd` (click-select a unit,
   `Selection.png` ground decal), `hud.gd` (owner of all panels, updates from the sim each frame). Replace the
   sandbox label in `main.gd`. Then compare against `reference/media/ingame/*.webp` with a screenshot and tune.
2. Card hint on hover (`MainMenu/Shared/Card/CardHUD.dui` + `shared_card.scss`), announcements (warm-up
   countdown), in-world health bars, floating combat text.
3. Later: audit the Steam patch notes newer than 2022-01-19 (CLAUDE.md Decisions) and apply via the extractor.

## Rules that bit us
- Run `--import` before `-s tests/run_tests.gd` when new class_name scripts or assets were added.
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
