// Smoke test of the RELEASE web export (the itch.io build) inside an iframe at 1280x720: the loading bar,
// the intro, keyboard input, audio after the first input, 0 console errors, and that none of the debug
// hooks exist or respond (window.wake* / __wake / __map / __goo, the ?start= / ?x= / ... query parameters,
// the F1-F6 hotkeys).
//
//   node tools/audit/web_release_smoke.mjs <release_export_dir> <out_dir> [--port=10830] [--gpu=swiftshader]
//
// <release_export_dir> is made by tools/export_web.sh release <dir>. Needs the playwright package (PW_DIR env)
// and /usr/bin/chromium.
import { createRequire } from 'node:module';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { installAudioProbe } from './web_audio_probe.mjs';

const PW = process.env.PW_DIR
  || path.join(os.homedir(), '.local/share/mise/installs/npm-playwright/latest/node_modules/playwright');
const { chromium } = createRequire(import.meta.url)(PW);
const args = process.argv.slice(2).filter(a => !a.startsWith('--'));
const flags = process.argv.slice(2).filter(a => a.startsWith('--'));
const [root, outdir] = args;
fs.mkdirSync(outdir, { recursive: true });
const gpu = (flags.find(f => f.startsWith('--gpu=')) || '--gpu=vulkan').split('=')[1];
const port = +((flags.find(f => f.startsWith('--port=')) || '--port=10830').split('=')[1]);
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.png': 'image/png' };
const QUERY = 'start=room4&x=900&shock=1&power=1&keys=red&show=1&noloop=1&completed=room1';
const missing = [];
const server = http.createServer((q, r) => {
  const u = q.url.split('?')[0];
  if (u === '/favicon.ico') { r.writeHead(204); r.end(); return; }   // the harness page, not the game
  if (u === '/wrap.html') {
    r.writeHead(200, { 'Content-Type': 'text/html' });
    r.end(`<!doctype html><body style="margin:0;background:#000"><iframe id="g" src="/index.html?${QUERY}" width="1280" height="720" style="border:0" allow="autoplay; fullscreen"></iframe></body>`);
    return;
  }
  const p = path.join(root, decodeURIComponent(u));
  fs.readFile(p, (e, d) => {
    if (e) { missing.push(u); r.writeHead(404); r.end(); return; }
    r.writeHead(200, { 'Content-Type': MIME[path.extname(p)] || 'application/octet-stream' });
    // The pck is held back a moment so the loading bar can be seen on a local disk.
    if (u.endsWith('.pck')) setTimeout(() => r.end(d), 2500); else r.end(d);
  });
});
await new Promise((res, rej) => { server.once('error', rej); server.listen(port, '127.0.0.1', res); });

const launchArgs = gpu === 'swiftshader'
  ? ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader']
  : ['--use-angle=vulkan', '--enable-features=Vulkan', '--enable-unsafe-webgpu'];
const browser = await chromium.launch({ executablePath: '/usr/bin/chromium', headless: true, args: [...launchArgs, '--ignore-gpu-blocklist', '--no-sandbox'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
await page.addInitScript(() => {
  // The WebAudio destination tap (as in web_audio_levels.mjs): what the browser OUTPUTS.
  const taps = new WeakMap(), conn = AudioNode.prototype.connect;
  window.__lv = [];
  AudioNode.prototype.connect = function (dest, ...r) {
    if (dest instanceof AudioDestinationNode) {
      if (!taps.has(this.context)) {
        const g = this.context.createGain(), an = this.context.createAnalyser();
        an.fftSize = 2048; conn.call(g, an); conn.call(an, this.context.destination);
        taps.set(this.context, g); window.__tap = an;
      }
      return conn.call(this, taps.get(this.context), ...r);
    }
    return conn.call(this, dest, ...r);
  };
  const buf = new Float32Array(2048);
  setInterval(() => {
    if (!window.__tap) return;
    window.__tap.getFloatTimeDomainData(buf);
    let pk = 0; for (const v of buf) pk = Math.max(pk, Math.abs(v));
    window.__lv.push([performance.now(), 20 * Math.log10(pk + 1e-9)]);
  }, 50);
});
await installAudioProbe(page);
const errors = [];
page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
page.on('pageerror', e => errors.push('pageerror: ' + e.message));
const sleep = ms => new Promise(r => setTimeout(r, ms));
let bad = 0;
function note(name, ok, detail = '') { if (!ok) bad++; console.log(`${ok ? 'PASS' : 'FAIL'}  ${name.padEnd(70)} ${detail}`); }
const shot = n => page.screenshot({ path: `${outdir}/${n}.png` });

await page.goto(`http://127.0.0.1:${port}/wrap.html`);
const frameEl = await page.waitForSelector('#g');
const frame = await frameEl.contentFrame();
// The loading bar: Godot's HTML shell shows #status-progress while the pck downloads.
let bar = false;
for (let i = 0; i < 400 && !bar; i++) {
  bar = await frame.evaluate(() => { const p = document.getElementById('status-progress'); return !!p && getComputedStyle(p).display !== 'none' && p.offsetWidth > 0; }).catch(() => false);
  if (!bar) await sleep(10);
}
note('loading bar shown while the game loads', bar);
await shot('01_loading');
console.log('[missing urls]', missing.join(' ') || 'none');
await frame.waitForFunction(() => { const s = document.getElementById('status'); return !s || s.style.visibility === 'hidden' || getComputedStyle(s).display === 'none'; }, null, { timeout: 120000 });
await sleep(2500);
await shot('02_before_click');
await page.mouse.click(640, 360);
await sleep(300);
const hooks = await frame.evaluate(() => ['wakeTeleport', 'wakeFx', 'wakeStrike', 'wakePower', 'wakeShock', 'wakeKey', '__wake', '__map', '__goo'].filter(k => k in window));
note('no debug hook exists on window', hooks.length === 0, hooks.join(','));
await sleep(6000);
await shot('03_intro');
// Keyboard input: the intro ends on movement input and the cat then walks; the picture must change.
const a = await page.screenshot();
for (const k of ['F1', 'F2', 'F3', 'F4', 'F5', 'F6', 'BracketRight']) { await page.keyboard.press(k); await sleep(80); }
await sleep(500);
const b = await page.screenshot();
await page.keyboard.down('KeyD'); await sleep(2500); await page.keyboard.up('KeyD');
const tJump = await frame.evaluate(() => performance.now());
await page.keyboard.down('Space'); await sleep(300); await page.keyboard.up('Space');
await sleep(1500);
await shot('04_after_input');
const c = await page.screenshot();
note('the intro / the game is running (the picture animates)', !a.equals(b) || !b.equals(c));
const probe = await frame.evaluate(() => ({ p: window.__audioProbe ? window.__audioProbe() : null, ctx: (window.GodotAudio && GodotAudio.ctx && GodotAudio.ctx.state) || null }));
const lv = await frame.evaluate(() => window.__lv);
const outPk = lv.length ? Math.max(...lv.map(r => r[1])) : -120;
const around = (a, b) => { const v = lv.filter(r => r[0] >= a && r[0] < b).map(r => r[1]); return v.length ? Math.max(...v) : -120; };
console.log(`[output peaks, dBFS] whole run ${outPk.toFixed(1)}; 2 s of walking before the jump ${around(tJump - 2000, tJump).toFixed(1)}; the 0.6 s from the jump ${around(tJump, tJump + 600).toFixed(1)}`);
// Audible at the browser output (the tap), not merely "a sample source exists": the one-shots
// are only played near the cat now, so a source count is a coin toss.
note('audio is playing after input (output peak > -40 dBFS)', outPk > -40, JSON.stringify({ outPk, probe }));
const hooks2 = await frame.evaluate(() => ['wakeTeleport', 'wakeFx', 'wakeStrike', 'wakePower', 'wakeShock', 'wakeKey', '__wake', '__map', '__goo'].filter(k => k in window));
note('still no debug hook after play (F1-F6 pressed, deep-link query ignored)', hooks2.length === 0, hooks2.join(','));
console.log('[missing urls]', missing.join(' ') || 'none');
note('0 console errors', errors.length === 0, errors.slice(0, 3).join(' | '));
await browser.close();
server.close();
console.log(bad ? `${bad} FAILED` : 'ALL PASSED');
process.exit(bad ? 1 : 0);
