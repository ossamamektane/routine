// Routine - model.js
// The rules, with no access to the page: days, schedules, items, the "day you're living" clock,
// "Did you sleep?" detection, the planner (what's on Today) and bill totals.
// It's a port of the iPhone app's Swift Model folder (Day, DayClock, Schedule, Item, Planner, SleepCheck, Money),
// so it behaves the same. Read README.md first; it explains the short names (S, I, C, P) and the data.
"use strict";

// ---------- Day (ISO "YYYY-MM-DD") ----------
const pad = (n, w = 2) => String(n).padStart(w, "0");
// True for leap years (Feb has 29 days).
const isLeap = (y) => (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;
// How many days month m (1-12) has in year y.
function daysIn(y, m) { return m === 2 ? (isLeap(y) ? 29 : 28) : [4, 6, 9, 11].includes(m) ? 30 : 31; }
// Modulo that never returns a negative number (mod(-1, 7) = 6).
function mod(a, b) { const r = a % b; return r < 0 ? r + b : r; }
// Builds an ISO day string from year, month, day. Out-of-range month/day are clamped, so Jan 31 + 1 month = Feb 28.
function mkDay(y, m, d) {
  m = Math.min(Math.max(m, 1), 12);
  d = Math.min(Math.max(d, 1), daysIn(y, m));
  return pad(y, 4) + "-" + pad(m) + "-" + pad(d);
}
// Splits "2026-11-26" into [2026, 11, 26].
function dParts(iso) { return [+iso.slice(0, 4), +iso.slice(5, 7), +iso.slice(8, 10)]; }
// True if the value is a real ISO day string (rejects "2026-02-30", null, etc.).
function validDay(iso) {
  if (typeof iso !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(iso)) return false;
  const [y, m, d] = dParts(iso);
  return m >= 1 && m <= 12 && d >= 1 && d <= daysIn(y, m);
}
// Day number since 1970-01-01. Lets us compare and subtract days without time zones getting in the way.
function dIndex(iso) { const [y, m, d] = dParts(iso); const t = new Date(0); t.setUTCFullYear(y, m - 1, d); return Math.round(t.getTime() / 864e5); }
// The opposite of dIndex: day number -> ISO day string.
function dFromIndex(n) { const t = new Date(n * 864e5); return mkDay(t.getUTCFullYear(), t.getUTCMonth() + 1, t.getUTCDate()); }
// The local calendar day (ISO string) that a timestamp (ms) falls on.
function dayOf(ms) { const t = new Date(ms); return mkDay(t.getFullYear(), t.getMonth() + 1, t.getDate()); }
// Moves an ISO day forward (or back, with a negative n) by n days.
function addDays(iso, n) { return dFromIndex(dIndex(iso) + n); }
function weekday(iso) { return mod(dIndex(iso) + 4, 7) + 1; } // 1 = Sunday ... 7 = Saturday
// The Monday of the week this day is in.
function monday(iso) { return addDays(iso, -((weekday(iso) + 5) % 7)); }
// Months since year 0 (year * 12 + month - 1). Used to step and compare months.
function monthIndex(iso) { const [y, m] = dParts(iso); return y * 12 + (m - 1); }
// Day `day` of month index `mi`, clamped to the month's length.
function inMonth(mi, day) { const y = Math.floor(mi / 12); return mkDay(y, mi - y * 12 + 1, day); }
// Same day of the month, n months later (clamped: Jan 31 + 1 = Feb 28).
function addMonths(iso, n) { return inMonth(monthIndex(iso) + n, dParts(iso)[2]); }
// The 1st of this day's month.
function firstOfMonth(iso) { const [y, m] = dParts(iso); return mkDay(y, m, 1); }
// The last day of this day's month.
function lastOfMonth(iso) { const [y, m] = dParts(iso); return mkDay(y, m, daysIn(y, m)); }
// A timestamp (ms) for a clock time on a day. minutes = minutes after midnight; 1500 means 1:00 AM the next day.
function dDate(iso, minutes = 0) {
  const m = Math.max(minutes, 0);
  const base = m >= 1440 ? addDays(iso, Math.floor(m / 1440)) : iso;
  const inDay = m % 1440;
  const [y, mo, d] = dParts(base);
  const t = new Date(2000, 0, 1, 0, 0, 0, 0);
  t.setFullYear(y, mo - 1, d);
  t.setHours(Math.floor(inDay / 60), inDay % 60, 0, 0);
  return t.getTime();
}
// Minutes after local midnight for a timestamp (0-1439).
function minOfDay(ms) { const t = new Date(ms); return t.getHours() * 60 + t.getMinutes(); }
// Minutes from the start of day `iso` until timestamp `ms` (can be over 1440 after midnight).
function minutesUntil(iso, ms) { return (dIndex(dayOf(ms)) - dIndex(iso)) * 1440 + minOfDay(ms); }
// Timestamp of local midnight at the start of a day.
const dStart = (iso) => dDate(iso, 0);
// Timestamp of noon on a day. Used when formatting a date, so DST changes can't shift it to another day.
const dNoon = (iso) => dDate(iso, 720);
// Timestamp of midnight at the end of a day (start of the next one).
const dEnd = (iso) => dStart(addDays(iso, 1));
// The later of two ISO days (ISO strings compare correctly as text).
const maxDay = (a, b) => (a > b ? a : b);
// The earlier of two ISO days.
const minDay = (a, b) => (a < b ? a : b);
// First day of the week for the user's locale: 1 = Sunday, 2 = Monday. Used for "this week".
const FIRST_WEEKDAY = (() => {
  try {
    const l = new Intl.Locale(typeof navigator !== "undefined" ? navigator.language : "en-US");
    const w = l.getWeekInfo ? l.getWeekInfo() : l.weekInfo;
    if (w && w.firstDay) return (w.firstDay % 7) + 1;
  } catch (e) {}
  return 1;
})();

// ---------- Format ----------
let HOUR24 = false; // set from Settings (24-Hour Time)
const LOC = typeof navigator !== "undefined" ? navigator.language : "en-US";
const Format = {
  // Minutes after midnight -> "9:00 AM" or "09:00" (follows the 24-Hour Time setting).
  time(minutes) { return new Date(dDate(dayOf(Date.now()), minutes)).toLocaleTimeString(LOC, { hour: "numeric", minute: "2-digit", hourCycle: HOUR24 ? "h23" : "h12" }); },
  // Timestamp -> clock time, like time().
  timeMs(ms) { return new Date(ms).toLocaleTimeString(LOC, { hour: "numeric", minute: "2-digit", hourCycle: HOUR24 ? "h23" : "h12" }); },
  // ISO day -> short date like "Thu, Nov 26".
  day(iso) { return new Date(dNoon(iso)).toLocaleDateString(LOC, { weekday: "short", month: "short", day: "numeric" }); },
  // "Today", "Tomorrow", "Yesterday" or a short date.
  relative(iso, today) {
    const n = dIndex(iso) - dIndex(today);
    if (n === 0) return "Today";
    if (n === 1) return "Tomorrow";
    if (n === -1) return "Yesterday";
    if (n >= 2 && n <= 6) return new Date(dNoon(iso)).toLocaleDateString(LOC, { weekday: "long" });
    return Format.day(iso);
  },
  // Amount -> money text in the chosen currency, like "MAD 249.00".
  money(amount, code) {
    try { return new Intl.NumberFormat(LOC, { style: "currency", currency: code }).format(amount); }
    catch (e) { return code + " " + amount.toFixed(2); }
  },
  // Currency symbol only, like "$" or "MAD". Shown next to the Amount field.
  symbol(code) {
    try { return new Intl.NumberFormat(LOC, { style: "currency", currency: code }).formatToParts(0).find((p) => p.type === "currency").value; }
    catch (e) { return code; }
  },
  // How long you've been up, like "5h 20m".
  span(minutes) {
    const m = Math.max(0, minutes);
    if (m >= 1440) return Format.days(Math.floor(m / 1440));
    if (m < 60) return m + "m";
    const h = Math.floor(m / 60), r = m % 60;
    return r ? h + "h " + r + "m" : h + "h";
  },
  // "1 day" / "3 days".
  days(n) { return n + (n === 1 ? " day" : " days"); },
  // A length of time in words, like "15 min", "2 hr", "1 hr 30 min".
  duration(minutes) {
    const h = Math.floor(minutes / 60), r = minutes % 60;
    const parts = [];
    if (h) parts.push(h + " hr");
    if (r || !h) parts.push(r + " min");
    return parts.join(", ");
  },
  // Weekday numbers (1 = Sun) -> "Mon, Wed, Fri" in the user's language.
  weekdays(days) {
    const set = new Set(days);
    if (set.size === 5 && [2, 3, 4, 5, 6].every((d) => set.has(d))) return "weekdays";
    if (set.size === 2 && set.has(1) && set.has(7)) return "weekends";
    const sym = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
    return [...days].sort((a, b) => mod(a - FIRST_WEEKDAY, 7) - mod(b - FIRST_WEEKDAY, 7)).filter((d) => d >= 1 && d <= 7).map((d) => sym[d - 1]).join(", ");
  },
  // "first Sunday", "last Friday" (for monthly and yearly items).
  nth(x) {
    const ord = { 1: "first", 2: "second", 3: "third", 4: "fourth", 5: "fifth", "-1": "last" }[x.n];
    return ord + " " + new Date(2001, 0, 7 + x.wd - 1, 12).toLocaleDateString(LOC, { weekday: "long" });
  },
  // "Every day", "Every 2 weeks", ...
  every(n, unit) {
    const names = { hour: "hour", day: "day", week: "week", month: "month", year: "year" };
    return n === 1 ? "Every " + names[unit] : "Every " + n + " " + names[unit] + "s";
  },
  // "Twice a week", "3 times a month", ... for "any day" items.
  goal(count, period) {
    const t = count === 1 ? "Once" : count === 2 ? "Twice" : count + " times";
    return t + " a " + period;
  },
  // "1 of 3 this week".
  goalProgress(done, total, period) {
    return done + " of " + total + (period === "day" ? " today" : period === "week" ? " this week" : " this month");
  },
  // Joins words like a sentence: "a, b and c" (uses the locale's own list format).
  list(arr) {
    try { return new Intl.ListFormat(LOC, { type: "conjunction" }).format(arr); } catch (e) { return arr.join(", "); }
  }
};

// ---------- Schedule ----------
function newSchedule(today) {
  return { kind: "repeating", every: 1, unit: "day", start: today, times: [], weekdays: [], afterWaking: null,
    nextDue: null, nextDueTime: null, fromDone: false, goalCount: 3, goalPeriod: "week", monthDays: [], months: [], nth: null };
}
const S = {
  // Repeats every few hours.
  isHourly: (s) => s.kind === "repeating" && s.unit === "hour",
  // Can be timed from when you wake up (hourly items and daily-every-day items only).
  supportsWake: (s) => s.kind === "repeating" && (s.unit === "hour" || (s.unit === "day" && s.every === 1)),
  // Is actually timed from waking up ("After I Wake Up" is on).
  usesWake: (s) => S.supportsWake(s) && s.afterWaking != null,
  // Weekdays a weekly item happens on; if none were picked, the start day's weekday.
  effectiveWeekdays: (s) => (s.weekdays.length ? s.weekdays : [weekday(s.start)]),
  // Happens every single day.
  isEveryDay(s) {
    if (s.kind !== "repeating" || s.every !== 1) return false;
    return s.unit === "day" || (s.unit === "week" && S.effectiveWeekdays(s).length === 7);
  },
  // If missed, stays on Today as overdue (true) or just disappears at the end of the day (false).
  carriesOver(s) {
    if (s.kind === "once" || s.kind === "afterDone") return true;
    if (s.kind === "goal") return false;
    if (s.unit === "hour") return false;
    if (s.unit === "day") return s.every > 1;
    return true;
  },
  // Cleans up a schedule: fills defaults, clamps numbers, sorts times, drops fields that don't apply to its kind. Run before saving.
  normalized(src) {
    const s = JSON.parse(JSON.stringify(src));
    s.every = Math.min(Math.max(Math.round(+s.every || 1), 1), 999);
    s.times = [...new Set((s.times || []).filter((t) => t >= 0 && t < 1440))].sort((a, b) => a - b);
    s.weekdays = [...new Set((s.weekdays || []).filter((d) => d >= 1 && d <= 7))].sort((a, b) => a - b);
    s.goalCount = Math.min(Math.max(Math.round(+s.goalCount || 1), 1), 99);
    // Monthly: chosen days (1-31) or "On the first Sunday" (nth); yearly: chosen months (1-12).
    s.monthDays = [...new Set((s.monthDays || []).filter((d) => d >= 1 && d <= 31))].sort((a, b) => a - b);
    s.months = [...new Set((s.months || []).filter((m) => m >= 1 && m <= 12))].sort((a, b) => a - b);
    s.nth = s.nth && [1, 2, 3, 4, 5, -1].includes(s.nth.n) && s.nth.wd >= 1 && s.nth.wd <= 7 ? { n: s.nth.n, wd: s.nth.wd } : null;
    if (s.nextDueTime != null && !(s.nextDueTime >= 0 && s.nextDueTime < 1440)) s.nextDueTime = null;
    switch (s.kind) {
      case "repeating":
        if (s.unit === "hour") { s.every = Math.min(s.every, 12); s.times = s.times.slice(0, 1); }
        if (s.unit === "week") { if (!s.weekdays.length) s.weekdays = [weekday(s.start)]; } else s.weekdays = [];
        if (s.unit !== "month") s.monthDays = [];
        if (s.unit !== "year") s.months = [];
        if (s.unit !== "month" && s.unit !== "year") s.nth = null;
        if (s.nth) s.monthDays = [];
        s.nextDue = null; s.nextDueTime = null;
        break;
      case "afterDone":
        s.times = s.times.slice(0, 1); s.weekdays = [];
        if (s.nextDue == null) s.nextDue = s.start;
        if (s.unit !== "hour" && !s.times.length) s.nextDueTime = null;
        break;
      default:
        s.times = s.times.slice(0, 1); s.weekdays = []; s.nextDue = null; s.nextDueTime = null;
    }
    if (s.kind !== "repeating") { s.monthDays = []; s.months = []; s.nth = null; }
    if (!S.isHourly(s)) s.fromDone = false;
    if (s.afterWaking != null) s.afterWaking = Math.min(Math.max(s.afterWaking, 0), 18 * 60);
    if (!S.supportsWake(s)) s.afterWaking = null;
    if (s.afterWaking != null && s.unit !== "hour") s.times = [];
    return s;
  },
  // True if the item is due on day d.
  occurs(s, d) {
    switch (s.kind) {
      case "goal": return false;
      case "once": return d === s.start;
      case "afterDone": return d === (s.nextDue || s.start);
    }
    if (d < s.start) return false;
    const n = Math.max(1, s.every);
    switch (s.unit) {
      case "hour": return true;
      case "day": return (dIndex(d) - dIndex(s.start)) % n === 0;
      case "week": {
        const weeks = Math.trunc((dIndex(monday(d)) - dIndex(monday(s.start))) / 7);
        return weeks % n === 0 && S.effectiveWeekdays(s).includes(weekday(d));
      }
      default: return S.monthHits(s, monthIndex(d)).includes(d);
    }
  },
  // The "n"th weekday wd (1 = Sun) of month mi (n = -1: the last one), or null if that month has none.
  nthWeekday(mi, n, wd) {
    const y = Math.floor(mi / 12), m = mi - y * 12 + 1, len = daysIn(y, m);
    let day;
    if (n > 0) day = 1 + mod(wd - weekday(mkDay(y, m, 1)), 7) + 7 * (n - 1);
    else day = len - mod(weekday(mkDay(y, m, len)) - wd, 7);
    return day >= 1 && day <= len ? mkDay(y, m, day) : null;
  },
  // Monthly and yearly items: the days due in month mi (sorted), counting "every n months/years" and the start date.
  monthHits(s, mi) {
    const n = Math.max(1, s.every), start = monthIndex(s.start), startDay = dParts(s.start)[2];
    if (mi < start) return [];
    let out;
    if (s.unit === "month") {
      if ((mi - start) % n !== 0) return [];
      if (s.nth) out = [S.nthWeekday(mi, s.nth.n, s.nth.wd)];
      else if (s.monthDays && s.monthDays.length) { const y = Math.floor(mi / 12), m = mi - y * 12 + 1; out = s.monthDays.filter((d) => d <= daysIn(y, m)).map((d) => mkDay(y, m, d)); }
      else out = [inMonth(mi, startDay)];
    } else {
      const y = Math.floor(mi / 12), m = mi - y * 12 + 1, sy = Math.floor(start / 12);
      if ((y - sy) % n !== 0) return [];
      const months = s.months && s.months.length ? s.months : [dParts(s.start)[1]];
      if (!months.includes(m)) return [];
      out = [s.nth ? S.nthWeekday(mi, s.nth.n, s.nth.wd) : inMonth(mi, startDay)];
    }
    return out.filter((d) => d && d >= s.start);
  },
  // The first day on or after d that the item is due, or null if never again.
  nextOccurrence(s, d) {
    switch (s.kind) {
      case "goal": return null;
      case "once": return s.start >= d ? s.start : null;
      case "afterDone": { const due = s.nextDue || s.start; return due >= d ? due : null; }
    }
    const from = maxDay(d, s.start);
    const n = Math.max(1, s.every);
    switch (s.unit) {
      case "hour": return from;
      case "day": { const k = Math.trunc((dIndex(from) - dIndex(s.start) + n - 1) / n); return addDays(s.start, k * n); }
      case "week":
        for (let o = 0; o < 7 * n + 7; o++) { const c = addDays(from, o); if (S.occurs(s, c)) return c; }
        return null;
      default: {
        // Walks month by month (at most 400 years ahead).
        for (let mi = monthIndex(from), i = 0; i < 4800; i++, mi++) { const hit = S.monthHits(s, mi).find((c) => c >= from); if (hit) return hit; }
        return null;
      }
    }
  },
  // The last day on or before d that the item was due, or null.
  previousOccurrence(s, d) {
    switch (s.kind) {
      case "goal": return null;
      case "once": return s.start <= d ? s.start : null;
      case "afterDone": { const due = s.nextDue || s.start; return due <= d ? due : null; }
    }
    if (d < s.start) return null;
    const n = Math.max(1, s.every);
    switch (s.unit) {
      case "hour": return d;
      case "day": { const k = Math.trunc((dIndex(d) - dIndex(s.start)) / n); return addDays(s.start, k * n); }
      case "week":
        for (let o = 0; o < 7 * n + 7; o++) {
          const c = addDays(d, -o);
          if (c < s.start) return null;
          if (S.occurs(s, c)) return c;
        }
        return null;
      default: {
        for (let mi = monthIndex(d), i = 0; i < 4800 && mi >= monthIndex(s.start); i++, mi--) { const hit = S.monthHits(s, mi).filter((c) => c <= d).pop(); if (hit) return hit; }
        return null;
      }
    }
  },
  // The times an item is due on a day. Each slot = { key, minute }; key tells several times on one day apart.
  slots(s, day, wake, end) {
    switch (s.kind) {
      case "goal": return [];
      case "once": return [{ key: null, minute: s.times.length ? s.times[0] : null }];
      case "afterDone": return [{ key: null, minute: s.nextDueTime != null ? s.nextDueTime : (s.times.length ? s.times[0] : null) }];
    }
    if (s.unit === "hour") {
      let first;
      if (s.afterWaking != null) { if (wake == null) return []; first = wake + s.afterWaking; }
      else first = s.times.length ? s.times[0] : 8 * 60;
      const limit = end != null ? end : (wake != null ? wake + 1440 : 1440);
      return S.hourlySlots(first, s.every, limit);
    }
    if (s.afterWaking != null) return [{ key: null, minute: wake != null ? wake + s.afterWaking : null }];
    if (!s.times.length) return [{ key: null, minute: null }];
    return s.times.map((t) => ({ key: t, minute: t }));
  },
  // Every `every` hours from minute `first` until `end`.
  hourlySlots(first, every, end) {
    const step = Math.max(1, every) * 60, out = [];
    let minute = first, k = 0;
    while (minute < end && k < 48) { out.push({ key: k, minute }); minute += step; k++; }
    return out;
  },
  // For "any day" items: [first day, last day] of the day/week/month that d is in.
  goalRange(s, d) {
    if (s.goalPeriod === "day") return [d, d];
    if (s.goalPeriod === "week") { const first = addDays(d, -mod(weekday(d) - FIRST_WEEKDAY, 7)); return [first, addDays(first, 6)]; }
    return [firstOfMonth(d), lastOfMonth(d)];
  },
  // For "after completion" items: moves the next due date forward from when it was done.
  advanceAfterDone(s, date, day) {
    const n = Math.max(1, s.every);
    const from = day || dayOf(date);
    switch (s.unit) {
      case "hour": { const next = date + n * 3600e3; s.nextDue = dayOf(next); s.nextDueTime = minOfDay(next); return; }
      case "day": s.nextDue = addDays(from, n); break;
      case "week": s.nextDue = addDays(from, 7 * n); break;
      case "month": s.nextDue = addMonths(from, n); break;
      case "year": s.nextDue = addMonths(from, 12 * n); break;
    }
    if (!s.times.length) s.nextDueTime = null;
    else if (dayOf(date) === from) s.nextDueTime = minOfDay(date);
  },
  // For "any day" items: how many should be done by day d to stay on track.
  goalPace(s, d) {
    const [lo, hi] = S.goalRange(s, d);
    const length = dIndex(hi) - dIndex(lo) + 1, elapsed = dIndex(d) - dIndex(lo) + 1;
    if (length <= 0) return s.goalCount;
    // Whole check-offs only: once a week is behind on the last day, 3 a week from day 3.
    return Math.min(s.goalCount, Math.max(0, Math.floor(s.goalCount * elapsed / length)));
  },
  // The full schedule in words, like "Every day at 9:00 AM". Shown under each task.
  summary(s) {
    switch (s.kind) {
      case "once": { let t = "Once · " + Format.day(s.start); if (s.times.length) t += " · " + Format.time(s.times[0]); return t; }
      case "goal": return Format.goal(s.goalCount, s.goalPeriod) + " · " + (s.goalPeriod === "day" ? "any time" : "any day");
      case "afterDone": { let t = Format.every(s.every, s.unit); if (s.unit !== "hour" && s.times.length) t += " · " + Format.time(s.times[0]); return t; }
    }
    const parts = [];
    const wd = S.effectiveWeekdays(s), set = new Set(wd);
    if (s.unit === "week") {
      if (s.every === 1 && wd.length === 7) parts.push("Every day");
      else if (s.every === 1 && set.size === 5 && [2, 3, 4, 5, 6].every((d) => set.has(d))) parts.push("Every weekday");
      else if (s.every === 1 && set.size === 2 && set.has(1) && set.has(7)) parts.push("Every weekend");
      else if (s.every === 1) parts.push("Every " + Format.weekdays(wd));
      else { parts.push(Format.every(s.every, s.unit)); parts.push(Format.weekdays(wd)); }
    } else if (s.unit === "month") {
      parts.push(Format.every(s.every, s.unit));
      if (s.nth) parts.push(Format.nth(s.nth));
      else { const days = s.monthDays && s.monthDays.length ? s.monthDays : [dParts(s.start)[2]]; parts.push((days.length > 1 ? "days " : "day ") + Format.list(days.map(String))); }
    } else if (s.unit === "year") {
      parts.push(Format.every(s.every, s.unit));
      const months = s.months && s.months.length ? s.months : [dParts(s.start)[1]], day = dParts(s.start)[2];
      const name = (m, opts) => new Date(2001, m - 1, s.nth ? 1 : Math.min(day, daysIn(2001, m)), 12).toLocaleDateString(LOC, opts);
      if (s.nth) parts.push(Format.nth(s.nth) + " of " + Format.list(months.map((m) => name(m, { month: "short" }))));
      else parts.push(Format.list(months.map((m) => name(m, { month: "short", day: "numeric" }))));
    }
    else parts.push(Format.every(s.every, s.unit));
    if (s.unit === "hour") {
      if (s.afterWaking != null) parts.push(s.afterWaking === 0 ? "after waking" : Format.duration(s.afterWaking) + " after waking");
      else parts.push("from " + Format.time(s.times.length ? s.times[0] : 8 * 60));
    } else if (s.afterWaking != null) parts.push(s.afterWaking === 0 ? "when you wake up" : Format.duration(s.afterWaking) + " after waking");
    else if (s.times.length) parts.push(Format.list(s.times.map(Format.time)));
    return parts.join(" · ");
  },
  // A shorter schedule in words, used after the due date on Today.
  shortSummary(s) {
    switch (s.kind) {
      case "once": return null;
      case "goal": return Format.goal(s.goalCount, s.goalPeriod);
      case "afterDone": return Format.every(s.every, s.unit);
    }
    if (s.fromDone) return Format.every(s.every, s.unit);
    if (s.unit === "week" && s.every === 1) {
      const wd = S.effectiveWeekdays(s), set = new Set(wd);
      if (set.size === 7) return "Every day";
      if (set.size === 5 && [2, 3, 4, 5, 6].every((d) => set.has(d))) return "Every weekday";
      if (set.size === 2 && set.has(1) && set.has(7)) return "Every weekend";
      return "Every " + Format.weekdays(wd);
    }
    return Format.every(s.every, s.unit);
  }
};

// ---------- Item ----------
const uid = () => (typeof crypto !== "undefined" && crypto.randomUUID ? crypto.randomUUID().toUpperCase() : Date.now().toString(36) + Math.random().toString(36).slice(2));
// A blank task. Every saved item has exactly these fields (see README for what each means).
function newItem(now) {
  const today = dayOf(now);
  return { id: uid(), title: "", notes: "", schedule: newSchedule(today), cost: null, autopay: false, reminder: "onTime",
    paused: false, pauses: [], trackFrom: today, log: [], snoozes: [], createdAt: now, modifiedAt: now, deletedAt: null };
}
// True if two slot keys are the same (null and undefined count as the same).
const sameSlot = (a, b) => (a == null ? null : a) === (b == null ? null : b);
const I = {
  // Has an amount, which makes it a bill instead of a task.
  hasCost: (i) => (i.cost || 0) > 0,
  // A bill that pays itself on its due date ("Payment: Automatic").
  isAutopay: (i) => I.hasCost(i) && i.autopay && (i.schedule.kind === "repeating" || i.schedule.kind === "once"),
  // A bill paid any day in a period ("Every month, any day").
  isAnyDayBill: (i) => I.hasCost(i) && i.schedule.kind === "goal",
  // How the money leaves: the method's names (menu, details line) and whether it pays itself.
  PAYMENTS: {
    autoRenew: { name: "Auto-Renew", short: "Auto-renew", auto: true },
    directDebit: { name: "Direct Debit", short: "Direct debit", auto: true },
    standingOrder: { name: "Standing Order", short: "Standing order", auto: true },
    cash: { name: "Cash", short: "Cash", auto: false },
    card: { name: "Card", short: "Card", auto: false },
    transfer: { name: "Bank Transfer", short: "Bank transfer", auto: false },
    mobile: { name: "Mobile Payment", short: "Mobile payment", auto: false }
  },
  // The bill's payment method, or a sensible one for bills saved before methods existed.
  payment: (i) => (I.PAYMENTS[i.payment] ? i.payment : i.autopay ? "autoRenew" : "cash"),
  // Paid by hand but counted as paid on its date without a check-off (everyday spending like coffee).
  isCounted: (i) => I.isAutopay(i) && !I.PAYMENTS[I.payment(i)].auto,
  // A one-time item that's been done or skipped.
  isFinished: (i) => i.schedule.kind === "once" && i.log.some((e) => e.day === i.schedule.start),
  // Not deleted, not paused, not finished: shows up on Today.
  isActive: (i) => i.deletedAt == null && !i.paused && !I.isFinished(i),
  // The name to show ("Untitled" if empty).
  title: (i) => (i.title || "").trim() || "Untitled",
  // The log entry (done or skipped) for one occurrence, or null.
  entry(i, day, slot) { for (let k = i.log.length - 1; k >= 0; k--) { const e = i.log[k]; if (e.day === day && sameSlot(e.slot, slot)) return e; } return null; },
  // The "Later" for one occurrence, or null.
  snooze: (i, day, slot) => i.snoozes.find((z) => z.day === day && sameSlot(z.slot, slot)) || null,
  // How many times it was done between two days (inclusive).
  doneCount: (i, lo, hi) => i.log.filter((e) => e.kind === "done" && e.day >= lo && e.day <= hi).length,
  // The most recent "done" log entry, or null.
  lastDone(i) { let b = null; for (const e of i.log) if (e.kind === "done" && (!b || e.at > b.at)) b = e; return b; },
  // Pauses or resumes, remembering when, so paused days aren't counted as missed.
  setPaused(i, pause, day) {
    if (pause === i.paused) return;
    i.paused = pause;
    if (pause) {
      i.pauses.push({ start: day, end: null });
      if (i.pauses.length > 24) i.pauses.splice(0, i.pauses.length - 24);
    } else {
      i.trackFrom = day;
      let idx = -1;
      for (let k = i.pauses.length - 1; k >= 0; k--) if (i.pauses[k].end == null) { idx = k; break; }
      if (idx >= 0) i.pauses[idx].end = maxDay(day, i.pauses[idx].start);
      else i.pauses.push({ start: "0001-01-01", end: day });
    }
  },
  // True if the item was paused on day d.
  wasPaused(i, d) {
    for (const span of i.pauses) {
      let end = span.end;
      if (end == null && !i.paused) end = maxDay(i.trackFrom, span.start);
      if (d >= span.start && (end == null || d < end)) return true;
    }
    if (i.paused && !i.pauses.some((p) => p.end == null)) return true;
    return false;
  },
  // Keeps saved data small: log entries from the last 400 days (150 at most) and Laters from the last day.
  trimHistory(i, now) {
    const oldest = now - 400 * 864e5;
    i.log = i.log.filter((e) => e.at >= oldest);
    if (i.log.length > 150) { i.log.sort((a, b) => a.at - b.at); i.log.splice(0, i.log.length - 150); }
    i.snoozes = i.snoozes.filter((z) => z.until >= now - 864e5);
  },
  // Removes log entries and Laters dated in the future (e.g. after the clock was set back).
  forgetFuture(i, now) {
    const limit = now + 60e3;
    let changed = false;
    const future = i.log.filter((e) => e.at > limit);
    if (future.length) {
      if (i.schedule.kind === "afterDone") {
        const first = future.reduce((a, b) => (b.at < a.at ? b : a));
        if (first.previousDue) { i.schedule.nextDue = first.previousDue; i.schedule.nextDueTime = first.previousDueTime; }
      }
      i.log = i.log.filter((e) => e.at <= limit);
      changed = true;
    }
    const n = i.snoozes.length;
    i.snoozes = i.snoozes.filter((z) => z.until <= now + 400 * 864e5);
    if (n !== i.snoozes.length) changed = true;
    const today = dayOf(now);
    if (i.modifiedAt > limit && i.trackFrom > today) { i.trackFrom = today; changed = true; }
    if (i.createdAt > limit) { i.createdAt = now; changed = true; }
    return changed;
  }
};
// Accepts amounts typed with "." or "," (and Arabic digits), like the app.
function parseAmount(input) {
  let text = "";
  for (const ch of String(input)) {
    const c = ch.codePointAt(0);
    if (c >= 0x30 && c <= 0x39) text += ch;
    else if (c >= 0x660 && c <= 0x669) text += String(c - 0x660);
    else if (c >= 0x6f0 && c <= 0x6f9) text += String(c - 0x6f0);
    else if (ch === "." || ch === "," || ch === "٫") text += ".";
  }
  const last = text.lastIndexOf(".");
  if (last >= 0) {
    const whole = text.slice(0, last).replace(/\./g, "");
    let fraction = text.slice(last + 1);
    const count = (text.match(/\./g) || []).length;
    const dec = (1.1).toLocaleString(LOC).charAt(1);
    const typed = [...String(input)].reverse().find((c) => c === "." || c === "," || c === "٫") || ".";
    if (count === 1 && fraction.length === 3 && typed !== dec && typed !== "٫") return +(whole + fraction);
    if (!fraction) fraction = "0";
    return +((whole || "0") + "." + fraction);
  }
  return text ? +text : null;
}

// ---------- DayClock ----------
const DEFAULT_DAY = 16 * 60, LONGEST_DAY = 24 * 60;
// A day you're living lasts until you set a new wake-up time, or at most MAX_DAY minutes after waking.
const MAX_DAY = 36 * 60;
// The "day you're living": the day of your latest wake-up time. It never ends on its own after midnight;
// it changes only when a new wake-up time is set (or after MAX_DAY), so nothing resets by surprise.
function makeClock(now, rules) {
  const today = dayOf(now), nowMinute = minOfDay(now), usual = rules.usualDay;
  let best = null, lastEnd = 0;
  for (let b = 0; b <= 2; b++) {
    const d = addDays(today, -b), w = rules.wakes[d];
    if (w == null) continue;
    const began = dDate(d, w);
    if (began > now + 600e3) continue;
    if (now - began >= MAX_DAY * 60e3) { lastEnd = Math.max(lastEnd, began + MAX_DAY * 60e3); continue; }
    if (!best || began > best.began) best = { d, w, b, began };
  }
  if (best) return { day: best.d, minute: nowMinute + 1440 * best.b, wake: best.w, upSince: null, began: best.began, now, usualDay: usual };
  return { day: today, minute: nowMinute, wake: null, upSince: null, began: Math.min(Math.max(dStart(today), lastEnd), now), now, usualDay: usual };
}
// A plain clock that follows the calendar, for bills (bills don't care when you sleep).
function calendarClock(now) { const today = dayOf(now); return { day: today, minute: minOfDay(now), wake: null, upSince: null, began: dStart(today), now, usualDay: DEFAULT_DAY }; }
const C = {
  // A wake-up time is set for today.
  isUp: (c) => c.wake != null,
  // It's after midnight but still "today" because you haven't slept.
  isPastMidnight: (c) => c.minute >= 1440,
  // Timestamp of today's wake-up, or null.
  wakeDate: (c) => (c.wake != null ? dDate(c.day, c.wake) : null),
  // When you got up (stayed up overnight counts from the earlier time).
  upDate: (c) => (c.upSince != null ? c.upSince : C.wakeDate(c)),
  // Minutes since you got up.
  minutesUp(c) { const s = C.upDate(c); return s == null ? 0 : Math.max(0, Math.floor((c.now - s) / 60e3)); },
  // Last minute of the day you're living (a day never lasts more than LONGEST_DAY).
  end: (c) => (c.wake != null ? c.wake + LONGEST_DAY : 1440),
  // After this minute no more reminders today (around when your day usually ends).
  reminderEnd(c) { if (c.wake == null) return 1440; return Math.min(Math.max(c.wake + c.usualDay, c.minute + 120), c.wake + LONGEST_DAY); },
  // True if log entry e belongs to the day you're living.
  includes(c, e) { if (e.at > c.now + 60e3) return false; return e.at >= c.began || (e.day === c.day && e.at >= dStart(c.day) && c.began - e.at < 12 * 3600e3); }
};

// ---------- SleepCheck ----------
const Sleep = {
  quietGap: 3 * 3600e3, shortestDay: 10 * 3600e3, defaultWake: 8 * 60, shortestLearnedDay: 4 * 60, longestLearnedDay: 30 * 60, remembered: 9,
  // Empty sleep log. See SleepLog in the iPhone app's SleepCheck.swift.
  newLog: () => ({ spans: [], question: null, wakeMinutes: [], dayLengths: [], stillUpAt: null, upSince: null, used: false, dismissedAt: null, sleeps: [], awakeGaps: [], bias: 0, quietUntil: null }),
  // Records that you're using the app right now (best clue that you're awake). Returns true if it changed.
  note(log, now) {
    let changed = false;
    const before = log.spans.length;
    log.spans = log.spans.filter((s) => s.start <= now + 600e3);
    if (log.spans.length !== before) changed = true;
    const last = log.spans[log.spans.length - 1];
    if (last && now >= last.start && now - last.end < 15 * 60e3) {
      if (now - last.end >= 60e3) { last.end = now; changed = true; }
    } else {
      log.spans.push({ start: now, end: now });
      log.spans.sort((a, b) => a.start - b.start);
      changed = true;
    }
    const kept = log.spans.length;
    log.spans = log.spans.filter((s) => s.end >= now - 4 * 864e5);
    if (log.spans.length > 300) log.spans.splice(0, log.spans.length - 300);
    if (log.spans.length !== kept) changed = true;
    return changed;
  },
  // When you last used the app before now, or null.
  lastUse(log, now) {
    for (let k = log.spans.length - 1; k >= 0; k--) if (log.spans[k].start <= now) return Math.min(log.spans[k].end, now);
    return null;
  },
  // Remembers a wake-up time so Routine learns your usual one.
  learnWake(log, date) { log.wakeMinutes.push(minOfDay(date)); if (log.wakeMinutes.length > 9) log.wakeMinutes.splice(0, log.wakeMinutes.length - 9); },
  // Remembers how long a day lasted so Routine learns your usual day length.
  learnDay(log, minutes) {
    if (minutes < Sleep.shortestLearnedDay || minutes > Sleep.longestLearnedDay) return;
    log.dayLengths.push(minutes);
    if (log.dayLengths.length > 9) log.dayLengths.splice(0, log.dayLengths.length - 9);
  },
  // Your usual wake-up minute (median of recent answers), or the default.
  usualWake(log) { const m = Sleep.circularMedian(log.wakeMinutes); return m == null ? Sleep.defaultWake : m; },
  // Your usual day length in minutes.
  usualDay(log) {
    const l = [...log.dayLengths].sort((a, b) => a - b);
    if (!l.length) return DEFAULT_DAY;
    const middle = l[Math.floor(l.length / 2)];
    const v = l.length < 3 ? Math.trunc((middle + DEFAULT_DAY) / 2) : middle;
    return Math.min(Math.max(v, 480), 1440);
  },
  // Median of clock times that wraps around midnight (11 PM and 1 AM -> midnight).
  circularMedian(minutes) {
    const v = minutes.map((m) => mod(m, 1440)).sort((a, b) => a - b);
    if (!v.length) return null;
    let start = 0, biggest = -1;
    for (let i = 0; i < v.length; i++) {
      const next = i + 1 < v.length ? v[i + 1] : v[0] + 1440;
      if (next - v[i] > biggest) { biggest = next - v[i]; start = (i + 1) % v.length; }
    }
    const line = v.slice(start).concat(v.slice(0, start).map((x) => x + 1440));
    const n = line.length;
    const middle = n % 2 === 1 ? line[(n - 1) / 2] : Math.trunc((line[n / 2 - 1] + line[n / 2] + 1) / 2);
    return mod(middle, 1440);
  },
  // Stretches between from and to when the app wasn't used.
  gaps(log, from, to) {
    if (to <= from) return [];
    const out = [];
    let cursor = from;
    for (const s of log.spans) {
      if (s.end < from || s.start > to) continue;
      const st = Math.max(s.start, from);
      if (st - cursor >= Sleep.quietGap) out.push({ start: cursor, end: st });
      if (s.end > cursor) cursor = Math.min(s.end, to);
    }
    if (to - cursor >= Sleep.quietGap) out.push({ start: cursor, end: to });
    return out;
  },
  // True if a quiet stretch looks like a night (ends near your usual wake-up).
  isNightish(from, to, usualWake) {
    if (to <= from) return false;
    const first = addDays(dayOf(from), -1);
    for (let k = 0; k < 4; k++) {
      const midnight = dStart(addDays(first, k));
      const ns = midnight + (usualWake - 480) * 60e3, ne = midnight + (usualWake + 120) * 60e3;
      if (Math.min(to, ne) - Math.max(from, ns) >= 2 * 3600e3) return true;
    }
    return false;
  },
  // Earliest moment a sleep could have started.
  sleepFrom(log, up) { const earliest = up + Sleep.shortestDay; return log.stillUpAt != null && log.stillUpAt > earliest ? log.stillUpAt : earliest; },
  // True if you said "Not Yet" (still up) recently.
  isStillUp(log, up, now) {
    const from = Sleep.sleepFrom(log, up);
    if (from >= now) return true;
    const wake = Sleep.usualWake(log);
    return !Sleep.gaps(log, from, now).some((g) => Sleep.isNightish(g.start, g.end, wake));
  },
  // Decides whether to ask "Did you sleep?" (probability above a threshold).
  shouldAsk(log, lastUse, now, up, missed) { const p = Sleep.probability(log, lastUse, now, up, missed); return p != null && p >= 0.8; },
  // Scores the clues (quiet time, night overlap, time up, closeness to usual wake-up, missed reminders) into 0..1.
  probability(log, lastUse, now, up, missed) {
    const minute = minOfDay(now);
    if (minute >= 120 && minute < 240) return null;
    let quietFrom = lastUse;
    if (log.stillUpAt != null && log.stillUpAt > quietFrom) quietFrom = log.stillUpAt;
    const quiet = (now - quietFrom) / 60e3;
    if (quiet < 180) return null;
    const day = Sleep.usualDay(log), wake = Sleep.usualWake(log), spread = Sleep.wakeSpread(log);
    const sleep = Math.min(Math.max(1440 - day, 240), 720), minAwake = Math.min(Math.max(day - 240, 480), 720);
    if (up != null && (now - up) / 60e3 < minAwake) return null;
    const bed = Sleep.clockMinute(wake - sleep - spread), nightEnd = Sleep.clockMinute(wake - 240);
    if (Sleep.isBetween(minute, bed, nightEnd)) return null;
    let overlap = 0;
    const firstDay = dIndex(dayOf(quietFrom)) - 1;
    const lastDay = Math.max(firstDay, Math.min(dIndex(dayOf(now)) + 1, firstDay + 30));
    for (let idx = firstDay; idx <= lastDay; idx++) {
      const midnight = dStart(dFromIndex(idx));
      const ws = midnight + (wake - sleep - spread) * 60e3, we = midnight + (wake + spread) * 60e3;
      const f = Math.max(quietFrom, ws), t = Math.min(now, we);
      if (t > f) overlap += (t - f) / 60e3;
    }
    const night = Math.min(overlap / Math.min(sleep, 360), 1);
    const length = Math.min(quiet / sleep, 1.5);
    let awake = 1;
    if (up != null) awake = Math.min(Math.max((quietFrom - up) / 60e3 / day, 0), 2);
    const before = Sleep.clockMinute(wake - spread - minute + 720) - 720;
    const morning = before <= 0 ? 1 : Math.exp(-0.5 * (before / 90) * (before / 90));
    const ignored = Math.min(Math.max(missed, 0), 3);
    const z = -10 + 3 * night + 4 * length + 4 * awake + 3 * morning + 0.5 * ignored;
    return 1 / (1 + Math.exp(-z));
  },
  // How much your wake-up time varies, in minutes.
  wakeSpread(log) {
    const v = log.wakeMinutes;
    if (!v.length) return 75;
    const a = v.map((x) => (x / 1440) * 2 * Math.PI);
    const c = a.reduce((s, x) => s + Math.cos(x), 0) / a.length, s = a.reduce((t, x) => t + Math.sin(x), 0) / a.length;
    const r = Math.max(Math.sqrt(c * c + s * s), 1e-9);
    let spread = (Math.sqrt(Math.max(0, -2 * Math.log(r))) / (2 * Math.PI)) * 1440;
    if (v.length < 3) spread = Math.max(spread, 75);
    return Math.min(Math.max(spread, 20), 180);
  },
  // Wraps any minute count into 0..1439.
  clockMinute: (v) => v - 1440 * Math.floor(v / 1440),
  // True if clock minute t is between a and b, wrapping past midnight.
  isBetween: (t, a, b) => (a <= b ? t >= a && t < b : t >= a || t < b),
  // The minute when an unanswered day is considered over.
  cut(wakeMinute, stillUp, usualDay, fixedTimes = []) {
    let c = stillUp ? Math.max(60, Math.min(wakeMinute, 720)) : Math.max(60, Math.min(wakeMinute, 720, wakeMinute + usualDay + 240 - 1440));
    for (const t of fixedTimes) if (t >= 0 && t < c) c = t;
    return c;
  }
};

// ---------- Sleep estimator (learns your own pattern; no fixed night) ----------
// Decides when to ask "Did you sleep?". Works for any lifestyle: night shifts, split sleep, naps,
// 30-hour days, short sleepers, people who rarely open the app. It learns from your answers:
//   log.sleeps    [{ start, end }]  confirmed sleeps (start = last use before, end = your wake-up answer)
//   log.awakeGaps [minutes]         quiet stretches that were NOT sleep (you answered "Not Yet")
//   log.bias      number            calibration: goes down after "Not Yet", up after "Yes"
// Clues for a quiet stretch (no use of Routine on any device):
//   length compared with your usual sleep, how much of it falls in YOUR usual sleep hours
//   (learned; a generic night only until you've answered a few times), whether right now is still
//   inside your usual sleep hours (a short look at the phone mid-sleep), how long you'd been up
//   before it, whether it's longer than your usual quiet-but-awake stretches, closeness to your usual
//   wake-up, and reminders you didn't react to.
const SleepAI = {
  BIN: 15, BINS: 96, minQuiet: 120, briefLook: 3,
  // Weights fitted on 12 simulated lifestyles (tests/sleep/fit.cjs). z = sum(w * clue) + bias.
  // Clues, in order: length / usual sleep, log2(length / 3h), usual-sleep-hours coverage, still in sleep hours,
  // time up before, beyond usual awake quiet, morning, missed reminders, 16h+, brief looks.
  W: [-5.269, 0.164, 1.405, 4.346, -2.092, 2.417, 0.566, 0.922, 0, -0.142, -0.733],
  threshold: 0.35, lookBack: 0.97,
  // Your learned pattern.
  profile(log) {
    const sleeps = (log.sleeps || []).filter((s) => s.end > s.start).slice(-30);
    const n = sleeps.length;
    const durs = sleeps.map((s) => (s.end - s.start) / 60e3).sort((a, b) => a - b);
    const med = n ? durs[Math.floor(n / 2)] : 450;
    const L = Math.min(Math.max(n < 3 ? (med * n + 450 * (3 - n)) / 3 : med, 150), 960);
    // Sleep-hours map: 96 quarter hours, 0..1. Starts as a generic night that fades as you answer.
    const D = new Array(SleepAI.BINS).fill(0);
    const prior = 3 / (n + 3);
    for (let b = 0; b < SleepAI.BINS; b++) { const m = b * SleepAI.BIN; if (m >= 23 * 60 || m < 7 * 60) D[b] += prior; }
    let weight = 1, total = 0;
    for (let k = n - 1; k >= 0; k--) {
      const s = sleeps[k];
      const add = (1 - prior) * weight;
      SleepAI.forBins(s.start, s.end, (b) => { D[b] += add; });
      total += weight;
      weight *= 0.9;
    }
    // Normalize so a quarter hour you're nearly always asleep in is 1.
    const top = Math.max(...D, 1e-9);
    for (let b = 0; b < SleepAI.BINS; b++) D[b] = Math.min(D[b] / top, 1);
    const gaps = (log.awakeGaps || []).slice(-30).sort((a, b) => a - b);
    const awakeLong = gaps.length >= 2 ? gaps[Math.min(gaps.length - 1, Math.floor(gaps.length * 0.9))] : null;
    const day = Sleep.usualDay(log);
    return { n, L, D, awakeLong, day, wake: Sleep.usualWake(log), spread: Sleep.wakeSpread(log), wakes: (log.wakeMinutes || []).length, bias: log.bias || 0 };
  },
  // Calls fn(bin) for every quarter hour between two moments (at most 2 days).
  forBins(from, to, fn) {
    const step = SleepAI.BIN * 60e3;
    let t = from, guard = 0;
    while (t < to && guard++ < 200) { fn(Math.floor(minOfDay(t) / SleepAI.BIN) % SleepAI.BINS); t += step; }
  },
  at(prof, t) { return prof.D[Math.floor(minOfDay(t) / SleepAI.BIN) % SleepAI.BINS]; },
  // The clues for the quiet stretch from..to. up = when your day started (or null).
  clues(prof, from, to, up, missed, looks = 0) {
    const d = (to - from) / 60e3;
    let sum = 0;
    SleepAI.forBins(from, Math.min(to, from + 2 * 864e5), (b) => { sum += prof.D[b]; });
    const cover = Math.min(sum / (prof.L / SleepAI.BIN), 1);
    const still = (SleepAI.at(prof, to + 30 * 60e3) + SleepAI.at(prof, to + 90 * 60e3)) / 2;
    const awake = up != null ? Math.min(Math.max((from - up) / 60e3 / prof.day, 0), 2) : 1;
    const beyond = prof.awakeLong != null ? Math.min(Math.max((d - prof.awakeLong) / 120, -2), 2) : 0;
    let morning = 0.5;
    if (prof.wakes >= 2) { const off = mod(minOfDay(to) - prof.wake + 720, 1440) - 720; morning = off >= 0 && off < 240 ? 1 : Math.exp(-0.5 * (off / Math.max(prof.spread, 45)) ** 2); }
    return [Math.min(d / prof.L, 2), Math.log2(d / 180), cover, still, awake, beyond, morning, Math.min(Math.max(missed || 0, 0), 3), d >= 16 * 60 ? 1 : 0, Math.min(looks, 3)];
  },
  // 0..1: how sure it is that you slept during from..to and are up now.
  chance(prof, from, to, up, missed, looks = 0) {
    if (to - from < SleepAI.minQuiet * 60e3) return 0;
    const x = SleepAI.clues(prof, from, to, up, missed, looks), w = SleepAI.W;
    let z = w[0] + prof.bias;
    for (let k = 0; k < x.length; k++) z += w[k + 1] * x[k];
    return 1 / (1 + Math.exp(-z));
  },
  // Looks for a sleep you haven't told Routine about, using when you used Routine (log.spans, plus
  // `extra` moments of use from other devices, like check-offs). up = when your day started.
  // Returns { from, to } for the quiet stretch to ask about, or null.
  find(log, now, up, missed, extra) {
    const prof = SleepAI.profile(log), anchor = Math.max(up || 0, log.stillUpAt || 0), M = 60e3;
    const raw = log.spans.filter((s) => s.start < now).map((s) => ({ start: s.start, end: Math.min(s.end, now) }));
    for (const t of extra || []) if (t < now && t > anchor) raw.push({ start: t, end: t });
    raw.sort((a, b) => a.start - b.start);
    const uses = [];
    for (const u of raw) { const l = uses[uses.length - 1]; if (l && u.start <= l.end) l.end = Math.max(l.end, u.end); else uses.push({ ...u }); }
    if (!uses.length) return null;
    // Brief looks at the phone (a few minutes, between long quiet stretches) count as part of the same sleep.
    let from = uses[uses.length - 1].end, looks = 0;
    for (let k = uses.length - 1; k > 0; k--) {
      const u = uses[k], next = k + 1 < uses.length ? uses[k + 1].start : now;
      if (u.end - u.start > SleepAI.briefLook * M || u.start - uses[k - 1].end < 90 * M || next - u.end < 90 * M || uses[k - 1].end <= anchor || now - uses[k - 1].end > 20 * 3600e3) break;
      from = uses[k - 1].end; looks++;
    }
    if (log.stillUpAt != null && log.stillUpAt > from) from = log.stillUpAt;
    // Look back first: an earlier quiet stretch since your day started that is almost surely a sleep you
    // never told Routine about (it explains a very long "Up for"). The oldest one wins.
    for (let k = 1; k < uses.length; k++) {
      const gs = Math.max(uses[k - 1].end, anchor), ge = uses[k].start;
      if (uses[k].start <= anchor || ge > from) continue;
      if (ge - gs >= SleepAI.minQuiet * M && SleepAI.chance(prof, gs, ge, up, 0, 0) >= SleepAI.lookBack) return { from: gs, to: ge };
    }
    if (SleepAI.chance(prof, from, now, up, missed, looks) >= SleepAI.threshold) return { from, to: now };
    return null;
  },
  // Best guess of when you woke up during from..to (the wake-up panel starts there).
  guessWake(prof, from, to) {
    const longest = from + (prof.L + 120) * 60e3;
    if (to <= longest) return to;
    // You stayed away after waking: the end of your usual sleep hours after a plausible sleep, else your usual length.
    const step = SleepAI.BIN * 60e3;
    for (let t = from + 0.6 * prof.L * 60e3; t < to; t += step) if (SleepAI.at(prof, t) < 0.35 && SleepAI.at(prof, t - step) >= 0.35) return t;
    return Math.min(to, from + prof.L * 60e3);
  },
  // A confirmed sleep. byHand = you set the wake-up time yourself (Routine missed it): ask a bit sooner next time.
  learnSleep(log, start, end, byHand) {
    if (!(end - start >= 60 * 60e3) || end - start > 30 * 3600e3) return;
    log.sleeps = (log.sleeps || []).concat([{ start, end }]).slice(-30);
    log.bias = Math.min((log.bias || 0) + (byHand ? 0.3 : 0.1), 1.5);
  },
  // "Not Yet". Inside your usual sleep hours it's a look at the phone mid-sleep, so nothing is learned.
  // Returns true for a look mid-sleep: then the quiet stretch keeps counting and Routine waits 90 minutes.
  notYet(log, prof, from, to, now) {
    if (SleepAI.at(prof, now) >= 0.5 && SleepAI.at(prof, now + 60 * 60e3) >= 0.5) { log.quietUntil = now + 90 * 60e3; return true; }
    SleepAI.learnAwake(log, (to - from) / 60e3);
    return false;
  },
  learnAwake(log, minutes) {
    if (!(minutes > 0)) return;
    log.awakeGaps = (log.awakeGaps || []).concat([Math.round(minutes)]).slice(-30);
    log.bias = Math.max((log.bias || 0) - 0.4, -2);
  }
};

// ---------- Planner ----------
// NOW_MINUTES: a timed task says "Now" only during its own minute, then "1m late", "1h 5m late"...
const LATE_AFTER = 60, NOW_MINUTES = 1;
// Unique ID for one occurrence: item ID | day | slot.
const occurrenceID = (id, day, slot) => id + "|" + day + "|" + (slot == null ? "-" : String(slot));
// One row on Today or Bills (an "agenda entry") with all fields defaulted.
function entry(o) {
  return Object.assign({ id: "", itemID: "", title: "", day: "", slot: null, minute: null, state: "due", overdue: false, progress: 0, total: 0,
    snoozedUntil: null, logID: null, at: null, hourly: false, goal: false, deadline: null, deadlineKind: "time", windowStart: null,
    sortDate: Infinity, doneToday: false, isBill: false, goalPeriod: null, afterWake: false, today: null }, o);
}
// Done or skipped.
const isFinishedEntry = (e) => e.state === "done" || e.state === "skipped";
const P = {
  // "upcoming", "due" or "late" (late = LATE_AFTER minutes past due).
  timeState(due, now) { if (due > now) return "upcoming"; return now - due >= LATE_AFTER * 60e3 ? "late" : "due"; },
  // Everything for Today: { tasks: [...rows to do], done: [...rows done today] }, sorted like the app.
  agenda(items, clock) {
    const ag = { tasks: [], done: [], hasWakeItems: false };
    const cal = calendarClock(clock.now);
    for (const item of items) {
      if (item.deletedAt != null || item.paused) continue;
      const first = ag.tasks.length;
      if (I.hasCost(item)) { P.addBill(item, clock, cal, ag); for (let k = first; k < ag.tasks.length; k++) ag.tasks[k].today = cal.day; continue; }
      const s = item.schedule;
      if (S.usesWake(s) && !I.isFinished(item)) ag.hasWakeItems = true;
      // A day is a calendar day: after midnight it's the new date. Only items timed from waking up follow
      // your wake-up (the day of your latest wake-up time), so staying up late doesn't redo or lose them.
      const ck = S.usesWake(s) ? clock : Object.assign({}, cal, { usualDay: clock.usualDay });
      // Completed: everything since midnight and since you woke up, so last night's check-offs stay visible.
      if (s.kind !== "goal") for (const e of item.log) if (C.includes(clock, e) || C.includes(cal, e)) ag.done.push(P.doneRow(e, item));
      if (I.isFinished(item)) continue;
      if (s.kind === "goal") { P.addGoal(item, ck, true, ag); for (let k = first; k < ag.tasks.length; k++) ag.tasks[k].today = ck.day; continue; }
      const before = ag.tasks.length;
      if (S.isHourly(s)) P.addHourly(item, ck, ag);
      else { P.addOverdue(item, ck, ag); P.addToday(item, ck, ag); }
      if (ag.tasks.length === before) { const next = P.nextRow(item, ck, ck.day); if (next) ag.tasks.push(next); }
      // Countdowns ("Tomorrow", "2 days late") count from the row's own day: the calendar, or your wake-up day.
      for (let k = first; k < ag.tasks.length; k++) ag.tasks[k].today = ck.day;
    }
    ag.tasks.sort(P.listOrder);
    ag.done.sort((a, b) => (a.at || 0) - (b.at || 0));
    return ag;
  },
  // Rows for the Bills list: each bill's current or next payment.
  bills(items, now) {
    const clock = calendarClock(now), rows = [];
    for (const item of items) {
      if (!I.isActive(item) || !I.hasCost(item)) continue;
      if (I.isAnyDayBill(item)) { rows.push(entry({ id: item.id + "|info", itemID: item.id, title: I.title(item), day: clock.day, state: "info", isBill: true })); continue; }
      if (I.isAutopay(item)) {
        const row = P.nextRow(item, clock, addDays(clock.day, -1));
        if (row) { row.state = "info"; row.isBill = true; rows.push(row); }
        continue;
      }
      const ag = { tasks: [], done: [] };
      P.addOverdue(item, clock, ag);
      P.addToday(item, clock, ag);
      let pick = null;
      if (ag.tasks.length) pick = [...ag.tasks].sort(P.billOrder)[0];
      else if (ag.done.length) pick = ag.done[0];
      else pick = P.nextRow(item, clock, clock.day);
      if (pick) { pick.isBill = true; rows.push(pick); }
    }
    for (const r of rows) r.today = clock.day;
    return rows.sort(P.billOrder);
  },
  // Turns a log entry into a "Completed" row.
  doneRow(e, item) {
    return entry({ id: "log|" + e.id, itemID: item.id, title: I.title(item), day: e.day, slot: e.slot, state: e.kind === "done" ? "done" : "skipped",
      logID: e.id, at: e.at, hourly: S.isHourly(item.schedule) });
  },
  // From when a check-off counts for this occurrence.
  windowStart(previous, due, clock) { if (previous != null && previous < due) return previous; return clock.began < due ? clock.began : dStart(clock.day); },
  // Adds a bill's rows to the agenda.
  addBill(item, clock, cal, ag) {
    if (I.isAutopay(item) || I.isAnyDayBill(item)) return;
    for (const e of item.log) if (C.includes(clock, e) || C.includes(cal, e)) { const r = P.doneRow(e, item); r.isBill = true; ag.done.push(r); }
    if (I.isFinished(item)) return;
    const due = { tasks: [], done: [] };
    P.addOverdue(item, cal, due);
    P.addToday(item, cal, due);
    if (!due.tasks.length) { const n = P.nextRow(item, cal, cal.day); if (n) due.tasks.push(n); }
    for (const r of due.tasks) { r.isBill = true; ag.tasks.push(r); }
  },
  // Adds today's occurrences of a task.
  addToday(item, clock, ag) {
    const s = item.schedule, today = clock.day;
    if (!S.occurs(s, today)) return;
    if (s.kind === "repeating" && today < item.trackFrom) return;
    const waiting = S.usesWake(s) && clock.wake == null;
    let previous = null;
    for (const slot of S.slots(s, today, clock.wake, C.end(clock))) {
      const due = slot.minute != null ? dDate(today, slot.minute) : null;
      const before = previous;
      if (due != null) previous = due;
      if (P.entryAt(item, today, slot.key, clock)) continue;
      const e = entry({ id: occurrenceID(item.id, today, slot.key), itemID: item.id, title: I.title(item), day: today, slot: slot.key, minute: slot.minute });
      if (waiting) { e.state = "waiting"; e.sortDate = dEnd(today); ag.tasks.push(e); continue; }
      if (due != null) { e.state = P.timeState(due, clock.now); e.deadline = due; e.deadlineKind = "time"; e.windowStart = P.windowStart(before, due, clock); }
      else { e.deadline = dEnd(today); e.deadlineKind = "endOfDay"; e.windowStart = clock.began; }
      P.applySnooze(item, e, clock);
      e.sortDate = e.deadline != null ? e.deadline : dEnd(today);
      ag.tasks.push(e);
    }
  },
  // Adds missed occurrences from earlier days (only for items that carry over).
  addOverdue(item, clock, ag) {
    const s = item.schedule;
    if (!S.carriesOver(s)) return;
    const today = clock.day, yesterday = addDays(today, -1);
    let missed = null;
    if (s.kind === "once" || s.kind === "afterDone") missed = S.previousOccurrence(s, yesterday);
    else if (s.kind === "repeating") {
      const p = S.previousOccurrence(s, yesterday);
      if (p && p >= item.trackFrom) {
        const next = S.nextOccurrence(s, addDays(p, 1));
        if (next == null || next > today) missed = p;
      }
    }
    if (!missed) return;
    for (const slot of S.slots(s, missed, null)) {
      if (P.entryAt(item, missed, slot.key, clock)) continue;
      const e = entry({ id: occurrenceID(item.id, missed, slot.key), itemID: item.id, title: I.title(item), day: missed, slot: slot.key, minute: slot.minute, state: "late", overdue: true });
      e.deadline = slot.minute != null ? dDate(missed, slot.minute) : dEnd(missed);
      e.deadlineKind = "missed";
      P.applySnooze(item, e, clock);
      e.sortDate = e.deadline != null ? e.deadline : dEnd(missed);
      ag.tasks.push(e);
    }
  },
  // If "Later" was chosen for this row, moves it to that time.
  applySnooze(item, e, clock) {
    const z = I.snooze(item, e.day, e.slot);
    if (!z) return;
    if (z.until > clock.now) {
      e.state = "snoozed"; e.snoozedUntil = z.until; e.minute = minOfDay(z.until); e.deadline = z.until; e.deadlineKind = "time"; e.windowStart = null;
    } else if (!e.overdue) {
      e.minute = minOfDay(z.until); e.state = P.timeState(z.until, clock.now); e.deadline = z.until; e.deadlineKind = "time"; e.windowStart = null;
    }
  },
  // Adds the current turn of an hourly task.
  addHourly(item, clock, ag) {
    const s = item.schedule, today = clock.day;
    if (today < s.start || today < item.trackFrom) return;
    const rowID = item.id + "|hourly";
    if (S.usesWake(s) && clock.wake == null) {
      ag.tasks.push(entry({ id: rowID, itemID: item.id, title: I.title(item), day: today, slot: 0, state: "waiting", hourly: true, sortDate: dEnd(today) }));
      return;
    }
    if (s.fromDone) {
      const next = P.fromDoneNext(item, clock);
      if (!next || next.minute == null) return;
      const due = dDate(today, next.minute);
      const e = entry({ id: rowID, itemID: item.id, title: I.title(item), day: today, slot: next.key, minute: next.minute, state: P.timeState(due, clock.now), hourly: true });
      e.deadline = due; e.deadlineKind = "time";
      const checks = P.hourlyChecks(item, today, clock);
      const last = checks.length ? checks.reduce((a, b) => (b.at > a.at ? b : a)) : null;
      e.windowStart = P.windowStart(last ? last.at : C.wakeDate(clock), due, clock);
      P.applySnooze(item, e, clock);
      e.sortDate = e.deadline;
      ag.tasks.push(e);
      return;
    }
    const slots = S.slots(s, today, clock.wake, C.end(clock));
    const logged = P.loggedSlots(item, today, clock);
    let index = -1;
    let li = -1;
    for (let k = slots.length - 1; k >= 0; k--) if ((slots[k].minute || 0) <= clock.minute) { li = k; break; }
    if (li >= 0 && !logged.has(slots[li].key == null ? -1 : slots[li].key)) index = li;
    else index = slots.findIndex((x) => (x.minute || 0) > clock.minute && !logged.has(x.key == null ? -1 : x.key));
    if (index < 0 || slots[index].minute == null) return;
    const m = slots[index].minute, due = dDate(today, m);
    const e = entry({ id: rowID, itemID: item.id, title: I.title(item), day: today, slot: slots[index].key, minute: m, state: P.timeState(due, clock.now), hourly: true });
    e.deadline = due; e.deadlineKind = "time";
    let previous = C.wakeDate(clock);
    if (index > 0 && slots[index - 1].minute != null) previous = dDate(today, slots[index - 1].minute);
    e.windowStart = P.windowStart(previous, due, clock);
    P.applySnooze(item, e, clock);
    e.sortDate = e.deadline;
    ag.tasks.push(e);
  },
  // True if this occurrence was already done or skipped.
  // Which day a check-off counts for. Wake-based items: anything checked since you woke up counts for today,
  // whatever day it was saved under (e.g. a device that briefly thought a new day had started).
  checkDay(item, e, clock) {
    if (!clock || clock.wake == null || !S.usesWake(item.schedule)) return e.day;
    return e.at >= clock.began && e.at <= clock.now + 60e3 ? clock.day : e.day;
  },
  // The check-off for one occurrence (see checkDay), or null.
  entryAt(item, day, slot, clock) {
    if (!clock || clock.wake == null || !S.usesWake(item.schedule)) return I.entry(item, day, slot);
    for (let k = item.log.length - 1; k >= 0; k--) { const e = item.log[k]; if (P.checkDay(item, e, clock) === day && sameSlot(e.slot, slot)) return e; }
    return null;
  },
  isLogged(item, day, slot, clock) {
    if (S.isHourly(item.schedule) && slot != null) return P.hourlyChecks(item, day, clock).some((e) => e.slot === slot);
    return P.entryAt(item, day, slot, clock) != null;
  },
  // Set of slot keys already done today for an hourly item.
  loggedSlots(item, day, clock) { return new Set(P.hourlyChecks(item, day, clock).map((e) => e.slot).filter((x) => x != null)); },
  // Today's check-offs of an hourly item.
  hourlyChecks(item, day, clock) {
    const since = S.usesWake(item.schedule) && day === clock.day ? clock.began : null;
    return item.log.filter((e) => P.checkDay(item, e, clock) === day && e.slot != null && !(since != null && e.at < since));
  },
  // Next turn of a "repeat after completion" hourly item.
  fromDoneNext(item, clock) {
    const s = item.schedule, today = clock.day;
    const first = S.slots(s, today, clock.wake, C.end(clock))[0];
    if (!first || first.minute == null) return null;
    const checks = P.hourlyChecks(item, today, clock);
    const key = (checks.length ? Math.max(...checks.map((e) => e.slot)) : -1) + 1;
    let minute = first.minute;
    if (checks.length) { const last = checks.reduce((a, b) => (b.at > a.at ? b : a)); minute = minutesUntil(today, last.at) + Math.max(1, s.every) * 60; }
    if (minute >= C.end(clock)) return null;
    return { key, minute };
  },
  // Adds an "any day" row with its progress (1 of 3 this week).
  addGoal(item, clock, oncePerDay, ag) {
    const s = item.schedule;
    const periodDay = s.goalPeriod === "day" ? clock.day : dayOf(clock.now);
    const [lo, hi] = S.goalRange(s, periodDay);
    const checks = item.log.filter((e) => e.kind === "done" && e.day >= lo && e.day <= hi);
    const count = checks.length;
    const e = entry({ id: item.id + "|goal", itemID: item.id, title: I.title(item), day: periodDay, minute: s.times.length ? s.times[0] : null,
      progress: count, total: s.goalCount, goal: true, goalPeriod: s.goalPeriod });
    e.deadline = dEnd(hi); e.deadlineKind = "period";
    e.windowStart = s.goalPeriod === "day" ? clock.began : dStart(lo);
    e.sortDate = dEnd(hi);
    const met = count >= s.goalCount;
    const checkedToday = oncePerDay && s.goalPeriod !== "day" && checks.some((x) => C.includes(clock, x));
    const latest = checks.length ? checks.reduce((a, b) => (b.at > a.at ? b : a)) : null;
    e.logID = latest ? latest.id : null;
    if (met || checkedToday) {
      e.state = "done"; e.at = latest ? latest.at : null; e.doneToday = checkedToday && !met;
      if (met) e.sortDate = dStart(addDays(hi, 1));
      ag.done.push(e);
    } else ag.tasks.push(e);
  },
  // The next future occurrence, for "Coming Up".
  nextRow(item, clock, day) {
    const s = item.schedule;
    let from = addDays(day, 1);
    if (s.kind === "repeating") from = maxDay(from, item.trackFrom);
    let found = null;
    for (let k = 0; k < 60; k++) {
      const d = S.nextOccurrence(s, from);
      if (!d) return null;
      const slots = S.slots(s, d, null);
      if (S.isHourly(s) || !slots.length) { found = [d, slots[0] || { key: S.isHourly(s) ? 0 : null, minute: null }]; break; }
      const open = slots.find((x) => !P.entryAt(item, d, x.key, clock));
      if (open) { found = [d, open]; break; }
      from = addDays(d, 1);
    }
    if (!found) return null;
    const [d, slot] = found;
    const e = entry({ id: occurrenceID(item.id, d, slot.key), itemID: item.id, title: I.title(item), day: d, slot: slot.key, minute: slot.minute, state: "future", hourly: S.isHourly(s) });
    const due = slot.minute != null ? dDate(d, slot.minute) : dEnd(d);
    e.deadline = due; e.deadlineKind = "later"; e.windowStart = P.previousTime(item, d); e.sortDate = due;
    // Timed from waking up: the next one comes after your next wake-up, which may be later today (not "Tomorrow").
    e.afterWake = S.usesWake(s);
    // Comes at the next wake-up, so before anything dated: order these by how long after waking.
    if (e.afterWake) e.sortDate = dDate(d, s.afterWaking || 0);
    return e;
  },
  // When the previous occurrence was due.
  previousTime(item, d) {
    const s = item.schedule;
    if (s.kind === "repeating") {
      const p = S.previousOccurrence(s, addDays(d, -1));
      if (p) { const sl = S.slots(s, p, null); const last = sl[sl.length - 1]; return last && last.minute != null ? dDate(p, last.minute) : dEnd(p); }
      return dStart(item.trackFrom);
    }
    if (s.kind === "afterDone") { const l = I.lastDone(item); return l ? l.at : item.createdAt; }
    return item.createdAt;
  },
  // Sort group: due now first, then waiting for wake-up, then any day, then future.
  rank(e) { if (e.state === "waiting") return 1; if (e.state === "future") return 3; return e.goal ? 2 : 0; },
  // Order of rows on Today: by rank, then anytime items for today first, then by due time.
  listOrder(a, b) {
    const l = P.rank(a), r = P.rank(b);
    if (l !== r) return l - r;
    const aa = a.deadlineKind === "endOfDay" ? 0 : 1, ba = b.deadlineKind === "endOfDay" ? 0 : 1;
    if (l === 0 && aa !== ba) return aa - ba;
    // Coming Up: by day, and on the same day things at wake-up come before set times.
    if (l === 3 && a.day !== b.day) return a.day < b.day ? -1 : 1;
    if (l === 3 && !!a.afterWake !== !!b.afterWake) return a.afterWake ? -1 : 1;
    if (a.sortDate !== b.sortDate) return a.sortDate < b.sortDate ? -1 : 1;
    return a.title.localeCompare(b.title, undefined, { numeric: true });
  },
  // Sort order for bills: late first, then by due date, then by name.
  billOrder(a, b) {
    if (a.sortDate !== b.sortDate) return a.sortDate < b.sortDate ? -1 : 1;
    return a.title.localeCompare(b.title, undefined, { numeric: true });
  },
  // The latest a "Later" can go: before the next one comes (and by midnight if it doesn't carry over).
  laterLimit(e, item, clock) {
    const s = item.schedule;
    let limit = Infinity;
    if (s.kind === "repeating") {
      const same = S.slots(s, e.day, e.day === clock.day ? clock.wake : null, C.end(clock));
      const next = e.slot != null ? same.find((x) => (x.key == null ? -1 : x.key) > e.slot) : null;
      if (next && next.minute != null) limit = dDate(e.day, next.minute);
      else {
        const nd = S.nextOccurrence(s, addDays(e.day, 1));
        if (nd) { const f = S.slots(s, nd, null)[0]; limit = dDate(nd, f && f.minute != null ? f.minute : 0); }
      }
      if (!S.carriesOver(s)) limit = Math.min(limit, dEnd(e.day));
    }
    return limit;
  },
  // The quick "Later" choices (In 1 Hour, In 3 Hours, This Evening, Tomorrow Morning) that still fit before the next turn.
  laterOptions(e, item, clock) {
    if (e.goal || isFinishedEntry(e)) return [];
    if (e.state === "info" || e.state === "future" || e.state === "waiting") return [];
    const now = clock.now, limit = P.laterLimit(e, item, clock);
    let c;
    // Bills are about days, not hours.
    if (e.isBill) { const t = dayOf(now); c = [["Tomorrow", dDate(addDays(t, 1), 9 * 60)], ["In 3 Days", dDate(addDays(t, 3), 9 * 60)], ["Next Week", dDate(addDays(t, 7), 9 * 60)]]; }
    else {
      c = [["In 1 Hour", now + 3600e3], ["In 3 Hours", now + 3 * 3600e3]];
      if (clock.minute < 18 * 60) c.push(["This Evening", dDate(clock.day, 19 * 60)]);
      c.push(["Tomorrow Morning", dDate(addDays(clock.day, 1), 9 * 60)]);
    }
    // Only times after it's due (putting off a 6 PM task "In 1 Hour" at 4 PM would make it earlier).
    const floor = e.deadlineKind === "time" && e.deadline != null && e.state !== "late" ? Math.max(now, e.deadline) : now;
    return c.filter((x) => x[1] > floor && x[1] < limit).map((x) => ({ label: x[0], date: x[1] }));
  },
  // The countdown text for a row, like "in 20m" or "2 days late", with a tone (now/late/normal).
  label(e, now, today) { if (e.today) today = e.today; return e.isBill ? P.billCountdown(e, now, today) : P.countdown(e, now, today); },
  // Due now or late. These are bold and counted on the Today tab.
  needsAttention(e, now, today) { const l = P.label(e, now, today); return !!l && (l.tone === "now" || l.tone === "late"); },
  // Countdown for bills, in days ("Today", "Tomorrow", "3 days late").
  billCountdown(e, now, today) {
    if (["info", "done", "skipped", "waiting"].includes(e.state)) return null;
    if (e.state === "snoozed") return P.countdown(e, now, today);
    if (e.goal) return null;
    const away = dIndex(e.day) - dIndex(today);
    if (away < 0) return { text: Format.days(-away) + " late", tone: "late" };
    if (away === 0) return { text: "Today", tone: "now" };
    if (away === 1) return { text: "Tomorrow", tone: "normal" };
    return { text: "In " + Format.days(away), tone: "normal" };
  },
  // Countdown for tasks, in minutes/hours/days.
  countdown(e, now, today) {
    if (e.deadline == null) return null;
    if (e.state === "skipped" || e.state === "waiting") return null;
    if (e.state === "done" && !(e.goal && e.doneToday && e.progress < e.total)) return null;
    const calm = e.state === "info" || e.state === "done";
    const seconds = (e.deadline - now) / 1000;
    const left = Math.ceil(seconds / 60), lateBy = Math.floor(-seconds / 60);
    if (seconds <= 0 && e.deadlineKind !== "later") {
      if (e.deadlineKind === "time" && lateBy < NOW_MINUTES) return { text: "Now", tone: calm ? "calm" : "now" };
      return { text: Format.span(Math.max(lateBy, 1)) + " late", tone: calm ? "calm" : "late" };
    }
    const tone = calm ? "calm" : "normal";
    switch (e.deadlineKind) {
      case "time": return { text: "In " + Format.span(left), tone };
      case "endOfDay": return { text: Format.span(left) + " left", tone };
      case "period": {
        const lastDay = dayOf(e.deadline - 1000);
        const days = dIndex(lastDay) - dIndex(dayOf(now)) + 1;
        if (days > 1) return { text: Format.days(days) + " left", tone };
        return { text: Format.span(left) + " left", tone };
      }
      case "missed": return { text: Format.span(Math.max(lateBy, 1)) + " late", tone: calm ? "calm" : "late" };
      case "later": {
        if (e.afterWake) return { text: "After waking", tone };
        if (e.minute != null && seconds > 0 && seconds < 86400) return { text: "In " + Format.span(left), tone };
        const days = dIndex(e.day) - dIndex(today);
        if (days <= 0) return { text: "Today", tone };
        if (days === 1) return { text: "Tomorrow", tone };
        return { text: "In " + Format.days(days), tone };
      }
    }
    return null;
  }
};

// ---------- Money ----------
// Year total: every bill counted for all 12 months of this year (January to December),
// not only from the month it was added. Paused and deleted bills are left out.
const Money = {
  // All ISO days from a to b, inclusive.
  daysBetween(a, b) { const out = []; for (let k = dIndex(a); k <= dIndex(b); k++) out.push(dFromIndex(k)); return out; },
  // True if a repeating bill is due on day d.
  onRepeat(d, s, anchor) {
    const n = Math.max(1, s.every);
    switch (s.unit) {
      case "hour": return true;
      case "day": return mod(dIndex(d) - dIndex(anchor), n) === 0;
      case "week": {
        const wd = s.kind === "repeating" ? S.effectiveWeekdays(s) : [weekday(anchor)];
        const weeks = Math.trunc((dIndex(monday(d)) - dIndex(monday(anchor))) / 7);
        return mod(weeks, n) === 0 && wd.includes(weekday(d));
      }
      default: {
        const step = s.unit === "month" ? n : 12 * n;
        return mod(monthIndex(d) - monthIndex(anchor), step) === 0 && d === inMonth(monthIndex(d), dParts(anchor)[2]);
      }
    }
  },
  // Payments of one bill in the month starting at `first`.
  payments(item, first) {
    const s = item.schedule, last = lastOfMonth(first), month = Money.daysBetween(first, last);
    switch (s.kind) {
      case "once": return s.start >= first && s.start <= last ? 1 : 0;
      case "repeating": return month.filter((d) => Money.onRepeat(d, s, s.start)).length;
      case "afterDone": {
        if (s.unit === "hour") return month.length * Math.max(1, Math.floor(24 / Math.max(1, s.every)));
        return month.filter((d) => Money.onRepeat(d, s, s.nextDue || s.start)).length;
      }
      case "goal": {
        if (s.goalPeriod === "day") return s.goalCount * month.length;
        if (s.goalPeriod === "week") return s.goalCount * month.filter((d) => S.goalRange(s, d)[0] === d).length;
        return s.goalCount;
      }
    }
    return 0;
  },
  // Bill totals for every month of this year (paused and finished bills left out).
  yearMonths(items, now) {
    const today = dayOf(now), year = dParts(today)[0];
    const bills = items.filter((i) => i.deletedAt == null && I.hasCost(i) && !i.paused && !I.isFinished(i));
    const out = [];
    for (let m = 1; m <= 12; m++) {
      const first = mkDay(year, m, 1);
      let amount = 0, payments = 0;
      for (const b of bills) { const n = Money.payments(b, first); amount += n * b.cost; payments += n; }
      out.push({ month: monthIndex(first), first, amount: Math.round(amount * 100) / 100, payments });
    }
    return out;
  }
};

if (typeof module !== "undefined") module.exports = { mkDay, dayOf, addDays, dDate, weekday, addMonths, S, I, P, C, Sleep, Money, Format, makeClock, calendarClock, newItem, newSchedule, parseAmount, minOfDay, dIndex, uid };
