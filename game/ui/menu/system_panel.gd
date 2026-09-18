class_name SystemPanel
extends Control
## The window buttons of the menu client (MainMenu/SystemPanel/SystemPanel.dui, menu.scss `.system-panel`):
## minimize, settings, close, top-right of the screen. Included at the top of MainMenu.dui, so it is visible for
## the whole MainMenu state, the loading page included.
##
## `.system-panel`: Position -4 4 anchored top-right, Size auto 16, horizontal stack; each button `100ch 100%`
## (`ch` = % of the container height, so 16x16) with Margin-Left 5.

signal settings_requested
signal exit_requested

const HEIGHT := 16.0
const MARGIN_LEFT := 5.0
const OFFSET := Vector2(-4, 4)

var _buttons: Array[TextureRect] = []


func _ready() -> void:
	# no anchors: _layout sizes this control from the menu canvas (anchors + size would warn)
	mouse_filter = MOUSE_FILTER_IGNORE
	var entries := [
		["Minimize", func(): DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)],   # client.Minimize
		["Options", func(): settings_requested.emit()],                                              # OpenDialog(diSettings)
		["Close", func(): exit_requested.emit()],                                                    # client.Close
	]
	for e in entries:
		var art: String = e[0]
		var button := HudStyle.picture(HudStyle.tex("MainMenu/SystemPanel/%s.tga" % art), Rect2(0, 0, HEIGHT, HEIGHT))
		button.mouse_filter = MOUSE_FILTER_STOP
		button.mouse_entered.connect(func(): button.texture = HudStyle.tex("MainMenu/SystemPanel/%s_Hover.tga" % art))
		button.mouse_exited.connect(func(): button.texture = HudStyle.tex("MainMenu/SystemPanel/%s.tga" % art))
		button.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				accept_event()
				e[1].call())
		add_child(button)
		_buttons.append(button)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var view := MenuLayout.layout_size(self)
	size = view
	var x := view.x + OFFSET.x
	for i in range(_buttons.size() - 1, -1, -1):   # laid out from the right edge inwards
		x -= HEIGHT
		HudStyle.place(_buttons[i], Rect2(x, OFFSET.y, HEIGHT, HEIGHT))
		x -= MARGIN_LEFT
