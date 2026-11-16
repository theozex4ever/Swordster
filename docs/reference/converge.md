# Reference: Converge and the default loadout

Slice #16 of the Godot port ([spec #4](https://github.com/theozex4ever/Swordster/issues/4)),
following [the Fang survival loop](fang-survival-loop.md),
[runners, brutes and crowds](runners-brutes-crowd.md),
[spitters, projectiles and parries](spitters-projectiles-parries.md), [Viper Flurry](viper-flurry.md),
[elemental conditions](elemental-conditions.md), [Warden and Maelstrom](warden-maelstrom.md),
[Pike and Skewer](pike-skewer.md) and [Colossus and Cataclysm](colossus-cataclysm.md). The Python
prototype `game/main.py` is the behavioural oracle. This file records what was captured from it, the
tolerances, the checks that assert each value, and every deliberate exception. Vocabulary follows
`GLOSSARY.md`: **Converge** is the player's coordinated command to all three equipped spirit swords; it
is **not** an ultimate (ultimates belong to a sword type and run through their sword slot, Q / E / R).

## How the reference was captured

`tools/reference/capture_converge.py` reuses the loader and helpers of `capture_fang_survival_loop.py` and
`capture_viper_flurry.py`, drives the prototype's real classes (`Game`, `Sword`, `Enemy`, `Player`) with fixed
1/60 s steps under SDL's dummy drivers, and writes `godot/tests/reference/converge.json`. Regenerate with:

```sh
python3 -I tools/reference/capture_converge.py godot/tests/reference/converge.json
```

Nothing is re-implemented. The click, the cooldown, the pause and death refusals and the 460 px clamp come from
the real `Game.handle` (a synthetic `MOUSEBUTTONDOWN` with a patched mouse position) and `Game.converge`; what each
sword does with the command from `Sword.command`, `Sword.begin(boost=1.5, fast=True)`, `Sword.update` and
`Sword.strike`; the damage from `Game.hit_enemy` and `Game.slam`; Q / E / R and Tab / G from `Game.handle`; the touch
Converge from `Game.auto_aim`; and the normal start from `Game.reset` and `Sword.__init__`. The capture wraps
`Sword.command` (every sword offered a command, its state before and after, the target it chose) and `Game.ring`
(where the Converge ring landed: the range-clamped point), and logs every click. Every case writes its fixture
(`setup`: swords, enemies, the player, whether conditions are on, and a `script` of timed clicks, keys, `Sword.begin`
calls, kills, a corpse, a hurt, pause, resume, reset) into the JSON and the Godot checks rebuild it. The JSON holds 68
traced cases (9,467 ticks, 145 clicks, 210 swords offered a command) and the default-loadout wave runs.

**Conditions per case.** `setup.conditions` says which the prototype ran with: **off** for every physical case
(targeting, boost, windups, eligibility, cooldown, refusals), **on** for the three cases whose subject is the default
loadout with its own elements (`default_converge`, `default_converge_far`, `default_converge_rarity`) and for the
wave runs. The capture asserts it (`fixture_scope`): only unarmed husks (arming and drops are issue #17), no waves
(#18) except in the wave runs, auto-attack cooldowns parked at 99 s unless a case says otherwise, crits pinned off.

## Tolerances

The same as the earlier slices: position ±0.05 px, velocity ±0.5 px/s, timers / stun / flash / hitstop / shake /
cooldowns ±0.002, angles ±0.002 rad, health ±0.001, counts exact. The wave runs are bands (see below).

## Reference values and the checks asserting them

| Rule | Prototype | Port |
|---|---|---|
| Cooldown | `CONVERGE_CD = 2.5`, started by every accepted click, ticks down with gameplay time | `SwordDefs.CONVERGE_COOLDOWN`; `GameRun.converge_cooldown_left` after the combo counter in `step()`, so hitstop freezes it and slow motion slows it |
| Range | a point more than 460 px from the player is pulled back onto 460 px along its direction | `SwordDefs.CONVERGE_RANGE`, `GameRun.try_converge` |
| Eligibility | `Sword.command` ignores `strike`, `stuck` and `ult`; idle, windup (restarts) and recover take it, whatever `cd` says | `SwordState.command` (`Phase.STRIKE`, `STUCK`, `ULTIMATE`) |
| Cooldown when nobody takes it | started anyway | same, and the `CONVERGE` cue says how many took it |
| Refusals | `converge` returns while `converge_cd > 0` or the player is dead; `handle` ignores clicks while paused | `ConvergeResult.COOLING_DOWN` / `UNAVAILABLE`, silent |
| Target | the enemy nearest the point within 90 px (strict `<`, first of equals), a dead enemy still in the list included; none → the point itself | `SwordDefs.CONVERGE_TARGET_RADIUS`; dead or removed targets are dropped by the sword's own update (`_in_play`) |
| Attack | `begin(tgt, point, boost=1.5, fast=True)`: windup 0.6x the type's, `boost` multiplies the blow (Fang 7 → 10, Warden 17 → 26, Pike 24 → 36, Colossus 50 → 75), side flips, hit set cleared; the next automatic `begin` resets `boost` to 1 | `SwordState.begin(…, fast)`, `command`; `windup_span` keeps the telegraphs honest |
| Buttons | MOUSEBUTTONDOWN 1 and 3 (left, right); not the middle one, not the wheel; not on mobile | `InputTranslator.CONVERGE_BUTTONS`, pressed only; touch-made mouse events are ignored (issue #20) |
| Ranges | Tab / G toggle `show_ranges` unless dead or paused; one circle per sword of radius `s.range` (rarity scaled) at the player, not drawn when dead; the flag survives a reset | `GameRun.show_ranges`, `EffectsLayer` (`range_ring`) |
| Touch Converge | `converge(auto_aim())`: nearest living enemy or 300 px ahead | `GameCommand.converge_at_nearest()` (no UI yet: issue #20) |
| Default loadout | `Game.reset`: Fang poison, Blade (Warden) ice, Colossus fire, Common, `cd` 0.2 to 0.6 | `RunScenario.default_loadout()`; `RunScenario.new()` and the normal start equip it; the earlier fixtures are explicit (`fang_fixture`, the warden / pike / colossus loadouts, the crowd, spitter and conditions encounters keep the three-Fang one) |

The checks (`godot/tests/converge_checks.gd`, 179 checks) replay every captured case through the real
`InputTranslator` and `GameRun` and compare every tick: sword state, pose, timers, cooldowns, boost, aim and target;
every enemy's pose, health, stun and flash (and conditions where on); the run's hitstop, shake, kills, player
and the Converge cooldown. They also compare every click (accepted or not, the cooldown before and after, the swords
that took it), every command and every ring against the capture's log. The rest are explicit: the near, far and empty
points, the clamp from the player (not the camera), the 89.9 / 90 px edge, ties, a removed target, the boost once and
not again, a Pike's shortened telegraph, the cooldown under pause, hitstop, slow motion and death, a click per tick for
2.5 s, all swords busy, Converge beside the three ultimates, the input mapping, the real Main scene (HUD buttons do not
Converge; a click on the arena does; the chime, the HUD countdown, Q / E / R in the default loadout), the aim across six
window sizes and after the camera moved (checked against the engine's own canvas transform), the attack-range rings,
a replaced sword visual leaving the fight unchanged, and the default-loadout fight at 5, 20, 60 and 240 fps.

## Deliberate exceptions

1. **Randomness the port cannot reproduce.** A Fang's recoil heading after a hit (and at the end of its flurry) and the
   knock heading of an enemy standing exactly on a slam's impact point are drawn from the prototype's random stream.
   The capture finds them (`random_sword`, `random_enemy`) and the checks stop comparing that sword's pose (or that
   enemy's motion) from that tick on. Where a recoiled Fang would strike a second time from its random pose,
   `compare_until` ends the comparison three ticks after that attack begins. Everything else in those cases is compared
   on every tick.
2. **Default-loadout wave runs are bands.** Spawn points and recoil differ by stream. The capture plays the first wave
   (husks only) on eight seeds with no input and with a Converge at the nearest enemy every 3 s (conditions on); the
   port must clear it on all eight, kill all eight, never die, within the captured band ±1 s, and a clicking player
   lands about as many Converges.
3. **A colossus's strike timer.** The prototype sets `timer = 1.0` when a slam starts and never reads it again (the
   fall is timed by its altitude); the port keeps no such timer and the checks skip it.
4. **A dead enemy still in the list.** No command ever sees one (the run removes the dead at the end of the tick that
   killed them), but the prototype's targeting loop does not skip them, so `SwordState.command` does not either; a case
   puts one there to prove it (`corpses`): the sword takes the corpse, drops it at its next update and strikes the point,
   instead of following a live enemy 78 px from the click.
5. **The chime.** The prototype's "chime" sound is a stand-in (`sfx_chime.wav`, generated by `tools/godot/gen_audio.py`).
6. **Clicks on HUD buttons.** The prototype has no desktop buttons; the port's Pause, Restart, Dash and Dev buttons
   take their own clicks, so a click on one is not also a Converge.
7. **Aim ignores screen shake.** As in the prototype's `mouse_world`, the world point is the camera's centre plus the
   cursor's offset from the middle of the visible area; the shaken camera only moves what is drawn.
8. **The visible area.** The port's stretch mode reveals more arena in a larger or taller window than the prototype's
   fixed 1280x720; the aim follows the visible area's size, so a click lands on what is under the cursor.

## Evidence (screenshots in `docs/reference/converge/`)

All Web screenshots and Wine frames come from build `20261116-003527-17165e49a` (head `17165e4`: #17's drops and swaps merged with this
slice; a clean tree; its `SHA256SUMS` verified). The Wine frames were refreshed in the round-2 review of #17 (they show the controls hint
regrouped so it clears the Pause / Restart buttons, and the HUD as it is now).

- **Web, headless Chromium with software WebGL, browser-level mouse and key events** (`SCENARIO=converge node
  tools/godot/web-encounter-capture.mjs`; the page is paused with P to take each screenshot): the normal start with the default
  loadout's three cards (Viper Flurry POISON, Maelstrom ICE, Cataclysm FIRE) and the attack ranges after Tab
  (`web-ranges-tab.png`); a left click 140 px east: all three swords converge on it (Colossus slam ring, Warden sweep, Fang
  dash), the HUD counts the cooldown (`web-left-click-near.png`); a right click during the cooldown is refused
  (`web-click-refused-cooldown.png`); a right click at a point about 670 px away: the slam lands 458 px from the player, the
  range clamp (`web-right-click-far-clamped.png`); Q, E and R with the cursor at three points: Viper Flurry recharging (7 s),
  Maelstrom active, Cataclysm recharging, Converge ready again (`web-qer-default-loadout.png`). The capture script's own first
  action, a click on the player to focus the canvas, is itself a Converge at the player's position.
- **Windows build under Wine (not a Windows machine), the shipped unmodified pack**, `SHA256SUMS` verified before and after,
  `--write-movie` (the movie is 1280x720: the game ignores the window size for its frames), no input and no autopilot: the normal
  start with the default loadout, the Converge line and the controls hint (`wine-shipped-normal-start.png`), and the swords
  fighting the first wave by themselves (`wine-shipped-default-loadout-fight.png`). A Converge is not shown under Wine; the Web
  screenshots show it. **Real-Windows input is deferred to #6 / #22.**
