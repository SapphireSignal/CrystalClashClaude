class_name Wela
## One weapon/ability group of a unit, built from the unit's server components (units.json "components").
## Covers the main attack (group 1), heals (e.g. Priest group 2), triggered abilities (Shieldblock),
## dealt-damage multipliers (Archer Relentless), resource regeneration (mana) and deathrattles.

enum Kind { FIGHT, ON_TAKE_DAMAGE, DEALT_DAMAGE_MULT, RESOURCE_REGEN, ON_DEATH }

var group: int
var kind: Kind
var order: int = 0                # component creation order (think chain order)
# targeting
var target_allies: bool = false
var must_have: Array = []
var must_have_any: Array = []
var must_not_have: Array = []
var efficiency_missing_health: bool = false
var picks_random_targets: bool = false
var blocking: bool = false         # TBrainWelaFightComponent.Blocking: attack does not run while this is busy
# effects
var heals: bool = false
var projectile: String = ""
var apply_script: String = ""      # TWarheadApplyScriptComponent on targets
var mana_cost: int = 0
var ready_at_start: bool = true
# ON_TAKE_DAMAGE (Shieldblock)
var threshold_lesser_equal: bool = false
# DEALT_DAMAGE_MULT (Relentless)
var weapon_groups: Array = []
var must_not_have_damage_types: int = 0
# RESOURCE_REGEN
var resource: String = ""
# runtime
var cooldown_ready_at: int = 0
var next_at: int = -1


## Parse all welas of a unit from its component list. Returns them in think-chain order.
static func parse(components: Array, bb: Blackboard) -> Array[Wela]:
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
	var target_constraints: Array = []   # applied after all groups exist
	for comp in components:
		order += 1
		var groups: Array = comp["groups"].map(func(s): return int(s) if str(s).is_valid_int() else -1)
		var calls: Array = comp.get("calls", [])
		var args: Array = comp.get("args", [])
		var g: int = groups[0] if not groups.is_empty() else -1
		match comp["class"]:
			"TBrainWelaFightComponent":
				var w: Wela = get.call(g, Kind.FIGHT)
				for c in calls:
					if c[0] == "Blocking":
						w.blocking = true
			"TWelaTargetingRadialComponent":
				var w: Wela = get.call(g, Kind.FIGHT)
				for c in calls:
					if c[0] == "SetTargetTeamConstraint":
						w.target_allies = c[1][0] == "tcAllies"
					elif c[0] == "PicksRandomTargets":
						w.picks_random_targets = true
			"TWelaEfficiencyMissingHealthComponent":
				get.call(g, Kind.FIGHT).efficiency_missing_health = true
			"TWarheadSpottyHealComponent":
				get.call(g, Kind.FIGHT).heals = true
			"TWelaEffectProjectileComponent":
				var w: Wela = get.call(g, Kind.FIGHT)
				w.projectile = bb.get_value("eiWelaUnitPattern", g, "").replace("\\", "/")
			"TWarheadApplyScriptComponent":
				if not args.is_empty() and by_group.has(g):
					by_group[g].apply_script = str(args[0]).get_file().get_basename()
			"TWelaReadyCostComponent":
				if by_group.has(g):
					by_group[g].mana_cost = bb.get_int("eiResourceCost.reMana", g, 0)
			"TWelaReadyCooldownComponent":
				if by_group.has(g) and not args.is_empty():
					by_group[g].ready_at_start = str(args[0]).to_lower() == "true"
			"TWelaTargetConstraintUnitPropertyComponent":
				target_constraints.append([groups, calls])
			"TAutoBrainOnTakeDamageComponent":
				var w: Wela = get.call(g, Kind.ON_TAKE_DAMAGE)
				w.kind = Kind.ON_TAKE_DAMAGE
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
						value_group = int(c[1][0][0])
					elif c[0] == "MustNotHave":
						must_not = SimConstants.damage_mask(c[1][0])
				var w: Wela = get.call(value_group, Kind.DEALT_DAMAGE_MULT)
				w.kind = Kind.DEALT_DAMAGE_MULT
				w.weapon_groups = groups
				w.must_not_have_damage_types = must_not
			"TWarheadSpottyResourceComponent":
				var res := ""
				for c in calls:
					if c[0] == "SetResourceType":
						res = c[1][0]
				if res == "reMana" and not by_group.has(g):
					var w: Wela = get.call(g, Kind.RESOURCE_REGEN)
					w.resource = res
			"TAutoBrainOnBeforeDeath", "TAutoBrainOnDeathComponent":
				var w: Wela = get.call(g, Kind.ON_DEATH)
				w.kind = Kind.ON_DEATH
	for tc in target_constraints:
		for g in tc[0]:
			if not by_group.has(g):
				continue
			var w: Wela = by_group[g]
			for c in tc[1]:
				match c[0]:
					"MustHave": w.must_have.append_array(c[1][0])
					"MustHaveAny": w.must_have_any.append_array(c[1][0])
					"MustNotHave": w.must_not_have.append_array(c[1][0])
	var out: Array[Wela] = []
	out.assign(by_group.values())
	out.sort_custom(func(a, b): return a.order < b.order)
	return out


## TWelaTargetConstraintUnitPropertyComponent.IsPossible for a candidate.
func target_allowed(target: SimEntity) -> bool:
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
	return true
