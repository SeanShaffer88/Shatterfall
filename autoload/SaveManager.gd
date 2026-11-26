extends Node
## Atomic JSON persistence (D15) with exactly one save slot (D23).
## Writes go to "<path>.tmp" and are then renamed over the target, so a crash
## mid-write never leaves a half-written save.

const SCHEMA_VERSION := 1
const DEFAULT_SAVE_PATH := "user://save.json"

## Overridable so tests never touch the real save slot.
var save_path: String = DEFAULT_SAVE_PATH


## Stamps schema_version and writes atomically. Returns OK or the failing Error.
func write_json_atomic(path: String, data: Dictionary) -> Error:
	var payload := data.duplicate(true)
	payload["schema_version"] = SCHEMA_VERSION
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var mk := DirAccess.make_dir_recursive_absolute(dir)
		if mk != OK:
			return mk
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(payload, "\t"))
	var write_err := f.get_error()
	f.close()
	if write_err != OK:
		DirAccess.remove_absolute(tmp)
		return write_err
	return DirAccess.rename_absolute(tmp, path)


## Result: { ok, data, error }. A missing file is an error with `missing: true`.
func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "missing": true, "data": {}, "error": "%s: file not found" % path}
	var r := DataLoader.parse(FileAccess.get_file_as_string(path), path.get_file())
	r["missing"] = false
	return r


func has_save() -> bool:
	return FileAccess.file_exists(save_path)


func save_profile() -> Error:
	return write_json_atomic(save_path, GameState.to_save_dict())


## Loads the save slot into GameState. Returns "" on success or when no save
## exists yet. A corrupt save is moved aside to "<name>.corrupt.json" so the
## player starts fresh instead of crashing, and the error is returned.
func load_profile() -> String:
	if not has_save():
		return ""
	var r := read_json(save_path)
	var err: String = r["error"]
	if r["ok"]:
		err = GameState.apply_save_dict(r["data"])
	if err != "":
		_quarantine(err)
	return err


func _quarantine(reason: String) -> void:
	var aside := save_path.get_basename() + ".corrupt.json"
	if FileAccess.file_exists(aside):
		DirAccess.remove_absolute(aside)
	DirAccess.rename_absolute(save_path, aside)
	push_error("SaveManager: save rejected (%s); moved to %s and starting fresh" % [reason, aside])
	GameState.reset_profile()
