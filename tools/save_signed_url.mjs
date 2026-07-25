#!/usr/bin/env node
/**
 * Helper: given a JSON line on stdin with {title,url,name}, download to PixelAssets.
 * Used with browser-extracted signed URLs (60s TTL).
 */
import fs from "fs";
import path from "path";
import os from "os";
import https from "https";
import http from "http";

const DEST = path.join(os.homedir(), "Downloads", "PixelAssets");

function safe(s) {
  return String(s).replace(/[\/\\?%*:|"<>]/g, "-").replace(/\s+/g, " ").trim().slice(0, 120);
}

function download(url, dest) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(dest);
    const lib = url.startsWith("https") ? https : http;
    lib
      .get(url, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          file.close();
          fs.unlinkSync(dest);
          return download(res.headers.location, dest).then(resolve, reject);
        }
        if (res.statusCode !== 200) {
          reject(new Error("HTTP " + res.statusCode));
          return;
        }
        res.pipe(file);
        file.on("finish", () => {
          file.close();
          resolve(fs.statSync(dest).size);
        });
      })
      .on("error", reject);
  });
}

const item = JSON.parse(fs.readFileSync(0, "utf8"));
const folder = path.join(DEST, safe(item.title));
fs.mkdirSync(folder, { recursive: true });
let name = item.name || "pack.zip";
if (!/\.[a-z0-9]{2,5}$/i.test(name)) name += ".zip";
const dest = path.join(folder, safe(name));
if (fs.existsSync(dest) && fs.statSync(dest).size > 1000) {
  console.log("skip exists", dest);
  process.exit(0);
}
const size = await download(item.url, dest);
console.log("ok", dest, size);
