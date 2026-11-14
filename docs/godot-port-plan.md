# Swordster: Godot port plan

## Confirmed requirements

Confirmed during the port interview:

- Retain both Windows downloads and browser playtesting.
- Preserve all existing mechanics and controls before replacing the Python game;
  record any agreed exceptions individually. Defer new features and balance changes.
- One local command, also used by CI, must produce complete Windows and Web
  artifacts from a clean checkout, without manual file patching. Include build
  identifiers and require a successful launch on another Windows machine and a
  hosted browser check.
- Use typed GDScript, the standard Godot editor and Compatibility rendering.
- Required targets: Windows 10/11 x86_64, desktop Chrome/Firefox and Android Chrome.
  iPhone/iPad and Safari are outside the port's acceptance matrix.
- Unsigned internal Windows builds are acceptable initially. Browser play remains
  available when Windows launch warnings obstruct a tester; revisit signing if
  actual launch failures prevent testing.
- CI builds and retains artifacts automatically. Updating the version available
  to testers requires an explicit publish action.
- The Linux build command automatically downloads, verifies against pinned
  checksums, and caches the chosen Godot editor and matching export templates
  when absent. Initial setup requires internet; later builds reuse the cache.
- Use one itch.io HTML project for browser play and the Windows download, with
  Public visibility, Unlisted in search & browse, No payments, and removal from
  the creator profile.
- Tester access uses an unlisted link without login. Anyone with the link can
  access or forward it; confidential access is not required.
- Performance targets are steady 60 FPS on Windows/desktop browsers and 30 FPS
  on Android Chrome, measured on named reference devices against a repeatable
  demanding combat workload. Define devices and workload before benchmarking;
  do not imply a guarantee for unlimited waves or arbitrary hardware.
- Visual parity is loose because the existing art is proof-of-concept. Make
  visuals modular so sprites can replace them later with minimal friction.
  Preserve gameplay and readable combat cues; matching the current pixels or
  visual identity is not an acceptance gate. Cosmetic density may vary by device.

See [the browser delivery decision](adr/0001-retain-browser-playtesting.md).
See also [the language decision](adr/0002-use-typed-gdscript.md) and
[the presentation boundary](adr/0003-separate-combat-from-visuals.md).
The user confirmed the consolidated shared understanding; the design interview
is complete. Implementation has not started. Reference device models, exact engine
version, account/project identifiers and credentials are implementation-time
inputs, to be established before the relevant build, benchmark or publish gate.

### Accepted build and publication workflow

Automatic tool setup covers Godot and its matching export templates. Document
the base Linux shell/download/archive utilities required by the script and fail
with actionable instructions if they are missing. Do not silently change system
packages or require a pre-existing manually configured Godot installation.

For itch.io, automatic CI builds retain artifacts without touching
live tester channels. An explicit publish action selects an existing successful
build pair by build ID and uploads both; it must not rebuild a moving branch.
Keep a known-good pair for rollback by re-upload. The two channel updates are
not atomic: verify both build IDs after publishing, and restore both if one fails.
Require signed-out browser play/download checks and a publish/rollback rehearsal.
CI artifacts alone are not tester links because their downloads can require login.
See [hosting research](godot-hosting-research.md) for official sources and limits.
The creator account and project slug are not established. No hosting account or
external service has been changed as part of planning.

## Decision: typed GDScript

Use Godot 4's standard editor, typed GDScript, and the Compatibility renderer.
Prioritize Windows x86_64 ZIPs and a browser demo. These targets preserve the
current required delivery options. Native mobile, macOS and Linux releases are
outside this port's scope; iPhone/iPad browser support is also excluded.

Browser playtesting is now a confirmed requirement. Even for Windows alone,
GDScript is the simpler default here: there is no
existing C# code or .NET dependency to preserve.

### C# versus GDScript

- **Tester access:** both support desktop exports, but Godot 4 C# currently cannot
  export to Web. GDScript preserves a click-to-play option. This is the deciding
  factor. [Official C# platform support](https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/index.html#c-platform-support)
- **Build maintenance:** C# requires the .NET editor and SDK. GDScript uses the
  standard editor and matching export templates. C# exports bundle runtime parts;
  testers do not need to install the SDK themselves. The extra burden is on the
  developer/build machine. [C# prerequisites](https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/c_sharp_basics.html)
- **Port effort:** both require a rewrite of Pygame APIs. GDScript's Python-like
  syntax reduces translation friction, but scene lifecycle, signals, resources,
  and engine timing still require deliberate redesign.
- **Maintainability:** C# offers mature general-purpose tooling and stronger type
  facilities. Typed GDScript supplies useful checks and fits Godot's editor
  workflow. Use explicit types at module boundaries and typed data resources;
  avoid passing arbitrary dictionaries through the combat system.
- **Performance:** C# may help CPU-heavy custom simulation, but no benchmark of
  this port exists. Enemy pair separation and repeated target scans deserve
  profiling before language changes. Do not maintain two language implementations
  or add native extensions speculatively.

C# becomes worth reconsidering if browser support is explicitly dropped and a
measured bottleneck or substantial .NET code reuse justifies its tooling cost.
Do not choose Godot 3 merely to retain C# Web export.

## What is being ported

Inspected repository: `game/main.py` is a 2,225-line prototype containing game
logic, rendering, procedural graphics, and audio synthesis. There is no existing
Godot project, automated test suite, dependency lockfile, or CI workflow in this
checkout. The initial working tree was clean.

Parity scope:

- A 2600 × 1800 bounded arena, 1280 × 720 reference view, smooth movement,
  camera follow/look-ahead, dash, invulnerability, player damage and death.
- Three independently operating swords: Fang (`fang`), Warden (`blade`), Pike
  (`lance`), Colossus (`colossus`). Preserve the internal IDs and displayed names.
  Include auto attacks, recovery, range limits, Converge, and all four ultimates.
- Fire spread on death, poison stacks, chill/freeze, frozen damage bonus and
  contact immunity; elemental ground fields and damage-over-time ticks.
- Husk, runner, spitter and brute behavior; enemy projectiles, sword parries,
  enemy separation, knockback, wall slams and launched-enemy collisions.
- Wave queues, telegraphed spawns, wave scaling, armed drops, three rarities,
  pickup expiration, slot swapping, healing motes, combo and kill counters.
- HUD, help, range display, pickup comparison, wave banners, pause, death screen,
  restart, trails, shadows, glows, particles, decals, shake, hitstop and slow motion.
- Keyboard/mouse and mobile browser controls, nearest-enemy touch aiming,
  arena-tap aiming, fullscreen where supported, and suspend/resume handling.

There is no persistent progression or multiplayer to migrate. Do not add those,
controller support or new gameplay content to this port. New production art is
not required; presentation may change to support the replaceable visual layer.

## Build outcome first

The current Windows path installs Windows Python under Wine, runs PyInstaller,
and converts an SVG icon through Pygame. The browser path builds with Pygbag,
downloads its runtime from a CDN, and injects JavaScript/CSS controls.

Replace that with a pinned Godot editor plus matching official export templates,
committed export presets, and one packaging script shared by local builds and CI.
Linux-to-Windows export uses templates; no Wine/Python packaging layer is needed.
[Export workflow](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html)

The first milestone must demonstrate the real delivery path with a tiny playable
scene. Do this before investing in the full rewrite. Success means another person
can unzip and launch on Windows without development tools, and open the served
browser build with sound and working input.

## Proposed implementation boundaries

Create `godot/project.godot` alongside the existing prototype. Keep Python runnable
as a reference until parity and tester delivery pass. Proposed files below do not
exist yet.

- `scenes/game.tscn`: owns a run, arena, entity containers, camera and HUD.
- `scripts/run.gd`: explicit update order, wave/death transitions, pause/restart,
  simulation time and run-owned collections. Keep run state local to the scene.
- `scenes/player.tscn`, `scripts/player.gd`: movement, dash, health and invulnerability.
- `scenes/enemy.tscn`, `scripts/enemy.gd`: shared enemy state with four explicit
  behavior branches initially; separate further only when it improves clarity.
- `scripts/sword.gd`: one sword instance with explicit attack/ultimate states,
  per-attack hit tracking and targeting. Split type-specific behavior if needed;
  avoid a general ability framework for four swords.
- `scripts/combat.gd`, `scripts/conditions.gd`: damage, knockback, deaths, elemental
  stacking and field ticks. Accept typed inputs; presentation responds to outcomes.
- `scripts/wave_director.gd`: spawn schedule, composition, armed loadouts and scaling.
- `scenes/pickup.tscn`, `scripts/pickup.gd`: dropped sword data and expiration;
  the run handles the swap transaction and slot cooldown transfer.
- `ui/hud.tscn`, `ui/touch_controls.tscn`: CanvasLayer/Control UI, with a shared
  input adapter so keyboard, mouse and touch call the same gameplay actions.
- `data/`: small typed Resource definitions for sword, enemy, element and rarity
  constants. Copy current numbers first; distinguish immutable definitions from
  per-instance cooldowns, health and condition state.
- `effects/`, `audio/`: drawing helpers, bounded effects and baked sound assets.

### Replaceable visuals and later sprites

Give actors and swords a visual child scene with a small explicit contract:
read logical pose, facing, action phase, elemental/rarity appearance and transient
combat cues. Initially it can draw simple shapes. Later the same child scene can
use Sprite2D/AnimatedSprite2D and local animation resources. Keep this a concrete
scene boundary rather than building a general skin/plugin framework.

Combat owns health, movement, collision geometry, targeting, damage timing and
cooldowns. Visual animation must not deliver damage or advance sword states via
animation callbacks. Resource-defined combat timing supplies windup/strike/recovery
cues; animations follow those phases. Keep cosmetic height, tilt, trails and
squash separate from the logical world position and hit geometry.

Expose visual-only size, pivot, facing orientation and animation mapping within
the visual scene. Texture dimensions must not determine reach or collision size.
Element color/indicators and sword identity must stay legible with either visual
implementation. An artist should be able to replace an actor or sword view and
adjust its visual settings without editing the damage, AI or movement scripts.

Verify this boundary during the small combat-loop milestone by replacing one
actor view and one sword view with temporary texture-based visuals. Confirm that
combat fixtures still pass without gameplay edits. No finished sprite pack is
needed for this check.

Use Node2D entities and explicit circle/segment collision queries initially.
Do not replace the current knockback/separation model with rigid-body physics.
Pike's fast sweep needs swept segment tests, rather than overlap-only detection.
Use a world Camera2D and world-space aiming; UI layout must not alter hit geometry.
Signals are useful for HUD/effects notifications; gameplay ordering stays explicit.

Run simulation from a fixed physics tick, initially 60 Hz, and interpolate visuals
where needed. This differs from the prototype's variable delta capped at 1/30;
compare movement, sword springs, damage cadence and dash distance before accepting
it. Centralize gameplay delta: hitstop freezes the same gameplay systems as today,
while pause freezes gameplay and still allows UI resume. Keep real-time shake
decay and slow-motion duration distinct from scaled gameplay time. Avoid globally
changing engine time scale until UI and audio consequences have been verified.

## Ordered milestones and acceptance gates

### 0. Capture the reference

Record short reference runs and focused cases for movement/dash, every auto attack
and ultimate, condition interactions, wall slams, swapping and death/restart.
Copy all balance tables, formulas and input mappings into a parity checklist.
Include hidden rules such as the 12% critical chance, poison cap of six, four ice
stacks to freeze, brute freeze duration reduction and slot cooldown fraction on swap.
Capture wave composition/unlock rules and the guaranteed first-wave Pike drop.

Use fixed fixtures for mechanical comparisons. Equal random seeds alone do not
produce equal Python/Godot random streams. Seed gameplay separately from visual
randomness in the new implementation; do not require pixel-identical effects.

Gate: each feature has an observable reference and expected behavior; no balance
changes are silently bundled into migration.

### 1. Prove export and tester delivery

Pin an exact supported stable Godot 4 release and template version after checking
their availability. Use Compatibility and standard GDScript; record version and
download checksums. Create a minimal arena, moving player, test sound, pause/restart,
keyboard/mouse and basic touch controls. Add Windows x86_64 and Web presets.

Implement `scripts/build-testers.sh` with version/template checks, asset import,
release export into a fresh staging directory, and ZIP packaging. Fail on any
export error or missing output; never distribute a stale previous executable.
Bootstrap and cache the pinned editor/templates automatically when missing, with
checksum verification and clear network/download failures. Use the same verified
tool versions locally and in CI; reject mismatches rather than silently upgrading.
Include icon, tester instructions, build ID/commit and a SHA-256 manifest. Keep
separate executable/PCK together in the Windows ZIP initially.

Illustrative CLI sequence, once project/presets/output directories exist:

```sh
godot --headless --path godot --editor --import
godot --headless --path godot --export-release "Windows Desktop" ../builds/windows/Swordster.exe
godot --headless --path godot --export-release "Web" ../builds/web/index.html
```

These are planned commands, not executed builds. Actual preset names and output
paths must match the script. Use the editor binary, not an export template binary.
[CLI export documentation](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html#exporting)

Web: start with single-thread export, extensions disabled, and normal HTTPS static
hosting with correct WASM MIME type. Keep all generated files together. This avoids
the cross-origin isolation setup required by threaded builds. Add a click/tap start
action to unlock audio. Smoke-test hosting and mobile browsers early.
[Web requirements](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)

Gate: build both targets from a clean Linux checkout; another Windows machine
launches the ZIP without Python/Godot installed; a desktop and mobile browser can
move, pause, resume and play sound. Record artifact size, startup time and hardware.
If this fails, resolve delivery before continuing.

### 2. Port a complete small combat loop

Implement player bounds, camera, dash, damage/invulnerability, one husk, Fang auto
attack, enemy death, healing motes, one wave, HUD and death/restart. Use simple
procedural visuals that already communicate windup and impact. Keep combat geometry
independent of cosmetic height/rotation.

Gate: a complete run works in both exports; dash distance/timing, incoming damage,
attack cadence and healing match the reference within documented tolerances.

### 3. Complete combat parity

Port Warden, Pike and Colossus auto attacks, then Converge and ultimates one at a
time. Include range clamping, target replacement after death, per-swing hit sets,
parries, knockback, separation, bowling and wall damage. Add conditions/fields,
then remaining enemy behavior, projectiles and full wave generation.

Gate: focused combat fixtures pass for every sword, with no tunneling at low frame
rates and no duplicate deaths/drops. Confirm frozen enemies cannot contact-damage
the player; poison caps/expires correctly; fire spreads with the current rules;
dead/freed targets are safe during flurry and impalement.

### 4. Complete loot, input and presentation

Port rarity modifiers, nearby-pickup selection, swap/drop behavior and cooldown
fraction preservation. Restore all HUD/help/range/death information and key aliases,
including R as slot-three ultimate while alive and delayed restart after death.
Restore combo and wave-clear presentation.

Rebuild touch controls in Godot rather than retaining the Pygbag JSON bridge.
Support simultaneous joystick/button fingers, independent pointer tracking, input
release on focus loss, tap-to-aim, nearest-enemy fallback, safe-area layout and
landscape/portrait resizing. UI taps must not also trigger arena actions. Retain
explicit resume after backgrounding; verify desktop and touch input precedence.

Use replaceable visual scenes with simple drawing/textures, trails and lightweight
effects. Reuse procedural presentation only where convenient; do not spend the
port budget reproducing proof-of-concept pixels. Bake the existing synthesized
sounds into WAV assets once, preserving
their character without a runtime synthesis dependency. Keep a reproducible asset
generation recipe. Web Sample playback has procedural-audio/effect restrictions;
validate sound timing on actual exports.
[Web audio documentation](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html#audio-playback)

Gate: every documented control and HUD state works, attack telegraphs/impacts read
clearly, actor/sword visuals can be replaced without gameplay edits, and touch
survives resize, background/resume and pointer cancellation without stuck movement.

### 5. Automate releases and run parity playtests

Add CI calling the same local build script on a clean Linux runner with pinned
editor/templates. Run import/parse checks and headless mechanical checks before
exporting. Upload complete Windows and Web artifacts for each selected commit;
release/tag packaging uses immutable versioned filenames and embedded build IDs.
Publishing to itch.io requires an explicit action selecting a successful retained
build pair. Configure the unlisted, no-payments HTML project with browser and
Windows channels, and verify signed-out access. Keep a rollback pair and verify
both channel versions after publishing. Do not require a signing certificate to
produce internal test builds.

Use a small dependency-free Godot headless test runner unless an existing test
convention is introduced during implementation. Test damage/condition rules,
cooldown transfer, wave transitions, invulnerability, hit tracking and restart
cleanup. Headless tests do not substitute for GPU/audio/browser/device checks.

Run actual Windows 10/11 x86_64 launch tests and desktop Chrome/Firefox plus
Android Chrome browser checks. Safari and iPhone/iPad are not required. Record any
unavailable required target as unverified; it cannot silently pass the acceptance
gate. Play a 20-minute soak and compare late-wave load
to the prototype. Validate the agreed 60 FPS desktop and 30 FPS Android targets
on the named reference devices with the documented demanding workload. These
targets have not yet been measured. Check entity/effect counts return to baseline
on restart.

Profile before optimizing. If enemy pair separation becomes dominant, add a simple
spatial grid behind the existing query boundary. Bound cosmetic lifetimes/counts;
never silently cap enemies or change combat rules as a performance fix.

Gate: one command/CI run produces both complete tester artifacts; mechanical
checks pass; device checks and limitations are recorded; testers can identify the
build when reporting a problem. Include log location/instructions and a concise
feedback checklist without collecting telemetry automatically.

### 6. Cut over

Switch README quick-start and tester instructions to Godot and the new build
command. Document exact editor/template versions, controls, export destinations,
known browser limitations and artifact layout. Preserve icon attribution and add
required Godot/license notices. Tag the last Python prototype as the reference.

After the acceptance gates pass, remove the obsolete Wine/PyInstaller script,
Pygbag server/control bridge and Python runtime path in a separate cleanup change.
Keep the reference accessible in Git. Do not maintain two gameplay branches.

Gate: fresh-checkout instructions work and no active tester workflow depends on
Wine, PyInstaller, Pygbag or a Python installation.

## Limits and effort

Godot reduces packaging complexity; it does not guarantee the disappearance of
Windows SmartScreen/antivirus warnings. Signing still needs a certificate and
signing tooling, and should be evaluated separately if it blocks testers.
[Windows signing](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html#code-signing)
Android Web performance and combat feel remain validation risks. Safari/iOS
compatibility is not a release gate and is not promised to testers.

Plan in independently reviewable milestones rather than one replacement commit.
A preliminary allowance is 2–4 focused developer weeks for parity and delivery,
with the largest uncertainty in combat/presentation and mobile validation. This
is a planning estimate, not a measured schedule; re-estimate after milestones 1
and 2. The immediate next implementation task is milestone 0 plus the export
proof, not a wholesale translation of `main.py`.

Supporting research: [Godot export constraints](godot-export-research.md), checked
against official stable documentation on 2026-11-08. No Godot builds or device
tests were run while writing this plan.
