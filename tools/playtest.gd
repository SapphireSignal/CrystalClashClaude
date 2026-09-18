extends SceneTree
## Autopilot playtest: plays the sandbox like a player for N seconds (default 180) - arms and plays cards
## at sensible targets, keeps the camera on the front line, and saves a screenshot every `shot` seconds
## plus one at every first-time event (first projectile, first death, first spell).
##
##   godot --path <proj> -s tools/playtest.gd --log-file <proj>/.tmp/godot.log -- [seconds] [shot=15]
##
## Output: .tmp/play_<t>.png + a final summary line with entity/projectile counts and script error count.

var _main: Node
var _elapsed := 0.0
var _duration := 180.0
var _shot_every := 15.0
var _next_shot := 10.0
var _next_play := 12.0
var _events := {}   # first-time event name -> true once shot


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("shot="):
			_shot_every = float(arg.trim_prefix("shot="))
		elif arg.is_valid_float():
			_duration = float(arg)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_position(DisplayServer.screen_get_position(DisplayServer.SCREEN_PRIMARY))
	DisplayServer.window_set_size(DisplayServer.screen_get_size(DisplayServer.SCREEN_PRIMARY))
	_main = load("res://game/main.tscn").instantiate()
	root.add_child(_main)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.tmp"))
	_boot()


func _boot() -> void:
	while _main.sim == null:   # main._ready builds the sim on its first frame
		await process_frame
	_main.sim.projectile_spawned.connect(func(_p): _event("first_projectile"))
	_main.sim.entity_died.connect(func(_e): _event("first_death"))
	await _run()


func _run() -> void:
	while _elapsed < _duration:
		await process_frame
		var dt := root.get_process_delta_time()
		_elapsed += dt
		if _main.sim == null or _main.sim.finished:
			break
		_follow_front()
		if _elapsed >= _next_play:
			_next_play = _elapsed + 8.0
			_play_something()
		if _elapsed >= _next_shot:
			_next_shot = _elapsed + _shot_every
			await _shot("play_%d" % int(_elapsed))
	await _shot("play_end")
	var alive: int = _main.sim.alive_entities(-1).size()
	print("PLAYTEST DONE t=%.0f alive=%d projectiles=%d" % [_elapsed, alive, _main.sim.projectiles.size()])
	quit(0)


## Camera follows the mean position of the human team's units nearest the enemy (the front line).
func _follow_front() -> void:
	var best: Vector2
	var found := false
	var enemy_nexus: Vector2 = _main.sim.entities[_main.sim.nexus_ids[_main.AI_TEAM]].position
	var best_d := INF
	for e in _main.sim.alive_entities(_main.HUMAN_TEAM):
		if e.is_spawner() or e.is_building() or e.is_lane_node() or not e.is_targetable():
			continue
		var d: float = e.position.distance_to(enemy_nexus)
		if d < best_d:
			best_d = d
			best = e.position
			found = true
	if found:
		var current: Vector2 = _main._look_at
		_main._place_camera(current.lerp(best, 0.08))


## Arm a random affordable slot and play it at a sensible target (own drop zone for drops, a free grid
## field for spawners, own units for ally spells, the front for enemy spells).
func _play_something() -> void:
	var c = _main.sim.commanders[_main.HUMAN_TEAM]
	var order := range(c.slots.size())
	order.shuffle()
	for slot in order:
		var s = c.slots[slot]
		if s == null or s.card == null:
			continue
		var nexus: Vector2 = _main.sim.entities[_main.sim.nexus_ids[_main.HUMAN_TEAM]].position
		var target := nexus + Vector2(-8 if nexus.x > 0 else 8, 0)
		if s.card.is_spell():
			var own = _main.sim.alive_entities(_main.HUMAN_TEAM).filter(func(e): return e.is_targetable() and not e.is_building() and not e.is_spawner())
			if own.is_empty():
				continue
			target = own[0].position
			if s.card.target_type == "ctEntity":
				if _main._play(_main.HUMAN_TEAM, slot, target) == Simulation.PlayResult.OK:
					_event("first_spell")
					return
				continue
		if _main._play(_main.HUMAN_TEAM, slot, target) == Simulation.PlayResult.OK:
			if s.card.is_spell():
				_event("first_spell")
			return


func _event(name: String) -> void:
	if _events.has(name):
		return
	_events[name] = true
	_shot(name)


func _shot(name: String) -> void:
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://.tmp/%s.png" % name)
	print("shot ", name, " at %.0f s" % _elapsed)
