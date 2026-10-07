// The Continue and Start Over pads on the DEBUG web export: seeds an IndexedDB save, then walks it.
//   node tools/audit/web_continue.mjs <debug_dir> <out_dir> <port>   (SV=1: old-version save, CP=cp_removed: stale checkpoint)
// Default run: both pads and their signs; walking right and a brush-past do nothing; a plain jump from the
// wake spot reaches the Start Over ledge; both pads need a 1 s sit (the cat sits, a ring fills); Continue loads
// Room 3; Start Over wipes the save for good (it stays gone after a reload); and the story's end (the
// final sleep in Home, via ?start=home) clears the save so a reload mid-credits has no pad.
import { createRequire } from 'node:module';
import http from 'node:http'; import fs from 'node:fs'; import os from 'node:os'; import path from 'node:path';
const PW = path.join(os.homedir(), '.local/share/mise/installs/npm-playwright/latest/node_modules/playwright');
const { chromium } = createRequire(import.meta.url)(PW);
const [root, out, port] = process.argv.slice(2); fs.mkdirSync(out, { recursive: true });
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png' };
const server = http.createServer((q, r) => { let p = path.join(root, decodeURIComponent(q.url.split('?')[0])); if (p.endsWith('/')) p += 'index.html';
  fs.readFile(p, (e, d) => { if (e) { r.writeHead(404); r.end(); return; } r.writeHead(200, { 'Content-Type': MIME[path.extname(p)] || 'application/octet-stream' }); r.end(d); }); });
await new Promise(r => server.listen(+port, r));
const url = `http://127.0.0.1:${port}/index.html`;
const browser = await chromium.launch({ executablePath: '/usr/bin/chromium', headless: true, args: ['--use-angle=vulkan', '--enable-features=Vulkan', '--ignore-gpu-blocklist', '--no-sandbox', '--autoplay-policy=no-user-gesture-required'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
const errs = []; page.on('console', m => { if (m.type() === 'error') errs.push(m.text()); }); page.on('pageerror', e => errs.push(e.message));
const sleep = ms => new Promise(r => setTimeout(r, ms));
let n = 0; const shot = async s => page.screenshot({ path: `${out}/${String(++n).padStart(2, '0')}_${s}.png` });
let fails = 0; const note = (s, ok, d = '') => { console.log(`${ok ? 'PASS' : 'FAIL'}  ${s}  ${d}`); if (!ok) fails++; };
const save = { version: +(process.env.SV || 2), scene: 'res://scenes/levels/room3.tscn', checkpoint: process.env.CP || 'cp_a', abilities: { shockwave: false, mind: true }, keys: [], letters: 1, letter_mask: 3, collectibles: [], health: 3, score: 4200, map: { completed: ['warehouse', 'yard'], unlocked: ['yard', 'stacks'], node: 'yard' } };
async function idb(fn, arg) { return page.evaluate(([f, a]) => new Promise((res, rej) => { const o = indexedDB.open('/userfs'); o.onerror = () => rej(o.error); o.onsuccess = () => { const db = o.result; const tx = db.transaction('FILE_DATA', 'readwrite'); const st = tx.objectStore('FILE_DATA'); eval('(' + f + ')')(st, a, res); }; }), [fn.toString(), arg]); }
const dir = '/userfs/godot/app_userdata/Wake Cycle';
const SAVE = dir + '/save.json';
let W = null; const poll = async () => (W = await page.evaluate(() => window.__wake));
async function putFile(p, text) {
  await idb((st, a, res) => { for (const d of ['/userfs/godot', '/userfs/godot/app_userdata', a[0].replace(/\/[^/]*$/, '')]) st.put({ timestamp: new Date(), mode: 16895 }, d); st.put({ timestamp: new Date(), mode: 33206, contents: new TextEncoder().encode(a[1]) }, a[0]); st.transaction.oncomplete = () => res(1); }, [p, text]);
}
async function hasFile(p) { return idb((st, a, res) => { const r = st.getAllKeys(); r.onsuccess = () => res(r.result.includes(a)); }, p); }
async function boot(u) {
  await page.goto(u || url); await sleep(1500);
  await page.waitForFunction(() => window.__wake && window.__wake.f > 0, null, { timeout: 60000 });
}
async function control() { for (let i = 0; i < 1500; i++) { await poll(); if (W.can_move) break; await sleep(100); } }
async function reseed() { await page.goto(url); await sleep(3000); await putFile(SAVE, JSON.stringify(save)); await page.reload(); await sleep(1000); await page.waitForFunction(() => window.__wake && window.__wake.f > 0, null, { timeout: 60000 }); await control(); }
async function hop() { // a plain jump from the wake spot, drifting left, onto the Start Over ledge
  await page.keyboard.down('Space'); await page.keyboard.down('KeyA');
  for (let i = 0; i < 80; i++) { await sleep(15); await poll(); if (i > 6 && W.vy > 0 && W.x < W.padS[2] + 20) await page.keyboard.up('KeyA'); if (i > 12 && W.floor) break; }
  await page.keyboard.up('Space'); await page.keyboard.up('KeyA'); await sleep(60); await poll();
}
async function toWake() { for (let k = 0; k < 3; k++) { await poll(); if (Math.abs(W.x - 144) < 8) break; const key = W.x < 144 ? 'KeyD' : 'KeyA'; await page.keyboard.down(key); for (let i = 0; i < 400; i++) { await poll(); if (key === 'KeyD' ? W.x >= 144 : W.x <= 144) break; await sleep(8); } await page.keyboard.up(key); await sleep(350); } await poll(); }

await page.goto(url); await sleep(3000);
console.log('keys', (await idb((st, a, res) => { const r = st.getAllKeys(); r.onsuccess = () => res(r.result); })).slice(0, 8), dir);
await putFile(SAVE, JSON.stringify(save));
await page.reload(); await sleep(1000);
await page.waitForFunction(() => window.__wake && window.__wake.f > 0, null, { timeout: 60000 });
await control();
note('control granted', W.can_move === true, JSON.stringify({ x: W.x, save: W.save }));
if (process.env.SV && +process.env.SV !== 2) { note('old-version save: no pad / no save', W.save === false && !W.padC[0] && !W.padS[0]); await shot('old_save_no_pad'); }
else if (process.env.CP === 'cp_removed') {
  note('save kept (valid version)', W.save === true);
}
else {
  note('v2 save: has_save true; both pads shown, Start Over above Continue', W.save === true && W.padC[0] && W.padS[0] && W.padS[3] < W.padC[3] - 48 && Math.abs(W.padS[2] - W.padC[2]) < 48, JSON.stringify([W.padC, W.padS]));
  await page.keyboard.down('KeyD'); await sleep(2500); await page.keyboard.up('KeyD'); await poll();
  note('walking right does not continue (or start over)', W.scene.endsWith('room1.tscn') && W.save === true, W.scene + ' x=' + W.x);
  await toWake();
  await shot('both_pads_with_signs');
  await page.keyboard.down('KeyA'); for (let i = 0; i < 200; i++) { await poll(); if (W.x < 175) break; await sleep(30); } await page.keyboard.up('KeyA'); await sleep(200);
  await shot('continue_pad_sign');
  await page.keyboard.down('KeyA'); await sleep(1500); await page.keyboard.up('KeyA'); await sleep(250); await poll();
  note('brush walk left (no stand) ok', W.scene.endsWith('room1.tscn') && W.save === true, 'x=' + W.x);
  await toWake();
  // ---- the Start Over ledge ----
  await hop();
  note('a plain jump from the wake spot lands on the Start Over ledge', W.floor && W.y < W.padS[3] + 8 && Math.abs(W.x - W.padS[2]) < 30, JSON.stringify({ x: W.x, y: W.y, pad: W.padS }));
  await sleep(450); await poll();
  note('standing on it sits the cat and fills the ring', W.anim === 'sit' && W.padS[1] > 0.15 && W.padS[1] < 0.9, W.anim + ' ' + W.padS[1]);
  await shot('start_over_sit_ring');
  await sleep(150); await shot('start_over_sit_ring_2');
  await page.keyboard.down('KeyD'); await sleep(700); await page.keyboard.up('KeyD'); await sleep(900); await poll();
  note('a short sit then walking off does not trigger; the ring drains', W.save === true && W.scene.endsWith('room1.tscn') && W.padS[1] === 0, JSON.stringify(W.padS));
  await toWake();
  // ---- Continue: sit and wait 1 s ----
  await page.keyboard.down('KeyD'); await sleep(100); await page.keyboard.up('KeyD');
  await page.keyboard.down('KeyA'); for (let i = 0; i < 200; i++) { await poll(); if (W.x < W.padC[2] + 20) break; await sleep(10); } await page.keyboard.up('KeyA');
  await sleep(120); await poll();
  note('the pad tease is a meow (no mind yet): meow played, no subtitle, nothing narrated', W.mind === false && W.meows.some(m => m[0] === 'continue_tease') && W.meowSfx >= 1 && W.mono === 0 && !W.speaking, JSON.stringify({ meows: W.meows, sfx: W.meowSfx, mono: W.mono, speaking: W.speaking }));
  await sleep(300); await poll();
  note('on the Continue pad the cat sits and the ring fills', W.anim === 'sit' && W.padC[1] > 0.1 && W.padC[1] < 0.9, W.anim + ' ' + W.padC[1]);
  await shot('continue_sit_ring');
  for (let i = 0; i < 10; i++) { await sleep(100); await shot('fade_' + i); }
  for (let i = 0; i < 100 && !W.scene.endsWith('room3.tscn'); i++) { await sleep(100); await poll(); }
  note('loaded room 3 at cp', W.scene.endsWith('room3.tscn') && W.cp === 'cp_a', W.scene + ' ' + W.cp + ' x=' + W.x);
  await sleep(2500); await shot('room3_after_continue');
  // ---- Start Over: wipe, and it stays wiped after a reload ----
  await reseed();
  await toWake(); await hop();
  note('(again) on the ledge', W.floor && Math.abs(W.x - W.padS[2]) < 30, JSON.stringify({ x: W.x, pad: W.padS }));
  await sleep(1300);
  for (let i = 0; i < 12; i++) { await sleep(100); await shot('start_over_flash_' + i); }
  await sleep(1500); await poll();
  note('Start Over: a new game in Room 1 from the wake spot, both pads gone', W.scene.endsWith('room1.tscn') && W.can_move && W.save === false && !W.padC[0] && !W.padS[0] && W.score === 0 && W.mind === false && W.lmask === 0 && W.got.length === 0 && Math.abs(W.x - 144) < 16, JSON.stringify({ x: W.x, save: W.save, score: W.score, pads: [W.padC, W.padS] }));
  note('the save file is gone from IndexedDB', !(await hasFile(SAVE)));
  await shot('after_start_over');
  await page.reload(); await sleep(1000);
  await page.waitForFunction(() => window.__wake && window.__wake.f > 0, null, { timeout: 60000 });
  await control();
  note('after a reload: still no save, no pads', W.save === false && !W.padC[0] && !W.padS[0]);
  // ---- the story's end: the final sleep clears the run, so closing the browser mid-credits leaves nothing ----
  await boot(`http://127.0.0.1:${port}/index.html?start=home`);
  for (let i = 0; i < 100; i++) { await poll(); if (W.can_move) break; await sleep(200); }
  note('Home: arriving auto-saves (the trap)', W.save === true && W.scene.endsWith('home.tscn'), JSON.stringify({ save: W.save, beat: W.beat }));
  await page.keyboard.down('KeyD');
  for (let i = 0; i < 1800 && W.beat < 3; i++) { await sleep(100); await poll(); }
  await page.keyboard.up('KeyD');
  note('the cat reaches the sunbeam: the final sleep begins and the save is gone at once', W.beat >= 3 && W.save === false, JSON.stringify({ beat: W.beat, save: W.save }));
  await sleep(2000); await shot('home_final_sleep');
  note('the save file is gone from IndexedDB, the completed flag is there', !(await hasFile(SAVE)) && (await hasFile(dir + '/complete.json')));
  await page.goto(url); await sleep(1000);   // the browser closed mid-credits, opened again (not the ?start=home deep link)
  await page.waitForFunction(() => window.__wake && window.__wake.f > 0, null, { timeout: 60000 });
  await control();
  note('the next launch: Room 1, no Continue pad, no Start Over pad', W.scene.endsWith('room1.tscn') && W.save === false && !W.padC[0] && !W.padS[0] && W.complete === true, JSON.stringify({ save: W.save, pads: [W.padC, W.padS], complete: W.complete }));
  await shot('next_launch_no_pads');
}
console.log('console errors', errs.length, errs.slice(0, 3));
await browser.close(); server.close(); process.exit(fails || errs.length ? 1 : 0);
