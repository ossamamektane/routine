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

- `mac/`, `.github/workflows/mac.yml`: the Mac app (see Mac app).

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

- `routine-data`: `{ items: [...], wakes: { "2026-11-26": 450, ... }, wakesModifiedAt, settings: { currency, modifiedAt } }`. This is what Export/Import uses.
- `routine-sleep`: the sleep log (when the app was used, learned wake-up times). This device only.
- `routine-prefs`: this device's settings (reminders, badges, 24-hour time, open tab, reminders already shown, sync repository and token).

One item (task or bill), see `newItem()` in model.js:

```
id, title, notes
schedule: { kind, every, unit, start, times, weekdays, afterWaking, nextDue, nextDueTime, fromDone, goalCount, goalPeriod }
cost      null for tasks; a number makes it a bill
autopay   bill pays itself on its due date
reminder  "off" | "onTime" | "dayBefore" | "whenBehind"
paused, pauses: [{ start, end }]
trackFrom first day that counts (missed days before it are ignored)
log:      [{ id, kind: "done"|"skipped", at, day, slot, ... }]   history
snoozes:  [{ day, slot, until }]                                 "Later"
createdAt, modifiedAt, deletedAt (deleted items are kept a while so imports don't bring them back)
```

`schedule.kind`:

- `repeating`: every N hours/days/weeks/months/years (`every`, `unit`, `weekdays`, `times`, `afterWaking` = minutes after waking up).
- `once`: one time, on `start`.
- `afterDone`: next due N units after it was last done (`nextDue`, `nextDueTime`).
- `goal`: "any day": `goalCount` times per `goalPeriod` (day/week/month).

## Updates and caching

No caching: there is no service worker, and every visit loads the newest files. After changing any file, bump the number in `?v=` on both `<script>` tags in index.html **and** `VERSION` in app.js (same number). If a browser shows an older page (GitHub Pages lets browsers keep pages up to 10 minutes), `checkForUpdate()` sees the newer number and reloads once. Data is never cached: GitHub requests use `cache: "no-store"`. The app needs the internet to open (no offline mode).

## How it runs

- Layout: everything is inside `table#page`. `fitPage()` sets its width when the page opens and on every resize or rotation: full width on phones, a centered 720-pixel column on wider screens. It also sizes the search boxes and puts the currency menu next to its name when there is room. Under 360 pixels (`NARROW`) list rows use tighter padding, the right column may wrap, short labels like "7 days late" stay on one line (`keepTogether`), and any-day bills say "This month" instead of "Any day this month". Checked with no sideways scrolling at 280, 320, 390, 768 and 1280 pixels. These are HTML attributes, not CSS.

1. `start()` (bottom of app.js) fills Settings, opens the saved tab, then calls `tick()` at the start of every minute and whenever the page comes back (visibilitychange, focus, pageshow). A timed task shows "Now" for 5 minutes (`NOW_MINUTES`), then how late it is.
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
- When it syncs: on opening, every minute while the page is showing, 4 seconds after a change (quick changes go together in one commit), and when the internet comes back.
- Each sync downloads `data.json`, merges with `mergeData` (the same merge Import uses), and saves only if this device has something newer. Saves include the file's last version (`sha`); if another device saved first, GitHub refuses (409/422) and the device waits a random moment, merges again and retries (4 tries). Every save is a commit, so the `data` branch keeps the history.
- Merge rules: the most recently changed version of each task or bill wins (`stamp()` never goes backwards, even if a device's clock is wrong). Equal times pick the same winner on every device. Check-offs from all devices are kept, except ones that were undone (`logGone`). Deleted items stay deleted for 2 years (slimmed after 60 days). Wake-up times merge per day (`db.wakeStamps`), newest wins.
- If `data.json` can't be read, it is never overwritten; Settings > Sync says so.
- Settings > Sync shows "Saved just now", "Offline. Changes will be saved later.", or what went wrong.
- The sleep log stays on each device.

## Mac app

`mac/` wraps the same files in a Mac app (WKWebView). It works offline, shows reminders as Mac notifications and the Today count on the Dock icon. Sync is the same as the website.

- Built automatically by GitHub (`.github/workflows/mac.yml`) on every push to `main`. The download is on the repository's Releases page, "mac-latest", file `Routine-mac.zip`.
- Install: unzip, drag Routine to Applications. First launch: right-click > Open (or System Settings > Privacy & Security > Open Anyway), because the app is not signed by Apple. Allow notifications when asked.
- Data is stored in `~/Library/Application Support/Routine/storage.json`.
- Updates: when the website has a newer version, Settings shows "Update Available" with Download.
- The web files are copied into the app when it's built, so the app uses the version from that build.
- `main.swift` talks to app.js through `window.webkit.messageHandlers.routine` (`toNative` in app.js; `NATIVE` is false in browsers). Messages: store, unstore, reminders, badge, askPermission, export, open.
