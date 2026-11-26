class_name EnemyProjectile
extends Area3D
## Spitter shot: a straight Area3D projectile on the enemy-attack layer. Hits the
## hero when within radius + hero body radius; Amber Ward applies via the
## `projectile` flag (D29, §2F).

const HERO_RADIUS := 0.4

var direction: Vector3 = Vector3.FORWARD
var speed: float = 9.0
var damage: int = 6
var radius: float = 0.25
var max_distance: float = 16.0
var hero: HeroController
var _travelled: float = 0.0


static func create(from: Vector3, dir: Vector3, move_speed: float, dmg: int, target_hero: HeroController) -> EnemyProjectile:
	var p := EnemyProjectile.new()
	p.name = "SpitterShot"
	p.direction = Combat.flat(dir).normalized()
	p.speed = move_speed
	p.damage = dmg
	p.hero = target_hero
	p.collision_layer = Combat.LAYER_ENEMY_ATTACK
	p.collision_mask = Combat.LAYER_HERO | Combat.LAYER_WORLD
	p.monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = p.radius
	shape.shape = sphere
	p.add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = p.radius
	mesh.height = p.radius * 2.0
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Telegraph.ALARM_WHITE
	mat.render_priority = Telegraph.RENDER_PRIORITY
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi)
	p.position = from
	p.add_to_group(Combat.TICK_GROUP)
	return p


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if is_queued_for_deletion():
		return
	var move := direction * speed * delta
	global_position += move
	_travelled += move.length()
	if is_instance_valid(hero) and hero.hp > 0 \
			and Combat.flat_distance(global_position, hero.global_position) <= radius + HERO_RADIUS:
		hero.take_damage(damage, {"source": "SPITTER", "projectile": true})
		queue_free()
		return
	if _travelled >= max_distance:
		queue_free()
