class_name EnemyBase
extends Node3D
## Crawler, Spitter and Bulwark (§2E, D33), implementing the Combat enemy
## contract. Movement is direct and clamped to the enemy's room (no physics
## bodies), so behavior is identical in fixed-step tests and in play.
## Telegraphed attacks use the AD7 alarm language (Telegraph).

signal died(enemy: EnemyBase)

const BODY_RADIUS := 0.5
const CONTACT_RANGE := 1.0      # center distance for Crawler contact
const SEPARATION := 0.9         # enemies push apart inside this distance

var type: String = ""
var cfg: Dictionary = {}
var hp: int = 1
var max_hp: int = 1
var hero: HeroController
var bounds: Rect2 = Rect2(-1000, -1000, 2000, 2000)   # XZ room rect the enemy stays in
var facing: Vector3 = Vector3(0, 0, 1)
var statuses: Dictionary = {}   # id -> data with "time_left"
var hits_taken: int = 0

var _contact_cd: float = 0.0
var _fire_cd: float = 0.0
var _windup: float = -1.0
var _bash_cd: float = 0.0
var _bash_t: float = -1.0
var _telegraph: Telegraph
var _body_mat: StandardMaterial3D
var _area: Area3D


func setup(type_id: String, enemy_cfg: Dictionary, target_hero: HeroController, room_bounds: Rect2) -> void:
	type = type_id
	cfg = enemy_cfg
	max_hp = int(cfg["hp"])
	hp = max_hp
	hero = target_hero
	bounds = room_bounds
	name = type_id.capitalize() + "_" + str(get_instance_id())
	_fire_cd = float(cfg.get("fire_interval", 0.0)) * 0.5
	_build()
	add_to_group(Combat.ENEMY_GROUP)
	add_to_group(Combat.TICK_GROUP)


func _build() -> void:
	_area = Area3D.new()
	_area.collision_layer = Combat.LAYER_ENEMY
	_area.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = BODY_RADIUS
	cyl.height = 1.4
	shape.shape = cyl
	shape.position.y = 0.7
	_area.add_child(shape)
	add_child(_area)
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color("#6B5A52")
	_body_mat.emission_enabled = true
	_body_mat.emission = Telegraph.CRIMSON
	_body_mat.emission_energy_multiplier = 0.0
	var mi := MeshInstance3D.new()
	match type:
		"CRAWLER":
			var m := BoxMesh.new()
			m.size = Vector3(0.8, 0.45, 1.0)
			mi.mesh = m
			mi.position.y = 0.25
		"SPITTER":
			var m := CylinderMesh.new()
			m.top_radius = 0.2
			m.bottom_radius = 0.4
			m.height = 1.3
			mi.mesh = m
			mi.position.y = 0.65
		_:
			var m := BoxMesh.new()
			m.size = Vector3(1.0, 1.3, 0.8)
			mi.mesh = m
			mi.position.y = 0.65
			var shield := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(1.3, 1.1, 0.12)
			shield.mesh = sm
			shield.position = Vector3(0, 0.65, 0.5)
			var smat := StandardMaterial3D.new()
			smat.albedo_color = Color("#8A8F9C")
			shield.material_override = smat
			shield.name = "Shield"
			add_child(shield)
	mi.material_override = _body_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# --- Combat contract -------------------------------------------------------------

func is_alive() -> bool:
	return hp > 0 and not is_queued_for_deletion()


func take_hit(hit: Dictionary) -> void:
	if not is_alive():
		return
	var dmg := int(hit.get("damage", 0))
	if type == "BULWARK" and hit.has("origin") and _in_front(hit["origin"], float(cfg["shield_arc_deg"])):
		dmg = maxi(1, roundi(dmg * (1.0 - float(cfg["shield_reduction"]))))
	hits_taken += 1
	hp = maxi(0, hp - dmg)
	if hp == 0:
		_die()


func has_status(id: String) -> bool:
	return statuses.has(id)


func status_data(id: String) -> Dictionary:
	return statuses.get(id, {})


func apply_status(id: String, data: Dictionary) -> void:
	var d := data.duplicate()
	d["time_left"] = float(data.get("duration", 0.0))
	statuses[id] = d


func displace(offset: Vector3) -> void:
	_set_flat(global_position + Combat.flat(offset))


# --- Behavior ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if not is_alive():
		return
	for id in statuses.keys():
		statuses[id]["time_left"] -= delta
		if statuses[id]["time_left"] <= 0.0:
			statuses.erase(id)
	if _telegraph != null:
		_telegraph.tick(delta)
	_contact_cd = maxf(0.0, _contact_cd - delta)
	_fire_cd = maxf(0.0, _fire_cd - delta)
	_bash_cd = maxf(0.0, _bash_cd - delta)
	if has_status("STUN") or not is_instance_valid(hero) or hero.hp <= 0:
		return
	match type:
		"CRAWLER":
			_tick_crawler(delta)
		"SPITTER":
			_tick_spitter(delta)
		"BULWARK":
			_tick_bulwark(delta)
	_separate()


func _tick_crawler(delta: float) -> void:
	var to := _to_hero()
	if to.length() > CONTACT_RANGE * 0.9:
		_move(to.normalized() * float(cfg["move_speed"]) * delta)
	if _to_hero().length() <= CONTACT_RANGE and _contact_cd <= 0.0:
		_contact_cd = float(cfg["contact_interval"])
		_hit_hero(int(cfg["contact_damage"]), false)


func _tick_spitter(delta: float) -> void:
	var to := _to_hero()
	var d := to.length()
	facing = to.normalized() if d > 0.001 else facing
	if _windup >= 0.0:
		_windup -= delta
		_body_mat.emission_energy_multiplier = 3.0 * (1.0 - maxf(_windup, 0.0) / float(cfg["windup"]))
		if _windup <= 0.0:
			_windup = -1.0
			_body_mat.emission_energy_multiplier = 0.0
			var dmg := _weakened(int(cfg["projectile_damage"]))
			var shot := EnemyProjectile.create(global_position + Vector3(0, 1.0, 0), _to_hero(), float(cfg["projectile_speed"]), dmg, hero)
			get_parent().add_child(shot)
			shot.global_position = global_position + Vector3(0, 1.0, 0)
		return
	if d < float(cfg["hold_min"]):
		_move(-to.normalized() * float(cfg["retreat_speed"]) * delta)
	elif d > float(cfg["hold_max"]):
		_move(to.normalized() * float(cfg["retreat_speed"]) * delta)
	elif _fire_cd <= 0.0:
		_fire_cd = float(cfg["fire_interval"])
		_windup = float(cfg["windup"])


func _tick_bulwark(delta: float) -> void:
	var to := _to_hero()
	var want := to.normalized() if to.length() > 0.001 else facing
	var angle := facing.signed_angle_to(want, Vector3.UP)
	var turn := deg_to_rad(float(cfg["turn_rate_deg"])) * delta
	facing = facing.rotated(Vector3.UP, clampf(angle, -turn, turn)).normalized()
	rotation.y = atan2(facing.x, facing.z)
	if _bash_t >= 0.0:
		_bash_t -= delta
		if _bash_t <= 0.0:
			_bash_t = -1.0
			_clear_telegraph()
			if _to_hero().length() <= float(cfg["bash_reach"]) and _in_front(hero.global_position, float(cfg["shield_arc_deg"])):
				_hit_hero(int(cfg["bash_damage"]), false)
		return
	if to.length() <= float(cfg["bash_reach"]) and _bash_cd <= 0.0:
		_bash_cd = float(cfg["bash_cooldown"])
		_bash_t = float(cfg["bash_telegraph"])
		_telegraph = Telegraph.cone(float(cfg["bash_reach"]), float(cfg["shield_arc_deg"]) * 2.0, _bash_t)
		add_child(_telegraph)
	elif to.length() > float(cfg["bash_reach"]) * 0.85:
		_move(facing * float(cfg["move_speed"]) * delta)


# --- Helpers ------------------------------------------------------------------------

func _to_hero() -> Vector3:
	return Combat.flat(hero.global_position - global_position)


## True when `point` is within ±arc of this enemy's facing.
func _in_front(point: Vector3, arc_deg: float) -> bool:
	var to := Combat.flat(point - global_position)
	if to.length() < 0.001:
		return true
	return facing.angle_to(to.normalized()) <= deg_to_rad(arc_deg) + 1e-6


func _weakened(amount: int) -> int:
	if has_status("WEAKEN"):
		return maxi(1, roundi(amount * float(status_data("WEAKEN").get("damage_mult", 1.0))))
	return amount


func _hit_hero(amount: int, projectile: bool) -> void:
	hero.take_damage(_weakened(amount), {"source": type, "projectile": projectile})


func _move(offset: Vector3) -> void:
	_set_flat(global_position + offset)


func _set_flat(p: Vector3) -> void:
	var margin := BODY_RADIUS + 0.1
	global_position = Vector3(
		clampf(p.x, bounds.position.x + margin, bounds.end.x - margin),
		global_position.y,
		clampf(p.z, bounds.position.y + margin, bounds.end.y - margin))


func _separate() -> void:
	for other in Combat.living_enemies(get_tree()):
		if other == self:
			continue
		var away := Combat.flat(global_position - other.global_position)
		var d := away.length()
		if d < SEPARATION and d > 0.0001:
			_move(away.normalized() * (SEPARATION - d) * 0.5)


func _clear_telegraph() -> void:
	if _telegraph != null:
		_telegraph.queue_free()
		_telegraph = null


func _die() -> void:
	_clear_telegraph()
	died.emit(self)
	queue_free()
