class_name ExitDialog
extends Control
## The quit confirmation (ExitDialog.dui, mainmenu_dialogs.scss `.exit-dialog`): 450x160 window with the caption,
## the message (80 % wide, 24 px, centred, word-wrapped) and the Quit / Cancel buttons. `TGameStateManager.Close`
## shows it (`CanProgramClose` sets `ExitDialogVisible` while `FAllowClose` is false); Quit = `CloseNoPrompt`.
## The original's third button opens the feedback dialog when a feedback service exists; there is none here, so
## the layout is the `feedback. = nil` one: Quit + Cancel.

signal closed

const WINDOW := Vector2(450, 160)

var _window: Control
var _blur: ColorRect
var _tint: ColorRect


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			close())
	_blur = HudStyle.blur(Rect2(), Color.WHITE)
	add_child(_blur)
	_tint = HudStyle.rect(SettingsMenu.BACKDROP, Rect2())
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
	var header := HudStyle.picture(HudStyle.tex("Shared/dialog_header.tga"), Rect2((WINDOW.x - 370) / 2.0, -35 - 53 / 2.0, 370, 53))
	_window.add_child(header)
	var caption := HudStyle.label(Lang.t("exit_dialog_caption"), 22, HudStyle.WHITE, HudStyle.FONT_BOLD)
	HudStyle.place(caption, Rect2(370 * 0.05, 53 * 0.2, 370 * 0.9, 53 * 0.52))
	HudStyle.fit(caption, 22)
	header.add_child(caption)
	# .message: 80 % wide, centred on the window, 24 px, word-wrapped
	var message := HudStyle.label(Lang.t("exit_dialog_message"), 24, SettingsMenu.FONT_DEFAULT, HudStyle.FONT_REGULAR)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.place(message, Rect2(WINDOW.x * 0.1, 0, WINDOW.x * 0.8, WINDOW.y))
	_window.add_child(message)
	# .window-buttons, as in the settings dialog: 58 high, centred 35 px below the window
	var total := 2 * SettingsMenu.BUTTON_W + 40.0
	var x := (WINDOW.x - total) / 2.0 + 10.0
	var y := WINDOW.y + 35.0 - SettingsMenu.BUTTON_H / 2.0
	var quit := SettingsMenu.XlButton.new(Lang.t("exit_dialog_close_btn_caption"), "_danger")
	quit.position = Vector2(x, y)
	quit.pressed.connect(func(): get_tree().quit())   # client.CloseNoPrompt
	_window.add_child(quit)
	var cancel := SettingsMenu.XlButton.new(Lang.t("cancel"))
	cancel.position = Vector2(x + SettingsMenu.BUTTON_W + 20.0, y)
	cancel.pressed.connect(close)
	_window.add_child(cancel)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var view := MenuLayout.layout_size(self)
	size = view
	_blur.size = view
	_tint.size = view
	_window.position = ((view - WINDOW) / 2.0).floor()


func close() -> void:
	closed.emit()
	queue_free()
