extends RefCounted
## ClientSettings: defaults, the quality preset logic of TSettingsWrapper, snapshot/revert (no file access: the
## tests only touch the in-memory overrides and restore them).

var runner


func _reset() -> void:
	ClientSettings._loaded = true
	ClientSettings._values = {}


func test_defaults_match_the_original() -> void:
	_reset()
	runner.check_eq(ClientSettings.get_int(ClientSettings.Category.SOUND, "MasterVolume"), 70, "master volume 70")
	runner.check_eq(ClientSettings.healthbar_mode(), ClientSettings.HealthbarMode.DAMAGED, "hmDamaged")
	runner.check_eq(ClientSettings.get_bool(ClientSettings.Category.GAMEPLAY, "ShowDeckHotkeys"), false, "hotkeys hidden by default")


func test_click_precision_thresholds() -> void:
	_reset()
	# Refresh: > 1.0 wide, > 0.0 extended, else precise; the setter writes 0.0 / 0.5 / 1.0
	runner.check_eq(ClientSettings.click_precision(), ClientSettings.ClickPrecision.EXTENDED, "default 1.0 reads back as extended")
	ClientSettings.set_click_precision(ClientSettings.ClickPrecision.PRECISE)
	runner.check_eq(ClientSettings.get_string(ClientSettings.Category.GAMEPLAY, "ClickPrecision"), "0.0", "precise writes 0.0")
	runner.check_eq(ClientSettings.click_precision(), ClientSettings.ClickPrecision.PRECISE, "reads precise")
	ClientSettings.set_click_precision(ClientSettings.ClickPrecision.WIDE)
	runner.check_eq(ClientSettings.click_precision(), ClientSettings.ClickPrecision.EXTENDED, "wide writes 1.0 which reads back as extended (original quirk)")


func test_graphics_quality_presets() -> void:
	_reset()
	# defaults: shadows 2048 (sqHigh), deferred + toon + glow + fxaa + unsharp + distortion + blur, no SSAO = gqHigh
	runner.check_eq(ClientSettings.shadow_quality(), ClientSettings.ShadowQuality.HIGH, "default shadows high")
	runner.check_eq(ClientSettings.graphics_quality(), ClientSettings.GraphicsQuality.HIGH, "defaults are the High preset")
	ClientSettings.set_bool(ClientSettings.Category.GRAPHICS, "PostEffectSSAO", true)
	runner.check_eq(ClientSettings.graphics_quality(), ClientSettings.GraphicsQuality.CUSTOM, "SSAO with High shadows = custom")
	ClientSettings.set_graphics_quality(ClientSettings.GraphicsQuality.VERY_HIGH)
	runner.check_eq(ClientSettings.shadow_quality(), ClientSettings.ShadowQuality.ULTRA_HIGH, "very high writes 4096 shadows")
	runner.check_eq(ClientSettings.get_string(ClientSettings.Category.ENGINE, "ShadowSlopeBias"), "0.35", "ultra shadows slope bias")
	runner.check_eq(ClientSettings.graphics_quality(), ClientSettings.GraphicsQuality.VERY_HIGH, "reads back very high")
	ClientSettings.set_graphics_quality(ClientSettings.GraphicsQuality.VERY_LOW)
	runner.check_eq(ClientSettings.shadow_quality(), ClientSettings.ShadowQuality.OFF, "very low switches shadows off")
	runner.check_eq(ClientSettings.get_bool(ClientSettings.Category.GRAPHICS, "PostEffectFXAA"), false, "very low: no fxaa")
	runner.check_eq(ClientSettings.graphics_quality(), ClientSettings.GraphicsQuality.VERY_LOW, "reads back very low")
	ClientSettings.set_graphics_quality(ClientSettings.GraphicsQuality.LOW)
	runner.check_eq(ClientSettings.get_bool(ClientSettings.Category.GRAPHICS, "PostEffectFXAA"), true, "low: fxaa on")
	runner.check_eq(ClientSettings.get_int(ClientSettings.Category.GRAPHICS, "ShadowResolution"), 512, "low: 512 shadows")
	ClientSettings.set_shadow_quality(ClientSettings.ShadowQuality.MEDIUM)
	runner.check_eq(ClientSettings.graphics_quality(), ClientSettings.GraphicsQuality.CUSTOM, "low options with medium shadows = custom")
	ClientSettings.set_graphics_quality(ClientSettings.GraphicsQuality.CUSTOM)
	runner.check_eq(ClientSettings.shadow_quality(), ClientSettings.ShadowQuality.MEDIUM, "choosing custom changes nothing")


func test_snapshot_and_revert() -> void:
	_reset()
	ClientSettings.set_bool(ClientSettings.Category.GAMEPLAY, "ShowDeckHotkeys", true)
	ClientSettings.save_snapshot()
	ClientSettings.set_int(ClientSettings.Category.SOUND, "MasterVolume", 12)
	ClientSettings.set_bool(ClientSettings.Category.GAMEPLAY, "ShowDeckHotkeys", false)
	ClientSettings.load_snapshot()
	runner.check_eq(ClientSettings.get_int(ClientSettings.Category.SOUND, "MasterVolume"), 70, "cancel restores the volume")
	runner.check_eq(ClientSettings.get_bool(ClientSettings.Category.GAMEPLAY, "ShowDeckHotkeys"), true, "cancel keeps the snapshot's value")
	ClientSettings.revert_category(ClientSettings.Category.GAMEPLAY)
	runner.check_eq(ClientSettings.get_bool(ClientSettings.Category.GAMEPLAY, "ShowDeckHotkeys"), false, "revert restores the default")
	runner.check_eq(ClientSettings._values.get(ClientSettings.Category.GAMEPLAY, {}).is_empty(), true, "defaults are not stored as overrides")
	_reset()


func test_surrender_ends_the_match() -> void:
	var sim := Simulation.new(1, 4)
	var lost: Array = []
	var handler := func(t: int): lost.append(t)
	sim.team_lost.connect(handler)
	sim.surrender(Simulation.TEAM_RED)
	sim.team_lost.disconnect(handler)
	runner.check_eq(sim.finished, true, "surrender finishes the match")
	runner.check_eq(sim.winner_team, Simulation.TEAM_BLUE, "the other team wins")
	runner.check_eq(lost, [Simulation.TEAM_RED], "team_lost fired for the surrendering team")


func test_menu_window_size() -> void:
	_reset()
	# SetClientWindow: msDownscaling on a screen that holds the canvas resolves to msDisabled (chosen size)
	runner.check_eq(ClientSettings.menu_window_size(Vector2i(1680, 1032)), Vector2i(1280, 720), "default 1280x720 on a 1680x1032 desktop")
	ClientSettings.set_menu_resolution(ClientSettings.MenuResolution.R1600X900)
	runner.check_eq(ClientSettings.menu_window_size(Vector2i(1680, 1032)), Vector2i(1600, 900), "a fitting choice is used verbatim")
	# a choice larger than the monitor falls back to the 16:9 fit of the screen (1680 wide -> 945 high)
	ClientSettings.set_menu_resolution(ClientSettings.MenuResolution.R1920X1080)
	runner.check_eq(ClientSettings.menu_window_size(Vector2i(1680, 1032)), Vector2i(1680, 945), "an oversized choice fits the screen at 16:9")
	# msFullscreen always uses the fitted size; on a 16:9 desktop that is the whole screen
	ClientSettings.set_menu_scaling(ClientSettings.MenuScaling.FULLSCREEN)
	runner.check_eq(ClientSettings.menu_window_size(Vector2i(1920, 1080)), Vector2i(1920, 1080), "fullscreen fills a 16:9 desktop")
	runner.check_eq(ClientSettings.menu_window_size(Vector2i(1680, 1032)), Vector2i(1680, 945), "fullscreen letterboxes a 16:10 desktop by width")
	# a desktop too small for the canvas: msDownscaling must resolve to msFullscreen, not the chosen size
	ClientSettings.set_menu_scaling(ClientSettings.MenuScaling.DOWNSCALING)
	ClientSettings.set_menu_resolution(ClientSettings.MenuResolution.R1280X720)
	runner.check_eq(ClientSettings.menu_window_size(Vector2i(1024, 600)), Vector2i(1024, 576), "a small desktop scales the canvas down")
	_reset()


func test_menu_canvas_scale() -> void:
	# GUI.VirtualSize = 1280x720: the menu canvas scales uniformly with the window
	runner.check_eq(MenuLayout.scale_for(Vector2(1280, 720)), 1.0, "1:1 at the canvas size")
	runner.check_eq(MenuLayout.scale_for(Vector2(1920, 1080)), 1.5, "1.5x at 1920x1080")
	runner.check_eq(MenuLayout.scale_for(Vector2(1680, 945)), 1680.0 / 1280.0, "uniform on the fitted size")
