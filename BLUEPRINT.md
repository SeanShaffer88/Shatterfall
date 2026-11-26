# SHATTERFALL — Design & Build Blueprint v2.1

**Release title:** *Shatterfall* (the former "Shattered Reliquary" codename is retired; do not use it anywhere, including filenames).

**What this document is:** a complete design + build spec for an AI coding agent (Claude Code / Codex / Cursor) and for humans. Everything needed to build the vertical slice is on this page. Where an earlier draft left ambiguity, there is now an explicit decision, marked **[D#]**. Tunable numbers are in tables; tune them, never silently.

**v2.1 changes:** D25–D40 added (damage formula, naming, skill aiming, ranges, run flow, drop/forge economy, boss/enemy sheets, echo recording/playback, time rule, star retune, test tooling, renderer, export). D2, D12, D19, D22 and D23 were revised in place; each revised entry names the decision that revised it. Section text below already reflects every revision.

---

## 0. Decision Log (locked decisions)

| # | Question | Decision |
|---|----------|----------|
| D1 | Orientation | **Landscape.** Base resolution 2400×1080, `canvas_items` stretch, aspect `expand`. **Two-thumb** layout: virtual stick bottom-left, 3 skill buttons bottom-right. |
| D2 | Renderer | **Mobile renderer** (Vulkan) for **all** builds, including Windows dev builds, so lighting and art are always judged on the shipping renderer. *(rev. D39)* |
| D3 | Camera | Fixed **isometric 3/4** follow: yaw **45°**, pitch **55°**, boom length **30 m**, FOV **30°** (flat, long-lens look; reference: Hunt Royale boss hunts), target lock with 0.15 s smoothing. No player zoom, no rotation. Stick input is turned by the yaw so "up" is up on screen. *(rev. Q-11)* |
| D4 | Dimension / units | Full 3D (`CharacterBody3D`, `Area3D`, `Vector3`). All tuning in **meters and m/s**. No 2D px/s units anywhere. |
| D5 | Weapon binding | **Hero-locked weapons.** Brute = Greataxe, Rogue = Daggers *and* Shortbow (two classes, both Rogue-only; mode switches with range), Magi = Staff. Off-class drops are marked "Not usable" in inventory and can only be salvaged. |
| D6 | Run length | Target **6–9 minutes** per full stage run (4 rooms + boss). |
| D7 | Star loop | Each stage has 3 stars, one per hero. A star is awarded **only on a run cleared with that hero** that also satisfies its condition. Full star loop = **3 clears per stage** (one per hero). Stars persist forever in the save. |
| D8 | Minimum device | Samsung Galaxy S24 Ultra (Snapdragon 8 Gen 3 / Adreno 750, Android 14) at **60 fps**. Engineering floor: Snapdragon 480-class at 30 fps must not crash and must stay playable. |
| D9 | Echo vs stars | Echo assists may damage enemies and help clear waves, but **echo damage/kills never count toward star objective tracking**. Indirect help (an echo's pull or debuff) is allowed. |
| D10 | Death | Hero death **ends the run** immediately (summary screen). Kept forever: absorbed XP, evolution progress, shards, essences, inventory drops. Lost: run boons. Echoes are **not** recorded on failed runs. No mid-run checkpoints. |
| D11 | Grudge lifecycle | Exactly **one active adaptation per boss**, **replaced** (never stacked) each time that boss is cleared. No adaptation exists before the first clear. Drop-rate bias for the other two heroes' weapon classes: **×1.25 class weight** (D30), active until the next clear. |
| D12 | Echo cap | Records manual casts of effect skills (D34), keeping the **first 2 casts per wave** (max 20 per run). Only the **last completed run per (stage, hero)** is stored; a new clear overwrites that hero's entry. *(rev. D34)* |
| D13 | Onboarding | Forge UI unlocks after the first boss kill. Before that, the inventory is usable (drops accumulate) but the Forge drawer shows a locked tooltip. |
| D14 | Boon persistence | Boons are run-only. They are lost on death **and** do not carry into the next run after a win. |
| D15 | Save format | All JSON files carry `"schema_version": 1`. Saves are atomic (write temp file, then rename). |
| D16 | Sub-stats | Absorb rotation is `+ATK`, `+CRIT`, `+HP` (no element system in the slice). `+ATK` = +1% weapon ATK per stack; `+CRIT` = +1% crit chance per stack (crit = ×2 damage, base 15%); `+HP` = +2 max HP per stack. Each sub-stat caps at **20 stacks** per weapon. Rotation order is fixed ATK→CRIT→HP and the next index is stored on the weapon. |
| D17 | Weapon power | `rarity` = quality band 1–3 (drives drop rarity, base XP, salvage yield and mesh/glow preset). Level-1 ATK per class: Greataxe 20, Daggers 6, Shortbow 11, Staff 14. ATK grows ×1.06 per weapon level; each evolution stage multiplies ATK by ×1.20 (D25). |
| D18 | Weapon slots | Strictly **one main weapon per weapon class per hero**. The Rogue owns mains for two classes and both are equipped at once (range swap is automatic). Every other same-class drop is fodder; off-class drops cannot be absorbed at all (D5). |
| D19 | Drops & essence | Stage 1: each cleared room drops one weapon with chance **60%**; Vespera guarantees 1 weapon + 1 Vespera essence per clear. Class weighting, rarity and drop level per D30. Monster essences drop only from bosses in the slice. *(rev. D30)* |
| D20 | Inventory | Single save slot; unlimited fodder items in the slice (no inventory cap); Absorb/Salvage happen only in the Hub, never mid-run. |
| D21 | Echo inheritance | Echo effects always resolve against the recording hero's **current** weapon state at playback time — evolutions retroactively strengthen old echoes. `weapon_id` in the echo record is informational only. |
| D22 | Engine & tooling pin | Godot **4.7.2 stable** (pinned, no minor-version drift — the version installed on the dev machine). Headless tests use a hand-rolled `SceneTree` script — no GUT or plugin dependencies. Loading `data/*.json` **fails loud**: malformed JSON aborts with a precise file/field error, never silent defaults. *(rev. D38)* |
| D23 | Save slots | Exactly one save slot: `user://save.json`. Echoes live in one file per stage, `user://echoes/<stage_id>.json`, keyed by hero. *(rev. D34)* |
| D24 | Package identity | Package id `com.seanshaffer88.shatterfall`, app version `0.1.0`, display name **Shatterfall**. English-only; no i18n scaffolding. |
| D25 | Damage formula | `ATK_eff = class_base × 1.06^(level−1) × 1.20^(evo_stage−1) × (1 + 0.01 × atk_stacks)`. `damage = round(ATK_eff × coeff × boon_mult × mark_mult × crit_mult)`, minimum 1. `coeff` is per attack/skill in `heroes.json`, defined as the §2D level-1 damage ÷ class base ATK, so a level-1 base weapon reproduces the §2D numbers exactly. Brute skills use the Greataxe, Magi skills the Staff, Rogue skills the weapon of the current mode (Adaptive Barrage) or Daggers (Shadow Vault bonus). All randomness uses seeded `RandomNumberGenerator` streams owned by `GameState` — one each for combat, loot and boons — seeded from a per-run `run_seed`. Tests set seeds explicitly. |
| D26 | Naming & tree shape | `rarity` (1–3) is the drop quality band; `evo_stage` (1 = Base, 2, 3) is evolution progress. The word "tier" is retired. Evolutions are **linear** in the slice (Base → Stage 2 → Stage 3); branching trees are post-slice. Level does **not** reset on evolution. |
| D27 | Skill input | **Tap to cast, auto-aimed**; skills can be cast while moving. Directional skills use stick direction if the stick is held, else the rules in §2D. Cast locks: `CASTING_SKILL` roots the hero for the skill's lock time (§2D) unless the skill sets its own velocity; `DASHING` for Shadow Vault (0.2 s); Phase Blink is an instant teleport. Presses during a lock are buffered for 0.15 s. Cooldowns start on cast. After a lock the state returns to `MOVING` and the 0.08 s attack grace applies again. |
| D28 | Ranges & targeting | Primary attacks only fire when the target is within reach: Brute 3.2 m, Rogue daggers 3.0 m, Rogue bow 10.5 m, Magi 14 m. Target = nearest living enemy in the current room (line of sight ignored, except that Vespera's shard wall blocks projectiles). Rogue mode uses **hysteresis**: Bow→Daggers at ≤ 2.6 m, Daggers→Bow at > 3.0 m. Dagger flurry cadence 0.5 s (rebalanced from 0.35 s). |
| D29 | Run flow | HP carries between rooms; each room clear heals **15% max HP**. Hero gets 0.4 s invulnerability after taking a hit. Pause (top-right) offers Resume / Abandon Run; abandoning follows D10 death rules. App backgrounded → auto-pause. Inventory drops are saved at **every room clear** and at run end. A force-kill mid-run counts as an abandoned run on relaunch: drops up to the last room clear are kept; there are no stars, echoes or grudge changes. Stars, grudge and echoes are written only on victory. |
| D30 | Drop math | Class weights per drop: the run hero's classes share weight 60 (Rogue 30/30), the other valid classes share 40 equally. The Grudge bias multiplies the other two heroes' class weights by 1.25, then weights are renormalized; drop chance is unchanged. Rarity roll 70/25/5 (rarity 1/2/3). Drop level: room drops 1, Vespera's drop 2. `base_xp` by rarity 20/35/60. Essence is an inventory currency only; weapons carry no infused essence. |
| D31 | Forge economy | `xp_to_next(level) = round(40 × 1.3^(level−1))`, cap level 10 (248 XP to reach L5, 1281 to reach L10). Absorb XP = `base_xp + level × 25`. Salvage = `2 + rarity` class shards. Stage 2: level 5 + 15 shards. Stage 3: level 10 + 40 shards + 1 Vespera essence (all consumed). At level cap, Absorb still grants the sub-stat and discards the XP; the UI warns first. **Pacing target:** Stage 2 ≈ 5 clears with that hero, Stage 3 ≈ 20 (Rogue roughly twice as long per weapon — tunable #8). |
| D32 | Vespera | Full sheet in §2E. 1600 HP; immune to stun, pull and knockback. Fight = boss activation (1.5 s after the door locks behind the hero) → boss death. Adaptation semantics in §2H. **Mirage Veil is a fair challenge:** the blink restarts the active telegraph from the new position with full warning time — the attack is delayed, never unwarned. |
| D33 | Enemies & traps | Full sheet in §2E (contact rate, projectile speed, Bulwark bash, spawn rules, trap cycle). |
| D34 | Echo recording | Recorded skills: Leap Slam, Rending Roar, Vortex Cleave, Adaptive Barrage, Shatter Mark, Gravity Well, Shatter Nova. Shadow Vault and Phase Blink (movement-only) are not recorded. Events are **wave-relative** (`room`, `wave`, `t` = seconds since that wave spawned; boss phase 1 = wave 0, phase 2 = wave 1). Positions are room-local, relative to each room's `EchoAnchor` (`Marker3D`). Keep the first 2 casts per wave. One file per stage, keyed by hero; no `client_version` field. |
| D35 | Echo playback | Per-skill behavior table in §2B. Values (damage, heal, durations) ×0.65; radii, pulls and knockback unchanged; echoes never crit. A cyan ground cue appears **1.0 s** before each echo cast *(rev. D41: room to conduct it)*. At most 2 echo actors at once: extra events wait up to 1.5 s, then drop. If the wave ends before `t`, the event drops. Grudge adaptations apply to echo hits; recoil is ignored (echoes have no HP). |
| D36 | Time rule | Every gameplay timer (cooldowns, statuses, wave/room elapsed, echo `t`) accumulates the `delta` passed to `_physics_process`, which `Engine.time_scale` scales. Hit-stop therefore pauses all of them proportionally in both recording and playback, so echo timing is consistent by construction. Nothing gameplay-relevant uses wall-clock time. |
| D37 | Stars (Stage 1) | Cleave Master: Crimson Guard active ≥ **50%** of the fight. Close Work: ≥ **60 dagger hits** in the fight (each flurry = 2 hits). Untouched Prism: Room 2 from entry to door unlock with **zero HP loss** (hits fully absorbed by the Arcane Glass Barrier do not count). Rending Roar grants one Crimson Guard stack. |
| D38 | Test tooling | Before tests on a fresh clone, run `godot --headless --path . --import` — verified on 4.7.2: without it, `class_name` lookups fail. Autoloads are present in `root` under `-s` after import (verified). The runner `res://tests/test_core_systems.gd` extends `SceneTree`, runs the suites under `tests/phase_N/` and exits with `quit(0)` / `quit(1)`. Physics-dependent tests step logic with a fixed 1/60 s delta, never wall time. On Windows, call the main `Godot_v4.7.2-stable_win64.exe` with `--headless` (the `_console` wrapper failed with CreateProcess error 193 in the agent sandbox). |
| D39 | Desktop renderer | See D2: Mobile renderer everywhere. Forward+ only for one-off comparisons, never for art or performance sign-off. |
| D40 | Export ownership | Phase 5 creates `export_presets.cfg`: Android (arm64-v8a only, sensor-landscape, D24 identity, debug keystore from editor settings) and a Windows dev preset. Keystores and signing passwords are never committed (`.gitignore`). Phase 6 prerequisites: Godot 4.7.2 export templates, OpenJDK 17, Android SDK as listed in the Godot 4.7 export docs. |
| D41 | Pillar 1 — Echoes as partners | Echoes are the game's signature: **co-op with your own past runs**. (a) **Echo Conducting** (Battleheart-style): the Echo cue lasts **1.0 s** (rev. D35); tapping open arena ground (not a HUD control) during a cue moves that Echo's cast to the tapped point, up to 6 m from the resolved point. One conduct per Echo. (b) **Twin Reliquaries** (raid-style two-body mechanic, §2B): in phase 2 Vespera raises two glass pillars 10 m apart every 20 s; both must be struck within 1.5 s of each other, within 6 s, or she gains **Shatter Shield** (−75% damage taken for 8 s). Solo play can solve it with ranged attacks or Leap Slam; an Echo hit counts as one of the two strikes. Failing is never fatal. Built in Phase 4. |
| D42 | Pillar 2 — Restore the Reliquary | The Hub (Phase 5) is a shattered cathedral rebuilt between runs, instead of chests or cards. New currency **Glass**: +3 per room cleared, +10 per Vespera kill, +1 per salvage; kept on death (D10). Six windows restored in order (§2I), each with a real, permanent unlock. Window costs 20 / 40 / 60 / 80 / 100 / 150 Glass (450 total ≈ 20 runs, matching D31 pacing). Restored windows pour stained-glass light into the Hub and are saved in `user://save.json`. |
| D43 | Pillar 3 — A world with a voice | Text barks, no voice-over in the slice. **Vespera** speaks her grudge (lines keyed to the last clearing hero and adaptation; run start, phase 2, first adaptation trigger, hero death, her defeat). **The Reliquary** narrates sparingly (first run, first evolution, each restored window, deaths, about one room clear in three). Lines live in `data/barks.json`; at most one line per 12 s; shown 3 s bottom-center, above the controls; never covers a telegraph; skipped when the same line played within the last 3 runs. Rooms **assemble from falling glass** as you approach (AD13). Built in Phase 5. |

Numbers marked "tunable" are starting points for one 6–9 minute run; tune by playtest, never silently.

---

## 1. Game Design Document

### High Concept
**Title:** *Shatterfall*
**Genre:** Solo-Hero Action Dungeon Crawler / Weapon-Evolution RPG
**Platform:** Android first (offline, no ads, no purchases), landscape, two-thumb: virtual stick on the left, 3 manual skill buttons on the right. Windows desktop build for development only.
**Visual Identity:** Painted Stained-Glass Reliquary — obsidian and charcoal cathedral stone pierced by crimson, amber and violet stained-glass light; crisp character silhouettes; glowing crystalline weapon evolutions; translucent stained-glass Echo spirits. **Visual language is normative in `ART_DIRECTION.md` (AD1–AD12)**; its per-hero emissive rules and color coding carry gate hooks (see that document §5).

### Core Gameplay Loop
1. **Stage Briefing & Hero Commit (Main Hub):** inspect hazards, the 3 hero-specific stars, your recorded Spectral Echoes for this stage, and Vespera's current Grudge Adaptation; commit **one** hero:
   - **Brute** — Sustain & Cleave Tank. Sweeping melee arcs; hitting **2+ targets** grants **Crimson Guard** (shield). Skills: Leap Slam, Rending Roar, Vortex Cleave.
   - **Rogue** — Range-Adaptive Skirmisher. Auto-switches **Shortbow** (range) / **Twin Daggers** (melee) by distance to the nearest enemy (D28 hysteresis). Skills: Shadow Vault, Adaptive Barrage, Shatter Mark.
   - **Magi** — Zone Control & AoE Burst. Homing **Prism Bolts**; **Arcane Glass Barrier** absorbs one hit and refreshes every 6 s (tunable). Skills: Phase Blink, Gravity Well, Shatter Nova.
2. **Room Clearing & Boon Draft:** move freely to dodge telegraphed attacks; **stop moving to auto-attack** the nearest enemy in reach. Clear waves room by room (HP carries over, 15% heal per room clear — D29); before Room 3, draft **1 of 3 run boons**.
3. **The Three Signature Hooks:**
   - **Hero-Specific Stars (D7, D37).**
   - **Spectral Echo Assists:** successful clears record your skill casts as a lightweight ghost timeline. Replaying the stage with a *different* hero spawns translucent cyan Echoes that re-cast those skills at the recorded wave-relative moments, each announced by a 1.0 s ground cue so you can combo off them or **conduct** them to a new spot (D41). Vespera's Twin Reliquaries need two bodies — you and an Echo (§2B).
   - **Boss Grudge & Adaptation (D11):** clearing Vespera with a hero installs one defensive adaptation against that archetype and boosts drops for the other two.
4. **Same-Type Absorption & Build-Up Forge (D5, D26, D31):** weapons never break. Same-class drops can be **Absorbed** (XP + a small permanent sub-stat) or **Salvaged** (class shards) to reach linear **Build-Up** evolutions (§2C).

### Fail State (D10, D29)
Hero death or Abandon Run ends the run. The summary screen shows: stars (victory only, with progress toward unmet conditions, e.g. "Guard uptime 41% / 50%"), drops kept, forge progress retained, boons lost.

---

## 2. Core Systems — Spec & Numbers

### A. Stop-to-Attack & Rogue Range-Switch Controller (`HeroController.gd`)

One threshold set, in meters:

- Input deadzone: stick magnitude `> 0.18` counts as movement intent.
- Full stop: velocity `<= 0.25 m/s`.
- Attack-start grace buffer: **0.08 s** of sustained near-stop before auto-attack begins (kills micro-twitch attacks, stays under the 0.10 s gate).
- Re-acquiring movement is **instant** (grace applies only to attack start).
- Reach and Rogue hysteresis per D28; skill locks per D27.

```gdscript
class_name HeroController
extends CharacterBody3D

enum HeroClass { BRUTE, ROGUE, MAGI }
enum CombatState { MOVING, STOPPED_ATTACKING, CASTING_SKILL, DASHING }
enum RogueMode { BOW, DAGGERS }

signal rogue_mode_changed(mode: RogueMode)   # drives the AD3 trim flash

@export var hero_class: HeroClass = HeroClass.BRUTE
@export var move_speed: float = 4.2          # m/s, tunable
@export var input_deadzone: float = 0.18

# Values mirror data/heroes.json; the JSON is authoritative at runtime.
const STOP_VELOCITY: float = 0.25            # m/s
const GRACE_TIME: float = 0.08               # s before auto-attack starts
const DAGGER_ENTER: float = 2.6              # Bow -> Daggers at <= 2.6 m (D28)
const DAGGER_EXIT: float = 3.0               # Daggers -> Bow at > 3.0 m (D28)
const BOW_RANGE: float = 10.5
const BRUTE_RANGE: float = 3.2
const MAGI_RANGE: float = 14.0

var state: CombatState = CombatState.MOVING
var input_vector: Vector2 = Vector2.ZERO
var attack_timer: float = 0.0
var stop_timer: float = 0.0
var lock_timer: float = 0.0                  # remaining CASTING_SKILL / DASHING time (D27)
var rogue_mode: RogueMode = RogueMode.BOW
var current_target: Node3D = null

func _physics_process(delta: float) -> void:
	if state == CombatState.CASTING_SKILL or state == CombatState.DASHING:
		lock_timer -= delta
		if lock_timer <= 0.0:
			state = CombatState.MOVING
			stop_timer = 0.0
			velocity = Vector3.ZERO          # a lock never leaves leftover leap/dash momentum
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

func begin_lock(lock_state: CombatState, duration: float, lock_velocity: Vector3) -> void:
	state = lock_state
	lock_timer = duration
	velocity = lock_velocity                 # Vector3.ZERO roots the hero

func _process_auto_attack(delta: float) -> void:
	current_target = _find_nearest_enemy()   # nearest living enemy in the current room
	if not is_instance_valid(current_target):
		return

	var to_target := current_target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	if hero_class == HeroClass.ROGUE:
		_update_rogue_mode(dist)
	if dist > _max_range():
		return                               # out of reach: no swing (D28)

	rotation.y = lerp_angle(rotation.y, atan2(to_target.x, to_target.z), 18.0 * delta)
	attack_timer -= delta
	if attack_timer <= 0.0:
		_execute_primary_attack()

func _update_rogue_mode(dist: float) -> void:
	var next := rogue_mode
	if rogue_mode == RogueMode.BOW and dist <= DAGGER_ENTER:
		next = RogueMode.DAGGERS
	elif rogue_mode == RogueMode.DAGGERS and dist > DAGGER_EXIT:
		next = RogueMode.BOW
	if next != rogue_mode:
		rogue_mode = next
		rogue_mode_changed.emit(rogue_mode)

func _max_range() -> float:
	match hero_class:
		HeroClass.BRUTE:
			return BRUTE_RANGE
		HeroClass.ROGUE:
			return DAGGER_EXIT if rogue_mode == RogueMode.DAGGERS else BOW_RANGE
		_:
			return MAGI_RANGE

func _execute_primary_attack() -> void:
	match hero_class:
		HeroClass.BRUTE:
			attack_timer = 0.9
			_fire_cleave_arc()
		HeroClass.ROGUE:
			if rogue_mode == RogueMode.DAGGERS:
				attack_timer = 0.5
				_fire_dagger_flurry(current_target)
			else:
				attack_timer = 0.55
				_fire_bow_arrow(current_target)
		HeroClass.MAGI:
			attack_timer = 0.7
			_fire_prism_bolt(current_target)
```

**Rogue swap rule (normative, D28):** Bow→Daggers when the nearest enemy is `<= 2.6 m`; Daggers→Bow when it is `> 3.0 m`; no attack beyond 10.5 m (walk closer). The first evaluation of a run starts in Bow mode. Every mode change emits `rogue_mode_changed` exactly once.

**Camera rig (D3):** a top-level pivot turned 45° about the vertical follows the hero (0.15 s smoothing); its `Camera3D` sits on a 30 m boom at pitch −55°, FOV 30°, fixed orientation. `HeroInput` rotates screen-space input by −45° before it reaches `input_vector`, so this §2A code stays world-space. Verify the hero and the bottom UI never overlap at 2400×1080 and at 19.5:9 (S24 Ultra native is 3120×1440; test 16:9 and 19.5:9 crops).

### B. Spectral Echo System (`EchoDirector.gd`)

Intent-anchored keyframes, not frame recording.

**Record (D12, D34):** manual casts of the seven effect skills (not auto-attacks, not Shadow Vault or Phase Blink). Each event stores room index, wave index, `t` (seconds since that wave spawned, D36), room-local hero position and target point (relative to the room's `EchoAnchor`), skill id, and for Adaptive Barrage the mode. Keep the **first 2 casts per wave** (max 20 per run). Save only on stage **victory**; the new clear replaces that hero's entry. Nothing is saved on failed or abandoned runs (D10, D29).

**Schema (`user://echoes/stage_01_sunken_nave.json`, one file per stage — D23):**
```json
{
  "schema_version": 1,
  "stage_id": "stage_01_sunken_nave",
  "echoes": {
    "BRUTE": {
      "weapon_id": "cinderheart_maul",
      "events": [
        { "room": 0, "wave": 0, "t": 2.4, "pos": [1.2, 0.0, -3.5], "target": [1.2, 0.0, -7.5], "skill": "LEAP_SLAM" },
        { "room": 2, "wave": 1, "t": 4.1, "pos": [0.0, 0.0, 0.0], "target": [0.0, 0.0, 0.0], "skill": "VORTEX_CLEAVE" },
        { "room": 3, "wave": 0, "t": 6.0, "pos": [2.0, 0.0, 1.0], "target": [6.0, 0.0, 1.0], "skill": "ADAPTIVE_BARRAGE", "mode": "BOW" }
      ]
    }
  }
}
```
`weapon_id` is informational only (D21).

**Playback (normative, D35):** while hero X plays, `EchoDirector` loads the saved entries of the **other two** heroes. For the active (room, wave), when `wave_elapsed >= t − 1.0` it resolves the target:
1. the nearest living enemy within **3.5 m** of the recorded target point; else
2. the nearest living enemy in the room within the skill's reach of the recorded position; else
3. skip the event silently.

It then shows a 1.0 s cyan ground cue at the resolved point, and at `t` spawns a `SpectralEcho` actor (translucent stained-glass Fresnel shader, **cold cyan only** — AD6) that casts the skill and dissolves into glass shards. At most 2 echo actors exist at once; a third event waits up to 1.5 s for a slot, then drops. If the wave ends before `t`, the event drops. Echoes fire in the boss room too. Players with no saved echoes from other heroes see "No echoes yet — clear this stage with another hero" in the Stage Briefing.

**Echo effects (×0.65 values; radii/pull/knockback unchanged; never crit; resolved against the recording hero's current weapon — D21):**

| Skill | Echo behavior |
|---|---|
| Leap Slam | Echo appears at the resolved point and slams: 65% damage, 0.33 s stun (bosses immune). |
| Rending Roar | Enemies within 6 m of the echo deal −30% damage for 3.25 s. Grants **no** Crimson Guard to anyone. |
| Vortex Cleave | 65% damage sweep with pull, centered on the echo at the resolved point. |
| Adaptive Barrage | Uses the recorded mode: Bow = 5 homing arrows, Daggers = 4 slices; 65% damage. |
| Shatter Mark | Marks the resolved target for 5.2 s (+25% damage taken). A marked kill heals the **current** hero 6 HP. |
| Gravity Well | 3 m pull zone for 2.6 s, 65% tick damage (bosses: damage only). |
| Shatter Nova | 4 m nova, 65% damage, knockback (bosses immune to knockback). |

Echo damage and kills are **excluded from star tracking** (D9). Grudge adaptations apply to echo hits, except Spiked Carapace recoil (echoes have no HP).

**Echo Conducting (D41):** while a cue is showing (1.0 s), a tap on open arena ground — not on the stick, a skill button or another HUD control — moves that Echo's cast point to the tap, clamped to 6 m from the resolved point. The cue ring turns gold to confirm. One conduct per Echo; a conducted Echo ignores smart snap. Conducting never changes damage, timing or star rules (D9).

**Twin Reliquaries (D41):** in phase 2, every 20 s Vespera raises two glass pillars on opposite sides of the arena, 10 m apart, each with a 6 s AD7 countdown ring. Each pillar breaks on any single hit (hero or Echo, melee or ranged). Breaking both within 1.5 s of each other within the 6 s shatters them harmlessly. Otherwise Vespera gains **Shatter Shield** for 8 s (−75% damage taken; stacks never, refreshes). Pillars are targetable enemies for auto-attack and Echo snap, but never count toward stars. Tunables: interval, spacing, window, shield %, shield duration.

**Time rule (D36):** all echo timers use scaled physics `delta`. An `Engine.time_scale` hit-stop dip during recording or playback shifts nothing in game time, so an event recorded at `t` fires at game-time `t` (± one physics tick) regardless of dips in either run.

### C. Same-Type Absorption & Build-Up (`WeaponForge.gd`)

**Data model:** `uid`, `weapon_id`, `weapon_class` (`GREATAXE`, `DAGGERS`, `SHORTBOW`, `STAFF`), `owner_hero` (hero-locked, D5), `rarity` (1–3, D17/D26), `evo_stage` (1–3), `level`, `xp`, `atk_stacks`, `crit_stacks`, `hp_stacks`, `next_substat` (0=ATK, 1=CRIT, 2=HP). `xp_to_next` is derived, not stored.

**Slots & power (D17, D18, D25):** one main weapon per weapon class per hero; the Rogue's two mains are both equipped and swap automatically. `ATK_eff = class_base × 1.06^(level−1) × 1.20^(evo_stage−1) × (1 + 0.01 × atk_stacks)`. Hero max HP = base HP + 2 × `hp_stacks` summed over that hero's equipped mains. Crit chance = 15% + `crit_stacks`% of the attacking weapon.

**Rules (normative):**
- `can_absorb(main, fodder)` = same `weapon_class` AND different `uid` AND `fodder.owner_hero == main.owner_hero`.
- **Absorb:** adds `base_xp(rarity) + fodder.level × 25` XP to `main` (`base_xp` = 20/35/60 — D30), levels up as many times as the XP allows (cap 10; excess discarded at cap), and adds +1 to the sub-stat at `next_substat` (skipping a capped sub-stat; no gain once all three are at 20), then advances `next_substat`. The fodder is destroyed.
- **XP curve (D31, tunable):** `xp_to_next(level) = round(40 × 1.3^(level−1))`.
- **Salvage:** destroys the fodder and grants `2 + rarity` class shards (`GREATAXE_SHARD`, …).
- **Build-Up trigger:** `main.level >= recipe.req_level` AND shards ≥ `recipe.shard_cost` AND (for Stage 3) owns `recipe.boss_essence_id`. Evolving consumes the shards/essence, increments `evo_stage`, mutates `weapon_id`, swaps mesh/VFX, and sets the evolution's visual preset. Level and sub-stats are kept.
- **Off-class drops (D5):** visually marked "Not usable — salvage only" in the inventory.

**Evolution line (linear, D26; all numbers tunable):**

| Hero | Class | Base | Stage 2 (lvl 5, 15 shards) | Stage 3 (lvl 10, 40 shards + Vespera essence) |
|---|---|---|---|---|
| Brute | Greataxe | Ashen Cleaver | Cinderheart Maul | Vesperglass Executioner |
| Rogue | Daggers | Nightbite Pair | Whispershard Fangs | Lamplighter Fangs |
| Rogue | Shortbow | Yewline Bow | Vinewhisper Bow | Choirglass Bow |
| Magi | Staff | Lorelight Rod | Prismheart Staff | Reliquary Nova Staff |

### D. Hero Kits, Cooldowns, Damage (all tunable)

Damage numbers are level-1 base-weapon values; `coeff` = value ÷ class base ATK (D25).

| Hero | HP | Primary | Skills (cooldown · lock — effect · aiming) |
|---|---|---|---|
| Brute | 140 | Cleave arc 22 dmg, 0.9 s, 3.2 m / 110° | **Leap Slam** (8 s · 0.45 s — 5 m leap, 30 dmg, 2.5 m AoE, 0.5 s stun · lands on the nearest enemy within 5 m, else 5 m along stick/facing) · **Rending Roar** (12 s · 0.3 s — 6 m radius, −30% enemy damage 5 s, grants one Crimson Guard stack · self-centered) · **Vortex Cleave** (15 s · 0.5 s — 7 m sweep, 45 dmg, slight pull · self-centered) |
| Rogue | 100 | Daggers 2×7 dmg, 0.5 s, 3.0 m · Bow 12 dmg, 0.55 s, 10.5 m | **Shadow Vault** (7 s · 0.2 s dash — 4 m, 0.25 s invuln, next dagger pair +50% · stick direction, else directly away from the nearest enemy) · **Adaptive Barrage** (10 s · 0.4 s — bow: 5 homing arrows 8 dmg; daggers: 4 slices 10 dmg · current mode, nearest enemy) · **Shatter Mark** (14 s · 0.15 s — target takes +25% dmg 8 s; killing a marked enemy heals 10 · nearest enemy) |
| Magi | 110 | Prism Bolt 15 dmg homing, 0.7 s, 14 m | **Phase Blink** (6 s · instant — 4 m teleport, refreshes Arcane Glass Barrier · stick direction, else directly away from the nearest enemy) · **Gravity Well** (12 s · 0.2 s — 3 m pull zone, 4 s, 6 dmg/s · centered on the nearest enemy within 8 m, else 3 m ahead) · **Shatter Nova** (16 s · 0.3 s — 4 m nova, 40 dmg, knockback · self-centered) |

- **Crimson Guard:** each cleave that hits 2+ enemies, and each Rending Roar, adds a shield stack = 10% max HP (cap 3 stacks = 30%). It lasts until broken or until 6 s pass without a qualifying hit or Roar (tunable). Guard absorbs damage before HP, including Spiked Carapace recoil.
- **Arcane Glass Barrier:** absorbs one hit fully; refreshes 6 s after it breaks, or immediately on Phase Blink.
- **Hit invulnerability (D29):** 0.4 s after the hero takes damage.

### E. Enemies, Waves & Boss (tunable)

| Enemy | HP | Behavior |
|---|---|---|
| Crawler | 30 | Melee chaser, 2.0 m/s; contact 8 dmg, at most once per 1.0 s per Crawler. |
| Spitter | 22 | Holds 5–8 m from the hero (retreats at 1.6 m/s when closer than 5 m); 0.4 s wind-up glow, then a straight projectile at 9 m/s, 6 dmg, every 1.8 s. |
| Bulwark | 60 | Walks 1.4 m/s, turns 120°/s toward the hero; frontal shield (±60° of facing) gives 50% damage reduction. Shield bash: 1.8 m reach, 12 dmg, 0.8 s telegraph, 3 s cooldown. |
| Spike trap | — | Room 3 only: 4 fixed 2×2 m panels. Cycle 4.0 s = 1.0 s warning → 0.4 s active (10 dmg once per activation) → 2.6 s idle; panels A/C run 2 s offset from B/D. Hurts the hero only; inactive after the room clears. |

**Wave rules:** the next wave spawns 1.0 s after the previous wave's last enemy dies, each spawn preceded by a 1.0 s spawn telegraph; spawn points are ≥ 6 m from the hero. All telegraphs use the AD7 crimson-white alarm language.

**Stage 1 — The Sunken Nave** (rooms 1→4, then Vespera; target 6–9 min, D6):
- Room 1: 1 wave — 3 Crawlers + 1 Spitter.
- Room 2: 2 waves — 4 Crawlers → 2 Spitters + 2 Crawlers.
- Room 3: 2 waves + spike traps — 2 Crawlers + 2 Spitters → 1 Bulwark + 3 Crawlers.
- Room 4: 3 waves — 3 Spitters + 2 Crawlers → 2 Bulwarks → 4 Crawlers + 2 Spitters.
- Room doors unlock only when the room's last wave is cleared. Each room clear heals 15% max HP (D29) and rolls the D19/D30 drop.

**Drops & essence (D19, D30):** each cleared room drops one weapon with chance **60%**; class weights 60 for the run hero's classes (Rogue 30/30) and 40 shared equally by the other valid classes, with the Grudge ×1.25 bias applied before renormalizing; rarity 70/25/5. Vespera guarantees **1 weapon (level 2, same weighting) + 1 Vespera essence** per clear. Inventory is uncapped and Absorb/Salvage happen only in the Hub (D20).

**Boss Vespera (D32):**
- 18×18 m arena; the door locks behind the hero; the boss activates 1.5 s later (fight timer starts).
- 1600 HP. Immune to stun, pull and knockback (those skills still deal their damage).
- Moves at 1.2 m/s, keeping 4–8 m from the hero. Picks her next attack every 2.5 s (phase 2: 1.8 s). No contact damage.
- **Sweep:** 120° cone, 5 m, 30 dmg, telegraph 0.9 s (phase 2: 0.65 s).
- **Glass-shard rain:** 3 circles of 1.8 m radius — one on the hero's position, two random within 4 m of the hero — 10 dmg each, telegraph 1.2 s (phase 2: 0.9 s).
- **Phase 2 (≤ 800 HP):** a one-time spawn of 4 Crawlers, plus a **shard wall** every 12 s: a 6 m × 0.6 m wall that appears 3 m from Vespera between her and the hero, lasts 5 s, blocks hero movement and all projectiles (hero and echo), with a 0.6 s rise telegraph.

### F. Boon List (run-only, D14)

Draft 1 of 3 before Room 3. Three unique offers are drawn from the pool using the boon RNG stream (D25); no duplicate offered. Same pool every run; re-picking across runs is allowed. Lost on death **and** after a win (D14).

| Boon | Effect |
|---|---|
| Crimson Surcharge | +12% damage |
| Glass Skin | +15 max HP and heal 15 |
| Tempest Heart | +10% move speed, +10% attack speed |
| Amber Ward | 15% less projectile damage taken |
| Second Wind | Once: dropping below 25% HP heals 40% (consumed on use) |
| Fracture Focus | Skill cooldowns −15% |

### G. Hero-Specific Stars — Stage 1 (D7, D9, D37)

Awarded only on a cleared run with the matching hero; every condition is code-verifiable. "Fight" = Vespera activation → death (D32).

| Star | Hero | Condition |
|---|---|---|
| Cleave Master ★ | Brute | Crimson Guard active (≥ 1 stack) for ≥ 50% of the fight |
| Close Work ★ | Rogue | ≥ 60 dagger-mode hits on any enemy during the fight (each flurry = 2 hits; echo hits never count) |
| Untouched Prism ★ | Magi | Zero HP lost from entering Room 2 to its door unlocking (Barrier-absorbed hits don't count) |

The run summary shows each unmet star's progress (D29 summary).

### H. Boss Grudge & Adaptation (D11, D32)

`GameState.get_last_clearing_hero("stage_01")` selects exactly one active adaptation; a new clear replaces it. None is active before the first clear.

| Beaten by | Adaptation | Effect |
|---|---|---|
| Brute | Spiked Carapace | Hero melee hits on Vespera (cleave, Leap Slam, Vortex Cleave, dagger hits, dagger-mode Barrage) reflect 15% of the damage dealt back to the hero. Crimson Guard absorbs recoil first; recoil never drops the hero below 1 HP. |
| Rogue | Mirage Veil | Every 8 s Vespera blinks 3 m sideways (random side, clamped to the arena). If a telegraph is active, it is cancelled and restarted from her new position with its **full** warning time. Projectiles already in flight continue on their path. |
| Magi | Runic Dampening | An AoE hits Vespera only if her center is within 70% of the effect's radius; duration effects on her (Gravity Well ticks, Shatter Mark) last 70% as long. |

Adaptations apply to echo hits as well (recoil excepted — D35). Drops are biased ×1.25 toward the other two heroes' weapon classes until the next clear (D11, D30). The Main Hub shows the current adaptation and a one-line counter tip on the hero-select cards.

---

### I. Restore the Reliquary (D42) — Phase 5 Hub

The Hub is a shattered cathedral. Six windows are restored in order with **Glass** (D42); each one lights part of the nave and grants one permanent unlock. All numbers tunable.

| # | Window | Glass | Unlock |
|---|---|---|---|
| 1 | Lantern Window | 20 | Room-clear heal 15% → 20% |
| 2 | Choir Window | 40 | Echo cap 2 → 3 casts per wave (D34) |
| 3 | Ember Window | 60 | Boon draft offers 4 instead of 3 |
| 4 | Ledger Window | 80 | Room drop chance 60% → 70% (D19) |
| 5 | Forge Window | 100 | Stage 3 evolutions cost 30 shards instead of 40 (D31) |
| 6 | Vesper Window | 150 + 1 Vespera essence | The slice's ending: Vespera's final line, the dais's full bloom (AD9) and a "Reliquary restored" title on the save |

Glass is earned and saved at the same moments as drops (D29): room clear (+3), Vespera kill (+10), salvage (+1). Restoration happens only in the Hub (like D20). The Hub shows the next window's cost and unlock in plain English.

### J. Barks and the narrator (D43) — Phase 5

`data/barks.json` holds every line, keyed by speaker (`VESPERA`, `RELIQUARY`), trigger and optional hero/adaptation. A `BarkDirector` picks lines with the boon RNG stream (D25), shows one at a time for 3 s bottom-center, respects the 12 s spacing and the 3-run repeat filter, and never draws over a telegraph's screen area. Vespera's grudge lines name the hero who last beat her ("You again, Brute. I grew spines for you."). The slice ships at least 4 lines per Vespera trigger and 3 per Reliquary trigger, all plain English.

## 3. Agent Workflow Blueprint — WFBP: Shatterfall, Godot 4.7 Vertical Slice

> Hand this section (and everything above it) to the coding agent as-is. Do **not** wrap it in an outer markdown fence — earlier drafts broke because of nested triple backticks.

### 1. Project Identity & Hard Constraints
- **Engine:** Godot **4.7.2 stable, pinned** (D22), **Mobile renderer** for every build (D2/D39); Android `arm64-v8a` + Windows dev build.
- **Package identity (D24):** id `com.seanshaffer88.shatterfall`, version `0.1.0`, display name **Shatterfall**, English-only — set in `project.godot` from Phase 1.
- **Orientation & UI:** **Landscape 2400×1080** base, `canvas_items` stretch, aspect `expand` (D1). Theme `#121318` background, crimson `#D92638` + jewel accents. Virtual stick bottom-left, 3 skill buttons bottom-right arc with radial cooldown rings, stats top-left, wave info top-right, pause top-right corner. Safe margins ≥ 48 px; verify at both 16:9 and 19.5:9.
- **Min device:** Galaxy S24 Ultra @ 60 fps (D8); floor = Snapdragon 480-class @ 30 fps, no crash.
- **Scope:** Stage 1 (*The Sunken Nave*, 4 rooms + Vespera), 3 heroes, Stop-to-Attack + 3 skills, Hero-Specific Stars, Spectral Echoes, Grudge Adaptation, Same-Type Absorption/Build-Up Forge. **No scope additions** — file an ambiguity as a question instead of inventing a system.
- **Art policy:** gray-box placeholder meshes + the one custom `stained_glass_echo.gdshader`; colors/lighting per Visual Identity and the locked rules in `ART_DIRECTION.md` (AD1–AD12), whose emissive hooks (AD2/AD3/AD4) must exist in `HeroActor.tscn` from Phase 2. No custom modeled art in the slice.

### 2. Directory & Scene Architecture
```text
res://
├── project.godot
├── export_presets.cfg        # Phase 5 (D40); no keystores committed
├── autoload/
│   ├── GameState.gd          # Active hero, stage progress, stars, grudge, seeded RNG streams (D25)
│   ├── SaveManager.gd        # Atomic JSON read/write, schema_version (D15), single slot (D23)
│   └── EchoDirector.gd       # Records skill keyframes & spawns SpectralEcho actors
├── data/
│   ├── heroes.json           # Base stats, coeffs, skills, cadences, locks (§2D, D25, D27)
│   ├── weapons.json          # Classes, hero-lock (D5), evolution lines (§2C), economy (D30/D31)
│   └── stages.json           # Rooms, waves, traps, drops, stars, Vespera + grudge (§2E–H)
├── systems/                  # Plain classes (class_name), no scene dependencies
│   ├── Weapon.gd             # §2C data model
│   ├── Inventory.gd          # Weapons, mains (D18), shards, essences
│   ├── WeaponForge.gd        # Absorb / salvage / Build-Up + power math (§2C, D25, D31)
│   ├── LootTable.gd          # Drop rolls + grudge bias (D19, D30)
│   ├── Combat.gd             # Layers, enemy contract, geometric hit queries
│   ├── DataLoader.gd         # Fail-loud JSON loading (D22)
│   └── DataSchema.gd         # Field validators for data/*.json
├── scenes/
│   ├── main/
│   │   ├── MainHub.tscn      # Hero trio selector, Stage Briefing, Weapon Forge drawer
│   │   ├── DungeonRun.tscn   # Landscape HUD, virtual stick, 3 skill buttons, Boon modal, pause
│   │   ├── CameraRig.gd      # D3 follow camera
│   │   └── HeroInput.gd      # Stick + WASD/arrows, J/K/L or 1/2/3 skills
│   ├── ui/
│   │   ├── RunHud.gd         # Stats, stick and skill-button layout
│   │   ├── VirtualStick.gd   # Multi-touch floating stick
│   │   └── SkillButton.gd    # Radial cooldown ring
│   ├── actors/
│   │   ├── HeroActor.tscn    # CharacterBody3D + HeroController + WeaponMeshMount
│   │   ├── HeroController.gd # §2A verbatim + kit, damage intake, passives
│   │   ├── HeroSkills.gd     # 9 skills, D27 aiming/locks/buffer, cooldowns
│   │   ├── HeroVisuals.gd    # Gray-box silhouettes + AD2/AD3/AD4 emissive hooks
│   │   ├── Hitbox.gd         # Area3D attack areas and zones
│   │   ├── Projectile.gd     # Area3D arrows / Prism Bolts
│   │   ├── TrainingDummy.gd  # Gray-box target (enemy contract, no AI)
│   │   ├── SpectralEcho.tscn # Translucent stained-glass ghost executor
│   │   ├── EnemyBase.tscn    # Crawler / Spitter / Bulwark AI + telegraph decals
│   │   └── BossVespera.tscn  # 2-phase boss + Grudge Adaptation handler
│   └── rooms/
│       ├── GrayboxArena.tscn # Phase 2 empty arena + training dummies
│       └── Stage01_Nave.tscn # 4 rooms + boss arena, EchoAnchor per room, gates, spike traps
├── shaders/
│   └── stained_glass_echo.gdshader
└── tests/
    ├── test_core_systems.gd  # Runner (extends SceneTree), quit(0/1) (D38)
    ├── lib/TestContext.gd    # Assertion collector
    ├── lib/CombatSim.gd      # Fixed-step hero + dummies sandbox
    └── phase_1/ … phase_5/   # Per-phase suites, all run by the runner
```

### 3. Execution Phases (build & verify sequentially; a phase is done only when its gate passes)

**Phase 1 — Data, SaveManager, Weapon Forge.** `GameState.gd` (incl. seeded RNG streams, D25), `SaveManager.gd` (schema_version, atomic writes, single slot D23), `WeaponForge.gd` with the D5 hero-lock, D18 slot model, D16 sub-stats, D17/D25 ATK math, D26 naming, D30 drop math and D31 economy; fail-loud `data/*.json` loading (D22); populate `heroes.json`/`weapons.json`/`stages.json` from the §2 tables. Test runner per D38.
*Gate 1 (headless):* absorption rejects mismatched class, foreign-owner and same-`uid` fodder; matching absorbs grant XP (multi-level-up, cap discard) + rotating sub-stat with 20-stack caps; D25 ATK math reproduces §2D level-1 damage exactly; salvage yields `2 + rarity` shards; evolution fires exactly at threshold, consumes cost, keeps level; D30 weights (incl. ×1.25 bias) match over a seeded sample; save round-trip preserves `schema_version`.

**Phase 2 — Stop-to-Attack Controller & Hero Kits.** `HeroActor.tscn`/`HeroController.gd` exactly as §2A; joystick (`InputEventScreenDrag`) + WASD fallback; D27 tap-to-cast, aiming rules and lock times; D28 reach and hysteresis; the 9 skills from §2D with cooldown rings; camera rig per D3.
*Gate 2 (headless):* auto-attack starts ≤ 0.10 s after full stop; movement re-acquires on the same frame; no swing when the target is out of reach; Rogue swaps at 2.6 m (enter) and 3.0 m (exit) with exactly one `rogue_mode_changed` per change; all 9 skills spawn valid `Area3D` hitboxes/projectiles with expected shapes, locks and cooldowns from `heroes.json`; camera lock verified in the scene test.

**Phase 3 — Dungeon Loop, Boon Draft, Boss Grudge.** `Stage01_Nave.tscn` with waves, spawn rules and traps per §2E, enemies per D33, 1-of-3 Boon modal before Room 3 (§2F), `BossVespera.tscn` per D32, Grudge per §2H/D11, run flow per D29.
*Gate 3 (headless):* doors unlock only on last-wave clear; room-clear heal and HP carry-over; each boon applies for the run only; Vespera clear installs exactly one adaptation keyed to the clearing hero and the bias flips across two consecutive clears by different heroes; Mirage Veil restarts telegraphs with full warning time; boss ignores stun/pull/knockback; D37 star conditions evaluated deterministically and persisted on victory only; death and abandon follow D10/D29; drops are saved at each room clear.

**Phase 4 — Spectral Echoes.** `EchoDirector.gd` per §2B/D34/D35/D36, Echo Conducting and Vespera's Twin Reliquaries (D41).
*Gate 4 (headless):* a recorded Brute run spawns a functional Leap Slam echo in a later Rogue run in the same room/wave at `t` (cue at `t − 1.0`); target resolution order (3.5 m → room → skip); per-wave cap of 2 and per-hero overwrite; ≤ 2 concurrent actors with 1.5 s wait/drop; wave-ended drop; ×0.65 values and no crits; D21 inheritance; star isolation; echo timing identical in game time with and without a simulated `time_scale` dip; serialization round-trip; a tap during a 1.0 s cue moves that Echo's cast (clamped to 6 m, once), a tap on a HUD control does not; Twin Reliquaries: both pillars within 1.5 s shatter them, a miss grants an 8 s −75% Shatter Shield, an Echo strike counts, pillars never feed stars.

**Phase 5 — Main Hub UI & Polish.** `MainHub.tscn`: 3 hero cards (weapon rarity + evolution stage, stars, Grudge warning + counter tip), Stage Briefing, Forge drawer (1-tap Absorb/Salvage, evolution nodes, D13 unlock gate, at-cap XP warning), run summary with star progress, floating damage numbers, hit-stop per D36, stained-glass lighting within the mobile perf budget, `export_presets.cfg` per D40; **Restore the Reliquary** (§2I, D42: Glass economy, six windows and their unlocks); **barks and narrator** (§2J, D43); rooms assembling from falling glass (AD13).
*Gate 5 (headless + scene):* hub flows (brief → commit → run → summary → hub) complete with no orphaned state, including death and abandon paths; Forge locked before the first boss kill; UI Forge actions match Phase 1 core results; export preset values match D24/D40; Glass earned and saved per D42 (kept on death); windows restore only in order and only with enough Glass; each unlock changes its rule (heal, Echo cap, draft size, drop chance, Stage 3 cost); BarkDirector spacing, repeat filter and grudge-keyed line selection.

**Phase 6 — Device Verification (manual, not headless).**
*Gate 6 checklist (Galaxy S24 Ultra, adb logging):* stable 60 fps in Room 4 and the boss fight; telegraphs readable at 2400×1080 and 19.5:9; two-thumb reach: stick never conflicts with skill buttons; echo actors and cues visible but never occluding enemy telegraphs; a full run starts and ends with zero errors in `adb logcat`; background/force-kill behave per D29; battery/heat sane over 3 back-to-back runs.

### 4. Automated Verification Command
```bash
godot --headless --path . --import        # once per fresh clone / after adding class_name scripts (D38)
godot --headless --path . -s res://tests/test_core_systems.gd
```
On Windows use `Godot_v4.7.2-stable_win64.exe` for `godot`. All assertions (hero-lock, weapon-class enforcement, D25 damage math, D30/D31 economy, Rogue hysteresis, Grudge rotation, star persistence, boon run-scope, echo round-trip and timing, stop-threshold timing, D23 save round-trip) must exit `0` before a phase is declared complete. Tests are a hand-rolled `SceneTree` script — no plugins (D22). **Headless gates cannot verify feel** — Phase 6 is not optional.

---

## 4. Open Tunables (first playtest agenda)
1. Stop grace 0.08 s vs. instant-cancel feel with real thumbs.
2. Cleave cadence 0.9 s vs. Crimson Guard upkeep; Cleave Master 50% threshold.
3. Rogue bow 10.5 m reach vs. Spitter 5–8 m band (kiting window); 2.6/3.0 m hysteresis feel.
4. Boon magnitudes (±12%/±15% classes) vs. 4-room difficulty curve; 15% room-clear heal.
5. Vespera 1600 HP vs. level-1 weapons: target ~2.5–3 min fight.
6. Echo 65% potency and the 1.0 s cue: should feel like backup, never autopilot.
7. Close Work 60-hit threshold vs. Spiked Carapace recoil when the last clear was the Brute.
8. Forge pacing (D31): Stage 2 ≈ 5 own-hero clears, Stage 3 ≈ 20; Rogue's two classes level about half as fast.
9. Echo Conducting (D41): is a 1.0 s cue long enough to tap with a thumb, and is 6 m the right reach?
10. Twin Reliquaries (D41): can a first-time Brute solve it without an Echo? Tune spacing and window until it's possible but satisfying with one.
11. Glass pacing (D42): ~20 runs to restore all six windows; check against D31 and how long players stay.
