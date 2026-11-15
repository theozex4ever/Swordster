# Reference: Pike and Skewer

Slice #14 of the Godot port ([spec #4](https://github.com/theozex4ever/Swordster/issues/4)),
following [the Fang survival loop](fang-survival-loop.md),
[runners, brutes and crowds](runners-brutes-crowd.md),
[spitters, projectiles and parries](spitters-projectiles-parries.md),
[Viper Flurry](viper-flurry.md), [elemental conditions](elemental-conditions.md) and
[Warden and Maelstrom](warden-maelstrom.md). The Python prototype `game/main.py` is the behavioural
oracle. This file records what was captured from it, the tolerances, the checks that assert each
value, and every deliberate exception. Vocabulary follows `GLOSSARY.md`: **Pike** is a sword type,
**Skewer** its ultimate, triggered through its equipped **sword slot**; **Converge** is a different
command (issue #16) and is not an ultimate.

The sword type keeps the prototype's internal identity: Pike is `SWORD_TYPES["lance"]`, so the Godot
type id is `lance` (`SwordDefs.PIKE`), exactly as Warden is `blade`; the displayed names (Pike,
Skewer) come from `SwordDefs.display_name` / `ultimate_name`.

## How the reference was captured

`tools/reference/capture_pike_skewer.py` reuses the loader and helpers of
`capture_fang_survival_loop.py` and `capture_viper_flurry.py`, drives the prototype's real classes
(`Game`, `Sword`, `Enemy`, `Projectile`) with fixed 1/60 s steps under SDL's dummy drivers, and
writes `godot/tests/reference/pike_skewer.json`. Regenerate with:

```sh
python3 -I tools/reference/capture_pike_skewer.py godot/tests/reference/pike_skewer.json
```

Nothing is re-implemented: the targeting, the windup, the thrust, its hit set and its parries come
from `Sword.acquire`, `Sword.begin`, `Sword.update` and `Sword.strike`; the aim, flight, impalement,
carry and release from `Sword.ultimate` and `Sword.update_ult`; wall slams and bowling from
`Enemy.update` and `Game.separate`/`wall_slam`; damage, crits, rounding and conditions from
`Game.hit_enemy` and `Game.afflict`; the Q/E/R keys through the real `Game.handle` with synthetic
`KEYDOWN` events and a patched mouse position. Every case writes its fixture (`setup`) into the JSON,
including the player's position and facing and whether elemental conditions are on, and the Godot
checks build their scenarios from it. The JSON holds 5107 traced ticks, 114 + 114 thrust-geometry
probes, 36 + 42 orb-parry probes and 14 start points.

**Conditions per case.** As in the Warden slice, `setup.conditions` says which the prototype ran with
(`fixture_scope.afflict_enabled_cases`):

- **Off** for every physical case: targeting, geometry, hit-once, parries, the aim, flight, carry,
  walls, boundaries, deaths, recharge and refusals.
- **On** for `conditions.thrust.{poison,ice,fire}` and `conditions.skewer.{poison,ice,fire}` (a
  Pike's thrust through three enemies for 260 ticks, a Skewer through three for 130; every condition
  field per tick) and for `skewer_deaths.burns_while_carried` (a fire Skewer leaves an enemy at 2 hp;
  it burns to death while it is carried).

Other controls (asserted by the capture, recorded as `fixture_scope`): every enemy is an unarmed husk,
runner or brute (arming and drops are issue #17); only Pike swords are equipped and Converge is never
commanded (#16); the wave machine is off (#18); a sword that is not meant to fight has its
auto-attack cooldown parked at 99 s; enemies stand still; crits are forced off (or on) by pinning
`random.random`. The geometry and parry grids start the thrust directly with `Sword.begin(target, aim)`
(Converge's own entry point) so the thrust line is chosen by the fixture instead of `acquire`, and
`skewer_boundary` puts a sword in flight directly, a tick short of the arena's edge.

## Tolerances

Chosen before accepting any difference; the same as the earlier slices: position ±0.05 px, velocity
±0.5 px/s, timers / stun / flash / hitstop / shake ±0.002, angles ±0.002 rad, health ±0.001, headings
±0.0001, damage / kills / counts exact, summary event ticks ±1. In practice every compared tick and
value matched exactly: the traces are compared on **every tick** (sword phase, Skewer sub-phase,
carried count, position, angle, velocity, clocks, recharge, cooldown; every enemy's position,
health, velocity, stun and death), not at sampled ticks.

## Reference values and the checks asserting them

### The sword (`SWORD_TYPES["lance"]` 91–96; `Sword.__init__` 568–606)

| Quantity | Value |
|---|---|
| Name / blurb | Pike / "long / piercing thrust" |
| Length, width | 74 px (x1.08 / x1.18 by rarity), 6 px |
| Range | 430 px (x1.06 / x1.12) |
| Cooldown | 1.35 s (x0.87 / x0.74) |
| Damage | 24 (x1.3 / x1.75): 24 / 31 / 42; x2 on a crit |
| Knockback / hitstop / shake | 380 x the enemy's knock factor; 0.06 s; 0.2 with a direction |
| Windup / thrust speed | 0.32 s (19 ticks); 2400 px/s (40 px per tick) |

Line numbers refer to `game/main.py` at this repository's base commit. Asserted by `pike: identity, constants and rarity numbers against the prototype`.

### Targeting (`Sword.acquire` 629–642)

Of the enemies within `range + radius` of the *player*, any farther than 130 px from the player are
preferred (the Pike wants a long thrust): only those are considered while one exists, then the
nearest of them. Exactly 130 is not "far"; an enemy farther than 130 but out of range does not count
as a candidate. Ten layouts are captured (a far one over a near one in either placement order, 130
and 131, the nearest of several far ones, a far one just outside range, runners and brutes at the
edge): `pike: who it targets`.

### The thrust (`Sword.update` windup 724–727 and strike 780–792; `Sword.strike` 1019–1024)

- **Windup.** The sword springs (k 150, c 20) to `aim - d x (0.5 length + 120)`, `d` being the heading
  from the *player* to the aim point, and turns toward `d` (rate 16). Recomputed every tick, so it
  follows a moving target until the strike.
- **Strike.** `dir = norm(aim - sword)` is fixed; the sword flies along it at 2400 px/s for
  `(distance to the aim + 170) / 2400` seconds. Each tick the swept segment runs from
  `0.3 length` behind where the sword was to `0.65 length` ahead of where it is; every enemy within
  `radius + 7` of it that is not yet in this attack's hit set is struck once, in the run's enemy order
  (the dead included: `hit_enemy` ignores them). The sword does **not** stop on a hit. Then every orb
  within 8 px of the segment is parried, hit or no hit. After 0.35 s of recovery at 420 px/s along the
  line the sword returns to its orbit.
- **Per-attack hit set.** Cleared when an attack (or an ultimate) begins.
- Captured: `thrust.{common,common_crit,rare,mythic}` (windup 1, strike 21, hit 24, recovery 34, idle
  56, the next attack from 106 (the first cooldown tick-for-tick); 24 / 24 x2 / 31 / 42 damage);
  `geometry` (114 husk and 114 brute probes at 13 along-line offsets and 10 lateral offsets: 33 and 55
  are reached, on the same tick as the prototype, the rest missed); `piercing.dense_line` (eleven
  husks 38 px apart: the first nine struck exactly once by one thrust, none twice, none skipped at
  2400 px/s), `piercing.spread_pack`, `piercing.brute_across_attacks` (a radius-30 brute hit once per
  thrust over four thrusts) and `piercing.three_pikes`; `deaths.*` (a corpse is not hit again, by the
  same or another Pike); `parry.*` (36 orb probes, 12 parried; an orb behind the target on the line
  is parried whatever the thrust hit or missed).

### Skewer (`SWORD_TYPES["lance"]["ult"]` 95; `Sword.ultimate` 848–852; `Sword.update_ult` 938–979; `Game.ultimate` 1400–1415)

| Phase / quantity | Value |
|---|---|
| Key | Q / E / R by slot; a skill shot: the aim point only gives the **heading** `norm(point - player)` (the player's facing if they coincide), never pulled back to a range |
| Recharge | 10 s (x0.87 / x0.74) from the command |
| Aim | 0.38 s (23 ticks): the sword springs (k 200, c 24) to `player - dir x 40` and faces `dir`; nothing is struck or parried |
| Launch | The sword appears at `player + dir x 10`, flies 950 px at 2600 px/s (22 ticks), shake 0.2 along `dir` |
| Each flight tick | Segment `0.3 length` behind to `0.65 length` ahead. In enemy order, every enemy within `radius + 18` not yet in the hit set (a corpse killed earlier this tick joins it) takes 2.2 x damage, no knockback, two doses of the element, a heavy flash and shake 0.12; a survivor is impaled. Then the impaled that died are dropped, the rest are moved by the sword's step with velocity zeroed and stun at least 0.5 s, and every orb within 14 px is parried |
| End | When the range is spent **or** the tip leaves the arena shrunk by `inflate(-20, -20)` (10 px a side; pygame's rectangle contains its left and top edges, not its right and bottom): everything still impaled is flung along `dir` at 1100 px/s at a wall (where the stunned enemy slams, bowling the enemies it meets) or 750 px/s at the range limit, stun at least 0.6 s; the sword recovers for 0.35 s, kicked back at 300 px/s from a wall, carried on at 420 px/s from the range |

Captured and asserted: `start.*` (14 points: inside, at and past the 950 px range, diagonal, south, on
the player with either facing; the sword does not move; the recharge and aim clock start; a command
interrupts a windup and a thrust); `skewer_single.*` (aim 23 ticks, launch, blow at tick 31 for 53 /
106 on a crit / 69 / 93, carry, release on tick 45, idle on 67); `skewer_carry.*` (a line with
enemies beside, behind and beyond; the muzzle: the first flight tick reaches 0.3 lengths behind the
launch; a crowd; three Skewers at once); `skewer_empty.*`; `skewer_walls.*` (east, west, north, south,
two corners and a pile-up: the release at 1100 px/s, the slam damage `6 + (speed - 380) x 0.04`,
bowling, an enemy pinned at the wall, the sword's kick-back); `skewer_boundary.*` (0.01 px inside and
outside each of the four edges of the 10 px margin: the flight ends one tick apart); `skewer_range.*`;
`skewer_deaths.*`; `skewer_rules.*` (recharge 600 / 522 / 445 ticks by rarity, refusal while
recharging and while flying, firing again after the recharge, the other Pikes keep thrusting);
`skewer_parry.*` (42 orb probes, 15 parried; none during the aim); `conditions.*`; `keys.*`.

### Enemies that die or leave the run (spec decision 7)

The prototype iterates **every** enemy of the update in its sword, movement and separation loops,
corpses included, and removes the dead only at the end of the update; only `hit_enemy` returns early
for them. The port mirrors that loop by loop (no `if enemy.dead: continue` where the prototype has
none), and the captured cases are the ones that catch a divergence:

- `skewer_deaths.killed_by_the_blow`: two enemies killed by the blow itself are not impaled and the
  Skewer flies on.
- `skewer_deaths.corpse_joins_the_hit_set`: a Pike's thrust (slot 0) kills an enemy on the very tick the
  Skewer (slot 1) reaches it; the corpse is added to the Skewer's hit set, is not impaled, is not
  struck or rewarded again. (Mutation `skewer-hit-loop-skips-corpses` re-adds the guard.)
- `skewer_deaths.killed_while_carried_{at_once,later}`: an impaled enemy killed from outside (`Game.kill`)
  beside living neighbours: it leaves the carry list at the next flight tick but, still in the run
  until its tick ends, is moved, separated and counted as the prototype does.
- `skewer_deaths.burns_while_carried`: an enemy left at 2 hp by a fire Skewer burns to death during the
  carry (tick 58) with neighbours carried on.
- `skewer_deaths.corpses_at_the_wall`: two impaled enemies (one pinned at the wall) die on the tick
  before the Skewer ends at the east wall; the corpses are dropped from the carry, the rest are flung
  and slam.
- `skewer_deaths.player_dies_in_flight`: the sword goes idle and lets go.

An impaled enemy that leaves the run **alive** (not reachable in the prototype) is let go by the
port's `_in_play` guard (the carried list is a reference across ticks): it is no longer moved, flung
or stunned. Asserted by `pike: enemies that leave the run are handled safely`.

## What the port adds, and how it is shared

- **Simulation** (`godot/scripts/sim/`): `sword_state.gd` dispatches the Pike's targeting
  (`acquire`), windup (`_update_thrust_windup`), thrust (`_update_thrust`) and Skewer
  (`begin_ultimate`, `_update_skewer`); `sword_defs.gd` holds the numbers; `skewer_flying` and
  `skewer_carried` are the Skewer's gameplay state (the prototype's `phase == "fly"` and `carried`);
  `GameRun.parry_projectiles` is shared with Fang and Warden. A thrust and a Skewer sweep a segment
  per fixed tick, so nothing tunnels at 2400 or 2600 px/s at any render rate (the render-rate probe
  plays a Pike and Skewer fight at 5, 20, 60 and 240 fps with identical outcomes).
- **Cues**: `SKEWER_LAUNCHED` and `SKEWER_RELEASED` (`amount` = how many were flung, `critical` = it
  ended at a wall). The wall slam is the existing #9 cue.
- **Encounter** (`RunScenario.pike_encounter()`): a column of six foes 330 to 90 px from the north wall
  and a wave of twelve more (two brutes) against three Pikes, poison / ice / fire, with the player at
  (1300, 700): aim north and a Skewer carries the column into the wall. Reachable with the dev button
  / `C` (the cycle is now normal, crowd, spitters, conditions, warden, pike, normal), `--encounter=pike`
  and `?encounter=pike`. The normal run is unchanged: three Fang swords (the final default is #16).
- **Presentation** (replaceable, ADR 0003; it only reads `SwordState` and cues): the Pike is a long
  shaft with a leaf head; a thrust's windup draws the line it will cut; a Skewer's aim draws its line
  out to 950 px, its flight rings every carried enemy, its launch and release draw rings and sparks and
  a "SLAM x4" / "FLUNG x2" number; the HUD cards read "Skewer" and "Pike sword  skill shot"; the
  encounter legend counts Skewers launched and wall slams; the launch and a release that flung
  something are heard.

## Deliberate exceptions

Each is a scope or correctness decision of slice #14, not a rebalance.

1. **The pike encounter is the only way to field Pike; the normal run is unchanged.** The earlier
   slices' cycle checks were extended by one step; nothing else about them changed.
2. **Gameplay randomness is its own stream** (crit rolls, the random heading for a zero-length
   vector), as in the earlier slices.
3. **The wall test fixes a bug in the first #14 commit.** `WORLD.inflate(-20, -20)` removes 20 px
   from the width and the height in total, i.e. 10 px a side; the first commit used 20 px a side.
   Found by the boundary capture; mutations `skewer-wall-margin-too-wide` and
   `skewer-wall-margin-none` guard it.
4. **Corners and walls are decided by the tip alone**, as in the prototype: the sword's whole step is
   applied and the enemies are carried even into and past a wall (their own movement clamps them).
5. **The Skewer's carried list is a reference across ticks**, so it is validated each flight tick
   with `_in_play` (alive and still in the run), like the other cross-tick references.
6. **A known float32-versus-float64 boundary at resting contact (not fixed, no gameplay change).**
   Carried enemies are driven into the same few pixels ahead of the tip, and the crowd separation
   leaves a touching pair at exactly `dist == radius_a + radius_b` up to rounding. When the Skewer
   lets go, whether that pair is bowled (`dist < reach`) depends on which side the rounding falls: the
   prototype's float64 and Godot's float32 `Vector2` can fall on different sides (observed: the
   prototype bowls an enemy for 3 and slows the bowler to 0.6, the port does not, on the release tick,
   in fixtures whose carried enemies touch). Fixtures with such a pile (`skewer_carry.{line,muzzle,
   crowd}`, `skewer_range.*`, `skewer_deaths.killed_while_carried_*`, the two corner walls) are marked
   `compare: until_release` in the JSON with a `stable_ticks` field: they are compared tick by tick
   up to the release (carry included) and after it only for invariants (nothing carried, the sword
   recovering). Everything else, including the east, west, north, south and pile-up walls with their
   slams and bowling, matches on every tick. No exact fix is cheap (it would need float64 positions
   throughout the simulation), as for #13's pull cutoff.
7. **No touch ultimate buttons and no Converge.** Touch aiming (`ultimate_at_nearest`) works for a Pike
   (the heading toward the nearest enemy, or 300 px ahead) but the on-screen buttons are issue #20, and
   Converge's fast windup is issue #16.
8. **Cosmetics are not a gate**: the prototype's lift (`z`), trails, sparks, "pierce" and "heave"
   sounds beyond the placeholders are not reproduced.

## Validation

Linux, Godot 4.7.2-stable. Base `origin/main` `2d68b50`; branch `feat/14-pike-skewer`.

| What | Result |
|---|---|
| `./build-godot.sh --checks-only` / full `./build-godot.sh` | `CHECKS PASSED: 1325` (the earlier slices' dev-encounter cycle checks were extended by one step). Full build OK on a clean tree: `20261115-083723-ed7ff2bd8` (head `ed7ff2b`; its `SHA256SUMS` verifies). |
| `tools/godot/mutation-check.sh` | **583 of 583** deliberate bugs caught, 0 inconclusive, 0 survived: one complete pass in 7 parallel shards (`SHARD=i SHARDS=7`, 84 / 84 / 83 / 83 / 83 / 83 / 83) on head `ed7ff2b`, baseline `CHECKS PASSED: 1325`. 453 of the 583 are the earlier slices' (eight of them repaired because the first #14 commit changed the text they patch); 130 are new, for the thrust, targeting, Skewer, walls and boundaries, deaths, the encounter, HUD and presentation. Earlier passes found test-side problems, all fixed before this one: survivors in the presentation and HUD checks (the legend counts, the launch sound, the release ring and number, the column fixture), mutations that were equivalent (impaling a corpse: the carry filter removes it in the same tick; clamping a skill shot to a range: the heading is unchanged) or could only crash the engine's own guard (`pike-unsupported`) and so were dropped or replaced, and checks that crashed instead of failing when an enemy or orb had died |
| Reference regeneration | All seven captures (`capture_pike_skewer.py`, `capture_warden_maelstrom.py`, `capture_fang_survival_loop.py`, `capture_crowd_and_walls.py`, `capture_spitters_and_parries.py`, `capture_viper_flurry.py`, `capture_elemental_conditions.py`) rerun on the head give output byte-identical (`cmp`) to the committed JSON; the six earlier JSON files are unchanged in this PR, as is `game/`. |
| Low/high render rates | The scripted Pike fight (three Pikes, six Skewers north, east, north-east, west, south and north again, two refused presses, columns of husks, runners and brutes slammed into the north and east walls and a corner, pinned spitters whose orbs are parried) played in the real Main scene under the engine's fixed-step loop at 5, 20, 60 and 240 fps ends with a digest identical to a bare `GameRun.step()` loop every time. |
| Per-tick comparison with the prototype | Sword pose, phase, carried count, velocity, clocks, recharge and every enemy's position, health, velocity, stun and death (and every condition field in the condition cases) match on every tick of every captured trace, except the fixtures marked `compare: until_release` (exception 6), plus 228 thrust-geometry, 36 thrust-parry and 42 Skewer-parry probe points. |
| **Web export, headless Chromium (software WebGL 2 via SwiftShader, 1280x720)** | Build `20261115-044153-950123b36`, served over HTTP with `?encounter=pike` and driven with browser mouse-move and key events (`tools/godot/web-encounter-capture.mjs`, `SCENARIO=pike`): **E** with the cursor above the player starts a Skewer north (the "SKEWER" text, the card ACTIVE, rings on the carried foes), the Skewer ends at the north wall with a wall slam and "wall slams 1" in the legend, **E** again while recharging is refused ("recharging 0s", the card at `0s`), **Q** fires a Skewer east (the card at `8s`) and **R** west. Console: the three Godot start-up lines, no errors. The frame pacing of the capture is the browser's, not a measurement; the press-to-slam timing in the screenshots is the browser's, not the simulation's. |
| **Windows export, under Wine 11 on Linux (not a Windows machine)** | The same build `20261115-044153-950123b36`: the full build's ZIP extracted unmodified, its own `SHA256SUMS` verified, the shipped `Swordster.exe` and `Swordster.pck` run as `wine ./Swordster.exe --resolution 1000x563 --write-movie <frames> --fixed-fps 30 --quit-after 450 -- --encounter=pike` (a scratch Wine prefix): engine-side frames of the game's own viewport (no desktop capture, no input, nothing added to the game). The frames show the pike encounter's HUD (the three cards **Q / E / R Skewer READY**, "Pike sword  skill shot"), the three Pikes with their long shafts and leaf heads, the column arriving and thrusts cutting through it with their 24-damage numbers. **What this does not show:** a Skewer in the Windows build. No key or mouse event was sent to the shipped build (no autopilot exists in the game), so Q/E/R input in a Windows build belongs to the deferred device matrix (#6/#22); the Skewer itself is shown in the Web build. |

The web and Wine frames were taken from build `20261115-044153-950123b36` (head `950123b`). Nothing under `godot/scripts`, `godot/scenes`, `godot/audio` or `godot/project.godot` changed after it: the later commits (`ae36554`, `ed7ff2b` and the documentation) changed the mutation script, the web capture script, the checks and docs only, so the frames are of the shipped game code of the final head (the final head's build, `20261115-083723-ed7ff2bd8`, contains the same game code).

Screenshots (in `docs/reference/pike-skewer/`):
[`web-pike-skewer-flight-north.png`](pike-skewer/web-pike-skewer-flight-north.png) (a Skewer in flight, the "SKEWER" text, the card ACTIVE, carried foes ringed at the top),
[`web-pike-skewer-wall-slam-and-recharge.png`](pike-skewer/web-pike-skewer-wall-slam-and-recharge.png) (just after the wall: the slam, `wall slams 1`, the card at `8s`),
[`web-pike-e-refused.png`](pike-skewer/web-pike-e-refused.png) (E refused while recharging),
[`web-pike-q-skewer-east.png`](pike-skewer/web-pike-q-skewer-east.png) (Q east, the card at `8s`),
[`wine-shipped-pike-thrust-and-hud.png`](pike-skewer/wine-shipped-pike-thrust-and-hud.png) and
[`wine-shipped-pike-thrusts.png`](pike-skewer/wine-shipped-pike-thrusts.png) (shipped pack, no input).

## What was not verified

- **No real Windows machine** and no real Android device (#6, #22). The Wine run proves the shipped export
  launches and renders the Pike fight and HUD, not that it behaves on Windows. No touch ultimate controls
  exist yet (#20), so Android has nothing to test.
- Web was run in headless Chromium with a software renderer and synthetic browser input, not Firefox, a
  real GPU or a phone. Frame pacing and audio were not measured (audio was muted).
- Windows evidence is engine-side frames of the shipped pack under Wine with no input: no Q/E/R key or
  mouse event was sent to it (the game has no autopilot), so a Skewer in the Windows build belongs to the
  deferred device matrix; the Skewer into a wall is shown in the Web build.
