<img src="assets/icon.svg" width="64" height="64" alt="">

# swordster

Created in [T3 Code](https://t3.codes).

A prototype for a game where three spirit swords hover around you and attack on their own.

## Run

```bash
python3 -m venv .venv && .venv/bin/pip install pygame-ce pygbag
.venv/bin/python game/main.py                      # desktop
.venv/bin/python serve.py                          # build and serve browser demo
```

Open **http://localhost:8000** and click the page when prompted to start the game.
The browser downloads its Python/Pygame runtime from Pygbag's CDN, so the first
load needs internet access and may take a moment.

Restart the server after editing the game to rebuild, then refresh your browser.
Use `--no-build` to serve an existing build, `--port 8080` to change the port, or
`--host 0.0.0.0` to demo on another device on your network using this computer's IP.
Press Ctrl+C to stop the server.

For a remote demo over Tailscale, bind to this computer's Tailscale address:

```bash
.venv/bin/python serve.py --host "$(tailscale ip -4)"
```

Open `http://<server-tailscale-ip>:8000` from a device connected to your tailnet.

## Controls

WASD move · Space/Shift dash · Q or click: Converge (all swords strike the cursor) ·
1/2/3 swap a dropped sword into that slot · Tab/G show ranges · P pause · H help · R restart

On a smartphone, use the left joystick to move and **DASH** to evade. **STRIKE**
converges on the nearest enemy; tap the arena to aim at a specific point. **SLOT
1/2/3** swaps a nearby dropped sword. Touch buttons also provide pause, restart,
range display, and fullscreen (where supported). Rotate to landscape for a larger
arena. Switching away from the browser pauses the game; tap **PAUSE** to resume.
