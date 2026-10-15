import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_toll/widgets/source_sheet.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');
  final launched = <MethodCall>[];
  var launchSucceeds = true;

  setUp(() {
    launched.clear();
    launchSucceeds = true;
    PackageInfo.setMockInitialValues(
      appName: 'Nova Toll',
      packageName: 'com.novatoll.nova_toll',
      version: '9.8.7',
      buildNumber: '42',
      buildSignature: '',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, (call) async {
          launched.add(call);
          return launchSucceeds;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, null);
  });

  Future<void> openPanel(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(showSources(context)),
              child: const Text('Open sources'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open sources'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shows installed version and opens both GitHub links externally',
    (tester) async {
      await openPanel(tester);
      expect(find.text('Sources & coverage'), findsOneWidget);
      expect(find.text('Version 9.8.7 (build 42)'), findsOneWidget);

      for (final link in const {
        'GitHub repository': 'https://github.com/Alchemist-Aloha/NovaToll',
        'GitHub releases':
            'https://github.com/Alchemist-Aloha/NovaToll/releases',
      }.entries) {
        await tester.ensureVisible(find.text(link.key));
        await tester.tap(find.text(link.key));
        await tester.pumpAndSettle();
        final call = launched.last;
        expect(call.method, 'launch');
        final arguments = call.arguments as Map<Object?, Object?>;
        expect(arguments['url'], link.value);
        expect(arguments['useWebView'], isFalse);
      }
      await tester.ensureVisible(
        find.text('I-66 outside Beltway · Ride66Express'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shows feedback when a GitHub link cannot be opened', (
    tester,
  ) async {
    launchSucceeds = false;
    await openPanel(tester);
    await tester.ensureVisible(find.text('GitHub releases'));
    await tester.tap(find.text('GitHub releases'));
    await tester.pumpAndSettle();
    expect(find.text('Could not open the link.'), findsOneWidget);
    expect(find.text('Sources & coverage'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
