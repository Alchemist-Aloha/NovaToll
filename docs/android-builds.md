# Android builds on GitHub Actions

The **Android APKs** workflow runs on pushes to `main` or `master`, version tags
matching `v*`, published GitHub Releases, or manually from
**Actions → Android APKs → Run workflow**. It uses Flutter 3.47.6 and Java 17,
runs analysis and tests, and builds signed release APKs for ARM64, ARMv7, and
x86_64 with `flutter build apk --release --split-per-abi`.

## Download an APK

For a versioned build, open the repository's **Releases** page and download the
appropriate APK directly from the releaseF assets:

- `app-arm64-v8a-release.apk`: most current Android phones.
- `app-armeabi-v7a-release.apk`: older 32-bit ARM devices.
- `app-x86_64-release.apk`: x86 Android devices and emulators.

Branch builds are available as **nova-toll-android-apks** under a successful
workflow run's **Artifacts**. Extract that archive to find the APKs. These workflow
artifacts are retained for 30 days.
