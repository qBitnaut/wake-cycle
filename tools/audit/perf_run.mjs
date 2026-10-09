// Perf harness (investigation): frame-time distribution at chosen spots, optional CPU throttling,
// optional runtime ablations (window.wakeAblate from PerfProbe). Needs the PERF HARNESS commit's
// export (hooks in a release template).
//
// (--url=start=map_completed=room1 for the map: '_' joins the query parameters)
//   node tools/audit/perf_run.mjs <export_dir> --room=room2 --spots=a:3000:700,b:900:700 \
//     [--gpu=dgpu|igpu|swift] [--throttle=1] [--w=1280 --h=720] [--secs=20] [--ablate=rain,puddles] [--out=file.jsonl]
//
// Serves the export on PORT (default 12100). Own browser only.
import { createRequire } from 'node:module';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const PW = process.env.PW_DIR
  || path.join(os.homedir(), '.local/share/mise/installs/npm-playwright/latest/node_modules/playwright');
const { chromium } = createRequire(import.meta.url)(PW);
const root = process.argv[2];
const opt = Object.fromEntries(process.argv.slice(3).filter(a => a.startsWith('--')).map(a => { const [k, v = '1'] = a.slice(2).split('='); return [k, v]; }));
const room = opt.room || 'room1';
// spot = name:x:y, or name:x1~x2~x3:y for a sweep (teleport along the list, dwell secs/len on each)
const spots = (opt.spots || 'start:0:0').split(',').map(s => { const [n, x, y] = s.split(':'); return x.includes('~') ? { n, xs: x.split('~').map(Number), y: +y } : { n, x: +x, y: +y }; });
const secs = +(opt.secs || 20);
const thr = +(opt.throttle || 1);
const W = +(opt.w || 1280), H = +(opt.h || 720);
const gpu = opt.gpu || 'dgpu';
const ablate = (opt.ablate || '').split(',').filter(Boolean);
const outf = opt.out || null;
const port = +(process.env.PORT || 12100);
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png' };
const server = http.createServer((q, r) => {
  let p = path.join(root, decodeURIComponent(q.url.split('?')[0]));
  if (p.endsWith('/')) p += 'index.html';
  fs.readFile(p, (e, d) => {
    if (e) { r.writeHead(404); r.end(); return; }
    r.writeHead(200, { 'Content-Type': MIME[path.extname(p)] || 'application/octet-stream' });
    r.end(d);
  });
});
await new Promise(res => server.listen(port, '127.0.0.1', res));

const env = { ...process.env };
let launch;
if (gpu === 'swift') launch = ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'];
else {
  launch = ['--use-angle=vulkan', '--enable-features=Vulkan', '--enable-unsafe-webgpu'];
  if (gpu === 'igpu') env.MESA_VK_DEVICE_SELECT = '1002:13c0!';
}
const browser = await chromium.launch({ executablePath: '/usr/bin/chromium', headless: true, env,
  args: [...launch, '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required', '--no-sandbox'] });
const page = await browser.newPage({ viewport: { width: W, height: H } });
// Main-thread cost per frame: time inside each requestAnimationFrame callback (Godot's whole
// Main.iteration: physics, scripts, scene update and the GL command submission). Immune to vsync
// quantisation. Our own sampling loop uses window.__raf0 and is not counted.
await page.addInitScript(() => {
  const raf0 = window.requestAnimationFrame.bind(window);
  window.__raf0 = raf0; window.__busy = [];
  window.requestAnimationFrame = cb => raf0(t => { const s = performance.now(); cb(t); window.__busy.push(performance.now() - s); });
});
const errors = [];
page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
page.on('pageerror', e => errors.push('pageerror: ' + e.message));
const sleep = ms => new Promise(r => setTimeout(r, ms));
const q = opt.url ? '?' + opt.url.replace(/_/g, '&') : (room === 'room1' ? '' : '?start=' + room);
await page.goto(`http://127.0.0.1:${port}/index.html${q}`);
const renderer = await page.evaluate(() => {
  const c = document.createElement('canvas').getContext('webgl2');
  const d = c && c.getExtension('WEBGL_debug_renderer_info');
  return d ? c.getParameter(d.UNMASKED_RENDERER_WEBGL) : 'unknown';
});
console.error('[gpu]', renderer);
await page.evaluate(() => { window.__pub = 1; });
let ok = false;
for (let i = 0; i < 1200 && !ok; i++) { ok = await page.evaluate(() => !!(window.wakeAblate && ((window.__wake && window.__wake.f > 0) || (window.__map && window.__map.scene)))); await sleep(50); }
if (!ok) { console.log('FAIL never started'); process.exit(1); }
await page.evaluate(() => { window.__pub = 0; });
await page.mouse.click(W / 2, H / 2);
const cdp = await page.context().newCDPSession(page);
await cdp.send('Emulation.setCPUThrottlingRate', { rate: thr });
// Room 1 starts asleep with input locked; teleport still works. Let the intro finish a bit.
await sleep(opt.cold ? 0 : 1500);

if (opt.strike) await page.evaluate(() => { if (window.wakeStrike) setInterval(() => window.wakeStrike(1), 2500); });
async function measure(label, xs, y) {
  await page.evaluate(() => { window.__fr = []; window.__ts = []; let last = performance.now(); window.__run = true; window.__t0 = last;
    (function f(t) { window.__fr.push(t - last); window.__ts.push(t - window.__t0); last = t; if (window.__run) window.__raf0(f); })(last); window.__busy = []; });
  if (xs) { for (const x of xs) { await page.evaluate(([x, y]) => window.wakeTeleport(x, y), [x, y]); await sleep(secs * 1000 / xs.length); } }
  else await sleep(secs * 1000);
  const r = await page.evaluate(() => { window.__run = false; return { busy: window.__busy.slice(), fr: window.__fr.slice(1), ts: window.__ts.slice(1), perf: JSON.parse(window.__perf || '{}') }; });
  const longs = []; r.fr.forEach((v, i) => { if (v > 33.5 && longs.length < 40) longs.push([+(r.ts[i] / 1000).toFixed(1), +v.toFixed(0)]); });
  const t = r.fr.slice().sort((a, b) => a - b);
  const q = p => t[Math.min(t.length - 1, Math.floor(t.length * p))];
  const b = r.busy.slice().sort((x, y) => x - y);
  const bq = p => b.length ? b[Math.min(b.length - 1, Math.floor(b.length * p))] : 0;
  const sum = r.fr.reduce((a, b) => a + b, 0);
  const res = { label, room, gpu, throttle: thr, w: W, h: H, n: t.length, fps: +(t.length * 1000 / sum).toFixed(1), avg: +(sum / t.length).toFixed(2),
    p50: +q(0.5).toFixed(1), p95: +q(0.95).toFixed(1), p99: +q(0.99).toFixed(1), max: +t[t.length - 1].toFixed(1),
    o33: t.filter(x => x > 33.5).length, o50: t.filter(x => x > 50).length, o100: t.filter(x => x > 100).length,
    busy: { avg: +(b.reduce((x, y) => x + y, 0) / Math.max(b.length, 1)).toFixed(2), p50: +bq(0.5).toFixed(2), p95: +bq(0.95).toFixed(2), max: +bq(1).toFixed(1) }, longs, godot: r.perf };
  console.log(JSON.stringify(res));
  if (outf) fs.appendFileSync(outf, JSON.stringify(res) + '\n');
}
for (const s of spots) {
  if (!s.xs && !opt.cold && (s.x || s.y)) { await page.evaluate(([x, y]) => window.wakeTeleport(x, y), [s.x, s.y]); await sleep(4000); }
  if (s.xs) { await page.evaluate(([x, y]) => window.wakeTeleport(x, y), [s.xs[0], s.y]); await sleep(3000); }
  await measure(s.n, s.xs, s.y);
  for (const a of ablate) {
    await page.evaluate(a => window.wakeAblate(a, false), a); await sleep(1500);
    await measure(`${s.n}|-${a}`);
    await page.evaluate(a => window.wakeAblate(a, true), a); await sleep(500);
  }
}
if (errors.length) console.error('console errors:', errors.slice(0, 5));
await browser.close(); server.close();
