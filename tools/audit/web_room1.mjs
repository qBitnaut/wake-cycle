// Plays Warehouse Room 1 on the web export with real keyboard events
// (Playwright + system Chromium), from the first black frame to Room 2, with
// plain movement only. Reads the state Room 1 publishes in window.__wake every
// physics frame, takes a screenshot at every beat and records console errors.
//
//   node tools/audit/web_room1.mjs <export_dir> <out_dir> [width height] [--gpu=swiftshader]
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
const url = `http://127.0.0.1:${server.address().port}/index.html`;

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

const sleep = ms => new Promise(r => setTimeout(r, ms));
let shotN = 0;
async function shot(name) { await page.screenshot({ path: `${outdir}/${String(++shotN).padStart(2, '0')}_${name}.png` }); }
const results = [];
function note(name, ok, detail = '') {
  results.push([name, ok, detail]);
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name.padEnd(50)} ${detail}`);
}

// The opening: shoot the fade from black as it happens, before any input.
await page.goto(url);
const renderer = await page.evaluate(() => {
  const c = document.createElement('canvas').getContext('webgl2');
  const d = c && c.getExtension('WEBGL_debug_renderer_info');
  return d ? c.getParameter(d.UNMASKED_RENDERER_WEBGL) : 'unknown';
});
console.log('[gpu]', renderer);

let W = null;
async function poll() { W = await page.evaluate(() => window.__wake || null); return W; }
for (let i = 0; i < 1200 && !(await poll()); i++) await sleep(50);
if (!W) { console.log('FAIL game never published state'); process.exit(1); }
const f0 = W.f;
note('A opens on Room 1 asleep, input locked', W.scene.endsWith('room1.tscn') && !W.can_move && W.anim.startsWith('sleep'), `${W.scene} anim ${W.anim}`);
note('A HUD hidden, no power UI at the start', !W.hud && W.power === 0 && !W.shock);
await page.mouse.click(+W_ / 2, +H_ / 2);  // focus the canvas (a click moves nothing: no mouse input)
// Wait on physics frames: black (0-0.6 s), fade up (to 2.8 s), title in (3.2-4.6 s).
async function untilFrame(n) { while ((await poll()).f - f0 < n) await sleep(15); }
await shot('opening_black_0s');
await untilFrame(100); await shot('opening_fade_1.7s');
await untilFrame(190); await shot('opening_fade_3.2s_nook_moonlight');
await untilFrame(300); await shot('title_Find_Your_Way_Out');
note('A title on screen while the input is still locked', W.title && !W.can_move, `f=${W.f - f0}`);
// Mashing keys in the dark moves nothing.
const x0 = W.x;
await page.keyboard.down('KeyD'); await page.keyboard.down('Space'); await sleep(400);
await page.keyboard.up('KeyD'); await page.keyboard.up('Space');
await poll();
note('A keys do nothing while it sleeps', Math.abs(W.x - x0) < 1 && !W.can_move, `dx=${(W.x - x0).toFixed(1)}`);
// Title out (to 8.4 s), then the stretch.
for (let i = 0; i < 2000 && W.title; i++) { await sleep(20); await poll(); }
await sleep(250); await poll();
await shot('wake_stretch');
note('A the stretch (wake-up) plays before control', W.anim === 'stretch' && !W.can_move, `anim ${W.anim}`);
for (let i = 0; i < 400 && !W.can_move; i++) { await sleep(20); await poll(); }
note('A control granted, HUD shown', W.can_move && W.hud, `f=${W.f - f0} (~${((W.f - f0) / 60).toFixed(1)} s)`);
await shot('A_awake_nook');
await measureFps('nook, moon sliver');

async function measureFps(label, ms = 4000) {
  const r = await page.evaluate(ms => new Promise(res => {
    let n = 0; const t0 = performance.now(); let last = t0; const times = [];
    function f(t) { n++; times.push(t - last); last = t; if (t - t0 < ms) requestAnimationFrame(f); else {
      times.sort((a, b) => a - b);
      res({ fps: +(n * 1000 / (t - t0)).toFixed(1), p50: +times[Math.floor(times.length * 0.5)].toFixed(2), p95: +times[Math.floor(times.length * 0.95)].toFixed(2), max: +times[times.length - 1].toFixed(2) }); } }
    requestAnimationFrame(f);
  }), ms);
  console.log(`[fps] ${W_}x${H_} ${label}`, JSON.stringify(r));
}

// ---- input helpers ----------------------------------------------------------
const CODE = { right: 'KeyD', left: 'KeyA', jump: 'Space', down: 'KeyS' };
const held = new Set();
async function hold(a, on = true) {
  if (on && !held.has(a)) { held.add(a); await page.keyboard.down(CODE[a]); }
  else if (!on && held.has(a)) { held.delete(a); await page.keyboard.up(CODE[a]); }
}
async function dir(d) { await hold('right', d > 0); await hold('left', d < 0); }
async function stop() { for (const a of [...held]) await hold(a, false); }
async function frame() {
  const f = W.f;
  for (let i = 0; i < 4000; i++) { await poll(); if (W.f > f) return W; await sleep(1); }
  throw new Error('physics stalled');
}
async function ticks(n) { for (let i = 0; i < n; i++) await frame(); }
const T = 32;
async function goTo(x, tol = 6, limit = 900) {
  let n = 0;
  while (Math.abs(W.x - x) > tol && n++ < limit) { await dir(Math.sign(x - W.x)); await frame(); }
  await dir(0); await ticks(6); return n < limit;
}
async function hop(d, dirFrames, dj = 0, holdFrames = 999, max = 300) {
  await hold('jump', true); await dir(d);
  for (let t = 1; t < max; t++) {
    await frame();
    if (t === dirFrames) await dir(0);
    if (t === holdFrames) await hold('jump', false);
    if (dj && t === dj) { await hold('jump', false); await frame(); await hold('jump', true); }
    if (t > 8 && W.floor) break;
  }
  await stop(); await ticks(8);
}
// Run right and take off at x >= jx (a running jump, like a player's), dir held for dirFrames.
async function runHop(jx, dirFrames, dj = 0) {
  await dir(1);
  for (let n = 0; W.x < jx && n < 400; n++) await frame();
  await hold('jump', true);
  for (let t = 1; t < 300; t++) {
    await frame();
    if (t === dirFrames) await dir(0);
    if (dj && t === dj) { await hold('jump', false); await frame(); await hold('jump', true); }
    if (process.env.HOP_TRACE) console.log(`   t=${t} x=${W.x.toFixed(0)} y=${W.y.toFixed(0)} vx=${W.vx.toFixed(0)} vy=${W.vy.toFixed(0)} f=${W.f}`);
    if (t > 8 && W.floor) break;
  }
  await stop(); await ticks(8);
}
const onFloorAt = (y, tol = 3) => W.floor && Math.abs(W.y - y) < tol;
const noPowers = () => W.power === 0 && !W.shock && W.violations === 0;

await goTo(112, 4);
note('A bonus letter A tucked in the cardboard box', W.letters === 1, `letters ${W.letters}`);
await shot('A_letter_in_box_hud_letters');

// ---- B: crate stairs, the catwalk -------------------------------------------
await goTo(430); await hop(1, 14);
note('B crate step 1 (1 tile)', onFloorAt(288) && W.x > 448 && W.x < 512, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
await goTo(498, 4); await hop(1, 12);
note('B crate step 2 (2 tiles)', onFloorAt(256) && W.x > 544 && W.x < 608, `x=${W.x.toFixed(0)}`);
await goTo(596, 4); await hop(1, 12);
note('B crate step 3: the catwalk level', onFloorAt(224) && W.x > 640, `x=${W.x.toFixed(0)}`);
await shot('B_catwalk_moonbeam');
await goTo(820, 4); await runHop(892, 60);
note('B catwalk gap crossed (3 tiles, single jump)', onFloorAt(228) && W.x > 992, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
await shot('B_catwalk_gap_crossed');
// Secret letter C: drop off deck 2's left end into the pocket under the gap.
await dir(-1);
for (let n = 0; !(W.x < 985 && W.floor && W.y > 300) && n < 300; n++) await frame();
await stop(); await goTo(944, 4); await ticks(6);
note('B secret letter C under the catwalk gap', W.letters === 2, `letters ${W.letters}`);
await shot('B_secret_letter_C_pocket');
await goTo(1120, 4); await hop(1, 12);
await goTo(1180); await ticks(30);
await goTo(1240, 6); await hop(1, 12);
await goTo(1360); await ticks(10);
note('B checkpoint A saves', W.cp === 'cp_a', W.cp);
await shot('B_checkpoint_A');

// ---- C: puddle hall, rain window, the bot -------------------------------------
await goTo(1385);
// Step into the first puddle (cols 44-47) and look at the splash and ripple.
await dir(1);
for (let n = 0; W.ripples === 0 && n < 200; n++) await frame();
let rippled = W.ripples > 0, splashShot = false, hp0 = W.hp;
await dir(0); await ticks(2); await shot('C_puddle_splash'); splashShot = true;
await hold('right', true);
for (let n = 0; W.x < 1830 && n < 1800 && !W.dead; n++) {
  const d = W.bot[0] - W.x;
  if (d > 30 && d < 62 && W.floor && W.bot[3] === 0) {
    await hold('jump', true); await ticks(22); await hold('jump', false);
  } else await hold('jump', false);
  await frame();
}
await stop(); await ticks(20);
note('C waded through the puddle: ripple and splash', rippled && splashShot);
note('C got past the patrol bot (stomp attempted)', W.x >= 1830 && !W.dead, `x=${W.x.toFixed(0)} hp ${W.hp} stomps ${W.bot[2]}`);
await shot('C_hall_rain_window_bot');

// ---- D: crawl ----------------------------------------------------------------
await goTo(1880); await dir(1); await ticks(100); await stop();
note('D low beam blocks the standing cat', W.x < 1952, `x=${W.x.toFixed(0)}`);
await hold('down', true); await dir(1);
for (let n = 0; W.x < 2190 && n < 1200; n++) { await frame(); if (n === 150) await shot('D_crawl'); }
await stop(); await ticks(20);
note('D crawled under the beam (crouch)', W.x >= 2150, `x=${W.x.toFixed(0)}`);

// ---- E: timed fence, crate on the plate, shutter -------------------------------
await goTo(2330); hp0 = W.hp;
for (let n = 0; !W.fenceT && n < 600; n++) await frame();
await shot('E_laser_fence_on');
for (let n = 0; W.fenceT && n < 600; n++) await frame();
await ticks(2); await dir(1);
while (W.x < 2500 && !W.dead) await frame();
await stop();
note('E timed fence crossed in its off window', W.x >= 2500 && W.hp === hp0, `x=${W.x.toFixed(0)} hp ${W.hp}`);
await goTo(2490);
note('E shutter shut at first', !W.shutter);
await dir(1);
for (let n = 0; !W.plate && n < 900; n++) await frame();
await stop(); await ticks(40);
note('E crate pushed onto the plate, shutter opens', W.plate && W.shutter, `crate x=${W.crate[0].toFixed(0)}`);
await shot('E_crate_on_plate_shutter_open');
await ticks(30); await hop(1, 26); await goTo(2790); await goTo(2860);
note('E through the shutter', W.x > 2850, `x=${W.x.toFixed(0)}`);

// ---- F: key, door ---------------------------------------------------------------
await goTo(2950); await hop(1, 12); await hop(1, 12);
note('F stairs up to the key deck', onFloorAt(228), `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
await goTo(3070, 5); await goTo(3120); await ticks(6);
note('F brass key on the deck', W.keys.includes('brass'), JSON.stringify(W.keys));
await shot('F_key_deck');
await goTo(3140, 5); await dir(1); await ticks(100); await stop(); await ticks(20);
await goTo(3300); await dir(1);
for (let n = 0; W.door && n < 300; n++) await frame();
await goTo(3420);
note('F door opened with the key', !W.door && !W.keys.includes('brass'), `x=${W.x.toFixed(0)}`);
await shot('F_door_opened');
await goTo(3472); await ticks(10);
note('F checkpoint B saves', W.cp === 'cp_b', W.cp);
note('F no powers yet', noPowers());

// ---- G: steam vents ----------------------------------------------------------------
hp0 = W.hp;
let steamShot = false;
for (const [px, idx, to] of [[3470, 0, 3640], [3670, 1, 3800], [3830, 2, 3960]]) {
  await goTo(px, 5);
  let seen = false;
  for (let i = 0; i < 900; i++) {
    if (W.steam[idx]) { seen = true; if (!steamShot && idx === 0) { steamShot = true; await shot('G_steam_vent_on'); } }
    else if (seen) break;
    await frame();
  }
  note(`G vent ${idx + 1} cycles on and off`, seen && !W.steam[idx]);
  await dir(1);
  while (W.x < to && !W.dead) await frame();
  await stop(); await ticks(4);
}
note('G steam dodged, no hits', W.hp === hp0 && !W.dead, `x=${W.x.toFixed(0)} hp ${W.hp}`);

// ---- H: flooded hall -----------------------------------------------------------------
// Wade through the flooded hall's puddle and look at the splash.
await goTo(3900); await dir(1);
for (let n = 0; W.ripples === 0 && n < 200; n++) await frame();
for (let k = 0; k < 3; k++) { await shot(`H_puddle_splash_${k}`); await frame(); }
await goTo(4050); await goTo(4080); await hop(1, 12); await hop(1, 12);
await goTo(4140, 5); await hop(1, 24, 18);
note('H bonus letter T on the high perch: all three, bonus score', W.letters === 3 && W.score >= 5000, `letters ${W.letters} score ${W.score}`);
await goTo(4240, 6); await dir(1); await ticks(60); await stop(); await ticks(40);
await shot('H_flooded_hall_tanks');
await goTo(4250);
await shot('I_pool_approach_dark_water');
await measureFps('pool approach');
await goTo(4330, 4); await hop(1, 10); await goTo(4400);
note('H up on the sill at the lip of the pool, still no powers, mind asleep', !W.mind && onFloorAt(288) && noPowers(), `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
await shot('I_pool_edge');

// ---- I: the pool -------------------------------------------------------------------------
await goTo(4350); await dir(1);
while (W.x < 4410) await frame();
await hold('jump', true);
for (let t = 0; t < 200 && W.beat === 1; t++) {
  await frame();
  if (t === 20) { await hold('jump', false); await frame(); await hold('jump', true); }
}
await stop();
const caughtX = W.x;
await shot('I_trigger_moment');
note('I jumping the pool fails: the cat is caught', W.beat === 2 && caughtX < 4736, `caught at x=${caughtX.toFixed(0)} (pool 4416..4736)`);
note('I input locked in the pool', !W.can_move);
const px0 = W.x;
await dir(1); await hold('jump', true); await ticks(60); await stop();
note('I the cat is stuck: feet do not move', Math.abs(W.x - px0) < 3, `dx=${(W.x - px0).toFixed(1)}`);
await shot('I_struggle');
await ticks(160); await shot('I_transform_stub_mid');
for (let n = 0; W.beat !== 4 && n < 1500; n++) await frame();
note('I TransformSequence finished: mind awakened, no power, no shockwave', W.beat === 4 && W.mind && !W.shock && W.violations === 0 && W.power === 0);
note('I control returns, pool goes inert', W.can_move);
await ticks(200);
await shot('I_after_transform_pool_inert');

// ---- J: exit --------------------------------------------------------------------------------
await goTo(4690, 8); await hop(1, 12);
note('J out of the pool onto the far sill', onFloorAt(288) && W.x > 4730, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
await shot('J_loading_door_night_outside');
await dir(1);
for (let n = 0; W.scene.endsWith('room1.tscn') && n < 600; n++) { await frame(); if (n === 40) await shot('J_exit_fade'); }
await stop();
for (let i = 0; i < 100 && !W.scene.endsWith('room2.tscn'); i++) await sleep(50);
await sleep(1500); await poll();
note('J exit fades out and loads Room 2', W.scene.endsWith('room2.tscn'), W.scene);
note('J Room 2 auto-saved, mind awake, still no shockwave', W.save && W.mind && !W.shock && W.power === 0, `save ${W.save}`);
await shot('K_room2_coming_soon');

const failed = results.filter(r => !r[1]);
console.log(`== ${results.length} checks, ${failed.length ? failed.length + ' FAILED' : 'ALL PASS'}; console errors: ${consoleErrors.length}`);
consoleErrors.slice(0, 20).forEach(e => console.log('  [console error]', e.slice(0, 300)));
await browser.close();
server.close();
process.exit(failed.length || consoleErrors.length ? 1 : 0);
