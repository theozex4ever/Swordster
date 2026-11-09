# itch.io delivery evidence (issue #6)

Blank record for the real-device checks in [`itchio-setup.md`](itchio-setup.md). **Nothing in
this file has been verified.** Every result starts as `UNVERIFIED`. Only the maintainer, who runs
the checks, changes a result, and only for something they personally observed. A target that is
unavailable stays `UNVERIFIED`; do not mark it `PASS` or `N/A`.

Result values: `UNVERIFIED` (default) · `PASS` · `FAIL` (describe it under Notes and in
"Delivery blockers"). Free-text fields start as `_not recorded_`.

How each check is defined (build id, movement, pause/resume, sound unlock, Web asset delivery,
startup times, warnings) and each interaction procedure (rows `D1`–`D3`, `D4`, `A1`–`A10`:
focus loss, resize, mouse, fullscreen, simultaneous touch, UI/arena separation, orientation,
pointer cancellation, background and explicit resume) is in section 6 of `itchio-setup.md`
("Required interaction procedures"), including which targets each applies to and what the
expected result is.

**A target is not complete until every required row for it is recorded.** A required row that is
still `UNVERIFIED` (not run, or the target was unavailable) keeps that target's Summary entry at
`UNVERIFIED`; set a target's Summary entry to `PASS` only when all of its rows are `PASS`.

## Run under test

| Field | Value |
|---|---|
| Build id (`<BUILD_ID>`) | _not recorded_ |
| Source commit (full, from `BUILD-INFO.json`) | _not recorded_ |
| `-dirty` in the build id? (must be no) | _not recorded_ |
| Page URL (`<PAGE_URL>`) | _not recorded_ |
| Windows ZIP uploaded: name and bytes | _not recorded_ |
| Web ZIP uploaded: name and bytes | _not recorded_ |
| Web ZIP contents verified against the pair's `SHA256SUMS` (`0 problems`)? | UNVERIFIED |
| Both uploads come from the same `dist/<BUILD_ID>/`? | UNVERIFIED |
| Date(s) tested / by | _not recorded_ |

## Summary

| Target | Overall |
|---|---|
| Page settings and signed-out access | UNVERIFIED |
| Windows 10 x86_64 (no Python/Godot) | UNVERIFIED |
| Windows 11 x86_64 (no Python/Godot) | UNVERIFIED |
| Desktop Chrome | UNVERIFIED |
| Desktop Firefox | UNVERIFIED |
| Android Chrome (physical device) | UNVERIFIED |
| Mobile Friendly enabled and re-checked on Android | UNVERIFIED |

## Page settings and signed-out access

Checked in a window with no itch.io login.

| Check | Result | Notes |
|---|---|---|
| Kind of project is HTML | UNVERIFIED | |
| Pricing is No payments | UNVERIFIED | |
| Visibility is Public with Unlisted in search & browse | UNVERIFIED | |
| Project removed from creator profile (profile viewed signed out) | UNVERIFIED | |
| Page not found by searching its title (signed out; say when) | UNVERIFIED | |
| Page opens and game launches with no login prompt | UNVERIFIED | |
| Page opens and game launches with no payment/donation prompt | UNVERIFIED | |
| Windows file downloads with no login prompt | UNVERIFIED | |
| Windows file downloads with no payment/donation prompt | UNVERIFIED | |
| Page offers both browser play and the Windows download | UNVERIFIED | |
| Web upload is the one marked playable; Windows upload is a platform download | UNVERIFIED | |
| Mobile Friendly enabled (after Android verification) | UNVERIFIED | |

## Windows 10 x86_64, machine without Python/Godot

| Field | Value |
|---|---|
| Machine model | _not recorded_ |
| Physical machine or VM | _not recorded_ |
| Windows version and build (`winver`) | _not recorded_ |
| How "no Python / no Godot" was checked | _not recorded_ |
| Build id seen in the game window | _not recorded_ |
| Build id matches the intended build (label, `READ-ME-FIRST.txt`, `BUILD-INFO.json`, file name) | UNVERIFIED |
| Windows ZIP size, as shown on the page / as downloaded | _not recorded_ |
| Cold startup (s) | _not recorded_ |
| Cached startup (s) | _not recorded_ |
| SmartScreen / unsigned / antivirus warning, exactly as shown | _not recorded_ |
| Basic movement (WASD/arrows) | UNVERIFIED |
| Pause / resume (P, Esc, button) | UNVERIFIED |
| Sound unlock | UNVERIFIED |
| D1 Focus loss with a key held (`Alt+Tab`/click away, key released while away): pauses, no stuck movement, resumes only by `Resume`/`P`/`Esc`; also key still held on return, and paused-then-away | UNVERIFIED |
| D2 Window resize and maximise/restore (idle, while moving, while paused): arena scales, buttons visible and working, no stuck movement | UNVERIFIED |
| D3 Mouse: `Pause`/`Resume`/`Restart` clicks work; clicks and drags in the arena move nothing | UNVERIFIED |
| Signed-out download from the page | UNVERIFIED |
| Notes | |

Fullscreen (`D4`) is not applicable on Windows: the game has no fullscreen control or key in this
slice (`itchio-setup.md`, D4). It is not a result row. If you find a fullscreen control in the
build, say so in Notes and test it.

## Windows 11 x86_64, machine without Python/Godot

| Field | Value |
|---|---|
| Machine model | _not recorded_ |
| Physical machine or VM | _not recorded_ |
| Windows version and build (`winver`) | _not recorded_ |
| How "no Python / no Godot" was checked | _not recorded_ |
| Build id seen in the game window | _not recorded_ |
| Build id matches the intended build (label, `READ-ME-FIRST.txt`, `BUILD-INFO.json`, file name) | UNVERIFIED |
| Windows ZIP size, as shown on the page / as downloaded | _not recorded_ |
| Cold startup (s) | _not recorded_ |
| Cached startup (s) | _not recorded_ |
| SmartScreen / unsigned / antivirus warning, exactly as shown | _not recorded_ |
| Basic movement (WASD/arrows) | UNVERIFIED |
| Pause / resume (P, Esc, button) | UNVERIFIED |
| Sound unlock | UNVERIFIED |
| D1 Focus loss with a key held (`Alt+Tab`/click away, key released while away): pauses, no stuck movement, resumes only by `Resume`/`P`/`Esc`; also key still held on return, and paused-then-away | UNVERIFIED |
| D2 Window resize and maximise/restore (idle, while moving, while paused): arena scales, buttons visible and working, no stuck movement | UNVERIFIED |
| D3 Mouse: `Pause`/`Resume`/`Restart` clicks work; clicks and drags in the arena move nothing | UNVERIFIED |
| Signed-out download from the page | UNVERIFIED |
| Notes | |

Fullscreen (`D4`) is not applicable on Windows: the game has no fullscreen control or key in this
slice (`itchio-setup.md`, D4). It is not a result row. If you find a fullscreen control in the
build, say so in Notes and test it.

## Desktop Chrome

| Field | Value |
|---|---|
| Computer model and OS version | _not recorded_ |
| Chrome version | _not recorded_ |
| Window / game viewport size | _not recorded_ |
| Build id seen in the game | _not recorded_ |
| Build id matches the intended build | UNVERIFIED |
| Web ZIP size, as shown on the page; `index.wasm` transferred size | _not recorded_ |
| Cold startup (s) | _not recorded_ |
| Cached startup (s) | _not recorded_ |
| Web asset delivery (all files 200, no 403/404 or console errors) | UNVERIFIED |
| Basic movement (WASD/arrows) | UNVERIFIED |
| Pause / resume (P, Esc, button) | UNVERIFIED |
| Sound unlock | UNVERIFIED |
| D1a Focus loss with a key held, tab switch (key released while away): pauses, no stuck movement, resumes only by `Resume`/`P`/`Esc`; also key still held on return, and paused-then-away | UNVERIFIED |
| D1b Focus loss with a key held, click outside the game frame / address bar / DevTools (same expectations) | UNVERIFIED |
| D2 Browser window narrow/wide, zoom and DevTools open/close (game viewport size before and after, or "did not change"): arena scales, buttons visible and working, no stuck movement | UNVERIFIED |
| D3 Mouse: `Pause`/`Resume`/`Restart` clicks work; clicks and drags in the arena move nothing | UNVERIFIED |
| D4 Fullscreen via the itch.io Fullscreen Button (or "button not offered"): label and buttons visible, keys and buttons work in and after fullscreen | UNVERIFIED |
| Signed-out access, no login/payment prompt | UNVERIFIED |
| Notes | |

## Desktop Firefox

| Field | Value |
|---|---|
| Computer model and OS version | _not recorded_ |
| Firefox version | _not recorded_ |
| Window / game viewport size | _not recorded_ |
| Build id seen in the game | _not recorded_ |
| Build id matches the intended build | UNVERIFIED |
| Web ZIP size, as shown on the page; `index.wasm` transferred size | _not recorded_ |
| Cold startup (s) | _not recorded_ |
| Cached startup (s) | _not recorded_ |
| Web asset delivery (all files 200, no 403/404 or console errors) | UNVERIFIED |
| Basic movement (WASD/arrows) | UNVERIFIED |
| Pause / resume (P, Esc, button) | UNVERIFIED |
| Sound unlock | UNVERIFIED |
| D1a Focus loss with a key held, tab switch (key released while away): pauses, no stuck movement, resumes only by `Resume`/`P`/`Esc`; also key still held on return, and paused-then-away | UNVERIFIED |
| D1b Focus loss with a key held, click outside the game frame / address bar / DevTools (same expectations) | UNVERIFIED |
| D2 Browser window narrow/wide, zoom and DevTools open/close (game viewport size before and after, or "did not change"): arena scales, buttons visible and working, no stuck movement | UNVERIFIED |
| D3 Mouse: `Pause`/`Resume`/`Restart` clicks work; clicks and drags in the arena move nothing | UNVERIFIED |
| D4 Fullscreen via the itch.io Fullscreen Button (or "button not offered"): label and buttons visible, keys and buttons work in and after fullscreen | UNVERIFIED |
| Signed-out access, no login/payment prompt | UNVERIFIED |
| Notes | |

## Android Chrome, physical device

Record the run with Mobile Friendly off first, then again after enabling it.

| Field | Mobile Friendly off | Mobile Friendly on |
|---|---|---|
| Phone model | _not recorded_ | _not recorded_ |
| Android version | _not recorded_ | _not recorded_ |
| Chrome version | _not recorded_ | _not recorded_ |
| Screen / game viewport size, portrait | _not recorded_ | _not recorded_ |
| Screen / game viewport size, landscape | _not recorded_ | _not recorded_ |
| Warning shown by itch.io, if any | _not recorded_ | _not recorded_ |
| Build id seen in the game | _not recorded_ | _not recorded_ |
| Build id matches the intended build | UNVERIFIED | UNVERIFIED |
| Web ZIP size, as shown on the page | _not recorded_ | _not recorded_ |
| Cold startup (s) | _not recorded_ | _not recorded_ |
| Cached startup (s) | _not recorded_ | _not recorded_ |
| Web asset delivery (reached the arena; network inspected or "not inspected") | UNVERIFIED | UNVERIFIED |
| Basic movement (left-area touch drag) | UNVERIFIED | UNVERIFIED |
| Pause / resume (on-screen button) | UNVERIFIED | UNVERIFIED |
| Sound unlock (first tap) | UNVERIFIED | UNVERIFIED |
| A1 Simultaneous: drag with one finger, second finger taps `Pause`, then `Resume` (and finger lifted while paused) | UNVERIFIED | UNVERIFIED |
| A2 A second finger in the arena is ignored while the first drives the stick | UNVERIFIED | UNVERIFIED |
| A3 UI/arena separation: touches starting on `Pause`/`Restart`, in the right ~45% and in the top strip never move the player; a touch in the left area does | UNVERIFIED | UNVERIFIED |
| A4 Rotate portrait ↔ landscape while idle: layout visible, buttons do not start the stick, fresh drag works in both | UNVERIFIED | UNVERIFIED |
| A5 Rotate during a drag: no stuck movement or ring after lifting; fresh drag works | UNVERIFIED | UNVERIFIED |
| A6 Rotate while paused: stays paused, `Resume` is explicit, movement works afterwards | UNVERIFIED | UNVERIFIED |
| A7 Pointer cancelled mid-drag (edge gesture started; notification shade): no stuck movement or ring, fresh touch works | UNVERIFIED | UNVERIFIED |
| A8 Background mid-drag (Home/app switch, 5 s): returns paused, no stuck movement, resumes only via `Resume` | UNVERIFIED | UNVERIFIED |
| A9 Screen lock and Chrome tab switch mid-drag: same expectations as A8 | UNVERIFIED | UNVERIFIED |
| A10 Fullscreen (itch.io button when off; forced fullscreen launch when on): label/buttons visible, touch works in and after fullscreen, or "not offered" | UNVERIFIED | UNVERIFIED |
| Signed-out access, no login/payment prompt | UNVERIFIED | UNVERIFIED |
| Notes | | |

## Delivery blockers

List anything that stops a tester from playing or downloading (asset errors, wrong or mismatched
build id, a login/payment prompt, a Windows warning that blocks launch, no sound after unlock,
unusable touch layout, stuck movement or a stuck stick ring after backgrounding, rotating, focus
loss or a cancelled touch, a touch that begins on a button moving the player, missing Windows
download on the HTML page). Each must be resolved before
combat-port work continues; copy them to issue #6.

| Blocker | Target | Status |
|---|---|---|
| _none recorded_ | | |
