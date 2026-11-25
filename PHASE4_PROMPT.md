# Phase 4 Prompt — paste this into a fresh Claude Code session

Prerequisite: Phase 3 complete with Gate 3 green (exit code `0`). If not true in this working copy, stop and reconcile with `main` first.

Copy everything below the line into Claude Code (from the repo root).

---

**Assignment: BLUEPRINT.md §3, Phase 4 only — Spectral Echo Recording & Playback.**

Working from `AGENTS.md` rules, `BLUEPRINT.md` §2B, and `ART_DIRECTION.md` AD6:

1. Implement `autoload/EchoDirector.gd` recording: capture every **manual skill cast** (never auto-attacks) as a keyframe — room index, room-relative time, hero position, skill id, target point. Cap at the **12 most recent events** per run (D12). Persist **only on stage victory**, one file per `(stage, hero)` under `user://echoes/`, overwriting the previous clear (D10/D12). Never record on failed runs.
2. Schema per §2B: `schema_version: 1`, `stage_id`, per-hero `echoes` with `weapon_id` (**recorded but non-authoritative**, D21) and the `events` array; hand-rolled atomic JSON persistence through `SaveManager.gd` (D15/D23).
3. Playback: entering Room `R` as hero X, load the saved echoes of the **other two** heroes. At `room_elapsed_time >= event.time`, spawn `scenes/actors/SpectralEcho.tscn` — translucent stained-glass Fresnel shader in **cold cyan only** (AD6: echo VFX overrides any inherited warm weapon palette), smart snap to the nearest **living** enemy within **3.5 m** of the recorded target point, **silently skip the event** if no living enemy exists in the room. Execute the skill hitbox at **65% base potency**, resolving the recording hero's **current** weapon state at playback time (D21 — evolutions retroactively strengthen old echoes).
4. Echoes fire in the boss room too. Echo damage/kills help clear waves but **never** feed the §2G star conditions (D9) — the star trackers must be provably isolated from echo damage events.
5. Hit-stop interaction (§2B caveat): if `Engine.time_scale` micro-dips exist at this stage or later, they must not shift echo or room-elapsed timers; gate tests must cover echo timers under a simulated time-scale dip.
6. Extend the Gate tests (hand-rolled `SceneTree`, D22):
   - The canonical case: a recorded Brute run spawns a **functional** Leap Slam echo in a subsequent Rogue run at the exact room and time window (seed the run deterministically).
   - Snap behavior: echo aims at the nearest living enemy within 3.5 m; event is skipped when the room is empty at fire time.
   - Star isolation: echo kills do not move §2G counters.
   - 65% potency is applied (and D21 inheritance: an evolved `weapon_id` on the recording hero changes echo output).
   - Cap and overwrite: >12 casts keep the 12 most recent; a new victory overwrites the prior `(stage, hero)` record; serialization round-trip preserves `schema_version`.
   - AD6: echo palette is cyan even when inheriting a warm weapon effect.
7. Run the gate:
   ```bash
   godot --headless --path . -s res://tests/test_core_systems.gd
   ```
8. **Stop condition:** exit code `0` with real output shown, commit as `phase-4: spectral echo recording & playback, gate 4 green`. On failure: commit as `phase-4: ..., gate 4 red — <failing assertion>`, report exact output, log ambiguities in `QUESTIONS.md`, stop. Do **not** begin Phase 5.

Scope guard: the Stage Briefing UI ("No echoes yet — clear this stage with another hero" message) and all Hub screens belong to Phase 5; build the data plumbing only.
