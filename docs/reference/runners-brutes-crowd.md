# Reference: runners, brutes, crowds and walls

Slice #9 of the Godot port ([spec #4](https://github.com/theozex4ever/Swordster/issues/4)),
following [the Fang survival loop](fang-survival-loop.md). The Python prototype
`game/main.py` is the behavioural oracle. This file records what was captured from it,
the tolerances, the checks that assert each value, and every deliberate exception.

## How the reference was captured

`tools/reference/capture_crowd_and_walls.py` reuses the loader and helpers of
`capture_fang_survival_loop.py`, drives the prototype's real classes (`Game`, `Enemy`,
`Player`, `Sword`) with fixed 1/60 s steps under SDL's dummy drivers, and writes
`godot/tests/reference/crowd_and_walls.json`. Regenerate with:

```sh
python3 -I tools/reference/capture_crowd_and_walls.py godot/tests/reference/crowd_and_walls.json
```

Nothing is re-implemented: separation, bowling and wall slams are read off the
prototype's own `Game.update`. Every case also writes its **fixture** (`setup`: kind,
position, velocity, stun, health, clock phase) into the JSON, and the Godot checks build
their scenarios from that, so no starting number is copied by hand.

Controls applied for repeatability (and asserted by the capture, which records
`fixture_scope` in the JSON; the Godot checks reject a reference that does not say so):

- `afflict` (elemental conditions) is a no-op: conditions are issue #11.
- Every enemy it creates is unarmed (`armed is None`): armed foes carry 1.35× health and
  drop swords (issue #17). The capture stops on an assertion otherwise.
- Only husks, runners and brutes appear: spitters and projectiles are issue #10.
- No sword is equipped in the physics cases (no ultimate, no Converge). The Fang-vs-one-foe
  case uses one Fang with its start cooldown pinned to 0.4 s and crit rolls forced off.
- Enemy speed (the prototype draws 0.9–1.12×) and clock `t` (random 0–10) are pinned per
  case; the weave phase is varied on purpose (`t` 0 and 1.3).

The Godot side runs the same scenarios through the real `GameRun` with
`GameCommand`s (`godot/tests/crowd_and_wall_checks.gd`, registered in
`godot/tests/run_checks.gd`).

## Tolerances

Chosen before accepting any difference; the same as the Fang slice.

| Quantity | Tolerance | Why |
|---|---|---|
| Position, velocity | ±0.05 px, ±0.05 px/s | Same algorithm at the prototype's 60 FPS step; float noise only. |
| Health, stun, timers, shake, hitstop | ±0.002 | Same. |
| Event ticks (hits, deaths, slams) | ±1 fixed tick | The two frame loops can order a same-frame event one tick apart. |
| Damage, kills, motes, counts | exact | Integers. |
| 12-enemy shoved crowd over 240 ticks | ±0.5 px | Hundreds of collisions; float32 (Godot) vs float64 (Python). |

In practice every compared value matched; the crowd's looser band was not needed
beyond float noise but is kept as headroom for the long composite only.

## Reference values and the checks asserting them

Line numbers refer to `game/main.py` at this repository's base commit.

### Enemy table (`ENEMY_TYPES` 125–130; `Enemy.__init__` 485–520)

| Type | Radius | Health | Speed | Contact damage | Knockback multiplier |
|---|---|---|---|---|---|
| husk | 16 | 30 | 92 | 10 | 1.0 |
| runner | 11 | 14 | 178 | 6 | 1.3 |
| brute | 30 | 170 | 52 | 20 | 0.35 |

Health scales `× (1 + 0.1·(wave − 1))`: brute 170 / 187 / 204 / 238 on waves 1 / 2 / 3 / 5
(armed ×1.35 is out of scope). The speed factor 0.9–1.12 and the clock phase 0–10 are
random draws per enemy in the prototype; the port draws both from the run's gameplay
random stream (`WaveDirector`) and the checks pin them.

### Movement (`Enemy.update` 521–563)

Chase the player at `speed`; a **runner** adds a sideways pull
`(dir + perp·sin(t·5)·0.5) · speed` (`t` is the enemy's own clock, random start). Stunned
enemies only decay their velocity (`× e^(−5·dt)`). After the player dies every enemy drifts
at 0.3 × speed instead of chasing or weaving.

| Case (enemy 700 px away, stationary player) | Reference (offset from the player) |
|---|---|
| runner, `t₀` = 0, at 0.5 / 1 / 3 s | (−633.607, 130.698) / (−547.939, 112.366) / (−200.538, 45.406) |
| runner, `t₀` = 1.3, at 1 s | (−548.688, 108.745) |
| husk at 3 s / brute at 3 s | (−441.57, 75.698) / (−553.931, 94.96) |

Asserted by `crowd: runner weave, husk and brute chase`: position, velocity and facing at
0.25, 0.5, 1, 2 and 3 s for all three types and both phases. The weave changes the path
(3.6 px at 1 s between the two phases).

### Contact (`Game.update` 1577–1581; `hurt_player`)

Same rule as husks: damage on contact unless invulnerable; the enemy is shoved away at
200 px/s and stunned 0.2 s **even when the hit is refused**.

| Type | First contact | Parked: hit ticks |
|---|---|---|
| husk | health 90 | 1, 54, 107, … (−10 each) |
| runner | health 94 | 1, 54, 107, … (−6 each) |
| brute | health 80 | 1, 54, 107, 160, 213 (−20 each; dead at the fifth) |

A brute's blow kills a player on 15 health (health 0, slow motion 1.4 s at ×0.25).

### Knockback resistance and launches (`hit_enemy` 1122–1160)

Force = `knock · knock_mult · (1.3 if crit)`; the old velocity keeps 30 %; stun = `max(stun,
0.08 + force/1500)`.

| Hit (Fang, knock 170) | Common | Critical (×1.3) |
|---|---|---|
| husk | 170.0 px/s, stun 0.193 | 221.0, 0.227 |
| runner (×1.3) | 221.0, 0.227 | 287.3, 0.272 |
| brute (×0.35) | 59.5, 0.120 | 77.35, 0.132 |

A heavy Colossus knock (650) launches a husk at 650 px/s (stun 0.513), a runner at 845
(0.643) and a brute at 227.5 (0.232); an enemy already moving keeps 30 % of its velocity
((100, −50) → (30, 635) when struck along +y). One Fang against one brute walking at it:
25 hits of 7, death at tick 688, player untouched; against a runner: two hits, death at
tick 57 (`crowd: one Fang against a brute and a runner`).

### Separation (`Game.separate` 1643–1668)

Pairs closer than the sum of radii are pushed apart along the line between centres, each
by `overlap · (other mass)/(total mass)` with mass = radius². Exactly touching (46 px for a
husk and a brute) and coincident enemies (distance 0) are **not** separated.

| Case | After one tick |
|---|---|
| husk/husk, overlap 8 | 596.0 / 628.0 (4 px each) |
| husk/brute, overlap 16 | 587.543 / 633.543 (husk 12.5 px, brute 3.5 px: 900 : 256) |
| brute/brute, overlap 10 | 595 / 655 |
| runner/brute diagonal | (591.463, 396.341) / (629.148, 412.492) |

Also asserted: the packed crowd of twelve mixed enemies matches the prototype at 1, 5, 20
and 60 ticks and ends with no overlap above 1 px.

### Crowd bowling (`Game.separate` 1661–1668)

When two enemies overlap and one is **stunned, faster than 340 px/s and moving toward the
other**, it transfers `0.55 · v · r_launched / r_hit · 0.6` to the other, stuns it ≥ 0.25 s,
deals 3 damage (it can kill), loses 40 % of its own velocity and adds 0.06 shake. The speed
is tested after one tick of stun drag, so it is 92 % of the launch velocity.

| Launched at 700 px/s into | husk | runner | brute |
|---|---|---|---|
| husk | 212.5 → target, hp 27 | 309.1, hp 11 | 113.3, hp 167 |
| runner | 146.1 | 212.5 | 77.9 |
| brute | 398.5 | 579.6 | 212.5 |

The launcher always leaves at 386.4 (700 × 0.92 × 0.6). Thresholds: 366 px/s launch
(336.7 after drag): untouched; 373 (343.2): bowls; not stunned: untouched; moving away:
untouched.

Chained deaths (`crowd: chained collision deaths`): a launched brute through six weak
enemies kills three (ticks 1, 1, 5); a launched husk through four runners kills two (1, 1);
a brute through spaced husks kills two (3, 3), through spaced runners two (3, 4); a brute
bowling a husk into the east wall kills both (7, 7). Each death counts once and yields
exactly three motes; kills, kill cues and dead bodies agree.

### Wall slams (`Enemy.update` 559–563; `wall_slam` 1341–1355)

A stunned enemy that reaches an arena wall faster than 380 px/s (speed after the tick's
stun drag, before the bounce) takes `round(6 + (speed − 380)·0.04)` damage (Python
rounding), has its stun capped at 0.15 s, adds 0.18 shake and 0.04 s hitstop, and may die.
Every enemy bounces off a wall at −0.35 × the axis velocity whether or not it slams; a
corner slams once.

| Launch speed (husk, east wall) | 400 | 410 | 412 | 414 | 420 | 500 | 800 | 1200 |
|---|---|---|---|---|---|---|---|---|
| damage | 0 | 0 | 0 | 6 | 6 | 9 | 20 | 35 |

Not stunned: no slam at any speed. A stun of 0.05 s is not lengthened to 0.15. All four
walls and the corner slam; a slam kills an enemy once (kills 1, motes 3).

### The shoved crowd (composite, `crowd: a shoved crowd pinned against the wall`)

Fourteen enemies (two brutes, five husks, seven runners) around a player 350 px from the
east wall, shoved at tick 0 and then left alone for 240 ticks: four wall slams (ticks 4, 8,
12, 12), two deaths (ticks 4 and 12), identical positions, velocities, health and
stun for every enemy at ticks 10, 30, 60, 120 and 240 within 0.5 px, and the player's
health (88 at tick 240).

## What this slice adds beyond the reference

- **The crowd encounter fixture** (`RunScenario.crowd_encounter()`): one wave of five husks,
  five runners and two brutes (telegraphed per type, in a fixed interleaved order), the
  three-Fang fixture loadout, and the dev shove. Open it with the Crowd button, the `C`
  key, `--encounter=crowd` (Windows/Linux, after `--`) or `index.html?encounter=crowd`
  (browser). `--encounter=wall` / `?encounter=wall` starts the same fixture with the
  composite's fourteen foes already pinned between the player and the east wall and no
  further wave (`RunScenario.wall_encounter()`, asserted equal to this reference's crowd).
- **The dev shove** (`F` / Shove button, `GameCommand.dev_shove`): launches every enemy
  within 320 px of the player away from it with the knockback of a heavy Colossus blow
  (650, scaled by each type's resistance) and no damage, through the same `launch` impulse
  a sword hit uses. It exists because bowling and wall slams need a heavy source and the
  sword types that cause them (Warden, Pike, Colossus) are later slices. It is disabled
  outside the fixture scenario, while paused, and after death.
- **Frame-rate independence evidence**: the simulation steps exactly one fixed 1/60 s tick
  per call; the engine's own fixed-step loop decides how many run per rendered frame. The
  checks play one scripted fight (the shoved crowd plus the encounter wave, seven shoves
  and a dash, 900 ticks) through the real Main scene in child Godot processes at
  `--fixed-fps` 5, 20, 60 and 240 (75, 300, 900 and 3603 frames for the same 900 ticks)
  and require the digest — kills, combo, health, position, motes, kill/slam/bowl/shove/spawn
  cue counts and every surviving enemy's position and health — to be identical to a bare
  `GameRun.step()` loop, with each kill rewarded exactly once.

## Deliberate exceptions

Each is a scope decision of slice #9, not a rebalance.

1. **Runners and brutes in wave 1 of the fixture only.** The prototype unlocks runners and
   brutes from wave 2 (`start_wave` 1441); the normal run stays the husk wave. The crowd
   encounter fields them in wave 1 at wave-1 health as a fixture; wave composition,
   unlocks and scaling are issue #18.
2. **The dev shove is not in the prototype.** It stands in for heavy sword hits; its knockback
   is the prototype's own formula with Colossus's knock value, and the capture builds the
   reference launch from the prototype's real `hit_enemy` (heavy blow, damage restored).
3. **Gameplay randomness is its own stream.** The speed factor (0.9–1.12) and the clock
   phase (0–10) of spawned enemies, spawn points and recoil directions follow the
   prototype's distributions but not its random sequence. The runner's weave phase is
   therefore random per enemy but controlled in the checks.
4. **No armed enemies, spitters, conditions or ultimates.** As in #8; frozen/chilled enemies
   (movement ×0.5, contact immunity) and burning-death spread arrive with #11.
5. **Cosmetics are not a gate.** Placeholder silhouettes (below) replace the prototype's
   particles, sparks and trails; they follow the logical pose only (ADR 0003).
6. **The dead are still pushed within the tick they die in**, exactly as in the prototype
   (dead enemies stay in the list until the end of the update), so a corpse can still bowl or
   be bowled; rewards still resolve once.

## Presentation

`PlaceholderEnemyVisual` draws a distinct silhouette per type without final art: husk — a
mid-size red disc with two eyes; runner — a small orange disc with five spinning spikes;
brute — a large dark-purple armoured body with a bright rim, an inner ring and two horns.
A white dashed ring marks an enemy that is stunned or flying (it is told so by the
simulation's stun timer). Spawn telegraphs are tinted and sized by type, bowling shows a
white ring and `-3`, a wall slam an orange burst and `SLAM n` with the thud sound. All sizes
belong to the visual; the collision radius comes only from `EnemyDefs`.
`godot/tests/alt_enemy.tscn` (a 5× stretched, rotated visual) leaves the shoved crowd fight
unchanged, as asserted by `crowd: swapping enemy visuals leaves the crowd fight unchanged`.

## Validation

Run on build `20261114-105847-25a30ea24` (source commit 25a30ea, clean tree; later commits
change documentation, the evidence capture script and the mutation list only), Linux,
Godot 4.7.2-stable.

| What | Result |
|---|---|
| `./build-godot.sh --checks-only` / full `./build-godot.sh` | `CHECKS PASSED: 519` (289 from #8 plus 230 new); full build OK, Windows ZIP and Web bundle produced |
| `tools/godot/mutation-check.sh` | 116 of 116 deliberate bugs caught, 0 inconclusive (baseline 519 checks pass; 46 from #8 plus 70 for this slice: stats, weave, resistance, separation, bowling, wall slams, shove, wave composition, silhouettes, buttons, launch option, frame-rate dependence) |
| Reference regeneration | `capture_crowd_and_walls.py` run twice gives byte-identical output, equal to the committed JSON; `capture_fang_survival_loop.py` still reproduces the #8 JSON |
| Low/high render rates | The scripted 900-tick fight played in the real Main scene under the engine's fixed-step loop at 5, 20, 60 and 240 fps (75 / 300 / 900 / 3603 frames) ends with an identical digest every time, equal to a bare `GameRun.step()` loop: 12 kills, 12 kill cues, 4 wall slams, 8 bowls, 7 shoves, same survivors to three decimals |
| **Web export, headless Chromium (software WebGL 2 via SwiftShader, 1280×720)** | Served the built bundle over HTTP: `?encounter=crowd` shows the telegraphed wave and the three enemy types, the legend and the Shove/Normal buttons; a real keyboard `F` (browser key event) launches nearby foes (white dashed stun rings, shove ring); the Shove button shoves; `C` switches to the normal husk wave and back. `?encounter=wall` with an immediate `F` slams the pinned crowd into the east wall (`SLAM 7` text, wall-side foes ringed) and shows bowling `-3`/`7` numbers. No console errors. `tools/godot/web-encounter-capture.mjs` reproduces it. |
| **Windows export, under Wine 11 on Linux (not a Windows machine)** | The full build's `Swordster.exe`, extracted from the ZIP, run as `Swordster.exe -- --encounter=crowd` with Godot's Movie Maker (`--write-movie`, 30 fps frames of the game's own viewport), shows husks, spiky runners and brutes arriving and being fought by the three Fang swords for 15 s. No input was sent (no X11 test events: they trigger a desktop permission prompt), so shove, wall slam and bowling were **not** exercised in the Windows export. |

Screenshots (in `docs/reference/runners-brutes-crowd/`): [`web-wall-slam.png`](runners-brutes-crowd/web-wall-slam.png),
[`web-wall-bowling.png`](runners-brutes-crowd/web-wall-bowling.png),
[`web-crowd-shove.png`](runners-brutes-crowd/web-crowd-shove.png),
[`web-normal-wave.png`](runners-brutes-crowd/web-normal-wave.png),
[`wine-crowd-fight.png`](runners-brutes-crowd/wine-crowd-fight.png),
[`wine-crowd-brutes.png`](runners-brutes-crowd/wine-crowd-brutes.png) (the Wine frames are the
game viewport as written by Movie Maker; the top of the HUD is cropped in them).

## What was not verified

- **No real Windows machine** and no real Android device: deferred to #6 and #22 by the
  maintainer's decision. The Wine run proves the export launches and fights, not that it
  behaves on Windows, and it did not exercise shove, slam or bowling.
- Web was run in headless Chromium with a software renderer and synthetic browser input, not
  in Firefox, on a real GPU or on a phone. Frame pacing, audio and real multi-touch were not
  measured. The Shove/Crowd buttons were driven by a mouse click, not by touch; the headless
  checks drive them with `button_down` like the #8 buttons.
- Only the launch options were verified by parsing in a headless child process
  (`--encounter=crowd|wall`); the browser query string `?encounter=...` worked in the
  Chromium run, but the Windows `--` argument path was only exercised under Wine
  (`--encounter=crowd`).
- Runners and brutes were not tuned for fun or difficulty: the three-Fang fixture against
  the crowd encounter is a behaviour demonstration, not a balance pass.
- Spitters, projectiles, conditions, drops and later waves are out of scope (#10, #11, #17, #18).
