class_name FinalScreen
extends Control
## Victory / defeat banner (HUD/FinalScreen/Final.dui, core_game_dialogs.scss `.final`): shown
## TIME_OFFSET_ENDSCREEN after the game ends, the Continue button (or TIME_TO_FINISH_GAME) leaves the match.

signal continue_pressed

const TIME_OFFSET_ENDSCREEN := 4000            # Constants.Client.pas:46
const TIME_TO_FINISH_GAME := TIME_OFFSET_ENDSCREEN + 7000
const BANNER_W := 1920.0
const BANNER_H := 289.0
const BUTTON_W := 155.0
const BUTTON_H := 58.0

var _panel: Control
var _result: TextureRect
var _finished_at: int = -1
var _victory := false
var _shown := false
var _left := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	_panel = Control.new()
	_panel.mouse_filter = MOUSE_FILTER_STOP
	HudStyle.place(_panel, Rect2(0, (1080 - BANNER_H) / 2.0, BANNER_W, BANNER_H))
	add_child(_panel)
	_panel.add_child(HudStyle.picture(HudStyle.tex("HUD/FinalScreen/banner.png"), Rect2(0, 0, BANNER_W, BANNER_H)))
	_result = HudStyle.picture(null, Rect2())
	_panel.add_child(_result)
	var button := TextureButton.new()   # btn-xl: Shared/button_xl.tga, hover variant, 5 % above the bottom
	button.texture_normal = HudStyle.tex("Shared/button_xl.tga")
	button.texture_hover = HudStyle.tex("Shared/button_xl_hover.tga")
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	HudStyle.place(button, Rect2((BANNER_W - BUTTON_W) / 2.0, BANNER_H - BUTTON_H - BANNER_H * 0.05, BUTTON_W, BUTTON_H))
	button.pressed.connect(_leave)
	_panel.add_child(button)
	var caption := HudStyle.outline(HudStyle.label(Lang.t("continue"), 20, Color.WHITE, HudStyle.FONT_EXTRABOLD), 1,
		Color(0x3A / 255.0, 0x3F / 255.0, 0x3F / 255.0, 1.0))
	HudStyle.place(caption, Rect2(BUTTON_W * 0.15, BUTTON_H * 0.17, BUTTON_W * 0.70, BUTTON_H * 0.54))   # padding 17 % 15 % 29 % 15 %
	button.add_child(caption)


## TClientEntityManagerComponent: the losing team's nexus death decides victory for everyone else.
## Timers run on the wall clock (TTimer) because the simulation stops stepping once it is finished.
func game_over(losing_team: int, own_team: int) -> void:
	if _finished_at >= 0:
		return
	_finished_at = Time.get_ticks_msec()
	_victory = losing_team != own_team


func refresh() -> void:
	if _finished_at < 0 or _left:
		return
	var now := Time.get_ticks_msec()
	if not _shown and now - _finished_at >= TIME_OFFSET_ENDSCREEN:
		_shown = true
		var tex := HudStyle.tex("HUD/FinalScreen/%s.png" % ("Victory" if _victory else "Defeat"))
		var h := BANNER_H * 0.30
		var w := h * tex.get_width() / tex.get_height()
		_result.texture = tex
		HudStyle.place(_result, Rect2((BANNER_W - w) / 2.0, (BANNER_H - h) / 2.0, w, h))
		visible = true
		_panel.scale = Vector2(0.6, 0.6)   # $scale-in
		_panel.pivot_offset = _panel.size / 2.0
		create_tween().tween_property(_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if now - _finished_at >= TIME_TO_FINISH_GAME:
		_leave()


func _leave() -> void:
	if _left:
		return
	_left = true
	continue_pressed.emit()
