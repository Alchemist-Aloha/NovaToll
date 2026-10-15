import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

typedef Json = Map<String, dynamic>;

const _expressPricesUrl =
    'https://expresslanes.com/maps-api/infra-price-confirmed-all';
const _i66Url = 'https://vai66tolls.com/Index';
const _outside66Url =
    'https://ride66express.com/wp-content/themes/i66/theme-ajax.php';
const _outside66Note =
    'Ride66Express planner estimate for a standard E-ZPass vehicle. '
    'The operator describes these as historical-average estimates; realtime '
    'accuracy is not verified.';
const _eastStops = <Json>[
  {'id': '4', 'label': 'Route 7 - Leesburg Pike'},
  {'id': '10', 'label': 'Westmoreland St'},
  {'id': '11', 'label': 'Washington Blvd'},
  {'id': '12', 'label': 'Fairfax Drive'},
  {'id': '13', 'label': 'Lee Highway - Spout Run Parkway'},
  {'id': '14', 'label': 'Exit 73 - Rosslyn'},
  {'id': '15', 'label': 'Exit 75 - Pentagon/Alexandria'},
  {'id': '16', 'label': 'Washington'},
];
const _westStops = <List<String>>[
  ['50', 'Route 50 · Fairfax'],
  ['monument', 'Monument Drive'],
  ['stringfellow', 'Stringfellow Road'],
  ['28', 'Route 28 · Centreville'],
  ['29g', 'Route 29 · Gainesville'],
];

class PricingService {
  PricingService({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  Json _catalog = <String, dynamic>{};
  List<Json> ramps = <Json>[];
  Map<String, dynamic> _outside = <String, dynamic>{};
  Map<String, dynamic> _outsideMap = <String, dynamic>{};
  bool _loaded = false;

  Future<void> load() async {
    tzdata.initializeTimeZones();
    final values = await Future.wait<String>([
      rootBundle.loadString('assets/catalog.json'),
      rootBundle.loadString('assets/ramps.json'),
      rootBundle.loadString('assets/outside66.json'),
      rootBundle.loadString('assets/outside66_map.json'),
    ]);
    final catalog = jsonDecode(values[0]);
    final rampData = jsonDecode(values[1]);
    final outside = jsonDecode(values[2]);
    final outsideMap = jsonDecode(values[3]);
    if (catalog is! Map<Object?, Object?> ||
        rampData is! List<dynamic> ||
        outside is! Map<Object?, Object?> ||
        outsideMap is! Map<Object?, Object?>) {
      throw const FormatException('Pricing assets have an invalid shape.');
    }
    _catalog = _json(catalog);
    final baseRamps = rampData
        .whereType<Map<Object?, Object?>>()
        .map(_json)
        .toList();
    _outside = Map<String, dynamic>.from(outside);
    _outsideMap = Map<String, dynamic>.from(outsideMap);
    ramps = _enrichOutsideRamps(baseRamps);
    _loaded = true;
  }

  Future<List<Json>> entries(String road, String dir) async {
    await _ensureLoaded();
    if (road == '66outside') {
      return _outside[dir] is List<dynamic>
          ? (_outside[dir] as List<dynamic>)
                .whereType<Map<Object?, Object?>>()
                .map(_json)
                .toList()
          : <Json>[];
    }
    if (road == '66') {
      final east = dir == 'Eastbound';
      final response = await _request(
        Uri.parse('$_i66Url?handler=BeginIntPartial&rbEastVal=$east'),
      );
      return _parseOptionsWithCoordinates(response.body);
    }
    final data = _catalog[dir];
    final source = data is Map<Object?, Object?> ? data['entries'] : null;
    if (source is! Map<Object?, Object?>) return <Json>[];
    return source.entries
        .where(
          (e) =>
              e.value is Map<Object?, Object?> &&
              '${(e.value as Map<Object?, Object?>)['path']}'.startsWith(road),
        )
        .map((e) => _json(e.value))
        .toList();
  }

  Future<List<Json>> exits(String road, String dir, String entry) async {
    final direct = await _nativeExits(road, dir, entry);
    final result = <Json>[...direct];
    final origin = {'road': road, 'dir': dir, 'entry': entry};
    void connect(
      Json via,
      String nextRoad,
      String nextDir,
      String nextEntry,
      List<Json> destinations,
    ) {
      for (final destination in destinations) {
        final destinationRoad = destination['road'] ?? nextRoad;
        final marker = ramps
            .where(
              (r) =>
                  r['ramp'] == 'exit' &&
                  r['id'] == destination['id'] &&
                  r['road'] == destinationRoad &&
                  (r['direction'] == null || r['direction'] == nextDir) &&
                  (destination['group'] == null ||
                      r['group'] == destination['group']),
            )
            .firstOrNull;
        final id =
            'via:${via['id']}|$nextRoad|$nextDir|$nextEntry|${destination['id']}';
        result.add({
          ...?marker,
          ...destination,
          'id': id,
          'label': '${destination['label']}'.startsWith('I-')
              ? destination['label']
              : '${_roadLabel(destinationRoad)} · ${destination['label']}',
          'road': destinationRoad,
          'direction': destination['direction'] ?? nextDir,
          'connection': [
            {...origin, 'exit': via['id']},
            {
              'road': nextRoad,
              'dir': nextDir,
              'entry': nextEntry,
              'exit': destination['id'],
            },
          ],
        });
      }
    }

    if (road == '66outside' && dir == 'Eastbound') {
      final through = direct
          .where((e) => e['label'] == 'EB GP Exit')
          .firstOrNull;
      if (through != null) {
        connect(through, '66', 'Eastbound', '1', _insideEastStops());
      }
      final express = direct
          .where((e) => e['label'] == 'I-495 Express Lanes (NB & SB)')
          .firstOrNull;
      if (express != null) {
        for (final (nextDir, nextEntry) in [
          ('Northbound', '187NO'),
          ('Southbound', '187SO'),
        ]) {
          connect(
            express,
            '495',
            nextDir,
            nextEntry,
            _expressExits(
              '495',
              nextDir,
              nextEntry,
            ).where((e) => !'${e['id']}'.contains(':')).toList(),
          );
        }
      }
    } else if (road == '66' && dir == 'Westbound') {
      final through = direct.where((e) => e['id'] == '1').firstOrNull;
      if (through != null) {
        connect(
          through,
          '66outside',
          'Westbound',
          '417',
          _outsideExits('Westbound', '417'),
        );
      }
      final south = direct.where((e) => e['id'] == '5').firstOrNull;
      if (south != null) {
        connect(
          south,
          '495',
          'Southbound',
          '187SO',
          _expressExits(
            '495',
            'Southbound',
            '187SO',
          ).where((e) => !'${e['id']}'.contains(':')).toList(),
        );
      }
    } else if (road != '66' && road != '66outside') {
      final interchange = direct
          .where((e) => '${e['label']}'.endsWith('Interstate 66'))
          .firstOrNull;
      if (interchange != null) {
        final nextEntry = '${interchange['path']}'.startsWith('495North')
            ? '415'
            : '414';
        const legacyLabels = {
          'US-50 EB',
          'Monument Dr',
          'Stringfellow Rd',
          'Rt28 NB/Walney Rd/Braddock Rd',
          'WB GP Exit',
        };
        connect(
          interchange,
          '66outside',
          'Westbound',
          nextEntry,
          _outsideExits(
            'Westbound',
            nextEntry,
          ).where((e) => !legacyLabels.contains(e['label'])).toList(),
        );
      }
    }
    return result;
  }

  List<Json> _insideEastStops() => [
    for (final stop in _eastStops)
      {
        ...?ramps
            .where(
              (r) =>
                  r['road'] == '66' &&
                  r['group'] == '66e' &&
                  r['ramp'] == 'exit' &&
                  r['id'] == stop['id'],
            )
            .firstOrNull,
        ...stop,
        'road': '66',
        'direction': 'Eastbound',
      },
  ];

  String _roadLabel(dynamic road) => switch (road) {
    '66' => 'I-66 inside Beltway',
    '66outside' => 'I-66 outside Beltway',
    _ => 'I-$road',
  };

  Future<List<Json>> _nativeExits(String road, String dir, String entry) async {
    await _ensureLoaded();
    if (road == '66outside') {
      return _outsideExits(dir, entry);
    }
    if (road == '66') {
      final east = dir == 'Eastbound';
      final response = await _request(
        Uri.parse(
          '$_i66Url?handler=ExitIntPartial&bIntId=$entry&rbEastVal=$east',
        ),
      );
      return [
        for (final item in _parseOptionsWithCoordinates(response.body))
          {
            ...item,
            'group': east ? '66e' : '66w',
            'road': '66',
            'direction': dir,
          },
      ];
    }
    return _expressExits(road, dir, entry);
  }

  List<Json> _outsideExits(String dir, String entry) {
    final list = _outside[dir];
    final selected = list is List<dynamic>
        ? list.whereType<Map<Object?, Object?>>().cast<Json>().where(
            (e) => e['id'] == entry,
          )
        : const <Json>[];
    final found = selected.isEmpty ? null : selected.first;
    final exits = found?['exits'];
    if (exits is! List<dynamic>) return <Json>[];
    return [
      for (var i = 0; i < exits.length; i++)
        if (exits[i] is Map<Object?, Object?>)
          _enrichOutsideExit(_json(exits[i]), dir: dir, entry: entry, index: i),
    ];
  }

  List<Json> _expressExits(String road, String dir, String entry) {
    final data = _catalog[dir];
    final entries = data is Map<Object?, Object?> ? data['entries'] : null;
    final item = entries is Map<Object?, Object?> ? entries[entry] : null;
    if (item is! Map<Object?, Object?> || !'${item['path']}'.startsWith(road)) {
      throw StateError('Unknown entry');
    }
    final exits = item['exits'];
    if (exits is! List<dynamic>) return <Json>[];
    final all = data is Map<Object?, Object?> ? data['exits'] : null;
    final direct = <Json>[
      for (final link in exits)
        if (link is Map<Object?, Object?> &&
            all is Map<Object?, Object?> &&
            all[link['id']] is Map<Object?, Object?>)
          {
            ..._json(all[link['id']]),
            'ods': link['ods'],
            'road': RegExp(r'^\d+')
                .firstMatch(
                  '${(all[link['id']] as Map<Object?, Object?>)['path']}',
                )
                ?.group(0),
            'direction': dir,
          },
    ];
    final interchange = direct
        .where((item) => '${item['label']}'.endsWith('Interstate 66'))
        .firstOrNull;
    if (interchange == null) return direct;
    final result = <Json>[...direct];
    for (final stop in _westStops) {
      result.add({
        'id': '66w:${stop[0]}',
        'label': 'I-66 west · ${stop[1]} (express)',
        'group': '66w',
        'via': interchange['id'],
        'road': '66outside',
        'direction': 'Westbound',
        ..._outsideMapForConnectedLabel(stop[0]),
      });
      if (stop[0] != 'monument' && stop[0] != 'stringfellow') {
        result.add({
          'id': '66g:${stop[0]}',
          'label': 'I-66 west · ${stop[1]} (regular lanes)',
          'group': '66w',
          'via': interchange['id'],
          'road': '66outside',
          'direction': 'Westbound',
          ..._outsideMapForConnectedLabel(stop[0]),
        });
      }
    }
    if ('${interchange['path']}'.startsWith('495North')) {
      for (final stop in _insideEastStops()) {
        result.add({
          ...stop,
          'id': '66e:${stop['id']}',
          'label': 'I-66 east · ${stop['label']}',
          'group': '66e',
          'via': interchange['id'],
          'direction': 'Eastbound',
        });
      }
    }
    return result;
  }

  Future<Json> quote(Json trip) async {
    await _ensureLoaded();
    final result = await _quoteRoute(trip);
    return {...result, 'roads': routeRoads(trip)};
  }

  List<String> routeRoads(Json trip) {
    final road = '${trip['road']}';
    final exit = '${trip['exit']}';
    if (exit.startsWith('via:')) {
      final parts = exit.substring(4).split('|');
      if (parts.length == 5) return [road, parts[1]];
    }
    return [
      road,
      if (exit.startsWith('66e:')) '66',
      if (exit.startsWith('66w:') || exit.startsWith('66g:')) '66outside',
    ];
  }

  Future<Json> _quoteRoute(Json trip) async {
    final road = '${trip['road']}';
    if ('${trip['exit']}'.startsWith('via:')) return _quoteConnection(trip);
    if (road == '66outside') return _quoteOutside(trip);
    if (road == '66') return _quoteInside(trip);
    if ('${trip['exit']}'.startsWith('66w:')) {
      return _quoteConnectedWest(trip);
    }
    return _quoteExpress(trip);
  }

  Future<Json> _quoteConnection(Json trip) async {
    final destinations = await exits(
      '${trip['road']}',
      '${trip['dir']}',
      '${trip['entry']}',
    );
    final destination = destinations
        .where((e) => e['id'] == trip['exit'])
        .firstOrNull;
    final connection = destination?['connection'];
    if (connection is! List<dynamic>) {
      return _errorQuote('${trip['exit']}', 'No verified connection');
    }
    final segments = connection.cast<Json>();
    final results = await Future.wait(
      segments.map((segment) async {
        try {
          return await _quoteRoute(segment);
        } catch (_) {
          return <String, dynamic>{'error': 'Operator estimate unavailable'};
        }
      }),
    );
    final complete = results.every(
      (r) => r['error'] == null && r['price'] is num,
    );
    var total = 0.0;
    var known = false;
    final legs = <Json>[];
    for (var i = 0; i < results.length; i++) {
      final result = results[i];
      final amount = result['error'] == null
          ? result['price']
          : result['knownPrice'];
      if (amount is num) {
        total += amount;
        known = true;
      }
      if (result['legs'] is List<dynamic> &&
          (result['legs'] as List<dynamic>).isNotEmpty) {
        legs.addAll(
          (result['legs'] as List<dynamic>)
              .whereType<Map<Object?, Object?>>()
              .map(_json),
        );
      } else {
        legs.add({
          'road': _roadLabel(segments[i]['road']),
          if (result['error'] == null && amount is num) 'price': amount,
          if (result['error'] != null) 'error': result['error'],
        });
      }
    }
    final notes = results.map((r) => r['note']).whereType<String>().toSet();
    final warnings = results
        .map((r) => r['warning'])
        .whereType<String>()
        .toSet();
    return _finish(
      {
        'id': trip['exit'],
        if (complete) 'price': _round(total),
        if (!complete) 'error': 'Total incomplete',
        if (!complete && known) 'knownPrice': _round(total),
        'legs': legs,
        if (notes.isNotEmpty) 'note': notes.join(' '),
        if (warnings.isNotEmpty) 'warning': warnings.join(' '),
      },
      source: segments
          .map(
            (s) => switch (s['road']) {
              '66outside' => 'Ride66Express planner',
              '66' => 'VDOT I-66 calculator',
              _ => 'Express Lanes',
            },
          )
          .toSet()
          .join(' + '),
    );
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<Json> _quoteExpress(Json trip) async {
    final response = await _request(Uri.parse(_expressPricesUrl));
    final source = jsonDecode(response.body);
    if (source is! Map<Object?, Object?> ||
        source['error']?.toString() != '0') {
      throw StateError('Operator pricing unavailable');
    }
    final dir = '${trip['dir']}';
    final directionData = _catalog[dir];
    final directionEntries = directionData is Map<Object?, Object?>
        ? directionData['entries']
        : null;
    final entry = directionEntries is Map<Object?, Object?>
        ? directionEntries[trip['entry']]
        : null;
    if (entry is! Map<Object?, Object?>) throw StateError('Unknown entry');
    final id = '${trip['exit']}';
    final allowed = _expressExits('${trip['road']}', dir, '${trip['entry']}');
    final destination = allowed.where((x) => x['id'] == id).firstOrNull;
    if (destination == null) return _errorQuote(id, 'No verified connection');
    final baseDestination = id.contains(':')
        ? allowed.where((x) => x['id'] == destination['via']).firstOrNull ??
              destination
        : destination;
    final direct = _directQuote(source, baseDestination);
    if (!id.contains(':')) return _finish(direct, source: 'Express Lanes');
    if (direct['error'] != null) {
      if (id.contains(':')) direct['id'] = id;
      return _finish(direct, source: 'Express Lanes');
    }
    if (id.startsWith('66w:')) {
      return _finish(<String, dynamic>{
        ...direct,
        'id': id,
      }, source: 'Express Lanes');
    }
    if (id.startsWith('66g:')) {
      return _finish(<String, dynamic>{
        ...direct,
        'id': id,
        'legs': [
          ...?direct['legs'] as List<dynamic>?,
          {'road': 'I-66 west regular lanes', 'price': 0},
        ],
        'note': 'Use regular lanes on I-66; no I-66 express toll included',
      }, source: 'Express Lanes');
    }
    try {
      final price = await _quote66('3', id.split(':')[1], true);
      return _finish(<String, dynamic>{
        ...direct,
        'id': id,
        'price': (direct['price'] as num) + price,
        'legs': [
          ...?direct['legs'] as List<dynamic>?,
          {'road': 'I-66 east', 'price': price},
        ],
        'note':
            'Current component estimates; I-66 may change before you reach it',
      }, source: 'Express Lanes');
    } catch (_) {
      return _finish(<String, dynamic>{
        'id': id,
        'error': 'Total incomplete',
        'knownPrice': direct['price'],
        'sourceTime': direct['sourceTime'],
        'legs': [
          ...?direct['legs'] as List<dynamic>?,
          {'road': 'I-66 east', 'error': 'Live price unavailable'},
        ],
      }, source: 'Express Lanes');
    }
  }

  Future<Json> _quoteConnectedWest(Json trip) async {
    final results = await Future.wait<Object?>([
      _quoteExpress(trip)
          .then<Object?>((value) => value)
          .catchError((Object error) => error),
      _quoteOutside(trip)
          .then<Object?>((value) => value)
          .catchError((Object error) => error),
    ]);
    final base = results[0] is Json ? results[0] as Json : null;
    final outside = results[1] is Json ? results[1] as Json : null;
    if (base == null || base['error'] != null) {
      if (outside != null) {
        return _finish({
          'id': trip['exit'],
          'error': 'Total incomplete',
          'knownPrice': outside['price'],
          'legs': [
            {'road': 'I-66 west express', 'price': outside['price']},
          ],
          'note': outside['note'],
        }, source: 'Express Lanes + Ride66Express planner');
      }
      return _finish({
        'id': trip['exit'],
        'error': base?['error'] ?? 'Total incomplete',
        if (base?['knownPrice'] != null) 'knownPrice': base!['knownPrice'],
        if (base?['legs'] != null) 'legs': base!['legs'],
      }, source: 'Express Lanes');
    }
    if (outside == null || outside['price'] == null) {
      final knownPrice = base.remove('price');
      return _finish({
        ...base,
        'id': trip['exit'],
        'error': 'Total incomplete',
        'knownPrice': knownPrice,
        'legs': [
          ...?base['legs'] as List<dynamic>?,
          {'road': 'I-66 west express', 'error': _outsideError(results[1])},
        ],
      }, source: 'Express Lanes');
    }
    return _finish({
      ...base,
      'id': trip['exit'],
      'price': (base['price'] as num) + (outside['price'] as num),
      'legs': [
        ...?base['legs'] as List<dynamic>?,
        {'road': 'I-66 west express', 'price': outside['price']},
      ],
      'note': outside['note'],
    }, source: 'Express Lanes + Ride66Express planner');
  }

  String _outsideError(Object? value) {
    if (value is StateError) return value.message;
    return 'Live I-66 west planner price unavailable';
  }

  Json _directQuote(Map<Object?, Object?> source, Json destination) {
    final rows = <Json>[];
    final response = source['response'];
    for (final od in (destination['ods'] as List<dynamic>? ?? const [])) {
      final found = response is List<dynamic>
          ? response.whereType<Map<Object?, Object?>>().where(
              (r) => r['od'] == 'od_$od',
            )
          : const <Map<Object?, Object?>>[];
      if (found.isEmpty) {
        return _errorQuote('${destination['id']}', 'Price unavailable');
      }
      rows.add(_json(found.first));
    }
    if (rows.any((row) => !_validAmount(row['price']))) {
      return _errorQuote('${destination['id']}', 'Price unavailable');
    }
    if (rows.any((row) => row['status'] != 'open')) {
      return _errorQuote(
        '${destination['id']}',
        'Lane status unconfirmed or closed',
      );
    }
    final times = rows.map((r) => r['time']).toList();
    return {
      'id': destination['id'],
      'price': rows.fold<double>(
        0,
        (sum, row) => sum + double.parse('${row['price']}'),
      ),
      'sourceTime': times.any((t) => t == null || t == 'null')
          ? null
          : times.reduce((a, b) => '$a'.compareTo('$b') < 0 ? a : b),
      'legs': rows
          .map(
            (r) => {
              'road': 'I-${r['road']}',
              'price': double.parse('${r['price']}'),
              'sourceTime': r['time'],
            },
          )
          .toList(),
    };
  }

  Future<Json> _quoteInside(Json trip) async {
    await _validateInsideRoute(trip);
    final ids = '${trip['exit']}'.split(',');
    final quotes = <Json>[];
    for (final id in ids) {
      try {
        quotes.add({
          'id': id,
          'price': await _quote66(
            '${trip['entry']}',
            id,
            '${trip['dir']}' == 'Eastbound',
          ),
          'dataSource': 'VDOT current I-66 calculator',
        });
      } catch (error) {
        quotes.add({
          'id': id,
          'error': 'Current I-66 estimate unavailable',
          'note': '$error',
        });
      }
    }
    final q = quotes.length == 1 ? quotes.first : {'legs': quotes};
    return _finish(q, source: 'VDOT I-66 calculator');
  }

  Future<double> _quote66(String entry, String exit, bool east) async {
    final now = tz.TZDateTime.now(tz.getLocation('America/New_York'));
    final date =
        '${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}/${now.year}';
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final time =
        '$hour:${now.minute.toString().padLeft(2, '0')} ${now.hour < 12 ? 'AM' : 'PM'}';
    final query = Uri.parse(_i66Url).replace(
      queryParameters: {
        'handler': 'TollCalcPartial',
        'bIntId': entry,
        'eIntId': exit,
        'datePicked': date,
        'timePicked': time,
        'rbEastVal': '$east',
        'isCurrent': 'true',
      },
    );
    Object? last;
    for (var i = 0; i < 2; i++) {
      try {
        final body = jsonDecode((await _request(query)).body);
        final value = body is Map<Object?, Object?> ? body['decToll'] : null;
        if (value is num && value.isFinite && value >= 0) {
          return value.toDouble();
        }
        throw StateError('VDOT returned an invalid I-66 price');
      } catch (error) {
        last = error;
      }
    }
    throw StateError('VDOT current I-66 calculator unavailable: $last');
  }

  Future<Json> _quoteOutside(Json trip) async {
    final route = _outsideRoute(trip);
    final ends = route['gantries'].toString().split(',');
    final form = <String, String>{
      'action': 'api_call',
      'data[starting_gantry_id]': '${route['entry']}',
      'data[ending_gantry_id]': ends.last,
      'data[middle_ending_gantry_id]': ends.length >= 2
          ? ends[ends.length - 2]
          : '',
      'data[first_ending_gantry_id]': ends.length == 3 ? ends.first : '',
      'data[xvWr]': '1',
      'data[response]': '',
    };
    final response = await _client
        .post(
          Uri.parse(_outside66Url),
          headers: {'X-Requested-With': 'XMLHttpRequest'},
          body: form,
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Ride66Express returned HTTP ${response.statusCode}.');
    }
    final payload = _decodeObject(
      response.body,
      'Ride66Express returned an unreadable response.',
    );
    final data = payload['data'];
    dynamic result = data is Map<Object?, Object?>
        ? data['curl_response']
        : null;
    if (result is String) {
      result = _decodeObject(
        result,
        'Ride66Express returned unreadable pricing data.',
      );
    }
    final rates = result is Map<Object?, Object?> ? result['rates'] : null;
    if (rates is! List<dynamic>) {
      throw StateError('The operator returned no rate list.');
    }
    final components = <Json>[];
    for (final id in {
      ...[route['entry'].toString(), ...ends],
    }) {
      final rows = rates
          .whereType<Map<Object?, Object?>>()
          .where(
            (r) =>
                '${(r['gantry'] as Map<Object?, Object?>?)?['gantryId']}' == id,
          )
          .toList();
      if (rows.isEmpty) {
        throw StateError('Rate missing for required I-66 gantry $id.');
      }
      try {
        for (final row in rows) {
          DateTime.parse('${row['rateEndDate']}');
        }
        rows.sort(
          (a, b) =>
              DateTime.parse('${b['rateEndDate']}')
                  .compareTo(DateTime.parse('${a['rateEndDate']}')),
        );
      } on FormatException {
        throw StateError(
          'The operator returned an invalid rate timestamp for gantry $id.',
        );
      }
      final row = rows.first;
      final raw =
          ((row['gantry'] as Map<Object?, Object?>?)?['vehicleClasses']
                  as List<dynamic>?)
              ?.firstOrNull;
      final amount = raw is Map<Object?, Object?> ? raw['rateAmountTag'] : null;
      if (!_validAmount(amount)) {
        throw StateError(
          'The operator returned an invalid toll for gantry $id.',
        );
      }
      components.add({
        'gantry': id,
        'price': double.parse('$amount'),
        'rateEndDate': row['rateEndDate'],
      });
    }
    final total = _round(
      components.fold<double>(0, (s, c) => s + (c['price'] as double)),
    );
    return _finish({
      'id': trip['exit'],
      'price': total,
      'outside66': true,
      'outside66RateEnds': components
          .map((c) => c['rateEndDate'])
          .toSet()
          .toList(),
      'components': components,
      'note': _outside66Note,
      'dataSource': 'Ride66Express planner via visitor browser',
      'legs': [
        {
          'road': trip['road'] == '66outside'
              ? 'I-66 outside Beltway'
              : 'I-66 west express',
          'price': total,
        },
      ],
    }, source: 'Ride66Express planner');
  }

  List<Json> _enrichOutsideRamps(List<Json> base) {
    final result = <Json>[...base];
    final catalog = <String, dynamic>{};
    for (final direction in const ['Eastbound', 'Westbound']) {
      final source = _outside[direction];
      if (source is! List<dynamic>) {
        throw FormatException(
          'I-66 outside catalog is missing $direction entries.',
        );
      }
      final enrichedEntries = <Json>[];
      for (final raw in source.whereType<Map<Object?, Object?>>()) {
        final entry = _json(raw);
        final id = '${entry['id']}';
        final mapped = _outsideMetadata(
          direction: direction,
          locationKey: _mapEntryLocation(id, direction),
          description: 'entry $id',
        );
        final enriched = {
          ...entry,
          ...mapped,
          'road': '66outside',
          'direction': direction,
          'ramp': 'entry',
        };
        enrichedEntries.add(enriched);
        result.add({...enriched, 'exits': null});
        final exits = entry['exits'];
        if (exits is! List<dynamic>) {
          throw FormatException('I-66 outside entry $id has no exits list.');
        }
        for (var i = 0; i < exits.length; i++) {
          if (exits[i] is! Map<Object?, Object?>) {
            throw FormatException(
              'I-66 outside entry $id has an invalid exit at index $i.',
            );
          }
          result.add(
            _enrichOutsideExit(
              _json(exits[i]),
              dir: direction,
              entry: id,
              index: i,
            ),
          );
        }
      }
      catalog[direction] = enrichedEntries;
    }
    _outside = catalog;
    return result;
  }

  Json _enrichOutsideExit(
    Json exit, {
    required String dir,
    required String entry,
    required int index,
  }) {
    final label = '${exit['label']}';
    return {
      ...exit,
      'id': 'o66:$entry:$index',
      ..._outsideMetadata(
        direction: dir,
        locationKey: _mapExitLocation(label, dir),
        description: 'exit "$label" ($dir entry $entry index $index)',
      ),
      'road': '66outside',
      'direction': dir,
      'ramp': 'exit',
    };
  }

  String _mapEntryLocation(String id, String direction) {
    final entries = _outsideMap['entries'];
    final value = entries is Map<Object?, Object?> ? entries[id] : null;
    if (value is! String || value.isEmpty) {
      throw FormatException(
        'I-66 outside map is missing entry $id ($direction).',
      );
    }
    return value;
  }

  String _mapExitLocation(String label, String direction) {
    final exits = _outsideMap['exits'];
    final value = exits is Map<Object?, Object?> ? exits[label] : null;
    if (value is! String || value.isEmpty) {
      throw FormatException(
        'I-66 outside map is missing exit "$label" ($direction).',
      );
    }
    return value;
  }

  Json _outsideMetadata({
    required String direction,
    required String locationKey,
    required String description,
  }) {
    final locations = _outsideMap['locations'];
    final location = locations is Map<Object?, Object?>
        ? locations[locationKey]
        : null;
    if (location is! Map<Object?, Object?>) {
      throw FormatException(
        'I-66 outside map has no location "$locationKey" for $description.',
      );
    }
    final x = location['x'];
    final y = location['y'];
    if (x is! num || y is! num || !x.isFinite || !y.isFinite) {
      throw FormatException(
        'I-66 outside map has invalid coordinates for $description.',
      );
    }
    final label = location['label'];
    if (label is! String || label.trim().isEmpty) {
      throw FormatException('I-66 outside map has no label for $description.');
    }
    return {
      'mapKey': '66outside:$locationKey',
      'mapLabel': label,
      'mapX': x.toDouble(),
      'mapY': y.toDouble(),
    };
  }

  Json _outsideMapForConnectedLabel(String key) {
    const labels = {
      '50': 'US-50 EB',
      'monument': 'Monument Dr',
      'stringfellow': 'Stringfellow Rd',
      '28': 'Rt28 NB/Walney Rd/Braddock Rd',
      '29g': 'WB GP Exit',
    };
    final label = labels[key];
    if (label == null) return <String, dynamic>{};
    return _outsideMetadata(
      direction: 'Westbound',
      locationKey: _mapExitLocation(label, 'Westbound'),
      description: 'connected destination "$label"',
    );
  }

  Json _outsideRoute(Json trip) {
    final dir = '${trip['dir']}';
    if ('${trip['road']}' == '66outside') {
      final entries = _outside[dir];
      final entry = entries is List<dynamic>
          ? entries
                .whereType<Map<Object?, Object?>>()
                .where((e) => e['id'] == trip['entry'])
                .firstOrNull
          : null;
      final exits = entry?['exits'];
      final selected = exits is List<dynamic>
          ? exits
                .whereType<Map<Object?, Object?>>()
                .where(
                  (e) =>
                      'o66:${trip['entry']}:${exits.indexOf(e)}' ==
                      trip['exit'],
                )
                .firstOrNull
          : null;
      if (entry == null || selected == null) {
        throw StateError('No verified outside-Beltway route.');
      }
      return {'entry': entry['id'], 'gantries': selected['gantries']};
    }
    if (!['Northbound', 'Southbound'].contains(dir) ||
        !'${trip['exit']}'.startsWith('66w:')) {
      throw StateError('No verified outside-Beltway connection.');
    }
    final destination = _expressExits(
      '${trip['road']}',
      dir,
      '${trip['entry']}',
    ).where((e) => e['id'] == trip['exit']).firstOrNull;
    final interchange = _expressExits(
      '${trip['road']}',
      dir,
      '${trip['entry']}',
    ).where((e) => e['id'] == destination?['via']).firstOrNull;
    if (interchange == null) {
      throw StateError('No verified outside-Beltway connection.');
    }
    final start = '${interchange['path']}'.startsWith('495North')
        ? '415'
        : '414';
    final key = '${trip['exit']}'.split(':')[1];
    final end = {
      '50': start,
      'monument': '420',
      'stringfellow': '420',
      '28': '420',
      '29g': '420,423,425',
    }[key];
    if (end == null) {
      throw StateError('No verified outside-Beltway connection.');
    }
    return {'entry': start, 'gantries': end};
  }

  Future<http.Response> _request(Uri uri) async {
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Operator returned HTTP ${response.statusCode}.');
    }
    return response;
  }

  Future<void> _validateInsideRoute(Json trip) async {
    final dir = '${trip['dir']}';
    final entry = '${trip['entry']}';
    final exit = '${trip['exit']}';
    if (!RegExp(r'^\d+$').hasMatch(entry) || !RegExp(r'^\d+$').hasMatch(exit)) {
      throw StateError('No verified I-66 route.');
    }
    final knownEntries = await entries('66', dir);
    if (!knownEntries.any((item) => item['id'] == entry)) {
      throw StateError('No verified I-66 entry.');
    }
    final knownExits = await _nativeExits('66', dir, entry);
    if (!knownExits.any((item) => item['id'] == exit)) {
      throw StateError('No verified I-66 exit.');
    }
  }

  Future<void> _ensureLoaded() async {
    if (!_loaded) await load();
  }

  Json _finish(Json value, {required String source}) {
    final result = <String, dynamic>{
      ...value,
      'fetchedAt': DateTime.now().toUtc().toIso8601String(),
      'source': source,
    };
    final timestamps = <dynamic>[];
    if (result['sourceTime'] != null) timestamps.add(result['sourceTime']);
    final legs = result['legs'];
    if (legs is List<dynamic>) {
      timestamps.addAll(
        legs.whereType<Map<Object?, Object?>>().map((leg) => leg['sourceTime']),
      );
    }
    final warning = _freshnessWarning(timestamps);
    if (warning != null) result['warning'] = warning;
    return result;
  }

  String? _freshnessWarning(Iterable<dynamic> values) {
    final timestamps = values.where((value) => value != null).toList();
    if (timestamps.isEmpty) return 'Operator rate timestamp not supplied.';
    final now = tz.TZDateTime.now(tz.getLocation('America/New_York'));
    for (final raw in timestamps) {
      final parsed = DateTime.tryParse('$raw');
      if (parsed == null) {
        return 'The operator rate timestamp is invalid or unverified.';
      }
      final age = now.toUtc().difference(parsed.toUtc());
      if (age > const Duration(minutes: 5) ||
          age < -const Duration(minutes: 1)) {
        return 'The operator timestamp is older than 5 minutes or unverified.';
      }
    }
    return null;
  }

  Json _errorQuote(String id, String error) => {'id': id, 'error': error};
  bool _validAmount(dynamic value) =>
      value != null &&
      value.toString().trim().isNotEmpty &&
      value != 'null' &&
      double.tryParse('$value') != null &&
      double.parse('$value') >= 0;
  double _round(double value) => (value * 100).roundToDouble() / 100;
  Json _json(dynamic value) =>
      Map<String, dynamic>.from(value as Map<Object?, Object?>);

  Json _decodeObject(String value, String message) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<Object?, Object?>) return _json(decoded);
    } on FormatException {
      // Use one stable service error for malformed operator responses.
    }
    throw StateError(message);
  }

  List<Json> _parseOptionsWithCoordinates(String html) {
    final options = <Json>[];
    final re = RegExp(r'<option value="(\d+)">([^<]+)</option>');
    for (final match in re.allMatches(html)) {
      options.add({'id': match.group(1), 'label': match.group(2)});
    }
    final coords = RegExp(
      r"new Exit\('[^']*', 0, 0, '[^']*', (\d+), ([\d.-]+), ([\d.-]+)",
    );
    for (final match in coords.allMatches(html)) {
      final item = options.where((x) => x['id'] == match.group(1)).firstOrNull;
      if (item != null) {
        item['latitude'] = double.parse(match.group(2)!);
        item['longitude'] = double.parse(match.group(3)!);
      }
    }
    return options;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
