## Simulation tests against numbers from the original source (docs/original-architecture.md).
extends RefCounted
var runner


func test_armor_formula() -> void:
	var A := SimConstants.ArmorType
	var D := SimConstants.DamageType
	runner.check_near(SimConstants.apply_armor(100.0, A.UNARMORED, D.MELEE), 100.0, "unarmored takes full")
	runner.check_near(SimConstants.apply_armor(100.0, A.LIGHT, D.MELEE), 85.0, "light 0.85")
	runner.check_near(SimConstants.apply_armor(100.0, A.MEDIUM, D.MELEE), 80.0, "medium 0.8 vs melee")
	runner.check_near(SimConstants.apply_armor(100.0, A.MEDIUM, D.RANGED), 70.0, "medium 0.7 vs ranged")
	runner.check_near(SimConstants.apply_armor(100.0, A.HEAVY, D.MELEE), 65.0, "heavy 0.7 - 5")
	runner.check_near(SimConstants.apply_armor(7.0, A.HEAVY, D.MELEE), 1.0, "heavy floors at 1")
	runner.check_near(SimConstants.apply_armor(100.0, A.FORTIFIED, D.RANGED), 100.0, "fortified normal")
	runner.check_near(SimConstants.apply_armor(100.0, A.FORTIFIED, D.SIEGE), 400.0, "fortified x4 vs siege")
	runner.check_near(SimConstants.apply_armor(100.0, A.HEAVY, D.IGNORE_ARMOR), 100.0, "ignore armor")
	runner.check_near(SimConstants.apply_armor(1.0, A.HEAVY, D.MELEE), 1.0, "amount <= 1 untouched")


func test_unit_data_footman() -> void:
	var e := SimEntity.new()
	e.setup("Units/White/Footman", 4)
	runner.check_near(e.max_health, 32.0, "footman hp")
	runner.check_near(e.attack_damage(), 13.0, "footman dmg")
	runner.check_eq(e.attack_cooldown(), 2000, "footman cooldown")
	runner.check_near(e.attack_range(), 1.0, "footman range")
	runner.check_eq(e.armor, SimConstants.ArmorType.MEDIUM, "footman armor")
	runner.check_near(e.collision_radius, 0.55, "footman radius")
	runner.check_near(e.speed, 0.004, "default speed 4 u/s")
	runner.check(e.has("upMelee"), "footman is melee")


func test_league_arrays() -> void:
	var e := SimEntity.new()
	e.setup("Units/Neutral/Nexus", 3)
	runner.check_near(e.attack_damage(), 120.0, "nexus dmg league 3")
	runner.check_eq(e.bb.get_int("eiResourceCap.reWelaCharge"), 16, "nexus ammo league 3")
	e = SimEntity.new()
	e.setup("Units/Neutral/Nexus", 1)
	runner.check_near(e.attack_damage(), 110.0, "nexus dmg league 1")


func test_economy_tick() -> void:
	var sim := Simulation.new(1, 4)
	var c: Simulation.Commander = sim.commanders[Simulation.TEAM_RED]
	runner.check_near(c.gold, 300.0, "starting gold")
	runner.check_near(c.wood, 1600.0, "starting wood")
	while sim.time_ms < SimConstants.GAME_WARMING_MS:
		sim.step()
	runner.check_eq(sim.tick_counter, 1, "first tick at warm-up end")
	runner.check(sim.game_started, "game started on first tick")
	runner.check_near(c.gold, 310.0, "income 10 on first tick")
	for i in 20:
		while sim.time_ms < SimConstants.GAME_WARMING_MS + SimConstants.GAME_TICK_MS * (i + 1):
			sim.step()
	runner.check_eq(sim.tick_counter, 21, "21 ticks")
	runner.check_near(c.gold, 400.0, "gold capped at 400")
	runner.check_near(c.wood, 1600.0 + 110.0, "overflow gold becomes wood")


func test_tech_events() -> void:
	var sim := Simulation.new(1, 4)
	var events: Array = []
	sim.game_event.connect(func(n): events.append(n))
	while sim.tick_counter < 240:
		sim.step()
	runner.check(events.has("tech_level_2"), "tech 2 at 4 min for league 4")
	runner.check(not events.has("tech_level_3"), "tech 3 not yet")
	runner.check_eq(sim.commanders[Simulation.TEAM_RED].tier, 2, "tier raised to 2")


func test_melee_fight_deterministic() -> void:
	var a := _run_duel(7)
	var b := _run_duel(7)
	runner.check_eq(a, b, "same seed gives same result")


func _run_duel(seed: int) -> Array:
	var sim := Simulation.new(seed, 4)
	sim.drop_squad("Units/White/Footman", Simulation.TEAM_RED, Vector2(5, -23), 4)
	sim.drop_squad("Units/White/Archer", Simulation.TEAM_BLUE, Vector2(-5, -23), 2)
	var steps := 0
	while sim.alive_entities(Simulation.TEAM_RED).size() > 0 and sim.alive_entities(Simulation.TEAM_BLUE).size() > 0 and steps < 5000:
		sim.step()
		steps += 1
	var survivors := sim.alive_entities()
	var out := [steps, survivors.size()]
	for e in survivors:
		out.append(e.team)
		out.append(snappedf(e.health, 0.01))
	return out


func test_attack_timing() -> void:
	var sim := Simulation.new(3, 4)
	var footman := sim.spawn("Units/White/Footman", Simulation.TEAM_RED, Vector2(1.0, -23))
	var archer := sim.spawn("Units/White/Archer", Simulation.TEAM_BLUE, Vector2(-0.5, -23))
	archer.speed = 0.0
	var hits: Array = []
	var on_hit := func(att, _t, dmg): if att == footman: hits.append([sim.time_ms, dmg])
	sim.attack_fired.connect(on_hit)
	while hits.size() < 2 and sim.time_ms < 10000:
		sim.step()
	sim.attack_fired.disconnect(on_hit)  # the lambda captures sim; break the reference cycle
	runner.check_eq(hits.size(), 2, "footman hit twice")
	if hits.size() == 2:
		runner.check(hits[0][0] >= 300, "first hit after actionpoint 300 ms")
		var gap: int = hits[1][0] - hits[0][0]
		runner.check(gap >= 2300 and gap < 2300 + SimConstants.TICK_MS, "cooldown 2000 + actionpoint 300 between hits (got %d)" % gap)
		runner.check_near(hits[0][1], 13.0, "footman raw damage 13")


func test_nexus_death_ends_game() -> void:
	var sim := Simulation.new(1, 4)
	sim.spawn_bases()
	var nexus := sim.enemy_nexus(Simulation.TEAM_RED)
	runner.check_eq(nexus.team, Simulation.TEAM_BLUE, "enemy nexus of red is blue")
	runner.check_eq(nexus.position, Vector2(-96, -23), "blue nexus at -96,-23 on Single")
	runner.check_near(nexus.max_health, 3750.0, "nexus hp league 4")
	var lost := []
	sim.team_lost.connect(func(t): lost.append(t))
	sim.deal_damage(nexus, 1e9, SimConstants.DamageType.TRUE, nexus)
	runner.check(sim.finished, "game finished")
	runner.check_eq(sim.winner_team, Simulation.TEAM_RED, "red wins")
	runner.check_eq(lost, [Simulation.TEAM_BLUE], "blue lost signal")


func test_pathfinding_grid() -> void:
	var m := SimMap.load_map(SimMap.SINGLE)
	var pf := m.pathfinding
	runner.check(not pf.is_blocked(pf.index_of(pf.tile_of(Vector2(0, -23)))), "lane center walkable")
	runner.check(pf.is_blocked(pf.index_of(pf.tile_of(Vector2(0, 40)))), "outside walkzone blocked")
	var path := pf.compute_path(1, Vector2(0, -23), Vector2(10, -23), 0, 0.004, false, false, Lanes.NORMAL)
	runner.check(path.size() >= 12 and path.size() <= 14, "straight path of ~13 tiles (got %d)" % path.size())
	# a second unit planning the same corridor at the same time must be pushed aside by the reservations
	var path2 := pf.compute_path(2, Vector2(0, -23), Vector2(10, -23), 0, 0.004, false, false, Lanes.NORMAL)
	runner.check(path2.size() > 0, "second unit finds a path")
	runner.check(path2 != path, "second unit avoids reserved tiles")
	pf.cancel_path(1)
	var path3 := pf.compute_path(3, Vector2(0, -23), Vector2(10, -23), 0, 0.004, false, false, Lanes.NORMAL)
	runner.check_eq(path3, path, "after release the straight path is free again")


func test_lane_waypoints() -> void:
	var lanes := Lanes.single()
	var wp = lanes.lanes[0].next_waypoint(Vector2(-80, -23), Lanes.NORMAL)
	runner.check_eq(wp, Vector2(-60, -23), "first gate ahead when walking +x")
	wp = lanes.lanes[0].next_waypoint(Vector2(0, -23), Lanes.NORMAL)
	runner.check_eq(wp, Vector2(60, -23), "second gate ahead from center")
	wp = lanes.lanes[0].next_waypoint(Vector2(80, -23), Lanes.NORMAL)
	runner.check_eq(wp, null, "no gate ahead near red nexus")
	wp = lanes.lanes[0].next_waypoint(Vector2(80, -23), Lanes.REVERSE)
	runner.check_eq(wp, Vector2(60, -23), "walking -x sees the +60 gate first")


func test_unit_walks_lane_to_enemy_nexus() -> void:
	var sim := Simulation.new(5, 4)
	sim.spawn_bases()
	var squad := sim.drop_squad("Units/White/Footman", Simulation.TEAM_BLUE, Vector2(-80, -23), 4)
	# red has no units: footmen walk ~113 units until the red lanetower (x=48, range 15, 100 dmg) shoots them
	var hits: Array = []
	var on_hit := func(att, t, d): if att.has("upLanetower") and t.has("upMelee"): hits.append([sim.time_ms, d, t.position])
	sim.attack_fired.connect(on_hit)
	while hits.is_empty() and sim.time_ms < 120000:
		sim.step()
	sim.attack_fired.disconnect(on_hit)
	runner.check(not hits.is_empty(), "footmen walked into the red lanetower's range")
	if not hits.is_empty():
		# 113 units at 4 u/s = 28.25 s, plus 1 s summoning sickness
		runner.check(hits[0][0] > 28000 and hits[0][0] < 32000, "arrival time matches 4 u/s (got %d ms)" % hits[0][0])
		runner.check_near(hits[0][1], 100.0, "lanetower damage 100")
		var p: Vector2 = hits[0][2]
		runner.check(p.x > 30.0 and p.y > -36 and p.y < -10, "footman was on the lane inside the walkzone")
	for f in squad:
		runner.check(f.position.y > -36 and f.position.y < -10, "footman stayed inside the walkzone")
