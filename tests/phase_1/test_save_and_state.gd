extends RefCounted
## Gate 1: atomic saves (D15, D23), profile round-trip, Grudge replacement (D11),
## stars (D7), Forge unlock (D13), max HP (D16) and project identity (D1, D2, D24).

const STAGE := "stage_01_sunken_nave"
const TMP_DIR := "user://test_tmp"


func before_each() -> void:
	_clean()
	SaveManager.save_path = TMP_DIR + "/save.json"
	GameState.reset_profile()


func after_each() -> void:
	_clean()
	SaveManager.save_path = SaveManager.DEFAULT_SAVE_PATH
	GameState.reset_profile()


func _clean() -> void:
	if not DirAccess.dir_exists_absolute(TMP_DIR):
		return
	for f in DirAccess.get_files_at(TMP_DIR):
		DirAccess.remove_absolute("%s/%s" % [TMP_DIR, f])


func _write_raw(text: String) -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var f := FileAccess.open(SaveManager.save_path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _canonical(d: Dictionary) -> String:
	return JSON.stringify(d, "", true)


func test_atomic_write_stamps_schema_version(t: TestContext) -> void:
	var path := TMP_DIR + "/a.json"
	t.eq(SaveManager.write_json_atomic(path, {"a": 1}), OK, "write succeeds")
	var r := SaveManager.read_json(path)
	t.ok(r["ok"], "file reads back: %s" % r["error"])
	t.eq(r["data"]["schema_version"], 1, "schema_version stamped (D15)")
	t.eq(r["data"]["a"], 1, "payload preserved")
	t.ok(not FileAccess.file_exists(path + ".tmp"), "no temp file left behind")


func test_atomic_write_replaces_existing_file(t: TestContext) -> void:
	var path := TMP_DIR + "/b.json"
	SaveManager.write_json_atomic(path, {"v": "first"})
	t.eq(SaveManager.write_json_atomic(path, {"v": "second"}), OK, "second write succeeds")
	t.eq(SaveManager.read_json(path)["data"]["v"], "second", "rename replaced the old file")


func test_profile_round_trip(t: TestContext) -> void:
	var gs := GameState
	var axe := gs.inventory.main_for("BRUTE", "GREATAXE")
	var fodder := gs.grant_drop({"weapon_class": "GREATAXE", "rarity": 2, "level": 1})
	gs.forge.absorb(gs.inventory, axe.uid, fodder.uid)
	gs.grant_drop({"weapon_class": "STAFF", "rarity": 3, "level": 2})
	gs.inventory.add_shards("DAGGERS_SHARD", 7)
	gs.inventory.add_essence("VESPERA_ESSENCE", 1)
	gs.record_victory(STAGE, "MAGI", true)
	var before := _canonical(gs.to_save_dict())
	t.eq(SaveManager.save_profile(), OK, "save_profile succeeds")
	gs.reset_profile()
	t.ok(_canonical(gs.to_save_dict()) != before, "reset actually cleared state")
	t.eq(SaveManager.load_profile(), "", "load_profile succeeds")
	t.eq(_canonical(gs.to_save_dict()), before, "profile identical after round-trip")
	t.eq(gs.inventory.main_for("BRUTE", "GREATAXE").level, 2, "absorbed level survives")
	t.eq(SaveManager.read_json(SaveManager.save_path)["data"]["schema_version"], 1, "save carries schema_version (D15)")


func test_no_save_means_fresh_start(t: TestContext) -> void:
	t.ok(not SaveManager.has_save(), "no save file in the test slot")
	t.eq(SaveManager.load_profile(), "", "missing save is not an error")
	t.eq(GameState.star_count(STAGE), 0, "fresh profile")


func test_corrupt_save_is_quarantined(t: TestContext) -> void:
	t.expect_errors(1)
	GameState.record_victory(STAGE, "BRUTE", true)
	_write_raw("{ this is not json")
	var err := SaveManager.load_profile()
	t.contains(err, "save.json: line 1: ", "parse error names file and line")
	t.ok(FileAccess.file_exists(TMP_DIR + "/save.corrupt.json"), "corrupt save moved aside")
	t.ok(not SaveManager.has_save(), "slot is empty after quarantine")
	t.eq(GameState.star_count(STAGE), 0, "profile reset to fresh")


func test_wrong_schema_version_save_rejected(t: TestContext) -> void:
	t.expect_errors(1)
	_write_raw('{"schema_version": 2, "profile": {}, "inventory": {}}')
	var err := SaveManager.load_profile()
	t.contains(err, "schema_version: expected 1, got 2", "future schema rejected")
	t.ok(not err.contains("2.0"), "whole numbers print without .0: %s" % err)


func test_save_with_dangling_main_rejected(t: TestContext) -> void:
	t.expect_errors(1)
	var d := GameState.to_save_dict()
	d["inventory"]["mains"]["BRUTE"]["GREATAXE"] = "w999999"
	SaveManager.write_json_atomic(SaveManager.save_path, d)
	t.contains(SaveManager.load_profile(), "inventory.mains.BRUTE.GREATAXE: unknown weapon uid 'w999999'", "precise inventory error")


func test_starter_profile(t: TestContext) -> void:
	var inv := GameState.inventory
	t.eq(inv.weapons.size(), 4, "one starter main per weapon class")
	for cls in GameState.forge.class_order():
		var owner: String = GameState.forge.class_cfg(cls)["owner_hero"]
		var w := inv.main_for(owner, cls)
		t.ok(w != null, "%s main exists" % cls)
		if w != null:
			t.eq([w.level, w.rarity, w.evo_stage, w.owner_hero], [1, 1, 1, owner], "%s starter state" % cls)
	t.eq(inv.mains_of("ROGUE").size(), 2, "Rogue equips two mains (D18)")
	t.ok(not GameState.forge_unlocked, "Forge locked before the first boss kill (D13)")


func test_grudge_is_replaced_never_stacked(t: TestContext) -> void:
	t.eq(GameState.get_last_clearing_hero(STAGE), "", "no grudge before the first clear")
	t.eq(GameState.active_adaptation(STAGE), {}, "no adaptation before the first clear")
	GameState.record_victory(STAGE, "BRUTE", false)
	t.eq(GameState.active_adaptation(STAGE)["id"], "SPIKED_CARAPACE", "Brute clear installs Spiked Carapace")
	GameState.record_victory(STAGE, "MAGI", false)
	t.eq(GameState.get_last_clearing_hero(STAGE), "MAGI", "latest clearer wins")
	t.eq(GameState.active_adaptation(STAGE)["id"], "RUNIC_DAMPENING", "Magi clear replaces it")
	t.eq(GameState.last_clearing_hero.size(), 1, "exactly one adaptation per boss")


func test_stars_only_on_condition_and_persist(t: TestContext) -> void:
	GameState.record_victory(STAGE, "ROGUE", false)
	t.ok(not GameState.has_star(STAGE, "ROGUE"), "no star when the condition failed")
	t.ok(GameState.forge_unlocked, "first boss kill unlocks the Forge (D13)")
	GameState.record_victory(STAGE, "ROGUE", true)
	GameState.record_victory(STAGE, "ROGUE", false)
	t.ok(GameState.has_star(STAGE, "ROGUE"), "a star persists after later failed attempts")
	t.ok(not GameState.has_star(STAGE, "BRUTE"), "stars are per hero (D7)")
	t.eq([GameState.star_count(STAGE), GameState.clear_count(STAGE, "ROGUE")], [1, 3], "one star, three clears")


func test_hero_max_hp_includes_hp_stacks(t: TestContext) -> void:
	t.eq(GameState.hero_max_hp("ROGUE"), 100, "base Rogue HP")
	GameState.inventory.main_for("ROGUE", "DAGGERS").hp_stacks = 2
	GameState.inventory.main_for("ROGUE", "SHORTBOW").hp_stacks = 1
	t.eq(GameState.hero_max_hp("ROGUE"), 106, "+2 HP per stack across both mains")


func test_project_identity_and_display(t: TestContext) -> void:
	t.eq(ProjectSettings.get_setting("application/config/name"), "Shatterfall", "display name (D24)")
	t.eq(ProjectSettings.get_setting("application/config/version"), "0.1.0", "version (D24)")
	t.eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"), "mobile", "Mobile renderer (D2)")
	t.eq(ProjectSettings.get_setting("display/window/size/viewport_width"), 2400, "base width (D1)")
	t.eq(ProjectSettings.get_setting("display/window/size/viewport_height"), 1080, "base height (D1)")
	t.eq(ProjectSettings.get_setting("display/window/stretch/mode"), "canvas_items", "stretch mode (D1)")
	t.eq(ProjectSettings.get_setting("display/window/stretch/aspect"), "expand", "stretch aspect (D1)")
	t.eq(ProjectSettings.get_setting("display/window/handheld/orientation"), 4, "sensor landscape (D40)")
