class_name Hud
extends Control
## In-game HUD (docs/hud.md): owns the panels, lays them out in the 1920x1080 design space and
## refreshes them from the simulation every frame. Input on the panels never reaches the world.

signal slot_clicked(slot_index: int)
signal spawner_jump

const TECH_W := 158.0
const TECH_H := 34.0

var info_bar: GameInfoBar
var resources: ResourcePanel
var deck: DeckPanel
var minimap: Minimap
var info: InfoPanel

var _sim: Simulation
var _own_team: int
var _fps: Label
var _ping: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
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
	deck = DeckPanel.new()
	deck.slot_clicked.connect(func(i): slot_clicked.emit(i))
	deck.spawner_jump.connect(func(): spawner_jump.emit())
	add_child(deck)
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
	info.setup(own_team)


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
	info.refresh(_sim)
	_fps.text = "%d FPS" % Engine.get_frames_per_second()
