// Renders index.html frame by frame with headless Chromium.
//   node render.mjs <outDir> [fps=30] [workers=4]        full film → outDir/00000.jpg …
//   node render.mjs <outDir> --stills 1.5,12,20           preview stills → outDir/still-<t>.png
// SCALE=2 renders at 3840×2160 (the scene is laid out at 1920×1080 and is resolution-independent).
import { chromium } from "playwright";
import { mkdirSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";
import { dirname, join } from "node:path";

const DURATION = 45, SCALE = Number(process.env.SCALE || 1);
const here = dirname(fileURLToPath(import.meta.url));
const url = pathToFileURL(join(here, "index.html")).href;
const [outDir, a2, a3] = process.argv.slice(2);
mkdirSync(outDir, { recursive: true });

const browser = await chromium.launch({ args: ["--allow-file-access-from-files", "--force-color-profile=srgb"] });
async function page() {
  const p = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: SCALE });
  await p.goto(url);
  await p.evaluate(() => Promise.all([document.fonts.ready, ...[...document.images].map((i) => i.decode().catch(() => {}))]));
  return p;
}

if (a2 === "--stills") {
  const p = await page();
  for (const t of a3.split(",").map(Number)) {
    await p.evaluate((t) => window.render(t), t);
    await p.screenshot({ path: join(outDir, `still-${t}.png`) });
  }
} else {
  const fps = Number(a2 || 30), workers = Number(a3 || 4), total = DURATION * fps;
  let done = 0; const start = Date.now();
  await Promise.all(Array.from({ length: workers }, async (_, w) => {
    const p = await page();
    for (let f = w; f < total; f += workers) {
      await p.evaluate(([t, fps]) => window.render(t, fps), [f / fps, fps]);
      await p.screenshot({ path: join(outDir, String(f).padStart(5, "0") + ".jpg"), type: "jpeg", quality: 94 });
      if (++done % 100 === 0) console.log(`${done}/${total} frames · ${((Date.now() - start) / 1000).toFixed(0)}s`);
    }
  }));
}
await browser.close();
