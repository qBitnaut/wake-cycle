// Plays Room 3, "The Stacks" (48 rows tall), on the web export with real keyboard events
// (Playwright + system Chromium): the Spring discovery wall, the chained ledges, the underfloor
// corridor (electric strip, crawlers, moving platform, hopper, falling platforms, the lift), the
// conduit (the shockwave), the crates, the patrol bot, the shock switch, the light well ladder, the
// roof (cracked wall and crawlspace, turret, laser bot, the barrel chain and the sealed door), the
// vent tower (Spring, steam, falling platform, flame, the golden bone and the memory fragment),
// the mirror bot and its plate, the exit tower and the exit to the world map and Room 4, at the
// default capped frame rate. Starts through the
// debug deep link index.html?start=room3 (Room1 _web_start_override: the cat
// arrives as Room 2 leaves it). Reads the state Room 3 publishes in window.__wake
// every physics frame, takes a screenshot at every beat and records console
// errors. The proofs (a power is required, the shockwave only at the conduit,
// the mirror puzzle is recoverable) live in room3_playthrough.gd; this run is
// the route end to end in a real browser.
//
//   node tools/audit/web_room3.mjs <export_dir> <out_dir> [width height] [--gpu=swiftshader] [--dpr=1.25] [--port=10300]
//
// The server binds a port from 10300-10399 (a random free one unless --port is
// given), so it can run beside other audits.

// Needs the playwright package (PW_DIR env, default: the mise npm-playwright
// install) and /usr/bin/chromium. By default it asks Chromium for the real GPU
// through ANGLE/Vulkan; pass --gpu=swiftshader for the software rasteriser.
import { createRequire } from 'node:module';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { installAudioProbe, audioLoops, soundClean } from './web_audio_probe.mjs';

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
  const port = portFlag ? +portFlag.split('=')[1] : 10300 + Math.floor(Math.random() * 100);
  bound = await new Promise(res => {
    const onErr = () => res(false);
    server.once('error', onErr);
    server.listen(port, '127.0.0.1', () => { server.off('error', onErr); res(true); });
  });
  if (portFlag) break;
}
if (!bound) { console.log('FAIL no free port in 10300-10399'); process.exit(1); }
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
await installAudioProbe(page);   // what the browser really plays (Godot's web audio is samples)
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

// The room stops publishing once the map takes over (frame() then stalls: the exit wait catches it).
// The exit lands on the world map (the level finishes, the next one opens and the cat
// walks to it); the next room is entered from the map with Up, as the player does it.
async function throughMap(tag, done, next, nextFile) {
  let M = null;
  for (let i = 0; i < 400 && !(M && M.scene === 'map'); i++) { await sleep(50); M = await page.evaluate(() => window.__map || null); }
  note(`${tag} the exit fades out onto the world map`, !!M && M.scene === 'map', M ? M.scene : 'no map');
  if (!M) return;
  for (let i = 0; i < 1500 && !(M.node === next && !M.auto); i++) { await sleep(50); M = await page.evaluate(() => window.__map || M); }
  note(`${tag} ${done} is finished, ${next} is open and the cat stands on it`, M.completed.includes(done) && M.open.includes(next) && M.node === next, `completed ${M.completed} node ${M.node}`);
  await sleep(400);
  await shot(`${tag}_map_after_${done}`);
  M = await page.evaluate(() => window.__map || M);
  { const c = soundClean(M.loops || { playing: 0, orphans: 0, positional: 0 }, await audioLoops(page));
    note(`${tag} sound: on the map no looping sound from the room plays (tree and browser)`, c.ok && (M.loops ? M.loops.positional === 0 : false), c.detail); }
  await page.keyboard.down('KeyW'); await sleep(90); await page.keyboard.up('KeyW');
  for (let i = 0; i < 600 && !(W.scene.endsWith(nextFile) && W.f > 0); i++) { await sleep(50); await poll(); }
  await sleep(900); await poll();
  { const c = soundClean(W.loops || { playing: 0, orphans: 0, positional: 0 }, await audioLoops(page));
    note(`${tag} sound: in the next room no looping sound is left from the previous one`, c.ok, c.detail); }
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
// A reactive runner (the same rules as room3_playthrough.gd run_to): hold a direction, hop walls,
// walkers and (gaps) the edge of a pit with a single jump. Either direction.
async function runTo(target, o = {}) {
  const d = Math.sign(target - W.x) || 1;
  let jf = -1, n = 0;
  while ((target - W.x) * d > 0 && n++ < (o.limit || 2400) && !W.dead) {
    await dir(d);
    const air = jf < 0 ? -1 : W.f - jf;
    if (W.floor && air >= 3) { jf = -1; await hold('jump', false); await frame(); continue; }
    if (W.floor && jf < 0) {
      const botAhead = (W.bots || []).some(b => { const dx = (b[0] - W.x) * d, dy = b[1] - W.y; return dx > 40 && dx < 92 && Math.abs(dy) < 30; });
      const edge = o.gaps && !W.groundAhead && d > 0;
      if ((d > 0 ? W.wallAhead : W.wallAhead) || botAhead || edge) { await hold('jump', true); jf = W.f; }
    } else if (jf >= 0 && air > 24) await hold('jump', false);
    await frame();
  }
  await stop();
  return (target - W.x) * d <= 0;
}
const T = 32;
const waitFor = async (cond, ms = 8000) => { for (let t = 0; t < ms; t += 20) { await poll(); if (cond()) return true; await sleep(20); } return false; };
const lines = id => W.monoIds.filter(i => i === id).length;
// Wait standing still, hopping whatever walks or rolls at the cat.
async function waitEvading(cond, limit = 1500) {
  for (let n = 0; n < limit && !cond() && !W.dead; n++) {
    if (W.floor && (W.bots || []).some(b => Math.abs(b[0] - W.x) < 62 && Math.abs(b[1] - W.y) < 26)) {
      await hold('jump', true); await ticks(18); await hold('jump', false);
    }
    await frame();
  }
  return cond();
}
const idleStart = k => W.phase[k] === 0 && W.phaseT[k] < 0.25;
async function waitIdle(k) { for (let n = 0; n < 900 && !idleStart(k); n++) await frame(); }

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
const R1 = 1216, R2 = 1024, R3 = 832, R4 = 640, R5 = 448, R6 = 256;
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
  return r;
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
const fpsA = await measureFps('the yard in the lighter rain');
const hp0 = W.hp;
let ok = await runTo(980);
note('A crossed the arrival yard past the walker and the crates', ok && W.hp === hp0 && !W.dead, `x=${W.x.toFixed(0)} hp ${W.hp}`);
await shot('A_the_wall_and_the_pad');

// ---- B1: Spring, discovery ---------------------------------------------------------------------
await hop(1053, -1, { at: 14, fn: async () => { await shot('B1_spring_single_jump_up_the_wall'); } });
note('B1 the pad granted Spring and one held jump climbs the 6-tile wall', landed(1100, 1700, R1) && W.grants >= 1, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)} power ${W.power}`);
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
const tChain = W.f;
await hop(1369, -1, { at: 14, fn: async () => { await shot('B2_chain_first_jump'); } });
const ledgeOk = landed(1450, 1625, R2);
await shot('B2_on_the_floating_ledge');
await hop(1680, -1);
const roofOk = landed(1735, 2100, R3);
note('B2 the chain: shed roof -> ledge -> long roof inside one charge', ledgeOk && roofOk && W.power === 2, `${((W.f - tChain) / 60).toFixed(1)} s, ${W.powerTime.toFixed(1)} s of Spring left`);
await shot('B2_long_roof_reached');
await runTo(1860);
note('B2 checkpoint B on the long roof', W.cp === 'cp_b', W.cp);

// ---- C: the underfloor corridor ------------------------------------------------------------------
await shot('C1_electric_strip_ahead');
for (let n = 0; n < 900 && !idleStart('strip'); n++) await frame();
let hpC = W.hp;
ok = await runTo(2030);
note('C1 the electric strip is crossed in its idle phase, unhurt', ok && W.hp === hpC, `x=${W.x.toFixed(0)} hp ${W.hp}`);
await runTo(2200);
await shot('C2_corridor_mouth_crawlers_on_the_ceiling');
ok = await runTo(2680, { gaps: true });
await shot('C2_crawler_dropped_behind');
await waitEvading(() => true, 60);
await shot('C3_pit_and_the_moving_platform');
const L1 = 2768;   // platform centre at its left end; its travel is 160 px
await waitEvading(() => W.mover && W.mover[0] < L1 + 12 && W.mover[0] > L1 - 4, 900);
await dir(1);
for (let n = 0; n < 120 && W.x < 2760; n++) await frame();
await stop();
const rodeFrom = W.x;
await shot('C3_boarding_the_moving_platform');
await waitEvading(() => W.mover[0] > L1 + 160 - 12, 900);
note('C3 the moving platform carries the cat across the 8-tile pit', W.x - rodeFrom > 110 && Math.abs(W.y - R3) < 4, `x ${rodeFrom.toFixed(0)} -> ${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
await shot('C3_platform_at_the_far_end');
await runTo(3010);
ok = await runTo(3250, { gaps: true });
await shot('C4_the_hopper');
note('C4 the hopper stretch is crossed', ok && !W.dead, `x=${W.x.toFixed(0)} hp ${W.hp}`);
await shot('C5_falling_platforms_over_the_second_pit');
ok = await runTo(3560, { gaps: true });
note('C5 three falling platforms carry the cat over the second pit', ok && Math.abs(W.y - R3) < 4 && !W.dead, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)} hp ${W.hp}`);
await runTo(3660);
note('C6 checkpoint C east of the pits', W.cp === 'cp_c', W.cp);
await goTo(3712, 6);
await waitFor(() => W.lift && W.lift[1] < R3 - 80, 12000);   // let it leave, so it is boarded at the start of its pause
await waitFor(() => W.lift[1] >= R3 - 2, 12000);
await dir(1);
for (let n = 0; n < 120 && W.x < 3768; n++) await frame();
await stop();
await shot('C6_on_the_lift');
await waitFor(() => W.lift[1] <= R4 + 6, 9000);
note('C6 the lift carries the cat up through the gallery floor', Math.abs(W.y - R4) < 8, `y=${W.y.toFixed(0)}`);
await shot('C6_lift_at_the_top');
await dir(-1);
for (let n = 0; n < 120 && W.x > 3700; n++) await frame();
await stop(); await ticks(10);
note('C6 steps off west onto the gallery floor', W.floor && Math.abs(W.y - R4) < 4, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);

// ---- D: the conduit -----------------------------------------------------------------------------
note('D the shockwave is still locked before the conduit', W.shock === false);
await shot('D_gallery_head_tunnel_ahead');
const hpD = W.hp;
await dir(-1);
for (let n = 0; !W.shock && n < 900; n++) {
  await frame();
  if (W.x < 3640 && n % 200 === 0) await shot('D_the_sparking_conduit_ahead');
}
if (W.shock) await shot('D_the_flash_shockwave_unlocked');
await stop();
note('D the conduit unlocks the shockwave, harmlessly', W.shock && W.hp === hpD && W.unlocks === 1, `x=${W.x.toFixed(0)} hp ${W.hp}`);
await sleep(500);
await shot('D_augments_flare');
await waitFor(() => lines('conduit') >= 2, 14000);
note('D the conduit monologue (not pain / the air pushes out)', lines('conduit') === 2, `${lines('conduit')} lines`);
await waitFor(() => W.can_move, 4000);
note('D control returns after the hold', W.can_move);

// ---- E1: the crates ----------------------------------------------------------------------------
await goTo(3340, 6);
await shot('E1_crate_stack_blocks_the_corridor');
for (let k = 0; k < 5 && W.crates > 0; k++) {
  await burst(); await ticks(10);
  if (k === 0) await shot('E1_shockwave_breaks_crates');
  await ticks(30); await dir(-1); await ticks(25); await stop(); await ticks(5);
}
note('E1 the double-jump shockwave breaks the crates', W.crates === 0, `${W.crates} left`);
await waitFor(() => lines('shock_first') >= 1, 12000);
note('E1 "a lot of power for a house cat" plays', lines('shock_first') === 1);
await shot('E1_crates_gone_monologue');

// ---- E2: the patrol bot -----------------------------------------------------------------------------
await runTo(3070);
await shot('E2_patrol_bot_in_the_corridor');
for (let n = 0; n < 900 && !(W.patrol && W.patrol[2] === 1); n++) {
  await stop();
  if (W.patrol && Math.abs(W.patrol[0] - W.x) < 70 && W.floor) { await burst(); await ticks(2); } else await frame();
}
note('E2 the shockwave stuns the bot', W.patrol && W.patrol[2] === 1, `bot ${W.patrol && W.patrol[0].toFixed(0)}`);
await shot('E2_bot_stunned');
const hpE = W.hp;
ok = await runTo(2570);
note('E2 and the cat passes it unhurt', ok && W.hp === hpE && !W.dead, `hp ${W.hp}`);

// ---- E3: the switch and the shutter ---------------------------------------------------------------
await goTo(2446, 6);
await dir(-1); await ticks(60); await stop();
note('E3 the shutter is shut: the cat cannot pass', W.shutter === false && W.x > 2424, `x=${W.x.toFixed(0)}`);
await shot('E3_shutter_shut_switch_behind');
await goTo(2552, 6);
for (let k = 0; k < 4 && !W.switch; k++) { await burst(); await ticks(30); }
note('E3 a double jump near the switch opens the shutter', W.switch && W.shutter, `switch ${W.switch}`);
await shot('E3_switch_on_shutter_rolling_up');
ok = await runTo(2386);
note('E3 through the shutter inside the window', ok && W.switch, `x=${W.x.toFixed(0)}`);

// ---- F: the light well ----------------------------------------------------------------------------------
await goTo(2176, 6);
await hold('jump', true); await ticks(30); await hold('jump', false); await ticks(20);
const g1 = W.floor && Math.abs(W.y - 580) < 8;
await dir(1); await hold('jump', true); await ticks(12); await hold('jump', false); await ticks(30); await stop(); await ticks(20);
const g2 = W.floor && Math.abs(W.y - 516) < 8;
await goTo(2250, 6);
await hold('jump', true); await dir(1); await ticks(14); await hold('jump', false); await ticks(40); await stop();
note('F the girder ladder of the light well: three plain jumps of two tiles onto the roof', g1 && g2 && W.floor && Math.abs(W.y - R5) < 6 && W.x > 2272 && W.power === 0, `g1 ${g1} g2 ${g2} x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
await shot('F_on_the_roof_the_city_below');
await runTo(2360);
note('F checkpoint on the roof', W.cp === 'cp_roof', W.cp);

// ---- G1: the cracked wall, the turret, the laser bot -------------------------------------------------
await waitFor(() => lines('stacks_crack') >= 1, 14000);
await shot('G1_the_pump_house_cracked_wall');
await goTo(2386, 4);
for (let k = 0; k < 4 && W.crack; k++) { await burst(); await ticks(40); }
note('G1 the shockwave breaks the cracked wall', !W.crack);
await shot('G1_crawlspace_open');
await hold('down', true); await goTo(2540, 6); await hold('down', false); await ticks(10);
note('G1 the crawlspace holds the toy mouse', W.got.mouse);
await shot('G1_in_the_crawlspace');
await goTo(2400, 8);
await hold('jump', true); await dir(1); await ticks(24); await hold('jump', false); await ticks(20);
await runTo(2558);
for (let n = 0; n < 600 && !W.turretStun; n++) {
  await stop();
  if (Math.abs(2608 - W.x) < 62 && W.floor) { await burst(); await ticks(2); } else await frame();
}
note('G1 the turret on the pump house is stunned by the shockwave', W.turretStun === true, `x=${W.x.toFixed(0)} hp ${W.hp}`);
await shot('G1_turret_stunned');
await runTo(2700);
for (let n = 0; n < 900 && !W.rbotStun; n++) {
  await stop();
  const rb = (W.bots || []).find(b => b[1] > R5 - 20 && b[1] < R5 + 4 && b[0] > 2700 && b[0] < 2960);
  if (rb && Math.abs(rb[0] - W.x) < 58 && W.floor) { await burst(); await ticks(2); }
  else if (rb && rb[0] - W.x > 100) { await dir(1); await frame(); }
  else await frame();
}
note('G1 the laser patrol bot is stunned by the shockwave', W.rbotStun === true, `hp ${W.hp}`);
await shot('G1_laser_bot_stunned');
await runTo(2900);

// ---- G2: the barrel chain and the sealed door --------------------------------------------------------------
await waitFor(() => lines('stacks_barrels') >= 1, 14000);
await shot('G2_barrels_before_the_sealed_hatch');
const hpG = W.hp;
await goTo(2900, 6);
await burst();
await shot('G2_the_fuse_is_lit');
await runTo(2760);
await waitFor(() => !W.door, 9000);
note('G2 the chain reaction blows the sealed door open, the cat unhurt', !W.door && W.hp === hpG, `hp ${W.hp}`);
await shot('G2_the_door_blown_open');

// ---- H: the vent tower -------------------------------------------------------------------------------------
await runTo(3108);
await ticks(10);
await shot('H1_inside_the_tower_pad_and_pillar');
await hop(3165, -1, { at: 14, fn: async () => { await shot('H1_spring_up_the_pillar'); } });
note('H1 the pad inside the tower lifts the cat onto the pillar', landed(3208, 3350, R6), `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
await shot('H1_on_the_pillar_steam_ahead');
if (W.x < 3262) { await goTo(3250, 6); await waitIdle('steam'); }
await goTo(3328, 6);
await waitFor(() => W.power === 0, 14000);
await hold('jump', true); await ticks(30); await hold('jump', false); await ticks(25);
const onFp = Math.abs(W.y - 192) < 10;
await shot('H2_on_the_falling_platform');
await hold('jump', true); await ticks(30); await hold('jump', false); await ticks(25);
note('H2 two plain jumps (falling platform, then the crane deck)', onFp && W.floor && Math.abs(W.y - 132) < 8, `on platform ${onFp}, now y=${W.y.toFixed(0)}`);
await shot('H3_the_crane_deck_city_lights');
await waitFor(() => lines('stacks_vent_top') >= 1, 14000);
await waitIdle('flame');
ok = await runTo(3170);
await goTo(3120, 6); await ticks(10);
await waitFor(() => W.got.memory && W.got.bone, 4000);
note('H3 the golden fish bone and the memory fragment', W.got.bone && W.got.memory, `bone ${W.got.bone} memory ${W.got.memory}`);
await shot('H3_memory_fragment');
await waitFor(() => lines('memory_stacks') >= 2 || !W.speaking, 20000);
await waitFor(() => !W.speaking, 15000);
await waitIdle('flame');
await runTo(3600);
await dir(1);
for (let n = 0; n < 400 && !(W.floor && W.y > 400); n++) await frame();
await stop();
note('H4 off the end of the skywalk the cat drops ten tiles onto the roof', W.floor && Math.abs(W.y - R5) < 6, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)} hp ${W.hp}`);
await shot('H4_back_on_the_roof');

// ---- I: the machine bay, the mirror bot --------------------------------------------------------------------
await runTo(3776);
note('I the loader bot sleeps until the cat is near', W.mirror && W.mirror[2] === false);
await dir(1);
for (let n = 0; n < 200 && !(W.mirror && W.mirror[2]); n++) await frame();
await stop();
note('I it wakes as the augmented cat steps onto the catwalk', W.mirror && W.mirror[2], `cat ${W.x.toFixed(0)} bot ${W.mirror && W.mirror[0].toFixed(0)}`);
await shot('I_loader_bot_wakes_below_the_catwalk');
note('I checkpoint at the bay mouth', W.cp === 'cp_bay', W.cp);
const bx0 = W.mirror[0], cx0 = W.x;
await runTo(cx0 + 200);
await ticks(30);
note('I the bot mirrors the steps: same direction, same distance', Math.abs((W.mirror[0] - bx0) - (W.x - cx0)) < 0.1 * (W.x - cx0), `cat ${(W.x - cx0).toFixed(0)} px, bot ${(W.mirror[0] - bx0).toFixed(0)} px`);
await waitFor(() => lines('mirror_bot') >= 2, 14000);
note('I the mirror monologue plays', lines('mirror_bot') === 2);
await shot('I_the_bot_copies_every_step');
await dir(-1); for (let n = 0; n < 200 && W.x > 3830; n++) await frame(); await stop(); await ticks(20);
note('I walking back brings the bot back and the shutter stays shut', W.plate === false && W.bayShutter === false);
await dir(1);
let plateShot = false;
for (let n = 0; n < 1500 && !W.plate; n++) { await frame(); if (W.mirror[0] > 4400 && !plateShot) { plateShot = true; await shot('I_bot_nearing_the_plate'); } }
await stop();
note('I the bot ends on the plate at the end of its track', W.plate === true, `cat ${W.x.toFixed(0)} bot ${W.mirror[0].toFixed(0)}`);
await sleep(700);
await shot('I_plate_held_shutter_open');
note('I the shutter at the end of the catwalk is open', W.bayShutter === true);
ok = await runTo(4747);
note('I the cat walks on through, the plate keeps holding', ok && W.plate && W.bayShutter, `x=${W.x.toFixed(0)}`);

// ---- J: the exit tower, the exit pit ---------------------------------------------------------------------------
await runTo(4780); await ticks(10);
note('J checkpoint at the gate', W.cp === 'cp_gate', W.cp);
await shot('J_the_tower_and_its_pad');
await hop(4829, 6, { at: 14, fn: async () => { await shot('J_spring_up_the_tower'); } });
note('J Spring climbs the exit tower', landed(4872, 5000, R6), `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
await shot('J_tower_top_the_pit_ahead');
await goTo(5010, 6);
ok = await runTo(5340, { gaps: true });
await ticks(30);
note('J two falling platforms carry the cat over the exit pit', ok && W.floor && Math.abs(W.y - R6) < 4, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
await shot('J_exit_roof_suburb_lights_in_the_distance');
await waitFor(() => lines('stacks_exit') >= 2, 14000);
note('J exit monologue (past the fences, little lights in windows)', lines('stacks_exit') === 2);
note('J only Spring was granted, no violations', W.violations === 0, `${W.grants} grants`);

// ---- K: the exit -----------------------------------------------------------------------------------------
await dir(1);
for (let n = 0; W.scene.endsWith('room3.tscn') && n < 900; n++) { try { await frame(); } catch { break; }  if (n === 40) await shot('K_exit_fade'); }
await stop();
await throughMap('K', 'stacks', 'perimeter', 'room4.tscn');
await sleep(1800); await poll();
note('K exit leads to Room 4', W.scene.endsWith('room4.tscn'), W.scene);
note('K the shockwave and the mind carried over, saved', W.save && W.mind && W.shock, `power ${W.power}`);
await shot('K_room4_arrival');
note('fps: the capped default rate is held on the yard', fpsA.fps >= 40, JSON.stringify(fpsA));

const failed = results.filter(r => !r[1]);
console.log(`== ${results.length} checks, ${failed.length ? failed.length + ' FAILED' : 'ALL PASS'}; console errors: ${consoleErrors.length}`);
consoleErrors.slice(0, 20).forEach(e => console.log('  [console error]', e.slice(0, 300)));
await browser.close();
server.close();
process.exit(failed.length || consoleErrors.length ? 1 : 0);
