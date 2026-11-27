const fs = require('fs'); const { P, run, SleepAI, summary, setSeed } = require('./sim.cjs');

const seeds = (process.argv[2] || '21,22,23').split(',').map(Number);
for (const mode of ['old', 'new']) { console.log('== ' + mode); let tot = 0, ok = 0, wr = 0;
  for (const n of Object.keys(P)) { let a = { sleeps: 0, first: 0, late: 0, falseAsk: 0, peekAsk: 0, guessErr: [], days: 0, lateBy: [] };
    for (const s of seeds) { setSeed(s); const r = run(n, 60, null, mode); for (const k of ['sleeps', 'first', 'late', 'falseAsk', 'peekAsk', 'days']) a[k] += r[k]; a.guessErr.push(...r.guessErr); }
    tot += a.sleeps; ok += a.first; wr += (a.falseAsk + a.peekAsk) / a.days * 7; console.log(n.padEnd(12), JSON.stringify(summary(a))); }
  console.log('ALL right', (100 * ok / tot).toFixed(1) + '%', 'wrong/week', (wr / Object.keys(P).length).toFixed(2)); }
