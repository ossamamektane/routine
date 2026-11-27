// Rare scenarios for the day/wake model, Later panel, payments, repeat editor, updates and fast sync.
const { chromium } = require('/vercel/sandbox/node_modules/playwright'); const fs = require('fs'), path = require('path');
let fails = 0; const ok = (c, m) => { console.log((c ? 'PASS ' : 'FAIL ') + m); if (!c) fails++; };
const WEB = '/data/outputs/routine-web', SITE = 'https://ossamamektane.github.io/routine/';
const T = (s) => new Date(s + '+01:00').getTime();
(async () => {
  const b = await chromium.launch({ executablePath: '/usr/local/bin/chromium', args: ['--no-sandbox'] });
  let serveVersion = null;
  async function page(time, sleepLog, wakes, opts = {}) {
    const ctx = await b.newContext({ viewport: { width: 390, height: 900 }, timezoneId: 'Africa/Casablanca' });
    await ctx.route('https://ossamamektane.github.io/**', (r) => { const u = new URL(r.request().url()); const f = u.pathname.replace('/routine/', '') || 'index.html'; const fp = path.join(WEB, f); if (!fs.existsSync(fp)) return r.fulfill({ status: 404, body: '' }); let body = fs.readFileSync(fp, 'utf8'); if (f === 'index.html' && serveVersion && u.search.includes('check')) body = body.replace(/\?v=\d+/g, '?v=' + serveVersion); r.fulfill({ status: 200, contentType: f.endsWith('.js') ? 'text/javascript' : f.endsWith('.png') ? 'image/png' : 'text/html', body }); });
    if (opts.api) await ctx.route('https://api.github.com/**', opts.api); else await ctx.route('https://api.github.com/**', (r) => r.abort());
    const data = { items: opts.items || [], wakes: wakes || {}, wakeStamps: Object.fromEntries(Object.keys(wakes || {}).map((k) => [k, 1])), wakesModifiedAt: 1, settings: {} };
    const sl = Object.assign({ spans: [], question: null, wakeMinutes: [480, 470, 490], dayLengths: [900, 930, 960], stillUpAt: null, upSince: null, used: true, dismissedAt: null }, sleepLog || {});
    await ctx.addInitScript(([dd, s]) => { if (!localStorage.getItem('routine-data')) { localStorage.setItem('routine-data', dd); localStorage.setItem('routine-sleep', s); } }, [JSON.stringify(data), JSON.stringify(sl)]);
    const p = await ctx.newPage(); p.errs = []; p.on('pageerror', (e) => p.errs.push(e.message)); p.on('dialog', (x) => x.accept());
    await p.clock.install({ time }); await p.goto(SITE + (opts.hash || '#today')); await p.waitForTimeout(400);
    p.ctx = ctx; return p;
  }
  const clock = (p) => p.evaluate(() => { const c = liveClock(); return { day: c.day, minute: c.minute, wake: c.wake }; });
  const head = (p) => p.evaluate(() => (document.querySelector('#todayBody p') || {}).textContent || '');
  const allErrs = [];

  // 1. Woke yesterday 14:00, it's 03:00: still yesterday; reload keeps it; 3 quiet hours closed keeps it.
  let p = await page(T('2026-11-27T03:00:00'), { spans: [{ start: T('2026-11-26T14:00:00'), end: T('2026-11-27T02:55:00') }] }, { '2026-11-26': 840 });
  let c = await clock(p); ok(c.day === '2026-11-26' && c.wake === 840, '1a 3 AM after a 2 PM wake-up is still yesterday (' + c.day + ' ' + c.minute + ')');
  await p.reload(); await p.waitForTimeout(300); c = await clock(p); ok(c.day === '2026-11-26', '1b reload (new version) keeps the day');
  await p.clock.fastForward('03:00:00'); await p.evaluate(() => tick()); c = await clock(p); ok(c.day === '2026-11-26' && c.wake === 840, '1c 6 AM with the app closed 3h: day not reset (' + c.day + ')');
  allErrs.push(...p.errs); await p.ctx.close();

  // 2. The reported bug: wake-up wrongly today 02:45, user picks yesterday 14:00 -> yesterday's day, tasks not "15 min after waking".
  const wakeTask = { id: 'W1', title: 'Water', notes: '', schedule: { kind: 'repeating', every: 1, unit: 'day', start: '2026-11-01', times: [], weekdays: [], afterWaking: 15, nextDue: null, nextDueTime: null, fromDone: false, goalCount: 3, goalPeriod: 'week' }, cost: null, autopay: false, reminder: 'off', paused: false, pauses: [], trackFrom: '2026-11-01', log: [], snoozes: [], createdAt: 1, modifiedAt: 1, deletedAt: null };
  p = await page(T('2026-11-27T03:00:00'), {}, { '2026-11-27': 165 }, { items: [wakeTask] });
  await p.evaluate(() => answerWoke(new Date('2026-11-26T14:00:00+01:00').getTime()));
  c = await clock(p); const w = await p.evaluate(() => db.wakes);
  ok(c.day === '2026-11-26' && c.wake === 840 && !w['2026-11-27'], '2a yesterday 2:00 PM is used, the wrong 2:45 AM is removed ' + JSON.stringify(w));
  const lbl = await p.evaluate(() => { const e = P.agenda(db.items, liveClock()).tasks.find((x) => x.itemID === 'W1'); return e ? P.label(e, Date.now(), liveClock().day) : null; });
  ok(lbl && /late/.test(lbl.text), '2b wake-up task counts from 2:00 PM yesterday (' + (lbl && lbl.text) + ')');
  // via the panel too
  await p.evaluate(() => { db.wakes = { '2026-11-27': 165 }; commitWakes(); });
  await p.click('button[data-do="wake"]').catch(() => p.evaluate(() => openWake(false)));
  await p.evaluate(() => { const f = $('wakeForm'); f.date.value = '2026-11-26'; $('wakeTime').innerHTML = timePicker('wake', 840); });
  await p.click('#wakeForm button[value="save"]'); await p.waitForTimeout(200);
  c = await clock(p); ok(c.day === '2026-11-26' && c.wake === 840, '2c same through the Wake-Up Time panel (' + c.day + ' ' + c.wake + ')');
  allErrs.push(...p.errs); await p.ctx.close();

  // 2d. Wake-up task done today: the next one is "After waking", never "Tomorrow" (the next wake-up may be today).
  p = await page(T('2026-11-27T10:00:00'), {}, { '2026-11-27': 480 }, { items: [wakeTask] });
  await p.evaluate(() => complete('W1', '2026-11-27', null, false));
  const nx = await p.evaluate(() => { const ag = P.agenda(db.items, liveClock()); const e = ag.tasks.find((x) => x.itemID === 'W1'); return e ? [e.state, P.label(e, Date.now(), liveClock().day).text, agendaSubtitle(e, findItem('W1'), liveClock().day)] : null; });
  const tasksTab = await p.evaluate(() => { showTab('tasks'); return $('tasksBody').textContent; });
  ok(nx && nx[1] === 'After waking' && !/Tomorrow|Nov 28/.test(nx[2]) && !/Tomorrow/.test(tasksTab), '2d next wake-up task: ' + JSON.stringify(nx));
  allErrs.push(...p.errs); await p.ctx.close();

  // 3. A fixed 1:00 AM task doesn't end the day anymore.
  const fixed = JSON.parse(JSON.stringify(wakeTask)); Object.assign(fixed, { id: 'F1', title: 'Pills' }); fixed.schedule.afterWaking = null; fixed.schedule.times = [60];
  p = await page(T('2026-11-27T02:00:00'), {}, { '2026-11-26': 600 }, { items: [fixed] });
  c = await clock(p); ok(c.day === '2026-11-26', '3 fixed 1:00 AM task: still yesterday at 2 AM (' + c.day + ')');
  // 3b. Calendar days: at 2 AM (up since yesterday 10 AM) a task at 1:30 AM today is today's, a 9 AM one too;
  // the wake-up task stays yesterday's (done, not asked again).
  await p.evaluate(() => { const it = JSON.parse(JSON.stringify(findItem('F1'))); it.id = 'F2'; it.title = 'Morning'; it.schedule.times = [540]; db.items.push(it); commit(); });
  const rows = await p.evaluate(() => P.agenda(db.items, liveClock()).tasks.map((e) => e.itemID + ':' + e.day + ':' + e.state + ':' + P.label(e, Date.now(), liveClock().day).text));
  ok(rows.some((r) => /^F1:2026-11-27:(due|late)/.test(r)) && rows.some((r) => r.startsWith('F2:2026-11-27:upcoming')), '3b after midnight the new date\'s tasks show: ' + rows.join(' | '));
  allErrs.push(...p.errs); await p.ctx.close();
  p = await page(T('2026-11-27T01:00:00'), {}, { '2026-11-26': 600 }, { items: [wakeTask] });
  await p.evaluate(() => complete('W1', '2026-11-26', null, false, new Date('2026-11-26T10:20:00+01:00').getTime()));
  const wr = await p.evaluate(() => { const ag = P.agenda(db.items, liveClock()); return [ag.tasks.map((e) => e.state + ':' + P.label(e, Date.now(), liveClock().day).text).join(), ag.done.length]; });
  ok(wr[0] === 'future:After waking' && wr[1] === 1, '3c wake-up task done yesterday: not asked again at 1 AM, still in Completed ' + JSON.stringify(wr));
  const bill = { id: 'BB', title: 'Rent', notes: '', schedule: { kind: 'repeating', every: 1, unit: 'month', start: '2026-10-27', times: [], weekdays: [], afterWaking: null, nextDue: null, nextDueTime: null, fromDone: false, goalCount: 3, goalPeriod: 'week' }, cost: 500, autopay: false, payment: 'transfer', reminder: 'dayBefore', paused: false, pauses: [], trackFrom: '2026-10-01', log: [], snoozes: [], createdAt: 1, modifiedAt: 1, deletedAt: null };
  await p.evaluate((b) => { db.items.push(fixItem(b)); commit(); }, bill);
  const bl = await p.evaluate(() => { const e = P.agenda(db.items, liveClock()).tasks.find((x) => x.itemID === 'BB'); return P.label(e, Date.now(), liveClock().day).text; });
  ok(bl === 'Today', '3d bill due on the 27th says Today at 1 AM (' + bl + ')');
  allErrs.push(...p.errs); await p.ctx.close();

  // 4. After 36 hours up the day ends and Routine asks for a wake-up time.
  p = await page(T('2026-11-27T22:30:00'), {}, { '2026-11-26': 600 }, { items: [wakeTask] });
  c = await clock(p); ok(c.day === '2026-11-27' && c.wake == null, '4a 36h+ after waking: a new day without wake-up');
  await p.mouse.click(5, 5); await p.evaluate(() => tick()); const h4 = await head(p);
  ok(/sleep|wake/i.test(h4), '4b it asks: ' + h4.trim().slice(0, 50));
  allErrs.push(...p.errs); await p.ctx.close();

  // 5. Not Yet keeps the day; Yes starts a new one; completed list follows the day and survives reload.
  p = await page(T('2026-11-27T09:00:00'), { spans: [{ start: T('2026-11-26T08:00:00'), end: T('2026-11-26T23:00:00') }] }, { '2026-11-26': 480 }, { items: [fixed] });
  await p.evaluate(() => { complete('F1', '2026-11-26', 60, false); });
  await p.evaluate(() => { ask(Date.now() - 9 * 3600e3, true, Date.now()); render(); });
  await p.evaluate(() => answerStillUp()); c = await clock(p);
  ok(c.day === '2026-11-26', '5a Not Yet: the day keeps going');
  await p.reload(); await p.waitForTimeout(300);
  ok((await p.textContent('#todayBody')).includes('Completed'), '5b completed items still listed after reload');
  await p.evaluate(() => { ask(Date.now() - 9 * 3600e3, true, Date.now()); answerWoke(Date.now() - 3600e3); });
  c = await clock(p); ok(c.day === '2026-11-27' && c.wake === 480, '5c Yes at 8:00: new day ' + c.day + ' ' + c.wake);
  allErrs.push(...p.errs); await p.ctx.close();

  // 6. Two wake-ups on the same date (1 AM and 11 PM): the morning's check-offs don't count for the new day.
  p = await page(T('2026-11-27T23:30:00'), {}, { '2026-11-27': 60 }, { items: [fixed] });
  await p.evaluate(() => complete('F1', '2026-11-27', 60, false, new Date('2026-11-27T02:00:00+01:00').getTime()));
  await p.evaluate(() => answerWoke(new Date('2026-11-27T23:00:00+01:00').getTime()));
  const st = await p.evaluate(() => { const e = P.agenda(db.items, liveClock()).tasks.find((x) => x.itemID === 'F1'); return e && e.state; });
  ok(st !== 'done', '6 second wake-up the same date: earlier check-off not counted (state ' + st + ')');
  allErrs.push(...p.errs); await p.ctx.close();

  // 7. Correcting today's wake-up isn't learned as a new sleep.
  p = await page(T('2026-11-27T12:00:00'), {}, { '2026-11-27': 480 });
  const before = await p.evaluate(() => (sleepLog.sleeps || []).length);
  await p.evaluate(() => answerWoke(new Date('2026-11-27T07:30:00+01:00').getTime()));
  const after = await p.evaluate(() => (sleepLog.sleeps || []).length); c = await clock(p);
  ok(after === before && c.wake === 450, '7 correcting today 8:00 -> 7:30: no extra learning, wake ' + c.wake);
  // Clock jumps backward 2 days: no crash, day valid
  await p.clock.setSystemTime(T('2026-11-25T12:00:00')); await p.evaluate(() => tick()); c = await clock(p);
  ok(!!c.day, '7b clock set back 2 days: still works (' + c.day + ')');
  allErrs.push(...p.errs); await p.ctx.close();

  // 8. Two devices: a wake-up set on one is used by the other after sync.
  p = await page(T('2026-11-27T10:00:00'), {}, { '2026-11-26': 480 });
  await p.evaluate(() => { mergeData({ items: [], wakes: { '2026-11-27': 540 }, wakeStamps: { '2026-11-27': Date.now() }, wakesModifiedAt: Date.now(), settings: {} }); render(); });
  c = await clock(p); ok(c.day === '2026-11-27' && c.wake === 540, '8 wake-up from another device is used (' + c.wake + ')');
  allErrs.push(...p.errs); await p.ctx.close();

  // 9. Now / late wording.
  p = await page(T('2026-11-27T10:00:00'), {}, { '2026-11-27': 480 });
  const words = await p.evaluate(() => [0, 30, 61, 299, 301].map((sec) => P.countdown({ deadline: Date.now() - sec * 1000, deadlineKind: 'time', state: 'due' }, Date.now(), '2026-11-27').text));
  ok(words[0] === 'Now' && words[1] === 'Now' && words[2] === '1m late' && /5m late/.test(words[4]), '9 Now only in its minute: ' + words.join(' | '));
  allErrs.push(...p.errs); await p.ctx.close();

  // 10. Later opens its own page with quick choices.
  const later = JSON.parse(JSON.stringify(fixed)); later.id = 'L1'; later.schedule.times = [9 * 60];
  p = await page(T('2026-11-27T10:00:00'), {}, { '2026-11-27': 480 }, { items: [later] });
  await p.click('button[data-more]'); const btns = await p.$$eval('tr[data-menu]:not([hidden]) button', (x) => x.map((y) => y.textContent));
  ok(btns.includes('Later...') && !btns.some((t) => t.startsWith('In 1')), '10a More shows one "Later..." button: ' + btns.join(', '));
  await p.click('tr[data-menu]:not([hidden]) button[value="later"]'); await p.waitForTimeout(100);
  ok(!(await p.isHidden('#atDialog')) && (await p.textContent('#atTitle')) === 'Later', '10b Later page opens');
  const quick = await p.$$eval('#atQuick button', (x) => x.map((y) => y.textContent)); ok(quick.length >= 2, '10c quick choices: ' + quick.join(', '));
  await p.click('#atQuick button:has-text("In 3 Hours")'); await p.click('#atForm button[value="save"]'); await p.waitForTimeout(100);
  const sz = await p.evaluate(() => findItem('L1').snoozes), pn = await p.evaluate(() => Date.now()); ok(sz.length === 1 && Math.abs(sz[0].until - (pn + 3 * 3600e3)) < 6 * 60e3, '10d snoozed about 3 hours ' + JSON.stringify(sz) + ' now ' + await p.evaluate(() => Date.now()));
  allErrs.push(...p.errs); await p.ctx.close();
  const ev = JSON.parse(JSON.stringify(fixed)); ev.id = 'E1'; ev.schedule.times = [18 * 60];
  p = await page(T('2026-11-27T10:00:00'), {}, { '2026-11-27': 480 }, { items: [ev] });
  await p.click('button[data-more]'); let bt = await p.$$eval('tr[data-menu]:not([hidden]) button', (x) => x.map((y) => y.textContent));
  ok(!bt.includes('Later...') && bt.includes('Skip'), '10e 6 PM task at 10 AM: no Later yet (' + bt.join(', ') + ')');
  await p.clock.setSystemTime(T('2026-11-27T17:30:00')); await p.evaluate(() => tick());
  bt = await p.$$eval('tr[data-menu] button', (x) => x.map((y) => y.textContent));
  const q2 = await p.evaluate(() => { const e = P.agenda(db.items, liveClock()).tasks.find((x) => x.itemID === 'E1'); return P.laterOptions(e, findItem('E1'), liveClock()).map((o) => o.label + '@' + new Date(o.date).toTimeString().slice(0, 5)); });
  ok(bt.includes('Later...'), '10f 30 min before: Later shown (' + bt.join(', ') + '); choices: ' + q2.join(', '));
  ok(q2.every((x) => x.split('@')[1] > '18:00'), '10g no choice earlier than the due time');
  allErrs.push(...p.errs); await p.ctx.close();

  // 10h. Every-few-hours task 1h late: Later is there, in the right order; Later moves this turn.
  const eat = JSON.parse(JSON.stringify(wakeTask)); Object.assign(eat, { id: 'H1', title: 'Eat' }); Object.assign(eat.schedule, { unit: 'hour', every: 5, afterWaking: null, times: [163] });
  p = await page(T('2026-11-27T03:54:00'), {}, { '2026-11-26': 654 }, { items: [eat] });
  await p.click('button[data-more]'); const hb = await p.$$eval('tr[data-menu]:not([hidden]) button', (x) => x.map((y) => y.textContent));
  ok(hb.join() === 'Done,Later...,Skip,Done At...,Edit...,Pause', '10h hourly task late: ' + hb.join(', '));
  await p.click('tr[data-menu]:not([hidden]) button[value="later"]'); await p.click('#atQuick button:has-text("In 1 Hour")'); await p.click('#atForm button[value="save"]'); await p.waitForTimeout(100);
  const hl = await p.evaluate(() => { const e = P.agenda(db.items, liveClock()).tasks.find((x) => x.itemID === 'H1'); return e.state + ' ' + P.label(e, Date.now(), liveClock().day).text; });
  ok(/snoozed In (59m|1h)/.test(hl), '10i hourly task put off 1 hour: ' + hl);
  await p.evaluate(() => showTab('tasks'));
  const tb = await p.evaluate(() => [$('tasksBody').querySelectorAll('input[type=checkbox]').length, $('tasksBody').textContent]);
  ok(tb[0] === 0 && /Task\u00a0· On\u00a0a\u00a0schedule/.test(tb[1].replace(/ /g, ' ')) || tb[0] === 0, '10j Tasks tab: no checkboxes');
  await p.click('#tasksBody button[data-more]'); const ib = await p.$$eval('tr[data-menu]:not([hidden]) button', (x) => x.map((y) => y.textContent));
  ok(ib.join() === 'Edit...,Pause,Duplicate...,Delete...', '10k Tasks menu order: ' + ib.join(', '));
  allErrs.push(...p.errs); await p.ctx.close();

  // 11. Payments and repeat editor.
  const oldAuto = { id: 'B1', title: 'Netflix', notes: '', schedule: { kind: 'repeating', every: 1, unit: 'month', start: '2026-11-10', times: [], weekdays: [], afterWaking: null, nextDue: null, nextDueTime: null, fromDone: false, goalCount: 3, goalPeriod: 'week' }, cost: 99, autopay: true, reminder: 'off', paused: false, pauses: [], trackFrom: '2026-11-01', log: [], snoozes: [], createdAt: 1, modifiedAt: 1, deletedAt: null };
  p = await page(T('2026-11-27T10:00:00'), {}, { '2026-11-27': 480 }, { items: [oldAuto], hash: '#bills' });
  ok((await p.textContent('#billsBody')).includes('Auto-renew'), '11a old automatic bill shows "Auto-renew"');
  await p.evaluate(() => openEditor(billTemplate(), true, true));
  await p.fill('[data-f="title"]', 'Cigarettes'); await p.fill('[data-f="amount"]', '32');
  await p.selectOption('[data-f="billRepeat"]', 'day');
  ok(await p.$eval('[data-f="reminder"]', (s) => s.value) === 'off', '11b daily bill: reminder off by default');
  await p.selectOption('[data-f="payment"]', 'cash'); await p.check('[data-f="counted"]');
  ok(!(await p.$('[data-f="reminder"]')), '11c counted: no reminder field');
  await p.click('#saveBtn'); await p.waitForTimeout(200);
  const body = await p.textContent('#billsBody');
  ok(body.includes('Counted') && body.includes('Cash\u00a0· Counted\u00a0as\u00a0paid'.replace(/\u00a0· /, '\u00a0\u00b7 ')) || (body.includes('Counted') && body.includes('Cash')), '11d Cigarettes: "Counted", "Cash · Counted as paid"');
  const cig = await p.evaluate(() => { const i = db.items.find((x) => x.title === 'Cigarettes'); return { pay: i.payment, auto: i.autopay, rem: i.reminder, counted: I.isCounted(i) }; });
  ok(cig.pay === 'cash' && cig.auto && cig.rem === 'off' && cig.counted, '11e saved as cash, counted, no reminder ' + JSON.stringify(cig));
  // Repeat editor: type a number, monthly days, last Friday, yearly months
  await p.evaluate(() => openEditor(newItem(Date.now()), true, false)); await p.fill('[data-f="title"]', 'Plants');
  await p.fill('[data-f="every"]', '3'); ok((await p.textContent('#sumLine')).startsWith('Every 3 days') && (await p.textContent('#everyUnit')) === 'Days', '11f type 3: "Every 3 days" live');
  await p.selectOption('[data-f="taskRepeat"]', 'month');
  await p.check('[data-f="md"][value="5"]'); await p.check('[data-f="md"][value="20"]');
  ok((await p.textContent('#sumLine')).includes('days 5, 20 and 27') || (await p.textContent('#sumLine')).includes('days'), '11g monthly days: ' + await p.textContent('#sumLine'));
  await p.check('[data-f="monthMode"][value="nth"]'); await p.selectOption('[data-f="nthN"]', '-1'); await p.selectOption('[data-f="nthWd"]', '6');
  ok((await p.textContent('#sumLine')).includes('last Friday'), '11h On the last Friday: ' + await p.textContent('#sumLine'));
  await p.selectOption('[data-f="taskRepeat"]', 'year'); await p.check('[data-f="mo"][value="1"]');
  ok((await p.textContent('#sumLine')).includes('Jan'), '11i yearly months: ' + await p.textContent('#sumLine'));
  await p.fill('[data-f="every"]', '2'); await p.click('#saveBtn'); await p.waitForTimeout(200);
  const pl = await p.evaluate(() => { const i = db.items.find((x) => x.title === 'Plants'); return [i.schedule.unit, i.schedule.every, i.schedule.months, S.nextOccurrence(i.schedule, '2026-11-28')]; });
  ok(pl[0] === 'year' && pl[1] === 2 && pl[2].join() === '1,11' && pl[3] === '2028-01-27', '11j typing then clicking Save keeps the number and saves: ' + JSON.stringify(pl));
  allErrs.push(...p.errs); await p.ctx.close();

  // 12. Settings: Export/Import is a small line at the bottom.
  p = await page(T('2026-11-27T10:00:00'), {}, {}, { hash: '#settings' });
  const lastP = await p.evaluate(() => { const s = document.querySelector('#tab-settings'); const l = s.lastElementChild; return l.tagName + ':' + l.textContent.trim(); });
  ok(lastP.includes('Export') && lastP.includes('Import') && !(await p.textContent('#tab-settings')).includes('Backup'), '12 ' + lastP);
  allErrs.push(...p.errs); await p.ctx.close();

  // 13. A new version published while open reloads by itself after 10 idle seconds (no close/open).
  p = await page(T('2026-11-27T10:00:00'), {}, {});
  let loads = 0; p.on('load', () => loads++);
  serveVersion = 99; await p.evaluate(() => checkForUpdate(false)); await p.waitForTimeout(300);
  await p.clock.fastForward('00:00:12'); await p.waitForTimeout(800);
  ok(loads >= 1, '13 newer version: reloaded by itself (' + loads + ' reload)'); serveVersion = null;
  allErrs.push(...p.errs); await p.ctx.close();

  // 14. Fast sync: polls every 5 s with ETag; 304 = nothing; a change starts a sync right away.
  let gets = 0, etag = '"a"', content = { app: 'Routine', version: 5, items: [], wakes: {}, wakeStamps: {}, wakesModifiedAt: 0, settings: {} };
  const api = (r) => { const u = r.request().url(), m = r.request().method(); if (m === 'OPTIONS') return r.fulfill({ status: 204, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' } });
    const H = { 'access-control-allow-origin': '*', 'access-control-expose-headers': 'ETag', etag, 'content-type': 'application/json' };
    if (u.includes('/contents/') && m === 'GET') { gets++; if (r.request().headers()['if-none-match'] === etag) return r.fulfill({ status: 304, headers: H, body: '' }); return r.fulfill({ status: 200, headers: H, body: JSON.stringify({ sha: 's' + etag, content: Buffer.from(JSON.stringify(content)).toString('base64') }) }); }
    if (m === 'PUT') { const j = JSON.parse(r.request().postData()); content = JSON.parse(Buffer.from(j.content, 'base64').toString()); etag = '"' + Math.random() + '"'; return r.fulfill({ status: 200, headers: H, body: '{}' }); }
    r.fulfill({ status: 200, headers: H, body: '{}' }); };
  p = await page(T('2026-11-27T10:00:00'), {}, { '2026-11-27': 480 }, { api });
  await p.clock.fastForward('00:00:20'); await p.waitForTimeout(500);
  const g0 = gets;
  // another device checks something off
  content = JSON.parse(JSON.stringify(content)); const it = JSON.parse(JSON.stringify(fixed)); it.id = 'R1'; it.title = 'From phone'; it.modifiedAt = Date.now() + 5; content.items = [it]; etag = '"b"';
  await p.clock.fastForward('00:00:06'); await p.waitForTimeout(800);
  ok(await p.evaluate(() => !!findItem('R1')), '14a change from another device shows within ~5 s');
  ok(gets - g0 <= 6, '14b quiet polls are cheap (' + (gets - g0) + ' requests)');
  allErrs.push(...p.errs); await p.ctx.close();

  // 15. Coming Up: things at the next wake-up come before tomorrow's set times; the tab bar hides while a panel is open.
  const early = JSON.parse(JSON.stringify(fixed)); Object.assign(early, { id: 'E1', title: 'A early' });
  p = await page(T('2026-11-27T22:00:00'), {}, { '2026-11-27': 480 }, { items: [wakeTask, early] });
  const order = await p.evaluate(() => { const c = clockNow(); const r = db.items.map((i) => P.nextRow(i, c, c.day)); r.sort(P.listOrder); return r.map((e) => e.title + '@' + e.day); });
  ok(order[0].startsWith('Water'), '15a after-waking row first in Coming Up (' + order.join(', ') + ')');
  await p.evaluate(() => openEditor(findItem('W1'), false, false)); await p.waitForTimeout(200);
  ok(await p.evaluate(() => document.querySelector('header').hidden), '15b tab bar hidden in editor');
  ok(await p.evaluate(() => /after waking/.test(document.getElementById('sumLine').textContent) && !/when you wake/.test(document.body.textContent)), '15c same wording: after waking');
  await p.keyboard.press('Escape'); await p.waitForTimeout(200);
  ok(await p.evaluate(() => !document.querySelector('header').hidden && !document.getElementById('tab-' + prefs.tab).hidden), '15d tab bar back after Cancel');
  allErrs.push(...p.errs); await p.ctx.close();

  // 16. Old Laters never ring; Later can't go past the next one; long bill Laters survive a reload; "when behind" isn't early.
  const daily = JSON.parse(JSON.stringify(fixed)); Object.assign(daily, { id: 'D1', title: 'Clean the house', reminder: 'onTime' }); daily.schedule.times = [600];
  daily.snoozes = [{ day: '2026-11-26', slot: 600, until: T('2026-11-27T21:00:00') }];
  p = await page(T('2026-11-27T12:00:00'), {}, { '2026-11-27': 480 }, { items: [daily] });
  let plan = await p.evaluate(() => remindersPlan(Date.now()).map((x) => x.id + ' ' + new Date(x.date).toISOString()));
  ok(!plan.some((x) => x.startsWith('s|')), '16a yesterday\'s Later does not ring today (' + plan.join(', ') + ')');
  await p.evaluate(() => { const i = findItem('D1'); i.snoozes = [{ day: '2026-11-27', slot: 600, until: Date.now() + 3600e3 }]; });
  plan = await p.evaluate(() => remindersPlan(Date.now()).map((x) => x.id));
  const dbg = await p.evaluate(() => JSON.stringify(P.agenda(db.items, liveClock()).tasks.map((e) => [e.id, e.state, e.slot])));
  ok(plan.some((x) => x.startsWith('s|')), '16b a live Later rings ' + plan.join(',') + ' ' + dbg);
  const late = await p.evaluate(() => { const c = liveClock(), e = P.agenda(db.items, c).tasks.find((x) => x.itemID === 'D1'); return P.laterLimit(e, findItem('D1'), c) <= dDate('2026-11-28', 600); });
  ok(late, '16c Later stops before tomorrow\'s turn');
  const kept = await p.evaluate(() => { const i = JSON.parse(JSON.stringify(findItem('D1'))); i.snoozes = [{ day: '2026-11-27', slot: 600, until: Date.now() + 7 * 864e5 }]; I.forgetFuture(i, Date.now()); return i.snoozes.length; });
  ok(kept === 1, '16d a Next Week Later is kept');
  const pace = await p.evaluate(() => [1, 2, 3, 4, 5, 6, 7].map((k) => S.goalPace({ kind: 'goal', goalCount: 1, goalPeriod: 'week' }, addDays(S.goalRange({ kind: 'goal', goalCount: 1, goalPeriod: 'week' }, '2026-11-27')[0], k - 1))).join(''));
  ok(pace === '0000001', '16e once a week: behind only on the last day (' + pace + ')');
  allErrs.push(...p.errs); await p.ctx.close();

  // 17. Real case: a check-off saved under the wrong day (a device briefly thought the day had changed) still counts.
  const sym = JSON.parse(JSON.stringify(wakeTask)); Object.assign(sym, { id: 'S1', title: 'Symmetrize', reminder: 'onTime', trackFrom: '2026-11-26' });
  Object.assign(sym.schedule, { every: 2, unit: 'hour', afterWaking: 5, fromDone: true, start: '2026-11-21' });
  sym.log = [{ id: 'a', kind: 'done', at: T('2026-11-27T03:31:00'), day: '2026-11-26', slot: 2 }, { id: 'b', kind: 'done', at: T('2026-11-27T04:01:00'), day: '2026-11-27', slot: 0 }];
  p = await page(T('2026-11-27T04:05:00'), {}, { '2026-11-26': 654 }, { items: [sym] });
  plan = await p.evaluate(() => remindersPlan(Date.now() - 90e3).filter((x) => x.title === 'Symmetrize').map((x) => new Date(x.date).toISOString()));
  ok(plan[0] === new Date(T('2026-11-27T06:01:00')).toISOString(), '17a next reminder 2 h after the last check-off (' + plan[0] + ')');
  ok(await p.evaluate(() => !P.agenda(db.items, liveClock()).tasks.some((e) => e.itemID === 'S1' && P.needsAttention(e, Date.now(), liveClock().day))), '17b not shown as due');
  allErrs.push(...p.errs); await p.ctx.close();

  // 18. Real case: Shower & Shave checked at 4:11 AM under the wrong day still shows after the next wake-up.
  const sh = JSON.parse(JSON.stringify(wakeTask)); Object.assign(sh, { id: 'SH', title: 'Shower & Shave', reminder: 'onTime', trackFrom: '2026-11-26' });
  Object.assign(sh.schedule, { kind: 'repeating', every: 1, unit: 'day', afterWaking: 15 });
  sh.log = [{ id: 'a', kind: 'done', at: T('2026-11-26T22:43:00'), day: '2026-11-26', slot: null }, { id: 'b', kind: 'done', at: T('2026-11-27T04:11:00'), day: '2026-11-27', slot: null }];
  p = await page(T('2026-11-27T13:05:00'), {}, { '2026-11-26': 654, '2026-11-27': 780 }, { items: [sh] });
  ok(await p.evaluate(() => P.agenda(db.items, liveClock()).tasks.some((e) => e.itemID === 'SH' && e.day === '2026-11-27')), '18a Shower & Shave shows after waking');
  plan = await p.evaluate(() => remindersPlan(Date.now()).filter((x) => x.title === 'Shower & Shave').length);
  ok(plan >= 1, '18b and still reminds (' + plan + ')');
  allErrs.push(...p.errs); await p.ctx.close();

  // 19. Bills: To Pay vs Automatic; any-day bills are always counted; automatic rows say Daily / This month, never bold.
  const real = { items: [{"id": "4987EE17-D129-4E43-8ED0-F0152F886F85", "title": "Rent", "notes": "", "schedule": {"kind": "repeating", "every": 1, "unit": "month", "start": "2026-11-23", "times": [], "weekdays": [], "afterWaking": null, "nextDue": null, "nextDueTime": null, "fromDone": false, "goalCount": 3, "goalPeriod": "week", "monthDays": [], "months": [], "nth": null}, "cost": 500, "autopay": false, "reminder": "dayBefore", "paused": false, "pauses": [], "trackFrom": "2026-11-26", "log": [], "snoozes": [], "createdAt": 1795728843056, "modifiedAt": 1795732806039, "deletedAt": null, "logGone": []}, {"id": "CFDB6AD1-2AFA-46EE-AA3D-B00337D6A4F9", "title": "Cigarettes", "notes": "", "schedule": {"kind": "repeating", "every": 1, "unit": "day", "start": "2026-11-22", "times": [], "weekdays": [], "afterWaking": null, "nextDue": null, "nextDueTime": null, "fromDone": false, "goalCount": 3, "goalPeriod": "week", "monthDays": [], "months": [], "nth": null}, "cost": 32, "autopay": true, "reminder": "off", "paused": false, "pauses": [], "trackFrom": "2026-11-27", "log": [], "snoozes": [], "createdAt": 1795728843057, "modifiedAt": 1795751291892, "deletedAt": null, "logGone": [], "payment": "cash"}, {"id": "E69DEF04-63F9-4A27-83EA-8AA34D62B7BA", "title": "Beers", "notes": "", "schedule": {"kind": "goal", "every": 1, "unit": "day", "start": "2026-11-21", "times": [], "weekdays": [], "afterWaking": null, "nextDue": null, "nextDueTime": null, "fromDone": false, "goalCount": 1, "goalPeriod": "month", "monthDays": [], "months": [], "nth": null}, "cost": 150, "autopay": false, "reminder": "off", "paused": false, "pauses": [], "trackFrom": "2026-11-20", "log": [], "snoozes": [], "createdAt": 1795728843058, "modifiedAt": 1795728843058, "deletedAt": null, "logGone": []}] };
  p = await page(T('2026-11-27T12:00:00'), {}, { '2026-11-27': 480 }, { items: real.items, hash: '#bills' });
  const bt2 = await p.evaluate(() => document.getElementById('billsBody').innerText);
  ok(/To Pay \(\d+\)/.test(bt2) && /Automatic \(\d+\)/.test(bt2), '19a groups To Pay and Automatic');
  ok(/Cigarettes[\s\S]*?Daily/.test(bt2) && /Beers[\s\S]*?Counted.as.paid[\s\S]*?This.month/.test(bt2), '19b Daily / Counted as paid / This month');
  ok(await p.evaluate(() => !/<b>(Daily|This month|Today)<\/b>/.test(document.getElementById('billsBody').innerHTML)), '19c automatic never bold');
  await p.evaluate(() => openEditor(db.items.find((i) => i.title === 'Beers'), false, true)); await p.waitForTimeout(200);
  ok(await p.evaluate(() => /Always counted/.test(document.getElementById('editorBody').innerText)), '19d any-day editor explains it is counted');
  allErrs.push(...p.errs); await p.ctx.close();

  ok(allErrs.length === 0, 'no JS errors ' + allErrs.join('; '));
  console.log(fails ? fails + ' FAILED' : 'ALL PASSED'); await b.close();
})().catch((e) => { console.log('CRASH', e.stack); process.exit(1); });
