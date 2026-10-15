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
    if (catalog is! Map ||
        rampData is! List ||
        outside is! Map ||
        outsideMap is! Map) {
      throw const FormatException('Pricing assets have an invalid shape.');
    }
    _catalog = _json(catalog);
    final baseRamps = rampData.whereType<Map>().map(_json).toList();
    _outside = Map<String, dynamic>.from(outside);
    _outsideMap = Map<String, dynamic>.from(outsideMap);
    ramps = _enrichOutsideRamps(baseRamps);
    _loaded = true;
  }

  Future<List<Json>> entries(String road, String dir) async {
    await _ensureLoaded();
    if (road == '66outside') {
      return _outside[dir] is List
          ? (_outside[dir] as List).whereType<Map>().map(_json).toList()
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
    final source = data is Map ? data['entries'] : null;
    if (source is! Map) return <Json>[];
    return source.entries
        .where((e) => e.value is Map && '${e.value['path']}'.startsWith(road))
        .map((e) => _json(e.value))
        .toList();
  }

  Future<List<Json>> exits(String road, String dir, String entry) async {
    await _ensureLoaded();
    if (road == '66outside') {
      final list = _outside[dir];
      final selected = list is List
          ? list.whereType<Map>().cast<Json>().where((e) => e['id'] == entry)
          : const <Json>[];
      final found = selected.isEmpty ? null : selected.first;
      final exits = found?['exits'];
      if (exits is! List) return <Json>[];
      return [
        for (var i = 0; i < exits.length; i++)
          if (exits[i] is Map)
            _enrichOutsideExit(
              _json(exits[i]),
              dir: dir,
              entry: entry,
              index: i,
            ),
      ];
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
          {...item, 'group': east ? '66e' : '66w'},
      ];
    }
    final data = _catalog[dir];
    final entries = data is Map ? data['entries'] : null;
    final item = entries is Map ? entries[entry] : null;
    if (item is! Map) throw StateError('Unknown entry');
    final exits = item['exits'];
    if (exits is! List) return <Json>[];
    final all = data is Map ? data['exits'] : null;
    final direct = <Json>[
      for (final link in exits)
        if (link is Map && all is Map && all[link['id']] is Map)
          {..._json(all[link['id']]), 'ods': link['ods']},
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
        ..._outsideMapForConnectedLabel(stop[0]),
      });
      if (stop[0] != 'monument' && stop[0] != 'stringfellow') {
        result.add({
          'id': '66g:${stop[0]}',
          'label': 'I-66 west · ${stop[1]} (regular lanes)',
          'group': '66w',
          'via': interchange['id'],
          ..._outsideMapForConnectedLabel(stop[0]),
        });
      }
    }
    if (dir == 'Northbound') {
      for (final stop in _eastStops) {
        result.add({
          ...stop,
          'id': '66e:${stop['id']}',
          'label': 'I-66 east · ${stop['label']}',
          'group': '66e',
          'via': interchange['id'],
        });
      }
    }
    return result;
  }

  Future<Json> quote(Json trip) async {
    await _ensureLoaded();
    final road = '${trip['road']}';
    if (road == '66outside') return _quoteOutside(trip);
    if (road == '66') return _quoteInside(trip);
    if ('${trip['exit']}'.startsWith('66w:')) {
      return _quoteConnectedWest(trip);
    }
    return _quoteExpress(trip);
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<Json> _quoteExpress(Json trip) async {
    final response = await _request(Uri.parse(_expressPricesUrl));
    final source = jsonDecode(response.body);
    if (source is! Map || source['error']?.toString() != '0') {
      throw StateError('Operator pricing unavailable');
    }
    final dir = '${trip['dir']}';
    final directionData = _catalog[dir];
    final directionEntries = directionData is Map
        ? directionData['entries']
        : null;
    final entry = directionEntries is Map
        ? directionEntries[trip['entry']]
        : null;
    if (entry is! Map) throw StateError('Unknown entry');
    final id = '${trip['exit']}';
    final allowed = await exits('${trip['road']}', dir, '${trip['entry']}');
    final destination = allowed.where((x) => x['id'] == id).firstOrNull;
    if (destination == null) return _errorQuote(id, 'No verified connection');
    final baseDestination = id.contains(':')
        ? allowed.where((x) => x['id'] == destination['via']).firstOrNull ??
              destination
        : destination;
    final direct = _directQuote(source, entry, baseDestination);
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
          ...?direct['legs'] as List?,
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
          ...?direct['legs'] as List?,
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
          ...?direct['legs'] as List?,
          {'road': 'I-66 east', 'error': 'Live price unavailable'},
        ],
      }, source: 'Express Lanes');
    }
  }

  Future<Json> _quoteConnectedWest(Json trip) async {
    final results = await Future.wait<Object?>([
      _quoteExpress(trip)
          .then<Object?>((value) => value)
          .catchError((error) => error),
      _quoteOutside(trip)
          .then<Object?>((value) => value)
          .catchError((error) => error),
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
      return _finish({
        ...base,
        'id': trip['exit'],
        'error': 'Total incomplete',
        'knownPrice': base['price'],
        'legs': [
          ...?base['legs'] as List?,
          {'road': 'I-66 west express', 'error': _outsideError(results[1])},
        ],
      }, source: 'Express Lanes');
    }
    return _finish({
      ...base,
      'id': trip['exit'],
      'price': (base['price'] as num) + (outside['price'] as num),
      'legs': [
        ...?base['legs'] as List?,
        {'road': 'I-66 west express', 'price': outside['price']},
      ],
      'note': outside['note'],
    }, source: 'Express Lanes + Ride66Express planner');
  }

  String _outsideError(Object? value) {
    if (value is StateError) return value.message;
    return 'Live I-66 west planner price unavailable';
  }

  Json _directQuote(dynamic source, dynamic entry, Json destination) {
    final rows = <Json>[];
    final response = source['response'];
    for (final od in (destination['ods'] as List? ?? const [])) {
      final found = response is List
          ? response.whereType<Map>().where((r) => r['od'] == 'od_$od')
          : const <Map>[];
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
        final value = body is Map ? body['decToll'] : null;
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
    dynamic result = data is Map ? data['curl_response'] : null;
    if (result is String) {
      result = _decodeObject(
        result,
        'Ride66Express returned unreadable pricing data.',
      );
    }
    final rates = result is Map ? result['rates'] : null;
    if (rates is! List) throw StateError('The operator returned no rate list.');
    final components = <Json>[];
    for (final id in {
      ...[route['entry'].toString(), ...ends],
    }) {
      final rows = rates
          .whereType<Map>()
          .where((r) => '${(r['gantry'] as Map?)?['gantryId']}' == id)
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
          ((row['gantry'] as Map?)?['vehicleClasses'] as List?)?.firstOrNull;
      final amount = raw is Map ? raw['rateAmountTag'] : null;
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
    final total = _round(components.fold<double>(0, (s, c) => s + c['price']));
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
      if (source is! List) {
        throw FormatException(
          'I-66 outside catalog is missing $direction entries.',
        );
      }
      final enrichedEntries = <Json>[];
      for (final raw in source.whereType<Map>()) {
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
        if (exits is! List) {
          throw FormatException('I-66 outside entry $id has no exits list.');
        }
        for (var i = 0; i < exits.length; i++) {
          if (exits[i] is! Map) {
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
    final value = entries is Map ? entries[id] : null;
    if (value is! String || value.isEmpty) {
      throw FormatException(
        'I-66 outside map is missing entry $id ($direction).',
      );
    }
    return value;
  }

  String _mapExitLocation(String label, String direction) {
    final exits = _outsideMap['exits'];
    final value = exits is Map ? exits[label] : null;
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
    final location = locations is Map ? locations[locationKey] : null;
    if (location is! Map) {
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
      final entry = entries is List
          ? entries
                .whereType<Map>()
                .where((e) => e['id'] == trip['entry'])
                .firstOrNull
          : null;
      final exits = entry?['exits'];
      final selected = exits is List
          ? exits
                .whereType<Map>()
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
    final start = dir == 'Northbound' ? '415' : '414';
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
    final knownExits = await exits('66', dir, entry);
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
    if (legs is List) {
      timestamps.addAll(legs.whereType<Map>().map((leg) => leg['sourceTime']));
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
  Json _json(dynamic value) => Map<String, dynamic>.from(value as Map);

  Json _decodeObject(String value, String message) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return _json(decoded);
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
