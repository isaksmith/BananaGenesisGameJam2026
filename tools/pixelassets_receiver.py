#!/usr/bin/env python3
"""Local receiver: browser POSTs signed itch batches; we download into PixelAssets."""
from http.server import BaseHTTPRequestHandler, HTTPServer
import json, re, threading, urllib.request
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

DEST = Path.home() / "Downloads" / "PixelAssets"
DEST.mkdir(parents=True, exist_ok=True)
LOG = DEST / "_download_log.txt"
PORT = 8765

def safe(s: str) -> str:
    s = re.sub(r'[\/\\?%*:|"<>]+', "-", s)
    return re.sub(r"\s+", " ", s).strip()[:120]

def fetch_one(title: str, name: str, url: str):
    folder = DEST / safe(title)
    folder.mkdir(parents=True, exist_ok=True)
    name = re.sub(r"\s+\d+(\.\d+)?\s*[kKmMgG]?[bB]\s*$", "", name).strip()
    name = safe(name)
    if not re.search(r"\.[A-Za-z0-9]{2,5}$", name):
        name += ".zip"
    dest = folder / name
    if dest.exists() and dest.stat().st_size > 1000:
        return f"skip {title}/{name}"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=180) as r, open(dest, "wb") as f:
        while True:
            chunk = r.read(256 * 1024)
            if not chunk:
                break
            f.write(chunk)
    return f"ok {title}/{name} ({dest.stat().st_size})"

def handle_batch(packs):
    jobs = []
    for pack in packs:
        title = pack.get("title") or "pack"
        for f in pack.get("files") or []:
            if f.get("url"):
                jobs.append((title, f.get("name") or "file.zip", f["url"]))
    results = []
    with ThreadPoolExecutor(max_workers=10) as ex:
        futs = [ex.submit(fetch_one, *j) for j in jobs]
        for fut in as_completed(futs):
            try:
                results.append(fut.result())
            except Exception as e:
                results.append(f"ERR {e}")
    with open(LOG, "a") as log:
        for line in results:
            log.write(line + "\n")
            print(line, flush=True)
    return {"downloaded": len([r for r in results if r.startswith("ok")]), "total": len(jobs), "results": results}


class Handler(BaseHTTPRequestHandler):
    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS, GET")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        self.send_response(200)
        self._cors()
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"PixelAssets receiver OK\n")

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        try:
            packs = json.loads(body.decode("utf-8"))
            if isinstance(packs, dict) and "packs" in packs:
                packs = packs["packs"]
            summary = handle_batch(packs)
            payload = json.dumps(summary).encode()
            self.send_response(200)
            self._cors()
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(payload)
        except Exception as e:
            self.send_response(500)
            self._cors()
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode())

    def log_message(self, fmt, *args):
        print("[recv]", fmt % args, flush=True)


if __name__ == "__main__":
    print(f"Listening on http://127.0.0.1:{PORT} → {DEST}", flush=True)
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
