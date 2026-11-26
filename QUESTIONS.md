# QUESTIONS.md — Ambiguity Log

The agent appends questions here instead of inventing systems (`AGENTS.md`). The designer answers, then changes `Status: open` → `Status: answered (<date>)` and, if the answer becomes a design decision, adds it to `BLUEPRINT.md` §0.

## Open questions

(none)

## Answered

### Q-8 — D3 "boom height 11 m" vs §2A "distance 11 m" — Phase 2 — 2026-11-25
Context: the two camera specs disagreed on whether 11 m is the boom's height or its length.
Answer: boom **length** 11 m at 40° pitch (height ≈ 7.07 m), matching §2A. D3 reworded.
Status: answered (2026-11-25), decided under the designer's delegation

### Q-9 — Kit details §2D left open — Phase 2 — 2026-11-25
Context: §2D gives the skills' effects but not these values; Phase 2 needs them.
Answer (all tunable):
- Projectile speeds: arrows 30 m/s, Prism Bolts 16 m/s (homing, 9 rad/s turn); both fly 1.5 m past their reach.
- Shadow Vault and Phase Blink are movement-only and spawn no attack Area3D; the other 7 skills each spawn one (Barrage spawns 5 arrows or one fan).
- Shatter Mark targets the nearest enemy within 10.5 m; with no target it does not cast and keeps its cooldown. Every other skill always casts.
- Escape direction with no stick and no enemy: straight backwards.
- "Slight pull" (Vortex Cleave) = 1.5 m toward the Brute, never closer than 1 m; Shatter Nova knockback 3 m; Gravity Well pulls at 2 m/s and ticks once per second (4 ticks).
- Dagger-mode Adaptive Barrage hits everything in a 120° fan within 3.0 m.
- Hit resolution is geometric (center distance + arc), not physics overlap, so headless tests and play agree (D38). Hitboxes and projectiles are still real Area3D nodes with sphere shapes.
Status: answered (2026-11-25), decided under the designer's delegation

### Q-10 — Leftover momentum after a lock — Phase 2 — 2026-11-25
Context: the §2A code ended a CASTING_SKILL/DASHING lock without clearing velocity, so a Leap Slam or Shadow Vault slid about 1.5 m past its target.
Answer: one line in the §2A lock exit, `velocity = Vector3.ZERO`, now in both BLUEPRINT §2A and `HeroController.gd`.
Status: answered (2026-11-25), decided under the designer's delegation

### Q-7 — Where WeaponForge.gd and the package id live — Phase 1 — 2026-11-25
Context: §3.2's tree had no home for `WeaponForge.gd` (it isn't an autoload), and `project.godot` has no package-id setting.
Answer: plain classes go in `res://systems/` (now in the §3.2 tree). `project.godot` sets the display name and version from Phase 1; the package id `com.seanshaffer88.shatterfall` is an export-preset field, set in Phase 5 with `export_presets.cfg` (D40).
Status: answered (2026-11-25), decided under the designer's delegation

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
