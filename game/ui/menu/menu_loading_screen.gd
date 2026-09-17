class_name MenuLoadingScreen
extends Control
## The main menu's own loading page (MainMenu/LoadingScreen/LoadingScreen.dui, `.state-page.loading-main-page`,
## state_pages_shared.scss), shown while the client's API is not ready or the menu is preloading
## (TGameStateMainMenu.IsPreLoading). Layout values are the stylesheet's, resolved per the engine's rules
## (docs/lobby.md section 3): `%` positions are relative to the parent's content rect, `auto` sizes keep the
## background art's aspect ratio, `FontSize : 100%` is the element's height.

signal logo_clicked(url: String)

const PADDING := 10.0                 # .state-page Padding : 10
const FONT_DEFAULT := Color(0xA9 / 255.0, 0xDC / 255.0, 0xE7 / 255.0, 1.0)   # $font-color-default
const SLOW_LOADING_TIME_MS := 40 * 1000   # TGameStateMainMenu.SLOW_LOADING_TIME
const SPINNER_ROTATION := -1.0        # rotation="-1.0" (radians per second, Engine.GUI.pas:4823)
const URL_PUBLISHER := "http://www.crunchyleafgames.com/"   # BrowseTo(wePublisher)
const URL_COMPANY := "http://brokengames.de"                 # BrowseTo(weCompany)
const URL_FMOD := "http://fmod.com/"                         # BrowseTo(weFMod)

var _logo: TextureRect
var _banner: TextureRect
var _opener: Label
var _status_text: Label
var _spinner: TextureRect
var _logos: Array = []   # [TextureRect, aspect w/h]
var _shown_at_ms: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_logo = HudStyle.picture(HudStyle.tex("Shared/Logos/game_logo.png"), Rect2())
	add_child(_logo)
	_banner = HudStyle.picture(HudStyle.tex("MainMenu/LoadingScreen/ReleaseBanner.png"), Rect2())
	_logo.add_child(_banner)
	# .opener: FontSize 24, FontWeight 700, [ffCenter, ffWordWrap]
	_opener = HudStyle.label(Lang.t("main_menu_loading_opener"), 24, FONT_DEFAULT, HudStyle.FONT_BOLD)
	_opener.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_opener.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_opener)
	# .status .text: FontSize 100% (= its height), [ffCenter, ffVerticalCenter], root weight 500
	_status_text = HudStyle.label(Lang.t("gui_load_main_menu"), 24, FONT_DEFAULT, HudStyle.FONT_MEDIUM)
	add_child(_status_text)
	# .spinner: Shared/Spinner.png tinted $font-color-default, rotating
	_spinner = HudStyle.picture(HudStyle.tex("Shared/Spinner.png"), Rect2())
	_spinner.modulate = FONT_DEFAULT
	add_child(_spinner)
	for entry in [["Shared/Logos/crunchy_leaf_logo.tga", URL_PUBLISHER], ["Shared/Logos/broken_games_logo.png", URL_COMPANY],
			["Shared/Logos/fmod_logo.png", URL_FMOD]]:
		var tex: Texture2D = HudStyle.tex(entry[0])
		var pic := HudStyle.picture(tex, Rect2())
		pic.mouse_filter = MOUSE_FILTER_STOP   # Enabled : True (clickable)
		var url: String = entry[1]
		pic.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				logo_clicked.emit(url))
		add_child(pic)
		_logos.append([pic, float(tex.get_width()) / tex.get_height()])
	_logos[2][0].modulate.a = 0.7   # .fmod-logo Opacity : 0.7
	get_viewport().size_changed.connect(_layout)
	_layout()
	_shown_at_ms = Time.get_ticks_msec()


func _process(delta: float) -> void:
	_spinner.rotation += SPINNER_ROTATION * delta
	var slow := Time.get_ticks_msec() - _shown_at_ms >= SLOW_LOADING_TIME_MS
	_status_text.text = Lang.t("gui_load_main_menu_slow" if slow else "gui_load_main_menu")


func _layout() -> void:
	var view := get_viewport_rect().size
	var content := Rect2(PADDING, PADDING, view.x - 2 * PADDING, view.y - 2 * PADDING)   # the page's content rect
	var cw := content.size.x
	var ch := content.size.y
	var centre := content.get_center()
	# .game-logo: Size 30% auto, Anchor caBottom, ParentAnchor caCenter, Position 0 -10% (loading-main-page)
	var logo_w := 0.3 * cw
	var logo_h := logo_w * _logo.texture.get_height() / _logo.texture.get_width()
	var logo_bottom := centre.y - 0.1 * ch
	HudStyle.place(_logo, Rect2(centre.x - logo_w / 2.0, logo_bottom - logo_h, logo_w, logo_h))
	# .banner: Size auto 100bh (the art's height), Anchor caTop, ParentAnchor caBottom, Position 0 -20%
	var banner_h := float(_banner.texture.get_height())
	var banner_w := banner_h * _banner.texture.get_width() / banner_h
	HudStyle.place(_banner, Rect2(logo_w / 2.0 - banner_w / 2.0, logo_h - 0.2 * logo_h, banner_w, banner_h))
	# .opener: Size 80% 50%, Anchor caTop, ParentAnchor caCenter, Position 0 -10%, Padding-Top 7.3vh
	var opener_w := 0.8 * cw
	var opener_top := centre.y - 0.1 * ch + 0.073 * view.y
	HudStyle.place(_opener, Rect2(centre.x - opener_w / 2.0, opener_top, opener_w, 0.5 * ch - 0.073 * view.y))
	# .status: Size 50% 7.5%, Anchor caBottom, ParentAnchor caBottom, Position 0 -10%
	var status_w := 0.5 * cw
	var status_h := 0.075 * ch
	var status := Rect2(centre.x - status_w / 2.0, content.end.y - 0.1 * ch - status_h, status_w, status_h)
	# .text: Size 100% 46.67% at the top, FontSize 100%
	var text_h := 0.4667 * status_h
	HudStyle.place(_status_text, Rect2(status.position.x, status.position.y, status_w, text_h))
	_status_text.add_theme_font_size_override("font_size", int(text_h))
	# .spinner: Size auto 53.33%, Anchor caBottom, ParentAnchor caBottom, Position 0 20%
	var spinner_s := 0.5333 * status_h
	var spinner_bottom := status.end.y + 0.2 * status_h
	_spinner.size = Vector2(spinner_s, spinner_s)
	_spinner.pivot_offset = _spinner.size / 2.0
	_spinner.position = Vector2(centre.x - spinner_s / 2.0, spinner_bottom - spinner_s)
	# Publisher / company / audio logos along the content's bottom-left edge (state_pages_shared.scss)
	var crunchy_h := 0.08 * ch                                   # .crunchy-logo Size auto 8%
	var crunchy_w: float = crunchy_h * _logos[0][1]
	HudStyle.place(_logos[0][0], Rect2(content.position.x, content.end.y - crunchy_h, crunchy_w, crunchy_h))
	var broken_w := 0.08 * cw                                    # .broken-logo Position 7%, Size 8% auto
	var broken_h: float = broken_w / _logos[1][1]
	HudStyle.place(_logos[1][0], Rect2(content.position.x + 0.07 * cw, content.end.y - broken_h, broken_w, broken_h))
	var fmod_w := 0.08 * cw                                      # .fmod-logo Position 17% -2.5%, Size 8% auto
	var fmod_h: float = fmod_w / _logos[2][1]
	HudStyle.place(_logos[2][0], Rect2(content.position.x + 0.17 * cw, content.end.y - 0.025 * ch - fmod_h, fmod_w, fmod_h))
