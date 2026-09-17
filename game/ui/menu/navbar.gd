class_name Navbar
extends Control
## The main menu's navigation bar (MainMenu/Navbar/Navbar.dui, navbar.scss, navbar_player.scss). Layout values
## are the stylesheet's, resolved per docs/lobby.md section 3: the wrapper is `100% auto` of NavbarBackground.png
## (1280x68), the bar itself 54 px high with `Padding : 3 0`, buttons `1000text 100%` wide with 15 px side padding,
## font 43 % of the content height, and the player panel pinned to the right edge (`Position : -1`).
## Profile values (name, level, currencies) come from the caller; there is no master server, so they are the
## local player's stubs (MainMenu.PROFILE).

signal menu_selected(menu: int)

const SIZE := 54.0                     # $navbar-size
const PADDING_Y := 3.0                 # .navbar Padding : 3 0
const BUTTON_PADDING_X := 15.0         # .btn-nav Padding : 0 15
const START_WIDTH := 53.0              # .start width : 53
const START_BACKGROUND := Color(0x31 / 255.0, 0x47 / 255.0, 0x47 / 255.0, 1.0)
const START_BACKGROUND_HOVER := Color(0x36 / 255.0, 0x4f / 255.0, 0x4f / 255.0, 1.0)
const FONT_SUBTLE := Color(0x83 / 255.0, 0x9C / 255.0, 0x9C / 255.0, 1.0)      # $font-color-subtle
const FONT_HIGHLIGHT := Color(0xD6 / 255.0, 0xF5 / 255.0, 0xF5 / 255.0, 1.0)   # $font-color-highlight
const FONT_GOLD := Color(0xEE / 255.0, 0xF4 / 255.0, 0xAD / 255.0, 1.0)        # $font-color-gold
const FONT_CRYSTAL := Color(0x83 / 255.0, 1.0, 1.0, 1.0)                        # $font-color-crystal
const FONT_DISABLED := Color(1.0, 1.0, 1.0, 0.5)                                # .btn-nav:disabled $80FFFFFF
const DARK_BACKGROUND := Color(0, 0, 0, 0x30 / 255.0)                           # $dark-background
const PLAY_MIN_WIDTH_CH := 2.042       # .btn-play MinWidth : 204.2ch
const LEVEL_COLLECTION := 1            # Collection locked below player level 1
const LEVEL_LEADERBOARDS := 5          # Leaderboards locked below player level 5

## menu ids in the order of MainMenu.Menu
const BUTTONS := [
	["start", "", "navbar_menu_start_hint", 0],
	["play", "navbar_menu_play", "navbar_menu_play_hint", 0],
	["deck", "navbar_menu_deckbuilding", "navbar_menu_deckbuilding_hint", 0],
	["collection", "navbar_menu_collection", "navbar_menu_collection_hint", LEVEL_COLLECTION],
	["leaderboards", "navbar_menu_leaderboards", "navbar_menu_leaderboards_hint", LEVEL_LEADERBOARDS],
	["shop", "navbar_menu_shop", "navbar_menu_shop_hint", 0],
]

var profile: Dictionary
var _background: TextureRect
var _buttons: Array = []       # NavButton per BUTTONS entry
var _selected := 0
var _premium: TextureRect
var _user: Control
var _user_bar: TextureRect
var _user_caption: Label
var _member_icon: TextureRect
var _currencies: Array = []    # [wrapper Control, icon TextureRect, balance Label] x 2


class NavButton extends Control:
	var index: int
	var kind: String
	var label: Label
	var indicator: TextureRect      # .selection-indicator (chosen_tab_indicator.png), behind the text
	var highlight: TextureRect      # .btn-play .highlight (play_button.png)
	var lock: TextureRect           # .player-level-lock > icon.lock
	var start_fill: ColorRect       # .start BackgroundColor
	var logo: TextureRect           # .start .logo (Home.png)
	var hovered := false
	var enabled := true
	var selected := false

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_STOP
		mouse_entered.connect(func(): hovered = true; _restyle())
		mouse_exited.connect(func(): hovered = false; _restyle())

	func _restyle() -> void:
		var color := Navbar.FONT_SUBTLE
		var font: Font = HudStyle.FONT_MEDIUM   # FontWeight : 500
		if not enabled:
			color = Navbar.FONT_DISABLED
		elif kind == "play":   # .btn-play FontColor highlight, hover real white + hover art
			color = Color.WHITE if hovered else Navbar.FONT_HIGHLIGHT
		elif kind == "shop":   # .btn-shop gold, hover lighten 0.8
			color = Navbar.FONT_GOLD.lerp(Color.WHITE, 0.8) if hovered else Navbar.FONT_GOLD
		elif hovered:
			color = Navbar.FONT_HIGHLIGHT
		if selected and enabled:   # &.selected: Fontweight 1000, highlight colour, indicator visible
			color = Navbar.FONT_HIGHLIGHT
			font = HudStyle.FONT_EXTRABOLD
		if label != null:
			label.add_theme_color_override("font_color", color)
			label.add_theme_font_override("font", font)
		if indicator != null:
			indicator.visible = selected
		if highlight != null:
			highlight.texture = HudStyle.tex("MainMenu/Navbar/play_button_hover.png" if hovered and enabled else "MainMenu/Navbar/play_button.png")
		if start_fill != null:
			start_fill.color = Navbar.START_BACKGROUND_HOVER if hovered else Navbar.START_BACKGROUND


func _init(p: Dictionary) -> void:
	profile = p


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	mouse_filter = MOUSE_FILTER_IGNORE   # .navbar-wrapper MouseEvents : mePass
	_background = HudStyle.picture(HudStyle.tex("MainMenu/Navbar/NavbarBackground.png"), Rect2())
	add_child(_background)
	for i in BUTTONS.size():
		var entry: Array = BUTTONS[i]
		var b := NavButton.new()
		b.index = i
		b.kind = entry[0]
		b.tooltip_text = Lang.t(entry[2])
		if b.kind == "start":
			b.start_fill = HudStyle.rect(START_BACKGROUND, Rect2())
			b.add_child(b.start_fill)
			b.logo = HudStyle.picture(HudStyle.tex("MainMenu/Navbar/Home.png"), Rect2())
			b.add_child(b.logo)
		else:
			if b.kind == "play":
				b.highlight = HudStyle.picture(HudStyle.tex("MainMenu/Navbar/play_button.png"), Rect2())
				b.add_child(b.highlight)
			b.indicator = HudStyle.picture(HudStyle.tex("MainMenu/Navbar/chosen_tab_indicator.png"), Rect2())
			b.indicator.visible = false
			b.add_child(b.indicator)
			b.label = HudStyle.label(Lang.t(entry[1]), 20, FONT_SUBTLE, HudStyle.FONT_MEDIUM)
			b.label.uppercase = true   # TextTransform : ttUppercase
			b.add_child(b.label)
			b.enabled = int(profile.get("level", 1)) >= int(entry[3])
			if not b.enabled:
				b.lock = HudStyle.picture(HudStyle.tex("Shared/Lock.png"), Rect2())
				b.add_child(b.lock)
				b.tooltip_text = Lang.t("feature_level_requirement") % int(entry[3])
		b.gui_input.connect(_on_button_input.bind(b))
		add_child(b)
		_buttons.append(b)
		b._restyle()
	# .player-panel (navbar_player.scss): resource panel | team panel | boosts over the user progress bar
	for entry in [["currency_gold", "currency_gold_hint", "credits"], ["currency_diamonds", "currency_diamonds_hint", "crystals"]]:
		var wrapper := Control.new()
		wrapper.mouse_filter = MOUSE_FILTER_STOP
		wrapper.tooltip_text = Lang.t(entry[1])
		wrapper.add_child(HudStyle.rect(DARK_BACKGROUND, Rect2()))
		var icon := HudStyle.picture(HudStyle.tex("Shared/CurrencyIcons/%s.png" % entry[0]), Rect2())
		wrapper.add_child(icon)
		var balance := HudStyle.label(str(int(profile.get(entry[2], 0))), 16, FONT_CRYSTAL, HudStyle.FONT_SEMIBOLD, HORIZONTAL_ALIGNMENT_RIGHT)
		wrapper.add_child(balance)
		add_child(wrapper)
		_currencies.append([wrapper, icon, balance])
	_member_icon = HudStyle.picture(HudStyle.tex("Shared/Icons/UnknownPlayer.png"), Rect2())
	_member_icon.tooltip_text = str(profile.get("name", ""))
	_member_icon.mouse_filter = MOUSE_FILTER_STOP
	add_child(_member_icon)
	_premium = HudStyle.picture(HudStyle.tex("MainMenu/Navbar/PremiumIndicator.png"), Rect2())
	_premium.modulate = HudStyle.DARKEN   # BackgroundColorOverride $override-darken while not premium
	_premium.tooltip_text = Lang.t("profile_boosts_premium_inactive")
	_premium.mouse_filter = MOUSE_FILTER_STOP
	add_child(_premium)
	_user = Control.new()
	_user.mouse_filter = MOUSE_FILTER_STOP
	_user.add_child(HudStyle.rect(DARK_BACKGROUND, Rect2()))
	_user_bar = HudStyle.picture(HudStyle.tex("MainMenu/Navbar/xp_bar_background.png"), Rect2())
	_user.add_child(_user_bar)
	_user_caption = HudStyle.label("%s (%d)" % [str(profile.get("name", "")).left(20), int(profile.get("level", 1))], 16,
			FONT_CRYSTAL, HudStyle.FONT_SEMIBOLD, HORIZONTAL_ALIGNMENT_LEFT)
	_user.add_child(_user_caption)
	add_child(_user)
	get_viewport().size_changed.connect(_layout)
	_layout()


func select(menu: int) -> void:
	_selected = menu
	for b in _buttons:
		b.selected = b.index == menu
		b._restyle()


func _on_button_input(ev: InputEvent, b: NavButton) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and b.enabled:
		menu_selected.emit(b.index)


func _layout() -> void:
	var view := MenuLayout.layout_size(self)
	var w := view.x
	size = Vector2(w, SIZE)
	# .navbar-wrapper: Size 100% auto -> the art's aspect
	HudStyle.place(_background, Rect2(0, 0, w, w * _background.texture.get_height() / _background.texture.get_width()))
	var h := SIZE - 2 * PADDING_Y   # content height 48
	var font_size := int(round(0.43 * h))   # Fontsize : 43%
	var x := 0.0
	for b in _buttons:
		var bw := 0.0
		if b.kind == "start":
			bw = START_WIDTH
			HudStyle.place(b.start_fill, Rect2(0, 0, bw, h))
			var logo_h := 0.65 * h   # .logo Size auto 65%, centred
			var logo_w: float = logo_h * b.logo.texture.get_width() / b.logo.texture.get_height()
			HudStyle.place(b.logo, Rect2((bw - logo_w) / 2.0, (h - logo_h) / 2.0, logo_w, logo_h))
		else:
			b.label.add_theme_font_size_override("font_size", font_size)
			var font: Font = b.label.get_theme_font("font")
			var text_w := font.get_string_size(b.label.text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			bw = ceil(text_w) + 2 * BUTTON_PADDING_X   # size : 1000text 100% + Padding 0 15
			if b.kind == "play":
				x += 10.0   # Margin : 0 0 0 10
				bw = max(bw, PLAY_MIN_WIDTH_CH * h)
				var hh := float(b.highlight.texture.get_height())   # Size auto 100bh, centred
				var hw := float(b.highlight.texture.get_width())
				HudStyle.place(b.highlight, Rect2((bw - hw) / 2.0, (h - hh) / 2.0, hw, hh))
			HudStyle.place(b.label, Rect2(0, 0, bw, h))
			var iw: float = h * b.indicator.texture.get_width() / b.indicator.texture.get_height()   # Size auto 100%
			HudStyle.place(b.indicator, Rect2((bw - iw) / 2.0, 0, iw, h))
			if b.lock != null:
				var lh := 0.35 * h   # icon.lock Size auto 35%, centred
				var lw: float = lh * b.lock.texture.get_width() / b.lock.texture.get_height()
				HudStyle.place(b.lock, Rect2((bw - lw) / 2.0, (h - lh) / 2.0, lw, lh))
		HudStyle.place(b, Rect2(x, PADDING_Y, bw, h))
		x += bw
	# .player-panel: Position -1, stacked from the right edge
	var right := w - 1.0
	var column_w := 0.125 * w   # .boosts / .user Size 12.5vw
	var boosts_h := 0.45 * h
	var pad := 0.15 * boosts_h   # Padding : 15ch 0
	var premium_h := boosts_h - 2 * pad
	var premium_w: float = premium_h * _premium.texture.get_width() / _premium.texture.get_height()
	HudStyle.place(_premium, Rect2(right - column_w + 3.0, PADDING_Y + pad, premium_w, premium_h))   # Margin-Left 3
	var user_h := 0.55 * h
	HudStyle.place(_user, Rect2(right - column_w, PADDING_Y + h - user_h, column_w, user_h))
	HudStyle.place(_user.get_child(0), Rect2(0, 0, column_w, user_h))
	var inner := Rect2(2, 2, column_w - 4, user_h - 4)   # Padding : 2
	HudStyle.place(_user_bar, Rect2(inner.position, Vector2(inner.size.x * clamp(float(profile.get("level_progress", 0.0)), 0.0, 1.0), inner.size.y)))
	var cap_h := 0.7 * inner.size.y   # caption: bottom-left, Size 100% 70%, Padding-Left 3
	HudStyle.place(_user_caption, Rect2(inner.position.x + 3.0, inner.end.y - cap_h, inner.size.x - 3.0, cap_h))
	HudStyle.fit(_user_caption, int(cap_h))
	# .team-panel: Size auto 100%, Margin-Right 30; one member icon (the 1v1 team is full, no invite button)
	var member_x := right - column_w - 30.0 - h
	HudStyle.place(_member_icon, Rect2(member_x, PADDING_Y, h, h))
	# .resource-panel: Size 11.5vw 100%, Padding 25% 0; two .currency-wrapper Size 50% 100%, Margin-Right 25%
	var panel_w := 0.115 * w
	var wrapper_w := 0.5 * panel_w
	var margin := 0.25 * wrapper_w
	var pad_y := 0.25 * h
	var wrapper_h := h - 2 * pad_y
	var wx := member_x - 3.0 - 2 * (wrapper_w + margin)
	for c in _currencies:
		var wrapper: Control = c[0]
		HudStyle.place(wrapper, Rect2(wx, PADDING_Y + pad_y, wrapper_w, wrapper_h))
		HudStyle.place(wrapper.get_child(0), Rect2(0, 0, wrapper_w, wrapper_h))
		var icon: TextureRect = c[1]   # img: Position -30ch 0, Size auto 170%, left-centred
		var ih := 1.7 * wrapper_h
		var iw := ih * icon.texture.get_width() / icon.texture.get_height()
		HudStyle.place(icon, Rect2(-0.3 * wrapper_h, (wrapper_h - ih) / 2.0, iw, ih))
		var balance: Label = c[2]   # .balance Padding 12% 4% 8% 32%, right + vertically centred, auto-shrink
		var br := Rect2(0.32 * wrapper_w, 0.12 * wrapper_h, wrapper_w * (1.0 - 0.32 - 0.04), wrapper_h * (1.0 - 0.12 - 0.08))
		HudStyle.place(balance, br)
		HudStyle.fit(balance, int(br.size.y))
		wx += wrapper_w + margin
