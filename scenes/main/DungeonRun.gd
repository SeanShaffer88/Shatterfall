class_name DungeonRun
extends Node3D
## One full stage run (§1 loop, §2E–§2H): rooms → waves → boon draft before
## Room 3 → Vespera → victory, death or abandon. Owns run flow (D29), drops
## (D19/D30), star tracking (D37) and the summary (D10). Everything advances in
## `tick(delta)` so headless tests can step it at a fixed 1/60 s.

signal room_started(room: int)
signal wave_spawning(room: int, wave: int, points: Array)
signal wave_started(room: int, wave: int)
signal room_cleared(room: int)
signal draft_opened(offers: Array)
signal boon_taken(id: String)
signal boss_activated
signal run_ended(summary: Dictionary)

enum Phase { ROOM, ROOM_CLEARED, DRAFT, BOSS_INTRO, BOSS, ENDED }

const STAGE_ID := "stage_01_sunken_nave"
const HERO_SCENE := preload("res://scenes/actors/HeroActor.tscn")
const SPAWN_MARKER_RADIUS := 0.8
const DAGGER_SOURCES := ["DAGGER_FLURRY"]

## Used when the scene is run directly (no hero committed from the Hub yet).
@export var dev_hero: String = "BRUTE"

@onready var stage: StageLayout = $Stage
@onready var camera_rig: CameraRig = $CameraRig
@onready var hero_input: HeroInput = $HeroInput
@onready var hud: RunHud = $HUD/RunHud

var hero: HeroController
var cfg: Dictionary = {}
var phase: Phase = Phase.ROOM
var room: int = 0
var wave: int = -1
var paused: bool = false
var result: String = ""                    # "", "VICTORY", "DEFEAT", "ABANDONED"
var summary: Dictionary = {}
var enemies: Array[EnemyBase] = []
var boss: BossVespera
var draft_offers: Array = []
var run_drops: Array[Dictionary] = []
var grudge_hero: String = ""               # last clearer when the run began (D11 bias)

# Star tracking (D37). Echo hits never count (D9).
var fight_time: float = 0.0
var guard_time: float = 0.0
var dagger_hits: int = 0
var room_hp_lost: Dictionary = {}          # room index -> HP lost while its waves were live
var rooms_completed: Array[int] = []

var _wave_timer: float = -1.0
var _spawn_timer: float = -1.0
var _spawn_plan: Array[Dictionary] = []
var _spawn_markers: Array[Telegraph] = []
var _boss_intro: float = -1.0


func _ready() -> void:
	cfg = GameState.stage_cfg(STAGE_ID)
	stage.build_traps(cfg, 2)
	var id := GameState.active_hero
	if id == "":
		id = dev_hero
		GameState.begin_run(id, int(Time.get_unix_time_from_system()))
	grudge_hero = GameState.get_last_clearing_hero(STAGE_ID)
	hero = HERO_SCENE.instantiate()
	hero.name = "Hero"
	stage.add_child(hero)
	hero.global_position = stage.hero_spawn()
	hero.setup(id)
	hero.died.connect(_on_hero_died)
	hero.hit_dealt.connect(_on_hit_dealt)
	hero.damaged.connect(_on_hero_damaged)
	for trap in stage.traps:
		trap.hero = hero
	camera_rig.follow(hero)
	hero_input.bind(hero, hud.stick, camera_rig)
	hud.bind(hero)
	hud.bind_run(self)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_start_room(0)


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if paused or phase == Phase.ENDED:
		return
	match phase:
		Phase.ROOM:
			_tick_waves(delta)
		Phase.ROOM_CLEARED:
			var next := room + 1
			if stage.is_inside(next, hero.global_position, 1.0):
				_enter(next)
		Phase.BOSS_INTRO:
			_boss_intro -= delta
			if _boss_intro <= 0.0:
				_boss_intro = -1.0
				phase = Phase.BOSS
				boss.activate()
				boss_activated.emit()
		Phase.BOSS:
			fight_time += delta
			if hero.guard_active():
				guard_time += delta


# --- Rooms and waves (§2E, D29, D33) ------------------------------------------------

func waves_in(room_index: int) -> Array:
	return cfg["rooms"][room_index]["waves"]


func alive_enemies() -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	for e in enemies:
		if is_instance_valid(e) and e.is_alive():
			out.append(e)
	return out


func _start_room(i: int) -> void:
	room = i
	phase = Phase.ROOM
	room_hp_lost[i] = 0
	for trap in stage.traps:
		trap.arm(i == 2)
	room_started.emit(i)
	_queue_wave(0, true)


func _queue_wave(w: int, first: bool) -> void:
	wave = w
	_wave_timer = 0.0 if first else float(GameState.stages_data["wave_rules"]["next_wave_delay"])
	_spawn_timer = -1.0


func _tick_waves(delta: float) -> void:
	if _wave_timer >= 0.0:
		_wave_timer -= delta
		if _wave_timer <= 0.0:
			_wave_timer = -1.0
			_begin_spawn()
		return
	if _spawn_timer >= 0.0:
		_spawn_timer -= delta
		for m in _spawn_markers:
			m.tick(delta)
		if _spawn_timer <= 0.0:
			_spawn_timer = -1.0
			_spawn_wave()
		return
	if alive_enemies().is_empty():
		if wave + 1 < waves_in(room).size():
			_queue_wave(wave + 1, false)
		else:
			_clear_room()


## Picks spawn points ≥ 6 m from the hero and shows a 1.0 s spawn telegraph.
func _begin_spawn() -> void:
	var rules: Dictionary = GameState.stages_data["wave_rules"]
	var points := _spawn_points_away(room, float(rules["min_spawn_distance"]))
	_spawn_plan.clear()
	var k := 0
	for group in waves_in(room)[wave]:
		for n in int(group["count"]):
			_spawn_plan.append({"type": group["enemy"], "pos": points[k % points.size()]})
			k += 1
	var positions: Array = []
	for p in _spawn_plan:
		var m := Telegraph.circle(SPAWN_MARKER_RADIUS, float(rules["spawn_telegraph"]))
		stage.add_child(m)
		m.global_position = Vector3(p["pos"].x, 0.03, p["pos"].z)
		_spawn_markers.append(m)
		positions.append(p["pos"])
	_spawn_timer = float(rules["spawn_telegraph"])
	wave_spawning.emit(room, wave, positions)


func _spawn_points_away(room_index: int, min_distance: float) -> Array[Vector3]:
	var all := stage.spawn_points(room_index)
	var far: Array[Vector3] = []
	for p in all:
		if Combat.flat_distance(p, hero.global_position) >= min_distance:
			far.append(p)
	if far.is_empty():
		far = all
	for i in range(far.size() - 1, 0, -1):
		var j := GameState.rng_combat.randi_range(0, i)
		var tmp := far[i]
		far[i] = far[j]
		far[j] = tmp
	return far


func _spawn_wave() -> void:
	for m in _spawn_markers:
		m.queue_free()
	_spawn_markers.clear()
	for p in _spawn_plan:
		spawn_enemy(p["type"], p["pos"], room)
	_spawn_plan.clear()
	wave_started.emit(room, wave)


func spawn_enemy(type: String, at: Vector3, room_index: int) -> EnemyBase:
	var e := EnemyBase.new()
	e.setup(type, GameState.stages_data["enemies"][type], hero, stage.room_rect(room_index))
	stage.add_child(e)
	e.global_position = Combat.flat(at)
	enemies.append(e)
	return e


## Last wave down (D29): heal 15%, roll the room drop and save it, then open
## the door — or open the boon draft first when Room 3 is next.
func _clear_room() -> void:
	for trap in stage.traps:
		trap.arm(false)
	rooms_completed.append(room)
	hero.heal(roundi(hero.max_hp * float(cfg["room_clear_heal"])))
	var drop := GameState.loot_table(STAGE_ID).roll_room_drop(GameState.rng_loot, hero.hero_id, grudge_hero)
	if not drop.is_empty():
		run_drops.append(GameState.grant_drop(drop).to_dict())
	SaveManager.save_profile()
	room_cleared.emit(room)
	if room + 1 == int(cfg["boon_draft_before_room"]):
		_open_draft()
	else:
		stage.doors[room].open()
		phase = Phase.ROOM_CLEARED


func _enter(next: int) -> void:
	stage.doors[next - 1].close()          # locks behind the hero
	if next == StageLayout.BOSS_ROOM:
		_start_boss()
	else:
		_start_room(next)


# --- Boon draft (§2F, D14) ------------------------------------------------------------

func _open_draft() -> void:
	phase = Phase.DRAFT
	draft_offers = Boons.draft(GameState.rng_boons, GameState.stages_data["boons"], int(cfg["boon_offer_count"]))
	hud.show_draft(draft_offers)
	draft_opened.emit(draft_offers)


func pick_boon(index: int) -> bool:
	if phase != Phase.DRAFT or index < 0 or index >= draft_offers.size():
		return false
	var boon: Dictionary = draft_offers[index]
	Boons.apply(hero, boon)
	hud.hide_draft()
	boon_taken.emit(boon["id"])
	stage.doors[room].open()
	phase = Phase.ROOM_CLEARED
	return true


# --- Boss (D32, §2H) -------------------------------------------------------------------

func _start_boss() -> void:
	room = StageLayout.BOSS_ROOM
	phase = Phase.BOSS_INTRO
	_boss_intro = float(cfg["boss"]["activation_delay"])
	boss = BossVespera.new()
	boss.setup_boss(cfg["boss"], GameState.active_adaptation(STAGE_ID), hero,
		stage.room_rect(StageLayout.BOSS_ROOM), GameState.rng_combat)
	stage.add_child(boss)
	boss.global_position = stage.boss_spawn()
	boss.died.connect(func(_b: EnemyBase) -> void: _finish("VICTORY"))
	boss.adds_requested.connect(_on_adds_requested)
	hud.show_boss(boss)


func _on_adds_requested(groups: Array) -> void:
	var points := _spawn_points_away(StageLayout.BOSS_ROOM, float(GameState.stages_data["wave_rules"]["min_spawn_distance"]))
	var k := 0
	for group in groups:
		for n in int(group["count"]):
			spawn_enemy(group["enemy"], points[k % points.size()], StageLayout.BOSS_ROOM)
			k += 1


# --- Stars (D37, D9) --------------------------------------------------------------------

func _on_hit_dealt(_target: Node3D, hit: Dictionary) -> void:
	if phase != Phase.BOSS or hit.get("is_echo", false):
		return
	var src: String = hit.get("source", "")
	if src in DAGGER_SOURCES or (src == "ADAPTIVE_BARRAGE" and hit.get("mode", "") == "DAGGERS"):
		dagger_hits += 1


func _on_hero_damaged(hp_lost: int, _by: String) -> void:
	if hp_lost > 0 and phase == Phase.ROOM:
		room_hp_lost[room] = int(room_hp_lost.get(room, 0)) + hp_lost


## Progress toward the current hero's star: { id, metric, value, threshold, met }.
func star_progress() -> Dictionary:
	var st: Dictionary = cfg["stars"][hero.hero_id]
	var thr := float(st["threshold"])
	var value := 0.0
	var met := false
	match str(st["metric"]):
		"guard_uptime_fraction":
			value = guard_time / fight_time if fight_time > 0.0 else 0.0
			met = fight_time > 0.0 and value >= thr - 1e-9
		"dagger_hits":
			value = dagger_hits
			met = value >= thr
		"hp_lost":
			var r := int(str(st["scope"]).trim_prefix("room_"))
			value = room_hp_lost.get(r, 0)
			met = r in rooms_completed and value <= thr
	return {"id": st["id"], "name": st["name"], "metric": st["metric"], "value": value, "threshold": thr, "met": met}


# --- End of run (D10, D29) ----------------------------------------------------------------

func _on_hero_died() -> void:
	_finish("DEFEAT")


func abandon() -> void:
	if phase != Phase.ENDED:
		set_paused(false)
		_finish("ABANDONED")


func _finish(r: String) -> void:
	if phase == Phase.ENDED:
		return
	phase = Phase.ENDED
	result = r
	hero.input_vector = Vector2.ZERO
	for e in alive_enemies():
		e.queue_free()
	var star := star_progress()
	summary = {
		"result": r,
		"hero": hero.hero_id,
		"star": star,
		"star_earned": false,
		"drops": run_drops,
		"boons_lost": hero.boons.duplicate(),
		"essence": "",
		"adaptation": "",
	}
	if r == "VICTORY":
		var bd := GameState.loot_table(STAGE_ID).roll_boss_drop(GameState.rng_loot, hero.hero_id, grudge_hero)
		run_drops.append(GameState.grant_drop(bd["weapon"]).to_dict())
		GameState.inventory.add_essence(bd["essence_id"], 1)
		summary["essence"] = bd["essence_id"]
		GameState.record_victory(STAGE_ID, hero.hero_id, star["met"])
		summary["star_earned"] = star["met"]
		summary["adaptation"] = GameState.active_adaptation(STAGE_ID).get("name", "")
	summary["drops"] = run_drops
	SaveManager.save_profile()
	hud.show_summary(summary)
	run_ended.emit(summary)


# --- Pause (D29) ---------------------------------------------------------------------------

func set_paused(on: bool) -> void:
	if phase == Phase.ENDED and on:
		return
	paused = on
	get_tree().paused = on
	hud.show_pause(on)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if not paused and phase != Phase.ENDED:
			set_paused(true)


## Summary "Continue": a fresh run (the Hub replaces this in Phase 5).
func restart() -> void:
	get_tree().paused = false
	GameState.active_hero = ""
	get_tree().reload_current_scene()
