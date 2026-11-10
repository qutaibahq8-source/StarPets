#!/usr/bin/env node
// Renders thumbnail pages (thumbnails/<name>.html) to PNG with headless Chromium.
//   node render.js            -> every page
//   node render.js income     -> just income.html
// Output: out/<name>.png (1920x1080, Roblox thumbnail size), supersampled from a 2x render.
const http = require('http');
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { chromium } = require('playwright');

const ROOT = __dirname;
const OUT = path.join(ROOT, 'out');
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.woff': 'font/woff', '.png': 'image/png', '.json': 'application/json' };

function serve() {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      const file = path.join(ROOT, decodeURIComponent(new URL(req.url, 'http://x').pathname));
      if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
        res.writeHead(404); res.end(); return;
      }
      res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
      fs.createReadStream(file).pipe(res);
    });
    server.listen(0, '127.0.0.1', () => resolve(server));
  });
}

// 3840x2160 -> 1920x1080. ImageMagick (Lanczos) when installed, otherwise Chromium's own resampling.
async function downscale(browser, src, dst) {
  for (const bin of ['magick', 'convert']) {
    try {
      execFileSync(bin, [src, '-filter', 'Lanczos', '-resize', '1920x1080!', '-strip', dst], { stdio: 'ignore' });
      return;
    } catch { /* try the next option */ }
  }
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  const data = fs.readFileSync(src).toString('base64');
  await page.setContent(`<body style="margin:0"><img style="display:block;width:1920px;height:1080px" src="data:image/png;base64,${data}"></body>`);
  await page.waitForFunction(() => document.images[0].complete);
  await page.screenshot({ path: dst });
  await page.close();
}

(async () => {
  const args = process.argv.slice(2);
  const names = args.length ? args : fs.readdirSync(ROOT).filter((f) => f.endsWith('.html')).map((f) => f.slice(0, -5));
  fs.mkdirSync(OUT, { recursive: true });
  const server = await serve();
  const base = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  for (const name of names) {
    const t0 = Date.now();
    const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 2 });
    page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') console.log(`[${name}] ${m.type()}: ${m.text()}`); });
    page.on('pageerror', (e) => console.log(`[${name}] pageerror: ${e.message}`));
    await page.goto(`${base}/${name}.html`);
    await page.waitForFunction(() => window.__thumbReady === true || window.__thumbError, null, { timeout: 600000 });
    const err = await page.evaluate(() => window.__thumbError);
    if (err) throw new Error(`${name}: ${err}`);
    const big = path.join(OUT, `${name}@2x.png`);
    const final = path.join(OUT, `${name}.png`);
    await page.screenshot({ path: big });
    await downscale(browser, big, final);
    console.log(`${name}: out/${name}.png (${((Date.now() - t0) / 1000).toFixed(1)}s)`);
    await page.close();
  }
  await browser.close();
  server.close();
})().catch((e) => { console.error(e); process.exit(1); });
