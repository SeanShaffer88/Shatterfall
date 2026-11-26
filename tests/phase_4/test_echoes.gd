extends RefCounted
## Gate 4: Spectral Echo recording, storage and playback (§2B; D9, D12, D21,
## D23, D34, D35, D36, AD6) and Echo Conducting (D41).

const STAGE := "stage_01_sunken_nave"
const DT := 1.0 / 60.0

var sim: RunSim


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	if sim != null:
		sim.dispose()
		sim = null
	EchoDirector.discard()


func _until_wave_live(s: RunSim) -> void:
	s.step_until(func() -> bool: return s.run.wave_live and not s.run.alive_enemies().is_empty(), 300)


## A playback event in world space for room 0 (its EchoAnchor sits at the origin).
func _event(hero: String, skill: String, t: float, pos: Vector3, target: Vector3, mode: String = "", room: int = 0, wave: int = 0) -> Dictionary:
	return {"hero": hero, "room": room, "wave": wave, "t": t, "pos": pos, "target": target, "skill": skill, "mode": mode}


func _inject(s: RunSim, evs: Array) -> void:
	var typed: Array[Dictionary] = []
	typed.assign(evs)
	s.run.echo_player.setup(s.run, typed)


func _capture(s: RunSim) -> Dictionary:
	var log := {"cues": [], "casts": [], "drops": []}
	s.run.echo_player.cue_shown.connect(func(e: Dictionary) -> void: log["cues"].append([e, s.run.wave_elapsed]))
	s.run.echo_player.echo_cast.connect(func(e: Dictionary, a: SpectralEcho) -> void: log["casts"].append([e, a, s.run.wave_elapsed]))
	s.run.echo_player.event_dropped.connect(func(e: Dictionary, r: String) -> void: log["drops"].append([e, r]))
	return log


func test_recorded_brute_leap_replays_in_a_rogue_run(t: TestContext) -> void:
	sim = RunSim.new(_tree(), "BRUTE", 21)
	sim.hero.attack_timer = 1e9
	_until_wave_live(sim)
	sim.step_until(func() -> bool: return Combat.nearest_enemy(_tree(), sim.hero.global_position, 4.5) != null, 600)
	var cast_t := sim.run.wave_elapsed
	t.ok(sim.cast("LEAP_SLAM"), "Brute leaps onto an approaching enemy during Room 1's wave")
	t.eq(EchoDirector.recorded().size(), 1, "recorded")
	sim.seconds(0.6)
	sim.hero.attack_timer = 0.0
	sim.activate_boss()
	sim.kill_boss()
	t.eq(sim.run.result, "VICTORY", "Brute clears the stage")
	var file := SaveManager.read_json(EchoDirector.path_for(STAGE))
	t.ok(file["ok"], "echo file written on victory")
	var evs: Array = file["data"]["echoes"]["BRUTE"]["events"]
	t.eq(evs[0]["skill"], "LEAP_SLAM", "Leap Slam stored")
	t.eq([int(evs[0]["room"]), int(evs[0]["wave"])], [0, 0], "Room 1, wave 1")
	t.near(float(evs[0]["t"]), cast_t, 0.002, "wave-relative time")
	sim.dispose(false)
	sim = RunSim.new(_tree(), "ROGUE", 21)
	sim.hero.attack_timer = 1e9
	var log := _capture(sim)
	t.eq(sim.run.echo_player.events.size(), evs.size(), "Rogue run loads the Brute's echoes")
	sim.step_until(func() -> bool: return not log["casts"].is_empty(), 600)
	t.eq(log["cues"].size(), 1, "one cue")
	t.near(log["cues"][0][1], cast_t - 1.0, DT + 1e-6, "cue appears 1.0 s before t")
	t.eq(log["casts"].size(), 1, "the Echo cast")
	t.near(log["casts"][0][2], cast_t, DT + 1e-6, "cast at t")
	var actor: SpectralEcho = log["casts"][0][1]
	t.eq([actor.hero_id, actor.skill_id], ["BRUTE", "LEAP_SLAM"], "a Brute Leap Slam Echo")
	t.ok(not actor.hits_dealt.is_empty(), "the Echo's slam hit enemies")
	for h in actor.hits_dealt:
		t.eq(h["damage"], 20, "30 × 0.65 = 19.5 → 20")
		t.ok(h["is_echo"] and not h["crit"], "echo hit, never a crit")


func test_target_resolution_order(t: TestContext) -> void:
	sim = RunSim.new(_tree(), "ROGUE", 3)
	sim.hero.attack_timer = 1e9
	_until_wave_live(sim)
	sim.stun_all()
	var enemies := sim.run.alive_enemies()
	var e0: EnemyBase = enemies[0]
	var at := sim.run.wave_elapsed + 1.2
	var far := Vector3(-7.5, 0, -7.5)
	var nearest_to_far: EnemyBase = null
	for e in enemies:
		if nearest_to_far == null or Combat.flat_distance(far, e.global_position) < Combat.flat_distance(far, nearest_to_far.global_position):
			nearest_to_far = e
	_inject(sim, [
		_event("MAGI", "SHATTER_NOVA", at, e0.global_position, e0.global_position + Vector3(2, 0, 0)),
		_event("BRUTE", "VORTEX_CLEAVE", at, nearest_to_far.global_position + Vector3(1, 0, 0), Vector3(30, 0, 30)),
		_event("MAGI", "SHATTER_NOVA", at, Vector3(30, 0, 30), Vector3(30, 0, 30)),
	])
	var log := _capture(sim)
	sim.seconds(0.3)
	t.eq(log["cues"].size(), 2, "two events found a target")
	t.ok(log["cues"][0][0]["target_node"] == e0, "1: nearest living enemy within 3.5 m of the recorded target")
	t.ok(log["cues"][1][0]["target_node"] == nearest_to_far, "2: else nearest enemy in the room within the skill's reach")
	t.eq(log["drops"].size(), 0, "3: no target yet → keeps looking until t")
	sim.seconds(1.0)
	t.eq(log["drops"].size(), 1, "3: still none at t → skipped")
	t.eq(log["drops"][0][1], "no_target", "skip reason")


func test_cap_two_per_wave_and_per_hero_overwrite(t: TestContext) -> void:
	EchoDirector.echo_dir = RunSim.ECHOES
	EchoDirector.begin_recording(STAGE, "MAGI")
	t.ok(EchoDirector.record(0, 0, 1.0, Vector3.ZERO, Vector3.ONE, "GRAVITY_WELL"), "1st cast kept")
	t.ok(EchoDirector.record(0, 0, 2.0, Vector3.ZERO, Vector3.ONE, "SHATTER_NOVA"), "2nd cast kept")
	t.ok(not EchoDirector.record(0, 0, 3.0, Vector3.ZERO, Vector3.ONE, "SHATTER_NOVA"), "3rd cast in the wave dropped (D12)")
	t.ok(EchoDirector.record(0, 1, 0.5, Vector3.ZERO, Vector3.ONE, "SHATTER_NOVA"), "next wave has its own cap")
	t.eq(EchoDirector.commit_victory("lorelight_rod"), OK, "commit")
	EchoDirector.begin_recording(STAGE, "BRUTE")
	EchoDirector.record(2, 0, 4.0, Vector3.ZERO, Vector3.ONE, "LEAP_SLAM")
	EchoDirector.commit_victory("ashen_cleaver")
	var echoes: Dictionary = EchoDirector.load_stage_file(STAGE)["echoes"]
	t.eq(echoes.keys().size(), 2, "one entry per hero")
	t.eq(echoes["MAGI"]["events"].size(), 3, "Magi entry intact")
	EchoDirector.begin_recording(STAGE, "MAGI")
	EchoDirector.record(1, 0, 9.0, Vector3.ZERO, Vector3.ONE, "SHATTER_NOVA")
	EchoDirector.commit_victory("prismheart_staff")
	echoes = EchoDirector.load_stage_file(STAGE)["echoes"]
	t.eq(echoes["MAGI"]["events"].size(), 1, "a new Magi clear replaces only the Magi entry")
	t.eq(echoes["MAGI"]["weapon_id"], "prismheart_staff", "weapon_id updated (informational)")
	t.eq(echoes["BRUTE"]["events"].size(), 1, "Brute entry untouched")
	EchoDirector.echo_dir = EchoDirector.DEFAULT_DIR
	for f in DirAccess.get_files_at(RunSim.ECHOES):
		DirAccess.remove_absolute(RunSim.ECHOES + "/" + f)


func test_movement_skills_are_not_recorded_and_modes_are(t: TestContext) -> void:
	sim = RunSim.new(_tree(), "ROGUE", 4)
	sim.hero.attack_timer = 1e9
	_until_wave_live(sim)
	sim.cast("SHADOW_VAULT")
	sim.seconds(0.3)
	t.eq(EchoDirector.recorded().size(), 0, "Shadow Vault is movement-only: not recorded (D34)")
	sim.cast("ADAPTIVE_BARRAGE")
	t.eq(EchoDirector.recorded().size(), 1, "Adaptive Barrage recorded")
	t.eq(EchoDirector.recorded()[0].get("mode", ""), "BOW", "with its mode")


func test_failed_and_abandoned_runs_record_nothing(t: TestContext) -> void:
	for ending in ["DEFEAT", "ABANDONED"]:
		sim = RunSim.new(_tree(), "BRUTE", 5)
		_until_wave_live(sim)
		sim.seconds(1.5)
		sim.cast("RENDING_ROAR")
		t.eq(EchoDirector.recorded().size(), 1, "%s: cast recorded during the run" % ending)
		if ending == "DEFEAT":
			sim.hero.take_damage(9999)
		else:
			sim.run.abandon()
		t.eq(sim.run.result, ending, ending)
		t.ok(not FileAccess.file_exists(EchoDirector.path_for(STAGE)), "%s: nothing written (D10)" % ending)
		t.eq(EchoDirector.recorded().size(), 0, "%s: buffer discarded" % ending)
		sim.dispose()
		sim = null


func test_two_actor_cap_wait_and_drop(t: TestContext) -> void:
	sim = RunSim.new(_tree(), "BRUTE", 6)
	sim.hero.attack_timer = 1e9
	_until_wave_live(sim)
	sim.stun_all()
	var e0 := sim.run.alive_enemies()[0].global_position
	var at := sim.run.wave_elapsed + 1.1
	var evs := []
	for i in 5:
		evs.append(_event("MAGI", "SHATTER_NOVA", at, e0, e0))
	_inject(sim, evs)
	var log := _capture(sim)
	sim.seconds(1.15)
	t.eq(log["casts"].size(), 2, "only 2 Echo actors at once (AD12)")
	t.eq(sim.run.echo_player.live_actors().size(), 2, "2 live actors")
	sim.seconds(0.85)
	t.eq(log["casts"].size(), 4, "waiting Echoes cast as slots free up")
	sim.seconds(0.75)
	t.eq(log["drops"].size(), 1, "the 5th waited more than 1.5 s and dropped")
	t.eq(log["drops"][0][1], "no_slot", "drop reason")


func test_event_drops_when_its_wave_ends_first(t: TestContext) -> void:
	sim = RunSim.new(_tree(), "ROGUE", 7)
	_until_wave_live(sim)
	var e0 := sim.run.alive_enemies()[0].global_position
	_inject(sim, [_event("BRUTE", "LEAP_SLAM", sim.run.wave_elapsed + 5.0, e0, e0)])
	var log := _capture(sim)
	sim.seconds(0.5)
	sim.kill_all()
	sim.step(2)
	t.eq(log["drops"].size(), 1, "dropped")
	t.eq(log["drops"][0][1], "wave_ended", "the wave ended before t")
	t.eq(log["casts"].size(), 0, "never cast")


func test_potency_and_current_weapon_inheritance(t: TestContext) -> void:
	sim = RunSim.new(_tree(), "ROGUE", 8)
	sim.hero.attack_timer = 1e9
	_until_wave_live(sim)
	sim.stun_all()
	var e0 := sim.run.alive_enemies()[0].global_position
	var at := sim.run.wave_elapsed + 1.1
	var axe := GameState.inventory.main_for("BRUTE", "GREATAXE")
	_inject(sim, [_event("BRUTE", "LEAP_SLAM", at, e0, e0)])
	var log := _capture(sim)
	sim.seconds(1.2)
	t.eq(log["casts"][0][1].hits_dealt[0]["damage"], 20, "×0.65 at level 1")
	axe.evo_stage = 2
	at = sim.run.wave_elapsed + 1.1
	_inject(sim, [_event("BRUTE", "LEAP_SLAM", at, e0, e0)])
	log = _capture(sim)
	sim.seconds(1.2)
	t.eq(log["casts"][0][1].hits_dealt[0]["damage"], 23, "an evolution strengthens old Echoes (D21): 19.5 × 1.2 = 23.4 → 23")


func test_echo_hits_never_feed_stars(t: TestContext) -> void:
	sim = RunSim.new(_tree(), "ROGUE", 9)
	sim.activate_boss()
	sim.run.boss._attack_cd = 1e9
	sim.hero.attack_timer = 1e9
	var hero_hits := [0]
	sim.hero.hit_dealt.connect(func(_tg, _h) -> void: hero_hits[0] += 1)
	var b := sim.run.boss.global_position
	var room_center := sim.run.stage.room_center(StageLayout.BOSS_ROOM)
	var anchor_local := b - room_center
	_inject(sim, [_event("MAGI", "SHATTER_NOVA", sim.run.wave_elapsed + 1.1, anchor_local, anchor_local, "", StageLayout.BOSS_ROOM, 0)])
	var log := _capture(sim)
	var hp0 := sim.run.boss.hp
	sim.seconds(1.2)
	t.eq(log["casts"].size(), 1, "Echoes fire in the boss room")
	t.ok(sim.run.boss.hp < hp0, "the Echo damaged Vespera")
	t.eq(hero_hits[0], 0, "echo hits never go through the hero's star tracking (D9)")
	t.eq(sim.run.dagger_hits, 0, "Close Work untouched")


func test_time_rule_hit_stop_does_not_shift_echoes(t: TestContext) -> void:
	sim = RunSim.new(_tree(), "BRUTE", 10)
	sim.hero.attack_timer = 1e9
	_until_wave_live(sim)
	sim.stun_all()
	var e0 := sim.run.alive_enemies()[0].global_position
	var at := sim.run.wave_elapsed + 2.0
	_inject(sim, [_event("MAGI", "SHATTER_NOVA", at, e0, e0)])
	var log := _capture(sim)
	for i in 400:
		if not log["casts"].is_empty():
			break
		sim.step_delta(DT * (0.25 if i % 7 < 3 else 1.0))   # repeated time_scale dips
	t.eq(log["casts"].size(), 1, "cast")
	t.near(log["casts"][0][2], at, DT + 1e-6, "fires at the same game-time t despite dips (D36)")


func test_file_round_trip(t: TestContext) -> void:
	EchoDirector.echo_dir = RunSim.ECHOES
	EchoDirector.begin_recording(STAGE, "ROGUE")
	EchoDirector.record(3, 2, 6.25, Vector3(2, 0, 1), Vector3(6, 0, 1), "ADAPTIVE_BARRAGE", "BOW")
	EchoDirector.commit_victory("yewline_bow")
	var raw := SaveManager.read_json(EchoDirector.path_for(STAGE))
	t.eq(raw["data"]["schema_version"], 1, "schema_version 1 (D15)")
	t.ok(not raw["data"]["echoes"]["ROGUE"].has("client_version"), "no client_version (D34)")
	var evs := EchoDirector.events_for(STAGE, "MAGI")
	t.eq(evs.size(), 1, "loaded for another hero")
	t.eq([evs[0]["hero"], evs[0]["room"], evs[0]["wave"], evs[0]["skill"], evs[0]["mode"]], ["ROGUE", 3, 2, "ADAPTIVE_BARRAGE", "BOW"], "fields")
	t.near(evs[0]["t"], 6.25, 1e-6, "t")
	t.ok(evs[0]["pos"].is_equal_approx(Vector3(2, 0, 1)) and evs[0]["target"].is_equal_approx(Vector3(6, 0, 1)), "vectors")
	t.eq(EchoDirector.events_for(STAGE, "ROGUE").size(), 0, "a hero never replays its own Echoes")
	EchoDirector.echo_dir = EchoDirector.DEFAULT_DIR
	for f in DirAccess.get_files_at(RunSim.ECHOES):
		DirAccess.remove_absolute(RunSim.ECHOES + "/" + f)


func test_echoes_are_always_cold_cyan(t: TestContext) -> void:
	sim = RunSim.new(_tree(), "MAGI", 11)
	sim.hero.attack_timer = 1e9
	_until_wave_live(sim)
	sim.stun_all()
	GameState.inventory.main_for("BRUTE", "GREATAXE").evo_stage = 3
	var e0 := sim.run.alive_enemies()[0].global_position
	_inject(sim, [_event("BRUTE", "LEAP_SLAM", sim.run.wave_elapsed + 1.1, e0, e0)])
	var log := _capture(sim)
	var areas: Array[Area3D] = []
	sim.seconds(0.2)
	var cue: MeshInstance3D = log["cues"][0][0]["cue"]
	var cue_color := (cue.material_override as StandardMaterial3D).albedo_color
	t.ok(cue_color.b > 0.8 and cue_color.r < 0.5, "cue is cyan, never alarm crimson (AD6/AD7)")
	sim.seconds(0.95)
	var actor: SpectralEcho = log["casts"][0][1]
	for m in actor.materials:
		t.ok(m.shader == SpectralEcho.SHADER, "stained_glass_echo shader")
		t.ok((m.get_shader_parameter("echo_color") as Color).is_equal_approx(SpectralEcho.ECHO_CYAN), "cyan even with a Stage 3 warm weapon")
	for n in sim.run.stage.get_children():
		if n is Hitbox and str(n.kind).begins_with("ECHO_"):
			areas.append(n)
	t.ok(not areas.is_empty(), "echo hitbox spawned")
	for a in areas:
		for c in a.get_children():
			if c is MeshInstance3D:
				var col := (c.material_override as StandardMaterial3D).albedo_color
				t.ok(Color(col.r, col.g, col.b).is_equal_approx(Color(SpectralEcho.ECHO_CYAN.r, SpectralEcho.ECHO_CYAN.g, SpectralEcho.ECHO_CYAN.b)), "echo hitbox is cyan")


func test_echo_conducting(t: TestContext) -> void:
	sim = RunSim.new(_tree(), "ROGUE", 12)
	sim.hero.attack_timer = 1e9
	_until_wave_live(sim)
	sim.stun_all()
	var e0 := sim.run.alive_enemies()[0].global_position
	var at := sim.run.wave_elapsed + 1.1
	_inject(sim, [_event("MAGI", "SHATTER_NOVA", at, e0, e0), _event("BRUTE", "VORTEX_CLEAVE", at + 3.0, e0, e0)])
	var log := _capture(sim)
	t.ok(not sim.run.echo_player.conduct(e0), "no live cue yet: nothing to conduct")
	sim.seconds(0.3)
	var ev: Dictionary = log["cues"][0][0]
	var original: Vector3 = ev["point"]
	var want := original + Vector3(4, 0, 0)
	t.ok(sim.run.echo_player.conduct(want), "tap during the cue conducts it")
	t.ok(ev["conducted"], "marked conducted")
	t.ok(Combat.flat_distance(ev["point"], want) < 1e-4, "moved to the tap")
	var gold := (ev["cue"].material_override as StandardMaterial3D).albedo_color
	t.ok(gold.r > 0.8 and gold.g > 0.6 and gold.b < 0.5, "cue ring turns gold")
	t.ok(not sim.run.echo_player.conduct(want + Vector3(1, 0, 0)), "once per Echo")
	sim.seconds(0.9)
	var actor: SpectralEcho = log["casts"][0][1]
	t.ok(Combat.flat_distance(actor.global_position, want) < 1e-4, "the Echo casts where it was conducted")
	sim.seconds(2.0)                      # second event's cue opens at t + 3.0 − 1.0
	var ev2: Dictionary = log["cues"][1][0]
	var resolved: Vector3 = ev2["point"]
	var far: Vector3 = resolved + Vector3(0, 0, -10)
	var hud := sim.run.hud
	var cam := sim.run.camera_rig.camera
	var over_button := hud.buttons[0].get_global_rect().get_center()
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = over_button
	hud._input(touch)
	t.ok(not ev2["conducted"], "a tap on a skill button never conducts")
	t.ok(sim.run.conduct_at_screen(cam.unproject_position(far)), "a tap on open ground conducts")
	t.near(Combat.flat_distance(ev2["point"], resolved), 6.0, 0.05, "clamped to 6 m from the resolved point")


## Regression (found by the windowed run): an Echo's Gravity Well outlives the
## Echo's 0.8 s fade, and its tick callbacks point back at the Echo.
func test_echo_outlives_its_fade_while_its_zone_runs(t: TestContext) -> void:
	sim = RunSim.new(_tree(), "BRUTE", 13)
	sim.hero.attack_timer = 1e9
	_until_wave_live(sim)
	sim.stun_all()
	var e0 := sim.run.alive_enemies()[0].global_position
	_inject(sim, [_event("MAGI", "GRAVITY_WELL", sim.run.wave_elapsed + 1.05, e0, e0)])
	var log := _capture(sim)
	sim.seconds(1.1)
	var actor: SpectralEcho = log["casts"][0][1]
	sim.seconds(1.0)
	t.ok(not actor.visible, "faded after 0.8 s")
	t.ok(not actor.is_queued_for_deletion(), "kept alive while its Gravity Well runs")
	t.eq(sim.run.echo_player.live_actors().size(), 0, "a faded Echo frees its AD12 slot")
	sim.seconds(2.0)
	t.ok(actor.is_queued_for_deletion(), "freed once the zone is done")
	var ticks := actor.hits_dealt.filter(func(h: Dictionary) -> bool: return h["source"] == "GRAVITY_WELL")
	t.eq(ticks.size(), 2, "2.6 s zone (×0.65) ticks twice per enemy")


## Regression: the resolved enemy is freed before the Echo casts.
func test_cast_survives_a_freed_target(t: TestContext) -> void:
	sim = RunSim.new(_tree(), "ROGUE", 14)
	sim.hero.attack_timer = 1e9
	_until_wave_live(sim)
	sim.stun_all()
	var victim: EnemyBase = sim.run.alive_enemies()[0]
	_inject(sim, [_event("ROGUE", "SHATTER_MARK", sim.run.wave_elapsed + 1.1, victim.global_position, victim.global_position)])
	var log := _capture(sim)
	sim.seconds(0.3)
	t.ok(log["cues"][0][0]["target_node"] == victim, "resolved onto the victim")
	sim.run.enemies.erase(victim)
	victim.free()
	sim.seconds(1.0)
	t.eq(log["casts"].size(), 1, "the Echo still casts (no target to mark, no error)")
