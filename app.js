// Routine - app.js
// Everything that touches the page or saved data: loading/saving, actions (done, undo, later, pause...),
// reminders, drawing each tab as plain HTML, the editor, and event handlers. Uses model.js.
// Sections, in order: Storage, AppStore (actions), Reminders, Time pickers, Screens, Panels, Editor,
// Export/import, Sync, Events, Start. Read README.md first (rules: no CSS, bold = needs you now, only show what's possible).
"use strict";
const KEY = "routine-data", SLEEP_KEY = "routine-sleep", PREF_KEY = "routine-prefs";
const $ = (id) => document.getElementById(id);
// True inside the Mac app (mac/ folder): the same page in a native window. Reminders, the Dock badge,
// notification permission and saving files then go through the app (toNative), so they work offline
// and even when the window is closed.
const NATIVE = !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.routine);
const toNative = (m) => { try { window.webkit.messageHandlers.routine.postMessage(m); } catch (e) {} };
const SITE = "https://ossamamektane.github.io/routine/", MAC_DOWNLOAD = "https://github.com/ossamamektane/routine/releases/tag/mac-latest";
let nativePermission = "default", nativeSent = "";
// Called by the Mac app with "granted", "denied" or "default".
window.routineNative = { permission(p) {
  nativePermission = p;
  if (p === "default" && prefs.reminders && !prefs.askedNative) { prefs.askedNative = true; savePrefs(); toNative({ type: "askPermission" }); }
  renderNotify(); planReminders();
} };
// Escapes text for safe use inside HTML. ALWAYS use it for anything the user typed.
const esc = (t) => String(t == null ? "" : t).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
// Deep copy of plain data (items, schedules).
const clone = (o) => JSON.parse(JSON.stringify(o));

// ---------- Storage ----------
function defaultCurrency() {
  try { const r = new Intl.Locale(navigator.language).maximize().region; return { MA: "MAD", FR: "EUR", DE: "EUR", ES: "EUR", GB: "GBP", US: "USD", CA: "CAD" }[r] || "USD"; } catch (e) { return "USD"; }
}
// Empty saved data for a first launch.
function blankData() { return { items: [], wakes: {}, wakeStamps: {}, wakesModifiedAt: 0, settings: { currency: defaultCurrency(), modifiedAt: 0 } }; }
// Repairs one saved/imported item: fills missing fields and drops broken log entries, so old or hand-edited files still load.
function fixItem(o) {
  const now = Date.now();
  const it = Object.assign(newItem(now), o || {});
  it.schedule = S.normalized(Object.assign(newSchedule(it.trackFrom || dayOf(now)), (o && o.schedule) || {}));
  it.cost = it.cost != null && +it.cost > 0 ? +it.cost : null;
  it.log = (it.log || []).filter((e) => e && validDay(e.day)).map((e) => ({ id: e.id || uid(), kind: e.kind === "skipped" ? "skipped" : "done",
    at: typeof e.at === "number" ? e.at : Date.parse(e.at) || dNoon(e.day), day: e.day, slot: e.slot == null ? null : e.slot,
    previousDue: e.previousDue || null, previousDueTime: e.previousDueTime == null ? null : e.previousDueTime, amount: e.amount == null ? null : +e.amount }));
  it.snoozes = (it.snoozes || []).filter((z) => z && validDay(z.day));
  // Check-offs that were undone ({ id, at }), so syncing doesn't bring them back.
  it.logGone = (it.logGone || []).filter((g) => g && g.id);
  it.pauses = (it.pauses || []).filter((p) => p && p.start);
  if (!validDay(it.trackFrom)) it.trackFrom = it.schedule.start;
  return it;
}
// Reads saved data from localStorage (or starts empty).
function loadData() {
  try {
    const d = JSON.parse(localStorage.getItem(KEY));
    if (d && Array.isArray(d.items)) { const b = blankData(); return { items: d.items.map(fixItem), wakes: d.wakes || {}, wakeStamps: d.wakeStamps || {}, wakesModifiedAt: d.wakesModifiedAt || 0, settings: Object.assign(b.settings, d.settings || {}) }; }
  } catch (e) {}
  return blankData();
}
let db = loadData();
// Wake-up times as last saved, to see which days changed (each day syncs on its own).
let wakesSaved = clone(db.wakes);
// What Routine remembers to decide when to ask "Did you sleep?" (kept on this device only).
let sleepLog = (() => { try { return Object.assign(Sleep.newLog(), JSON.parse(localStorage.getItem(SLEEP_KEY)) || {}); } catch (e) { return Sleep.newLog(); } })();
// True if this device shows 24-hour time. Default for the 24-Hour Time setting.
const deviceUses24 = (() => { try { const hc = new Intl.DateTimeFormat(LOC, { hour: "numeric" }).resolvedOptions().hourCycle; return hc === "h23" || hc === "h24"; } catch (e) { return false; } })();
// Settings that belong to this device only (not exported): reminders, badges, 24-hour time, open tab, last sync time.
let prefs = (() => { try { return Object.assign({ reminders: true, badge: true, lastSeen: 0, fired: {} }, JSON.parse(localStorage.getItem(PREF_KEY)) || {}); } catch (e) { return { reminders: true, badge: true, lastSeen: 0, fired: {} }; } })();
if (prefs.hour24 == null) prefs.hour24 = deviceUses24;
HOUR24 = !!prefs.hour24;
let now = Date.now();
// Saves tasks and bills.
const persist = () => localStorage.setItem(KEY, JSON.stringify(db));
// Saves the sleep log.
const saveSleep = () => localStorage.setItem(SLEEP_KEY, JSON.stringify(sleepLog));
// Saves this device's settings.
const savePrefs = () => localStorage.setItem(PREF_KEY, JSON.stringify(prefs));
// Item by ID (including deleted ones).
const findItem = (id) => db.items.find((i) => i.id === id);
// Items that aren't deleted (deleted ones are kept so imports know they were deleted).
const visible = () => db.items.filter((i) => i.deletedAt == null);

// ---------- AppStore ----------
function fixedTimes(day) {
  const out = [];
  for (const item of db.items) {
    if (!I.isActive(item) || I.hasCost(item)) continue;
    const s = item.schedule;
    if (s.kind === "goal" || S.isHourly(s) || S.usesWake(s) || !S.occurs(s, day)) continue;
    if (s.kind === "repeating" && day < item.trackFrom) continue;
    for (const sl of S.slots(s, day, null)) if (sl.minute != null && !I.entry(item, day, sl.key)) out.push(sl.minute);
  }
  return out;
}
// The day rules at a moment: wake-up times, usual day length, fixed times. Feeds makeClock().
function rulesAt(date) {
  const usual = Sleep.usualDay(sleepLog);
  const r = { wakes: db.wakes, usualDay: usual, cuts: {}, upSince: sleepLog.upSince };
  const today = dayOf(date), yesterday = addDays(today, -1);
  const wy = db.wakes[yesterday];
  if (wy != null) {
    const began = dDate(yesterday, wy);
    let up = began;
    if (sleepLog.upSince != null && sleepLog.upSince < began) up = sleepLog.upSince;
    r.cuts[yesterday] = Sleep.cut(wy, Sleep.isStillUp(sleepLog, up, date), usual, fixedTimes(today));
  }
  const wt = db.wakes[today];
  if (wt != null) r.cuts[today] = Sleep.cut(wt, false, usual, fixedTimes(addDays(today, 1)));
  return r;
}
// The day you're living, as of the last tick (stable while rendering).
const clockNow = () => makeClock(now, rulesAt(now));
// The day you're living, right this moment.
const liveClock = () => { const d = Date.now(); return makeClock(d, rulesAt(d)); };
// When you last woke up (from saved wake-up times), or null.
function lastWakeDate() {
  const today = dayOf(now);
  for (let b = 0; b <= 2; b++) {
    const d = addDays(today, -b), w = db.wakes[d];
    if (w == null) continue;
    const date = dDate(d, w);
    if (date <= now + 600e3 && now - date <= 48 * 3600e3) return date;
  }
  return null;
}
// A new modifiedAt time, always later than the previous one (newest change wins on import).
// Also always later than any change seen from another device (stampFloor), so a device whose clock is
// a bit behind still wins with a change made after it synced (like a hybrid logical clock).
let stampFloor = 0;
const stamp = (prev) => { const d = Math.max(Date.now(), stampFloor + 1, prev == null ? 0 : prev + 1); stampFloor = Math.max(stampFloor, d); return d; };
// The newest change time anywhere in some data.
const newestStamp = (d) => Math.max(0, d.wakesModifiedAt || 0, (d.settings && d.settings.modifiedAt) || 0, ...Object.values(d.wakeStamps || {}), ...(d.items || []).map((i) => i.modifiedAt || 0));
// Call after every change: saves, re-renders, re-plans reminders.
function commit() { persist(); now = Date.now(); render(); planReminders(); if (!syncMerging) { if (!prefs.syncDirty) { prefs.syncDirty = true; savePrefs(); } scheduleSync(); } }
// Adds or replaces an item, then commits.
function saveItem(item) {
  const copy = clone(item);
  copy.schedule = S.normalized(copy.schedule);
  copy.title = (copy.title || "").trim();
  const idx = db.items.findIndex((i) => i.id === copy.id);
  copy.modifiedAt = stamp(idx >= 0 ? db.items[idx].modifiedAt : null);
  if (idx >= 0) { copy.log = db.items[idx].log; db.items[idx] = copy; } else db.items.push(copy);
  noteActivity();
  commit();
}
// Changes one item in place with a function, stamps it, then commits.
function mutate(id, change) {
  const idx = db.items.findIndex((i) => i.id === id);
  if (idx < 0) return;
  const copy = clone(db.items[idx]);
  change(copy);
  copy.modifiedAt = stamp(db.items[idx].modifiedAt);
  db.items[idx] = copy;
  noteActivity();
  commit();
}
// Marks an item deleted (kept as a tombstone so imports don't bring it back).
function deleteItem(id) { mutate(id, (i) => { i.deletedAt = Date.now(); i.snoozes = []; }); }
// Pauses or resumes an item from the More buttons.
function setPausedItem(id, paused) {
  const today = liveClock().day, cal = dayOf(Date.now());
  mutate(id, (i) => I.setPaused(i, paused, I.hasCost(i) ? cal : today));
}
// at: optional time it was really done (for "Done at a Different Time").
function complete(itemID, day, slot, skipped, at) {
  const date = at != null ? Math.min(at, Date.now()) : Date.now();
  const current = liveClock();
  const living = at != null ? makeClock(date, rulesAt(date)).day : current.day;
  mutate(itemID, (item) => {
    if (item.schedule.kind !== "goal" && P.isLogged(item, day, slot, current)) return;
    const e = { id: uid(), kind: skipped ? "skipped" : "done", at: date, day, slot: slot == null ? null : slot, previousDue: null, previousDueTime: null, amount: null };
    if (!skipped) e.amount = item.cost;
    if (item.schedule.kind === "afterDone") {
      e.previousDue = item.schedule.nextDue;
      e.previousDueTime = item.schedule.nextDueTime;
      S.advanceAfterDone(item.schedule, date, I.hasCost(item) ? dayOf(date) : living);
    }
    item.log.push(e);
    item.snoozes = item.snoozes.filter((z) => !(z.day === day && sameSlot(z.slot, slot)));
    I.trimHistory(item, date);
  });
}
// Removes a done/skipped log entry and puts the item back the way it was.
function undo(itemID, logID) {
  const today = dayOf(Date.now()), current = liveClock();
  mutate(itemID, (item) => {
    let i = -1;
    for (let k = item.log.length - 1; k >= 0; k--) {
      const e = item.log[k];
      if (logID != null ? e.id === logID : (C.includes(current, e) || dayOf(e.at) === today || e.day === today)) { i = k; break; }
    }
    if (i < 0) return;
    const e = item.log[i];
    if (item.schedule.kind === "afterDone" && i === item.log.length - 1 && e.previousDue) {
      item.schedule.nextDue = e.previousDue;
      item.schedule.nextDueTime = e.previousDueTime;
    }
    item.log.splice(i, 1);
    item.logGone.push({ id: e.id, at: Date.now() });
  });
}
// Change the time of something already checked off.
function changeLogTime(itemID, logID, at) {
  const date = Math.min(at, Date.now());
  mutate(itemID, (item) => {
    const i = item.log.findIndex((e) => e.id === logID);
    if (i < 0) return;
    const e = item.log[i];
    e.at = date;
    if (item.schedule.kind === "afterDone" && i === item.log.length - 1 && e.previousDue) {
      item.schedule.nextDue = e.previousDue;
      item.schedule.nextDueTime = e.previousDueTime;
      S.advanceAfterDone(item.schedule, date, I.hasCost(item) ? dayOf(date) : makeClock(date, rulesAt(date)).day);
    }
  });
}
// "Later": hides one occurrence until `until` (timestamp).
function snooze(itemID, day, slot, until) {
  mutate(itemID, (item) => {
    item.snoozes = item.snoozes.filter((z) => !(z.day === day && sameSlot(z.slot, slot)));
    item.snoozes.push({ day, slot: slot == null ? null : slot, until });
  });
}
// Records that you're using Routine right now.
function noteActivity() { if (Sleep.note(sleepLog, Date.now())) saveSleep(); }
// How many timed reminders went by since you last used the app (a clue you were asleep).
function missedCount(lastUse) {
  return P.agenda(db.items, clockNow()).tasks.filter((e) => e.deadlineKind === "time" && e.deadline != null && e.deadline > lastUse && e.deadline <= now).length;
}
// Decides whether to show "Did you sleep?" or "What time did you wake up?" on Today. Same rules as the iPhone app.
function checkSleep(lastUse) {
  if (sleepLog.question) return;
  const relevant = sleepLog.used || db.items.some((i) => I.isActive(i) && !I.hasCost(i) && (S.usesWake(i.schedule) || S.isHourly(i.schedule)));
  if (!relevant) return;
  const current = clockNow();
  if (current.wake == null && sleepLog.dismissedAt != null && sleepLog.dismissedAt >= current.began) return;
  const lastWake = lastWakeDate();
  if (lastUse != null && now - lastUse >= Sleep.quietGap) {
    const wokeSince = lastWake != null && lastWake > lastUse;
    if (!wokeSince) {
      const up = C.upDate(current) != null ? C.upDate(current) : lastWake;
      if (Sleep.shouldAsk(sleepLog, lastUse, now, up, missedCount(lastUse))) { ask(lastUse, true); return; }
    }
  }
  if (current.wake != null) return;
  const earliest = dStart(dayOf(now)) + (Sleep.usualWake(sleepLog) - 240) * 60e3;
  if (now >= earliest) ask(now, false);
}
// Shows the question on Today.
function ask(from, auto) { sleepLog.question = { from, auto }; saveSleep(); }
// "Not Yet": you haven't slept, so the current day keeps going.
function answerStillUp() {
  now = Date.now();
  const before = clockNow();
  const previousUp = C.upDate(before) != null ? C.upDate(before) : lastWakeDate();
  sleepLog.stillUpAt = now; sleepLog.question = null; sleepLog.used = true;
  const after = clockNow();
  if (after.wake == null && previousUp != null) {
    const today = dayOf(now);
    const ended = rulesAt(now).cuts[addDays(today, -1)] || 0;
    db.wakes[today] = Math.min(minOfDay(now), Math.max(ended, Sleep.usualWake(sleepLog)));
    sleepLog.upSince = previousUp;
    saveSleep(); commitWakes();
  } else { saveSleep(); commit(); }
}
// Saves today's wake-up time.
function setWake(moment) {
  const day = dayOf(moment), kept = {};
  for (const [k, v] of Object.entries(db.wakes)) if (k !== day && validDay(k) && dDate(k, v) < moment) kept[k] = v;
  kept[day] = minOfDay(moment);
  db.wakes = kept;
}
// Answer to the wake-up question: starts a new day from that time and learns from it.
function answerWoke(date) {
  now = Date.now();
  const moment = Math.min(date, now), current = clockNow(), question = sleepLog.question;
  const today = dayOf(now), yesterday = addDays(today, -1);
  const startsNewDay = current.wake == null || current.day !== today || question != null;
  if (dayOf(moment) === today) {
    const previousUp = C.upDate(current) != null ? C.upDate(current) : lastWakeDate();
    setWake(moment);
    sleepLog.upSince = null; sleepLog.stillUpAt = null;
    if (startsNewDay) Sleep.learnWake(sleepLog, moment);
    if (question && question.auto && previousUp != null && question.from > previousUp) Sleep.learnDay(sleepLog, Math.floor((question.from - previousUp) / 60e3));
  } else {
    const minute = minOfDay(moment);
    sleepLog.stillUpAt = now;
    db.wakes[yesterday] = minute;
    const ended = Sleep.cut(minute, true, Sleep.usualDay(sleepLog), fixedTimes(today));
    if (minOfDay(now) < ended) { delete db.wakes[today]; sleepLog.upSince = null; }
    else { db.wakes[today] = Math.min(minOfDay(now), Math.max(ended, Sleep.usualWake(sleepLog))); sleepLog.upSince = moment; }
  }
  sleepLog.question = null; sleepLog.used = true;
  saveSleep(); commitWakes();
}
// "Not Now": hides the question until the next day.
function dismissQuestion() { sleepLog.question = null; sleepLog.dismissedAt = Date.now(); saveSleep(); commit(); }
// "I'm Not Up Yet": removes today's wake-up time.
function clearWake() {
  const current = liveClock();
  if (current.wake != null) delete db.wakes[current.day];
  sleepLog.upSince = null; sleepLog.stillUpAt = null; sleepLog.question = null; sleepLog.dismissedAt = Date.now();
  saveSleep(); commitWakes();
}
// Saves wake-up time changes.
function commitWakes() {
  const oldest = addDays(dayOf(Date.now()), -30);
  for (const k of Object.keys(db.wakes)) if (k < oldest) delete db.wakes[k];
  db.wakesModifiedAt = stamp(db.wakesModifiedAt);
  // Stamp each day that changed, so two devices setting different days both keep theirs.
  for (const k of new Set([...Object.keys(db.wakes), ...Object.keys(wakesSaved)])) if (k >= oldest && db.wakes[k] !== wakesSaved[k]) db.wakeStamps[k] = stamp(db.wakeStamps[k]);
  for (const k of Object.keys(db.wakeStamps)) if (k < oldest) delete db.wakeStamps[k];
  wakesSaved = clone(db.wakes);
  noteActivity();
  commit();
}
// If the device clock jumped backwards, removes things dated in the future.
function repairClockIfNeeded(date) {
  const seen = prefs.lastSeen;
  prefs.lastSeen = date; savePrefs();
  if (!(seen > 0 && date < seen - 600e3)) return;
  let changed = false;
  for (const item of db.items) if (I.forgetFuture(item, date)) { item.modifiedAt = stamp(item.modifiedAt); changed = true; }
  const limit = date + 600e3;
  for (const [k, v] of Object.entries(db.wakes)) if (dDate(k, v) > limit) { delete db.wakes[k]; changed = true; }
  sleepLog.spans = sleepLog.spans.filter((s) => s.start <= limit).map((s) => ({ start: s.start, end: s.end > date ? Math.max(s.start, date) : s.end }));
  for (const k of ["stillUpAt", "upSince", "dismissedAt"]) if (sleepLog[k] != null && sleepLog[k] > limit) sleepLog[k] = null;
  if (sleepLog.question && sleepLog.question.from > limit) sleepLog.question = null;
  saveSleep();
  if (changed) persist();
}
// Once a day: trims old history and Laters, and slims down items deleted over 60 days ago.
function cleanUp() {
  const date = Date.now();
  for (const item of db.items) I.trimHistory(item, date);
  // Deleted items are kept (without their history) for 2 years, so a device that was offline for a long time
  // can't bring them back when it syncs.
  const cutoff = date - 730 * 864e5, slim = date - 60 * 864e5;
  db.items = db.items.filter((i) => !(i.deletedAt != null && i.deletedAt < cutoff));
  for (const i of db.items) {
    if (i.deletedAt != null && i.deletedAt < slim) { i.log = []; i.snoozes = []; i.pauses = []; i.notes = ""; i.logGone = []; }
    i.logGone = i.logGone.filter((g) => g.at >= slim);
  }
  const oldest = addDays(dayOf(date), -30);
  for (const k of Object.keys(db.wakes)) if (k < oldest) delete db.wakes[k];
  persist();
}
const IDLE_MS = 5 * 60e3;
let lastInput = Date.now();
// Called on any tap, key or scroll. After 5+ quiet minutes it runs tick() right away (maybe ask "Did you sleep?").
function userHere() {
  const was = lastInput;
  lastInput = Date.now();
  if (lastInput - was >= IDLE_MS) tick(); // back after a quiet stretch: maybe ask "Did you sleep?"
}
for (const ev of ["pointerdown", "keydown", "touchstart", "wheel", "scroll", "focus"]) window.addEventListener(ev, userHere, { passive: true, capture: true });
// Runs at the start of every minute and when the page comes back: updates the time, checks sleep, re-renders, plans reminders.
function tick() {
  const date = Date.now();
  repairClockIfNeeded(date);
  const newDay = dayOf(date) !== dayOf(now);
  const lastUse = Sleep.lastUse(sleepLog, date);
  now = date;
  if (newDay) cleanUp();
  // Like the app being open on iPhone: you count as here only if Routine is on screen and you
  // touched, typed, or scrolled in the last few minutes (a tab left open overnight doesn't count).
  if (document.visibilityState === "visible" && date - lastInput < IDLE_MS) { checkSleep(lastUse); noteActivity(); }
  render();
  planReminders();
}

// ---------- Reminders (while the page is open) and badge ----------
function planReminders() {
  updateBadge();
  clearTimeout(planReminders.timer);
  if (NATIVE) {
    // The Mac app schedules the next 60 reminders itself, so they ring even when the window is closed.
    const date = Date.now(), items = prefs.reminders && nativePermission === "granted" ? remindersPlan(date).filter((p) => p.date > date).map((p) => ({ id: p.id, date: p.date, title: p.title, body: p.body })) : [];
    const text = JSON.stringify(items);
    if (text !== nativeSent) { nativeSent = text; toNative({ type: "reminders", items }); }
    return;
  }
  if (!prefs.reminders || typeof Notification === "undefined" || Notification.permission !== "granted") return;
  const date = Date.now(), planned = remindersPlan(date - 90e3);
  for (const p of planned) if (p.date <= date && !prefs.fired[p.id]) { prefs.fired[p.id] = p.date; show(p); }
  for (const k of Object.keys(prefs.fired)) if (prefs.fired[k] < date - 3 * 864e5) delete prefs.fired[k];
  savePrefs();
  const next = planned.find((p) => p.date > date);
  if (next) planReminders.timer = setTimeout(planReminders, Math.min(next.date - date + 500, 30 * 60e3));
}
// Shows one notification (through the service worker when possible, so tapping it opens the app).
function show(p) {
  const opts = { body: p.body, tag: p.id };
  try { new Notification(p.title, opts); } catch (e) {}
}
// Every reminder from now on: [{ key, at, title, body }]. Same rules as the app's reminders.
function remindersPlan(from) {
  const date = from, today = dayOf(date), clock = makeClock(date, rulesAt(date));
  const dayEnds = dDate(clock.day, C.reminderEnd(clock)), out = [], anytime = {};
  // Notification text for one item.
  const body = (item, dayBefore, minute) => {
    const parts = [];
    if (dayBefore) parts.push(minute != null ? "Tomorrow at " + Format.time(minute) : "Tomorrow");
    if (I.hasCost(item)) parts.push(Format.money(item.cost, db.settings.currency));
    if (!parts.length) { const n = (item.notes || "").split("\n")[0].slice(0, 90); if (n) parts.push(n); }
    return parts.join(" · ");
  };
  for (const item of db.items) {
    if (!I.isActive(item) || item.reminder === "off" || I.isAutopay(item) || I.isAnyDayBill(item)) continue;
    const s = item.schedule;
    if (s.kind === "goal") {
      if (!s.times.length) continue;
      for (let o = 0; o < 7; o++) {
        const d = addDays(today, o), [lo, hi] = S.goalRange(s, d);
        const count = today >= lo && today <= hi ? I.doneCount(item, lo, hi) : 0;
        if (count >= s.goalCount) continue;
        if (item.reminder === "whenBehind" && count >= S.goalPace(s, d)) continue;
        if (d === today && s.goalPeriod !== "day" && item.log.some((e) => e.kind === "done" && e.day === today)) continue;
        const fire = dDate(d, s.times[0]);
        if (fire <= date) continue;
        let b = Format.goalProgress(count, s.goalCount, s.goalPeriod);
        if (s.goalPeriod !== "day") b += " · " + Format.days(dIndex(hi) - dIndex(d) + 1) + " left";
        out.push({ id: "g|" + item.id + "|" + d, date: fire, title: I.title(item), body: b });
      }
      continue;
    }
    const days = S.isHourly(s) ? 3 : 9;
    for (let o = 0; o < days; o++) {
      const d = addDays(clock.day, o);
      if (!S.occurs(s, d)) continue;
      if (s.kind === "repeating" && d < item.trackFrom) continue;
      const isCurrent = d === clock.day, wake = isCurrent ? clock.wake : null;
      if (S.usesWake(s) && wake == null) continue;
      const end = isCurrent ? C.reminderEnd(clock) : LONGEST_DAY;
      const logged = S.isHourly(s) ? P.loggedSlots(item, d, clock) : new Set();
      let slots = S.slots(s, d, wake, end);
      if (S.isHourly(s) && s.fromDone) {
        if (isCurrent) { const n = P.fromDoneNext(item, clock); slots = n && (n.minute || 0) < end ? [n] : []; }
        else slots = slots.slice(0, 1);
      }
      for (const slot of slots) {
        if (S.isHourly(s)) { if (slot.key != null && logged.has(slot.key)) continue; }
        else if (I.entry(item, d, slot.key)) continue;
        if (!isCurrent && S.isHourly(s) && C.isUp(clock) && slot.minute != null && dDate(d, slot.minute) <= dayEnds) continue;
        const occ = occurrenceID(item.id, d, slot.key);
        const z = I.snooze(item, d, slot.key);
        if (z) { if (z.until > date) out.push({ id: "s|" + occ + "|" + z.until, date: z.until, title: I.title(item), body: body(item, false) }); continue; }
        if (item.reminder === "dayBefore" && !S.isHourly(s)) {
          const fire = dDate(addDays(d, -1), slot.minute != null ? slot.minute : 540);
          if (fire > date) out.push({ id: "b|" + occ, date: fire, title: I.title(item), body: body(item, true, slot.minute) });
          continue;
        }
        if (slot.minute == null) { (anytime[d] = anytime[d] || []).push(item); continue; }
        const fire = dDate(d, slot.minute);
        if (fire > date) out.push({ id: "o|" + occ, date: fire, title: I.title(item), body: body(item, false) });
      }
    }
    for (const z of item.snoozes) if (z.day < clock.day && z.until > date && !I.entry(item, z.day, z.slot))
      out.push({ id: "s|" + occurrenceID(item.id, z.day, z.slot) + "|" + z.until, date: z.until, title: I.title(item), body: body(item, false) });
  }
  for (const [d, list] of Object.entries(anytime)) {
    const fire = dDate(d, 540);
    if (fire <= date) continue;
    if (list.length === 1) out.push({ id: "o|" + occurrenceID(list[0].id, d, null), date: fire, title: I.title(list[0]), body: body(list[0], false) });
    else out.push({ id: "a|" + d, date: fire, title: "Today", body: Format.list(list.map(I.title)) });
  }
  return out.sort((a, b) => a.date - b.date).slice(0, 60);
}
// Number on the app icon = items due now or late (where the browser supports badges).
function updateBadge() {
  if (!NATIVE && !navigator.setAppBadge) return;
  const c = clockNow();
  const n = prefs.badge ? P.agenda(db.items, c).tasks.filter((e) => P.needsAttention(e, c.now, c.day)).length : 0;
  if (NATIVE) { toNative({ type: "badge", count: n }); return; }
  (n ? navigator.setAppBadge(n) : navigator.clearAppBadge()).catch(() => {});
}

// ---------- Time pickers: hour, minute, AM/PM ----------
function timePicker(name, minute) {
  const h24 = Math.floor(minute / 60), m = minute % 60, pm = h24 >= 12, h12 = h24 % 12 || 12;
  let html = '<span data-tp="' + esc(name) + '"><select data-part="h" aria-label="Hour">';
  if (HOUR24) for (let h = 0; h < 24; h++) html += '<option value="' + h + '"' + (h === h24 ? " selected" : "") + ">" + pad(h) + "</option>";
  else for (let h = 1; h <= 12; h++) html += "<option" + (h === h12 ? " selected" : "") + ">" + h + "</option>";
  html += '</select> : <select data-part="m" aria-label="Minute">';
  for (let k = 0; k < 60; k++) html += '<option value="' + k + '"' + (k === m ? " selected" : "") + ">" + pad(k) + "</option>";
  html += "</select>";
  if (!HOUR24) html += ' <select data-part="ap" aria-label="AM or PM"><option' + (pm ? "" : " selected") + ">AM</option><option" + (pm ? " selected" : "") + ">PM</option></select>";
  return html + "</span>";
}
// Reads a timePicker() back into minutes after midnight.
function readPicker(span) {
  const h = +span.querySelector('[data-part="h"]').value, m = +span.querySelector('[data-part="m"]').value, ap = span.querySelector('[data-part="ap"]');
  return ap ? ((h % 12) + (ap.value === "PM" ? 12 : 0)) * 60 + m : h * 60 + m;
}
// "After I Wake Up": the same choices as the app, in plain words.
function wakeOffsetMenu(minutes) {
  const choices = []; for (let k = 0; k <= 120; k++) choices.push(k); for (let k = 125; k <= 600; k += 5) choices.push(k);
  if (!choices.includes(minutes)) { choices.push(minutes); choices.sort((a, b) => a - b); }
  return '<select data-f="offset">' + choices.map((k) => '<option value="' + k + '"' + (k === minutes ? " selected" : "") + ">" + (k === 0 ? "Right when I wake up" : esc(Format.duration(k)) + " after waking") + "</option>").join("") + "</select>";
}

// ---------- Screens ----------
let rowMap = {};
// Countdown text; bold only when due now or late (bold means "needs you now").
function countdownHTML(c) {
  if (!c) return "";
  return c.tone === "late" || c.tone === "now" ? "<b>" + esc(c.text) + "</b>" : esc(c.text);
}
// True if the row's checkbox can be checked right now.
function canComplete(e) {
  if (isFinishedEntry(e) || e.state === "info") return false;
  if (e.hourly && (e.state === "waiting" || e.state === "future")) return false;
  return true;
}
// The small line under a Today row: amount, time, schedule. Overdue = italic.
function agendaSubtitle(e, item, today) {
  const parts = [], cur = db.settings.currency;
  if (e.isBill && I.hasCost(item)) parts.push(Format.money(item.cost, cur));
  if (e.goal) { parts.push(Format.goalProgress(e.progress, e.total, item.schedule.goalPeriod)); return parts.join(" · "); }
  switch (e.state) {
    case "done":
      if (e.at != null) {
        parts.push((e.isBill ? "Paid at " : "Done at ") + Format.timeMs(e.at));
        if (e.day < today) parts.push("was due " + Format.day(e.day));
      }
      break;
    case "skipped": parts.push("Skipped"); break;
    case "snoozed": if (e.snoozedUntil != null) parts.push("Later · " + Format.timeMs(e.snoozedUntil)); break;
    case "waiting": { const o = item.schedule.afterWaking || 0; parts.push(o === 0 ? "When you wake up" : Format.duration(o) + " after waking"); break; }
    case "future": { let w = Format.day(e.day); if (e.minute != null) w += " · " + Format.time(e.minute); parts.push(w); break; }
    case "info": break;
    default:
      if (e.overdue) parts.push(Format.day(e.day));
      if (e.minute != null) parts.push(Format.time(e.minute));
  }
  if (!isFinishedEntry(e) && e.state !== "waiting") { const o = S.shortSummary(item.schedule); if (o) parts.push(o); }
  let text = parts.join(" · ");
  if (e.overdue && !isFinishedEntry(e) && e.state !== "snoozed") text = "<i>" + esc(text) + "</i>";
  else text = esc(text);
  return text;
}
// The row checkbox: enabled if it can be done, checked if done, greyed out otherwise.
function checkBox(e) {
  if (!e) return '<input type="checkbox" disabled aria-label="Not yet">';
  const checked = isFinishedEntry(e);
  rowMap[e.id] = e;
  return canComplete(e) || checked ? '<input type="checkbox" data-check="' + esc(e.id) + '"' + (checked ? " checked" : "") + ' aria-label="Done">' : '<input type="checkbox" disabled aria-label="Not yet">';
}
// Every list row has the same four columns: checkbox | name and details | countdown | More.
// More opens a row right under it with what you can do, in one line of buttons.
// Short right-column texts like "7 days late" never break across lines, even on small screens.
const keepTogether = (html) => html.replace(/<[^>]*>/g, "").length <= 12 ? html.replace(/ (?![^<]*>)/g, "&nbsp;") : html;
const listRow = (box, title, sub, cd, menu) => '<tr><td>' + box + '</td><td width="100%">' + title + (sub ? "<br><small>" + sub + "</small>" : "") + '</td><td align="right"' + (NARROW ? "" : " nowrap") + ">" + keepTogether(cd) + "</td><td nowrap>" +
  '<button type="button" data-more="' + menu.key + '" aria-expanded="false">More</button></td></tr><tr data-menu="' + menu.key + '" hidden><td colspan="4" align="center">' + menu.html + "</td></tr>";
// One row on Today with its More buttons (only actions that are possible for it).
function agendaRow(e, item, clock) {
  const completable = canComplete(e);
  const canSkip = completable && !e.goal && e.state !== "future";
  const canUndo = isFinishedEntry(e) || (e.goal && e.progress > 0);
  const canLater = completable && !e.hourly && !e.goal && !["info", "future", "waiting"].includes(e.state);
  const checked = isFinishedEntry(e);
  const menu = moreMenu("act", e.id, [["done", "Done", completable], ["doneAt", "Done At...", completable && !e.goal], ["skip", "Skip", canSkip],
    ["undo", "Undo", canUndo], ["changeAt", "Change Time...", e.state === "done" && e.logID && !e.goal], ["edit", "Edit...", true], ["pause", "Pause", true]],
    canLater ? P.laterOptions(e, item, liveClock()) : null);
  const title = checked ? "<s>" + esc(I.title(item)) + "</s>" : esc(I.title(item));
  const right = I.isAnyDayBill(item) || (I.isAutopay(item) && !checked) ? stateText(item, e, clock) : countdownHTML(P.label(e, clock.now, clock.day));
  return listRow(checkBox(e), title, agendaSubtitle(e, item, clock.day), right, menu);
}
// Tasks and Bills rows look like Today's: paused and finished ones get a greyed-out checkbox,
// and the right column says what's going on (a countdown, Paused, Automatic, or "Any day this week").
function pausedSince(it) {
  const p = [...(it.pauses || [])].reverse().find((x) => x.end == null);
  return p && p.start ? "Since " + Format.day(p.start) : "";
}
// Right column text for Tasks and Bills rows.
function stateText(it, e, clock) {
  if (it.paused) return "<i>Paused</i>";
  if (I.isFinished(it)) return "Completed";
  const s = it.schedule;
  if (I.isAnyDayBill(it)) {
    const [lo, hi] = S.goalRange(s, dayOf(clock.now)), n = I.doneCount(it, lo, hi), when = { day: "today", week: "this week", month: "this month" }[s.goalPeriod];
    // Small screens get the short form; the row's subtitle already says "every month · any day".
    if (n >= s.goalCount) return NARROW ? "Paid" : "Paid " + when;
    if (n > 0) return n + " of " + s.goalCount + (NARROW ? " paid" : " paid " + when);
    if (NARROW) return when.charAt(0).toUpperCase() + when.slice(1);
    return s.goalPeriod === "day" ? "Any time today" : "Any day " + when;
  }
  if (I.isAutopay(it) && !(e && isFinishedEntry(e))) return "Automatic";
  return e ? countdownHTML(P.label(e, clock.now, clock.day)) : "";
}
// One row on the Tasks or Bills tab.
function itemRow(it, e, sub, clock) {
  const off = it.paused || I.isFinished(it);
  const box = off ? '<input type="checkbox" disabled' + (I.isFinished(it) ? " checked" : "") + ' aria-label="' + (it.paused ? "Paused" : "Completed") + '">' : checkBox(e);
  const title = I.isFinished(it) ? "<s>" + esc(I.title(it)) + "</s>" : it.paused ? "<i>" + esc(I.title(it)) + "</i>" : esc(I.title(it));
  if (it.paused && pausedSince(it)) sub = "<i>" + esc(pausedSince(it)) + "</i> · " + sub;
  return listRow(box, title, sub, stateText(it, e, clock), itemMenu(it));
}
// "Since 7:30 AM" / "Since yesterday, 11:00 PM" for the Up For line.
function sinceText(c) {
  const up = C.upDate(c);
  if (up == null) return "";
  const time = Format.timeMs(up), days = dIndex(dayOf(c.now)) - dIndex(dayOf(up));
  if (days <= 0) return "Since " + time;
  if (days === 1) return "Since yesterday, " + time;
  return "Since " + Format.day(dayOf(up)) + ", " + time;
}
// Every status line has the same shape: bold status · details · buttons.
// Bold only means "needs you now": late or due countdowns and the sleep question.
const statusLine = (head, text, buttons, urgent) => '<p align="center">' + (urgent ? "<b>" + esc(head) + "</b>" : esc(head)) + (text ? " · " + esc(text) : "") + " " +
  buttons.map(([act, label]) => '<button type="button" data-do="' + act + '">' + label + "</button>").join(" ") + "</p>";
// Top of Today: the sleep question, or how long you've been up.
function dayHeaderHTML(c) {
  if (sleepLog.question) {
    if (lastWakeDate() != null) return statusLine("Did you sleep?", "Tap Yes to start a new day.", [["sleepYes", "Yes"], ["sleepNo", "Not Yet"]], true);
    return statusLine("What time did you wake up?", "Your day starts from then.", [["sleepYes", "Set Wake-Up Time"], ["notNow", "Not Now"]], true);
  }
  if (C.isUp(c)) return statusLine("Up for " + Format.span(C.minutesUp(c)), sinceText(c), [["wake", "Change"]]);
  return statusLine("Not up yet", "Set the time you woke up.", [["wake", "Start My Day"]]);
}
// Draws the Today tab: Up Next, Coming Up, Completed.
function renderToday(c) {
  const ag = P.agenda(db.items, c), byID = {};
  db.items.forEach((i) => (byID[i.id] = i));
  const hasTasks = visible().some((i) => !I.hasCost(i));
  let html = "";
  if (hasTasks || ag.tasks.length || ag.done.length) {
    if (hasTasks) html += dayHeaderHTML(c);
    const list = ag.tasks.filter((e) => byID[e.itemID]), soon = list.filter((e) => e.state !== "future"), later = list.filter((e) => e.state === "future");
    // One table for the whole list so every column lines up.
    const rows = (list) => list.map((e) => agendaRow(e, byID[e.itemID], c)).join("");
    const done = ag.done.filter((e) => byID[e.itemID]);
    html += listOpen() + heading("Up Next" + (soon.length ? " (" + soon.length + ")" : "")) + (soon.length ? rows(soon) : '<tr><td colspan="4">Nothing left to do.</td></tr>');
    if (later.length) html += heading("Coming Up (" + later.length + ")") + rows(later);
    if (done.length) html += heading("Completed (" + done.length + ")") + rows(done);
    html += "</table>";
  } else {
    html += statusLine("Nothing Today", "Tasks and bills you add will appear here.", []);
  }
  $("todayBody").innerHTML = html;
}
// Opening tag of a list table. Tighter padding on very small screens.
const listOpen = () => '<table width="100%" cellpadding="' + (NARROW ? 3 : 6) + '" cellspacing="0" frame="void" rules="rows">';
// A group heading row inside a list table (spans all 4 columns).
const heading = (text) => '<tr><td colspan="4" align="center"><h3>' + esc(text) + "</h3></td></tr>";
// Splits items into the groups shown on Tasks and Bills (Every Day, On a Schedule, ...).
function itemGroups(items, afterDoneTitle) {
  const g = { daily: [], repeating: [], anyDay: [], afterDone: [], once: [], paused: [], finished: [] };
  for (const it of items) {
    const s = it.schedule;
    if (I.isFinished(it)) { g.finished.push(it); continue; }
    if (it.paused) { g.paused.push(it); continue; }
    if (s.kind === "repeating") { if (s.fromDone) g.afterDone.push(it); else if (S.isEveryDay(s) || S.isHourly(s)) g.daily.push(it); else g.repeating.push(it); }
    else if (s.kind === "afterDone") g.afterDone.push(it);
    else if (s.kind === "goal") g.anyDay.push(it);
    else g.once.push(it);
  }
  const titles = [["daily", "Every Day"], ["repeating", "On a Schedule"], ["anyDay", "Any Day"], ["afterDone", afterDoneTitle], ["once", "One-Time"], ["paused", "Paused"], ["finished", "Completed"]];
  return titles.filter(([k]) => g[k].length).map(([k, t]) => ({ title: t, items: g[k] }));
}
// Only what's possible for this row. Later lists the same times as the app, then any other time.
function moreMenu(kind, id, choices, later) {
  // One button inside a More row.
  const btn = (v, t) => '<button type="button" data-' + kind + '="' + esc(id) + '" value="' + v + '">' + t + "</button>";
  let html = choices.filter((c) => c[2]).map(([v, t]) => btn(v, t)).join(" ");
  if (later) html += "<br>Later: " + later.map((o) => btn("later:" + o.date, esc(o.label))).concat(btn("later", "Other Time...")).join(" ");
  return { key: esc(kind + ":" + id), html };
}
// More buttons for a Tasks or Bills row.
function itemMenu(item) {
  const l = I.hasCost(item) ? I.lastDone(item) : null, undoPay = !!l && Date.now() - l.at < 30 * 864e5;
  return moreMenu("item", item.id, [["edit", "Edit...", true], ["pause", item.paused ? "Resume" : "Pause", !I.isFinished(item)],
    ["duplicate", "Duplicate...", true], ["undoPay", "Undo Payment", undoPay], ["delete", "Delete...", true]]);
}
// The 7 days of this week, starting on the locale's first weekday.
function weekDays(today) { const first = addDays(today, -mod(weekday(today) - FIRST_WEEKDAY, 7)); return [0, 1, 2, 3, 4, 5, 6].map((n) => addDays(first, n)); }
// Draws the Tasks tab: weekly count, then every task grouped.
function renderTasks(c) {
  const today = dayOf(c.now), tasks = visible().filter((i) => !I.hasCost(i));
  const q = $("taskSearch").value.trim().toLowerCase();
  const found = tasks.filter((i) => !q || i.title.toLowerCase().includes(q) || (i.notes || "").toLowerCase().includes(q)).sort((a, b) => I.title(a).localeCompare(I.title(b), undefined, { numeric: true }));
  let html = "";
  if (!tasks.length) { html = statusLine("No Tasks", "Tasks you add will appear here.", []); $("taskSummary").innerHTML = ""; }
  else {
    // The summary sits under the title, above Search: it describes the whole page, the list starts after Search.
    const wasOpen = !!$("taskSummary").querySelector("details[open]");
    let sum = "";
      const days = weekDays(today), start = dStart(days[0]), end = dStart(addDays(days[6], 1)), counts = [0, 0, 0, 0, 0, 0, 0];
      for (const it of tasks) for (const e of it.log) if (e.kind === "done" && e.at >= start && e.at < end) { const k = dIndex(dayOf(e.at)) - dIndex(days[0]); if (k >= 0 && k < 7) counts[k]++; }
      const week = counts.reduce((a, b) => a + b, 0), todayCount = counts[days.indexOf(today)] || 0;
      sum += '<details' + (wasOpen ? ' open' : '') + '><summary>' + todayCount + " tasks completed today · " + week + " this week</summary><br><table cellpadding=\"4\" cellspacing=\"0\" frame=\"hsides\" rules=\"groups\"><thead><tr><th align=\"left\">Day</th><th align=\"right\">Completed</th></tr></thead><tbody>";
      days.forEach((d, k) => { let n = new Date(dNoon(d)).toLocaleDateString(LOC, { weekday: "long" }); let v = String(counts[k]); if (d === today) n += " (Today)"; else if (d > today) { n = "<i>" + n + "</i>"; v = "<i>" + v + "</i>"; } sum += "<tr><td>" + n + '</td><td align="right">' + v + "</td></tr>"; });
      sum += "</tbody><tfoot><tr><th align=\"left\">Total this week</th><th align=\"right\">" + week + "</th></tr></tfoot></table><br></details>";
    $("taskSummary").innerHTML = sum;
    const ag = P.agenda(db.items, c), byItem = {};
    for (const e of [...ag.tasks, ...ag.done]) if (!byItem[e.itemID]) byItem[e.itemID] = e;
    html += listOpen();
    for (const g of itemGroups(found, "After Completion")) {
      html += heading(g.title + " (" + g.items.length + ")");
      for (const it of g.items) html += itemRow(it, byItem[it.id], esc(S.summary(it.schedule)), c);
    }
    html += "</table>";
    if (q && !found.length) html += "<p>No results for “" + esc(q) + "”.</p>";
    if (!q) html += "<p align=\"center\"><small>" + tasks.length + " Tasks</small></p>";
  }
  $("tasksBody").innerHTML = html;
}
// Small line under a bill: when it's due and how often.
function billSubtitle(item, e, paidToday, today) {
  const s = item.schedule;
  if (!e) {
    if (I.isFinished(item)) { const d = I.lastDone(item); return d ? "Paid " + Format.day(dayOf(d.at)) : "Skipped"; }
    return S.summary(s);
  }
  if (I.isAnyDayBill(item)) {
    if (s.goalCount === 1 && s.goalPeriod === "week") return "Every week · any day";
    if (s.goalCount === 1 && s.goalPeriod === "month") return "Every month · any day";
    if (s.goalCount === 1 && s.goalPeriod === "day") return "Every day";
    return Format.goal(s.goalCount, s.goalPeriod) + " · any day";
  }
  const parts = [], everyDay = S.isEveryDay(s) && !s.fromDone;
  if (paidToday && !e.overdue) parts.push("Paid today");
  else if (e.state === "skipped") parts.push("Skipped");
  else if (e.goal) parts.push(Format.goalProgress(e.progress, e.total, s.goalPeriod));
  else if (e.state === "snoozed" && e.snoozedUntil != null) parts.push("Later · " + Format.timeMs(e.snoozedUntil));
  else if (!everyDay) parts.push(Format.relative(e.day, today));
  if (everyDay) parts.push("Every day"); else { const o = S.shortSummary(s); if (o) parts.push(o); }
  return parts.join(" · ");
}
// Draws the Bills tab: monthly/yearly totals, then every bill grouped.
function renderBills(c) {
  const code = db.settings.currency, today = dayOf(c.now), all = visible().filter(I.hasCost);
  const q = $("billSearch").value.trim().toLowerCase();
  const due = P.bills(db.items, c.now), byItem = {}, rank = {};
  due.forEach((e, k) => { if (!byItem[e.itemID]) { byItem[e.itemID] = e; rank[e.itemID] = k; } });
  const found = all.filter((i) => !q || i.title.toLowerCase().includes(q) || (i.notes || "").toLowerCase().includes(q)).sort((a, b) => {
    const l = rank[a.id] != null ? rank[a.id] : 1e9, r = rank[b.id] != null ? rank[b.id] : 1e9;
    return l !== r ? l - r : I.title(a).localeCompare(I.title(b), undefined, { numeric: true });
  });
  let html = "";
  if (!all.length) { html = statusLine("No Bills", "Bills you add will appear here.", []); $("billSummary").innerHTML = ""; }
  else {
    // The summary sits under the title, above Search: it describes the whole page, the list starts after Search.
    const wasOpen = !!$("billSummary").querySelector("details[open]");
    let sum = "";
      const months = Money.yearMonths(db.items, c.now), cm = months.find((m) => m.month === monthIndex(today)), year = months.reduce((a, m) => a + m.amount, 0);
      sum += '<details' + (wasOpen ? ' open' : '') + '><summary>' + esc(Format.money(cm ? cm.amount : 0, code)) + " this month · " + esc(Format.money(year, code)) + " this year</summary>" +
        "<br><table cellpadding=\"4\" cellspacing=\"0\" frame=\"hsides\" rules=\"groups\"><thead><tr><th align=\"left\">Month</th><th align=\"right\">Amount</th></tr></thead><tbody>";
      for (const m of months) {
        let n = new Date(dNoon(m.first)).toLocaleDateString(LOC, { month: "long" }), v = Format.money(m.amount, code);
        n = esc(n) + (m.month === monthIndex(today) ? " (This Month)" : ""); v = esc(v);
        sum += "<tr><td>" + n + '</td><td align="right">' + v + "</td></tr>";
      }
      sum += "</tbody><tfoot><tr><th align=\"left\">Total for " + dParts(today)[0] + "</th><th align=\"right\">" + esc(Format.money(year, code)) + "</th></tr></tfoot></table><p><small>Excludes paused bills.</small></p></details>";
    $("billSummary").innerHTML = sum;
    html += listOpen();
    for (const g of itemGroups(found, "After Payment")) {
      html += heading(g.title + " (" + g.items.length + ")");
      for (const it of g.items) {
        const e = byItem[it.id], paidToday = [...it.log].reverse().find((x) => x.kind === "done" && dayOf(x.at) === today);
        let sub = esc(billSubtitle(it, e, paidToday, today));
        if (e && e.overdue && !isFinishedEntry(e) && e.state !== "snoozed") sub = "<i>" + sub + "</i>";
        html += itemRow(it, e, esc(Format.money(it.cost, code)) + " · " + sub, c);
      }
    }
    html += "</table>";
    if (q && !found.length) html += "<p>No results for “" + esc(q) + "”.</p>";
    if (!q) html += "<p align=\"center\"><small>" + all.length + " Bills</small></p>";
  }
  $("billsBody").innerHTML = html;
}
// Notification status in Settings > Reminders. Only shown when there's a problem or a button to press.
function renderNotify() {
  if (NATIVE) {
    $("allow").hidden = nativePermission !== "default";
    $("notifyText").textContent = nativePermission === "denied" ? "Turned off in System Settings \u203a Notifications." : nativePermission === "default" ? "Not allowed yet." : "";
    $("notifyLine").hidden = nativePermission === "granted";
    return;
  }
  const has = typeof Notification !== "undefined";
  const p = has ? Notification.permission : "unsupported";
  $("allow").hidden = !(has && p === "default");
  $("notifyText").textContent = !has ? "Not available. On iPhone, add Routine to the Home Screen first." :
    p === "denied" ? "Turned off in browser settings." : p === "default" ? "Not allowed yet." : "";
  $("notifyLine").hidden = !$("notifyText").textContent && $("allow").hidden;
}
// One More open at a time; it stays open when the page refreshes.
let openMenu = null;
// Opens the More row with this key (null closes all). Also flips the button between More and Close.
function showMenu(key) {
  openMenu = key;
  for (const r of document.querySelectorAll("tr[data-menu]")) r.hidden = r.dataset.menu !== key;
  for (const b of document.querySelectorAll("[data-more]")) { const on = b.dataset.more === key; b.setAttribute("aria-expanded", on ? "true" : "false"); b.textContent = on ? "Close" : "More"; }
}
// Redraws all tabs from the data. Safe to call any time; skipped while the editor is open.
function render() {
  if (editor.open) return; // don't rebuild the page while editing
  rowMap = {};
  const c = clockNow();
  renderToday(c); renderTasks(c); renderBills(c);
  if (openMenu) showMenu(openMenu); renderNotify(); if (typeof renderTabs === "function" && prefs.tab) renderTabs();
}

// ---------- Panels (wake time, done at, editor) ----------
// Shown in the page in place of the open tab, then the tab comes back.
const PANELS = ["wakeDialog", "atDialog", "editor"];
// True if a panel (editor, wake-up time, done at) is showing.
const panelOpen = () => PANELS.some((id) => !$(id).hidden);
// Shows a panel in place of the tabs.
function openPanel(id) {
  for (const t of TABS) $("tab-" + t).hidden = true;
  for (const p of PANELS) $(p).hidden = p !== id;
  window.scrollTo(0, 0);
}
// Hides a panel and brings the open tab back.
function closePanel(id) {
  $(id).hidden = true;
  if (!panelOpen()) for (const t of TABS) $("tab-" + t).hidden = t !== prefs.tab;
}
// ---------- Wake and "done at" ----------
let wakeAnswering = false, atTarget = null;
// Earliest and latest allowed wake-up time, for today or yesterday.
function wakeRange(yesterday, n) {
  const today = dayOf(n);
  if (yesterday) { const lower = Math.max(dStart(addDays(today, -1)), n - 24 * 3600e3); return [lower, Math.max(lower, dStart(today) - 60e3)]; }
  return [dStart(today), Math.max(dStart(today), n)];
}
// Opens the Wake-Up Time panel. answering = true when answering the sleep question.
function openWake(answering) {
  wakeAnswering = answering;
  const n = Date.now(), c = liveClock(), f = $("wakeForm"), today = dayOf(n);
  let time;
  const up = C.upDate(c);
  if (!answering && up != null) { const r = wakeRange(dayOf(up) < today, n); time = Math.min(Math.max(up, r[0]), r[1]); }
  else time = Math.min(dStart(today) + Math.floor(minOfDay(n) / 5) * 5 * 60e3, n);
  f.date.value = dayOf(time);
  f.date.min = addDays(today, -1);
  f.date.max = today;
  $("wakeTime").innerHTML = timePicker("wake", minOfDay(time));
  $("notUp").hidden = !(!answering && c.wake != null);
  openPanel("wakeDialog");
}
// Reads the chosen wake-up time, kept within the allowed range.
function readWake() {
  const n = Date.now(), today = dayOf(n), f = $("wakeForm");
  const day = f.date.value === addDays(today, -1) ? f.date.value : today, r = wakeRange(day < today, n);
  const t = dDate(day, readPicker($("wakeTime").querySelector("[data-tp]")));
  return Math.min(Math.max(t, r[0]), r[1]);
}

// Opens the Done At / Change Time / Later panel for one row.
function openAt(target, title, initial) {
  atTarget = target;
  const f = $("atForm"), today = dayOf(Date.now()), later = target.kind === "later";
  $("atTitle").textContent = title;
  f.date.value = dayOf(initial);
  f.date.min = later ? today : "";
  f.date.max = later ? "" : today;
  $("atTime").innerHTML = timePicker("at", minOfDay(initial));
  openPanel("atDialog");
}

// ---------- Editor (same choices as the app's editor) ----------
const editor = { open: false, isNew: true, isBill: false, draft: null, baseline: null, amountText: "", times: [] };
// Today for the editor: the day you're living for tasks, the calendar day for bills.
const livingDay = () => (editor.isBill ? dayOf(Date.now()) : clockNow().day);
// Default reminder time for "any day" tasks: your evening (5-10 PM).
const eveningMinute = () => Math.min(Math.max(Sleep.usualWake(sleepLog) + Sleep.usualDay(sleepLog) - 240, 1020), 1320);
// Now, rounded up to 5 minutes.
const roundedNow = () => Math.min(Math.floor((minOfDay(Date.now()) + 4) / 5) * 5, 23 * 60 + 55);
// A blank bill (monthly, reminds the day before).
function billTemplate() { const it = newItem(Date.now()); it.schedule.unit = "month"; it.reminder = "dayBefore"; return it; }
// Opens the editor for an item. isNew = adding; isBill = bill editor (amount, payment).
function openEditor(item, isNew, isBill) {
  const it = clone(item);
  const s = it.schedule;
  if (!isBill && s.kind === "afterDone" && s.unit === "hour") { s.kind = "repeating"; s.fromDone = true; if (s.nextDueTime != null) s.times = [s.nextDueTime]; s.nextDue = null; s.nextDueTime = null; }
  if (isBill) { if (isNew) it.reminder = "dayBefore"; s.afterWaking = null; if (s.kind === "repeating" && s.unit === "hour") s.unit = "day"; s.times = []; }
  Object.assign(editor, { open: true, isNew, isBill, draft: it, baseline: clone(it), amountText: it.cost != null ? String(+it.cost) : "", times: [...s.times], confirmDelete: false });
  if (isNew && !isBill) { const day = clockNow().day; if (it.schedule.start === dayOf(Date.now()) && day < it.schedule.start) { it.schedule.start = day; editor.baseline.schedule.start = day; } }
  renderEditor();
  openPanel("editor");
  if (isNew && !it.title) setTimeout(() => $("editorBody").querySelector('[data-f="title"]')?.focus(), 50);
}
// What the Repeat menu shows (day/week/month...; "any day" items use their period).
function frequency() {
  const s = editor.draft.schedule;
  if (s.kind !== "goal") return s.unit;
  return s.goalPeriod;
}
// The schedule as it would be saved, for the summary line and saving.
function previewSchedule() {
  const d = editor.draft, s = clone(d.schedule);
  s.times = [...editor.times];
  if (editor.isBill) { s.afterWaking = null; if (s.kind !== "goal" && s.unit === "hour") s.unit = "day"; s.times = []; }
  if (s.kind === "repeating" && s.unit === "hour" && s.afterWaking == null && !s.times.length) s.times = [Sleep.usualWake(sleepLog)];
  if (s.kind === "afterDone" && s.unit === "hour" && s.nextDueTime == null) s.nextDueTime = roundedNow();
  if (!editor.isBill && s.kind === "goal" && d.reminder !== "off" && !s.times.length) s.times = [eveningMinute()];
  return S.normalized(s);
}
// True if "The day before" makes sense as a reminder.
function dayBeforeAllowed() {
  const s = editor.draft.schedule;
  if (s.kind === "goal") return false;
  if (s.kind === "once") return true;
  return s.unit !== "hour" && !(s.unit === "day" && s.every === 1);
}
// Automatic payment only for repeating and one-time bills.
const allowsAutopay = () => editor.draft.schedule.kind === "repeating" || editor.draft.schedule.kind === "once";
// The bill being edited is set to pay itself.
const paidAutomatically = () => editor.isBill && editor.draft.autopay && allowsAutopay();
// True if the item has a time of day (decides "At the time" vs "In the morning").
function hasTime() {
  const s = editor.draft.schedule, t = editor.times.length > 0;
  if (s.kind === "repeating") return s.unit === "hour" || s.afterWaking != null || t;
  if (s.kind === "afterDone") return s.unit === "hour" || t;
  return t;
}
// The Amount field as a number, or null if empty/invalid.
function parsedAmount() { const v = parseAmount(editor.amountText); return v != null && v > 0 ? v : null; }
// Add/Save is enabled only with a title (and an amount for bills).
function canSave() { if (!editor.draft.title.trim()) return false; return !editor.isBill || parsedAmount() != null; }
// After any editor change: fixes combinations that don't make sense (like the app's editor).
function keepConsistent() {
  const d = editor.draft, s = d.schedule;
  if (s.kind === "repeating" && s.unit === "hour" && s.every > 12) s.every = 12;
  if (s.unit === "week" && !s.weekdays.length) s.weekdays = [weekday(s.start)];
  if (s.kind === "afterDone") { if (s.nextDue == null) s.nextDue = livingDay(); if (s.unit === "hour" && s.nextDueTime == null) s.nextDueTime = roundedNow(); }
  if (!S.supportsWake(s) && s.afterWaking != null) s.afterWaking = null;
  if (d.reminder === "dayBefore" && !dayBeforeAllowed()) d.reminder = "onTime";
  if (d.reminder === "whenBehind" && s.kind !== "goal") d.reminder = "onTime";
}
// Puts back a sensible reminder when the old one no longer applies.
function restoreReminder() {
  const d = editor.draft;
  if (d.reminder !== "off" && d.reminder !== "whenBehind") return;
  const o = editor.baseline;
  if (o.schedule.kind === "goal" || o.reminder === "whenBehind") d.reminder = editor.isBill ? "dayBefore" : "onTime";
  else d.reminder = o.reminder;
}
// Switches schedule kind (repeating, once, after completion, any day).
function setKind(kind) {
  const s = editor.draft.schedule, wasAnyDay = s.kind === "goal";
  if (kind === "repeating" && wasAnyDay) return;
  s.kind = kind;
  if (kind === "repeating") s.fromDone = false;
  if (wasAnyDay) restoreReminder();
}
// Changes the Repeat unit (hour/day/week/month/year).
function setFrequency(unit) {
  const s = editor.draft.schedule;
  if (unit === frequency()) return;
  if (s.kind === "goal") {
    if (unit === "week" || unit === "month") { s.goalPeriod = unit; return; }
    s.kind = "repeating"; restoreReminder();
  }
  if (s.kind === "afterDone" && unit === "hour") { s.kind = "repeating"; s.fromDone = true; }
  else if (s.kind === "repeating" && s.fromDone && unit !== "hour") { s.kind = "afterDone"; s.fromDone = false; if (s.nextDue == null) s.nextDue = livingDay(); }
  s.unit = unit;
  if (unit === "hour" && s.afterWaking == null && !editor.isBill) s.afterWaking = 0;
}
// Repeat menu for tasks (Never, Hourly, Daily, ...).
function setTaskRepeat(choice) {
  const s = editor.draft.schedule;
  const current = s.kind === "once" ? "never" : frequency();
  if (choice === current) return;
  if (choice === "never") { setKind("once"); return; }
  if (s.kind === "once") setKind("repeating");
  setFrequency(choice);
}
// "Repeat After Completion" checkbox.
function setRepeatAfter(on) {
  const s = editor.draft.schedule;
  if (s.unit === "hour") { s.kind = "repeating"; s.fromDone = on; }
  else if (on) { const next = S.nextOccurrence(previewSchedule(), livingDay()) || livingDay(); s.kind = "afterDone"; s.nextDue = next; }
  else { s.kind = "repeating"; s.fromDone = false; s.start = s.nextDue || livingDay(); }
}
// "Any Day" vs "Specific Day" for weekly/monthly items.
function setAnyDay(anyDay) {
  const d = editor.draft, s = d.schedule;
  if (anyDay === (s.kind === "goal")) return;
  const unit = frequency();
  if (anyDay) {
    const o = editor.baseline, period = unit === "month" ? "month" : "week";
    const wasEvery = s.every, wd = S.effectiveWeekdays(s).length;
    s.kind = "goal"; s.goalPeriod = period;
    s.goalCount = o.schedule.kind === "goal" && o.schedule.goalPeriod === period ? o.schedule.goalCount : unit === "week" && wasEvery === 1 ? wd : 1;
    d.reminder = o.schedule.kind === "goal" ? o.reminder : editor.isBill ? "off" : "whenBehind";
    if (!editor.isBill && d.reminder !== "off" && !editor.times.length) editor.times = [eveningMinute()];
  } else { s.kind = "repeating"; s.unit = unit; restoreReminder(); }
}
// Repeat menu for bills.
function setBillRepeat(choice) {
  const s = editor.draft.schedule;
  if (choice === "once") { s.kind = "once"; return; }
  if (s.kind === "goal" && (choice === "week" || choice === "month")) { s.goalPeriod = choice; return; }
  if (s.kind === "afterDone") s.unit = choice; else { s.kind = "repeating"; s.unit = choice; }
}
// Current value for the bill Repeat menu.
function billRepeat() { const s = editor.draft.schedule; if (s.kind === "once") return "once"; const f = frequency(); return f === "hour" ? "day" : f; }
// Changes the start date (and the next due date that depends on it).
function setStart(day) {
  const s = editor.draft.schedule, old = weekday(s.start);
  s.start = day;
  if (s.unit === "week" && s.weekdays.length === 1 && s.weekdays[0] === old) s.weekdays = [weekday(day)];
}
// Keeps "after completion" items in step when times are added/removed.
const timesChanged = () => { if (editor.draft.schedule.kind === "afterDone") editor.draft.schedule.nextDueTime = null; };
// Builds a <select> for the editor. options = [[value, label], ...].
function sel(f, options, value, extra = "") {
  return '<select data-f="' + f + '"' + extra + ">" + options.map(([v, t]) => '<option value="' + esc(v) + '"' + (String(v) === String(value) ? " selected" : "") + ">" + esc(t) + "</option>").join("") + "</select>";
}
// "How often" menu (Every day, Every 2 days, ...).
function everyRow() {
  const s = editor.draft.schedule, max = s.kind === "repeating" && s.unit === "hour" ? 12 : 99, opts = [];
  for (let n = 1; n <= Math.max(max, s.every); n++) opts.push([n, Format.every(n, s.unit)]);
  return "<p><label>How often<br>" + sel("every", opts, s.every) + "</label></p>";
}
// "How many times" menu for any-day items.
function goalRow() {
  const s = editor.draft.schedule, opts = [];
  for (let n = 1; n <= 99; n++) opts.push([n, Format.goal(n, s.goalPeriod)]);
  return "<p><label>How many times<br>" + sel("goalCount", opts, s.goalCount) + "</label></p>";
}
// Weekday checkboxes for weekly items.
function weekdayRow() {
  const s = editor.draft.schedule, on = S.effectiveWeekdays(s), names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
  let h = "<p>On<br>";
  for (let k = 0; k < 7; k++) { const d = ((FIRST_WEEKDAY - 1 + k) % 7) + 1; h += '<label><input type="checkbox" data-f="wd" value="' + d + '"' + (on.includes(d) ? " checked" : "") + "> " + names[d - 1].slice(0, 3) + "</label> "; }
  return h + "</p>";
}
// A labelled date field.
const dateRow = (label, f, value) => "<p><label>" + label + '<br><input type="date" data-f="' + f + '" value="' + esc(value) + '" required></label></p>';
// Time pickers with Add a Time / Remove (up to `limit` times).
function timeRows(limit) {
  let h = "";
  editor.times.forEach((t, k) => { h += "<p>Time " + (editor.times.length > 1 ? k + 1 : "") + "<br>" + timePicker("time" + k, t) + ' <button type="button" data-e="removeTime" value="' + k + '">Remove</button></p>'; });
  if (!editor.times.length) h += "<p>Time: Anytime</p>";
  if (editor.times.length < limit) h += '<p><button type="button" data-e="addTime">Add a Time</button></p>';
  return h;
}
// Draws the editor. Called again after every change so only relevant fields show.
function renderEditor() {
  const d = editor.draft, s = d.schedule, code = db.settings.currency;
  // Like the app's editor: Cancel on the left, the title in the middle, Add or Save on the right.
  let h = '<table width="100%" cellspacing="0" cellpadding="0"><tr><td width="20%" align="left"><button type="button" data-e="cancel">Cancel</button></td><td align="center"><h2>' + (editor.isNew ? (editor.isBill ? "New Bill" : "New Task") : "Details") +
    '</h2></td><td width="20%" align="right"><button type="submit" id="saveBtn"' + (canSave() ? "" : " disabled") + ">" + (editor.isNew ? "Add" : "Save") + "</button></td></tr></table>";
  h += "<fieldset><legend>Name</legend><p><label>Title<br><input data-f=\"title\" value=\"" + esc(d.title) + "\" autocomplete=\"off\" size=\"30\"></label></p>";
  if (editor.isBill) h += "<p><label>Amount (" + esc(Format.symbol(code)) + ")<br><input data-f=\"amount\" inputmode=\"decimal\" value=\"" + esc(editor.amountText) + "\" size=\"12\"></label></p>";
  h += "<p><label>Notes<br><textarea data-f=\"notes\" rows=\"2\" cols=\"30\">" + esc(d.notes) + "</textarea></label></p></fieldset>";
  const repeatTask = sel("taskRepeat", [["never", "Never"], ["hour", "Hourly"], ["day", "Daily"], ["week", "Weekly"], ["month", "Monthly"], ["year", "Yearly"]], s.kind === "once" ? "never" : frequency());
  const f = frequency();
  // Specific Day / Any Day menu.
  const anyDayPicker = () => "<p><label>Day<br>" + sel("anyDay", [["no", f === "week" ? "Specific Days" : "Specific Day"], ["yes", "Any Day"]], s.kind === "goal" ? "yes" : "no") + "</label></p>";
  // "Repeat After Completion" checkbox.
  const afterToggle = (label) => '<p><label><input type="checkbox" data-f="repeatAfter"' + (s.kind === "afterDone" || s.fromDone ? " checked" : "") + "> " + label + "</label></p>";
  if (editor.isBill) {
    h += "<fieldset><legend>Due</legend><p><label>Repeat<br>" + sel("billRepeat", [["once", "Never"], ["day", "Daily"], ["week", "Weekly"], ["month", "Monthly"], ["year", "Yearly"]], billRepeat()) + "</label></p>";
    if (s.kind === "once") h += dateRow("Date", "start", s.start);
    else if (s.kind === "afterDone") h += everyRow() + afterToggle("Repeat After Payment") + dateRow("Next Date", "nextDue", s.nextDue || s.start);
    else {
      if (f === "week" || f === "month") h += anyDayPicker();
      if (s.kind === "goal") h += goalRow();
      else { h += everyRow(); if (!d.autopay) h += afterToggle("Repeat After Payment"); if (s.unit === "week") h += weekdayRow(); h += dateRow("Start Date", "start", s.start); }
    }
    h += "</fieldset>";
    if (s.kind !== "goal") {
      h += "<fieldset><legend>Payment</legend>";
      if (allowsAutopay()) h += "<p><label>Payment<br>" + sel("autopay", [["no", "Manual"], ["yes", "Automatic"]], d.autopay ? "yes" : "no") + "</label></p>";
      if (!paidAutomatically()) {
        const o = [["off", "None"]]; if (dayBeforeAllowed()) o.push(["dayBefore", "The day before"]); o.push(["onTime", "On the day"]);
        h += "<p><label>Remind Me<br>" + sel("reminder", o, d.reminder) + "</label></p>";
      }
      h += "</fieldset>";
    }
  } else {
    h += "<fieldset><legend>Repeat</legend><p><label>Repeat<br>" + repeatTask + "</label></p>";
    if (s.kind === "afterDone") h += everyRow() + afterToggle("Repeat After Completion") + dateRow("Next Date", "nextDue", s.nextDue || s.start);
    else if (s.kind === "once") h += dateRow("Date", "start", s.start);
    else {
      if (f === "week" || f === "month") h += anyDayPicker();
      if (s.kind === "goal") h += goalRow();
      else {
        h += everyRow() + afterToggle("Repeat After Completion");
        if (s.unit === "week") h += weekdayRow();
        if (s.unit !== "hour" || s.start > livingDay()) h += dateRow("Start Date", "start", s.start);
      }
    }
    h += "</fieldset>";
    if (s.kind !== "goal") {
      h += "<fieldset><legend>Time</legend>";
      if (s.kind === "afterDone" || s.kind === "once") h += timeRows(1);
      else {
        if (S.supportsWake(s)) {
          h += '<p><label><input type="checkbox" data-f="wake"' + (s.afterWaking != null ? " checked" : "") + "> After I Wake Up</label></p>";
          if (s.afterWaking != null) h += "<p><label>" + (s.unit === "hour" ? "Starts" : "Time") + "<br>" + wakeOffsetMenu(s.afterWaking) + "</label></p>";
        }
        if (s.unit === "hour") { if (s.afterWaking == null) h += "<p>Starts<br>" + timePicker("single", editor.times.length ? editor.times[0] : Sleep.usualWake(sleepLog)) + "</p>"; }
        else if (s.afterWaking == null) h += timeRows(12);
      }
      h += "</fieldset>";
    }
    const o = [["off", "None"]];
    if (s.kind === "goal") o.push(["whenBehind", "When I'm behind"], ["onTime", "Every day"]);
    else { o.push(["onTime", hasTime() ? "At the time" : "In the morning"]); if (dayBeforeAllowed()) o.push(["dayBefore", "The day before"]); }
    h += "<fieldset><legend>Reminder</legend><p><label>Remind Me<br>" + sel("reminder", o, d.reminder) + "</label></p>";
    if (s.kind === "goal" && d.reminder !== "off") h += "<p>Time<br>" + timePicker("single", editor.times.length ? editor.times[0] : eveningMinute()) + "</p>";
    h += "</fieldset>";
  }
  h += "<p align=\"center\"><small>" + esc(S.summary(previewSchedule())) + "</small></p>";
  if (!editor.isNew) {
    h += '<fieldset><legend>Pause</legend><p><label><input type="checkbox" data-f="paused"' + (d.paused ? " checked" : "") + "> Paused</label></p></fieldset>";
    const recent = [...d.log].sort((a, b) => b.at - a.at).slice(0, 5);
    if (recent.length) {
      h += '<details><summary>History</summary><table cellpadding="4" cellspacing="0" frame="void" rules="rows">';
      for (const e of recent) h += "<tr><td>" + (e.kind === "done" ? (editor.isBill ? "Paid" : "Done") : "Skipped") + "</td><td>" + esc(new Date(e.at).toLocaleString(LOC, { dateStyle: "medium", timeStyle: "short" })) + "</td><td align=\"right\">" + (editor.isBill && e.amount != null ? esc(Format.money(e.amount, code)) : "") + "</td></tr>";
      h += "</table></details>";
    }
  }
  if (!editor.isNew) h += '<p align="center"><button type="button" data-e="delete">' + (editor.isBill ? "Delete Bill" : "Delete Task") + "</button></p>";
  $("editorBody").innerHTML = h;
}
// Handles a change to any editor field (data-f tells which), then redraws.
function editorChange(t) {
  const d = editor.draft, s = d.schedule, f = t.dataset.f;
  const tp = t.closest("[data-tp]");
  if (tp) {
    // Currency name in the user's language, like "Moroccan Dirham".
    const name = tp.dataset.tp, m = readPicker(tp);
    if (name === "single") { if (s.kind === "afterDone") s.nextDueTime = null; editor.times = editor.times.length ? [m, ...editor.times.slice(1)] : [m]; }
    else { editor.times[+name.slice(4)] = m; timesChanged(); }
  }
  else switch (f) {
    case "taskRepeat": setTaskRepeat(t.value); keepConsistent(); break;
    case "billRepeat": setBillRepeat(t.value); keepConsistent(); break;
    case "anyDay": setAnyDay(t.value === "yes"); keepConsistent(); break;
    case "every": s.every = +t.value; keepConsistent(); break;
    case "goalCount": s.goalCount = +t.value; break;
    case "repeatAfter": setRepeatAfter(t.checked); keepConsistent(); break;
    case "wd": {
      const v = +t.value, cur = S.effectiveWeekdays(s).slice();
      if (t.checked) { if (!cur.includes(v)) cur.push(v); } else if (cur.length > 1) cur.splice(cur.indexOf(v), 1);
      s.weekdays = cur.sort((a, b) => a - b); break;
    }
    case "start": if (validDay(t.value)) setStart(t.value); break;
    case "nextDue": if (validDay(t.value)) { s.nextDue = t.value; s.nextDueTime = s.unit === "hour" ? (s.nextDueTime != null ? s.nextDueTime : roundedNow()) : null; } break;
    case "wake": s.afterWaking = t.checked ? (s.afterWaking != null ? s.afterWaking : 0) : null; break;
    case "reminder":
      d.reminder = t.value;
      if (!editor.isBill && s.kind === "goal" && d.reminder !== "off" && !editor.times.length) editor.times = [eveningMinute()];
      break;
    case "autopay": d.autopay = t.value === "yes"; break;
    case "paused": d.paused = t.checked; break;
    case "offset": s.afterWaking = +t.value; break;
    default: return;
  }
  renderEditor();
}
// Validates and saves the editor's item.
function saveEditor() {
  if (!canSave()) return;
  const item = clone(editor.draft), base = editor.baseline;
  item.title = item.title.trim(); item.notes = (item.notes || "").trim();
  item.schedule = previewSchedule();
  item.cost = editor.isBill ? parsedAmount() : null;
  if (item.cost == null || !allowsAutopay()) item.autopay = false;
  if (I.isAutopay(item) || I.isAnyDayBill(item)) item.reminder = "off";
  if (item.reminder === "dayBefore" && !dayBeforeAllowed()) item.reminder = "onTime";
  const today = livingDay();
  if (item.paused !== base.paused) { const p = item.paused; item.paused = base.paused; I.setPaused(item, p, today); }
  if (editor.isNew) { item.createdAt = Date.now(); item.trackFrom = today; }
  else if (JSON.stringify(item.schedule) !== JSON.stringify(S.normalized(base.schedule))) { item.trackFrom = today; item.snoozes = []; }
  closeEditor();
  saveItem(item);
  if (item.reminder !== "off" && typeof Notification !== "undefined" && Notification.permission === "default" && prefs.reminders) Notification.requestPermission().then(() => { renderNotify(); planReminders(); });
}
// Closes the editor without saving.
function closeEditor() { editor.open = false; closePanel("editor"); render(); }

// ---------- Export / import ----------
function exportData() {
  const data = { app: "Routine", version: 5, exportedAt: new Date().toISOString(), items: db.items, wakes: db.wakes, wakeStamps: db.wakeStamps, wakesModifiedAt: db.wakesModifiedAt, settings: db.settings };
  if (NATIVE) { toNative({ type: "export", name: "routine-" + dayOf(Date.now()) + ".json", text: JSON.stringify(data, null, 1) }); return; }
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([JSON.stringify(data, null, 1)], { type: "application/json" }));
  a.download = "routine-" + dayOf(Date.now()) + ".json";
  document.body.appendChild(a); a.click(); a.remove();
}
// Merges a backup file into this browser. Same item in both: the newer modifiedAt wins. Returns a short result text.
// Merges another copy of the data (an imported file or the synced copy) into this one. Doesn't save.
// - Tasks and bills: the most recently changed version wins (modifiedAt). Check-offs are combined, so
//   marking something done on one device and editing it on another (both offline) keeps both;
//   undone check-offs (logGone) stay undone. Deleted stays deleted.
// - Wake-up times: each day on its own, the most recently changed wins.
// - Settings: the most recently changed wins.
// Returns how many were added and updated, and whether anything here changed.
function mergeData(d) {
  let added = 0, updated = 0, changed = false;
  for (const raw of d.items) {
    const it = fixItem(raw), i = db.items.findIndex((x) => x.id === it.id);
    if (i < 0) { db.items.push(it); added++; continue; }
    const mine = db.items[i], merged = mergeItem(mine, it);
    if (sameText({ items: [merged] }) !== sameText({ items: [mine] })) { db.items[i] = merged; updated++; }
  }
  const oldest = addDays(dayOf(Date.now()), -30);
  if (d.wakeStamps) {
    for (const [k, t] of Object.entries(d.wakeStamps)) {
      const mineT = db.wakeStamps[k] || 0, v0 = d.wakes ? d.wakes[k] : undefined;
      // Newer wins; with the same time, a time that's set wins over one that's missing (so all devices agree).
      if (k < oldest || !(t > mineT || (t === mineT && db.wakes[k] == null && v0 != null))) continue;
      db.wakeStamps[k] = t;
      const v = d.wakes ? d.wakes[k] : undefined;
      if (db.wakes[k] !== v) { if (v == null) delete db.wakes[k]; else db.wakes[k] = v; changed = true; }
    }
    if ((d.wakesModifiedAt || 0) > db.wakesModifiedAt) db.wakesModifiedAt = d.wakesModifiedAt;
  } else if (d.wakes && (d.wakesModifiedAt || 0) > db.wakesModifiedAt) {
    // Files from before per-day stamps: the whole set, newest wins.
    db.wakes = d.wakes; db.wakesModifiedAt = d.wakesModifiedAt; changed = true;
  }
  wakesSaved = clone(db.wakes);
  if (d.settings && (d.settings.modifiedAt || 0) > db.settings.modifiedAt) { db.settings = Object.assign(db.settings, d.settings); changed = true; }
  stampFloor = Math.max(stampFloor, newestStamp(d));
  return { added, updated, changed: changed || added + updated > 0 };
}
// One task or bill from two devices: the newer version, plus check-offs only the other one has.
function mergeItem(mine, theirs) {
  // Same change time but different contents (for example history trimmed on one device): every device
  // picks the same one, so they all end up identical.
  const tie = theirs.modifiedAt === mine.modifiedAt && sameText({ items: [theirs] }) > sameText({ items: [mine] });
  const newer = theirs.modifiedAt > mine.modifiedAt || tie ? theirs : mine, older = newer === mine ? theirs : mine;
  const out = clone(newer);
  const gone = new Map();
  for (const g of [...mine.logGone, ...theirs.logGone]) if (!gone.has(g.id) || gone.get(g.id).at < g.at) gone.set(g.id, g);
  out.logGone = [...gone.values()];
  const have = new Set(out.log.map((e) => e.id));
  const extra = older.log.filter((e) => !have.has(e.id) && !gone.has(e.id) && out.deletedAt == null);
  out.log = out.log.filter((e) => !gone.has(e.id)).concat(extra).sort((a, b) => a.at - b.at);
  // "After completion" tasks move their next date when checked off; keep the later one.
  const ns = out.schedule, os = older.schedule;
  if (extra.length && ns.kind === "afterDone" && os.kind === "afterDone" && os.nextDue && (!ns.nextDue || os.nextDue > ns.nextDue)) { ns.nextDue = os.nextDue; ns.nextDueTime = os.nextDueTime; }
  return out;
}
// Reads an exported file and merges it in.
function importData(text) {
  const d = JSON.parse(text);
  if (!d || !Array.isArray(d.items)) throw new Error("This file isn't a Routine backup.");
  const r = mergeData(d);
  commit();
  return r.added + " added, " + r.updated + " updated.";
}

// ---------- Sync (GitHub) ----------
// Like wordpad.cc: open the site on any device and your tasks and bills are there. Nothing to set up.
// The data is saved as data.json in SYNC_REPO, on the "data" branch (so saving never rebuilds the site),
// using the token below. The token is in the code on purpose (the owner chose this): anyone who reads
// the code can read and change the data and the repository. To use another token, replace SYNC_TOKEN_PARTS
// with the output of: btoa("<token>".split("").reverse().join("")) split into pieces (keeps GitHub's
// secret scanner from revoking it).
// Each sync: download data.json, merge (newest change wins, see mergeData), upload if this device has
// anything newer. Uploads send the file's last version (sha); if another device saved first, GitHub
// refuses (409) and we merge again. Every save is a commit, so the branch keeps the full history.
const GITHUB_API = "https://api.github.com";
const SYNC_REPO = "ossamamektane/routine", DATA_BRANCH = "data", DATA_FILE = "data.json";
const SYNC_TOKEN_PARTS = ["dGRVRDNZQnRHTjJYQVI0QlA3Uk9paEVyem9JRTdKM", "3BtSWNReFBDVm5IdExqeGNYNHRsWWZYYXZuWHFfc2", "9ZUHhJTk92amlVMEk3UlhZUEMxMV90YXBfYnVodGln"];
const SYNC_TOKEN = (() => { try { return atob(SYNC_TOKEN_PARTS.join("")).split("").reverse().join(""); } catch (e) { return ""; } })();
// UTF-8 text <-> base64 (GitHub sends file contents as base64).
const textB64 = (text) => { const u8 = new TextEncoder().encode(text); let t = ""; for (let i = 0; i < u8.length; i += 32768) t += String.fromCharCode.apply(null, u8.subarray(i, i + 32768)); return btoa(t); };
const b64Text = (t) => new TextDecoder().decode(Uint8Array.from(atob(String(t).replace(/\s/g, "")), (c) => c.charCodeAt(0)));
// The part of the data that syncs: the same as an export, so data.json can also be imported.
const syncPayload = () => ({ app: "Routine", version: 5, items: db.items, wakes: db.wakes, wakeStamps: db.wakeStamps, wakesModifiedAt: db.wakesModifiedAt, settings: db.settings });
// JSON with keys in a fixed order and items sorted by ID, so two equal copies compare equal.
function sameText(o) {
  const norm = (v) => Array.isArray(v) ? v.map(norm) : v && typeof v === "object" ? Object.keys(v).sort().reduce((a, k) => (a[k] = norm(v[k]), a), {}) : v;
  // Wake-up times older than 30 days are dropped on each device anyway, so they're left out of the comparison.
  const oldest = addDays(dayOf(Date.now()), -30), recent = (m) => Object.fromEntries(Object.entries(m || {}).filter(([k]) => k >= oldest));
  const c = norm({ items: o.items || [], wakes: recent(o.wakes), wakeStamps: recent(o.wakeStamps), settings: o.settings || {} });
  c.items = [...c.items].sort((a, b) => (a.id < b.id ? -1 : 1));
  return JSON.stringify(c);
}
// Calls the GitHub API. Returns { status, body, limited }.
async function gh(method, path, body) {
  let r;
  try {
    r = await fetch(GITHUB_API + path, { method, cache: "no-store", headers: Object.assign({ Accept: "application/vnd.github+json", Authorization: "Bearer " + SYNC_TOKEN }, body ? { "Content-Type": "application/json" } : {}), body: body ? JSON.stringify(body) : undefined });
  } catch (e) { return { status: 0, body: null }; }
  let b = null; try { b = await r.json(); } catch (e) {}
  return { status: r.status, body: b, limited: r.headers.get("x-ratelimit-remaining") === "0" };
}
const fileURL = "/repos/" + SYNC_REPO + "/contents/" + DATA_FILE;
// Turns a GitHub answer into a reason for the status line.
const ghReason = (r) => r.status === 0 ? (navigator.onLine ? "server" : "offline") : r.status === 401 ? "token" : r.limited ? "busy" : r.status === 403 || r.status === 404 ? "access" : "server";
// Makes the "data" branch the first time (from the repository's main branch).
async function ensureBranch() {
  if ((await gh("GET", "/repos/" + SYNC_REPO + "/branches/" + DATA_BRANCH)).status === 200) return;
  const info = await gh("GET", "/repos/" + SYNC_REPO);
  if (info.status !== 200 || !info.body) throw new Error(ghReason(info));
  const main = await gh("GET", "/repos/" + SYNC_REPO + "/git/ref/heads/" + info.body.default_branch);
  if (main.status !== 200 || !main.body) throw new Error(ghReason(main));
  const made = await gh("POST", "/repos/" + SYNC_REPO + "/git/refs", { ref: "refs/heads/" + DATA_BRANCH, sha: main.body.object.sha });
  if (made.status !== 201 && made.status !== 422) throw new Error(ghReason(made));
}
// syncDirty: there are changes here that GitHub doesn't have yet (saved with the data, so it survives closing).
let syncBusy = false, syncAgain = false, syncTimer = 0, syncMerging = false;
// Syncs a few seconds after a change, so quick changes are saved together in one commit.
function scheduleSync(ms) { if (!SYNC_TOKEN) return; clearTimeout(syncTimer); syncTimer = setTimeout(syncNow, ms == null ? 4000 : ms); }
// One sync with GitHub.
async function syncNow() {
  if (!SYNC_TOKEN) return;
  if (syncBusy) { syncAgain = true; return; }
  if (!navigator.onLine) { setSyncState("offline"); return; }
  syncBusy = true;
  setSyncState("syncing");
  try {
    let saved = false;
    for (let tries = 0; tries < 4 && !saved; tries++) {
      const got = await gh("GET", fileURL + "?ref=" + DATA_BRANCH);
      let sha = null;
      if (got.status === 200 && got.body) {
        sha = got.body.sha;
        let remote;
        try { remote = JSON.parse(b64Text(got.body.content || "")); } catch (e) { throw new Error("file"); }
        if (!remote || !Array.isArray(remote.items)) throw new Error("file");
        if (mergeData(remote).changed) { syncMerging = true; commit(); syncMerging = false; }
        if (sameText(remote) === sameText(syncPayload())) { saved = true; break; }
      } else if (got.status === 404) await ensureBranch();
      else throw new Error(ghReason(got));
      const put = await gh("PUT", fileURL, Object.assign({ message: "Update " + DATA_FILE, branch: DATA_BRANCH, content: textB64(JSON.stringify(syncPayload(), null, 1) + "\n") }, sha ? { sha } : {}));
      if (put.status === 200 || put.status === 201) { saved = true; break; }
      if (put.status === 409 || put.status === 422) { await new Promise((ok) => setTimeout(ok, 300 + Math.random() * 1200)); continue; } // someone saved first: merge again
      throw new Error(ghReason(put));
    }
    if (!saved) throw new Error("server");
    prefs.syncAt = Date.now(); prefs.syncDirty = false;
    setSyncState("ok");
  } catch (e) {
    setSyncState(SYNC_PROBLEMS[e.message] ? e.message : "server");
  } finally {
    syncBusy = false;
    if (syncAgain) { syncAgain = false; scheduleSync(500); }
  }
}
// What each problem looks like in Settings.
const SYNC_PROBLEMS = {
  offline: "Offline. Changes will be saved later.",
  token: "The GitHub token in the code is wrong or has expired.",
  access: "The GitHub token in the code can't save to " + SYNC_REPO + ".",
  busy: "GitHub is busy. Trying again later.",
  file: DATA_FILE + " on GitHub couldn't be read.",
  server: "Couldn't reach GitHub. Trying again later."
};
let syncState = "";
// Remembers and shows the sync status.
function setSyncState(state) { syncState = state; if (state === "ok") savePrefs(); renderSync(); }
// "Saved 5 min ago" and the like, for Settings.
function syncStatusText() {
  if (!SYNC_TOKEN) return "Off";
  const ago = (t) => { const m = Math.floor((Date.now() - t) / 60e3); return m < 1 ? "just now" : m < 60 ? m + " min ago" : dayOf(t) === dayOf(Date.now()) ? "at " + Format.timeMs(t) : Format.day(dayOf(t)); };
  if (syncState === "syncing") return "Saving\u2026";
  if (syncState === "offline" && prefs.syncDirty) return "Offline. Your latest changes are on this device and will be saved when you're back online.";
  if (SYNC_PROBLEMS[syncState]) return SYNC_PROBLEMS[syncState];
  return prefs.syncAt ? "Saved " + ago(prefs.syncAt) : "Not saved yet";
}
// Fills the Sync row in Settings.
function renderSync() { $("syncText").textContent = syncStatusText(); }

// ---------- Events ----------
function onAction(sel) {
  const v = sel.value;
  const e = rowMap[sel.dataset.act];
  if (!e || !v) return;
  const item = findItem(e.itemID);
  if (!item) return;
  if (v === "done") complete(e.itemID, e.day, e.slot, false);
  else if (v === "skip") complete(e.itemID, e.day, e.slot, true);
  else if (v === "undo") undo(e.itemID, e.logID);
  else if (v === "edit") openEditor(item, false, I.hasCost(item));
  else if (v === "doneAt") openAt({ kind: "done", e }, (e.isBill ? "Paid" : "Done") + " At", Date.now());
  else if (v === "changeAt") openAt({ kind: "change", e }, "Change Time", e.at);
  else if (v === "pause") setPausedItem(e.itemID, true);
  else if (v.startsWith("later:")) snooze(e.itemID, e.day, e.slot, +v.slice(6));
  else if (v === "later") openAt({ kind: "later", e }, "Later", e.snoozedUntil != null && e.snoozedUntil > Date.now() ? e.snoozedUntil : Date.now() + 3600e3);
}
// Runs a More button from a Tasks or Bills row.
function onItemMenu(sel) {
  const v = sel.value;
  const item = findItem(sel.dataset.item);
  if (!item || !v) return;
  if (v === "edit") openEditor(item, false, I.hasCost(item));
  else if (v === "duplicate") {
    const c = clone(item);
    Object.assign(c, { id: uid(), log: [], snoozes: [], paused: false, pauses: [], deletedAt: null, createdAt: Date.now(), trackFrom: clockNow().day });
    openEditor(c, true, I.hasCost(c));
  } else if (v === "pause") setPausedItem(item.id, !item.paused);
  else if (v === "undoPay") { const l = I.lastDone(item); if (l) undo(item.id, l.id); }
  else if (v === "delete" && confirm("Delete “" + I.title(item) + "”?\n" + (I.hasCost(item) ? "This bill" : "This task") + " and its history will be deleted.")) deleteItem(item.id);
}
document.addEventListener("change", (ev) => {
  const t = ev.target;
  if ($("editor").contains(t)) { if (t.dataset.f !== "title" && t.dataset.f !== "notes" && t.dataset.f !== "amount") editorChange(t); return; }
  if (t.dataset.check != null) {
    const e = rowMap[t.dataset.check];
    if (!e) return;
    if (isFinishedEntry(e)) undo(e.itemID, e.logID); else if (canComplete(e)) complete(e.itemID, e.day, e.slot, false);
  }
});
document.addEventListener("input", (ev) => {
  const t = ev.target, f = t.dataset && t.dataset.f;
  if (!$("editor").contains(t)) return;
  if (f === "title") editor.draft.title = t.value;
  else if (f === "notes") editor.draft.notes = t.value;
  else if (f === "amount") editor.amountText = t.value;
  else return;
  const b = $("saveBtn"); if (b) b.disabled = !canSave();
});
document.addEventListener("click", (ev) => {
  const t = ev.target.closest("button");
  if (!t) return;
  const act = t.dataset.do, e = t.dataset.e;
  if (t.dataset.more != null) { showMenu(t.getAttribute("aria-expanded") === "true" ? null : t.dataset.more); return; }
  if (t.dataset.act != null || t.dataset.item != null) { showMenu(null); t.dataset.act != null ? onAction(t) : onItemMenu(t); return; }
  if (act === "wake") openWake(false);
  else if (act === "sleepYes") openWake(true);
  else if (act === "sleepNo") answerStillUp();
  else if (act === "notNow") dismissQuestion();
  else if (act === "goTasks") showTab("tasks");
  else if (act === "addTask") openEditor(newItem(Date.now()), true, false);
  else if (act === "addBill") openEditor(billTemplate(), true, true);
  else if (e === "cancel") closeEditor();
  else if (e === "addTime") { const last = editor.times.length ? Math.max(...editor.times) : null; editor.times.push(last == null ? 540 : Math.min(last + 240, 1320)); timesChanged(); renderEditor(); }
  else if (e === "removeTime") { editor.times.splice(+t.value, 1); timesChanged(); renderEditor(); }
  else if (e === "delete") { if (confirm("Delete “" + I.title(editor.draft) + "”?\n" + (editor.isBill ? "This bill" : "This task") + " and its history will be deleted.")) { const id = editor.draft.id; closeEditor(); deleteItem(id); } }
});
$("form").addEventListener("submit", (ev) => { ev.preventDefault(); saveEditor(); });
document.addEventListener("keydown", (ev) => {
  if (ev.key === "Escape" && !panelOpen() && openMenu) { showMenu(null); return; }
  if (ev.key !== "Escape" || !panelOpen()) return;
  ev.preventDefault();
  if (!$("editor").hidden) closeEditor();
  if (!$("wakeDialog").hidden) closePanel("wakeDialog");
  if (!$("atDialog").hidden) { closePanel("atDialog"); atTarget = null; }
});
$("wakeForm").addEventListener("submit", (ev) => {
  ev.preventDefault();
  const b = ev.submitter && ev.submitter.value;
  closePanel("wakeDialog");
  if (b === "save") answerWoke(readWake());
});
$("notUp").addEventListener("click", () => { closePanel("wakeDialog"); clearWake(); });
$("atForm").addEventListener("submit", (ev) => {
  ev.preventDefault();
  const b = ev.submitter && ev.submitter.value, f = $("atForm");
  if (b !== "save" || !atTarget) { closePanel("atDialog"); atTarget = null; return; }
  if (!validDay(f.date.value)) { alert("Choose a date."); return; }
  const n = Date.now(), at = dDate(f.date.value, readPicker($("atTime").querySelector("[data-tp]"))), e = atTarget.e;
  if (atTarget.kind === "later") {
    if (at <= n) { alert("Choose a time later than now."); return; }
    snooze(e.itemID, e.day, e.slot, at);
  } else if (atTarget.kind === "done") complete(e.itemID, e.day, e.slot, false, Math.min(at, n));
  else changeLogTime(e.itemID, e.logID, Math.min(at, n));
  closePanel("atDialog");
  atTarget = null;
});
$("addTask2").addEventListener("click", () => openEditor(newItem(Date.now()), true, false));
// Tabs: one section at a time, like the app. The open tab is remembered (and in the link, e.g. #bills).
const TABS = ["today", "tasks", "bills", "settings"];
// Switches tab, remembers it (prefs + #hash in the address), closes any open panel.
function showTab(name) {
  if (!TABS.includes(name)) name = "today";
  prefs.tab = name; savePrefs();
  if (editor.open) { editor.open = false; render(); }
  atTarget = null;
  for (const p of PANELS) $(p).hidden = true;
  for (const t of TABS) $("tab-" + t).hidden = t !== name;
  if (location.hash !== "#" + name) history.replaceState(null, "", "#" + name);
  renderTabs();
  window.scrollTo(0, 0);
}
// Greys out the open tab's button (you're on it) and shows the Today count.
function renderTabs() {
  const c = clockNow(), n = P.agenda(db.items, c).tasks.filter((e) => P.needsAttention(e, c.now, c.day)).length;
  // Page title: "Routine", with the count of things that need you: "(5) Routine".
  document.title = (n ? "(" + n + ") " : "") + "Routine";
  for (const b of document.querySelectorAll("[data-tab]")) {
    const t = b.dataset.tab, label = { today: "Today", tasks: "Tasks", bills: "Bills", settings: "Settings" }[t] + (t === "today" && n ? " (" + n + ")" : "");
    b.textContent = label;
    b.disabled = t === prefs.tab;
    if (t === prefs.tab) b.setAttribute("aria-current", "page"); else b.removeAttribute("aria-current");
  }
}
for (const b of document.querySelectorAll("[data-tab]")) b.addEventListener("click", () => showTab(b.dataset.tab));
// Keyboard: 1-4 switch tabs, n adds a task (a bill on the Bills tab), / searches.
document.addEventListener("keydown", (ev) => {
  const tag = (ev.target.tagName || "").toLowerCase();
  if (ev.ctrlKey || ev.metaKey || ev.altKey || tag === "input" || tag === "textarea" || tag === "select" || panelOpen()) return;
  if (ev.key >= "1" && ev.key <= "4") { showTab(TABS[+ev.key - 1]); ev.preventDefault(); }
  else if (ev.key === "n" && prefs.tab === "tasks") { ev.preventDefault(); openEditor(newItem(Date.now()), true, false); }
  else if (ev.key === "n" && prefs.tab === "bills") { ev.preventDefault(); openEditor(billTemplate(), true, true); }
  else if (ev.key === "/") { const f = prefs.tab === "bills" ? $("billSearch") : prefs.tab === "tasks" ? $("taskSearch") : null; if (f) { ev.preventDefault(); f.focus(); } }
});
window.addEventListener("hashchange", () => showTab(location.hash.slice(1)));
$("addBill").addEventListener("click", () => openEditor(billTemplate(), true, true));
$("taskSearch").addEventListener("input", () => renderTasks(clockNow()));
$("billSearch").addEventListener("input", () => renderBills(clockNow()));
$("allow").addEventListener("click", () => NATIVE ? toNative({ type: "askPermission" }) : Notification.requestPermission().then(() => { renderNotify(); planReminders(); }));
addEventListener("online", () => scheduleSync(0));
addEventListener("offline", () => setSyncState("offline"));
$("export").addEventListener("click", exportData);
$("updateBtn").addEventListener("click", () => toNative({ type: "open", url: MAC_DOWNLOAD }));
$("importBtn").addEventListener("click", () => $("import").click());
$("import").addEventListener("change", (ev) => {
  const file = ev.target.files[0];
  if (!file) return;
  file.text().then((t) => { try { alert("Import Complete\n" + importData(t)); } catch (err) { alert(err.message || "Couldn't read this file."); } ev.target.value = ""; });
});
$("prefReminders").addEventListener("change", (ev) => { prefs.reminders = ev.target.checked; savePrefs(); if (prefs.reminders && NATIVE && nativePermission === "default") toNative({ type: "askPermission" }); else if (prefs.reminders && typeof Notification !== "undefined" && Notification.permission === "default") Notification.requestPermission().then(planReminders); else planReminders(); renderNotify(); });
$("pref24").addEventListener("change", (ev) => { prefs.hour24 = HOUR24 = ev.target.checked; savePrefs(); render(); planReminders(); });
$("prefBadge").addEventListener("change", (ev) => { prefs.badge = ev.target.checked; savePrefs(); updateBadge(); });
$("currency").addEventListener("change", (ev) => { db.settings.currency = ev.target.value; db.settings.modifiedAt = stamp(db.settings.modifiedAt); commit(); });
// Phones pause pages in the background; catch up as soon as the page is back.
addEventListener("pageshow", () => tick());
addEventListener("focus", () => tick());
document.addEventListener("visibilitychange", () => { if (document.visibilityState !== "visible" && prefs.syncDirty) syncNow(); if (document.visibilityState === "visible") { lastInput = Date.now(); tick(); scheduleSync(0); } else if (Date.now() - lastInput < IDLE_MS) noteActivity(); });

// ---------- Updates (no caching) ----------
// No service worker and no saved copies: every visit loads the newest files.
// VERSION must match the ?v= numbers on the <script> tags in index.html; bump both on every change.
const VERSION = 30;
// Removes the service worker and saved copies left by older versions.
function dropOldCaches() {
  if (navigator.serviceWorker) navigator.serviceWorker.getRegistrations().then((rs) => rs.forEach((r) => r.unregister())).catch(() => {});
  if (window.caches) caches.keys().then((ks) => ks.forEach((k) => caches.delete(k))).catch(() => {});
}
// If the browser showed an older copy of the page, reloads once to get the new one.
function checkForUpdate() {
  if (NATIVE) {
    // The Mac app has its own copy of the page; if the site has a newer one, Settings offers the new app.
    fetch(SITE + "index.html?check=" + Date.now(), { cache: "no-store" }).then((r) => r.text()).then((html) => {
      const m = html.match(/app\.js\?v=(\d+)/);
      $("updateRow").hidden = !(m && +m[1] > VERSION);
    }).catch(() => {});
    return;
  }
  if (location.protocol === "file:") return;
  fetch("index.html?check=" + Date.now(), { cache: "no-store" }).then((r) => r.text()).then((html) => {
    const m = html.match(/app\.js\?v=(\d+)/), latest = m ? +m[1] : VERSION;
    if (latest > VERSION && sessionStorage.getItem("routine-reloaded") !== String(latest)) {
      sessionStorage.setItem("routine-reloaded", String(latest));
      location.reload();
    }
  }).catch(() => {});
}

// ---------- Start ----------
// Fits the page to the screen, again on every resize or rotation: full width on phones,
// a centered 720-pixel column on wider screens, search boxes sized to the space,
// and the currency menu next to its name only when there's room for it.
const PAGE_MAX = 720;
// True on very small screens: the right column of list rows may then wrap onto two lines.
let NARROW = false, fitReady = false;
function fitPage() {
  const w = document.documentElement.clientWidth || innerWidth;
  const page = w > PAGE_MAX + 40 ? PAGE_MAX : w;
  $("page").setAttribute("width", w > PAGE_MAX + 40 ? String(PAGE_MAX) : "100%");
  const size = String(Math.max(12, Math.min(40, Math.floor((page - 60) / 9))));
  $("taskSearch").size = $("billSearch").size = size;
  const wide = page >= 600, sel = $("currency");
  if (wide && sel.parentNode !== $("curRight")) $("curRight").append(sel);
  if (!wide && sel.parentNode !== $("curLeft")) $("curLeft").append(sel);
  $("curBreak").hidden = wide;
  if (NARROW !== (page < 360)) { NARROW = page < 360; if (fitReady) render(); }
  // On narrow screens the menu goes under its name and uses the whole row.
  $("curLeft").colSpan = wide ? 1 : 2;
  $("curRight").hidden = !wide;
  // Long currency names are shortened so the menu never makes the page wider than the screen.
  const max = Math.max(10, Math.floor((wide ? page / 2 : page - 60) / 8) - 6);
  for (const o of sel.options) { const n = o.dataset.name || ""; o.textContent = (n.length > max ? n.slice(0, max - 1).trimEnd() + "…" : n) + " · " + o.value; }
}
let fitTimer = 0;
addEventListener("resize", () => { clearTimeout(fitTimer); fitTimer = setTimeout(fitPage, 100); });
addEventListener("orientationchange", fitPage);

(function start() {
  // Wake-up times saved before each day had its own stamp get one now.
  for (const k of Object.keys(db.wakes)) if (!db.wakeStamps[k]) db.wakeStamps[k] = db.wakesModifiedAt || 1;
  stampFloor = newestStamp(db);
  const name = (c) => { try { return new Intl.DisplayNames([LOC], { type: "currency" }).of(c); } catch (e) { return c; } };
  let codes = Intl.supportedValuesOf ? Intl.supportedValuesOf("currency") : ["MAD", "USD", "EUR", "GBP"];
  if (!codes.includes(db.settings.currency)) codes = [db.settings.currency, ...codes];
  codes = [...codes].sort((a, b) => name(a).localeCompare(name(b)));
  const top = [...new Set([db.settings.currency, "USD", "EUR", "GBP", "MAD", "CAD", "CHF", "AED", "SAR", "DZD", "TND", "EGP", "QAR", "KWD", "TRY", "AUD", "JPY", "INR"])].filter((c) => codes.includes(c));
  // One currency <option>.
  const opt = (c) => '<option value="' + c + '" data-name="' + esc(name(c)) + '">' + esc(name(c)) + " · " + c + "</option>";
  $("currency").innerHTML = '<optgroup label="Suggested">' + top.map(opt).join("") + '</optgroup><optgroup label="All Currencies">' + codes.map(opt).join("") + "</optgroup>";
  try { const n = new Intl.DisplayNames([LOC], { type: "language" }).of(LOC); $("language").textContent = n.charAt(0).toLocaleUpperCase(LOC) + n.slice(1); } catch (e) { $("language").textContent = LOC; }
  fitPage();
  $("currency").value = db.settings.currency;
  // Keyboard shortcuts only matter with a keyboard and mouse, so phones don't show them.
  $("keysRow").hidden = !matchMedia("(pointer: fine)").matches;
  $("prefReminders").checked = prefs.reminders;
  $("prefBadge").checked = prefs.badge;
  $("pref24").checked = HOUR24;
  const seen = Date.now();
  now = seen;
  showTab(location.hash.slice(1) || prefs.tab || "today");
  tick();
  fitReady = true;
  // Every minute, right after the minute changes, so "Now" turns into "1m late" on time.
  (function everyMinute() { setTimeout(() => { tick(); everyMinute(); }, 60e3 - (Date.now() % 60e3) + 250); })();
  // Sync: now, then every minute while the page is showing (60 of GitHub's 5,000 requests an hour).
  renderSync();
  scheduleSync(0);
  setInterval(() => { if (document.visibilityState === "visible") syncNow(); }, 60e3);
  dropOldCaches();
  checkForUpdate();
})();
