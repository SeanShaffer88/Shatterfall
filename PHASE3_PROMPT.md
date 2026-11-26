# Phase 3 Prompt — paste this into a fresh Claude Code session

Prerequisite: Phase 2 complete with Gate 2 green (exit code `0`). If not true in this working copy, stop and reconcile with `main` first.

Copy everything below the line into Claude Code (from the repo root).

---

**Assignment: BLUEPRINT.md §3, Phase 3 only — 4-Room Dungeon Loop, Boon Draft & Boss Grudge.**

Working from `AGENTS.md` rules, `BLUEPRINT.md`, and the art hooks in `ART_DIRECTION.md`:

1. Build `scenes/rooms/Stage01_Nave.tscn`: 4 sequential locked rooms with gate triggers and spike traps, plus `scenes/main/DungeonRun.tscn` flow wiring. Waves, spawn rules and the spike-trap cycle exactly per §2E/D33; each room has an `EchoAnchor` `Marker3D` (needed in Phase 4); doors unlock **only** on last-wave clear. Run flow per D29: HP carries over, 15% heal per room clear, 0.4 s hit invulnerability, pause with Resume / Abandon Run, auto-pause on app background, drops saved at each room clear.
2. Enemy AI from `EnemyBase.tscn` per the §2E sheet: Crawler (2.0 m/s, 8 contact dmg max once per 1.0 s), Spitter (holds 5–8 m, 9 m/s projectile, 6 dmg every 1.8 s), Bulwark (±60° frontal 50% reduction, 1.8 m shield bash) — all telegraphed attacks use the shared crimson-white alarm language per AD7, rendered above decorative lighting.
3. Boon modal before Room 3: draft 1 of 3 from the §2F pool; three unique offers, no duplicates; effects per D14 (run-only, lost on death **and** after a win); apply stat effects via the same D16/D17 math as skills.
4. `scenes/actors/BossVespera.tscn` per the §2E boss sheet / D32: 1600 HP, immune to stun/pull/knockback, activation 1.5 s after the door locks, sweep and shard-rain timings, phase 2 at ≤ 800 HP (faster telegraphs, one-time 4 Crawlers, shard wall every 12 s).
5. Grudge Adaptation per §2H/D11: `GameState.get_last_clearing_hero("stage_01")` selects exactly one active adaptation (Spiked Carapace / Mirage Veil / Runic Dampening); a new clear **replaces** it; adaptation semantics exactly per §2H (incl. Mirage Veil restarting telegraphs with full warning); apply the D11/D30 **×1.25 class-weight bias** toward the other two heroes' classes.
6. Drops per D19/D30: 60% per cleared room, class weights 60/40 (Rogue 30/30), rarity 70/25/5, Vespera guarantees 1 level-2 weapon + 1 Vespera essence; write straight into the Phase 1 inventory model (Forge actions remain Hub-only, D20).
7. Stars per D7/D37/§2G: evaluate Cleave Master (Guard ≥ 50% of the fight) / Close Work (≥ 60 dagger hits) / Untouched Prism (zero HP loss in Room 2) **only on a cleared run with the matching hero**; persist in the Phase 1 star storage on victory. Remember D9: echo damage never feeds star conditions, and **this phase must not record or play echoes** (Phase 4).
8. Death and abandon handling per D10/D29: hero death or Abandon Run ends the run immediately with a summary screen (stars — victory only, drops kept, forge progress kept, boons lost); no mid-run checkpoints; echoes are not recorded on failed runs.
9. Extend the Gate tests (hand-rolled `SceneTree`, D22): doors unlock only on wave clear; each boon applies for the run only; Vespera clear installs exactly one adaptation keyed to the clearing hero and the drop bias flips correctly across two consecutive clears by different heroes; Mirage Veil restarts an active telegraph with full warning time; Vespera ignores stun/pull/knockback; room-clear heal and HP carry-over; star conditions are verifiable in headless simulation (simulate the §2G conditions deterministically); death and abandon end the run with the D10/D29 keep/lose split; drops persist at room clear; D30 room-drop rolls honor the 60% chance and weights over a seeded sample.
10. Run the gate:
    ```bash
    godot --headless --path . -s res://tests/test_core_systems.gd
    ```
11. **Stop condition:** exit code `0` with real output shown, commit as `phase-3: dungeon loop, boon draft & boss grudge, gate 3 green`. On failure: commit as `phase-3: ..., gate 3 red — <failing assertion>`, report exact output, log ambiguities in `QUESTIONS.md`, stop. Do **not** begin Phase 4 — no echo capture or playback in this phase.

Scope guard: do not touch `EchoDirector.gd`, `SpectralEcho.tscn`, or `MainHub.tscn` beyond what §2G star persistence requires through `GameState.gd`.
