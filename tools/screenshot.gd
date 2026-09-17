extends SceneTree
## Runs game/main.tscn for a while and saves screenshots of the HUD for comparison with
## reference/rolmedia/ingame. Usage (windowed, not headless):
##   godot --path <proj> -s tools/screenshot.gd --log-file <proj>/.tmp/godot.log -- <seconds> [<seconds> ...] [select] [hover=<slot>] [finish] [zoom=nexus|unit|node] [at=node] [screen=X,Y] [size=WxH, default 1679x1079] [play=<slot>]
## Writes .tmp/shot_<seconds>.png for each requested time; "select" selects a unit (or the blue nexus), "hover=N" shows deck slot N's card hint.

var _targets: Array = []
var _elapsed := 0.0
var _main: Node
var _select := false
var _hover := -1
var _finish := false
var _zoom := ""
var _at := ""
var _screen := Vector2(-1, -1)   # screen=X,Y: put the at= target on this pixel (matches a reference shot's framing)
var size := "1679x1079"   # the owner's live-client window (small HUD layout); comparisons must use it      # at=node: look at the first lane node at the default zoom
var _play := -1


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.is_valid_float():
			_targets.append(float(arg))
		elif arg == "select":
			_select = true
		elif arg.begins_with("hover="):
			_hover = int(arg.trim_prefix("hover="))
		elif arg == "finish":
			_finish = true
		elif arg.begins_with("zoom="):
			_zoom = arg.trim_prefix("zoom=")
		elif arg.begins_with("play="):
			_play = int(arg.trim_prefix("play="))
		elif arg.begins_with("at="):
			_at = arg.trim_prefix("at=")
		elif arg.begins_with("screen="):
			var xy := arg.trim_prefix("screen=").split(",")
			_screen = Vector2(float(xy[0]), float(xy[1]))
		elif arg.begins_with("size="):   # size=WxH overrides the default reference window size
			size = arg.trim_prefix("size=")
	var parts := size.split("x")
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)   # else the taskbar clamps the height
	DisplayServer.window_set_position(Vector2i.ZERO)
	DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))
	if _targets.is_empty():
		_targets = [3.0]
	_targets.sort()
	_main = load("res://game/main.tscn").instantiate()
	root.add_child(_main)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.tmp"))


func _process(delta: float) -> bool:
	_elapsed += delta
	if not _targets.is_empty() and _elapsed >= _targets[0]:
		var seconds: float = _targets.pop_front()
		if _select:
			var units: Array = _main.sim.alive_entities().filter(func(e): return e.has("upUnit"))
			var pick: SimEntity = units[0] if not units.is_empty() else _main.sim.entities[_main.sim.nexus_ids[_main.HUMAN_TEAM]]
			_main._hud.select(pick)
		if _hover >= 0:   # hover at the first shot only: later shots show the delayed ability box
			var c: Commander = _main.sim.commanders[_main.HUMAN_TEAM]
			_main._hud.card_hint.show_slot(c.slots[_hover], c, _main.sim.time_ms)
			_hover = -1
		if _zoom != "":   # zoom=nexus | unit | node: close camera on the blue nexus, the first unit or lane node
			var target: SimEntity = _main.sim.entities[_main.sim.nexus_ids[_main.HUMAN_TEAM]]
			if _zoom == "unit" or _zoom == "node":
				var units: Array = _main.sim.alive_entities(-1).filter(func(e): return e.is_lane_node() if _zoom == "node" else e.has("upUnit"))
				if not units.is_empty():
					target = units[0]
			_main._zoom = 2.6   # close-up for detail checks only: the game itself never zooms
			_main._place_camera(target.position)
		if _at == "node":
			var nodes: Array = _main.sim.alive_entities(-1).filter(func(e): return e.is_lane_node())
			if not nodes.is_empty():
				_main._place_camera(nodes[0].position)
				if _screen.x >= 0:   # shift the look-at so the node projects onto the requested pixel
					var centre := Vector2(root.get_viewport().size) / 2.0
					_main._place_camera(nodes[0].position + (_main._ground_at(centre) - _main._ground_at(_screen)))
		if _play >= 0:   # play=N: the blue deck slot N at the camera's look-at point (free cards not needed: 300 gold)
			_main.sim.commanders[_main.HUMAN_TEAM].free_cards = true
			_main._play(_main.HUMAN_TEAM, _play, _main._look_at + Vector2(6, 0))
			_play = -1
		if _finish:   # kill the red nexus at the first shot: later shots show the victory screen
			_main.sim._kill(_main.sim.entities[_main.sim.nexus_ids[_main.AI_TEAM]])
			_finish = false
		var path := "res://.tmp/shot_%d.png" % int(seconds)
		var err := root.get_viewport().get_texture().get_image().save_png(path)
		print("screenshot %s: %s" % [path, error_string(err)])
	return _targets.is_empty()
