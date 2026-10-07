// Plays the Home ending on the web export with real keyboard events
// (Playwright + system Chromium), at the default capped frame rate: the
// sunny street, the flap, the sunbeam, the cat curling up, every final line,
// the warm fade, the title card, the credits and the return to Room 1.
// Starts through the debug deep link index.html?start=home (Room1
// _web_start_override: the mind awake and every ability). Reads the state the
// scenes publish in window.__wake, takes a screenshot at every moment and
// records console errors (there must be none).
//
//   node tools/audit/web_home.mjs <export_dir> <out_dir> [width height] [--gpu=swiftshader] [--dpr=1.25] [--port=8937]
// <export_dir> must be a DEBUG export (tools/export_web.sh debug <dir>): the hooks and deep links
// this audit uses do not exist in a release export.
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
// A fixed port by default (other runs on this machine use their own); the next free one if taken.
let port = +flag('port', '8937');
for (;;) {
  const ok = await new Promise(res => {
    server.once('error', () => res(false));
    server.listen(port, '127.0.0.1', () => res(true));
  });
  if (ok) break;
  port++;
}
const url = `http://127.0.0.1:${port}/index.html?start=home`;
console.log('[url]', url);

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
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name.padEnd(56)} ${detail}`);
}

await page.goto(url);
const renderer = await page.evaluate(() => {
  const c = document.createElement('canvas').getContext('webgl2');
  const d = c && c.getExtension('WEBGL_debug_renderer_info');
  return d ? c.getParameter(d.UNMASKED_RENDERER_WEBGL) : 'unknown';
});
console.log('[gpu]', renderer);

let W = null;
async function poll() { W = await page.evaluate(() => window.__wake || null); return W; }
async function until(cond, ms = 60000, step = 50) {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) { await poll(); if (W && cond(W)) return true; await sleep(step); }
  return false;
}
await until(w => w.scene && w.scene.endsWith('home.tscn') && w.f > 0, 90000);
if (!W || !W.scene.endsWith('home.tscn')) { console.log('FAIL Home never came up', W && W.scene); process.exit(1); }
await page.mouse.click(+W_ / 2, +H_ / 2);  // focus the canvas (a click moves nothing: no mouse input)

const CODE = { right: 'KeyD', left: 'KeyA', jump: 'Space', down: 'KeyS' };
const held = new Set();
async function hold(a, on = true) {
  if (on && !held.has(a)) { held.add(a); await page.keyboard.down(CODE[a]); }
  else if (!on && held.has(a)) { held.delete(a); await page.keyboard.up(CODE[a]); }
}
async function walkTo(x, ms = 60000) {
  await hold('right');
  const ok = await until(w => w.x >= x || !w.can_move, ms, 20);
  await hold('right', false);
  return ok;
}

// ---- the street -------------------------------------------------------------
note('A Home arrives through ?start=home', W.scene.endsWith('home.tscn'));
note('A the mind and every ability on a direct start', W.mind && W.shock, `mind ${W.mind} shock ${W.shock}`);
note('A the augments show', W.aug);
await sleep(3000);
await shot('sunny_street_arrival');
await walkTo(150);
await until(w => w.monoIds.includes('home_arrival'), 8000);
await sleep(600);
await shot('home_arrival_line1');
await walkTo(332);
await sleep(250);
await shot('puddle_reflection');
await until(w => w.monoIds.filter(i => i === 'home_arrival').length >= 2, 12000);
await sleep(500);
await shot('home_arrival_line2');
note('B home_arrival plays', W.monoIds.filter(i => i === 'home_arrival').length === 2);
await walkTo(1440);
await hold('right');
await until(w => w.birdsFlown >= 3 || w.x > 1640, 8000, 20);
await sleep(150);
await shot('sparrows_take_off');
await hold('right', false);
note('B sparrows take off', W.birdsFlown >= 3, `flown ${W.birdsFlown}`);
await walkTo(1600);
await sleep(400);
await shot('big_puddle_glints');
const fpsStreet = W.fps;
note('B glints and drips', W.glints > 10 && W.drops > 1, `glints ${W.glints} drops ${W.drops}`);
await walkTo(2780);
await sleep(300);
await shot('home_tree_sun_rays');
await walkTo(3110);
await until(w => w.monoIds.includes('home_flap'), 6000);
await walkTo(3236);
await sleep(300);
await shot('porch_cat_flap_home_flap_line');
note('C home_flap plays at the steps', W.monoIds.includes('home_flap'));

// ---- the flap ---------------------------------------------------------------
await hold('right');
await until(w => w.beat === 1, 8000, 10);
await sleep(250);
await shot('through_the_flap');
await hold('right', false);
await until(w => w.facade < 0.6, 4000, 10);
await shot('facade_dissolving');
await until(w => w.beat === 2 && w.facade <= 0, 6000);
await sleep(400);
await shot('inside_sunbeam');
note('C the facade dissolves and control returns inside', W.beat === 2 && W.facade <= 0 && W.can_move);
note('C the facade\'s drips and glints went with it (none inside the room)', W.facadeWet === 0, `${W.facadeWet} still drawn`);

// ---- the spot ---------------------------------------------------------------
await hold('right');
await until(w => w.beat === 3, 10000, 10);
const spotX = W.x;
await until(w => w.step === 'circle', 4000, 10);
await shot('settle_circles');
await until(w => w.step === 'sit', 4000, 10);
await sleep(300);
await shot('settle_sits');
await until(w => w.step === 'lie_down', 4000, 10);
await sleep(700);
await shot('settle_lies_down');
await until(w => w.step === 'sleep', 4000, 10);
await sleep(800);
await shot('asleep_curled');
await hold('right', false);
note('D input locked through the settle (right held)', !W.can_move && Math.abs(W.x - 3520) <= 5, `x ${W.x.toFixed(0)}`);
note('D the settle anims run to the sleeping breath', W.anim === 'sleep_breath', W.anim);
await hold('jump'); await sleep(100); await hold('jump', false);
await hold('left'); await sleep(400); await hold('left', false);
await poll();
note('D movement keys change nothing once asleep', Math.abs(W.x - 3520) <= 5 && W.anim === 'sleep_breath');

// ---- the last lines ------------------------------------------------------------
const want = [
  'Home. It smells like home.',
  "I don't know exactly what I am now. Something more than I was.",
  'But some things are still simple.',
  'Warm sun. Soft cushion. Safe.',
  '...Wake cycle complete.',
];
const seen = [];
for (let k = 0; k < want.length; k++) {
  const ok = await until(w => w.monoIds.filter(i => i === 'home_final').length > k, 30000, 20);
  await sleep(1300);
  await poll();
  seen.push(W.monoLast);
  await shot(`final_line_${k + 1}`);
  if (!ok) break;
}
console.log(`MEASURE  frame rate: street ${fpsStreet}, close-up ${W.fps}`);
note('D home_final, every line in order', JSON.stringify(seen) === JSON.stringify(want), JSON.stringify(seen));
note('D the close-up has eased in', W.cz > 2.0, `zoom ${W.cz.toFixed(2)}`);
note('D the augments stay on, dimmed to a sleeping glow', W.aug && W.asleep && W.augE <= 0.35, `energy ${W.augE.toFixed(2)}`);
note('D the music is in', W.music > -20, `${W.music.toFixed(1)} dB`);
await until(w => w.fade > 0.45, 20000, 20);
await shot('fade_to_warm_white');

// ---- the credits ------------------------------------------------------------
await until(w => w.scene && w.scene.endsWith('credits.tscn'), 20000);
note('E the credits follow', W.scene.endsWith('credits.tscn'));
await until(w => w.title > 0.98, 10000, 20);
await shot('title_card');
await until(w => w.step === 2, 20000);
await sleep(2500);
await shot('credits_roll_1');
await hold('jump');
await sleep(3500);
await hold('jump', false);
await sleep(1500);
await shot('credits_roll_2');
await hold('jump');
await until(w => w.rollDone, 90000);
await hold('jump', false);
await sleep(1500);
await shot('thanks_for_playing');
await until(w => w.step === 3, 15000);
await sleep(2000);
await shot('the_end');
note('E "The End" shows and waits', W.step === 3 && W.end > 0.95);
await hold('right'); await sleep(120); await hold('right', false);
await until(w => w.scene && w.scene.endsWith('room1.tscn') && w.f > 0, 20000);
await sleep(2500);
await poll();
await shot('return_room1_intro');
note('E a movement press returns to Room 1, the intro', W.scene.endsWith('room1.tscn') && W.beat === 0, `beat ${W.beat}`);
note('E a fresh game: no mind, no save', !W.mind && !W.save, `mind ${W.mind} save ${W.save}`);

note('Z no console errors', consoleErrors.length === 0, consoleErrors.slice(0, 5).join(' | '));
const failed = results.filter(r => !r[1]);
console.log(`\n${results.length} checks, ${failed.length} failed`);
await browser.close();
server.close();
process.exit(failed.length ? 1 : 0);
