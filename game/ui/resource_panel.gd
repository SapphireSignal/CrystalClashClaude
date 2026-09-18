class_name ResourcePanel
extends Control
## Bottom left: gold / wood / income rows and the tech tier book (docs/hud.md "RessourcePanel").

const SIZE := 302.0
const CONTENT := 281.0
const CONTENT_Y := 21.0
const ROW_X := 49.0
const ROW_W := 214.0
const ROW_H := 30.0
const ROW_Y := [18.0, 63.0, 108.0]   # content coordinates: the art's dark rows sit at panel y 39 / 84 / 129
const ROW_TEXT_PAD := 37.0           # Padding-Right 120ch = 1.2 x the row height (core_game.scss:375; ch = own rect height, Engine.GUI.pas:7005)
const ICON_H := ROW_H * 1.1          # icon "Size auto 110%", centred 10 px inside the row's right end
const ICON_CX := ROW_X + ROW_W - 16.0   # icon centre 16 px inside the row end (measured: the row shows ~5 px right of the icon)
const TIER_RECT := Rect2(88, 177, 56, 56)   # tech-wrapper 31.5% 63% of the 281 content

var _gold: Label
var _wood: Label
var _income: Label
var _income_fill: ColorRect
var _tier: Label
var _tech_timer: Label


func _ready() -> void:
	size = Vector2(SIZE, SIZE)
	mouse_filter = MOUSE_FILTER_STOP
	add_child(HudStyle.blur(Rect2(0, CONTENT_Y, CONTENT, CONTENT)))   # .content Blur : True
	add_child(HudStyle.picture(HudStyle.tex("HUD/RessourcePanel/ressource_panel.png"), Rect2(0, 0, SIZE, SIZE)))
	var content := Control.new()
	HudStyle.place(content, Rect2(0, CONTENT_Y, CONTENT, CONTENT))
	content.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(content)
	_income_fill = HudStyle.rect(HudStyle.CYAN, Rect2(ROW_X, ROW_Y[2], 0, ROW_H))
	content.add_child(_income_fill)
	_gold = _row(content, 0, "HUD/RessourcePanel/mana.png")
	_wood = _row(content, 1, "HUD/RessourcePanel/essence.png")
	_income = _row(content, 2, "HUD/RessourcePanel/income_upgrade.png")
	# .tech-wrapper .caption Fontsize 60 % of the 56 px wrapper (core_game.scss:438-447); Fontsize % = em size in px.
	_tier = HudStyle.label("I", int(TIER_RECT.size.y * 0.6), HudStyle.WHITE, HudStyle.FONT_EXTRABOLD)
	HudStyle.place(_tier, TIER_RECT)
	content.add_child(_tier)
	# tech-timer: Position 105% 2% from the wrapper centre, anchored left, 18 high, font 100 %.
	_tech_timer = HudStyle.label("", 18, HudStyle.WHITE, HudStyle.FONT_SEMIBOLD, HORIZONTAL_ALIGNMENT_LEFT)
	var wrapper_centre := TIER_RECT.position + TIER_RECT.size * 0.5
	HudStyle.place(_tech_timer, Rect2(wrapper_centre.x + TIER_RECT.size.x * 1.05, wrapper_centre.y + TIER_RECT.size.y * 0.02 - 9, 100, 18))
	content.add_child(_tech_timer)


func _row(content: Control, index: int, icon: String) -> Label:
	var y: float = ROW_Y[index]
	var l := HudStyle.label("", int(ROW_H * 0.7), HudStyle.WHITE, HudStyle.FONT_SEMIBOLD, HORIZONTAL_ALIGNMENT_RIGHT)   # .caption Fontsize 70 % of the row (core_game.scss:376-382), em size = px (Engine.GfxApi.pas:2186)
	HudStyle.place(l, Rect2(ROW_X, y, ROW_W - ROW_TEXT_PAD, ROW_H))   # caption left of the icon square
	content.add_child(l)
	var icon_rect := Rect2(ICON_CX - ICON_H * 0.5, y + (ROW_H - ICON_H) * 0.5, ICON_H, ICON_H)
	content.add_child(HudStyle.picture(HudStyle.tex(icon), icon_rect))
	return l


func refresh(sim: Simulation, own_team: int) -> void:
	var c: Commander = sim.commanders[own_team]
	_gold.text = "%d / %d (+%d)" % [int(c.gold), int(c.gold_cap()), int(c.income())]
	var wood_income := c.income() if c.gold >= c.gold_cap() else 0.0   # RIncome.Wood: overflow at the cap
	_wood.text = "%d" % int(c.wood)
	if wood_income > 0.0:
		_wood.text += " (+%d)" % int(wood_income)
	if c.income_upgrades >= SimConstants.INCOME_UPGRADE_CAP:
		_income.text = "Max"
		_income_fill.size.x = ROW_W
	else:
		_income.text = "%d / %d" % [int(c.spent_wood), int(c.income_upgrade_cost())]
		_income_fill.size.x = ROW_W * clampf(c.spent_wood / c.income_upgrade_cost(), 0.0, 1.0)
	_tier.text = HudStyle.roman(c.tier)
	var seconds := time_to_next_tier(sim, c)
	_tech_timer.visible = seconds >= 0
	_tech_timer.text = HudStyle.int_to_time(seconds)


## eiGameEventTimeTo for tech_level_2 / tech_level_3: seconds until the event, -1 at the last tier.
static func time_to_next_tier(sim: Simulation, c: Commander) -> int:
	var idx := clampi(sim.league, 1, 5) - 1
	match c.tier:
		1: return maxi(0, SimConstants.TECH_LEVEL_2_SECONDS[idx] - sim.tick_counter)
		2: return maxi(0, SimConstants.TECH_LEVEL_3_SECONDS[idx] - sim.tick_counter)
	return -1
