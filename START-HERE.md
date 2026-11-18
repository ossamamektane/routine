# Start here

Routine is a native iPhone app. This project uses the new bundle ID **com.ossamamektane.routine** (singular). Apple treats it as a separate app from **com.ossamamektane.routines** (plural).

**Keep the old app and its record for now.** The new app installs separately; its TestFlight build, on-device data and iCloud storage do not automatically transfer from the old app. This project’s legacy import can only read data inside its own app container, not the other app’s container.

## 1. Register the new App ID

1. Open Apple Developer → **Certificates, IDs & Profiles → Identifiers**.
2. Click **+**, choose **App IDs**, then **App**.
3. Enter a description such as `Routine` and choose **Explicit** bundle ID: `com.ossamamektane.routine`.
4. Enable **iCloud**. Routine uses iCloud key-value storage; it does not require a CloudKit container. Complete the registration.

If the ID is unavailable or Apple asks you for a capability setting you are unsure about, stop and check before proceeding.

## 2. Create a new app record

1. In App Store Connect, open **Apps → + → New App**.
2. Choose iOS, select the new bundle ID `com.ossamamektane.routine`, and enter a unique SKU. A SKU is your own internal identifier and cannot be changed later.
3. Enter the app name and primary language. If the existing app record has reserved your desired name, follow App Store Connect’s prompts; do not delete the old record without checking the consequences.
4. Add the product information and privacy details to this new record.

## 3. Upload the project to GitHub

1. Unzip the changed-files archive. On GitHub, open your Routine repository and choose **Add file → Upload files**.
2. Upload everything inside `Routine-changes`, preserving folders. Include the hidden `.github` folder (on Mac, press **Cmd + Shift + .** to show hidden files).
3. Commit to `main`. Verify `project.yml` and `.github/workflows/testflight.yml` contain the singular ID. Repository secrets remain in GitHub settings.

## 4. Test and upload

1. Run **Actions → Tests → Run workflow**. Check the results before releasing.
2. Run **Actions → TestFlight → Run workflow**. Use the same version as the new App Store Connect record, normally `1.0.0`.
3. Once Apple has processed it, open the **new** app record → **TestFlight**, add yourself as an internal tester, and install the build. It is a separate installation from the old app.
4. Check language, tasks, reminders, iCloud and bill totals on your iPhone. Add sample data; no automatic import from the plural-ID app is promised.

The workflow uses the existing GitHub secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, and `APPLE_TEAM_ID`. The Apple key must have appropriate access for signing and uploading. If a workflow fails, open the failed step and share its error log without sharing secrets.

## 5. Submit

See [APP-STORE-STEPS.md](APP-STORE-STEPS.md). Keep the old record until you have confirmed the new build and listing are correct.
