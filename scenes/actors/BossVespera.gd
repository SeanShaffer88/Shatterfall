class_name BossVespera
extends EnemyBase
## Vespera (§2E, D32) with her single active Grudge Adaptation (§2H, D11).
## 1600 HP, immune to stun/pull/knockback. Keeps 4–8 m from the hero and picks
## an attack every 2.5 s (1.8 s in phase 2): a 120° sweep or a 3-zone shard rain,
## both AD7-telegraphed. Phase 2 (≤ 50% HP) spawns 4 Crawlers once and raises a
## shard wall every 12 s.

signal phase_changed(phase_index: int)
signal adds_requested(groups: Array)          # the run controller spawns them
signal wall_raised(wall: ShardWall)
signal blinked(from: Vector3, to: Vector3)
signal reliquaries_raised(pillars: Array)
signal adaptation_triggered(id: String)        # first time per fight (D43 barks)
signal reliquaries_resolved(success: bool)

const MELEE_SOURCES := ["CLEAVE", "LEAP_SLAM", "VORTEX_CLEAVE", "DAGGER_FLURRY"]

var boss_cfg: Dictionary = {}
var adaptation: Dictionary = {}               # {} before the first clear
var active: bool = false
var phase_index: int = 0
var rng: RandomNumberGenerator

var current_attack: Dictionary = {}           # {id, t, full, telegraphs, dir, zones}
var _attack_cd: float = 0.0
var _veil_t: float = 0.0
var _wall_t: float = 0.0
var _adds_spawned: bool = false

# Twin Reliquaries (D41): phase-2 two-body mechanic and its Shatter Shield.
var shield_left: float = 0.0
var pillars: Array[ReliquaryPillar] = []
var _pillar_t: float = 0.0
var _pair_age: float = 0.0
var _break_times: Array[float] = []
var _clock: float = 0.0
var _adaptation_announced: bool = false


func setup_boss(cfg_boss: Dictionary, adapt: Dictionary, target_hero: HeroController, arena: Rect2, random: RandomNumberGenerator) -> void:
	boss_cfg = cfg_boss
	adaptation = adapt
	rng = random
	setup("VESPERA", {"hp": cfg_boss["hp"], "move_speed": cfg_boss["move_speed"]}, target_hero, arena)
	name = "Vespera"
	scale = Vector3(1.6, 1.6, 1.6)


## Gray-box Vespera: a tall glass-crowned figure (no shield, unlike the Bulwark).
func _build() -> void:
	_area = Area3D.new()
	_area.collision_layer = Combat.LAYER_ENEMY
	_area.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = BODY_RADIUS
	cyl.height = 2.2
	shape.shape = cyl
	shape.position.y = 1.1
	_area.add_child(shape)
	add_child(_area)
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color("#4A3F5C")
	var body := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.25
	cone.bottom_radius = 0.6
	cone.height = 2.0
	body.mesh = cone
	body.position.y = 1.0
	body.material_override = _body_mat
	add_child(body)
	var crown := MeshInstance3D.new()
	var cm := PrismMesh.new()
	cm.size = Vector3(0.9, 0.5, 0.3)
	crown.mesh = cm
	crown.position.y = 2.25
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color("#8F4FD4")
	glass.emission_enabled = true
	glass.emission = Color("#8F4FD4")
	glass.emission_energy_multiplier = 1.5
	crown.material_override = glass
	add_child(crown)
	for c in get_children():
		if c is GeometryInstance3D:
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func adaptation_id() -> String:
	return adaptation.get("id", "")


func phase_cfg() -> Dictionary:
	return boss_cfg["phases"][phase_index]


func activate() -> void:
	active = true
	_attack_cd = float(phase_cfg()["attack_interval"])


# --- Contract overrides ------------------------------------------------------------

func take_hit(hit: Dictionary) -> void:
	if not is_alive():
		return
	if adaptation_id() == "RUNIC_DAMPENING" and not _dampening_allows(hit):
		_announce_adaptation()
		return
	var before := hp
	var dmg := int(hit.get("damage", 0))
	if shield_left > 0.0:
		dmg = maxi(1, roundi(dmg * float(_twin()["shield_damage_taken_mult"])))
	hp = maxi(0, hp - dmg)
	hits_taken += 1
	if adaptation_id() == "SPIKED_CARAPACE" and not hit.get("is_echo", false) and _is_melee(hit) and is_instance_valid(hero):
		var recoil := roundi((before - hp) * float(adaptation["params"]["recoil_fraction"]))
		hero.apply_recoil(recoil)
		_announce_adaptation()
	if phase_index == 0 and hp <= int(boss_cfg["hp"]) * float(boss_cfg["phases"][1]["hp_at_or_below"]):
		_enter_phase_two()
	if hp == 0:
		_cancel_attack()
		_clear_pillars()
		_die()


func apply_status(id: String, data: Dictionary) -> void:
	if id in ["STUN"] and "STUN" in boss_cfg["immune"]:
		return
	if adaptation_id() == "RUNIC_DAMPENING":
		if not _dampening_allows(data):
			return
		data = data.duplicate()
		data["duration"] = float(data.get("duration", 0.0)) * float(adaptation["params"]["duration_mult"])
	super.apply_status(id, data)


func displace(_offset: Vector3) -> void:
	pass   # immune to pull and knockback (D32)


func _is_melee(hit: Dictionary) -> bool:
	var src: String = hit.get("source", "")
	return src in MELEE_SOURCES or (src == "ADAPTIVE_BARRAGE" and hit.get("mode", "") == "DAGGERS")


## Runic Dampening: an AoE reaches her only if her center is inside 70% of its
## radius; zone ticks only during the first 70% of the zone's life.
func _dampening_allows(info: Dictionary) -> bool:
	var p: Dictionary = adaptation["params"]
	if info.has("aoe_radius"):
		var d := Combat.flat_distance(global_position, info["aoe_center"])
		if d > float(info["aoe_radius"]) * float(p["radius_mult"]) + 1e-6:
			return false
	if info.has("zone_duration") and float(info["zone_age"]) > float(info["zone_duration"]) * float(p["duration_mult"]) + 1e-6:
		return false
	return true


# --- Behavior ---------------------------------------------------------------------

func tick(delta: float) -> void:
	if not is_alive() or not active:
		return
	for id in statuses.keys():
		statuses[id]["time_left"] -= delta
		if statuses[id]["time_left"] <= 0.0:
			statuses.erase(id)
	if not is_instance_valid(hero) or hero.hp <= 0:
		return
	_keep_distance(delta)
	if adaptation_id() == "MIRAGE_VEIL":
		_veil_t += delta
		if _veil_t >= float(adaptation["params"]["interval"]):
			_veil_t = 0.0
			_blink()
	_clock += delta
	shield_left = maxf(0.0, shield_left - delta)
	if phase_index == 1:
		_wall_t += delta
		if _wall_t >= float(phase_cfg()["shard_wall_interval"]):
			_wall_t = 0.0
			_raise_wall()
		_tick_reliquaries(delta)
	if not current_attack.is_empty():
		current_attack["t"] -= delta
		for tg in current_attack["telegraphs"]:
			if is_instance_valid(tg):
				tg.tick(delta)
		if current_attack["t"] <= 0.0:
			_resolve_attack()
		return
	_attack_cd -= delta
	if _attack_cd <= 0.0:
		_start_attack("SWEEP" if rng.randf() < 0.5 else "SHARD_RAIN")


func _keep_distance(delta: float) -> void:
	var to := _to_hero()
	var d := to.length()
	if d > 0.001:
		facing = to.normalized()
		rotation.y = atan2(facing.x, facing.z)
	var speed := float(boss_cfg["move_speed"]) * delta
	if d > float(boss_cfg["keep_max"]):
		_move(facing * speed)
	elif d < float(boss_cfg["keep_min"]):
		_move(-facing * speed)


func _telegraph_time(id: String) -> float:
	return float(phase_cfg()["sweep_telegraph" if id == "SWEEP" else "rain_telegraph"])


func _start_attack(id: String) -> void:
	var full := _telegraph_time(id)
	current_attack = {"id": id, "t": full, "full": full, "telegraphs": []}
	_place_attack()


## Lays out the attack's telegraphs from Vespera's current position.
func _place_attack() -> void:
	for tg in current_attack.get("telegraphs", []):
		if is_instance_valid(tg):
			tg.queue_free()
	var tgs: Array = []
	var id: String = current_attack["id"]
	var a: Dictionary = boss_cfg["attacks"][id]
	var world := get_parent()
	if id == "SWEEP":
		var dir := _to_hero().normalized() if _to_hero().length() > 0.001 else facing
		current_attack["origin"] = global_position
		current_attack["dir"] = dir
		var tg := Telegraph.cone(float(a["range"]), float(a["arc_deg"]), current_attack["full"])
		world.add_child(tg)
		tg.global_position = Vector3(global_position.x, 0.03, global_position.z)
		tg.rotation.y = atan2(dir.x, dir.z)
		tgs.append(tg)
	else:
		var zones: Array = [Combat.flat(hero.global_position)]
		for i in int(a["zones"]) - 1:
			var ang := rng.randf() * TAU
			var r := rng.randf() * float(a["scatter"])
			zones.append(_clamp_point(Combat.flat(hero.global_position) + Vector3(cos(ang), 0, sin(ang)) * r))
		current_attack["zones"] = zones
		for z in zones:
			var tg := Telegraph.circle(float(a["radius"]), current_attack["full"])
			world.add_child(tg)
			tg.global_position = Vector3(z.x, 0.03, z.z)
			tgs.append(tg)
	current_attack["telegraphs"] = tgs


func _resolve_attack() -> void:
	var id: String = current_attack["id"]
	var a: Dictionary = boss_cfg["attacks"][id]
	if id == "SWEEP":
		var to := Combat.flat(hero.global_position - current_attack["origin"])
		var inside: bool = to.length() <= float(a["range"]) and (to.length() < 0.001 \
			or current_attack["dir"].angle_to(to.normalized()) <= deg_to_rad(float(a["arc_deg"])) * 0.5 + 1e-6)
		if inside:
			_hit_hero(int(a["damage"]), false)
	else:
		for z in current_attack["zones"]:
			if Combat.flat_distance(hero.global_position, z) <= float(a["radius"]):
				_hit_hero(int(a["damage"]), false)
	_cancel_attack()
	_attack_cd = float(phase_cfg()["attack_interval"])


func _cancel_attack() -> void:
	for tg in current_attack.get("telegraphs", []):
		if is_instance_valid(tg):
			tg.queue_free()
	current_attack = {}


## Mirage Veil: blink 3 m sideways; an active telegraph restarts from her new
## position with its full warning time (D32: delayed, never unwarned).
func _blink() -> void:
	var to := _to_hero().normalized() if _to_hero().length() > 0.001 else facing
	var side := to.cross(Vector3.UP).normalized() * (1.0 if rng.randf() < 0.5 else -1.0)
	var from := global_position
	_move(side * float(adaptation["params"]["blink_distance"]))
	blinked.emit(from, global_position)
	_announce_adaptation()
	if not current_attack.is_empty():
		current_attack["t"] = current_attack["full"]
		_place_attack()


func _enter_phase_two() -> void:
	phase_index = 1
	_wall_t = 0.0
	_pillar_t = 0.0
	phase_changed.emit(1)
	if not _adds_spawned:
		_adds_spawned = true
		adds_requested.emit(phase_cfg()["spawn_once"])


func _raise_wall() -> void:
	var a: Dictionary = boss_cfg["attacks"]["SHARD_WALL"]
	var dir := _to_hero().normalized() if _to_hero().length() > 0.001 else facing
	var wall := ShardWall.new()
	wall.setup(a)
	get_parent().add_child(wall)
	wall.global_position = Combat.flat(global_position) + dir * float(a["distance_from_boss"])
	wall.rotation.y = atan2(dir.x, dir.z)
	wall_raised.emit(wall)


# --- Twin Reliquaries (D41) ----------------------------------------------------------

func _announce_adaptation() -> void:
	if not _adaptation_announced and adaptation_id() != "":
		_adaptation_announced = true
		adaptation_triggered.emit(adaptation_id())


func _twin() -> Dictionary:
	return boss_cfg["twin_reliquaries"]


func is_shielded() -> bool:
	return shield_left > 0.0


func _tick_reliquaries(delta: float) -> void:
	var cfg_t := _twin()
	if pillars.is_empty():
		_pillar_t += delta
		if _pillar_t >= float(cfg_t["interval"]):
			_pillar_t = 0.0
			raise_reliquaries()
		return
	_pair_age += delta
	if _pair_age >= float(cfg_t["time_limit"]):
		_resolve_reliquaries(false)


## Two pillars on opposite sides of the arena center, `spacing` apart.
func raise_reliquaries() -> void:
	_clear_pillars()
	var cfg_t := _twin()
	var center := Vector3(bounds.get_center().x, 0.0, bounds.get_center().y)
	var half := float(cfg_t["spacing"]) * 0.5
	for side in [-1.0, 1.0]:
		var p := ReliquaryPillar.new()
		p.setup(float(cfg_t["time_limit"]), float(cfg_t["pillar_radius"]))
		get_parent().add_child(p)
		p.global_position = center + Vector3(side * half, 0.0, 0.0)
		p.broken.connect(_on_pillar_broken)
		pillars.append(p)
	_pair_age = 0.0
	_break_times.clear()
	reliquaries_raised.emit(pillars)


func _on_pillar_broken(_p: ReliquaryPillar) -> void:
	_break_times.append(_clock)
	if _break_times.size() >= 2:
		_resolve_reliquaries(absf(_break_times[1] - _break_times[0]) <= float(_twin()["window"]) + 1e-6)


## Both broken within the window: they shatter harmlessly. Otherwise Vespera
## gains (or refreshes) Shatter Shield. Never fatal.
func _resolve_reliquaries(success: bool) -> void:
	if not success:
		shield_left = float(_twin()["shield_duration"])
	_clear_pillars()
	reliquaries_resolved.emit(success)


func _clear_pillars() -> void:
	for p in pillars:
		if is_instance_valid(p):
			p.queue_free()
	pillars.clear()
	_break_times.clear()
	_pair_age = 0.0


func _clamp_point(p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, bounds.position.x, bounds.end.x), 0.0, clampf(p.z, bounds.position.y, bounds.end.y))
