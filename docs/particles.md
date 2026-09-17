# Particle effects (.pfx) — original format and semantics

Ground truth: `reference/delphi3d-engine/Engine/Engine.ParticleEffects*.pas` (root `.pas`, `.Types`, `.Emitters`,
`.Simulators`, `.Particles`) and `reference/rise-of-legions/Graphics/Effects/ParticleEffects/**/*.pfx` (366 XML
files, same `HXMLSerializer` format as the maps: German decimal commas, `identifier` back-references).
Game usage: `BaseConflict.EntityComponents.Client.Visuals.pas` `TParticleEffectComponent` (lines ~3590-4039).

## File structure
Root `TParticleEffectPattern`: `FEmitter` (list of `TParticleEmitter`), `FSimulationData` (list of
`TPatternSimulationData`, referenced by `identifier`), `FTrigger` (list of triggers referencing emitters).

`TParticleEmitter` (Emitters.pas:24-76): `FPosition`, `FFront`, `FUp` (emitter frame relative to the effect),
`FSize` (unused), `FRotation` (RVariedVector3, pitch/yaw/roll per particle; negative variance = sweep across the
burst), `FParticleType` (`ptPointsprite`, `ptQuad`, `ptLight`, `ptEffect`, `ptTrace`), `FEmissionCount`, `FTimes`
(repeat the burst), `FStartingOffset` (ms, negative variance = swept), `FSimulationData` (ref),
`FStickToEmitter`, `FDieWithEmitter`, `FEmittedEffect` (nested .pfx for `ptEffect`), `FParticleTexture`
(`BlendMode`, `IgnoreZ`, `Softparticle`, `AlphaSubtraction`, `TextureFileName`, `NormalMapFileName`,
`DrawOrder`), `FTextureAtlasSize` (cols, rows: a random cell picked once at spawn, not animated).

Blend modes (Types.pas:15): `pbAdditive` (srcAlpha/ONE), `pbLinear` (alpha blend), `pbSubtractive`
(srcAlpha/ONE reverse subtract), `pbGlow` (alpha blend into the bloom buffer), `pbDistortion` (screen distortion
buffer), `pbShaded` (deferred-lit, 7 uses only).

Randomised values: `RVariedSingle{Mean,Variance}` -> `Mean + (Random*2-1)*Variance`; `RVariedVector3` adds
`FRadialVaried` (`Mean + RandomPointInSphere(Variance.X)`); negative variance at rotation / time offset / node
values = deterministic sweep with the particle's `FixedRandomFactor` (index within the burst), so a particle's
whole path stays coherent (`GetRandomVectorSpecial`, Engine.Math.pas:3981).

## Path simulation (`TPathPatternSimulationData` -> `TParticlePath` -> `RParticlePathNode` list)
Per node: `ParticlePattern` {`Rotation` (RVariedVector3), `Front`, `Up`, `Size` (RVariedVector3, x = width,
y = height), `Color` (RVariedVector4 rgba)}, `InterpolationScheme` (`isLinear`, `isHermite`, `is*TangentFront`,
`is*TangentUp`), `Position` (RVariedVector3, offset relative to the previous node, chained into absolute
positions at spawn, scaled by the effect size), `Tangent1/2` (Hermite), `PathTime` (ms to the next node; the
last node's time is unused). Life = sum of PathTimes; each frame the node segment is found and everything is
lerped (Hermite spline for `isHermite*` positions; `*TangentFront/Up` derive Front/Up from the travel
direction). Before the spawn offset the scale is 0. `TPhysicalPatternSimulationData` exists but no shipped
.pfx uses it.

Triggers: `TInstantEmissionTrigger` (668: burst on start), `TIntervalEmissionTrigger` (157: `FInterval` ms,
continuous while emitting, max 40 emits/s), `TDistanceEmissionTrigger` (52: every `EmitDistance` units of
parent travel).

## Rendering (Particles.pas:151-238)
Quads of 6 vertices. Orientation from the node's Front/Up: both zero (or `ptPointsprite`) = full billboard;
Front zero + Up set = cylindrical billboard around Up (most common); Up zero + Front set = symmetric; both set =
fixed quad. Then the node `Rotation` (z roll, then y, x) via `RotateAxis`. Batches by texture + blend mode +
`DrawOrder`; no per-particle depth sort. Soft particles fade near geometry (depth buffer). `ptLight` spawns a
point light (colour + scaling = range), `ptTrace` a `TVertexTrace` ribbon, `ptEffect` a nested effect.

## Game usage
`TParticleEffectComponent.CreateGrouped(Entity, groups, path, SizeNormalization)`; final uniform scale =
`(event scale, default 1) * (eiModelSize unless IgnoreModelSize) * (eiSize unless IgnoreSize) / SizeNormalization`
(Visuals.pas:2520-2543, 3750). Paths with `%d` are formatted with the displayed team id (`ShowAsTeam` fixes
it). Activation: `ActivateOnCreate` (after deserialisation), `ActivateOnFire` / `OnPreFire` / `OnFireWarhead` /
`OnFireDelayed(ms)`, `ActivateOnDie`, `ActivateOnLose` (own team lost), `ActivateOnFree`, `ActivateOnWelaActivate`
(while the ability is active); `Deactivate*` variants stop emission. `BindToSubPositionGroup(zone, groups)`
attaches to a bind zone bone, `EmitFromAllBones` clones per bone, `AtFireTarget` / `ClonesToTarget` place the
effect at the fire target. Examples: Footman `\White\shield_block.pfx` (1.7, on create, scaled with the
collision radius, bound to `BIND_ZONE_CENTER`, visible while the wela is ready) and
`\White\footman_shield_block_trigger.pfx` (1.0, on fire, IgnoreModelSize); LightPulse `\White\light_pulse_cast.pfx`
(6.0) + `\White\white_border_wide_once.pfx` (5.0); soul donor `\Shared\energy_trail.pfx` (4.0). The Archer has no
particle component (mesh arrow only).

## Counts
366 files; emitters by type: `ptQuad` 387, `ptPointsprite` 374, `ptLight` 100, `ptTrace` 10, `ptEffect` 5;
blend modes: additive 578, linear 168, distortion 102, subtractive 18, shaded 7, glow 5; interpolation:
linear 1927, hermite 256, tangent variants 38.

## Port plan
A Python converter reads the XML into a compact JSON per effect (emitters, path nodes, triggers, textures) and
copies the textures; Godot plays them with a custom CPU particle node (path evaluation per particle, the same
random rules with a per-effect RNG, billboard quads via a MultiMesh per emitter, blend mode materials:
additive / mix / subtract; glow as additive, distortion skipped at first). Effects attach to units via the
extractor (`TParticleEffectComponent` chains -> `units.json` `effects`).
