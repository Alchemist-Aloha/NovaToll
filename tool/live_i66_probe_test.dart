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
}
