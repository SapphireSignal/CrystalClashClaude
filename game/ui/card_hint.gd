class_name CardHint
extends Control
## The card summary shown while a deck slot is hovered (MainMenu/Shared/Card/CardHUD.dui + shared_card.scss,
## docs/hud.md "DeckPanel"): shadow, icon frame with league/level, name plate, skill list or spell text,
## DPS / health boxes and the price tag with the tech roman.

const WIDTH := 334.0
const HEIGHT := WIDTH * 324.0 / 649.0   # CardShadow*.png aspect
const CARD := "MainMenu/Shared/Card/"
const INFO_TEXT := Color(0, 0, 0, 0xDF / 255.0)
const STAT_BOX := Color(0x1C / 255.0, 0x2B / 255.0, 0x2E / 255.0, 1.0)

var _shadow: TextureRect
var _frame: TextureRect
var _icon: TextureRect
var _special: TextureRect
var _league: TextureRect
var _level: TextureRect
var _info_bg: TextureRect
var _name: Label
var _name_size: int
var _description: Label
var _stats: Control
var _dps_icon: TextureRect
var _dps: Label
var _health_icon: TextureRect
var _health: Label
var _price: TextureRect
var _cost: Label
var _tech: Label
var _content_h: float
var _skill_hint: PanelContainer   # .skill-hint: ability names + hints and keyword descriptions
var _skill_list: VBoxContainer
var _keyword_list: VBoxContainer
var _keyword_panel: PanelContainer
var _hover_started_ms: int = -1

const SKILL_HINT_W := 250.0
const SKILL_HINT_DELAY_MS := 1000    # the live client opens the ability box after a short hover (docs/hud.md)
const HINT_BG := Color(0x3C / 255.0, 0x57 / 255.0, 0x57 / 255.0, 1.0)         # $background-hint
const FIELD_BG := Color(0x27 / 255.0, 0x3A / 255.0, 0x3C / 255.0, 1.0)        # $field-background
const BORDER_CYAN := Color(0x5C / 255.0, 0x89 / 255.0, 0x89 / 255.0, 1.0)     # $border-cyan
const FONT_DEFAULT := Color(0xA9 / 255.0, 0xDC / 255.0, 0xE7 / 255.0, 1.0)    # $font-color-default


func _ready() -> void:
	size = Vector2(WIDTH, HEIGHT)
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	_shadow = HudStyle.picture(null, Rect2(0, 0, WIDTH, HEIGHT))
	_shadow.modulate = Color(1, 1, 1, 0xA0 / 255.0)
	add_child(_shadow)
	# .shadow padding 7% 4% 16% 4% (top right bottom left, of the own height / width)
	var content := Control.new()
	content.mouse_filter = MOUSE_FILTER_IGNORE
	HudStyle.place(content, Rect2(WIDTH * 0.04, HEIGHT * 0.07, WIDTH * 0.92, HEIGHT * 0.77))
	add_child(content)
	var cw := content.size.x
	var ch := content.size.y
	_content_h = ch
	# icon-frame: 105 % of the content height, at 1 % 1 %
	var fs := ch * 1.05
	var frame_rect := Rect2(cw * 0.01, ch * 0.01, fs, fs)
	_frame = HudStyle.picture(null, frame_rect)
	content.add_child(_frame)
	_icon = HudStyle.picture(null, frame_rect)
	content.add_child(_icon)
	var ind_h := fs * 0.92
	_special = HudStyle.picture(null, Rect2(frame_rect.position - Vector2(fs * 0.06, fs * 0.06), Vector2(ind_h * 235.0 / 256.0, ind_h)))
	content.add_child(_special)
	var ls := fs * 0.36
	var league_rect := Rect2(frame_rect.position + Vector2(fs * 0.85, fs * 0.98) - Vector2(ls, ls) / 2.0, Vector2(ls, ls))
	_league = HudStyle.picture(null, league_rect)
	content.add_child(_league)
	var ns := ls * 0.692
	_level = HudStyle.picture(null, Rect2(league_rect.get_center() - Vector2(ns, ns) / 2.0, Vector2(ns, ns)))
	content.add_child(_level)
	# card-info: background at 100 % height, anchored top-right at -1.5 % 4.5 %
	var iw := ch * 379.0 / 251.0
	var info := Control.new()
	info.mouse_filter = MOUSE_FILTER_IGNORE
	HudStyle.place(info, Rect2(cw - iw - cw * 0.015, ch * 0.045, iw, ch))
	content.add_child(info)
	_info_bg = HudStyle.picture(null, Rect2(0, 0, iw, ch))
	info.add_child(_info_bg)
	var name_rect := Rect2(iw - iw * 0.86 - iw * 0.04, ch * 0.02, iw * 0.86, ch * 0.15)
	_name_size = int(name_rect.size.y * 0.85)
	_name = HudStyle.label("", _name_size, Color.WHITE, HudStyle.FONT_MEDIUM)
	HudStyle.place(_name, name_rect)
	info.add_child(_name)
	var body := Rect2(iw - iw * 0.74 - iw * 0.07, ch * 0.248, iw * 0.74, ch * 0.60)
	_description = HudStyle.label("", int(body.size.y * 0.175), INFO_TEXT, HudStyle.FONT_BOLD, HORIZONTAL_ALIGNMENT_LEFT)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	HudStyle.place(_description, body)
	info.add_child(_description)
	# card-stats: two boxes (49 % each) in the body's top 15.6 % of the info height, icons hang left of each box
	_stats = Control.new()
	_stats.mouse_filter = MOUSE_FILTER_IGNORE
	HudStyle.place(_stats, Rect2(body.position, Vector2(body.size.x, ch * 0.156)))
	info.add_child(_stats)
	var box_w := _stats.size.x * 0.49
	var box_h := _stats.size.y
	var box_font := int(box_h * 0.8)
	_stats.add_child(HudStyle.rect(STAT_BOX, Rect2(0, 0, box_w, box_h)))
	_dps = HudStyle.label("", box_font, Color.WHITE, HudStyle.FONT_BOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	HudStyle.place(_dps, Rect2(0, 0, box_w - box_w * 0.05, box_h))
	_stats.add_child(_dps)
	_dps_icon = HudStyle.picture(null, Rect2(box_h * 0.05, box_h * 0.05, box_h * 0.9, box_h * 0.9))   # icon inside, left
	_stats.add_child(_dps_icon)
	var hx := _stats.size.x - box_w
	_stats.add_child(HudStyle.rect(STAT_BOX, Rect2(hx, 0, box_w, box_h)))
	_health = HudStyle.label("", box_font, Color.WHITE, HudStyle.FONT_BOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	HudStyle.place(_health, Rect2(hx, 0, box_w - box_w * 0.05, box_h))
	_stats.add_child(_health)
	_health_icon = HudStyle.picture(null, Rect2(hx + box_h * 0.05, box_h * 0.05, box_h * 0.9, box_h * 0.9))
	_stats.add_child(_health_icon)
	# costs: price tag 24 % high anchored bottom-right at +3.7 % +6.2 %
	var ph := ch * 0.24
	var pw := ph * 190.0 / 60.0
	_price = HudStyle.picture(null, Rect2(iw - pw + iw * 0.037, ch - ph + ch * 0.062, pw, ph))
	info.add_child(_price)
	_cost = HudStyle.label("", int(ph * 0.5), HudStyle.WHITE, HudStyle.FONT_BOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	HudStyle.place(_cost, Rect2(20, 0, pw * 0.66 - 20, ph))
	_price.add_child(_cost)
	var tech_w := ph * 0.72
	_tech = HudStyle.label("", int(ph * 0.5), Color.BLACK, HudStyle.FONT_EXTRABOLD)
	HudStyle.place(_tech, Rect2(pw - tech_w - pw * 0.02, 0, tech_w, ph))
	_price.add_child(_tech)
	# .skill-hint: 250 wide vertical stack to the right of the description, growing upwards from its bottom
	_skill_hint = PanelContainer.new()
	_skill_hint.mouse_filter = MOUSE_FILTER_IGNORE
	_skill_hint.add_theme_stylebox_override("panel", _frame_style(HINT_BG))
	_skill_hint.visible = false
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	_skill_hint.add_child(stack)
	_skill_list = VBoxContainer.new()
	_skill_list.add_theme_constant_override("separation", 15)
	stack.add_child(_skill_list)
	_keyword_panel = PanelContainer.new()
	_keyword_panel.add_theme_stylebox_override("panel", _frame_style(FIELD_BG.lerp(HINT_BG, 0.5), FIELD_BG.lerp(HINT_BG, 0.5)))
	_keyword_list = VBoxContainer.new()
	_keyword_list.add_theme_constant_override("separation", 15)
	_keyword_panel.add_child(_keyword_list)
	stack.add_child(_keyword_panel)
	add_child(_skill_hint)


static func _frame_style(bg: Color, border: Color = BORDER_CYAN) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()   # $frame: padding 2, border 2 $border-cyan
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_content_margin_all(4)
	return style


static func _hint_label(text: String, color: Color, font: Font, bg: Variant = null) -> Control:
	var l := HudStyle.label(text, 15, color, font, HORIZONTAL_ALIGNMENT_LEFT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if bg == null:
		return l
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_content_margin_all(0)
	style.content_margin_left = 4
	style.content_margin_right = 4
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(l)
	return panel


## Fills the ability box for the card: spells list the card description, units their tooltip components,
## then the keyword descriptions (effect_<keyword>_description) without duplicates.
func _fill_skill_hint(card: Cards.CardDef, league: int) -> void:
	for child in _skill_list.get_children():
		child.queue_free()
	for child in _keyword_list.get_children():
		child.queue_free()
	var keywords := []
	var skills := 0
	var unit_id := unit_script(card)
	for ability in HudStyle.ability_details(unit_id):
		var vars: Array = ability.get("vars", [])
		for k in ability.get("keywords", []):
			if not keywords.has(str(k).to_lower()):
				keywords.append(str(k).to_lower())
		if ability.get("card_description", false):
			if card.is_spell():
				var text := Lang.format(Lang.first(["card_description_%s" % Lang.identifier(card.unit_id)], ""), vars, league)
				_skill_list.add_child(_hint_label(text, FONT_DEFAULT, HudStyle.FONT_MEDIUM))
				skills += 1
			continue
		var name := str(ability["name"]).to_lower()
		var skill := VBoxContainer.new()
		skill.add_theme_constant_override("separation", 2)
		var title := Lang.format(Lang.t("unitability_name_%s" % name), vars, league)
		skill.add_child(_hint_label("- %s -" % title.to_upper(), Color.WHITE, HudStyle.FONT_EXTRABOLD, FIELD_BG))
		skill.add_child(_hint_label(Lang.format(Lang.t("unitability_hint_%s" % name), vars, league), FONT_DEFAULT, HudStyle.FONT_MEDIUM))
		_skill_list.add_child(skill)
		skills += 1
	_skill_list.visible = skills > 0
	for k in keywords:
		_keyword_list.add_child(_hint_label(Lang.t("effect_%s_description" % k), FONT_DEFAULT, HudStyle.FONT_MEDIUM))
	_keyword_panel.visible = not keywords.is_empty()
	_skill_hint.visible = false
	_skill_hint.custom_minimum_size.x = SKILL_HINT_W


## Two-stage hint: the ability box opens after the slot has been hovered for a moment.
func refresh(now: int) -> void:
	if not visible or _hover_started_ms < 0:
		return
	if now - _hover_started_ms >= SKILL_HINT_DELAY_MS:
		_skill_hint.visible = true
		# wrapped labels settle over a few frames: shrink to the content each frame, keep the fixed width
		_skill_hint.reset_size()
		_skill_hint.size.x = SKILL_HINT_W
		# bottom-left corner at the description's right edge (ParentAnchor caRight, Anchor caBottomLeft)
		var info: Control = _description.get_parent()
		var anchor: Vector2 = info.get_parent().position + info.position + _description.position + _description.size
		_skill_hint.position = anchor + Vector2(_description.size.x * 0.06, 0) - Vector2(0, _skill_hint.size.y)


func show_slot(slot: Commander.DeckSlot, commander: Commander, now: int = 0) -> void:
	var card := slot.card
	visible = true
	_hover_started_ms = now
	_fill_skill_hint(card, slot.league)
	var kind := "Spell" if card.is_spell() else ("Spawner" if card.is_spawner() else "Drop")
	_shadow.texture = HudStyle.tex(CARD + "CardShadow%s.png" % kind)
	_frame.texture = HudStyle.card_frame(card)
	_icon.texture = HudStyle.card_icon(card)
	_special.texture = HudStyle.tex(CARD + "LegendaryIndicator.png") if card.legendary else (HudStyle.tex(CARD + "EpicIndicator.png") if card.epic else null)
	_league.texture = HudStyle.tex("Shared/LeagueIcons/League%d.tga" % clampi(slot.league, 1, 5))
	_level.texture = HudStyle.tex(CARD + "%d.png" % clampi(slot.level, 1, 5))
	var colors := HudStyle.color_string(card.colors)
	var info_kind := "Spell" if card.is_spell() else ("Spawner" if card.is_spawner() else "Unit")
	_info_bg.texture = HudStyle.tex(CARD + "CardBackground%s%s.png" % [colors, info_kind])
	_name.text = Lang.card_name(card)
	HudStyle.fit(_name, _name_size)
	_stats.visible = not card.is_spell()
	if card.is_spell():
		_description.text = spell_text(card, slot.league)
		_description.add_theme_font_size_override("font_size", int(_description.size.y * 0.175))
		_description.position.y = _stats.position.y
	else:
		var unit_id := unit_script(card)
		_description.text = skill_list(unit_id, slot.league)
		_description.add_theme_font_size_override("font_size", int(_description.size.y * 0.175))   # live client: same size as spell text
		_description.position.y = _stats.position.y + _description.size.y * 0.30   # .skills padding-top
		var stats := HudStyle.unit_stats(unit_id, slot.league, slot.level)
		var squad := squad_size(card)
		var dps := stats.damage() / (stats.cooldown() / 1000.0) if stats.can_attack() and stats.cooldown() > 0 else 0.0
		_dps.text = str(int(dps * squad)) if dps != 0.0 else "-"
		var mask := stats.damage_type()
		var dt := "dtSiege" if mask & SimConstants.DamageType.SIEGE else ("dtRanged" if mask & SimConstants.DamageType.RANGED else "dtMelee")
		_dps_icon.texture = HudStyle.tex(CARD + "Attack_%s.png" % dt)
		_health.text = str(int(stats.max_health * squad))
		var armor_key: String = SimConstants.ARMOR_NAMES.find_key(stats.armor())
		_health_icon.texture = HudStyle.tex(CARD + "Armor%s.png" % armor_key)
	_price.texture = HudStyle.tex(CARD + ("PriceTagSpawner.png" if card.is_spawner() else "PriceTag.png"))
	var cost := commander.gold_cap() if card.epic else (slot.wood_cost if card.is_spawner() else slot.gold_cost)
	_cost.text = str(roundi(cost))
	_tech.visible = not card.is_spawner()
	_tech.text = HudStyle.roman(card.tier)


func hide_card() -> void:
	visible = false
	_hover_started_ms = -1
	_skill_hint.visible = false


## TCardInfo.UnitFilename: the unit a drop / spawner / building card produces (its own script for spells).
static func unit_script(card: Cards.CardDef) -> String:
	if card.is_spell():
		return card.unit_id
	var pattern := str(UnitDb.raw(card.unit_id)["values"].get("eiWelaUnitPattern", {}).get("0", ""))
	return pattern.replace("\\", "/").trim_suffix(".ets") if pattern != "" else card.unit_id


## eiWelaCount of the drop / spawner group (Footman 4), 1 otherwise.
static func squad_size(card: Cards.CardDef) -> int:
	return int(UnitDb.raw(card.unit_id)["values"].get("eiWelaCount", {}).get("0", 1))


## TCardInfo.SkillList: unitability_name_<name> of the unit's tooltip components, joined by ", ".
static func skill_list(unit_id: String, league: int) -> String:
	var names := []
	for ability in HudStyle.ability_details(unit_id):
		if ability.get("card_description", false):
			continue
		names.append(Lang.format(Lang.t("unitability_name_%s" % str(ability["name"]).to_lower()), ability.get("vars", []), league))
	return ", ".join(names)


## TCardInfo.ShortDescription: card_short_description_<ident> with the IsCardDescription tooltip's variables.
static func spell_text(card: Cards.CardDef, league: int) -> String:
	var text := Lang.first(["card_short_description_%s" % Lang.identifier(card.unit_id)], "")
	for ability in HudStyle.ability_details(card.unit_id):
		if ability.get("card_description", false):
			text = Lang.format(text, ability.get("vars", []), league)
	return text
