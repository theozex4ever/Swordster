#!/usr/bin/env node
// Evidence for issue #19 (readable combat feedback, sound and the desktop HUD) from the exported Web build in headless Chromium.
// The NORMAL run is played by browser events only (CDP Input.dispatchKeyEvent / dispatchMouseEvent: nothing touches the desktop,
// and the game has no autopilot): a first click, WASD, Converge clicks, Q / E / R, H for the help, P for the pause. Screenshots show the
// HUD, the help overlay, the chain counter, banners, hits, the death screen and the restart.
//
// Audio: a script injected before the page loads wraps AudioContext and AudioBufferSourceNode so the page's own audio can be observed
// from outside: the context's state before and after the first click (autoplay policy "user-gesture-required" is requested, but headless
// Chromium may still report the context as already running before the click, so the context state is not unlock evidence), its reported latency, and every sound started (time on the context's clock). Written to
// <out-dir>/audio-report.json. What headless can prove: the first user gesture is recorded with its timestamp on the page clock, sounds start after it and
// none before it (counted against that timestamp, not against the context state), the output latency the browser reports, and that starts are scheduled promptly after the game frame that caused them.
// What it cannot: that the samples are audible (the sink is muted/fake) or how they sound on a real device (issue #6 / #22).
//
//   node tools/godot/web-feedback-capture.mjs <chrome-headless-shell> <web-bundle-dir> <out-dir>
//
// Needs Node 22+ (global fetch and WebSocket). Software WebGL (SwiftShader), 1280x720.
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { extname, join, normalize } from "node:path";

const [chrome, bundle, outDir] = process.argv.slice(2);
if (!chrome || !bundle || !outDir) {
  console.error("usage: web-feedback-capture.mjs <chrome-headless-shell> <web-bundle-dir> <out-dir>");
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

const port = 9800 + Math.floor(Math.random() * 400);
const proc = spawn(chrome, [
  `--remote-debugging-port=${port}`, "--no-sandbox", "--hide-scrollbars", "--mute-audio", "--autoplay-policy=user-gesture-required",
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
const pending = new Map();
const consoleLines = [];
ws.addEventListener("message", (event) => {
  const msg = JSON.parse(event.data);
  if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
  else if (msg.method === "Runtime.consoleAPICalled") consoleLines.push(`${msg.params.type}: ${msg.params.args.map((a) => a.value ?? a.description).join(" ")}`);
  else if (msg.method === "Runtime.exceptionThrown") consoleLines.push(`exception: ${msg.params.exceptionDetails.text} ${msg.params.exceptionDetails.exception?.description ?? ""}`);
});
const send = (method, params = {}) => new Promise((ok) => { const id = nextId++; pending.set(id, ok); ws.send(JSON.stringify({ id, method, params })); });
const shot = async (name) => {
  const { result } = await send("Page.captureScreenshot", { format: "png" });
  writeFileSync(join(outDir, `${name}.png`), Buffer.from(result.data, "base64"));
  console.log(`screenshot ${name}`);
};
const down = (code, k, vk) => send("Input.dispatchKeyEvent", { type: "rawKeyDown", code, key: k, windowsVirtualKeyCode: vk, nativeVirtualKeyCode: vk });
const up = (code, k, vk) => send("Input.dispatchKeyEvent", { type: "keyUp", code, key: k, windowsVirtualKeyCode: vk, nativeVirtualKeyCode: vk });
const key = async (code, k, vk) => { await down(code, k, vk); await up(code, k, vk); };
const move = (x, y) => send("Input.dispatchMouseEvent", { type: "mouseMoved", x, y });
const clickWith = async (x, y, button) => {
  const buttons = button === "right" ? 2 : 1;
  await send("Input.dispatchMouseEvent", { type: "mouseMoved", x, y });
  await send("Input.dispatchMouseEvent", { type: "mousePressed", x, y, button, buttons, clickCount: 1 });
  await send("Input.dispatchMouseEvent", { type: "mouseReleased", x, y, button, buttons: 0, clickCount: 1 });
};
const evaluate = async (expression) => (await send("Runtime.evaluate", { expression, returnByValue: true })).result?.result?.value;

// Observe the page's own audio from the outside, before any of its scripts run.
await send("Page.addScriptToEvaluateOnNewDocument", { source: `(() => {
  const log = window.__audio = { contexts: [], starts: [], states: [], workletMessages: 0, firstGesture: null };
  // The first user gesture the browser delivered (a trusted press or key down; moves and releases are not gestures), stamped with the
  // event's own time on the same clock as every sound start (performance.now()). Captured on window before the game sees the event.
  for (const type of ["pointerdown", "mousedown", "touchstart", "keydown"]) {
    window.addEventListener(type, (e) => {
      if (e.isTrusted && log.firstGesture === null) log.firstGesture = { type, at: e.timeStamp, seenAt: performance.now() };
    }, true);
  }
  const Native = window.AudioContext || window.webkitAudioContext;
  if (!Native) return;
  const Wrapped = function (...args) {
    const ctx = new Native(...args);
    const entry = { created: performance.now(), initial: ctx.state, baseLatency: ctx.baseLatency, sampleRate: ctx.sampleRate };
    log.contexts.push(entry);
    log.states.push({ at: performance.now(), state: ctx.state });
    ctx.addEventListener("statechange", () => log.states.push({ at: performance.now(), state: ctx.state, currentTime: ctx.currentTime }));
    entry.ctx = ctx;
    return ctx;
  };
  Wrapped.prototype = Native.prototype;
  window.AudioContext = Wrapped;
  if (window.webkitAudioContext) window.webkitAudioContext = Wrapped;
  const start = AudioBufferSourceNode.prototype.start;
  AudioBufferSourceNode.prototype.start = function (...args) {
    log.starts.push({ at: performance.now(), contextTime: this.context.currentTime, state: this.context.state, duration: this.buffer ? this.buffer.duration : null });
    return start.apply(this, args);
  };
  const post = MessagePort.prototype.postMessage;
  MessagePort.prototype.postMessage = function (...args) { log.workletMessages++; return post.apply(this, args); };
})();` });
await send("Runtime.enable");
await send("Page.enable");
await send("Emulation.setDeviceMetricsOverride", { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });
const visuals = process.env.VISUALS ? `?visuals=${process.env.VISUALS}` : ""; // e.g. VISUALS=textured
await send("Page.navigate", { url: `${base}${visuals}` });
for (let i = 0; i < 600 && !consoleLines.some((l) => l.includes("Build configuration")); i++) await sleep(50);
await sleep(3000);

const report = { build: consoleLines.find((l) => l.includes("Build")) ?? null };
const snapshot = async () => evaluate(`JSON.stringify({ contexts: window.__audio.contexts.map((c) => ({ state: c.ctx.state, baseLatency: c.baseLatency, outputLatency: c.ctx.outputLatency ?? null, sampleRate: c.sampleRate, currentTime: c.ctx.currentTime })), starts: window.__audio.starts.length, states: window.__audio.states, workletMessages: window.__audio.workletMessages })`);
report.beforeGesture = JSON.parse(await snapshot());
await shot("feedback-01-before-click");
const t0 = Date.now();
const stamp = () => ((Date.now() - t0) / 1000).toFixed(1);

await clickWith(640, 360, "left"); // the first gesture: unlocks audio (and is a Converge)
await sleep(600);
report.afterFirstClick = JSON.parse(await snapshot());
await shot("feedback-02-after-click-help");

// Walk about and fight: only browser key and mouse events.
const hold = async (code, k, vk, ms) => { await down(code, k, vk); await sleep(ms); await up(code, k, vk); };
let shots = 3;
const name = (label) => `feedback-${String(shots++).padStart(2, "0")}-${label}`;
await hold("KeyD", "d", 68, 700);
await key("KeyH", "h", 72); await sleep(150); await shot(name("help-hidden"));
await key("KeyH", "h", 72); await sleep(150); await shot(name("help-shown-again"));
await key("KeyH", "h", 72);
for (let round = 0; round < Number(process.env.ROUNDS ?? 24); round++) {
  await hold(["KeyD", "KeyS", "KeyA", "KeyW"][round % 4], ["d", "s", "a", "w"][round % 4], [68, 83, 65, 87][round % 4], 500);
  await clickWith(640 + 150 * Math.cos(round), 360 + 150 * Math.sin(round), round % 2 ? "right" : "left");
  await move(640 + 160, 360 - 40);
  await key(["KeyQ", "KeyE", "KeyR"][round % 3], ["q", "e", "r"][round % 3], [81, 69, 82][round % 3]);
  await sleep(350);
  if (round % 3 === 0) await shot(name(`fight-t${stamp().replace(".", "_")}`));
}
await key("KeyTab", "Tab", 9); await sleep(300); await shot(name("ranges"));
await key("KeyTab", "Tab", 9);
await key("KeyP", "p", 80); await sleep(300); await shot(name("paused"));
await key("KeyP", "p", 80);
report.afterFight = JSON.parse(await snapshot());

// Stand still (no input at all) and let the wave kill the player; a screenshot every ten seconds, so the death screen is caught.
const waitSeconds = Number(process.env.WAIT_SECONDS ?? 120);
for (let waited = 0; waited < waitSeconds; waited += 10) {
  await sleep(10000);
  await shot(name(`idle-${waited + 10}s`));
}
await sleep(1500);
await shot(name("death-screen"));
await key("KeyR", "r", 82);
await sleep(800);
await shot(name("restarted"));
report.afterRestart = JSON.parse(await snapshot());

// How many sounds started before and after the first user gesture, by the gesture's recorded timestamp (page clock, ms), and how soon
// the first one followed it. `startsWhileContextNotRunning` is kept apart on purpose: headless Chromium may report the context as
// running before any gesture, so it says nothing about the game's own gate.
const starts = JSON.parse(await evaluate("JSON.stringify(window.__audio.starts)"));
const firstGesture = JSON.parse(await evaluate("JSON.stringify(window.__audio.firstGesture)"));
report.soundsStarted = starts.length;
report.firstGesture = firstGesture;
if (firstGesture) {
  const before = starts.filter((s) => s.at < firstGesture.at);
  const after = starts.filter((s) => s.at >= firstGesture.at);
  report.startedBeforeFirstGesture = before.length;
  report.startedAfterFirstGesture = after.length;
  report.startedWithinSecondOfGesture = after.filter((s) => s.at - firstGesture.at <= 1000).length;
  report.firstStartAfterGestureMs = after.length ? Math.round((after[0].at - firstGesture.at) * 10) / 10 : null;
} else {
  report.startedBeforeFirstGesture = report.startedAfterFirstGesture = report.firstStartAfterGestureMs = null;
  report.error = "no trusted user gesture was observed";
}
report.startsWhileContextNotRunning = starts.filter((s) => s.state !== "running").length;
report.firstStartContextTime = starts[0]?.contextTime ?? null;
report.consoleErrors = consoleLines.filter((l) => /error|exception/i.test(l)).slice(0, 10);
writeFileSync(join(outDir, "audio-report.json"), JSON.stringify(report, null, 2));
writeFileSync(join(outDir, "console.log"), consoleLines.join("\n"));
console.log(JSON.stringify(report, null, 2));
ws.close();
proc.kill();
server.close();
