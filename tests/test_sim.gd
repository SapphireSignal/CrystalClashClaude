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
	var nexus := sim.spawn("Units/Neutral/NexusLevel1", Simulation.TEAM_BLUE, Vector2(-96, -23))
	var lost := []
	sim.team_lost.connect(func(t): lost.append(t))
	sim.deal_damage(nexus, 1e9, SimConstants.DamageType.TRUE, nexus)
	runner.check(sim.finished, "game finished")
	runner.check_eq(sim.winner_team, Simulation.TEAM_RED, "red wins")
	runner.check_eq(lost, [Simulation.TEAM_BLUE], "blue lost signal")
