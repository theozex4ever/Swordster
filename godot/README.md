# Swordster (Godot port)

Godot 4 port of Swordster, built slice by slice. Currently playable: a complete
Fang survival loop (move, dash, three Fang spirit swords attacking on their own, a
telegraphed wave of eight husks, healing motes, death and restart) with **Viper
Flurry** on Q / E / R (each sword slot's ultimate, aimed at the cursor), a **crowd
encounter** with runners and brutes, crowd bowling and wall slams, a **spitter
encounter** with ranged foes, enemy orbs and sword parries, **elemental conditions**
(burn, poison, chill and freeze on every blow) and **Warden**, the sword of sweeping
arcs, with its **Maelstrom** ultimate (a **warden encounter** equips it), and **Pike**,
the sword of long piercing thrusts, with its **Skewer** ultimate (a **pike encounter** equips it), and **Colossus**,
the sword of crushing slams, with its **Cataclysm** ultimate and the elemental ground field it leaves (a **colossus
encounter** equips it), **armed enemies, sword drops and swaps** (a **drops encounter**) on top of the delivery-proof
arena, exported to Windows and Web from one Linux command.
Converge, the final default loadout and further waves arrive in
later slices; the Python/Pygame prototype in `game/` stays the behavioural reference
and keeps working. Reference values, tolerances and deliberate exceptions:
[Fang survival loop](../docs/reference/fang-survival-loop.md) (#8) and
[runners, brutes and crowds](../docs/reference/runners-brutes-crowd.md) (#9) and
[spitters, projectiles and parries](../docs/reference/spitters-projectiles-parries.md) (#10) and
[Viper Flurry](../docs/reference/viper-flurry.md) (#12) and
[elemental conditions](../docs/reference/elemental-conditions.md) (#11) and
[Warden and Maelstrom](../docs/reference/warden-maelstrom.md) (#13) and
[Pike and Skewer](../docs/reference/pike-skewer.md) (#14) and
[Colossus and Cataclysm](../docs/reference/colossus-cataclysm.md) (#15) and
[drops and swaps](../docs/reference/drops-swaps.md) (#17).

### Viper Flurry (Q / E / R)

Each sword slot has an ultimate triggered by its key: **Q** slot one, **E** slot two,
**R** slot three (R is also the restart key once the death screen is up). Point the
mouse and press: the sword blinks to the cursor (at most 420 px from you), darts between
the enemies inside the 150 px area for 1.25 s (one dart every 0.08 s, 1.2x the sword's
damage), then recovers. The ultimate recharges for 9 s (shorter for Rare and Mythic
swords) from the moment it starts; the cards at the bottom left show READY, ACTIVE or
the seconds left, with the sword type under the bar. Three Fang swords are still the normal run's
fixture loadout, so every slot holds Viper Flurry there; the warden encounter below equips a Fang
and two Wardens, whose slots hold Maelstrom, and the pike encounter equips three Pikes, whose slots hold
Skewer, and the colossus encounter equips three Colossus swords, whose slots hold Cataclysm.

### Warden and Maelstrom

Slice #13 ([reference](../docs/reference/warden-maelstrom.md)). **Warden** (the prototype's
`blade`) is the sword of sweeping arcs: it targets the nearest foe within 245 px, winds up for 0.16 s
(a faint band shows the arc it will cut), then swings a 0.15 s sweep about a pivot just behind the
target, alternating its direction every attack. Every foe the blade passes through is hit once per
sweep (17 damage, 300 knockback, 0.05 s of hitstop), and it knocks enemy orbs out of the air like a
Fang strike does. Its ultimate, **Maelstrom** (11 s recharge, aimed at the cursor within 400 px), makes
the sword whirl around that point for 2.2 s: foes inside the pull range are dragged toward it, a beat
every 0.2 s strikes everything inside the blades' reach for 0.6x damage, and a finishing burst
(1.6x damage, two doses of the sword's element, heavy knockback and a hitstop) ends it before a 0.3 s recovery.
Warden does not parry during Maelstrom, as in the prototype. To fight with it: the **warden
encounter** (`Swordster.exe -- --encounter=warden`, `index.html?encounter=warden`, or the dev button / `C`
after the conditions encounter) is one wave of husks, runners and two brutes against Fang (poison, Q),
Warden (ice, E) and Warden (fire, R). This mixed loadout is a development fixture, not the final default
loadout (issue #16); the normal run is unchanged.

### Pike and Skewer

Slice #14 ([reference](../docs/reference/pike-skewer.md)). **Pike** (the prototype's `lance`) is the
sword of long piercing thrusts: it prefers a foe more than 130 px from you (within 430 px), winds up
for 0.32 s (a line shows where it will cut), then thrusts at 2400 px/s along a fixed line a little
past its target. Every foe on that line is hit once per thrust (24 damage, 380 knockback), the sword
does not stop at the first, and it knocks enemy orbs out of the air. Its ultimate, **Skewer** (10 s
recharge), is a skill shot: aim with the cursor and press Q / E / R, the heading is the line from you
to the cursor whatever the distance. After a 0.38 s aim the sword launches along it for 950 px at
2600 px/s; every foe it touches is struck once for 2.2x damage with two doses of its element and
**impaled**: carried along with the sword, stunned. The Skewer lets go of what it carries at the end of its
range (flung at 750 px/s) or when its tip reaches a wall (1100 px/s: the stunned foe **slams** into the
wall and bowls others). To fight with it: the **pike encounter** (`Swordster.exe -- --encounter=pike`,
`index.html?encounter=pike`, or the dev button / `C` after the warden encounter) stands you 700 px south
of the north wall with a column of foes strung out toward it, against three Pikes (poison, ice, fire):
aim north. This is a development fixture, not the final default loadout (issue #16); the normal run is
unchanged.

### Colossus and Cataclysm

Slice #15 ([reference](../docs/reference/colossus-cataclysm.md)). **Colossus** (the prototype's
`colossus`) is the sword of crushing slams: it goes for the biggest cluster within 330 px, winds up for
0.55 s hanging high above its target, falls onto the spot it chose and crushes everything within 118 px
(50 damage at the centre down to 28 at the edge, 650 knockback scaled the same way, a heavy blow that
stops the game for 0.13 s) and destroys the enemy orbs inside. Its ultimate, **Cataclysm** (14 s recharge),
is aimed at the cursor (up to 480 px from you): the sword rises for 0.75 s, falls, and lands a slam 1.8x as wide
with 2.2x the damage and three doses of its element, then leaves an **elemental field** 1.1x as wide
that lasts 5 s and doses everything standing in it (one dose now and every half second) with the sword's element.
Poison stacks, ice chills and freezes, fire burns; fields of different swords overlap and each doses on its own
clock. The sword's height and fall are drawn from the simulation's own altitude (the slam lands when it
reaches the ground), never the other way round. To fight with it: the **colossus encounter**
(`Swordster.exe -- --encounter=colossus`, `index.html?encounter=colossus`, or the dev button / `C` after the
pike encounter) puts a cluster east of you and a wave behind it against three Colossi (poison, ice, fire): press
Q, E and R with the cursor on the crowd and watch all three fields. This is a development fixture, not the final
default loadout (issue #16); the normal run is unchanged.

### Drops and swaps (1 / 2 / 3)

Slice #17 ([reference](../docs/reference/drops-swaps.md)). An **armed enemy** carries one spirit sword, of
any type, element and rarity (Common, Rare or Mythic), drawn beside it; its health is 1.35 times an unarmed
one's. When it dies the exact sword lies where it fell for 45 s (it blinks for the last 6) with a ring of its
rarity's colour, a pillar of light for a Rare or Mythic one and its name floating up. Stand within 80 px of a drop
(the **nearest** one counts, the first of two equally near) and a card shows its name, what the type is for, damage,
speed and range with the rarity applied, its element, its ultimate and how long that takes to recharge, and how it
compares with each of the three swords you hold. **1, 2 or 3** swap it into that **sword slot**: the new sword
starts where the drop lay and rises to your side, the old one drops just below it (up to 20 px to either side) to be
claimed back, and the slot **keeps its ultimate recharge as a fraction**, so a swap can neither reset a recharge nor skip
one (a Common sword with half its Cataclysm recharge left becomes a Mythic one with half of *its* shorter recharge
left). With nothing in reach the key says so and changes nothing. Rarity makes a sword larger, faster and harder-hitting
(Rare 1.3x damage, 0.87x cooldown, 1.06x range, 1.08x size; Mythic 1.75x, 0.74x, 1.12x, 1.18x), the slot cards carry
the rarity as a border and tag, and each card says which key swaps its slot. To play it: the **drops encounter**
(`Swordster.exe -- --encounter=drops`, `index.html?encounter=drops`, or the dev button / `C` after the colossus
encounter) walks twelve armed foes (every enemy type, every sword type, all three rarities and elements) in from a
ring against Fang, Warden and Colossus, followed by a wave armed by the prototype's rule (the first two foes are
armed for sure, the first with a Pike). This is a development fixture: **the normal run is unchanged and arms no
enemies** until the full wave generation (issue #18) turns the same arming rule on for it.

### The crowd encounter

A development fixture for slice #9: one wave of five husks, five runners and two
brutes against the three-Fang fixture loadout, with a **shove** that flings nearby
foes like a heavy Colossus blow (the sword types that cause bowling and wall slams
are not ported yet). The **`Dev: ... (restarts)`** button (top right, under Pause) and
`C` cycle the dev encounters, restarting play each time: normal → crowd → spitters →
conditions → warden → pike → colossus → drops → normal; shove with the **Shove** button or `F`. To start in it:
`Swordster.exe -- --encounter=crowd` on Windows/Linux, or open the Web build as
`index.html?encounter=crowd`. Use `wall` instead of `crowd` for the same fixture with
fourteen foes already pinned between the player and the east wall and no further wave
(shove them straight into the wall). The normal run stays the husk wave.

### The spitter encounter

A development fixture for slice #10: one wave of five spitters among three husks against
the same three-Fang loadout. Spitters back away when you are within 260 px, circle out to
380 px, glow at the snout for half a second (a dashed line shows the heading) and spit an
orb at 270 px/s that hurts for 8 unless you are invulnerable (a dash gives 0.24 s). A Fang
strike that sweeps through an orb **parries** it: green flash, sparks and a `PARRY` tag, no
damage numbers. Start in it with `Swordster.exe -- --encounter=spitters` or
`index.html?encounter=spitters`, or reach it with the dev button / `C` (after the crowd).
The prototype only brings spitters in from wave 3, so the normal run is unchanged.

### Elemental conditions and the conditions encounter

Slice #11 ([reference](../docs/reference/elemental-conditions.md)). Every sword blow that
leaves its target alive applies the sword's element: **fire** burns for 3 s (spreading to
neighbours when a burning enemy dies), **poison** stacks to six and ticks for 4.5 s, **ice**
chills (half speed) and freezes at four stacks for 1.6 s (0.96 s on a brute). A frozen enemy
cannot hurt you by touch and takes 30 % more from every blow. Enemies show their conditions
(tinted rim, glow, ice shell and one pip per element), each sword card names its element, and
the legend of the dev encounter counts the burning, poisoned and frozen. A development fixture
for it: one wave of husks, runners and two brutes against the three-Fang loadout. Start in it
with `Swordster.exe -- --encounter=conditions` or `index.html?encounter=conditions`, or reach it
with the dev button / `C` (after the spitters).

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
`SWORDSTER_SOURCE_COMMIT`), `sha512sum`, `flock` (util-linux), and coreutils/findutils-style `timeout`,
`sleep`, `date`, `grep`, `sed`, `cp`, `mv`, `rm`, `mkdir`, `mktemp`, `touch`, `find`, `sort`,
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
├── Swordster-<build-id>-web/            index.html/.js/.wasm/.pck, index.png, the two icons,
│                                        both audio worklet scripts, BUILD-INFO.json, SHA256SUMS
├── BUILD-INFO.json                      build_id, source_commit, source_dirty, built_at_utc, ...
└── SHA256SUMS                           covers the ZIP, every Web file and BUILD-INFO.json
```

Build id is `<UTC timestamp>-<commit prefix>` (`-dirty` appended for an unclean
working tree); a custom id must start with a letter or digit (a leading `.` is
reserved for hidden `.incoming-*` publication directories). The same id and full commit appear in both packages, in
`BUILD-INFO.json`, in the tester `READ-ME-FIRST.txt`, and in the game's top-left
label. Verify a pair with `sha256sum -c SHA256SUMS` from inside `dist/<build-id>/`.
This documents identifiable outputs, not byte-for-byte reproducibility.

The Web bundle is single-thread, needs no COOP/COEP headers and can be served by
any static file server; all asset URLs are relative (`python3 -m http.server`
inside the `-web` folder works). Windows builds are unsigned, so Windows
SmartScreen may warn about an unrecognised app on first launch; the Windows build
has not been run yet, so what testers actually see is unverified (instructions for
a warning are in the ZIP).

To share a pair on itch.io (browser play plus Windows download) and record device
results, follow [`docs/itchio-setup.md`](../docs/itchio-setup.md) and fill in
[`docs/itchio-evidence.md`](../docs/itchio-evidence.md). The Web folder is not itch.io's
upload format: that procedure includes the command that makes the Web ZIP.

### Environment overrides

| Variable | Default | Purpose |
|---|---|---|
| `SWORDSTER_CACHE_DIR` | `$XDG_CACHE_HOME/swordster` | tool cache |
| `SWORDSTER_WORK_DIR` | `<repo>/.build-godot` | one private `staging.XXXXXX/` per run (removed on success; kept with its `logs/` after a failure, pruned after 7 days unless a live run still holds its lock) |
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
times only when the process was killed by a signal; ordinary failures and
timeouts are never retried. Retries cannot hide anything: each attempt has its own
log and a script error or failed check in *any* attempt fails the step, and the
step's export directory is emptied and recreated before every attempt (other
expected outputs are deleted), so a retry that exits 0 without writing them fails
(exit 17). After the final attempt each export must contain exactly the pinned
4.7.2 file set — Windows: `Swordster.exe`, `Swordster.pck`; Web: `index.html`,
`.js`, `.wasm`, `.pck`, `.png`, `.icon.png`, `.apple-touch-icon.png`,
`.audio.worklet.js`, `.audio.position.worklet.js` — a missing, empty or stale file or
any unexpected extra file (a thread worker, a side module) fails with 17.

Runs may overlap (full builds, `--checks-only`, any mix, even in one work
directory): each uses its own staging directory and holds an `flock` on it for
its whole lifetime, pruning only removes old directories whose lock it can take
(so a paused build is never pruned), and toolchain bootstrapping is serialized
with the same kind of lock. The kernel releases these locks when a run exits or
crashes, so there is no stale lock to clean up. `dist/<build-id>` is published by
moving the pair into a freshly reserved, empty `.incoming-<id>.XXXXXX` directory and
renaming it onto the final path with `mv -T`, which cannot overwrite or merge into
an existing pair; the published root is then re-verified (exact entries, build ids,
ZIP, every Web file, both manifests) before `BUILD OK`, and removed again with exit
17 if anything is off. A `.incoming-*` directory left by a killed run is not a
pair (pair names never start with `.`) and is removed by a later publication once
it is a day old and unlocked.

A failed run never touches `dist/`: output is assembled in staging and moved in
only after every step and the manifest verification pass. Corrupted or
tampered cached tools are reported, not silently re-downloaded or upgraded; delete
the named cache directory to reinstall. To change the engine, update every line of
`tools/godot/godot.lock` together.

## CI

`.github/workflows/build.yml` runs the unchanged `./build-godot.sh` on a clean
`ubuntu-24.04` runner for every push to `main`, every pull request (the PR head
commit, not the merge commit) and on manual dispatch. There is no CI-only build
path: the script's own order (verified toolchain → import → headless checks →
exports → packaging → verification) applies, and a failing check, import, export
or missing output fails the job with the script's exit code, which the job log
reports as an annotation (see *Exit codes*). The job also fails if the produced
`BUILD-INFO.json` is not for the checked-out commit or is `dirty`.

- **Toolchain cache:** only `~/.cache/swordster/downloads` is cached, keyed by the
  hash of `tools/godot/godot.lock`. On every run the script re-verifies each
  cached archive against the SHA-512 values in the lock and re-extracts from it, so
  a bad cache entry fails with exit 12 rather than being trusted. Changing the pin
  changes the key.
- **Concurrency:** a new push to a pull request cancels that PR's superseded
  in-progress build. Pushes to `main` and manual runs each get their own
  concurrency group, so they never queue behind or replace one another and every
  commit on `main` keeps its pair (parallel runs are possible). Pushes to a
  branch without a pull request are not built.
- **Not run by `build.yml`:** `tools/godot/test-build-failures.sh` (dozens of
  sandboxed builds, minutes of runtime) is a tooling self-test run by hand when
  the script changes. The mutation checker (`tools/godot/mutation-check.sh`, which
  tests the checks themselves, not the build) has its own workflow,
  `.github/workflows/mutation.yml`: the full pass on every push to `main` and on
  manual dispatch, never on a pull request. See *Mutation checks* under *Checks*.
- **Where the build is:** open the run (Actions → *Build*, or `gh run list
  --workflow build.yml`). Each successful run uploads one artifact named
  `swordster-<build-id>` containing `<build-id>/` with the Windows ZIP, the Web
  bundle folder, `BUILD-INFO.json` and `SHA256SUMS`, exactly as in *Output*. The
  build ID is also in the run's summary. Find a run by build ID with
  `gh api "repos/theozex4ever/Swordster/actions/artifacts?name=swordster-<build-id>"`
  (its `workflow_run.id` is the run) and download with
  `gh run download <run-id> -n swordster-<build-id>`. Verify with
  `sha256sum -c SHA256SUMS` inside `<build-id>/`.
- **Retention:** artifacts are kept **90 days** (the GitHub maximum), then
  deleted (re-running a run builds again, with a new build ID, and replaces that
  run's artifact); an expired build ID can only be rebuilt, which yields a new ID.
  Anything that must outlive that (a known-good rollback pair) has to be
  re-published or copied elsewhere before it expires. Failed runs upload only
  their step logs (`build-logs-<run-id>-<attempt>`, 7 days).
- **Not a tester channel:** the workflow has `contents: read` only, no secrets,
  and no itch.io credentials, and it never publishes. Downloading a CI artifact
  needs a GitHub login with access to the repository, so these are not tester
  links; publication to testers is a separate, explicit step.

## Checks

- `godot/tests/run_checks.gd` drives the real `GameRun` simulation, the
  `InputTranslator` and the `Main` scene headlessly (movement, bounds, pause,
  resume, restart, key aliases, independent touch pointers, focus loss, audio
  unlock, visual replacement). It must print `CHECKS PASSED: <n>`.
- `godot/tests/survival_loop_checks.gd` (run by the same runner) holds the Fang
  survival-loop behaviour checks: they submit the same `GameCommand`s as player
  input to a real `GameRun` and compare movement, camera, dash, damage,
  hitstop/slow motion, Fang timing, healing and the wave schedule against values
  captured from the Python prototype (`godot/tests/reference/fang_survival_loop.json`,
  regenerated by `tools/reference/capture_fang_survival_loop.py`, needs `pygame`).
- `godot/tests/warden_maelstrom_checks.gd` (issue #13) replays the Python prototype's captured Warden
  and Maelstrom cases (`godot/tests/reference/warden_maelstrom.json`, regenerated by
  `tools/reference/capture_warden_maelstrom.py`) tick by tick on the real simulation: sweep geometry and
  coverage at hundreds of probe points, hit-once tracking, parries, the pull, beats, burst, recovery,
  recharge, refusals, pause/death, conditions, plus the HUD, effects and render-rate fights.
- `godot/tests/pike_skewer_checks.gd` (issue #14) replays the Python prototype's captured Pike and
  Skewer cases (`godot/tests/reference/pike_skewer.json`, regenerated by
  `tools/reference/capture_pike_skewer.py`) tick by tick on the real simulation: targeting preference,
  thrust geometry at 228 probe points, piercing without gaps, parries, the Skewer's aim, flight, impalement,
  carry and release at the range and at every wall and corner, enemies that die or leave the run while
  impaled, conditions, plus the HUD, effects and a render-rate fight with wall slams.
- `godot/tests/colossus_cataclysm_checks.gd` (issue #15) replays the Python prototype's captured Colossus,
  Cataclysm and field cases (`godot/tests/reference/colossus_cataclysm.json`, regenerated by
  `tools/reference/capture_colossus_cataclysm.py`) tick by tick on the real simulation: cluster targeting, the windup,
  the fall's timing from different altitudes, area damage and falloff at 56 + 12 probe points, hitstop and shake,
  projectile clearing, Cataclysm's rise, fall and field, every element's doses and cadence, overlapping fields,
  expiry, deaths by condition, corpses, pause and restart, plus the HUD, effects and a render-rate fight.
- `godot/tests/drops_swaps_checks.gd` (issue #17) replays the Python prototype's captured drop and swap cases
  (`godot/tests/reference/drops_swaps.json`, regenerated by `tools/reference/capture_drops_swaps.py`) on the real
  simulation: all 36 type x rarity x element swords, the armed health, every arming roll and rarity threshold, drops
  on death, a pickup's life under pause, hitstop and slow motion, the 80 px reach and nearest / tie rules, 36 swaps
  with ready, part-spent and full recharges, ten in a row, the swapped-in sword's flight tick by tick, keys, pause,
  death and restart, plus the pickup card, slot cards, effects and a render-rate fight.
- `tools/godot/mutation-check.sh` applies deliberate bugs (zero speed, ignored
  pause, stale restart, ...) to a scratch copy and requires the checks themselves to
  reject each one; a crash or timeout is reported as inconclusive, not as caught.
  See *Mutation checks* below for the per-PR procedure.
- `tools/godot/test-build-failures.sh` runs `build-godot.sh` in sandboxes against
  representative failures (plus crashed-and-retried steps and overlapping runs) and
  requires the specific exit code and no new or damaged pair.

### Mutation checks

The checker lists every deliberate bug (nearly 1,000) in sections, one per slice
(`# --- <title> (slice #N)` in the script), after an ungrouped `core` block of
simulation basics (speed, pause and resume, restart, the diagonal and wall clamps).
A mutation is **caught** only when `run_checks.gd` itself rejects it (exit 1, a
`CHECKS FAILED` verdict, at least one `  FAIL` line, no script error); a crash,
timeout or missing verdict is **inconclusive**; a project the checks accept is
**survived**. Either of the last two fails the run.

How it is fast. Nearly all of a complete `run_checks.gd` run (about 45 s) is the
render-rate probes, sub-Godot processes at 5/20/60/240 fps, and most of the rest is
the groups the mutation has nothing to do with. So each mutation is judged in steps
(the **fast** mode, the local default), each only when the one before found nothing:

1. **Focused**: `run_checks.gd -- --fail-fast --skip-probes --focus=<group>` runs the
   checks of the mutation's own section (`warden_maelstrom` for the Warden section;
   `core` runs only `run_checks.gd`'s own checks) and stops at the first failing one.
   Most mutations end here, in about two seconds.
2. **Quick**: the same without `--focus`, over every group.
3. **Full**: the same with the probes. Only a complete `CHECKS PASSED` here makes a
   mutation a survivor.

Steps 1 and 2 end in `CHECKS PARTIAL` (never `CHECKS PASSED`, which the build
requires) when nothing failed; so does any run with a `--focus`, even `--focus=none`
or one naming every group. They run a subset of the full run's checks, so a
failure there is a failure of the full run too. Crashes, timeouts and script errors
in a step that never reached a clean failure stay inconclusive.

**Fast and classic modes differ in one case.** `FAST=0` is the **classic** mode: one
complete, non-fail-fast run per mutation, probes included, and the strict definition of
*caught*: the whole run must end in the ordinary failure verdict, so a mutation that
fails a check cleanly but then crashes, times out or hits a script error in a *later*
check is **inconclusive**. The fast mode stops at the first clean failure and never
reaches those later checks, so it counts that mutation as **caught** locally: a clean
assertion failure reported through `run_checks.gd`'s verdict path is genuine
behavioural evidence, and the fast mode trades the later-crash information for speed.
**The CI full pass runs the classic mode** (`FAST=0` in `mutation.yml`) and is the
authoritative verdict; a mutation the fast mode called caught that crashes later turns
up there as inconclusive. `tools/godot/test-mutation-runner.sh` pins this: the same
crash-after-failure mutant must be caught in fast mode and inconclusive in classic mode.

A check group takes part by starting its `run_all()` with
`if not CheckFocus.includes("<file name without _checks.gd>"): return` and its
render-rate check with `if not RenderRateScenario.probes_enabled(): return`, as the
existing groups do. A group without those lines is not wrong, only slower: it runs
in every step. The section's group is found by the table in the script (the early
slices) or, for a later section, by a group file whose name starts with the section's
key (`pike` finds `pike_skewer_checks.gd`).

Selection (all of these compose):

| Variable | Effect |
| --- | --- |
| `SECTIONS=pike,warden` | only those sections **plus `core`**. A section is the first word of its header title (`SECTIONS=list` prints them) or its slice number (`SECTIONS=14`). `CORE=0` leaves core out; unset or `all` selects every section. An unknown name is refused. |
| `ONLY=name,name` | only the named mutations (an unknown name is refused); combined with `SECTIONS`, only those inside the chosen sections. |
| `SHARD=i SHARDS=n` | every n-th mutation of the selection starting at `i`, so `n` copies run in parallel over the same list. |
| `FAST=0` | the strict classic mode described above (default `FAST=1`). |

A new section needs no registration: append its `mutate` lines under a
`# --- <title> (slice #N)` header and it becomes selectable.

Per-PR procedure for a slice:

1. While developing, run the sections the PR touches plus `core`, split over the
   cores you have: `SECTIONS=pike,core` (core is implied) with `SHARD=$i SHARDS=8`
   in eight terminals, or a single process for a small section. It needs the pinned
   Godot: `./build-godot.sh --bootstrap-only` first.
2. After fixing a check or the code a survivor pointed at, rerun only those
   mutations: `ONLY=name,name tools/godot/mutation-check.sh`. Do not repeat the
   whole section for each fix.
3. Do not run the full pass for the PR. After merge, the *Mutation checks* workflow
   runs every section on `main` in the classic mode (12 shards), and its *all shards*
   job fails unless the whole matrix succeeded and every shard's result file is
   present, records exit status 0 and shows every mutation caught (no survivor, no
   inconclusive, none not applied). A failed, cancelled or timed-out shard fails it
   even if the other shards' files look clean. A survivor found there is fixed in a
   follow-up with `ONLY=`.

Each shard prints one line per mutation (with its time) and ends with
`RESULT shard=… mode=… ran=… caught=… survived=… inconclusive=… not_applied=…`.
`caught` counts only mutations that were applied and cleanly rejected. A mutation
whose search text no longer matches exactly once is **not applied**: reported on its own
line (`MUTATION NOT APPLIED: <name>`), never caught, and it fails the run. The checker
itself is covered by `tools/godot/test-mutation-runner.sh` (stale mutations, the
crash-after-failure difference, `CHECKS PARTIAL` for focused runs, and the CI summary
logic against synthetic result sets); run it by hand when `mutation-check.sh`,
`mutation-summary.sh` or the workflow change.

## Layout

```
godot/
├── scripts/sim/            GameRun (owns run state, 60 Hz step), GameCommand, RunScenario,
│                           SwordState/SwordDefs, EnemyState, Mote, WaveDirector, SimCue
├── scripts/input/          InputTranslator (keyboard), TouchJoystick (per-pointer)
├── scripts/presentation/   ActorVisual / SwordVisual / EnemyVisual contracts + placeholder
│                           drawn visuals, RunPresenter, EffectsLayer
├── scripts/main.gd         wiring: input -> commands -> run -> visual
├── scripts/hud.gd, audio/  overlay UI, baked sound effects
└── tests/                  headless checks (excluded from exports)
```

Replacing the art: point `Main.actor_visual`, `Main.sword_visual` or
`Main.enemy_visual` (in `scenes/main.tscn`) at a scene whose root extends
`ActorVisual`, `SwordVisual` or `EnemyVisual`. Gameplay never reads a visual and
hit geometry never follows texture size.

Sound effects are baked WAVs; the recipe is `tools/godot/gen_audio.py`.
`godot/icon.ico`/`icon.png` come from `godot/icon.svg` via `tools/godot/make_icon.gd`.

## Controls

W A S D or arrow keys move · Space or Shift dash · Q / E / R trigger the ultimate of
sword slot one / two / three at the mouse (Viper Flurry for a Fang, Maelstrom for a Warden, Skewer for a Pike) · P or Esc pause/resume ·
R also restarts once the death screen is up (while alive it is only the slot-three
ultimate) · touch (no ultimate buttons yet, issue #20): drag in the left part of the screen to move, on-screen
Dash, Pause and Restart buttons (Restart always works, also after surviving the
wave). The three spirit swords attack on their own. The first
click/tap/key unlocks sound (browsers require a gesture). Losing focus or
backgrounding pauses the run and releases all input; resume is explicit.
