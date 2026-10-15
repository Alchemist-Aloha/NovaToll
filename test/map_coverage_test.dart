import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nova_toll/planner_controller.dart';
import 'package:nova_toll/pricing.dart';
import 'package:nova_toll/route_map.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PricingService service;
  late http.Client client;
  late Json locations;

  setUpAll(() async {
    client = MockClient((request) async {
      expect(request.url.host, 'ride66express.com');
      expect(request.headers['X-Requested-With'], 'XMLHttpRequest');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'curl_response': {
              'rates': [
                for (var id = 400; id <= 425; id++)
                  {
                    'rateEndDate': '2026-10-15T06:00:00Z',
                    'gantry': {
                      'gantryId': id,
                      'vehicleClasses': [
                        {'rateAmountTag': 1.25},
                      ],
                    },
                  },
              ],
            },
          },
        }),
        200,
      );
    });
    service = PricingService(client: client);
    await service.load();
    locations = Map<String, dynamic>.from(
      jsonDecode(
        await rootBundle.loadString('assets/outside66_map.json'),
      )['locations'],
    );
  });
  tearDownAll(() {
    service.dispose();
    client.close();
  });

  test(
    'all bundled Express Lanes entries and exits have matching map records',
    () async {
      final catalog =
          jsonDecode(await rootBundle.loadString('assets/catalog.json')) as Map;
      for (final direction in catalog.keys) {
        final data = catalog[direction] as Map;
        for (final kind in {'entries': 'entry', 'exits': 'exit'}.entries) {
          for (final record in (data[kind.key] as Map).values.cast<Map>()) {
            final road = [
              '495',
              '395',
              '95',
            ].firstWhere((road) => '${record['path']}'.startsWith(road));
            final matches = service.ramps.where(
              (r) =>
                  r['road'] == road &&
                  r['direction'] == direction &&
                  r['ramp'] == kind.value &&
                  r['id'] == record['id'],
            );
            expect(
              matches,
              hasLength(1),
              reason: '$road $direction ${kind.value} ${record['id']}',
            );
            expect(double.tryParse('${matches.single['latitude']}'), isNotNull);
            expect(
              double.tryParse('${matches.single['longitude']}'),
              isNotNull,
            );
          }
        }
      }
    },
  );

  test(
    'every outside map entry and exit selects and quotes its exact route',
    () async {
      final entries = service.ramps
          .where((r) => r['road'] == '66outside' && r['ramp'] == 'entry')
          .toList();
      expect(entries, hasLength(22));
      var checkedExits = 0;
      for (final entry in entries) {
        final controller = PlannerController(service: service);
        Future<Json?> choose(
          String _,
          List<Json> _,
          String Function(Json) _,
        ) async =>
            fail('An exact route should not require an ambiguous choice');
        await controller.selectMap([entry], choose);
        final exits = await service.exits(
          '66outside',
          entry['direction'],
          entry['id'],
        );
        expect(controller.mapRoutes.single['entry'], entry['id']);
        expect(
          controller.mapRecords.where((r) => r['road'] == '66outside'),
          hasLength(194),
        );
        for (final exit in exits.where(
          (e) => '${e['id']}'.startsWith('o66:'),
        )) {
          final record = controller.mapRecords.singleWhere(
            (r) => r['road'] == '66outside' && r['id'] == exit['id'],
          );
          expect(record['mapKey'], startsWith('66outside:'));
          controller.setChoosingEntry(false);
          await controller.selectMap([record], choose);
          await Future<void>.delayed(Duration.zero);
          expect(controller.trip?['road'], '66outside');
          expect(controller.trip?['entry'], entry['id']);
          expect(controller.trip?['exit'], exit['id']);
          final gantries = {entry['id'], ...'${exit['gantries']}'.split(',')};
          expect(
            controller.quote?['price'],
            closeTo(gantries.length * 1.25, .001),
          );
          expect(controller.quote?['error'], isNull);
          checkedExits++;
        }
        controller.dispose();
      }
      expect(checkedExits, 172);
    },
  );

  test(
    'shared Beltway marker offers the actual outside entry variant',
    () async {
      final controller = PlannerController(service: service);
      final records = service.ramps
          .where((r) => r['mapKey'] == '66outside:beltway')
          .toList();
      await controller.selectMap(records, (title, options, label) async {
        expect(title, 'Choose your entry ramp');
        final chosen = options.singleWhere((r) => r['id'] == '415');
        expect(label(chosen), contains('I-495 NB EL'));
        return chosen;
      });
      expect(controller.mapRoutes.single['entry'], '415');
      expect(controller.mapRoutes.single['dir'], 'Westbound');
      expect(controller.mapOriginLabel, 'I-495 NB EL');
      controller.dispose();
    },
  );

  testWidgets(
    'all outside physical locations render on the western map corridor',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      List<Json>? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RouteMap(
              ramps: service.ramps,
              onChoose: (value) => chosen = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final matrix = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value;
      for (final entry in locations.entries) {
        final marker = find.byKey(
          ValueKey('ramp-marker:66outside:${entry.key}'),
        );
        expect(marker, findsOneWidget, reason: entry.key);
        final position = MatrixUtils.transformPoint(
          matrix,
          Offset(
            (entry.value['x'] as num).toDouble(),
            (entry.value['y'] as num).toDouble(),
          ),
        );
        expect(tester.getCenter(marker).dx, closeTo(position.dx, .01));
        expect(tester.getCenter(marker).dy, closeTo(position.dy, .01));
      }
      await tester.tap(find.byTooltip('Search ramps'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'University Boulevard');
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('I-66 outside Beltway · University Boulevard'),
      );
      await tester.pumpAndSettle();
      expect(
        chosen!.any((r) => r['id'] == '402' && r['ramp'] == 'entry'),
        isTrue,
      );
      expect(
        chosen!.any(
          (r) => r['ramp'] == 'exit' && '${r['id']}'.startsWith('o66:'),
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
