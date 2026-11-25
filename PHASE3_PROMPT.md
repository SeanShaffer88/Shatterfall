# Phase 3 Prompt — paste this into a fresh Claude Code session

Prerequisite: Phase 2 complete with Gate 2 green (exit code `0`). If not true in this working copy, stop and reconcile with `main` first.

Copy everything below the line into Claude Code (from the repo root).

---

**Assignment: BLUEPRINT.md §3, Phase 3 only — 4-Room Dungeon Loop, Boon Draft & Boss Grudge.**

Working from `AGENTS.md` rules, `BLUEPRINT.md`, and the art hooks in `ART_DIRECTION.md`:

1. Build `scenes/rooms/Stage01_Nave.tscn`: 4 sequential locked rooms with gate triggers and spike traps, plus `scenes/main/DungeonRun.tscn` flow wiring. Waves exactly per §2E (Room 1: 1 wave; Room 2: 2 waves; Room 3: 2 waves + traps; Room 4: 3 waves); doors unlock **only** on wave clear.
2. Enemy AI from `EnemyBase.tscn`: Crawler (melee chase 2.0 m/s, 8 contact dmg), Spitter (8 m, 6 dmg projectile every 1.8 s), Bulwark (50% frontal reduction) — all telegraphed attacks use the shared crimson-white alarm language per AD7, rendered above decorative lighting.
3. Boon modal before Room 3: draft 1 of 3 from the §2F pool; three unique offers, no duplicates; effects per D14 (run-only, lost on death **and** after a win); apply stat effects via the same D16/D17 math as skills.
4. `scenes/actors/BossVespera.tscn`: 600 HP, 2 phases (phase 2 at 50%: faster telegraphs, one-time spawn of 4 Crawlers, shard wall); attacks per §2E.
5. Grudge Adaptation per §2H/D11: `GameState.get_last_clearing_hero("stage_01")` selects exactly one active adaptation (Spiked Carapace / Mirage Veil / Runic Dampening); a new clear **replaces** it; apply the D19 **+25% drop bias** toward the other two heroes' classes.
6. Drops per D19: 40% per cleared room, class weighted 60% toward the current hero, Vespera guarantees 1 weapon + 1 Vespera essence; write straight into the Phase 1 inventory model (Forge actions remain Hub-only, D20).
7. Stars per D7/§2G: evaluate Cleave Master / Close Work / Untouched Prism **only on a cleared run with the matching hero**; persist in the Phase 1 star storage on victory. Remember D9: echo damage never feeds star conditions, and **this phase must not record or play echoes** (Phase 4).
8. Death handling per D10: hero death ends the run immediately with a summary screen (stars — victory only, drops kept, forge progress kept, boons lost); no mid-run checkpoints; echoes are not recorded on failed runs.
9. Extend the Gate tests (hand-rolled `SceneTree`, D22): doors unlock only on wave clear; each boon applies for the run only; Vespera clear installs exactly one adaptation keyed to the clearing hero and the drop bias flips correctly across two consecutive clears by different heroes; star conditions are verifiable in headless simulation (simulate the §2G conditions deterministically); death ends the run with the D10 keep/lose split; D19 room-drop rolls honor the 40%/60-40 weighting over a seeded sample.
10. Run the gate:
    ```bash
    godot --headless --path . -s res://tests/test_core_systems.gd
    ```
11. **Stop condition:** exit code `0` with real output shown, commit as `phase-3: dungeon loop, boon draft & boss grudge, gate 3 green`. On failure: commit as `phase-3: ..., gate 3 red — <failing assertion>`, report exact output, log ambiguities in `QUESTIONS.md`, stop. Do **not** begin Phase 4 — no echo capture or playback in this phase.

Scope guard: do not touch `EchoDirector.gd`, `SpectralEcho.tscn`, or `MainHub.tscn` beyond what §2G star persistence requires through `GameState.gd`.
