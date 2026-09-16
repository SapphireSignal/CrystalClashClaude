class_name Blackboard
## Per-entity stat store, mirrors TBlackboard (Entity.pas:100-119).
## Values are keyed by event name and component group. Group -1 means "entity-wide" (the original's []).
## get_value() falls back from the group to the entity-wide value (ReadHierarchic, Entity.pas:240).

const ANY_GROUP: int = -1

var _values: Dictionary = {}   # key: "event" -> Dictionary[group:int -> Variant]


func set_value(event: String, group: int, value: Variant) -> void:
	var by_group: Dictionary = _values.get(event, {})
	by_group[group] = value
	_values[event] = by_group


func has_value(event: String, group: int = ANY_GROUP) -> bool:
	var by_group: Dictionary = _values.get(event, {})
	return by_group.has(group) or by_group.has(ANY_GROUP)


func get_value(event: String, group: int = ANY_GROUP, default: Variant = null) -> Variant:
	var by_group: Dictionary = _values.get(event, {})
	if by_group.has(group):
		return by_group[group]
	if by_group.has(ANY_GROUP):
		return by_group[ANY_GROUP]
	return default


func get_float(event: String, group: int = ANY_GROUP, default: float = 0.0) -> float:
	var v: Variant = get_value(event, group, default)
	return float(v)


func get_int(event: String, group: int = ANY_GROUP, default: int = 0) -> int:
	var v: Variant = get_value(event, group, default)
	return int(v)


func groups_of(event: String) -> Array:
	return _values.get(event, {}).keys()
