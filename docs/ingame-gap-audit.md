# In-match client feature gap audit

Compares the original Delphi client's in-match systems (`reference/rise-of-legions/BaseConflict.EntityComponents.Client*.pas`,
`BaseConflict.Classes.Client.pas`) against the port (`game/`). Rise of Legions source only; `reference/ccmedia/` was not
consulted. Status: DONE / PARTIAL / MISSING. MISSING items most visible to a player are listed first within each group.

## Audio

- MISSING: All in-match sound. `TSoundComponent` (Client.Sound.pas:46, attack/hit/death/ability sfx per unit),
  `TGameSoundManagerComponent` (Client.Sound.pas:179, music/ambience), `TGlobalSoundManagerComponent` (Client.Sound.pas:144,
  GUI clicks/card play/announcement stingers). `game/` has no `AudioStreamPlayer` usage anywhere in sim/ui/effects; only
  `game/settings.gd` stores volume sliders with nothing to drive. The match is currently silent — highest-visibility gap.

## Unit visuals & mesh effects

- PARTIAL: Death: unit view is `queue_free()`'d immediately on death (`game/main.gd:618 _on_died`) — no
  `TUnitDecayManagerComponent` (Client.pas:595) dissolve/fade-out/ragdoll settle before removal.
- PARTIAL: Runtime mesh effects. Only `TMeshEffectSpawn` is ported (`game/effects/spawn_mesh_effect.gd`, drop-in dissolve).
  The rest of the `TMeshEffect*` family (Visuals.pas:472-845: Tint, Ice/Frozen, Stone/petrify, Ghost, Glow, HideAndGlow,
  Spherify, Melt, Warp, Metal, Matcap, Wobble, Invisible, Void, SlidingTexture, ColorOverlay, SoulExtract, SoulGain) is
  MISSING as a generic system — buff visuals only get particle effects via `_sync_buff_effects` (`game/main.gd:585`),
  never a material/shader change on the unit mesh itself, so e.g. a frozen unit doesn't turn icy and a petrified unit
  doesn't turn to stone on the model.
- MISSING: `TVertexTraceComponent` / `TVertexTraceManagerComponent` (Visuals.pas:1117, Client.pas:572) — weapon/projectile
  motion trails. No trail rendering anywhere in `game/`.
- MISSING: `TPositionerSplineComponent`, `TPositionerMeteorComponent`, `TPositionerRotationComponent`,
  `TPositionerOffsetComponent` (Visuals.pas:1403-1478) — secondary bone/attachment motion (idle sway, meteor arcs,
  spinning parts). `game/units/unit_model.gd` only plays baked animations; no procedural positioners.
- MISSING: `TCameraShakerComponent` (Visuals.pas:56) — camera shake on impacts/explosions. No shake logic in
  `game/main.gd` camera code (`_place_camera`).
- MISSING: `TPointLightComponent` (Visuals.pas:1069) — dynamic lights from muzzle flashes/explosions. No dynamic
  `OmniLight3D`/`SpotLight3D` spawned by effects; `game/effects/particle_effect.gd` and `main.gd` never add lights.
- MISSING: `TAnimatorComponent` general-purpose property animator (Visuals.pas:1334, drives arbitrary numeric properties
  over time e.g. scale pulses, opacity fades outside of mesh effects) — no equivalent in `game/`.
- DONE: Team-color material selection at model build (`game/units/unit_model.gd:_material`, descriptor `team_textures`).
- DONE: Baked animation playback incl. attack/move blending (`unit_model.gd:play`, `play_attack`, `set_moving`).
- DONE: Outline highlight on hover (`game/effects/outline.gdshader`, `main.gd:_set_outline`).
- DONE: Spawn/drop dissolve-in mesh effect (`game/effects/spawn_mesh_effect.gd`, `main.gd:_play_drop`).
- DONE: Shadows — one orthogonal cascade matching the source's single shadow map (`game/maps/map_view.gd:106-111`).

## Particles & decals

- DONE: Particle effect playback engine (`game/effects/particle_effect.gd`): Hermite tangents, StickToEmitter,
  bone-zone attachment, create/fire/die/firewarhead activations (`game/main.gd:_spawn_effects`, `_attach_effect`).
- DONE: Buff-driven particle attachments for "now"/"create" activated effects (`main.gd:_sync_buff_effects`).
- PARTIAL: Buff effects that need a discrete trigger (e.g. shield-block flash) are explicitly skipped — see
  `main.gd:594` comment `"fire" effects (shield_block_trigger) need a block trigger; not wired yet`.
- PARTIAL: Effects with `at_fire_target` (impact-point-anchored particles distinct from the projectile) are skipped —
  `main.gd:650` `# needs target tracking (later)`.
- DONE: Drop-zone overlay with stencil pass (`game/effects/drop_zone_overlay.gd`, `zone_mesh.gdshader`, `zone_post.gdshader`)
  porting `TZoneRenderer` (Classes.Client.pas:35).
- DONE: Lane-node capture range circle (`game/effects/range_circle.gd`, ports `TTextureRangeIndicatorComponent`,
  GUI.pas:406).

## HUD panels

- MISSING: `TIndicatorCooldownCircleComponent` / `TIndicatorResourceCircleComponent` (Client.GUI.pas:474, 523) — the
  radial cooldown/resource-charge ring shown around an ability's ground-target reticle while a timed ability winds up.
  `game/main.gd`'s spell reticle (`_reticle`, line 34) is a static ground decal only, no fill/cooldown ring.
- MISSING: `TSpelltargetVisualizerShowPatternComponent` / `TSpelltargetVisualizerLineBetweenTargetsComponent`
  (GUI.pas:616, 631) — AoE pattern preview outline and the line drawn between a multi-point spell's points while casting
  (e.g. Relocate). The port supports the two-point cast logic (`main.gd` `_pending_points`) but does not draw a
  connecting line or shape preview.
- MISSING: `TMinimapPingComponent` (GUI.pas:130) — minimap pings (ally alert markers). No ping placement/rendering in
  `game/ui/minimap.gd` (only draws units/camera quad, no input handling for pings at all).
- MISSING: `TTooltipUnitAbilityComponent` (GUI.pas:100) — in-world tooltip when hovering a unit's ability icon above its
  head; `game/ui/card_hint.gd` only covers deck-card hover tooltips, not on-field unit ability tooltips.
- MISSING: Scoreboard / end-of-round stat panel and in-match chat (`TIngameHUD` per CLAUDE.md's cited
  `BaseConflict.Classes.Gamestates.GUI.pas`). No chat widget or scoreboard exists in `game/ui/`. Low visibility until
  multiplayer exists (Phase 6, not yet started) — listed for completeness.
- MISSING: Spectator mode UI (team/camera switch panel). Not applicable until multiplayer; no code present.
- DONE: Resource panel (gold/wood/tech), `game/ui/resource_panel.gd`.
- DONE: Deck panel with tier locks, cooldown fill, charge/hotkey badges (`game/ui/deck_panel.gd`).
- DONE: Minimap render incl. `WorldToMiniMap` port and camera frustum quad (`game/ui/minimap.gd`).
- DONE: Info panel for a clicked unit with ground decal (`game/ui/info_panel.gd`).
- DONE: Card hint hover tooltip incl. delayed ability box (`game/ui/card_hint.gd`).
- DONE: Announcements banner (`game/ui/announcements.gd`).
- DONE: Victory/defeat final screen with original timers (`game/ui/final_screen.gd`).
- DONE: Card-arm ghost preview + validity coloring (`main.gd:_update_preview`).
- DONE: Drop-zone / build-grid visuals (`game/maps/build_grid.gd`, `game/effects/drop_zone_overlay.gd`).

## Unit bars & indicators

- DONE: Health/mana/ammo bars projected over units (`game/ui/unit_bars.gd`), incl. chunked ammo bars.
- MISSING: `TStateDisplayComponent` / `TStateDisplayStackComponent` (GUI.pas:206, 224) — status/buff icon stack shown
  above a unit (stunned, frozen, shielded, etc.). No equivalent icon row exists; buffs are only visible via their
  particle effect if any, not a readable icon.
- MISSING: `TEntityDisplayWrapperComponent` general visibility/culling wrapper for on-field UI (GUI.pas:147) — the port
  draws bars unconditionally rather than through a generic wrapper; likely fine functionally but no distance/occlusion
  culling behavior was found (`unit_bars.gd:_draw` iterates all entities every frame).
- MISSING: `TShowOnMinimapComponent`-driven selective visibility rules (GUI.pas:681) beyond what `minimap.gd` hardcodes.

## Input & camera

- PARTIAL: Camera: pan via right-drag and arrow keys, zoom via wheel (`game/main.gd:160-186`, `_place_camera`) — matches
  `TClientCameraComponent` (Client.pas:218) core pan/zoom, but no `TCameraShakerComponent` (see above) and no dedicated
  camera-jump keybindings beyond the spawner-jump helper (`_spawner_jump`).
- MISSING: Drag-select / multi-unit selection box. Original `TClientInputComponent` (Client.pas:334) and
  `TSelectedEntityComponent` (GUI.pas:649) support marquee-select; the port's left-click only selects one unit under the
  cursor (`main.gd:167 _hud.select(_unit_at(...))`) — no drag rectangle, no multi-select.
  Note: the original RTS gameplay is drop-and-forget (no unit orders), so this may matter less than in a normal RTS —
  still flagged since the source component exists and hover/selection is a visible HUD feature (info panel highlight).
- MISSING: Minimap click-to-ping / minimap pings (see HUD panels).
- MISSING: `TTutorialDirectorComponent` and its action classes (Client.pas:618-836) — scripted tutorial hints, arrows,
  camera locks, world text during a guided match. `game/app.gd` only has a `tutorial` mention in the loading-screen
  slideshow copy, not an in-match tutorial director. Not required until a tutorial scenario is built.
- MISSING: `TClickCollisionComponent` precise 3D-mesh click picking (Client.pas:61) — the port uses a 2D ground-plane
  math pick (`main.gd:_unit_at`, `_mouse_world_2d`) rather than per-mesh collision; functionally close enough for a
  top-down RTS camera but not the same technique (no misclick edge cases audited).

## Match flow

- DONE: Fixed-tick simulation, economy, spawning, combat — see CLAUDE.md Status (extensive, not repeated here).
- DONE: Final screen victory/defeat with original 4s/11s timers (`game/ui/final_screen.gd`).
- DONE: Loading screen with match display, VS icon, tutorial slideshow, minimum time (`game/ui/loading_screen.gd`
  per CLAUDE.md Status — file present under `game/ui/menu/`).
- MISSING: Surrender confirmation flow beyond the basic ingame-menu Surrender button — original's
  `TCommanderManagerComponent`/`TGameStateCoreGame` networked surrender handshake (multiplayer-only; not applicable
  to the current single-player sandbox).
- MISSING: `TGameIntensityComponent` (Client.pas:494) — tracks match "intensity" for dynamic music mixing. Moot until
  Audio exists (see above), but flagged since it's a client component with no port equivalent.

## Sandbox / debug

- PARTIAL: `tools/playtest.gd` autopilot exists as the project's own test harness, not a port of any original debug
  panel. The original's "technical panel" (FPS/network stats overlay, referenced in CLAUDE.md Status under Settings) is
  read from `game/settings.gd` toggles but the actual overlay content (network ping, tick timing) was not found wired
  into `game/ui/hud.gd` beyond the toggle existing.
- MISSING: In-original sandbox mode has no special debug UI beyond free cards (`Commander.free_cards`, already ported
  per CLAUDE.md Decisions) — nothing further identified as missing here.

## Performance-relevant

- PARTIAL: `unit_bars.gd:_draw` iterates every simulation entity each frame with no culling by camera frustum or
  distance, unlike the original's `TEntityDisplayWrapperComponent`-gated display components. Likely fine at current
  unit counts; flag for later large-battle profiling.
- MISSING: No object pooling evidence for view-side particle effects (`ParticleEffect.create` / `queue_free` pattern in
  `main.gd:_attach_effect`, `_spawn_effects`) — CLAUDE.md's "pooled units, no per-frame allocations" decision covers the
  sim layer; the render/effect layer still allocates and frees particle nodes per event. Not necessarily wrong, but
  unverified against the stated performance decision.

---

## Top 15 by visibility

1. No sound at all — attack/hit/death/ability SFX, music, GUI sounds (`TSoundComponent`, `TGameSoundManagerComponent`).
2. No death dissolve/decay animation — units vanish instantly instead of fading out (`TUnitDecayManagerComponent`).
3. No generic mesh-effect system — frozen/petrified/ghosted/metal units never change appearance beyond particles
   (`TMeshEffectIce/Stone/Ghost/Metal/...`).
4. No status/buff icon stack above units — can't tell at a glance what's stunned/shielded/frozen
   (`TStateDisplayComponent`).
5. No camera shake on impacts/explosions (`TCameraShakerComponent`).
6. No cooldown/resource ring on the ability ground reticle while a timed ability is active
   (`TIndicatorCooldownCircleComponent`).
7. No weapon/projectile motion trails (`TVertexTraceComponent`).
8. No dynamic lights from muzzle flashes / explosions (`TPointLightComponent`).
9. No drag-select marquee for multiple units.
10. No minimap pings.
11. No AoE pattern / multi-point spell line preview while casting (`TSpelltargetVisualizerShowPatternComponent` /
    `...LineBetweenTargetsComponent`).
12. No in-world unit ability tooltip on hover (`TTooltipUnitAbilityComponent`).
13. Shield-block and other trigger-activated buff effects not wired (explicit TODO in `main.gd`).
14. Impact-point-anchored particle effects (`at_fire_target`) not wired (explicit TODO in `main.gd`).
15. No procedural secondary motion (idle sway, meteor arcs, spinning attachments) via positioner components.
