class_name Lanes
## Port of TLaneManager / TLane (BaseConflict.Map.pas:519-800). A lane is a list of waypoint "gates":
## a cross-section segment with a projection center. Units head to the projection of their position
## onto the next gate in their travel direction. Values are the original hardcoded ones.

const NORMAL: int = 0    # ldNormal: travelling toward +x
const REVERSE: int = 1   # ldReverse: travelling toward -x

var lanes: Array[Lane] = []


class Lane:
	var gates: Array[PackedVector2Array] = []   # each gate: [point_a, point_b]

	func add_gate(a: Vector2, b: Vector2) -> void:
		gates.append(PackedVector2Array([a, b]))

	func distance_to_point(p: Vector2) -> float:
		var best := INF
		for g in gates:
			best = minf(best, _segment_distance(p, g[0], g[1]))
		return best

	## TLane.TryGetNextWaypoint: nearest gate that lies ahead in the travel direction (more than 1 unit away).
	## Returns the projection of the position onto that gate, or null if none is ahead.
	func next_waypoint(p: Vector2, direction: int) -> Variant:
		var best: PackedVector2Array
		var best_dist := INF
		for g in gates:
			var d := _segment_distance(p, g[0], g[1])
			var ahead := _is_left(p, g[0], g[1]) != (direction == REVERSE)
			if not ahead and d > 1.0 and d < best_dist:
				best = g
				best_dist = d
		if best_dist == INF:
			return null
		return Geometry2D.get_closest_point_to_segment(p, best[0], best[1])

	func center_first() -> Vector2:
		return (gates[0][0] + gates[0][1]) * 0.5

	func center_last() -> Vector2:
		return (gates[-1][0] + gates[-1][1]) * 0.5

	static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
		return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))

	## RLine2D.IsLeft: sign of the cross product of the line direction and the point offset.
	static func _is_left(p: Vector2, a: Vector2, b: Vector2) -> bool:
		return (b - a).cross(p - a) > 0.0


## TLaneManager.Create: the two-lane "Classic" map. RVector2.nXY negates X, XnY negates Y.
static func classic() -> Lanes:
	var l := Lanes.new()
	var p1 := Vector2(-60, -11)
	var p2 := Vector2(-60, -35)
	var lane := Lane.new()
	lane.add_gate(p1, p2)
	lane.add_gate(Vector2(-p1.x, p1.y), Vector2(-p2.x, p2.y))
	l.lanes.append(lane)
	lane = Lane.new()
	lane.add_gate(Vector2(p2.x, -p2.y), Vector2(p1.x, -p1.y))
	lane.add_gate(Vector2(-p2.x, -p2.y), Vector2(-p1.x, -p1.y))
	l.lanes.append(lane)
	return l


## TLaneManager.Single: the one-lane map (lane along y = -23).
static func single() -> Lanes:
	var l := Lanes.new()
	var p1 := Vector2(-60, -11)
	var p2 := Vector2(-60, -35)
	var lane := Lane.new()
	lane.add_gate(p1, p2)
	lane.add_gate(Vector2(-p1.x, p1.y), Vector2(-p2.x, p2.y))
	l.lanes.append(lane)
	return l


func nearest_lane(p: Vector2) -> Lane:
	var best: Lane = lanes[0]
	var best_dist := INF
	for lane in lanes:
		var d := lane.distance_to_point(p)
		if d < best_dist:
			best_dist = d
			best = lane
	return best


## TLaneManager.GetLanePropertiesOfEntity: direction is toward the nearest enemy nexus.
static func direction_toward(from: Vector2, enemy_nexus: Vector2) -> int:
	return NORMAL if enemy_nexus.x > from.x else REVERSE
