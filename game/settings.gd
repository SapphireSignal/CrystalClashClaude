class_name ClientSettings
extends RefCounted
## The client options (TOptionManager, BaseConflict.Settings.Client.pas) with the settings menu's derived values
## (TSettingsWrapper, BaseConflict.Classes.Gamestates.pas:525-5640). Options are strings keyed by their enum name
## without the `co<Category>` prefix, stored in `user://Settings.ini` under the category section exactly like the
## original `Settings.ini` (`[Gameplay] ClipCursor=False`); only values differing from the defaults are written.
## Opening the dialog takes a snapshot (SaveSnapshot); Cancel restores it (LoadSnapshot), Save writes the file.
##
## Static: read by the HUD and the sandbox, written by the SettingsMenu. `apply()` pushes the engine-level options
## (display mode, vsync, master volume) to Godot.

const FILE := "user://Settings.ini"

enum Category { ENGINE, SOUND, SOUND_META, GRAPHICS, MENU, GAMEPLAY, SANDBOX, GENERAL, KEYBINDING }
enum HealthbarMode { NONE, DAMAGED, ALWAYS }              # EnumHealthbarMode hmNone, hmDamaged, hmAlways
enum DropZoneMode { ALL, AREA, CURSOR, HIDE }              # EnumDropZoneMode dzAll, dzArea, dzCursor, dzHide
enum ClickPrecision { PRECISE, EXTENDED, WIDE }            # EnumClickPrecision (0.0 / 0.5 / 1.0 bias)
enum DisplayMode { BORDERLESS_FULLSCREEN_WINDOW, WINDOWED } # EnumDisplayMode
enum GraphicsQuality { VERY_LOW, LOW, MEDIUM, HIGH, VERY_HIGH, CUSTOM }   # EnumGraphicsQuality
enum TextureQuality { MAXIMUM, HIGH, MEDIUM, LOW, MINIMUM }               # EnumTextureQuality
enum ShadowQuality { OFF, VERY_LOW, LOW, MEDIUM, HIGH, ULTRA_HIGH }        # EnumShadowQuality
enum MenuScaling { DOWNSCALING, FULLSCREEN, DISABLED }                     # EnumMenuScaling
enum MenuResolution { R1024X576, R1280X720, R1600X900, R1920X1080, R2560X1440, CUSTOM }   # EnumMenuResolution

## TSettingsWrapper.MENU_RESOLUTIONS (mrCustom has no size of its own).
const MENU_RESOLUTIONS := [Vector2i(1024, 576), Vector2i(1280, 720), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440)]

const SECTIONS := {
	Category.ENGINE: "Engine", Category.SOUND: "Sound", Category.SOUND_META: "SoundMeta", Category.GRAPHICS: "Graphics",
	Category.MENU: "Menu", Category.GAMEPLAY: "Gameplay", Category.SANDBOX: "Sandbox", Category.GENERAL: "General",
	Category.KEYBINDING: "Keybinding",
}

## TOptionManager.DefaultOption per option; the sound-meta values (the menu's own mixer) share the sound defaults.
const DEFAULTS := {
	Category.GENERAL: {"HasSecretAccess": "False", "FirstStart": "True", "Language": ""},
	Category.ENGINE: {
		"DisplayMode": "0", "ShadowBiasMin": "0.01", "ShadowBiasMax": "0.02", "ShadowSlopeBias": "0.5",
		"CameraFoV": "0.6853981635", "VSyncLevel": "1",
	},
	Category.GRAPHICS: {
		"PerformanceAnalysed": "False", "Shadows": "True", "DeferredShading": "True", "VSync": "False",
		"ShadowResolution": "2048", "GUIBlurBackgrounds": "True", "TextureQuality": "0", "PostEffectSSAO": "False",
		"PostEffectToon": "True", "PostEffectGlow": "True", "PostEffectFXAA": "True", "PostEffectUnsharpMasking": "True",
		"PostEffectDistortion": "True",
	},
	Category.SOUND: {
		"PlayMaster": "True", "MasterVolume": "70", "Background": "False", "PlayMusic": "True", "MusicVolume": "70",
		"PlayEffects": "True", "EffectVolume": "70", "PlayGUISound": "True", "GUISoundVolume": "70",
		"PlayPings": "True", "PingVolume": "70", "PlayAtmo": "True",
	},
	Category.SOUND_META: {
		"PlayMaster": "True", "MasterVolume": "70", "Background": "False", "PlayMusic": "True", "MusicVolume": "70",
		"PlayGUISound": "True", "GUISoundVolume": "70",
	},
	Category.GAMEPLAY: {
		"ShowEffectRadius": "True", "HealthbarMode": "1", "DragWavetemplates": "False", "EndlessBuild": "False",
		"ClipCursor": "True", "RightClickPanning": "True", "CameraMinZoom": "2.6", "CameraMaxZoom": "3.8",
		"DropZoneMode": "0", "DropValidColor": "$FF00FF00", "DropInvalidColor": "$FFFF0000",
		"PreviewValidColor": "$FF00FF00", "PreviewInvalidColor": "$FFFF0000", "FixedTeamColors": "True",
		"ClickPrecision": "1.0", "ScrollSpeed": "40.0", "ShowTechnicalPanel": "True",
		"ShowNumericChargeCooldown": "False", "ShowDeckHotkeys": "False",
	},
	Category.MENU: {
		"AnimatedBackground": "True", "DeckbuildingGridSize": "3", "DeckbuildingSacrificeGridSize": "12",
		"LimitFramerate": "50", "ClientResolution": "1280x720",   # TGameStateManager.CLIENT_DEFAULT_DIMENSIONS
		"ClientScaling": "0", "ClientFullscreenFrame": "False", "BringToFrontOnMatchFound": "True",
	},
	Category.SANDBOX: {},
	Category.KEYBINDING: {},
}

## TSettingsWrapper.GRAPHICS_PRESET_*: the shadow quality and the options a quality preset switches on.
const PRESET_SHADOW := [ShadowQuality.OFF, ShadowQuality.LOW, ShadowQuality.MEDIUM, ShadowQuality.HIGH, ShadowQuality.ULTRA_HIGH]
const PRESET_OPTIONS := ["DeferredShading", "GUIBlurBackgrounds", "PostEffectSSAO", "PostEffectToon", "PostEffectGlow",
	"PostEffectFXAA", "PostEffectUnsharpMasking", "PostEffectDistortion"]
const PRESET_ACTIVE := [
	[],
	["PostEffectFXAA"],
	["PostEffectFXAA", "GUIBlurBackgrounds", "PostEffectGlow", "PostEffectUnsharpMasking", "PostEffectDistortion"],
	["PostEffectFXAA", "GUIBlurBackgrounds", "PostEffectGlow", "PostEffectUnsharpMasking", "PostEffectDistortion",
		"DeferredShading", "PostEffectToon"],
	["PostEffectFXAA", "GUIBlurBackgrounds", "PostEffectGlow", "PostEffectUnsharpMasking", "PostEffectDistortion",
		"DeferredShading", "PostEffectToon", "PostEffectSSAO"],
]
## WriteShadowQualityToSettings: resolution, bias min, bias max, slope bias per quality (OFF only clears Shadows).
const SHADOW_VALUES := {
	ShadowQuality.VERY_LOW: ["256", "0.11", "0.22", "3.4"],
	ShadowQuality.LOW: ["512", "0.11", "0.22", "1.9"],
	ShadowQuality.MEDIUM: ["1024", "0.03", "0.06", "0.8"],
	ShadowQuality.HIGH: ["2048", "0.01", "0.02", "0.5"],
	ShadowQuality.ULTRA_HIGH: ["4096", "0.01", "0.02", "0.35"],
}

static var _values: Dictionary = {}     # Category -> {option: string}; only overrides of the defaults
static var _snapshot: Dictionary = {}
static var _loaded := false
static var _listeners: Array[Callable] = []   # called after save() and revert_category()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var file := ConfigFile.new()
	if file.load(FILE) != OK:
		return
	for category: int in SECTIONS:
		var section: String = SECTIONS[category]
		if not file.has_section(section):
			continue
		for key in file.get_section_keys(section):
			set_string(category, key, str(file.get_value(section, key)))


static func get_string(category: int, option: String) -> String:
	_ensure_loaded()
	var overrides: Dictionary = _values.get(category, {})
	if overrides.has(option):
		return overrides[option]
	return DEFAULTS[category].get(option, "")


static func set_string(category: int, option: String, value: String) -> void:
	_ensure_loaded()
	if not _values.has(category):
		_values[category] = {}
	if value == DEFAULTS[category].get(option, ""):
		_values[category].erase(option)
	else:
		_values[category][option] = value


static func get_bool(category: int, option: String) -> bool:
	return get_string(category, option).to_lower() == "true"


static func set_bool(category: int, option: String, value: bool) -> void:
	set_string(category, option, "True" if value else "False")


static func get_int(category: int, option: String) -> int:
	return int(get_string(category, option))


static func set_int(category: int, option: String, value: int) -> void:
	set_string(category, option, str(value))


static func get_float(category: int, option: String) -> float:
	return float(get_string(category, option))


## TOptionManager.RevertOption for every option of the category (TSettingsWrapper.RevertCategory).
static func revert_category(category: int) -> void:
	_ensure_loaded()
	_values.erase(category)
	_notify()


static func save_snapshot() -> void:
	_ensure_loaded()
	_snapshot = _values.duplicate(true)


static func load_snapshot() -> void:
	_values = _snapshot.duplicate(true)
	_notify()


## TOptionManager.SaveSettings: writes the overrides to the ini and applies the engine-level options.
static func save(in_game: bool = true) -> void:
	_ensure_loaded()
	var file := ConfigFile.new()
	for category: int in _values:
		for option: String in _values[category]:
			file.set_value(SECTIONS[category], option, _values[category][option])
	var err := file.save(FILE)
	if err != OK:
		push_error("saving %s failed: %s" % [FILE, error_string(err)])
	apply(in_game)
	_notify()


static func listen(callable: Callable) -> void:
	_listeners.append(callable)


static func unlisten(callable: Callable) -> void:
	_listeners.erase(callable)


static func _notify() -> void:
	for c in _listeners:
		if c.is_valid():
			c.call()


## The options Godot owns: the window (display mode in a match, the menu client's scaling/resolution outside one),
## vsync (coGraphicsVSync) and the master mixer (coSoundPlayMaster / coSoundMasterVolume; the other channels get
## their buses with the audio phase). Applied on Save only: at start the project's window settings stand (the tools
## and the owner's window setup rely on them), like the original applying its window options through its launcher.
##
## The original ran the menu in its own small client window (1280x720) and the match in the game window, so the two
## sets never met. This port has one window, so `in_game` picks which set owns it: the game's display mode in a
## match, the menu client's scaling + resolution outside one.
static func apply(in_game: bool = true) -> void:
	if in_game:
		_apply_game_window()
	else:
		_apply_menu_window()
	apply_startup()


static func _apply_game_window() -> void:
	var window := DisplayServer.MAIN_WINDOW_ID
	if DisplayServer.window_get_mode(window) == DisplayServer.WINDOW_MODE_MINIMIZED:
		return
	if display_mode() == DisplayMode.BORDERLESS_FULLSCREEN_WINDOW:
		# dmBorderlessFullscreenWindow is exactly that: `BorderStyle := bsNone` plus `SetBounds(TargetMonitor...)`,
		# a borderless window over the whole monitor (its full bounds, taskbar included) - never a fullscreen mode
		# switch, so alt-tab and a second monitor keep working.
		var monitor := DisplayServer.window_get_current_screen(window)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED, window)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true, window)
		DisplayServer.window_set_position(DisplayServer.screen_get_position(monitor), window)
		DisplayServer.window_set_size(DisplayServer.screen_get_size(monitor), window)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED, window)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false, window)
	# dmWindowed: a plain window, fitted to the usable area so it cannot hang off the screen edges
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen(window))
	var wanted := DisplayServer.window_get_size(window)
	var fitted := Vector2i(mini(wanted.x, screen.size.x), mini(wanted.y, screen.size.y))
	DisplayServer.window_set_size(fitted, window)
	DisplayServer.window_set_position(screen.position + (screen.size - fitted) / 2, window)


## TGameStateManager.SetClientWindow: the menu runs in a borderless window sized from the chosen resolution, the
## scaling mode and the monitor. The GUI itself is always the 1280x720 canvas scaled to that window (MenuLayout).
static func _apply_menu_window() -> void:
	var window := DisplayServer.MAIN_WINDOW_ID
	if DisplayServer.window_get_mode(window) == DisplayServer.WINDOW_MODE_MINIMIZED:
		return
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen(window))
	var wanted := menu_window_size(screen.size)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED, window)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true, window)   # GameWindow.BorderStyle := bsNone
	DisplayServer.window_set_size(wanted, window)
	DisplayServer.window_set_position(screen.position + (screen.size - wanted) / 2, window)


## SetClientWindow's size arithmetic. `ScaledWindowSize` is the screen fitted to the canvas' 16:9, so the window
## never letterboxes; msDownscaling picks msFullscreen when the screen cannot hold the canvas at 1:1, else
## msDisabled (the chosen resolution verbatim). Our one deviation: a chosen resolution larger than the monitor
## falls back to the fitted size instead of hanging off the screen edges.
static func menu_window_size(screen: Vector2i) -> Vector2i:
	var canvas := MENU_RESOLUTIONS[MenuResolution.R1280X720]
	var wide := screen.x * canvas.y > screen.y * canvas.x
	var scaled := Vector2i(screen.y * canvas.x / canvas.y, screen.y) if wide 			else Vector2i(screen.x, screen.x * canvas.y / canvas.x)
	var scaling := menu_scaling()
	if scaling == MenuScaling.DOWNSCALING:
		var fits := scaled.y >= canvas.y if wide else scaled.x >= canvas.x
		scaling = MenuScaling.DISABLED if fits else MenuScaling.FULLSCREEN
	if scaling == MenuScaling.FULLSCREEN:
		return scaled
	var wanted := menu_dimensions()
	if wanted.x > screen.x or wanted.y > screen.y:
		return scaled
	return wanted


static func apply_startup() -> void:
	var window := DisplayServer.MAIN_WINDOW_ID
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_bool(Category.GRAPHICS, "VSync") else DisplayServer.VSYNC_DISABLED, window)
	var master := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(master, not get_bool(Category.SOUND, "PlayMaster"))
	AudioServer.set_bus_volume_db(master, linear_to_db(maxf(0.0001, get_int(Category.SOUND, "MasterVolume") / 100.0)))


# --- derived values of TSettingsWrapper -----------------------------------------------------------------------

static func healthbar_mode() -> int:
	return get_int(Category.GAMEPLAY, "HealthbarMode")


static func set_healthbar_mode(mode: int) -> void:
	set_int(Category.GAMEPLAY, "HealthbarMode", mode)


static func drop_zone_mode() -> int:
	return get_int(Category.GAMEPLAY, "DropZoneMode")


static func set_drop_zone_mode(mode: int) -> void:
	set_int(Category.GAMEPLAY, "DropZoneMode", mode)


## Refresh: > 1.0 wide, > 0.0 extended, else precise.
static func click_precision() -> int:
	var value := get_float(Category.GAMEPLAY, "ClickPrecision")
	if value > 1.0:
		return ClickPrecision.WIDE
	if value > 0.0:
		return ClickPrecision.EXTENDED
	return ClickPrecision.PRECISE


static func set_click_precision(precision: int) -> void:
	set_string(Category.GAMEPLAY, "ClickPrecision", ["0.0", "0.5", "1.0"][precision])


static func display_mode() -> int:
	return get_int(Category.ENGINE, "DisplayMode")


static func set_display_mode(mode: int) -> void:
	set_int(Category.ENGINE, "DisplayMode", mode)


static func texture_quality() -> int:
	return get_int(Category.GRAPHICS, "TextureQuality")


static func set_texture_quality(quality: int) -> void:
	set_int(Category.GRAPHICS, "TextureQuality", quality)


## DetermineShadowQualityFromSettings: by the shadow map resolution thresholds.
static func shadow_quality() -> int:
	if not get_bool(Category.GRAPHICS, "Shadows"):
		return ShadowQuality.OFF
	var resolution := get_int(Category.GRAPHICS, "ShadowResolution")
	if resolution >= 4096:
		return ShadowQuality.ULTRA_HIGH
	if resolution >= 2048:
		return ShadowQuality.HIGH
	if resolution >= 1024:
		return ShadowQuality.MEDIUM
	if resolution >= 512:
		return ShadowQuality.LOW
	return ShadowQuality.VERY_LOW


static func set_shadow_quality(quality: int) -> void:
	set_bool(Category.GRAPHICS, "Shadows", quality != ShadowQuality.OFF)
	if quality == ShadowQuality.OFF:
		return
	var v: Array = SHADOW_VALUES[quality]
	set_string(Category.GRAPHICS, "ShadowResolution", v[0])
	set_string(Category.ENGINE, "ShadowBiasMin", v[1])
	set_string(Category.ENGINE, "ShadowBiasMax", v[2])
	set_string(Category.ENGINE, "ShadowSlopeBias", v[3])


## DetermineGraphicsQualityFromSettings: the preset whose shadow quality and active option set match exactly.
static func graphics_quality() -> int:
	var active: Array = []
	for option in PRESET_OPTIONS:
		if get_bool(Category.GRAPHICS, option):
			active.append(option)
	active.sort()
	var shadows := shadow_quality()
	for quality in range(GraphicsQuality.VERY_HIGH, GraphicsQuality.VERY_LOW - 1, -1):
		var preset: Array = PRESET_ACTIVE[quality].duplicate()
		preset.sort()
		if shadows == PRESET_SHADOW[quality] and preset == active:
			return quality
	return GraphicsQuality.CUSTOM


## WriteGraphicsQualityToSettings: a preset writes its shadow quality and every preset option (Custom changes nothing).
static func set_graphics_quality(quality: int) -> void:
	if quality == GraphicsQuality.CUSTOM:
		return
	set_shadow_quality(PRESET_SHADOW[quality])
	for option in PRESET_OPTIONS:
		set_bool(Category.GRAPHICS, option, PRESET_ACTIVE[quality].has(option))


static func menu_dimensions() -> Vector2i:
	var parts := get_string(Category.MENU, "ClientResolution").split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return MENU_RESOLUTIONS[MenuResolution.R1280X720]
	return Vector2i(int(parts[0]), int(parts[1]))


## DetermineMenuResolution: the entry whose size matches the stored dimension, else mrCustom.
static func menu_resolution() -> int:
	var current := menu_dimensions()
	for i in MENU_RESOLUTIONS.size():
		if MENU_RESOLUTIONS[i] == current:
			return i
	return MenuResolution.CUSTOM


static func set_menu_resolution(resolution: int) -> void:
	if resolution == MenuResolution.CUSTOM:
		return   # SetMenuResolution writes nothing for mrCustom
	var size: Vector2i = MENU_RESOLUTIONS[resolution]
	set_string(Category.MENU, "ClientResolution", "%dx%d" % [size.x, size.y])


static func menu_scaling() -> int:
	return get_int(Category.MENU, "ClientScaling")


static func set_menu_scaling(scaling: int) -> void:
	set_int(Category.MENU, "ClientScaling", scaling)
