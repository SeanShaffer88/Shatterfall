extends RefCounted
## Gate 1: drop math (D19, D30), the Grudge class bias (D11) and seeded RNG (D25).

const STAGE := "stage_01_sunken_nave"

var loot: LootTable


func before_each() -> void:
	loot = GameState.loot_table(STAGE)


func _check_weights(t: TestContext, got: Dictionary, want: Dictionary, label: String) -> void:
	for cls in want:
		t.near(got[cls], want[cls], 1e-9, "%s: %s weight" % [label, cls])
	var total := 0.0
	for cls in got:
		total += got[cls]
	t.near(total, 1.0, 1e-9, "%s: weights sum to 1" % label)


func test_class_weights_without_grudge(t: TestContext) -> void:
	_check_weights(t, loot.class_weights("BRUTE", ""),
		{"GREATAXE": 0.6, "DAGGERS": 0.4 / 3, "SHORTBOW": 0.4 / 3, "STAFF": 0.4 / 3}, "Brute run")
	_check_weights(t, loot.class_weights("ROGUE", ""),
		{"DAGGERS": 0.3, "SHORTBOW": 0.3, "GREATAXE": 0.2, "STAFF": 0.2}, "Rogue run (60 split 30/30)")


func test_grudge_bias_multiplies_then_renormalizes(t: TestContext) -> void:
	# Rogue run after a Brute clear: 30×1.25, 30×1.25, 20, 20×1.25 → total 120.
	_check_weights(t, loot.class_weights("ROGUE", "BRUTE"),
		{"DAGGERS": 37.5 / 120, "SHORTBOW": 37.5 / 120, "GREATAXE": 20.0 / 120, "STAFF": 25.0 / 120}, "Rogue run, Brute grudge")
	# Same hero as the last clearer: only the other heroes' classes are boosted.
	_check_weights(t, loot.class_weights("BRUTE", "BRUTE"),
		{"GREATAXE": 60.0 / 110, "DAGGERS": (40.0 / 3 * 1.25) / 110, "SHORTBOW": (40.0 / 3 * 1.25) / 110, "STAFF": (40.0 / 3 * 1.25) / 110}, "Brute run, Brute grudge")


func test_bias_flips_across_consecutive_clears(t: TestContext) -> void:
	var after_brute := loot.class_weights("ROGUE", "BRUTE")
	var after_magi := loot.class_weights("ROGUE", "MAGI")
	t.ok(after_brute["GREATAXE"] < after_brute["STAFF"], "after a Brute clear the Greataxe is not boosted")
	t.ok(after_magi["STAFF"] < after_magi["GREATAXE"], "after a Magi clear the Staff is not boosted")


func test_seeded_sample_matches_weights(t: TestContext) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var n := 20000
	var drops := 0
	var by_class := {}
	var by_rarity := [0, 0, 0]
	for i in n:
		var d := loot.roll_room_drop(rng, "ROGUE", "BRUTE")
		if d.is_empty():
			continue
		drops += 1
		by_class[d["weapon_class"]] = by_class.get(d["weapon_class"], 0) + 1
		by_rarity[d["rarity"] - 1] += 1
		if d["level"] != 1:
			t.ok(false, "room drops are level 1, got %d" % d["level"])
	t.near(float(drops) / n, 0.6, 0.015, "room drop chance 60%")
	var want := loot.class_weights("ROGUE", "BRUTE")
	for cls in want:
		t.near(float(by_class.get(cls, 0)) / drops, want[cls], 0.015, "%s frequency" % cls)
	for i in 3:
		t.near(float(by_rarity[i]) / drops, [0.70, 0.25, 0.05][i], 0.015, "rarity %d frequency" % (i + 1))


func test_same_seed_same_rolls(t: TestContext) -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 777
	b.seed = 777
	var seq_a := []
	var seq_b := []
	for i in 50:
		seq_a.append(loot.roll_room_drop(a, "MAGI", "ROGUE"))
		seq_b.append(loot.roll_room_drop(b, "MAGI", "ROGUE"))
	t.eq(seq_a, seq_b, "identical seeds give identical drop sequences")


func test_boss_drop_is_guaranteed(t: TestContext) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 200:
		var d := loot.roll_boss_drop(rng, "BRUTE", "")
		if d["weapon"].is_empty() or d["weapon"]["level"] != 2 or d["essence_id"] != "VESPERA_ESSENCE":
			t.ok(false, "boss drop %d: %s" % [i, str(d)])
			return
	t.ok(true, "200 boss drops each had a level-2 weapon and a Vespera essence")


func test_run_seed_drives_independent_streams(t: TestContext) -> void:
	GameState.begin_run("ROGUE", 99)
	var loot_a := [GameState.rng_loot.randi(), GameState.rng_loot.randi()]
	var combat_a := GameState.rng_combat.randi()
	GameState.begin_run("ROGUE", 99)
	t.eq([GameState.rng_loot.randi(), GameState.rng_loot.randi()], loot_a, "same run seed replays loot rolls")
	t.eq(GameState.rng_combat.randi(), combat_a, "same run seed replays combat rolls")
	t.ok(loot_a[0] != combat_a, "loot and combat streams differ")
	t.eq(GameState.active_hero, "ROGUE", "begin_run sets the active hero")
	GameState.active_hero = ""
