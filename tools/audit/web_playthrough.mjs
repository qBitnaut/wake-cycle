// Plays the web export beat by beat with real keyboard events (Playwright +
// system Chromium), reading the state the test room publishes in window.__wake
// every physics frame. Also records console errors, screenshots and fps.
//
//   node tools/audit/web_playthrough.mjs <export_dir> <out_dir> [width height] [--gpu=swiftshader]
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
const [root, outdir, W_ = '1920', H_ = '1080'] = args;
fs.mkdirSync(outdir, { recursive: true });
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
await new Promise(res => server.listen(0, res));
const url = `http://127.0.0.1:${server.address().port}/index.html?start=test`;  // Room 1's deep link to the test room (the main scene is Room 1)

const launchArgs = gpu === 'swiftshader'
  ? ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader']
  : ['--use-angle=vulkan', '--enable-features=Vulkan', '--enable-unsafe-webgpu'];
const browser = await chromium.launch({
  executablePath: '/usr/bin/chromium',
  headless: true,
  args: [...launchArgs, '--ignore-gpu-blocklist', '--disable-gpu-vsync', '--disable-frame-rate-limit',
    '--autoplay-policy=no-user-gesture-required', '--no-sandbox'],
});
const page = await browser.newPage({ viewport: { width: +W_, height: +H_ }, deviceScaleFactor: 1 });
const consoleErrors = [];
page.on('console', m => { if (m.type() === 'error') consoleErrors.push(m.text()); });
page.on('pageerror', e => consoleErrors.push('pageerror: ' + e.message));
await page.goto(url);
const renderer = await page.evaluate(() => {
  const c = document.createElement('canvas').getContext('webgl2');
  const d = c && c.getExtension('WEBGL_debug_renderer_info');
  return d ? c.getParameter(d.UNMASKED_RENDERER_WEBGL) : 'unknown';
});
console.log('[gpu]', renderer);

const sleep = ms => new Promise(r => setTimeout(r, ms));
let W = null;
async function poll() { W = await page.evaluate(() => window.__wake || null); return W; }
for (let i = 0; i < 600 && !(await poll()); i++) await sleep(100);
if (!W) { console.log('FAIL game never published state'); process.exit(1); }
await page.mouse.click(+W_ / 2, +H_ / 2);  // focus the canvas
await sleep(1500);  // let the title/fades settle

// ---- input helpers ----------------------------------------------------------
const CODE = { right: 'KeyD', left: 'KeyA', jump: 'Space', down: 'KeyS', dash: 'ShiftLeft' };
const held = new Set();
async function hold(a, on = true) {
  if (on && !held.has(a)) { held.add(a); await page.keyboard.down(CODE[a]); }
  else if (!on && held.has(a)) { held.delete(a); await page.keyboard.up(CODE[a]); }
}
async function dir(d) { await hold('right', d > 0); await hold('left', d < 0); }
async function stop() { for (const a of [...held]) await hold(a, false); }
async function frame() {
  const f0 = W.f;
  for (let i = 0; i < 4000; i++) { await poll(); if (W.f > f0) return W; await sleep(1); }
  throw new Error('physics stalled');
}
async function ticks(n) { for (let i = 0; i < n; i++) await frame(); }
const T = 32, FLOOR = 320;
async function goTo(x, tol = 6, limit = 900) {
  let n = 0;
  while (Math.abs(W.x - x) > tol && n++ < limit) { await dir(Math.sign(x - W.x)); await frame(); }
  await dir(0); await ticks(6); return n < limit;
}
async function runPast(x, d, limit = 900) {
  let n = 0;
  while ((W.x - x) * d < 0 && n++ < limit) { await dir(d); await frame(); }
  return n < limit;
}
async function leap(d, dj = 28, max = 300) {
  await hold('jump', true); await dir(d);
  for (let t = 1; t < max; t++) {
    await frame();
    if (dj && t === dj) { await hold('jump', false); await frame(); await hold('jump', true); }
    if (t > 8 && W.floor) break;
  }
  await stop(); await ticks(4);
}

const results = [];
function note(name, ok, detail = '') {
  results.push([name, ok, detail]);
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name.padEnd(46)} ${detail}`);
}
let shotN = 0;
async function shot(name) { await page.screenshot({ path: `${outdir}/${String(++shotN).padStart(2, '0')}_${name}.png` }); }

// ---- beats (the same script as tools/audit/playthrough.gd, on real input) ---
// A
note('A start on floor', Math.abs(W.x - 304) < 4 && W.floor, `x=${W.x.toFixed(0)}`);
await shot('A_start');
await goTo(12 * T + 16); await ticks(10);
note('A checkpoint A saves', W.cp === 'cp_a', W.cp);
let s0 = W.score;
await goTo(14 * T + 16); await hold('jump', true); await ticks(20); await stop();
await goTo(15 * T + 16); await leap(0, 0);
note('A gems collected', W.score > s0, `score ${W.score}`);
// B
await goTo(17 * T - 160); await runPast(17 * T + 8, 1); await leap(1, 28);
const landedA = W.floor && W.x > 23 * T && Math.abs(W.y - FLOOR) < 2;
note('B pit A crossed (6 tiles, double jump)', landedA, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
await goTo(25 * T + 16); await ticks(6);
note('B shockwave unlocked', W.shock);
await shot('B_shockwave_pad');
await goTo(26 * T + 16); await leap(0, 28); await ticks(10);
note('B letter C on the deck', W.letters >= 1, `letters ${W.letters}`);
await shot('B_deck');
await goTo(29 * T + 16); await goTo(31 * T + 8);
await hold('jump', true); await ticks(10); await hold('jump', false); await ticks(2);
await hold('jump', true); await ticks(5); await shot('B_shockwave'); await ticks(9); await stop(); await ticks(30);
note('B crate stack broken by shockwave', W.crates === 2, `${W.crates - 2} crates left (+2 cracked floors)`);
await goTo(36 * T);
note('B corridor passable, drops collected', W.score > s0, `score ${W.score}`);
// C
await goTo(38 * T + 16); await ticks(4);
note('C surge pad', W.power === 1, `power ${W.power}`);
await runPast(41 * T + 8, 1); await leap(1, 28);
note('C pit C crossed (8 tiles, surge + double)', W.floor && W.x > 49 * T && Math.abs(W.y - FLOOR) < 2, `x=${W.x.toFixed(0)}`);
// D
await goTo(52 * T + 16); await ticks(4);
note('D spring pad', W.power === 2, `power ${W.power}`);
await goTo(54 * T - 6);
await hold('jump', true); await dir(1);
for (let t = 1; t < 200; t++) {
  await frame();
  if (t === 22) { await hold('jump', false); await frame(); await hold('jump', true); }
  if (t > 10 && W.floor) break;
}
await stop(); await ticks(6);
note('D tall wall climbed (spring + double)', W.floor && Math.abs(W.y - 128) < 3 && W.x >= 55 * T && W.x <= 59 * T, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
await shot('D_wall_top');
s0 = W.score; await goTo(57 * T + 16); await leap(0, 0);
note('D top gem', W.score > s0);
await goTo(62 * T);
// E
await dir(1); await ticks(90); await stop();
note('E tunnel blocks the standing cat', W.x < 64 * T + 4, `x=${W.x.toFixed(0)}`);
await hold('down', true); await dir(1);
for (let n = 0; W.x < 70 * T && n < 900; n++) { await frame(); if (n === 150) await shot('E_crawl'); }
await stop(); await ticks(10);
note('E crawl through the tunnel, letter A', W.x >= 70 * T - 8 && W.letters >= 2, `x=${W.x.toFixed(0)} letters ${W.letters}`);
await goTo(71 * T + 16);
note('E checkpoint B', W.cp === 'cp_b', W.cp);
// F
await goTo(75 * T); await dir(1);
for (let n = 0; !W.plate && n < 900; n++) await frame();
await ticks(5);
note('F crate pushed onto the plate', W.plate && !W.fenceA, `crate x=${W.crate[0].toFixed(0)}`);
await dir(1); await ticks(90); await stop(); await ticks(20);
note('F crate cannot be overshot past the plate', Math.abs(W.crate[0] - 80 * T - 16) < 8 && W.plate, `x=${W.crate[0].toFixed(0)}`);
await shot('F_plate');
await leap(1, 0); let hp0 = W.hp;
await goTo(86 * T);
note('F through the fence', W.x > 85 * T && W.hp === hp0, `x=${W.x.toFixed(0)} hp ${W.hp}`);
// G
await goTo(87 * T + 8); hp0 = W.hp;
for (let n = 0; !W.fenceT && n < 600; n++) await frame();  // wait for the beam to fire,
for (let n = 0; W.fenceT && n < 600; n++) await frame();   // then cross at the start of its off window
await ticks(3); await runPast(93 * T, 1); await stop();
note('G timed fence crossed in its off window', W.x > 92 * T && W.hp === hp0, `x=${W.x.toFixed(0)} hp ${W.hp}`);
await goTo(93 * T + 8);
await hold('jump', true); await dir(1);
for (let t = 1; t < 120; t++) {
  await frame();
  if (t === 20) { await hold('jump', false); await frame(); await hold('jump', true); }
  if (t > 8 && W.floor) break;
}
await stop();
note('G shock switch thrown', W.switch, `x=${W.x.toFixed(0)}`);
hp0 = W.hp; await runPast(101 * T, 1); await stop();
note('G switched fence B crossed', W.x > 100 * T && W.hp === hp0 && !W.fenceB, `x=${W.x.toFixed(0)} hp ${W.hp}`);
// H
await goTo(103 * T + 16); await ticks(4);
note('H phase pad', W.power === 3, `power ${W.power}`);
await goTo(108 * T + 16 - 34); hp0 = W.hp;
for (let n = 0; !W.fenceD && n < 600; n++) await frame();
await ticks(2); await dir(1); await hold('dash', true); await ticks(2); await hold('dash', false); await shot('H_dash'); await ticks(16); await stop();
note('H dashed through the live beam', W.x > 109 * T && W.hp === hp0, `x=${W.x.toFixed(0)} hp ${W.hp}`);
await goTo(113 * T + 16); await leap(0, 28); await ticks(10);
note('H key taken from the deck', W.keys.includes('brass'), JSON.stringify(W.keys));
await goTo(118 * T); await dir(1); await ticks(60); await stop();
note('H door opened with the key', !W.door || W.x > 121 * T, `x=${W.x.toFixed(0)}`);
await goTo(122 * T);
// I
for (let n = 0; W.x < 133 * T && n < 1800 && !W.dead; n++) {
  const near = Math.abs(W.bot[0] - W.x) < 90 && W.bot[3] === 0;
  if (near && W.floor) {
    await hold('jump', true); await dir(1); await ticks(8); await hold('jump', false); await frame(); await hold('jump', true); await ticks(6);
  } else { await dir(1); await hold('jump', false); }
  await frame();
  if (n === 40) await shot('I_bot');
}
await stop(); await ticks(20);
note('I past the patrol bot', W.x >= 133 * T && !W.dead, `x=${W.x.toFixed(0)} hp ${W.hp}`);
await ticks(60);
note('I bot stays inside its stoppers', W.bot[0] < 133 * T + 4 && W.bot[0] > 123 * T, `bot x=${W.bot[0].toFixed(0)}`);
await goTo(133 * T - 12); await runPast(133 * T + 4, 1); await leap(1, 0);
note('I spikes cleared', !W.dead && W.x > 136 * T, `x=${W.x.toFixed(0)}`);
await goTo(139 * T + 16); await ticks(4);
note('I impact pad', W.power === 4, `power ${W.power}`);
await goTo(140 * T);
await hold('jump', true); await dir(1);
let pounded = false;
for (let t = 1; t < 200; t++) {
  await frame();
  if (t === 14) { await hold('jump', false); await frame(); await hold('jump', true); }
  if (!pounded && W.x >= 142 * T + 16 && !W.floor && t > 20) { await dir(0); await hold('jump', false); await hold('down', true); pounded = true; }
  if (pounded && t === 40) await shot('I_pound');
  if (pounded && W.floor && W.y > 330) break;
  if (t > 150 && W.floor) break;
}
await stop(); await ticks(30);
note('I cracked floor broken by the ground pound', W.y > 330, `y=${W.y.toFixed(0)}`);
note('I letter T in the chamber', W.letters >= 3, `letters ${W.letters}`);
await hold('jump', true); await dir(1); await ticks(40); await stop();
await goTo(147 * T + 16); await ticks(10);
note('I out of the chamber, checkpoint C', W.cp === 'cp_c' && W.letters === 3, `cp ${W.cp} letters ${W.letters}`);
await shot('I_checkpoint_C');

// ---- a tour for screenshots: one frame per beat, taken where the cat is placed ----
for (const [name, x] of [['tour_pit_A', 520], ['tour_corridor', 1000], ['tour_pit_C', 1290], ['tour_tunnel', 2080],
    ['tour_fence_timed', 2830], ['tour_key_deck', 3560], ['tour_door', 3790], ['tour_spikes', 4220], ['tour_chamber_pad', 4500]]) {
  await page.evaluate(([px]) => window.wakeTeleport(px, 290), [x]);
  await sleep(900);
  await shot(name);
}

// ---- fps at the page size ---------------------------------------------------
await stop();
await page.evaluate(() => window.wakeTeleport(9 * 32 + 16, 300));  // the moon shaft: the heaviest-lit spot
await sleep(1500);
const fps = await page.evaluate(ms => new Promise(res => {
  let n = 0; const t0 = performance.now(); let last = t0; const times = [];
  function f(t) { n++; times.push(t - last); last = t; if (t - t0 < ms) requestAnimationFrame(f); else {
    times.sort((a, b) => a - b);
    res({ fps: +(n * 1000 / (t - t0)).toFixed(1), p50: +times[Math.floor(times.length * 0.5)].toFixed(2), p95: +times[Math.floor(times.length * 0.95)].toFixed(2), max: +times[times.length - 1].toFixed(2) }); } }
  requestAnimationFrame(f);
}), 6000);
console.log('[fps]', `${W_}x${H_}`, JSON.stringify(fps));
await shot('moonshaft_start');

const failed = results.filter(r => !r[1]);
console.log(`== ${results.length} beats, ${failed.length ? failed.length + ' FAILED' : 'ALL PASS'}; console errors: ${consoleErrors.length}`);
consoleErrors.slice(0, 20).forEach(e => console.log('  [console error]', e.slice(0, 300)));
await browser.close();
server.close();
process.exit(failed.length || consoleErrors.length ? 1 : 0);
