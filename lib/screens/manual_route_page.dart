import 'package:flutter/material.dart';

import '../formatting.dart';
import '../planner_controller.dart';
import '../pricing.dart';

class ManualRoutePage extends StatelessWidget {
  const ManualRoutePage({
    super.key,
    required this.controller,
    required this.choose,
    required this.onCalculate,
  });
  final PlannerController controller;
  final ChooseRoute choose;
  final VoidCallback onCalculate;

  Future<void> _pick(
    BuildContext context,
    String title,
    List<Json> options,
    String Function(Json) label,
    void Function(Json) apply,
  ) async {
    if (options.isEmpty || controller.manualBusy) return;
    final result = await choose(title, options, label);
    if (result != null) apply(result);
  }

  Widget _choice(
    BuildContext context, {
    required String label,
    required String value,
    required VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          isEmpty: value.isEmpty,
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: const Icon(Icons.expand_more),
            enabled: onTap != null,
          ),
          child: Text(
            value.isEmpty ? 'Choose an option' : value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: value.isEmpty ? scheme.onSurfaceVariant : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final names = roadNames;
    final directions = c.road.startsWith('66')
        ? const ['Eastbound', 'Westbound']
        : const ['Northbound', 'Southbound'];
    final entryLabel =
        c.entries
            .where((e) => e['id'] == c.entry)
            .firstOrNull?['label']
            ?.toString() ??
        '';
    final exitLabel =
        c.exits
            .where((e) => e['id'] == c.exit)
            .firstOrNull?['label']
            ?.toString() ??
        '';
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Set your route',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose the original entry where your express-lane trip begins.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                _choice(
                  context,
                  label: 'Starting highway',
                  value: names[c.road] ?? c.road,
                  onTap: () => _pick(
                    context,
                    'Starting highway',
                    names.entries
                        .map(
                          (e) => <String, dynamic>{
                            'id': e.key,
                            'label': e.value,
                          },
                        )
                        .toList(),
                    (e) => '${e['label']}',
                    (e) => c.selectRoad('${e['id']}'),
                  ),
                ),
                const SizedBox(height: 12),
                Semantics(
                  label: 'Travel direction',
                  child: SegmentedButton<String>(
                    style: const ButtonStyle(
                      minimumSize: WidgetStatePropertyAll(Size(48, 48)),
                    ),
                    segments: [
                      for (final d in directions)
                        ButtonSegment(
                          value: d,
                          label: Text(
                            {
                                  'Northbound': 'North',
                                  'Southbound': 'South',
                                  'Eastbound': 'East',
                                  'Westbound': 'West',
                                }[d] ??
                                d,
                          ),
                          tooltip: d,
                        ),
                    ],
                    selected: {c.direction},
                    onSelectionChanged: c.manualBusy
                        ? null
                        : (v) => c.selectDirection(v.first),
                  ),
                ),
                const SizedBox(height: 12),
                _choice(
                  context,
                  label: 'Entry ramp',
                  value: entryLabel.isEmpty
                      ? (c.manualBusy
                            ? 'Loading operator ramps…'
                            : 'Choose your entry')
                      : entryLabel,
                  onTap: c.manualBusy
                      ? null
                      : () => _pick(
                          context,
                          'Choose your entry',
                          c.entries,
                          (e) => '${e['label']}',
                          (e) => c.loadExits('${e['id']}'),
                        ),
                ),
                const SizedBox(height: 12),
                _choice(
                  context,
                  label: 'Exit / connected destination',
                  value: exitLabel.isEmpty
                      ? (c.entry == null
                            ? 'Choose an entry first'
                            : 'Choose your destination')
                      : exitLabel,
                  onTap: c.manualBusy || c.entry == null
                      ? null
                      : () => _pick(
                          context,
                          'Choose your destination',
                          c.exits,
                          (e) => '${e['label']}',
                          (e) => c.selectExit('${e['id']}'),
                        ),
                ),
                if (c.manualBusy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Includes verified connections beyond the starting highway. GP = general-purpose lanes; EL = Express Lanes.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: c.manualBusy || c.entry == null || c.exit == null
                      ? null
                      : onCalculate,
                  child: const Text('Calculate this trip'),
                ),
                const SizedBox(height: 28),
                Card(
                  color: scheme.surfaceContainerLow,
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Start near you',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Use your location to suggest a nearby entry. Your coordinates stay on this device.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: c.gpsBusy ? null : () => c.useGps(choose),
                          icon: c.gpsBusy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.my_location),
                          label: Text(
                            c.gpsBusy
                                ? 'Finding your entry…'
                                : 'Use my location',
                          ),
                        ),
                        if (c.gpsStatus.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(c.gpsStatus),
                          ),
                        const SizedBox(height: 8),
                        ExpansionTile(
                          title: const Text('Direction needs movement'),
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.zero,
                          children: [
                            Text(
                              'GPS heading is used only when the device reports reliable movement. Otherwise, confirm your direction manually. If you are already in the lanes, choose your original entry.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (c.notice.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Material(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        title: Text(
                          c.notice,
                          style: TextStyle(color: scheme.onErrorContainer),
                        ),
                        trailing: IconButton(
                          tooltip: 'Dismiss notice',
                          onPressed: c.dismissNotice,
                          icon: Icon(
                            Icons.close,
                            color: scheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
