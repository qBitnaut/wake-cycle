// Stress test for the web-only engine FATAL "Index p_index = 3 is out of bounds (size() = 1)"
// (cowdata.h): a BackBufferCopy under a z-indexed node, off screen, in the web export's
// Compatibility renderer (ShockwaveFX used one). Hammers the pattern in Room 4: one-shot
// effects (shockwave, bell sparkle, explosion), then a far camera teleport within a frame or two,
// and a death -> checkpoint respawn (scene reload) with effects alive. Passes with 0 console
// errors, 0 pageerrors and a game that keeps publishing frames.
//
//   node tools/audit/web_particles_stress.mjs <export_dir> [minutes=4] [--room1] [--gpu=swiftshader]
// <export_dir> must be a DEBUG export (tools/export_web.sh debug <dir>): the hooks and deep links
// this audit uses do not exist in a release export.
//
// --room1 runs the Room 1 variant instead: the static GooPool (BackBufferCopy era, z_index 6) with
// far camera jumps across it, plus spawned pools (wakeFx 'pool') jumped away from and freed.
//
// Needs the playwright package (PW_DIR env) and /usr/bin/chromium. Serves the export on PORT
// (default 10710).
import { createRequire } from 'node:module';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const PW = process.env.PW_DIR
  || path.join(os.homedir(), '.local/share/mise/installs/npm-playwright/latest/node_modules/playwright');
const { chromium } = createRequire(import.meta.url)(PW);
const args = process.argv.slice(2).filter(a => !a.startsWith('--'));
const flags = process.argv.slice(2).filter(a => a.startsWith('--'));
const [root, minutes = '4'] = args;
const gpu = (flags.find(f => f.startsWith('--gpu=')) || '--gpu=vulkan').split('=')[1];
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
const port = process.env.PORT ? +process.env.PORT : 10710;
await new Promise(res => server.listen(port, '127.0.0.1', res));

const launchArgs = gpu === 'swiftshader'
  ? ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader']
  : ['--use-angle=vulkan', '--enable-features=Vulkan', '--enable-unsafe-webgpu'];
const browser = await chromium.launch({
  executablePath: '/usr/bin/chromium', headless: true,
  args: [...launchArgs, '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required', '--no-sandbox'],
});
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
const errors = [];
page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
page.on('pageerror', e => errors.push('pageerror: ' + e.message));
const sleep = ms => new Promise(r => setTimeout(r, ms));
const room1 = flags.includes('--room1');
await page.goto(`http://127.0.0.1:${port}/index.html${room1 ? '' : '?start=room4'}`);
let W = null;
const poll = async () => (W = await page.evaluate(() => window.__wake || null));
async function ready() {
  for (let i = 0; i < 1200; i++) {
    await poll();
    if (W && W.scene.endsWith(room1 ? 'room1.tscn' : 'room4.tscn') && W.f > 0 && !W.dead) return true;
    await sleep(50);
  }
  return false;
}
if (!await ready()) { console.log('FAIL game never started'); process.exit(1); }
await sleep(1500);

if (room1) {
  const tp = (x, y) => page.evaluate(([x, y]) => window.wakeTeleport(x, y), [x, y]);
  const t1 = Date.now() + +minutes * 60000;
  let m = 0;
  while (Date.now() < t1 && !errors.length) {
    m++;
    await tp(200, 300); await sleep(150); await tp(4300, 300); await sleep(150); await tp(200, 300); await sleep(60); await tp(4500, 300); await sleep(100);
    await page.evaluate(() => { window.wakeFx('pool', 3000, 0); window.wakeFx('pool', -1500, 0); window.wakeFx('pool', 0, 0); });
    await sleep([0, 16, 100, 400][m % 4]); await tp(m % 2 ? 200 : 3000, 300); await sleep(200); await tp(m % 2 ? 3000 : 200, 300); await sleep(150);
    await page.evaluate(() => window.wakeFx('poolfree')); await sleep(100); await tp(1000, 300); await sleep(100);
    await poll();
  }
  console.log(`${errors.length ? 'FAIL' : 'PASS'}  room1 pool stress, ${m} iterations, ${errors.length} console errors`, errors.slice(0, 3));
  await browser.close(); server.close(); process.exit(errors.length ? 1 : 0);
}
const kinds = ['shock', 'bell', 'explode'];
const spots = [112, 3000, 700, 5200, 1600, 3600].map(x => [x, 384]);
const t0 = Date.now();
const until = t0 + +minutes * 60000;
let n = 0, tele = 0, deaths = 0, bad = null;
while (Date.now() < until && !bad) {
  n++;
  // 1-3 effects, then a far teleport after 0-2 frames (physics 60 Hz) .. a few hundred ms
  const k = 1 + (n % 3);
  await page.evaluate(([ks, k]) => { for (let i = 0; i < k; i++) window.wakeFx(ks[(i + 1) % 3]); window.wakeFx(ks[0]); }, [kinds, k]);
  await sleep([0, 16, 33, 120, 400, 700][n % 6]);
  const [x, y] = spots[n % spots.length];
  await page.evaluate(([x, y]) => window.wakeTeleport(x, y), [x, y]);
  tele++;
  await sleep(250);
  if (n % 12 === 0) {            // death -> respawn (scene reload) with effects alive
    await page.evaluate(() => { window.wakeFx('shock'); window.wakeFx('explode'); window.wakeFx('die'); });
    deaths++;
    await sleep(1500);
    if (!await ready()) { bad = 'game did not come back after respawn'; break; }
  }
  const f0 = W && W.f; await sleep(100); await poll();
  if (!W || W.f === f0) { bad = 'frames stopped publishing'; break; }
  if (errors.length) bad = errors[0];
  if (n % 20 === 0) console.log(`[${((Date.now() - t0) / 1000).toFixed(0)}s] iterations ${n}, teleports ${tele}, respawns ${deaths}, errors ${errors.length}`);
}
const secs = ((Date.now() - t0) / 1000).toFixed(0);
console.log(`${bad ? 'FAIL' : 'PASS'}  ${secs}s, ${n} iterations, ${tele} teleports, ${deaths} respawns, ${errors.length} console errors`);
if (bad) console.log('first problem:', bad, errors.slice(0, 5));
await browser.close(); server.close();
process.exit(bad ? 1 : 0);
