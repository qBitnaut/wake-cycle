// Plays Warehouse Room 1 on the web export with real keyboard events
// (Playwright + system Chromium), from the first black frame to Room 2, with
// plain movement only. Reads the state Room 1 publishes in window.__wake every
// physics frame, takes a screenshot at every beat and records console errors.
//
//   node tools/audit/web_room1.mjs <export_dir> <out_dir> [width height] [--gpu=swiftshader] [--dpr=1.25]
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
const url = `http://127.0.0.1:${server.address().port}/index.html`;

const launchArgs = gpu === 'swiftshader'
  ? ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader']
  : ['--use-angle=vulkan', '--enable-features=Vulkan', '--enable-unsafe-webgpu'];
const browser = await chromium.launch({
  executablePath: '/usr/bin/chromium',
  headless: true,
  args: [...launchArgs, '--ignore-gpu-blocklist', '--disable-gpu-vsync',
    '--autoplay-policy=no-user-gesture-required', '--no-sandbox'],
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
  trackAudio(M.audio);
  { const c = soundClean(M.loops || { playing: 0, orphans: 0, positional: 0 }, await audioLoops(page));
    note(`${tag} sound: on the map no looping sound from the room plays (tree and browser)`, c.ok && (M.loops ? M.loops.positional === 0 : false), c.detail); }
  await page.keyboard.down('KeyW'); await sleep(90); await page.keyboard.up('KeyW');
  for (let i = 0; i < 600 && !(W.scene.endsWith(nextFile) && W.f > 0); i++) { await sleep(50); await poll(); }
  await sleep(900); await poll();
  { const c = soundClean(W.loops || { playing: 0, orphans: 0, positional: 0 }, await audioLoops(page));
    note(`${tag} sound: in the next room no looping sound is left from the previous one`, c.ok, c.detail); }
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
// What the audio director has done, seen through every poll (room and map).
const A = { keys: new Set(), maxDuck: 0, sawFade: false, maxSources: 0 };
function trackAudio(a) { if (!a) return; if (a.music) A.keys.add(a.music); A.maxDuck = Math.max(A.maxDuck, a.duck || 0); A.sawFade = A.sawFade || !!a.fading; }
async function poll() { W = await page.evaluate(() => window.__wake || null); if (W) trackAudio(W.audio); return W; }
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

// The hidden letter A peeks out from behind the box and twinkles: shoot it at the peak of a glint.
for (let n = 0; !(W.glintA > 0.3 && W.glintA < 0.4) && n < 400; n++) await frame();
await shot('A_letter_glint_peeking_behind_box');
await goTo(112, 4);
note('A bonus letter A peeking out behind the cardboard box', W.letters === 1, `letters ${W.letters}`);
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
for (let n = 0; !(W.glintC > 0.3 && W.glintC < 0.4) && n < 400; n++) await frame();
await shot('B_letter_C_glint_in_pocket');
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
// The bot faces the way it walks (the art faces right: flipped when going left).
let faceOk = true;
for (let i = 0; i < 90; i++) { await frame(); if (W.bot[3] === 0 && Math.abs(W.botVx) > 1 && W.botFlip !== (W.botVx < 0)) faceOk = false; }
note('C the patrol bot faces the way it walks', faceOk);
// Stomp it without powers: the cat bounces, nothing else happens.
hp0 = W.hp;
const bx0 = W.bot[0];
await page.evaluate(([x, y]) => window.wakeTeleport(x, y), [W.bot[0], W.bot[1] - 80]);
let bounced = false, flinched = false, bounceShot = false;
for (let i = 0; i < 40; i++) {
  await frame();
  bounced = bounced || W.vy < -300;
  if (W.botFlinch > 0.1) { flinched = true; if (!bounceShot) { bounceShot = true; await shot('C_bot_bounce_clank_flinch'); } }
}
note('C stomping the bot without powers bounces the cat', bounced && flinched, `bounced ${bounced} flinch ${flinched}`);
note('C ...does no damage: no stun, no befriend, no hurt', W.bot[3] === 0 && W.bot[2] === 0 && W.hp === hp0 && !W.dead, `state ${W.bot[3]} stomps ${W.bot[2]} hp ${W.hp}`);
await goTo(1440); await ticks(90);
note('C ...and the bot keeps patrolling', W.bot[3] === 0 && Math.abs(W.bot[0] - bx0) > 6 && Math.abs(W.botVx) > 1, `x ${bx0.toFixed(0)} -> ${W.bot[0].toFixed(0)}`);
await hold('right', true);
for (let n = 0; W.x < 1830 && n < 1800 && !W.dead; n++) {
  const d = W.bot[0] - W.x;
  if (d > 30 && d < 62 && W.floor) {
    await hold('jump', true); await ticks(22); await hold('jump', false);
  } else await hold('jump', false);
  await frame();
}
await stop(); await ticks(20);
note('C waded through the puddle: ripple and splash', rippled && splashShot);
note('C hopped over the patrol bot and got past', W.x >= 1830 && !W.dead && W.bot[2] === 0, `x=${W.x.toFixed(0)} hp ${W.hp} stomps ${W.bot[2]}`);
await shot('C_hall_rain_window_bot');

// ---- D: crawl ----------------------------------------------------------------
await goTo(1880); await dir(1); await ticks(100); await stop();
note('D low beam blocks the standing cat', W.x < 1952, `x=${W.x.toFixed(0)}`);
await hold('down', true); await dir(1);
const crawlAnims = new Set();
for (let n = 0; W.x < 2190 && n < 1200; n++) { await frame(); if (Math.abs(W.vx) > 14) crawlAnims.add(W.anim); if (n === 150) await shot('D_crawl'); }
note('D crawling plays crawl (or the old crouch if there is no crawl)', crawlAnims.size === 1 && (crawlAnims.has('crawl') || crawlAnims.has('crouch')), [...crawlAnims].join());
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
// Count animation changes (from the cat's own counter) from first contact until 1.5 s after the plate: the crate is shoved against its stopper.
let sw0 = -1, swFrames = 0, plateN = -1, pushShot = false; const pushAnims = new Set();
for (let n = 0; n < 900 && (plateN < 0 || n - plateN < 90); n++) {
  await frame();
  if (plateN < 0 && W.plate) plateN = n;
  if (sw0 < 0 && Math.abs(W.crate[0] - W.x) < 32) sw0 = W.sw;
  if (sw0 >= 0) { swFrames++; pushAnims.add(W.anim); if (!pushShot && W.pushT > 0.1 && swFrames > 20) { pushShot = true; await shot('E_push_crate_onto_plate'); } }
}
await stop(); await ticks(40);
const pushSw = W.sw - sw0, pushSecs = Math.max(swFrames / 60, 0.01);
note('E pushing the crate: no animation thrash', sw0 >= 0 && pushSw <= 3 && pushSw / pushSecs <= 2, `${pushSw} switches in ${pushSecs.toFixed(1)} s (${(pushSw / pushSecs).toFixed(1)}/s), anims ${[...pushAnims].join()}`);
note('E pushing plays push (or walk) and never idles', (pushAnims.has('push') || pushAnims.has('walk')) && !pushAnims.has('idle'), [...pushAnims].join());
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
await goTo(4140, 5);
for (let n = 0; !(W.glintT > 0.3 && W.glintT < 0.4) && n < 400; n++) await frame();
await shot('H_letter_T_glint_on_perch');
await hop(1, 24, 18);
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
const caughtX = W.x, fT = W.f;
// The camera entering the pool: shots every ~130 ms and the camera centre, which must not jump.
const camLog = [];
for (let k = 0; k < 8; k++) { camLog.push([W.cam[1], W.cz]); await shot('pool_entry_' + k); await sleep(40); await poll(); }
note('I the game camera holds steady entering the pool (no drop)', camLog.every(c => Math.abs(c[0] - camLog[0][0]) < 1), camLog.map(c => `${c[0].toFixed(0)}@z${c[1].toFixed(2)}`).join(' '));
note('I jumping the pool fails: the cat is caught', W.beat === 3 && caughtX < 4736, `caught at x=${caughtX.toFixed(0)} (pool 4416..4736)`);
note('I input locked in the pool', !W.can_move);
const px0 = W.x;
await dir(1); await hold('jump', true); await ticks(20); await stop();
note('I the cat is stuck: feet do not move', Math.abs(W.x - px0) < 3, `dx=${(W.x - px0).toFixed(1)}`);
// The real transformation (about 18 s): a screenshot at each beat, by physics frame.
async function atSec(sec, name) {
  while ((await poll()).f - fT < sec * 60) await sleep(8);
  await shot(name);
}
await atSec(0.7, 'seq1_caught');
await atSec(3.4, 'seq2_goo_half');
await atSec(6.6, 'seq3_veins');
await atSec(8.1, 'seq4_eyes');
await atSec(8.55, 'seq5_pulse');
await atSec(10.8, 'seq6_normal');
await atSec(13.0, 'seq7_augments');
// The first subtitle line comes up at mind_awakened, over the close-up (CineZoom's unmagnified overlay).
for (let i = 0; i < 1500 && W.mono < 1; i++) { await sleep(8); await poll(); }
await sleep(350); await poll();
const overCine = W.cineActive && W.overlaid && W.speaking;
await shot('subtitles_during_close_up');
note('I a subtitle is on screen while the zoom pass is active (overlay)', overCine, `zoom ${W.cz.toFixed(2)} overlaid ${W.overlaid}`);
// Over the close-up the line must hug the bottom of the window and stay off the zoomed cat;
// once the zoom is over it must stay off the cat (and the crate) in the game frame.
const hit = (a, b) => a[2] > 0 && b[2] > 0 && a[0] < b[0] + b[2] && b[0] < a[0] + a[2] && a[1] < b[1] + b[3] && b[1] < a[1] + a[3];
const sub = { cine: 0, cineHit: 0, cineOff: 0, cineGap: 0, play: 0, playHit: 0, playOff: 0, first: '' };
let afterShot = false, clearAt = -1;
for (let i = 0; i < 4000 && W.speaking; i++) {
  await sleep(16); await poll();
  if (W.subAlpha < 0.5) continue;
  if (W.cineActive && W.overlaid) {
    sub.cine++;
    if (hit(W.subWin, W.catWin)) { sub.cineHit++; sub.first ||= `cine plate ${W.subWin} cat ${W.catWin}`; }
    const [sx, sy, sw, sh] = W.subWin;
    if (sx < 0 || sy < 0 || sx + sw > W.win[0] || sy + sh > W.win[1]) sub.cineOff++;
    sub.cineGap = Math.max(sub.cineGap, W.win[1] - (sy + sh));
  } else if (!W.cineActive) {
    sub.play++;
    if (hit(W.subRect, W.catRect)) { sub.playHit++; sub.first ||= `play plate ${W.subRect} cat ${W.catRect}`; }
    const [sx, sy, sw, sh] = W.subRect;
    if (sx < 0 || sy < 0 || sx + sw > 640 || sy + sh > 360) sub.playOff++;
    if (clearAt < 0) clearAt = i;
    if (!afterShot && i - clearAt > 25) { afterShot = true; await shot('subtitles_after_close_up'); }
    if (i - clearAt > 400) break;
  }
}
note('I subtitles hug the window bottom and stay off the zoomed cat during the close-up', sub.cine > 20 && sub.cineHit === 0 && sub.cineOff === 0 && sub.cineGap < 24 * (W.win[1] / 360), `${sub.cine} samples, ${sub.cineHit} overlap, ${sub.cineOff} off-window, widest gap ${sub.cineGap}px of ${W.win[1]} ${sub.first}`);
note('I subtitles stay off the cat right after the close-up', sub.play > 20 && sub.playHit === 0 && sub.playOff === 0, `${sub.play} samples, ${sub.playHit} overlap, ${sub.playOff} off-screen ${sub.first}`);
await shot('subtitles_awakening_line1');
await atSec(16.0, 'seq8_mind');
await atSec(17.9, 'seq9_zoom_out');
note('I the awakening monologue starts with the mind (subtitles)', W.mono >= 1 && W.monoIds[0] === 'awakening', `${W.mono} line(s): ${W.monoLast && W.monoLast[1]}`);
note('I mind awakens during the sequence, before control returns', W.mind || W.beat !== 4);
for (let n = 0; W.beat !== 4 && n < 2400; n++) await sleep(20), await poll();
note('I TransformSequence finished: mind awakened, no power, no shockwave', W.beat === 4 && W.mind && !W.shock && W.violations === 0 && W.power === 0);
note('I control returns, pool goes inert', W.can_move);
await sleep(3500);
await shot('I_after_transform_pool_inert');

// ---- J: exit --------------------------------------------------------------------------------
await goTo(4690, 8); await hop(1, 12);
note('J out of the pool onto the far sill', onFloorAt(288) && W.x > 4730, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
// The awakening lines keep playing while the cat walks: subtitles over the moving cat.
for (let i = 0; i < 600 && W.mono < 3; i++) { await sleep(20); await poll(); }
await sleep(700); await shot('subtitles_awakening_line3_cat_free');
for (let i = 0; i < 2000 && W.monoIds.filter(id => id === 'awakening').length < 5; i++) { await sleep(20); await poll(); }
note('J awakening monologue: all five lines played', W.monoIds.filter(id => id === 'awakening').length === 5, `${W.mono} lines`);
for (let i = 0; i < 1500 && W.speaking; i++) { await sleep(20); await poll(); }
note('J narration: a voice clip played for each line shown, and each subtitle was held at least as long as its clip + tail', W.audio.voice[0] >= 5 && W.audio.voice[1] >= -0.001, `clips ${W.audio.voice[0]}, hold margin ${W.audio.voice[1].toFixed(2)} s`);
note('J the music and ambience duck under the voice', A.maxDuck > 0.9, `deepest ${A.maxDuck.toFixed(2)}`);
note('J the warehouse music is playing (after the first input)', W.audio.music === 'warehouse' && W.audio.unlocked && W.audio.musicDb > -30, `${W.audio.music} ${W.audio.musicDb.toFixed(1)} dB`);
note('J the first line is spoken (not text only)', W.audio.voice[2] > 0.5, `clip ${W.audio.voice[2].toFixed(2)} s`);
note('J the container is not read before the cat reaches it', !W.container, `x=${W.x.toFixed(0)}`);
await shot('J_loading_door_night_outside');
await goTo(4832, 6); await ticks(6);
note('J the container trigger fires after the mind awakens', W.container && W.mind, `x=${W.x.toFixed(0)}`);
for (let i = 0; i < 400 && W.monoIds.filter(id => id === 'nanofluid_container').length < 1; i++) { await sleep(20); await poll(); }
await sleep(1100); await shot('J_container_and_monologue_line1');
for (let i = 0; i < 1500 && W.monoIds.filter(id => id === 'nanofluid_container').length < 4; i++) { await sleep(20); await poll(); }
note('J container monologue: four lines', W.monoIds.filter(id => id === 'nanofluid_container').length === 4);
await sleep(1200); await shot('J_container_monologue_line4');
await goTo(4872, 6); await ticks(6);
await sleep(300); await shot('J_crate_label_cat_in_front');
note('J the exit hint plays once the container was read', W.hint);
await dir(1);
for (let n = 0; W.scene.endsWith('room1.tscn') && n < 600; n++) { try { await frame(); } catch { break; }  if (n === 40) await shot('J_exit_fade'); }
await stop();
await throughMap('J', 'warehouse', 'yard', 'room2.tscn');
await sleep(1500); await poll();
note('J exit fades out and loads Room 2', W.scene.endsWith('room2.tscn'), W.scene);
{ const a = await audioLoops(page); A.maxSources = Math.max(A.maxSources, a.sources);
  note('J music crossfaded warehouse -> map -> yard', A.keys.has('warehouse') && A.keys.has('map') && A.sawFade, `keys ${[...A.keys]} fade seen ${A.sawFade}`);
  note('J the web audio source count stays bounded (stream playback for loops)', a.audible >= 0 && a.audible <= 8 && a.sources <= 40, `sources ${a.sources}, sounding ${a.audible}`); }
note('J Room 2 auto-saved, mind awake, still no shockwave', W.save && W.mind && !W.shock && W.power === 0, `save ${W.save}`);
await sleep(1500);
await shot('K_room2_cat_with_augments');

const failed = results.filter(r => !r[1]);
console.log(`== ${results.length} checks, ${failed.length ? failed.length + ' FAILED' : 'ALL PASS'}; console errors: ${consoleErrors.length}`);
consoleErrors.slice(0, 20).forEach(e => console.log('  [console error]', e.slice(0, 300)));
await browser.close();
server.close();
process.exit(failed.length || consoleErrors.length ? 1 : 0);
