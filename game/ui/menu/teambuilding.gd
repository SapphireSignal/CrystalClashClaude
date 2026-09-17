class_name Teambuilding
extends Control
## The Play screen (MainMenu/Teambuilding/Teambuilding.dui, matchmaking.scss, Teamlist.dui, Queue.dui): a
## sub-navbar with the scenario types, the type description with the tier hint, the scenario options, the
## team list (one member with their deck) and the Start button. There is no master server, so there is no
## queue: Start asks the app to begin the sandbox match. The scenario/difficulty/deck dialogs are not built;
## their buttons show the current choice.

signal start_requested

const SUB_PADDING_X := 0.045      # .navbar-sub Padding-Left/Right 4.5%
const SUB_TOP := 54.0             # $navbar-size: the strip sits directly below the navbar
const SUB_PADDING_BOTTOM := 0.15  # .navbar-sub Padding-Bottom 15 % (of the strip height)
const SUB_BUTTON_PADDING_Y := 3.0 # .btn-nav Padding-Top 2 + Padding-Bottom 1
const SUB_FONT_FACTOR := 0.9      # .btn-nav Fontsize 90 % (of its own height)
# The strip is `Size : 100% auto`, so its height comes from SubNavbarBackground.png (2560x55 -> 27.5 at the
# 1280 canvas width) and the content box below the 15 % padding is 23.4 high, i.e. $navbar-sub-size (23).
const CONTENT_PADDING := [40.0, 10.0, 10.0, 10.0]   # .content-sub Padding : 40 10 10 10
const FONT_DEFAULT := Dashboard.FONT_DEFAULT
const FONT_SUCCESS := Color(0, 1, 0, 1)   # $font-color-highlight-strong
const LEVEL_DUO := 2

## [id, label key, level requirement, pve]; EnumScenarioType names from the .dui
const SCENARIOS := [
	["es1v1", "teambuilding_mode_pvp", 0, false],
	["es2v2", "teambuilding_mode_pvp_duo", LEVEL_DUO, false],
	["es1vE", "teambuilding_mode_pve", 0, true],
	["es2vE", "teambuilding_mode_pve_duo", LEVEL_DUO, true],
	["esDuel", "teambuilding_mode_duel", 0, false],
	["esTutorial", "teambuilding_mode_tutorial", 0, false],   # the .right stack
]

var profile: Dictionary
var chosen := "es1v1"   # matchmaking.ChosenScenario
var deck_name := ""
var deck_league := 1
var _sub_background: TextureRect
var _tabs: Array = []            # Navbar.NavButton per SCENARIOS entry
var _description: Label
var _league_hint: Label
var _exclamations: Array = []
var _options: Array = []         # [button Control, text Label, caption Label, league icon or null]
var _member_frame: TextureRect
var _member_icon: TextureRect
var _member_name: Label
var _member_leader: Label
var _deck: TextureRect
var _deck_icon: TextureRect
var _deck_name: Label
var _deck_league: TextureRect
var _deck_banner: TextureRect
var _deck_banner_text: Label
var _start: TextureRect
var _start_label: Label
var _start_hovered := false
var _guides: TextureRect


func _init(p: Dictionary, p_deck_name: String, p_deck_league: int) -> void:
	profile = p
	deck_name = p_deck_name
	deck_league = p_deck_league


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	# .navbar.navbar-sub
	_sub_background = HudStyle.picture(HudStyle.tex("MainMenu/Navbar/SubNavbarBackground.png"), Rect2())
	_sub_background.z_index = 1   # .navbar-sub ZOffset 900: above the navbar wrapper's art (ZOffset 100)
	add_child(_sub_background)
	for i in SCENARIOS.size():
		var entry: Array = SCENARIOS[i]
		var b := Navbar.NavButton.new()
		b.index = i
		b.kind = "sub"
		b.tooltip_text = Lang.t("scenario_type_description_" + entry[0])
		b.indicator = HudStyle.picture(HudStyle.tex("MainMenu/Navbar/chosen_tab_indicator.png"), Rect2())
		b.indicator.visible = false
		b.add_child(b.indicator)
		b.label = HudStyle.label(Lang.t(entry[1]), 18, Navbar.FONT_SUBTLE, HudStyle.FONT_MEDIUM)
		b.label.uppercase = true
		b.add_child(b.label)
		b.enabled = int(profile.get("level", 1)) >= int(entry[2])
		if not b.enabled:
			b.lock = HudStyle.picture(HudStyle.tex("Shared/Lock.png"), Rect2())
			b.add_child(b.lock)
			b.tooltip_text = Lang.t("feature_level_requirement") % int(entry[2])
		b.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and b.enabled:
				choose(entry[0]))
		b.z_index = 1
		add_child(b)
		_tabs.append(b)
	# .layout: description + league hint, scenario options
	_description = HudStyle.label("", 24, FONT_DEFAULT, HudStyle.FONT_MEDIUM)
	add_child(_description)
	_league_hint = HudStyle.label(Lang.t("scenario_type_description_pvp_tier_hint"), 24, FONT_DEFAULT, HudStyle.FONT_BOLD)
	add_child(_league_hint)
	for _i in 2:
		var e := HudStyle.picture(HudStyle.tex("Shared/exclamation_success.png"), Rect2())
		_league_hint.add_child(e)
		_exclamations.append(e)
	for caption_key in ["teambuilding_choose_gamemode", "teambuilding_choose_difficulty"]:
		var button := HudStyle.picture(HudStyle.tex("MainMenu/Teambuilding/Button_Sub.png"), Rect2())
		button.mouse_filter = MOUSE_FILTER_STOP
		button.mouse_entered.connect(func(): button.texture = HudStyle.tex("MainMenu/Teambuilding/button_sub_hover.png"))
		button.mouse_exited.connect(func(): button.texture = HudStyle.tex("MainMenu/Teambuilding/Button_Sub.png"))
		var text := HudStyle.label("", 24, FONT_DEFAULT, HudStyle.FONT_MEDIUM)
		button.add_child(text)
		var caption := HudStyle.label(Lang.t(caption_key), 16, FONT_DEFAULT, HudStyle.FONT_MEDIUM)
		button.add_child(caption)
		var icon: TextureRect = null
		if caption_key == "teambuilding_choose_difficulty":
			icon = HudStyle.picture(HudStyle.tex("Shared/LeagueIcons/League1.tga"), Rect2())
			text.add_child(icon)
		add_child(button)
		_options.append([button, text, caption, icon])
	# .scenario-team > .teamlist: one .team-member (member-info | deck-info) and the selected-deck banner
	_member_frame = HudStyle.picture(HudStyle.tex("Shared/player_icon_frame.png"), Rect2())
	add_child(_member_frame)
	_member_icon = HudStyle.picture(HudStyle.tex("Shared/Icons/UnknownPlayer.png"), Rect2())
	_member_frame.add_child(_member_icon)
	_member_name = HudStyle.label(str(profile.get("name", "")), 16, FONT_DEFAULT, HudStyle.FONT_MEDIUM, HORIZONTAL_ALIGNMENT_LEFT)
	add_child(_member_name)
	_member_leader = HudStyle.label(Lang.t("teambuilding_teamleader"), 12, FONT_DEFAULT, HudStyle.FONT_MEDIUM, HORIZONTAL_ALIGNMENT_LEFT)
	_member_leader.modulate.a = 0.6
	add_child(_member_leader)
	_deck = HudStyle.picture(HudStyle.tex("MainMenu/Deckbuilding/Deckslot.png"), Rect2())
	_deck.tooltip_text = Lang.t("league_deck_hint").replace("§league_%d", Lang.t("league_%d" % deck_league))
	_deck.mouse_filter = MOUSE_FILTER_STOP
	add_child(_deck)
	_deck_icon = HudStyle.picture(HudStyle.tex("Shared/Icons/UnknownDeck.png"), Rect2())
	_deck.add_child(_deck_icon)
	_deck_name = HudStyle.label(deck_name, 16, FONT_DEFAULT, HudStyle.FONT_MEDIUM, HORIZONTAL_ALIGNMENT_LEFT)
	_deck.add_child(_deck_name)
	_deck_league = HudStyle.picture(HudStyle.tex("Shared/LeagueIcons/League%d.tga" % clamp(deck_league, 1, 5)), Rect2())
	_deck.add_child(_deck_league)
	_deck_banner = HudStyle.picture(HudStyle.tex("MainMenu/Teambuilding/selected_deck_banner.png"), Rect2())
	add_child(_deck_banner)
	_deck_banner_text = HudStyle.label(Lang.t("teambuilding_selected_deck"), 14, FONT_DEFAULT, HudStyle.FONT_MEDIUM)
	_deck_banner.add_child(_deck_banner_text)
	# .scenario-queue .btn-queue (btn-xl): tier art while the league is automatic (PvP), plain xl button otherwise
	_start = HudStyle.picture(HudStyle.tex("Shared/button_xl.tga"), Rect2())
	_start.mouse_filter = MOUSE_FILTER_STOP
	_start.tooltip_text = Lang.t("teambuilding_qeyes")
	_start.mouse_entered.connect(func(): _start_hovered = true; _refresh())
	_start.mouse_exited.connect(func(): _start_hovered = false; _refresh())
	_start.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			start_requested.emit())
	add_child(_start)
	_start_label = HudStyle.label(Lang.t("teambuilding_start_queue"), 20, HudStyle.WHITE, HudStyle.FONT_EXTRABOLD)
	_start.add_child(_start_label)
	# .btn-tutorial-videos (the Quick Guides dialog is not built)
	_guides = HudStyle.picture(HudStyle.tex("MainMenu/Tutorial/tutorial_video_button.png"), Rect2())
	add_child(_guides)
	var guides_label := HudStyle.label(Lang.t("tutorial_video_dialog_button_caption"), 14, FONT_SUCCESS, HudStyle.FONT_BOLD)
	guides_label.uppercase = true
	_guides.add_child(guides_label)
	get_viewport().size_changed.connect(_layout)
	choose(chosen)


func choose(id: String) -> void:
	chosen = id
	for b in _tabs:
		b.selected = SCENARIOS[b.index][0] == id
		b._restyle()
	_refresh()
	_layout()


func _is_pve() -> bool:
	for entry in SCENARIOS:
		if entry[0] == chosen:
			return entry[3]
	return false


func _refresh() -> void:
	_description.text = Lang.t("scenario_type_description_" + chosen)
	var pvp := chosen == "es1v1" or chosen == "es2v2"   # matchmaking.HasAutoLeague: the deck's league decides the tier
	_league_hint.visible = pvp
	for o in _options:   # .scenario-options-section is invisible without scenario/league selection (PvP)
		o[0].visible = _is_pve()
	_options[0][1].text = Lang.t("scenario_pve_sandbox")
	_options[1][1].text = "%s (%s)" % [Lang.t("scenario_difficulty_1"), Lang.t("scenario_difficulty_loot_1")]
	_start.texture = HudStyle.tex("MainMenu/Teambuilding/enter_queue_tier_%d%s.png" % [clamp(deck_league, 1, 4) - 1, "_hover" if _start_hovered else ""]) if pvp \
			else HudStyle.tex("Shared/button_xl%s.tga" % ("_hover" if _start_hovered else ""))


func _layout() -> void:
	var view := MenuLayout.layout_size(self)
	size = view
	var w := view.x
	# sub-navbar: background 100% auto below the navbar, buttons SUB_SIZE high with Padding-Top 2 / Bottom 1
	var sub_top := SUB_TOP
	var sub_h := w * _sub_background.texture.get_height() / _sub_background.texture.get_width()
	HudStyle.place(_sub_background, Rect2(0, sub_top, w, sub_h))
	var content_h := sub_h * (1.0 - SUB_PADDING_BOTTOM)   # the buttons fill the strip's content box
	var bh := content_h - SUB_BUTTON_PADDING_Y
	var font_size := int(round(bh * SUB_FONT_FACTOR))
	var tab_top := sub_top + (content_h - bh) / 2.0
	var x := SUB_PADDING_X * w
	var right_x := w - SUB_PADDING_X * w
	for b in _tabs:
		b.label.add_theme_font_size_override("font_size", font_size)
		var font: Font = b.label.get_theme_font("font")
		var bw: float = ceil(font.get_string_size(b.label.text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x) + 2 * Navbar.BUTTON_PADDING_X
		HudStyle.place(b.label, Rect2(0, 0, bw, bh))
		var iw: float = bh * b.indicator.texture.get_width() / b.indicator.texture.get_height()
		HudStyle.place(b.indicator, Rect2((bw - iw) / 2.0, 0, iw, bh))
		if b.lock != null:
			var lh := 0.35 * bh
			var lw: float = lh * b.lock.texture.get_width() / b.lock.texture.get_height()
			HudStyle.place(b.lock, Rect2((bw - lw) / 2.0, (bh - lh) / 2.0, lw, lh))
		if SCENARIOS[b.index][0] == "esTutorial":   # stack.right: anchored top-right
			HudStyle.place(b, Rect2(right_x - bw, tab_top, bw, bh))
		else:
			HudStyle.place(b, Rect2(x, tab_top, bw, bh))
			x += bw
	# .content-sub below the sub-navbar; .layout is a vertical stack at its top centre, 20 px between items
	var content := Rect2(CONTENT_PADDING[3], Navbar.SIZE + sub_h + CONTENT_PADDING[0], w - CONTENT_PADDING[1] - CONTENT_PADDING[3],
			view.y - Navbar.SIZE - sub_h - CONTENT_PADDING[0] - CONTENT_PADDING[2])
	var cx := content.get_center().x
	var y := content.position.y
	var desc_w := 0.8 * w   # .scenario-type-description Size 80vw 24
	HudStyle.place(_description, Rect2(cx - desc_w / 2.0, y, desc_w, 24))
	# .league-hint: below the description (Position 0 10), Size text 100%, exclamation marks 200 % high at both ends
	var hint_font: Font = _league_hint.get_theme_font("font")
	var hint_w: float = ceil(hint_font.get_string_size(_league_hint.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x)
	HudStyle.place(_league_hint, Rect2(cx - hint_w / 2.0, y + 24 + 10, hint_w, 24))
	var ex_h := 48.0
	var ex_w: float = ex_h * _exclamations[0].texture.get_width() / _exclamations[0].texture.get_height()
	HudStyle.place(_exclamations[0], Rect2(-10 - ex_w, (24 - ex_h) / 2.0, ex_w, ex_h))
	HudStyle.place(_exclamations[1], Rect2(hint_w + 10, (24 - ex_h) / 2.0, ex_w, ex_h))
	y += 24 + 20
	# .scenario-options-section (Margin-Top 20): centred row of 223x35 buttons with Margin 10, caption above
	y += 20
	var visible_options := []
	for o in _options:
		if o[0].visible:
			visible_options.append(o)
	var row_w: float = visible_options.size() * (223.0 + 20.0)
	var ox := cx - row_w / 2.0
	for o in visible_options:
		var button: TextureRect = o[0]
		HudStyle.place(button, Rect2(ox + 10, y + 10, 223, 35))
		var text: Label = o[1]   # .text Size text 100%, centred; with-icon shifted by 35ch
		text.add_theme_font_size_override("font_size", 20)
		var tw: float = ceil(text.get_theme_font("font").get_string_size(text.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x)
		var tx := (223.0 - tw) / 2.0 + (0.35 * 29.0 if o[3] != null else 0.0)
		HudStyle.place(text, Rect2(tx, 3, tw, 29))
		if o[3] != null:   # .league-icon Size auto 100%, right edge on the text's left
			var lh := 29.0
			var lw: float = lh * o[3].texture.get_width() / o[3].texture.get_height()
			HudStyle.place(o[3], Rect2(-lw, 0, lw, lh))
		var caption: Label = o[2]   # .caption Size 100% 60%, bottom at the button's padding-box top
		HudStyle.place(caption, Rect2(0, -0.6 * 29.0, 223, 0.6 * 29.0))
		caption.add_theme_font_size_override("font_size", 16)
		ox += 223.0 + 20.0
	# .scenario-team: 75vw x 148 centred, Position 0 -5% (of the content height); .teamlist 65 % wide, row 64 high
	var team := Rect2(cx - 0.375 * w, content.get_center().y - 0.05 * content.size.y - 74, 0.75 * w, 148)
	var list_w := 0.65 * team.size.x
	var row := Rect2(team.position.x + (team.size.x - list_w) / 2.0 + 5, team.get_center().y - 32, list_w - 10, 64)
	var rh := row.size.y
	# .member-wrapper Stackpartitioning 100% 383: the deck takes 383 px on the right, the member the rest
	var deck_w := 383.0
	var member := Rect2(row.position, Vector2(row.size.x - deck_w, rh))
	HudStyle.place(_member_frame, Rect2(member.position, Vector2(rh, rh)))   # .player-icon Size auto 100%
	var mi := 0.69 * rh
	HudStyle.place(_member_icon, Rect2((rh - mi) / 2.0, (rh - mi) / 2.0, mi, mi))
	# .name: Position-X 5, Padding-Left 100ch (= the row height), Fontsize 40%
	HudStyle.place(_member_name, Rect2(member.position.x + 5 + rh, member.position.y, member.size.x - rh - 5, rh))
	_member_name.add_theme_font_size_override("font_size", int(0.4 * rh))
	HudStyle.place(_member_leader, Rect2(member.position.x + 5 + rh, member.end.y - 0.3 * rh, member.size.x - rh - 5, 0.3 * rh))
	_member_leader.add_theme_font_size_override("font_size", int(0.3 * rh))
	# .deck: Deckslot.png (366x71) at the row height, icon 69 % at 50ph from the left, name, league icon right
	var dw: float = rh * _deck.texture.get_width() / _deck.texture.get_height()
	HudStyle.place(_deck, Rect2(row.end.x - dw, row.position.y, dw, rh))
	var di := 0.69 * rh
	HudStyle.place(_deck_icon, Rect2(0.5 * rh - di / 2.0, (rh - di) / 2.0, di, di))
	var info := Rect2(1.1 * rh + 0.2 * rh, 0.21 * rh, dw - 1.3 * rh - 0.1 * rh, rh - 0.42 * rh)   # .info Margin 21ch 10ch 21ch 110ch, Padding-Left 20ch
	var li: float = info.size.y * _deck_league.texture.get_width() / _deck_league.texture.get_height()
	HudStyle.place(_deck_league, Rect2(info.end.x - li, info.position.y, li, info.size.y))
	HudStyle.place(_deck_name, Rect2(info.position, Vector2(info.size.x - info.size.y, info.size.y)))   # Margin-Right 100ch
	_deck_name.add_theme_font_size_override("font_size", int(0.59 * info.size.y))
	HudStyle.fit(_deck_name, int(0.59 * info.size.y))
	# .selected-deck banner: bottom on the list's top, Position 5.2% 0, Size auto 100bh
	var bnh := float(_deck_banner.texture.get_height())
	var bnw := float(_deck_banner.texture.get_width())
	HudStyle.place(_deck_banner, Rect2(row.position.x - 5 + 0.052 * list_w, row.position.y - 5 - bnh, bnw, bnh))
	HudStyle.place(_deck_banner_text, Rect2(0.1 * bnw, 0.1 * bnh, 0.8 * bnw, 0.6 * bnh))   # Padding 10% 10% 30% 10%
	# .scenario-queue: 80vw x 30 at the bottom (Position 0 -10%); .btn-queue auto x 70, bottom -4%
	var queue_bottom := content.end.y - 0.1 * content.size.y
	var sh := 70.0
	var sw: float = sh * _start.texture.get_width() / _start.texture.get_height()
	HudStyle.place(_start, Rect2(cx - sw / 2.0, queue_bottom - 30 + 0.04 * 30 - sh, sw, sh))
	HudStyle.place(_start_label, Rect2(0.15 * sw, 0.17 * sh, 0.7 * sw, sh * (1.0 - 0.17 - 0.29)))   # btn-xl Padding 17% 15% 29% 15%
	# .btn-tutorial-videos: left edge, 92 % down the padding box, art size
	var gh := float(_guides.texture.get_height())
	var gw := float(_guides.texture.get_width())
	HudStyle.place(_guides, Rect2(content.position.x, content.position.y + 0.92 * content.size.y - gh / 2.0, gw, gh))
	HudStyle.place(_guides.get_child(0), Rect2(0.08 * gw, 0.1 * gh, gw * (1.0 - 0.08 - 0.11), 0.8 * gh))
