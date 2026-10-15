// Opt-in network probe: flutter test tool/live_i66_probe_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_toll/pricing.dart';

// Use the real native HTTP transport instead of Flutter's test HTTP stub.
class _LiveHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'official outside-Beltway pricing through the native app adapter',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final service = PricingService();
        final results = <Json>[];
        try {
          await service.load();
          for (final sample in [
            {'dir': 'Eastbound', 'entry': '401', 'exitIndex': 0},
            {'dir': 'Eastbound', 'entry': '401', 'exitIndex': 4},
            {'dir': 'Westbound', 'entry': '415', 'exitIndex': 7},
          ]) {
            final dir = sample['dir'] as String;
            final id = sample['entry'] as String;
            final entries = await service.entries('66outside', dir);
            final exits = await service.exits('66outside', dir, id);
            final entry = entries.firstWhere((e) => e['id'] == id);
            final exit = exits[sample['exitIndex'] as int];
            final trip = <String, dynamic>{
              'road': '66outside',
              'dir': dir,
              'entry': id,
              'exit': exit['id'],
              'entryLabel': entry['label'],
              'exitLabel': exit['label'],
            };
            final quote = await service.quote(trip);
            expect(quote['price'], isA<num>());
            expect(quote['price'], greaterThanOrEqualTo(0));
            expect(quote['error'], isNull);
            expect(quote['components'], isNotEmpty);
            expect(quote['note'], contains('historical-average'));
            results.add({'trip': trip, 'quote': quote});
            // Public route data only; no device location or cookies are used.
            stdout.writeln(
              '${entry['label']} → ${exit['label']}: USD ${quote['price']}',
            );
          }
          final report = File('output/i66-investigation/native-probe.json');
          await report.parent.create(recursive: true);
          await report.writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'checkedAt': DateTime.now().toUtc().toIso8601String(),
              'transport': 'native Dart HTTP through PricingService',
              'livePriceVerified': false,
              'results': results,
            }),
          );
        } finally {
          service.dispose();
        }
      }, _LiveHttp());
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test('cross-highway operator handoffs', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final service = PricingService();
      final results = <Json>[];
      try {
        await service.load();
        for (final (road, direction, entry, targetRoad, targetExit) in [
          ('66outside', 'Eastbound', '401', '66', '|16'),
          ('66', 'Westbound', '16', '66outside', '|o66:417:9'),
          ('66outside', 'Eastbound', '401', '95', '|218SD'),
          ('66outside', 'Eastbound', '401', '495', '|181ND'),
          ('66', 'Westbound', '16', '95', '|218SD'),
          ('395', 'Southbound', '2232SO', '66outside', '66w:28'),
          ('495', 'Northbound', '189NO', '66', '66e:16'),
        ]) {
          final exits = await service.exits(road, direction, entry);
          final destination = exits.firstWhere(
            (exit) =>
                exit['road'] == targetRoad &&
                '${exit['id']}'.endsWith(targetExit),
          );
          final trip = <String, dynamic>{
            'road': road,
            'dir': direction,
            'entry': entry,
            'exit': destination['id'],
            'exitLabel': destination['label'],
          };
          final quote = await service.quote(trip);
          expect(quote['id'], destination['id']);
          expect(
            quote['roads'],
            containsAll([road, targetRoad == '95' ? '495' : targetRoad]),
          );
          expect(quote['error'], isNot('No verified connection'));
          if (quote['error'] != null) expect(quote['price'], isNull);
          results.add({'trip': trip, 'quote': quote});
          stdout.writeln(
            '$road $direction $entry → ${destination['label']}: '
            '${quote['price'] ?? quote['error']} (known ${quote['knownPrice'] ?? '—'})',
          );
        }
        final report = File(
          'output/cross-highway-investigation/native-probe.json',
        );
        await report.parent.create(recursive: true);
        await report.writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'checkedAt': DateTime.now().toUtc().toIso8601String(),
            'results': results,
          }),
        );
      } finally {
        service.dispose();
      }
    }, _LiveHttp());
  }, timeout: const Timeout(Duration(minutes: 3)));
}
