#!/usr/bin/env python3
"""Download itch signed URL batch into ~/Downloads/PixelAssets."""
import json, re, sys, urllib.request
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

DEST = Path.home() / "Downloads" / "PixelAssets"

def safe(s: str) -> str:
    s = re.sub(r'[\/\\?%*:|"<>]+', "-", s)
    return re.sub(r"\s+", " ", s).strip()[:120]

def fetch(title: str, name: str, url: str):
    folder = DEST / safe(title)
    folder.mkdir(parents=True, exist_ok=True)
    name = safe(name.split()[0] if " " in name and name.lower().endswith("kb") else name)
    # clean names like "IcePlatform.zip 141 kB"
    name = re.sub(r"\s+\d+(\.\d+)?\s*[kKmMgG]?[bB]\s*$", "", name).strip()
    if not re.search(r"\.[A-Za-z0-9]{2,5}$", name):
        name += ".zip"
    dest = folder / name
    if dest.exists() and dest.stat().st_size > 1000:
        return f"skip {dest.name}"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=120) as r, open(dest, "wb") as f:
        while True:
            chunk = r.read(1024 * 256)
            if not chunk:
                break
            f.write(chunk)
    return f"ok {dest.name} ({dest.stat().st_size})"

def main():
    packs = json.loads(Path(sys.argv[1]).read_text())
    jobs = []
    for pack in packs:
        title = pack["title"]
        for f in pack.get("files") or []:
            if f.get("url"):
                jobs.append((title, f.get("name") or f["id"] + ".zip", f["url"]))
    print(f"jobs={len(jobs)}")
    with ThreadPoolExecutor(max_workers=8) as ex:
        futs = [ex.submit(fetch, *j) for j in jobs]
        for fut in as_completed(futs):
            try:
                print(fut.result())
            except Exception as e:
                print("ERR", e)

if __name__ == "__main__":
    main()
