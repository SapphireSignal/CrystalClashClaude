extends SceneTree
## Minimal headless test runner. Run:
##   godot --headless --path <project> -s tests/run_tests.gd --log-file <abs path>
## Every tests/test_*.gd script is instantiated and each method starting with "test_" is called.
## Fails loudly (exit code 1) when any assertion fails.

var failures: int = 0
var passed: int = 0


func _initialize() -> void:
	var dir := DirAccess.open("res://tests")
	for file in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd"):
			_run_script("res://tests/" + file)
	print("tests passed: %d  failed: %d" % [passed, failures])
	quit(1 if failures > 0 else 0)


func _run_script(path: String) -> void:
	var script: GDScript = load(path)
	var suite: RefCounted = script.new()
	suite.runner = self
	for m in script.get_script_method_list():
		if m.name.begins_with("test_"):
			suite.call(m.name)
	suite.runner = null


func check(cond: bool, message: String) -> void:
	if cond:
		passed += 1
	else:
		failures += 1
		printerr("FAIL: " + message)


func check_eq(a: Variant, b: Variant, message: String) -> void:
	check(a == b, "%s (got %s, expected %s)" % [message, str(a), str(b)])


func check_near(a: float, b: float, message: String, eps: float = 0.001) -> void:
	check(absf(a - b) <= eps, "%s (got %s, expected %s)" % [message, str(a), str(b)])
