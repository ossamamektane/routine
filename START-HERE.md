# Start here

This folder replaces the Expo app. It's a native SwiftUI app that merges **Routines** and **Bills** into one app called **Routine**, syncs through iCloud with no login, and builds on GitHub Actions without a Mac.

It keeps the same bundle ID (`com.ossamamektane.routines`), so it's an **update** to your existing app in App Store Connect, not a new app.

You only do steps 1–4 once.

---

## 1. Turn on iCloud for the app (Apple Developer website)

1. Open **developer.apple.com/account** → **Certificates, IDs & Profiles** → **Identifiers**.
2. Click `com.ossamamektane.routines` (EAS may have named it something like "[expo] com.ossamamektane.routines").
3. Under **Capabilities**, tick **iCloud**. You don't need to pick a container: Routine uses iCloud key-value storage, which doesn't need one.
4. Click **Save**, then **Confirm**. Apple warns that profiles will be invalidated. That's expected, and the workflow makes new ones.

## 2. Check the App Store Connect key has the Admin role

The workflow lets Apple create the signing certificate and profile automatically. Apple only allows that with an **Admin** key.

1. Open **appstoreconnect.apple.com** → **Users and Access** → **Integrations** → **App Store Connect API** → **Team Keys**.
2. Find the key whose **Key ID** matches your `ASC_KEY_ID` secret. The **Access** column must say **Admin**.
3. If it doesn't:
   - Click **+**, choose **Admin**, and download the `.p8` file. You can only download it once.
   - In GitHub → **Settings** → **Secrets and variables** → **Actions**, update `ASC_KEY_ID` with the new Key ID.
   - Update `ASC_KEY_P8` with the whole file content, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines.
   - `ASC_ISSUER_ID` stays the same.

## 3. Put this folder in your GitHub repository

Your **secrets stay where they are**. They live in the repository settings, not in the files.

**First, keep a copy of the Expo app:** on your repository page, click the branch menu (it says `main`), type `expo-backup`, and click **Create branch expo-backup from main**.

### Option A — GitHub Desktop (easiest)

1. Install **GitHub Desktop** and sign in. Then go to **File → Clone repository** and pick your repository.
2. **Repository → Show in Finder** (or **Show in Explorer**).
3. Show hidden files: on Mac press **Cmd + Shift + .**; on Windows go to **View → Show → Hidden items**.
4. Delete everything in that folder **except the `.git` folder**.
5. Unzip `Routine-Swift.zip`. Copy everything **inside** the `Routine-Swift` folder into the repository folder, including the hidden `.github` folder and `.gitignore`.
6. Back in GitHub Desktop, type a summary like `Native Swift app`. Click **Commit to main**, then **Push origin**.

### Option B — GitHub website only

1. On your repository page, delete the old Expo files and folders. For a folder, use **… → Delete directory**; for a file, open it and use **… → Delete file**. Delete the old workflow files in `.github/workflows` too, so nobody runs the EAS build by mistake.
2. **Add file → Upload files**, then drag in everything from inside `Routine-Swift` and commit.
3. Browsers often skip hidden folders, so check that `.github/workflows/testflight.yml` and `.github/workflows/tests.yml` exist. If they're missing, use **Add file → Create new file**, type the name exactly (for example `.github/workflows/testflight.yml`), paste the file's content, and commit. Do the same for `tests.yml`.

`EXPO_TOKEN` and `APPLE_TEAM_TYPE` are no longer used. You can leave them or delete them.

## 4. Build and send it to TestFlight

1. GitHub → **Actions** → **TestFlight** (left side) → **Run workflow**.
2. **Version:** the same version your App Store Connect version page shows (usually `1.0.0`). If that version is already live on the App Store, use `1.1.0` instead, because Apple doesn't accept new builds for a released version.
3. Click **Run workflow**. It takes about 10–20 minutes. A green check means it was uploaded.

The build number is the date and time (for example `2026.1116.2015`). It's always higher than the old EAS builds (61), so you never set it by hand.

> **GitHub minutes:** on a private repository, GitHub counts macOS minutes ×10 against your free monthly minutes. One build uses roughly 150 of the 2,000 free minutes. That's why the **Tests** workflow only runs when you start it.

## 5. Install it on your iPhone

1. In **App Store Connect → your app → TestFlight**, the build appears once Apple finishes processing it (5–30 minutes). The encryption question is already answered inside the app, so there's nothing to fill in.
2. Add yourself as an internal tester if you aren't one already. Then open the **TestFlight** app on your iPhone and tap **Update**.
3. **Don't delete the old app first.** Install over it. On first launch, Routine copies your routines from the old version once.
4. **Bills:** Bills was a separate app, and iOS doesn't let one app read another app's data. Add your bills again in the **Money** tab with **+**. It only takes a minute each.

### Quick test checklist

- [ ] Welcome screen → **Continue** → allow notifications.
- [ ] The time, Wi-Fi and battery show at the top of every screen.
- [ ] **Today** shows your imported routines.
- [ ] Add a routine with a time 2 minutes from now and lock the phone. The reminder arrives, and **Done** on the notification checks it off.
- [ ] Add a bill with an amount. It shows in **Money** (paid, left to pay, coming up).
- [ ] A routine with **After I Wake Up** waits until you tap **I'm up** on Today.
- [ ] Settings (gear on Today) shows **Synced with iCloud**.
- [ ] Switch the language to French or Arabic: iPhone **Settings → Apps → Routine → Language**. If Language isn't there, first add French or Arabic in **Settings → General → Language & Region**. Arabic should read right to left.
- [ ] Long-press the Home Screen → **Edit → Customize** → try **Dark** and **Tinted**. The icon changes with it.

## If something fails

The code was written without a Mac to compile it on, so the first build may need a small fix or two. That's normal.

- **Red ✗ on "Build":** a code error. Open the run, click the **Build** step, and copy the lines that contain `error:`. Or download everything with **… → Download log archive**. Send them to me and I'll fix them.
- **Red ✗ on "Sign and upload to TestFlight":** almost always setup.
  - The error mentions *Cloud signing permission* → see step 2 (Admin key).
  - The error mentions *iCloud* or *ubiquity-kvstore-identifier* → see step 1.
  - The error says *train version … is closed* → run again with a higher version (for example `1.1.0`).
  - The run page has a **testflight-logs** download with Apple's full details.

## Later

- **New version:** run **TestFlight** again with a new version number (`1.0.1`, `1.1.0`…).
- **Tests:** Actions → **Tests** → **Run workflow** runs the automatic scheduling and money tests (optional).
- **Screenshots:** Actions → **Screenshots** → **Run workflow** opens the app in an iPhone simulator, taps through it and saves screenshots and videos. Download **Routine-screenshots** at the bottom of the finished run. No signing needed.
- **Changing text, the icon or translations:** ask me. For reference: the translations come from `scripts/localize.py`, and the icon from `design/*.svg` via `scripts/make-icons.cjs`.

## When it all works

Follow [APP-STORE-STEPS.md](APP-STORE-STEPS.md). It covers every click in the Apple Developer website and App Store Connect, plus the texts to paste.
