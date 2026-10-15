# Android builds on GitHub Actions

The **Android APKs** workflow runs on pushes to `main` or `master`, version tags
matching `v*`, published GitHub Releases, or manually from
**Actions → Android APKs → Run workflow**. It uses Flutter 3.47.6 and Java 17,
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

For a versioned build, open the repository's **Releases** page and download the
appropriate APK directly from the release assets:

- `app-arm64-v8a-release.apk`: most current Android phones.
- `app-armeabi-v7a-release.apk`: older 32-bit ARM devices.
- `app-x86_64-release.apk`: x86 Android devices and emulators.

Branch builds are available as **nova-toll-android-apks** under a successful
workflow run's **Artifacts**. Extract that archive to find the APKs. These workflow
artifacts are retained for 30 days.

## Publish a release automatically

Update `pubspec.yaml` to the intended app version, commit the changes, then push a
matching version tag, for example:

```sh
git tag v1.0.0
git push origin v1.0.0
```

After analysis, tests, and APK signature verification pass, the workflow creates
the GitHub Release with generated notes and attaches all three APKs. If the release
already exists, it uploads the APKs there instead. Publishing a release through
GitHub's UI also triggers the build and attachment process. Rerunning a build for
the same tag replaces assets with matching filenames.

Manual runs targeting a `v*` tag also publish release assets; branch runs keep
their APKs as workflow artifacts. No extra token is required: the workflow uses
`GITHUB_TOKEN` with `contents: write`. The two signing secrets above must still be
configured. The workflow does not upload anything to the Play Store.

See the [Flutter action documentation](https://github.com/subosito/flutter-action)
and [GitHub artifact documentation](https://github.com/actions/upload-artifact)
for the underlying setup and download behavior.
