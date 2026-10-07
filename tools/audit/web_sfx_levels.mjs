// Every sound effect, as the BROWSER outputs it. Same WebAudio destination tap as
// web_audio_levels.mjs (GainNode -> AnalyserNode, polled every 50 ms). Runs Room 1, unlocks
// the audio with a key, then fires each sound through the game's own path (window.wakeSfx:
// Sfx.play / KitSfx.play, "loop:<name>" for a positional loop) and records the output peak in
// the 1.5 s after it, next to the peak of the 1.5 s of bed just before it.
//
//   node tools/audit/web_sfx_levels.mjs <debug_export_dir> [--port=10911]
// Asserts: every sound peaks above -35 dBFS at the browser output and at least 6 dB over what
// the output carried just before it (Music and Ambience are muted for the test, so that is
// near silence: a sound cannot pass on a bed's say-so); no console errors. A DEBUG export.
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
const flag = (n, d) => (flags.find(f => f.startsWith(`--${n}=`)) || `--${n}=${d}`).split('=')[1];
const root = args[0];
const port = +flag('port', 10911);
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
await new Promise((res, rej) => { server.once('error', rej); server.listen(port, '127.0.0.1', res); });
const browser = await chromium.launch({ executablePath: '/usr/bin/chromium', headless: true,
  args: ['--use-angle=vulkan', '--enable-features=Vulkan', '--enable-unsafe-webgpu', '--ignore-gpu-blocklist', '--no-sandbox', '--autoplay-policy=no-user-gesture-required'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
const errors = [];
page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
page.on('pageerror', e => errors.push('pageerror: ' + e.message));
await page.addInitScript(() => {
  const taps = new WeakMap();
  const conn = AudioNode.prototype.connect;
  const tapFor = ctx => {
    if (!taps.has(ctx)) {
      const g = ctx.createGain(), an = ctx.createAnalyser();
      an.fftSize = 2048;
      conn.call(g, an); conn.call(an, ctx.destination);
      taps.set(ctx, { g, an });
      window.__tap = an;
    }
    return taps.get(ctx).g;
  };
  AudioNode.prototype.connect = function (dest, ...r) {
    if (dest instanceof AudioDestinationNode) {
      return conn.call(this, tapFor(this.context), ...r);
    }
    return conn.call(this, dest, ...r);
  };
  window.__lv = [];
  const buf = new Float32Array(2048);
  setInterval(() => {
    if (!window.__tap) return;
    window.__tap.getFloatTimeDomainData(buf);
    let s = 0, pk = 0;
    for (const v of buf) { s += v * v; pk = Math.max(pk, Math.abs(v)); }
    const a = window.__wake && window.__wake.audio;
    window.__lv.push([performance.now(), 10 * Math.log10(s / buf.length + 1e-12), 20 * Math.log10(pk + 1e-9), a && a.speaking ? 1 : 0, a ? (a.voice ? a.voice[0] : 0) : -1]);
  }, 50);
});
await page.goto(`http://127.0.0.1:${port}/index.html?start=test`);
await page.mouse.click(640, 360);
const sleep = ms => new Promise(r => setTimeout(r, ms));
for (let i = 0; i < 600 && !(await page.evaluate(() => !!window.wakeSfx)); i++) await sleep(100);
await sleep(5000);
await page.keyboard.press('KeyD');   // the audio unlock
for (let i = 0; i < 300 && !(await page.evaluate(() => window.__wake && window.__wake.audio && window.__wake.audio.unlocked)); i++) await sleep(100);
await sleep(4000);
// Music and Ambience muted: the rain's own peaks (-17 dBFS) would otherwise hide a quiet sound.
await page.evaluate(() => { window.wakeBus('Music', true); window.wakeBus('Ambience', true); });
await sleep(1500);
const SOUNDS = [
  ['jump', 'jump'], ['double jump', 'double_jump'], ['land', 'land'], ['land hard', 'land_hard'],
  ['footstep (concrete)', 'step_concrete'], ['footstep (metal)', 'step_metal'], ['crawl', 'crawl'],
  ['pad activate', 'pad_impact'], ['pad spring', 'pad_spring'], ['spring boost', 'spring_boost'],
  ['pad surge', 'pad_surge'], ['surge whoosh', 'surge_whoosh'], ['pickup', 'pickup_small'],
  ['pickup fish', 'pickup_fish'], ['laser zap', 'laser_zap'], ['laser fence hum (loop)', 'loop:laser_hum'],
  ['turret fire', 'turret_fire'], ['robot explosion', 'robot_explode'], ['crusher slam', 'crusher_slam'],
  ['hurt', 'hurt'], ['door open', 'door_open'], ['checkpoint', 'checkpoint'],
  ['meow: curious', 'meow:0'], ['meow: questioning mrrp', 'meow:1'], ['meow: trill', 'meow:2'],
  ['meow: uneasy', 'meow:3'], ['meow: small mew', 'meow:4'],
];
const rows = [];
for (const [label, name] of SOUNDS) {
  await sleep(1200);
  const t0 = await page.evaluate(() => performance.now());
  await sleep(1500);
  const t1 = await page.evaluate((n) => { const t = performance.now(); window.wakeSfx(n); return t; }, name);
  await sleep(name.startsWith('loop:') ? 3000 : 1800);
  rows.push({ label, name, t0, t1 });
}
const lv = await page.evaluate(() => window.__lv);
await browser.close(); server.close();
const pk = (a, b) => { const v = lv.filter(r => r[0] >= a && r[0] < b && r[1] > -90).map(r => r[2]); return v.length ? Math.max(...v) : -120; };
let ok = true;
console.log('sound'.padEnd(26) + 'pre-roll'.padStart(10) + 'sound peak'.padStart(12) + '  result');
for (const r of rows) {
  const bed = pk(r.t0, r.t1), snd = pk(r.t1, r.t1 + 1500);
  const pass = snd > -35 && snd >= bed + 6;
  ok = ok && pass;
  console.log(r.label.padEnd(26) + bed.toFixed(1).padStart(10) + snd.toFixed(1).padStart(12) + '  ' + (pass ? 'PASS' : 'FAIL'));
}
console.log(`${ok ? 'PASS' : 'FAIL'} every sound > -35 dBFS and >= pre-roll + 6 dB at the browser output`);
console.log(`${errors.length === 0 ? 'PASS' : 'FAIL'} console errors: ${errors.length}`);
for (const e of errors.slice(0, 5)) console.log('  ' + e);
process.exit(ok && errors.length === 0 ? 0 : 1);
