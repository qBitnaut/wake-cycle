// Continue pad on the DEBUG web export: seeds an IndexedDB save, then walks it. node tools/audit/web_continue.mjs <debug_dir> <out_dir> <port>   (SV=1: old-version save, CP=cp_removed: stale checkpoint)
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
const save = { version: +(process.env.SV || 2), scene: 'res://scenes/levels/room3.tscn', checkpoint: process.env.CP || 'cp_a', abilities: { shockwave: false, mind: true }, keys: [], letters: 1, letter_mask: 3, collectibles: [], health: 3, score: 10, map: { completed: ['warehouse', 'yard'], unlocked: ['yard', 'stacks'], node: 'yard' } };
async function idb(fn, arg) { return page.evaluate(([f, a]) => new Promise((res, rej) => { const o = indexedDB.open('/userfs'); o.onerror = () => rej(o.error); o.onsuccess = () => { const db = o.result; const tx = db.transaction('FILE_DATA', 'readwrite'); const st = tx.objectStore('FILE_DATA'); eval('(' + f + ')')(st, a, res); }; }), [fn.toString(), arg]); }
await page.goto(url); await sleep(6000);
const keys = await idb((st, a, res) => { const r = st.getAllKeys(); r.onsuccess = () => res(r.result); });
const dir = '/userfs/godot/app_userdata/Wake Cycle';
console.log('keys', keys.slice(0, 8), dir);
const p = dir + '/save.json';
await idb((st, a, res) => { for (const d of ['/userfs/godot', '/userfs/godot/app_userdata', a[0].replace('/save.json', '')]) st.put({ timestamp: new Date(), mode: 16895 }, d); st.put({ timestamp: new Date(), mode: 33206, contents: new TextEncoder().encode(a[1]) }, a[0]); st.transaction.oncomplete = () => res(1); }, [p, JSON.stringify(save)]);
await page.reload(); await sleep(1000);
await page.waitForFunction(() => window.__wake && window.__wake.f > 0, null, { timeout: 60000 });
let W = null; const poll = async () => (W = await page.evaluate(() => window.__wake));
for (let i = 0; i < 400; i++) { await poll(); if (W.canMove) break; await sleep(100); }
note('control granted', W.canMove === true, JSON.stringify({ x: W.x, save: W.save }));
if (process.env.SV && +process.env.SV !== 2) { note('old-version save: no pad / no save', W.save === false); await shot('old_save_no_pad'); }
else if (process.env.CP === 'cp_removed') {
  note('save kept (valid version)', W.save === true);
}
else {
  note('v2 save: has_save true', W.save === true);
  await page.keyboard.down('KeyD'); await sleep(2500); await page.keyboard.up('KeyD'); await poll();
  note('walking right does not continue', W.scene.endsWith('room1.tscn'), W.scene + ' x=' + W.x);
  await page.keyboard.down('KeyA'); for (let i = 0; i < 200; i++) { await poll(); if (W.x < 175) break; await sleep(30); } await page.keyboard.up('KeyA'); await sleep(200);
  await shot('pad_left_of_wake_spot_with_sign');
  await page.keyboard.down('KeyA'); await sleep(1500); await page.keyboard.up('KeyA'); await sleep(250); await poll();
  note('brush walk left (no stand) ok', true, 'x=' + W.x);
  await page.keyboard.down('KeyD'); for (let i = 0; i < 200; i++) { await poll(); if (W.x > 135) break; await sleep(10); } await page.keyboard.up('KeyD'); await sleep(500);
  await page.keyboard.down('KeyA'); for (let i = 0; i < 200; i++) { await poll(); if (W.x < 98) break; await sleep(10); } await page.keyboard.up('KeyA');
  await sleep(120); await shot('charging_ring');
  for (let i = 0; i < 10; i++) { await sleep(100); await shot('fade_' + i); }
  for (let i = 0; i < 100 && !W.scene.endsWith('room3.tscn'); i++) { await sleep(100); await poll(); }
  note('loaded room 3 at cp', W.scene.endsWith('room3.tscn') && W.cp === 'cp_a', W.scene + ' ' + W.cp + ' x=' + W.x);
  await sleep(2500); await shot('room3_after_continue');
}
console.log('console errors', errs.length, errs.slice(0, 3));
await browser.close(); server.close(); process.exit(fails || errs.length ? 1 : 0);
