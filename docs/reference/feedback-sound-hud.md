# Reference: combat feedback, sound and the desktop HUD

Slice #19 of the Godot port ([spec #4](https://github.com/theozex4ever/Swordster/issues/4)), following
[waves and the normal run](waves.md) and the slices before it. The Python prototype `game/main.py` is the behavioural oracle: its
sound table (`synth`, `SOUND_DEFS`, ~255-345), where each sound plays, the HUD draw code (`draw_hud`, ~1990-2180), the effects
(`hit_enemy`, `kill`, `slam`, `hurt_player`, `Particle`, `draw_trail`, decals) and the key handling (`Game.handle`, ~1538).
Pixel parity is not a goal; what is preserved is gameplay timing (hitstop, slow motion, camera shake and kick are the simulation's,
unchanged) and what each cue tells the player.

## Inventory: what the Godot side already had, and what this slice added

| Prototype | Before #19 | #19 |
| --- | --- | --- |
| health bar with a white "recent damage" bar, health number | yes | checked against real hits |
| wave, kills | yes | checked in a real first wave |
| big top-right `x{combo}` that fades toward grey with `combo_t / 2.6`, its bar | only `chain N` in the wave line | restored (`Hud._show_chain`); the wave line no longer carries the chain |
| game-over line `wave / kills / best chain` | yes | checked after a real death |
| dash bar, Converge bar | text only for dash | dash bar added |
| slot cards: rarity, element, ultimate name, recharge, **normal attack recharge bar** | all but the attack bar | attack bar added to each card |
| help overlay (H, 14 s, fades in the last second) | none | `GameRun.help_left`, `GameCommand.toggle_help`, `Hud._show_help` |
| pause, death, delayed restart, R as ultimate and restart | yes | re-checked through the real input path |
| hit sparks in the sword's colour, sized by damage; number sizes by damage, drifting with the blow | white ring and a fixed number | sparks, ring, sizes, drift (`EffectsLayer._apply_hit`) |
| kill dots + falling debris in the enemy's colour, ring | one ring | dots, debris, ring (`_apply_kill`; 14 dots more for a heavy blow) |
| smoke for dash, spawn, wall slam, slam; slam debris | none | `_bits` (kind `smoke`, `debris`, `dot`) |
| red sparks when the player is hit | none | `_spray` |
| sword ribbons (`draw_trail`) | afterimages in ultimates only | a ribbon per sword, nine points, brighter with speed |
| Colossus floor cracks (decals, 7 s) | none | `GroundMarks`, drawn under the actors |
| dark vignette, red hurt flash (2.5/s), red pulse below 30 % health | none | `ScreenFeedback` |
| the fourteen sounds | nine stand-ins with different names and shapes | the prototype's synthesizer, baked |

Left as they were: shake and kick (`GameRun.trauma`, `kick`), hitstop and slow motion, rings, range rings, telegraphs, conditions'
particles, the pickup card, banners, spawn warnings.

## The sounds

`tools/godot/gen_audio.py` ports `synth` and `SOUND_DEFS` line for line. The prototype synthesizes with Python's global random stream
at run time; the port gives each sound a stream of its own (`random.Random(index + 1)`), so the result is reproducible. Each file is the
prototype's samples times its volume, mono 16-bit at 22050 Hz (the rate the prototype renders at under a 44.1 kHz mixer). The four
interface sounds the port added (`unlock`, `pause`, `resume`, `restart`) come from the same file and are byte-for-byte unchanged.

```sh
python3 -I tools/godot/gen_audio.py            # rewrites godot/audio/*.wav
python3 -I tools/godot/check_audio_recipe.py   # runs it twice, requires identical bytes and equality with the committed files
```

`build-godot.sh` runs the second command before the headless checks (exit 15 on a mismatch). Python is needed only to regenerate;
nothing at play time synthesizes.

| sound | played when (prototype line) | cue here |
| --- | --- | --- |
| `tick` | Fang's normal blow (`sword.t["sound"]`), each Viper Flurry dart (873) | `ENEMY_HIT` of a Fang (a heavy one is a dart) |
| `slash` | Warden's blow, each Maelstrom beat that struck, its burst (922, 938) | `ENEMY_HIT` of a Warden; `MAELSTROM_BEAT` with `amount > 0`; `MAELSTROM_BURST` |
| `pierce` | Pike's blow, a Skewer's launch (950) | `ENEMY_HIT` of a Pike; `SKEWER_LAUNCHED` |
| `boom` | Colossus's blow and every slam (1311) | `ENEMY_HIT` of a Colossus; `COLOSSUS_SLAM` |
| `thud` | every `hit_enemy`, a wall slam (1154, 1349) | `ENEMY_HIT`, `WALL_SLAM` |
| `whoosh` | a Fang, Warden or Pike starts its attack; a Maelstrom begins (847, 1015-1024) | `SWORD_STRIKE`; `ULTIMATE_STARTED` of a Warden |
| `heave` | a Colossus starts its slam; a Skewer's aim and a Cataclysm's rise begin (852, 856, 1029) | `SWORD_STRIKE` of a Colossus; `ULTIMATE_STARTED` of a Pike or Colossus |
| `hurt` | the player is hit (1376) | `PLAYER_HURT` |
| `pop` | a kill (1289) | `ENEMY_KILLED` |
| `chime` | Converge, a swap (1398, 1438) | `CONVERGE`, `SWORD_SWAPPED` |
| `dash` | the player's dash, a Viper Flurry's blink (478, 841) | `DASH`; `ULTIMATE_STARTED` of a Fang |
| `gong` | a wave starts (1464) | `WAVE_STARTED` |
| `parry` | a parried orb, a freeze (1184, 1362) | `PROJECTILE_PARRIED`, `ENEMY_FROZEN` |
| `shot` | a spitter fires (544) | `PROJECTILE_FIRED` |

`SimCue` gained `spec` (on `ENEMY_HIT`, `SWORD_STRIKE`, `ULTIMATE_STARTED`), `heavy` (on `ENEMY_HIT`) and `enemy_kind` (on
`ENEMY_KILLED`, whose `critical` now means a heavy or critical blow, as `kill(..., big)`); cues are never read back by the simulation.
As in the prototype, one sound is not restarted within 40 ms of itself; instances of different sounds, and of one sound after the
gap, overlap (up to four each, `AudioStreamPlayer.max_polyphony`; the prototype has 24 channels).

Deliberate differences: a Skewer's release is silent (the prototype plays nothing there; a wall slam has its own `thud`); the older
slices' stand-ins `hit`, `strike`, `kill` and `wave` are gone.

### Web audio: what was verified

Browsers keep audio locked until a user gesture. `Main._input` unlocks on the first key press, mouse press or touch press (releases,
motion and the engine's emulated mouse are not gestures); until then every sound is dropped and the HUD asks for a click or tap.
`tools/godot/web-feedback-capture.mjs` plays the exported build in headless Chromium (browser key and mouse events only) with
`--autoplay-policy=user-gesture-required` and wraps `AudioContext` / `AudioBufferSourceNode.start` before the page loads. It also
records the first trusted user gesture (a press or key down; moves and releases are not gestures) with the event's own timestamp on the
page clock, the same clock every sound start is stamped on; the report is
[web-audio-report.json](feedback-sound-hud/web-audio-report.json). Sound starts are counted against that timestamp
(`startedBeforeFirstGesture`, `startedAfterFirstGesture`); the earlier `startedBeforeFirstClick` counted AudioContexts that were not
running, which says nothing about when sounds started, and is gone (`startsWhileContextNotRunning` keeps that number, apart, under its
true name). Result for build 20261116-134623-e327803b3 (regenerated for #49; the screenshots in this folder are from the original
#19 build 20261116-124501-e46522905): the first gesture was a `pointerdown` at 5087 ms on the page clock; **0 sounds started before
it, 361 after it** (6 within the following second, the unlock chirp and the Converge's chime among them, the first 42.6 ms after the
gesture), no console errors; the context reports a base latency of 10.7 ms and an output latency of 48 ms at 48 kHz, and the first
start is stamped on the context's own clock right after the click. The earlier run's counts (509 over the whole run, 0 before the
click) came from the old metric and a different fight; the totals vary with how the fight goes. Honest limits: headless
Chromium's context was already `running` before the click (the autoplay flag did not suspend it), so the browser's
suspended-to-running transition itself is not shown (`startsWhileContextNotRunning` is 0 for that reason, and proves nothing); what
is shown is that the game's own gate keeps every sound silent until the first gesture and plays afterwards. Nor can headless prove that
anything is audible (the output is muted) or how the latency feels on a device; real-device sound is deferred to #6 and #22.

## The HUD

- **Chain counter**: from the third kill in a row `x{chain}` at font size 56 at the top right, under the Pause / Restart / Dev buttons
  (the prototype had no buttons there), going from (90, 80, 110) toward (255, 210, 110) as `combo_left / 2.6`, with a 100 px bar that
  shrinks with it. The colour for x5 with 1.3 s left is the prototype's captured (172, 145, 110).
- **Help**: the prototype's seven lines, shown from the start for 14 s of gameplay time, fading over the last second at 86 % alpha;
  H hides it, or shows it until hidden. H does nothing while paused or dead. It gives way while the wave banner or a dropped sword's card is
  up (each would sit on it), and a restart brings it back.
- **Cooldowns**: each card gains a bar for the sword's own attack recharge (`1 - cooldown_left / cooldown`) under the ultimate's; the
  dash gets a bar like Converge's. Cards are 108 px tall (were 98); the pickup card's clearance machinery sees every new element.
- **Banner then card** (the carried-forward review item): `show_run` updates the banner labels before it places the pickup card, so the
  first update after a banner appears already keeps the card off both lines.
- **Screen feedback**: dark vignette, a red flash of up to 0.78 alpha on a hit fading at 2.5 per second of ticks, and a slow red pulse
  while health is below 30 %.

Layout: the cooldown bars sit under their labels (y 146), the encounter legend moved from y 146 to 158 and the help block starts at 248,
so nothing overlaps at 1280x720, 1084x720, 1000x563, 1920x1080, 800x1280 and 1280x1024.

## Effects

All drawn from `EffectsLayer`'s own random stream; their density may vary and never touches the run. Constants are the prototype's:
hit sparks `clamp(4 + 0.35 dmg, 4, 26)` along the blow (speed 200-650, 250-900 when heavy) in the sword's colour mixed 0.4 toward white;
numbers 22 / 32 / 40 by damage (under 12 / 35), +10 for a critical (cap 56), drifting `d.x * 60` and rising `90 + dmg`; a kill throws 16
dots (+14 when heavy) and `6 + r / 3` pieces of debris under gravity 1400 with a 0.35 bounce, and rings `r` to `3.2 r`; a hit on the
player throws 14 red sparks; a dash, a spawn and a wall slam leave smoke; a slam leaves 26 puffs, 18 stones and 5-8 cracks that last 7 s
(the first second glowing); each sword keeps nine points of ribbon. Differences: everything is drawn with ordinary alpha blending (the
prototype adds light), the layer keeps at most 500 bits at every instant (the prototype 700; the cap is applied as each bit is inserted, evicting the oldest, so a burst of 95 heavy kills never holds more than 500) and ribbons use the sword's element colour.

## Checks

`godot/tests/feedback_hud_checks.gd` (group `feedback_hud`): the baked files against the prototype's durations, volumes and format; every
row of the sound table through the real `SfxBank`; a real run's sounds; audio unlock by key, click, right click and touch (and not by a
release); help, chain counter, cooldown bars, health and counters through real runs; every key and mouse alias; pause, death and the
delayed restart; the banner-then-card transition at six window sizes; pairwise layout at six window sizes; the hurt flash; impact
particles; ribbons and cracks; and a 2400-tick normal run through the real Main scene against the bare simulation (hitstop and slow-motion
timeline, final digest); the particle ceiling right after 95 simultaneous heavy kill bursts (4,180 bits offered, 500 kept, no update in
between); and the same run with feedback off, normal and dense (the effects layer flooded every third tick) ending in one simulation
digest. Every wait loop is bounded by a counter that does not depend on the tick. Mutations: the `feedback` section of
`tools/godot/mutation-check.sh`.

Export evidence ([screenshots](feedback-sound-hud/)): the Web build in headless Chromium (help after the first click and hidden with H,
a fight with the chain counter and hit numbers, WAVE CLEARED over a Cataclysm's floor, pause, the death screen, the restart, and the
`--visuals=textured` look), and the shipped, unmodified Windows build under Wine 11 on an isolated Xvfb display, `Swordster.exe
--resolution 1000x563 --write-movie ... --fixed-fps 30`, no input: a 90 s movie (the engine recorded it at its own 1280x720) whose frames
show the help, the chain, hit numbers, floor cracks and drops, and the audio prompt a player who never clicks keeps seeing.
