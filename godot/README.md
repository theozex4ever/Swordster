# Swordster (Godot port)

Delivery-proof slice of the Godot 4 port: a small moving, audible, pausable arena
that exports to Windows and Web from one Linux command. Combat arrives in later
slices; the Python/Pygame prototype in `game/` stays the behavioural reference
and keeps working.

- Engine: Godot **4.7.2-stable**, standard (non-.NET) editor, typed GDScript,
  Compatibility renderer, Web export single-thread with extensions disabled.
- Pinned in `tools/godot/godot.lock` (editor + templates, SHA-512 from the
  release's `SHA512-SUMS.txt`).

## Build

```bash
./build-godot.sh                  # full build -> dist/<build-id>/
./build-godot.sh --checks-only    # bootstrap, import, headless checks only
./build-godot.sh --bootstrap-only # just fetch/verify/install the pinned Godot
```

No Godot needs to be installed: the script downloads the pinned editor and
export templates (about 1.4 GB, once), verifies them against the committed
checksums, extracts only what it needs into `~/.cache/swordster/`, and runs only
that copy (a `godot` on your `PATH` is never used). Godot's own settings and user
data are redirected into the build's work directory.

**Required base utilities** (the script checks them and never installs anything):
`bash`, `curl`, `python3` (3.8+, standard library only), `git` (or set
`SWORDSTER_SOURCE_COMMIT`), `sha512sum`, and coreutils/findutils-style `timeout`,
`sleep`, `date`, `grep`, `sed`, `cp`, `mv`, `rm`, `mkdir`, `touch`, `find`, `sort`,
`xargs`, `cut`, `tr`, `head`, `tail`, `cat`, `env` (`sha256sum` to check a finished
pair by hand). Linux x86_64 host.

Pipeline: prerequisite check → verified tool bootstrap/cache → fresh staging copy
of `godot/` (with the build identity written into `BuildInfo`) → asset import →
headless checks (`godot/tests/run_checks.gd`) → Windows and Web release exports →
output/single-thread validation → packaging → manifest verification → atomic move
into `dist/`.

### Output

```
dist/<build-id>/
├── Swordster-<build-id>-windows.zip     Swordster.exe, Swordster.pck, Swordster.ico,
│                                        READ-ME-FIRST.txt, BUILD-INFO.json, SHA256SUMS
├── Swordster-<build-id>-web/            index.html/.js/.wasm/.pck + audio worklets,
│                                        BUILD-INFO.json, SHA256SUMS
├── BUILD-INFO.json                      build_id, source_commit, source_dirty, built_at_utc, ...
└── SHA256SUMS                           covers the ZIP, every Web file and BUILD-INFO.json
```

Build id is `<UTC timestamp>-<commit prefix>` (`-dirty` appended for an unclean
working tree). The same id and full commit appear in both packages, in
`BUILD-INFO.json`, in the tester `READ-ME-FIRST.txt`, and in the game's top-left
label. Verify a pair with `sha256sum -c SHA256SUMS` from inside `dist/<build-id>/`.
This documents identifiable outputs, not byte-for-byte reproducibility.

The Web bundle is single-thread, needs no COOP/COEP headers and can be served by
any static file server; all asset URLs are relative (`python3 -m http.server`
inside the `-web` folder works). Windows builds are unsigned, so SmartScreen shows
"Windows protected your PC" (instructions are in the ZIP).

### Environment overrides

| Variable | Default | Purpose |
|---|---|---|
| `SWORDSTER_CACHE_DIR` | `$XDG_CACHE_HOME/swordster` | tool cache |
| `SWORDSTER_WORK_DIR` | `<repo>/.build-godot` | fresh `staging/` each run, logs in `staging/logs` |
| `SWORDSTER_DIST_DIR` | `<repo>/dist` | finished pairs |
| `SWORDSTER_BUILD_ID` | timestamp + commit | refuses an id that already exists |
| `SWORDSTER_SOURCE_COMMIT` | `git rev-parse HEAD` | for builds outside a git checkout |
| `SWORDSTER_DOWNLOAD_BASE` | the pinned GitHub release URL | mirror; checksums still enforced |

### Exit codes

`0` ok · `2` usage · `10` missing base utility · `11` download failed ·
`12` checksum mismatch (download, installed tool, or changed pin) ·
`13` Godot version mismatch · `14` import failed · `15` automated checks failed ·
`16` export failed · `17` expected output missing/invalid ·
`18` unknown source commit or build id already exists.

Godot's headless editor sometimes aborts at shutdown after finishing its work
(roughly 1 run in 25 observed with 4.7.2). The script retries a Godot step up to 3
times only when the process was killed by a signal; ordinary failures, timeouts and
script errors are never retried, and outputs are validated regardless.

A failed run never touches `dist/`: output is assembled in staging and moved in
only after every step and the manifest verification pass. Corrupted or
tampered cached tools are reported, not silently re-downloaded or upgraded; delete
the named cache directory to reinstall. To change the engine, update every line of
`tools/godot/godot.lock` together.

## Checks

- `godot/tests/run_checks.gd` drives the real `GameRun` simulation, the
  `InputTranslator` and the `Main` scene headlessly (movement, bounds, pause,
  resume, restart, key aliases, independent touch pointers, focus loss, audio
  unlock, visual replacement). It must print `CHECKS PASSED: <n>`.
- `tools/godot/mutation-check.sh` applies deliberate bugs (zero speed, ignored
  pause, stale restart, ...) to a scratch copy and requires the checks to fail.
- `tools/godot/test-build-failures.sh` runs `build-godot.sh` in sandboxes against
  representative failures and requires the specific exit code and no new pair.

## Layout

```
godot/
├── scripts/sim/            GameRun (owns run state, 60 Hz step), GameCommand, RunScenario
├── scripts/input/          InputTranslator (keyboard), TouchJoystick (per-pointer)
├── scripts/presentation/   ActorVisual contract + placeholder drawn actor
├── scripts/main.gd         wiring: input -> commands -> run -> visual
├── scripts/hud.gd, audio/  overlay UI, baked sound effects
└── tests/                  headless checks (excluded from exports)
```

Replacing the actor art: point `Main.actor_visual` (in `scenes/main.tscn`) at a
scene whose root extends `ActorVisual`. Gameplay never reads the visual.

Sound effects are baked WAVs; the recipe is `tools/godot/gen_audio.py`.
`godot/icon.ico`/`icon.png` come from `godot/icon.svg` via `tools/godot/make_icon.gd`.

## Controls

W A S D or arrow keys move · P or Esc pause/resume · R restart · touch: drag in the
left part of the screen to move, on-screen Pause/Restart buttons. The first
click/tap/key unlocks sound (browsers require a gesture). Losing focus or
backgrounding pauses the run and releases all input; resume is explicit.
