# Reference: Warden and Maelstrom

Slice #13 of the Godot port ([spec #4](https://github.com/theozex4ever/Swordster/issues/4)),
following [the Fang survival loop](fang-survival-loop.md),
[runners, brutes and crowds](runners-brutes-crowd.md),
[spitters, projectiles and parries](spitters-projectiles-parries.md),
[Viper Flurry](viper-flurry.md) and [elemental conditions](elemental-conditions.md). The Python
prototype `game/main.py` is the behavioural oracle. This file records what was captured from it,
the tolerances, the checks that assert each value, and every deliberate exception. Vocabulary
follows `GLOSSARY.md`: **Warden** is a sword type, **Maelstrom** its ultimate, triggered through
its equipped **sword slot**; **Converge** is a different command (issue #16) and is not an ultimate.

The sword type keeps the prototype's internal identity: Warden is `SWORD_TYPES["blade"]`, so the
Godot type id is `blade` (`SwordDefs.WARDEN`), exactly as Fang is `fang`; the displayed names
(Warden, Maelstrom) come from `SwordDefs.display_name` / `ultimate_name`.

## How the reference was captured

`tools/reference/capture_warden_maelstrom.py` reuses the loader and helpers of
`capture_fang_survival_loop.py` and `capture_viper_flurry.py`, drives the prototype's real classes
(`Game`, `Sword`, `Enemy`, `Projectile`) with fixed 1/60 s steps under SDL's dummy drivers, and
writes `godot/tests/reference/warden_maelstrom.json`. Regenerate with:

```sh
python3 -I tools/reference/capture_warden_maelstrom.py godot/tests/reference/warden_maelstrom.json
```

Nothing is re-implemented: the targeting, the windup, the sweep, the hit set and the parries come
from the prototype's own `Sword.acquire`, `Sword.begin`, `Sword.update` and `Sword.strike`; the
whirl, pull, beats, burst and recovery from `Sword.ultimate` and `Sword.update_ult`; the damage,
crits, rounding, knockback, stun and elements from `Game.hit_enemy` and `Game.afflict`; the keys
through the real `Game.handle` with synthetic `KEYDOWN` events and a patched mouse position. Every
case writes its fixture (`setup`) into the JSON and the Godot checks build their scenarios from it.

**Conditions per case.** Elemental conditions are decided case by case and written into each
`setup.conditions`; the Godot side builds `RunScenario.new()` or `.without_conditions()` from it
and the checks reject a reference that does not say which (`fixture_scope.afflict_enabled_cases`
lists the cases that ran with the prototype's own `afflict`):

- **Off** (as the earlier slices' references were captured; `Game.afflict` is a no-op) for every
  physical case: targeting, sweep geometry and coverage, hit-once, parries, the whirl's pull,
  beats, burst, recharge, refusals, clocks and deaths.
- **On** for the cases whose subject is how Warden's blows apply conditions: `sweep_conditions`
  (a poison, ice and fire Warden sweeping one enemy for 340 ticks, and a poison Warden sweeping a
  pack of three) and `maelstrom_conditions` (the three elements through a Maelstrom on a husk, a
  brute and a runner). Their traces carry every condition field per tick.

Other controls (asserted by the capture, recorded as `fixture_scope`):

- Every enemy is an unarmed husk, runner or brute (`armed is None`): arming and drops are issue #17.
- Only Warden swords are equipped and Converge is never commanded (issue #16).
- The wave machine is off (issue #18). A sword that is not meant to fight has its automatic-attack
  cooldown parked at 99 s. Enemies stand still (speed 0). Crits are forced off, or on for the crit
  cases, by pinning `random.random`.
- Two kinds of case start an attack directly with `Sword.begin(target, aim)`, the prototype's own
  entry point (Converge uses it too): the arc-coverage and parry grids, so the sweep's pivot is chosen
  by the fixture instead of `acquire`. The Godot checks call `SwordState.begin` the same way.
- What the prototype draws at random cannot be matched across random streams (crit rolls, a
  random direction when a vector is zero-length); no case depends on them.

## Tolerances

Chosen before accepting any difference; the same as the earlier slices.

| Quantity | Tolerance | Why |
|---|---|---|
| Position | ±0.05 px | Same algorithm at the prototype's 60 FPS step; float noise only. |
| Enemy and sword velocity | ±0.5 px/s | The prototype's sword velocity is a position difference x 60 and the capture rounds positions to 0.001. |
| Timers, cooldowns, shake, stun, flash, hitstop | ±0.002 | Same. |
| Angles | ±0.002 rad | The capture rounds to 0.0001. |
| Enemy health | ±0.001 | Integers in practice. |
| Event ticks (a first hit, a parry, a transition, a recharge) | ±1 fixed tick | Cases that compare per tick (below) are exact; only the summary comparisons use the slack. |
| Damage, kills, counts | exact | Integers. |

In practice every compared tick and value matched exactly: the traces are compared on **every
tick** (sword pose, angle, velocity, phase, side, clocks, recharge; every enemy's position, health,
velocity and stun; every condition field), not just at sampled ticks.

## Reference values and the checks asserting them

Line numbers refer to `game/main.py` at this repository's base commit.

### The sword (`SWORD_TYPES["blade"]` 85–89; `Sword.__init__` 567–595)

| Quantity | Value |
|---|---|
| Name / blurb | Warden / "mid / sweeping arc" |
| Length, width | 54 px (x1.08 / x1.18 by rarity), 8 px |
| Range | 245 px (x1.06 / x1.12) |
| Cooldown | 0.85 s (x0.87 / x0.74): 0.85 / 0.7395 / 0.629 s |
| Damage | 17 (x1.3 / x1.75), rounded half-even, x2 on a crit (12 %): 17 / 22 / 30 (a crit: 34) |
| Knockback / hitstop / shake | 300 x the enemy's knock factor (x1.3 on a crit); 0.05 s (x1.5 on a crit); 0.16 (+0.1 on a crit) with a direction |
| Windup | 0.16 s (10 ticks) |

Asserted by `warden: identity, constants and rarity numbers against the prototype`.

### The automatic attack (`Sword.acquire` 598–610; `Sword.begin` 612–620; `update` windup 700–706, strike 757–775; `strike` 977–980)

- **Targeting.** The nearest enemy whose distance from the *player* is under `range + radius`
  (a husk 260 px away is acquired, 262 px is not; the nearer of two wins whichever was placed first).
  Asserted by `warden: who it targets`.
- **Windup.** The pivot sits `0.55 x length` behind the aim point on the line from the player;
  `amid` is the heading of that line; the swing runs from `amid - side x 1.9` to
  `amid + side x 1.45`; the sword springs (k 220, c 26) onto the start of the arc and turns toward it
  (rate 18). All of it is recomputed every tick, so the arc follows a moving target until the strike.
- **Alternation.** `side` flips at the *start* of every attack (it begins as 1, so the first attack
  has side -1, the second +1). Captured: attacks begin on ticks 1, 66 (Common), 1, 60, 119 (Rare),
  1, 53, 105 (Mythic) with strikes on 11, 76 / 11, 70, 129 / 11, 63, 115. Asserted by `warden: the
  alternating sweep, tick by tick, against the prototype`.
- **The sweep.** 0.15 s (9 ticks of motion) with `u = 1 - timer/duration` and a cubic ease-out; the
  sword's pose rides the arc at `0.5 x length` from the pivot. Each tick the cutting segment, from
  `0.12 x length` to `1.15 x length` from the pivot, is tested at **two** angles: halfway between
  last tick's heading and the new one, and the new one. An enemy within `radius + 8` of either
  segment, and not yet in this attack's hit set, is struck once (direction `0.6 x tangent + the
  push away from the player`, the sword's knockback) and added to the hit set. After each sample
  every orb within `radius + 6` of the segment is parried, **whether or not the sword hit anything**
  (a Fang strike only parries on a tick that hits nothing). On the last tick the sword recovers for
  0.3 s at 300 px/s along the swing's tangent.
- **Captured sweep** (Common, a husk at (1470, 930), player (1300, 900), crit off): windup on tick 1,
  strike on 11 (the sweep's first step is tick 12), the hit on tick 12 for 17 (0.0933 s of flash left after the tick, hitstop
  0.05 s, shake 0.16), recovery from tick 25, idle again on tick 44, the second attack winds up on tick 66
  and strikes the other way (hit on 77); the crit case hits for 34 with hitstop 0.075 and shake 0.26; Rare hits for 22
  on ticks 13 and 72, Mythic for 30 on 13 and 65.
- **Arc coverage.** For both swing directions a stationary husk was placed at 78 probe points
  around the pivot (angle -2.75..+2.75 rad, radius 8..72 px) while the sweep targeted a husk 200 px
  east: the blade reaches 32 of them in one direction and 39 in the other, on ticks 11, 17, 18, 19
  (and 20-22), and misses the rest, including points inside the sampled gaps. Asserted at every
  point by `warden: which points the swinging blade reaches, on which tick, in both directions`.
- **Parry coverage.** An orb parked at 161 points per direction with no enemy in the sweep is parried
  at 83 and 87 of them on ticks 11-17 with the parry's hitstop (0.025 s); with an enemy in the sweep
  too, the hit and the parry both resolve on tick 12 and the hitstop is the larger, 0.05 s. An orb the
  blade never meets is left alone. Asserted by `warden: projectiles are parried through the shared rule`.
- **Hit once per attack.** Three enemies in front of the sword are hit 3, 3 and 2 times over the
  150 ticks (one per attack at most; the last is out of reach of one sweep); five spread around the player, 1, 0, 2, 0, 1;
  nobody twice in one attack. Three Wardens at once each cut their own arc. Deaths: a 5 hp enemy in the
  sweep dies once with three motes and a chain of 1; two Wardens striking a 10 hp enemy on the same tick
  kill it once and the second finds a corpse; a target that dies in the windup is dropped and the
  sweep carries on. Asserted by `warden: several enemies in one sweep take one hit each per attack` and
  `warden: deaths during a sweep resolve once`.

The reference reproduces a quirk of the prototype on purpose: the sword's heading during the windup is
eased with `ang_lerp` (shortest way) and the strike takes `lerp(prev_a, a, 0.5)` of two angles that can
differ by a whole turn, so the first tick's halfway sample can point the wrong way round the circle.
It is ported exactly (the same arithmetic on the same values), not corrected.

### Maelstrom (`SWORD_TYPES["blade"]["ult"]` 89; `Sword.ultimate` 842–846; `Sword.update_ult` 896–929)

| Quantity | Value |
|---|---|
| Name | Maelstrom (not a skill shot) |
| Range / base radius | 400 px / 100 px (x the rarity's size: 100 / 108 / 118) |
| Recharge | 11.0 s x the rarity's cooldown factor: 11.00 / 9.57 / 8.14 s, from the command |
| Whirl | 2.2 s (132 ticks of gameplay time); the sword circles the centre at `radius x size`, spin 15 rad/s, closing `min(1, dt x 25)` of the way to its place each tick |
| Start | no blink: the sword begins from where it hangs, its spin starting at its bearing from the centre |
| Reach of the blades | `radius x size + 0.7 x length`: 137.8 px (Common), 148.8 (Rare), 162.6 (Mythic) |
| Pull | every enemy with `8 < distance < reach + 120` moves `170 x knock factor` px/s straight toward the centre (a brute 0.35, a runner 1.3), directly on its position |
| Beats | the first after 0.15 s, then every 0.2 s: everything within `reach + radius` takes 0.6 x damage (10 / 13 / 18), heavy (flash 0.2, no hitstop, no hit shake), knockback 40 along the tangent, one dose of the element; if any was struck, shake +0.08 |
| Burst | when the clock ends: everything within `reach + 30 + radius` takes 1.6 x damage (27 / 35 / 48), heavy, knockback 520 away from the centre, **two** doses of the element; shake +0.35, hitstop 0.06 s |
| Recovery | 0.3 s at 500 px/s along the spin's tangent, then idle |
| Parries | none: an orb inside the whirl survives it |

Captured (Common, a husk 60 px from the centre): the first beat on tick 10, then 23, 36, 49, 62, 75, 88, 101, 114
and 127 (ten beats, each for 10 with the enemy's flash at 0.1833 and shake 0.08), the burst on tick 133 for 27 (shake 0.35,
hitstop 0.06), recovery from tick 133, idle on tick 156, the recharge 8.783 s at the burst and 8.467 s at idle. The crit case
doubles every blow (20, 54); Rare and Mythic hit for 13 / 35 and 18 / 48 and reach farther.

Asserted by `warden: Maelstrom's whirl, beats, burst and recovery, tick by tick` (four cases, 175
ticks each), `warden: the pull, who is struck by the beats and the burst` (seven enemies of three
kinds at seven distances, one a hair outside the pull range, for Common and Mythic reach), `warden:
kills during the whirl resolve once`, and `warden: Maelstrom's range clamp and start (no blink)`.

### Starting it (`Game.ultimate` 1400–1415; `Game.handle`)

The same rules as every ultimate (see [Viper Flurry](viper-flurry.md)): refused when paused or dead,
when the slot holds no sword, while that slot's ultimate runs (even with a zero recharge) and while it
recharges (a cue with the seconds left); the aim point is clamped to **400 px** from the player; the
recharge starts at once. Captured clamp: a point 100 px / 400 px away is kept; 401 px, 900 px,
a diagonal and a far south-west point land exactly 400 px from the player; a point on the player is
not clamped. A command during an automatic attack interrupts it and clears the target and the hit set,
also mid-sweep. Asserted by `warden: Maelstrom's range clamp and start`, `warden: recharge, refusal and
the other slots` and `warden: Q, E and R and the touch aim`.

### Clocks, death and the other swords

| Case | Reference |
|---|---|
| paused for 120 ticks in the middle of the whirl | the whirl, its clock, the beat timer, the pull and the recharge are frozen bit for bit |
| the player dies in the middle of the whirl | the death's own hitstop holds the next tick; the sword is then idle, nothing is struck or pulled afterwards, the recharge keeps running |
| 0.2 s of hitstop at the command | first beat on tick 23 (13 ticks of hitstop, then 10) |
| slow motion x0.25 | first beat on tick 36; clocks and recharge a quarter as fast |
| recharge reaches zero | tick 664 / 579 / 493 (Common / Rare / Mythic: 660 / 574 / 489 ticks of gameplay time plus the burst's 0.06 s hitstop) |
| the other two Wardens while one whirls | keep sweeping |

Asserted by `warden: pause, the player's death, hitstop and slow motion in the middle of the whirl` and
`warden: recharge, refusal and the other slots`.

### Conditions (`Game.hit_enemy` 1122–1158; `Game.afflict` 1160–1181)

A sweep applies one dose; a beat one; the burst two (`stacks=2`: fire burns twice as hard, poison and chill stack
two at a time). Captured with a Rare ice Warden on a husk, a brute and a runner: chill stacks 1, 2, 3 on the first
three beats and the fourth (tick 49) freezes all three (1.5833 s; 0.9433 s on the brute), after which a beat hits
for 17 instead of 13 (the shatter bonus, 13 x 1.3); a poison Warden reaches the six-stack cap on tick 75; a
Mythic fire Warden burns at `(1.5 + 0.2 x 29.75)` = 7.45 per second per dose, 14.9 after the burst's two. Asserted by `warden: a sweep's blow applies its element once` and
`warden: Maelstrom's beats apply one dose, its burst two` (health, burn, poison, chill, frozen,
accumulator and position of every enemy compared on every tick).

## What the port adds, and how it is shared

- **A small per-type dispatch, not a framework.** `SwordDefs.base_*(type)` and `ultimate_*(type)`
  return the type's numbers; `SwordState.begin_ultimate`, `_update_ultimate`, the windup and the
  strike each add one `match` branch for Warden (`_update_sweep_windup`, `_update_sweep`,
  `_update_maelstrom`). Pike (#14) and Colossus (#15) add a branch to each of the same places.
- **One hit rule.** A Warden's blow is `GameRun.hit_enemy` (crit, frozen bonus, rounding, knockback,
  stun, death once, the element through `GameRun.afflict`); `heavy` and `stacks` are its existing
  parameters. The hitstop and shake of a normal blow are now the *sword type's own* (Fang 0.02 / 0.07,
  Warden 0.05 / 0.16: the prototype's `sword.t[...]`), where they were Fang's constants; Fang is unchanged.
- **One parry rule.** `SwordState._update_sweep` passes each sampled segment and pad 6 to
  `GameRun.parry_projectiles`, the same function Fang's strike uses (pad 8).
- **Gameplay owns the geometry (ADR 0003).** The sweep's pivot, start and end angles (`sweep_pivot`,
  `sweep_from`, `sweep_to`) and Maelstrom's `maelstrom_radius()`, `maelstrom_reach()`,
  `maelstrom_pull_range()` are sword state the presentation reads to draw the arc and rings. No visual
  feeds anything back; the check that swaps in a stretched, rotated sword visual (`alt_sword.tscn`)
  leaves the whole Warden fight unchanged.
- **Update order** (unchanged, `GameRun.step()`): paused returns; the real clock, shake and kick advance;
  hitstop freezes everything else; slow motion scales `dt`; the player; each sword slot's
  `SwordState.update` in slot order (**a sweep's hits and parries and a whirl's pull, beats and burst all
  happen here, before the enemies move that tick**); every enemy's `update`; `_separate`; the conditions'
  damage over time, deaths and spread; contacts; removal of the dead; projectiles; motes; counters and the
  wave director.
- **Cues.** `SWORD_STRIKE` at the start of a sweep (sound), `ULTIMATE_STARTED` (slot in `amount`),
  `MAELSTROM_BEAT` (`amount` = enemies struck, `radius` = reach, `element`) and `MAELSTROM_BURST`; each
  blow is an ordinary `ENEMY_HIT`.
- **HUD.** Each slot card shows the key badge, the ultimate's name (Viper Flurry / Maelstrom), READY /
  ACTIVE / seconds left, the recharge bar, the element tag and, new in this slice, the sword type under the
  bar ("Fang sword", "Warden sword"). The warden encounter's legend counts foes left, Maelstroms finished
  and hits landed.
- **Presentation.** Warden is drawn with a broad blade, a fuller, a wide crossguard and a pommel (Fang stays
  a needle). During the windup a faint band shows the arc about to be cut and brightens as the windup runs
  out; the sweep leaves a fading fan along the arc it cut; a Maelstrom outlines the reach of the blades, a
  dashed ring at the pull range, spinning arcs and a short tick on every enemy being dragged, a ring at every
  beat and a burst of rings and sparks at the end; the blade keeps its afterimages. A beat that struck something
  and the burst are heard (`strike`).

## Deliberate exceptions

Each is a scope or correctness decision of slice #13, not a rebalance.

1. **The warden encounter is the only way to field Warden; the normal run is unchanged.** The run's default
   loadout is still three Fang swords (issue #16 sets the final default; the prototype's is Fang / Warden /
   Colossus). The mixed loadout is a development fixture in the existing dev-encounter mechanism
   (`RunScenario.warden_encounter()`: one wave of husks, runners and two brutes against Fang poison, Warden
   ice, Warden fire), reachable with the dev button / `C` (the cycle is now normal, crowd, spitters,
   conditions, warden, normal), `--encounter=warden` and `?encounter=warden`. The earlier slices' cycle checks
   were extended by one step; nothing else about them changed.
2. **Gameplay randomness is its own stream.** Crit rolls and the random heading drawn for a zero-length
   vector follow the prototype's distributions, not its random sequence; cosmetic randomness never uses it.
3. **The sweep is sampled exactly as the prototype samples it.** The prototype tests the cutting segment at
   two angles per update; the port does the same per *fixed 60 Hz tick*, so what a sweep reaches never
   depends on the render rate (the render-rate probe plays a Warden fight at 5, 20, 60 and 240 fps with
   identical outcomes), and where the prototype's own variable step (up to 1/30 s) would sample farther apart,
   the port samples at the prototype's 60 FPS spacing, as the other slices do. The two samples leave gaps in
   the arc (a point can be skipped between them; the arc-coverage case records exactly which); no extra
   sample was added, as that would change which enemies are hit.
4. **A corpse is neither pulled nor struck, and its beat shakes nothing (hardening).** The prototype's whirl
   iterates every enemy including one killed earlier in the same update (it is removed at the end of the
   update): such a corpse is pulled, "struck" (a no-op) and counts toward a beat's shake. The port skips a dead
   enemy in the pull, the beats and the burst, so a beat that struck nothing live makes no shake. The sweep
   also skips corpses (the prototype's `hit_enemy` returns at once for them). Unobservable except for that
   shake. Asserted by `warden: enemies that die or leave the run are handled safely`; the mutations
   `maelstrom-pulls-corpses`, `maelstrom-beat-strikes-corpses`, `maelstrom-burst-strikes-corpses` and
   `sweep-hits-corpses` fail it.
5. **Enemies that leave the run, alive, are never reached.** The sweep and the whirl iterate `run.enemies`
   only, and the sword's attack target is dropped by the guard of #12 (exception 10 there), so a removed enemy
   takes no damage and causes no kill, mote, cue or shake (spec decision 7). Same reachable behaviour as the
   prototype. Asserted by the same check.
6. **The hit set is per attack and per sword.** It is cleared when an attack begins and when an ultimate
   begins (the prototype clears `hit` in `begin` and `ultimate`), kept as a dictionary keyed by the enemy.
7. **Hit feedback is the sword type's own.** `GameRun.hit_enemy` now reads the sword's hitstop and shake
   (prototype `sword.t["hitstop"]`, `["shake"]`) instead of Fang's constants; `null` (no sword) falls back to
   Fang's. Fang's own numbers equal them, so nothing about Fang changes.
8. **Cosmetics are not a gate.** The prototype's lift (`z`), trails, element sparks, the floating
   "MAELSTROM" text style and its sounds beyond "whoosh" and "slash" are not reproduced; the placeholder
   drawing follows the logical pose (`sweep_*`, `ultimate_*`). The refusal text is "recharging Ns" as in #12.
9. **No touch ultimate buttons and no Converge.** Touch aiming (`ultimate_at_nearest`) works for a Warden but
   the on-screen buttons are issue #20, and Converge's fast windup (`begin(..., fast=True)`) is issue #16.
10. **A Warden rolls its own element.** Maelstrom's beats and burst use the sword's element and power like every
    other blow (`afflict(enemy, element, damage, stacks)`); no new element rule was introduced.

## Validation

Linux, Godot 4.7.2-stable. Base `origin/main` `066041d`; branch `feat/13-warden-maelstrom`.

| What | Result |
|---|---|
| `./build-godot.sh --checks-only` / full `./build-godot.sh` | `CHECKS PASSED: 1165` (159 of them in `warden_maelstrom_checks.gd`; the earlier slices' dev-encounter cycle checks were extended by one step). Full build OK on a clean tree: `20261115-004119-fa9ab5b65` (head `fa9ab5b`); `sha256sum -c SHA256SUMS` over the pair passes. |
| `tools/godot/mutation-check.sh` | **453 of 453** deliberate bugs caught, 0 inconclusive, 0 survived on the final list. Evidence: one full pass in 8 parallel shards (`SHARD=i SHARDS=8`) on commit `43e2dbb` caught 452 of 454 with one survivor (`maelstrom-burst-ring-lost`: the ring check only counted rings, now exact) and one inconclusive (`warden-key-renamed`: renaming the type id trips an assertion in `SwordState.equip`, a crash and never a behavioural rejection, so the mutation was removed; the identity is asserted by the definitions check). The survivor, and the two earlier-flagged `placement-health-dropped` (a crash in an early version of this file's checks, since made index-safe) and `heavy-hit-causes-hitstop` (its anchor was moved by this slice's edit of `hit_enemy`), were rerun with `ONLY=...` (new filter) on the final checks and are caught. 111 of the 453 are this slice's (Warden constants, sweep rules, Maelstrom rules, fixtures, HUD, effects, sound, visual). The only later game-code change is the legend text (`fa9ab5b`); no mutation touches it. |
| Reference regeneration | All six captures (`capture_warden_maelstrom.py`, `capture_fang_survival_loop.py`, `capture_crowd_and_walls.py`, `capture_spitters_and_parries.py`, `capture_viper_flurry.py`, `capture_elemental_conditions.py`) rerun on the head give output byte-identical (`cmp`) to the committed JSON; the five earlier JSON files are unchanged in this PR, as is `game/`. |
| Low/high render rates | The scripted Warden fight (a Fang and two Wardens, six ultimates including two Maelstroms still whirling when it ends, three refused presses, sweeps and whirls through fourteen husks, three runners, two brutes and two tough posts) played in the real Main scene under the engine's fixed-step loop at 5, 20, 60 and 240 fps ends with a digest identical to a bare `GameRun.step()` loop every time. |
| Per-tick comparison with the prototype | Sword pose, velocity, side, timers, recharge and every enemy's position, health, knockback, stun (and every condition field in the condition cases) match on every tick of every captured trace, plus 156 arc-coverage and 322 parry probe points, with no tolerance used beyond the float noise of the capture's rounding. |
| **Web export, headless Chromium (software WebGL 2 via SwiftShader, 1280x720)** | Build `20261115-004119-fa9ab5b65` served over HTTP with `?encounter=warden` and driven with browser mouse-move and key events (`tools/godot/web-encounter-capture.mjs`, `SCENARIO=warden`): the Wardens sweep (fan of the arc, damage numbers 17 / 7), **E** at the cursor starts a Maelstrom (reach ring, dashed pull range, spinning arcs, the card reads ACTIVE then `8s`), **R** starts the other slot's, **E** while recharging is refused, **Q** is Viper Flurry. Screenshots below. Console: the three Godot start-up lines, no errors. The frame pacing of the capture is the browser's, not a measurement. |
| **Windows export, under Wine 11 on Linux (not a Windows machine)** | Build `20261115-004119-fa9ab5b65`: the full build's ZIP extracted unmodified, its own `SHA256SUMS` verified, the shipped `Swordster.exe` and `Swordster.pck` run as `wine ./Swordster.exe --resolution 1000x563 --write-movie <frames> --fixed-fps 30 --quit-after 450 -- --encounter=warden`: engine-side frames of the game's own viewport (no desktop capture, no input, nothing added to the game). The frames show the warden encounter's HUD (the three cards **Q Viper Flurry / E Maelstrom / R Maelstrom READY**, with the "Fang sword" / "Warden sword" lines), the Fang and two Wardens with their broad blades, the husks arriving, and a Warden's sweep cutting with its fan and a hit number. **What this does not show:** a Maelstrom in the Windows build. No key or mouse event was sent to the shipped build (no autopilot exists in the game), so Q/E/R input in a Windows build belongs to the deferred device matrix (#6/#22); the Maelstrom itself is shown in the Web build. |

The game code of both exports is the head `fa9ab5b`; everything committed after it is documentation and screenshots.

Screenshots (in `docs/reference/warden-maelstrom/`):
[`web-warden-maelstrom-active.png`](warden-maelstrom/web-warden-maelstrom-active.png) (a Maelstrom whirling, the telegraph of the other Warden's coming arc),
[`web-warden-sweep-fan-and-recharge.png`](warden-maelstrom/web-warden-sweep-fan-and-recharge.png) (the fan a sweep leaves; E counting down),
[`web-warden-r-maelstrom.png`](warden-maelstrom/web-warden-r-maelstrom.png),
[`wine-shipped-warden-hud-ready.png`](warden-maelstrom/wine-shipped-warden-hud-ready.png) and
[`wine-shipped-warden-sweep.png`](warden-maelstrom/wine-shipped-warden-sweep.png) (shipped pack, no input).

## What was not verified

- **No real Windows machine** and no real Android device (#6, #22). The Wine run proves the shipped export
  launches and renders the Warden fight and HUD, not that it behaves on Windows. No touch ultimate controls exist
  yet (#20), so Android has nothing to test.
- Web was run in headless Chromium with a software renderer and synthetic browser input, not Firefox, a real GPU
  or a phone. Frame pacing and audio were not measured (audio was muted).
- Windows evidence is engine-side frames of the shipped pack under Wine with no input: **no Q/E/R key or mouse
  event was exercised in any Windows build** (deferred to #6/#22).
- Warden and Maelstrom were not tuned for fun or difficulty; the numbers are the prototype's.
- Out of scope and untouched: Pike and Skewer (#14), Colossus and Cataclysm (#15), Converge and the final
  default loadout (#16), drops and swaps (#17), multi-wave generation (#18), touch ultimate buttons (#20).
