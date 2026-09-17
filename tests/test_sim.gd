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
	runner.check_near(e.damage(), 13.0, "footman dmg")
	runner.check_eq(e.cooldown(), 2000, "footman cooldown")
	runner.check_near(e.range_of(), 1.0, "footman range")
	runner.check_eq(e.armor(), SimConstants.ArmorType.MEDIUM, "footman armor")
	runner.check_near(e.collision_radius, 0.55, "footman radius")
	runner.check_near(e.speed(), 0.004, "default speed 4 u/s")
	runner.check(e.has("upMelee"), "footman is melee")


func test_league_arrays() -> void:
	var e := SimEntity.new()
	e.setup("Units/Neutral/Nexus", 3)
	runner.check_near(e.damage(), 120.0, "nexus dmg league 3")
	runner.check_eq(e.bb.get_int("eiResourceCap.reWelaCharge"), 16, "nexus ammo league 3")
	e = SimEntity.new()
	e.setup("Units/Neutral/Nexus", 1)
	runner.check_near(e.damage(), 110.0, "nexus dmg league 1")


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
	archer.base_speed = 0.0
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
	sim.spawn_bases()
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
	footman.base_speed = 0.0
	footman.add_buff(Buff.create("Stun", 0))   # target dummy: stunned, never thinks
	var launched: Array = []
	var hits: Array = []
	var on_launch := func(p): launched.append([sim.time_ms, p.speed])
	var on_removed := func(p, hit): hits.append([sim.time_ms, hit, p.position])
	sim.projectile_spawned.connect(on_launch)
	sim.projectile_removed.connect(on_removed)
	while hits.size() < 2 and sim.time_ms < 8000:
		sim.step()
	sim.projectile_spawned.disconnect(on_launch)
	sim.projectile_removed.disconnect(on_removed)
	runner.check_eq(launched.size(), 2, "archer launched two projectiles")
	runner.check_eq(hits.size(), 2, "both projectiles arrived")
	if launched.size() == 2 and hits.size() == 2:
		runner.check_near(launched[0][1], 0.02, "archer projectile speed 20 u/s")
		runner.check(hits[0][1], "projectile hit the footman")
		var flight: int = hits[0][0] - launched[0][0]
		# 9 units at 20 u/s = 450 ms, quantised to 32 ms ticks
		runner.check(flight >= 448 and flight <= 480, "flight time ~450 ms (got %d)" % flight)
		# first arrow (20 >= 10) is absorbed by Shieldblock, the second lands while Shieldblock is on cooldown
		runner.check_near(footman.health, 32.0 - 20.0 * 0.7, "Shieldblock ate the first arrow, second did 20 ranged vs medium = 14")
		runner.check_eq(hits[0][2], footman.position, "impact at the target position")


func test_projectile_misses_dead_target() -> void:
	var sim := Simulation.new(4, 4)
	var archer := sim.spawn("Units/White/Archer", Simulation.TEAM_BLUE, Vector2(-5, -23))
	var footman := sim.spawn("Units/White/Footman", Simulation.TEAM_RED, Vector2(4, -23))
	footman.base_speed = 0.0
	while sim.projectiles.is_empty() and sim.time_ms < 5000:
		sim.step()
	runner.check_eq(sim.projectiles.size(), 1, "projectile in flight")
	sim._kill(footman, archer)
	var results: Array = []
	var on_removed := func(_p, hit): results.append(hit)
	sim.projectile_removed.connect(on_removed)
	while sim.projectiles.size() > 0 and sim.time_ms < 8000:
		sim.step()
	sim.projectile_removed.disconnect(on_removed)
	runner.check_eq(results, [false], "projectile flew to the last position and fizzled")


func test_tower_ammo_and_tech_up() -> void:
	var sim := Simulation.new(6, 4)
	sim.spawn_bases()
	var nexus := sim.enemy_nexus(Simulation.TEAM_RED)
	runner.check_eq(nexus.ammo, 20, "nexus starts with 20 ammo at league 4")
	runner.check_eq(nexus.ammo_cost, 1, "nexus shot costs 1 ammo")
	runner.check_eq(nexus.ammo_recharge_ms, 6000, "nexus recharge 6 s at league 4")
	var tower: SimEntity = sim.alive_entities(Simulation.TEAM_RED).filter(func(e): return e.has("upLanetower"))[0]
	runner.check_eq(tower.ammo, 9, "lanetower starts with 9 of 18 ammo at league 4")
	runner.check_near(tower.max_health, 1200.0, "lanetower hp 1200 at league 4")
	runner.check_eq(sim.alive_entities(0).size(), 1, "one neutral lane node on Single")
	# damage the nexus, then tech up: NexusLevel2 keeps the taken damage
	sim.deal_damage(nexus, 1000.0, SimConstants.DamageType.TRUE, nexus)
	while sim.tick_counter < 241:
		sim.step()
	var nexus2 := sim.enemy_nexus(Simulation.TEAM_RED)
	runner.check(nexus2 != nexus, "nexus replaced at tech 2")
	runner.check_eq(nexus2.unit_id, "Units/Neutral/NexusLevel2", "replaced by NexusLevel2")
	runner.check_near(nexus2.max_health - nexus2.health, 1000.0, "taken damage kept")
	runner.check(not nexus.alive, "old nexus gone without a loss")
	runner.check(not sim.finished, "game continues")
	var towers := sim.alive_entities(Simulation.TEAM_RED).filter(func(e): return e.has("upLanetower"))
	runner.check_eq(towers.size(), 1, "still one red tower")
	runner.check_eq(towers[0].unit_id, "Units/Neutral/LanetowerLevel2", "lanetower teched to level 2")


func test_tower_uses_ammo() -> void:
	var sim := Simulation.new(6, 4)
	sim.spawn_bases()
	var tower: SimEntity = sim.alive_entities(Simulation.TEAM_RED).filter(func(e): return e.has("upLanetower"))[0]
	tower.ammo = 1
	tower.ammo_recharge_ms = 0   # no recharge for this test
	for i in 3:
		var f := sim.spawn("Units/White/Footman", Simulation.TEAM_BLUE, Vector2(40, -23 + i))
		f.base_speed = 0.0
	var shots: Array = []   # lambdas capture ints by value, so collect into an array
	var on_fire := func(att, _t, _d): if att == tower: shots.append(sim.time_ms)
	sim.attack_fired.connect(on_fire)
	while sim.time_ms < 5000:
		sim.step()
	sim.attack_fired.disconnect(on_fire)
	runner.check_eq(shots.size(), 1, "tower fired once and ran out of ammo")
	runner.check_eq(tower.ammo, 0, "ammo spent")


func test_lane_node_capture() -> void:
	var sim := Simulation.new(6, 4)
	sim.spawn_bases()
	var node: SimEntity = sim.alive_entities(0)[0]
	runner.check_eq(node.position, Vector2(0, -23), "lane node on the lane center")
	while not sim.game_started:
		sim.step()
	for i in 2:
		var f := sim.spawn("Units/White/Footman", Simulation.TEAM_BLUE, Vector2(-5, -23 + i))
		f.base_speed = 0.0
	# 15 team power at +1 per 500 ms = 7.5 s
	var t0 := sim.time_ms
	while node.alive and sim.time_ms < t0 + 12000:
		sim.step()
	runner.check(not node.alive, "node captured")
	runner.check(sim.time_ms - t0 >= 7000 and sim.time_ms - t0 <= 8100, "capture took ~7.5 s (got %d ms)" % (sim.time_ms - t0))
	var towers := sim.alive_entities(Simulation.TEAM_BLUE).filter(func(e): return e.has("upLanetower"))
	runner.check_eq(towers.size(), 2, "blue now owns two lanetowers")
	var captured: SimEntity = towers.filter(func(e): return e.position == Vector2(0, -23))[0]
	runner.check_eq(captured.unit_id, "Units/Neutral/LanetowerLevel1", "tier 1 tower at tier 1")
	# killing it leaves a neutral lane node again
	sim.deal_damage(captured, 1e6, SimConstants.DamageType.TRUE, captured)
	runner.check_eq(sim.alive_entities(0).size(), 1, "lane node respawned on tower death")
	var blocked_node: SimEntity = sim.alive_entities(0)[0]
	runner.check_eq(blocked_node.unit_id, "Units/Neutral/LaneNode_Red", "the node blocks the team that lost the tower")
	runner.check(sim._node_blocked_for(blocked_node, Simulation.TEAM_BLUE) and not sim._node_blocked_for(blocked_node, Simulation.TEAM_RED), "blue is blocked, red may capture")
	var t1 := sim.time_ms
	while sim._node_blocked_for(blocked_node, Simulation.TEAM_BLUE) and sim.time_ms < t1 + 45000:
		sim.step()
	runner.check(sim.time_ms - t1 >= 40000 and sim.time_ms - t1 < 40100, "recapture block lasts 40 s (got %d)" % (sim.time_ms - t1))


func test_buffs_from_modifier_scripts() -> void:
	var sim := Simulation.new(8, 4)
	var f := sim.spawn("Units/White/Footman", Simulation.TEAM_BLUE, Vector2(0, -23))
	var stun := sim.apply_buff(f, "Stun")
	runner.check_eq(stun.expires_at, sim.time_ms + 3000, "stun lasts 3000 ms")
	runner.check(f.has("upStunned") and f.has("upHasStateEffect"), "stunned properties")
	runner.check(not f.can_think(sim.time_ms), "stunned units do not think")
	runner.check_eq(stun.buff_types, ["btNegative", "btState"], "buff types from TAutoBrainBuffComponent")
	sim.apply_buff(f, "BlessingStrength")
	runner.check_near(f.max_health, 72.0, "+40 health")
	runner.check_near(f.health, 72.0, "health filled with the cap")
	runner.check_near(f.damage(), 21.0, "+8 damage added to the main weapon")
	sim.apply_buff(f, "BlessingArmor")
	runner.check_eq(f.armor(), SimConstants.ArmorType.HEAVY, "armor class up by one")
	runner.check(f.has("upBlessed"), "blessed")
	var t0 := sim.time_ms
	while f.has("upStunned") and sim.time_ms < t0 + 5000:
		sim.step()
	runner.check(sim.time_ms - t0 >= 3000 and sim.time_ms - t0 < 3000 + 2 * SimConstants.TICK_MS, "stun expired after 3 s")
	runner.check(f.has("upBlessed"), "permanent blessings stay")
	sim.apply_buff(f, "Root", {}, f)
	runner.check(not f.can_move(), "rooted units cannot move")
	var hp := f.health
	t0 = sim.time_ms
	while sim.time_ms < t0 + 2100:
		sim.step()
	runner.check_near(f.health, hp - 3.0, "root DoT: 1.5 dmg -> min 1 after armor, at once then every second (3 in 2.1 s)")


func test_archer_relentless_vs_stunned() -> void:
	var sim := Simulation.new(8, 4)
	var archer := sim.spawn("Units/White/Archer", Simulation.TEAM_BLUE, Vector2(-5, -23))
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(4, -23))   # unarmored, no shieldblock
	sim.apply_buff(monk, "Stun")
	monk.buffs[0].expires_at = 1 << 40
	var hits: Array = []
	var on_removed := func(_p, hit): hits.append(hit)
	sim.projectile_removed.connect(on_removed)
	while hits.is_empty() and sim.time_ms < 5000:
		sim.step()
	sim.projectile_removed.disconnect(on_removed)
	runner.check_near(monk.health, 265.0 - 40.0, "20 dmg x2 vs stunned = 40")


func test_priest_heals_injured_ally() -> void:
	var sim := Simulation.new(8, 4)
	var priest := sim.spawn("Units/White/Priest", Simulation.TEAM_BLUE, Vector2(-3, -23))
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(0, -23))
	priest.base_speed = 0.0
	monk.base_speed = 0.0
	runner.check_eq(priest.mana, 5, "priest starts with 5 mana")
	monk.health = 100.0
	var t0 := sim.time_ms
	while monk.health < 200.0 and sim.time_ms < t0 + 5000:
		sim.step()
	runner.check_near(monk.health, 200.0, "healed for 100")
	runner.check_eq(priest.mana, 0, "heal cost 5 mana")
	runner.check(monk.has("upBlessedArmor"), "heal also applies BlessingArmor")
	while priest.mana < 1 and sim.time_ms < t0 + 8000:
		sim.step()
	runner.check(sim.time_ms - t0 >= 3000, "mana regenerates 1 per 3 s")


func test_monk_dragon_punch_and_exile() -> void:
	var sim := Simulation.new(9, 4)
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(0, -23))     # 265 hp, 38 dmg
	var archer := sim.spawn("Units/White/Archer", Simulation.TEAM_RED, Vector2(1.5, -23)) # 19 hp: less than half
	archer.base_speed = 0.0
	sim.apply_buff(archer, "Stun")
	while archer.alive and sim.time_ms < 3000:
		sim.step()
	runner.check(not archer.alive, "archer killed")
	runner.check(archer.exiled, "target with less than half the monk's health is exiled")
	var monk2 := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(20, -23))
	var monk3 := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(21.5, -23))
	monk3.base_speed = 0.0
	sim.apply_buff(monk3, "Stun")
	monk2.health = 200.0   # healthier than a 150 hp target but not twice as healthy
	monk3.health = 150.0
	var hits: Array = []
	var on_hit := func(att, _t, d): if att == monk2: hits.append(d)
	sim.attack_fired.connect(on_hit)
	while hits.is_empty() and sim.time_ms < 6000:
		sim.step()
	sim.attack_fired.disconnect(on_hit)
	# 38 (group 4) + 48 dragon punch (group 3, monk healthier), no exile (group 2 needs 2x)
	runner.check(monk3.alive, "not exiled when target has more than half the monk's health")
	runner.check_near(monk3.health, 150.0 - 38.0 - 48.0, "38 + 48 dragon punch damage vs unarmored")


func test_avenger_double_shot_at_full_health() -> void:
	var sim := Simulation.new(9, 4)
	var avenger := sim.spawn("Units/White/Avenger", Simulation.TEAM_BLUE, Vector2(0, -23))
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(4, -23))
	monk.base_speed = 0.0
	sim.apply_buff(monk, "Stun")
	var launched: Array = []
	var on_launch := func(_p): launched.append(sim.time_ms)
	sim.projectile_spawned.connect(on_launch)
	while launched.size() < 2 and sim.time_ms < 3000:
		sim.step()
	runner.check_eq(launched.size(), 2, "two projectiles per attack at full health")
	if launched.size() == 2:
		runner.check_eq(launched[0], launched[1], "both launched in the same tick")
	avenger.health = 100.0
	launched.clear()
	while launched.size() < 1 and sim.time_ms < 8000:
		sim.step()
	var t := sim.time_ms
	sim.step()
	sim.projectile_spawned.disconnect(on_launch)
	runner.check_eq(launched.size(), 1, "one projectile per attack when damaged")


func test_marksman_range_grows_while_standing() -> void:
	var e := SimEntity.new()
	e.setup("Units/White/Marksman", 4)
	runner.check_near(e.range_of(1, 0), 13.5, "base range while moving")
	e.stand_since = 0
	e.moving = false
	runner.check_near(e.range_of(1, 5000), 13.5 + 3.0, "half the bonus after 5 s")
	runner.check_near(e.range_of(1, 20000), 13.5 + 6.0, "+6 after 10 s standing")


func test_suntower_homeland_aura_links_allies() -> void:
	var sim := Simulation.new(9, 4)
	var tower := sim.spawn("Units/White/Suntower", Simulation.TEAM_BLUE, Vector2(0, -23))
	var near := sim.spawn("Units/White/Footman", Simulation.TEAM_BLUE, Vector2(3, -23))
	var far := sim.spawn("Units/White/Footman", Simulation.TEAM_BLUE, Vector2(30, -23))
	near.base_speed = 0.0
	far.base_speed = 0.0
	sim.step()
	runner.check(near.linked_from(tower.id), "ally within 5.5 is linked")
	runner.check(not far.linked_from(tower.id), "ally out of range is not linked")
	sim._kill(tower)
	runner.check(not near.linked_from(tower.id), "links break when the tower dies")
	var defender := sim.spawn("Units/White/Defender", Simulation.TEAM_BLUE, Vector2(10, -23))
	var friend := sim.spawn("Units/White/Footman", Simulation.TEAM_BLUE, Vector2(12, -23))
	friend.base_speed = 0.0
	while sim.time_ms < 2000:
		sim.step()
	runner.check(friend.has("upLotharBuffed"), "Defender aura marks allies upLotharBuffed after its 1.8 s delay")
	runner.check(not defender.has("upLotharBuffed"), "aura does not affect the Defender itself")


func test_monument_of_light_aoe() -> void:
	var sim := Simulation.new(9, 4)
	var monument := sim.spawn("Units/White/MonumentOfLight", Simulation.TEAM_BLUE, Vector2(0, -23))
	var ally := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(4, -23))
	var enemy := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-4, -23))
	ally.base_speed = 0.0
	enemy.base_speed = 0.0
	sim.apply_buff(enemy, "Stun")
	ally.health = 100.0
	runner.check_eq(monument.mana, 3, "monument starts with 3 mana")
	while ally.health < 200.0 and sim.time_ms < 3000:
		sim.step()
	runner.check_near(ally.health, 200.0, "allies in 8 healed for 100")
	runner.check_near(enemy.health, 265.0 - 20.0, "enemies in 8 take 20 splash")
	runner.check_eq(monument.mana, 0, "pulse cost 3 mana")


func test_homeland_rescue() -> void:
	var sim := Simulation.new(10, 4)
	sim.spawn_bases()
	var tower := sim.spawn("Units/White/Suntower", Simulation.TEAM_BLUE, Vector2(-40, -23))
	var footman := sim.spawn("Units/White/Footman", Simulation.TEAM_BLUE, Vector2(-37, -23))
	footman.base_speed = 0.0
	sim.apply_buff(footman, "Stun")
	sim.step()
	runner.check(footman.has("upRescued"), "linked footman is marked rescued")
	sim._kill(footman)
	runner.check(footman.alive, "death prevented once")
	runner.check_near(footman.health, 10.0, "health set to 10")
	runner.check(not footman.has("upStunned"), "state effects stripped")
	runner.check(footman.has("upImmuneToRescued"), "immune to a second rescue")
	runner.check(footman.position.distance_to(Vector2(-96, -23)) < 6.0, "teleported next to the own nexus")
	runner.check(not footman.linked_from(tower.id), "link consumed")
	sim._kill(footman)
	runner.check(not footman.alive, "second death is final")


func test_heavy_gunner_gains_mana_when_blessed() -> void:
	var sim := Simulation.new(10, 4)
	var gunner := sim.spawn("Units/White/HeavyGunner", Simulation.TEAM_BLUE, Vector2(0, -23))
	runner.check_eq(gunner.mana, 0, "heavy gunner starts empty")
	sim.apply_buff(gunner, "BlessingArmor")
	runner.check_eq(gunner.mana, gunner.mana_cap, "a blessing fills the mana (group 5 gives 100, capped at 4)")


func _spell_sim() -> Simulation:
	var sim := Simulation.new(12, 4)
	sim.spawn_bases()
	var c: Commander = sim.commanders[Simulation.TEAM_BLUE]
	c.set_deck(["Spells/White/LightPulse.sps", "Spells/White/ShieldsUp.sps", "Spells/White/SolarFlare.sps",
		"Spells/White/SurgeOfLight.sps", "Spells/White/HailOfArrows.sps"])
	c.gold = 1000.0
	c.raise_tier(3)
	while not sim.game_started:
		sim.step()
	return sim


func test_spell_costs_and_targets() -> void:
	var sim := _spell_sim()
	var c: Commander = sim.commanders[Simulation.TEAM_BLUE]
	runner.check_near(c.slots[0].cost, 70.0, "Light Pulse costs 80 - 10")
	runner.check_near(c.slots[1].cost, 80.0, "Shields Up costs 80")
	runner.check_near(c.slots[2].cost, 180.0, "Solar Flare tier 3 spell 200 - 20")
	runner.check_eq(c.slots[2].card.target_type, "ctEntity", "Solar Flare targets a unit")
	runner.check_eq(c.slots[0].card.target_type, "ctCoordinate", "Light Pulse targets a point")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, Vector2(0, 40)), Simulation.PlayResult.BAD_TARGET, "outside walkzone")


func test_light_pulse_stuns_and_blinds() -> void:
	var sim := _spell_sim()
	var enemies: Array = []
	for i in 10:
		var m := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(0 + i * 0.2, -23 + (i % 2) * 0.5))
		m.base_speed = 0.0
		enemies.append(m)
	var far := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(4.5, -23))   # inside 5, outside 2
	far.base_speed = 0.0
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, Vector2(0, -23)), Simulation.PlayResult.OK, "cast light pulse")
	var stunned := enemies.filter(func(m): return m.has("upStunned")).size()
	runner.check_eq(stunned, 8, "8 units stunned in radius 2")
	runner.check(far.has("upBlinded") and not far.has("upStunned"), "unit at 4.5 only blinded")
	runner.check_eq(sim.alive_entities(Simulation.TEAM_BLUE).filter(func(e): return e.is_spell_effect()).size(), 0, "effect entity removed itself")


func test_shields_up_gives_shieldblock() -> void:
	var sim := _spell_sim()
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(2, -23))
	monk.base_speed = 0.0
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 1, Vector2(0, -23)), Simulation.PlayResult.OK, "cast shields up")
	runner.check(monk.has("upHasShieldBlock"), "ally gained Shieldblock")
	sim.deal_damage(monk, 50.0, SimConstants.DamageType.MELEE, monk)
	runner.check_near(monk.health, 265.0, "first big hit blocked")


func test_solar_flare_and_surge_of_light() -> void:
	var sim := _spell_sim()
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(2, -23))
	var enemy := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(10, -23))
	monk.base_speed = 0.0
	enemy.base_speed = 0.0
	monk.health = 10.0
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 2, monk.id), Simulation.PlayResult.OK, "cast solar flare on ally")
	runner.check_near(monk.health, 265.0, "healed by 400 up to max")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 2, enemy.id), Simulation.PlayResult.BAD_TARGET, "solar flare refuses enemies")
	var c: Commander = sim.commanders[Simulation.TEAM_BLUE]
	c.slots[3].charges = 5
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 3, enemy.id), Simulation.PlayResult.BAD_TARGET, "surge damage mode needs a stored charge")
	monk.health = 10.0
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 3, monk.id), Simulation.PlayResult.OK, "surge heal mode on ally")
	runner.check_near(monk.health, 210.0, "healed 200")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 3, monk.id), Simulation.PlayResult.OK, "second heal")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 3, enemy.id), Simulation.PlayResult.OK, "damage mode with 2 charges")
	runner.check_near(enemy.health, 265.0 - 120.0, "60 x 2 charges = 120 spell damage")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 3, enemy.id), Simulation.PlayResult.BAD_TARGET, "charges consumed")


func test_hail_of_arrows_field() -> void:
	var sim := _spell_sim()
	var enemy := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(1, -23))
	enemy.base_speed = 0.0
	sim.apply_buff(enemy, "Stun")
	enemy.buffs[0].expires_at = 1 << 40
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 4, Vector2(0, -23)), Simulation.PlayResult.OK, "cast hail of arrows")
	var t0 := sim.time_ms
	while sim.time_ms < t0 + 3000:
		sim.step()
	# 4 charges = 4 ticks of 16 spell damage every 0.5 s, then the field is gone
	runner.check_near(enemy.health, 265.0 - 4 * 16.0, "four ticks of 16")
	runner.check_eq(sim.alive_entities(Simulation.TEAM_BLUE).filter(func(e): return e.is_spell_effect()).size(), 0, "field expired")


func test_promise_of_life_charm() -> void:
	var sim := _spell_sim()
	var c: Commander = sim.commanders[Simulation.TEAM_BLUE]
	c.set_deck(["Spells/White/PromiseOfLife.sps"])
	c.raise_tier(3)
	c.gold = 5000.0
	c.slots[0].charges = 5
	runner.check_near(c.slots[0].cost, 130.0 + 40.0, "tier 2 spell 130 + 40")
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(2, -23))
	monk.base_speed = 0.0
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, Vector2(0, -23)), Simulation.PlayResult.OK, "charm placed")
	runner.check_eq(c.charm_count, 1, "one charm counted")
	var charm: SimEntity = sim.alive_entities(Simulation.TEAM_BLUE).filter(func(e): return e.has("upCharm"))[0]
	runner.check_eq(charm.ammo, 10, "charm has 10 charges")
	sim.step()
	runner.check(monk.has("upGuarded"), "ally in 5 is guarded")
	runner.check(monk.has("upImmuneToStateEffects"), "ally is immune to state effects")
	runner.check(not charm.moving, "charm stays put")
	sim._kill(monk)
	runner.check(monk.alive, "guarded ally survives")
	runner.check_near(monk.health, 1.0, "with 1 health")
	runner.check_eq(charm.ammo, 9, "one charge spent on the rescue")
	runner.check(monk.has("upImmuneToGuarded") and monk.has("upInvincible"), "immune to guarded, briefly invincible")
	for i in 3:
		sim.play_card(Simulation.TEAM_BLUE, 0, Vector2(-20 + i * 3, -23))
	runner.check_eq(c.charm_count, 3, "charm count capped at 3")
	runner.check(not charm.alive, "oldest charm removed when the fourth was placed")
	runner.check_eq(sim.alive_entities(Simulation.TEAM_BLUE).filter(func(e): return e.has("upCharm")).size(), 3, "three charms alive")


func test_overheal() -> void:
	var sim := _spell_sim()
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(2, -23))
	monk.base_speed = 0.0
	monk.health = 200.0
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 2, monk.id), Simulation.PlayResult.OK, "solar flare")
	runner.check_near(monk.health, 265.0, "health capped")
	runner.check_near(monk.overheal, 335.0, "400 - 65 becomes overheal")
	sim.deal_damage(monk, 100.0, SimConstants.DamageType.TRUE, monk)
	runner.check_near(monk.overheal, 235.0, "damage eats overheal first")
	runner.check_near(monk.health, 265.0, "health untouched while overheal lasts")
	sim.deal_damage(monk, 300.0, SimConstants.DamageType.TRUE, monk)
	runner.check_near(monk.overheal, 0.0, "overheal gone")
	runner.check_near(monk.health, 200.0, "remaining 65 hit health")
	monk.overheal = 0.0
	monk.health = 265.0
	sim.commanders[Simulation.TEAM_BLUE].slots[2].charges = 3
	sim.play_card(Simulation.TEAM_BLUE, 2, monk.id)
	sim.play_card(Simulation.TEAM_BLUE, 2, monk.id)
	runner.check_near(monk.overheal, 530.0, "overheal capped at 2x max health")


func test_projectile_splash() -> void:
	var sim := Simulation.new(13, 4)
	var saint := sim.spawn("Units/White/PatronSaint", Simulation.TEAM_BLUE, Vector2(0, -23))   # 110 dmg, aoe 2
	var a := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(3, -23))
	var b := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(4, -23))
	var far := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(8, -23))
	for m in [a, b, far]:
		m.base_speed = 0.0
		sim.apply_buff(m, "Stun")
		m.buffs[0].expires_at = 1 << 40
	var hits: Array = []
	var on_removed := func(_p, hit): hits.append(hit)
	sim.projectile_removed.connect(on_removed)
	while hits.is_empty() and sim.time_ms < 5000:
		sim.step()
	sim.projectile_removed.disconnect(on_removed)
	runner.check_near(a.health, 265.0 - 110.0, "primary target takes 110")
	runner.check_near(b.health, 265.0 - 110.0, "neighbour in the 2.0 area takes full splash")
	runner.check_near(far.health, 265.0, "unit outside the area untouched")


func test_dynamic_drop_zone() -> void:
	var sim := Simulation.new(13, 4)
	sim.spawn_bases()
	var c: Commander = sim.commanders[Simulation.TEAM_BLUE]
	c.set_deck(["Units/White/FootmanDrop"])
	c.free_cards = true
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, Vector2(-70, -23)), Simulation.PlayResult.OK, "within 31.5 of the nexus")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, Vector2(-25, -23)), Simulation.PlayResult.OK, "within 30 of the own lanetower at -48")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, Vector2(0, -23)), Simulation.PlayResult.BAD_TARGET, "lane center is outside the blue zone")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, Vector2(60, -23)), Simulation.PlayResult.BAD_TARGET, "red side is outside")
	var node: SimEntity = sim.alive_entities(0)[0]
	sim.replace_entity(node, "Units/Neutral/LanetowerLevel1", Simulation.TEAM_BLUE)
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, Vector2(20, -23)), Simulation.PlayResult.OK, "captured lane tower extends the zone")


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


func test_souls_fly_to_gatherer() -> void:
	var sim := Simulation.new(3, 4)
	var skeleton := sim.spawn("Units/Black/VoidSkeleton", Simulation.TEAM_BLUE, Vector2(0, -23))
	runner.check_eq(skeleton.mana_cap, 1, "void skeleton stores 1 soul")
	runner.check_eq(skeleton.mana, 0, "starts empty")
	var footman := sim.spawn("Units/White/Footman", Simulation.TEAM_BLUE, Vector2(3, -23))
	var souls: Array = []
	var on_proj := func(p): if p.gives_mana: souls.append(p)
	sim.projectile_spawned.connect(on_proj)
	sim._kill(footman)
	runner.check(souls.is_empty(), "SoulGatherProjectileSpawner waits one frame")
	sim.step()
	runner.check_eq(souls.size(), 1, "one soul projectile per death")
	if not souls.is_empty():
		runner.check_eq(souls[0].target_id, skeleton.id, "soul flies to the gatherer")
		runner.check_near(souls[0].speed, 0.01, "soul speed 10/1000")
	for i in 20:   # 3 units at 10 u/s = 300 ms
		sim.step()
	runner.check_eq(skeleton.mana, 1, "gatherer received the soul")
	var enemy := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(2, -23))
	sim._kill(enemy)
	for i in 30:
		sim.step()
	runner.check_eq(souls.size(), 1, "full gatherer receives nothing")
	runner.check_eq(skeleton.mana, 1, "soul cap holds")
	skeleton.mana = 0
	enemy = sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(2, -23))
	sim._kill(enemy)
	for i in 30:
		sim.step()
	runner.check_eq(skeleton.mana, 1, "enemy souls are eligible when no own gatherer wants them")
	sim.projectile_spawned.disconnect(on_proj)
	runner.check_eq(sim.alive_entities().size(), 1, "spawner entities vanish after firing")


func test_void_skeleton_undying() -> void:
	var sim := Simulation.new(3, 4)
	var skeleton := sim.spawn("Units/Black/VoidSkeleton", Simulation.TEAM_BLUE, Vector2(0, -23))
	sim._kill(skeleton)
	runner.check(not skeleton.alive, "without a soul the skeleton just dies")
	skeleton = sim.spawn("Units/Black/VoidSkeleton", Simulation.TEAM_BLUE, Vector2(0, -23))
	skeleton.mana = 1
	skeleton.health = 20.0
	sim._kill(skeleton)
	runner.check(skeleton.alive, "undying cancels death")
	runner.check_eq(skeleton.mana, 0, "paid 1 soul")
	runner.check_near(skeleton.health, 105.0, "healed to full")
	runner.check(skeleton.has("upUnhealable"), "undying cannot be healed")
	runner.check_near(sim.heal(skeleton, 10.0, 0, null), 0.0, "heal refused")
	var start := sim.time_ms
	while skeleton.alive and sim.time_ms < start + 20000:
		sim.step()
	runner.check(not skeleton.alive, "dies when undying ends")
	runner.check(sim.time_ms - start >= 15000 and sim.time_ms - start < 15100, "undying lasts 15 s (got %d)" % (sim.time_ms - start))


func test_void_bane_cleave_reaper_and_soul_donation() -> void:
	var sim := Simulation.new(3, 4)
	var bane := sim.spawn("Units/Black/VoidBane", Simulation.TEAM_BLUE, Vector2(0, -23))
	runner.check_eq(bane.mana_cap, 14, "void bane stores 14 souls")
	sim.gain_mana(bane, 3)
	runner.check_eq(bane.mana, 3, "3 souls stored")
	runner.check_near(bane.max_health, 190.0 + 45.0, "reaper: +15 max hp per soul")
	runner.check_near(bane.health, 235.0, "cap increase fills")
	var front_monk := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(1.5, -23))
	var behind_monk := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-1.5, -23))
	bane.target_id = front_monk.id
	sim._fire_group(bane, 1, front_monk)
	runner.check_near(front_monk.health, 265.0 - 27.0, "cone cleave hits the target for 27")
	runner.check_near(behind_monk.health, 265.0, "cleave misses units behind the bane")
	var skeleton := sim.spawn("Units/Black/VoidSkeleton", Simulation.TEAM_BLUE, Vector2(0, -20))
	var souls: Array = []
	var on_proj := func(p): if p.gives_mana: souls.append(p)
	sim.projectile_spawned.connect(on_proj)
	sim._kill(bane)
	runner.check_eq(souls.size(), 3, "death rattle: one soul donor projectile per stored soul")
	for p in souls:
		runner.check_eq(p.target_id, skeleton.id, "donations go to a non-full allied gatherer")
	sim.step()
	runner.check_eq(souls.size(), 4, "plus the bane's own soul")
	sim.projectile_spawned.disconnect(on_proj)


func test_void_bowman_grievous_wounds() -> void:
	var sim := Simulation.new(3, 4)
	var bowman := sim.spawn("Units/Black/VoidBowman", Simulation.TEAM_BLUE, Vector2(0, -23))
	runner.check(bowman.has("upBlessedGrievousWounds"), "enchanted at spawn")
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(5, -23))
	monk.locked_until = 1 << 30   # a passive victim: the monk would kill the 60 hp bowman otherwise
	while not monk.has("upBleeding") and sim.time_ms < 8000:
		sim.step()
	runner.check(monk.has("upBleeding"), "first hit applies bleeding")
	var bleeding: Buff = null
	for b in monk.buffs:
		if b.name == "Bleeding":
			bleeding = b
	if bleeding == null:
		return
	runner.check_eq(bleeding.charges, 1, "one stack")
	runner.check_near(sim.heal(monk, 10.0, 0, null), 6.0, "bleeding reduces healing by 40%")
	var hp := monk.health
	var t := sim.time_ms
	while sim.time_ms < t + 1000:
		sim.step()
	runner.check(monk.health < hp - 0.5 * 265.0 * 0.005 * 0.99, "bleed tick 0.5% max hp per stack per second")
	while bleeding.charges < 2 and sim.time_ms < 12000:
		sim.step()
	runner.check_eq(bleeding.charges, 2, "further hits stack bleeding")
	runner.check(bleeding.expires_at > sim.time_ms + 9000, "stacking refreshes the 10 s duration")


func test_void_worm_frost_shot_and_immunity() -> void:
	var sim := Simulation.new(3, 4)
	var worm := sim.spawn("Units/Black/VoidWorm", Simulation.TEAM_BLUE, Vector2(0, -23))
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(4, -23))
	monk.locked_until = 1 << 30
	while not monk.has("upFrozen") and sim.time_ms < 5000:
		sim.step()
	runner.check(monk.has("upFrozen"), "frost shot freezes the target")
	runner.check(monk.has("upImmuneToFrozen"), "frozen units are immune to a re-freeze")
	worm.locked_until = 1 << 30   # stop shooting so the timers can be measured
	var frozen_at := sim.time_ms
	while monk.has("upFrozen") and sim.time_ms < frozen_at + 12000:
		sim.step()
	runner.check(sim.time_ms - frozen_at >= 9000 and sim.time_ms - frozen_at < 9100, "frozen lasts 9 s (got %d)" % (sim.time_ms - frozen_at))
	runner.check(monk.has("upImmuneToFrozen"), "immunity outlives the freeze")
	while monk.has("upImmuneToFrozen") and sim.time_ms < frozen_at + 25000:
		sim.step()
	runner.check(sim.time_ms - frozen_at >= 19000 and sim.time_ms - frozen_at < 19100, "immunity lasts 19 s (got %d)" % (sim.time_ms - frozen_at))
	var near := sim.spawn("Units/White/Footman", Simulation.TEAM_RED, Vector2(worm.position.x + 1.5, worm.position.y))
	sim._kill(worm)
	runner.check(near.has("upFrozen"), "death rattle freezes enemies within 2")


func test_frostgoyle_fury() -> void:
	var sim := Simulation.new(3, 4)
	var goyle := sim.spawn("Units/Black/Frostgoyle", Simulation.TEAM_BLUE, Vector2(0, -23))
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(1.3, -23))
	monk.locked_until = 1 << 30
	var hits: Array = []
	var on_hit := func(a, _t, _d): if a == goyle: hits.append(sim.time_ms)
	sim.attack_fired.connect(on_hit)
	while hits.size() < 3 and sim.time_ms < 12000:
		sim.step()
	sim.attack_fired.disconnect(on_hit)
	runner.check_eq(hits.size(), 3, "three hits")
	if hits.size() == 3:
		runner.check(hits[1] - hits[0] < 1000, "fury: hitting a full-health unit resets the 3.6 s cooldown (got %d)" % (hits[1] - hits[0]))
		runner.check(hits[2] - hits[1] >= 3600, "no reset against an injured unit (got %d)" % (hits[2] - hits[1]))


func test_void_cauldron_blast() -> void:
	var sim := Simulation.new(3, 4)
	var cauldron := sim.spawn("Units/Black/VoidCauldron", Simulation.TEAM_BLUE, Vector2(0, -23))
	var tower := sim.spawn("Units/Neutral/LanetowerLevel1", Simulation.TEAM_RED, Vector2(10, -23))
	var shots: Array = []
	var on_proj := func(p): if not p.gives_mana: shots.append(p)
	sim.projectile_spawned.connect(on_proj)
	sim._kill(cauldron)
	runner.check_eq(shots.size(), 0, "no souls, no blast")
	cauldron = sim.spawn("Units/Black/VoidCauldron", Simulation.TEAM_BLUE, Vector2(0, -23))
	sim.gain_mana(cauldron, 3)
	sim._kill(cauldron)
	sim.projectile_spawned.disconnect(on_proj)
	runner.check_eq(shots.size(), 3, "one blast projectile per stored soul")
	for p in shots:
		runner.check_eq(p.target_id, tower.id, "aimed at enemy buildings")
		runner.check_near(p.damage, 15.0, "blast damage 15")


func test_frostgoyle_fountain() -> void:
	var sim := Simulation.new(3, 4)
	var fountain := sim.spawn("Units/Black/FrostgoyleFountain", Simulation.TEAM_BLUE, Vector2(-60, -23))
	runner.check_eq(fountain.lifetime_ms, 90000, "building lives 90 s")
	sim.gain_mana(fountain, 3)
	sim.step()
	runner.check_eq(sim.alive_entities().size(), 1, "3 souls are not enough")
	sim.gain_mana(fountain, 1)
	sim.step()
	var goyles: Array = []
	for e in sim.alive_entities():
		if e.unit_id == "Units/Black/Frostgoyle":
			goyles.append(e)
	runner.check_eq(goyles.size(), 1, "4 souls spawn a frostgoyle")
	runner.check_eq(fountain.mana, 0, "souls paid")
	if goyles.is_empty():
		return
	var goyle: SimEntity = goyles[0]
	runner.check(goyle.has("upSummoningSickness"), "legendary spawn lockout")
	var born := sim.time_ms
	while goyle.has("upSummoningSickness") and sim.time_ms < born + 2000:
		sim.step()
	runner.check(sim.time_ms - born >= 660 and sim.time_ms - born < 700, "lockout 660 ms (got %d)" % (sim.time_ms - born))
	while goyle.alive and sim.time_ms < born + 20000:
		sim.step()
	runner.check(sim.time_ms - born >= 17000 and sim.time_ms - born < 17100, "timed life 17 s (got %d)" % (sim.time_ms - born))
	while fountain.alive and sim.time_ms < 95000:
		sim.step()
	runner.check(sim.time_ms >= 90000 and sim.time_ms < 90100, "fountain dies after 90 s (got %d)" % sim.time_ms)


func test_tyrus_soul_armor_undertow_and_debut() -> void:
	var sim := Simulation.new(3, 4)
	var victims: Array = []
	for i in 3:
		var m := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(3 + i, -23))
		m.locked_until = 1 << 30
		victims.append(m)
	var far := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(15, -23))
	var tyrus := sim.spawn("Units/Black/Tyrus", Simulation.TEAM_BLUE, Vector2(0, -23))
	runner.check(tyrus.has("upSummoningSickness"), "legendary spawn lockout")
	runner.check_eq(tyrus.mana_cap, 20, "tyrus stores 20 souls")
	var souls: Array = []
	var on_proj := func(p): if p.gives_mana: souls.append(p)
	sim.projectile_spawned.connect(on_proj)
	var banishes: Array = []
	var on_buff := func(e, b): if b.name == "Banished": banishes.append([sim.time_ms, e.id])
	sim.buff_applied.connect(on_buff)
	sim.step()
	runner.check_eq(souls.size(), 3, "lord of souls: one soul drained from every enemy within 9")
	var fresh := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(2, -23))   # arrives after the debut
	fresh.locked_until = 1 << 30
	for m in victims:
		runner.check(m.has("upBanished"), "debut banishes")
	runner.check(not far.has("upBanished"), "outside 9 untouched")
	for i in 125:   # outlasts the 3300 ms spawn invincibility and the first undertow (one more soul)
		sim.step()
	runner.check_eq(tyrus.mana, 4, "drained souls arrive")
	sim.deal_damage(tyrus, 4.0, SimConstants.DamageType.MELEE, null)
	runner.check_eq(tyrus.mana, 4, "hits below 5 are not blocked")
	var before := tyrus.health
	sim.deal_damage(tyrus, 50.0, SimConstants.DamageType.MELEE, null)
	runner.check_near(tyrus.health, before, "soul armor nullifies a hit of 5 or more")
	runner.check_eq(tyrus.mana, 3, "and pays one soul")
	tyrus.mana = 0
	sim.deal_damage(tyrus, 50.0, SimConstants.DamageType.MELEE, null)
	runner.check(tyrus.health < before, "no souls, no armor")
	sim.projectile_spawned.disconnect(on_proj)
	sim.buff_applied.disconnect(on_buff)
	# undertow: the 3 s cooldown starts at spawn, the 3.3 s spawn lockout delays the first cast a little
	var undertow: Array = []
	for ev in banishes:
		if ev[1] == fresh.id:
			undertow.append(ev[0])
	runner.check_eq(undertow.size(), 1, "soul undertow banished the fresh enemy once")
	if not undertow.is_empty():
		runner.check(undertow[0] >= 3300 and undertow[0] < 3500, "first undertow right after the lockout (got %d)" % undertow[0])


func test_vecra_icy_prison() -> void:
	var sim := Simulation.new(3, 4)
	var vecra := sim.spawn("Units/Black/Vecra", Simulation.TEAM_BLUE, Vector2(0, -23))
	runner.check(vecra.has("upFrozen") and vecra.has("upGround") and vecra.has("upImmuneToFrozen"), "imprisoned: frozen, grounded, frost-immune")
	runner.check(not vecra.wela(4).active, "monarch of frost aura starts inactive")
	var start_hp := vecra.health
	while sim.time_ms < 4100:   # invincible for the first 2500 ms: the 2000 ms tick is blocked, the 4000 ms one lands
		sim.step()
	runner.check_near(vecra.health, start_hp - 10.0, "melts 10 every 2 s (ignores armor)")
	var before := vecra.health
	sim.deal_damage(vecra, 100.0, SimConstants.DamageType.SPELL, null)
	runner.check_near(vecra.health, before - (100.0 * 0.2 * 0.7 - 5.0), "incoming damage x0.2 in the prison (then heavy armor)")
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(3, -23))
	monk.locked_until = 1 << 30
	vecra.health = 0.5 * vecra.max_health
	sim.step()
	runner.check(not vecra.has("upFrozen"), "unleashed at 50%: prison gone")
	runner.check(vecra.wela(4).active, "aura active")
	runner.check(monk.has("upFrozen"), "freeze burst froze the enemy")
	runner.check(vecra.has("upSummoningSickness"), "1666 ms lockout after breaking out")
	var monk_hp := monk.health
	vecra.health = 100.0
	var t := sim.time_ms
	while sim.time_ms < t + 1100:
		sim.step()
	runner.check(monk.health < monk_hp, "aura link hurts frozen enemies")
	runner.check(vecra.health > 100.0, "and leeches life back")


func test_void_wraith_frost_nova() -> void:
	var sim := Simulation.new(3, 4)
	var wraith := sim.spawn("Units/Black/VoidWraith", Simulation.TEAM_BLUE, Vector2(0, -23))
	runner.check_eq(wraith.mana, 6, "starts with 6 souls")
	var a := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(5, -23))
	var b := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(7, -23))
	a.locked_until = 1 << 30
	b.locked_until = 1 << 30
	while not a.has("upFrozen") and sim.time_ms < 6000:
		sim.step()
	runner.check(a.has("upFrozen"), "nova freezes the target")
	runner.check_near(a.health, 265.0 - 200.0 - 60.0, "200 direct plus 60 splash")
	runner.check_near(b.health, 265.0 - 60.0, "splash 60 within 4")
	runner.check_eq(wraith.mana, 0, "nova costs 6 souls")
	while wraith.mana < 1 and sim.time_ms < 4000:
		sim.step()
	runner.check(sim.time_ms >= 3000 and sim.time_ms <= 3100, "+1 soul on the 3 s regeneration timer (got %d)" % sim.time_ms)


func test_void_altar() -> void:
	var sim := Simulation.new(3, 4)
	var altar := sim.spawn("Units/Black/VoidAltar", Simulation.TEAM_BLUE, Vector2(-60, -23))
	var footman := sim.spawn("Units/White/Footman", Simulation.TEAM_RED, Vector2(-30, -23))
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-31, -23))
	footman.locked_until = 1 << 30
	monk.locked_until = 1 << 30
	sim.step()
	sim.step()   # prefire, then the shot resolves next tick
	runner.check(not footman.alive and footman.exiled, "soul vortex exiles a unit with max hp <= 60 within 40")
	runner.check(monk.alive, "265 hp monk is safe")
	for i in 110:   # 30 units at 10 u/s
		sim.step()
	runner.check_eq(altar.mana, 1, "exile harvests the soul")
	var bane := sim.spawn("Units/Black/VoidBane", Simulation.TEAM_BLUE, Vector2(-55, -23))
	for i in 60:
		sim.step()
	runner.check_eq(bane.mana, 1, "altar donates its souls to gatherers within 12")
	runner.check_eq(altar.mana, 0, "donation costs the soul")


func test_void_slime_status_mirror() -> void:
	var sim := Simulation.new(3, 4)
	var slime := sim.spawn("Units/Black/VoidSlime", Simulation.TEAM_BLUE, Vector2(0, -23))
	runner.check_near(slime.max_health, 495.0, "slime hp")
	sim.apply_buff(slime, "Stun")
	runner.check_near(slime.max_health, 745.0, "absorb: first stun +250 max hp")
	sim.apply_buff(slime, "Stun")
	runner.check_near(slime.max_health, 745.0, "only once per status")
	sim.apply_buff(slime, "Bleeding")
	runner.check_near(slime.max_health, 995.0, "each status counts once")
	# mirror to enemy: an attacker hitting the stunned slime gets stunned
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(1.5, -23))
	monk.locked_until = 1 << 30
	sim.deal_damage(slime, 10.0, SimConstants.DamageType.MELEE, monk)
	runner.check(monk.has("upStunned"), "mirror: the attacker is stunned")
	runner.check(not monk.has("upBleeding"), "one mirrored status per 200 ms")
	for i in 7:
		sim.step()
	sim.deal_damage(slime, 10.0, SimConstants.DamageType.MELEE, monk)
	runner.check(monk.has("upBleeding"), "mirror: the next hit passes on the bleeding")
	# mirror to self: hitting a frozen enemy freezes the slime
	for b in slime.buffs.duplicate():
		slime.remove_buff(b)
	sim.apply_buff(monk, "Frozen")
	slime.fire_group = 1
	sim.deal_damage(monk, 10.0, SimConstants.DamageType.MELEE, slime)
	runner.check(slime.has("upFrozen"), "mirror to self: copies the victim's frozen status")


func _black_spell_sim() -> Simulation:
	var sim := Simulation.new(21, 4)
	sim.spawn_bases()
	var c: Commander = sim.commanders[Simulation.TEAM_BLUE]
	c.set_deck(["Spells/Black/Frenzy.sps", "Spells/Black/Frostspear.sps", "Spells/Black/Freeze.sps",
		"Spells/Black/OnTheEdge.sps", "Spells/Black/PermaFrost.sps", "Spells/Black/RipOutSoul.sps", "Spells/Black/ShatterIce.sps"])
	c.gold = 1000.0
	c.raise_tier(3)
	while not sim.game_started:
		sim.step()
	return sim


func test_frenzy() -> void:
	var sim := _black_spell_sim()
	var footman := sim.spawn("Units/White/Footman", Simulation.TEAM_BLUE, Vector2(0, -23))
	var archer := sim.spawn("Units/White/Archer", Simulation.TEAM_BLUE, Vector2(2, -23))
	var enemy := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(1, -23))
	enemy.locked_until = 1 << 30
	sim.apply_buff(footman, "Stun")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, enemy.id), Simulation.PlayResult.BAD_TARGET, "frenzy is for allies")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, footman.id), Simulation.PlayResult.OK, "frenzy on the footman")
	runner.check(not footman.has("upStunned"), "frenzy strips state effects")
	runner.check(footman.has("upBlessedFrenzy") and footman.has("upImmuneToStateEffects"), "blessed and immune")
	runner.check_eq(footman.cooldown(1), 1000, "melee attacks twice as fast")
	runner.check_eq(footman.target_count(1), 1, "melee gets no extra target")
	footman.health = 10.0
	footman.fire_group = 1
	sim._fire_group(footman, 1, enemy)
	runner.check_near(footman.health, 32.0, "melee heals 70 per attack (capped)")
	var archer_cooldown := archer.cooldown(1)
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, archer.id), Simulation.PlayResult.OK, "frenzy on the archer")
	runner.check_eq(archer.cooldown(1), int(archer_cooldown * 0.75), "ranged attack speed x0.75")
	runner.check_eq(archer.target_count(1), 2, "ranged gains one extra target")
	var t := sim.time_ms
	while footman.has("upBlessedFrenzy") and sim.time_ms < t + 12000:
		sim.step()
	runner.check(sim.time_ms - t >= 10000 and sim.time_ms - t < 10100, "frenzy lasts 10 s (got %d)" % (sim.time_ms - t))


func test_frostspear() -> void:
	var sim := _black_spell_sim()
	var victim := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(0, -23))
	var a := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(3, -23))
	var b := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-3, -23))
	for m in [victim, a, b]:
		m.locked_until = 1 << 30
	var shards: Array = []
	var on_proj := func(p): if p.unit_id.ends_with("FrostspearProjectile"): shards.append(p)
	sim.projectile_spawned.connect(on_proj)
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 1, victim.id), Simulation.PlayResult.OK, "frostspear on an enemy")
	runner.check(victim.has("upFrozen"), "target frozen")
	for i in 60:
		sim.step()
	sim.projectile_spawned.disconnect(on_proj)
	runner.check_eq(shards.size(), 12, "12 ice shards")
	runner.check_near(shards[0].damage, 10.0, "10 spell damage each")
	runner.check_near(a.health + b.health, 2 * 265.0 - 120.0, "shards hit the victim's team mates within 6")
	var tower := sim.spawn("Units/Neutral/LanetowerLevel1", Simulation.TEAM_RED, Vector2(20, -23))
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 1, tower.id), Simulation.PlayResult.OK, "frostspear on a base building")
	runner.check(tower.has("upFrozen"), "base frozen")
	var frozen: Buff = null
	for x in tower.buffs:
		if x.name == "Frozen":
			frozen = x
	runner.check(frozen != null and frozen.expires_at - sim.time_ms == 5000, "bases freeze for only 5 s")


func test_freeze_spell() -> void:
	var sim := _black_spell_sim()
	var near: Array = []
	for i in 3:
		var m := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(i * 1.5, -23))
		m.locked_until = 1 << 30
		near.append(m)
	var far := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(6, -23))
	var friend := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(0, -22))
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 2, Vector2(0, -23)), Simulation.PlayResult.OK, "cast freeze")
	for m in near:
		runner.check(m.has("upFrozen"), "enemies within 4 frozen")
	runner.check(not far.has("upFrozen") and not friend.has("upFrozen"), "far enemy and ally untouched")
	runner.check_eq(sim.alive_entities(Simulation.TEAM_BLUE).filter(func(e): return e.is_spell_effect()).size(), 0, "field removed itself")


func test_on_the_edge() -> void:
	var sim := _black_spell_sim()
	var allies: Array = []
	for i in 10:
		var f := sim.spawn("Units/White/Footman", Simulation.TEAM_BLUE, Vector2((i % 5) * 1.2, -23 + (i / 5) * 1.2))
		f.base_speed = 0.0
		allies.append(f)
	var archer := sim.spawn("Units/White/Archer", Simulation.TEAM_RED, Vector2(0, -20))
	archer.locked_until = 1 << 30
	var base_range := archer.range_of(1)
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 3, Vector2(0, -23)), Simulation.PlayResult.OK, "cast on the edge")
	for i in 5:
		sim.step()
	runner.check(archer.has("upBefogged"), "non-melee enemies in radius 5 are befogged")
	runner.check_near(archer.range_of(1), base_range - 3.0, "befogged: -3 range")
	var t := sim.time_ms
	while sim.time_ms < t + 3200:
		sim.step()
	var blessed := allies.filter(func(f): return f.has("upBlessedGrievousWounds")).size()
	runner.check_eq(blessed, 4, "one ally enchanted per second (first at once)")
	while sim.time_ms < t + 12000:
		sim.step()
	runner.check_eq(sim.alive_entities(Simulation.TEAM_BLUE).filter(func(e): return e.has("upCharm")).size(), 0, "field gone after 10 enchantments")


func test_permafrost() -> void:
	var sim := _black_spell_sim()
	var slime := sim.spawn("Units/Black/VoidSlime", Simulation.TEAM_RED, Vector2(0, -23))
	slime.locked_until = 1 << 30
	sim.apply_buff(slime, "Frozen")
	for i in 100:   # 3.2 s into the 9 s freeze
		sim.step()
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 4, slime.id), Simulation.PlayResult.OK, "cast permafrost")
	var frozen: Buff = null
	for b in slime.buffs:
		if b.name == "Frozen":
			frozen = b
	runner.check(frozen != null and frozen.expires_at - sim.time_ms == 9000, "old freeze replaced by a fresh 9 s one")
	runner.check_near(slime.max_health, 495.0 + 250.0 - 300.0, "enemy max hp -300 (after the slime's own +250 absorb)")
	runner.check_eq(slime.armor(), SimConstants.ArmorType.HEAVY, "heavy armor while frozen")
	var t := sim.time_ms
	while slime.has("upFrozen") and sim.time_ms < t + 10000:
		sim.step()
	runner.check_eq(slime.armor(), SimConstants.ArmorType.UNARMORED, "armor back once thawed")
	runner.check(slime.has("upBlessedHardening"), "hardening stays")


func test_rip_out_soul() -> void:
	var sim := _black_spell_sim()
	var a := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(0, -23))
	var b := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(3, -23))
	var own := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(-3, -23))
	for m in [a, b, own]:
		m.locked_until = 1 << 30
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 5, Vector2(0, -23)), Simulation.PlayResult.OK, "cast rip out soul")
	sim.step()
	runner.check_near(a.health, 265.0, "nothing before the 500 ms delay")
	for i in 16:
		sim.step()
	runner.check_near(a.health, 265.0 * 0.7, "30% max hp")
	runner.check(a.has("upBanished") and b.has("upBanished"), "banished")
	runner.check(own.has("upBanished"), "own units in the area are hit too")
	runner.check_eq(sim.alive_entities(Simulation.TEAM_BLUE).filter(func(e): return e.is_spell_effect()).size(), 0, "effect removed itself")


func test_shatter_ice() -> void:
	var sim := _black_spell_sim()
	var frozen := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(0, -23))
	var warm := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(2, -23))
	var tower := sim.spawn("Units/Neutral/LanetowerLevel1", Simulation.TEAM_RED, Vector2(-2, -23))
	frozen.locked_until = 1 << 30
	warm.locked_until = 1 << 30
	sim.apply_buff(frozen, "Frozen")
	sim.apply_buff(tower, "Frozen")
	var tower_hp := tower.health
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 6, Vector2(0, -23)), Simulation.PlayResult.OK, "cast shatter ice")
	runner.check_near(frozen.health, 265.0 - 250.0, "250 to frozen units")
	runner.check_near(warm.health, 265.0, "unfrozen units untouched")
	runner.check_near(tower.health, tower_hp - 800.0, "800 to frozen buildings")


func test_sapling_timed_life_and_flourish() -> void:
	var sim := Simulation.new(7, 4)
	sim.spawn_bases()
	var sapling := sim.spawn("Units/Green/Sapling", Simulation.TEAM_BLUE, Vector2(-60, -23))
	runner.check_near(sapling.max_health, 2.0, "sapling has 2 hp")
	while sapling.alive and sim.time_ms < 20000:
		sim.step()
	runner.check(not sapling.alive, "sapling died")
	runner.check(sim.time_ms >= 17000 and sim.time_ms < 17100, "timed life 17 s (got %d)" % sim.time_ms)
	var blessed := sim.spawn("Units/Green/Sapling", Simulation.TEAM_BLUE, Vector2(-60, -23))
	var t := sim.time_ms
	while sim.time_ms < t + 1500:
		sim.step()
	runner.check(blessed.position.distance_to(Vector2(-60, -23)) > 1.0, "saplings walk the lane")
	sim.apply_buff(blessed, "BlessingStrength")
	runner.check_near(blessed.max_health, 2.0 + 40.0 + 50.0, "flourish: +50 max hp on the first enchantment")
	while sim.time_ms < t + 20000:
		sim.step()
	runner.check(blessed.alive, "an enchanted sapling is permanent")


func test_thistle_evasion() -> void:
	var sim := Simulation.new(7, 4)
	var thistle := sim.spawn("Units/Green/Thistle", Simulation.TEAM_BLUE, Vector2(0, -23))
	runner.check_eq(thistle.target_count(1), 2, "multishot: 2 targets")
	var dodged := 0
	for i in 400:
		thistle.health = 27.0
		sim.deal_damage(thistle, 5.0, SimConstants.DamageType.RANGED, null)
		if thistle.health == 27.0:
			dodged += 1
	runner.check(dodged > 120 and dodged < 200, "about 40%% of hits are dodged (got %d of 400)" % dodged)
	var spell_dodged := 0
	for i in 100:
		thistle.health = 27.0
		sim.deal_damage(thistle, 5.0, SimConstants.DamageType.SPELL, null)
		if thistle.health == 27.0:
			spell_dodged += 1
	runner.check_eq(spell_dodged, 0, "spell damage cannot be dodged")


func test_wisp_depleting_bounce() -> void:
	var sim := Simulation.new(7, 4)
	var wisp := sim.spawn("Units/Green/Wisp", Simulation.TEAM_BLUE, Vector2(0, -23))
	var monks: Array = []   # 2 hp saplings: each hit only depletes 2 of the 64, so the shot keeps bouncing
	for i in 9:
		var m := sim.spawn("Units/Green/Sapling", Simulation.TEAM_RED, Vector2(4 + (i % 3) * 1.5, -23 + (i / 3) * 1.5))
		m.locked_until = 1 << 30
		monks.append(m)
	var shots: Array = []
	var on_proj := func(p): shots.append(p)
	sim.projectile_spawned.connect(on_proj)
	while shots.is_empty() and sim.time_ms < 6000:
		sim.step()
	for i in 60:
		sim.step()
	sim.projectile_spawned.disconnect(on_proj)
	runner.check_eq(shots.size(), 1, "one wisp shot")
	if shots.is_empty():
		return
	var hit := 0
	for m in monks:
		if not m.alive:
			hit += 1
	runner.check_eq(hit, 7, "6 bounces after the first hit: 7 saplings killed")
	runner.check_near(shots[0].damage, 64.0 - 7 * 2.0, "each hit depletes the damage dealt")


func test_rootling_root_network() -> void:
	var sim := Simulation.new(7, 4)
	var rootling := sim.spawn("Units/Green/Rootling", Simulation.TEAM_BLUE, Vector2(0, -23))
	var target := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(4, -23))
	var near := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(6, -23))
	var far := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(12, -23))
	for m in [target, near, far]:
		m.locked_until = 1 << 30
	sim.apply_buff(near, "Root")
	sim.step()
	runner.check(target.linked_from(rootling.id), "beam links the nearest enemy")
	runner.check(target.has("upRooted"), "rooted once when the beam forms")
	runner.check(not rootling.moving, "preemptive: stands while linked")
	var hp := target.health
	var near_hp := near.health
	for i in 33:
		sim.step()
	runner.check_near(target.health, hp - 12.0 - 10.0 - 1.5, "12 beam damage per second, the 10 splash (it is rooted too) and a root tick")
	runner.check_near(near.health, near_hp - 10.0 - 1.5, "10 splash to rooted enemies within 3 of the target, plus its own root tick")
	runner.check_near(far.health, 265.0, "far unit untouched")


func test_heart_of_the_forest() -> void:
	var sim := Simulation.new(7, 4)
	sim.spawn_bases()
	var heart := sim.spawn("Units/Green/HeartOfTheForest", Simulation.TEAM_BLUE, Vector2(-60, -23))
	var a := sim.spawn("Units/White/Footman", Simulation.TEAM_BLUE, Vector2(-58, -23))
	var b := sim.spawn("Units/White/Footman", Simulation.TEAM_BLUE, Vector2(-56, -23))
	a.base_speed = 0.0
	b.base_speed = 0.0
	runner.check_eq(heart.mana, 3, "starts with 3 mana")
	while not (a.has("upBlessedStrength") or b.has("upBlessedStrength")) and sim.time_ms < 3000:
		sim.step()
	var first := a if a.has("upBlessedStrength") else b
	runner.check(first.has("upBlessedStrength"), "marks its target at once")
	runner.check_eq(heart.mana, 0, "spends 3 mana")
	for i in 40:
		sim.step()
	runner.check(first.has("upBlessed"), "the projectile delivers Blessing of Strength")
	runner.check_near(first.max_health, 32.0 + 40.0, "+40 max hp")
	runner.check_near(first.damage(), 13.0 + 8.0, "+8 damage")
	var t := sim.time_ms
	while heart.mana < 3 and sim.time_ms < t + 12000:
		sim.step()
	runner.check(sim.time_ms - t >= 6800 and sim.time_ms - t < 8200, "+1 mana per 3 s, timer running since the cast (got %d)" % (sim.time_ms - t))
	var enemy := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(heart.position.x + 6, -23))
	enemy.locked_until = 1 << 30
	for i in 5:
		sim.step()
	runner.check(not heart.moving, "waits while an enemy is within 10")


func test_spore_field() -> void:
	var sim := Simulation.new(7, 4)
	var spore := sim.spawn("Units/Green/Spore", Simulation.TEAM_BLUE, Vector2(0, -23))
	var hurt := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(2, -23))
	hurt.base_speed = 0.0
	hurt.health = 100.0
	var flyer := sim.spawn("Units/Green/Wisp", Simulation.TEAM_RED, Vector2(-2, -23))
	flyer.locked_until = 1 << 30
	sim._kill(spore)
	var fields := sim.alive_entities(Simulation.TEAM_BLUE).filter(func(e): return e.unit_id == "Effects/SporeField")
	runner.check_eq(fields.size(), 1, "death rattle spawns a spore field")
	sim.step()
	runner.check(flyer.has("upGrounded") and not flyer.has("upFlying") and flyer.has("upGround"), "flying enemies in 4 are grounded")
	for i in 32:
		sim.step()
	runner.check_near(hurt.health, 130.0, "injured allies heal 30 per second")
	while fields[0].alive and sim.time_ms < 12000:
		sim.step()
	runner.check(sim.time_ms >= 10000 and sim.time_ms < 10100, "field lasts 10 s (got %d)" % sim.time_ms)
	runner.check(not hurt.linked_from(fields[0].id), "heal link breaks with the field")
	while flyer.has("upGrounded") and sim.time_ms < 20000:
		sim.step()
	runner.check(sim.time_ms >= 15000 and sim.time_ms < 15100, "grounded for 15 s (got %d)" % sim.time_ms)
	runner.check(flyer.has("upImmobilized") and flyer.has("upFlying"), "take-off: immobilized briefly, flying again")


func test_woodwalker_and_sapling_farm_summons() -> void:
	var sim := Simulation.new(7, 4)
	sim.spawn_bases()
	var walker := sim.spawn("Units/Green/Woodwalker", Simulation.TEAM_BLUE, Vector2(-60, -23))
	runner.check_eq(walker.mana, 4, "starts with 4 mana")
	var saplings := func(): return sim.alive_entities(Simulation.TEAM_BLUE).filter(func(e): return e.unit_id == "Units/Green/Sapling").size()
	for i in 30:   # 800 ms actionpoint
		sim.step()
	runner.check_eq(saplings.call(), 2, "4 mana: summons 2 saplings")
	runner.check_eq(walker.mana, 0, "mana spent")
	var t := sim.time_ms
	while walker.mana < 4 and sim.time_ms < t + 15000:
		sim.step()
	runner.check(sim.time_ms - t >= 11000 and sim.time_ms - t < 12200, "+1 mana / 3 s, next summon after 12 s (got %d)" % (sim.time_ms - t))
	var farm := sim.spawn("Units/Green/SaplingFarm", Simulation.TEAM_RED, Vector2(60, -23))
	var red_saplings := func(): return sim.alive_entities(Simulation.TEAM_RED).filter(func(e): return e.unit_id == "Units/Green/Sapling").size()
	for i in 20:   # 500 ms actionpoint
		sim.step()
	runner.check_eq(red_saplings.call(), 3, "farm: 5 mana -> 3 saplings at once")
	runner.check_eq(farm.mana, 0, "farm mana spent")


func test_rootdude() -> void:
	var sim := Simulation.new(7, 4)
	var dude := sim.spawn("Units/Green/Rootdude", Simulation.TEAM_BLUE, Vector2(0, -23))
	dude.base_speed = 0.0
	runner.check_eq(dude.mana, 0, "no mana at start")
	var archer := sim.spawn("Units/White/Archer", Simulation.TEAM_RED, Vector2(9, -23))
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(6, -23))
	archer.locked_until = 1 << 30
	monk.locked_until = 1 << 30
	dude.health = 100.0
	sim.heal(dude, 60.0, 0, null)
	runner.check_eq(dude.mana, 1, "+1 mana per 50 hp healed")
	for i in 30:
		sim.step()
	runner.check(monk.has("upRooted") and not archer.has("upRooted"), "root braid prefers melee units over the farther archer")
	runner.check_eq(dude.mana, 0, "one mana per braid")
	sim.heal(dude, 50.0, 0, null)
	for i in 30:
		sim.step()
	runner.check(archer.has("upRooted"), "next braid: the rooted monk is immune, the archer is next")
	sim.apply_buff(dude, "BlessingStrength")
	runner.check_eq(dude.mana, 4, "an enchantment fills the mana")


func test_forest_guardian_shared_cooldown() -> void:
	var sim := Simulation.new(7, 4)
	var guardian := sim.spawn("Units/Green/ForestGuardian", Simulation.TEAM_BLUE, Vector2(0, -23))
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(8, -23))
	monk.locked_until = 1 << 30
	var tower := sim.spawn("Units/Neutral/LanetowerLevel1", Simulation.TEAM_RED, Vector2(20, -23))
	var shots: Array = []
	var on_proj := func(p): shots.append([sim.time_ms, p.target_id, p.damage])
	sim.projectile_spawned.connect(on_proj)
	for i in 200:
		sim.step()
	runner.check(shots.size() >= 2, "guardian fires (got %d shots)" % shots.size())
	if shots.size() >= 2:
		runner.check(shots[1][0] - shots[0][0] >= 2800, "shots 2800 ms apart (got %d)" % (shots[1][0] - shots[0][0]))
	runner.check(shots.filter(func(s): return s[1] == tower.id).is_empty(), "the unit shot comes first in the chain and wins the shared cooldown")
	sim._kill(monk)
	shots.clear()
	for i in 120:
		sim.step()
	sim.projectile_spawned.disconnect(on_proj)
	var lobs := shots.filter(func(s): return s[1] == tower.id)
	runner.check(not lobs.is_empty() and is_equal_approx(lobs[0][2], 16.0), "with no unit in 11, a 16-damage lob at the building 20 away")
	runner.check(guardian.lifetime_ms == 90000, "building lifetime 90 s")


func test_groundbreaker_rupture() -> void:
	var sim := Simulation.new(7, 4)
	var breaker := sim.spawn("Units/Green/Groundbreaker", Simulation.TEAM_BLUE, Vector2(0, -23))
	runner.check(breaker.has("upBurrowed") and breaker.has("upInvincible"), "spawns burrowed and invincible")
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(6, -23))
	monk.locked_until = 1 << 30
	sim.deal_damage(breaker, 50.0, SimConstants.DamageType.MELEE, monk)
	runner.check_near(breaker.health, 345.0, "no damage while burrowed")
	while monk.health == 265.0 and sim.time_ms < 6000:
		sim.step()
	runner.check_near(monk.health, 265.0 - 120.0, "rupture: 120 splash at its own position")
	runner.check(not breaker.has("upBurrowed") and not breaker.has("upInvincible"), "unburrowed after the rupture")


func test_oracle_feast() -> void:
	var sim := Simulation.new(7, 4)
	var oracle := sim.spawn("Units/Green/Oracle", Simulation.TEAM_BLUE, Vector2(0, -23))
	runner.check_eq(oracle.charge_capacity_cap, 12, "eats up to 12 saplings")
	for i in 14:
		var s := sim.spawn("Units/Green/Sapling", Simulation.TEAM_BLUE, Vector2(2 + (i % 4) * 0.8, -23 + (i / 4) * 0.8))
		s.base_speed = 0.0
	for i in 250:
		sim.step()
	var left := sim.alive_entities(Simulation.TEAM_BLUE).filter(func(e): return e.unit_id == "Units/Green/Sapling").size()
	runner.check_eq(left, 2, "12 saplings sacrificed, 2 spared")
	runner.check_eq(oracle.charge_capacity, 12, "capacity counter full")
	runner.check_near(oracle.max_health, 610.0 + 12 * 60.0, "+60 max hp per sapling")
	runner.check_eq(oracle.ammo, 12, "+1 charge per sapling")


func test_brratu() -> void:
	var sim := Simulation.new(7, 4)
	sim.spawn_bases()
	var brratu := sim.spawn("Units/Green/Brratu", Simulation.TEAM_BLUE, Vector2(-60, -23))
	runner.check_near(brratu.damage(), 34.0 + 0.2 * 1800.0, "damage 34 + 0.2 x health")
	brratu.health = 900.0
	runner.check_near(brratu.damage(), 34.0 + 180.0, "scales with current health")
	sim.apply_buff(brratu, "BlessingStrength")
	runner.check_near(brratu.max_health, 1800.0 + 40.0 + 300.0, "ancient wisdom: +300 max hp per enchantment")
	sim._teleport(brratu, Vector2(-33, -23))   # away from the blue lane tower's guns
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-30, -23))
	monk.locked_until = 1 << 30
	var start := brratu.position
	while sim.time_ms < 8000:
		sim.step()
	runner.check_near(monk.health, 265.0, "ignores units, only attacks buildings")
	runner.check(brratu.position.x > start.x + 5.0, "walks straight down the lane at 2 u/s past the monk")
	runner.check(brratu.no_pathfinding, "no pathfinding")


func _green_spell_sim() -> Simulation:
	var sim := Simulation.new(23, 4)
	sim.spawn_bases()
	var c: Commander = sim.commanders[Simulation.TEAM_BLUE]
	c.set_deck(["Spells/Green/EntanglingRoots.sps", "Spells/Green/GiantGrowth.sps", "Spells/Green/EvolveOracle.sps",
		"Spells/Green/HealingGarden.sps", "Spells/Green/EvolveThistle.sps", "Spells/Green/Saplingcharge.sps"])
	c.gold = 1000.0
	c.raise_tier(3)
	while not sim.game_started:
		sim.step()
	return sim


func test_entangling_roots() -> void:
	var sim := _green_spell_sim()
	var ground: Array = []
	for i in 18:
		var m := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2((i % 6) * 0.6, -23 + (i / 6) * 0.6))
		m.locked_until = 1 << 30
		ground.append(m)
	var flyer := sim.spawn("Units/Green/Wisp", Simulation.TEAM_RED, Vector2(0, -22))
	flyer.locked_until = 1 << 30
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, Vector2(0, -23)), Simulation.PlayResult.OK, "cast entangling roots")
	var rooted := ground.filter(func(m): return m.has("upRooted")).size()
	runner.check_eq(rooted, 16, "up to 16 ground enemies rooted")
	runner.check(not flyer.has("upRooted"), "flying units are not rooted")


func test_giant_growth() -> void:
	var sim := _green_spell_sim()
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(0, -23))
	monk.base_speed = 0.0
	monk.health = 100.0
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 1, monk.id), Simulation.PlayResult.OK, "cast giant growth")
	runner.check_near(monk.max_health, 265.0 + 160.0, "+160 max hp")
	runner.check(monk.has("upBlessed") and monk.has("upBlessedGrowth"), "enchanted")
	var t := sim.time_ms
	while sim.time_ms < t + 1100:
		sim.step()
	runner.check_near(monk.health, 260.0 + 0.02 * 425.0, "heals 2 % of max hp per second (the +160 also filled the cap)")
	while sim.time_ms < t + 12000:
		sim.step()
	runner.check_near(monk.health, 260.0 + 12 * 0.02 * 425.0, "one tick per second")
	monk.health = 100.0
	while sim.time_ms < t + 25000:
		sim.step()
	runner.check_near(monk.health, 100.0 + 8 * 0.02 * 425.0, "20 ticks in total, then the heal stops")
	runner.check(monk.has("upBlessedGrowth") and is_equal_approx(monk.max_health, 425.0), "the hp bonus stays")


func test_evolve_oracle_and_thistle() -> void:
	var sim := _green_spell_sim()
	var sapling := sim.spawn("Units/Green/Sapling", Simulation.TEAM_BLUE, Vector2(0, -23))
	sapling.base_speed = 0.0
	for i in 10:   # saplings are untargetable during their 200 ms spawn lockout
		sim.step()
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 2, sapling.id), Simulation.PlayResult.OK, "cast evolve oracle on a sapling")
	runner.check(not sapling.alive and sapling.exiled, "the sapling is exiled")
	var oracles := sim.alive_entities(Simulation.TEAM_BLUE).filter(func(e): return e.unit_id == "Units/Green/Oracle")
	runner.check_eq(oracles.size(), 1, "an oracle appears")
	if not oracles.is_empty():
		runner.check_near(oracles[0].health, 0.6 * 610.0, "at 60 % health")
		runner.check(oracles[0].has("upSummoningSickness"), "1 s of summoning sickness")
	var saplings: Array = []
	for i in 8:
		var s := sim.spawn("Units/Green/Sapling", Simulation.TEAM_BLUE, Vector2(10 + (i % 4) * 0.8, -23 + (i / 4) * 0.8))
		s.base_speed = 0.0
		saplings.append(s)
	for i in 10:
		sim.step()
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 4, Vector2(10, -23)), Simulation.PlayResult.OK, "cast evolve thistle")
	var thistles := sim.alive_entities(Simulation.TEAM_BLUE).filter(func(e): return e.unit_id == "Units/Green/Thistle").size()
	runner.check_eq(thistles, 6, "up to 6 saplings become thistles")
	runner.check_eq(saplings.filter(func(s): return s.alive).size(), 2, "the other saplings stay")


func test_healing_garden() -> void:
	var sim := _green_spell_sim()
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(0, -23))
	var walker := sim.spawn("Units/Green/Woodwalker", Simulation.TEAM_BLUE, Vector2(2, -23))
	monk.base_speed = 0.0
	walker.base_speed = 0.0
	walker.mana = 0
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 3, Vector2(1, -23)), Simulation.PlayResult.OK, "cast healing garden")
	for i in 3:
		sim.step()
	runner.check(walker.has("upEnergyAuraBuffed"), "mana users in 3.5 get the energy aura")
	var t := sim.time_ms
	while sim.time_ms < t + 2200:
		sim.step()
	var blessed := [monk, walker].filter(func(u): return u.has("upBlessedHealth"))
	runner.check_eq(blessed.size(), 2, "one unit enchanted at once, another after 2 s")
	runner.check_near(monk.max_health, 265.0 + 0.3 * 265.0 + 50.0, "blessing of health: +30 % max hp + 50")
	while sim.time_ms < t + 3200:
		sim.step()
	runner.check(walker.mana >= 1, "energy aura: +1 mana per 3 s (walker's own regen stops at 0 mana? it has its own too)")


func test_saplingcharge() -> void:
	var sim := _green_spell_sim()
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 5, Vector2(-20, -23)), Simulation.PlayResult.OK, "cast saplingcharge")
	var count := func(): return sim.alive_entities(Simulation.TEAM_BLUE).filter(func(e): return e.unit_id == "Units/Green/Sapling").size()
	var t := sim.time_ms
	while sim.time_ms < t + 3300:
		sim.step()
	# both timers fire on the 1 s tick in component order: the first wave activates the second one at once
	runner.check_eq(count.call(), 25, "first tick: 15 + 10 saplings by ~3.1 s")
	while sim.time_ms < t + 14500:
		sim.step()
	runner.check_eq(count.call(), 125, "15 + 11 ticks x 10 saplings in total (the 11th tick spawns before the removal)")
	runner.check_eq(sim.alive_entities(Simulation.TEAM_BLUE).filter(func(e): return e.unit_id == "Spells/Green/Saplingcharge").size(), 1, "the field is still there before 15 s")
	while sim.time_ms < t + 15100:
		sim.step()
	runner.check_eq(sim.alive_entities(Simulation.TEAM_BLUE).filter(func(e): return e.unit_id == "Spells/Green/Saplingcharge").size(), 0, "field gone after 15 s")


func test_damper_drone_breaching_charge() -> void:
	var sim := Simulation.new(9, 4)
	var drone := sim.spawn("Units/Blue/DamperDrone", Simulation.TEAM_BLUE, Vector2(0, -23))
	drone.mana = 2
	var tower := sim.spawn("Units/Neutral/LanetowerLevel1", Simulation.TEAM_RED, Vector2(1.9, -23))
	tower.locked_until = 1 << 30
	var hp := tower.health
	for i in 3:
		sim.step()
	runner.check(not drone.alive, "explodes at an enemy building")
	runner.check_near(tower.health, hp - (20.0 + 2 * 15.0) * 4.0, "20 + 15 per energy siege damage (x4 on fortified)")
	var other := sim.spawn("Units/Blue/DamperDrone", Simulation.TEAM_BLUE, Vector2(20, -23))
	sim.deal_damage(other, 10.0, SimConstants.DamageType.SPLASH, null)
	runner.check_near(other.health, 41.0 - 10.0 * 0.3 * 0.85, "takes 30 % of splash damage (then light armor)")


func test_gatling_drone_beam() -> void:
	var sim := Simulation.new(9, 4)
	var drone := sim.spawn("Units/Blue/GatlingDrone", Simulation.TEAM_BLUE, Vector2(0, -23))
	var target := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(4, -23))
	var near := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(5.5, -23))
	target.locked_until = 1 << 30
	near.locked_until = 1 << 30
	sim.step()
	runner.check(target.linked_from(drone.id), "beam on the nearest enemy")
	var hp := target.health
	var near_hp := near.health
	for i in 17:
		sim.step()
	runner.check_near(target.health, hp - 11.0 - 3.0, "11 armor-piercing beam damage plus 3 splash every 500 ms")
	runner.check_near(near.health, near_hp - 3.0, "3 splash in 2.5 around the target")


func test_gatling_turret_energy_and_gadget_cap() -> void:
	var sim := Simulation.new(9, 4)
	var turret := sim.spawn("Units/Blue/GatlingTurret", Simulation.TEAM_BLUE, Vector2(0, -23))
	runner.check_eq(sim.commanders[Simulation.TEAM_BLUE].gadget_count, 1, "gadgets are counted")
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(4, -23))
	monk.locked_until = 1 << 30
	sim.step()
	runner.check_eq(turret.mana, 19, "linking costs one energy at once")
	var t := sim.time_ms
	while sim.time_ms < t + 3100:
		sim.step()
	runner.check_eq(turret.mana, 16, "one energy per second of uptime")
	turret.mana = 0
	for i in 40:
		sim.step()
	runner.check(not monk.linked_from(turret.id), "no energy, no beam")
	for i in 5:
		sim.spawn("Units/Blue/MissileTurret", Simulation.TEAM_BLUE, Vector2(-20 + i * 2, -23))
	runner.check(not turret.alive, "a 6th gadget sacrifices the oldest one")
	runner.check_eq(sim.commanders[Simulation.TEAM_BLUE].gadget_count, 5, "cap of 5")


func test_missile_turret_and_ammo_factory() -> void:
	var sim := Simulation.new(9, 4)
	var turret := sim.spawn("Units/Blue/MissileTurret", Simulation.TEAM_BLUE, Vector2(0, -23))
	var flyer := sim.spawn("Units/Green/Wisp", Simulation.TEAM_RED, Vector2(8, -23))
	var walker := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(9, -23))
	flyer.locked_until = 1 << 30
	walker.locked_until = 1 << 30
	while flyer.health == 75.0 and sim.time_ms < 4000:
		sim.step()
	runner.check(not flyer.alive, "missiles prefer flyers and deal double damage: 94 kills the 75 hp wisp")
	runner.check(turret.mana < 14 and (14 - turret.mana) % 2 == 0, "a missile costs 2 energy (got %d)" % turret.mana)
	for i in 100:
		sim.step()
	runner.check(walker.health <= 265.0 - 94.0, "splash 47 from the first missile, then direct hits (got %.0f)" % walker.health)
	turret.mana = 0
	var factory := sim.spawn("Units/Blue/AmmoFactory", Simulation.TEAM_BLUE, Vector2(3, -23))
	for i in 60:
		sim.step()
	runner.check(turret.mana >= 1, "the ammo factory refills allies (got %d)" % turret.mana)
	runner.check(factory.mana < 4, "and spends its own energy")


func test_induction() -> void:
	var sim := _black_spell_sim()
	var drone := sim.spawn("Units/Blue/PhaseDrone", Simulation.TEAM_BLUE, Vector2(-40, -23))
	drone.mana = 0
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(-45, -23))
	monk.base_speed = 0.0
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, monk.id), Simulation.PlayResult.OK, "cast frenzy near the drone")
	runner.check_eq(drone.mana, 1, "induction: +1 energy per allied spell within 12")


func test_observer_drone_range_aura_and_cloak() -> void:
	var sim := Simulation.new(9, 4)
	var drone := sim.spawn("Units/Blue/ObserverDrone", Simulation.TEAM_BLUE, Vector2(0, -23))
	var archer := sim.spawn("Units/White/Archer", Simulation.TEAM_BLUE, Vector2(2, -23))
	var turret := sim.spawn("Units/Blue/GatlingTurret", Simulation.TEAM_BLUE, Vector2(-2, -23))
	var footman := sim.spawn("Units/White/Footman", Simulation.TEAM_BLUE, Vector2(0, -21))
	archer.locked_until = 1 << 30
	var base_range := archer.range_of()
	var turret_range := turret.range_of()
	sim.step()
	runner.check(drone.has("upInvisible"), "cloaked while no enemy is near")
	runner.check(not archer.linked_from(drone.id), "the range aura activates only after 1 s")
	while sim.time_ms < 1200:
		sim.step()
	runner.check_near(archer.range_of(), base_range + 3.0, "+3 range for ranged units")
	runner.check_near(turret.range_of(), turret_range + 5.0, "+5 range for ranged buildings")
	runner.check(not footman.linked_from(drone.id), "melee units are not linked")
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(10, -23))
	monk.locked_until = 1 << 30
	for i in 3:
		sim.step()
	runner.check(drone.has("upInvisible"), "a ground enemy does not reveal a flyer")
	var wisp := sim.spawn("Units/Green/Wisp", Simulation.TEAM_RED, Vector2(10, -23))
	wisp.locked_until = 1 << 30
	for i in 3:
		sim.step()
	runner.check(not drone.has("upInvisible"), "a flying enemy within 15 reveals it")
	sim._kill(wisp)
	for i in 12:
		sim.step()
	runner.check(drone.has("upInvisible"), "cloaks again once the enemy is gone")


func test_atlas_supreme_levels() -> void:
	var sim := Simulation.new(2, 4)
	var lvl1 := sim.spawn("Units/Blue/Atlas", Simulation.TEAM_BLUE, Vector2(-50, -23), Vector2.ZERO, 1)
	runner.check_near(lvl1.max_health, 155.0, "level 1: 155 hp")
	runner.check_eq(lvl1.base_armor, SimConstants.ArmorType.UNARMORED, "level 1: unarmored")
	var lvl5 := sim.spawn("Units/Blue/Atlas", Simulation.TEAM_BLUE, Vector2(-50, -20), Vector2.ZERO, 5)
	runner.check_near(lvl5.max_health, 155.0 + 70.0 * 4, "level 5: +70 hp per level above 1")
	runner.check_eq(lvl5.base_armor, SimConstants.ArmorType.MEDIUM, "level 5: medium armor")
	var lvl10 := sim.spawn("Units/Blue/Atlas", Simulation.TEAM_BLUE, Vector2(-50, -17), Vector2.ZERO, 10)
	runner.check_eq(lvl10.base_armor, SimConstants.ArmorType.HEAVY, "level 6+: heavy armor")
	sim.spawn_bases()
	var c: Commander = sim.commanders[Simulation.TEAM_BLUE]
	c.set_deck(["Units/Blue/AtlasDrop"])
	c.free_cards = true
	for a in [lvl1, lvl5, lvl10]:
		sim._kill(a)
	var levels := []
	for i in 12:
		runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, Vector2(-50, -23)), Simulation.PlayResult.OK, "play atlas %d" % (i + 1))
		var atlas: SimEntity = sim.alive_entities(Simulation.TEAM_BLUE).filter(func(e): return e.has("upLegendary"))[0]
		levels.append(atlas.level)
		sim._kill(atlas)
	runner.check_eq(levels, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 10], "level = times played, capped at 10")


func test_atlas_active_armor_and_induction_repair() -> void:
	var sim := _black_spell_sim()
	var atlas := sim.spawn("Units/Blue/Atlas", Simulation.TEAM_BLUE, Vector2(-40, -23), Vector2.ZERO, 1)
	atlas.locked_until = 1 << 30
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-36, -23))
	monk.locked_until = 1 << 30
	var t := sim.time_ms
	while sim.time_ms < t + 2300:   # legendary spawn lockout
		sim.step()
	var hp := atlas.health
	var dealt := sim.deal_damage(atlas, 20.0, SimConstants.DamageType.MELEE, monk)
	runner.check_near(atlas.health, hp - dealt - 10.0, "active armor: 10 true feedback damage per hit taken")
	var monk_hp := monk.health
	for i in 40:
		sim.step()
	runner.check(monk.health < monk_hp, "a 10-damage projectile flies at a random enemy within 6.5")
	hp = atlas.health
	sim.deal_damage(atlas, 5.0, SimConstants.DamageType.TRUE, atlas)
	runner.check_near(atlas.health, hp - 5.0, "self-inflicted damage does not trigger it")
	atlas.health = 100.0
	var ally := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(-45, -23))
	ally.base_speed = 0.0
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, ally.id), Simulation.PlayResult.OK, "cast frenzy near atlas")
	runner.check_near(atlas.health, 100.0 + 15.5, "induction repair: 10 % of max hp per allied spell within 12")


func test_phase_drone_teleport_strike_and_shield_overload() -> void:
	var sim := Simulation.new(2, 4)
	var drone := sim.spawn("Units/Blue/PhaseDrone", Simulation.TEAM_BLUE, Vector2(-40, -23))
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-34, -23))
	monk.locked_until = 1 << 30
	var hp := monk.health
	var t := sim.time_ms
	while monk.health == hp and sim.time_ms < t + 2000:
		sim.step()
	runner.check_near(monk.health, hp - 100.0, "teleport strike: 100 ability damage (armor does not apply)")
	runner.check_near(drone.position.distance_to(monk.position), drone.collision_radius + monk.collision_radius - 0.1, "blinked next to its victim", 0.05)
	runner.check_eq(drone.mana, 0, "costs its 2 energy")
	drone.locked_until = 1 << 30
	sim.deal_damage(drone, 10.0, SimConstants.DamageType.MELEE, monk)
	runner.check(drone.has("upInvincible"), "shield overload: invincible after taking damage")
	var shielded := drone.health
	sim.deal_damage(drone, 10.0, SimConstants.DamageType.MELEE, monk)
	runner.check_near(drone.health, shielded, "no damage while invincible")
	t = sim.time_ms
	while sim.time_ms < t + 2100:
		sim.step()
	runner.check(not drone.has("upInvincible"), "invincibility lasts 2 s")
	sim.deal_damage(drone, 10.0, SimConstants.DamageType.MELEE, monk)
	runner.check(not drone.has("upInvincible"), "shield overload has an 8 s cooldown")
	while sim.time_ms < t + 8100:
		sim.step()
	sim.deal_damage(drone, 10.0, SimConstants.DamageType.MELEE, monk)
	runner.check(drone.has("upInvincible"), "ready again after 8 s")


func test_inductioner_missile_launcher() -> void:
	var sim := Simulation.new(2, 4)
	var ind := sim.spawn("Units/Blue/Inductioner", Simulation.TEAM_BLUE, Vector2(-40, -23))
	ind.locked_until = 1 << 30
	var wisp := sim.spawn("Units/Green/Wisp", Simulation.TEAM_RED, Vector2(-28, -23))
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-30, -23))
	wisp.locked_until = 1 << 30
	monk.locked_until = 1 << 30
	for i in 20:
		sim.step()
	runner.check(wisp.alive and monk.health == 265.0, "no energy: no missile, and the main gun is ground-only within 8")
	ind.mana = 2
	var t := sim.time_ms
	while wisp.alive and sim.time_ms < t + 3000:
		sim.step()
	runner.check(not wisp.alive, "missile launcher: 53 x2 vs flying kills the wisp at range 15")
	runner.check_eq(ind.mana, 0, "costs 2 energy")


func test_shield_drone_follow_and_reflect() -> void:
	var sim := Simulation.new(2, 4)
	var drone := sim.spawn("Units/Blue/ShieldDrone", Simulation.TEAM_BLUE, Vector2(-40, -23))
	var footman := sim.spawn("Units/White/Footman", Simulation.TEAM_BLUE, Vector2(-34, -23))
	footman.base_speed = 0.0
	var archer := sim.spawn("Units/White/Archer", Simulation.TEAM_RED, Vector2(-26, -23))
	archer.locked_until = 1 << 30
	for i in 40:
		sim.step()
	runner.check(drone.position.distance_to(footman.position) < 3.5 and drone.position.x > -39.0, "follows the melee ally (got %.1f)" % drone.position.distance_to(footman.position))
	runner.check(footman.linked_from(drone.id), "reflective shield linked to allies within 7 after 1 s")
	runner.check(footman.has("upProjectileReflector"), "the link grants upProjectileReflector")
	archer.locked_until = 0
	drone.locked_until = 1 << 30
	var drone_hp := drone.health
	var archer_hp := archer.health
	var t := sim.time_ms
	while archer.health == archer_hp and sim.time_ms < t + 4000:
		sim.step()
	runner.check(archer.health < archer_hp, "the archer's arrow flies back at it")
	runner.check_near(archer_hp - archer.health, 20.0 * 0.4, "reflected at 40 % (archer 20 ranged, light armor takes ranged in full)")
	runner.check_near(drone.health, drone_hp - 10.0, "the drone pays 10 true damage per reflection")


func test_airdominator_hits_flyers_only() -> void:
	var sim := Simulation.new(2, 4)
	var air := sim.spawn("Units/Blue/Airdominator", Simulation.TEAM_BLUE, Vector2(-40, -23))
	var wisp := sim.spawn("Units/Green/Wisp", Simulation.TEAM_RED, Vector2(-28, -23))
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-34, -23))   # outside the missile splash
	wisp.locked_until = 1 << 30
	monk.locked_until = 1 << 30
	var t := sim.time_ms
	while wisp.alive and sim.time_ms < t + 8000:
		sim.step()
	runner.check(not wisp.alive, "two 25 x2 missiles at range 15 kill the 75 hp wisp")
	for i in 120:
		sim.step()
	runner.check_near(monk.health, 265.0, "a flyer's weapon never hits ground units (BothMustHaveAny)")


func test_bombardier_line_laser_and_wave_gun() -> void:
	var sim := Simulation.new(2, 4)
	var bomb := sim.spawn("Units/Blue/Bombardier", Simulation.TEAM_BLUE, Vector2(-40, -23))
	var line: Array = []
	for x in [-33.0, -28.0, -24.0]:
		var m := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(x, -23))
		m.locked_until = 1 << 30
		line.append(m)
	var aside := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-33, -20))
	aside.locked_until = 1 << 30
	var t := sim.time_ms
	while line[0].health == 265.0 and sim.time_ms < t + 3000:
		sim.step()
	for m in line:
		runner.check_near(m.health, 265.0 - 82.0, "laser: 82 splash to every enemy on the 18-long line (monks are unarmored)")
	runner.check_near(aside.health, 265.0, "a unit beside the 1.0-wide line is missed")
	runner.check_eq(bomb.mana, 4, "wave gun waits for a target with max hp >= 300")
	var big := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-25, -30))
	big.locked_until = 1 << 30
	big.max_health = 400.0
	big.health = 400.0
	t = sim.time_ms
	while big.health == 400.0 and sim.time_ms < t + 6000:
		sim.step()
	runner.check_near(big.health, 400.0 - 275.0, "wave gun: 275 ability damage")
	runner.check(big.has("upStunned"), "and a 3 s stun")
	runner.check_eq(bomb.mana, 0, "for all 4 energy")


func test_aegis_starfall_rift_missiles() -> void:
	var sim := Simulation.new(2, 4)
	var ally := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(-39, -23))
	var near := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-41, -23))
	var big := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-32, -23))
	var small := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-31, -20))
	for m in [ally, near, big, small]:
		m.locked_until = 1 << 30
	big.max_health = 400.0
	big.health = 400.0
	var aegis := sim.spawn("Units/Blue/Aegis", Simulation.TEAM_BLUE, Vector2(-40, -23))
	var t := sim.time_ms
	while sim.time_ms < t + 500:
		sim.step()
	runner.check(not ally.alive and not near.alive, "debut starfall kills every unit of both teams within 1.5")
	runner.check(big.alive and small.alive, "but nothing further away")
	while big.alive and sim.time_ms < t + 3000:
		sim.step()
	runner.check(not big.alive and big.exiled, "rift cannon annihilates the highest-max-hp enemy within 11")
	runner.check(small.alive, "one shot per 4 s")
	while sim.time_ms < t + 6000:
		sim.step()
	runner.check(aegis.mana <= 10 and aegis.mana >= 9, "missiles: one energy per 1.8 s after 1.6 s (got %d)" % aegis.mana)


func test_aegis_gatling_cones() -> void:
	var sim := Simulation.new(2, 4)
	var aegis := sim.spawn("Units/Blue/Aegis", Simulation.TEAM_BLUE, Vector2(-40, -23))
	aegis.wela(1).used = true
	aegis.wela(2).used = true
	var south := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-40, -19))
	var west := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-44, -23))
	south.locked_until = 1 << 30
	west.locked_until = 1 << 30
	var t := sim.time_ms
	while sim.time_ms < t + 2500:
		sim.step()
	runner.check(south.link_buffs.has("%d:4" % aegis.id) and not south.link_buffs.has("%d:3" % aegis.id), "the (0,1) cone gatling links the unit in +y")
	runner.check(west.link_buffs.has("%d:3" % aegis.id) and not west.link_buffs.has("%d:4" % aegis.id), "the (-1,0) cone gatling links the unit in -x")
	var hp := south.health
	for i in 17:
		sim.step()
	runner.check(south.health < hp, "beams deal damage every 500 ms")


func _blue_spell_sim() -> Simulation:
	var sim := Simulation.new(31, 4)
	sim.spawn_bases()
	var c: Commander = sim.commanders[Simulation.TEAM_BLUE]
	c.set_deck(["Spells/Blue/AmmoRefill.sps", "Spells/Blue/EnergyRift.sps", "Spells/Blue/Relocate.sps",
		"Spells/Blue/FactoryReset.sps", "Spells/Blue/FluxField.sps", "Spells/Blue/InverseGravity.sps", "Spells/Blue/OrbitalStrike.sps"])
	c.gold = 1000.0
	c.raise_tier(3)
	c.free_cards = true
	while not sim.game_started:
		sim.step()
	return sim


func test_ammo_refill() -> void:
	var sim := _blue_spell_sim()
	var drone := sim.spawn("Units/Blue/DamperDrone", Simulation.TEAM_BLUE, Vector2(-40, -23))   # tier 1, cap 2
	var turret := sim.spawn("Units/Blue/MissileTurret", Simulation.TEAM_BLUE, Vector2(-45, -23))   # tier 2, cap 14
	var aegis := sim.spawn("Units/Blue/Aegis", Simulation.TEAM_BLUE, Vector2(-50, -23))   # tier 3, cap 12
	drone.mana = 0
	turret.mana = 0
	aegis.mana = 0
	var t := sim.time_ms
	while sim.time_ms < t + 1500:   # the legendary spawn lockout makes the Aegis untargetable
		sim.step()
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, drone.id), Simulation.PlayResult.OK, "refill a tier 1 unit")
	runner.check_eq(drone.mana, 2, "tier 1: 100 % of max energy")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, turret.id), Simulation.PlayResult.OK, "refill a tier 2 building")
	runner.check_eq(turret.mana, 7, "tier 2: 50 %")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, aegis.id), Simulation.PlayResult.OK, "refill a tier 3 unit")
	runner.check_eq(aegis.mana, 3, "tier 3: 25 %")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, drone.id), Simulation.PlayResult.BAD_TARGET, "a full unit is no target")
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(-40, -20))
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, monk.id), Simulation.PlayResult.BAD_TARGET, "no energy, no target")


func test_energy_rift() -> void:
	var sim := _blue_spell_sim()
	var turret := sim.spawn("Units/Blue/GatlingTurret", Simulation.TEAM_BLUE, Vector2(-40, -23))
	turret.mana = 0
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-30, -23))
	monk.locked_until = 1 << 30
	var unit := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(-50, -20))
	unit.base_speed = 0.0
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 1, unit.id), Simulation.PlayResult.BAD_TARGET, "buildings only")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 1, turret.id), Simulation.PlayResult.OK, "energy rift on an allied building")
	runner.check(turret.has("upHasEnergyRift"), "marked")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 1, turret.id), Simulation.PlayResult.BAD_TARGET, "one rift per building")
	var t := sim.time_ms
	while sim.time_ms < t + 5500:
		sim.step()
	runner.check(monk.health <= 265.0 - 4 * 24.0 and monk.health > 265.0 - 7 * 24.0, "24 spell damage per second at a random enemy within 14 (got %.0f)" % monk.health)
	while sim.time_ms < t + 31000:
		sim.step()
	runner.check(not turret.has("upHasEnergyRift"), "the rift ends after 30 s")


func test_inverse_gravity() -> void:
	var sim := _blue_spell_sim()
	var wisp := sim.spawn("Units/Green/Wisp", Simulation.TEAM_RED, Vector2(-30, -23))
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(-31, -21))
	var far := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-20, -23))
	for m in [wisp, monk, far]:
		m.locked_until = 1 << 30
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 5, Vector2(-30, -23)), Simulation.PlayResult.OK, "inverse gravity at a point")
	runner.check(wisp.has("upGround") and not wisp.has("upFlying") and wisp.has("upGrounded"), "flyers in 4.5 are grounded")
	runner.check(monk.has("upFlying") and not monk.has("upGround") and monk.has("upLifted"), "ground units of both teams are lifted")
	runner.check(not far.has("upLifted"), "not beyond 4.5")
	var t := sim.time_ms
	while sim.time_ms < t + 15100:
		sim.step()
	runner.check(wisp.has("upFlying") and not wisp.has("upGrounded"), "grounding ends after 15 s")
	runner.check(wisp.has("upImmuneToGrounded") and monk.has("upImmuneToLifted"), "then 10 more seconds of immunity")
	runner.check(wisp.has("upImmobilized"), "and 500 ms immobilized while taking off")
	while sim.time_ms < t + 25100:
		sim.step()
	runner.check(not wisp.has("upImmuneToGrounded") and not wisp.has("upImmobilized"), "immunity over after 25 s")


func test_factory_reset() -> void:
	var sim := _blue_spell_sim()
	var turret := sim.spawn("Units/Blue/GatlingTurret", Simulation.TEAM_BLUE, Vector2(-30, -23))
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-31, -20))
	monk.locked_until = 1 << 30
	turret.mana = 3
	turret.health = 50.0
	monk.health = 100.0
	sim.apply_buff(monk, "Stun", {}, turret)
	var t := sim.time_ms
	while sim.time_ms < t + 5000:
		sim.step()
	var tower := sim.spawn("Units/White/Suntower", Simulation.TEAM_BLUE, Vector2(-28, -25))
	tower.lifetime_started_at = t
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 3, Vector2(-30, -23)), Simulation.PlayResult.OK, "factory reset at a point")
	runner.check_near(turret.health, turret.max_health, "health reset to full")
	runner.check_eq(turret.mana, 20, "energy reset to full")
	runner.check_eq(tower.lifetime_started_at, sim.time_ms, "a timed building's lifetime restarts")
	runner.check_near(monk.health, 265.0, "enemies in radius 4 are reset too")
	runner.check(not monk.has("upStunned"), "and stripped of all buffs")


func test_flux_field() -> void:
	var sim := _blue_spell_sim()
	var drones: Array = []
	for i in 8:
		var d := sim.spawn("Units/Blue/DamperDrone", Simulation.TEAM_BLUE, Vector2(-40 + (i % 4) * 1.2, -23 + (i / 4) * 1.2))
		d.base_speed = 0.0
		d.mana = 0
		drones.append(d)
	var monk := sim.spawn("Units/White/Footman", Simulation.TEAM_BLUE, Vector2(-40, -20))   # no energy pool: never enchanted
	monk.base_speed = 0.0
	var enemy := sim.spawn("Units/White/Archer", Simulation.TEAM_RED, Vector2(-38, -21))
	enemy.locked_until = 1 << 30
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 4, Vector2(-40, -23)), Simulation.PlayResult.OK, "flux field at a point")
	for i in 5:
		sim.step()
	runner.check(enemy.has("upSilenced") and enemy.has("upHasStateEffect"), "enemies in radius 4 are silenced")
	var t := sim.time_ms
	while sim.time_ms < t + 3200:
		sim.step()
	runner.check_eq(drones.filter(func(d): return d.has("upBlessedEnergy")).size(), 6, "6 energy users enchanted, one per 500 ms")
	runner.check(not monk.has("upBlessedEnergy"), "units without energy are skipped")
	var blessed: SimEntity = drones.filter(func(d): return d.has("upBlessedEnergy"))[0]
	runner.check_eq(blessed.mana_cap, 4, "blessing energy: +2 max energy, not filled")
	var most: int = drones.map(func(d): return d.mana).max()
	runner.check(most >= 1, "and +1 energy every 3 s (got %d)" % most)
	runner.check_eq(sim.alive_entities(Simulation.TEAM_BLUE).filter(func(e): return e.has("upCharm")).size(), 0, "field gone after 6 enchantments")
	for i in 5:
		sim.step()
	runner.check(not enemy.has("upSilenced"), "silence ends with the field")
	while sim.time_ms < t + 13000:
		sim.step()
	runner.check_eq(blessed.mana, 4, "four regenerations in total fill the raised cap")


func test_orbital_strike() -> void:
	var sim := _blue_spell_sim()
	var target := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-30, -23))
	var buddy := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-32, -23))
	var far := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-20, -23))
	for m in [target, buddy, far]:
		m.locked_until = 1 << 30
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 6, target.id), Simulation.PlayResult.OK, "orbital strike on an enemy")
	var t := sim.time_ms
	while sim.time_ms < t + 3000:
		sim.step()
	runner.check(target.health <= 265.0 - 5 * 13.0, "13 spell damage every 0.5 s to the marked unit (got %.0f)" % target.health)
	runner.check(buddy.health < 265.0 - 3 * 11.0, "bombs (11 splash) rain on its team within 6 after 1 s (got %.0f)" % buddy.health)
	runner.check_near(far.health, 265.0, "nothing beyond 6")
	while sim.time_ms < t + 15500:
		sim.step()
	var hp := target.health
	var buddy_hp := buddy.health
	for i in 40:
		sim.step()
	runner.check(target.health == hp and buddy.health == buddy_hp, "the strike ends after 15 s")


func test_relocate() -> void:
	var sim := _blue_spell_sim()
	var turret := sim.spawn("Units/Blue/GatlingTurret", Simulation.TEAM_BLUE, Vector2(-40, -23))
	turret.health = 100.0
	turret.mana = 0
	var monk := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(-38, -23))
	monk.base_speed = 0.0
	var far := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(-30, -23))
	far.base_speed = 0.0
	var a := Vector2(-40, -23)
	var b := Vector2(-25, -20)
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 2, a), Simulation.PlayResult.BAD_TARGET, "relocate needs two points")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 2, [a, Vector2(-10, -23)]), Simulation.PlayResult.BAD_TARGET, "points at most 20 apart")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 2, [a, b]), Simulation.PlayResult.OK, "relocate from A to B")
	runner.check(monk.has("upSummoningSickness"), "targets are stopped for 600 ms")
	runner.check(monk.has("upImmuneToRelocate"), "and immune to another relocate")
	var t := sim.time_ms
	while sim.time_ms < t + 600:
		sim.step()
	runner.check_near(turret.position.distance_to(b), 0.0, "buildings blink to B after 500 ms", 0.01)
	runner.check_near(monk.position.distance_to(b + Vector2(2, 0)), 0.0, "units keep their offset to A", 0.01)
	runner.check_near(far.position.x, -30.0, "units beyond 5 of A stay")
	runner.check_near(turret.health, 100.0 + 0.3 * turret.max_health, "tier 1 buildings heal 30 % of max hp")
	runner.check_eq(turret.mana, 6, "and refill 30 % energy")
	while sim.time_ms < t + 20100:
		sim.step()
	runner.check(not monk.has("upImmuneToRelocate"), "relocate immunity lasts 20 s")


func test_golems_standard_units() -> void:
	var sim := Simulation.new(2, 4)
	var small := sim.spawn("Units/Golems/GolemsSmallMeleeGolem", Simulation.TEAM_BLUE, Vector2(-40, -23))
	var victim := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-38.5, -23))
	victim.locked_until = 1 << 30
	var t := sim.time_ms
	while victim.health == 265.0 and sim.time_ms < t + 3000:
		sim.step()
	runner.check_near(victim.health, 265.0 - 14.0, "small melee golem: 14 melee")
	runner.check(small.has("upSpellImmune"), "and spell immune")
	sim._kill(small)
	sim._kill(victim)
	# medium melee golem: 45 degree tremor cone of 32 splash over 6.0
	var medium := sim.spawn("Units/Golems/GolemsMediumMeleeGolem", Simulation.TEAM_BLUE, Vector2(-40, -10))
	var front := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-38.6, -10))
	var behind := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-34.5, -10))
	var aside := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-37, -6))
	for m in [front, behind, aside]:
		m.locked_until = 1 << 30
	t = sim.time_ms
	while front.health == 265.0 and sim.time_ms < t + 3000:
		sim.step()
	runner.check_near(front.health, 265.0 - 32.0, "medium melee golem: 32 splash on the target")
	runner.check_near(behind.health, 265.0 - 32.0, "and on units up to 6 behind it in the 45 degree cone")
	runner.check_near(aside.health, 265.0, "but not outside the cone")
	for m in [medium, front, behind, aside]:
		sim._kill(m)
	# small ranged golem: siege pebbles x4 vs fortified
	var ranged := sim.spawn("Units/Golems/GolemsSmallRangedGolem", Simulation.TEAM_BLUE, Vector2(-40, 0))
	var tower := sim.spawn("Units/Neutral/LanetowerLevel1", Simulation.TEAM_RED, Vector2(-33, 0))
	tower.locked_until = 1 << 30
	var tower_hp := tower.health
	t = sim.time_ms
	while tower.health == tower_hp and sim.time_ms < t + 4000:
		sim.step()
	runner.check_near(tower.health, tower_hp - 15.0 * 4.0, "small ranged golem: 15 siege damage, x4 on fortified")
	sim._kill(ranged)
	sim._kill(tower)


func test_golems_multishot_and_towers() -> void:
	var sim := Simulation.new(2, 4)
	var flyer := sim.spawn("Units/Golems/GolemsSmallFlyingGolem", Simulation.TEAM_BLUE, Vector2(-40, -23))
	var a := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-36, -23))
	var b := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-36, -21))
	var c := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-36, -25))
	for m in [a, b, c]:
		m.locked_until = 1 << 30
	var t := sim.time_ms
	while a.health == 265.0 and b.health == 265.0 and c.health == 265.0 and sim.time_ms < t + 4000:
		sim.step()
	for i in 20:
		sim.step()
	var hit := [a, b, c].filter(func(m): return m.health < 265.0).size()
	runner.check_eq(hit, 2, "small flying golem: multishot at two different targets")
	runner.check([a, b, c].any(func(m): return is_equal_approx(m.health, 265.0 - 29.0)), "29 ranged each")
	sim._kill(flyer)
	var big := sim.spawn("Units/Golems/GolemsBigFlyingGolem", Simulation.TEAM_BLUE, Vector2(-40, -23))
	for m in [a, b, c]:
		m.health = 265.0
	t = sim.time_ms
	while a.health == 265.0 and sim.time_ms < t + 4000:
		sim.step()
	for i in 20:
		sim.step()
	hit = [a, b, c].filter(func(m): return m.health < 265.0).size()
	runner.check_eq(hit, 3, "big flying golem: three targets")
	runner.check_near(a.health, 265.0 - 63.0, "63 ranged each")
	sim._kill(big)
	# towers
	var small_tower := sim.spawn("Units/Golems/GolemsSmallGolemTower", Simulation.TEAM_BLUE, Vector2(-40, -10))
	runner.check_eq(small_tower.lifetime_ms, 90000, "golem towers live 90 s")
	var far := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-29.5, -10))
	far.locked_until = 1 << 30
	t = sim.time_ms
	while far.health == 265.0 and sim.time_ms < t + 3000:
		sim.step()
	runner.check_near(far.health, 265.0 - 30.0, "small golem tower: 30 ranged at range 11")
	sim._kill(small_tower)
	sim._kill(far)
	var melee_tower := sim.spawn("Units/Golems/GolemsMeleeGolemTower", Simulation.TEAM_BLUE, Vector2(-40, 0))
	var small_unit := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-38.5, 0))
	small_unit.locked_until = 1 << 30
	small_unit.max_health = 150.0   # max hp < 200: swept, not punched
	small_unit.health = 150.0
	var small_hp := small_unit.health
	t = sim.time_ms
	while small_unit.health == small_hp and sim.time_ms < t + 3000:
		sim.step()
	runner.check_near(small_unit.health, small_hp - 0.333 * 110.0, "melee golem tower sweeps small targets for 36.63 splash", 0.05)
	sim._kill(small_unit)
	var big_unit := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-38.5, 0))   # 265 max hp
	big_unit.locked_until = 1 << 30
	t = sim.time_ms
	while big_unit.health == 265.0 and sim.time_ms < t + 3000:
		sim.step()
	runner.check_near(big_unit.health, 265.0 - 110.0, "and punches targets with max hp >= 200 for 110")
	sim._kill(melee_tower)
	sim._kill(big_unit)
	var big_tower := sim.spawn("Units/Golems/GolemsBigGolemTower", Simulation.TEAM_BLUE, Vector2(-40, 10))
	var x := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-33, 10))
	var y := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-33, 12))
	x.locked_until = 1 << 30
	y.locked_until = 1 << 30
	t = sim.time_ms
	while x.health == 265.0 and sim.time_ms < t + 3000:
		sim.step()
	for i in 20:
		sim.step()
	runner.check(x.health < 265.0 and y.health < 265.0, "big golem tower: 68 at two targets")


func test_golems_boss_golem() -> void:
	var sim := Simulation.new(2, 4)
	var near := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-37, -23))
	near.locked_until = 1 << 30
	var boss := sim.spawn("Units/Golems/GolemsBossGolem", Simulation.TEAM_BLUE, Vector2(-40, -23))
	runner.check(boss.has("upGround") and boss.has("upFlying"), "the boss counts as ground and flying")
	var t := sim.time_ms
	while sim.time_ms < t + 600:
		sim.step()
	runner.check_near(near.health, 265.0 - 100.0, "debut asteroid: 100 splash in 4.5 after 500 ms")
	while sim.time_ms < t + 1700:   # legendary spawn lockout 1600
		sim.step()
	var wisp := sim.spawn("Units/Green/Wisp", Simulation.TEAM_RED, Vector2(-38, -23))
	wisp.locked_until = 1 << 30
	near.health = 265.0
	boss.locked_until = 0
	t = sim.time_ms
	while near.health == 265.0 and not (wisp.health < 75.0) and sim.time_ms < t + 4000:
		sim.step()
	runner.check(near.health < 265.0 or not wisp.alive, "370 cone cleave against ground or flying targets")


func test_golems_big_melee_splinter() -> void:
	var sim := Simulation.new(2, 4)
	var big := sim.spawn("Units/Golems/GolemsBigMeleeGolem", Simulation.TEAM_BLUE, Vector2(-40, -23))
	var hitter := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-20, -23))
	hitter.locked_until = 1 << 30
	sim.step()
	sim.deal_damage(big, 34.0, SimConstants.DamageType.TRUE, hitter)
	runner.check(sim.projectiles.is_empty(), "splinter: a 34 hit is below the 35 threshold")
	sim.deal_damage(big, 35.0, SimConstants.DamageType.TRUE, hitter)
	runner.check_eq(sim.projectiles.size(), 1, "a 35 hit lobs one splinter stone")
	var stone: Projectile = sim.projectiles.values()[0]
	var dist := stone.last_target_position.distance_to(big.position)
	runner.check(dist >= 3.0 - 0.01 and dist <= 4.0 + 0.01, "aimed at a ground point 3-4 away")
	runner.check(sim.map.in_zone("Walkzone", stone.last_target_position), "inside the walk zone")
	sim.deal_damage(big, 35.0, SimConstants.DamageType.TRUE, hitter)
	runner.check_eq(sim.projectiles.size(), 1, "at most once per 3 s")
	var t := sim.time_ms
	while not sim.projectiles.is_empty() and sim.time_ms < t + 3000:
		sim.step()
	var small: SimEntity = null
	for e in sim.alive_entities(Simulation.TEAM_BLUE):
		if e.unit_id == "Units/Golems/GolemsSmallMeleeGolem":
			small = e
	runner.check(small != null, "the stone spawns a SmallMeleeGolem on landing")
	if small != null:
		runner.check(small.position.distance_to(stone.last_target_position) < 0.01, "at the impact point")
		runner.check(small.has_buff("LegendarySpawn"), "with the 500 ms spawn lockout")
	while sim.time_ms < t + 3100:
		sim.step()
	sim.deal_damage(big, 35.0, SimConstants.DamageType.TRUE, hitter)
	runner.check_eq(sim.projectiles.size(), 1, "ready again after 3 s")


func test_golems_small_caster_crystal_speed() -> void:
	var sim := Simulation.new(2, 4)
	var caster := sim.spawn("Units/Golems/GolemsSmallCasterGolem", Simulation.TEAM_BLUE, Vector2(-40, -23))
	var a := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(-38, -23))
	var b := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(-42, -23))
	var far := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(-25, -23))
	for m in [caster, a, b, far]:
		m.locked_until = 1 << 30
	var t := sim.time_ms
	while sim.time_ms < t + 500:
		sim.step()
	var linked := int(a.has("upHasCrystalSpeed")) + int(b.has("upHasCrystalSpeed"))
	runner.check_eq(linked, 1, "crystal speed: one ally linked at once (MaxNewTargetCount 1)")
	while sim.time_ms < t + 3500:
		sim.step()
	runner.check(a.has("upHasCrystalSpeed") and b.has("upHasCrystalSpeed"), "the second ally 3 s later")
	runner.check(not far.has("upHasCrystalSpeed"), "not beyond 8")
	runner.check(not caster.has("upHasCrystalSpeed"), "never the caster itself")
	runner.check_eq(a.cooldown(SimConstants.GROUP_MAINWEAPON), int(a.bb.get_int("eiCooldown", 1, 0) * 0.7), "main weapon cooldown x0.7 while linked")
	sim._kill(caster)
	sim.step()
	runner.check(not a.has("upHasCrystalSpeed"), "the buff ends with the link")


func test_golems_big_caster_beam() -> void:
	var sim := Simulation.new(2, 4)
	var caster := sim.spawn("Units/Golems/GolemsBigCasterGolem", Simulation.TEAM_BLUE, Vector2(-40, -23))
	var victim := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-34, -23))
	victim.locked_until = 1 << 30
	victim.max_health = 100000.0
	victim.health = 100000.0
	runner.check(caster.has("upImmuneToBlinded") and caster.has("upLinkWeapon"), "big caster golem: link weapon, can't be blinded")
	var next_hit := func(until: int) -> float:
		var hp: float = victim.health
		while victim.health == hp and sim.time_ms < until:
			sim.step()
		return hp - victim.health
	var t := sim.time_ms
	runner.check_near(next_hit.call(t + 2000), 21.0, "beam: 14 x 1.5 x 1 charge per tick")
	var t0 := sim.time_ms
	next_hit.call(t0 + 1000)
	runner.check(sim.time_ms - t0 <= 512, "every 500 ms")
	runner.check(sim.projectiles.is_empty(), "no projectiles: it is a beam")
	while sim.time_ms < t + 3500:
		sim.step()
	runner.check_near(next_hit.call(t + 4500), 42.0, "x2 charges after 3 s")
	while sim.time_ms < t + 6600:
		sim.step()
	runner.check_near(next_hit.call(t + 7500), 63.0, "x3 charges after 6 s (cap)")
	while sim.time_ms < t + 10000:
		sim.step()
	runner.check_near(next_hit.call(t + 11000), 63.0, "stays at x3")
	sim._teleport(victim, Vector2(-20, -23))
	while sim.time_ms < t + 12000:
		sim.step()
	runner.check(victim.link_buffs.is_empty(), "the beam breaks out of range")
	sim._teleport(victim, Vector2(-34, -23))
	runner.check_near(next_hit.call(t + 14000), 21.0, "and restarts at x1")


func test_golems_siege_golem_artillery() -> void:
	var sim := Simulation.new(2, 4)
	var golem := sim.spawn("Units/Golems/GolemsSiegeGolem", Simulation.TEAM_BLUE, Vector2(-40, -23))
	var tower := sim.spawn("Units/Neutral/LanetowerLevel1", Simulation.TEAM_RED, Vector2(-22, -23))
	tower.locked_until = 1 << 30
	var start := golem.position
	var t := sim.time_ms
	while golem.ammo < 16 and sim.time_ms < t + 9000:
		sim.step()
	runner.check(sim.time_ms - t >= 7000 and sim.time_ms - t <= 8100, "siege golem: 16 charges after 8 s near an enemy building")
	runner.check(golem.position == start, "it stands still while charging")
	var t2 := sim.time_ms
	while sim.projectiles.is_empty() and sim.time_ms < t2 + 1000:
		sim.step()
	runner.check_eq(sim.projectiles.size(), 1, "then hurls a stone at the building")
	runner.check_eq(golem.ammo, 0, "spending all charges")
	var hp := tower.health
	while tower.health == hp and sim.time_ms < t2 + 6000:
		sim.step()
	runner.check_near(tower.health, hp - 50.0 * 4.0, "50 siege damage, x4 on fortified")
	sim._kill(tower)
	golem.ammo = 5
	for i in 3:
		sim.step()
	runner.check_eq(golem.ammo, 0, "walking without a building in range dumps the charges")
	var far_tower := sim.spawn("Units/Neutral/LanetowerLevel1", Simulation.TEAM_RED, Vector2(-22, -23))
	far_tower.locked_until = 1 << 30
	golem.ammo = 5
	var b := sim.apply_buff(golem, "Stun", {}, null)
	runner.check_eq(golem.ammo, 0, "being stunned dumps the charges")
	golem.remove_buff(b)
	sim._kill(far_tower)
	sim._teleport(golem, Vector2(-40, -10))
	var victim := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(-38.5, -10))
	victim.locked_until = 1 << 30
	golem.ammo = 5
	sim.step()
	sim.step()
	runner.check_eq(golem.ammo, 5, "charges are kept while it winds up a melee swing")
	var t3 := sim.time_ms
	while victim.health == 265.0 and sim.time_ms < t3 + 3000:
		sim.step()
	runner.check_near(victim.health, 265.0 - 68.0, "68 melee siege damage")
	runner.check_eq(golem.ammo, 0, "and the swing dumps the charges")


func _golems_spell_sim() -> Simulation:
	var sim := Simulation.new(41, 4)
	sim.spawn_bases()
	var c: Commander = sim.commanders[Simulation.TEAM_BLUE]
	c.set_deck(["Spells/Golems/Cataclysm.sps", "Spells/Golems/EchoesOfTheFuture.sps", "Spells/Golems/Petrify.sps",
		"Spells/Golems/StoneCircle.sps", "Spells/Golems/Earthquake.sps"])
	c.gold = 1000.0
	c.raise_tier(3)
	c.free_cards = true
	while not sim.game_started:
		sim.step()
	return sim


func test_petrify() -> void:
	var sim := _golems_spell_sim()
	var enemy := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(1, -23))
	var ally := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(-1, -23))
	var far := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(8, -23))
	for m in [enemy, ally, far]:
		m.base_speed = 0.0
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 2, Vector2(0, -23)), Simulation.PlayResult.OK, "cast petrify")
	for i in 3:
		sim.step()
	runner.check(enemy.has("upPetrified") and ally.has("upPetrified"), "units of both teams in radius 4 are petrified")
	runner.check(not far.has("upPetrified"), "not beyond 4")
	runner.check(not enemy.can_think(sim.time_ms), "petrified units can't act")
	runner.check_eq(sim.alive_entities(Simulation.TEAM_BLUE).filter(func(e): return e.is_spell_effect()).size(), 0, "the field vanishes at once")
	var t := sim.time_ms
	while sim.time_ms < t + 2100:
		sim.step()
	runner.check_near(ally.overheal, 20.0, "10 hp per second as overheal")
	while sim.time_ms < t + 12500:
		sim.step()
	runner.check(not enemy.has("upPetrified"), "stone crumbles after 12 s")
	runner.check(enemy.has("upImmuneToPetrified"), "then immune")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 2, Vector2(0, -23)), Simulation.PlayResult.OK, "cast again")
	for i in 3:
		sim.step()
	runner.check(not enemy.has("upPetrified"), "immune units are skipped")
	while sim.time_ms < t + 22500:
		sim.step()
	runner.check(not enemy.has("upImmuneToPetrified"), "immunity ends 10 s later")


func test_stone_circle() -> void:
	var sim := _golems_spell_sim()
	var allies: Array = []
	for i in 10:
		var f := sim.spawn("Units/White/Footman", Simulation.TEAM_BLUE, Vector2((i % 5) * 1.2, -23 + (i / 5) * 1.2))
		f.base_speed = 0.0
		allies.append(f)
	var archer := sim.spawn("Units/White/Archer", Simulation.TEAM_BLUE, Vector2(0, -20))
	archer.base_speed = 0.0
	var base_damage: float = allies[0].damage(1)
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 3, Vector2(0, -23)), Simulation.PlayResult.OK, "cast stone circle")
	for i in 5:
		sim.step()
	runner.check(archer.has("upSpellshieldAuraBuffed"), "allies in radius 4.5 get the spellshield aura")
	var hp := archer.health
	sim.deal_damage(archer, 50.0, SimConstants.DamageType.SPELL, null)
	runner.check_near(archer.health, hp - 10.0, "spell damage x0.2")
	var blessed := allies.filter(func(f): return f.has("upBlessedStonefist"))
	runner.check_eq(blessed.size(), 1, "one melee ally enchanted at once")
	if not blessed.is_empty():
		runner.check_near(blessed[0].damage(1), base_damage + 15.0, "stonefist: +15 damage")
	runner.check(not archer.has("upBlessedStonefist"), "ranged allies are never enchanted")
	var t := sim.time_ms
	while sim.time_ms < t + 6200:
		sim.step()
	runner.check_eq(allies.filter(func(f): return f.has("upBlessedStonefist")).size(), 4, "one more every 2 s")
	while sim.time_ms < t + 21000:
		sim.step()
	runner.check_eq(allies.filter(func(f): return f.has("upBlessedStonefist")).size(), 10, "all ten enchanted")
	runner.check_eq(sim.alive_entities(Simulation.TEAM_BLUE).filter(func(e): return e.has("upCharm")).size(), 0, "field gone after 10 enchantments")
	runner.check(not archer.has("upSpellshieldAuraBuffed"), "aura gone with the field")


func test_earthquake() -> void:
	var sim := _golems_spell_sim()
	var enemy := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, Vector2(1, -23))
	var flyer := sim.spawn("Units/Golems/GolemsSmallFlyingGolem", Simulation.TEAM_RED, Vector2(-1, -23))
	var ally := sim.spawn("Units/White/Monk", Simulation.TEAM_BLUE, Vector2(2, -23))
	for m in [enemy, flyer, ally]:
		m.base_speed = 0.0
		m.locked_until = 1 << 30
	enemy.max_health = 1000.0
	enemy.health = 1000.0
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 4, Vector2(0, -23)), Simulation.PlayResult.OK, "cast earthquake")
	for i in 3:
		sim.step()
	runner.check_near(enemy.health, 1000.0 - 35.0, "first wave at once: 35 siege spell splash")
	runner.check(enemy.has("upStunned"), "and a stun")
	runner.check_near(flyer.health, 97.0, "flying enemies untouched")
	runner.check_near(ally.health, 265.0, "allies untouched")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 4, Vector2(0, -23)), Simulation.PlayResult.LEGENDARY_ALIVE, "counts as the legendary")
	var t := sim.time_ms
	while sim.time_ms < t + 4800:
		sim.step()
	runner.check_near(enemy.health, 1000.0 - 35.0, "nothing in between")
	while sim.time_ms < t + 5200:
		sim.step()
	runner.check_near(enemy.health, 1000.0 - 70.0, "second wave after 5 s")
	while sim.time_ms < t + 26000:
		sim.step()
	runner.check_near(enemy.health, 1000.0 - 6 * 35.0, "six waves in all")
	runner.check_eq(sim.alive_entities(Simulation.TEAM_BLUE).filter(func(e): return e.is_spell_effect()).size(), 0, "field gone after the sixth")


func test_cataclysm() -> void:
	var sim := _golems_spell_sim()
	var c: Commander = sim.commanders[Simulation.TEAM_BLUE]
	var nexus: Vector2 = sim.map.base_layout(Simulation.TEAM_BLUE)["nexus"]
	var at := nexus + Vector2(8, 0)
	var enemy := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, at + Vector2(2, 0))
	var ally := sim.spawn("Units/White/Footman", Simulation.TEAM_BLUE, at + Vector2(-2, 0))
	var far := sim.spawn("Units/White/Monk", Simulation.TEAM_RED, at + Vector2(0, 9))
	for m in [enemy, ally, far]:
		m.base_speed = 0.0
		m.locked_until = 1 << 30
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, Vector2(0, -23)), Simulation.PlayResult.BAD_TARGET, "cataclysm: only near the own nexus")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, at), Simulation.PlayResult.OK, "cast in the nexus zone")
	var field: SimEntity = null
	for e in sim.alive_entities(Simulation.TEAM_BLUE):
		if e.is_spell_effect():
			field = e
	runner.check(field != null and is_equal_approx(field.range_of(0), 6.0 + 0.5 * 3), "range 6 + 0.5 x tier (3)")
	for i in 3:
		sim.step()
	runner.check(enemy.alive and ally.alive, "nothing happens for 500 ms")
	var t := sim.time_ms
	while sim.time_ms < t + 600:
		sim.step()
	runner.check(not enemy.alive and not ally.alive, "then units of both teams in range are annihilated")
	runner.check(enemy.exiled, "exiled: no death effects")
	runner.check(far.alive, "units beyond the range survive")
	runner.check(sim.entities[sim.nexus_ids[Simulation.TEAM_BLUE]].alive, "the nexus (upBase) is spared")
	runner.check_eq(sim.alive_entities(Simulation.TEAM_BLUE).filter(func(e): return e.is_spell_effect()).size(), 0, "field gone")
	c.free_cards = false
	c.gold = 100.0
	c.wood = 0.0
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, at), Simulation.PlayResult.NOT_READY, "needs the full gold bar")
	c.gold = c.gold_cap()
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, at), Simulation.PlayResult.OK, "castable at the gold cap")
	runner.check_near(c.gold, 0.0, "consumes all gold")
	runner.check_near(c.wood, c.gold_cap(), "refunded as wood")
	c.gold = c.gold_cap()
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 0, at), Simulation.PlayResult.OK, "no charges: castable again at once")


func test_echoes_of_the_future() -> void:
	var sim := _golems_spell_sim()
	var c: Commander = sim.commanders[Simulation.TEAM_BLUE]
	runner.check_eq(c.slots[1].charge_cooldown_ms, Cards.charge_cooldown(1, 4, 5, false, false) * 3, "echoes: charge cooldown x3")
	var next_tick := func() -> void:
		var n: int = sim.tick_counter
		while sim.tick_counter == n:
			sim.step()
	c.gold = 0.0
	next_tick.call()
	runner.check_near(c.gold, c.income(), "normal income")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 1, Vector2(0, -23)), Simulation.PlayResult.OK, "cast echoes")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 1, Vector2(0, -23)), Simulation.PlayResult.NOT_READY, "not while it runs")
	var t := sim.time_ms
	c.gold = 0.0
	next_tick.call()
	runner.check_near(c.gold, c.income() * 2.0, "gold income x2")
	while sim.time_ms < t + 29000:
		sim.step()
	c.gold = 0.0
	next_tick.call()
	runner.check_near(c.gold, c.income() * 2.0, "still x2 near the end of 30 s")
	while sim.time_ms < t + 32000:
		sim.step()
	c.gold = 0.0
	next_tick.call()
	runner.check_near(c.gold, 0.0, "then x0 for the payback")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 1, Vector2(0, -23)), Simulation.PlayResult.NOT_READY, "still blocked during the payback")
	while sim.time_ms < t + 62000:
		sim.step()
	c.gold = 0.0
	next_tick.call()
	runner.check_near(c.gold, c.income(), "normal income after 60 s")
	runner.check_eq(sim.play_card(Simulation.TEAM_BLUE, 1, Vector2(0, -23)), Simulation.PlayResult.OK, "castable again")


func test_deck_rules() -> void:
	var deck := Deck.new()
	runner.check(deck.is_empty() and not deck.is_full(), "new deck: 12 empty slots")
	runner.check_eq(deck.slots.size(), 12, "DECKSLOT_COUNT = 12")
	runner.check_eq(deck.league(), 1, "empty deck is league 1")
	var footman := Cards.by_script("Units/White/FootmanDrop")
	runner.check(deck.add_card(footman, 3), "add a white card")
	runner.check(not deck.add_card(footman, 3), "a card fits only once")
	runner.check_eq(deck.color_count(), 1, "one color")
	runner.check_eq(deck.league(), 3, "deck league = max card league")
	runner.check(deck.add_card(Cards.by_script("Units/Black/VoidSkeletonDrop"), 5), "a second color fits")
	runner.check_eq(deck.league(), 5, "league follows the strongest card")
	runner.check(not deck.can_add_card(Cards.by_script("Units/Green/WispSpawner")), "a third color does not")
	runner.check(deck.can_add_card(Cards.by_script("Units/Golems/GolemsSmallMeleeGolemSpawner")), "colorless (Crystal Legion) always fits")
	runner.check(deck.add_card(Cards.by_script("Spells/Golems/Cataclysm.sps")), "one epic is allowed")
	runner.check_eq(deck.color_count(), 2, "colorless does not count as a color")
	var deck2 := Deck.new()
	deck2.add_card(Cards.by_script("Spells/Golems/Cataclysm.sps"))
	runner.check(not deck2.can_add_card(Cards.by_script("Spells/Golems/Cataclysm.sps")), "no second epic")
	deck.remove_card(footman)
	runner.check(not deck.contains_card(footman), "remove card")
	for unit_id in ["Units/White/ArcherDrop", "Units/White/FootmanSpawner", "Units/White/ArcherSpawner",
			"Units/White/BallistaDrop", "Units/White/PriestDrop", "Units/White/MonkDrop",
			"Units/White/SuntowerBuilding", "Spells/White/LightPulse.sps", "Spells/White/ShieldsUp.sps"]:
		runner.check(deck.add_card(Cards.by_script(unit_id)), "fill up with %s" % unit_id)
	runner.check(deck.add_card(footman), "12th card")
	runner.check(deck.is_full(), "deck is full")
	runner.check(not deck.add_card(Cards.by_script("Spells/White/SolarFlare.sps")), "no 13th card")


func test_deck_sort_order() -> void:
	var deck := Deck.from_scripts(["Units/White/FootmanSpawner", "Spells/White/LightPulse.sps",
		"Units/White/SuntowerBuilding", "Units/White/BallistaDrop", "Units/White/FootmanDrop"])
	var ids := deck.card_ids()
	runner.check_eq(ids[ids.size() - 1], "Units/White/FootmanSpawner", "spawners sort last")
	runner.check_eq(ids[0], "Units/White/BallistaDrop", "tier 1 units first, ties by filename (B < F)")
	var ballista := ids.find("Units/White/BallistaDrop")
	var pulse := ids.find("Spells/White/LightPulse.sps")
	var tower := ids.find("Units/White/SuntowerBuilding")
	runner.check(ballista >= 0 and pulse >= 0 and tower >= 0, "all cards kept")
	for i in ids.size() - 2:   # non-spawner block is sorted by tier
		runner.check(Cards.by_script(ids[i]).tier <= Cards.by_script(ids[i + 1]).tier, "tier order at %d" % i)
	var gap := Deck.new()
	gap.add_card(Cards.by_script("Units/White/FootmanDrop"))
	gap.add_card(Cards.by_script("Units/White/FootmanSpawner"))
	runner.check(gap.slots[0] != null and gap.slots[11] != null and gap.slots[5] == null,
		"empty slots sit between units and spawners (TCardInfo.Compare nil rule)")


func test_deck_card_league_level() -> void:
	# RGameCard: each commander slot uses its card's own league/level for charge count and recharge.
	var deck := Deck.new()
	deck.add_card(Cards.by_script("Units/White/FootmanDrop"), 1, 1)
	deck.add_card(Cards.by_script("Units/White/ArcherDrop"), 5, 5)
	var c := Commander.new(1)
	c.set_deck_from(deck)
	runner.check_eq(c.slots.size(), 2, "two slots from the deck")
	for s in c.slots:
		if s.card.unit_id == "Units/White/FootmanDrop":
			runner.check_eq(s.league, 1, "footman keeps its own league")
			runner.check_eq(s.charge_cap, 1, "tier 1 league 1: 1 charge")
			runner.check_eq(s.charge_cooldown_ms, 37000, "league 1 level 1 recharge")
		elif s.card.unit_id == "Units/White/ArcherDrop":
			runner.check_eq(s.charge_cap, 5, "tier 1 league 5: 5 charges")
			runner.check_eq(s.charge_cooldown_ms, 22000, "league 5 level 5 recharge")
	var legacy := Commander.new(1)
	legacy.set_deck(["Units/White/FootmanDrop"])
	runner.check_eq(legacy.slots[0].charge_cap, Cards.charge_count(1, 4, false),
		"set_deck keeps the commander league (DEFAULT_LEAGUE)")
	runner.check_eq(legacy.slots[0].charge_cooldown_ms, Cards.charge_cooldown(1, 4, 5, false, false),
		"set_deck uses level 5 (DEFAULT_LEVEL)")
