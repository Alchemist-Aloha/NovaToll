import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_toll/main.dart';
import 'package:nova_toll/planner_controller.dart';
import 'package:nova_toll/pricing.dart';
import 'package:nova_toll/route_map.dart';
import 'package:nova_toll/widgets/trip_estimate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;

class FakePricing extends PricingService {
  @override
  Future<void> load() async {
    ramps = [
      {
        'id': 'a',
        'label': 'Route 267',
        'road': '495',
        'direction': 'Northbound',
        'ramp': 'entry',
        'latitude': 38.931,
        'longitude': -77.21,
      },
      {
        'id': 'b',
        'label': 'Westpark Drive',
        'road': '495',
        'direction': 'Northbound',
        'ramp': 'exit',
        'latitude': 38.9193,
        'longitude': -77.216,
      },
    ];
  }

  @override
  Future<List<Json>> entries(String road, String dir) async => [
    {'id': 'a', 'label': 'Route 267'},
  ];

  @override
  Future<List<Json>> exits(String road, String dir, String entry) async => [
    {'id': 'b', 'label': 'Westpark Drive'},
  ];

  @override
  Future<Json> quote(Json trip) async => {
    'price': 4.25,
    'legs': [
      {'road': 'I-495', 'price': 4.25},
    ],
    'fetchedAt': '2026-10-15T13:00:00Z',
    'source': 'Test operator',
  };
}

void main() {
  setUpAll(tzdata.initializeTimeZones);

  Future<void> start(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      NovaTollApp(service: FakePricing(), themeMode: themeMode),
    );
    await tester.pumpAndSettle();
  }

  Future<void> chooseManualRoute(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose your entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Route 267'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose your destination'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Westpark Drive'));
    await tester.pumpAndSettle();
  }

  Future<void> showEstimate(
    WidgetTester tester, {
    required Json trip,
    Json? quote,
  }) async {
    final controller = PlannerController(service: FakePricing())
      ..trip = trip
      ..quote = quote;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TripEstimate(controller: controller, onEdit: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('manual route calculates on map, saves, reloads, and deletes', (
    tester,
  ) async {
    await start(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    await chooseManualRoute(tester);
    await tester.tap(find.text('Calculate this trip'));
    await tester.pumpAndSettle();
    expect(find.text('Trip estimate'), findsOneWidget);
    expect(find.byKey(const ValueKey('estimate-amount')), findsOneWidget);
    expect(find.text('\$4.25'), findsWidgets);
    expect(find.text('Official toll check websites'), findsOneWidget);
    expect(find.text('I-495 / I-95 / I-395 Express Lanes'), findsOneWidget);

    final expand = find.byTooltip('Expand trip details');
    if (expand.evaluate().isNotEmpty) {
      await tester.tap(expand);
      await tester.pumpAndSettle();
    }
    final sheetList = find.descendant(
      of: find.byKey(const ValueKey('trip-sheet')),
      matching: find.byType(ListView),
    );
    expect(sheetList, findsOneWidget);
    final sheetScroll = find.descendant(
      of: sheetList,
      matching: find.byType(Scrollable),
    );
    final saveButton = find.ancestor(
      of: find.text('Save this trip'),
      matching: find.byType(FilledButton),
    );
    await tester.scrollUntilVisible(saveButton, 300, scrollable: sheetScroll);
    await tester.drag(sheetList, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('nova-toll-trips'), contains('Route 267'));

    await tester.tap(find.byKey(const ValueKey('tab-2')));
    await tester.pumpAndSettle();
    expect(find.text('Saved trips'), findsWidgets);
    expect(find.text('Route 267 → Westpark Drive'), findsOneWidget);
    await tester.tap(find.text('Route 267 → Westpark Drive'));
    await tester.pumpAndSettle();
    expect(find.text('Trip estimate'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tab-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete saved trip'));
    await tester.pumpAndSettle();
    expect(find.text('No saved trips yet'), findsOneWidget);
    expect(prefs.getString('nova-toll-trips'), '[]');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'cross-highway estimate shows both operator websites before quote',
    (tester) async {
      await showEstimate(
        tester,
        trip: {
          'road': '495',
          'entry': 'a',
          'exit': '66e:3',
          'dir': 'Northbound',
        },
      );
      expect(find.text('I-495 / I-95 / I-395 Express Lanes'), findsOneWidget);
      expect(find.text('I-66 inside Beltway · VDOT'), findsOneWidget);
    },
  );

  testWidgets('partial cross-highway quote shows all involved operators', (
    tester,
  ) async {
    await showEstimate(
      tester,
      trip: {'road': '495', 'entry': 'a', 'exit': 'via:unused'},
      quote: {
        'error': 'Total incomplete',
        'roads': ['495', '66outside'],
        'legs': [
          {'road': 'I-495', 'price': 3},
          {'road': 'I-66 west express', 'error': 'Unavailable'},
        ],
      },
    );
    expect(find.text('I-495 / I-95 / I-395 Express Lanes'), findsOneWidget);
    expect(find.text('I-66 outside Beltway · Ride66Express'), findsOneWidget);
  });

  testWidgets('operator links are deduplicated across route roads', (
    tester,
  ) async {
    await showEstimate(
      tester,
      trip: {'road': '495', 'entry': 'a', 'exit': '66e:3'},
      quote: {
        'roads': ['495', '95', '395', '66', '66outside'],
        'legs': const <Json>[],
      },
    );
    expect(find.text('Official toll check websites'), findsOneWidget);
    expect(find.text('I-495 / I-95 / I-395 Express Lanes'), findsOneWidget);
    expect(find.text('I-66 inside Beltway · VDOT'), findsOneWidget);
    expect(find.text('I-66 outside Beltway · Ride66Express'), findsOneWidget);
  });

  testWidgets('map fills phone viewport and preserves zoom across navigation', (
    tester,
  ) async {
    await start(tester);
    expect(
      tester.getSize(find.byKey(const ValueKey('planning-map'))),
      const Size(390, 708),
    );
    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    final zoomed = controller.value.getMaxScaleOnAxis();
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-0')));
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(zoomed, 0.0001));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('full map control is tablet-only', (tester) async {
    final ramps = [
      {
        'id': 'test-ramp',
        'label': 'Test ramp',
        'road': '495',
        'ramp': 'entry',
        'mapX': 500,
        'mapY': 400,
      },
    ];

    Future<void> show(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RouteMap(ramps: ramps, onChoose: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await show(const Size(390, 844));
    expect(find.byTooltip('Full map'), findsNothing);
    await show(const Size(844, 390));
    expect(find.byTooltip('Full map'), findsNothing);
    await show(const Size(1024, 768));
    expect(find.byTooltip('Full map'), findsOneWidget);
  });

  testWidgets(
    'two-finger pinch changes map transform without selecting or moving sheet',
    (tester) async {
      await start(tester);
      final controller = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      final beforeScale = controller.value.getMaxScaleOnAxis();
      final sheet = find.byKey(const ValueKey('trip-sheet'));
      final sheetController = tester
          .widget<DraggableScrollableSheet>(sheet)
          .controller!;
      final beforeSheetExtent = sheetController.size;
      final first = await tester.startGesture(
        const Offset(140, 300),
        pointer: 1,
      );
      final second = await tester.startGesture(
        const Offset(250, 300),
        pointer: 2,
      );
      await first.moveBy(const Offset(-40, 0));
      await second.moveBy(const Offset(40, 0));
      await tester.pumpAndSettle();
      await first.up();
      await second.up();
      expect(controller.value.getMaxScaleOnAxis(), greaterThan(beforeScale));
      expect(sheetController.size, closeTo(beforeSheetExtent, .001));
      expect(find.text('Choose your entry'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('narrow large text and dark mode remain usable', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await start(tester, size: const Size(320, 740), themeMode: ThemeMode.dark);
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );
    await tester.tap(find.byKey(const ValueKey('tab-1')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('landscape and tablet navigation have no layout exceptions', (
    tester,
  ) async {
    await start(tester, size: const Size(800, 400));
    expect(find.byType(Scaffold), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await start(tester, size: const Size(1024, 768));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.text('Route'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
