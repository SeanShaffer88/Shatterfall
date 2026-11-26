class_name StageLayout
extends Node3D
## Gray-box Stage 1 — The Sunken Nave (§2E): 4 rooms (16 × 16 m) and Vespera's
## 18 × 18 m arena in a line along −Z, joined by 4 m corridors with a Door each.
## Every room has an EchoAnchor (Marker3D, Phase 4) and a ring of spawn points;
## Room 3 has the four spike panels. Built in code from these constants so the
## geometry, the spawn rules and the tests share one source of truth.

const ROOM_COUNT := 4                 # combat rooms; index 4 is the boss arena
const BOSS_ROOM := 4
const ROOM_SIZE := 16.0
const BOSS_SIZE := 18.0
const CORRIDOR := 4.0                 # length and width of each corridor
const WALL_H := 3.0
const WALL_T := 1.0
const TRAP_OFFSETS := [Vector3(-3, 0, -3), Vector3(3, 0, -3), Vector3(-3, 0, 3), Vector3(3, 0, 3)]

var doors: Array[Door] = []
var traps: Array[SpikeTrap] = []
var rooms: Array[Node3D] = []
var _stone: StandardMaterial3D


func _ready() -> void:
	if rooms.is_empty():
		build()


func room_size(i: int) -> float:
	return BOSS_SIZE if i == BOSS_ROOM else ROOM_SIZE


func room_center(i: int) -> Vector3:
	var z := 0.0
	for k in i:
		z -= room_size(k) * 0.5 + CORRIDOR + room_size(k + 1) * 0.5
	return Vector3(0, 0, z)


## XZ rectangle of room `i` (x → Rect2.x, z → Rect2.y).
func room_rect(i: int) -> Rect2:
	var c := room_center(i)
	var s := room_size(i)
	return Rect2(c.x - s * 0.5, c.z - s * 0.5, s, s)


func room_index_at(p: Vector3) -> int:
	for i in ROOM_COUNT + 1:
		if room_rect(i).has_point(Vector2(p.x, p.z)):
			return i
	return -1


## True when `p` is inside room `i` and at least `margin` from its edges.
func is_inside(i: int, p: Vector3, margin: float) -> bool:
	return room_rect(i).grow(-margin).has_point(Vector2(p.x, p.z))


func hero_spawn() -> Vector3:
	return room_center(0) + Vector3(0, 0, 5)


func boss_spawn() -> Vector3:
	return room_center(BOSS_ROOM) + Vector3(0, 0, -4)


## The corridor door between room i and room i + 1.
func door_z(i: int) -> float:
	return room_center(i).z - room_size(i) * 0.5 - CORRIDOR * 0.5


func echo_anchor(i: int) -> Marker3D:
	return rooms[i].get_node("EchoAnchor")


## Ring of spawn points 1.5 m inside the walls, plus the room's far corners.
func spawn_points(i: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var c := room_center(i)
	var r := room_size(i) * 0.5 - 1.5
	for k in 12:
		var a := TAU * k / 12.0
		out.append(c + Vector3(cos(a) * r, 0, sin(a) * r))
	return out


func build() -> void:
	_stone = StandardMaterial3D.new()
	_stone.albedo_color = Color("#2A2C33")
	_stone.roughness = 0.9
	_build_lighting()
	for i in ROOM_COUNT + 1:
		var node := Node3D.new()
		node.name = "BossArena" if i == BOSS_ROOM else "Room%d" % (i + 1)
		add_child(node)
		node.position = room_center(i)
		rooms.append(node)
		var anchor := Marker3D.new()
		anchor.name = "EchoAnchor"
		node.add_child(anchor)
		_build_room(i)
		if i < ROOM_COUNT:
			_build_corridor(i)


func _build_lighting() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#121318")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.32, 0.3, 0.38)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, 30, 0)
	key.light_color = Color(0.95, 0.72, 0.55)
	key.light_energy = 1.3
	key.shadow_enabled = false
	add_child(key)


func _build_room(i: int) -> void:
	var c := room_center(i)
	var s := room_size(i)
	var h := s * 0.5
	_solid(Vector3(s, 1, s), c + Vector3(0, -0.5, 0), "Floor%d" % i)
	_solid(Vector3(WALL_T, WALL_H, s), c + Vector3(-h - WALL_T * 0.5, WALL_H * 0.5, 0), "WallW%d" % i)
	_solid(Vector3(WALL_T, WALL_H, s), c + Vector3(h + WALL_T * 0.5, WALL_H * 0.5, 0), "WallE%d" % i)
	# South (+Z) side opens toward the previous corridor, north (−Z) toward the next.
	_wall_with_gap(c.z + h + WALL_T * 0.5, s, i > 0, "WallS%d" % i)
	_wall_with_gap(c.z - h - WALL_T * 0.5, s, i < ROOM_COUNT, "WallN%d" % i)


func _wall_with_gap(z: float, width: float, gap: bool, label: String) -> void:
	if not gap:
		_solid(Vector3(width + WALL_T * 2.0, WALL_H, WALL_T), Vector3(0, WALL_H * 0.5, z), label)
		return
	var seg := (width + WALL_T * 2.0 - CORRIDOR) * 0.5
	var off := CORRIDOR * 0.5 + seg * 0.5
	_solid(Vector3(seg, WALL_H, WALL_T), Vector3(-off, WALL_H * 0.5, z), label + "a")
	_solid(Vector3(seg, WALL_H, WALL_T), Vector3(off, WALL_H * 0.5, z), label + "b")


func _build_corridor(i: int) -> void:
	var z := door_z(i)
	_solid(Vector3(CORRIDOR, 1, CORRIDOR), Vector3(0, -0.5, z), "CorridorFloor%d" % i)
	_solid(Vector3(WALL_T, WALL_H, CORRIDOR), Vector3(-CORRIDOR * 0.5 - WALL_T * 0.5, WALL_H * 0.5, z), "CorridorW%d" % i)
	_solid(Vector3(WALL_T, WALL_H, CORRIDOR), Vector3(CORRIDOR * 0.5 + WALL_T * 0.5, WALL_H * 0.5, z), "CorridorE%d" % i)
	var door := Door.new()
	door.name = "Door%d" % (i + 1)
	door.setup(CORRIDOR, WALL_H, 0.5)
	add_child(door)
	door.position = Vector3(0, 0, z)
	doors.append(door)


## Places Room 3's spike panels from stages.json (D33).
func build_traps(stage_cfg: Dictionary, room_index: int) -> void:
	var trap_ids: Array = stage_cfg["rooms"][room_index]["traps"]
	for k in trap_ids.size():
		var id: String = trap_ids[k]
		var trap := SpikeTrap.new()
		trap.setup(id, int(stage_cfg["traps"]["groups"][id]), stage_cfg["traps"]["spike"])
		rooms[room_index].add_child(trap)
		trap.position = TRAP_OFFSETS[k % TRAP_OFFSETS.size()]
		traps.append(trap)


func _solid(size: Vector3, at: Vector3, label: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = Combat.LAYER_WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = _stone
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mesh)
	add_child(body)
	body.position = at
	return body
