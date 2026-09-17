class_name Wela
## One weapon/ability group of a unit, built from the unit's server components (units.json "components").
## Covers the main attack (group 1), heals (Priest), triggered abilities (Shieldblock), dealt-damage
## multipliers (Archer Relentless), resource regeneration (mana), deathrattles, chained effect groups
## (Monk Dragon Punch, Avenger double shot), auras/links (Suntower Homeland), ground self-target AoE
## (Monument of Light), on-healed triggers and cooldown resets (Defender).

enum Kind { FIGHT, SUB, ON_TAKE_DAMAGE, DEALT_DAMAGE_MULT, RESOURCE_REGEN, ON_DEATH, LINK, ON_HEALED, SELF_GROUND, ON_PROPERTY,
	PREVENT_DEATH, ON_RESOURCE, SELF_PASSIVE, WAIT, ON_ABILITY_USED }

var group: int
var kind: Kind
var order: int = 0                # component creation order (think chain order)
# targeting
var target_allies: bool = false
var must_have: Array = []
var must_have_any: Array = []
var must_not_have: Array = []
var compare_any: Array = []        # BothMustHaveAny: owner and target share one of these
var not_self: bool = false
var efficiency_missing_health: bool = false
var efficiency_max_health: int = 0   # 1 = prefer highest max health, -1 = lowest
var picks_random_targets: bool = false
var picks_with_repetition: bool = false   # PicksRandomTargetsWithRepetition
var blocking: bool = false         # TBrainWelaFightComponent.Blocking: attack does not run while this is busy
var passive: bool = false          # ThinksPassively: never claims the unit / no stand
# resource compare constraint (own vs target): "coGreater" etc, factor applied to the target value
var compare_resource: String = ""
var compare_op: String = ""
var compare_target_factor: float = 1.0
# ready checks
var ready_resource: String = ""    # TWelaReadyResourceCompareComponent on the owner
var ready_op: String = ""
var ready_reference: float = 0.0
var ready_absolute: bool = false
var ready_props: Array = []        # TWelaReadyUnitPropertyComponent.MustHave on the owner
var ready_not_props: Array = []
var target_health_full: bool = false   # TWelaTargetConstraintResourceComponent.CheckFull
var target_mana_not_full: bool = false # TWelaTargetConstraintResourceComponent.CheckResource(reMana).CheckNotFull
var target_any_team: bool = false      # SetTargetTeamConstraint(tcAll)
var prefer_allies: bool = false        # SetTargetTeamConstraintPriority(tcAllies): allies first when any qualifies
var prefer_enemies: bool = false       # SetTargetTeamConstraintPriority(tcEnemies)
var team_constraint_set: bool = false
var validate_group: int = -1           # TWelaTargetingRadialComponent.SetValidateGroup: constraints that keep a link alive
var projectile_reverse: bool = false   # TWelaEffectProjectileComponent.Reverse: flies from the target to the owner
var activates_groups: Array = []       # TWelaEffectActivationAbilityComponent.SetsActive.SetActivationGroup
var active: bool = true                # eiWelaActive (Vecra's aura starts inactive)
var removes_groups: Array = []         # TWelaEffectRemoveAfterUseComponent.TargetGroup: other groups removed on use
var taken_mult: float = 1.0            # TBuffTakenDamageMultiplierComponent on a unit group (Vecra's prison: 0.2)
var taken_mult_not_types: int = 0      # DamageTypeMustNotHave
var dodge_chance: float = 0.0          # TBuffTakenDamageMultiplierComponent.DodgeDamage: chance to take 0 (Thistle 0.4)
var cap_op: String = ""                # TWelaTargetConstraintResourceComponent.CompareCapToReference (VoidAltar: max hp <= 60)
var cap_ref: float = 0.0
var modifies_amount: bool = false      # TAutoBrainOnTakeDamageComponent.ModifiesAmount
var mirror_pairs: Array = []           # TAutoBrainOnTakeDamageComponent.CheckSelfForTargetsInGroup + FireTargetsInGroup: [[self, enemy]]
var on_deal_groups: Array = []         # TAutoBrainOnDealDamageComponent.FireInGroup on a unit weapon (VoidSlime mirror)
var apply_script_values: Array = []    # TWarheadApplyScriptComponent.PassIntValue for apply_script
var extra_apply_scripts: Array = []    # further TWarheadApplyScriptComponents on the same group: [script, values, pass_same_team]
var apply_script_same_team: bool = false   # PassSameTeam: the script gets SameTeam = target on the owner's team
var removes_buff_types_any: Array = [] # TWarheadSpottyRemoveBuffComponent.MustHaveAny (Frenzy strips state effects)
var remove_beacon_props: Array = []    # TWelaEffectRemoveBeaconComponent.SearchForWelaBeacon (PermaFrost wipes Frozen)
var damage_percent_of_max: bool = false   # TWarheadSpottyDamageComponent.PercentageOfMaxHealth
var ignore_own_radius: bool = false    # TWelaTargetingRadialComponent.IgnoreOwnCollisionradius
var approach: bool = false             # TBrainApproachComponent: walk toward this group's attention targets
var link_time: int = 250               # TBrainWelaLinkComponent.LinkTime: re-acquire cadence (DEFAULT_LINK_BUILD_TIME)
var preemptive_link: bool = false      # TBrainWelaLinkComponent.Preemptive: stands still while linked
var fires_at_create_group: int = -1    # TLinkBrainComponent.FiresAtCreate([g]) on a link entity
var prioritize_most_distant: bool = false   # TWelaTargetingRadialComponent.PrioritizeMostDistant
var prioritize_damage_types: int = 0   # TWelaEfficiencyDamageTypeComponent.Prioritize (targets whose weapon has any)
var shared_cooldown_groups: Array = [] # TWelaReadyCooldownComponent on several groups: one cooldown for all
var companion_groups: Array = []       # TBrainWelaFightComponent on several groups: the others fire along
var warhead_to_self: bool = false      # TWarheadSpottyResourceComponent.RedirectToSelf
var redirect_to_ground: bool = false   # TWelaEffectRedirecterComponent.RedirectToGround: fires at the owner's position
var ready_not_full: bool = false       # TWelaReadyResourceCompareComponent.CheckNotFull
var damage_scale_resource: String = ""   # TModifierWelaDamageComponent.ScaleWithResource on a unit weapon (Brratu)
var damage_scale_group: int = -1
var timer_period: int = -1             # TThinkImpulseTimerCooldownComponent: fires every eiCooldown of the group
var nth: int = 0                       # TWelaReadyNthComponent.Nth: ready on the nth think
var think_count: int = 0
var produced_fire_group: int = -1      # TAutoBrainWelaTargetProducedUnitComponent.FireInGroup
var resource_percentage: bool = false  # TWarheadSpottyResourceComponent.AmountIsPercentage (of the target's cap)
var resource_sets_value: bool = false  # TWarheadSpottyResourceComponent.SetsResourceToValue
var resolve_team_id: bool = false      # TWelaHelperResolveComponent.ResolveTeamID: pattern indexed by the owner's team
var taken_mult_types: int = 0          # TBuffTakenDamageMultiplierComponent.DamageTypeMustHave (DamperDrone: splash only)
var link_brain: bool = false           # TLinkBrainComponent lists this group: fires every tick of the link
var link_pay_cost: bool = false        # TWelaEffectLinkPayCostMyselfComponentServer: mana on link + per second
var link_paid_until: int = -1
var damage_scale_add: bool = true      # unit-level ScaleWithResource: Previous + modifier x balance
# effects
var heals: bool = false
var damages: bool = false
var kills: bool = false
var exiles: bool = false
var projectile: String = ""
var apply_script: String = ""      # TWarheadApplyScriptComponent on targets
var chain_groups: Array = []       # TWelaEffectFireComponent MultiTargetGroup / TargetGroup
var chain_first: bool = false      # the fire component precedes the warhead: chains run before damage (Frostgoyle fury)
var produced_scripts: Array = []   # TWarheadApplyScriptComponent.ApplyToProducedUnits: [script, [int values]]
var ready_not_empty: bool = false  # TWelaReadyResourceCompareComponent.CheckNotEmpty
var chain_to_self: bool = false
var reset_cooldown_groups: Array = []   # TWelaEffectResetCooldownComponent
var instant_target_groups: Array = []   # TWelaEffectInstantComponent.TargetGroup (splash warheads)
var splash: bool = false
var mana_cost: int = 0
var ready_at_start: bool = true
var range_modifier_group: int = -1     # TModifierWelaRangeComponent value group
var range_scales_with_time: bool = false
var range_ready_group: int = -1
# ON_TAKE_DAMAGE (Shieldblock)
var threshold_lesser_equal: bool = false
# DEALT_DAMAGE_MULT (Relentless)
var weapon_groups: Array = []
var must_not_have_damage_types: int = 0
# RESOURCE_REGEN
var resource: String = ""
# LINK (aura)
var link_property: String = ""
var link_pattern: String = ""
var link_delay: int = 0
# ON_HEALED
var times_for_each: int = 0
# ON_PROPERTY (TAutoBrainOnUnitPropertyComponent.TriggerOn)
var trigger_props: Array = []
# runtime
var cooldown_ready_at: int = 0
var next_at: int = -1
var active_since: int = -1


# charges (reWelaCharge kept per group, e.g. Surge of Light's damage mode)
var charge_cost: int = 0
var charge_consumes_all: bool = false
var charge_gain_group: int = -1      # TWarheadSpottyResourceComponent(reWelaCharge).TargetGroup on fire
var damage_scales_with_charges_of: int = -1   # TModifierWelaDamageComponent.Multiply.ScaleWithResource(reWelaCharge)
var suicide_when_empty: bool = false # TWelaReadyResourceCompareComponent(reWelaCharge).CheckEmpty + suicide
# spell effect entities
var commander_cast: bool = false     # TBrainWelaCommanderComponent: cast by the player, not auto
var suicide: bool = false            # TWelaEffectSuicideComponent
# TWelaEffectFactoryComponent: spawn eiWelaUnitPattern x eiWelaCount at the target position
var spawns: bool = false
var spawn_spread: bool = false       # SpreadSpawns: squad formation
var spawn_team: int = -1             # SetSpawnedTeam
# TWelaEfficiencyUnitPropertyComponent: prefer targets with any of these properties (or without, reversed)
var prioritize_props: Array = []
var prioritize_reversed: bool = false
# TModifierWelaTargetCountComponent: eiWelaTargetCount += eiWelaModifier of the value group
var target_count_add_group: int = -1
var target_count_scale_resource: String = ""   # TModifierWelaTargetCountComponent.ScaleWithResource
var remove_after_use: bool = false   # TWelaEffectRemoveAfterUseComponent on its own group
var used: bool = false
var resource_triggers: Array = []    # TAutoBrainOnResourceComponent.TriggerOn
var changes_max: bool = false        # TWarheadSpottyResourceComponent.ChangesMax (raises the cap and fills it)
var apply_script_to_self_at_create: bool = false   # TWarheadApplyScriptComponent.ApplyToSelfAtCreate


## 'Modifiers\Stun.dws' -> "Stun", 'Links\Homeland.dws' -> "Links/Homeland", 'Spells\White\SolarFlare.dws'
## -> "Spells/White/SolarFlare" (the keys of modifiers.json).
static func script_key(path: String) -> String:
	var key := path.replace("\\", "/").trim_suffix(".dws")
	return key.trim_prefix("Modifiers/")


## Parse all welas of a unit from its component list. Returns them in think-chain order.
## `map` resolves symbolic group names (spell scripts) to ids, see UnitDb.group_map.
static func parse(components: Array, bb: Blackboard, map: Dictionary = {}) -> Array[Wela]:
	var by_group: Dictionary = {}
	var order := 0
	var get := func(g: int, kind: Kind) -> Wela:
		if not by_group.has(g):
			var w := Wela.new()
			w.group = g
			w.kind = kind
			w.order = order
			by_group[g] = w
		return by_group[g]
	var later: Array = []   # [groups, callable] applied after all groups exist
	var warhead_seen := {}   # group -> true once its instant/projectile effect component appeared
	var booleans: Array = []   # TWelaTargetConstraintBooleanComponent: [group, [A, B]] merged after the constraints
	for comp in components:
		order += 1
		var groups: Array = comp["groups"].map(func(s): return UnitDb.group_id(s, map))
		if groups.is_empty():
			groups = [-1]   # CreateGrouped(Entity, []): the entity-wide group
		var calls: Array = comp.get("calls", [])
		var args: Array = comp.get("args", [])
		var g: int = groups[0] if not groups.is_empty() else -1
		match comp["class"]:
			"TBrainWelaCommanderComponent":
				for gg in groups:
					get.call(gg, Kind.SUB).commander_cast = true
			"TWelaEffectSuicideComponent":
				get.call(g, Kind.SUB).suicide = true
			"TWelaTargetConstraintAlliesComponent":
				for gg in groups:
					get.call(gg, Kind.SUB).target_allies = true
			"TWelaTargetConstraintEnemiesComponent":
				for gg in groups:
					get.call(gg, Kind.SUB).target_allies = false
			"TBrainWelaFightComponent":
				var w: Wela = get.call(g, Kind.FIGHT)
				w.kind = Kind.FIGHT if w.kind == Kind.SUB else w.kind
				for gg in groups:
					if gg != g:
						w.companion_groups.append(gg)
				for c in calls:
					if c[0] == "Blocking":
						w.blocking = true
					elif c[0] == "ThinksPassively":
						w.passive = true
			"TWelaEfficiencyDamageTypeComponent":
				for c in calls:
					if c[0] == "Prioritize":
						get.call(g, Kind.SUB).prioritize_damage_types = SimConstants.damage_mask(c[1][0])
			"TWelaEffectRedirecterComponent":
				for c in calls:
					if c[0] == "RedirectToGround":
						get.call(g, Kind.SUB).redirect_to_ground = true
			"TThinkImpulseTimerCooldownComponent":
				var period := 0   # one timer for all its groups: the first group's cooldown (RipOutSoul [0,1,3] = 500)
				for gg in groups:
					if bb.has_value("eiCooldown", gg):
						period = bb.get_int("eiCooldown", gg, 0)
						break
				for gg in groups:
					get.call(gg, Kind.SUB).timer_period = period
			"TWelaReadyNthComponent":
				for c in calls:
					if c[0] == "Nth" or c[0] == "Times":
						get.call(g, Kind.SUB).nth = int(c[1][0])
			"TAutoBrainWelaTargetProducedUnitComponent":
				for c in calls:
					if c[0] == "FireInGroup":
						get.call(g, Kind.SUB).produced_fire_group = UnitDb.group_id(c[1][0][0], map)
			"TWelaHelperResolveComponent":
				for c in calls:
					if c[0] == "ResolveTeamID":
						get.call(g, Kind.SUB).resolve_team_id = true
			"TBrainWelaSelftargetGroundComponent":
				var w: Wela = get.call(g, Kind.SELF_GROUND)
				w.kind = Kind.SELF_GROUND
			"TWelaHelperActivateTimerComponent":
				for c in calls:
					if c[0] == "Delay":
						get.call(g, Kind.LINK).link_delay = int(c[1][0])
			"TBrainWelaLinkComponent":
				var w: Wela = get.call(g, Kind.LINK)
				w.kind = Kind.LINK
				w.link_pattern = bb.get_value("eiLinkPattern", g, "").replace("\\", "/")
				for c in calls:
					if c[0] == "LinkTime":
						w.link_time = int(c[1][0])
					elif c[0] == "Preemptive":
						w.preemptive_link = true
			"TWelaLinkEffectUnitPropertyComponent":
				if args.size() >= 1:
					get.call(g, Kind.LINK).link_property = str(args[0])
			"TBrainApproachComponent":
				get.call(g, Kind.SUB).approach = true
			"TBrainWaitComponent":
				get.call(g, Kind.WAIT).kind = Kind.WAIT
			"TLinkBrainComponent":
				for gg in groups:
					get.call(gg, Kind.SUB).link_brain = true
				var w: Wela = get.call(g, Kind.SUB)
				for c in calls:
					if c[0] == "FiresAtCreate":
						w.fires_at_create_group = UnitDb.group_id(c[1][0][0], map)
			"TWelaEffectLinkPayCostMyselfComponentServer":
				var w: Wela = get.call(g, Kind.SUB)
				w.link_pay_cost = true
				w.mana_cost = bb.get_int("eiResourceCost.reMana", g, 0)
			"TAutoBrainOnCommanderAbilityUsedComponent":
				get.call(g, Kind.ON_ABILITY_USED).kind = Kind.ON_ABILITY_USED
			"TWelaTargetingRadialAttentionComponent":
				for gg in groups:
					var w: Wela = get.call(gg, Kind.SUB)
					for c in calls:
						if c[0] == "SetTargetTeamConstraint":
							w.target_allies = c[1][0] == "tcAllies"
							w.target_any_team = c[1][0] == "tcAll"
							w.team_constraint_set = true
			"TWelaTargetingRadialComponent":
				for gg in groups:
					var w: Wela = get.call(gg, Kind.SUB)
					for c in calls:
						if c[0] == "SetTargetTeamConstraint":
							w.target_allies = c[1][0] == "tcAllies"
							w.target_any_team = c[1][0] == "tcAll"
							w.team_constraint_set = true
						elif c[0] == "SetTargetTeamConstraintPriority":
							w.prefer_allies = c[1][0] == "tcAllies"
							w.prefer_enemies = c[1][0] == "tcEnemies"
							if not w.team_constraint_set:
								w.target_any_team = true   # a priority alone leaves the default tcAll constraint
						elif c[0] == "PicksRandomTargets":
							w.picks_random_targets = true
						elif c[0] == "SetValidateGroup":
							w.validate_group = UnitDb.group_id(c[1][0][0], map)
						elif c[0] == "IgnoreOwnCollisionradius":
							w.ignore_own_radius = true
						elif c[0] == "PrioritizeMostDistant":
							w.prioritize_most_distant = true
						elif c[0] == "PicksRandomTargetsWithRepetition":
							w.picks_random_targets = true
							w.picks_with_repetition = true
			"TWelaEfficiencyMissingHealthComponent":
				get.call(g, Kind.SUB).efficiency_missing_health = true
			"TWelaEfficiencyUnitPropertyComponent":
				for gg in groups:
					var w: Wela = get.call(gg, Kind.SUB)
					for c in calls:
						if c[0] == "Prioritize":
							w.prioritize_props.append_array(c[1][0])
						elif c[0] == "Reverse":
							w.prioritize_reversed = true
			"TWelaEffectFactoryComponent":
				var w: Wela = get.call(g, Kind.SUB)
				w.spawns = true
				for c in calls:
					if c[0] == "SpreadSpawns":
						w.spawn_spread = true
					elif c[0] == "SetSpawnedTeam":
						w.spawn_team = int(c[1][0])
			"TModifierWelaTargetCountComponent":
				var w: Wela = get.call(g, Kind.SUB)
				w.target_count_add_group = g
				for c in calls:
					if c[0] == "SetValueGroup":
						w.target_count_add_group = UnitDb.group_id(c[1][0][0], map)
					elif c[0] == "ScaleWithResource":
						w.target_count_scale_resource = c[1][0]
			"TWelaEfficiencyMaxHealthComponent":
				var w: Wela = get.call(g, Kind.SUB)
				w.efficiency_max_health = 1
				for c in calls:
					if c[0] == "Inverse":
						w.efficiency_max_health = -1
			"TWarheadSpottyHealComponent", "TWarheadSplashHealComponent":
				var w: Wela = get.call(g, Kind.SUB)
				w.heals = true
				w.splash = comp["class"].begins_with("TWarheadSplash")
				w.target_allies = true
			"TWarheadSpottyDamageComponent", "TWarheadSplashDamageComponent":
				var w: Wela = get.call(g, Kind.SUB)
				w.damages = true
				w.splash = comp["class"].begins_with("TWarheadSplash")
				for c in calls:
					if c[0] == "PercentageOfMaxHealth":
						w.damage_percent_of_max = true
			"TWarheadSpottyRemoveBuffComponent":
				for c in calls:
					if c[0] == "MustHaveAny":
						get.call(g, Kind.SUB).removes_buff_types_any = c[1][0]
			"TWelaEffectRemoveBeaconComponent":
				for c in calls:
					if c[0] == "SearchForWelaBeacon":
						get.call(g, Kind.SUB).remove_beacon_props = c[1][0]
			"TWelaTargetConstraintBooleanComponent":
				var sources: Array = []
				for c in calls:
					if c[0] == "GroupA" or c[0] == "GroupB":
						sources.append(UnitDb.group_id(c[1][0][0], map))
					elif c[0] == "OperatorOr":
						push_warning("TWelaTargetConstraintBooleanComponent.OperatorOr treated as And")
				booleans.append([g, sources])
			"TWarheadSpottyKillComponent":
				var w: Wela = get.call(g, Kind.SUB)
				w.kills = true
				for c in calls:
					if c[0] == "Exile":
						w.exiles = true
			"TWelaEffectProjectileComponent":
				var w: Wela = get.call(g, Kind.SUB)
				w.projectile = bb.get_value("eiWelaUnitPattern", g, "").replace("\\", "/")
				warhead_seen[g] = true
				for c in calls:
					if c[0] == "Reverse":
						w.projectile_reverse = true
			"TWelaEffectActivationAbilityComponent":
				var w: Wela = get.call(g, Kind.SUB)
				var sets_active := false
				var groups_to: Array = []
				for c in calls:
					if c[0] == "SetsActive":
						sets_active = true
					elif c[0] == "SetActivationGroup":
						groups_to = c[1][0].map(func(s): return UnitDb.group_id(s, map))
				if sets_active:
					w.activates_groups = groups_to
			"TBuffTakenDamageMultiplierComponent":
				var w: Wela = get.call(g, Kind.SUB)
				w.taken_mult = bb.get_float("eiWelaModifier", g, 1.0)
				for c in calls:
					if c[0] == "DamageTypeMustNotHave":
						w.taken_mult_not_types = SimConstants.damage_mask(c[1][0])
					elif c[0] == "DamageTypeMustHave":
						w.taken_mult_types = SimConstants.damage_mask(c[1][0])
					elif c[0] == "DodgeDamage":
						w.dodge_chance = w.taken_mult
						w.taken_mult = 1.0
			"TWelaEffectInstantComponent":
				var w: Wela = get.call(g, Kind.SUB)
				warhead_seen[g] = true
				for c in calls:
					if c[0] == "TargetGroup":
						w.instant_target_groups = c[1][0].map(func(s): return UnitDb.group_id(s, map))
			"TWelaEffectFireComponent":
				var w: Wela = get.call(g, Kind.SUB)
				if not warhead_seen.has(g):
					w.chain_first = true
				for c in calls:
					if c[0] == "MultiTargetGroup" or c[0] == "TargetGroup":
						w.chain_groups.append(UnitDb.group_id(c[1][0][0], map))
					elif c[0] == "RedirectToSelf":
						w.chain_to_self = true
			"TWelaEffectResetCooldownComponent":
				var w: Wela = get.call(g, Kind.SUB)
				for c in calls:
					if c[0] == "TargetGroup":
						w.reset_cooldown_groups = c[1][0].map(func(s): return UnitDb.group_id(s, map))
			"TWarheadApplyScriptComponent":
				if not args.is_empty():
					var w: Wela = get.call(g, Kind.SUB)
					var produced := false
					var passed: Array = []
					var same_team := false
					for c in calls:
						if c[0] == "ApplyToSelfAtCreate":
							w.apply_script_to_self_at_create = true
						elif c[0] == "ApplyToProducedUnits":
							produced = true
						elif c[0] == "PassIntValue":
							passed.append(int(c[1][0]))
						elif c[0] == "PassSameTeam":
							same_team = true
					if produced:
						w.produced_scripts.append([script_key(str(args[0])), passed])
					elif w.apply_script != "":
						w.extra_apply_scripts.append([script_key(str(args[0])), passed, same_team])
					else:
						w.apply_script = script_key(str(args[0]))
						w.apply_script_values = passed
						w.apply_script_same_team = same_team
			"TBrainWelaSelftargetComponent":
				var passive := false
				for c in calls:
					if c[0] == "ThinksPassively":
						passive = true
				var w: Wela = get.call(g, Kind.SELF_PASSIVE if passive else Kind.SELF_GROUND)
				if w.kind == Kind.SUB:
					w.kind = Kind.SELF_PASSIVE if passive else Kind.SELF_GROUND   # Blocking self-target acts like a self-ground action
			"TWelaEffectRemoveAfterUseComponent":
				var w: Wela = get.call(g, Kind.SUB)
				w.remove_after_use = true
				for c in calls:
					if c[0] == "TargetGroup":
						var targets: Array = c[1][0].map(func(s): return UnitDb.group_id(s, map))
						w.remove_after_use = targets.has(g)
						for tg in targets:
							if tg != g:
								w.removes_groups.append(tg)
			"TAutoBrainPreventDeathComponent":
				get.call(g, Kind.PREVENT_DEATH).kind = Kind.PREVENT_DEATH
			"TAutoBrainOnResourceComponent":
				var w: Wela = get.call(g, Kind.ON_RESOURCE)
				w.kind = Kind.ON_RESOURCE
				for c in calls:
					if c[0] == "TriggerOn":
						w.resource_triggers.append_array(c[1][0])
					elif c[0] == "TimesForEach":
						w.times_for_each = 1
			"TWelaReadyCostComponent":
				for gg in groups:
					var w: Wela = get.call(gg, Kind.SUB)
					w.mana_cost = bb.get_int("eiResourceCost.reMana", gg, 0)
					w.charge_cost = bb.get_int("eiResourceCost.reWelaCharge", gg, 0) if bb.has_value("eiResourceCost.reWelaCharge", gg) and gg != SimConstants.GROUP_MAINWEAPON else 0
			"TWelaEffectPayCostComponent":
				for c in calls:
					if c[0] == "ConsumesAll":
						get.call(g, Kind.SUB).charge_consumes_all = true
			"TWelaReadyResourceCompareComponent":
				var w: Wela = get.call(g, Kind.SUB)
				for c in calls:
					match c[0]:
						"ComparedResource":
							if w.ready_resource == "":
								w.ready_resource = c[1][0]
						"SetComparator": w.ready_op = c[1][0]
						"ReferenceValue": w.ready_reference = float(c[1][0])
						"ReferenceIsAbsolute": w.ready_absolute = true
						"CheckEmpty": w.suicide_when_empty = true
						"CheckNotEmpty": w.ready_not_empty = true
						"CheckNotFull": w.ready_not_full = true
			"TModifierWelaDamageComponent":
				var w: Wela = get.call(g, Kind.SUB)
				var scales := false
				var res_group := g
				var value_group := g
				var resource := ""
				for c in calls:
					if c[0] == "ScaleWithResource" and c[1][0] == "reWelaCharge":
						scales = true
					elif c[0] == "ScaleWithResource":
						resource = c[1][0]
					elif c[0] == "ResourceGroup":
						res_group = UnitDb.group_id(c[1][0][0], map) if not c[1][0].is_empty() else -1   # [] = entity-wide pool
					elif c[0] == "SetValueGroup":
						value_group = UnitDb.group_id(c[1][0][0], map)
				if scales:
					w.damage_scales_with_charges_of = res_group
				elif resource != "":
					w.damage_scale_resource = resource   # Brratu: +0.2 x current health; DamperDrone: +15 x energy
					w.damage_scale_group = value_group
			"TWelaReadyCooldownComponent":
				for gg in groups:
					if by_group.has(gg) and not args.is_empty():
						by_group[gg].ready_at_start = str(args[0]).to_lower() == "true"
					if groups.size() > 1:
						get.call(gg, Kind.SUB).shared_cooldown_groups = groups
			"TWelaReadyUnitPropertyComponent":
				var w: Wela = get.call(g, Kind.SUB)
				for c in calls:
					if c[0] == "MustHave":
						w.ready_props.append_array(c[1][0])
					elif c[0] == "MustNotHave":
						w.ready_not_props.append_array(c[1][0])
			"TWelaTargetConstraintResourceCompareComponent":
				var w: Wela = get.call(g, Kind.SUB)
				for c in calls:
					match c[0]:
						"ComparedResource":
							if w.compare_resource == "":
								w.compare_resource = c[1][0]
						"SetComparator": w.compare_op = c[1][0]
						"TargetFactor": w.compare_target_factor = float(c[1][0])
			"TWelaTargetConstraintResourceComponent":
				var w: Wela = get.call(g, Kind.SUB)
				var resource := "reHealth"
				var op := ""
				var reference := 0.0
				for c in calls:
					if c[0] == "CheckResource":
						resource = c[1][0]
					elif c[0] == "CheckFull" and resource == "reHealth":
						w.target_health_full = true
					elif c[0] == "CheckNotFull" and resource == "reMana":
						w.target_mana_not_full = true
					elif c[0] == "Comparator":
						op = c[1][0]
					elif c[0] == "Reference":
						reference = float(c[1][0])
					elif c[0] == "CompareCapToReference" and resource == "reHealth":
						w.cap_op = op
						w.cap_ref = reference
			"TWelaTargetConstraintNotSelfComponent":
				for gg in groups:
					get.call(gg, Kind.SUB).not_self = true
			"TWelaTargetConstraintUnitPropertyComponent", "TWelaTargetConstraintCompareUnitPropertyComponent":
				later.append([groups, calls])
			"TModifierWelaRangeComponent":
				var w: Wela = get.call(g, Kind.SUB)
				w.range_modifier_group = g
				for c in calls:
					match c[0]:
						"SetValueGroup": w.range_modifier_group = UnitDb.group_id(c[1][0][0], map)
						"ReadyGroup": w.range_ready_group = UnitDb.group_id(c[1][0][0], map)
						"ScaleWithTime": w.range_scales_with_time = true
			"TAutoBrainOnTakeDamageComponent":
				var w: Wela = get.call(g, Kind.ON_TAKE_DAMAGE)
				w.kind = Kind.ON_TAKE_DAMAGE
				var self_group := -1
				var enemy_group := -1
				for c in calls:
					if c[0] == "ModifiesAmount":
						w.modifies_amount = true
					elif c[0] == "CheckSelfForTargetsInGroup":
						self_group = UnitDb.group_id(c[1][0][0], map)
					elif c[0] == "FireTargetsInGroup":
						enemy_group = UnitDb.group_id(c[1][0][0], map)
				if self_group >= 0 and enemy_group >= 0:
					w.mirror_pairs.append([self_group, enemy_group])
			"TAutoBrainOnDealDamageComponent":
				var w: Wela = get.call(g, Kind.SUB)
				for c in calls:
					if c[0] == "FireInGroup":
						w.on_deal_groups.append(UnitDb.group_id(c[1][0][0], map))
			"TWelaTriggerCheckTakeDamageThresholdComponent":
				var w: Wela = get.call(g, Kind.ON_TAKE_DAMAGE)
				for c in calls:
					if c[0] == "LesserEqual":
						w.threshold_lesser_equal = true
			"TModifierMultiplyDealtDamageComponent":
				var value_group := g
				var must_not: int = 0
				for c in calls:
					if c[0] == "SetValueGroup":
						value_group = UnitDb.group_id(c[1][0][0], map)
					elif c[0] == "MustNotHave":
						must_not = SimConstants.damage_mask(c[1][0])
				var w: Wela = get.call(value_group, Kind.DEALT_DAMAGE_MULT)
				w.kind = Kind.DEALT_DAMAGE_MULT
				w.weapon_groups = groups
				w.must_not_have_damage_types = must_not
			"TWarheadSpottyResourceComponent":
				var res := ""
				var target_group := -1
				for c in calls:
					if c[0] == "SetResourceType":
						res = c[1][0]
					elif c[0] == "TargetGroup" and not c[1][0].is_empty():
						target_group = UnitDb.group_id(c[1][0][0], map)
					elif c[0] == "ChangesMax":
						get.call(g, Kind.SUB).changes_max = true
					elif c[0] == "RedirectToSelf":
						get.call(g, Kind.SUB).warhead_to_self = true
					elif c[0] == "AmountIsPercentage":
						get.call(g, Kind.SUB).resource_percentage = true
					elif c[0] == "SetsResourceToValue":
						get.call(g, Kind.SUB).resource_sets_value = true
				if res == "reWelaCharge" and by_group.has(g) and by_group[g].kind in [Kind.SELF_PASSIVE, Kind.SELF_GROUND]:
					by_group[g].kind = Kind.SUB   # ammo recharge groups are handled by _recharge_ammo
				if res == "reWelaCharge" and target_group >= 0:
					get.call(g, Kind.SUB).charge_gain_group = target_group
				else:
					var w: Wela = get.call(g, Kind.RESOURCE_REGEN)
					w.resource = res
					if (w.kind == Kind.SUB or w.kind == Kind.SELF_PASSIVE) and res == "reMana" and not w.changes_max:
						w.kind = Kind.RESOURCE_REGEN
			"TAutoBrainOnHealedComponent":
				var w: Wela = get.call(g, Kind.ON_HEALED)
				w.kind = Kind.ON_HEALED
				for c in calls:
					if c[0] == "TimesForEach":
						w.times_for_each = int(c[1][0])
			"TThinkImpulseFireComponent":
				var w: Wela = get.call(g, Kind.ON_HEALED)
				for c in calls:
					if c[0] == "TargetGroup":
						w.chain_groups.append(UnitDb.group_id(c[1][0][0], map))
			"TAutoBrainOnBeforeDeath", "TAutoBrainOnDeathComponent":
				get.call(g, Kind.ON_DEATH).kind = Kind.ON_DEATH
			"TAutoBrainOnUnitPropertyComponent":
				var w: Wela = get.call(g, Kind.ON_PROPERTY)
				if w.kind == Kind.SUB:
					w.kind = Kind.ON_PROPERTY   # a fight group may also trigger on a property (Groundbreaker's rupture when lifted)
				for c in calls:
					if c[0] == "TriggerOn":
						w.trigger_props.append_array(c[1][0])
	for item in later:
		for gg in item[0]:
			if gg < 0:
				continue
			var w: Wela = get.call(gg, Kind.SUB)   # constraint-only groups still need a wela (VoidSlime self checks)
			for c in item[1]:
				match c[0]:
					"MustHave": w.must_have.append_array(c[1][0])
					"MustHaveAny": w.must_have_any.append_array(c[1][0])
					"MustNotHave": w.must_not_have.append_array(c[1][0])
					"BothMustHaveAny": w.compare_any.append_array(c[1][0])
	for item in booleans:   # both sides must pass: fold their constraints into the firing group
		var w: Wela = get.call(item[0], Kind.SUB)
		for src in item[1]:
			if by_group.has(src) and src != item[0]:
				var s: Wela = by_group[src]
				w.must_have.append_array(s.must_have)
				w.must_have_any.append_array(s.must_have_any)
				w.must_not_have.append_array(s.must_not_have)
				w.compare_any.append_array(s.compare_any)
	var out: Array[Wela] = []
	out.assign(by_group.values())
	out.sort_custom(func(a, b): return a.order < b.order)
	return out


## Target constraints (unit property, compare property, not-self, resource compare, full health).
func target_allowed(target: SimEntity, owner: SimEntity = null) -> bool:
	if not_self and target == owner:
		return false
	for p in must_have:
		if not target.has(p):
			return false
	if not must_have_any.is_empty():
		var any := false
		for p in must_have_any:
			if target.has(p):
				any = true
		if not any:
			return false
	for p in must_not_have:
		if target.has(p):
			return false
	if owner != null and not compare_any.is_empty():
		var shared := false
		for p in compare_any:
			if owner.has(p) and target.has(p):
				shared = true
		if not shared:
			return false
	if target_health_full and target.health < target.max_health:
		return false
	if target_mana_not_full and target.mana >= target.mana_cap:
		return false
	if cap_op != "" and not _compare(target.max_health, cap_op, cap_ref):
		return false
	if owner != null and compare_resource == "reHealth":
		if not _compare(owner.health, compare_op, target.health * compare_target_factor):
			return false
	return true


## Owner-side readiness (TWelaReadyUnitPropertyComponent, TWelaReadyResourceCompareComponent).
func owner_ready(owner: SimEntity) -> bool:
	for p in ready_props:
		if not owner.has(p):
			return false
	for p in ready_not_props:
		if owner.has(p):
			return false
	if ready_resource == "reHealth":
		var value := owner.health if ready_absolute else (owner.health / owner.max_health if owner.max_health > 0.0 else 0.0)
		if not _compare(value, ready_op, ready_reference):
			return false
	if ready_resource == "reMana" and ready_not_empty and owner.mana <= 0:
		return false
	if ready_resource == "reWelaChargeCapacity" and ready_not_full and owner.charge_capacity >= owner.charge_capacity_cap:
		return false
	if suicide_when_empty and owner.ammo > 0:   # CheckEmpty(reWelaCharge): only once the charges are spent
		return false
	return true


static func _compare(a: float, op: String, b: float) -> bool:
	match op:
		"coGreater": return a > b
		"coGreaterEqual": return a >= b
		"coLower", "coLess": return a < b
		"coLowerEqual", "coLessEqual": return a <= b
		"coEqual": return is_equal_approx(a, b)
	return true
