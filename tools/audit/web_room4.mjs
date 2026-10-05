// Plays Room 4, "The Perimeter", on the web export with real keyboard events
// (Playwright + system Chromium), at the default capped frame rate: arrival, the
// three Phase steps, the three Impact steps, the three relays, the scanner, the
// credential, the gate and the dawn-lit exit, with a screenshot at every beat
// and a count of console errors. Starts through the debug deep link
// index.html?start=room4 (Room1 _web_start_override: the cat arrives as Room 3
// leaves it, mind awake and the shockwave unlocked). Reads the state Room 4
// publishes in window.__wake every physics frame. The trials (a plain cat is
// hurt, the windows, the soft-lock nets, every relay needed) live in
// room4_playthrough.gd; this run is the route end to end by keyboard, with a
// teleport only to stage a beat that has just been shown to work.
//
//   node tools/audit/web_room4.mjs <export_dir> <out_dir> [width height] [--gpu=swiftshader] [--dpr=1.25]
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
const consoleErrors = [];
page.on('console', m => { if (m.type() === 'error') consoleErrors.push(m.text()); });
page.on('pageerror', e => consoleErrors.push('pageerror: ' + e.message));

const sleep = ms => new Promise(r => setTimeout(r, ms));
let shotN = 0;
async function shot(name) { await page.screenshot({ path: `${outdir}/${String(++shotN).padStart(2, '0')}_${name}.png` }); }
const results = [];
function note(name, ok, detail = '') {
  results.push([name, ok, detail]);
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name.padEnd(62)} ${detail}`);
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
async function teleport(x, y = 320) {
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
    if (dn >= 34 && dn <= 46 && W.f - last > 30 && W.power === 3) {
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
  await goTo(px - from, 6);
  await dir(1);
  for (let n = 0; W.power !== power && n < 420; n++) await frame();
  await stop();
  return W.power === power;
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

// ---- A: arrival -------------------------------------------------------------------
await sleep(1500); await poll();
note('A arrives in Room 4 through the deep link: start, control, HUD', W.scene.endsWith('room4.tscn') && Math.abs(W.x - 112) < 10 && W.can_move && W.hud, `x=${W.x.toFixed(0)}`);
note('A mind awake, shockwave unlocked, no power, auto-saved', W.mind && W.shock && W.power === 0 && W.save);
const lum0 = lum(W.tint);
await shot('A_arrival');
await waitFor(() => lines('perimeter_arrival') >= 2, 14000);
note('A arrival monologue (fences, lasers / authorised units)', lines('perimeter_arrival') === 2, `${lines('perimeter_arrival')} lines`);
fps.push(await measureFps('the arrival yard in the rain'));
const hp0 = W.hp;
let ok = await runTo(cx(30));
note('A crossed the yard past the walker', ok && W.hp === hp0 && !W.dead, `x=${W.x.toFixed(0)} hp ${W.hp}`);

// ---- P1: Phase, discovery -----------------------------------------------------------
await shot('P1_gatehouse_corridor_sign_pad_fence');
await teleport(cx(40));
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
const hpD = W.hp;
let res = await phaseRun(cx(52), { onDash: async () => { if (!dashShot) { dashShot = true; await shot('P1_laser_dash_through'); } } });
note('P1 one dash goes through the fence: unhurt', res.reached && res.hpLost === 0 && res.dashes === 1, JSON.stringify(res));
await waitFor(() => lines('phase_first') >= 2, 14000);
note('P1 first-use monologue (through it / cyan)', lines('phase_first') === 2, `${lines('phase_first')} lines`);

// ---- P2: Phase, use -----------------------------------------------------------------
await teleport(cx(55));
await ticks(10);
note('P2 checkpoint A', W.cp === 'cp_a', W.cp);
await takePad(cx(60), 3);
let shot2 = false;
res = await phaseRun(cx(108), { onDash: async n => { if (n === 3 && !shot2) { shot2 = true; await shot('P2_laser_dash_series_and_drones'); } } });
note('P2 the corridor by keyboard: three fences and two drones, unhurt', res.reached && res.hpLost === 0 && res.dashes >= 5, JSON.stringify(res));
fps.push(await measureFps('the laser corridor'));
// The turret: stand just outside its beam (it starts at x=3376), past the drone, wait for the end of a shot, cross.
await teleport(cx(104.5));
await shot('P2_turret_beam_telegraph');
let t0 = W.turret; let seenFire = false;
for (let n = 0; n < 900 && !(seenFire && W.turret === 0); n++) { await frame(); if (W.turret === 2) seenFire = true; }
const hpT = W.hp;
await dir(1);
for (let n = 0; W.x < cx(114) && n < 400; n++) await frame();
await stop();
note('P2 the turret is dodged by timing (cross right after a shot)', W.hp === hpT && W.x >= cx(114), `hp ${W.hp}`);

// ---- P3: Phase with Spring ----------------------------------------------------------------
await shot('P3_guardhouse_roof_spring_pad');
await goTo(cx(112), 8);
ok = await takePad(cx(114), 2, 3 * 32);
await sleep(700);
note('P3 the Spring pad grants Spring', W.power === 2, `power ${W.power}`);
await dir(1);
while (W.x < cx(116)) await frame();
await hold('jump', true);
for (let air = 1; air < 60; air++) {
  await frame();
  if (air === 27) { await hold('jump', false); await frame(); await hold('jump', true); }
  if (air === 40) await hold('jump', false);
}
await stop(); await ticks(30);
note('P3 Spring and a double jump: up onto the guardhouse roof', Math.abs(W.y - 96) < 4 && W.x > cx(118), `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
await shot('P3_on_the_roof');
await takePad(cx(120), 3, 36);
res = await phaseRun(cx(133));
note('P3 Phase through the roof fence (Spring, then Phase)', res.reached && res.hpLost === 0, JSON.stringify(res));
ok = await runTo(cx(139));
await ticks(20);
note('P3 off the roof to checkpoint B', ok && W.cp === 'cp_b', W.cp);

// ---- I1: Impact, discovery ------------------------------------------------------------------
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
for (let n = 0; n < 60; n++) { await frame(); if (!impactShot && W.y > 380) { impactShot = true; await shot('I1_impact_break_the_floor_gives'); } }
note('I1 stepping off and pressing Down breaks the cracked floor', pressed && W.y > 430, `y=${W.y.toFixed(0)}`);
await waitFor(() => lines('impact_first') >= 2, 14000);
note('I1 first-use monologue (heavy / violet)', lines('impact_first') === 2, `${lines('impact_first')} lines`);
await shot('I1_lower_tunnel');

// ---- I2: the armoured bot, the chained hatch -------------------------------------------------------
await goTo(cx(152), 6);
await ticks(10);
note('I2 checkpoint C in the tunnel', W.cp === 'cp_c', W.cp);
await ticks(200);
ok = await takePad(4976, 4, 36);
await goTo(5035, 3);
await shot('I2_armoured_bot_corridor');
const botX = () => (W.bots || []).filter(b => Math.abs(b[1] - 448) < 6).map(b => b[0])[0];
for (let n = 0; n < 1500 && !(botX() < 5095 && botX() > 5076); n++) await frame();
await poundJump(5);
await ticks(30);
const botSt = (W.bots || []).filter(b => Math.abs(b[1] - 448) < 8).map(b => b[2])[0];
note('I2 the ground pound stuns the armoured bot', botSt === 1, `state ${botSt}`);
await shot('I2_armoured_bot_stunned');
const hpB = W.hp;
ok = await runTo(cx(168) + 8);
note('I2 through the corridor past the stunned bot, unhurt', ok && W.hp === hpB, `x=${W.x.toFixed(0)}`);
await dir(1);
while (W.x < cx(170.2)) await frame();
await poundJump(5);
await stop();
await ticks(70);
note('I2 the chained hatch drops the cat to the second tunnel', Math.abs(W.y - 576) < 6, `y=${W.y.toFixed(0)}`);

// ---- I3: shield, fence, last hatch ----------------------------------------------------------------
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
note('I3 Phase through the tunnel fence', res.reached && res.hpLost === 0, JSON.stringify(res));
await ticks(200);
await takePad(cx(184), 4, 36);
await dir(1);
while (W.x < cx(188)) await frame();
await poundJump(5);
await stop();
await ticks(70);
note('I3 the last hatch: down to the third tunnel', Math.abs(W.y - 704) < 6, `y=${W.y.toFixed(0)}`);
await goTo(cx(191), 6);
await ticks(10);
note('I3 checkpoint E', W.cp === 'cp_e', W.cp);
ok = await runTo(cx(209));
note('I3 the stair climbs out to the surface', ok && Math.abs(W.y - 320) < 6, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
fps.push(await measureFps('the plaza after the tunnels'));

// ---- F / R1: Spring tower -------------------------------------------------------------------------------
await goTo(cx(213), 6);
await waitFor(() => lines('relays_intro') >= 1, 14000);
note('F the relays intro line plays', lines('relays_intro') === 1);
await shot('F_plaza_three_relays_required');
await goTo(cx(218) - 40, 6);
ok = await takePad(cx(217), 2, 36);
await dir(1);
while (W.x < cx(219.5) + 36) await frame();
await hold('jump', true);
for (let air = 1; air < 60; air++) {
  await frame();
  if (air === 27) { await hold('jump', false); await frame(); await hold('jump', true); }
  if (air === 40) await hold('jump', false);
}
await stop(); await ticks(20);
note('R1 Spring up the tower (7 rows)', Math.abs(W.y - 96) < 4 && W.x > cx(222), `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
await dir(1);
for (let n = 0; n < 300 && !W.relayLit[0]; n++) await frame();
await stop();
note('R1 relay 1 lit, the cat held for the camera pan', W.relayLit[0] === true && W.relays === 1, `relays ${W.relays}`);
await sleep(250);
await shot('R1_relay_lit_pan_starts');
await waitFor(() => W.pans >= 1 && W.cam[0] > 10640, 8000);
await sleep(500);
await shot('R1_pan_to_the_gatehouse_lamp_one');
await waitFor(() => !W.panning && W.can_move, 8000);
note('R1 the camera is back and the cat is free', !W.panning && W.can_move);
await waitFor(() => lines('relay_done') >= 1, 8000);
ok = await runTo(cx(233));
await ticks(20);
note('R1 down to checkpoint G', W.cp === 'cp_g', W.cp);

// ---- R2: the Phase maze ----------------------------------------------------------------------------------
const lit0 = W.hp;
ok = await runTo(cx(244));
await shot('R2_searchlight_drone_then_the_maze');
note('R2 outran the searchlight drone into the maze', ok && !W.dead && W.hp === lit0, `x=${W.x.toFixed(0)}`);
await goTo(cx(243.5), 6);
ok = await takePad(cx(245), 3, 36);
res = await phaseRun(cx(281));
note('R2 Phase through the laser maze, unhurt', res.reached && res.hpLost === 0 && res.dashes >= 4, JSON.stringify(res));
await dir(1);
for (let n = 0; n < 200 && !W.relayLit[1]; n++) await frame();
await stop();
note('R2 relay 2 lit', W.relayLit[1] === true && W.relays === 2, `relays ${W.relays}`);
await sleep(250);
await shot('R2_relay_lit');
await waitFor(() => W.pans >= 2 && W.cam[0] > 10640, 8000);
await sleep(400);
await shot('R2_pan_to_the_gatehouse_lamp_two');
await waitFor(() => !W.panning && W.can_move, 8000);
ok = await runTo(cx(289));
await ticks(20);
note('R2 out of the maze to checkpoint H', W.cp === 'cp_h', W.cp);
fps.push(await measureFps('the plaza by the maze exit'));

// ---- R3: the vault ------------------------------------------------------------------------------------------
await takePad(cx(295), 4, 40);
await dir(1);
while (W.x < cx(300)) await frame();
await stop();
await poundJump(5);
await ticks(70);
note('R3 the pound opens the hatch above the vault', Math.abs(W.y - 448) < 6, `y=${W.y.toFixed(0)}`);
await shot('R3_vault_below_the_shield_and_the_relay');
await goTo(cx(303), 6);
await tap('jump', 3);
await ticks(14);
await tap('jump', 3);
await ticks(30);
note('R3 the shockwave breaks the shield', W.shields[1] === false, JSON.stringify(W.shields));
await dir(1);
for (let n = 0; n < 300 && !W.relayLit[2]; n++) await frame();
await stop();
note('R3 relay 3 lit', W.relayLit[2] === true && W.relays === 3, `relays ${W.relays}`);
await sleep(250);
await shot('R3_relay_lit');
await waitFor(() => W.pans >= 3 && W.cam[0] > 10640, 8000);
await sleep(400);
await shot('R3_pan_to_the_gatehouse_all_three_lamps');
await waitFor(() => !W.panning && W.can_move, 8000);
await waitFor(() => lines('relay_done') >= 3, 12000);
note('R3 "One down." / "Two." / "That\'s all of them!"', lines('relay_done') === 3);
ok = await runTo(cx(318));
note('R3 out of the vault by the stair (checkpoint I)', ok && Math.abs(W.y - 320) < 6, `x=${W.x.toFixed(0)}`);

// ---- scanner, credential, gate -----------------------------------------------------------------------------------
const lumMid = lum(W.tint);
ok = await goTo(cx(325), 6);
await shot('S_scanner_ready_three_lamps');
await dir(1);
for (let n = 0; n < 300 && W.scanMode !== 2; n++) await frame();
await stop();
note('S walking in starts the scan and holds the cat', W.scanning && !W.can_move, `mode ${W.scanMode}`);
await waitFor(() => lines('scanner') >= 1, 8000);
await sleep(900);
await shot('S_scanner_sweeping_the_cat');
await waitFor(() => W.scanMode === 3, 8000);
await sleep(300);
note('S SUPERVISOR CREDENTIAL ACCEPTED on the screen', W.scanMode === 3 && W.scanText[0] === 'SUPERVISOR CREDENTIAL ACCEPTED', JSON.stringify(W.scanText));
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

// ---- E: the road and the exit -----------------------------------------------------------------------------------------
await shot('E_gate_open_dawn_road_ahead');
ok = await runTo(cx(359));
await ticks(20);
note('E through the open gate to checkpoint J', ok && W.cp === 'cp_j', W.cp);
await waitFor(() => lines('perimeter_exit') >= 2, 14000);
note('E exit lines (the rain is stopping / almost home)', lines('perimeter_exit') === 2);
await sleep(3500); await poll();
const lumEnd = lum(W.tint);
note('E the sky lightened with progress: night -> pre-dawn -> sunrise', lum0 < lumMid && lumMid < lumEnd && lumEnd - lum0 > 0.3, `tint luminance ${lum0.toFixed(2)} -> ${lumMid.toFixed(2)} -> ${lumEnd.toFixed(2)}`);
await shot('E_dawn_exit_road_to_the_suburbs');
await dir(1);
for (let n = 0; W.scene.endsWith('room4.tscn') && n < 900; n++) { await frame(); if (n === 60) await shot('E_exit_fade'); }
await stop();
for (let i = 0; i < 100 && !W.scene.endsWith('after_room4.tscn'); i++) { await sleep(50); await poll(); }
await sleep(1800); await poll();
note('E the exit leads to the Home stub', W.scene.endsWith('stubs/after_room4.tscn'), W.scene);
note('E auto-saved with the mind and the shockwave', W.save && W.mind && W.shock);
await shot('E_home_coming_soon');

console.log('[fps summary]', JSON.stringify(fps));
const failed = results.filter(r => !r[1]);
console.log(`== ${results.length} checks, ${failed.length ? failed.length + ' FAILED' : 'ALL PASS'}; console errors: ${consoleErrors.length}`);
consoleErrors.slice(0, 20).forEach(e => console.log('  [console error]', e.slice(0, 300)));
await browser.close();
server.close();
process.exit(failed.length || consoleErrors.length ? 1 : 0);
