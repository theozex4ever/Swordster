"""Build and serve the Swordster browser demo."""

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import shutil
import sys


ROOT = Path(__file__).resolve().parent
WEB_ROOT = ROOT / "game" / "build" / "web"


class DemoHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        # A refresh should pick up a newly built game immediately.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def list_directory(self, path):
        self.send_error(404, "File not found")
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1", help="Bind address (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=8000, help="Port (default: 8000)")
    parser.add_argument("--no-build", action="store_true", help="Serve the existing browser build")
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("--port must be between 1 and 65535")

    if not args.no_build:
        try:
            import pygbag  # noqa: F401
        except ImportError:
            parser.exit(1, "Install the browser build dependencies first: python -m pip install pygame-ce pygbag\n")
        print("Building Swordster for the browser...", flush=True)
        subprocess.run([sys.executable, "-m", "pygbag", "--build", "game"], cwd=ROOT, check=True)

    if not (WEB_ROOT / "index.html").is_file():
        parser.exit(1, "No browser build found. Run again without --no-build.\n")

    # Keep browser controls outside Pygbag's archive and install on every launch.
    for name in ("mobile.js", "mobile.css"):
        shutil.copyfile(ROOT / "web" / name, WEB_ROOT / name)
    index = WEB_ROOT / "index.html"
    html = index.read_text()
    if 'src="mobile.js"' not in html:
        html = html.replace("</head>", '<link rel="stylesheet" href="mobile.css">\n</head>')
        html = html.replace("</body>", '<script src="mobile.js"></script>\n</body>')
        index.write_text(html)

    handler = partial(DemoHandler, directory=str(WEB_ROOT))
    try:
        server = ThreadingHTTPServer((args.host, args.port), handler)
    except OSError as exc:
        parser.exit(1, f"Could not start the demo server: {exc}\n")
    display_host = "localhost" if args.host in ("127.0.0.1", "0.0.0.0") else args.host
    with server:
        print(f"Swordster demo: http://{display_host}:{args.port}\nPress Ctrl+C to stop.", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("\nDemo server stopped.")


if __name__ == "__main__":
    main()
