class_name Pathfinding
## Port of BaseConflict.Classes.Pathfinding.pas: square tile grid over the map, 8-neighbour A*,
## permanent blocking from the Walkzone polygon and buildings, "standing" blockers per entity, and
## space-time reservations (TIMESLOTLENGTH ms slots in a ring buffer of SLOT_COUNT) so moving units
## avoid each other. Paths are capped at MAX_PATH_LENGTH world units and re-planned constantly.

const TILE_SIZE: float = SimConstants.PATHFINDING_TILE_SIZE
const TIMESLOT_MS: int = 150
const SLOT_COUNT: int = 50
const MAX_PATH_LENGTH: float = 15.0   # PATHFINDING_MAX_COMPUTED_PATH_LENGTH

var origin: Vector2                    # world position of tile (0,0) corner
var width: int
var height: int
var _permanent: PackedByteArray        # 1 = blocked by the environment (outside the Walkzone)
var _buildings: PackedInt32Array       # number of buildings covering the tile (Relocate moves them)
var _standing: PackedInt32Array        # count of entities standing on the tile
var _reservations: Dictionary = {}     # tile index -> PackedByteArray(SLOT_COUNT) of blocked slots
var _reservation_owner: Dictionary = {} # tile index -> PackedInt32Array(SLOT_COUNT) entity id that reserved
var _paths: Dictionary = {}            # entity id -> Array of [tile_index, enter_ms, duration_ms]
var lanes: Lanes

const DIAGONAL: float = TILE_SIZE * 1.41421356
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]


func _init(bounds: Rect2, walk_polygons: Array, p_lanes: Lanes) -> void:
	lanes = p_lanes
	origin = bounds.position
	width = ceili(bounds.size.x / TILE_SIZE)
	height = ceili(bounds.size.y / TILE_SIZE)
	_permanent.resize(width * height)
	_buildings.resize(width * height)
	_standing.resize(width * height)
	for y in height:
		for x in width:
			var center := tile_center(Vector2i(x, y))
			if not _point_in_multipolygon(center, walk_polygons):
				_permanent[y * width + x] = 1


# ---------------------------------------------------------------- geometry

func tile_of(pos: Vector2) -> Vector2i:
	var t := Vector2i(floori((pos.x - origin.x) / TILE_SIZE), floori((pos.y - origin.y) / TILE_SIZE))
	return Vector2i(clampi(t.x, 0, width - 1), clampi(t.y, 0, height - 1))


func index_of(t: Vector2i) -> int:
	return t.y * width + t.x


func tile_from_index(i: int) -> Vector2i:
	return Vector2i(i % width, i / width)


func tile_center(t: Vector2i) -> Vector2:
	return origin + Vector2((t.x + 0.5) * TILE_SIZE, (t.y + 0.5) * TILE_SIZE)


func is_permanently_blocked(i: int) -> bool:
	return _permanent[i] != 0 or _buildings[i] > 0


func is_blocked(i: int) -> bool:
	return _permanent[i] != 0 or _buildings[i] > 0 or _standing[i] > 0


## Polygons: Array of {"points": PackedVector2Array, "subtractive": bool}. A point is inside the
## multipolygon when inside any additive polygon and not inside any subtractive one.
static func _point_in_multipolygon(p: Vector2, polygons: Array) -> bool:
	var inside := false
	for poly in polygons:
		if not poly["subtractive"] and Geometry2D.is_point_in_polygon(p, poly["points"]):
			inside = true
			break
	if not inside:
		return false
	for poly in polygons:
		if poly["subtractive"] and Geometry2D.is_point_in_polygon(p, poly["points"]):
			return false
	return true


# ---------------------------------------------------------------- blocking

func block_permanent_area(center: Vector2, radius: float) -> void:
	_change_building_area(center, radius, 1)


func unblock_permanent_area(center: Vector2, radius: float) -> void:
	_change_building_area(center, radius, -1)


func _change_building_area(center: Vector2, radius: float, delta: int) -> void:
	var lo := tile_of(center - Vector2(radius, radius))
	var hi := tile_of(center + Vector2(radius, radius))
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			if tile_center(Vector2i(x, y)).distance_to(center) <= radius:
				_buildings[y * width + x] = maxi(0, _buildings[y * width + x] + delta)


func stand_on(i: int) -> void:
	_standing[i] += 1


func leave(i: int) -> void:
	_standing[i] = maxi(0, _standing[i] - 1)


func _slots(i: int) -> PackedByteArray:
	if not _reservations.has(i):
		var arr := PackedByteArray()
		arr.resize(SLOT_COUNT)
		_reservations[i] = arr
		var owners := PackedInt32Array()
		owners.resize(SLOT_COUNT)
		_reservation_owner[i] = owners
	return _reservations[i]


func is_walkable_at(i: int, time_ms: int, stay_ms: int) -> bool:
	if is_blocked(i):
		return false
	if not _reservations.has(i):
		return true
	var slots: PackedByteArray = _reservations[i]
	var first := time_ms / TIMESLOT_MS
	for t in range(0, stay_ms / TIMESLOT_MS + 1):
		if slots[(first + t) % SLOT_COUNT]:
			return false
	return true


func reserve(i: int, entity_id: int, start_ms: int, duration_ms: int) -> void:
	var slots := _slots(i)
	var owners: PackedInt32Array = _reservation_owner[i]
	var first := start_ms / TIMESLOT_MS
	for t in range(0, duration_ms / TIMESLOT_MS + 1):
		var s := (first + t) % SLOT_COUNT
		slots[s] = 1
		owners[s] = entity_id


func release(i: int, entity_id: int, start_ms: int, duration_ms: int) -> void:
	if not _reservations.has(i):
		return
	var slots: PackedByteArray = _reservations[i]
	var owners: PackedInt32Array = _reservation_owner[i]
	var first := start_ms / TIMESLOT_MS
	for t in range(0, duration_ms / TIMESLOT_MS + 1):
		var s := (first + t) % SLOT_COUNT
		if owners[s] == entity_id:
			slots[s] = 0
			owners[s] = 0


func cancel_path(entity_id: int) -> void:
	var path: Array = _paths.get(entity_id, [])
	for wp in path:
		release(wp[0], entity_id, wp[1], wp[2])
	_paths.erase(entity_id)


# ---------------------------------------------------------------- A*

## Returns an Array of tile indices from the source tile to the last reached tile (inclusive),
## or an empty array when no path exists. Reserves the time slots for entity_id.
func compute_path(entity_id: int, from: Vector2, to: Vector2, now_ms: int, speed: float,
		use_waypoints: bool, ignore_others: bool, direction: int) -> Array:
	cancel_path(entity_id)
	var source := index_of(tile_of(from))
	var target := index_of(tile_of(to))
	var g := {source: 0.0}
	var enter := {source: now_ms}
	var parent := {}
	var closed := {}
	var open := _Heap.new()
	open.push(source, _heuristic(source, target, direction, use_waypoints))
	var end_tile := -1
	while not open.is_empty():
		var current: int = open.pop()
		if closed.has(current):
			continue
		if current == target or g[current] >= MAX_PATH_LENGTH:
			end_tile = current
			break
		closed[current] = true
		var ct := tile_from_index(current)
		for d in NEIGHBOURS:
			var nt := ct + d
			if nt.x < 0 or nt.y < 0 or nt.x >= width or nt.y >= height:
				continue
			var n := index_of(nt)
			if closed.has(n):
				continue
			var cost := DIAGONAL if (d.x != 0 and d.y != 0) else TILE_SIZE
			var new_g: float = g[current] + cost
			var enter_time: int = now_ms + roundi((g[current] + cost / 2.0) / speed)
			var stay: int = roundi(DIAGONAL / speed)
			if n == target:
				parent[n] = current
				g[n] = new_g
				enter[n] = enter_time
				end_tile = n
				break
			var walkable := (not is_permanently_blocked(n)) if ignore_others else is_walkable_at(n, enter_time, stay)
			if not walkable:
				continue
			if not g.has(n) or g[n] > new_g:
				parent[n] = current
				g[n] = new_g
				enter[n] = enter_time
				open.push(n, new_g + _heuristic(n, target, direction, use_waypoints))
		if end_tile >= 0:
			break
	if end_tile < 0:
		return []
	var path: Array = []
	var t := end_tile
	while true:
		path.push_front(t)
		if t == source:
			break
		t = parent[t]
	# reserve time slots (DoPathfinding tail)
	var stored: Array = []
	for i in path.size():
		var enter_ms: int = enter[path[i]]
		var duration: int
		if i == path.size() - 1:
			duration = roundi(DIAGONAL * 0.5 / speed)
		else:
			duration = enter[path[i + 1]] - enter_ms
		reserve(path[i], entity_id, enter_ms, duration)
		stored.append([path[i], enter_ms, duration])
	_paths[entity_id] = stored
	return path


## ComputeAndSetHeuristicCost: beeline, or the distance along the remaining lane waypoints.
func _heuristic(tile: int, target: int, direction: int, use_waypoints: bool) -> float:
	var here := tile_center(tile_from_index(tile))
	var goal := tile_center(tile_from_index(target))
	if not use_waypoints or lanes == null:
		return here.distance_to(goal)
	var lane := lanes.nearest_lane(here)
	var cost := 0.0
	var last := here
	var pos := here
	var wp: Variant = lane.next_waypoint(pos, direction)
	while wp != null:
		var gate: Vector2 = wp
		var ahead: bool = (gate.x > here.x) if direction == Lanes.NORMAL else (gate.x < here.x)
		if ahead:
			cost += here.distance_to(gate) if cost == 0.0 else last.distance_to(gate)
		last = gate
		pos = gate
		wp = lane.next_waypoint(pos, direction)
	if cost == 0.0:
		return here.distance_to(goal)
	return cost + last.distance_to(goal)


## Binary min-heap of [key, value] pairs used as the open list.
class _Heap:
	var _keys: PackedFloat32Array = []
	var _values: PackedInt32Array = []

	func is_empty() -> bool:
		return _keys.is_empty()

	func push(value: int, key: float) -> void:
		_keys.append(key)
		_values.append(value)
		var i := _keys.size() - 1
		while i > 0:
			var p := (i - 1) / 2
			if _keys[p] <= _keys[i]:
				break
			_swap(i, p)
			i = p

	func pop() -> int:
		var top := _values[0]
		var last := _keys.size() - 1
		_swap(0, last)
		_keys.resize(last)
		_values.resize(last)
		var i := 0
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < last and _keys[l] < _keys[m]:
				m = l
			if r < last and _keys[r] < _keys[m]:
				m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return top

	func _swap(a: int, b: int) -> void:
		var k := _keys[a]
		_keys[a] = _keys[b]
		_keys[b] = k
		var v := _values[a]
		_values[a] = _values[b]
		_values[b] = v
