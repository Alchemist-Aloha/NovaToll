# Android builds on GitHub Actions

The **Android APKs** workflow runs on pushes to `main` or `master`, or manually
from **Actions → Android APKs → Run workflow**. It uses Flutter 3.47.6 and Java 17,
runs analysis and tests, and builds signed release APKs for ARM64, ARMv7, and
x86_64 with `flutter build apk --release --split-per-abi`.

## Configure signing once

Create these repository secrets under **Settings → Secrets and variables →
Actions**:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64 encoding of the existing `novatoll.jks` keystore |
| `ANDROID_KEY_PROPERTIES_BASE64` | Base64 encoding of the local `android/key.properties` signing configuration |

With GitHub CLI authenticated, run the following from the repository root.
Replace `OWNER/REPOSITORY` with the destination GitHub repository:

```sh
base64 -w0 "$HOME/flutter_keys/novatoll.jks" | gh secret set ANDROID_KEYSTORE_BASE64 --repo OWNER/REPOSITORY
base64 -w0 android/key.properties | gh secret set ANDROID_KEY_PROPERTIES_BASE64 --repo OWNER/REPOSITORY
```

These commands send values directly to GitHub without printing passwords or key
material. Base64 is encoding, not encryption; keep encoded values private too.
The workflow restores the key into the runner's temporary directory and overrides
the local `storeFile` path. Missing signing secrets fail the build; release builds
never fall back to debug signing. Signing files are removed at the end of the job.

## Download an APK

Open a successful workflow run and download **nova-toll-android-apks** under
**Artifacts**. Extract the archive and install the appropriate APK:

- `app-arm64-v8a-release.apk`: most current Android phones.
- `app-armeabi-v7a-release.apk`: older 32-bit ARM devices.
- `app-x86_64-release.apk`: x86 Android devices and emulators.

Artifacts are retained for 30 days. The workflow does not publish a GitHub Release
or upload anything to the Play Store.

See the [Flutter action documentation](https://github.com/subosito/flutter-action)
and [GitHub artifact documentation](https://github.com/actions/upload-artifact)
for the underlying setup and download behavior.
