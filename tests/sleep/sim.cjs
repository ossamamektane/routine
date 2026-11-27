// Simulates many lifestyles to fit and test the "Did you sleep?" estimator.
process.env.TZ = 'UTC';
const fs = require('fs'), vm = require('vm');
const ctx = vm.createContext({ console, Math, Date, JSON, Intl });
vm.runInContext(fs.readFileSync(require('path').join(__dirname, '../../model.js'), 'utf8') + '\nthis.SleepAI = SleepAI; this.Sleep = Sleep; this.minOfDay = minOfDay;', ctx);
const { SleepAI, Sleep } = ctx;
const DEBUG = !!process.env.DEBUG; let MANUAL = 0.3; const APPFIND = !process.env.INLINE; const H = 3600e3, M = 60e3, DAY = 864e5;
let seed = 1; const rnd = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; };
const N = (m, sd) => { let u = 0, v = 0; while (!u) u = rnd(); v = rnd(); return m + sd * Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v); };
const U = (a, b) => a + (b - a) * rnd();
const T0 = Date.UTC(2026, 0, 5);
// Next moment after `after` whose clock time is near `minute` (+/- sd minutes), at least `gap` later.
const clock = (after, minute, sd, gap = 2 * H) => { let t = Math.floor((after + gap) / DAY) * DAY + N(minute, sd) * M; while (t < after + gap) t += DAY; return t; };
// Each persona: sleeps(t) -> next sleep {s, e} after being up since t; rate (app opens per awake hour); quiet blocks; peeks per sleep.
const P = {
  office: { rate: 1.5, peek: 0.1, next: (t, day) => { const wk = Math.floor((t - T0) / DAY) % 7 >= 5; const s = clock(t, (wk ? 25 : 23.5) * 60, 40, 10 * H); return [s, s + N(wk ? 9 : 7.5, 0.7) * H]; } },
  nightShift: { rate: 1, peek: 0.1, next: (t) => { const s = clock(t, 8.5 * 60, 45, 10 * H); return [s, s + N(7, 1) * H]; } },
  rotating: { rate: 1.2, peek: 0.1, next: (t) => { const night = Math.floor((t - T0) / (7 * DAY)) % 2 === 1; const s = clock(t, night ? 8.5 * 60 : 23 * 60, 45, 8 * H); return [s, s + N(7, 0.8) * H]; } },
  rapper: { rate: 2, peek: 0.15, next: (t) => { const s = clock(t, 4.5 * 60, 120, 9 * H); return [s, s + Math.max(4, N(8, 2)) * H]; } },
  binge: { rate: 0.5, peek: 0.05, quiet: [1, 3, 8], next: (t) => { const s = t + U(18, 44) * H; return [s, s + U(7, 16) * H]; } },
  delivery: { rate: 1, peek: 0.1, quiet: [1, 2, 4], next: (t) => { const h = (t % DAY) / H; if (h > 8 && h < 14 && rnd() < 0.5) { const s = clock(t, 14.5 * 60, 30, 5 * H); return [s, s + U(1.3, 2.2) * H]; } const s = clock(t, 60, 40, 6 * H); return [s, s + N(5, 0.6) * H]; } },
  businessman: { rate: 0.5, peek: 0.05, quiet: [2, 4, 8], next: (t) => { const s = clock(t, 30, 30, 12 * H); return [s, s + N(5, 0.4) * H]; } },
  dealer: { rate: 1.2, peek: 0.2, next: (t) => { const s = t + U(6, 12) * H; return [s, s + U(3, 5) * H]; } },
  newParent: { rate: 1.3, peek: 0.6, wakes: 2, next: (t) => { const s = clock(t, 22.5 * 60, 30, 10 * H); return [s, s + N(8, 0.5) * H]; } },
  student: { rate: 2, peek: 0.15, next: (t) => { const wk = Math.floor((t + 6 * H - T0) / DAY) % 7 >= 5; const s = clock(t, wk ? 3.5 * 60 : 60, 60, 10 * H); return [s, s + (wk ? N(8.5, 1) : N(7, 0.8)) * H]; } },
  insomniac: { rate: 1.3, peek: 0.3, next: (t) => { const extra = rnd() < 0.2 ? DAY : 0; const s = clock(t, 2 * 60, 90, 12 * H) + extra; return [s, s + U(3.2, 5) * H]; } },
  earlyNapper: { rate: 1, peek: 0.1, next: (t) => { const h = (t % DAY) / H; if (h > 4 && h < 12 && rnd() < 0.7) { const s = clock(t, 13 * 60, 20, 4 * H); return [s, s + U(0.7, 1.4) * H]; } const s = clock(t, 21 * 60, 30, 5 * H); return [s, s + N(8, 0.5) * H]; } }
};
// Builds sleeps and app sessions for `days` days.
function timeline(p, days) {
  const sleeps = [], sessions = [];
  let t = T0 + 8 * H;
  while (t < T0 + days * DAY) {
    const [s, e] = p.next(t);
    // Awake from t to s: app opens (some quiet blocks with none).
    let quietLeft = p.quiet && rnd() < 0.7 ? U(p.quiet[1], p.quiet[2]) * H : 0, quietAt = U(t, s);
    let a = t + U(0, 20) * M;
    while (a < s) {
      if (quietLeft && a > quietAt && a < quietAt + quietLeft) { a = quietAt + quietLeft; continue; }
      sessions.push({ t: a, len: U(1, 8) * M }); a += -Math.log(1 - rnd()) / p.rate * H + 5 * M;
    }
    const main = e - s >= 3 * H;
    sleeps.push({ s, e, main });
    // Peeks at the phone mid-sleep (and night wakes for new parents).
    const peeks = (p.wakes || 0) + (rnd() < p.peek ? 1 : 0);
    for (let k = 0; k < peeks; k++) { const at = U(s + 1.5 * H, e - 1 * H); if (at > s && at < e) sessions.push({ t: at, len: U(1, 3) * M, peek: true }); }
    // First open after waking: soon (or hours later for some).
    const first = e + (rnd() < 0.75 ? U(1, 30) * M : U(1, 5) * H);
    sessions.push({ t: first, len: U(2, 8) * M });
    t = e;
    if (first > t) t = Math.min(first, e + 60 * M) - 0; // keep the next sleep after waking
    t = e + 30 * M;
  }
  sessions.sort((x, y) => x.t - y.t);
  // Merge overlapping sessions.
  const out = [];
  for (const s of sessions) { const last = out[out.length - 1]; if (last && s.t <= last.t + last.len) { last.len = Math.max(last.len, s.t + s.len - last.t); last.peek = last.peek && s.peek; } else out.push({ ...s }); }
  return { sleeps, sessions: out };
}
// Runs the app's decision at every app open, answering truthfully. Collects clues and outcomes.
// mode: "new" (estimator + look back) or "old" (current rules).
function run(name, days, collect, mode = "new") {
  const p = P[name], { sleeps, sessions } = timeline(p, days);
  const log = Sleep.newLog(); log.sleeps = []; log.awakeGaps = []; log.bias = 0;
  let lastWake = null, dismissedUntil = 0; const handled = new Set();
  const r = { sleeps: 0, first: 0, late: 0, falseAsk: 0, peekAsk: 0, guessErr: [], lateBy: [], days };
  const inSleep = (t) => sleeps.some((z) => t > z.s && t < z.e);
  const ends = []; // session ends so far (for looking back)
  for (const z of sleeps) if (z.main) r.sleeps++;
  const firstSeen = new Map();
  for (const ses of sessions) {
    const t = ses.t;
    if (ends.length) {
      const lastUse = ends[ends.length - 1].end;
      const awakeNow = !inSleep(t);
      for (const z of sleeps) if (z.main && z.e <= t && awakeNow && !firstSeen.has(z)) firstSeen.set(z, t);
      const skip = (lastWake != null && lastWake > lastUse) || t < dismissedUntil || t < (log.quietUntil || 0);
      if (!skip) {
        // Brief looks at the phone (a few minutes, after a long quiet) count as part of the same sleep.
        const anchor0 = Math.max(lastWake || 0, log.stillUpAt || 0);
        let chain = lastUse, looks = 0;
        for (let k = ends.length - 1; k > 0; k--) {
          const e = ends[k];
          if (e.end - e.start > SleepAI.briefLook * M || e.start - ends[k - 1].end < 90 * M || (k + 1 < ends.length ? ends[k + 1].start : t) - e.end < 90 * M || ends[k - 1].end <= anchor0 || t - ends[k - 1].end > 20 * H) break;
          chain = ends[k - 1].end; looks++;
        }
        let from = log.stillUpAt != null && log.stillUpAt > chain ? log.stillUpAt : chain, to = t, pr;
        const prof = SleepAI.profile(log);
        if (mode === "old") pr = Sleep.shouldAsk(log, lastUse, t, lastWake, 0) ? 1 : 0;
        else {
          if (collect && t - from >= SleepAI.minQuiet * M) { const pending = sleeps.some((z) => z.main && z.e > from && z.e <= t && !handled.has(z)); collect.push({ x: SleepAI.clues(prof, from, t, lastWake, 0, looks), y: awakeNow && pending ? 1 : 0, b: prof.bias }); }
          // The app's own code: SleepAI.find on the uses so far.
          log.spans = ends.map((e) => ({ start: e.start, end: e.end }));
          const f = SleepAI.find(log, t, lastWake, 0);
          pr = f ? 1 : 0; if (f) { from = f.from; to = f.to; }
          if (APPFIND) { /* skip the inline look back below */ } else pr = SleepAI.chance(prof, from, t, lastWake, 0, looks);
          // Look back: an earlier quiet stretch since your day started that looks like a sleep you never told Routine about.
          if (!APPFIND && pr < SleepAI.threshold) {
            const anchor = Math.max(lastWake || 0, log.stillUpAt || 0);
            for (let k = ends.length - 1; k > 0 && ends[k].start > anchor; k--) {
              const gs = Math.max(ends[k - 1].end, anchor), ge = ends[k].start;
              if (ge - gs < SleepAI.minQuiet * M) continue;
              const q = SleepAI.chance(prof, gs, ge, lastWake, 0);
              if (q >= SleepAI.lookBack) { from = gs; to = ge; pr = q; break; }
            }
          }
        }
        if (DEBUG && pr < SleepAI.threshold && awakeNow) { const pend = sleeps.filter((z) => z.main && z.e > lastUse - 0 && z.e <= t && !handled.has(z)); if (pend.length) { const z = pend[pend.length - 1]; console.log('MISS', new Date(t).toISOString().slice(5,16), 'sleep', new Date(z.s).toISOString().slice(11,16), ((z.e - z.s) / H).toFixed(1) + 'h', 'gap', ((t - from) / H).toFixed(1), 'looks', looks, 'p', pr.toFixed(2), 'L', (prof.L/60).toFixed(1), 'awakeLong', prof.awakeLong, 'x', SleepAI.clues(prof, from, t, lastWake, 0, looks).map((v) => +v.toFixed(2)).join(',')); } }
        if (pr >= SleepAI.threshold) {
          const ended = sleeps.filter((z) => z.main && z.e > from && z.e <= to && !handled.has(z));
          if (awakeNow && ended.length) {
            const z = ended[ended.length - 1];
            if (mode !== "old") { const g = SleepAI.guessWake(prof, from, to); r.guessErr.push(Math.abs(g - z.e) / M); }
            if (firstSeen.get(z) === t) r.first++; else { r.late++; r.lateBy.push((t - firstSeen.get(z)) / H); }
            for (const q of ended) handled.add(q);
            SleepAI.learnSleep(log, from, z.e); Sleep.learnWake(log, z.e);
            if (lastWake != null && from > lastWake) Sleep.learnDay(log, Math.floor((from - lastWake) / M));
            lastWake = z.e; log.stillUpAt = null;
          } else if (!awakeNow) { r.peekAsk++; if (!SleepAI.notYet(log, prof, from, to, t)) log.stillUpAt = t; }
          else { if (DEBUG) console.log('FALSE', new Date(t).toISOString().slice(5,16), 'gap', ((to - from) / H).toFixed(1), 'p', pr.toFixed(2)); r.falseAsk++; if (!SleepAI.notYet(log, prof, from, to, t)) log.stillUpAt = t; }
        }
      }
    }
    // You notice Routine missed your sleep ("Up for 20h") and set your wake-up time yourself, sometimes.
    if (MANUAL && !inSleep(t) && (lastWake == null || lastWake <= (ends.length ? ends[ends.length - 1].end : 0))) {
      const pend = sleeps.filter((z) => z.main && z.e <= t && z.e > (lastWake || 0) && !handled.has(z));
      if (pend.length && rnd() < MANUAL) {
        const z = pend[pend.length - 1]; for (const q of pend) handled.add(q);
        let before = null; for (const e of ends) if (e.end <= z.e) before = e.end;
        if (before != null) SleepAI.learnSleep(log, before, z.e, true);
        Sleep.learnWake(log, z.e); lastWake = z.e; log.stillUpAt = null; r.manual = (r.manual || 0) + 1;
      }
    }
    ends.push({ start: t, end: t + ses.len });
  }
  return r;
}
const summary = (r) => ({ sleeps: r.sleeps, right: Math.round(100 * r.first / r.sleeps) + "%", late: Math.round(100 * r.late / r.sleeps) + "%", never: Math.round(100 * (r.sleeps - r.first - r.late) / r.sleeps) + "%", wrongPerWeek: +((r.falseAsk + r.peekAsk) / r.days * 7).toFixed(1), guessErr: r.guessErr.length ? Math.round(r.guessErr.sort((a, b) => a - b)[Math.floor(r.guessErr.length / 2)]) + "m" : "-" });
module.exports = { P, run, SleepAI, summary, setSeed: (s) => { seed = s; }, setManual: (m) => { MANUAL = m; } };
if (require.main === module) {
  SleepAI.W = JSON.parse(fs.readFileSync(__dirname + '/weights.json', 'utf8'));
  for (const mode of ["old", "new"]) { console.log("== " + mode); for (const name of Object.keys(P)) { seed = 7; console.log(name.padEnd(12), JSON.stringify(summary(run(name, 60, null, mode)))); } }
}
