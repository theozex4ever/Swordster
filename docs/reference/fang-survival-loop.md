# Reference: the Fang survival loop

Slice #8 of the Godot port ([spec #4](https://github.com/theozex4ever/Swordster/issues/4)).
The Python prototype `game/main.py` is the behavioural oracle. This file records
what was captured from it, the comparison tolerances chosen **before** accepting any
difference, the checks that assert each value, and every deliberate exception.

Vocabulary follows `GLOSSARY.md`: spirit sword, sword type (Fang), sword slot.

## How the reference was captured

`tools/reference/capture_fang_survival_loop.py` loads the prototype's real classes
(`Game`, `Player`, `Sword`, `Enemy`, ...) without starting its main loop, drives
them with fixed timesteps under SDL's dummy drivers, and writes
`godot/tests/reference/fang_survival_loop.json`. Regenerate with:

```sh
python3 -I tools/reference/capture_fang_survival_loop.py godot/tests/reference/fang_survival_loop.json
```

Controls applied for repeatability: crit rolls are forced (`random.random`) where a
case needs them, sword start cooldowns are pinned to 0.4 s (the prototype draws
`uniform(0.2, 0.6)`, line 589), husk speed is pinned (no 0.9–1.12 factor, line 493)
and the elemental `afflict` step is disabled (conditions are a later slice, see
exceptions). The Godot side runs the same scenarios through the real `GameRun`
with `GameCommand`s (`godot/tests/survival_loop_checks.gd`, run by
`godot/tests/run_checks.gd`).

## Tolerances

Decided first, then used by every comparison.

| Quantity | Tolerance | Why |
|---|---|---|
| Position, camera (px) | ±0.05 | Same algorithm at the prototype's own 60 FPS step; float noise only. |
| Velocity (px/s) | ±0.05 | Same. |
| Health, timers, shake, hitstop | ±0.002 | Same. |
| Event times (hits, spawns, state changes) | ±1 fixed tick (1/60 s) | The prototype's frame loop and the 60 Hz tick can order a same-frame event one tick apart. |
| Damage dealt, kills, motes, counts | exact | Integers. |
| Wave clear time across seeds | reference band ±1 s | Random spawn points and recoil differ by stream; Python/Godot RNG streams cannot match. |

In practice every compared value matched exactly; the loose bands exist for
randomness only.

**Accepted difference: fixed tick vs variable step.** The prototype steps with the
real frame time capped at 1/30 s. The port steps at a fixed 1/60 s. At 60 FPS they
are identical; at other frame rates the prototype itself drifts. Captured evidence
(movement `dx` after 1 s holding right, spawn at the arena centre):

| Frame step | x offset at 1 s | vs 60 FPS |
|---|---|---|
| 1/30 s | 274.143 | +4.75 px |
| **1/60 s (port)** | **269.393** | – |
| 1/120 s | 267.018 | −2.4 px |

Dash distance (204.76 px) is identical at all three. The port is therefore the
prototype's 60 FPS behaviour everywhere; the ≤5 px frame-rate-dependent spread of the
prototype is accepted and not reproduced.

## Reference values and the checks asserting them

Line numbers refer to `game/main.py` at this repository's base commit.

### Movement and camera (Player 421–467; Game.update 1549–1641)

- Arena 2600×1800 (21), player radius 14, speed 285, acceleration blend
  `min(1, dt·14)`, spawn at the arena centre.
- Camera follows `pos + vel·0.12` with `1 − e^(−7·dt)` easing, clamped to
  `[view/2 − 140, world − view/2 + 140]` (1639–1641), i.e. it may show 140 px past
  the wall. View is the 1280×720 reference.

| Case (hold right unless noted) | Reference |
|---|---|
| x offset at 0.25 / 0.5 / 1 / 2 s | 55.933 / 126.898 / 269.393 / 554.393 |
| vx at 0.25 / 0.5 / 1 / 2 s | 279.704 / 284.902 / 285 / 285 |
| camera x offset at the same times | 52.920 / 122.925 / 265.214 / 550.207 |
| diagonal speed, facing | 285, (0.7071, 0.7071) |
| east wall (12 s) | player x 2586, camera x 2100 |
| north-west corner (12 s) | player (14, 14), camera (500, 220) |
| velocity 0.1 / 0.2 / 0.5 s after release | 57.874 / 11.752 / 0.098 |

### Dash (Player.dash 469–482; keys 1534)

Aliases Space, Left Shift, Right Shift (Godot reports both Shift keys as one key).
Speed 1000 px/s for 0.14 s (9 ticks at 60 Hz), cooldown 0.65 s, invulnerability
0.24 s, direction = held movement else facing, refused while paused or dead.

| Case | Reference |
|---|---|
| displacement at 0.2 / 0.3 / 0.5 / 1 s | 180.085 / 199.751 / 204.555 / 204.762 |
| velocity at 0.2 / 0.3 s | 450.63 / 91.508 |
| driven ticks | 9 |
| gating after a dash: 0.5 / 0.6 / 0.64 s | refused |
| gating: 0.66 / 0.7 s | accepted |
| held W+A at dash | velocity (−707.107, −707.107) |
| idle dash after moving left | (−1000, 0) |

### Incoming damage and death (hurt_player 1365–1385; contact 1577–1581)

Husk contact damage 10, invulnerability 0.8 s, knockback 420 px/s away from the
source, hitstop 0.07 s, shake +0.45. Enemies in contact are knocked back (200 px/s,
stun 0.2 s) even when the hit is refused.

| Case | Reference |
|---|---|
| parked husk: hit ticks | 1, 54, 107, 160, 213 (health 90, 80, 70, 60, 50) |
| lethal hit | health 0, slow motion 1.4 s at ×0.25, death timer 0 |
| R becomes eligible | 116 real ticks (1.933 s) after death |

Restart: R restarts only when dead **and** the death timer (scaled time) is above
0.8 s (1530); otherwise R is the slot-three ultimate key. Because slow motion
quarters the timer for the first 1.4 real seconds, the delay is ~1.93 real seconds.
Since slice #12 R is that slot-three ultimate key while alive
([Viper Flurry](viper-flurry.md)); the translator sends the ultimate command and then
the delayed restart, and the run refuses whichever does not apply.

### Touch buttons (web/mobile.js 54–60; `Hud`)

The prototype's on-screen buttons all dispatch on `pointerdown`, never on release.
In the port the Dash, Pause/Resume and Restart buttons act on press: they are wired to
`button_down`, not `pressed` (which fires on release by default; connecting it was a
bug in the first version of this slice that delayed a touch dash by the length of
the tap). `button_down` rather than `pressed` plus press mode, because Godot also
delivers a real touch as its own emulated mouse button, and `pressed` then fires twice per
touch while `button_down` fires once. `survival_loop_checks.gd` drives all three
buttons with real mouse and touch events through the viewport: the dash is live on
press (invulnerable before the next contact tick), holding does not repeat it even
after the cooldown, releasing does nothing, and Pause/Resume and Restart likewise act
once on press. The joystick, Ranges, ultimate, swap, Strike and fullscreen buttons
belong to later slices.

### Time: hitstop, slow motion, pause (Game.update 1549–1560)

Real time (`real_time`, shake decay and the hitstop timer itself) keeps running
during hitstop and slow motion; gameplay time does not advance during hitstop and
is scaled during slow motion. Both implementations return from the update before
the slow-motion timer is decremented while hitstop is active, so **slow motion
waits out hitstop** rather than running down alongside it. Pause freezes
everything.

| Case | Reference |
|---|---|
| hitstop 0.05 s / 0.02 s | 4 / 2 frozen ticks |
| slow motion ×0.25, 0.5 real s | 0.125 scaled s, 0.9 s left |
| slow motion ×0.25, 2 real s | 0.95 scaled s, finished |
| shake 1.0 after 0.25 s of hitstop | 0.6 |
| slow motion 1.0 s ×0.25 set during 0.05 s hitstop | 4 frozen ticks, slow motion still 1.0 s, no scaled time |

### Fang (SWORD_TYPES["fang"] 79–86; acquire 629; strike 1008; update 738–764)

Length 34, range 175 (+ target radius), cooldown 0.30, damage 7, knock 170, windup
0.06, speed 1700, hitstop 0.02, shake 0.07; strike lasts ≤0.3 s, tip at 0.65·length,
hit pad 6, recovery 0.25 s after a hit or 0.2 s after a miss. Target: the nearest
enemy within range. Damage: 12 % critical (×2, knockback ×1.3, hitstop ×1.5,
shake +0.1), rounded with Python's `round()` (halves to even), minimum 1.

| Case | Reference |
|---|---|
| one Fang, stationary husk at 100 px: windup / strike start | tick 25 / 29 |
| hit ticks (7 damage each) | 30, 56, 83, 111 |
| acquisition at 150 / 190 px | engaged |
| acquisition at 192 / 195 px | ignored (175 + 16 = 191) |
| Common hit / crit | 7 / 14; knockback 170 / 221; stun 0.193 / 0.227 |
| Rare 9.1 → hit / crit | 9 / 18 |
| Mythic 12.25 → hit / crit | 12 / **24** (24.5 rounds to even; `roundi` would give 25) |

### Husk, wave and healing motes (ENEMY_TYPES 125; start_wave 1441; update_waves 1696; Mote 375, 1596–1608)

Husk: radius 16, health 30·(1 + 0.1·(wave−1)), speed 92 (×0.9–1.12), contact
damage 10, knock multiplier 1. Wave 1 is 5 + 3 = 8 husks, husk-only (runners from
wave 2). The first break is 1.6 s; the first telegraph appears 0.3 s after wave
start, the next every `max(0.12, 0.42 − 0.02·wave)` s; each telegraph lasts 0.7 s
before the husk appears; the spawn point is 420–720 px from the player and over
320 px away, kept 50 px inside the arena. Clearing the wave (queue, telegraphs and
enemies empty) starts 0.7 s of slow motion at ×0.3 and a 3.2 s break.

| Case | Reference |
|---|---|
| wave 1 starts | tick 97 |
| telegraph ticks | 116, 141, 166, 191, 216, 241, 266, 291 |
| husk appearance ticks | 157, 182, 207, 232, 257, 282, 307, 332 |
| three Fangs vs wave 1, **unarmed** husks, stationary player, 8 seeds | all survive, 8 kills, cleared 13.1–14.6 s, lowest health 83 |

The survival row is an **unarmed** fixture. The prototype's `start_wave` always arms
the first two foes of wave 1 and rolls arming for the rest; an armed foe has 1.35×
health (40.5 for a husk) and drops a sword, none of which this slice has. The capture
therefore discards the arming result of every spawn-queue entry (the prototype still
draws its random numbers) and stops with an assertion if any marker or enemy it sees
is armed or any husk's health is not 30. Each seed records `armed_enemies: 0` and
`husks_spawned: 8`, and the Godot check rejects a reference that does not say so. An
earlier capture without this step contained two armed husks per seed and so measured
a different, harder fight (13.2–14.3 s then; the unarmed band is 13.1–14.6 s). The
Godot run is compared with the band ±1 s, unchanged.

After the player dies, husks stop chasing and drift: the velocity eases (blend
`min(1, dt·6)`) toward a vector of length `0.3 × speed` whose angle is
`t·0.3 + id % 7`, i.e. it turns 0.3 rad/s. The starting angle is an identity value
in the prototype, so the reference only holds quantities independent of it.

| Case (husk 300 px away, player dead) | Reference |
|---|---|
| speed at 0.5 / 1 / 2 / 3 s | 26.414 / 27.522 / 27.569 / 27.569 (target 27.6) |
| distance travelled at 0.5 / 1 / 2 / 3 s | 9.83 / 23.39 / 50.38 / 76.25 px |
| heading turn from 1 s to 3 s | 0.5995 rad |

A killed enemy releases 3 healing motes: they scatter 120–260 px/s, home in after
0.25 s, are collected within 18 px for +0.5 health, capped at 100; a mote is
consumed at full health and a dead player is not healed.

| Case | Reference |
|---|---|
| three motes from 50 / 99.8 health | 51.5 / 100 |
| one mote at full health / when dead | consumed, health unchanged |

## Deliberate exceptions

Each is a scope decision of slice #8, not a rebalance.

1. **Fang-only fixture loadout.** The prototype's default is Fang / Warden /
   Colossus (poison / ice / fire, line 1059). This slice equips three Fang swords
   (poison / ice / fire colours) as a development fixture
   (`RunScenario.fang_fixture_loadout`) until Warden, Pike and Colossus land. It is
   not the final default loadout.
2. **No armed enemies or drops.** Prototype wave 1 arms the first two husks (the
   first with a Pike) at 1.35× health and they drop swords. Drops are issue #17, so
   husks here are unarmed with base health (30). Wave composition beyond wave 1,
   unlocks and brute/runner/spitter behaviour are issue #18 and later. The survival
   reference is captured with the arming disabled to match (see above).
3. **One wave.** After the scenario's wave count (1) is cleared the run is
   *survived* and no further wave starts; the prototype would continue.
4. **No elemental conditions.** Burn, poison, chill, freeze, the frozen damage
   bonus (×1.3) and fire spread arrive with the conditions slice; swords only carry
   their element for colouring. The reference was captured with `afflict` disabled.
5. **No ultimates, Converge, parry, projectiles, wall-slam sources.** Q/E/R, mouse
   Converge and swapping are later slices. R while alive does nothing for that reason.
   (`wall_slam` and bowling are ported but unreachable with Fang-only knockback.)
   *Superseded for ultimates by #12:* Q, E and R now trigger the Fang ultimate of
   sword slots one to three and R while alive is the slot-three ultimate, no longer a
   no-op (see [viper-flurry.md](viper-flurry.md)); the delayed restart after death is
   unchanged. Converge and swapping remain later slices.
6. **Restart un-pauses.** The prototype's keyboard R-after-death (line 1530) resets
   the world but leaves the pause flag, so a restart done while paused begins paused.
   The port restarts un-paused (as the prototype's touch Restart already does).
7. **Dash heading uses the last applied movement.** Prototype `Player.move` is the
   previous frame's movement (touch overrides it); the port uses the last applied
   movement command. Identical at 60 Hz for held keys.
8. **A dead enemy still consumes a Fang strike in the same tick.** Reproduced from
   the prototype (a sword touching an enemy another sword just killed ends its
   strike without damage). Deaths, motes and counters still resolve once.
9. **Gameplay randomness is its own stream** (`GameRun.rng`, seedable). Crit rolls,
   spawn points, recoil direction and sword start cooldowns follow the prototype's
   distributions but not its random sequence; cosmetic randomness (screen-shake
   offset, damage-number jitter) never uses it.
10. **Rendering is not a gate.** Placeholder visuals follow the logical pose; the
    prototype's particles, trails, glow and vignette are not reproduced.

## Validation

Run on build `20261114-100754-3895208bf` (source commit 3895208, clean tree; the
later commits on this branch change documentation only), Linux, Godot 4.7.2-stable.

| What | Result |
|---|---|
| `./build-godot.sh --checks-only` / full `./build-godot.sh` | `CHECKS PASSED: 289`; full build OK, Windows ZIP and Web bundle produced |
| `tools/godot/mutation-check.sh` | 46 of 46 deliberate bugs caught, 0 inconclusive (baseline 289 checks pass) |
| Reference regeneration | `capture_fang_survival_loop.py` run twice gives byte-identical output |
| **Windows export, under Wine 11 on Linux (not a Windows machine)** | The full build's `Swordster.exe`, extracted from the ZIP, starts under Wine with this machine's NVIDIA GPU, opens a window, shows the build label, arena and HUD, spawns telegraphed husks, the three Fang swords fight them and the run ends on the WAVE SURVIVED screen (8 kills, health 96, ~17 s after launch). Wine screenshots were taken at 2, 6, 10 and 17 s. No input was sent: the only way to synthesise it on this desktop (X11 test events) triggered a desktop remote-control permission prompt, which was not approved. Dash and Restart in that export were therefore not exercised. |
| **Web export, headless Chromium (software WebGL 2 via SwiftShader, desktop viewport 1280×720)** | Served the built bundle over HTTP and loaded it: engine starts without console errors, the same loop plays to WAVE SURVIVED (kills 8, health 100, ~25 s). Space dashes (HUD shows the dash cooldown). A real mouse press on Restart restarts the run while the button is still held. A synthetic CDP **touch** on Dash shows the dash cooldown running while the finger is still down, and holding it past the cooldown does not dash again (HUD back to "dash ready" after release). |

## What was not verified

- **No real Windows machine** and no real Android device. Windows and Android hardware
  validation is deferred to #6 and #22 by the maintainer's decision; the Wine run above
  proves the export launches and runs the loop, not that it behaves on Windows.
- Web was run in headless Chromium with a software renderer and synthetic CDP touch,
  not in Firefox, on a real GPU or on a phone. Frame pacing, audio and real multi-touch
  were not measured.
- Only Space (dash) was pressed in the Web run; WASD, P and R were covered by the
  headless checks alone. No keyboard or button input reached the Windows export.
