# Reference: waves, rewards and the normal run

Slice #18 of the Godot port ([spec #4](https://github.com/theozex4ever/Swordster/issues/4)), following
[the Fang survival loop](fang-survival-loop.md), [runners, brutes and crowds](runners-brutes-crowd.md),
[spitters, projectiles and parries](spitters-projectiles-parries.md), [Viper Flurry](viper-flurry.md),
[elemental conditions](elemental-conditions.md), [Warden and Maelstrom](warden-maelstrom.md),
[Pike and Skewer](pike-skewer.md), [Colossus and Cataclysm](colossus-cataclysm.md) and [drops and swaps](drops-swaps.md).
The Python prototype `game/main.py` is the behavioural oracle. This file records what was captured from it, the tolerances,
the checks that assert each value and every deliberate exception. Vocabulary follows `GLOSSARY.md`: an **armed enemy** carries
one **spirit sword** that lies where it fell as a **sword drop**; the player's **swap** claims one; **Converge** and the
**ultimate** are different commands.

The normal run (no `--encounter`, no `?encounter=`) now plays the prototype's own waves **until the player dies**: wave 1 arrives
1.6 s after the start, every wave has `5 + 3 w` enemies drawn from the pool its number unlocks, foes arrive armed by the rule
slice #17 ported, the rarity of what they carry grows with the wave, and a break follows every clear. Every earlier fixture and
dev encounter keeps its own composition, unarmed (the drops encounter armed), exactly as before.

## How the reference was captured

`tools/reference/capture_waves.py` reuses the loader and helpers of the earlier captures, drives the prototype's real classes
(`Game`, `Enemy`) under SDL's dummy drivers with fixed 1/60 s steps and writes `godot/tests/reference/waves.json`. Regenerate:

```sh
python3 -I tools/reference/capture_waves.py godot/tests/reference/waves.json
```

The output is byte-identical on every run (`cmp` of two runs, and of a run against the committed file). Nothing is
re-implemented:

- the composition pools from `Game.start_wave` itself: the call it makes to `weighted()` is **spied on**, so the pool recorded
  for each wave 1 to 30 is the list the prototype built; the kind a draw picks is the real `weighted()` at, just under and just over
  every cumulative weight;
- the health from `Enemy.__init__` (four kinds, thirty waves, unarmed and armed) and the speed factor it draws;
- the spawn timing from the real `Game.update` / `update_waves`, tick by tick for ten waves: the tick each marker appears and each
  enemy arrives; the marker's life from `Marker`;
- the positions from the real `Game.spawn_point` with a **scripted random source** (384 single attempts from eight places, mixed
  sequences of refused and good attempts, the twelve-refusals fallback);
- completion from the real `update_waves` for each of the eight combinations of a queued enemy, a marker and a standing enemy, and
  for a corpse still in the list; the clear, slow motion, break and next wave from a played clear; the freeze under pause and
  hitstop; death (the dead player's wave machine does nothing) and `Game.reset`;
- the counters from `Game.kill` (130 kills), its chain announcements (the real `Game.text` call is intercepted), the chain's decay and
  `Game.update`'s healing motes;
- the heads-up text and the game-over statistics from `Game.draw` itself, recorded through a stand-in font;
- the prototype's **normal run against its first wave**, arming on (the earlier default-loadout capture, `converge.json`, disarmed
  it): eight seeds, no input and a Converge every 3 s, how long the clear takes, how many foes were armed, the swords lying.

**Random streams are never matched.** The port cannot reproduce Python's `random`, so every exact comparison is made from scripted
draws or from rules with no draw at all, and everything random is captured as a **distribution** over many seeded waves
(1,500 for waves below 12, 800 above; nine sampled waves) and compared within sampling error. The cosmetic stream (shake, effect
sparks) is separate from the gameplay one (ADR 0003): a check runs the same normal run with different cosmetic seeds and a
differently drawn set of replacement visuals and requires the same final state.

## Tolerances

| Quantity | Tolerance |
|---|---|
| Timers (break, banner, spawn, marker) | 2e-6 s (the reference rounds to six places); tick counts exactly |
| Spawn points | 0.01 px (the reference rounds to four places) |
| Health | 1e-4 |
| Shares in a sampled distribution | 4.5 standard errors of the difference between the two samples (+ 0.004) |
| Unscripted spawn means | 8 px for the distance, 12 px for the drift |
| The armed first wave's clear time | the prototype's range over eight seeds, +-1 s (as #16's) |

## Reference values and the checks asserting them

### Formulas (`Game.start_wave` 1441-1464, `Enemy.__init__` 485-491; `WaveDefs`)

| Value | Prototype | Port |
|---|---|---|
| Enemies in wave `w` | `5 + 3 w` | `WaveDefs.enemy_count` |
| Pool | husk 6; runner 2.5 from wave 2; spitter 2 from wave 3; brute `0.6 + 0.25 w` from wave 2 | `WaveDefs.pool_kinds`, `weight_of` |
| A draw's kind | `weighted()`: subtract each weight, first at or below zero wins, the last otherwise | `WaveDefs.kind_for` |
| Health | type x `(1 + 0.1 (w - 1))` x 1.35 when armed | `EnemyState.make`, `WaveDefs.hp_factor` |
| Speed factor | `uniform(0.9, 1.12)` | the director's marker-to-enemy step |
| Marker delay | 0.3 s after the wave starts, then `max(0.12, 0.42 - 0.02 w)` s | `WaveDefs.spawn_interval` |
| Marker life | 0.7 s | `SpawnMarker.TELEGRAPH` |

Checks: "waves 1 to 30 queue 5 + 3 w enemies from the prototype's weighted pool", "the unlocks are husk; then runners and brutes; then
spitters", "the kind a draw picks agrees with the prototype's `weighted()`", "an enemy's health is its type's x (1 + 0.1 (wave - 1))",
"markers appear 0.3 s after a wave starts and then every ... on the same ticks as the prototype for waves 1, 2, 3, 5, 10, 15, 19, 20, 21
and 30" and "the interval floors at 0.12 s from wave 15".

### Spawn positions (`Game.spawn_point` 1466-1474; `WaveDefs.spawn_point`)

Twelve tries at an angle in `[0, 2 pi)` and a distance in `[420, 720]` from the player, each clamped 50 px inside the arena; the
first more than 320 px from the player wins, the twelfth is taken whatever it is. Checks: the 384 scripted single attempts, the mixed
refused-then-good sequences, the twelve-refusals fallback (`(50, 50)` for a corner player after twelve attempts), and the unscripted
distribution from four places (inside the arena, within 720 px, the prototype's mean distance and drift).

### Arming and rarity (`Game.start_wave` 1449-1460; ported by #17, now played every wave)

Husk 20 %, runner 12 %, spitter 22 %, brute 75 % to carry a sword; the first two enemies of **wave 1** carry one for sure, the very
first a Pike; Mythic below `min(0.25, 0.02 + 0.02 w) + 0.075 [brute]`, Rare below `min(0.55, 0.16 + 0.04 w) + 0.15 [brute]`.
`LootDefs` pins every branch from scripted draws (#17). This slice adds the **distribution over played waves**: for nine sampled
waves the shares of each kind, of armed by kind, of each rarity (and of a brute's), of each sword type and of each element agree with
the prototype's within sampling error; the first-wave guarantee holds on 40 seeds through the whole pipeline (queue, marker, the first
enemy to appear carrying the Pike with 40.5 health); wave 2's first enemy is armed by chance only (the prototype's 72 of 300 armed).

### Completion, breaks, death and restart (`Game.update_waves` 1696-1722, `Game.reset` 1060-1097)

A wave completes only when its queue, its markers and every enemy in the list (a corpse still in it included) are gone; the next tick
shows **WAVE CLEARED**, starts 0.7 s of x0.3 slow motion and a 3.2 s break that counts down in slowed time; the next wave starts
221 ticks later (the prototype's count), the banner `WAVE n`. Pause and hitstop freeze the spawn and break timers; slow motion
runs them at x0.3. A dead player's wave machine does nothing (no spawning, no marker countdown, no completion). A restart (button or
R after the 0.8 s delay) puts every run-owned thing back: wave 0, 1.6 s to wave 1, no kills, chain, best chain, queue, markers,
enemies, orbs, drops, motes or banner. Each is a named check ("a wave completes only when ...", "the last kill completes the wave
on the next tick", "the break counts down in slowed time", "the next wave starts 221 ticks after the clear", "a fresh run waits
1.6 s", "the spawn timer does not move while paused", "with the player dead nothing spawns", "a restart puts every run-owned thing
back").

### Counters and the heads-up display (`Game.kill` 1257-1263, `Game.update` 1627, `Game.draw` 2072-2086, 2171)

Each kill counts once, extends the chain and restarts its 2.6 s window and leaves three healing motes (0.5 health each); a chain of
10, 25, 50 and 100 announces itself over the player; the best chain survives the chain's end. The wave line reads `WAVE n   kills k`
and, from a chain of three, `chain c`; the game-over screen reads the prototype's `THE SWORDS FALL SILENT` and
`wave w   kills k   best chain b`. Healing is the motes alone: **the prototype heals nothing when a wave is cleared**.

### The normal run's armed first wave against the prototype's (`normal_first_wave` in the reference)

On eight seeds, with no input and with a Converge at the nearest enemy every 3 s, the default loadout clears the armed first wave
within the prototype's range +-1 s, never dies, kills all 8, has 2 to 8 foes armed with a Pike on the first, and as many swords lying as
foes were armed.

## What the port adds, and how it is shared

- `WaveDefs` (new): every formula and constant above, pure functions of their arguments (no random stream), so a check can pin every
  boundary; `WaveDirector` and `EnemyState` use it, never their own copies.
- `RunScenario.normal_run()` (new): `generated_waves`, `arm_waves`, `wave_count = 0` (never survived). **Plain `RunScenario.new()` and every
  named encounter are unchanged**: unarmed, one wave, their own composition (`generated_waves` false). `GameRun.new()` with no scenario,
  the launch without an encounter, a restart and the dev cycle's "normal" slot all use `normal_run()`.
- `WaveDirector._start_wave` draws each enemy's kind (a generated wave) and then its arming, in the prototype's order; a fixture draws
  nothing for either, so every fixture plays as before.
- `GameRun.banner_sub` and the HUD's second banner line: "armed foes carry swords - kill them and claim one" at a wave's start and
  "grab dropped swords: stand on one, press 1 / 2 / 3" at its clear, only in an armed run.
- `SimCue.Kind.CHAIN_MILESTONE` and its floating "N CHAIN!" (56 px, gold, 1.4 s rising).
- The HUD's chain readout begins at three kills in a row (the prototype's x counter), not two.

## Deliberate exceptions

- **No clear-time healing.** The issue text mentions "healing on clear"; the prototype's `update_waves` has none, so the port has none.
  Healing is the motes (3 a kill, 0.5 each), checked in the normal run.
- **The chain readout** is the wave line's `chain c` (from three), not the prototype's large `xc` counter in the top-right corner with
  its decay bar; the announcement at 10 / 25 / 50 / 100 is the prototype's.
- **Game-over statistics** read `maxi(1, wave)` where the prototype prints `self.wave` (0 only before the first wave starts, when the
  player cannot die).
- The banner's title is 56 px and fades over its last second (the prototype's is 88 px over its last half-second); the second line is 22 px.
  Cosmetic, from slice #9.
- The marker is drawn in the enemy kind's colour with a closing ring (the prototype draws one colour); cosmetic.
- The step is fixed at 1/60 s (the prototype's variable step is capped at 1/30), as in every slice.
- The prototype's 700-particle cap is a cosmetic cap on its own particles; nothing here caps enemies, queue or markers
  (`nothing caps the enemies` plays wave 30's 95 enemies in the arena at once).
- The Godot normal run is endless (`wave_count = 0`); the "WAVE SURVIVED" outcome exists only for the one-wave fixtures.

## Validation

Linux, Godot 4.7.2-stable. Branch `feat/18-waves-rewards`, started from `origin/main` `44e077b` (drops, swaps and the arming rule
behind `arm_waves`). Tooling issue #41 (one combined render-rate probe, a full FAST pass as a PR CI job) had **not merged** when
this slice was done, so the group adds **no render-rate probe of its own**: the frame-rate independence of the wave machine is
checked in the group by running the same normal run with different visuals and cosmetic randomness (below); when #41 lands, wave,
break and arming coverage belongs in its combined fight (`combined_fight.gd`), per its README.

| What | Result |
|---|---|
| `./build-godot.sh --checks-only` / full `./build-godot.sh` | `CHECKS PASSED: 1967` (the group adds 103 to #17's 1864). Full build OK on a clean tree: `20261116-040801-53b6e8c17` (head `53b6e8c17`, `SHA256SUMS` verified; every screenshot and frame below is from it). Later commits change only documentation. |
| `tools/godot/mutation-check.sh` | The new section `waves` (slice #18): **83 of 83** deliberate bugs caught in FAST mode, one at a time (`SECTIONS=waves`): every constant of `WaveDefs`, the unlock gates and pool order, the draw edge and fallback, the spawn clamp, refusal and attempt count, each of the three completion conditions, the break, slow motion and banner timings and texts, the dead player's wave machine, the first spawn gap, arming (off, off by one, by the wrong wave), the marker and the enemy forgetting their sword, health that ignores the wave, the speed range, the chain cue, the restart keeping the banner line, the HUD's chain threshold, banner line, fade, placement and the pickup card ignoring the banner, the game-over line, the chain text's size, colour, life and place, and the silent gong. The full-list FAST pass and its figures are in the pull request. |
| Reference regeneration | `capture_waves.py` rerun gives output byte-identical to itself and to the committed `waves.json` (`cmp`, three runs); no earlier reference was touched (`git diff origin/main -- godot/tests/reference` adds only `waves.json`). |
| Per-tick comparison with the prototype | Marker and arrival ticks for ten waves; the clear, slow motion, break (at four points of it) and next-wave tick for a played clear (221 ticks); the first wave 97 ticks after the start; the chain's end 157 ticks after its last kill; 384 scripted spawn positions. |
| **Web export, headless Chromium (software WebGL 2 via SwiftShader, 1280x720)** | Build `20261116-040801-53b6e8c17`, the **normal run** (no `?encounter`), played for four minutes by **browser key and mouse events only** (`tools/godot/web-encounter-capture.mjs`, `SCENARIO=waves`: WASD, left clicks for Converge, Q, E, R and 1, 2, 3, the page paused with P for every screenshot; no autopilot exists in the game). It plays waves 1 to 6 (kills past 85, chains to 18), shows the banners, spawn markers, armed foes carrying swords, drops with cards and swaps, the break after each clear, the player's death at wave 6 and the restart to wave 1 (27 screenshots). Console: the three Godot start-up lines, no errors. |
| **Windows export, under Wine 11 on Linux (not a Windows machine)** | The same build's ZIP extracted unmodified, its `SHA256SUMS` verified (all five files OK), the shipped `Swordster.exe` and `Swordster.pck` run as `wine ./Swordster.exe --resolution 1000x563 --write-movie Z:/<frames>/f.png --fixed-fps 10 --quit-after 1000` on an isolated Xvfb display (`:77`, no network listener, so no window reached the desktop; Xvfb was unpacked from the distribution's signed package into a scratch directory): engine-side frames, no desktop capture, no input, nothing added to the game. A stationary player plays wave 1, wave 2 (banner, break, drops), wave 3 and **dies in wave 3 with 32 kills and a best chain of 11**, the game over screen reading `wave 3   kills 32   best chain 11`; the frames show the wave banners, the "10 CHAIN!" announcement, WAVE CLEARED and the lying drops. **What this does not show:** input in a Windows build (a restart, a swap): that belongs to the deferred device matrix (#6/#22); the Web run shows them. |

Screenshots (in `docs/reference/waves/`):
[`web-waves-cleared-card-clear.png`](waves/web-waves-cleared-card-clear.png) (WAVE CLEARED with its second line; the pickup card has stepped below it),
[`web-waves-wave3-banner.png`](waves/web-waves-wave3-banner.png) (WAVE 3 and what to do, a Cataclysm over the arriving foes),
[`web-waves-wave5-chain-drops.png`](waves/web-waves-wave5-chain-drops.png) (wave 5, chain 18, a Rare Venom Warden in slot two, a drop's card),
[`web-waves-wave6-drops.png`](waves/web-waves-wave6-drops.png) (wave 6),
[`wine-shipped-wave-cleared.png`](waves/wine-shipped-wave-cleared.png),
[`wine-shipped-wave3-banner.png`](waves/wine-shipped-wave3-banner.png),
[`wine-shipped-10-chain.png`](waves/wine-shipped-10-chain.png) and
[`wine-shipped-game-over.png`](waves/wine-shipped-game-over.png) (shipped pack, no input).

## What was not verified

- Real-Windows input and real-device touch (issues #6, #22 and #20, by standing ruling). Windows evidence is engine-side frames of the
  shipped pack under Wine with no input.
- Touch buttons for ultimates and swaps (issue #20).
