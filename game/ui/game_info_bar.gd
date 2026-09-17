class_name GameInfoBar
extends Control
## Top centre: clock and both nexus health bars on top_panel.png (docs/hud.md "GameInfoBar").

const WIDTH := 570.0
const HEIGHT := 56.0
const BAR_W := 200.0
const BAR_H := 42.0

var _clock: Label
var _left_clip: Control
var _left_bar: TextureRect
var _right_clip: Control
var _left_caption: Label
var _right_caption: Label


func _ready() -> void:
	size = Vector2(WIDTH, HEIGHT)
	mouse_filter = MOUSE_FILTER_STOP
	add_child(HudStyle.blur(Rect2(0, 0, WIDTH, HEIGHT)))   # .game-info Blur : True
	var bar_y := (HEIGHT - BAR_H) / 2.0
	# left bar: right edge at 37.5 %, shrinks leftwards; right bar starts at 62.5 %
	_left_clip = Control.new()
	_left_clip.clip_contents = true
	HudStyle.place(_left_clip, Rect2(WIDTH * 0.375 - BAR_W, bar_y, BAR_W, BAR_H))
	_left_bar = HudStyle.picture(HudStyle.tex("HUD/GameStatePanel/blue_shield_hp.png"), Rect2(0, 0, BAR_W, BAR_H))
	_left_clip.add_child(_left_bar)
	add_child(_left_clip)
	_right_clip = Control.new()
	_right_clip.clip_contents = true
	HudStyle.place(_right_clip, Rect2(WIDTH * 0.625, bar_y, BAR_W, BAR_H))
	_right_clip.add_child(HudStyle.picture(HudStyle.tex("HUD/GameStatePanel/red_shield_hp.png"), Rect2(0, 0, BAR_W, BAR_H)))
	add_child(_right_clip)
	add_child(HudStyle.picture(HudStyle.tex("HUD/GameStatePanel/top_panel.png"), Rect2(0, 0, WIDTH, HEIGHT)))
	var clock_w := WIDTH * 0.193
	_clock = HudStyle.label("00:00", int(HEIGHT * 0.53), HudStyle.WHITE, HudStyle.FONT_SEMIBOLD)
	HudStyle.place(_clock, Rect2((WIDTH - clock_w) / 2.0, 0, clock_w, HEIGHT))
	add_child(_clock)
	_left_caption = HudStyle.outline(HudStyle.label("100%", 15, HudStyle.WHITE, HudStyle.FONT_BOLD), 1)
	HudStyle.place(_left_caption, Rect2(WIDTH * 0.375 - BAR_W - 6, HEIGHT - 16 - 20, 111, 20))
	add_child(_left_caption)
	_right_caption = HudStyle.outline(HudStyle.label("100%", 15, HudStyle.WHITE, HudStyle.FONT_BOLD), 1)
	HudStyle.place(_right_caption, Rect2(WIDTH * 0.625 + BAR_W - 111 + 6, HEIGHT - 16 - 20, 111, 20))
	add_child(_right_caption)


func refresh(sim: Simulation, own_team: int) -> void:
	_clock.text = spawn_timer(sim)
	var left_team := own_team
	var right_team := Simulation.TEAM_RED if own_team == Simulation.TEAM_BLUE else Simulation.TEAM_BLUE
	_set_bar(_left_clip, _left_caption, sim, left_team, true)
	_set_bar(_right_clip, _right_caption, sim, right_team, false)


## Before the first game tick: tenths of a second ("0.x" up to 0.9, else whole seconds); after: mm:ss.
static func spawn_timer(sim: Simulation) -> String:
	if not sim.game_started:
		var tenths := ceili((sim.next_game_tick_at - sim.time_ms) / 100.0)
		if tenths <= 9:
			return "0.%d" % tenths
		return str(ceili(tenths / 10.0))
	return HudStyle.int_to_time(sim.tick_counter)


static func health_percent(e: SimEntity) -> int:
	if e == null or e.max_health <= 0.0:
		return 0
	var p := ceili(e.health / e.max_health * 100.0)
	if p >= 100 and e.health < e.max_health:
		return 99
	return clampi(p, 0, 100)


func _set_bar(clip: Control, caption: Label, sim: Simulation, team: int, anchored_right: bool) -> void:
	var nexus: SimEntity = sim.entities.get(sim.nexus_ids.get(team, -1))
	var percent := health_percent(nexus)
	caption.text = "%d%%" % percent
	var w := BAR_W * percent / 100.0
	clip.size.x = w
	if anchored_right:
		clip.position.x = WIDTH * 0.375 - w
		_left_bar.position.x = w - BAR_W
