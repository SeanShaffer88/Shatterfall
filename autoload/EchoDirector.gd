extends Node
## Spectral Echo recording and storage (§2B; D12, D21, D23, D34).
## Records the current hero's manual effect-skill casts as wave-relative,
## room-local keyframes (first 2 per wave), and writes them only on victory
## into one file per stage, replacing just that hero's entry.
## Playback lives in EchoPlayer (one per run).

const DEFAULT_DIR := "user://echoes"

## Overridable so tests never touch the player's real echoes.
var echo_dir: String = DEFAULT_DIR
## D12 cap; the Choir Window (D42) raises it to 3 in Phase 5.
var cap_per_wave: int = 2

var _stage_id: String = ""
var _hero_id: String = ""
var _events: Array[Dictionary] = []
var _per_wave: Dictionary = {}          # "room:wave" -> casts recorded


func path_for(stage_id: String) -> String:
	return "%s/%s.json" % [echo_dir, stage_id]


func begin_recording(stage_id: String, hero_id: String) -> void:
	_stage_id = stage_id
	_hero_id = hero_id
	_events.clear()
	_per_wave.clear()


## Stores one cast if its wave still has room under the cap. Positions are
## room-local (relative to that room's EchoAnchor). Returns true when kept.
func record(room: int, wave: int, t: float, pos_local: Vector3, target_local: Vector3, skill: String, mode: String = "") -> bool:
	var key := "%d:%d" % [room, wave]
	var n: int = _per_wave.get(key, 0)
	if n >= cap_per_wave:
		return false
	_per_wave[key] = n + 1
	var ev := {"room": room, "wave": wave, "t": t, "pos": _arr(pos_local), "target": _arr(target_local), "skill": skill}
	if mode != "":
		ev["mode"] = mode
	_events.append(ev)
	return true


func recorded() -> Array[Dictionary]:
	return _events


## Victory only (D10/D12): replaces this hero's entry in the stage file.
## `weapon_id` is informational (D21). Returns OK or the write error.
func commit_victory(weapon_id: String) -> Error:
	var data := load_stage_file(_stage_id)
	var echoes: Dictionary = data.get("echoes", {})
	echoes[_hero_id] = {"weapon_id": weapon_id, "events": _events.duplicate(true)}
	var err := SaveManager.write_json_atomic(path_for(_stage_id), {"stage_id": _stage_id, "echoes": echoes})
	discard()
	return err


## Failed or abandoned runs record nothing (D10, D29).
func discard() -> void:
	_events.clear()
	_per_wave.clear()


## The stage file as stored, or a fresh skeleton when missing or unreadable.
func load_stage_file(stage_id: String) -> Dictionary:
	var r := SaveManager.read_json(path_for(stage_id))
	if not r["ok"]:
		if not r["missing"]:
			push_warning("EchoDirector: ignoring unreadable echo file (%s)" % r["error"])
		return {"stage_id": stage_id, "echoes": {}}
	var data: Dictionary = r["data"]
	if typeof(data.get("echoes")) != TYPE_DICTIONARY:
		push_warning("EchoDirector: %s has no echoes object; ignoring it" % path_for(stage_id))
		return {"stage_id": stage_id, "echoes": {}}
	return data


## Playable events of every hero except `exclude_hero`, with vectors decoded
## and the recording hero attached. Malformed events are skipped.
func events_for(stage_id: String, exclude_hero: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var echoes: Dictionary = load_stage_file(stage_id)["echoes"]
	for hero in echoes:
		if hero == exclude_hero or typeof(echoes[hero]) != TYPE_DICTIONARY:
			continue
		for ev in echoes[hero].get("events", []):
			if not _valid(ev):
				continue
			out.append({
				"hero": str(hero),
				"room": int(ev["room"]),
				"wave": int(ev["wave"]),
				"t": float(ev["t"]),
				"pos": _vec(ev["pos"]),
				"target": _vec(ev["target"]),
				"skill": str(ev["skill"]),
				"mode": str(ev.get("mode", "")),
			})
	return out


func has_echoes_for(stage_id: String, exclude_hero: String) -> bool:
	return not events_for(stage_id, exclude_hero).is_empty()


static func _valid(ev) -> bool:
	if typeof(ev) != TYPE_DICTIONARY:
		return false
	for k in ["room", "wave", "t", "pos", "target", "skill"]:
		if not ev.has(k):
			return false
	return typeof(ev["pos"]) == TYPE_ARRAY and ev["pos"].size() == 3 \
		and typeof(ev["target"]) == TYPE_ARRAY and ev["target"].size() == 3


static func _arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


static func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
