import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_toll/planner_controller.dart';
import 'package:nova_toll/pricing.dart';

class _FakePricing extends PricingService {
  _FakePricing() : super();

  final Completer<Json> quoteResult = Completer<Json>();

  @override
  Future<void> load() async {}

  @override
  Future<List<Json>> entries(String road, String direction) async => [
    {'id': 'entry', 'label': 'Entry'},
  ];

  @override
  Future<List<Json>> exits(String road, String direction, String entry) async =>
      [
        {'id': 'exit', 'label': 'Exit'},
      ];

  @override
  Future<Json> quote(Json trip) => quoteResult.future;
}

class _DelayedExitsPricing extends _FakePricing {
  final exitsResult = Completer<List<Json>>();

  @override
  Future<List<Json>> exits(String road, String direction, String entry) =>
      exitsResult.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Json trip() => {
    'road': '495',
    'dir': 'Northbound',
    'entry': 'entry',
    'exit': 'exit',
    'entryLabel': 'Entry',
    'exitLabel': 'Exit',
  };

  test('clearing a trip ignores a late quote response', () async {
    final service = _FakePricing();
    final controller = PlannerController(service: service);
    controller.applyTrip(trip());
    controller.clearTrip();
    service.quoteResult.complete({'price': 9});
    await Future<void>.delayed(Duration.zero);
    expect(controller.trip, isNull);
    expect(controller.quote, isNull);
    controller.dispose();
  });

  test('saveTrip and deleteTrip preserve the public saved state', () async {
    final service = _FakePricing();
    final controller = PlannerController(service: service);
    controller.trip = trip();
    await controller.saveTrip();
    expect(controller.tripSaved, isTrue);
    expect(controller.saved, hasLength(1));
    await controller.deleteTrip(controller.saved.single);
    expect(controller.saved, isEmpty);
    expect(controller.tripSaved, isFalse);
    controller.dispose();
  });

  test('tick only refreshes while active and viewing results', () async {
    final service = _FakePricing();
    final controller = PlannerController(service: service);
    controller.trip = trip();
    controller.setVisibility(active: true, resultVisible: false);
    controller.tick();
    expect(controller.pricingBusy, isFalse);
    controller.setVisibility(active: true, resultVisible: true);
    controller.tick();
    expect(controller.pricingBusy, isTrue);
    service.quoteResult.complete({'price': 4});
    await Future<void>.delayed(Duration.zero);
    expect(controller.quote?['price'], 4);
    controller.dispose();
  });

  test('late async callbacks after dispose do not notify', () async {
    final service = _FakePricing();
    final controller = PlannerController(service: service);
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.applyTrip(trip());
    final beforeDispose = notifications;
    controller.dispose();
    service.quoteResult.complete({'price': 7});
    await Future<void>.delayed(Duration.zero);
    expect(notifications, beforeDispose);
  });

  test('entering exit mode hydrates a loaded trip map route', () async {
    final controller = PlannerController(service: _FakePricing());
    controller.trip = trip();
    controller.setChoosingEntry(false);
    await Future<void>.delayed(Duration.zero);
    expect(controller.mapRoutes.single['entry'], 'entry');
    expect(controller.mapRoutes.single['exits'], hasLength(1));
    controller.dispose();
  });

  test('superseded edit does not restore an old exit', () async {
    final service = _DelayedExitsPricing();
    final controller = PlannerController(service: service);
    controller.trip = trip();
    controller.editTrip();
    await Future<void>.delayed(Duration.zero);
    controller.selectRoad('95');
    service.exitsResult.complete([
      {'id': 'exit', 'label': 'Exit'},
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.exit, isNull);
    controller.dispose();
  });
}
