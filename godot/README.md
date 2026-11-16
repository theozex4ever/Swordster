# Swordster (Godot port)

Godot 4 port of Swordster, built slice by slice. Currently playable: a complete
Fang survival loop (move, dash, three spirit swords attacking on their own, telegraphed waves, healing motes, death and restart) with **Viper
Flurry** on Q / E / R (each sword slot's ultimate, aimed at the cursor), a **crowd
encounter** with runners and brutes, crowd bowling and wall slams, a **spitter
encounter** with ranged foes, enemy orbs and sword parries, **elemental conditions**
(burn, poison, chill and freeze on every blow) and **Warden**, the sword of sweeping
arcs, with its **Maelstrom** ultimate (a **warden encounter** equips it), and **Pike**,
the sword of long piercing thrusts, with its **Skewer** ultimate (a **pike encounter** equips it), and **Colossus**,
the sword of crushing slams, with its **Cataclysm** ultimate and the elemental ground field it leaves (a **colossus
encounter** equips it), **Converge** (click), the prototype's **default loadout** (Fang, Warden, Colossus: the normal start) and
**armed enemies, sword drops and swaps** (a **drops encounter**) and, in the normal run, the prototype's own **waves without end**
(`5 + 3 w` enemies a wave from a pool that unlocks runners, brutes and spitters, foes growing 10 % tougher a wave, armed foes carrying swords of
growing rarity, a break between waves, a chain and a kill count) on top of the delivery-proof arena, exported to Windows
and Web from one Linux command. The Python/Pygame prototype in `game/` stays the behavioural reference
and keeps working. Reference values, tolerances and deliberate exceptions:
[Fang survival loop](../docs/reference/fang-survival-loop.md) (#8) and
[runners, brutes and crowds](../docs/reference/runners-brutes-crowd.md) (#9) and
[spitters, projectiles and parries](../docs/reference/spitters-projectiles-parries.md) (#10) and
[Viper Flurry](../docs/reference/viper-flurry.md) (#12) and
[elemental conditions](../docs/reference/elemental-conditions.md) (#11) and
[Warden and Maelstrom](../docs/reference/warden-maelstrom.md) (#13) and
[Pike and Skewer](../docs/reference/pike-skewer.md) (#14) and
[Colossus and Cataclysm](../docs/reference/colossus-cataclysm.md) (#15) and
[drops and swaps](../docs/reference/drops-swaps.md) (#17) and
[waves and the normal run](../docs/reference/waves.md) (#18).

### Viper Flurry (Q / E / R)

Each sword slot has an ultimate triggered by its key: **Q** slot one, **E** slot two,
**R** slot three (R is also the restart key once the death screen is up). Point the
mouse and press: the sword blinks to the cursor (at most 420 px from you), darts between
the enemies inside the 150 px area for 1.25 s (one dart every 0.08 s, 1.2x the sword's
damage), then recovers. The ultimate recharges for 9 s (shorter for Rare and Mythic
swords) from the moment it starts; the cards at the bottom left show READY, ACTIVE or
the seconds left, with the sword type under the bar. The normal run equips the prototype's default loadout, so Q holds Viper Flurry (Fang, poison), E Maelstrom (Warden, ice) and R
Cataclysm (Colossus, fire); the crowd, spitter and conditions encounters keep the three-Fang fixture loadout, so every slot
holds Viper Flurry there; the warden encounter below equips a Fang
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
Warden (ice, E) and Warden (fire, R). This mixed loadout is a development fixture, not the default
loadout (the normal run equips Fang, Warden and Colossus).

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
aim north. This is a development fixture, not the default loadout.

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
Q, E and R with the cursor on the crowd and watch all three fields. This is a development fixture, not the default
loadout.

### Converge and the default loadout

Slice #16 ([reference](../docs/reference/converge.md)). A new run starts with the prototype's **default loadout**: Fang
(poison), Warden (ice) and Colossus (fire), all Common, in sword slots one to three (Q, E, R). **Converge** is the
player's coordinated command, not an ultimate: **left or right click** sends all three swords to strike the cursor's world point
at once (a point more than 460 px from you is pulled back onto that range). Every sword that is not in the middle of a strike,
stuck in the floor after a slam or in its ultimate drops what it is doing and attacks that point with 0.6x its normal windup and
1.5x its damage, aimed at the enemy nearest the point if one is within 90 px of it. Each sword type makes its own attack of
it (Fang dashes, Warden sweeps, Pike thrusts, Colossus slams), and the sword's automatic attacks carry on afterwards. The
command is shared: after one the next waits 2.5 s (the **converge** line under the dash cooldown counts it down), and it
is refused while paused or dead. **Tab** or **G** shows a ring around you for each sword's attack range. A click on the HUD's
own buttons is not a Converge, and neither is a mouse click the engine makes up from a touch (the touch controls arrive with
issue #20). The aim follows the camera, so it stays right when the window is resized.

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
armed for sure, the first with a Pike). This is a development fixture; the **normal run arms its waves by the same rule**
(see [The normal run](#the-normal-run-waves-without-end)), so the drops, the card and the swap keys are part of ordinary play.

### The normal run: waves without end

With no `--encounter` the game is the prototype's own: after 1.6 s wave 1 arrives (eight husks, the first two armed, the
first with a Pike), each enemy telegraphed for 0.7 s by a marker where it will stand, 0.3 s after the wave starts and then
every `max(0.12, 0.42 - 0.02 w)` s. A wave has `5 + 3 w` enemies drawn from a pool that grows: husks always, **runners and
brutes from wave 2, spitters from wave 3**, brutes weighing more every wave. Foes are `1 + 0.1 (w - 1)` times as tough
(1.35 times more when armed). **Nothing caps how many arrive**: wave 30 puts 95 enemies in the arena. A wave is over only when
its queue, its markers and every living enemy are gone: then comes **WAVE CLEARED**, 0.7 s of slow motion, the sword drops to
claim, and 3.2 s later the next wave. Armed foes arm by kind (husk 20 %, runner 12 %, spitter 22 %, brute 75 %) and the swords
they carry get better with the wave: Mythic below `min(25 %, 2 % + 2 % w)`, Rare below `min(55 %, 16 % + 4 % w)` (brutes carry
better). The wave line shows the wave, your kills and, from three in a row, the chain; a chain of 10, 25, 50 and 100 is announced
over you; healing motes (three a kill, half a point each) are the only healing. There is no end: a run is only lost (**R** restarts).
Fixtures and the other dev encounters are unchanged.

### Visual sets: replacing the player and sword art

Slice #21 ([artist guide](../docs/art/replacing-visuals.md)). The player and the spirit swords are replaceable
views (ADR 0003); a **visual set** names which scenes draw them. `placeholder` (the default, the shipped look) draws
them procedurally; `textured` draws texture sheets (`godot/art/placeholder/`, original placeholder drawings made by
`tools/godot/gen_placeholder_art.gd`) with their own sizes, pivots, orientation and animation clips, kept in two
settings resources. Pick one at launch: `Swordster.exe -- --visuals=textured` or `index.html?visuals=textured`
(it composes with `--encounter=`); anything else keeps the default. Scale, pivot, orientation and clips are
presentation only: `visual_replacement_checks.gd` replays the scripted fights of earlier slices with the drawn look,
the textured look and hostile replacements (other texture sizes, pivots, orientation, animation speed and length)
and requires identical per-tick movement, hit geometry, damage, timing, cooldowns and targets.

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
(shove them straight into the wall). The normal run plays the prototype's own waves.

### The spitter encounter

A development fixture for slice #10: one wave of five spitters among three husks against
the same three-Fang loadout. Spitters back away when you are within 260 px, circle out to
380 px, glow at the snout for half a second (a dashed line shows the heading) and spit an
orb at 270 px/s that hurts for 8 unless you are invulnerable (a dash gives 0.24 s). A Fang
strike that sweeps through an orb **parries** it: green flash, sparks and a `PARRY` tag, no
damage numbers. Start in it with `Swordster.exe -- --encounter=spitters` or
`index.html?encounter=spitters`, or reach it with the dev button / `C` (after the crowd).
The prototype only brings spitters in from wave 3; the normal run brings them then.

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
  tests the checks themselves, not the build) has its own workflows: `mutation-gate.yml`
  runs the full pass in the fast mode on every pull request except one that changes only docs and
  repository-level Markdown (a deny list: a build dependency such as `build-godot.sh`, `game/` or `build.yml` gates it by
  default) and on every push to `main` (blocking, 8 shards), and `mutation.yml` runs the
  strict classic pass weekly and on manual dispatch (both call `mutation-pass.yml`, which
  shards the list and judges the shards). See *Mutation checks* under *Checks*.
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
  recharge, refusals, pause/death, conditions, plus the HUD, effects and a replacement-visual fight.
- `godot/tests/pike_skewer_checks.gd` (issue #14) replays the Python prototype's captured Pike and
  Skewer cases (`godot/tests/reference/pike_skewer.json`, regenerated by
  `tools/reference/capture_pike_skewer.py`) tick by tick on the real simulation: targeting preference,
  thrust geometry at 228 probe points, piercing without gaps, parries, the Skewer's aim, flight, impalement,
  carry and release at the range and at every wall and corner, enemies that die or leave the run while
  impaled, conditions, plus the HUD, effects and a replacement-visual fight with wall slams.
- `godot/tests/colossus_cataclysm_checks.gd` (issue #15) replays the Python prototype's captured Colossus,
  Cataclysm and field cases (`godot/tests/reference/colossus_cataclysm.json`, regenerated by
  `tools/reference/capture_colossus_cataclysm.py`) tick by tick on the real simulation: cluster targeting, the windup,
  the fall's timing from different altitudes, area damage and falloff at 56 + 12 probe points, hitstop and shake,
  projectile clearing, Cataclysm's rise, fall and field, every element's doses and cadence, overlapping fields,
  expiry, deaths by condition, corpses, pause and restart, plus the HUD, effects and a replacement-visual fight.
- `godot/tests/drops_swaps_checks.gd` (issue #17) replays the Python prototype's captured drop and swap cases
  (`godot/tests/reference/drops_swaps.json`, regenerated by `tools/reference/capture_drops_swaps.py`) on the real
  simulation: all 36 type x rarity x element swords, the armed health, every arming roll and rarity threshold, drops
  on death, a pickup's life under pause, hitstop and slow motion, the 80 px reach and nearest / tie rules, 36 swaps
  with ready, part-spent and full recharges, ten in a row, the swapped-in sword's flight tick by tick, keys, pause,
  death and restart, plus the pickup card, slot cards, effects and a replacement-visual fight.
- `godot/tests/waves_checks.gd` (issue #18) replays the Python prototype's captured wave cases
  (`godot/tests/reference/waves.json`, regenerated by `tools/reference/capture_waves.py`) on the real simulation: the
  composition pool and unlocks of waves 1 to 30, the kind a draw picks at every cumulative weight, health per wave, the
  tick every marker appears and enemy arrives for ten waves, 384 scripted spawn positions and the twelve-refusals
  fallback, the armed share, rarity mix, sword types and elements of nine sampled waves (as distributions, never a random
  stream), the first wave's Pike, completion with every combination of queue, marker and standing enemy, the clear, the
  slow motion, the break and the next wave tick for tick, pause and hitstop, death and restart, 130 kills and the chain
  announcements, healing, nine waves played through with controlled kills, wave 30's 95 enemies standing at once, the
  armed first wave against the prototype's, the HUD and banners (and the pickup card clear of them), and the real Main
  scene with replaced visuals and different camera-shake and effects random streams.
- `godot/tests/render_rate_checks.gd` (issue #41) is the one place the engine's frame rate is varied. The
  simulation is stepped at a fixed 60 Hz from the physics loop and the presentation only reads it, so frame-rate
  independence is a property of shared code, not of any slice. One scripted fight (`combined_fight.gd`) is played with
  bare `GameRun.step()` calls and through the real Main scene in child Godot processes at 5, 20, 60 and 240 fps (started
  together, at most four at a time, each batch under a deadline). Segment 0 is the mechanics: every sword type, every
  ultimate, Converge, every enemy type (standing packs, and four stalkers that really walk across the arena: the fight
  records how far each type walked and fails if one did not), all three conditions, fields, orbs and parries, a bowled
  crowd and wall slams, drops and swaps. Segment 1 restarts into the normal run and plays a wave transition: spawn
  markers, arrival, an armed enemy's drop, the clear with its slow motion and banner, the break and the next wave. The
  fight fails if it stops exercising any of that (`REQUIRED_CUES`, `REQUIRED_WAVE_CUES`, `REQUIRED_TRAVEL` and the
  wave observations). What is compared is `GameRun.state_digest()`: the **whole run state by reflection** (every
  script variable of the run and of every object it reaches: the player with its dash, cooldowns and iframes,
  each sword's full state, each enemy with its conditions, projectiles, fields, pickups, motes, the wave director with
  its queue and markers, Converge's cooldown, counters and clocks, and the gameplay random generator's seed and
  state). It is hashed every 50 ticks and kept in full at the end of each segment; every checkpoint must be equal at
  every rate. The group also checks the digest itself: it pins the few members it leaves out (`GameRun.STATE_DIGEST_EXCLUDED`,
  each with a reason), and changes every plain value of the run, and of one instance of every class it reaches, to
  require that the digest notices. It also checks the `--encounter=` launch options, which are only read at engine
  start, and requires every child process to end with exit status 0 **and** valid output. It replaced nine per-slice probes
  that each replayed their own slice's fight at four rates and made up about 70% of a suite run (about 64 s of a 90 s
  suite on an idle machine; the group is now about 8 s).
  **Adding frame-rate coverage for a new mechanic never means a new probe.** Four small edits in `combined_fight.gd`,
  in this order: (1) put the new foes in `scenario()` (segment 0) or the wave rules in `waves_scenario()` (segment 1);
  (2) put the new commands in the `script()` list (one `_step(tick, kind, slot, aim)` each; `commands_at` plays it
  for segment 0 only); (3) add a minimum count of the new cue to `REQUIRED_CUES` (or `REQUIRED_WAVE_CUES`), and a counter
  to `counters_of()` if the cue is not there yet, so the fight fails if it ever stops exercising the mechanic; (4) nothing
  for the digest: a member of any class the run holds is in `GameRun.state_digest()` by reflection the day it is
  declared. Only state that must stay out of it (a static input, a queue the presentation drains) is added to
  `GameRun.STATE_DIGEST_EXCLUDED` with its reason and to `EXPECTED_EXCLUDED` in `render_rate_checks.gd`, which is a
  reviewed decision. A new CLASS of state is picked up when the run holds an instance, but add it to `EXPECTED_CLASSES`
  too, so the digest check keeps proving it is reached. Keep `FIGHT_TICKS` / `WAVES_TICKS` past the last step and the
  player alive (the check says what is missing). Tune the step ticks with the fight's own recharges in mind (a press at
  a tick the sword is still recharging is refused, which counts as an ultimate not started).
- `tools/godot/mutation-check.sh` applies deliberate bugs (zero speed, ignored
  pause, stale restart, ...) to a scratch copy and requires the checks themselves to
  reject each one: a genuine failing check is the only evidence that counts, and a crash or timeout
  with no failing check is reported as inconclusive, not as caught. It gates every pull request
  that touches the game. See *Mutation checks* below for the procedure.
- `tools/godot/test-build-failures.sh` runs `build-godot.sh` in sandboxes against
  representative failures (plus crashed-and-retried steps and overlapping runs) and
  requires the specific exit code and no new or damaged pair.

### Mutation checks

The checker lists every deliberate bug (about 1,100) in sections, one per slice
(`# --- <title> (slice #N)` in the script), after an ungrouped `core` block of
simulation basics (speed, pause and resume, restart, the diagonal and wall clamps).
Each mutation gets one of these verdicts:

| Verdict | Meaning | Effect on the run |
| --- | --- | --- |
| `caught` | the standard output holds at least one genuine failing check (a line that starts with `  FAIL[<token>] `, printed by `run_checks.gd` with the random token the checker made for that run and passed as `--verdict-token=`; a `FAIL` line without the token, inside an engine error message or on standard error, such as a `push_error` whose text contains a newline and `  FAIL`, does not count) and the run ended in the ordinary failure verdict | none |
| `caught-with-warning` | a genuine failing check, **then** a crash, script error, timeout or hang | none: still a rejection by a failing check, listed on its own line and in the CI summary as a hygiene warning |
| `INCONCLUSIVE` | no failing check, and a crash, script error, timeout or no verdict at all: nothing was proved (retried once first) | fails the run |
| `SURVIVED` | the complete suite accepts the broken project | fails the run |
| `MUTATION NOT APPLIED` | the search text no longer matches exactly once, so no bug was planted | fails the run |

A check that crashes or hangs once it runs on a broken project is a bug in the checks, not a gap in
coverage, and a hang already fails the normal build, which has a time limit; so the verdict follows the
evidence: one failing check is a rejection, whatever follows it. The `caught-with-warning` lines are the
list of checks worth hardening.

How it is fast. Nearly all of a complete `run_checks.gd` run is the groups the mutation has nothing to do
with, and the render-rate group (child Godot processes, see *Checks*). So each mutation is judged in steps
(the **fast** mode, the default, and the pull-request gate), each only when the one before found no genuine failing check:

1. **Focused**: `run_checks.gd -- --fail-fast --skip-probes --focus=<group>` runs the
   checks of the mutation's own section (`warden_maelstrom` for the Warden section;
   `core` runs only `run_checks.gd`'s own checks) and stops at the first failing one.
   Most mutations end here, in about two seconds.
2. **Quick**: the same without `--focus`, over every group.
3. **Full**: the same with the render-rate group. Only this step decides what is not a rejection: a complete
   `CHECKS PASSED` makes a mutation a survivor, and a crash, timeout or no verdict with no failing check makes it
   `INCONCLUSIVE`.

Steps 1 and 2 decide only by a genuine failing check: whatever else they end with (a clean partial run, but also a
timeout, a crash or a script error with no failing check) is no evidence, and the next step runs. They end in `CHECKS PARTIAL` (never `CHECKS PASSED`, which the build
requires) when nothing failed; so does any run with a `--focus`, even `--focus=none`
or one naming every group. They run a subset of the full run's checks, so a
failure there is a failure of the full run too. Each `caught` line ends with the step that caught it
(`[focused, 2.1s]`); a mutation shown as `[full, ...]` is rejected only by the render-rate group.

**Fast and classic modes differ in one case.** `FAST=0` is the **classic** mode: one
complete, non-fail-fast run per mutation, render-rate group included. It keeps running after the first
failing check, so it is the mode that finds the checks that crash or hang *later* on a broken project: those
are the `caught-with-warning` lines. The fast mode stops at the first failing check and never reaches them, so
it says plain `caught`. `tools/godot/test-mutation-runner.sh` pins this: the same crash-after-failure mutant is
`caught` in fast mode and `caught-with-warning` in classic mode, and a crash with no failing check is
`INCONCLUSIVE` in both.

A check group takes part by starting its `run_all()` with
`if not CheckFocus.includes("<file name without _checks.gd>"): return`, as the existing groups do (a group
without that line is not wrong, only slower: it runs in every step). The render-rate group also starts with
`if not RenderRateScenario.probes_enabled(): return`, which is what the quick steps skip.
The section's group is found by the table in the script (the early slices) or, for a later section, by a
group file whose name starts with the section's key (`pike` finds `pike_skewer_checks.gd`).

**Checks must end when the code under test is broken**, because a mutation can break exactly what a check waits
for. Every loop in a check group is bounded, and above all **every loop that walks the encounter cycle
(`toggle_encounter` until some encounter comes round) and every wait for a state** (`while not run.dead`,
`while sword.phase != ...`, waiting for a pickup, a cue or a field) counts steps next to the real condition and
gives up at a limit, failing a check with the count it reached instead of spinning (an unbounded walk of the
cycle was the cause of ten hangs on PR #40). A group whose fixtures are built
from the prototype's sword keys verifies the keys first and skips the rest with a failure when one is wrong (a renamed
key would otherwise crash it: a script error with no failing check is *inconclusive*), and a check never indexes what an
earlier failing check may have left empty. Child processes are run with a deadline (`render_rate_checks.gd`). A timeout,
hang or script error that follows a failing check is a `caught-with-warning`: harmless to the verdict, but fix the
check when you see it.

Selection (all of these compose):

| Variable | Effect |
| --- | --- |
| `SECTIONS=pike,warden` | only those sections **plus `core`**. A section is the first word of its header title (`SECTIONS=list` prints them) or its slice number (`SECTIONS=14`). `CORE=0` leaves core out; unset or `all` selects every section. An unknown name is refused. |
| `ONLY=name,name` | only the named mutations (an unknown name is refused); combined with `SECTIONS`, only those inside the chosen sections. |
| `SHARD=i SHARDS=n` | every n-th mutation of the selection starting at `i`, so `n` copies run in parallel over the same list. |
| `FAST=0` | the strict classic mode described above (default `FAST=1`). |
| `QUICK_TIMEOUT=60 FULL_TIMEOUT=120` | seconds a focused or quick step, and a full or classic run, may take (the runner's regression test shortens them). |

A new section needs no registration: append its `mutate` lines under a
`# --- <title> (slice #N)` header and it becomes selectable.

Procedure for a slice (what an implementer does, and what CI does):

1. While developing, run **only your own sections** plus `core`, locally: `SECTIONS=pike`
   (core is implied; `SECTIONS=list` shows the names). A section of about 220 mutations takes
   about 18 minutes in one process on a busy machine (4 to 5 s a mutation: nearly all of it is starting the engine and
   the section's own checks), so split a big one over the cores you have with `SHARD=$i SHARDS=4` (about 5 minutes). It needs the
   pinned Godot: `./build-godot.sh --bootstrap-only` first.
2. After fixing a check or the code a survivor pointed at, rerun only those
   mutations: `ONLY=name,name tools/godot/mutation-check.sh`. Do not repeat the
   whole section for each fix.
3. **Do not run the full pass yourself.** The pull request's *Mutation gate* job (`mutation-gate.yml`) is the full
   pass: every mutation of the list in the fast mode, split over 8 shards, in about 7 minutes of wall time (measured: 7 min on the pull request that introduced it). It runs on
   every pull request except one that changes only `docs/**`, repository-root Markdown or issue templates (a `paths-ignore`
   deny list, so any file not named there, build dependencies included, gates the pull request), and on every
   push to `main`, and it is **blocking**: its *all shards* job fails unless every shard ran and recorded exit status 0,
   the shards together covered the whole list (the summary derives the expected share of each shard from the list itself:
   a missing, duplicate, extra, filtered or short shard fails it, and so does a shard that ran in the wrong mode), and every
   mutation was caught (no survivor, none inconclusive, none not applied). A new push to the pull request cancels the
   superseded run. A local full pass is optional (`tools/godot/mutation-check.sh` with `SHARD=i SHARDS=4` in four
   terminals, about 20 minutes), useful before a large refactor of the checks themselves.
4. The strict **classic** pass (`mutation.yml`, `FAST=0`, 24 shards) runs weekly (Monday 03:17 UTC) and on manual dispatch
   (Actions → *Mutation checks (classic, weekly)* → *Run workflow*, on any branch). It reports the hygiene warnings
   (`caught-with-warning`) without failing on them; it fails on a survivor, an inconclusive mutation or a stale one. A
   survivor found by either run is fixed in a follow-up with `ONLY=`.

Each shard prints one line per mutation (with its time) and ends with
`RESULT shard=… mode=… ran=… caught=… warned=… survived=… inconclusive=… not_applied=…`.
`caught` counts the mutations rejected with the ordinary failure verdict, `warned` the `caught-with-warning` ones.
A mutation whose search text no longer matches exactly once is **not applied**: reported on its own
line (`MUTATION NOT APPLIED: <name>`), never caught, and it fails the run. The checker
itself is covered by `tools/godot/test-mutation-runner.sh` (stale mutations, the verdict function on synthetic
logs, the crash-after-failure and crash-without-failure cases in both modes, `CHECKS PARTIAL` for focused runs, and the
CI summary logic against synthetic result sets); run it by hand when `mutation-check.sh`,
`mutation-summary.sh` or a mutation workflow changes.

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
