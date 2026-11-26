# Shatterfall

Solo-Hero Action Dungeon Crawler / Weapon-Evolution RPG. Godot 4.7.2 stable (pinned), Android-first (landscape, offline), Mobile renderer.

## Documents

- [BLUEPRINT.md](BLUEPRINT.md) — normative design + build spec. §0 Decision Log (D1–D40) is locked.
- [ART_DIRECTION.md](ART_DIRECTION.md) — locked visual language addendum (AD1–AD12) with per-hero emissive rules and gate hooks.
- [AGENTS.md](AGENTS.md) — session rules for the coding agent (phase discipline, test integrity, scope locks).
- [QUESTIONS.md](QUESTIONS.md) — ambiguity log; the agent files questions here instead of inventing systems.
- [PHASE1_PROMPT.md](PHASE1_PROMPT.md) — the first prompt to paste into a Claude Code session.
- [PHASE2_PROMPT.md](PHASE2_PROMPT.md) — the Phase 2 prompt (controller, hero kits, camera rig, Gate 2).
- [PHASE3_PROMPT.md](PHASE3_PROMPT.md) — the Phase 3 prompt (dungeon loop, boon draft, boss grudge, Gate 3).
- [PHASE4_PROMPT.md](PHASE4_PROMPT.md) — the Phase 4 prompt (spectral echo recording & playback, Gate 4).
- [PHASE5_PROMPT.md](PHASE5_PROMPT.md) — the Phase 5 prompt (main hub, stage briefing, visual polish, Gate 5).
- [PHASE6_PROMPT.md](PHASE6_PROMPT.md) — the Phase 6 on-device verification checklist (manual, Galaxy S24 Ultra).

## Build order

Follow `BLUEPRINT.md` §3 phases 1→6. A phase is complete only when its gate passes:

```bash
godot --headless --path . --import   # fresh clone only
godot --headless --path . -s res://tests/test_core_systems.gd
```

Headless gates verify logic only; Phase 6 is a manual on-device checklist (Galaxy S24 Ultra, 60 fps target).
