class_name DeckPanel
extends Control
## Bottom centre card bar (docs/hud.md "DeckPanel"): stage 1/2/3 groups then the spawner group,
## tier-locked groups sink down under a countdown plate, cooldown fill and charge / hotkey badges.

signal slot_clicked(slot_index: int)
signal slot_hovered(slot_index: int)
signal slot_unhovered(slot_index: int)
signal spawner_jump

const HEIGHT := 75.0
const SLOT_W := 85.0
const SLOT_H := 90.0
const SLOT_STEP := 87.0        # 1 px padding each side
const SPAWNER_MARGIN := 80.0
## `.core-game.small` (core_game_scaling.scss): the deck panel is 64 px high with 66x64 slots, spawner margin 48,
## locked groups shifted 38 % (normal: 75 high, 85x90 slots, margin 80, 55 %). The HUD scales the panel by
## 66/85 for the slots, so the panel height and margin are given in that scaled design space.
var panel_height := HEIGHT
var locked_shift := 0.55
var spawner_margin := SPAWNER_MARGIN
var slot_height := SLOT_H   # build-slot-wrapper height: 90 normal, 64 small (the 66 px frame then overflows the bottom by 2 px)
const HOTKEYS := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="]
const GLOW_PERIOD_MS := 2000.0     # $glow keyframes: opacity 1 -> 0.6 -> 1, scale 1.02 -> 1 -> 1.02, ease-in-out
const OVERRIDE_SHADER := preload("res://game/ui/color_override.gdshader")


class SlotView:
	var index: int
	var slot: Commander.DeckSlot
	var root: Control
	var glow: TextureRect
	var darken: ShaderMaterial   # BackgroundColorOverride on the frame + icon (not a square)
	var cooldown: TextureProgressBar
	var cooldown_text: Label
	var charge_text: Label


class Group:
	var tier: int                 # 1..3 for instant groups, 0 for spawners
	var root: Control
	var slots: Array[SlotView] = []
	var plate: Control            # tier-timer plate above locked groups (behind the deco)
	var plate_top: Control        # its countdown + lock icon, drawn over the deco and the sunken slots
	var timer: Label
	var width: float


var _groups: Array[Group] = []
var _views: Array[SlotView] = []
var _jump: TextureButton


## Applied before build(): the small layout of core_game_scaling.scss.
func set_small(small: bool) -> void:
	var slot_scale := 66.0 / SLOT_W
	panel_height = 64.0 / slot_scale if small else HEIGHT
	locked_shift = 0.38 if small else 0.55
	spawner_margin = 48.0 / slot_scale if small else SPAWNER_MARGIN
	slot_height = 64.0 / slot_scale if small else SLOT_H


func build(commander: Commander) -> void:
	for child in get_children():
		child.queue_free()
	_groups.clear()
	_views.clear()
	mouse_filter = MOUSE_FILTER_IGNORE
	var by_group := {1: [], 2: [], 3: [], 0: []}
	for i in commander.slots.size():
		var s: Commander.DeckSlot = commander.slots[i]
		by_group[0 if s.card.is_spawner() else clampi(s.card.tier, 1, 3)].append(i)
	var x := 0.0
	for tier in [1, 2, 3, 0]:
		var indices: Array = by_group[tier]
		if indices.is_empty():
			continue
		if tier == 0:
			x += spawner_margin
		var g := _build_group(commander, tier, indices)
		g.root.position = Vector2(x, 0)
		add_child(g.root)
		_groups.append(g)
		x += g.width
	_jump = TextureButton.new()
	_jump.texture_normal = HudStyle.tex("HUD/DeckPanel/nexus_jump_btn.png")
	_jump.texture_hover = HudStyle.tex("HUD/DeckPanel/nexus_jump_btn_hover.png")
	_jump.ignore_texture_size = true
	_jump.stretch_mode = TextureButton.STRETCH_SCALE
	var jump_h := panel_height * 0.8
	HudStyle.place(_jump, Rect2(x + 8, panel_height - jump_h, 67.0 / 61.0 * jump_h, jump_h))
	_jump.tooltip_text = Lang.t("core_spawner_jump")
	_jump.pressed.connect(func(): spawner_jump.emit())
	add_child(_jump)
	x += 8 + _jump.size.x
	size = Vector2(x, panel_height)


func _build_group(commander: Commander, tier: int, indices: Array) -> Group:
	var g := Group.new()
	g.tier = tier
	g.root = Control.new()
	g.root.mouse_filter = MOUSE_FILTER_IGNORE
	g.width = SLOT_STEP * indices.size()
	g.root.size = Vector2(g.width, panel_height)
	if tier >= 2:
		g.plate = _build_plate(indices.size())   # ZOffset -5: behind the deco (-4) and the slots
		g.plate.position = Vector2(0, 0)   # 100 % of the panel height
		g.root.add_child(g.plate)
	var deco_h := panel_height * 0.8
	var deco := "spawner" if tier == 0 else "main"
	var left := HudStyle.tex("HUD/DeckPanel/deck_%s_left.png" % deco)
	var mid := HudStyle.tex("HUD/DeckPanel/deck_%s_mid.png" % deco)
	var right := HudStyle.tex("HUD/DeckPanel/deck_%s_right.png" % deco)
	var scale := deco_h / left.get_height()
	var lw := left.get_width() * scale
	var rw := right.get_width() * scale
	var deco_y := panel_height - deco_h
	g.root.add_child(HudStyle.picture(left, Rect2(-lw * 0.3, deco_y, lw, deco_h)))
	g.root.add_child(HudStyle.picture(mid, Rect2(lw * 0.7, deco_y, g.width - lw * 0.7 - rw * 0.7, deco_h)))
	g.root.add_child(HudStyle.picture(right, Rect2(g.width - rw * 0.7, deco_y, rw, deco_h)))
	var slots_root := Control.new()
	slots_root.name = "Slots"
	slots_root.mouse_filter = MOUSE_FILTER_IGNORE
	g.root.add_child(slots_root)
	for k in indices.size():
		var view := _build_slot(commander, indices[k])
		view.root.position = Vector2(k * SLOT_STEP + 1, panel_height - slot_height)
		slots_root.add_child(view.root)
		g.slots.append(view)
		_views.append(view)
	if g.plate != null:
		g.plate_top = _build_plate_top(indices.size())
		g.plate_top.position = g.plate.position
		g.timer = g.plate_top.get_node("Timer")
		g.root.add_child(g.plate_top)
	return g


## tier_block_single.png for one card, else end + repeated mid + mirrored end; countdown and lock icon on top.
func _build_plate(count: int) -> Control:
	var plate := Control.new()
	plate.mouse_filter = MOUSE_FILTER_STOP
	var w := SLOT_STEP * count
	plate.size = Vector2(w, panel_height)
	if count == 1:
		plate.add_child(HudStyle.picture(HudStyle.tex("HUD/DeckPanel/tier_block_single.png"), Rect2((w - 84) / 2.0, 0, 84, panel_height)))
	else:
		var end := HudStyle.tex("HUD/DeckPanel/tier_block_multi_end.png")
		var mid := HudStyle.tex("HUD/DeckPanel/tier_block_multi_mid.png")
		var x := 41.0
		while x < w - 41:   # whole tiles first, the ends drawn over them: no fractional seam
			plate.add_child(HudStyle.picture(mid, Rect2(x, 0, 45, panel_height)))
			x += 45
		plate.add_child(HudStyle.picture(end, Rect2(0, 0, 41, panel_height)))
		var right_end := HudStyle.picture(end, Rect2(w - 41, 0, 41, panel_height))
		right_end.flip_h = true
		plate.add_child(right_end)
	return plate


## The countdown (`.timer` 7 % from the top, 25 % high) and `.lock` (15 % high) of a tier plate.
func _build_plate_top(count: int) -> Control:
	var top := Control.new()
	top.mouse_filter = MOUSE_FILTER_IGNORE
	var w := SLOT_STEP * count
	top.size = Vector2(w, panel_height)
	var timer := HudStyle.label("00:00", int(panel_height * 0.25), HudStyle.WHITE, HudStyle.FONT_SEMIBOLD)
	timer.name = "Timer"
	HudStyle.place(timer, Rect2(0, panel_height * 0.07, w - 24, 22))
	top.add_child(timer)
	var lock_h := panel_height * 0.15
	top.add_child(HudStyle.picture(HudStyle.tex("HUD/DeckPanel/lock_icon.png"), Rect2(w / 2.0 + 24, panel_height * 0.11, lock_h * 19.0 / 26.0, lock_h)))
	return top


func _build_slot(commander: Commander, index: int) -> SlotView:
	var v := SlotView.new()
	v.index = index
	v.slot = commander.slots[index]
	var card := v.slot.card
	v.root = Button.new()
	v.root.flat = true
	v.root.size = Vector2(SLOT_W, SLOT_H)
	v.root.mouse_filter = MOUSE_FILTER_STOP
	v.root.focus_mode = Control.FOCUS_NONE
	v.root.pressed.connect(func(): slot_clicked.emit(index))
	v.root.mouse_entered.connect(func(): slot_hovered.emit(index))
	v.root.mouse_exited.connect(func(): slot_unhovered.emit(index))
	# ready glow behind the icon
	var glow_name := "highlight_spawner" if card.is_spawner() else "highlight_drop"
	var glow_tex := HudStyle.tex("HUD/DeckPanel/%s.png" % glow_name)
	var glow_w := SLOT_W * (2.15 if card.is_spawner() else 1.13)
	var glow_h := glow_w * glow_tex.get_height() / glow_tex.get_width()
	var glow_cy := SLOT_H / 2.0 - SLOT_H * (0.24 if card.is_spawner() else 0.135)
	v.glow = HudStyle.picture(glow_tex, Rect2((SLOT_W - glow_w) / 2.0, glow_cy - glow_h / 2.0, glow_w, glow_h))
	v.glow.pivot_offset = v.glow.size / 2.0
	v.root.add_child(v.glow)
	v.darken = ShaderMaterial.new()
	v.darken.shader = OVERRIDE_SHADER
	var frame := HudStyle.card_frame(card)   # icon-frame is the background, the round icon sits on it
	if frame != null:
		var f := HudStyle.picture(frame, Rect2(0, 0, SLOT_W, SLOT_W))
		f.material = v.darken
		v.root.add_child(f)
	var icon := HudStyle.card_icon(card)
	if icon != null:
		var ic := HudStyle.picture(icon, Rect2(0, 0, SLOT_W, SLOT_W))
		ic.material = v.darken
		v.root.add_child(ic)
	v.cooldown = TextureProgressBar.new()
	var mask := "ProgressMaskSpawner" if card.is_spawner() else ("ProgressMaskSpell" if card.is_spell() else "ProgressMask")
	v.cooldown.texture_progress = HudStyle.tex("HUD/DeckPanel/%s.tga" % mask)
	v.cooldown.tint_progress = HudStyle.COOLDOWN
	v.cooldown.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	v.cooldown.nine_patch_stretch = true
	v.cooldown.min_value = 0
	v.cooldown.max_value = 1000
	v.cooldown.mouse_filter = MOUSE_FILTER_IGNORE
	HudStyle.place(v.cooldown, Rect2(0, 0, SLOT_W, SLOT_W))
	v.root.add_child(v.cooldown)
	v.cooldown_text = HudStyle.outline(HudStyle.label("", int(SLOT_H * 0.35), HudStyle.WHITE, HudStyle.FONT_BOLD), 2)
	HudStyle.place(v.cooldown_text, Rect2(0, 0, SLOT_W, SLOT_W))
	v.root.add_child(v.cooldown_text)
	# charge badge bottom-left, hotkey badge bottom centre
	var charge_h := SLOT_H * 0.22
	v.root.add_child(HudStyle.picture(HudStyle.tex("HUD/DeckPanel/charge_background.png"), Rect2(-2, SLOT_H - charge_h + 2, charge_h, charge_h)))
	v.charge_text = HudStyle.label("0", int(charge_h * 0.65), HudStyle.WHITE, HudStyle.FONT_BOLD)
	HudStyle.place(v.charge_text, Rect2(-2, SLOT_H - charge_h + 2, charge_h, charge_h))
	v.root.add_child(v.charge_text)
	var hot_h := SLOT_H * 0.2
	var hot_w := hot_h * 46.0 / 41.0
	v.root.add_child(HudStyle.picture(HudStyle.tex("HUD/DeckPanel/hotkey_background.png"), Rect2((SLOT_W - hot_w) / 2.0, SLOT_H - hot_h, hot_w, hot_h)))
	var hot := HudStyle.label(HOTKEYS[index] if index < HOTKEYS.size() else "", int(hot_h * 0.65), HudStyle.WHITE, HudStyle.FONT_BOLD)
	HudStyle.place(hot, Rect2((SLOT_W - hot_w) / 2.0, SLOT_H - hot_h, hot_w, hot_h))
	v.root.add_child(hot)
	return v


func refresh(sim: Simulation, commander: Commander) -> void:
	var now := sim.time_ms
	var phase := float(Time.get_ticks_msec() % int(GLOW_PERIOD_MS)) / GLOW_PERIOD_MS
	var pulse := 0.5 - 0.5 * cos(TAU * phase)   # 0 at the keyframe ends, 1 in the middle
	pulse = pulse * pulse * (3.0 - 2.0 * pulse)  # ease-in-out
	var locked_views := {}
	for g in _groups:
		if g.plate == null:
			continue
		var locked := commander.tier < g.tier
		g.plate.visible = locked
		g.plate_top.visible = locked
		g.root.get_node("Slots").position.y = SLOT_H * locked_shift if locked else 0.0
		if locked:
			g.timer.text = HudStyle.int_to_time(_time_to_tier(sim, g.tier))
			for v in g.slots:
				locked_views[v] = true
	for v in _views:
		var s := v.slot
		var ready := s.is_ready(now, commander) and not locked_views.has(v)   # .disabled: no highlight, darkened
		v.glow.visible = ready
		v.glow.modulate.a = lerpf(1.0, 0.6, pulse)
		v.glow.scale = Vector2.ONE * lerpf(1.02, 1.0, pulse)
		v.darken.set_shader_parameter("override_color", Color(0, 0, 0, 0) if ready else HudStyle.DARKEN_SOFT)
		v.charge_text.text = str(s.charges)
		var charging := s.recharge_at >= 0 and s.charges < s.charge_cap and not s.card.epic
		if charging:
			var remaining := maxf(0.0, float(s.recharge_at - now))
			var progress := 1.0 - remaining / maxf(1.0, float(s.charge_cooldown_ms))
			v.cooldown.value = (1.0 - progress) * 1000.0
			v.cooldown_text.text = HudStyle.float_to_cooldown(remaining / 1000.0) if s.charges < 1 else ""
		else:
			v.cooldown.value = 0
			v.cooldown_text.text = ""


static func _time_to_tier(sim: Simulation, tier: int) -> int:
	var idx := clampi(sim.league, 1, 5) - 1
	var at: int = SimConstants.TECH_LEVEL_2_SECONDS[idx] if tier == 2 else SimConstants.TECH_LEVEL_3_SECONDS[idx]
	return maxi(0, at - sim.tick_counter)
