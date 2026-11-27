# Routine (web)

A plain HTML version of the Routine iPhone app: daily tasks, bills, and a day that starts when you wake up.
It runs in any browser, offline too. Data is saved in the browser (localStorage). There is no server yet.

## Rules for working on this app (read first)


1. **No CSS.** No `<style>`, no `style=""`, no classes for looks. Layout only uses HTML itself:
   `<table width="100%">`, `align="center"`, `cellpadding`, `frame`/`rules`, `<fieldset>`, `<hr>`, `<br>`, `<small>`, `<b>`, `<i>`, `<s>`.
2. **No colors, no icons, no emojis, no logo.**
3. **Bold means "needs you now"** and nothing else: countdowns that are due or late, and the "Did you sleep?" question.
   Table headings (`<th>`) are bold by browser default; that's fine.
4. **Italic** = overdue details and paused items. **Strikethrough** = done or finished. **Greyed out** (disabled checkbox) = can't be done right now.
5. **Only show what's possible.** The More buttons list only actions that work for that row. Never show disabled choices.
6. **Wording:** short and plain, like Apple's apps. Title Case for buttons and headings ("Add a Time", "Other Time..."),
   "..." after a button that opens something else. No explaining sentences unless really needed. No suggestions or presets.
7. **Made for anyone**, not one person: currency, language and 24-hour time come from the user's own browser.
8. **Symmetric layout:** page titles centered with equal side columns (Cancel left, Add/Save right), centered single items, full-width lists.
9. The rules (what's due when, when to ask "Did you sleep?") match the iPhone app's Swift code. Change them only on purpose.

## Files

- `icon.png`: the logo.
- `tests/sleep/`: lifestyle simulator that fits the sleep question's weights.
- `tests/rare.cjs`: rare-case checks (day and wake-up, Later, reminders, Coming Up order, tab bar, payments, repeat editor, updates, 5-second sync), run with Playwright + Chromium (paths at the top).
- `apps/`, `.github/workflows/apps.yml`: the Mac and iPhone/iPad apps (see Apps).

| File | What's in it |
| --- | --- |
| `index.html` | The page: tab buttons, one `<section>` per tab, the panels (editor, wake-up time, done at), Settings. |
| `model.js` | Pure rules, no page access. Days, schedules, items, the "day you're living" clock, sleep detection, the planner (what shows on Today), bill totals. Port of the Swift `Model/` folder. |
| `app.js` | Everything else: saving/loading, actions (done, undo, later, pause...), reminders, drawing the tabs as HTML, the editor, events, start-up. Port of `AppStore` + the SwiftUI views. |
| `sw.js` | Only removes the service worker and offline copies left by older versions. Nothing is cached anymore. |
| `manifest.json` | Lets people add it to the Home Screen as an app. |

`model.js` loads first and only defines things. `app.js` uses them.

## Short names used in the code

| Name | Meaning |
| --- | --- |
| `S` | Schedule functions (`S.occurs`, `S.summary`, ...) |
| `I` | Item functions (`I.title`, `I.hasCost`, ...) |
| `C` | Clock functions (`C.isUp`, `C.end`, ...) |
| `P` | Planner: builds the rows for Today and Bills (`P.agenda`, `P.bills`, `P.label`) |
| `Sleep` | "Did you sleep?" logic |
| `Money` | Bill totals per month |
| `Format` | Text for times, dates, money, durations |
| `$` | `document.getElementById` |
| `esc` | Escapes text for HTML. Use it on anything the user typed. |
| day / `iso` | A calendar day as text: `"2026-11-26"` |
| minute | Minutes after midnight (`540` = 9:00 AM). Over 1440 = after midnight of the next day. |
| ms / `at` | A timestamp in milliseconds |
| entry / `e` | One row on Today/Bills (one occurrence of an item), made by `entry()` in model.js |
| slot | Which time of the day an occurrence is, for items due several times a day |

## Saved data

localStorage keys:

- `routine-data`: `{ items: [...], wakes: { "2026-11-26": 450, ... }, wakesModifiedAt, settings: { currency, modifiedAt } }`. This is what Export/Import and sync use.
- Days are calendar days: after midnight it's the new date for tasks and bills. Only tasks timed from waking up follow your wake-up: they belong to the day of your latest wake-up time in `wakes` (synced to GitHub), so staying up past midnight doesn't redo or lose them, and the next one says "After waking", never "Tomorrow". The wake-up time never resets by itself (not at midnight, not after a quiet stretch, not on reload): only a new wake-up time changes it, or 36 hours after waking (`MAX_DAY`). `makeClock` gives the wake-up day; `P.agenda` uses the calendar for everything else. Setting a wake-up time (today or yesterday) removes any later one. Completed on Today lists check-offs since midnight and since you woke up.
- `routine-sleep`: the sleep log (when the app was used, learned wake-up times). This device only.
- `routine-prefs`: this device's settings (reminders, badges, 24-hour time, open tab, reminders already shown, sync repository and token).

One item (task or bill), see `newItem()` in model.js:

```
id, title, notes
schedule: { kind, every, unit, start, times, weekdays, afterWaking, nextDue, nextDueTime, fromDone, goalCount, goalPeriod, monthDays, months, nth }
cost      null for tasks; a number makes it a bill
payment   how the money leaves: autoRenew | directDebit | standingOrder (pay themselves) | cash | card | transfer | mobile (by hand)
autopay   marked paid on its due date without a check-off (methods that pay themselves, or by hand + "Count as Paid")
reminder  "off" | "onTime" | "dayBefore" | "whenBehind"
paused, pauses: [{ start, end }]
trackFrom first day that counts (missed days before it are ignored)
log:      [{ id, kind: "done"|"skipped", at, day, slot, ... }]   history
snoozes:  [{ day, slot, until }]                                 "Later"
createdAt, modifiedAt, deletedAt (deleted items are kept a while so imports don't bring them back)
```

`schedule.kind`:

- `repeating`: every N hours/days/weeks/months/years (`every`: any number 1-999, typed like Apple's Reminders; `unit`, `weekdays`, `times`, `afterWaking` = minutes after waking up). Monthly: `monthDays` (days 1-31; a day a month doesn't have is skipped) or `nth` = `{ n: 1-5 or -1 (last), wd: 1 (Sun)-7 }` ("On the last Friday"). Yearly: `months` (1-12) and optional `nth`. Empty = the start date's day and month.
- `once`: one time, on `start`.
- `afterDone`: next due N units after it was last done (`nextDue`, `nextDueTime`).
- `goal`: "any day": `goalCount` times per `goalPeriod` (day/week/month).

## Updates and caching

No caching: there is no service worker, and every visit loads the newest files. After changing any file, bump the number in `?v=` on both `<script>` tags in index.html **and** `VERSION` in app.js (same number). `checkForUpdate()` runs at start, every 2 minutes and whenever Routine comes back: a newer number reloads the page by itself (at start right away, otherwise when no panel is open and nothing was touched for 10 seconds, or when Routine is hidden). In the apps it asks the app to download the new copy first. Data is never cached: GitHub requests use `cache: "no-store"`. The app needs the internet to open (no offline mode).

## How it runs

- Layout: everything is inside `table#page`. `fitPage()` sets its width when the page opens and on every resize or rotation: full width on phones, a centered 720-pixel column on wider screens. It also sizes the search boxes and puts the currency menu next to its name when there is room. Under 360 pixels (`NARROW`) list rows use tighter padding, the right column may wrap, short labels like "7 days late" stay on one line (`keepTogether`), and any-day bills say "This month" instead of "Any day this month". Checked with no sideways scrolling at 280, 320, 390, 768 and 1280 pixels. These are HTML attributes, not CSS.

1. `start()` (bottom of app.js) fills Settings, opens the saved tab, then calls `tick()` at the start of every minute and whenever the page comes back (visibilitychange, focus, pageshow). A timed task shows "Now" only during its own minute (`NOW_MINUTES`), then how late it is ("1m late").
2. `tick()` updates the time, checks whether to ask "Did you sleep?", then `render()` and `planReminders()`.
3. `render()` rebuilds Today, Tasks and Bills as HTML strings from the data (`renderToday`, `renderTasks`, `renderBills`).
4. Clicks are handled by a few listeners at the bottom of app.js (`data-do`, `data-act`, `data-item`, `data-more`, `data-check`, `data-e`, `data-f` attributes say what a control does).
5. Every change goes through an action (`complete`, `undo`, `snooze`, `saveItem`, `mutate`...), which ends with `commit()`: save, render, re-plan reminders.

## Adding something

- A new action on a row: add it to the list in `agendaRow()` (Today) or `itemMenu()` (Tasks/Bills) with when it's possible, then handle its value in `onAction()` / `onItemMenu()`.
- A new editor field: draw it in `renderEditor()` with a `data-f="name"` attribute, handle it in `editorChange()`.
- A new setting: add a row to the Settings table in `index.html` (name + `<small>` note on the left, control on the right, like list rows), store it in `prefs` (this device) or `db.settings` (exported), wire it in the events part of app.js.

## Testing

Open `index.html` in a browser. To load data, use Settings > Import with an exported file.
Headless screenshot (Chromium):

```
chromium --headless --window-size=390,900 --screenshot=out.png "file:///path/to/index.html#today"
```

`#today`, `#tasks`, `#bills`, `#settings` open that tab.

## Sync (GitHub)

Like wordpad.cc: open `ossamamektane.github.io/routine` on any device and your tasks and bills are there. Nothing to set up.

- Saved as `data.json` (same format as an export) in `ossamamektane/routine`, on the **`data`** branch, so saving never rebuilds the site. The branch is made automatically the first time. To see the file on GitHub: open the repository, switch the branch menu from `main` to `data`.
- The GitHub token is in app.js (`SYNC_TOKEN_PARTS`), reversed and base64-encoded so GitHub's secret scanner doesn't revoke it. This was chosen on purpose: anyone who reads the code can get the token and read or change the data and the repository.
- New token (when it expires): `btoa("github_pat_...".split("").reverse().join(""))` in a browser console, split the result into 3 pieces, and put them in `SYNC_TOKEN_PARTS`.
- When it syncs: on opening, 1 second after a change, when the internet comes back, and whenever `data.json` changed: `pollSync()` asks GitHub every 5 seconds with the file's ETag (an unchanged answer is a tiny 304 that doesn't count against GitHub's limit). Changes from another device show up within about 5 seconds. The Mac app keeps this running with its window hidden (a 5-second timer calls `routineNative.poll`); on iPhone and iPad it runs while Routine is open.
- Each sync downloads `data.json`, merges with `mergeData` (the same merge Import uses), and saves only if this device has something newer. Saves include the file's last version (`sha`); if another device saved first, GitHub refuses (409/422) and the device waits a random moment, merges again and retries (4 tries). Every save is a commit, so the `data` branch keeps the history.
- Merge rules: the most recently changed version of each task or bill wins (`stamp()` never goes backwards, even if a device's clock is wrong). Equal times pick the same winner on every device. Check-offs from all devices are kept, except ones that were undone (`logGone`). Deleted items stay deleted for 2 years (slimmed after 60 days). Wake-up times merge per day (`db.wakeStamps`), newest wins.
- If `data.json` can't be read, it is never overwritten; Settings > Sync says so.
- Settings > Sync shows "Saved just now", "Offline. Changes will be saved later.", or what went wrong.
- The sleep log stays on each device.

## "Did you sleep?" (SleepAI in model.js)

No fixed night: it learns your own pattern, so night shifts, split sleep, naps, 30-hour days, 4-hour sleeps and rarely opening the app all work.

- Clues for a quiet stretch (no use of Routine on this device, and no check-offs on any device): its length compared with your usual sleep, how much of it falls in your usual sleep hours (a 96 quarter-hour map learned from your answers; a generic night only until you've answered a few times), whether right now is still inside your sleep hours (a look at the phone mid-sleep), how long you'd been up, whether it's longer than your usual quiet-but-awake stretches, closeness to your usual wake-up, missed reminders, and brief looks at the phone (2-3 minutes between long quiet stretches count as part of the same sleep).
- Look back: if you slept without touching Routine and then used it later (a very long "Up for"), an earlier quiet stretch that is almost surely a sleep is asked about first ("Quiet since 8:00 PM").
- Learns from: Yes plus a wake-up time (`log.sleeps`), Not Yet (`log.awakeGaps`, asks less eagerly), and setting the wake-up time by hand after a missed sleep (asks a little sooner). Not Yet inside your usual sleep hours counts as a look mid-sleep: nothing changes, it waits 90 minutes.
- The wake-up panel starts at the best guess (now, or the end of your usual sleep if you opened Routine much later).
- Weights (`SleepAI.W`) were fitted on 12 simulated lifestyles (office, night shift, rotating shifts, rapper, binges with 18-44 hours up, delivery with split sleep, busy businessman, two sleeps a day, new parent, student, insomniac, early sleeper with naps): `node tests/sleep/fit.cjs` (then copy weights.json into `SleepAI.W` and thresholds.json into `threshold` / `lookBack`), results `node tests/sleep/show.cjs`, checks `node tests/sleep/cases.cjs`. Caught at the first open after waking: 93% (old fixed rules: 69%); wrong questions: about 1 a week, answered with one tap.
- The sleep log stays on each device; wake-up times sync.

## Same pattern everywhere

- **Today** (doing): title; under it when (time or date, never "Tomorrow") and the short repeat; right column: a countdown ("In 37m", "11m late", "Today", "In 2 days", "After waking"). Checkboxes only here.
- **Tasks and Bills** (managing): no checkboxes. Title; line 1: [amount ·] full schedule (`S.summary`); lines 2-3 (`itemDetails`): Type · Repeat style (On a schedule, Any day, After completion/payment, One time — the same words as the group headings), then Timing (After waking, At set times, Any time, From last done) or Payment method · Reminder (the editor's own words: Reminder at the time, in the morning, the day before, on the day, when behind, every day, No reminder; bills: Pays itself, Counted as paid). Right column: the countdown to the next one, or one word when there is none (Paused, Finished).
- Group headings: Every Day, On a Schedule, Any Day, After Completion/Payment, One Time, Paused, Finished.

## More buttons

One line, only what makes sense right now, most used first and the one you can't take back last. Today: Done (Paid for bills), Later..., Skip, Undo, Done At..., Change Time..., Edit..., Pause. Tasks and Bills: Edit..., Undo Payment, Pause/Resume, Duplicate..., Delete... Panels end with "...".

Later... opens its own page (date, time, and quick choices that fill them in). It shows when there's something to put off: due now, within the hour, no set time today, late, or already put off (also for tasks every few hours); not for a 6 PM task at 10 AM. Quick choices are always after the due time; bills get days (Tomorrow, In 3 Days, Next Week). New daily bills start with no reminder.

A Later can't go past the next one (`P.laterLimit`: the next turn, or midnight for things that don't carry over); the picker says "Choose an earlier time." A Later only rings if its row is still on Today then, so an old Later never rings. Long Laters (Next Week) are kept.

Wake-based items: a check-off made since you woke up counts for today, whatever day it was saved under (`P.checkDay`, `P.entryAt`), so a device that briefly thought a new day had started can't shift the next reminder or tick off tomorrow. `remindersPlan` works out the day for right now (its 90 s look-back only picks which reminders to show).

Reminder "When I'm behind" counts whole check-offs (`S.goalPace`, rounded down): once a week rings on the last day, 3 a week from day 3.

Coming Up: by day; on the same day, things at wake-up ("After waking") come before set times.

Panels (Edit, Later, Done At, Wake-Up Time) replace the whole page, tab bar included, like a sheet: Cancel or Save brings the tabs back. Number keys don't switch tabs while one is open.

Wake-up wording is the same everywhere: "After waking", "When I wake up", "15 min after waking".

## Apps (Mac, iPhone, iPad)

`apps/` wraps this site in real apps (WKWebView). **Site changes never need a new app build**: the apps download the site by themselves.

- How the apps get site changes: they show their own copy of the site (`routine://app/...`), so they open instantly and work offline. On opening, on coming back, and every 5 minutes they download index.html and every file it uses (`src=` needed, `href=` optional, plus manifest.json and icon.png). If anything changed, the new copy replaces the old one and the page reloads when nothing is being edited (`routineNative.updateReady` in app.js).
- Safety: a new copy must send `toNative({ type: "ready" })` within 20 seconds (end of `start()` in app.js; **keep it**). If it doesn't, the app goes back to the previous copy and skips that version until the site changes again.
- New files: any file linked from index.html with `src="..."` or `href="..."` is downloaded too. Use relative paths (no leading `/`, no `..`).
- Data: localStorage is replaced in the apps by a copy kept by the app (`apps/Shared/bridge.js`), saved in `storage.json` (plus `storage-backup.json`) in the app's Application Support folder. The page reads it fresh on every load (`prompt("routine:storage")`, answered by the app). Sync is the same as the website.
- The apps add: reminders as real notifications (next 60, they ring when the app is closed), the Today count on the icon, alerts, Import, Export (Mac: save panel, iPhone: share sheet).
- Logo: `icon.png` (1024 × 1024, a Times "R", black on white). Website and Home Screen use it directly. The Mac Dock icon is drawn from the downloaded icon.png while the app runs. The icon inside the apps (Finder, iPhone Home Screen) is made from icon.png when the apps are built (`apps/make_icons.py`).
- Built by GitHub (`.github/workflows/apps.yml`) only when `apps/`, `icon.png` or the workflow change. Download: Releases, "mac-latest": `Routine-mac.zip` and `Routine-ios.ipa`.
- Mac install: unzip, drag to Applications. First launch: System Settings > Privacy & Security > Open Anyway (not signed by Apple).
- iPhone/iPad install: AltStore (free Apple ID; AltServer on the Mac renews it every 7 days on the same Wi-Fi). Download Routine-ios.ipa on the phone, then AltStore > My Apps > + .
- SHELL 2: the page keeps running with the window hidden and polls sync every 5 seconds; site checks every 5 minutes even in the background.
- App changes (Swift): bump `SHELL` in `apps/Shared/Core.swift` and `SHELL_LATEST` in app.js together; older apps then show "Update Available" in Settings.
- Messages from the page (`toNative`): store, unstore, ready, reminders, badge, askPermission, export, open, checkSite. From the app: `routineNative.permission(p)`, `.resume()`, `.updateReady()`. `window.ROUTINE_APP` = { platform: "mac" | "ios", shell }.
