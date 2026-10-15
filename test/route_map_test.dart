import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_toll/route_map.dart';

void main() {
  final ramps = <Map<String, dynamic>>[
    {
      'id': '183NO',
      'label': 'Jones Branch Drive/Route 123',
      'latitude': '38.9275663',
      'longitude': '-77.2125236',
      'road': '495',
      'direction': 'Northbound',
      'ramp': 'entry',
    },
    {
      'id': '183SO',
      'label': 'Jones Branch Drive/Route 123',
      'latitude': '38.9275663',
      'longitude': '-77.2125236',
      'road': '495',
      'direction': 'Southbound',
      'ramp': 'exit',
    },
  ];

  testWidgets('entry selection shows only reachable exits and the origin', (
    tester,
  ) async {
    final records = <Map<String, dynamic>>[
      for (final ramp in [
        ('origin', 'entry', 'Origin'),
        ('reachable', 'exit', 'Reachable exit'),
        ('blocked', 'exit', 'Unreachable exit'),
        ('reachable', 'entry', 'Other entry'),
      ])
        {
          'id': ramp.$1,
          'ramp': ramp.$2,
          'label': ramp.$3,
          'road': '495',
          'mapX': 500,
          'mapY': 400,
        },
    ];
    Future<void> showMap({String? entry, Set<String>? exits}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RouteMap(
              ramps: records,
              entryId: entry,
              reachableIds: exits,
              onChoose: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder dot(String name) => find.byKey(ValueKey('ramp-marker:495:$name'));
    await showMap();
    expect(
      find.byKey(const ValueKey('ramp-marker:495:Other entry')),
      findsOneWidget,
    );
    expect(dot('Unreachable exit'), findsOneWidget);

    await showMap(entry: 'origin', exits: {'reachable'});
    expect(dot('Origin'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(dot('Reachable exit'), findsOneWidget);
    expect(dot('Unreachable exit'), findsNothing);
    expect(dot('Other entry'), findsNothing);

    await showMap(entry: 'origin', exits: {});
    expect(dot('Origin'), findsOneWidget);
    expect(dot('Reachable exit'), findsNothing);
    expect(dot('Unreachable exit'), findsNothing);
    expect(dot('Other entry'), findsNothing);

    await showMap();
    expect(dot('Other entry'), findsOneWidget);
    expect(dot('Reachable exit'), findsOneWidget);
    expect(dot('Unreachable exit'), findsOneWidget);
  });

  testWidgets('search selects the complete grouped ramp records', (
    tester,
  ) async {
    List<Map<String, dynamic>>? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RouteMap(ramps: ramps, onChoose: (value) => selected = value),
        ),
      ),
    );
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('Search ramps'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Jones Branch');
    await tester.pump();
    await tester.tap(find.text('I-495 · Jones Branch Drive/Route 123').last);
    await tester.pump();
    expect(selected, hasLength(2));
    expect(
      selected!.map((record) => record['id']),
      containsAll(<String>['183NO', '183SO']),
    );
  });

  testWidgets('zoom controls work at a phone-sized viewport', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RouteMap(ramps: ramps, onChoose: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.tap(find.byTooltip('Full map'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'two-finger pinch increases the map scale without selecting a ramp',
    (tester) async {
      var selected = 0;
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RouteMap(ramps: ramps, onChoose: (_) => selected++),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewer = find.byType(InteractiveViewer);
      final interactive = tester.widget<InteractiveViewer>(viewer);
      final before = interactive.transformationController!.value
          .getMaxScaleOnAxis();
      final first = await tester.startGesture(
        const Offset(145, 420),
        pointer: 1,
      );
      final second = await tester.startGesture(
        const Offset(245, 420),
        pointer: 2,
      );
      await tester.pump();
      await first.moveBy(const Offset(-45, 0));
      await second.moveBy(const Offset(45, 0));
      await tester.pumpAndSettle();
      final after = interactive.transformationController!.value
          .getMaxScaleOnAxis();
      expect(after, greaterThan(before));
      expect(selected, 0);
      await first.up();
      await second.up();
    },
  );

  testWidgets('search opens only from its button without resizing the map', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RouteMap(ramps: ramps, onChoose: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(InteractiveViewer)),
      const Size(390, 844),
    );
    expect(find.byType(TextField), findsNothing);
    final searchTop = tester.getTopLeft(find.byTooltip('Search ramps')).dy;
    expect(
      searchTop,
      lessThan(tester.getTopLeft(find.byTooltip('Zoom in')).dy),
    );
    await tester.tap(find.byTooltip('Search ramps'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Jones');
    await tester.pump();
    expect(
      tester.getSize(find.byType(InteractiveViewer)),
      const Size(390, 844),
    );
    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('panning the map does not select a ramp', (tester) async {
    var selected = 0;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RouteMap(ramps: ramps, onChoose: (_) => selected++),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(const Offset(190, 420));
    await gesture.moveBy(const Offset(80, 40));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(selected, 0);
  });

  testWidgets('zoom out never goes below the fitted map scale', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RouteMap(ramps: ramps, onChoose: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    final fitted = controller.value.getMaxScaleOnAxis();
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.byTooltip('Zoom out'));
    }
    await tester.pumpAndSettle();
    expect(controller.value.getMaxScaleOnAxis(), closeTo(fitted, 0.0001));
  });
  testWidgets('larger markers accept taps outside the visible dot', (
    tester,
  ) async {
    List<Map<String, dynamic>>? selected;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RouteMap(ramps: ramps, onChoose: (value) => selected = value),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scale = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!
        .value
        .getMaxScaleOnAxis();
    final marker = find.byKey(
      const ValueKey('ramp-marker:495:Jones Branch Drive/Route 123'),
    );
    final hit = find.byKey(
      const ValueKey('ramp-hit:495:Jones Branch Drive/Route 123'),
    );
    expect(tester.getSize(marker).width * scale, closeTo(20, .01));
    expect(tester.getSize(hit).width * scale, closeTo(56, .01));
    await tester.tapAt(tester.getCenter(marker) + const Offset(24, 0));
    await tester.pumpAndSettle();
    expect(selected, hasLength(2));
  });

  testWidgets('selected entry and exit markers stay large when zooming', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RouteMap(ramps: ramps, entryId: '183NO', onChoose: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    final marker = find.byKey(
      const ValueKey('ramp-marker:495:Jones Branch Drive/Route 123'),
    );
    expect(
      tester.getSize(marker).width * controller.value.getMaxScaleOnAxis(),
      closeTo(34, .01),
    );
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(marker).width * controller.value.getMaxScaleOnAxis(),
      closeTo(34, .01),
    );
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('pinch zoom out stops at the centered full map', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RouteMap(ramps: ramps, onChoose: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    final fit = controller.value.clone();
    final first = await tester.startGesture(const Offset(80, 420), pointer: 1);
    final second = await tester.startGesture(
      const Offset(310, 420),
      pointer: 2,
    );
    await tester.pump();
    await first.moveTo(const Offset(180, 420));
    await second.moveTo(const Offset(210, 420));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(
      controller.value.getMaxScaleOnAxis(),
      closeTo(fit.getMaxScaleOnAxis(), .0001),
    );
    expect(controller.value.storage[12], closeTo(fit.storage[12], .01));
    expect(controller.value.storage[13], closeTo(fit.storage[13], .01));
  });
}
