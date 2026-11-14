# Reference: elemental conditions (fire, poison, ice)

Slice #11 of the Godot port ([spec #4](https://github.com/theozex4ever/Swordster/issues/4)),
following [the Fang survival loop](fang-survival-loop.md),
[runners, brutes and crowds](runners-brutes-crowd.md),
[spitters, projectiles and parries](spitters-projectiles-parries.md) and
[Viper Flurry](viper-flurry.md). The Python prototype `game/main.py` is the behavioural oracle.
This file records what was captured from it, the tolerances, the checks that assert each value,
and every deliberate exception. Vocabulary follows `GLOSSARY.md`: an **element** (fire, ice or
poison) belongs to a **spirit sword** independent of its **sword type** and **rarity**; a
**condition** is what that element's blows leave on an enemy (burning, poisoned, chilled,
frozen). Elemental *fields* are the Colossus's Cataclysm (issue #15) and are not in this slice;
they will call the same `GameRun.afflict`.

## How the reference was captured

`tools/reference/capture_elemental_conditions.py` reuses the loader and helpers of
`capture_fang_survival_loop.py` and `capture_viper_flurry.py`, drives the prototype's real
classes (`Game`, `Sword`, `Enemy`, `Player`) with fixed 1/60 s steps under SDL's dummy drivers,
and writes `godot/tests/reference/elemental_conditions.json`. Regenerate with:

```sh
python3 -I tools/reference/capture_elemental_conditions.py godot/tests/reference/elemental_conditions.json
```

**Unlike the earlier captures it leaves the prototype's `Game.afflict` ON** (they replaced it by
a no-op; their files are byte-identical to before). Nothing is re-implemented: burning, poison,
chilling, freezing, the damage-over-time cadence, the frozen bonus, the contact immunity and the
fire spread are read off the prototype's own `afflict`, `update_conditions`, `hit_enemy`, `kill`
and `Enemy.update`. The output is deterministic (two runs compare equal byte for byte).

Every case is a **spec** that the Godot checks replay on the real `GameRun`: the swords equipped
(rarity, element), the enemies standing in the arena (kind, position, health, speed scale,
starting velocity, stun, clock, frozen seconds, spitter cooldown) and a list of **events** that
happen just before a given tick: a sword's blow on an enemy through the prototype's own
`hit_enemy` (damage, critical or not, heavy or not), a bare `afflict` (what an elemental field's
tick will do), or a Viper Flurry command through the real key handler. The trace records, after
every tick in `watch`, every enemy's health, `dead`, each condition's timer, stack count and dps,
the damage-over-time accumulator and its timer, position, velocity, stun and clock, and the run's
player health, kills, flying projectiles, hitstop and the three sword states. The Godot side
compares the same trace field by field; **no starting number is copied into the checks**.

Controls applied for repeatability (asserted by the capture and recorded as `fixture_scope`; the
Godot checks reject a reference that does not say so):

- Conditions ON; every enemy is unarmed (`armed is None`: arming and drops are issue #17).
- Only Fang swords; Converge is never commanded (issue #16); no Warden, Pike or Colossus (#13-#15).
- The wave machine is off (issue #18) and every sword's automatic attack is parked at 99 s,
  except in the `sword_hits` cases, where one sword's own attack is the thing under test.
- Enemies stand still (speed 0) unless a case is about movement. Crits are forced off, or on for
  the one blow that asks. Direct blows are `heavy` (no hitstop) with zero knockback, so time and
  positions stay comparable and the cases measure conditions, not knockback.
- What the prototype draws at random cannot be matched across random streams: where a healing
  mote scatters (so motes are not compared; kills and cue counts pin the reward), the dart's victim
  among several (flurry cases have one eligible enemy), and cosmetic particles.

## Tolerances

Chosen before accepting any difference; the same as the earlier slices.

| Quantity | Tolerance | Why |
|---|---|---|
| Position | ±0.05 px | Same algorithm at the prototype's 60 FPS step; float noise only. |
| Enemy velocity | ±0.05 px/s | Same. |
| Timers, accumulators, dps, stun, clock | ±0.001 | The reference rounds to four decimals. |
| Health | ±0.001 | Integers in practice. |
| Stacks, kills, dead, projectile counts | exact | Integers and flags. |
| Event ticks (first blow, thaw, freeze, spitter's first orb) | ±1 fixed tick | The two frame loops can order a same-frame event one tick apart. |

In practice every watched tick matched exactly (the ±1 allowance is only used where a check
measures a tick distance from observed data).

## Reference values and the checks asserting them

Line numbers refer to `game/main.py` at this repository's base commit.

### Constants and formulas (`ELEMENTS` 109-116; `Game.afflict` 1160-1184; `update_conditions` 1203-1240; `kill` 1275-1286)

| Quantity | Value |
|---|---|
| Burn / poison / chill / freeze time | 3.0 s / 4.5 s / 2.5 s / 1.6 s (a brute's freeze: × 0.6 = 0.96 s) |
| Poison cap / ice stacks to freeze | 6 stacks / 4 stacks |
| Chill slow / frozen bonus / freeze velocity kept | movement × 0.5 / damage × 1.3 / velocity × 0.2 |
| Burn dps of one dose | `(1.5 + power × 0.2) × stacks`; `power` is the source sword's base damage (type damage × rarity): 2.9 / 3.32 / 3.95 dps (Common / Rare / Mythic Fang), 8.7 for three stacks of Common |
| Poison dps of one stack | `1 + power × 0.06`: 1.42 / 1.546 / 1.735 per stack; total = per stack × stacks (up to 8.52 at six Common stacks) |
| Damage over time | accumulates `dps × dt`; every 0.5 s the **whole** part lands as damage (`int()`), the fraction carries over; the accumulator is wiped on a tick with no burn and no poison |
| Fire spread on a burning death | every living enemy within `radius + radius + 70` px of the dead one: burn dps `max(its own while burning, 0.6 × the dead one's)`, burn time `max(its own, 3.0 × 0.7 = 2.1 s)` |

Asserted by `conditions: constants and formulas` (every constant, the three rarities' dps).
The Python values are written to `table` in the reference by calling the prototype's own
`afflict` on each rarity's sword.

### Applying a dose (`afflict` 1160-1184)

| Rule | Reference |
|---|---|
| Fire | burn dps is replaced when not burning, otherwise `max(old, new)` (a weaker blow never lowers it; one after expiry starts at its own dps, not the stale one); the timer renews to 3 s on every dose; stacks multiply the dps |
| Poison | stacks `min(6, stacks + doses)`; per-stack dps as fire's rule; the timer renews to 4.5 s; all stacks (and only then) reset when the timer runs out |
| Ice | the chill timer renews to 2.5 s on **every** dose, but stacks only grow while the enemy is not frozen; the dose that brings stacks to 4 resets them to 0 and freezes for 1.6 s × 0.6 for a brute; velocity × 0.2; the stacks reset when the chill runs out |
| A blow that kills | applies **nothing** (`hit_enemy` kills instead of calling `afflict`): the victim never burns, so it never spreads |
| Which sword | the blow's sword's element, with `power = sword.damage` (not the blow's damage), `stacks = 1` for Fang's automatic attack and Viper Flurry's darts (Warden, Pike and Colossus pass 2 or 3 in the prototype: `hit_enemy(..., stacks)`) |

Asserted by `conditions: fire burns, refreshes and expires`, `poison stacks to six and expires`,
`ice chills, freezes at four stacks, thaws and expires` and `each sword's own blows apply its
own element`: tick-for-tick replays of the fire, poison and ice cases plus the semantic checks that
read the observed run (the cap, the freeze tick, the thaw 96 ticks later, 57 for a brute,
the chill and its stacks vanishing 150 ticks after the last dose, stale dps not reused).

### Damage rounding and the frozen bonus (`hit_enemy` 1122-1158)

`damage = raw × 2 (if critical) × 1.3 (if frozen)`, then `max(1, round(damage))` with
**Python's round-half-even**, applied to the enemy before the element. The blow does not end the
freeze. Damage over time is not critical and not boosted. Examples read from the prototype:
a 7 blow deals 7 unfrozen and 9 frozen; 5 × 1.3 = 6.5 deals 6; 15 × 1.3 = 19.5 deals 20;
25 × 1.3 = 32.5 deals 32; a Common critical on a frozen enemy deals 18; a Viper Flurry dart
(8.4) deals 8 unfrozen and 11 frozen.

Asserted by `conditions: the frozen damage bonus and its rounding` (thirty blows on frozen
enemies and the same thirty on unfrozen ones, each against the prototype and against
`max(1, py_round(raw × 2? × 1.3?))`; a blow made lethal by the bonus; the freeze surviving blows).

### Frozen enemies (`Enemy.update` 515-552; contacts 1577-1581)

A frozen enemy's own clock (`t`) stops, it does not steer (it decays its velocity like a
stunned one, cancelling a spitter's wind-up and holding its cooldown), and the contact loop skips
it entirely: it neither hurts the player nor is pushed by the touch. A chilled (not frozen) enemy's
wanted velocity is halved after the type's own steering (runner weave, spitter bands).

| Case | Reference |
|---|---|
| a husk overlapping the player, unfrozen | hurts at tick 1 (10 damage), is pushed away |
| the same, frozen 1 s | no damage until the tick it thaws (tick 60), not pushed |
| chilled husk walking 400 px from the player | 97 px in 2.3 s against 202 px unchilled; full pace again after the chill expires |
| frozen runner coasting | `t` stays 0 for the freeze, resumes after |
| spitter, 0.1 s cooldown, 300 px away | first orb at tick 37 free, tick 97 when frozen for 1 s (60 ticks later) |

Asserted by `conditions: a frozen enemy cannot hurt the player by contact` and `chill slows, a
frozen enemy stops steering and its clock stops`.

### Fire spread (`kill` 1275-1286) and chains

A burning enemy's death (by a blow, bowling, a wall slam or its own damage over time: they all
come through `kill`) ignites its living neighbours. The fixture rings a victim with husks at 101
and 103 px (reach 102), brutes at 115 and 117 px (reach 116), one neighbour already burning at
7.5 dps, one at 1.7 dps and one already dead: the 101 px husk and the 115 px brute burn at
1.74 dps (0.6 × 2.9) for 2.1 s; the 103 and 117 px ones do not; the strong burn keeps 7.5 and keeps
its longer timer; the weak one is raised to 1.74; the dead one is untouched. Spread **sets
burns only**, so a chain advances one death at a time: five husks 90 px apart, the first burning
and struck dead, die at ticks 2, 125 and 248 at 2.9, 1.74 and 1.044 dps, the fourth (0.6264 dps
for 2.1 s, 1.3 damage against 2 health) survives with 1 health and the fifth is never ignited.
A death that is only poisoned and chilled spreads nothing, and neither does a fire sword's
killing blow (it afflicts nothing).

Asserted by `conditions: a burning death spreads fire to its neighbours` and `spread chains
advance one death at a time`.

### Deaths during ongoing effects, exactly once

Damage over time kills through the same `kill` (rewards once: kill counter, combo, healing
motes, cue); a corpse is skipped by later ticks; two enemies can die on one tick; a blow that
kills just before its poison would have landed leaves the poison nothing to kill; poison finishes a
frozen enemy (it shatters); poison finishing a burning enemy still spreads. A condition
death while a flurry has the enemy as its victim is the existing `_in_play` guard: no dart
on the corpse, no second kill.

Asserted by `conditions: deaths during ongoing effects resolve exactly once` (including four enemies
dying of burn and poison under a running flurry: four kills, four cues) and the render-rate fight.

### Viper Flurry darts and automatic attacks

Each dart is a heavy `hit_enemy` with `stacks = 1`: the poison sword's flurry on one enemy adds one
stack per dart (cap 6), the ice sword's freezes on the fourth dart and the darts after it deal the
frozen 11 instead of 8, the fire sword's keeps the burn renewed. Each sword's automatic attack
applies its own element on its first blow (tick 8 in the reference).

Asserted by `conditions: Viper Flurry darts apply their sword's element` and `each sword's own
blows apply its own element`.

### The first wave with conditions ON

`survival.wave1_three_fangs_stationary_player`: three Fang swords (poison, ice, fire), the first
wave of eight husks, the player standing still, eight seeds. The prototype clears it in
12.23-13.75 s (13.12-14.6 s with `afflict` off, the #8 band), never loses health and kills all
eight. Asserted by `conditions: the first wave against three elemental Fangs`: the port clears all
eight seeds in 11.95-13.32 s (the same ±1 s band rule as #8), no seed loses health.

## What the port adds, and how it is shared

- **Where the rules live.** `ConditionDefs` (constants and the two dps formulas: typed
  definitions, ADR 0002), `EnemyConditions` (one enemy's burn, poison, chill, freeze and
  accumulator: `apply`, `ignite_from_spread`, `tick`, `dominant_element`; owned by
  `EnemyState.conditions`), and in `GameRun` only the consequences: `afflict(enemy, element,
  power, stacks)`, `_update_conditions(dt)`, the frozen bonus inside `hit_enemy`, the contact
  immunity in `_resolve_contacts`, and `kill`'s fire spread. `EnemyConditions.tick` returns the
  whole damage to deal; it never kills, so an enemy can only die through `GameRun.kill`.
- **One application path.** Sword blows (`hit_enemy` → `afflict`) and, later, Cataclysm's field
  ticks (issue #15: `afflict(enemy, field.element, field.power)` every 0.5 s) share it; it
  ignores dead enemies, unknown elements and condition-free fixtures. `hit_enemy` takes the
  prototype's `stacks` (default 1) so the other sword types' blows need no new path.
- **Update order** (`GameRun.step()`): paused returns; the real clock, shake and kick advance;
  hitstop freezes everything else; slow motion scales `dt`; `_update_player`; each sword slot's
  `SwordState.update` in slot order; every enemy's `update` (chill slows, frozen holds);
  `_separate`; **`_update_conditions`** (damage over time, expiry, deaths, spread); `_resolve_contacts`
  (frozen enemies skipped); removal of the dead; `_update_projectiles`; `_update_motes`; combo,
  banner, wave director and camera. The prototype's `update_fields` will go right after
  `_update_conditions` (issue #15).
- **Time.** Conditions advance by the scaled gameplay `dt`, so they freeze during hitstop and slow
  down in slow motion like every other timer; the render-rate probe plays a fight full of burns,
  poison, freezes and spread deaths at 5, 20, 60 and 240 fps and gets one outcome.
- **Randomness.** The simulation draws nothing for conditions (the prototype's draws there are
  cosmetic particles); the effects layer has its own random stream.
- **Cues** (`SimCue`, `element` field): `ENEMY_FROZEN` (position), `ENEMY_SHATTERED` (died frozen),
  `CONDITION_DAMAGE` (whole points, the element shown), `FIRE_SPREAD` (a burning enemy died) and
  `ENEMY_HIT` tagged `ice` when it struck a frozen enemy. They are for presentation and audio
  only; gameplay never reads them.
- **Presentation** (read-only, ADR 0003). `EnemyVisual.apply_conditions(ConditionView)` hands a
  visual a read-only copy each tick (a visual that draws nothing may ignore it; the replacement
  `alt_enemy.tscn` is handed it and the whole fight is unchanged). The placeholder greens a poisoned
  body by stack, pulses a burning rim and warm glow, cools a chilled rim, blanches a frozen body inside
  a hexagonal ice shell, and draws one pip per element above the health bar (fire one, poison and ice
  their stacks; a ringed pip means more than one). The effects layer sheds embers, drips and ice
  motes at the prototype's rates, bursts on a freeze or a shatter, rings a burning death, and shows
  burn and poison damage as small numbers in the element's colour and a frozen-struck blow in ice
  blue. A freeze plays the existing `parry` ping (the prototype plays it too). Each sword's card
  names its element (POISON / ICE / FIRE) in its colour; a sword was already tinted by its element.
- **The condition-free fixture.** `RunScenario.conditions_enabled` (default **true**) and
  `without_conditions()`. The earlier slices' references were captured with `afflict` switched
  off, so their checks keep comparing against them on condition-free fixtures
  (`RunScenario.new().without_conditions()`, and the same for the crowd, wall and spitter
  encounters): their JSON is unchanged and their tolerances untouched. The shipped game always plays
  with conditions.
- **The conditions encounter** (dev fixture, no new control): the dev button / `C` now cycles normal →
  crowd → spitters → **conditions** → normal. One wave of eight husks, two runners and two brutes against
  the three-Fang loadout (`--encounter=conditions`, `?encounter=conditions`), so poison stacks, a
  freeze (shorter on a brute), chill, burning and fire spreading through the clustered crowd can all
  be watched. The prototype fields runners and brutes only from wave 2; the composition is a fixture,
  not a wave rule (issue #18).

## Deliberate exceptions

Each is a scope or correctness decision of slice #11, not a rebalance. No formula, duration,
cadence or threshold differs from the prototype.

1. **The earlier slices' fixtures are condition-free.** See above; the alternative (regenerating
   their references with `afflict` on) would have changed four committed files and mixed two
   oracles in one. The #8 survival band is therefore asserted twice: condition-free against the
   #8 reference, and conditions-on against this slice's reference.
2. **The fixture loadout is still three Fang swords.** The prototype's default is Fang / Warden /
   Colossus with poison / ice / fire. Only Fang's automatic attack and Viper Flurry's darts apply
   an element in this slice, each one dose; Warden's, Pike's and Colossus's blows (and their
   2-3 stacks) arrive with #13-#15, and `hit_enemy`'s `stacks` parameter is ready for them.
3. **Fields are not ported.** `update_fields` (1242-1257) and the Cataclysm's ground field are #15; the
   shared `afflict` is exercised by `afflict` events in the capture and by a field-style dose check.
4. **Healing motes are not compared.** Where a mote scatters is random in both games, so when one
   reaches the player cannot match; the reward is pinned by the kill counter, the kill cues and
   (in the exactly-once checks) the cue counts.
5. **Gameplay randomness is its own stream.** Crits, the dart's victim and the wander follow the
   prototype's distributions, not its random sequence. Conditions need none; cosmetic randomness
   (particles, number jitter) never uses the run's stream (the prototype uses one global stream).
6. **Cosmetics are not a gate.** Placeholder shapes replace the prototype's glows, shell and
   particle counts (a 6-point polygon becomes a closed 6-point hexagon, and so on); the sounds are
   the existing baked ones (the freeze ping is the `parry` asset, as in the prototype).
7. **The dead and unknown elements are ignored (hardening).** The prototype never calls `afflict` on a
   dead enemy (its callers check `dead`/hp first) and has no unknown elements; `GameRun.afflict`
   returns at once for either so a stale reference or a typo can never revive a condition on a
   corpse or invent one. Identical to the prototype for every reachable state.
8. **A burn that expires on this tick still deals this tick's damage.** The prototype subtracts
   `dt` and then adds the dps, so a timer that crosses zero shows a tiny negative value on its last
   tick (`-0.0167`) after paying one more step of dps. Preserved exactly (and visible in the
   reference), not "fixed".
9. **A killing blow afflicts nothing, and a damage-over-time number is coloured by whichever of
   burn and poison is stronger.** Prototype behaviour, preserved; listed because each looks like a
   bug at first sight.

## Validation

Counts and ids are in the pull request that closes #11; this table records what was run and
what it showed.

| Check | Result |
|---|---|
| `./build-godot.sh --checks-only` / full `./build-godot.sh` | see the pull request description (the count, build id and head it ran on) |
| Reference captures regenerate | `capture_fang_survival_loop.py`, `capture_crowd_and_walls.py`, `capture_spitters_and_parries.py` and `capture_viper_flurry.py` produce JSON byte-identical to the committed files; `capture_elemental_conditions.py` is deterministic (two runs identical) |
| Mutation check | see the pull request description |
| Web export, headless Chromium (software WebGL 2, 1280x720) | `SCENARIO=conditions` of `tools/godot/web-encounter-capture.mjs` against the full build's Web bundle served over HTTP with `?encounter=conditions`: the player walked with browser key events and Q, E and R were pressed; burning, poisoned and frozen foes, pips, the fire-spread ring and the element tags on the cards are visible ([`web-burning-poisoned-pack.png`](elemental-conditions/web-burning-poisoned-pack.png), [`web-fire-spread-ring.png`](elemental-conditions/web-fire-spread-ring.png), [`web-frozen-brute-and-pips.png`](elemental-conditions/web-frozen-brute-and-pips.png)). No console errors. |
| Windows export under Wine (not a Windows machine) | The full build's Windows ZIP extracted unmodified (`SHA256SUMS` verified before and after), run as `wine Swordster.exe --resolution 1000x563 --write-movie cond.png --fixed-fps 30 --quit-after 720 -- --encounter=conditions` from another directory: engine-side frames of the game's own viewport, no desktop capture, no input injected, nothing added to the game. The shipped game fights the encounter on its own: kills 12, burning / poisoned / frozen counts in the legend, `FROZEN`, a frozen brute in its shell, and `WAVE SURVIVED` ([`wine-shipped-burning-pack.png`](elemental-conditions/wine-shipped-burning-pack.png), [`wine-shipped-frozen-brute.png`](elemental-conditions/wine-shipped-frozen-brute.png), [`wine-shipped-wave-survived.png`](elemental-conditions/wine-shipped-wave-survived.png)). |

## What was not verified

- **No real Windows machine and no real Android device** (#6, #22). The Wine run proves the exported
  binary and the shipped pack run the encounter, not that a Windows machine does.
- **No input was sent to the Windows build** (no key or mouse event): the player stood still while the
  swords fought. Input-driven play was only exercised in the Web build, with synthetic browser events
  in headless Chromium and a software renderer, which says nothing about frame rate or touch.
- **No comparison against a played prototype session**: the prototype's outcomes are compared tick for tick
  in the capture's controlled fixtures and as a band over eight seeds of the first wave, not
  against a recorded human session.
- **Sound** was exercised by cue-to-sound mapping checks only, not by listening.
