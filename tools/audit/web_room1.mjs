// Plays Warehouse Room 1 on the web export with real keyboard events
// (Playwright + system Chromium), from the first black frame to Room 2, with
// plain movement only. Reads the state Room 1 publishes in window.__wake every
// physics frame, takes a screenshot at every beat and records console errors.
//
//   node tools/audit/web_room1.mjs <export_dir> <out_dir> [width height] [--gpu=swiftshader] [--dpr=1.25]
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

// ---- The route (tools/audit/room1_route.json, shared with room1_playthrough.gd) ------------------
const ROUTE = JSON.parse(fs.readFileSync(new URL('./room1_route.json', import.meta.url)));
const watch = (n, i) => (W.n && W.n[n]) ? W.n[n][i] : null;
let scoreMark = 0, hpMark = 3;
// Run right/left until x passes jx, then jump; the direction is held for dirFrames, a double jump at frame dj.
async function runHopD(d, jx, dirFrames, dj = 0) {
  await dir(d);
  for (let n = 0; (W.x - jx) * d < 0 && n < 600; n++) await frame();
  await hold('jump', true);
  for (let t = 1; t < 300; t++) {
    await frame();
    if (t === dirFrames) await dir(0);
    if (dj && t === dj) { await hold('jump', false); await frame(); await hold('jump', true); }
    if (t > 8 && W.floor) break;
  }
  await stop(); await ticks(8);
}
async function runSteps(steps, label) {
  for (const st of steps) {
    const op = st[0];
    if (op === 'go') await goTo(st[1], st[2] ?? 6);
    else if (op === 'board') {
      // Step onto the moving lift only while it is down at the catwalk's level.
      for (let n = 0; n < 3000; n++) {
        const ly = watch(st[1], 1), lx = watch(st[1], 0);
        if (W.floor && Math.abs(W.y - ly) < 8 && Math.abs(W.x - lx) < 28) break;
        if (W.x > 392 && ly < 500 && Math.abs(W.y - 516) < 6) await dir(0);
        else await dir(W.x > st[2] ? -1 : 1);
        await frame();
      }
      await dir(0); await ticks(4);
    }
    else if (op === 'key') note(st[1], W.keys.includes('brass'), JSON.stringify(W.keys));
    else if (op === 'gone') note(st[1], !W.door, `x=${W.x.toFixed(0)}`);
    else if (op === 'opendoor') { await dir(1); for (let n = 0; W.door && n < 400; n++) await frame(); await dir(0); await ticks(10); }
    else if (op === 'pos') { /* dev only */ }
    else if (op === 'gorel') await goTo(W.x + st[1], 6);
    else if (op === 'hop') await hop(st[1], st[2], st[3] ?? 0, st[4] ?? 999);
    else if (op === 'runhop') await runHopD(st[1], st[2], st[3], st[4] ?? 0);
    else if (op === 'crawl') {
      await hold('down', true); await dir(st[1]);
      for (let n = 0; (W.x - st[2]) * st[1] < 0 && n < 1500; n++) await frame();
      await hold('down', false); await dir(0); await ticks(20);
    } else if (op === 'off') {
      const d = st[1];
      await dir(d);
      for (let n = 0; (W.x - st[2]) * d < 0 && n < 1500; n++) await frame();
      if (st[4] > 0) { await dir(st[3]); await ticks(st[4]); await dir(0); }
      for (let n = 0; W.floor && n < 40; n++) await frame();
      for (let n = 0; !W.floor && n < 600; n++) await frame();
      await dir(0); await ticks(8);
    } else if (op === 'wait' || op === 'waitgt' || op === 'waitlt') {
      let n = 0;
      for (; n < 1800; n++) {
        const v = watch(st[1], st[2]);
        const ok = v !== null && v !== undefined && (op === 'wait' ? v === st[3] : op === 'waitgt' ? v > st[3] : v < st[3]);
        if (ok) break;
        await frame();
      }
      note(`${label} waited for ${st[1]}[${st[2]}] ${op} ${st[3]}`, n < 1800, `${n} ticks`);
    } else if (op === 'expect') {
      note(st[1], W.floor && Math.abs(W.x - st[2]) <= st[4] && Math.abs(W.y - st[3]) <= st[5], `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)} (want ${st[2]}, ${st[3]})`);
    } else if (op === 'cpcheck') note(`${label} checkpoint ${st[1]} saves`, W.cp === st[1], W.cp);
    else if (op === 'mask') note(st[1], W.lmask === st[2], `mask ${W.lmask}`);
    else if (op === 'collected') note(st[1], (W.got || []).includes(st[2]), `${(W.got || []).length} collected`);
    else if (op === 'hp0') hpMark = W.hp;
    else if (op === 'hp') note(st[1], W.hp >= hpMark, `hp ${W.hp} (was ${hpMark})`);
    else if (op === 'markscore') scoreMark = W.score;
    else if (op === 'scoreup') note(st[1], W.score - scoreMark >= st[2], `score +${W.score - scoreMark}`);
    else if (op === 'hold') await ticks(st[1]);
    else if (op === 'stand') { await stop(); await ticks(st[1]); }
    else if (op === 'nopower') note(`${label} no powers yet`, noPowers());
  }
  await shot(label);
}
for (const beat of ['crates', 'floor', 'racks', 'mezz', 'lift', 'roof', 'office', 'shaft', 'basement', 'tunnel', 'drain', 'lab']) {
  await runSteps(ROUTE[beat], beat);
  if (beat === 'lab') await measureFps('the lab, before the pool');
}
note('H all three letters and a memory, no powers, mind asleep', W.letters === 3 && !W.mind && noPowers(), `letters ${W.letters}`);

// ---- I: the pool -------------------------------------------------------------------------
await goTo(3660); await dir(1);
for (let n = 0; W.x < 3706 && n < 600; n++) await frame();
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
note('I jumping the pool fails: the cat is caught', W.beat === 3 && caughtX < 4032, `caught at x=${caughtX.toFixed(0)} (pool 3712..4032)`);
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
for (let i = 0; i < 1500 && !W.monoIds.includes('awakening'); i++) { await sleep(8); await poll(); }
await sleep(150); await poll();
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
note('I the awakening monologue starts with the mind (subtitles)', W.monoIds.includes('awakening'), `${W.mono} line(s): ${W.monoLast && W.monoLast[1]}`);
note('I mind awakens during the sequence, before control returns', W.mind || W.beat !== 4);
for (let n = 0; W.beat !== 4 && n < 2400; n++) await sleep(20), await poll();
note('I TransformSequence finished: mind awakened, no power, no shockwave', W.beat === 4 && W.mind && !W.shock && W.violations === 0 && W.power === 0);
note('I control returns, pool goes inert', W.can_move);
await sleep(3500);
await shot('I_after_transform_pool_inert');

// ---- J: exit --------------------------------------------------------------------------------
await goTo(3990, 8); await hop(1, 12);
note('J out of the pool onto the far sill', onFloorAt(1024) && W.x > 4034, `x=${W.x.toFixed(0)} y=${W.y.toFixed(0)}`);
// The awakening lines keep playing while the cat walks: subtitles over the moving cat.
for (let i = 0; i < 600 && W.monoIds.filter(id => id === 'awakening').length < 3; i++) { await sleep(20); await poll(); }
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
await goTo(4128, 6); await ticks(6);
note('J the container trigger fires after the mind awakens', W.container && W.mind, `x=${W.x.toFixed(0)}`);
for (let i = 0; i < 400 && W.monoIds.filter(id => id === 'nanofluid_container').length < 1; i++) { await sleep(20); await poll(); }
await sleep(1100); await shot('J_container_and_monologue_line1');
for (let i = 0; i < 1500 && W.monoIds.filter(id => id === 'nanofluid_container').length < 4; i++) { await sleep(20); await poll(); }
note('J container monologue: four lines', W.monoIds.filter(id => id === 'nanofluid_container').length === 4);
await sleep(1200); await shot('J_container_monologue_line4');
await goTo(4170, 6); await ticks(6);
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
