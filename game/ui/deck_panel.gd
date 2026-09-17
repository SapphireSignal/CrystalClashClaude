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
const HOTKEYS := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="]


class SlotView:
	var index: int
	var slot: Commander.DeckSlot
	var root: Control
	var glow: TextureRect
	var darken: ColorRect
	var cooldown: TextureProgressBar
	var cooldown_text: Label
	var charge_text: Label


class Group:
	var tier: int                 # 1..3 for instant groups, 0 for spawners
	var root: Control
	var slots: Array[SlotView] = []
	var plate: Control            # tier-timer plate above locked groups
	var timer: Label
	var width: float


var _groups: Array[Group] = []
var _views: Array[SlotView] = []
var _jump: TextureButton


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
			x += SPAWNER_MARGIN
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
	var jump_h := HEIGHT * 0.8
	HudStyle.place(_jump, Rect2(x + 8, HEIGHT - jump_h, 67.0 / 61.0 * jump_h, jump_h))
	_jump.tooltip_text = Lang.t("core_spawner_jump")
	_jump.pressed.connect(func(): spawner_jump.emit())
	add_child(_jump)
	x += 8 + _jump.size.x
	size = Vector2(x, HEIGHT)


func _build_group(commander: Commander, tier: int, indices: Array) -> Group:
	var g := Group.new()
	g.tier = tier
	g.root = Control.new()
	g.root.mouse_filter = MOUSE_FILTER_IGNORE
	g.width = SLOT_STEP * indices.size()
	g.root.size = Vector2(g.width, HEIGHT)
	var deco_h := HEIGHT * 0.8
	var deco := "spawner" if tier == 0 else "main"
	var left := HudStyle.tex("HUD/DeckPanel/deck_%s_left.png" % deco)
	var mid := HudStyle.tex("HUD/DeckPanel/deck_%s_mid.png" % deco)
	var right := HudStyle.tex("HUD/DeckPanel/deck_%s_right.png" % deco)
	var scale := deco_h / left.get_height()
	var lw := left.get_width() * scale
	var rw := right.get_width() * scale
	var deco_y := HEIGHT - deco_h
	g.root.add_child(HudStyle.picture(left, Rect2(-lw * 0.3, deco_y, lw, deco_h)))
	g.root.add_child(HudStyle.picture(mid, Rect2(lw * 0.7, deco_y, g.width - lw * 0.7 - rw * 0.7, deco_h)))
	g.root.add_child(HudStyle.picture(right, Rect2(g.width - rw * 0.7, deco_y, rw, deco_h)))
	var slots_root := Control.new()
	slots_root.name = "Slots"
	slots_root.mouse_filter = MOUSE_FILTER_IGNORE
	g.root.add_child(slots_root)
	for k in indices.size():
		var view := _build_slot(commander, indices[k])
		view.root.position = Vector2(k * SLOT_STEP + 1, HEIGHT - SLOT_H)
		slots_root.add_child(view.root)
		g.slots.append(view)
		_views.append(view)
	if tier >= 2:
		g.plate = _build_plate(indices.size())
		g.plate.position = Vector2(0, HEIGHT - 75)
		g.timer = g.plate.get_node("Timer")
		g.root.add_child(g.plate)
	return g


## tier_block_single.png for one card, else end + repeated mid + mirrored end; countdown and lock icon on top.
func _build_plate(count: int) -> Control:
	var plate := Control.new()
	plate.mouse_filter = MOUSE_FILTER_STOP
	var w := SLOT_STEP * count
	plate.size = Vector2(w, 75)
	if count == 1:
		plate.add_child(HudStyle.picture(HudStyle.tex("HUD/DeckPanel/tier_block_single.png"), Rect2((w - 84) / 2.0, 0, 84, 75)))
	else:
		var end := HudStyle.tex("HUD/DeckPanel/tier_block_multi_end.png")
		var mid := HudStyle.tex("HUD/DeckPanel/tier_block_multi_mid.png")
		plate.add_child(HudStyle.picture(end, Rect2(0, 0, 41, 75)))
		var x := 41.0
		while x < w - 41:
			var piece := HudStyle.picture(mid, Rect2(x, 0, minf(45, w - 41 - x), 75))
			plate.add_child(piece)
			x += 45
		var right_end := HudStyle.picture(end, Rect2(w - 41, 0, 41, 75))
		right_end.flip_h = true
		plate.add_child(right_end)
	var timer := HudStyle.label("00:00", int(75 * 0.25), HudStyle.WHITE, HudStyle.FONT_SEMIBOLD)
	timer.name = "Timer"
	HudStyle.place(timer, Rect2(0, 75 * 0.07, w - 24, 22))
	plate.add_child(timer)
	plate.add_child(HudStyle.picture(HudStyle.tex("HUD/DeckPanel/lock_icon.png"), Rect2(w / 2.0 + 24, 75 * 0.07 - 2, 19, 26)))
	return plate


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
	v.root.add_child(v.glow)
	var frame := HudStyle.card_frame(card)   # icon-frame is the background, the round icon sits on it
	if frame != null:
		v.root.add_child(HudStyle.picture(frame, Rect2(0, 0, SLOT_W, SLOT_W)))
	var icon := HudStyle.card_icon(card)
	if icon != null:
		v.root.add_child(HudStyle.picture(icon, Rect2(0, 0, SLOT_W, SLOT_W)))
	v.darken = HudStyle.rect(HudStyle.DARKEN_SOFT, Rect2(2, 2, SLOT_W - 4, SLOT_W - 4))
	v.root.add_child(v.darken)
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
	for g in _groups:
		if g.plate == null:
			continue
		var locked := commander.tier < g.tier
		g.plate.visible = locked
		g.root.get_node("Slots").position.y = SLOT_H * 0.55 if locked else 0.0
		if locked:
			g.timer.text = HudStyle.int_to_time(_time_to_tier(sim, g.tier))
	for v in _views:
		var s := v.slot
		var ready := s.is_ready(now, commander)
		v.glow.visible = ready
		v.darken.visible = not ready
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
