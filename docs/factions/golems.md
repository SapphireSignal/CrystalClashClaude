# Golems faction ("Colorless") spec

Extracted from `reference/rise-of-legions/Scripts/Units/Golems`, `Scripts/Spells/Golems`, `Scripts/Projectiles/Colorless`,
related Links/Modifiers, plus the Pascal component implementations. Numbers are exact. Use with `game/data/units.json`;
this doc explains what each group does. All Golems scripts set `eiColorIdentity = ecColorless` and carry `upGolem`.

## 0. Faction-wide mechanics

There is no faction resource. Three cross-cutting traits instead:
- **`upGolem`** is a marker only: no Pascal gameplay logic reads it except the sandbox commands
  (`Server.pas:3494-3512`: `ccClearUnits`/`ccClearSpawners`/`ccClearLaneTowers` exclude golems) and the client unit filter.
- **`upSpellImmune`** (SmallMeleeGolem only) is likewise script-level: every spell constraint lists `MustNotHave([... upSpellImmune])`
  (see section 2 and the Black spells). No Pascal special case.
- **Towers are cards**: `GolemsSmallGolemTowerBuilding.ets`, `GolemsMeleeGolemTowerBuilding.ets`, `GolemsBigGolemTowerBuilding.ets`
  use `BuildingCardTemplate.dws` (`InitBuildingCardData(Entity, False, Tier)`, pattern in `GROUP_DROP_SPAWNER`). The towers
  themselves use `InitBuildingData(Entity, True)` / `InitBuildingEntity(Entity, True)` = **90 000 ms lifetime** (`GROUP_BUILDING_LIFETIME`,
  `HelperScripts/BuildingTemplate.dws:8`). Note the Colorless (scenario) towers pass `False` = permanent.
- **Crystal links**: two units fight/buff through `Links\*` entities (`TWelaLinkEffectComponent`), not projectiles.
- Cards: 10 spawner cards (`*Spawner.ets`, squad sizes: SmallMelee 3, others as in `{@UBL_SpawnerSquadSize}`), 10 drop cards, 3 building cards,
  BossGolem spawner+drop (tier 3, `InitSpawnerData(Entity, False, 3)` — **not** flagged legendary at card level although the unit is `upLegendary`).

## 1. Units

Standard attack chain (referred to as "approach + melee/projectile chain"): `TBrainApproachComponent([0])` + `TWelaTargetingRadialAttentionComponent([0]).SetTargetTeamConstraint(tcEnemies)`;
`TBrainWelaFightComponent([1]).Preemptive` → `TWelaReadyCooldownComponent([1], true)` → `TWelaTargetingRadialComponent([1]) tcEnemies` →
constraints on `[0,1]`: `Event(eiDamageable)`, `MustNotHave([upInvisible, upBanished])`, melee also `BothMustHaveAny([upGround, upFlying])` →
`TWelaEffectInstantComponent` + `TWarheadSpottyDamageComponent` (melee) or `TWelaEffectProjectileComponent` (ranged).

### GolemsSmallMeleeGolem — T1 melee ground, spell immune
CollisionRadius `0.55`. `[upTier1, upUnit, upGround, upMelee, upGolem, upSpellImmune]`, `atLight`, HP `110`.
Group [0,1] range `1.0`; group 1 `dtMelee`, dmg `14`, CD `1700`, AP `533`, dur `1133`. SERVER: standard melee chain. **Plain melee; cannot be targeted by any spell.**

### GolemsMediumMeleeGolem — T2 melee ground (Tremor)
CollisionRadius `0.65`. `[upTier2, upUnit, upGround, upMelee, upGolem]`, `atMedium`, HP `205`.
Group [0,1] range `1.0`; group 1 `[dtMelee, dtSplash]`, dmg `32`, CD `2300`, AoE `6.0`, AoE-cone `3.141*0.25`, AP `533`, dur `1133`.
SERVER: standard melee targeting + `TWelaTargetConstraintEnemiesComponent([0,1])` → instant → `TWarheadSplashDamageComponent`.
**Every hit is a 45° cone cleave of 32 splash over radius 6.0 (long, narrow tremor line).**

### GolemsBigMeleeGolem — T3 melee ground (Splinter)
CollisionRadius `0.8`. `[upTier3, upUnit, upGround, upMelee, upGolem]`, `atHeavy`, HP `505`.
Group [0,1] range `1.0`; group 1 `dtMelee`, dmg `100`, CD `2800`, AP `466`, dur `1000`.
Group 2 Splinter: `eiWelaDamage 35.0` (damage threshold), CD `3000`; group 3 pattern `Projectiles\Colorless\SplinterProjectile`.
SERVER:
- **group 1**: standard melee chain.
- **group 2**: `TAutoBrainOnTakeDamageComponent([2]).FireSelfInGroup([2]).ThinksPassively` → `TWelaReadyCooldownComponent([2], True)` →
  `TWelaTriggerCheckTakeDamageThresholdComponent([2])` → `TWelaEffectFireComponent([2]).TargetGroup([3]).RedirectToGround.RandomizeGroundtarget(3.0, 4.0)` →
  group 3 `TWelaEffectProjectileComponent`. **Any single hit ≥ 35 damage (at most once per 3 s) lobs a stone to a random ground point 3–4 away (clamped to the walk zone); on landing it spawns one `GolemsSmallMeleeGolem` (see SplinterProjectile).**

### GolemsSmallRangedGolem — T1 ranged siege ground
CollisionRadius `0.4`. `[upTier1, upUnit, upGround, upRanged, upGolem]`, `atLight`, HP `46`.
Group [0,1] range `8.0`, pattern `SmallRangedGolemProjectile`; group 1 CD `1700`, `[dtRanged, dtSiege]`, dmg `15`, AP `100`, dur `333`.
SERVER: standard projectile chain (no `BothMustHaveAny`). **Siege pebble thrower.**

### GolemsSmallCasterGolem — T1 ranged ground supporter (Crystal Speed)
CollisionRadius `0.45`. `[upTier1, upUnit, upGround, upRanged, upGolem, upSupporter]`, `atLight`, HP `51`.
Group [0,1] range `8.0`, pattern `SmallCasterGolemProjectile`; group 1 CD `2800`, `dtRanged`, dmg `33` (no actionpoint/duration set).
Groups [2,3] Crystal Speed: targetcount `200`, `eiLinkPattern 'Links\CrystalSpeedLink'`, range `8.0`, `eiCooldown[3] 3000`.
SERVER:
- **group 1**: standard projectile chain.
- **group 2/3**: `TBrainWelaLinkComponent([2]).SetBuildCheckGroup([3]).ThinksPassivelyIfConscious()` → `TWelaReadyCooldownComponent([3], True)` →
  `TWelaTargetingRadialComponent([2]).SetValidateGroup([3]).SetTargetTeamConstraint(tcAllies).MaxNewTargetCount(1)` → group 2 `MustNotHave([upHasCrystalSpeed])` →
  [2,3] `NotSelf`, `MustHave([upUnit])` → `TWelaLinkEffectComponent([2,3])`.
  **Every 3 s links one more allied unit within 8 that is not yet buffed (max 200 links); each link applies `Links\CrystalSpeed.dws` (−30 % main-weapon cooldown) for as long as the link lives. Runs even while walking (passive-if-conscious).**

### GolemsBigCasterGolem — T3 ranged ground, beam weapon (Surefire, Intensify)
CollisionRadius `0.6`. `[upTier3, upUnit, upGround, upRanged, upImmuneToBlinded, upGolem, upLinkWeapon]`, `atLight`, HP `270`.
Group [0,1] range `8.0`, `eiLinkPattern[1] 'Links\BigCasterGolemLink'`, CD `500`, `dtRanged`, dmg `14`.
SERVER: approach + `TBrainWelaLinkComponent([1]).Preemptive` → radial `tcEnemies` → `[0,1]` `Event(eiDamageable)`, `MustNotHave([upInvisible, upBanished])` → `TWelaLinkEffectComponent([1])`.
**Instead of shooting it keeps one beam link on the nearest enemy; the link entity deals 14 every 500 ms, ramping ×1.5 per 3 s up to ×3 (see BigCasterGolemLink). Cannot be blinded.**

### GolemsSmallFlyingGolem — T1 ranged flying (Multishot 2)
CollisionRadius `0.6`. `[upTier1, upUnit, upFlying, upRanged, upGolem]`, `atMedium`, HP `97`.
Group [0,1] range `6.0`, pattern `SmallFlyingGolemProjectile`; group 1 `eiWelaTargetCount 2`, CD `2300`, `dtRanged`, dmg `29`.
SERVER: standard projectile chain. **Fires 29 at two different targets every 2.3 s.**

### GolemsBigFlyingGolem — T3 ranged flying (Multishot 3)
CollisionRadius `0.8`. `[upTier3, upUnit, upFlying, upRanged, upGolem]`, `atMedium`, HP `160`.
Group [0,1] range `6.0`, pattern `BigFlyingGolemProjectile`; group 1 `eiWelaTargetCount 3`, CD `2000`, `dtRanged`, dmg `63`.
SERVER: standard projectile chain. **63 at three targets every 2 s.**

### GolemsSiegeGolem — T2 melee ground (Crystal Artillery)
CollisionRadius `0.9`. `[upTier2, upUnit, upGround, upMelee, upGolem]`, `atMedium`, HP `270`, `reWelaCharge` start `0` cap `16`.
Group 1 melee: cost `reWelaCharge 1`, `[dtMelee, dtSiege]`, dmg `68`, range `0.5 + 1.0`, CD `2300`, AP `633`, dur `1033`.
Group 2 charge: range `20.0`, dmg `1.0`, CD `500`. Group 3 artillery: cost `reWelaCharge 16`, range `21.0`, pattern `SiegeGolemProjectile`, `[dtRanged, dtSiege]`, dmg `50`, AP `250`, dur `833`.
Group 4: cost `reWelaCharge 1`. Constraints [0,2,3]: `Event(eiDamageable)`, `MustHave([upBuilding]).MustNotHave([upInvisible, upBanished])`.
SERVER (order matters, the think chain stops at the first brain that acts):
- **group 1**: `TBrainWelaFightComponent.Preemptive` → cooldown → radial `tcEnemies` → `Event(eiDamageable)`, `BothMustHaveAny([upGround, upFlying])`, `MustNotHave([upInvisible, upBanished])` → instant → spotty damage → `TWelaEffectPayCostComponent.ConsumesAll().SetPayingGroupForType(reWelaCharge, [])`. **Melee hit of 68 siege; any melee swing dumps all stored charges.**
- **group 2**: `TBrainWelaFightComponent.ChangeTargetToMyself.Preemptive` → `TWelaReadyCooldownComponent(true)` → `TWelaReadyResourceCompareComponent.ComparedResource(reWelaCharge).CheckNotFull()` → radial `tcEnemies` (buildings only) → instant → `TWarheadSpottyResourceComponent.SetResourceType(reWelaCharge)` fired at itself. **While an enemy building is within 20, gains 1 charge every 500 ms (8 s to full).**
- **group 3**: `TBrainWelaFightComponent.Blocking` → `TWelaReadyCostComponent(reWelaCharge, [])` → radial `tcEnemies` (buildings) → `TWelaEffectProjectileComponent` → `TWelaEffectPayCostComponent.ConsumesAll()`. **At 16 charges stops and hurls a 50 siege stone at a building within 21, spending all charges.**
- **group 4**: `TBrainWelaSelftargetComponent([4])` + `TAutoBrainOnUnitPropertyComponent([4]).TriggerOn([upFrozen, upStunned, upBanished])` → `TWelaEffectPayCostComponent.ConsumesAll()`. **Reached only when no earlier brain acted (i.e. walking) or on freeze/stun/banish: all charges are lost.** No cooldown/ready check in this group.
Client: `TResourceDisplayProgressBarComponent` shows the charge bar.

### GolemsBossGolem — T3 legendary monumental melee (ground and air)
CollisionRadius `1.5`. `[upFlying, upGround, upMonumental, upUnit, upMelee, upLegendary, upTier3, upGolem]`, `atFortified`, HP `1900`.
Groups [1,2]: range `0.5 + 1.0`, `[dtMelee, dtSplash]`, dmg `370`, CD `2800`, AoE `5.0`, AoE-cone `3.141*0.9`; group 1 AP `1600` dur `2533` (vs ground), group 2 AP `1166` dur `2333` (vs air).
Group 3 Debut Asteroid: AoE `4.5`, dmg `100`, `[dtAbility, dtSplash]`, CD `500`.
Constraints [0,1,2]: `MustNotHave([upInvisible, upBanished])`, `Enemies`, `Event(eiDamageable)`.
SERVER:
- **group 2**: `TBrainWelaFightComponent.Blocking` → radial `tcEnemies` → `TWelaReadyUnitPropertyComponent([2]).MustHave([upGround])` (self check) → target `MustHave([upFlying]).MustNotHave([upBanished])` → instant → `TWarheadSplashDamageComponent`. Shared `TWelaReadyCooldownComponent([1,2], true)`.
- **group 1**: `TBrainWelaFightComponent.Preemptive` → radial → target `MustHave([upGround]).MustNotHave([upBanished])` → instant → `TWarheadSplashDamageComponent`.
  **162° cone cleave of 370 in radius 5 against ground (group 1) or flying (group 2) targets; one shared 2.8 s cooldown. Carries both `upGround` and `upFlying`, so both ground- and air-only attackers can hit it.**
- **group 3**: `TThinkImpulseTimerCooldownComponent([3])` → `TBrainWelaSelftargetGroundComponent([3]).ThinksLocal.ThinksPassively` → `Enemies` + `Event(eiDamageable)` → instant → `TWarheadSplashDamageComponent` → `TWelaEffectRemoveAfterUseComponent`. **500 ms after spawning, 100 splash in radius 4.5 around its landing point, once.**
Shared: `LegendarySpawn.dws PassIntValue(1600) ApplyToSelfAtCreate`; `TUnitPropertyComponent([], [upHasLegendaryUnit]).GivePropertyOwner()`. Client-only asteroid drop animation (1500 ms, hidden until 1400).

### GolemsSmallGolemTower — T1 ranged building (card)
`InitBuildingData(Entity, True)` (90 s). CollisionRadius `0.5`. `[upTier1, upGround, upBuilding, upRanged, upGolem]`, `atFortified`, HP `275`.
Group [0,1] range `11.0`, pattern `SmallGolemTowerProjectile`; group 1 CD `1500`, `dtRanged`, dmg `30`. SERVER: fight chain (no approach). **Static 30-dmg turret, range 11.**

### GolemsMeleeGolemTower — T2 melee building (card)
`InitBuildingData(Entity, True)`. CollisionRadius `0.75`. `[upTier2, upGround, upBuilding, upMelee, upGolem]`, `atFortified`, HP `770`.
Group 1: `dtMelee`, dmg `110`, AP `666`, dur `1033`; groups [1,2] range `0.5 + 1.0`, CD `1700`. Group 2: `[dtMelee, dtSplash]`, dmg `0.333 * 110`, AoE `2.0`, cone `3.141`, AP `466`, dur `866`.
SERVER: group 1 `TBrainWelaFightComponent.Preemptive` → radial `tcEnemies` → `TWelaTargetConstraintResourceComponent.CheckResource(reHealth).Comparator(coGreaterEqual).Reference(200.0).CompareCapToReference()` → `Event(eiDamageable)`, `BothMustHaveAny([upGround, upFlying])`, `MustNotHave([upInvisible, upBanished])` → instant → spotty damage.
Shared `TWelaReadyCooldownComponent([1,2], true)`. Group 2 `Preemptive` → radial → same constraints + `Enemies` → instant → `TWarheadSplashDamageComponent`.
**Big targets (max HP ≥ 200) get a 110 single punch; otherwise a 180° sweep of 36.63 splash in radius 2. One shared 1.7 s cooldown.**

### GolemsBigGolemTower — T3 ranged building (card, Multishot 2)
`InitBuildingData(Entity, True)`. CollisionRadius `0.85`. `[upTier3, upGround, upBuilding, upRanged, upGolem]`, `atFortified`, HP `570`.
Group [0,1] range `11.0`, pattern `BigGolemTowerProjectile`; group 1 targetcount `2`, CD `1700`, `dtRanged`, dmg `68`. SERVER: fight chain. **68 at two targets every 1.7 s.**

### Colorless (scenario) variants — `Scripts/Units/Colorless/*.ets`
Same component chains; only data differs. `SmallMeleeGolem`: no `upSpellImmune`, HP `68`, dmg `10`. `MediumMeleeGolem`: `atLight`, HP `190`, dmg `17`.
`BigMeleeGolem`: identical (Golems adds statistics only). `SmallRangedGolem`: `atUnarmored`, HP `34`, range `10.0`, `dtRanged` only, dmg `18`.
`SmallCasterGolem`: `atUnarmored`, HP `60`, dmg `26`, link `Links\CrystalPowerLink` (see section 3), `eiCooldown[3] 5000`, `ThinksPassively()`, `MustHave([upUnit]).MustNotHave([upHasCrystalPower])`.
`BigCasterGolem`: `atMedium`, HP `340`, dmg `21`. `SmallFlyingGolem`: `atUnarmored`, HP `105`, range `8.0`, single target, dmg `47`. `BigFlyingGolem`: HP `220`, range `8.0`, dmg `54`.
`SiegeGolem`: charge cap `100`, melee dmg `52`, charge tick `5.0` (so 10 s to full), artillery cost `100`. `BossGolem`: `eiSpeed 4/1000`, `eiAttentionrange[0..5] 18.0`, `atHeavy`, HP `4000`, range `2.5`, dmg `200`, CD `3000`, no asteroid/legendary spawn, group 1 uses `BothMustHaveAny`; plus `TBrainFleeComponent([3]).Range(30)` + `TBrainOverwatchComponent([3])` (holds position, returns if pulled > 30).
Towers: `InitBuildingData(Entity, False)` (permanent); SmallGolemTower HP `210` dmg `37`; MeleeGolemTower HP `655` dmg `150` CD `2800`; BigGolemTower HP `625` dmg `93` single target.

## 2. Spells

All use `PrepareSpellData` + `PrepareSpell` from `HelperScripts/SpellTemplate.dws` (cost formula, charge group, gold→wood refund, `TCommanderAbility`, `TWelaTargetConstraintZoneComponent(ZONE_WALK, False)`).

| Spell | Tier | Properties | Target | Cost delta |
|---|---|---|---|---|
| Cataclysm | 1 (epic) | `upEpic, upSpellArea, upSpellEnemy` | `ctCoordinate`, count 1 | fixed `reGold 400.0` (overridden, see below) |
| EchoesOfTheFuture | 1 | (none set) | `ctCoordinate`, count 1, but `OverrideTargetToOwner` | base; charge cooldown = base **×3** |
| Petrify | 2 | `upSpellArea, upSpellAlly` | `ctCoordinate`, count 1 | base **−30** |
| StoneCircle | 2 | `upSpellCharm, upSpellAlly` | `ctCoordinate`, count 1 | base **−10** |
| Earthquake | 3 (legendary) | `upLegendary, upSpellArea, upSpellEnemy` | `ctCoordinate`, count 1 | base(legendary) **−60** |

**Cataclysm.sps** — `PrepareEpicSpell` = `PrepareSpell(..., IsEpic = True)` (`SpellTemplate.dws:80`). Epic differences (`SpellTemplate.dws:38-66`): pay-cost `ConsumesAll`, `AddCharging` skipped (no recharge), `TWelaReadyCostComponent.CostsCap` (ready only when every cost resource is at its **cap**; `Shared.Wela.pas:1897` replaces each amount by the payer's cap, so the 400 is effectively "full gold bar + full charge"), targeting `TWelaTargetConstraintDynamicZoneComponent.SetZone([dzNexus])` + `TWelaTargetConstraintZoneComponent(ZONE_DROP, False)` instead of ZONE_WALK. SERVER: `TWelaEffectFactoryComponent.PassCardValues` + `TBrainWelaCommanderComponent`, pattern `Spells\Golems\Cataclysm`.
**Cataclysm.ets** — `eiCooldown[0,1] 500`, range `6.0`, targetcount `200`, `eiWelaModifier[0] 0.5`. `CreateMeta`: `TModifierWelaRangeComponent([0]).ScaleWithStage.AddModifier` (range = 6 + 0.5 × tier of `ServerGame.Commanders.First` — the *first* commander, `Shared.Wela.pas:2959-2966`; unusual); constraint `MustHaveAny([upUnit, upBuilding]).MustNotHave([upBase, upSpellImmune])`.
SERVER: `TThinkImpulseTimerCooldownComponent([0,1])` → group 0 `TBrainWelaFightComponent` → radial `tcAll` → instant → `TWarheadSpottyKillComponent.Exile`; group 1 `TBrainWelaTargetlessComponent` + `TWelaEffectSuicideComponent`.
**After 500 ms annihilates (exile, no death/soul) up to 200 units and buildings of both teams in radius 6 + 0.5·tier, then despawns. Only castable near the own nexus in the drop zone.**

**EchoesOfTheFuture.sps** — no unit pattern. `TWelaReadyUnitPropertyComponent([SpellGroup]).MustNotHave([upHasEchoesOfTheFuture])` (self/commander check). SERVER: `TBrainWelaCommanderComponent.OverrideTargetToOwner` → `TWelaEffectInstantComponent`; shared `TWarheadApplyScriptComponent(..., 'Spells\Golems\EchoesOfTheFuture.dws')` applied to the commander entity.
**EchoesOfTheFuture.dws** — `DOUBLE_DURATION 30000`; group `eiCooldown = 60000`. SERVER: `TThinkImpulseTimerComponent` + `TBrainWelaSelftargetComponent.ThinksPassively` + `TAutoBrainBuffComponent([btPositive])` + `TWelaReadyCooldownComponent(False)` + `TWelaEffectRemoveAfterUseComponent`. Shared: `TUnitPropertyComponent([upHasEchoesOfTheFuture])`, `TCommanderIncomeLoanComponent.Factor(2.0).Duration(30000)`.
**Gold income ×2 for 30 s, then ×0 for the next 30 s (loan payback); can't be recast while active (60 s).**

**Petrify.sps** — factory spawning `Spells\Golems\Petrify`; `upSpellAlly` (cast on own units for the overheal, but targets `tcAll`).
**Petrify.ets** — range `4.0`, targetcount `16`. `CreateMeta`: group 1 `MustHaveAny([upUnit, upBuilding]).MustNotHave([upLegendary, upBase, upSpellImmune])`; group 2 `MustNotHave([upImmuneToPetrified, upImmuneToStateEffects])`; `TWelaTargetConstraintBooleanComponent.GroupA([1]).GroupB([2]).OperatorAnd` into group []. SERVER: `TThinkImpulseOnceComponent` → `TBrainWelaFightComponent` → radial `tcAll` → instant → suicide; shared `Modifiers\Petrified.dws`.
**Petrifies up to 16 units/buildings of both teams in radius 4 (12 s stone + 10 HP/s overheal), then vanishes.**

**StoneCircle.sps** — factory spawning `Spells\Golems\StoneCircle`.
**StoneCircle.ets** (charm field) — CollisionRadius `4.5`, `[upCharm]`, `reWelaCharge` `10/10`. Group 0: cost `reWelaCharge 1`, targetcount `1`, CD `2000`, range `4.5`. Groups [4,5]: range `4.5`, targetcount `200`, `eiLinkPattern 'Links\SpellshieldAura'`. [6,7] dmg `1.0`; group 8 range `10000.0`.
`CreateMeta`: group 0 `Allies` + `MustHave([upUnit, upMelee]).MustNotHave([upBlessedStonefist])`. SERVER: `TCollisionComponent` + `TPositionComponent` + `TThinkImpulseTimerComponent`.
- group 0: `TBrainWelaFightComponent.DisableTargetLock()` → cooldown(true) → `TWelaReadyCostComponent.SetPayingGroupForType(reWelaCharge, [])` → radial `.IgnoreOwnCollisionradius.SetTargetTeamConstraint(tcAllies).PicksRandomTargets` → `NotSelf` → instant → pay cost → shared `Modifiers\BlessingStonefist.dws`. **Every 2 s enchants one random allied melee unit in radius 4.5 with Stonefist (+15 flat damage), 10 charges.**
- group 1: `TWelaEffectFireComponent([0]).TargetGroup([1]).RedirectToSelf` → `TWelaReadyResourceCompareComponent(reWelaCharge).CheckEmpty` → suicide. **Dies after 10 enchantments.**
- groups 4/5: `TBrainWelaLinkComponent([4]).ThinksPassively()` → radial `.IgnoreOwnCollisionradius.SetValidateGroup([5]).SetTargetTeamConstraint(tcAllies)` → group 4 `MustNotHave([upSpellshieldAuraBuffed])`, [4,5] `MustHaveAny([upUnit, upBuilding])` → `TWelaLinkEffectComponent([4,5])`. **Up to 200 `SpellshieldAura` links: allied units/buildings in radius 4.5 take only 20 % from `dtSpell`/`dtAbility`.**
- group 8 / groups 6,7: identical charm-cap bookkeeping to Black's OnTheEdge (`reCharmCount` +1 on create, −1 on free, oldest charm removed when the cap is full).

**Earthquake.sps** — `PrepareSpellData(..., True, 3)` (legendary), factory spawning `Spells\Golems\Earthquake`.
**Earthquake.ets** — `[upLegendary]`, `reWelaCharge` `6/6`. Group 1: cost `reWelaCharge 1`, CD `5000`, AoE `8.0`, dmg `35`, `[dtSiege, dtSpell, dtSplash]`. Group 2: range `8.0`, targetcount `200`.
`CreateMeta`: group 1 `Enemies`, `Event(eiDamageable)`, `MustNotHave([upBanished, upSpellImmune])`, `MustHave([upGround])`; group 2 `MustHave([upUnit, upGround]).MustNotHave([upLegendary, upNoAutoAttack, upImmuneToStateEffects])` + `Enemies`.
SERVER: `TStatisticsUnitComponent` (stats only); `TThinkImpulseTimerCooldownComponent([1,2,3]).TimerIsReady` → group 1 `TBrainWelaSelftargetGroundComponent` → `TWelaReadyCostComponent.SetPayingGroup([])` → `TWelaEffectPayCostComponent.SetPayingGroup([])` → instant → `TWarheadSplashDamageComponent`; group 2 `TBrainWelaFightComponent` → radial `tcEnemies` → instant → shared `Modifiers\Stun.dws`; group 3 `TBrainWelaSelftargetComponent` → `TWelaReadyResourceCompareComponent(reWelaCharge).CheckEmpty` → suicide. Shared `TUnitPropertyComponent([], [upHasLegendaryUnit]).GivePropertyOwner()`.
**Six waves, one immediately and then every 5 s: 35 siege-spell splash to enemy ground units/buildings in radius 8 and a 3 s stun on up to 200 enemy ground units; field dies after the 6th wave. Counts as the player's legendary.**

## 3. Referenced Modifiers / Links / Projectiles

- **`Links\CrystalSpeedLink.ets`** — no data; SERVER `TWarheadLinkApplyScriptComponent([], 'Links\CrystalSpeed.dws')`.
  **`Links\CrystalSpeed.dws`** (returns its group) — `eiWelaModifier 0.7`; `TModifierMultiplyCooldownComponent([GROUP_MAINWEAPON, Group]).SetValueGroup([Group])`; `[upHasCrystalSpeed]`. **Main weapon cooldown ×0.7 while linked.**
- **`Links\BigCasterGolemLink.ets`** — `reWelaCharge` start `1` cap `3`; `eiWelaModifier[1] 1.5`; `eiWelaDamage[2] 1.0`; `eiCooldown[2] 3000`. SERVER: `TLinkBrainComponent([0])` (fires at `eiLinkDest` every `eiCooldown[0]` = the owner's 500 ms copied into the link) → instant → `TWarheadSpottyDamageComponent` with `TModifierWelaDamageComponent([0]).Multiply.ScaleWithResource(reWelaCharge).SetValueGroup([1])`; group 2 `TThinkImpulseTimerComponent` → `TBrainWelaSelftargetComponent` → cooldown(False) → `CheckNotFull` → +1 `reWelaCharge`. **14 × 1.5 × charge every 500 ms: 21 / 42 / 63 dmg after 0 / 3 / 6 s on the same target; resets when the link breaks.**
- **`Links\SpellshieldAura.ets` + `Links\Spellshield.dws`** — `eiWelaModifier 0.2`; `TBuffTakenDamageMultiplierComponent.DamageTypeMustHaveAny([dtSpell, dtAbility])`; `[upSpellshieldAuraBuffed]`. **−80 % spell/ability damage taken.**
- **`Links\CrystalPowerLink.ets` + `Links\CrystalPower.dws`** (Colorless SmallCasterGolem only) — `[upHasCrystalPower]`; `TAutoBrainOnDealDamageComponent([GROUP_MAINWEAPON, Group]).FireInGroup([PowerGroup])` → instant → `TWarheadApplyScriptComponent(PowerGroup, 'Modifiers\CrystalPowerSpark.dws').PassValueFromEvent(eiTeamID).PassDirectionToTarget()`; `TAutoBrainOnWelaShotProjectileComponent([ProjectileGroup])` → instant → `TWarheadApplyScriptComponent(ProjectileGroup, 'Modifiers\CrystalPowerFireSpark.dws')` (gives the projectile the same on-damage spark, passing `eiTeamID` and `eiFront`).
  **`Modifiers\CrystalPowerSpark.dws(TeamID, Front)`** — one-shot group: dmg `20`, range `11.0`, pattern `Projectiles\Colorless\CrystalPowerProjectile`, `dtRanged`; `TBrainWelaFightComponent.ThinksPassively.ThinksLocal` → `TWelaTargetingRadialComponent.Cone(Front, PI/4).PrioritizeMiddleDistant.SetTargetTeamConstraint(tcAll)` → `NotSelf` → `TWelaTargetConstraintTeamIDComponent.SetTargetTeam(TeamID).Invert` → `Event(eiDamageable)` → projectile → `TThinkImpulseNowComponent`; then `Entity.RemoveGroups([Group])`. **Whenever the linked unit's main weapon damages something, a 20-dmg spark flies from the victim to another enemy (of the linked unit's team) within 11 in a 45° cone behind it, preferring mid-range.**
- **`Modifiers\BlessingStonefist.dws`** — `eiWelaModifier 15.0`; `TAutoBrainBuffComponent([btPositive])` + `TWelaEffectRemoveAfterUseComponent`; `[upBlessed, upBlessedStonefist]`; `TModifierWelaDamageComponent([0, 1, Group]).SetValueGroup([Group])` (additive). **+15 main-weapon damage, permanent.**
- **`Modifiers\Petrified.dws`** — `DEFAULT_DURATION 12000`, immunity `22000`, HoT tick `1000`, `eiWelaDamage[HoT] 10.0`, `[dtHoT, dtOverheal]`. Structure as Frozen (`btNegative, btState`, `TWelaHelperBeaconComponent.TriggerAt([upPetrified])`, `[upHasStateEffect, upPetrified]` → `[upImmuneToPetrified]`); HoT group: selftarget passive → cooldown → `MustNotHave([upUnhealable])` → `TWarheadSpottyHealComponent`. **12 s stone (can't act), healed/overhealed 10 per second, then 10 s immunity.**
- **`Modifiers\Stun.dws`** — `STUN_DURATION 3000`, `[btNegative, btState]`, `[upHasStateEffect, upStunned]`. No immunity group.
- **`Modifiers\LegendarySpawn.dws`** — BossGolem `1600`, splinter-spawned SmallMeleeGolems `500`.
- **Projectiles** (all: `TMovementComponent`, `TBrainProjectileComponent([0])`, instant + `TWarheadSpottyDamageComponent` unless noted):
  - `SmallRangedGolemProjectile` `28/1000`; `SmallCasterGolemProjectile` `14/1000`; `SmallFlyingGolemProjectile` `14/1000`; `BigFlyingGolemProjectile` `30/1000`;
    `SmallGolemTowerProjectile` `14/1000`; `BigGolemTowerProjectile` `30/1000`; `SiegeGolemProjectile` `12/1000`; `CrystalPowerProjectile` `14/1000`.
  - `SplinterProjectile` speed `3/1000`, `eiWelaUnitPattern[0] 'Units\Golems\GolemsSmallMeleeGolem'`; SERVER `TWelaEffectFactoryComponent([0]).PassCardValues` (no damage); shared `LegendarySpawn.dws PassIntValue(500) ApplyToProducedUnits`. **Slow lob that spawns one Small Melee Golem at the impact point.**
  - Scenario-only: `BossSiegeGolemAttackProjectile` `24/1000` (+`Enemies`, `Event(eiDamageable)`), `GolemLaneTowerLevel1Projectile` `14/1000`, `Level2/3` `30/1000` (used by `Units\Scenario\GolemLaneTower*`).

## 4. Component semantics (Pascal) — not yet in `wela.gd` / `buff.gd`

**`TCommanderIncomeLoanComponent`** (`Shared.pas:553`, `:2559-2571`) — hooks `eiReadIncome` for the owning commander. While the timer (`Duration`) runs: `Income.Gold *= Factor`. On the first income read after expiry: restart the timer with `Interval * Factor / 2` and set `Factor := 0`, so gold income is ×0 for that payback window (Echoes: ×2 for 30 s, then ×0 for 30 s). Wood is untouched.

**`TLinkBrainComponent`** (`Server.pas:150`, `:1538-1580`) — lives on the link entity. First idle: reads `eiCooldown` of its group, starts a timer; `FiresAtCreate` optional. Each expiry fires `eiFire` at `eiLinkDest` (up to 50 catch-up times) if `eiIsReady` and `eiWelaTargetPossible`; `FiresAtSources` also fires at `eiLinkSource`. BigCasterGolemLink group 0 has no own `eiCooldown`; the link reads the values copied from the creating wela (dmg 14, CD 500, dtRanged).

**`TWarheadLinkApplyScriptComponent`** (`Shared.Wela.pas:918`, `:2580-2610`) — `OnAfterCreate`: applies the `.dws` `Apply` function to `eiLinkDest[0]` if `eiWelaTargetPossible` on its group, stores the returned groups, writes `eiCreator`/`eiCreatorGroup` into them. `BeforeComponentFree` (link broken/dies) triggers `eiRemoveComponentGroup` for those groups → **buff lasts exactly as long as the link**. `OnReplaceEntity` removes the groups from the replaced entity too.

**`TAutoBrainOnWelaShotProjectileComponent`** (`Server.Brains.pas:572`, `:2858`) — on `eiWelaShotProjectile` fires `eiFire` with the projectile entity as target (if ready and target-possible). Used to hand the CrystalPower spark ability to each projectile.

**`TWelaTargetConstraintTeamIDComponent`** (`Shared.Wela.pas:395`, `:1453`) — target valid iff `TeamID = SetTargetTeam` (or `<>` with `Invert`). Needed because the spark's owner is the *victim*, so `tcEnemies` would be wrong.

**`TThinkImpulseNowComponent`** (`Server.Brains.pas:2845`) — constructor immediately triggers `eiThink` + `eiThinkChain` on its group (unless exiled). Fire-and-forget one-shot welas.

**`TBrainWelaTargetlessComponent`** (`Server.Brains.pas:397`) — fires its group with an empty target whenever thinking and ready (used with `TWelaEffectSuicideComponent`).

**Fluent options not yet handled**:
- `TBrainWelaFightComponent.ChangeTargetToMyself` (`Brains.pas:1394`, `:1444`): still targets normally but every `eiFire` is sent with the owner as target (SiegeGolem charging).
- `TBrainWelaLinkComponent.SetBuildCheckGroup(G)` (`:1346`, `:1377-1388`): new links are established only when `FLinkTimer` (250 ms `DEFAULT_LINK_BUILD_TIME`) expired **and** group G is ready; fire goes to `ComponentGroup + G` so G's cooldown restarts (SmallCasterGolem: one new link per 3 s).
- `TBrainComponent.ThinksPassivelyIfConscious` (`:2104-2114`): like `ThinksPassively` — thinks in `eiThink` (not in the chain), so it runs while moving/fighting.
- `TWelaTargetingRadialComponent.MaxNewTargetCount(n)` (`Welas.pas:1169`, `:1709`): at most n new targets per targeting pass; `.Cone(Dir, Angle)` (`:1653`, `:1724-1731`): candidate rejected if the angle between `Dir` and the target direction minus the target's angular width exceeds `Angle/2`; `.PrioritizeMiddleDistant` (`:1770`): sort by `|distance − range/2|` ascending.
- `TWelaEffectFireComponent.RedirectToGround.RandomizeGroundtarget(min, max)` (`:2859-2865`, `:2891`): replaces the target by `TargetPos + random-rotated vector of length min + random·(max−min)`, clamped to `ZONE_WALK`; bypasses `eiWelaTargetPossible` of the target group (`:2828`).
- `TModifierWelaDamageComponent.Multiply.ScaleWithResource(R)` (`Shared.Wela.pas:1058-1085`): `Factor = eiWelaModifier[ValueGroup] × Balance(R)`; `Multiply` → `damage × Factor` (default additive). Port has `Multiply`/`ScaleWithResource` for other classes; verify this combo.
- `TModifierWelaRangeComponent.ScaleWithStage` (`:2959-2966`): `Factor *= Balance(reTier)` of `ServerGame.Commanders.First` (not the caster).
- `TBrainWelaCommanderComponent.OverrideTargetToOwner` (`Brains.pas:1186`): ability is used with the commander entity as target regardless of the clicked coordinate.
- `TWarheadApplyScriptComponent.PassValueFromEvent(eiTeamID|eiFront)` / `PassDirectionToTarget` (`Shared.Wela.pas:2445-2480`): extra `Apply` parameters — team id (public event), owner front, or normalized owner→target direction.
- Epic spells (`SpellTemplate.dws:38-66`): `TWelaReadyCostComponent.CostsCap` (`Shared.Wela.pas:1897`), pay `ConsumesAll`, no charge regeneration, target zone `dzNexus` ∧ `ZONE_DROP`.

Unusual script features: `GolemsBossGolem` builds its spawn animation arrays with `random` in `CreateEntity` (client only); `CrystalPowerSpark.dws` calls `Entity.RemoveGroups([Group])` inside `Apply` after `TThinkImpulseNowComponent`; `CrystalSpeed.dws`/`Spellshield.dws`/`CrystalPower.dws` are `function Apply(...) : array of integer` (return groups for link removal); `EchoesOfTheFuture.dws` uses a `const` inside `Apply`; every unit uses `{@UBL_*}` league arrays (`Health`, `Damage`, `Cooldown`, `Range`, `Armortype`) and spells `{@SBL_Tier}`; MeleeGolemTower/BossGolem/SiegeGolem compute range as `0.5 + {@UBL_Range}1.0`; MeleeGolemTower cone damage is `0.333 * {@UBL_Damage}110.0`.
