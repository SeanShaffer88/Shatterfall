# QUESTIONS.md — Ambiguity Log

The agent appends questions here instead of inventing systems (`AGENTS.md`). The designer answers, then changes `Status: open` → `Status: answered (<date>)` and, if the answer becomes a design decision, adds it to `BLUEPRINT.md` §0.

## Open questions

(none)

## Answered

The six questions below came from the pre-implementation design review. The designer delegated these calls ("you decide everything"), and each answer is now a locked decision in `BLUEPRINT.md` §0.

### Q-1 — Skill aiming model — pre-Phase 1 — 2026-11-25
Context: §2D skills have directions and placements (Leap Slam, Shadow Vault, Phase Blink, Gravity Well) but no aiming input.
Answer: tap to cast, auto-aimed; stick direction overrides for directional skills; per-skill rules in §2D.
Status: answered (2026-11-25) → D27

### Q-2 — HP between rooms — pre-Phase 1 — 2026-11-25
Context: healing sources were almost nonexistent and nothing said whether HP resets per room.
Answer: HP carries over; each room clear heals 15% max HP; 0.4 s hit invulnerability.
Status: answered (2026-11-25) → D29

### Q-3 — Echo timing anchor — pre-Phase 1 — 2026-11-25
Context: room-relative timestamps drift when a different hero clears waves at a different pace, and a "12 most recent" cap kept only boss-room casts.
Answer: wave-relative time, first 2 casts per wave, 0.5 s cyan cue before each cast.
Status: answered (2026-11-25) → D34, D35

### Q-4 — Is Stage 3 evolution reachable in the slice? — pre-Phase 1 — 2026-11-25
Context: the v2.0 economy needed roughly 80+ runs for Stage 3.
Answer: yes. Retuned economy targets Stage 2 ≈ 5 own-hero clears and Stage 3 ≈ 20 (Rogue roughly double per weapon; Open Tunable #8).
Status: answered (2026-11-25) → D30, D31

### Q-5 — Mirage Veil direction — pre-Phase 1 — 2026-11-25
Context: "cancelling one telegraph" could mean the boss loses an attack (helps the player) or the warning vanishes (unfair).
Answer: neither — the active telegraph restarts from the new position with full warning time; the attack is delayed, never unwarned.
Status: answered (2026-11-25) → D32, §2H

### Q-6 — App backgrounded or killed mid-run — pre-Phase 1 — 2026-11-25
Context: Phase 6 force-kills the app, but nothing defined mid-run save timing or abandonment.
Answer: backgrounding auto-pauses; a force-kill counts as an abandoned run (drops up to the last room clear kept, no stars/echoes/grudge change); drops save at every room clear.
Status: answered (2026-11-25) → D29
