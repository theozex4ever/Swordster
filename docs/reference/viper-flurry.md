# Reference: Viper Flurry and the sword-slot ultimates

Slice #12 of the Godot port ([spec #4](https://github.com/theozex4ever/Swordster/issues/4)),
following [the Fang survival loop](fang-survival-loop.md),
[runners, brutes and crowds](runners-brutes-crowd.md) and
[spitters, projectiles and parries](spitters-projectiles-parries.md). The Python prototype
`game/main.py` is the behavioural oracle. This file records what was captured from it, the
tolerances, the checks that assert each value, and every deliberate exception. Vocabulary
follows `GLOSSARY.md`: an **ultimate** belongs to a sword type and is triggered through its
equipped **sword slot**; **Converge** is a different command (issue #16) and is not an ultimate.

## How the reference was captured

`tools/reference/capture_viper_flurry.py` reuses the loader and helpers of
`capture_fang_survival_loop.py`, drives the prototype's real classes (`Game`, `Sword`,
`Enemy`, `Projectile`) with fixed 1/60 s steps under SDL's dummy drivers, and writes
`godot/tests/reference/viper_flurry.json`. Regenerate with:

```sh
python3 -I tools/reference/capture_viper_flurry.py godot/tests/reference/viper_flurry.json
```

Nothing is re-implemented: the blink, cadence, damage and recharge come from the
prototype's own `Sword.ultimate`, `Sword.update_ult`, `Game.ultimate` and `Game.hit_enemy`,
and the keys through the real `Game.handle` with synthetic `KEYDOWN` events and a patched
mouse position (the world point is `screen + cam - (W/2, H/2)`, as `Game.mouse_world`
computes it). Every case writes its fixture (`setup`) into the JSON and the Godot checks
build their scenarios from it.

Controls applied for repeatability (asserted by the capture, recorded as `fixture_scope`;
the Godot checks reject a reference that does not say so):

- `afflict` (elemental conditions) is a no-op: conditions are issue #11.
- Every enemy is an unarmed husk (`armed is None`): arming and drops are issue #17.
- Only Fang swords are equipped and Converge is never commanded (issue #16).
- The wave machine is off (issue #18) and every sword's automatic-attack cooldown is parked
  at 99 s, so only the ultimate fights (a case that wants the other swords to fight says so).
- Enemies stand still (speed 0) unless a case says otherwise; crits are forced off, or on
  for the crit case, by pinning `random.random`.
- What the prototype draws at random cannot be matched across random streams: the dart's
  victim among several, the wander point in an empty area and the recovery nudge. Cases are
  built so the choice is forced (exactly one eligible enemy) or record a **property** of the
  choice (alternation, bounds, cadence ticks) instead of a value.

## Tolerances

Chosen before accepting any difference; the same as the earlier slices.

| Quantity | Tolerance | Why |
|---|---|---|
| Position | ±0.05 px | Same algorithm at the prototype's 60 FPS step; float noise only. |
| Enemy velocity | ±0.05 px/s (sword velocity ±0.5) | Same. |
| Timers, cooldowns, shake, stun, flash | ±0.002 | Same. |
| Event ticks (dart, transition, restart) | ±1 fixed tick | The two frame loops can order a same-frame event one tick apart. |
| Damage, kills, counts | exact | Integers. |

In practice every compared tick and value matched exactly.

## Reference values and the checks asserting them

Line numbers refer to `game/main.py` at this repository's base commit.

### The ultimate (`SWORD_TYPES` 79–86; `Sword.ultimate` 819–856; `Sword.update_ult` 858–892)

| Quantity | Value |
|---|---|
| Name | Viper Flurry (not a skill shot) |
| Range / area radius | 420 px / 150 px |
| Recharge | 9.0 s × the rarity's cooldown factor: 9.00 / 7.83 / 6.66 s (Common / Rare / Mythic) |
| Flurry length / cadence | 1.25 s (75 fixed ticks) / one dart per 0.08 s (every 5 ticks) |
| Dart damage | sword damage × 1.2, rounded half-even, ×2 on a crit (12 %): 8 / 11 / 15 (Common / Rare / Mythic), 17 on a Common crit |
| Dart knockback / stun | 120 × the enemy's knock factor (×1.3 on a crit); stun 0.08 + force / 1500 |
| Dart feedback | flash 0.2 (a normal hit 0.11); **no hitstop**; shake +0.05 per dart (no direction) |
| Approach | each tick the sword moves `min(1, dt × 28)` of the way to its goal |
| Goal | the victim's position pushed 20 px past its edge, away from the sword; with nothing to strike a random point 20 to 105 px (0.7 × radius) from the centre |
| End | recovery 0.3 s at 300 px/s in a random direction, then idle |

Asserted by `flurry: constants and recharge against the prototype`.

### Starting it (`Game.ultimate` 1400–1415; `Game.handle` 1537)

In the prototype's order: refused when the player is dead or the slot holds no sword; refused
when that sword is already in its ultimate (even with a zero recharge); refused while
recharging (with a floating "Viper Flurry 7s"); otherwise the aim point is the mouse in world
coordinates, **clamped to 420 px from the player** (a point at exactly 420 px is not moved)
and the sword starts: it **blinks onto the point at once**, drops its target and any attack
it was in the middle of, and the recharge starts that instant (so it counts the flurry and the
recovery). Paused play ignores the keys. A command given during hitstop starts immediately
but nothing advances until the hitstop ends.

| Case | Reference |
|---|---|
| point 100 px / 420 px / 421 px / 900 px away east | lands on it / on it / (1720, 900) / (1720, 900) |
| diagonal (500, −600) / south-west (−1000, +300) | (1568.877, 577.347) / (897.713, 1020.686) |
| the player at (800, 600), aim (1800, 1000) | (1189.96, 755.984), 420 px away |
| aim on the player | lands on the player (zero length is not clamped) |
| a second command while recharging (100 ticks in) | refused; recharge 7.333 s, pose and area unchanged |
| a second command while the flurry runs (recharge forced to 0) | refused; area and clock unchanged |
| R with only two swords | ignored |
| Q while the sword is winding up an automatic attack | the sword is in its ultimate, target cleared |
| Q, E, R | slot one, two, three only |

Asserted by `flurry: the aim point is clamped to the 420 px range`, `flurry: refusals (...)`
and `flurry: Q, E and R through the input translator, and R as restart after death`.

### The flurry (one forced victim)

A single husk 30 px from the aim point: the sword blinks to (1560, 940); on its first tick it
picks the husk and steps 46.7 % of the way to the goal (1587.978, 921.348), and so on. Darts
land on ticks **6, 11, 16, … 71** (fourteen of them, as the cadence is 0.08 s and the
step is 1/60 s), each for 8 (17 on a crit, 11 Rare, 15 Mythic), with the husk's knockback
(first dart velocity (91.863, −61.242), stun 0.143), flash 0.183 after the tick, hitstop 0 and
trauma 0.05. The flurry ends on tick 75 into recovery and the sword is idle again on tick 94;
the recharge reads 7.75 s at the end of the flurry and 7.433 s when it idles (Common).
Sampled sword positions, headings, velocities, timers and recharge at 21 ticks match for the
Common, Common-crit (up to the tick where the crit knockback carries the husk out of the
area and the wander becomes random), Rare and Mythic cases.

Asserted by `flurry: the blink, the darts, the damage and the recovery against the prototype`.

### Targets (`update_ult` 862–892)

The victim is **chosen one beat ahead and struck on the next**; an enemy inside the area is
`(e.pos − centre).length() < 150 + e.r` and alive. The next victim is a random one among the
eligible enemies **other than the one just struck**, or the same one when it is alone.

| Case | Reference |
|---|---|
| husk 165 px / 167 px from the point (150 + radius 16 = 166) | struck from tick 6 (2 darts in 89 ticks as the knockback drives it out) / never struck |
| two enemies in the area, five seeds | the darts alternate strictly, ticks 6, 11, … 71, fourteen darts |
| one enemy | struck by every dart (14) |
| the victim dies on its dart (5 hp) | one kill on tick 6, chain 1; an enemy outside the area is untouched; the flurry then wanders and idles |
| the victim is killed by something else between darts | no damage to the corpse, one kill; the next beat replaces it; the other enemy is struck one beat later |
| an empty area | a new wander goal every five ticks (ticks 1, 6, … 71), 20 to 105 px from the centre, the sword never farther than 105 px; no hit, no kill |

In the prototype "removed" is the same case as "dead": an enemy only leaves the enemy list
when it is dead. The port goes one step further for a reference kept across ticks (see
deliberate exception 10: an enemy removed from the run while still alive is dropped too).
Asserted by `flurry: who is inside the 150 px area, and an empty
area` and `flurry: dart targets are replaced, never repeated, and dead or removed ones are
skipped`, and by `flurry: deaths and rewards resolve exactly once` (three weak enemies, nine
darts, three kills and nine motes, nothing duplicated).

### Clocks, death and the other swords

| Case | Reference |
|---|---|
| the player dies in the middle of the flurry | three darts had landed (first at tick 6, 11, 16); none after; the sword is idle, its victim dropped; the recharge keeps running |
| paused for 120 ticks | the flurry, its clock and the recharge are frozen bit for bit |
| 0.2 s of hitstop at the command | first dart on tick 19 (13 ticks of hitstop, then 6) |
| slow motion ×0.25 | first dart on tick 21; timers a quarter speed |
| an orb hanging where the sword blinks | **not parried** (the prototype's flurry never parries) |
| the other two Fangs with their automatic attack ready | keep striking while one flurries |
| recharge reaches zero | tick 540 / 470 / 400 for Common / Rare / Mythic |

Asserted by `flurry: pause and death in the middle of the flurry`, `flurry: hitstop and slow
motion`, `flurry: orbs and the other swords` and `flurry: the recharge`.

### R, Q, E (`Game.handle` 1521–1540)

R while alive is the slot-three ultimate and never a restart. Dead, Q/E/R start nothing; R
restarts only when `death_t > 0.8` (116 real ticks after death with the slow motion), **even
while paused**. Asserted through the real input translator and the real Main scene
(`flurry: Q, E and R in the real Main scene (...)`).

| Case | Reference |
|---|---|
| touch aim | the nearest living enemy, or 300 px ahead of the player |

## What the port adds, and how it is shared

- **One slot command path.** `GameCommand.ultimate(slot, world_point)` (and
  `ultimate_at_nearest(slot)` for touch) reaches `GameRun.try_ultimate(slot, point)`, which
  owns the eligibility rules (paused, dead, no sword, running, recharging), the range clamp
  and the cues, and hands the sword over to `SwordState.begin_ultimate(point)`. The
  recharge (`ultimate_cooldown`, `ultimate_cooldown_left`, `ultimate_ready()`,
  `ultimate_charge()`) is per-slot sword state that ticks in every phase on gameplay time.
- **A small per-type dispatch, not a framework.** The type's name, base recharge, range and
  whether it is a skill shot are `SwordDefs.ultimate_*(type)`; the sword's start and tick are
  one `match spec.type_id` each in `SwordState` (`begin_ultimate`, `_update_ultimate`). Warden
  (#13), Pike (#14) and Colossus (#15) add a constant block and a branch each; the command,
  clamp, rejections, recharge, cues and HUD cards are already generic.
- **`hit_enemy(..., heavy)`.** A heavy blow flashes longer and causes no hitstop or hit
  shake; every other rule (crit, rounding, knockback, stun, one death) is the normal hit's.
- **Update order** (`GameRun.step()`): paused returns; the real clock, shake and kick advance;
  hitstop freezes everything else; slow motion scales `dt`; `_update_player`; each sword slot's
  `SwordState.update` in slot order (cooldowns tick first, then the phase: a running flurry
  darts here, **before** the enemies move that tick); every enemy's `update`; `_separate`;
  `_resolve_contacts`; removal of the dead; `_update_projectiles`; `_update_motes`; combo,
  banner, wave director and camera.
- **Input.** Q, E and R are `InputTranslator.ULTIMATE_KEYS` (slot = index). R sends the
  ultimate first and the delayed restart after it; the run refuses whichever does not apply, so
  a dead player's R cannot start an ultimate on the restarted run. The translator tracks the
  mouse (`pointer`, viewport coordinates) and converts it through `Main._world_at`: the
  camera's unshaken centre plus the offset from the middle of the view, as `Game.mouse_world`.
- **Cues.** `ULTIMATE_STARTED` (slot in `amount`, landing in `position`, departure in
  `origin`) and `ULTIMATE_REFUSED` (whole seconds left, only for a recharge refusal, as the
  prototype's text). Each dart is an ordinary `ENEMY_HIT`.
- **HUD.** One card per sword slot, bottom left: key badge (Q / E / R), the ultimate's name,
  `READY`, `ACTIVE` or the whole seconds left, and a bar that fills as it recharges.
- **Presentation.** The blink shows a small ring where the sword was, a ring closing on the
  area where it landed and the name over the player; while it runs the area is outlined, the
  current victim ringed and each dart leaves a streak, the blade draws afterimages and keeps
  the attack pose; a refused command prints "recharging Ns". Everything reads the sword's
  `phase` and the cues; nothing is fed back (ADR 0003). The check that swaps in a stretched,
  rotated sword visual (`alt_sword.tscn`) leaves the whole scripted fight unchanged.

## Deliberate exceptions

Each is a scope or correctness decision of slice #12, not a rebalance.

1. **R is now the slot-three ultimate while alive.** This replaces the #8 exception ("R while
   alive does nothing until the ultimates exist"); the delayed restart after death is
   unchanged and tested. The two #8 checks that asserted the old behaviour were updated.
2. **The fixture loadout is still three Fang swords.** Every slot holds Viper Flurry for now;
   the prototype's default is Fang / Warden / Colossus. Other sword types are #13–#15.
3. **Touch aiming is in the run, touch controls are not.** `GameCommand.ultimate_at_nearest`
   and `GameRun.auto_aim` (nearest living enemy, else 300 px ahead) are built and tested because
   they are trivial, but no on-screen ultimate buttons exist: those are issue #20.
4. **No conditions on dart hits.** A dart would also apply the sword's element and the frozen
   bonus; both are issue #11 (the capture disabled `afflict`).
5. **Gameplay randomness is its own stream.** The dart's victim, the wander point, the
   recovery direction and the crit roll follow the prototype's distributions, not its random
   sequence; cosmetic randomness never uses it.
6. **The refusal text is "recharging Ns".** The prototype floats the ultimate's name with the
   seconds ("Viper Flurry 7s"); the cue carries only the seconds. Cosmetic.
7. **Cosmetics are not a gate.** The prototype's lift (`z`), particles, element sparks and
   sounds beyond the blink's "dash" are not reproduced; placeholder shapes follow the logical
   pose.
8. **The flurry does not parry.** The prototype's does not either, so the shared parry rule
   (`GameRun.parry_projectiles`) is not called; a check pins that an orb in the area survives.
9. **No dedicated dev encounter.** The existing encounters (normal, crowd, spitters) already
   give targets; no new control was added.
10. **A sword drops an enemy that left the run, dead or alive (hardening).** The prototype
    (`update_ult` 869, `Sword.update` 667) asks only `not v.dead`, because an enemy only leaves
    `enemies` once dead, so a living-but-removed enemy cannot occur in play. Spec #4
    Implementation Decision 7 asks for dead *or removed* targets to be handled safely, so
    `SwordState._in_play` (alive **and** still in `run.enemies`) guards every enemy reference a
    sword keeps across ticks: the flurry's victim and the Fang's automatic-attack `target`. A
    victim no longer in play takes no damage, causes no kill, mote, cue or shake, and the flurry
    picks a fresh one on the same beat exactly as it does for a dead victim; an attack target no
    longer in play is dropped and its aim stops following it. (The strike's sweep and `acquire`
    already iterate `run.enemies`, so they cannot reach a removed enemy.) Asserted by
    `flurry: an enemy removed from the run while alive ...`; the mutations
    `flurry-strikes-the-removed`, `attack-keeps-removed-target`, `in-play-ignores-dead` and
    `in-play-ignores-removal` fail it. Identical to the prototype for every reachable state: the
    reference comparisons are unchanged.

## Validation

Review fixes (removed-while-alive hardening, HUD layout check, shipped-pack Wine frames) were run
on head `df64a92` plus documentation; the original slice figures were on `7a90f29`. Linux, Godot
4.7.2-stable.

| What | Result |
|---|---|
| `./build-godot.sh --checks-only` / full `./build-godot.sh` | `CHECKS PASSED: 839` (824 before the review fixes plus 6 for removed-while-alive and 9 for the HUD layout at eight window shapes). Full builds OK on a clean tree: `20261114-185904-adff4e9c3` (the one the Wine frames used) and the final head's build (see the PR) |
| `tools/godot/mutation-check.sh` | **259 of 259** deliberate bugs caught, 0 retried, 0 inconclusive, 0 survived (251 before the fixes plus 8: the four removed-while-alive guards `flurry-strikes-the-removed`, `attack-keeps-removed-target`, `in-play-ignores-dead`, `in-play-ignores-removal` and four HUD layout ones `hud-card-below-the-view`, `hud-cards-anchored-top`, `hud-dash-below-the-view`, `hud-stretch-not-expand`; `flurry-strikes-the-dead` was re-expressed against the new guard). Run as six parallel shards of the same list (`SHARD=i SHARDS=6`, 44 + 43 + 43 + 43 + 43 + 43); the first pass of the last shard aborted on `flurry-strikes-the-dead` not applying (its anchor text had changed), and the whole shard was rerun after fixing it. |
| Reference regeneration | `capture_viper_flurry.py`, `capture_spitters_and_parries.py`, `capture_crowd_and_walls.py` and `capture_fang_survival_loop.py` each run again on the review head give byte-identical output equal to the committed JSON (no JSON changed); `crowd_and_walls.json`, `fang_survival_loop.json`, `spitters_and_parries.json` and `game/` are unchanged against the base commit 435308d |
| Low/high render rates | The scripted flurry fight (six flurries from all three slots, four refused commands, 55 darts, seven kills, player alive) played in the real Main scene under the engine's fixed-step loop at 5, 20, 60 and 240 fps ends with a digest identical to a bare `GameRun.step()` loop every time (darts, kills, positions, phases and recharges) |
| **Web export, headless Chromium (software WebGL 2 via SwiftShader, 1280x720)** | Served build `20261114-175450-59536bf6e` (identical game code; only test files changed since) over HTTP with `?encounter=crowd` and drove it with browser mouse-move and key events (`tools/godot/web-encounter-capture.mjs`, `SCENARIO=flurry`): the cursor was moved and Q, E and R pressed; each sword blinked to the cursor, the 150 px area was outlined, darts streaked between foes with damage numbers (8, 17!), the cards read ACTIVE / READY and then counted down (`2s`, `5s`), Q while recharging printed "recharging 3s", and Q worked again after the recharge. No console errors. |
| **Windows export, under Wine 11 on Linux (not a Windows machine)** | Build `20261114-185904-adff4e9c3`, the full build's Windows ZIP extracted unmodified (`SHA256SUMS` verified; `Swordster.exe` and the shipped `Swordster.pck`), run as `wine ./Swordster.exe --resolution 1000x563 --write-movie <png> --fixed-fps 30 --quit-after 300` (and again with `-- --encounter=crowd`): engine-side frames of the game's own viewport, no desktop capture and no input injected, nothing added to the game. At 1280x720 (visible rect) the shipped pack renders the whole HUD: the three slot cards **Q / E / R "Viper Flurry" READY**, with their key badges and full tinted bars, bottom left; Dash (and Shove in the crowd encounter) bottom right; Pause, Restart and the Dev button top right; every top-left line. The run also fights (kills 3 and 7, hit numbers `14!` and `7`). **What this does not show:** Q/E/R input in a Windows build. No key or mouse event was sent to the shipped build, so that belongs to the deferred device matrix (#6/#22). The earlier **replacement-pack** run (an autoload added to a scratch `.pck` to feed Q/E/R; `wine-flurry-blink.png`, `wine-flurry-darts.png`) showed the exported *binary* running the ultimates, not the shipped pack, and is kept only as that. |
| **The 35 px "crop" in the earlier Wine frame: a capture artifact, not a HUD bug** | Reproduced with the shipped build and no special pack ([`wine-shipped-default-window-cropped.png`](viper-flurry/wine-shipped-default-window-cropped.png)): with no `--resolution`, the bottom cards and Dash button are cut and the top lines are shifted. Cause, measured with a diagnostic autoload in a scratch export (not shipped): this machine's monitor is **1080 px wide** (portrait 1080x1920), so the window requested at 1280x720 is clamped to **1084x720**. The project stretches with `canvas_items` / `expand`, so the viewport rectangle becomes **1280x850** (the HUD correctly anchors to its edges), while Godot's Movie Maker always writes a **1280x720** frame, which cuts the top and bottom of that rectangle (about 65 px each, not the 35 px first estimated by eye). With `--resolution 1000x563` (16:9, fits the monitor) the visible rect is exactly 1280x720 and the same shipped pack shows the whole HUD. So it is the narrow monitor and the movie frame, not window decorations (the decorated window was 1092x754) and not an anchor or scale-mode bug. What a real player sees in a 1084x720 window (the full 1280x850 rectangle) was not captured, since full-desktop capture was out of bounds; the new layout check asserts every HUD control lies inside the visible rect at eight window shapes including 1084x720. |

Screenshots (in `docs/reference/viper-flurry/`):
[`web-flurry-02-q-150.png`](viper-flurry/web-flurry-02-q-150.png),
[`web-flurry-03-q-refused.png`](viper-flurry/web-flurry-03-q-refused.png),
[`web-flurry-04-r-200.png`](viper-flurry/web-flurry-04-r-200.png),
[`wine-shipped-hud-ready.png`](viper-flurry/wine-shipped-hud-ready.png) and
[`wine-shipped-crowd-ready.png`](viper-flurry/wine-shipped-crowd-ready.png) (shipped pack, whole HUD),
[`wine-shipped-default-window-cropped.png`](viper-flurry/wine-shipped-default-window-cropped.png) (the clamped-window artifact),
[`wine-flurry-blink.png`](viper-flurry/wine-flurry-blink.png) and
[`wine-flurry-darts.png`](viper-flurry/wine-flurry-darts.png) (replacement pack, input-driven).

## What was not verified

- **No real Windows machine** and no real Android device (#6, #22). The Wine run proves the
  shipped export launches and renders the slot HUD, not that it behaves on Windows. No touch ultimate
  controls exist yet (#20), so Android has nothing to test.
- Web was run in headless Chromium with a software renderer and synthetic browser input, not
  Firefox, a real GPU or a phone. Frame pacing and audio were not measured (audio was muted;
  the blink sound is asserted by a check only).
- Windows evidence is engine-side frames of the shipped pack under Wine: **no Q/E/R key or mouse input was exercised in any Windows build** (deferred to #6/#22), and a real player's view of a window narrower than 1280 px was not captured (only asserted by the layout check).
- Viper Flurry was not tuned for fun or difficulty; the numbers are the prototype's.
- Out of scope and untouched: conditions (#11), Warden/Pike/Colossus (#13-#15), Converge (#16),
  drops and swaps (#17), later waves (#18), touch controls (#20).
