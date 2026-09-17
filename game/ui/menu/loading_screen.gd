class_name LoadingScreen
extends Control
## The in-match loading screen (Graphics/GUI/LoadingScreen.dui, loading.scss, tutorial.scss), shown by
## TGameStateLoadCoreGame (BaseConflict.Classes.Gamestates.pas:3123-3296) while the match assets load:
## the background art with the progress bar and the loading-state text at the bottom, above it either the
## match display (both teams' players with their decks around the VS icon) for the first MATCH_TIME seconds
## or the tutorial slides (one per SLIDE_TIME seconds, starting at a random slide; the tutorial scenario starts
## with slide 1 right away). The screen stays for at least MINIMUM_LOADING_TIME seconds and the bar never
## goes faster than that; the first match of the session also shows the first-time hint above the bar.
##
## Layout rules per docs/lobby.md section 3: `%` positions/sizes are of the parent's content rect, `auto`
## keeps the art's aspect, the engine's default FontSize is 24 (Engine.GUI.pas:5926), Padding `%` on the top
## and bottom edges is of the element's height (the 32 px bar fill confirms it).

const SLIDE_TIME := 5.0                # TGameStateLoadCoreGame.SLIDE_TIME
const MATCH_TIME := 10.0               # TGameStateLoadCoreGame.MATCH_TIME
const MINIMUM_LOADING_TIME := MATCH_TIME
const TUTORIAL_SLIDE_COUNT := 5        # BaseConflict.Constants.Client.pas:40
const ASSET_CATEGORIES := ["acUnknown", "acModel", "acTexture", "acXMLFile", "acScriptFile", "acParticleEffect", "acShader"]
const FONT_DEFAULT := Dashboard.FONT_DEFAULT
const FONT_GOLD := Color(0xEE / 255.0, 0xF4 / 255.0, 0xAD / 255.0, 1.0)   # $font-color-gold
const ROW_HEIGHT := 200.0              # .match stack > * Size 100% 200
const ROW_PADDING := 35.0              # Padding 35 0 35 0
const SLIDE_HEIGHT := 655.0            # .tutorial-slide Size auto 655

## Set before adding to the tree.
var players: Array = []                # [{username, team_id, deckname, deck_icon}] (RGameFoundData.players)
var first_loading := true              # FirstLoading: true until the first match of the session was loaded
var tutorial := false                  # HScenario.IsTutorial(scenario_uid): hint stage from the start
var loader_progress := 1.0             # FAssetPreloader.Progress (the sandbox scene is preloaded: done)

var progress := 0.0                    # Progress
var stage_match := true                # Stage = lsMatch (else lsHint)
var slide_index := 0                   # SlideIndex
var done := false                      # EnterCore condition reached

var _elapsed := 0.0                    # FLoadingTime in seconds (stage/slide clock)
var _minimum_elapsed := 0.0            # FMinimumLoadingTime in seconds
var _slide_offset := 0
var _background: TextureRect
var _bar_frame: TextureRect
var _bar_clip: Control
var _bar_fill: TextureRect
var _state: Label
var _first_time_hint: Label
var _match: Control
var _rows: Array = []                  # [row Control, team_id, username Label, deck TextureRect, icon, name Label]
var _vs: TextureRect
var _tutorial: Control
var _slide: TextureRect
var _logo: TextureRect
var _slide_text: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_slide_offset = randi() % TUTORIAL_SLIDE_COUNT
	slide_index = _slide_offset
	if tutorial:
		_slide_offset = 0
		slide_index = 1
		stage_match = false
		_elapsed = MATCH_TIME   # FLoadingTime.SetZeitDiffProzent(MATCH_TIME)
	_background = HudStyle.picture(HudStyle.tex("LoadingScreen/loadingscreen_background.jpg"), Rect2())
	add_child(_background)
	# progress.loading-progress: the bar art with the fill inside its padding box
	_bar_frame = HudStyle.picture(HudStyle.tex("LoadingScreen/loadingscreen_loading_bar.tga"), Rect2())
	_background.add_child(_bar_frame)
	_bar_clip = Control.new()
	_bar_clip.clip_contents = true
	_bar_clip.mouse_filter = MOUSE_FILTER_IGNORE
	_bar_frame.add_child(_bar_clip)
	_bar_fill = HudStyle.picture(HudStyle.tex("LoadingScreen/loadingscreen_loading_bar_fill.tga"), Rect2())
	_bar_clip.add_child(_bar_fill)
	_state = HudStyle.label(Lang.t("loading_initializing"), 24, FONT_DEFAULT, HudStyle.FONT_MEDIUM)
	_bar_frame.add_child(_state)
	_first_time_hint = HudStyle.label(Lang.t("loading_first_time_hint"), 24, FONT_DEFAULT, HudStyle.FONT_MEDIUM)
	_first_time_hint.visible = first_loading
	_bar_frame.add_child(_first_time_hint)
	# wrapper.match: one stack per team, the VS icon in the middle
	_match = Control.new()
	_match.mouse_filter = MOUSE_FILTER_IGNORE
	_background.add_child(_match)
	for p in players:
		var row := Control.new()
		row.mouse_filter = MOUSE_FILTER_IGNORE
		_match.add_child(row)
		var right: bool = int(p.get("team_id", 1)) == 2
		var username := HudStyle.label(str(p.get("username", "")), 24, FONT_GOLD, HudStyle.FONT_BOLD,
				HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT)
		row.add_child(username)
		var deck := HudStyle.picture(HudStyle.tex("MainMenu/Deckbuilding/Deckslot.png"), Rect2())
		row.add_child(deck)
		var icon_path: String = p.get("deck_icon", "")
		var icon := HudStyle.picture(HudStyle.tex(icon_path if icon_path != "" else "Shared/Icons/UnknownDeck.png"), Rect2())
		deck.add_child(icon)
		var deck_name := HudStyle.label(str(p.get("deckname", "")), 24, FONT_DEFAULT, HudStyle.FONT_MEDIUM, HORIZONTAL_ALIGNMENT_LEFT)
		deck.add_child(deck_name)
		_rows.append([row, int(p.get("team_id", 1)), username, deck, icon, deck_name])
	_vs = HudStyle.picture(HudStyle.tex("LoadingScreen/loadingscreen_vs.tga"), Rect2())
	_match.add_child(_vs)
	# wrapper.tutorial: the slide with the logo at its top and the caption below the centre
	_tutorial = Control.new()
	_tutorial.mouse_filter = MOUSE_FILTER_IGNORE
	_background.add_child(_tutorial)
	_slide = HudStyle.picture(HudStyle.tex("Shared/Tutorial/tut1.png"), Rect2())
	_tutorial.add_child(_slide)
	_logo = HudStyle.picture(HudStyle.tex("Shared/Logos/game_logo.png"), Rect2())
	_slide.add_child(_logo)
	_slide_text = HudStyle.label("", 24, FONT_DEFAULT, HudStyle.FONT_MEDIUM)
	_slide.add_child(_slide_text)
	get_viewport().size_changed.connect(_layout)
	_refresh()
	_layout()


func _process(delta: float) -> void:
	if done:
		return
	_elapsed += delta
	_minimum_elapsed += delta
	# TGameStateLoadCoreGame.Idle: match display for MATCH_TIME seconds, then the slides
	if stage_match and _elapsed < MATCH_TIME:
		slide_index = 0
	else:
		stage_match = false
		slide_index = maxi(0, (int(_elapsed - MATCH_TIME) / int(SLIDE_TIME) + _slide_offset) % TUTORIAL_SLIDE_COUNT) + 1
	var minimum_fraction := clampf(_minimum_elapsed / MINIMUM_LOADING_TIME, 0.0, 1.0)
	progress = maxf(progress, minf(loader_progress, minimum_fraction))
	# UpdateLoadingState: the category the preloader is at, "finalizing" when it is done
	if loader_progress >= 1.0:
		_state.text = Lang.t("loading_finalizing")
	else:
		var category: int = roundi(loader_progress * (ASSET_CATEGORIES.size() - 1))
		_state.text = Lang.t("loading_asset_type_" + ASSET_CATEGORIES[category].to_lower())
	done = loader_progress >= 1.0 and _minimum_elapsed >= MINIMUM_LOADING_TIME
	_refresh()


func _refresh() -> void:
	_match.visible = stage_match
	_tutorial.visible = not stage_match
	if not stage_match and slide_index >= 1:
		_slide.texture = HudStyle.tex("Shared/Tutorial/tut%d.png" % slide_index)
		_slide_text.text = Lang.t("loading_tutorial_text_%d" % slide_index)
	_bar_clip.size.x = progress * _bar_frame_content().size.x   # bar width = Progress * 100%


func _bar_frame_content() -> Rect2:   # padding box of the bar: Padding 25% 3% 24% 3% (top/bottom of the height)
	var s := _bar_frame.size
	return Rect2(0.03 * s.x, 0.25 * s.y, s.x - 0.06 * s.x, s.y - 0.25 * s.y - 0.24 * s.y)


func _layout() -> void:
	var view := MenuLayout.layout_size(self)
	size = view
	# .background: Size auto 100%, centred (the art is 16:9; every child is relative to it)
	var bh := view.y
	var bw: float = bh * _background.texture.get_width() / _background.texture.get_height()
	HudStyle.place(_background, Rect2((view.x - bw) / 2.0, 0, bw, bh))
	# .loading-progress: Size 36.33% auto, bottom at -5% of the background's bottom
	var fw := 0.3633 * bw
	var fh: float = fw * _bar_frame.texture.get_height() / _bar_frame.texture.get_width()
	HudStyle.place(_bar_frame, Rect2((bw - fw) / 2.0, bh - 0.05 * bh - fh, fw, fh))
	var content := _bar_frame_content()
	HudStyle.place(_bar_clip, Rect2(content.position, Vector2(progress * content.size.x, content.size.y)))
	HudStyle.place(_bar_fill, Rect2(0, 0, content.size.x, content.size.y))
	# .loading-state: top 30% below the bar, Size 100% 40%; .first-time-hint: bottom 90% above the bar, 100sw x 50%
	HudStyle.place(_state, Rect2(0, fh + 0.3 * fh, fw, 0.4 * fh))
	HudStyle.place(_first_time_hint, Rect2((fw - view.x) / 2.0, -0.9 * fh - 0.5 * fh, view.x, 0.5 * fh))
	# .match: stacks 25% wide centred at 25% / 75% x, 48% y; rows 200 high with 35 px padding top/bottom
	for team in [1, 2]:
		var rows := []
		for r in _rows:
			if r[1] == team:
				rows.append(r)
		var sw := 0.25 * bw
		var sh: float = rows.size() * ROW_HEIGHT
		var sx: float = (0.25 if team == 1 else 0.75) * bw - sw / 2.0
		var sy: float = 0.48 * bh - sh / 2.0
		for i in rows.size():
			var r: Array = rows[i]
			var row: Control = r[0]
			HudStyle.place(row, Rect2(sx, sy + i * ROW_HEIGHT, sw, ROW_HEIGHT))
			var ch := ROW_HEIGHT - 2 * ROW_PADDING   # the row's content rect
			var username: Label = r[2]
			HudStyle.place(username, Rect2(0, ROW_PADDING, sw, 0.4 * ch))
			HudStyle.fit(username, 24)
			# .deck: Position-Y 40%, Size auto 60%; the right stack's deck anchors top-right
			var deck: TextureRect = r[3]
			var dh := 0.6 * ch
			var dw: float = dh * deck.texture.get_width() / deck.texture.get_height()
			HudStyle.place(deck, Rect2(sw - dw if team == 2 else 0.0, ROW_PADDING + 0.4 * ch, dw, dh))
			# .icon 69% high centred at 50ph; .info Margin 21ch 10ch 21ch 110ch + Padding-Left 20ch, .name Margin-Right 100ch, font 59%
			var icon: TextureRect = r[4]
			var di := 0.69 * dh
			HudStyle.place(icon, Rect2(0.5 * dh - di / 2.0, (dh - di) / 2.0, di, di))
			var info := Rect2(1.3 * dh, 0.21 * dh, dw - 1.4 * dh, dh - 0.42 * dh)
			var deck_name: Label = r[5]
			HudStyle.place(deck_name, Rect2(info.position, Vector2(info.size.x - info.size.y, info.size.y)))
			HudStyle.fit(deck_name, int(0.59 * info.size.y))
	# .vs-icon: Size 7.214% auto, centred
	var vw := 0.07214 * bw
	var vh: float = vw * _vs.texture.get_height() / _vs.texture.get_width()
	HudStyle.place(_vs, Rect2((bw - vw) / 2.0, (bh - vh) / 2.0, vw, vh))
	# .tutorial-slide: Size auto 655 centred; .logo 40% wide, centre 3% below the slide's top; .text 100% x 5%, centre at -16.2%
	var slh := SLIDE_HEIGHT
	var slw: float = slh * _slide.texture.get_width() / _slide.texture.get_height()
	HudStyle.place(_slide, Rect2((bw - slw) / 2.0, (bh - slh) / 2.0, slw, slh))
	var lw := 0.4 * slw
	var lh: float = lw * _logo.texture.get_height() / _logo.texture.get_width()
	HudStyle.place(_logo, Rect2((slw - lw) / 2.0, 0.03 * slh - lh / 2.0, lw, lh))
	HudStyle.place(_slide_text, Rect2(0, slh / 2.0 - 0.162 * slh - 0.025 * slh, slw, 0.05 * slh))
