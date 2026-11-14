#!/usr/bin/env node
// Plays the exported Web build's crowd encounter in headless Chromium and writes
// page screenshots. Evidence for issue #9; not part of the build.
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
const key = async (code, k, vk) => {
  const common = { code, key: k, windowsVirtualKeyCode: vk, nativeVirtualKeyCode: vk };
  await send("Input.dispatchKeyEvent", { type: "rawKeyDown", ...common });
  await send("Input.dispatchKeyEvent", { type: "keyUp", ...common });
};
const click = async (x, y) => {
  await send("Input.dispatchMouseEvent", { type: "mouseMoved", x, y });
  await send("Input.dispatchMouseEvent", { type: "mousePressed", x, y, button: "left", buttons: 1, clickCount: 1 });
  await send("Input.dispatchMouseEvent", { type: "mouseReleased", x, y, button: "left", buttons: 0, clickCount: 1 });
};

await send("Runtime.enable");
await send("Page.enable");
await send("Emulation.setDeviceMetricsOverride", { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });
const scenario = process.env.SCENARIO ?? "crowd"; // crowd | wall | normal
const query = scenario === "normal" ? "" : `?encounter=${scenario}`;
await send("Page.navigate", { url: `${base}${query}` });
await sleep(5000);
await click(640, 360); // focus the canvas and unlock audio
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
  await key("KeyC", "c", 67); // switch back to the normal husk wave
  await sleep(1500); await shot("crowd-05-normal-wave");
  await key("KeyC", "c", 67); // and into the encounter again
  await sleep(1500); await shot("crowd-06-encounter-again");
} else if (scenario === "wall") {
  await shot("wall-01-pinned");
  await key("KeyF", "f", 70);
  console.log(`shove F at ${stamp()}s`);
  for (const wait of [100, 150, 200, 300]) { await sleep(wait); await shot(`wall-02-shoved-${wait}`); }
  await sleep(1500); await shot("wall-03-aftermath");
  await key("KeyF", "f", 70);
  for (const wait of [150, 300]) { await sleep(wait); await shot(`wall-04-second-shove-${wait}`); }
} else {
  await sleep(2500); await shot("normal-01");
}
writeFileSync(join(outDir, "console.log"), consoleLines.join("\n") + "\n");
console.log(`console lines: ${consoleLines.length}`);
ws.close();
proc.kill();
server.close();
process.exit(0);
