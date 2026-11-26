class_name MainHub
extends Node3D
## The Hub: a shattered cathedral (§2I, D42) around a stained-glass dais (AD9).
## Hero cards, the Stage Briefing, the Forge tome (AD8, D13, D16–D20, D31),
## window restoration with Glass, barks (D43), the evolution moment (AD10) and
## "Enter the Nave". Logic is exposed as small methods so Gate 5 can test it
## without clicking; the UI calls the same methods.

signal evolution_sequence_finished(weapon_id: String)
signal hub_changed

const STAGE_ID := "stage_01_sunken_nave"
const RUN_SCENE := "res://scenes/main/DungeonRun.tscn"
const HEROES: Array[String] = ["BRUTE", "ROGUE", "MAGI"]
const CLASS_COLORS := {"GREATAXE": Color("#D92638"), "DAGGERS": Color("#D9A441"), "SHORTBOW": Color("#D9A441"), "STAFF": Color("#8F4FD4")}
## AD9: dais glow per evolution stage (Base dim smoky, Stage 2 brighter, Stage 3 full bloom).
const DAIS_GLOW := {1: 0.6, 2: 2.0, 3: 5.0}
const SMOKY := Color(0.55, 0.52, 0.5)
## AD10 timeline (seconds): rise → stained-glass wash → return.
const SEQ_RISE := 0.5
const SEQ_WASH := 0.6
const SEQ_RETURN := 0.5

var selected_hero: String = "BRUTE"
var selected_class: String = "GREATAXE"
var sequences_played: int = 0
var ui: HubUI

var _dais_weapon: MeshInstance3D
var _dais_mat: StandardMaterial3D
var _window_panels: Array[MeshInstance3D] = []
var _pending_absorb: Dictionary = {}          # at-cap confirmation (D31)
var _seq: Dictionary = {}                     # active AD10 sequence


func _ready() -> void:
	_build_world()
	ui = HubUI.new()
	ui.name = "HubUI"
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	layer.add_child(ui)
	ui.bind(self)
	BarkDirector.blocked_check = Callable()
	if not BarkDirector.line_shown.is_connected(ui.show_bark):
		BarkDirector.line_shown.connect(ui.show_bark)
	select_hero(GameState.active_hero if GameState.active_hero != "" else "BRUTE")


func _exit_tree() -> void:
	if ui != null and BarkDirector.line_shown.is_connected(ui.show_bark):
		BarkDirector.line_shown.disconnect(ui.show_bark)


# --- Selection, cards, briefing -------------------------------------------------------

func select_hero(hero_id: String) -> void:
	selected_hero = hero_id
	selected_class = GameState.heroes_data["heroes"][hero_id]["weapon_classes"][0]
	_pending_absorb = {}
	_refresh_dais()
	hub_changed.emit()


func select_class(weapon_class: String) -> void:
	if weapon_class in GameState.heroes_data["heroes"][selected_hero]["weapon_classes"]:
		selected_class = weapon_class
		_pending_absorb = {}
		_refresh_dais()
		hub_changed.emit()


func main_weapon(hero_id: String = "", weapon_class: String = "") -> Weapon:
	var h := hero_id if hero_id != "" else selected_hero
	var c: String = weapon_class if weapon_class != "" else GameState.heroes_data["heroes"][h]["weapon_classes"][0]
	return GameState.inventory.main_for(h, c)


func weapon_name(w: Weapon) -> String:
	return GameState.forge.stage_entry(w.weapon_class, w.evo_stage).get("name", w.weapon_id)


## Hero card: weapon, stage, rarity, ATK (D25), stars (D7), grudge warning (§2H).
func hero_card(hero_id: String) -> Dictionary:
	var w := main_weapon(hero_id)
	var card := {
		"hero": hero_id,
		"weapon": weapon_name(w),
		"stage": w.evo_stage,
		"rarity": w.rarity,
		"level": w.level,
		"atk": roundi(GameState.forge.atk_eff(w)),
		"star": GameState.has_star(STAGE_ID, hero_id),
		"grudge": "",
		"tip": "",
	}
	if GameState.get_last_clearing_hero(STAGE_ID) == hero_id:
		var a := GameState.active_adaptation(STAGE_ID)
		card["grudge"] = "Vespera adapted to you: %s" % a["name"]
		card["tip"] = a["tip"]
	return card


func briefing(hero_id: String = "") -> Dictionary:
	var h := hero_id if hero_id != "" else selected_hero
	var cfg := GameState.stage_cfg(STAGE_ID)
	var stars: Array = []
	for other in HEROES:
		var st: Dictionary = cfg["stars"][other]
		stars.append({"hero": other, "name": st["name"], "condition": star_text(st), "earned": GameState.has_star(STAGE_ID, other)})
	var by_hero := {}
	for ev in EchoDirector.events_for(STAGE_ID, h):
		by_hero[ev["hero"]] = int(by_hero.get(ev["hero"], 0)) + 1
	var echo_text := "No echoes yet — clear this stage with another hero"
	if not by_hero.is_empty():
		var parts: PackedStringArray = []
		for k in by_hero:
			parts.append("%s (%d casts)" % [str(k).capitalize(), by_hero[k]])
		echo_text = "Echoes ready: " + ", ".join(parts)
	var a := GameState.active_adaptation(STAGE_ID)
	return {
		"stage": cfg["name"],
		"hazards": "Four rooms of Crawlers, Spitters and Bulwarks; spike traps in Room 3. Vespera telegraphs a sweep and shard rain; at half health she calls Crawlers, raises shard walls and the Twin Reliquaries.",
		"stars": stars,
		"echoes": by_hero,
		"echo_text": echo_text,
		"adaptation": a.get("name", "None yet"),
		"adaptation_tip": a.get("tip", ""),
	}


static func star_text(st: Dictionary) -> String:
	match str(st["metric"]):
		"guard_uptime_fraction":
			return "Keep Crimson Guard up for %d%% of the Vespera fight" % roundi(float(st["threshold"]) * 100)
		"dagger_hits":
			return "Land %d dagger hits during the Vespera fight" % int(st["threshold"])
		"hp_lost":
			return "Clear Room 2 without losing any HP"
	return ""


# --- Forge (AD8; D13, D16–D20, D31) ----------------------------------------------------

func forge_locked() -> bool:
	return not GameState.forge_unlocked


## Fodder for the selected main: same class & owner (absorbable) and everything
## else that can only be salvaged ("Not usable — salvage only", D5).
func forge_items() -> Dictionary:
	var main := main_weapon(selected_hero, selected_class)
	var absorbable: Array[Weapon] = []
	var salvage_only: Array[Weapon] = []
	for w in GameState.inventory.fodder():
		if GameState.forge.can_absorb(main, w):
			absorbable.append(w)
		elif w.owner_hero != selected_hero:
			salvage_only.append(w)
	return {"main": main, "absorbable": absorbable, "salvage_only": salvage_only}


## AD8 runes: one per requirement of the next evolution, lit when met.
func rune_state(w: Weapon = null) -> Dictionary:
	var weapon := w if w != null else main_weapon(selected_hero, selected_class)
	var s := GameState.forge.evolution_status(GameState.inventory, weapon)
	var recipe: Dictionary = s["recipe"]
	return {
		"final": s["final"],
		"level": s["level_ok"],
		"shards": s["shards_ok"],
		"essence": s["essence_ok"],
		"needs_essence": not recipe.is_empty() and str(recipe.get("boss_essence_id", "")) != "",
		"stage3_orb": not recipe.is_empty() and int(recipe["stage"]) == 3,
		"available": s["available"],
	}


## One tap absorbs; at the level cap the first tap only warns (D31), a second
## tap on the same fodder confirms. Result: { ok, needs_confirm, discard, ... }.
func absorb(fodder_uid: String) -> Dictionary:
	if forge_locked():
		return {"ok": false, "error": "The Forge wakes once Vespera falls."}
	var main := main_weapon(selected_hero, selected_class)
	var fodder := GameState.inventory.get_weapon(fodder_uid)
	if fodder == null:
		return {"ok": false, "error": "unknown weapon"}
	var discard := GameState.forge.would_discard_xp(main, fodder)
	if discard > 0 and _pending_absorb.get("uid", "") != fodder_uid:
		_pending_absorb = {"uid": fodder_uid}
		return {"ok": false, "needs_confirm": true, "discard": discard,
			"error": "At the level cap: %d XP would be lost. Tap again to absorb anyway." % discard}
	_pending_absorb = {}
	var r := GameState.forge.absorb(GameState.inventory, main.uid, fodder_uid)
	_after_forge_action()
	return r


func salvage(uid: String) -> Dictionary:
	if forge_locked():
		return {"ok": false, "error": "The Forge wakes once Vespera falls."}
	_pending_absorb = {}
	var r := GameState.salvage(uid)
	_after_forge_action()
	return r


func evolve() -> Dictionary:
	if forge_locked():
		return {"ok": false, "error": "The Forge wakes once Vespera falls."}
	var main := main_weapon(selected_hero, selected_class)
	var first := GameState.evolutions_done == 0
	var r := GameState.evolve(main.uid)
	if r["ok"]:
		_start_sequence(main)
		if first:
			BarkDirector.say("RELIQUARY", "FIRST_EVOLUTION")
	_after_forge_action()
	return r


func _after_forge_action() -> void:
	SaveManager.save_profile()
	if _seq.is_empty():
		_refresh_dais()
	hub_changed.emit()


# --- Restore the Reliquary (D42) --------------------------------------------------------

func restore_window() -> Dictionary:
	var r := GameState.restore_next_window()
	if r["ok"]:
		SaveManager.save_profile()
		_refresh_windows()
		BarkDirector.say("RELIQUARY", "WINDOW_RESTORED")
	hub_changed.emit()
	return r


func window_lit(i: int) -> bool:
	return i < GameState.windows_restored


func window_energy(i: int) -> float:
	return (_window_panels[i].material_override as StandardMaterial3D).emission_energy_multiplier


# --- Dais (AD9) and the evolution moment (AD10) -----------------------------------------

## The dais blade's glow: energy by evolution stage, smoky at Base, the class
## colour once evolved.
func dais_glow() -> Dictionary:
	return {"stage": _shown_stage(), "energy": _dais_mat.emission_energy_multiplier, "color": _dais_mat.emission}


func _shown_stage() -> int:
	return int(_dais_weapon.get_meta("stage", 1))


func _refresh_dais() -> void:
	var w := main_weapon(selected_hero, selected_class)
	_dais_weapon.set_meta("stage", w.evo_stage)
	_dais_mat.emission = SMOKY if w.evo_stage == 1 else CLASS_COLORS.get(w.weapon_class, Color.WHITE)
	_dais_mat.emission_energy_multiplier = DAIS_GLOW[w.evo_stage]
	var h := 1.6 + 0.25 * (w.evo_stage - 1)
	(_dais_weapon.mesh as BoxMesh).size = Vector3(0.18, h, 0.05 + 0.03 * w.evo_stage)


func is_sequence_playing() -> bool:
	return not _seq.is_empty()


func _start_sequence(w: Weapon) -> void:
	_seq = {"t": 0.0, "weapon_id": w.weapon_id, "swapped": false}


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if _seq.is_empty():
		return
	_seq["t"] += delta
	var t: float = _seq["t"]
	var base_y := 1.1
	if t < SEQ_RISE:
		_dais_weapon.position.y = base_y + t / SEQ_RISE
		ui.set_wash(0.0)
	elif t < SEQ_RISE + SEQ_WASH:
		var k := (t - SEQ_RISE) / SEQ_WASH
		ui.set_wash(sin(k * PI))
		if k >= 0.5 and not _seq["swapped"]:
			_seq["swapped"] = true
			_refresh_dais()                      # new mesh/glow appears inside the wash
	elif t < SEQ_RISE + SEQ_WASH + SEQ_RETURN:
		ui.set_wash(0.0)
		_dais_weapon.position.y = base_y + 1.0 - (t - SEQ_RISE - SEQ_WASH) / SEQ_RETURN
	else:
		_dais_weapon.position.y = base_y
		var id: String = _seq["weapon_id"]
		_seq = {}
		sequences_played += 1
		evolution_sequence_finished.emit(id)


# --- Run hand-off ----------------------------------------------------------------------------

## Commits the selected hero (D7: one hero per run) and enters the Nave.
func commit_run(change_scene: bool = true) -> void:
	GameState.begin_run(selected_hero, int(Time.get_unix_time_from_system()) ^ (GameState.runs_started * 7919))
	SaveManager.save_profile()
	if change_scene:
		get_tree().change_scene_to_file(RUN_SCENE)


# --- World (gray-box cathedral) --------------------------------------------------------------

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#121318")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.3, 0.28, 0.36)
	e.ambient_light_energy = 0.7
	e.glow_enabled = true
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -20, 0)
	key.light_energy = 0.8
	key.light_color = Color(0.95, 0.75, 0.6)
	add_child(key)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("#2A2C33")
	_mesh(BoxMesh.new(), Vector3(24, 0.4, 14), Vector3(0, -0.2, -2), stone)          # nave floor
	_mesh(BoxMesh.new(), Vector3(24, 9, 0.6), Vector3(0, 4.5, -8), stone)             # back wall
	var dais := CylinderMesh.new()
	dais.top_radius = 1.6
	dais.bottom_radius = 1.9
	dais.height = 0.5
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color("#3A2F4A")
	glass.emission_enabled = true
	glass.emission = Color("#8F4FD4")
	glass.emission_energy_multiplier = 0.6
	_mesh(dais, Vector3.ONE, Vector3(0, 0.25, 0), glass)
	for i in 6:                                                                      # candles
		var a := TAU * i / 6.0
		var wax := StandardMaterial3D.new()
		wax.albedo_color = Color("#D8CFC0")
		var c := CylinderMesh.new()
		c.top_radius = 0.08
		c.bottom_radius = 0.08
		c.height = 0.4
		_mesh(c, Vector3.ONE, Vector3(cos(a) * 2.4, 0.2, sin(a) * 2.4), wax)
		var flame := StandardMaterial3D.new()
		flame.emission_enabled = true
		flame.emission = Color("#E8912D")
		flame.emission_energy_multiplier = 3.0
		var f := SphereMesh.new()
		f.radius = 0.06
		f.height = 0.12
		_mesh(f, Vector3.ONE, Vector3(cos(a) * 2.4, 0.46, sin(a) * 2.4), flame)
	_dais_mat = StandardMaterial3D.new()
	_dais_mat.albedo_color = Color("#5A5E6A")
	_dais_mat.emission_enabled = true
	_dais_mat.emission = SMOKY
	_dais_mat.emission_energy_multiplier = DAIS_GLOW[1]
	_dais_weapon = _mesh(BoxMesh.new(), Vector3(0.18, 1.6, 0.08), Vector3(0, 1.1, 0), _dais_mat)
	_dais_weapon.name = "DaisWeapon"
	_dais_weapon.mesh = BoxMesh.new()
	(_dais_weapon.mesh as BoxMesh).size = Vector3(0.18, 1.6, 0.08)
	for i in GameState.windows().size():                                             # six windows
		var w: Dictionary = GameState.windows()[i]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#1A1B20")
		mat.emission_enabled = true
		mat.emission = Color(w["color"])
		var panel := _mesh(BoxMesh.new(), Vector3(2.2, 4.2, 0.1), Vector3(-9.0 + i * 3.6, 4.5, -7.6), mat)
		(panel.mesh as BoxMesh).size = Vector3(2.2, 4.2, 0.1)
		panel.name = "Window_%s" % w["id"]
		_window_panels.append(panel)
	_refresh_windows()
	var cam := Camera3D.new()
	cam.position = Vector3(0, 5.2, 9.5)
	cam.rotation_degrees = Vector3(-18, 0, 0)
	cam.fov = 55
	cam.current = true
	add_child(cam)


func _refresh_windows() -> void:
	for i in _window_panels.size():
		var mat := _window_panels[i].material_override as StandardMaterial3D
		mat.emission_energy_multiplier = 2.5 if window_lit(i) else 0.05
		mat.albedo_color = Color(GameState.windows()[i]["color"]).darkened(0.3) if window_lit(i) else Color("#1A1B20")


func _mesh(m: Mesh, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	if m is BoxMesh:
		(m as BoxMesh).size = size
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = at
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi
