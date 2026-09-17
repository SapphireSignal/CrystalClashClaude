class_name InfoPanel
extends Control
## Right edge unit panel for the selected entity (docs/hud.md "Tooltip / unit panel"): portrait with
## league icon, name, health / mana bars, weapon and armor with captions, ability keywords.

const WIDTH := 257.0
const HEIGHT := 371.0

var _own_team: int = 1
var _selected: SimEntity
var _stats: SimEntity           # entity whose stats are shown (a spawner shows its produced unit)
var _content: Control
var _portrait_icon: TextureRect
var _portrait_frame: TextureRect
var _league_icon: TextureRect
var _level: Label
var _name: Label
var _health_fill: ColorRect
var _overheal_fill: ColorRect
var _health_text: Label
var _mana_back: ColorRect
var _mana_fill: ColorRect
var _mana_text: Label
var _weapon_icon: TextureRect
var _weapon_text: Label
var _armor_icon: TextureRect
var _armor_text: Label
var _abilities: Label
var _name_max_size: int


func _ready() -> void:
	size = Vector2(WIDTH, HEIGHT)
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	add_child(HudStyle.blur(Rect2(WIDTH * 0.01, HEIGHT * 0.105 + HEIGHT * 0.06, WIDTH * 0.99, HEIGHT * 0.79)))   # .content Blur : True (99 % x 79 %, y 6 %)
	add_child(HudStyle.picture(HudStyle.tex("HUD/InfoPanel/info_panel_background.png"), Rect2(0, 0, WIDTH, HEIGHT)))
	_content = Control.new()
	_content.mouse_filter = MOUSE_FILTER_IGNORE
	HudStyle.place(_content, Rect2(WIDTH * 0.005, HEIGHT * 0.06, WIDTH * 0.99, HEIGHT * 0.79))
	add_child(_content)
	var cw := _content.size.x
	var ch := _content.size.y
	# portrait hangs above the plate: bottom edge at 10 % of the content
	var pw := cw * 0.48
	var portrait := Rect2((cw - pw) / 2.0, ch * 0.10 - pw, pw, pw)
	_portrait_frame = HudStyle.picture(null, portrait)   # frame behind, round icon on top
	_content.add_child(_portrait_frame)
	_portrait_icon = HudStyle.picture(null, portrait)
	_content.add_child(_portrait_icon)
	var lw := pw * 0.36
	var league_rect := Rect2(portrait.position + Vector2(pw * 0.85, pw * 0.98) - Vector2(lw, lw) / 2.0, Vector2(lw, lw))
	_league_icon = HudStyle.picture(null, league_rect)
	_content.add_child(_league_icon)
	_level = HudStyle.outline(HudStyle.label("", int(lw * 0.45), HudStyle.WHITE, HudStyle.FONT_BOLD), 1)
	HudStyle.place(_level, league_rect)
	_content.add_child(_level)
	_name_max_size = int(ch * 0.11 * 0.7)
	_name = HudStyle.label("", _name_max_size, HudStyle.WHITE, HudStyle.FONT_BOLD)
	HudStyle.place(_name, Rect2(cw * 0.03, ch * 0.10, cw * 0.94, ch * 0.11))
	_content.add_child(_name)
	# info block below the name
	var block := Rect2(0, ch * 0.21, cw, ch * 0.79)
	var bar := Rect2(block.position.x + cw * 0.03, block.position.y, cw * 0.94, block.size.y * 0.15)
	_content.add_child(HudStyle.rect(HudStyle.HEALTH_BACK, bar))
	_health_fill = HudStyle.rect(HudStyle.HEALTH_RED, bar)
	_content.add_child(_health_fill)
	_overheal_fill = HudStyle.rect(Color(1, 1, 1, 0.85), bar)
	_content.add_child(_overheal_fill)
	_health_text = HudStyle.outline(HudStyle.label("", int(bar.size.y * 0.55), HudStyle.WHITE, HudStyle.FONT_BOLD), 1)
	HudStyle.place(_health_text, bar)
	_content.add_child(_health_text)
	var mana_bar := Rect2(bar.position + Vector2(0, block.size.y * 0.16), Vector2(bar.size.x, bar.size.y * 0.6))
	_mana_back = HudStyle.rect(HudStyle.HEALTH_BACK, mana_bar)
	_content.add_child(_mana_back)
	_mana_fill = HudStyle.rect(HudStyle.MANA_CYAN, mana_bar)
	_content.add_child(_mana_fill)
	_mana_text = HudStyle.outline(HudStyle.label("", int(mana_bar.size.y * 0.75), HudStyle.WHITE, HudStyle.FONT_BOLD), 1)
	HudStyle.place(_mana_text, mana_bar)
	_content.add_child(_mana_text)
	var stat_y := block.position.y + block.size.y * 0.30
	var stat_w := cw * 0.30
	var icon_s := stat_w * 0.75
	_weapon_icon = HudStyle.picture(null, Rect2(cw * 0.25 - icon_s / 2.0, stat_y, icon_s, icon_s))
	_content.add_child(_weapon_icon)
	_weapon_text = HudStyle.label("", 18, HudStyle.WHITE, HudStyle.FONT_SEMIBOLD)
	HudStyle.place(_weapon_text, Rect2(cw * 0.25 - stat_w / 2.0, stat_y + icon_s, stat_w, 24))
	_content.add_child(_weapon_text)
	_armor_icon = HudStyle.picture(null, Rect2(cw * 0.75 - icon_s / 2.0, stat_y, icon_s, icon_s))
	_content.add_child(_armor_icon)
	_armor_text = HudStyle.label("", 18, HudStyle.WHITE, HudStyle.FONT_SEMIBOLD)
	HudStyle.place(_armor_text, Rect2(cw * 0.75 - stat_w / 2.0, stat_y + icon_s, stat_w, 24))
	_content.add_child(_armor_text)
	_abilities = HudStyle.label("", 16, HudStyle.WHITE, HudStyle.FONT_SEMIBOLD)
	_abilities.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_abilities.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	HudStyle.place(_abilities, Rect2(cw * 0.05, block.position.y + block.size.y * 0.71, cw * 0.9, block.size.y * 0.29))
	_content.add_child(_abilities)


func setup(own_team: int) -> void:
	_own_team = own_team


func select(e: SimEntity, sim: Simulation) -> void:
	_selected = e
	_stats = e
	visible = e != null
	if e == null:
		return
	if e.is_spawner():   # spawners show the produced unit's stats
		var pattern := str(e.bb.get_value("eiWelaUnitPattern", 0, "")).replace("\\", "/").trim_suffix(".ets")
		if UnitDb.has_unit(pattern):
			_stats = SimEntity.new()
			_stats.setup(pattern, e.league, e.level)
			_stats.team = e.team
	var team := HudStyle.displayed_team(e.team, _own_team)
	_portrait_icon.texture = HudStyle.unit_icon(_stats.unit_id, team)
	_portrait_frame.texture = HudStyle.unit_frame(_stats.unit_id)
	_league_icon.texture = HudStyle.tex("Shared/LeagueIcons/League%d.tga" % clampi(e.league, 1, 5))
	_level.text = str(e.level) if e.level > 0 else ""
	_name.text = Lang.unit_name(_stats.unit_id)
	HudStyle.fit(_name, _name_max_size)
	var data := UnitDb.raw(_stats.unit_id) if UnitDb.has_unit(_stats.unit_id) else {}
	var names := []
	for a in data.get("abilities", []):
		names.append(Lang.t("unitability_name_%s" % str(a).to_lower()))
	_abilities.text = ", ".join(names)
	if _stats.can_attack():
		var mask := _stats.damage_type()
		var kind := "Siege" if mask & SimConstants.DamageType.SIEGE else ("Ranged" if mask & SimConstants.DamageType.RANGED else "Melee")
		_weapon_icon.texture = HudStyle.tex("HUD/InfoPanel/Attack/DamageType%s.png" % kind)
		_weapon_text.text = "%.1f" % (_stats.damage() / maxf(0.001, _stats.cooldown() / 1000.0))
	else:
		_weapon_icon.texture = null
		_weapon_text.text = ""
	var armor_key: String = SimConstants.ARMOR_NAMES.find_key(_stats.armor())
	_armor_icon.texture = HudStyle.tex("HUD/InfoPanel/Armor/Armor%s.png" % armor_key.trim_prefix("at"))
	_armor_text.text = Lang.t("armortype_%s_caption" % armor_key.to_lower())
	refresh(sim)


func refresh(sim: Simulation) -> void:
	if _selected == null:
		return
	if not _selected.alive or not sim.entities.has(_selected.id):
		select(null, sim)
		return
	var e := _stats
	var full := _mana_back.size.x   # health and mana bars share the width
	if e.max_health > 0.0:
		_health_fill.size.x = full * clampf(e.health / e.max_health, 0.0, 1.0)
		_overheal_fill.size.x = full * clampf(e.overheal / e.max_health, 0.0, 1.0)
		_health_text.text = "%d / %d" % [ceili(e.health), ceili(e.max_health)]
	else:
		_health_fill.size.x = 0
		_overheal_fill.size.x = 0
		_health_text.text = ""
	var pool := 0
	var cap := 0
	if e.mana_cap > 0:
		pool = e.mana
		cap = e.mana_cap
	elif e.ammo_cap > 0:   # reWelaCharge stands in for mana
		pool = e.ammo
		cap = e.ammo_cap
	_mana_back.visible = cap > 0
	_mana_fill.visible = cap > 0
	_mana_text.visible = cap > 0
	if cap > 0:
		_mana_fill.size.x = _mana_back.size.x * clampf(float(pool) / cap, 0.0, 1.0)
		_mana_text.text = "%d / %d" % [pool, cap]


func selected() -> SimEntity:
	return _selected
