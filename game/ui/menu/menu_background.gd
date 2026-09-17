class_name MenuBackground
extends Control
## The animated menu background (TAnimatedImage, Engine.AnimatedBackground.pas) every full-screen menu state
## draws behind its page (TGameStateMenu, BaseConflict.Classes.Gamestates.pas:7791-7813): four 1280x720 layers
## from Shared/AnimatedBackground/bg.anb, each stretched to the screen times the zoom and shifted by the
## shared offset scaled with (1 - depth), so near layers drift more than far ones (parallax).

## bg.anb: texture, depth. Draw order = MAX_DRAW_ORDER * (1 - depth): the deepest layer is painted first.
const LAYERS := [
	["Shared/AnimatedBackground/background_layer_0.png", 0.9],
	["Shared/AnimatedBackground/background_layer_1.png", 0.66],
	["Shared/AnimatedBackground/background_layer_2.png", 0.23],
	["Shared/AnimatedBackground/background_layer_3.png", 0.001],
]
const ZOOM := 1.15           # TGameStateMenu.Idle: FAnimatedBackground.Zoom := 1.15
const OFFSET_SCALE := 0.08   # ... * 0.08

var _layers: Array = []   # [TextureRect, depth]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	for layer in LAYERS:
		var pic := HudStyle.picture(HudStyle.tex(layer[0]), Rect2())
		add_child(pic)
		_layers.append([pic, layer[1]])


func _process(_delta: float) -> void:
	# TGameStateMenu.Idle, with the engine's floating timestamp in ms.
	var t := Time.get_ticks_msec() / 1.0
	var offset := Vector2(sin(t / 3000.0), (sin(t / 924.0) * 0.3 + 0.7) * cos(t / 3000.0)) * OFFSET_SCALE
	var screen := get_viewport_rect().size
	for l in _layers:
		var pic: TextureRect = l[0]
		var depth: float = l[1]
		# TAnimatedImageLayer.Idle: centre = (0.5 - 0.5) * zoom + 0.5 + offset * (1 - depth), size = zoom (relative screen)
		var centre := (Vector2(0.5, 0.5) + offset * (1.0 - depth)) * screen
		pic.size = screen * ZOOM
		pic.position = centre - pic.size / 2.0
