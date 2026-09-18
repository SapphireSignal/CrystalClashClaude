extends Node
## Client state machine (TGameStateManager, BaseConflict.Classes.Gamestates.pas:268-382; state ids
## BaseConflict.Constants.Client.pas:51-58). Each state owns its scene subtree; ChangeGameState frees the old
## state's nodes (LeaveState) and builds the new one (EnterState). docs/lobby.md section 1 has the flow.
##
## Built so far: MainMenu (the menu's loading page over the animated background while preloading, then the
## MainMenu shell with navbar, dashboard and the Play screen), LoadGame (the in-match LoadingScreen for the
## original's minimum loading time) and Game (the sandbox in game/main.tscn).

const GAMESTATE_INGAME := "Game"
const GAMESTATE_LOADGAMESTATE := "LoadGame"
const GAMESTATE_MAINMENU := "MainMenu"
const MAIN_SCENE := "res://game/main.tscn"

var _state := ""
var _state_root: Node = null   # everything the current state created
var _loading_screen: MenuLoadingScreen = null
var _menu_layer: CanvasLayer = null
var _is_preloading := false     # TGameStateMainMenu.IsPreLoading
var _preloaded: PackedScene = null
var _match_loading: LoadingScreen = null
var _first_loading := true      # TGameStateLoadCoreGame.FirstLoading: cleared when the first match was loaded
var _scenario := "es1v1"        # the Play screen's choice, RGameFoundData.scenario_uid stand-in
var _menu_settings: SettingsMenu = null   # diSettings opened from the SystemPanel
var _exit_dialog: ExitDialog = null       # client.Close -> ExitDialogVisible
var _system_panel: SystemPanel = null     # kept in front of the shell (its ZOffset 20000)
var _menu_resize: Callable = Callable()   # MenuLayout re-apply on window resize, disconnected with the menu


func _ready() -> void:
	ClientSettings.apply_startup()   # vsync and the master mixer from user://Settings.ini
	change_game_state(GAMESTATE_MAINMENU)


func _process(_delta: float) -> void:
	if _state == GAMESTATE_MAINMENU and _is_preloading:
		# Synchronous load one frame after the loading page appeared: the scene is one script, its heavy assets
		# load in-game. (A threaded load raced the menu's own use of the shared UI classes and failed to parse.)
		_preloaded = load(MAIN_SCENE)
		if _preloaded == null:
			push_error("preload of %s failed" % MAIN_SCENE)
		_is_preloading = false
		_loading_screen.visible = false
		var menu := MainMenu.new()   # client.IsApiReady and not IsPreloading: the shell appears
		menu.play_requested.connect(func(scenario: String):
			_scenario = scenario
			change_game_state(GAMESTATE_LOADGAMESTATE))
		_menu_layer.add_child(menu)
		_menu_layer.move_child(_system_panel, -1)   # .system-panel ZOffset 20000: above the navbar overlay
	elif _state == GAMESTATE_LOADGAMESTATE and _match_loading.done:
		change_game_state(GAMESTATE_INGAME)   # EnterCore


func change_game_state(id: String) -> void:
	if _state_root != null:   # LeaveState
		if _menu_resize.is_valid():
			get_viewport().size_changed.disconnect(_menu_resize)
			_menu_resize = Callable()
		if _state == GAMESTATE_LOADGAMESTATE:
			_first_loading = false
		if id == GAMESTATE_INGAME:
			# The loading screen stays on top until the match has drawn its first frames (the map's shaders compile
			# on first use), so no grey clear-colour frames show between the two states.
			var old_root := _state_root
			_free_after_frames(old_root, 3)
		else:
			_state_root.queue_free()
		_state_root = null
		_loading_screen = null
		_menu_layer = null
		_match_loading = null
		_menu_settings = null
		_exit_dialog = null
		_system_panel = null
	_state = id
	# The original runs the menu in its own client window and the match in the game window, which is fullscreen by
	# default (coEngineDisplayMode = dmBorderlessFullscreenWindow): the window changes with the state.
	ClientSettings.apply(id != GAMESTATE_MAINMENU)
	_state_root = Node.new()
	_state_root.name = id
	add_child(_state_root)
	match id:   # EnterState
		GAMESTATE_MAINMENU:
			var layer := CanvasLayer.new()
			_state_root.add_child(layer)
			_menu_layer = layer
			# GUI.VirtualSize = 1280x720 for the menu client: the canvas scales with the window (MenuLayout)
			MenuLayout.apply(layer)
			_menu_resize = func(): MenuLayout.apply(layer)
			get_viewport().size_changed.connect(_menu_resize)
			layer.add_child(MenuBackground.new())   # TGameStateMenu.EnterState (coMenuAnimatedBackground)
			# MainMenu.dui includes the SystemPanel above everything, so it is there during the loading page too
			_system_panel = SystemPanel.new()
			_system_panel.settings_requested.connect(_open_menu_settings)
			_system_panel.exit_requested.connect(_open_exit_dialog)
			layer.add_child(_system_panel)
			_loading_screen = MenuLoadingScreen.new()
			_loading_screen.logo_clicked.connect(func(url: String): OS.shell_open(url))
			layer.add_child(_loading_screen)
			_is_preloading = true
		GAMESTATE_LOADGAMESTATE:
			# TGameStateLoadCoreGame: the loading screen with the match's players; without a master server the
			# game data is the local player on their team with the sandbox deck (the AI is not a player)
			var layer := CanvasLayer.new()
			_state_root.add_child(layer)
			layer.layer = 10   # above the match while it starts (see change_game_state)
			_match_loading = LoadingScreen.new()
			_match_loading.players = [{
				"username": MainMenu.PROFILE["name"], "team_id": load("res://game/main.gd").HUMAN_TEAM,
				"deckname": Lang.t("scenario_sandbox"), "deck_icon": "",
			}]
			_match_loading.first_loading = _first_loading
			_match_loading.tutorial = _scenario == "esTutorial"
			layer.add_child(_match_loading)
		GAMESTATE_INGAME:
			var scene: PackedScene = _preloaded if _preloaded != null else load(MAIN_SCENE)
			var game := scene.instantiate()
			# TGameStateCoreGame.EnterMainMenu: leaving the match re-enters MainMenu, which preloads again (its
			# loading page, quick from the cache) and lands on the dashboard (mtStart; the rewards/statistics
			# screen of a server match is not built). Deferred: the game frees itself from inside its own signal.
			game.match_left.connect(func(): change_game_state.call_deferred(GAMESTATE_MAINMENU))
			_state_root.add_child(game)


## SystemPanel's options button: OnDialogOpen outside a match starts on the Menu category (`IsClientWindow`).
func _open_menu_settings() -> void:
	if _menu_settings != null or _menu_layer == null:
		return
	_menu_settings = SettingsMenu.new()
	_menu_settings.in_game = false
	_menu_settings.closed.connect(func(): _menu_settings = null)
	_menu_layer.add_child(_menu_settings)
	_menu_layer.move_child(_menu_settings, -1)


## SystemPanel's close button: TGameStateManager.Close -> CanProgramClose shows the exit dialog.
func _open_exit_dialog() -> void:
	if _exit_dialog != null or _menu_layer == null:
		return
	_exit_dialog = ExitDialog.new()
	_exit_dialog.closed.connect(func(): _exit_dialog = null)
	_menu_layer.add_child(_exit_dialog)
	_menu_layer.move_child(_exit_dialog, -1)


func _free_after_frames(node: Node, frames: int) -> void:
	for i in frames:
		await RenderingServer.frame_post_draw
	if is_instance_valid(node):
		node.queue_free()
