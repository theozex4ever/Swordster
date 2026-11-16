# Reference: replacing the actor and sword visuals (issue #21)

Slice #21 of the Godot port ([spec #4](https://github.com/theozex4ever/Swordster/issues/4)), on the replaceable
visual boundary of [ADR 0003](../adr/0003-separate-combat-from-visuals.md). Artist procedure:
[replacing-visuals.md](../art/replacing-visuals.md). There is no Python prototype reference for this slice: the oracle is
the Godot simulation itself, played with the default look.

## What was built

- A **visual set** (`VisualSets`) names the actor, sword and enemy scenes a run is drawn with. `placeholder` is the default
  and the shipped look; `textured` draws the player and every spirit sword from texture sheets (original placeholder
  drawings in `godot/art/placeholder/`, produced by `tools/godot/gen_placeholder_art.gd`). Chosen with `--visuals=textured`
  (Windows / editor user argument) or `?visuals=textured` (Web); anything else keeps the default. The enemies keep their drawn look.
- Scale, pivot, orientation, the sheet layout and the animation mapping (phase / cue to clip) live in two settings resources
  (`actor_settings.tres`, `sword_settings.tres`), not in scripts. The placeholder art deliberately differs from the drawn look:
  sheets of 64x80 (player) and 96x96, 160x128, 112x176, 256x208 (four sword sheets), pivots that are not frame centres
  (player body, sword guard), art that points down (player, -90) or up (swords, 90), scales 0.5 to 0.9.
- Cues reaching the picture: logical position, facing, moving, invulnerable blink, dead; sword type (sheet), element (tint),
  rarity (size factor and glow colour, the element's for Common), attack phase (clip, brightening on a strike), idle / attack
  lift, hover for a lying drop, a Colossus's altitude and shadow, the swap flash.
- No animation callback can reach the run: a clip that runs out only emits `clip_finished`, which nothing in gameplay connects to.

## How the checks prove it (`visual_replacement_checks.gd`, group `visual_replacement`)

| Claim | Check |
| --- | --- |
| Same movement, hit geometry, damage, timing, cooldowns, targets | Four scripted fights (spitters, Converge default loadout, drops with every type / rarity / element, Colossus) are played by the bare `GameRun`, by Main with the drawn look and by Main with the textured look. Every tick the snapshot, each sword's phase / timers / cooldown / heading / target, each sword's raw hit geometry (length, attack range, size factor, the Warden's sweep pivot / arc / duration / side, the slam's impact point, the ultimate's point, altitude, aim), each enemy's pose, health and radius, and every cue (position, direction, amount, radius, element, sword) are folded into a SHA-256; the three hashes and the final outcome digests must be equal. |
| Art size, pivot, orientation, animation speed and length are irrelevant | Converge and drops again with (a) all animations a tenth of the speed, (b) all animations sixty times faster and each playing once (hundreds of `clip_finished` callbacks; the variants are uncapped and a check proves every clip rate is exactly the original's times 0.1 or times 60, so an 8 fps clip really plays at 480 fps), (c) other textures (1500x900, five frames), pivots moved 240 px, art 7x bigger and turned 33 degrees: identical hashes and digests, and the replacement is shown to have really drawn differently. |
| The replacement is actually drawn | Every tick of every textured fight and hostile variant, the textured actor and each equipped sword are visible in the tree and each of their sprites (actor body and shadow; sword blade, glow and shadow) has a texture with a non-empty frame, an effective opacity above nil (its `self_modulate`, its `modulate` and every ancestor's `modulate`), a non-nil global scale, a draw order above the arena floor (effective z index, then tree order, on the floor's canvas layer; the sword also over the ground marks) and its own origin where the simulation puts it (within the height it is lifted to). Every lying sword, every tick, is drawn exactly when the simulation's blink says it is not in the hidden half of its expiry blink, in every hostile variant too; the drops fight must show well over a hundred such sword-ticks. The same holds for the 36 sword combinations and the actor in the cue checks. |
| The simulation is blind to visuals | No `res://scripts/sim` script names a visual, sprite, texture, presenter, animation or clip callback. |
| Cues reach the picture | 36 sword combinations (4 types x 3 elements x 3 rarities), phases, lift, hover, altitude, flash, actor facing / moving / blink / dead, clip looping and finishing. |
| Selection | Default look, unknown names, case, launch-option parsing, every scene loads, Main swaps all three views on `visuals`, a restart frees and redraws. |

110 mutations in `tools/godot/mutation-check.sh` (section `Visual replacement (slice #21)`) break each of these, including two in which a
presentation callback reaches into the run (a sword's clip end refunds a cooldown; the actor visual heals the run, moves it):
all caught by the equivalence hashes. Others nudge a sword's length, reach or an active Warden sweep, or an enemy's radius, from a
callback (caught by the hit-geometry fields of the hash). Others make a picture present but not drawn: the actor, a sword, its
blade, glow or shadow hidden, emptied, transparent (`modulate` or `self_modulate`), scaled to nothing, drawn under the floor or placed 4000 px away;
and lying swords that are hidden for every odd serial, shown only for their first 0.1 s, or hidden only when the art is slow
(caught by the on-screen and per-sword blink checks).

## Exported evidence

Build `20261116-121720-7af5ed338` (2068 checks). Web in headless Chromium (software WebGL, browser events only), page address
`index.html?encounter=drops&visuals=textured` and `?visuals=textured` for the default loadout; Windows: the shipped, unmodified
ZIP (SHA256SUMS verified) under Wine 11 on an isolated Xvfb display, `Swordster.exe --resolution 1000x563 --write-movie ... --fixed-fps 10
-- --visuals=textured --encounter=drops`, engine frames, no input, no desktop capture.

| What | Screenshot |
| --- | --- |
| Alignment: the player's body sits on the centre of the Tab attack-range circles; three swords of the default loadout (Fang poison, Warden ice, Colossus fire) turn about their guards | [web-textured-ranges-alignment.png](visual-replacement/web-textured-ranges-alignment.png) |
| Phase cues and ultimates: Maelstrom ACTIVE (ice), Cataclysm field, lifted Colossus | [web-textured-ultimates.png](visual-replacement/web-textured-ultimates.png) |
| Element and rarity: swords of every type lying and carried, gold Mythic and blue Rare glows, fire / ice / poison tints | [web-textured-drops-element-rarity.png](visual-replacement/web-textured-drops-element-rarity.png) |
| After swaps into all slots, a Mythic card | [web-textured-swap-mythic-card.png](visual-replacement/web-textured-swap-mythic-card.png) |
| Shipped Windows build under Wine | [wine-shipped-textured-mythic-card.png](visual-replacement/wine-shipped-textured-mythic-card.png), [wine-shipped-textured-drops.png](visual-replacement/wine-shipped-textured-drops.png) |

**What this does not show:** input in a Windows build (that belongs to the deferred device matrix, #6 / #22); final art (these are
placeholders); the Wine run has no player input, so the player stands still. Existing reference captures and screenshots are untouched.

## Deliberate limits

- The enemies and the effects layer (slash arcs, sparks, fields) keep their drawn look in the `textured` set: only the actor and sword views are replaced, as the issue asks.
- A launch option read from the Web page address or the command line is not exercised by the headless checks (they have neither); the parser (`LaunchOptions.visuals_from`) is, and the exports above exercise the rest.
