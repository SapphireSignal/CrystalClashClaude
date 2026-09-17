class_name Announcements
extends Control
## Centre-top announcement banner (HUD/Announcements/Announcements.dui, core_game.scss `.announcements`):
## warm-up countdown, stage 1/2/3 and showdown (TClientGUIComponent.OnGameEvent / OnGameTick).

const WIDTH := 1189.0
const HEIGHT := 206.0
const TOP := 150.0
const FADE_MS := 200

var _title: Label
var _subtitle: Label
var _hide_at_ms: int = -1     # ShowAnnouncementForTime: sim time when the banner fades
var _shown := false


func _ready() -> void:
	size = Vector2(WIDTH, HEIGHT)
	mouse_filter = MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	add_child(HudStyle.picture(HudStyle.tex("HUD/Announcements/AnnouncementBackground.png"), Rect2(0, 0, WIDTH, HEIGHT)))
	# .content padding 29 % 10 %, title 70 % of it, subtitle 32 % at the bottom
	var content := Rect2(WIDTH * 0.10, HEIGHT * 0.29, WIDTH * 0.80, HEIGHT * 0.42)
	_title = HudStyle.label("", 46, HudStyle.WHITE, HudStyle.FONT_BOLD)
	_title.uppercase = true
	HudStyle.place(_title, Rect2(content.position, Vector2(content.size.x, content.size.y * 0.70)))
	add_child(_title)
	_subtitle = HudStyle.label("", 26, HudStyle.WHITE, HudStyle.FONT_BOLD)
	HudStyle.place(_subtitle, Rect2(content.position.x, content.end.y - content.size.y * 0.32 - HEIGHT * 0.05, content.size.x, content.size.y * 0.32))
	add_child(_subtitle)


## TIngameHUD.ShowAnnouncement: core_announcement_title_<uid> / core_announcement_subtitle_<uid>.
func show_announcement(uid: String, now: int, duration_ms: int = -1) -> void:
	show_text(Lang.t("core_announcement_title_%s" % uid), Lang.t("core_announcement_subtitle_%s" % uid), now, duration_ms)


func show_text(title: String, subtitle: String, now: int, duration_ms: int = -1) -> void:
	_title.text = title
	_subtitle.text = subtitle
	_hide_at_ms = now + duration_ms if duration_ms >= 0 else -1
	if not _shown:
		_shown = true
		_fade(1.0)


func hide_announcement() -> void:
	if _shown:
		_shown = false
		_fade(0.0)


func refresh(now: int) -> void:
	if _shown and _hide_at_ms >= 0 and now >= _hide_at_ms:
		hide_announcement()


func _fade(to: float) -> void:
	create_tween().tween_property(self, "modulate:a", to, FADE_MS / 1000.0)
