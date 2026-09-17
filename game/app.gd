extends Node
## Client state machine (TGameStateManager, BaseConflict.Classes.Gamestates.pas:268-382; state ids
## BaseConflict.Constants.Client.pas:51-58). Each state owns its scene subtree; ChangeGameState frees the old
## state's nodes (LeaveState) and builds the new one (EnterState). docs/lobby.md section 1 has the flow.
##
## Built so far: MainMenu (the menu's loading page over the animated background while preloading) and
## Game (the sandbox in game/main.tscn). The dashboard, teambuilding and the in-match LoadingScreen follow;
## until then MainMenu jumps into the sandbox as soon as the preload finishes.

const GAMESTATE_INGAME := "Game"
const GAMESTATE_LOADGAMESTATE := "LoadGame"
const GAMESTATE_MAINMENU := "MainMenu"
const MAIN_SCENE := "res://game/main.tscn"

var _state := ""
var _state_root: Node = null   # everything the current state created
var _loading_screen: MenuLoadingScreen = null
var _is_preloading := false     # TGameStateMainMenu.IsPreLoading


func _ready() -> void:
	change_game_state(GAMESTATE_MAINMENU)


func _process(_delta: float) -> void:
	if _state == GAMESTATE_MAINMENU and _is_preloading:
		var status := ResourceLoader.load_threaded_get_status(MAIN_SCENE)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_is_preloading = false
			_loading_screen.visible = false
			change_game_state(GAMESTATE_LOADGAMESTATE)   # no dashboard yet: play at once
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error("preload of %s failed" % MAIN_SCENE)
			_is_preloading = false


func change_game_state(id: String) -> void:
	if _state_root != null:   # LeaveState
		_state_root.queue_free()
		_state_root = null
		_loading_screen = null
	_state = id
	_state_root = Node.new()
	_state_root.name = id
	add_child(_state_root)
	match id:   # EnterState
		GAMESTATE_MAINMENU:
			var layer := CanvasLayer.new()
			_state_root.add_child(layer)
			layer.add_child(MenuBackground.new())   # TGameStateMenu.EnterState (coMenuAnimatedBackground)
			_loading_screen = MenuLoadingScreen.new()
			_loading_screen.logo_clicked.connect(func(url: String): OS.shell_open(url))
			layer.add_child(_loading_screen)
			_is_preloading = true
			ResourceLoader.load_threaded_request(MAIN_SCENE)
		GAMESTATE_LOADGAMESTATE:
			# TGameStateLoadCoreGame: assets loaded and the game socket connected -> Game
			change_game_state(GAMESTATE_INGAME)
		GAMESTATE_INGAME:
			var scene: PackedScene = ResourceLoader.load_threaded_get(MAIN_SCENE) if ResourceLoader.load_threaded_get_status(MAIN_SCENE) == ResourceLoader.THREAD_LOAD_LOADED else load(MAIN_SCENE)
			_state_root.add_child(scene.instantiate())
