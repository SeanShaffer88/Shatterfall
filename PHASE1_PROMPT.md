# Phase 1 Prompt — paste this into a new Claude Code session

Copy everything below the line into Claude Code (from the repo root) as the first build prompt. Later phase prompts should follow the same shape: name the phase, its scope, the gate, and the stop condition.

---

**Assignment: BLUEPRINT.md §3, Phase 1 only — Core Data, SaveManager & Weapon Forge Logic.**

Working from `AGENTS.md` rules and `BLUEPRINT.md` (note: decisions D16–D24 in §0 are new — read them before starting; they define the sub-stat rotation, ATK/tier math, slot model, drop rates, save slot, engine pin, and package identity):

1. Create the `autoload/` and `data/` skeleton exactly as specified in `BLUEPRINT.md` §3.2 (directory tree), populated with real GDScript and the §2 numeric tables — do not stub with invented values.
2. Implement:
   - `GameState.gd`: active hero, stage progress, stars per (stage, hero), grudge state per `BLUEPRINT.md` §2H / D11.
   - `SaveManager.gd`: atomic JSON write-then-rename, `schema_version: 1` on every file (D15), exactly one save slot `user://save.json` (D23), headless-friendly; all `data/*.json` loading **fails loud** with precise file/field errors on malformed input (D22).
   - `WeaponForge.gd`: same-class + hero-locked absorption (D5 and §2C rules: `can_absorb` must reject mismatched class, foreign owner, and same `uid`), absorb XP formula `fodder.base_xp + level * 25`, XP curve `round(50 * 1.5^(level-1))`, salvage shards `2 + tier`, Build-Up trigger at level/shards/essence thresholds, and the §2C evolution trees in `data/weapons.json`.
3. Write the Gate 1 headless test (a hand-rolled `SceneTree` script, no plugins — D22; `res://tests/test_core_systems.gd`) covering: foreign-owner and mismatched-class rejection; XP grant on matching absorb with the D16 sub-stat rotation (+ATK/+CRIT/+HP; no +ELEMENT); D17 ATK math (class base × 1.06^(level−1), +20% on evolution); correct shard counts on salvage (`2 + tier`); Build-Up evolution firing exactly at threshold; D19 drop-table weights; and a save-file serialization round-trip preserving `schema_version`.
4. Run the gate:
   ```bash
   godot --headless --path . -s res://tests/test_core_systems.gd
   ```
5. **Stop condition:** exit code `0` with real output shown, commit as `phase-1: data, SaveManager & WeaponForge, gate 1 green`. If the gate fails, do not touch the test to force a pass — commit as `phase-1: ..., gate 1 red — <failing assertion>`, report the exact output, and stop for my review. Do **not** begin Phase 2.
