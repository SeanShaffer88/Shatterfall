class_name Combat
extends RefCounted
## Shared combat constants and geometric target queries.
##
## Hit resolution is geometric (center distance and facing arc on the XZ plane),
## not physics-overlap based, so results are identical in headless fixed-step
## tests and in play (D38). Hitboxes and projectiles are still real Area3D nodes
## with collision shapes on the layers below.
##
## Enemy contract (TrainingDummy now; EnemyBase / BossVespera in Phase 3):
##   is_alive() -> bool
##   take_hit(hit: Dictionary) -> void      # hit keys: damage, crit, source, hero, is_echo, weapon_class
##   has_status(id: String) -> bool
##   status_data(id: String) -> Dictionary
##   apply_status(id: String, data: Dictionary) -> void   # data includes "duration"
##   displace(offset: Vector3) -> void      # pulls / knockback; immune bosses ignore it

const ENEMY_GROUP := "enemies"
const TICK_GROUP := "combat_tick"   # nodes with tick(delta): hitboxes, projectiles, dummies

# Physics layer bits (names are set in project.godot).
const LAYER_WORLD := 1
const LAYER_HERO := 2
const LAYER_ENEMY := 4
const LAYER_HERO_ATTACK := 8
const LAYER_ENEMY_ATTACK := 16


static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func flat_distance(a: Vector3, b: Vector3) -> float:
	return flat(b - a).length()


static func living_enemies(tree: SceneTree) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in tree.get_nodes_in_group(ENEMY_GROUP):
		if n is Node3D and n.is_inside_tree() and not n.is_queued_for_deletion() and n.is_alive():
			out.append(n)
	return out


## Nearest living enemy within `max_range` (center distance), or null.
static func nearest_enemy(tree: SceneTree, from: Vector3, max_range: float = INF) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for e in living_enemies(tree):
		var d := flat_distance(from, e.global_position)
		if d <= max_range and d < best_d:
			best = e
			best_d = d
	return best


static func in_radius(tree: SceneTree, center: Vector3, radius: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for e in living_enemies(tree):
		if flat_distance(center, e.global_position) <= radius:
			out.append(e)
	return out


## Enemies within `reach` and within ±arc/2 of `forward`.
static func in_arc(tree: SceneTree, origin: Vector3, forward: Vector3, reach: float, arc_deg: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var fwd := flat(forward).normalized()
	var half := deg_to_rad(arc_deg) * 0.5
	for e in living_enemies(tree):
		var to := flat(e.global_position - origin)
		if to.length() > reach:
			continue
		if to.length() < 0.001 or fwd.angle_to(to.normalized()) <= half + 1e-6:
			out.append(e)
	return out


## Applies a hit; returns true when it killed the target.
static func apply_hit(target: Node3D, hit: Dictionary) -> bool:
	if not is_instance_valid(target) or not target.is_alive():
		return false
	target.take_hit(hit)
	return not target.is_alive()
