class_name CombatSim
extends RefCounted
## Deterministic fixed-step combat sandbox for headless tests (D38): one hero,
## any number of training dummies, no physics frames between steps. Each step
## advances the hero, its skills/statuses/visuals and every combat-tick node
## (hitboxes, projectiles, dummies) by exactly 1/60 s.

const DT := 1.0 / 60.0
const HERO_SCENE := preload("res://scenes/actors/HeroActor.tscn")

var tree: SceneTree
var root: Node3D
var hero: HeroController
var time: float = 0.0
var spawned: Array[Area3D] = []
var spawn_positions: Array[Vector3] = []
var attacks: Array[String] = []


func _init(scene_tree: SceneTree, hero_id: String, seed_value: int = 1) -> void:
	tree = scene_tree
	GameState.reset_profile()
	GameState.begin_run(hero_id, seed_value)
	root = Node3D.new()
	root.name = "CombatSim"
	tree.root.add_child(root)
	hero = HERO_SCENE.instantiate()
	root.add_child(hero)
	hero.setup(hero_id)
	# move_and_slide() advances by the engine's physics delta, not by the delta
	# passed to _physics_process, so manual steps are only exact when they match.
	var engine_dt := hero.get_physics_process_delta_time()
	if absf(engine_dt - DT) > 1e-6:
		push_error("CombatSim: engine physics delta is %f, expected %f" % [engine_dt, DT])
	hero.attack_spawned.connect(func(n: Area3D) -> void:
		spawned.append(n)
		spawn_positions.append(n.global_position))
	hero.primary_attack_fired.connect(func(id: String, _t: Node3D) -> void: attacks.append(id))


func dummy(at: Vector3, hp: int = 100000) -> TrainingDummy:
	var d := TrainingDummy.new()
	d.max_hp = hp
	root.add_child(d)
	d.global_position = at
	return d


func step(n: int = 1) -> void:
	for i in n:
		hero._physics_process(DT)
		hero.skills.tick(DT)
		hero.visuals.tick(DT)
		for node in tree.get_nodes_in_group(Combat.TICK_GROUP):
			if root.is_ancestor_of(node) and not node.is_queued_for_deletion():
				node.tick(DT)
		time += DT


func seconds(s: float) -> void:
	step(roundi(s / DT))


## Steps until `condition` is true; returns the number of steps taken, or -1.
func step_until(condition: Callable, max_steps: int = 600) -> int:
	for i in max_steps:
		if condition.call():
			return i
		step()
	return max_steps if condition.call() else -1


func spawned_of(kind: String) -> Array[Area3D]:
	var out: Array[Area3D] = []
	for n in spawned:
		if is_instance_valid(n) and n.get("kind") == kind:
			out.append(n)
	return out


func cast(skill: String) -> bool:
	return hero.skills.request(hero.skills.index_of(skill))


func dispose() -> void:
	if is_instance_valid(root):
		root.free()
