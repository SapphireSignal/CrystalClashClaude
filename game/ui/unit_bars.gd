class_name UnitBars
extends Control
## Bars above units, drawn in screen space at the projected world position
## (TEntityDisplayWrapperComponent / TResourceDisplay*Component in BaseConflict.EntityComponents.Client.GUI.pas).
## Health: 63x8, shown while damaged or with overheal (coGameplayHealthbarMode = hmDamaged) or while Alt is
## held. Extra bars from units.json `unit_bars`: integer chunk bars (mana / ammo) and progress bars.

const BAR_W := 63.0
const HEALTH_H := 8.0
const BAR_H := 6.0
const BACKGROUND := Color(0, 0, 0, 0x99 / 255.0)
const UNIT_TOP := 1.8      # capsule height stands in for the bounding sphere top
const BUILDING_TOP := 4.0
const GRADIENTS := {   # top, bottom
	"health_0": [Color("DEDEDE"), Color("404040")],
	"health_1": [Color("51A2FF"), Color("2850A0")],
	"health_2": [Color("E66868"), Color("723333")],
	"reOverheal": [Color("FFFFFF"), Color("808080")],
	"reMana": [Color("FAF800"), Color("8B8A00")],
	"reWelaCharge": [Color("63D9DB"), Color("377D7D")],
	"other": [Color("DEDEDE"), Color("404040")],
}

var _sim: Simulation
var _own_team: int
var _camera: Camera3D


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE


func setup(sim: Simulation, own_team: int, camera: Camera3D) -> void:
	_sim = sim
	_own_team = own_team
	_camera = camera


func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	if _sim == null or _camera == null:
		return
	# coGameplayHealthbarMode: hmAlways shows every bar, hmDamaged only injured/overhealed units, hmNone hides
	# them; Alt shows all bars in every mode.
	var mode := ClientSettings.healthbar_mode()
	var always := Input.is_key_pressed(KEY_ALT) or mode == ClientSettings.HealthbarMode.ALWAYS
	var damaged_only := mode != ClientSettings.HealthbarMode.NONE
	for e in _sim.alive_entities():
		if e.is_spawner() or e.exiled or e.max_health <= 0.0 or e.is_lane_node():
			continue
		var bars := []   # [height, draw callable]
		var health_visible := e.health > 0.0 and (always or (damaged_only and (e.health < e.max_health or e.overheal > 0.0)))
		if health_visible:
			bars.append([HEALTH_H, _draw_health.bind(e)])
		if UnitDb.has_unit(e.unit_id):
			for bar in UnitDb.raw(e.unit_id).get("unit_bars", []):
				var current := _resource(e, bar["resource"])
				var cap := _resource_cap(e, bar)
				if (bar.get("hide_if_empty", false) and current <= 0) or (bar.get("hide_if_full", false) and current >= cap):
					continue
				var h: float = bar.get("size_y", BAR_H)
				if bar["kind"] == "integer":
					bars.append([h, _draw_chunks.bind(e, bar, current, cap)])
				else:
					bars.append([h, _draw_progress.bind(e, bar, current, cap)])
		if bars.is_empty():
			continue
		var top := BUILDING_TOP if e.is_building() else UNIT_TOP
		var world := Vector3(e.position.x, top + 1.0, -e.position.y)   # sim -> global (World is mirrored on Z)
		if _camera.is_position_behind(world):
			continue
		var screen := _camera.unproject_position(world)
		if not Rect2(Vector2.ZERO, get_viewport_rect().size).grow(BAR_W).has_point(screen):
			continue   # off-screen (grazing projections give huge coordinates that break polygon drawing)
		var total := 0.0
		for b in bars:
			total += b[0]
		var y := screen.y - total / 2.0   # wrapper anchored at its centre
		for b in bars:
			b[1].call(Rect2(screen.x - BAR_W / 2.0, y, BAR_W, b[0]))
			y += b[0]


func _resource(e: SimEntity, resource: String) -> int:
	match resource:
		"reMana": return e.mana
		"reWelaCharge": return e.ammo
		"reHealth": return int(e.health)
	return 0


func _resource_cap(e: SimEntity, bar: Dictionary) -> int:
	if bar.has("fixed_cap"):
		return int(bar["fixed_cap"])
	match bar["resource"]:
		"reMana": return e.mana_cap
		"reWelaCharge": return e.ammo_cap
		"reHealth": return int(e.max_health)
	return 1


func _gradient(key: String) -> Array:
	return GRADIENTS.get(key, GRADIENTS["other"])


## Bar frame: background with a 1 px inset black border and 1 px padding.
func _frame(rect: Rect2) -> Rect2:
	draw_rect(rect, BACKGROUND)
	draw_rect(rect, Color.BLACK, false, 1.0)
	return rect.grow(-1.0)


func _fill(rect: Rect2, gradient: Array) -> void:
	if rect.size.x < 1.0 or rect.size.y < 1.0 or not rect.position.is_finite() or not rect.end.is_finite():
		return   # degenerate polygons (and units projected from behind the camera) fail to triangulate
	var top: Color = gradient[0]
	var bottom: Color = gradient[1]
	if rect.size.x < 2.0 or rect.size.y < 2.0:   # a thin sliver shows no gradient and fails ear clipping
		draw_rect(rect, top)
		return
	draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))


func _draw_health(rect: Rect2, e: SimEntity) -> void:
	var inner := _frame(rect)
	if e.overheal > 0.0:   # overheal fills the whole bar behind the health
		_fill(inner, _gradient("reOverheal"))
	var progress := clampf(e.health / (e.max_health + e.overheal), 0.0, 1.0)
	_fill(Rect2(inner.position, Vector2(inner.size.x * progress, inner.size.y)), _gradient("health_%d" % HudStyle.displayed_team(e.team, _own_team)))


func _draw_progress(rect: Rect2, _e: SimEntity, bar: Dictionary, current: int, cap: int) -> void:
	var inner := _frame(rect)
	var progress := clampf(float(current) / maxf(1.0, float(cap)), 0.0, 1.0)
	_fill(Rect2(inner.position, Vector2(inner.size.x * progress, inner.size.y)), _gradient(bar["resource"]))


## TResourceDisplayIntegerProgressBarComponent.RecomputeChunk: the bar is split into `cap` chunks with 1 px
## black outlines, the width remainder goes to the last chunks.
func _draw_chunks(rect: Rect2, _e: SimEntity, bar: Dictionary, current: int, cap: int) -> void:
	var inner := _frame(rect)
	var count := maxi(cap, current)
	if count <= 0:
		return
	var parent_w := int(inner.size.x) - 1
	var width := parent_w / count
	var overhang := parent_w - width * count
	var gradient := _gradient(bar["resource"])
	var x := inner.position.x
	for i in count:
		var w := width + (1 if i >= count - overhang else 0)
		if i < current:
			var chunk := Rect2(x, inner.position.y, w, inner.size.y)
			_fill(chunk, gradient)
			draw_rect(chunk, Color.BLACK, false, 1.0)
		x += w
