class_name SpectralEcho
extends Node3D
## One Echo re-cast (§2B, D35): a cyan stained-glass ghost of the recording
## hero that casts one skill at ×0.65 values (radii, pulls and knockback
## unchanged), never crits, uses the recording hero's *current* weapon (D21),
## then dissolves. Its hits carry `is_echo`, so they never feed stars (D9) and
## never trigger Spiked Carapace recoil, while other adaptations still apply.

signal attack_spawned(node: Area3D)
signal hit_dealt(target: Node3D, hit: Dictionary)   # cyan damage numbers

const ECHO_CYAN := Color("#5FD4E6")     # AD6: always cold cyan, even for warm weapons
const POTENCY := 0.65
const LIFETIME := 0.8
const SHADER := preload("res://shaders/stained_glass_echo.gdshader")
const NOVA_KNOCKBACK := 3.0
const VORTEX_PULL := 1.5
const WELL_PULL_SPEED := 2.0
const FAN_ARC := 120.0
const BARRAGE_STAGGER := 0.06

var hero_id: String = ""                # the recording hero
var skill_id: String = ""
var mode: String = ""
var player: HeroController              # the hero playing now (Shatter Mark heals them)
var hits_dealt: Array[Dictionary] = []
var materials: Array[ShaderMaterial] = []

var _age: float = 0.0
var _pending: Array[Dictionary] = []
var _spawned: Array[Area3D] = []      # zones/projectiles whose callbacks point back here


func setup(recording_hero: String, skill: String, skill_mode: String, current_hero: HeroController) -> void:
	hero_id = recording_hero
	skill_id = skill
	mode = skill_mode
	player = current_hero
	name = "Echo_%s_%s" % [hero_id, skill_id]
	add_to_group(Combat.TICK_GROUP)
	_build()


func skill_def() -> Dictionary:
	for s in GameState.heroes_data["heroes"][hero_id]["skills"]:
		if s["id"] == skill_id:
			return s
	return {}


func _build() -> void:
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.4 if hero_id != "BRUTE" else 0.55
	cap.height = 1.8
	body.mesh = cap
	body.position.y = 0.9
	add_child(body)
	var crown := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = {"BRUTE": Vector3(1.4, 0.3, 0.6), "ROGUE": Vector3(0.6, 0.3, 0.5), "MAGI": Vector3(1.3, 0.12, 0.7)}.get(hero_id, Vector3.ONE * 0.4)
	crown.mesh = box
	crown.position.y = 1.75
	add_child(crown)
	for m in [body, crown]:
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("echo_color", ECHO_CYAN)
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		materials.append(mat)


# --- Casting (§2B echo table) -----------------------------------------------------

## Casts at `point`; `target` is the resolved enemy (may be null).
func cast(point: Vector3, target: Node3D) -> void:
	var d := skill_def()
	var p: Dictionary = d.get("params", {})
	match skill_id:
		"LEAP_SLAM":
			_area("LEAP_SLAM", point, float(p["radius"]), func(e: Node3D) -> void:
				_deal(e, _dmg(d), _aoe(point, float(p["radius"])))
				e.apply_status("STUN", _aoe(point, float(p["radius"]), {"duration": float(p["stun"]) * POTENCY})))
		"RENDING_ROAR":
			_area("RENDING_ROAR", point, float(p["radius"]), func(e: Node3D) -> void:
				e.apply_status("WEAKEN", _aoe(point, float(p["radius"]), {
					"duration": float(p["duration"]) * POTENCY, "damage_mult": float(p["enemy_damage_mult"])})))
		"VORTEX_CLEAVE":
			_area("VORTEX_CLEAVE", point, float(p["radius"]), func(e: Node3D) -> void:
				_deal(e, _dmg(d), _aoe(point, float(p["radius"])))
				var to := Combat.flat(point - e.global_position)
				var pull := minf(VORTEX_PULL, maxf(0.0, to.length() - 1.0))
				if pull > 0.0:
					e.displace(to.normalized() * pull))
		"SHATTER_NOVA":
			_area("SHATTER_NOVA", point, float(p["radius"]), func(e: Node3D) -> void:
				_deal(e, _dmg(d), _aoe(point, float(p["radius"])))
				var away := Combat.flat(e.global_position - point)
				e.displace((away.normalized() if away.length() > 0.001 else Vector3(0, 0, 1)) * NOVA_KNOCKBACK))
		"SHATTER_MARK":
			if is_instance_valid(target) and target.is_alive():
				_spawn_hitbox("SHATTER_MARK", target.global_position, 0.6)
				target.apply_status("MARK", {
					"duration": float(p["duration"]) * POTENCY,
					"damage_taken_mult": float(p["damage_taken_mult"]),
					"kill_heal": int(float(p["kill_heal"]) * POTENCY),
					"hero": hero_id, "is_echo": true,
				})
		"GRAVITY_WELL":
			_gravity_well(d, point)
		"ADAPTIVE_BARRAGE":
			_barrage(d, point, target)


func _gravity_well(d: Dictionary, center: Vector3) -> void:
	var p: Dictionary = d["params"]
	var radius := float(p["radius"])
	var dmg := _dmg(d)
	var zone := _spawn_hitbox("GRAVITY_WELL", center, radius)
	zone.duration = float(p["duration"]) * POTENCY
	zone.tick_interval = 1.0
	zone.on_tick = func() -> void:
		for e in Combat.in_radius(get_tree(), zone.global_position, radius):
			_deal(e, dmg, _aoe(zone.global_position, radius, {"zone_age": zone._age, "zone_duration": zone.duration}))
	zone.on_physics = func(delta: float) -> void:
		for e in Combat.in_radius(get_tree(), zone.global_position, radius):
			var to := Combat.flat(zone.global_position - e.global_position)
			if to.length() > 0.05:
				e.displace(to.normalized() * minf(WELL_PULL_SPEED * delta, to.length()))


func _barrage(d: Dictionary, point: Vector3, target: Node3D) -> void:
	var entry := _dmg(d, mode)
	var to := Combat.flat(point - global_position)
	var dir := to.normalized() if to.length() > 0.001 else Vector3(0, 0, 1)
	if mode == "DAGGERS":
		var reach := HeroController.DAGGER_EXIT
		_spawn_hitbox("ADAPTIVE_BARRAGE_DAGGERS", global_position + dir * reach * 0.5, reach)
		var hits := Combat.in_arc(get_tree(), global_position, dir, reach, FAN_ARC)
		for i in int(entry["hits"]):
			for e in hits:
				_deal(e, entry, {"mode": "DAGGERS"})
		return
	for i in int(entry["hits"]):
		var spread := deg_to_rad((i - (int(entry["hits"]) - 1) * 0.5) * 8.0)
		var arrow_dir := dir.rotated(Vector3.UP, spread)
		_pending.append({"t": i * BARRAGE_STAGGER, "fn": func() -> void:
			var pr := Projectile.create("ECHO_ADAPTIVE_BARRAGE_ARROW", global_position + Vector3(0, 1.2, 0), arrow_dir,
				HeroController.ARROW_SPEED, HeroController.BOW_RANGE + HeroController.ARROW_OVERSHOOT, ECHO_CYAN)
			pr.homing_target = target
			pr.on_hit = func(e: Node3D) -> void: _deal(e, entry, {"mode": "BOW"})
			get_parent().add_child(pr)
			pr.global_position = global_position + Vector3(0, 1.2, 0)
			_spawned.append(pr)
			attack_spawned.emit(pr)})


# --- Helpers -------------------------------------------------------------------------

## The skill's damage entry (by Barrage mode), or {} for non-damaging skills.
func _dmg(d: Dictionary, want_mode: String = "") -> Dictionary:
	for e in d.get("damage", []):
		if want_mode == "" or str(e["mode"]) == want_mode:
			return e
	return {}


func _aoe(center: Vector3, radius: float, data: Dictionary = {}) -> Dictionary:
	var out := data.duplicate()
	out["aoe_center"] = center
	out["aoe_radius"] = radius
	return out


func _area(kind: String, at: Vector3, radius: float, each: Callable) -> void:
	_spawn_hitbox(kind, at, radius)
	for e in Combat.in_radius(get_tree(), at, radius):
		each.call(e)


func _spawn_hitbox(kind: String, at: Vector3, radius: float) -> Hitbox:
	var hb := Hitbox.create("ECHO_" + kind, at, radius, ECHO_CYAN)
	get_parent().add_child(hb)
	hb.global_position = Vector3(at.x, 0.0, at.z)
	_spawned.append(hb)
	attack_spawned.emit(hb)
	return hb


## ×0.65, never a crit, the recording hero's current weapon (D21, D35).
func _deal(target: Node3D, entry: Dictionary, extra: Dictionary = {}) -> void:
	if entry.is_empty() or not is_instance_valid(target) or not target.is_alive():
		return
	var cls: String = entry["weapon_class"]
	var w: Weapon = GameState.inventory.main_for(hero_id, cls)
	var marked: bool = target.has_status("MARK")
	var mark_mult := float(target.status_data("MARK").get("damage_taken_mult", 1.0)) if marked else 1.0
	var hit := {
		"damage": GameState.forge.damage(w, float(entry["damage_l1"]) * POTENCY, 1.0, mark_mult, false),
		"crit": false,
		"source": skill_id,
		"hero": hero_id,
		"is_echo": true,
		"weapon_class": cls,
		"origin": global_position,
	}
	hit.merge(extra)
	hits_dealt.append(hit)
	var killed := Combat.apply_hit(target, hit)
	hit_dealt.emit(target, hit)
	if killed and marked and is_instance_valid(player):
		player.heal(int(target.status_data("MARK").get("kill_heal", 0)))


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if is_queued_for_deletion():
		return
	_age += delta
	for p in _pending.duplicate():
		p["t"] -= delta
		if p["t"] <= 1e-6:
			_pending.erase(p)
			p["fn"].call()
	var fade := clampf((_age - LIFETIME * 0.5) / (LIFETIME * 0.5), 0.0, 1.0)
	for m in materials:
		m.set_shader_parameter("dissolve", fade)
	if _age >= LIFETIME:
		visible = false
		if _pending.is_empty() and not has_live_attacks():
			queue_free()


## The ghost fades out after LIFETIME but the node lives on, invisibly, while
## any zone or projectile it spawned still runs (their callbacks use this node).
func has_live_attacks() -> bool:
	for a in _spawned:
		if is_instance_valid(a) and not a.is_queued_for_deletion():
			return true
	return false
