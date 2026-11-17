# Routine

Routines, chores, goals and bills in one calm iPhone app.
Native Swift and SwiftUI, iOS 17 or later, English, French and Arabic, private iCloud sync with no account.

- **First time?** Follow [START-HERE.md](START-HERE.md) (one-time setup, about 15 minutes).
- **Submitting to the App Store?** Follow [APP-STORE-STEPS.md](APP-STORE-STEPS.md) (every click, plus all the texts to copy).

## Releasing a new build

GitHub → **Actions** → **TestFlight** → **Run workflow** → type the version (for example `1.0.0`) → **Run workflow**.
The build number is set automatically from the date and time, so it always goes up.

## What's in here

| Folder | What it is |
| --- | --- |
| `Routine/Model` | Scheduling and money rules (what's due when, totals) |
| `Routine/Store` | Saving on the iPhone, iCloud sync, one-time import from the old app |
| `Routine/Reminders` | Local notifications with Done / In 1 hour / I'm up buttons |
| `Routine/Views` | The screens: Today, Routines, Money, editor, Settings, Welcome |
| `Routine/Resources` | App icon, colors, translations (en, fr, ar), privacy manifest |
| `RoutineTests` | Automatic tests for scheduling and money |
| `Config` | Info.plist and the iCloud entitlement |
| `.github/workflows` | **TestFlight** (build + upload), **Tests** (run the tests) and **Screenshots** (see the app in a simulator) |
| `ci` | Small helper files used by the workflows |
| `design` | Icon artwork (SVG) and a preview |
| `docs` | Support and privacy pages for the App Store listing |
| `scripts` | Regenerate the icon (`make-icons.cjs`) and translations (`localize.py`) |
| `project.yml` | Recipe the workflow turns into an Xcode project (with XcodeGen) |
