# SHATTERFALL — Design & Build Blueprint v2.0

**Release title:** *Shatterfall* (the former "Shattered Reliquary" codename is retired; do not use it anywhere, including filenames).

**What this document is:** a complete design + build spec for an AI coding agent (Claude Code / Codex / Cursor) and for humans. Everything needed to build the vertical slice is on this page. Where the earlier draft left ambiguity, there is now an explicit decision, marked **[D#]**. Tunable numbers are in tables; tune them, never silently.

---

## 0. Decision Log (locked decisions)

| # | Question | Decision |
|---|----------|----------|
| D1 | Orientation | **Landscape.** Base resolution 2400×1080 (16:9), `canvas_items` stretch, aspect `expand`. Virtual stick bottom-left, 3 skill buttons bottom-right. |
| D2 | Renderer | **Mobile renderer** (Vulkan) for all builds. Forward+ is allowed only for Windows desktop dev builds. |
| D3 | Camera | Fixed follow top-down: pitch **40°**, boom height **11 m**, FOV 45°, target lock with 0.15 s smoothing. No player zoom, no rotation. |
| D4 | Dimension / units | Full 3D (`CharacterBody3D`, `Area3D`, `Vector3`). All tuning in **meters and m/s**. No 2D px/s units anywhere. |
| D5 | Weapon binding | **Hero-locked weapons.** Brute = Greataxe, Rogue = Daggers *and* Shortbow (two classes, both Rogue-only; class switches with range), Magi = Staff. Off-class drops are absorb/salvage fodder for nobody — they are marked "Not usable" in inventory and can only be salvaged. |
| D6 | Run length | Target **6–9 minutes** per full stage run (4 rooms + boss). |
| D7 | Star loop | Each stage has 3 stars, one per hero. A star is awarded **only on a run cleared with that hero** that also satisfies its condition. Full star loop = **3 clears per stage** (one per hero). Stars persist forever in the save. |
| D8 | Minimum device | Samsung Galaxy S24 Ultra (Snapdragon 8 Gen 3 / Adreno 750, Android 14) at **60 fps**. Engineering floor: Snapdragon 480-class at 30 fps must not crash and must stay playable. |
| D9 | Echo vs stars | Echo assists may damage enemies and help clear waves, but **echo damage/kills never count toward star objective tracking**. |
| D10 | Death | Hero death **ends the run** immediately (summary screen). Kept forever: absorbed XP, evolution progress, shards, essences, inventory drops. Lost: run boons. Echoes are **not** recorded on failed runs. No mid-run checkpoints. |
| D11 | Grudge lifecycle | Exactly **one active adaptation per boss**, **replaced** (never stacked) each time that boss is cleared, until the next clear replaces it. Drop-rate bias for the other two heroes' weapon classes: **+25%**, active until the next clear. |
| D12 | Echo cap | Records every manual skill cast, capped at the **12 most recent events** per run. Only the **last completed run per (stage, hero)** is stored; a new clear overwrites it. |
| D13 | Onboarding | Forge UI unlocks after the first boss kill. Before that, the inventory is usable (drops accumulate) but the Forge drawer shows a locked tooltip. See §5. |
| D14 | Boon persistence | Boons are run-only. They are lost on death **and** do not carry into the next run after a win. |
| D15 | Save format | All JSON files carry `"schema_version": 1`. Saves are atomic (write temp file, then rename). |

Numbers marked "tunable" are starting points selected for one 6–9 minute run with the three grips below; tune by playtest, never silently.

---

## 1. Game Design Document

### High Concept
**Title:** *Shatterfall*
**Genre:** Solo-Hero Action Dungeon Crawler / Weapon-Evolution RPG
**Platform:** Android first (offline, no ads, no purchases), landscape, one-thumb virtual stick + 3 manual skill buttons; Windows desktop build for development only.
**Visual Identity:** Painted Stained-Glass Reliquary — obsidian and charcoal cathedral stone pierced by crimson, amber, and violet stained-glass light; crisp character silhouettes; glowing crystalline weapon evolutions; translucent stained-glass Echo spirits. **Visual language is normative in `ART_DIRECTION.md` (AD1–AD12)**; its per-hero emissive rules and color coding carry gate hooks (see that document §5).

### Core Gameplay Loop
1. **Stage Briefing & Hero Commit (Main Hub):** inspect hazards, the 3 hero-specific stars, your recorded Spectral Echoes for this stage, and Vespera's current Grudge Adaptation; commit **one** hero:
   - **Brute** — Sustain & Cleave Tank. Sweeping melee arcs; hitting **2+ targets** grants **Crimson Guard** (shield). Skills: Leap Slam, Rending Roar, Vortex Cleave.
   - **Rogue** — Range-Adaptive Skirmisher. Auto-switches **Shortbow** (range) / **Twin Daggers** (melee) based on distance to the nearest enemy while stopped. Skills: Shadow Vault, Adaptive Barrage, Shatter Mark.
   - **Magi** — Zone Control & AoE Burst. Homing **Prism Bolts**; **Arcane Glass Barrier** absorbs one hit every 6 s (tunable). Skills: Phase Blink, Gravity Well, Shatter Nova.
2. **Room Clearing & Boon Draft:** move freely to dodge telegraphed attacks; **stop moving to auto-attack** the nearest enemy. Clear waves room-by-room; before Room 3, draft **1 of 3 run boons**.
3. **The Three Signature Hooks:**
   - **Hero-Specific Stars (D7).**
   - **Spectral Echo Assists:** successful clears record your skill casts as a lightweight ghost timeline. Replaying the stage with a *different* hero spawns translucent stained-glass Echoes that re-cast those skills at the recorded room-relative moments (D9/D12 rules in §2B).
   - **Boss Grudge & Adaptation (D11):** clearing Vespera with a hero installs one defensive adaptation against that archetype and boosts drops for the other two.
4. **Same-Type Absorption & Build-Up Forge (D5):** weapons never break. Same-weapon-class drops can be **Absorbed** (XP + a small permanent sub-stat) or **Salvaged** (class shards + essence) to trigger branching **Build-Up** evolutions (§2C).

### Fail State (D10)
Hero death ends the run. Summary screen shows: stars earned (only on clear), drops kept, forge progress retained, boons lost.

---

## 2. Core Systems — Spec & Numbers

### A. Stop-to-Attack & Rogue Range-Switch Controller (`HeroController.gd`)

One threshold set, in meters, matching the sample code exactly:

- Input deadzone: stick magnitude `> 0.18` counts as movement intent.
- Full stop: velocity `<= 0.25 m/s`.
- Attack-start grace buffer: **0.08 s** of sustained near-stop before auto-attack begins (kills micro-twitch attacks, stays under the 0.10 s gate).
- Re-acquiring movement is **instant** (no grace on movement, only on attack start).

```gdscript
class_name HeroController
extends CharacterBody3D

enum HeroClass { BRUTE, ROGUE, MAGI }
enum CombatState { MOVING, STOPPED_ATTACKING, CASTING_SKILL, DASHING }

@export var hero_class: HeroClass = HeroClass.BRUTE
@export var move_speed: float = 4.2          # m/s, tunable
@export var input_deadzone: float = 0.18

const STOP_VELOCITY: float = 0.25            # m/s
const GRACE_TIME: float = 0.08               # s before auto-attack starts

var state: CombatState = CombatState.MOVING
var input_vector: Vector2 = Vector2.ZERO
var attack_timer: float = 0.0
var stop_timer: float = 0.0
var current_target: Node3D = null

func _physics_process(delta: float) -> void:
	if state == CombatState.CASTING_SKILL or state == CombatState.DASHING:
		move_and_slide()
		return

	if input_vector.length() > input_deadzone:
		stop_timer = 0.0
		state = CombatState.MOVING
		var dir := Vector3(input_vector.x, 0.0, input_vector.y).normalized()
		velocity = dir * move_speed
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 14.0 * delta)
	else:
		velocity = velocity.move_toward(Vector3.ZERO, 40.0 * delta)
		if velocity.length() <= STOP_VELOCITY:
			stop_timer += delta
			if stop_timer >= GRACE_TIME:
				state = CombatState.STOPPED_ATTACKING
				_process_auto_attack(delta)
		else:
			stop_timer = 0.0

	move_and_slide()

func _process_auto_attack(_delta: float) -> void:
	current_target = _find_nearest_enemy()
	if not is_instance_valid(current_target):
		return

	var to_target := current_target.global_position - global_position
	to_target.y = 0.0
	rotation.y = lerp_angle(rotation.y, atan2(to_target.x, to_target.z), 18.0 * delta)

	attack_timer -= _delta
	if attack_timer <= 0.0:
		_execute_primary_attack(to_target.length())

func _execute_primary_attack(dist: float) -> void:
	match hero_class:
		HeroClass.BRUTE:
			attack_timer = 0.9
			_fire_cleave_arc()
		HeroClass.ROGUE:
			if dist <= 2.6:               # dagger mode
				attack_timer = 0.35
				_fire_dagger_flurry(current_target)
			elif dist <= 10.5:            # bow mode
				attack_timer = 0.55
				_fire_bow_arrow(current_target)
		HeroClass.MAGI:
			attack_timer = 0.7
			_fire_prism_bolt(current_target)
```

**Rogue swap rule (normative):** the weapon is chosen by **distance to nearest enemy while stopped** — `<= 2.6 m` daggers, `2.6–10.5 m` bow, `> 10.5 m` no attack (walk closer). "Switches when stopping" wording from earlier drafts is superseded.

**Camera rig (D3):** `Camera3D` on a boom parenting the hero: pitch −40°, distance 11 m, FOV 45°, position lerp 0.15 s, fixed orientation. Verify the hero and the bottom UI never overlap at 2400×1080 and at 19.5:9 (S24 Ultra native is 3120×1440; test 16:9 and 19.5:9 crops).

### B. Spectral Echo System (`EchoSystem.gd` / `EchoDirector.gd`)

Intent-anchored keyframes, not frame recording.

**Record (D12):** every **manual skill cast** (not auto-attacks, not dashes/blink alone), with room index, room-relative time, hero position, skill id, and a target point. Keep the 12 most recent events of the run; drop older overflow. Save only on stage **victory**, one file per `(stage, hero)`, overwrite on new clear. No save on failed runs (D10).

**Schema (`user://echoes/stage_01.json`):**
```json
{
  "schema_version": 1,
  "stage_id": "stage_01_sunken_nave",
  "echoes": {
    "BRUTE": {
      "weapon_id": "cinderheart_maul",
      "client_version": 1,
      "events": [
        { "room": 0, "time": 2.4, "pos": [1.2, 0.0, -3.5], "skill": "LEAP_SLAM", "target_offset": [0.0, 0.0, -4.0] },
        { "room": 2, "time": 4.1, "pos": [0.0, 0.0, 0.0], "skill": "VORTEX_CLEAVE", "target_offset": [0.0, 0.0, 0.0] }
      ]
    }
  }
}
```

**Playback (normative):** entering Room `R` as hero X, `EchoDirector` loads the saved echoes of the **other two** heroes. At `room_elapsed_time >= event.time`, spawn a `SpectralEchoActor` (translucent stained-glass Fresnel shader, crimson/cyan), aim via **smart snap**: the nearest **living** enemy within **3.5 m** of the recorded target point; if none is alive in the room, **skip the event silently** (no whiff into empty rooms). Execute at **65% base potency**, inheriting the recording hero's current Build-Up weapon effect. Echo damage/kills are **excluded from star tracking** (D9). Echoes fire in the boss room too. First-run heroes (no saved echoes) see: "No echoes yet — clear this stage with another hero" in the Stage Briefing.

**Hit-stop caveat:** `Engine.time_scale` micro-dips must **not** shift any countdown the Echo system uses. If global time tricks are used, trigger them only mid-swing on non-skill hits, and record/play back echo timers in *scaled* time consistently.

### C. Same-Type Absorption & Build-Up (`WeaponForge.gd`)

**Data model:** `weapon_class` (`GREATAXE`, `DAGGERS`, `SHORTBOW`, `STAFF`), `owner_hero` (hero-locked, D5), `tier`, `level`, `xp`, `xp_to_next`, `salvage_shards`, `uid`.

**Rules (normative):**
- `can_absorb(main, fodder)` = same `weapon_class` AND different `uid` AND `fodder.owner_hero == main.owner_hero`.
- **Absorb:** transfers `fodder.base_xp + (fodder.level * 25)` XP (default `base_xp = 10`, tunable) into `main.xp` and adds a permanent `+1` to one rotating sub-stat (`+ATK`, `+CRIT`, `+ELEMENT`).
- **XP curve (tunable):** `xp_to_next(level) = round(50 * 1.5^(level-1))`; level cap 10 in the slice.
- **Salvage:** destroys the fodder, grants N class shards (`GREATAXE_SHARD`, …; N = 2 + tier, tunable) plus any infused monster essence.
- **Build-Up trigger:** `main.level >= recipe.req_level` AND shards ≥ `recipe.shard_cost` AND owns `recipe.boss_essence_id`. Evolving mutates `weapon_id`, swaps mesh/VFX, grants **+20% ATK**, and sets the evolution's Echo visual preset.
- **Off-class drops (D5):** visually marked "Not usable — salvage only" in the inventory.

**Evolution trees (2 tiers per class, slice scope, all numbers tunable):**

| Hero | Class | Base | Tier 2 (lvl 5, 40 shards) | Tier 3 (lvl 10, 80 shards + Vespera essence) |
|---|---|---|---|---|
| Brute | Greataxe | Ashen Cleaver | Cinderheart Maul | Vesperglass Executioner |
| Rogue | Daggers | Nightbite Pair | Whispershard Fangs | Lamplighter Fangs |
| Rogue | Shortbow | Yewline Bow | Vinewhisper Bow | Choirglass Bow |
| Magi | Staff | Lorelight Rod | Prismheart Staff | Reliquary Nova Staff |

### D. Hero Kits, Cooldowns, Damage (all tunable)

| Hero | HP | Primary | Skills (cooldown — effect) |
|---|---|---|---|
| Brute | 140 | Cleave arc 22 dmg, 0.9 s, 3.2 m / 110° | Leap Slam (8 s — 5 m leap, 30 dmg, 2.5 m AoE, 0.5 s stun) · Rending Roar (12 s — 6 m radius, −30% enemy damage 5 s, grants Crimson Guard) · Vortex Cleave (15 s — 7 m sweep, 45 dmg, slight pull) |
| Rogue | 100 | Daggers 2×7 dmg, 0.35 s, 2.2 m · Bow 12 dmg, 0.55 s, 10.5 m | Shadow Vault (7 s — 4 m dash, 0.25 s invuln, next dagger pair +50%) · Adaptive Barrage (10 s — bow: 5 homing arrows 8 dmg; daggers: 4 slices 10 dmg) · Shatter Mark (14 s — target takes +25% dmg 8 s; killing a marked enemy heals 10) |
| Magi | 110 | Prism Bolt 15 dmg homing, 0.7 s, 14 m | Phase Blink (6 s — 4 m teleport, refreshes Arcane Glass Barrier) · Gravity Well (12 s — 3 m pull zone, 4 s, 6 dmg/s) · Shatter Nova (16 s — 4 m nova, 40 dmg, knockback) |

- **Crimson Guard:** hitting 2+ enemies with the cleave grants a shield = 10% max HP (stacking to 30% cap), lasts until broken or 6 s without a qualifying hit (tunable).
- **Arcane Glass Barrier:** absorbs one hit; refreshes every 6 s or on Phase Blink.
- All damage scales off weapon ATK × hero multiplier; the flat numbers above assume a level-1 base weapon.

### E. Enemies & Waves (tunable)

| Enemy | HP | Behavior |
|---|---|---|
| Crawler | 30 | Melee chaser, 2.0 m/s, contact 8 dmg |
| Spitter | 22 | Ranged, 8 m range, 6 dmg projectile every 1.8 s |
| Bulwark | 60 | Frontal shield: 50% damage reduction from the front |
| Spike trap | — | Telegraphed floor spikes, 10 dmg, 1 s warning |

**Stage 1 — The Sunken Nave** (rooms 1→4, then Vespera; target 6–9 min, D6):
- Room 1: 1 wave — 3 Crawlers + 1 Spitter.
- Room 2: 2 waves — 4 Crawlers → 2 Spitters + 2 Crawlers.
- Room 3: 2 waves + spike traps — 2 Crawlers + 2 Spitters → 1 Bulwark + 3 Crawlers.
- Room 4: 3 waves — 3 Spitters + 2 Crawlers → 2 Bulwarks → 4 Crawlers + 2 Spitters.
- Room doors unlock only on wave clear.
- **Boss Vespera:** 600 HP, 2 phases (phase 2 at 50%: faster telegraphs, spawns 4 Crawlers once). Attacks: telegraphed sweep (30 dmg), glass-shard rain (3 zones × 10 dmg). Phase 2 adds a shard wall.

### F. Boon List (run-only, D14)

Draft 1 of 3 before Room 3. Pool from which 3 unique offers are drawn; no duplicate offered. Same pool every run; re-picking across runs is allowed. Lost on death **and** after a win (D14).

| Boon | Effect |
|---|---|
| Crimson Surcharge | +12% damage |
| Glass Skin | +15 max HP and heal 15 |
| Tempest Heart | +10% move speed, +10% attack speed |
| Amber Ward | 15% less projectile damage taken |
| Second Wind | Once: dropping below 25% HP heals 40% (consumed on use) |
| Fracture Focus | Skill cooldowns −15% |

### G. Hero-Specific Stars — Stage 1 (D7, D9)

Awarded only on a cleared run with the matching hero; all conditions are code-verifiable:

| Star | Hero | Condition |
|---|---|---|
| Cleave Master ★ | Brute | Crimson Guard active ≥ 70% of the Vespera fight duration |
| Close Work ★ | Rogue | Land ≥ 20 dagger-mode hits during the Vespera fight |
| Untouched Prism ★ | Magi | Clear Room 2 without taking any damage |

### H. Boss Grudge & Adaptation (D11)

`GameState.get_last_clearing_hero("stage_01")` selects exactly one active adaptation; a new clear replaces it:

| Beaten by | Adaptation | Effect |
|---|---|---|
| Brute | Spiked Carapace | Melee attackers take 15% of dealt damage as recoil |
| Rogue | Mirage Veil | Every 8 s the boss blinks 3 m sideways, cancelling one telegraph |
| Magi | Runic Dampening | AoE effects on the boss: −30% radius and duration |

Drops biased +25% toward the other two heroes' weapon classes until the next clear (D11). Main Hub shows the current adaptation warning on the hero-select cards.

---

## 3. Agent Workflow Blueprint — WFBP: Shatterfall, Godot 4.x Vertical Slice

> Hand this section (and everything above it) to the coding agent as-is. Do **not** wrap it in an outer markdown fence — earlier drafts broke because of nested triple backticks.

### 1. Project Identity & Hard Constraints
- **Engine:** Godot 4.x, **Mobile renderer** (D2); Android `arm64-v8a` + Windows dev build.
- **Orientation & UI:** **Landscape 2400×1080** base, `canvas_items` stretch, aspect `expand` (D1). Theme `#121318` background, crimson `#D92638` + jewel accents. Virtual stick bottom-left, 3 skill buttons bottom-right arc with radial cooldown rings, stats top-left, wave info top-right, pause top-right corner. Safe margins ≥ 48 px; verify at both 16:9 and 19.5:9.
- **Min device:** Galaxy S24 Ultra @ 60 fps (D8); floor = Snapdragon 480-class @ 30 fps, no crash.
- **Scope:** Stage 1 (*The Sunken Nave*, 4 rooms + Vespera), 3 heroes, Stop-to-Attack + 3 skills, Hero-Specific Stars, Spectral Echoes, Grudge Adaptation, Same-Type Absorption/Build-Up Forge. **No scope additions** — file an ambiguity as a question instead of inventing a system.
- **Art policy:** gray-box placeholder meshes + the one custom `stained_glass_echo.gdshader`; colors/lighting per Visual Identity and the locked rules in `ART_DIRECTION.md` (AD1–AD12), whose emissive hooks (AD2/AD3/AD4) must exist in `HeroActor.tscn` from Phase 2. No custom modeled art in the slice.

### 2. Directory & Scene Architecture
```text
res://
├── project.godot
├── autoload/
│   ├── GameState.gd          # Active hero, stage progress, stars, grudge state
│   ├── SaveManager.gd        # Atomic JSON read/write, schema_version (D15)
│   └── EchoDirector.gd       # Records skill keyframes & spawns SpectralEcho actors
├── data/
│   ├── heroes.json           # Base stats, skills, cadences (§2D values)
│   ├── weapons.json          # Classes, hero-lock (D5), evolution trees (§2C)
│   └── stages.json           # Rooms, waves, stars, Vespera grudge modifiers (§2E–H)
├── scenes/
│   ├── main/
│   │   ├── MainHub.tscn      # Hero trio selector, Stage Briefing, Weapon Forge drawer
│   │   └── DungeonRun.tscn   # Landscape HUD, virtual stick, 3 skill buttons, Boon modal
│   ├── actors/
│   │   ├── HeroActor.tscn    # CharacterBody3D + HeroController + WeaponMeshMount
│   │   ├── SpectralEcho.tscn # Translucent stained-glass ghost executor
│   │   ├── EnemyBase.tscn    # Melee/ranged/shielded AI + telegraph decals
│   │   └── BossVespera.tscn  # 2-phase boss + Grudge Adaptation handler
│   └── rooms/
│       └── Stage01_Nave.tscn # 4 rooms, gate triggers, spike traps
├── shaders/
│   └── stained_glass_echo.gdshader
└── tests/
    └── test_core_systems.gd  # Headless CLI verification suite
```

### 3. Execution Phases (build & verify sequentially; a phase is done only when its gate passes)

**Phase 1 — Data, SaveManager, Weapon Forge.** `GameState.gd`, `SaveManager.gd` (schema_version, atomic writes), `WeaponForge.gd` with the D5 hero-lock and §2C rules.
*Gate 1 (headless):* absorption rejects mismatched class **and** foreign-owner fodder; matching absorbs grant XP + sub-stat; salvage yields correct shard counts; evolution triggers at level/shard/essence thresholds; save round-trip preserves `schema_version`.

**Phase 2 — Stop-to-Attack Controller & Hero Kits.** `HeroActor.tscn`/`HeroController.gd` exactly as §2A (one threshold set: deadzone 0.18, stop 0.25 m/s, grace 0.08 s); joystick (`InputEventScreenDrag`) + WASD fallback; Rogue distance-based swap (≤ 2.6 m daggers / ≤ 10.5 m bow); 3 skills per hero from §2D with cooldown rings; camera rig per D3.
*Gate 2 (headless):* auto-attack starts ≤ 0.10 s after full stop; movement re-acquires the same frame; Rogue swaps per distance table; all 9 skills spawn valid `Area3D` hitboxes/projectiles; camera lock verified in the scene test.

**Phase 3 — Dungeon Loop, Boon Draft, Boss Grudge.** `Stage01_Nave.tscn` with waves per §2E, spike traps, 1-of-3 Boon modal before Room 3 (§2F pool), `BossVespera.tscn` 2 phases, Grudge per §2H/D11.
*Gate 3 (headless):* doors unlock only on wave clear; each boon modifies stats for the run only; Vespera clear installs exactly one adaptation keyed to the clearing hero and applies the +25% drop bias; star conditions from §2G are evaluated and persisted; dying ends the run with the D10 keep/lose split.

**Phase 4 — Spectral Echoes.** `EchoDirector.gd` per §2B: record manual casts, cap 12, per-(stage,hero) overwrite, victory-only persistence; playback 65% potency, ≤ 3.5 m snap, skip-if-no-target, star-tracking exclusion (D9).
*Gate 4 (headless):* a recorded Brute run spawns a functional Leap Slam echo in a subsequent Rogue run at the exact room/time window; echo timestamps are unaffected by `Engine.time_scale` dips; serialization round-trip.

**Phase 5 — Main Hub UI & Polish.** `MainHub.tscn`: 3 hero cards (weapon tier, stars, Grudge warning), Forge drawer (1-tap Absorb/Salvage, evolution tree nodes, D13 unlock gate), floating damage numbers, hit-stop with the §2B caveat, stained-glass lighting within the mobile perf budget.
*Gate 5 (headless + scene):* hub flows (brief → commit → run → summary → hub) complete with no orphaned state; Forge locked before first boss kill.

**Phase 6 — Device Verification (manual, not headless).**
*Gate 6 checklist (Galaxy S24 Ultra, adb logging):* stable 60 fps in Room 4 and the boss fight; telegraphs readable at 2400×1080 and 19.5:9; one-thumb reach: stick never conflicts with skill buttons; Echo actors visible but never occluding enemy telegraphs; a full run starts and ends with zero errors in `adb logcat`; battery/heat sane over 3 back-to-back runs.

### 4. Automated Verification Command
```bash
godot --headless --path . -s res://tests/test_core_systems.gd
```
All assertions (hero-lock, weapon-class enforcement, Rogue threshold switching, Grudge rotation, star persistence, boon run-scope, echo round-trip, stop-threshold timing) must exit `0` before a phase is declared complete. **Headless gates cannot verify feel** — Phase 6 is not optional.

---

## 4. Open Tunables (first playtest agenda)
1. Stop grace 0.08 s vs. instant-cancel feel with real thumbs.
2. Cleave cadence 0.9 s vs. Crimson Guard upkeep at 30% cap.
3. Rogue bow 10.5 m reach vs. Spitter 8 m range (kiting window).
4. Boon magnitudes (±12%/±15% classes) vs. 4-room difficulty curve.
5. Vespera 600 HP vs. level-1 weapons: target ~2.5–3 min fight.
6. Echo 65% potency: should feel like backup, never like autopilot.
