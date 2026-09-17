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
	var c: Commander = sim.commanders[Simulation.TEAM_RED]
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


func test_build_zone_geometry() -> void:
	var m := SimMap.load_map(SimMap.SINGLE)
	var zones := m.build_zones()
	runner.check_eq(zones.size(), 2, "single map has two build zones")
	var blue: BuildZone = zones[0]
	runner.check_eq(blue.team, 1, "zone 0 is blue")
	runner.check_eq(blue.left(), Vector2(0, 1), "left is orthogonal of front (1,0)")
	runner.check_eq(blue.center_of_field(Vector2i(0, 0)), Vector2(-108.7, -30), "field (0,0) center")
	runner.check_eq(blue.position_to_coord(Vector2(-108.7, -30)), Vector2i(0, 0), "coord round trip")
	runner.check_eq(blue.spawn_slots().size(), 20, "20 usable slots")
	runner.check(blue.is_banned(Vector2i(7, 2)), "corner banned")
	runner.check(blue.is_free(Vector2i(3, 1)), "middle field free")
	runner.check_eq(blue.spawn_position_for_field(Vector2i(3, 1)), Vector2(-90, -24), "spawn offset follows grid offset")
	runner.check_eq(blue.spawn_position_for_field(Vector2i(4, 1)), Vector2(-90, -22), "mirrored field mirrored offset")


func test_spawner_waves() -> void:
	var sim := Simulation.new(11, 4)
	sim.spawn_bases()
	runner.check_eq(sim.place_spawner("Units/White/FootmanSpawner", Simulation.TEAM_BLUE, 0, Vector2i(0, 0)), null, "corner rejected")
	runner.check_eq(sim.place_spawner("Units/White/FootmanSpawner", Simulation.TEAM_RED, 0, Vector2i(3, 1)), null, "wrong team rejected")
	var spawner := sim.place_spawner("Units/White/FootmanSpawner", Simulation.TEAM_BLUE, 0, Vector2i(3, 1))
	runner.check(spawner != null, "spawner placed")
	runner.check_eq(sim.place_spawner("Units/White/FootmanSpawner", Simulation.TEAM_BLUE, 0, Vector2i(3, 1)), null, "occupied rejected")
	runner.check_eq(sim.alive_entities(Simulation.TEAM_BLUE).size(), 3, "no units before game start (nexus, tower, spawner)")
	var spawned: Array = []
	var on_spawn := func(e): if e.has("upMelee"): spawned.append(sim.time_ms)
	sim.entity_spawned.connect(on_spawn)
	while sim.tick_counter < 1:
		sim.step()
	runner.check_eq(spawned.size(), 4, "squad of 4 footmen at game start")
	if spawned.size() == 4:
		var first := sim.entities.values().filter(func(e): return e.has("upMelee"))
		var center := Vector2.ZERO
		for f in first:
			center += f.position
		center /= 4.0
		runner.check(center.distance_to(Vector2(-90, -24)) < 0.5, "squad centered on the spawn target (%s)" % center)
	# one field per zone per wave, 20 fields per cycle: the spawner fires again within 20 waves (40 ticks)
	while sim.tick_counter < 41:
		sim.step()
	runner.check_eq(spawned.size(), 8, "spawner fired exactly once more within a full rotation")
	while sim.tick_counter < 81:
		sim.step()
	runner.check_eq(spawned.size(), 12, "and once per following rotation")
	sim.entity_spawned.disconnect(on_spawn)


func test_card_formulas() -> void:
	runner.check_near(Cards.base_cost(1, false, false, false), 100.0, "tier1 drop 100 gold")
	runner.check_near(Cards.base_cost(2, false, false, false), 150.0, "tier2 drop 150")
	runner.check_near(Cards.base_cost(3, true, false, false), 300.0, "tier3 legendary 300")
	runner.check_near(Cards.base_cost(1, false, true, false), 80.0, "tier1 spell 80")
	runner.check_near(Cards.base_cost(1, false, false, true), 800.0, "tier1 spawner 800 wood")
	runner.check_near(Cards.base_cost(3, false, false, true), 2400.0, "tier3 spawner 2400 wood")
	runner.check_eq(Cards.charge_cooldown(1, 4, 5, false, false), 25000, "L4 lvl5 tier1 charge cooldown")
	runner.check_eq(Cards.charge_cooldown(2, 1, 1, false, false), 55500, "tier2 x1.5")
	runner.check_eq(Cards.charge_cooldown(3, 5, 5, true, false), 110000, "tier3 legendary x2 x2.5")
	runner.check_eq(Cards.charge_cooldown(1, 4, 5, false, true), 150000, "tier1 spawner x6")
	runner.check_eq(Cards.charge_count(1, 4, false), 4, "tier1 league4 = 4 charges")
	runner.check_eq(Cards.charge_count(3, 4, false), 2, "tier3 league4 = 2 charges")
	runner.check_eq(Cards.charge_count(3, 5, true), 2, "legendary league5 = 2")
	var footman := Cards.by_script("Units/White/FootmanDrop")
	runner.check_eq(footman.name, "Footman", "english name from Lang/cards.csv")
	runner.check_eq(footman.type, "ctDrop", "footman drop type")
	runner.check(Cards.by_script("Units/White/DefenderDrop").legendary, "defender is legendary")
	runner.check_eq(Cards.all().size(), 160, "160 registered cards")


func test_play_cards_and_economy() -> void:
	var sim := Simulation.new(2, 4)
	sim.spawn_bases()
	var c: Commander = sim.commanders[Simulation.TEAM_BLUE]
	c.set_deck(["Units/White/FootmanDrop", "Units/White/FootmanSpawner", "Units/White/MarksmanDrop", "Units/White/DefenderDrop"])
	runner.check_eq(c.slots[0].charges, 4, "footman starts with 4 charges")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, Vector2(-50, -23)), Simulation.PlayResult.OK, "drop footmen in drop zone")
	runner.check_near(c.gold, 200.0, "paid 100 gold")
	runner.check_near(c.wood, 1700.0, "gold spent becomes wood")
	runner.check_eq(c.slots[0].charges, 3, "one charge used")
	runner.check_eq(c.slots[0].recharge_at, sim.time_ms + 25000, "recharge started")
	runner.check_eq(sim.alive_entities(Simulation.TEAM_BLUE).filter(func(e): return e.has("upMelee")).size(), 4, "4 footmen spawned")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, Vector2(-50, 40)), Simulation.PlayResult.BAD_TARGET, "outside drop zone")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 2, Vector2(-50, -23)), Simulation.PlayResult.NOT_READY, "tier 2 card locked at tier 1")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 3, Vector2(-50, -23)), Simulation.PlayResult.NOT_READY, "tier 3 legendary locked at tier 1")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 1, [0, Vector2i(3, 1)]), Simulation.PlayResult.OK, "spawner placed for 800 wood")
	runner.check_near(c.wood, 900.0, "wood paid")
	runner.check_near(c.spent_wood, 800.0, "spent wood tracked")
	runner.check_eq(c.income_upgrades, 0, "no income upgrade yet")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 1, [0, Vector2i(3, 1)]), Simulation.PlayResult.BAD_TARGET, "field occupied")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 1, [0, Vector2i(4, 1)]), Simulation.PlayResult.OK, "second spawner")
	runner.check_eq(c.income_upgrades, 1, "1600 spent wood bought the 1500 upgrade")
	runner.check_near(c.spent_wood, 100.0, "remainder kept")
	runner.check_near(c.income(), 12.0, "income now 12")
	runner.check_near(c.income_upgrade_cost(), 1750.0, "next upgrade costs 1750")
	# charges come back after the cooldown
	var t0 := sim.time_ms
	while sim.time_ms < t0 + 25000 + SimConstants.TICK_MS:
		sim.step()
	runner.check_eq(c.slots[0].charges, 4, "charge regenerated after 25 s")
	runner.check_eq(c.slots[0].recharge_at, -1, "recharging stops at cap")
	# tier 3 unlocks the legendary, and only one may be alive
	c.raise_tier(3)
	c.gold = 1000.0
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 3, Vector2(-50, -23)), Simulation.PlayResult.OK, "defender dropped")
	runner.check_eq(c.slots[3].charges, 0, "legendary has a single charge at league 4")
	c.slots[3].charges = 1
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 3, Vector2(-50, -23)), Simulation.PlayResult.LEGENDARY_ALIVE, "second legendary refused while one lives")


func test_sandbox_free_cards() -> void:
	var sim := Simulation.new(2, 4)
	var c: Commander = sim.commanders[Simulation.TEAM_RED]
	c.free_cards = true
	c.set_deck(["Units/White/FootmanDrop"])
	for i in 6:
		runner.check_eq(sim.play_card(Simulation.TEAM_RED, 0, Vector2(50, -23)), Simulation.PlayResult.OK, "free play %d" % i)
	runner.check_near(c.gold, 300.0, "sandbox pays nothing")


func test_archer_projectile() -> void:
	var sim := Simulation.new(4, 4)
	var archer := sim.spawn("Units/White/Archer", Simulation.TEAM_BLUE, Vector2(-5, -23))
	var footman := sim.spawn("Units/White/Footman", Simulation.TEAM_RED, Vector2(4, -23))
	footman.speed = 0.0
	footman.summoning_sick_until = 1 << 40   # target dummy: never thinks
	var launched: Array = []
	var hits: Array = []
	var on_launch := func(p): launched.append([sim.time_ms, p.speed])
	var on_removed := func(p, hit): hits.append([sim.time_ms, hit, p.position])
	sim.projectile_spawned.connect(on_launch)
	sim.projectile_removed.connect(on_removed)
	while hits.is_empty() and sim.time_ms < 5000:
		sim.step()
	sim.projectile_spawned.disconnect(on_launch)
	sim.projectile_removed.disconnect(on_removed)
	runner.check_eq(launched.size(), 1, "archer launched one projectile")
	runner.check_eq(hits.size(), 1, "projectile arrived")
	if launched.size() == 1 and hits.size() == 1:
		runner.check_near(launched[0][1], 0.02, "archer projectile speed 20 u/s")
		runner.check(hits[0][1], "projectile hit the footman")
		var flight: int = hits[0][0] - launched[0][0]
		# 9 units at 20 u/s = 450 ms, quantised to 32 ms ticks
		runner.check(flight >= 448 and flight <= 480, "flight time ~450 ms (got %d)" % flight)
		runner.check_near(footman.health, 32.0 - 20.0 * 0.7, "20 ranged dmg vs medium armor = 14")
		runner.check_eq(hits[0][2], footman.position, "impact at the target position")


func test_projectile_misses_dead_target() -> void:
	var sim := Simulation.new(4, 4)
	var archer := sim.spawn("Units/White/Archer", Simulation.TEAM_BLUE, Vector2(-5, -23))
	var footman := sim.spawn("Units/White/Footman", Simulation.TEAM_RED, Vector2(4, -23))
	footman.speed = 0.0
	while sim.projectiles.is_empty() and sim.time_ms < 5000:
		sim.step()
	runner.check_eq(sim.projectiles.size(), 1, "projectile in flight")
	sim.deal_damage(footman, 1e6, SimConstants.DamageType.TRUE, archer)
	var results: Array = []
	var on_removed := func(_p, hit): results.append(hit)
	sim.projectile_removed.connect(on_removed)
	while sim.projectiles.size() > 0 and sim.time_ms < 8000:
		sim.step()
	sim.projectile_removed.disconnect(on_removed)
	runner.check_eq(results, [false], "projectile flew to the last position and fizzled")


func test_drop_formation() -> void:
	var sim := Simulation.new(1, 4)
	var squad := sim.drop_squad("Units/White/Footman", Simulation.TEAM_BLUE, Vector2(0, -23), 4)
	var expected := Simulation.spawning_pattern(Vector2(0, -23), Vector2(1, 0), false, 2, 4)
	runner.check(squad[2].position.distance_to(expected) < 0.001, "formation from ComputeSpawningPattern")
	runner.check_near(squad[0].position.distance_to(Vector2(0, -23)), 1.5, "drop ring radius 1.5")


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
