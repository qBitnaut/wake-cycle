// Plays Room 2, "The Yard", on the web export with real keyboard events
// (Playwright + system Chromium): arrival in the rain, the three Surge beats,
// the docked bot, the exit and the Room 3 stub, at the default capped frame
// rate. Starts through the debug deep link index.html?start=room2 (Room1
// _web_start_override: the cat arrives as Room 1 leaves it). Reads the state
// Room 2 publishes in window.__wake every physics frame, takes a screenshot at
// every beat and records console errors. The trial logic (the plain cat falls
// short, the gate wins against a plain cat) lives in room2_playthrough.gd; this
// run is the Surge route end to end.
//
//   node tools/audit/web_room2.mjs <export_dir> <out_dir> [width height] [--gpu=swiftshader] [--dpr=1.25]
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
await new Promise(res => server.listen(Number(process.env.PORT || process.env.AUDIT_PORT || 0), res));
const url = `http://127.0.0.1:${server.address().port}/index.html?start=room2`;

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
for (let i = 0; i < 400 && !(W.scene.endsWith('room2.tscn') && W.f > 0); i++) { await sleep(50); await poll(); }

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
  for (let i = 0; i < 15000; i++) { await poll(); if (W.f > f) return W; await sleep(1); }
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

// ---- A: arrival in the rain -------------------------------------------------------
await sleep(1500); await poll();
note('A arrives in Room 2 through the transition: warehouse door, control, HUD', W.scene.endsWith('room2.tscn') && Math.abs(W.x - 112) < 10 && W.can_move && W.hud, `x=${W.x.toFixed(0)}`);
note('A mind awake, no power, no shockwave, auto-saved', W.mind && W.power === 0 && !W.shock && W.save);
await shot('A_arrival_in_the_rain');
await waitFor(() => lines('yard_arrival') >= 2, 14000);
await sleep(500);
note('A arrival monologue (Rain. Cold. Real. / The city...)', lines('yard_arrival') === 2, `${lines('yard_arrival')} lines`);
await shot('A_arrival_monologue_city_lights');
// Lightning: strike, shoot the flash, and the thunder follows.
const t0 = W.thunders;
let flashShot = false;
for (let k = 0; k < 4 && !flashShot; k++) {
  await page.evaluate(() => window.wakeStrike());
  if (await waitFor(() => W.flash > 0.8, 1500)) { await shot('lightning_flash'); flashShot = true; }
  await sleep(2600);
}
await waitFor(() => W.thunders > t0, 4000);
note('A lightning flashes and the thunder signal fires (sound hooked)', W.thunders > t0, `thunders ${W.thunders}`);
await measureFps('the yard in the rain');
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
// The first walker: hop it. A stop at the crate steps and on.
const hp0 = W.hp;
let ok = await runTo(930);
note('A crossed the arrival yard past the first walker', ok && W.hp === hp0 && !W.dead, `x=${W.x.toFixed(0)} hp ${W.hp}`);
await shot('A_yard_walker_crates_fence');

// ---- B1: Surge, discovery ------------------------------------------------------------
await shot('B1_tunnel_mouth_container_on_gantry');
await dir(1);
let minY = 1e9;
for (let n = 0; W.x < 1240 && n < 600; n++) {
  if (n % 18 === 0) await hold('jump', true); else if (n % 18 === 9) await hold('jump', false);
  await frame();
  if (W.x > 975 && W.x < 1180) minY = Math.min(minY, W.y);
  if (W.power === 1 && n % 4 === 0 && !globalThis.__shot1) { globalThis.__shot1 = true; await sleep(450); await shot('B1_first_surge_pad_emitters_blue'); }
}
await stop();
note('B1 the pad in the low tunnel cannot be hopped: Surge granted', W.power === 1, `power ${W.power}, headroom rise ${(768 - minY).toFixed(1)} px`);
await waitFor(() => lines('surge_first') >= 2, 14000);
note('B1 first-use monologue (my legs / the same blue)', lines('surge_first') === 2, `${lines('surge_first')} lines`);
await ticks(30); await poll();
note('B1 the HUD has the power and a running timer', W.power === 1 && W.powerTime > 0 && W.powerTime < 10, `${W.powerTime.toFixed(1)} s left`);
await dir(1); await ticks(50); const vx = W.vx; await stop();
note('B1 Surge speed on the clear run (1.5x)', Math.abs(vx - 267) < 8, `vx ${vx.toFixed(0)}`);
await shot('B1_surge_run_clear_ground');
await sleep(900);  // standing still: the emitters have settled on the Surge blue
await shot('B1_emitters_blue_standing');
ok = await runTo(1850);
await ticks(10);
note('B1 checkpoint A', W.cp === 'cp_a', W.cp);

// ---- B2: the Surge gap (a hole into the underpass) -------------------------------------------
await goTo(1960, 8);
await hold('right', true);
for (let n = 0; W.x < 2150 && n < 400; n++) await frame();
await stop();
note('B2 second pad: Surge again', W.power === 1 && W.powerTime > 9, `${W.powerTime.toFixed(1)} s`);
await shot('B2_surge_gap_ahead_nine_tiles');
let crossTries = 0;
for (;;) {
  crossTries++;
  ok = await runTo(2700, { each: async () => { if (W.x > 2300 && W.x < 2480 && !globalThis.__gap) { globalThis.__gap = true; await shot('B2_crossing_the_gap_mid_air'); } } });
  if ((ok && W.y < 800) || crossTries >= 3) break;
  // A miss is a safe drop into the underpass: a human walks back to the pad and goes again.
  await page.evaluate(() => window.wakeTeleport(1960, 768)); await sleep(3500); await ticks(10);
  await hold('right', true); for (let n = 0; W.x < 2150 && n < 400; n++) await frame(); await stop();
}
note('B2 crossed the gap with Surge (run-up, double jump)', ok && !W.dead && W.y < 800, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
await ticks(10);
note('B2 checkpoint B on the far side', W.cp === 'cp_b', W.cp);
await shot('B2_landing_turret_on_the_stub');

// A scripted hop (the same as room2_playthrough.gd hop): run to jumpX, jump, hold d to the landing.
async function hop(d, jx, tx0, tx1, ty) {
  for (let n = 0; (W.x - jx) * d < 0 && n < 900; n++) { await dir(d); await frame(); }
  await hold('jump', true);
  for (let f = 1; f < 220; f++) {
    await dir(d); await frame();
    if (f === 22) await hold('jump', false);
    if (f > 6 && W.floor && W.vy >= 0) break;
  }
  await stop(); await ticks(6);
  return W.floor && W.x >= tx0 && W.x <= tx1 && Math.abs(W.y - ty) < 6;
}
async function climb(steps, fromX, fromY) {
  for (let t = 0; t < 3; t++) {
    if (t) { await page.evaluate(([x, y]) => window.wakeTeleport(x, y), [fromX, fromY]); await ticks(20); }
    let good = true;
    for (const st of steps) if (!(await hop(...st))) { good = false; break; }
    if (good) return true;
  }
  return false;
}
const tp = async (x, y) => { await page.evaluate(([a, b]) => window.wakeTeleport(a, b), [x, y]); await ticks(20); };

// ---- U: the underpass (entered by a teleport to the landing; everything after is real keys) ----
await tp(1840, 1024);
note('U the underpass loads: the cat stands on the drain floor under the yard', W.floor && Math.abs(W.y - 1024) < 4, `y=${W.y.toFixed(0)}`);
await shot('U_the_drain_under_the_yard');
await measureFps('the underpass');
await waitFor(() => W.barrelGone && W.hatchGone, 14000);
await shot('U3_the_hatch_after_the_blast');
note('U3 the turret\'s bolt popped the barrel and the blast broke the hatch', W.barrelGone && W.hatchGone, `barrel gone ${W.barrelGone} hatch gone ${W.hatchGone}`);
await waitFor(() => lines('yard_vault') >= 2, 14000);
await dir(-1);
for (let n = 0; W.x > 1690 && n < 300; n++) await frame();
await stop();
await waitFor(() => W.y > 1100, 4000);
await goTo(1488, 8);
await waitFor(() => lines('memory_yard') >= 2, 16000);
note('U3 the memory fragment is collected (5000) and plays', lines('memory_yard') === 2 && W.score >= 5000, `lines ${lines('memory_yard')} score ${W.score}`);
await shot('U3_the_vault_memory_fragment');
await tp(3110, 1024);
await dir(1);
const score0 = W.score;
for (let n = 0; W.x < 3712 && n < 900; n++) await frame();
await stop();
note('U1 the crawl cache: the dip, the low tunnel and the golden bone (+2000)', W.x >= 3640 && W.score >= score0 + 2000, `x=${W.x.toFixed(0)} score +${W.score - score0}`);
await shot('U1_the_crawl_cache_bone');
await tp(4656, 1024);
await shot('U2_stand_on_the_hatch_under_the_drone');
await waitFor(() => W.spurMode === 1, 15000);
await dir(-1);
for (let n = 0; W.x > 4540 && n < 200; n++) await frame();
await stop();
await waitFor(() => W.closetGone, 4000);
note('U2 the drone\'s bomb broke the closet hatch', W.closetGone, `gone ${W.closetGone}`);
await shot('U2_the_closet_hatch_broken');

// ---- R: the rooftops (a girder stair by real hops, the pad, a Surge run, the crane stair) -----
await tp(2600, 768);
const okc1 = await climb([[1, 2658, 2696, 2776, 704], [1, 2764, 2792, 2872, 640], [1, 2860, 2888, 2968, 576], [1, 2956, 2984, 3200, 512]], 2600, 768);
note('R climbed the girder stair to the first roof', okc1, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
await shot('R_first_roof_pad_and_turret');
await goTo(3040, 6);
await waitFor(() => W.power === 1, 2000);
await waitFor(() => lines('yard_roof') >= 1, 12000);
note('R the roof pad grants Surge and the hint plays', W.power === 1 && lines('yard_roof') === 1, `power ${W.power}`);
ok = await runTo(3900, { each: async () => { if (W.x > 3500 && !globalThis.__roof) { globalThis.__roof = true; await shot('R_surge_run_over_the_containers'); } } });
for (let n = 0; !W.floor && n < 90; n++) await frame();
note('R ran the rooftops on Surge', ok && !W.dead && Math.abs(W.y - 512) < 6, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
await waitFor(() => W.power === 0, 14000);   // plain hops: let the Surge run out
await goTo(4034, 6);
const okc2 = await climb([[1, 4040, 4072, 4152, 448], [-1, 4094, 3976, 4056, 384], [1, 4040, 4072, 4152, 320], [1, 4136, 4168, 4300, 256]], 4034, 512);
note('R climbed the crane stair to the cab', okc2 && Math.abs(W.y - 256) < 4, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
await ticks(20);
note('R the cab checkpoint', W.cp === 'cp_r', W.cp);
await shot('R_the_crane_cab_at_the_top');

// ---- D: the loading dock ---------------------------------------------------------------------
await tp(4368, 768);
await goTo(4290, 6);
await ticks(10);
note('D checkpoint C', W.cp === 'cp_c', W.cp);
await shot('D_dock_conveyors_and_gantry_crate');
ok = await runTo(4540);
note('D the dock bot has not reacted yet', W.dockReacted === false || W.dock > 0);
await goTo(4540, 8);
await waitFor(() => W.dock > 0.9, 6000);
await sleep(1300);
await shot('D_dock_bot_reacts_eye_in_emitter_colour');
await waitFor(() => lines('dock_bot') >= 2, 14000);
note('D the bot reacts and the monologue plays', W.dockReacted && lines('dock_bot') === 2, `wake ${W.dock && W.dock.toFixed(2)}`);
await goTo(4770, 8);
{ let d = 1;
  for (let n = 0; W.camAlarms < 1 && n < 1800 && !W.dead; n++) { await dir(d); await frame(); if (W.x > 4890) d = -1; else if (W.x < 4780) d = 1; }
  await stop(); }
await waitFor(() => W.shutterOpen === false, 3000);
note('D the camera spots the cat: the alarm shuts the guard door', W.camAlarms >= 1 && W.shutterOpen === false, `alarms ${W.camAlarms} door open ${W.shutterOpen}`);
await shot('D_camera_alarm_door_shut');
await waitFor(() => W.shutterOpen === true, 12000);
note('D the alarm passes and the door opens again', W.shutterOpen === true);

// ---- B4: combine ---------------------------------------------------------------------------
await tp(5200, 768);
await ticks(10);
note('D checkpoint D', W.cp === 'cp_d', W.cp);
let droneShot = false, ventShot = false, pitShot = false, droneAudible = false;
await runTo(6560, { cf: 6122, ct: 6282, each: async () => {
  if (W.drone === 1 && W.loops && W.loops.positional >= 1) droneAudible = true;
  if (W.drone === 1 && W.x > 5420 && !droneShot) { droneShot = true; await shot('B4_drone_searchlight_chasing'); }
  if (W.x > 5700 && W.x < 5740 && !pitShot) { pitShot = true; await shot('B4_hole_ahead_steps_behind'); }
  if (W.crouch && W.x > 6170 && !ventShot) { ventShot = true; await shot('B4_crawl_vent_cover'); }
} });
note('B4 combined challenge on Surge: pad, steps, hole, vent, never seen', W.x >= 6560 && !W.alarm && !W.dead, `x=${W.x.toFixed(0)} alarm ${W.alarm}`);
note('B4 the drone was triggered and swept', W.drone !== null && W.drone >= 1, `drone state ${W.drone}`);
note('B4 sound: the drone\'s whirr was audible (distance-faded) while it chased', droneAudible, `positional loops seen: ${droneAudible}`);
await waitFor(() => W.drone === 3, 15000);
await sleep(2500); await poll();
{ const c = soundClean(W.loops, await audioLoops(page));
  note('B4 sound: once the drone has left its whirr is gone: no audible drone loop, no orphan, nothing in the browser', W.drone === 3 && W.loops.positional === 0 && c.ok, `drone state ${W.drone}; ${c.detail}`); }

// ---- E: the fence ------------------------------------------------------------------------------
await goTo(6672, 8);
await waitFor(() => lines('exit_fence') >= 1, 12000);
await sleep(300); await shot('E_fence_cut_exit');
note('E the fence line plays', lines('exit_fence') === 1);
await dir(1);
for (let n = 0; W.scene.endsWith('room2.tscn') && n < 900; n++) { try { await frame(); } catch { break; }  if (n === 60) await shot('E_exit_fade'); }
await stop();
await throughMap('E', 'yard', 'stacks', 'room3.tscn');
await sleep(1800); await poll();
note('E exit leads to Room 3', W.scene.endsWith('room3.tscn'), W.scene);
note('E Room 3 auto-saved with the mind, no shockwave', W.save && W.mind && !W.shock, `power ${W.power}`);
await shot('E_room3_coming_soon');

const failed = results.filter(r => !r[1]);
console.log(`== ${results.length} checks, ${failed.length ? failed.length + ' FAILED' : 'ALL PASS'}; console errors: ${consoleErrors.length}`);
consoleErrors.slice(0, 20).forEach(e => console.log('  [console error]', e.slice(0, 300)));
await browser.close();
server.close();
process.exit(failed.length || consoleErrors.length ? 1 : 0);
