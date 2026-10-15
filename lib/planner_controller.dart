import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pricing.dart';

typedef ChooseRoute = Future<Json?> Function(
  String,
  List<Json>,
  String Function(Json),
);

/// Owns the route planner's mutable state and asynchronous work.
class PlannerController extends ChangeNotifier {
  PlannerController({PricingService? service})
    : service = service ?? PricingService();

  final PricingService service;
  static const _storageKey = 'nova-toll-trips';

  bool ready = false;
  bool manualBusy = false;
  bool pricingBusy = false;
  bool gpsBusy = false;
  bool mapBusy = false;
  bool autoRefresh = true;
  bool active = true;
  bool resultVisible = false;
  bool choosingEntry = true;
  String road = '495';
  String direction = 'Northbound';
  String notice = '';
  String gpsStatus = '';
  String? entry;
  String? exit;
  String? mapEntryId;
  String? mapExitId;
  String? mapOriginLabel;
  List<Json> entries = <Json>[];
  List<Json> exits = <Json>[];
  List<Json> saved = <Json>[];
  List<Json> mapRoutes = <Json>[];
  Json? trip;
  Json? quote;

  Timer? _timer;
  SharedPreferences? _preferences;
  int _manualGeneration = 0;
  int _priceGeneration = 0;
  int _mapGeneration = 0;
  bool _disposed = false;

  bool get tripSaved =>
      trip != null && saved.any((item) => _tripKey(item) == _tripKey(trip!));

  List<Json> get mapRecords {
    final records = <Json>[...service.ramps];
    for (final route in mapRoutes) {
      final destinations = route['exits'];
      if (destinations is! List) continue;
      for (final destination in destinations.whereType<Map>()) {
        final id = destination['id'];
        if (id is! String || !id.contains(':')) continue;
        if (service.ramps.any(
          (record) =>
              record['id'] == id &&
              record['ramp'] == 'exit' &&
              record['road'] == route['road'],
        )) {
          continue;
        }
        final east = id.startsWith('66e:');
        final base = east
            ? service.ramps
                  .where(
                    (record) =>
                        record['id'] == id.split(':').last &&
                        record['ramp'] == 'exit' &&
                        record['road'] == '66' &&
                        record['group'] == '66e',
                  )
                  .firstOrNull
            : null;
        records.add({
          ...?base,
          ...Map<String, dynamic>.from(destination),
          'road': destination['road'] ?? (east ? '66' : '66outside'),
          'ramp': 'exit',
        });
      }
    }
    return records;
  }

  Future<void> initialize() async {
    try {
      await service.load();
      try {
        _preferences = await SharedPreferences.getInstance();
        final decoded = jsonDecode(
          _preferences!.getString(_storageKey) ?? '[]',
        );
        if (decoded is List) {
          saved = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .where(_validSaved)
              .toList();
        }
      } catch (_) {
        _setNotice(
          'Saved trips are unavailable. New trips will stay in this session.',
        );
      }
      if (_disposed) return;
      ready = true;
      notifyListeners();
      startRefreshTimer();
      await loadEntries();
    } catch (_) {
      _setNotice(
        'Could not load the ramp catalog. Close and reopen the app to try again.',
      );
    }
  }

  Future<void> loadEntries({String? suggested}) async {
    return _loadEntries(suggested: suggested);
  }

  Future<void> _loadEntries({String? suggested, String? restoreExit}) async {
    final token = ++_manualGeneration;
    _update(() {
      manualBusy = true;
      entries = <Json>[];
      exits = <Json>[];
      entry = null;
      exit = null;
    });
    try {
      final result = await service.entries(road, direction);
      if (_disposed || token != _manualGeneration) return;
      _update(() => entries = result);
      if (suggested != null && result.any((r) => r['id'] == suggested)) {
        await _loadExits(suggested, restoreExit: restoreExit);
      } else {
        _update(() => manualBusy = false);
      }
    } catch (e) {
      if (!_disposed && token == _manualGeneration) {
        _update(() {
          manualBusy = false;
          notice = _cleanError(e);
        });
      }
    }
  }

  Future<void> loadExits(String id) async {
    return _loadExits(id);
  }

  Future<void> _loadExits(String id, {String? restoreExit}) async {
    final token = ++_manualGeneration;
    _update(() {
      entry = id;
      exit = null;
      exits = <Json>[];
      manualBusy = true;
    });
    try {
      final result = await service.exits(road, direction, id);
      if (!_disposed && token == _manualGeneration) {
        _update(() {
          exits = result;
          if (restoreExit != null &&
              result.any((r) => r['id'] == restoreExit)) {
            exit = restoreExit;
          }
          manualBusy = false;
        });
      }
    } catch (e) {
      if (!_disposed && token == _manualGeneration) {
        _update(() {
          manualBusy = false;
          notice = _cleanError(e);
        });
      }
    }
  }

  Future<void> selectMap(List<Json> records, ChooseRoute choose) async {
    if (mapBusy) return;
    if (choosingEntry || mapRoutes.isEmpty) {
      var candidates = records.where((r) => r['ramp'] == 'entry').toList();
      if (candidates.isEmpty) {
        _setNotice('This dot is an exit. Choose a supported entry first.');
        return;
      }
      if (candidates.length > 1 &&
          candidates.every((r) => r['road'] == '66outside')) {
        final chosen = await choose(
          'Choose your entry ramp',
          candidates,
          (r) => '${r['label']} · ${r['direction']}',
        );
        if (_disposed || chosen == null) return;
        candidates = [chosen];
      }
      final token = ++_mapGeneration;
      ++_priceGeneration;
      _update(() {
        mapEntryId = candidates.first['id'];
        mapOriginLabel = candidates.first['label'];
        mapExitId = null;
        trip = null;
        quote = null;
        pricingBusy = false;
        mapBusy = true;
        mapRoutes = <Json>[];
        notice = 'Checking reachable destinations…';
      });
      final routes = await Future.wait(
        candidates.map((r) async {
          try {
            final destinations = await service.exits(
              r['road'] ?? r['group'],
              r['direction'],
              r['id'],
            );
            return <String, dynamic>{
              'road': r['road'] ?? r['group'],
              'dir': r['direction'],
              'entry': r['id'],
              'entryLabel': r['label'],
              'exits': destinations,
            };
          } catch (_) {
            return null;
          }
        }),
      );
      if (_disposed || token != _mapGeneration) return;
      _update(() {
        mapRoutes = routes.whereType<Json>().toList();
        choosingEntry = false;
        mapBusy = false;
        notice = mapRoutes.any((r) => (r['exits'] as List).isNotEmpty) ? '' : 'Destinations are unavailable for this entry. Try Manual / GPS or another ramp.';
      });
      return;
    }
    final matches = <Json>[];
    for (final route in mapRoutes) {
      final destinations = route['exits'];
      if (destinations is! List) continue;
      for (final dest in destinations.whereType<Map>()) {
        if (records.any(
          (r) =>
              r['id'] == dest['id'] &&
              r['ramp'] == 'exit' &&
              (r['direction'] == null ||
                  r['direction'] == (dest['direction'] ?? route['dir'])) &&
              r['road'] == (dest['road'] ?? route['road']),
        )) {
          matches.add({
            ...route,
            'exit': dest['id'],
            'exitLabel': dest['label'],
          });
        }
      }
    }
    if (matches.isEmpty) {
      _setNotice(
        'No verified route connects these ramps. Choose another exit or change your entry.',
      );
      return;
    }
    final selected = matches.length == 1
        ? matches.first
        : await choose(
            'Choose your route',
            matches,
            (m) => '${m['dir']} · ${m['entryLabel']} → ${m['exitLabel']}',
          );
    if (!_disposed && selected != null) applyTrip(selected);
  }

  void applyTrip(Json selected) {
    ++_mapGeneration;
    final preserveRoutes = mapRoutes.any(
      (route) =>
          route['road'] == selected['road'] &&
          route['dir'] == selected['dir'] &&
          route['entry'] == selected['entry'],
    );
    final next = {
      for (final k in [
        'road',
        'dir',
        'entry',
        'exit',
        'entryLabel',
        'exitLabel',
      ])
        k: selected[k],
    };
    _update(() {
      trip = next;
      quote = null;
      notice = '';
      pricingBusy = false;
      mapBusy = false;
      if (!preserveRoutes) mapRoutes = <Json>[];
      choosingEntry = !preserveRoutes;
      mapEntryId = next['entry'];
      mapExitId = next['exit'];
      mapOriginLabel = next['entryLabel'];
    });
    refresh();
  }

  Future<void> refresh() async {
    if (trip == null || pricingBusy) return;
    final token = ++_priceGeneration;
    final selected = Map<String, dynamic>.from(trip!);
    _update(() {
      pricingBusy = true;
      quote = null;
    });
    try {
      final result = await service.quote(selected);
      if (!_disposed && token == _priceGeneration) {
        _update(() => quote = result);
      }
    } catch (e) {
      if (!_disposed && token == _priceGeneration) {
        _update(
          () =>
              quote = {'error': 'Estimate unavailable', 'note': _cleanError(e)},
        );
      }
    } finally {
      if (!_disposed && token == _priceGeneration) {
        _update(() => pricingBusy = false);
      }
    }
  }

  Future<void> useGps(ChooseRoute choose) async {
    _update(() {
      gpsBusy = true;
      gpsStatus = 'Finding a nearby entry…';
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Turn on device location, then try again.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception(
          'Location permission is off. Enable it in Android app settings.',
        );
      }
      if (permission == LocationPermission.denied) {
        throw Exception(
          'Location permission was declined. You can choose your route manually.',
        );
      }
      final location = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (!location.accuracy.isFinite || location.accuracy > 200) {
        throw Exception(
          'Location accuracy must be within 200 m. Try outdoors or choose your entry manually.',
        );
      }
      final headingValid =
          location.speed.isFinite &&
          location.speed >= 2 &&
          location.heading.isFinite &&
          location.heading >= 0 &&
          location.heading < 360;
      final nearby = <Json>[];
      for (final ramp in service.ramps.where((r) => r['ramp'] == 'entry')) {
        final lat = double.tryParse('${ramp['latitude']}'),
            lon = double.tryParse('${ramp['longitude']}');
        if (lat == null || lon == null) continue;
        final distance = Geolocator.distanceBetween(
          location.latitude,
          location.longitude,
          lat,
          lon,
        );
        if (distance > 5000) continue;
        if (headingValid) {
          final target = {
            'Northbound': 0.0,
            'Eastbound': 90.0,
            'Southbound': 180.0,
            'Westbound': 270.0,
          }[ramp['direction']];
          if (target == null) {
            continue;
          }
          final delta = (location.heading - target + 540) % 360 - 180;
          if (delta.abs() > 65) {
            continue;
          }
        }
        nearby.add({...ramp, 'distance': distance});
      }
      nearby.sort(
        (a, b) => (a['distance'] as double).compareTo(b['distance'] as double),
      );
      if (nearby.isEmpty) {
        throw Exception(
          'No supported entry found within 5 km. Choose your original entry manually.',
        );
      }
      final candidates = nearby
          .where(
            (r) =>
                (r['distance'] as double) <=
                (nearby.first['distance'] as double) + 200,
          )
          .take(8)
          .toList();
      final selected = candidates.length == 1
          ? candidates.first
          : await choose(
              'Confirm entry and direction',
              candidates,
              (r) => '${r['label']} · ${r['direction']}',
            );
      if (_disposed || selected == null) return;
      _update(() {
        road = selected['road'] ?? selected['group'];
        direction = selected['direction'];
        gpsStatus =
            'Suggested entry: ${selected['label']}. ${headingValid ? 'Check the entry and direction.' : 'Confirm the travel direction manually.'} Then choose your destination.';
      });
      await loadEntries(suggested: selected['id']);
    } catch (e) {
      if (!_disposed) _update(() => gpsStatus = _cleanError(e));
    } finally {
      if (!_disposed) _update(() => gpsBusy = false);
    }
  }

  void editTrip() {
    final selected = trip;
    if (selected == null) return;
    _update(() {
      road = '${selected['road']}';
      direction = '${selected['dir']}';
    });
    _loadEntries(
      suggested: '${selected['entry']}',
      restoreExit: '${selected['exit']}',
    );
  }

  void selectRoad(String value) {
    _update(() {
      road = value;
      direction = value.startsWith('66') ? 'Eastbound' : 'Northbound';
      notice = '';
    });
    loadEntries();
  }

  void selectDirection(String value) {
    _update(() {
      direction = value;
      notice = '';
    });
    loadEntries();
  }

  void selectExit(String value) => _update(() => exit = value);
  void setChoosingEntry(bool value) {
    _update(() => choosingEntry = value);
    if (!value && mapRoutes.isEmpty && trip != null) {
      unawaited(_hydrateTripMap());
    }
  }

  void setAutoRefresh(bool value) => _update(() => autoRefresh = value);
  void setVisibility({required bool active, required bool resultVisible}) {
    this.active = active;
    this.resultVisible = resultVisible;
  }

  void dismissNotice() => _setNotice('');
  void clearTrip() {
    ++_mapGeneration;
    ++_priceGeneration;
    _update(() {
      trip = null;
      quote = null;
      mapEntryId = null;
      mapExitId = null;
      mapOriginLabel = null;
      mapRoutes = <Json>[];
      choosingEntry = true;
      pricingBusy = false;
      mapBusy = false;
      notice = '';
    });
  }

  Future<void> saveTrip() async {
    if (trip == null || tripSaved) return;
    _update(() => saved.add(Map<String, dynamic>.from(trip!)));
    await _persist();
  }

  Future<void> deleteTrip(Json value) async {
    _update(
      () => saved.removeWhere((item) => _tripKey(item) == _tripKey(value)),
    );
    await _persist();
  }

  void tick() {
    if (autoRefresh &&
        active &&
        resultVisible &&
        trip != null &&
        !pricingBusy) {
      refresh();
    }
  }

  void startRefreshTimer() {
    _timer ??= Timer.periodic(const Duration(seconds: 60), (_) => tick());
  }

  Future<void> _hydrateTripMap() async {
    final selected = trip;
    if (selected == null) return;
    final token = ++_mapGeneration;
    final selectedRoad = '${selected['road']}';
    final selectedDirection = '${selected['dir']}';
    final selectedEntry = '${selected['entry']}';
    _update(() {
      mapEntryId = selectedEntry;
      mapOriginLabel = selected['entryLabel'];
      mapBusy = true;
    });
    try {
      final destinations = await service.exits(
        selectedRoad,
        selectedDirection,
        selectedEntry,
      );
      if (_disposed || token != _mapGeneration) return;
      _update(() {
        mapRoutes = [
          {
            'road': selectedRoad,
            'dir': selectedDirection,
            'entry': selectedEntry,
            'entryLabel': selected['entryLabel'],
            'exits': destinations,
          },
        ];
        mapBusy = false;
      });
    } catch (e) {
      if (!_disposed && token == _mapGeneration) {
        _update(() {
          mapBusy = false;
          notice = _cleanError(e);
        });
      }
    }
  }

  bool _validSaved(Json e) => [
    'road',
    'dir',
    'entry',
    'exit',
    'entryLabel',
    'exitLabel',
  ].every((k) => e[k] is String);
  String _tripKey(Json t) =>
      ['road', 'dir', 'entry', 'exit'].map((k) => t[k]).join(':');
  String _cleanError(Object e) => e.toString().replaceFirst(
    RegExp(r'^(Exception|StateError|Bad state): '),
    '',
  );
  Future<void> _persist() async {
    try {
      if (await _preferences?.setString(_storageKey, jsonEncode(saved)) !=
          true) {
        throw StateError('Storage unavailable');
      }
    } catch (_) {
      _setNotice(
        'Device storage is unavailable. Changes are saved for this session only.',
      );
    }
  }

  void _setNotice(String value) {
    if (_disposed) return;
    notice = value;
    notifyListeners();
  }

  void _update(void Function() change) {
    if (_disposed) return;
    change();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    service.dispose();
    super.dispose();
  }
}
