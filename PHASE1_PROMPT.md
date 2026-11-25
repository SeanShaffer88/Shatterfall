# Phase 1 Prompt — paste this into a new Claude Code session

Copy everything below the line into Claude Code (from the repo root) as the first build prompt. Later phase prompts should follow the same shape: name the phase, its scope, the gate, and the stop condition.

---

**Assignment: BLUEPRINT.md §3, Phase 1 only — Core Data, SaveManager & Weapon Forge Logic.**

Working from `AGENTS.md` rules and `BLUEPRINT.md`:

1. Create the `autoload/` and `data/` skeleton exactly as specified in `BLUEPRINT.md` §3.2 (directory tree), populated with real GDScript and the §2 numeric tables — do not stub with invented values.
2. Implement:
   - `GameState.gd`: active hero, stage progress, stars per (stage, hero), grudge state per `BLUEPRINT.md` §2H / D11.
   - `SaveManager.gd`: atomic JSON write-then-rename, `schema_version: 1` on every file (D15), headless-friendly.
   - `WeaponForge.gd`: same-class + hero-locked absorption (D5 and §2C rules: `can_absorb` must reject mismatched class, foreign owner, and same `uid`), absorb XP formula `fodder.base_xp + level * 25`, XP curve `round(50 * 1.5^(level-1))`, salvage shards `2 + tier`, Build-Up trigger at level/shards/essence thresholds, and the §2C evolution trees in `data/weapons.json`.
3. Write the Gate 1 headless test (`res://tests/test_core_systems.gd`) covering: foreign-owner and mismatched-class rejection, XP grant on matching absorb, correct shard counts on salvage, evolution firing exactly at threshold, and a save-file serialization round-trip preserving `schema_version`.
4. Run the gate:
   ```bash
   godot --headless --path . -s res://tests/test_core_systems.gd
   ```
5. **Stop condition:** exit code `0` with real output shown, commit as `phase-1: data, SaveManager & WeaponForge, gate 1 green`. If the gate fails, do not touch the test to force a pass — commit as `phase-1: ..., gate 1 red — <failing assertion>`, report the exact output, and stop for my review. Do **not** begin Phase 2.
