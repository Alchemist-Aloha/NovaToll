import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nova_toll/planner_controller.dart';
import 'package:nova_toll/pricing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CrossFixtureClient extends http.BaseClient {
  _CrossFixtureClient({
    this.failExpress = false,
    this.failOutside = false,
    this.failInside = false,
  });

  final bool failExpress;
  final bool failOutside;
  final bool failInside;
  final requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final copy = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    if (request is http.Request) copy.body = request.body;
    requests.add(copy);

    if (request.url.host == 'expresslanes.com') {
      if (failExpress) return _response('unavailable', 503, request);
      final catalog = (jsonDecode(
        await rootBundle.loadString('assets/catalog.json'),
      ) as Map).cast<String, dynamic>();
      final ods = <String>{};
      for (final direction in catalog.values.whereType<Json>()) {
        final entries = direction['entries'];
        if (entries is Map) {
          for (final entry in entries.values.whereType<Json>()) {
            for (final exit in (entry['exits'] as List? ?? const [])) {
              if (exit is Json) {
                ods.addAll(
                  (exit['ods'] as List? ?? const []).map((value) => '$value'),
                );
              }
            }
          }
        }
      }
      return _response(
        jsonEncode({
          'error': '0',
          'response': [
            for (final od in ods)
              {'od': 'od_$od', 'price': '1.00', 'status': 'open'},
          ],
        }),
        200,
        request,
      );
    }

    if (request.url.host == 'vai66tolls.com') {
      final handler = request.url.queryParameters['handler'];
      if (handler != 'TollCalcPartial') {
        final east = request.url.queryParameters['rbEastVal'] == 'true';
        final fixture =
            (jsonDecode(
                  await File('test/fixtures/i66_catalog.json').readAsString(),
                ) as Json)['directions']
                as Json;
        final catalog = fixture[east ? 'Eastbound' : 'Westbound'] as Json;
        final options = handler == 'ExitIntPartial'
            ? (catalog['exits'] as Json)[request.url.queryParameters['bIntId']]
            : catalog['entries'];
        return _response(
          [
            for (final option in options as List? ?? [])
              '<option value="${(option as Json)['id']}">${option['label']}</option>',
          ].join(),
          200,
          request,
        );
      }
      if (failInside) return _response('unavailable', 503, request);
      return _response('{"decToll":1}', 200, request);
    }

    if (request.method == 'POST' && request.url.host == 'ride66express.com') {
      if (failOutside) return _response('forbidden', 403, request);
      final ids =
          RegExp(
                r'(?:starting|ending|middle_ending|first_ending)_gantry_id\]=?([0-9]+)',
              )
              .allMatches(Uri.decodeComponent(copy.body))
              .map((m) => m.group(1)!)
              .toSet();
      return _response(
        jsonEncode({
          'success': true,
          'data': {
            'curl_response': jsonEncode({
              'rates': [
                for (final id in ids.isEmpty ? {'400'} : ids)
                  {
                    'rateEndDate': '2099-01-01T00:00:00Z',
                    'gantry': {
                      'gantryId': id,
                      'vehicleClasses': [
                        {'rateAmountTag': '1.00'},
                      ],
                    },
                  },
              ],
            }),
          },
        }),
        200,
        request,
      );
    }
    return _response('not found', 404, request);
  }

  http.StreamedResponse _response(
    String body,
    int status,
    http.BaseRequest request,
  ) => http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    status,
    request: request,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'every bundled express entry and exit is directed and quoteable',
    () async {
      final client = _CrossFixtureClient();
      final service = PricingService(client: client);
      await service.load();
      final catalog = (jsonDecode(
        await rootBundle.loadString('assets/catalog.json'),
      ) as Map).cast<String, dynamic>();

      for (final direction in const ['Northbound', 'Southbound']) {
        final directionData = catalog[direction] as Json;
        final entries = directionData['entries'] as Json;
        for (final item in entries.entries) {
          final itemData = item.value as Json;
          final road = RegExp(r'^\d+')
              .firstMatch('${itemData['path']}')!
              .group(0)!;
          final exits = await service.exits(road, direction, item.key);
          expect(exits, isNotEmpty, reason: '$direction $road ${item.key}');
          for (final exit in exits.where((e) => !'${e['id']}'.contains(':'))) {
            final quote = await service.quote({
              'road': road,
              'dir': direction,
              'entry': item.key,
              'exit': exit['id'],
            });
            expect(
              quote['error'],
              isNull,
              reason: '$direction $road ${item.key} → ${exit['id']}',
            );
            expect(
              quote['price'],
              closeTo((exit['ods'] as List).length.toDouble(), .001),
            );
          }
        }
      }
    },
  );

  test(
    'every generated cross-highway route quotes all required components',
    () async {
      final service = PricingService(client: _CrossFixtureClient());
      await service.load();
      final express =
          jsonDecode(await rootBundle.loadString('assets/catalog.json')) as Map;
      final outside = (jsonDecode(
        await rootBundle.loadString('assets/outside66.json'),
      ) as Map).cast<String, dynamic>();
      double segmentPrice(Json segment) {
        if (segment['road'] == '66') return 1;
        if (segment['road'] == '66outside') {
          final entry = (outside[segment['dir']] as List)
              .cast<Json>()
              .singleWhere((e) => e['id'] == segment['entry']);
          final index = int.parse('${segment['exit']}'.split(':').last);
          final exit = (entry['exits'] as List<dynamic>).cast<Json>()[index];
          return <String>{
            '${entry['id']}',
            ...'${exit['gantries']}'.split(','),
          }.length.toDouble();
        }
        final direction = express[segment['dir']] as Json;
        final entry = (direction['entries'] as Json)[segment['entry']] as Json;
        final exit = (entry['exits'] as List).cast<Json>().singleWhere(
          (e) => e['id'] == segment['exit'],
        );
        return (exit['ods'] as List).length.toDouble();
      }

      var checked = 0;
      for (final road in ['495', '95', '395', '66', '66outside']) {
        final directions = road.startsWith('66')
            ? ['Eastbound', 'Westbound']
            : ['Northbound', 'Southbound'];
        for (final direction in directions) {
          for (final entry in await service.entries(road, direction)) {
            final exits = await service.exits(
              road,
              direction,
              '${entry['id']}',
            );
            for (final exit in exits.where((e) => '${e['id']}'.contains(':'))) {
              final trip = <String, dynamic>{
                'road': road,
                'dir': direction,
                'entry': entry['id'],
                'exit': exit['id'],
              };
              final quote = await service.quote(trip);
              expect(quote['error'], isNull, reason: '$trip');
              double expected;
              if (exit['connection'] case final List<dynamic> connection) {
                expected = connection.cast<Json>().fold<double>(
                  0,
                  (sum, segment) => sum + segmentPrice(segment),
                );
              } else if ('${exit['id']}'.startsWith('o66:')) {
                expected = segmentPrice(trip);
              } else {
                final base = segmentPrice({...trip, 'exit': exit['via']});
                final id = '${exit['id']}';
                final added = id.startsWith('66e:')
                    ? 1
                    : id.startsWith('66g:')
                    ? 0
                    : id.endsWith(':50')
                    ? 1
                    : id.endsWith(':29g')
                    ? 4
                    : 2;
                expected = base + added;
              }
              expect(quote['price'], expected, reason: '$trip');
              checked++;
            }
          }
        }
      }
      expect(checked, 1364);
    },
  );

  test(
    'allowed cross-highway families preserve directed connection components',
    () async {
      final service = PricingService(client: _CrossFixtureClient());
      await service.load();
      final cases = <Map<String, String>>[
        {
          'road': '66outside',
          'dir': 'Eastbound',
          'entry': '401',
          'next': '66|Eastbound|1',
        },
        {
          'road': '66',
          'dir': 'Westbound',
          'entry': '16',
          'next': '66outside|Westbound|417',
        },
        {
          'road': '66outside',
          'dir': 'Eastbound',
          'entry': '401',
          'next': '495|Northbound|187NO',
        },
        {
          'road': '66outside',
          'dir': 'Eastbound',
          'entry': '401',
          'next': '495|Southbound|187SO',
        },
        {
          'road': '66',
          'dir': 'Westbound',
          'entry': '16',
          'next': '495|Southbound|187SO',
        },
      ];
      for (final c in cases) {
        final exits = await service.exits(c['road']!, c['dir']!, c['entry']!);
        final next = c['next']!.split('|');
        final route = exits.where((e) {
          final connection = e['connection'];
          if (connection is! List) return false;
          return connection.any(
            (segment) =>
                segment is Map &&
                segment['road'] == next[0] &&
                segment['dir'] == next[1] &&
                segment['entry'] == next[2],
          );
        }).firstOrNull;
        expect(
          route,
          isNotNull,
          reason: '${c['road']} ${c['dir']} ${c['entry']}',
        );
        expect(route!['connection'], isA<List<dynamic>>());
        final quote = await service.quote({
          'road': c['road'],
          'dir': c['dir'],
          'entry': c['entry'],
          'exit': route['id'],
        });
        expect(quote['error'], isNull, reason: '${route['id']}');
        expect(quote['price'], isA<num>());
      }
    },
  );

  test(
    'unsupported and forged cross-road exits never request component prices',
    () async {
      final client = _CrossFixtureClient();
      final service = PricingService(client: client);
      await service.load();
      for (final (road, direction) in [
        ('66', 'Eastbound'),
        ('66outside', 'Westbound'),
      ]) {
        for (final entry in await service.entries(road, direction)) {
          final exits = await service.exits(road, direction, '${entry['id']}');
          expect(exits.any((e) => '${e['id']}'.startsWith('via:')), isFalse);
        }
      }
      client.requests.clear();
      final quote = await service.quote({
        'road': '66outside',
        'dir': 'Westbound',
        'entry': '417',
        'exit': 'via:417|66|Eastbound|1|4',
      });
      expect(quote['error'], 'No verified connection');
      expect(quote['price'], isNull);
      expect(client.requests, isEmpty);
    },
  );

  test('I-395 southbound and I-495 southbound use distinct I-66 interchange directions', () async {
    final service = PricingService(client: _CrossFixtureClient());
    await service.load();

    final from395 = await service.exits('395', 'Southbound', '2232SO');
    final outside395 = from395.where((destination) {
      final connection = destination['connection'];
      return connection is List &&
          connection.any(
            (segment) =>
                segment is Map &&
                segment['road'] == '66outside' &&
                segment['entry'] == '415',
          );
    }).toList();
    expect(outside395, isNotEmpty);
    expect(
      from395.any((destination) => '${destination['id']}'.startsWith('66e:')),
      isTrue,
    );

    final from495 = await service.exits('495', 'Southbound', '180SO');
    final outside495 = from495.where((destination) {
      final connection = destination['connection'];
      return connection is List &&
          connection.any(
            (segment) =>
                segment is Map &&
                segment['road'] == '66outside' &&
                segment['entry'] == '414',
          );
    }).toList();
    expect(outside495, isNotEmpty);
    expect(
      from495.any((destination) => '${destination['id']}'.startsWith('66e:')),
      isFalse,
    );
  });

  test('cross quote keeps a known subtotal when one operator fails', () async {
    final service = PricingService(
      client: _CrossFixtureClient(failOutside: true),
    );
    await service.load();
    final exits = await service.exits('66', 'Westbound', '16');
    final route = exits.firstWhere(
      (e) =>
          '${e['id']}'.startsWith('via:') &&
          '${e['id']}'.contains('66outside') &&
          (e['connection'] as List<dynamic>).cast<Json>().first['entry'] ==
              '16',
    );
    final quote = await service.quote({
      'road': '66',
      'dir': 'Westbound',
      'entry': '16',
      'exit': route['id'],
    });
    expect(quote['error'], 'Total incomplete');
    expect(quote['knownPrice'], isA<num>());
    expect(quote['price'], isNull);
  });

  test(
    'either failed provider preserves only the other known component',
    () async {
      for (final (client, road, direction, entry, target, known) in [
        (
          _CrossFixtureClient(failInside: true),
          '66outside',
          'Eastbound',
          '401',
          '|66|Eastbound|1|16',
          3,
        ),
        (
          _CrossFixtureClient(failOutside: true),
          '66outside',
          'Eastbound',
          '401',
          '|66|Eastbound|1|16',
          1,
        ),
        (
          _CrossFixtureClient(failExpress: true),
          '66outside',
          'Eastbound',
          '401',
          '|495|Northbound|187NO|181ND',
          3,
        ),
      ]) {
        final service = PricingService(client: client);
        final exits = await service.exits(road, direction, entry);
        final exit = exits.singleWhere((e) => '${e['id']}'.endsWith(target));
        final quote = await service.quote({
          'road': road,
          'dir': direction,
          'entry': entry,
          'exit': exit['id'],
        });
        expect(quote['error'], 'Total incomplete');
        expect(quote['price'], isNull);
        expect(quote['knownPrice'], known);
        expect(
          (quote['legs'] as List<dynamic>).cast<Json>().any(
            (e) => e['error'] != null,
          ),
          isTrue,
        );
      }
    },
  );

  test(
    'planner map selects and reloads both I-66 cross-provider directions',
    () async {
      for (final (road, direction, entryId, destinationRoad) in [
        ('66outside', 'Eastbound', '401', '66'),
        ('66', 'Westbound', '16', '66outside'),
      ]) {
        SharedPreferences.setMockInitialValues({});
        final service = PricingService(client: _CrossFixtureClient());
        final controller = PlannerController(service: service);
        await controller.initialize();
        final entry = service.ramps.singleWhere(
          (record) =>
              record['road'] == road &&
              record['direction'] == direction &&
              record['ramp'] == 'entry' &&
              record['id'] == entryId,
        );
        await controller.selectMap([
          entry,
        ], (_, options, _) async => options.first);
        final destination = controller.mapRecords.firstWhere(
          (record) =>
              record['road'] == destinationRoad &&
              record['ramp'] == 'exit' &&
              '${record['id']}'.startsWith('via:'),
        );
        await controller.selectMap([
          destination,
        ], (_, options, _) async => options.first);
        expect(controller.trip?['road'], road);
        expect(controller.trip?['entry'], entryId);
        expect(controller.trip?['exit'], destination['id']);
        await controller.saveTrip();
        expect(controller.saved, hasLength(1));
        controller.dispose();

        final restored = PlannerController(
          service: PricingService(client: _CrossFixtureClient()),
        );
        await restored.initialize();
        expect(restored.saved, hasLength(1));
        restored.applyTrip(restored.saved.single);
        restored.setChoosingEntry(false);
        for (
          var i = 0;
          i < 30 && (restored.mapRoutes.isEmpty || restored.pricingBusy);
          i++
        ) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(restored.trip?['exit'], destination['id']);
        expect(restored.quote?['error'], isNull);
        expect(restored.quote?['price'], isA<num>());
        expect(
          restored.mapRecords.any(
            (r) => r['id'] == destination['id'] && r['road'] == destinationRoad,
          ),
          isTrue,
        );
        restored.dispose();
      }
    },
  );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => length == 0 ? null : first;
}
