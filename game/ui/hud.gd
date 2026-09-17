class_name Hud
extends Control
## In-game HUD (docs/hud.md): owns the panels, lays them out in the 1920x1080 design space and
## refreshes them from the simulation every frame. Input on the panels never reaches the world.

signal slot_clicked(slot_index: int)
signal spawner_jump
signal match_left      # the final screen's Continue button (or its timeout)

const TECH_W := 158.0
const TECH_H := 34.0

var info_bar: GameInfoBar
var resources: ResourcePanel
var deck: DeckPanel
var minimap: Minimap
var info: InfoPanel
var card_hint: CardHint
var announcements: Announcements
var unit_bars: UnitBars
var final_screen: FinalScreen

var _sim: Simulation
var _own_team: int
var _fps: Label
var _ping: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	unit_bars = UnitBars.new()   # HEALTHBARWRAPPER: behind every panel
	add_child(unit_bars)
	info_bar = GameInfoBar.new()
	info_bar.position = Vector2((1920 - GameInfoBar.WIDTH) / 2.0, 0)
	add_child(info_bar)
	resources = ResourcePanel.new()
	resources.position = Vector2(0, 1080 - ResourcePanel.SIZE)
	add_child(resources)
	minimap = Minimap.new()
	minimap.position = Vector2(1920 - Minimap.SIZE, 1080 - Minimap.SIZE)
	add_child(minimap)
	info = InfoPanel.new()
	info.position = Vector2(1920 - InfoPanel.WIDTH, 1080 * 0.4 - InfoPanel.HEIGHT / 2.0)
	add_child(info)
	card_hint = CardHint.new()   # .card-hint: top edge 260 px above the bottom, centred
	card_hint.position = Vector2((1920 - CardHint.WIDTH) / 2.0, 1080 - 260)
	add_child(card_hint)
	deck = DeckPanel.new()
	deck.slot_clicked.connect(func(i): slot_clicked.emit(i))
	deck.slot_hovered.connect(func(i): card_hint.show_slot(_sim.commanders[_own_team].slots[i], _sim.commanders[_own_team], _sim.time_ms))
	deck.slot_unhovered.connect(func(_i): card_hint.hide_card())
	deck.spawner_jump.connect(func(): spawner_jump.emit())
	add_child(deck)
	announcements = Announcements.new()
	announcements.position = Vector2((1920 - Announcements.WIDTH) / 2.0, Announcements.TOP)
	add_child(announcements)
	final_screen = FinalScreen.new()
	final_screen.continue_pressed.connect(func(): match_left.emit())
	add_child(final_screen)
	# TechnicalPanel: fps, ping icon, latency
	var tech := Control.new()
	tech.mouse_filter = MOUSE_FILTER_IGNORE
	HudStyle.place(tech, Rect2(4, 2, TECH_W, TECH_H))
	add_child(tech)
	_fps = HudStyle.label("60 FPS", 13, HudStyle.BLACK, HudStyle.FONT_SEMIBOLD, HORIZONTAL_ALIGNMENT_LEFT)
	HudStyle.place(_fps, Rect2(0, 0, 62, TECH_H))
	tech.add_child(_fps)
	tech.add_child(HudStyle.picture(HudStyle.tex("HUD/TechnicalPanel/PingSymbolGood.png"), Rect2(62, (TECH_H - 14) / 2.0, 14, 14)))
	_ping = HudStyle.label("0 ms", 13, HudStyle.BLACK, HudStyle.FONT_SEMIBOLD, HORIZONTAL_ALIGNMENT_LEFT)
	HudStyle.place(_ping, Rect2(78, 0, 80, TECH_H))
	tech.add_child(_ping)


func setup(sim: Simulation, own_team: int, camera: Camera3D) -> void:
	_sim = sim
	_own_team = own_team
	deck.build(sim.commanders[own_team])
	deck.position = Vector2((1920 - deck.size.x) / 2.0, 1080 - DeckPanel.HEIGHT)
	minimap.setup(sim, own_team, camera)
	unit_bars.setup(sim, own_team, camera)
	info.setup(own_team)
	sim.game_event.connect(_on_game_event)
	sim.team_lost.connect(func(team): final_screen.game_over(team, _own_team))
	sim.game_tick.connect(_on_game_tick)


func select(e: SimEntity) -> void:
	info.select(e, _sim)


func selected() -> SimEntity:
	return info.selected()


func refresh() -> void:
	if _sim == null:
		return
	info_bar.refresh(_sim, _own_team)
	resources.refresh(_sim, _own_team)
	deck.refresh(_sim, _sim.commanders[_own_team])
	minimap.refresh()
	unit_bars.refresh()
	info.refresh(_sim)
	card_hint.refresh(_sim.time_ms)
	if not _sim.game_started:   # live client: countdown to the first game tick
		var seconds := ceili((_sim.next_game_tick_at - _sim.time_ms) / 1000.0)
		announcements.show_text(str(maxi(seconds, 1)), Lang.t("core_game_countdown"), _sim.time_ms)
	announcements.refresh(_sim.time_ms)
	final_screen.refresh()
	_fps.text = "%d FPS" % Engine.get_frames_per_second()


## TClientGUIComponent.OnGameEvent: stage 2 / 3 (stage 3 only above league 2) and the showdown, 2 s each.
func _on_game_event(name: String) -> void:
	match name:
		"tech_level_2": announcements.show_announcement("stage_2", _sim.time_ms, 2000)
		"tech_level_3":
			if _sim.league > 2:
				announcements.show_announcement("stage_3", _sim.time_ms, 2000)
		"showdown": announcements.show_announcement("showdown", _sim.time_ms, 2000)


## OnGameTick: the first game tick announces stage 1.
func _on_game_tick(counter: int) -> void:
	if counter == 1:
		announcements.show_announcement("stage_1", _sim.time_ms, 2000)
