extends RefCounted
## Gate 2: D3 camera rig, hero framing at 16:9 and 19.5:9, HUD layout (D1, §3.1),
## touch + keyboard input, and a DungeonRun scene smoke test.

const RUN_SCENE := preload("res://scenes/main/DungeonRun.tscn")

var sim: CombatSim
var nodes: Array[Node] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	if sim != null:
		sim.dispose()
		sim = null
	for n in nodes:
		if is_instance_valid(n):
			n.free()
	nodes.clear()
	GameState.active_hero = ""


func _keep(n: Node) -> Node:
	nodes.append(n)
	return n


func _rig_for(s: CombatSim) -> CameraRig:
	var rig := CameraRig.new()
	s.root.add_child(rig)
	rig.follow(s.hero)
	return rig


func test_camera_rig_matches_d3(t: TestContext) -> void:
	sim = CombatSim.new(_tree(), "BRUTE")
	var rig := _rig_for(sim)
	var p := deg_to_rad(40.0)
	t.ok(rig.top_level, "rig is top-level (never inherits hero rotation)")
	t.ok(rig.camera.position.distance_to(Vector3(0, 11.0 * sin(p), 11.0 * cos(p))) < 1e-5, "11 m boom at 40° pitch")
	t.near(rig.camera.rotation_degrees.x, -40.0, 1e-4, "pitch −40°")
	t.near(rig.camera.fov, 45.0, 1e-6, "FOV 45°")
	t.ok(rig.camera.current, "camera is current")
	var to_hero := (sim.hero.global_position - rig.camera.global_position).normalized()
	var look := -rig.camera.global_transform.basis.z
	t.ok(look.angle_to(to_hero) < 0.001, "camera looks straight at the hero")
	sim.hero.rotation.y = 2.0
	rig.tick(CombatSim.DT)
	t.near(rig.camera.global_rotation_degrees.y, 0.0, 1e-4, "hero rotation never turns the camera")


func test_camera_follow_smoothing(t: TestContext) -> void:
	sim = CombatSim.new(_tree(), "ROGUE")
	var rig := _rig_for(sim)
	sim.hero.global_position = Vector3(4, 0, 0)
	for i in 9:
		rig.tick(CombatSim.DT)
	var frac := rig.global_position.x / 4.0
	t.near(frac, 1.0 - exp(-0.15 / 0.15), 0.01, "63% of the way after one 0.15 s time constant")
	for i in 51:
		rig.tick(CombatSim.DT)
	t.ok(rig.global_position.distance_to(Vector3(4, 0, 0)) < 0.01, "locked on after 1 s")
	t.near(rig.global_position.y, 0.0, 1e-6, "pivot stays on the ground plane")


func test_hero_framed_at_16_9_and_19_5_9(t: TestContext) -> void:
	sim = CombatSim.new(_tree(), "MAGI")
	var rig := _rig_for(sim)
	for size in [Vector2i(2400, 1080), Vector2i(3120, 1440)]:
		var vp := SubViewport.new()
		vp.size = size
		vp.disable_3d = false
		_keep(vp)
		_tree().root.add_child(vp)
		var cam := Camera3D.new()
		vp.add_child(cam)
		cam.fov = rig.camera.fov
		cam.global_transform = rig.camera.global_transform
		var feet := cam.unproject_position(sim.hero.global_position)
		var head := cam.unproject_position(sim.hero.global_position + Vector3(0, 2.0, 0))
		var label := "%dx%d" % [size.x, size.y]
		t.near(feet.x, size.x * 0.5, 1.0, "%s: hero centered horizontally" % label)
		t.ok(feet.y > size.y * 0.35 and feet.y < size.y * 0.65, "%s: feet in the middle band (%.0f)" % [label, feet.y])
		t.ok(head.y > 48.0, "%s: head below the top safe margin" % label)
		var ui_top: float = size.y - 48.0 - 268.0 * size.y / 1080.0
		t.ok(feet.y < ui_top, "%s: hero clear of the bottom controls" % label)


func _hud(size: Vector2) -> RunHud:
	# The whole run scene inside a SubViewport of the target resolution, so the
	# HUD's anchors resolve exactly as they do on a device screen.
	var vp := SubViewport.new()
	vp.size = Vector2i(size)
	_keep(vp)
	_tree().root.add_child(vp)
	GameState.active_hero = ""
	var run := RUN_SCENE.instantiate()
	vp.add_child(run)
	return run.get_node("HUD/RunHud")


func test_hud_layout_safe_margins_16_9_and_19_5_9(t: TestContext) -> void:
	for size in [Vector2(2400, 1080), Vector2(2340, 1080)]:
		var hud := _hud(size)
		t.eq(hud.size, size, "HUD fills the %dx%d screen" % [size.x, size.y])
		var bounds := Rect2(Vector2.ZERO, size).grow(-48.0)
		var label := "%dx%d" % [size.x, size.y]
		var stick: Control = hud.get_node("VirtualStick")
		t.ok(bounds.encloses(stick.get_rect()), "%s: stick inside 48 px margins" % label)
		t.ok(stick.get_rect().position.x < size.x * 0.5, "%s: stick bottom-left" % label)
		var rects: Array[Rect2] = []
		for name in ["Skill1", "Skill2", "Skill3"]:
			var b: Control = hud.get_node(name)
			t.ok(bounds.encloses(b.get_rect()), "%s: %s inside 48 px margins" % [label, name])
			t.ok(b.get_rect().position.x > size.x * 0.5, "%s: %s bottom-right" % [label, name])
			t.ok(not b.get_rect().intersects(stick.get_rect()), "%s: %s never overlaps the stick" % [label, name])
			for r in rects:
				t.ok(not b.get_rect().intersects(r), "%s: %s does not overlap another button" % [label, name])
			rects.append(b.get_rect())
		var stats: Label = hud.get_node("Stats")
		t.ok(stats.get_rect().position.x >= 48.0 and stats.get_rect().position.y >= 48.0, "%s: stats top-left inside margins" % label)
		for n in nodes:
			n.free()
		nodes.clear()


func _touch(index: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	return e


func _drag(index: int, pos: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	return e


func test_virtual_stick_touch(t: TestContext) -> void:
	var stick := VirtualStick.new()
	_keep(stick)
	_tree().root.add_child(stick)
	stick.position = Vector2(48, 380)
	stick.size = Vector2(960, 652)
	t.ok(not stick.handle(_touch(0, Vector2(1500, 700), true)), "touch outside is ignored")
	t.ok(stick.handle(_touch(1, Vector2(300, 800), true)), "touch inside starts the stick")
	t.ok(stick.is_active(), "active")
	stick.handle(_drag(1, Vector2(380, 800)))
	t.ok(stick.output.distance_to(Vector2(0.5, 0)) < 1e-5, "80 px of a 160 px radius = 0.5")
	stick.handle(_drag(1, Vector2(300, 400)))
	t.ok(stick.output.distance_to(Vector2(0, -1)) < 1e-5, "clamped to length 1, up is −Y")
	t.ok(not stick.handle(_drag(2, Vector2(900, 900))), "another finger does not move the stick")
	stick.handle(_touch(1, Vector2(300, 400), false))
	t.eq(stick.output, Vector2.ZERO, "release recenters")
	t.ok(not stick.is_active(), "inactive after release")


func test_skill_button_touch_requests_skill(t: TestContext) -> void:
	sim = CombatSim.new(_tree(), "BRUTE")
	var b := SkillButton.new()
	_keep(b)
	_tree().root.add_child(b)
	b.index = 1
	b.position = Vector2(2000, 800)
	b.size = Vector2(200, 200)
	b.bind(sim.hero.skills)
	t.eq(b.label_text, "RENDING ROAR", "label from heroes.json")
	t.ok(not b.handle(_touch(0, Vector2(2005, 805), true)), "corner outside the circle ignored")
	t.ok(b.handle(_touch(0, Vector2(2100, 900), true)), "touch inside the circle")
	t.ok(not sim.hero.skills.is_ready(1), "skill cast and on cooldown")
	t.near(b.ring_fraction(), 1.0, 1e-6, "ring full right after the cast")


func test_keyboard_fallback(t: TestContext) -> void:
	sim = CombatSim.new(_tree(), "MAGI")
	HeroInput.ensure_actions()
	var input := HeroInput.new()
	_keep(input)
	_tree().root.add_child(input)
	input.bind(sim.hero, null)
	Input.action_press("move_up")
	Input.action_press("move_right")
	var v := input.current_vector()
	Input.action_release("move_up")
	Input.action_release("move_right")
	t.ok(v.distance_to(Vector2(1, -1).normalized()) < 1e-4, "W + D → normalized up-right: %s" % str(v))
	t.eq(input.current_vector(), Vector2.ZERO, "released keys → zero")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_L
	key.pressed = true
	input._unhandled_input(key)
	t.ok(not sim.hero.skills.is_ready(2), "L casts skill 3 (Shatter Nova)")


func test_dungeon_run_scene_smoke(t: TestContext) -> void:
	GameState.reset_profile()
	GameState.active_hero = ""
	var run: DungeonRun = RUN_SCENE.instantiate()
	run.dev_hero = "ROGUE"
	_keep(run)
	_tree().root.add_child(run)
	t.ok(run.hero != null and run.hero.hero_id == "ROGUE", "dev hero spawned")
	t.eq(GameState.active_hero, "ROGUE", "run begun for the dev hero")
	t.ok(run.camera_rig.target == run.hero, "camera follows the hero")
	t.ok(run.camera_rig.camera.current, "run camera is current")
	t.eq(run.hud.buttons.size(), 3, "3 skill buttons")
	t.eq(run.hud.buttons[0].label_text, "SHADOW VAULT", "buttons bound to the hero's skills")
	t.ok(run.hero_input.hero == run.hero and run.hero_input.stick == run.hud.stick, "input wired to hero and stick")
	t.eq(run.arena.get_node("DummyA").get("max_hp"), 300, "gray-box arena with training dummies")
	for i in 30:
		run.hero._physics_process(CombatSim.DT)
		run.hero.skills.tick(CombatSim.DT)
	t.ok(run.hero.hp == run.hero.max_hp, "hero idles safely")
