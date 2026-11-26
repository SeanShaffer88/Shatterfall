class_name DataLoader
extends RefCounted
## Fail-loud loading for res://data/*.json (D22): malformed JSON, a wrong
## schema_version or an invalid field yields a precise "file: field: problem"
## error and no data. There are no silent defaults.

const SCHEMA_VERSION := 1


## Result: { ok: bool, data: Dictionary, error: String }.
static func parse(text: String, file_label: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		# JSON.get_error_line() is 0-based; report 1-based lines like an editor.
		return _err("%s: line %d: %s" % [file_label, json.get_error_line() + 1, json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _err("%s: top level must be a JSON object" % file_label)
	var data: Dictionary = json.data
	if not data.has("schema_version"):
		return _err("%s: schema_version: missing" % file_label)
	if typeof(data["schema_version"]) not in [TYPE_INT, TYPE_FLOAT] or int(data["schema_version"]) != SCHEMA_VERSION:
		return _err("%s: schema_version: expected %d, got %s" % [file_label, SCHEMA_VERSION, _fmt(data["schema_version"])])
	return {"ok": true, "data": data, "error": ""}


## Parses then validates. `validator` takes the data and returns Array[String] of field errors.
static func parse_and_validate(text: String, file_label: String, validator: Callable) -> Dictionary:
	var r := parse(text, file_label)
	if not r["ok"]:
		return r
	var errors: Array = validator.call(r["data"])
	if not errors.is_empty():
		var lines := PackedStringArray()
		for e in errors:
			lines.append("%s: %s" % [file_label, e])
		return _err("\n".join(lines))
	return r


static func load_file(path: String, validator: Callable) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _err("%s: file not found" % path)
	return parse_and_validate(FileAccess.get_file_as_string(path), path.get_file(), validator)


## JSON numbers are floats; print whole numbers without the ".0".
static func _fmt(v) -> String:
	if typeof(v) == TYPE_FLOAT and v == floorf(v):
		return str(int(v))
	return str(v)


static func _err(msg: String) -> Dictionary:
	return {"ok": false, "data": {}, "error": msg}
