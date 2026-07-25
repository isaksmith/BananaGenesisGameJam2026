#!/usr/bin/env node
/**
 * Download itch.io purchase packs into ~/Downloads/PixelAssets
 * using purchase-key download pages (no browser login required).
 */
import { chromium } from "playwright";
import fs from "fs";
import path from "path";
import os from "os";

const DEST = path.join(os.homedir(), "Downloads", "PixelAssets");
const MANIFEST = path.join(DEST, "_manifest.json");
fs.mkdirSync(DEST, { recursive: true });

function safeName(name) {
  return String(name || "download.bin")
    .replace(/[\/\\?%*:|"<>]/g, "-")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 160);
}

async function downloadPack(context, item, index, total) {
  const page = await context.newPage();
  try {
    console.log(`\n[${index + 1}/${total}] ${item.title}`);
    await page.goto(item.href, { waitUntil: "domcontentloaded", timeout: 90000 });
    await page.waitForTimeout(800);

    // File rows: buttons that trigger downloads
    const fileLinks = await page.evaluate(() => {
      const out = [];
      const seen = new Set();
      const candidates = [
        ...document.querySelectorAll("a.upload_btn_download, a[download], a.button.download_btn"),
        ...document.querySelectorAll(".upload_list_widget a.button, .upload_row a.button"),
        ...document.querySelectorAll('a[href*="/file/"]'),
      ];
      for (const a of candidates) {
        const href = a.href;
        if (!href || seen.has(href)) continue;
        // skip share/social
        if (/twitter|facebook|reddit|mailto/i.test(href)) continue;
        seen.add(href);
        const label =
          a.getAttribute("data-upload_name") ||
          a.getAttribute("title") ||
          a.innerText.trim() ||
          "file";
        out.push({ href, label });
      }
      // Also look for form posts / data attributes
      document.querySelectorAll("[data-upload_id]").forEach((el) => {
        const a = el.matches("a") ? el : el.querySelector("a");
        if (a && a.href && !seen.has(a.href)) {
          seen.add(a.href);
          out.push({ href: a.href, label: a.innerText.trim() || "file" });
        }
      });
      return out;
    });

    if (fileLinks.length === 0) {
      // Fallback: any strong Download button
      const btn = page.locator('a:has-text("Download"), button:has-text("Download")').first();
      if (await btn.isVisible({ timeout: 3000 }).catch(() => false)) {
        const [download] = await Promise.all([
          page.waitForEvent("download", { timeout: 120000 }),
          btn.click(),
        ]);
        const folder = path.join(DEST, safeName(item.title));
        fs.mkdirSync(folder, { recursive: true });
        const target = path.join(folder, safeName(download.suggestedFilename()));
        await download.saveAs(target);
        console.log("  saved:", target);
        return [target];
      }
      console.warn("  no files found");
      return [];
    }

    const folder = path.join(DEST, safeName(item.title));
    fs.mkdirSync(folder, { recursive: true });
    const saved = [];

    for (const file of fileLinks) {
      try {
        const [download] = await Promise.all([
          page.waitForEvent("download", { timeout: 180000 }).catch(() => null),
          page.goto(file.href, { waitUntil: "commit", timeout: 120000 }).catch(() => null),
        ]);
        if (download) {
          const target = path.join(folder, safeName(download.suggestedFilename()));
          await download.saveAs(target);
          console.log("  saved:", path.basename(target));
          saved.push(target);
          continue;
        }
        // Try clicking if navigation didn't trigger download
        const res = await page.request.get(file.href);
        const buf = Buffer.from(await res.body());
        if (buf.length < 500) {
          console.warn("  tiny response for", file.label, buf.length);
          continue;
        }
        const cd = res.headers()["content-disposition"] || "";
        let name = file.label;
        const m = /filename\*?=(?:UTF-8'')?["']?([^"';]+)/i.exec(cd);
        if (m) name = decodeURIComponent(m[1]);
        else if (!/\.[a-z0-9]{2,5}$/i.test(name)) name += ".zip";
        const target = path.join(folder, safeName(name));
        fs.writeFileSync(target, buf);
        console.log("  fetched:", path.basename(target), `(${buf.length} bytes)`);
        saved.push(target);
      } catch (e) {
        console.warn("  failed file:", file.label, e.message);
      }
    }
    return saved;
  } finally {
    await page.close().catch(() => {});
  }
}

async function main() {
  const items = JSON.parse(fs.readFileSync(MANIFEST, "utf8"));
  console.log(`Downloading ${items.length} packs → ${DEST}`);
  const browser = await chromium.launch({ headless: true, channel: "chrome" });
  const context = await browser.newContext({ acceptDownloads: true });
  let ok = 0;
  for (let i = 0; i < items.length; i++) {
    const saved = await downloadPack(context, items[i], i, items.length);
    if (saved.length) ok++;
  }
  await browser.close();
  console.log(`\nDone. Packs with files: ${ok}/${items.length}`);
  console.log("Listing:", DEST);
  for (const f of fs.readdirSync(DEST).filter((x) => x !== "_manifest.json")) {
    console.log(" -", f);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
