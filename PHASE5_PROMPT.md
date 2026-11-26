# Phase 5 Prompt — paste this into a fresh Claude Code session

Prerequisite: Phase 4 complete with Gate 4 green (exit code `0`). If not true in this working copy, stop and reconcile with `main` first.

Copy everything below the line into Claude Code (from the repo root).

---

**Assignment: BLUEPRINT.md §3, Phase 5 — Main Hub UI, Stage Briefing & Visual Polish.**

Working from `AGENTS.md` rules, `BLUEPRINT.md`, and `ART_DIRECTION.md` AD5–AD12:

1. Build `scenes/main/MainHub.tscn` (D1 landscape, 2400×1080 base, safe margins ≥ 48 px):
   - Symmetrical 3-hero selector cards: equipped weapon (evolution stage, rarity + D25 ATK readout), stars earned (D7), and the current Grudge Adaptation warning plus its counter tip from §2H/D11.
   - **Stage Briefing** panel: hazards, the 3 star conditions, the hero's recorded echoes for this stage, Vespera's active adaptation. First-run heroes see "No echoes yet — clear this stage with another hero" (§2B) — wire it to the Phase 4 data, not a placeholder.
2. **Weapon Forge drawer (AD8 — reliquary book):** render the Forge as an open illuminated tome; each spread = one weapon class; evolution nodes are runes that **ignite as level/shard/essence requirements complete** (assert this state-matching in Gate 5). 1-tap **Absorb** vs **Salvage** following the D5/D18 rules with D16/D25 math and the D30/D31 economy (warn before an at-cap Absorb discards XP); Forge actions happen **only here** (D20) and the drawer is **locked until the first boss kill** (D13). A glowing red orb marks Stage 3 evolution entries.
3. **Hub dais (AD9):** center the scene on the committed hero's weapon plunged into a stained-glass dais ringed by candles; the blade's glow color/intensity encodes evolution stage (Base = dim smoky, Stage 2 = brighter, Stage 3 = full radiant bloom; rarity as rim tint). Assert the glow state matches the `weapons.json` state in Gate 5.
4. **Evolution moment (AD10):** Build-Up evolution plays the shared liturgical sequence (rise from dais → stained-glass wash → evolved weapon returns with new mesh/glow preset); parameterized per class; driven by the Phase 1 `weapon_id` mutation hook.
5. **Polish within budget (AD11/AD12, D8):** floating damage/rupture numbers; hit-stop as an `Engine.time_scale` micro-dip **only** on heavy non-skill crits, consistent with the D36 time rule (gate-test it now); run summary with progress toward unmet stars; procedural stained-glass lighting must respect the AD12 perf caps (≤ 1 custom emissive light per hero, ≤ 2 visible echo actors, no dynamic character shadows in-run).
6. Global visual rules to enforce in-scene (AD5–AD7): living heroes warm-only (Brute crimson / Rogue gold / Magi violet-amber), echoes cold cyan only, telegraphs crimson-white and always rendered above decorative light.
7. Extend the Gate tests (hand-rolled `SceneTree`, D22):
   - Hub flow (brief → commit → run → summary → hub) completes with no orphaned/save-corrupting state across a full run loop, including a death path (D10).
   - Forge drawer is locked before the first Vespera kill and unlocks after (D13); UI absorb/salvage calls yield identical results to the Phase 1 core functions (D16–D19).
   - AD8 rune ignition state matches recipe progress; AD9 dais glow matches evolution stage; AD10 sequence fires exactly once per evolution.
   - Package identity is set per D24 in `project.godot`; `export_presets.cfg` matches D24/D40 (arm64-v8a only, sensor-landscape) and no keystore is committed.
8. Run the gate:
   ```bash
   godot --headless --path . -s res://tests/test_core_systems.gd
   ```
9. **Stop condition:** exit code `0` with real output shown, commit as `phase-5: main hub, stage briefing & visual polish, gate 5 green`. On failure: commit as `phase-5: ..., gate 5 red — <failing assertion>`, report exact output, log ambiguities in `QUESTIONS.md`, stop.

Scope guard: on-device verification belongs to Phase 6; create the export presets (D40) but do not export to or test on a device in this phase. No new dependencies, no custom modeled art.
