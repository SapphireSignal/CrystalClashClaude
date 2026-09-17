# Black faction ("Void") spec

Extracted from `reference/rise-of-legions/Scripts/Units/Black`, `Scripts/Spells/Black`, related Modifiers,
Links and Projectiles, plus the Pascal component implementations. Numbers are exact. Use with
`game/data/units.json` (the components are already extracted there); this doc explains what each group does.

## 0. The soul mechanic (global, `GROUP_SOUL = 11`)

Souls are stored in **`reMana`** (no `reSoul`); 1 soul = 1 mana. `UnitTemplate.dws` gives every unit group 11:
`TAutoBrainOnDeathComponent.FireAtGround` → `MustNotHave([upSoulless])` → `TWelaEffectFactoryComponent.PassCardValues`
spawning `Projectiles\Black\SoulGatherProjectileSpawner` at the corpse (`BuildingTemplate.dws`: `eiWelaRange[11] = 12.0`).

`SoulGatherProjectileSpawner.ets` — group 0: dmg `1.0`, targetcount `1`, range `12.0`, pattern
`SoulGatherProjectile`; `TThinkImpulseOnceComponent.WaitOneFrame` → fight → radial `tcAll` priority `tcAllies`
`PicksRandomTargets` → `MustHave([upSoulGatherer])` → `CheckResource(reMana).CheckNotFull()` → projectile → suicide.
**One soul from any dying unit flies to one random non-full `upSoulGatherer` within 12; allies preferred, enemies eligible.**
`SoulGatherProjectile.ets` speed `10/1000`, on impact `TWarheadSpottyResourceComponent(reMana)` +1.
`SoulDonorProjectile` identical; `VoidGatherProjectile` (speed 10/1000) used reversed (target → Tyrus);
`VoidGatherProjectileTyrus` speed `(3 + random*3)/1000`.
Gatherers (`upSoulGatherer`): VoidBane cap 14, VoidSkeleton 1, VoidCauldron 15, FrostgoyleFountain 8, Tyrus 20,
VoidAltar 10. VoidWraith has mana 12 (start 6) but is not a gatherer. `upSoulDonor` = excluded from receiving;
`upSoulless` = releases no soul.

## 1. Units

### VoidBane (`VoidBane.ets`) — T1 melee ground
CollisionRadius `0.7`. `[upTier1, upUnit, upGround, upMelee, upSoulGatherer, upHasDeathRattle]`, `atUnarmored`, HP `190`, `reMana` cap `14` start `0`.
Group [0,1] range `1.5`. Group 1: `dtMelee, dtSplash`, dmg `27`, CD `2300`, AoE `2.5`, AoE-cone `3.141*0.9`, AP `333`, dur `1133`.
Group 2 (Reaper): `eiWelaDamage = 15.0` (max-HP gained per soul).
Group 3 (Death Rattle Soul Donor): `eiWelaTargetCount 0` + modifier `1` (×mana), range `8.0`, pattern `SoulDonorProjectileVoidBane`, dmg `1.0`, `dtIrredirectable`.
SERVER:
- **group 1**: fight `Preemptive` → cooldown(true) → radial `tcEnemies` → constraints [0,1]: `Enemies`, `Event(eiDamageable)`, `BothMustHaveAny([upGround, upFlying])`, `MustNotHave([upInvisible, upBanished])` → instant → `TWarheadSplashDamageComponent`. **Cone cleave: 27 splash in radius 2.5 over a 162° cone.**
- **group 2**: `TAutoBrainOnResourceComponent.TriggerOn([reMana]).TimesForEach` → instant → `TWarheadSpottyResourceComponent.SetResourceType(reHealth).ChangesMax`. **Each stored soul permanently raises max HP by 15.**
- **group 3**: `TAutoBrainOnBeforeDeath.FireAtTarget()` → `MustNotHave([upSilenced])` → radial `tcAllies.PicksRandomTargetsWithRepetition()` → `NotSelf` → `MustNotHave([upSoulDonor])` → `CheckResource(reMana).CheckNotFull()` → `TModifierWelaTargetCountComponent.ScaleWithResource(reMana)` → projectile. **On death, one soul-donor projectile per stored soul to random non-full allied gatherers within 8.**

### VoidBowman (`VoidBowman.ets`) — T1 ranged ground
CollisionRadius `0.45`. `[upTier1, upUnit, upGround, upRanged]`, `atUnarmored`, HP `60`.
Group [0,1] range `8.0`, pattern `VoidBowmanProjectile`; group 1 CD `1700`, `dtRanged`, dmg `20`, AP `366`, dur `1200`.
SERVER: standard approach + projectile chain (`MustNotHave([upInvisible, upBanished])`, `Event(eiDamageable)`).
Shared group 2: `TWarheadApplyScriptComponent([2],'Modifiers\BlessingGrievousWounds.dws').ApplyToSelfAtCreate.Methodname('ApplyWithoutEffect')` — **permanently enchanted with Grievous Wounds at spawn (hits apply/stack Bleeding, max once per 1000 ms).**

### VoidSkeleton (`VoidSkeleton.ets`) — T1 melee ground
CollisionRadius `0.45`. `[upTier1, upUnit, upGround, upMelee, upHasUndying, upSoulGatherer]`, `atUnarmored`, HP `105`, `reMana` cap `1` start `0`.
Group [0,1] range `1.0`; group 1 `dtMelee`, dmg `16`, CD `1700`, AP `266`, dur `933`. Relentless: `eiWelaModifier[2] = 1.5` (vs impaired), `[3] = 2.0` (vs frozen). Group 4: `eiResourceCost[4] reMana = 1`.
SERVER:
- **group 1**: standard melee (`BothMustHaveAny([upGround, upFlying])`, `MustNotHave([upInvisible, upBanished])`) → instant → spotty damage.
- **Relentless**: `TModifierMultiplyDealtDamageComponent([1]).MustNotHave([dtSpell]).CheckWelaConstraint.SetValueGroup([2])` gated by group 2 `MustHaveAny([upStunned, upBlinded, upRooted, upGrounded, upLifted, upBleeding, upPetrified]).MustNotHave([upFrozen])` → ×1.5; second one `SetValueGroup([3])` gated by `MustHave([upFrozen])` → ×2.0.
- **group 4 (Undying)**: `TAutoBrainPreventDeathComponent` → `MustNotHave([upSilenced, upRescued])` → `TWelaReadyCostComponent.SetPayingGroup([])` → instant → `TWelaEffectRemoveAfterUseComponent.TargetGroup([4])`; shared `TWarheadApplyScriptComponent([4],'Modifiers\Undying.dws')`.
**Consumes its 1 soul to cancel death, fully heal and become Undying for 15 s, then dies anyway.**

### VoidWorm (`VoidWorm.ets`) — T1 ranged ground, ground-only
CollisionRadius `0.6`. `[upTier1,upUnit,upGround,upRanged,upRangedGroundOnly,upHasDeathRattle]`, `atLight`, HP `100`. Card A4/D3/U3.
[0,1] range `5.0`, pattern `Projectiles\Black\VoidwormProjectile`; group 1 CD `1700`, `dtRanged`, dmg `40`, AP `250`, dur `666`. Death Rattle [2,3] range `2.0`; `eiWelaTargetCount[2] = 200`.
SERVER: approach + projectile attack chain; plus `TWelaEfficiencyUnitPropertyComponent.CreateGrouped([1]).Prioritize([upImmuneToFrozen,upLegendary,upBuilding,upImmuneToStateEffects]).Reverse` — **deprioritizes targets that can't be frozen.**
- **group 2 (Death Rattle Frostexplosion)**: `TAutoBrainOnBeforeDeath.FireAtTarget` → radial `tcEnemies` → `BothMustHaveAny([upGround,upFlying])` → `Event(eiDamageable)` → `MustHave([upUnit]).MustNotHave([upImmuneToFrozen,upLegendary,upImmuneToStateEffects])` → stats → `TWelaEffectInstantComponent` → shared `TWarheadApplyScriptComponent([2],'Modifiers\Frozen.dws')`. **Freezes up to 200 enemy units within 2.0 on death.**
- **group 3**: `TAutoBrainOnBeforeDeath.FireAtSelf` (VFX/SFX only).

### Frostgoyle (`Frostgoyle.ets`) — T2 melee flying (token, summoned by Fountain)
CollisionRadius `0.7`. `[upTier2,upUnit,upMelee,upFlying]`, `atUnarmored`, HP `155`.
[0,1] range `1.0`; group 1 `dtMelee`, dmg `75`, CD `3600`, AP `400`, dur `700`. Group 2 modifier `1.5`, group 3 modifier `2.0`.
SERVER: approach + melee; **Fury**: `TWelaEffectFireComponent([1]).TargetGroup([4])` → group 4 `TWelaTargetConstraintResourceComponent.CheckResource(reHealth).CheckFull` → `TWelaEffectFireComponent([4]).TargetGroup([5]).RedirectToSelf` → `TWelaEffectResetCooldownComponent([5]).TargetGroup([1]).Expire`. **If the struck enemy was at full HP, the 3600 ms attack cooldown is immediately reset.** Then `TWelaEffectInstantComponent` + `TWarheadSpottyDamageComponent`, stats `'Melee'/'Flying'`. Relentless multipliers identical to VoidSkeleton (groups 2/3).

### VoidCauldron (`VoidCauldron.ets`) — T2 ranged siege ground
CollisionRadius `0.6`. `[upTier2,upUnit,upGround,upRanged,upSoulGatherer,upHasDeathRattle]`, `atHeavy`, HP `285`, `reMana` cap `15`.
[0,1] range `3.0`, pattern `VoidCauldronProjectile`; group 1 CD `2800`, `[dtRanged,dtSiege]`, dmg `60`, AP `200`, dur `500`.
Group 2 (Death Rattle Blast): range `14.0`, pattern `VoidCauldronBuildingBlastProjectile`, `[dtRanged,dtSiege,dtAbility]`, dmg `15`, targetcount `0` + modifier `1` (×mana).
SERVER group 2: `TAutoBrainOnBeforeDeath.FireAtTarget()` → `MustNotHave([upSilenced])` → `TWelaReadyResourceCompareComponent.ComparedResource(reMana).CheckNotEmpty` → radial `tcEnemies.PicksRandomTargetsWithRepetition()` → `Event(eiDamageable)` → `MustNotHave([upInvisible,upBanished]).MustHave([upBuilding])` → `TModifierWelaTargetCountComponent.ScaleWithResource(reMana)` → `TWelaEffectProjectileComponent` → stats. **On death launches one 15-dmg siege projectile per stored soul (max 15) at enemy buildings within 14.**

### VoidSlime (`VoidSlime.ets`) — T2 melee ground, status mirror
CollisionRadius `0.7`. `[upTier2,upUnit,upGround,upMelee]`, `atUnarmored`, HP `495`. [0,1] range `1.0`; group 1 `dtMelee`, dmg `100`, CD `2300`, AP `350`, dur `966`. `eiCooldown[2] = 200` (reflect rate limit).
Three generated patterns, each reserving fresh groups:
- **`ApplyAbsorbToSelf(prop)`** ×10 (`upStunned, upRooted, upBlinded, upFrozen, upLifted, upBanished, upSilenced, upBleeding, upBefogged, upPetrified`): `eiWelaDamage[G] = 250.0`; `TAutoBrainOnUnitPropertyComponent.TriggerOn([prop])` → instant → `TWarheadSpottyResourceComponent.SetResourceType(reHealth).ChangesMax` → `TWelaEffectRemoveAfterUseComponent`. **First time each of the 10 status effects hits it, +250 permanent max HP (once each).**
- **`ApplyMirrorToSelf(prop, script)`** ×8 (`Stun, Root, Blind, Frozen, Lifted, Banished, Bleeding, Petrified`): `TAutoBrainOnDealDamageComponent([1]).FireInGroup([Enemy])` → enemy `MustHave([prop])` → `TWelaEffectFireComponent.TargetGroup([Self]).RedirectToSelf` → self `MustNotHave([prop])` → instant → `TWarheadApplyScriptComponent(script)`. **Copies the victim's status onto itself.**
- **`ApplyMirrorToEnemy(prop, immunity, secondImmunity, script, name)`** ×7: `TAutoBrainOnTakeDamageComponent([2]).CheckSelfForTargetsInGroup([Self]).FireTargetsInGroup([Enemy]).ThinksPassively` + `TWelaReadyCooldownComponent([2,Enemy],true)` (200 ms) → self `MustHave([prop])`, enemy `MustHave([upUnit]).MustNotHave([immunity, secondImmunity, upLegendary, upImmuneToStateEffects])` → instant → apply script. Pairs: `(upStunned,upStunned,upStunned,Stun)`, `(upRooted,upImmuneToRooted,upImmuneToRooted,Root)`, `(upBlinded,upImmuneToBlinded,upNoAutoAttack,Blind)`, `(upFrozen,upImmuneToFrozen,upImmuneToFrozen,Frozen)`, `(upLifted,upImmuneToLifted,upFlying,Lifted)`, `(upBleeding,upBleeding,upBleeding,Bleeding)`, `(upPetrified,upImmuneToPetrified,upImmuneToPetrified,Petrified)`. **Passes its own statuses back to attackers.**

### FrostgoyleFountain (`FrostgoyleFountain.ets`) — T2 building
`InitBuildingData(Entity, True)` (90 000 ms lifetime via `GROUP_BUILDING_LIFETIME`). CollisionRadius `0.6`. `[upTier2,upGround,upBuilding,upSoulGatherer,upNoAutoAttack]`, `atFortified`, HP `475`, `reMana` cap `8`.
Group 2: cost `reMana 4`, CD `3000`, pattern `Units\Black\Frostgoyle`.
SERVER group 2: `TBrainWelaSelftargetComponent.ThinksPassively` → `MustNotHave([upSilenced])` → `TWelaReadyCooldownComponent(...,true)` → `TWelaReadyCostComponent.SetPayingGroupForType(reMana,[])` → `TWelaEffectPayCostComponent.SetPayingGroupForType(reMana,[])` → `TWelaEffectFactoryComponent`. **Every 4 souls (≥3 s apart) spawns a Frostgoyle at its own position.**
Shared: `TWarheadApplyScriptComponent([2],'Modifiers\LegendarySpawn.dws').PassIntValue(660).ApplyToProducedUnits()` and `...('Modifiers\TimedLife.dws').ApplyToProducedUnits` — **Frostgoyles have a spawn-lockout of 660 ms and expire after 17 000 ms.**

### Tyrus (`Tyrus.ets`) — T3 legendary melee ground
CollisionRadius `0.9`. `[upTier3,upUnit,upGround,upMelee,upLegendary,upSoulGatherer]`, `atMedium`, HP `390`, `reMana` cap `20`.
[0,1] range `1.0`; group 1 `dtMelee`, dmg `65`, CD `1000`, AP `366`, dur `800`.
Group 2 Soul Armor: cost `reMana 1`, `eiWelaDamage 5.0` (damage threshold), `eiWelaModifier 0.0` (damage multiplier after block).
Group 3 Soul Undertow: targetcount `1`, CD `3000`, range `5.0`, pattern `VoidGatherProjectile`, dmg `1.0`.
Group 5 Powerful Debut "Lord of Souls": targetcount `200`, range `9.0`, pattern `VoidGatherProjectileTyrus`, dmg `1.0`.
`CreateMeta` (shared): group 5 `MustHave([upUnit]).MustNotHave([upBase,upLegendary,upImmuneToBanished,upImmuneToStateEffects])` + `Event(eiDamageable)`.
SERVER:
- **group 2**: `TAutoBrainOnTakeDamageComponent.ModifiesAmount.FireSelfInGroup([2]).ThinksPassively` → `MustNotHave([upSilenced])` → `TWelaReadyCostComponent(reMana)` → `TWelaTriggerCheckTakeDamageThresholdComponent` → `TWelaEffectPayCostComponent(reMana)`. **Any incoming hit above 5 damage is nullified (×0.0) at the cost of 1 soul.**
- **group 3**: `TBrainWelaFightComponent` → `TWelaReadyCooldownComponent(...,False)` → radial `SetTargetTeamConstraintPriority(tcEnemies).PicksRandomTargets()` → `MustHave([upUnit]).MustNotHave([upBase,upLegendary,upImmuneToBanished,upImmuneToStateEffects,upInvisible])` + `Event(eiDamageable)` → `TWelaEffectInstantComponent` → `TWelaEffectProjectileComponent.Reverse`. **Every 3 s banishes 1 enemy within 5 and pulls a soul out of it (reverse projectile → +1 mana).** Shared: `TWarheadApplyScriptComponent([3],'Modifiers\Banished.dws')`.
- **group 5**: `TBrainWelaFightComponent.ThinksPassively` → radial priority `tcEnemies`, `PicksRandomTargets()` → instant → `TWelaEffectProjectileComponent.Reverse` → `TWelaEffectRemoveAfterUseComponent`. Shared `Banished.dws`. **Once on spawn: banish up to 200 enemies within 9 and drain one soul from each.**
- **group 1**: standard melee with `TWarheadSpottyDamageComponent`.
Shared: `LegendarySpawn.dws PassIntValue(3300) ApplyToSelfAtCreate`; `TUnitPropertyComponent([],[upHasLegendaryUnit]).GivePropertyOwner()`.

### Vecra (`Vecra.ets`) — T3 legendary ranged flying
CollisionRadius `1.2`. `[upTier3,upUnit,upRanged,upFlying,upLegendary]`, `atHeavy`, HP `460`.
[0,1] targetcount `1`, range `7.0`, pattern `VecraProjectile`; group 1 `dtRanged`, dmg `290`, CD `2000`, AP `450`, dur `833`.
Group 2 Icy Prison melt tick: dmg `10`, `dtIgnoreArmor`, CD `2000`. Group 3: `eiWelaModifier 0.2` (damage taken multiplier while imprisoned), pattern `Projectiles\Black\VecraFreeze`.
Groups [4,5] Monarch of Frost: targetcount `200`, `eiLinkPattern 'Links\VecraAura'`, range `8.0`, `eiWelaActive False`.
SERVER:
- **group 1**: approach + ranged projectile chain.
- **group 2**: `TBrainWelaSelftargetComponent.ThinksPassively()` → `TWelaReadyCooldownComponent(...,False)` → `Event(eiDamageable)` → instant → `TWarheadSpottyDamageComponent`. **Self-damages 10 (ignoring armor) every 2 s while in the prison.**
- **group 3 (unleash)**: `TBuffTakenDamageMultiplierComponent.DamageTypeMustNotHave([dtIgnoreArmor])` (×0.2 incoming); `TBrainWelaSelftargetComponent.ThinksPassively()` → `TWelaReadyResourceCompareComponent.ComparedResource(reHealth).SetComparator(coLowerEqual).ReferenceValue(0.5)` → `TWelaEffectFactoryComponent` (spawns `VecraFreeze` field) → `TWelaEffectInstantComponent` → `TWelaEffectActivationAbilityComponent.SetsActive.SetActivationGroup([4,5])` → `TWelaEffectFireComponent.TargetGroup([6])` → `TWelaEffectRemoveAfterUseComponent.TargetGroup([2,3])`. **At ≤50 % HP she breaks out: mass-freeze burst, aura goes live, prison components removed.** Shared: `TUnitPropertyComponent([3],[upFrozen,upImmuneToFrozen,upGround])` — while imprisoned she is frozen, frost-immune and counts as ground.
- **groups 4/5 aura**: `TBrainWelaLinkComponent([4]).ThinksPassively()` → `TWelaTargetingRadialComponent([4]).SetValidateGroup([5]).SetTargetTeamConstraint(tcEnemies)` → `MustHave([upFrozen])` on [4,5] → `TWelaLinkEffectComponent.CreateGrouped(Entity,[4,5])`. **Maintains up to 200 `Links\VecraAura` links to frozen enemies within 8.**
Shared: `LegendarySpawn.dws PassIntValue(2500) ApplyToSelfAtCreate`; on group 3 `LegendarySpawn.dws PassIntValue(1666)`; `upHasLegendaryUnit` to owner.

### VoidWraith (`VoidWraith.ets`) — T3 ranged ground
CollisionRadius `0.7`. `[upTier3,upUnit,upGround,upRanged]`, `atUnarmored`, HP `475`, `reMana` start `6` cap `12`.
[0,1] range `5.0`, pattern `VoidWraithProjectile`; group 1 CD `2000`, `dtRanged`, dmg `86`, AP `266`, dur `833`.
Group 2 Frost Nova: cost `reMana 6`, dmg `200`, range `7.0`, `eiDamageType []`, AP `800`, dur `1600`, CD `3000`. Group 3 splash: `[dtSplash,dtAbility]`, dmg `60`, AoE `4.0`. Group 5 mana-reg: dmg `1.0`, CD `3000`.
SERVER:
- **group 2**: `TBrainWelaFightComponent.Blocking` → cooldown → `MustNotHave([upSilenced])` → `TWelaReadyCostComponent(reMana)` → radial `tcEnemies` → `Enemies`/`Event(eiDamageable)` on [2,3] → `MustNotHave([upInvisible,upBanished])` → `TWelaEfficiencyUnitPropertyComponent.Prioritize([upImmuneToFrozen,upLegendary,upBuilding,upImmuneToStateEffects]).Reverse` → `TWelaEffectPayCostComponent(reMana)` → `TWelaEffectActivationAbilityComponent...SetActivationGroup([5])` → `TWelaEffectFireComponent.TargetGroup([3])` → group 3 instant + `TWarheadSplashDamageComponent` (60 in 4.0) → group 2 instant + `TWarheadSpottyDamageComponent` (200 single target) → `TWelaEffectFireComponent.TargetGroup([4])` → group 4 `MustHave([upUnit]).MustNotHave([upImmuneToFrozen,upLegendary,upImmuneToStateEffects])` → instant → shared `Frozen.dws`.
- **group 5**: `TBrainWelaSelftargetComponent.ThinksPassively` → `TWelaReadyCooldownComponent(...,False)` → instant → `TWarheadSpottyResourceComponent.SetResourceType(reMana).TargetGroup([])`. **+1 mana / 3 s.**

### VoidAltar (`VoidAltar.ets`) — T3 building
`InitBuildingData(Entity, True)` (90 s). CollisionRadius `0.9`. `[upTier3,upGround,upBuilding,upRanged,upSoulDonor,upSoulGatherer,upNoAutoAttack,upSupporter]`, `atFortified`, HP `115`, `reMana` cap `10`.
Group 2 Soul Vortex: range `40.0`, CD `3000`, pattern `Projectiles\Black\SoulGatherProjectile`, `eiWelaDamage[2,3] 1.0`.
Group 4 Soul Donor: cost `reMana 1`, range `12.0`, CD `1000`, pattern `SoulDonorProjectile`, dmg `1.0`, `dtIrredirectable`.
SERVER:
- **group 2**: `TBrainWelaFightComponent` → cooldown → radial `tcEnemies.PicksRandomTargets()` → `TWelaTargetConstraintResourceComponent.CheckResource(reHealth).Comparator(coLowerEqual).Reference(60.0).CompareCapToReference()` → `MustHave([upUnit]).MustNotHave([upBase,upLegendary,upBanished,upInvisible])` + `Event(eiDamageable)` → `TWelaEffectProjectileComponent.Reverse` → instant → `TWarheadSpottyKillComponent.Exile`. **Every 3 s exiles one enemy unit with max HP ≤ 60 anywhere within 40 and harvests its soul.**
- **group 4**: `TBrainWelaFightComponent` → `MustNotHave([upSilenced])` → cooldown → `TWelaReadyCostComponent`/`TWelaEffectPayCostComponent` (`reMana`, group `[]`) → radial `tcAllies.PicksRandomTargets()` → `MustNotHave([upSoulDonor])` → `CheckResource(reMana).CheckNotFull()` → `TWelaEffectProjectileComponent`. **Every 1 s gives 1 stored soul to a random non-full allied gatherer within 12.**

## 2. Spells

All use `PrepareSpellData(...)` + `PrepareSpell(...)` from `SpellTemplate.dws` (gold cost via `GetCardBaseCost`, charge group, `TWelaEffectPayCostComponent...ConvertResource(reGold,reWood)`, `TCommanderAbility`, `TWelaTargetConstraintZoneComponent(ZONE_WALK,False)`).

| Spell | Tier | Properties | Target | Cost delta |
|---|---|---|---|---|
| Frenzy | 1 | `upSpellSingle, upSpellAlly` | `ctEntity`, count 1 | base **+10** |
| Frostspear | 1 | `upSpellSingle, upSpellEnemy` | `ctEntity`, count 1 | base **+20** |
| Freeze | 2 | `upSpellArea, upSpellEnemy` | `ctCoordinate`, count 1 | base |
| OnTheEdge | 2 | `upSpellCharm, upSpellEnemy` | `ctCoordinate`, count 1 | base **−20** |
| PermaFrost | 2 | `upSpellSingle, upSpellEnemy` | `ctEntity`, count 1 | base **−30** |
| RipOutSoul | 2 | `upSpellArea, upSpellEnemy` | `ctCoordinate`, count 1 | base **−50** |
| ShatterIce | 3 | `upSpellArea, upSpellEnemy` | `ctCoordinate`, count 1 | base **−40** |

**Frenzy.sps** — shared: `TWelaTargetConstraintAlliesComponent` + `MustHave([upUnit]).MustNotHave([upBase,upBlessedFrenzy])`. SERVER: `TBrainWelaCommanderComponent` → `TWelaEffectInstantComponent` → `TWarheadSpottyRemoveBuffComponent.MustHaveAny([btState])` (strips all state effects) → shared `TWarheadApplyScriptComponent(...,'Modifiers\BlessingFrenzy.dws')`.

**Frostspear.sps** — reserves `SpellFreeze`, `SpellFreezeBase`. Shared constraints: `MustHaveAny([upUnit,upBuilding]).MustNotHave([upBanished,upSpellImmune])` + `Enemies`. SERVER: `TBrainWelaCommanderComponent` → `TWelaEffectFireComponent.TargetGroup([SpellFreeze])` (constraint `MustNotHave([upCharm,upLegendary,upNexus,upImmuneToFrozen,upImmuneToStateEffects,upBase])`, instant) → `TWelaEffectFireComponent.TargetGroup([SpellFreezeBase])` (`MustHave([upBase]).MustHaveAny([upBuilding])`, instant) → `TWelaEffectInstantComponent([SpellGroup])`. Shared warheads: `Frozen.dws` on SpellFreeze; `Frozen.dws .PassIntValue(5000).MethodName('ApplyWithDuration')` on SpellFreezeBase (bases freeze only 5 s); `'Spells\Black\Frostspear.dws'` on SpellGroup.

**Frostspear.dws** (effect attached to the target) — `eiCooldown 100`, `eiWelaDamage 10.0`, `eiWelaRange 6.0`, pattern `Projectiles\Black\FrostspearProjectile`, `dtSpell`. SERVER: `TThinkImpulseTimerCooldownComponent([Group,FinishGroup]).TimerIsReady` → `TBrainWelaFightComponent.DisableTargetLock.ThinksLocal.ThinksPassively` → radial `.IgnoreOwnCollisionradius.SetTargetTeamConstraint(tcAllies).PicksRandomTargets` → `NotSelf`, `MustNotHave([upInvisible,upBanished,upSpellImmune])`, `Event(eiDamageable)` → `TWelaEffectProjectileComponent`; then `TBrainWelaTargetlessComponent` → `TWelaReadyNthComponent.Nth(12)` → `TWelaEffectRemoveAfterUseComponent.TargetGroup([Group,FinishGroup])`. **Ice shards: 12 projectiles of 10 spell damage, one every 100 ms, at random units within 6 (targeting "allies" = the victim's own team).**

**Freeze.sps** — SERVER: `TWelaEffectFactoryComponent` + `TBrainWelaCommanderComponent`; `eiWelaUnitPattern = 'Spells\Black\Freeze'`.
**Freeze.ets** (field) — `eiWelaRange 4.0`, `eiWelaTargetCount 12`. `CreateMeta`: group 10 `MustHave([upUnit]).MustNotHave([upLegendary,upSpellImmune])` + `Enemies`; group 11 `Event(eiDamageable)` + `MustNotHave([upFrozen,upImmuneToStateEffects,upImmuneToFrozen])`; `TWelaTargetConstraintBooleanComponent.GroupA([10]).GroupB([11]).OperatorAnd`. SERVER: `TThinkImpulseOnceComponent` → `TBrainWelaFightComponent` → radial `tcEnemies` → instant → `TWelaEffectSuicideComponent`; shared `Frozen.dws`. **Freezes up to 12 enemy units in radius 4, then vanishes.**

**OnTheEdge.sps** — factory spawning `Spells\Black\OnTheEdge`.
**OnTheEdge.ets** (charm field) — CollisionRadius `5.0`, `[upCharm]`, `reWelaCharge` balance/cap `10`. Group 0: cost `reWelaCharge 1`, targetcount `1`, CD `1000`, range `5.0`. Groups [4,5]: range `5.0`, targetcount `200`, `eiLinkPattern 'Links\BefoggedAura'`. Group [6,7] dmg `1.0`; group 8 range `10000.0`.
`CreateMeta`: group 0 `Allies` + `MustHaveAny([upUnit,upBuilding]).MustNotHave([upBase,upNoAutoAttack,upBlessedGrievousWounds])`; group 4 `Enemies` + `MustNotHave([upBefogged])`; [4,5] `NotSelf` + `MustHaveAny([upUnit,upBuilding]).MustNotHave([upNoAutoAttack,upMelee,upBase,upSpellImmune])`.
SERVER: `TCollisionComponent.Create` + `TPositionComponent` + `TThinkImpulseTimerComponent`.
- group 0: `TBrainWelaFightComponent.DisableTargetLock()` → cooldown → `TWelaReadyCostComponent.SetPayingGroupForType(reWelaCharge,[])` → radial `.IgnoreOwnCollisionradius.SetTargetTeamConstraint(tcAllies).PicksRandomTargets` → `NotSelf` → instant → `TWelaEffectPayCostComponent(reWelaCharge)` → shared `BlessingGrievousWounds.dws`. **Every 1 s enchants one allied unit in radius 5 with Grievous Wounds, spending 1 of 10 charges.**
- group 1: `TWelaEffectFireComponent([0]).TargetGroup([1]).RedirectToSelf` → `TWelaReadyResourceCompareComponent.ComparedResource(reWelaCharge).CheckEmpty` → `TWelaEffectSuicideComponent`. **Field dies after 10 enchantments.**
- groups 4/5: `TBrainWelaLinkComponent.ThinksPassively()` → radial `.IgnoreOwnCollisionradius.SetValidateGroup([5]).SetTargetTeamConstraint(tcEnemies)` → `TWelaLinkEffectComponent.CreateGrouped(Entity,[4,5])`. **Up to 200 `Links\BefoggedAura` links to non-melee enemies in radius 5.**
- group 8: `TAutoBrainOnCreateComponent.FireAtTarget` → `TWelaReadyResourceCompareComponent.ComparedResource(reCharmCount).CheckFull.ChecksCommander` → radial `tcAllies` → `MustHave([upCharm])` → `TWelaEfficiencyCreatedComponent` → instant → `TWarheadSpottyKillComponent.Remove`. **If the charm cap is full, removes the oldest charm.**
- groups 6/7: on create `FireAtCommander` +1 `reCharmCount`; on free −1 `reCharmCount`.

**PermaFrost.sps** — shared constraint `MustHave([upUnit]).MustNotHave([upBase,upLegendary,upBlessedHardening,upSpellImmune])`. SERVER: `TBrainWelaCommanderComponent` → `TWelaEffectRemoveBeaconComponent.SearchForWelaBeacon([upFrozen])` (strips any existing Frozen group) → `TWelaEffectInstantComponent`. Shared: `Frozen.dws` (fresh 9 s freeze) and `'Spells\Black\PermaFrost.dws' .PassSameTeam`.
**PermaFrost.dws** — `eiWelaDamage[Group] = 300.0`; if target is not on the caster's team `eiWelaModifier[Group] = -1.0`. SERVER: `TAutoBrainBuffComponent([Group],[btPositive])` + `TWelaEffectRemoveAfterUseComponent.TargetGroup([Group])`; `TModifierResourceComponent.Resource(reHealth).ApplyNow()`. Shared: `TUnitPropertyComponent([Group],[upBlessed,upBlessedHardening])`; `TWelaReadyUnitPropertyComponent([ArmorGroup]).MustHave([upFrozen])` + `TModifierArmorTypeComponent.SetTo(atHeavy).ReadyGroup([ArmorGroup])`. **Freezes the target; while frozen its armor becomes `atHeavy` and its max HP changes by ±300 (−300 on enemies).**

**RipOutSoul.sps** — factory spawning `Spells\Black\RipOutSoul`.
**RipOutSoul.ets** — CD `500`, range `5.5`, targetcount `20`, `eiWelaDamage 0.30` (30 % of max HP), `[dtSpell,dtSplash]`. `CreateMeta`: group 10 `MustHave([upUnit]).MustNotHave([upLegendary,upSpellImmune])`; group 11 `Event(eiDamageable)` + `MustNotHave([upImmuneToBanished,upImmuneToStateEffects])`; boolean AND into group 0.
SERVER: `TThinkImpulseTimerCooldownComponent([0,1,3])` (500 ms delay) → group 0 `TBrainWelaFightComponent` → radial `tcAll` → instant → `TWarheadSpottyDamageComponent.PercentageOfMaxHealth()` → shared `Banished.dws`; group 3 `TBrainWelaTargetlessComponent` → `TWelaEffectSuicideComponent`. **Deals 30 % max HP and banishes up to 20 units (both teams, `tcAll`) in radius 5.5, then despawns.** Killed units release their soul normally.

**ShatterIce.sps** — factory spawning `Spells\Black\ShatterIce`.
**ShatterIce.ets** — `eiWelaAreaOfEffect[0,1] = 4.0`, `[dtSpell,dtSplash]`, `eiWelaDamage[0] = 250.0` (units), `eiWelaDamage[1] = 800.0` (buildings). `CreateMeta`: group 0 `MustHave([upUnit,upFrozen]).MustNotHave([upBanished,upSpellImmune])`; `Enemies` on [0,1]; group 1 `MustHave([upBuilding,upFrozen]).MustNotHave([upBanished])`.
SERVER: `TThinkImpulseOnceComponent` → per group `TBrainWelaSelftargetGroundComponent` → radial `tcEnemies` → instant → `TWarheadSplashDamageComponent.TargetsGroundAndAir` → group 2 `TBrainWelaTargetlessComponent` + `TWelaEffectSuicideComponent`. **250 to frozen units / 800 to frozen buildings in radius 4, then despawns.**

## 3. Referenced Modifiers / Links / Projectiles

- **`Modifiers\Frozen.dws`** — `DEFAULT_DURATION 9000`; freeze group cooldown = duration, immunity group = duration + `10000`. Triggers `eiStand`+`eiWelaStop`, `TAutoBrainBuffComponent([btNegative,btState])`, `TWelaHelperBeaconComponent.TriggerAt([upFrozen])`; grants `[upHasStateEffect,upFrozen]` then `[upImmuneToFrozen]` for 19 s total. `ApplyWithDuration(d)` overrides.
- **`Modifiers\Banished.dws`** — `DURATION 10000`, immunity `20000`. Same structure; `[upHasStateEffect,upBanished]` → `[upImmuneToBanished]`. Unit stands still and can't act.
- **`Modifiers\Undying.dws`** — `DURATION 15000`, `eiWelaDamage[HealthGroup] = 100000.0`. Full heal on apply, `[upHasUndying,upUnhealable]`, `TWelaEffectSuicideComponent` after 15 s. Cannot be healed while undying.
- **`Modifiers\BlessingFrenzy.dws`** — buff duration `10000`; attack-speed modifier `0.5` for melee / `0.75` for ranged (`TModifierMultiplyCooldownComponent` on `GROUP_MAINWEAPON`); ranged also gain `+1` target (`TModifierWelaTargetCountComponent`, modifier `1`); melee gain `70` `dtFlatHeal` per attack (`TWarheadSpottyHealComponent`). Grants `[upBlessed,upBlessedFrenzy,upImmuneToStateEffects]`.
- **`Modifiers\BlessingGrievousWounds.dws`** — bleed apply rate `eiCooldown 1000`, `eiWelaDamage[StackBleedingGroup] = 1.0`. On dealing damage to a non-legendary, non-status-immune unit: if target already `upBleeding`, reset its bleed beacon cooldown and add +1 `reWelaCharge` stack; otherwise apply `Modifiers\Bleeding.dws`. Grants `[upBlessed,upBlessedGrievousWounds]`.
- **`Modifiers\TimedLife.dws`** — `eiCooldown 17000`; suicide after 17 s; `TAutoBrainOnUnitPropertyComponent.TriggerOn([upBlessed])` removes the timer when the unit becomes blessed.
- **`Modifiers\LegendarySpawn.dws`** — passed `PassIntValue(ms)` (Tyrus 3300, Vecra 2500 / 1666 on unleash, Frostgoyle 660): spawn-animation lockout window.
- **`Links\VecraAura.ets`** — group 0: `eiWelaDamage 12.0`, `eiCooldown 1000`, `dtAbility`; group 1: `eiWelaModifier 0.5`, `dtHoT`. **12 damage/s to each linked frozen enemy, healing Vecra for 50 % of it.**
- **`Links\BefoggedAura.ets` + `Links\Befogged.dws`** — `eiWelaModifier[Group] = -3.0` applied via `TModifierWelaRangeComponent...AddModifier` on groups 0,1; grants `[upBefogged,upHasStateEffect]`. **−3 attack range on linked non-melee enemies.**
- **Projectiles** (copy `eiWelaDamage`, `eiWelaSplashfactor`, `eiWelaAreaOfEffect`, `eiDamageType`, `eiWelaTargetCount` at launch):
  - `VoidBowmanProjectile` speed `20/1000`, spotty damage.
  - `VoidWormProjectile` speed `20/1000`, spotty damage + group 1 `TAutoBrainOnDealDamageComponent` → `MustHave([upUnit]).MustNotHave([upImmuneToFrozen,upLegendary,upImmuneToStateEffects])` → `Frozen.dws`. **Frostshot: every hit freezes.**
  - `VoidCauldronProjectile` speed `14/1000`; `VoidCauldronBuildingBlastProjectile` speed `12/1000`.
  - `VoidWraithProjectile` speed `18/1000`; `eiWelaModifier[1] 2.0` (status-impaired), `[2] 3.0` (frozen), applied by two `TModifierMultiplyDealtDamageComponent...MustNotHave([dtSpell]).CheckWelaConstraint.SetValueGroup([1]/[2])`. **Shatter Ice: ×2 / ×3.**
  - `VecraProjectile` speed `22/1000`, spotty damage → `TWelaEffectFireComponent.TargetGroup([1])` → `Frozen.dws`.
  - `VecraFreeze.ets` (field spawned on unleash): group 0 range `8.0`, targetcount `200`; group 1 AoE `8.0`, dmg `1000.0`, `[dtSpell,dtSplash]`. Group 1: splash 1000 to already-frozen enemies in 8; group 0: then freezes up to 200 unfrozen enemies in 8, then suicide.
  - `FrostspearProjectile` speed `14/1000`, spotty damage.

## 4. Component semantics (Pascal)

**`TWelaEffectFactoryComponent`** (`Server.Welas.pas:1252`) — On fire, `Count = Max(1, eiWelaCount)`; for each target spawns `Count` entities of `eiWelaUnitPattern` at the target's position (for self-target welas the owner's own position), facing `Owner.Front`. `SpreadSpawns`: random offset of length `random·eiWelaAreaOfEffect` rotated randomly (`SpreadSpawnsOnCircle` skips the `·random`); with empty AoE it falls back to `ComputeSpawningPattern(Position, Front, IsSpawner, i, Count)`. `SetSpawnedTeam(id)` overrides the team. `PassTargets` spawns only at `Targets[0]` and writes the target array into the child's `eiWelaSavedTargets`. `PassCardValues` copies `reCardTimesPlayed`/`reLevel`; `SpawnsDifferentUnits` indexes the pattern by spawn index.

**`TModifierWelaTargetCountComponent`** — Hooks `eiWelaTargetCount`. `AddValue = eiWelaModifier` of the value group (default own group). If `AddValue > 0` and `ScaleWithResource(R)`: `AddValue *= Owner.Balance(R)` (truncated). Returns `Previous(default 1) + AddValue`; `AddValue <= 0` passes through. VoidBane/VoidCauldron: one extra target per stored soul.

**`TWelaEfficiencyUnitPropertyComponent`** — Target scoring: `1` when the candidate has any of `Prioritize([...])`, else `0`; `Reverse` flips. Soft preference, not a constraint.

**`TAutoBrainOnResourceComponent`** — Listens to `eiResourceTransaction`; reacts when the resource is in `TriggerOn([...])`, sent to the global group, and own group is ready. `Times = min(Cap - Balance, Amount)` (the amount that actually fit), clamped to 1 unless `TimesForEach`. Fires `eiFire` that many times. VoidBane group 2: each stored soul fires one +15 max-HP warhead.

**`TWelaEffectRemoveBeaconComponent`** — Finds the target's component groups carrying a `TWelaHelperBeaconComponent` matching `SearchForWelaBeacon([...])` and removes those groups instantly (no expiry). PermaFrost wipes the running Frozen timer (and its pending immunity) before re-applying a fresh 9 s freeze.

**`TCollisionComponent`** — Registers the entity in the map's quadtree with `Entity.CollisionRadius`. Spell fields (OnTheEdge radius 5.0) use it so the field is a queryable area; with `IgnoreOwnCollisionradius` the field's radius is not added to the wela range.

**`TWelaLinkEffectComponent`** — `Fire` triggers `eiLinkEstablish(Owner, Target)` per target; refuses duplicates; at `eiWelaTargetCount` breaks the oldest link first; spawns the `eiLinkPattern` entity on the owner's team. Links break on `eiLinkBreak`, `eiDie`, `eiExiled`, `eiLose`. `SetValidateGroup([5])` keeps the link's own applied property from invalidating it.
