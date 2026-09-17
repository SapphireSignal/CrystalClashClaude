class_name BuildZone
## Port of TBuildZone (BaseConflict.Map.pas:39-515): an 8x3 grid of 2x2 world-unit fields where spawner
## cards are placed. Corners are banned. Spawned units appear around SpawnTarget, offset by the field's
## position relative to the grid (TBrainSpawnerComponent.Spawn with ApplyGridOffset).

const GRIDNODESIZE: float = 2.0
const FIELD_BANNED: int = -2
const FIELD_FREE: int = -1

var id: int
var team: int
var center: Vector2
var size: Vector2i = SimConstants.BUILDGRID_SIZE
var front: Vector2
var spawn_target: Vector2
var spawn_direction: Vector2
var _fields: Dictionary = {}     # Vector2i -> entity id, FIELD_FREE or FIELD_BANNED


func _init(p_id: int, p_team: int, p_center: Vector2, p_front: Vector2, p_spawn_target: Vector2, p_spawn_dir: Vector2) -> void:
	id = p_id
	team = p_team
	center = p_center
	front = p_front.normalized()
	spawn_target = p_spawn_target
	spawn_direction = p_spawn_dir.normalized()
	for x in size.x:
		for y in size.y:
			_fields[Vector2i(x, y)] = FIELD_FREE
	for c in [Vector2i(0, 0), Vector2i(size.x - 1, 0), Vector2i(0, size.y - 1), Vector2i(size.x - 1, size.y - 1)]:
		_fields[c] = FIELD_BANNED


## RVector2.GetOrthogonal: (-y, x)
func left() -> Vector2:
	return Vector2(-front.y, front.x)


func center_of_field(coord: Vector2i) -> Vector2:
	return center + GRIDNODESIZE * front * (coord.y - size.y / 2.0 + 0.5) + GRIDNODESIZE * left() * (coord.x - size.x / 2.0 + 0.5)


func position_to_coord(pos: Vector2) -> Vector2i:
	var offset := pos - center
	return Vector2i(
		roundi(left().dot(offset) / GRIDNODESIZE + size.x / 2.0 - 0.5),
		roundi(front.dot(offset) / GRIDNODESIZE + size.y / 2.0 - 0.5))


func in_range(coord: Vector2i) -> bool:
	return coord.x >= 0 and coord.y >= 0 and coord.x < size.x and coord.y < size.y


func is_banned(coord: Vector2i) -> bool:
	return not in_range(coord) or _fields[coord] <= FIELD_BANNED


func is_free(coord: Vector2i) -> bool:
	return in_range(coord) and _fields[coord] == FIELD_FREE


func occupy(coord: Vector2i, entity_id: int) -> void:
	_fields[coord] = entity_id


func release(coord: Vector2i) -> void:
	if in_range(coord) and _fields[coord] >= 0:
		_fields[coord] = FIELD_FREE


func entity_at(coord: Vector2i) -> int:
	return _fields.get(coord, FIELD_FREE)


## All non-banned coordinates (the 20 spawn slots), in x-major order like TSpawnrotation.Fill.
func spawn_slots() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in size.x:
		for y in size.y:
			var c := Vector2i(x, y)
			if not is_banned(c):
				out.append(c)
	return out


## TBrainSpawnerComponent.Spawn with ApplyGridOffset: the field offset in grid space (base -Front, -Left,
## inverted = transposed) mapped into the spawn-target base (SpawnDirection, its orthogonal).
func spawn_position_for_field(coord: Vector2i) -> Vector2:
	var d := center_of_field(coord) - center
	var grid_space := Vector2((-front).dot(d), (-left()).dot(d))
	var sd := spawn_direction
	var sd_orth := Vector2(-sd.y, sd.x)
	return spawn_target + sd * grid_space.x + sd_orth * grid_space.y
