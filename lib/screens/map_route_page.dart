import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../formatting.dart';
import '../planner_controller.dart';
import '../pricing.dart';
import '../route_map.dart';
import '../widgets/trip_estimate.dart';

class MapRoutePage extends StatefulWidget {
  const MapRoutePage({
    super.key,
    required this.controller,
    required this.choose,
    required this.onManual,
    required this.onEdit,
  });
  final PlannerController controller;
  final ChooseRoute choose;
  final VoidCallback onManual;
  final VoidCallback onEdit;
  @override
  State<MapRoutePage> createState() => _MapRoutePageState();
}

class _MapRoutePageState extends State<MapRoutePage> {
  final sheet = DraggableScrollableController();
  final sideScroll = ScrollController();
  ScrollController? detailsScroll;
  double extent = .40;
  bool editingMap = false;
  Json? lastTrip;
  PlannerController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    lastTrip = c.trip;
  }

  @override
  void didUpdateWidget(covariant MapRoutePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(lastTrip, c.trip)) {
      lastTrip = c.trip;
      if (c.trip != null) {
        editingMap = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            if (detailsScroll?.hasClients ?? false) {
              detailsScroll!.jumpTo(0);
            }
            if (sideScroll.hasClients) {
              sideScroll.jumpTo(0);
            }
            expandTo(.72);
          }
        });
      }
    }
  }

  @override
  void dispose() {
    sheet.dispose();
    sideScroll.dispose();
    super.dispose();
  }

  void expandTo(double size) {
    if (!sheet.isAttached) return;
    final target = size.clamp(.18, .92).toDouble();
    if (MediaQuery.disableAnimationsOf(context)) {
      sheet.jumpTo(target);
    } else {
      sheet.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void chooseStop(bool entry) {
    setState(() => editingMap = true);
    c.setChoosingEntry(entry || c.mapEntryId == null);
    FocusManager.instance.primaryFocus?.unfocus();
    expandTo(.30);
  }

  Widget buildMap(double bottomPadding) => RouteMap(
    key: const ValueKey('planning-map'),
    ramps: c.mapRecords,
    onChoose: (records) => c.selectMap(records, widget.choose),
    entryId: c.mapEntryId,
    exitId: c.mapExitId,
    reachableIds: c.mapBusy
        ? const <String>{}
        : c.choosingEntry
        ? null
        : c.mapRoutes
              .expand((r) => (r['exits'] as List).map((e) => e['id'] as String))
              .toSet(),
    bottomPadding: bottomPadding,
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final sideBySide =
          bounds.maxWidth >= 800 ||
          (bounds.maxWidth >= 640 && bounds.maxHeight < 460);
      final colors = Theme.of(context).colorScheme;
      if (sideBySide) {
        return Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 0, 12),
                child: buildMap(0),
              ),
            ),
            SizedBox(
              width: 360,
              child: Material(
                color: colors.surface,
                child: ListView(
                  controller: sideScroll,
                  padding: const EdgeInsets.all(20),
                  children: details(draggable: false),
                ),
              ),
            ),
          ],
        );
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          buildMap(bounds.maxHeight * extent),
          NotificationListener<DraggableScrollableNotification>(
            onNotification: (notification) {
              if ((extent - notification.extent).abs() > .001) {
                setState(() => extent = notification.extent);
              }
              return false;
            },
            child: DraggableScrollableSheet(
              key: const ValueKey('trip-sheet'),
              controller: sheet,
              initialChildSize: .40,
              minChildSize: .18,
              maxChildSize: .92,
              snap: true,
              snapSizes: const [.18, .40, .72, .92],
              shouldCloseOnMinExtent: false,
              builder: (context, scroll) {
                detailsScroll = scroll;
                return Material(
                  color: colors.surfaceContainerLow,
                  elevation: 3,
                  clipBehavior: Clip.antiAlias,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: ListView(
                    controller: scroll,
                    padding: EdgeInsets.fromLTRB(
                      20,
                      0,
                      20,
                      math.max(20, MediaQuery.viewPaddingOf(context).bottom),
                    ),
                    children: details(draggable: true),
                  ),
                );
              },
            ),
          ),
        ],
      );
    },
  );

  List<Widget> details({required bool draggable}) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hasEstimate = c.trip != null && !editingMap;
    return [
      if (draggable)
        Semantics(
          label: 'Drag to expand trip details',
          child: Center(
            child: Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: colors.onSurfaceVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: hasEstimate
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.pricingBusy ? 'Checking toll…' : 'Trip estimate',
                        style: text.labelLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (c.pricingBusy)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: LinearProgressIndicator(),
                        )
                      else if (c.quote?['price'] is num)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              money(c.quote!['price']),
                              key: const ValueKey('estimate-amount'),
                              style: text.headlineLarge?.copyWith(
                                color: colors.primary,
                              ),
                            ),
                          ),
                        )
                      else
                        Text(
                          c.quote?['error'] ?? 'Estimate unavailable',
                          style: text.titleLarge,
                        ),
                    ],
                  )
                : Text(
                    c.mapBusy
                        ? 'Finding your route…'
                        : c.choosingEntry
                        ? 'Choose your entry'
                        : 'Choose your exit',
                    style: text.titleLarge,
                  ),
          ),
          if (c.mapEntryId != null)
            IconButton(
              tooltip: 'Clear trip',
              onPressed: () {
                setState(() => editingMap = false);
                c.clearTrip();
                expandTo(.40);
              },
              icon: const Icon(Icons.restart_alt),
            ),
          if (draggable)
            IconButton(
              tooltip: extent > .55
                  ? 'Collapse trip details'
                  : 'Expand trip details',
              onPressed: () => expandTo(extent > .55 ? .18 : .72),
              icon: Icon(
                extent > .55
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_up,
              ),
            ),
        ],
      ),
      if (!hasEstimate) ...[
        const SizedBox(height: 8),
        Text(
          c.choosingEntry
              ? 'Tap a ramp to start your trip.'
              : 'Tap a reachable exit on the map.',
          style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
      if (c.mapBusy)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: LinearProgressIndicator(),
        ),
      if (c.notice.isNotEmpty && !c.mapBusy)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Material(
            color: colors.errorContainer,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      c.notice,
                      style: text.bodyMedium?.copyWith(
                        color: colors.onErrorContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Dismiss notice',
                    onPressed: c.dismissNotice,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
        ),
      const SizedBox(height: 12),
      stop('A', 'Entry', c.mapOriginLabel ?? 'Choose a starting ramp', true),
      stop(
        'B',
        'Exit',
        c.trip?['exitLabel'] ?? 'Choose your destination',
        false,
      ),
      if (hasEstimate) ...[
        const SizedBox(height: 8),
        Text(
          '${roadNames[c.trip!['road']]} · ${c.trip!['dir']}',
          style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const Divider(height: 32),
        TripEstimate(controller: c, onEdit: widget.onEdit),
      ] else ...[
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: widget.onManual,
          icon: const Icon(Icons.edit_road_outlined),
          label: const Text('Choose route by road'),
        ),
        const SizedBox(height: 16),
        Text(
          'Drag with one finger. Pinch with two to zoom. Ramp positions are approximate.',
          style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    ];
  }

  Widget stop(String letter, String label, String value, bool entry) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: entry
            ? colors.primaryContainer
            : colors.tertiaryContainer,
        foregroundColor: entry
            ? colors.onPrimaryContainer
            : colors.onTertiaryContainer,
        child: Text(letter),
      ),
      title: Text(value),
      subtitle: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => chooseStop(entry),
    );
  }
}
