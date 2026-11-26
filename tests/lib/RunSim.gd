class_name RunSim
extends RefCounted
## Fixed-step driver for a whole DungeonRun (D38). Saves go to a test slot.
## Helpers clear rooms, walk through doors and reach Vespera without playing
## every swing, so each test can focus on one rule.

const DT := 1.0 / 60.0
const STAGE := "stage_01_sunken_nave"
const SAVE := "user://test_tmp/run_save.json"
const RUN_SCENE := preload("res://scenes/main/DungeonRun.tscn")

var tree: SceneTree
var run: DungeonRun
var hero: HeroController
var time: float = 0.0


func _init(scene_tree: SceneTree, hero_id: String, seed_value: int = 7, last_clearer: String = "") -> void:
	tree = scene_tree
	SaveManager.save_path = SAVE
	GameState.reset_profile()
	if last_clearer != "":
		GameState.last_clearing_hero[STAGE] = last_clearer
	GameState.begin_run(hero_id, seed_value)
	run = RUN_SCENE.instantiate()
	tree.root.add_child(run)
	hero = run.hero


func step(n: int = 1) -> void:
	for i in n:
		if not run.paused:
			hero._physics_process(DT)
			hero.skills.tick(DT)
			hero.visuals.tick(DT)
			for node in tree.get_nodes_in_group(Combat.TICK_GROUP):
				if run.is_ancestor_of(node) and not node.is_queued_for_deletion():
					node.tick(DT)
		run.tick(DT)
		time += DT


func seconds(s: float) -> void:
	step(roundi(s / DT))


func step_until(condition: Callable, max_steps: int = 900) -> bool:
	for i in max_steps:
		if condition.call():
			return true
		step()
	return condition.call()


func kill_all() -> void:
	for e in run.alive_enemies():
		e.take_hit({"damage": 999999, "source": "TEST"})


## Plays the current room's waves to the end by killing each wave as it lands.
func clear_room() -> void:
	var start_room := run.room
	for guard in 20:
		if run.phase != DungeonRun.Phase.ROOM or run.room != start_room:
			return
		step_until(func() -> bool: return not run.alive_enemies().is_empty() or run.phase != DungeonRun.Phase.ROOM, 400)
		kill_all()
		step()


## Moves the hero just inside the next room (doors must already be open).
func enter_next_room() -> void:
	var next := run.room + 1
	var c := run.stage.room_center(next)
	hero.global_position = c + Vector3(0, 0, run.stage.room_size(next) * 0.5 - 3.0)
	hero.velocity = Vector3.ZERO
	step()


## From the start of a run to Vespera's arena (taking boon offer `boon_pick`).
func to_boss(boon_pick: int = 0) -> void:
	while run.room < StageLayout.ROOM_COUNT and run.phase != DungeonRun.Phase.ENDED:
		clear_room()
		if run.phase == DungeonRun.Phase.DRAFT:
			run.pick_boon(boon_pick)
		if run.phase == DungeonRun.Phase.ROOM_CLEARED:
			enter_next_room()


func activate_boss() -> void:
	to_boss()
	step_until(func() -> bool: return run.phase == DungeonRun.Phase.BOSS, 200)


func kill_boss() -> void:
	run.boss.take_hit({"damage": 999999, "source": "TEST"})
	step()


func saved() -> Dictionary:
	return SaveManager.read_json(SAVE)["data"]


func dispose() -> void:
	if is_instance_valid(run):
		run.free()
	tree.paused = false
	GameState.active_hero = ""
	GameState.reset_profile()
	SaveManager.save_path = SaveManager.DEFAULT_SAVE_PATH
	if DirAccess.dir_exists_absolute("user://test_tmp"):
		for f in DirAccess.get_files_at("user://test_tmp"):
			DirAccess.remove_absolute("user://test_tmp/" + f)
