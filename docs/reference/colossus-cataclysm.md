# Reference: Colossus, Cataclysm and elemental fields

Slice #15 of the Godot port ([spec #4](https://github.com/theozex4ever/Swordster/issues/4)),
following [the Fang survival loop](fang-survival-loop.md),
[runners, brutes and crowds](runners-brutes-crowd.md),
[spitters, projectiles and parries](spitters-projectiles-parries.md), [Viper Flurry](viper-flurry.md),
[elemental conditions](elemental-conditions.md), [Warden and Maelstrom](warden-maelstrom.md) and
[Pike and Skewer](pike-skewer.md). The Python prototype `game/main.py` is the behavioural oracle. This file
records what was captured from it, the tolerances, the checks that assert each value, and every deliberate
exception. Vocabulary follows `GLOSSARY.md`: **Colossus** is a sword type, **Cataclysm** its ultimate,
triggered through its equipped **sword slot**; **Converge** is a different command (issue #16) and is not an
ultimate. A **field** is the elemental ground Cataclysm leaves.

The sword type keeps the prototype's internal identity: Colossus is `SWORD_TYPES["colossus"]`, so the Godot
type id is `colossus` (`SwordDefs.COLOSSUS`); the displayed names (Colossus, Cataclysm) come from
`SwordDefs.display_name` / `ultimate_name`.

## How the reference was captured

`tools/reference/capture_colossus_cataclysm.py` reuses the loader and helpers of
`capture_fang_survival_loop.py` and `capture_viper_flurry.py`, drives the prototype's real classes (`Game`,
`Sword`, `Enemy`, `Projectile`, `Field`) with fixed 1/60 s steps under SDL's dummy drivers, and writes
`godot/tests/reference/colossus_cataclysm.json`. Regenerate with:

```sh
python3 -I tools/reference/capture_colossus_cataclysm.py godot/tests/reference/colossus_cataclysm.json
```

Nothing is re-implemented: the cluster targeting, the windup, the fall and the stuck pause come from
`Sword.acquire`, `Sword.begin`, `Sword.update` and `Sword.strike`; the rise and fall of the ultimate from
`Sword.ultimate` and `Sword.update_ult`; the area damage, falloff, knockback, hitstop, shake and projectile
clearing from `Game.slam`; the heavy blow's rounding, crits and doses from `Game.hit_enemy` and `Game.afflict`; the
field's life and cadence from `Game.update_fields`; the Q/E/R keys through the real `Game.handle` with synthetic
`KEYDOWN` events and a patched mouse position. Every case writes its fixture (`setup`) into the JSON (swords,
enemies, orbs, the player, whether conditions are on, and a short `script` of timed commands: start an attack
with `Sword.begin`, press a key at a world point, kill an enemy, hurt the player) and the Godot checks build
their scenarios from it. The capture wraps `Game.slam`, `Game.afflict` and `Game.update_fields` to log every
slam (its point, radius, and the enemies in reach with their distances, corpses included) and every dose (who,
which element, from a blow or from a field). The JSON holds 7,150 traced ticks, 56 + 12 + 12 probe points, 54
orb probes and 15 targeting layouts.

**Conditions per case.** As in the earlier slices, `setup.conditions` says which the prototype ran with
(`fixture_scope.afflict_enabled_cases`):

- **Off** for every physical case: targeting, the timing of the fall, the area and its falloff, knockback,
  hitstop and shake, orbs, deaths, recharge and refusals.
- **On** for the cases whose subject is conditions: the slam's doses and the field's cadence per element
  (`conditions.{poison,ice,fire}`), overlapping fields, deaths by burn and poison inside a field, a corpse on a
  pulse tick, a field that outlives the player, a pause over a field, and a composite fight of three Colossi
  against nine walking enemies.

Other controls (asserted by the capture, recorded as `fixture_scope`): every enemy is an unarmed husk, runner or
brute (arming and drops are issue #17); only Colossus swords are equipped and Converge is never commanded (#16);
the wave machine is off (#18); a sword that is not meant to fight has its auto-attack cooldown parked at 99 s;
crits are forced off (or on) by pinning `random.random`.

## Tolerances

Chosen before accepting any difference; the same as the earlier slices: position ±0.05 px, velocity
±0.5 px/s, timers / stun / flash / hitstop / shake ±0.002, kick ±0.01, angles ±0.002 rad, health ±0.001,
damage / kills / counts exact. In practice every compared tick and value matched: the traces compare, **on every
tick**, each watched sword (phase including the ultimate's rise or fall, position, angle, velocity, altitude,
fall speed, clocks, recharge, cooldown, the impact point while falling), every enemy (position, health, velocity,
stun, flash, death, and all condition fields when conditions are on), the orbs, up to three fields (life and dose
clock), and the run's shared state (hitstop, shake and its kick, kills, combo, the player, the number of enemies a
slam found in reach and the radius it used, how many enemies a field dosed).

## Reference values and the checks asserting them

### The sword (`SWORD_TYPES["colossus"]` 98–103; `Sword.__init__` 568–606)

| Quantity | Value |
|---|---|
| Name / blurb | Colossus / "far / slow / crushing slam" |
| Length, width | 88 px (x1.08 / x1.18 by rarity), 15 px |
| Range | 330 px (x1.06 / x1.12) |
| Cooldown | 1 slam per 2.1 s (x0.87 / x0.74) |
| Damage | 50 (x1.3 / x1.75): 50 / 65 / 87.5 |
| Knockback / hitstop / shake | 650 x the enemy's knock factor x the falloff; 0.13 s; 0.6 |
| Windup | 0.55 s |
| Slam radius | 118 px x the rarity's size factor (118 / 127.44 / 139.24) |
| Cataclysm | recharge 14 s (x0.87 / x0.74), range 480 px, area 118 x 1.8 x size (212.4 / 229.39 / 250.63) |

Asserted by `colossus: identity, constants and rarity numbers against the prototype`.

### Targeting (`Sword.acquire` 629–636)

Of the enemies within `range + radius` of the *player*, the one with the most enemies (itself included) within
118 px of it wins; on equal counts the nearer to the player (the score is `count x 1000 - distance`; the first
of equal scores wins). The neighbour count uses the type's 118 px, **not** the rarity-scaled radius the slam
itself uses, counts enemies of any distance from the player, and, as in the prototype, counts the dead of this
tick (they are still in the run's list until the update ends). Captured: `acquire.*` (an enemy at 345 and 347
px: acquired / ignored, and one close by; twelve layouts: a cluster over a nearer lone foe, the nearest of a cluster, ties to the
first in order in either order, neighbours out of range and behind counted, 117 and 118 px edges, brutes and
runners, the plain radius a Mythic counts with): `colossus: who it targets`.

### The slam (`Sword.update` windup 726–730, strike 794–805; `Sword.strike` 853–856; `Game.slam` 1298–1339)

- **Windup** (0.55 s, 33 ticks): the sword springs (k 120, c 18) onto the aim point, which follows its target
  until the strike, climbs toward altitude 200 (rate 7) and turns upright with a small tremble.
- **The fall.** The impact point is fixed when the strike begins. Each tick the sword glides
  `min(1, dt x 30)` of the way to it while it drops: fall speed starts at 300 and grows by 9000 per second,
  and the slam lands on the **first tick the altitude reaches 0**, exactly on the point. The altitude the fall
  starts from is where the windup's climb had got to (about 197 px after 33 ticks of easing toward 200, whatever
  the idle bob it began from), so here a slam always lands 11 ticks after its strike begins: `timing.runs` (eight
  starts spread over the idle bob, per-tick traces; strikes on ticks 35, 39, 44, 48, 53, 59, 65, 70 and landings
  on 46, 50, 55, 59, 64, 70, 76, 81). The altitude carried over matters when a Cataclysm interrupts an attack
  (`start.interrupts_*`) and will matter for Converge's shorter windup (#16).
- **The slam.** Every enemy within `radius + its own radius` of the point is struck, in the run's order, **the
  dead included** (`hit_enemy` ignores them, but a corpse still counts as something struck), by a heavy blow of
  `damage x boost x power x fall`, `fall = 1 - 0.45 x clamp(distance / radius, 0, 1)`, with `knock x fall`
  and the element's doses (one for an automatic slam). Every orb whose centre is closer than `radius` to the point
  is destroyed (no padding, no sound of a parry). Hitstop and shake are the sword's own (0.13 s, 0.6) if anything
  was in reach, else 0.04 s and 0.35; the shake kicks straight down.
- **After.** The sword sticks in the floor for 0.32 s (trembling), recovers for 0.4 s (kicked up at 60 px/s) and
  is idle again; the next attack comes when the cooldown, which started at the strike, is spent.

Captured and asserted: `slam.{common,common_crit,rare,mythic}` (a walking husk and a second one: windup 1, strike
35, landing 46, recover 74, idle 99, the next windup 175 and landing 225: the first cooldown tick for tick; damage
50 at the centre down to 28 at the edge, every tick), `geometry` (56 probes: husk and brute, Common and
Mythic, 0.5 to 160 px from the impact; a husk is struck out to 133 px and not at 134 = 118 + 16, a brute to 147 and
not at 148 = 118 + 30, a Mythic's 139.24 reaches a husk at 149 and a brute at 160; the damage falls 50, 44, 39,
33, 28 and stays 28 beyond 117 px because of the clamp), `empty_slam.*`, `orbs.grid` (40 orbs around a slam,
Common and Mythic: cleared strictly inside the radius, 117 px yes and 118 no, Mythic 139 yes and 140 no).

### Cataclysm (`SWORD_TYPES["colossus"]["ult"]` 102; `Sword.ultimate` 853–855; `Sword.update_ult` 984–1008; `Game.ultimate` 1400–1415)

| Phase / quantity | Value |
|---|---|
| Key | Q / E / R by slot; a targeted ultimate: the aim point is pulled back onto 480 px from the player |
| Recharge | 14 s (x0.87 / x0.74) from the command; it runs on gameplay time, so every slam's hitstop stretches it (ready on tick 848, 739 and 630 by rarity, not 840, 731 and 622) |
| Rise | 0.75 s (the first 44 ticks show a rising sword, the 45th turns it into a fall): the sword springs onto the point (120, 18), climbs toward altitude 420 (rate 5), trembles; it does not move at the start |
| Fall | from fall speed 600 with gravity 12000, the same glide; lands on the first tick the altitude reaches 0 (tick 58 for the reference case) |
| The slam | area 212.4 px (x size), `damage x 2.2 x fall`, knockback `650 x fall`, **three** doses of the element, hitstop and shake as a slam, then an extra shake 0.4 |
| The field | created in the same tick (see below); the sword sticks for 0.6 s, then recovers |

Captured and asserted: `start.*` (seven points: inside, at and past the 480 px range, diagonal, south, on the
player, far west; the sword does not move; the recharge and the rise clock start; the command interrupts a
windup, a fall and the stuck pause), `single.*` (a ring of seven enemies: the rise, the fall, 110 at the centre
down to 63 at 202 px (60 at the edge itself) for six of them and the seventh, 252 px from the point, untouched, every tick of the
field's life), `edge.*` (twelve probes: a husk is struck out to 228 px = 212.4 + 16, a brute to 242 = 212.4 + 30),
`rules.*` (recharge to the exact tick, refusals while it rises and falls and while it recharges, the other
Colossi keep slamming), `keys.*`, `orbs.cataclysm_grid` (a wider area: 212 yes, 212.5 no; Mythic 250 yes, 251 no).

### Elemental fields (`Field` 402–413; `Game.update_fields` 1243–1256; creation 1003)

A field is `Field(point, area x 1.1, the sword's element, the sword's damage, 5.0 s)`. Its dose clock starts at
zero. **It is created during the sword's update and ticked in the very same update** (the fields tick right after
the conditions): its life and clock lose `dt`, the clock is spent, so every enemy whose centre is within `radius
+ its radius` of the point and that is not dead takes **one dose** (`afflict(enemy, element, power)`) in the run's
order, the clock is set to 0.5 s and the field is removed after the loop once its life is 0 or less. So:

- The impact tick is a pulse tick (the field's first dose): poison enemies in reach go 3 -> **4** stacks the same
  tick, an ice Cataclysm freezes everything it struck (three doses + the field's = four) on the impact tick (a
  brute for 0.96 s, a husk for 1.6 s), fire stays at burn 3.0 s.
- The next pulse is **31 ticks** of gameplay time later (0.5 s of `dt` is not quite used up by 30 steps in double
  precision, as in the prototype) plus any ticks frozen by hitstop: pulses on ticks 58, 97, 128, 159, ... in the
  reference case (the slam's own hitstop of 8 ticks makes the first gap 39). Poison reaches its cap of six on the
  third pulse.
- The field lives 308 ticks (300 of gameplay time + 8 frozen by the slam's hitstop), then goes. A paused run or a
  run in hitstop does not age it (nothing in `update` runs), the player's death does not end it, a restart removes
  it.
- A dead enemy is skipped; so is an enemy that dies on the very tick the field pulses (a second Colossus slam
  killing it earlier in the tick): `field_deaths.corpse_on_a_pulse_tick`.
- Fields of several swords each have their own life and clock, and an enemy standing in two is dosed by both, in
  the order the fields were made: `overlap.*`.

Captured and asserted: `conditions.{poison,ice,fire}` (three enemies in the field for 380 ticks, every condition
field every tick), `field_reach` (twelve probes: a husk dosed out to 249.5 px = 233.64 + 16 and not at 249.75, a
brute to 263.5 and not at 263.75), `overlap.{same_tick,twenty_ticks_apart,three_elements}`, `field_deaths.*`
(enemies burned and poisoned down inside a field, a burning death igniting its neighbours, a corpse on a pulse
tick, the player's death), `pause_and_hitstop.pause_over_a_field`.

### Order inside one tick

The prototype's update (`Game.update` 1549–1587) is: the player, each sword in slot order (a slam or a Cataclysm
lands inside its sword's update), the enemies, crowd separation, the conditions, **the fields**, contacts, the removal of
the dead, projectiles. `GameRun.step()` has the same order; `_update_fields` is called straight after
`_update_conditions`. Asserted by the per-tick traces and by mutations `fields-tick-before-the-conditions` and
`fields-never-tick`.

### Enemies that die or leave the run (spec decision 7)

The prototype iterates **every** enemy of the update in its sword loops, corpses included, and removes the dead only
at the end of the update; only `hit_enemy` returns early for them and the field's loop skips them explicitly. The
port mirrors each loop and the captured cases catch a divergence:

- `empty_slam.two_slams_corpse`: two Colossi land on one tick; the first kills two enemies standing where the second's
  area is; the second still counts them as struck (the sword's hitstop and shake, shake 0.6 + 0.6 caps at 1.0),
  while with the dead outside its area (`two_slams_corpse_far`) it is an empty slam (shake 0.6 + 0.35 = 0.95).
- `deaths.corpse_cluster_is_targeted`: a Colossus that looks for a target on the very tick another one's slam killed
  a cluster finds the corpses still in the run's list, counts them as neighbours and winds up on them instead of the
  living foe.
- `deaths.target_killed_in_the_windup`: the target killed from outside during the windup is dropped, the sword still
  lands on the point it was going to.
- `deaths.player_dies_in_the_fall`: the sword goes idle where it is, no slam happens, its altitude sinks at 120 px/s.
- `field_deaths.corpse_on_a_pulse_tick`: described above.

An enemy that leaves the run **alive** (not reachable in the prototype) is dropped by the port's `_in_play` guard as
the target of a windup; a field simply no longer finds it in the run. Asserted by `colossus: enemies that leave the run,
restart and the player's death are handled safely`.

## What the port adds, and how it is shared

- **Simulation** (`godot/scripts/sim/`): `sword_state.gd` dispatches the Colossus's targeting (`acquire` ->
  `_acquire_cluster`), windup (`_update_slam_windup`), fall (`_update_slam_fall`), stuck pause (`_update_stuck`) and
  Cataclysm (`begin_ultimate`, `_update_cataclysm`); `sword_defs.gd` holds the numbers; `field_state.gd` is the
  field; `game_run.gd` has `slam` (the prototype's `Game.slam`), `add_field` and `_update_fields`. The slam clears orbs
  through the shared `clear_projectiles_in_circle` built in issue #10 and applies doses through the shared
  `afflict`. A fall is a closed-form step per fixed tick, so nothing tunnels at any render rate (the render-rate probe
  plays a Colossus and Cataclysm fight at 5, 20, 60 and 240 fps with identical outcomes). Runs own their fields:
  they are cleared on restart, frozen by pause and hitstop.
- **Altitude is gameplay state, drawn by the visual.** The prototype keeps a height `z` and a fall speed `vz` for every
  sword, and for Colossus alone they decide when the slam lands. They are `SwordState.altitude` and `fall_speed`
  (gameplay state, mirrored per tick, ADR 0003: the damage timing belongs to the simulation), and the visual reads
  the altitude through a new read-only `SwordVisual.apply_altitude` call: it draws the blade as high as that, scales
  its shadow, and can ignore it (a replacement visual changes nothing: `colossus: swapping the sword visual leaves
  the fight unchanged`). No visual or animation callback drives the fall.
- **Cues**: `COLOSSUS_SLAM` (impact, radius, how many in reach, the element, `critical` = a Cataclysm), `FIELD_CREATED`
  and `FIELD_PULSED` (how many it dosed). The slam is heard (the existing hit sound) even when it struck nothing.
- **Encounter** (`RunScenario.colossus_encounter()`): a cluster of seven husks 280 to 440 px east of the player and a wave of
  sixteen (husks, runners, two brutes and two spitters whose orbs the slams clear) against three Colossi, poison / ice / fire.
  Reachable with the dev button / `C` (the cycle is now normal, crowd, spitters, conditions, warden, pike, colossus,
  normal), `--encounter=colossus` and `?encounter=colossus`. The normal run is unchanged: three Fang swords (the final
  default is #16).
- **Presentation** (replaceable, ADR 0003; it only reads `SwordState`, `FieldState` and cues): a Colossus is a huge slab
  of a blade that hangs point-down above a shadow that shrinks as it climbs; the windup and the fall draw the ring the
  slam will crush (it follows the target, then stays on the point); a Cataclysm's rise draws its wider ring; a landing
  throws two rings, sparks and (for a Cataclysm) its name; a field is a flattened ellipse of its element with a pulsing
  rim that fades over its last third and sheds the element's particles; a field's creation and each pulse that dosed
  someone ring; the HUD cards read "Cataclysm" and "Colossus sword"; the encounter legend counts slams and fields.

## Deliberate exceptions

Each is a scope or correctness decision of slice #15, not a rebalance.

1. **The colossus encounter is the only way to field Colossus; the normal run is unchanged.** The earlier slices' cycle checks
   were extended by one step; nothing else about them changed.
2. **Gameplay randomness is its own stream** (crit rolls, the random heading for a zero-length vector), as before. Two
   consequences are visible in the captures: an enemy that stands **exactly** on a slam's impact point is struck in a random
   direction by the prototype (`norm` of a zero vector); the capture lists them (`random_heading`) and the checks compare
   nothing but health, stun and death for them from that tick on. And healing motes fly off in random directions, so when
   they reach the player differs: the per-tick comparisons do not include the mote count, and the player's health is
   compared with a margin of one mote's healing (0.5) per mote that could have been collected.
3. **After the player's death enemies wander by Python's object `id()`** (`want = polar(t x 0.3 + id(self) % 7, ...)`), which no
   port can reproduce: the death cases use pinned enemies (speed 0).
4. **A destroyed orb cannot also hit the player** (shared with issue #10, exception 1). The prototype's projectile loop moves
   and tests every orb without looking at `pr.dead`, so an orb a slam destroyed this tick is still moved and, overlapping the
   player, still hurts. The capture builds it (`orbs.destroyed_orb_still_hurts_in_the_prototype`: the player invulnerable until
   the very tick of the slam; the prototype ends on 92 health), the port ends on 100 with no hurt cue
   (`DELIBERATE EXCEPTION` check).
5. **Cosmetics are not a gate**: the prototype's floor cracks (decals), smoke and debris particles, trails, sword-lift
   jitter and its "boom" and "heave" sounds are not reproduced (the slam uses the hit sound, the start the dash sound).
6. **Only the encounter dev loadout fields Colossus.** The prototype's default loadout is Fang / Warden / Colossus
   (poison / ice / fire); restoring it is issue #16. Converge's fast windup (`begin(fast=True)`, boost 1.5) is also #16 and
   the port's `begin` already takes the boost (asserted at 1.5 against the slam's formula).
7. **No touch ultimate buttons.** Touch aiming (`auto_aim`) works for a Colossus (the nearest enemy, or 300 px ahead) but the
   on-screen buttons are issue #20.
8. **Float32 versus float64.** The port's `Vector2` is single precision, the prototype's double. Reach probes use
   binary-exact coordinates (integers and halves), so a probe is never rounded onto a radius; the 133 / 134 px husk and
   147 / 148 px brute edges of a Common slam, the 212 / 212.5 px edge of a Cataclysm and the 249.5 / 249.75 px edge of a field
   are all exact in both.

## Validation

Linux, Godot 4.7.2-stable. Built stacked on `feat/14-pike-skewer` (started from `e6f35c1`, merged its later commits) and,
once #14 and the fast mutation runner (#35) had reached `main`, merged `origin/main` `50c9814`; branch `feat/15-colossus-cataclysm`.

| What | Result |
|---|---|
| `./build-godot.sh --checks-only` / full `./build-godot.sh` | `CHECKS PASSED: 1503` (166 of them are `colossus_cataclysm_checks.gd`'s; the earlier slices' dev-encounter cycle checks were extended by one step). Full build OK on a clean tree: `20261115-101330-5fd36ea7d` (its `SHA256SUMS` verifies; the Web and Wine evidence below is from it), and again after merging `origin/main` on head `6c82759`: `20261115-161001-6c82759f2`. The commits between the two changed tests, tooling and docs only (no file under `godot/scripts` differs). |
| `tools/godot/mutation-check.sh` | **790 of 790** deliberate bugs caught, 0 inconclusive, 0 survived, 0 not applied: one complete pass in the runner's fast mode (focused, then quick, then full; `SHARDS=6`, 132 / 132 / 132 / 131 / 131 / 132) on head `e94352b` (the head with `origin/main` merged; its game code is the same as the evidence build's), run once the fast modes of #35 were on `main`. 195 of the 790 are new: constants, targeting, altitude and fall, the slam, Cataclysm, the field, orbs, the encounter and its wiring, effects (the strokes are counted by the call that draws them) and visuals. Five earlier mutations were repaired because the new `_update_fields` call and the dev cycle's new last step changed the text they patch (`conditions-tick-after-contacts`, `conditions-render-rate-dependent` and the three `*-encounter-not-in-cycle`). Before #35 had landed, the classic runner (one complete, non-fail-fast run per mutation) was used for an earlier complete pass on `33dcc11` (the same game code): 789 caught and 1 inconclusive, `placement-health-dropped`, an earlier slice's mutation that made the new Colossus checks index an enemy that had died (a crash after the failure instead of a verdict). The checks were fixed to keep their enemy references (tests only), and that mutation plus the whole Colossus section and the five repaired ones (201) were re-run classic on `882214e`: 201 of 201 caught. In that classic pass the runner's fixed 120 s per-run timeout was raised to 300 s in a scratch copy (nothing else changed, nothing committed) because other agents' passes loaded the shared machine and made correct runs exit 124. Mutations deliberately left out as equivalent: landing "exactly on the point" (the glide has already closed to under 0.05 px), a field reaching an enemy exactly on its edge (no fixture can sit there; a direct check covers the strict `<`), and the `<=` of the slam's landing test (only differs at exactly zero). |
| Reference regeneration | All eight captures (`capture_colossus_cataclysm.py` and the seven earlier ones) rerun on the merged head give output byte-identical (`cmp`) to the committed JSON; the seven earlier JSON files are unchanged by this PR. |
| Low/high render rates | The scripted fight (a Mythic poison, a Rare ice and a Common fire Colossus crushing standing packs, four Cataclysms, two refused presses, orbs cleared) played in the real Main scene under the engine's fixed-step loop at 5, 20, 60 and 240 fps ends with a digest identical to a bare `GameRun.step()` loop every time. |
| Per-tick comparison with the prototype | Sword pose, phases, altitude, fall speed, clocks, recharge; every enemy's position, health, velocity, stun, flash, death and every condition field; the orbs; up to three fields' life and clock; hitstop, shake, kick, kills, combo; the slam found in reach and the doses a field gave: on every tick of every captured trace (7,150 ticks), apart from what exception 2 excludes, plus 56 + 12 reach probes, 12 field probes, 54 orb probes and 12 targeting layouts. |
| **Web export, headless Chromium (software WebGL 2 via SwiftShader, 1280x720)** | Build `20261115-101330-5fd36ea7d`, served over HTTP with `?encounter=colossus` and driven with browser mouse-move and key events (`tools/godot/web-encounter-capture.mjs`, `SCENARIO=colossus`): **Q** with the cursor over the cluster (poison), then **E** west (ice) and **R** north (fire) in quick succession; the page is paused with **P** for the screenshots, because the software-rendered page takes seconds per screenshot while the game runs on. The shots show the three Cataclysms rising, the rings they will crush, the landing, then **three live fields at once** (green east, blue west, orange north: card status 11s / 12s / 12s, legend "fields 3 (live 3)"), frozen foes inside the ice field, and **Q** pressed while recharging refused ("recharging 9s"). Console: the three Godot start-up lines, no errors. The press-to-landing timing in the screenshots is the browser\'s, not the simulation\'s. |
| **Windows export, under Wine 11 on Linux (not a Windows machine)** | The same build: the full build\'s ZIP extracted unmodified, its own `SHA256SUMS` verified (all five files OK), the shipped `Swordster.exe` and `Swordster.pck` run as `wine ./Swordster.exe --resolution 1000x563 --write-movie <frames> --fixed-fps 30 --quit-after 600 -- --encounter=colossus` (a scratch Wine prefix): engine-side frames of the game\'s own viewport (no desktop capture, no input, nothing added to the game). The frames show the colossus encounter\'s HUD (three **Cataclysm READY** cards with POISON / ICE / FIRE, "Colossus sword"), the three Colossi winding up over the cluster with the ring they will crush, the landings with their damage numbers and kills. **What this does not show:** a Cataclysm or a field in the Windows build. No key or mouse event was sent to the shipped build (no autopilot exists in the game), so Q/E/R input in a Windows build belongs to the deferred device matrix (#6/#22); the Cataclysms and their three fields are shown in the Web build. |

Screenshots (in `docs/reference/colossus-cataclysm/`):
[`web-cataclysm-three-rising.png`](colossus-cataclysm/web-cataclysm-three-rising.png) (three Cataclysms in the air, ice and fire "ACTIVE", the poison field already down),
[`web-cataclysm-three-fields.png`](colossus-cataclysm/web-cataclysm-three-fields.png) (poison, ice and fire fields standing together),
[`web-cataclysm-q-refused.png`](colossus-cataclysm/web-cataclysm-q-refused.png) (Q refused while recharging),
[`wine-shipped-colossus-windup-ring.png`](colossus-cataclysm/wine-shipped-colossus-windup-ring.png),
[`wine-shipped-colossus-slam-ring.png`](colossus-cataclysm/wine-shipped-colossus-slam-ring.png) and
[`wine-shipped-colossus-slam.png`](colossus-cataclysm/wine-shipped-colossus-slam.png) (shipped pack, no input).

## What was not verified

- **No real Windows machine** and no real Android device (#6, #22). The Wine run proves the shipped export launches and
  renders the Colossus fight and HUD, not that it behaves on Windows. No touch ultimate controls exist yet (#20).
- Web was run in headless Chromium with a software renderer and synthetic browser input, not Firefox, a real GPU or a
  phone. Frame pacing and audio were not measured (audio was muted).
- Windows evidence is engine-side frames of the shipped pack under Wine with no input: no Q/E/R event was sent to it, so
  a Cataclysm and its fields in the Windows build belong to the deferred device matrix.
- Converge's interaction with a slam (the fast windup, boost 1.5) is not captured: only the damage boost's formula is
  asserted (issue #16).
