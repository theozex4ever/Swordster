# Reference: spitters, projectiles and parries

Slice #10 of the Godot port ([spec #4](https://github.com/theozex4ever/Swordster/issues/4)),
following [the Fang survival loop](fang-survival-loop.md) and
[runners, brutes and crowds](runners-brutes-crowd.md). The Python prototype `game/main.py`
is the behavioural oracle. This file records what was captured from it, the tolerances,
the checks that assert each value, and every deliberate exception.

## How the reference was captured

`tools/reference/capture_spitters_and_parries.py` reuses the loader and helpers of
`capture_fang_survival_loop.py`, drives the prototype's real classes (`Game`, `Enemy`,
`Projectile`, `Sword`, `Player`) with fixed 1/60 s steps under SDL's dummy drivers, and
writes `godot/tests/reference/spitters_and_parries.json`. Regenerate with:

```sh
python3 -I tools/reference/capture_spitters_and_parries.py godot/tests/reference/spitters_and_parries.json
```

Nothing is re-implemented: the spitter's bands, charge and shot come from the
prototype's own `Enemy.update`, flight and the hit on the player from `Game.update`, the
parry from `Sword.update` and `Game.parry_projectiles`. Every case also writes its
**fixture** (`setup`: the enemy, projectile or sword state it started from) into the JSON,
and the Godot checks build their scenarios from that, so no starting number is copied by
hand.

Controls applied for repeatability (asserted by the capture, which records `fixture_scope`
in the JSON; the Godot checks reject a reference that does not say so):

- `afflict` (elemental conditions) is a no-op: conditions are issue #11.
- Every enemy it creates is unarmed (`armed is None`): armed foes carry 1.35× health and
  drop swords (issue #17).
- Only husks and spitters appear; the wave machine is off (the prototype brings spitters in
  from wave 3, `start_wave` 1445: issue #18).
- Only Fang swords are ever equipped and no ultimate or Converge is invoked (`swords_used`
  is `["fang"]`, `ultimates_and_converge_used` false).
- Enemy speed (the prototype draws 0.9–1.12×), clock `t` (0–10) and `shoot_cd` (1.5–3.0 s)
  are pinned per case. The cooldown after a shot (uniform 2.0–2.9 s) cannot be matched
  across random streams, so it is recorded as a range together with the intervals the
  prototype actually produced.
- Where a Fang strike has to be in a known state the case sets the sword's own fields
  (`state`, `timer`, `pos`, `dir`, `aim`) and then lets the prototype's `Sword.update` run.
  The Godot checks set the same fields on `SwordState`. Three cases instead run the whole
  acquire → windup → strike path (`fang_auto`).

The Godot side runs the same scenarios through the real `GameRun` with `GameCommand`s
(`godot/tests/spitter_and_parry_checks.gd`, registered in `godot/tests/run_checks.gd`).

## Tolerances

Chosen before accepting any difference; the same as the earlier slices.

| Quantity | Tolerance | Why |
|---|---|---|
| Position, velocity | ±0.05 px, ±0.05 px/s | Same algorithm at the prototype's 60 FPS step; float noise only. |
| Health, timers, shake, hitstop, charge, cooldown | ±0.002 | Same. |
| Event ticks (shot, hit, parry, expiry, death) | ±1 fixed tick | The two frame loops can order a same-frame event one tick apart. |
| Damage, kills, counts | exact | Integers. |

In practice every compared tick and value matched exactly; the ±1 tick band is headroom.

## Reference values and the checks asserting them

Line numbers refer to `game/main.py` at this repository's base commit.

### The spitter (`ENEMY_TYPES` 127; `Enemy.update` 533–545)

| Radius | Health | Speed | Contact damage | Knockback multiplier |
|---|---|---|---|---|
| 15 | 24 | 85 | 8 | 1.1 |

Health scales `× (1 + 0.1·(wave − 1))`: 24 / 26.4 / 28.8 / 33.6 on waves 1 / 2 / 3 / 5.
Asserted by `spitters: stats and projectile constants against the prototype`.

**Movement** keeps a distance from the player: closer than **260 px** it backs away at its
full speed, from 260 to **380 px** it circles at 0.6 × speed in the fixed direction
`(−dirp.y, dirp.x)` (from the east of the player it goes toward +y), farther it approaches.
The bands are tested on the distance at the start of the tick.

| Case (player stationary, shooting disabled) | Offset from the player at 0.25 / 0.5 / 1 / 2 s |
|---|---|
| retreat from 150 px | (−160.749, 42.867) / (−179.268, 47.805) / (−219.833, 58.622) / (−256.555, 93.191) |
| orbit from 300 px | (−299.084, 46.612) / (−297.283, 57.968) / (−292.039, 82.593) / (−275.398, 130.706) |
| approach from 450 px | (−438.919, 39.015) / (−419.828, 37.318) / (−378.011, 33.601) / (−359.665, 75.442) |

The first tick's velocity reveals the band: 259.9 px → (−8.5, 0) (retreat), 260.1 px →
(0, 5.1) (orbit), 379.9 px → (0, 5.1), 380.1 px → (8.5, 0) (approach). Asserted by
`spitters: retreat, orbit and approach`: position, velocity and facing at four times for four
distances, eight band-edge distances, and the orbit direction.

**The shot.** `shoot_cd` counts down every tick the spitter is in control, even out of range.
Once it is spent **and** the player is closer than **620 px**, the spitter charges: `charge`
grows by `dt`, its wanted velocity is multiplied by **0.15**, and when `charge ≥ 0.5 s` it
fires an orb from `pos + dirp·radius` at `dirp · 270` px/s, resets `charge`, plays "shot"
and draws a new `shoot_cd = uniform(2.0, 2.9)`. A freshly spawned spitter starts with
`uniform(1.5, 3.0)`.

| Case | Reference |
|---|---|
| spitter at 450 px, `shoot_cd` 1.0 | charge starts on tick 60, **fires on tick 90**; charge 0.017 / 0.183 / 0.35 on ticks 60 / 70 / 80; orb 19.445 px from the spitter after its first move, velocity (−269.993, 2.006) |
| 30 s of shooting from 330 px | first shot tick 66, then gaps of 154, 178, 155, 192, 172, 172, 193, 189, 184 ticks (2.57–3.22 s), i.e. cooldown 2.0–2.9 s plus 0.5 s charge |
| `shoot_cd` 0, 650 px, charge 0.2 | never charges, charge stays 0.2, cooldown keeps falling (−2.0 after 2 s) |
| 619 px / 621 px | charge 0.167 after 10 ticks / charge 0 |
| charging at 450 px | first tick velocity (−1.275, 0) (15 % of the first-tick approach), tick 10 (−8.304, 0) |
| charge 0.3, stunned | charge 0 after the stun starts; cooldown frozen at 0 (and at 0.4 for a stunned spitter with 0.4 left); nothing fires |
| player dead | the spitter wanders and never charges |

Asserted by `spitters: the charged shot` (first shot tick and every trace value up to it,
muzzle offset, heading, speed, cooldown draw in range, 30-second intervals, the cooldown
being a draw rather than a constant, spawn cooldown range) and `spitters: range, charge
slowing, stun, death`.

### Projectiles (`Projectile` 382–388; `Game.update` 1584–1592)

Radius 7, life 4.0 s, no acceleration. Each tick, in this order: move by `vel·dt`
(scaled time: slow motion slows an orb, hitstop and pause freeze it), subtract `dt` from
life; **expire** if life ≤ 0 or **leave** if the point is outside the arena rectangle (left
and top inclusive, right and bottom exclusive); **otherwise hit** the player when the
distance is under `7 + 14` and the player is neither invulnerable nor dead; the hit removes
the orb and calls `hurt_player(8, orb position)` (a flat 8: not the shooter's contact damage).

| Case | Reference |
|---|---|
| expiry in the open (from (1300, 1000) at 270 px/s) | removed on tick 241 at x 2384.5, life −0.017 |
| leaving east / west | tick 134 at x 2603 / −3 |
| leaving south / north | tick 112 at y 1804 / −4 |
| leaving diagonally | tick 95 at (2502.288, 1802.288) |
| life 0.05 s | removed on tick 4 |
| slow motion ×0.25 for 60 ticks | x 1367.5, life 3.75 |
| head-on shot from 100 px | hits on tick 18: health 92, invulnerable 0.8 s, player knocked back (−420, 0), hitstop 0.07, shake 0.45 |
| parallel shot 20 px off / 22 px off | hits (health 92) / misses (health 100, still flying) |
| iframes 0.5 s, shot passing through | no damage, the orb is **not consumed**, flies on to x 1175 |
| iframes 0.1 s, slow shot overlapping | hits on tick 39 when the invulnerability ends |
| dash (0.24 s of invulnerability) across the shot | no damage, orb alive |
| two orbs 60 px apart | one hit on tick 18, the second flies on through the invulnerable player |
| dead player | health unchanged, orb flies through |
| player on 8 health | dies on tick 18: health 0, slow motion 1.4 s at ×0.25 |
| life ends on the tick it would hit | expires (health 100): the `elif` |

Asserted by `projectiles: flight, expiry and leaving the arena` and `projectiles: damage to
the player and invulnerability`.

A spitter's contact, knockback (×1.1: Fang 187 px/s, critical 243.1) and death follow the
same rules as any enemy (`spitters: the same contact and blow rules as any enemy`).

### Parry (`Sword.update` 748–755 and `parry_projectiles` 1356–1363)

`parry_projectiles(a, b, pad)` destroys every living projectile whose centre is closer than
`radius + pad` to the segment `a`–`b`, sparks, rings, plays "parry" and sets
`hitstop = max(hitstop, 0.025)`. The prototype calls it from four places: Fang's strike
(`prev → tip`, pad 8), Warden's sweep (two sub-arcs per tick, pad 6), Pike's thrust
(`tail → tip`, pad 8) and Skewer (pad 14). Colossus's slam does not parry: it silently kills
every orb within the blast circle. **Only the Fang call is in this slice**; the rule itself
is built once and shared (below).

A Fang strike **only parries on a tick on which it hit nothing**: the hit loop `break`s on
the first enemy touched and the parry sits in the loop's `else`. A hit is a different event
from a parry: damage, knockback, the hit's own hitstop (0.02) and recovery, versus a
destroyed orb, no damage, no shake and no change to the strike.

| Case (sword mid-strike from (1000, 600), orb hanging still, one tick) | Reference |
|---|---|
| orb 0 / 10 / 14 / −14 px off the line | parried, hitstop 0.025 |
| orb 16 / 20 / −16 px off the line | not parried (reach 7 + 8 = 15 from the swept segment) |
| 14 px behind the sword's previous position / 16 px | parried / not |
| 14 px past the tip / 16 px | parried / not |
| Mythic Fang (blade ×1.18) | reaches an orb a Common one misses |
| final tick of the strike (timer 0.015) | parried, then the sword recovers |
| orb crossing the line at 270 px/s (down / up) | parried on tick 11 |
| orb flying head-on at the sword | parried on tick 15; an orb running ahead of the sword: tick 3 |
| two orbs in one sweep | both parried on tick 1; hitstop 0.025 (a max, not a sum) |
| parry on tick 1, strike goes on | still `strike` after 3 ticks; no shake (0), no kill or combo |
| orb in the same sweep as a hit on a husk | husk 30 → 23, orb **not** parried, hitstop 0.02 (the hit's) |
| the recovering sword afterwards | leaves the orb alone |
| idle sword with the orb on top of it | not parried |
| a Fang from acquire → windup → strike, orb hanging at 100 px, husk at 170 px | parried on tick 30 (0 px or 12 px off the path), first hit on the husk tick 34; an orb 40 px off the path is left alone (hit on tick 32) |
| spitter's shot with no defence | shot on tick 43, hits on tick 128, health 92 |

Asserted by `parry: what a Fang's swept strike reaches`, `parry: moving projectiles and what
the parry leaves alone`, `parry: a sweep that hits an enemy does not parry on that tick` and
`parry: a Fang that acquires, winds up and strikes by itself`.

Natural Fang fights rarely parry: a strike lasts four or five ticks and a thrown orb has to
be on the lane at that moment. The prototype shows the same (twenty-four natural
shot-and-fight scans produced no parry); the deterministic cases above are what pins the
rule down.

## What the port adds, and how it is shared

- **One projectile simulation.** `ProjectileState` (position, velocity, radius, life, a single
  `fate`) is run-owned: `GameRun.projectiles` is cleared on restart and stepped by
  `_update_projectiles` in the prototype's order (after enemy movement, contacts and the
  dead's removal, before motes). An orb resolves **once**: `resolve(fate)` accepts the first
  fate and refuses later ones, so it can be hit, parried, cleared or expire, never two of them.
- **One parry rule.** `GameRun.parry_projectiles(from, to, pad) -> int` is the prototype's
  `parry_projectiles`. Fang's strike calls it with `previous → tip` and `FANG_PARRY_PAD`.
  The later slices call the same function: Warden (#13) with each sub-arc segment and pad 6,
  Pike (#14) with `tail → tip` and pads 8 and 14. `GameRun.clear_projectiles_in_circle(center,
  radius)` is the Colossus slam's silent clearing (#15); both are covered by direct tests, so
  those slices only add their call sites. No ability framework was built.
- **Swept geometry, no rigid bodies.** The parry tests the orb's centre against the sword's
  swept segment (`SimMath.seg_dist`), exactly as the prototype does. The simulation advances
  in fixed 1/60 s ticks whatever the frame rate (a sword moves at most 28 px a tick and an
  orb 4.5 px, against a 15 px reach), so neither can tunnel past the other, and the engine's
  render rate cannot change the outcome (see the validation below).
- **Cues.** `PROJECTILE_FIRED` (muzzle) and `PROJECTILE_PARRIED` (where the orb died, pointing
  back along its flight). A hit on the player is the existing `PLAYER_HURT`; nothing is a
  parry unless it is `PROJECTILE_PARRIED`.
- **Dev encounter cycle and the spitter encounter.** The C key and the dev button now cycle
  through the dev encounters (normal → crowd → spitters → normal), restarting play each time;
  `--encounter=spitters` (Windows/Linux, after `--`) and `index.html?encounter=spitters`
  (browser) start in it. `RunScenario.spitter_encounter()` is one wave of five spitters among
  three husks with the three-Fang fixture loadout and no shove (`encounter` on the scenario
  names it). The dev button now reads `Dev: <next encounter> (restarts)` (the #9 review nit:
  it used to say only "Crowd"/"Normal" although pressing it restarts play), and the hint line
  and legends say "dev". The normal run is unchanged: wave 1 is still husks only
  (`spitters: the normal run is unchanged`).

## Deliberate exceptions

Each is a scope or correctness decision of slice #10, not a rebalance.

1. **A destroyed orb cannot also hit the player.** In the prototype `Game.update` moves and
   tests every orb in `self.projectiles` without looking at `pr.dead`, so an orb that a sword
   just destroyed this tick is still moved and, if it then overlaps the player, still calls
   `hurt_player`. The capture builds that case (`prototype_quirk`: a Fang sweep clips an orb
   24 px from the player) and the prototype's player ends on **92** health. The port resolves
   every orb exactly once (the issue asks for no duplicate hits or parries): the same case
   ends on 100 health with one parry and no hurt cue (`DELIBERATE EXCEPTION` check).
2. **"Guard behaviour" is only the Fang strike.** The issue text mentions Fang's swept attacks
   and guard behaviour. The prototype has no separate guard parry: `Sword.guard_tip` is used
   only to draw the blade's trail, and idle, windup and recovering swords parry nothing (a
   check asserts that for an idle and a winding-up Fang). The parry in this slice is the Fang
   strike's, which is the whole of what the oracle does for Fang.
3. **Spitters in a fixture, not in waves.** The prototype brings spitters in from wave 3; the
   normal run stays the husk wave. The spitter encounter fields them in wave 1 at wave-1
   health as a dev fixture; wave composition, unlocks and scaling are issue #18.
4. **Gameplay randomness is its own stream.** The first cooldown (1.5–3.0 s), the cooldown
   after a shot (2.0–2.9 s), speed factor and clock phase follow the prototype's
   distributions but not its random sequence. Only the draws a spitter needs are made, so
   existing scenarios keep their random streams.
5. **No armed spitters, conditions or ultimates.** As in #8 and #9: arming and drops are #17,
   conditions #11, the other swords #12–#15.
6. **Cosmetics are not a gate.** Placeholder shapes replace the prototype's particles and
   sparks and follow the logical pose only (ADR 0003).
7. **Out-of-arena test is exact.** The prototype's `WORLD.collidepoint` truncates floats to
   integers (a point at x = −0.5 still counts as inside); the port uses the exact half-open
   rectangle. The difference is under one pixel of an orb leaving the arena and was never
   visible in any captured tick.

## Presentation

`PlaceholderEnemyVisual` draws the spitter as a **green disc with a darker core and a snout
pointing at the player**, distinct from the red husk, orange spiked runner and purple horned
brute (colour, silhouette and, by one pixel, size). While it winds up a shot it shows a
**telegraph read off the simulation's charge** (`EnemyState.telegraph()`, 0..1): a glow at
the muzzle that swells and brightens, a ring tightening on the body and a dashed aim line
growing toward the player; the visual is only told the fraction (a new `telegraph` argument
of `EnemyVisual.apply_pose`) and owns none of the timing. Orbs are drawn by the effects layer
as a green glow, body and bright core with a short streak behind. Feedback is deliberately
different for each outcome:

| Outcome | Feedback |
|---|---|
| orb fired | small green ring at the muzzle, "shot" sound |
| orb hits the player | red ring, red `-8`, "hurt" sound (the existing player-hurt feedback) |
| orb parried | bright green ring and white flash, ten green sparks thrown back along its flight, a `PARRY` tag, "parry" sound; no number |
| sword hits an enemy | white ring and damage number (unchanged) |

The two new sounds are baked WAVs generated by `tools/godot/gen_audio.py` (`sfx_shot`,
`sfx_parry`; the existing WAVs regenerate byte-identically). Sizes of every drawing belong to
the visual; the collision radii come only from `EnemyDefs` and `ProjectileState`.
`godot/tests/alt_enemy.tscn` (the 5× stretched, rotated visual, which now also receives the
telegraph) leaves the spitter fight unchanged, as asserted by `spitters: swapping enemy
visuals leaves the spitter fight unchanged`.

## Validation

Run on build `20261114-163133-a4a77eae7` (source commit a4a77ea, clean tree; the commits after
the behaviour/tests only add documentation), Linux, Godot 4.7.2-stable.

| What | Result |
|---|---|
| `./build-godot.sh --checks-only` / full `./build-godot.sh` | `CHECKS PASSED: 683` (519 before this slice plus 164 new); full build OK, Windows ZIP and Web bundle produced |
| `tools/godot/mutation-check.sh` | 197 of 197 deliberate bugs caught, 0 inconclusive (baseline 683 checks pass; 114 from the earlier slices plus 83 for this one: spitter stats, bands, charge and cooldown, projectile flight, expiry and hits, invulnerability, parry geometry and pads, hit-versus-parry, exactly-once, paused/dead, the dev cycle and button, launch option, frame-rate dependence) |
| Reference regeneration | `capture_spitters_and_parries.py`, `capture_crowd_and_walls.py` and `capture_fang_survival_loop.py` each run twice give byte-identical output equal to the committed JSON; `crowd_and_walls.json`, `fang_survival_loop.json` and `game/` are unchanged against the base commit 7bb0740 |
| Low/high render rates | The scripted orb fight (35 orbs fired, 10 parried, 7 hurt the player, player alive) played in the real Main scene under the engine's fixed-step loop at 5, 20, 60 and 240 fps ends with a digest identical to a bare `GameRun.step()` loop every time; every hurt cue cost exactly 8 health |
| **Web export, headless Chromium (software WebGL 2 via SwiftShader, 1280x720)** | Served the built bundle over HTTP with `?encounter=spitters`; browser key events (WASD, Space) walked and dashed through five spitters and three husks. Orbs flew, the HUD counted `orbs fired 23, parried 5` by the end of the wave (`WAVE SURVIVED`), a charging spitter showed its glow, ring and dashed aim line, and `C` went to the normal run. No console errors. `tools/godot/web-encounter-capture.mjs` (`SCENARIO=spitters`, `CAST=1` for a screencast of every frame) reproduces it. |
| **Windows export, under Wine 11 on Linux (not a Windows machine)** | The full build's `Swordster.exe`, extracted from the ZIP, run as `Swordster.exe -- --encounter=spitters` with Godot's Movie Maker (`--write-movie`, 30 fps frames of the game's own viewport, 20 s), shows the spitters shooting, the Fang swords parrying (`orbs fired 9, parried 4` at 10 s) and a hit on the player (`-8`). No input was sent, so the player stood still: the dash and the dev button were **not** exercised in the Windows export. |

Screenshots (in `docs/reference/spitters-projectiles-parries/`):
[`web-spitter-fight.png`](spitters-projectiles-parries/web-spitter-fight.png),
[`web-spitter-telegraph.png`](spitters-projectiles-parries/web-spitter-telegraph.png),
[`web-wave-survived.png`](spitters-projectiles-parries/web-wave-survived.png),
[`wine-spitter-fight.png`](spitters-projectiles-parries/wine-spitter-fight.png).

The first mutation run for this slice found two survivors (a director-spawned spitter with no
first cooldown; a second sweep over an already-parried orb in the same tick) and one mutant
that crashed a check instead of failing it (a lost `spitters` launch option). Each now has a
check that fails on it.

## What was not verified

- **No real Windows machine** and no real Android device: deferred to #6 and #22. The Wine run
  proves the export launches and fights, not that it behaves on Windows.
- Web was run in headless Chromium with a software renderer and synthetic browser input, not
  Firefox, a real GPU or a phone. Frame pacing, audio and touch were not measured. The `Dev:`
  button was exercised by the headless checks (`button_down`), not by touch.
- Parry feedback was confirmed in the exports only through the HUD's parried counter; the
  `PARRY` tag, sparks and sound were not inspected in a captured frame, and the audio was muted.
- Spitters were not tuned for fun or difficulty; the three-Fang fixture against five spitters
  is a behaviour demonstration. The prototype's spitters arrive from wave 3, which is #18.
- Out of scope and untouched: conditions (#11), Viper Flurry (#12), Warden/Pike/Colossus (#13-#15),
  Converge (#16), drops (#17), later waves (#18).
