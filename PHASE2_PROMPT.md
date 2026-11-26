# Phase 2 Prompt — paste this into a fresh Claude Code session

Prerequisite: Phase 1 is complete with Gate 1 green (exit code `0` on the headless test run). If that is not true in this working copy, stop and reconcile with `main` first.

Copy everything below the line into Claude Code (from the repo root). Same shape as Phase 1: named phase, locked scope, gate, stop condition.

---

**Assignment: BLUEPRINT.md §3, Phase 2 only — Stop-to-Attack Controller & Hero Kits.**

Working from `AGENTS.md` rules and `BLUEPRINT.md`, with the visual hooks in `ART_DIRECTION.md` (AD1–AD12):

1. Build `scenes/actors/HeroActor.tscn` (`CharacterBody3D` + `WeaponMeshMount`) and `HeroController.gd` **exactly as specified in §2A** — one threshold set: stick deadzone `0.18`, full stop `<= 0.25 m/s`, grace buffer `0.08 s` before auto-attack starts, instant movement re-acquisition, attack cadences per §2D, reach limits per D28, and the `CASTING_SKILL`/`DASHING` lock exit.
2. Input: virtual joystick via `InputEventScreenDrag`/`InputEventScreenTouch` plus WASD desktop fallback (D1 landscape layout: stick region bottom-left).
3. Camera rig per D3: `Camera3D` on a boom — pitch −40°, distance 11 m, FOV 45°, position lerp 0.15 s, fixed orientation, no zoom.
4. Rogue range-swap with D28 hysteresis: Bow→Daggers at `<= 2.6 m`, Daggers→Bow at `> 3.0 m`, no attack beyond `10.5 m` (§2A "Rogue swap rule"). Both mains equipped per D18; the swap is automatic and emits `rogue_mode_changed` once per change.
5. Implement all 9 skills from §2D (3 per hero) with D27 tap-to-cast auto-aim, lock times, 0.15 s input buffer, cooldown timers and radial progress rings on the `DungeonRun` HUD; spawn real `Area3D` hitboxes/projectiles driven by the D25 damage math from Phase 1 data.
6. **Bake the AD2/AD3/AD4 emissive hooks into `HeroActor.tscn` now** (gray-box friendly): Brute armor emissive tracks Crimson Guard charge; Rogue trim flash (0.15 s) fires on every weapon-class swap; Magi staff-beam origin + orb brightness tracks Arcane Glass Barrier status. Gray-box meshes only — no custom art (AD11/AD12).
7. Extend `res://tests/test_core_systems.gd` (hand-rolled `SceneTree`, no plugins — D22) with Gate 2 coverage:
   - auto-attack begins ≤ 0.10 s after full stop, and movement re-acquires on the same physics frame intent is expressed;
   - no swing when the target is beyond reach (D28);
   - Rogue swaps at exactly 2.6 m (enter daggers) and 3.0 m (exit), holds its mode inside the band, attacks nothing beyond 10.5 m, and the AD3 swap flash event fires once per mode change;
   - all 9 skills spawn valid `Area3D` hitboxes/projectiles with expected shapes/radii, aim targets, lock times and cooldowns from `heroes.json`;
   - a scene-level smoke test that the camera lock resolves and no node errors occur.
8. Run the gate:
   ```bash
   godot --headless --path . -s res://tests/test_core_systems.gd
   ```
9. **Stop condition:** exit code `0` with real output shown, commit as `phase-2: stop-to-attack controller, hero kits & camera rig, gate 2 green`. If the gate fails, do not touch the test to force a pass — commit as `phase-2: ..., gate 2 red — <failing assertion>`, report the exact output, record anything ambiguous in `QUESTIONS.md`, and stop for my review. Do **not** begin Phase 3.

Scope guard: do not build rooms/waves, the Boon modal, echo capture, or any Hub UI in this phase — that is Phase 3+, and the gray-box test scenario is a single empty arena scene.
