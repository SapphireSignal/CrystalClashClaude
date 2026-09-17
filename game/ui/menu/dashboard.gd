class_name Dashboard
extends Control
## The main menu's start page (MainMenu/Dashboard/Dashboard.dui, dashboard.scss): header art, players-online
## line and the announcement box on the left, a divider, and the news tiles on the right. The dashboard sits in
## `.main-content` (Padding-Top $navbar-size) with `Padding : 20`. Server-fed content (players online, the
## announcement, the Scill banner index, the patch-notes date) has no master server here: the values come from
## MainMenu.SERVER_STATE. Tile clicks open the original client's websites (TGameStateManager.BrowseTo).

const PADDING := 20.0
const NAVBAR_SIZE := 54.0                # .main-content Padding : $navbar-size 0 0 0
const FONT_DEFAULT := Color(0xA9 / 255.0, 0xDC / 255.0, 0xE7 / 255.0, 1.0)   # root Fontcolor
const TILE_BACKGROUND := Color(0x17 / 255.0, 0x3F / 255.0, 0x48 / 255.0, 0x80 / 255.0)   # .news-tile $80173F48
const TILE_BORDER := Color(0x5c / 255.0, 0x89 / 255.0, 0x89 / 255.0, 1.0)   # $frame-border 2 $border-cyan
const TILE_HOVER_OVERLAY := Color(1.0, 1.0, 1.0, 0x10 / 255.0)             # .banner:hover .icon override
const STATE_TILE := Color(0x23 / 255.0, 0x6F / 255.0, 0x7E / 255.0, 0xAF / 255.0)          # $AF236F7E
const STATE_TILE_HEADER := Color(0x1D / 255.0, 0x4D / 255.0, 0x57 / 255.0, 0xAF / 255.0)   # $AF1D4D57
const DIVIDER := Color(0x1C / 255.0, 0x2A / 255.0, 0x2B / 255.0, 1.0)      # $FF1C2A2B
const URL_YOUTUBE := "https://www.youtube.com/c/Riseoflegions"
const URL_TWITTER := "https://twitter.com/Rise_Of_Legions"
const URL_FACEBOOK := "https://www.facebook.com/RiseOfLegions/"
const URL_SCILL := "https://bit.ly/3cZdar4"
const URL_SCILL_TOURNAMENT := "https://app.scillplay.com/games/522523512784945154/tournaments"
const URL_STEAM_CHAT := "https://s.team/chat/LCJy43S0"
const URL_DISCORD := "https://discordapp.com/invite/yZvpPBT"
const URL_PATCH_NOTES := "http://riseoflegions.com/patch-notes"

var server_state: Dictionary
var _header: TextureRect
var _players_online: Label
var _announcement: Control
var _announcement_title: Label
var _announcement_text: Label
var _social: NewsTile
var _social_icons: Array = []
var _divider: ColorRect
var _tiles: Array = []   # right column, top to bottom


## `.news-tile`: $frame (2 px cyan border, only while hovered and enabled), translucent background, Padding 10.
class NewsTile extends Control:
	var fixed_height: float
	var padding := 10.0
	var banner := false
	var enabled := true
	var hovered := false
	var url := ""
	var icon: TextureRect
	var title: Label
	var caption: Label

	func _init(h: float) -> void:
		fixed_height = h
		clip_contents = true
		mouse_filter = MOUSE_FILTER_STOP
		mouse_entered.connect(func(): hovered = true; _restyle())
		mouse_exited.connect(func(): hovered = false; _restyle())
		gui_input.connect(func(ev: InputEvent):
			if enabled and url != "" and ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				OS.shell_open(url))

	func _restyle() -> void:
		queue_redraw()
		if caption != null:   # &:enabled:hover .caption FontColor real white
			caption.add_theme_color_override("font_color", Color.WHITE if hovered and enabled else Dashboard.FONT_DEFAULT)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Dashboard.TILE_BACKGROUND)
		if hovered and enabled:   # BorderSides all four while hovered
			draw_rect(Rect2(Vector2.ZERO, size), Dashboard.TILE_BORDER, false, 2.0)
			if banner:
				draw_rect(Rect2(Vector2.ZERO, size), Dashboard.TILE_HOVER_OVERLAY)


func _init(state: Dictionary) -> void:
	server_state = state


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_header = HudStyle.picture(HudStyle.tex("MainMenu/Dashboard/Header.png"), Rect2())
	add_child(_header)
	_players_online = HudStyle.label(Lang.t("misc_players_online") % int(server_state.get("players_online", 0)), 24, FONT_DEFAULT, HudStyle.FONT_MEDIUM)
	add_child(_players_online)
	_announcement = HudStyle.rect(STATE_TILE, Rect2())
	add_child(_announcement)
	var title_back := HudStyle.rect(STATE_TILE_HEADER, Rect2())
	_announcement.add_child(title_back)
	_announcement_title = HudStyle.label(str(server_state.get("dashboard_headline", "")), 24, FONT_DEFAULT, HudStyle.FONT_MEDIUM)
	_announcement.add_child(_announcement_title)
	_announcement_text = HudStyle.label(str(server_state.get("dashboard_text", "")), 16, FONT_DEFAULT, HudStyle.FONT_MEDIUM, HORIZONTAL_ALIGNMENT_LEFT)
	_announcement_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_announcement_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_announcement.add_child(_announcement_text)
	# .left .news-tile (:enabled="False"): the social icons, each clickable on its own
	_social = NewsTile.new(56.0)
	_social.enabled = false
	add_child(_social)
	for entry in [["youtubeLink.png", URL_YOUTUBE], ["TwitterLink.png", URL_TWITTER], ["facebookLink.png", URL_FACEBOOK]]:
		var pic := HudStyle.picture(HudStyle.tex("MainMenu/Dashboard/" + entry[0]), Rect2())
		pic.mouse_filter = MOUSE_FILTER_STOP
		var url: String = entry[1]
		pic.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				OS.shell_open(url))
		pic.mouse_entered.connect(func(): pic.scale = Vector2(1.1, 1.1))   # &:hover Transform scale(1.1)
		pic.mouse_exited.connect(func(): pic.scale = Vector2.ONE)
		_social.add_child(pic)
		_social_icons.append(pic)
	_divider = HudStyle.rect(DIVIDER, Rect2())
	add_child(_divider)
	# .right: vertical stack of tiles
	var banner := _tile(173.0, "MainMenu/Dashboard/scill_banner_%d.png" % int(server_state.get("scill_banner_index", 0)), "", "", URL_SCILL)
	banner.banner = true
	banner.padding = 0.0
	var single := _tile(82.0, "MainMenu/Dashboard/scill_tournaments.png", "", "", URL_SCILL_TOURNAMENT)
	single.banner = true
	single.padding = 0.0
	_tile(80.0, "MainMenu/Dashboard/SteamLogo.png", "", Lang.t("home_steam_chat_text"), URL_STEAM_CHAT)
	_tile(80.0, "MainMenu/Dashboard/DiscordLogo.tga", "", Lang.t("home_discord_text"), URL_DISCORD)
	_tile(80.0, "", "%s %s" % [Lang.t("home_patch_notes_title"), str(server_state.get("latest_patch_notes", ""))],
			Lang.t("home_patch_notes_text"), URL_PATCH_NOTES)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _tile(h: float, icon_path: String, title: String, caption: String, url: String) -> NewsTile:
	var t := NewsTile.new(h)
	t.url = url
	if icon_path != "":
		t.icon = HudStyle.picture(HudStyle.tex(icon_path), Rect2())
		t.add_child(t.icon)
	if title != "":
		t.title = HudStyle.label(title, 24, FONT_DEFAULT, HudStyle.FONT_MEDIUM)
		t.add_child(t.title)
	if caption != "":
		t.caption = HudStyle.label(caption, 16, FONT_DEFAULT, HudStyle.FONT_MEDIUM)
		t.add_child(t.caption)
	add_child(t)
	_tiles.append(t)
	return t


func _layout() -> void:
	var view := MenuLayout.layout_size(self)
	size = view
	var content := Rect2(PADDING, NAVBAR_SIZE + PADDING, view.x - 2 * PADDING, view.y - NAVBAR_SIZE - 2 * PADDING)
	var left := Rect2(content.position, Vector2(0.57 * content.size.x, content.size.y))
	# .title-image: Position 0 -7, Size 100bw auto (the art's native size)
	HudStyle.place(_header, Rect2(left.position + Vector2(0, -7), _header.texture.get_size()))
	# .players-online: Anchor caCenter / ParentAnchor caTop, Position 0 72.2%, Size 100% 3.5%, FontSize 100%
	var po_h := 0.035 * left.size.y
	HudStyle.place(_players_online, Rect2(left.position.x, left.position.y + 0.722 * left.size.y - po_h / 2.0, left.size.x, po_h))
	_players_online.add_theme_font_size_override("font_size", int(po_h))
	# .beta-announcement: Position 0 72%, Size 100% 20.2%, BoxSizing bsMargin + Margin 20
	var ann := Rect2(left.position.x + 20, left.position.y + 0.72 * left.size.y + 20, left.size.x - 40, 0.202 * left.size.y - 40)
	HudStyle.place(_announcement, ann)
	var title_h := 0.45 * ann.size.y   # .title Size 100% 45%, Padding 4 6
	HudStyle.place(_announcement.get_child(0), Rect2(0, 0, ann.size.x, title_h))
	HudStyle.place(_announcement_title, Rect2(6, 4, ann.size.x - 12, title_h - 8))
	_announcement_title.add_theme_font_size_override("font_size", int(title_h - 8))
	HudStyle.place(_announcement_text, Rect2(7, title_h + 7, ann.size.x - 14, ann.size.y - title_h - 14))   # .text Padding 7
	# social .news-tile: Position 0 90.5%, Size-Y 56, Margin 0 21 (bsMargin)
	var social := Rect2(left.position.x + 21, left.position.y + 0.905 * left.size.y, left.size.x - 42, 56)
	HudStyle.place(_social, social)
	var icon_h := 0.9 * (social.size.y - 2 * _social.padding)   # stack.icon > *: Size auto 90%, Position-Y 5%, Margin-Left 10
	var ix := _social.padding
	for pic in _social_icons:
		ix += 10.0
		var iw: float = icon_h * pic.texture.get_width() / pic.texture.get_height()
		HudStyle.place(pic, Rect2(ix, _social.padding - 1 + 0.05 * (social.size.y - 2 * _social.padding), iw, icon_h))
		pic.pivot_offset = pic.size / 2.0
		ix += iw
	# .divider: Size 3 100% at 59 %
	HudStyle.place(_divider, Rect2(content.position.x + 0.59 * content.size.x, content.position.y, 3, content.size.y))
	# .right: Size 39% 100%, Position 61% 0; tiles Size 100% <h>, Margin-Bottom 10
	var right := Rect2(content.position.x + 0.61 * content.size.x, content.position.y, 0.39 * content.size.x, content.size.y)
	var y := right.position.y
	for t in _tiles:
		HudStyle.place(t, Rect2(right.position.x, y, right.size.x, t.fixed_height))
		var inner := Rect2(t.padding, t.padding, right.size.x - 2 * t.padding, t.fixed_height - 2 * t.padding)
		if t.banner:   # .icon Size 100% auto at the top
			var bh: float = inner.size.x * t.icon.texture.get_height() / t.icon.texture.get_width()
			HudStyle.place(t.icon, Rect2(inner.position, Vector2(inner.size.x, bh)))
		else:
			var top_h := 0.6 * inner.size.y   # .icon, .title: Size auto 60% at the top, centred
			if t.icon != null:
				var iw: float = top_h * t.icon.texture.get_width() / t.icon.texture.get_height()
				HudStyle.place(t.icon, Rect2(inner.position.x + (inner.size.x - iw) / 2.0, inner.position.y, iw, top_h))
			if t.title != null:   # .title Size-X 100%, FontSize 100%
				HudStyle.place(t.title, Rect2(inner.position, Vector2(inner.size.x, top_h)))
				t.title.add_theme_font_size_override("font_size", int(top_h))
				HudStyle.fit(t.title, int(top_h))
			if t.caption != null:   # .caption: bottom, Size 100% 30%, FontSize 90%
				var ch := 0.3 * inner.size.y
				HudStyle.place(t.caption, Rect2(inner.position.x, inner.end.y - ch, inner.size.x, ch))
				t.caption.add_theme_font_size_override("font_size", int(0.9 * ch))
		y += t.fixed_height + 10.0
