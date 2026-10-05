// Drives the world map on the web export with real keyboard events
// (Playwright + system Chromium) at the default capped frame rate, through the
// debug deep link index.html?start=map&completed=<level> (WorldMap.web_deep_link):
// the arrival after the warehouse (night, rain), after the stacks (pre-dawn)
// and after the perimeter (morning), the reveal's pan, the name plate, the
// locked bonus nodes, walking with the keys, and going in (the view eases in
// on the door, fades, and the right level loads). Reads window.__map (and
// window.__wake once a room is up), takes a screenshot at each moment and
// records console errors (there must be none).
//
//   node tools/audit/web_map.mjs <export_dir> <out_dir> [width height] [--gpu=swiftshader] [--dpr=1.25] [--port=8961]
//
// Needs the playwright package (PW_DIR env, default: the mise npm-playwright
// install) and /usr/bin/chromium. By default it asks Chromium for the real GPU
// through ANGLE/Vulkan; pass --gpu=swiftshader for the software rasteriser.
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
const flag = (k, d) => (flags.find(f => f.startsWith(`--${k}=`)) || `--${k}=${d}`).split('=')[1];
const [root, outdir, W_ = '1280', H_ = '720'] = args;
fs.mkdirSync(outdir, { recursive: true });
const gpu = flag('gpu', 'vulkan');

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
// Our own port range (8900-8999); the next free one if taken.
let port = +flag('port', '8961');
for (;;) {
  const ok = await new Promise(res => {
    server.once('error', () => res(false));
    server.listen(port, '127.0.0.1', () => res(true));
  });
  if (ok) break;
  port++;
}
const base = `http://127.0.0.1:${port}/index.html`;
console.log('[url]', base);

const launchArgs = gpu === 'swiftshader'
  ? ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader']
  : ['--use-angle=vulkan', '--enable-features=Vulkan'];
const browser = await chromium.launch({
  executablePath: '/usr/bin/chromium',
  headless: true,
  args: [...launchArgs, '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required', '--no-sandbox'],
});
const page = await browser.newPage({ viewport: { width: +W_, height: +H_ }, deviceScaleFactor: +flag('dpr', '1') });
const consoleErrors = [];
page.on('console', m => { if (m.type() === 'error') consoleErrors.push(m.text()); });
page.on('pageerror', e => consoleErrors.push('pageerror: ' + e.message));

const sleep = ms => new Promise(r => setTimeout(r, ms));
let shotN = 0;
async function shot(name) { await page.screenshot({ path: `${outdir}/${String(++shotN).padStart(2, '0')}_${name}.png` }); }
const results = [];
function note(name, ok, detail = '') {
  results.push([name, ok, detail]);
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name.padEnd(60)} ${detail}`);
}

let M = null;
async function poll() { M = await page.evaluate(() => window.__map || null); return M; }
async function until(cond, ms = 60000, step = 40) {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) { await poll(); if (M && cond(M)) return true; await sleep(step); }
  return false;
}
const CODE = { right: 'KeyD', left: 'KeyA', up: 'KeyW', down: 'KeyS', jump: 'Space' };
async function tap(a, ms = 90) { await page.keyboard.down(CODE[a]); await sleep(ms); await page.keyboard.up(CODE[a]); }

async function openMap(done) {
  await page.goto(`${base}?start=map&completed=${done}`);
  const ok = await until(m => m.scene === 'map', 90000);
  if (!ok) { console.log('FAIL the map never came up for', done); process.exit(1); }
  await page.mouse.click(+W_ / 2, +H_ / 2);  // focus the canvas (a click moves nothing: no mouse input)
}

let renderer = '?';
const fpsSeen = [];

// ---- after the warehouse: night, rain ---------------------------------------
await openMap('warehouse');
renderer = await page.evaluate(() => {
  const c = document.createElement('canvas').getContext('webgl2');
  const d = c && c.getExtension('WEBGL_debug_renderer_info');
  return d ? c.getParameter(d.UNMASKED_RENDERER_WEBGL) : 'unknown';
});
console.log('[gpu]', renderer);
note('A the map opens from the deep link, mid reveal', M.auto === true, `node ${M.node}`);
await sleep(900);
await shot('night_warehouse_stamp');
// The pan: wait until the camera is between the two nodes.
await until(m => m.cam > 380 && m.cam < 520, 8000, 20);
await shot('night_reveal_parallax_pan');
note('A the reveal pans the camera', M.cam > 380, `cam ${M.cam.toFixed(0)}`);
await until(m => !m.auto, 15000);
await sleep(600);
await poll();
fpsSeen.push(M.fps);
await shot('night_yard_label');
note('A the cat walked to the yard, which is now open', M.node === 'yard' && M.open.includes('yard'), `node ${M.node} open ${M.open}`);
note('A the name plate shows on the node', M.label === 'yard' && M.labelA > 0.9, `${M.label} ${M.labelA}`);
note('A night at this end (p < 0.35)', M.p < 0.35, `p ${M.p.toFixed(2)}`);
note('A progress saved', M.save && M.completed.includes('warehouse') && M.mapNode === 'yard');
// Walking with the keys.
await page.keyboard.down(CODE.left);
await until(m => m.node === '' , 3000, 20);
await sleep(700);
await shot('night_walking_left');
await until(m => m.node === 'warehouse', 8000, 20);
await page.keyboard.up(CODE.left);
note('B Left walks the cat back to the warehouse', M.node === 'warehouse', M.node);
await sleep(300);
await page.keyboard.down(CODE.right);
await until(m => m.node === 'yard', 8000, 20);
await page.keyboard.up(CODE.right);
note('B Right walks it to the yard again', M.node === 'yard', M.node);
await tap('right');
await sleep(1500);
await poll();
note('B Right at the yard goes nowhere (the stacks are locked)', M.node === 'yard', M.node);

// ---- after the yard: the stacks, the locked water tower ----------------------
await openMap('yard');
await until(m => !m.auto, 20000);
await sleep(700);
await poll();
fpsSeen.push(M.fps);
await shot('rain_easing_stacks_locked_water_tower');
note('C after the yard the cat is on the stacks', M.node === 'stacks', M.node);
note('C the water tower (bonus placeholder) stays locked', !M.open.includes('water_tower'));

// ---- after the stacks: pre-dawn at the fence ---------------------------------
await openMap('stacks');
await until(m => m.auto && m.cam > 1150 && m.cam < 1300, 12000, 20);
await shot('dawn_reveal_parallax_pan');
await until(m => !m.auto, 20000);
await sleep(700);
await poll();
fpsSeen.push(M.fps);
await shot('predawn_perimeter_label');
note('D pre-dawn at the perimeter (0.6 < p < 0.85)', M.p > 0.6 && M.p < 0.85 && M.node === 'perimeter', `p ${M.p.toFixed(2)} node ${M.node}`);
// The signal box (bonus) sits locked to the right: walk to the fork to see it.
await shot('locked_bonus_signal_box');
await tap('right');
await sleep(1200);
await poll();
note('D Right at the perimeter goes nowhere yet (home is locked)', M.node === 'perimeter', M.node);

// ---- after the perimeter: morning, home ----------------------------------------
await openMap('perimeter');
await until(m => !m.auto, 20000);
await sleep(800);
await poll();
fpsSeen.push(M.fps);
await shot('day_home_label');
note('E morning at home (p > 0.9)', M.p > 0.9 && M.node === 'home', `p ${M.p.toFixed(2)} node ${M.node}`);

// ---- going in: the yard (a real scene on every branch) --------------------------
await openMap('warehouse');
await until(m => !m.auto, 20000);
await sleep(500);
await tap('up');
await sleep(300);
await shot('enter_zoom_in');
await poll();
note('F Up on the yard goes in', M.leaving && M.chosen === 'yard', `chosen ${M.chosen}`);
await until(m => false, 380);
await shot('enter_fade');
const inRoom = await (async () => {
  const t0 = Date.now();
  while (Date.now() - t0 < 30000) {
    const w = await page.evaluate(() => window.__wake || null);
    if (w && w.scene && w.scene.endsWith('room2.tscn')) return w;
    await sleep(60);
  }
  return null;
})();
await sleep(900);
await shot('entered_room2');
note('F the yard loads room2.tscn', !!inRoom, inRoom ? inRoom.scene : 'no room');

note('Z no console errors', consoleErrors.length === 0, consoleErrors.slice(0, 5).join(' | '));
console.log('MEASURE fps on the map (capped):', fpsSeen.join(', '));
console.log('MEASURE renderer:', renderer);
const fails = results.filter(r => !r[1]);
console.log(`\n${results.length} checks, ${fails.length} failed`);
await browser.close();
server.close();
process.exit(fails.length ? 1 : 0);
