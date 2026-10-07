// What the browser actually OUTPUTS, next to what the game says: every connection into the
// AudioContext destination is routed through one tap (GainNode -> AnalyserNode), polled every
// 50 ms for RMS and peak. Runs Room 1 from the first black frame, presses a key (the audio
// unlock), waits for the awakening narration and reports the output level while a narrated
// line is on screen (window.__wake.audio.speaking) versus the beds alone.
//
//   node tools/audit/web_audio_levels.mjs <debug_export_dir> [--port=10910]
// Asserts: while speaking, output peak > -30 dBFS and the speaking RMS (90th percentile) is at least 6 dB above
// the bed-only RMS; no console errors. A DEBUG export (it reads window.__wake).
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
const port = +flag('port', 10910);
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
await page.goto(`http://127.0.0.1:${port}/index.html`);
await page.mouse.click(640, 360);
const sleep = ms => new Promise(r => setTimeout(r, ms));
for (let i = 0; i < 600 && !(await page.evaluate(() => !!window.wakeSay)); i++) await sleep(100);
await sleep(5000);            // the opening fades up
await page.keyboard.press('KeyD');   // the audio unlock
for (let i = 0; i < 300 && !(await page.evaluate(() => window.__wake && window.__wake.audio && window.__wake.audio.unlocked)); i++) await sleep(100);
await sleep(2500);            // the beds fade in
const bedFrom = await page.evaluate(() => window.__lv.length);
await sleep(8000);            // beds alone
const bedTo = await page.evaluate(() => window.__lv.length);
let sawVoice = 0;
const LINES = [['awakening', 1], ['awakening', 2]];
for (const [id, i] of LINES) {
  await page.evaluate(([id, i]) => window.wakeSay(id, i), [id, i]);
  await sleep(6500);
  sawVoice = await page.evaluate(() => window.__wake.audio.voice[0]);
}
const lv = await page.evaluate(() => window.__lv);
await browser.close(); server.close();
const db = a => 10 * Math.log10(a.reduce((s, v) => s + Math.pow(10, v / 10), 0) / Math.max(1, a.length));
// Windows below -90 dB are underruns of the software-rendered headless page, not sound: skipped.
const sp = lv.filter(r => r[3] === 1 && r[1] > -90), bedLate = lv.slice(bedFrom, bedTo).filter(r => r[3] === 0 && r[1] > -90);
const pct = (a, q) => { const v = a.map(r => r[1]).sort((x, y) => x - y); return v.length ? v[Math.floor((v.length - 1) * q)] : null; };
const out = {
  samples: lv.length, voiceLinesStarted: sawVoice,
  speaking: { n: sp.length, rms: sp.length ? +db(sp.map(r => r[1])).toFixed(1) : null, rmsP90: sp.length ? +pct(sp, 0.9).toFixed(1) : null, peak: sp.length ? +Math.max(...sp.map(r => r[2])).toFixed(1) : null },
  beds: { n: bedLate.length, rms: bedLate.length ? +db(bedLate.map(r => r[1])).toFixed(1) : null, peak: bedLate.length ? +Math.max(...bedLate.map(r => r[2])).toFixed(1) : null },
};
console.log(JSON.stringify(out));
const ok1 = out.speaking.peak !== null && out.speaking.peak > -30;
const ok2 = out.speaking.rmsP90 !== null && out.beds.rms !== null && out.speaking.rmsP90 >= out.beds.rms + 6;
console.log(`${ok1 ? 'PASS' : 'FAIL'} voice peak at the browser output > -30 dBFS while a line is spoken`);
console.log(`${ok2 ? 'PASS' : 'FAIL'} speaking RMS (90th percentile of the 50 ms windows) >= beds RMS + 6 dB`);
console.log(`${errors.length === 0 ? 'PASS' : 'FAIL'} console errors: ${errors.length}`);
for (const e of errors.slice(0, 5)) console.log('  ' + e);
process.exit(ok1 && ok2 && errors.length === 0 ? 0 : 1);
