#!/usr/bin/env node
/**
 * Opens Gmail with Playwright, finds emails that look like resource-pack
 * download links, downloads each file into ~/Downloads/PixelAssets.
 *
 * If not signed in, complete Google login in the opened window — the script
 * waits up to 5 minutes for the inbox to appear.
 */
import { chromium } from "playwright";
import fs from "fs";
import path from "path";
import os from "os";
import { pathToFileURL } from "url";

const DEST = path.join(os.homedir(), "Downloads", "PixelAssets");
const PROFILE = path.join(os.homedir(), ".cache", "gamejam-playwright-gmail");
const SEARCH =
  process.env.GMAIL_SEARCH ||
  '(filename:zip OR "download" OR "resource pack" OR itch.io OR "your download" OR "download link") newer_than:90d';

fs.mkdirSync(DEST, { recursive: true });
fs.mkdirSync(PROFILE, { recursive: true });

function safeName(name) {
  return String(name || "download.bin")
    .replace(/[^\w.\- ()[\]]+/g, "_")
    .slice(0, 180);
}

function looksLikePackUrl(href) {
  if (!href) return false;
  const h = href.toLowerCase();
  if (h.startsWith("mailto:") || h.includes("accounts.google") || h.includes("support.google"))
    return false;
  // Direct archives / CDN / itch / dropbox / drive / we.tl / mega / gumroad
  if (/\.(zip|rar|7z|tar\.gz)(\?|$)/i.test(h)) return true;
  if (
    /itch\.io\/download|drive\.google\.com|dropbox\.com|dl\.dropboxusercontent|we\.tl|mega\.nz|gumroad\.com|mediafire\.com|pixeljoint|opengameart|kenney\.nl|file\.io|wetransfer|send\.firefox|pixel-?assets|resource.?pack/i.test(
      h
    )
  )
    return true;
  if (/download|file|asset|pack|zip/i.test(h) && /^https?:\/\//i.test(h)) return true;
  return false;
}

async function waitForInbox(page) {
  const deadline = Date.now() + 5 * 60 * 1000;
  while (Date.now() < deadline) {
    const url = page.url();
    if (/mail\.google\.com\/mail/i.test(url) && !/ServiceLogin|accounts\.google/i.test(url)) {
      // Inbox chrome present
      const ok = await page.locator('[role="main"], [gh="tm"], input[aria-label*="Search"]').first().isVisible().catch(() => false);
      if (ok) return;
    }
    console.log("Waiting for Gmail inbox / login…", url.slice(0, 80));
    await page.waitForTimeout(3000);
  }
  throw new Error("Timed out waiting for Gmail login/inbox.");
}

async function collectThreadLinks(page) {
  // Expand clipped content if present
  const expand = page.locator('span:has-text("…"), span:has-text("Show trimmed content"), [data-tooltip="Show trimmed content"]').first();
  if (await expand.isVisible().catch(() => false)) {
    await expand.click().catch(() => {});
    await page.waitForTimeout(500);
  }

  const links = await page.evaluate(() => {
    const out = [];
    for (const a of document.querySelectorAll('div[role="main"] a[href]')) {
      const href = a.href;
      const text = (a.innerText || a.textContent || "").trim();
      if (!href || href.startsWith("javascript:")) continue;
      out.push({ href, text });
    }
    return out;
  });

  const filtered = [];
  const seen = new Set();
  for (const L of links) {
    let href = L.href;
    // Unwrap Google redirect
    try {
      const u = new URL(href);
      if (u.hostname.includes("google.com") && u.pathname.includes("/url")) {
        href = u.searchParams.get("q") || u.searchParams.get("url") || href;
      }
    } catch {}
    if (!looksLikePackUrl(href)) continue;
    if (seen.has(href)) continue;
    seen.add(href);
    filtered.push({ href, text: L.text });
  }
  return filtered;
}

async function downloadUrl(context, href, destDir) {
  const page = await context.newPage();
  try {
    const [download] = await Promise.all([
      page.waitForEvent("download", { timeout: 45000 }).catch(() => null),
      page.goto(href, { waitUntil: "domcontentloaded", timeout: 60000 }).catch(() => null),
    ]);

    if (download) {
      const suggested = safeName(download.suggestedFilename());
      const target = path.join(destDir, suggested);
      await download.saveAs(target);
      console.log("Saved:", target);
      return target;
    }

    // Maybe a page with a download button
    const btn = page
      .locator(
        'a:has-text("Download"), button:has-text("Download"), a[download], a[href*=".zip"], a[href*="download"]'
      )
      .first();
    if (await btn.isVisible({ timeout: 5000 }).catch(() => false)) {
      const [dl2] = await Promise.all([
        page.waitForEvent("download", { timeout: 60000 }),
        btn.click(),
      ]);
      const suggested = safeName(dl2.suggestedFilename());
      const target = path.join(destDir, suggested);
      await dl2.saveAs(target);
      console.log("Saved via button:", target);
      return target;
    }

    // Fetch via API request from browser context (cookies/session)
    const res = await page.request.get(href);
    const cd = res.headers()["content-disposition"] || "";
    let name = "pack.bin";
    const m = /filename\*?=(?:UTF-8'')?["']?([^"';]+)/i.exec(cd);
    if (m) name = decodeURIComponent(m[1]);
    else {
      try {
        name = path.basename(new URL(href).pathname) || name;
      } catch {}
    }
    if (!/\.(zip|rar|7z|png|jpg|gif|mp3|wav|ogg|glb|fbx|aseprite)$/i.test(name)) {
      const ct = res.headers()["content-type"] || "";
      if (ct.includes("zip") || ct.includes("octet-stream")) name = name.replace(/\.[^.]+$/, "") + ".zip";
    }
    const buf = await res.body();
    if (buf && buf.length > 200) {
      const target = path.join(destDir, safeName(name));
      fs.writeFileSync(target, buf);
      console.log("Fetched:", target, `(${buf.length} bytes)`);
      return target;
    }

    console.warn("No download found for", href);
    return null;
  } finally {
    await page.close().catch(() => {});
  }
}

async function main() {
  console.log("Destination:", DEST);
  console.log("Gmail search:", SEARCH);

  const context = await chromium.launchPersistentContext(PROFILE, {
    headless: false,
    channel: "chrome",
    acceptDownloads: true,
    viewport: { width: 1400, height: 900 },
    downloadsPath: DEST,
    args: ["--disable-blink-features=AutomationControlled"],
    ignoreDefaultArgs: ["--enable-automation"],
  });
  const page = context.pages()[0] || (await context.newPage());

  await page.goto("https://mail.google.com/mail/u/0/#inbox", {
    waitUntil: "domcontentloaded",
    timeout: 120000,
  });
  await waitForInbox(page);

  // Run search
  const searchBox = page.locator('input[aria-label*="Search"], form[role="search"] input').first();
  await searchBox.click({ timeout: 15000 });
  await searchBox.fill("");
  await searchBox.fill(SEARCH);
  await searchBox.press("Enter");
  await page.waitForTimeout(2500);

  // Collect thread row ids / subjects
  const rows = page.locator('tr.zA, div[role="main"] tr[jscontroller]');
  let count = await rows.count();
  if (count === 0) {
    // Fallback: any clickable thread in list
    const alt = page.locator('div[role="main"] table tr');
    count = Math.min(await alt.count(), 40);
    console.log("Using fallback rows:", count);
  } else {
    count = Math.min(count, 40);
  }
  console.log("Threads to scan:", count);

  const allLinks = [];
  const seen = new Set();

  for (let i = 0; i < count; i++) {
    const row = rows.nth(i);
    if (!(await row.isVisible().catch(() => false))) continue;
    const subject = (await row.innerText().catch(() => "")).replace(/\s+/g, " ").slice(0, 120);
    console.log(`\n[${i + 1}/${count}] ${subject}`);
    await row.click({ timeout: 10000 }).catch(async () => {
      await row.locator("td").nth(1).click().catch(() => {});
    });
    await page.waitForTimeout(1500);

    const links = await collectThreadLinks(page);
    for (const L of links) {
      if (seen.has(L.href)) continue;
      seen.add(L.href);
      allLinks.push({ ...L, subject });
      console.log("  link:", L.href.slice(0, 120));
    }

    // Back to search results
    await page.goBack({ waitUntil: "domcontentloaded" }).catch(() => {});
    await page.waitForTimeout(800);
  }

  console.log(`\nUnique candidate links: ${allLinks.length}`);
  const saved = [];
  for (const L of allLinks) {
    try {
      const file = await downloadUrl(context, L.href, DEST);
      if (file) saved.push(file);
    } catch (e) {
      console.warn("Failed:", L.href, e.message);
    }
  }

  // Move any stray downloads that landed in DEST already
  console.log("\nDone. Files in PixelAssets:");
  for (const f of fs.readdirSync(DEST)) {
    console.log(" -", f);
  }
  console.log(`Downloaded ${saved.length} file(s).`);

  // Keep browser open briefly so user can see result, then close
  await page.waitForTimeout(2000);
  await context.close();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
