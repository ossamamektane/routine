// Fits the estimator's weights on simulated lifestyles (closed loop, a few rounds), then picks thresholds.
const fs = require('fs');
const sim = require('./sim.cjs'), { P, run, SleepAI, summary, setSeed } = sim;
const names = Object.keys(P);
let W = [-6, 2, 1, 3, -3, 2, 0, 2, 0.5, 2, 0];
function fit(data, W0) {
  const w = W0.slice(), m = w.map(() => 0), v = w.map(() => 0), lr = 0.03, l2 = 1e-3;
  for (let it = 1; it <= 1500; it++) {
    const g = w.map(() => 0); let n = 0;
    for (const d of data) {
      let z = w[0] + d.b; for (let k = 0; k < d.x.length; k++) z += w[k + 1] * d.x[k];
      const p = 1 / (1 + Math.exp(-z)), wt = d.y ? 2 : 1, e = (p - d.y) * wt;
      g[0] += e; for (let k = 0; k < d.x.length; k++) g[k + 1] += e * d.x[k]; n += wt;
    }
    for (let k = 0; k < w.length; k++) { const gk = g[k] / n + l2 * w[k]; m[k] = 0.9 * m[k] + 0.1 * gk; v[k] = 0.999 * v[k] + 0.001 * gk * gk; w[k] -= lr * (m[k] / (1 - 0.9 ** it)) / (Math.sqrt(v[k] / (1 - 0.999 ** it)) + 1e-8); }
  }
  return w;
}
const score = (seeds) => { let right = 0, total = 0, wrong = 0, worst = 1; for (const n of names) for (const s of seeds) { setSeed(s); const r = run(n, 60); right += r.first + 0.5 * r.late; total += r.sleeps; wrong += (r.falseAsk + r.peekAsk) / r.days * 7; worst = Math.min(worst, (r.first + 0.5 * r.late) / r.sleeps); } return { right: right / total, wrongPerWeek: wrong / (names.length * seeds.length), worst }; };
for (let round = 0; round < 4; round++) {
  SleepAI.W = W; const data = [];
  for (const n of names) for (let s = 1; s <= 4; s++) { setSeed(s * 101); run(n, 60, data); }
  W = fit(data, W);
  SleepAI.W = W;
  console.log('round', round, 'samples', data.length, 'pos', data.filter((d) => d.y).length, JSON.stringify(score([11, 12])), W.map((x) => +x.toFixed(2)).join(','));
}
let best = null;
for (const th of [0.35, 0.45, 0.55, 0.65, 0.75]) for (const lb of [0.8, 0.9, 0.97]) {
  SleepAI.threshold = th; SleepAI.lookBack = lb; const s = score([11, 12]);
  const v = s.right - 0.06 * s.wrongPerWeek + 0.3 * s.worst;
  console.log('th', th, 'lookBack', lb, JSON.stringify(s), v.toFixed(3));
  if (!best || v > best.v) best = { v, th, lb };
}
fs.writeFileSync(__dirname + '/weights.json', JSON.stringify(W.map((x) => +x.toFixed(3))));
fs.writeFileSync(__dirname + '/thresholds.json', JSON.stringify(best));
console.log('best', JSON.stringify(best));
