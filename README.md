# Watch Lens

A cross-platform Flutter app, initially targeting Android.

GitHub Actions builds a release APK on every push to `main` and on manual dispatch. Download the `watch-lens-release-apk` artifact from the workflow run.

## Project layout
- `lib/models/` — domain models
- `lib/services/` — platform and API services
- `lib/database/` — local persistence
- `lib/providers/` — app state
- `lib/screens/` — UI screens

This is a compiling scaffold; feature implementation will be added incrementally.
