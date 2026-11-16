#!/usr/bin/env node
// Plays the exported Web build in headless Chromium with phone emulation (touch events, device scale
// factor, portrait and landscape, a safe area, the page being hidden) and writes page screenshots.
// Evidence for issue #20 (Android touch controls); not part of the build. Physical Android checks are
// deferred to the device matrix (#6 / #22): this stands in for them and does not replace them.
//
//   node tools/godot/web-touch-capture.mjs <chrome-headless-shell> <web-bundle-dir> <out-dir>
//
// The page is driven only through the Chrome DevTools Protocol: real touch events
// (`Input.dispatchTouchEvent` with several points at once), device metrics, safe-area insets and
// page events. Nothing touches the desktop and the game has no test hooks. Needs Node 22+.
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { extname, join, normalize } from "node:path";

const [chrome, bundle, outDir] = process.argv.slice(2);
if (!chrome || !bundle || !outDir) {
  console.error("usage: web-touch-capture.mjs <chrome-headless-shell> <web-bundle-dir> <out-dir>");
  process.exit(2);
}
mkdirSync(outDir, { recursive: true });
const DPR = Number(process.env.DPR ?? 2);

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
const evaluate = async (expression) => (await send("Runtime.evaluate", { expression, returnByValue: true })).result?.result?.value;

// ---- fingers: every point that is down is sent with each event, like a real touchscreen
const down = new Map(); // id -> {x, y}
const points = () => [...down.entries()].map(([id, p]) => ({ x: p.x, y: p.y, id, radiusX: 8, radiusY: 8, force: 1 }));
const finger = {
  async start(id, x, y) { down.set(id, { x, y }); await send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: points() }); },
  async move(id, x, y) { down.set(id, { x, y }); await send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: points() }); },
  async end(id) { down.delete(id); await send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: points() }); },
  async cancel() { down.clear(); await send("Input.dispatchTouchEvent", { type: "touchCancel", touchPoints: [] }); },
  async tap(id, x, y) { await finger.start(id, x, y); await sleep(60); await finger.end(id); },
};

// ---- where the controls are, from the layout the game documents (godot/scripts/input/touch_layout.gd)
let view = { w: 0, h: 0, vx: 0, vy: 0, s: 1 };
const setView = async (w, h) => {
  view.w = w; view.h = h;
  const portrait = h > w;
  view.s = portrait ? Math.min(w / 720, h / 1280) : Math.min(w / 1280, h / 720);
  view.vx = w / view.s; view.vy = h / view.s;
  await send("Emulation.setDeviceMetricsOverride", { width: w, height: h, deviceScaleFactor: DPR, mobile: true, screenWidth: w, screenHeight: h, screenOrientation: { type: portrait ? "portraitPrimary" : "landscapePrimary", angle: portrait ? 0 : 90 } });
};
const css = (lx, ly) => ({ x: Math.round(lx * view.s), y: Math.round(ly * view.s) });
const lift = () => (view.vx >= 1100 ? 0 : 126);
const where = {
  dash: () => css(view.vx - 128 + 52, view.vy - 128 + 52),
  converge: () => css(view.vx - 128 + 52, view.vy - 128 - 10 - 52),
  ultimate: (i) => css(view.vx - 128 - 120 - 10 - (3 - i) * 96 - (2 - i) * 10 + 48, view.vy - 24 - 96 - lift() + 48),
  swap: (i) => css(view.vx - 128 - 120 - 10 - (3 - i) * 96 - (2 - i) * 10 + 48, view.vy - 24 - 96 - lift() - 10 - 39),
  ranges: () => css(view.vx - 24 - 48, 116 + 39),
  pause: () => css(view.vx - 176 + 36, 16 + 22),
  resume: () => css(view.vx * 0.4, view.vy * 0.5 + 130),
  arena: (dx, dy) => css(view.vx * 0.5 + dx, view.vy * 0.5 + dy),
};

await send("Runtime.enable");
await send("Page.enable");
await send("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 5 });
await send("Emulation.setEmitTouchEventsForMouse", { enabled: false });

const boot = async (w, h, query = "") => {
  await setView(w, h);
  await send("Page.navigate", { url: `${base}${query}` });
  for (let i = 0; i < 1200 && !consoleLines.some((l) => l.includes("Build configuration")); i++) await sleep(20);
  await sleep(4000);
};

// 1. portrait phone, no touch yet: the platform reports a touchscreen, so the controls are already up
await boot(412, 915);
console.log("touch available in the page:", await evaluate("'ontouchstart' in window && navigator.maxTouchPoints"));
await shot("01-portrait-first-screen");
await finger.tap(0, ...Object.values(where.arena(60, -120)));
await sleep(150); await shot("02-portrait-tap-converge");

// 2. the same phone turned sideways, under the running game
await setView(915, 412);
await sleep(1500);
await shot("03-landscape-after-turn");

// 3. a tap on the arena aims Converge at the tapped world point; a tap on a button never does
await sleep(2600); // the Converge cooldown (2.5 s) ends
const tapAt = where.arena(230, -90);
await finger.tap(0, tapAt.x, tapAt.y);
await sleep(120); await shot("04-landscape-tap-converge-at-point");
await sleep(2600);
const converge = where.converge();
await finger.tap(0, converge.x, converge.y);
await sleep(120); await shot("05-landscape-converge-button-nearest");

// 4. simultaneous: the left thumb steers, a second finger dashes, a third presses an ultimate
const stick = css(260, 420);
await finger.start(0, stick.x, stick.y);
for (let i = 1; i <= 6; i++) { await finger.move(0, stick.x + i * 10, stick.y - i * 4); await sleep(60); }
await sleep(500);
await shot("06-landscape-stick-held");
const dash = where.dash();
await finger.start(1, dash.x, dash.y);
const ult = where.ultimate(0);
await finger.start(2, ult.x, ult.y);
await sleep(120); await shot("07-landscape-stick-dash-ultimate-together");
await finger.end(2); await finger.end(1);
await sleep(300); await shot("08-landscape-stick-still-steering");
await finger.end(0);

// 5. the page is hidden (another tab, the app sent to the background): the run pauses and waits for an explicit resume
await evaluate("Object.defineProperty(document, 'hidden', {configurable: true, get: () => true}); document.dispatchEvent(new Event('visibilitychange'))");
await sleep(400); await shot("09-page-hidden-paused");
await evaluate("Object.defineProperty(document, 'hidden', {configurable: true, get: () => false}); document.dispatchEvent(new Event('visibilitychange'))");
await sleep(1500); await shot("10-page-back-still-paused");
const resume = where.resume();
await finger.tap(0, resume.x, resume.y);
await sleep(600); await shot("11-resumed-by-tap");

// 6. a window blur and a cancelled touch
await finger.start(0, stick.x, stick.y);
await finger.move(0, stick.x + 60, stick.y);
await sleep(300);
await finger.cancel();
await sleep(500); await shot("12-touch-cancelled-stopped");

// 7. a notch: safe-area insets (the page's env(safe-area-inset-*))
await send("Emulation.setSafeAreaInsetsOverride", { insets: { top: 24, left: 48, right: 48, bottom: 20 } });
console.log("env() probe after the override:", await evaluate("(function(){var d=document.createElement('div');d.style.cssText='position:fixed;padding:env(safe-area-inset-top,0px) env(safe-area-inset-right,0px) env(safe-area-inset-bottom,0px) env(safe-area-inset-left,0px)';document.body.appendChild(d);var s=getComputedStyle(d);var r=[s.paddingTop,s.paddingRight,s.paddingBottom,s.paddingLeft].join(',');document.body.removeChild(d);return r;})()"));
await boot(915, 412, "?safe=24,48,20,48");
await shot("13-landscape-safe-area-notch");
await send("Emulation.setSafeAreaInsetsOverride", { insets: { top: 0, left: 0, right: 0, bottom: 0 } });

// 8. portrait again with the notch in the other direction, and a tablet shape
await boot(412, 915, "?safe=40,0,30,0");
await shot("14-portrait-safe-area");
await boot(768, 1024);
await shot("15-tablet-portrait");

writeFileSync(join(outDir, "console.log"), consoleLines.join("\n"));
console.log(consoleLines.filter((l) => /error|exception/i.test(l)).slice(0, 10).join("\n") || "no console errors");
proc.kill();
server.close();
process.exit(0);
