// Native Flutter raster previews, not physical-device screenshots.
// Run explicitly: flutter test tool/render_mobile_previews_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_toll/app.dart';
import 'package:nova_toll/pricing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PreviewPricing extends PricingService {
  @override
  Future<void> load() async {
    if (ramps.isEmpty) {
      await super.load();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    for (final entry in {'DM': 'body.ttf', 'Manrope': 'display.ttf'}.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(rootBundle.load('assets/${entry.value}'));
      await loader.load();
    }
  });
  final scenarios = [
    (
      name: 'map-light',
      size: const Size(390, 844),
      theme: ThemeMode.light,
      scale: 1.0,
      route: false,
    ),
    (
      name: 'map-dark',
      size: const Size(390, 844),
      theme: ThemeMode.dark,
      scale: 1.0,
      route: false,
    ),
    (
      name: 'route-light',
      size: const Size(390, 844),
      theme: ThemeMode.light,
      scale: 1.0,
      route: true,
    ),
    (
      name: 'map-large-text',
      size: const Size(320, 740),
      theme: ThemeMode.light,
      scale: 1.5,
      route: false,
    ),
    (
      name: 'map-landscape',
      size: const Size(844, 390),
      theme: ThemeMode.light,
      scale: 1.0,
      route: false,
    ),
    (
      name: 'map-tablet',
      size: const Size(1024, 768),
      theme: ThemeMode.light,
      scale: 1.0,
      route: false,
    ),
  ];
  for (final scenario in scenarios) {
    testWidgets('render ${scenario.name}', (tester) async {
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = previousShadows);
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      rootBundle.clear();
      tester.view.physicalSize = scenario.size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scenario.scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final service = _PreviewPricing();
      await tester.runAsync(() async {
        await service.load();
        await SharedPreferences.getInstance();
      });
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: NovaTollApp(themeMode: scenario.theme, service: service),
        ),
      );
      await tester.runAsync(() async {
        await precacheImage(
          const AssetImage('assets/map.png'),
          tester.element(find.byType(Scaffold)),
        );
      });
      await tester.pumpAndSettle();
      if (scenario.route) {
        await tester.tap(find.byKey(const ValueKey('tab-1')));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1.5);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final file = File('output/mobile-preview/${scenario.name}.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes.buffer.asUint8List());
        image.dispose();
      });
      debugDisableShadows = previousShadows;
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
