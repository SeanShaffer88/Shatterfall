# ART_DIRECTION.md — Shatterfall Visual Language Addendum (Locked)

**Status:** normative, companion to `BLUEPRINT.md`. The rules below are locked decisions (AD1–AD12); implement them exactly as written. Where an AD touches gameplay state, the tie is named so the corresponding gate can verify it. Nothing here requires custom modeled art — everything is achievable with gray-box meshes + shaders + lights within the slice's art policy.

**Design intent, in one sentence:** three warm-lit living heroes, one cold cyan ghost, and a liturgy of light that turns every combat state and forge milestone into something you can read at a glance on a top-down phone screen.

---

## 1. Per-Hero Look (silhouette-first, AD1–AD4)

### AD1 — Silhouette-first rule
At the fixed isometric 3/4 camera (55° pitch, 45° yaw, D3) on a phone screen, recognition comes from **helm shape, shoulder line, and weapon profile** — not surface detail. Design each hero so their black silhouette is unmistakable in a single-color test. Surface detail budget stays near zero in the slice; time spent on micro-detail before Phase 5 is wasted.

### AD2 — Brute: charred plate, ember cracks
Charred, layered plate with bone/scale edges; jagged asymmetric silhouette; horned/crested helm profile. **Combat tie:** cracks in the armor plate glow with crimson ember light proportional to **Crimson Guard** charge — dim when shielded at 10%, fully lit at the 30% cap, dark when broken. This is the shield's primary readability channel (verify in Gate 3 that the emissive intensity tracks the Guard value).

### AD3 — Rogue: angular light plate, gold-on-dark trim
Elegant, angular chrome/bronze trim on gunmetal-dark plate; light, sharp silhouette that contrasts deliberately with the Brute's mass. Absolutely no heavy spiked armor or skull iconography — heavy silhouettes read "tank" and would confuse the hero typology. Twin **curved** daggers (scimitar-shaped, elongated) with a distinct swing arc visual, so dagger-mode swings are distinguishable from the Brute's straight cleave fan at a glance. **Combat tie:** trim flashes once (0.15 s) on each Bow→Dagger and Dagger→Bow swap (verify in Gate 2 that the swap event triggers the flash).

### AD4 — Magi: layered robes, angular headdress, glass light
Tall, broad angular headdress carried low and wide for the single most readable top-down silhouette; layered robes that flare in wide crescent shapes. **Combat tie:** the staff's amber **orb-tipped focus** is the beam origin for all Prism Bolts, and its brightness indicates **Arcane Glass Barrier** status — bright when up, extinguished while the 6 s refresh is recharging. Accent palette: violet glass with amber light.

## 2. Global Color Language (AD5–AD7)

### AD5 — Warm beats cold
The canonical palette is obsidian/charcoal (`#121318`, `#2A2C33` stone) pierced by light: crimson `#D92638`, amber `#E8912D` (tunable), violet `#8F4FD4` (tunable), and by rule **AD6**, cold cyan for ghosts. Living heroes speak only warm light: Brute crimson, Rogue gold, Magi violet/amber.

### AD6 — Echoes are always cold cyan
All Spectral Echo rendering uses cold cyan glass light (`#5FD4E6`, tunable), even when an echo inherits a warm-weapon effect. Players must be able to distinguish "ally now" from "ghost of my past run" with zero text. The 0.5 s pre-cast ground cue (D35) is cyan too, so it can never be mistaken for an AD7 crimson-white telegraph. **Combat tie:** verify in Gate 4 that echo VFX overrides the inherited weapon's warm palette.

### AD7 — Telegraphs outrank ambience
Every enemy telegraph (decal or glow) renders in a shared alarm language — crimson-white ramp — that takes render priority over all decorative lighting. Stained-glass shafts, candle pools, and hero glows never share the telegraph's exact hue-and-value. Readability of dodge cues outranks beauty in every conflict.

## 3. Signature Screens (AD8–AD10)

### AD8 — The Forge is a reliquary book
The Weapon Forge drawer renders as an **open illuminated tome**: each two-page spread is one weapon class; evolution nodes are rune illustrations that ignite as level/shard/essence requirements complete; a glowing red reliquary orb appears at Stage 3 evolution entries as the payoff mark. This is UI framing, not unique 3D art — buildable in Godot UI with shaders/textures.

### AD9 — The Hub dais is the centerpiece (and a status readout)
`MainHub.tscn` centers on the committed hero's weapon displayed plunged into a **stained-glass dais** ringed by candles. **Combat tie:** the blade's glow color and intensity encode evolution stage (D26: Base = dim smoky glow; Stage 2 = brighter colored light; Stage 3 = full radiant bloom), with rarity as a secondary rim tint — an idle status readout that costs no extra UI.

### AD10 — Evolution is a liturgical moment
On Build-Up evolution: rise from dais → screen washes to stained-glass light → evolved weapon returns with its new mesh/glow preset. One shared moment for all four weapon classes, parameterized per class. Slated for Phase 5; the state hook (`weapon_id` mutation) already exists in Phase 1.

## 4. Rendering & Budget Guards (AD11–AD12)

### AD11 — Emissive over geometry
All hero/forge "glow" states are **emissive materials and lights**, not extra geometry or particles. A gray-box hero must support the AD2/AD3/AD4 emissive hooks before any Phase 5 polish begins — bake them into `HeroActor.tscn` in Phase 2.

### AD12 — Mobile perf budget is part of art direction
Per-frame art cost targets on Galaxy S24 Ultra (D8): each hero ≤ 1 custom emissive light contribution; echo count ≤ 2 actors visible simultaneously (enforced by the D35 wait-or-drop queue); zero real-time shadows from dynamic characters outside the hub dais scene. If a visual idea requires violating D8's 60 fps, the idea loses — a cheaper approximation wins.

---

## 5. Tunables & Verification Summary

| Param | Default | Tunable |
|---|---|---|
| Amber accent | `#E8912D` | yes |
| Violet accent | `#8F4FD4` | yes |
| Echo cyan | `#5FD4E6` | yes |
| Rogue swap-trim flash | 0.15 s | yes |
| Crimson Guard ember ramp | linear 10%→30% | yes |

**Gate hooks added by this document:** Gate 2 — Rogue swap flash fires on weapon-class change (AD3). Gate 3 — Brute emissive tracks Crimson Guard value (AD2); Magi orb brightness tracks barrier status (AD4). Gate 4 — echo VFX forces cold cyan over inherited warm weapon palettes (AD6). Gate 5 — hub dais weapon glow encodes evolution stage (AD9); Forge rune ignition state matches recipe progress (AD8).
