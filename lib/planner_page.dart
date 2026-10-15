import 'dart:async';

import 'package:flutter/material.dart';

import 'planner_controller.dart';
import 'pricing.dart';
import 'screens/manual_route_page.dart';
import 'screens/map_route_page.dart';
import 'screens/saved_trips_page.dart';
import 'widgets/route_picker.dart';
import 'widgets/source_sheet.dart';

class PlannerPage extends StatefulWidget {
  const PlannerPage({super.key, this.service});
  final PricingService? service;
  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> with WidgetsBindingObserver {
  late final PlannerController controller;
  int destination = 0;
  Json? lastTrip;
  bool active = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller = PlannerController(service: widget.service)
      ..addListener(_changed);
    unawaited(controller.initialize());
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      if (controller.trip != null && !identical(lastTrip, controller.trip)) {
        destination = 0;
      }
      lastTrip = controller.trip;
    });
    _visibility();
  }

  void _visibility() => controller.setVisibility(
    active: active,
    resultVisible: destination == 0 && controller.trip != null,
  );
  void navigate(int next) {
    setState(() => destination = next);
    _visibility();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    _visibility();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_changed);
    controller.dispose();
    super.dispose();
  }

  Future<Json?> choose(
    String title,
    List<Json> options,
    String Function(Json) label,
  ) => showRoutePicker(context, title, options, label);

  void calculate() {
    final c = controller;
    if (c.entry == null || c.exit == null || c.manualBusy) return;
    c.applyTrip({
      'road': c.road,
      'dir': c.direction,
      'entry': c.entry,
      'exit': c.exit,
      'entryLabel': c.entries.firstWhere((e) => e['id'] == c.entry)['label'],
      'exitLabel': c.exits.firstWhere((e) => e['id'] == c.exit)['label'],
    });
  }

  void edit() {
    controller.editTrip();
    navigate(1);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, bounds) {
        final expanded = bounds.maxWidth >= 840;
        final pages = controller.ready
            ? IndexedStack(
                index: destination,
                children: [
                  MapRoutePage(
                    controller: controller,
                    choose: choose,
                    onManual: () => navigate(1),
                    onEdit: edit,
                  ),
                  ManualRoutePage(
                    controller: controller,
                    choose: choose,
                    onCalculate: calculate,
                  ),
                  SavedTripsPage(
                    controller: controller,
                    onLoad: (trip) {
                      controller.applyTrip(trip);
                      navigate(0);
                    },
                    onPlan: () => navigate(1),
                  ),
                ],
              )
            : Center(
                child: controller.notice.isEmpty
                    ? const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(controller.notice),
                      ),
              );
        return PopScope(
          canPop: destination == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && destination != 0) {
              navigate(0);
            }
          },
          child: Scaffold(
            resizeToAvoidBottomInset: destination != 0,
            appBar: AppBar(
              leading: destination == 0
                  ? Icon(Icons.explore_outlined, color: colors.primary)
                  : null,
              title: Text(
                ['Nova Toll', 'Plan a route', 'Saved trips'][destination],
              ),
              actions: [
                IconButton(
                  tooltip: 'Sources and coverage',
                  onPressed: () => showSources(context),
                  icon: const Icon(Icons.info_outline),
                ),
                const SizedBox(width: 4),
              ],
            ),
            body: SafeArea(
              top: false,
              bottom: expanded,
              child: Row(
                children: [
                  if (expanded) ...[
                    NavigationRail(
                      selectedIndex: destination,
                      onDestinationSelected: navigate,
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.map_outlined),
                          selectedIcon: Icon(Icons.map),
                          label: Text('Map'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.route_outlined),
                          selectedIcon: Icon(Icons.route),
                          label: Text('Route'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.bookmark_border),
                          selectedIcon: Icon(Icons.bookmark),
                          label: Text('Saved'),
                        ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                  ],
                  Expanded(child: pages),
                ],
              ),
            ),
            bottomNavigationBar: expanded
                ? null
                : NavigationBar(
                    selectedIndex: destination,
                    onDestinationSelected: navigate,
                    destinations: const [
                      NavigationDestination(
                        key: ValueKey('tab-0'),
                        icon: Icon(Icons.map_outlined),
                        selectedIcon: Icon(Icons.map),
                        label: 'Map',
                      ),
                      NavigationDestination(
                        key: ValueKey('tab-1'),
                        icon: Icon(Icons.route_outlined),
                        selectedIcon: Icon(Icons.route),
                        label: 'Route',
                      ),
                      NavigationDestination(
                        key: ValueKey('tab-2'),
                        icon: Icon(Icons.bookmark_border),
                        selectedIcon: Icon(Icons.bookmark),
                        label: 'Saved',
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
