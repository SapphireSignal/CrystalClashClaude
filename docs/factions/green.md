# Green faction ("Nature") spec

Extracted from `reference/rise-of-legions/Scripts/Units/Green`, `Scripts/Spells/Green`, related Modifiers,
Links, Effects and Projectiles, plus the Pascal component implementations. Numbers are exact. Use with
`game/data/units.json` (the components are already extracted there); this doc explains what each group does.

## 0. Saplings and Enchantments (faction-wide)

Green has no template-level group like Black's soul group; its shared mechanic lives in the scripts:
- **Saplings** (`Sapling.ets`, `upSapling`, `upSoulless`, 2 HP, 17 s life) are mass-produced tokens: Woodwalker (2 per
  4 mana), SaplingFarm (3 per 5 mana), Saplingcharge (115 over 11 s, §2). They are consumed by Oracle (sacrifice → +60 max HP
  each, via `reWelaChargeCapacity`), and transformed by EvolveOracle (1 sapling → Oracle at 60 % HP) and EvolveThistle
  (up to 6 saplings → Thistles). `upSoulless` = release no soul to Black gatherers.
- **Enchantments** = any `upBlessed` buff (`TAutoBrainOnUnitPropertyComponent.TriggerOn([upBlessed])`): Sapling "Flourish"
  (+50 max HP, timer removed → permanent), Brratu "Ancient Wisdom" (+300 max HP per enchant), Rootdude (+1 mana per enchant).
  Green's own blessings: `BlessingStrength` (HeartOfTheForest, +40 HP +8 dmg), `BlessingGrowth` (Giant Growth, +160 HP +2 %/s HoT),
  `BlessingHealth` (Healing Garden, +30 % +50 HP). Note `Modifiers\TimedLife.dws` (Black) also cancels on `upBlessed`.
- **Root** (`Modifiers\Root.dws`, 12 s, 1.5 dmg/s, immunity 22 s) is the faction status; Groundbreaker's Relentless does ×2 vs rooted.

## 1. Units

### Sapling (`Sapling.ets`) — T1 melee ground token
CollisionRadius `0.3`. `[upTier1,upUnit,upGround,upMelee,upSapling,upSoulless]`, `atUnarmored`, HP `2`. Card A5/D5/U0.
Group 1 range `0.5`, `dtMelee`, dmg `4`, CD `1500`, AP `266`, dur `766`. Group 9 `eiCooldown 17000`.
SERVER:
- **group 1**: `Preemptive` fight → cooldown(true) → radial `tcEnemies` → [0,1] `Event(eiDamageable)`, `BothMustHaveAny([upGround,upFlying])`, `MustNotHave([upInvisible,upBanished])` → instant → spotty damage.
- **group 9 (TimedLife)**: `TBrainWelaSelftargetGroundComponent` → `TWelaReadyCooldownComponent(...,False)` → `TWelaEffectSuicideComponent`. **Dies after 17 s.**
- **group 10 (Flourish)**: `TAutoBrainOnUnitPropertyComponent.TriggerOn([upBlessed])` → instant → shared `TWarheadApplyScriptComponent([10],'Modifiers\BlessingSapling.dws')` → `TWelaEffectRemoveAfterUseComponent.TargetGroup([9,10])`. **First enchantment: +50 max HP and the 17 s timer is removed (permanent sapling).**
Shared: `LegendarySpawn.dws PassIntValue(200) ApplyToSelfAtCreate` (200 ms spawn lockout). Stats component `SaplingByBaseBuilding` is telemetry only.

### Rootling (`Rootling.ets`) — T1 link-weapon ground, ground-only
CollisionRadius `0.45`. `[upTier1,upUnit,upGround,upRangedGroundOnly,upRanged,upImmuneToBlinded,upLinkWeapon]`, `atLight`, HP `200`. Card A2/D3/U5.
[0,1] range `5.0`; group 1 `eiLinkPattern 'Links/RootlingLink'`, CD `1000`, `dtRanged`, dmg `12`, AP `500`, dur `500`.
SERVER: approach [0] → `TBrainWelaLinkComponent([1]).LinkTime(1000).Preemptive` → radial `tcEnemies` → [0,1] `Event(eiDamageable)`, `BothMustHaveAny([upGround,upFlying])`, `MustNotHave([upInvisible,upBanished])` → `TWelaLinkEffectComponent([1])`.
**Its weapon is a persistent beam (`Links\RootlingLink`, §3): while linked it deals 12 every 1000 ms (link reads CD/damage/type from owner group 1), roots the target once at link creation, and each tick splashes 10 in 3.0 to already-rooted enemies around the target.** No cooldown component; `LinkTime(1000)` is the re-acquire cadence and `Preemptive` makes it stand still while linked (§4).

### Wisp (`Wisp.ets`) — T1 ranged flying
CollisionRadius `0.5`. `[upTier1,upUnit,upFlying,upRanged]`, `atUnarmored`, HP `75`. Card A7/D3/U0.
[0,1] range `6.0`, pattern `WispProjectile`; group 1 CD `2800`, `dtRanged`, dmg `64`, AP `900`, dur `1500`.
SERVER: standard approach + `Preemptive` fight + cooldown(true) + radial `tcEnemies` + `MustNotHave([upInvisible,upBanished])`/`Event(eiDamageable)` → `TWelaEffectProjectileComponent`.
**Depleting Bounce (in the projectile, §3): the shot bounces to up to 6 targets within 5, each hit subtracting the damage dealt from the remaining damage.**

### Thistle (`Thistle.ets`) — T1 ranged ground
CollisionRadius `0.45`. `[upTier1,upUnit,upGround,upRanged]`, `atUnarmored`, HP `27`. Card A8/D2/U0.
[0,1] range `8.0`, pattern `ThistleProjectile`; group 1 `eiWelaTargetCount 2` (Multishot), CD `1700`, `dtRanged`, dmg `14`, AP `233`, dur `1400`. Group 2 `eiWelaModifier 0.40` (Evasion).
SERVER: standard projectile chain (2 targets per volley). Group 2: `TBuffTakenDamageMultiplierComponent.DodgeDamage().DamageTypeMustNotHave([dtSpell,dtDot,dtSplash])`. **40 % chance to fully dodge any non-spell, non-DoT, non-splash hit.**

### HeartOfTheForest (`HeartOfTheForest.ets`) — T1 support ground, no attack
CollisionRadius `0.45`. `[upTier1,upUnit,upGround,upNoAutoAttack,upSupporter]`, `atUnarmored`, HP `60`, `reMana` cap `3` start `3`. `eiAttentionrange[0] = 10.0`.
Groups [2,4]: cost `reMana 3`, range `6.0`; group 2 pattern `HeartOfTheForestProjectile`, targetcount `1`, `[dtIrredirectable]`, AP `400`, dur `800`. Group 5 mana-reg: dmg `1.0`, CD `3000`.
SERVER:
- **group 4**: `TBrainApproachComponent([4])` + `TWelaTargetingRadialAttentionComponent([4]).SetTargetTeamConstraint(tcAllies)`; [2,4] `MustNotHave([upSilenced])`, `TWelaReadyCostComponent(reMana,[])`, `Allies`, `NotSelf`, `MustHave([upUnit]).MustNotHave([upBlessedStrength,upInvisible,upBanished])`. **Walks toward unenchanted allies instead of enemies.**
- **group 2**: `TBrainWelaFightComponent.DisableTargetLock().Blocking` → radial `tcAllies` → `TWelaEffectProjectileComponent` → instant → `TWelaEffectPayCostComponent(reMana,[])` → `TWelaEffectActivationAbilityComponent.SetCheckGroup([]).CheckNotFull(reMana).SetsActive().SetActivationGroup([5])`. Shared `TWarheadApplyScriptComponent([2],'Modifiers\BlessingStrengthIncoming.dws')` (marks the target `upBlessedStrength` instantly so it is not double-targeted; the projectile applies the real `BlessingStrength.dws`). **Spends 3 mana to fire a Blessing-of-Strength projectile at one allied unit within 6; the target gets +40 max HP and +8 damage (+4 for link weapons).**
- **group 0**: `TBrainWaitComponent([0])` + attention radial `tcEnemies` + `MustHaveAny([upUnit,upBuilding]).MustNotHave([upInvisible])`. **Stops and waits while an enemy unit/building is within 10.**
- **group 5**: `TBrainWelaSelftargetComponent.ThinksPassively` → cooldown(False) → instant → `TWarheadSpottyResourceComponent(reMana).TargetGroup([])` → `TWelaEffectActivationAbilityComponent.SetCheckGroup([]).TriggerOnReachResourceCap(reMana)`. **+1 mana / 3 s, paused at full mana, resumed by group 2.**

### Spore (`Spore.ets`) — T2 ranged flying
CollisionRadius `0.6`. `[upTier2,upUnit,upFlying,upRanged,upHasDeathRattle]`, `atUnarmored`, HP `140`. Card A3/D2/U5.
[0,1] range `3.0`, pattern `SporeProjectile`; group 1 CD `1500`, `dtRanged`, dmg `80`, AP `333`, dur `666`. Group 2 pattern `Effects\SporeField`.
SERVER: standard projectile chain. **group 2**: `TAutoBrainOnBeforeDeath([2])` → `TWelaEffectFactoryComponent([2])`. **Death Rattle: spawns a SporeField (§3) at the corpse — 10 s field healing injured allied units 30/s in radius 4 and grounding flying enemies.**

### Woodwalker (`Woodwalker.ets`) — T2 ranged ground summoner
CollisionRadius `0.45`. `[upTier2,upUnit,upGround,upRanged]`, `atUnarmored`, HP `85`, `reMana` start `4` cap `16`.
[0,1] range `8.0`; group 1 pattern `WoodwalkerProjectile`, CD `2800`, `dtRanged`, dmg `99`, AP `350`, dur `1166`.
Group 2: cost `reMana 4`, range `12.0`, pattern `Units\Green\Sapling`, `eiWelaCount 2`, AP `800`, dur `1700`. Group 3 mana-reg dmg `1.0`, CD `3000`.
SERVER:
- **group 2**: `TBrainWelaSelftargetComponent.Blocking()` → `MustNotHave([upSilenced])` → `TWelaReadyCostComponent(reMana,[])` → `TWelaEffectFactoryComponent.SpreadSpawns()` → `TWelaEffectPayCostComponent(reMana,[])` → `TWelaEffectActivationAbilityComponent.SetCheckGroup([]).CheckNotFull(reMana).SetsActive().SetActivationGroup([3])`. **Whenever it has 4 mana it stops to summon 2 Saplings spread within 12 (blocking action 1700 ms).**
- **group 1**: standard ranged chain. **group 3**: +1 mana / 3 s with `TriggerOnReachResourceCap(reMana)` pause.

### Rootdude (`Rootdude.ets`) — T2 short-ranged ground, ground-only
CollisionRadius `0.85`. `[upTier2,upUnit,upGround,upRangedGroundOnly,upRanged]`, `atUnarmored`, HP `495`, `reMana` cap `4` start `0`.
Group 1 range `3.0`, `dtRanged` (no projectile), dmg `89`, CD `2800`, AP `666`, dur `1366`. Group 2 Root Braid: cost `reMana 1`, range `11.0`, pattern `RootdudeRootBraidProjectile`. Group 3 dmg `1.0` (mana per heal), group 4 dmg `100.0` (mana on enchant → clamps to cap 4).
SERVER:
- **group 1**: `Preemptive` fight → instant → `TWarheadSpottyDamageComponent` with `BothMustHaveAny([upGround,upFlying])`. **Hitscan 89 damage at range 3.**
- **group 2**: `TBrainWelaFightComponent.DisableTargetLock` → `MustNotHave([upSilenced])` → `TWelaReadyCostComponent(reMana,[])` → `TWelaEfficiencyDamageTypeComponent.Prioritize([dtMelee])` → radial `.PrioritizeMostDistant.SetTargetTeamConstraint(tcEnemies)` → `MustHave([upUnit,upGround]).MustNotHave([upLegendary,upImmuneToRooted,upImmuneToStateEffects])` → `TWelaEffectProjectileComponent` → `TWelaEffectPayCostComponent(reMana,[])`. **Each mana fires a rooting projectile at the farthest (melee-preferred) rootable ground enemy within 11.**
- **group 3**: `TAutoBrainOnHealedComponent.TimesForEach(50)` → instant → `TWarheadSpottyResourceComponent(reMana)`. **+1 mana per 50 HP healed.**
- **group 4**: `TAutoBrainOnUnitPropertyComponent.TriggerOn([upBlessed])` → instant → `+100 reMana` (fills to cap). **Any enchantment fills its mana.**

### ForestGuardian (`ForestGuardian.ets`) — T2 building, siege artillery
`InitBuildingData(Entity, True)` (90 s lifetime). CollisionRadius `0.75`. `[upTier2,upGround,upBuilding,upRanged]`, `atFortified`, HP `335`.
Group 1 range `11.0`, `[dtRanged,dtSplash,dtSiege]`, dmg `32`, AoE `2.0`, CD `2800`, AP `880`, dur `1933`, pattern `ForestGuardianProjectile` on [0,1,2].
Group 2 Hail of Stones: range `24.0`, `[dtRanged,dtSplash,dtSiege,dtAbility]`, dmg `0.5 * 32 = 16`, AoE `2.0`, CD `2800`.
SERVER: group 1 `Preemptive` fight → cooldown [1] and shared `TWelaReadyCooldownComponent([1,2],True)` → radial `tcEnemies` → `MustNotHave([upInvisible,upBanished])`/`Event(eiDamageable)` → projectile. Group 2 `Preemptive` fight → radial `tcEnemies` → `MustHave([upBuilding])` → projectile. **32 splash (2.0) at anything within 11; a separate 16-splash lob at enemy buildings up to 24 away; both share one 2800 ms cooldown (the [1,2] ready component).**

### SaplingFarm (`SaplingFarm.ets`) — T1 building
`InitBuildingData(Entity, True)` (90 s). CollisionRadius `0.55`. `[upTier1,upGround,upBuilding,upNoAutoAttack]`, `atFortified`, HP `84`, `reMana` start `5` cap `10`.
Group 2: cost `reMana 5`, pattern `Units\Green\Sapling`, `eiWelaCount 3`, AP `500`, dur `1366`. Group 3 mana-reg dmg `1.0`, CD `3000`.
SERVER: same chain as Woodwalker group 2/3 (`Blocking`, `SpreadSpawns()` with no AoE → `ComputeSpawningPattern`). **Every 5 mana (15 s) spawns 3 Saplings; starts with 5 so spawns immediately.**

### Groundbreaker (`Groundbreaker.ets`) — T3 melee ground, burrower
CollisionRadius `0.75`. `[upTier3,upUnit,upGround,upMelee]`, `atUnarmored`, HP `345`.
Group 1 range `1.0`, `dtMelee`, dmg `150`, CD `1700`, AP `500`, dur `1500`. Relentless `eiWelaModifier[2] 1.5`, `[3] 2.0`.
Powerful Debut "Rupture": [4,5] range `1.0`; group 5 `[dtSplash,dtAbility]`, AoE `3.0`, dmg `120`, AP `133`, dur `1233`. Group 6 `eiWelaModifier 0.40` (Evasion).
`CreateMeta` (shared): `TUnitPropertyComponent([5],[upInvincible,upBurrowed])` — **while group 5 exists it is burrowed and invincible.**
SERVER:
- **groups 4/5**: `TBrainApproachComponent([4])` + attention `tcEnemies` (digging approach); `TBrainWelaFightComponent([5]).Preemptive` + `TAutoBrainOnUnitPropertyComponent([5]).TriggerOn([upFlying])` → radial `tcEnemies` → [4,5] `Event(eiDamageable)`, `MustHave([upGround]).MustNotHave([upBanished])`, `Enemies` → `TWelaEffectRedirecterComponent.RedirectToGround` → instant → `TWarheadSplashDamageComponent` → `TWelaEffectRemoveAfterUseComponent.TargetGroup([4,5])`. **Spawns burrowed: approaches the first ground enemy, erupts for 120 splash in 3.0 at its **own** ground position (`RedirectToGround` = owner position; or immediately if it ever becomes flying), then groups 4/5 are removed and it fights normally.**
- **group 1**: standard melee; Relentless `TModifierMultiplyDealtDamageComponent([1]).MustNotHave([dtSpell]).CheckWelaConstraint.SetValueGroup([2])` gated by group 2 `MustHaveAny([upFrozen,upStunned,upBlinded,upGrounded,upLifted,upBleeding,upPetrified]).MustNotHave([upRooted])` → ×1.5; `SetValueGroup([3])` gated by `MustHave([upRooted])` → ×2.0.
- **group 6**: `TBuffTakenDamageMultiplierComponent.DodgeDamage().DamageTypeMustNotHave([dtSpell,dtDot,dtSplash])`. **40 % dodge.**

### Oracle (`Oracle.ets`) — T3 melee ground, sapling eater
CollisionRadius `0.9`. `[upTier3,upUnit,upGround,upMelee]`, `atLight`, HP `610`, `reWelaCharge` cap `12`, `reWelaChargeCapacity` cap `12` (both start 0).
Group 1 range `1.5`, `[dtMelee,dtSplash]`, dmg `87`, CD `3600`, AoE `2.0`, AP `533`, dur `1166`.
Group 2 Sapling boost: CD `500`, `eiWelaDamage 60.0`, range `6.0`, pattern `OracleSaplingProjectile`; group 3 dmg `1.0`.
SERVER:
- **groups 2/3**: `TBrainWelaFightComponent([2,3])` → cooldown [2] (true) → `TWelaReadyResourceCompareComponent.ComparedResource(reWelaChargeCapacity).CheckNotFull()` → radial `tcAllies` → `Event(eiIsAlive)` + `MustHave([upSapling])` → `TWelaEffectProjectileComponent([2]).Reverse` → instant [2,3] → `TWarheadSpottyKillComponent([2]).Sacrifice` + `TWarheadSpottyResourceComponent([3]).SetResourceType(reWelaChargeCapacity).RedirectToSelf`. **Every 500 ms sacrifices one allied Sapling within 6 and a projectile flies from it to the Oracle: +60 max HP and +1 charge (via the projectile, §3); capacity counter +1; stops at 12 saplings (+720 HP).**
- **group 1**: cone-less splash melee (`TWarheadSplashDamageComponent`, 87 in 2.0), `Enemies` + `BothMustHaveAny`.

### Brratu (`Brratu.ets`) — T3 legendary monumental siege
CollisionRadius `1.8`. `udUsePathfinding False`, `eiSpeed 2/1000`. `[upMonumental,upTier3,upUnit,upGround,upFlying,upMelee,upLegendary]`, `atUnarmored`, HP `1800`. Card A2/D10/U2.
Group 1 range `0.5`, `[dtMelee,dtSiege]`, dmg `34`, CD `3600`, AP `1000`, dur `2000`. Group 2 `eiWelaModifier 0.2` (Massive Stomp). Group 3 `eiWelaDamage 300.0` (Ancient Wisdom).
SERVER:
- **group 1**: `Preemptive` fight → radial `tcEnemies` → [0,1] `Event(eiDamageable)`, `BothMustHaveAny([upGround,upFlying])`, `MustHave([upBuilding]).MustNotHave([upInvisible,upBanished])` → instant → spotty damage. **Only attacks buildings (FocusSiege).** Shared `TModifierWelaDamageComponent([1]).ScaleWithResource(reHealth).SetValueGroup([2])`: **damage = 34 + 0.2 × current HP (394 at full HP).**
- **group 3**: `TAutoBrainOnUnitPropertyComponent.TriggerOn([upBlessed])` → instant → `TWarheadSpottyResourceComponent(reHealth).ChangesMax`. **+300 max HP every time it gets enchanted.**
Shared: `LegendarySpawn.dws PassIntValue(3000)`; `upHasLegendaryUnit` to owner. It is both ground and flying (hits everything, targetable by both), walks in a straight line ignoring pathfinding (§4).

## 2. Spells

All use `PrepareSpellData`/`PrepareSpell` from `SpellTemplate.dws` (see black.md §2).

| Spell | Tier | Properties | Target | Cost delta |
|---|---|---|---|---|
| EntanglingRoots | 1 | `upSpellArea, upSpellEnemy` | `ctCoordinate`, count 1 | base |
| GiantGrowth | 1 | `upSpellSingle, upSpellAlly` | `ctEntity`, count 1 | base |
| EvolveOracle | 2 | `upSpellSingle, upSpellAlly` | `ctEntity`, count 1 | base |
| HealingGarden | 2 | `upSpellCharm, upSpellAlly` | `ctCoordinate`, count 1 | base **+20** |
| EvolveThistle | 3 | `upSpellArea, upSpellAlly` | `ctCoordinate`, count 1 | base **−100** |
| Saplingcharge | 3 (legendary) | `upLegendary, upSpellArea, upSpellEnemy` | `ctCoordinate`, count 1 | legendary base **−80** |

**EntanglingRoots.sps** — factory (`PassCardValues`) spawning `Spells\Green\EntanglingRoots`.
**EntanglingRoots.ets** — range `4.0`, targetcount `16`. `CreateMeta`: group 1 `MustHave([upUnit,upGround]).MustNotHave([upLegendary,upSpellImmune])` + `Enemies`; group 2 `MustNotHave([upImmuneToRooted,upImmuneToStateEffects])`; boolean AND into group []. SERVER: `TThinkImpulseOnceComponent` → `TBrainWelaFightComponent` → radial `tcEnemies` → instant → shared `Root.dws` → suicide. **Roots up to 16 enemy ground units in radius 4 for 12 s (1.5 dmg/s).**

**GiantGrowth.sps** — shared `Allies` + `MustHave([upUnit]).MustNotHave([upBase,upBlessedGrowth])`. SERVER: `TBrainWelaCommanderComponent` → instant → shared `BlessingGrowth.dws`. **Enchant: +160 max HP and 2 % max-HP heal per second for 20 s.**

**EvolveOracle.sps** — reserves `SpellGroup`, `SpellGroupHealthReduction`, `ChargeGroup`; `eiWelaDamage[SpellGroupHealthReduction] = 0.6`; pattern `Units\Green\Oracle`; shared constraints `MustHave([upSapling])` + `Allies`. SERVER: `TWelaEffectFactoryComponent.PassCardValues` → instant → `TWarheadSpottyKillComponent.Exile` (the sapling) → `TBrainWelaCommanderComponent`; `TAutoBrainWelaTargetProducedUnitComponent.FireOnlyAtUnitsInOwnGroup.FireInGroup([SpellGroupHealthReduction])` → instant → `TWarheadSpottyResourceComponent(reHealth).AmountIsPercentage().SetsResourceToValue()`. Shared `Evolve.dws PassIntValue(1000) ApplyToProducedUnits`. **Replaces a Sapling with an Oracle at 60 % HP with 1 s of summoning sickness.**

**EvolveThistle.sps** — factory spawning `Spells\Green\EvolveThistle`.
**EvolveThistle.ets** — range `4.0`, targetcount `6`, pattern `Units\Green\Thistle`; `MustHave([upSapling])` + `Allies`. SERVER: `TThinkImpulseOnceComponent` → fight → radial `tcAllies` → `TWelaEffectFactoryComponent.PassCardValues` → instant → `TWarheadSpottyKillComponent.Exile` → suicide; shared `Evolve.dws PassIntValue(1000) ApplyToProducedUnits`. **Turns up to 6 Saplings in radius 4 into Thistles (full HP, 1 s sickness).**

**HealingGarden.sps** — factory spawning `Spells\Green\HealingGardenSpell`.
**HealingGardenSpell.ets** (charm field) — CollisionRadius `3.5`, `[upCharm]`, `reWelaCharge` 6/6. Group 0: cost `reWelaCharge 1`, targetcount `1`, CD `2000`, range `3.5`; [4,5] range `3.5`, targetcount `200`, `eiLinkPattern 'Links\ManaRegenerationAura'`; [6,7] dmg `1.0`; group 8 range `10000`.
`CreateMeta`: group 0 `MustHave([upUnit]).MustNotHave([upBlessedHealth])` + `Allies`; group 4 `MustHaveAny([upUnit,upBuilding]).MustNotHave([upEnergyAuraBuffed,upBase])`; [4,5] `Allies`, `CheckResource(reMana).CheckNotFull`, `NotSelf`, `MustHaveAny([upUnit,upBuilding])`.
SERVER (same plumbing as OnTheEdge): group 0 `TBrainWelaFightComponent.DisableTargetLock()` → cooldown(true) → `TWelaReadyCostComponent(reWelaCharge,[])` → radial `.IgnoreOwnCollisionradius.tcAllies.PicksRandomTargets` → `NotSelf` → instant → pay cost → shared `BlessingHealth.dws`; group 1 `TWelaEffectFireComponent([0]).TargetGroup([1]).RedirectToSelf` → `CheckEmpty(reWelaCharge)` → suicide; groups 4/5 `TBrainWelaLinkComponent.ThinksPassively` → radial `.IgnoreOwnCollisionradius.SetValidateGroup([5]).tcAllies` → `TWelaLinkEffectComponent([4,5])`; group 8 oldest-charm removal; groups 6/7 `reCharmCount` ±1. **Every 2 s enchants one allied unit in radius 3.5 with Blessing of Health (6 charges, then vanishes); meanwhile links `ManaRegenerationAura` (+1 mana / 3 s) to every allied mana user in radius 3.5.**

**Saplingcharge.sps** — `PrepareSpellData(..., True, 3)` (legendary); factory spawning `Spells\Green\Saplingcharge`.
**Saplingcharge.ets** — `[upLegendary]`, `ecGreen`; [0,1] pattern `SaplingchargeSapling`, AoE `7.0`; group 0 CD `1000`, `eiWelaCount 15`; group 1 `eiWelaCount 10`, `eiWelaActive False`, [1,2] CD `1000`; group 3 CD `15000`. SERVER: `TStatisticsUnitComponent`; group 0 `TThinkImpulseTimerCooldownComponent` → `TBrainWelaSelftargetGroundComponent` → `TWelaEffectFactoryComponent.SpreadSpawns()` → `TWelaEffectActivationAbilityComponent.SetsActive.SetActivationGroup([1])` → `TWelaEffectRemoveAfterUseComponent`; groups 1/2 `TThinkImpulseTimerCooldownComponent([1,2])` → group 1 ground-selftarget + factory `SpreadSpawns()`; group 2 `TWelaReadyNthComponent.Nth(11)` → `TWelaEffectRemoveAfterUseComponent.TargetGroup([1,2])`; group 3 timer 15 s → suicide. Shared `upHasLegendaryUnit` to owner.
**SaplingchargeSapling.ets** — group 0 CD `round(random*500)`; group 1 pattern `Units\Green\Sapling`, `eiWelaActive False`, CD `1600`. SERVER: group 0 timer → `SetsActive.SetActivationGroup([1])` → remove; group 1 `TThinkImpulseImmediateComponent` + cooldown(False) → `TWelaEffectFactoryComponent` → suicide.
**After 1 s: 15 seed markers spread in radius 7; then 10 more per second for 10 more seconds (Nth(11) counts the first tick too); each marker becomes a Sapling after 0–500 ms + 1600 ms. Total 115 Saplings; the field despawns at 15 s.** Unusual: the first-tick/Nth accounting and `random` in `CreateData` (per-marker jitter).

## 3. Referenced Modifiers / Links / Effects / Projectiles

- **`Modifiers\Root.dws`** — `ROOT_DURATION 12000`; `eiStand` on apply; `[btNegative,btState]`, grants `[upHasStateEffect,upRooted]`; DoT group `eiCooldown 1000`, dmg `1.5`, `[dtSpell,dtAbility,dtDoT]`, `TWelaReadyNthComponent.Times(12)` (12 ticks); immunity group `22000` grants `[upImmuneToRooted]` (`btDivine`). Removed on kill.
- **`Modifiers\Grounded.dws`** (`ApplyGreen`/`ApplyBlue` = `Apply`) — `GROUND_DURATION 15000`, immunity `25000`; `eiStand`; `TUnitPropertyComponent([Group],[upFlying]).Remove` + `[upGround]` + `[upHasStateEffect,upGrounded]`; immunity `[upImmuneToGrounded]`; on end applies `GroundedEnds.dws` (500 ms `upImmobilized` take-off).
- **`Modifiers\Evolve.dws`** — `PassIntValue(Duration)`: `[btSummoningSickness]`, `[upInvincible,upSummoningSickness,upUntargetable]` for `Duration` ms.
- **`Modifiers\BlessingSapling.dws`** — `[btDivine]`, `TModifierResourceComponent.Resource(reHealth).ApplyNow()` with dmg `50.0` (+50 max HP); no `upBlessed` property (not an enchantment itself).
- **`Modifiers\BlessingStrength.dws`** — `[btPositive]`, `[upBlessed,upBlessedStrength]`; HealthGroup dmg `40.0` (+40 HP via `TModifierResourceComponent...ApplyNow`); DamageGroup `eiWelaModifier 8.0` via `TModifierWelaDamageComponent([0,1,Group]).FactorForUnitProperty([upLinkWeapon],0.5).SetValueGroup([DamageGroup])` (+8 dmg, +4 on Rootling).
- **`Modifiers\BlessingStrengthIncoming.dws`** — `[btPositive]`, only `[upBlessedStrength]` marker (removed by TargetGroup([Group]) on buff clear).
- **`Modifiers\BlessingGrowth.dws`** — `[upBlessed,upBlessedGrowth]`; HealthGroup dmg `160.0` (+160 HP); HoTGroup `reWelaCharge` 20/20 cost 1, CD `1000`; HoTEffectGroup dmg `0.02` `[dtHoT]` → `TWarheadSpottyHealComponent.PercentageOfMaxHealth` on `MustHave([upInjured]).MustNotHave([upUnhealable])`. **20 ticks of 2 % max HP (comment says 5 %, value is 0.02).** HoT charges are only spent by ticks, so the HoT lasts exactly 20 s; the HP bonus stays.
- **`Modifiers\BlessingHealth.dws`** — `[upBlessed,upBlessedHealth]`; `eiWelaDamage 0.3`, `eiWelaModifier 50.0`; `TModifierResourceComponent.Resource(reHealth).ScaleWithResource(reHealth).UseResourceCap.AddModifier.ApplyNow()` (§4: +30 % of max HP + 50).
- **`Modifiers\LegendarySpawn.dws`** — Sapling 200, Brratu 3000.
- **`Links\RootlingLink.ets`** — group 2 dmg `10.0`, AoE `3.0`. SERVER: `TLinkBrainComponent([0]).FiresAtCreate([1])` → instant → `TWarheadSpottyDamageComponent([0])` (12 from owner group); `TWelaEffectFireComponent([0]).TargetGroup([1])` → `MustHave([upUnit]).MustNotHave([upLegendary,upImmuneToRooted,upImmuneToStateEffects])` → instant → shared `Root.dws`; `TWelaEffectFireComponent([0]).TargetGroup([2]).RedirectToGround` → `Enemies`, `Event(eiDamageable)`, `MustHave([upRooted]).MustNotHave([upBanished])` → instant → `TWarheadSplashDamageComponent` (10 in 3.0). Group 0 has no own `eiCooldown`/`eiWelaDamage`/`eiDamageType`: `TLinkEventRedirecter` reads them from the link source's group 1 (1000 / 12 / `dtRanged`). **Root Network: root once on link, then every 1000 ms 12 dmg to the target and 10 splash (3.0) to rooted enemies around it.**
- **`Links\ManaRegenerationAura.ets` + `Links\ManaRegeneration.dws`** — link applies a group: dmg `1.0`, CD `3000`, `TWarheadSpottyResourceComponent(reMana).TargetGroup([])`, `[upEnergyAuraBuffed]`. **+1 mana / 3 s while linked.**
- **`Effects\SporeField.ets`** — group 1 range `4.0`, targetcount `200`, `eiLinkPattern 'Links\HealthRegenerationAura'`; group 3 CD `10000`; group 4 range `4.0`, targetcount `200`. SERVER: `TPositionComponent` + `TThinkImpulseTimerComponent`; group 1 `TBrainWelaLinkComponent.ThinksPassively` → radial `.IgnoreOwnCollisionradius.SetValidateGroup([2]).tcAllies` → `MustHave([upInjured,upUnit]).MustNotHave([upUnhealable,upSporeFieldRegenerating])` (+ [1,2] `NotSelf`, `MustHave([upInjured,upUnit]).MustNotHave([upUnhealable])`) → `TWelaLinkEffectComponent([1])`; group 3 timer → suicide; group 4 `TBrainWelaFightComponent.DisableTargetLock().ThinksPassively` → radial `.IgnoreOwnCollisionradius.tcEnemies` → `MustHave([upUnit,upFlying]).MustNotHave([upGround,upLegendary,upImmuneToGrounded,upImmuneToStateEffects])` → instant → shared `Grounded.dws .Methodname('ApplyGreen')`. **10 s field: heal-links (`HealthRegeneration.dws`: 30 `dtHoT` per 1000 ms, `[upSporeFieldRegenerating]`) to injured allied units in 4; grounds flying enemies in 4 for 15 s.**
- **Projectiles** (copy owner group values at launch):
  - `ThistleProjectile` speed `20/1000`, `WoodwalkerProjectile` `20/1000`, `SporeProjectile` `14/1000`: spotty damage.
  - `ForestGuardianProjectile` speed `16/1000`; `TBrainProjectileComponent.NoTargetChecks()` → `Enemies`, `Event(eiDamageable)`, `MustNotHave([upBanished])` → `TWarheadSplashDamageComponent`.
  - `WispProjectile` speed `14/1000`; `eiWelaCount[0] 6`, `eiWelaRange[1] 5.0`, `eiWelaModifier[2] -1.0`. `TBrainProjectileComponent([0]).Bounces([1])`; `TWelaReadyEventCompareComponent([0]).ComparedEvent(eiWelaDamage).SetComparator(coGreater).ReferenceValue(0.0)`; instant + spotty damage; group 1 radial `tcEnemies.PicksRandomTargets` + `MustNotHave([upInvisible,upBanished])` + `Event(eiDamageable)` + `TWelaTargetConstraintBlacklistComponent`; group 2 `TAutoBrainOnDealDamageComponent.DontFire.WriteAmountTo(eiWelaDamage).AddAmountAtWrite.FireInGroup([0])`. **Depleting Bounce: up to 6 hits, jumping ≤5 to random unhit enemies, remaining damage −= damage dealt, stops at 0.**
  - `HeartOfTheForestProjectile` speed `14/1000`; on impact shared `BlessingStrength.dws`.
  - `OracleSaplingProjectile` speed `14/1000`, `eiWelaDamage[1] 1.0`; `TBrainProjectileComponent([0,1])` → instant → group 0 `TWarheadSpottyResourceComponent(reHealth).ChangesMax()` (+60), group 1 `(reWelaCharge)` (+1). Fired `.Reverse` (sapling → Oracle).
  - `RootdudeRootBraidProjectile` speed `20/1000`; `MustNotHave([upImmuneToRooted,upImmuneToStateEffects])` → shared `Root.dws`.

## 4. Component semantics (Pascal) — not yet handled by the port

Port already handles the classes/fluents listed in `game/sim/wela.gd` + `buff.gd`. New for Green:

**`TBrainWelaLinkComponent.LinkTime(ms)` / `.Preemptive`** (`Server.Brains.pas:979`, impl 1316–1393) — `LinkTime` sets the re-link timer (default `DEFAULT_LINK_BUILD_TIME 250`, :982): when it expires and the group is ready, `eiFire` is re-triggered on all current targets (:1387), i.e. the acquire cadence, not a duration. `Preemptive` (:1086) returns `False` from `ThinkChain` while linked and triggers `eiStand` (:1382), so the Rootling stops moving while its beam is up. Invalid targets get `eiLinkBreak` (:1340).

**`TLinkEventRedirecter`** (`Server.Welas.pas:677`, 922; created on the link with `SourceGroup = ComponentGroup` :1557) — empty `eiCooldown`/`eiWelaDamage`/`eiDamageType` reads on a link entity are redirected to the link source's group. `RootlingLink` group 0 thus uses 1000 / 12 / `[dtRanged]` from Rootling group 1.

**`TLinkBrainComponent.FiresAtCreate([g])`** (`Server.pas:150`, impl 1502–1580) — hooks `eiIdle`; on the first tick it loads `eiCooldown` of its group into a timer and, with `FiresAtCreate`, immediately fires `eiFire` at `eiLinkDest` in group `g` (gated by `eiIsReady` of both groups + `eiWelaTargetPossible`, :1544–1552). Then on every timer expiry it fires at `eiLinkDest` in its own group (`TimesExpired`, capped 50, :1555–1578). Root once, damage every 1000 ms.

**`TWarheadLinkApplyScriptComponent`** (`Shared.Wela.pas:918`, impl 2554–2609) — ctor sets `FNotAtFire` (:2577); hooks `eiAfterCreate` and applies the script to `eiLinkDest[0]`, remembering the returned groups (:2580–2599); `BeforeComponentFree` (:2554) removes those groups from the target via global `eiRemoveComponentGroup` — the buff lives exactly as long as the link (SporeField heal, HealingGarden mana aura).

**`TBuffTakenDamageMultiplierComponent.DodgeDamage()`** (`Server.pas:77`, logic `OnTakeDamage` 2123–2167) — `eiWelaModifier` of the group is the dodge chance: `if random < f then f := 0 else f := 1` (:2143–2151), `Amount *= f` (:2165); on dodge fires `eiFire` at self in its group (:2148). Skipped entirely when the damage carries any `DamageTypeMustNotHave` type (:2083) or when a heal.

**`TBrainProjectileComponent.Bounces([g])` / `.NoTargetChecks`** (`Server.Brains.pas:429`, `OnMoveTargetReached` 1885–1949) — after a hit, if `FBounceCount < eiWelaCount` and the wela is ready: the hit target is appended to `eiWelaSavedTargets` of group `g` (the blacklist), `eiWelaUpdateTargets` runs in `g`, the found target becomes the new `eiWelaSavedTargets`, `FBounceCount++`, `eiMoveTo` re-issued (:1923–1946); no target → `SelfDestruct` (:1998). `NoTargetChecks` (:1879) skips the `eiIsReady` and `eiWelaTargetPossible` checks on arrival (ForestGuardian splash always lands).

**`TWelaReadyEventCompareComponent`** (`Shared.Wela.pas:747`, 3147–3183) — `IsReady = ResourceCompare(reFloat, Read(ComparedEvent, CheckingGroup), Comparator, ReferenceValue)`; Wisp: ready while `eiWelaDamage[0] > 0`.

**`TWelaTargetConstraintBlacklistComponent`** (`Shared.Wela.pas:265`, 2902–2908) — target invalid if contained in `eiWelaSavedTargets` of the constraint's own group.

**`TAutoBrainOnDealDamageComponent.DontFire.WriteAmountTo(ev).AddAmountAtWrite`** (`Server.Brains.pas:670`, 2736–2798) — on `eiDamageDone`: `Amount *= eiWelaModifier(own group, default 1)`, then `Amount += Blackboard(ev, FireGroup)` and written to `ev` in the fire group (:2762–2768); `DontFire` suppresses the `eiFire`. Wisp: modifier −1 → remaining damage −= dealt.

**`TWelaEfficiencyDamageTypeComponent.Prioritize([...])`** (`Server.Welas.pas:865`, 3092–3105) — score 1 if the target's `eiDamageType[GROUP_MAINWEAPON]` intersects the set, else 0 (soft sort key).

**`TWelaTargetingRadialComponent.PrioritizeMostDistant`** (`Server.Welas.pas:127`, comparer 1777–1779) — flips the distance tiebreak to farthest-first (after efficiency and `upLowPrio`); no sort when `MaxTargets >= count` (:1758).

**`TWelaTargetingRadialAttentionComponent` with `eiAttentionrange` / `tcAllies`** (`Server.Welas.pas:82`, 1574–1649) — queries 1.2× `eiAttentionrange` of its group with the team constraint, keeps efficiency ≥ 0, picks the lane-weighted nearest, discards it if beyond the true range. **`TBrainWaitComponent`** (`Server.Brains.pas:314`, 1270–1287) — `eiThinkChain` at epLow: updates its targets and, if any, triggers `eiStand` and returns `False` (blocks lower brains). **`TBrainApproachComponent`** with allied attention (:237, 1572–1600) walks to `eiWelaRange + radii − 0.1` of the ally.

**`TWarheadSpottyKillComponent.Sacrifice`** (`Server.Warheads.pas:91`, `ApplyEffect` 329–345) — triggers `eiSacrifice` (no subscriber anywhere; marker only) then the full `eiKill` path → `eiDie` (death rattles, kill credit) like `Exile` (which additionally writes `eiExiled`); `.Remove` only queues `eiDelayedKillEntity` (silent).

**`TWarheadSpottyResourceComponent.AmountIsPercentage / SetsResourceToValue / SetFactor / RedirectToSelf`** (`Server.Warheads.pas:159`, `ApplyEffect` 390–475) — amount = `eiWelaDamage(own group) * FFactor`; `AmountIsPercentage` multiplies by the **target's cap** (:433); `SetsResourceToValue` zeroes the balance then transacts the amount (:455–462); `ChangesMax` → `eiResourceCapTransaction` (fills balance too, `Shared.pas:1886–1914`); `RedirectToSelf` (`TWarheadComponent` :640–653) retargets the warhead to its owner. EvolveOracle: current HP := 0.6 × cap.

**`TAutoBrainWelaTargetProducedUnitComponent.FireOnlyAtUnitsInOwnGroup.FireInGroup([g])`** (`Server.Brains.pas:520`, 1756–1766) — hooks `eiWelaUnitProduced`; only for productions addressed to its own group; fires `eiFire` at the produced entity in group `g`.

**`TModifierWelaDamageComponent.ScaleWithResource(r)` / `.FactorForUnitProperty(props,f)`** (`Shared.Wela.pas:151`, `OnWelaDamage` 1058–1085) — `Factor = eiWelaModifier(value group)`; with `ScaleWithResource` `Factor *= Balance(r) + offset` (current balance, capped by `MaximumResourceScaleFactor`); with matching properties `Factor *= f`; result `Previous + Factor` (unless `Multiply`/`Divide`). Brratu: `34 + 0.2 × current HP`. BlessingStrength: +8, +4 on `upLinkWeapon` (subscribed on groups `[0,1,Group]`).

**`TModifierResourceComponent.ScaleWithResource.UseResourceCap.AddModifier`** (`Shared.Wela.pas:102`, `ApplyNow` 1124–1149) — `v = eiWelaDamage(value group)`; `ScaleWithResource` multiplies by cap (`UseResourceCap`) or balance; then `v *= eiWelaModifier` or `v += eiWelaModifier` with `AddModifier`; negative clamped to keep cap ≥ 1; applied via `eiResourceCapTransaction` (max **and** current HP). Removal applies `−v` (:1150–1156). BlessingHealth: `0.3 × maxHP + 50`.

**`TWelaEffectRedirecterComponent.RedirectToGround`** (`Server.Welas.pas:253`, 3164–3175) — `eiFire` at epFirst replaces the targets with `ATarget.Create(Owner.Position)` — the **owner's** ground position.

**`TWelaEffectActivationAbilityComponent.SetCheckGroup([]).CheckNotFull(r)` / `.TriggerOnReachResourceCap(r)`** (`Server.Welas.pas:353`, `Fire` 2691–2709) — on fire, reads balance/cap of `r` in the check group; `TriggerOnReachResourceCap` requires `balance = cap`, `CheckNotFull` the inverse (:2677–2683); then writes `eiWelaActive := FActivationState` (default False; `SetsActive` → True) to the activation group if it changes. Mana-reg groups switch themselves off at cap; the spender switches them back on.

**`TThinkImpulseImmediateComponent`** (`Server.Brains.pas:74`, 1035–1043) — thinks every frame unless exiled. (`TThinkImpulseOnceComponent` :2389 once then frees; `TThinkImpulseTimerComponent` :1464 every ~250 ms; `TThinkImpulseTimerCooldownComponent` :1783 uses group `eiCooldown`, not ready until first expiry unless `TimerIsReady`.)

**`TUnitPropertyComponent.Remove`** (`Shared.pas:36`, 2346–2366) — subtracts the properties from every `eiUnitProperties` read while the group lives (Grounded strips `upFlying`).

**`TWelaTargetConstraintEventComponent(eiIsAlive)`** (`Shared.Wela.pas:501`, 1489–1502) — reads the target's `eiIsAlive` (`THealthComponent.OnIsAlive`, `Shared.pas:1073`: plain alive flag), unlike `eiDamageable` (alive and not invincible). Oracle can eat saplings that are invincible (e.g. during `LegendarySpawn`).

**`udUsePathfinding = False` / `upMonumental` / `eiSpeed`** — `TMovementComponent` (`Shared.pas:998–1002`, `IdleDirect` 706–735) walks straight to the target by `eiSpeed` per ms without a grid path and with `IgnoreOtherEntities` (:671); `upMonumental` has no engine behaviour (`Constants.pas:254`, script tag for targeting only); default unit speed is `4/1000` (`HelperScripts/UnitTemplate.dws:7`), Brratu `2/1000`.

**Statistics** — `TWelaEffectStatisticsComponent` (incl. `.CheckMaxTargets`, `Server.Statistics.pas:105`) and `TStatisticsUnitComponent` are telemetry only; ignore.
