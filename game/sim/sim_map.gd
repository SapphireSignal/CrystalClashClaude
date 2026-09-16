class_name SimMap
## Loads game/data/maps/<Name>.json (from tools/extract_maps.py) and exposes zones, lanes and the
## scenario base layout (Scripts/Scenarios/PvPBase.dws, PvPRed.dws, PvPBlue.dws).

const SINGLE := "Single"
const CLASSIC := "Classic"

var name: String
var bounds: Rect2
var zones: Dictionary = {}          # zone name -> Array of {"points": PackedVector2Array, "subtractive": bool}
var lanes: Lanes
var pathfinding: Pathfinding


static func load_map(map_name: String) -> SimMap:
	var m := SimMap.new()
	m.name = map_name
	var file := FileAccess.open("res://game/data/maps/%s.json" % map_name, FileAccess.READ)
	assert(file != null, "missing map json for %s, run tools/extract_maps.py" % map_name)
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	var b: Dictionary = data["bounds"]
	m.bounds = Rect2(b["left"], b["top"], b["right"] - b["left"], b["bottom"] - b["top"])
	for zone_name in data["zones"]:
		var polys: Array = []
		for poly in data["zones"][zone_name]:
			var pts := PackedVector2Array()
			for p in poly["points"]:
				pts.append(Vector2(p[0], p[1]))
			polys.append({"points": pts, "subtractive": poly["subtractive"]})
		m.zones[zone_name] = polys
	m.lanes = Lanes.single() if map_name == SINGLE else Lanes.classic()
	m.pathfinding = Pathfinding.new(m.bounds, m.zones["Walkzone"], m.lanes)
	return m


func is_single() -> bool:
	return name == SINGLE


func in_zone(zone_name: String, p: Vector2) -> bool:
	return Pathfinding._point_in_multipolygon(p, zones.get(zone_name, []))


## Base layout per team: {"nexus": Vector2, "lanetowers": [Vector2], "lane_nodes": [Vector2]}.
## Blue (team 1) sits at -x, Red (team 2) at +x. Values from PvPRed.dws / PvPBlue.dws / PvPBase.dws.
func base_layout(team: int) -> Dictionary:
	var sx := -1.0 if team == 1 else 1.0
	if is_single():
		return {"nexus": Vector2(96 * sx, -23), "lanetowers": [Vector2(48 * sx, -23)]}
	return {"nexus": Vector2(92 * sx, 0), "lanetowers": [Vector2(48 * sx, 23), Vector2(48 * sx, -23)]}


func lane_node_positions() -> Array:
	return [Vector2(0, -23)] if is_single() else [Vector2(0, -23), Vector2(0, 23)]
