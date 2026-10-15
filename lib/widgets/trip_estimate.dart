import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../formatting.dart';
import '../planner_controller.dart';

class TripEstimate extends StatelessWidget {
  const TripEstimate({
    super.key,
    required this.controller,
    required this.onEdit,
  });
  final PlannerController controller;
  final VoidCallback onEdit;

  List<Map<String, String>> _officialSources(Json? trip, Json? quote) {
    final roads = <String>[
      '${trip?['road'] ?? ''}',
      for (final leg in (quote?['legs'] as List? ?? const []))
        if (leg is Map) '${leg['road'] ?? ''}',
    ].map((road) => road.toLowerCase()).toList();
    final source = '${quote?['source'] ?? ''}'.toLowerCase();
    final sources = <Map<String, String>>[];
    void add(String label, String url) {
      if (sources.every((source) => source['url'] != url)) {
        sources.add({'label': label, 'url': url});
      }
    }

    final express = roads.any(
          (road) =>
              road == '495' ||
              road == '95' ||
              road == '395' ||
              road.contains('i-495') ||
              road.contains('i-95') ||
              road.contains('i-395'),
        ) ||
        source.contains('express lanes');
    final inside66 = roads.any(
      (road) =>
          road == '66' ||
          road == 'i-66' ||
          road.contains('i-66 east') ||
          road.contains('inside beltway'),
    );
    final outside66 = roads.any(
      (road) =>
          road == '66outside' ||
          road == '66w' ||
          road.contains('i-66 west') ||
          road.contains('outside beltway'),
    );
    if (express) {
      add(
        'I-495 / I-95 / I-395 Express Lanes',
        'https://www.expresslanes.com/map-your-trip',
      );
    }
    if (inside66) add('I-66 inside Beltway · VDOT', 'https://vai66tolls.com');
    if (outside66) {
      add(
        'I-66 outside Beltway · Ride66Express',
        'https://ride66express.com/pricing/plan-your-trip/',
      );
    }
    return sources;
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final q = c.quote;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget note(String text, {bool error = false}) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error ? scheme.errorContainer : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: error ? scheme.onErrorContainer : scheme.onSecondaryContainer,
        ),
      ),
    );
    final officialSources = _officialSources(c.trip, q);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Standard vehicle · Paid E-ZPass trip',
          style: theme.textTheme.bodyMedium,
        ),
        if (q?['error'] case final String error) note(error, error: true),
        if (q?['knownPrice'] is num)
          note(
            'Known subtotal: ${money(q!['knownPrice'])}. The full trip toll is incomplete.',
          ),
        if (q?['warning'] case final String warning when warning.isNotEmpty)
          note(warning),
        if (q?['note'] case final String value when value.isNotEmpty)
          note(value),
        for (final leg in (q?['legs'] as List? ?? const []))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text('${leg['road'] ?? 'Road segment'}')),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    leg['price'] is num
                        ? money(leg['price'])
                        : '${leg['error'] ?? 'Unavailable'}',
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
        if (q?['fetchedAt'] is String)
          Text(
            'Fetched ${easternTime('${q!['fetchedAt']}')}. Fetch time does not prove a new rate.',
            style: theme.textTheme.bodySmall,
          ),
        if (q?['source'] is String)
          Text('Source: ${q!['source']}', style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: c.pricingBusy ? null : c.refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh price'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: c.tripSaved ? null : c.saveTrip,
          icon: const Icon(Icons.bookmark_border),
          label: Text(c.tripSaved ? 'Trip saved' : 'Save this trip'),
        ),
        TextButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit route'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Refresh every 60 seconds'),
          subtitle: const Text('While viewing this estimate'),
          value: c.autoRefresh,
          onChanged: c.setAutoRefresh,
        ),
        if (officialSources.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Official toll check websites',
            style: theme.textTheme.titleSmall,
          ),
          for (final source in officialSources)
            TextButton.icon(
              onPressed: () async {
                try {
                  if (!await launchUrl(
                    Uri.parse(source['url']!),
                    mode: LaunchMode.externalApplication,
                  )) {
                    throw StateError('No browser');
                  }
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Could not open the official toll website.',
                        ),
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.open_in_new),
              label: Text(source['label']!),
            ),
        ],
      ],
    );
  }
}
