import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nova_toll/pricing.dart';

class _FixtureClient extends http.BaseClient {
  _FixtureClient(this.handler);
  final http.Response Function(http.Request request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final fixtureRequest = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    if (request is http.Request) {
      fixtureRequest.body = request.body;
    }
    final response = handler(fixtureRequest);
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

PricingService _expressFixture(Object response) => PricingService(
  client: _FixtureClient((request) => http.Response(jsonEncode(response), 200)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads the complete outside-Beltway map inventory', () async {
    final service = _expressFixture({'error': '0'});
    await service.load();

    final allEntries = <Map<String, dynamic>>[];
    final allExits = <Map<String, dynamic>>[];
    for (final direction in const ['Eastbound', 'Westbound']) {
      final entries = await service.entries('66outside', direction);
      allEntries.addAll(entries);
      for (final entry in entries) {
        final exits = await service.exits(
          '66outside',
          direction,
          '${entry['id']}',
        );
        allExits.addAll(exits);
        expect(entry['road'], '66outside');
        expect(entry['direction'], direction);
        expect(entry['ramp'], 'entry');
        expect(entry['mapKey'], startsWith('66outside:'));
        expect(entry['mapLabel'], isA<String>());
        expect(entry['mapX'], inInclusiveRange(0, 1429));
        expect(entry['mapY'], inInclusiveRange(0, 1707));
      }
    }
    expect(allEntries, hasLength(22));
    expect(allExits, hasLength(172));
    expect(allExits.map((exit) => exit['id']).toSet(), hasLength(172));
    for (final exit in allExits) {
      expect('${exit['id']}', matches(r'^o66:\w+:\d+$'));
      expect(exit['road'], '66outside');
      expect(exit['direction'], anyOf('Eastbound', 'Westbound'));
      expect(exit['ramp'], 'exit');
      expect(exit['mapKey'], startsWith('66outside:'));
      expect(exit['mapLabel'], isA<String>());
      expect(exit['mapX'], inInclusiveRange(0, 1429));
      expect(exit['mapY'], inInclusiveRange(0, 1707));
    }
    expect(
      service.ramps.where((ramp) => ramp['road'] == '66outside'),
      hasLength(194),
    );
  });

  test('quotes a direct express route and preserves operator rows', () async {
    final service = PricingService(
      client: _FixtureClient((request) {
        expect(request.url.host, 'expresslanes.com');
        return http.Response(
          jsonEncode({
            'error': '0',
            'response': [
              {
                'od': 'od_1038',
                'price': '4.25',
                'status': 'open',
                'road': '495',
                'time': '2099-01-01T00:00:00Z',
              },
            ],
          }),
          200,
        );
      }),
    );
    await service.load();
    final quote = await service.quote({
      'road': '495',
      'dir': 'Northbound',
      'entry': '182NO',
      'exit': '181ND',
    });
    expect(quote['price'], 4.25);
    expect((quote['legs'] as List).single['road'], 'I-495');
    expect(quote['fetchedAt'], isA<String>());
    expect(quote['source'], 'Express Lanes');
  });

  test(
    'selects newest outside-Beltway gantry rate and de-duplicates entry',
    () async {
      final service = PricingService(
        client: _FixtureClient((request) {
          expect(request.method, 'POST');
          expect(request.headers['x-requested-with'], 'XMLHttpRequest');
          expect(request.body, contains('data%5Bstarting_gantry_id%5D=401'));
          expect(request.body, contains('data%5Bending_gantry_id%5D=401'));
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'curl_response': jsonEncode({
                  'rates': [
                    {
                      'rateEndDate': '2025-01-01T00:00:00Z',
                      'gantry': {
                        'gantryId': '401',
                        'vehicleClasses': [
                          {'rateAmountTag': '1.25'},
                        ],
                      },
                    },
                    {
                      'rateEndDate': '2026-01-01T00:00:00Z',
                      'gantry': {
                        'gantryId': '401',
                        'vehicleClasses': [
                          {'rateAmountTag': '2.50'},
                        ],
                      },
                    },
                  ],
                }),
              },
            }),
            200,
          );
        }),
      );
      await service.load();
      final quote = await service.quote({
        'road': '66outside',
        'dir': 'Eastbound',
        'entry': '401',
        'exit': 'o66:401:0',
      });
      expect(quote['price'], 2.5);
      expect((quote['components'] as List), hasLength(1));
      expect(quote['outside66'], true);
      expect(quote['warning'], isA<String>());
    },
  );

  test('retains direct unavailable semantics for missing, closed, and invalid rows', () async {
    for (final row in <Map<String, dynamic>>[
      {'od': 'od_1038', 'price': '4.25', 'status': 'open', 'road': '495'},
      {'od': 'od_1038', 'price': '4.25', 'status': 'closed', 'road': '495'},
      {'od': 'od_1038', 'price': 'bad', 'status': 'open', 'road': '495'},
      {'missing': true},
    ]) {
      final service = _expressFixture({
        'error': '0',
        'response': row['missing'] == true ? [] : [row],
      });
      await service.load();
      final quote = await service.quote({
        'road': '495',
        'dir': 'Northbound',
        'entry': '182NO',
        'exit': '181ND',
      });
      if (row['missing'] == true ||
          (row['status'] == 'open' && row['price'] == 'bad')) {
        expect(quote['error'], 'Price unavailable');
      } else if (row['status'] == 'closed') {
        expect(quote['error'], 'Lane status unconfirmed or closed');
      }
    }
  });

  test(
    'connected I-66 west quote keeps known base subtotal and requested id',
    () async {
      final service = _expressFixture({
        'error': '0',
        'response': [
          {'od': 'od_1024', 'price': '3.00', 'status': 'open', 'road': '495'},
        ],
      });
      await service.load();
      final connected = await service.exits('495', 'Northbound', '189NO');
      final route28 = connected.firstWhere((item) => item['id'] == '66w:28');
      expect(route28['mapKey'], startsWith('66outside:'));
      expect(route28['mapLabel'], isA<String>());
      expect(route28['mapX'], inInclusiveRange(0, 1429));
      expect(route28['mapY'], inInclusiveRange(0, 1707));
      final quote = await service.quote({
        'road': '495',
        'dir': 'Northbound',
        'entry': '189NO',
        'exit': '66w:50',
      });
      expect(quote['id'], '66w:50');
      expect(quote['error'], 'Total incomplete');
      expect(quote['knownPrice'], 3.0);
      expect((quote['legs'] as List).last['road'], 'I-66 west express');
    },
  );

  test(
    'connected west quote combines express and planner components',
    () async {
      final service = PricingService(
        client: _FixtureClient((request) {
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'error': '0',
                'response': [
                  {
                    'od': 'od_1024',
                    'price': '3.00',
                    'status': 'open',
                    'road': '495',
                  },
                ],
              }),
              200,
            );
          }
          expect(request.headers['x-requested-with'], 'XMLHttpRequest');
          expect(request.body, contains('data%5Bstarting_gantry_id%5D=415'));
          expect(request.body, contains('data%5Bending_gantry_id%5D=420'));
          expect(request.body, contains('data%5Bmiddle_ending_gantry_id%5D='));
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'curl_response': jsonEncode({
                  'rates': [
                    {
                      'rateEndDate': '2026-01-01T00:00:00Z',
                      'gantry': {
                        'gantryId': '415',
                        'vehicleClasses': [
                          {'rateAmountTag': '2'},
                        ],
                      },
                    },
                    {
                      'rateEndDate': '2026-01-01T00:00:00Z',
                      'gantry': {
                        'gantryId': '420',
                        'vehicleClasses': [
                          {'rateAmountTag': '4'},
                        ],
                      },
                    },
                  ],
                }),
              },
            }),
            200,
          );
        }),
      );
      await service.load();
      final quote = await service.quote({
        'road': '495',
        'dir': 'Northbound',
        'entry': '189NO',
        'exit': '66w:28',
      });
      expect(quote['price'], 9.0);
      expect(quote['error'], isNull);
      expect((quote['legs'] as List).last['road'], 'I-66 west express');
      expect(quote['note'], contains('historical-average'));
    },
  );

  test('connected west 403 retains the known express subtotal', () async {
    final service = PricingService(
      client: _FixtureClient((request) {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'error': '0',
              'response': [
                {
                  'od': 'od_1024',
                  'price': '3.00',
                  'status': 'open',
                  'road': '495',
                },
              ],
            }),
            200,
          );
        }
        expect(request.headers['x-requested-with'], 'XMLHttpRequest');
        expect(request.body, contains('data%5Bstarting_gantry_id%5D=415'));
        expect(request.body, contains('data%5Bending_gantry_id%5D=420'));
        return http.Response('forbidden', 403);
      }),
    );
    await service.load();
    final quote = await service.quote({
      'road': '495',
      'dir': 'Northbound',
      'entry': '189NO',
      'exit': '66w:28',
    });
    expect(quote['error'], 'Total incomplete');
    expect(quote['knownPrice'], 3.0);
    expect((quote['legs'] as List).last['error'], contains('HTTP 403'));
  });

  test('rejects an unknown route before asking the operator', () async {
    final service = _expressFixture({'error': '0', 'response': []});
    await service.load();
    final quote = await service.quote({
      'road': '495',
      'dir': 'Northbound',
      'entry': '182NO',
      'exit': '999',
    });
    expect(quote['error'], 'No verified connection');
  });

  test(
    'rejects malformed outside rate timestamps with a stable error',
    () async {
      final service = PricingService(
        client: _FixtureClient(
          (request) => http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'curl_response': jsonEncode({
                  'rates': [
                    {
                      'rateEndDate': 'not-a-date',
                      'gantry': {
                        'gantryId': '401',
                        'vehicleClasses': [
                          {'rateAmountTag': '1'},
                        ],
                      },
                    },
                  ],
                }),
              },
            }),
            200,
          ),
        ),
      );
      await service.load();
      await expectLater(
        service.quote({
          'road': '66outside',
          'dir': 'Eastbound',
          'entry': '401',
          'exit': 'o66:401:0',
        }),
        throwsA(isA<StateError>()),
      );
    },
  );
}
