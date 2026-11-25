# Shatterfall

Solo-Hero Action Dungeon Crawler / Weapon-Evolution RPG. Godot 4.5.x (pinned), Android-first (landscape, offline), Mobile renderer.

## Documents

- [BLUEPRINT.md](BLUEPRINT.md) — normative design + build spec. §0 Decision Log (D1–D15) is locked.
- [ART_DIRECTION.md](ART_DIRECTION.md) — locked visual language addendum (AD1–AD12) with per-hero emissive rules and gate hooks.
- [AGENTS.md](AGENTS.md) — session rules for the coding agent (phase discipline, test integrity, scope locks).
- [QUESTIONS.md](QUESTIONS.md) — ambiguity log; the agent files questions here instead of inventing systems.
- [PHASE1_PROMPT.md](PHASE1_PROMPT.md) — the first prompt to paste into a Claude Code session.

## Build order

Follow `BLUEPRINT.md` §3 phases 1→6. A phase is complete only when its gate passes:

```bash
godot --headless --path . -s res://tests/test_core_systems.gd
```

Headless gates verify logic only; Phase 6 is a manual on-device checklist (Galaxy S24 Ultra, 60 fps target).
