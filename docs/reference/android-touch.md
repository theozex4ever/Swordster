# Reference: Android touch controls

Slice #20 of the Godot port ([spec #4](https://github.com/theozex4ever/Swordster/issues/4), user stories 50-55 and the shared-input
decision). The Python prototype was desktop-only, so there is no reference capture: the rules below are the issue's, and every one
is asserted by `godot/tests/touch_controls_checks.gd` and attacked by the `touch` section of `tools/godot/mutation-check.sh`.
Vocabulary follows `GLOSSARY.md`. **Physical Android checks are not done here**: they belong to the device matrix (#6 / #22);
the last section is the exact list that remains.

## What a player gets

| Control | Does | Shared command |
|---|---|---|
| Left of the screen (floating joystick) | steers | `move_axis` |
| Tap anywhere on the arena | **Converge** at the tapped world point | `converge(point)` |
| **Converge** button | Converge at the nearest living enemy, else 300 px ahead of the player | `converge_at_nearest()` |
| **Q / E / R** buttons (READY, ACTIVE or seconds left) | the slot's **ultimate**, same aiming as the Converge button | `ultimate_at_nearest(slot)` |
| **Swap 1-3** (lit when a **sword drop** is within reach) | **swap** the nearest drop into that **sword slot** | `swap(slot)` |
| **Ranges** | show / hide the attack-range rings | `toggle_ranges()` |
| **Full** (only where the browser offers fullscreen) | asks the platform when the finger lifts on it (the browser grants a fullscreen request on a lift, not a landing); not a gameplay command | - |
| **Dash**, **Pause / Resume**, **Restart** (the HUD's own) | as on desktop | `dash()`, `toggle_pause()`, `restart()` |
| large **Resume** (paused) / **Restart** (run over) | explicit, hard to miss | `resume()`, `restart()` |

No touch-only gameplay path exists: the buttons emit the same `GameCommand`s the keys and the mouse produce, and the run refuses
them under the same rules (paused, dead, cooling down, no sword, nothing in reach).

## How a finger is handled (`TouchPointers`)

Every finger (touch index) is a **contact** with exactly one owner for its whole life, chosen when it lands:

```text
land(index, p)
  if p is inside a visible button's rectangle      -> UI        (the button's own press acts; nothing else may)
  elif the joystick is free and p is in its zone   -> JOYSTICK  (steers; commands nothing yet)
  else                                             -> ARENA     (Converge at the tapped world point, at once)
lift(index)
  JOYSTICK finger that lifts within 0.3 s having moved at most 18 px -> also a tap: Converge where it landed
  cancelled contact -> never a tap, always released
release_all()  (focus loss, suspension, restart)  -> forget every finger; their later drags / lifts change nothing
```

- Buttons act on the finger **landing** (`button_down`), like the prototype's pointerdown and the HUD's buttons, and Godot delivers
  each finger to them independently, so one thumb can steer while others press (checked through the engine's own touch-to-mouse
  emulation too: an arena tap is one Converge, not two).
- The rectangles that swallow a landing finger (`Hud.button_rects` and `TouchControls.blocked_rects`) include only buttons that are
  showing: the Shove button outside the crowd encounter, or Resume while the run goes on, block nothing. A check walks every visible
  `Button` in the scene and requires a blocked rectangle around it.
- The Resume and Restart buttons hide themselves from inside their own press; the engine then ignores their *next* press, so a held
  button stays up until its finger lifts (found by the checks, see "Found while building").
- The mouse is unchanged: a left or right click is a Converge at the cursor; a mouse click the engine makes up from a touch is not
  (touch has its own path above).

## Layout (`TouchLayout`, pure geometry)

```text
top right    [Full][Ranges]        under the HUD's Pause / Restart / Dev buttons
left of mid  [Resume] / [Restart]  one at a time
bottom right        [Swap 1][Swap 2][Swap 3]
                    [  Q  ][  E  ][  R  ]   [Converge]
                                             [ Dash ]  (the HUD's own button is the anchor)
```

- Landscape keeps the game's 1280 x 720 base; a window **taller than wide** uses a 740 x 1280 base (touch play only), so the
  controls are as large upright as sideways (about 0.55 css px per logical px on a 412 px phone either way). Desktop windows keep
  the project's own base. Square windows count as landscape.
- In a narrow (portrait) view the bottom rows rise above the HUD's three sword cards, and a "Turn your phone sideways for a wider view" hint
  shows. The 740 px width (not 720) is what lets the HUD's own Dash button clear the third card; a check asserts no overlap at every window shape.
- Safe area: touch buttons stay inside the insets (the Dash-anchored cluster is pulled in) and so does the joystick zone. Insets come
  from the browser's `env(safe-area-inset-*)` (probed through a hidden element, together with the page's width), from
  `DisplayServer.get_display_safe_area()` elsewhere, or from `?safe=top,right,bottom,left` / `-- --safe=...` as a stand-in **in the same
  CSS pixels, through the same conversion onto the viewport** (a check gives both paths the same numbers and requires the same answer:
  a 915 px page shown 1599 logical px wide turns 24,48,20,48 into left 83.88, top 41.94, right 83.88, bottom 34.95 either way). The HUD's own elements do not move for insets (Chrome keeps the page
  out of cutouts unless `viewport-fit=cover`, which the export's shell does not ask for).
- Touch UI sizes are at least 80 logical px a side, which is 44 css px on a phone held either way at 0.55 scale or better.
- The controls are shown when the platform reports a touchscreen, `?touch=1` / `-- --touch` asks, or the first finger lands;
  `?touch=0` hides them. They hide the HUD's keyboard hint line. A desktop start shows none of this (a check pins it).
- Launch options sit beside `?encounter=` and `?visuals=` (each read on its own from the same address; a check pins `--visuals=` still parses
  beside `--touch` and `--safe=`).

## Suspension

`Main._notification` already released input and paused on focus loss; a browser hook now also reports the page being hidden,
left (`pagehide`) or blurred (`window.__swordsterSuspend`, installed once). Both call `release_input_and_pause`, which clears every
finger, key and the stick, and pauses (idempotently). Nothing resumes by itself: the pause overlay and a large Resume button wait.

**Buttons the engine believes are pressed.** A finger on a button when the page is suspended, the touch cancelled or the run restarted never
reports its lift, and the engine's `Button` then believes itself pressed and swallows its next press (the run stayed paused with Resume doing
nothing). The engine's buttons ignore a *cancelled* touch, so `Main` gives each such finger a plain lift (`_lift_on_buttons`, landing off the
screen, with `TouchControls.quiet` set so the release-triggered Full button cannot act on it) before it forgets the finger, on suspend, on a
cancelled touch and on restart (deferred for restart: the finger is inside the engine's own press handling then). Held Resume / Restart
stay visible until that lift, because hiding a pressed button drops the hold only after the lift is delivered.

## Checks

`touch_controls_checks.gd` (registered in `run_checks.gd`, focus group `touch_controls`, the #35 focus guard; it has no render-rate
probe, as asked, so it needs no probe guard). All input is real `InputEventScreenTouch` / `InputEventScreenDrag` through the viewport
(and, for one group, through `Input.parse_input_event` with the engine's mouse emulation). Waiting loops are bounded by frame or tick
counters and fail when they run out.

| Group | Asserts |
|---|---|
| Pointer table | arena landing = Converge at the world point; a second / third / fifth finger independent; a finger on a button owns nothing else; tap thresholds (0.25 s and 18 px tap; 0.5 s, 19 px and back, cancelled do not); a stale press; `release_all` forgets fingers; unknown drags ignored |
| Geometry | 6 views x 4 safe areas: in the safe area, >= 80 px, no overlaps, Dash clear; the zone is the earlier 55 % / 15 % with no insets; portrait lift; Q E R order |
| Platform values | orientation base (square included), CSS-to-viewport insets, `?safe=` parsing, launch options beside `--visuals=` |
| Activation, desktop | no touch UI on a desktop start; hint stays; a tall desktop window keeps its base; the first finger brings the controls up and already counts as the tap; off again restores desktop |
| Views and aiming | 100+ taps at 10 window shapes (phones and tablets both ways, square) x 2 camera positions: the tap's world point is the camera plus the offset, clamped to 460 px, exactly one Converge, in the zone and outside it; the engine's own canvas transform agrees; a moved camera; portrait / landscape / square turned under a running scene |
| Buttons and aiming | three ultimates start at the nearest living enemy (a corpse is skipped), never at the button; refused while active; Converge button and cooldown text; Ranges; empty arena: 300 px ahead of a player facing west for ultimates and Converge; swaps (none in reach, claim, nearest drop); fullscreen asks the platform once and commands nothing; hidden when unsupported |
| Simultaneous | stick + Dash + ultimate with all three down; lifting the action fingers leaves the stick steering; a fourth finger on the arena; two buttons held at once |
| UI consumes | the centre and both corners of all 12 buttons never Converge, steer or leave a contact; the Converge button aims at the enemy exactly once; hidden buttons block nothing; every visible `Button` is inside a blocked rectangle; the card avoids the touch buttons |
| Engine emulation | through `Input.parse_input_event`: one Converge per arena tap, one dash per Dash tap, the Converge button once, a second finger reaching a button while the first steers |
| Release, suspension | cancel releases the stick and the player coasts to a stop; focus-out, window focus-out and app pause each pause, release stick, key and two fingers, ignore the old fingers, stay paused however long, need Resume (a landing on Resume that appeared after the stick's rectangles were set is the button's), then a *new* finger steers |
| Paused, dead | paused: taps, Converge, 3 ultimates, a swap, Ranges, Dash do nothing and spend no cooldown; dead: same; no Restart until the delay, then a big Restart that restarts and clears the stick |
| Bridge values | `bridge_truthy` / `bridge_text` over every shape the browser bridge can return (bool, int 1 / 0 / 2, float, text true / 1 / yes in any case, empty text, null, list, dictionary, vector); the probe's answer parses; a 915 px page shown 1599 px wide gives the same insets from the browser and from `?safe=` (83.88 / 41.94 / 83.88 / 34.95) |
| Fingers that never lift | hold Resume, suspend, press Resume again with the same and another finger: it resumes; the same for the HUD's Pause; for a cancelled touch; for a restart with another finger. Full asks nothing while the finger is down, once on the lift, nothing for a cancelled touch |
| Scene layout | 10 window shapes x 3 safe areas in the running scene: touch buttons in the safe area and clear of the HUD's buttons; the zone follows |

Mutations: the `touch` section of `tools/godot/mutation-check.sh` (74 mutations: tap and travel thresholds, ownership, UI consumption,
world mapping, stale and cancelled contacts, `release_all`, layout constants and insets, orientation, every button's command, slot and
aim, dimming, held Resume / Restart, first-touch activation, blocked rectangles, launch-option parsing, the bridge readings, the safe-area conversion, the lift given to buttons on suspend, cancel and restart). Mutations that could not change behaviour (the joystick already ignores a foreign finger's drag; `_held.clear()` is also done by the lift's `button_up`) were removed instead of excused.

## Found while building

- A button that hides in its own `button_down` (Resume / Restart) was ignored the next time it appeared (the check's second pass
  failed). Fixed: it stays up until its finger lifts.
- In the browser the layout silently never ran: `JavaScriptBridge.eval` returned a Variant that was not a `bool`, and the typed
  `layout(..., fullscreen_supported: bool)` call failed without a message in a release export (found from the first Chromium
  screenshots: every button stacked at the top left). **Round 1 of review then showed the first fix was wrong too**: it accepted only a
  GDScript `bool`, but in the pinned Web runtime `document.fullscreenEnabled === true` comes back as the number `1`, so the Full button
  stayed hidden. (My earlier note that headless Chromium lacks fullscreen support was wrong: `document.fullscreenEnabled` is `true`
  there.) Fixed: `TouchPlatform.bridge_truthy` accepts a bool, a non-zero number or the text true / 1 / yes, `bridge_text` reads text or
  numbers, a check covers each shape, and every other bridge read in the game goes through them. The Web run now shows the button and the
  request (below).
- A finger that never lifts left the engine's button pressed: see "Buttons the engine believes are pressed" above (review round 1).
  The reproduction (hold Resume, suspend, press Resume again) is now a check, in the scene and in the browser.
- `?safe=` was read as logical pixels while documented as CSS pixels (scale 1); it now takes the browser insets' conversion (review round 1).
- The pre-existing `Hud.button_rects()` blocked the hidden Shove button's place (it would have swallowed arena taps there).

## Evidence

Web export in headless Chromium (`tools/godot/web-touch-capture.mjs`, browser events only): `Emulation.setDeviceMetricsOverride` (mobile,
device scale factor 2), `Emulation.setTouchEmulationEnabled`, real `Input.dispatchTouchEvent` with several points at once, a dispatched
`visibilitychange`, a `touchCancel`, `Emulation.setSafeAreaInsetsOverride` (the page's `env()` read back as `24px,48px,20px,48px`) and an
observer on `Element.prototype.requestFullscreen`; build `20261116-143141-c774c39f5` (the head this document ships with). No console errors.
**Fullscreen:** `document.fullscreenEnabled` is `true` in this Chromium (an earlier version of this document said it was not: wrong; the
Full button was hidden by the bridge reading described above). The Full button is shown; the observer counts **0** requests while the finger
is down and **1** after the lift, the result is `["granted"]` and `document.fullscreenElement` is the canvas.

| What | Screenshot |
|---|---|
| Portrait phone (412 x 915) on first screen: no touch yet, the platform already reports one, so the controls are up | [web-01](android-touch/web-01-portrait-first-screen.png) |
| The same phone turned landscape (915 x 412) under the running game | [web-03](android-touch/web-03-landscape-after-turn.png) |
| Tap on the arena: `converge 2.2s`, swords striking at that point | [web-04](android-touch/web-04-landscape-tap-converge-at-point.png) |
| Converge button: `Converge 2.2s`, aimed at the nearest enemy | [web-05](android-touch/web-05-landscape-converge-button-nearest.png) |
| Stick held (ring), a second finger on Dash, a third on Q (Viper Flurry ACTIVE), all at once | [web-07](android-touch/web-07-landscape-stick-dash-ultimate-together.png) |
| Page hidden: PAUSED with the large Resume button | [web-09](android-touch/web-09-page-hidden-paused.png) |
| Back in the page, a tap on Resume resumes (Q now recharging) | [web-11](android-touch/web-11-resumed-by-tap.png) |
| A finger holds Resume (it resumed), the page is suspended again with that finger still down: PAUSED | [web-11c](android-touch/web-11c-suspended-with-finger-on-resume.png) |
| A second finger lands on Resume without the first one's lift ever arriving: the run resumes (the review's reproduction) | [web-11d](android-touch/web-11d-second-press-on-resume-works.png) |
| Touch cancelled mid-drag: no ring, no walking | [web-12](android-touch/web-12-touch-cancelled-stopped.png) |
| The **Full** button is shown (landscape) | [web-13](android-touch/web-13-landscape-full-button-shown.png) |
| After the tap on it (one granted `requestFullscreen`; headless keeps the viewport size) | [web-14](android-touch/web-14-landscape-after-full-tap.png) |
| Safe area 24 / 48 / 20 / 48 from the browser (CDP `env()`), and the same numbers as `?safe=24,48,20,48`: identical layouts | [web-15](android-touch/web-15-landscape-safe-area-from-browser.png), [web-16](android-touch/web-16-landscape-safe-area-from-query.png) |
| Portrait with `?safe=40,0,30,0` | [web-17](android-touch/web-17-portrait-safe-area.png) |
| The shipped, unmodified Windows build under Wine 11 (`--write-movie`, no input, isolated Xvfb display, own Wine prefix): desktop HUD, keyboard hint, no touch controls | [wine](android-touch/wine-shipped-desktop-unchanged.png) |

What this does **not** show: whether a real phone grants the fullscreen request (a headless Chromium grants it without a real gesture
policy; Android Chrome wants a user activation, which is why Full acts on the lift); the "page hidden" event was a dispatched
`visibilitychange`, not a real tab switch; CDP touches are not a finger; Android Chrome's gesture navigation, notification shade, rotation
lock, display cutouts and performance are untouched.

## Physical Android checklist (#6 / #22)

Add to `docs/itchio-evidence.md`'s Android table (A1-A10 there still stand; note that A3's "right ~45%" now Converges instead of
doing nothing, and "Pause then Resume" can use the large Resume button):

| ID | Check | Expect |
|---|---|---|
| B1 | Cold load in portrait and in landscape, no touch yet | touch controls already visible; no keyboard hint; build id shown |
| B2 | Thumb steers while a second thumb taps Dash, then Q, E, R, Converge, Swap (with a drop in reach) | each acts immediately; steering never stops or jumps |
| B3 | Tap the arena in each quadrant, in the left (stick) zone with a quick tap and with a hold | Converge at the tapped point (cooldown text counts); a hold only steers |
| B4 | Press every button with a finger already steering and with a finger resting on the arena | no extra Converge, no stick start |
| B5 | Empty arena (right after a wave clears): Converge button and each ultimate | fire ahead of the player, not at the button |
| B6 | Rotate portrait <-> landscape idle, mid-drag, while paused | layout refits, taps still land on target, nothing stuck, still paused |
| B7 | Home / app switch / lock screen / tab switch mid-drag, return | paused, no stuck movement or ring, only Resume continues |
| B8 | Edge gesture or notification shade mid-drag (cancelled touch), also with a finger on a button (Resume, Dash, Pause) | stick released, fresh touch works, the button works on its next press |
| B9 | Fullscreen via **Full** (and the itch.io button) | the button is shown on Android Chrome; one tap enters fullscreen (the request acts on the lift); controls still reachable and aimed correctly after; record if a stuck-pressed look or a refused request appears |
| B10 | A device with a display cutout, fullscreen, landscape both directions | no button under the cutout; record whether `env()` insets are non-zero |
| B11 | Dead, then restart by the large Restart button; paused, resume by the large Resume | works the first time, every time |
| B12 | Tap target size and thumb reach on the named reference phone | buttons comfortable; list any that are not |
| B13 | 5+ fingers on the screen, palm rejection | no stuck input; record what the device did |
