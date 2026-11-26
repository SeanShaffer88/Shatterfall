extends RefCounted
## Gate 3: rooms, waves, doors, heal, drops, boon draft, traps, death, abandon
## and pause (§2E, §2F, D10, D14, D19, D29, D33).

var sim: RunSim


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	if sim != null:
		sim.dispose()
		sim = null


func _new(hero_id: String, seed_value: int = 7, last_clearer: String = "") -> RunSim:
	sim = RunSim.new(_tree(), hero_id, seed_value, last_clearer)
	return sim


func _counts(enemies: Array) -> Dictionary:
	var c := {}
	for e in enemies:
		c[e.type] = int(c.get(e.type, 0)) + 1
	return c


func _expected(groups: Array) -> Dictionary:
	var c := {}
	for g in groups:
		c[g["enemy"]] = int(c.get(g["enemy"], 0)) + int(g["count"])
	return c


func test_first_wave_spawns_after_its_telegraph(t: TestContext) -> void:
	var s := _new("BRUTE")
	t.eq(s.run.phase, DungeonRun.Phase.ROOM, "run starts in Room 1")
	s.step()
	var markers := _tree().get_nodes_in_group(Telegraph.GROUP).filter(func(n: Node) -> bool: return s.run.is_ancestor_of(n))
	t.eq(markers.size(), 4, "4 spawn telegraphs for 3 Crawlers + 1 Spitter")
	s.seconds(0.9)
	t.eq(s.run.alive_enemies().size(), 0, "nothing spawns during the 1.0 s telegraph")
	s.seconds(0.2)
	var alive := s.run.alive_enemies()
	t.eq(_counts(alive), {"CRAWLER": 3, "SPITTER": 1}, "Room 1 wave 1 from stages.json")
	for e in alive:
		t.ok(Combat.flat_distance(e.global_position, s.hero.global_position) >= 6.0 - 1e-3, "spawn ≥ 6 m from the hero")


func test_doors_unlock_only_on_last_wave_clear(t: TestContext) -> void:
	var s := _new("ROGUE")
	var doors := s.run.stage.doors
	s.seconds(1.1)
	t.ok(not doors[0].is_open, "door closed while Room 1 is live")
	s.kill_all()
	s.step()
	t.ok(doors[0].is_open, "Room 1's only wave cleared: door opens")
	t.eq(doors[0].collision_layer, 0, "open door has no collision")
	s.enter_next_room()
	t.eq(s.run.room, 1, "entered Room 2")
	t.ok(not doors[0].is_open, "door locks behind the hero")
	s.seconds(1.1)
	t.eq(_counts(s.run.alive_enemies()), {"CRAWLER": 4}, "Room 2 wave 1")
	s.kill_all()
	s.step()
	t.ok(not doors[1].is_open, "door stays shut after a non-final wave")
	s.seconds(1.85)
	t.eq(s.run.alive_enemies().size(), 0, "next wave waits 1.0 s delay + 1.0 s telegraph")
	s.seconds(0.25)
	t.eq(_counts(s.run.alive_enemies()), {"SPITTER": 2, "CRAWLER": 2}, "Room 2 wave 2")
	s.kill_all()
	s.step()
	t.eq(s.run.phase, DungeonRun.Phase.DRAFT, "boon draft opens before Room 3")
	t.ok(not doors[1].is_open, "door stays shut until a boon is chosen")
	s.run.pick_boon(0)
	t.ok(doors[1].is_open, "door opens after the pick")


func test_every_wave_matches_stages_json(t: TestContext) -> void:
	var s := _new("MAGI")
	var seen := []
	s.run.wave_started.connect(func(r: int, w: int) -> void:
		seen.append([r, w, _counts(s.run.alive_enemies())]))
	s.to_boss()
	var want := []
	var rooms: Array = GameState.stage_cfg(RunSim.STAGE)["rooms"]
	for r in rooms.size():
		for w in rooms[r]["waves"].size():
			want.append([r, w, _expected(rooms[r]["waves"][w])])
	t.eq(seen, want, "every room/wave composition (§2E)")
	t.eq(s.run.room, StageLayout.BOSS_ROOM, "reached Vespera's arena")


func test_room_clear_heals_and_hp_carries(t: TestContext) -> void:
	var s := _new("BRUTE")
	s.hero.hp = 100
	s.clear_room()
	t.eq(s.hero.hp, 121, "15% of 140 = 21 on room clear")
	s.enter_next_room()
	t.eq(s.hero.hp, 121, "HP carries into the next room")


func test_drops_saved_at_room_clear(t: TestContext) -> void:
	var found := false
	for seed_value in range(1, 12):
		var s := _new("BRUTE", seed_value)
		s.clear_room()
		if not s.run.run_drops.is_empty():
			var uid: String = s.run.run_drops[0]["uid"]
			var saved_uids := []
			for w in s.saved()["inventory"]["weapons"]:
				saved_uids.append(w["uid"])
			t.ok(uid in saved_uids, "room drop %s is in the save right after the clear (D29)" % uid)
			t.eq(int(s.run.run_drops[0]["level"]), 1, "room drops are level 1 (D30)")
			found = true
		sim.dispose()
		sim = null
		if found:
			break
	t.ok(found, "a room drop occurred in the seeded sample")


func test_boon_draft_offers_three_unique(t: TestContext) -> void:
	var s := _new("ROGUE")
	s.clear_room()
	s.enter_next_room()
	s.clear_room()
	var offers := s.run.draft_offers
	t.eq(offers.size(), 3, "3 offers")
	var ids := {}
	for o in offers:
		ids[o["id"]] = true
	t.eq(ids.size(), 3, "no duplicate offer")
	t.ok(s.run.hud.draft_panel.visible, "draft modal shown")
	t.ok(s.run.pick_boon(1), "pick the second offer")
	t.eq(s.hero.boons, [offers[1]["id"]], "boon applied to this run's hero")
	t.ok(not s.run.pick_boon(0), "only one pick")
	t.ok(not s.run.hud.draft_panel.visible, "modal closed")


func test_boons_are_run_only(t: TestContext) -> void:
	var s := _new("BRUTE")
	s.clear_room()
	s.enter_next_room()
	s.clear_room()
	s.run.pick_boon(0)
	t.eq(s.hero.boons.size(), 1, "boon active this run")
	s.hero.take_damage(9999)
	t.eq(s.run.result, "DEFEAT", "run lost")
	t.eq(s.run.summary["boons_lost"].size(), 1, "summary lists the lost boon")
	sim.dispose()
	var s2 := _new("BRUTE")
	t.eq(s2.hero.boons, [], "next run starts with no boons (D14)")
	t.eq([s2.hero.damage_mult, s2.hero.attack_speed_mult, s2.hero.projectile_taken_mult], [1.0, 1.0, 1.0], "no boon multipliers")


func test_spike_traps_cycle_in_room_3_only(t: TestContext) -> void:
	var s := _new("MAGI")
	var traps := s.run.stage.traps
	t.eq(traps.size(), 4, "4 spike panels")
	t.eq(traps[0].phase_name(), "OFF", "traps are off outside Room 3")
	s.clear_room()
	s.enter_next_room()
	s.clear_room()
	s.run.pick_boon(0)
	s.enter_next_room()
	t.eq(s.run.room, 2, "in Room 3")
	var a: SpikeTrap = traps[0]
	var b: SpikeTrap = traps[1]
	t.eq([a.group, b.group], [0, 1], "SPIKE_A group 0, SPIKE_B group 1")
	s.hero.take_damage(1)                 # break the barrier the normal way (6 s refresh)
	s.hero.invuln_timer = 0.0
	s.hero.global_position = a.global_position
	var hp0 := s.hero.hp
	s.seconds(0.5)
	t.eq(a.phase_name(), "WARNING", "0–1.0 s warning")
	t.eq(s.hero.hp, hp0, "no damage during the warning")
	s.seconds(0.6)
	t.eq(a.phase_name(), "ACTIVE", "1.0–1.4 s active")
	t.eq(s.hero.hp, hp0 - 10, "10 damage, once")
	s.seconds(0.35)
	t.eq(s.hero.hp, hp0 - 10, "only once per activation")
	t.eq(a.phase_name(), "IDLE", "idle after 1.4 s")
	t.eq(b.phase_name(), "IDLE", "group 1 runs 2 s behind")
	s.seconds(0.8)
	t.eq(b.phase_name(), "WARNING", "group 1 warns at 2.0 s")
	s.clear_room()
	t.eq(a.phase_name(), "OFF", "traps disarm when the room clears")


func test_death_ends_run_with_keep_lose_split(t: TestContext) -> void:
	var s := _new("ROGUE", 3)
	s.clear_room()
	var drops_before := s.run.run_drops.size()
	var grudge_before := GameState.get_last_clearing_hero(RunSim.STAGE)
	s.enter_next_room()
	s.hero.take_damage(9999)
	t.eq(s.run.result, "DEFEAT", "death ends the run")
	t.eq(s.run.phase, DungeonRun.Phase.ENDED, "ended")
	t.ok(not s.run.summary["star_earned"], "no star on a failed run")
	t.eq(GameState.star_count(RunSim.STAGE), 0, "no star recorded")
	t.eq(GameState.get_last_clearing_hero(RunSim.STAGE), grudge_before, "grudge unchanged")
	t.eq(s.run.summary["drops"].size(), drops_before, "drops from cleared rooms kept")
	for d in s.run.summary["drops"]:
		t.ok(GameState.inventory.get_weapon(d["uid"]) != null, "kept drop still in the inventory")
	t.ok(s.run.hud.summary_panel.visible, "summary shown")
	t.contains(s.run.hud.summary_label.text, "Forge progress kept", "summary states the keep/lose split")


func test_abandon_from_pause(t: TestContext) -> void:
	var s := _new("BRUTE")
	s.clear_room()
	s.run.set_paused(true)
	t.ok(_tree().paused, "tree paused")
	t.ok(s.run.hud.pause_panel.visible, "pause menu shown")
	s.run.abandon()
	t.eq(s.run.result, "ABANDONED", "abandoned")
	t.ok(not _tree().paused, "unpaused for the summary")
	t.ok(s.saved()["inventory"]["weapons"].size() >= 4, "save intact after abandoning")


func test_app_background_auto_pauses(t: TestContext) -> void:
	var s := _new("MAGI")
	s.run._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	t.ok(s.run.paused, "auto-paused on background (D29)")
	s.seconds(2.0)
	t.eq(s.run.alive_enemies().size(), 0, "waves do not advance while paused")
	s.run.set_paused(false)
	s.seconds(1.1)
	t.eq(s.run.alive_enemies().size(), 4, "resumes where it left off")


func test_hud_wave_info(t: TestContext) -> void:
	var s := _new("ROGUE")
	s.step()
	t.eq(s.run.hud.wave_text(), "Room 1 / 4   ·   Wave 1 / 1", "wave info top-right")
	s.clear_room()
	t.eq(s.run.hud.wave_text(), "Room 1 clear — onward", "cleared")
