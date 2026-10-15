import 'package:flutter/material.dart';

import '../formatting.dart';
import '../planner_controller.dart';
import '../pricing.dart';

class SavedTripsPage extends StatelessWidget {
  const SavedTripsPage({
    super.key,
    required this.controller,
    required this.onLoad,
    required this.onPlan,
  });
  final PlannerController controller;
  final void Function(Json) onLoad;
  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = <Widget>[
      Text('Saved on this device', style: theme.textTheme.bodyMedium),
      const SizedBox(height: 16),
    ];
    if (controller.saved.isEmpty) {
      content.add(
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.bookmark_border, size: 42),
                const SizedBox(height: 12),
                Text('No saved trips yet', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'Save a route after checking its toll estimate.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onPlan,
                  child: const Text('Plan a trip'),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      for (final trip in controller.saved) {
        content.add(
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 6,
              ),
              onTap: () => onLoad(trip),
              leading: const Icon(Icons.route),
              title: Text('${trip['entryLabel']} → ${trip['exitLabel']}'),
              subtitle: Text(
                '${roadNames[trip['road']] ?? trip['road']} · ${trip['dir']}',
              ),
              trailing: IconButton(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                tooltip: 'Delete saved trip',
                onPressed: () => controller.deleteTrip(trip),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          ),
        );
      }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: content,
            ),
          ),
        ),
      ],
    );
  }
}
