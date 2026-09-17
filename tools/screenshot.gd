extends SceneTree
## Runs game/main.tscn for a while and saves screenshots of the HUD for comparison with
## reference/media/ingame. Usage (windowed, not headless):
##   godot --path <proj> -s tools/screenshot.gd --log-file <proj>/.tmp/godot.log -- <seconds> [<seconds> ...] [select]
## Writes .tmp/shot_<seconds>.png for each requested time; "select" selects a unit (or the blue nexus) first (info panel).

var _targets: Array = []
var _elapsed := 0.0
var _main: Node
var _select := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.is_valid_float():
			_targets.append(float(arg))
		elif arg == "select":
			_select = true
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
			var pick: SimEntity = units[0] if not units.is_empty() else _main.sim.entities[_main.sim.nexus_ids[Simulation.TEAM_BLUE]]
			_main._hud.select(pick)
		var path := "res://.tmp/shot_%d.png" % int(seconds)
		var err := root.get_viewport().get_texture().get_image().save_png(path)
		print("screenshot %s: %s" % [path, error_string(err)])
	return _targets.is_empty()
