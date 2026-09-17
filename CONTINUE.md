# Continue here

Paste into a new chat: **"Read CLAUDE.md and CONTINUE.md, then continue."**

## State (2026-09-17, checkpoint 31)
- Phases 1-3 done, 799 tests pass. Sandbox `game/main.tscn`: blue deck on keys 1-9,0,-,= or by clicking a card
  (drops/spells then need a left click on the ground, spawners go to the next free field); red AI plays Black.
- **Phase 4 (HUD): step 1 done.** `game/ui/` holds the code-built HUD from `docs/hud.md`: top bar (clock, nexus
  bars), resource panel (rows, income fill, tier book + tech timer), deck panel (stage groups, locked tier plates
  with countdown, ready glow, darken, radial cooldown + seconds, charge/hotkey badges, spawner jump button),
  minimap (WorldToMiniMap port with the original angle/scale, icons by kind, camera ground quad, menu button
  without a menu yet), unit info panel on left click (portrait + league icon, name, health/mana or ammo, DPS,
  armor caption, ability keywords; spawners show the produced unit), `Selection.png` ground decal.
  `tools/screenshot.gd` runs the game and saves `.tmp/shot_<s>.png` (`-- 30 31 select` selects a unit first,
  `hover=N` shows slot N's card hint at the first shot; a shot one second later shows the ability box).
- **Step 2 + 3 done (checkpoint 27):** `card_hint.gd` (CardHUD replica: shadow, frame/icon/league/level, name,
  skill list or spell text with `%(key)` variables, DPS/health boxes, price tag + tech roman, ability box after
  1 s), `announcements.gd` (warm-up countdown, stage 1/2/3, showdown), `unit_bars.gd` (health bars while damaged
  or Alt, overheal, integer chunk bars for mana/ammo, progress bars). The extractor now records `ability_details`
  and `unit_bars`. The original has no floating combat text (not built). `docs/hud.md` updated.
- **Final screen done (checkpoint 28):** `final_screen.gd` shows Victory/Defeat on `banner.png` 4 s after
  `team_lost` (TIME_OFFSET_ENDSCREEN), Continue or 11 s (TIME_TO_FINISH_GAME) emits `Hud.match_left`; the
  sandbox reloads the scene. Timers use the wall clock because the sim stops stepping once finished.
  `tools/screenshot.gd -- 3 9 finish` kills the red nexus at the first shot. Phase 4 (HUD) is complete except
  the settings menu (blocked, see below), chat, scoreboard and pings (multiplayer).
- Verified by screenshot against `reference/media/ingame/*.webp` (those use the client's small layout; ours is
  the normal 1920x1080 layout, so sizes differ but the structure matches).

- **Phase 5 started (checkpoint 29): unit models.** `tools/copy_unit_assets.py` copies `Graphics/Units/**` (FBX,
  TGA, PNG, TMesh xml) to `assets/units/` and writes `game/data/models.json` (UnitScaleFactor per FBX). The extractor
  records `visuals` per script (meshes with path/groups/animation frame ranges/bind zones/flags, `model_sizes` per
  wela group, merged through inheritance). `game/units/unit_model.gd` instantiates the imported FBX, assigns the
  diffuse material, applies the original scale (`docs/assets.md`), cuts stand/walk/attack clips at 30 fps and plays
  them from the sim state (walk while moving, attack when `fire_at` changes). `main.gd` uses it, capsules remain for
  entities without visuals (lane nodes, effects). Verified with `tools/screenshot.gd -- 30 31 zoom=unit` and the
  debug view `.tmp/model_view.gd` (not committed).
- Research results (subagent, verified): FBX loaded via assimp in raw units, `.msh` = cache; frames -> ms at 30 fps
  (`Engine.Mesh.pas:2697`); `SIZE_FACTOR_3DSMAX = 2/125`; Material.tga = (A shading reduction, R spec intensity,
  G spec power, B tint); team colour via a separate mask + HSV hue shift (`TeamColoring.fx`) or `BindTextureToTeam`
  textures per team (Nexus: `NexusDiffuse.tga` team 1, `NexusDiffuse2.tga` team 2); maps are XML (`.ter` 513x513
  zlib+base64 heights with `FScale` 300/50/300, `.veg` mesh scatter list, `.wat` water planes, `.lig` lights,
  `.bcm` zones, `.bcc` decorations); `.pfx` XML particle patterns; FMOD banks + `Sound/Banks/GUIDs.txt`.

- **Checkpoint 30: exact meshes.** Godot's FBX import lost the assimp pivot animations (nexus crystal underground),
  so `tools/msh.py` reads the engine's `.msh` caches and `tools/msh_to_gltf.py --all` writes `assets/units/**/*.glb`
  (174 meshes, pivots collapsed, static nodes as exact matrices, winding reversed back). Verified against the
  engine's skinning math in Python (`tools/msh.py` `skinned_positions`) and visually (nexus base + blue crystal,
  footman, Void Bane). FBX files are no longer copied. `BindTextureToTeam` -> `team_textures` per mesh, applied
  by `UnitModel.create(unit_id, displayed_team)`. Lane nodes have no mesh (particles only) and get no view.

- **Checkpoint 31: the original maps.** `tools/convert_map.py <Map>` writes `assets/maps/<Map>/terrain.glb` +
  chunk textures + `map.json` (water, lights, 3428/2425 vegetation instances, 47/23 decorations) and copies
  `assets/environment/**` (meshes via `tools/msh_to_gltf.py --environment`). `game/maps/map_view.gd` builds
  terrain, a flat water plane, the map lights/ambient, MultiMesh vegetation and decoration meshes; `main.tscn`
  lost its flat ground and sun. The sandbox (Single map) now looks like the reference screenshots.

## Next step (in order, one at a time, run the game after each)
1. Map polish: (a) compare `tools/screenshot.gd` shots with `reference/media/ingame` at the same camera spot and
   tune light energies / ambient (the lane looks washed out); (b) water: port the look roughly (colour, wave
   texture `Maps/Classic/WaterTexture.tga`, transparency) as a shader; (c) terrain `Material.png` (specular) and
   the grass vegetation entries (`.veg` items without `Meshes`, `TVegetationGrass`?); (d) verify the Delphi
   `Random` replica against the original (palm variants/rotations) if a screenshot shows a mismatch.
2. Models polish: (a) walk clip speed per the original formula (`Visuals.pas:3352`, IgnoreScalingForAnimations
   variant at 3355); (b) glow textures (`GlowTexture`, team glow) as emission; (c) `Effects/Meshes` spell props and
   the Environment/Gameplay `.msh` (13 + 2) once the map needs them; (d) the 18 "Basis must be normalized" import
   errors: find which glb nodes have zero scale (probably `_Scaling` pivots folded into static matrices are fine;
   check animated ones) - cosmetic unless a model looks wrong.
3. Particles (`.pfx`) and sounds (FMOD banks: need a bank extractor) later. Find the original mesh/animation formats under `reference/rise-of-legions/`
   and the loaders in `reference/delphi3d-engine/`, textures (`.tga`/`.dds`), particles `.pfx`, FMOD sound banks.
   Write `docs/assets.md` rows per format with a conversion plan, then `tools/convert_*.py` for meshes first
   (Footman), swap the capsule in `main.gd` for the real model, then the maps.
2. **Settings menu (the gear button on the minimap): do NOT build it yet.** The owner will add screenshots of the
   live client's settings screens to `reference/media/` first; build it only after they exist.
3. Later: audit the Steam patch notes newer than 2022-01-19 (CLAUDE.md Decisions) and apply via the extractor.

## Rules that bit us
- Run `--import` before `-s tests/run_tests.gd` when new class_name scripts or assets were added.
- `TextureRect`: set `expand_mode = EXPAND_IGNORE_SIZE` **before** `texture`/`size`, else the texture's
  minimum size sticks and the node stays 256 px (use `HudStyle.picture`).
- Card icon file names differ in case from script names (`BlackVoidbane.tga` vs `VoidBane`): `HudStyle.card_atlas`
  matches the folder listing case-insensitively; never `load()` those paths directly.
- Card frames (`Card_<Color>.tga`) are opaque: draw the frame first, the round icon on top.
- Children of a Control draw above the Control's own `_draw`: minimap icons go on an overlay child.
- A screenshot shows the previous frame: call `show_*` one shot earlier than the shot that should contain it.
- Autowrap labels in a container inflate it on the first frame: `reset_size()` each frame while visible
  (see `CardHint.refresh`).
- Regex alternations must list the longer name first (`PassSingleAsInteger|PassSingle`).
- Bash heredocs choke on apostrophes in long text: write doc/patch scripts with the Write tool, then run them.
- `TextureRect`/`Label` typed `var x := node.method()` fails to parse when the return type is Variant: annotate.
- Godot import errors "quaternion (nan)" / "Basis must be normalized" come from some FBX skins; models still load.
- `UnitModel` must collect its AnimationPlayers in `create()` (before `_ready`), or `play()` finds none.
- StandardMaterial3D has `metallic_specular`, not `specular`.
- The engine's XML serializer uses a custom base64 alphabet (`0-9A-Za-z+/`) and 5-byte headers per nested
  dynamic array; `compressed="true"` is lowercase. The sim loads `SimMap.SINGLE` by default, not Classic.
- `tools/msh_to_gltf.py --all` skips glbs newer than their `.msh`: delete `assets/units/**/*.glb` to force a rebuild.
- Godot's glTF importer keeps `matrix` nodes exactly; TRS decomposition of zero-scale pivots loses rotations.
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
