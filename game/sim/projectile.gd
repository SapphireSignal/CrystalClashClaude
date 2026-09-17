class_name Projectile
## A homing projectile (TBrainProjectileComponent + TMovementComponent.IdleDirect on the server):
## spawned at the shooter, flies straight at the target entity's current position at eiSpeed,
## and applies the shooter's weapon damage on arrival if the target is still valid.

var id: int
var unit_id: String
var team: int
var source_id: int
var target_id: int
var position: Vector2
var last_target_position: Vector2
var speed: float           # world units per ms
var speed_random: float = 0.0   # eiSpeed given as '(a + random * b) / 1000': speed holds a, this b, resolved by the sim
var damage: float
var damage_type: int
var created_at: int
var aoe: float = 0.0          # splash radius on impact (eiWelaAreaOfEffect passed from the shooter or own)
var splash_factor: float = 10000.0   # eiWelaSplashfactor: total damage pool = damage * factor
var gives_mana: bool = false         # TWarheadSpottyResourceComponent(reMana): +damage mana on impact (souls)
var on_hit_script: String = ""      # TAutoBrainOnDealDamageComponent + TWarheadApplyScriptComponent (VoidWorm: Frozen)
var on_hit_must_have: Array = []
var on_hit_must_not_have: Array = []
var impact_script: String = ""      # TWarheadApplyScriptComponent on the impact group itself (HeartOfTheForestProjectile)
var damages: bool = false            # has a damage warhead
var raises_max_health: bool = false  # TWarheadSpottyResourceComponent(reHealth).ChangesMax (Oracle: +60 max hp)
var gives_charges: int = 0           # TWarheadSpottyResourceComponent(reWelaCharge): +eiWelaDamage of that group
# TBrainProjectileComponent.Bounces: after a hit jump to a random unhit enemy within bounce_range, up to
# eiWelaCount times; a depleting shot (Wisp) loses the damage it dealt (TAutoBrainOnDealDamageComponent
# WriteAmountTo(eiWelaDamage) with modifier -1) and stops when nothing is left
var bounces_max: int = 0
var bounce_range: float = 0.0
var bounce_must_not_have: Array = []
var bounce_count: int = 0
var hit_ids: Array = []
var damage_change_per_hit: float = 0.0   # eiWelaModifier of the on-deal-damage group (-1 = depleting)


func _init(p_unit_id: String, league: int) -> void:
	unit_id = p_unit_id
	var bb := Blackboard.new()
	UnitDb.fill_blackboard(bb, unit_id, league)
	var raw_speed: Variant = bb.get_value("eiSpeed", Blackboard.ANY_GROUP, 20.0 / 1000.0)
	if raw_speed is String:
		var m := RegEx.create_from_string("\\(\\s*([0-9.]+)\\s*\\+\\s*random\\s*\\*\\s*([0-9.]+)\\s*\\)\\s*/\\s*1000").search(raw_speed)
		assert(m != null, "unsupported eiSpeed expression %s in %s" % [raw_speed, unit_id])
		speed = float(m.get_string(1))
		speed_random = float(m.get_string(2))
	else:
		speed = bb.get_float("eiSpeed", Blackboard.ANY_GROUP, 20.0 / 1000.0)
	for g in bb.groups_of("eiWelaAreaOfEffect"):   # projectile scripts with their own splash group
		aoe = maxf(aoe, bb.get_float("eiWelaAreaOfEffect", g, 0.0))
	for g in bb.groups_of("eiWelaSplashfactor"):
		splash_factor = bb.get_float("eiWelaSplashfactor", g, 10000.0)
	var hit_group := ""
	var bounce_group := ""
	for comp in UnitDb.raw(unit_id).get("components", []):
		var calls: Array = comp.get("calls", [])
		match comp["class"]:
			"TBrainProjectileComponent":
				for c in calls:
					if c[0] == "Bounces":
						bounce_group = c[1][0][0]
						bounces_max = bb.get_int("eiWelaCount", int(comp["groups"][0]), 0)
						bounce_range = bb.get_float("eiWelaRange", int(bounce_group), 0.0)
			"TWarheadSpottyResourceComponent":
				var res := ""
				var changes_max := false
				for c in calls:
					if c[0] == "SetResourceType":
						res = c[1][0]
					elif c[0] == "ChangesMax":
						changes_max = true
				if res == "reMana":
					gives_mana = true
				elif res == "reHealth" and changes_max:
					raises_max_health = true
				elif res == "reWelaCharge":
					gives_charges = int(bb.get_float("eiWelaDamage", int(comp["groups"][0]), 1.0))
			"TAutoBrainOnDealDamageComponent":
				var writes_damage := false
				for c in calls:
					if c[0] == "WriteAmountTo" and c[1][0] == "eiWelaDamage":
						writes_damage = true
				if writes_damage:
					damage_change_per_hit = bb.get_float("eiWelaModifier", int(comp["groups"][0]), 1.0)
				else:
					hit_group = comp["groups"][0]
			"TWelaEffectFireComponent":
				for c in calls:
					if c[0] == "TargetGroup":
						hit_group = c[1][0][0]
			"TWelaTargetConstraintUnitPropertyComponent":
				if hit_group != "" and comp["groups"].has(hit_group):
					for c in calls:
						if c[0] == "MustHave":
							on_hit_must_have.append_array(c[1][0])
						elif c[0] == "MustNotHave":
							on_hit_must_not_have.append_array(c[1][0])
				if bounce_group != "" and comp["groups"].has(bounce_group):
					for c in calls:
						if c[0] == "MustNotHave":
							bounce_must_not_have.append_array(c[1][0])
			"TWarheadApplyScriptComponent":
				if hit_group != "" and comp["groups"].has(hit_group):
					on_hit_script = Wela.script_key(str(comp["args"][0]))
				else:
					impact_script = Wela.script_key(str(comp["args"][0]))
			"TWarheadSpottyDamageComponent", "TWarheadSplashDamageComponent":
				damages = true
