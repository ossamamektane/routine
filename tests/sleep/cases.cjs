process.env.TZ = 'UTC';
const fs = require('fs'), vm = require('vm'); const ctx = vm.createContext({ console, Math, Date, JSON, Intl });
vm.runInContext(fs.readFileSync(require('path').join(__dirname, '../../model.js'), 'utf8') + '\nthis.SleepAI = SleepAI; this.Sleep = Sleep;', ctx);
const { SleepAI, Sleep } = ctx; const H = 3600e3, D0 = Date.UTC(2026, 10, 2);
const at = (d, h) => D0 + d * 864e5 + h * H;
const logWith = (spans, sleeps = []) => { const l = Sleep.newLog(); l.spans = spans.map(([a, b]) => ({ start: a, end: b || a + 5 * 60e3 })); l.sleeps = sleeps; return l; };
const check = (name, want, got) => console.log((!!got === want ? 'PASS ' : 'FAIL ') + name + (got ? ' -> from ' + new Date(got.from).toISOString().slice(5, 16) + ' to ' + new Date(got.to).toISOString().slice(5, 16) : ' -> no question'));
// Office night: last use 23:10, opens 07:05.
check('normal night', true, SleepAI.find(logWith([[at(0, 8)], [at(0, 15)], [at(0, 23.1)]]), at(1, 7.1), at(0, 7), 0));
// Busy afternoon: 4h quiet 12-16.
check('4h busy afternoon (new user)', false, SleepAI.find(logWith([[at(0, 8)], [at(0, 12)]]), at(0, 16), at(0, 7), 0));
// Slept at 20:00 without touching the app, busy all next day, opens 23:00 next day (27h).
check('slept 8 PM, back 27h later', true, SleepAI.find(logWith([[at(0, 9)], [at(0, 20)]]), at(1, 23), at(0, 8), 0));
// Same, but opened briefly at 10:00 next day (awake) and nothing asked then: look back finds the night.
check('missed sleep found later (look back)', true, SleepAI.find(logWith([[at(0, 9)], [at(0, 20)], [at(1, 10), at(1, 10.2)], [at(1, 14)]]), at(1, 18), at(0, 8), 0));
// Night shifter who taught it 5 day-sleeps 09-16: quiet 08:30 -> 16:20 should ask; 2.5h quiet at night shouldn't.
const ns = [0, 1, 2, 3, 4].map((d) => ({ start: at(d, 9), end: at(d, 16) }));
check('night shifter day sleep', true, SleepAI.find(logWith([[at(5, 2)], [at(5, 8.5)]], ns), at(5, 16.3), at(4, 16), 0));
check('night shifter quiet at work', false, SleepAI.find(logWith([[at(5, 20)], [at(5, 23)]], ns), at(6, 1.5), at(5, 16), 0));
// New parent: 23:00 last use, 3:00 look (2 min), opens 07:00: the whole night counts.
check('new parent with 3 AM look', true, SleepAI.find(logWith([[at(0, 22.9)], [at(1, 3), at(1, 3.03)]]), at(1, 7), at(0, 7), 0));
// Dealer: 4h sleeps taught; 4.5h quiet at 15:00-19:30.
const dl = [0, 1, 2, 3, 4, 5].map((d) => ({ start: at(d, 3 + d * 3), end: at(d, 7 + d * 3) }));
check('dealer short sleep', true, SleepAI.find(logWith([[at(6, 9)], [at(6, 15)]], dl), at(6, 19.6), at(6, 9), 0));
// 2 AM wake-up for someone who taught 21:30-02:00 sleeps (old rules never asked between 2 and 4 AM).
const early = [0, 1, 2, 3].map((d) => ({ start: at(d, 21.5), end: at(d + 1, 2) }));
check('wakes at 2 AM', true, SleepAI.find(logWith([[at(4, 21.4)]], early), at(5, 2.2), at(4, 2), 0));
const g = SleepAI.guessWake(SleepAI.profile(logWith([])), at(0, 23), at(1, 13));
console.log('guess when opened at 13:00 after 23:00:', new Date(g).toISOString().slice(11, 16));
