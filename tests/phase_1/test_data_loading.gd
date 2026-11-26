extends RefCounted
## Gate 1: fail-loud data loading (D22) and the §2 numbers in data/*.json.


func _raw(file_name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/" + file_name))


func test_all_data_files_load_and_validate(t: TestContext) -> void:
	t.eq(GameState.load_data(), "", "load_data() error")
	t.eq(DataSchema.validate_heroes(_raw("heroes.json")), [], "heroes.json validation errors")
	t.eq(DataSchema.validate_weapons(_raw("weapons.json")), [], "weapons.json validation errors")
	t.eq(DataSchema.validate_stages(_raw("stages.json")), [], "stages.json validation errors")


func test_malformed_json_reports_file_and_line(t: TestContext) -> void:
	var r := DataLoader.parse('{\n  "schema_version": 1,\n  "x": [1, 2,\n}', "weapons.json")
	t.ok(not r["ok"], "malformed JSON must fail")
	t.contains(r["error"], "weapons.json: line 4: ", "error names the file and the 1-based line")
	t.contains(DataLoader.parse("{ bad", "x.json")["error"], "x.json: line 1: ", "first-line errors report line 1")
	t.eq(r["data"], {}, "no partial data on failure")


func test_schema_version_mismatch_rejected(t: TestContext) -> void:
	var r := DataLoader.parse('{"schema_version": 2}', "stages.json")
	t.ok(not r["ok"], "schema_version 2 must fail")
	t.eq(r["error"], "stages.json: schema_version: expected 1, got 2", "precise schema error")
	var missing := DataLoader.parse('{"a": 1}', "stages.json")
	t.contains(missing["error"], "stages.json: schema_version: missing", "missing schema_version")


func test_missing_field_reports_precise_path(t: TestContext) -> void:
	var d := _raw("weapons.json")
	d["classes"]["DAGGERS"].erase("base_atk")
	var errs := DataSchema.validate_weapons(d)
	t.ok("classes.DAGGERS.base_atk: missing" in errs, "missing base_atk reported, got %s" % str(errs))


func test_wrong_type_and_value_rejected(t: TestContext) -> void:
	var d := _raw("heroes.json")
	d["heroes"]["BRUTE"]["hp"] = "lots"
	d["heroes"]["ROGUE"]["skills"][1]["lock_state"] = "FLYING"
	d["heroes"]["MAGI"]["primary"][0]["weapon_class"] = "GREATAXE"
	var errs := DataSchema.validate_heroes(d)
	t.ok("heroes.BRUTE.hp: expected number, got String" in errs, "type error, got %s" % str(errs))
	var joined := "\n".join(PackedStringArray(errs))
	t.contains(joined, "heroes.ROGUE.skills[1].lock_state: 'FLYING' is not one of", "enum error")
	t.contains(joined, "heroes.MAGI.primary[0].weapon_class: 'GREATAXE' is not one of", "off-hero weapon class")


func test_unknown_enemy_and_bad_ranges_rejected(t: TestContext) -> void:
	var d := _raw("stages.json")
	var stage: Dictionary = d["stages"]["stage_01_sunken_nave"]
	stage["rooms"][0]["waves"][0][0]["enemy"] = "DRAGON"
	stage["drops"]["room_drop_chance"] = 1.5
	var joined := "\n".join(PackedStringArray(DataSchema.validate_stages(d)))
	t.contains(joined, "stages.stage_01_sunken_nave.rooms[0].waves[0][0].enemy: 'DRAGON' is not one of", "unknown enemy")
	t.contains(joined, "stages.stage_01_sunken_nave.drops.room_drop_chance: 1.5 is outside [0.0, 1.0]", "range error")


func test_load_file_fails_loud(t: TestContext) -> void:
	var missing := DataLoader.load_file("res://data/nope.json", DataSchema.validate_weapons)
	t.ok(not missing["ok"], "missing file fails")
	t.contains(missing["error"], "res://data/nope.json: file not found", "missing file named")
	var bad := DataLoader.parse_and_validate('{"schema_version": 1, "class_order": []}', "weapons.json", DataSchema.validate_weapons)
	t.ok(not bad["ok"], "invalid data fails")
	t.contains(bad["error"], "weapons.json: class_order: expected at least 1 entries", "errors are prefixed with the file")
	t.eq(bad["data"], {}, "no partial data on validation failure")


func test_weapon_numbers_match_blueprint(t: TestContext) -> void:
	var w := GameState.weapons_data
	var expected := {"GREATAXE": [20, "BRUTE"], "DAGGERS": [6, "ROGUE"], "SHORTBOW": [11, "ROGUE"], "STAFF": [14, "MAGI"]}
	for cls in expected:
		t.eq(w["classes"][cls]["base_atk"], expected[cls][0], "%s base ATK (D17)" % cls)
		t.eq(w["classes"][cls]["owner_hero"], expected[cls][1], "%s owner (D5)" % cls)
		var line: Array = w["evolutions"][cls]
		t.eq([line[1]["req_level"], line[1]["shard_cost"], line[1]["boss_essence_id"]], [5, 15, ""], "%s Stage 2 recipe (D31)" % cls)
		t.eq([line[2]["req_level"], line[2]["shard_cost"], line[2]["boss_essence_id"]], [10, 40, "VESPERA_ESSENCE"], "%s Stage 3 recipe (D31)" % cls)
	t.eq(w["evolutions"]["GREATAXE"][1]["name"], "Cinderheart Maul", "evolution names (§2C)")
	t.eq(w["evolutions"]["STAFF"][2]["name"], "Reliquary Nova Staff", "evolution names (§2C)")
	t.eq(w["growth"]["substat_order"], ["ATK", "CRIT", "HP"], "sub-stat rotation (D16)")


func test_hero_numbers_match_blueprint(t: TestContext) -> void:
	var h: Dictionary = GameState.heroes_data["heroes"]
	t.eq([h["BRUTE"]["hp"], h["ROGUE"]["hp"], h["MAGI"]["hp"]], [140, 100, 110], "hero HP (§2D)")
	var cooldowns := {"BRUTE": [8, 12, 15], "ROGUE": [7, 10, 14], "MAGI": [6, 12, 16]}
	var recorded := {"BRUTE": [true, true, true], "ROGUE": [false, true, true], "MAGI": [false, true, true]}
	for hero in cooldowns:
		var cds := []
		var rec := []
		for s in h[hero]["skills"]:
			cds.append(s["cooldown"])
			rec.append(s["recorded"])
		t.eq(cds, cooldowns[hero], "%s cooldowns (§2D)" % hero)
		t.eq(rec, recorded[hero], "%s recorded skills (D34)" % hero)
	t.eq(h["ROGUE"]["primary"][0]["cadence"], 0.5, "dagger cadence (D28)")
	t.eq(h["ROGUE"]["primary"][0]["reach"], 3.0, "dagger reach (D28)")
	t.eq(h["ROGUE"]["skills"][0]["lock_state"], "DASHING", "Shadow Vault lock (D27)")
	t.eq(h["MAGI"]["skills"][0]["lock_state"], "INSTANT", "Phase Blink lock (D27)")


func test_stage_numbers_match_blueprint(t: TestContext) -> void:
	var s := GameState.stage_cfg("stage_01_sunken_nave")
	var wave_counts := []
	var enemy_total := 0
	for room in s["rooms"]:
		wave_counts.append(room["waves"].size())
		for wave in room["waves"]:
			for group in wave:
				enemy_total += int(group["count"])
	t.eq(wave_counts, [1, 2, 2, 3], "waves per room (§2E)")
	t.eq(enemy_total, 33, "total room enemies (§2E)")
	t.eq(s["rooms"][2]["traps"].size(), 4, "Room 3 spike traps (D33)")
	t.eq(s["boss"]["hp"], 1600, "Vespera HP (D32)")
	t.eq(s["boss"]["immune"], ["STUN", "PULL", "KNOCKBACK"], "Vespera immunities (D32)")
	t.eq(s["drops"]["room_drop_chance"], 0.6, "room drop chance (D19)")
	t.eq(s["drops"]["rarity_weights"], [70, 25, 5], "rarity roll (D30)")
	t.eq([s["stars"]["BRUTE"]["threshold"], s["stars"]["ROGUE"]["threshold"], s["stars"]["MAGI"]["threshold"]], [0.5, 60, 0], "star thresholds (D37)")
	t.eq([s["grudge"]["BRUTE"]["id"], s["grudge"]["ROGUE"]["id"], s["grudge"]["MAGI"]["id"]], ["SPIKED_CARAPACE", "MIRAGE_VEIL", "RUNIC_DAMPENING"], "adaptations (§2H)")
	t.eq(GameState.stages_data["boons"].size(), 6, "boon pool (§2F)")
	t.eq(s["room_clear_heal"], 0.15, "room clear heal (D29)")
