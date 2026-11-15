#!/usr/bin/env node
// Plays the exported Web build's dev encounters in headless Chromium and writes
// page screenshots. Evidence for issues #9 (crowd, wall) and #10 (spitters); not
// part of the build. SCENARIO=crowd|wall|spitters|normal|flurry|conditions|warden|pike (issue #11: the
// conditions encounter, with the player walking about and Q, E and R pressed as browser key
// events so burning, poisoned, chilled and frozen foes and fire spreading can be seen); flurry (issue #12: the mouse
// is moved and Q, E and R are pressed as browser key events; the flurry scenario
// starts in the crowd encounter so there is something to dart between), warden (issue #13: the
// warden encounter, with Fang / Warden / Warden; the sweeps are watched, then E and R start
// Maelstroms at the cursor and Q the flurry, all as browser key and mouse events), pike (issue #14: the
// pike encounter, with three Pikes; the thrusts are watched, then E starts a Skewer with the cursor
// above the player (north: the column is carried into the wall and slammed), Q and R fire the other
// slots east and west, and a press while recharging is refused, all as browser key and mouse events), colossus (issue #15:
// the colossus encounter, with three Colossus swords (poison, ice, fire); the slams are watched, then Q, E and R drop a
// Cataclysm of each element with the cursor east, west and north of the player, and a press while recharging is refused,
// all as browser key and mouse events, so the three elemental fields can be seen), converge (issue #16: the NORMAL start with
// the default loadout, Fang / Warden / Colossus; left and right mouse clicks command Converge at near and far points, Tab
// shows the attack ranges, and Q, E and R press the slots' ultimates, all as browser key and mouse events).
//
//   node tools/godot/web-encounter-capture.mjs <chrome-headless-shell> <web-bundle-dir> <out-dir>
//
// It serves the bundle over HTTP on localhost, drives the page through the Chrome
// DevTools Protocol (page screenshots and browser-level input events only: nothing
// touches the desktop), and logs the browser console. Software WebGL (SwiftShader),
// 1280x720. Needs Node 22+ (global fetch and WebSocket).
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { extname, join, normalize } from "node:path";

const [chrome, bundle, outDir] = process.argv.slice(2);
if (!chrome || !bundle || !outDir) {
  console.error("usage: web-encounter-capture.mjs <chrome-headless-shell> <web-bundle-dir> <out-dir>");
  process.exit(2);
}
mkdirSync(outDir, { recursive: true });

const TYPES = { ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm", ".pck": "application/octet-stream", ".png": "image/png", ".json": "application/json" };
const server = createServer((req, res) => {
  const path = normalize(decodeURIComponent(new URL(req.url, "http://x").pathname)).replace(/^\/+/, "") || "index.html";
  const file = join(bundle, path);
  if (!existsSync(file) || !file.startsWith(bundle)) { res.writeHead(404).end(); return; }
  res.writeHead(200, { "content-type": TYPES[extname(file)] ?? "application/octet-stream" }).end(readFileSync(file));
});
await new Promise((ok) => server.listen(0, "127.0.0.1", ok));
const base = `http://127.0.0.1:${server.address().port}/index.html`;

const port = 9400 + Math.floor(Math.random() * 400);
const proc = spawn(chrome, [
  `--remote-debugging-port=${port}`, "--no-sandbox", "--hide-scrollbars", "--mute-audio",
  "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist",
  "--window-size=1280,720", `--user-data-dir=${join(outDir, "profile")}`, "about:blank",
], { stdio: "ignore" });
const sleep = (ms) => new Promise((ok) => setTimeout(ok, ms));
let targets;
for (let i = 0; i < 100 && !targets; i++) {
  try { targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json(); } catch { await sleep(100); }
}
const page = targets.find((t) => t.type === "page");
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((ok) => ws.addEventListener("open", ok));
let nextId = 1;
let castIndex = 0;
const pending = new Map();
const consoleLines = [];
ws.addEventListener("message", (event) => {
  const msg = JSON.parse(event.data);
  if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
  else if (msg.method === "Page.screencastFrame") {
    // CAST=1: every rendered frame, so short effects (parry sparks) are not missed.
    writeFileSync(join(outDir, `cast-${String(castIndex++).padStart(5, "0")}.png`), Buffer.from(msg.params.data, "base64"));
    ws.send(JSON.stringify({ id: nextId++, method: "Page.screencastFrameAck", params: { sessionId: msg.params.sessionId } }));
  } else if (msg.method === "Runtime.consoleAPICalled") consoleLines.push(`${msg.params.type}: ${msg.params.args.map((a) => a.value ?? a.description).join(" ")}`);
  else if (msg.method === "Runtime.exceptionThrown") consoleLines.push(`exception: ${msg.params.exceptionDetails.text} ${msg.params.exceptionDetails.exception?.description ?? ""}`);
});
const send = (method, params = {}) => new Promise((ok) => { const id = nextId++; pending.set(id, ok); ws.send(JSON.stringify({ id, method, params })); });
const shot = async (name) => {
  const { result } = await send("Page.captureScreenshot", { format: "png" });
  writeFileSync(join(outDir, `${name}.png`), Buffer.from(result.data, "base64"));
  console.log(`screenshot ${name}`);
};
const key = async (code, k, vk) => {
  const common = { code, key: k, windowsVirtualKeyCode: vk, nativeVirtualKeyCode: vk };
  await send("Input.dispatchKeyEvent", { type: "rawKeyDown", ...common });
  await send("Input.dispatchKeyEvent", { type: "keyUp", ...common });
};
const move = (x, y) => send("Input.dispatchMouseEvent", { type: "mouseMoved", x, y });
const clickWith = async (x, y, button) => {
  const buttons = button === "right" ? 2 : 1;
  await send("Input.dispatchMouseEvent", { type: "mouseMoved", x, y });
  await send("Input.dispatchMouseEvent", { type: "mousePressed", x, y, button, buttons, clickCount: 1 });
  await send("Input.dispatchMouseEvent", { type: "mouseReleased", x, y, button, buttons: 0, clickCount: 1 });
};
const click = async (x, y) => {
  await send("Input.dispatchMouseEvent", { type: "mouseMoved", x, y });
  await send("Input.dispatchMouseEvent", { type: "mousePressed", x, y, button: "left", buttons: 1, clickCount: 1 });
  await send("Input.dispatchMouseEvent", { type: "mouseReleased", x, y, button: "left", buttons: 0, clickCount: 1 });
};

await send("Runtime.enable");
await send("Page.enable");
await send("Emulation.setDeviceMetricsOverride", { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });
const scenario = process.env.SCENARIO ?? "crowd"; // crowd | wall | spitters | normal | flurry | conditions | warden | pike | colossus | converge
const query = scenario === "normal" || scenario === "converge" ? "" : `?encounter=${scenario === "flurry" ? "crowd" : scenario}`;
await send("Page.navigate", { url: `${base}${query}` });
if (scenario === "wall") {
  // The pinned crowd starts fighting the moment the engine runs, so react to the
  // engine's first console line instead of a fixed delay: focus, then shove.
  for (let i = 0; i < 600 && !consoleLines.some((l) => l.includes("Build configuration")); i++) await sleep(20);
  await click(640, 360);
  await key("KeyF", "f", 70);
  console.log("shove F right after engine start");
}
if (scenario === "pike") {
  // The Pikes start killing the column the moment the engine runs, so react to the engine's first
  // console line, focus the page, aim north with the cursor and press E (slot two's Skewer) at once.
  for (let i = 0; i < 600 && !consoleLines.some((l) => l.includes("Build configuration")); i++) await sleep(20);
  await click(640, 360);
  await move(640, 360 - 300);
  await key("KeyE", "e", 69);
  console.log("E (Skewer north, slot two) right after engine start, cursor (640, 60)");
}
if (scenario === "colossus") {
  // The Colossi start winding up on the cluster the moment the engine runs: react to the engine's first console line,
  // focus the page and press Q (slot one, poison) with the cursor east of the player over the cluster at once.
  for (let i = 0; i < 600 && !consoleLines.some((l) => l.includes("Build configuration")); i++) await sleep(20);
  await click(640, 360);
  await move(640 + 330, 360 - 10);
  await key("KeyQ", "q", 81);
  console.log("Q (Cataclysm east, slot one, poison) right after engine start, cursor (970, 350)");
}
await sleep(scenario === "wall" || scenario === "pike" || scenario === "colossus" ? 500 : 5000);
if (scenario !== "wall" && scenario !== "pike" && scenario !== "colossus") await click(640, 360); // focus the canvas and unlock audio
const t0 = Date.now();
const stamp = () => ((Date.now() - t0) / 1000).toFixed(1);

if (scenario === "crowd") {
  await sleep(1800); await shot("crowd-01-arrival");
  await sleep(2500); await shot("crowd-02-fight");
  await key("KeyF", "f", 70); // shove through the keyboard
  console.log(`shove F at ${stamp()}s`);
  for (const wait of [200, 300, 400]) { await sleep(wait); await shot(`crowd-03-shoved-${wait}`); }
  await click(1084, 644); // the Shove button (bottom right, left of Dash)
  console.log(`shove button at ${stamp()}s`);
  await sleep(300); await shot("crowd-04-shove-button");
  await key("KeyC", "c", 67); // the next dev encounter is the spitters (this restarts play)
  await sleep(1500); await shot("crowd-05-next-dev-encounter");
  await key("KeyC", "c", 67); // then the normal husk wave
  await sleep(1500); await shot("crowd-06-normal-wave");
  await key("KeyC", "c", 67); // and round to the crowd again
  await sleep(1500); await shot("crowd-07-encounter-again");
} else if (scenario === "flurry") {
  // Viper Flurry through the keyboard and mouse: aim with the cursor (the view is
  // 1280x720 and centred on the player), press Q, E and R, then Q again while it
  // recharges (refused). Screenshots follow each press.
  await sleep(2500); await shot("flurry-01-before");
  await move(840, 330); await key("KeyQ", "q", 81);
  console.log(`Q at ${stamp()}s, cursor (840, 330)`);
  for (const wait of [60, 150, 250, 400]) { await sleep(wait); await shot(`flurry-02-q-${wait}`); }
  await move(470, 420); await key("KeyE", "e", 69);
  console.log(`E at ${stamp()}s, cursor (470, 420)`);
  for (const wait of [60, 200, 400]) { await sleep(wait); await shot(`flurry-03-e-${wait}`); }
  await key("KeyQ", "q", 81); // slot one is still recharging: refused, with a "recharging Ns" tag
  console.log(`Q while recharging at ${stamp()}s`);
  await sleep(100); await shot("flurry-03-q-refused");
  await move(660, 200); await key("KeyR", "r", 82);
  console.log(`R at ${stamp()}s, cursor (660, 200)`);
  for (const wait of [60, 200, 600, 900]) { await sleep(wait); await shot(`flurry-04-r-${wait}`); }
  // by now (more than nine seconds after the first press) slot one has recharged: Q works again
  await key("KeyQ", "q", 81);
  console.log(`Q after the recharge at ${stamp()}s`);
  await sleep(150); await shot("flurry-05-q-again");
} else if (scenario === "warden") {
  // The warden encounter: watch the Wardens sweep, then press E and R (Maelstrom) with the cursor on
  // the crowd, Q (Viper Flurry), and E again while it recharges (refused). The view is 1280x720 and
  // centred on the player, so the cursor at (640 + dx, 360 + dy) aims dx, dy pixels from him.
  const hold = async (code, k, vk, ms) => {
    const common = { code, key: k, windowsVirtualKeyCode: vk, nativeVirtualKeyCode: vk };
    await send("Input.dispatchKeyEvent", { type: "rawKeyDown", ...common });
    await sleep(ms);
    await send("Input.dispatchKeyEvent", { type: "keyUp", ...common });
  };
  let shotIndex = 0;
  await sleep(1500); await shot("warden-01-arrival");
  for (const wait of [700, 700, 700]) { await sleep(wait); await shot(`warden-02-sweeps-${wait}-${shotIndex++}`); }
  await move(640 + 170, 360 + 20); await key("KeyE", "e", 69);
  console.log(`E (Maelstrom, slot two) at ${stamp()}s, cursor (810, 380)`);
  for (const wait of [80, 250, 500, 600, 700, 800]) { await sleep(wait); await shot(`warden-03-e-${wait}-${shotIndex++}`); }
  await move(640 - 170, 360 - 10); await key("KeyR", "r", 82);
  console.log(`R (Maelstrom, slot three) at ${stamp()}s, cursor (470, 350)`);
  for (const wait of [80, 250, 500, 600, 700, 800]) { await sleep(wait); await shot(`warden-04-r-${wait}-${shotIndex++}`); }
  await key("KeyE", "e", 69); // slot two is recharging (11 s): refused, with a "recharging Ns" tag
  console.log(`E while recharging at ${stamp()}s`);
  await sleep(120); await shot("warden-05-e-refused");
  await move(640 + 120, 360 + 80); await key("KeyQ", "q", 81);
  console.log(`Q (Viper Flurry, slot one) at ${stamp()}s`);
  for (const wait of [100, 300]) { await sleep(wait); await shot(`warden-06-q-${wait}-${shotIndex++}`); }
  const moves = [["KeyD", "d", 68], ["KeyS", "s", 83], ["KeyA", "a", 65], ["KeyW", "w", 87]];
  for (let round = 0; round < Number(process.env.ROUNDS ?? 8); round++) {
    const [code, k, vk] = moves[round % 4];
    await hold(code, k, vk, 500);
    await shot(`warden-07-round-${String(round).padStart(2, "0")}`);
  }
  await key("KeyC", "c", 67); // the next dev encounter after the warden one is the normal run
  await sleep(1200); await shot("warden-08-next-dev-encounter-normal");
} else if (scenario === "pike") {
  // The pike encounter: watch the Pikes thrust through the column, then press E with the cursor above the
  // player (a Skewer north: aim line, launch, the carried foes ringed, the release at the wall and its
  // slams), Q to the east and R to the west (to the range limit), and E again while it recharges
  // (refused). The view is 1280x720 and centred on the player, so the cursor at (640 + dx, 360 + dy)
  // aims dx, dy pixels from him.
  const hold = async (code, k, vk, ms) => {
    const common = { code, key: k, windowsVirtualKeyCode: vk, nativeVirtualKeyCode: vk };
    await send("Input.dispatchKeyEvent", { type: "rawKeyDown", ...common });
    await sleep(ms);
    await send("Input.dispatchKeyEvent", { type: "keyUp", ...common });
  };
  let shotIndex = 0;
  await shot("pike-01-aim-or-flight");
  for (const wait of [100, 150, 200, 250, 300, 400, 500]) { await sleep(wait); await shot(`pike-03-e-${wait}-${shotIndex++}`); }
  await key("KeyE", "e", 69); // slot two is recharging (10 s): refused, with a "recharging Ns" tag
  console.log(`E while recharging at ${stamp()}s`);
  await sleep(120); await shot("pike-04-e-refused");
  for (const wait of [500, 500]) { await sleep(wait); await shot(`pike-02-thrusts-${wait}-${shotIndex++}`); }
  await sleep(2500); // let the Pikes thrust at the next arrivals
  await move(640 + 300, 360); await key("KeyQ", "q", 81);
  console.log(`Q (Skewer east, slot one) at ${stamp()}s, cursor (940, 360)`);
  for (const wait of [200, 250, 300, 400]) { await sleep(wait); await shot(`pike-05-q-${wait}-${shotIndex++}`); }
  await move(640 - 300, 360); await key("KeyR", "r", 82);
  console.log(`R (Skewer west, slot three) at ${stamp()}s, cursor (340, 360)`);
  for (const wait of [200, 250, 300, 400]) { await sleep(wait); await shot(`pike-06-r-${wait}-${shotIndex++}`); }
  const moves = [["KeyD", "d", 68], ["KeyS", "s", 83], ["KeyA", "a", 65], ["KeyW", "w", 87]];
  for (let round = 0; round < Number(process.env.ROUNDS ?? 8); round++) {
    const [code, k, vk] = moves[round % 4];
    await hold(code, k, vk, 500);
    await shot(`pike-07-round-${String(round).padStart(2, "0")}`);
  }
  await key("KeyC", "c", 67); // the next dev encounter after the pike one is the normal run
  await sleep(1200); await shot("pike-08-next-dev-encounter-normal");
} else if (scenario === "colossus") {
  // The colossus encounter, driven only by browser key and mouse events. The software-rendered page takes seconds per
  // screenshot while the game runs on, so the three Cataclysms are pressed in quick succession (Q poison east over the
  // cluster, E ice west, R fire north) and the game is PAUSED with P (a key the game itself handles) to take the
  // screenshots: paused, the rise, the landing and the three fields stand still. The view is 1280x720 and centred on the
  // player, so the cursor at (640 + dx, 360 + dy) aims dx, dy pixels from him.
  const pause = async () => { await key("KeyP", "p", 80); await sleep(300); };
  let shotIndex = 0;
  const watch = async (label, ms) => { await sleep(ms); await pause(); await shot(`colossus-${label}-${shotIndex++}`); await pause(); };
  await watch("01-q-landing", 0);
  await move(640 - 220, 360 + 40); await key("KeyE", "e", 69);
  console.log(`E (Cataclysm west, slot two, ice) at ${stamp()}s, cursor (420, 400)`);
  await move(640, 360 - 250); await key("KeyR", "r", 82);
  console.log(`R (Cataclysm north, slot three, fire) at ${stamp()}s, cursor (640, 110)`);
  await watch("02-three-rising", 250);
  await watch("03-landings", 400);
  await watch("04-three-fields", 500);
  await watch("05-fields", 700);
  await key("KeyQ", "q", 81); // slot one is recharging (14 s): refused, with a "recharging Ns" tag
  console.log(`Q while recharging at ${stamp()}s`);
  await watch("06-q-refused", 100);
  await key("KeyC", "c", 67); // the next dev encounter after the colossus one is the normal run
  await sleep(1200); await shot("colossus-07-next-dev-encounter-normal");
} else if (scenario === "converge") {
  // The normal start (no encounter): the default loadout, Fang (poison), Warden (ice), Colossus (fire). The page is software
  // rendered, so the game is PAUSED with P (a key the game itself handles) to take each screenshot. The view is 1280x720 and
  // centred on the player, so the cursor at (640 + dx, 360 + dy) aims dx, dy pixels from him.
  const pause = async () => { await key("KeyP", "p", 80); await sleep(300); };
  let shotIndex = 0;
  const watch = async (label, ms) => { await sleep(ms); await pause(); await shot(`converge-${label}-${shotIndex++}`); await pause(); };
  await sleep(1500); await watch("01-start", 0);
  await key("Tab", "Tab", 9);
  await watch("02-ranges", 400);
  await key("Tab", "Tab", 9);
  // The wave arrives about 1.6 s in; give it time, then command Converge at a NEAR point east of the player with the left button.
  await sleep(2500);
  await move(640 + 140, 360 - 10);
  await clickWith(640 + 140, 360 - 10, "left");
  console.log("left click, near point 140 px east, at " + stamp() + "s");
  await watch("03-left-click-near", 120);
  await watch("04-after-left-click", 500);
  // The shared cooldown: a second click right away is refused (the HUD shows converge counting down).
  await clickWith(640 - 150, 360 + 30, "right");
  console.log("right click during the cooldown (refused), at " + stamp() + "s");
  await watch("05-right-click-refused", 150);
  await sleep(3000);
  // A FAR point (about 640 px away, 460 px is the range): the right button, pulled back onto the range.
  await move(640 + 600, 360 - 300);
  await clickWith(640 + 600, 360 - 300, "right");
  console.log("right click, far point 670 px north-east, at " + stamp() + "s");
  await watch("06-right-click-far", 120);
  await watch("07-after-right-click-far", 500);
  await move(640 - 200, 360 + 60); await key("KeyQ", "q", 81);
  await move(640 + 200, 360 - 60); await key("KeyE", "e", 69);
  await move(640, 360 - 200); await key("KeyR", "r", 82);
  console.log("Q, E, R at " + stamp() + "s");
  await watch("08-ultimates-starting", 250);
  await watch("09-ultimates-running", 600);
  await watch("10-ultimates-landing", 900);
} else if (scenario === "conditions") {
  // Walk about in the conditions encounter so the swords keep fighting, press the three
  // ultimates now and then, and take a page screenshot every half second or so. CAST=1
  // also records every rendered frame so short effects (a freeze burst, a fire ring) are caught.
  const hold = async (code, k, vk, ms) => {
    const common = { code, key: k, windowsVirtualKeyCode: vk, nativeVirtualKeyCode: vk };
    await send("Input.dispatchKeyEvent", { type: "rawKeyDown", ...common });
    await sleep(ms);
    await send("Input.dispatchKeyEvent", { type: "keyUp", ...common });
  };
  await sleep(1200); await shot("conditions-01-arrival");
  if (process.env.CAST) await send("Page.startScreencast", { format: "png", everyNthFrame: 1 });
  const moves = [["KeyD", "d", 68], ["KeyW", "w", 87], ["KeyA", "a", 65], ["KeyS", "s", 83]];
  const ultimates = [["KeyQ", "q", 81], ["KeyE", "e", 69], ["KeyR", "r", 82]];
  for (let round = 0; round < Number(process.env.ROUNDS ?? 30); round++) {
    await shot(`conditions-02-round-${String(round).padStart(2, "0")}`);
    const [code, k, vk] = moves[round % 4];
    await hold(code, k, vk, 400);
    if (round % 5 === 4) { const [c, kk, v] = ultimates[(round / 5 | 0) % 3]; await move(640 + 150, 360); await key(c, kk, v); console.log(`ultimate ${kk} at ${stamp()}s`); }
  }
  if (process.env.CAST) { await send("Page.stopScreencast"); console.log(`screencast frames: ${castIndex}`); }
} else if (scenario === "spitters") {
  // The spitters arrive, glow, shoot. Walk toward them with the keyboard so the
  // Fang swords strike near the orbs, dash through some, and keep shooting the
  // page (the HUD legend counts orbs fired and parried).
  await sleep(1500); await shot("spitters-01-arrival");
  const hold = async (code, k, vk, ms) => {
    const common = { code, key: k, windowsVirtualKeyCode: vk, nativeVirtualKeyCode: vk };
    await send("Input.dispatchKeyEvent", { type: "rawKeyDown", ...common });
    await sleep(ms);
    await send("Input.dispatchKeyEvent", { type: "keyUp", ...common });
  };
  for (let round = 0; round < Number(process.env.ROUNDS ?? 14); round++) {
    await shot(`spitters-02-round-${String(round).padStart(2, "0")}`);
    const moves = [["KeyD", "d", 68], ["KeyW", "w", 87], ["KeyA", "a", 65], ["KeyS", "s", 83]];
    const [code, k, vk] = moves[round % 4];
    await hold(code, k, vk, 450);
    if (round % 3 === 2) { await key("Space", " ", 32); console.log(`dash at ${stamp()}s`); }
  }
  // BURST=n: a dense run of screenshots (about one per 150 ms) while walking about,
  // so the half-second parry sparks are caught; tools pick frames afterwards.
  if (process.env.CAST) await send("Page.startScreencast", { format: "png", everyNthFrame: 1 });
  for (let i = 0; i < Number(process.env.CAST_ROUNDS ?? 0); i++) {
    const moves = [["KeyD", "d", 68], ["KeyW", "w", 87], ["KeyA", "a", 65], ["KeyS", "s", 83]];
    const [code, k, vk] = moves[i % 4];
    await hold(code, k, vk, 600);
    if (i % 4 === 3) await key("Space", " ", 32);
  }
  if (process.env.CAST) { await send("Page.stopScreencast"); console.log(`screencast frames: ${castIndex}`); }
  for (let i = 0; i < Number(process.env.BURST ?? 0); i++) {
    await shot(`spitters-burst-${String(i).padStart(3, "0")}`);
    if (i % 6 === 0) { const moves = [["KeyD", "d", 68], ["KeyW", "w", 87], ["KeyA", "a", 65], ["KeyS", "s", 83]]; const [code, k, vk] = moves[(i / 6) % 4]; hold(code, k, vk, 500); }
    if (i % 17 === 16) await key("Space", " ", 32);
  }
  await key("KeyC", "c", 67); // the next dev encounter after the spitters is the normal run
  await sleep(1200); await shot("spitters-03-next-dev-encounter-normal");
} else if (scenario === "wall") {
  for (let i = 1; i <= 4; i++) { await shot(`wall-01-shoved-${i}`); await sleep(150); }
  await sleep(2000); await shot("wall-02-aftermath");
  await key("KeyF", "f", 70);
  for (const wait of [150, 300]) { await sleep(wait); await shot(`wall-03-second-shove-${wait}`); }
} else {
  await sleep(2500); await shot("normal-01");
}
writeFileSync(join(outDir, "console.log"), consoleLines.join("\n") + "\n");
console.log(`console lines: ${consoleLines.length}`);
ws.close();
proc.kill();
server.close();
process.exit(0);
