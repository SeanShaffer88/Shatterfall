# Phase 6 Prompt — on-device verification checklist (manual; not a paste-into-Claude prompt)

Prerequisite: Phase 5 complete with Gate 5 green. This phase is **yours, not the agent's**: headless tests cannot verify feel, input latency, readability, or thermals. Work through this checklist on the actual target device and record results.

## Setup

Already verified on the dev machine (2026-11-26): Godot 4.7.2 export templates, JDK 21, the Android SDK and the debug keystore are configured. `export_presets.cfg` builds a debug APK whose manifest shows `com.seanshaffer88.shatterfall`, version 0.1.0, `arm64-v8a` only and `screenOrientation=sensorLandscape`.

1. Enable USB debugging on the **Galaxy S24 Ultra** (D8) and connect it. Check it's listed:
   ```powershell
   & "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices
   ```
2. Build the debug APK from the repo root:
   ```powershell
   & "$env:LOCALAPPDATA\Programs\Godot\4.7.2-stable\Godot_v4.7.2-stable_win64.exe" --headless --path . --export-debug "Android" build/android/Shatterfall.apk
   ```
3. Install it and start a log capture:
   ```powershell
   & "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" install -r build/android/Shatterfall.apk
   ```
   ```powershell
   & "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" logcat -s godot:V > phase6_logcat.txt
   ```
4. Run the checklist below untethered for feel tests and connected for log capture. The game opens in the Hub.

## Gate 6 checklist — all items must pass to declare the slice done

**Performance (D8/AD12)**
- [ ] Stable 60 fps during Room 4 (3 waves + Bulwarks) and the full Vespera fight with echoes active.
- [ ] No thermal throttling below 60 fps across 3 back-to-back runs; battery/heat sane.
- [ ] `adb logcat` shows zero Godot errors/warnings for a complete run start → victory → hub → second run.

**Readability (AD1, AD5–AD7)**
- [ ] All three hero silhouettes distinguishable at a glance at 2400×1080 **and** 19.5:9 (S24 Ultra native crop).
- [ ] Enemy telegraphs readable over decorative stained-glass lighting; spike trap warnings have enough lead time to dodge at default speed.
- [ ] Echo actors are clearly cyan and never occlude or dim a telegraph.

**Two-thumb ergonomics (D1, D27)**
- [ ] Virtual stick and the 3 skill buttons never conflict; every skill reachable without re-gripping; no accidental skill triggers while dodging; auto-aim picks the target you expected.
- [ ] Auto-attack stop-brief: stopping feels snappy (no perceivable 0.08 s hitch) and micro-dodge adjustments never trigger unwanted attack starts.

**Systems feel (D6, D9, D11, D12, §4 Open Tunables)**
- [ ] A full run lands in the 6–9 minute target; Vespera ~2.5–3 min at level-1 weapons.
- [ ] Echo assists read as backup, not autopilot; their cyan presentation and 1.0 s cue are unmistakable and never confused with telegraphs.
- [ ] Grudge adaptation is noticeable in the boss fight but not oppressive; the +25% drop bias is visible in the Forge.
- [ ] Crimson Guard ember ramp, Rogue swap flash, and Magi orb states all track gameplay as specced (AD2–AD4).

**Hub, Reliquary and voice (D42, D43, AD8–AD10, AD13)**
- [ ] The Hub fills the screen; hero cards, briefing and the bottom-right buttons are readable with thumbs and inside the safe area.
- [ ] Forge tome: one-tap Absorb/Salvage works with a thumb; the at-cap warning makes sense; runes light as requirements are met; the evolution moment feels like a payoff.
- [ ] Restoring a window feels rewarding (light, narrator line), and the unlock is noticeable in the next run.
- [ ] Vespera's grudge lines and the narrator are readable, not spammy, and never cover a telegraph or a menu.
- [ ] Rooms assembling from glass looks good and never delays the first wave awkwardly.

**Echoes as partners (D41)**
- [ ] Echo Conducting: tapping open ground during a cue is easy with a thumb, and the 1.0 s cue is long enough (open tunable #9).
- [ ] Twin Reliquaries: possible for a first-time Brute without Echoes, satisfying with one (open tunable #10).

**Camera (D3, Q-11)**
- [ ] The isometric 3/4 view reads like the reference; the hero isn't too small at the 30 m boom (open tunable #12 — try 22–26 m).
- [ ] "Stick up" always moves the hero up on screen.

**Persistence**
- [ ] Background the app mid-run: it auto-pauses (D29).
- [ ] Force-kill the app mid-run and from the Hub; relaunch — the mid-run kill counts as abandoned (drops up to the last room clear kept), and `user://save.json` and echo files survive with `schema_version: 1` intact (D15/D23/D29).

## Recording results

Commit a `PHASE6_REPORT.md` with the checklist filled in, fps/logcat excerpts, and any tunables you adjusted from §4 Open Tunables — each tuning change gets its own commit referencing the tunable number (e.g., `tune-3: bow reach 10.5m → 9.5m (open tunable #3)`), and the Decision Log entry in `BLUEPRINT.md` is updated if a change is structural rather than a number tweak.

## Completion

When every box is checked and `PHASE6_REPORT.md` is merged, the vertical slice is done. Anything that failed goes back as a named fix task (or a new `QUESTIONS.md` entry if the fix needs a design decision) — never a silent workaround.
