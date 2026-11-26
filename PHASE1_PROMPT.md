# Phase 1 Prompt — paste this into a new Claude Code session

Copy everything below the line into Claude Code (from the repo root) as the first build prompt. Later phase prompts should follow the same shape: name the phase, its scope, the gate, and the stop condition.

---

**Assignment: BLUEPRINT.md §3, Phase 1 only — Core Data, SaveManager & Weapon Forge Logic.**

Working from `AGENTS.md` rules and `BLUEPRINT.md` (read all of §0 first — D16–D31 and D38 define the sub-stat rotation and caps, the D25 damage formula and seeded RNG, `rarity`/`evo_stage` naming, slot model, drop math, forge economy, save slot, engine pin, package identity and test tooling):

1. Create the `autoload/` and `data/` skeleton exactly as specified in `BLUEPRINT.md` §3.2 (directory tree), populated with real GDScript and the §2 numeric tables — do not stub with invented values.
2. Implement:
   - `GameState.gd`: active hero, stage progress, stars per (stage, hero), grudge state per `BLUEPRINT.md` §2H / D11, and the seeded combat/loot/boon RNG streams (D25).
   - `SaveManager.gd`: atomic JSON write-then-rename, `schema_version: 1` on every file (D15), exactly one save slot `user://save.json` (D23), headless-friendly; all `data/*.json` loading **fails loud** with precise file/field errors on malformed input (D22).
   - `WeaponForge.gd`: same-class + hero-locked absorption (D5 and §2C rules: `can_absorb` must reject mismatched class, foreign owner, and same `uid`), absorb XP `base_xp(rarity) + level * 25` with multi-level-up and cap discard, XP curve `round(40 * 1.3^(level-1))`, sub-stat rotation with 20-stack caps (D16), salvage shards `2 + rarity`, Build-Up at level/shards/essence thresholds (consumes cost, keeps level), the D30 drop math, and the §2C evolution lines in `data/weapons.json`.
3. Write the test runner `res://tests/test_core_systems.gd` (extends `SceneTree`, runs `tests/phase_N/` suites, `quit(0)`/`quit(1)` — D38) and the Gate 1 suite covering: foreign-owner, mismatched-class and same-`uid` rejection; XP grant on matching absorb incl. multi-level-up and cap discard; D16 rotation and caps; D25 ATK/damage math reproducing the §2D level-1 numbers exactly; shard counts on salvage (`2 + rarity`); Build-Up firing exactly at threshold; D30 class weights incl. the ×1.25 grudge bias over a seeded sample; and a save round-trip preserving `schema_version`.
4. Run the gate (import first on a fresh clone — D38):
   ```bash
   godot --headless --path . --import
   godot --headless --path . -s res://tests/test_core_systems.gd
   ```
5. **Stop condition:** exit code `0` with real output shown, commit as `phase-1: data, SaveManager & WeaponForge, gate 1 green`. If the gate fails, do not touch the test to force a pass — commit as `phase-1: ..., gate 1 red — <failing assertion>`, report the exact output, and stop for my review. Do **not** begin Phase 2.
