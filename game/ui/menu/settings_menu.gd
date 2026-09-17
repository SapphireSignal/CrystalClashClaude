class_name SettingsMenu
extends Control
## The settings dialog (SettingsMenu.dui + SettingsMenu/*.dui, settings.scss, _common.scss `.window`/`.backdrop`):
## a blurred backdrop with the 800x580 window, the category column (Menu: Graphics/Sound, In game: Graphics/Sound/
## Interface/Keybindings) and the chosen category's rows in the `.column` (check boxes on Checkbox.tga, form-control
## selects with their option list, progress sliders, captions). Save = TGameStateComponentSettings.
## DeactivateAndSaveSettings, Cancel / backdrop click = DeactivateAndDiscardSettings (the snapshot taken on open).
##
## Built: the Gameplay ("Interface"), Sound and Graphics categories. Not built: the two Menu categories (they need the
## menu's own mixer and resolution; darkened like the original does in a match), the Keybindings rows and dialog.

signal closed

enum Category { MENU, SOUND_META, GRAPHICS, SOUND, GAMEPLAY, KEYBINDING }   # EnumOptionType subset used by the dialog

const WINDOW := Vector2(800, 580)
const FRAME_INSET := 12.0            # $frame padding 2 + border 2 (drawn inside) + window padding 10 (x)
const FRAME_INSET_Y := 32.0          # ... + window padding 30 (y)
const BACKDROP := Color(0x08 / 255.0, 0x0D / 255.0, 0x0D / 255.0, 0xA0 / 255.0)   # $background-backdrop
const WINDOW_BG := Color(0x32 / 255.0, 0x4B / 255.0, 0x50 / 255.0, 1.0)            # $window-background
const BORDER_CYAN := Color(0x5C / 255.0, 0x89 / 255.0, 0x89 / 255.0, 1.0)          # $border-cyan
const SHADOW := Color(0, 0, 0, 0x40 / 255.0)                                        # $shadow-outline 3 px
const FIELD_BG := Color(0x27 / 255.0, 0x3A / 255.0, 0x3C / 255.0, 1.0)             # $field-background
const HIGHLIGHT_CYAN := Color(0x59 / 255.0, 0xDC / 255.0, 0xE2 / 255.0, 1.0)       # $highlight-cyan
const FONT_DEFAULT := Color(0xA9 / 255.0, 0xDC / 255.0, 0xE7 / 255.0, 1.0)         # $font-color-default
const FONT_CRYSTAL := Color(0x83 / 255.0, 0xFF / 255.0, 0xFF / 255.0, 1.0)         # $font-color-crystal
const FONT_HIGHLIGHT := Color(0xD6 / 255.0, 0xF5 / 255.0, 0xF5 / 255.0, 1.0)       # $font-color-highlight
const FONT_WHITE := Color(1, 1, 1, 1)                                               # $font-color-real-white
const PROGRESS_BAR := Color(0x23 / 255.0, 0x91 / 255.0, 0x91 / 255.0, 1.0)         # progress bar $FF239191
const ROW_H := 22.0                  # .column > * Size inherit 22
const ROW_PITCH := 26.0              # ... margin 2 0 2 0
const COLUMN_W := 320.0
const BUTTON_W := 155.0              # button_xl.tga is 155x58: `auto 58`
const BUTTON_H := 58.0

var category: int = Category.GRAPHICS
var in_game := true                  # `hud. <> nil`: the Menu categories are disabled in a match

var _window: Control
var _blur: ColorRect
var _tint: ColorRect
var _category_rows: Array = []       # [{category, control, label, headline}]
var _pages: Dictionary = {}          # Category -> Control
var _rows: Array = []                # every widget with a refresh() (Sync)
var _dropdown: Control = null        # the open select's option list, drawn last


class Check extends Control:
	## `<check>`: Checkbox.tga (72x72, `brAuto brStretch` = square of the row height) at the left, the text after
	## `Padding-Left 120ch`; `:down` (checked) and hover art variants.
	var getter: Callable
	var setter: Callable
	var checked := false
	var hovered := false
	var deactivated := false
	var secret := false              # `.secret`: Opacity 0.01 unless checked
	var art: TextureRect
	var label: Label

	func _init(text: String, hint: String, get_value: Callable, set_value: Callable) -> void:
		getter = get_value
		setter = set_value
		mouse_filter = MOUSE_FILTER_STOP
		tooltip_text = hint
		art = HudStyle.picture(HudStyle.tex("Shared/Checkbox.tga"), Rect2(0, 0, ROW_H, ROW_H))
		add_child(art)
		label = HudStyle.label(text, 18, FONT_DEFAULT, HudStyle.FONT_REGULAR, HORIZONTAL_ALIGNMENT_LEFT)
		HudStyle.place(label, Rect2(ROW_H * 1.2, 0, COLUMN_W - ROW_H * 1.2, ROW_H))
		add_child(label)
		mouse_entered.connect(func(): hovered = true; refresh())
		mouse_exited.connect(func(): hovered = false; refresh())
		gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and not deactivated:
				setter.call(not checked)
				refresh())

	func refresh() -> void:
		checked = getter.call()
		var file := "Checkbox%s%s.tga" % ["Down" if checked else "", "Hover" if hovered and not deactivated else ""]
		art.texture = HudStyle.tex("Shared/" + file)
		modulate.a = 0.55 if deactivated else (0.01 if secret and not checked else 1.0)


class Select extends Control:
	## `<select class="form-control">`: the $field-frame box (24 high, 28 for `.primary`) with the current option's
	## caption and the chevron; a click opens the option list below it (`:focus > .options`).
	var getter: Callable
	var setter: Callable
	var options: Array = []          # [[value, text]]
	var deactivated := false         # `.deactivated`: opacity 0.55, no input
	var caption: Label
	var arrow: Label
	var menu: SettingsMenu

	func _init(owner: SettingsMenu, entries: Array, get_value: Callable, set_value: Callable, height: float = 24.0) -> void:
		menu = owner
		options = entries
		getter = get_value
		setter = set_value
		mouse_filter = MOUSE_FILTER_STOP
		custom_minimum_size.y = height
		size.y = height
		var font_size := int(round(height * 0.7))   # $field-frame fontsize 70%
		caption = HudStyle.label("", font_size, FONT_DEFAULT, HudStyle.FONT_REGULAR, HORIZONTAL_ALIGNMENT_LEFT)
		caption.clip_text = true
		HudStyle.place(caption, Rect2(6, 0, COLUMN_W - 6 - height, height))   # Padding 3 0 3 6, room for the arrow
		add_child(caption)
		arrow = HudStyle.label("v", int(round(height * 0.6)), FONT_DEFAULT, HudStyle.FONT_BOLD)
		arrow.modulate.a = 0.7
		HudStyle.place(arrow, Rect2(COLUMN_W - height, -1, height, height))
		add_child(arrow)
		mouse_entered.connect(func(): arrow.modulate.a = 1.0)
		mouse_exited.connect(func(): arrow.modulate.a = 0.7)
		gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and not deactivated:
				menu.open_dropdown(self))

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0x40 / 255.0))
		draw_rect(Rect2(Vector2.ZERO, size), BORDER_CYAN, false, 1.0)

	func refresh() -> void:
		modulate.a = 0.55 if deactivated else 1.0
		var value: int = getter.call()
		for o in options:
			if o[0] == value:
				caption.text = o[1]
				return
		caption.text = ""

	func choose(value: int) -> void:
		setter.call(value)
		menu.refresh()


class VolumeBar extends Control:
	## `<progress dxml-on:change=...>` with `<bar width="N%">`: the 0..100 value as the filled fraction, a click or
	## drag sets the value from the pointer's x.
	var getter: Callable
	var setter: Callable
	var value := 0
	var deactivated := false
	var dragging := false

	func _init(get_value: Callable, set_value: Callable) -> void:
		getter = get_value
		setter = set_value
		mouse_filter = MOUSE_FILTER_STOP
		gui_input.connect(func(ev: InputEvent):
			if deactivated:
				return
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
				dragging = ev.pressed
				if ev.pressed:
					_set_from(ev.position.x)
			elif ev is InputEventMouseMotion and dragging:
				_set_from(ev.position.x))

	func _set_from(x: float) -> void:
		setter.call(clampi(int(round(x / size.x * 100.0)), 0, 100))
		refresh()

	func refresh() -> void:
		value = getter.call()
		modulate.a = 0.55 if deactivated else 1.0
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(0, 0, size.x * value / 100.0, size.y), PROGRESS_BAR)


class XlButton extends TextureRect:
	## `btn.btn-xl`: button_xl[_success|_danger][_hover].tga with the $big-font caption in its padding box
	## (17% 15% 29% 15%).
	signal pressed
	var variant: String
	var label: Label

	func _init(text: String, kind: String = "") -> void:
		variant = kind
		expand_mode = EXPAND_IGNORE_SIZE
		stretch_mode = STRETCH_SCALE
		mouse_filter = MOUSE_FILTER_STOP
		_set_art(false)
		size = Vector2(BUTTON_W, BUTTON_H)
		label = HudStyle.label(text, 24, HudStyle.WHITE, HudStyle.FONT_EXTRABOLD)
		HudStyle.place(label, Rect2(BUTTON_W * 0.15, BUTTON_H * 0.17, BUTTON_W * 0.7, BUTTON_H * 0.54))
		HudStyle.fit(label, 24)
		add_child(label)
		mouse_entered.connect(func(): _set_art(true))
		mouse_exited.connect(func(): _set_art(false))
		gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				accept_event()
				pressed.emit())

	func _set_art(hover: bool) -> void:
		texture = HudStyle.tex("Shared/button_xl%s%s.tga" % [variant, "_hover" if hover else ""])


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP   # .backdrop MouseEvents meAll; a click outside the window discards
	gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if _dropdown != null:
				close_dropdown()
			else:
				discard())
	ClientSettings.save_snapshot()   # OnDialogOpen: Settings.SaveSnapshot
	category = Category.GRAPHICS if in_game else Category.MENU
	_blur = HudStyle.blur(Rect2(), Color.WHITE)   # .backdrop Blur : True, BlurColor $FFFFFFFF; $background-backdrop tint in _draw
	add_child(_blur)
	_tint = HudStyle.rect(BACKDROP, Rect2())   # children draw above _draw: the tint is its own node
	add_child(_tint)
	_window = Control.new()
	_window.mouse_filter = MOUSE_FILTER_STOP
	_window.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and _dropdown != null:
			close_dropdown())
	_window.draw.connect(_draw_window)
	_window.size = WINDOW
	add_child(_window)
	_build_caption()
	_build_menu()
	_build_pages()
	_build_buttons()
	get_viewport().size_changed.connect(_layout)
	_layout()
	refresh()


func _draw_window() -> void:
	var r := Rect2(Vector2.ZERO, WINDOW)
	_window.draw_rect(r.grow(3), SHADOW)                       # Outline 3 $40000000
	_window.draw_rect(r, WINDOW_BG)
	_window.draw_rect(r.grow(-1), BORDER_CYAN, false, 2.0)     # Border 2 $border-cyan inside the box
	# .menu: 30 % wide column with BackgroundColor $40000000
	_window.draw_rect(_content_rect().grow_individual(0, 0, -_content_rect().size.x * 0.7, 0), Color(0, 0, 0, 0.25))


func _content_rect() -> Rect2:
	return Rect2(FRAME_INSET, FRAME_INSET_Y, WINDOW.x - 2 * FRAME_INSET, WINDOW.y - 2 * FRAME_INSET_Y)


func _layout() -> void:
	var view := MenuLayout.layout_size(self)
	size = view
	_blur.size = view
	_tint.size = view
	_window.position = ((view - WINDOW) / 2.0).floor()
	queue_redraw()


func _build_caption() -> void:
	# .window-caption: dialog_header.tga (370x53) centred on the window's top edge, 35 px up; text in its padding
	# box (20% 5% 28% 5%), bold, auto-shrunk.
	var header := HudStyle.picture(HudStyle.tex("Shared/dialog_header.tga"), Rect2((WINDOW.x - 370) / 2.0, -35 - 53 / 2.0, 370, 53))
	_window.add_child(header)
	var text := HudStyle.label(Lang.t("settings_caption"), 22, HudStyle.WHITE, HudStyle.FONT_BOLD)
	HudStyle.place(text, Rect2(370 * 0.05, 53 * 0.2, 370 * 0.9, 53 * 0.52))
	header.add_child(text)


func _build_menu() -> void:
	# .menu .categories: the vertical stack starts below the menu's Padding 20; headline 70 (bsMargin, Margin 5),
	# category 50 + Margin 0 5 5 5, divider 10.
	var menu_rect := _content_rect()
	menu_rect.size.x *= 0.3
	var x := menu_rect.position.x
	var w := menu_rect.size.x
	var y := menu_rect.position.y + 20.0
	var entries := [
		["headline", "settings_menu_category_descriptor_menu", [Category.MENU, Category.SOUND_META]],
		["category", "settings_menu_category_graphics", Category.MENU],
		["category", "settings_menu_category_sound", Category.SOUND_META],
		["divider"],
		["headline", "settings_menu_category_descriptor_ingame", [Category.GRAPHICS, Category.SOUND, Category.GAMEPLAY, Category.KEYBINDING]],
		["category", "settings_menu_category_graphics", Category.GRAPHICS],
		["category", "settings_menu_category_sound", Category.SOUND],
		["category", "settings_menu_category_gameplay", Category.GAMEPLAY],
		["category", "settings_menu_category_keybinding", Category.KEYBINDING],
	]
	for e in entries:
		match e[0]:
			"divider":
				y += 10.0
			"headline":
				var row := Control.new()
				row.mouse_filter = MOUSE_FILTER_IGNORE
				HudStyle.place(row, Rect2(x + 5, y + 5, w - 10, 60))
				_window.add_child(row)
				var label := HudStyle.label(Lang.t(e[1]), 26, FONT_CRYSTAL, HudStyle.FONT_BOLD, HORIZONTAL_ALIGNMENT_LEFT)
				HudStyle.place(label, Rect2(15, 0, w - 25, 60))
				row.add_child(label)
				_category_rows.append({"categories": e[2], "control": row, "label": label, "headline": true, "hovered": false})
				row.draw.connect(_draw_category_row.bind(_category_rows.back()))
				y += 70.0
			"category":
				var row := Control.new()
				row.mouse_filter = MOUSE_FILTER_STOP
				HudStyle.place(row, Rect2(x + 5, y, w - 10, 50))
				_window.add_child(row)
				var label := HudStyle.label(Lang.t(e[1]), 28, FONT_DEFAULT, HudStyle.FONT_BOLD, HORIZONTAL_ALIGNMENT_LEFT)
				HudStyle.place(label, Rect2(15, 0, w - 25, 50))
				row.add_child(label)
				var entry := {"categories": [e[2]], "control": row, "label": label, "headline": false, "hovered": false}
				_category_rows.append(entry)
				row.draw.connect(_draw_category_row.bind(entry))
				row.mouse_entered.connect(func(): entry["hovered"] = true; row.queue_redraw())
				row.mouse_exited.connect(func(): entry["hovered"] = false; row.queue_redraw())
				row.gui_input.connect(func(ev: InputEvent):
					if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
						accept_event()
						if _enabled(e[2]):
							set_category(e[2]))
				y += 55.0


func _enabled(cat: int) -> bool:
	return not in_game or (cat != Category.MENU and cat != Category.SOUND_META)


func _draw_category_row(entry: Dictionary) -> void:
	var row: Control = entry["control"]
	var r := Rect2(Vector2.ZERO, row.size)
	var selected: bool = entry["categories"].has(category)
	if entry["headline"]:
		if selected:
			row.draw_rect(r, Color(HIGHLIGHT_CYAN, 0.1))
		entry["label"].add_theme_color_override("font_color", FONT_HIGHLIGHT if selected else FONT_CRYSTAL)
		return
	var enabled := _enabled(entry["categories"][0])
	if selected:
		row.draw_rect(r, Color(HIGHLIGHT_CYAN, 0.3))
		row.draw_rect(Rect2(0, 0, 5, r.size.y), HIGHLIGHT_CYAN)   # BorderSides [bsLeft], Border 5
	elif enabled and entry["hovered"]:
		row.draw_rect(r, Color(1, 1, 1, 0x30 / 255.0))
		row.draw_rect(Rect2(0, 0, 5, r.size.y), Color(1, 1, 1, 0x60 / 255.0))
	else:
		row.draw_rect(r, Color(0.5, 0.5, 0.5, 0x20 / 255.0))
	if not enabled:
		row.draw_rect(r, HudStyle.DARKEN)   # :disabled BackgroundColorOverride $override-darken


func set_category(cat: int) -> void:
	category = cat
	close_dropdown()
	for c in _pages:
		_pages[c].visible = c == cat
	for entry in _category_rows:
		entry["control"].queue_redraw()
	refresh()


func _build_pages() -> void:
	# .content: the right 70 %, Padding 0 15; the .column is 320 wide; the revert button sits bottom-right.
	var content := _content_rect()
	content.position.x += content.size.x * 0.3 + 15.0
	content.size.x = content.size.x * 0.7 - 30.0
	var builders := {
		Category.GAMEPLAY: _build_gameplay, Category.SOUND: _build_sound, Category.GRAPHICS: _build_graphics,
		Category.MENU: _build_menu_display, Category.SOUND_META: _build_menu_sound, Category.KEYBINDING: Callable(),
	}
	for cat: int in builders:
		var page := Control.new()
		page.mouse_filter = MOUSE_FILTER_IGNORE
		HudStyle.place(page, content)
		_window.add_child(page)
		_pages[cat] = page
		if builders[cat].is_valid():
			builders[cat].call(page)
			var revert := XlButton.new(Lang.t("revertsettings"))
			revert.position = Vector2(content.size.x - BUTTON_W, content.size.y - BUTTON_H)
			var revert_category: int = {Category.GAMEPLAY: ClientSettings.Category.GAMEPLAY, Category.SOUND: ClientSettings.Category.SOUND,
				Category.GRAPHICS: ClientSettings.Category.GRAPHICS, Category.MENU: ClientSettings.Category.MENU,
				Category.SOUND_META: ClientSettings.Category.SOUND_META}[cat]
			revert.pressed.connect(func():
				ClientSettings.revert_category(revert_category)
				if cat == Category.GRAPHICS:
					ClientSettings.revert_category(ClientSettings.Category.ENGINE)   # the shadow bias / display mode live there
				refresh())
			page.add_child(revert)


## Column helpers: each adds a row at `y` (top of the row's margin box) and returns the next y.

func _add(page: Control, widget: Control, y: float, height: float = ROW_H, indent: float = 0.0) -> float:
	HudStyle.place(widget, Rect2(indent, y + 2.0, COLUMN_W - indent, height))
	page.add_child(widget)
	if widget.has_method("refresh"):
		_rows.append(widget)
	return y + height + 4.0


func _text_row(page: Control, text: String, y: float, font_size: int, color: Color = FONT_DEFAULT, hint: String = "") -> float:
	var label := HudStyle.label(text, font_size, color, HudStyle.FONT_REGULAR, HORIZONTAL_ALIGNMENT_LEFT)
	if hint != "":
		label.mouse_filter = MOUSE_FILTER_STOP
		label.tooltip_text = hint
	return _add(page, label, y)


func _check(page: Control, key: String, hint_key: String, option: String, y: float, category_id: int = ClientSettings.Category.GAMEPLAY, indent: float = 0.0) -> float:
	var check := Check.new(Lang.t(key), Lang.t(hint_key) if hint_key != "" and Lang.has_key(hint_key) else "",
		func(): return ClientSettings.get_bool(category_id, option),
		func(v: bool): ClientSettings.set_bool(category_id, option, v); refresh())
	return _add(page, check, y, ROW_H, indent)


func _select(page: Control, prefix: String, names: Array, getter: Callable, setter: Callable, y: float, height: float = 24.0) -> float:
	var entries := []
	for i in names.size():
		entries.append([i, Lang.t(prefix + names[i])])
	return _add(page, Select.new(self, entries, getter, setter, height), y, height)


func _build_gameplay(page: Control) -> void:
	var y := 0.0
	y = _check(page, "settingsgameplaydragwavetemplates", "settingsgameplaydragwavetemplateshint", "DragWavetemplates", y)
	y = _check(page, "settingsgameplayendlessbuild", "settingsgameplayendlessbuildhint", "EndlessBuild", y)
	y = _check(page, "settingsgameplayclipcursor", "settingsgameplayclipcursorhint", "ClipCursor", y)
	y = _check(page, "settingsgameplayrightclickpanning", "settingsgameplayrightclickpanninghint", "RightClickPanning", y)
	y = _text_row(page, Lang.t("settings_gameplay_healthbarmode_caption"), y, 18)
	y = _select(page, "settings_gameplay_healthbarmode_", ["hmNone", "hmDamaged", "hmAlways"],
		ClientSettings.healthbar_mode, ClientSettings.set_healthbar_mode, y)
	y = _text_row(page, Lang.t("settings_gameplay_dropzonemode_caption"), y, 18)
	y = _select(page, "settings_gameplay_dropzonemode_", ["dzAll", "dzArea", "dzCursor", "dzHide"],
		ClientSettings.drop_zone_mode, ClientSettings.set_drop_zone_mode, y)
	y = _text_row(page, Lang.t("settings_gameplay_clickprecision_caption"), y, 18, FONT_DEFAULT, Lang.t("settings_gameplay_clickprecision_hint"))
	y = _select(page, "settings_gameplay_clickprecision_", ["cpPrecise", "cpExtended", "cpWide"],
		ClientSettings.click_precision, ClientSettings.set_click_precision, y)
	y = _check(page, "settingsgameplayshoweffectradius", "settingsgameplayshoweffectradiushint", "ShowEffectRadius", y)
	y = _check(page, "settings_gameplay_fixed_team_colors", "settings_gameplay_fixed_team_colors_hint", "FixedTeamColors", y)
	y = _check(page, "settings_gameplay_technical_panel", "settings_gameplay_technical_panel_hint", "ShowTechnicalPanel", y)
	y = _check(page, "settings_gameplay_cogameplayshownumericchargecooldown", "settings_cogameplayshownumericchargecooldown_hint", "ShowNumericChargeCooldown", y)
	y = _check(page, "settings_cogameplayshowdeckhotkeys", "settings_cogameplayshowdeckhotkeys_hint", "ShowDeckHotkeys", y)
	# `.secret` check (coGeneralHasSecretAccess): Opacity 0.01 unless checked; a leftover developer switch, kept.
	var secret := Check.new(Lang.t("settings_general_has_secret_access"), "",
		func(): return ClientSettings.get_bool(ClientSettings.Category.GENERAL, "HasSecretAccess"),
		func(v: bool): ClientSettings.set_bool(ClientSettings.Category.GENERAL, "HasSecretAccess", v); refresh())
	secret.secret = true
	_add(page, secret, y)


func _build_sound(page: Control) -> void:
	var y := 0.0
	var S := ClientSettings.Category.SOUND
	y = _text_row(page, Lang.t("settings_sound_caption"), y, 24, FONT_WHITE)
	y = _check(page, "settings_sound_check", "", "PlayMaster", y, S)
	y = _add(page, VolumeBar.new(func(): return ClientSettings.get_int(S, "MasterVolume"), func(v: int): ClientSettings.set_int(S, "MasterVolume", v)), y)
	y = _check(page, "settings_sound_background_check", "", "Background", y, S)
	# the nested stack (Padding-Left 35) gets `.deactivated` while the master is off
	var nested: Array = []
	for pair in [["settings_sound_music_check", "PlayMusic", "MusicVolume"], ["settings_sound_effect_check", "PlayEffects", "EffectVolume"],
			["settings_sound_ping_check", "PlayPings", "PingVolume"], ["settings_sound_gui_check", "PlayGUISound", "GUISoundVolume"]]:
		y = _check(page, pair[0], "", pair[1], y, S, 35.0)
		nested.append(_rows.back())
		var option: String = pair[2]
		y = _add(page, VolumeBar.new(func(): return ClientSettings.get_int(S, option), func(v: int): ClientSettings.set_int(S, option, v)), y, ROW_H, 35.0)
		nested.append(_rows.back())
	_rows.insert(_rows.size() - nested.size(), _Gate.new(func():
		var off := not ClientSettings.get_bool(S, "PlayMaster")
		for w in nested:
			w.deactivated = off))


class _Gate extends RefCounted:
	## A refresh hook without visuals, so dependent rows learn their `.deactivated` state before they refresh.
	var hook: Callable
	func _init(callable: Callable) -> void:
		hook = callable
	func refresh() -> void:
		hook.call()


func _build_graphics(page: Control) -> void:
	var y := 0.0
	var G := ClientSettings.Category.GRAPHICS
	y = _text_row(page, Lang.t("settings_graphics_display"), y, 24, FONT_WHITE)
	y = _text_row(page, Lang.t("settings_graphics_display_mode"), y, 18)
	y = _select(page, "settings_graphics_display_mode_", ["dmBorderlessFullscreenWindow", "dmWindowed"],
		ClientSettings.display_mode, ClientSettings.set_display_mode, y)
	y = _check(page, "settings_graphics_vsync", "settings_graphics_vsync_hint", "VSync", y, G)
	y += ROW_PITCH   # .spacer
	y = _text_row(page, Lang.t("settings_graphics_quality"), y, 24, FONT_WHITE)
	y = _select(page, "settings_graphics_quality_", ["gqVeryLow", "gqLow", "gqMedium", "gqHigh", "gqVeryHigh", "gqCustom"],
		ClientSettings.graphics_quality, ClientSettings.set_graphics_quality, y, 28.0)   # .primary Size-Y 28
	y += ROW_PITCH   # .spacer
	y = _check(page, "gui_settings_menu_graphics_deferred_shading", "", "DeferredShading", y, G)
	# .need-restart caption with the warning icon (Shared/warning.png, 70 % of the row, 5 px right of the text)
	var restart := HudStyle.label(Lang.t("settings_graphics_texture_quality"), 18, FONT_DEFAULT, HudStyle.FONT_REGULAR, HORIZONTAL_ALIGNMENT_LEFT)
	var text_w := restart.get_theme_font("font").get_string_size(restart.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var icon_h := ROW_H * 0.7
	var icon := HudStyle.picture(HudStyle.tex("Shared/warning.png"), Rect2(text_w + 5, (ROW_H - icon_h) / 2.0 - ROW_H * 0.08, icon_h * 21.0 / 18.0, icon_h))
	icon.mouse_filter = MOUSE_FILTER_STOP
	icon.tooltip_text = Lang.t("settings_need_restart_hint")
	restart.add_child(icon)
	y = _add(page, restart, y)
	y = _select(page, "settings_graphics_texture_quality_", ["tqMaximum", "tqHigh", "tqMedium", "tqLow", "tqMinimum"],
		ClientSettings.texture_quality, ClientSettings.set_texture_quality, y)
	y = _text_row(page, Lang.t("gui_settings_menu_graphics_shadows"), y, 18)
	y = _select(page, "gui_settings_menu_graphics_shadowmode_", ["sqoff", "sqverylow", "sqlow", "sqmedium", "sqhigh", "squltrahigh"],
		ClientSettings.shadow_quality, ClientSettings.set_shadow_quality, y)
	y = _check(page, "gui_settings_menu_graphics_fxaa", "", "PostEffectFXAA", y, G)
	y = _check(page, "gui_settings_menu_graphics_glow", "", "PostEffectGlow", y, G)
	y = _check(page, "gui_settings_menu_graphics_unsharp_masking", "", "PostEffectUnsharpMasking", y, G)
	y = _check(page, "gui_settings_menu_graphics_distortion", "", "PostEffectDistortion", y, G)
	y = _check(page, "gui_settings_menu_graphics_gui_blur", "", "GUIBlurBackgrounds", y, G)
	var deferred_only: Array = []
	y = _check(page, "gui_settings_menu_graphics_toon", "", "PostEffectToon", y, G)
	deferred_only.append(_rows.back())
	y = _check(page, "gui_settings_menu_graphics_ssao", "gui_settings_menu_graphics_experimental", "PostEffectSSAO", y, G)
	deferred_only.append(_rows.back())
	_rows.insert(_rows.size() - 2, _Gate.new(func():
		var off := not ClientSettings.get_bool(G, "DeferredShading")
		for w in deferred_only:
			w.deactivated = off))


## MenuSettings.dui (otMenu, listed as "Graphics" under the Menu headline): the client window's language and
## display options. The original ran the menu in its own 1280x720 client window; here they size the one window
## (`ClientSettings._apply_menu_window`). Only English is extracted, so the language list has one entry.
func _build_menu_display(page: Control) -> void:
	var y := 0.0
	var M := ClientSettings.Category.MENU
	y = _text_row(page, Lang.t("settings_menu_language"), y, 24, FONT_WHITE)
	y = _add(page, Select.new(self, [[0, "100% - English (English)"]],
		func(): return 0, func(_v: int): pass), y, 24.0)   # settings.AvailableLanguages: Steam's list, one here
	y += ROW_PITCH   # .spacer
	y = _text_row(page, Lang.t("settings_menu_display"), y, 24, FONT_WHITE)
	y = _text_row(page, Lang.t("settings_menu_scaling_mode"), y, 18)
	y = _select(page, "settings_menu_scaling_mode_", ["msDownscaling", "msFullscreen", "msDisabled"],
		ClientSettings.menu_scaling, ClientSettings.set_menu_scaling, y)
	# the resolution rows carry `.deactivated` while the scaling is msFullscreen
	var fullscreen_only: Array = []
	var caption := HudStyle.label(Lang.t("settings_menu_resolution"), 18, FONT_DEFAULT, HudStyle.FONT_REGULAR, HORIZONTAL_ALIGNMENT_LEFT)
	y = _add(page, caption, y)
	y = _select(page, "settings_menu_resolution_", ["mr1024x576", "mr1280x720", "mr1600x900", "mr1920x1080", "mr2560x1440", "mrCustom"],
		ClientSettings.menu_resolution, ClientSettings.set_menu_resolution, y)
	fullscreen_only.append(_rows.back())
	y = _check(page, "settings_menu_fullscreen_frame", "", "ClientFullscreenFrame", y, M)
	y += ROW_PITCH   # .spacer
	y = _check(page, "settings_menu_bringtofront_on_match_found", "", "BringToFrontOnMatchFound", y, M)
	_rows.insert(_rows.size() - 2, _Gate.new(func():
		var off := ClientSettings.menu_scaling() == ClientSettings.MenuScaling.FULLSCREEN
		caption.modulate.a = 0.55 if off else 1.0
		for w in fullscreen_only:
			w.deactivated = off))


## MenuSoundSettings.dui (otSoundMeta): the menu client's own mixer, same rows as the game's minus effects/pings.
func _build_menu_sound(page: Control) -> void:
	var y := 0.0
	var S := ClientSettings.Category.SOUND_META
	y = _text_row(page, Lang.t("settings_sound_meta_caption"), y, 24, FONT_WHITE)
	y = _check(page, "settings_sound_check", "", "PlayMaster", y, S)
	y = _add(page, VolumeBar.new(func(): return ClientSettings.get_int(S, "MasterVolume"), func(v: int): ClientSettings.set_int(S, "MasterVolume", v)), y)
	y = _check(page, "settings_sound_background_check", "", "Background", y, S)
	var nested: Array = []
	for pair in [["settings_sound_music_check", "PlayMusic", "MusicVolume"], ["settings_sound_gui_check", "PlayGUISound", "GUISoundVolume"]]:
		y = _check(page, pair[0], "", pair[1], y, S, 35.0)
		nested.append(_rows.back())
		var option: String = pair[2]
		y = _add(page, VolumeBar.new(func(): return ClientSettings.get_int(S, option), func(v: int): ClientSettings.set_int(S, option, v)), y, ROW_H, 35.0)
		nested.append(_rows.back())
	_rows.insert(_rows.size() - nested.size(), _Gate.new(func():
		var off := not ClientSettings.get_bool(S, "PlayMaster")
		for w in nested:
			w.deactivated = off))


func _build_buttons() -> void:
	# .window-buttons: 58 high, centred 35 px below the window's bottom edge; children Margin 0 10.
	var total := 2 * BUTTON_W + 40.0
	var x := (WINDOW.x - total) / 2.0 + 10.0
	var y := WINDOW.y + 35.0 - BUTTON_H / 2.0
	var save := XlButton.new(Lang.t("save"), "_success")
	save.position = Vector2(x, y)
	save.pressed.connect(save_and_close)
	_window.add_child(save)
	var cancel := XlButton.new(Lang.t("cancel"), "_danger")
	cancel.position = Vector2(x + BUTTON_W + 20.0, y)
	cancel.pressed.connect(discard)
	_window.add_child(cancel)


## TSettingsWrapper.Sync: every widget re-reads its option.
func refresh() -> void:
	for w in _rows:
		w.refresh()


func open_dropdown(select: Select) -> void:
	close_dropdown()
	# select > .options: below the field (ParentAnchor caBottomRight, Anchor caTopRight), 100 % wide, rows 24 with
	# Padding 5 7 on the $field-background, framed like the field.
	var list := Control.new()
	list.mouse_filter = MOUSE_FILTER_STOP
	var row_h := 24.0
	list.position = select.global_position - _window.global_position + Vector2(0, select.size.y)
	list.size = Vector2(select.size.x, row_h * select.options.size())
	list.draw.connect(func():
		list.draw_rect(Rect2(Vector2.ZERO, list.size), FIELD_BG)
		list.draw_rect(Rect2(Vector2.ZERO, list.size), BORDER_CYAN, false, 1.0))
	for i in select.options.size():
		var option: Array = select.options[i]
		var row := Control.new()
		row.mouse_filter = MOUSE_FILTER_STOP
		HudStyle.place(row, Rect2(0, i * row_h, list.size.x, row_h))
		var state := {"hover": false}
		row.draw.connect(func():
			if state["hover"]:
				row.draw_rect(Rect2(Vector2.ZERO, row.size), Color(0.5, 0.5, 0.5, 0x40 / 255.0)))
		row.mouse_entered.connect(func(): state["hover"] = true; row.queue_redraw())
		row.mouse_exited.connect(func(): state["hover"] = false; row.queue_redraw())
		row.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				accept_event()
				close_dropdown()
				select.choose(option[0]))
		var label := HudStyle.label(option[1], int(round(select.size.y * 0.7)), FONT_DEFAULT, HudStyle.FONT_REGULAR, HORIZONTAL_ALIGNMENT_LEFT)
		HudStyle.place(label, Rect2(7, 0, row.size.x - 14, row_h))
		row.add_child(label)
		list.add_child(row)
	_window.add_child(list)
	_dropdown = list


func close_dropdown() -> void:
	if _dropdown != null:
		_dropdown.queue_free()
		_dropdown = null


func save_and_close() -> void:
	ClientSettings.save(in_game)
	closed.emit()
	queue_free()


func discard() -> void:
	ClientSettings.load_snapshot()
	closed.emit()
	queue_free()
