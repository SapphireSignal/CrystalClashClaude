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
var damage: float
var damage_type: int
var created_at: int
var aoe: float = 0.0          # splash radius on impact (eiWelaAreaOfEffect passed from the shooter or own)
var splash_factor: float = 10000.0   # eiWelaSplashfactor: total damage pool = damage * factor
var gives_mana: bool = false         # TWarheadSpottyResourceComponent(reMana): +damage mana on impact (souls)


func _init(p_unit_id: String, league: int) -> void:
	unit_id = p_unit_id
	var bb := Blackboard.new()
	UnitDb.fill_blackboard(bb, unit_id, league)
	speed = bb.get_float("eiSpeed", Blackboard.ANY_GROUP, 20.0 / 1000.0)
	for g in bb.groups_of("eiWelaAreaOfEffect"):   # projectile scripts with their own splash group
		aoe = maxf(aoe, bb.get_float("eiWelaAreaOfEffect", g, 0.0))
	for g in bb.groups_of("eiWelaSplashfactor"):
		splash_factor = bb.get_float("eiWelaSplashfactor", g, 10000.0)
	for comp in UnitDb.raw(unit_id).get("components", []):
		if comp["class"] == "TWarheadSpottyResourceComponent":
			for c in comp.get("calls", []):
				if c[0] == "SetResourceType" and c[1][0] == "reMana":
					gives_mana = true
