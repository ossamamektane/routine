# App Store: step by step for the new version

Do this **after** the TestFlight build works on your iPhone (see START-HERE.md).
On GitHub, every grey box has a copy button in its top-right corner.

---

## Part 1 — Apple Developer website (developer.apple.com)

1. Go to **Account → Certificates, IDs & Profiles → Identifiers** and click `com.ossamamektane.routines`.
2. Tick **iCloud**. If it asks which kind, choose **Include CloudKit support**. You don't need to pick a container.
3. Leave every other tick (like Push Notifications) as it is. They don't hurt.
4. Click **Save**, then **Confirm**.
5. **Certificates** and **Profiles**: nothing to do. Old EAS profiles may now say "Invalid". That's fine; the workflow makes its own.

## Part 2 — App Store Connect key (once)

**Users and Access → Integrations → App Store Connect API → Team Keys**: the **Access** column for your key must say **Admin**.
If it doesn't, see START-HERE.md step 2.

## Part 3 — App Store Connect → Apps → Routines

### 3.1 App Information (left menu, under General)

| Field | Set it to |
| --- | --- |
| Name | `Routine: Planner & Bills` |
| Subtitle | `Daily routines, bills & goals` |
| Primary category | Productivity |
| Secondary category | Lifestyle |
| Content Rights | No, it does not contain, show, or access third-party content |
| Age Rating | **Edit**, answer **No / None** to every question, and the result is 4+ |

Click **Save** (top right).

### 3.2 App Privacy (left menu)

1. **Privacy Policy URL**: the link to your privacy page (see "Your two web pages" below).
2. Under Data Collection, click **Get Started** (or **Edit**), choose **No, we do not collect data from this app**, and click **Save**.
3. Click **Publish** (top right).

### 3.3 Pricing and Availability (left menu)

1. **Price**: Free (USD 0.00). Leave all countries ticked.
2. Optional but recommended: under **iPhone and iPad Apps on Apple Silicon Macs** and **Apple Vision Pro**, untick availability. Routine is made for iPhone, and this stops reviewers from testing it on other devices.

### 3.4 The version page (left menu, under iOS App)

1. **Which version:**
   - If your 1.0.0 was rejected, open it.
   - If 1.0.0 is already live, click **+** next to iOS App and type `1.1.0`.
   - The version here must be the same as the one you typed when you ran the TestFlight workflow.
2. **Previews and Screenshots → iPhone 6.9" Display**: delete the old screenshots. Upload 3–6 new ones taken in the new app: Today, Routines, Money, the editor, and Settings → Privacy.
   - Take them on your iPhone with Side button + Volume Up.
   - Use realistic sample routines, not your personal data.
   - If the size is refused, send them to me and I'll resize them (the required size is 1290 × 2796).
3. **Promotional Text**, **Description** and **Keywords**: paste from the "Texts to copy" section below.
4. **Support URL**: the link to your support page. **Marketing URL**: leave empty.
5. **What's New in This Version**: this field only appears if the app was live before. Paste from below.
6. **Build**:
   - If an old EAS build is attached, hover over it and click the ⊖ to remove it.
   - Click **Add Build** and pick the new one. Its number looks like a date, for example `2026.1116.2015`.
   - Click **Done**.
7. **App Review Information**:
   - **Sign-in required**: untick it.
   - **Contact**: Ossama Mektane, your phone number, `ossamamektane@proton.me`.
   - **Notes**: paste from below.
8. **Version Release**: choose **Manually release this version**, so you decide when it goes live.
9. Click **Save** (top right).

### 3.5 Submit

1. Click **Add for Review**, then **Submit to App Review**.
2. If the old rejection message is still open under **App Review** (left menu), reply there with the "Reply to the earlier rejection" text below.

### 3.6 The Bills app

Don't submit Bills again.

- If it's live, go to **Bills → Pricing and Availability → Remove from sale**.
- If it was never approved, you can delete it at the bottom of **App Information** (**Remove App**).

---

## Texts to copy

### Promotional text

```
Routines, bills and goals in one calm list. No account needed: your own iCloud keeps your iPhones in sync, and nothing is tracked.
```

### Keywords

```
habit,tracker,chores,reminder,schedule,morning,subscription,budget,todo,checklist,recurring,payday
```

### Description

```
Routine keeps the things you do regularly, and the bills you pay regularly, in one calm list.

TODAY AT A GLANCE
• Everything due today in one list, in time order
• Check things off with a tap, skip them, or move them to later
• Hourly routines, like drinking water, fill a progress ring through the day

ROUTINES THAT FIT REAL LIFE
• Every day, every other week, the 1st of the month or once a year
• After the last time: a haircut 6 weeks after the last one
• Goals: 3 workouts a week, whenever it suits you
• Morning routines that start when you tap "I'm up"
• One-time tasks that stay on Today until they're done

BILLS IN THE SAME PLACE
• Add an amount to anything: rent, subscriptions, a gym membership
• See what's paid and what's left to pay this month, and what's coming up
• Mark automatic payments so they never need checking off
• Your next 12 months at a glance

REMINDERS THAT HELP
• At the time, or the day before for bills
• Mark as done or snooze for an hour right from the notification

PRIVATE BY DESIGN
• No account, no sign-in, no ads, no tracking
• Syncs through your own iCloud
• Works offline

Available in English, French and Arabic.
```

### What's New in This Version

```
Routine has been rebuilt from the ground up as a native iPhone app.
• Bills are now part of Routine. Add an amount to anything and see what's paid and what's left in the new Money tab.
• Syncs through your own iCloud, with no account
• A new Today view with Done, Skip and Later
• Reminders with Done and "In 1 hour" buttons
• Routines that start when you wake up, goals, and routines based on the last time you did them
• In English, French and Arabic
```

### Notes for App Review

```
Routine is a personal planner for recurring things: daily routines, chores, goals and household bills.

One app, no duplicates: our separate "Bills" app has been discontinued and its features are now part of Routine. Routine was rebuilt natively in Swift and SwiftUI for this version. It doesn't use a commercial template, an app builder or any third-party SDK.

No account: there is no sign-up or login, so no demo account is needed. Everything is free and available right away. There are no in-app purchases.

How to try it:
1. Tap Continue on the welcome screen and allow notifications.
2. On Today, tap + and add "Water the plants". Set Frequency to Daily, tap "Add a Time" and pick a time 2 minutes from now, then tap Add. At that time a reminder arrives with "Done" and "In 1 hour" buttons.
3. On the Routines tab, tap + to add a Bill, a Goal (e.g. 3 times a week) or a One-time task. In the editor, the Type "After the last time" covers things like a haircut 6 weeks after the last one.
4. Turn on "After I Wake Up" for a routine. It waits on Today until you tap "I'm up".
5. Enter a Cost on any item, or tap + on the Money tab. Money shows what's paid and left to pay this month, upcoming payments and the next 12 months.

Data and privacy: data is stored on the device and synced through the user's private iCloud key-value storage (NSUbiquitousKeyValueStore). Without iCloud, the app works fully offline. Reminders are local notifications. There are no servers, no push notifications, no analytics, no ads and no tracking. The app collects no data.

Languages: English, French and Arabic (right-to-left).

Contact: ossamamektane@proton.me
```

### Reply to the earlier rejection

Change the part in [brackets] first:

```
Hello,

Thank you for the feedback. We've made substantial changes for Guidelines 4.3(a) and 2.1.

4.3(a): We consolidated our apps. "Bills" has been [removed from sale / withdrawn] and its features are now part of Routine, so we no longer offer similar apps. Routine has been rebuilt natively in Swift and SwiftUI, without templates or app-generation services. Its features include routines that start when you wake up, routines scheduled from the last time you did them, weekly goals, bills with automatic-payment tracking and a 12-month overview, and actionable reminders.

2.1:
- Purpose and audience: people who want to keep track of their recurring personal tasks and household bills.
- No login, no accounts, no in-app purchases, no ads.
- No third-party services or SDKs. Data stays on the device and in the user's private iCloud. We collect no data.
- Step-by-step instructions are in the App Review notes.

We've submitted a new build for review. Thank you!
```

---

## Your two web pages

The `docs` folder has a **support** page (`index.html`) and a **privacy policy** (`privacy.html`), with your email already in them. Apple needs a link to each. Publish them one of two ways:

- **GitHub Pages** (free if the repository is public): go to **Settings → Pages**, choose **Deploy from a branch**, then branch `main` and folder `/docs`, and **Save**. After a minute your links are `https://<your-username>.github.io/<repo-name>/` (support) and `https://<your-username>.github.io/<repo-name>/privacy.html` (privacy).
- **Notion** (works with a private repository): make two pages, paste in the text from the two files, then go to **Share → Publish** and copy each link.

Open both links on your phone before you paste them into App Store Connect.

---

## Why this avoids 2.1 and 4.3(a)

| Guideline | What Apple means | What this version does |
| --- | --- | --- |
| **4.3(a) Spam** | Two or more apps that look and work alike, or an app that looks like it came from a template. | Bills is merged into Routine, so there's only one app. It's rebuilt natively with its own features: wake-up routines, "after the last time" routines, goals, bills with autopay, and a 12-month view. |
| **2.1 App Completeness / Information Needed** | The reviewer couldn't see or use everything (login, missing info, bugs), or needs answers about the app. | No login at all, so no demo account. The notes explain how to try every feature. No servers, no third-party SDKs. |

**Other rejections this version already avoids**

- **5.1.1 (privacy):** no account, so account deletion isn't needed. A privacy manifest is included, and Settings → Privacy explains everything in the app.
- **4.5.4 (notifications):** notifications are optional, and the app explains them before asking.
- **2.1 (crashes):** saved data loads defensively. A damaged entry is skipped instead of crashing the app, and a backup of the previous save is kept.
- **Export compliance:** declared inside the app, so App Store Connect won't ask.
