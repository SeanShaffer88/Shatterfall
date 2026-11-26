class_name HeroVisuals
extends Node3D
## Gray-box hero silhouettes (AD1) and the emissive gameplay hooks (AD2–AD4, AD11):
##   Brute — armor ember cracks glow with Crimson Guard (dark → dim at 10% → full at 30%).
##   Rogue — gold trim flashes for 0.15 s on every Bow↔Daggers swap.
##   Magi  — the staff's amber orb is bright while the Arcane Glass Barrier is up,
##           dark while it recharges, and is the beam origin of every Prism Bolt.
## Emissive materials only — no extra lights, particles or shadows (AD11/AD12).

const CHARCOAL := Color("#2A2C33")
const GUNMETAL := Color("#545866")   # hero bodies sit a step above #2A2C33 stone (AD1 readability)
const CRIMSON := Color("#D92638")
const GOLD := Color("#D9A441")
const VIOLET := Color("#8F4FD4")
const AMBER := Color("#E8912D")

const EMBER_MAX := 4.0          # Brute crack energy at the 30% Guard cap
const TRIM_BASE := 0.6
const TRIM_FLASH := 4.0
const FLASH_TIME := 0.15        # AD3, tunable
const ORB_UP := 3.5
const ORB_DOWN := 0.0

var hero: HeroController
var accent_color: Color = CRIMSON
var flash_count: int = 0        # AD3 flashes fired (test hook)

var _accent_mat: StandardMaterial3D
var _orb: MeshInstance3D
var _flash_left: float = 0.0


func build(owner_hero: HeroController) -> void:
	hero = owner_hero
	for c in get_children():
		c.free()
	_orb = null
	flash_count = 0
	_flash_left = 0.0
	var body := _mat(GUNMETAL)
	match hero.hero_class:
		HeroController.HeroClass.BRUTE:
			accent_color = CRIMSON
			_accent_mat = _emissive(CRIMSON, 0.0)
			_box(Vector3(1.0, 1.1, 0.7), Vector3(0, 0.75, 0), body)            # torso
			_box(Vector3(1.6, 0.35, 0.8), Vector3(0, 1.35, 0), body)           # heavy shoulder line
			_box(Vector3(0.5, 0.45, 0.5), Vector3(0, 1.75, 0), body)           # helm
			_box(Vector3(0.12, 0.45, 0.12), Vector3(-0.3, 2.05, 0), body)       # horns / crest
			_box(Vector3(0.12, 0.45, 0.12), Vector3(0.3, 2.05, 0), body)
			_box(Vector3(0.9, 0.08, 0.72), Vector3(0, 0.95, 0.01), _accent_mat) # ember cracks
			_box(Vector3(0.14, 1.3, 0.14), Vector3(0.75, 0.9, 0.3), body)       # greataxe haft
			_box(Vector3(0.55, 0.45, 0.06), Vector3(0.75, 1.5, 0.3), body)      # axe head
		HeroController.HeroClass.ROGUE:
			accent_color = GOLD
			_accent_mat = _emissive(GOLD, TRIM_BASE)
			_box(Vector3(0.6, 1.0, 0.45), Vector3(0, 0.75, 0), body)            # slim torso
			_box(Vector3(0.75, 0.18, 0.5), Vector3(0, 1.3, 0), body)            # light shoulders
			_box(Vector3(0.36, 0.38, 0.36), Vector3(0, 1.6, 0), body)           # angular hood
			_box(Vector3(0.64, 0.06, 0.48), Vector3(0, 1.0, 0.01), _accent_mat) # gold trim
			_box(Vector3(0.06, 0.06, 0.7), Vector3(-0.45, 0.9, 0.3), _accent_mat).rotation_degrees = Vector3(0, -20, 0)  # curved daggers
			_box(Vector3(0.06, 0.06, 0.7), Vector3(0.45, 0.9, 0.3), _accent_mat).rotation_degrees = Vector3(0, 20, 0)
		HeroController.HeroClass.MAGI:
			accent_color = VIOLET
			_accent_mat = _emissive(VIOLET, 1.0)
			var robe := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.25
			cone.bottom_radius = 0.7
			cone.height = 1.4
			robe.mesh = cone
			robe.position = Vector3(0, 0.7, 0)
			robe.material_override = body
			add_child(robe)
			_box(Vector3(1.3, 0.12, 0.7), Vector3(0, 1.65, 0), _accent_mat)     # wide, low headdress
			_box(Vector3(0.08, 1.9, 0.08), Vector3(0.55, 0.95, 0.25), body)     # staff
			_orb = MeshInstance3D.new()
			_orb.name = "Orb"
			var sphere := SphereMesh.new()
			sphere.radius = 0.16
			sphere.height = 0.32
			_orb.mesh = sphere
			_orb.position = Vector3(0.55, 2.0, 0.25)
			_orb.material_override = _emissive(AMBER, ORB_UP)
			add_child(_orb)
	for c in get_children():
		if c is GeometryInstance3D:
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not hero.guard_changed.is_connected(_on_guard_changed):
		hero.guard_changed.connect(_on_guard_changed)
		hero.barrier_changed.connect(_on_barrier_changed)
		hero.rogue_mode_changed.connect(_on_rogue_mode_changed)
	_on_guard_changed(hero.guard_fraction())
	_on_barrier_changed(hero.barrier_up)


## Emission energy of the hero's gameplay-coded accent (cracks, trim or orb).
func accent_energy() -> float:
	if hero.hero_class == HeroController.HeroClass.MAGI:
		return (_orb.material_override as StandardMaterial3D).emission_energy_multiplier
	return _accent_mat.emission_energy_multiplier


## AD4: the Prism Bolt beam origin.
func beam_origin() -> Vector3:
	if _orb != null:
		return _orb.global_position
	return hero.global_position + Vector3(0, 1.2, 0)


func _on_guard_changed(fraction: float) -> void:
	if hero.hero_class == HeroController.HeroClass.BRUTE:
		_accent_mat.emission_energy_multiplier = EMBER_MAX * clampf(fraction, 0.0, 1.0)


func _on_barrier_changed(up: bool) -> void:
	if _orb != null:
		(_orb.material_override as StandardMaterial3D).emission_energy_multiplier = ORB_UP if up else ORB_DOWN


func _on_rogue_mode_changed(_mode: int) -> void:
	flash_count += 1
	_flash_left = FLASH_TIME
	_accent_mat.emission_energy_multiplier = TRIM_FLASH


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_accent_mat.emission_energy_multiplier = TRIM_BASE


func is_flashing() -> bool:
	return _flash_left > 0.0


func _box(size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.position = at
	m.material_override = mat
	add_child(m)
	return m


static func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	return m


static func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.5)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m
