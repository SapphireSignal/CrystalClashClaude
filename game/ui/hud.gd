class_name Hud
extends Control
## In-game HUD (docs/hud.md): owns the panels, lays them out in the 1920x1080 design space and
## refreshes them from the simulation every frame. Input on the panels never reaches the world.

signal slot_clicked(slot_index: int)
signal spawner_jump
signal match_left      # the final screen's Continue button (or its timeout)

const TECH_W := 158.0
const TECH_H := 34.0
const SMALL_LAYOUT_MAX := Vector2i(1710, 816)   # docs/hud.md: below this window size the client uses `.small`

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
	add_child(info_bar)
	resources = ResourcePanel.new()
	add_child(resources)
	minimap = Minimap.new()
	add_child(minimap)
	info = InfoPanel.new()
	add_child(info)
	card_hint = CardHint.new()   # .card-hint: top edge 260 px above the bottom, centred
	add_child(card_hint)
	deck = DeckPanel.new()
	deck.slot_clicked.connect(func(i): slot_clicked.emit(i))
	deck.slot_hovered.connect(func(i): card_hint.show_slot(_sim.commanders[_own_team].slots[i], _sim.commanders[_own_team], _sim.time_ms))
	deck.slot_unhovered.connect(func(_i): card_hint.hide_card())
	deck.spawner_jump.connect(func(): spawner_jump.emit())
	add_child(deck)
	announcements = Announcements.new()
	add_child(announcements)
	get_viewport().size_changed.connect(_layout)
	_layout()
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
	deck.set_small(_is_small())   # before build(): the deck's own small-layout sizes
	deck.build(sim.commanders[own_team])
	_layout()
	minimap.setup(sim, own_team, camera)
	unit_bars.setup(sim, own_team, camera)
	info.setup(own_team)
	sim.game_event.connect(_on_game_event)
	sim.team_lost.connect(func(team): final_screen.game_over(team, _own_team))
	sim.game_tick.connect(_on_game_tick)


## Panels are designed at 1920x1080 (docs/hud.md) and pinned to the window's edges / centre, so any window
## size and aspect shows the same layout (the original client anchors its .dui panels the same way).
func _is_small() -> bool:
	var window := DisplayServer.window_get_size()
	return window.x < SMALL_LAYOUT_MAX.x or window.y < SMALL_LAYOUT_MAX.y


func _layout() -> void:
	var view := get_viewport_rect().size   # the canvas (1920 wide, height by the window's aspect); size is 0 under a CanvasLayer
	var w := view.x
	var h := view.y
	# core_game_scaling.scss `.core-game.small` (window narrower than 1710 or lower than 816 px): resources,
	# minimap, game-info, tooltip at 80 % of their art, deck slots 66x64 instead of 85x90 (panel 64 high),
	# card hint 267 wide with its top 208 px above the bottom.
	var small := _is_small()
	var s := 0.8 if small else 1.0
	var deck_s := 66.0 / DeckPanel.SLOT_W if small else 1.0
	var hint_s := 267.0 / CardHint.WIDTH if small else 1.0
	info_bar.scale = Vector2(s, s)
	resources.scale = Vector2(s, s)
	minimap.scale = Vector2(s, s)
	deck.scale = Vector2(deck_s, deck_s)
	card_hint.scale = Vector2(hint_s, hint_s)
	info_bar.position = Vector2((w - GameInfoBar.WIDTH * s) / 2.0, 0)
	resources.position = Vector2(0, h - ResourcePanel.SIZE * s)
	minimap.position = Vector2(w - Minimap.SIZE * s, h - Minimap.SIZE * s)
	info.position = Vector2(w - InfoPanel.WIDTH, h * 0.4 - InfoPanel.HEIGHT / 2.0)
	card_hint.position = Vector2((w - CardHint.WIDTH * hint_s) / 2.0, h - (208.0 if small else 260.0))
	announcements.position = Vector2((w - Announcements.WIDTH) / 2.0, Announcements.TOP)
	deck.position = Vector2((w - deck.size.x * deck_s) / 2.0, h - (64.0 if small else DeckPanel.HEIGHT))


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
	# 2022 client: 'waiting' while players load (nothing to wait for in the sandbox), nothing during the warm-up,
	# 'stage_1' at the first game tick (TClientGUIComponent.OnClientInit / OnGameTick).
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
