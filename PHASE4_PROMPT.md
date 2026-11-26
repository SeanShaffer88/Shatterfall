# Phase 4 Prompt — paste this into a fresh Claude Code session

Prerequisite: Phase 3 complete with Gate 3 green (exit code `0`). If not true in this working copy, stop and reconcile with `main` first.

Copy everything below the line into Claude Code (from the repo root).

---

**Assignment: BLUEPRINT.md §3, Phase 4 only — Spectral Echo Recording & Playback.**

Working from `AGENTS.md` rules, `BLUEPRINT.md` §2B, and `ART_DIRECTION.md` AD6:

1. Implement `autoload/EchoDirector.gd` recording per D34: capture manual casts of the seven effect skills (never auto-attacks, Shadow Vault or Phase Blink) — room, wave, wave-relative `t`, room-local position and target (relative to the room's `EchoAnchor`), skill id, Barrage mode. Keep the **first 2 casts per wave** (D12). Persist **only on stage victory** into `user://echoes/<stage_id>.json`, replacing only the clearing hero's entry (D23). Never record on failed or abandoned runs.
2. Schema per §2B: `schema_version: 1`, `stage_id`, per-hero `echoes` with `weapon_id` (**informational only**, D21) and the `events` array; no `client_version`; atomic JSON persistence through `SaveManager.gd` (D15/D23).
3. Playback per §2B/D35: load the **other two** heroes' entries; for the active (room, wave) resolve the target at `t − 0.5` (nearest living enemy within 3.5 m of the recorded target → nearest living enemy in the room within the skill's reach → skip), show the 0.5 s cyan ground cue, then at `t` spawn `scenes/actors/SpectralEcho.tscn` — **cold cyan only** (AD6). Apply the §2B per-skill echo table: values ×0.65, radii/pull/knockback unchanged, no crits, the recording hero's **current** weapon state (D21). Max 2 concurrent actors (wait ≤ 1.5 s, then drop); drop events whose wave ended before `t`; grudge adaptations apply except recoil.
4. Echoes fire in the boss room too. Echo damage/kills help clear waves but **never** feed the §2G star conditions (D9) — the star trackers must be provably isolated from echo damage events.
5. Time rule (D36): all echo, wave and room timers accumulate scaled physics `delta`; gate tests must show an event fires at the same game-time `t` (± one physics tick) with and without a simulated `time_scale` dip in either run.
6. Extend the Gate tests (hand-rolled `SceneTree`, D22):
   - The canonical case: a recorded Brute run spawns a **functional** Leap Slam echo in a subsequent Rogue run in the same room and wave at `t`, with its cue at `t − 0.5` (seed the run deterministically).
   - Target resolution order (3.5 m → room → skip); wave-ended drop; ≤ 2 concurrent actors with the 1.5 s wait/drop rule.
   - Star isolation: echo kills do not move §2G counters.
   - ×0.65 values and no crits are applied (and D21 inheritance: evolving the recording hero's weapon changes echo output).
   - Cap and overwrite: a third cast in one wave is not recorded; a new victory replaces only that hero's entry; Shadow Vault/Phase Blink are never recorded; serialization round-trip preserves `schema_version`.
   - AD6: echo palette is cyan even when inheriting a warm weapon effect.
7. Run the gate:
   ```bash
   godot --headless --path . -s res://tests/test_core_systems.gd
   ```
8. **Stop condition:** exit code `0` with real output shown, commit as `phase-4: spectral echo recording & playback, gate 4 green`. On failure: commit as `phase-4: ..., gate 4 red — <failing assertion>`, report exact output, log ambiguities in `QUESTIONS.md`, stop. Do **not** begin Phase 5.

Scope guard: the Stage Briefing UI ("No echoes yet — clear this stage with another hero" message) and all Hub screens belong to Phase 5; build the data plumbing only.
