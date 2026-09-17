class_name IngameMenu
extends Control
## The in-match game menu (HUD/Menu.dui, core_game_dialogs.scss `.core-menu-dialog`): backdrop, 270x330 window with
## the small caption, the button stack Settings / Surrender / Exit to desktop and Back to game at the bottom.
## Opened by Escape or the minimap's menu button (`hud.IsMenuOpen`); a click on the backdrop closes it.

signal settings_requested
signal surrender_requested
signal exit_requested
signal closed

const WINDOW := Vector2(270, 330)
const CONTENT_X := 12.0     # $frame padding 2 + border 2 + window padding 10
const CONTENT_Y := 32.0     # ... + window padding 30
const BUTTON_ASPECT := 155.0 / 58.0

var _window: Control
var _blur: ColorRect
var _tint: ColorRect


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			close())
	_blur = HudStyle.blur(Rect2(), Color.WHITE)   # .backdrop Blur : True, BlurColor $FFFFFFFF; $background-backdrop tint in _draw
	add_child(_blur)
	_tint = HudStyle.rect(SettingsMenu.BACKDROP, Rect2())   # children draw above _draw: the tint is its own node
	add_child(_tint)
	_window = Control.new()
	_window.mouse_filter = MOUSE_FILTER_STOP
	_window.size = WINDOW
	_window.draw.connect(func():
		var r := Rect2(Vector2.ZERO, WINDOW)
		_window.draw_rect(r.grow(3), SettingsMenu.SHADOW)
		_window.draw_rect(r, SettingsMenu.WINDOW_BG)
		_window.draw_rect(r.grow(-1), SettingsMenu.BORDER_CYAN, false, 2.0))
	add_child(_window)
	# .window-caption.small: dialog_header_small.png (232x53) centred on the top edge, 35 px up
	var header := HudStyle.picture(HudStyle.tex("Shared/dialog_header_small.png"), Rect2((WINDOW.x - 232) / 2.0, -35 - 53 / 2.0, 232, 53))
	_window.add_child(header)
	var caption := HudStyle.label(Lang.t("gui_ingame_menu_caption"), 22, HudStyle.WHITE, HudStyle.FONT_BOLD)
	HudStyle.place(caption, Rect2(232 * 0.05, 53 * 0.2, 232 * 0.9, 53 * 0.52))
	HudStyle.fit(caption, 22)
	header.add_child(caption)
	# .buttons: 90 % wide stack at the top of the content; children 90 % wide at 5 %, `auto` high, Margin-Top -10;
	# the last child sits at the stack's bottom (Padding-Bottom 10 on the window).
	var content := Rect2(CONTENT_X, CONTENT_Y, WINDOW.x - 2 * CONTENT_X, WINDOW.y - CONTENT_Y - CONTENT_Y - 10.0)
	var stack_w := content.size.x * 0.9
	var stack_x := content.position.x + (content.size.x - stack_w) / 2.0
	var bw := stack_w * 0.9
	var bh := bw / BUTTON_ASPECT
	var bx := stack_x + stack_w * 0.05
	var y := content.position.y
	var entries := [
		["settings", "", func(): settings_requested.emit()],
		["surrender", "_danger", func(): surrender_requested.emit(); close()],
		["quit", "", func(): exit_requested.emit()],   # client.CloseForcePrompt: always asks
	]
	for e in entries:
		var b := SettingsMenu.XlButton.new(Lang.t(e[0]), e[1])
		_size_button(b, Rect2(bx, y, bw, bh))
		b.pressed.connect(e[2])
		_window.add_child(b)
		y += bh - 10.0
	var back := SettingsMenu.XlButton.new(Lang.t("backtogame"), "_success")
	_size_button(back, Rect2(bx, content.end.y - bh, bw, bh))
	back.pressed.connect(close)
	_window.add_child(back)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _size_button(b: SettingsMenu.XlButton, r: Rect2) -> void:
	# Fontsize 50 % of the button, auto-shrunk into the padding box (17% 15% 29% 15%)
	HudStyle.place(b, r)
	HudStyle.place(b.label, Rect2(r.size.x * 0.15, r.size.y * 0.17, r.size.x * 0.7, r.size.y * 0.54))
	b.label.add_theme_font_size_override("font_size", int(r.size.y * 0.5))
	HudStyle.fit(b.label, int(r.size.y * 0.5))


func _layout() -> void:
	var view := MenuLayout.layout_size(self)
	size = view
	_blur.size = view
	_tint.size = view
	_window.position = ((view - WINDOW) / 2.0).floor()
	queue_redraw()


func close() -> void:
	closed.emit()
	queue_free()
