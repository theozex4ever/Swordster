# Reference: armed enemies, sword drops, rarity and swaps

Slice #17 of the Godot port ([spec #4](https://github.com/theozex4ever/Swordster/issues/4)),
following [the Fang survival loop](fang-survival-loop.md),
[runners, brutes and crowds](runners-brutes-crowd.md),
[spitters, projectiles and parries](spitters-projectiles-parries.md), [Viper Flurry](viper-flurry.md),
[elemental conditions](elemental-conditions.md), [Warden and Maelstrom](warden-maelstrom.md),
[Pike and Skewer](pike-skewer.md) and [Colossus and Cataclysm](colossus-cataclysm.md). The Python prototype
`game/main.py` is the behavioural oracle. This file records what was captured from it, the tolerances, the checks that
assert each value, and every deliberate exception. Vocabulary follows `GLOSSARY.md`: an **armed enemy** carries one
**spirit sword** (a **sword type**, **element** and **rarity**) that lies where it fell as a **sword drop**; a **swap**
puts the nearest drop within reach into a chosen **sword slot** (keys 1, 2, 3) and the sword it replaces becomes a drop;
**Converge** (issue #16) and the **ultimate** are different commands.

Sword type identities are unchanged: Warden is `blade`, Pike is `lance` (`SwordDefs`). Elements are `fire`, `ice`,
`poison`; rarity is the index 0 Common, 1 Rare, 2 Mythic.

## How the reference was captured

`tools/reference/capture_drops_swaps.py` reuses the loader and helpers of `capture_fang_survival_loop.py` and
`capture_viper_flurry.py`, drives the prototype's real classes (`Game`, `Sword`, `Enemy`, `Pickup`) under SDL's dummy
drivers and writes `godot/tests/reference/drops_swaps.json`. Regenerate with:

```sh
python3 -I tools/reference/capture_drops_swaps.py godot/tests/reference/drops_swaps.json
```

The output is byte-identical on every run (every case seeds `random`; the returned drop's random offset and a pickup's
bobbing phase are the only randomness, handled below). Nothing is re-implemented:

- the rarity modifiers, names and stats come from `Sword.__init__` and `Sword.name`;
- the armed health from `Enemy.__init__`; the drop from `Game.kill` (reached through the real `Game.hit_enemy`);
- the arming rolls from `Game.start_wave`, driven with a **scripted random source** (`Script` replaces
  `random.uniform`, `random.random` and `random.choice` for one call and fails the capture if any draw is missing, extra or
  out of range), so each branch and boundary is pinned without any seed;
- the pickup's life, removal, hitstop, pause and slow-motion behaviour from `Game.update` (3,200 ticks, seven scripts);
- the expiry blink from `Game.draw_pickup`, by looking at the pixels it draws on cleared surfaces;
- the swap from `Game.swap` (called directly and through the real key handler `Game.handle` with synthetic `KEYDOWN` events);
- the pickup card's six lines from `Game.draw_pickup_card` itself, recorded through a stand-in font.

Building a `Game` synthesises its sounds and takes seconds, so one is built and put back to its start by the prototype's own
`Game.reset` for each case. Every case's fixture is in the JSON; the swords of a swap case are parked (auto-attack cooldown
99 s) so no enemy, hit or Converge is involved (`fixture_scope`). The JSON holds 36 swords, 36 swaps, 7 pickup-life scripts,
174 + 12 arming probes, 23 blink samples, 4 swapped-in flight traces of 150 ticks and 10 chained swaps.

**Rolls in the arming probes are rounded to nine places** before they are fed to the prototype and written down: Godot's JSON
parser is only good to about 1e-15, so a roll sitting exactly on a threshold (e.g. 0.12000000000000001) would not survive the
round trip. What the prototype does with the rounded value is what is recorded.

## Tolerances

As in the earlier slices: position ±0.05 px, velocity ±0.5 px/s, timers / cooldowns / flash / recharge ±0.002, angles
±0.002 rad. Stats are rounded to four places in the reference (±0.0006). Pickup life is compared to ±0.002 per tick and its
removal tick must be exact. In practice the swapped-in sword's 150-tick flights agree within 0.0007 px, 0.0016 px/s and 0.00005 rad.

## Reference values and the checks asserting them

All in `godot/tests/drops_swaps_checks.gd` (group `drops_swaps`), run through the real `GameRun`, `GameCommand`,
`InputTranslator` and `Main` scene.

### The tables (`RARITIES` 118–122; `ELEMENTS` 109–113; `SWORD_TYPES` 79–103; `DROP_WEIGHTS` 104; `ENEMY_TYPES[..]["armed"]` 125–128)

| | Common | Rare | Mythic |
|---|---|---|---|
| damage x | 1.0 | 1.3 | 1.75 |
| cooldown x | 1.0 | 0.87 | 0.74 |
| range x | 1.0 | 1.06 | 1.12 |
| size x | 1.0 | 1.08 | 1.18 |
| colour (RGB) | 205 205 215 | 90 175 255 | 255 196 60 |

Element adjectives: fire "Ember", ice "Frost", poison "Venom" (a sword is named "Rare Ember Fang"). Armed chances: husk 0.20,
runner 0.12, spitter 0.22, brute 0.75. Drop weights Fang 3, Warden 3, Pike 2.5, Colossus 1.6 (total 10.1). Armed health 1.35x
(`Enemy.__init__`), checked for every kind at waves 1, 2 and 5. A pickup lives 45 s and is claimed from strictly less than 80 px.
Checks: `_check_definitions`, `_check_matrix` (all 36 type x rarity x element swords: name, damage, cooldown, range, ultimate
recharge, size, length, element colour and the six card lines; plus Common < Rare < Mythic for every type).

### Arming (`Game.start_wave` 1451–1460)

For each enemy of a wave, in order: `(wave == 1 and j < 2) or random() < chance(kind)`; the type is a Pike for wave 1's first
enemy, else `weighted(DROP_WEIGHTS)` (walk the list taking each weight off the draw; `<= 0` takes it); the rarity is Mythic below
`min(0.25, 0.02 + 0.02 w) + bonus x 0.5`, Rare below `min(0.55, 0.16 + 0.04 w) + bonus`, else Common, with `bonus = 0.15` for a
brute; the element is `random.choice` of fire, ice, poison. `LootDefs.armed_from_draws` is that function of its draws and the
reference pins it with 186 scripted probes (every kind's chance at, just under and just over; every weight edge exactly and +/-0.001;
all three elements; every wave 1–12's two rarity thresholds at, below and above, for a husk and a brute; the guarantees of wave 1's
first four enemies with a roll of 0 and of 0.99, and their absence for wave 2's first two). `LootDefs.roll_armed` makes the same draws from the
run's gameplay stream and only the draws the prototype makes. Checks: `_check_arming`, `_check_armed_waves`.

**Scope (wave generation is issue #18).** The prototype arms inside `start_wave`, which also decides the wave's composition and
size; those are #18. This slice ports the arming **rule and data** and a switch, `RunScenario.arm_waves`, that rolls every enemy of
the wave the director builds. The switch is **off by default**, so the normal run and every earlier fixture start their waves
unarmed and draw nothing from the gameplay stream (asserted: the generator state is identical before and after the wave start). The
drops encounter turns it on; #18 turns it on for the normal run together with the prototype's wave composition. `WaveDirector.queue_armed`
carries each queued enemy's sword through the spawn telegraph (`SpawnMarker.armed`) to the enemy (`EnemyState.armed`).

### Drops (`Game.kill` 1290–1296)

The sword an armed enemy carries lies at its position with 45 s of life, once, whichever way it died (a blow, damage over time,
a wall slam, bowling, a direct kill, two at once). `kill` resolves each enemy once, so a second blow on a corpse drops nothing. 16
reference kills (4 enemy kinds x 4 swords), the unarmed case and two simultaneous deaths in order; the four causes of death; and a
real fight (a Fang kills an armed husk). A drop produces one `SWORD_DROPPED` cue naming the sword. Checks: `_check_death_drops`,
`_check_cues`.

### A pickup's life (`Game.update` 1612–1615)

`pk.t += dt; pk.life -= dt`, then only `life > 0` remains, after the motes and on gameplay time: frozen by pause and hitstop,
slowed by slow motion (including the death's), running on while the player is dead. Seven scripts: plain (removed on tick 2701:
45 s of 1/60 steps accumulate a hair above zero), a 0.5 s hitstop at tick 100 (2732), a 1.4 s x0.25 slow motion at tick 200 (2764),
a pause over ticks 50–110 (2761), a 1 s life (60), a life of one tick (1) and a death at tick 30 (2769). The per-tick lives of the
first 420 ticks and every removal tick match. In its last six seconds a drop is hidden on every other eighth of a second
(`int(life x 8)` even; 23 reference samples from the real drawing function). Checks: `_check_life`, `_check_blink`.

### Reach and choosing (`Game.swap` 1417–1422)

A swap claims the nearest drop **strictly** within 80 px of the player (`(pk.pos - p.pos).length() < 80`); of equal distances the
first in the arena's order wins (Python's `min`). Reference: 21 single-pickup cases (0, 40, 79.95, 80.0, 80.05, 120 and 400 px in
three directions: claimed only below 80), nine multi-pickup layouts (nearest of three, ties in both orders and a three-way tie, a far
one ignored, all out of reach, two on the player, a diagonal at 79.9 and 80.2 px), a slot that holds no sword, and no pickup at all.
Checks: `_check_reach`.

### The swap (`Game.swap` 1417–1440)

The slot gets `Sword(pk.kind, pk.rarity, pk.element, pk.pos)` with `cd = 0.4`, `z = 10`, `flash = 1`, `vel = (0, -200)`, and
`ult_cd = new.ult_max x old.ult_cd / old.ult_max`: **the slot keeps its ultimate's recharge fraction**, so the same fraction of a
different (rarity-scaled) recharge is left, a ready ultimate stays ready, a just-used one stays just used, and a running ultimate
hands its fraction on and ends. The claimed pickup is removed and the old sword is appended as a pickup at
`pk.pos + (uniform(-20, 20), 24)` with 45 s of life. 36 swaps (every type, rarity and element, into every slot, with recharge
fractions 0, 0.37 and 1) match field for field; ten chained swaps match step for step, a recharge running between them; the swapped-in
sword's flight (a Fang, Warden, Pike and Colossus for 150 ticks) matches tick by tick. The offset of the returned drop is random: over
400 swaps it is exactly 24 px down and within 20 px sideways, spread across the range. Checks: `_check_swaps`, `_check_returned_drops`,
`_check_repeated`, `_check_trace`, `_check_shared_definitions`.

### Keys, pause, death, restart (`Game.handle` 1538–1544; `Game.reset`)

Keys 1, 2, 3 are slots 0, 1, 2 (a held key does not repeat). Paused or dead the key does nothing (the prototype's key handler
returns early; no refusal either). Restart (the button, the R key after the death screen, a scenario switch) clears every drop and
all counters. Checks: `_check_rules`.

## What the port adds, and how it is shared

- **Definitions are data.** `LootDefs` (constants and the arming function), `SwordDefs` (`RARITY_*`, names, colours, blurbs,
  `damage_of`/`cooldown_of`/`range_of`/`length_of`/`ultimate_recharge_of`) and `SwordSpec` (an immutable type/rarity/element) are
  read-only; `SwordState.equip` computes a sword's own numbers from them and writes only to itself, and a pickup holds the same
  `SwordSpec` the sword was built from. Checked after 36 swaps (tables unchanged; a Mythic Fang built between two Common ones
  leaves them equal).
- **Gameplay and cosmetic randomness are separate.** The returned drop's offset and the arming rolls draw from the run's gameplay
  stream; a drop's bobbing phase (the prototype's random `Pickup.t`), its sparks and the swap's effects never touch it (the layer has
  its own generator; the phase comes from the pickup's serial). A pickup's `serial` is its own counter, so a drop never shifts the
  serial an enemy spawns with.
- **Presentation.** `PickupState`s are drawn by the same replaceable sword scene as the equipped swords (`SwordVisual.apply_hover`),
  hanging point-down above a shadow; the ground ring, pillar of light (Rare and Mythic) and glows are `EffectsLayer`'s
  (`pickup_ring`, `pickup_beam`, `pickup_glow_rarity`, `pickup_glow_element`). Equipped swords are as much larger as the rarity's size
  factor with a glow in the rarity's colour (the element's for a Common one) that flares after a swap (`apply_flash`); an armed enemy
  draws its sword beside it (`EnemyVisual.apply_armed`). The HUD's pickup card is `PickupCard` (the prototype's six lines plus, new,
  a comparison with each equipped sword), placed beside the drop and clamped inside the view above the slot cards; each slot card
  gains a rarity tag, a border in the rarity's colour and a "key N swaps this sword" line. A new baked sound, `sfx_chime`, stands in
  for the prototype's chime.
- **Dev encounter.** `drops` (`RunScenario.drops_encounter`; the dev button / `C` after the colossus encounter, `--encounter=drops`,
  `?encounter=drops`): twelve armed foes ringed 520 px around the player (all four enemy kinds, all four sword types, four of each
  rarity, elements in rotation) walk in, followed by a ten-enemy wave armed by the prototype's rule, against Fang / Warden / Colossus
  with poison / ice / fire (explicit; the final default is issue #16). The cycle is now normal, crowd, spitters, conditions, warden,
  pike, colossus, drops.

## Deliberate exceptions

1. **A refused swap with nothing in reach is visible.** The prototype's `swap` returns silently. Here the sword slots and drops are
   unchanged exactly as there (asserted), but `SWAP_REFUSED` makes the layer print "no sword within reach" (the slot of a missing
   sword and a paused or dead run stay silent). The standing request for the Web evidence ("show refusal when no pickup") is why.
2. **No pickup phase randomisation in the simulation.** `Pickup.t` starts at `uniform(0, 5)` in the prototype and only drives the bob
   in drawing; here `age` starts at zero and the visual derives its phase from the pickup's serial.
3. **A swap by the touch action path while dead** is not offered: the prototype's key handler ignores 1/2/3 while dead and its touch
   action path (`name == "swap"`) is only paused-checked; the port refuses both (the touch buttons are issue #20).
4. **A new `Sword`'s random starting cooldown is not drawn**: the swap overwrites it with 0.4 in the prototype, so the port builds the
   sword with 0.4 directly (the prototype's draw consumed random state that no rule reads).
5. **Armed enemies are only in the drops encounter**, see *Scope* above.
6. **The pickup sword's hover is the prototype's** (0.6 blade lengths plus 3 px of bob) but the point-down pose, the shadow and the
   sway are the placeholder visual's own; exact pixels are not a gate (spec decision 12).
7. **Colossus's start height after a swap** is `z = 10` as in the prototype; other types keep no height in the simulation.

## Validation

See the pull request for the counts and builds: `./build-godot.sh --checks-only`, a clean `./build-godot.sh`, the section
`SECTIONS=drops` of `tools/godot/mutation-check.sh` (fast mode) and the full fast pass, every capture script byte-identical twice,
the Web export driven by browser key events in headless Chromium, and the shipped Windows build under Wine.

## What was not verified

- Real-Windows input and real-device touch (issues #6, #22 and #20, by standing ruling).
- Swapping with the touch buttons (issue #20) and the final default loadout (issue #16).
- Multi-wave arming in a normal run (issue #18); the rolls themselves are pinned, but no normal run uses them yet.
