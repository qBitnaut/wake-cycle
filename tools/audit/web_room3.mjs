// Plays Room 3, "The Stacks", on the web export with real keyboard events
// (Playwright + system Chromium): the Spring discovery wall, the chained ledges,
// the conduit (the shockwave), the crates, the patrol bot, the shock switch,
// the mirror bot and its plate, the Spring tower, the Surge gap and the exit to
// Room 4, at the default capped frame rate. Starts through the
// debug deep link index.html?start=room3 (Room1 _web_start_override: the cat
// arrives as Room 2 leaves it). Reads the state Room 3 publishes in window.__wake
// every physics frame, takes a screenshot at every beat and records console
// errors. The proofs (a power is required, the shockwave only at the conduit,
// the mirror puzzle is recoverable) live in room3_playthrough.gd; this run is
// the route end to end in a real browser.
//
//   node tools/audit/web_room3.mjs <export_dir> <out_dir> [width height] [--gpu=swiftshader] [--dpr=1.25] [--port=8700]
//
// The server binds a port from 8700-8799 (a random free one unless --port is
// given), so it can run beside other audits.

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
const portFlag = flags.find(f => f.startsWith('--port='));
let bound = false;
for (let i = 0; i < 100 && !bound; i++) {
  const port = portFlag ? +portFlag.split('=')[1] : 8700 + Math.floor(Math.random() * 100);
  bound = await new Promise(res => {
    const onErr = () => res(false);
    server.once('error', onErr);
    server.listen(port, '127.0.0.1', () => { server.off('error', onErr); res(true); });
  });
  if (portFlag) break;
}
if (!bound) { console.log('FAIL no free port in 8700-8799'); process.exit(1); }
console.log('[server] http://127.0.0.1:' + server.address().port);
const url = `http://127.0.0.1:${server.address().port}/index.html?start=room3`;

const launchArgs = gpu === 'swiftshader'
  ? ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader']
  : ['--use-angle=vulkan', '--enable-features=Vulkan', '--enable-unsafe-webgpu'];
const browser = await chromium.launch({
  executablePath: '/usr/bin/chromium',
  headless: true,
  args: [...launchArgs, '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required', '--no-sandbox'],
});
const page = await browser.newPage({ viewport: { width: +W_, height: +H_ }, deviceScaleFactor: +((flags.find(f => f.startsWith('--dpr=')) || '--dpr=1').split('=')[1]) });
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

// The opening: Room 2 comes up through the deep link.
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
await page.mouse.click(+W_ / 2, +H_ / 2);  // focus the canvas (a click moves nothing: no mouse input)
for (let i = 0; i < 400 && !(W.scene.endsWith('room3.tscn') && W.f > 0); i++) { await sleep(50); await poll(); }

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
async function goTo(x, tol = 6, limit = 1500) {
  let n = 0;
  while (Math.abs(W.x - x) > tol && n++ < limit) { await dir(Math.sign(x - W.x)); await frame(); }
  await dir(0); await ticks(6); return n < limit;
}
// A reactive runner (the same rules as room2_playthrough.gd run_to): hold right, hop walls and
// walkers, double jump pits from the last pixel, crouch between cf and ct. `each` runs every frame.
async function runTo(target, o = {}) {
  let jf = -1, pit = false, n = 0;
  while (W.x < target && n++ < (o.limit || 2400) && !W.dead) {
    await dir(1);
    const crouch = o.cf !== undefined && W.x >= o.cf && W.x <= o.ct;
    await hold('down', crouch);
    const air = jf < 0 ? -1 : W.f - jf;
    if (W.floor && air >= 3) { jf = -1; await hold('jump', false); }
    if (W.floor && jf < 0 && !crouch) {
      const botAhead = (W.bots || []).some(b => { const dx = b[0] - W.x, dy = b[1] - W.y; return dx > 40 && dx < 92 && Math.abs(dy) < 30; });
      const noGround = !W.groundBelow;
      if (W.wallAhead || noGround || botAhead) { await hold('jump', true); jf = W.f; pit = noGround; }
    } else if (jf >= 0) {
      if (pit && air === 26) await hold('jump', false);
      else if (pit && air === 27) await hold('jump', true);
      else if (!pit && air > 24) await hold('jump', false);
    }
    if (o.each) await o.each();
    await frame();
  }
  await stop();
  return W.x >= target;
}
const T = 32;
const waitFor = async (cond, ms = 8000) => { for (let t = 0; t < ms; t += 20) { await poll(); if (cond()) return true; await sleep(20); } return false; };
const lines = id => W.monoIds.filter(i => i === id).length;

// ---- hops: the parameters room3_playthrough.gd found (jump_x, frames to the double jump) -------
// run right to jumpX, jump, double jump `dj` frames later (held for 40 frames), until it lands
async function hop(jumpX, dj, mid) {
  let n = 0;
  while (W.x < jumpX && n++ < 900) { await dir(1); await frame(); }
  await hold('jump', true);
  let f = 0, done = dj < 0;
  const y0 = W.y;
  while (f < 220) {
    await dir(1); await frame(); f++;
    if (!done && f === dj) await hold('jump', false);
    else if (!done && f === dj + 1) { await hold('jump', true); done = true; }
    else if (f === dj + 40) await hold('jump', false);
    if (mid && f === mid.at) { await mid.fn(); }
    if (f > 6 && W.floor && W.vy >= 0) break;
    if (W.y > y0 + 700) break;
  }
  await stop(); await ticks(3);
}
async function burst() {
  await hold('jump', true); await ticks(8);
  await hold('jump', false); await ticks(1);
  await hold('jump', true); await ticks(6);
  await hold('jump', false);
}
const S1 = 960, S2 = 768, S3 = 576, S4 = 384;
const landed = (x0, x1, y) => W.floor && W.x >= x0 && W.x <= x1 && Math.abs(W.y - y) < 3;
async function measureFps(label, ms = 3000) {
  const r = await page.evaluate(ms => new Promise(res => {
    let n = 0; const t0 = performance.now(); let last = t0; const times = [];
    function f(t) { n++; times.push(t - last); last = t; if (t - t0 < ms) requestAnimationFrame(f); else {
      times.sort((a, b) => a - b);
      res({ fps: +(n * 1000 / (t - t0)).toFixed(1), p50: +times[Math.floor(times.length * 0.5)].toFixed(2), p95: +times[Math.floor(times.length * 0.95)].toFixed(2) }); } }
    requestAnimationFrame(f);
  }), ms);
  console.log(`[fps] ${W_}x${H_} ${label}`, JSON.stringify(r));
}

// ---- A: arrival in the easing rain -------------------------------------------------------
await sleep(1500); await poll();
note('A arrives in Room 3 through the transition: yard floor, control, HUD', W.scene.endsWith('room3.tscn') && Math.abs(W.x - 112) < 10 && W.can_move && W.hud, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
note('A mind awake, no power, no shockwave, auto-saved', W.mind && W.power === 0 && !W.shock && W.save);
await shot('A_arrival_rain_easing_skyline');
await waitFor(() => lines('stacks_arrival') >= 2, 14000);
await sleep(500);
note('A arrival monologue (the rain is easing / not one person)', lines('stacks_arrival') === 2, `${lines('stacks_arrival')} lines`);
await shot('A_arrival_monologue');
await measureFps('the yard in the lighter rain');
const hp0 = W.hp;
let ok = await runTo(980);
note('A crossed the arrival yard past the walker and the crates', ok && W.hp === hp0 && !W.dead, `x=${W.x.toFixed(0)} hp ${W.hp}`);
await shot('A_the_wall_and_the_pad');

// ---- B1: Spring, discovery -----------------------------------------------------------------------
await shot('B1_pad_at_the_foot_of_the_wall_ledge_above');
await hop(1053, 12, { at: 14, fn: async () => { await shot('B1_spring_double_jump_up_the_wall'); } });
note('B1 the pad granted Spring and the double jump climbs the 6-tile wall', landed(1100, 1700, S1) && W.grants >= 1, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)} power ${W.power}`);
await sleep(400);
await shot('B1_on_the_shed_roof_emitters_green');
await waitFor(() => lines('spring_first') >= 2, 14000);
note('B1 first-use monologue (up! higher / green this time)', lines('spring_first') === 2, `${lines('spring_first')} lines`);
note('B1 the HUD has the power and a running timer', W.power === 2 && W.powerTime > 0 && W.powerTime < 10, `${W.powerTime.toFixed(1)} s left`);

// ---- B2: Spring, use it ---------------------------------------------------------------------------
await goTo(1168, 8); await ticks(6);
note('B2 checkpoint A', W.cp === 'cp_a', W.cp);
await goTo(1328, 8); await ticks(6);
note('B2 second pad: Spring refreshed', W.power === 2 && W.powerTime > 9, `${W.powerTime.toFixed(1)} s`);
await shot('B2_pad_two_ledge_above');
const tChain = W.f;
await hop(1369, 12, { at: 14, fn: async () => { await shot('B2_chain_first_jump'); } });
const ledgeOk = landed(1450, 1625, S2);
await shot('B2_on_the_floating_ledge');
await hop(1609, 12);
const roofOk = landed(1735, 2100, S3);
note('B2 the chain: shed roof -> ledge -> long roof inside one charge', ledgeOk && roofOk && W.power === 2, `${((W.f - tChain) / 60).toFixed(1)} s, ${W.powerTime.toFixed(1)} s of Spring left`);
await shot('B2_long_roof_reached');
ok = await runTo(1900);
note('B2 checkpoint B on the long roof', W.cp === 'cp_b', W.cp);

// ---- C: the conduit -----------------------------------------------------------------------------
note('C the shockwave is still locked before the conduit', W.shock === false);
await shot('C_gallery_mouth_tunnel_ahead');
await dir(1);
let conduitShot = false, sparkShot = false;
for (let n = 0; !W.shock && n < 900; n++) {
  await frame();
  if (W.x > 2100 && !sparkShot) { sparkShot = true; await shot('C_the_sparking_conduit_ahead'); }
}
if (W.shock) { await shot('C_the_flash_shockwave_unlocked'); conduitShot = true; }
await stop();
note('C the conduit unlocks the shockwave, harmlessly', W.shock && W.hp === 3 && W.unlocks === 1, `x=${W.x.toFixed(0)} hp ${W.hp}`);
await sleep(500);
await shot('C_augments_flare');
await waitFor(() => lines('conduit') >= 2, 14000);
note('C the conduit monologue (not pain / the air pushes out)', lines('conduit') === 2, `${lines('conduit')} lines`);
await shot('C_conduit_monologue');
await waitFor(() => W.can_move, 4000);
note('C control returns after the hold', W.can_move);

// ---- E1: the crates ----------------------------------------------------------------------------
await goTo(2424, 6);
await shot('E1_crate_stack_blocks_the_corridor');
for (let k = 0; k < 5 && W.crates > 0; k++) {
  await burst(); await ticks(10);
  if (k === 0) await shot('E1_shockwave_breaks_crates');
  await ticks(30); await dir(1); await ticks(25); await stop(); await ticks(5);
}
note('E1 the double-jump shockwave breaks the crates', W.crates === 0, `${W.crates} left`);
await waitFor(() => lines('shock_first') >= 1, 12000);
note('E1 "a lot of power for a house cat" plays', lines('shock_first') === 1);
await shot('E1_crates_gone_monologue');

// ---- E2: the patrol bot -----------------------------------------------------------------------------
await runTo(2640);
await shot('E2_patrol_bot_in_the_corridor');
for (let n = 0; n < 900 && !(W.patrol && W.patrol[2] === 1); n++) {
  await stop();
  if (W.patrol && Math.abs(W.patrol[0] - W.x) < 70 && W.floor) { await burst(); await ticks(2); } else await frame();
}
note('E2 the shockwave stuns the bot', W.patrol && W.patrol[2] === 1, `bot ${W.patrol && W.patrol[0].toFixed(0)}`);
await shot('E2_bot_stunned');
const hpE = W.hp;
ok = await runTo(3050);
note('E2 and the cat passes it unhurt', ok && W.hp === hpE && !W.dead, `hp ${W.hp}`);

// ---- E3: the switch and the shutter ---------------------------------------------------------------
await goTo(3154, 6);
await dir(1); await ticks(60); await stop();
note('E3 the shutter is shut: the cat cannot pass', W.shutter === false && W.x < 3176, `x=${W.x.toFixed(0)}`);
await shot('E3_shutter_shut_switch_behind');
await goTo(3048, 6);
for (let k = 0; k < 4 && !W.switch; k++) { await burst(); await ticks(30); }
note('E3 a double jump near the switch opens the shutter', W.switch && W.shutter, `switch ${W.switch}`);
await shot('E3_switch_on_shutter_rolling_up');
ok = await runTo(3214);
note('E3 through the shutter inside the window', ok && W.switch, `x=${W.x.toFixed(0)}`);

// ---- F: the machine bay, the mirror bot --------------------------------------------------------------
await goTo(3200, 6); await ticks(10);
note('F the loader bot sleeps until the cat is near', W.mirror && W.mirror[2] === false);
await dir(1);
for (let n = 0; n < 200 && !(W.mirror && W.mirror[2]); n++) await frame();
await stop();
note('F it wakes as the augmented cat steps onto the catwalk', W.mirror && W.mirror[2], `cat ${W.x.toFixed(0)} bot ${W.mirror && W.mirror[0].toFixed(0)}`);
await shot('F_loader_bot_wakes_below_the_catwalk');
note('F checkpoint at the bay mouth', W.cp === 'cp_bay', W.cp);
const bx0 = W.mirror[0], cx0 = W.x;
await runTo(cx0 + 200);
await ticks(30);
note('F the bot mirrors the steps: same direction, same distance', Math.abs((W.mirror[0] - bx0) - (W.x - cx0)) < 0.1 * (W.x - cx0), `cat ${(W.x - cx0).toFixed(0)} px, bot ${(W.mirror[0] - bx0).toFixed(0)} px`);
await waitFor(() => lines('mirror_bot') >= 2, 14000);
note('F the mirror monologue plays', lines('mirror_bot') === 2);
await shot('F_the_bot_copies_every_step');
// walk back, then forward again: nothing is lost
await dir(-1); for (let n = 0; n < 200 && W.x > 3190; n++) await frame(); await stop(); await ticks(20);
note('F walking back brings the bot back and the shutter stays shut', W.plate === false && W.bayShutter === false);
await shot('F_walked_back_the_bot_follows');
await dir(1);
let plateShot = false;
for (let n = 0; n < 1500 && !W.plate; n++) { await frame(); if (W.mirror[0] > 3800 && !plateShot) { plateShot = true; await shot('F_bot_nearing_the_plate'); } }
await stop();
note('F the bot ends on the plate at the end of its track', W.plate === true, `cat ${W.x.toFixed(0)} bot ${W.mirror[0].toFixed(0)}`);
await sleep(700);
await shot('F_plate_held_shutter_open');
note('F the shutter at the end of the catwalk is open', W.bayShutter === true);
ok = await runTo(4170);
note('F the cat walks on through, the plate keeps holding', ok && W.plate && W.bayShutter, `x=${W.x.toFixed(0)}`);

// ---- G: Spring tower, Surge gap -----------------------------------------------------------------------
await runTo(4240); await ticks(10);
note('G checkpoint C', W.cp === 'cp_c', W.cp);
await shot('G_the_tower_and_its_pad');
await hop(4381, 12, { at: 14, fn: async () => { await shot('G_spring_up_the_tower'); } });
note('G Spring climbs the tower', landed(4430, 4660, S4), `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
await shot('G_tower_top_the_gap_ahead');
await goTo(4528, 6); await ticks(40);
note('G the Surge pad on top replaces Spring', W.power === 1, `power ${W.power}`);
await shot('G_surge_pad_emitters_blue_ten_tile_gap');
await hop(4668, 27, { at: 22, fn: async () => { await shot('G_crossing_the_gap_mid_air'); } });
note('G Surge double jump crosses the ten-tile gap', landed(4995, 5400, S4), `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
await ticks(10);
await goTo(5056, 6); await ticks(10);
note('G checkpoint D on the exit roof', W.cp === 'cp_d', W.cp);
await runTo(5150);
await waitFor(() => lines('stacks_exit') >= 2, 14000);
await sleep(300);
await shot('G_exit_roof_suburb_lights_in_the_distance');
note('G exit monologue (past the fences, little lights in windows)', lines('stacks_exit') === 2);
note('G only Spring and Surge were granted, no violations', W.violations === 0, `${W.grants} grants`);

// ---- H: the exit -----------------------------------------------------------------------------------------
await dir(1);
for (let n = 0; W.scene.endsWith('room3.tscn') && n < 900; n++) { await frame(); if (n === 40) await shot('H_exit_fade'); }
await stop();
for (let i = 0; i < 100 && !W.scene.endsWith('room4.tscn'); i++) { await sleep(50); await poll(); }
await sleep(1800); await poll();
note('H exit leads to Room 4', W.scene.endsWith('room4.tscn'), W.scene);
note('H the shockwave and the mind carried over, saved', W.save && W.mind && W.shock, `power ${W.power}`);
await shot('H_room4_arrival');

const failed = results.filter(r => !r[1]);
console.log(`== ${results.length} checks, ${failed.length ? failed.length + ' FAILED' : 'ALL PASS'}; console errors: ${consoleErrors.length}`);
consoleErrors.slice(0, 20).forEach(e => console.log('  [console error]', e.slice(0, 300)));
await browser.close();
server.close();
process.exit(failed.length || consoleErrors.length ? 1 : 0);
