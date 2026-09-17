class_name Minimap
extends Control
## Bottom right minimap (docs/hud.md "Minimap"): TMiniMap.WorldToMiniMap projection, entity icons
## tinted with the displayed team colour, the camera's ground quad and the menu button.

signal menu_pressed

const SIZE := 302.0
const CONTENT := 281.0
const INFLATE := -38.0
const CAMERAOFFSET_XZ := Vector2(-0.394721269607544, -0.429695725440979)   # Constants.Client.pas CAMERAOFFSET: the map image is drawn for this angle (the live camera yaw in main.gd would put the icons 8 deg off the painted lane)

var _sim: Simulation
var _own_team: int = 1
var _camera: Camera3D
var _content: Control
var _overlay: Control
var _gui_rect: Rect2      # projection target rect in content space
var _world_rect: Rect2
var _angle: float
var _icons: Dictionary = {}


func _ready() -> void:
	size = Vector2(SIZE, SIZE)
	mouse_filter = MOUSE_FILTER_STOP
	add_child(HudStyle.blur(Rect2(SIZE - CONTENT, SIZE - CONTENT, CONTENT, CONTENT)))   # .content Blur : True
	add_child(HudStyle.picture(HudStyle.tex("HUD/MinimapPanel/map_panel.png"), Rect2(0, 0, SIZE, SIZE)))
	_content = Control.new()
	_content.clip_contents = true
	_content.mouse_filter = MOUSE_FILTER_IGNORE
	HudStyle.place(_content, Rect2(SIZE - CONTENT, SIZE - CONTENT, CONTENT, CONTENT))
	add_child(_content)
	_overlay = Control.new()   # icons and the camera quad, drawn above the map image
	_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	HudStyle.place(_overlay, Rect2(0, 0, CONTENT, CONTENT))
	_overlay.draw.connect(_draw_map)
	var btn := TextureButton.new()
	btn.texture_normal = HudStyle.tex("HUD/MinimapPanel/menu_button.png")
	btn.texture_hover = HudStyle.tex("HUD/MinimapPanel/menu_button_hover.png")
	btn.texture_pressed = HudStyle.tex("HUD/MinimapPanel/menu_button_down.png")
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_SCALE
	var bw := SIZE * 0.17
	var bh := bw * 58.0 / 62.0
	HudStyle.place(btn, Rect2(SIZE - SIZE * 0.105 - bw / 2.0, SIZE - SIZE * 0.098 - bh / 2.0, bw, bh))
	btn.pressed.connect(func(): menu_pressed.emit())
	add_child(btn)
	_angle = Vector2(0, 1).angle_to(CAMERAOFFSET_XZ) - PI / 37.25
	_gui_rect = Rect2(0, 0, CONTENT, CONTENT).grow(INFLATE)
	_gui_rect.position += Vector2(3, -1)
	for name in ["MinimapUnitIcon", "MinimapBuildingIcon", "MinimapCharmIcon", "MinimapBossIcon",
			"minimap_icon_nexus_1", "minimap_icon_nexus_2",
			"minimap_icon_tower_0", "minimap_icon_tower_1", "minimap_icon_tower_2"]:
		_icons[name] = HudStyle.tex("HUD/MinimapPanel/%s.png" % name)


func setup(sim: Simulation, own_team: int, camera: Camera3D) -> void:
	_sim = sim
	_own_team = own_team
	_camera = camera
	_world_rect = sim.map.bounds
	var map_tex := "map_minimap_single" if sim.map.is_single() else "map_minimap"
	_content.add_child(HudStyle.picture(HudStyle.tex("HUD/MinimapPanel/%s.png" % map_tex), Rect2(0, 0, CONTENT, CONTENT)))
	_content.add_child(_overlay)


func refresh() -> void:
	_overlay.queue_redraw()


## TMiniMap.WorldToMiniMap: centre, rotate, mirror along x = y, scale 1.8, back to the centre, clamp.
func world_to_minimap(world: Vector2, clamp_to_rect: bool = true) -> Vector2:
	var rel := (world - _world_rect.get_center()) / _world_rect.size
	rel = rel.rotated(_angle)
	rel = Vector2(rel.y, rel.x) * 1.8
	var p := _gui_rect.get_center() + rel * _gui_rect.size
	if clamp_to_rect:
		p = p.clamp(_gui_rect.position, _gui_rect.end)
	return p


static func icon_size(unit_size: float) -> float:
	return 2.0 * (4.0 + unit_size * 1.8)


func _draw_map() -> void:
	if _sim == null:
		return
	var items := []   # [size, texture, position, tint]
	for e in _sim.alive_entities():
		if e.is_spawner() or e.think_once_waits:
			continue
		var team := HudStyle.displayed_team(e.team, _own_team)
		if e.has("upNexus"):
			items.append([5.0, _icons["minimap_icon_nexus_%d" % maxi(team, 1)], e.position, Color.WHITE])
		elif e.has("upLanetower") or e.is_lane_node():
			items.append([2.5, _icons["minimap_icon_tower_%d" % team], e.position, Color.WHITE])
		elif e.has("upCharm"):
			items.append([e.collision_radius * 0.25, _icons["MinimapCharmIcon"], e.position, HudStyle.TEAM_COLORS[team]])
		elif e.has("upBoss"):
			items.append([3.0, _icons["MinimapBossIcon"], e.position, HudStyle.TEAM_COLORS[team]])
		elif e.is_building():
			items.append([e.collision_radius, _icons["MinimapBuildingIcon"], e.position, HudStyle.TEAM_COLORS[team]])
		elif e.has("upUnit"):
			items.append([e.collision_radius, _icons["MinimapUnitIcon"], e.position, HudStyle.TEAM_COLORS[team]])
	items.sort_custom(func(a, b): return a[0] > b[0])   # bigger icons behind
	for it in items:
		var px := icon_size(it[0])
		var p: Vector2 = world_to_minimap(it[2])
		if it[1] != null:
			_overlay.draw_texture_rect(it[1], Rect2(p - Vector2(px, px) / 2.0, Vector2(px, px)), false, it[3])
	_draw_camera_quad()


## IdleViewQuad: the four viewport corners projected onto the ground, drawn as a white outline.
func _draw_camera_quad() -> void:
	if _camera == null:
		return
	var vp := _camera.get_viewport().get_visible_rect().size
	var pts := PackedVector2Array()
	for corner in [Vector2(0, 0), Vector2(vp.x, 0), vp, Vector2(0, vp.y)]:
		var from := _camera.project_ray_origin(corner)
		var dir := _camera.project_ray_normal(corner)
		if absf(dir.y) < 0.0001:
			return
		var t := -from.y / dir.y
		if t < 0.0:
			return
		var hit := from + dir * t
		pts.append(world_to_minimap(Vector2(hit.x, hit.z), false))
	pts.append(pts[0])
	_overlay.draw_polyline(pts, Color(1, 1, 1, 0.9), 1.0)
