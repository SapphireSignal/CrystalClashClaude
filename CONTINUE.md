# Continue here

Paste into a new chat: **"Read CLAUDE.md and CONTINUE.md, then continue."**

**Owner (2026-09-17):** the owner **playtests**: at each
checkpoint give the run command and a short list of things to check, and fix what they report first.

## State (2026-09-17, checkpoint 73; see the checkpoint 73 paragraph below for the latest)
- Phases 1-3 done, 835 tests pass. Sandbox `game/main.tscn`: blue deck on keys 1-9,0,-,= or by clicking a card
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
- Verified by screenshot against `reference/ccmedia/ingame/*.webp` (those use the client's small layout; ours is
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

- **Checkpoint 32:** grass tufts (`TGrassTuft.ComputeAndSave` ported into `convert_map.py`, baked to
  `grass.glb`, 1435 / 1207 tufts), the original camera (`main.gd`: zoom 3.8 default, 2.6..3.8, 0.2 per wheel
  notch, distance = zoom x 10, FOV 0.6853981635 rad, `coEngineCameraFoV`), `MapView.LIGHT_SCALE` 0.7 so the lane
  stones render at ~190 like the reference (Godot lights in linear space, the original in gamma space,
  `Standardshader.fx:515`).

- **Checkpoint 33:** water shader port (`game/maps/water.gdshader`, parameters from the `.wat` via `map.json`,
  `TextureNormalization = GeometrySize / 2000`, wave texture copied next to the map).

- **Checkpoint 34: particle effects.** `tools/convert_particles.py` (366 .pfx -> json, textures),
  `game/effects/particle_effect.gd` (emitters, triggers instant/interval/distance, path nodes with the engine's
  random rules, Hermite, billboard modes, atlas cells, blend modes), extractor `effects` per script
  (`TParticleEffectComponent` chains), `main.gd` plays them on create (attached to the model), fire/prefire,
  die/free, projectile impact (firewarhead); scale = scale_with(collision radius / wela range) x model size /
  size normalization. Verified with `.tmp/effect_view.gd` (not committed) and Light Pulse in the sandbox
  (`tools/screenshot.gd -- 15 16 zoom=nexus play=8`).

- **Checkpoint 35:** attached effects follow their bind zone bone (`UnitModel.bone_attachment(zone)`:
  BoneAttachment3D + BoneOffset, model scale countered) and `VisibleWithWelaReady` effects toggle with
  `sim._wela_ready` (the footmen's shield rings). `tools/screenshot.gd -- 15 17 zoom=nexus play=2` shows them.

- **Checkpoint 36 (HUD fixes 1-2 of the owner's list, verified against `reference/ccmedia/ingame`):** resource
  panel rows/roman/timer at the art's positions (the 21 px content offset had been applied twice; roman 28 px
  bold, caption right pad 31, icon 110 % centred 10 px inside the row end); deck panel darken is the engine's
  COLOR_REPLACEMENT lerp (`game/ui/color_override.gdshader` on frame + icon, not a square), tier plate behind the
  deco with the countdown/lock drawn on top (`plate_top`), locked slots darkened without glow, ready glow pulses
  per `$glow` (opacity 1->0.6, scale 1.02->1, 2 s). The "double ring" is the source art (white spell frame +
  blue `highlight_drop.png` disc): kept. Side fixes: particle quads with a zero normal no longer error, unit bars
  skip off-screen / non-finite projections (the polygon errors are gone). `tools/screenshot.gd` has `zoom=node`.

- **Checkpoint 38: live-client camera.** Measured on the reference screenshots (ellipse fit of the platform ring
  and the sand strip angle): pitch/zoom/FOV as the 2022 constant. **Checkpoint 41 corrected the yaw**: a fit of
  the spawner tile corners + nexus in the game-start reference gives pitch 52-54 / yaw 49 / distance 39 = the
  2022 `CAMERAOFFSET`; `main.gd` uses the constant verbatim again (the 55.5 deg sand-strip value was wrong).
  **Sides swapped to the live client's** (blue at +x: own base top-right, lane to the bottom-left, blue
  top-right on the minimap): `SimMap.side()` / `legacy_sides` (tests keep the 2022 layout). **Lane rocks fixed**:
  `.bcc` items carry `<Size>` (BridgeParts 0.01) that `convert_map.py` now multiplies into the decoration scale
  (they were 100x too big: giant slabs = the "lifted ground"). CLAUDE.md decision recorded.
  Noted for later: the live top bar is red-left / blue-right for both players (ours: own blue left).
  Verified with `tools/screenshot.gd -- 12 13 zoom=nexus` (second shot: the first shows the frame before the
  camera moved!) against `image-1789614749130.webp`: clearing, jungle, stone ring, nexus and lane direction now
  match. Difference left: the live nexus crystal glows bright cyan (ours is the plain textured crystal).
- **Checkpoint 40: spawner tiles.** `game/maps/build_grid.gd` ports `TBuildGridManagerComponent`: one
  `Gameplay/Buildgrid/Buildgrid<1-4>` tile per free field (random variant / 90 deg rotation, scale 2/1.84+0.08,
  sunk 0.04), GlowOvershoot lerp to cyan by 0.4 while the field is in the wave rotation, dims over 1 s on
  `Simulation.wave_spawned`, all relight over 0.5 s after a full rotation. Assets via
  `tools/msh_to_gltf.py --gameplay` + `tools/copy_unit_assets.py --gameplay` -> `assets/gameplay/`. Not built:
  the red/green occupation colouring while placing a spawner (`ShowOccupation`/`ShowInvalid` ColorAdjustment)
  and the `buildgrid_activate.pfx` burst on spawn. Reference tiles look a bit brighter (post-effect glow).

- **Checkpoint 42: lighting matches the reference.** The original lights in gamma space (shadow = 63 % of lit
  on screen); Godot in linear needs ambient x0.35 and sun x1.06 (`MapView.AMBIENT_SCALE` / `SUN_SCALE`, replaces
  LIGHT_SCALE 0.7) plus a small shadow blur. Patch medians of sand / platform / shadowed jungle now match the
  game-start reference within ~5 levels. The terrain and vegetation heights were already right (the jungle ring
  rises up to 18 units); the "flat" look was the light balance. Fix-list item 3 (lane brightness) is thereby done.

- **Checkpoint 43/44: camera settled = the 2022 constant.** Checkpoint 43's flatter camera (pitch 48, distance
  33.5) came from a whole-frame correlation with the frame bottom masked and was wrong (lower-left ground 15 %
  off); checkpoint 44 re-scored with per-block alignment: pitch 54 / yaw 47 / distance 38 / original FOV wins
  (4.8 px). `main.gd` uses `CAMERAOFFSET` verbatim. Window stretch `expand` + `Hud._layout()` from the viewport
  rect (panels pinned to edges at any resolution; `FinalScreen` centred). `tools/screenshot.gd -- ... size=WxH`
  renders at the reference window size (1679x1079) for honest comparisons. The owner's monitor is 1680x1050-ish:
  their screenshots are 1679x1079 and use the client's *small* HUD layout. Owner's remark: where the reference
  looks bad (e.g. its blocky shadows) we may do better, as long as it stays unnoticeable as a difference.
- **Checkpoint 45: HUD sizes match.** Stretch mode disabled (absolute pixels like the original) and `Hud._layout`
  applies the `.small` layout below 1710x816 (80 % panels, 66x64 deck slots, 267 card hint). Verified at
  1679x1079 against the game-start reference (`.tmp/hud_cmp.png`). Small-layout details not done: locked deck
  groups shift 38 % (ours 55 %), spawner margin 48, jump button position, hint text 12 px.

- **Checkpoint 46: HUD blur backdrops.** `Blur : True` panels (top bar, resources, minimap, info panel) draw the
  scene blurred + recoloured to `$blur-color` behind their art (`HudStyle.blur`, `blur_backdrop.gdshader`); the
  minimap no longer shows the sharp world through its translucent water (`docs/hud.md`).

- **Checkpoint 47: world mirrored (handedness).** `Main/World` Node3D scaled -1 on Z holds map, units, effects,
  build grid, decal; camera/mouse/HUD convert z_global = -z_sim; map lights `top_level` with mirrored direction.
  Verified at the lane node and the base (`.tmp/mirror_fixed.png`): wall shadows and texture details now on the
  reference's sides. Next checks: rock wall pieces vs reference at high zoom (facing sign if still one rock
  off), top bar red-left/blue-right.
- **Checkpoint 48: mirrored-world fallout fixed.** Foliage under the mirrored node drew its back faces with
  normals pointing away (trees at half brightness): `game/maps/foliage.gdshader` (alpha cut-out, cull off,
  back faces flip the normal) replaces the StandardMaterial for vegetation + grass; tree patch medians now
  99/120/62 vs reference 92/112/58. Water shader gets the mirrored `sun_direction`. **Water still grey-teal
  instead of the reference's deep blue**: our port draws refraction + flat sky colour only (checkpoint 33);
  the original reflects the sky/scene (SSR) and its extinction makes deep water saturated blue. Next: port the
  reflection/extinction path of `Water.fx` (reference/delphi3d-engine) or tune sky_color/fresnel against the
  node reference patch (ref water ~ (30,110,150) at the top-left of `image-1789614715701.webp`).

- **Checkpoint 49: detail pass (owner: "every little thing like the reference").** Water: the Compatibility
  renderer has no depth texture, so the water depth now comes from `heightmap.png` (convert_map writes it;
  `water.gdshader` samples it in sim coords); live-client water colour/transparency/fresnel overrides in
  `MapView` (`LIVE_WATER_*`, deep water now (15,96,136) vs ref (0,95,134)). Spawner tiles fitted to the
  reference teal ((117,204,204) vs (120,206,204)). Resource panel rows: caption font 0.57 x row, pad 36, icon
  16 px inside the row end (matches the 1679 shots). Nexus textures were missing from `assets/units`
  (copy tool re-run for `Neutral/Nexus`); unit glow emission gets `UnitModel.GLOW_GAIN` 4.
  **Open**: (a) nexus crystal still dark blue (ref near-white cyan (203,234,237)): the original's gamma-space
  `colour * (NdotL * sun + ambient)` saturates the light-blue crystal texture; needs a unit shader port of
  Standardshader.fx lighting (also lifts all units); (b) the live map has sand beaches outside both lane
  walls (ref pixel (1500,1000) = sand where our 2022 heightmap is 12 units under water): live map data, not
  reproducible from the repo (note as delta); (c) top bar red-left/blue-right; (d) rock wall pieces check.

- **Checkpoint 50: deck panel small layout done properly.** `DeckPanel.set_small()` (called by the HUD before
  build): panel 64 high, 66x64 slot wrappers (frame overflows 2 px: circles rest on the screen edge), spawner
  margin 48, locked groups shifted 38 %; the tier plate spans the full panel height (top 11 px above the deck
  art, timer 10 px below its top) like the reference. Verified on the 1679x1079 grid (`.tmp/deck_grid.png`).
  Still open in the HUD: top bar red-left/blue-right; the sandbox deck has 7 stage-1 cards (reference decks
  show 3/3/3/3, so their plates are 3 wide).
- **Checkpoint 51: tier plates corrected.** The multi plate = mid over the group inset 21 design px per side
  (measured: a 3-slot plate is 170 px for 198 px of slots, adjacent plates never touch), end pieces with the
  slant outwards (left end = mirrored art), countdown + lock icon laid out as one centred pair (lock 6 px
  after the text, `DeckPanel.refresh`). `.tmp/plates_cmp.png` shows reference vs ours. Checkpoint 52: the plate
  is drawn after the deco band (covers the band's top edge like the live client) and before the cards.

## FIX FIRST (owner's request, before anything else)
00. **Done (checkpoint 56): back to the 2022 repo (owner).** Reverted every live-client adaptation: sides (blue at -x,
   `SimMap.side()`, `legacy_sides` gone), water from the `.wat` values, wheel zoom 2.6..3.8 back, hotkey badges back,
   the warm-up countdown text removed (2022 shows nothing during the warm-up, `stage_1` at the first tick). The
   Crystal Clash hand-over plan is in CLAUDE.md Decisions; screenshot deltas stay in `docs/reference-material.md`.
   The owner's screenshots turned out to be the Red player's view (own team always displayed blue): the sandbox human
   is now team 2 at +x (`Main.HUMAN_TEAM` / `AI_TEAM`), so the sandbox matches them 1:1 again.
0. **Done (checkpoint 53): lane node ring + two extractor fixes.** `tools/convert_particles.py` reads `<x>`/`<y>`
   axis tags case-insensitively (16 effects had zero sizes/colours: LaneNode, Capture0-2, Stun, SummoningSickness,
   RootDebuff, DarkTrollFireWave, 5 White effects, lib_field, lib_vertical_lines); `tools/extract_units.py` parses
   size expressions with parentheses (`10.0/(3.0)`). `tools/screenshot.gd` now renders at 1920x1080 by default like `reference/rolmedia` (borderless; `size=WxH` overrides, e.g. 1680x1050 for the small layout) and `-- 12 14 at=node` frames the
   map middle at the default zoom (use this, not `zoom=node`, for reference comparisons; lane nodes exist after the
   10 s warm-up). Camera re-checked against both reference shots: angle matches, remaining scale = player's wheel
   zoom (`docs/reference-material.md`). Still missing at the node: the live client's filled disc + sparkles (live
   delta) and the blue capture-progress ring (only while units capture).
1. **Done (checkpoint 37): lane node capture circle verified.** The ring renders (mesh, y 0.01, orientation:
   start +Z about +Y, gaps across the lane, arcs along it, exactly `DrawCircle` Up=UNITZ Left=UNITX); it was
   invisible because it was tinted white. The original tints it `GetTeamColor(Owner.TeamID)` and the node
   stays team 0, so it is neutral grey `404040` at the texture's 13 % peak alpha: a faint dark arc, visible at
   zoom 3.8 (at `zoom=node` 2.6 the 16.5 radius is outside the frame). Live-client delta (light arc) noted in
   `docs/reference-material.md`. Still open here: `LaneNode.pfx` (the disc particles) did not show in the shot,
   check `_spawn_effects(e, "create", holder)` for lane nodes; the blue progress ring (`TResourceDisplayComponent`
   team power) and `Capture%d.pfx` on fire are not built yet.
2. **Done (checkpoint 67): shield-block ring + three particle-player fixes.** (a) `convert_particles.py` parsed
   `Tangent1/2` with `vec()` but they are varied vectors (Mean/Variance children) -> every Hermite tangent was zero
   (all 366 effects regenerated); (b) bone-attached effects inherited the skeleton's scale (footman: -160!) into the
   emission base -> `ParticleEffect._emit` now uses `basis.orthonormalized()` + `effect_size` only, like the engine's
   `FParticleEffect.Update(pos, front, up, FinalSize.X)` (scalar size, no parent scale); (c) `FStickToEmitter` was
   ignored -> sticky particles (shield ring) now recompute their origin from the live emitter transform each frame,
   like `Particle.Origin := ownBase * rotMat` + current base (Emitters.pas:238-249); (d) `main.gd` no longer
   multiplies model size into `eiWelaRange`/`eiWelaAreaOfEffect` scaling (GAMEPLAY_SCALE_EVENTS skip it,
   Visuals.pas:2538). `main._play` returns the PlayResult; `tools/screenshot.gd` `play=N` tries look-at +-6 and the
   nexus +-8 as drop points. Footmen now show the orbiting golden shields + shimmer ring, moving with the unit.
3. Lane stones still brighter/flatter than the reference: revisit `MapView.LIGHT_SCALE` and the terrain
   material (roughness, Material.png) with a side-by-side crop.
Then checkpoint (tests, Status, CONTINUE.md, commit + push, give the new-chat prompt and STOP).

## Owner playtest fixes (2026-09-17, checkpoint 68) — from the owner's first playtest
Done this checkpoint:
- **Card arming** (TClientInputComponent port): keys/deck clicks ARM the card; translucent ghost units
  (squad pattern) / spawner ghost snapped to a free grid cell / Spelltarget ground-or-entity reticle with the
  `Invalid` texture variant follow the cursor; LMB plays (invalid click keeps it armed), RMB/Escape cancel.
  `tools/copy_ui_assets.py` copies `Spelltarget/`. Full research spec (zone renderer overlay, grid occupation
  tints, endless build, drag mode, error sound) is in this file's history via the subagent report — still to
  build: deck-slot armed glow, drop-zone overlay, grid red/green occupation tints, entity hover outline.
- **Render interpolation**: views lerp from the pre-step sim state (`_capture_prev`/`_lerp_pos`, alpha =
  accumulator/TICK_MS) — units no longer step at 31 Hz ("glitchy walk").
- **Shield ring gate**: VisibleWithWelaReady includes `w.cooldown_ready_at` (ring hides 5 s after a block).
  Sim itself was correct (absorb -> cooldown; ShieldsUp buff absorbs one 10+ hit then is spent).
- **White ground square** = VoidSkeleton attack slash with no texture: pfx texture names differ in case from
  disk (`Slice.png` vs `slice.png`); `convert_particles.py` now records the disk case (also ShockWave,
  Stones_Inflamed). Missing texture = opaque white quad (blend_mix, no alpha).
- **Terrain chunk textures** clamp to edge (glTF sampler 33071; default REPEAT bled the opposite edge).
- **Card hint font error** (alt-tab glitch): font sizes clamped to >= 1 (`card_hint.gd`), was 44+ red errors/session.
- **Projectiles**: effect-only projectiles (magic shots) now spawn their create-effects on a holder instead of
  the yellow fallback sphere; mesh projectiles also play their create-effects (trails).
- **The dark "line across the lane"** = the neutral lane node capture ring (2022-faithful, r 16.5 grey 404040
  at 13 % alpha). Not a bug; the live client's bright ring comes with the Crystal Clash refresh.
- `tools/screenshot.gd`: default window = primary monitor size (owner's screen), `size=WxH` for reference shots;
  `arm=N`; `play=N` falls back to nexus +-8; `main._play` returns the PlayResult.

**Checkpoint 69 (owner's second round):**
- **"Black line across the lane" root-caused for real**: it was the DirectionalLight PSSM cascade split
  boundary (a straight brightness seam crossing terrain AND units). `map_view.gd` uses SHADOW_ORTHOGONAL
  with max distance 220 (single cascade like the original's one shadow map). The capture-ring arc remains
  (faithful). Terrain textures also clamp + sample texel centers now (both were harmless-but-wrong).
- **Giant arrows fixed**: `ApplyAutoSizeNormalization` + ungrouped `Eventbus.Write(eiModelSize)` are now
  extracted (`auto_size`, `model_sizes["*"]`); `UnitModel` fits such meshes to eiModelSize world units
  (ArcherBaseProjectile: arrow = 1.2 units).
- **End-of-match fullscreen lobby fixed**: a hand-made borderless window covering the monitor gets promoted
  to exclusive fullscreen by Windows (mode reads 4, resizes ignored). `_apply_game_window` now uses Godot's
  WINDOW_MODE_FULLSCREEN (= borderless fullscreen window); leaving to the 1280x720 menu window works.
  Probably also fixes PrtSc.
- **Settings dialog overlap fixed**: all category pages started visible (`set_category` was only called on
  clicks); `_ready` now calls it. The SystemPanel path showed every page stacked.
- **`tools/playtest.gd`**: autopilot playtest (plays affordable cards at sensible targets, camera follows the
  front line, screenshots every N s + first projectile/death/spell, summary line). THE standard test now:
  `godot --path <proj> -s tools/playtest.gd --log-file <proj>/.tmp/godot.log -- 150 shot=25`.
- **Probe hygiene**: parse-check scratch scripts headlessly before opening a window
  (`.tmp/parse_check.gd -- res://path.gd`); the owner sees every red block on their screen.

**Checkpoint 70:** buff/modifier visuals done (first slice): the extractor records `{$IFDEF CLIENT}`
TParticleEffectComponent chains in Modifiers/Links (`modifiers.json` `effects`, 43 scripts), `Buff.effects()`
serves them, `main.gd _sync_buff_effects` polls each unit's buffs per frame and attaches the "now"/"create"
effects to the bind zone while the buff lasts (Shieldblock ring via ShieldsUp verified). `tools/screenshot.gd`
`play=` takes a comma list. Not built: "fire"-activated buff effects (shield_block_trigger on a block needs a
block event from the sim) and buffs on non-UnitModel views.

**Checkpoint 71 (owner's "finish everything in-game" round, 2026-09-17):**
- **Drop-zone overlay** = TZoneRenderer port: `game/effects/drop_zone_overlay.gd` (SubViewport with its own mirrored
  world + camera copy, the Drop_<Map> / _Invalid / _Cutout / _Dynamic meshes from `assets/gameplay/Zone` drawn with
  stencil passes in `zone_mesh.gdshader`, composited by `zone_post.gdshader` = PostprocessZone.fx: 0.7 alpha, 7x7
  border, world-space yellow noise, cursor fade dzAll). Shown while a drop/building card or an epic spell is armed;
  dynamic circles = own nexus (+ lanetowers unless epic) eiWelaRange[3]. Valid colour $FF00FF00 / invalid $FFFF0000.
- **Build grid tints**: `build_tile.gdshader` (HSV ColorAdjustment port) + `BuildGrid.show_occupation / show_invalid /
  reset_colors`; `buildgrid_activate.pfx` plays on each wave spawn.
- **Drop visuals**: `SimEntity.card_drop` (set before the spawn signal via `spawn(..., card_drop)`) -> `main._play_drop`
  plays the faction's drop_<color>.pfx from modifiers.json `Drop` and `SpawnMeshEffect` (`spawn_mesh.gdshader` = the
  five SpawnShader_<Color>.fx, EFFECT_TIMES, GLOW_COLOR_MAP; Blue's 20 ghost passes reduced to one). Spawner placement:
  `spawner_placed` -> Spawner.dws animation (scale Y 3->0.3->1, drop 3->0 over 160/300 ms, SpawnerImpact after 160 ms,
  permanent +0.2 offset via `_view_y`). Mesh glow flash (TMeshEffectGlow 350 ms) not built.
- **Hover outline**: `outline.gdshader` as material_overlay on the unit under the cursor, BORDER_TEAMCOLORS by real
  team id (entity spells: only while targetable). Approximation of the rsOutline post (normal-extruded shell).
- **Extractor**: mesh chains ending in `end;` inside skin branches (Monk had no animations). Verify after any
  extractor change: `python -c` count units with empty `animations` (now: ShieldDrone, FrostgoyleFountain,
  MonumentOfLight = genuinely static).
- **App**: the loading screen stays 3 frames over the starting match (no grey clear-colour flash).
- `tools/screenshot.gd` names fractional shot times `shot_14_4.png`.
- Top bar orientation confirmed from the source (left = team 1's nexus, coloured by displayed team): correct.
- `docs/ingame-gap-audit.md` (subagent) = the full checklist of in-match client features still missing; work it
  top-down by visibility next, one item per step, screenshot-verified.

**Checkpoint 72 (RoL-only sweep, owner repeated 2026-09-17: "I really want only Rise of Legions for now")**: every
number that had been fitted to Crystal Clash shots is now source-derived (file:line in the code comments):
- Resource panel: caption Padding-Right 120ch = 1.2 x row height = 37 px, row font 70 % of the row (21 px em), tier
  roman 60 % of the 56 px wrapper (33 px) — `core_game.scss:361-447`; engine `ch` = own rect height, Fontsize % =
  em size in px (`Engine.GUI.pas:7005`, `Engine.GfxApi.pas:2186`).
- Deck panel locked plate: ends at Position-X 70ch (0.7 x 75 = 52.5 px) anchored outwards -> inset 11.5 px per
  side (was 21), full panel height, over the deco band, under the cards (`core_game_deck.scss:155-183`).
- Card hint: CARD_HINT_DELAY 800 ms (`Classes.Gamestates.GUI.pas:153`); unit skill list font = 26 % of the content
  rect left by Padding-Top 30 % / Bottom 5 % (`shared_card.scss:315-320`).
- Build grid tiles: `GlowOvershoot.fx` lerp(diffuse, cyan, 0.4) = the source's no-Glow-post branch
  (`EntityComponents.Client.pas:3052-3063`; we have no Glow post-effect). Measured: rolmedia lit tiles (70,188,187),
  ours now (71,214,213) (green/blue = the known lighting brightness gap). With a Glow post the source uses 0.032 +
  the blurred glow stage — that is the path to take once a Godot glow environment is added.
- `MapView.GLOW_POST_GAIN` = (GAUSS_3_ADDITIVE taps 4.94164 x Intensity 0.44)^2 = 4.73 (PostEffects.fxs:22-33,
  Shaderglobals.fx:24, Engine.Core.pas:1835-1890): the unit glow-texture emission gain now derives from it
  (was a fitted 4.0).
- Camera comment cites Constants.Client.pas:34 / Settings.Client.pas:512,576-577 / EntityComponents.Client.pas:2078.
- Removed every "live client" / owner-screenshot mention from `game/`; `docs/hud.md` hint delay corrected.
Everything in `game/` now cites the 2022 source or `rolmedia`.

**Checkpoint 73 (gamma-space lighting port, 2026-09-17):** `MapView.AMBIENT_SCALE` / `SUN_SCALE` (fitted to
Crystal Clash shots) are gone. `game/maps/gamma_lit.gdshader` is the verbatim port of `Standardshader.fx:486-515`
(= `DeferredDirectionalAmbientLight.fx`, the default DeferredShading path): `tex * lerp(NdotL * (1 - shadow) * sun +
ambient, 1, shading_reduction) + specular * light` in gamma space (textures sampled raw, no `source_color`), then
the Glow post (additive, gain `GLOW_POST_GAIN`, render order 2) and ColorCorrection (`PosteffectColorCorrection.fx`,
PostEffects.fxs: shadows 0 / lights 0.956 / midtones **1.008**, order 10; the old note said 1.08), converted once
to linear for Godot's sRGB output. `game/maps/gamma_lit.gd` (`GammaLit.material(albedo, options)`) builds the
variants (`CULL_DISABLED`, `FLIP_BACKFACE`, `SEMI_TRANSPARENT` as prepended #defines) and serves the material
queries the spawn mesh effect / hover outline need. Used by: terrain chunks (glb materials replaced, normal map +
UV clamp), vegetation + grass (replaces `foliage.gdshader`), decorations, unit models (`UnitModel._material` now
returns a ShaderMaterial with the xml's SpecularPower/Intensity/Tint/ShadingReduction; engine defaults
`Engine.Mesh.pas:630-633`, specular intensity 0). Ambient (`rgb * intensity`, `Engine.Core.pas:1009`) and sun
(`rgb * a`) are the global shader parameters `rol_ambient` / `rol_sun` (project.godot `[shader_globals]`, set by
`MapView._add_lights`); the DirectionalLight3D only supplies direction + shadow (`ATTENUATION`). Verified: before/
after shots nearly identical to the fitted look (slightly more contrast in the jungle), shadows/glow/ghost preview/
playtest fine, 835 tests. Not ported: the spawn mesh effect shader (`spawn_mesh.gdshader`) still lights PBR during
its 2 s; particles/water untouched (their own shaders). Rules learned: Godot multiplies `DIFFUSE_LIGHT` by `ALBEDO`
after `light()` (pass the texel through a varying, set ALBEDO white); `get_shader_parameter` returns null for a
uniform at its default (never wrap it in `float()`/`bool()` blindly).

**Checkpoint 74 (owner's report on 73, 2026-09-17):**
- **Black line through the towers across the lane** = the terrain chunk seam (4x4 chunks, edges at x = +-75 where the
  lanetowers stand): the gamma shader clamped UVs but sampled with `repeat_enable`, which wraps at coarser mip levels.
  `UV_CLAMP` define -> `repeat_disable` samplers (hardware CLAMP_TO_EDGE like the glTF).
- **"Everything glowy" / bright tile grid**: the build tiles were still PBR-lit while the terrain used the gamma port.
  The lighting now lives in `game/maps/gamma_light.gdshaderinc` (uniforms, globals, varyings, `light()`), included by
  `gamma_lit.gdshader` and `build_tile.gdshader`. Reference lit tiles (70,188,187) = lerp(gamma-lit diffuse (128,143,143),
  cyan, 0.4): the no-Glow-post branch matches the rolmedia shots (the Glow branch would give (128,181,181)). Ours now
  (77,219,218): G/B still ~+30 (the `buildgrid_activate.pfx` additive flashes over the active tiles; check the pfx
  intensity next). The jungle interior is still lighter than the reference (SSAO `PostEffectSSAO` default on in the
  2022 presets, not built; palm self-shadowing): next lighting item.
- **Rubberband / units not smooth**: the sim is smooth (headless probes `.tmp/walk_probe.gd`, `.tmp/crowd_probe.gd`:
  0 backward steps, 24 blocked-tile stalls in 24000 unit-ticks). The pop was `UnitModel._cut_animations`: keys one frame
  outside the range were clamped onto the clip edges, so a walk loop ended on the *next take's first pose*. Now only
  keys inside the range are copied and the exact edge poses are sampled (`_sample_track`).
- **Red errors after a match**: `app.gd` connected `size_changed` to a lambda capturing the menu layer and never
  disconnected it (`_menu_resize` now disconnected in LeaveState).
- **Own units outlined red / info panel**: sandbox human is now **team 1** (see CLAUDE.md Decisions): the outline
  follows the raw team id like the source, so own = blue, enemy = red. The unit panel health bar is red for every
  unit (`docs/hud.md`: HEALTH_RED, the original's `.health` bar) and the ground marker under a clicked unit is
  `HUD/Selection.png` (`HUD_SELECTION_TEXTURE`, Constants.Client.pas:303): both faithful.
- **"Watchtower radius ring stays after it dies"**: faithful. A destroyed lanetower leaves a neutral LaneNode whose
  `TTextureRangeIndicatorComponent` is `IsPermanent` (LaneNode.ets:41-56); the tower's own indicator only shows
  with the drop zone (`DrawOnShowSpawnZone([dzDrop])`, Lanetower.ets:231).
- **Yellow placeholder projectile spheres**: TVertexQuadComponent (sprites: lens flares, souls, arrows) and
  TVertexTraceComponent (ribbons/trails) are now extracted (`units.json` `quads` 35 / `traces` 56 scripts; texture
  expressions with skin suffix / script variables resolved) and rendered by `game/effects/vertex_quad.gd`
  (+ `vertex_quad.gdshader`: ScreenSpace / CameraOriented / fixed orientation, additive, colour) and
  `game/effects/vertex_trace.gd` (TVertexTrace port: sampling distance, texture offset, fade, widening, roll-up,
  camera-facing ribbon). `tools/convert_particles.py` copies `Graphics/Effects/Textures` to
  `assets/effects/vertex_textures/`. Views: quads/traces attach to unit and projectile views; the yellow sphere is
  only the last resort. Not built: TPointLightComponent, `VisibleWithResource` traces, trace deactivate-on-move.
- **FPS (250-360 on an RTX 4090)**: not profiled yet; suspects are per-frame GDScript (`_sync_views`,
  `_sync_buff_effects` polling, the CPU particle player, `find_children` in the hover outline) and the drop-zone
  SubViewport. Next: profile with `--debug` / `Performance` monitors and cut the per-frame work.

Still open from the owner's earlier report:
1. Owner re-test (this checkpoint: seam, walk pop, team colours, tiles, projectile sprites/trails, errors).
2. FIX FIRST item 3 (lane stones brightness) re-check against `rolmedia` with the ported lighting, then the
   particle/model polish lists and `docs/ingame-gap-audit.md` top-down.

## Done from `reference/rolmedia/` (2026-09-17)
- Hotkey badges hidden by default (`coGameplayShowDeckHotkeys` = false; `DeckPanel.show_hotkeys` for the settings menu).
- Top bar: left = team 1, right = team 2, bar colour by displayed team (own blue): a Red player sees red left.
- Deck slot pitch 85 (was 87).

## Next step (in order, one at a time, run the game after each)
0. **Pre-match screens** per `docs/lobby.md` section 4 (checkpoint 59 wrote the spec). **(1) done (checkpoint 60):**
   `game/app.tscn` + `app.gd` = TGameStateManager (states MainMenu / LoadGame / Game, project main scene);
   `game/ui/menu/menu_background.gd` (bg.anb: 4 layers, zoom 1.15, sin/cos offset x0.08 scaled by 1-depth) and
   `menu_loading_screen.gd` (`.loading-main-page`: logo 30 % + release banner, opener 24 px bold, status text
   font = its height, spinner -1 rad/s, three clickable logos, slow text after 40 s). Engine rules learned:
   `%` in Position = of the parent's content rect, `auto` size = art aspect, `FontSize : 100%` = own height.
   Preloading = threaded load of `main.tscn`; with no dashboard yet MainMenu jumps into the sandbox when done,
   and the sandbox's Continue reloads `app.tscn` (step 6 rewires it). `tools/copy_ui_assets.py` copies
   `Shared/Logos`, `Shared/AnimatedBackground`, `MainMenu/LoadingScreen`, `Shared/Spinner.png`. Verified with
   `.tmp/menu_shot.gd` (not committed; instantiates MenuBackground + MenuLoadingScreen, saves `.tmp/menu_*.png`).
   **(2) done (checkpoint 61):** `game/ui/menu/main_menu.gd` (MainMenu.dui shell, `Menu` enum = mtStart..mtShop,
   `PROFILE`/`SERVER_STATE` stubs for the missing master server), `navbar.gd` (navbar.scss + navbar_player.scss:
   54 px bar with `Padding 3 0`, buttons `text + 15 px` wide at 43 % font, Start 53 px with Home.png, Play with
   `play_button(_hover).png` and MinWidth 204.2ch, selected = ExtraBold + `chosen_tab_indicator.png`, Shop gold,
   Collection/Leaderboards level locks with `Shared/Lock.png`; right: two currency boxes, member icon, premium
   indicator darkened, name+level bar; hints via `tooltip_text` for now), `dashboard.gd` (dashboard.scss: Header.png
   at native size, players-online, announcement box, disabled social tile with clickable icons, divider at 59 %,
   right tiles: Scill banner 173 / tournaments 82 / Steam / Discord / patch notes 80 with hover border, URLs from
   `TGameStateManager.BrowseTo`). The dashboard was designed for 1280 wide: at 1920 the banners clip (kept).
   `app.gd` shows the shell after the preload; the preload is now a synchronous `load` one frame after the loading
   page (a threaded load raced the menu's use of HudStyle/Lang and failed to parse `hud.gd`). Play -> LoadGame ->
   sandbox. Verified with `.tmp/menu_shot.gd` (shell over the background) and `.tmp/app_flow.gd` (full flow, presses
   Play after 2 s; both not committed). Not built: SystemPanel (minimise/settings/close), hover-menu, notifications,
   the styled `.hint` tooltip, `$cyan-glow` on the highlighted banner, the `new-flag` badge.
   **(3) done (checkpoint 62):** `game/ui/menu/teambuilding.gd` (Teambuilding.dui + matchmaking.scss + Teamlist.dui
   + Queue.dui): sub-navbar tabs Quick Match / 2v2 Match (level 2 lock) / Golem Challenge / Co-op Challenge (lock) /
   Custom Game / Tutorial right, drawn above the navbar art with `z_index` 1 (the original's ZOffset 900); the tab
   row is placed by the reference queue screenshot (strip top 62, text centre y 85, font 18: the scss `100% auto`
   strip did not explain the reference, so these three are empirical); type description (80vw x 24) with the bold
   tier hint + `exclamation_success.png` for PvP; PvE shows the Gamemode ("Sandbox - Solo Challenge") and Difficulty
   (Stone, +0%) `Button_Sub.png` buttons (display only, dialogs not built); team row 75vw x 148 centred -5 %:
   `player_icon_frame.png` + UnknownPlayer, name 40 %, "Teamleader" at 60 % opacity, `Deckslot.png` at 383 px with
   UnknownDeck icon, deck name "Sandbox" (`scenario_sandbox`) and the deck's league icon, `selected_deck_banner.png`
   above; Start = btn-xl 70 high at the bottom (-10 %), `enter_queue_tier_<league-1>.png` for PvP (auto league from
   the sandbox deck = Gold) else `button_xl.tga`, hover variants; `tutorial_video_button.png` "QUICK GUIDES" bottom
   left (no dialog). `MainMenu` mounts it for mtGame; Start -> `play_requested` -> app LoadGame -> sandbox. All
   scenario types start the same sandbox for now. Not built: queue window / queue timer in the Play button,
   scenario/difficulty/deck dialogs, match hints, the `$pulsate` animation on Start, DEBUG button.
   **(4) done (checkpoint 63):** `game/ui/menu/loading_screen.gd` (LoadingScreen.dui + loading.scss + tutorial.scss,
   TGameStateLoadCoreGame `Gamestates.pas:3123-3296`): background `auto 100%` centred, progress bar 36.33 % wide at -5 %
   with the fill clipped inside its padding box (25/3/24/3 %, top/bottom of the height), state text 30 % below
   (`loading_initializing` -> asset category by progress -> `loading_finalizing`), first-time hint 90 % above (first
   match of the session only), `.match` stacks 25 % wide at 25 %/75 % x 48 % (rows 200 high, padding 35, gold bold
   username 40 %, Deckslot 60 % high right-anchored for team 2, UnknownDeck icon, deck name 59 %), VS icon 7.214 %;
   `.tutorial` slide 655 high centred with the logo 40 % at 3 % and the caption at -16.2 %. Timing: match display 10 s
   then slide (random offset) every 5 s, minimum 10 s, Progress = max(prev, min(loader, minimum fraction)); the sandbox
   scene is already preloaded so the bar is the minimum timer and the game starts at 10 s (the slides only show for the
   tutorial scenario, `esTutorial` from `MainMenu.play_requested(scenario)`). Players = the local player on team
   `Main.HUMAN_TEAM` (the AI is not a player, like PvE). Engine default FontSize = 24 (`Engine.GUI.pas:5926`).
   `tools/copy_ui_assets.py` copies `LoadingScreen/` (now incl. jpg) and `Shared/Tutorial/`. Verified with
   `.tmp/app_flow.gd` (shots at 4/9 s) and `.tmp/loading_shot.gd` (tutorial stage; both not committed). Not built:
   loading music, the game-server connection/abort paths.
   **(6) done (checkpoint 64):** `main.gd` has `signal match_left` (forwarded from the HUD's final screen; stand-alone
   it still restarts the match); `app.gd` connects it to a deferred `change_game_state(MAINMENU)`, so Continue (or the
   11 s timeout) frees the game and re-enters MainMenu like `TGameStateCoreGame.EnterMainMenu` (`Gamestates.pas:2468`):
   the preload page shows again briefly (the original re-runs `InitAssetLoader` with its cache) and lands on mtStart
   (`Idle` `:2971-3010`: without ServerGameData -> mtStart; the mtGameRewards statistics screen of server matches is
   not built). Verified with `.tmp/exit_flow.gd` (kills the human nexus at 14 s, shots at 17/30.5 s; not committed).
   **(7) done (checkpoint 65):** `game/settings.gd` = `ClientSettings` (TOptionManager + TSettingsWrapper: options
   keyed `<Category>/<Name>` like the original ini (`[Gameplay] ClipCursor`), DefaultOption values verbatim, only
   overrides written to `user://Settings.ini`, SaveSnapshot on open / LoadSnapshot on Cancel, RevertCategory,
   ClickPrecision thresholds (`> 1.0` wide, `> 0.0` extended: the default 1.0 reads back as extended, original quirk),
   shadow quality by resolution thresholds + the bias triples, graphics presets = exact option-set match, `apply()`
   on Save sets display mode/vsync/master bus, `apply_startup()` in `app.gd` only vsync + audio so the project's window
   settings stand). `game/ui/menu/settings_menu.gd` (SettingsMenu.dui + settings.scss + _common.scss `.window`
   /`.backdrop`): backdrop blur with BlurColor white (greyscale) + `$background-backdrop` tint as its own node (children
   draw above `_draw`), 800x580 window (bg 324b50, border 2 5c8989 inside, outline 3), dialog_header.tga caption 35 px
   above the top, category column (30 %, padding 20; headline 70/bsMargin 5, category 50 + margin 0 5 5 5, divider 10,
   selected = cyan 0.3 + 5 px left border, hover 30FFFFFF, Menu categories darkened in a match), `.column` 320 wide
   with 22-high rows at 26 pitch (check = Checkbox[Down][Hover].tga square + text at 1.2 h, select = field frame 24/28
   high with 70 % font and a dropdown list drawn last, progress = 80000000 bg + 239191 bar set by click/drag,
   `.deactivated` opacity 0.55 for the nested sound rows / toon+SSAO without deferred, `.secret` check opacity 0.01),
   Revert bottom-right of the content, Save/Cancel btn-xl 35 px below the window. `ingame_menu.gd` = HUD/Menu.dui
   (270x330, small caption, buttons 90 % wide `auto` high with -10 margin, Back to game at the bottom); `main.gd`:
   Escape toggles it (was quit), minimap `menu_pressed` too, Settings opens the dialog on Graphics (OnDialogOpen in a
   match), Surrender = `Simulation.surrender(team)` (eiSurrender: the team loses at once), Exit quits. HUD:
   `apply_settings()` (hotkey badges via `DeckPanel.set_show_hotkeys`, technical panel) through `ClientSettings.listen`,
   `unit_bars.gd` health bar mode (hmNone/hmDamaged/hmAlways, Alt shows all). `tools/screenshot.gd` gained `menu` and
   `settings=<gameplay|sound|graphics|keybinding>`. Tests: `tests/test_settings.gd` (defaults, precision thresholds,
   presets, snapshot/revert, surrender); 826 pass. Not built: Keybindings rows + KeybindingDialog (EnumKeybinding
   defaults from `Constants.Client.pas:63` + KeybindingManager), the Menu categories' content, SystemPanel (opens the
   dialog from the main menu), the `$fade-in`/`$scale-in` dialog animations, GUI click sounds. Open check: whether the
   HUD stays faintly visible under the blurred backdrop like the original (our shot showed only the scene).
   **(8) done (checkpoint 66):** `system_panel.gd` (SystemPanel.dui + menu.scss `.system-panel`: three 16x16 buttons
   at -4/4 top-right, moved in front of the shell like its ZOffset 20000), `exit_dialog.gd` (ExitDialog.dui, 450x160,
   Quit/Cancel; also the in-game menu's Quit = `CloseForcePrompt`), the settings dialog's two **Menu** categories
   (MenuSettings.dui: language list, scaling mode, resolution with the rows deactivated on msFullscreen, fullscreen
   frame, bring-to-front; MenuSoundSettings.dui: the menu's own mixer), opened from the panel with `in_game = false`
   so it starts on the Menu category (`OnDialogOpen`: `IsClientWindow` -> otMenu).
   **The big finding of this step (owner spotted it):** the menu client draws on a fixed **1280x720 canvas** scaled
   to its window (`GUI.VirtualSize := CLIENT_DEFAULT_DIMENSIONS`), while the game window has none - see CLAUDE.md
   Decisions and `docs/lobby.md`. `menu_layout.gd` holds the canvas, every menu control lays out against
   `MenuLayout.layout_size(self)`, and `ClientSettings.menu_window_size` ports SetClientWindow's arithmetic. The
   window now follows the client state: menu = borderless 1280x720 centred on the monitor, match = borderless over
   the monitor's full bounds (windowed fullscreen, never a mode switch). `project.godot` opens centred on the
   primary screen and `tools/screenshot.gd` positions there too (the desktop origin is the owner's second monitor).
   The Play screen's sub-navbar was re-derived from SubNavbarBackground.png (2560x55 -> 27.5 canvas px) and the scss
   (`Padding-Bottom 15%` -> 23.4 content = `$navbar-sub-size`, `.btn-nav` padding 2/1, `Fontsize 90%` -> 18); its old
   constants were screenshot measurements taken at 1600 wide and never divided by that shot's 1.25 scale.
   Open: no English Play/queue reference at a known scale exists in `reference/rolmedia/lobby`, so the sub-navbar
   font is stylesheet-derived, not screenshot-verified (the Shop shot uses the *secondary* sub-navbar).
   Next: (9) the Keybindings tab (`KeybindingSettings.dui` + `KeybindingDialog.dui`, EnumKeybinding from
   `Constants.Client.pas:63` and the KeybindingManager defaults), then the remaining polish lists below.
   Earlier notes: SystemPanel (MainMenu/SystemPanel: minimise / options / close top-right) so the settings open from the
   menu with `in_game = false` (Menu categories enabled, MenuSettings.dui/MenuSoundSettings.dui content), or the
   Keybindings tab. Then the remaining polish lists below.
1. Particles polish; for (e) the rotation sign convention if an effect looks mirrored: (a) `AtFireTarget` / `ClonesToTarget` effects; (c) light particles as
   OmniLight3D (100 emitters), `ptTrace` ribbons, nested `ptEffect`; (d) deactivation (`DeactivateOn*`,
   `stop_on_free`) and interval emitters that should stop when the wela ends; (e) the rotation sign convention
   (`Basis.from_euler(-rot)`) is a guess: compare an effect with a mean rotation against the original if one
   looks mirrored; (f) the light_pulse_cast flash appears off-centre in the debug view: check emitter FPosition.
2. Map polish (lighting/material comparisons kept disagreeing before): (b) shadows look weak: check the DirectionalLight shadow settings and
   the original's shadow strength; (c) terrain `Material.png` (specular) later; (d) verify the Delphi `Random`
   replica against the original (palm variants/rotations) if a screenshot shows a mismatch; (e) grass wind
   animation (`Custom` vertex data = time offset) as a shader.
2. Models polish; for (d) the zero-scale import errors if a model looks wrong (glow textures done: `copy_unit_assets.py` bakes `*Glow*` maps as premultiplied png used as
   emission with `emission = BLACK` + ADD): (a) done (checkpoint 59): walk clip length per `Visuals.pas:3343-3361`
   incl. the IgnoreScalingForAnimations variant, SpeedFactor as a length multiplier, random 0-70 % walk offset; (b) glow textures (`GlowTexture`, team glow) as emission; (c) `Effects/Meshes` spell props and
   the Environment/Gameplay `.msh` (13 + 2) once the map needs them; (d) the 18 "Basis must be normalized" import
   errors: find which glb nodes have zero scale (probably `_Scaling` pivots folded into static matrices are fine;
   check animated ones) - cosmetic unless a model looks wrong.
3. Particles: `docs/particles.md` is the researched spec (format, path simulation, triggers, blend modes,
   game usage, port plan). Next: `tools/extract_units.py` records `TParticleEffectComponent` chains as `effects`
   per script; `tools/convert_particles.py` -> `assets/effects/<path>.json` + textures; `game/effects/
   particle_effect.gd` CPU path player (MultiMesh billboards per emitter, additive / mix / subtract materials);
   hook `ActivateOnCreate/OnFire/OnDie` in the sandbox views. Sounds (FMOD banks: need a bank extractor) later. Find the original mesh/animation formats under `reference/rise-of-legions/`
   and the loaders in `reference/delphi3d-engine/`, textures (`.tga`/`.dds`), particles `.pfx`, FMOD sound banks.
   Write `docs/assets.md` rows per format with a conversion plan, then `tools/convert_*.py` for meshes first
   (Footman), swap the capsule in `main.gd` for the real model, then the maps.
2. **Pre-match screens and settings menu: build from the repo's `.dui`/`.scss`/images** (owner, 2026-09-17: "we
   know all of it, build it all"). Spec: `docs/lobby.md` (state flow, every screen's layout, GUI engine units,
   build order). No waiting for screenshots; `reference/rolmedia/lobby` verifies what it can.
3. Later: audit the Steam patch notes newer than 2022-01-19 (CLAUDE.md Decisions) and apply via the extractor.

## Rules that bit us
- Menu layout numbers are **1280x720 canvas units**: a feature measured on a 1600- or 1920-wide menu screenshot must
  be divided by that shot's scale (width / 1280) before it goes into the code. The in-match HUD is the opposite.
- `DisplayServer.screen_get_rect()` does not exist; use `screen_get_position()` + `screen_get_size()`.
- Never position a window at `Vector2i.ZERO`: the desktop origin is the owner's secondary monitor.
- Inner class names must not shadow Godot classes (`class Slider` failed to compile: "hides a native class").
- A tint drawn in a Control's `_draw` is covered by its child nodes (the blur ColorRect): make the tint a node too.
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
