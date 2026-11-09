# Sharing a Swordster build on itch.io (manual setup and device checks)

Procedure for the maintainer to put one build on one unlisted itch.io page (browser play plus a
free Windows download) and to collect real-device evidence. It covers issue
[#6](https://github.com/theozex4ever/Swordster/issues/6) of the Godot port
([#4](https://github.com/theozex4ever/Swordster/issues/4)). **Nothing here has been done yet:**
no page exists, nothing was uploaded and no device has run a build. Record results in
[`itchio-evidence.md`](itchio-evidence.md); every result there starts as `UNVERIFIED`.

This is the manual, first-time path through the itch.io website. Automated publication
(butler/CI), retention and rollback belong to issue #7 and are not described here.

Placeholders used below: `<ITCH_USERNAME>`, `<PROJECT_SLUG>`, `<PAGE_URL>` (the page's address
once it exists), `<BUILD_ID>`. They are never real values in this repo.

## 1. Only you can provide

- A free **itch.io creator account** you are authorised to use, and the decision on which
  account/project hosts the page. Sign in yourself in your own browser. Do not put a password,
  API key or session cookie in the repo, a PR, an issue or a chat. (No API key or butler is needed
  for this procedure: uploads go through the website.)
- **Real devices**, none of which may be the Linux build machine:
  - a Windows 10 x86_64 machine and a separate Windows 11 x86_64 machine, both **without Python
    or Godot installed**;
  - desktop **Chrome** and desktop **Firefox** (any OS you have);
  - a **physical Android phone** with **Chrome**.
  A target you cannot test stays `UNVERIFIED` in the evidence record. A VM is not the same as
  "another machine": if you use one, label it as a VM.
- A second browser session with no itch.io login (private window, or a browser profile that is
  signed out) for the signed-out checks.

## 2. Build and package

From a clean checkout of the commit you want to test (an unclean tree gives a `-dirty` build id;
do not upload one). Linux, from the repo root:

```bash
./build-godot.sh
```

The first run downloads the pinned Godot (about 1.4 GB); later runs reuse `~/.cache/swordster/`.
Full details and exit codes: [`godot/README.md`](../godot/README.md). On success it prints
`BUILD OK: <BUILD_ID>` and creates:

```text
dist/<BUILD_ID>/
├── Swordster-<BUILD_ID>-windows.zip     upload as-is (the Windows download)
├── Swordster-<BUILD_ID>-web/            folder of the Web export (NOT directly uploadable, see below)
├── BUILD-INFO.json
└── SHA256SUMS
```

`<BUILD_ID>` looks like `YYYYMMDD-HHMMSS-<9 hex commit chars>`.

### Make the itch.io Web ZIP

itch.io needs the Web files in one ZIP with `index.html` at its top level. The build produces the
Web files as a folder, not that ZIP, so create it from the pair you just built (bash; needs only
the `python3` the build already requires). The ZIP goes next to, not inside, `dist/<BUILD_ID>/`,
so the pair stays exactly as built:

```bash
ID=<BUILD_ID>                                  # e.g. the id printed by ./build-godot.sh
OUT="$PWD/dist/_itch-upload/Swordster-$ID-web.zip"
mkdir -p "${OUT%/*}"; rm -f "$OUT"
(cd "dist/$ID/Swordster-$ID-web" && python3 -m zipfile -c "$OUT" *)

python3 -m zipfile -l "$OUT"                   # index.html must be listed with no folder prefix
V="$(mktemp -d)"; python3 -I -m zipfile -e "$OUT" "$V"
python3 -I tools/godot/pack.py verify-manifest "$V/SHA256SUMS" "$V"   # expect: 10 files listed, 0 problems
rm -rf "$V"
```

The last two commands prove the ZIP's contents are the files the build recorded in the pair's
Web `SHA256SUMS`. Optional local smoke test before uploading: extract the ZIP into an empty folder
and run `python3 -m http.server` inside it (see `godot/README.md`).

Upload exactly these two files, from the same `dist/<BUILD_ID>/`, so both channels carry one build:

| Channel | File |
|---|---|
| Windows download | `dist/<BUILD_ID>/Swordster-<BUILD_ID>-windows.zip` |
| Web play | `dist/_itch-upload/Swordster-<BUILD_ID>-web.zip` |

Sizes seen when this procedure was run locally on build `20261109-055628-38df7acb2` (that build
only; expect similar, not identical, values): Windows ZIP 39,252,215 bytes; Web upload ZIP
10,407,144 bytes; largest single Web file `index.wasm` 39,514,754 bytes; 11 files in the Web ZIP.
Those are well inside the HTML limits itch.io documents (1,000 files, 500 MB extracted, 200 MB per
file, 240-character paths; section 8).

## 3. Create the page

Dashboard → Create new game (itch.io's wording: "hit the Create new game button"). Use these
settings; the right-hand column says where itch.io's own documentation states it.

| Setting | Value | Documented at |
|---|---|---|
| Kind of project | **HTML** ("HTML Game" in the Kind Of Game list) | html5 |
| Pricing | **No payments** (all payments off, all files freely downloadable) | pricing |
| Visibility & access | **Public**, with **Unlisted in search & browse** ticked | access-control |
| Creator profile | remove this project from your profile via the **profile theme editor** | access-control (see flag A) |
| Title / URL | your choice; the URL slug is generated from the title (`<PROJECT_SLUG>`) | getting-started |

Do the visibility change in one step: choose Public and tick Unlisted before saving, so the page
is never briefly listed. New pages start private (Draft), which lets you check the page with
**Save & view page** before publishing (getting-started). Unlisted is not confidentiality: anyone
with the link can open it, and itch.io's wording is that the page won't show in itch.io browse and
search and external search engines are *instructed* to ignore it (access-control).

## 4. Upload and configure

1. Upload `Swordster-<BUILD_ID>-windows.zip` and `Swordster-<BUILD_ID>-web.zip` as two files on
   the page. Keep the file names: the build id in them is how you tell later which build is where.
   itch.io says uploads can be tagged by platform (getting-started). Tag the Windows file as
   Windows (see flag B).
2. Mark the Web ZIP as the file to **play in the browser**. After itch.io accepts a file for
   embedding you get an **Embed options** section (html5). The Web ZIP is that file. The Windows
   ZIP must stay a normal download (see flag B for how itch.io labels this).
3. Embed options (all from html5; the specific values are suggestions):
   - **Embed in page**, viewport **1280 × 720** (the project's own base resolution; the game
     scales to its window, so this is a size choice, not a requirement);
   - leave **Click to Play** on (the default);
   - itch.io's **Fullscreen Button** on: the game itself has no fullscreen control;
   - **Scrollbars** off;
   - **Mobile Friendly: leave off for now.** Enable it only after the Android Chrome check passes
     (section 6), then re-check on the phone (see "What Mobile Friendly changes").
4. After saving, itch.io needs a moment to process the archive on first load (html5). Wait for it
   before testing.

### What Mobile Friendly changes (html5)

On a mobile browser itch.io then always uses "Click to launch in fullscreen" regardless of the
desktop embed setting. With it off, a mobile viewer sees a warning that the game may not work but
can still start it. That is why the first Android run happens with it off, and the page is
re-tested on the phone after turning it on.

## 5. Confirm anonymous access

In a signed-out private window (nothing signed in to itch.io):

1. Open `<PAGE_URL>`. The game page loads and the game starts after you click the launch/play
   control, with **no login prompt and no payment/donation prompt**.
2. The Windows file downloads directly: no login, no payment or donation prompt (no-payments
   pricing is documented as "freely downloadable"; free downloads create no download key, so an
   account should not be needed, but itch.io does not say "anonymous" in so many words, so this
   check is the evidence).
3. Open `https://<ITCH_USERNAME>.itch.io` while signed out: the project is not listed on the
   profile.
4. Search itch.io for the page's title while signed out: it does not appear in search or browse.
   (A just-changed setting may take a short while to be reflected; note when you checked.)
5. Record each result in the "Signed-out access" section of the evidence file.

## 6. Device checks

Run these on every target in the evidence file, using the itch.io page (the Windows ZIP is
downloaded from the page, not copied over from the build machine). Use the same `<BUILD_ID>`
everywhere.

### What the game shows (this slice of the port)

- A small arena: dark grid floor inside a purple border. A placeholder shape is the player; the
  camera follows it.
- **Top-left:** `Build <BUILD_ID> (<first 9 chars of the commit>)`, below it the hint
  `WASD / arrows: move   P / Esc: pause   R: restart` and `Touch: drag on the left half to move`.
- **Top-right:** `Pause` and `Restart` buttons (`Pause` becomes `Resume` while paused).
- **Bottom-centre:** `Click or tap to enable sound` until the first key press, mouse click or touch.
- **Paused:** big `PAUSED` text (`Press P / Esc or tap Resume`).
- There is no combat, enemies or dash yet. Controls: W A S D or arrow keys move; P or Esc
  pause/resume; R restart. Touch: drag in the left part of the screen (about the left 55%, below
  the top strip) to move with a floating ring stick, and use the on-screen buttons.
- Losing focus (switching tab/window/app) pauses automatically and releases input; resuming is
  always explicit.

### Checks to record

| Check | Pass when |
|---|---|
| **Build ID** | The top-left label shows the intended `<BUILD_ID>` and commit prefix. Web: the label inside the game. Windows: the label in the game window, the `Build:` line of `READ-ME-FIRST.txt` and `BUILD-INFO.json` in the extracted folder. The uploaded file names carry the same id. |
| **Movement** | Keys (desktop) or left-area drag (Android) move the player; the camera follows; the player stops at the arena border. |
| **Pause / resume** | `P`, `Esc` or the button shows `PAUSED`; holding a movement key while paused moves nothing; resuming (`P`, `Esc` or `Resume`) continues. On Android use the button. |
| **Sound unlock** | Before any input the prompt is visible and there is no sound. After the first key/click/tap the prompt disappears and a short unlock sound plays; pause, resume and restart each then play their own sound. Device volume up. |
| **Web asset delivery** | Desktop browser DevTools → Network (reload with cache disabled for the cold run): `index.html`, `index.js`, `index.wasm`, `index.pck`, `index.png` and both `index.audio*.worklet.js` all return 200; no 403/404 or console errors; note the transferred size of `index.wasm` (itch.io's CDN gzips `.wasm` and `.pck`, so it can be much smaller than 39.5 MB). On Android, if you cannot inspect the network, write "not inspected"; reaching the arena with the correct build label is then the only evidence. |
| **Startup time** | Stopwatch or screen recording, to about a second. Web: from clicking the launch/play control to the build label and sound prompt appearing. **Cold** = first load with an empty browser cache (private window or cleared site data); **cached** = reload straight afterwards. Windows: from double-clicking `Swordster.exe` to the window showing the build label. **Cold** = first launch after extracting; **cached** = close and launch again. If SmartScreen appears, time from clicking "Run anyway". |
| **Windows warning** | Write down exactly what Windows showed (e.g. the "Windows protected your PC" screen, whether a "More info" / "Run anyway" path existed, any antivirus message) or "none". Builds are unsigned; the ZIP's `READ-ME-FIRST.txt` describes the expected blue screen, but what testers actually see is unverified until you record it. |

### Per target

- **Windows 10 / Windows 11 (separate machines, no Python or Godot):** confirm and record how you
  checked that neither is installed (for example `py --version`, `python --version` and
  `where godot` in a command prompt report not found). Download the Windows ZIP from the signed-out
  page, extract it with "Extract All..." (the game needs `Swordster.exe` and `Swordster.pck`
  together), run the exe, then do the checks above. Optional integrity check:
  `Get-FileHash -Algorithm SHA256 .\Swordster.exe` in PowerShell against the matching line in the
  extracted `SHA256SUMS`. (Do not compare itch.io's download byte-for-byte with the original ZIP:
  verify contents.)
- **Desktop Chrome, desktop Firefox:** open `<PAGE_URL>` signed out, run the checks, including
  the DevTools network check. Record the exact versions (Help → About).
- **Android Chrome (physical phone):** open `<PAGE_URL>` in Chrome itself (not an in-app browser)
  signed out. First run with Mobile Friendly off and note the warning, if any; run the checks;
  then enable Mobile Friendly in the itch.io editor, reload on the phone and re-run them. Record
  both outcomes. Optional: rotate the phone and switch away/back to see that the run pauses.

## 7. Finish

1. Fill in [`itchio-evidence.md`](itchio-evidence.md). Change a result from `UNVERIFIED` only
   for something you personally observed.
2. Any failure (asset 403/404, wrong build id, blocked download, SmartScreen that stops testers,
   a payment/login prompt, no sound after unlock, an unusable Android layout, a missing Windows
   download on the HTML page) is a delivery blocker: note it in the evidence file and on issue #6,
   and fix it before combat-port work (the downstream issues) continues.
3. Issue #6 can only be closed with this evidence from real devices; the PR that adds these two
   documents does not close it.

## 8. Sources and what is not confirmed

Read from itch.io's own documentation on 2026-11-09:

- HTML5: <https://itch.io/docs/creators/html5> (ZIP with `index.html`, relative paths, ZIP limits,
  embed options, Mobile Friendly, HTML game kind)
- Access control: <https://itch.io/docs/creators/access-control> (Public, Unlisted in search &
  browse, profile theme editor)
- Pricing: <https://itch.io/docs/creators/pricing> ("No payments")
- Getting started: <https://itch.io/docs/creators/getting-started> (create flow, private by
  default, publishing, platform tagging)
- Download keys: <https://itch.io/docs/creators/download-keys> (free downloads create no key)

Not confirmed by those pages. Check each in the live dashboard and write down what you actually
see; where it differs from this document, trust the dashboard and update this file:

- **A. Removing the project from your profile.** Documentation only says it can be removed "via
  the profile theme editor". The exact menu path and control are not documented there.
- **B. One page with both a browser-playable HTML upload and a Windows download.** The docs say
  uploads can be tagged by platform and that HTML games take a ZIP with `index.html`. They do not
  describe the exact control that marks one upload as "play in browser" while another stays a
  platform download, nor state that an HTML-kind page keeps a Windows download. If the page
  cannot show both Play and a Windows download, that is a delivery blocker (section 7).
- **C. Where "No payments" sits on the edit page.** The pricing page names the option; the
  getting-started page separately mentions payment settings under User settings → Seller settings.
- **D. Anonymous Windows download** (see section 5, step 2) and whether an `index.html` inside a
  sub-folder of the ZIP would also work; this procedure avoids the question by putting it at the
  root.
- **E. New-account upload limit.** getting-started says new accounts have an upload size limit
  (raisable on request) without stating the number. The largest upload here is about 39 MB.
