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

  List<Map<String, String>> _officialSources(
    Map<String, dynamic>? trip,
    Map<String, dynamic>? quote,
    List<String> routeRoads,
  ) {
    final roads = <String>{
      '${trip?['road'] ?? ''}',
      ...routeRoads,
      for (final road in (quote?['roads'] as List? ?? const [])) '$road',
    };
    return [
      if (roads.any({'495', '95', '395'}.contains))
        {
          'label': 'I-495 / I-95 / I-395 Express Lanes',
          'url': 'https://www.expresslanes.com/map-your-trip',
        },
      if (roads.contains('66'))
        {
          'label': 'I-66 inside Beltway · VDOT',
          'url': 'https://vai66tolls.com',
        },
      if (roads.contains('66outside'))
        {
          'label': 'I-66 outside Beltway · Ride66Express',
          'url': 'https://ride66express.com/pricing/plan-your-trip/',
        },
    ];
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
    final officialSources = _officialSources(
      c.trip,
      q,
      c.trip == null ? const [] : c.service.routeRoads(c.trip!),
    );
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
