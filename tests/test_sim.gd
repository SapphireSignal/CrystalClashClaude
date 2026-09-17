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
	runner.check_near(f.health, hp - 2.0, "root DoT: 1.5 dmg -> min 1 after armor, twice in 2 s")


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
