class_name Wela
## One weapon/ability group of a unit, built from the unit's server components (units.json "components").
## Covers the main attack (group 1), heals (Priest), triggered abilities (Shieldblock), dealt-damage
## multipliers (Archer Relentless), resource regeneration (mana), deathrattles, chained effect groups
## (Monk Dragon Punch, Avenger double shot), auras/links (Suntower Homeland), ground self-target AoE
## (Monument of Light), on-healed triggers and cooldown resets (Defender).

enum Kind { FIGHT, SUB, ON_TAKE_DAMAGE, DEALT_DAMAGE_MULT, RESOURCE_REGEN, ON_DEATH, LINK, ON_HEALED, SELF_GROUND, ON_PROPERTY,
	PREVENT_DEATH, ON_RESOURCE }

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
# effects
var heals: bool = false
var damages: bool = false
var kills: bool = false
var exiles: bool = false
var projectile: String = ""
var apply_script: String = ""      # TWarheadApplyScriptComponent on targets
var chain_groups: Array = []       # TWelaEffectFireComponent MultiTargetGroup / TargetGroup
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
	for comp in components:
		order += 1
		var groups: Array = comp["groups"].map(func(s): return UnitDb.group_id(s, map))
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
				for c in calls:
					if c[0] == "Blocking":
						w.blocking = true
					elif c[0] == "ThinksPassively":
						w.passive = true
			"TBrainWelaSelftargetGroundComponent":
				var w: Wela = get.call(g, Kind.SELF_GROUND)
				w.kind = Kind.SELF_GROUND
			"TBrainWelaLinkComponent":
				var w: Wela = get.call(g, Kind.LINK)
				w.kind = Kind.LINK
				w.link_pattern = bb.get_value("eiLinkPattern", g, "").replace("\\", "/")
			"TWelaHelperActivateTimerComponent":
				for c in calls:
					if c[0] == "Delay":
						get.call(g, Kind.LINK).link_delay = int(c[1][0])
			"TWelaLinkEffectUnitPropertyComponent":
				if args.size() >= 1:
					get.call(g, Kind.LINK).link_property = str(args[0])
			"TWelaTargetingRadialComponent":
				for gg in groups:
					var w: Wela = get.call(gg, Kind.SUB)
					for c in calls:
						if c[0] == "SetTargetTeamConstraint":
							w.target_allies = c[1][0] == "tcAllies"
							w.target_any_team = c[1][0] == "tcAll"
						elif c[0] == "SetTargetTeamConstraintPriority":
							w.prefer_allies = c[1][0] == "tcAllies"
						elif c[0] == "PicksRandomTargets":
							w.picks_random_targets = true
						elif c[0] == "PicksRandomTargetsWithRepetition":
							w.picks_random_targets = true
							w.picks_with_repetition = true
			"TWelaEfficiencyMissingHealthComponent":
				get.call(g, Kind.SUB).efficiency_missing_health = true
			"TWelaEfficiencyUnitPropertyComponent":
				var w: Wela = get.call(g, Kind.SUB)
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
			"TWarheadSpottyKillComponent":
				var w: Wela = get.call(g, Kind.SUB)
				w.kills = true
				for c in calls:
					if c[0] == "Exile":
						w.exiles = true
			"TWelaEffectProjectileComponent":
				var w: Wela = get.call(g, Kind.SUB)
				w.projectile = bb.get_value("eiWelaUnitPattern", g, "").replace("\\", "/")
			"TWelaEffectInstantComponent":
				var w: Wela = get.call(g, Kind.SUB)
				for c in calls:
					if c[0] == "TargetGroup":
						w.instant_target_groups = c[1][0].map(func(s): return UnitDb.group_id(s, map))
			"TWelaEffectFireComponent":
				var w: Wela = get.call(g, Kind.SUB)
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
					w.apply_script = script_key(str(args[0]))
					for c in calls:
						if c[0] == "ApplyToSelfAtCreate":
							w.apply_script_to_self_at_create = true
			"TWelaEffectRemoveAfterUseComponent":
				var w: Wela = get.call(g, Kind.SUB)
				for c in calls:
					if c[0] == "TargetGroup" and c[1][0].map(func(s): return UnitDb.group_id(s, map)).has(g):
						w.remove_after_use = true
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
			"TModifierWelaDamageComponent":
				var w: Wela = get.call(g, Kind.SUB)
				var scales := false
				var res_group := g
				for c in calls:
					if c[0] == "ScaleWithResource" and c[1][0] == "reWelaCharge":
						scales = true
					elif c[0] == "ResourceGroup":
						res_group = UnitDb.group_id(c[1][0][0], map)
				if scales:
					w.damage_scales_with_charges_of = res_group
			"TWelaReadyCooldownComponent":
				for gg in groups:
					if by_group.has(gg) and not args.is_empty():
						by_group[gg].ready_at_start = str(args[0]).to_lower() == "true"
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
				for c in calls:
					if c[0] == "CheckResource":
						resource = c[1][0]
					elif c[0] == "CheckFull" and resource == "reHealth":
						w.target_health_full = true
					elif c[0] == "CheckNotFull" and resource == "reMana":
						w.target_mana_not_full = true
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
				get.call(g, Kind.ON_TAKE_DAMAGE).kind = Kind.ON_TAKE_DAMAGE
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
				if res == "reWelaCharge" and target_group >= 0:
					get.call(g, Kind.SUB).charge_gain_group = target_group
				else:
					var w: Wela = get.call(g, Kind.RESOURCE_REGEN)
					w.resource = res
					if w.kind == Kind.SUB:
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
				w.kind = Kind.ON_PROPERTY
				for c in calls:
					if c[0] == "TriggerOn":
						w.trigger_props.append_array(c[1][0])
	for item in later:
		for gg in item[0]:
			if not by_group.has(gg):
				continue
			var w: Wela = by_group[gg]
			for c in item[1]:
				match c[0]:
					"MustHave": w.must_have.append_array(c[1][0])
					"MustHaveAny": w.must_have_any.append_array(c[1][0])
					"MustNotHave": w.must_not_have.append_array(c[1][0])
					"BothMustHaveAny": w.compare_any.append_array(c[1][0])
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
	return true


static func _compare(a: float, op: String, b: float) -> bool:
	match op:
		"coGreater": return a > b
		"coGreaterEqual": return a >= b
		"coLower", "coLess": return a < b
		"coLowerEqual", "coLessEqual": return a <= b
		"coEqual": return is_equal_approx(a, b)
	return true
