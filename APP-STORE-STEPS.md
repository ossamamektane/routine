# App Store steps for Routine

This project uses **com.ossamamektane.routine** (singular), a separate app record from the previous plural-ID app. First follow [START-HERE.md](START-HERE.md), install the new TestFlight build and test it.

## App Information

- Name: `Routine: Tasks & Bills`
- Subtitle: `Plan your day, stay on track`
- Primary category: Productivity; optional secondary category: Lifestyle.
- Fill in the age rating and content rights truthfully for the build you submit.

## Privacy and compliance

- Publish the privacy policy in `docs/privacy.html` and enter its working public URL.
- The project has no analytics or advertising SDKs. Review the build and your services before answering the App Privacy questions; update your answers if your practices change.
- For China mainland, answer the security assessment and AIGC declarations based on the features actually offered there.

## App Store version

1. Use a version matching your TestFlight workflow, normally `1.0.0` for a new record.
2. Add screenshots from the actual app and, optionally, an app preview video.
3. Add your description, promotional text and keywords. Review the text for accuracy against the build.
4. Publish the support page from `docs/index.html` and add its working URL. The Marketing URL is optional.
5. Select the new TestFlight build for the singular bundle ID.
6. Under App Review Information, leave **Sign-in required** unchecked. Add your own contact name, email and telephone number.
7. Choose a release option, save, and submit for review.

## Notes for App Review

```text
Routine is a personal planner for tasks, routines and bills. No account or sign-in is required.

To try the app:
1. Tap Continue on the welcome screen.
2. Use the + button to add a task or bill and choose its schedule.
3. Check off a task on Today or view bills in the Bills tab.

Reminders are optional and use local notifications. Data is stored on the device and can sync through the user’s iCloud account.
```

## Publish the support and privacy pages

If the repository is public, open GitHub **Settings → Pages**, choose **Deploy from a branch**, branch `main`, folder `/docs`, then save. After deployment, open both the support page and `privacy.html` in a browser to verify them before submitting. Publishing a different folder can show the developer README instead of the support page.
