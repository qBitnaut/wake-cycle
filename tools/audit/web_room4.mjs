// Plays Room 4, "The Perimeter" (the tall, multi-tier level), on the web export with real keyboard
// events (Playwright + system Chromium), at the default capped frame rate: arrival, the three Phase
// steps, the three Impact steps down through the floors, the bunker, the cistern (relay 2, acid, a
// lift), the shaft's ladder, the tower (relay 1), the vault and the HeavyMech (relay 3), the armoury
// secret, the scanner, the credential, the gate and the dawn-lit exit, with a screenshot at every beat
// and a count of console errors. Starts through the debug deep link
// index.html?start=room4 (Room1 _web_start_override: the cat arrives as Room 3
// leaves it, mind awake and the shockwave unlocked). Reads the state Room 4
// publishes in window.__wake every physics frame. The trials (a plain cat is
// hurt, the windows, the soft-lock nets, every relay needed) live in
// room4_playthrough.gd; this run is the route end to end by keyboard, with a
// teleport only to stage a beat that has just been shown to work.
//
//   node tools/audit/web_room4.mjs <export_dir> <out_dir> [width height] [--gpu=swiftshader] [--dpr=1.25]
// <export_dir> must be a DEBUG export (tools/export_web.sh debug <dir>): the hooks and deep links
// this audit uses do not exist in a release export.
//
// Needs the playwright package (PW_DIR env, default: the mise npm-playwright
// install) and /usr/bin/chromium. By default it asks Chromium for the real GPU
// through ANGLE/Vulkan; pass --gpu=swiftshader for the software rasteriser.
// Serves the export on its own port (PORT env, else the first free one from
// 8800 to 8899).
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
let port = process.env.PORT ? +process.env.PORT : 8800 + (process.pid % 100);
for (let tries = 0; tries < 100; tries++) {
  try {
    await new Promise((res, rej) => { server.once('error', rej); server.listen(port, '127.0.0.1', () => { server.off('error', rej); res(); }); });
    break;
  } catch (e) {
    port = 8800 + ((port - 8800 + 1) % 100);
  }
}
const url = `http://127.0.0.1:${port}/index.html?start=room4`;
console.log('[server]', url);

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
const consoleAll = [];
page.on('console', m => { consoleAll.push(m.type() + ': ' + m.text()); if (consoleAll.length > 400) consoleAll.shift(); if (m.type() === 'error') consoleErrors.push(m.text()); });
page.on('pageerror', e => { consoleErrors.push('pageerror: ' + e.message); if (process.env.STACK) console.log('[pageerror stack]', e.stack); });

const sleep = ms => new Promise(r => setTimeout(r, ms));
let shotN = 0;
async function shot(name) {
  consoleAll.push('SHOT ' + name);
  await page.screenshot({ path: `${outdir}/${String(++shotN).padStart(2, '0')}_${name}.png` }); }
const results = [];
function note(name, ok, detail = '') {
  results.push([name, ok, detail]);
  consoleAll.push('NOTE ' + name.slice(0, 60));
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name.padEnd(62)} ${detail}`);
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
for (let i = 0; i < 400 && !(W.scene.endsWith('room4.tscn') && W.f > 0); i++) { await sleep(50); await poll(); }

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
  const f = W.f;
  for (let i = 0; i < 4000; i++) { await poll(); if (W.f > f) return W; await sleep(1); }
  console.log('[stalled] last console lines:', JSON.stringify(consoleAll.filter((l, i, a) => !(l.startsWith('warning: WebGL') && a[i - 1] && a[i - 1].startsWith('warning: WebGL'))).slice(-(+process.env.TAIL || 30)), null, 0));
  console.log('[stalled] console errors:', JSON.stringify(consoleErrors.slice(-5)), 'last state', JSON.stringify({ x: W.x, y: W.y, f: W.f, scene: W.scene }));
  throw new Error('physics stalled');
}
async function ticks(n) { for (let i = 0; i < n; i++) await frame(); }
async function tap(a, n = 3) { await hold(a, true); await ticks(n); await hold(a, false); }
const cx = c => c * 32 + 16;
async function goTo(x, tol = 6, limit = 1500) {
  let n = 0;
  while (Math.abs(W.x - x) > tol && n++ < limit) { await dir(Math.sign(x - W.x)); await frame(); }
  await dir(0); await ticks(6); return n < limit;
}
const SURF = 384, ROOF = 192, L1 = 544, L2 = 704, L3 = 864, L4 = 1120;
async function teleport(x, y = SURF) {
  await page.evaluate(([a, b]) => window.wakeTeleport(a, b), [x, y]);
  await ticks(24);
}
// Hold right, hopping walls and walkers with a held jump of 22 frames. `each` runs every frame.
async function runTo(target, o = {}) {
  let n = 0;
  while (W.x < target && n++ < (o.limit || 2400) && !W.dead) {
    await dir(1);
    if (W.floor) {
      const botAhead = (W.bots || []).some(b => { const dx = b[0] - W.x, dy = b[1] - W.y; return dx > 40 && dx < 92 && Math.abs(dy) < 30 && b[2] === 0; });
      if (W.wallAhead || botAhead) {
        await hold('jump', true);
        for (let i = 0; i < 22; i++) { if (o.each) await o.each(); await frame(); n++; }
        await hold('jump', false);
        for (let k = 0; k < 90 && !W.floor; k++) { if (o.each) await o.each(); await frame(); n++; }
        continue;
      }
    }
    if (o.each) await o.each();
    await frame();
  }
  await stop();
  return W.x >= target;
}
// Run right; Shift when a fence (in the cat's band) or any guard drone is 34-46 px ahead.
async function phaseRun(target, o = {}) {
  let dashes = 0, last = -99, n = 0;
  const hp0 = W.hp;
  while (W.x < target && n++ < 2400 && !W.dead) {
    await dir(1);
    let dn = 1e9;
    for (const [ox, oy, k] of W.obs || []) {
      if (k === 0 && Math.abs(oy - W.y) > 40) continue;
      const dx = ox - W.x;
      if (dx > 0 && dx < dn) dn = dx;
    }
    if (dn >= 30 && dn <= 62 && W.f - last > 30 && W.power === 3) {
      await hold('dash', true); dashes++; last = W.f;
      if (o.onDash) o.onDash(dashes);
    } else if (W.f - last >= 2) await hold('dash', false);
    await frame();
  }
  await stop();
  return { dashes, hpLost: hp0 - W.hp, reached: W.x >= target };
}
const waitFor = async (cond, ms = 8000) => { for (let t = 0; t < ms; t += 20) { await poll(); if (cond()) return true; await sleep(20); } return false; };
const lines = id => W.monoIds.filter(i => i === id).length;
async function takePad(px, power, from = 36) {
  for (let pass = 0; pass < 4; pass++) {
    await goTo(px - from, 6);
    await dir(1);
    for (let n = 0; n < 150 && !(n >= 24 && W.power === power); n++) await frame();
    await stop();
    if (W.power === power) break;
    await ticks(60);
  }
  return W.power === power;
}
// After a pound: wait until the cat stands on the floor at y (the hatch breaks, the fall lands).
async function waitFall(y, ms = 6000) {
  await waitFor(() => W.floor && Math.abs(W.y - y) < 6, ms);
  await ticks(6);
}
// A hop: walk to lx, jump (held 22 frames) holding direction d (0: straight up); true when it stands at ty.
async function hop(lx, d, ty, hf = 22) {
  await goTo(lx, 4);
  await dir(d);
  await hold('jump', true);
  for (let i = 0; i < hf; i++) await frame();
  await hold('jump', false);
  for (let k = 0; k < 120 && (k < 8 || !W.floor); k++) await frame();
  await stop(); await ticks(4);
  return Math.abs(W.y - ty) < 6;
}
// Walk right to target, waiting while a timed hazard ahead (crusher, spikes, electric floor) is warning or live.
async function hazardRun(target, limit = 3000) {
  for (let n = 0; W.x < target && n < limit && !W.dead; n++) {
    let wait = false;
    for (const [hx, hy, ph, pt, idle, wt] of W.haz || []) {
      if (Math.abs(hy - W.y) > 150) continue;
      const half = wt * 16, dx = hx - W.x;
      if (dx > half + 4 && dx < half + 60 && !(ph === 0 && pt < idle - 1.0)) wait = true;
    }
    if (wait) await stop(); else await dir(1);
    await frame();
  }
  await stop();
  return W.x >= target;
}
// Ride a lift: wait for it at boardY, step on, wait for topY, step off towards exitX.
async function ride(lift, boardX, boardY, topY, exitX) {
  if (!await waitFor(() => W[lift] && Math.abs(W[lift][1] - boardY) < 4 && Math.abs(W[lift][0] - boardX) < 40, 30000)) return false;
  await goTo(W[lift][0], 6);
  if (!await waitFor(() => W[lift] && Math.abs(W[lift][1] - topY) < 4 && Math.abs(W.y - topY) < 8, 30000)) return false;
  await dir(Math.sign(exitX - W.x));
  await waitFor(() => Math.abs(W.x - exitX) < 12 || (W.x - exitX) * Math.sign(exitX - boardX) > 0, 4000);
  await stop(); await ticks(20);
  return Math.abs(W.y - topY) < 6;
}
// A held jump, then Down in the air: the ground pound.
async function poundJump(waitFrames = 5) {
  await hold('jump', true);
  await ticks(waitFrames);
  await tap('down', 3);
  await hold('jump', false);
}
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
const lum = t => t[0] * 0.3 + t[1] * 0.59 + t[2] * 0.11;
const fps = [];


const SECTIONS = (process.env.SECTIONS || '').split(',').filter(Boolean);   // e.g. SECTIONS=P3,I1 runs only those (each stages itself)
const sec = k => SECTIONS.length === 0 || SECTIONS.includes(k);
let lum0 = 0, lumMid = 0, ok = false, res = null;
// ---- A: arrival -------------------------------------------------------------------
if (sec('A')) {
await sleep(1500); await poll();
note('A arrives in Room 4 through the deep link: start, control, HUD', W.scene.endsWith('room4.tscn') && Math.abs(W.x - 112) < 10 && W.can_move && W.hud, `x=${W.x.toFixed(0)}`);
note('A mind awake, shockwave unlocked, no power, auto-saved', W.mind && W.shock && W.power === 0 && W.save);
lum0 = lum(W.tint);
await shot('A_arrival');
await waitFor(() => lines('perimeter_arrival') >= 2, 14000);
note('A arrival monologue (fences, lasers / authorised units)', lines('perimeter_arrival') === 2, `${lines('perimeter_arrival')} lines`);
fps.push(await measureFps('the arrival yard in the rain'));
const hp0 = W.hp;
ok = await runTo(cx(30));
note('A crossed the yard past the walker', ok && W.hp === hp0 && !W.dead, `x=${W.x.toFixed(0)} hp ${W.hp}`);
// The first guard tower's interior: three girders and the roof, plain hops, a bell on top.
await teleport(cx(11));
{
  const a = await hop(cx(12), 0, 320), b = await hop(14 * 32 - 36, 1, 256), c = await hop(14 * 32 + 36, -1, 192), d = await hop(cx(12), 0, 128);
  note('A2 up the guard tower\'s interior: girder, girder, girder, roof (plain hops)', a && b && c && d, `${a} ${b} ${c} ${d} y=${W.y.toFixed(0)}`);
  await shot('A2_guard_tower_interior_roof');
}

}
// ---- P1: Phase, discovery -----------------------------------------------------------
if (sec('P1')) {
await teleport(cx(40));
await shot('P1_gatehouse_corridor_sign_pad_fence');
const hpP = W.hp;
await dir(1);
for (let n = 0; n < 400 && W.hp === hpP; n++) await frame();
await stop(); await ticks(30);
note('P1 without Phase the laser hurts and pushes the cat back', W.hp === hpP - 1 && W.x < 1520, `hp ${hpP} -> ${W.hp}, x=${W.x.toFixed(0)}`);
await shot('P1_laser_hurts_without_phase');
await ticks(100);
await teleport(cx(33));
ok = await takePad(1168, 3);
note('P1 the Phase pad grants Phase (a real walk over it)', ok && W.power === 3, `power ${W.power}, ${W.powerTime.toFixed(1)} s`);
await sleep(700);
await shot('P1_phase_pad_discovery_cyan_emitters');
let dashShot = false;
res = await phaseRun(cx(52), { onDash: async () => { if (!dashShot) { dashShot = true; await shot('P1_laser_dash_through'); } } });
note('P1 one dash goes through the fence: unhurt', res.reached && res.hpLost === 0 && res.dashes === 1, JSON.stringify(res));
await waitFor(() => lines('phase_first') >= 2, 14000);
note('P1 first-use monologue (through it / cyan)', lines('phase_first') === 2, `${lines('phase_first')} lines`);

}
// ---- P2: Phase, use -----------------------------------------------------------------
if (sec('P2')) {
await teleport(cx(55));
await ticks(10);
note('P2 checkpoint A', W.cp === 'cp_a', W.cp);
let shot2 = false;
let tries = 0;
do {
  tries++;
  await teleport(cx(55));
  await ticks(10);
  await takePad(cx(60), 3);
  res = await phaseRun(cx(108), { onDash: async n => { if (n === 3 && !shot2) { shot2 = true; await shot('P2_laser_dash_series_and_drones'); } } });
} while (!(res.reached && res.hpLost === 0) && tries < 3);
note('P2 the corridor by keyboard: three fences and two drones, unhurt', res.reached && res.hpLost === 0 && res.dashes >= 5, JSON.stringify(res) + `, ${tries} tries`);
fps.push(await measureFps('the laser corridor'));
await teleport(cx(104.5));
await shot('P2_turret_beam_telegraph');
let seenFire = false;
for (let n = 0; n < 900 && !(seenFire && W.turret === 0); n++) { await frame(); if (W.turret === 2) seenFire = true; }
const hpT = W.hp;
await dir(1);
for (let n = 0; W.x < cx(114) && n < 400; n++) await frame();
await stop();
note('P2 the turret is dodged by timing (cross right after a shot)', W.hp === hpT && W.x >= cx(114), `hp ${W.hp}`);

}
// ---- P3: Phase with Spring ----------------------------------------------------------------
if (sec('P3')) {
if (SECTIONS.length) await teleport(cx(112));
await goTo(cx(112), 8);
await shot('P3_base_hint_pad_and_6_row_roof');
{
ok = await takePad(cx(115), 2, 3 * 32);
await sleep(700);
note('P3 the Spring pad grants Spring', W.power === 2, `power ${W.power}`);
await dir(1);
for (let n = 0; W.x < cx(116) && n < 600; n++) await frame();
await hold('jump', true);
for (let air = 1; air < 70; air++) {
  await frame();
  if (air === 4) await hold('jump', false);
  if (air === 12) await hold('jump', true);
  if (air === 16) await hold('jump', false);
  if ([3, 14, 28, 40].includes(air)) await shot(`P3_taptap_strip_air${String(air).padStart(2, '0')}`);
}
await stop(); await ticks(30);
note('P3 Spring and tap-tap (two short presses, a real double jump): up onto the guardhouse roof (6 rows)', Math.abs(W.y - ROOF) < 4 && W.x > cx(118), `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
await shot('P3_on_the_roof');
}
{
await takePad(cx(120), 3, 36);
res = await phaseRun(cx(133));
}
note('P3 Phase through the roof fence (Spring, then Phase)', res.reached && res.hpLost === 0, JSON.stringify(res));
{
// The optional catwalk: a plain double jump across the gap, a bell, back down.
await teleport(cx(121), ROOF);
await dir(-1);
for (let n = 0; W.x > 118 * 32 + 10 && n < 200; n++) await frame();
await hold('jump', true); await ticks(26); await hold('jump', false); await ticks(1); await hold('jump', true);
for (let n = 0; n < 120 && !(W.floor && Math.abs(W.y - ROOF) < 6 && W.x < 113 * 32 + 20); n++) await frame();
await hold('jump', false); await stop(); await ticks(10);
// Step back out of the sentry's range and let the dust settle before the check.
await dir(1); for (let n = 0; W.x < 112 * 32 + 8 && n < 60; n++) await frame();
await stop(); await sleep(2500);
note('P3b the catwalk (the optional harder route): a plain double jump across the 5-tile gap', Math.abs(W.y - ROOF) < 6 && W.x < 113 * 32 + 20 && W.x > 100 * 32, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
await shot('P3b_catwalk_armed_with_robots');
}
await teleport(cx(133), ROOF);
ok = await runTo(cx(139));
await ticks(20);
note('P3 off the roof to checkpoint B', ok && W.cp === 'cp_b', W.cp);

}
// ---- I1: Impact, discovery ------------------------------------------------------------------
if (sec('I1')) {
await shot('I1_impact_placard_ledge_hatch');
ok = await runTo(cx(143.4));
await ticks(20);
note('I1 up onto the ledge, the Impact pad grants Impact', ok && W.power === 4, `power ${W.power}`);
await sleep(600);
await shot('I1_impact_pad_violet');
await dir(1);
let pressed = false;
for (let n = 0; n < 200 && W.y < 400; n++) {
  await frame();
  if (!pressed && !W.floor && W.vy > 40) { pressed = true; await tap('down', 3); }
}
await stop();
let impactShot = false;
for (let n = 0; n < 60; n++) { await frame(); if (!impactShot && W.y > 400) { impactShot = true; await shot('I1_impact_break_the_floor_gives'); } }
await ticks(30);
note('I1 stepping off and pressing Down breaks the cracked floor: down to the service duct', pressed && Math.abs(W.y - L1) < 6, `y=${W.y.toFixed(0)}`);
await waitFor(() => lines('impact_first') >= 2, 14000);
note('I1 first-use monologue (heavy / violet)', lines('impact_first') === 2, `${lines('impact_first')} lines`);
await shot('I1_service_duct_below');

}
// ---- I2: the armoured bot, the chained hatch -------------------------------------------------------
if (sec('I2')) {
await goTo(cx(152), 6);
await ticks(10);
note('I2 checkpoint C in the duct', W.cp === 'cp_c', W.cp);
await ticks(200);
ok = await takePad(4976, 4, 36);
await goTo(5035, 3);
await shot('I2_armoured_bot_corridor');
const botX = () => (W.bots || []).filter(b => Math.abs(b[1] - L1) < 6).map(b => b[0])[0];
for (let n = 0; n < 1500 && !(botX() < 5095 && botX() > 5076); n++) await frame();
await poundJump(5);
await ticks(30);
const botSt = (W.bots || []).filter(b => Math.abs(b[1] - L1) < 8).map(b => b[2])[0];
note('I2 the ground pound stuns the armoured bot', botSt === 1, `state ${botSt}`);
await shot('I2_armoured_bot_stunned');
const hpB = W.hp;
ok = await runTo(cx(168) + 8);
note('I2 through the corridor past the stunned bot, unhurt', ok && W.hp === hpB, `x=${W.x.toFixed(0)}`);
await dir(1);
for (let n = 0; W.x < cx(170.2) && n < 600; n++) await frame();
await poundJump(5);
await stop();
await ticks(80);
note('I2 the chained hatch drops the cat to the lower duct', Math.abs(W.y - L2) < 6, `y=${W.y.toFixed(0)}`);

}
// ---- I3: shield, fence, last hatch ----------------------------------------------------------------
if (sec('I3')) {
await goTo(cx(166), 6);
await ticks(10);
note('I3 checkpoint D', W.cp === 'cp_d', W.cp);
await goTo(cx(172), 6);
await tap('jump', 3);
await ticks(14);
await tap('jump', 3);
await ticks(30);
note('I3 the double-jump shockwave breaks the shield wall', W.shields[0] === false, JSON.stringify(W.shields));
await shot('I3_shield_wall_broken');
await takePad(cx(177), 3, 36);
res = await phaseRun(cx(183.5));
note('I3 Phase through the duct fence', res.reached && res.hpLost === 0, JSON.stringify(res));
await ticks(200);
await takePad(cx(184), 4, 36);
await dir(1);
for (let n = 0; W.x < cx(188) && n < 600; n++) await frame();
await poundJump(5);
await stop();
await ticks(80);
note('I3 the last hatch: down to the bunker', Math.abs(W.y - L3) < 6, `y=${W.y.toFixed(0)}`);
await goTo(cx(190), 6);
await ticks(10);
note('I3 checkpoint E in the bunker', W.cp === 'cp_e', W.cp);

}
// ---- Bunker: the camera corridor and the press ----------------------------------------------------
if (sec('B')) {
await teleport(cx(200), L3);
await shot('B_camera_corridor');
for (let n = 0; n < 1200 && !(W.camU3 >= 1); n++) await frame();
note('B standing in the camera\'s view: it spots the cat and the alarm wakes the turret', W.camU3 >= 1 && W.turU3 > 0, `alarms ${W.camU3} alert ${W.turU3}`);
await shot('B_alarm_turret_wakes');
await ticks(400);
await teleport(cx(210), L3);
ok = await hazardRun(cx(224));
note('B the press (electric floor, crushers, spikes) crossed by timing', ok && !W.dead, `x=${W.x.toFixed(0)} hp ${W.hp}`);
await shot('B_the_press');

}
// ---- R2: the flooded cistern ------------------------------------------------------------------------
if (sec('R2')) {
await teleport(cx(188), L3);
await takePad(cx(192), 4, 36);
await dir(1);
for (let n = 0; W.x < cx(193.4) && n < 600; n++) await frame();
await poundJump(7);
await stop();
await waitFall(L4);
note('R2 the pound breaks the cistern hatch: down into the dry hall', Math.abs(W.y - L4) < 6, `y=${W.y.toFixed(0)}`);
await waitFor(() => lines('perimeter_cistern') >= 1, 14000);
note('R2 the hint plays (flooded, keep to the stones)', lines('perimeter_cistern') === 1);
await goTo(cx(191), 4);
await ticks(10);
note('R2 checkpoint G in the cistern', W.cp === 'cp_g', W.cp);
await teleport(cx(201), L4);
await shot('R2_cistern_hall_pools_ahead');
const hpC = W.hp;
const s1 = await hop(205 * 32 - 14, 1, 34 * 32), s2 = await hop(211 * 32 - 30, 1, 34 * 32);
note('R2 hall -> stone -> stone over the acid by plain hops (at most a pip lost)', s1 && s2 && W.hp >= hpC - 1, `${s1} ${s2} hp ${W.hp}`);
await shot('R2_over_the_acid');
await goTo(217 * 32 - 30, 4);
await dir(1); await hold('jump', true); await ticks(18); await hold('jump', false);
for (let n = 0; n < 90 && !W.floor; n++) await frame();
await dir(1);
for (let n = 0; n < 60 && W.x < 220 * 32 - 24; n++) await frame();
await hold('jump', true); await ticks(18); await hold('jump', false);
for (let n = 0; n < 90 && !W.floor; n++) await frame();
await stop(); await ticks(10);
note('R2 the falling platform bridges the widest pool (hop on, hop off before it drops)', W.x > 221 * 32 && W.hp >= hpC - 2, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)} hp ${W.hp}`);
await teleport(cx(222), 34 * 32);
ok = await takePad(cx(223), 3, 36);
res = await phaseRun(cx(231.5));
note('R2 the laser tunnel: Phase through two fences with a pad between', ok && res.reached && res.hpLost === 0 && res.dashes === 2, JSON.stringify(res));
await shot('R2_laser_tunnel');
await dir(1);
for (let n = 0; n < 300 && !W.relayLit[1]; n++) await frame();
await stop();
note('R2 the console lights relay 2', W.relayLit[1] === true && W.relays === 1, `relays ${W.relays}`);
await sleep(250);
await shot('R2_relay_lit');
await waitFor(() => W.pans >= 1 && W.cam[0] > 7000 && W.cam[0] > W.x + 800, 8000);
await sleep(400);
await shot('R2_pan_to_the_gatehouse_from_the_cistern');
await waitFor(() => !W.panning && W.can_move, 8000);
ok = await ride('liftA', 235 * 32, L4, L3, 233 * 32);
note('R2 the lift in the chamber carries the cat up to the bunker', ok, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
await shot('R2_lift_arrives_in_the_bunker');

}
// ---- S1: the shaft, a ladder (then the lift is shown) ----------------------------------------------------------
if (sec('S1')) {
{
  await teleport(cx(224), L3);
  const edge = 229 * 32;
  let good = true;
  for (const [i, row] of [25, 23, 21, 19, 17, 15, 13].entries()) {
    const r = i % 2 === 0 ? await hop(edge - 36, 1, row * 32) : await hop(edge + 36, -1, row * 32);
    good = good && r;
    if (i === 3) await shot('S1_shaft_midway');
    if (!r) break;
  }
  note('S1 the ladder of girders: seven plain hops from the bunker to the top girder', good && Math.abs(W.y - 13 * 32) < 6, `y=${W.y.toFixed(0)}`);
  const top = await hop(238 * 32 - 36, 1, SURF);
  note('S1 off the top girder onto the plaza', top && W.x > 238 * 32, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
  await shot('S1_shaft_top');
}
fps.push(await measureFps('the plaza after the shaft'));
await goTo(cx(241), 6);
await ticks(10);
note('F checkpoint F on the plaza', W.cp === 'cp_f', W.cp);
await goTo(cx(243), 4);
await waitFor(() => lines('relays_intro') >= 1, 14000);
note('F the relays intro line plays', lines('relays_intro') === 1);
await shot('F_plaza_three_relays_required');

}
// ---- R1: the tower ---------------------------------------------------------------------------------------------------
if (sec('R1')) {
await teleport(cx(250));
await shot('R1_tower_door_hint');
{
  const a = await hop(cx(254), 0, 320), b = await hop(257 * 32 - 36, 1, 256);
  note('R1 up inside the guard tower by two plain hops to the second girder', a && b, `${a} ${b}`);
  await goTo(cx(257), 6);
  ok = await takePad(cx(258), 2, 36);
  note('R1 the Spring pad on the girder grants Spring', ok && W.power === 2, `power ${W.power}`);
  await hold('jump', true);
  for (let air = 1; air < 60; air++) { await frame(); if (air === 22) await shot('R1_midair_single_spring_jump'); if (air === 45) await hold('jump', false); }
  await hold('jump', false);
  for (let n = 0; n < 120 && !W.floor; n++) await frame();
  await ticks(10);
  note('R1 with Spring one held jump reaches the relay\'s roof (6 rows)', Math.abs(W.y - 64) < 6, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
  await shot('R1_on_the_tower_roof');
  await dir(-1);
  for (let n = 0; n < 300 && !W.relayLit[0]; n++) await frame();
  await stop();
  note('R1 relay 1 lit, the cat held for the camera pan', W.relayLit[0] === true && W.relays === 2, `relays ${W.relays}`);
  await sleep(250);
  await shot('R1_relay_lit_pan_starts');
  await waitFor(() => W.pans >= 2 && W.cam[0] > W.x + 300, 8000);
  await sleep(500);
  await shot('R1_pan_to_the_gatehouse_lamp_two');
  await waitFor(() => !W.panning && W.can_move, 8000);
  note('R1 the camera is back and the cat is free', !W.panning && W.can_move);
  ok = await runTo(cx(266));
  await waitFall(SURF);
  note('R1 the way on goes over the tower: along the relay roof past checkpoint L, down the far side', ok && W.cp === 'cp_l' && Math.abs(W.y - SURF) < 6, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)} cp ${W.cp}`);
}

}
// ---- R3: the vault and the mech ---------------------------------------------------------------------------------------
if (sec('R3')) {
await teleport(cx(270));
ok = await takePad(cx(272), 4, 36);
await dir(1);
for (let n = 0; W.x < cx(276.6) && n < 600; n++) await frame();
await poundJump(7);
await stop();
await waitFall(576);
note('R3 the pound opens the vault hatch: down into the antechamber', Math.abs(W.y - 576) < 6, `y=${W.y.toFixed(0)}`);
await shot('R3_vault_antechamber');
await waitFor(() => lines('perimeter_mech') >= 1, 14000);
await goTo(cx(275), 4);
await ticks(10);
note('R3 checkpoint I before the arena', W.cp === 'cp_i', W.cp);
{
  const t0 = W.f;
  let pounds = 0, lastHp = 3;
  const alive = () => W.mech && !W.mech[2];
  let shotFight = false;
  while (alive() && W.f - t0 < 60 * 120 && !W.dead) {
    const m = W.mech;
    if (W.power !== 4) {
      if (W.x > cx(283)) { await dir(-1); for (let n = 0; n < 120 && W.x > cx(282.4); n++) await frame(); await stop(); }
      await takePad(cx(282), 4, 36);
    } else if (m[5] || m[0] === 3) {
      if (!shotFight) { shotFight = true; await shot('R3_mech_dazed_by_the_wall'); }
      const tx = m[3];
      await dir(Math.sign(tx - W.x));
      for (let n = 0; n < 120 && Math.abs(W.x - tx) > 18 && W.mech && (W.mech[5] || W.mech[0] === 3); n++) await frame();
      await stop();
      if (W.mech && (W.mech[5] || W.mech[0] === 3)) {
        const before = W.mech[1];
        await hold('jump', true); await ticks(6); await hold('jump', false); await ticks(2);
        await tap('down', 3); await ticks(30);
        if (!W.mech || W.mech[1] < before) pounds++;
      }
    } else {
      if (W.x > cx(283) - 4) { await dir(-1); for (let n = 0; n < 120 && W.x > cx(282.4); n++) await frame(); await stop(); }
      await ticks(3);
    }
  }
  note('R3 the HeavyMech is beaten by pounds (each stuns it, the wall slam dazes it)', !alive() && pounds >= 1 && !W.dead, `${pounds} pound hits, ${((W.f - t0) / 60).toFixed(1)} s, hp ${W.hp}`);
  await shot('R3_mech_defeated');
}
await ticks(30);
await dir(1);
for (let n = 0; n < 600 && !W.relayLit[2]; n++) await frame();
await stop();
note('R3 the console behind the mech lights relay 3', W.relayLit[2] === true && W.relays === 3, `relays ${W.relays}`);
await sleep(250);
await shot('R3_relay_lit');
await waitFor(() => W.pans >= 3 && W.cam[0] > W.x + 300, 8000);
await sleep(400);
await shot('R3_pan_to_the_gatehouse_all_three_lamps');
await waitFor(() => !W.panning && W.can_move, 8000);
await waitFor(() => lines('relay_done') >= 3, 12000);
note('R3 "One down." / "Two." / "That\'s all of them!"', lines('relay_done') === 3);
ok = await runTo(cx(311));
note('R3 out of the vault by the stair', ok && Math.abs(W.y - SURF) < 6, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
fps.push(await measureFps('the plaza by the vault exit'));

}
// ---- S3: the armoury (a blast-only floor) ---------------------------------------------------------------------------------
if (sec('S3')) {
await teleport(cx(311));
await dir(1);
for (let n = 0; n < 200 && W.x < cx(314.4); n++) await frame();
await stop();
const hpA = W.hp;
for (let n = 0; n < 900 && W.barrel; n++) await frame();
await ticks(30);
note('S3 the turret\'s bolt sets off the barrel: the blast breaks the floor, the cat 4 tiles back unhurt', W.barrel === false && W.sealArmoury === false && W.hp === hpA, `hp ${hpA} -> ${W.hp}`);
await shot('S3_armoury_pit_open');
await dir(1);
for (let n = 0; n < 200 && W.y < 500; n++) await frame();
await stop(); await ticks(30);
ok = await runTo(cx(323));
await ticks(20);
note('S3 the golden fish bone in the armoury', W.bone === true, `gems ${W.gems}`);
await shot('S3_armoury_bone');
ok = await runTo(cx(336));
note('S3 out by the stair, east of the turret', ok && Math.abs(W.y - SURF) < 6, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);

}
// ---- scanner, credential, gate -----------------------------------------------------------------------------------
if (sec('S')) {
lumMid = lum(W.tint);
if (SECTIONS.length) await teleport(cx(333));
ok = await goTo(cx(335), 6);
await shot('S_scanner_ready_three_lamps');
await dir(1);
for (let n = 0; n < 300 && W.scanMode !== 2; n++) await frame();
await stop();
note('S walking in starts the scan and holds the cat', W.scanning && !W.can_move, `mode ${W.scanMode}`);
await waitFor(() => lines('scanner') >= 1, 8000);
await sleep(900);
await poll();
note('S sound: the scanner\'s hum is audible during the scan (distance-faded loop)', W.loops && W.loops.positional >= 1, JSON.stringify(W.loops));
await shot('S_scanner_sweeping_the_cat');
await waitFor(() => W.scanMode === 3, 8000);
await sleep(300);
note('S SUPERVISOR CREDENTIAL ACCEPTED on the screen', W.scanMode === 3 && W.scanText[0] === 'SUPERVISOR CREDENTIAL ACCEPTED', JSON.stringify(W.scanText));
await sleep(1500); await poll();
{ const c = soundClean(W.loops, await audioLoops(page));
  // (By here the route has fired a mech's explosion, relay chimes and lift motors: the browser still has their tails and
  // a few distant kit loops sounding, so the browser-side count is bounded, not exact; the tree must be clean.)
  note('S sound: the scanner hum stopped when the scan ended (no audible positional loop, no orphan)', W.loops.positional === 0 && W.loops.orphans === 0 && (await audioLoops(page)).audible <= 14, c.detail); }
await shot('S_credential_accepted');
note('S the gate is still shut at the moment of acceptance', W.gateLift < 0.05 && !W.gateOpen);
await waitFor(() => W.gateLift > 0.4, 12000);
await shot('S_gate_opening');
await waitFor(() => W.gateOpen, 12000);
note('S the gate grinds open', W.gateOpen === true, `lift ${W.gateLift.toFixed(2)}`);
await waitFor(() => W.can_move && !W.scanning, 12000);
await waitFor(() => lines('credential') >= 3, 14000);
note('S credential monologue (accepted / one of them / maybe I am)', lines('credential') === 3);
note('S the sunrise begins', W.dawn > 0.05, `dawn ${W.dawn.toFixed(2)}`);
fps.push(await measureFps('the gate open, sunrise'));

}
// ---- E: the road and the exit -----------------------------------------------------------------------------------------
if (sec('E')) {
await shot('E_gate_open_dawn_road_ahead');
if (SECTIONS.length === 1) await teleport(cx(352));
ok = await runTo(cx(361));
await ticks(20);
note('E through the open gate to checkpoint J', ok && W.cp === 'cp_j', W.cp);
await waitFor(() => lines('perimeter_exit') >= 2, 14000);
note('E exit lines (the rain is stopping / almost home)', lines('perimeter_exit') === 2);
await sleep(3500); await poll();
const lumEnd = lum(W.tint);
note('E the sky lightened with progress: night -> pre-dawn -> sunrise', lum0 < lumMid && lumMid < lumEnd && lumEnd - lum0 > 0.3, `tint luminance ${lum0.toFixed(2)} -> ${lumMid.toFixed(2)} -> ${lumEnd.toFixed(2)}`);
await shot('E_dawn_exit_road_to_the_suburbs');
await dir(1);
for (let n = 0; W.scene.endsWith('room4.tscn') && n < 900; n++) { try { await frame(); } catch { break; }  if (n === 60) await shot('E_exit_fade'); }
await stop();
await throughMap('E', 'perimeter', 'home', 'home.tscn');
await sleep(1800); await poll();
note('E the exit leads to Home', W.scene.endsWith('home.tscn'), W.scene);
note('E auto-saved with the mind and the shockwave', W.save && W.mind && W.shock);
await shot('E_home_arrival');


}console.log('[fps summary]', JSON.stringify(fps));
const failed = results.filter(r => !r[1]);
console.log(`== ${results.length} checks, ${failed.length ? failed.length + ' FAILED' : 'ALL PASS'}; console errors: ${consoleErrors.length}`);
consoleErrors.slice(0, 20).forEach(e => console.log('  [console error]', e.slice(0, 300)));
await browser.close();
server.close();
process.exit(failed.length || consoleErrors.length ? 1 : 0);
