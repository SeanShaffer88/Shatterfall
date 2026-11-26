# AGENTS.md — Session Rules for the Coding Agent (Claude Code / Codex / Cursor)

## Source of truth
- `BLUEPRINT.md` is the **normative** spec. The Decision Log (`BLUEPRINT.md` §0, D1–D40) is locked: do not change any decision without first asking, and never without updating the Decision Log entry in the same change.
- Numbers in tables are tuned starting points ("tunable"). You may implement them exactly as written; you may not invent replacements.

## Phase discipline
- Work **one phase at a time** (`BLUEPRINT.md` §3). A session prompt names the phase; stay inside it.
- Do **not** touch files outside the phase's scope, and do **not** begin the next phase unprompted.
- No scope additions. If you see a missing requirement or ambiguity, **append it to `QUESTIONS.md`** with the phase, date, and your proposed default, then **stop and ask**. Do not silently invent systems.

## Test integrity (non-negotiable)
- A phase is **done only when its gate passes** for real:
  ```bash
  godot --headless --path . -s res://tests/test_core_systems.gd
  ```
- **Never weaken, skip, or edit a test to make a failing gate pass.** If a gate fails, report the exact failing assertion and command output, and stop.
- Always paste/return the real command output in your summary. A gate claim without output is not a completed phase.

## Engineering ground rules
- Godot **4.7.2 stable, pinned** (D22), **Mobile renderer** for every build, Windows dev builds included (D2/D39).
- Fresh clone: run `godot --headless --path . --import` before the test command, or `class_name` lookups fail (D38). On Windows use `Godot_v4.7.2-stable_win64.exe --headless`; the `_console` wrapper fails in the agent sandbox.
- Loading `data/*.json` **fails loud**: malformed JSON aborts with a precise file/field error — never default silently (D22).
- Full 3D; all units meters and m/s (D4). No 2D px/s values anywhere.
- All JSON files carry `"schema_version": 1`; saves are atomic write-then-rename (D15). Single save slot `user://save.json` (D23).
- Package identity (D24): id `com.seanshaffer88.shatterfall`, version `0.1.0`, display name **Shatterfall**, English-only.
- Art is **gray-box placeholder meshes + `stained_glass_echo.gdshader`** only. Visual language rules and emissive hooks are locked in `ART_DIRECTION.md` (AD1–AD12); bake AD2/AD3/AD4 emissive hooks into `HeroActor.tscn` during Phase 2. No custom modeled art in the slice.
- `Engine.time_scale` effects must respect the Echo timing caveat (`BLUEPRINT.md` §2B).
- Echo damage/kills never count toward star conditions (D9); boons are run-only (D14).
- Tests step gameplay manually at a fixed 1/60 s (`tests/lib/CombatSim.gd`). `move_and_slide()` moves by the *engine's* physics delta, so the runner waits for one real physics frame first; never step physics bodies before that.
- All gameplay timers use scaled physics `delta` (D36); all randomness goes through `GameState`'s seeded RNG streams (D25).
- Say `rarity` (drop quality 1–3) and `evo_stage` (evolution 1–3); the word "tier" is retired (D26).

## Commit convention
One commit per completed unit of work, phrased as:
- `phase-N: <what was built>, gate N green`
- `phase-N: <what was built>, gate N red — <failing assertion>` (when stopping on a failure)

## QUESTIONS.md protocol
Append entries in this shape:

```
### Q-<n> — <short title> — <phase> — <date>
Context: <why this blocks the current task>
Proposed default: <what you would do if no answer comes>
Status: open
```

## First assignment
`PHASE1_PROMPT.md`.
