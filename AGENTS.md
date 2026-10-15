# Repository Guidelines

## Project Structure & Module Organization

This Flutter application targets Android. `lib/main.dart` initializes the app; `lib/app.dart` defines themes. `lib/planner_controller.dart` owns route selection, asynchronous requests, saved trips, GPS, and refresh lifecycle. Keep operator adapters in `lib/pricing.dart`, screens in `lib/screens/`, and reusable UI in `lib/widgets/`.

`assets/` contains bundled maps, catalogs, and fonts. `test/` holds automated tests; `tool/` holds opt-in network probes and preview generators. `docs/` records coverage and operator investigations. Preserve `reference/nova-toll/` as the original website snapshot. Android configuration lives in `android/`; Linux and web runners support development previews.

## Build, Test, and Development Commands

Use Flutter 3.47 with Dart satisfying `pubspec.yaml` (`^3.13.5`) and an Android SDK.

- `flutter pub get`: install dependencies.
- `flutter run -d <android-device-id>`: launch locally.
- `dart format lib test tool`: format Dart sources.
- `flutter analyze`: run static analysis and configured Flutter lints.
- `flutter test`: run the default test suite.
- `flutter test test/pricing_test.dart`: run focused pricing tests.
- `flutter build apk --release --split-per-abi`: produce three ABI-specific APKs in `build/app/outputs/flutter-apk/`.

## Coding Style & Naming Conventions

Follow `dart format`, two-space indentation, and `flutter_lints` from `analysis_options.yaml`. Use `snake_case.dart` filenames, `UpperCamelCase` types, `lowerCamelCase` members, and leading underscores for private declarations. Reuse the existing controller, service, and widget boundaries rather than introducing parallel state owners.

## Testing Guidelines

Use `flutter_test`, descriptive behavior-based test names, and `*_test.dart` files. Add focused regression tests for pricing, stale asynchronous responses, persistence, or gestures when those behaviors change. Use fixture HTTP clients for deterministic tests. No numeric coverage threshold is configured.

Run `flutter test tool/live_i66_probe_test.dart` explicitly for live operator checks. Run `flutter test tool/render_mobile_previews_test.dart` for layout previews in `output/mobile-preview/`; these do not replace physical-device checks.

## Commit & Pull Request Guidelines

Git history is unavailable in this checkout, so no existing commit convention can be verified. Use concise imperative subjects and keep changes focused. Pull requests should explain behavior changes, link relevant issues, report validation, and include screenshots for visible UI changes.

## Security & Configuration

Never treat missing toll components as free travel or transmit GPS coordinates to toll services. Release APKs use the private keystore at `/home/likun/flutter_keys/novatoll.jks`, configured through the ignored `android/key.properties` file with alias `upload`. Keep that file, its passwords, and the keystore out of version control; back them up securely. Release builds must use this private signing configuration.
