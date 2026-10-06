// Shared by the web audits: what the browser is really playing, next to what the game says.
// Godot's web export plays audio as SAMPLES by default: every AudioStreamPlayer becomes a
// Web Audio AudioBufferSourceNode. This installs a probe (page.addInitScript, before the game
// loads) that tracks the looping ones that are started and not yet stopped, so a loop that the
// game freed but the browser kept playing cannot hide behind the node count.
//
//   import { installAudioProbe, audioLoops } from './web_audio_probe.mjs';
//   await installAudioProbe(page);          // before page.goto
//   const a = await audioLoops(page);       // {loops, sources, ctx}
//
// The game publishes window.__wake.loops (and window.__map.loops) = LoopSfx.census():
//   playing    looping AudioStreamPlayer nodes that are playing, anywhere in the tree
//   orphans    ... of those, the ones outside the current scene (the leak; must be 0)
//   positional the distance-faded LoopSfx loops that are audible now (drones, scanner)
// LoopSfx players are forced to stream playback (an AudioWorklet), so they are not sources
// here: the probe's loops must therefore be <= playing - positional.
export async function installAudioProbe(page) {
  await page.addInitScript(() => {
    const active = new Set();
    const P = window.AudioBufferSourceNode && AudioBufferSourceNode.prototype;
    if (!P) return;
    const start = P.start, stop = P.stop;
    P.start = function (...a) {
      this.__t0 = this.context.currentTime;
      this.__dur = this.buffer ? this.buffer.duration : 0;
      active.add(this);
      this.addEventListener('ended', () => active.delete(this));
      return start.apply(this, a);
    };
    P.stop = function (...a) {
      active.delete(this);
      return stop.apply(this, a);
    };
    // `audible` = sources that have not yet run past the end of their buffer (a looping one never does);
    // the rest are finished sources the browser never reported as ended.
    window.__audioDump = () => [...active].map(s => ({ t0: s.__t0, dur: s.__dur, loop: s.loop, now: s.context.currentTime, state: s.context.state, rate: s.playbackRate.value }));
    window.__audioProbe = () => {
      const now = [...active][0] ? [...active][0].context.currentTime : 0;
      const live = [...active].filter(s => s.loop || (now - s.__t0) < s.__dur + 0.25);
      return { sources: active.size, audible: live.length, loops: live.filter(s => s.loop).length, ctx: window.AudioContext ? 'AudioContext' : 'none' };
    };
  });
}

export async function audioLoops(page) {
  return await page.evaluate(() => (window.__audioProbe ? window.__audioProbe() : { sources: -1, audible: -1, loops: -1, ctx: 'no probe' }));
}

// The assertion every web audit uses: no looping player outside the current scene, and the
// browser plays nothing the game does not know about: the sample sources it has running
// that are still SOUNDING (not past the end of their buffer: Godot sets a loop on the sample, not
// on the node, so `loops` reads 0) are at most the looping players the tree has playing, plus one
// for a one-shot that is still ringing. `sources` also counts finished ones the browser never
// reported ended (see audio_probe notes in the report: footsteps restart one player).
// `L` is a census ({playing, orphans, positional}).
// `slack`: how many one-shots may be ringing besides the known loops (1; a room with a dense one-shot
// bed, such as Room 4's sparks and rain, passes more: the dump shows they are all short, none looping).
export function soundClean(L, a, slack = 1) {
  const known = L.playing - L.positional;
  const orphanFree = L.orphans === 0;
  const browserFree = a.audible < 0 || a.audible <= known + slack;
  return { ok: orphanFree && browserFree, detail: `tree: playing ${L.playing} orphans ${L.orphans} positional ${L.positional}; browser sources ${a.sources} (still sounding ${a.audible})` };
}
