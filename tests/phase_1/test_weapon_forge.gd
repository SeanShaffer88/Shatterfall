extends RefCounted
## Gate 1: absorption, sub-stats, power math, salvage and Build-Up
## (BLUEPRINT §2C; D5, D16, D17, D18, D25, D26, D31).

var forge: WeaponForge
var inv: Inventory


func before_each() -> void:
	forge = WeaponForge.new(GameState.weapons_data)
	inv = Inventory.new()
	for cls in forge.class_order():
		inv.set_main(inv.add_weapon(forge.create_weapon(cls)))


func _main(cls: String) -> Weapon:
	return inv.main_for(forge.class_cfg(cls)["owner_hero"], cls)


func _add(cls: String, rarity: int = 1, level: int = 1) -> Weapon:
	return inv.add_weapon(forge.create_weapon(cls, rarity, level))


func test_can_absorb_rejects_class_owner_and_uid(t: TestContext) -> void:
	var axe := _main("GREATAXE")
	t.ok(forge.can_absorb(axe, _add("GREATAXE")), "same class + owner absorbs")
	t.ok(not forge.can_absorb(axe, _add("STAFF")), "mismatched class rejected")
	var foreign := _add("GREATAXE")
	foreign.owner_hero = "ROGUE"
	t.ok(not forge.can_absorb(axe, foreign), "foreign-owner fodder rejected")
	t.ok(not forge.can_absorb(axe, axe), "same uid rejected")
	t.ok(not forge.can_absorb(axe, null), "null fodder rejected")


func test_absorb_refusals_leave_inventory_unchanged(t: TestContext) -> void:
	var axe := _main("GREATAXE")
	var staff := _add("STAFF")
	var fodder := _add("GREATAXE")
	var r := forge.absorb(inv, axe.uid, staff.uid)
	t.ok(not r["ok"], "off-class absorb refused")
	t.ok(inv.get_weapon(staff.uid) != null, "refused fodder is kept")
	t.ok(not forge.absorb(inv, axe.uid, axe.uid)["ok"], "absorbing a main into itself refused")
	t.ok(not forge.absorb(inv, fodder.uid, _add("GREATAXE").uid)["ok"], "non-main target refused")
	t.ok(not forge.absorb(inv, axe.uid, "w999999")["ok"], "unknown uid refused")
	t.eq(axe.xp, 0, "no XP after refusals")
	t.eq(axe.level, 1, "no level after refusals")


func test_xp_curve_matches_d31(t: TestContext) -> void:
	var curve := []
	for level in range(1, 10):
		curve.append(forge.xp_to_next(level))
	t.eq(curve, [40, 52, 68, 88, 114, 149, 193, 251, 326], "xp_to_next 1..9")
	var to_l5 := 0
	for v in curve.slice(0, 4):
		to_l5 += v
	var to_l10 := 0
	for v in curve:
		to_l10 += v
	t.eq(to_l5, 248, "XP to reach level 5")
	t.eq(to_l10, 1281, "XP to reach level 10")
	t.eq(forge.xp_to_next(10), 0, "no XP needed at the cap")


func test_absorb_grants_xp_substat_and_consumes_fodder(t: TestContext) -> void:
	var axe := _main("GREATAXE")
	var fodder := _add("GREATAXE", 1, 1)
	t.eq(forge.absorb_xp_value(fodder), 45, "base_xp 20 + level 1 × 25")
	var r := forge.absorb(inv, axe.uid, fodder.uid)
	t.ok(r["ok"], "absorb succeeds: %s" % r.get("error", ""))
	t.eq(r["xp_gained"], 45, "xp_gained")
	t.eq([axe.level, axe.xp, r["levels_gained"]], [2, 5, 1], "45 XP: level 1 -> 2 with 5 left")
	t.eq(r["substat"], "ATK", "first sub-stat in rotation")
	t.eq(axe.atk_stacks, 1, "+1 ATK stack")
	t.ok(inv.get_weapon(fodder.uid) == null, "fodder destroyed")


func test_absorb_multi_level_up(t: TestContext) -> void:
	var bow := _main("SHORTBOW")
	var fodder := _add("SHORTBOW", 3, 5)
	t.eq(forge.absorb_xp_value(fodder), 185, "base_xp 60 + level 5 × 25")
	var r := forge.absorb(inv, bow.uid, fodder.uid)
	t.eq([bow.level, bow.xp, r["levels_gained"], r["xp_discarded"]], [4, 25, 3, 0], "185 XP: 40+52+68 spent, 25 left")


func test_absorb_at_cap_discards_xp_but_grants_substat(t: TestContext) -> void:
	var staff := _main("STAFF")
	staff.level = 9
	staff.xp = 300
	var fodder := _add("STAFF")
	t.eq(forge.would_discard_xp(staff, fodder), 19, "warning value before absorbing")
	var r := forge.absorb(inv, staff.uid, fodder.uid)
	t.eq([staff.level, staff.xp, r["xp_discarded"]], [10, 0, 19], "345 XP: reach cap, discard 19")
	var r2 := forge.absorb(inv, staff.uid, _add("STAFF").uid)
	t.eq([r2["levels_gained"], r2["xp_discarded"], staff.xp], [0, 45, 0], "all XP discarded at the cap")
	t.eq(r2["substat"], "CRIT", "sub-stat still granted at the cap")


func test_substat_rotation_and_caps(t: TestContext) -> void:
	var axe := _main("GREATAXE")
	var got := []
	for i in 4:
		got.append(forge.absorb(inv, axe.uid, _add("GREATAXE").uid)["substat"])
	t.eq(got, ["ATK", "CRIT", "HP", "ATK"], "fixed ATK→CRIT→HP rotation (D16)")
	t.eq(axe.next_substat, 1, "rotation index persisted on the weapon")
	axe.atk_stacks = 20
	axe.crit_stacks = 20
	axe.hp_stacks = 19
	axe.next_substat = 0
	t.eq(forge.absorb(inv, axe.uid, _add("GREATAXE").uid)["substat"], "HP", "capped sub-stats are skipped")
	t.eq(forge.absorb(inv, axe.uid, _add("GREATAXE").uid)["substat"], "", "nothing granted when all are capped")
	t.eq([axe.atk_stacks, axe.crit_stacks, axe.hp_stacks], [20, 20, 20], "caps hold at 20")


func test_atk_math_d25(t: TestContext) -> void:
	var axe := _main("GREATAXE")
	t.near(forge.atk_eff(axe), 20.0, 1e-9, "level-1 base ATK")
	axe.level = 5
	t.near(forge.atk_eff(axe), 20.0 * pow(1.06, 4), 1e-9, "×1.06 per level")
	axe.evo_stage = 3
	t.near(forge.atk_eff(axe), 20.0 * pow(1.06, 4) * 1.44, 1e-9, "×1.20 per stage, multiplicative")
	axe.atk_stacks = 10
	t.near(forge.atk_eff(axe), 20.0 * pow(1.06, 4) * 1.44 * 1.10, 1e-9, "+1% per ATK stack")


func test_level1_damage_reproduces_blueprint(t: TestContext) -> void:
	var count := 0
	for hero in GameState.heroes_data["heroes"]:
		var h: Dictionary = GameState.heroes_data["heroes"][hero]
		var entries: Array = h["primary"].duplicate()
		for s in h["skills"]:
			entries.append_array(s["damage"])
		for e in entries:
			var w := forge.create_weapon(e["weapon_class"])
			t.eq(forge.damage(w, e["damage_l1"]), e["damage_l1"], "%s %s level-1 damage" % [hero, e.get("id", e["weapon_class"])])
			count += 1
	t.eq(count, 10, "all damage entries checked")


func test_damage_modifiers(t: TestContext) -> void:
	var axe := _main("GREATAXE")
	t.eq(forge.damage(axe, 22, 1.12), 25, "Crimson Surcharge ×1.12 → 24.64 rounds to 25")
	t.eq(forge.damage(axe, 22, 1.0, 1.25), 28, "Shatter Mark ×1.25 → 27.5 rounds to 28")
	t.eq(forge.damage(axe, 22, 1.0, 1.0, true), 44, "crit ×2")
	t.eq(forge.damage(axe, 0.001), 1, "minimum 1 damage")


func test_crit_chance_and_hp_bonus(t: TestContext) -> void:
	var w := _main("DAGGERS")
	t.near(forge.crit_chance(w), 0.15, 1e-9, "base crit 15%")
	w.crit_stacks = 5
	t.near(forge.crit_chance(w), 0.20, 1e-9, "+1% per CRIT stack")
	w.hp_stacks = 3
	t.eq(forge.hp_bonus(w), 6, "+2 HP per HP stack")


func test_salvage_yields_two_plus_rarity(t: TestContext) -> void:
	for rarity in [1, 2, 3]:
		var w := _add("GREATAXE", rarity)
		var r := forge.salvage(inv, w.uid)
		t.eq([r["shard_id"], r["shards"]], ["GREATAXE_SHARD", 2 + rarity], "rarity %d salvage" % rarity)
		t.ok(inv.get_weapon(w.uid) == null, "salvaged weapon destroyed")
	t.eq(inv.shard_count("GREATAXE_SHARD"), 12, "3 + 4 + 5 shards")
	var off := forge.salvage(inv, _add("STAFF").uid)
	t.eq(off["shard_id"], "STAFF_SHARD", "off-class salvage yields its own class shards")
	t.ok(not forge.salvage(inv, _main("GREATAXE").uid)["ok"], "an equipped main cannot be salvaged")


func test_build_up_fires_exactly_at_threshold(t: TestContext) -> void:
	var axe := _main("GREATAXE")
	axe.level = 4
	inv.add_shards("GREATAXE_SHARD", 15)
	t.ok(not forge.evolution_status(inv, axe)["level_ok"], "level 4 is below the Stage 2 requirement")
	t.ok(not forge.evolve(inv, axe.uid)["ok"], "level 4 + 15 shards cannot evolve")
	axe.level = 5
	inv.add_shards("GREATAXE_SHARD", -1)
	t.ok(not forge.evolve(inv, axe.uid)["ok"], "level 5 + 14 shards cannot evolve")
	inv.add_shards("GREATAXE_SHARD", 1)
	var before := forge.atk_eff(axe)
	var r := forge.evolve(inv, axe.uid)
	t.ok(r["ok"], "level 5 + 15 shards evolves: %s" % r.get("error", ""))
	t.eq([axe.evo_stage, axe.weapon_id, axe.level], [2, "cinderheart_maul", 5], "Stage 2, level kept (D26)")
	t.eq(inv.shard_count("GREATAXE_SHARD"), 0, "shard cost consumed")
	t.near(forge.atk_eff(axe), before * 1.2, 1e-9, "evolution grants ×1.20 ATK")


func test_stage3_requires_essence_and_is_final(t: TestContext) -> void:
	var staff := _main("STAFF")
	staff.level = 10
	staff.evo_stage = 2
	inv.add_shards("STAFF_SHARD", 40)
	var status := forge.evolution_status(inv, staff)
	t.eq([status["level_ok"], status["shards_ok"], status["essence_ok"]], [true, true, false], "essence missing")
	t.ok(not forge.evolve(inv, staff.uid)["ok"], "no Stage 3 without Vespera essence")
	inv.add_essence("VESPERA_ESSENCE", 1)
	var r := forge.evolve(inv, staff.uid)
	t.ok(r["ok"], "Stage 3 evolves with essence")
	t.eq([staff.evo_stage, staff.weapon_id], [3, "reliquary_nova_staff"], "Stage 3 weapon")
	t.eq([inv.shard_count("STAFF_SHARD"), inv.essence_count("VESPERA_ESSENCE")], [0, 0], "shards and essence consumed")
	t.ok(forge.next_evolution(staff).is_empty(), "no stage after 3")
	t.ok(forge.evolution_status(inv, staff)["final"], "status reports final")
	t.ok(not forge.evolve(inv, staff.uid)["ok"], "cannot evolve past Stage 3")


func test_only_mains_evolve(t: TestContext) -> void:
	var spare := _add("DAGGERS", 1, 5)
	inv.add_shards("DAGGERS_SHARD", 15)
	t.ok(not forge.evolve(inv, spare.uid)["ok"], "fodder cannot evolve")
	t.eq(inv.shard_count("DAGGERS_SHARD"), 15, "no shards spent on refusal")
