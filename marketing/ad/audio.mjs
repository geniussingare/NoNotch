// Synthesizes the score and sound design for the film → <out.wav> (48 kHz stereo, 16-bit).
//   node audio.mjs out.wav
import { writeFileSync } from "node:fs";

const SR = 48000, DUR = 45, N = SR * DUR;
const L = new Float32Array(N), R = new Float32Array(N);       // dry bus
const RL = new Float32Array(N), RR = new Float32Array(N);     // reverb send
let seed = 1; const rnd = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296) * 2 - 1;
const TAU = Math.PI * 2;

function add(t0, dur, fn, { gain = 1, pan = 0, send = 0 } = {}) {
  const s0 = Math.max(0, Math.round(t0 * SR)), s1 = Math.min(N, Math.round((t0 + dur) * SR));
  const gl = gain * Math.cos((pan + 1) * Math.PI / 4) * Math.SQRT2, gr = gain * Math.sin((pan + 1) * Math.PI / 4) * Math.SQRT2;
  for (let i = s0; i < s1; i++) {
    const v = fn((i - s0) / SR, i / SR);
    L[i] += v * gl; R[i] += v * gr;
    if (send) { RL[i] += v * gl * send; RR[i] += v * gr * send; }
  }
}
const env = (t, a, d) => (t < a ? t / a : Math.exp(-(t - a) * d));
const tri = (x) => 2 / Math.PI * Math.asin(Math.sin(x));

// ---- Instruments ----
// Pitch sweeps 156 → 46 Hz; the phase is the integral of that sweep.
const kick = (t0, g = 1) => add(t0, .5, (t) => Math.sin(TAU * (46 * t + (110 / 32) * (1 - Math.exp(-t * 32)))) * Math.exp(-t * 6.5) * Math.min(1, t / .002) + rnd() * Math.exp(-t * 400) * .3, { gain: .9 * g });
const hat = (t0, g = 1, pan = .25) => { let p = 0; add(t0, .07, (t) => { const n = rnd(); const v = n - p; p = n; return v * Math.exp(-t * 70); }, { gain: .09 * g, pan }); };
const clap = (t0) => { let p = 0; add(t0, .3, (t) => { const n = rnd(); const v = (n - p * .6); p = n; const e = Math.exp(-((t % .011) < .011 && t < .03 ? (t % .011) : t) * 22); return v * e; }, { gain: .22, send: .35 }); };
function bass(t0, f, dur, g = 1) {
  add(t0, dur, (t) => { let v = 0; for (let k = 1; k <= 5; k++) v += Math.sin(TAU * f * k * t) / (k * k * .7 + .3); const e = Math.min(1, t / .008) * Math.min(1, (dur - t) / .05) * (0.75 + .25 * Math.exp(-t * 6)); return v * e; }, { gain: .2 * g });
}
function pad(t0, freqs, dur, g = 1, bright = 1) {
  freqs.forEach((f, j) => {
    add(t0, dur + 1.2, (t) => {
      const a = Math.min(1, t / .7) * (t > dur ? Math.exp(-(t - dur) * 3) : 1);
      let v = 0; for (const d of [-0.07, 0, 0.065]) v += tri(TAU * f * (1 + d / 100 * 9) * t + j) * .5 + Math.sin(TAU * f * 2 * (1 + d / 100) * t) * .12 * bright;
      return v * a * (0.9 + .1 * Math.sin(TAU * .3 * t + j));
    }, { gain: .045 * g, pan: (j - 1) * .45, send: .55 });
  });
}
const pluck = (t0, f, g = 1, pan = 0) => add(t0, 1.2, (t) => (Math.sin(TAU * f * t) + .35 * Math.sin(TAU * f * 2 * t) + .12 * Math.sin(TAU * f * 3 * t)) * Math.exp(-t * 7) * Math.min(1, t / .003), { gain: .07 * g, pan, send: .45 });
const chime = (t0, f, g = 1, pan = 0) => add(t0, 2.5, (t) => (Math.sin(TAU * f * t) + .4 * Math.sin(TAU * f * 2.76 * t) * Math.exp(-t * 4) + .2 * Math.sin(TAU * f * 5.4 * t) * Math.exp(-t * 9)) * Math.exp(-t * 2.4) * Math.min(1, t / .002), { gain: .1 * g, pan, send: .7 });
const tick = (t0, g = 1, f = 2300, pan = 0) => add(t0, .06, (t) => (Math.sin(TAU * f * t) * .7 + rnd() * .5) * Math.exp(-t * 110), { gain: .16 * g, pan, send: .15 });
const click = (t0, g = 1, pan = 0) => add(t0, .03, (t) => (rnd() * .6 + Math.sin(TAU * 1500 * t)) * Math.exp(-t * 260), { gain: .22 * g, pan });
function whoosh(t0, dur, rising = true, g = 1, pan = 0) {
  let lp = 0, lp2 = 0;
  add(t0, dur, (t) => {
    const p = t / dur; const sh = rising ? p * p : (1 - p) * (1 - p) * Math.min(1, t / .03);
    const c = .02 + .5 * (rising ? p * p : 1 - p);
    lp += (rnd() - lp) * c; lp2 += (lp - lp2) * c;
    return lp2 * sh * 2.2;
  }, { gain: .5 * g, pan, send: .4 });
}
const boom = (t0, g = 1) => { let lp = 0; add(t0, 3, (t) => { lp += (rnd() - lp) * .03; return Math.sin(TAU * (38 * t + 2 * (1 - Math.exp(-t * 8)))) * Math.exp(-t * 1.6) * 1.1 + lp * Math.exp(-t * 3) * 1.5; }, { gain: .8 * g, send: .3 }); };
const bonk = (t0) => add(t0, .4, (t) => { const f = 210 - 50 * t; return Math.tanh(Math.sin(TAU * f * t) * 3) * Math.exp(-t * 9); }, { gain: .14, send: .2 });
const snap = (t0) => { add(t0, .3, (t) => Math.sin(TAU * (70 + 120 * Math.exp(-t * 40)) * t) * Math.exp(-t * 16), { gain: .55 }); chime(t0 + .01, 2637, .6, .1); };
const thud = (t0) => add(t0, 1.2, (t) => Math.sin(TAU * (42 + 40 * Math.exp(-t * 12)) * t) * Math.exp(-t * 3.2), { gain: .6, send: .25 });

// ---- Score ----
const BEAT = 60 / 110, BAR = BEAT * 4, T0 = 10.6;
const CH = [ // Am, F, C, G
  { root: 55, tones: [220, 261.63, 329.63], arp: [440, 523.25, 659.25, 880] },
  { root: 43.65, tones: [174.61, 220, 261.63], arp: [349.23, 440, 523.25, 698.46] },
  { root: 65.41, tones: [261.63, 329.63, 392], arp: [523.25, 659.25, 783.99, 1046.5] },
  { root: 49, tones: [196, 246.94, 293.66], arp: [392, 493.88, 587.33, 783.99] },
];

// Hook + friction drone (A minor, dark), fades in, cuts at 9.6
add(0, 9.62, (t) => { const a = Math.min(1, t / 2.5) * Math.min(1, (9.62 - t) / .02) * (1 + .6 * Math.min(1, Math.max(0, (t - 3) / 6)));
  return (Math.sin(TAU * 55 * t) * .6 + Math.sin(TAU * 82.41 * t) * .25 + Math.sin(TAU * 110.3 * t) * .12 * Math.sin(TAU * .4 * t)) * a; }, { gain: .22, send: .2 });
tick(2.62, 1.3, 3200); chime(2.62, 3520, .35);                         // outline locks
// Friction: clock ticking faster + rushed clicks + error bonk
for (let t = 3.4, gap = .5; t < 9.55; t += gap, gap = Math.max(.09, gap * .93)) tick(t, .8, 1700, Math.sin(t * 3) * .3);
[3.3, 3.5, 3.7, 3.9, 4.1].forEach((t, i) => click(t, .9, (i - 2) * .2));  // windows popping
[4.2, 4.8, 5.5, 6.1, 6.6, 7.25].forEach((t) => click(t + .02, .7, .2));
whoosh(6.3, .45, true, .35, .7); whoosh(7.35, .4, false, .3, .7);         // banner in/out
bonk(7.95);
// Silence, then reverse whoosh into the drop
whoosh(9.9, .72, true, 1.1);
boom(T0, .9);

// Main groove 10.6 → 35.0
const grooveEnd = 35.0;
for (let b = 0; T0 + b * BEAT < grooveEnd - .01; b++) {
  const t = T0 + b * BEAT, bar = Math.floor(b / 4), ch = CH[bar % 4];
  kick(t, b % 4 === 0 ? 1 : .85);
  hat(t + BEAT / 2, 1, .3); if (t > 17) hat(t + BEAT * .75, .5, -.3);
  if (t > 17 && b % 2 === 1) clap(t);
  bass(t, ch.root, BEAT * .45); bass(t + BEAT / 2, ch.root * (b % 2 ? 2 : 1), BEAT * .4, .8);
  if (b % 4 === 0) pad(t, ch.tones, BAR - .05, 1);
  if (t > 17) for (let k = 0; k < 2; k++) pluck(t + k * BEAT / 2, ch.arp[(b * 2 + k) % 4], .9, ((b * 2 + k) % 4 - 1.5) * .3);
}
// UI sound design
chime(10.7, 1318.5, .5, -.2); chime(10.85, 1975.5, .4, .2);              // island blooms
click(17.55, 1); chime(17.62, 1567.98, .4);                            // open player
[18.6, 19.55, 20.5].forEach((t, i) => chime(t, [2093, 2349.3, 2637][i], .25, (i - 1) * .4));  // lyric shimmers
whoosh(21.7, .35, false, .4); click(22.55, 1); chime(22.6, 1760, .3, .3);
whoosh(23.9, .3, false, .4);
[[24.45, [1046.5, 1318.5], -.5], [26.15, [783.99, 987.77], .5], [27.9, [1318.5, 1567.98], -.4], [29.15, [880, 1046.5], .4]]
  .forEach(([t, fs, pan]) => { fs.forEach((f, i) => chime(t + i * .07, f, .7, pan)); });
[25.95, 27.65, 28.95].forEach((t) => whoosh(t - .25, .35, false, .35));
click(29.55, 1);
click(30.25, .8); whoosh(30.3, .65, true, .45); snap(31.0);
click(32.95, 1.1, -.3); click(33.45, 1.1, 0); click(34.0, 1.2, .3); thud(34.0);

// Payoff: drums out, warm pad + soft bass
pad(35.0, [220, 261.63, 329.63, 493.88], 5.2, 1.2, .5);
bass(35.0, 55, 5.2, .55);
chime(35.1, 1318.5, .35);
// CTA: final hit, sustained chord, glass ting
boom(40.3, 1);
pad(40.3, [220, 329.63, 493.88, 659.25], 3.6, 1.1, .7);
bass(40.3, 55, 3.8, .5);
chime(43.5, 2093, .9, 0); chime(43.56, 3135.96, .5, .2);

// ---- Reverb (Schroeder: 4 combs + 2 allpasses per channel) ----
function reverb(inp, offs) {
  const out = new Float32Array(N);
  const combs = [1557, 1617, 1491, 1422].map((d) => ({ b: new Float32Array(d + offs), i: 0, f: 0 }));
  const aps = [556, 441].map((d) => ({ b: new Float32Array(d + offs), i: 0 }));
  for (let n = 0; n < N; n++) {
    let s = 0;
    for (const c of combs) { const y = c.b[c.i]; c.f = y * .75 + c.f * .25; c.b[c.i] = inp[n] + c.f * .84; c.i = (c.i + 1) % c.b.length; s += y; }
    for (const a of aps) { const y = a.b[a.i]; const v = -s + y; a.b[a.i] = s + y * .5; a.i = (a.i + 1) % a.b.length; s = v; }
    out[n] = s * .25;
  }
  return out;
}
const wl = reverb(RL, 0), wr = reverb(RR, 23);

// ---- Master: sum, soft clip, fade, normalise ----
let peak = 0;
for (let i = 0; i < N; i++) {
  const t = i / SR; const fade = Math.min(1, (45 - t) / .45, 1);
  L[i] = Math.tanh((L[i] + wl[i]) * 1.1) * Math.max(0, fade); R[i] = Math.tanh((R[i] + wr[i]) * 1.1) * Math.max(0, fade);
  peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]));
}
const g = .89 / peak;
const buf = Buffer.alloc(44 + N * 4);
buf.write("RIFF", 0); buf.writeUInt32LE(36 + N * 4, 4); buf.write("WAVEfmt ", 8); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20);
buf.writeUInt16LE(2, 22); buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 4, 28); buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34);
buf.write("data", 36); buf.writeUInt32LE(N * 4, 40);
for (let i = 0; i < N; i++) { buf.writeInt16LE(Math.round(L[i] * g * 32767), 44 + i * 4); buf.writeInt16LE(Math.round(R[i] * g * 32767), 46 + i * 4); }
writeFileSync(process.argv[2] || "music.wav", buf);
console.log("wrote", process.argv[2] || "music.wav");
